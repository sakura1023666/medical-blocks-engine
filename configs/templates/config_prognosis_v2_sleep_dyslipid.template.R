###############################################################################
#  config_prognosis_v2_sleep_dyslipid.template.R
#  预后 2.0：睡眠时长 × 血脂异常 × 全因死亡（三库可并行）
#  不改 configs/config_survival_dual_batch.R，也不改其 pipeline$blocks。
#  决策树: Decisiontree/decision_tree_prognosis_v2.md
#  文献: Jin et al. 2026 PMID 41904528（方法骨架）；暴露改为睡眠范围。
###############################################################################

.block_repo_root <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
.block_result_root <- {
  if (dir.exists("G:/02block_result")) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

# 主库/验证库新项目目录；旧三库平权结果见 prognosis_v2_41904528_ARCHIVE_*
.v2_root <- file.path(.block_result_root, "49_Dyslipidemia", "prognosis_v2_mainval_41904528")
.v2_data <- file.path(.block_result_root, "49_Dyslipidemia", "prognosis_41904528", "data")

config <- list(
  project = list(
    name = "Prognosis_v2_sleep_dyslipidemia",
    disease = "dyslipidemia",
    disease_code = "49",
    study_type = "prognosis",
    routine = "prognosis_v2",
    literature_pmid = "41904528",
    literature_doi = "10.1186/s12933-026-03149-5",
    root = .block_repo_root,
    output_dir = .v2_root,
    use_step_prefixed_block_dirs = TRUE,
    analysis_group = "Dead",
    reference_group = "Alive"
  ),

  # 年龄切点依据：对标 Jin 2026 亚组 <60 / ≥60（PMID 41904528）
  subgroup = list(
    age_cutoff = 60L,
    level_order = list(Age_Group = c("< 60", "\u2265 60"))
  ),

  prognosis_v2 = list(
    database = "SHHS",
    data_root = .v2_data,
    short_lt = 7,
    long_ge = 9,
    horizon_years = 2,
    horizon_alt_years = 5,
    shhs_death_code = 0L,
    charls_sleep_path = "",
    mediator = "HbA1c",
    mediation_sims = 200L,
    full_covariates = c("Age", "Gender", "BMI")
  ),

  # 血脂异常诊断、用药和定义用的血脂列不进协变量
  # m=5：操作层 complete#1（图/Boruta）；Cox 须 Rubin（pv2_mi_cox.R）。rubin_pool=TRUE。
  imputation = list(
    missing_col_threshold = 0.4, method = "cart", m = 5L, max_iter = 5L,
    seed = 1234L, complete_action = 1L, rubin_pool = TRUE
  ),
  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = c(
      "Hyperlipidemia", "TG", "TC", "HDL", "LDL", "LBDLDL_calc",
      "chol", "hdl", "trig", "Lipid_lowering_agents"
    ),
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  survival = list(
    time_var = "futime_years",
    event_var = "fustatus",
    index_var = "Sleep_hours"
  ),

  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L, int_big_mark = TRUE, desc_trim = TRUE),

  feishu = list(
    enable = TRUE,
    disease_label = "血脂异常",
    protocol_label = "预后2.0"
  ),

  study_batch = list(
    output_base = .v2_root,
    project_root = .block_repo_root,
    units = c("NHANES", "CHARLS", "SHHS"),
    parallel_workers = 3L,
    worker_script = "run/prognosis_v2/run_prognosis_v2_worker.R"
  )
)

pipeline_shared <- list(
  name = "prognosis_v2_shared_noop",
  blocks = character(0),
  checkpoint = list(enable = FALSE)
)

pipeline_unit <- list(
  name = "prognosis_v2_unit",
  blocks = c(
    "sleep_dyslipid_cohort",
    "sleep_duration_range",
    "survival_fixed_horizon",
    "horizon_roc_youden",
    "bayesian_mediation_horizon"
  ),
  checkpoint = list(enable = TRUE, dir = NULL),
  render_tables_after = character(0),
  render_figures_after = character(0)
)

pipeline <- pipeline_unit
