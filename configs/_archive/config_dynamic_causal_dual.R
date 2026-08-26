###############################################################################
#  config_dynamic_causal_dual.R — 动态因果 CMI 总暴露 × 新发 CVD（CHARLS+ELSA）
#  文献: Li 2025 ajpc 101046
#  决策树: Decisiontree/decision_tree_dynamic_causal_dual.md
#  入口: run/dynamic_causal/run_dynamic_causal_dual.R
###############################################################################

.batch_project_root <- "Output/Dynamic_Causal_CMI_CVD_Dual"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_dynamic_causal_dual.RData",
    rawdata_obj    = "DynamicCausal",
    outcome_column = "CVD_event",
    id_column      = "ID",
    strip_id_columns_after_imputation = c("ID")
  ),

  project = list(
    name = "Dynamic_Causal_CMI_CVD",
    disease_code = "07",
    disease = "CVD",
    literature_pmid = "101046",
    database = "CHARLS+ELSA",
    database_type = "regular",
    study_type = "prognosis",
    classification_mode = "binary",
    analysis_group = "Case",
    reference_group = "Control",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  survival = list(time_var = "futime", event_var = "CVD_event", index_var = "Total_CMI"),

  dynamic_causal = list(
    tg_col = "Triglycerides",
    hdl_col = "HDL",
    wc_col = "Waist_circumference",
    height_col = "Height",
    baseline_suffix = "_baseline", followup_suffix = "_wave2", seed = 42L,
    analysis_type = "change",
    change_sample_frac = 0.62,
    change_subsample_seed = 101046L
  ),

  dynamic_causal_meta = list(cohorts = c("CHARLS", "ELSA"), analysis_tag = "total_cmi"),

  rcs_prognosis = list(
    index_var = "analysis_index",
    nk_range = 3:4,
    pause_enable = FALSE
  ),

  dynamic_causal_cox = list(tertile_var = "Total_CMI_tert", continuous_var = "Total_CMI"),
  cox_tertile = list(index_var = "Total_CMI_tert", pause_enable = FALSE),

  incidence = list(outcome_var = "CVD_event", index_var = "Total_CMI"),
  logistic = list(index_var = "Total_CMI"),

  data_clean = list(missing_threshold = 0.5, drop_columns = NULL,
                    bp_columns = list(sbp = "SBP", dbp = "DBP", pp = "PP")),
  column_mapping = list(enable = FALSE),

  imputation = list(
    missing_col_threshold = 0.5, method = "cart", m = 1L, max_iter = 3L,
    seed = 1234L, complete_action = 1L, export_missing_fig = FALSE
  ),

  baseline_binary = list(sig_cutoff = 0.05, pause_enable = FALSE, early_stop_if_index_ns = FALSE),
  univariate_prognosis = list(sig_cutoff = 0.1, pause_enable = FALSE),
  multivariate_prognosis = list(sig_cutoff = 0.05, pause_enable = FALSE, pause_on_min_sig_vars = FALSE,
                                input_from = "tb1"),
  multicollinearity = list(
    vif_threshold_strict = 4, vif_threshold_loose = 10, min_vars_threshold = 0,
    exclude_vars = c("ID", "Total_CMI", "CMI_baseline", "CMI_wave2", "Delta_CMI"),
    screen = list(csv_name = "VIF_check_screen.csv"),
    final  = list(csv_name = "VIF_check_final.csv")
  ),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "07_CVD_Dynamic_CMI",
    protocol_label = "dynamic_causal_cmi_dual",
    project_id = "07_dynamic_causal_101046",
    literature_default = "CMI dynamic change × incident CVD (CHARLS+ELSA, Li 2025 ajpc 101046)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B12"
  )
)

pipeline <- list(
  name = "dynamic_causal_cmi_dual",
  blocks = c(
    "data_clean", "imputation",
    "dynamic_causal_index_compute",
    "baseline_binary", "univariate_prognosis", "multicollinearity_screen", "multivariate_prognosis", "multicollinearity_final",
    "dynamic_causal_cox_baseline", "dynamic_causal_cox_total",
    "dynamic_causal_rcs_change",
    "dynamic_causal_meta_merge"
  ),
  render_tables_after = c("baseline_binary", "dynamic_causal_cox_total"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
