###############################################################################
#  horizon_roc_youden — 在固定随访窗口内把死亡当作是否发生，算 AUC 与 Youden
#
#  register_block: "horizon_roc_youden"
#  典型流水线: survival_fixed_horizon 之后（依赖 event_h）
#
#  预测分是连续睡眠小时。主窗口与备选窗口各一行。
#  写: Tables/Table_ROC_Youden.csv；Figures/Figure_ROC_horizon.pdf
###############################################################################

if (!exists(".sd_load_common", mode = "function")) {
  .sd_load_common <- function() {
    p <- file.path(getwd(), "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R")
    if (!file.exists(p)) stop("找不到 00_sleep_dyslipid_common.R", call. = FALSE)
    source(p, local = FALSE)
  }
}

.sd_youden_row <- function(y, score, label) {
  ok <- !is.na(y) & !is.na(score)
  y <- as.integer(y[ok]); score <- as.numeric(score[ok])
  if (length(unique(y)) < 2L) {
    return(data.frame(window = label, n = length(y), events = sum(y),
                      AUC = NA_real_, cutoff = NA_real_,
                      sensitivity = NA_real_, specificity = NA_real_,
                      stringsAsFactors = FALSE))
  }
  # 方向不定（U 型），两侧都试，取 AUC 较大的一侧
  roc_obj <- NULL
  direction <- "<"
  if (requireNamespace("pROC", quietly = TRUE)) {
    a <- pROC::roc(y, score, direction = "<", quiet = TRUE)
    b <- pROC::roc(y, score, direction = ">", quiet = TRUE)
    roc_obj <- if (as.numeric(pROC::auc(a)) >= as.numeric(pROC::auc(b))) a else b
    direction <- roc_obj$direction
    aucv <- as.numeric(pROC::auc(roc_obj))
    thr <- pROC::coords(roc_obj, "best", best.method = "youden", ret = c("threshold", "sensitivity", "specificity"))
    data.frame(
      window = label, n = length(y), events = sum(y),
      AUC = round(aucv, 3),
      cutoff = round(thr$threshold[1], 3),
      sensitivity = round(thr$sensitivity[1], 3),
      specificity = round(thr$specificity[1], 3),
      direction = direction,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(window = label, n = length(y), events = sum(y),
               AUC = NA_real_, cutoff = NA_real_, sensitivity = NA_real_, specificity = NA_real_,
               direction = "pROC_missing", stringsAsFactors = FALSE)
  }
}

block_horizon_roc_youden <- function(ctx, ...) {
  .sd_load_common()
  if (!.sd_ready(ctx)) {
    cli::cli_alert_warning("ROC 跳过：还没有固定窗口结局")
    return(ctx)
  }
  d <- .sd_dat(ctx)
  if (!"event_h" %in% names(d)) {
    cli::cli_alert_warning("ROC 跳过：缺少 event_h，请先跑 survival_fixed_horizon")
    return(ctx)
  }
  rows <- list(.sd_youden_row(d$event_h, d$Sleep_hours, "primary_horizon"))
  if ("event_alt" %in% names(d)) {
    rows[[2]] <- .sd_youden_row(d$event_alt, d$Sleep_hours, "alt_horizon")
  }
  tab <- do.call(rbind, rows)
  .sd_write_csv(tab, file.path(.sd_dir(ctx, "tables"), "Table_ROC_Youden.csv"))
  if (requireNamespace("pROC", quietly = TRUE) && length(unique(d$event_h)) == 2L) {
    roc_obj <- pROC::roc(d$event_h, d$Sleep_hours, direction = tab$direction[1], quiet = TRUE)
    pdf(file.path(.sd_dir(ctx, "figures"), "Figure_ROC_horizon.pdf"), width = 5.2, height = 5)
    plot(roc_obj, main = sprintf("Death within horizon  AUC %.3f", tab$AUC[1]))
    dev.off()
  }
  ctx$results$horizon_roc_youden <- tab
  cli::cli_alert_success("固定窗口 ROC / Youden 已写出")
  ctx
}

register_block("horizon_roc_youden", block_horizon_roc_youden,
               "预后2.0 固定窗口 AUC 与 Youden")
