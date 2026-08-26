###############################################################################
#  medication_literature_targets — 与 Pagani 2020 摘要目标值对照
###############################################################################

block_medication_literature_targets <- function(ctx, ...) {
  cmp <- (ctx$results$medication_trial_comparisons %||% list())$table
  if (is.null(cmp) || !is.data.frame(cmp) || !nrow(cmp)) {
    cmp_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                          "Table_Medication_TEXT_SOFT_Trial_Comparisons.csv")
    if (file.exists(cmp_path)) cmp <- utils::read.csv(cmp_path, stringsAsFactors = FALSE)
  }
  targets <- data.frame(
    comparison = c("TEXT_Chemo_ExeOFS_vs_TamOFS", "SOFT_ChemoPremeno_ExeOFS_vs_Tam",
                   "SOFT_ChemoPremeno_TamOFS_vs_Tam", "NoChemo_ExeOFS_vs_Tam"),
    literature_abs_benefit = c(0.051, 0.052, 0.035, 0.025),
    literature_note = c("TEXT chemo avg ~5.1%", "SOFT premeno chemo avg ~5.2%",
                        "TamOFS vs Tam max ~3.5%", "No chemo ~1-4%"),
    stringsAsFactors = FALSE
  )
  if (!is.null(cmp) && nrow(cmp)) {
    m <- merge(targets, cmp[, c("comparison", "abs_benefit_8y")], by = "comparison", all.x = TRUE)
    m$delta_vs_literature <- m$abs_benefit_8y - m$literature_abs_benefit
  } else m <- targets

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(m, file.path(out_dir, "Table_Medication_Literature_Target_Check.csv"), row.names = FALSE)

  ctx$results$medication_literature_targets <- m
  cli::cli_alert_success("文献目标值对照表完成")
  ctx
}

register_block("medication_literature_targets", block_medication_literature_targets, "Pagani 2020 数值对照")
