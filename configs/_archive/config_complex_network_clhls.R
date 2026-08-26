###############################################################################
#  config_complex_network_clhls.R — 复杂网络（抑郁×焦虑症状 GGM）
#  文献: Chang 2025 BMC Psychiatry — CLHLS 独居老人
#  决策树: Decisiontree/decision_tree_complex_network_clhls.md
#  入口: run/complex_network/run_complex_network_clhls.R
###############################################################################

.batch_project_root <- "Output/Complex_Network_CLHLS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_complex_network_clhls.RData",
    rawdata_obj    = "NetworkCLHLS",
    outcome_column = "CESD_total",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name = "Complex_Network_CLHLS",
    disease_code = "14",
    disease = "Depression_Anxiety_Network",
    literature_pmid = "06443",
    database = "CLHLS",
    database_type = "regular",
    study_type = "cross_sectional",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  complex_network = list(
    subgroup_col = "Gender",
    symptom_prefixes = c("CESD", "GAD"),
    covariate_cols = c("Age", "Gender", "Living_alone"),
    bootnet_n_boot = 50L,
    ebicglasso_lambda_min_ratio = 0.01
  ),

  data_clean = list(missing_threshold = 0.3),
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
    disease_label = "14_Depression_Anxiety_Network",
    protocol_label = "complex_network_ggm_clhls",
    project_id = "14_complex_network_06443",
    literature_default = "CLHLS GGM depression-anxiety network (Chang 2025 BMC Psychiatry)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B14"
  )
)

pipeline <- list(
  name = "complex_network_clhls",
  blocks = c(
    "data_clean", "imputation",
    "complex_network_descriptive",
    "complex_network_publication_tables",
    "complex_network_bootnet",
    "complex_network_covariate_residual",
    "complex_network_ggm"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
