###############################################################################
#  ml_gbdt — sklearn GradientBoosting 风格的 R 实现（gbm / xgboost 回退）
#
#  文献 TCF 七模型中的 GBDT（NPJ-codes: GradientBoostingClassifier）
#  register_block: "ml_gbdt"
###############################################################################

block_ml_gbdt <- function(ctx, ...) {
  bl <- ctx$config$ml_gbdt %||% ctx$config$ml_models$gbdt %||% list()
  if (isFALSE(bl$enable %||% TRUE)) return(ctx)

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  if (!length(feats)) stop("ml_gbdt: feature_selection_final 为空", call. = FALSE)
  tr <- ctx$data$train
  te <- ctx$data$test
  if (is.null(tr) || is.null(te)) stop("ml_gbdt: 需要 train/test", call. = FALSE)

  y_tr <- as.integer(as.character(tr[[outcome_col]]) == ana | as.character(tr[[outcome_col]]) == "1")
  x_tr <- as.matrix(tr[, feats, drop = FALSE])
  x_te <- as.matrix(te[, feats, drop = FALSE])
  storage.mode(x_tr) <- "double"
  storage.mode(x_te) <- "double"
  x_tr[is.na(x_tr)] <- 0
  x_te[is.na(x_te)] <- 0

  seed <- as.integer(bl$seed %||% ctx$config$splitting$seed %||% 42L)[1L]
  set.seed(seed)

  if (requireNamespace("gbm", quietly = TRUE)) {
    df <- as.data.frame(x_tr)
    df$.y <- y_tr
    fit <- gbm::gbm(
      .y ~ .,
      data = df,
      distribution = "bernoulli",
      n.trees = as.integer(bl$n_trees %||% 100L)[1L],
      interaction.depth = as.integer(bl$interaction_depth %||% 3L)[1L],
      shrinkage = as.numeric(bl$learning_rate %||% 0.1)[1L],
      verbose = FALSE
    )
    p1 <- as.numeric(gbm::predict.gbm(
      fit, newdata = as.data.frame(x_te),
      n.trees = fit$n.trees, type = "response"
    ))
  } else if (requireNamespace("xgboost", quietly = TRUE)) {
    dtr <- xgboost::xgb.DMatrix(x_tr, label = y_tr)
    fit <- xgboost::xgb.train(
      params = list(objective = "binary:logistic", eval_metric = "auc", max_depth = 3L, eta = 0.1),
      data = dtr, nrounds = as.integer(bl$n_trees %||% 100L)[1L], verbose = 0L
    )
    p1 <- as.numeric(predict(fit, x_te))
  } else {
    stop("ml_gbdt: 需要 R 包 gbm 或 xgboost", call. = FALSE)
  }

  ctx$results$ml_gbdt <- list(model = fit, features = feats, pred_prob = p1)
  ctx <- .ml_register_model_probs(ctx, "GBDT", p = as.numeric(p1))
  cli::cli_alert_success("ml_gbdt: 完成（n_test={length(p1)}）")
  ctx
}

register_block("ml_gbdt", block_ml_gbdt, "GBDT（TCF 子模型）")
