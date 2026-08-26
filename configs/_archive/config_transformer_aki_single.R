###############################################################################
#  config_transformer_aki_single.R — 单库短序列 Transformer CSA-AKI 预测
#  文献: Zhong 2025 Lancet Digit Health — REACT causal deep learning
###############################################################################

.batch_project_root <- "Output/Transformer_AKI_Single"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_transformer_aki_single.RData",
    rawdata_obj    = "TransformerAKI",
    outcome_column = "CSA_AKI",
    id_column      = "Patient_ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Transformer_AKI_Single",
    disease_code = "17",
    disease = "CSA_AKI_Transformer",
    literature_pmid = "10.1016/j.landig.2025.100901",
    database = "Single_Center_EHR",
    study_type = "prediction_ml",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/"),
    analysis_group = "CSA_AKI",
    reference_group = "No_AKI"
  ),
  transformer_aki = list(
    id_col = "Patient_ID", time_col = "Hour", label_col = "label",
    center_col = "Center",
    feature_cols = c("Heart_rate", "MAP", "Creatinine", "Urine_output", "Lactate", "Hemoglobin"),
    horizon_hours = 48L, seq_len = 24L, n_folds = 3L, seed = 42L,
    literature_tol_pct = 8,
    literature_targets = list(auroc_internal = 0.93, auroc_external = 0.92, early_hours = 16.35)
  ),
  data_clean = list(missing_threshold = 0.2, skip_outcome_row_filter = TRUE),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, complete_action = 1L),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "17_Transformer_AKI_Single",
    protocol_label = "transformer_shortseq_csa_aki",
    project_id = "17_transformer_aki_2025",
    literature_default = "Lancet Digit Health 2025 REACT CSA-AKI",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B17"
  )
)

pipeline <- list(
  name = "transformer_aki_single",
  blocks = c(
    "data_clean", "imputation",
    "trf_data_prep", "trf_causal_discovery", "trf_train_eval",
    "trf_calibration", "trf_early_detection",
    "trf_multicenter_val", "trf_external_val", "trf_sensitivity", "trf_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
