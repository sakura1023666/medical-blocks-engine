###############################################################################
#  configs/study_interface/ml_dual_batch_build.R
#
#  由程序员研究目录下的 config.R 调用；程序员只维护 .study 列表。
#  前置条件: 已定义 .study；环境变量 MEDICAL_BLOCKS_ROOT 已设置。
#
#  产出: config, pipeline_shared_*, pipeline_nhanes_batch,
#        pipeline_regular_primary_ml_batch, pipeline_mimic_ml_batch
###############################################################################

if (!exists(".study", inherits = TRUE))
  stop(".study 未定义：请在 config.R 顶部设置", call. = FALSE)

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.engine))
  stop("MEDICAL_BLOCKS_ROOT 未设置：请使用 run_study.bat / run_study.sh 运行", call. = FALSE)

.study <- .study %||% list()
.req <- function(x, key) {
  v <- .study[[key]]
  if (is.null(v) || (is.character(v) && !nzchar(v)))
    stop("config.R 中 .study$", key, " 必填", call. = FALSE)
  v
}

if (!exists(".batch_project_root", inherits = TRUE) || !nzchar(.batch_project_root %||% "")) {
  .study_config_file <- {
    ca <- commandArgs(trailingOnly = TRUE)
    i  <- match("--config", ca)
    if (!is.na(i) && i < length(ca))
      normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
    else
      NA_character_
  }
  .batch_project_root <- if (!is.na(.study_config_file)) {
    dirname(.study_config_file)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
}

.normalize_study_root <- function(p) {
  p <- gsub("\\\\", "/", p)
  if (.Platform$OS.type == "windows") {
    p <- sub("^//192\\.168\\.68\\.133/", "G:/", p)
    p <- sub("^//192\\.168\\.68\\.133", "G:/", p)
  }
  p
}
.batch_project_root <- .normalize_study_root(.batch_project_root)

.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")
.batch_data_root <- file.path(.batch_project_root, "Data")

disease_code   <- .req(.study, "disease_code")
disease        <- .req(.study, "disease")
pmid           <- .study$literature_pmid %||% .study$pmid %||% "00000000"
analysis_group <- .study$analysis_group %||% "Case"
reference_grp  <- .study$reference_group %||% "Control"
index_group    <- .study$index_group %||% "dual_safe"
index_vars     <- .study$index_vars %||% NULL
feishu_on      <- isTRUE(.study$feishu_enable %||% FALSE)

outcome_col    <- .study$outcome_column %||% "Disease"
id_col         <- .study$id_column %||% "ID"

primary_name   <- .study$primary_name %||% "CHARLS"
primary_type   <- tolower(.study$primary_db_type %||% "regular")
primary_subdir <- .study$primary_subdir %||% tolower(primary_name)
primary_file   <- .req(.study, "primary_rdata_file")
primary_obj    <- .study$primary_rdata_obj %||% "data"
primary_map    <- .study$primary_column_mapping %||% primary_name

secondary_name   <- .study$secondary_name %||% "ELSA"
secondary_type   <- tolower(.study$secondary_db_type %||% "regular")
secondary_subdir <- .study$secondary_subdir %||% tolower(secondary_name)
secondary_file   <- .req(.study, "secondary_rdata_file")
secondary_obj    <- .study$secondary_rdata_obj %||% "data"
secondary_map    <- .study$secondary_column_mapping %||% secondary_name

merge_tables     <- isTRUE(.study$merge_dual_db_tables %||% FALSE)
prefix_db        <- isTRUE(.study$mirror_aggregate_prefix_db %||% FALSE)
use_nhanes_path  <- isTRUE(.study$apply_nhanes_upstream %||% (primary_type == "nhanes"))

disease_preset <- .study$disease_config_preset %||% "psoriasis"
preset_path <- file.path(.engine, "configs", disease_preset, "config11.R")
if (!file.exists(preset_path))
  stop("疾病预设 config 缺失: ", preset_path, call. = FALSE)

source(preset_path, local = TRUE)
source(file.path(.engine, "configs/ml_dual_shared_overrides.R"), local = TRUE)

config <- ml_dual_apply_feature_selection_overrides(config)
config <- ml_dual_apply_ml_models_overrides(config)
if (use_nhanes_path) {
  config <- ml_dual_apply_nhanes_upstream_overrides(config)
  config <- ml_dual_apply_nhanes_logistic_outputs_overrides(config)
} else {
  config <- ml_dual_apply_regular_upstream_overrides(config)
}
# 次库/外验走 inherit + logistic/ML（不跑 UV/VIF）；仍应用 regular pause 关闭
config <- ml_dual_apply_regular_upstream_overrides(config)
config <- ml_dual_apply_train_validation_batch_overrides(config)
config$ml_models$methods <- ml_dual_default_ml_methods()

config$data$rawdata_path   <- file.path(.batch_data_root, primary_subdir, primary_file)
config$data$rawdata_obj    <- primary_obj
config$data$outcome_column <- outcome_col
config$data$id_column      <- id_col
config$incidence$outcome_var <- outcome_col

config$boxplot <- modifyList(
  config$boxplot %||% list(),
  list(group_var = outcome_col, enable = TRUE, pause_if_all_overall_ns = FALSE)
)
config$baseline <- modifyList(
  config$baseline %||% list(),
  list(strata = outcome_col)
)
config$nhanes <- modifyList(
  config$nhanes %||% list(),
  list(
    exclude_cols = unique(c(
      as.character(config$nhanes$exclude_cols %||% character(0)),
      "ID", "SEQN", "new_Weight", "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
      "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA", "Source_File"
    ))
  )
)

config$baseline_binary <- modifyList(
  config$baseline_binary %||% list(),
  list(
    sig_cutoff = 0.05,
    pause_enable = FALSE,
    pause_on_min_sig_vars = FALSE
  )
)

config$project$name                <- paste0(disease, "_ML_dual_batch")
config$project$disease_code        <- disease_code
config$project$disease             <- disease
config$project$literature_pmid     <- pmid
config$project$database            <- primary_name
config$project$database_type       <- if (primary_type == "nhanes") "nhanes" else "regular"
config$project$study_type          <- {
  st0 <- tolower(trimws(as.character(.study$study_type %||% "incidence")[1L]))
  if (!st0 %in% c("incidence", "prognosis", "prediction")) st0 <- "incidence"
  ## prediction 与 incidence 同走分类 ML；预后必须显式 prognosis
  if (identical(st0, "prediction")) "incidence" else st0
}
config$project$analysis_group      <- analysis_group
config$project$reference_group     <- reference_grp
config$project$output_dir          <- .batch_project_root
config$project$use_step_prefixed_block_dirs <- TRUE
config$project$block_steps_prefix  <- "step"
config$project$mirror_pub_outputs_to_root  <- TRUE

## 预后：时间/事件列 + UV→VIF + 仅 LASSO-Cox
if (identical(config$project$study_type, "prognosis")) {
  config$survival <- modifyList(
    config$survival %||% list(),
    list(
      time_var = as.character(.study$time_var %||% config$survival$time_var %||% "futime")[1L],
      event_var = as.character(.study$event_var %||% config$survival$event_var %||% "fustatus")[1L]
    )
  )
  config <- ml_dual_apply_prognosis_ml_overrides(config)
}

## 发病壳 + Cox 关联的预后 ML（如 IBD ACAG）：Shiny 仍走 surv_prognostic 默认
if (identical(tolower(as.character(config$ml_batch$assoc_model %||% "")[1L]), "cox") &&
    !identical(config$project$study_type, "prognosis")) {
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
      ui_style = config$shiny_ml_app$ui_style %||% "surv_prognostic",
      app_subdir = config$shiny_ml_app$app_subdir %||% "ShinyApp"
    )
  )
  ## 与正式 prognosis 一致：不足 min 靠放宽 λ，不事后补足
  .fs_methods <- tolower(as.character((config$feature_selection %||% list())$methods %||% character(0)))
  if (length(.fs_methods) && all(.fs_methods %in% c("lasso_cox", "lassocox"))) {
    config$feature_selection <- modifyList(
      config$feature_selection %||% list(),
      list(pad_if_below_min = FALSE)
    )
    config$feature_selection_lasso_cox <- modifyList(
      config$feature_selection_lasso_cox %||% list(),
      list(lambda_adjust_to_n = TRUE)
    )
  }
}

