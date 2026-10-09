###############################################################################
#  ml_xgbsurv — XGBoost 生存 Cox（XGBSurv / survival:cox）网格调参 + 评估
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_data += ctx$data$train / ctx$data$test（须先 train_validation）
#  require_ctx_results = feature_selection_final（feature_selection 启用时）
#  study_type = "prognosis"；config$survival$time_var / event_var 必填
#
#  ml_xgbsurv = list(
#    enable = TRUE,
#    cv_folds = NULL,
#    seed = NULL,
#    limits = list(min_total_n, min_event_n, min_train_n, max_train_n),
#    pause_enable = TRUE,
#    pause_on_missing_data = TRUE,
#    xgb_max_depth_grid = c(2L, 4L),
#    xgb_eta_grid = c(0.03, 0.1),
#    xgb_nrounds = 300L,
#  ),
#
#  register_block: "ml_xgbsurv"
#  典型流水线: train_validation → 本块 → ml_aggregate（prognosis）
###############################################################################

.mlxgbs19_source_helpers <- function(ctx) {
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  path <- file.path(root, "R/ml_survival_model_helpers.R")
  if (file.exists(path)) source(path, local = FALSE)
}

.mlxgbs19_xgb_cox_label <- function(time, event) {
  time <- suppressWarnings(as.numeric(time))
  ev <- .mlsurv_coerce_event01(event)
  ifelse(ev == 1L, time, -time)
}

.mlxgbs19_run_xgbsurv <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    stop("需要安装 xgboost 包。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation
  mm <- .mlsurv_model_matrix(tr, te)
  x_tr <- mm$train
  x_te <- mm$validation

  max_depth_grid <- as.integer(bl_cfg$xgb_max_depth_grid %||% c(2L, 4L))
  eta_grid <- as.numeric(bl_cfg$xgb_eta_grid %||% c(0.03, 0.1))
  nrounds <- as.integer(bl_cfg$xgb_nrounds %||% 300L)[1L]
  grid <- expand.grid(
    max_depth = max_depth_grid,
    eta = eta_grid,
    stringsAsFactors = FALSE
  )

  label_tr <- .mlxgbs19_xgb_cox_label(tr$.time, tr$.event)
  dtrain_full <- xgboost::xgb.DMatrix(data = as.matrix(x_tr), label = label_tr)

  set.seed(seed)
  folds <- rsample::vfold_cv(tr, v = fold_num)
  best_c <- -Inf
  best_hp <- grid[1L, , drop = FALSE]
  cv_rows <- list()

  params_base <- list(
    objective = "survival:cox",
    eval_metric = "cox-nloglik"
  )

  for (gi in seq_len(nrow(grid))) {
    hp <- grid[gi, , drop = FALSE]
    fold_c <- numeric(fold_num)
    for (fi in seq_len(fold_num)) {
      split <- folds$splits[[fi]]
      tr_f <- rsample::analysis(split)
      va_f <- rsample::assessment(split)
      mm_f <- .mlsurv_model_matrix(tr_f, va_f)
      lab_f <- .mlxgbs19_xgb_cox_label(tr_f$.time, tr_f$.event)
      dtr <- xgboost::xgb.DMatrix(data = as.matrix(mm_f$train), label = lab_f)
      dva <- xgboost::xgb.DMatrix(data = as.matrix(mm_f$validation))
      fit_f <- tryCatch(
        xgboost::xgb.train(
          params = c(params_base, list(max_depth = hp$max_depth, eta = hp$eta)),
          data = dtr,
          nrounds = nrounds,
          verbose = 0L
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        as.numeric(stats::predict(fit_f, dva)),
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      fold_c[fi] <- .mlsurv_cindex(va_f$.time, va_f$.event, pr)
    }
    cv_rows[[gi]] <- .mlsurv_cv_cindex_rows(seq_len(fold_num), fold_c, "XGBoost-Cox")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_hp <- hp
    }
  }

  final_fit <- xgboost::xgb.train(
    params = c(params_base, list(max_depth = best_hp$max_depth, eta = best_hp$eta)),
    data = dtrain_full,
    nrounds = nrounds,
    verbose = 0L
  )
  dte <- xgboost::xgb.DMatrix(data = as.matrix(x_te))
  risk_tr <- as.numeric(stats::predict(final_fit, dtrain_full))
  risk_te <- as.numeric(stats::predict(final_fit, dte))

  hp_str <- paste(
    "max_depth=", best_hp$max_depth,
    ", eta=", round(best_hp$eta, 4),
    ", nrounds=", nrounds,
    sep = ""
  )
  cv5 <- dplyr::bind_rows(cv_rows[which(vapply(cv_rows, nrow, integer(1L)) > 0L)])
  if (nrow(cv5)) {
    cv5 <- cv5[cv5$.metric == "c_index" & is.finite(cv5$.estimate), , drop = FALSE]
    if (nrow(cv5)) {
      cv5 <- cv5 %>%
        dplyr::group_by(.data$.metric) %>%
        dplyr::summarise(
          mean = mean(.data$.estimate, na.rm = TRUE),
          std_err = stats::sd(.data$.estimate, na.rm = TRUE) / sqrt(sum(is.finite(.data$.estimate))),
          .groups = "drop"
        ) %>%
        dplyr::mutate(model = "XGBoost-Cox")
    }
  }

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = cv5,
    hpbest_frame = data.frame(
      Model = "XGBoost-Cox",
      Hyperparameter = hp_str,
      stringsAsFactors = FALSE
    ),
    feature_names = colnames(x_tr)
  )
}

