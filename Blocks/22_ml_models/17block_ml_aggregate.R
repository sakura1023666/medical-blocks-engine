
###############################################################################
#  ml_aggregate — 汇总各 ML 子块 evalresult_* / ctx$results$ml_eval_by_model
#
#  require: 至少一个 ML 训练子块已成功（或 Models/evalresult_*.RData 存在）
#
#  ml_aggregate = list(
#    enable = TRUE,
#    pause_enable = TRUE,
#    pause_on_no_models = TRUE,
#  ),
###############################################################################

.mlag17_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.mlag17_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "ml_aggregate",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ml_aggregate — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.mlag17_load_eval_from_rdata <- function(models_dir, tag) {
  path <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  if (!file.exists(path)) return(NULL)
  env <- new.env(parent = emptyenv())
  tryCatch(load(path, envir = env), error = function(e) NULL)
  ev_nm <- paste0("eval_", tag)
  if (ev_nm %in% names(env)) return(get(ev_nm, envir = env))
  if ("eval" %in% names(env)) return(get("eval", envir = env))
  NULL
}

block_ml_aggregate <- function(ctx, ...) {
  bl_cfg <- ctx$config$ml_aggregate %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_aggregate$enable=FALSE，跳过。")
    return(ctx)
  }

  models_dir <- ctx$results$ml_models_models_dir %||%
    file.path(ctx$output_dir, "Models")
  all_eval <- list()

  by_model <- ctx$results[["ml_eval_by_model"]] %||% list()
  if (length(by_model)) {
    for (nm in names(by_model)) {
      if (is.data.frame(by_model[[nm]])) all_eval[[nm]] <- by_model[[nm]]
    }
  }

  if (!length(all_eval) && dir.exists(models_dir)) {
    rdata_files <- list.files(models_dir, pattern = "^evalresult_.*[.]RData$", full.names = FALSE)
    for (f in rdata_files) {
      tag <- sub("^evalresult_(.*)[.]RData$", "\\1", f)
      ev <- .mlag17_load_eval_from_rdata(models_dir, tag)
      if (!is.null(ev)) all_eval[[tag]] <- ev
    }
  }

  if (!length(all_eval)) {
    msg <- "未发现任何 ML 模型评估结果。"
    if (.mlag17_should_pause(bl_cfg, "pause_on_no_models")) {
      .mlag17_pause(ctx, msg, "请先运行需要的 ml_* 训练子块。")
    }
    cli::cli_alert_warning("ml_aggregate: {msg}")
    return(ctx)
  }

  eval_all <- dplyr::bind_rows(all_eval)
  fp <- file.path(ctx$output_dir_tables, "Table_ML_ModelPerformance.xlsx")
  export_sci_table(eval_all, fp, title = "Machine Learning Models Performance Summary")
  ctx$results$ml_eval_all <- eval_all
  ctx <- save_result(ctx, "ml_eval_all_export", eval_all, "ml_eval_all.csv")
  cli::cli_alert_success("ml_aggregate: 汇总 {nrow(eval_all)} 行性能指标。")

  all_models <- ctx$results[["ml_models"]] %||% list()
  if (nrow(eval_all)) {
    ev <- eval_all
    sub <- ev[tolower(as.character(ev$dataset)) == "test" &
                tolower(as.character(ev$.metric)) %in% c("roc_auc", "c_index"), , drop = FALSE]
    if (nrow(sub)) {
      sub <- sub[order(match(tolower(as.character(sub$.metric)), c("c_index", "roc_auc"))), , drop = FALSE]
      sub <- sub[!duplicated(sub$model), , drop = FALSE]
      dm <- c(
        "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "ENet" = "enet",
        "RSVM" = "rsvm", "MLP" = "mlp", "RealMLP" = "realmlp", "Logistic" = "logistic",
        "LightGBM" = "lightgbm", "KNN" = "knn", "TabPFN" = "tabpfn", "TabPFNv2" = "tabpfnv2",
        "RealTabPFN-2.5" = "realtabpfn_2_5",
        "AdaBoost" = "adaboost", "CatBoost" = "catboost", "TablCL_v2" = "tablcl_v2",
        "RSF" = "rsf", "Random Survival Forest (RSF)" = "rsf",
        "Random survival forest" = "rsf",
        "XGBSurv" = "xgbsurv", "XGBoost Survival (XGBSurv)" = "xgbsurv",
        "XGBoost-Cox" = "xgbsurv",
        "CoxBoost" = "coxboost",
        "GBM-Cox" = "gbmsurv",
        "Ridge-Cox" = "ridge_cox",
        "ElasticNet-Cox" = "enet_cox",
        "SurvivalSVM" = "survivalsvm",
        "mboost-Cox" = "mboost_cox"
      )
      .row_tag <- function(disp) {
        hit <- match(tolower(trimws(disp)), tolower(names(dm)), nomatch = NA_integer_)
        if (is.na(hit)) tolower(trimws(disp)) else unname(dm[hit])
      }
      sub[["tmp_ml_tag"]] <- vapply(as.character(sub$model), .row_tag, character(1L))
      in_fit <- sub[["tmp_ml_tag"]] %in% names(all_models)
      sub_use <- if (any(in_fit)) sub[in_fit, , drop = FALSE] else sub
      best <- sub_use[which.max(as.numeric(sub_use$.estimate)), , drop = FALSE]
      disp <- as.character(best$model[1L])
      hit <- match(tolower(trimws(disp)), tolower(names(dm)), nomatch = NA_integer_)
      ctx$results$ml_best_model_display <- disp
      ctx$results$ml_best_model_tag <- if (is.na(hit)) tolower(trimws(disp)) else unname(dm[hit])
      ctx$results$ml_best_auc <- as.numeric(best$.estimate[1L])
    }
  }

  ctx
}

register_block("ml_aggregate", block_ml_aggregate, "汇总 ML 子块性能表与 ml_best_model_tag")
