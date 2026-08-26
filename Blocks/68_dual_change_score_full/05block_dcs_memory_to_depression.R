###############################################################################
#  dcs_memory_to_depression — DCSM 记忆斜率→抑郁变化
###############################################################################

block_dcs_memory_to_depression <- function(ctx, ...) {
  res <- (ctx$results$dcs_bivariate_dcsm %||% list())$memory
  if (is.null(res)) return(ctx)
  pe <- res$pe
  tab <- pe[pe$op == "~" & grepl("s_cog", pe$lhs) & grepl("s_dep", pe$rhs), , drop = FALSE]
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Mem_to_Dep.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(if (nrow(tab)) tab else pe, out, row.names = FALSE)
  tgt <- dcs_yin_extract_targets(pe, "memory")
  ctx$results$dcs_memory_to_depression <- list(table = tab, mem_change_beta = tgt$mem_to_dep_slope)
  cli::cli_alert_success("DCSM 记忆→抑郁完成")
  ctx
}

register_block("dcs_memory_to_depression", block_dcs_memory_to_depression, "DCSM 记忆→抑郁")
