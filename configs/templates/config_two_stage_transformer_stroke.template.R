###############################################################################
#  config_two_stage_transformer_stroke.template.R — 缺血性脑卒中两阶段 Transformer（单跑）
#  单库 MIMIC 急性缺血性脑卒中住院队列；landmark 24/48/72/96/120h；主结局院内死亡
#
#  依据: Yang et al. 2025 Precision Clinical Medicine pbaf003（两阶段 Transformer）
#  方法迁移: 缺血性脑卒中两阶段Transformer双轨复现方案.pdf
#  设计: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md
#  决策树: Decisiontree/decision_tree_two_stage_transformer_stroke.md
#  任务并行版本: configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R
#  入口: run/two_stage_transformer_stroke/run_two_stage_transformer_stroke.R
#
#  Blocks 71_two_stage_transformer_stroke/01-12（tst_cohort…tst_summary_results）
#  复制到研究产出目录后按【必改】修改；勿改 pipeline_* blocks。
###############################################################################

.mb_root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) {
    env
  } else {
    env2 <- Sys.getenv("BLOCK_REPO_ROOT", "")
    if (nzchar(env2) && dir.exists(env2)) env2 else {
      cands <- c("E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")
      hit <- cands[dir.exists(cands)]
      if (length(hit)) hit[[1]] else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    }
  }
}

# 数据与产出根：\\...\02block_result\11_ischemic stroke\two_stage_transformer_40041421
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) {
    env
  } else if (dir.exists("/mnt/g/02block_result")) {
    "/mnt/g/02block_result"
  } else {
    "G:/02block_result"
  }
}
.tst_project_root <- file.path(
  .block_result_root, "11_ischemic stroke/two_stage_transformer_40041421"
)
.tst_data_root <- file.path(.tst_project_root, "data")

# 全部结果写到研究产出根，禁止写仓库 Output/
.tst_output_root <- .tst_project_root
.tst_ck_root      <- file.path(.tst_output_root, "checkpoints")

