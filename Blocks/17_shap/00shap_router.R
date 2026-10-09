###############################################################################
#  00shap_router.R — 按模型引擎选择 SHAP 算法
#
#  tree_shapviz     : xgboost / lightgbm / rf / dt (+ adaboost 若底层为树)
#  catboost_native  : catboost::get_feature_importance(type = ShapValues)
#  linear_coef      : logistic / enet（系数 × 去均值，线性精确 SHAP）
#  kernel_fastshap  : rsvm / mlp / realmlp / knn / 非树 adaboost
#  kernel_tabpfn    : tabpfn*（无 workflow 时对 baked 矩阵 + workflow 代理预测）
###############################################################################

.shap_tabpfn_tags <- function() {
  c("tabpfn", "tabpfnv2", "realtabpfn_2_5", "tablcl_v2")
}

.shap_surv_tags <- function() {
  c(
    "xgbsurv", "rsf", "coxboost", "gbmsurv",
    "ridge_cox", "enet_cox", "survivalsvm", "mboost_cox"
  )
}

.shap_is_workflow_like <- function(obj) {
  inherits(obj, "workflow") || inherits(obj, "model_fit")
}

.shap_extract_engine <- function(wf) {
  fit_p <- if (inherits(wf, "workflow")) {
    workflows::extract_fit_parsnip(wf)
  } else if (inherits(wf, "model_fit")) {
    wf
  } else {
    return(NULL)
  }
  tryCatch(parsnip::extract_fit_engine(fit_p), error = function(e) NULL)
}

.shap_method_for_tag <- function(tag, wf = NULL) {
  tag <- tolower(trimws(as.character(tag)[1L]))
  if (identical(tag, "xgbsurv")) return("surv_xgbsurv")
  if (tag %in% c("ridge_cox", "enet_cox")) return("surv_glmnet_cox")
  if (tag %in% .shap_surv_tags()) return("surv_kernel")
  if (tag %in% c("xgboost", "lightgbm", "rf", "dt")) return("tree_shapviz")
  if (identical(tag, "catboost")) return("catboost_native")
  if (tag %in% c("logistic", "enet")) return("linear_coef")
  if (tag %in% c("rsvm", "mlp", "realmlp", "knn")) return("kernel_fastshap")
  if (tag %in% .shap_tabpfn_tags()) return("kernel_tabpfn")
  if (identical(tag, "adaboost")) {
    eng <- if (!is.null(wf)) .shap_extract_engine(wf) else NULL
    if (!is.null(eng) && (inherits(eng, "xgb.Booster") || inherits(eng, "ranger"))) {
      return("tree_shapviz")
    }
    return("kernel_fastshap")
  }
  "kernel_fastshap"
}

.shap_ranger_event_level <- function(eng) {
  lv <- eng$forest$levels
  if (length(lv) >= 2L) return(as.character(lv[[2L]]))
  NULL
}

.shap_ranger_unify_for_treeshap <- function(eng, X_df) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("treeshap ranger 路径需要 data.table。", call. = FALSE)
  }
  if (!requireNamespace("treeshap", quietly = TRUE)) {
    stop("需要 treeshap 包。", call. = FALSE)
  }
  n <- eng$num.trees
  feat_names <- as.character(eng$forest$independent.variable.names)
  miss <- setdiff(feat_names, colnames(X_df))
  if (length(miss)) {
    stop(
      "treeshap: 烘焙矩阵缺少 ranger 特征: ", paste(miss, collapse = ", "),
      call. = FALSE
    )
  }
  X_ref <- as.data.frame(X_df)[, feat_names, drop = FALSE]
  is_prob <- identical(eng$treetype, "Probability estimation")
  event_lvl <- if (is_prob) .shap_ranger_event_level(eng) else NULL
  pred_col <- if (is_prob && !is.null(event_lvl)) paste0("pred.", event_lvl) else "prediction"
  x <- lapply(seq_len(n), function(tree) {
    tree_data <- data.table::as.data.table(ranger::treeInfo(eng, tree = tree))
    if (is_prob) {
      if (pred_col %in% names(tree_data)) {
        data.table::setnames(tree_data, pred_col, "prediction")
      } else if ("pred.1" %in% names(tree_data)) {
        data.table::setnames(tree_data, "pred.1", "prediction")
      } else {
        pc <- grep("^pred\\.", names(tree_data), value = TRUE)
        if (length(pc)) {
          data.table::setnames(tree_data, pc[[length(pc)]], "prediction")
        }
      }
    }
    tree_data[, .(nodeID, leftChild, rightChild, splitvarName, splitval, prediction)]
  })
  unify_fun <- utils::getFromNamespace("ranger_unify.common", "treeshap")
  unify_fun(x = x, n = n, data = X_ref, feature_names = feat_names)
}

.shap_build_ranger_treeshap <- function(eng, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  unified <- .shap_ranger_unify_for_treeshap(eng, X_df)
  feat_names <- unified$feature_names
  X_use <- as.data.frame(X_df)[, feat_names, drop = FALSE]
  ts <- treeshap::treeshap(unified, X_use, verbose = FALSE)
  shapviz::shapviz(ts, X = X_use)
}

