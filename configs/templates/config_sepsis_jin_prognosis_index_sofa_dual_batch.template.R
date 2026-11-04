###############################################################################
#  config_sepsis_jin_prognosis_index_sofa_dual_batch.template.R
#
#  脓毒症 · Jin2025 方法迁移 · 双库全复合指标并行（预后地基 + 方法目录块）
#  决策树: Decisiontree/decision_tree_sepsis_jin_prognosis_index_sofa_dual.md
#  对抗阅读: paper_40295872（Q1–Q8 PASS）
#
#  复制到:
#    //192.168.68.133/02block_result/36_spesis/prediction_41194138/config_survival.R
#  先准备数据:
#    Rscript run/sepsis_jin_prognosis/prepare_analysis_data.R --project <项目根>
#  再跑:
#    Rscript run/sepsis_jin_prognosis/run_batch.R --config <config> --shared-only
#    Rscript run/sepsis_jin_prognosis/run_batch.R --config <config> --workers auto
###############################################################################

.study <- list(
  disease_code    = "36",
  disease         = "Sepsis",
  literature_pmid = "41194138",
  analysis_group  = "Non-survivor",
  reference_group = "Survivor",

  ## D7：双库可算复合指标全池（剔 HDL/LDL 透传与 HbA1c 轴）
  index_group = NULL,
  index_vars = c(
    "NLR", "PLR", "SII", "NLPR", "ANLR", "PHR", "HALP", "GLR", "WPR",
    "CRI_II", "GPR", "De_Ritis", "FIB4", "APRI", "ALBI", "AGR", "BAR",
    "LAR", "log2LAR", "CAR", "UA_CR", "BUN_Cr", "RAR", "HRR", "PNI",
    "EASIX", "SOSM", "BMI", "MCH", "MCV", "MCHC", "RDW_CV", "HHR",
    "LHR", "UHR", "ALI", "ACAG", "AFR", "ALT_HDL_C", "HSI", "NFS"
  ),

  eicu_rdata_file  = "D04_dabiao.RData",
  mimic_rdata_file = "D04_dabiao.RData",
  eicu_rdata_obj   = "dabiao",
  mimic_rdata_obj  = "dabiao",
  id_column        = "ID",
  time_var         = "futime",
  event_var        = "fustatus",

  ## 主库 = MIMIC（开发）；次库 = eICU（外验角色由 survival dual 编排）
  primary_db = "MIMIC",
  secondary_db = "eICU",

  database_version_eicu  = "eICU-CRD v2.0",
  database_version_mimic = "MIMIC-IV",

  ## 年龄切点依据：脓毒症 ICU 预后亚组常用 65（无病种特异 RCT 强制界）
  sensitivity_enable       = TRUE,
  sensitivity_age_cutoff   = 65L,
  subgroup_fallback_enable = FALSE,
  feishu_enable            = TRUE,

  model3_required_factors  = character(0)
)

.study_config_file <- {
  ca <- commandArgs(trailingOnly = TRUE)
  i  <- match("--config", ca)
  if (!is.na(i) && i < length(ca))
    normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
  else
    NA_character_
}
.batch_project_root <- if (!is.na(.study_config_file)) {
  dirname(.study_config_file)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
if (is.na(engine_root) || !nzchar(engine_root)) {
  .cand <- c(
    "/mnt/e/01block/01Block-new-Final",
    "E:/01block/01Block-new-Final"
  )
  for (.ef in .cand) if (dir.exists(.ef)) { engine_root <- .ef; break }
}
if (is.na(engine_root) || !nzchar(engine_root)) stop("无法获取 MEDICAL_BLOCKS_ROOT")
engine_root <- gsub("\\\\", "/", engine_root)
if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", engine_root)) {
  .drv <- tolower(substr(engine_root, 1L, 1L))
  engine_root <- paste0("/mnt/", .drv, substring(engine_root, 3L))
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "configs/study_interface/survival_dual_batch_build.R"),
       local = TRUE)

`%||%` <- function(a, b) if (is.null(a)) b else a

## 决策树：MIMIC = 开发主库；eICU = 外验次库（覆盖 build 默认 eICU-primary）
.prim <- config$dual_db$primary
.sec <- config$dual_db$secondary
if (!is.null(.prim) && !is.null(.sec)) {
  .mim <- if (identical(.prim$name, "MIMIC")) .prim else .sec
  .eic <- if (identical(.prim$name, "eICU")) .prim else .sec
  if (!identical(.mim$name, "MIMIC")) {
    .mim <- .sec
    .eic <- .prim
  }
  config$dual_db$primary <- utils::modifyList(.mim, list(name = "MIMIC"))
  config$dual_db$secondary <- utils::modifyList(.eic, list(name = "eICU"))
  config$project$database <- "MIMIC"
}

###############################################################################
#  Jin 方法后缀：按方法目录挂块（禁止 82_* 套路整包）
#  derived_grouping → 02_data_clean
#  cox_multi_horizon → 10_cox
#  logistic_nomogram → 11_logistic
#  shap_glm → 17_shap（解释 nomogram/glm；ML 树模型仍用 shap）
#  另复用：cox_tertile / cox_interaction / km_strata / rcs / mediation_prognosis
###############################################################################

