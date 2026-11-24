###############################################################################
#  dcs_depression_to_memory — DCSM 抑郁斜率→记忆变化
###############################################################################

block_dcs_depression_to_memory <- function(ctx, ...) {
  res <- (ctx$results$dcs_bivariate_dcsm %||% list())$memory
  if (is.null(res)) {
    bl <- ctx$config$dual_change_score %||% list()
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "R/literature_dcsm_yin.R"), local = FALSE)
    data <- dcs_yin_prep(ctx$data$dcs_long %||% ctx$data$cleaned, bl)
    res <- dcs_yin_fit_lavaan(data, bl, "memory")
  }
  pe <- res$pe
  tab <- pe[pe$op == "~" & (grepl("s_dep", pe$lhs) | grepl("s_cog", pe$rhs)), , drop = FALSE]
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Dep_to_Mem.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(if (nrow(tab)) tab else pe, out, row.names = FALSE)
  tgt <- dcs_yin_extract_targets(pe, "memory")
  ctx$results$dcs_depression_to_memory <- list(table = tab, dep_change_beta = tgt$dep_to_mem_slope)
  cli::cli_alert_success("DCSM 抑郁→记忆完成")
  ctx
}

register_block("dcs_depression_to_memory", block_dcs_depression_to_memory, "DCSM 抑郁→记忆")
