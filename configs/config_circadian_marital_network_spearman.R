###############################################################################
#  CHARLS 2015 婚姻质量 × CircS 症状式网络（Spearman 重跑）
#  与「婚姻质量」Pearson 版同数据；输出目录加 Spearman 尾缀，不改原文件夹。
#  相关：Spearman + pairwise.complete.obs；必要时 nearPD → EBICglasso(γ=0.5)
#  入口: run/clhls_symptom_network/run_clhls_symptom_network.R --config 本文件
###############################################################################

.out_root <- "G:/02block_result/23_circadian rhythm/Complex_network/婚姻质量 Spearman"
.ck_root  <- file.path(.out_root, "checkpoints")
.cohort   <- file.path(.out_root, "data", "CHARLS_2015_marital_circadian_network.csv")

.node_items <- c(
  mqual = "Marital quality (1-5; higher = worse)",
  circ1 = "Central obesity",
  circ2 = "Elevated blood pressure",
  circ3 = "Elevated glucose",
  circ4 = "Elevated triglycerides",
  circ5 = "Reduced HDL-C",
  circ6 = "Depressive symptoms",
  circ7 = "Short sleep"
)
.communities <- list(
  MaritalQuality = "mqual",
  Circadian = paste0("circ", 1:7)
)
.short_labels <- c("M", paste0("C", 1:7))

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
    name = "CHARLS_Marital_Circadian_Network_Spearman",
    disease_code = "23",
    disease = "Circadian_rhythm",
    literature_pmid = "",
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
    cor_method = "spearman",
    cor_use = "pairwise.complete.obs",
    ebic_gamma = 0.5,
    n_boots = 1000L,
    nct_it = 1000L,
    n_cores = max(1L, parallel::detectCores() - 1L),
    sex_col = "sex",
    male_code = "1",
    female_code = "2",
    figure1_stem = "Figure 1. Marital quality and circadian component network",
    table1_stem = "Table 1. Basic information of network nodes"
  ),
  pub_figures = list(dpi = 600L),
  pub = list(renumber = FALSE, auto_qc = TRUE),
  feishu = list(enable = FALSE)
)

# 不跑性别亚组（与当前交付口径一致）
pipeline <- list(
  name = "circadian_marital_network_spearman",
  blocks = c(
    "data_clean",
    "column_mapping",
    "imputation",
    "clhls_symptom_ingest",
    "clhls_network",
    "clhls_centrality",
    "clhls_weighted",
    "clhls_bridge",
    "clhls_stability",
    "clhls_network_pub"
  ),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.ck_root, "main"))
)
