###############################################################################
#  config_ssd_lpa_network_mediation.template.R
#  地基：发病前缀 + 方法后缀（LPA / CFA / 平行竞争中介 / 剖面网络 / ROC+DCA）
#  文献方法源：Ma 2026 Acta Psychol PMID 42214160（管道迁移+实质重设）
#  决策树：Decisiontree/decision_tree_ssd_lpa_network_mediation.md
#
#  用法:
#    "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#      run/ssd_lpa_network_mediation/run_ssd_lpa_network_mediation.R \
#      --config <本文件或课题 config>
#  冒烟: SSD_MED_SIMS=50 SSD_NET_BOOTS=20
###############################################################################

.resolve_batch_path <- function(p) {
  p <- as.character(p)[1L]
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || file.exists(wsl) || dir.exists(dirname(wsl))) return(wsl)
  }
  p
}

.project_root <- .resolve_batch_path(
  "G:/02block_result/63_SSD/LPA_Network_Mediaton_42214160"
)
.data_csv <- file.path(.project_root, "data", "201804_complete.csv")
.out_dir <- file.path(.project_root, "by_index", "main_full_sample")

# 年龄切点依据：成人门诊功能残疾文献常用 65；无病种特异亚组 RCT 时用默认 65
.age_cut <- 65L

.likert_whodas <- c(
  "no" = 0, "small" = 1, "moderate" = 2, "severe" = 3,
  "very severe or unable" = 4
)
.likert_ssd12 <- c(
  "never" = 0, "seldom" = 1, "sometimes" = 2, "often" = 3, "always" = 4
)
.likert_whiteley <- c(
  "no" = 0, "a little" = 1, "some" = 2, "often" = 3, "severe" = 4
)
.likert_phq15 <- c("No" = 0, "no" = 0, "some" = 1, "a lot" = 2)
.likert_sss8 <- c(
  "no" = 0, "little" = 1, "some" = 2, "a lot" = 3, "severe" = 4
)
.likert_phq9 <- c(
  "no" = 0, "a few days" = 1, "more than half days" = 2, "almost everyday" = 3
)

config <- list(
  project = list(
    name = "SSD_LPA_Network_Mediation",
    disease = "Somatic_Symptom_Disorder",
    disease_cn = "躯体症状障碍/功能残疾",
    database = "Hospital_outpatient",
    study_type = "incidence",
    classification_mode = "multiclass",
    analysis_group = "SSD",
    reference_group = "Non_SSD",
    output_dir = .out_dir,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path = .data_csv,
    rawdata_obj = NULL,
    outcome_column = "WHODAS",
    id_column = "row_id",
    strip_id_columns_after_imputation = character(0)
  ),

  plot = list(font_family = "Times New Roman"),

  # 完整病例主分析（对齐对抗阅读 Q5）；另做 MI 时改 method
  imputation = list(
    method = "none",
    m = 5L,
    rubin_pool = FALSE,
    complete_action = 1L,
    seed = 1234L
  ),

  data_clean = list(
    missing_threshold = 0.5,
    age_filter = NULL,
    drop_columns = NULL
  ),

  analysis_exclusion = list(
    allow_no_index = TRUE,
    # 诊断标记 / 疾病相关：不进回归协变量池；可用 protect 保留分层列
    disease_vars = c("SSD", "BDS", "therapy", "satisfaction", "effect"),
    protect_vars = c("SSD"),
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  psychometrics_scale_score = list(
    write_to = c("cleaned", "raw"),
    scales = list(
      list(
        name = "PHQ15", items = paste0("PHQ15", 1:15),
        value_map = .likert_phq15, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "SSS8", items = paste0("SSS8", 1:8),
        value_map = .likert_sss8, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "SSD12", items = paste0("SSD12", 1:12),
        value_map = .likert_ssd12, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "Whiteley8",
        items = c("WHITELEY", paste0("WHITELE", 1:7)),
        value_map = .likert_whiteley, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "WHODAS", items = paste0("DAS", 1:12),
        value_map = .likert_whodas, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "PHQ9", items = paste0("PHQ9", 1:9),
        value_map = .likert_phq9, na_rm = TRUE, write_items = TRUE
      ),
      list(
        name = "GAD7", items = paste0("GAD7", 1:7),
        value_map = .likert_phq9, na_rm = TRUE, write_items = TRUE
      )
    )
  ),

  # LPA：DAS1–12；复合选模 = BIC + 极小类门槛（Q1）
  latent_profile = list(
    items = paste0("DAS", 1:12),
    n_profiles_max = 5L,
    min_class_n = 30L,
    min_class_prop = 0.04,
    seed = 1234L,
    class_col = "LPA_class"
  ),

  analysis_var_policy = list(
    min_categorical_n = 5L
  ),

  baseline_multiclass = list(
    strata = "LPA_class_label",
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE,
    include_vars = c(
      "age", "sex", "education", "marriage", "income", "livingsite",
      "occupation", "center", "department", "height", "weight",
      "PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7",
      "SSD", "N12AA"
    ),
    exclude_vars = c("number", "BirthYear", "yearmonth", "LPA_class", "row_id")
  ),

  sem_cfa_discriminant = list(
    factor_a = list(name = "SSD12", items = paste0("SSD12", 1:12)),
    factor_b = list(
      name = "Whiteley",
      items = c("WHITELEY", paste0("WHITELE", 1:7))
    ),
    estimator = "MLR"
  ),

  # 预声明调整集（Q4）：人口学；情绪共变（PHQ9/GAD7）默认不进主中介，敏感性另开
  parallel_competing_mediation = list(
    exposure = "PHQ15",
    mediators = c("SSD12", "Whiteley8"),
    outcome = "WHODAS",
    covariates = c("age", "sex", "education", "marriage", "income", "livingsite"),
    sims = 5000L,
    seed = 1234L,
    compare_indirect = TRUE
  ),

  complex_network_profile_batch = list(
    class_col = "LPA_class",
    # 节点规模门控：量表总分块（症状 / 认知恐惧 / 功能 / 情绪）
    nodes = c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7"),
    min_n = 30L,
    gamma = 0.5,
    n_boots = 200L,
    include_overall = TRUE
  ),

  clinical_threshold_dca = list(
    predictors = c("SSD12", "Whiteley8", "PHQ15", "SSS8"),
    outcome_continuous = "WHODAS",
    outcome_cut = "median",
    thresholds = seq(0.05, 0.95, by = 0.05)
  ),

  correlation = list(
    vars = c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7"),
    method = "spearman"
  ),

  subgroup = list(
    age_cutoff = .age_cut,
    level_order = list(Age_Group = c("< 65", "\u2265 65"))
  ),

  pub_digits = list(
    est = 3L, p = 3L, desc = 3L, cutoff = 3L,
    int_big_mark = TRUE, desc_trim = TRUE, p_style = "fixed"
  ),

  pub_figures = list(
    export_png = FALSE,
    export_tiff = FALSE
  ),

  feishu = list(
    enable = TRUE,
    disease_label = "SSD功能残疾",
    protocol_label = "LPA_Network_平行竞争中介_42214160"
  ),

  seed = 1234L
)

pipeline <- list(
  blocks = c(
    "data_clean",
    "psychometrics_scale_score",
    "analysis_exclusion",
    "latent_profile_tidylpa",
    "baseline_multiclass",
    "sem_cfa_discriminant",
    "parallel_competing_mediation",
    "complex_network_profile_batch",
    "clinical_threshold_dca",
    "correlation"
  ),
  checkpoint = list(
    dir = file.path(.out_dir, "checkpoints"),
    enable = TRUE
  )
)
