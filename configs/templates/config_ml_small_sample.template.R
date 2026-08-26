###############################################################################
#  config_ml_small_sample.template.R — 小样本 ML 配置模板（单库 / 单指标 or 全变量）
#
#  复制到产出目录 config.R 或 config_ml_small_sample.R，按需改 outcome_kind / feature_mode。
#
#  outcome_kind : "prognosis"（Cox/院内死亡）| "incidence"（发病 logistic）
#  feature_mode : "single_index"（一个复合指标，走 ml_dual_batch 引擎）
#               | "all_vars"（全连续变量池 → VIF → 共识特征，独立 step 链）
#
#  引擎批量（单指标）:
#    Rscript run/ml/run_ml_dual_batch.R --config "<study>/config.R"
#
#  后处理 Table 4/5 + Figure 4（两种模式共用）:
#    Rscript run/ml/run_ml_small_sample_pub.R --config "<study>/config.R"
###############################################################################

.study_root <- "//192.168.68.133/02block_result/{disease_code}_{disease}/small_sample_{PMID}"

config <- list(
  project = list(
    name = "{disease}_small_sample_ML",
    disease_code = "{disease_code}",
    disease = "{disease}",
    literature_pmid = "{PMID}",
    output_dir = .study_root,
    root = NULL
  ),
  data = list(
    rawdata_path = file.path(.study_root, "Data/D04_dabiao.RData"),
    rawdata_obj = "dabiao",
    id_column = "ID"
  ),

  # ── 小样本 ML 模式（写 config 时二选一说明）────────────────────────────
  ml_small_sample = list(
    enable = TRUE,
    outcome_kind = "prognosis",       # prognosis | incidence
    feature_mode = "all_vars",        # single_index | all_vars
    index_var = NULL,                 # feature_mode=single_index 时填，如 "AnionGap"

    bootstrap_B = 1000L,
    threshold_method = "youden",      # youden（主文默认）
    cv_folds = 5L,
    cv_repeats = 10L,
    model_order = c(
      "AdaBoost", "TabPFN", "CatBoost", "XGBoost", "LightGBM", "RF"
    ),

    # 路径（相对 output_dir）
    ml_matrix_csv = "ml_matrix.csv",
    ml_python_results_csv = "ml_python_results.csv",
    ml_r_probs_csv = "ml_all_probs.csv",
    tables_dir = "Tables",
    figures_dir = "Figures",
    figure4_name = "Figure 4. ML performance combined 2x4.pdf",

    # Python 可执行（Windows 研究机）
    python_exe = "C:/ProgramData/Miniconda3/envs/torch/python.exe"
  ),

  # 发病课题：outcome_kind=incidence 时使用
  incidence = list(
    outcome_column = "Disease",
    event_positive = "1"
  ),

  # 预后课题：outcome_kind=prognosis 时使用
  prognosis = list(
    time_column = "hosp_day",
    event_column = "DN",
    event_positive = "Non-survivor"
  ),

  # 全变量模式：疾病泄漏排除（按 skills/review-raw-covariate-columns）
  analysis_exclusion = list(
    disease_vars = c(),  # 按课题填写
    exclude_exposure_if_uses_disease_var = TRUE
  ),

  # Cox/Logistic 协变量铁律（勿写死 model1/model2_factors）
  # Model1 = Age 强制；Model2 = Age + UV显著且未进最终 ML
  assoc_covariate = list(
    enable = TRUE,
    force_model1 = "Age",
    uv_source = "tb1",
    max_model2_extra = Inf,  # 小样本可设 1L～2L
    allow_m2_eq_m1 = TRUE
  ),

  # 单指标模式：与 ml_dual_batch 对齐时复制 config_ml_dual_batch.template.R 的 ml_batch 段
  ml_batch = list(
    index_vars = c("AnionGap"),
    db_mode = "mimic_only",
    skip_existing = TRUE
  )
)

# feature_mode=single_index → 用 run/ml/run_ml_dual_batch.R 跑引擎，再 run_ml_small_sample_pub.R
# feature_mode=all_vars     → 研究目录 all_vars_ml/ step 链 + run_ml_small_sample_pub.R
