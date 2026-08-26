###############################################################################
#  ml_small_sample_metrics.R — 小样本 ML 分类指标（Youden 切点 + Bootstrap CI）
#
#  复用于：单指标 ml_dual_batch 后处理、全变量 all_vars_ml、发病/预后课题。
#  研究目录只保留产出；逻辑一律 source 本文件。
###############################################################################

#' Youden 最优概率切点（pROC，direction="<"：高风险=高概率）
ml_youden_threshold <- function(y, p) {
  y <- as.integer(y)
  p <- as.numeric(p)
  r <- pROC::roc(y, p, quiet = TRUE, direction = "<")
  cd <- pROC::coords(r, "best", ret = "threshold", best.method = "youden", transpose = FALSE)
  thr <- as.numeric(cd)[1L]
  if (!is.finite(thr)) 0.5 else thr
}

#' 固定切点下的 AUC / accuracy / sensitivity / specificity / F1
ml_metrics_at_threshold <- function(y, p, thr) {
  y <- as.integer(y)
  p <- as.numeric(p)
  pred <- as.integer(p >= thr)
  tp <- sum(pred == 1L & y == 1L)
  tn <- sum(pred == 0L & y == 0L)
  fp <- sum(pred == 1L & y == 0L)
  fn <- sum(pred == 0L & y == 1L)
  n <- length(y)
  auc_val <- NA_real_
  if (length(unique(y)) >= 2L) {
    auc_val <- tryCatch(
      as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE, direction = "<"))),
      error = function(e) NA_real_
    )
  }
  list(
    auc = auc_val,
    acc = (tp + tn) / n,
    sens = if ((tp + fn) > 0L) tp / (tp + fn) else NA_real_,
    spec = if ((tn + fp) > 0L) tn / (tn + fp) else NA_real_,
    f1 = if ((2L * tp + fp + fn) > 0L) 2L * tp / (2L * tp + fp + fn) else NA_real_
  )
}

#' Bootstrap 百分位 95% CI（B 次有放回重抽样，切点固定）
ml_bootstrap_metrics <- function(y, p, thr, B = 1000L, seed = 42L) {
  y <- as.integer(y)
  p <- as.numeric(p)
  n <- length(y)
  pt <- ml_metrics_at_threshold(y, p, thr)
  set.seed(seed)
  mats <- matrix(NA_real_, nrow = B, ncol = 5L,
                 dimnames = list(NULL, c("auc", "acc", "sens", "spec", "f1")))
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    mats[b, ] <- unlist(ml_metrics_at_threshold(y[idx], p[idx], thr))[1:5]
  }
  qci <- function(x) {
    x <- x[is.finite(x)]
    if (length(x) < 10L) return(c(NA_real_, NA_real_))
    as.numeric(quantile(x, probs = c(0.025, 0.975), na.rm = TRUE, names = FALSE))
  }
  list(point = pt, ci = apply(mats, 2L, qci, simplify = FALSE))
}

#' 点估计 (lo-hi) 字符串
ml_fmt_metric_ci <- function(est, ci) {
  if (!is.finite(est) || length(ci) != 2L || !all(is.finite(ci))) return("\u2014")
  sprintf("%.3f (%.3f-%.3f)", est, ci[1], ci[2])
}

#' 合并 Python + R 侧保存的模型概率
ml_load_all_probs <- function(out_dir,
                              py_file = "ml_python_results.csv",
                              rf_file = "ml_all_probs.csv",
                              rf_model = "RF") {
  py_path <- file.path(out_dir, py_file)
  rf_path <- file.path(out_dir, rf_file)
  if (!file.exists(py_path)) {
    stop("Missing ", py_path, call. = FALSE)
  }
  py <- read.csv(py_path, stringsAsFactors = FALSE)
  if (file.exists(rf_path)) {
    rf <- read.csv(rf_path, stringsAsFactors = FALSE)
    rf <- rf[rf$model == rf_model, , drop = FALSE]
    py <- rbind(py, rf)
  }
  py
}

#' 单行 bootstrap 表（Model 列由调用方拼）
ml_perf_row_bootstrap <- function(y, p, thr, B = 1000L, seed = 42L) {
  b <- ml_bootstrap_metrics(y, p, thr, B = B, seed = seed)
  data.frame(
    AUC = ml_fmt_metric_ci(b$point$auc, b$ci$auc),
    accuracy = ml_fmt_metric_ci(b$point$acc, b$ci$acc),
    Sensitivity = ml_fmt_metric_ci(b$point$sens, b$ci$sens),
    Specificity = ml_fmt_metric_ci(b$point$spec, b$ci$spec),
    F1 = ml_fmt_metric_ci(b$point$f1, b$ci$f1),
    stringsAsFactors = FALSE
  )
}

#' 从 config$ml_small_sample 取默认值
ml_small_sample_cfg <- function(cfg, key, default = NULL) {
  ms <- cfg$ml_small_sample
  if (is.null(ms) || is.null(ms[[key]])) default else ms[[key]]
}

#' 默认 6 模型顺序（与 Figure 4 / Table 4 一致）
ml_small_sample_model_order <- function(cfg = list()) {
  ord <- ml_small_sample_cfg(cfg, "model_order", NULL)
  if (!is.null(ord) && length(ord)) return(as.character(ord))
  c("AdaBoost", "TabPFN", "CatBoost", "XGBoost", "LightGBM", "RF")
}
