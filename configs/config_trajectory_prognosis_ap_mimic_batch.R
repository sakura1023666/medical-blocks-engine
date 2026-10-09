###############################################################################
# Acute pancreatitis, MIMIC single-database 28-day prognosis trajectories.
# Data preparation:
#   Rscript run/trajectory_prognosis/prepare_ap_mimic_trajectory_data.R
# Run:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#     --config configs/config_trajectory_prognosis_ap_mimic_batch.R --workers 5
###############################################################################

source("configs/templates/config_trajectory_prognosis_batch.template.R")

.ap_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
.ap_project_root <- file.path(.ap_root, "41_AP/Prognosis_Trajectory_38882552")
.ap_data_dir <- file.path(.ap_project_root, "data/mimic")
.ap_baseline <- file.path(.ap_data_dir, "D01_AP_MIMIC_surv28.csv")
.ap_labs <- file.path(.ap_data_dir, "mimic-实验室指标-all-1~30天.csv")
.ap_coverage <- file.path(.ap_project_root, "Data/trajectory_index_coverage.csv")

if (!file.exists(.ap_baseline)) {
  stop("缺少预处理基线表，请先运行 prepare_ap_mimic_trajectory_data.R", call. = FALSE)
}
if (!file.exists(.ap_coverage)) {
  stop("缺少指标覆盖率审计表，请先运行 prepare_ap_mimic_trajectory_data.R", call. = FALSE)
}

.ap_coverage_dt <- utils::read.csv(
  .ap_coverage,
  stringsAsFactors = FALSE,
  check.names = FALSE
)
.ap_index_vars <- unique(as.character(
  .ap_coverage_dt$index[.ap_coverage_dt$retained %in% TRUE]
))
if (!length(.ap_index_vars)) stop("覆盖率审计未保留任何指标", call. = FALSE)

# AP-specific hard exclusions. These columns are absent from the assembled
# baseline today, but remain locked out if later data revisions add them.
.disease_exclusion_vars <- c(
  "Lipase", "Amylase", "Pancreatitis", "Acute_Pancreatitis",
  "BISAP", "Ranson", "APACHEII", "Pancreatic_Necrosis", "Pseudocyst"
)

config$project$name <- "Prognosis_Trajectory_38882552_AP_MIMIC"
config$project$disease <- "Acute pancreatitis"
config$project$disease_code <- "41"
config$project$analysis_group <- "Non-survivor"
config$project$reference_group <- "Survivor"
config$project$database <- "MIMIC"
config$project$output_dir <- .ap_project_root
config$project$mirror_pub_outputs_to_root <- TRUE

config$data$rawdata_path <- .ap_baseline
config$data$rawdata_obj <- NULL
config$data$id_column <- "subject_id"
config$data$outcome_column <- "survival_28d"

config$survival$time_var <- "survival_time_28d"
config$survival$event_var <- "survival_28d"
config$survival$index_var <- NULL

# Keep sparse baseline components during the shared calculation; the unit
# imputation stage applies its own threshold. No n=1000 template subsampling.
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
  .disease_exclusion_vars
))

.outcome_leak_vars <- c(
  "stay_id", "hadm_id", "survival_time_28d", "survival_28d",
  "is_dead", "is_hosp_dead", "is_icu_dead",
  "death_within_hosp_28days", "death_within_icu_28days",
  "hosp_survival_day", "icu_survival_day", "dead_time",
  "hosp_day", "icu_day", "admit_time", "icu_intime",
  "disch_time", "icu_outtime", "discharge_location"
)
config$baseline_binary$exclude_vars <- unique(c(
  config$baseline_binary$exclude_vars,
  .outcome_leak_vars,
  .disease_exclusion_vars
))
config$baseline_binary$always_include_vars <- c("survival_time_28d")
config$univariate_prognosis$excluded_predictors <- unique(c(
  config$univariate_prognosis$excluded_predictors,
  .outcome_leak_vars,
  .disease_exclusion_vars
))
config$multicollinearity$exclude_vars <- unique(c(
  config$multicollinearity$exclude_vars,
  .outcome_leak_vars,
  .disease_exclusion_vars
))

