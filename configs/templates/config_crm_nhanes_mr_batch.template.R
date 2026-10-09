###############################################################################
#  config_crm_nhanes_mr_batch.template.R — NHANES 单库 CRM × 孟德尔随机化（Batch）
#  三层 batch（共享层 + 任务并行 worker）：obs_main / obs_strata / mr_cvd / mr_ckd / mr_diabetes
#
#  依据：Han et al. 2025 JAHA e038723
#  设计: docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md
#  单次运行版本: configs/templates/config_crm_nhanes_mr.template.R
#  入口: run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R
#  Worker: run/crm_nhanes_mr/run_crm_nhanes_mr_batch_worker.R
#
#  复制到研究产出目录后按【必改】修改；勿改 pipeline_* blocks。
#
#  CLI:
#    Rscript run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --shared-only --no-skip
#    Rscript run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --only-unit obs_main --no-skip
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
.block_repo_root <- .mb_root

# 项目产出根目录固定为 CRM 结果盘目录，不随 --config 所在路径（如 configs/templates）漂移，
# 以确保共享层（无 --config，进程内跑）与 worker 子进程（总是带 --config）读写同一
# checkpoints/_shared/main（否则 worker 会报"共享检查点缺失"）。
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
.crm_project_root <- file.path(.block_result_root, "14_CRM/comorbid_Mendelia_randomization_40145269")

.crm_data_root <- file.path(.crm_project_root, "data/nhanes")

.batch_project_root <- .crm_project_root
.batch_ck_root <- file.path(.batch_project_root, "checkpoints")