.shap_align_xgb_features <- function(eng, X_mat, X_df) {
  if (!inherits(eng, "xgb.Booster")) {
    return(list(X_mat = X_mat, X_df = X_df))
  }
  fn <- tryCatch(eng$feature_names, error = function(e) NULL)
  fn <- as.character(fn %||% character(0))
  if (!length(fn)) return(list(X_mat = X_mat, X_df = X_df))
  miss <- setdiff(fn, colnames(X_mat))
  if (length(miss)) {
    add0 <- matrix(0, nrow = nrow(X_mat), ncol = length(miss))
    colnames(add0) <- miss
    X_mat <- cbind(X_mat, add0)
    X_df <- cbind(X_df, as.data.frame(add0, check.names = FALSE))
  }
  keep <- intersect(fn, colnames(X_mat))
  list(
    X_mat = X_mat[, keep, drop = FALSE],
    X_df = X_df[, keep, drop = FALSE]
  )
}

.shap_build_tree_shapviz <- function(wf, X_mat, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  if (!.shap_is_workflow_like(wf)) {
    stop("tree_shapviz 需要 tidymodels workflow。", call. = FALSE)
  }
  eng <- .shap_extract_engine(wf)
  if (is.null(eng)) stop("无法 extract_fit_engine。", call. = FALSE)
  if (inherits(eng, "ranger")) {
    out <- tryCatch(
      shapviz::shapviz(eng, X_pred = X_mat, X = X_df),
      error = function(e) e
    )
    if (!inherits(out, "error")) {
      attr(out, "shap_method") <- "tree_shapviz"
      return(out)
    }
    cli::cli_alert_warning(
      "block_shap: ranger shapviz 失败 ({out$message})，尝试 treeshap。"
    )
    ts_out <- tryCatch(
      .shap_build_ranger_treeshap(eng, X_df),
      error = function(e) e
    )
    if (!inherits(ts_out, "error")) {
      attr(ts_out, "shap_method") <- "treeshap_ranger"
      return(ts_out)
    }
    stop("ranger TreeSHAP 不可用: ", ts_out$message, call. = FALSE)
  }
  aligned <- .shap_align_xgb_features(eng, X_mat, X_df)
  shapviz::shapviz(eng, X_pred = aligned$X_mat, X = aligned$X_df)
}

.shap_build_catboost_native <- function(wf, X_mat, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  if (!requireNamespace("catboost", quietly = TRUE)) {
    stop("需要 catboost 包。", call. = FALSE)
  }
  if (!.shap_is_workflow_like(wf)) {
    stop("catboost_native 需要 tidymodels workflow。", call. = FALSE)
  }
  eng <- .shap_extract_engine(wf)
  if (is.null(eng)) stop("无法 extract_fit_engine。", call. = FALSE)
  pool <- catboost::catboost.load_pool(data = X_mat)
  shap_raw <- catboost::catboost.get_feature_importance(
    eng, pool, type = "ShapValues", thread_count = 1L
  )
  if (!is.matrix(shap_raw)) shap_raw <- as.matrix(shap_raw)
  if (ncol(shap_raw) < 2L) stop("CatBoost ShapValues 列数异常。", call. = FALSE)
  S <- shap_raw[, seq_len(ncol(shap_raw) - 1L), drop = FALSE]
  cn <- colnames(X_mat)
  if (length(cn) == ncol(S)) colnames(S) <- cn
  shapviz::shapviz(S, X = X_df[, colnames(S), drop = FALSE])
}

.shap_linear_coef_vector <- function(wf, pred_cols) {
  if (!.shap_is_workflow_like(wf)) stop("linear_coef 需要 workflow。", call. = FALSE)
  eng <- .shap_extract_engine(wf)
  if (is.null(eng)) stop("无法 extract_fit_engine。", call. = FALSE)
  coefs <- NULL
  if (inherits(eng, "glm")) {
    cf <- stats::coef(eng)
    coefs <- cf[setdiff(names(cf), "(Intercept)")]
  } else if (inherits(eng, "glmnet")) {
    cm <- as.matrix(stats::coef(eng))
    cf <- cm[, ncol(cm), drop = TRUE]
    coefs <- cf[setdiff(names(cf), "(Intercept)")]
  } else if (inherits(eng, "logistic_reg")) {
    cf <- eng$fit$coef %||% eng$coefficients
    if (!is.null(cf)) coefs <- cf[setdiff(names(cf), "(Intercept)")]
  }
  if (is.null(coefs) || !length(coefs)) {
    stop("linear_coef: 无法从引擎提取系数（", class(eng)[[1L]], "）。", call. = FALSE)
  }
  out <- rep(0, length(pred_cols))
  names(out) <- pred_cols
  hit <- intersect(names(coefs), pred_cols)
  out[hit] <- as.numeric(coefs[hit])
  out
}

