###############################################################################
#  cits_model_fit — 比较中断时间序列（CITS）回归
###############################################################################

block_cits_model_fit <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  monthly <- ctx$data$cits_monthly
  if (is.null(monthly) || !nrow(monthly))
    stop("cits_model_fit: 请先运行 cits_aggregate_monthly", call. = FALSE)

  outcomes <- unique(monthly$outcome)
  rows <- list()
  for (oc in outcomes) {
    sub <- monthly[monthly$outcome == oc, , drop = FALSE]
    if (nrow(sub) < 12L) next
    fml <- stats::as.formula("rate ~ ban * post + ban * tau + post * tau")
    fit <- tryCatch(stats::lm(fml, data = sub), error = function(e) NULL)
    if (is.null(fit)) next
    cf <- summary(fit)$coefficients
    for (nm in rownames(cf)) {
      rows[[length(rows) + 1L]] <- data.frame(
        outcome = oc, term = nm,
        estimate = cf[nm, 1], se = cf[nm, 2], p_value = cf[nm, 4],
        stringsAsFactors = FALSE
      )
    }
    if (requireNamespace("sandwich", quietly = TRUE) && requireNamespace("lmtest", quietly = TRUE)) {
      nw <- tryCatch(lmtest::coeftest(fit, vcov = sandwich::NeweyWest(fit)), error = function(e) NULL)
      if (!is.null(nw)) {
        for (nm in rownames(nw)) {
          idx <- which(vapply(rows, function(r) r$outcome == oc && r$term == nm, logical(1L)))
          if (length(idx)) rows[[idx[1L]]]$se <- nw[nm, 2]
        }
      }
    }
  }
  res_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res_df, file.path(out_dir, "Table_CITS_Model_Coefficients.csv"), row.names = FALSE)

  ctx$results$cits_model_fit <- list(n_outcomes = length(outcomes), n_terms = nrow(res_df))
  cli::cli_alert_success("CITS 模型拟合完成")
  ctx
}

register_block("cits_model_fit", block_cits_model_fit, "CITS 回归模型")
