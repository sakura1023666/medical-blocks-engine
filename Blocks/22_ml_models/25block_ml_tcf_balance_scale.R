###############################################################################
#  ml_tcf_balance_scale — 训练集 MinMax + SMOTE 1:1（对齐 Wang 2025 / NPJ-codes）
#
#  公开代码：SMOTE(sampling_strategy=1, k_neighbors=20) + MinMaxScaler(fit on train)
#  实现：R base MinMax + smotefamily::SMOTE(K = k_neighbors)；external_all 跳过
#
#  register_block: "ml_tcf_balance_scale"
#  位置：feature_selection_entropy_stepwise 之后、ml_models_bundle 之前
###############################################################################

.mltcf25_minmax_fit_transform <- function(X_train, X_test) {
  X_train <- as.matrix(X_train)
  X_test <- as.matrix(X_test)
  storage.mode(X_train) <- "double"
  storage.mode(X_test) <- "double"
  med <- apply(X_train, 2L, stats::median, na.rm = TRUE)
  for (j in seq_len(ncol(X_train))) {
    if (anyNA(X_train[, j])) X_train[is.na(X_train[, j]), j] <- med[[j]]
    if (anyNA(X_test[, j])) X_test[is.na(X_test[, j]), j] <- med[[j]]
  }
  mn <- apply(X_train, 2L, min, na.rm = TRUE)
  mx <- apply(X_train, 2L, max, na.rm = TRUE)
  den <- pmax(mx - mn, 1e-12)
  Xtr_s <- sweep(sweep(X_train, 2L, mn, `-`), 2L, den, `/`)
  Xte_s <- sweep(sweep(X_test, 2L, mn, `-`), 2L, den, `/`)
  list(train = Xtr_s, test = Xte_s, min = mn, max = mx, median = med)
}

.mltcf25_smote_1to1 <- function(X, y, k_neighbors = 20L, seed = 42L) {
  if (!requireNamespace("smotefamily", quietly = TRUE)) {
    stop("ml_tcf_balance_scale: 需要 R 包 smotefamily（对齐 NPJ-codes SMOTE）", call. = FALSE)
  }
  y <- as.integer(y)
  tab <- table(y)
  if (length(tab) < 2L) stop("ml_tcf_balance_scale: 训练集需两类", call. = FALSE)
  ## smotefamily::SMOTE 的 K 为近邻数；不可 ≥ 少数类 n
  k <- as.integer(k_neighbors)[1L]
  k <- max(1L, min(k, as.integer(min(tab)) - 1L))
  df <- as.data.frame(X)
  df$class <- factor(y, levels = c(0L, 1L))
  set.seed(as.integer(seed)[1L])
  ## dup_size：使少数类扩增到与多数类接近（1:1）
  n_min <- as.integer(min(tab))
  n_maj <- as.integer(max(tab))
  dup <- max(0L, as.integer(ceiling(n_maj / n_min) - 1L))
  res <- smotefamily::SMOTE(df[, -ncol(df), drop = FALSE], df$class, K = k, dup_size = dup)
  syn <- res$data
  ## 末列一般为 class
  cls_col <- names(syn)[ncol(syn)]
  yb <- as.integer(as.character(syn[[cls_col]]))
  Xb <- as.matrix(syn[, seq_len(ncol(syn) - 1L), drop = FALSE])
  storage.mode(Xb) <- "double"
  list(X = Xb, y = yb, k_neighbors = k, dup_size = dup)
}

block_ml_tcf_balance_scale <- function(ctx, ...) {
  cfg <- ctx$config$ml_tcf_balance_scale %||% ctx$config$ml_models$tcf_balance_scale %||% list()
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  if (isTRUE(ctx$results$train_validation_external_all)) {
    cli::cli_alert_info("ml_tcf_balance_scale: external_all 外验整库，跳过 MinMax/SMOTE")
    return(ctx)
  }

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  ref <- as.character(ctx$config$project$reference_group %||% "0")[1L]
  feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  if (!length(feats)) stop("ml_tcf_balance_scale: feature_selection_final 为空", call. = FALSE)
  tr <- ctx$data$train
  te <- ctx$data$test
  if (is.null(tr) || is.null(te)) stop("ml_tcf_balance_scale: 需要 train/test", call. = FALSE)
  miss <- setdiff(c(outcome_col, feats), names(tr))
  if (length(miss)) {
    stop("ml_tcf_balance_scale: 训练集缺列: ", paste(miss, collapse = ", "), call. = FALSE)
  }

  y_tr <- as.integer(
    as.character(tr[[outcome_col]]) == ana | as.character(tr[[outcome_col]]) == "1"
  )
  X_tr <- tr[, feats, drop = FALSE]
  X_te <- te[, feats, drop = FALSE]
  scaled <- .mltcf25_minmax_fit_transform(X_tr, X_te)

  k <- as.integer(cfg$k_neighbors %||% 20L)[1L]
  seed <- as.integer(cfg$seed %||% ctx$config$splitting$seed %||% 42L)[1L]
  sm <- .mltcf25_smote_1to1(scaled$train, y_tr, k_neighbors = k, seed = seed)

  tr_new <- as.data.frame(sm$X)
  names(tr_new) <- feats
  tr_new[[outcome_col]] <- ifelse(sm$y == 1L, ana, ref)
  tr_new$Group <- factor(ifelse(sm$y == 1L, ana, ref), levels = c(ref, ana))

  te_new <- te
  for (f in feats) te_new[[f]] <- scaled$test[, f]

  out_dir <- file.path(ctx$output_dir %||% ".", "Models", "TCF_balance")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      n_train_before = nrow(tr),
      n_train_after = nrow(tr_new),
      n_test = nrow(te_new),
      k_neighbors = sm$k_neighbors,
      dup_size = sm$dup_size,
      stringsAsFactors = FALSE
    ),
    file.path(out_dir, "balance_summary.csv"),
    row.names = FALSE
  )

  ctx$data$train <- tr_new
  ctx$data$test <- te_new
  ctx$results$ml_tcf_balance_scale <- list(
    n_train_before = nrow(tr),
    n_train_after = nrow(tr_new),
    n_test = nrow(te_new),
    k_neighbors = sm$k_neighbors,
    dup_size = sm$dup_size,
    features = feats,
    out_dir = out_dir
  )
  cli::cli_alert_success(
    "ml_tcf_balance_scale: MinMax+SMOTE K={sm$k_neighbors}；train {nrow(tr)} → {nrow(tr_new)}；test={nrow(te_new)}"
  )
  ctx
}

register_block("ml_tcf_balance_scale", block_ml_tcf_balance_scale, "TCF MinMax+SMOTE 对齐公开代码")
