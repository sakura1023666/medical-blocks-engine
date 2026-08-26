###############################################################################
#  dcs_verbal_fluency — 言语流畅性（无双向变化）
###############################################################################

block_dcs_verbal_fluency <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  data <- ctx$data$dcs_long %||% ctx$data$cleaned
  flu <- bl$fluency_col %||% "Verbal_fluency"
  if (!flu %in% names(data)) { ctx$results$dcs_verbal_fluency <- list(skipped = TRUE); return(ctx) }
  data$flu_change <- ave(data[[flu]], data[[bl$id_col %||% "ID"]], FUN = function(x) c(NA, diff(x)))
  sub <- data[!is.na(data$flu_change), , drop = FALSE]
  fit <- stats::lm(stats::as.formula(paste("flu_change ~ dep_change + dep_level +", flu)), data = sub)
  ct <- summary(fit)$coefficients
  tab <- data.frame(term = rownames(ct), estimate = ct[, 1], p_value = ct[, 4], bidirectional = FALSE, stringsAsFactors = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Verbal_Fluency.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$dcs_verbal_fluency <- list(table = tab)
  cli::cli_alert_success("言语流畅性分析完成")
  ctx
}

register_block("dcs_verbal_fluency", block_dcs_verbal_fluency, "言语流畅性")