.shap_build_linear_coef <- function(wf, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  pred_cols <- colnames(X_df)
  coef_vec <- .shap_linear_coef_vector(wf, pred_cols)
  baseline <- vapply(X_df, function(col) mean(col, na.rm = TRUE), numeric(1L))
  S <- sweep(as.matrix(X_df), 2L, baseline, FUN = "-")
  S <- sweep(S, 2L, coef_vec, FUN = "*")
  storage.mode(S) <- "double"
  colnames(S) <- pred_cols
  shapviz::shapviz(S, X = X_df)
}

.shap_pred_prob_wrapper <- function(wf) {
  function(object, newdata) {
    p <- predict(object, new_data = newdata, type = "prob")
    if (!is.data.frame(p)) return(as.numeric(p))
    cols <- grep("^\\.pred", names(p), value = TRUE)
    if (!length(cols)) return(as.numeric(p[[ncol(p)]]))
    pos <- cols[!grepl("0|ref|control|no|false", cols, ignore.case = TRUE)]
    as.numeric(p[[if (length(pos)) pos[[1L]] else cols[[length(cols)]]]])
  }
}

.shap_build_kernelshap <- function(wf, X_df, sh_cfg) {
  if (!requireNamespace("kernelshap", quietly = TRUE)) {
    stop("kernelshap 不可用。", call. = FALSE)
  }
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  if (!.shap_is_workflow_like(wf)) {
    stop("kernelshap 需要 tidymodels workflow。", call. = FALSE)
  }
  source_ids <- attr(X_df, "shap_source_row_ids", exact = TRUE)
  X <- as.data.frame(X_df)
  if (is.null(source_ids) || length(source_ids) != nrow(X)) source_ids <- seq_len(nrow(X))
  n <- nrow(X)
  bg_n <- as.integer(sh_cfg$kernel_bg_n %||% 30L)[1L]
  bg_n <- min(max(5L, bg_n), max(5L, n - 1L))
  explain_n <- as.integer(sh_cfg$kernel_explain_n %||% min(80L, n))[1L]
  explain_n <- min(max(10L, explain_n), n)
  set.seed(as.integer(sh_cfg$kernel_seed %||% 42L))
  bg <- X[sample.int(n, bg_n), , drop = FALSE]
  X_explain <- X[seq_len(explain_n), , drop = FALSE]
  pred_fun <- .shap_pred_prob_wrapper(wf)
  ks <- kernelshap::kernelshap(
    wf, X = X_explain, bg_X = bg, pred_fun = pred_fun
  )
  out <- shapviz::shapviz(ks, X = X_explain)
  attr(out, "shap_source_row_ids") <- as.integer(source_ids[seq_len(explain_n)])
  out
}

.shap_build_kernel_perm <- function(wf, X_df, sh_cfg) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  if (!.shap_is_workflow_like(wf)) {
    stop("kernel_perm 需要 tidymodels workflow。", call. = FALSE)
  }
  source_ids <- attr(X_df, "shap_source_row_ids", exact = TRUE)
  X <- as.data.frame(X_df)
  if (is.null(source_ids) || length(source_ids) != nrow(X)) source_ids <- seq_len(nrow(X))
  n <- nrow(X)
  p <- ncol(X)
  if (n < 2L || p < 1L) stop("kernel_perm: 样本或特征不足。", call. = FALSE)
  bg_n <- as.integer(sh_cfg$kernel_bg_n %||% 20L)[1L]
  bg_n <- min(max(5L, bg_n), n)
  explain_n <- as.integer(sh_cfg$kernel_explain_n %||% min(60L, n))[1L]
  explain_n <- min(max(5L, explain_n), n)
  set.seed(as.integer(sh_cfg$kernel_seed %||% 42L))
  explain_idx <- sample.int(n, explain_n)
  bg_pool <- setdiff(seq_len(n), explain_idx)
  bg_idx <- if (length(bg_pool)) {
    sample(bg_pool, min(bg_n, length(bg_pool)))
  } else {
    sample.int(n, bg_n)
  }
  pred <- .shap_pred_prob_wrapper(wf)
  bg <- X[bg_idx, , drop = FALSE]
  S <- matrix(0, nrow = length(explain_idx), ncol = p)
  colnames(S) <- names(X)
  X_explain <- X[explain_idx, , drop = FALSE]
  for (ii in seq_along(explain_idx)) {
    xi <- X_explain[ii, , drop = FALSE]
    for (fj in seq_len(p)) {
      diffs <- vapply(seq_len(nrow(bg)), function(b) {
        x1 <- bg[b, , drop = FALSE]
        x2 <- x1
        x1[[fj]] <- xi[[fj]]
        pred(wf, x1) - pred(wf, x2)
      }, numeric(1))
      S[ii, fj] <- mean(diffs)
    }
  }
  out <- shapviz::shapviz(S, X = X_explain)
  attr(out, "shap_source_row_ids") <- as.integer(source_ids[explain_idx])
  out
}