config$prediction$index_vars <- index_vars
if (length(index_vars)) {
  config$incidence$index_var <- index_vars
  config$logistic$index_var <- index_vars[[1L]]
  config$rcs_incidence$index_var <- index_vars[[1L]]
}
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
## 预后：SHAP 必须钉死最优模型（build 后再次强调，避免被上面覆盖丢键）
if (identical(config$project$study_type, "prognosis")) {
  config$shap <- modifyList(
    config$shap %||% list(),
    list(
      ml_model = "auto",
      force_kernel_best_model = TRUE,
      prefer_tree_shapviz = FALSE
    )
  )
}
config$feature_selection_venn <- modifyList(
  config$feature_selection_venn %||% list(),
  list(
    supp_figure_slot = 1L,
    venn_filename = "Figure S1.Venn.pdf",
    upset_filename = "Figure S1.Upset.pdf",
    single_method_use_s2_plot = TRUE
  )
)
config$shiny <- modifyList(config$shiny %||% list(), list(ml_model_tag = NULL))

config$ml_feature_selection_bundle <- list(enable = TRUE, export_for_secondary = TRUE)
config$ml_inherit_primary_features <- list(enable = TRUE)
config$ml_id_deduplicate <- list(
  enable = TRUE,
  id_column = NULL,
  keep = "first",
  stop_if_no_id_col = TRUE
)