# Age cutoff basis: AP cohorts commonly define elderly patients as >=65 years
# (e.g. PMID 36205509; BMC Gastroenterology 2023, 110,021-patient cohort).
# This supplied dataset has no Age column, so no artificial age subgroup is made.
config$subgroup <- list(
  age_cutoff = 65L,
  level_order = list(Age_Group = c("< 65", "\u2265 65"))
)
config$trajectory_subgroup_class$age_var <- "Age"
config$trajectory_subgroup_class$age_cutoff <- 65L
config$trajectory_subgroup_class$auto_scan_categorical <- FALSE
# 亚组名单（2026-09-17 基线表重并后按规则锁定）：
# 年龄二分类 <65/≥65（AP 老年界值文献）；分类变量最小类 >20 全部纳入；
# T1DM 最小类=14 <20 → 排除；Ventilation 本数据无此列。
config$trajectory_subgroup_class$subgroup_vars <- c(
  "Gender", "Race", "Language", "Marital_Status",
  "Hypertension", "T2DM", "Heart_Failure", "Myocardial_Infarction",
  "Malignant_Tumor", "CKD", "Acute_Renal_Failure", "Liver_cirrhosis",
  "Hepatitis", "Tuberculosis", "Pneumonia", "Stroke", "Hyperlipidemia", "COPD"
)

config$trajectory_jlcm$index_vars <- .ap_index_vars
config$trajectory_jlcm$rawdata_path_template <- file.path(
  .ap_project_root, "data/mimic/12_{Index}.RData"
)
config$trajectory_jlcm$output_dir_template <- file.path(.ap_data_dir)
config$trajectory_jlcm$id_column <- "subject_id"
config$trajectory_jlcm$survival_time_var <- "survival_time_28d"
config$trajectory_jlcm$survival_event_var <- "survival_28d"
config$trajectory_jlcm$dual_db_harmonize_survival_covariates <- FALSE
# ng=2 未收敛不再早停：继续 ng=3..cap，交给 health guard + BIC 选类（根因修复）。
config$trajectory_jlcm$stop_on_ng1_fail <- TRUE
config$trajectory_jlcm$stop_on_ng2_fail <- FALSE
# 本库 WPR/GPR n≈916，模板默认 rep=50 在 ng=4 上单步即 70min+；
# 降初始 rep 提速，收敛性由 health guard 的 gridsearch_refit（cap 200）兜底。
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
# 全指标批量扫描：某条轨迹与死亡无关联是正当阴性结果，不得中断整个 worker
# （否则丢 code 包 / 下游图并误判 failed）。
config$trajectory_chisq$pause_on_all_ns <- FALSE

config$trajectory_pub$enable <- TRUE
config$trajectory_pub$combine_figures <- FALSE
config$trajectory_pub$shared_piecewise_cut$enable <- FALSE
config$trajectory_pub$export_formats <- TRUE

# 亚组图恢复后沿用引擎默认 13 图白名单（Fig1–4 + S1–S9，S4=Subgroup）；
# 此前因空亚组图临时加的 figure_renumber / figure_stems 覆盖已移除。

config$feishu$enable <- FALSE
config$feishu$disease_label <- "41_AP_Trajectory"
config$feishu$protocol_label <- "trajectory_prognosis_jlcm_ap_mimic"

config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  combine_figures = list(enable = FALSE),
  secondary = list(
    name = "MIMIC",
    db_type = "mimic",
    rawdata_path = .ap_baseline,
    rawdata_obj = NULL,
    id_column = "subject_id",
    lab_id_column = "subject_id",
    output_subdir = .ap_data_dir,
    lab_sources = list(path = .ap_labs)
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
  db_seq = "mimic",
  index_vars = .ap_index_vars,
  index_group = NULL,
  parallel_workers = 5L,
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

rm(.block_name, .ap_coverage_dt)
