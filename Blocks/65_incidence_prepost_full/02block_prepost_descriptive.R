###############################################################################
#  prepost_descriptive — 糖尿病前后基线描述
###############################################################################

block_prepost_descriptive <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  cog <- bl$global_cog_col %||% "Global_cognition"
  tab <- data.frame(
    Group = c("No_diabetes_yet", "Post_diabetes"),
    N = c(sum(data$Post_diabetes == 0L, na.rm = TRUE), sum(data$Post_diabetes == 1L, na.rm = TRUE)),
    Mean_cognition = c(mean(data[[cog]][data$Post_diabetes == 0L], na.rm = TRUE),
                       mean(data[[cog]][data$Post_diabetes == 1L], na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Descriptive.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$prepost_descriptive <- list(table = tab)
  cli::cli_alert_success("发病前后描述统计完成")
  ctx
}

register_block("prepost_descriptive", block_prepost_descriptive, "发病前后描述")
