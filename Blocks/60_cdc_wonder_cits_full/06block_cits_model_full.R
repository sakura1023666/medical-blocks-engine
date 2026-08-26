###############################################################################
#  cits_model_full — 完整 CITS（tau 基线趋势 + 组内 post 斜率 + Newey-West）
###############################################################################

block_cits_model_full <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/cdc_wonder_cits_utils.R"), local = FALSE)

  records <- ctx$data$cleaned
  if (is.null(records) || !"Birth_month" %in% names(records))
    records <- ctx$data$wonder_raw %||% ctx$data$raw
  if (is.null(records)) stop("cits_model_full: 无数据", call. = FALSE)

  monthly <- .cits_prepare_monthly_rates(records, bl)
  ctx$data$cits_monthly <- monthly

  outcomes <- unique(monthly$outcome)
  coef_all <- list()
  did_all <- list()
  for (oc in outcomes) {
    fit <- .cits_fit_full(monthly, oc)
    cf <- fit$coefficients
    cf$outcome <- oc
    coef_all[[length(coef_all) + 1L]] <- cf
    did_all[[length(did_all) + 1L]] <- .cits_did_change(monthly, oc)
  }

  coef_df <- do.call(rbind, coef_all)
  did_df <- do.call(rbind, did_all)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(coef_df, file.path(out_dir, "Table_CITS_Full_Model_Coefficients.csv"), row.names = FALSE)
  utils::write.csv(did_df, file.path(out_dir, "Table_CITS_DID_Change_per10k.csv"), row.names = FALSE)

  ctx$results$cits_model_full <- list(coefficients = coef_df, did = did_df)
  cli::cli_alert_success("完整 CITS 模型（per 10,000 + DID）完成")
  ctx
}

register_block("cits_model_full", block_cits_model_full, "完整 CITS 回归")
