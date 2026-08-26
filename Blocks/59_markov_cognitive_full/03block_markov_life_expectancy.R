###############################################################################
#  markov_life_expectancy — 认知健康/CI 期望寿命（状态占用）
###############################################################################

block_markov_life_expectancy <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("markov_life_expectancy: 无数据", call. = FALSE)

  state_col <- bl$state_col %||% "Cognitive_state"
  time_col  <- bl$time_col %||% "Followup_years"
  d <- data[!is.na(data[[state_col]]), , drop = FALSE]
  d$state_num <- as.integer(factor(d[[state_col]], levels = c("Healthy", "CI", "Death")))
  d$time <- suppressWarnings(as.numeric(d[[time_col]]))

  healthy_years <- sum(d$time[d$state_num == 1L], na.rm = TRUE) / max(length(unique(d$ID)), 1L)
  ci_years      <- sum(d$time[d$state_num == 2L], na.rm = TRUE) / max(length(unique(d$ID)), 1L)
  le_df <- data.frame(
    State = c("Healthy_cognition_LE", "CI_LE", "Total_followup_mean"),
    Years = c(healthy_years, ci_years, mean(d$time, na.rm = TRUE)),
    stringsAsFactors = FALSE
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(le_df, file.path(out_dir, "Table_Markov_LifeExpectancy.csv"), row.names = FALSE)

  ctx$results$markov_life_expectancy <- as.list(le_df$Years)
  names(ctx$results$markov_life_expectancy) <- le_df$State
  cli::cli_alert_success("认知期望寿命估计完成")
  ctx
}

register_block("markov_life_expectancy", block_markov_life_expectancy, "认知健康期望寿命")
