###############################################################################
#  00block_ml_eval_common.R — ML 分类评估公共约定
#
#  Group factor 一律 levels = c(reference_group, analysis_group)，例如 Control, Case。
#  yardstick 的 sensitivity / specificity / F1 必须以 analysis_group（第二水平）为事件。
#  ROC/AUC 仍可用 .pred_<reference> + event_level="first"（与 P(Case) 等价，AUC 不变）。
###############################################################################

#' TCF / TOPSIS 规范名（Wang 2025 七模型）
.ml_tcf_canonical_name <- function(nm) {
  nm <- as.character(nm)[1L]
  if (!nzchar(nm) || is.na(nm)) return(NA_character_)
  alias <- c(
    DT = "DT", dt = "DT", ml_dt = "DT", DecisionTree = "DT",
    RF = "RF", rf = "RF", ml_rf = "RF", RandomForest = "RF",
    XGB = "XGB", xgboost = "XGB", ml_xgboost = "XGB", xgb = "XGB",
    XGBoost = "XGB",
    LGBM = "LGBM", lightgbm = "LGBM", ml_lightgbm = "LGBM", lgbm = "LGBM",
    LightGBM = "LGBM",
    SVM = "SVM", rsvm = "SVM", ml_rsvm = "SVM", svm = "SVM", RSVM = "SVM",
    NB = "NB", naive_bayes = "NB", ml_naive_bayes = "NB", NaiveBayes = "NB",
    GBDT = "GBDT", gbdt = "GBDT", ml_gbdt = "GBDT"
  )
  ## 未知名用 [[ ]] 会 subscript out of bounds；先 %in% 再取
  if (nm %in% names(alias)) return(as.character(alias[[nm]]))
  tl <- tolower(nm)
  if (!is.na(tl) && tl %in% names(alias)) return(as.character(alias[[tl]]))
  NA_character_
}

#' 从 tidymodels final_predictions 抽 test 上的 analysis 概率列
.ml_extract_test_ana_prob <- function(preds_df) {
  if (!is.data.frame(preds_df) || !nrow(preds_df)) return(NULL)
  ds <- if ("dataset" %in% names(preds_df)) as.character(preds_df$dataset) else character(nrow(preds_df))
  is_te <- tolower(trimws(ds)) %in% c(
    "validation set", "test", "test set", "validation", "external", "holdout"
  )
  if (!any(is_te)) {
    ## 无 dataset 列时：若整表行数像单折 test，整列都用
    is_te <- rep(TRUE, nrow(preds_df))
  }
  pv <- grep("_predicted_value$", names(preds_df), value = TRUE)
  if (!length(pv)) {
    ## 兜底：.pred_<ana> 类列（排除 .pred_class）
    pv <- grep("^\\.pred_", names(preds_df), value = TRUE)
    pv <- pv[!grepl("class$", pv, ignore.case = TRUE)]
  }
  if (!length(pv)) return(NULL)
  p <- as.numeric(preds_df[[pv[[1L]]]][is_te])
  if (!length(p) || !any(is.finite(p))) return(NULL)
  p
}

#' 写入 ctx$results$ml_model_probs（供 ml_topsis_fusion 七模型真融合）
.ml_register_model_probs <- function(ctx, tag, p = NULL, preds_df = NULL) {
  key <- .ml_tcf_canonical_name(tag)
  if (is.na(key)) return(ctx)
  if (is.null(p) && !is.null(preds_df)) {
    p <- .ml_extract_test_ana_prob(preds_df)
  }
  if (is.null(p)) return(ctx)
  p <- as.numeric(p)
  if (!length(p) || !any(is.finite(p))) return(ctx)
  ctx$results$ml_model_probs <- ctx$results$ml_model_probs %||% list()
  ctx$results$ml_model_probs[[key]] <- p
  ctx$results$ml_model_probs[[as.character(tag)[1L]]] <- p
  ctx
}

#' yardstick conf_mat / sens / spec 的事件水平（analysis_group = second）
.ml_yardstick_event_level <- function() {
  "second"
}

#' ROC/AUC 仍用 reference 概率列 + first（与 P(Case) 等价，勿改为 second）
.ml_yardstick_roc_event_level <- function() {
  "first"
}

#' Youden 切点（与各 ml_* 块内 roc_curve 一致）
.ml_youden_threshold_from_roc <- function(roc_tbl) {
  x <- dplyr::mutate(roc_tbl, yueden = sensitivity + specificity - 1)
  x <- dplyr::slice_max(x, yueden, n = 1, with_ties = FALSE)
  dplyr::pull(x, .threshold)
}

#' 从已保存 predtrain/predtest 重算 eval（修正 sens/spec/F1 事件水平，无需重训）
.ml_recompute_eval_from_preds <- function(predtrain, predtest, pred_ref_col, ref_g, ana_g,
                                          model_name) {
  if (!requireNamespace("yardstick", quietly = TRUE)) {
    stop("需要 yardstick 包。", call. = FALSE)
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("需要 dplyr 包。", call. = FALSE)
  }
  `%>%` <- dplyr::`%>%`
  el_roc <- .ml_yardstick_roc_event_level()
  el_cm <- .ml_yardstick_event_level()
  if (!is.factor(predtrain$Group)) {
    predtrain$Group <- factor(as.character(predtrain$Group), levels = c(ref_g, ana_g))
  }
  if (!is.factor(predtest$Group)) {
    predtest$Group <- factor(as.character(predtest$Group), levels = c(ref_g, ana_g))
  }
  grp_levels <- levels(predtrain$Group)

  roctrain <- yardstick::roc_curve(
    predtrain, Group, !!rlang::sym(pred_ref_col), event_level = el_roc
  )
  yueden <- .ml_youden_threshold_from_roc(roctrain)

  .make_classes <- function(pred_df, thr) {
    pred_df %>%
      dplyr::mutate(.pred_class = factor(
        ifelse(.data[[pred_ref_col]] >= thr, ref_g, ana_g),
        levels = grp_levels
      ))
  }

  .eval_one <- function(pred2, pred_prob, ds) {
    cm <- yardstick::conf_mat(pred2, truth = Group, estimate = .pred_class)
    sm <- summary(cm, event_level = el_cm)
    auc_row <- yardstick::roc_auc(
      pred_prob, Group, !!rlang::sym(pred_ref_col), event_level = el_roc
    )
    dplyr::bind_rows(sm, auc_row) %>% dplyr::mutate(dataset = ds)
  }

  predtrain2 <- .make_classes(predtrain, yueden)
  predtest2 <- .make_classes(predtest, yueden)
  dplyr::bind_rows(
    .eval_one(predtrain2, predtrain, "train"),
    .eval_one(predtest2, predtest, "test")
  ) %>%
    dplyr::mutate(model = model_name)
}
