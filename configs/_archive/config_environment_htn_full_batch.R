###############################################################################
#  config_environment_htn_full_batch.R — 高血压 × 环境暴露全量
#
#  数据: Data/D04_环境_删除尼古丁空缺值(2).RData（dabiao4，临床+环境预合并）
#
#  产出: G:/02block_result/05_DKD/environment_37419158/
#       (网络盘 \\192.168.68.133\02block_result\05_DKD\environment_37419158)
#
#  用法:
#    Rscript run/environment/run_environment_dkd_batch.R \
#      --config configs/config_environment_htn_full_batch.R --workers auto --no-skip
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()
source(file.path(.cfg_root, "configs/config_environment_dkd_batch.R"), local = FALSE)

.resolve_batch_path <- function(p) {
  p <- as.character(p)[1L]
  if (grepl("^\\\\", p)) {
    # UNC: \\192.168.68.133\02block_result\... → G:/02block_result/...
    p <- sub("^\\\\\\\\[^\\\\]+\\\\", "G:/", gsub("\\\\", "/", p))
  }
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || dir.exists(dirname(wsl))) return(wsl)
  }
  p
}

.batch_project_root <- .resolve_batch_path("G:/02block_result/05_DKD/environment_37419158")
.batch_data_root      <- file.path(.batch_project_root, "Data")
.batch_ck_root        <- file.path(.batch_project_root, "checkpoints")

config$data$rawdata_path            <- file.path(.batch_data_root, "nhanes/D03_EnvResultData.RData")
config$data$rawdata_obj             <- "EnvResult"
config$data$outcome_column          <- "Group"
config$data$outcome_source_column   <- "Hypertension"

config$project$analysis_group  <- "Hypertension"
config$project$reference_group <- "No Hypertension"
config$project$disease         <- "Hypertension"
config$project$disease_cn      <- "高血压"
config$glm_environment_quartile$analysis_group   <- "Hypertension"
config$glm_environment_quartile$reference_group    <- "No Hypertension"

config$environment_prepare$enable                    <- TRUE
config$environment_prepare$mode                        <- "premerged_rdata"
config$environment_prepare$data_dir                    <- file.path(.cfg_root, "Data")
config$environment_prepare$premerged_file              <- "D04_环境_删除尼古丁空缺值(2).RData"
config$environment_prepare$premerged_obj               <- "dabiao4"
config$environment_prepare$env_voc_pattern             <- "^(URX|LBX)"
config$environment_prepare$voc_exclude_fixed           <- c("URXUCR")
config$environment_prepare$nhanes_dir                  <- file.path(.cfg_root, "Data/nhanes")
config$environment_prepare$merged_output_dir           <- file.path(.batch_data_root, "nhanes")
config$environment_prepare$save_merged                 <- TRUE
config$environment_prepare$env_weight_file             <- "D01_环境_权重_总砷 (1)(1).RData"
config$environment_prepare$env_weight_obj              <- "df"
config$environment_prepare$env_weight_col              <- "WTSA2YR"
config$environment_prepare$env_weight_fallback_wtmec   <- FALSE
config$environment_prepare$require_env_weight          <- TRUE
config$environment_prepare$merged_weight_col           <- "new_Weight"
config$environment_prepare$outcome_source_column       <- "Hypertension"
config$environment_prepare$kidney_disease_voc_workflow <- FALSE
config$environment_prepare$adjust_voc_urinary_creatinine <- TRUE
config$environment_prepare$restore_all_voc_to_ugl        <- FALSE
config$environment_prepare$urinary_creatinine_file       <- "尿肌酐_nhanes.csv"
config$environment_prepare$urinary_creatinine_id_col     <- "SEQN"
config$environment_prepare$urinary_creatinine_col        <- "URXUCR"
config$environment_prepare$urinary_creatinine_out_col    <- "Urinary_Creatinine"
config$environment_prepare$urinary_creatinine_trim_enable  <- TRUE
config$environment_prepare$urinary_creatinine_trim_lower_pct <- 0.01
config$environment_prepare$urinary_creatinine_trim_upper_pct <- 0.99
config$environment_prepare$urinary_creatinine_floor_pct    <- 0.05
config$environment_prepare$voc_adjusted_winsor_enable      <- TRUE
config$environment_prepare$voc_adjusted_winsor_log_scale   <- TRUE
config$environment_prepare$voc_adjusted_winsor_lower_pct   <- 0.01
config$environment_prepare$voc_adjusted_winsor_upper_pct   <- 0.99
config$environment_voc_log_transform$apply_log         <- TRUE
config$environment_voc_log_transform$force_all_vocs      <- TRUE
config$environment_lod$legacy_stats_file                 <- file.path(.cfg_root, "Data/stats(1).RData")
config$environment_lod$legacy_stats_obj                  <- "stats"

config$nhanes$survey_weight   <- "new_Weight"
config$nhanes$auto_new_weight <- FALSE

config$project$name            <- "Hypertension_Environment_Full"
config$project$disease_code    <- "05"
config$project$literature_pmid <- "37419158"
config$project$output_dir      <- .batch_project_root
config$project$root            <- .cfg_root
config$project$study_type      <- "environment"

