###############################################################################
#  tte_bootstrap_ci — Bootstrap 95% CI（累积发病率与风险差）
###############################################################################

block_tte_bootstrap_ci <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$tte_weighted %||% ctx$data$tte_trials %||% ctx$data$cleaned
  B <- as.integer(bl$bootstrap_R %||% 200L)
  tab <- tte_nie_bootstrap_ci(data, ".tte_out", ".tte_trt", "sw", B = B, seed = bl$seed %||% 42L)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Bootstrap_CI.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$tte_bootstrap_ci <- list(table = tab)
  cli::cli_alert_success("Bootstrap CI (B={B}) 完成")
  ctx
}

register_block("tte_bootstrap_ci", block_tte_bootstrap_ci, "TTE Bootstrap CI")
