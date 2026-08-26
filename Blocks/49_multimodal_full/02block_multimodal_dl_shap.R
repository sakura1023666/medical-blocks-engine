###############################################################################
#  multimodal_dl_shap — 深度学习 MLP + SHAP 可解释性
###############################################################################

block_multimodal_dl_shap <- function(ctx, ...) {
  bl <- ctx$config$multimodal %||% list()
  root <- ctx$config$project$root %||% getwd()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimodal_dl_shap: 无数据", call. = FALSE)

  outcome <- ctx$config$data$outcome_column %||% "Outcome"
  clinical <- intersect(bl$clinical_vars %||% c("Age", "Gender", "GCS", "SBP"), names(data))
  omics <- intersect(bl$omics_vars %||% grep("^Omics_", names(data), value = TRUE), names(data))
  preds <- unique(c(clinical, omics))
  case_lbl <- pipeline_outcome_case_label(ctx$config)

  ov <- data[[outcome]]
  if (is.character(ov) || is.factor(ov)) {
    y <- as.integer(as.character(ov) == case_lbl)
  } else {
    y <- as.integer(suppressWarnings(as.numeric(ov)))
  }
  export <- data.frame(y = y)
  for (p in preds) export[[p]] <- data[[p]]
  export <- export[stats::complete.cases(export), , drop = FALSE]
  if (nrow(export) < 40L) stop("multimodal_dl_shap: 样本不足", call. = FALSE)

  csv_in <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_dl_input.csv")
  dir.create(dirname(csv_in), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(export, csv_in, row.names = FALSE)

  if (!exists("run_literature_python", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "DL")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "multimodal_dl_shap", c("--out-dir", out, "--data-path", csv_in, "--outcome-col", "y"))

  auc_path <- file.path(out, "Table_DL_MLP_AUC.csv")
  shap_path <- file.path(out, "Table_SHAP_Feature_Importance.csv")
  ctx$results$multimodal_dl_shap <- list(
    output_dir = out,
    auc = if (file.exists(auc_path)) utils::read.csv(auc_path) else NULL,
    shap = if (file.exists(shap_path)) utils::read.csv(shap_path) else NULL
  )
  cli::cli_alert_success("深度学习 MLP + SHAP 完成")
  ctx
}

register_block(
  "multimodal_dl_shap",
  block_multimodal_dl_shap,
  "深度学习融合 + SHAP"
)
