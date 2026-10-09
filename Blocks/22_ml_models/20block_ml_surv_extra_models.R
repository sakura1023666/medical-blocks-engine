###############################################################################
#  ml_surv_extra_models — 预后专用生存 ML 模型集
#
#  文献常用六模型 + 小样本补充：
#    ml_coxboost      — CoxBoost
#    ml_gbmsurv       — GBM-Cox（gbm::coxph）
#    ml_ridge_cox     — Ridge-Cox（glmnet α=0）
#    ml_enet_cox      — ElasticNet-Cox（glmnet α=0.5）
#    ml_survivalsvm   — SurvivalSVM（小样本友好）
#    ml_mboost_cox    — mboost 分量提升 Cox（高维/小样本友好）
#
#  已有对照块（本文件不重复注册）：
#    ml_xgbsurv — XGBoost-Cox
#    ml_rsf     — Random survival forest
#
#  require: study_type=prognosis；survival$time_var/event_var；feature_selection_final
#  典型流水线: train_validation → 本系列 → ml_aggregate → performance_ml
###############################################################################

.mlsve20_source <- function(ctx) {
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  path <- file.path(root, "R/ml_survival_model_helpers.R")
  if (file.exists(path)) source(path, local = FALSE)
}

.mlsve20_run_block <- function(ctx, cfg_key, tag, display_name, train_fn) {
  suppressPackageStartupMessages({
    if (requireNamespace("dplyr", quietly = TRUE)) library(dplyr)
    if (requireNamespace("rsample", quietly = TRUE)) library(rsample)
  })
  .mlsve20_source(ctx)
  bl_cfg <- ctx$config[[cfg_key]] %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("{cfg_key}$enable=FALSE，跳过。")
    return(ctx)
  }
  prep <- .mlsurv_prep(ctx, bl_cfg, cfg_key)
  if (is.null(prep)) return(ctx)
  if (!.mlsurv_check_limits(prep$n_train, prep$n_events, bl_cfg, tag)) return(ctx)

  cli::cli_h2("{cfg_key}: 训练 {display_name}；折数={prep$fold_num}；种子={prep$seed_val}")
  res_core <- tryCatch(
    train_fn(prep$df_train, prep$df_validation, prep$fold_num, prep$seed_val, bl_cfg),
    error = function(e) {
      cli::cli_alert_danger("{display_name} 失败: {conditionMessage(e)}")
      NULL
    }
  )
  if (is.null(res_core)) return(ctx)
  ctx <- .mlsurv_finish_block(ctx, prep, tag, display_name, res_core)
  cli::cli_alert_success("{cfg_key} 完成。")
  ctx
}

