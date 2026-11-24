###############################################################################
#  markov_apoe_lifestyle — APOE × 健康生活方式分层转移风险
###############################################################################

block_markov_apoe_lifestyle <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("markov_apoe_lifestyle: 无数据", call. = FALSE)

  apoe_col <- bl$apoe_col %||% "APOE_carrier"
  life_col <- bl$lifestyle_col %||% "Healthy_lifestyle"
  state_col <- bl$state_col %||% "Cognitive_state"
  if (!all(c(apoe_col, life_col, state_col) %in% names(data)))
    stop("markov_apoe_lifestyle: 缺少分层变量", call. = FALSE)

  d <- data
  d$to_ci <- as.integer(d[[state_col]] %in% c("CI", "Death"))
  strata <- interaction(d[[apoe_col]], d[[life_col]], drop = TRUE)
  rows <- list()
  for (st in levels(strata)) {
    sub <- d[strata == st, , drop = FALSE]
    if (nrow(sub) < 15L) next
    rate <- mean(sub$to_ci, na.rm = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      Stratum = st, N = nrow(sub), CI_transition_rate = rate, stringsAsFactors = FALSE
    )
  }
  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Markov_APOE_Lifestyle_Strata.csv"), row.names = FALSE)

  ctx$results$markov_apoe_lifestyle <- list(n_strata = nrow(out_df))
  cli::cli_alert_success("APOE×生活方式分层分析完成")
  ctx
}

register_block("markov_apoe_lifestyle", block_markov_apoe_lifestyle, "APOE×生活方式 Markov 分层")
