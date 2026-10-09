###############################################################################
#  config_two_stage_transformer_stroke_task_parallel.template.R
#  缺血性脑卒中两阶段 Transformer 双轨 — 任务并行（共享层 1 次 + Worker 并行）
#
#  依据: Yang et al. 2025 Precision Clinical Medicine pbaf003
#  设计: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md
#  决策树: Decisiontree/decision_tree_two_stage_transformer_stroke.md
#  单跑版本: configs/templates/config_two_stage_transformer_stroke.template.R
#  入口: run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R
#  Worker: run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_worker.R
#  Runner（Task7 交付）: R/tst_stroke_task_runner.R ::
#    tst_stroke_run_task_parallel(root, config, pipeline_shared, units, workers)
#
#  复制到研究产出目录后按【必改】修改；勿改 pipeline_* blocks。
#
#  CLI:
#    Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --shared-only
#    Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R \
#      --only-unit L72_B_twostage,external_synthetic --workers 2
#    Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --list-units
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

# 研究产出根（\\192.168.68.133\02block_result\...\two_stage_transformer_40041421）
# 固定到结果盘，不随 configs/templates 路径漂移（与 CRM batch 同策略）。
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

# 全部结果写到研究产出根（by_unit / checkpoints / logs / Tables），禁止写仓库 Output/
.tst_output_root <- .tst_project_root
.tst_ck_root      <- file.path(.tst_output_root, "checkpoints")

config <- list(
  project = list(
    name = "TwoStage_Transformer_Stroke_TaskParallel",
    disease = "IschemicStroke_TwoStageTransformer",
    disease_code = "11",
    study_type = "prognosis",
    literature_pmid = "pbaf003",
    analysis_group = "1",
    reference_group = "0",
    database = "MIMIC",
    database_type = "MIMIC",
    root = .mb_root,
    output_dir = .tst_output_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = FALSE
  ),

  data = list(
    rawdata_path = file.path(.tst_data_root, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData"),
    rawdata_obj  = "baseline",
    baseline_id_column = "ID",
    id_column = "stay_id",
    lab_long_path  = file.path(.tst_data_root, "mimic-\u5b9e\u9a8c\u5ba4\u6307\u6807-all-1~30\u5929.csv"),
    prognosis_path = file.path(.tst_data_root, "mimic\u9884\u540e\u6570\u636e-all.csv"),
    dabiao_path    = file.path(.tst_data_root, "dabiao.csv"),  # 缺血性卒中 stay 名单（必需）
    outcome_column = "is_hosp_dead",
    admission_time_column = "icu_intime"
  ),

  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = TRUE, database_type = "MIMIC"),

  imputation = list(
    missing_col_threshold = 0.30,  # 缺失率>30% 的列剔除后再插补（仅入选队列）
    method = "rf",                 # 静态特征：随机森林插补（对齐原文 Methods）
    m = 5L,
    seed = 1234L,
    # A2 铁律：仅训练集拟合；val∪test 用 mice(ignore=TRUE) 套用（禁止 val/test 各自重拟合）
    fit_on = "train",
    complete_action = 1L,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE,
    pause_enable = FALSE
  ),

  # 纵向：day1 缺失>30% 剔特征；再在保留特征×前5天上、前向填前剔患者缺失>30%；然后前向填充
  tst_timeseries = list(
    feature_missing_threshold = 0.30,
    density_gate_apply_coverage_drop = TRUE,
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

  # Table1：需 sig_cutoff；显著变量过少时不 pause
  baseline_binary = list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_min_sig_vars = FALSE,
    pause_on_table1_fail = FALSE,
    exclude_vars = c(
      "admit_time", "disch_time", "icu_intime", "icu_outtime", "tst_time_zero",
      "hadm_id", "subject_id", "tst_patient_id", "stay_id"
    )
  ),

  tst_stroke = list(
    landmarks = c(24L, 48L, 72L, 96L, 120L),
    split = list(train = 0.7, val = 0.2, test = 0.1, seed = 42L),
    # 方案 A：日级对齐增强
    sliding_window = TRUE,
    expand_hours = TRUE,          # 每日快照广播到 24 小时槽（【场景迁移】）
    max_calendar_day = 30L,
    n_hours = 24L,
    temporal_force_skip = TRUE,   # MIMIC 去标识日期；对齐原文「地理外推非时间外」
    external = list(mode = "synthetic", is_synthetic = TRUE, n = 200L, seed = 42L),
    model_families = c("A1", "A2", "B", "logistic", "xgb", "mlp", "lstm"),
    ablation_variants = c("mask", "structure"),
    # 对齐原文约 100 epoch + 早停（A3：patience 盯验证集 val_auc，非 val_loss）
    epochs = 100L,
    worker_epochs = 100L,
    early_stop_patience = 15L,
    early_stop_monitor = "val_auc",
    # A4：Two-stage = 小时级 Transformer → 日级 Transformer（架构）；非两阶段训练流程；
    #     arch B 可另加 tabular fusion，但“两阶段”不指表格+时序两路
    # CPU 训练易超 1h；system2 exit=124=超时。默认 12h，可按机器调大/调小
    python_train_timeout_sec = 43200L,
    max_workers = 4L,
    ram_per_worker_gb = 4.0,
    finalize_blocks = c("tst_literature_validate", "tst_pub_export", "tst_summary_results"),
    # summary_results 主文图默认 landmark（小时）；每项目尾段必出 summary_results/
    summary_primary_landmark = 72L,
    expand_full_matrix = TRUE,
    pause_enable = FALSE,
    # A 轨：A1=公开单截止；A2=规范单阶段多截止；B=两阶段多截止（双轨复现方案）
    branch_map = list(
      external_synthetic = list(
        blocks = c("tst_external"), python_mode = "tst_external_synthetic"
      ),
      temporal_holdout = list(
        blocks = c("tst_split", "tst_train_eval"), python_mode = "tst_train_b", temporal = TRUE
      )
    )
  ),

  feishu = list(
    enable = TRUE,
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

# task_units：expand_full_matrix=TRUE 时由 expander 在入口脚本 source 后填充。
# 子集 smoke 示例：--only-unit L72_B_twostage,external_synthetic
task_units <- character(0)

# 【方法学顺序 — 防泄漏 A2】
# 1) dabiao 内连接 + 预后 → tst_cohort
# 2) 患者级 7:2:1（tst_split）→ 物化 train / (val∪test)
# 3) MICE fit_on=train，holdout 仅套用（mice ignore）
# 4) 纵向 timeseries（静态广播用插补后基线）→ baseline → landmark
# 5) Python：expand_hours / true_hourly + Day-k；训练 100 epoch + early stop(val_auc, patience=15)
# 6) A1/A2/B：A4 两阶段=小时→日架构；B 可另加 tabular fusion
pipeline_shared <- list(
  name = "tst_stroke_shared",
  blocks = c(
    "data_clean", "column_mapping",
    "tst_cohort", "tst_split", "imputation",
    "tst_timeseries", "baseline_binary", "tst_landmark"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.tst_ck_root, "_shared", "main"))
)

pipeline_unit <- list(
  name = "tst_stroke_unit",
  blocks = character(0),  # 按 config$tst_stroke$branch_map[[unit]]$blocks 在 worker 内填充（Task7）
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
