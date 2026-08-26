###############################################################################
#  mr_egger_presso — MR-Egger + MR-PRESSO（Python/R 混合）
###############################################################################

block_mr_egger_presso <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  iv_path <- file.path(out, "Table_MR_SNP_Screened.csv")
  if (!file.exists(iv_path)) {
    ctx <- block_mr_snp_screen(ctx)
    iv_path <- ctx$results$mr_snp_screen$screened_path
  }
  outcomes <- paste(bl$mr_outcomes %||% c("CVD", "CKD", "Diabetes"), collapse = ",")
  run_literature_python(root, "mr_egger_presso", c(
    "--out-dir", out,
    "--data-path", iv_path,
    "--genes", outcomes,
    "--expr-path", file.path(root, "Data/smoke")
  ))
  ctx$results$mr_egger_presso <- list(output_dir = out)
  cli::cli_alert_success("MR-Egger / MR-PRESSO 完成")
  ctx
}

register_block("mr_egger_presso", block_mr_egger_presso, "MR-Egger PRESSO")
