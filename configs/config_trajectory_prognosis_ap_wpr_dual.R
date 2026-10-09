###############################################################################
# Acute pancreatitis, MIMIC + eICU dual-database WPR trajectory prognosis.
# New output root — does NOT overwrite
#   41_AP/Prognosis_Trajectory_38882552/by_index or checkpoints.
#
# Prepare:
#   Rscript run/trajectory_prognosis/prepare_ap_eicu_wpr_dual_data.R
# Run:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#     --config configs/config_trajectory_prognosis_ap_wpr_dual.R \
#     --only-index WPR --workers 1
###############################################################################

source("configs/templates/config_trajectory_prognosis_batch.template.R")

.ap_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
.src_project_root <- file.path(.ap_root, "41_AP/Prognosis_Trajectory_38882552")
.ap_project_root <- file.path(.ap_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual")
.ap_eicu_dir <- file.path(.ap_project_root, "data/eicu")
.ap_mimic_dir <- file.path(.ap_project_root, "data/mimic")
.ap_eicu_baseline <- file.path(.ap_eicu_dir, "D01_AP_EICU_surv28.csv")
.ap_mimic_baseline <- file.path(.ap_mimic_dir, "D01_AP_MIMIC_surv28.csv")
.ap_eicu_labs <- file.path(.ap_eicu_dir, "eicu-实验室指标-wbc-plt-1~28天.csv")
.ap_mimic_labs <- file.path(.ap_mimic_dir, "mimic-实验室指标-all-1~30天.csv")
.ap_coverage <- file.path(.ap_project_root, "data/trajectory_index_coverage.csv")

if (!file.exists(.ap_eicu_baseline) || !file.exists(.ap_eicu_labs)) {
  stop("缺少 eICU 预处理表，请先运行 prepare_ap_eicu_wpr_dual_data.R", call. = FALSE)
}
if (!file.exists(.ap_mimic_baseline) || !file.exists(.ap_mimic_labs)) {
  stop("缺少 MIMIC 基线/实验室表（应在本课题 data/mimic/）", call. = FALSE)
}
if (!file.exists(.ap_coverage)) {
  stop("缺少指标覆盖率审计表，请先运行 prepare_ap_eicu_wpr_dual_data.R", call. = FALSE)
}

.ap_index_vars <- "WPR"

.disease_exclusion_vars <- c(
  "Lipase", "Amylase", "Pancreatitis", "Acute_Pancreatitis",
  "BISAP", "Ranson", "APACHEII", "Pancreatic_Necrosis", "Pseudocyst"
)

.eicu_only_table_vars <- c(
  "Ventilation", "Diabetes", "SOFA", "APSIII", "OASIS", "GCS", "PP",
  "PH", "PCO2", "PO2", "Lactate", "TotalCo2", "FreeCalcium",
  "PT", "PTT", "INR", "CK", "CKMb", "TroponinT", "BNP",
  "UrineOsmolality", "CRP", "HSCRP", "UrineCreatinine",
  "CalciumTotal", "Chloride", "BilirubinDirect", "BilirubinIndirect"
)

.outcome_leak_vars <- c(
  "stay_id", "hadm_id", "patientunitstayid", "ID",
  "survival_time_28d", "survival_28d",
  "is_dead", "is_hosp_dead", "is_icu_dead",
  "death_within_hosp_28days", "death_within_icu_28days",
  "hosp_survival_day", "icu_survival_day", "dead_time",
  "hosp_day", "icu_day", "admit_time", "icu_intime",
  "disch_time", "icu_outtime", "discharge_location",
  "hospdischargestatus", "hosplosday", "unitlosday",
  "unitdischargestatus", "unitdischargelocation",
  "hospitaldischargelocation", "hospitaladmitsource",
  "unitadmitsource", "unitstaytype", "unittype"
)

config$project$name <- "Prognosis_Trajectory_38882552_AP_WPR_dual"
config$project$disease <- "Acute pancreatitis"
config$project$disease_code <- "41"
config$project$analysis_group <- "Non-survivor"
config$project$reference_group <- "Survivor"
config$project$database <- "eICU+MIMIC"
config$project$output_dir <- .ap_project_root
config$project$mirror_pub_outputs_to_root <- TRUE

config$data$rawdata_path <- .ap_eicu_baseline
config$data$rawdata_obj <- NULL
config$data$id_column <- "subject_id"
config$data$outcome_column <- "survival_28d"

config$survival$time_var <- "survival_time_28d"
config$survival$event_var <- "survival_28d"
config$survival$index_var <- "WPR"

config$data_clean$missing_threshold <- 1.0
config$data_clean$subsample_n <- NULL
config$column_mapping$enable <- FALSE

config$analysis_exclusion$disease_vars <- .disease_exclusion_vars
config$analysis_exclusion$component_scope <- "current_transitive"
config$analysis_exclusion$allow_no_index <- TRUE
config$analysis_exclusion$exclude_other_composite_indices <- TRUE
config$analysis_exclusion$exclude_exposure_if_uses_disease_var <- TRUE

config$imputation$missing_col_threshold <- 0.95
config$imputation$table_s1_exclude_vars <- unique(c(
  config$imputation$table_s1_exclude_vars,
  .disease_exclusion_vars,
  .eicu_only_table_vars
))

config$baseline_binary$exclude_vars <- unique(c(
  config$baseline_binary$exclude_vars,
  .outcome_leak_vars,
  .disease_exclusion_vars,
  .eicu_only_table_vars
))
config$baseline_binary$always_include_vars <- c("survival_time_28d")
# Table S2 判 HR 为正态（Mean±SD）时，勿再被模板 vital_sign 强制改成 median(IQR)
.miqr_vars <- as.character(config$baseline_binary$median_iqr_vars)
if (!length(.miqr_vars) || all(is.na(.miqr_vars))) .miqr_vars <- character(0)
config$baseline_binary$median_iqr_vars <- setdiff(.miqr_vars, "HR")
rm(.miqr_vars)
config$univariate_prognosis$excluded_predictors <- unique(c(
  config$univariate_prognosis$excluded_predictors,
  .outcome_leak_vars,
  .disease_exclusion_vars,
  .eicu_only_table_vars
))
config$multicollinearity$exclude_vars <- unique(c(
  config$multicollinearity$exclude_vars,
  .outcome_leak_vars,
  .disease_exclusion_vars,
  .eicu_only_table_vars
))

# 年龄切点依据：AP 队列常用 ≥65 定义为老年（PMID 36205509）。
# 双库亚组：只锁两库都有、且 eICU 最小类大致可用的变量。
# 排除 Language/Marital_Status/Acute_Renal_Failure/Tuberculosis（eICU 无列）；
# 排除 T2DM/MI/肿瘤/肝硬化/卒中/高脂（eICU 最小类 <20）。
config$subgroup <- list(
  age_cutoff = 65L,
  level_order = list(Age_Group = c("< 65", "\u2265 65"))
)
config$trajectory_subgroup_class$age_var <- "Age"
config$trajectory_subgroup_class$age_cutoff <- 65L
config$trajectory_subgroup_class$auto_scan_categorical <- FALSE
config$trajectory_subgroup_class$subgroup_vars <- c(
  "Gender", "Race", "Hypertension", "Heart_Failure", "CKD",
  "Hepatitis", "Pneumonia", "COPD"
)

config$trajectory_jlcm$index_vars <- .ap_index_vars
config$trajectory_jlcm$rawdata_path_template <- file.path(
  .ap_project_root, "data/{db}/12_{Index}.RData"
)
config$trajectory_jlcm$output_dir_template <- file.path(.ap_project_root, "data/{db}")
config$trajectory_jlcm$id_column <- "subject_id"
config$trajectory_jlcm$survival_time_var <- "survival_time_28d"
config$trajectory_jlcm$survival_event_var <- "survival_28d"
# 双库套路：VIF 终稿交集后共用 JLCM survival 协变量。
config$trajectory_jlcm$dual_db_harmonize_survival_covariates <- TRUE
config$trajectory_jlcm$stop_on_ng1_fail <- TRUE
config$trajectory_jlcm$stop_on_ng2_fail <- FALSE
# 锁定 MIMIC 已发表 WPR 类别数（optimal_ng_WPR.txt = 2）。
config$trajectory_jlcm$prefer_final_ng <- 2L
config$trajectory_jlcm$assign_class_ng <- 2L
config$trajectory_jlcm$auto_select_class_ng <- TRUE
config$trajectory_jlcm$gridsearch_rep <- 20L
config$trajectory_jlcm$gridsearch_maxiter <- 10L

for (.block_name in c(
  "trajectory_plot_jlcm", "trajectory_km_class", "trajectory_dynpred",
  "trajectory_piecewise_cox", "trajectory_weibull_compare",
  "trajectory_subgroup_class", "trajectory_baseline_by_class",
  "trajectory_chisq"
)) {
  config[[.block_name]]$index_vars <- .ap_index_vars
}
config$trajectory_dynpred_individual$index_vars <- .ap_index_vars
config$trajectory_chisq$outcome_vars <- c("survival_28d")
config$trajectory_chisq$pause_on_all_ns <- FALSE
# 与 Table S5/S6/S7/S8/KM/Table3 同一原始 JLCM 标签：Class1=多数低风险，禁止 majority-swap
config$trajectory$skip_class_swap <- TRUE
config$trajectory_plot_jlcm$skip_class_swap <- TRUE
config$trajectory_km_class$skip_class_swap <- TRUE

# 双库发表收口（能力在 R/trajectory_pub_finalize.R + trajectory_dual_pub_harmonize.R）
config$trajectory_pub$enable <- TRUE
config$trajectory_pub$combine_figures <- TRUE
config$trajectory_pub$skip_class_swap <- TRUE
config$trajectory_pub$drop_missing_overview <- TRUE
config$trajectory_pub$figure_extra <- c(
  "Figure S9. Trajectory of WPR three latent classes",
  "Figure S10. Twenty-eight day mortality by WPR trajectory class"
)
config$trajectory_pub$shared_piecewise_cut$enable <- TRUE
# 两库 Table3 共用主库 MIMIC 最优切点；根目录保留 MIMIC+eICU 两份 Table3
config$trajectory_pub$shared_piecewise_cut$mode <- "mimic"
# 分段 Cox 切点搜索图仍只留主库；Table3 不因本项删次库
config$trajectory_pub$shared_piecewise_cut$cut_search_fig_db <- "mimic"
config$trajectory_pub$shared_piecewise_cut$root_keep_db <- NULL
config$trajectory_pub$align_dual_tables <- list(
  enable = TRUE,
  kinds = c("table1", "s1", "s2", "s3", "s5"),
  keep_vars = NULL # NULL = 两库变量交集
)
config$trajectory_pub$export_formats <- TRUE
config$trajectory_pub$enforce_13_figures <- TRUE
config$trajectory_pub$fix_tables <- TRUE

config$feishu$enable <- FALSE
config$feishu$disease_label <- "41_AP_Trajectory_WPR_dual"
config$feishu$protocol_label <- "trajectory_prognosis_jlcm_ap_wpr_dual"

# runner 约定：primary = eICU，secondary = MIMIC。
# 拼图 A=MIMIC（原主分析），B=eICU（外验）。
config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  combine_figures = list(
    enable = TRUE,
    remove_singles = TRUE,
    drop_missing_overview = TRUE,
    panel_order = "secondary_first",
    label_format = "A. {db}"
  ),
  primary = list(
    name = "eICU",
    db_type = "eicu",
    rawdata_path = .ap_eicu_baseline,
    rawdata_obj = NULL,
    id_column = "subject_id",
    lab_id_column = "patientunitstayid",
    output_subdir = .ap_eicu_dir,
    lab_sources = list(path = .ap_eicu_labs)
  ),
  secondary = list(
    name = "MIMIC",
    db_type = "mimic",
    rawdata_path = .ap_mimic_baseline,
    rawdata_obj = NULL,
    id_column = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = .ap_mimic_dir,
    lab_sources = list(path = .ap_mimic_labs)
  )
)

config$trajectory_calc_28d_index <- list(
  index_vars = .ap_index_vars,
  days = 1:28,
  min_non_na_days = 2L,
  min_n_after_index = 49L,
  restrict_to_baseline_ids = TRUE
)

config$trajectory_batch <- list(
  output_base = .ap_project_root,
  shared_ck_base = file.path(.ap_project_root, "checkpoints/_shared"),
  index_ck_base = file.path(.ap_project_root, "checkpoints/by_index"),
  db_seq = c("eicu", "mimic"),
  index_vars = .ap_index_vars,
  index_group = NULL,
  parallel_workers = 1L,
  worker_script = "run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R",
  pipeline_unit_prefix = pipeline_unit_prefix,
  pipeline_unit_suffix = pipeline_unit_suffix
)

config$imputation$exclude_from_mice_cols <- unique(c(
  config$imputation$exclude_from_mice_cols,
  .composite_index_vars
))
config$imputation$table_s1_exclude_vars <- unique(c(
  config$imputation$table_s1_exclude_vars,
  .composite_index_vars
))

pipeline <- pipeline_shared

rm(.block_name)
