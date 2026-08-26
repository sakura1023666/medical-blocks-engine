###############################################################################
#  config_multimodal_tbi.R — 多模态融合（临床+组学→TBI 手术/输血）
#  文献: Deng 2025 npj Digital Med 02072-5
#  决策树: Decisiontree/decision_tree_multimodal_tbi.md
#  入口: run/multimodal/run_multimodal_tbi.R
###############################################################################

.batch_project_root <- "Output/Multimodal_TBI_Surgery_Transfusion"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_multimodal_tbi.RData",
    rawdata_obj    = "MultimodalTBI",
    outcome_column = "Outcome",
    id_column      = "ID",
    strip_id_columns_after_imputation = c("ID")
  ),

  project = list(
    name = "Multimodal_TBI",
    disease_code = "09",
    disease = "TBI",
    literature_pmid = "02072",
    database = "Clinical+Omics",
    database_type = "regular",
    study_type = "multimodal",
    classification_mode = "binary",
    analysis_group = "Case",
    reference_group = "Control",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  multimodal = list(
    clinical_vars = c("Age", "Gender", "GCS", "SBP"),
    omics_vars = NULL,
    outcome_positive = 1L,
    seed = 2025L,
    min_variance = 1e-4
  ),

  data_clean = list(missing_threshold = 0.5,
                    bp_columns = list(sbp = character(0), dbp = character(0), pp = character(0))),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 99L, export_missing_fig = FALSE),

  train_validation = list(enable = FALSE),
  performance_ml = list(enable = FALSE),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "09_TBI_Multimodal",
    protocol_label = "multimodal_early_fusion",
    project_id = "09_multimodal_02072",
    literature_default = "Multiomics TBI surgery/transfusion (Deng 2025 npj Digital Med)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B23"
  )
)

pipeline <- list(
  name = "multimodal_tbi_fusion",
  blocks = c(
    "data_clean", "imputation",
    "multimodal_omics_preprocess",
    "multimodal_early_fusion",
    "multimodal_dl_shap"
  ),
  render_tables_after = c("multimodal_early_fusion"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
