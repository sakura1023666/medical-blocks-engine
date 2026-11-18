###############################################################################
#  config_clhls_symptom_network.R — CLHLS 抑郁×焦虑症状网络（Chang 2025）
#  决策树: Decisiontree/decision_tree_clhls_symptom_network.md
#  入口: run/clhls_symptom_network/run_clhls_symptom_network.R
#  Block: Blocks/81_clhls_symptom_network_full/
###############################################################################

# Windows R-4.5.1 必须用盘符路径；勿写 /mnt/g（会被当成 E:/mnt/g/...）
.out_root <- "G:/02block_result/22_depression/Complex_network测试"
.ck_root  <- file.path(.out_root, "checkpoints")

# 节点、条目说明、社区只放在本课题 config。block 不写死 CESD/GAD。
.clhls_node_items <- c(
  CESD1 = "Feeling bothered", CESD2 = "Trouble focus", CESD3 = "Feeling depressed",
  CESD4 = "Trouble doing anything", CESD5 = "Hopelessness", CESD6 = "Felt fearful",
  CESD7 = "Lack of happiness", CESD8 = "Loneliness", CESD9 = "Inability to get going",
  CESD10 = "Sleep quality",
  GAD1 = "Nervousness or anxiety", GAD2 = "Uncontrollable worry", GAD3 = "Generalized worry",
  GAD4 = "Trouble relaxing", GAD5 = "Restlessness", GAD6 = "Irritability",
  GAD7 = "Fear of horrible events"
)
.clhls_communities <- list(
  Depression = paste0("CESD", 1:10),
  Anxiety = paste0("GAD", 1:7)
)
.clhls_short_labels <- c(paste0("D", 1:10), paste0("A", 1:7))

config <- list(
  data = list(
    rawdata_path = file.path(.out_root, "data", "CLHLS-复杂网络-复现队列_2028.csv"),
    outcome_column = "CESD1",
    id_column = "id"
  ),

  # 发病套路前三步：清洗 → 列映射（本课题关闭改名）→ 插补。网络块读 ctx$data$imputed。
  data_clean = list(
    missing_threshold = 0.2,
    skip_hematology_scale = TRUE,
    never_drop_columns = c(names(.clhls_node_items), "sex", "id")
  ),
  column_mapping = list(enable = FALSE),
  imputation = list(
    missing_col_threshold = 0.2,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE,
    m = 1L,
    max_iter = 1L
  ),

  project = list(
    name = "CLHLS_Symptom_Network",
    disease_code = "14",
    disease = "Depression_Anxiety_Network",
    literature_pmid = "39780094",
    database = "CLHLS",
    database_type = "regular",
    study_type = "cross_sectional",
    output_dir = .out_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),

  clhls_network = list(
    cohort_csv = file.path(.out_root, "data", "CLHLS-复杂网络-复现队列_2028.csv"),
    node_items = .clhls_node_items,
    communities = .clhls_communities,
    short_labels = .clhls_short_labels,
    ebic_gamma = 0.5,
    n_boots = 1000L,
    nct_it = 1000L,
    n_cores = max(1L, parallel::detectCores() - 1L),
    sex_col = "sex",
    male_code = "1",
    female_code = "2"
  ),

  pub_figures = list(dpi = 600L),
  # 本套路表号已按文献 Table 1–3 固定命名，禁止引擎顺延改号
  pub = list(renumber = FALSE, auto_qc = TRUE),

  feishu = list(
    enable = TRUE,
    app_id = Sys.getenv("FEISHU_APP_ID", ""),
    app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
    app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
    table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
    table_success_id = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""),
    table_failure_id = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""),
    disease_label = "14_Depression_Anxiety_Network",
    protocol_label = "clhls_symptom_network",
    project_id = "14_clhls_symptom_network_39780094",
    literature_default = "CLHLS depression-anxiety symptom network (Chang 2025 BMC Psychiatry)",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE,
    workplan_code = "B14"
  )
)

pipeline <- list(
  name = "clhls_symptom_network",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "clhls_symptom_ingest",
    "clhls_network",
    "clhls_centrality",
    "clhls_weighted",
    "clhls_bridge",
    "clhls_sex",
    "clhls_sex_nct",
    "clhls_stability",
    "clhls_network_pub"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.ck_root, "main"))
)