## 合法挂接（须与项目根 extensions.json 一致；勿破坏基线顺序）
## - survival.after_rcs_prognosis → derived_grouping（紧邻 RCS，早于 km_strata）
## - survival.end → 下列末尾后缀
.jin_after_rcs <- "derived_grouping"
.jin_end <- c(
  "rcs_sofa_horizon",   # Jin Fig1：SOFA×院内/30d/365d 2×3（须在 derived_grouping 后）
  "cox_interaction",
  "cox_multi_horizon",
  "logistic_nomogram",
  "shap_glm",
  "simple_ROC",
  "boxplot",
  "mediation_prognosis"
)
.bl <- as.character(pipeline_regular_batch$blocks)
.bl <- setdiff(.bl, c(.jin_after_rcs, .jin_end))
.rcs_i <- match("rcs_prognosis", .bl)
if (is.na(.rcs_i)) {
  stop("pipeline 缺少 rcs_prognosis，无法挂 derived_grouping", call. = FALSE)
}
.bl <- c(
  .bl[seq_len(.rcs_i)],
  .jin_after_rcs,
  .bl[seq(.rcs_i + 1L, length(.bl))],
  .jin_end
)
pipeline_regular_batch$blocks <- .bl
.jin_tail <- c(.jin_after_rcs, .jin_end)
pipeline_regular_batch$render_tables_after <- unique(c(
  as.character(pipeline_regular_batch$render_tables_after %||% character(0)),
  .jin_tail
))
pipeline_regular_batch$render_figures_after <- unique(c(
  as.character(pipeline_regular_batch$render_figures_after %||% character(0)),
  .jin_tail
))
pipeline_regular_batch$checkpoint$enable <- TRUE
pipeline <- pipeline_regular_batch

###############################################################################
#  疾病硬排除：SOFA 用 protect 保列（分层/nomogram），禁止进 Model1/2
###############################################################################

.disease_exclusion_vars <- c(
  "SIRS", "Lactate",
  "CKD", "Acute_Renal_Failure",
  "CRRT", "CRRT_Day",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "UrineCreatinine", "UrineVolume", "UrineOsmolality"
)

config$analysis_exclusion <- list(
  disease_vars = .disease_exclusion_vars,
  ## TotalCo2=中介/诺模图；Hemoglobin/WBC=诺模图；SOFA=分层
  protect_vars = c(
    "SOFA", "Age", "BMI", "TotalCo2",
    "Hemoglobin", "WBC", "NBPM", "Sodium", "CalciumTotal"
  ),
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)

config$survival_batch <- utils::modifyList(config$survival_batch %||% list(), list(
  base_subgroup_vars = c("Age", "BMI", "Gender", "Hypertension", "T2DM",
                         "COPD", "Heart_Failure", "Pneumonia"),
  base_exclude_vars = unique(c(
    as.character((config$survival_batch %||% list())$base_exclude_vars %||% character(0)),
    .disease_exclusion_vars, "SOFA"
  )),
  trim_quantile = 0,
  ## Jin 原文图序：Fig1=RCS, Fig2=Nomogram, Fig3=SHAP, Fig4=Mediation;
  ## S1=Flowchart, S2=KM, S3=Calibration（见 R/jin_index_sofa_pub.R）
  pub_figure_scheme = "jin_index_sofa"
))

## 主终点 = 院内死亡（D2）；不作 28 天 landmark 覆盖院内口径
config$prognosis_outcome <- utils::modifyList(config$prognosis_outcome %||% list(), list(
  enable = FALSE
))
config$survival <- utils::modifyList(config$survival %||% list(), list(
  time_var = "futime",
  event_var = "fustatus",
  outcome_label = "In-hospital all-cause mortality"
))

## 方法块 config（优先新键；旧 jin_index_sofa 仍作块内 fallback）
config$derived_grouping <- list(
  enable = TRUE,
  sofa_var = "SOFA",
  sofa_cutoff = 5L,                # D3 主分析
  sofa_cutoff_sensitivity = "median",
  high_low_mode = "t3_vs_t1",      # D1
  primary_horizon = "in_hospital"  # D2
)

config$cox_multi_horizon <- list(
  enable = TRUE,
  # hosp=院内；d30/d365 对齐 prepare_analysis_data 的 futime_*/event_* 列
  horizons = c("hosp", "d30", "d365"),
  exposure_var = "Index_SOFA_Q",
  hosp = list(time = "futime", event = "fustatus"),
  d30  = list(time = "futime_30d", event = "event_30d"),
  d365 = list(time = "futime_365d", event = "event_365d")
)

## Jin 原文 Fig1：High/Low SOFA × 院内/30d/365d（2×3 RCS；非 Crude/M1/M2 横排）
config$rcs_sofa_horizon <- list(
  enable = TRUE,
  sofa_bin_var = "SOFA_bin",
  high_level = "High",
  low_level = "Low",
  horizons = c("hosp", "d30", "d365"),
  nk = 4L,
  model = "crude",
  figure_number = 1L,
  figure_kind = "main_figure",
  ## 拟合仍用全样本；作图横轴/直方图裁到层内 P1–P99（WPR 等右偏指标防尾部撑轴）
  plot_x_quantiles = c(0.01, 0.99)
)

