###############################################################################
#  environment_single_exposure_transform — 单环境毒物暴露 log 变换与四分位
#
#  register_block: "environment_single_exposure_transform"
#  对齐文献: 血镉 log10 四分位 logistic（NHANES 骨质疏松）
###############################################################################

block_environment_single_exposure_transform <- function(ctx, ...) {
  bl <- ctx$config$environment_single %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
  if (is.null(data) || !is.data.frame(data)) {
    stop("environment_single_exposure_transform: 无分析数据", call. = FALSE)
  }

  raw_col <- bl$exposure_col %||% (ctx$config$incidence %||% list())$index_var
  if (is.null(raw_col) || !raw_col %in% names(data)) {
    stop("environment_single_exposure_transform: 暴露列不存在: ", raw_col, call. = FALSE)
  }

  log_col <- bl$log_col %||% paste0("log10_", raw_col)
  min_pos <- bl$min_positive %||% 1e-6
  x <- as.numeric(data[[raw_col]])
  x[x <= 0 & is.finite(x)] <- min_pos
  data[[log_col]] <- log10(pmax(x, min_pos, na.rm = TRUE))

  qs <- stats::quantile(data[[log_col]], probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
  if (length(unique(qs)) < 5L) {
    cli::cli_alert_warning("log 暴露分位点重复，使用三等分")
    qs <- stats::quantile(data[[log_col]], probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
    grp <- cut(data[[log_col]], breaks = unique(qs), include.lowest = TRUE, labels = paste0("Q", 1:3))
  } else {
    grp <- cut(data[[log_col]], breaks = qs, include.lowest = TRUE, labels = paste0("Q", 1:4))
  }
  qcol <- bl$quartile_col %||% paste0(log_col, "_Q")
  data[[qcol]] <- as.character(grp)
  data[[qcol]][is.na(data[[log_col]])] <- NA_character_

  ctx$data$cleaned  <- data
  ctx$data$imputed  <- data
  ctx$data$mapped   <- data
  ctx$results$environment_single <- list(
    exposure_col = raw_col,
    log_col = log_col,
    quartile_col = qcol,
    n_valid = sum(is.finite(data[[log_col]]))
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  summ <- data.frame(
    variable = c(raw_col, log_col),
    n = c(sum(is.finite(x)), sum(is.finite(data[[log_col]]))),
    mean = c(mean(x, na.rm = TRUE), mean(data[[log_col]], na.rm = TRUE)),
    std_dev = c(stats::sd(x, na.rm = TRUE), stats::sd(data[[log_col]], na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(summ, file.path(out_dir, "Table_Single_Exposure_Summary.csv"), row.names = FALSE)
  cli::cli_alert_success("单暴露变换完成: {raw_col} → {log_col}（n={sum(is.finite(data[[log_col]]))}）")
  ctx
}

register_block(
  "environment_single_exposure_transform",
  block_environment_single_exposure_transform,
  "单环境毒物 log10 变换与四分位"
)
