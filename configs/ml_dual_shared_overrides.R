###############################################################################
#  ml_dual_shared_overrides.R — 单库 / 批量 ML 双库共用配置片段
###############################################################################

ml_dual_sanitize_multicollinearity_anthropometric <- function(config) {
  mc <- config$multicollinearity %||% list()
  anthro <- c(
    "BMI", "bmi", "Weight", "weight", "Height", "height",
    "Waist_circumstance", "Waist", "Waist_circumference", "waist"
  )
  excl <- unique(as.character(mc$exclude_vars %||% character(0)))
  if (length(intersect(excl, anthro))) {
    mc$exclude_vars <- setdiff(excl, anthro)
  }
  ar <- mc$anthropometric_vif_resolution %||% list()
  mc$anthropometric_vif_resolution <- modifyList(
    ar,
    list(
      enable = isTRUE(ar$enable %||% TRUE),
      vars = unique(c("BMI", "Weight", "Height", as.character(ar$vars %||% character(0)))),
      prefer_drop_one_order = unique(c(
        as.character(ar$prefer_drop_one_order %||% character(0)),
        "Weight", "Height"
      ))
    )
  )
  config$multicollinearity <- mc
  config
}

#' 启动前审计：警示 preset / 上一课题遗留的硬排除人体测量或错误 force_model1
ml_dual_audit_study_inherited_excludes <- function(config) {
  anthro <- c("BMI", "bmi", "Weight", "weight", "Height", "height")
  mc <- config$multicollinearity %||% list()
  excl <- intersect(unique(as.character(mc$exclude_vars %||% character(0))), anthro)
  ac <- config$assoc_covariate %||% list()
  m2e <- intersect(unique(as.character(ac$model2_exclude %||% character(0))), anthro)
  fm1 <- unique(as.character(ac$force_model1 %||% "Age"))
  fm1_anthro <- intersect(fm1, anthro)
  if (!requireNamespace("cli", quietly = TRUE)) {
    if (length(excl)) message("警告: multicollinearity$exclude_vars 含人体测量: ", paste(excl, collapse = ", "))
    if (length(m2e)) message("警告: assoc_covariate$model2_exclude 含人体测量: ", paste(m2e, collapse = ", "))
    if (length(fm1_anthro)) message("警告: assoc_covariate$force_model1 强制纳入人体测量: ", paste(fm1_anthro, collapse = ", "))
    return(invisible(config))
  }
  if (length(excl)) {
    cli::cli_alert_warning(
      "multicollinearity$exclude_vars 含人体测量 {paste(excl, collapse = ', ')}；建议清空，由 VIF>4 / anthropometric 协调决定"
    )
  }
  if (length(m2e)) {
    cli::cli_alert_warning(
      "assoc_covariate$model2_exclude 含人体测量 {paste(m2e, collapse = ', ')}；本项目应留空，仅 VIF 高时排除"
    )
  }
  if (length(fm1_anthro)) {
    cli::cli_alert_warning(
      "assoc_covariate$force_model1 强制纳入人体测量 {paste(fm1_anthro, collapse = ', ')}；仅 Age 应强制，其余靠 UV 显著进 Model1"
    )
  }
  ac <- config$assoc_covariate %||% list()
  if (isTRUE(ac$demo_uv_to_model1 %||% FALSE)) {
    dk <- unique(as.character(ac$demo_keywords %||% character(0)))
    if (!length(dk) || !any(tolower(dk) %in% c("gender", "sex"))) {
      cli::cli_alert_warning(
        "assoc_covariate$demo_keywords 未含 Gender/Sex；单因素显著的性别可能不进 Table2 Model1（与 VIF 不一致）"
      )
    }
  }
  rcs <- config$rcs_incidence %||% list()
  if (isTRUE(rcs$ylim_force %||% FALSE) &&
      is.finite(suppressWarnings(as.numeric(rcs$y_max %||% NA)[1L]))) {
    cli::cli_alert_warning(
      "rcs_incidence 写死 y_max={rcs$y_max} + ylim_force=TRUE；建议 ylim/y_max=NULL 由窗内 CI 自适应"
    )
  }
  lg <- as.character(config$ml_batch$logistic_grouping_scheme %||% config$incidence_batch$logistic_grouping_scheme %||% "")[1L]
  if (nzchar(lg)) {
    cli::cli_alert_warning(
      "写死了 logistic_grouping_scheme={lg}；应交给 logistic 闸门动态胜出，勿复制上一课题分位"
    )
  }
  if (exists("ml_dual_sanitize_ml_model_methods", mode = "function")) {
    config <- ml_dual_sanitize_ml_model_methods(config)
  }
  invisible(config)
}

