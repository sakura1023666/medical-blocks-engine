###############################################################################
#  markov_apoe_le_difference — APOE ε4 携带 vs 非携带 CH 期望寿命差
###############################################################################

block_markov_apoe_le_difference <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/markov_msm_utils.R"), local = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  apoe_col <- bl$apoe_col %||% "APOE_carrier"
  if (!apoe_col %in% names(data)) stop("markov_apoe_le_difference: 缺少 APOE 分层", call. = FALSE)

  rows <- list()
  for (grp in c("Carrier", "Non_carrier")) {
    sub <- data[as.character(data[[apoe_col]]) == grp, , drop = FALSE]
    if (nrow(sub) < 20L) next
    long <- .markov_prep_long_msm(sub, bl)
    ch <- long[long$Cognitive_state %in% c("CH", "Healthy"), , drop = FALSE]
    if (!nrow(ch)) next
    le <- mean(ch$Followup_years %||% ch[[bl$time_col %||% "Followup_years"]], na.rm = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      APOE_group = grp, CH_mean_followup_years = le, n_ids = length(unique(ch$ID)),
      stringsAsFactors = FALSE
    )
  }
  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()
  if (nrow(out_df) == 2L) {
    diff <- out_df$CH_mean_followup_years[out_df$APOE_group == "Non_carrier"] -
      out_df$CH_mean_followup_years[out_df$APOE_group == "Carrier"]
    out_df <- rbind(out_df, data.frame(
      APOE_group = "Diff_NonCarrier_minus_Carrier",
      CH_mean_followup_years = diff, n_ids = NA_integer_,
      stringsAsFactors = FALSE
    ))
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Markov_APOE_CH_LifeExpectancy_Diff.csv"), row.names = FALSE)

  ctx$results$markov_apoe_le_difference <- out_df
  cli::cli_alert_success("APOE ε4 CH 期望寿命差完成")
  ctx
}

register_block("markov_apoe_le_difference", block_markov_apoe_le_difference, "APOE CH 期望寿命差")
