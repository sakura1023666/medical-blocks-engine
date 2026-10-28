###############################################################################
#  feature_selection_entropy_stepwise — Wang 2025 TCF 特征处理
#
#  文献：PMID 40295871 Methods Data preprocessing (1)–(5)
#  (1) 缺失率 > missing_threshold 删除
#  (2) 布尔特征众数占比 > boolean_mode_max 删除（原文 >90% 一致）
#  (3) 插补方法择优 — 由上游 imputation 块完成（本课题 logistic_mi）
#  (4) |Pearson| ≥ corr_threshold 成对比较，保留单变量 AUC 更大者
#  (5) 信息熵排序 + 逐步加特征至路径 AUC 局部最优
#
#  register_block: "feature_selection_entropy_stepwise"
#  注意：须在 train 上拟合；最终集为路径局部最优（见对抗 Q4）
###############################################################################

.fsent11_entropy <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(0)
  ## 连续变量：分位箱离散化后算熵
  br <- unique(stats::quantile(x, probs = seq(0, 1, length.out = 11L), na.rm = TRUE))
  if (length(br) < 3L) return(0)
  g <- cut(x, breaks = br, include.lowest = TRUE)
  p <- as.numeric(table(g)) / length(g)
  p <- p[p > 0]
  -sum(p * log2(p))
}

.fsent11_is_booleanish <- function(x) {
  if (is.logical(x)) return(TRUE)
  if (is.factor(x)) {
    return(nlevels(droplevels(x)) <= 2L)
  }
  x <- x[!is.na(x)]
  if (!length(x)) return(FALSE)
  if (is.character(x)) return(length(unique(x)) <= 2L)
  if (is.numeric(x) || is.integer(x)) {
    ux <- unique(as.numeric(x))
    ux <- ux[is.finite(ux)]
    return(length(ux) <= 2L)
  }
  FALSE
}

.fsent11_to_num <- function(x) {
  if (is.logical(x)) return(as.integer(x))
  if (is.factor(x)) return(as.integer(x))
  if (is.character(x)) {
    ux <- unique(x[!is.na(x)])
    if (length(ux) <= 2L) return(as.integer(factor(x, levels = ux)))
    return(suppressWarnings(as.numeric(x)))
  }
  as.numeric(x)
}

.fsent11_outcome01 <- function(data, outcome_col, ana) {
  as.integer(
    as.character(data[[outcome_col]]) == ana |
      as.character(data[[outcome_col]]) == "1" |
      tolower(as.character(data[[outcome_col]])) %in%
        c("non-survivor", "nonsurvivor", "dead", "death", "expired", "yes")
  )
}

