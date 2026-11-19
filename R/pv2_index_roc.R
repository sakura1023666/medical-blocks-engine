###############################################################################
#  pv2_index_roc — 预后 v2 Table S4 / Figure 5：单指标连续值 ROC（无协变量）
#
#  COPD ALBI 2026-11 教训：交付曾写成 Cox LP（index + Age/Sodium/GCS），
#  与参考文献单指标 ROC 口径分裂。本模块是唯一引擎入口；课题 rebuild /
#  remirror 禁止再手写 pROC + coxph LP。
#
#  铁律：主文 S4 / Fig5 = continuous index alone, unadjusted。
#  Cox LP / 多协变量 ROC 仅可作敏感性且不得占用 S4 / Figure 5 编号。
###############################################################################

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

#' Fit unadjusted continuous-index ROC (Youden + DeLong CI)
#'
#' @param event integer/logical 0/1 outcome
#' @param score numeric continuous index
#' @param index_lab character label for Index column / curve legend
#' @param direction pROC direction; default "auto"
#' @param min_n minimum complete rows
#' @return list(table_row, curve_df, auc, ci, roc) or NULL
pv2_index_roc_fit <- function(
    event,
    score,
    index_lab,
    direction = "auto",
    min_n = 20L
) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    warning("pv2_index_roc_fit: pROC not installed")
    return(NULL)
  }
  index_lab <- as.character(index_lab %||% "Index")[1L]
  event <- as.integer(event)
  score <- as.numeric(score)
  ok <- is.finite(score) & !is.na(event)
  if (sum(ok) < as.integer(min_n) || length(unique(event[ok])) < 2L) return(NULL)

  roc <- tryCatch(
    pROC::roc(event[ok], score[ok], quiet = TRUE, direction = direction),
    error = function(e) NULL
  )
  if (is.null(roc)) return(NULL)

  auc <- as.numeric(pROC::auc(roc))
  ci <- tryCatch(as.numeric(pROC::ci.auc(roc)), error = function(e) c(NA_real_, NA_real_, NA_real_))
  best <- tryCatch(
    pROC::coords(
      roc, "best", best.method = "youden",
      ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE
    ),
    error = function(e) NULL
  )
  cd <- tryCatch(
    pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE),
    error = function(e) NULL
  )

  table_row <- data.frame(
    Index = paste0(index_lab, " (continuous, unadjusted)"),
    AUC = sprintf("%.3f", auc),
    `AUC 95% CI` = sprintf("%.3f\u2013%.3f", ci[1], ci[3]),
    `Youden cutoff` = if (!is.null(best)) sprintf("%.3f", best$threshold[1]) else "",
    Sensitivity = if (!is.null(best)) sprintf("%.3f", best$sensitivity[1]) else "",
    Specificity = if (!is.null(best)) sprintf("%.3f", best$specificity[1]) else "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  curve_lab <- sprintf("%s (AUC %.3f)", index_lab, auc)
  curve_df <- if (!is.null(cd)) {
    data.frame(
      fpr = 1 - cd$specificity,
      tpr = cd$sensitivity,
      curve = curve_lab,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(fpr = numeric(0), tpr = numeric(0), curve = character(0),
               stringsAsFactors = FALSE)
  }

  list(
    table_row = table_row,
    curve_df = curve_df,
    auc = auc,
    ci = ci,
    roc = roc,
    n = sum(ok),
    index_lab = index_lab
  )
}

#' Dual-DB (or multi-panel) curve rows; legend uses database name + AUC
pv2_index_roc_curve_by_db <- function(dbs, index_col, event_col = "fustatus", ...) {
  out <- list()
  for (nm in names(dbs)) {
    d <- as.data.frame(dbs[[nm]])
    if (!index_col %in% names(d) || !event_col %in% names(d)) next
    fit <- pv2_index_roc_fit(
      event = d[[event_col]],
      score = d[[index_col]],
      index_lab = nm,
      ...
    )
    if (is.null(fit)) next
    out[[nm]] <- fit$curve_df
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

#' Standard S4 / Fig5 footnotes (English, delivery)
pv2_index_roc_footnotes <- function(index_lab, endpoint) {
  index_lab <- as.character(index_lab %||% "index")[1L]
  endpoint <- as.character(endpoint %||% "all-cause mortality")[1L]
  c(
    paste0(
      "Discrimination for ", endpoint, " using continuous ", index_lab,
      " alone (unadjusted; same specification as Figure 5)."
    ),
    "Youden index on the ROC of the continuous index; AUC with DeLong 95% CI."
  )
}

#' image_information body lines for Figure 5
pv2_index_roc_image_md <- function(stem, index_lab, endpoint, dual_db = TRUE) {
  index_lab <- as.character(index_lab %||% "index")[1L]
  endpoint <- as.character(endpoint %||% "all-cause mortality")[1L]
  panel <- if (isTRUE(dual_db)) {
    paste0(
      "单画面双曲线（MIMIC / eICU）；预测变量为连续 ", index_lab,
      "，不加任何协变量；与 Table S4 同源。"
    )
  } else {
    paste0(
      "预测变量为连续 ", index_lab, "，不加任何协变量；与 Table S4 同源。"
    )
  }
  c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    panel,
    "",
    "## 分析上下文",
    paste0("- 暴露: ", index_lab, " (continuous, unadjusted)"),
    paste0("- 结局: ", endpoint),
    if (isTRUE(dual_db)) "- 数据库: MIMIC + eICU" else "- 数据库: 见课题"
  )
}

#' Reject delivery blobs that still advertise Cox-LP / covariate ROC for S4/Fig5
#'
#' @param text character blob (xlsx cells / md / PDF text)
#' @return character(0) if OK; otherwise failure messages
pv2_index_roc_audit_delivery_text <- function(text) {
  text <- as.character(text %||% "")
  if (!length(text) || !nzchar(paste(text, collapse = ""))) return(character(0))
  blob <- paste(text, collapse = "\n")
  fails <- character(0)
  if (grepl("Cox\\s*LP|Cox linear predictor|linear predictor of", blob, ignore.case = TRUE)) {
    fails <- c(fails, "S4/Fig5 text still describes Cox LP / linear predictor (must be continuous index unadjusted)")
  }
  # Age + clinical covs listed as ROC predictors
  if (grepl("\\+\\s*Age\\b", blob) && grepl("ROC|Discriminat|Youden|AUC", blob, ignore.case = TRUE) &&
      grepl("Sodium|GCS|CHARLSON|SOFA|APSIII", blob, ignore.case = TRUE)) {
    fails <- c(fails, "S4/Fig5 text lists covariates alongside Age for ROC (forbidden for delivery Table S4 / Figure 5)")
  }
  # positive signal preferred when table present
  if (grepl("Discriminat|Predictive performance|Youden", blob, ignore.case = TRUE) &&
      !grepl("unadjusted|continuous", blob, ignore.case = TRUE) &&
      grepl("AUC", blob, ignore.case = TRUE)) {
    fails <- c(fails, "S4/Fig5 discrimination text missing 'continuous'/'unadjusted' marker")
  }
  unique(fails)
}
