Sys.setenv(
  MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final",
  MEDICAL_BLOCKS_SKIP_WIN_R = "1"
)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
source(file.path(root, "R/pipeline_extension_guard.R"))
source(file.path(study, "config_ua_cr.R"))
pipeline_extension_guard_check(
  "ml",
  list(
    pipeline_regular_primary_ml_batch = pipeline_regular_primary_ml_batch,
    pipeline_mimic_ml_batch = pipeline_mimic_ml_batch,
    pipeline_nhanes_batch = pipeline_nhanes_batch
  ),
  study,
  root
)
cat(
  "GUARD_OK\n",
  "methods=", paste(config$ml_models$methods, collapse = ","), "\n",
  "FS=", paste(config$feature_selection$methods, collapse = ","), "\n",
  "lasso_src=", config$feature_selection_lasso$candidate_source, "\n",
  "scheme=", config$ml_batch$pub_figure_scheme, "\n",
  "has_cor=", "correlation" %in% pipeline_regular_primary_ml_batch$blocks, "\n",
  sep = ""
)
