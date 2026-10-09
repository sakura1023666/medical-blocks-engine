###############################################################################
# config_pa_mobility_cognitive.R — PA–Mobility × 认知衰老（CHARLS 单流水线入口）
# 设计: docs/superpowers/specs/2026-09-20-pa-mobility-cognitive-charls-nhanes-design.md
###############################################################################

.batch_project_root <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.pamob_data_root    <- "G:/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"

config <- list(
  data = list(
    rawdata_path = NULL,
    rawdata_obj = NULL,
    id_column = "ID_h"
  ),
  project = list(
    name = "PA_Mobility_Cognitive_CHARLS_NHANES",
    disease_code = "02",
    disease = "Cognitive_impairment",
    literature_pmid = "pa_mobility_cognitive_framework_v1",
    database = "CHARLS",
    study_type = "longitudinal_triangulation",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  pub_digits = list(est = 3L, p = 3L, desc = 2L, cutoff = 4L),
  pamob = list(
    data_root = .pamob_data_root,
    baseline_wave = 2011L,
    charls_age_min = 45,
    nhanes_cycle = "H",
    nhanes_source_file = "2013-2014",
    nhanes_age_min = 60,
    nhanes_age_max = 75,
    # 正文 DSST：age≥60、不设上限、WTMEC2YR、不要求 NfL
    nhanes_dsst_age_min = 60,
    nhanes_dsst_age_max = Inf,
    # CHARLS Model1–3（方案 §5.8）
    covariates_model1 = c("Age", "Gender"),
    covariates_model2 = c("Age", "Gender", "Education", "Marital_Status", "Residence", "Incometotal"),
    covariates_model3 = c(
      "Age", "Gender", "Education", "Marital_Status", "Residence", "Incometotal",
      "BMI", "Smoke", "Alcohol_drinking",
      "Hypertension", "Diabetes", "Cardiopathy", "Stroke", "CESD10"
    ),
    # NHANES Model1–3（方案 §6.7）
    nhanes_covariates_model1 = c("Age", "Gender", "Race"),
    nhanes_covariates_model2 = c("Age", "Gender", "Race", "Education", "PIR", "Marital_Status"),
    nhanes_covariates_model3 = c(
      "Age", "Gender", "Race", "Education", "PIR", "Marital_Status",
      "BMI", "Smoke", "Alcohol_drinking",
      "Hypertension", "Diabetes", "CHD", "HF", "Stroke", "Depression"
    ),
    pa_met_threshold = 600,
    phenotype_reference = "Active_preserved"
  ),
  pub_figures = list(formats_dir = TRUE, write_image_information = TRUE, dpi = 300L),
  feishu = list(enable = FALSE),
  data_clean = list(missing_threshold = 0.5, skip_outcome_row_filter = TRUE),
  column_mapping = list(enable = FALSE),
  imputation = list(method = "none", m = 1L, seed = 42L, export_missing_fig = FALSE)
)

pipeline <- list(
  name = "pamob_charls_full",
  blocks = c(
    "pamob_feasibility",
    "pamob_assemble_charls", "pamob_cognition_long", "pamob_baseline_charls",
    "pamob_lmm_global", "pamob_lmm_episodic", "pamob_contrast_preset",
    "pamob_traj_plot", "pamob_sensitivity_charls",
    "pamob_flowchart", "pamob_concept_fig1",
    "pamob_assemble_nhanes", "pamob_baseline_nhanes",
    "pamob_svy_dsst", "pamob_svy_nfl", "pamob_panel_fig4",
    "pamob_sensitivity_nhanes", "pamob_pub_export"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
