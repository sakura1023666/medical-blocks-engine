###############################################################################
#  configs/study_interface/incidence_dual_batch_build.R
#
#  由程序员研究目录下的 config.R 调用；程序员只维护 .study 列表。
#  前置条件: 已定义 .study、.batch_project_root；环境变量 MEDICAL_BLOCKS_ROOT 已设置。
#
#  产出: config, pipeline_shared_*, pipeline_nhanes_batch, pipeline_regular_batch
###############################################################################

if (!exists(".study", inherits = TRUE))
  stop(".study 未定义：请在 config.R 顶部设置", call. = FALSE)

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.engine))
  stop("MEDICAL_BLOCKS_ROOT 未设置：请使用 run_study.bat / run_study.sh 运行", call. = FALSE)

.study <- .study %||% list()
.req <- function(x, key) {
  v <- .study[[key]]
  if (is.null(v) || (is.character(v) && !nzchar(v)))
    stop("config.R 中 .study$", key, " 必填", call. = FALSE)
  v
}

if (!exists(".batch_project_root", inherits = TRUE) || !nzchar(.batch_project_root %||% "")) {
  .study_config_file <- {
    ca <- commandArgs(trailingOnly = TRUE)
    i  <- match("--config", ca)
    if (!is.na(i) && i < length(ca))
      normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
    else
      NA_character_
  }
  .batch_project_root <- if (!is.na(.study_config_file)) {
    dirname(.study_config_file)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
}

.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")
.batch_data_root <- file.path(.batch_project_root, "Data")

disease_code   <- .req(.study, "disease_code")
disease        <- .req(.study, "disease")
pmid           <- .study$literature_pmid %||% .study$pmid %||% "00000000"
analysis_group <- .study$analysis_group %||% disease
reference_grp  <- .study$reference_group %||% paste0("Non_", disease)
index_group    <- .study$index_group %||% "dual_safe"
index_vars     <- .study$index_vars %||% NULL
feishu_on      <- isTRUE(.study$feishu_enable %||% FALSE)

eicu_obj  <- .study$eicu_rdata_obj %||% "eicu"
mimic_obj <- .study$mimic_rdata_obj %||% "mimic"
eicu_map  <- .study$eicu_column_mapping %||% "eICU"
mimic_map <- .study$mimic_column_mapping %||% "MIMIC"

common_model <- .study$common_model_factors %||% c("SBP", "Potassium", "BUN", "Hypertension")
demo_m1      <- .study$harmonized_model1 %||% c("Age", "Gender")
demo_m2      <- .study$harmonized_model2 %||% c(demo_m1, common_model)

sens_enable <- isTRUE(.study$sensitivity_enable %||% TRUE)
age_cutoff  <- as.integer(.study$sensitivity_age_cutoff %||% 65L)

config <- list(
  data = list(
    rawdata_path     = file.path(.batch_data_root, "eicu/D01_eicu.RData"),
    rawdata_obj      = eicu_obj,
    outcome_path     = NULL,
    outcome_column   = "Disease_Group",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "subject_id", "SEQN")
  ),
  project = list(
    name                = paste0(disease, "_dual_batch"),
    disease_code        = disease_code,
    disease             = disease,
    literature_pmid     = pmid,
    database            = "eICU",
    database_type       = "regular",
    study_type          = "incidence",
    classification_mode = "binary",
    analysis_group      = analysis_group,
    reference_group     = reference_grp,
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root  = TRUE,
    root                = NULL
  ),
  incidence = list(
    outcome_var = "Disease_Group", index_var = NULL,
    index_component_vars = NULL, index_exclude_vars = NULL
  ),
  logistic = list(index_var = NULL, model2_max_covariates = 6L),
  index = list(enable = TRUE, only = NULL, skip = NULL, digits = 4L),
  nhanes = list(
    survey_weight = "new_Weight", survey_cluster = "SDMVPSU", survey_strata = "SDMVSTRA",
    cutoff_index_var = NULL, auto_new_weight = TRUE,
    exclude_cols = c("ID", "SEQN", "new_Weight", "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
                     "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File")
  ),
  prediction = list(index_vars = NULL, keep_index_vars_in_regression_table = TRUE),
  plot = list(font_family = "Times New Roman"),
  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),
  data_clean = list(missing_threshold = 0.3, age_filter = NULL, drop_columns = NULL),
  column_mapping = list(enable = TRUE, database_type = eicu_map),
  imputation = list(
    missing_col_threshold = 0.4, method = "cart", m = 1L, max_iter = 5L,
    seed = 1234L, complete_action = 1L, export_missing_fig = TRUE, export_table_s1 = TRUE
  ),
  dual_db = list(
    enable = TRUE, mirror_aggregate = TRUE, checkpoint_base = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    current_db = NULL,
    primary = list(
      name = "eICU", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "eicu/D01_eicu.RData"),
      rawdata_obj = eicu_obj, id_column = "ID", column_mapping_type = eicu_map
    ),
    secondary = list(
      name = "MIMIC", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "mimic/D01_mimic.RData"),
      rawdata_obj = mimic_obj, id_column = "ID", column_mapping_type = mimic_map
    ),
    harmonization = list(
      index_component_vars = NULL,
      demo_keywords = c("Age", "Gender", "Sex", "Race", "ethnicity", "Education", "edu",
                        "Marital", "marriage", "Income", "PIR", "poverty", "Smoking",
                        "Smoke", "Insurance", "Language", "Alcohol"),
      common_non_demo_cols = common_model,
      common_model_factors = common_model,
      harmonized_model1_nhanes = demo_m1, harmonized_model2_nhanes = demo_m2,
      harmonized_model1_mimic = demo_m1, harmonized_model2_mimic = demo_m2,
      require_same_clinical_cols = TRUE, sync_after_vif_final = TRUE,
      covariate_source = "vif_screen", sync_logistic_branch = TRUE,
      subgroup_var_aliases = list(
        Gender = c("Gender", "Sex"), Smoking = c("Smoking", "Smoke"),
        Smoke = c("Smoking", "Smoke")
      )
    )
  ),
  feishu = list(
    enable = feishu_on,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    literature_default = paste0("eICU + MIMIC 发病双库（", disease_code, " ", disease, ", PMID ", pmid, "）"),
    project_id = paste0(disease_code, "_", disease, "_incidence_", pmid),
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = feishu_on, push_on_batch_summary = feishu_on,
    disease_label = paste0(disease_code, "_", disease),
    protocol_label = paste0(disease_code, "_", disease, "_incidence_", pmid),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),
  incidence_batch = list(
    index_vars = index_vars, index_group = index_group,
    parallel_workers = NULL, fail_policy = "continue", skip_existing = TRUE,
    db_mode = "both", output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    ram_per_worker_gb = 2.0, cpu_headroom = 2L, ram_headroom_gb = 4.0,
    max_workers = NULL, gate_a_missing_threshold = 1.0, min_valid_per_db = 50L,
    nhanes_imputation_threshold = 0.40, mimic_imputation_threshold = 0.40,
    base_exclude_vars = c("ID", "SEQN", "subject_id", "Hemoglobin", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR", "WTSAF2YR", "WTSAF4YR",
      "SDMVPSU", "SDMVSTRA", "Source_File"),
    extra_index_exclude_vars = c("Hemoglobin"),
    base_subgroup_vars = c("Age", "Gender", "Race", "Hypertension", "T2DM",
                           "COPD", "Heart_Failure", "CKD", "Pneumonia"),
    sensitivity_suite = if (sens_enable) list(
      enable = TRUE, age_cutoff = age_cutoff, min_n_per_db = 50L,
      scenarios = list(
        list(label = "SA_no_hypertension",
             expr = 'is.na(Hypertension) | trimws(as.character(Hypertension)) != "Yes"'),
        list(label = "SA_no_diabetes",
             expr = 'is.na(T2DM) | trimws(as.character(T2DM)) != "Yes"'),
        list(label = "SA_no_cancer",
             expr = 'is.na(Cancer) | trimws(as.character(Cancer)) != "Yes"'),
        list(label = "SA_age_lt_{age_cutoff}", expr = "Age < {age_cutoff}")
      )
    ) else list(enable = FALSE)
  )
)

