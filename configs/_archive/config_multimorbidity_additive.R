###############################################################################
#  config_multimorbidity_additive.R — 多病叠加（抑郁×腹型肥胖→认知）
#  文献: Wang 2025 BMC Med 04298
#  决策树: Decisiontree/decision_tree_multimorbidity_additive.md
#  入口: run/multimorbidity/run_multimorbidity_additive.R
###############################################################################

.batch_project_root <- "Output/Multimorbidity_Depression_AO_Cognition"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_multimorbidity_additive.RData",
    rawdata_obj    = "Multimorbidity",
    outcome_column = "Cognition_z",
    id_column      = "row_id",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Multimorbidity_Additive",
    disease_code = "08",
    disease = "Cognitive_Decline",
    literature_pmid = "04298",
    database = "CHARLS+ELSA+HRS+MHAS",
    database_type = "regular",
    study_type = "incidence",
    classification_mode = "binary",
    analysis_group = "Case",
    reference_group = "Control",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  multimorbidity_gee = list(
    cognition_col = "Cognition_z",
    time_col = "Followup_wave",
    stratify_vars = c("Gender", "Age_group")
  ),

  multimorbidity = list(
    depression_col = "Depression",
    obesity_col = "Abdominal_obesity",
    depression_cutoff = 1L,
    obesity_cutoff = 1L,
    category_col = "Multimorbidity_cat",
    kml3d_clusters = 4L
  ),

  data_clean = list(missing_threshold = 0.5,
                    bp_columns = list(sbp = character(0), dbp = character(0), pp = character(0))),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, export_table_s1 = FALSE,
                    complete_action = 1L),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "08_Cognition_Multimorbidity",
    protocol_label = "multimorbidity_additive_gee",
    project_id = "08_multimorbidity_04298",
    literature_default = "Depression+AO additive × cognition (Wang 2025 BMC Med 04298)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B09"
  )
)

pipeline <- list(
  name = "multimorbidity_additive",
  blocks = c(
    "data_clean", "imputation",
    "multimorbidity_baseline_category",
    "multimorbidity_kml3d_trajectory",
    "multimorbidity_gee_cognition",
    "multimorbidity_gee_stratified",
    "multimorbidity_gee_interaction",
    "multimorbidity_sensitivity_suite"
  ),
  render_tables_after = c("multimorbidity_baseline_category", "multimorbidity_gee_cognition"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