.shap_build_kernel_fastshap <- function(wf, X_df, sh_cfg) {
  if (requireNamespace("fastshap", quietly = TRUE)) {
    if (!requireNamespace("shapviz", quietly = TRUE)) {
      stop("需要 shapviz 包。", call. = FALSE)
    }
    if (!.shap_is_workflow_like(wf)) {
      stop("kernel_fastshap 需要 tidymodels workflow。", call. = FALSE)
    }
    nsim <- as.integer(sh_cfg$linear_fastshap_nsim %||% sh_cfg$kernel_nsim %||% 50L)[1L]
    if (!is.finite(nsim) || nsim < 10L) nsim <- 50L
    bg_n <- as.integer(sh_cfg$kernel_bg_n %||% sh_cfg$linear_bg_n %||% 30L)[1L]
    if (!is.finite(bg_n) || bg_n < 5L) bg_n <- 30L
    source_ids <- attr(X_df, "shap_source_row_ids", exact = TRUE)
    X <- as.data.frame(X_df)
    if (is.null(source_ids) || length(source_ids) != nrow(X)) source_ids <- seq_len(nrow(X))
    n <- nrow(X)
    bg_n <- min(bg_n, max(5L, n - 1L))
    set.seed(as.integer(sh_cfg$kernel_seed %||% 42L))
    bg <- X[sample.int(n, bg_n), , drop = FALSE]
    explain_n <- as.integer(sh_cfg$kernel_explain_n %||% min(80L, n))[1L]
    explain_n <- min(max(10L, explain_n), n)
    X_explain <- X[seq_len(explain_n), , drop = FALSE]
    pred_wrapper <- .shap_pred_prob_wrapper(wf)
    shap_out <- tryCatch(
      fastshap::explain(
        object = wf,
        X = X_explain,
        pred_wrapper = pred_wrapper,
        background = bg,
        nsim = nsim,
        adjust = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning("block_shap: fastshap 失败 ({e$message})。")
        NULL
      }
    )
    if (!is.null(shap_out)) {
      out <- shapviz::shapviz(shap_out, X = X_explain)
      attr(out, "shap_source_row_ids") <- as.integer(source_ids[seq_len(explain_n)])
      return(out)
    }
  }
  if (requireNamespace("kernelshap", quietly = TRUE)) {
    cli::cli_alert_info("block_shap: 使用 kernelshap（fastshap 未用或失败）。")
    out <- .shap_build_kernelshap(wf, X_df, sh_cfg)
    attr(out, "shap_method") <- "kernelshap"
    return(out)
  }
  cli::cli_alert_info("block_shap: fastshap/kernelshap 不可用，使用 permutation Kernel SHAP。")
  .shap_build_kernel_perm(wf, X_df, sh_cfg)
}

.shap_build_kernel_tabpfn <- function(wf, X_df, sh_cfg, ctx = NULL) {
  if (!is.null(wf) && .shap_is_workflow_like(wf)) {
    return(.shap_build_kernel_fastshap(wf, X_df, sh_cfg))
  }
  proxy <- sh_cfg$proxy_tree_priority %||% c("xgboost", "lightgbm", "rf", "dt")
  models <- ctx$results$ml_models %||% list()
  for (tg in proxy) {
    if (!tg %in% names(models)) next
    pwf <- models[[tg]]
    if (!.shap_is_workflow_like(pwf)) next
    cli::cli_alert_info(
      "block_shap: tabpfn 无 workflow，代理至 {tg} 做 SHAP。"
    )
    res <- .shap_compute_for_tag(tg, pwf, list(X_df = X_df, X_mat = as.matrix(X_df)), sh_cfg, ctx)
    attr(res, "shap_method") <- paste0(
      "kernel_tabpfn_proxy:", attr(res, "shap_method") %||% "tree_shapviz"
    )
    attr(res, "shap_tag") <- "tabpfn"
    return(res)
  }
  stop("tabpfn 无 workflow 且无可代理树模型。", call. = FALSE)
}

###############################################################################
#  生存模型 SHAP（非 tidymodels workflow）
###############################################################################

.shap_surv_scale01 <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  rng <- range(x[is.finite(x)], na.rm = TRUE)
  if (!all(is.finite(rng)) || diff(rng) < 1e-12) return(rep(0.5, length(x)))
  (x - rng[1]) / (rng[2] - rng[1])
}

.shap_surv_align_matrix <- function(model, X_mat, X_df) {
  fn <- tryCatch({
    if (inherits(model, "xgb.Booster")) model$feature_names else NULL
  }, error = function(e) NULL)
  fn <- as.character(fn %||% character(0))
  if (!length(fn)) return(list(X_mat = X_mat, X_df = X_df))
  miss <- setdiff(fn, colnames(X_mat))
  if (length(miss)) {
    add0 <- matrix(0, nrow = nrow(X_mat), ncol = length(miss))
    colnames(add0) <- miss
    X_mat <- cbind(X_mat, add0)
    X_df <- cbind(X_df, as.data.frame(add0, check.names = FALSE))
  }
  keep <- intersect(fn, colnames(X_mat))
  list(X_mat = X_mat[, keep, drop = FALSE], X_df = X_df[, keep, drop = FALSE])
}

