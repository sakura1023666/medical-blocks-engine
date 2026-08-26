###############################################################################
#  markov_life_table_figure — 65/75/85 岁 CH/CI 生命表 + Figure 输出
###############################################################################

block_markov_life_table_figure <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/markov_msm_utils.R"), local = FALSE)

  long <- .markov_prep_long_msm(ctx$data$imputed %||% ctx$data$cleaned, bl)
  ages <- bl$life_table_ages %||% c(65, 75, 85)
  le_df <- .markov_life_expectancy_table(long, bl, ages)

  if (requireNamespace("msm", quietly = TRUE) && requireNamespace("elect", quietly = TRUE)) {
    tryCatch({
      fit <- .markov_fit_msm(long, bl)
      le_msm <- data.frame(
        entry_age = ages,
        total_le = vapply(ages, function(a) {
          as.numeric(msm::ppassage(t = a, q = fit$Qmatrices$baseline, from = 1L, to = 3L))
        }, numeric(1L))
      )
      utils::write.csv(le_msm, file.path(ctx$config$project$output_dir, "Tables", "Table_Markov_elect_MSM_LE.csv"), row.names = FALSE)
    }, error = function(e) cli::cli_alert_warning("elect/msm 生命表: {e$message}"))
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(le_df, file.path(out_dir, "Table_Markov_LifeTable_65_75_85.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(le_df)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(le_df, ggplot2::aes(x = factor(entry_age), y = life_expectancy_years, fill = state)) +
      ggplot2::geom_col(position = "dodge") +
      ggplot2::labs(title = "Life Expectancy by Entry Age and State", x = "Entry Age", y = "Years") +
      ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(fig_dir, "Figure_Markov_LifeExpectancy_Bars.pdf"), p, width = 8, height = 5)
  }

  ctx$results$markov_life_table_figure <- le_df
  cli::cli_alert_success("Markov 生命表 Figure 完成")
  ctx
}

register_block("markov_life_table_figure", block_markov_life_table_figure, "Markov 生命表 Figure")
