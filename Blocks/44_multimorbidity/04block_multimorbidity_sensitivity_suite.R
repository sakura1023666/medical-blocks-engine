###############################################################################
#  multimorbidity_sensitivity_suite — 文献敏感性：去低体重 + 20% jackknife 重聚
###############################################################################

block_multimorbidity_sensitivity_suite <- function(ctx, ...) {
  mm <- ctx$config$multimorbidity %||% list()
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_sensitivity_suite: 无数据", call. = FALSE)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  bmi_col <- as.character(mm$bmi_col %||% "BMI")[1L]
  rows <- list()

  # (1) 剔除 BMI < 18.5 后重跑四分类 GEE（若可）
  if (bmi_col %in% names(data) && requireNamespace("geepack", quietly = TRUE)) {
    suppressPackageStartupMessages(library(geepack))
    d1 <- data[is.na(data[[bmi_col]]) | as.numeric(data[[bmi_col]]) >= 18.5, , drop = FALSE]
    cat_col <- as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
    out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
    time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
    if (all(c(cat_col, out_col, time_col, id_col) %in% names(d1)) && nrow(d1) >= 30L) {
      d1[[cat_col]] <- factor(as.character(d1[[cat_col]]))
      form <- stats::as.formula(paste(out_col, "~", cat_col, "+", time_col))
      fit <- tryCatch(
        geepack::geeglm(form, data = d1, id = d1[[id_col]], family = gaussian(), corstr = "exchangeable"),
        error = function(e) NULL
      )
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        rows[[length(rows) + 1L]] <- data.frame(
          spec = "Exclude_BMI_lt_18.5", term = rownames(sm),
          beta = sm[, "Estimate"], p = sm[, "Pr(>|W|)"], n = nrow(d1),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  # (2) 随机保留 80% ID，重跑 kmeans 簇数稳定性（CH 最优 k 与主分析比较）
  cl_main <- ctx$results$multimorbidity_kml3d$n_clusters %||% NA_integer_
  seed <- as.integer(mm$kml3d_seed %||% 20260331L)[1L]
  set.seed(seed + 791L)
  ids <- unique(as.character(data[[id_col]]))
  keep_ids <- sample(ids, size = max(2L, floor(0.8 * length(ids))))
  d2 <- data[as.character(data[[id_col]]) %in% keep_ids, , drop = FALSE]
  # 轻量：若已有轨迹矩阵所需列，调用同一 block 函数在临时 ctx
  ctx2 <- ctx
  ctx2$data$imputed <- d2
  ctx2$data$cleaned <- d2
  ctx2$config$project <- ctx$config$project %||% list()
  ctx2$config$project$output_dir <- file.path(out_dir, "_sens_jackknife80")
  k_ok <- FALSE
  k_jk <- NA_integer_
  if (exists("block_multimorbidity_kml3d_trajectory", mode = "function")) {
    ctx2 <- tryCatch(block_multimorbidity_kml3d_trajectory(ctx2), error = function(e) {
      cli::cli_alert_warning("jackknife kml3d: {e$message}")
      ctx2
    })
    k_jk <- ctx2$results$multimorbidity_kml3d$n_clusters %||% NA_integer_
    k_ok <- is.finite(k_jk)
  }
  rows[[length(rows) + 1L]] <- data.frame(
    spec = "Jackknife_keep_80pct_kml3d",
    term = "best_k",
    beta = as.numeric(k_jk %||% NA_real_),
    p = NA_real_,
    n = length(keep_ids),
    stringsAsFactors = FALSE
  )
  rows[[length(rows) + 1L]] <- data.frame(
    spec = "Jackknife_vs_main_k",
    term = "k_match",
    beta = as.numeric(isTRUE(identical(as.integer(k_jk), as.integer(cl_main)))),
    p = NA_real_,
    n = length(keep_ids),
    stringsAsFactors = FALSE
  )

  # 附加：AR1 相关结构（次要）
  if (isTRUE(bl$sensitivity_include_ar1 %||% TRUE) && requireNamespace("geepack", quietly = TRUE)) {
    cat_col <- as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
    out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
    time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
    if (all(c(cat_col, out_col, time_col, id_col) %in% names(data))) {
      data[[cat_col]] <- factor(as.character(data[[cat_col]]))
      form <- stats::as.formula(paste(out_col, "~", cat_col, "+", time_col))
      fit <- tryCatch(
        geepack::geeglm(form, data = data, id = data[[id_col]], family = gaussian(), corstr = "ar1"),
        error = function(e) NULL
      )
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        rows[[length(rows) + 1L]] <- data.frame(
          spec = "Sensitivity_AR1", term = rownames(sm),
          beta = sm[, "Estimate"], p = sm[, "Pr(>|W|)"], n = nrow(data),
          stringsAsFactors = FALSE
        )
      }
    }
  }

  tab <- do.call(rbind, rows)
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Sensitivity.csv"), row.names = FALSE)
  ctx$results$multimorbidity_sensitivity <- list(
    table = tab, jackknife_k = k_jk, main_k = cl_main, jackknife_ok = k_ok
  )
  cli::cli_alert_success("敏感性完成（去低体重 + jackknife80；附加 AR1 可选）")
  ctx
}

register_block(
  "multimorbidity_sensitivity_suite",
  block_multimorbidity_sensitivity_suite,
  "多病叠加敏感性（文献规格）"
)
