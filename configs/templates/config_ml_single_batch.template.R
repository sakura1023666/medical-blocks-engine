###############################################################################
#  config_ml_single_batch.template.R — 单库发病/预测 ML 批量模板
#
#  复制到产出目录:
#    //192.168.68.133/02block_result/{疾病}_{病}/ml_{PMID}_single_{DB}/config.R
#
#  与双库模板共用 ml_dual_batch_build；.study$single_db=TRUE 时：
#    - 只跑 primary（worker --db nhanes；槽位名仍叫 nhanes，不是真 NHANES）
#    - 跳过 Gate A
#    - 发表图/表文件名与表题不加 -库名（Table 1. … / Figure 2. …）
#    - 指标根写 summary_results/（交付白名单：Figures/Tables/Methods md/
#      Methods_software_versions.txt/*中期*.pdf；见 R/ml_index_summary_results.R）
#    - 课题根不再另写 summary_result/（避免双份）
#    - 插补默认 m=5 + rubin_pool（logistic 走 mi_glm_binomial）
#
#  运行:
#    Rscript run/ml/run_ml_dual_batch.R --config "<config.R>" --shared-only --db nhanes
#    Rscript run/ml/run_ml_dual_batch.R --config "<config.R>" --only-index HHR --db nhanes --workers 1
###############################################################################

.study <- list(
  disease_code    = "{disease_code}",
  disease         = "{disease}",
  literature_pmid = "{PMID}",
  analysis_group  = "{Case}",
  reference_group = "{Control}",

  single_db = TRUE,
  mode = "single",
  write_index_summary_results = TRUE,

  index_group = "dual_safe",
  index_vars = c("HHR"),

  outcome_column = "Disease_Group",
  id_column      = "ID",

  primary_name           = "CHARLS",
  primary_db_type        = "regular",
  primary_subdir         = "charls",
  primary_rdata_file     = "D04_dabiao.RData",
  primary_rdata_obj      = "dabiao",
  primary_column_mapping = "CHARLS",

  ## 单库可省略次库文件；占位即可
  secondary_name           = "UNUSED",
  secondary_db_type        = "regular",
  secondary_subdir         = "charls",
  secondary_rdata_file     = "D04_dabiao.RData",
  secondary_rdata_obj      = "dabiao",
  secondary_column_mapping = "CHARLS",

  merge_dual_db_tables       = FALSE,
  mirror_aggregate_prefix_db = FALSE,
  apply_nhanes_upstream      = FALSE,
  split_mode = "per_db_internal",

  disease_config_preset = "psoriasis",
  feishu_enable         = FALSE
)