#' 去掉与 mlp 重复的 realmlp；SHAP 默认 auto 时勿写死 xgboost
ml_dual_sanitize_ml_model_methods <- function(config) {
  methods <- as.character(config$ml_models$methods %||% character(0))
  if (length(methods) && any(tolower(methods) == "realmlp")) {
    config$ml_models$methods <- methods[tolower(methods) != "realmlp"]
    config$ml_realmlp <- modifyList(
      config$ml_realmlp %||% list(),
      list(enable = FALSE)
    )
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "已从 ml_models$methods 移除 realmlp（与 mlp 训练流程重复，结果相同）"
      )
    }
  }
  sh <- config$shap %||% list()
  sh_model <- tolower(trimws(as.character(sh$ml_model %||% sh$model %||% "")[1L]))
  if (identical(sh_model, "xgboost") && !isTRUE(sh$allow_fixed_xgboost %||% FALSE)) {
    config$shap <- modifyList(sh, list(ml_model = "auto"))
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "shap$ml_model 由 xgboost 改为 auto（验证集 AUC 最优模型做 SHAP；树模型用 TreeSHAP，其余用 kernel）"
      )
    }
  }
  config
}

ml_dual_apply_feature_selection_overrides <- function(config) {
  config$feature_selection$enable <- TRUE
  config$feature_selection$target_n_features_min <- 5L
  config$feature_selection$target_n_features_max <- 12L
  config$feature_selection$lasso_first <- TRUE
  config$feature_selection$pause_enable <- FALSE
  config$upstream <- modifyList(
    config$upstream %||% list(),
    list(restrict_to_train = TRUE)
  )
  config$multicollinearity <- modifyList(
    config$multicollinearity %||% list(),
    list(
      vif_removal_mode = "iterative",
      export_full_vif_table = FALSE,
      vif_threshold_before_feature_selection = 4,
      selection_on = "train"
    )
  )
  config$feature_selection <- modifyList(
    config$feature_selection %||% list(),
    list(
      dedupe_overlapping_severity_scores = TRUE,
      severity_score_keep_priority = c("APSIII", "SAPSII", "OASIS", "SOFA", "GCS")
    )
  )
  ## Cox/Logistic 协变量铁律（全 ML 课题默认）：仅 Age 强制；人体测量由 VIF 协调
  config$assoc_covariate <- modifyList(
    config$assoc_covariate %||% list(),
    list(
      enable = TRUE,
      force_model1 = "Age",
      demo_uv_to_model1 = TRUE,
      demo_keywords = c("Gender", "Sex", "Height", "Weight", "BMI"),
      model2_exclude = character(0),
      uv_source = "tb1",
      allow_m2_eq_m1 = TRUE
    )
  )
  config$performance_ml <- modifyList(
    config$performance_ml %||% list(),
    list(
      table_digits = 3L,
      combined_dca_auto_ylim = TRUE,
      dca_y_min = 0,
      dca_y_max = NULL,
      ## 发表用 bootstrap CI 表（Train+Val）：默认关；课题显式 TRUE 再开
      bootstrap_ci_table = FALSE,
      bootstrap_B = 1000L,
      bootstrap_seed = 42L
    )
  )
  config$shap <- modifyList(
    config$shap %||% list(),
    list(
      ml_model = "auto",
      combine = TRUE,
      save_each = FALSE,
      combined_width = 16,
      combined_height = 11.5,
      panel_axis_text_size = 8,
      panel_margin_right = 42,
      panel_margin_left = 22,
      prefer_tree_shapviz = FALSE,
      force_kernel_best_model = TRUE,
      show_panel_titles = TRUE,
      waterfall_prob_threshold = 0.75,
      waterfall_link = "logit",
      waterfall_fx_label = "f(x) = predicted probability",
      waterfall_efx_label = "E[f(x)] = incidence",
      waterfall_auto_case_high_prob = TRUE
    )
  )
  # 通用能力层默认开关（项目可覆盖）
  config$capability <- modifyList(
    config$capability %||% list(),
    list(
      exposure_mode = config$capability$exposure_mode %||% "primary_only",
      variable_aliases = modifyList(
        list(age = "Age", hypertension = "Hypertension", diabetes = "Diabetes"),
        config$capability$variable_aliases %||% list()
      ),
      sensitivity_suite = modifyList(
        list(enable = FALSE, min_n = 30L),
        config$capability$sensitivity_suite %||% list()
      )
    )
  )
  config$imputation <- modifyList(
    config$imputation %||% list(),
    list(mi_quality_exclude_enable = TRUE, mi_quality_p_threshold = 0.05)
  )
  config$baseline_binary <- modifyList(
    config$baseline_binary %||% list(),
    list(export_train_val_baseline = TRUE)
  )
  config$feature_selection_lasso <- modifyList(
    config$feature_selection_lasso %||% list(),
    list(auto_lasso_params = FALSE, lasso_lambda_step = 0.1, lasso_lambda_mult_max = 2.0)
  )
  config$supplementary_ml <- modifyList(
    config$supplementary_ml %||% list(),
    list(
      table_digits = 3L,
      ## methods 默认不含 calibration_boot；需要时课题显式加入
      calibration_boot_B = 1000L,
      calibration_boot_seed = 42L
    )
  )
  for (.fs_blk in c(
    "feature_selection_lasso", "feature_selection_boruta", "feature_selection_bayesian",
    "feature_selection_random_forest", "feature_selection_bagged_trees",
    "feature_selection_lvq", "feature_selection_consensus"
  )) {
    config[[.fs_blk]] <- modifyList(
      config[[.fs_blk]] %||% list(),
      list(pause_enable = FALSE, pause_on_insufficient_candidates = FALSE)
    )
  }
  config$ml_aggregate <- modifyList(
    config$ml_aggregate %||% list(),
    list(pause_enable = FALSE, pause_on_no_models = FALSE)
  )
  config$ml <- modifyList(
    config$ml %||% list(),
    list(
      include_composite_index = FALSE,
      use_venn_center_features = TRUE
    )
  )
  ## force_composite：暴露进 FS 候选+最终特征；VIF/assoc 仍不当调整协变量
  ## （inject_feature_selection_compound_indices 会写入 Model2Factors）
  config$feature_selection <- modifyList(
    config$feature_selection %||% list(),
    list(
      restrict_to_train = TRUE,
      force_composite_features = TRUE,
      include_composite_in_ml = TRUE,
      ## Figure S1：多方法→韦恩；单方法→该方法筛选图（LASSO 两图上下拼）
      draw_venn = TRUE
    )
  )
  config$feature_selection_venn <- modifyList(
    config$feature_selection_venn %||% list(),
    list(
      enable = TRUE,
      sync_venn_center_to_ml = TRUE,
      require_exposure_in_features = TRUE,
      single_method_use_s2_plot = TRUE
    )
  )
  ml_dual_sanitize_multicollinearity_anthropometric(config)
}

