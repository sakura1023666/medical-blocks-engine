###############################################################################
#  config_environment_dkd_full_batch.R — DKD × 环境 VOC 正式全量（D02 加权数据, n≈773）
#
#  产出根目录:
#    Windows: G:/02block_result/05_DKD/environment_37419158/
#
#  数据: Step00 local_bundle — Data/D01_RawCleanData(1) + D01_EnvCleanData(1) 行对齐合并
#
#  用法:
#    Rscript run/environment/run_environment_dkd_batch.R --shared-only --config "G:/02block_result/05_DKD/environment_37419158/Data/config_environment_dkd_full_batch.R"
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()
source(file.path(.cfg_root, "configs/config_environment_dkd_batch.R"), local = FALSE)

.resolve_batch_path <- function(p) {
  p <- as.character(p)[1L]
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || dir.exists(dirname(wsl))) return(wsl)
  }
  p
}

.batch_project_root <- .resolve_batch_path("G:/02block_result/05_DKD/environment_37419158")
.batch_data_root      <- file.path(.batch_project_root, "Data")
.batch_ck_root        <- file.path(.batch_project_root, "checkpoints")

config$data$rawdata_path <- file.path(.batch_data_root, "nhanes/D03_EnvResultData.RData")
config$data$rawdata_obj  <- "EnvResult"

config$project$analysis_group  <- "PD"
config$project$reference_group <- "Never PD"
config$project$disease         <- "PD"
config$glm_environment_quartile$analysis_group  <- "PD"
config$glm_environment_quartile$reference_group <- "Never PD"

config$environment_prepare$enable                <- TRUE
config$environment_prepare$mode                  <- "local_bundle"
config$environment_prepare$data_dir              <- file.path(.cfg_root, "Data")
config$environment_prepare$clinical_file         <- "D01_RawCleanData(1).RData"
config$environment_prepare$clinical_obj          <- "data"
config$environment_prepare$environment_file      <- "D01_EnvCleanData(1).RData"
config$environment_prepare$environment_obj       <- "environment_data"
config$environment_prepare$merged_output_dir     <- file.path(.batch_data_root, "nhanes")
config$environment_prepare$nhanes_dir            <- file.path(.cfg_root, "Data/nhanes")
config$environment_prepare$save_merged           <- TRUE
config$environment_prepare$merge_baseline_survey <- TRUE
config$environment_prepare$cohort_filter_file    <- NULL
config$environment_prepare$cohort_target_n       <- NULL
config$environment_prepare$env_weight_file       <- "D01_环境_权重_总砷 (1)(1).RData"
config$environment_prepare$env_weight_obj        <- "df"
config$environment_prepare$env_weight_col        <- "WTSA2YR"
config$environment_prepare$env_weight_fallback_wtmec <- FALSE
config$environment_prepare$require_env_weight    <- TRUE
config$environment_prepare$merged_weight_col     <- "new_Weight"
config$environment_prepare$adjust_voc_urinary_creatinine <- TRUE
config$environment_prepare$kidney_disease_voc_workflow     <- TRUE
config$environment_prepare$restore_all_voc_to_ugl          <- TRUE
config$environment_voc_log_transform$apply_log             <- TRUE
config$environment_voc_log_transform$force_all_vocs          <- TRUE
config$environment_prepare$urinary_creatinine_file       <- "尿肌酐_nhanes.csv"
config$environment_prepare$urinary_creatinine_id_col     <- "SEQN"
config$environment_prepare$urinary_creatinine_col        <- "URXUCR"
config$environment_prepare$urinary_creatinine_out_col    <- "Urinary_Creatinine"
config$environment_lod$legacy_stats_file         <- file.path(.cfg_root, "Data/stats(1).RData")
config$environment_lod$legacy_stats_obj          <- "stats"

config$nhanes$survey_weight    <- "new_Weight"
config$nhanes$auto_new_weight  <- FALSE

config$project$name              <- "DKD_Environment_VOC_Full"
config$project$disease_code      <- "05"
config$project$disease           <- "DKD"
config$project$literature_pmid   <- "37419158"
config$project$output_dir        <- .batch_project_root
config$project$root              <- .cfg_root
config$project$study_type        <- "environment"

config$environment_batch$output_base    <- .batch_project_root
config$environment_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared", "main")
config$environment_batch$project_root     <- .cfg_root

# 权重: WTSA2YR / 周期数 → new_Weight；无有效 WTSA2YR 者剔除（不回退 WTMEC2YR）

