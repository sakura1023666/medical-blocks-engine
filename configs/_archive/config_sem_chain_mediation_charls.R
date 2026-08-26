###############################################################################
#  config_sem_chain_mediation_charls.R — SEM + 链式中介（CHARLS 肌少症→抑郁→认知→衰弱）
#  文献: Zhu 2025 J Adv Research
#  决策树: Decisiontree/decision_tree_sem_chain_mediation_charls.md
#  入口: run/sem_chain_mediation/run_sem_chain_mediation_charls.R
###############################################################################

.batch_project_root <- "Output/SEM_Chain_Mediation_CHARLS"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path   = "Data/smoke/D01_sem_chain_mediation_charls.RData",
    rawdata_obj    = "SemChainCHARLS",
    outcome_column = "Sex",
    id_column      = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "SEM_Chain_Mediation_CHARLS",
    disease_code = "25",
    disease = "Sarcopenia_Frailty_SEM",
    literature_pmid = "j.jare.2024.12.021",
    database = "CHARLS",
    study_type = "longitudinal",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  sem_chain = list(
    exposure_var = "Sarcopenia",
    m1_var = "Depression",
    m2_var = "Cognitive_score",
    event_var = "Frailty_event",
    time_var = "Frailty_time",
    covariates = c("Age", "Sex", "Education", "BMI", "Smoking", "Drinking"),
    covariate_vars = c("Age", "Sex", "Education", "BMI", "Smoking", "Drinking"),
    mediation_boot_R = 500L,
    literature_tol_pct = 20,
    literature_targets = list(
      depression_frailty_HR = 1.371, cognitive_frailty_HR = 1.514, sarcopenia_frailty_HR = 1.456
    ),
    early_event_cut_years = 1L,
    depression_cutoff = 10L,
    cognitive_items = c("Immediate_recall", "Delayed_recall")
  ),
  data_clean = list(missing_threshold = 0.4, skip_outcome_row_filter = TRUE),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, complete_action = 1L,
                    required_non_na_cols = character(0)),
  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "25_SEM_Chain_Mediation_CHARLS",
    protocol_label = "sem_chain_mediation_sarcopenia_frailty",
    project_id = "25_sem_chain_charls_2025",
    literature_default = "J Adv Research 2025 Zhu SEM chain mediation CHARLS",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B25"
  )
)

pipeline <- list(
  name = "sem_chain_mediation_charls",
  blocks = c(
    "data_clean", "imputation",
    "sem_data_prep", "sem_descriptive", "sem_cox_baseline",
    "sem_path_lavaan", "sem_chain_mediation", "sem_cox_chain_mediation",
    "sem_stratified", "sem_sensitivity", "sem_literature_validate"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
