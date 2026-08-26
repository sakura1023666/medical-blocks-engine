###############################################################################
#  ml_dual_shared_overrides.R — 单库 / 批量 ML 双库共用配置片段
###############################################################################

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
  ## Cox/Logistic 协变量铁律（全 ML 课题默认）
  config$assoc_covariate <- modifyList(
    config$assoc_covariate %||% list(),
    list(
      enable = TRUE,
      force_model1 = "Age",
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
      dca_y_max = NULL
    )
  )
  config$shap <- modifyList(
    config$shap %||% list(),
    list(
      combine = TRUE,
      save_each = FALSE,
      combined_width = 11,
      combined_height = 9,
      waterfall_prob_threshold = 0.75,
      waterfall_link = "logit",
      waterfall_fx_label = "f(x) = predicted disease probability",
      waterfall_efx_label = "E[f(x)] = dataset incidence",
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
    list(table_digits = 3L)
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
      include_composite_in_ml = TRUE
    )
  )
  config$feature_selection_venn <- modifyList(
    config$feature_selection_venn %||% list(),
    list(
      sync_venn_center_to_ml = TRUE,
      require_exposure_in_features = TRUE
    )
  )
  config
}

ml_dual_default_ml_methods <- function() {
  c(
    "dt", "rf", "xgboost", "enet", "rsvm", "mlp", "realmlp",
    "logistic", "lightgbm", "knn", "adaboost", "catboost",
    "tabpfn", "tabpfnv2", "realtabpfn_2_5", "tablcl_v2"
  )
}

ml_dual_apply_ml_models_overrides <- function(config) {
  config$ml_models$enable <- TRUE
  if (is.null(config$ml_models$methods) || !length(config$ml_models$methods)) {
    config$ml_models$methods <- ml_dual_default_ml_methods()
  }
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
  uni <- if (identical(st, "prognosis")) {
    "univariate_incidence_binary"
  } else {
    "univariate_incidence_binary"
  }
  ## 故意不含 ml_assoc_bundle：须等特征选择后再解析「UV显著且未进 ML」协变量
  c(uni, "ml_vif_train_test")
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
    config[[.blk]] <- modifyList(
      config[[.blk]] %||% list(),
      # ML assoc：强制导出 quartile/tertile/binary（及 RCS 复跑）到 Tables；
      # gate 关闭，避免 dual_db 下 do_export=FALSE 导致 step Tables 空
      list(
        pause_enable = FALSE,
        gate_enable = FALSE,
        force_export = TRUE,
        p_threshold = 0.05
      )
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
    config$rcs_prognosis %||% list(),
    list(ylim = c(0, 5), y_min = 0, y_max = 5)
  )
  config$rcs_incidence <- modifyList(
    config$rcs_incidence %||% list(),
    list(
      max_model1_vars = 4L, knot_quantiles = c(0.1, 0.5, 0.9), histper = 25L,
      ylim = c(0, 5), y_min = 0, y_max = 5
    )
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
