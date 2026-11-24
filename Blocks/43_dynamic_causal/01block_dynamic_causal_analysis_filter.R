###############################################################################
#  dynamic_causal_analysis_filter — baseline vs change 队列切片（不同样本量）
###############################################################################

block_dynamic_causal_analysis_filter <- function(ctx, ...) {
  bl <- ctx$config$dynamic_causal %||% list()
  at <- tolower(as.character(bl$analysis_type %||% "change")[1L])
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("dynamic_causal_analysis_filter: 无数据", call. = FALSE)

  if (at == "baseline") {
    data$analysis_index <- data$CMI_baseline
    data$analysis_tert <- data$CMI_baseline_tert %||% NA
    # 模拟原文 baseline 分析更大样本：保留全部有 baseline CMI 者
    keep <- is.finite(data$CMI_baseline)
  } else {
    data$analysis_index <- data$Total_CMI
    data$analysis_tert <- data$Total_CMI_tert
    # change 分析需双波次 + 模拟较小样本（约 60%）
    keep <- is.finite(data$CMI_baseline) & is.finite(data$CMI_wave2) & is.finite(data$Total_CMI)
    if (sum(keep) > 20L) {
      set.seed(bl$change_subsample_seed %||% 101046L)
      idx <- which(keep)
      frac <- as.numeric(bl$change_sample_frac %||% 0.62)
      sub <- sample(idx, size = max(10L, floor(frac * length(idx))))
      keep <- rep(FALSE, nrow(data))
      keep[sub] <- TRUE
    }
  }

  data <- data[keep, , drop = FALSE]
  if (nrow(data) < 10L) stop("dynamic_causal_analysis_filter: 有效样本不足 n=", nrow(data), call. = FALSE)

  # 三分位基于当前 analysis_index
  ai <- data$analysis_index
  tert <- stats::quantile(ai, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)
  brk <- unique(as.numeric(tert))
  if (length(brk) >= 4L) {
    data$analysis_tert <- cut(ai, breaks = brk, include.lowest = TRUE,
                              labels = c("T1_low", "T2_mid", "T3_high"))
  } else {
    med <- stats::median(ai, na.rm = TRUE)
    data$analysis_tert <- ifelse(ai <= med, "T1_low", "T3_high")
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$config$survival$index_var <- "analysis_index"
  ctx$config$dynamic_causal_cox$tertile_var <- "analysis_tert"
  ctx$config$dynamic_causal_cox$continuous_var <- "analysis_index"
  ctx$config$rcs_prognosis$index_var <- "analysis_index"
  ctx$results$dynamic_causal_analysis <- list(
    analysis_type = at, n = nrow(data), events = sum(as.numeric(data$CVD_event) %in% c(1, "Case"), na.rm = TRUE)
  )
  cli::cli_alert_success("动态因果队列 [{at}] n={nrow(data)}")
  ctx
}

register_block(
  "dynamic_causal_analysis_filter",
  block_dynamic_causal_analysis_filter,
  "baseline/change 队列切片"
)
