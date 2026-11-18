###############################################################################
#  trajectory_lcmm_mpcmp_plot — 边际投影轨迹图（mixed model 按类投影）
###############################################################################

block_trajectory_lcmm_mpcmp_plot <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  long <- ctx$data$trajectory_long[[paste0((bl$index_vars %||% "CreatininePct")[1L], "_long")]]
  if (is.null(long)) {
    long <- ctx$data$trajectory_long[["CreatininePct_long"]]
  }
  if (is.null(long)) long <- ctx$data$trajectory_long[["Creatinine_long"]]
  if (is.null(long)) stop("trajectory_lcmm_mpcmp_plot: 无长格式数据", call. = FALSE)

  id_col <- bl$id_column %||% "ID"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if ("trajectory_class" %in% names(data) && id_col %in% names(long)) {
    long <- merge(long, data[, c(id_col, "trajectory_class")], by = id_col, all.x = TRUE)
  }
  if (!"trajectory_class" %in% names(long)) {
    assign_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "LCMM", "Table_LCMM_Assignment_Dev.csv")
    if (file.exists(assign_path)) {
      adf <- utils::read.csv(assign_path, stringsAsFactors = FALSE)
      mid <- intersect(c(id_col, "ID"), names(adf))[1L]
      if (!is.na(mid)) long <- merge(long, adf[, c(mid, "trajectory_class")], by = mid, all.x = TRUE)
    }
  }
  if (!"trajectory_class" %in% names(long)) {
    cli::cli_alert_warning("trajectory_lcmm_mpcmp_plot: 缺少 trajectory_class，跳过作图")
    ctx$results$trajectory_lcmm_mpcmp_plot <- data.frame(note = "no class")
    return(ctx)
  }

  agg <- stats::aggregate(Value ~ Time + trajectory_class, data = long, FUN = mean, na.rm = TRUE)
  out_fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
  dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p <- ggplot2::ggplot(agg, ggplot2::aes(x = Time, y = Value, color = factor(trajectory_class))) +
      ggplot2::geom_line(linewidth = 1) +
      ggplot2::geom_point(size = 2) +
      ggplot2::labs(
        x = "Day", y = "Creatinine % change",
        title = "Marginal projected creatinine trajectories by LCMM class",
        color = "Class"
      ) +
      ggplot2::theme_bw()
    ggplot2::ggsave(file.path(out_fig, "Figure_LCMM_Marginal_Trajectory.pdf"), p, width = 9, height = 6)
  } else {
    grDevices::pdf(file.path(out_fig, "Figure_LCMM_Marginal_Trajectory.pdf"), width = 9, height = 6)
    for (cl in sort(unique(agg$trajectory_class))) {
      sub <- agg[agg$trajectory_class == cl, ]
      graphics::lines(sub$Time, sub$Value, type = "b", col = cl + 1L)
    }
    grDevices::dev.off()
  }

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "LCMM", "Table_Marginal_Trajectory.csv")
  dir.create(dirname(out_tab), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(agg, out_tab, row.names = FALSE)
  ctx$results$trajectory_lcmm_mpcmp_plot <- agg
  cli::cli_alert_success("边际投影轨迹图已输出")
  ctx
}

register_block("trajectory_lcmm_mpcmp_plot", block_trajectory_lcmm_mpcmp_plot, "LCMM 边际投影轨迹图")
