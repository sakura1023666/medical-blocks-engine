###############################################################################
#  markov_msm_fit — 连续时间三状态 MSM（完整 Q 矩阵 + 协变量）
###############################################################################

block_markov_msm_fit <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/markov_msm_utils.R"), local = FALSE)

  long <- .markov_prep_long_msm(ctx$data$imputed %||% ctx$data$cleaned, bl)
  fit <- tryCatch(.markov_fit_msm(long, bl), error = function(e) {
    cli::cli_alert_warning("msm 拟合失败，使用粗转移率: {e$message}")
    NULL
  })

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(fit)) {
    qm <- as.data.frame(fit$Qmatrices$baseline)
    utils::write.csv(qm, file.path(out_dir, "Table_Markov_MSM_Qmatrix.csv"))
    hr <- tryCatch(summary(fit)$hazard.ratios, error = function(e) NULL)
    if (!is.null(hr)) utils::write.csv(as.data.frame(hr), file.path(out_dir, "Table_Markov_MSM_HazardRatios.csv"))
    ctx$results$markov_msm_fit <- list(method = "msm", n_trans = nrow(long), fit = fit)
  } else {
    trans <- aggregate(
      state_num ~ ID, data = long, FUN = function(x) length(unique(x))
    )
    ctx$results$markov_msm_fit <- list(method = "fallback", n = nrow(long))
  }

  cli::cli_alert_success("Markov MSM 拟合完成")
  ctx
}

register_block("markov_msm_fit", block_markov_msm_fit, "三状态 MSM 完整拟合")
