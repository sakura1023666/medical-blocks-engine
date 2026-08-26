###############################################################################
#  config_medication_regimen_text_soft.R — TEXT/SOFT STEPP 用药方案
#  文献: Pagani 2020 J Clin Oncol
#  决策树: Decisiontree/decision_tree_medication_regimen_text_soft.md
###############################################################################

.batch_project_root <- "Output/Medication_Regimen_TEXT_SOFT"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_medication_regimen_text_soft.RData",
    rawdata_obj    = "MedicationTEXTSOFT",
    outcome_column = "Treatment",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Medication_Regimen_TEXT_SOFT",
    disease_code = "30",
    disease = "Breast_Cancer_Endocrine",
    analysis_group = "1",
    reference_group = "0",
    literature_pmid = "JCO-19-00934",
    database = "TEXT_SOFT",
    study_type = "prognosis",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  survival = list(
    time_var = "futime",
    event_var = "distant_recurrence",
    event_value = 1L,
    index_var = "composite_risk"
  ),
  medication_regimen = list(
    treatment_var = "Treatment",
    chemo_var = "Chemotherapy",
    trial_var = "Trial",
    time_var = "futime",
    event_var = "distant_recurrence",
    eval_time_months = 96L,
    composite_covars = c("Age", "Nodal_status", "Tumor_size", "Grade", "ER_pct", "PR_pct", "Ki67")
  ),
  stepp_prognosis = list(
    index_var = "composite_risk",
    eval_time_months = 96L,
    y_axis_label = "8-Year Freedom From Distant Recurrence (%)",
    x_axis_label = "Composite Risk (Subpopulation Median)",
    hist_x_label = "Composite Risk",
    pause_enable = FALSE,
    overall = list(window_size = 40L, step_size = 8L, panel_title = "A", panel_hist_title = "B"),
    by_group = list(
      stratum_var = "Treatment",
      stratum_levels = c("Tamoxifen", "Tamoxifen_OFS", "Exemestane_OFS"),
      stratum_colors = list(Tamoxifen = "#E41A1C", Tamoxifen_OFS = "#377EB8", Exemestane_OFS = "#4DAF4A"),
      window_size = 20L, step_size = 5L, panel_title = "C", panel_hist_title = "D"
    )
  ),
  data_clean = list(missing_threshold = 0.5),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, complete_action = 1L,
                    exclude_from_mice_cols = c("distant_recurrence", "futime", "Treatment", "Chemotherapy", "Trial")),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "30_Breast_Endocrine_STEPP",
    protocol_label = "medication_regimen_text_soft_stepp",
    project_id = "30_medication_regimen_jco19",
    literature_default = "J Clin Oncol 2020 TEXT/SOFT STEPP endocrine therapy",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B30"
  )
)

pipeline <- list(
  name = "medication_regimen_text_soft",
  blocks = c(
    "data_clean", "imputation",
    "medication_composite_risk", "medication_descriptive",
    "medication_km_treatment", "medication_chemo_strata",
    "medication_trial_comparisons", "medication_stepp_strata",
    "medication_literature_targets",
    "stepp_prognosis"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