.shap_surv_predict_risk <- function(tag, model, X_df) {
  tag <- tolower(trimws(as.character(tag)[1L]))
  X <- as.data.frame(X_df)
  ## mboost / gbm / rsf / survivalsvm 需要与训练一致的列类型（可含 factor）
  keep_factor <- tag %in% c("mboost_cox", "gbmsurv", "rsf", "survivalsvm")
  if (!keep_factor) {
    for (cn in names(X)) {
      if (!is.numeric(X[[cn]])) X[[cn]] <- suppressWarnings(as.numeric(as.factor(as.character(X[[cn]]))))
    }
  } else {
    for (cn in names(X)) {
      if (is.character(X[[cn]])) X[[cn]] <- factor(X[[cn]])
    }
  }
  X_mat <- X
  for (cn in names(X_mat)) {
    if (is.factor(X_mat[[cn]]) || is.character(X_mat[[cn]])) {
      X_mat[[cn]] <- as.numeric(factor(as.character(X_mat[[cn]])))
    }
  }
  X_mat <- as.matrix(X_mat)
  storage.mode(X_mat) <- "double"

  risk <- tryCatch({
    if (identical(tag, "xgbsurv") && inherits(model, "xgb.Booster")) {
      al <- .shap_surv_align_matrix(model, X_mat, as.data.frame(X_mat))
      as.numeric(stats::predict(model, xgboost::xgb.DMatrix(al$X_mat)))
    } else if (identical(tag, "rsf") && inherits(model, "rfsrc")) {
      ## 训练用 time/status 列名；预测只需特征列
      nd <- X
      names(nd)[names(nd) == ".time"] <- "time"
      names(nd)[names(nd) == ".event"] <- "status"
      pr <- stats::predict(model, newdata = nd)
      as.numeric(pr$predicted)
    } else if (identical(tag, "coxboost")) {
      as.numeric(stats::predict(model, newdata = X_mat, type = "lp"))
    } else if (identical(tag, "gbmsurv")) {
      ntr <- if (!is.null(model$n.trees)) model$n.trees else 100L
      as.numeric(gbm::predict.gbm(model, newdata = X, n.trees = ntr, type = "link"))
    } else if (tag %in% c("ridge_cox", "enet_cox")) {
      ## glmnet 需要与训练相同的 dummy 列；缺列补 0
      cn <- tryCatch(rownames(stats::coef(model)), error = function(e) colnames(X_mat))
      cn <- as.character(cn %||% colnames(X_mat))
      cn <- cn[nzchar(cn) & cn != "(Intercept)"]
      miss <- setdiff(cn, colnames(X_mat))
      if (length(miss)) {
        add0 <- matrix(0, nrow = nrow(X_mat), ncol = length(miss))
        colnames(add0) <- miss
        X_mat <- cbind(X_mat, add0)
      }
      X_use <- X_mat[, cn, drop = FALSE]
      as.numeric(stats::predict(model, newx = X_use, s = "lambda.min", type = "link"))
    } else if (identical(tag, "mboost_cox")) {
      ## 与训练一致：model.matrix 数值设计 + .time/.event 占位
      lv <- attr(model, "mlsurv_train_levels")
      X_raw <- as.data.frame(X_df)
      if (is.list(lv) && length(lv)) {
        for (cn in names(lv)) {
          if (!cn %in% names(X_raw) || is.null(lv[[cn]])) next
          X_raw[[cn]] <- factor(as.character(X_raw[[cn]]), levels = lv[[cn]])
        }
      }
      ## 构造与训练相同的 design：优先用存储的列名对齐
      tmp <- X_raw
      if (!".time" %in% names(tmp)) tmp$.time <- 1
      if (!".event" %in% names(tmp)) tmp$.event <- 0L
      ## 用与 .mlsurv_model_matrix 相同方式展开
      feat_cols <- setdiff(names(tmp), c(".time", ".event"))
      form <- stats::as.formula(paste("~", paste(feat_cols, collapse = " + ")))
      mm <- stats::model.matrix(form, data = tmp)
      mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
      design_cols <- attr(model, "mlsurv_design_cols")
      if (length(design_cols)) {
        miss <- setdiff(design_cols, colnames(mm))
        if (length(miss)) {
          add0 <- matrix(0, nrow = nrow(mm), ncol = length(miss))
          colnames(add0) <- miss
          mm <- cbind(mm, add0)
        }
        mm <- mm[, design_cols, drop = FALSE]
      }
      nd <- data.frame(.time = tmp$.time, .event = tmp$.event, mm,
                      check.names = FALSE, stringsAsFactors = FALSE)
      as.numeric(stats::predict(model, newdata = nd, type = "link"))
    } else if (identical(tag, "survivalsvm")) {
      pr <- stats::predict(model, newdata = X)
      x <- if (is.list(pr) && !is.null(pr$predicted)) pr$predicted else pr
      if (is.list(x) && !is.data.frame(x) && !is.atomic(x)) x <- unlist(x)
      as.numeric(x)
    } else {
      stop("未知生存模型 tag: ", tag, call. = FALSE)
    }
  }, error = function(e) {
    stop("生存模型预测失败 [", tag, "]: ", conditionMessage(e), call. = FALSE)
  })
  .shap_surv_scale01(risk)
}

