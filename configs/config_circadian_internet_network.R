###############################################################################
#  CHARLS 2015 互联网设备多样性 × 昼夜节律综合征 症状式网络
#  暴露社区 = 台式/笔记本/平板/手机；其他设备阳性仅 2 人，不作为节点。结局社区 = CircS 七组分。
#  入口: run/clhls_symptom_network/run_clhls_symptom_network.R --config 本文件
###############################################################################

.out_root <- "G:/02block_result/23_circadian rhythm/Complex_network/Internet diversity"
.ck_root  <- file.path(.out_root, "checkpoints")
.cohort   <- file.path(.out_root, "data", "CHARLS_2015_internet_circadian_network.csv")

.node_items <- c(
  dev1 = "Desktop computer",
  dev2 = "Laptop",
  dev3 = "Tablet",
  dev4 = "Mobile phone",
  circ1 = "Central obesity",
  circ2 = "Elevated blood pressure",
  circ3 = "Elevated glucose",
  circ4 = "Elevated triglycerides",
  circ5 = "Reduced HDL-C",
  circ6 = "Depressive symptoms",
  circ7 = "Short sleep"
)
.communities <- list(
  InternetDiversity = paste0("dev", 1:4),
  Circadian = paste0("circ", 1:7)
)
.short_labels <- c(paste0("I", 1:4), paste0("C", 1:7))

config <- list(
  data = list(
    rawdata_path = .cohort,
    outcome_column = "age",
    id_column = "ID"
  ),
  data_clean = list(
    missing_threshold = 0.2,
    skip_hematology_scale = TRUE,
    never_drop_columns = c(names(.node_items), "sex", "ID", "age")
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
    name = "CHARLS_Internet_Circadian_Network",
    disease_code = "23",
    disease = "Circadian_rhythm",
    literature_pmid = "39780094",
    database = "CHARLS",
    database_type = "regular",
    study_type = "cross_sectional",
    output_dir = .out_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = normalizePath(getwd(), winslash = "/")
  ),
  clhls_network = list(
    cohort_csv = .cohort,
    node_items = .node_items,
    communities = .communities,
    short_labels = .short_labels,
    ebic_gamma = 0.5,
    n_boots = 1000L,
    nct_it = 1000L,
    n_cores = max(1L, parallel::detectCores() - 1L),
    sex_col = "sex",
    male_code = "1",
    female_code = "2",
    figure1_stem = "Figure 1. Internet diversity and circadian component network",
    table1_stem = "Table 1. Basic information of network nodes"
  ),
  pub_figures = list(dpi = 600L),
  pub = list(renumber = FALSE, auto_qc = TRUE),
  feishu = list(enable = FALSE)
)

pipeline <- list(
  name = "circadian_internet_network",
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
