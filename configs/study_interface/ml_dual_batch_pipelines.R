###############################################################################
#  configs/study_interface/ml_dual_batch_pipelines.R
#  ML 双库批量 pipeline 定义（需已设置 .batch_ck_root）
###############################################################################

.primary_slot <- tolower(config$dual_db$primary$name %||% "primary")
.secondary_slot <- tolower(config$dual_db$secondary$name %||% "secondary")

# 预测模型规范：
#   1) 先 train_validation 划分（cross_db 为 passthrough 已有 train/test）
#   2) 再 imputation fit_on=train（MICE 仅用训练估计，ignore 应用到验证）
#   3) index 后硬排除疾病变量 + 当前指标组成变量（Albumin/AnionGap 等）
#   4) 不挂 trim_index_extreme（极端值由 extreme_to_na 置空，不删人）
._ml_head <- c(
  "ml_id_deduplicate", "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
  "analysis_exclusion",
  "train_validation",
  "imputation"
)

._ml_baseline_incidence <- c("baseline_binary", "simple_ROC", "boxplot")
._ml_baseline_nhanes <- c("cutoff", "obj", "baseline_nhanes")

pipeline_shared_nhanes <- list(
  name = paste0("ml_dual_batch_shared_", .primary_slot),
  blocks = c("ml_id_deduplicate", "data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", .primary_slot))
)

pipeline_shared_regular <- list(
  name = paste0("ml_dual_batch_shared_", .secondary_slot),
  blocks = c("ml_id_deduplicate", "data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
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
  logistic_gate = list(enable = TRUE),
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
    ._ml_head,
    ._ml_baseline_incidence,
    ml_dual_secondary_ml_symmetric_blocks(config)
  ),
  logistic_gate = list(enable = FALSE),
  # 外验不跑 UV/VIF/FS；特征来自主库 inherit
  # ml_eval_external / 自训尾由 split_mode 的 enable 开关二选一
  render_tables_after = c(
    "train_validation", "imputation", "baseline_binary", "simple_ROC", "boxplot",
    "ml_inherit_primary_features",
    "ml_assoc_covariate_resolve", "ml_assoc_bundle",
    "ml_eval_external", "ml_models_bundle", "performance_ml",
    ml_dual_primary_ml_subgroup_render_blocks(config)
  ),
  render_figures_after = c(
    "simple_ROC", "boxplot",
    "ml_assoc_bundle",
    "performance_ml", "shap",
    ml_dual_primary_ml_subgroup_render_blocks(config)
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_regular_primary_ml_batch

rm(.primary_slot, .secondary_slot, ._ml_head, ._ml_baseline_incidence, ._ml_baseline_nhanes)
