###############################################################################
#  tte_descriptive — 停药 vs 继续基线特征
###############################################################################

block_tte_descriptive <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  data <- ctx$data$tte_trials %||% ctx$data$cleaned
  treat <- bl$treatment_col %||% "RASi_discontinue_2d"
  covs <- intersect(bl$covariates %||% c("Age", "Sex"), names(data))
  rows <- list()
  for (arm in c(0L, 1L)) {
    sub <- data[data[[treat]] == arm, , drop = FALSE]
    row <- list(arm = ifelse(arm == 1L, "Discontinue", "Continue"), N = nrow(sub))
    for (cv in covs) row[[cv]] <- mean(sub[[cv]], na.rm = TRUE)
    rows[[length(rows) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE)
  }
  tab <- do.call(rbind, rows)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Descriptive.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$tte_descriptive <- list(table = tab)
  cli::cli_alert_success("TTE 描述统计完成")
  ctx
}

register_block("tte_descriptive", block_tte_descriptive, "TTE 描述")
