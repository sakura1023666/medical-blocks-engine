# 数据库池化 / BlendedLoS batch 模板
# 文献：Allyn et al. Critical Care 2026;30:364 (DOI 10.1186/s13054-026-06034-5)
# 公开代码：https://github.com/CIC-1410/BlendedLoS
# 地基：预后 survival + 方法后缀（多源池化/迁移/TPC）
# 决策树：Decisiontree/decision_tree_database_pooling.md

.root <- if (exists("MEDICAL_BLOCKS_ROOT") && nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  Sys.getenv("MEDICAL_BLOCKS_ROOT")
} else {
  normalizePath(getwd(), winslash = "/")
}

config <- list(
  project = list(
    name = "database_pooling_blendedlos",
    root = .root,
    # 结果目录：请改为课题 Output，勿覆盖既有 【success】 项目
    output_dir = file.path(
      "/mnt/g/02block_result/48_ICU/database_pooled_42151996",
      "Output_database_pooling"
    ),
    database = "BlendedICU_4DB",
    use_step_prefixed_block_dirs = TRUE
  ),

  # Windows Rscript（用户指定）
  rscript = "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe",

  dbpool = list(
    enable = TRUE,
    # 四库协调底座在 Aiya-Linux 192.168.68.29，官方原库已跑过 BlendedICU。
    # 别的课题复用这一步，不要重抽原库：
    #   blendedicu_base  = 协调长表（labels / long_timeseries / long_medication）
    #   blendedicu_ready = 每人一张小时宽表，给 BlendedLoS 或其它下游
    # 展开命令：run/database_pooling/run_blendedicu_hourly.sh
    blendedicu_base = "/mnt/sda/BlendedICU/data/blended_data",
    blendedicu_ready = "/mnt/sda/BlendedICU/data/blendedlos_ready",
    # RealExtraction 只作本机没有 29 协调库时的后备
    data_root = "/mnt/g/02block_result/48_ICU/database_pooled_42151996/data/RealExtraction_4DB_20261009",
    blended_out = file.path(
      "/mnt/g/02block_result/48_ICU/database_pooled_42151996",
      "Output_database_pooling", "blendedICU_adapted"
    ),
    python_bin = file.path(.root, ".venv_dbpool", "bin", "python"),
    # 公开代码 canonical 路径（默认同 Blocks/78/.../upstream/BlendedLoS）
    upstream_dir = file.path(.root, "Blocks/78_database_pooling_full/upstream/BlendedLoS"),
    split_seed = 974L,
    run_upstream_split = TRUE,
    run_generate_tables = TRUE,
    dry_run = FALSE,
    # 冒烟：设为正整数限制每库 stay 数；正式跑设 NULL
    smoke_max_stays_per_db = NULL,
    train_timeout_sec = 172800L,
    adapt_timeout_sec = 86400L,
    default_unit = "expD_pooled_mimic_amumc",
    # 损失权重 / RLoS cap / 训练超参（对齐 BlendedLoS 公开 config.py 默认）
    alpha = 20,
    rlos_cap_days = 10,
    train_ratio = 0.70,
    val_ratio = 0.15,
    test_ratio = 0.15,
    # 文献级默认；仅冒烟/调试设 TRUE（40 epoch / batch 64）
    fast_train = FALSE,
    literature_mode = TRUE,
    n_epochs = 200L,
    batch_size = 32L,
    # 下面四项留 NULL 就是全文口径。缩小样本时再填整数，例如：
    #   stays_per_db = 640L      每个库、每个划分最多这么多次住院
    #   max_n_batch = 24L        每个 epoch 最多这么多个 batch
    #   n_epochs 已在上面，改小即缩短上限；早停仍是验证集 5 轮
    #   percentage_test = 100L   测试集使用比例，公开代码默认 100
    stays_per_db = NULL,
    max_n_batch = NULL,
    percentage_test = 100L
  ),

  # 并行实验单元（Fig.1 / Table2–3 / S2 / Fig.2）
  task_units = c(
    "expA_amumc_solo",
    "expB_mimic_solo",
    "expC_mimic2amumc_transfer",
    "expD_pooled_mimic_amumc",
    "model_benchmark",
    "dataset_benchmark",
    "training_size_study"
  ),

  pub_digits = list(
    est = 3L, p = 3L, desc = 3L, cutoff = 3L,
    int_big_mark = TRUE, desc_trim = TRUE
  ),

  feishu = list(
    enable = TRUE,
    app_token = "RBjfb2iwmamW14s4WhKcS7kwnie",
    # 由 run/feishu/run_feishu_setup_database_pooling_tables.R 生成后回填
    table_id = "",
    table_success_id = "",
    table_failure_id = "",
    table_routine_id = "",
    disease_label = "48_ICU_DatabasePooling_BlendedLoS",
    protocol_label = "database_pooling",
    project_id = "DBPOOL_001"
  ),

  pub = list(auto_qc = TRUE)
)

# 可选：课题 live config 覆盖
# source("configs/studies/database_pooling/xxx.R")
