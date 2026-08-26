###############################################################################
#  configs/study_interface/survival_dual_batch_build.R
#
#  由程序员研究目录下的 config.R 调用；程序员只维护 .study 列表。
#  前置条件: 已定义 .study、.batch_project_root；环境变量 MEDICAL_BLOCKS_ROOT 已设置。
#
#  产出: config, pipeline_shared_regular, pipeline_regular_batch
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
analysis_group <- .study$analysis_group %||% "Non-survivor"
reference_grp  <- .study$reference_group %||% "Survivor"
index_group    <- .study$index_group %||% "dual_safe"
index_vars     <- .study$index_vars %||% NULL
feishu_on      <- isTRUE(.study$feishu_enable %||% FALSE)

eicu_rdata_file  <- .study$eicu_rdata_file %||% "D04_rt_CleanData.RData"
mimic_rdata_file <- .study$mimic_rdata_file %||% "D04_rt_CleanData.RData"
eicu_obj         <- .study$eicu_rdata_obj %||% "rt"
mimic_obj        <- .study$mimic_rdata_obj %||% "rt"
id_col           <- .study$id_column %||% "subject_id"
time_var         <- .study$time_var %||% "futime"
event_var        <- .study$event_var %||% "fustatus"
eicu_map         <- .study$eicu_column_mapping %||% "eICU"
mimic_map        <- .study$mimic_column_mapping %||% "MIMIC"

common_model <- .study$common_model_factors %||% NULL
# 勿默认写入 harmonized_model*：否则 dual_db_preset_gate_b 会跳过 VIF 决策树，导致 Model1=Model2
harm_lock    <- isTRUE(.study$lock_covariates_preset %||% FALSE)
harm_m1      <- if (harm_lock || !is.null(.study$harmonized_model1)) {
  as.character(.study$harmonized_model1 %||% c("Age", "Gender"))
} else {
  NULL
}
harm_m2      <- if (harm_lock || !is.null(.study$harmonized_model2)) {
  as.character(.study$harmonized_model2 %||% c(harm_m1 %||% c("Age", "Gender"), common_model %||% character(0)))
} else if (length(common_model %||% character(0))) {
  as.character(c(harm_m1 %||% c("Age", "Gender"), common_model))
} else {
  NULL
}

sens_enable  <- isTRUE(.study$sensitivity_enable %||% TRUE)
sgfb_enable  <- isTRUE(.study$subgroup_fallback_enable %||% TRUE)
age_cutoff   <- as.integer(.study$sensitivity_age_cutoff %||% 65L)

disease_short <- gsub("[^A-Za-z0-9_]", "_", disease)
protocol_id   <- paste0(disease_code, "_", disease_short, "_prognosis_", pmid)

