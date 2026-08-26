###############################################################################
#  network_temp_trajectory — 网络温度随年龄/波次轨迹（R 汇总 Python 输出）
###############################################################################

block_network_temp_trajectory <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  out_dir <- (ctx$results$network_temp_compute %||% list())$output_dir
  if (is.null(out_dir) || !dir.exists(out_dir))
    stop("network_temp_trajectory: 请先运行 network_temp_compute", call. = FALSE)

  temp_path <- file.path(out_dir, "Table_Network_Temperature_by_Wave.csv")
  ising_path <- file.path(out_dir, "Table_Network_Temperature_Ising_by_Wave.csv")
  if (!file.exists(temp_path) && file.exists(ising_path)) temp_path <- ising_path
  if (!file.exists(temp_path)) stop("network_temp_trajectory: 缺少温度表", call. = FALSE)
  temp_df <- utils::read.csv(temp_path, stringsAsFactors = FALSE)
  if ("Subgroup" %in% names(temp_df)) {
    temp_df$Subgroup <- ifelse(is.na(temp_df$Subgroup) | temp_df$Subgroup == "", "All", temp_df$Subgroup)
  } else {
    temp_df$Subgroup <- "All"
  }

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(temp_df)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(temp_df, ggplot2::aes(x = Wave, y = network_temperature, color = Subgroup)) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::geom_point(size = 2) +
      ggplot2::labs(title = "Network Temperature Across Adolescence", x = "Wave", y = "Network Temperature") +
      ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(fig_dir, "Figure_Network_Temperature_Trajectory.pdf"), p, width = 8, height = 5)
  }

  ctx$results$network_temp_trajectory <- list(n_rows = nrow(temp_df))
  cli::cli_alert_success("网络温度轨迹图完成")
  ctx
}

register_block("network_temp_trajectory", block_network_temp_trajectory, "网络温度发展轨迹")
