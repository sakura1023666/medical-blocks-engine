###############################################################################
#  cross_lagged_fig1_group — 按结局分层的虚弱均值~年份折线（Fig1）
#
#  require_data = ctx$data$longitudinal
#  来源: C02_Fig1_year_or_country_group.R（去掉硬编码 HRS csv；用 ctx 长表）
#  register_block: "cross_lagged_fig1_group"
###############################################################################

block_cross_lagged_fig1_group <- function(ctx, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || !requireNamespace("dplyr", quietly = TRUE))
    stop("cross_lagged_fig1_group: 需要 ggplot2 + dplyr", call. = FALSE)

  cfg <- ctx$config
  bl <- cfg$cross_lagged_fig1_group %||% list()
  data <- ctx$data$longitudinal %||% ctx$data$imputed
  if (is.null(data) || !is.data.frame(data))
    stop("cross_lagged_fig1_group: 无纵向/分析数据", call. = FALSE)

  fi <- bl$fi_var %||% cfg$incidence$index_var %||% "FI"
  outcome <- bl$outcome %||% cfg$data$outcome_column %||% "Disease_Group"
  year_col <- bl$year_col %||% if ("Year" %in% names(data)) "Year" else if ("year" %in% names(data)) "year" else if ("wave" %in% names(data)) "wave" else NULL
  if (!fi %in% names(data)) stop("缺 FI 列 ", fi, call. = FALSE)
  if (!outcome %in% names(data)) stop("缺结局列 ", outcome, call. = FALSE)
  if (is.null(year_col)) stop("缺 Year/wave 列", call. = FALSE)

  df <- data.frame(
    Disease = as.character(data[[outcome]]),
    Year = as.character(data[[year_col]]),
    Frailty = as.numeric(data[[fi]]),
    stringsAsFactors = FALSE
  )
  df <- df[stats::complete.cases(df), , drop = FALSE]

  summary_df <- as.data.frame(dplyr::summarise(
    dplyr::group_by(df, Year, Disease),
    mean_frailty = mean(.data$Frailty, na.rm = TRUE),
    se = stats::sd(.data$Frailty, na.rm = TRUE) / sqrt(dplyr::n()),
    n = dplyr::n(),
    .groups = "drop"
  ))

  p <- ggplot2::ggplot(summary_df, ggplot2::aes(x = .data$Year, y = .data$mean_frailty,
                                                 color = .data$Disease, group = .data$Disease)) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 2) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$mean_frailty - .data$se,
                                        ymax = .data$mean_frailty + .data$se),
                           width = 0.15) +
    ggplot2::labs(title = paste0("Mean ", fi, " by Year and ", outcome),
                  x = "Year", y = paste0("Mean ", fi), color = outcome) +
    ggplot2::theme_bw()

  fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
  tab_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(fig_dir, "Fig1_FI_by_Year_Disease.pdf")
  ggplot2::ggsave(out, p, width = 8, height = 5)
  utils::write.csv(summary_df, file.path(tab_dir, "Fig1_FI_by_Year_Disease.csv"), row.names = FALSE)

  ctx$results$cross_lagged_fig1_group <- list(path = out, table = summary_df)
  cli::cli_alert_success("Fig1 已写: {out}")
  ctx
}

register_block("cross_lagged_fig1_group", block_cross_lagged_fig1_group, "Fig1 年-结局虚弱均值")
