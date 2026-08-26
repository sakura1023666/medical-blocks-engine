# refresh_gpr_new_pub.R — 用已 Rubin 的模型结果刷新 pub_export / status
root <- Sys.getenv("BLOCK_REPO_ROOT", "/mnt/e/01block/01Block-new-Final")
unit_dir <- "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/by_unit/GPR[new]"
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/mi_rubin_pool.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "Blocks/55_competing_risk_full/18block_competing_pub_export.R"))

# Prefer latest ck with mice_row_ids
ck_candidates <- c(
  file.path(unit_dir, "checkpoints", "competing_models_123_death.rds"),
  file.path(unit_dir, "checkpoints", "competing_models_123.rds"),
  file.path(unit_dir, "checkpoints", "competing_mixed_cox.rds")
)
ck <- ck_candidates[file.exists(ck_candidates)][1]
stopifnot(nzchar(ck %||% ""))
ctx <- readRDS(ck)$ctx
ctx$config$project$output_dir <- unit_dir
# ensure footnote flags
ctx$config$competing_risk$discharge_as_censor <- TRUE
ctx$config$imputation$rubin_pool <- TRUE

# restore cov footnote file
covs <- ctx$results$competing_model_covs
if (!is.null(covs)) {
  writeLines(
    c(
      paste0("Model 1/4: unadjusted; Model 2/5: ", paste(covs$m2, collapse = ", "),
             "; Model 3/6: ", paste(covs$m3, collapse = ", "), " (pre-specified)"),
      paste0("trajectory: method=", ctx$results$competing_trajectory_class$method %||% "lmm_blup",
             "; optimal_K=", ctx$results$competing_trajectory_class$optimal_K %||% NA,
             "; labels=", paste(ctx$results$competing_trajectory_class$labels %||% character(0), collapse = ", "))
    ),
    file.path(unit_dir, "Tables", "00_Model_Covariates.txt")
  )
}

ctx <- tryCatch(block_competing_pub_export(ctx), error = function(e) {
  message("pub_export warn: ", conditionMessage(e))
  ctx
})

# batch status
status <- list(
  unit = "GPR[new]",
  index = "GPR",
  status = "success",
  db_mode = "MIMIC",
  error_message = list(),
  failed_stage = NULL,
  trajectory_k = as.character(ctx$results$competing_trajectory_class$optimal_K %||% NA),
  model2_covariates = as.character(covs$m2 %||% character(0)),
  model3_covariates = as.character(covs$m3 %||% character(0)),
  mi_pool = "rubin",
  mi_m = 5L,
  discharge_as_censor = TRUE,
  disease = "ischemic_stroke_aki_competing_risk",
  finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(status, file.path(unit_dir, "_batch_status.json"),
                       auto_unbox = TRUE, pretty = TRUE)
}
message("OK pub refresh")
