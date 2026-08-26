###############################################################################
#  config_cross_lagged_frailty_batch.template.R — 交叉滞后 三库+Pooled
#  复制到研究产出目录后按【必改】修改路径 / 队列。
#  Table 1 三库统一：configs/cross_lagged/table1_harmonized_vars.R
#    （run 入口会按 cross_lagged$table1_harmonize=TRUE 自动套用）
#  决策树: Decisiontree/decision_tree_cross_lagged_frailty.md
###############################################################################

.batch_project_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"  # 【必改】
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")

# 引擎根：模板在 configs/templates/ 下时自动推断；复制到研究区后请改成引擎绝对路径或依赖 run 脚本注入
.engine_root <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[[1]])), winslash = "/")
    if (basename(sp) == "cross_lagged" && basename(dirname(sp)) == "run")
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
  }
  # 模板位于 <engine>/configs/templates/
  here <- tryCatch(normalizePath(".", winslash = "/"), error = function(e) getwd())
  if (basename(here) == "templates" && basename(dirname(here)) == "configs")
    return(normalizePath(file.path(here, "..", ".."), winslash = "/"))
  Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
})

config <- list(
  # 开启后：统一 Table 1，且单因素/VIF screen 仅用 Table 1 特征
  cross_lagged = list(
    table1_harmonize = TRUE,
    univariate_from_baseline_table1 = TRUE
  ),
  # CLPN 网络稳定性（Figure S1/S2；文献 Supp Figs. 25–26；同源脚本 nBoots=1000）
  # pub_figs 阶段默认读取本组；可用 CROSS_LAGGED_BOOT_EDGE/CASE 覆盖（出版勿 <1000）
  cross_lagged_network_bootstrap = list(
    n_boot_edge = 1000L,
    n_boot_case = 1000L,
    nfolds = 10L,
    case_props = seq(0.95, 0.25, by = -0.05),
    seed = 40595747L
  ),
  # 发病敏感性（--phase sensitivity；S9–S17.1 接在 Table S8 之后；仅表）
  # competing_risk：占位；当前无死亡变量 → FALSE（有死亡数据后再开）
  # complete_case：插补前 dabiao + 分析变量 listwise（N 可 < AfterMI）
  cross_lagged_sensitivity = list(
    enable = TRUE,
    competing_risk = FALSE,
    chronic_min_count = 2L,
    chronic_stems = c("hibpe", "diabe", "cancre", "arthre", "lunge", "psyche", "memrye"),
    exclude_event_within_years = 2L,
    scenarios = c("exclude_chronic_ge2", "complete_case", "exclude_event_le_2y")
  ),
  data = list(
    # 运行时由 unit override 指向各库 harmonized dabiao
    rawdata_path = file.path(.batch_project_root, "data/harmonized/D04_CHARLS_hip_baseline.RData"),
    rawdata_obj  = "dabiao",
    outcome_column = "Disease_Group",
    id_column = "ID",
    strip_id_columns_after_imputation = c("ID")
  ),
  project = list(
    name = "Hip_Frailty_cross_lagged",
    disease_code = "16",
    disease = "Hip_fracture",
    literature_pmid = "40595747",
    database = "CHARLS",
    database_type = "regular",
    study_type = "incidence",
    classification_mode = "binary",
    analysis_group = "Hip_Fracture",
    reference_group = "No_Fracture",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  incidence = list(outcome_var = "Disease_Group", index_var = "FI"),
  logistic  = list(index_var = "FI"),
  prediction = list(index_vars = "FI", keep_index_vars_in_regression_table = TRUE),
  index = list(enable = FALSE),
  data_clean = list(missing_threshold = 0.3),
  column_mapping = list(enable = TRUE, database_type = "regular"),
  imputation = list(
    missing_col_threshold = 0.2, method = "cart", m = 5L, max_iter = 5L,
    seed = 1234L, complete_action = 1L
  ),
  # trim_index_extreme：本套路不修剪 FI 极端值（不挂该 block）
  baseline_binary = list(
    sig_cutoff = 0.05,
    strata = "Disease_Group",
    # include/exclude/labels 由 cross_lagged_apply_table1_harmonized() 覆盖写入
    # 同时写入 UV include_predictors：单因素/VIF screen 仅 Table 1 特征
    use_cross_lagged_table1_harmonized = TRUE,
    univariate_from_baseline_table1 = TRUE,
    pause_enable = FALSE,
    pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE
  ),
  # 三库锁定：VIF final 交集 → 若空回退 VIF screen 交集（R/cross_lagged_covariate_lock.R）
  # pooled_bind 运行时由 phase2 注入 model1_locked / model2_locked / lock_source
  cross_lagged_pooled_bind = list(
    country_map = list(CHARLS = "China", ELSA = "UK", HRS = "America"),
    force_country_in_model = TRUE,
    index_var = "FI",
    outcome_column = "Disease_Group",
    id_column = "ID"
  ),
  mediation_longitudinal = list(
    treat = "FI",
    mediator = "Depression_cont",
    outcome = "Disease_Group",
    outcome_event_level = "Hip_Fracture",
    sims = 1000L,
    seed = 1000L,
    diagram_enable = TRUE
  ),
  cross_lagged_long_prepare = list(
    medition_dir = file.path(.batch_project_root, "data/medition"),
    require_baseline_free = TRUE,
    waves = list(
      CHARLS = list(
        x_year = 2011L, m_year = 2013L, y_year = 2015L,
        dep_file = "CHARLS_2013_抑郁.csv", dep_id = "ID", dep_score = "cesd10_total",
        y_outcome_rdata = file.path(.batch_project_root, "data/CHARLS/D03_result_CHARLS_2015.RData")
      ),
      ELSA = list(
        x_wave = 2L, m_wave = 3L, y_wave = 4L,
        dep_file = "ELSA_wave3_抑郁.csv", dep_id = "idauniq", dep_score = "cesd8_total",
        y_outcome_rdata = file.path(.batch_project_root, "data/ELSA/D03_result_ELSA4.RData")
      ),
      HRS = list(
        x_year = 2012L, m_year = 2014L, y_year = 2016L,
        dep_file = "HRS_2014_抑郁.csv", dep_id = "HHID_PN", dep_score = "cesd8_total",
        y_outcome_rdata = file.path(.batch_project_root, "data/HRS/D03_result_HRS16.RData")
      )
    )
  ),
  # Fig2 可标全部交点（rcs_cutoffs_all）；FI_RCS_Group / Table S-XX 只用主 cutoff 二分
  rcs_incidence = list(
    index_var = "FI",
    nk_range = 3:5,
    histbin = 1,
    color_seed = 123,
    group_cutoffs = "primary"
  ),
  # Table S5：自动 2y/≥3y；Table S5.1：output_suffix="_twowave" + design="two_wave"
  #   scheme 由 run 脚本按主文闸门注入；covariates=锁定 Model2
  cross_lagged_change_logistic = list(
    scheme = "tertile",
    covariates = NULL
    # design / output_suffix 由 --phase long_figs 控制
  ),
  study_batch = list(
    output_base = .batch_project_root,
    units = c("CHARLS", "ELSA", "HRS"),
    unit_mode = "cohort",
    # Pooled 不进 pre_vif；由 run 脚本在 VIF 后 bind
    pooled_after_vif = TRUE,
    parallel_workers = "auto",
    skip_existing = TRUE
  )
)

# 阶段 B：仅三单库，到 VIF final（不含 Pooled）
pipeline_unit_pre_vif <- list(
  name = "cross_lagged_pre_vif",
  blocks = c(
    "data_clean", "column_mapping",
    "imputation",
    "baseline_binary",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve",
    "multicollinearity_final"
  ),
  logistic_gate = list(enable = FALSE),
  checkpoint = list(enable = TRUE)
)

# 阶段 D：四路（含 Pooled）logistic / RCS / 亚组 — 不含横断面 mediation_incidence
pipeline_unit_post <- list(
  name = "cross_lagged_post_vif",
  blocks = c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "logistic_quintile_glm_rcs",
    "subgroup_incidence"
  ),
  # 级联：四分位→三分位→二分位→五分位（分离或不显著则降级）；见 R/logistic_gate.R
  logistic_gate = list(enable = TRUE),
  checkpoint = list(enable = TRUE)
)

# 阶段 E：纵向（在 long_prepare 之后）
pipeline_longitudinal <- list(
  name = "cross_lagged_longitudinal",
  blocks = c(
    "cross_lagged_long_prepare",
    "cross_lagged_corr_table",
    "cross_lagged_forest_or",
    "cross_lagged_country_year_bar",
    "cross_lagged_fig1_group",
    "cross_lagged_network",
    "cross_lagged_network_bootstrap",
    "cross_lagged_change_logistic",
    "mediation_longitudinal"
  ),
  checkpoint = list(enable = TRUE)
)

# 兼容旧 batch runner：shared 空 / unit=pre_vif；正式编排见 run 脚本分段
pipeline_shared <- list(
  name = "cross_lagged_shared_noop",
  blocks = character(0),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)
pipeline_unit <- pipeline_unit_pre_vif
pipeline <- pipeline_unit_pre_vif
