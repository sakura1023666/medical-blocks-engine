###############################################################################
#  prepost_visualize — 认知轨迹可视化数据导出
###############################################################################

block_prepost_visualize <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  cog <- bl$global_cog_col %||% "Global_cognition"
  time_col <- bl$time_col %||% "Years_from_baseline"
  agg <- aggregate(data[[cog]], by = list(Time = data[[time_col]], Post = data$Post_diabetes),
                 FUN = mean, na.rm = TRUE)
  names(agg)[3] <- "mean_cognition"
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Trajectory_Points.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(agg, out, row.names = FALSE)
  ctx$results$prepost_visualize <- list(table = agg)
  cli::cli_alert_success("轨迹可视化数据导出")
  ctx
}

register_block("prepost_visualize", block_prepost_visualize, "发病前后轨迹图")