config$dual_db <- list(
  enable = TRUE,
  mirror_aggregate = TRUE,
  mirror_aggregate_prefix_db = prefix_db,
  merge_dual_db_tables = merge_tables,
  workflow = "primary_full_secondary_ml",
  checkpoint_base = .batch_ck_root,
  harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
  current_db = NULL,
  primary = list(
    name = primary_name,
    db_type = primary_type,
    rawdata_path = file.path(.batch_data_root, primary_subdir, primary_file),
    rawdata_obj = primary_obj,
    id_column = id_col,
    column_mapping_type = primary_map
  ),
  secondary = list(
    name = secondary_name,
    db_type = secondary_type,
    rawdata_path = file.path(.batch_data_root, secondary_subdir, secondary_file),
    rawdata_obj = secondary_obj,
    id_column = id_col,
    column_mapping_type = secondary_map
  ),
  harmonization = list(
    demo_keywords = c(
      "Age", "Gender", "Sex", "Race", "ethnicity",
      "Education", "edu", "Marital", "marriage",
      "Income", "PIR", "poverty", "Smoking", "Smoke",
      "Insurance", "Language", "Alcohol"
    ),
    covariate_source = "vif_screen",
    sync_after_vif_final = TRUE,
    sync_logistic_branch = FALSE,
    # ML 次库 VIF 池常与主库不一致：临床交集空时各库保留 Model1/2，不因 GATE_B_EMPTY_COMMON 硬停
    require_same_clinical_cols = FALSE,
    stop_on_empty_common_clinical = FALSE
  )
)

config$column_mapping$database_type <- primary_map

config$multicollinearity <- modifyList(
  config$multicollinearity %||% list(),
  list(
    vif_threshold_strict = 4,
    vif_threshold_loose = 10,
    screen = list(
      table_title = "Multicollinearity Analysis (VIF, univariate p<0.1 screen)",
      csv_name = "VIF_check_screen.csv"
    ),
    final = list(
      table_title = "Multicollinearity Analysis (VIF, multivariate p<0.05)",
      csv_name = "VIF_check_final.csv"
    )
  )
)

