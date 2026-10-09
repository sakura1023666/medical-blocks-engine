###############################################################################
#  ml_eval_external — 用主库冻结模型在外验集上预测（不重训）
#
#  register_block: "ml_eval_external"
#  典型流水线: ml_inherit_primary_features → 本块（次库 split_mode=dev_internal_ext）
#
#  仅发病双库：人少的库整库当外部验证，不重训 12 模型。
#  读主库 Models/evalresult_*.RData 的 final_<tag>，在 ctx$data$test 上 predict。
#
#  config$ml_eval_external = list(
#    enable = TRUE   # FALSE 则跳过
#  )
###############################################################################

block_ml_eval_external <- function(ctx, ...) {
  bl <- ctx$config$ml_eval_external %||% list()
  if (!isTRUE(bl$enable %||% FALSE)) {
    cli::cli_alert_info("ml_eval_external$enable 未开，跳过。")
    return(ctx)
  }
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  src <- file.path(er, "R/ml_dual_dev_ext.R")
  if (file.exists(src)) source(src, local = FALSE)
  eval_src <- file.path(er, "Blocks/22_ml_models/00block_ml_eval_common.R")
  if (file.exists(eval_src)) source(eval_src, local = FALSE)
  suppressPackageStartupMessages({
    if (requireNamespace("tidymodels", quietly = TRUE)) library(tidymodels)
    else {
      if (requireNamespace("parsnip", quietly = TRUE)) library(parsnip)
      if (requireNamespace("workflows", quietly = TRUE)) library(workflows)
      if (requireNamespace("recipes", quietly = TRUE)) library(recipes)
    }
  })

  te <- ctx$data$test
  if (is.null(te) || !is.data.frame(te) || nrow(te) < 1L) {
    stop("ml_eval_external: 需要非空 ctx$data$test（外验全集）。", call. = FALSE)
  }
  feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  miss <- setdiff(feats, names(te))
  if (length(miss)) {
    stop(
      "ml_eval_external: 外验数据缺主库特征: ", paste(miss, collapse = ", "),
      "（检查 Gate A 是否误删双库共有列；dev_internal_ext 下主库所选特征必须在次库保留）",
      call. = FALSE
    )
  }
  ana <- as.character(ctx$config$project$analysis_group %||% "Case")[1L]
  ref <- as.character(ctx$config$project$reference_group %||% "Control")[1L]
  if (!"Group" %in% names(te)) {
    oc <- ctx$config$data$outcome_column %||% "Disease"
    te$Group <- factor(
      ifelse(trimws(as.character(te[[oc]])) == ana, ana, ref),
      levels = c(ref, ana)
    )
    ctx$data$test <- te
  }

  ix_root <- dirname(ctx$config$project$output_dir %||% ".")
  pri_slot <- dual_db_slot_path_name(ctx$config, "nhanes")
  pri_dir <- file.path(ix_root, pri_slot)
  files <- ml_dual_dev_ext_find_evalresults(pri_dir)
  if (!length(files)) {
    stop("ml_eval_external: 未找到主库 evalresult_*.RData（请先完成主库 ML 训练）。", call. = FALSE)
  }
  train_pri <- ml_dual_dev_ext_load_primary_train(ctx, pri_dir)
  if (is.null(train_pri)) {
    stop("ml_eval_external: 未找到主库训练集，无法按训练 recipe bake 外验。", call. = FALSE)
  }

  models_dir <- file.path(ctx$output_dir %||% ".", "Models")
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  all_eval <- list()
  n_ok <- 0L

  for (f in files) {
    L <- ml_dual_dev_ext_load_eval(f)
    if (is.null(L) || is.null(L$final)) {
      cli::cli_alert_warning("ml_eval_external: 跳过无冻结模型 {basename(f)}")
      next
    }
    tag <- L$tag
    scale_type <- ml_dual_dev_ext_scale_for_tag(tag)
    baked <- tryCatch(
      ml_dual_dev_ext_bake_newdata(train_pri, te, feats, scale_type),
      error = function(e) {
        cli::cli_alert_warning("ml_eval_external: {tag} bake 失败: {e$message}")
        NULL
      }
    )
    if (is.null(baked)) next
    pred <- tryCatch(
      ml_dual_dev_ext_predict_new(L$final, baked, ana, ref),
      error = function(e) {
        cli::cli_alert_warning("ml_eval_external: 模型 {tag} 外验预测失败: {e$message}")
        NULL
      }
    )
    if (is.null(pred) || !nrow(pred)) {
      cli::cli_alert_warning("ml_eval_external: 模型 {tag} 外验预测失败，跳过。")
      next
    }
    pred$model <- ml_dual_dev_ext_display(tag)
    pred$dataset <- "test"
    pred_ref <- paste0(".pred_", make.names(ref))
    ev <- tryCatch(
      .ml_recompute_eval_from_preds(
        L$predtrain, pred, pred_ref, ref, ana,
        ml_dual_dev_ext_display(tag)
      ),
      error = function(e) {
        cli::cli_alert_warning("ml_eval_external: {tag} eval 失败: {e$message}")
        NULL
      }
    )
    ## 只保留外验 test 行写入本库；train 行仍来自主库文件
    tag_pt <- paste0("predtrain_", tag)
    tag_pv <- paste0("predtest_", tag)
    tag_ft <- paste0("final_", tag)
    tag_ev <- paste0("eval_", tag)
    save_env <- new.env(parent = emptyenv())
    assign(tag_pt, L$predtrain, envir = save_env)
    assign(tag_pv, pred, envir = save_env)
    assign(tag_ft, L$final, envir = save_env)
    if (!is.null(ev)) assign(tag_ev, ev, envir = save_env)
    save(
      list = ls(envir = save_env),
      file = file.path(models_dir, paste0("evalresult_", tag, ".RData")),
      envir = save_env
    )
    if (!is.null(ev)) {
      ev_te <- ev[tolower(as.character(ev$dataset)) == "test", , drop = FALSE]
      if (nrow(ev_te)) all_eval[[length(all_eval) + 1L]] <- ev_te
    }
    n_ok <- n_ok + 1L
    cli::cli_alert_info("ml_eval_external: {tag} 外验 n={nrow(pred)}")
  }
  if (length(all_eval)) {
    ctx$results$ml_eval_all <- dplyr::bind_rows(all_eval)
  }
  if (n_ok < 1L) {
    stop("ml_eval_external: 没有任何主库模型成功预测外验集。", call. = FALSE)
  }
  cli::cli_alert_success("ml_eval_external: 已用 {n_ok} 个冻结模型评估外验集。")
  ctx
}

register_block(
  "ml_eval_external",
  block_ml_eval_external,
  "外验库：冻结主库模型预测（不重训）"
)
