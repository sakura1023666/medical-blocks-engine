###############################################################################
#  trajectory_survival_utils.R — 轨迹预后块共用生存/协变量工具
###############################################################################

trajectory_coerce_event01 <- function(x) {
  if (is.null(x)) return(integer(0))
  if (is.numeric(x) || is.integer(x)) {
    xi <- as.integer(x)
    if (all(xi %in% c(0L, 1L, NA), na.rm = TRUE)) return(xi)
  }
  xs <- as.character(x)
  dplyr::case_when(
    xs %in% c("1", "Non-survivor", "Dead", "dead", "DEAD", "Yes", "TRUE", "T") ~ 1L,
    xs %in% c("0", "Survivor", "Alive", "alive", "ALIVE", "No", "FALSE", "F") ~ 0L,
    TRUE ~ suppressWarnings(as.integer(xs))
  )
}

trajectory_unwrap_jointlcmm <- function(m) {
  if (is.null(m) || !is.list(m)) return(NULL)
  if (inherits(m, "Jointlcmm")) return(m)
  if (!is.null(m$best) && inherits(m$best, "Jointlcmm")) return(m$best)
  if (!is.null(m$ng)) return(m)
  NULL
}

trajectory_jlcm_cov_cols <- function(jlcm_entry, model_obj = NULL) {
  cov <- as.character(jlcm_entry$covariate_vars_used %||% character(0))
  if (length(cov)) return(cov)
  m <- trajectory_unwrap_jointlcmm(model_obj)
  if (!is.null(m) && length(m$Xnames)) {
    return(setdiff(as.character(m$Xnames), c("time_day", "(Intercept)")))
  }
  character(0)
}

# 与 Fig2A.R / Fig2B.R / Fig3.R 一致：当 ng==2 且 Class 1 为多数类时，交换 Class1/Class2
# 标签（让 Class 2 成为人数多、预后好的低风险类），返回“旧类别 -> 新类别”的整数映射。
# 其它情况恒等映射。任何 block 用相同规则即可保证全论文类别标签一致。
trajectory_class_swap_map <- function(class_vec) {
  cl <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(class_vec))))
  ux <- sort(unique(cl[!is.na(cl)]))
  if (length(ux) == 2L && all(ux == c(1L, 2L))) {
    tab <- table(cl)
    if (length(tab) && names(which.max(tab))[1] == "1") {
      return(stats::setNames(c(2L, 1L), c("1", "2")))
    }
  }
  stats::setNames(as.integer(ux), as.character(ux))
}

# 对整数/字符类别向量应用交换映射，返回整数向量（无法映射的保持原值）
trajectory_apply_class_swap <- function(class_vec, swap_map) {
  cl <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(class_vec))))
  key <- as.character(cl)
  out <- swap_map[key]
  out <- ifelse(is.na(out), cl, as.integer(out))
  as.integer(out)
}

#' 从 JLCM 结果解析最优潜类别数 ng（供画图/动态预测/卡方等下游块共用）
trajectory_resolve_optimal_ng <- function(ctx, Index = NULL, cfg = NULL, fallback = 2L) {
  if (!is.null(Index) && nzchar(as.character(Index)[1L])) {
    ng_ix <- ctx$results[[paste0("trajectory_optimal_ng_", Index)]]
    if (!is.null(ng_ix)) {
      ng_ix <- suppressWarnings(as.integer(ng_ix)[1L])
      if (is.finite(ng_ix) && ng_ix >= 1L) return(ng_ix)
    }
  }
  ng <- ctx$results$trajectory_optimal_ng
  if (!is.null(ng)) {
    ng <- suppressWarnings(as.integer(ng)[1L])
    if (is.finite(ng) && ng >= 1L) return(ng)
  }
  jlcm <- (cfg$trajectory_jlcm %||% list())
  if (!isTRUE(jlcm$auto_select_class_ng %||% FALSE)) {
    ng_cfg <- suppressWarnings(as.integer(
      jlcm$assign_class_ng %||% jlcm$prefer_final_ng %||% NA_integer_
    )[1L])
    if (is.finite(ng_cfg) && ng_cfg >= 1L) return(ng_cfg)
  }
  fb <- suppressWarnings(as.integer(fallback)[1L])
  if (is.finite(fb) && fb >= 1L) fb else 2L
}