ml_dual_default_ml_methods <- function() {
  c(
    "dt", "rf", "xgboost", "enet", "rsvm", "mlp",
    "logistic", "lightgbm", "knn", "adaboost", "catboost",
    "tabpfn", "tabpfnv2", "realtabpfn_2_5", "tablcl_v2"
  )
}

ml_dual_apply_ml_models_overrides <- function(config) {
  config$ml_models$enable <- TRUE
  if (is.null(config$ml_models$methods) || !length(config$ml_models$methods)) {
    config$ml_models$methods <- ml_dual_default_ml_methods()
  }
  config <- ml_dual_sanitize_ml_model_methods(config)
  config$ml_adaboost <- modifyList(config$ml_adaboost %||% list(), list(
    enable = TRUE,
    pause_enable = FALSE,
    limits = list(max_train_n = 349L)
  ))
  config
}

ml_dual_apply_train_validation_batch_overrides <- function(config) {
  config$train_validation <- modifyList(
    config$train_validation %||% list(),
    list(
      enable = TRUE,
      # 划分在插补前：基线表在缺失值上不稳定；表在插补后由 baseline 等块负责时可关
      export_baseline_table = FALSE,
      # 批量默认 2000 次重划分会导致 MIMIC train_validation 单块 >50min
      max_resplit_iter = 150L
    )
  )
  # 预测模型默认：仅训练集拟合 MICE，再应用到 validation（须 pipeline 中 train_validation 在 imputation 前）
  config$imputation <- modifyList(
    config$imputation %||% list(),
    list(fit_on = "train")
  )
  config
}

