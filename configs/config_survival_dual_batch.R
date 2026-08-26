###############################################################################
#  configs/config_survival_dual_batch.R
#  预后双库批量 — 标准 pipeline_shared_regular / pipeline_regular_batch 定义
#  供模板注释指引与 survival_dual_batch_build.R 加载；扩展请用 add_block.sh
###############################################################################

# pipeline_shared_regular / pipeline_regular_batch（与 baseline_pipelines.json survival 一致）

pipeline_shared_regular <- list(
  name   = "survival_dual_batch_shared",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after  = character(0),
  render_figures_after = character(0),
  dual_db    = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_regular_batch <- list(
  name = "survival_dual_batch_regular",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    # 本套路不修剪指标极端值（不挂 trim_index_extreme）
    "imputation",
    "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize",
    # Gate B 后：锁定双库统一协变量再出一份多因素表（Table S7）
    "multivariate_prognosis_harmonized",
    "cox_quartile", "cox_tertile", "cox_binary",
    "rcs_prognosis", "km_strata",
    "segmented_cox_quartile", "segmented_cox_tertile",
    "km_binary", "segmented_cox_binary",
    "subgroup_prognosis"
  ),
  # 注：2026-08-21 起分段 Cox 统一走 segmented_cox_binary（切点=RCS primary cutoff），
  # cox_gate 在全部分支跳过 segmented_cox_quartile/tertile；块名保留以兼容旧检查点。
  # 已停产 plot_cutoff（maxstat Figure S1）。
  cox_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation", "baseline_binary",
    "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
    "dual_db_covariate_harmonize", "multivariate_prognosis_harmonized",
    "cox_quartile", "cox_tertile", "cox_binary",
    "segmented_cox_quartile", "segmented_cox_binary", "subgroup_prognosis"
  ),
  render_figures_after = c(
    "rcs_prognosis", "km_strata", "km_binary", "subgroup_prognosis"
  ),
  dual_db    = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_regular_batch
