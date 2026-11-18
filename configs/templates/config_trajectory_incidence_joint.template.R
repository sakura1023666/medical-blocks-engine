###############################################################################
# config_trajectory_incidence_joint.template.R
# 联合轨迹发病套路（GBMTM joint longitudinal trajectories）
# 对标文献: Liu et al. Cardiovasc Diabetol 2026;25:207
# Blocks/82_trajectory_incidence_joint: 01 ingest -> 02 gbmtm -> 03 cox-rubin
#   -> 04 subgroup -> 05 sensitivity -> 06 pub_export
#
# 换项目只需改本文件：疾病 / 数据库 / 指标体系(index_pairs) / 波次 / 协变量集 / 结局列
# 铁律联动：m=5+Rubin、指标筛选门控(见规则)、疾病成分硬排除、纳排诚实分项。
###############################################################################

.block_repo_root <- {
  env <- Sys.getenv("BLOCK_REPO_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else "E:/01block/01Block-new-Final"
}
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

# ── 项目定位（换项目改这里）────────────────────────────────────────────
.project_root <- file.path(.block_result_root, "56_CVD", "incidence_trajectory_joint")
.raw_rds      <- file.path(.project_root, "data", "master_wide.rds")  # 多波宽表（含各成分 <comp>_w<k>）
.raw_obj      <- "master"                                            # rds 内对象名

config <- list(
  project = list(
    name = "CVD_Joint_Trajectory_Incidence",
    disease = "cvd",
    disease_code = "56",
    study_type = "incidence",
    literature_pmid = "13393250",
    database = "ELSA",                 # 单库；换库改此
    root = .block_repo_root,
    output_dir = file.path(.project_root, "Output")
  ),

  data = list(
    rawdata_path = .raw_rds,
    rawdata_obj  = .raw_obj,
    id_column    = "id"
  ),

  # ── 多重插补铁律（mi_m5_rubin_pool）：m=5 + Rubin ─────────────────────
  imputation = list(
    enable = TRUE,
    method = "mice",
    m = 5L,
    maxit = 10L,
    seed = 42L,
    fit_on = "all",          # 轨迹定类锁全样本；协变量插补可改 "train" 视设计
    rubin_pool = TRUE,       # 推断 Cox/亚组/敏感性跨 m 套合并
    complete_action = 1L     # 仅操作层（Table1/KM/画图）；推断走 Rubin
  ),

  # ── 联合轨迹发病核心配置 ──────────────────────────────────────────────
  joint_trajectory = list(
    id_column = "id",
    waves = c(2, 4, 6),                # 轨迹测量波（对照文献随访波次）
    wave_suffix = "_w",
    recompute_indices = TRUE,          # 用 00_index 公式按波重算复合指标
    age_filter = "age >= 50",          # 人群门控（依据文献纳排）

    # 指标体系：每个体系 = 一联合轨迹对（多指标课题默认多对，逐对出图）
    # ⚠ 须先过「指标筛选门控」(index_pool_screening)：复合指标库真公式 + 双库/多波可算
    index_pairs = list(
      BMI_TyG  = c("TyG", "BMI"),
      WHtR_TyG = c("TyG", "WHtR")
    ),
    group_col_prefix = "grp_",

    # GBMTM 参数（gbmtm_core.R）
    k_range = 2:6,
    poly_degree = 2L,
    n_start = 10L,
    seed = 42L,
    force_K = NULL,                    # 数据驱动 AIC/BIC + AvePP>=0.70 + 最小类>=5%
    force_K_by_system = list(),

    # 基线现患剔除（结局定义相关诊断，防 prevalence 混入 incidence）
    prevalent_exclude = list(cvd0 = c("angina", "mi", "hf", "arry", "stroke")),

    # 结局列（须由独立结局步预生成到 master：新发 event 0/1 + 中点随访 time_m）
    exclude_first_years = 2,
    outcome = list(
      primary = list(name = "cvd", event_col = "cvd_event", time_col = "cvd_time_m"),
      secondaries = list(
        list(name = "heart",  event_col = "heart_event",  time_col = "heart_time_m"),
        list(name = "stroke", event_col = "stroke_event", time_col = "stroke_time_m")
      )
    ),

    # 序贯 Cox 协变量集（文献四段式；换病种须裁剪成分/泄漏变量）
    model_sets = list(
      model1 = c("age", "sex", "race_white", "edu"),
      model2 = c("age", "sex", "race_white", "edu", "smoke", "drink"),
      model3 = c("age", "sex", "race_white", "edu", "smoke", "drink",
                 "hbp_d", "dm_d", "chol_d"),
      model4 = c("age", "sex", "race_white", "edu", "smoke", "drink",
                 "hbp_d", "dm_d", "chol_d", "bpmed", "dmmed", "fvc")
    ),

    subgroup = list(
      vars = c("Age_Group", "Sex_lbl", "Edu_Group", "DM_lbl", "HBP_lbl", "Smoke_lbl"),
      age_cutoff = 65L,                 # 年龄亚组二分类切点（病种文献依据）
      model = "model4",
      min_events = 15L
    ),

    sensitivity = list(
      model = "model4",
      items = c("S0_main", "S1_exclude_first2y", "S3_exclude_DM", "S4_exclude_HBP",
                "S5_complete_case", "S6_exclude_glucose_lipid_med", "S7_PP_weighted",
                "S9a_linear_time", "S9b_cubic_time")
    ),

    pub = list(
      delivery_root = NULL,             # NULL -> <Output>/summary_results
      table1_cont = NULL,               # NULL -> 自动探测
      table1_cat  = NULL
    )
  ),

  # 疾病成分/泄漏硬排除（disease_component_hard_exclusion）
  analysis_exclusion = list(
    disease_vars = c("hbp_d", "dm_d", "insulin", "bpmed", "dmmed"),  # 视课题
    exclude_exposure_if_uses_disease_var = FALSE                      # 暴露即指标成分本身
  ),

  # 小数位 / 字体（pub_digits_consistency / pub_times_new_roman）
  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L,
                    int_big_mark = TRUE, desc_trim = TRUE, p_style = "fixed"),
  pub_figures = list(export_png = FALSE, export_tiff = FALSE, require_vector_pdf = TRUE)
)