config$feishu <- list(
  enable = feishu_on,
  app_id = Sys.getenv("FEISHU_APP_ID", ""),
  app_secret = Sys.getenv("FEISHU_APP_SECRET", ""),
  app_token = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
  table_id = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),
  literature_default = paste0(
    primary_name, " + ", secondary_name, " ML 双库（",
    disease_code, " ", disease, ", PMID ", pmid, "）"
  ),
  project_id = paste0(disease_code, "_", disease, "_ml_", pmid),
  owner_default = Sys.getenv("FEISHU_OWNER", ""),
  push_on_worker_finish = feishu_on,
  push_on_batch_summary = feishu_on,
  disease_label = paste0(disease_code, "_", disease),
  protocol_label = paste0(disease_code, "_", disease, "_ml_", pmid)
)

## 双库均为非 NHANES regular 时默认开发内验+外验（对齐 12_AKI 发表口径）；
## 主库为 NHANES 加权时仍默认 per_db_internal（两侧各自训练）。
.study_split_mode <- {
  sm0 <- .study$split_mode %||% NULL
  if (!is.null(sm0) && nzchar(as.character(sm0)[1L])) {
    as.character(sm0)[1L]
  } else if (!identical(tolower(primary_type), "nhanes") &&
             !identical(tolower(secondary_type), "nhanes")) {
    "dev_internal_ext"
  } else {
    "per_db_internal"
  }
}

config$ml_batch <- list(
  index_mode = "single_loop",
  index_vars = index_vars,
  index_group = index_group,
  multi_top_n = 3L,
  parallel_workers = NULL,
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
  worker_warn_sec = 10800L,
  worker_wait_sec = 28800L,
  gate_a_missing_threshold = 1.0,
  min_valid_per_db = 50L,
  trim_quantile = 0.01,
  curate_purge_pub_figures = TRUE,
  pub_figure_scheme = "ml_dual_standard",
  merge_dual_db_tables = merge_tables,
  split_mode = .study_split_mode
)

config$incidence_batch <- config$ml_batch
config <- ml_dual_apply_cross_db_split_overrides(config)
if (exists("ml_dual_apply_dev_ext_overrides", mode = "function")) {
  config <- ml_dual_apply_dev_ext_overrides(config)
} else {
  de_src <- file.path(.engine, "R/ml_dual_dev_ext.R")
  if (file.exists(de_src)) {
    source(de_src, local = FALSE)
    config <- ml_dual_apply_dev_ext_overrides(config)
  }
}
config$multi_db <- NULL

source(file.path(.engine, "configs/study_interface/ml_dual_batch_pipelines.R"), local = TRUE)

config$project$output_dir <- .batch_project_root
config$ml_batch$output_base <- .batch_project_root
config$ml_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared")
config$ml_batch$index_ck_base <- file.path(.batch_ck_root, "by_index")
config$incidence_batch <- config$ml_batch
config$dual_db$checkpoint_base <- .batch_ck_root
config$dual_db$harmonization_dir <- file.path(.batch_ck_root, "_global_harmonization")
config$data$rawdata_path <- file.path(.batch_data_root, primary_subdir, primary_file)
config$dual_db$primary$rawdata_path <- file.path(.batch_data_root, primary_subdir, primary_file)
config$dual_db$secondary$rawdata_path <- file.path(.batch_data_root, secondary_subdir, secondary_file)

# 铁律：Table 1 暴露不显著 → BASELINE_INDEX_NS_STOP（worker 启动前会再次强制）
config <- ml_dual_apply_baseline_index_ns_fail_rule(config)

rm(.study, .engine, .req, disease_code, disease, pmid, analysis_group, reference_grp,
   index_group, index_vars, feishu_on, outcome_col, id_col,
   primary_name, primary_type, primary_subdir, primary_file, primary_obj, primary_map,
   secondary_name, secondary_type, secondary_subdir, secondary_file, secondary_obj, secondary_map,
   merge_tables, prefix_db, use_nhanes_path, disease_preset, preset_path,
   .normalize_study_root, .study_split_mode,
   list = intersect(c(".study_config_file"), ls()))

invisible(NULL)