#' cross_db 模式：沿用跨库 assign 的 train/test，不再 rsample 重切；
#' 仍 fit_on=train（runner 在 index 后已写入 raw train/test）。
ml_dual_apply_cross_db_split_overrides <- function(config) {
  split_mode <- config$ml_batch$split_mode %||% config$incidence_batch$split_mode %||% "per_db_internal"
  if (identical(split_mode, "cross_db")) {
    config$train_validation <- modifyList(
      config$train_validation %||% list(),
      list(passthrough = TRUE)
    )
    config$imputation <- modifyList(
      config$imputation %||% list(),
      list(fit_on = "train")
    )
    config$project$database <- ""
  }
  config
}

ml_dual_apply_nhanes_upstream_overrides <- function(config) {
  config$univariate_nhanes <- modifyList(
    config$univariate_nhanes %||% list(),
    list(
      sig_cutoff = 0.05,
      screening_cutoff = 0.1,
      pause_enable = FALSE,
      excluded_predictors = unique(c(
        as.character(config$univariate_nhanes$excluded_predictors %||% character(0)),
        "Disease", "Disease_Group"
      ))
    )
  )
  config$multivariate_nhanes <- modifyList(
    config$multivariate_nhanes %||% list(),
    list(
      sig_cutoff = 0.05,
      input_from = "vif_screen_pass",
      pause_enable = FALSE,
      demo_keywords = c(
        "Age", "Gender", "Sex", "Race", "Smoking", "Education", "Income"
      ),
      excluded_predictors = unique(c(
        as.character(config$multivariate_nhanes$excluded_predictors %||% character(0)),
        "Disease", "Disease_Group"
      ))
    )
  )
  config$multivariate_covariate_resolve <- list(
    enable = TRUE,
    fallback_from = "vif_screen_pass"
  )
  config$baseline_nhanes <- modifyList(
    config$baseline_nhanes %||% list(),
    list(
      sig_cutoff = 0.05,
      pause_enable = FALSE,
      pause_on_weighted_table_fail = FALSE,
      pause_on_min_sig_vars = FALSE,
      # 红线：暴露指标加权 Table 1 组间 P >= sig_cutoff → BASELINE_INDEX_NS_STOP 早停
      early_stop_if_index_ns = TRUE
    )
  )
  config$baseline_binary <- modifyList(
    config$baseline_binary %||% list(),
    list(
      sig_cutoff = 0.05,
      pause_enable = FALSE,
      pause_on_weighted_table_fail = FALSE,
      pause_on_min_sig_vars = FALSE,
      early_stop_if_index_ns = TRUE
    )
  )
  config
}

#' ML 双库铁律：主/次库 Table 1 暴露指标组间 P >= sig_cutoff → BASELINE_INDEX_NS_STOP（记 failed）
#' 显式 opt-out：config$ml_batch$baseline_index_ns_fail_rule = FALSE 时跳过
#' （无固定暴露设计：LASSO 入选变量即使粗关联 NS 也须出多因素 logistic 的课题）
ml_dual_apply_baseline_index_ns_fail_rule <- function(config) {
  .optout <- (config$ml_batch %||% config$incidence_batch %||% list())$baseline_index_ns_fail_rule
  if (identical(as.logical(.optout)[1L], FALSE)) {
    return(config)
  }
  config$baseline_binary <- modifyList(
    config$baseline_binary %||% list(),
    list(
      sig_cutoff = as.numeric(config$baseline_binary$sig_cutoff %||% 0.05)[1L],
      early_stop_if_index_ns = TRUE,
      pause_enable = FALSE,
      pause_on_min_sig_vars = FALSE
    )
  )
  config$baseline_nhanes <- modifyList(
    config$baseline_nhanes %||% list(),
    list(
      sig_cutoff = as.numeric(config$baseline_nhanes$sig_cutoff %||% 0.05)[1L],
      early_stop_if_index_ns = TRUE,
      pause_enable = FALSE,
      pause_on_weighted_table_fail = FALSE,
      pause_on_min_sig_vars = FALSE
    )
  )
  config
}

