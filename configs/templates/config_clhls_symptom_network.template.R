###############################################################################
#  config_clhls_symptom_network.template.R — 复制后改【必改】路径
#  正式实例: configs/config_clhls_symptom_network.R
###############################################################################

# 【必改】产出根目录
.out_root <- "G:/02block_result/22_depression/Complex_network测试"
.ck_root  <- file.path(.out_root, "checkpoints")

# 【必改】节点列名 = 条目说明；社区名 = 这些列的分组。不要写进 block。
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
    study_type = "cross_sectional",
    output_dir = .out_root,
    root = normalizePath(getwd(), winslash = "/")
  ),
  clhls_network = list(
    # 【必改】2028 人复现队列 csv
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
    workplan_code = "B14"
  )
)

pipeline <- list(
  name = "clhls_symptom_network",
  blocks = c(
    "data_clean", "column_mapping", "imputation",
    "clhls_symptom_ingest", "clhls_network", "clhls_centrality", "clhls_weighted",
    "clhls_bridge", "clhls_sex", "clhls_sex_nct", "clhls_stability", "clhls_network_pub"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.ck_root, "main"))
)
