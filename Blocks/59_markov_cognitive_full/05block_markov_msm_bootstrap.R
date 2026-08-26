###############################################################################
#  markov_msm_bootstrap — 1000 次 Bootstrap Q 矩阵与转移强度 CI
###############################################################################

block_markov_msm_bootstrap <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/markov_msm_utils.R"), local = FALSE)

  long <- .markov_prep_long_msm(ctx$data$imputed %||% ctx$data$cleaned, bl)
  R <- as.integer(bl$bootstrap_R %||% 100L)
  if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) R <- min(R, 50L)

  fit <- tryCatch(.markov_fit_msm(long, bl), error = function(e) NULL)
  q_base <- if (!is.null(fit)) as.data.frame(fit$Qmatrices$baseline) else data.frame()

  boot <- .markov_bootstrap_q(long, bl, R = R)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (nrow(q_base)) utils::write.csv(q_base, file.path(out_dir, "Table_Markov_MSM_Qmatrix_MLE.csv"))
  if (!is.null(boot) && nrow(boot)) utils::write.csv(boot, file.path(out_dir, "Table_Markov_MSM_Bootstrap_CI.csv"), row.names = FALSE)

  ctx$results$markov_msm_bootstrap <- list(R = R, mle = fit, bootstrap = boot)
  cli::cli_alert_success("Markov Bootstrap ({R} 次) 完成")
  ctx
}

register_block("markov_msm_bootstrap", block_markov_msm_bootstrap, "MSM Bootstrap 1000")
