###############################################################################
#  ml_topsis_fusion — TOPSIS 分类融合（TCF）
#
#  文献：Wang et al. npj Digit Med 2025;8:228 (PMID 40295871)
#  公开代码：Blocks/22_ml_models/_extract_npj_tcf/ + python/ml_tcf/topsis.py
#
#  前置：七子模型 test 概率 → ctx$results$ml_model_probs（或 ml_predictions_all 兜底）
#  默认六指标等权 TOPSIS → alpha → 加权概率；阈值 0.5
#
#  register_block: "ml_topsis_fusion"
#  建议流水线位置：ml_models_bundle 之后、performance_ml 之前
###############################################################################

.mltcf24_binary_metrics <- function(y, p, thr = 0.5) {
  y <- as.integer(y)
  p <- as.numeric(p)
  pred <- as.integer(p > thr)
  auc <- tryCatch(as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE))), error = function(e) NA_real_)
  tp <- sum(pred == 1L & y == 1L)
  tn <- sum(pred == 0L & y == 0L)
  fp <- sum(pred == 1L & y == 0L)
  fn <- sum(pred == 0L & y == 1L)
  prec <- if ((tp + fp) == 0L) 0 else tp / (tp + fp)
  sen <- if ((tp + fn) == 0L) 0 else tp / (tp + fn)
  spe <- if ((tn + fp) == 0L) 0 else tn / (tn + fp)
  f1 <- if ((prec + sen) == 0) 0 else 2 * prec * sen / (prec + sen)
  acc <- mean(pred == y)
  c(AUC = auc, F1 = f1, ACC = acc, PRE = prec, SEN = sen, SPE = spe)
}

.mltcf24_topsis_alpha <- function(metric_mat) {
  ## rows=models, cols=AUC F1 ACC PRE SEN SPE；等权（文献 1/6）
  m <- as.matrix(metric_mat)
  w <- rep(1 / ncol(m), ncol(m))
  pis <- apply(m, 2L, max, na.rm = TRUE)
  nis <- apply(m, 2L, min, na.rm = TRUE)
  d_pis <- sqrt(rowSums(sweep(sweep(m, 2L, pis, `-`) ^ 2, 2L, w, `*`)))
  d_nis <- sqrt(rowSums(sweep(sweep(m, 2L, nis, `-`) ^ 2, 2L, w, `*`)))
  score <- d_nis / (d_nis + d_pis + 1e-12)
  alpha <- score / sum(score)
  stats::setNames(as.numeric(alpha), rownames(m))
}

.mltcf24_load_preds_disk <- function(root_dir, tag) {
  if (!nzchar(root_dir) || !dir.exists(root_dir)) return(NULL)
  cands <- c(
    file.path(root_dir, "Models", paste0("evalresult_", tag, ".RData")),
    file.path(root_dir, paste0("evalresult_", tag, ".RData"))
  )
  step_dirs <- list.dirs(root_dir, full.names = TRUE, recursive = FALSE)
  for (sd in step_dirs) {
    cands <- c(cands, file.path(sd, "Models", paste0("evalresult_", tag, ".RData")))
  }
  cands <- unique(cands[file.exists(cands)])
  if (!length(cands)) return(NULL)
  env <- new.env(parent = emptyenv())
  ok <- tryCatch({ load(cands[[1L]], envir = env); TRUE }, error = function(e) FALSE)
  if (!isTRUE(ok)) return(NULL)
  nms <- ls(env, all.names = TRUE)
  for (pref in c(
    paste0("final_predictions_", tag),
    "final_predictions",
    paste0("preds_", tag),
    "preds"
  )) {
    if (pref %in% nms) {
      x <- get(pref, envir = env)
      if (is.data.frame(x)) return(x)
    }
  }
  ## 任意 data.frame 名含 prediction
  for (nm in nms) {
    x <- get(nm, envir = env)
    if (is.data.frame(x) && any(grepl("predicted_value|\\.pred_", names(x)))) {
      return(x)
    }
  }
  NULL
}

