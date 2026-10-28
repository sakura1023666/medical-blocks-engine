###############################################################################
# 预后 2.0：髋关节置换合并 AKI · MIMIC-IV · SIRI/PIV · 365 天全因死亡
# 单库：表/图文件名不加数据库前缀（R/pv2_pub_names.R）
# 文献骨架：Jin 2026 PMID 41904528（Boruta+SHAP+VIF；连续+分位；M1/M2/M3）
# 暴露：SIRI、PIV（多指标）；不加权
# 分位：引擎 quantile_scheme_cascade（quartile→tertile→binary；crude 最高档；多指标 all）
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

.v2_root <- file.path(.block_result_root, "52_Hip_arthroplasty_aki", "prognosis_v2_41904528")
.v2_data <- file.path(.v2_root, "data")

config <- list(
  project = list(
    name = "Prognosis_v2_hip_AKI_SIRI_PIV",
    disease = "hip_arthroplasty_aki",
    disease_code = "52",
    study_type = "prognosis",
    routine = "prognosis_v2",
    literature_pmid = "41904528",
    root = .block_repo_root,
    output_dir = file.path(.v2_root, "summary_results"),
    database = "MIMIC",
    analysis_group = "Dead",
    reference_group = "Alive"
  ),

  # 分析集已 Age≥65；亚组切点 75（老年髋关节/骨科 ICU 常用）
  subgroup = list(
    age_cutoff = 75L,
    level_order = list(Age_Group = c("< 75", "\u2265 75")),
    required_subgroup_vars = c("Age", "Gender", "Hypertension", "Diabetes", "SOFA"),
    continuous_index_mode = "highest_vs_lowest",
    forest_n_source = "full_stratum",
    forest_xlim = c(0.2, 5)
  ),

  prognosis_v2 = list(
    database = "MIMIC",
    data_root = .v2_data,
    analysis_rds = "analysis_Age65_SIRI_PIV_ready_365d.rds",
    index_vars = c("SIRI", "PIV"),
    landmark_days = 365L,
    time_var = "futime",
    event_var = "fustatus",
    # 中介：OASIS（急性病情严重度）自数据源进入协变量池与 MICE，与主分析同一插补队列
    mediator = "OASIS",
    single_db = TRUE
  ),

  # 分位级联闸门（引擎 R/quantile_scheme_cascade.R）：Q→T→B
  # pass_rule=all：SIRI 与 PIV 的 crude 最高档均显著才锁定该档
  quantile_scheme_cascade = list(
    enable = TRUE,
    try_schemes = c("quartile", "tertile", "binary"),
    p_threshold = 0.05,
    pass_rule = "all",
    on_none_pass = "best_n_pass",
    family = "cox",
    time_var = "futime_years",
    event_var = "fustatus"
  ),

  imputation = list(
    missing_col_threshold = 0.4, method = "cart", m = 5L, maxit = 5L,
    seed = 1234L, complete_action = 1L, rubin_pool = TRUE
  ),

  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = c(
      "Creatinine", "UreaNitrogen", "Acute_Renal_Failure", "CKD", "CRRT", "CRRT_Day",
      "AlbuminUrine", "AlbuminCreatinine", "UrineCreatinine", "UrineVolume",
      "UrineProtein", "UrineGlucose",
      "Neutrophil_Count", "NeutrophilCount", "Monocyte", "Lymphocytes",
      "PlateletCount", "WBC",
      "T1DM", "T2DM"
    ),
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  survival = list(
    time_var = "futime",
    event_var = "fustatus",
    index_var = "SIRI"
  ),

  # 全文统一协变量（事件数受限精简；Table3/4/敏感性共用）
  # Model1 未调整；Model2 = Age + Gender；Model3 = Age + Gender + CHARLSON
  # 不调 SOFA/OASIS：急性严重度与中介路径重叠，易过度调整
  force_model_covariates = list(
    model2 = c("Age", "Gender"),
    model3 = c("Age", "Gender", "CHARLSON")
  ),

  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L, int_big_mark = TRUE, desc_trim = TRUE),

  study_batch = list(
    output_base = .v2_root,
    project_root = .block_repo_root,
    units = c("MIMIC"),
    parallel_workers = 1L,
    worker_script = "run/prognosis_v2/run_prognosis_v2_hip_aki.R"
  )
)

pipeline <- list(name = "prognosis_v2_hip_aki", blocks = character(0))
