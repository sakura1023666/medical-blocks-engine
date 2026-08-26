###############################################################################
#  config_environment_cd_osteo_nhanes.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_environment_cd_osteo_nhanes.R
###############################################################################

###############################################################################
#  config_environment_cd_osteo_nhanes.R — 单环境毒物（血镉×骨质疏松，NHANES）
#  文献: Li 2025 ecoenv 118502 / 镉暴露骨质疏松
#  决策树: Decisiontree/decision_tree_environment_cd_osteo_nhanes.md
#  入口: run/environment/run_environment_cd_osteo_nhanes.R
###############################################################################

.batch_project_root <- "Output/Environment_Cd_Osteoporosis_NHANES"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path     = "Data/smoke/D01_environment_cd_osteo_nhanes.RData",
    rawdata_obj      = "EnvCd",
    outcome_column   = "Group",
    id_column        = "SEQN",
    strip_id_columns_after_imputation = c("SEQN")
  ),

  project = list(
    name                = "Cd_Osteoporosis_NHANES",
    disease_code        = "06",
    disease             = "Osteoporosis",
    disease_cn          = "骨质疏松",
    literature_pmid     = "118502",
    database            = "NHANES",
    database_type       = "NHANES",
    study_type          = "environment",
    classification_mode = "binary",
    analysis_group      = "Osteoporosis",
    reference_group     = "No_Osteoporosis",
    output_dir          = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root   = TRUE
  ),

  environment_single = list(
    exposure_col = "Blood_Cadmium",
    log_col      = "log10_Blood_Cadmium",
    quartile_col = "log10_Blood_Cadmium_Q"
  ),

  incidence = list(outcome_var = "Group", index_var = "log10_Blood_Cadmium"),
  logistic  = list(index_var = "log10_Blood_Cadmium"),

  nhanes = list(
    survey_weight  = "new_Weight",
    survey_cluster = "SDMVPSU",
    survey_strata  = "SDMVSTRA",
    cutoff_index_var = "log10_Blood_Cadmium",
    auto_new_weight  = TRUE,
    exclude_cols = c("ID", "SEQN", "new_Weight", "WTMEC2YR", "SDMVPSU", "SDMVSTRA", "Source_File")
  ),

  prediction = list(index_vars = c("log10_Blood_Cadmium"), keep_index_vars_in_regression_table = TRUE),
  plot = list(font_family = "Times New Roman"),

  data_clean = list(missing_threshold = 0.4, age_filter = NULL, drop_columns = NULL,
                    bp_columns = list(sbp = "SBP", dbp = "DBP", pp = "PP")),
  column_mapping = list(enable = TRUE, database_type = "NHANES"),

  imputation = list(
    missing_col_threshold = 0.3, method = "cart", m = 2L, max_iter = 3L,
    seed = 1234L, complete_action = 1L, export_missing_fig = FALSE, export_table_s1 = FALSE
  ),

  baseline_nhanes = list(sig_cutoff = 0.05, pause_enable = FALSE, pause_on_min_sig_vars = FALSE,
                         early_stop_if_index_ns = FALSE),
  univariate_nhanes = list(sig_cutoff = 0.05, screening_cutoff = 0.2, pause_enable = FALSE, pause_on_min_sig_vars = FALSE),
  multivariate_nhanes = list(
    sig_cutoff = 0.2, input_from = "vif_screen_pass",
    demo_keywords = c("Age", "Gender", "Race"),
    model1_candidate_names = c("Age", "Gender", "Race", "Smoking", "BMI"),
    pause_enable = FALSE, pause_on_min_sig_vars = FALSE
  ),

  logistic_nhanes_weighted = list(
    covariate_source = "vif_final_pass",
    demo_factor_names = c("Age", "Gender", "Race"),
    clinical_factor_names = c("BMI", "Smoking", "Diabetes", "Hypertension"),
    exclude_from_models = c("ID", "SEQN", "Blood_Cadmium", "log10_Blood_Cadmium"),
    random_search = list(enable = FALSE),
    pause_enable = FALSE
  ),

  multicollinearity = list(
    vif_threshold_strict = 4, vif_threshold_loose = 10, vif_threshold_hard_drop = 50,
    min_vars_threshold = 0,
    exclude_vars = c("ID", "SEQN", "Blood_Cadmium", "log10_Blood_Cadmium"),
    export_full_vif_table = TRUE,
    allow_empty_tb2_final = TRUE,
    screen = list(csv_name = "VIF_check_screen_weighted.csv"),
    final  = list(csv_name = "VIF_check_final_weighted.csv")
  ),

  logistic_quartile_nhanes_weighted = list(
    index_var = "log10_Blood_Cadmium", gate_enable = FALSE, pause_enable = FALSE,
    include_continuous_row = TRUE, p_threshold = 0.05,
    model1_factors = c("Age", "Gender", "Race"),
    model2_factors = c("Age", "Gender", "Race", "BMI", "Smoking")
  ),

  rcs_nhanes = list(index_var = "log10_Blood_Cadmium", knots = 3L, pause_enable = FALSE),
  subgroup_nhanes_weighted = list(index_var = "log10_Blood_Cadmium", pause_enable = FALSE),
  mediation_nhanes_weighted = list(
    index_var = "log10_Blood_Cadmium",
    mediators = c("CRP", "Albumin"),
    sims = 100L, pause_enable = FALSE, allow_empty_results = TRUE
  ),

  cutoff = list(pause_enable = FALSE),

  environment_omics = list(
    network_genes = c("FOXO3", "CCND1", "MAP1LC3B", "HMOX1", "MT1G"),
    gene_expr_path = "Data/smoke/D02_env_cd_gene_expr.csv",
    scrna_path = "Data/smoke/D02_env_cd_scrna.csv",
    gsea_rank_path = "Data/smoke/D02_env_cd_gsea_rank.csv"
  ),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "06_Osteoporosis_Cd",
    protocol_label = "environment_cd_osteo_nhanes",
    project_id = "06_environment_cd_118502",
    literature_default = "Cd exposure × Osteoporosis (NHANES, Li 2025 ecoenv 118502)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B08"
  )
)

  pipeline <- list(
  name = "environment_cd_osteo_nhanes",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "environment_single_exposure_transform",
    "cutoff", "obj", "baseline_nhanes",
    "univariate_nhanes", "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "logistic_quartile_nhanes_weighted", "rcs_nhanes",
    "subgroup_nhanes_weighted", "mediation_nhanes_weighted",
    "env_network_toxicology", "env_ml_gene_screen", "env_scrna_summary",
    "env_gsea", "env_mr_docking"
  ),
  render_tables_after = c("baseline_nhanes", "logistic_quartile_nhanes_weighted", "mediation_nhanes_weighted"),
  render_figures_after = c("rcs_nhanes"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
