# Resume IPW main from univariate checkpoint (skip MICE)
root <- "E:/01block/01Block-new-Final"
setwd(root)
source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
cfg_path <- "G:/02block_result/11_ischemic stroke/Medication_regimen_model_42118193/config_ipw_diabetes_stroke_batch.R"
source(cfg_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

unit <- "main"
output_unit <- study_batch_unit_output_dir(config, unit)
unit_ck <- file.path(output_unit, "checkpoints")
config$project$output_dir <- output_unit
config$study_batch$active_unit <- unit
config$analysis_exclusion$allow_no_index <- TRUE
config$analysis_exclusion$index_var <- NULL
config$incidence <- list()

initial_ctx <- study_batch_load_checkpoint_ctx(unit_ck, "stepp_prognosis")
blocks <- c(
  "cox_binary",
  "ipw_overlap_weights",
  "ipw_surv_calibration_roc",
  "ipw_literature_targets",
  "ipw_pub_export"
)
pl <- list(
  name = "ipw_diabetes_resume",
  blocks = blocks,
  checkpoint = list(enable = TRUE, dir = unit_ck)
)
final_ctx <- run_pipeline(
  root, config = config, pipeline = pl,
  run_opts = list(initial_ctx = initial_ctx, only = blocks)
)
study_batch_write_status(output_unit, list(
  unit = unit, index = "composite_risk", status = "success",
  db_mode = "MIMIC", error_message = NULL, failed_stage = NA_character_,
  n_diabetes = NA_integer_, n_event = NA_integer_,
  univariate_covariates = as.character(final_ctx$results$Model2Factors %||% character(0)),
  lasso_covariates = character(0), final_covariates = character(0),
  elapsed_sec = NA_real_, disease = config$project$disease %||% "", protocol = ""
))
# rename to success if dispatcher expects it
succ <- file.path(dirname(output_unit), paste0("\u3010success\u3011", unit))
if (!identical(normalizePath(output_unit, winslash = "/", mustWork = FALSE),
               normalizePath(succ, winslash = "/", mustWork = FALSE))) {
  if (dir.exists(succ)) unlink(succ, recursive = TRUE)
  file.rename(output_unit, succ)
}
cli::cli_alert_success("resume main OK -> {succ}")