ml_dual_apply_nhanes_logistic_outputs_overrides <- function(config) {
  config$logistic_nhanes_weighted <- modifyList(
    config$logistic_nhanes_weighted %||% list(),
    list(
      cascade = list(
        crude_p_threshold = 0.05,
        crude_sig_method = "trend_or_any_group"
      ),
      covariate_source = "vif_final_pass",
      demo_factor_names = c(
        "Age", "Gender", "Race", "Smoking", "Education", "Income", "Marital_Status"
      ),
      clinical_factor_names = c(
        "HDL", "Hypertension", "Diabetes", "Lipid_lowering_agents",
        "Hyperlipidemia", "Heart_Failure", "CKD", "COPD"
      ),
      random_search = list(
        enable = TRUE,
        # 与 Cox 参考同结构（外层递增 factors_Num + 内层随机），但上限对齐发病 batch，避免 1000×1000 拖慢 44 指标批跑
        max_attempts = 100L,
        max_inner_attempts = 20L,
        max_total_fits = 300L,
        exhaustive_max_pool = 10L,
        max_exhaustive_combinations = 400L,
        initial_sample_n = 1L,
        p_threshold = NULL,
        require_highest_group_or_gt1 = FALSE,
        require_all_six_p = FALSE,
        pause_on_search_fail = FALSE,
        require_triple_model_sig = TRUE,
        m1_to_m2_fallback = TRUE
      ),
      pause_enable = FALSE
    )
  )
  for (.blk in c(
    "logistic_quartile_nhanes_weighted",
    "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted"
  )) {
    base <- config[[.blk]] %||% list()
    defaults <- switch(.blk,
      logistic_quartile_nhanes_weighted = list(
        include_continuous_row = TRUE, gate_enable = TRUE,
        extend_branch = "extend_quartile", degrade_branch = "degrade_tertile",
        p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
        pause_on_missing_design = TRUE
      ),
      logistic_tertile_nhanes_weighted = list(
        include_continuous_row = TRUE, gate_enable = TRUE,
        extend_branch = "extend_tertile", degrade_branch = "degrade_binary",
        p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
        pause_on_missing_design = TRUE
      ),
      logistic_binary_nhanes_weighted = list(
        include_continuous_row = TRUE, gate_enable = TRUE,
        extend_branch = "extend_binary", degrade_branch = character(0),
        p_threshold = 0.05, phase = "screen", pause_enable = FALSE,
        pause_on_missing_design = TRUE
      )
    )
    config[[.blk]] <- modifyList(defaults, base)
  }
  config$rcs_nhanes <- modifyList(
    config$rcs_nhanes %||% list(),
    list(
      max_model1_vars = 4L,
      knot_quantiles = c(0.1, 0.5, 0.9),
      histper = 25L
    )
  )
  config$subgroup <- modifyList(
    config$subgroup %||% list(),
    list(
      min_n = 20,
      var_source = "table1_categorical",
      required_subgroup_vars = NULL,
      forbid_subgroup_vars = c(
        "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group"
      ),
      forest_xlim = c(0, 4),
      pause_enable = FALSE
    )
  )
  config$boxplot <- modifyList(
    config$boxplot %||% list(),
    list(
      enable = TRUE,
      group_var = "Disease_Group",
      response_vars = NULL,
      overall_method = "kruskal.test",
      pairwise_method = "wilcox.test",
      pause_enable = FALSE,
      pause_if_all_overall_ns = FALSE
    )
  )
  if (is.null(config$data)) config$data <- list()
  config$data$outcome_column <- "Disease_Group"
  config$incidence <- modifyList(
    config$incidence %||% list(),
    list(outcome_var = "Disease_Group")
  )
  config
}

#' ML 双库主库流水线块序列（发病 / 预后由 study_type 决定）
ml_dual_primary_upstream_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  surv <- config$survival %||% list()
  has_time <- nzchar(as.character(surv$time_var %||% "")[1L])
  if (identical(st, "prognosis")) {
    upstream <- c(
      "univariate_prognosis", "multicollinearity_screen",
      "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
      "cox_tertile", "cox_quartile", "cox_binary",
      "km_binary"
    )
  } else {
    upstream <- c(
      "univariate_incidence_binary", "multicollinearity_screen",
      "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "rcs_incidence",
      "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
    )
    if (has_time) upstream <- c(upstream, "cox_binary", "km_binary")
  }
  upstream
}