## 诺模图：强制暴露+SOFA；其余候选 backward α=0.05（对齐 Jin stepwise）后 lrm
config$logistic_nomogram <- list(
  enable = TRUE,
  outcome = "fustatus",
  selection = "backward",
  selection_alpha = 0.05,
  candidate_features = c(
    "Age", "Gender", "NBPM", "HeartRate", "RespiratoryRate",
    "WBC", "Hemoglobin", "Platelet_Count", "PLT",
    "TotalCo2", "Sodium", "Potassium", "CalciumTotal", "Creatinine"
  )
)

config$shap_glm <- list(
  enable = TRUE,
  label = "SHAP for logistic nomogram (in-hospital mortality; not bare best-model)"
)

## 兼容旧键（块内仍可读）；新课题以方法键为准
config$jin_index_sofa <- list(
  enable = TRUE,
  sofa_var = "SOFA",
  sofa_cutoff = 5,
  sofa_cutoff_sensitivity = "median",
  high_low_mode = "t3_vs_t1",
  primary_horizon = "in_hospital",
  multi_horizon = config$cox_multi_horizon,
  nomogram = config$logistic_nomogram,
  shap = config$shap_glm
)

## 中介：预后套路 — 血检池 LM 筛显著 → 双库锁 best（勿点名 TotalCo2）
config$mediation_prognosis <- utils::modifyList(config$mediation_prognosis %||% list(), list(
  diagram_enable = TRUE,
  mediators = NULL,
  best_mediator = NULL,
  mediators_strict_only = FALSE,
  dual_library_lm_screen = TRUE,
  dual_db_lock_best_mediator = TRUE,
  skip_export_if_ns = TRUE,
  outcome_label = "In-hospital all-cause mortality"
))

## 连续暴露 × SOFA_bin 交互（复用 10_cox/cox_interaction；须在 derived_grouping 之后）
## pause_enable=FALSE：层内/编码异常时跳过交互块，不因 PAUSE 拖死整指标
config$cox_interaction <- utils::modifyList(config$cox_interaction %||% list(), list(
  enable = TRUE,
  modifier_var = "SOFA_bin",
  ref_level = "Low",
  pause_enable = FALSE,
  pause_on_low_events = FALSE
))

## 四组 KM（复用 27_KM/km_strata；列由 derived_grouping 写入）
config$km_strata <- utils::modifyList(config$km_strata %||% list(), list(
  enable = TRUE,
  strata_vars = c("Index_SOFA_Q"),
  keep_explicit_strata = TRUE
))

config$subgroup <- utils::modifyList(config$subgroup %||% list(), list(
  age_cutoff = 65L,
  var_source = "required",
  required_subgroup_vars = c("Age", "Gender", "Hypertension", "T2DM"),
  continuous_index_mode = "highest_vs_lowest",
  forest_n_source = "full_stratum",
  level_order = list(Age_Group = c("< 65", "\u2265 65"))
))

## Table 1 暴露组间 P≥0.05 → BASELINE_INDEX_NS_STOP → 整指标【failed】
## 双库：任一侧触发即整指标失败，不再跑对侧 / Phase 2–3（见 survival dual worker）
config$baseline_binary <- utils::modifyList(config$baseline_binary %||% list(), list(
  early_stop_if_index_ns = TRUE,
  sig_cutoff = 0.05
))

## method = mice 包单变量法（pmm），勿写 "mice"（会被当成 mice.impute.mice）
config$imputation <- utils::modifyList(config$imputation %||% list(), list(
  method = "pmm",
  m = 5L,
  rubin_pool = TRUE,
  complete_action = 1L,
  export_missing_fig = FALSE
))

config$attrition <- utils::modifyList(config$attrition %||% list(), list(
  enable = TRUE,
  outcome_breakdown = TRUE,
  steps = list(
    list(label = "ICU stays in extract", note = "D01 baseline"),
    list(label = "Sepsis cohort (ICD/ID list)", note = "project _cohort_ids"),
    list(label = "Age 18-150 & ICU stay >=1 day"),
    list(label = "Included for analysis")
  )
))

config$pub_digits <- list(
  est = 3L, p = 3L, desc = 3L, cutoff = 3L,
  int_big_mark = TRUE, desc_trim = TRUE, p_style = "fixed"
)

config$pub_figures <- utils::modifyList(config$pub_figures %||% list(), list(
  formats_dir = TRUE,
  export_png = FALSE,
  export_tiff = FALSE,
  write_image_information = TRUE
))

config$feishu <- utils::modifyList(config$feishu %||% list(), list(
  enable = TRUE,
  push_on_worker_finish = TRUE,
  push_on_batch_summary = TRUE
))

config$ml_models <- utils::modifyList(config$ml_models %||% list(), list(
  enable = FALSE  # D6：不开五模型竞赛
))