# ── Ridge / ElasticNet Cox（glmnet）─────────────────────────────────────────
.mlsve20_run_glmnet_cox <- function(train_df, test_df, fold_num, seed, bl_cfg,
                                    alpha, display_name, model_label) {
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    stop("需要安装 glmnet。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation
  mm <- .mlsurv_model_matrix(tr, te)
  x_tr <- mm$train
  x_te <- mm$validation
  y_tr <- survival::Surv(tr$.time, tr$.event)

  nfolds <- max(3L, min(as.integer(fold_num), max(3L, as.integer(nrow(x_tr) %/% 5L))))
  if (!is.finite(nfolds) || nfolds < 3L) nfolds <- 3L
  set.seed(seed)
  cvfit <- glmnet::cv.glmnet(
    x_tr, y_tr, family = "cox", alpha = alpha, nfolds = nfolds,
    type.measure = "deviance"
  )
  lam_choice <- tolower(trimws(as.character(bl_cfg$lambda_choice %||% "lambda.min")[1L]))
  s_use <- if (identical(lam_choice, "lambda.1se")) cvfit$lambda.1se else cvfit$lambda.min

  risk_tr <- as.numeric(stats::predict(cvfit, newx = x_tr, s = s_use, type = "link"))
  risk_te <- as.numeric(stats::predict(cvfit, newx = x_te, s = s_use, type = "link"))

  ## 简易 holdout CV C-index（用同一 λ）
  set.seed(seed)
  folds <- rsample::vfold_cv(tr, v = nfolds)
  fold_c <- vapply(seq_len(nfolds), function(fi) {
    split <- folds$splits[[fi]]
    tr_f <- rsample::analysis(split)
    va_f <- rsample::assessment(split)
    mm_f <- .mlsurv_model_matrix(tr_f, va_f)
    y_f <- survival::Surv(tr_f$.time, tr_f$.event)
    fit_f <- tryCatch(
      glmnet::cv.glmnet(
        mm_f$train, y_f, family = "cox", alpha = alpha,
        nfolds = min(5L, max(3L, nrow(mm_f$train) %/% 5L)),
        type.measure = "deviance"
      ),
      error = function(e) NULL
    )
    if (is.null(fit_f)) return(NA_real_)
    pr <- as.numeric(stats::predict(fit_f, newx = mm_f$validation, s = "lambda.min", type = "link"))
    .mlsurv_cindex(va_f$.time, va_f$.event, pr)
  }, numeric(1L))

  list(
    model = cvfit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = .mlsurv_summarise_cv5(
      list(.mlsurv_cv_cindex_rows(seq_len(nfolds), fold_c, display_name)),
      display_name
    ),
    hpbest_frame = data.frame(
      Model = model_label,
      Hyperparameter = paste0(
        "alpha=", alpha, ", lambda=", lam_choice, "=",
        signif(as.numeric(s_use)[1L], 4)
      ),
      stringsAsFactors = FALSE
    )
  )
}

# ── CoxBoost ────────────────────────────────────────────────────────────────
.mlsve20_run_coxboost <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("CoxBoost", quietly = TRUE)) {
    stop("需要安装 CoxBoost。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation
  mm <- .mlsurv_model_matrix(tr, te)
  x_tr <- as.matrix(mm$train)
  x_te <- as.matrix(mm$validation)
  stepno_grid <- as.integer(bl_cfg$stepno_grid %||% c(50L, 100L, 200L))
  penalty <- as.numeric(bl_cfg$penalty %||% 100)[1L]
  if (!is.finite(penalty) || penalty <= 0) penalty <- 100

  set.seed(seed)
  folds <- rsample::vfold_cv(tr, v = fold_num)
  best_c <- -Inf
  best_step <- stepno_grid[1L]
  cv_rows <- list()

  for (si in seq_along(stepno_grid)) {
    stepno <- stepno_grid[[si]]
    fold_c <- numeric(fold_num)
    for (fi in seq_len(fold_num)) {
      split <- folds$splits[[fi]]
      tr_f <- rsample::analysis(split)
      va_f <- rsample::assessment(split)
      mm_f <- .mlsurv_model_matrix(tr_f, va_f)
      fit_f <- tryCatch(
        CoxBoost::CoxBoost(
          time = tr_f$.time, status = tr_f$.event,
          x = as.matrix(mm_f$train),
          stepno = stepno, penalty = penalty
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        as.numeric(stats::predict(fit_f, newdata = as.matrix(mm_f$validation), type = "lp")),
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      fold_c[fi] <- .mlsurv_cindex(va_f$.time, va_f$.event, pr)
    }
    cv_rows[[si]] <- .mlsurv_cv_cindex_rows(seq_len(fold_num), fold_c, "CoxBoost")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_step <- stepno
    }
  }

  final_fit <- CoxBoost::CoxBoost(
    time = tr$.time, status = tr$.event,
    x = x_tr, stepno = best_step, penalty = penalty
  )
  risk_tr <- as.numeric(stats::predict(final_fit, newdata = x_tr, type = "lp"))
  risk_te <- as.numeric(stats::predict(final_fit, newdata = x_te, type = "lp"))

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = .mlsurv_summarise_cv5(cv_rows, "CoxBoost"),
    hpbest_frame = data.frame(
      Model = "CoxBoost",
      Hyperparameter = paste0("stepno=", best_step, ", penalty=", penalty),
      stringsAsFactors = FALSE
    )
  )
}

# ── GBM-Cox ─────────────────────────────────────────────────────────────────
.mlsve20_run_gbmsurv <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("gbm", quietly = TRUE)) {
    stop("需要安装 gbm。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation
  n_trees <- as.integer(bl_cfg$n_trees %||% 300L)[1L]
  depth_grid <- as.integer(bl_cfg$interaction_depth_grid %||% c(1L, 2L, 3L))
  shrink_grid <- as.numeric(bl_cfg$shrinkage_grid %||% c(0.01, 0.05))
  grid <- expand.grid(depth = depth_grid, shrinkage = shrink_grid, stringsAsFactors = FALSE)

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
        gbm::gbm(
          survival::Surv(.time, .event) ~ .,
          data = tr_f,
          distribution = "coxph",
          n.trees = n_trees,
          interaction.depth = hp$depth,
          shrinkage = hp$shrinkage,
          bag.fraction = 0.8,
          train.fraction = 1,
          verbose = FALSE
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        as.numeric(gbm::predict.gbm(fit_f, newdata = va_f, n.trees = n_trees, type = "link")),
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      fold_c[fi] <- .mlsurv_cindex(va_f$.time, va_f$.event, pr)
    }
    cv_rows[[gi]] <- .mlsurv_cv_cindex_rows(seq_len(fold_num), fold_c, "GBM-Cox")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_hp <- hp
    }
  }

  final_fit <- gbm::gbm(
    survival::Surv(.time, .event) ~ .,
    data = tr,
    distribution = "coxph",
    n.trees = n_trees,
    interaction.depth = best_hp$depth,
    shrinkage = best_hp$shrinkage,
    bag.fraction = 0.8,
    train.fraction = 1,
    verbose = FALSE
  )
  risk_tr <- as.numeric(gbm::predict.gbm(final_fit, newdata = tr, n.trees = n_trees, type = "link"))
  risk_te <- as.numeric(gbm::predict.gbm(final_fit, newdata = te, n.trees = n_trees, type = "link"))

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = .mlsurv_summarise_cv5(cv_rows, "GBM-Cox"),
    hpbest_frame = data.frame(
      Model = "GBM-Cox",
      Hyperparameter = paste0(
        "n.trees=", n_trees,
        ", depth=", best_hp$depth,
        ", shrinkage=", best_hp$shrinkage
      ),
      stringsAsFactors = FALSE
    )
  )
}