#' ML 预测流水线关联块序列（ml_assoc_bundle 内部循环）
ml_dual_primary_ml_assoc_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  assoc <- tolower(trimws(as.character(config$ml_batch$assoc_model %||% "")[1L]))
  surv <- config$survival %||% list()
  has_time <- nzchar(as.character(surv$time_var %||% "")[1L])
  use_cox <- identical(assoc, "cox") || identical(st, "prognosis")
  if (isTRUE(use_cox)) {
    return(c("cox_quartile", "cox_tertile", "cox_binary", "rcs_prognosis", "km_binary"))
  }
  blocks <- c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
  )
  if (has_time) blocks <- c(blocks, "cox_binary", "km_binary")
  blocks
}

#' ML 预测流水线统计上游：单因素 → VIF（关联表放到特征选择之后）
ml_dual_primary_ml_stat_upstream_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  ## 预后：必须 univariate_prognosis → VIF（Cox 协变量 / LASSO-Cox 候选池同源）
  uni <- if (identical(st, "prognosis")) {
    "univariate_prognosis"
  } else {
    "univariate_incidence_binary"
  }
  ## 故意不含 ml_assoc_bundle：须等特征选择后再解析协变量
  c(uni, "ml_vif_train_test")
}

#' 预后 ML 专用覆盖：UV→VIF 定 Cox 协变量；特征选择仅 LASSO-Cox
ml_dual_apply_prognosis_ml_overrides <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% ""))
  if (!identical(st, "prognosis")) return(config)

  ## 特征选择：只跑 LASSO-Cox，关闭多模型 auto
  config$feature_selection <- modifyList(
    config$feature_selection %||% list(),
    list(
      enable = TRUE,
      methods = c("lasso_cox"),
      auto_methods = FALSE,
      lasso_first = FALSE,
      draw_venn = TRUE,
      restrict_to_train = TRUE,
      force_composite_features = TRUE,
      include_composite_in_ml = TRUE,
      ## 不足 min 时靠 LASSO-Cox 放宽 λ，禁止事后塞 Age/UV
      pad_if_below_min = FALSE
    )
  )
  config$feature_selection_lasso_cox <- modifyList(
    config$feature_selection_lasso_cox %||% list(),
    list(
      enable = TRUE,
      candidate_source = "vif",
      lambda_choice = "lambda.min",
      lambda_adjust_to_n = TRUE,
      cv_folds = 10L,
      pause_enable = FALSE,
      pause_on_insufficient_candidates = FALSE,
      fig_combined_name = "Figure S2.LASSO-Cox.pdf",
      fig_s1_name = "Figure S1.LASSO-Cox.pdf"
    )
  )
  config$feature_selection_venn <- modifyList(
    config$feature_selection_venn %||% list(),
    list(
      enable = TRUE,
      single_method_use_s2_plot = TRUE,
      require_exposure_in_features = TRUE,
      venn_filename = "Figure S1.LASSO-Cox.pdf"
    )
  )

  ## Cox 关联协变量 = 单因素→VIF 通过池（仅排除暴露）；不再用「UV 显著且未进 ML」
  config$assoc_covariate <- modifyList(
    config$assoc_covariate %||% list(),
    list(
      enable = TRUE,
      force_model1 = "Age",
      demo_uv_to_model1 = TRUE,
      demo_keywords = c("Gender", "Sex", "Height", "Weight", "BMI"),
      uv_source = "tb1",
      model2_from_vif_pass = TRUE,
      allow_ml_features_in_model2 = TRUE,
      allow_m2_eq_m1 = TRUE,
      model2_exclude = character(0)
    )
  )

  ## 预后单因素默认
  config$univariate_prognosis <- modifyList(
    config$univariate_prognosis %||% list(),
    list(
      sig_cutoff = 0.05,
      screening_cutoff = 0.1,
      pause_enable = FALSE,
      data_slot = "train"
    )
  )

  ## 预后默认模型：文献六模型（铁律）
  ## XGBoost-Cox / CoxBoost / GBM-Cox / RSF / Ridge-Cox / ElasticNet-Cox
  ## SurvivalSVM / mboost 仅小样本课题显式开启，不进默认六模型
  config$ml_models <- modifyList(
    config$ml_models %||% list(),
    list(
      enable = TRUE,
      methods = c(
        "xgbsurv", "coxboost", "gbmsurv", "rsf",
        "ridge_cox", "enet_cox"
      ),
      cv_folds = 5L
    )
  )
  for (.sk in c(
    "ml_xgbsurv", "ml_coxboost", "ml_gbmsurv", "ml_rsf",
    "ml_ridge_cox", "ml_enet_cox"
  )) {
    config[[.sk]] <- modifyList(
      config[[.sk]] %||% list(),
      list(enable = TRUE, pause_enable = FALSE)
    )
  }
  for (.sk_off in c("ml_survivalsvm", "ml_mboost_cox")) {
    config[[.sk_off]] <- modifyList(
      config[[.sk_off]] %||% list(),
      list(enable = FALSE, pause_enable = FALSE)
    )
  }

  ## 预后性能图：分面校准 + 合并 DCA
  ## surv_horizon：写 config 前查数据；NULL/"auto" → performance_ml 按 time 列推断
  ## ICU 行政截尾常见 28 天；门诊/随访常见 12/36/60 月——勿盲目写 60
  .prev_h <- config$performance_ml$surv_horizon
  config$performance_ml <- modifyList(
    config$performance_ml %||% list(),
    list(
      enable = TRUE,
      roc_calibration_dca = TRUE,
      prognosis_facet_calibration = TRUE,
      prognosis_combined_dca = TRUE,
      surv_horizon = if (is.null(.prev_h) || identical(.prev_h, "auto")) {
        NULL
      } else {
        suppressWarnings(as.numeric(.prev_h)[1L])
      },
      surv_horizon_unit = as.character(
        config$performance_ml$surv_horizon_unit %||% "auto"
      )[1L],
      combined_panel = FALSE,
      parallel_lines = TRUE,
      cv_boxplot = TRUE,
      summary_tables = TRUE
    )
  )

  ## SHAP 必须解释验证集表现最好的模型（C-index）；禁止回退 xgboost 画图
  config$shap <- modifyList(
    config$shap %||% list(),
    list(
      enable = TRUE,
      ml_model = "auto",
      force_kernel_best_model = TRUE,
      prefer_tree_shapviz = FALSE,
      match_venn_features = TRUE,
      combine = TRUE
    )
  )

  ## 预后 ML Shiny：默认对齐 RSF-model_pro 样式；模型标签仍可由课题钉死最优
  ## https://webcalcula.shinyapps.io/RSF-model_pro/
  config$shiny <- modifyList(
    config$shiny %||% list(),
    list(enable = TRUE, export_app = TRUE, run_interactive = FALSE)
  )
  config$shiny_ml_app <- modifyList(
    config$shiny_ml_app %||% list(),
    list(
      enable = TRUE,
      export_app = TRUE,
      run_interactive = FALSE,
      ui_style = "surv_prognostic",
      app_subdir = "ShinyApp"
    )
  )

  message(
    "预后 ML 覆盖: 上游=univariate_prognosis→VIF; FS=仅 LASSO-Cox; ",
    "assoc=Model2 来自 VIF 通过池; ",
    "models=文献六模型 XGBoost-Cox/CoxBoost/GBM-Cox/RSF/Ridge-Cox/ElasticNet-Cox; ",
    "SHAP=auto(最优模型); Shiny=surv_prognostic; ",
    "surv_horizon=",
    if (is.null(config$performance_ml$surv_horizon)) "auto(查数据)" else config$performance_ml$surv_horizon
  )
  config
}

