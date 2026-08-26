###############################################################################
#  config_cdc_wonder_dobbs.R — CDC WONDER Dobbs CITS
#  文献: Gressler 2025 BMC Public Health
###############################################################################

.batch_project_root <- "Output/CDC_WONDER_Dobbs_CITS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_cdc_wonder_dobbs.RData",
    rawdata_obj    = "CDCWonderDobbs",
    outcome_column = "Ban_state",
    id_column      = "Record_ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "CDC_WONDER_Dobbs_CITS",
    disease_code = "15",
    disease = "Maternal_Infant_Outcomes",
    literature_pmid = "s12889-025-23468-8",
    database = "CDC_WONDER",
    study_type = "ecological",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  cdc_wonder = list(
    date_col = "Birth_month",
    group_col = "Ban_state",
    state_col = "State",
    outcome_cols = c("Nonliving_birth", "Congenital_anomaly", "Maternal_morbidity"),
    primary_outcome = "Congenital_anomaly",
    intervention_date = "2022-11-01",
    sensitivity_cutoffs = c("2022-09-01", "2022-10-01", "2022-11-01"),
    monthly_cache = "Data/smoke/D01_cdc_wonder_monthly_rates.csv",
    rate_per_n = 10000L
  ),
  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = FALSE),
  imputation = list(enable = FALSE),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "15_CDC_WONDER_Dobbs",
    protocol_label = "cdc_wonder_comparative_its",
    project_id = "15_cdc_wonder_23468",
    literature_default = "BMC Public Health 2025 Dobbs CITS natality",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B15"
  )
)

pipeline <- list(
  name = "cdc_wonder_dobbs",
  blocks = c(
    "data_clean", "cdc_wonder_fetch", "cits_aggregate_monthly",
    "cits_model_full", "cits_sensitivity_extended",
    "cits_publication_tables", "cits_plot"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
