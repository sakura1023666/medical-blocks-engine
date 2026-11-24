###############################################################################
#  dcs_data_prep — ELSA 波次 + log(CES-D) + 二次时间项
###############################################################################

block_dcs_data_prep <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_dcsm_yin.R"), local = FALSE)
  data <- ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
  data <- dcs_yin_prep(data, bl)
  ctx$data$dcs_long <- data
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "DCS_long_ready.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, out, row.names = FALSE)
  ctx$results$dcs_data_prep <- list(n = nrow(data))
  cli::cli_alert_success("Yin DCSM 数据准备完成")
  ctx
}

register_block("dcs_data_prep", block_dcs_data_prep, "DCSM 数据准备")
