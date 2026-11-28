###############################################################################
#  bayesian_roc_calibration — BLSA 训练 → InCHIANTI/NHANES 外验 ROC + 校准
###############################################################################

block_bayesian_roc_calibration <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  literature_ensure_packages("bayesian")

  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !"Cohort" %in% names(data))
    stop("bayesian_roc_calibration: 需要 Cohort 列", call. = FALSE)

  train <- bl$train_cohort %||% "BLSA"
  val_cohorts <- bl$validate_cohorts %||% c("InCHIANTI", "NHANES")
  pred_col <- bl$roc_predictor %||% "Body_Clock"
  outcome <- bl$roc_outcome %||% "Mortality"
  if (!pred_col %in% names(data) || !outcome %in% names(data))
    stop("bayesian_roc_calibration: 缺少预测或结局列", call. = FALSE)

  train_df <- data[data$Cohort == train, , drop = FALSE]
  thr <- stats::quantile(train_df[[pred_col]], 0.75, na.rm = TRUE)

  rows <- list()
  for (coh in val_cohorts) {
    sub <- data[data$Cohort == coh, , drop = FALSE]
    if (nrow(sub) < 20L) next
    y <- as.integer(as.numeric(sub[[outcome]]) >= 1)
    x <- as.numeric(sub[[pred_col]])
    roc_obj <- tryCatch(pROC::roc(y, x, quiet = TRUE), error = function(e) NULL)
    auc <- if (!is.null(roc_obj)) as.numeric(pROC::auc(roc_obj)) else NA_real_
    pred_bin <- as.integer(x >= thr)
    cal <- data.frame(obs = y, pred = pred_bin)
    cal_tab <- stats::aggregate(obs ~ pred, data = cal, FUN = mean)
    rows[[length(rows) + 1L]] <- data.frame(
      cohort = coh, predictor = pred_col, outcome = outcome,
      AUC = auc, n = nrow(sub), threshold = thr,
      stringsAsFactors = FALSE
    )
    utils::write.csv(
      cal_tab,
      file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                paste0("Table_Calibration_", coh, ".csv")),
      row.names = FALSE
    )
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "insufficient data")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_ROC_External_Validation.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(tab) && any(!is.na(tab$AUC))) {
    out_fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(tab, ggplot2::aes(x = cohort, y = AUC, fill = cohort)) +
      ggplot2::geom_col() + ggplot2::ylim(0, 1) +
      ggplot2::labs(title = paste("ROC AUC:", pred_col, "->", outcome)) +
      ggplot2::theme_bw()
    ggplot2::ggsave(file.path(out_fig, "Figure_ROC_AUC_External.pdf"), p, width = 7, height = 5)
  }

  ctx$results$bayesian_roc_calibration <- tab
  cli::cli_alert_success("ROC/校准外验完成（train={train}）")
  ctx
}

register_block("bayesian_roc_calibration", block_bayesian_roc_calibration, "ROC 与校准外验")