config <- list(
  data = list(
    rawdata_path     = file.path(.batch_data_root, "eicu", eicu_rdata_file),
    rawdata_obj      = eicu_obj,
    outcome_path     = NULL,
    outcome_column   = event_var,
    id_column        = id_col,
    strip_id_columns_after_imputation = c("ID", id_col, "SEQN")
  ),
  project = list(
    name                = paste0(disease, "_dual_survival_batch"),
    disease_code        = disease_code,
    disease             = disease,
    literature_pmid     = pmid,
    database            = "eICU",
    database_type       = "regular",
    study_type          = "prognosis",
    classification_mode = "binary",
    analysis_group      = analysis_group,
    reference_group     = reference_grp,
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root  = TRUE,
    root                = NULL
  ),
  survival = list(
    time_var = time_var, event_var = event_var,
    index_var = NULL, time_unit = "days", time_divisor = 1
  ),
  logistic = list(index_var = NULL, model2_max_covariates = 20L),
  index = list(enable = TRUE, only = NULL, skip = NULL, digits = 4L),
  prediction = list(index_vars = NULL, keep_index_vars_in_regression_table = TRUE),
  plot = list(font_family = "Times New Roman"),
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
      rawdata_path = file.path(.batch_data_root, "eicu", eicu_rdata_file),
      rawdata_obj = eicu_obj, id_column = id_col, column_mapping_type = eicu_map
    ),
    secondary = list(
      name = "MIMIC", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "mimic", mimic_rdata_file),
      rawdata_obj = mimic_obj, id_column = id_col, column_mapping_type = mimic_map
    ),
    harmonization = list(
      index_component_vars = NULL,
      demo_keywords = c("Age", "Gender", "Sex", "Race", "ethnicity", "Education", "edu",
                        "Marital", "marriage", "Income", "PIR", "poverty", "Smoking",
                        "Smoke", "Insurance", "Language", "Alcohol"),
      common_non_demo_cols = common_model,
      common_model_factors = common_model,
      harmonized_model1_nhanes = harm_m1,
      harmonized_model2_nhanes = harm_m2,
      harmonized_model1_mimic = harm_m1,
      harmonized_model2_mimic = harm_m2,
      lock_covariates_preset = harm_lock,
      require_same_clinical_cols = FALSE,
      require_same_demo_cols = TRUE,
      stop_on_empty_common_clinical = FALSE,
      sync_after_vif_final = TRUE,
      # 多因素显著后仍用单因素→VIF screen 作 Cox 协变量，再在闸门 B 双库取交集
      covariate_source = "auto", sync_logistic_branch = FALSE,
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
    literature_default = paste0("eICU + MIMIC 预后双库（", disease_code, " ", disease, ", PMID ", pmid, "）"),
    project_id = protocol_id,
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = feishu_on, push_on_batch_summary = feishu_on,
    disease_label = paste0(disease_code, "_", disease_short),
    protocol_label = protocol_id,
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", "")
  ),
  survival_batch = list(
    index_vars = index_vars, index_group = index_group,
    parallel_workers = NULL, fail_policy = "continue", skip_existing = TRUE,
    db_mode = "both", output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    ram_per_worker_gb = 2.0, cpu_headroom = 2L, ram_headroom_gb = 4.0,
    max_workers = NULL, gate_a_missing_threshold = 1.0, min_valid_per_db = 50L,
    nhanes_imputation_threshold = 0.40, mimic_imputation_threshold = 0.40,
    base_exclude_vars = c("ID", "SEQN", id_col, "Hemoglobin", time_var, event_var,
      "new_Weight", "WTINT2YR", "WTMEC2YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"),
    extra_index_exclude_vars = c("Hemoglobin"),
    base_subgroup_vars = c("Age", "BMI", "Gender", "Hypertension", "T2DM",
                           "COPD", "Heart_Failure", "CKD", "Pneumonia"),
    protect_index_cols = c("BMI", "Weight", "Height"),
    sensitivity_suite = if (sens_enable) list(
      enable = TRUE, age_cutoff = age_cutoff, min_n_per_db = 50L,
      scenarios = list(
        # trimws：原始库常有 "Yes "/"No " 尾随空格，否则过滤恒真
        list(label = "SA_no_hypertension",
             expr = 'is.na(Hypertension) | trimws(as.character(Hypertension)) != "Yes"'),
        list(label = "SA_no_diabetes",
             expr = 'is.na(T2DM) | trimws(as.character(T2DM)) != "Yes"'),
        list(label = "SA_no_cancer",
             expr = 'is.na(Cancer) | trimws(as.character(Cancer)) != "Yes"'),
        list(label = "SA_age_lt_{age_cutoff}", expr = "Age < {age_cutoff}")
      )
    ) else list(enable = FALSE),
    subgroup_fallback = if (sgfb_enable) list(
      enable = TRUE, try_all = TRUE, min_n_per_subgroup = 30L,
      sep = "|", age_cutoff = age_cutoff, age_mid_lower = 45L,
      obesity_standard = "chinese",
      subgroups = list(
        list(label = "Age_{age_cutoff}",                 expr = "Age >= {age_cutoff}"),
        list(label = "Age_{age_mid_lower}_{age_cutoff}", expr = "Age >= {age_mid_lower} & Age < {age_cutoff}"),
        list(label = "Hypertension",                     expr = 'Hypertension == "Yes"'),
        list(label = "Diabetes",                         expr = 'T2DM == "Yes"'),
        list(label = "Obesity_BMI{obesity_cut}",         expr = "BMI >= {obesity_cut}")
      )
    ) else list(enable = FALSE)
  )
)

# 合并 block 级默认参数 + pipeline（引擎内标准预后 batch 配置）
.template_path <- file.path(.engine, "configs/templates/config_survival_dual_batch.template.R")
if (!file.exists(.template_path))
  stop("引擎模板缺失: ", .template_path, call. = FALSE)

.study_config <- config
._saved_root <- .batch_project_root
._saved_ck   <- .batch_ck_root
._saved_data <- .batch_data_root
source(.template_path, local = TRUE)

# 模板不再内嵌 pipeline_*；从标准定义加载（扩展由 studies 侧 add_block 覆盖）
if (!exists("pipeline_regular_batch", inherits = FALSE) || !exists("pipeline_shared_regular", inherits = FALSE)) {
  .pipe_path <- file.path(.engine, "configs/config_survival_dual_batch.R")
  if (!file.exists(.pipe_path))
    stop("缺少标准 pipeline 定义: ", .pipe_path, call. = FALSE)
  source(.pipe_path, local = TRUE)
}
.batch_project_root <- ._saved_root
.batch_ck_root      <- ._saved_ck
.batch_data_root    <- ._saved_data

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

config$project$output_dir <- .batch_project_root
config$survival_batch$output_base <- .batch_project_root
config$survival_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared")
config$survival_batch$index_ck_base <- file.path(.batch_ck_root, "by_index")
config$dual_db$checkpoint_base <- .batch_ck_root
config$dual_db$harmonization_dir <- file.path(.batch_ck_root, "_global_harmonization")
config$data$rawdata_path <- file.path(.batch_data_root, "eicu", eicu_rdata_file)
config$dual_db$primary$rawdata_path <- file.path(.batch_data_root, "eicu", eicu_rdata_file)
config$dual_db$secondary$rawdata_path <- file.path(.batch_data_root, "mimic", mimic_rdata_file)
config$survival$time_var <- time_var
config$survival$event_var <- event_var

pipeline_shared_regular$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "eICU")

rm(.study_config, .template_path, .study, .engine, .req, .deep_merge,
   "._saved_root", "._saved_ck", "._saved_data",
   list = intersect(
  c("disease_code", "disease", "pmid", "analysis_group", "reference_grp",
    "index_group", "index_vars", "feishu_on", "eicu_obj", "mimic_obj",
    "eicu_rdata_file", "mimic_rdata_file", "id_col", "time_var", "event_var",
    "eicu_map", "mimic_map", "common_model", "harm_m1", "harm_m2", "harm_lock",
    "sens_enable", "sgfb_enable", "age_cutoff", "disease_short", "protocol_id"),
  ls()
))

invisible(NULL)
