###############################################################################
#  ml_topsis_fusion — TOPSIS 分类融合（TCF）
#
#  文献：Wang et al. npj Digit Med 2025;8:228 (PMID 40295871)
#  公开代码：Blocks/22_ml_models/_extract_npj_tcf/ + python/ml_tcf/topsis.py
#
#  前置：各子模型已写入 ctx$results$ml_model_probs$<NAME>
#  默认六指标等权 TOPSIS → alpha → 加权概率；阈值 0.5
#
#  register_block: "ml_topsis_fusion"
#  建议流水线位置：ml_models_bundle 之后、performance_ml 之前
###############################################################################

.mltcf24_binary_metrics <- function(y, p, thr = 0.5) {
  y <- as.integer(y)
  p <- as.numeric(p)
  pred <- as.integer(p > thr)
  auc <- tryCatch(as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE))), error = function(e) NA_real_)
  tp <- sum(pred == 1L & y == 1L)
  tn <- sum(pred == 0L & y == 0L)
  fp <- sum(pred == 1L & y == 0L)
  fn <- sum(pred == 0L & y == 1L)
  prec <- if ((tp + fp) == 0L) 0 else tp / (tp + fp)
  sen <- if ((tp + fn) == 0L) 0 else tp / (tp + fn)
  spe <- if ((tn + fp) == 0L) 0 else tn / (tn + fp)
  f1 <- if ((prec + sen) == 0) 0 else 2 * prec * sen / (prec + sen)
  acc <- mean(pred == y)
  c(AUC = auc, F1 = f1, ACC = acc, PRE = prec, SEN = sen, SPE = spe)
}

.mltcf24_topsis_alpha <- function(metric_mat) {
  ## rows=models, cols=AUC F1 ACC PRE SEN SPE；等权（文献 1/6）
  m <- as.matrix(metric_mat)
  w <- rep(1 / ncol(m), ncol(m))
  pis <- apply(m, 2L, max, na.rm = TRUE)
  nis <- apply(m, 2L, min, na.rm = TRUE)
  d_pis <- sqrt(rowSums(sweep(sweep(m, 2L, pis, `-`) ^ 2, 2L, w, `*`)))
  d_nis <- sqrt(rowSums(sweep(sweep(m, 2L, nis, `-`) ^ 2, 2L, w, `*`)))
  score <- d_nis / (d_nis + d_pis + 1e-12)
  alpha <- score / sum(score)
  stats::setNames(as.numeric(alpha), rownames(m))
}

block_ml_topsis_fusion <- function(ctx, ...) {
  cfg <- ctx$config$ml_topsis_fusion %||% list()
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  probs <- ctx$results$ml_model_probs %||% list()
  ## 文献七模型别名
  want <- cfg$models %||% c("DT", "RF", "XGB", "LGBM", "SVM", "NB", "GBDT")
  alias <- c(
    DT = "DT", dt = "DT", ml_dt = "DT",
    RF = "RF", rf = "RF", ml_rf = "RF",
    XGB = "XGB", xgboost = "XGB", ml_xgboost = "XGB", xgb = "XGB",
    LGBM = "LGBM", lightgbm = "LGBM", ml_lightgbm = "LGBM", lgbm = "LGBM",
    SVM = "SVM", rsvm = "SVM", ml_rsvm = "SVM", svm = "SVM",
    NB = "NB", naive_bayes = "NB", ml_naive_bayes = "NB",
    GBDT = "GBDT", gbdt = "GBDT", ml_gbdt = "GBDT"
  )
  mapped <- list()
  for (nm in names(probs)) {
    key <- alias[[nm]] %||% alias[[tolower(nm)]] %||% toupper(nm)
    if (key %in% want) mapped[[key]] <- as.numeric(probs[[nm]])
  }
  if (!length(mapped)) {
    cli::cli_alert_warning("ml_topsis_fusion: ml_model_probs 为空，跳过")
    return(ctx)
  }

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  te <- ctx$data$test
  y <- as.integer(as.character(te[[outcome_col]]) == ana | as.character(te[[outcome_col]]) == "1")
  thr <- as.numeric(cfg$threshold %||% 0.5)[1L]

  metric_rows <- lapply(names(mapped), function(m) .mltcf24_binary_metrics(y, mapped[[m]], thr))
  metric_mat <- do.call(rbind, metric_rows)
  rownames(metric_mat) <- names(mapped)

  alpha <- .mltcf24_topsis_alpha(metric_mat)
  ## 加权融合
  n <- length(y)
  p <- numeric(n)
  for (m in names(alpha)) p <- p + alpha[[m]] * mapped[[m]]
  pred <- as.integer(p > thr)
  tcf_met <- .mltcf24_binary_metrics(y, p, thr)

  ctx$results$ml_topsis_fusion <- list(
    alpha = alpha,
    metrics_submodels = metric_mat,
    metrics_tcf = tcf_met,
    pred_prob = p,
    pred_class = pred,
    threshold = thr,
    y_test = y
  )
  ctx$results$ml_model_probs$TCF <- p

  ## 落盘
  out_dir <- file.path(ctx$output_dir %||% ".", "Models", "TCF")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(metric_mat, file.path(out_dir, "metrics_submodels.csv"))
  utils::write.csv(data.frame(model = names(alpha), alpha = as.numeric(alpha)),
                   file.path(out_dir, "topsis_alpha.csv"), row.names = FALSE)
  utils::write.csv(as.data.frame(as.list(tcf_met)), file.path(out_dir, "metrics_tcf.csv"),
                   row.names = FALSE)

  cli::cli_alert_success(
    "ml_topsis_fusion: TCF AUC={round(tcf_met[['AUC']], 3)}；子模型={paste(names(alpha), collapse=',')}"
  )
  ctx
}

register_block("ml_topsis_fusion", block_ml_topsis_fusion, "TOPSIS 分类融合（TCF）")
