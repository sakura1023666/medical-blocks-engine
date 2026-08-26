###############################################################################
#  competing_models_123_death — Model 1–6（死亡）Competing + Standard Cox
###############################################################################

block_competing_models_123_death <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_models_123_death: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  if (!exists(".competing_fit_models_16", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/55_competing_risk_full/09block_competing_models_123.R"), local = FALSE)
  }
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  index_var <- bl$index_var %||% "TyG"
  death_cause <- as.integer(bl$death_cause %||% 2L)[1L]
  horizons <- as.integer(bl$model_horizons %||% c(7L, 14L, 28L))
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  exp_q <- bl$exposure_var %||% paste0(index_var, "_quartile")
  exp_t <- bl$trajectory_var %||% paste0(index_var, "_trajectory")
  covs <- ctx$results$competing_model_covs %||% .competing_resolve_model_covs(data, bl, ctx)
  ctx$results$competing_model_covs <- covs

  tab_q <- if (exp_q %in% names(data)) {
    .competing_fit_models_16(
      data, time_var, event_col, exp_q, death_cause,
      file.path(out_dir, paste0("Table_Models_123_", index_var, "_quartile_death.csv")),
      horizons = horizons, covs_by_model = covs, ctx = ctx, bl = bl
    )
  } else data.frame(note = "missing quartile", stringsAsFactors = FALSE)

  tab_t <- if (exp_t %in% names(data)) {
    .competing_fit_models_16(
      data, time_var, event_col, exp_t, death_cause,
      file.path(out_dir, paste0("Table_Models_123_", index_var, "_trajectory_death.csv")),
      horizons = horizons, covs_by_model = covs, ctx = ctx, bl = bl
    )
  } else NULL

  ctx$results$competing_models_123_death <- list(table = tab_q)
  ctx$results$competing_models_123_death_trajectory <- list(table = tab_t)
  cli::cli_alert_success("Model 1–6（死亡 Competing+Standard）完成")
  ctx
}

register_block("competing_models_123_death", block_competing_models_123_death, "Model 1–6（死亡）")
