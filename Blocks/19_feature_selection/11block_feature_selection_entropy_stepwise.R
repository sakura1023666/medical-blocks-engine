###############################################################################
#  feature_selection_entropy_stepwise — 信息熵排序 + 逐步加特征至 AUC 最优
#
#  文献：Wang 2025 TCF Methods 特征处理第(5)步（PMID 40295871）
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

block_feature_selection_entropy_stepwise <- function(ctx, ...) {
  cfg <- ctx$config$feature_selection_entropy_stepwise %||%
    ctx$config$feature_selection$entropy_stepwise %||% list()
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  data <- ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("feature_selection_entropy_stepwise: 无数据", call. = FALSE)

  id_col <- ctx$config$data$id_column
  strip_ids <- as.character(
    (ctx$config$data %||% list())$strip_id_columns_after_imputation %||% character(0)
  )
  ## 排除 ID / 时间 / 结局泄漏（院内死亡标志等）
  leak <- c(
    "stay_id", "hadm_id", "subject_id", "hosp_day", "icu_day",
    "is_hosp_dead", "is_icu_dead", "death_within_hosp_28days", "death_within_icu_28days",
    "hosp_survival_day", "icu_survival_day", "Group", "Disease_Group", "Disease"
  )
  drop <- unique(c(
    outcome_col, id_col, strip_ids, leak,
    ctx$config$survival$time_var, ctx$config$survival$event_var
  ))
  drop <- drop[nzchar(as.character(drop))]
  cand <- setdiff(names(data), drop)
  ## 仅数值/可强制数值
  cand <- cand[vapply(cand, function(v) is.numeric(data[[v]]) || is.integer(data[[v]]), logical(1))]
  if (!length(cand)) stop("无候选数值特征", call. = FALSE)

  y <- as.integer(as.character(data[[outcome_col]]) == ana | as.character(data[[outcome_col]]) == "1")
  ent <- sort(vapply(cand, function(v) .fsent11_entropy(data[[v]]), numeric(1)), decreasing = TRUE)
  ordered <- names(ent)
  ordered <- ordered[nzchar(ordered) & !is.na(ordered)]

  step <- as.integer(cfg$step %||% 2L)[1L]
  max_k <- as.integer(cfg$max_k %||% 50L)[1L]
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
    X <- as.matrix(data[, xs, drop = FALSE])
    storage.mode(X) <- "double"
    X[!is.finite(X)] <- 0
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

  ctx$results$feature_selection_entropy_path <- data.frame(k = ks, AUC = aucs)
  ctx$results$feature_selection_final <- final
  ctx$results$feature_selection_entropy_ordered <- ordered
  cli::cli_alert_success(
    "feature_selection_entropy_stepwise: 选中 {length(final)} 个特征（路径局部最优 k={best_k}, AUC={round(aucs[[best_i]],3)}）"
  )
  ctx
}

register_block(
  "feature_selection_entropy_stepwise",
  block_feature_selection_entropy_stepwise,
  "熵排序逐步特征（TCF）"
)
