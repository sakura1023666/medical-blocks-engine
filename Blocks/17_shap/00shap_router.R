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
  X <- as.data.frame(X_df)
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
  shapviz::shapviz(ks, X = X_explain)
}

.shap_build_kernel_perm <- function(wf, X_df, sh_cfg) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("需要 shapviz 包。", call. = FALSE)
  }
  if (!.shap_is_workflow_like(wf)) {
    stop("kernel_perm 需要 tidymodels workflow。", call. = FALSE)
  }
  X <- as.data.frame(X_df)
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
  shapviz::shapviz(S, X = X_explain)
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
    X <- as.data.frame(X_df)
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
      return(shapviz::shapviz(shap_out, X = X_explain))
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
      stop("未知 SHAP 方法: ", m, call. = FALSE)
    )
  }

  out <- tryCatch(
    .do_compute(method),
    error = function(e) {
      if (method %in% c("tree_shapviz", "catboost_native")) {
        cli::cli_alert_warning(
          "block_shap [{tag}]: {method} 失败 ({e$message})，回退 kernel_fastshap。"
        )
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
  proxy_trees <- .shap_shapviz_capable_tags()
  proxy <- .shap_pick_best_tag_among(ctx, fitted_names, proxy_trees)
  c(
    primary,
    setdiff(fitted_names, primary),
    setdiff(proxy_trees, fitted_names)
  )
}

.shap_try_compute_best <- function(ctx, sh_cfg, models) {
  fitted <- names(models)
  order_tags <- unique(.shap_interpret_tag_order(ctx, sh_cfg, fitted))
  explain_on <- sh_cfg$explain_on %||% "train"
  last_err <- NULL
  for (tag in order_tags) {
    if (!tag %in% fitted || is.null(models[[tag]])) next
    wf <- models[[tag]]
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
      next
    }
    if (!.shap_is_workflow_like(wf)) next
    baked <- tryCatch(
      .shap_baked_matrix(ctx, tag, explain_on, sh_cfg = sh_cfg, wf = wf),
      error = function(e) { last_err <<- e$message; NULL }
    )
    if (is.null(baked)) next
    shp <- tryCatch(
      .shap_compute_for_tag(tag, wf, baked, sh_cfg, ctx),
      error = function(e) { last_err <<- e$message; NULL }
    )
    if (!is.null(shp)) {
      return(list(tag = tag, shp = shp, baked = baked, method = attr(shp, "shap_method")))
    }
  }
  list(tag = NULL, shp = NULL, baked = NULL, method = NULL, error = last_err)
}