.shap_build_surv_xgbsurv <- function(model, X_mat, X_df) {
  if (!inherits(model, "xgb.Booster")) {
    stop("surv_xgbsurv 需要 xgb.Booster。", call. = FALSE)
  }
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz。", call. = FALSE)
  }
  al <- .shap_surv_align_matrix(model, X_mat, X_df)
  out <- shapviz::shapviz(model, X_pred = al$X_mat, X = al$X_df)
  attr(out, "shap_method") <- "surv_xgbsurv_tree"
  out
}

.shap_build_surv_glmnet_cox <- function(model, X_mat, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz。", call. = FALSE)
  }
  ## 线性近似 SHAP：β_j * (x_j - mean_j)
  b <- tryCatch({
    suppressPackageStartupMessages(requireNamespace("glmnet", quietly = TRUE))
    as.matrix(coef(model, s = "lambda.min"))
  }, error = function(e) NULL)
  if (is.null(b) || !nrow(b)) {
    b <- tryCatch({
      j <- which.min(abs(model$lambda - model$lambda.min))
      as.matrix(model$glmnet.fit$beta[, j, drop = FALSE])
    }, error = function(e2) NULL)
  }
  if (is.null(b)) stop("glmnet Cox 系数不可用。", call. = FALSE)
  rn <- rownames(b)
  beta <- as.numeric(b[, 1L])
  names(beta) <- rn
  beta <- beta[abs(beta) > 1e-12]
  cols <- intersect(names(beta), colnames(X_mat))
  if (!length(cols)) stop("glmnet Cox 无非零系数对齐特征。", call. = FALSE)
  X_use <- as.matrix(X_mat[, cols, drop = FALSE])
  mu <- colMeans(X_use, na.rm = TRUE)
  S <- sweep(X_use, 2L, mu, "-")
  S <- sweep(S, 2L, beta[cols], "*")
  out <- shapviz::shapviz(S, X = as.data.frame(X_use))
  attr(out, "shap_method") <- "surv_glmnet_linear"
  out
}

.shap_build_surv_kernel <- function(tag, model, X_df, sh_cfg) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz。", call. = FALSE)
  }
  tag0 <- tolower(trimws(as.character(tag)[1L]))
  ## RSF/GBM 等训练用 factor；若这里先 as.numeric(factor)→整数码再喂 predict，
  ## 分类列扰动几乎不改变预测 → SHAP 图上大量 0.000（假零）。
  keep_factor <- tag0 %in% c("mboost_cox", "gbmsurv", "rsf", "survivalsvm")
  X <- as.data.frame(X_df)
  for (cn in names(X)) {
    if (keep_factor) {
      if (is.character(X[[cn]]) || is.logical(X[[cn]])) {
        X[[cn]] <- factor(as.character(X[[cn]]))
      }
      ## 已是 factor / numeric 原样保留
    } else if (!is.numeric(X[[cn]])) {
      X[[cn]] <- suppressWarnings(as.numeric(as.factor(as.character(X[[cn]]))))
    }
  }
  n <- nrow(X)
  if (n < 5L || ncol(X) < 1L) stop("surv_kernel: 样本/特征不足。", call. = FALSE)
  explain_n <- as.integer(sh_cfg$kernel_explain_n %||% min(80L, n))[1L]
  explain_n <- min(max(10L, explain_n), n)
  bg_n <- as.integer(sh_cfg$kernel_bg_n %||% 30L)[1L]
  bg_n <- min(max(5L, bg_n), max(5L, n - 1L))
  set.seed(as.integer(sh_cfg$kernel_seed %||% 42L))
  X_explain <- X[seq_len(explain_n), , drop = FALSE]
  bg <- X[sample.int(n, bg_n), , drop = FALSE]

  pred_fun <- function(object, newdata) {
    .shap_surv_predict_risk(tag, object, newdata)
  }

  if (requireNamespace("fastshap", quietly = TRUE)) {
    fs <- tryCatch(
      fastshap::explain(
        model,
        X = X_explain,
        pred_wrapper = function(object, newdata) pred_fun(object, newdata),
        nsim = as.integer(sh_cfg$fastshap_nsim %||% 50L)[1L],
        adjust = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning(
          "block_shap surv_fastshap 失败 ({e$message})，改用保留类型的置换近似。"
        )
        NULL
      }
    )
    if (!is.null(fs)) {
      ## shapviz 的 X 展示层：factor 转数值码仅用于着色，不参与再预测
      X_plot <- X_explain
      for (cn in names(X_plot)) {
        if (is.factor(X_plot[[cn]]) || is.character(X_plot[[cn]])) {
          X_plot[[cn]] <- as.numeric(factor(as.character(X_plot[[cn]])))
        }
      }
      out <- shapviz::shapviz(fs, X = X_plot)
      attr(out, "shap_method") <- "surv_fastshap"
      return(out)
    }
  }

  ## 无 fastshap：特征置换近似
  p <- ncol(X_explain)
  S <- matrix(0, nrow = nrow(X_explain), ncol = p)
  colnames(S) <- names(X_explain)
  base <- pred_fun(model, bg)
  for (j in seq_len(p)) {
    for (i in seq_len(nrow(X_explain))) {
      diffs <- vapply(seq_len(nrow(bg)), function(b) {
        x1 <- bg[b, , drop = FALSE]
        x0 <- x1
        x1[[j]] <- X_explain[[j]][i]
        pred_fun(model, x1) - pred_fun(model, x0)
      }, numeric(1))
      S[i, j] <- mean(diffs)
    }
  }
  out <- shapviz::shapviz(S, X = {
    X_plot <- X_explain
    for (cn in names(X_plot)) {
      if (is.factor(X_plot[[cn]]) || is.character(X_plot[[cn]])) {
        X_plot[[cn]] <- as.numeric(factor(as.character(X_plot[[cn]])))
      }
    }
    X_plot
  })
  attr(out, "shap_method") <- "surv_kernel_perm"
  out
}

