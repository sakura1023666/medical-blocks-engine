###############################################################################
#  ml_nafld_nested_cv — 三空间 × 嵌套CV × 多算法（老师方案 G1+G2）
#
#  register_block: "ml_nafld_nested_cv"
#  典型位置: ml_nafld_feature_spaces 之后（折内仍重做特征选择）
#  config$ml_small_sample$cv_folds / cv_repeats / inner_folds / model_order
#  写: Tables/Table 4...；Figures/Figure 3...
###############################################################################

.nafld_cm_fit_pred <- function(algo, x_tr, y_tr, x_te, seed = 1L, cfg = NULL) {
  algo <- as.character(algo)[1L]
  set.seed(seed)
  pred <- rep(NA_real_, nrow(x_te))
  ok <- FALSE
  err <- NULL
  tryCatch({
    if (algo %in% c("Logistic", "LASSO", "ElasticNet")) {
      if (!requireNamespace("glmnet", quietly = TRUE)) stop("need glmnet")
      alpha <- if (identical(algo, "Logistic") || identical(algo, "LASSO")) 1 else 0.5
      # Logistic = 无惩罚近似：用很小 lambda 的 ridge/lasso；此处用 alpha=1 + lambda.min 近端
      if (identical(algo, "Logistic")) {
        df <- as.data.frame(x_tr)
        df$y <- y_tr
        fit <- stats::glm(y ~ ., data = df, family = binomial())
        pred <- as.numeric(stats::predict(fit, newdata = as.data.frame(x_te), type = "response"))
      } else {
        cv <- glmnet::cv.glmnet(x_tr, y_tr, family = "binomial", alpha = alpha, nfolds = min(5L, nrow(x_tr)))
        pred <- as.numeric(stats::predict(cv, newx = x_te, s = "lambda.1se", type = "response"))
      }
      ok <- TRUE
    } else if (identical(algo, "RF")) {
      if (!requireNamespace("randomForest", quietly = TRUE)) stop("need randomForest")
      df <- as.data.frame(x_tr); df$y <- factor(y_tr)
      fit <- randomForest::randomForest(y ~ ., data = df, ntree = 300L)
      pred <- as.numeric(stats::predict(fit, newdata = as.data.frame(x_te), type = "prob")[, "1"])
      ok <- TRUE
    } else if (identical(algo, "XGBoost")) {
      if (!requireNamespace("xgboost", quietly = TRUE)) stop("need xgboost")
      dtr <- xgboost::xgb.DMatrix(x_tr, label = y_tr)
      fit <- xgboost::xgb.train(
        params = list(
          objective = "binary:logistic", eval_metric = "auc",
          max_depth = 3, eta = 0.1, nthread = 1L
        ),
        data = dtr, nrounds = 100L, verbose = 0L
      )
      pred <- as.numeric(stats::predict(fit, x_te))
      ok <- TRUE
    } else if (identical(algo, "LightGBM")) {
      if (!requireNamespace("lightgbm", quietly = TRUE)) stop("need lightgbm")
      dtr <- lightgbm::lgb.Dataset(x_tr, label = y_tr)
      fit <- lightgbm::lgb.train(
        params = list(
          objective = "binary", metric = "auc", num_leaves = 15L,
          learning_rate = 0.1, verbosity = -1L, num_threads = 1L
        ),
        data = dtr, nrounds = 100L
      )
      pred <- as.numeric(stats::predict(fit, x_te))
      ok <- TRUE
    } else if (identical(algo, "SVM")) {
      if (!requireNamespace("e1071", quietly = TRUE)) stop("need e1071")
      df <- as.data.frame(x_tr); df$y <- factor(y_tr)
      fit <- e1071::svm(y ~ ., data = df, probability = TRUE, kernel = "radial")
      pr <- attr(stats::predict(fit, newdata = as.data.frame(x_te), probability = TRUE), "probabilities")
      cn <- colnames(pr)
      pred <- as.numeric(pr[, if ("1" %in% cn) "1" else cn[1]])
      ok <- TRUE
    } else if (identical(algo, "TabNet")) {
      if (is.null(cfg)) stop("TabNet requires cfg")
      fp <- .nafld_cm_tabnet_fit_pred(x_tr, y_tr, x_te, cfg, seed = seed)
      pred <- fp$pred
      ok <- isTRUE(fp$ok)
      if (!ok) err <- fp$error
    } else {
      stop("unknown algo: ", algo)
    }
  }, error = function(e) {
    err <<- conditionMessage(e)
  })
  list(pred = pred, ok = ok, error = err)
}

.nafld_cm_auc <- function(y, p) {
  if (!requireNamespace("pROC", quietly = TRUE)) return(NA_real_)
  if (length(unique(y)) < 2L) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE, direction = "<")))
}

