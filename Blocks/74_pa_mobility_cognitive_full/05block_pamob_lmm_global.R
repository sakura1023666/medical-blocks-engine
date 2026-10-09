###############################################################################
# pamob_lmm_global — CHARLS LMM Global_cognition ~ Time * phenotype + (1|ID)
###############################################################################

block_pamob_lmm_global <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  long <- ctx$data$pamob_charls_long
  if (is.null(long)) stop("pamob_lmm_global: 无长表", call. = FALSE)
  bl <- pamob_cfg(ctx)
  res <- pamob_fit_lmm(long, "Global_cognition", bl)
  out <- file.path(pamob_tables_dir(ctx), "Table 2. CHARLS LMM Global cognition.csv")
  pamob_write_csv(res$table, out)
  ctx$results$pamob_lmm_global <- res
  ctx$data$pamob_lmm_fit_data <- res$data
  cli::cli_alert_success("pamob_lmm_global: Table 2 已写出")
  ctx
}

register_block("pamob_lmm_global", block_pamob_lmm_global, "CHARLS LMM global")
