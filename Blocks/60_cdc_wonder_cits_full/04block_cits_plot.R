###############################################################################
#  cits_plot — CITS 时间序列可视化
###############################################################################

block_cits_plot <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  monthly <- ctx$data$cits_monthly
  if (is.null(monthly) || !nrow(monthly))
    stop("cits_plot: 无月度聚合数据", call. = FALSE)

  oc <- bl$primary_outcome %||% unique(monthly$outcome)[1L]
  sub <- monthly[monthly$outcome == oc, , drop = FALSE]
  if (!nrow(sub)) stop("cits_plot: 结局无数据", call. = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  y_var <- if ("rate_per10k" %in% names(sub)) "rate_per10k" else if ("rate" %in% names(sub)) "rate" else names(sub)[5L]
  sub$Group <- ifelse(sub$ban == 1L, "Ban states", "No-ban states")
  p <- ggplot2::ggplot(sub, ggplot2::aes(x = month, y = .data[[y_var]], color = Group)) +
      ggplot2::geom_line(linewidth = 0.7) +
      ggplot2::geom_vline(xintercept = as.Date(bl$intervention_date %||% "2022-11-01"),
                          linetype = "dashed", color = "gray40") +
      ggplot2::labs(title = paste("CITS:", oc), x = "Month", y = "Rate per 10,000") +
      ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(fig_dir, paste0("Figure_CITS_", oc, ".pdf")), p, width = 9, height = 5)
  }

  ctx$results$cits_plot <- list(outcome = oc, n_points = nrow(sub))
  cli::cli_alert_success("CITS 时间序列图完成")
  ctx
}

register_block("cits_plot", block_cits_plot, "CITS 时间序列图")
