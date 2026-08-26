###############################################################################
#  cross_lagged_country_year_bar — 按年/国的暴露分布（半小提琴+箱线）
#
#  require_data = ctx$data$longitudinal %||% ctx$data$imputed
#  来源: C01.Country_Year_barplot_new.R（保留 new；旧 barplot 废弃）
#  暴露/结局从 config 读取（默认 FI / Disease_Group），禁止写死 Leisure_activities
#  register_block: "cross_lagged_country_year_bar"
###############################################################################

block_cross_lagged_country_year_bar <- function(ctx, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("cross_lagged_country_year_bar: 需要 ggplot2", call. = FALSE)

  cfg <- ctx$config
  bl <- cfg$cross_lagged_country_year_bar %||% list()
  data <- ctx$data$longitudinal %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("cross_lagged_country_year_bar: 无数据", call. = FALSE)

  index <- bl$index_var %||% cfg$incidence$index_var %||% "FI"
  outcome <- bl$outcome %||% cfg$data$outcome_column %||% "Disease_Group"
  year_col <- bl$year_col %||% if ("Year" %in% names(data)) "Year" else if ("year" %in% names(data)) "year" else if ("wave" %in% names(data)) "wave" else NULL
  country_col <- bl$country_col %||% if ("Country" %in% names(data)) "Country" else if ("country" %in% names(data)) "country" else NULL

  if (!index %in% names(data)) stop("缺暴露列 ", index, call. = FALSE)
  if (!outcome %in% names(data)) stop("缺结局列 ", outcome, call. = FALSE)
  if (is.null(year_col)) stop("缺 Year/wave 列；请在 config$cross_lagged_country_year_bar$year_col 指定", call. = FALSE)

  df <- data.frame(
    DISEASE = as.character(data[[outcome]]),
    Year = as.character(data[[year_col]]),
    index = as.numeric(data[[index]]),
    stringsAsFactors = FALSE
  )
  if (!is.null(country_col) && country_col %in% names(data))
    df$country <- as.character(data[[country_col]])
  df <- df[stats::complete.cases(df[, c("DISEASE", "Year", "index")]), , drop = FALSE]
  if (nrow(df) < 10L) stop("cross_lagged_country_year_bar: 有效行过少", call. = FALSE)

  # per-year t-test labels
  p_values <- do.call(rbind, lapply(split(df, df$Year), function(sub) {
    pv <- tryCatch(stats::t.test(index ~ DISEASE, data = sub)$p.value, error = function(e) NA_real_)
    data.frame(
      Year = as.character(sub$Year[1]),
      p_value = pv,
      y_max = max(sub$index, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  p_values$sig_label <- ifelse(is.na(p_values$p_value), "na",
    ifelse(p_values$p_value < 0.001, "***",
      ifelse(p_values$p_value < 0.01, "**",
        ifelse(p_values$p_value < 0.05, "*", "ns"))))
  p_values$y_text <- p_values$y_max * 1.05

  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$Year, y = .data$index, fill = .data$DISEASE)) +
    ggplot2::geom_boxplot(width = 0.35, outlier.size = 0.6, position = ggplot2::position_dodge(0.55)) +
    ggplot2::geom_text(
      data = p_values,
      ggplot2::aes(x = .data$Year, y = .data$y_text, label = .data$sig_label),
      inherit.aes = FALSE, size = 3.5
    ) +
    ggplot2::labs(
      title = paste0(index, " by Year and ", outcome),
      x = "Year", y = index, fill = outcome
    ) +
    ggplot2::theme_bw()

  if (!is.null(df$country) && length(unique(df$country)) > 1L) {
    p <- p + ggplot2::facet_wrap(~country, scales = "free_x")
  }

  fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
  tab_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(fig_dir, paste0("Fig_CountryYear_", index, ".pdf"))
  ggplot2::ggsave(out, p, width = 9, height = 5)
  utils::write.csv(p_values, file.path(tab_dir, paste0("CountryYear_p_", index, ".csv")), row.names = FALSE)

  ctx$results$cross_lagged_country_year_bar <- list(path = out, p_values = p_values)
  cli::cli_alert_success("Country/Year 图已写: {out}")
  ctx
}

register_block("cross_lagged_country_year_bar", block_cross_lagged_country_year_bar, "年/国暴露分布图")
