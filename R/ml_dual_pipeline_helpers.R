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

#' 单库 ML：db_mode=nhanes 或次库槽位 UNUSED → 非真双库 logistic 初筛
ml_dual_is_single_primary_db <- function(ctx) {
  cfg <- if (is.list(ctx) && !is.null(ctx$config)) ctx$config else ctx
  batch <- cfg$ml_batch %||% cfg$incidence_batch %||% list()
  db_mode <- tolower(as.character(batch$db_mode %||% "")[1L])
  if (identical(db_mode, "nhanes")) return(TRUE)
  dual <- cfg$dual_db %||% list()
  sec <- trimws(as.character((dual$secondary %||% list())$name %||% ""))[1L]
  identical(toupper(sec), "UNUSED") || !nzchar(sec)
}

pipeline_get_sys_cols <- function(cfg) {
  meta <- if (exists("pipeline_meta_exclude_cols", mode = "function")) {
    pipeline_meta_exclude_cols()
  } else {
    character(0)
  }
  unique(c(
    as.character(cfg$data$id_column %||% character(0)),
    as.character(cfg$data$strip_id_columns_after_imputation %||% character(0)),
    as.character(cfg$nhanes$survey_weight %||% character(0)),
    as.character(cfg$nhanes$survey_cluster %||% character(0)),
    as.character(cfg$nhanes$survey_strata %||% character(0)),
    "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
    "WTSAF2YR", "WTSAF4YR", "WTSOG2YR", "WTDRD1", "WTDR2D",
    "new_Weight", "new_weight",
    "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR",
    "Group",
    meta
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

## 从多个候选 ctx 键里取第一个非空特征向量（venn_center 可能被 strip 成
## 非 NULL 的 character(0)，直接 `%||%` 会误取空值，故逐键扫描）。
.ml_primary_pick_feats <- function(res) {
  for (k in c(
    "feature_selection_final", "feature_selection_venn_center", "ml_feature_names"
  )) {
    v <- unique(as.character(res[[k]] %||% character(0)))
    v <- v[nzchar(v)]
    if (length(v)) return(v)
  }
  character(0)
}

pipeline_export_primary_ml_features <- function(ctx8, root, config) {
  feats <- .ml_primary_pick_feats(ctx8$results)
  if (!length(feats)) {
    ## 单方法（如仅 Boruta）共识已把最终特征持久化到输出根 / checkpoint 的
    ## feature_selection_final.rds，但某些路径下未回灌到当前 ctx。导出前先尝试回读，
    ## 避免「主库已选出特征却报未产出」误停（对全部双库 ML 课题均为安全兜底）。
    if (exists("load_feature_selection_final_into_ctx", mode = "function")) {
      ctx8 <- tryCatch(
        load_feature_selection_final_into_ctx(ctx8),
        error = function(e) ctx8
      )
      feats <- .ml_primary_pick_feats(ctx8$results)
    }
  }
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

pipeline_assoc_current_index <- function(config, ctx = NULL) {
  as.character(
    (config$ml_batch %||% list())$current_index %||%
      (config$incidence_batch %||% list())$current_index %||%
      (ctx$results$current_index %||% NULL) %||%
      ((config$prediction %||% list())$index_vars %||%
         (config$index_vars %||% character(0)))[1L] %||%
      ""
  )[1L]
}

pipeline_load_imputed_colnames_for_slot <- function(root, config, slot_path, ctx = NULL) {
  slot_path <- as.character(slot_path)[1L]
  if (!nzchar(slot_path)) return(character(0))
  if (!is.null(ctx) && is.data.frame(ctx$data$imputed) &&
      grepl(slot_path, as.character(config$project$database %||% ""), ignore.case = TRUE)) {
    return(names(ctx$data$imputed))
  }
  ck_base <- as.character(
    (config$dual_db %||% list())$checkpoint_base %||%
      file.path(root, "checkpoints", "by_index", pipeline_assoc_current_index(config, ctx))
  )[1L]
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", ck_base)) {
    ck_base <- file.path(root, ck_base)
  }
  for (fn in c("imputation.rds", "step08_imputation.rds", "step05_imputation.rds")) {
    p <- file.path(ck_base, slot_path, fn)
    if (!file.exists(p)) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(obj)) next
    cx <- if (!is.null(obj$ctx)) obj$ctx else obj
    df <- cx$data$imputed %||% cx$data$train
    if (is.data.frame(df)) return(names(df))
  }
  character(0)
}

#' 双库插补后列名交集（发表 M2 / VIF 必须用这个，禁止一侧独有列如高缺失砍掉的 TotalCo2）
pipeline_dual_db_imputed_common_names <- function(root, config, ctx = NULL) {
  dual <- config$dual_db %||% list()
  pri <- as.character((dual$primary %||% list())$name %||% "")[1L]
  sec <- as.character((dual$secondary %||% list())$name %||% "")[1L]
  if (exists("dual_db_slot_path_name", mode = "function")) {
    pri <- dual_db_slot_path_name(config, "nhanes")
    sec <- dual_db_slot_path_name(config, "mimic")
  }
  n1 <- pipeline_load_imputed_colnames_for_slot(root, config, pri, ctx)
  n2 <- pipeline_load_imputed_colnames_for_slot(root, config, sec, ctx)
  if (is.data.frame(ctx$data$imputed) && !length(n1)) {
    n1 <- names(ctx$data$imputed)
  }
  if (!length(n1) || !length(n2)) return(character(0))
  intersect(n1, n2)
}

pipeline_assoc_restrict_to_imputed_common <- function(vars, common, what = "协变量") {
  vars <- unique(as.character(vars)[nzchar(as.character(vars))])
  common <- unique(as.character(common)[nzchar(as.character(common))])
  if (!length(vars) || !length(common)) return(vars)
  dropped <- setdiff(vars, common)
  if (length(dropped) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "发表{what}改为插补后双库交集，去掉 {length(dropped)} 个单库列: {paste(dropped, collapse = ', ')}"
    )
  }
  intersect(vars, common)
}

#' 主库训练集锁定的 Table 2 / VIF 协变量（次库必须原样继承，禁止再 UV 解析成只剩 Age）
pipeline_export_primary_assoc_covariates <- function(ctx, root, config) {
  m1 <- unique(as.character(
    ctx$results$assoc_model1_factors %||%
      ctx$results$logistic_model1_factors %||%
      ctx$results$Model1Factors %||%
      character(0)
  ))
  m2 <- unique(as.character(
    ctx$results$assoc_model2_factors %||%
      ctx$results$logistic_model2_factors %||%
      character(0)
  ))
  m1 <- m1[nzchar(m1)]
  m2 <- m2[nzchar(m2)]
  if (!length(m1)) {
    cli::cli_alert_warning("主库 assoc 协变量未锁定，跳过导出 assoc_covariates_primary.rds")
    return(invisible(NULL))
  }
  if (!length(m2)) m2 <- m1
  exposure <- character(0)
  if (exists("ml_assoc_exposure_var", mode = "function")) {
    exposure <- as.character(ml_assoc_exposure_var(ctx))
  } else if (exists("pipeline_index_exposure_var", mode = "function")) {
    exposure <- as.character(pipeline_index_exposure_var(config))
  }
  exposure <- exposure[nzchar(exposure)]
  m1 <- setdiff(m1, exposure)
  m2 <- unique(c(m1, setdiff(m2, exposure)))
  vif_pass <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
  vif_pass <- vif_pass[nzchar(vif_pass)]
  common <- pipeline_dual_db_imputed_common_names(root, config, ctx)
  if (length(common)) {
    m1 <- pipeline_assoc_restrict_to_imputed_common(m1, common, "Model1")
    m2 <- unique(c(m1, pipeline_assoc_restrict_to_imputed_common(setdiff(m2, m1), common, "Model2")))
    vif_pass <- pipeline_assoc_restrict_to_imputed_common(vif_pass, common, "VIF")
    ctx$results$assoc_model1_factors <- m1
    ctx$results$assoc_model2_factors <- m2
    ctx$results$logistic_model1_factors <- m1
    ctx$results$logistic_model2_factors <- m2
    ctx$results$vif_screen_pass <- vif_pass
    ctx$results$assoc_restricted_to_imputed_common <- TRUE
  }
  harm_dir <- pipeline_harmonization_dir(root, config)
  rds_path <- file.path(harm_dir, "assoc_covariates_primary.rds")
  payload <- list(
    model1 = m1,
    model2 = m2,
    vif_screen_pass = vif_pass,
    source_db = config$project$database %||% "primary",
    exported_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    index_vars = if (exists("pipeline_index_mode", mode = "function")) {
      pipeline_index_mode(config)$index_vars
    } else {
      character(0)
    }
  )
  saveRDS(payload, rds_path)
  writeLines(
    c(
      paste("Model1:", paste(m1, collapse = ", ")),
      paste("Model2:", paste(m2, collapse = ", ")),
      paste("vif_screen_pass:", paste(vif_pass, collapse = ", "))
    ),
    file.path(harm_dir, "assoc_covariates_primary.txt")
  )
  cli::cli_alert_success(
    "主库训练集协变量已导出（M1={length(m1)}, M2={length(m2)}, VIF={length(vif_pass)}）: {.file {basename(rds_path)}}"
  )
  invisible(list(rds = rds_path, model1 = m1, model2 = m2, vif_screen_pass = vif_pass))
}

pipeline_load_primary_assoc_covariates <- function(root, config, must_exist = FALSE) {
  harm_dir <- pipeline_harmonization_dir(root, config)
  rds_path <- file.path(harm_dir, "assoc_covariates_primary.rds")
  if (!file.exists(rds_path)) {
    if (isTRUE(must_exist)) {
      stop(
        "未找到主库协变量文件 {.file {rds_path}}；请先完成主库 ml_assoc_covariate_resolve。",
        call. = FALSE
      )
    }
    return(NULL)
  }
  obj <- readRDS(rds_path)
  m1 <- unique(as.character(obj$model1 %||% obj$M1 %||% character(0)))
  m2 <- unique(as.character(obj$model2 %||% obj$M2 %||% character(0)))
  m1 <- m1[nzchar(m1)]
  m2 <- m2[nzchar(m2)]
  if (!length(m1)) {
    if (isTRUE(must_exist)) stop("主库协变量 RDS 中 Model1 为空。", call. = FALSE)
    return(NULL)
  }
  if (!length(m2)) m2 <- m1
  list(
    model1 = m1,
    model2 = unique(c(m1, m2)),
    vif_screen_pass = unique(as.character(obj$vif_screen_pass %||% character(0))),
    rds_path = rds_path,
    meta = obj
  )
}

pipeline_intersect_named_vars <- function(vars, data_names, db_tag, what) {
  vars <- unique(as.character(vars)[nzchar(as.character(vars))])
  if (!length(vars)) return(character(0))
  if (is.null(data_names)) return(vars)
  present <- intersect(vars, data_names)
  missing <- setdiff(vars, data_names)
  if (length(missing)) {
    cli::cli_alert_warning(
      "{db_tag}: 主库{what}在本库缺失 {length(missing)} 个，已跳过: {paste(head(missing, 8), collapse = ', ')}"
    )
  }
  present
}

pipeline_inject_primary_assoc_covariates <- function(cx, root, config, db_tag = "DB2") {
  loaded <- pipeline_load_primary_assoc_covariates(root, config, must_exist = FALSE)
  if (is.null(loaded)) {
    cli::cli_alert_warning(
      "{db_tag}: 未找到主库 assoc_covariates_primary.rds，外验 Table 2 仍可能只解析出 Age。"
    )
    return(cx)
  }
  dat <- cx$data$imputed %||% cx$data$test %||% cx$data$cleaned
  nm <- if (is.data.frame(dat)) names(dat) else NULL
  m1 <- pipeline_intersect_named_vars(loaded$model1, nm, db_tag, "Model1")
  m2 <- pipeline_intersect_named_vars(loaded$model2, nm, db_tag, "Model2")
  if (!length(m1)) {
    cli::cli_alert_warning("{db_tag}: 主库 Model1 在本库列中全部缺失，放弃注入。")
    return(cx)
  }
  m2 <- unique(c(m1, setdiff(m2, m1)))
  vif_pass <- pipeline_intersect_named_vars(
    loaded$vif_screen_pass, nm, db_tag, "VIF screen"
  )
  cx$results$assoc_model1_factors <- m1
  cx$results$assoc_model2_factors <- m2
  cx$results$assoc_model2_extras <- setdiff(m2, m1)
  cx$results$logistic_model1_factors <- m1
  cx$results$logistic_model2_factors <- m2
  cx$results$cox_model1_covariates <- m1
  cx$results$cox_model2_covariates <- setdiff(m2, m1)
  cx$results$Model1Factors <- m1
  ## assoc bundle 读 Model2Factors 当 Table 2 M2；ML 特征另存 feature_selection_final
  cx$results$Model2Factors <- m2
  if (length(vif_pass)) cx$results$vif_screen_pass <- vif_pass
  cx$results$assoc_covariates_inherited_from <- "primary"
  cx$results$assoc_covariates_primary_rds <- loaded$rds_path
  cx$results$assoc_covariate_note <- sprintf(
    "继承主库训练集 Model1=%s; Model2=%s",
    paste(m1, collapse = "+"), paste(m2, collapse = "+")
  )
  n2 <- length(m2)
  if (n2 > 0L) {
    cx$config$logistic <- modifyList(
      cx$config$logistic %||% list(),
      list(model2_max_covariates = max(
        n2,
        as.integer((cx$config$logistic %||% list())$model2_max_covariates %||% 10L)
      ))
    )
    if (!is.null(cx$config$incidence)) {
      cx$config$incidence$model2_max_covariates <- max(
        n2,
        as.integer((cx$config$incidence %||% list())$model2_max_covariates %||% 10L)
      )
    }
  }
  cli::cli_alert_success(
    "{db_tag}: 已注入主库训练集协变量 M1={length(m1)} M2={length(m2)} VIF={length(vif_pass)}"
  )
  cx
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
  ## Table 2 / VIF 必须跟训练集选出的协变量，不能再在外验库用空 UV 解析成 Age
  if (exists("pipeline_inject_primary_assoc_covariates", mode = "function")) {
    cx <- pipeline_inject_primary_assoc_covariates(cx, root, config, db_tag)
  }
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

#' 铁律：主库插补后 N 须 ≥ 外验库。从共享/指标 index 检查点读行数。
#'
#' @param stop_on_fail TRUE 时硬停；FALSE 仅警告（调试用）
ml_dual_assert_primary_larger_n <- function(config, ix = NULL, stop_on_fail = TRUE) {
  dual <- config$dual_db %||% list()
  if (!isTRUE(dual$enable %||% FALSE)) return(invisible(NULL))
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  shared_base <- bc$shared_ck_base %||% file.path(
    dual$checkpoint_base %||% "checkpoints", "_shared"
  )
  ## use_ix=TRUE 读 per-index（本组合完整病例）；FALSE 读 shared 队列层（推导库人数）。
  .n_from_ck <- function(slot, use_ix = TRUE) {
    dir <- tryCatch(
      incidence_batch_shared_ck_dir(config, slot),
      error = function(e) {
        file.path(shared_base, dual_db_slot_path_name(config, slot))
      }
    )
    if (use_ix && !is.null(ix) && nzchar(as.character(ix)[1L])) {
      ck_base <- bc$index_ck_base %||% file.path(
        dual$checkpoint_base %||% "checkpoints", "by_index"
      )
      per <- file.path(ck_base, as.character(ix)[1L], dual_db_slot_path_name(config, slot))
      for (stem in c("imputation", "index")) {
        p <- file.path(per, paste0(stem, ".rds"))
        if (!file.exists(p) && dir.exists(per)) {
          hits <- list.files(
            per,
            pattern = paste0("(^|_)", stem, "\\.rds$"),
            full.names = TRUE
          )
          if (length(hits)) p <- hits[[1L]]
        }
        if (!file.exists(p)) next
        obj <- tryCatch(readRDS(p), error = function(e) NULL)
        df <- tryCatch(
          if (exists("incidence_batch_ctx_data", mode = "function")) {
            incidence_batch_ctx_data(obj$ctx)
          } else {
            obj$ctx$data$imputed %||% obj$ctx$data$analysis %||% obj$ctx$data$raw
          },
          error = function(e) NULL
        )
        if (is.data.frame(df) && nrow(df) > 0L) return(as.integer(nrow(df)))
      }
    }
    p <- file.path(dir, "index.rds")
    if (!file.exists(p)) return(NA_integer_)
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    df <- tryCatch(
      if (exists("incidence_batch_ctx_data", mode = "function")) {
        incidence_batch_ctx_data(obj$ctx)
      } else {
        obj$ctx$data$imputed %||% obj$ctx$data$analysis %||% obj$ctx$data$raw
      },
      error = function(e) NULL
    )
    if (is.data.frame(df) && nrow(df) > 0L) as.integer(nrow(df)) else NA_integer_
  }
  ## 「人多当主库」= 推导库队列人数（shared 层），据此定角色；
  ## 各指标/组合的完整病例 N 只作信息 + 缺失提醒，不翻转主/外验（否则 10 组合角色会不一致）。
  pri_nm <- as.character((dual$primary %||% list())$name %||% "primary")[1L]
  sec_nm <- as.character((dual$secondary %||% list())$name %||% "secondary")[1L]
  n_pri_q <- .n_from_ck("nhanes", use_ix = FALSE)
  n_sec_q <- .n_from_ck("mimic", use_ix = FALSE)
  n_pri <- .n_from_ck("nhanes")
  n_sec <- .n_from_ck("mimic")

  if (!is.na(n_pri) && !is.na(n_sec)) {
    cli::cli_alert_info(
      "双库样本量[{ix %||% 'ALL'} 完整病例]: 主库 {pri_nm} N={n_pri}; 外验 {sec_nm} N={n_sec}"
    )
  }
  if (is.na(n_pri_q) || is.na(n_sec_q)) {
    cli::cli_alert_warning(
      "主库/外验队列 N 未能从共享层读取（primary={n_pri_q}, secondary={n_sec_q}），跳过 N 校验"
    )
    return(invisible(list(
      primary_n = n_pri, secondary_n = n_sec,
      primary_cohort_n = n_pri_q, secondary_cohort_n = n_sec_q, ok = NA
    )))
  }
  cli::cli_alert_info(
    "队列人数: 主库 {pri_nm} N={n_pri_q}; 外验 {sec_nm} N={n_sec_q}"
  )
  if (n_pri_q < n_sec_q) {
    msg <- paste0(
      "主库队列 N(", n_pri_q, ", ", pri_nm, ") < 外验队列 N(", n_sec_q, ", ", sec_nm,
      ")。请在 .study 中把人多的库设为 primary_*，人少的设为 secondary_*。"
    )
    if (isTRUE(stop_on_fail)) stop(msg, call. = FALSE)
    cli::cli_alert_danger(msg)
    return(invisible(list(
      primary_n = n_pri, secondary_n = n_sec,
      primary_cohort_n = n_pri_q, secondary_cohort_n = n_sec_q, ok = FALSE
    )))
  }
  ## 角色对（队列人多=主库）但本指标完整病例主库<外验 → 缺失结构提醒（不 fail）
  if (!is.na(n_pri) && !is.na(n_sec) && n_pri < n_sec) {
    cli::cli_alert_warning(paste0(
      "本指标/组合 [{ix %||% '-'}] 主库完整病例 N({n_pri}) < 外验 N({n_sec})：",
      "主库相关列缺失更多，请在结果解读 / Table1 脚注披露；角色仍按队列人数固定。"
    ))
  }
  invisible(list(
    primary_n = n_pri, secondary_n = n_sec,
    primary_cohort_n = n_pri_q, secondary_cohort_n = n_sec_q, ok = TRUE
  ))
}
