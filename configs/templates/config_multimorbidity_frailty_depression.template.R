###############################################################################
#  config_multimorbidity_frailty_depression.template.R — hrs 示例：Frailty×抑郁→肌少症
#  方法壳同 Wang 2025；变量对齐 hrs/analysis_config.R
###############################################################################

.batch_project_root <- "Output/Multimorbidity_Frailty_Depression_Sarcopenia"
.batch_ck_root <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path = "hrs/Step01_RawData/D01_AfterMI_Data_HRS.RData",
    rawdata_obj = "data_imp",
    outcome_column = "Sarcopenia",
    id_column = "ID"
  ),
  project = list(
    name = "Multimorbidity_Frailty_Depression",
    disease = "Sarcopenia",
    database = "HRS",
    study_type = "incidence",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step"
  ),
  multimorbidity = list(
    # 用 frailty 连续分充当 exposure_a；二分 frailty>=0.25
    obesity_indicator = "BMI",
    bmi_col = "Frailty_Score",
    bmi_cutoff = 0.25,
    depression_score_col = "Depression_Score",
    depression_cutoff = 3,
    depression_binary_col = "Depression",
    obesity_binary_col = "Frailty",
    exposure_a_col = "Frailty_Score",
    exposure_b_col = "Depression_Score",
    category_col = "Multimorbidity_cat",
    wave_col = "Followup_wave",
    waves = c(8L, 10L, 12L),
    baseline_wave = 8L,
    outcome_wave = 12L,
    cognition_zscore = list(enable = FALSE),
    graphical_abstract = list(
      cohorts = "HRS (USA)",
      exposure_a = "Frailty",
      exposure_b = "Depression",
      outcome = "Sarcopenia",
      joint_label = "Joint trajectories",
      process = c(
        "Main analysis:\nGrouping based on a clustering algorithm:\nFrailty & Depression",
        "Secondary analysis:\nAge strata / empirical transition",
        "Sensitive analysis:\nJackknife 80%; exclude incomplete cases"
      ),
      results = c(
        "Frailty & Depression\ntrajectories vs sarcopenia",
        "See GEE OR tables"
      ),
      random_colors = FALSE
    )
  ),
  multimorbidity_gee = list(
    outcome_col = "Sarcopenia",
    family = "binomial",
    time_col = "Followup_wave",
    covariates_m2 = c("Age", "Gender"),
    covariates_m3 = c("Age", "Gender", "Education"),
    stratify_vars = c("Gender", "Age_group"),
    ref_category = "Neither"
  ),
  data_clean = list(missing_threshold = 0.5),
  imputation = list(method = "cart", m = 1L, max_iter = 2L, seed = 42L,
                    export_missing_fig = FALSE, export_table_s1 = FALSE),
  feishu = list(enable = FALSE)
)

pipeline <- list(
  name = "multimorbidity_frailty_depression",
  blocks = c(
    "data_clean", "imputation",
    "multimorbidity_define_exposures",
    "multimorbidity_baseline_category",
    "multimorbidity_kml3d_trajectory",
    "multimorbidity_gee_cognition",
    "multimorbidity_gee_trajectory",
    "multimorbidity_gee_stratified",
    "multimorbidity_sensitivity_suite",
    "multimorbidity_graphical_abstract"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