.fsent11_univ_auc <- function(x, y) {
  x <- .fsent11_to_num(x)
  ok <- is.finite(x) & !is.na(y)
  if (sum(ok) < 20L || length(unique(y[ok])) < 2L) return(NA_real_)
  fit <- tryCatch(
    stats::glm(y[ok] ~ x[ok], family = binomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA_real_)
  p <- as.numeric(stats::predict(fit, type = "response"))
  tryCatch(
    as.numeric(pROC::auc(pROC::roc(y[ok], p, quiet = TRUE))),
    error = function(e) NA_real_
  )
}

.fsent11_drop_leak <- function(names_all, cfg) {
  outcome_col <- cfg$data$outcome_column
  id_col <- cfg$data$id_column
  strip_ids <- as.character(
    (cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)
  )
  leak <- c(
    "stay_id", "hadm_id", "subject_id", "hosp_day", "icu_day",
    "is_hosp_dead", "is_icu_dead", "death_within_hosp_28days", "death_within_icu_28days",
    "hosp_survival_day", "icu_survival_day", "Group", "Disease_Group", "Disease",
    "fustatus", "futime", "DN", "is_dead"
  )
  drop <- unique(c(
    outcome_col, id_col, strip_ids, leak,
    cfg$survival$time_var, cfg$survival$event_var
  ))
  drop <- drop[nzchar(as.character(drop))]
  setdiff(names_all, drop)
}

.fsent11_missing_filter <- function(data_miss, cand, thr) {
  if (is.null(data_miss) || !is.data.frame(data_miss) || !length(cand)) {
    return(list(keep = cand, dropped = character(0), rates = numeric(0)))
  }
  rates <- vapply(cand, function(v) {
    if (!v %in% names(data_miss)) return(1)
    mean(is.na(data_miss[[v]]))
  }, numeric(1))
  keep <- cand[is.finite(rates) & rates <= thr]
  list(
    keep = keep,
    dropped = setdiff(cand, keep),
    rates = rates
  )
}

.fsent11_boolean_variance_filter <- function(data, cand, mode_max) {
  dropped <- character(0)
  keep <- cand
  for (v in cand) {
    if (!v %in% names(data)) next
    x <- data[[v]]
    if (!.fsent11_is_booleanish(x)) next
    x <- x[!is.na(x)]
    if (!length(x)) {
      dropped <- c(dropped, v)
      next
    }
    tab <- sort(table(as.character(x)), decreasing = TRUE)
    mode_p <- as.numeric(tab[[1L]]) / length(x)
    if (is.finite(mode_p) && mode_p > mode_max) dropped <- c(dropped, v)
  }
  list(keep = setdiff(keep, dropped), dropped = unique(dropped))
}

.fsent11_corr_auc_filter <- function(data, cand, y, corr_thr) {
  if (length(cand) < 2L) {
    return(list(keep = cand, dropped = character(0), pairs = NULL))
  }
  mat <- sapply(cand, function(v) .fsent11_to_num(data[[v]]))
  if (!is.matrix(mat)) mat <- cbind(mat)
  colnames(mat) <- cand
  aucs <- vapply(cand, function(v) .fsent11_univ_auc(data[[v]], y), numeric(1))
  names(aucs) <- cand
  dropped <- character(0)
  pair_log <- list()
  ## 贪心：反复找 |r| 最大的超阈对，丢掉 AUC 较低者
  alive <- cand
  guard <- 0L
  while (length(alive) >= 2L && guard < 5000L) {
    guard <- guard + 1L
    sub <- mat[, alive, drop = FALSE]
    cr <- suppressWarnings(stats::cor(sub, use = "pairwise.complete.obs"))
    cr[is.na(cr)] <- 0
    diag(cr) <- 0
    abs_cr <- abs(cr)
    mx <- max(abs_cr, na.rm = TRUE)
    if (!is.finite(mx) || mx < corr_thr) break
    idx <- which(abs_cr == mx, arr.ind = TRUE)[1, ]
    a <- alive[[idx[[1]]]]
    b <- alive[[idx[[2]]]]
    aa <- aucs[[a]]
    bb <- aucs[[b]]
    if (!is.finite(aa)) aa <- -Inf
    if (!is.finite(bb)) bb <- -Inf
    drop_one <- if (aa >= bb) b else a
    keep_one <- if (identical(drop_one, a)) b else a
    pair_log[[length(pair_log) + 1L]] <- data.frame(
      var_a = a, var_b = b, abs_r = mx,
      auc_a = aucs[[a]], auc_b = aucs[[b]],
      dropped = drop_one, kept = keep_one,
      stringsAsFactors = FALSE
    )
    dropped <- c(dropped, drop_one)
    alive <- setdiff(alive, drop_one)
  }
  pairs_df <- if (length(pair_log)) {
    do.call(rbind, pair_log)
  } else {
    NULL
  }
  list(keep = alive, dropped = unique(dropped), pairs = pairs_df, univ_auc = aucs)
}

## 双库外验：候选须在伙伴库存在且缺失率 ≤ thr（否则冻结模型无法 bake/predict）
.fsent11_dual_db_intersect <- function(cand, cfg, thr) {
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable %||% FALSE)) {
    return(list(keep = cand, dropped = character(0), partner = NA_character_))
  }
  if (!exists("pipeline_dual_db_partner_key", mode = "function") ||
      !exists("pipeline_dual_db_load_analysis_df", mode = "function")) {
    cli::cli_alert_warning("TCF FS 双库交集：缺少 dual_db helper，跳过")
    return(list(keep = cand, dropped = character(0), partner = NA_character_))
  }
  partner <- tryCatch(pipeline_dual_db_partner_key(cfg), error = function(e) NULL)
  if (is.null(partner) || !nzchar(as.character(partner)[1L])) {
    return(list(keep = cand, dropped = character(0), partner = NA_character_))
  }
  dfp <- tryCatch(
    pipeline_dual_db_load_analysis_df(cfg, partner),
    error = function(e) NULL
  )
  if (!is.data.frame(dfp) || !ncol(dfp)) {
    cli::cli_alert_warning("TCF FS 双库交集：无法加载伙伴库 {partner}，跳过")
    return(list(keep = cand, dropped = character(0), partner = as.character(partner)[1L]))
  }
  thr <- as.numeric(thr)[1L]
  if (!is.finite(thr)) thr <- 0.30
  rates <- vapply(cand, function(v) {
    if (!v %in% names(dfp)) return(1)
    mean(is.na(dfp[[v]]))
  }, numeric(1))
  keep <- cand[is.finite(rates) & rates <= thr]
  list(
    keep = keep,
    dropped = setdiff(cand, keep),
    partner = as.character(partner)[1L],
    rates = rates
  )
}