#' 次库（外部验证）对称块：不跑 UV/VIF/FS，继承主库特征后与主库同构下游
#'
#' 铁律：主库 = 更大 N；外验库仅 inherit → 协变量铁律 → 关联。
#' split_mode=dev_internal_ext：冻结主库模型评整库外验（不重训）。
#' 其它模式：自训 ML（旧 per_db_internal）。
ml_dual_secondary_ml_symmetric_blocks <- function(config) {
  ## 基线固定：inherit → assoc → ml_eval_external → 自训尾。
  ## split_mode 只通过 enable 开关选路，禁止删 block（过 pipeline guard）。
  c(
    "ml_inherit_primary_features",
    "ml_assoc_covariate_resolve",
    "dual_db_covariate_harmonize",
    "ml_assoc_bundle",
    "ml_eval_external",
    "ml_models_bundle", "performance_ml", "supplementary_ml", "shap", "shiny_ml_app",
    ml_dual_primary_ml_subgroup_render_blocks(config),
    "attrition_flowchart"
  )
}

ml_dual_primary_ml_tail_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  has_time <- nzchar(as.character((config$survival %||% list())$time_var %||% "")[1L])
  ## 顺序：特征选择 → 协变量铁律 → 关联表(Cox/Logistic) → ML 训练
  tail <- c(
    "ml_feature_selection_bundle",
    "ml_assoc_covariate_resolve",
    "ml_assoc_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  )
  if (identical(st, "incidence")) {
    tail <- c(tail, "subgroup_incidence", "subgroup_prognosis")
  } else if (identical(st, "prognosis")) {
    tail <- c(tail, "subgroup_prognosis")
  }
  c(tail, "attrition_flowchart")
}

