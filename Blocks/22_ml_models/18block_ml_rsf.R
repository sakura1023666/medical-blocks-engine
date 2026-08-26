###############################################################################
#  ml_rsf — Random Survival Forest (randomForestSRC) 网格调参 + 评估
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_data += ctx$data$train / ctx$data$test（须先 train_validation）
#  require_ctx_results = feature_selection_final（feature_selection 启用时）
#  study_type = "prognosis"；config$survival$time_var / event_var 必填
#
#  ml_rsf = list(
#    enable = TRUE,
#    cv_folds = NULL,
#    seed = NULL,
#    limits = list(min_total_n, min_event_n, min_train_n, max_train_n),
#    pause_enable = TRUE,
#    pause_on_missing_data = TRUE,
#    rsf_ntree_grid = c(500L, 1000L),
#    rsf_nodesize_grid = c(3L, 15L),
#  ),
#
#  register_block: "ml_rsf"
#  典型流水线: train_validation → 本块 → ml_aggregate（prognosis）
###############################################################################

.mlsrf18_source_helpers <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  path <- file.path(root, "R/ml_survival_model_helpers.R")
  if (file.exists(path)) source(path, local = FALSE)
}

.mlsrf18_run_rsf <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("randomForestSRC", quietly = TRUE)) {
    stop("需要安装 randomForestSRC 包。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation

  ntree_grid <- as.integer(bl_cfg$rsf_ntree_grid %||% c(500L, 1000L))
  nodesize_grid <- as.integer(bl_cfg$rsf_nodesize_grid %||% c(3L, 15L))
  nfeat <- length(setdiff(names(tr), c(".time", ".event")))
  mtry_opts <- unique(pmax(1L, c(
    max(1L, floor(sqrt(nfeat))),
    max(1L, floor(nfeat / 3)),
    max(1L, min(5L, nfeat))
  )))
  grid <- expand.grid(
    ntree = ntree_grid,
    mtry = mtry_opts,
    nodesize = nodesize_grid,
    stringsAsFactors = FALSE
  )

  set.seed(seed)
  folds <- rsample::vfold_cv(tr, v = fold_num)
  best_c <- -Inf
  best_hp <- grid[1L, , drop = FALSE]
  cv_rows <- list()

  for (gi in seq_len(nrow(grid))) {
    hp <- grid[gi, , drop = FALSE]
    fold_c <- numeric(fold_num)
    for (fi in seq_len(fold_num)) {
      split <- folds$splits[[fi]]
      tr_f <- rsample::analysis(split)
      va_f <- rsample::assessment(split)
      fit_f <- tryCatch(
        randomForestSRC::rfsrc(
          stats::as.formula("survival::Surv(.time, .event) ~ ."),
          data = tr_f,
          ntree = hp$ntree,
          mtry = hp$mtry,
          nodesize = hp$nodesize,
          nsplit = 10L,
          splitrule = "logrank",
          importance = FALSE,
          seed = seed + gi + fi
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        stats::predict(fit_f, newdata = va_f)$predicted,
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      fold_c[fi] <- .mlsurv_cindex(va_f$.time, va_f$.event, pr)
    }
    cv_rows[[gi]] <- .mlsurv_cv_cindex_rows(seq_len(fold_num), fold_c, "RSF")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_hp <- hp
    }
  }

  final_fit <- randomForestSRC::rfsrc(
    stats::as.formula("survival::Surv(.time, .event) ~ ."),
    data = tr,
    ntree = best_hp$ntree,
    mtry = best_hp$mtry,
    nodesize = best_hp$nodesize,
    nsplit = 10L,
    splitrule = "logrank",
    importance = TRUE,
    seed = seed
  )
  risk_tr <- stats::predict(final_fit, newdata = tr)$predicted
  risk_te <- stats::predict(final_fit, newdata = te)$predicted

  hp_str <- paste(
    "ntree=", best_hp$ntree,
    ", mtry=", best_hp$mtry,
    ", nodesize=", best_hp$nodesize,
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
        dplyr::mutate(model = "RSF")
    }
  }

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = cv5,
    hpbest_frame = data.frame(
      Model = "Random Survival Forest (RSF)",
      Hyperparameter = hp_str,
      stringsAsFactors = FALSE
    )
  )
}

block_ml_rsf <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr)
    library(rsample)
  })
  .mlsrf18_source_helpers(ctx)
  bl_cfg <- ctx$config$ml_rsf %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_rsf$enable=FALSE，跳过。")
    return(ctx)
  }

  prep <- .mlsurv_prep(ctx, bl_cfg, "ml_rsf")
  if (is.null(prep)) return(ctx)
  ctx <- prep$ctx
  tag <- "rsf"

  if (!.mlsurv_check_limits(prep$n_train, prep$n_events, bl_cfg, tag)) return(ctx)

  cli::cli_h2("ml_rsf: 训练 {toupper(tag)}；折数={prep$fold_num}；种子={prep$seed_val}")

  res_core <- tryCatch(
    .mlsrf18_run_rsf(
      prep$df_train, prep$df_validation,
      fold_num = prep$fold_num,
      seed = prep$seed_val,
      bl_cfg = bl_cfg
    ),
    error = function(e) {
      cli::cli_alert_danger("RSF 失败: {e$message}")
      NULL
    }
  )
  if (is.null(res_core)) return(ctx)

  pe <- .mlsurv_predict_eval(
    prep$df_train$.time, prep$df_train$.event, res_core$risk,
    prep$df_train, prep$df_validation,
    "RSF", prep$pred_ref_col, prep$pred_ana_col,
    prep$ref_group, prep$ana_group
  )
  res <- c(res_core, pe)

  saved <- .mlsurv_save_result(prep, tag, res, res_core$model)
  ctx <- .mlsurv_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- saved$model
  ctx$results$ml_predictions_all[[tag]] <- saved$preds
  ctx$results$ml_eval_by_model[[tag]] <- saved$eval
  cli::cli_alert_success("ml_rsf 完成。")
  ctx
}

register_block("ml_rsf", block_ml_rsf, "Random Survival Forest (RSF) 网格调参 + 评估")
