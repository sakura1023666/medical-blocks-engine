###############################################################################
#  config_survival_iptw_pooled.template.R — 多队列 pooled IPTW-Cox 生存分析（通用模板）
#  source 后得到: config, pipeline
#  用法: run_survival_iptw_pooled.R
#
#  套路来源: paper_004（7 队列 harmonized + IPTW + Cox PH + shared frailty）
#  暴露/结局/时间列均为占位符，须经 wizard 交互确认后回填。
#
#  缺失 block（只登记，待开发后取消注释）:
#    GAP1 cox_binary_iptw_weighted
#    GAP2 cox_effectiveness_3group_iptw
#    GAP3 iptw_balance_multinomial
#    GAP5 e_value_cox
#    GAP6 sensitivity_cox_suite
#    GAP7 stratified_cox_preset
#    GAP8 competing_risk_cox
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/<TO_CONFIRM>/harmonized_cohorts.RData",
    rawdata_obj      = "<TO_CONFIRM>",
    outcome_path     = NULL,
    outcome_column   = "<Outcome_Event>",
    time_column      = "<Time_Since_Baseline>",
    id_column        = "<Subject_ID>",
    cohort_column    = "<Cohort_ID>",
    income_strata_column = "<Income_Strata>",
    strip_id_columns_after_imputation = c("<Subject_ID>", "SEQN", "ID")
  ),

  project = list(
    name                = "<Study_Name_IPTW_Cox>",
    disease             = "<Disease_Label>",
    database            = "<Database_Label>",
    database_type       = "regular",
    study_type          = "prognosis",
    classification_mode = "binary",
    analysis_group      = "<Case_Label>",
    reference_group     = "<Ref_Label>",
    output_dir          = "Output/<Study_Name_IPTW_Cox>",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  survival = list(
    time_var      = "<Time_Since_Baseline>",
    event_var     = "<Outcome_Event>",
    index_var     = "<Exposure_Use>",
    time_unit     = "years",
    time_divisor  = 1
  ),

  logistic = list(
    index_var = "<Exposure_Use>"
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "<Database_Label>"
  ),

  dual_db = list(
    enable = TRUE
  ),

  dual_db_column_harmonize = list(
    enable = TRUE,
    pause_enable = FALSE
  ),

  dual_db_covariate_harmonize = list(
    enable = TRUE,
    pause_enable = FALSE
  ),

  imputation = list(
    missing_col_threshold = 0.4,
    method                = "cart",
    m                     = 5L,
    max_iter              = 5L,
    seed                  = 1234L,
    complete_action       = 1L,
    export_missing_fig    = TRUE,
    export_table_s1       = TRUE
  ),

  baseline_binary = list(
    sig_cutoff            = 0.05,
    strata                = "<Income_Strata>",
    include_vars          = NULL,
    exclude_vars          = c("<Subject_ID>", "<Time_Since_Baseline>", "<Outcome_Event>"),
    pause_enable          = FALSE,
    pause_on_table1_fail  = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_min_sig_vars    = 3L
  ),

  iptw_balance = list(
    enable            = TRUE,
    exposure_var      = "<Exposure_Use_Binary>",
    index_var         = "<Exposure_Use>",
    weight_col        = "weight",
    smd_threshold     = 0.1,
    ps_covariates     = NULL,
    exclude_vars      = character(0),
    include_vars      = NULL,
    pause_enable      = TRUE,
    pause_on_ipw_fail = TRUE
  ),

  iptw_association = list(
    enable       = TRUE,
    table_var    = "<Exposure_Use_Binary>",
    pause_enable = FALSE
  ),

  # TODO(GAP3): iptw_balance_multinomial — 有效性三分 multinomial PS（Table S14）
  # iptw_balance_multinomial = list(
  #   enable = TRUE,
  #   exposure_var = "<Effectiveness_3Group>",
  #   levels = c("no_aid", "good", "poor"),
  #   smd_threshold = 0.1
  # ),

  cox_binary = list(
    gate_enable              = FALSE,
    stop_if_crude_highest_ns = FALSE,
    extend_branch            = character(0),
    degrade_branch           = character(0),
    p_threshold              = 0.05,
    group_var                = "<Exposure_Use_Binary>",
    group_levels             = c("<Ref_Label>", "<Case_Label>"),
    model1_factors           = NULL,
    model2_factors           = NULL,
    covariate_search         = list(enable = FALSE),
    pause_enable             = FALSE,
    pause_on_fit_fail        = TRUE
  ),

  # TODO(GAP1): cox_binary_iptw_weighted — IPTW + shared frailty 主分析（Fig 2）
  # cox_binary_iptw_weighted = list(
  #   enable = TRUE,
  #   exposure_var = "<Exposure_Use_Binary>",
  #   frailty_var = "<Cohort_ID>",
  #   weight_col = "weight",
  #   ph_test_mode = "graphical"
  # ),

  # TODO(GAP2): cox_effectiveness_3group_iptw — 有效性三分比较（Fig 4）
  # cox_effectiveness_3group_iptw = list(
  #   enable = TRUE,
  #   exposure_var = "<Effectiveness_3Group>",
  #   reference_level = "no_aid",
  #   frailty_var = "<Cohort_ID>",
  #   weight_col = "weight"
  # ),

  # TODO(GAP7): stratified_cox_preset — 按收入国分层重复主 Cox
  # stratified_cox_preset = list(
  #   enable = TRUE,
  #   strata_var = "<Income_Strata>",
  #   levels = c("high_income", "middle_income")
  # ),

  cox_interaction = list(
    enable             = TRUE,
    exposure_var       = "<Exposure_Use_Binary>",
    interaction_vars   = c("<Age_Group>", "<Gender>", "<Education>", "<SDI>"),
    test_method        = "likelihood_ratio",
    pause_enable       = FALSE
  ),

  subgroup = list(
    min_n                  = 100,
    age_cutoff             = 70,
    var_source             = "table1_categorical",
    required_subgroup_vars = character(0),
    forbid_subgroup_vars   = c("<Exposure_Use_Binary>", "<Effectiveness_3Group>"),
    forest_xlim            = c(0, 2),
    forest_ticks_at        = c(0, 0.5, 1, 1.5, 2),
    p_adjust               = "bonferroni"
  ),

  subgroup_prognosis = list(
    enable       = TRUE,
    index_var    = "<Exposure_Use>",
    pause_enable = FALSE
  ),

  # TODO(GAP5): e_value_cox
  # e_value_cox = list(enable = TRUE, exposure_var = "<Exposure_Use_Binary>"),

  # TODO(GAP6): sensitivity_cox_suite — SA1 排除前 3 年等
  # sensitivity_cox_suite = list(
  #   enable = TRUE,
  #   scenarios = c("exclude_first_3y", "age_ge_60", "ge_2_followup_waves")
  # ),

  # TODO(GAP8): competing_risk_cox — SA11
  # competing_risk_cox = list(enable = TRUE, competing_var = "<Death_Event>"),

  feature_selection = list(
    enable = FALSE
  )
)

pipeline <- list(
  name   = "survival_iptw_pooled_template",
  blocks = c(
    "data_clean",
    "column_mapping",
    "dual_db_column_harmonize",
    "dual_db_covariate_harmonize",
    "imputation",
    "baseline_binary",
    "iptw_balance",
    "iptw_association",
    # "iptw_balance_multinomial",       # GAP3
    # "cox_binary_iptw_weighted",       # GAP1
    # "stratified_cox_preset",          # GAP7
    # "e_value_cox",                    # GAP5
    "cox_binary",
    # "cox_effectiveness_3group_iptw",  # GAP2
    "cox_interaction",
    "subgroup_prognosis"
    # "sensitivity_cox_suite",          # GAP6
    # "competing_risk_cox"               # GAP8
  ),
  cox_gate = list(
    enable = FALSE
  ),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "iptw_balance", "iptw_association",
    "cox_binary", "cox_interaction", "subgroup_prognosis"
  ),
  render_figures_after = c(
    "cox_interaction", "subgroup_prognosis"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(
    enable = TRUE,
    dir    = "checkpoints/<Study_Name_IPTW_Cox>"
  )
)
