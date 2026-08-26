###############################################################################
#  config_ml_dual_batch.R — CHARLS+ELSA × Leisure_activities ML 双库批量
#
#  产出: //192.168.68.133/02block_result/06_Psoriasis/ml_{PMID}/
#  数据: 02旋旋/Data/{charls,elsa}/D04_dabiao.RData
#
#  运行:
#    Rscript run/ml/run_ml_dual_batch.R --config configs/config_ml_dual_batch.R --no-skip
#
#  红线（不可关闭）:
#    1. baseline_*$early_stop_if_index_ns = TRUE（Table 1 暴露 P >= 0.05 早停）
#    2. NHANES 主库保留 cutoff→obj；普通库主库用 simple_ROC
###############################################################################

.batch_disease_code    <- "07"
.batch_disease         <- "Leisure_Activity"
.batch_literature_pmid <- "local_charls_elsa"

.batch_data_root <- normalizePath("02旋旋/Data", winslash = "/", mustWork = FALSE)

.batch_project_root <- file.path(
  "//192.168.68.133/02block_result/06_Psoriasis",
  paste0("ml_", .batch_literature_pmid)
)
.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")

root_guess <- normalizePath(getwd(), winslash = "/")
source(file.path(root_guess, "configs/psoriasis/config11.R"))
source(file.path(root_guess, "configs/ml_dual_shared_overrides.R"))

config <- ml_dual_apply_feature_selection_overrides(config)
config <- ml_dual_apply_ml_models_overrides(config)
config <- ml_dual_apply_nhanes_upstream_overrides(config)
config <- ml_dual_apply_regular_upstream_overrides(config)
config <- ml_dual_apply_nhanes_logistic_outputs_overrides(config)
config <- ml_dual_apply_train_validation_batch_overrides(config)
config$ml_models$methods <- ml_dual_default_ml_methods()  # 15 模型，无 adaboost

config$data$rawdata_path     <- file.path(.batch_data_root, "charls/D04_dabiao.RData")
config$data$rawdata_obj      <- "dabiao"
config$data$outcome_column   <- "Disease_Group"
config$data$id_column        <- "ID"

config$project$name                <- paste0(.batch_disease, "_ML_dual_batch")
config$project$disease_code        <- .batch_disease_code
config$project$disease             <- .batch_disease
config$project$literature_pmid     <- .batch_literature_pmid
config$project$database            <- "CHARLS"
config$project$database_type       <- "regular"
config$project$study_type          <- "incidence"
config$project$analysis_group      <- "Case"
config$project$reference_group     <- "Control"
config$project$output_dir          <- .batch_project_root
config$project$use_step_prefixed_block_dirs <- TRUE
config$project$block_steps_prefix  <- "step"
config$project$mirror_pub_outputs_to_root  <- TRUE

config$prediction$index_vars <- NULL
config$index <- list(enable = FALSE, only = NULL, skip = NULL, digits = 4L)

config$train_validation$enable <- TRUE
config$performance_ml$enable <- TRUE
config$supplementary_ml$enable <- TRUE
config$shap$enable <- TRUE
config$shap <- modifyList(
  config$shap %||% list(),
  list(
    ml_model = "auto",
    save_individual = FALSE,
    combine = TRUE,
    run_nhanes_weighted = FALSE,
    match_venn_features = TRUE,
    exclude_categorical = FALSE,
    force_index_in_plot = FALSE
  )
)
config$feature_selection_venn <- modifyList(
  config$feature_selection_venn %||% list(),
  list(
    supp_figure_slot = 1L,
    venn_filename = "Figure S1.Venn.pdf",
    upset_filename = "Figure S1.Upset.pdf",
    single_method_use_s2_plot = TRUE
  )
)
config$shiny <- modifyList(
  config$shiny %||% list(),
  list(ml_model_tag = NULL)
)

config$ml_feature_selection_bundle <- list(enable = TRUE, export_for_secondary = TRUE)
config$ml_inherit_primary_features <- list(enable = TRUE)

config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  workflow = "primary_full_secondary_ml",
  checkpoint_base = .batch_ck_root,
  harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
  current_db = NULL,
  primary = list(
    name = "CHARLS",
    db_type = "regular",
    rawdata_path = file.path(.batch_data_root, "charls/D04_dabiao.RData"),
    rawdata_obj = "dabiao",
    id_column = "ID",
    column_mapping_type = "CHARLS"
  ),
  secondary = list(
    name = "ELSA",
    db_type = "regular",
    rawdata_path = file.path(.batch_data_root, "elsa/D04_dabiao.RData"),
    rawdata_obj = "dabiao_elsa",
    id_column = "ID",
    column_mapping_type = "ELSA"
  ),
  harmonization = list(
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    covariate_source = "vif_screen",
    sync_after_vif_final = FALSE,
    sync_logistic_branch = FALSE
  )
)

config$column_mapping$database_type <- "CHARLS"

config$multicollinearity <- modifyList(
  config$multicollinearity %||% list(),
  list(
    vif_threshold_strict = 4,
    vif_threshold_loose = 10,
    screen = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, univariate p<0.1 screen, NHANES)",
      csv_name = "VIF_check_screen_weighted.csv"
    ),
    final = list(
      table_title = "Weighted Multicollinearity Analysis (VIF, multivariate p<0.05, NHANES)",
      csv_name = "VIF_check_final_weighted.csv"
    )
  )
)

