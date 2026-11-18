###############################################################################
#  ml_naive_bayes — Bernoulli/Gaussian NB（文献 TCF 七模型之一）
#
#  来源：Wang 2025 npj Digit Med TCF（公开代码 NPJ-codes → BernoulliNB）
#  register_block: "ml_naive_bayes"
#  典型流水线: train_validation → … → ml_models_bundle（methods 含 naive_bayes）
###############################################################################

block_ml_naive_bayes <- function(ctx, ...) {
  if (!requireNamespace("e1071", quietly = TRUE) && !requireNamespace("naivebayes", quietly = TRUE)) {
    ## 无专用包时走 Python CLI（与 TCF bundle 同源）
    cli::cli_alert_warning("ml_naive_bayes: 建议安装 e1071 或在 ml_topsis_fusion 捆绑训练中覆盖 NB。")
  }
  bl <- ctx$config$ml_naive_bayes %||% ctx$config$ml_models$naive_bayes %||% list()
  if (isFALSE(bl$enable %||% TRUE)) return(ctx)

  outcome_col <- ctx$config$data$outcome_column
  ana <- ctx$config$project$analysis_group %||% "1"
  feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  if (!length(feats)) stop("ml_naive_bayes: feature_selection_final 为空", call. = FALSE)
  tr <- ctx$data$train
  te <- ctx$data$test
  if (is.null(tr) || is.null(te)) stop("ml_naive_bayes: 需要 train/test", call. = FALSE)

  y_tr <- as.integer(as.character(tr[[outcome_col]]) == as.character(ana) | as.character(tr[[outcome_col]]) == "1")
  x_tr <- as.matrix(tr[, feats, drop = FALSE])
  x_te <- as.matrix(te[, feats, drop = FALSE])
  storage.mode(x_tr) <- "double"
  storage.mode(x_te) <- "double"

  ## 二值化（BernoulliNB 口径）；连续特征按训练集中位数切
  med <- apply(x_tr, 2L, median, na.rm = TRUE)
  x_tr_b <- sweep(x_tr, 2L, med, FUN = ">") * 1
  x_te_b <- sweep(x_te, 2L, med, FUN = ">") * 1
  x_tr_b[is.na(x_tr_b)] <- 0
  x_te_b[is.na(x_te_b)] <- 0

  if (requireNamespace("e1071", quietly = TRUE)) {
    fit <- e1071::naiveBayes(x = as.data.frame(x_tr_b), y = factor(y_tr, levels = c(0L, 1L)))
    pr <- predict(fit, newdata = as.data.frame(x_te_b), type = "raw")
    p1 <- if (is.matrix(pr)) pr[, ncol(pr)] else as.numeric(pr)
  } else if (requireNamespace("naivebayes", quietly = TRUE)) {
    fit <- naivebayes::naive_bayes(x = as.data.frame(x_tr_b), y = factor(y_tr, levels = c(0L, 1L)))
    pr <- predict(fit, newdata = as.data.frame(x_te_b), type = "prob")
    p1 <- as.numeric(pr[, "1"])
  } else {
    ## 极简平滑频率后备（仅保证流水线可跑；正式分析请装 e1071）
    cli::cli_alert_warning("ml_naive_bayes: 使用平滑频率后备实现（请安装 e1071）")
    p_pos <- (sum(y_tr == 1L) + 1) / (length(y_tr) + 2)
    p1 <- rep(p_pos, nrow(x_te_b))
    fit <- list(type = "fallback_prior", p_pos = p_pos, median_cut = med)
  }

  ctx$results$ml_naive_bayes <- list(
    model = fit,
    features = feats,
    median_cut = med,
    pred_prob = as.numeric(p1),
    pred_class = as.integer(as.numeric(p1) > 0.5)
  )
  ctx <- .ml_register_model_probs(ctx, "NB", p = as.numeric(p1))
  cli::cli_alert_success("ml_naive_bayes: 完成（n_test={nrow(x_te_b)}）")
  ctx
}

register_block("ml_naive_bayes", block_ml_naive_bayes, "Naive Bayes（TCF 子模型）")