# ── 执行链（run_pipeline 的 pipeline$blocks）──────────────────────────
# 顺序铁律：轨迹定类(操作层锁全样本) → MICE(仅补 Cox 协变量) → 推断(Rubin)。
#   tj_gbmtm_fit 在 imputation 之前跑，类别列 grp_* 一旦写死便不参与插补；
#   tj_cox_rubin/subgroup/sensitivity 经 mi_complete_aligned(keep_vars=类别/结局) 取每套 complete。
pipeline <- list(
  blocks = c("tj_data_ingest", "tj_gbmtm_fit", "imputation", "tj_cox_rubin",
             "tj_subgroup", "tj_sensitivity", "tj_pub_export")
)

# 类别列 / 结局事件时间 / 波次成分不作为 MICE 插补目标（只作预测因子或纯标签）
config$imputation$exclude_from_mice_cols <- c(
  paste0("grp_", names(config$joint_trajectory$index_pairs)),
  ".tj_row_id",
  unlist(lapply(c(list(config$joint_trajectory$outcome$primary),
                  config$joint_trajectory$outcome$secondaries %||% list()),
                function(o) c(o$event_col, o$time_col)))
)
# 轨迹成分波次列（TyG_w2…）保留为预测因子，不作删列/整列剔除
config$imputation$force_keep_columns <- unique(c(
  config$imputation$force_keep_columns %||% character(0),
  ".tj_row_id"))

# 纳排诚实分项（attrition_consort_flowchart §8）：年龄 + 指标成分必出框
config$attrition <- list(
  outcome_breakdown = TRUE,
  config_steps_only = TRUE,
  steps = list(
    list(id = "q_start",  label = "Study baseline participants", kind = "include"),
    list(id = "q_age",    label = "Age >= 50",                   kind = "exclude"),
    list(id = "q_index",  label = "Joint trajectory indices computable", kind = "exclude"),
    list(id = "q_prev",   label = "Prevalent CVD at baseline",   kind = "exclude"),
    list(id = "q_final",  label = "Analytic cohort",             kind = "include")
  )
)
