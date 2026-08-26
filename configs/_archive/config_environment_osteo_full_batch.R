###############################################################################
#  config_environment_osteo_full_batch.R — 骨质疏松 × 环境暴露全量
#
#  数据: G:/02block_result/10_osteoporosis/environment_37419158/data
#       未删人全队列（baseline_sav），与「10_osteoporosis - 副本」删人目录完全隔离
#
#  用法:
#    Rscript run/environment/run_environment_dkd_batch.R \
#      --config configs/config_environment_osteo_full_batch.R --workers auto --no-skip
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()
source(file.path(.cfg_root, "configs/config_environment_dkd_batch.R"), local = FALSE)

.resolve_batch_path <- function(p) {
  p <- as.character(p)[1L]
  if (grepl("^\\\\", p)) {
    p <- sub("^\\\\\\\\[^\\\\]+\\\\", "G:/", gsub("\\\\", "/", p))
  }
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || dir.exists(dirname(wsl))) return(wsl)
  }
  p
}

.batch_project_root <- .resolve_batch_path("G:/02block_result/10_osteoporosis/environment_37419158")
.batch_data_root      <- file.path(.batch_project_root, "data")
.batch_ck_root        <- file.path(.batch_project_root, "checkpoints")

config$data$rawdata_path          <- file.path(.batch_data_root, "nhanes/D03_EnvResultData.RData")
config$data$rawdata_obj           <- "EnvResult"
config$data$outcome_column        <- "Group"

config$project$analysis_group  <- "Osteoporosis"
config$project$reference_group <- "No_Osteoporosis"
config$project$disease         <- "Osteoporosis"
config$project$disease_cn      <- "骨质疏松"
config$glm_environment_quartile$analysis_group   <- "Osteoporosis"
config$glm_environment_quartile$reference_group  <- "No_Osteoporosis"

config$environment_prepare$enable                      <- TRUE
config$environment_prepare$mode                        <- "baseline_sav"
config$environment_prepare$data_dir                    <- .batch_data_root
config$environment_prepare$nhanes_dir                    <- .batch_data_root
config$environment_prepare$baseline_file               <- "D01_baseline_NHANES_0610_DN.RData"
config$environment_prepare$baseline_obj                <- "baseline"
config$environment_prepare$environment_sav_file        <- file.path(.batch_data_root, "enviroment-factors.sav")
config$environment_prepare$baseline_pattern            <- "baseline.*NHANES.*\\.RData$"
config$environment_prepare$env_voc_pattern             <- "^(URX|LBX)"
config$environment_prepare$voc_exclude_fixed             <- c("URXUCR")
config$environment_prepare$merged_output_dir             <- file.path(.batch_data_root, "nhanes")
config$environment_prepare$save_merged                   <- TRUE
config$environment_prepare$env_weight_file               <- file.path(.batch_data_root, "D01_环境_权重_总砷 (2).RData")
config$environment_prepare$env_weight_obj                <- "df"
config$environment_prepare$env_weight_col                <- "WTSA2YR"
config$environment_prepare$env_weight_fallback_wtmec     <- TRUE
config$environment_prepare$require_env_weight            <- TRUE
config$environment_prepare$merged_weight_col             <- "new_Weight"
config$environment_prepare$kidney_disease_voc_workflow   <- FALSE
config$environment_prepare$adjust_voc_urinary_creatinine <- TRUE
config$environment_prepare$restore_all_voc_to_ugl        <- FALSE
config$environment_prepare$urinary_creatinine_file         <- file.path(.batch_data_root, "尿肌酐_nhanes.csv")
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
config$environment_voc_log_transform$apply_log           <- TRUE
config$environment_voc_log_transform$force_all_vocs        <- TRUE
config$environment_lod$legacy_stats_file                   <- file.path(.cfg_root, "Data/stats(1).RData")
config$environment_lod$legacy_stats_obj                    <- "stats"
# 样本×列迭代筛查（替代原 20%/80% Under-LOD 整列剔除）
config$environment_lod$sample_column_filter_enable         <- TRUE
config$environment_lod$drop_analytes_by_stats              <- FALSE
config$environment_lod$sample_miss_frac_initial            <- 0.8
config$environment_lod$sample_miss_frac_step             <- 0.05
config$environment_lod$sample_miss_frac_min              <- 0.5
config$environment_lod$column_missing_cutoff             <- 0.40
config$environment_lod$min_retained_vocs                   <- 10L
config$environment_lod$missing_cutoff                      <- 0.40
config$environment_lod$under_lod_cutoff                  <- 1.0
config$environment_process$missing_percentage_cutoff       <- 1.0
config$environment_process$below_limit_percentage_cutoff <- 1.0