#' 解析 class_for_plot / class_for_test / jlcm_ng 等：NULL 或 "auto" → JLCM 最优 ng
trajectory_resolve_class_ng_spec <- function(ctx, Index, cfg, bl_cfg,
                                             field = "class_for_plot",
                                             fallback = 2L) {
  raw <- bl_cfg[[field]]
  if (length(raw) == 1L && is.character(raw) && tolower(trimws(raw)) == "auto") {
    raw <- NULL
  }
  if (!is.null(raw) && length(raw)) {
    out <- suppressWarnings(as.integer(raw))
    out <- out[is.finite(out) & out >= 1L]
    if (length(out)) return(unique(out))
  }
  use_opt <- bl_cfg$use_optimal_class_ng
  if (is.na(use_opt)) {
    use_opt <- isTRUE((cfg$trajectory_jlcm %||% list())$auto_select_class_ng %||% FALSE)
  }
  if (isTRUE(use_opt)) {
    return(trajectory_resolve_optimal_ng(ctx, Index, cfg, fallback = fallback))
  }
  alt <- bl_cfg$class_range %||% (cfg$trajectory_jlcm %||% list())$class_range
  if (!is.null(alt) && length(alt)) {
    out <- suppressWarnings(as.integer(alt))
    out <- out[is.finite(out) & out >= 1L]
    if (length(out)) return(unique(out))
  }
  stop(
    field, " 未配置且无法从 JLCM 最优类别解析（请先运行 trajectory_jlcm，",
    "或设置 ", field, " / use_optimal_class_ng=FALSE）。",
    call. = FALSE
  )
}

# 生命体征 / 血压列：字符型 → 数值（column_mapping 关闭时 imputation 前仍需执行）
trajectory_coerce_vital_numeric <- function(data) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  cols <- c(
    "SBP", "MAP", "DBP", "HR", "RR", "SpO2", "Temperature",
    "Weight", "Height", "BMI",
    "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM",
    "Nbps", "Nbpd", "Nbpm", "GCS", "APS", "APACHE", "SOFA"
  )
  for (cn in intersect(cols, names(data))) {
    x <- data[[cn]]
    if (is.character(x) || is.factor(x)) {
      data[[cn]] <- suppressWarnings(as.numeric(as.character(x)))
    }
  }
  data
}

# index block 公式用标准列名；eICU/MIMIC 原始名做别名拷贝
trajectory_index_column_aliases <- function(data) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  alias <- list(
    BUN            = c("UreaNitrogen", "BUN"),
    Platelet_Count = c("PlateletCount", "Platelet_Count"),
    Neutrophil_Count = c("Neutrophil_Count", "Neutrophils"),
    Lymphocytes    = c("Lymphocytes", "Lymphocyte"),
    Albumin        = c("Albumin"),
    AST            = c("AST"),
    ALT            = c("ALT"),
    LD             = c("LD", "LDH")
  )
  for (std in names(alias)) {
    if (std %in% names(data)) next
    src <- intersect(alias[[std]], names(data))[1]
    if (!is.na(src) && nzchar(src)) data[[std]] <- suppressWarnings(as.numeric(data[[src]]))
  }
  data
}

