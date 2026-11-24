###############################################################################
#  trajectory_lcmm_external_validate — 发现集 JLCM 固定参数 → 外验库分类
#
#  对齐 Wang 2026：MIMIC 拟合 Jointlcmm 后，用同一参数在 eICU 上 predictClass。
#  禁止 smoke / 随机 / 开发表子集回退（用户 2026-11-18 确认强化）。
#
#  config$trajectory_lcmm_external_validate = list(
#    discovery_db = "mimic",
#    validate_cohort = "eICU",          # 仅文档；本块在外验库 worker 上运行
#    discovery_model_path = NULL,       # NULL → 自动找发现集 D01_jlcm_{Index}_models.RData
#    discovery_output_root = NULL,      # 指标根下 mimic/ 目录
#    index_vars = NULL,
#    id_column = NULL,
#    prefer_ng = NULL,                  # NULL → 用发现集 prefer/auto 选定 ng
#    require_predictClass = TRUE
#  )
#
#  亦兼容旧键 config$trajectory$lcmm_dev_model_path
###############################################################################

.tlcev_resolve_index <- function(ctx, bl) {
  ix <- bl$index_vars %||% ctx$config$trajectory_jlcm$index_vars %||%
    ctx$config$survival$index_var %||% character(0)
  as.character(ix)[1L]
}

.tlcev_index_dir_aliases <- function(by_index_root, Index) {
  # 裸名 / 【success】 / 【failed】（派发重命名后仍能找回发现集模型）
  unique(c(
    file.path(by_index_root, Index),
    file.path(by_index_root, paste0("\u3010success\u3011", Index)),
    file.path(by_index_root, paste0("\u3010failed\u3011", Index))
  ))
}

.tlcev_collect_model_candidates <- function(root, Index) {
  bn <- paste0("D01_jlcm_", Index, "_models.RData")
  out <- c(
    file.path(root, "data", bn),
    file.path(root, bn),
    file.path(root, "Models", bn),
    file.path(root, "Data", bn),
    # JLCM block 实际落盘：stepNN_trajectory_jlcm/Data/
    Sys.glob(file.path(root, "step*_trajectory_jlcm", "Data", bn)),
    Sys.glob(file.path(root, "step*_trajectory_jlcm", bn)),
    Sys.glob(file.path(root, "*", "Data", bn))
  )
  # 兜底：该库目录下递归找同名（深度有限，避免扫全盘）
  if (dir.exists(root)) {
    hit <- tryCatch(
      list.files(root, pattern = paste0("^", bn, "$"), recursive = TRUE, full.names = TRUE),
      error = function(e) character(0)
    )
    if (length(hit)) out <- c(out, hit)
  }
  unique(out[nzchar(out)])
}

.tlcev_find_model_file <- function(ctx, bl, Index) {
  cand <- character(0)
  if (!is.null(bl$discovery_model_path) && nzchar(bl$discovery_model_path))
    cand <- c(cand, bl$discovery_model_path)
  old <- ctx$config$trajectory$lcmm_dev_model_path %||% ""
  if (nzchar(old)) cand <- c(cand, old)

  disc <- tolower(as.character(bl$discovery_db %||% "mimic"))
  # 当前外验产出常在 by_index/<ix>/eicu；发现集在同级 mimic（或已打标目录）
  out_dir <- ctx$config$project$output_dir %||% "."
  root_out <- ctx$root_output_dir %||% out_dir
  by_index_guess <- c(
    dirname(dirname(out_dir)),           # .../by_index/<ix>/eicu → by_index
    dirname(dirname(root_out)),
    file.path(dirname(dirname(dirname(out_dir))), "by_index")
  )
  index_dirs <- character(0)
  for (bi in unique(by_index_guess[nzchar(by_index_guess)])) {
    index_dirs <- c(index_dirs, .tlcev_index_dir_aliases(bi, Index))
  }
  # worker 显式传入的发现集根（可能已是 .../mimic）
  roots <- c(
    bl$discovery_output_root %||% "",
    file.path(index_dirs, disc),
    file.path(dirname(out_dir), disc),
    file.path(dirname(root_out), disc),
    file.path(out_dir, "..", disc)
  )
  # 再扩：若 discovery_output_root 指向裸名 mimic 而实际在【failed】下
  disc_root <- bl$discovery_output_root %||% ""
  if (nzchar(disc_root)) {
    # .../by_index/NLPR/mimic → parent by_index
    maybe_ix <- basename(dirname(disc_root))
    maybe_bi <- dirname(dirname(disc_root))
    if (nzchar(maybe_ix) && nzchar(maybe_bi)) {
      roots <- c(roots, file.path(.tlcev_index_dir_aliases(maybe_bi, Index), disc))
    }
  }
  roots <- unique(normalizePath(roots[nzchar(roots)], winslash = "/", mustWork = FALSE))
  for (r in roots) {
    cand <- c(cand, .tlcev_collect_model_candidates(r, Index))
    tpl <- ctx$config$trajectory_jlcm$output_dir_template %||% ""
    if (nzchar(tpl)) {
      p <- gsub("\\{db\\}", disc, gsub("\\{Index\\}", Index, tpl, fixed = FALSE))
      cand <- c(cand, file.path(p, paste0("D01_jlcm_", Index, "_models.RData")))
    }
  }
  cand <- unique(cand[nzchar(cand) & file.exists(cand)])
  if (!length(cand)) return(NULL)
  # 优先 step*_trajectory_jlcm/Data（正式 JLCM 产出）
  prefer <- cand[grepl("trajectory_jlcm", cand, fixed = TRUE)]
  if (length(prefer)) return(prefer[[1L]])
  cand[[1L]]
}

