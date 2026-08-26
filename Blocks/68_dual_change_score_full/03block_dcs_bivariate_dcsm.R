###############################################################################
#  dcs_bivariate_dcsm — Yin 2024 正式 bivariate DCSM（lavaan growth）
###############################################################################

block_dcs_bivariate_dcsm <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_dcsm_yin.R"), local = FALSE)
  data <- ctx$data$dcs_long %||% ctx$data$cleaned
  data <- dcs_yin_prep(data, bl)
  ctx$data$dcs_long <- data

  res_mem <- dcs_yin_fit_lavaan(data, bl, domain = "memory")
  res_flu <- tryCatch(dcs_yin_fit_lavaan(data, bl, domain = "fluency"), error = function(e) NULL)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Lavaan_Memory.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res_mem$pe, out, row.names = FALSE)
  if (!is.null(res_flu)) {
    utils::write.csv(res_flu$pe, file.path(dirname(out), "Table_DCS_Lavaan_Fluency.csv"), row.names = FALSE)
  }

  tgt <- dcs_yin_extract_targets(res_mem$pe, "memory")
  ctx$results$dcs_bivariate_dcsm <- list(
    memory = res_mem, fluency = res_flu, targets = tgt, method = res_mem$method
  )
  cli::cli_alert_success("Yin DCSM lavaan ({res_mem$method})")
  ctx
}

register_block("dcs_bivariate_dcsm", block_dcs_bivariate_dcsm, "Yin DCSM lavaan")
