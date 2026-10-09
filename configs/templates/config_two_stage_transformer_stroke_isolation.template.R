###############################################################################
#  config_two_stage_transformer_stroke_isolation.template.R
#  缺血性脑卒中两阶段 Transformer — 任务并行（5006 程序员隔离模式）
#
#  复制 studies/_template_tst/ 后改 <TO_CONFIRM*>；勿改 pipeline_* blocks。
#  入口: run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R
#  决策树: docs/Decisiontree/decision_tree_two_stage_transformer_stroke.md
#  完整引擎模板: configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R
#
#  CLI:
#    run_study.bat <研究名> --routine tst --shared-only
#    run_study.bat <研究名> --routine tst --workers 2 --only-unit L72_B_twostage
#    run_study.bat <研究名> --routine tst --list-units
###############################################################################

.mb_root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

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
.batch_data_root <- file.path(.batch_project_root, "Data")
.tst_ck_root     <- file.path(.batch_project_root, "checkpoints")
.tst_output_root <- .batch_project_root

# <TO_CONFIRM_DATA>：相对 Data/mimic/ 的文件名
.baseline_rdata <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_BASELINE_RDATA>")
.lab_csv        <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_LAB_CSV>")
.prognosis_csv  <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_PROGNOSIS_CSV>")
.dabiao_csv     <- file.path(.batch_data_root, "mimic/<TO_CONFIRM_DABIAO_CSV>")

config <- list(
  project = list(
    name = "<TO_CONFIRM_PROJECT_NAME>",          # ❓ TwoStage_Transformer_Stroke
    disease = "<TO_CONFIRM_DISEASE>",             # ❓ IschemicStroke_TwoStageTransformer
    disease_code = "<TO_CONFIRM_CODE>",           # ❓ 11
    study_type = "prognosis",
    literature_pmid = "<TO_CONFIRM_PMID>",        # ❓ pbaf003
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
    rawdata_path = .baseline_rdata,
    rawdata_obj  = "<TO_CONFIRM_RAWDATA_OBJ>",    # ❓ baseline
    baseline_id_column = "ID",
    id_column = "stay_id",
    lab_long_path  = .lab_csv,
    prognosis_path = .prognosis_csv,
    dabiao_path    = .dabiao_csv,
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
    exclude_vars = c(
      "admit_time", "disch_time", "icu_intime", "icu_outtime", "tst_time_zero",
      "hadm_id", "subject_id", "tst_patient_id", "stay_id"
    )
  ),

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
    ablation_variants = c("mask", "structure"),
    epochs = 100L,
    worker_epochs = 100L,
    early_stop_patience = 15L,
    python_train_timeout_sec = 43200L,
    max_workers = 4L,
    ram_per_worker_gb = 4.0,
    finalize_blocks = c("tst_literature_validate", "tst_pub_export", "tst_summary_results"),
    summary_primary_landmark = 72L,
    expand_full_matrix = TRUE,
    pause_enable = FALSE,
    branch_map = list(
      external_synthetic = list(
        blocks = c("tst_external"), python_mode = "tst_external_synthetic"
      ),
      temporal_holdout = list(
        blocks = c("tst_split", "tst_train_eval"), python_mode = "tst_train_b", temporal = TRUE
      )
    )
  ),

  # 程序员隔离默认关飞书；需要时改为 TRUE 并配 .env.feishu
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

task_units <- character(0)

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
  blocks = character(0),
  checkpoint = list(enable = TRUE)
)

config$pipeline_unit <- pipeline_unit
pipeline <- pipeline_shared