# 从 12_{Index}.RData 宽表合并 day-1 基线指标值（如 NLR_1 → NLR）
trajectory_merge_wide_baseline_index <- function(data, rdata_path, index_name,
                                               id_col = "subject_id", day = 1L) {
  if (is.null(data) || !file.exists(rdata_path)) return(data)
  e <- new.env()
  tryCatch(load(rdata_path, envir = e), error = function(err) return(data))
  onm <- ls(e)[1]
  if (!length(onm)) return(data)
  wide <- get(onm, envir = e)
  col_day <- paste0(index_name, "_", day)
  if (!id_col %in% names(wide) || !col_day %in% names(wide)) return(data)
  tab <- wide[, c(id_col, col_day), drop = FALSE]
  names(tab) <- c(id_col, index_name)
  tab[[id_col]] <- as.character(tab[[id_col]])
  tab[[index_name]] <- suppressWarnings(as.numeric(tab[[index_name]]))
  out <- data
  out[[id_col]] <- as.character(out[[id_col]])
  if (index_name %in% names(out)) out[[index_name]] <- NULL
  dplyr::left_join(out, tab, by = id_col)
}

trajectory_jlcm_cov_grid <- function(data, cov_cols, time_var = "time_day",
                                     cycle = 28L, n = 100L) {
  newtime <- seq(0, cycle, length.out = as.integer(n))
  out <- list()
  out[[time_var]] <- newtime
  for (vn in as.character(cov_cols)) {
    if (!vn %in% names(data)) next
    val <- suppressWarnings(mean(as.numeric(data[[vn]]), na.rm = TRUE))
    if (!is.finite(val)) next
    out[[vn]] <- rep(val, length(newtime))
  }
  as.data.frame(out)
}

# ── JLCM survival 协变量筛选（连续型 + 单因素 P 排序 + 上限）────────────────
trajectory_is_continuous_col <- function(x, min_unique = 3L) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(FALSE)
  if (is.numeric(x) || is.integer(x)) {
    ux <- unique(x[!is.na(x) & is.finite(x)])
    return(length(ux) >= min_unique)
  }
  nx <- suppressWarnings(as.numeric(as.character(x)))
  ux <- unique(nx[!is.na(nx) & is.finite(nx)])
  length(ux) >= min_unique
}

trajectory_rank_covariates_by_univar <- function(vars, ctx) {
  univar <- ctx$results$univar_coef
  if (is.null(univar) || !is.data.frame(univar) || !"P" %in% names(univar)) return(vars)
  p_map <- stats::setNames(as.numeric(univar$P), as.character(univar$Variable))
  scores <- vapply(vars, function(v) {
    if (v %in% names(p_map)) return(p_map[[v]])
    hits <- p_map[startsWith(names(p_map), v)]
    if (length(hits)) min(hits, na.rm = TRUE) else NA_real_
  }, numeric(1))
  vars[order(ifelse(is.finite(scores), scores, Inf), vars)]
}

trajectory_select_survival_covariates <- function(d, candidates, ctx, cfg) {
  bl_cfg <- cfg$trajectory_jlcm %||% cfg
  max_n <- suppressWarnings(as.integer(bl_cfg$survival_covariate_max %||% 5L)[1L])
  if (!is.finite(max_n) || max_n < 1L) max_n <- 5L
  continuous_only <- isTRUE(bl_cfg$survival_covariate_continuous_only %||% TRUE)

  candidates <- unique(as.character(candidates))
  candidates <- candidates[nzchar(candidates)]
  if (is.data.frame(d)) candidates <- intersect(candidates, names(d))

  dropped_non_cont <- character(0)
  cont_vars <- character(0)
  for (v in candidates) {
    if (continuous_only && is.data.frame(d) && v %in% names(d) &&
        !trajectory_is_continuous_col(d[[v]])) {
      dropped_non_cont <- c(dropped_non_cont, v)
      next
    }
    cont_vars <- c(cont_vars, v)
  }

  cont_vars <- trajectory_rank_covariates_by_univar(cont_vars, ctx)
  dropped_extra <- character(0)
  if (length(cont_vars) > max_n) {
    dropped_extra <- cont_vars[(max_n + 1L):length(cont_vars)]
    cont_vars <- cont_vars[seq_len(max_n)]
  }

  if (is.data.frame(d) && length(cont_vars)) {
    for (v in cont_vars) {
      if (!v %in% names(d)) next
      x <- d[[v]]
      if (!is.numeric(x) && !is.integer(x)) {
        d[[v]] <- suppressWarnings(as.numeric(as.character(x)))
      }
    }
  }

  list(
    data = d,
    vars = cont_vars,
    dropped_non_continuous = dropped_non_cont,
    dropped_extra = dropped_extra,
    max_n = max_n
  )
}

