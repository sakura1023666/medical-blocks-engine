###############################################################################
#  prepost_sensitivity — Chen 2024 三项敏感性分析
###############################################################################

block_prepost_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_prepost_chen.R"), local = FALSE)
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  if (!"diabetes_grp" %in% names(data)) {
    data <- prepost_chen_build_composite(data, bl)
    data <- prepost_chen_piecewise_vars(data, bl)
  }
  outcome <- bl$global_cog_col %||% "Global_cognition_z"
  if (!outcome %in% names(data)) outcome <- "Global_cognition"
  time_col <- bl$time_col %||% "Years_from_baseline"
  rows <- list()

  ctrl <- data[data$diabetes_grp == 0L, , drop = FALSE]
  dm <- data[data$diabetes_grp == 1L, , drop = FALSE]
  pre_dm <- dm[dm$years_after_diabetes == 0, , drop = FALSE]
  if (nrow(ctrl) > 20L && nrow(pre_dm) > 20L) {
    fit_c <- stats::lm(stats::as.formula(paste(outcome, "~", time_col)), data = ctrl[ctrl[[time_col]] <= 2, , drop = FALSE])
    fit_p <- stats::lm(stats::as.formula(paste(outcome, "~", time_col)), data = pre_dm[pre_dm[[time_col]] <= 2, , drop = FALSE])
    rows[[1L]] <- data.frame(
      scenario = "prediabetes_vs_control_0_2y",
      slope_diff = coef(fit_p)[time_col] - coef(fit_c)[time_col],
      stringsAsFactors = FALSE
    )
  }

  if (nrow(ctrl) > 20L && nrow(dm) > 20L) {
    dm_last <- dm[dm[[time_col]] == max(dm[[time_col]], na.rm = TRUE), , drop = FALSE]
    dm_first <- dm[dm[[time_col]] == min(dm[[time_col]], na.rm = TRUE), , drop = FALSE]
    ctrl_last <- ctrl[ctrl[[time_col]] == max(ctrl[[time_col]], na.rm = TRUE), , drop = FALSE]
    ctrl_first <- ctrl[ctrl[[time_col]] == min(ctrl[[time_col]], na.rm = TRUE), , drop = FALSE]
    delta_dm <- mean(dm_last[[outcome]], na.rm = TRUE) - mean(dm_first[[outcome]], na.rm = TRUE)
    delta_ctrl <- mean(ctrl_last[[outcome]], na.rm = TRUE) - mean(ctrl_first[[outcome]], na.rm = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      scenario = "wave1_wave4_delta_dm_vs_ctrl",
      slope_diff = delta_dm - delta_ctrl,
      stringsAsFactors = FALSE
    )
  }

  res_full <- tryCatch(prepost_chen_fit_lmm(data, outcome, bl), error = function(e) NULL)
  if (!is.null(res_full)) {
    ps <- res_full$post_slope
    rows[[length(rows) + 1L]] <- data.frame(
      scenario = "primary_piecewise_lmm",
      slope_diff = if (length(ps)) as.numeric(ps[1L]) else NA_real_,
      stringsAsFactors = FALSE
    )
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Sensitivity.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$prepost_sensitivity <- list(table = tab)
  cli::cli_alert_success("Chen 敏感性分析完成")
  ctx
}

register_block("prepost_sensitivity", block_prepost_sensitivity, "Chen 敏感性")
