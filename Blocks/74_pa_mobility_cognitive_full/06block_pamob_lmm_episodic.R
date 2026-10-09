###############################################################################
# pamob_lmm_episodic — 次要结局情景记忆 LMM
###############################################################################

block_pamob_lmm_episodic <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  # ensure helper
  long <- ctx$data$pamob_charls_long
  if (is.null(long)) stop("pamob_lmm_episodic: 无长表", call. = FALSE)
  bl <- pamob_cfg(ctx)
  res <- pamob_fit_lmm(long, "Episodic_memory", bl)
  pamob_write_csv(res$table, file.path(pamob_tables_dir(ctx), "Table_S_CHARLS_LMM_Episodic.csv"))
  # 主文升格：与 global 并列（老师审稿：Active–limited memory vulnerability）
  pamob_write_csv(res$table, file.path(pamob_tables_dir(ctx), "Table 3. CHARLS LMM Episodic memory.csv"))
  ctx$results$pamob_lmm_episodic <- res
  cli::cli_alert_success("pamob_lmm_episodic 完成（主文 Table 3 + 附表副本）")
  ctx
}

register_block("pamob_lmm_episodic", block_pamob_lmm_episodic, "CHARLS LMM episodic")
