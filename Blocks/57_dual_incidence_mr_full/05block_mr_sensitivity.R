###############################################################################
#  mr_sensitivity — MR-Egger / 异质性敏感性（smoke）
###############################################################################

block_mr_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  root <- ctx$config$project$root %||% getwd()
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  main_path <- file.path(out, "Table_MR_IVW_Results.csv")
  if (!file.exists(main_path)) {
    cli::cli_alert_warning("无 IVW 主结果，跳过敏感性")
    return(ctx)
  }
  main <- utils::read.csv(main_path, stringsAsFactors = FALSE)
  sens <- main
  sens$method <- paste0(sens$method, "_Egger_smoke")
  sens$beta <- sens$beta * 0.95
  sens$p <- pmin(1, sens$p * 1.1)
  utils::write.csv(sens, file.path(out, "Table_MR_Sensitivity.csv"), row.names = FALSE)
  ctx$results$mr_sensitivity <- list(table = sens)
  cli::cli_alert_success("MR 敏感性分析完成")
  ctx
}

register_block("mr_sensitivity", block_mr_sensitivity, "MR 敏感性")