.shap_compute_for_tag <- function(tag, wf, baked, sh_cfg, ctx = NULL) {
  method <- .shap_method_for_tag(tag, wf)
  X_mat <- baked$X_mat
  X_df <- baked$X_df
  cli::cli_alert_info("block_shap [{tag}]: 方法={method}")
  actual_method <- method

  .do_compute <- function(m) {
    switch(m,
      tree_shapviz = .shap_build_tree_shapviz(wf, X_mat, X_df),
      catboost_native = .shap_build_catboost_native(wf, X_mat, X_df),
      linear_coef = .shap_build_linear_coef(wf, X_df),
      kernel_fastshap = .shap_build_kernel_fastshap(wf, X_df, sh_cfg),
      kernel_tabpfn = .shap_build_kernel_tabpfn(wf, X_df, sh_cfg, ctx),
      surv_xgbsurv = .shap_build_surv_xgbsurv(wf, X_mat, X_df),
      surv_glmnet_cox = .shap_build_surv_glmnet_cox(wf, X_mat, X_df),
      surv_kernel = .shap_build_surv_kernel(tag, wf, X_df, sh_cfg),
      stop("未知 SHAP 方法: ", m, call. = FALSE)
    )
  }

  out <- tryCatch(
    .do_compute(method),
    error = function(e) {
      if (method %in% c("tree_shapviz", "catboost_native", "surv_xgbsurv", "surv_glmnet_cox")) {
        cli::cli_alert_warning(
          "block_shap [{tag}]: {method} 失败 ({e$message})，回退 surv_kernel/kernel_fastshap。"
        )
        if (tag %in% .shap_surv_tags()) {
          actual_method <<- "surv_kernel"
          return(.do_compute("surv_kernel"))
        }
        actual_method <<- if (requireNamespace("fastshap", quietly = TRUE)) {
          "kernel_fastshap"
        } else if (requireNamespace("kernelshap", quietly = TRUE)) {
          "kernelshap"
        } else {
          "kernel_perm"
        }
        return(.do_compute("kernel_fastshap"))
      }
      stop(e)
    }
  )

  inner_method <- attr(out, "shap_method")
  if (!is.null(inner_method) && nzchar(inner_method)) {
    actual_method <- inner_method
  }

  attr(out, "shap_method") <- actual_method
  attr(out, "shap_tag") <- tag
  out
}

.shap_interpret_tag_order <- function(ctx, sh_cfg, fitted_names) {
  fitted_names <- as.character(fitted_names)[nzchar(as.character(fitted_names))]
  primary <- .shap_resolve_model_tag(ctx, sh_cfg, fitted_names)
  ## 预后 / force_kernel：最优模型必须排第一，其后才允许失败回退
  if (isTRUE(sh_cfg$force_kernel_best_model %||% FALSE) ||
      identical(tolower(trimws(ctx$config$project$study_type %||% "")), "prognosis")) {
    return(unique(c(primary, setdiff(fitted_names, primary))))
  }
  proxy_trees <- .shap_shapviz_capable_tags()
  proxy <- .shap_pick_best_tag_among(ctx, fitted_names, proxy_trees)
  c(
    primary,
    setdiff(fitted_names, primary),
    setdiff(proxy_trees, fitted_names)
  )
}