block_ml_xgbsurv <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr)
    library(rsample)
  })
  .mlxgbs19_source_helpers(ctx)
  bl_cfg <- ctx$config$ml_xgbsurv %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_xgbsurv$enable=FALSE，跳过。")
    return(ctx)
  }

  prep <- .mlsurv_prep(ctx, bl_cfg, "ml_xgbsurv")
  if (is.null(prep)) return(ctx)
  ctx <- prep$ctx
  tag <- "xgbsurv"

  if (!.mlsurv_check_limits(prep$n_train, prep$n_events, bl_cfg, tag)) return(ctx)

  cli::cli_h2("ml_xgbsurv: 训练 {toupper(tag)}；折数={prep$fold_num}；种子={prep$seed_val}")

  res_core <- tryCatch(
    .mlxgbs19_run_xgbsurv(
      prep$df_train, prep$df_validation,
      fold_num = prep$fold_num,
      seed = prep$seed_val,
      bl_cfg = bl_cfg
    ),
    error = function(e) {
      cli::cli_alert_danger("XGBSurv 失败: {e$message}")
      NULL
    }
  )
  if (is.null(res_core)) return(ctx)

  oriented <- .mlsurv_orient_risk(
    prep$df_train$.time, prep$df_train$.event,
    res_core$risk$train, res_core$risk$test
  )
  if (isTRUE(oriented$flipped)) {
    cli::cli_alert_info(
      "xgbsurv: 风险评分已翻转以对齐 Cox C-index 方向（train C≈{round(oriented$c_index_train, 3)}）。"
    )
  }
  res_core$risk <- list(train = oriented$train, test = oriented$test)

  pe <- .mlsurv_predict_eval(
    prep$df_train$.time, prep$df_train$.event, res_core$risk,
    prep$df_train, prep$df_validation,
    "XGBoost-Cox", prep$pred_ref_col, prep$pred_ana_col,
    prep$ref_group, prep$ana_group
  )
  res <- c(res_core, pe)

  saved <- .mlsurv_save_result(prep, tag, res, res_core$model)
  ctx <- .mlsurv_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- saved$model
  ctx$results$ml_predictions_all[[tag]] <- saved$preds
  ctx$results$ml_eval_by_model[[tag]] <- saved$eval
  cli::cli_alert_success("ml_xgbsurv 完成。")
  ctx
}

register_block("ml_xgbsurv", block_ml_xgbsurv, "XGBoost Survival Cox (XGBSurv) 网格调参 + 评估")
