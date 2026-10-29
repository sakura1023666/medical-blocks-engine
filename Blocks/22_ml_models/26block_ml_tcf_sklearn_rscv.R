###############################################################################
#  ml_tcf_sklearn_rscv — 公开代码口径七模型 RandomizedSearchCV(cv=5) + TOPSIS
#
#  调用 python/ml_tcf/train_tcf_bundle.py（MinMax + SMOTE K=20 + RSCV + 等权 TOPSIS）
#  register_block: "ml_tcf_sklearn_rscv"
#  建议：feature_selection_entropy_stepwise 之后；可替代
#        ml_tcf_balance_scale + ml_models_bundle + ml_topsis_fusion
###############################################################################

.mltcf26_python <- function() {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  venv_py <- if (nzchar(root)) {
    file.path(root, ".venv", "bin", "python")
  } else {
    ""
  }
  cands <- c(
    Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = ""),
    venv_py,
    Sys.which("python3"),
    Sys.which("python")
  )
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (!length(cands)) stop("ml_tcf_sklearn_rscv: 找不到 python3", call. = FALSE)
  cands[[1L]]
}

.mltcf26_build_eval_all <- function(metric_df, n_train, n_test) {
  ## yardstick-ish long table for performance_ml
  rows <- list()
  for (m in rownames(metric_df)) {
    auc <- as.numeric(metric_df[m, "AUC"])
    rows[[length(rows) + 1L]] <- data.frame(
      .metric = "roc_auc", .estimator = "binary", .estimate = auc,
      dataset = "test", model = m, stringsAsFactors = FALSE
    )
    rows[[length(rows) + 1L]] <- data.frame(
      .metric = "roc_auc", .estimator = "binary", .estimate = NA_real_,
      dataset = "train", model = m, stringsAsFactors = FALSE
    )
  }
  dplyr::bind_rows(rows)
}

