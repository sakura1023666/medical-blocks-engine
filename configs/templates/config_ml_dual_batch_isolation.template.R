###############################################################################
#  config_ml_dual_batch_isolation.template.R — ML 双库发病（隔离模式）
#
#  5006 / 2202 程序员接口：产出写在本研究文件夹（dirname(--config)）。
#  参考图/表角色：02block_result/40_Cataract/ml_40395549/by_index/【success】WWI
#    Fig1 纳排 · Fig2 LASSO · Fig3–6 ROC/校准/指标/DCA（训/内验/外验）
#    Fig7 SHAP · Fig8 亚组；Table1–5 + S1–S13 同类角色
#
#  复制 studies/_template_ml/ 后改 <TO_CONFIRM*>；勿改 build 内 pipeline 顺序。
#  入口: run/ml/run_ml_dual_batch.R
#  决策树: Decisiontree/decision_tree_ml_dual_batch.md
#
#  CLI:
#    run_study.bat <研究名> --routine ml --shared-only
#    run_study.bat <研究名> --routine ml --workers 4 --only-index WWI
#
#  收口铁律：成功指标自动写 by_index/【success】*/summary_results/
#    仅留 Figures/ Tables/ Methods_statistical_analysis.md
#           Methods_software_versions.txt / *中期*.pdf
###############################################################################

.study <- list(
  disease_code    = "<TO_CONFIRM_CODE>",       # ❓ 40
  disease         = "<TO_CONFIRM_DISEASE>",    # ❓ Cataract
  literature_pmid = "<TO_CONFIRM_PMID>",      # ❓
  analysis_group  = "<TO_CONFIRM_CASE>",      # ❓ Cataract
  reference_group = "<TO_CONFIRM_CTRL>",      # ❓ Non-Cataract
  study_type      = "incidence",

  # 冒烟可先只放 1–2 个指标；正式再扩 dual_safe / 自定义名单
  index_group = "dual_safe",
  index_vars = c("<TO_CONFIRM_INDEX>"),       # ❓ WWI

  outcome_column = "<TO_CONFIRM_OUTCOME>",    # ❓ Disease_Group
  id_column      = "ID",

  primary_name           = "NHANES",
  primary_db_type        = "nhanes",
  primary_subdir         = "nhanes",
  primary_rdata_file     = "D04_dabiao.RData",
  primary_rdata_obj      = "dabiao",
  primary_column_mapping = "NHANES",

  secondary_name           = "CHARLS",         # ❓ 或 MIMIC / eICU
  secondary_db_type        = "regular",
  secondary_subdir         = "charls",         # ❓
  secondary_rdata_file     = "D04_dabiao.RData",
  secondary_rdata_obj      = "dabiao",
  secondary_column_mapping = "CHARLS",         # ❓

  merge_dual_db_tables       = FALSE,
  mirror_aggregate_prefix_db = FALSE,
  apply_nhanes_upstream      = TRUE,

  # NHANES 开发+内验 → 次库整库外验（对齐 Cataract / 肌少症）
  split_mode = "dev_internal_ext",

  # 指标级 summary_results 白名单五件套（全项目默认）
  write_index_summary_results = TRUE,

  disease_config_preset = "psoriasis",
  feishu_enable         = FALSE
)

.study_config_file <- {
  ca <- commandArgs(trailingOnly = TRUE)
  i <- match("--config", ca)
  if (!is.na(i) && i < length(ca)) {
    normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
  } else {
    NA_character_
  }
}
.batch_project_root <- if (!is.na(.study_config_file)) {
  dirname(.study_config_file)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}
.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")
.batch_data_root <- file.path(.batch_project_root, "Data")

.mb_root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) {
    env
  } else if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
    "/mnt/e/01block/01Block-new-Final"
  } else if (dir.exists("E:/01block/01Block-new-Final")) {
    "E:/01block/01Block-new-Final"
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = .mb_root)

source(file.path(.mb_root, "configs/study_interface/ml_dual_batch_build.R"))

config$index$enable <- TRUE
config$ml_batch$index_mode <- "single_loop"
config$ml_batch$write_index_summary_results <- TRUE
config$incidence_batch <- config$ml_batch
config$pub_figures$dpi <- 600L
config$pub <- modifyList(
  config$pub %||% list(),
  list(
    write_index_summary_results = TRUE,
    index_summary_results_dir = "summary_results",
    summary_result = FALSE
  )
)

# <TO_CONFIRM_AGE>：成人队列示例 Age >= 45；无年龄限制则删此行
config$data_clean$age_filter <- "Age >= 45"

# 疾病泄漏列：按列审阅写入；白内障示例可为空
.disease_exclusion_vars <- character(0)  # <TO_CONFIRM_DISEASE_VARS>
config$analysis_exclusion <- list(
  enable = TRUE,
  disease_vars = .disease_exclusion_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)

# 年龄切点依据：<TO_CONFIRM_AGE_CUTOFF_LIT>；森林图仅二分类
config$subgroup <- modifyList(
  config$subgroup %||% list(),
  list(
    enable = TRUE,
    var_source = "required",
    restrict_to_required = TRUE,
    required_subgroup_vars = c("Age", "Gender"),
    age_cutoff = 65L,
    continuous_index_mode = "highest_vs_lowest",
    forest_n_source = "full_stratum",
    forest_xlim = c(0.2, 4),
    level_order = list(Age_Group = c("< 65", "\u2265 65"))
  )
)

config$shap <- modifyList(
  config$shap %||% list(),
  list(
    ml_model = "auto",
    force_kernel_best_model = TRUE,
    save_individual = FALSE,
    combine = TRUE
  )
)

config$pub_digits <- list(
  est = 3L, p = 3L, desc = 3L, cutoff = 3L,
  int_big_mark = TRUE, desc_trim = TRUE
)

rm(.disease_exclusion_vars)