.tlcev_pick_model <- function(models_list, prefer_ng = NULL) {
  if (inherits(models_list, "Jointlcmm")) return(list(model = models_list, ng = models_list$ng))
  if (is.list(models_list) && inherits(models_list$best, "Jointlcmm"))
    return(list(model = models_list$best, ng = models_list$best$ng))
  # named m2,m3,...
  keys <- names(models_list)
  if (is.null(keys)) keys <- character(0)
  mkeys <- grep("^m[0-9]+$", keys, value = TRUE)
  if (!length(mkeys) && is.list(models_list)) {
    # nested
    if (!is.null(models_list$models)) return(.tlcev_pick_model(models_list$models, prefer_ng))
  }
  ngs <- as.integer(sub("^m", "", mkeys))
  prefer_ng <- suppressWarnings(as.integer(prefer_ng)[1L])
  if (is.finite(prefer_ng) && paste0("m", prefer_ng) %in% mkeys) {
    m <- models_list[[paste0("m", prefer_ng)]]
    if (inherits(m, "Jointlcmm")) return(list(model = m, ng = prefer_ng))
    if (is.list(m) && inherits(m$best, "Jointlcmm"))
      return(list(model = m$best, ng = prefer_ng))
  }
  # 禁止默认 max ng（会把发现集 optimal=3 误用成 m6）
  # 回退顺序：optimal_ng 属性 → m2 → 最小可用 ng
  attr_ng <- suppressWarnings(as.integer(attr(models_list, "optimal_ng")[1L]))
  if (is.finite(attr_ng) && paste0("m", attr_ng) %in% mkeys) {
    m <- models_list[[paste0("m", attr_ng)]]
    if (inherits(m, "Jointlcmm")) return(list(model = m, ng = attr_ng))
  }
  for (g in sort(ngs, decreasing = FALSE)) {
    m <- models_list[[paste0("m", g)]]
    if (inherits(m, "Jointlcmm")) return(list(model = m, ng = g))
    if (is.list(m) && inherits(m$best, "Jointlcmm")) return(list(model = m$best, ng = g))
  }
  NULL
}