trajectory_find_model2_factors_file <- function(db_output_dir) {
  if (!dir.exists(db_output_dir)) return(NA_character_)
  cands <- c(
    file.path(db_output_dir, "step12_multicollinearity_final", "Model2Factors.txt"),
    file.path(db_output_dir, "step11_multicollinearity_final", "Model2Factors.txt"),
    file.path(db_output_dir, "Model2Factors.txt")
  )
  hit <- cands[file.exists(cands)][1L]
  if (!is.na(hit)) return(hit)
  found <- list.files(db_output_dir, pattern = "Model2Factors\\.txt$",
                      recursive = TRUE, full.names = TRUE)
  if (!length(found)) return(NA_character_)
  found[which.max(file.info(found)$mtime)]
}

trajectory_read_db_model2_factors <- function(db_output_dir) {
  fp <- trajectory_find_model2_factors_file(db_output_dir)
  if (is.na(fp)) return(character(0))
  unique(trimws(readLines(fp, warn = FALSE)))
}

#' 双库：取各库 VIF final 的 Model2Factors 交集，再按主库单因素 P 排序截断至 survival_covariate_max
trajectory_dual_db_select_shared_jlcm_covariates <- function(config_ix, ix,
                                                             db_seq = c("eicu", "mimic"),
                                                             root = NULL,
                                                             primary_db = NULL) {
  if (!exists("trajectory_batch_index_output_dir", mode = "function")) {
    stop("trajectory_dual_db_select_shared_jlcm_covariates: 需要 trajectory_prognosis_batch_runner.R",
         call. = FALSE)
  }
  root <- root %||% config_ix$project$root %||% getwd()
  base_ix <- trajectory_batch_index_output_dir(config_ix, ix)
  db_seq <- as.character(db_seq)
  primary_db <- as.character(primary_db %||% db_seq[[1L]])[1L]

  m2_by_db <- stats::setNames(
    lapply(db_seq, function(db) trajectory_read_db_model2_factors(file.path(base_ix, db))),
    db_seq
  )
  empty <- names(m2_by_db)[vapply(m2_by_db, length, 0L) == 0L]
  if (length(empty)) {
    stop(
      "双库 JLCM 协变量对齐失败：以下库无 Model2Factors — ",
      paste(empty, collapse = ", "),
      call. = FALSE
    )
  }

  common <- Reduce(intersect, m2_by_db)
  if (!length(common)) {
    stop("双库 Model2Factors 交集为空，无法对齐 JLCM survival 协变量。", call. = FALSE)
  }

  if (!exists("study_batch_load_checkpoint_ctx", mode = "function")) {
    source(file.path(root, "R/study_batch_runner.R"), local = FALSE)
  }
  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, primary_db)
  ctx <- study_batch_load_checkpoint_ctx(ck_dir, "multicollinearity_final")
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped

  res <- trajectory_select_survival_covariates(
    data, common, ctx, list(trajectory_jlcm = config_ix$trajectory_jlcm %||% list())
  )
  if (!length(res$vars)) {
    stop("双库共有协变量经连续型/上限筛选后为空。", call. = FALSE)
  }

  cli::cli_alert_success(
    "双库 JLCM 共有 survival 协变量 ({length(res$vars)}): {paste(res$vars, collapse = ', ')}"
  )
  cli::cli_alert_info(
    "各库 final 变量数: {paste(sprintf('%s=%d', names(m2_by_db), vapply(m2_by_db, length, 0L)), collapse = ', ')}；交集 {length(common)} 个"
  )
  if (length(res$dropped_extra)) {
    cli::cli_alert_info(
      "  交集内未纳入（>{res$max_n}）: {paste(head(res$dropped_extra, 8), collapse = ', ')}"
    )
  }
  res$vars
}