# 合并 block 级默认参数 + pipeline（来自引擎内标准模板，程序员不可见）
.template_path <- file.path(.engine, "configs/templates/config_incidence_dual_batch.template.R")
if (!file.exists(.template_path))
  stop("引擎模板缺失: ", .template_path, call. = FALSE)

.study_config <- config
._saved_root <- .batch_project_root
._saved_ck   <- .batch_ck_root
._saved_data <- .batch_data_root
source(.template_path, local = TRUE)  # 定义 config + pipeline_*（会覆盖 .batch_* 占位变量）
.batch_project_root <- ._saved_root
.batch_ck_root      <- ._saved_ck
.batch_data_root    <- ._saved_data

# 深合并：程序员 .study 覆盖模板顶层段
.deep_merge <- function(base, patch) {
  if (!is.list(base) || !is.list(patch)) return(patch)
  nm <- union(names(base), names(patch))
  out <- base
  for (k in nm) {
    if (k %in% names(patch)) {
      out[[k]] <- if (is.list(patch[[k]]) && is.list(base[[k]]))
        .deep_merge(base[[k]], patch[[k]]) else patch[[k]]
    }
  }
  out
}
config <- .deep_merge(config, .study_config)

# 强制写回路径（模板 source 时会用模板内 .batch_project_root 占位）
config$project$output_dir <- .batch_project_root
config$incidence_batch$output_base <- .batch_project_root
config$incidence_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared")
config$incidence_batch$index_ck_base <- file.path(.batch_ck_root, "by_index")
config$dual_db$checkpoint_base <- .batch_ck_root
config$dual_db$harmonization_dir <- file.path(.batch_ck_root, "_global_harmonization")
config$data$rawdata_path <- file.path(.batch_data_root, "eicu/D01_eicu.RData")
config$dual_db$primary$rawdata_path <- file.path(.batch_data_root, "eicu/D01_eicu.RData")
config$dual_db$secondary$rawdata_path <- file.path(.batch_data_root, "mimic/D01_mimic.RData")

# 修正 pipeline checkpoint 目录
pipeline_shared_nhanes$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "eICU")
pipeline_shared_regular$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "MIMIC")

rm(.study_config, .template_path, .study, .engine, .req, .deep_merge,
   "._saved_root", "._saved_ck", "._saved_data",
   list = intersect(
  c("disease_code", "disease", "pmid", "analysis_group", "reference_grp",
    "index_group", "index_vars", "feishu_on", "eicu_obj", "mimic_obj",
    "eicu_map", "mimic_map", "common_model", "demo_m1", "demo_m2",
    "sens_enable", "age_cutoff"),
  ls()
))

invisible(NULL)