#' 汇总七模型 test 概率：ml_model_probs → ml_predictions_all → 磁盘 evalresult
.mltcf24_collect_mapped_probs <- function(ctx, want, n_test) {
  mapped <- list()
  probs <- ctx$results$ml_model_probs %||% list()
  for (nm in names(probs)) {
    key <- .ml_tcf_canonical_name(nm)
    if (is.na(key) || !(key %in% want) || !is.null(mapped[[key]])) next
    p <- as.numeric(probs[[nm]])
    if (length(p) == n_test && any(is.finite(p))) mapped[[key]] <- p
  }

  allp <- ctx$results$ml_predictions_all %||% list()
  for (tag in names(allp)) {
    key <- .ml_tcf_canonical_name(tag)
    if (is.na(key) || !(key %in% want) || !is.null(mapped[[key]])) next
    p <- .ml_extract_test_ana_prob(allp[[tag]])
    if (!is.null(p) && length(p) == n_test && any(is.finite(p))) {
      mapped[[key]] <- as.numeric(p)
      ctx <- .ml_register_model_probs(ctx, key, p = p)
    }
  }

  ## 磁盘兜底：指标根 / 当前 output 父目录下各 step*/Models
  search_roots <- unique(c(
    ctx$output_dir %||% "",
    dirname(ctx$output_dir %||% "."),
    ctx$results$ml_models_db_root %||% "",
    ctx$project_root %||% ""
  ))
  search_roots <- search_roots[nzchar(search_roots) & dir.exists(search_roots)]
  tag_by_key <- c(
    DT = "dt", RF = "rf", XGB = "xgboost", LGBM = "lightgbm",
    SVM = "rsvm", NB = "naive_bayes", GBDT = "gbdt"
  )
  for (key in want) {
    if (!is.null(mapped[[key]])) next
    tag <- tag_by_key[[key]] %||% tolower(key)
    for (root in search_roots) {
      preds <- .mltcf24_load_preds_disk(root, tag)
      if (is.null(preds)) next
      p <- .ml_extract_test_ana_prob(preds)
      if (!is.null(p) && length(p) == n_test && any(is.finite(p))) {
        mapped[[key]] <- as.numeric(p)
        ctx <- .ml_register_model_probs(ctx, key, p = p)
        break
      }
    }
  }

  list(ctx = ctx, mapped = mapped)
}

block_ml_topsis_fusion <- function(ctx, ...) {
  cfg <- ctx$config$ml_topsis_fusion %||% list()
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  want <- cfg$models %||% c("DT", "RF", "XGB", "LGBM", "SVM", "NB", "GBDT")
  want <- unique(as.character(want))

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  te <- ctx$data$test
  if (is.null(te) || !nrow(te)) {
    cli::cli_alert_warning("ml_topsis_fusion: test 为空，跳过")
    return(ctx)
  }
  y <- as.integer(as.character(te[[outcome_col]]) == ana | as.character(te[[outcome_col]]) == "1")
  thr <- as.numeric(cfg$threshold %||% 0.5)[1L]
  n_test <- length(y)

  harvested <- .mltcf24_collect_mapped_probs(ctx, want, n_test)
  ctx <- harvested$ctx
  mapped <- harvested$mapped

  if (!length(mapped)) {
    cli::cli_alert_warning("ml_topsis_fusion: 未收到任何子模型 test 概率，跳过")
    return(ctx)
  }
  miss <- setdiff(want, names(mapped))
  if (length(miss)) {
    cli::cli_alert_warning(
      "ml_topsis_fusion: 缺概率子模型（将不参与融合）: {paste(miss, collapse=', ')}"
    )
  }
  ## 稳定顺序：按 want 排列已有模型
  ord <- intersect(want, names(mapped))
  mapped <- mapped[ord]

  if (length(mapped) < 2L) {
    cli::cli_alert_warning(
      "ml_topsis_fusion: 仅 {length(mapped)} 个模型有概率，TOPSIS 易退化为单模型权重"
    )
  }

  metric_rows <- lapply(names(mapped), function(m) .mltcf24_binary_metrics(y, mapped[[m]], thr))
  metric_mat <- do.call(rbind, metric_rows)
  rownames(metric_mat) <- names(mapped)

  alpha <- .mltcf24_topsis_alpha(metric_mat)
  ## 加权融合
  p <- numeric(n_test)
  for (m in names(alpha)) p <- p + alpha[[m]] * mapped[[m]]
  pred <- as.integer(p > thr)
  tcf_met <- .mltcf24_binary_metrics(y, p, thr)

  ctx$results$ml_topsis_fusion <- list(
    alpha = alpha,
    metrics_submodels = metric_mat,
    metrics_tcf = tcf_met,
    pred_prob = p,
    pred_class = pred,
    threshold = thr,
    y_test = y,
    models_used = names(alpha)
  )
  ctx$results$ml_model_probs <- ctx$results$ml_model_probs %||% list()
  ctx$results$ml_model_probs$TCF <- p

  ## 落盘
  out_dir <- file.path(ctx$output_dir %||% ".", "Models", "TCF")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(metric_mat, file.path(out_dir, "metrics_submodels.csv"))
  utils::write.csv(data.frame(model = names(alpha), alpha = as.numeric(alpha)),
                   file.path(out_dir, "topsis_alpha.csv"), row.names = FALSE)
  utils::write.csv(as.data.frame(as.list(tcf_met)), file.path(out_dir, "metrics_tcf.csv"),
                   row.names = FALSE)

  cli::cli_alert_success(
    "ml_topsis_fusion: TCF AUC={round(tcf_met[['AUC']], 3)}；子模型={paste(names(alpha), collapse=',')}；alpha=[{paste(sprintf('%s=%.3f', names(alpha), as.numeric(alpha)), collapse=', ')}]"
  )
  ctx
}

register_block("ml_topsis_fusion", block_ml_topsis_fusion, "TOPSIS 分类融合（TCF）")
