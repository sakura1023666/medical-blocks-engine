###############################################################################
#  00block_ml_eval_common.R — ML 分类评估公共约定
#
#  Group factor 一律 levels = c(reference_group, analysis_group)，例如 Control, Case。
#  yardstick 的 sensitivity / specificity / F1 必须以 analysis_group（第二水平）为事件。
#  ROC/AUC 仍可用 .pred_<reference> + event_level="first"（与 P(Case) 等价，AUC 不变）。
###############################################################################

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
