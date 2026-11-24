###############################################################################
#  multimorbidity_table1_fig1 — Table 1（按抑郁分层）+ Figure 1 基线特征条图
#
#  register_block: "multimorbidity_table1_fig1"
###############################################################################

block_multimorbidity_table1_fig1 <- function(ctx, ...) {
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_table1_fig1: 无数据", call. = FALSE)

  wave_col <- as.character(mm$wave_col %||% "Followup_wave")[1L]
  base_w <- as.integer(mm$baseline_wave %||% 1L)[1L]
  dep_bin <- as.character(mm$depression_binary_col %||% "Depression")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]

  base <- data[as.integer(data[[wave_col]]) == base_w, , drop = FALSE]
  if (!nrow(base)) stop("table1_fig1: 无基线波数据", call. = FALSE)
  if (!dep_bin %in% names(base)) {
    cli::cli_alert_warning("table1_fig1: 缺 {dep_bin}，跳过")
    return(ctx)
  }

  base$Depression_status <- ifelse(
    as.integer(base[[dep_bin]]) == 1L, "Depression", "No depression"
  )

  cont_vars <- intersect(
    c("Age", "BMI", "WHtR", "WC", "Height", "Weight", "Depression_Score", "Cognition_z"),
    names(base)
  )
  cat_vars <- intersect(
    c("Gender", "Education", "Race", "Marital", "Residence", "Smoke", "Alcohol",
      "Hypertension", "Diabetes", "Cancer", "Stroke", "Arthritis", "Obesity"),
    names(base)
  )

  rows <- list()
  for (v in cont_vars) {
    x <- suppressWarnings(as.numeric(base[[v]]))
    for (g in c("No depression", "Depression", "Overall")) {
      xi <- if (identical(g, "Overall")) x else x[base$Depression_status == g]
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, group = g, type = "continuous",
        mean = mean(xi, na.rm = TRUE), sd = stats::sd(xi, na.rm = TRUE),
        n = sum(is.finite(xi)), pct = NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  for (v in cat_vars) {
    xv <- as.character(base[[v]])
    lv <- sort(unique(stats::na.omit(xv)))
    for (lev in lv) {
      for (g in c("No depression", "Depression", "Overall")) {
        sub <- if (identical(g, "Overall")) xv else xv[base$Depression_status == g]
        n <- sum(sub == lev, na.rm = TRUE)
        den <- sum(!is.na(sub))
        rows[[length(rows) + 1L]] <- data.frame(
          variable = paste0(v, "=", lev), group = g, type = "categorical",
          mean = NA_real_, sd = NA_real_, n = n,
          pct = if (den > 0) 100 * n / den else NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  tab1 <- do.call(rbind, rows)

  out_t <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  out_f <- file.path(ctx$config$project$output_dir %||% "Output", "Figures", "pdf")
  dir.create(out_t, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_f, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab1, file.path(out_t, "Table 1. Baseline by depression.csv"), row.names = FALSE)

  # Figure 1: key continuous means by depression status
  if (requireNamespace("ggplot2", quietly = TRUE) && length(cont_vars)) {
    plot_df <- tab1[tab1$type == "continuous" & tab1$group != "Overall" &
                      tab1$variable %in% c("Age", "BMI", "Depression_Score", "Cognition_z"), ]
    if (nrow(plot_df)) {
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(variable, mean, fill = group)) +
        ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.7) +
        ggplot2::geom_errorbar(
          ggplot2::aes(ymin = mean - sd, ymax = mean + sd),
          position = ggplot2::position_dodge(width = 0.8), width = 0.2
        ) +
        ggplot2::theme_bw(base_family = "serif") +
        ggplot2::labs(
          title = "Figure 1. Main baseline characteristics",
          x = NULL, y = "Mean (± SD)", fill = NULL
        )
      ggplot2::ggsave(file.path(out_f, "Figure 1. Baseline characteristics.pdf"),
                      p, width = 8, height = 4.5)
    }
  }

  ctx$results$multimorbidity_table1 <- list(table = tab1, n_baseline = nrow(base))
  cli::cli_alert_success("Table 1 / Figure 1 完成（基线 n={nrow(base)}）")
  ctx
}

register_block(
  "multimorbidity_table1_fig1",
  block_multimorbidity_table1_fig1,
  "多病叠加 Table1 与 Figure1"
)