block_feature_selection_entropy_stepwise <- function(ctx, ...) {
  cfg_blk <- ctx$config$feature_selection_entropy_stepwise %||%
    ctx$config$feature_selection$entropy_stepwise %||% list()
  if (isFALSE(cfg_blk$enable %||% TRUE)) return(ctx)

  paper_preprocess <- isTRUE(cfg_blk$paper_preprocess %||% TRUE)
  dual_intersect <- isTRUE(cfg_blk$dual_db_intersect %||% TRUE)
  miss_thr <- as.numeric(cfg_blk$missing_threshold %||% 0.30)[1L]
  mode_max <- as.numeric(cfg_blk$boolean_mode_max %||% 0.90)[1L]
  corr_thr <- as.numeric(cfg_blk$corr_threshold %||% 0.70)[1L]

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  data <- ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("feature_selection_entropy_stepwise: 无数据", call. = FALSE)

  ## 缺失率尽量用插补前 train 口径（对齐原文 step1）
  data_miss <- NULL
  cleaned <- ctx$data$cleaned %||% ctx$data$mapped
  if (!is.null(cleaned) && is.data.frame(cleaned)) {
    id_col <- ctx$config$data$id_column %||% "ID"
    if (id_col %in% names(cleaned) && id_col %in% names(data)) {
      ids <- as.character(data[[id_col]])
      data_miss <- cleaned[as.character(cleaned[[id_col]]) %in% ids, , drop = FALSE]
    } else if (nrow(cleaned) == nrow(data)) {
      data_miss <- cleaned
    }
  }
  if (is.null(data_miss)) data_miss <- data

  cand <- .fsent11_drop_leak(names(data), ctx$config)
  ## 数值 + 布尔/二分类因子均可入候选（原文含 Boolean）
  cand <- cand[vapply(cand, function(v) {
    x <- data[[v]]
    is.numeric(x) || is.integer(x) || is.logical(x) ||
      .fsent11_is_booleanish(x)
  }, logical(1))]
  if (!length(cand)) stop("无候选特征", call. = FALSE)

  audit <- list(
    n_start = length(cand),
    missing_threshold = miss_thr,
    boolean_mode_max = mode_max,
    corr_threshold = corr_thr
  )

  if (isTRUE(paper_preprocess)) {
    m1 <- .fsent11_missing_filter(data_miss, cand, miss_thr)
    cand <- m1$keep
    audit$missing_dropped <- m1$dropped
    audit$n_after_missing <- length(cand)
    cli::cli_alert_info(
      "TCF FS (1) 缺失>{miss_thr*100}%: 剔除 {length(m1$dropped)}，剩余 {length(cand)}"
    )

    if (isTRUE(dual_intersect)) {
      md <- .fsent11_dual_db_intersect(cand, ctx$config, miss_thr)
      cand <- md$keep
      audit$dual_db_dropped <- md$dropped
      audit$dual_db_partner <- md$partner
      audit$n_after_dual_intersect <- length(cand)
      cli::cli_alert_info(
        "TCF FS (1b) 双库交集（伙伴 {md$partner} 缺失≤{miss_thr*100}%）: 剔除 {length(md$dropped)}，剩余 {length(cand)}"
      )
    }

    m2 <- .fsent11_boolean_variance_filter(data, cand, mode_max)
    cand <- m2$keep
    audit$boolean_dropped <- m2$dropped
    audit$n_after_boolean <- length(cand)
    cli::cli_alert_info(
      "TCF FS (2) 布尔众数>{mode_max*100}%: 剔除 {length(m2$dropped)}，剩余 {length(cand)}"
    )
    cli::cli_alert_info("TCF FS (3) 插补：已由上游 imputation 完成，本块跳过")

    y <- .fsent11_outcome01(data, outcome_col, ana)
    m4 <- .fsent11_corr_auc_filter(data, cand, y, corr_thr)
    cand <- m4$keep
    audit$corr_dropped <- m4$dropped
    audit$corr_pairs <- m4$pairs
    audit$univ_auc <- m4$univ_auc
    audit$n_after_corr <- length(cand)
    cli::cli_alert_info(
      "TCF FS (4) |r|>={corr_thr} 成对留高 AUC: 剔除 {length(m4$dropped)}，剩余 {length(cand)}"
    )
  }

  if (length(cand) < 2L) {
    stop("TCF FS: 预处理后候选特征 < 2，无法熵逐步", call. = FALSE)
  }

  y <- .fsent11_outcome01(data, outcome_col, ana)
  ent <- sort(
    vapply(cand, function(v) .fsent11_entropy(.fsent11_to_num(data[[v]])), numeric(1)),
    decreasing = TRUE
  )
  ordered <- names(ent)
  ordered <- ordered[nzchar(ordered) & !is.na(ordered)]

  step <- as.integer(cfg_blk$step %||% 2L)[1L]
  max_k <- as.integer(cfg_blk$max_k %||% 50L)[1L]
  max_k <- max(2L, min(max_k, length(ordered)))
  ks <- seq(from = max(2L, step), to = max_k, by = step)
  if (!length(ks)) ks <- max_k
  aucs <- numeric(length(ks))
  for (i in seq_along(ks)) {
    k <- ks[[i]]
    xs <- ordered[seq_len(k)]
    xs <- xs[xs %in% names(data)]
    if (length(xs) < 2L) {
      aucs[[i]] <- NA_real_
      next
    }
    X <- as.matrix(data.frame(
      lapply(xs, function(v) {
        z <- .fsent11_to_num(data[[v]])
        z[!is.finite(z)] <- 0
        z
      }),
      check.names = FALSE
    ))
    colnames(X) <- xs
    fit <- tryCatch(
      stats::glm(y ~ ., data = data.frame(y = y, X, check.names = FALSE), family = binomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      aucs[[i]] <- NA_real_
      next
    }
    p <- as.numeric(stats::predict(fit, type = "response"))
    aucs[[i]] <- tryCatch(
      as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE))),
      error = function(e) NA_real_
    )
  }
  best_i <- which.max(aucs)
  if (!length(best_i) || !is.finite(aucs[[best_i]])) best_i <- length(ks)
  best_k <- ks[[best_i]]
  final <- ordered[seq_len(min(best_k, length(ordered)))]
  audit$n_final <- length(final)
  audit$best_k <- best_k
  audit$best_auc <- aucs[[best_i]]

  ctx$results$feature_selection_entropy_path <- data.frame(k = ks, AUC = aucs)
  ctx$results$feature_selection_final <- final
  ctx$results$feature_selection_entropy_ordered <- ordered
  ctx$results$feature_selection_tcf_audit <- audit
  ctx$results$ml_feature_names <- final
  ctx$results$selected_features <- final

  ## 双库外验：导出主库特征供 inherit（TCF 不走 ml_feature_selection_bundle）
  if (isTRUE((ctx$config$dual_db %||% list())$enable %||% FALSE) &&
      exists("pipeline_export_primary_ml_features", mode = "function")) {
    root <- ctx$config$project$output_dir %||%
      Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
    if (!nzchar(as.character(root)[1L])) root <- getwd()
    tryCatch(
      pipeline_export_primary_ml_features(ctx, root, ctx$config),
      error = function(e) {
        cli::cli_alert_warning("主库特征导出失败: {e$message}")
      }
    )
  }

  ## 落盘审计
  out_dir <- ctx$output_dir %||% ctx$output_dir_tables %||% NULL
  if (!is.null(out_dir) && dir.exists(dirname(out_dir))) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(
      data.frame(feature = final, stringsAsFactors = FALSE),
      file.path(out_dir, "tcf_features_final.csv"),
      row.names = FALSE
    )
    utils::write.csv(
      data.frame(k = ks, AUC = aucs),
      file.path(out_dir, "tcf_entropy_path.csv"),
      row.names = FALSE
    )
    if (!is.null(audit$corr_pairs)) {
      utils::write.csv(
        audit$corr_pairs,
        file.path(out_dir, "tcf_corr_pair_drops.csv"),
        row.names = FALSE
      )
    }
  }

  cli::cli_alert_success(
    "feature_selection_entropy_stepwise: 选中 {length(final)} 个特征（路径局部最优 k={best_k}, AUC={round(aucs[[best_i]], 3)}；paper_preprocess={paper_preprocess}）"
  )
  ctx
}

register_block(
  "feature_selection_entropy_stepwise",
  block_feature_selection_entropy_stepwise,
  "熵排序逐步特征（TCF；含原文缺失/方差/相关预处理）"
)
