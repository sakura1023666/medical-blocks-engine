###############################################################################
#  configs/study_interface/ml_dual_batch_pipelines.R
#  ML 双库批量 pipeline 定义（需已设置 .batch_ck_root）
###############################################################################

.primary_slot <- tolower(config$dual_db$primary$name %||% "primary")
.secondary_slot <- tolower(config$dual_db$secondary$name %||% "secondary")

# 预测模型规范：
#   1) 先 train_validation 划分（cross_db 为 passthrough 已有 train/test）
#   2) 再 imputation fit_on=train（MICE 仅用训练估计，ignore 应用到验证）
#   3) 不挂 trim_index_extreme
._ml_head <- c(
  "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
  "train_validation",
  "imputation"
)

._ml_baseline_incidence <- c("baseline_binary", "simple_ROC", "boxplot")
._ml_baseline_nhanes <- c("cutoff", "obj", "baseline_nhanes")

pipeline_shared_nhanes <- list(
  name = paste0("ml_dual_batch_shared_", .primary_slot),
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", .primary_slot))
)

pipeline_shared_regular <- list(
  name = paste0("ml_dual_batch_shared_", .secondary_slot),
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", .secondary_slot))
)

pipeline_nhanes_batch <- list(
  name = "ml_dual_batch_primary_nhanes",
  blocks = c(
    ._ml_head,
    ._ml_baseline_nhanes,
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    ml_dual_primary_ml_tail_blocks(config)
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "imputation", "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multicollinearity_nhanes_final", "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c("ml_feature_selection_bundle", "performance_ml", "shap"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_regular_primary_ml_batch <- list(
  name = "ml_dual_regular_primary",
  blocks = c(
    ._ml_head,
    ._ml_baseline_incidence,
    ml_dual_primary_ml_stat_upstream_blocks(config),
    ml_dual_primary_ml_tail_blocks(config)
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "imputation", "baseline_binary", "simple_ROC", "boxplot",
    "univariate_incidence_binary", "ml_vif_train_test",
    "ml_feature_selection_bundle",
    "ml_assoc_covariate_resolve",
    "ml_assoc_bundle",
    "ml_models_bundle", "performance_ml",
    "shap",
    ml_dual_primary_ml_subgroup_render_blocks(config)
  ),
  render_figures_after = c(
    "ml_feature_selection_bundle",
    "simple_ROC", "boxplot",
    "ml_assoc_bundle",
    "performance_ml", "shap",
    ml_dual_primary_ml_subgroup_render_blocks(config)
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_mimic_ml_batch <- list(
  name = "ml_dual_batch_secondary_ml",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "train_validation",
    "imputation",
    "ml_inherit_primary_features",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap",
    "attrition_flowchart"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "imputation", "ml_inherit_primary_features",
    "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c("performance_ml", "shap"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_regular_primary_ml_batch

rm(.primary_slot, .secondary_slot, ._ml_head, ._ml_baseline_incidence, ._ml_baseline_nhanes)
