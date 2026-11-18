###############################################################################
#  skew_log1p — 基线表之后对指定偏态连续列做 log1p（Table1/S1 仍用原始单位）
#
#  典型顺序: imputation → train_validation → baseline_binary → skew_log1p → UV/ML
#  config$skew_log1p = list(enable=TRUE, vars=c("EBV_DNA_T0", ...))
###############################################################################

block_skew_log1p <- function(ctx, ...) {
  cfg <- ctx$config
  sk <- cfg$skew_log1p %||% list()
  if (isFALSE(sk$enable %||% TRUE)) {
    cli::cli_alert_info("skew_log1p: 已关闭，跳过。")
    return(ctx)
  }

  vars <- unique(as.character(sk$vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  if (!length(vars)) {
    cli::cli_alert_warning("skew_log1p: 未配置 vars，跳过。")
    return(ctx)
  }

  if (length(ctx$results$skew_log1p_applied %||% character(0))) {
    cli::cli_alert_info(
      "skew_log1p: 本流水线已应用过 ({paste(ctx$results$skew_log1p_applied, collapse=', ')})，跳过。"
    )
    return(ctx)
  }

  .apply_df <- function(df) {
    if (is.null(df) || !is.data.frame(df)) {
      return(list(data = df, done = character(0)))
    }
    done <- character(0)
    for (v in vars) {
      if (!v %in% names(df)) next
      x <- suppressWarnings(as.numeric(df[[v]]))
      ok <- is.finite(x) & x > -1 + .Machine$double.eps
      if (!any(ok)) next
      x[ok] <- log1p(x[ok])
      df[[v]] <- x
      done <- c(done, v)
    }
    list(data = df, done = unique(done))
  }

  all_done <- character(0)
  for (sl in c("imputed", "cleaned", "mapped", "train", "test")) {
    if (is.null(ctx$data[[sl]])) next
    res <- .apply_df(ctx$data[[sl]])
    ctx$data[[sl]] <- res$data
    all_done <- unique(c(all_done, res$done))
    if (length(res$done)) {
      cli::cli_alert_success(
        "skew_log1p: {sl} ← log1p({paste(res$done, collapse=', ')})"
      )
    }
  }

  ctx$results$skew_log1p_applied <- all_done
  if (!length(all_done)) {
    cli::cli_alert_warning("skew_log1p: 未变换任何列（列名不匹配或数据为空）。")
  } else {
    out_dir <- ctx$output_dir %||% "."
    data_dir <- file.path(out_dir, "Data")
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
    utils::write.csv(
      data.frame(variable = all_done, method = "log1p", stringsAsFactors = FALSE),
      file.path(data_dir, "skew_log1p_applied.csv"),
      row.names = FALSE,
      fileEncoding = "UTF-8"
    )
  }
  ctx
}

register_block(
  "skew_log1p",
  block_skew_log1p,
  "基线后对偏态连续变量 log1p（Table1/S1 保持原始单位）"
)