config$environment_batch$output_base    <- .batch_project_root
config$environment_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared", "main")
config$environment_batch$project_root   <- .cfg_root

config$data_clean$missing_threshold     <- 0.40
config$data_clean$env_missing_threshold <- 0.40
config$data_clean$never_drop_columns    <- c(
  "Group", "SEQN", "ID", "new_Weight", "SDMVPSU", "SDMVSTRA",
  "Source_File", "WTMEC2YR", "WTSA2YR"
)
config$imputation$missing_col_threshold   <- 0.40
config$imputation$force_keep_weight_cols  <- FALSE
config$environment$voc_col_pattern      <- "^(URX|LBX)"
config$environment$display_label_map <- c(AMC = "AMCC", URXAMC = "AMCC")

config$imputation$exclude_from_mice_cols <- c(
  "Source_File", "SDDSRVYR", "WTSA2YR", "WTSAF2YR", "WTSAF4YR",
  "WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTINT4YR",
  "SDMVPSU", "SDMVSTRA", "new_Weight"
)
config$remove_outliers$cols                 <- NULL
config$remove_outliers$enable               <- FALSE

config$bkmr_fit$auto_iter <- FALSE
config$bkmr_fit$iter      <- 100L
config$bkmr_fit$nchains   <- 2L
config$bkmr_fit$covariates <- c(
  "Race", "BMI", "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

config$lasso_environment$univariate_enable     <- FALSE
config$lasso_environment$require_clinical_gate <- TRUE
config$lasso_environment$freq_cutoff_method    <- "auto_floor100"
config$lasso_environment$min_select_vocs       <- 5L
config$lasso_environment$auto_lambda_tighten  <- TRUE
config$lasso_environment$auto_lambda_min_exclude <- 1L

config$wqs_environment$b <- 200L
config$wqs_environment$skip_if_vocs_lte <- 2L
config$wqs_environment$strict_glm_vocs <- TRUE
config$wqs_environment$auto_select_vocs <- FALSE
config$wqs_environment$min_select_vocs <- 2L
config$wqs_environment$covariates <- c(
  "Race", "BMI", "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

config$glm_environment_quartile$match_lasso_vocs          <- TRUE
config$glm_environment_quartile$require_lasso_passed      <- TRUE
config$glm_environment_quartile$use_wald_ci               <- TRUE
config$glm_environment_quartile$use_final_covariates      <- TRUE
config$glm_environment_quartile$covariate_search          <- TRUE
config$glm_environment_quartile$covariate_search_mode     <- "fast"
config$glm_environment_quartile$model2_factors <- c(
  "Age", "Race", "PIR", "Education", "Smoking", "BMI",
  "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

config$environment_batch$include_vocs_in_clinical_screen  <- TRUE
config$environment_batch$skip_clinical_multivariate     <- TRUE
config$environment_batch$exclude_vocs_from_clinical_vif   <- FALSE

config$environment_voc_clinical_gate$enable                  <- TRUE
config$environment_voc_clinical_gate$require_table1          <- FALSE
config$environment_voc_clinical_gate$min_pass_vocs           <- 2L
config$environment_voc_clinical_gate$voc_gate_mode           <- "univariate_vif"
config$environment_voc_clinical_gate$voc_univariate_source <- "tb1"
config$environment_voc_clinical_gate$voc_univariate_p_cutoff <- 0.05
config$environment_voc_clinical_gate$require_pass_for_lasso  <- TRUE
config$environment_voc_clinical_gate$voc_vif_threshold       <- 4
config$environment_voc_clinical_gate$voc_cor_enable          <- TRUE
config$environment_voc_clinical_gate$voc_cor_threshold       <- 0.80

config$environment_subgroup_search$enable <- TRUE
config$environment_subgroup_search$use_parallel <- FALSE
config$environment_subgroup_search$custom_filters <- list(
  list(id = "age_ge_18", label = "Age >= 18", expr = "Age >= 18"),
  list(id = "age_ge_45", label = "Age >= 45", expr = "Age >= 45"),
  list(id = "age_lt_45", label = "Age < 45", expr = "Age < 45")
)
config$environment_voc_extreme_trim$enable <- TRUE
config$environment_voc_recovery$min_glm_vocs <- 3L

config$environment_target$enable     <- FALSE

config$feishu$literature_default <- "高血压 × 环境暴露（D04 dabiao4, NHANES）"
config$feishu$project_id         <- "05_DKD_environment_37419158"
config$feishu$protocol_label     <- "05_DKD_environment_37419158"

config$environment_batch$subgroup_strata[[4]]$stratify_col  <- "Smoking"
config$environment_batch$subgroup_strata[[4]]$strata_levels <- c("nonSmoked", "Smoked")
config$environment_batch$covariate_fallback$enable <- TRUE

pipeline_shared$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
pipeline_tail$checkpoint$dir   <- file.path(.batch_ck_root, "_shared", "main")
pipeline$checkpoint$dir        <- file.path(.batch_ck_root, "full_run")