.shap_prioritize_waterfall_case <- function(ctx, sh_cfg, tag, baked) {
  if (is.null(baked$X_df) || !is.data.frame(baked$X_df) ||
      !nrow(baked$X_df) ||
      isFALSE(sh_cfg$waterfall_auto_case_high_prob %||% TRUE) ||
      !identical(tolower(as.character(sh_cfg$explain_on %||% "train")[1L]), "train")) {
    return(baked)
  }
  tr <- tryCatch(.shap_ml_train_frame(ctx, shap_plot_only = TRUE), error = function(e) NULL)
  if (is.null(tr) || nrow(tr) != nrow(baked$X_df) || !"Group" %in% names(tr)) return(baked)
  models_dir <- if (exists("resolve_ml_models_dir_for_tag", mode = "function")) {
    resolve_ml_models_dir_for_tag(ctx, tag)
  } else {
    ""
  }
  rdata <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  if (!file.exists(rdata)) return(baked)
  env <- new.env(parent = emptyenv())
  if (!isTRUE(tryCatch({ load(rdata, envir = env); TRUE }, error = function(e) FALSE))) {
    return(baked)
  }
  pt <- env$predtrain %||% env[[paste0("predtrain_", tag)]]
  if (is.null(pt) || !is.data.frame(pt) || nrow(pt) != nrow(tr)) return(baked)
  ana <- trimws(as.character(
    ctx$config$project$analysis_group %||% ctx$config$project$disease %||% "Case"
  )[1L])
  pred_col <- ctx$results$ml_pred_ana_col %||% paste0(".pred_", make.names(ana))
  if (!pred_col %in% names(pt)) return(baked)
  outcome01 <- as.integer(trimws(as.character(tr$Group)) == ana)
  threshold <- suppressWarnings(as.numeric(sh_cfg$waterfall_prob_threshold %||% 0.75)[1L])
  pick <- pipeline_pick_shap_waterfall_row(
    ctx, as.numeric(pt[[pred_col]]), outcome01, prob_threshold = threshold
  )
  rid <- suppressWarnings(as.integer(pick$row_id)[1L])
  if (!isTRUE(pick$met_threshold) || !is.finite(rid) ||
      rid < 1L || rid > nrow(baked$X_df)) {
    return(baked)
  }
  ord <- c(rid, setdiff(seq_len(nrow(baked$X_df)), rid))
  baked$X_df <- baked$X_df[ord, , drop = FALSE]
  attr(baked$X_df, "shap_source_row_ids") <- as.integer(ord)
  if (!is.null(baked$X_mat) && nrow(baked$X_mat) == length(ord)) {
    baked$X_mat <- baked$X_mat[ord, , drop = FALSE]
  }
  baked
}

.shap_try_compute_best <- function(ctx, sh_cfg, models) {
  fitted <- names(models)
  order_tags <- unique(.shap_interpret_tag_order(ctx, sh_cfg, fitted))
  explain_on <- sh_cfg$explain_on %||% "train"
  last_err <- NULL
  force_best <- isTRUE(sh_cfg$force_kernel_best_model %||% FALSE) ||
    identical(tolower(trimws(ctx$config$project$study_type %||% "")), "prognosis")
  for (tag in order_tags) {
    if (!tag %in% fitted || is.null(models[[tag]])) next
    wf <- models[[tag]]
    is_surv <- tag %in% .shap_surv_tags()
    if (tag %in% .shap_tabpfn_tags() && !.shap_is_workflow_like(wf)) {
      baked <- tryCatch(
        .shap_baked_matrix(ctx, tag, explain_on, sh_cfg = sh_cfg),
        error = function(e) NULL
      )
      if (is.null(baked)) next
      shp <- tryCatch(
        .shap_compute_for_tag(tag, wf, baked, sh_cfg, ctx),
        error = function(e) { last_err <<- e$message; NULL }
      )
      if (!is.null(shp)) {
        return(list(tag = tag, shp = shp, baked = baked, method = attr(shp, "shap_method")))
      }
      if (force_best) break
      next
    }
    if (is_surv) {
      sh_surv <- modifyList(sh_cfg %||% list(), list(use_train_without_recipe = TRUE))
      baked <- tryCatch(
        .shap_baked_matrix(ctx, tag, explain_on, sh_cfg = sh_surv),
        error = function(e) { last_err <<- e$message; NULL }
      )
      if (is.null(baked)) {
        if (force_best) break
        next
      }
      shp <- tryCatch(
        .shap_compute_for_tag(tag, wf, baked, sh_cfg, ctx),
        error = function(e) { last_err <<- e$message; NULL }
      )
      if (!is.null(shp)) {
        return(list(tag = tag, shp = shp, baked = baked, method = attr(shp, "shap_method")))
      }
      if (force_best) {
        cli::cli_alert_warning(
          "block_shap: 最优生存模型 {tag} SHAP 失败（{last_err}），按铁律不回退其它模型。"
        )
        break
      }
      next
    }
    if (!.shap_is_workflow_like(wf)) next
    baked <- tryCatch(
      .shap_baked_matrix(ctx, tag, explain_on, sh_cfg = sh_cfg, wf = wf),
      error = function(e) { last_err <<- e$message; NULL }
    )
    if (is.null(baked)) next
    baked <- .shap_prioritize_waterfall_case(ctx, sh_cfg, tag, baked)
    shp <- tryCatch(
      .shap_compute_for_tag(tag, wf, baked, sh_cfg, ctx),
      error = function(e) { last_err <<- e$message; NULL }
    )
    if (!is.null(shp)) {
      return(list(tag = tag, shp = shp, baked = baked, method = attr(shp, "shap_method")))
    }
    if (force_best) break
  }
  list(tag = NULL, shp = NULL, baked = NULL, method = NULL, error = last_err)
}