trajectory_dual_db_write_shared_jlcm_covariates <- function(config_ix, ix, cov_vars) {
  if (!exists("trajectory_batch_index_output_dir", mode = "function")) return(invisible(NULL))
  cov_vars <- unique(as.character(cov_vars)[nzchar(as.character(cov_vars))])
  summary_dir <- file.path(trajectory_batch_index_output_dir(config_ix, ix), "Tables", "Summary")
  dir.create(summary_dir, recursive = TRUE, showWarnings = FALSE)
  fp <- file.path(summary_dir, sprintf("JLCM_shared_survival_covariates_%s.txt", ix))
  lines <- c(
    sprintf("# JLCM shared survival covariates (dual-db intersection) — %s", ix),
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    cov_vars
  )
  writeLines(lines, fp)
  cli::cli_alert_success("双库共有 JLCM 协变量已写入: {.file {basename(fp)}}")
  invisible(fp)
}

#' JLCM 回写的潜类别列：不得进入 Table1 / UV / MV / VIF（按类分层表已用 class 作 by）
trajectory_class_column_names <- function(data_or_names) {
  nms <- if (is.data.frame(data_or_names)) names(data_or_names) else as.character(data_or_names)
  nms <- nms[nzchar(nms)]
  nms[grepl("^trajectory_class(\\b|_)", nms, ignore.case = TRUE) |
        grepl("^trajectory_class$", nms, ignore.case = TRUE)]
}

#' 轨迹批量：除当前 Index 外应排除的复合指标名（Table1 / UV / MV / VIF）
trajectory_batch_other_index_vars <- function(cfg, ix = NULL) {
  cfg <- cfg %||% list()
  ix <- as.character(ix %||% pipeline_index_exposure_var(cfg))[1L]
  all_ix <- character(0)
  if (exists("trajectory_batch_resolve_index_vars", mode = "function")) {
    all_ix <- tryCatch(trajectory_batch_resolve_index_vars(cfg), error = function(e) character(0))
  }
  if (!length(all_ix) && exists(".composite_index_vars_dual_safe", inherits = TRUE)) {
    all_ix <- get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% character(0)
  }
  if (!length(all_ix) && exists(".composite_index_vars", inherits = TRUE)) {
    all_ix <- get0(".composite_index_vars", inherits = TRUE) %||% character(0)
  }
  setdiff(unique(as.character(all_ix)[nzchar(as.character(all_ix))]), ix)
}

#' 合并 day-1 暴露指标后，仅保留有有效暴露值的受试者（与轨迹图/JLCM 人数对齐）
trajectory_filter_to_index_cohort <- function(data, index_name, id_col = "subject_id") {
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) return(data)
  index_name <- as.character(index_name)[1L]
  if (!nzchar(index_name) || !index_name %in% names(data)) return(data)
  idx <- suppressWarnings(as.numeric(data[[index_name]]))
  keep <- is.finite(idx)
  if (!any(keep)) return(data)
  out <- data[keep, , drop = FALSE]
  if (nrow(out) < nrow(data) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "trajectory_filter_to_index_cohort [{index_name}]: {nrow(data)} -> {nrow(out)} 例"
    )
  }
  out
}

#' 对 ctx 各数据槽应用暴露指标队列过滤
trajectory_apply_index_cohort_to_ctx <- function(ctx, index_name = NULL, id_col = NULL) {
  if (is.null(ctx) || !is.list(ctx)) return(ctx)
  cfg <- ctx$config %||% list()
  ix <- as.character(index_name %||% pipeline_index_exposure_var(cfg))[1L]
  if (!nzchar(ix)) return(ctx)
  id_col <- id_col %||% cfg$data$id_column %||% "subject_id"
  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]])) next
    ctx$data[[slot]] <- trajectory_filter_to_index_cohort(ctx$data[[slot]], ix, id_col)
  }
  ctx
}
