###############################################################################
#  config_crm_nhanes_mr.template.R — NHANES 单库 CRM × 孟德尔随机化（Han 2025 JAHA）
#  单次运行（非 batch）：串行跑 obs_main 全套 70_crm_nhanes_pub 链
#
#  依据：Han et al. 2025 JAHA e038723
#  设计: docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md
#  Batch 版本: configs/templates/config_crm_nhanes_mr_batch.template.R
#  入口: run/crm_nhanes_mr/run_crm_nhanes_mr.R
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

.crm_data_root <- {
  cands <- c(
    "G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes",
    "/mnt/g/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes"
  )
  hit <- cands[dir.exists(cands)]
  if (length(hit)) hit[[1]] else cands[[1]]
}

.batch_project_root <- "Output/CRM_NHANES_MR"
.batch_ck_root       <- file.path(.batch_project_root, "checkpoints")

config <- list(
  project = list(
    name = "CRM_NHANES_MR",
    disease = "CRM_NHANES_MR",
    disease_code = "14",
    study_type = "incidence",
    literature_pmid = "e038723",
    analysis_group = "1",
    reference_group = "0",
    database = "NHANES",
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
    outcome_column = "fustatus"
  ),

  data_clean = list(missing_threshold = 1.0),
  column_mapping = list(enable = FALSE),

  crm_nhanes_pub = list(
    mortality_path = file.path(.crm_data_root, "nhanes-\u6b7b\u4ea1.Rdata"),
    mortality_obj = "combined_data",
    sua_col = "UricAcid",
    # 高尿酸 cut：默认男女同一 7 mg/dL；若核实 Han 2025 JAHA e038723 用男女分层
    # 定义（常见 male=7 / female=6），改用以下两行代替本行（保留本行会被覆盖）：
    #   hyperuricemia_cut_male = 7,
    #   hyperuricemia_cut_female = 6,
    hyperuricemia_cut_male = 7,
    hyperuricemia_cut_female = 6,
    diabetes_col = "T2DM",
    cvd_cols = c("MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F"),
    ckd_rule = "ckd_epi",
    ckd_epi_version = "2021",
    creatinine_col = "Creatinine",
    race_col = "Race",
    weight_col = "WTMEC2YR",
    min_age = 45,
    gout_col = NULL,
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
    gwas_exposure = "E:/\u5b5f\u5fb7\u5c14/1\u66b4\u9732\u6570\u636e/29892013-GCST90028994-EFO_0004587.h.tsv.gz",
    gwas_exposure_path = "E:/\u5b5f\u5fb7\u5c14/1\u66b4\u9732\u6570\u636e/29892013-GCST90028994-EFO_0004587.h.tsv.gz",
    exposure_n = 343836L,
    exposure_name = "SUA",
    pval_threshold = 5e-8,
    clump_kb = 10000L,
    clump_r2 = 0.001,
    mr_outcomes = c("CVD", "CKD", "Diabetes"),
    mr_max_snps = 176L,
    mr_f_stat_threshold = 10,
    mendelian_lib_root = "E:/\u5b5f\u5fb7\u5c14",
    plink_bin = "D:/easyMR/MRmyy_refer_file/plink/plink.exe",
    ld_bfile = "D:/easyMR/MRmyy_refer_file/1000G_EUR_Phase3_plink/1000G.EUR.QC",
    ld_clump_per_chr = TRUE,
    reuse_iv_cache = TRUE,
    iv_cache_path = "E:/\u5b5f\u5fb7\u5c14/1\u66b4\u9732\u6570\u636e/crm_han2025_iv/SUA_IVs_p5e-8_kb10000_r0.001.rds",
    outcome_cache_dir = "E:/\u5b5f\u5fb7\u5c14/1\u7ed3\u5c40\u6570\u636e/crm_han2025",
    auto_download_outcomes = FALSE,
    presso_nb = 1000L,
    outcome_map = list(
      CVD = list(file = "finngen_R12_I9_CVD_HARD.gz", ncase = 80527L, ncontrol = 419821L),
      CKD = list(file = "finngen_R12_N14_CHRONKIDNEYDIS.gz", ncase = 12787L, ncontrol = 480448L),
      Diabetes = list(file = "finngen_R12_T2D.gz", ncase = 82878L, ncontrol = 403489L)
    )
  ),

  crm_mr_literature = list(
    pause_enable = FALSE,
    pause_on_few_ivs = FALSE,
    outcome_key = NULL
  ),

  crm_nhanes_flowchart = list(pause_enable = FALSE),
  crm_nhanes_baseline_weighted = list(pause_enable = FALSE),
  crm_nhanes_ordinal_pub = list(pause_enable = FALSE),
  crm_nhanes_cox_pub = list(pause_enable = FALSE),
  crm_nhanes_rcs_pub = list(pause_enable = FALSE),
  crm_nhanes_km_pub = list(pause_enable = FALSE),
  crm_nhanes_pub_align = list(pause_enable = FALSE, pause_on_any_fail = FALSE),

  feishu = list(
    enable = FALSE,
    app_token = "RBjfb2iwmamW14s4WhKcS7kwnie",
    disease_label = "14_CRM_NHANES_MR",
    protocol_label = "crm_nhanes_mr",
    project_id = "14_crm_nhanes_mr_038723",
    workplan_code = "B30"
  )
)

pipeline <- list(
  name = "crm_nhanes_mr",
  blocks = c(
    "data_clean",
    "crm_nhanes_derive",
    "crm_nhanes_flowchart",
    "crm_nhanes_baseline_weighted",
    "crm_nhanes_ordinal_pub",
    "crm_nhanes_cox_pub",
    "crm_nhanes_rcs_pub",
    "crm_nhanes_km_pub",
    "crm_nhanes_pub_align"
  ),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "main"))
)