config <- list(
  project = list(
    name = "CRM_NHANES_MR_Batch",
    disease = "CRM_NHANES_MR",
    disease_code = "14",
    # prognosis：满足 univariate_prognosis / multivariate_prognosis 硬检查；
    # Han 正表仍为调查加权 OR/Cox（70 块），与筛选链非加权 Cox 刻意分层。
    study_type = "prognosis",
    literature_pmid = "e038723",
    analysis_group = "1",
    reference_group = "0",
    database = "NHANES",
    database_type = "NHANES",
    root = .mb_root,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),

  data = list(
    rawdata_path   = file.path(.crm_data_root, "NHANES_\u6587\u732e_0722.RData"),
    rawdata_obj    = "df",
    id_column      = "SEQN",
    outcome_column = "fustatus",
    strip_id_columns_after_imputation = c("ID", "SEQN", "subject_id")
  ),

  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = TRUE, database_type = "NHANES"),

  # 单库阶段 enable=FALSE：块会跳过；预留双库结构便于日后接 CHARLS/第二库
  dual_db = list(
    enable = FALSE,
    primary = list(name = "NHANES", db_type = "nhanes", column_mapping_type = "NHANES"),
    secondary = list(name = NULL, db_type = NULL, column_mapping_type = NULL),
    harmonization = list(
      sync_after_vif_final = TRUE,
      covariate_source = "auto"
    )
  ),

  survival = list(
    time_var = "futime",
    event_var = "fustatus",
    index_var = "SUA",
    time_unit = "months",
    time_divisor = 1
  ),

  imputation = list(
    missing_col_threshold = 0.40,
    method = "cart",
    m = 5L,
    seed = 1234L,
    mi_quality_exclude_enable = TRUE,
    mi_quality_p_threshold = 0.05,
    export_missing_fig = FALSE,
    export_table_s1 = FALSE,
    pause_enable = FALSE
  ),

  # study_batch$trim_quantile 保留兼容字段；obs 主链不挂 trim_index_extreme

  incidence = list(index_var = "SUA"),

  univariate_prognosis = list(
    sig_cutoff = 0.05,
    screening_cutoff = 0.1,
    pause_enable = FALSE,
    excluded_predictors = c(
      "ID", "SEQN", "subject_id",
      "SUA", "UricAcid", "Uric_Acid", "hyperuricemia", "Hyperuricemia", "gout", "Gout", "gout_proxy",
      "CRM_count", "CVD", "CKD", "Diabetes", "T2DM", "eGFR", "Creatinine",
      "futime", "fustatus", "mortstat", "permth_int", "eligstat",
      "new_Weight", "WTMEC2YR", "SDMVPSU", "SDMVSTRA",
      "MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F"
    )
  ),
  multivariate_prognosis = list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    excluded_predictors = c(
      "ID", "SEQN", "subject_id",
      "SUA", "UricAcid", "Uric_Acid", "hyperuricemia", "Hyperuricemia", "gout", "Gout",
      "CRM_count", "CVD", "CKD", "Diabetes", "T2DM", "eGFR",
      "futime", "fustatus", "mortstat", "permth_int", "eligstat",
      "new_Weight", "WTMEC2YR", "SDMVPSU", "SDMVSTRA"
    )
  ),
  multicollinearity = list(
    vif_threshold_strict = 4,
    vif_threshold_loose = 10,
    pause_enable = FALSE
  ),

  # 不做 SUA cox_quartile/tertile/binary 闸门；筛选出的 Model2Factors 直接进 Han 发表块

  crm_nhanes_pub = list(
    mortality_path = file.path(.crm_data_root, "nhanes-\u6b7b\u4ea1.Rdata"),
    mortality_obj = "combined_data",
    sua_col = "UricAcid",
    # column_mapping 可能写成 Uric_Acid；derive 会自动解析 UricAcid/Uric_Acid/SUA
    # 高尿酸 cut：默认男女同一 7 mg/dL；若核实 Han 2025 JAHA e038723 用男女分层
    # 定义（常见 male=7 / female=6），改用以下两行代替本行（保留本行会被覆盖）：
    #   hyperuricemia_cut_male = 7,
    #   hyperuricemia_cut_female = 6,
    # 本跑自定：男女分层切点 7 / 6 mg/dL（常用临床定义）
    hyperuricemia_cut_male = 7,
    hyperuricemia_cut_female = 6,
    diabetes_col = "T2DM",
    cvd_cols = c("MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F"),
    ckd_rule = "ckd_epi",
    # 本跑自定：CKD-EPI 2021 race-free
    ckd_epi_version = "2021",
    creatinine_col = "Creatinine",
    race_col = "Race",
    weight_col = "WTMEC2YR",
    min_age = 45,
    gout_col = NULL,
    # 数据无痛风列：用 SUA>=8 作痛风样代理（【证据不足】非问卷痛风）
    gout_proxy_sua_cut = 8,
    pause_on_missing_gout = FALSE
  ),

  nhanes = list(
    survey_weight = "new_Weight",
    survey_cluster = "SDMVPSU",
    survey_strata = "SDMVSTRA"
  ),

  dual_incidence_mr = list(
    exposure_var = "SUA",
    crm_outcome_col = "CRM_count",
    time_var = "futime",
    event_var = "fustatus",
    # 原文 Table S2：ebi-a-GCST90018977（UKB EUR n=343836）+ FinnGen R9
    gwas_exposure = "E:/01block/01Block-new-Final/Data/GCST90018977.h.tsv.gz",
    gwas_exposure_path = "E:/01block/01Block-new-Final/Data/GCST90018977.h.tsv.gz",
    exposure_n = 343836L,
    exposure_name = "SUA",
    pval_threshold = 5e-8,
    clump_kb = 10000L,
    clump_r2 = 0.001,
    mr_outcomes = c("CVD", "CKD", "Diabetes"),
    mr_max_snps = NULL,
    mr_f_stat_threshold = 10,
    mendelian_lib_root = "E:/\u5b5f\u5fb7\u5c14",
    plink_bin = "D:/easyMR/MRmyy_refer_file/plink/plink.exe",
    ld_bfile = "D:/easyMR/MRmyy_refer_file/1000G_EUR_Phase3_plink/1000G.EUR.QC",
    ld_clump_per_chr = TRUE,
    reuse_iv_cache = TRUE,
    iv_cache_path = "E:/01block/01Block-new-Final/Data/crm_han2025_iv/SUA_IVs_GCST90018977_p5e-8_kb10000_r0.001.rds",
    outcome_cache_dir = "E:/01block/01Block-new-Final/Data/crm_han2025_r9",
    auto_download_outcomes = FALSE,
    presso_nb = 1000L,
    outcome_map = list(
      CVD = list(
        file = "finngen_R9_FG_CVD.gz",
        url = "https://storage.googleapis.com/finngen-public-data-r9/summary_stats/finngen_R9_FG_CVD.gz",
        ncase = NA_integer_, ncontrol = NA_integer_
      ),
      CKD = list(
        file = "finngen_R9_N14_CHRONKIDNEYDIS.gz",
        url = "https://storage.googleapis.com/finngen-public-data-r9/summary_stats/finngen_R9_N14_CHRONKIDNEYDIS.gz",
        ncase = NA_integer_, ncontrol = NA_integer_
      ),
      Diabetes = list(
        file = "finngen_R9_T2D_WIDE.gz",
        url = "https://storage.googleapis.com/finngen-public-data-r9/summary_stats/finngen_R9_T2D_WIDE.gz",
        ncase = NA_integer_, ncontrol = NA_integer_
      )
    )
  ),

  crm_nhanes_flowchart = list(
    pause_enable = FALSE,
    write_png = FALSE,
    figure_basename = "Figure S1-NHANES-Study_population_flowchart"
  ),
  crm_nhanes_baseline_weighted = list(
    pause_enable = FALSE,
    # 对齐原文补充 Table S4：按高尿酸分层（交付物编号为 Table S3）
    strata_var = "hyperuricemia",
    table_filename = "Table_S4_Baseline_NHANES.csv",
    table_title = paste0(
      "Table S3-NHANES. Baseline characteristics of NHANES participants ",
      "aged ≥45 with and without hyperuricemia"
    )
  ),
  crm_nhanes_ordinal_pub = list(pause_enable = FALSE),
  crm_nhanes_cox_pub = list(pause_enable = FALSE),
  crm_nhanes_rcs_pub = list(
    pause_enable = FALSE,
    write_png = FALSE,
    include_overall = FALSE,
    ncol = 2L,
    figure_basename = "Figure 2-NHANES-RCS_SUA_all-cause_mortality_by_CRM"
  ),
  crm_nhanes_km_pub = list(
    pause_enable = FALSE,
    conf_int = TRUE,
    write_png = FALSE,
    risk_table = FALSE,
    xlab = "Time",
    xlim_max = 160,
    group_labels = c("Non-CRM", "1 CRM", "2 CRM", "3 CRM"),
    force_levels = c(0, 1, 2, 3),
    figure_basename = "Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count",
    figure_caption = "Kaplan-Meier survival curve for all-cause mortality by CRM conditions (NHANES)",
    hr_table_filename = "Table 1-NHANES-KM_Cox_HR_by_CRM_count.csv"
  ),
  crm_nhanes_pub_align = list(pause_enable = FALSE, pause_on_any_fail = FALSE),
  crm_nhanes_subgroup_supp = list(pause_enable = FALSE),
  crm_mr_literature = list(
    pause_enable = FALSE,
    pause_on_download_fail = FALSE,
    pause_on_few_ivs = FALSE,
    pause_min_ivs = 10L,
    outcome_key = NULL
  ),

  crm_nhanes_pub_deliverables = list(
    pause_enable = FALSE,
    deliverables_dirname = "NHANES_pub_deliverables"
  ),

  study_batch = list(
    output_base = .batch_project_root,
    project_root = .block_repo_root,
    units = c("obs_main", "obs_strata", "mr_cvd", "mr_ckd", "mr_diabetes"),
    unit_mode = "branch",
    parallel_workers = "auto",
    skip_existing = TRUE,
    trim_quantile = 0.01,
    worker_script = "run/crm_nhanes_mr/run_crm_nhanes_mr_batch_worker.R",
    shared_ck_alias = "crm_nhanes_derive",
    # 全部 unit 成功后折叠正式交付物（白名单）
    finalize_blocks = c("crm_nhanes_pub_deliverables"),
    branch_map = list(
      obs_main = list(blocks = c(
        # 预后观测主链不修剪 SUA 极端值（不挂 trim_index_extreme）
        "imputation",
        "univariate_prognosis", "multicollinearity_screen",
        "crm_multivariate_prognosis", "multicollinearity_final",
        "dual_db_covariate_harmonize",
        "crm_nhanes_flowchart", "crm_nhanes_baseline_weighted",
        "crm_nhanes_ordinal_pub", "crm_nhanes_cox_pub", "crm_nhanes_rcs_pub",
        "crm_nhanes_km_pub", "crm_nhanes_pub_align"
      )),
      obs_strata = list(blocks = c("crm_gout_strata", "crm_nhanes_subgroup_supp")),
      mr_cvd = list(blocks = c("crm_mr_literature")),
      mr_ckd = list(blocks = c("crm_mr_literature")),
      mr_diabetes = list(blocks = c("crm_mr_literature"))
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
    disease_label = "14_CRM_NHANES_MR",
    protocol_label = "crm_nhanes_mr",
    project_id = "14_crm_nhanes_mr_038723",
    workplan_code = "B30",
    owner_default = Sys.getenv("FEISHU_OWNER", ""),
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

pipeline_shared <- list(
  name = "crm_nhanes_mr_shared",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "crm_nhanes_derive"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "main"))
)

pipeline_unit <- list(
  name = "crm_nhanes_mr_unit",
  blocks = character(0),  # 按 study_batch$branch_map[[unit]]$blocks 在 worker 内填充
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