# ── SurvivalSVM（小样本）────────────────────────────────────────────────────
.mlsve20_survsvm_pred_vec <- function(fit, newdata) {
  pr <- stats::predict(fit, newdata = newdata)
  x <- if (is.list(pr) && !is.null(pr$predicted)) pr$predicted else pr
  if (is.list(x) && !is.data.frame(x) && !is.atomic(x)) x <- unlist(x)
  as.numeric(x)
}

.mlsve20_run_survivalsvm <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("survivalsvm", quietly = TRUE)) {
    stop("需要安装 survivalsvm。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr <- imp$train
  te <- imp$validation
  ## 仅数值特征（SVM 更稳）
  feat_cols <- setdiff(names(tr), c(".time", ".event"))
  for (cc in feat_cols) {
    if (!is.numeric(tr[[cc]])) {
      tr_fac <- factor(as.character(tr[[cc]]))
      te_chr <- as.character(te[[cc]])
      te_chr[is.na(te_chr) | !nzchar(trimws(te_chr))] <- NA_character_
      te_fac <- factor(te_chr, levels = levels(tr_fac))
      tr[[cc]] <- as.numeric(tr_fac)
      te[[cc]] <- as.numeric(te_fac)
      med <- stats::median(tr[[cc]], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      te[[cc]][!is.finite(te[[cc]])] <- med
    } else {
      tr[[cc]] <- suppressWarnings(as.numeric(tr[[cc]]))
      te[[cc]] <- suppressWarnings(as.numeric(te[[cc]]))
      med <- stats::median(tr[[cc]], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      tr[[cc]][!is.finite(tr[[cc]])] <- med
      te[[cc]][!is.finite(te[[cc]])] <- med
    }
  }

  gamma_grid <- as.numeric(bl_cfg$gamma_grid %||% c(0.1, 1, 10))
  gamma_grid <- gamma_grid[is.finite(gamma_grid) & gamma_grid > 0]
  if (!length(gamma_grid)) gamma_grid <- 1
  set.seed(seed)
  nfold_use <- max(2L, min(as.integer(fold_num), max(2L, as.integer(nrow(tr) %/% 10L))))
  folds <- rsample::vfold_cv(tr, v = nfold_use)
  nfolds <- length(folds$splits)
  best_c <- -Inf
  best_g <- gamma_grid[1L]
  cv_rows <- list()

  for (gi in seq_along(gamma_grid)) {
    g <- gamma_grid[[gi]]
    fold_c <- numeric(nfolds)
    for (fi in seq_len(nfolds)) {
      split <- folds$splits[[fi]]
      tr_f <- rsample::analysis(split)
      va_f <- rsample::assessment(split)
      fit_f <- tryCatch(
        survivalsvm::survivalsvm(
          survival::Surv(.time, .event) ~ .,
          data = tr_f,
          type = "regression",
          gamma.mu = g,
          opt.meth = "quadprog",
          diff.meth = "makediff3",
          kernel = "lin_kernel"
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        .mlsve20_survsvm_pred_vec(fit_f, va_f),
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      ## 选方向：取 C 更高者（prognostic index 可能与风险相反）
      fold_c[fi] <- max(
        .mlsurv_cindex(va_f$.time, va_f$.event, pr),
        .mlsurv_cindex(va_f$.time, va_f$.event, -pr),
        na.rm = TRUE
      )
    }
    cv_rows[[gi]] <- .mlsurv_cv_cindex_rows(seq_len(nfolds), fold_c, "SurvivalSVM")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_g <- g
    }
  }

  final_fit <- survivalsvm::survivalsvm(
    survival::Surv(.time, .event) ~ .,
    data = tr,
    type = "regression",
    gamma.mu = best_g,
    opt.meth = "quadprog",
    diff.meth = "makediff3",
    kernel = "lin_kernel"
  )
  pr_tr <- .mlsve20_survsvm_pred_vec(final_fit, tr)
  pr_te <- .mlsve20_survsvm_pred_vec(final_fit, te)
  ## 选方向：训练集 C-index 更高者（finish_block 还会再做一次安全翻转）
  c_pos <- .mlsurv_cindex(tr$.time, tr$.event, pr_tr)
  c_neg <- .mlsurv_cindex(tr$.time, tr$.event, -pr_tr)
  flip <- is.finite(c_neg) && (!is.finite(c_pos) || c_neg > c_pos)
  risk_tr <- if (flip) -pr_tr else pr_tr
  risk_te <- if (flip) -pr_te else pr_te

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = .mlsurv_summarise_cv5(cv_rows, "SurvivalSVM"),
    hpbest_frame = data.frame(
      Model = "SurvivalSVM",
      Hyperparameter = paste0("gamma.mu=", best_g, ", kernel=lin, flip=", flip),
      stringsAsFactors = FALSE
    )
  )
}

# ── mboost CoxPH（小样本/高维）──────────────────────────────────────────────
.mlsve20_run_mboost_cox <- function(train_df, test_df, fold_num, seed, bl_cfg) {
  if (!requireNamespace("mboost", quietly = TRUE)) {
    stop("需要安装 mboost。", call. = FALSE)
  }
  imp <- .mlsurv_impute_frame(train_df, test_df)
  tr0 <- imp$train
  te0 <- imp$validation
  ## glmboost + factor newdata 易触发 colnames 断言失败；统一用 model.matrix 数值列
  mm <- .mlsurv_model_matrix(tr0, te0)
  tr <- data.frame(
    .time = tr0$.time, .event = tr0$.event,
    mm$train, check.names = FALSE, stringsAsFactors = FALSE
  )
  te <- data.frame(
    .time = te0$.time, .event = te0$.event,
    mm$validation, check.names = FALSE, stringsAsFactors = FALSE
  )
  mstop_grid <- as.integer(bl_cfg$mstop_grid %||% c(50L, 100L, 200L))
  nu <- as.numeric(bl_cfg$nu %||% 0.1)[1L]
  if (!is.finite(nu) || nu <= 0) nu <- 0.1

  set.seed(seed)
  folds <- rsample::vfold_cv(tr, v = fold_num)
  best_c <- -Inf
  best_m <- mstop_grid[1L]
  cv_rows <- list()

  for (mi in seq_along(mstop_grid)) {
    mstop <- mstop_grid[[mi]]
    fold_c <- numeric(fold_num)
    for (fi in seq_len(fold_num)) {
      split <- folds$splits[[fi]]
      tr_f <- rsample::analysis(split)
      va_f <- rsample::assessment(split)
      fit_f <- tryCatch(
        mboost::glmboost(
          survival::Surv(.time, .event) ~ .,
          data = tr_f,
          family = mboost::CoxPH(),
          control = mboost::boost_control(mstop = mstop, nu = nu),
          center = TRUE
        ),
        error = function(e) NULL
      )
      if (is.null(fit_f)) {
        fold_c[fi] <- NA_real_
        next
      }
      pr <- tryCatch(
        as.numeric(stats::predict(fit_f, newdata = va_f, type = "link")),
        error = function(e) rep(NA_real_, nrow(va_f))
      )
      fold_c[fi] <- .mlsurv_cindex(va_f$.time, va_f$.event, pr)
    }
    cv_rows[[mi]] <- .mlsurv_cv_cindex_rows(seq_len(fold_num), fold_c, "mboost-Cox")
    mc <- mean(fold_c, na.rm = TRUE)
    if (is.finite(mc) && mc > best_c) {
      best_c <- mc
      best_m <- mstop
    }
  }

  final_fit <- mboost::glmboost(
    survival::Surv(.time, .event) ~ .,
    data = tr,
    family = mboost::CoxPH(),
    control = mboost::boost_control(mstop = best_m, nu = nu),
    center = TRUE
  )
  risk_tr <- as.numeric(stats::predict(final_fit, newdata = tr, type = "link"))
  risk_te <- as.numeric(stats::predict(final_fit, newdata = te, type = "link"))
  ## 供 SHAP 对齐：记住训练设计矩阵列名
  attr(final_fit, "mlsurv_design_cols") <- setdiff(names(tr), c(".time", ".event"))
  attr(final_fit, "mlsurv_train_levels") <- lapply(
    tr0[, setdiff(names(tr0), c(".time", ".event")), drop = FALSE],
    function(x) if (is.factor(x) || is.character(x)) levels(factor(as.character(x))) else NULL
  )

  list(
    model = final_fit,
    risk = list(train = risk_tr, test = risk_te),
    cv5_cindex = .mlsurv_summarise_cv5(cv_rows, "mboost-Cox"),
    hpbest_frame = data.frame(
      Model = "mboost-Cox",
      Hyperparameter = paste0("mstop=", best_m, ", nu=", nu),
      stringsAsFactors = FALSE
    )
  )
}

# ── register blocks ─────────────────────────────────────────────────────────

block_ml_coxboost <- function(ctx, ...) {
  .mlsve20_run_block(ctx, "ml_coxboost", "coxboost", "CoxBoost", .mlsve20_run_coxboost)
}
register_block("ml_coxboost", block_ml_coxboost, "CoxBoost 似然提升 Cox（预后）")

block_ml_gbmsurv <- function(ctx, ...) {
  .mlsve20_run_block(ctx, "ml_gbmsurv", "gbmsurv", "GBM-Cox", .mlsve20_run_gbmsurv)
}
register_block("ml_gbmsurv", block_ml_gbmsurv, "GBM-Cox（gbm coxph 分布，预后）")

block_ml_ridge_cox <- function(ctx, ...) {
  .mlsve20_run_block(
    ctx, "ml_ridge_cox", "ridge_cox", "Ridge-Cox",
    function(tr, te, fold, seed, bl) {
      .mlsve20_run_glmnet_cox(tr, te, fold, seed, bl, alpha = 0, "Ridge-Cox", "Ridge-Cox")
    }
  )
}
register_block("ml_ridge_cox", block_ml_ridge_cox, "Ridge-Cox（glmnet α=0，预后/小样本友好）")

block_ml_enet_cox <- function(ctx, ...) {
  .mlsve20_run_block(
    ctx, "ml_enet_cox", "enet_cox", "ElasticNet-Cox",
    function(tr, te, fold, seed, bl) {
      alpha <- as.numeric(bl$alpha %||% 0.5)[1L]
      if (!is.finite(alpha)) alpha <- 0.5
      .mlsve20_run_glmnet_cox(
        tr, te, fold, seed, bl, alpha = alpha,
        "ElasticNet-Cox", "ElasticNet-Cox"
      )
    }
  )
}
register_block("ml_enet_cox", block_ml_enet_cox, "ElasticNet-Cox（glmnet α≈0.5，预后/小样本友好）")

block_ml_survivalsvm <- function(ctx, ...) {
  .mlsve20_run_block(ctx, "ml_survivalsvm", "survivalsvm", "SurvivalSVM", .mlsve20_run_survivalsvm)
}
register_block("ml_survivalsvm", block_ml_survivalsvm, "SurvivalSVM（小样本预后补充）")

block_ml_mboost_cox <- function(ctx, ...) {
  .mlsve20_run_block(ctx, "ml_mboost_cox", "mboost_cox", "mboost-Cox", .mlsve20_run_mboost_cox)
}
register_block("ml_mboost_cox", block_ml_mboost_cox, "mboost 分量提升 Cox（高维/小样本补充）")
