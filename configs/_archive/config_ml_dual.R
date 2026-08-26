###############################################################################
#  config_ml_dual.R — 机器学习双库（NHANES 主库 VIF 分步 + MIMIC 验证库仅 ML）
#
#  主库 NHANES（参考发病双库）:
#    univariate_nhanes → multicollinearity_nhanes_screen → multivariate_nhanes
#    → multicollinearity_nhanes_final → ml_feature_selection_bundle → ML 下游
#
#  验证库 MIMIC（primary_full_secondary_ml）:
#    data_clean → column_mapping → dual_db_column_harmonize → imputation
#    → ml_inherit_primary_features → ML 下游
#
#  数据: 02旋旋/Data/{nhanes,mimic}/D04_dabiao.RData
#  运行: Rscript run/ml/run_ml_dual.R --db both
#        Rscript run/ml/run_ml_dual.R --config configs/config_ml_dual.R --db nhanes
###############################################################################

root_guess <- normalizePath(getwd(), winslash = "/")
cfg11 <- file.path(root_guess, "configs/psoriasis/config11.R")
if (!file.exists(cfg11)) stop("缺少 configs/psoriasis/config11.R", call. = FALSE)
source(cfg11)
source(file.path(root_guess, "configs/ml_dual_shared_overrides.R"))

config <- ml_dual_apply_feature_selection_overrides(config)
config <- ml_dual_apply_ml_models_overrides(config)
config <- ml_dual_apply_nhanes_upstream_overrides(config)
config$data$rawdata_path   <- "02旋旋/Data/nhanes/D04_dabiao.RData"
config$data$rawdata_obj    <- "dabiao"
config$data$outcome_column <- "Disease"
config$data$id_column      <- "SEQN"

config$project$name         <- "Psoriasis ML Dual (ALBI/RAR/SII)"
config$project$disease      <- "Psoriasis"
config$project$study_type   <- "incidence"   # VIF 分步块要求 incidence；ML 下游仍正常
config$project$database     <- "NHANES"
config$project$database_type <- "nhanes"
config$project$output_dir   <- "Output/Psoriasis_ML_dual"

# 指标模式:
#   index_mode = "multi_combined" — ALBI/RAR/SII 合并为一次 ML（默认）
#   index_mode = "single"         — 仅跑 index_vars 中第一个
config$prediction$index_mode <- "multi_combined"
config$prediction$multi_top_n <- 3L
config$prediction$index_vars <- c("ALBI", "RAR", "SII")
config$incidence$index_var   <- config$prediction$index_vars
config$logistic$index_var    <- config$prediction$index_vars
config$nhanes$cutoff_index_var <- config$prediction$index_vars
config$feature_selection$composite_features <- config$prediction$index_vars
config$feature_selection$enable <- TRUE
config$feature_selection$target_n_features_min <- 3L
config$feature_selection$pause_enable <- FALSE
for (.fs_blk in c(
  "feature_selection_lasso", "feature_selection_boruta", "feature_selection_bayesian",
  "feature_selection_random_forest", "feature_selection_bagged_trees",
  "feature_selection_lvq", "feature_selection_consensus"
)) {
  config[[.fs_blk]] <- modifyList(
    config[[.fs_blk]] %||% list(),
    list(pause_enable = FALSE, pause_on_insufficient_candidates = FALSE)
  )
}
config$ml_aggregate <- modifyList(
  config$ml_aggregate %||% list(),
  list(pause_enable = FALSE, pause_on_no_models = FALSE)
)
config$train_validation$enable <- TRUE
config$performance_ml$enable <- TRUE
config$supplementary_ml$enable <- TRUE
config$shap$enable <- TRUE

config$ml_feature_selection_bundle <- list(
  enable = TRUE,
  export_for_secondary = TRUE
)
config$ml_inherit_primary_features <- list(enable = TRUE)

config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  workflow = "primary_full_secondary_ml",
  checkpoint_base = "checkpoints/Psoriasis_ML_dual",
  harmonization_dir = "checkpoints/Psoriasis_ML_dual/harmonization",
  current_db = NULL,
  primary = list(
    name = "NHANES",
    db_type = "nhanes",
    rawdata_path = "02旋旋/Data/nhanes/D04_dabiao.RData",
    rawdata_obj = "dabiao",
    id_column = "SEQN",
    column_mapping_type = "NHANES"
  ),
  secondary = list(
    name = "MIMIC",
    db_type = "regular",
    rawdata_path = "02旋旋/Data/mimic/D04_dabiao.RData",
    rawdata_obj = "dabiao_mimic",
    id_column = "SEQN",
    column_mapping_type = "MIMIC"
  ),
  harmonization = list(
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    covariate_source = "vif_screen",
    sync_after_vif_final = FALSE,
    sync_logistic_branch = FALSE
  )
)

config$column_mapping$database_type <- "NHANES"

config$univariate_nhanes <- modifyList(
  config$univariate_nhanes %||% list(),
  list(
    sig_cutoff = 0.05,
    screening_cutoff = 0.1,
    pause_enable = FALSE
  )
)

config$multivariate_nhanes <- modifyList(
  config$multivariate_nhanes %||% list(),
  list(
    sig_cutoff = 0.05,
    input_from = "vif_screen_pass",
    pause_enable = FALSE
  )
)

config$multivariate_covariate_resolve <- list(
  enable = TRUE,
  fallback_from = "vif_screen_pass"
)

config$baseline_nhanes <- modifyList(
  config$baseline_nhanes %||% list(),
  list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_weighted_table_fail = FALSE,
    pause_on_min_sig_vars = FALSE
  )
)

config$multicollinearity <- modifyList(
  config$multicollinearity %||% list(),
  list(
    vif_threshold_strict = 4,
    vif_threshold_loose = 10,
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name = "VIF_check_final_weighted.csv"
    )
  )
)

config$multi_db <- NULL

pipeline_nhanes <- list(
  name = "psoriasis_ml_dual_nhanes",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "imputation",
    "cutoff", "obj", "baseline_nhanes",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "imputation", "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "train_validation", "ml_feature_selection_bundle", "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c(
    "imputation", "ml_feature_selection_bundle", "performance_ml", "shap"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = "checkpoints/Psoriasis_ML_dual/nhanes")
)

pipeline_mimic_ml <- list(
  name = "psoriasis_ml_dual_mimic_secondary",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "imputation",
    "ml_inherit_primary_features",
    "train_validation", "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "imputation", "ml_inherit_primary_features",
    "train_validation", "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c("performance_ml", "shap"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = "checkpoints/Psoriasis_ML_dual/mimic")
)

pipeline <- pipeline_nhanes