block_ml_tcf_sklearn_rscv <- function(ctx, ...) {
  cfg <- ctx$config$ml_tcf_sklearn_rscv %||% ctx$config$ml_models %||% list()
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  if (!length(feats)) stop("ml_tcf_sklearn_rscv: feature_selection_final 为空", call. = FALSE)

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  tr <- ctx$data$train
  te <- ctx$data$test
  if (is.null(tr) || is.null(te)) stop("ml_tcf_sklearn_rscv: 需要 train/test", call. = FALSE)

  miss_tr <- setdiff(feats, names(tr))
  miss_te <- setdiff(feats, names(te))
  if (length(miss_tr) || length(miss_te)) {
    stop(
      "ml_tcf_sklearn_rscv: 缺特征 train=", paste(miss_tr, collapse = ","),
      " test=", paste(miss_te, collapse = ","),
      call. = FALSE
    )
  }

  y_tr <- as.integer(as.character(tr[[outcome_col]]) == ana | as.character(tr[[outcome_col]]) == "1")
  y_te <- as.integer(as.character(te[[outcome_col]]) == ana | as.character(te[[outcome_col]]) == "1")

  out_dir <- file.path(ctx$output_dir %||% ".", "Models", "TCF_sklearn")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(out_dir, "_csv")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

  tr_csv <- cbind(as.data.frame(tr[, feats, drop = FALSE]), y = y_tr)
  te_csv <- cbind(as.data.frame(te[, feats, drop = FALSE]), y = y_te)
  ## 强制数值
  for (f in feats) {
    tr_csv[[f]] <- as.numeric(tr_csv[[f]])
    te_csv[[f]] <- as.numeric(te_csv[[f]])
  }
  utils::write.csv(tr_csv, file.path(tmp, "train.csv"), row.names = FALSE)
  utils::write.csv(te_csv, file.path(tmp, "valid.csv"), row.names = FALSE)

  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- ctx$config$project$root %||% getwd()
  py_script <- file.path(root, "python", "ml_tcf", "train_tcf_bundle.py")
  if (!file.exists(py_script)) stop("找不到 ", py_script, call. = FALSE)

  seed <- as.integer(cfg$seed %||% ctx$config$splitting$seed %||% 42L)[1L]
  cv <- as.integer(cfg$cv %||% ctx$config$ml_models$cv_folds %||% 5L)[1L]
  k_nn <- as.integer(cfg$k_neighbors %||% ctx$config$ml_tcf_balance_scale$k_neighbors %||% 20L)[1L]
  thr <- as.numeric(cfg$threshold %||% ctx$config$ml_topsis_fusion$threshold %||% 0.5)[1L]
  do_smote <- isTRUE(cfg$smote %||% TRUE)
  ## 默认 4：避免 RandomizedSearchCV n_jobs=-1 与其它课题抢满主机
  n_jobs <- as.integer(cfg$n_jobs %||% 4L)[1L]
  if (!is.finite(n_jobs) || n_jobs < 1L) n_jobs <- 4L

  args <- c(
    py_script,
    "--train", file.path(tmp, "train.csv"),
    "--valid", file.path(tmp, "valid.csv"),
    "--out-dir", out_dir,
    "--outcome", "y",
    "--features", paste(feats, collapse = ","),
    "--cv", as.character(cv),
    "--seed", as.character(seed),
    "--threshold", as.character(thr),
    "--k-neighbors", as.character(k_nn),
    "--n-jobs", as.character(n_jobs),
    "--write-proba"
  )
  if (do_smote) args <- c(args, "--smote")

  met_path <- file.path(out_dir, "metrics_valid.csv")
  alpha_path <- file.path(out_dir, "topsis_alpha.csv")
  force_retrain <- isTRUE(cfg$force_retrain)
  if (file.exists(met_path) && file.exists(alpha_path) && !force_retrain) {
    cli::cli_alert_info(
      "ml_tcf_sklearn_rscv: 复用已有 metrics_valid.csv / topsis_alpha.csv（设 force_retrain=TRUE 可重训）"
    )
  } else {
    py <- .mltcf26_python()
    cli::cli_alert_info("ml_tcf_sklearn_rscv: {py} RandomizedSearchCV cv={cv} n_jobs={n_jobs} SMOTE={do_smote}")
    st <- system2(py, args = args, stdout = TRUE, stderr = TRUE)
    writeLines(st, file.path(out_dir, "train_tcf_bundle.log"))
    if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
      stop("ml_tcf_sklearn_rscv: python 失败\n", paste(st, collapse = "\n"), call. = FALSE)
    }
  }
  if (!file.exists(met_path)) stop("未写出 metrics_valid.csv", call. = FALSE)
  metric_df <- utils::read.csv(met_path, row.names = 1L, check.names = FALSE)
  alpha_df <- utils::read.csv(alpha_path, stringsAsFactors = FALSE)
  ## alpha 可能是 Series to_csv → 两列 index,0
  if (!"model" %in% names(alpha_df)) {
    nm <- names(alpha_df)
    alpha_df <- data.frame(
      model = alpha_df[[1L]],
      alpha = as.numeric(alpha_df[[ncol(alpha_df)]]),
      stringsAsFactors = FALSE
    )
  }

  ## 概率
  ctx$results$ml_model_probs <- ctx$results$ml_model_probs %||% list()
  proba_dir <- file.path(out_dir, "proba_valid")
  if (dir.exists(proba_dir)) {
    for (f in list.files(proba_dir, pattern = "\\.csv$", full.names = TRUE)) {
      key <- sub("\\.csv$", "", basename(f))
      p <- as.numeric(utils::read.csv(f, header = TRUE)[[1L]])
      if (length(p) == length(y_te)) {
        ctx <- .ml_register_model_probs(ctx, key, p = p)
      }
    }
  }
  tcf_p <- file.path(proba_dir, "TCF.csv")
  if (file.exists(tcf_p)) {
    ctx$results$ml_model_probs$TCF <- as.numeric(utils::read.csv(tcf_p, header = TRUE)[[1L]])
  }

  ## topsis 结果槽
  alpha_named <- stats::setNames(as.numeric(alpha_df$alpha), as.character(alpha_df$model))
  tcf_row <- if ("TCF" %in% rownames(metric_df)) as.list(metric_df["TCF", ]) else list()
  ctx$results$ml_topsis_fusion <- list(
    alpha = alpha_named,
    metrics_submodels = as.matrix(metric_df[setdiff(rownames(metric_df), "TCF"), , drop = FALSE]),
    metrics_tcf = unlist(tcf_row),
    pred_prob = ctx$results$ml_model_probs$TCF %||% NULL,
    threshold = thr,
    backend = "sklearn_rscv",
    out_dir = out_dir
  )

  ## performance_ml 需要的 eval 表 + 非空 ml_models 占位（无 tidymodels evalresult）
  ctx$results$ml_eval_all <- .mltcf26_build_eval_all(metric_df, nrow(tr), nrow(te))
  ctx$results$ml_eval_by_model <- list()
  ctx$results$ml_models <- ctx$results$ml_models %||% list()
  for (m in rownames(metric_df)) {
    ctx$results$ml_eval_by_model[[tolower(m)]] <- ctx$results$ml_eval_all[
      ctx$results$ml_eval_all$model == m, , drop = FALSE
    ]
    if (!identical(m, "TCF")) {
      ctx$results$ml_models[[tolower(m)]] <- list(
        backend = "sklearn_rscv",
        tag = tolower(m),
        joblib = file.path(out_dir, paste0("model_", m, ".joblib"))
      )
    }
  }
  ## 最优（test AUC）
  sub <- metric_df[setdiff(rownames(metric_df), "TCF"), , drop = FALSE]
  best <- rownames(sub)[which.max(as.numeric(sub$AUC))]
  ctx$results$ml_best_model <- list(tag = tolower(best), metric = "roc_auc", estimate = sub[best, "AUC"])

  ## 镜像 TCF csv（与旧 topsis 块同路径，便于核对）
  tcf_mirror <- file.path(ctx$output_dir %||% ".", "Models", "TCF")
  dir.create(tcf_mirror, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(metric_df, file.path(tcf_mirror, "metrics_submodels_sklearn.csv"))
  utils::write.csv(alpha_df, file.path(tcf_mirror, "topsis_alpha.csv"), row.names = FALSE)
  if ("TCF" %in% rownames(metric_df)) {
    utils::write.csv(
      as.data.frame(as.list(metric_df["TCF", ])),
      file.path(tcf_mirror, "metrics_tcf.csv"),
      row.names = FALSE
    )
  }

  ## 供外验：特征名单 + 目录指针
  ctx$results$ml_tcf_sklearn <- list(
    out_dir = out_dir,
    features = feats,
    alpha = alpha_named,
    threshold = thr,
    seed = seed,
    cv = cv
  )
  saveRDS(
    list(features = feats, alpha = alpha_named, threshold = thr, out_dir = out_dir),
    file.path(out_dir, "tcf_sklearn_meta.rds")
  )

  cli::cli_alert_success(
    "ml_tcf_sklearn_rscv: 完成；最优单模={best} AUC={round(sub[best,'AUC'],3)}；TCF AUC={round(as.numeric(metric_df['TCF','AUC']),3)}"
  )
  ctx
}

register_block(
  "ml_tcf_sklearn_rscv",
  block_ml_tcf_sklearn_rscv,
  "TCF 七模型 RandomizedSearchCV(cv=5)+TOPSIS（公开代码 Python）"
)