.nafld_cm_youden_metrics <- function(y, p) {
  if (!requireNamespace("pROC", quietly = TRUE) || length(unique(y)) < 2L) {
    return(list(auc = NA_real_, sens = NA_real_, spec = NA_real_, thr = 0.5))
  }
  roc <- pROC::roc(y, p, quiet = TRUE, direction = "<")
  coords <- pROC::coords(roc, "best", ret = c("threshold", "sensitivity", "specificity"),
                         best.method = "youden", transpose = FALSE)
  list(
    auc = as.numeric(pROC::auc(roc)),
    sens = as.numeric(coords$sensitivity[1]),
    spec = as.numeric(coords$specificity[1]),
    thr = as.numeric(coords$threshold[1])
  )
}

block_ml_nafld_nested_cv <- function(ctx, ...) {
  cfg <- ctx$config
  common <- file.path(getwd(), "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (!file.exists(common)) {
    common <- file.path(
      cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()),
      "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R"
    )
  }
  if (file.exists(common)) source(common, local = FALSE)
  .nafld_cm_ensure_dirs(cfg)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("ml_nafld_nested_cv: 无数据", call. = FALSE)
  data <- .nafld_cm_load_metabolome(cfg, data)
  data <- .nafld_cm_training_df(ctx, data)
  cli::cli_alert_info("嵌套CV用训练集 n={nrow(data)}")

  ml <- cfg$ml_small_sample %||% list()
  folds <- as.integer(ml$cv_folds %||% 5L)
  reps <- as.integer(ml$cv_repeats %||% 10L)
  # 快速冒烟：config$ml_small_sample$quick = TRUE
  if (isTRUE(ml$quick)) {
    folds <- as.integer(ml$quick_folds %||% 3L)
    reps <- as.integer(ml$quick_repeats %||% 1L)
  }
  algos <- as.character(ml$model_order %||% c(
    "Logistic", "LASSO", "ElasticNet", "RF", "XGBoost", "LightGBM", "SVM", "TabNet"
  ))
  if (isTRUE(ml$quick)) {
    algos <- as.character(ml$quick_model_order %||% c("Logistic", "LASSO", "RF", "XGBoost"))
  }
  # 跳过不可用
  if (!requireNamespace("lightgbm", quietly = TRUE)) {
    algos <- setdiff(algos, "LightGBM")
    cli::cli_alert_warning("未安装 lightgbm，跳过 LightGBM")
  }
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    algos <- setdiff(algos, "XGBoost")
  }
  if (!requireNamespace("e1071", quietly = TRUE)) {
    algos <- setdiff(algos, "SVM")
  }
  if ("TabNet" %in% algos) {
    if (.nafld_cm_tabnet_available(cfg)) {
      cli::cli_alert_info("TabNet: Python={(.nafld_cm_resolve_python_exe(cfg))}")
    } else {
      algos <- setdiff(algos, "TabNet")
      cli::cli_alert_warning("TabNet 不可用（请安装 pytorch-tabnet 或配置 ml_small_sample$tabnet_python）；跳过")
    }
  }

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  spaces <- list(
    C = .nafld_cm_clinical_pool(cfg, data),
    M = .nafld_cm_metabolite_pool(cfg, data)
  )
  spaces$CM <- unique(c(spaces$C, spaces$M))

  # 冒烟或补跑：折内复用外层 Table3 入选特征
  reuse_outer <- (isTRUE(ml$quick) && isTRUE(ml$quick_reuse_outer_features %||% TRUE)) ||
    isTRUE(ml$force_reuse_outer_features)
  outer_fe <- ctx$results$nafld_feature_spaces
  if (reuse_outer && !is.null(outer_fe)) {
    cli::cli_alert_info("折内复用外层共识特征（force_reuse_outer_features 或 quick）")
  }

  y_all <- .nafld_cm_outcome01(data[[oc]], pos)
  n <- nrow(data)
  set.seed(as.integer(ml$seed %||% 1234L))
  rows <- list()

  for (space in names(spaces)) {
    pool <- spaces[[space]]
    if (length(pool) < 2L) {
      cli::cli_alert_warning("空间 {space} 候选过少，跳过")
      next
    }
    cli::cli_h2("Nested CV space={space} pool={length(pool)} folds={folds} reps={reps} algos={length(algos)}")
    space_auc <- setNames(vector("list", length(algos)), algos)
    for (a in algos) space_auc[[a]] <- numeric(0)

    for (r in seq_len(reps)) {
      idx <- sample(seq_len(n))
      fold_id <- integer(n)
      for (cls in c(0L, 1L)) {
        ii <- which(y_all == cls)
        ii <- ii[order(idx[ii])]
        fold_id[ii] <- rep_len(seq_len(folds), length(ii))
      }
      for (f in seq_len(folds)) {
        te <- which(fold_id == f)
        tr <- which(fold_id != f)
        mm_tr <- .nafld_cm_model_matrix(data[tr, , drop = FALSE], pool, oc, pos)
        mm_te <- .nafld_cm_model_matrix(data[te, , drop = FALSE], pool, oc, pos)
        if (mm_tr$n < 30L || length(unique(mm_tr$y)) < 2L || length(unique(mm_te$y)) < 2L) next

        # 折内特征选择（各算法共用；quick 可复用外层）
        if (reuse_outer && !is.null(outer_fe)) {
          if (identical(space, "C")) {
            sel <- as.character(outer_fe$C$selected %||% character(0))
          } else if (identical(space, "M")) {
            sel <- as.character(outer_fe$M$selected %||% character(0))
          } else {
            sel <- as.character(outer_fe$CM$selected %||% character(0))
          }
        } else if (identical(space, "M")) {
          fe <- .nafld_cm_fe_metabolite(mm_tr$x, mm_tr$y, cfg)
          sel <- fe$selected
        } else if (identical(space, "C")) {
          fe <- .nafld_cm_fe_clinical(mm_tr$x, mm_tr$y, cfg)
          sel <- fe$selected
        } else {
          c_in <- intersect(colnames(mm_tr$x), spaces$C)
          m_in <- intersect(colnames(mm_tr$x), spaces$M)
          fe_c <- if (length(c_in)) .nafld_cm_fe_clinical(mm_tr$x[, c_in, drop = FALSE], mm_tr$y, cfg) else list(selected = character(0))
          fe_m <- if (length(m_in)) .nafld_cm_fe_metabolite(mm_tr$x[, m_in, drop = FALSE], mm_tr$y, cfg) else list(selected = character(0))
          sel <- unique(c(fe_c$selected, fe_m$selected))
        }
        if (!length(sel)) sel <- colnames(mm_tr$x)[seq_len(min(8L, ncol(mm_tr$x)))]
        sel <- intersect(sel, colnames(mm_tr$x))
        sel <- intersect(sel, colnames(mm_te$x))
        if (length(sel) < 1L) next

        xtr0 <- mm_tr$x[, sel, drop = FALSE]
        xte0 <- mm_te$x[, sel, drop = FALSE]
        mu <- colMeans(xtr0, na.rm = TRUE)
        sdv <- apply(xtr0, 2, stats::sd, na.rm = TRUE)
        sdv[!is.finite(sdv) | sdv == 0] <- 1
        xtr <- scale(xtr0, center = mu, scale = sdv)
        xte <- scale(xte0, center = mu, scale = sdv)

        for (algo in algos) {
          fp <- .nafld_cm_fit_pred(algo, xtr, mm_tr$y, xte, seed = 1000L * r + f, cfg = cfg)
          if (!isTRUE(fp$ok)) next
          space_auc[[algo]] <- c(space_auc[[algo]], .nafld_cm_auc(mm_te$y, fp$pred))
        }
        if (f == 1L || f == folds) {
          cli::cli_alert_info("{space} rep={r}/{reps} fold={f}/{folds} n_sel={length(sel)}")
        }
      }
    }

    for (algo in algos) {
      aucs <- space_auc[[algo]]
      rows[[length(rows) + 1L]] <- data.frame(
        space = space, algorithm = algo,
        n_eval = length(aucs),
        auc_mean = if (length(aucs)) mean(aucs, na.rm = TRUE) else NA_real_,
        auc_sd = if (length(aucs) > 1L) stats::sd(aucs, na.rm = TRUE) else NA_real_,
        stringsAsFactors = FALSE
      )
      cli::cli_alert_info("{space} | {algo}: AUC={round(mean(aucs, na.rm=TRUE), 3)} (n={length(aucs)})")
    }
  }

  tab <- do.call(rbind, rows)
  out <- .nafld_cm_out_dirs(cfg)
  t4_path <- file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.csv")
  t4_tmp <- tempfile(fileext = ".csv")
  utils::write.csv(tab, t4_tmp, row.names = FALSE, fileEncoding = "UTF-8")
  if (!file.copy(t4_tmp, t4_path, overwrite = TRUE)) {
    # 沙箱/挂载偶发 Permission denied：落到 step 目录再提示
    alt <- file.path(ctx$paths$step_dir %||% tempdir(), "Table 4. Nested CV performance by space and algorithm.csv")
    dir.create(dirname(alt), recursive = TRUE, showWarnings = FALSE)
    file.copy(t4_tmp, alt, overwrite = TRUE)
    cli::cli_alert_warning("Table 4 未能写入 {t4_path}；已备份到 {alt}")
  }
  unlink(t4_tmp)

  # 热图由 ml_nafld_pub_finalize 写入 Figure 3（避免根目录重复编号）
  # 最佳空间×算法：全数据重训一次出 Youden 指标 → Table 5 简化版
  if (nrow(tab) && any(is.finite(tab$auc_mean))) {
    best <- tab[which.max(tab$auc_mean), , drop = FALSE]
    ctx$results$nafld_nested_cv <- list(table = tab, best = best)
    utils::write.csv(best, file.path(out$tables, "Table 5. Best nested CV model.csv"),
                     row.names = FALSE, fileEncoding = "UTF-8")
    cli::cli_alert_success("最佳: {best$space} + {best$algorithm} AUC={round(best$auc_mean, 3)}")
  } else {
    ctx$results$nafld_nested_cv <- list(table = tab, best = NULL)
  }
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block(
    "ml_nafld_nested_cv",
    block_ml_nafld_nested_cv,
    "NAFLD 三空间嵌套CV多算法"
  )
}
