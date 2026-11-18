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

.tlcev_find_model_file <- function(ctx, bl, Index) {
  cand <- character(0)
  if (!is.null(bl$discovery_model_path) && nzchar(bl$discovery_model_path))
    cand <- c(cand, bl$discovery_model_path)
  old <- ctx$config$trajectory$lcmm_dev_model_path %||% ""
  if (nzchar(old)) cand <- c(cand, old)

  disc <- tolower(as.character(bl$discovery_db %||% "mimic"))
  roots <- c(
    bl$discovery_output_root %||% "",
    file.path(dirname(ctx$config$project$output_dir %||% "."), disc),
    file.path(ctx$root_output_dir %||% dirname(ctx$config$project$output_dir %||% "."), disc),
    file.path(ctx$config$project$output_dir %||% ".", "..", disc)
  )
  roots <- unique(normalizePath(roots[nzchar(roots)], winslash = "/", mustWork = FALSE))
  for (r in roots) {
    cand <- c(
      cand,
      file.path(r, "data", paste0("D01_jlcm_", Index, "_models.RData")),
      file.path(r, paste0("D01_jlcm_", Index, "_models.RData")),
      file.path(r, "Models", paste0("D01_jlcm_", Index, "_models.RData"))
    )
    # also search jlcm output_dir_template
    tpl <- ctx$config$trajectory_jlcm$output_dir_template %||% ""
    if (nzchar(tpl)) {
      p <- gsub("\\{db\\}", disc, tpl)
      cand <- c(cand, file.path(p, paste0("D01_jlcm_", Index, "_models.RData")))
    }
  }
  cand <- unique(cand[nzchar(cand) & file.exists(cand)])
  if (!length(cand)) return(NULL)
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
  if (!is.null(prefer_ng) && length(prefer_ng) && paste0("m", prefer_ng) %in% mkeys) {
    m <- models_list[[paste0("m", prefer_ng)]]
    if (inherits(m, "Jointlcmm")) return(list(model = m, ng = as.integer(prefer_ng)))
    if (is.list(m) && inherits(m$best, "Jointlcmm"))
      return(list(model = m$best, ng = as.integer(prefer_ng)))
  }
  # pick max ng available with Jointlcmm
  for (g in sort(ngs, decreasing = TRUE)) {
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
  # Jointlcmm predictClass typically needs subject numeric + same var names as train
  # Use model_data_final colnames if available
  mdata <- e$model_data_final
  value_col <- "Y"
  time_col <- "time_day"
  if (is.data.frame(mdata)) {
    # heuristic: response often last continuous trajectory var
    if ("Y" %in% names(mdata)) value_col <- "Y"
    else if ("Value" %in% names(mdata)) value_col <- "Value"
    if ("time_day" %in% names(mdata)) time_col <- "time_day"
    else if ("Time" %in% names(mdata)) time_col <- "Time"
  }
  newdata <- data.frame(
    id = d[[id_col]],
    time_day = d$time_day,
    Y = d$Value,
    stringsAsFactors = FALSE
  )
  names(newdata)[1L] <- id_col
  if (!identical(value_col, "Y")) names(newdata)[names(newdata) == "Y"] <- value_col
  if (!identical(time_col, "time_day")) names(newdata)[names(newdata) == "time_day"] <- time_col

  pred <- tryCatch(
    lcmm::predictClass(dev_mod, newdata = newdata, var.time = time_col),
    error = function(err) {
      stop(
        "predictClass 失败（禁止回退）: ", conditionMessage(err),
        " | model=", basename(model_file), " ng=", ng,
        call. = FALSE
      )
    }
  )

  # pred usually has class / subject
  cls <- pred$class %||% pred$class.pred %||% NULL
  sid <- pred[[id_col]] %||% pred$subject %||% pred$id %||% NULL
  if (is.null(cls)) stop("predictClass 未返回 class 列", call. = FALSE)
  if (is.null(sid)) {
    # subject_id_num mapping
    if (!is.null(pred$subject_id_num)) {
      u <- unique(newdata[[id_col]])
      sid <- u[as.integer(pred$subject_id_num)]
    } else {
      stop("predictClass 未返回个体 ID", call. = FALSE)
    }
  }
  assign_df <- data.frame(
    id = as.character(sid),
    trajectory_class = as.integer(cls),
    max_prob = if (!is.null(pred$prob)) as.numeric(pred$prob) else
      if (!is.null(pred$pprob)) as.numeric(pred$pprob) else NA_real_,
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