.tlcev_wide_to_long <- function(index_df, id_col, index_name, time_end = 28L) {
  day_cols <- paste0(index_name, "_", seq_len(time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("外验宽表缺少 ", index_name, "_* 日列", call. = FALSE)
  out <- lapply(day_cols, function(dc) {
    day <- as.integer(sub(paste0("^", index_name, "_"), "", dc))
    data.frame(
      id = as.character(index_df[[id_col]]),
      time_day = day,
      Value = suppressWarnings(as.numeric(index_df[[dc]])),
      stringsAsFactors = FALSE
    )
  })
  long <- do.call(rbind, out)
  long <- long[is.finite(long$Value), , drop = FALSE]
  names(long)[1L] <- id_col
  long
}

block_trajectory_lcmm_external_validate <- function(ctx, ...) {
  bl <- ctx$config$trajectory_lcmm_external_validate %||%
    ctx$config$trajectory %||% list()
  if (!requireNamespace("lcmm", quietly = TRUE))
    stop("trajectory_lcmm_external_validate: 需要 lcmm 包", call. = FALSE)
  # Jointlcmm 公式含 ns()；predictClass 求值时须能找到 splines::ns
  if (!requireNamespace("splines", quietly = TRUE))
    stop("trajectory_lcmm_external_validate: 需要 splines 包", call. = FALSE)
  suppressPackageStartupMessages(loadNamespace("splines"))
  if (!exists("ns", mode = "function", inherits = TRUE)) {
    ns <- splines::ns  # nolint: object_usage
    assign("ns", ns, envir = .GlobalEnv)
  }

  if (is.null(ctx$results$trajectory_lcmm_external) || !is.list(ctx$results$trajectory_lcmm_external))
    ctx$results$trajectory_lcmm_external <- list()

  Index <- .tlcev_resolve_index(ctx, bl)
  if (!nzchar(Index)) stop("trajectory_lcmm_external_validate: 未解析 Index", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "subject_id"
  model_file <- .tlcev_find_model_file(ctx, bl, Index)
  if (is.null(model_file)) {
    stop(
      "trajectory_lcmm_external_validate: 找不到发现集模型 D01_jlcm_", Index,
      "_models.RData（禁止 smoke 回退）。请先跑完 MIMIC discovery。",
      call. = FALSE
    )
  }

  e <- new.env(parent = emptyenv())
  load(model_file, envir = e)
  models_obj <- e$models_list_with_cov %||% e$models_list %||% NULL
  if (is.null(models_obj)) {
    stop("模型文件无 models_list_with_cov: ", model_file, call. = FALSE)
  }
  prefer_ng <- bl$prefer_ng %||% ctx$config$trajectory_jlcm$prefer_final_ng %||%
    ctx$results$trajectory_jlcm_selected_ng[[Index]] %||% NULL
  # 发现集落盘的 optimal_ng_*.txt（与 Table2 选类一致）优先于 max-ng 回退
  if (is.null(prefer_ng) || !is.finite(suppressWarnings(as.integer(prefer_ng)[1L]))) {
    opt_cands <- c(
      file.path(dirname(model_file), "Tables", "Summary", paste0("optimal_ng_", Index, ".txt")),
      file.path(dirname(dirname(model_file)), "Tables", "Summary", paste0("optimal_ng_", Index, ".txt")),
      file.path(dirname(model_file), paste0("optimal_ng_", Index, ".txt"))
    )
    # 常见：Data/D01_*.RData → 同级 ../Tables/Summary
    opt_cands <- c(
      opt_cands,
      file.path(dirname(dirname(model_file)), "Tables", "Summary", paste0("optimal_ng_", Index, ".txt")),
      file.path(dirname(dirname(dirname(model_file))), "Tables", "Summary", paste0("optimal_ng_", Index, ".txt"))
    )
    for (op in unique(opt_cands)) {
      if (!file.exists(op)) next
      og <- suppressWarnings(as.integer(trimws(readLines(op, warn = FALSE)[1L])))
      if (is.finite(og) && og >= 2L) {
        prefer_ng <- og
        cli::cli_alert_info("外验 prefer_ng 取自发现集 {.file {basename(op)}} = {og}")
        break
      }
    }
  }
  picked <- .tlcev_pick_model(models_obj, prefer_ng = prefer_ng)
  if (is.null(picked)) stop("无法从发现集文件提取 Jointlcmm 对象", call. = FALSE)
  dev_mod <- picked$model
  ng <- picked$ng

  # validation wide table
  tpl <- ctx$config$trajectory_jlcm$rawdata_path_template %||% NULL
  db_tag <- if (grepl("mimic", tolower(ctx$config$project$database %||% ""), fixed = TRUE)) "mimic" else "eicu"
  wide_path <- if (!is.null(tpl)) gsub("\\{Index\\}", Index, gsub("\\{db\\}", db_tag, tpl)) else NULL
  if (is.null(wide_path) || !file.exists(wide_path)) {
    stop("外验缺少纵向宽表: ", wide_path %||% "NULL", call. = FALSE)
  }
  e2 <- new.env(parent = emptyenv())
  load(wide_path, envir = e2)
  obj <- ctx$config$trajectory_jlcm$rawdata_obj %||% "index_df"
  index_df <- e2[[obj]]
  if (is.null(index_df)) stop("宽表对象缺失: ", obj, call. = FALSE)
  if (!id_col %in% names(index_df)) {
    if ("subject_id" %in% names(index_df)) id_col <- "subject_id"
    else if ("ID" %in% names(index_df)) {
      index_df$subject_id <- as.character(index_df$ID)
      id_col <- "subject_id"
    } else stop("宽表无 ID 列", call. = FALSE)
  }

  long <- .tlcev_wide_to_long(index_df, id_col, Index, time_end = as.integer(ctx$config$trajectory_jlcm$max_followup %||% 28L))
  d <- long
  d$time_day <- as.numeric(d$time_day)

  # 对齐发现集建模口径：Y 名 / subject 名 / 协变量 / 生存列（见 model$Names）
  nm <- tryCatch(dev_mod$Names, error = function(e) NULL)
  y_col <- as.character(nm$Yname %||% "scr_std")[1L]
  subj_col <- as.character(nm$ID %||% "subject_id_num")[1L]
  x_need <- as.character(nm$Xnames2 %||% character(0))
  t_surv <- as.character(nm$Tnames %||% c("surv_time", "surv_event"))
  mdata <- e$model_data_final

  # JLCM 块将 Value 直接 rename 为 scr_std（未再 scale）；外验同口径
  y_vec <- as.numeric(d$Value)

  # subject_id_num：外验 ID 映射到整数
  id_chr <- as.character(d[[id_col]])
  id_levels <- unique(id_chr)
  id_num <- match(id_chr, id_levels)

  newdata <- data.frame(
    time_day = d$time_day,
    stringsAsFactors = FALSE
  )
  newdata[[y_col]] <- y_vec
  newdata[[subj_col]] <- as.integer(id_num)
  newdata[[id_col]] <- id_chr

  # 合并基线协变量 + 生存（来自 imputed）；外验缺列用发现集 model_data 中位数填
  base <- ctx$data$imputed %||% ctx$data$cleaned
  cov_need <- unique(c(setdiff(x_need, "time_day"), t_surv))
  if (!is.null(base) && id_col %in% names(base)) {
    keep <- intersect(c(id_col, cov_need), names(base))
    b1 <- unique(base[, keep, drop = FALSE])
    if (!"surv_time" %in% names(b1)) {
      tv <- ctx$config$survival$time_var %||% "survival_time_28d"
      if (tv %in% names(base)) {
        b1$surv_time <- pmin(as.numeric(base[[tv]][match(b1[[id_col]], base[[id_col]])]), 28)
      }
    }
    if (!"surv_event" %in% names(b1)) {
      ev <- ctx$config$survival$event_var %||% "survival_28d"
      if (ev %in% names(base)) {
        raw <- base[[ev]][match(b1[[id_col]], base[[id_col]])]
        if (exists("pipeline_outcome_as_01", mode = "function"))
          b1$surv_event <- as.integer(pipeline_outcome_as_01(raw, ctx$config))
        else b1$surv_event <- as.integer(as.character(raw) %in% c("1", "Non-survivor"))
      }
    }
    newdata <- merge(newdata, b1, by = id_col, all.x = TRUE)
  }
  # 发现集中位数回填（外验库缺 LD/PT 等成分时）
  if (is.data.frame(mdata)) {
    for (cv in setdiff(x_need, "time_day")) {
      if (!cv %in% names(newdata) || all(!is.finite(as.numeric(newdata[[cv]])))) {
        if (cv %in% names(mdata) && is.numeric(mdata[[cv]])) {
          med <- stats::median(as.numeric(mdata[[cv]]), na.rm = TRUE)
          newdata[[cv]] <- med
          cli::cli_alert_warning(
            "外验缺协变量 {cv}，用发现集中位数 {round(med, 4)} 填补"
          )
        }
      } else {
        # 部分 NA 也填
        v <- as.numeric(newdata[[cv]])
        if (any(!is.finite(v)) && cv %in% names(mdata) && is.numeric(mdata[[cv]])) {
          med <- stats::median(as.numeric(mdata[[cv]]), na.rm = TRUE)
          v[!is.finite(v)] <- med
          newdata[[cv]] <- v
        }
      }
    }
  }
  miss_x <- setdiff(c(x_need, t_surv, y_col, subj_col), names(newdata))
  if (length(miss_x)) {
    stop(
      "predictClass newdata 缺列: ", paste(miss_x, collapse = ", "),
      "（须与发现集 Jointlcmm Names 一致）",
      call. = FALSE
    )
  }
  # subject 列必须数值
  newdata[[subj_col]] <- as.integer(newdata[[subj_col]])

  cli::cli_alert_info(
    "外验 predictClass: model={basename(model_file)} ng={ng}; Y={y_col}; subject={subj_col}; n={nrow(newdata)}"
  )

  .pc_args <- names(formals(lcmm::predictClass))
  .pc_call <- list(model = dev_mod, newdata = newdata)
  # subject= 列名（字符）；列值须为 numeric
  if ("subject" %in% .pc_args) .pc_call$subject <- subj_col
  if ("var.time" %in% .pc_args) .pc_call$var.time <- "time_day"
  pred <- tryCatch(
    do.call(lcmm::predictClass, .pc_call),
    error = function(err) {
      stop(
        "predictClass 失败（禁止回退）: ", conditionMessage(err),
        " | model=", basename(model_file), " ng=", ng,
        call. = FALSE
      )
    }
  )

  # pred usually has class / subject；禁止 pred$subject（会部分匹配 subject_id_num）
  cls <- pred[["class"]] %||% pred[["class.pred"]] %||% NULL
  sid <- pred[[id_col]] %||% pred[["subject"]] %||% pred[["id"]] %||% NULL
  if (is.null(cls)) stop("predictClass 未返回 class 列", call. = FALSE)
  # 始终用 subject_id_num → 原始 id 映射（id_levels 与建模时 match 同源）
  if (!is.null(pred[["subject_id_num"]])) {
    sid <- id_levels[as.integer(pred[["subject_id_num"]])]
  } else if (is.null(sid)) {
    stop("predictClass 未返回个体 ID", call. = FALSE)
  }
  assign_df <- data.frame(
    id = as.character(sid),
    trajectory_class = as.integer(cls),
    max_prob = {
      # 禁止 pred$prob 部分匹配 probYT*；取各类后验最大
      py <- grep("^probYT", names(pred), value = TRUE)
      if (length(py)) {
        as.numeric(apply(as.data.frame(pred)[py], 1L, max, na.rm = TRUE))
      } else {
        NA_real_
      }
    },
    cohort = ctx$config$project$database %||% "validation",
    ng = as.integer(ng),
    discovery_model = basename(model_file),
    stringsAsFactors = FALSE
  )
  names(assign_df)[1L] <- id_col
  assign_df <- assign_df[!duplicated(assign_df[[id_col]]), , drop = FALSE]

  out <- file.path(ctx$output_dir_tables %||% file.path(ctx$config$project$output_dir, "Tables"), "LCMM")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(assign_df, file.path(out, paste0("Table_LCMM_Assignment_External_", Index, ".csv")),
                   row.names = FALSE)

  base <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.null(base) && id_col %in% names(base)) {
    sub <- assign_df[, c(id_col, "trajectory_class")]
    names(sub)[2L] <- paste0("trajectory_class_", Index)
    base[[id_col]] <- as.character(base[[id_col]])
    base <- merge(base, sub, by = id_col, all.x = TRUE)
    base$trajectory_class <- base[[paste0("trajectory_class_", Index)]]
    ctx$data$imputed <- base
    ctx$data$cleaned <- base
  }

  ctx$results$trajectory_lcmm_external[[Index]] <- list(
    n = nrow(assign_df),
    ng = ng,
    model_file = model_file,
    assign = assign_df
  )
  # also expose class for downstream blocks expecting jlcm assign
  if (is.null(ctx$results$trajectory_jlcm_class)) ctx$results$trajectory_jlcm_class <- list()
  ctx$results$trajectory_jlcm_class[[Index]] <- assign_df

  cli::cli_alert_success(
    "外验 predictClass 完成 [{Index}]: n={nrow(assign_df)}, ng={ng}, model={basename(model_file)}"
  )
  ctx
}

register_block(
  "trajectory_lcmm_external_validate",
  block_trajectory_lcmm_external_validate,
  "JLCM 发现集固定参数外验（predictClass，无 smoke）"
)
