###############################################################################
#  block_run_pipeline_helpers.R — run_ml_dual / run_prediction 共用辅助函数
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

.pipeline_deep_copy <- function(x) {
  unserialize(serialize(x, NULL))
}

.pipeline_abs_path <- function(root, p) {
  p <- as.character(p)[1L]
  if (!nzchar(p)) return(p)
  if (grepl("^(/|[A-Za-z]:[/\\\\])", p)) {
    return(normalizePath(p, winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(root, p), winslash = "/", mustWork = FALSE)
}

pipeline_dual_db_init <- function(config) {
  multi_db_cfg <- config$multi_db %||% list()
  dual_db_mode <- isTRUE(multi_db_cfg$enable %||% FALSE)
  workflow <- tolower(trimws(as.character(multi_db_cfg$workflow %||% "both_full")))
  if (!workflow %in% c("both_full", "primary_full_secondary_ml")) {
    stop("multi_db$workflow 仅支持 both_full | primary_full_secondary_ml", call. = FALSE)
  }
  unify_before_baseline <- isTRUE(multi_db_cfg$unify_before_baseline %||% FALSE)
  config2 <- NULL
  if (dual_db_mode) {
    config2 <- .pipeline_deep_copy(config)
    db2 <- multi_db_cfg
    if (!is.null(db2$rawdata_path) && nzchar(db2$rawdata_path)) {
      config2$data$rawdata_path <- db2$rawdata_path
    }
    if (!is.null(db2$rawdata_obj) && nzchar(db2$rawdata_obj)) {
      config2$data$rawdata_obj <- db2$rawdata_obj
    }
    if (!is.null(db2$outcome_path)) config2$data$outcome_path <- db2$outcome_path
    if (!is.null(db2$outcome_column) && nzchar(db2$outcome_column)) {
      config2$data$outcome_column <- db2$outcome_column
    }
    if (!is.null(db2$id_column) && nzchar(db2$id_column)) {
      config2$data$id_column <- db2$id_column
    }
    if (!is.null(db2$database) && nzchar(db2$database)) {
      config2$project$database <- db2$database
    }
    if (!is.null(db2$database_type) && nzchar(db2$database_type)) {
      config2$project$database_type <- db2$database_type
    }
    if (!is.null(db2$output_dir) && nzchar(db2$output_dir)) {
      config2$project$output_dir <- db2$output_dir
    }
    if (!is.null(db2$column_mapping_type) && nzchar(db2$column_mapping_type)) {
      config2$column_mapping$database_type <- db2$column_mapping_type
    }
    patch_keys <- c(
      "cox", "weightplot_patch", "weightcox_patch",
      "logistic", "feature_selection", "ml_models", "train_validation"
    )
    for (k in patch_keys) {
      if (!is.null(db2[[k]])) {
        config2[[k]] <- utils::modifyList(config2[[k]] %||% list(), db2[[k]])
      }
    }
    config2$multi_db$role <- "secondary"
    config$multi_db$role <- "primary"
  }
  list(
    multi_db_cfg = multi_db_cfg,
    dual_db_mode = dual_db_mode,
    workflow = workflow,
    unify_before_baseline = unify_before_baseline,
    config2 = config2
  )
}

pipeline_apply_resolved_data_paths <- function(config, config2, multi_db_cfg, root, dual_db_mode) {
  config$data$rawdata_path <- .pipeline_abs_path(root, config$data$rawdata_path)
  if (dual_db_mode && !is.null(config2)) {
    config2$data$rawdata_path <- .pipeline_abs_path(root, config2$data$rawdata_path)
    if (identical(config$data$rawdata_path, config2$data$rawdata_path)) {
      stop(
        "DUAL_DB_ERROR: 两库 rawdata_path 解析后指向同一文件。\n  DB1: ",
        config$data$rawdata_path, "\n  DB2: ", config2$data$rawdata_path,
        call. = FALSE
      )
    }
  }
  config$project$output_dir <- .pipeline_abs_path(root, config$project$output_dir)
  if (dual_db_mode && !is.null(config2)) {
    config2$project$output_dir <- .pipeline_abs_path(root, config2$project$output_dir)
  }
  invisible(NULL)
}

pipeline_demo_keywords <- function(config) {
  uv <- config$univariate_multivariate %||% list()
  as.character(uv$demo_keywords %||% c(
    "Age", "Gender", "Sex", "Race", "ethnicity",
    "Education", "edu", "Marital", "marriage",
    "Income", "PIR", "poverty", "Smoking", "Smoke",
    "BMI", "Alcohol", "Language"
  ))
}

pipeline_is_demo_var <- function(v, kws) {
  vl <- tolower(trimws(as.character(v)))
  any(vapply(kws, function(k) grepl(tolower(k), vl, fixed = TRUE), logical(1)))
}

pipeline_get_sys_cols <- function(cfg) {
  unique(c(
    as.character(cfg$data$id_column %||% character(0)),
    as.character(cfg$data$strip_id_columns_after_imputation %||% character(0)),
    as.character(cfg$nhanes$survey_weight %||% character(0)),
    as.character(cfg$nhanes$survey_cluster %||% character(0)),
    as.character(cfg$nhanes$survey_strata %||% character(0)),
    "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
    "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR"
  ))
}

.pipeline_stage_order <- function() {
  c(
    "ctx", "ctx1", "ctx2", "ctx3", "ctx4", "ctx5", "ctx6", "ctx7", "ctx8",
    "ctx9", "ctx10", "ctx11", "ctx12", "ctx13", "ctx14"
  )
}

pipeline_checkpoint_init <- function(config, root, resume_from_partial, dual_db_mode) {
  ck_cfg <- config$checkpoint %||% list()
  checkpoint_enable <- isTRUE(ck_cfg$enable %||% TRUE)
  ck_dir <- ck_cfg$dir %||% "checkpoints"
  checkpoint_dir <- if (grepl("^(/|[A-Za-z]:[/\\\\])", ck_dir)) {
    ck_dir
  } else {
    file.path(root, ck_dir)
  }
  if (checkpoint_enable && !dir.exists(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE)
  }
  resume_from <- trimws(as.character(resume_from_partial %||% Sys.getenv("PIPELINE_RESUME_FROM", unset = "")))
  stages <- .pipeline_stage_order()
  resume_idx <- if (nzchar(resume_from)) {
    hit <- match(resume_from, stages)
    if (is.na(hit)) {
      stop("--from 仅支持: ", paste(stages, collapse = ", "), call. = FALSE)
    }
    hit
  } else {
    0L
  }
  .should_run_stage <- function(stage_id) {
    if (!checkpoint_enable && nzchar(resume_from)) {
      stop("续跑需要 checkpoint$enable=TRUE", call. = FALSE)
    }
    idx <- match(stage_id, stages)
    if (is.na(idx)) return(TRUE)
    idx > resume_idx
  }
  .save_checkpoint <- function(stage_id, objs) {
    if (!checkpoint_enable) return(invisible(NULL))
    path <- file.path(checkpoint_dir, paste0(stage_id, ".rds"))
    payload <- c(
      list(saved_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), stage = stage_id),
      objs
    )
    saveRDS(payload, path)
    cli::cli_alert_info("Checkpoint: {.file {basename(path)}}")
    invisible(path)
  }
  .restore_if_needed <- function() {
    if (!nzchar(resume_from) || !checkpoint_enable) return(invisible(NULL))
    path <- file.path(checkpoint_dir, paste0(resume_from, ".rds"))
    if (!file.exists(path)) {
      cli::cli_alert_warning("续跑检查点不存在: {.file {path}}，将从头运行。")
      return(invisible(NULL))
    }
    payload <- readRDS(path)
    for (nm in setdiff(names(payload), c("saved_at", "stage"))) {
      assign(nm, payload[[nm]], envir = globalenv())
    }
    cli::cli_alert_success("已从 {.file {basename(path)}} 恢复（续跑起点之后步骤）。")
    invisible(payload)
  }
  list(
    resume_from = resume_from,
    checkpoint_dir = checkpoint_dir,
    checkpoint_enable = checkpoint_enable,
    should_run_stage = .should_run_stage,
    save_checkpoint = .save_checkpoint,
    restore_if_needed = .restore_if_needed
  )
}

pipeline_index_mode <- function(config) {
  ix <- as.character((config$prediction %||% list())$index_vars %||% character(0))
  ix <- unique(ix[nzchar(ix)])
  if (!length(ix)) {
    lv <- (config$logistic %||% list())$index_var
    if (!is.null(lv)) ix <- unique(as.character(lv)[nzchar(as.character(lv))])
  }
  if (length(ix) <= 1L) {
    list(mode = "single", index_vars = ix, n = length(ix))
  } else {
    list(mode = "multi", index_vars = ix, n = length(ix))
  }
}

pipeline_db_role_is_secondary_ml <- function(config, workflow) {
  isTRUE((config$multi_db %||% list())$role == "secondary") &&
    identical(workflow, "primary_full_secondary_ml")
}

pipeline_harmonization_dir <- function(root, config) {
  dd <- config$dual_db %||% list()
  md <- config$multi_db %||% list()
  d <- dd$harmonization_dir %||% md$harmonization_dir %||% file.path(
    dd$checkpoint_base %||% config$checkpoint$dir %||% "checkpoints",
    "harmonization"
  )
  d <- if (grepl("^(/|[A-Za-z]:[/\\\\])", d)) d else file.path(root, d)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  normalizePath(d, winslash = "/", mustWork = FALSE)
}

pipeline_export_primary_ml_features <- function(ctx8, root, config) {
  feats <- as.character(
    ctx8$results$feature_selection_venn_center %||%
      ctx8$results$feature_selection_final %||%
      character(0)
  )
  feats <- feats[nzchar(feats)]
  if (!length(feats)) {
    stop("主库 feature_selection 未产出 feature_selection_final，无法传递给验证库。", call. = FALSE)
  }
  harm_dir <- pipeline_harmonization_dir(root, config)
  rds_path <- file.path(harm_dir, "feature_selection_final_primary.rds")
  payload <- list(
    features = feats,
    feature_selection_final = feats,
    source_db = config$project$database %||% "primary",
    exported_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    index_vars = pipeline_index_mode(config)$index_vars
  )
  saveRDS(payload, rds_path)
  txt_path <- file.path(harm_dir, "feature_selection_final_primary.txt")
  writeLines(feats, txt_path)
  cli::cli_alert_success(
    "主库最终 ML 特征已导出（n={length(feats)}）: {.file {basename(rds_path)}}"
  )
  invisible(list(rds = rds_path, txt = txt_path, features = feats))
}

pipeline_load_primary_ml_features <- function(root, config) {
  harm_dir <- pipeline_harmonization_dir(root, config)
  rds_path <- file.path(harm_dir, "feature_selection_final_primary.rds")
  if (!file.exists(rds_path)) {
    stop(
      "未找到主库特征文件 {.file {rds_path}}；请先跑 --db nhanes 或 --db both 完成主库 feature_selection。",
      call. = FALSE
    )
  }
  obj <- readRDS(rds_path)
  feats <- as.character(obj$features %||% obj$feature_selection_final %||% character(0))
  feats <- feats[nzchar(feats)]
  if (!length(feats)) stop("主库特征 RDS 为空。", call. = FALSE)
  list(features = feats, rds_path = rds_path, meta = obj)
}

pipeline_inject_primary_features_to_ctx <- function(cx, root, config, db_tag = "DB2") {
  loaded <- pipeline_load_primary_ml_features(root, config)
  feats <- loaded$features
  dat <- cx$data$imputed %||% cx$data$cleaned
  if (is.null(dat)) {
    stop("{db_tag}: 无插补数据，无法注入主库特征。", call. = FALSE)
  }
  present <- intersect(feats, names(dat))
  missing <- setdiff(feats, names(dat))
  if (length(missing)) {
    cli::cli_alert_warning(
      "{db_tag}: 主库特征在验证库中缺失 {length(missing)} 个，已跳过: {paste(head(missing, 8), collapse = ', ')}"
    )
  }
  if (length(present) < 3L) {
    stop(
      "DUAL_DB_ML_ERROR: {db_tag} 与主库共同可用 ML 特征不足 3 个（present={length(present)}）。",
      call. = FALSE
    )
  }
  cx$results$feature_selection_final <- present
  cx$results$Model2Factors <- present
  cx$results$ml_feature_names <- present
  cx$results$feature_selection_inherited_from <- "primary"
  cx$results$feature_selection_primary_rds <- loaded$rds_path
  if (exists("ensure_composite_in_ml_features", mode = "function") &&
      !isTRUE((config$ml %||% list())$use_venn_center_features %||% FALSE)) {
    cx <- ensure_composite_in_ml_features(cx, db_tag)
  }
  cli::cli_alert_success(
    "{db_tag}: 已注入主库 ML 特征 n={length(present)}（跳过缺失 {length(missing)}）"
  )
  cx
}

force_univar_only <- function(cx, db_tag = "DB") {
  tb2 <- cx$results$univar_features %||% cx$results$tb2 %||% character(0)
  tb2 <- unique(as.character(tb2))
  tb2 <- tb2[nzchar(tb2)]
  cx$results$univar_features <- tb2
  cx$results$tb2 <- tb2
  cx$results$tb3 <- tb2
  cx$results$multivar_features <- character(0)
  cx$results$Model2Factors <- tb2
  cli::cli_alert_info("{db_tag}: force_univar_only — 保留单因素显著变量 n={length(tb2)}")
  cx
}

run_cutoff_for_all_indices <- function(cx, db_tag = "DB") {
  pred <- cx$config$prediction %||% list()
  ix <- as.character(pred$index_vars %||% (cx$config$incidence %||% list())$index_var %||% character(0))
  ix <- unique(ix[nzchar(ix)])
  if (length(ix) <= 1L) return(cx)
  for (i in seq_along(ix)) {
    iv <- ix[[i]]
    if (!is.null(cx$config$nhanes)) cx$config$nhanes$cutoff_index_var <- iv
    if (!is.null(cx$config$incidence)) cx$config$incidence$index_var <- iv
    if (!is.null(cx$config$survival)) cx$config$survival$index_var <- iv
    cli::cli_alert_info("{db_tag}: cutoff 多指标 [{i}/{length(ix)}] {iv}")
    cx <- run_block(cx, "cutoff")
  }
  cx
}

prediction_apply_forbidden <- function(cx, db_tag = "DB") {
  pred <- cx$config$prediction %||% list()
  forbidden <- unique(as.character(pred$forbidden_model_predictors %||% character(0)))
  forbidden <- forbidden[nzchar(forbidden)]
  if (!length(forbidden)) return(cx)
  for (key in c("Model1Factors", "Model2Factors", "feature_selection_final", "univar_features")) {
    old <- as.character(cx$results[[key]] %||% character(0))
    if (!length(old)) next
    new <- setdiff(old, forbidden)
    if (length(new) < length(old)) {
      cx$results[[key]] <- new
    }
  }
  cli::cli_alert_info("{db_tag}: 已剔除 forbidden_model_predictors")
  cx
}

unify_model2_after_feature_selection <- function(cx1, cx2) {
  f1 <- as.character(cx1$results$feature_selection_final %||% character(0))
  f2 <- as.character(cx2$results$feature_selection_final %||% character(0))
  common <- intersect(f1, f2)
  if (length(common) < 3L) {
    cli::cli_alert_warning(
      "双库 feature_selection 交集仅 {length(common)} 个；保留各自特征集（both_full 模式）。"
    )
    return(list(cx1 = cx1, cx2 = cx2, common = common))
  }
  cx1$results$feature_selection_final <- common
  cx2$results$feature_selection_final <- common
  cx1$results$Model2Factors <- common
  cx2$results$Model2Factors <- common
  cli::cli_alert_success("双库 feature_selection 已统一为交集 n={length(common)}")
  list(cx1 = cx1, cx2 = cx2, common = common)
}

run_logistic_rcs_per_index <- function(cx, db_tag = "DB") {
  pred <- cx$config$prediction %||% list()
  ix <- as.character(pred$index_vars %||% (cx$config$logistic %||% list())$index_var %||% character(0))
  ix <- unique(ix[nzchar(ix)])
  if (!length(ix)) ix <- as.character((cx$config$logistic %||% list())$index_var %||% character(0))
  run_rcs <- isTRUE(pred$run_rcs %||% TRUE)
  cx <- prediction_apply_multi_index_logistic_plan(cx)
  plan_ix <- as.character((cx$config$prediction %||% list())$index_vars %||% ix)
  plan_ix <- plan_ix[nzchar(plan_ix)]
  if (length(plan_ix)) ix <- plan_ix
  for (i in seq_along(ix)) {
    iv <- ix[[i]]
    cx$config$logistic$index_var <- iv
    if (!is.null(cx$config$incidence)) cx$config$incidence$index_var <- iv
    if (!is.null(cx$config$survival)) cx$config$survival$index_var <- iv
    cli::cli_alert_info("{db_tag}: Logistic [{i}/{length(ix)}] {iv}")
    cx <- run_block(cx, "logistic")
    if (run_rcs) {
      if (!is.null(cx$config$rcs)) cx$config$rcs$vars <- c(iv)
      cx <- run_block(cx, "rcs")
    }
  }
  cx
}

run_subgroup_per_index <- function(cx, db_tag = "DB") {
  pred <- cx$config$prediction %||% list()
  ix <- as.character(pred$index_vars %||% (cx$config$logistic %||% list())$index_var %||% character(0))
  ix <- unique(ix[nzchar(ix)])
  primary_only <- isTRUE(pred$subgroup_primary_only %||% FALSE)
  if (primary_only && length(ix) > 1L) ix <- ix[1L]
  for (i in seq_along(ix)) {
    iv <- ix[[i]]
    if (!is.null(cx$config$incidence)) cx$config$incidence$index_var <- iv
    if (!is.null(cx$config$survival)) cx$config$survival$index_var <- iv
    if (!is.null(cx$config$subgroup)) {
      cx$config$subgroup$index_var <- iv
    }
    cli::cli_alert_info("{db_tag}: Subgroup [{i}/{length(ix)}] {iv}")
    cx <- run_block(cx, "subgroup")
  }
  cx
}

inject_feature_selection_compound_indices <- function(cx, db_tag = "DB") {
  fs <- cx$config$feature_selection %||% list()
  ## 全 ML 课题：暴露须进特征选择候选（LASSO/Boruta 等），但不当 assoc 协变量
  exp_var <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exp_var <- as.character(pipeline_index_exposure_var(cx$config) %||% character(0))
  }
  forced <- unique(c(
    as.character(fs$composite_features %||% character(0)),
    as.character((cx$config$prediction %||% list())$index_vars %||% character(0)),
    as.character((cx$config$ml_batch %||% list())$index_vars %||% character(0)),
    exp_var
  ))
  forced <- forced[nzchar(forced)]
  dat <- if (isTRUE(fs$restrict_to_train %||% FALSE) &&
              !is.null(cx$data$train) && is.data.frame(cx$data$train)) {
    cx$data$train
  } else {
    cx$data$imputed %||% cx$data$cleaned
  }
  if (is.null(dat) || !length(forced)) return(cx)
  present <- intersect(forced, names(dat))
  if (!length(present)) {
    cli::cli_alert_warning("{db_tag}: 未检测到复合指标 {paste(forced, collapse=', ')}，跳过强制并入。")
    return(cx)
  }
  never <- if (exists("pipeline_never_predictor_names", mode = "function")) {
    pipeline_never_predictor_names(cx$config)
  } else {
    character(0)
  }
  present <- setdiff(present, never)
  if (!length(present)) return(cx)

  ## VIF screen 故意不把暴露写入 Model2Factors（不当调整协变量）；
  ## 但 LASSO/Boruta 候选读的是 Model2Factors（≥3 时不回退 univar），
  ## 故此处必须同时写入 Model2Factors + univar_features（全课题生效）。
  old_uv <- unique(as.character(cx$results$univar_features %||% character(0)))
  old_m2 <- unique(as.character(cx$results$Model2Factors %||% character(0)))
  cx$results$univar_features <- unique(c(old_uv, present))
  cx$results$Model2Factors <- unique(c(old_m2, present))
  cli::cli_alert_info(
    "{db_tag}: 复合指标并入 feature_selection 候选 (Model2Factors+univar): {paste(present, collapse = ', ')}"
  )
  cx
}
