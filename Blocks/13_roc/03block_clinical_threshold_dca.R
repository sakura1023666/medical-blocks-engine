###############################################################################
#  clinical_threshold_dca — 连续预测因子 ROC + 决策曲线（临床阈值）
#
#  register_block: "clinical_threshold_dca"
#  方法目录: Blocks/13_roc/
#
#  config$clinical_threshold_dca = list(
#    predictors = c("SSD12", "Whiteley8", "PHQ15"),
#    outcome = "WHODAS_high",   # 0/1；或自动按 outcome_cut 从连续 Y 二分
#    outcome_continuous = "WHODAS",
#    outcome_cut = "median",
#    thresholds = seq(0.05, 0.95, by = 0.05)
#  )
###############################################################################

block_clinical_threshold_dca <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$clinical_threshold_dca %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("clinical_threshold_dca: 无数据", call. = FALSE)

  preds <- as.character(bl$predictors %||% character(0))
  preds <- preds[preds %in% names(data)]
  if (!length(preds)) stop("clinical_threshold_dca: predictors 为空", call. = FALSE)

  ybin <- as.character(bl$outcome %||% "")[1L]
  if (!nzchar(ybin) || !ybin %in% names(data)) {
    ycont <- as.character(bl$outcome_continuous %||% "")[1L]
    if (!ycont %in% names(data)) stop("clinical_threshold_dca: 无结局列", call. = FALSE)
    yc <- suppressWarnings(as.numeric(data[[ycont]]))
    cut <- bl$outcome_cut %||% "median"
    thr <- if (identical(cut, "median")) stats::median(yc, na.rm = TRUE) else as.numeric(cut)
    ybin <- paste0(ycont, "_high")
    data[[ybin]] <- as.integer(yc >= thr)
  }

  out_tab <- file.path(ctx$output_dir %||% ".", "Tables")
  out_fig <- file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

  if (!requireNamespace("pROC", quietly = TRUE)) stop("需要 pROC", call. = FALSE)

  roc_rows <- list()
  for (p in preds) {
    x <- suppressWarnings(as.numeric(data[[p]]))
    y <- suppressWarnings(as.integer(data[[ybin]]))
    ok <- is.finite(x) & !is.na(y)
    if (sum(ok) < 30L || length(unique(y[ok])) < 2L) next
    rr <- pROC::roc(y[ok], x[ok], quiet = TRUE, direction = "<")
    auc <- as.numeric(pROC::auc(rr))
    ci <- as.numeric(pROC::ci.auc(rr, quiet = TRUE))
    youden <- which.max(rr$sensitivities + rr$specificities - 1)
    cut_x <- as.numeric(rr$thresholds[youden])
    roc_rows[[length(roc_rows) + 1L]] <- data.frame(
      predictor = p, AUC = auc, AUC_lo = ci[1], AUC_hi = ci[3],
      youden_cut = cut_x,
      sens = as.numeric(rr$sensitivities[youden]),
      spec = as.numeric(rr$specificities[youden]),
      n = sum(ok)
    )
    pdf(file.path(out_fig, paste0("Figure_ROC_", p, ".pdf")), width = 6, height = 6)
    plot(rr, main = paste0("ROC: ", p, " (AUC=", round(auc, 3), ")"))
    grDevices::dev.off()
  }
  roc_df <- if (length(roc_rows)) do.call(rbind, roc_rows) else data.frame()
  if (nrow(roc_df)) utils::write.csv(roc_df, file.path(out_tab, "Table_clinical_ROC.csv"), row.names = FALSE)

  # 简易 DCA（净获益）：对每个预测因子标准化为 0-1 风险代理
  thr_grid <- as.numeric(bl$thresholds %||% seq(0.05, 0.95, by = 0.05))
  dca_rows <- list()
  y <- suppressWarnings(as.integer(data[[ybin]]))
  preval <- mean(y == 1L, na.rm = TRUE)
  for (p in preds) {
    x <- suppressWarnings(as.numeric(data[[p]]))
    ok <- is.finite(x) & !is.na(y)
    xs <- x[ok]; ys <- y[ok]
    # min-max 到 (0,1)
    rng <- range(xs, na.rm = TRUE)
    if (diff(rng) < .Machine$double.eps) next
    risk <- (xs - rng[1]) / (rng[2] - rng[1])
    for (pt in thr_grid) {
      pred_pos <- risk >= pt
      tp <- sum(pred_pos & ys == 1L)
      fp <- sum(pred_pos & ys == 0L)
      n <- length(ys)
      nb <- tp / n - fp / n * (pt / (1 - pt))
      dca_rows[[length(dca_rows) + 1L]] <- data.frame(
        predictor = p, threshold = pt, net_benefit = nb
      )
    }
  }
  # treat all / none
  for (pt in thr_grid) {
    dca_rows[[length(dca_rows) + 1L]] <- data.frame(
      predictor = "Treat all", threshold = pt,
      net_benefit = preval - (1 - preval) * (pt / (1 - pt))
    )
    dca_rows[[length(dca_rows) + 1L]] <- data.frame(
      predictor = "Treat none", threshold = pt, net_benefit = 0
    )
  }
  dca_df <- do.call(rbind, dca_rows)
  utils::write.csv(dca_df, file.path(out_tab, "Table_clinical_DCA.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(dca_df)) {
    p <- ggplot2::ggplot(dca_df, ggplot2::aes(threshold, net_benefit, colour = predictor)) +
      ggplot2::geom_line() + ggplot2::theme_bw() +
      ggplot2::labs(title = "Decision curve", x = "Threshold probability", y = "Net benefit")
    ggplot2::ggsave(file.path(out_fig, "Figure_clinical_DCA.pdf"), p, width = 7, height = 5)
  }

  ctx$results$clinical_threshold_dca <- list(roc = roc_df, dca = dca_df, outcome = ybin)
  cli::cli_alert_success("clinical_threshold_dca: ROC {nrow(roc_df)} 个预测因子 + DCA")
  ctx
}

register_block(
  "clinical_threshold_dca",
  block_clinical_threshold_dca,
  "临床阈值 ROC 与决策曲线 DCA"
)