config$nhanes$survey_weight   <- "new_Weight"
config$nhanes$auto_new_weight <- FALSE
config$nhanes$exclude_cols    <- unique(c(
  config$nhanes$exclude_cols %||% character(0),
  "new_weight", "new_Weight", "WTSA2YR", "WTMEC2YR", "WTINT2YR",
  "cycle", "Source_File", "SDDSRVYR"
))
# cycle / Source_File：保留在数据中用于权重计算与周期对齐，但不作协变量、不出现在 Table1/S1/VIF/相关性图
config$multicollinearity$exclude_vars <- unique(c(
  config$multicollinearity$exclude_vars %||% character(0),
  "cycle", "Source_File", "SDDSRVYR"
))

config$imputation$table_s1_exclude_vars <- unique(c(
  config$imputation$table_s1_exclude_vars %||% character(0),
  "new_Weight", "new_weight", "WTSA2YR", "WTMEC2YR", "WTINT2YR"
))

config$project$name            <- "Osteoporosis_Environment_Full"
config$project$disease_code    <- "10"
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
  "Source_File", "cycle", "WTMEC2YR", "WTSA2YR", "DN"
)
config$imputation$missing_col_threshold   <- 0.40
config$imputation$force_keep_weight_cols  <- FALSE
config$environment$voc_col_pattern      <- "^(URX|LBX)"
config$environment$display_label_map <- c(AMC = "AMCC", URXAMC = "AMCC")

config$imputation$exclude_from_mice_cols <- c(
  "Source_File", "cycle", "SDDSRVYR", "WTSA2YR", "WTSAF2YR", "WTSAF4YR",
  "WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTINT4YR",
  "SDMVPSU", "SDMVSTRA", "new_Weight", "DN"
)
config$remove_outliers$cols   <- NULL
config$remove_outliers$enable <- FALSE