config$feishu <- list(
  enable = FALSE,
  app_id = Sys.getenv("FEISHU_APP_ID", ""),
  app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
  app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
  table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
  literature_default = paste0(
    "NHANES + MIMIC ML 双库（", .batch_disease_code, " ", .batch_disease,
    ", PMID ", .batch_literature_pmid, "）"
  ),
  project_id = paste0(.batch_disease_code, "_", .batch_disease, "_ml_", .batch_literature_pmid),
  owner_default = Sys.getenv("FEISHU_OWNER", ""),
  push_on_worker_finish = FALSE,
  push_on_batch_summary = FALSE,
  disease_label = paste0(.batch_disease_code, "_", .batch_disease),
  protocol_label = paste0(.batch_disease_code, "_", .batch_disease, "_ml_", .batch_literature_pmid)
)

config$ml_batch <- list(
  index_mode = "single_loop",
  index_vars = c("Leisure_activities"),
  index_group = "dual_safe",
  multi_top_n = 3L,
  parallel_workers = 4L,
  fail_policy = "continue",
  skip_existing = TRUE,
  db_mode = "both",
  output_base = .batch_project_root,
  shared_ck_base = file.path(.batch_ck_root, "_shared"),
  index_ck_base = file.path(.batch_ck_root, "by_index"),
  ram_per_worker_gb = 2.5,
  cpu_headroom = 2L,
  ram_headroom_gb = 4.0,
  max_workers = 4L,
  # >1h 日志仅为告警；单指标 NHANES+MIMIC×15 模型正常需 1–3h
  worker_warn_sec = 10800L,
  worker_wait_sec = 28800L,
  gate_a_missing_threshold = 1.0,
  min_valid_per_db = 50L,
  trim_quantile = 0.01,
  # TRUE = 汇总目录仅保留 Fig2 RCS / Fig3 ML拼图 / Fig4 SHAP / Fig5 亚组 / FigS1 韦恩
  curate_purge_pub_figures = TRUE,
  pub_figure_scheme = "ml_dual_standard"
)

config$incidence_batch <- config$ml_batch
config$multi_db <- NULL

pipeline_shared_nhanes <- list(
  name = "ml_dual_batch_shared_charls",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "nhanes"))
)

pipeline_shared_regular <- list(
  name = "ml_dual_batch_shared_elsa",
  blocks = c("data_clean", "column_mapping", "dual_db_column_harmonize", "index"),
  logistic_gate = list(enable = FALSE),
  render_tables_after = character(0),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_ck_root, "_shared", "mimic"))
)

pipeline_nhanes_batch <- list(
  name = "psoriasis_ml_batch_nhanes",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "cutoff", "obj", "baseline_nhanes", "boxplot",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "baseline_binary", "logistic_binary_glm",
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap",
    "subgroup_nhanes_weighted",
    "shiny_ml_app"
  ),
  logistic_gate = list(enable = TRUE, weighted = TRUE),
  render_tables_after = c(
    "imputation", "baseline_nhanes", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multicollinearity_nhanes_final",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "baseline_binary", "logistic_binary_glm",
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "shap", "subgroup_nhanes_weighted"
  ),
  render_figures_after = c(
    "ml_feature_selection_bundle",
    "rcs_nhanes", "performance_ml", "shap", "subgroup_nhanes_weighted"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

# 多指标 Phase2：VIF 终 → 各指标 logistic 支路 → ML 下游
pipeline_nhanes_upstream <- list(
  name = "psoriasis_ml_batch_nhanes_upstream",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "univariate_nhanes", "multicollinearity_nhanes_screen",
    "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "imputation", "univariate_nhanes",
    "multicollinearity_nhanes_screen", "multivariate_nhanes",
    "multicollinearity_nhanes_final"
  ),
  render_figures_after = c("imputation"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_nhanes_multi_logistic <- list(
  name = "psoriasis_ml_batch_nhanes_multi_logistic",
  blocks = c("ml_logistic_multi_index_bundle"),
  logistic_gate = list(enable = TRUE, weighted = TRUE),
  render_tables_after = c("ml_logistic_multi_index_bundle"),
  render_figures_after = c("ml_logistic_multi_index_bundle"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_nhanes_ml_tail <- list(
  name = "psoriasis_ml_batch_nhanes_ml_tail",
  blocks = c(
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "train_validation", "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c("ml_feature_selection_bundle", "performance_ml", "shap"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

# CHARLS 等普通库主库：发病上游 + ML 下游（替代 pipeline_nhanes_batch）
pipeline_regular_primary_ml_batch <- list(
  name = "ml_dual_regular_primary",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "baseline_binary", "simple_ROC", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap",
    "subgroup_incidence",
    "shiny_ml_app"
  ),
  logistic_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation", "baseline_binary", "simple_ROC", "boxplot",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "train_validation",
    "ml_feature_selection_bundle",
    "ml_models_bundle", "performance_ml",
    "shap", "subgroup_incidence"
  ),
  render_figures_after = c(
    "ml_feature_selection_bundle",
    "simple_ROC", "boxplot", "rcs_incidence", "performance_ml", "shap", "subgroup_incidence"
  ),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline_mimic_ml_batch <- list(
  name = "psoriasis_ml_batch_mimic_secondary",
  blocks = c(
    "data_clean", "column_mapping", "dual_db_column_harmonize", "index",
    "imputation", "trim_index_extreme",
    "ml_inherit_primary_features",
    "train_validation", "ml_models_bundle", "performance_ml",
    "supplementary_ml", "shap", "shiny_ml_app"
  ),
  logistic_gate = list(enable = FALSE),
  render_tables_after = c(
    "imputation", "ml_inherit_primary_features",
    "train_validation", "ml_models_bundle", "performance_ml"
  ),
  render_figures_after = c("performance_ml", "shap"),
  dual_db = list(enable = TRUE),
  checkpoint = list(enable = TRUE, dir = NULL)
)

pipeline <- pipeline_nhanes_batch