.voc_rdata <- file.path(.batch_data_root, "nhanes/voc_columns.RData")
if (file.exists(.voc_rdata)) {
  .voc_env <- new.env()
  load(.voc_rdata, envir = .voc_env)
  if (exists("voc_columns", envir = .voc_env, inherits = FALSE)) {
    .voc_cols_loaded <- get("voc_columns", envir = .voc_env)
  } else if (exists("voc_cols", envir = .voc_env, inherits = FALSE)) {
    .voc_cols_loaded <- get("voc_cols", envir = .voc_env)
  }
  if (exists(".voc_cols_loaded")) {
    config$environment$voc_columns <- .voc_cols_loaded
    config$incidence$index_exclude_vars <- .voc_cols_loaded
    config$nhanes$cutoff_index_var <- .voc_cols_loaded[1L]
  }
}

config$data_clean$missing_threshold <- 0.4
# 与 data_clean 对齐：否则 ~31% 缺失的砷代谢物会在插补前再次被 20% 阈值剔除
config$imputation$missing_col_threshold <- 0.4

config$remove_outliers$cols   <- NULL
config$remove_outliers$enable <- FALSE

# BKMR：固定 iter=100，关闭自动选 iter（不强制 Overall 单调上升）
config$bkmr_fit$auto_iter <- FALSE
config$bkmr_fit$iter      <- 100L
config$bkmr_fit$nchains   <- 2L
config$bkmr_fit$covariates <- c(
  "Race", "BMI", "Albumin_Urine", "Creatinine_refrigerated_serum",
  "Glucose", "HbA1c", "Uric_Acid"
)
config$bkmr_analysis$qs_overall <- seq(0.4, 0.6, by = 0.02)

config$lasso_environment$univariate_enable   <- FALSE
config$lasso_environment$require_clinical_gate <- TRUE
config$lasso_environment$freq_cutoff_method  <- "auto_floor100"
config$lasso_environment$freq_cutoff_frac    <- NULL
config$lasso_environment$min_select_vocs     <- 5L

config$wqs_environment$b <- 200L
config$wqs_environment$skip_if_vocs_lte <- 2L
config$wqs_environment$strict_glm_vocs <- TRUE
config$wqs_environment$auto_select_vocs <- FALSE
config$wqs_environment$min_select_vocs <- 2L
config$wqs_environment$auto_select$quick_b <- 100L
config$wqs_environment$auto_select$max_trials <- 10L
config$wqs_environment$auto_select$bkmr_quick_iter <- 100L

config$wqs_environment$covariates <- c(
  "Race", "BMI", "Albumin_Urine", "Creatinine_refrigerated_serum",
  "Glucose", "HbA1c", "Uric_Acid"
)

config$glm_environment_quartile$match_lasso_vocs                 <- TRUE
config$glm_environment_quartile$require_lasso_passed             <- TRUE
config$glm_environment_quartile$use_final_covariates             <- TRUE
config$glm_environment_quartile$covariate_search                 <- TRUE
config$glm_environment_quartile$covariate_search_mode            <- "fast"
config$glm_environment_quartile$per_voc_covariates               <- TRUE
config$glm_environment_quartile$shared_exposure_scheme           <- TRUE
config$glm_environment_quartile$exposure_scheme                  <- NULL
config$glm_environment_quartile$require_crude_then_m1_m2         <- TRUE
config$glm_environment_quartile$covariate_sources                <- c("vif_uni", "table1")
config$glm_environment_quartile$exposure_schemes_primary         <- c("quartile")
config$glm_environment_quartile$exposure_schemes_fallback        <- c("quintile", "tertile", "binary")
config$glm_environment_quartile$table1_clinical_prefilter_n      <- 15L
config$glm_environment_quartile$table1_prefilter_p               <- 0.20
config$glm_environment_quartile$clinical_forward_max             <- 8L
config$glm_environment_quartile$demo_search_max_size             <- 3L
config$glm_environment_quartile$demo_random_attempts             <- 50L
config$glm_environment_quartile$full_screen_top_n                <- 5L
config$glm_environment_quartile$require_quartile_any_significant <- TRUE
config$glm_environment_quartile$require_trend_significant        <- TRUE
config$glm_environment_quartile$enforce_min_after_screen         <- FALSE
config$glm_environment_quartile$clinical_search_table1           <- TRUE
config$glm_environment_quartile$clinical_search_if_pool_gt       <- 5L
config$glm_environment_quartile$clinical_search_max_subset       <- 10L
config$glm_environment_quartile$model2_factors <- c(
  "Age", "Race", "PIR", "Education", "Smoking", "BMI",
  "Albumin_Urine", "Creatinine_refrigerated_serum", "Urine_Creatinine",
  "Glucose", "HbA1c", "Uric_Acid"
)