config$bkmr_fit$auto_iter            <- FALSE
config$bkmr_fit$iter                 <- 1000L
config$bkmr_fit$nchains              <- 2L
# BKMR 结果不好时（整体效应无趋势 / PIP 退化）对该步单独标准化协变量后重拟合
config$bkmr_fit$standardize_covariates_if_bad <- FALSE
config$bkmr_fit$covariates <- c(
  "Race", "BMI", "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

config$lasso_environment$univariate_enable     <- FALSE
config$lasso_environment$require_clinical_gate <- TRUE
config$lasso_environment$freq_cutoff_method    <- "auto_floor100"
config$lasso_environment$min_select_vocs       <- 5L
config$lasso_environment$auto_lambda_tighten  <- TRUE
config$lasso_environment$auto_lambda_min_exclude <- 1L
config$lasso_environment$cv_times              <- 1000L  # LASSO 稳定性重复次数
config$lasso_environment$fig_combined_filename   <- "Figure 2. Selection of Environmental exposure variables for 1000 Lasso regression.pdf"

# 单因素筛选阈值统一 0.05
config$univariate_nhanes$sig_cutoff       <- 0.05
config$univariate_nhanes$screening_cutoff <- 0.05
# 临床 VIF screen 只纳入单因素 p<0.05（tb1），不用 p<0.1 的 tb_screen
config$multicollinearity$screen$input_from <- "tb1"
# 临床协变量：只按单因素 P<0.05 进 VIF，不排除 OR<1（保护因素保留）
config$univariate_nhanes$exclude_or_below_one <- FALSE

config$wqs_environment$b <- 1000L
config$wqs_environment$skip_if_vocs_lte <- 2L
config$wqs_environment$strict_glm_vocs <- TRUE
config$wqs_environment$auto_select_vocs <- FALSE
config$wqs_environment$min_select_vocs <- 2L
# WQS 默认无协变量；不显著时再搜协变量子集
config$wqs_environment$p_threshold       <- 0.05
config$wqs_environment$require_significant <- TRUE
config$wqs_environment$search_covariates_if_nonsig <- TRUE
config$wqs_environment$search_extended   <- FALSE
config$wqs_environment$search_quick_b  <- 300L
config$wqs_environment$search_max_voc_trials <- 30L
config$wqs_environment$search_max_cov_trials <- 12L
config$wqs_environment$b1_pos_values     <- c(TRUE, FALSE)
config$wqs_environment$q_values          <- 4:10
config$wqs_environment$validation_values <- seq(0.5, 0.8, by = 0.05)
config$wqs_environment$seed_values       <- c(2025L, 123L, 42L, 777L, 314L)
config$wqs_environment$wqs_variable_label <- "WQS index"
config$wqs_environment$table_wqs_row_only <- FALSE
config$wqs_environment$table_filename <- paste0(
  "Table S9. Associations of WQS regression index with ",
  config$project$disease %||% "Outcome", ".xlsx"
)
config$wqs_environment$table_title <- paste0(
  "Table S9. Associations of WQS regression index with ",
  config$project$disease %||% "Outcome"
)
config$wqs_environment$covariates <- character(0)
config$wqs_environment$covariates_pool <- c(
  "Race", "BMI", "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

config$glm_environment_quartile$match_lasso_vocs          <- TRUE
config$glm_environment_quartile$require_lasso_passed      <- TRUE
config$glm_environment_quartile$use_wald_ci               <- TRUE
config$glm_environment_quartile$use_final_covariates      <- TRUE
config$glm_environment_quartile$covariate_search          <- TRUE
config$glm_environment_quartile$covariate_search_mode     <- "fast"
config$glm_environment_quartile$model2_factors <- c(
  "Age", "Gender", "Race", "PIR", "Education", "Smoking", "BMI",
  "Glucose", "HbA1c", "Uric_Acid", "Triglycerides"
)

# 临床 VIF 表(S4)展示临床协变量 + 通过单因素(P<0.05&OR>1)的环境毒物；Model2 仍自动排除 VOC
config$environment_batch$include_vocs_in_clinical_screen  <- TRUE
config$environment_batch$skip_clinical_multivariate     <- TRUE
config$environment_batch$exclude_vocs_from_clinical_vif   <- FALSE

# 临床/环境 VIF 筛选阈值统一为 4，逐一剔除 VIF>4（不被 feature_selection 放宽到 10）
config$multicollinearity$vif_threshold_strict                  <- 4
config$multicollinearity$vif_threshold_before_feature_selection <- 4

config$environment_voc_clinical_gate$enable                  <- TRUE
config$environment_voc_clinical_gate$require_table1          <- FALSE
config$environment_voc_clinical_gate$min_pass_vocs           <- 2L
config$environment_voc_clinical_gate$voc_gate_mode           <- "univariate_vif"
config$environment_voc_clinical_gate$voc_univariate_source <- "voc_survey"
config$environment_voc_clinical_gate$voc_univariate_p_cutoff <- 0.05
# VOC 单因素 OR<1 也排除（与临床协变量一致）
config$environment_voc_clinical_gate$voc_univariate_exclude_or_below_one <- TRUE
config$environment_voc_clinical_gate$require_pass_for_lasso  <- TRUE
config$environment_voc_clinical_gate$voc_vif_threshold       <- 4
config$environment_voc_clinical_gate$voc_vif_enable          <- TRUE
config$environment_voc_clinical_gate$voc_mv_min_for_step2    <- 5L
config$environment_voc_clinical_gate$voc_cor_enable          <- TRUE
config$environment_voc_clinical_gate$voc_cor_threshold       <- 0.70
config$environment_voc_clinical_gate$voc_cor_mode            <- "iterative"
config$environment_voc_clinical_gate$voc_cor_min_keep        <- 5L
# 相关性剪枝方法与 corrplot 图一致（Spearman），避免图显示 >0.7 而门禁按别的度量放行
config$environment_voc_clinical_gate$voc_cor_method          <- "spearman"

# corrplot 可视化
config$environment_corrplot                 <- list()
config$environment_corrplot$enable          <- TRUE
config$environment_corrplot$method          <- "spearman"
# 显示进入 LASSO 的最终 VOC 集合（相关性剪枝后），而非剪枝前的单因素集合
config$environment_corrplot$voc_source      <- "clinical_gate"
config$environment_corrplot$baseline_source <- "vif_final_pass"
config$environment_corrplot$table_prefix    <- "Table 2"
config$environment_corrplot$fig_width_voc   <- 8.5
config$environment_corrplot$fig_width_base  <- 11

config$environment_subgroup_search$enable <- TRUE
config$environment_subgroup_search$use_parallel <- FALSE
config$environment_subgroup_search$custom_filters <- list(
  list(id = "age_ge_18", label = "Age >= 18", expr = "Age >= 18"),
  list(id = "age_ge_45", label = "Age >= 45", expr = "Age >= 45"),
  list(id = "age_lt_45", label = "Age < 45", expr = "Age < 45")
)
config$environment_voc_extreme_trim$enable <- TRUE
config$environment_voc_recovery$min_glm_vocs <- 3L

config$environment_target$enable <- FALSE

config$mediation_ers_environment$allow_empty_results <- TRUE
config$mediation_ers_environment$sims <- 500L
config$mediation_ers_environment$compute_fi_lab <- FALSE
config$mediation_ers_environment$require_positive_indirect <- FALSE
config$mediation_ers_environment$auto_covariate_search <- TRUE

config$rcs_nhanes$covariate_search <- TRUE
# 每个 model（Crude/Model1/Model2）的 p for overall 都要 < 0.05；协变量自由搜索
config$rcs_nhanes$require_all_models_significant <- TRUE
config$rcs_nhanes$rcs_search_model2_only <- FALSE
config$rcs_nhanes$covariate_search_max_tries <- 800L
config$rcs_nhanes$covariate_search_seed <- 37419158L
config$rcs_nhanes$p_threshold <- 0.05
# RCS crude 必须显著：GLM 前按 crude RCS p_overall<0.05 预筛毒物，不显著的直接剔除
config$environment_voc_clinical_gate$crude_rcs_prefilter_enable  <- TRUE
config$environment_voc_clinical_gate$crude_rcs_p_threshold       <- 0.05
config$environment_voc_clinical_gate$crude_rcs_knots             <- 4L
# 协变量搜索池（自由挑选；随机搜索从并集抽样）
config$rcs_nhanes$model1_factor_sets <- list(
  c("Age", "Gender", "Race"),
  c("Age", "Gender", "Race", "PIR"),
  c("Age", "Gender", "BMI")
)
config$rcs_nhanes$model2_factor_sets <- list(
  c("Age", "Gender", "Race", "PIR", "BMI", "Glucose", "HbA1c", "Uric_Acid"),
  c("Age", "Gender", "Race", "BMI", "Triglycerides", "Total_Cholesterol", "SBP"),
  c("Age", "Gender", "Race", "PIR", "BMI", "Uric_Acid", "Potassium", "BUN"),
  c("Age", "Gender", "Race", "PIR", "Education", "Smoking", "BMI", "Glucose")
)

config$environment$exposure_code_file <- file.path(.batch_data_root, "Envrioment_code.RData")
config$environment$exposure_code_obj  <- "Envrioment_code"

config$feishu$literature_default <- "骨质疏松 × 环境暴露（未删人全队列 + 样本×列迭代筛查 A=n×0.8）"
config$feishu$project_id         <- "10_osteoporosis_environment_37419158"
config$feishu$protocol_label     <- "10_osteoporosis_environment_37419158"

config$environment_batch$subgroup_strata[[4]]$stratify_col  <- "Smoking"
config$environment_batch$subgroup_strata[[4]]$strata_levels <- c("nonSmoked", "Smoked")
config$environment_batch$covariate_fallback$enable <- TRUE

pipeline_shared$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
pipeline_tail$checkpoint$dir   <- file.path(.batch_ck_root, "_shared", "main")
pipeline$checkpoint$dir        <- file.path(.batch_ck_root, "full_run")

# 在 multicollinearity_nhanes_screen 之后插入 corrplot，再执行 clinical gate
.base_blocks <- pipeline_shared$blocks
.corrplot_idx <- which(.base_blocks == "multicollinearity_nhanes_screen")
if (length(.corrplot_idx) && !"environment_voc_corrplot" %in% .base_blocks) {
  pipeline_shared$blocks <- c(
    .base_blocks[seq_len(.corrplot_idx)],
    "environment_voc_corrplot",
    .base_blocks[seq(.corrplot_idx + 1L, length(.base_blocks))]
  )
}
