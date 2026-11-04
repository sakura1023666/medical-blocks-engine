###############################################################################
#  config_multimorbidity_additive.template.R — 多病叠加单队列模板（Wang 2025）
#  入口: Rscript run/multimorbidity/run_multimorbidity_additive.R --config <本文件副本>
###############################################################################

.batch_project_root <- "Output/Multimorbidity_Depression_AO_Cognition"
.batch_ck_root <- file.path(.batch_project_root, "checkpoints")

config <- list(
  data = list(
    rawdata_path = "Data/smoke/D01_multimorbidity_additive.RData",
    rawdata_obj = "Multimorbidity",
    outcome_column = "Cognition_z",
    id_column = "ID",
    strip_id_columns_after_imputation = character(0)
  ),
  project = list(
    name = "Multimorbidity_Additive",
    disease = "Cognitive_Decline",
    literature_pmid = "04298",
    database = "CHARLS",
    study_type = "incidence",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  multimorbidity = list(
    obesity_indicator = "BMI",
    bmi_col = "BMI",
    wc_col = "WC",
    height_col = "Height",
    weight_col = "Weight",
    bmi_cutoff = 28,
    whtr_cutoff = 0.6,
    depression_score_col = "Depression_Score",
    depression_cutoff = 10,
    depression_binary_col = "Depression",
    obesity_binary_col = "Obesity",
    exposure_a_col = "BMI",
    exposure_b_col = "Depression_Score",
    category_col = "Multimorbidity_cat",
    wave_col = "Followup_wave",
    waves = c(1L, 2L, 3L),
    baseline_wave = 1L,
    outcome_wave = 3L,
    id_col = "ID",
    kml3d_k_candidates = 2:5,
    kml3d_clusters = NULL,
    min_cluster_prop = 0.05,
    trajectory_cluster_col = "trajectory_cluster",
    cognition_raw_col = "Cognition",
    cognition_z_col = "Cognition_z",
    cognition_zscore = list(enable = TRUE),
    graphical_abstract = list(
      # 版式/配色锁定对齐 流程图1配色.ai；文案可改
      cohorts = c("CHARLS (China)", "HRS (USA)"),
      exposure_a = "Obesity (BMI)",
      exposure_b = "Depression",
      outcome = "Cognition z-score",
      joint_label = "Joint trajectories",
      methods = c(
        "Data\ncleaning",
        "Kml3D\nclustering\nalgorithm",
        "Generalized\nEstimating\nEquations"
      ),
      process = c(
        "Main analysis:\nGrouping based on a clustering algorithm:\nBMI & Depression",
        "Secondary analysis:\nGrouping based on Age Group:\nAge < 65 / Age ≥ 65\nGrouping based on a clustering algorithm:\nBMI & Depression",
        "Sensitive analysis:\nRepeated the main analysis:\nExcluded underweight participants\nRandomly excluded 20% of the participants"
      ),
      results = c(
        "Obesity (BMI) & Depression\nHeterogeneous results\nacross cohorts",
        "Depression-related groups:\npoorer cognition\n(see GEE tables)"
      ),
      # 默认 FALSE=flowchart1 锁定色；TRUE 时打乱强调色
      random_colors = FALSE,
      color_seed = NULL
    )
  ),
  multimorbidity_gee = list(
    outcome_col = "Cognition_z",
    cognition_col = "Cognition_z",
    family = "gaussian",
    time_col = "Followup_wave",
    covariates_m1 = character(0),
    covariates_m2 = c("Age", "Gender"),
    covariates_m3 = c("Age", "Gender", "Education", "Hypertension", "Diabetes"),
    stratify_vars = c("Gender", "Age_group"),
    ref_category = "Neither",
    sensitivity_include_ar1 = TRUE
  ),
  data_clean = list(missing_threshold = 0.5),
  column_mapping = list(enable = FALSE),
  imputation = list(
    method = "cart", m = 1L, max_iter = 2L, seed = 42L,
    export_missing_fig = FALSE, export_table_s1 = FALSE, complete_action = 1L
  ),
  plot = list(font_family = "Times New Roman", palette_group = 2L),
  feishu = list(enable = FALSE)
)

pipeline <- list(
  name = "multimorbidity_additive",
  blocks = c(
    "data_clean", "imputation",
    "multimorbidity_define_exposures",
    "multimorbidity_cognition_zscore",
    "multimorbidity_baseline_category",
    "multimorbidity_kml3d_trajectory",
    "multimorbidity_gee_cognition",
    "multimorbidity_gee_trajectory",
    "multimorbidity_sankey_transition",
    "multimorbidity_empirical_transition",
    "multimorbidity_gee_stratified",
    "multimorbidity_gee_interaction",
    "multimorbidity_sensitivity_suite",
    "multimorbidity_graphical_abstract"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