config$environment_batch$include_vocs_in_clinical_screen <- TRUE

config$environment_batch$skip_clinical_multivariate <- TRUE

config$environment_voc_clinical_gate$enable <- TRUE
config$environment_voc_clinical_gate$require_table1 <- FALSE
config$environment_voc_clinical_gate$multivariate_min_for_full_gate <- 5L
config$environment_voc_clinical_gate$min_pass_vocs <- 2L
config$bkmr_fit$min_select_vocs <- 3L

# 主流程 GLM<3 时：先亚组 recovery，再极端值剔除
config$environment_subgroup_search$enable <- TRUE
config$environment_subgroup_search$use_parallel <- FALSE
config$environment_subgroup_search$force_filter_id <- NULL
config$environment_subgroup_search$custom_filters <- list(
  list(id = "age_ge_18", label = "Age >= 18", expr = "Age >= 18"),
  list(id = "age_ge_45", label = "Age >= 45", expr = "Age >= 45"),
  list(id = "age_lt_45", label = "Age < 45", expr = "Age < 45")
)
config$environment_voc_extreme_trim$enable <- TRUE
config$environment_voc_extreme_trim$drop_frac_per_wave <- 0.005
config$environment_voc_clinical_gate$voc_gate_mode         <- "univariate_vif"
config$environment_voc_clinical_gate$voc_univariate_source <- "tb1"
config$environment_voc_clinical_gate$voc_univariate_p_cutoff <- 0.05
config$environment_voc_clinical_gate$require_pass_for_lasso  <- TRUE
config$environment_voc_clinical_gate$voc_vif_threshold      <- 4
config$environment_voc_clinical_gate$voc_cor_enable        <- TRUE
config$environment_voc_clinical_gate$voc_cor_threshold     <- 0.80
config$environment_voc_clinical_gate$voc_cor_method          <- "pearson"
config$environment_voc_clinical_gate$voc_cor_mode            <- "iterative"
config$environment_batch$exclude_vocs_from_clinical_vif    <- FALSE
config$environment_batch$include_vocs_in_clinical_screen   <- TRUE
config$environment_voc_recovery$min_glm_vocs               <- 3L

config$rcs_nhanes$covariate_search <- TRUE
config$rcs_nhanes$require_all_models_significant <- TRUE
config$rcs_nhanes$p_threshold <- 0.05

config$mediation_ers_environment$export_mediator_figures <- FALSE
config$mediation_ers_environment$auto_covariate_search <- TRUE
config$mediation_ers_environment$require_positive_indirect <- TRUE
config$bkmr_fit$min_select_vocs <- 3L
config$environment_bkmr <- list(min_vocs_before_bkmr = 3L)
config$environment$display_label_map <- c(AMC = "AMCC", URXAMC = "AMCC")

config$environment_target$enable        <- TRUE
config$environment_target$data_dir    <- file.path(.cfg_root, "VOC 最终/Step12_Target")
config$environment_target$project_root  <- .cfg_root

config$qgcomp_environment$table_filename <- "Table S19. Associations of Environmental Toxicants with DKD by using Quantile g-Computation.csv"
config$qgcomp_environment$table_title    <- "Table S19. Associations of Environmental Toxicants with DKD by using Quantile g-Computation"

config$mediation_ers_environment$boot           <- FALSE
config$mediation_ers_environment$sims           <- 500L
config$mediation_ers_environment$compute_fi_lab <- FALSE
config$mediation_ers_environment$allow_empty_results <- TRUE
config$mediation_ers_environment$mediators <- c(
  "Uric_Acid", "Glucose", "Triglycerides", "CRP", "Albumin", "Globulin"
)

config$feishu$literature_default <- "DKD × 环境 VOC（NHANES, Ren 2024, PMID 37419158）"
config$feishu$project_id         <- "05_DKD_environment_37419158"
config$feishu$protocol_label     <- "05_DKD_environment_37419158"

config$environment_batch$subgroup_strata[[4]]$stratify_col   <- "Smoking"
config$environment_batch$subgroup_strata[[4]]$strata_levels  <- c("nonSmoked", "Smoked")
config$environment_batch$covariate_fallback$enable <- TRUE

pipeline_shared$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
pipeline_tail$checkpoint$dir   <- file.path(.batch_ck_root, "_shared", "main")
pipeline$checkpoint$dir        <- file.path(.batch_ck_root, "full_run")
