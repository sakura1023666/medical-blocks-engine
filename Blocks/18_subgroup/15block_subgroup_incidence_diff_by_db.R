###############################################################################
#  subgroup_incidence_diff_by_db — 分数据库分层
###############################################################################

block_subgroup_incidence_diff_by_db <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  data <- ctx$data$tte_weighted %||% ctx$data$tte_trials %||% ctx$data$cleaned
  treat <- if (".tte_trt" %in% names(data)) ".tte_trt" else (bl$treatment_col %||% "Treatment_discontinue")
  outcome <- if (".tte_out" %in% names(data)) ".tte_out" else (bl$outcome_30d %||% "Death_30d")
  db_col <- bl$database_col %||% "Database"
  rows <- list()
  if (db_col %in% names(data)) {
    for (db in unique(data[[db_col]])) {
      sub <- data[data[[db_col]] == db, , drop = FALSE]
      if (nrow(sub) < 10L) next
      p0 <- mean(sub[[outcome]][sub[[treat]] == 0L], na.rm = TRUE)
      p1 <- mean(sub[[outcome]][sub[[treat]] == 1L], na.rm = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(database = db, continue = p0, discontinue = p1, rd = p1 - p0, stringsAsFactors = FALSE)
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Stratified.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$subgroup_incidence_diff_by_db <- list(table = tab)
  cli::cli_alert_success("TTE 分层分析完成")
  ctx
}

register_block("subgroup_incidence_diff_by_db", block_subgroup_incidence_diff_by_db, "TTE 分层")