config <- list(
  project = list(
    name = "TwoStage_Transformer_Stroke",
    disease = "IschemicStroke_TwoStageTransformer",
    disease_code = "11",
    study_type = "prognosis",
    literature_pmid = "pbaf003",
    analysis_group = "In-hospital death",
    reference_group = "Survived",
    database = "MIMIC",
    database_type = "MIMIC",
    root = .mb_root,
    output_dir = .tst_output_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    # 硬约束：发表级表/图留在 step 子目录，不镜像到 Output 根 Tables/Figures
    mirror_pub_outputs_to_root = FALSE
  ),

  data = list(
    rawdata_path = file.path(.tst_data_root, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData"),
    rawdata_obj  = "baseline",
    # 基线宽表（65366x104）主键为 ID（Task1 审计）；实验室长表/预后表主键为
    # subject_id/stay_id/hadm_id。Task4 tst_cohort 需建立 ID <-> stay_id 映射
    # （TODO：人工核实，禁止臆造），此前 id_column 仅约束长表/预后表侧。
    baseline_id_column = "ID",
    id_column = "stay_id",
    lab_long_path  = file.path(.tst_data_root, "mimic-\u5b9e\u9a8c\u5ba4\u6307\u6807-all-1~30\u5929.csv"),
    prognosis_path = file.path(.tst_data_root, "mimic\u9884\u540e\u6570\u636e-all.csv"),
    dabiao_path    = file.path(.tst_data_root, "dabiao.csv"),  # 缺血性卒中 stay 名单（必需）
    # 院内死亡（存活出院=0 / 院内死亡=1）；来自预后宽表 is_hosp_dead 列
    # （Task1 审计 §4.3 确认存在，需在 tst_cohort 按 id_column join 后使用）
    outcome_column = "is_hosp_dead",
    admission_time_column = "icu_intime"
  ),

  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = TRUE, database_type = "MIMIC"),

  imputation = list(
    missing_col_threshold = 0.30,
    method = "rf",
    m = 5L,
    seed = 1234L,
    fit_on = "train",
    complete_action = 1L,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE,
    pause_enable = FALSE
  ),

  tst_timeseries = list(
    feature_missing_threshold = 0.30,
    patient_missing_threshold = 0.30,
    patient_missing_days = 5L,
    min_longitudinal_days = 1L,
    temporal_forward_fill = TRUE,
    sliding_window = TRUE,
    max_export_day = 30L,
    pause_enable = FALSE
  ),

  tst_cohort = list(
    min_age = 18,
    id_overlap_pause_threshold = 0.5,
    dabiao_join_key = "stay_id",
    pause_enable = FALSE
  ),

  baseline_binary = list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_on_table1_fail = FALSE,
    strata = "is_hosp_dead",
    strata_level_labels = list(
      "0" = "Survived",
      "1" = "In-hospital death",
      "No IschemicStroke_TwoStageTransformer" = "Survived",
      "IschemicStroke_TwoStageTransformer" = "In-hospital death",
      "No IschemicStroke TwoStageTransformer" = "Survived",
      "IschemicStroke TwoStageTransformer" = "In-hospital death"
    ),
    # 时间戳/ID 若进 Table 1 会按唯一时刻展开成数千行；显式排除（block 内也会自动识别）
    exclude_vars = c(
      "admit_time", "disch_time", "icu_intime", "icu_outtime", "tst_time_zero",
      "hadm_id", "subject_id", "tst_patient_id", "stay_id"
    ),
    table1_label_overrides = list(
      APSIII = "APS III,points",
      SAPSII = "SAPS II,points",
      OASIS = "OASIS,points",
      SIRS = "SIRS,points",
      GCS = "GCS,points",
      SOFA = "SOFA,points",
      CHARLSON = "Charlson comorbidity index,points",
      CRRT = "CRRT",
      Ventilation = "Mechanical ventilation",
      Ventilation_Hour = "Mechanical ventilation duration,hours",
      BilirubinTotal = "Total bilirubin,mg/dL",
      PlateletCount = "Platelet count,K/uL",
      UreaNitrogen = "Blood urea nitrogen,mg/dL",
      hosp_day = "Hospital length of stay,days",
      icu_day = "ICU length of stay,days",
      Heart_Failure = "Heart failure",
      Myocardial_Infarction = "Myocardial infarction",
      Acute_Renal_Failure = "Acute kidney injury",
      Malignant_Tumor = "Malignant tumor",
      Liver_cirrhosis = "Liver cirrhosis",
      Marital_Status = "Marital status",
      CalciumTotal = "Total calcium,mg/dL"
    )
  ),

  # tst_stroke: Task4-8 各 R/Python block 共用命名空间
  tst_stroke = list(
    landmarks = c(24L, 48L, 72L, 96L, 120L),
    split = list(train = 0.7, val = 0.2, test = 0.1, seed = 42L),
    sliding_window = TRUE,
    expand_hours = TRUE,
    max_calendar_day = 30L,
    n_hours = 24L,
    temporal_force_skip = TRUE,
    external = list(mode = "synthetic", is_synthetic = TRUE, n = 200L, seed = 42L),
    model_families = c("A1", "A2", "B", "logistic", "xgb", "mlp", "lstm"),
    active_landmark = 72L,
    epochs = 100L,
    worker_epochs = 100L,
    early_stop_patience = 15L,
    python_train_timeout_sec = 43200L,
    summary_primary_landmark = 72L,
    pause_enable = FALSE
  ),

  # 飞书：单跑默认关闭推送（避免 smoke 产生噪音记录）；任务并行模板中默认开启
  feishu = list(
    enable = FALSE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = "RBjfb2iwmamW14s4WhKcS7kwnie",
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "11_IschemicStroke_TwoStageTransformer",
    protocol_label = "two_stage_transformer_stroke",
    project_id = "TST_STROKE_001",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

# 【方法学顺序 — 防泄漏 A2】tst_cohort → tst_split → imputation(fit_on=train) → timeseries → …
pipeline <- list(
  name = "tst_stroke_single",
  blocks = c(
    "data_clean", "column_mapping",
    "tst_cohort", "tst_split", "imputation",
    "tst_timeseries", "baseline_binary", "tst_landmark",
    "tst_repo_a1", "tst_train_eval", "tst_calibration_dca", "tst_shap",
    "tst_external", "tst_literature_validate", "tst_pub_export", "tst_summary_results"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.tst_ck_root, "main"))
)