ml_dual_primary_ml_subgroup_render_blocks <- function(config) {
  st <- tolower(trimws(config$project$study_type %||% "incidence"))
  if (identical(st, "incidence")) {
    return(c("subgroup_incidence", "subgroup_prognosis"))
  }
  if (identical(st, "prognosis")) return("subgroup_prognosis")
  character(0)
}

ml_dual_apply_regular_upstream_overrides <- function(config) {
  config$univariate_incidence_binary <- modifyList(
    config$univariate_incidence_binary %||% list(),
    list(
      sig_cutoff = 0.05,
      screening_cutoff = 0.1,
      pause_enable = FALSE,
      data_slot = "train"
    )
  )
  config$multivariate_incidence_binary <- modifyList(
    config$multivariate_incidence_binary %||% list(),
    list(sig_cutoff = 0.05, pause_enable = FALSE)
  )
  config$multicollinearity <- modifyList(
    config$multicollinearity %||% list(),
    list(
      pause_enable = FALSE,
      data_slots = c("train", "test")
    )
  )
  for (.blk in c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
  )) {
    extra <- list(
      pause_enable = FALSE,
      gate_enable = TRUE,
      force_export = FALSE,
      p_threshold = 0.05
    )
    if (.blk == "logistic_quartile_glm" || .blk == "logistic_quartile_glm_rcs") {
      extra$extend_branch <- "extend_quartile"
      extra$degrade_branch <- "degrade_tertile"
    } else if (.blk == "logistic_tertile_glm" || .blk == "logistic_tertile_glm_rcs") {
      extra$extend_branch <- "extend_tertile"
      extra$degrade_branch <- "degrade_binary"
    } else {
      extra$extend_branch <- "extend_binary"
      extra$degrade_branch <- character(0)
    }
    config[[.blk]] <- modifyList(
      config[[.blk]] %||% list(),
      extra
    )
  }
  .cox_ml_assoc <- list(
    pause_enable = FALSE,
    pause_on_fit_fail = FALSE,
    gate_enable = FALSE,
    require_both_models_sig = FALSE,
    # 无 UV-extra 时允许 Model2=Model1（仅 Age）
    allow_m2_eq_m1 = TRUE,
    covariate_search = list(
      enable = FALSE,
      prefer_full_first = TRUE,
      on_search_fail = "degrade",
      max_model1_attempts = 100L,
      max_model2_attempts = 100L
    )
  )
  for (.cx in c("cox_quartile", "cox_tertile", "cox_binary")) {
    config[[.cx]] <- modifyList(config[[.cx]] %||% list(), .cox_ml_assoc)
  }
  config$km_binary <- modifyList(
    config$km_binary %||% list(),
    list(pause_enable = FALSE, pause_on_no_output = FALSE)
  )
  config$rcs_prognosis <- modifyList(
    list(ylim = NULL, y_min = 0, y_max = NULL, ylim_force = FALSE),
    config$rcs_prognosis %||% list()
  )
  config$rcs_incidence <- modifyList(
    list(
      max_model1_vars = 4L, knot_quantiles = c(0.1, 0.5, 0.9), histper = 25L,
      ylim = NULL, y_min = 0, y_max = NULL, ylim_force = FALSE,
      ylim_auto_quantile = 0.95
    ),
    config$rcs_incidence %||% list()
  )
  config$subgroup_incidence <- modifyList(
    config$subgroup_incidence %||% list(),
    list(pause_enable = FALSE, min_n = 20)
  )
  config$subgroup_prognosis <- modifyList(
    config$subgroup_prognosis %||% list(),
    list(pause_enable = FALSE, min_n = 20, restrict_to_required = TRUE)
  )
  config$subgroup <- modifyList(
    config$subgroup %||% list(),
    list(restrict_to_required = TRUE, pause_enable = FALSE)
  )
  config
}
