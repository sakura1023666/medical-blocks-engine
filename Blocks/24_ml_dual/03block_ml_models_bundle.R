###############################################################################
#  ml_models_bundle — 按 config$ml_models$methods 训练多模型 + ml_aggregate
#
#  register_block: "ml_models_bundle"
#  前置: train_validation
###############################################################################

block_ml_models_bundle <- function(ctx, ...) {
  ml <- ctx$config$ml_models %||% list()
  if (isFALSE(ml$enable %||% TRUE)) {
    cli::cli_alert_info("ml_models$enable=FALSE，跳过 ml_models_bundle。")
    return(ctx)
  }
  if (!length(ctx$results$feature_selection_final %||% character(0))) {
    if (exists("load_feature_selection_final_into_ctx", mode = "function")) {
      ctx <- load_feature_selection_final_into_ctx(ctx)
    }
  }
  use <- ml$methods
  all_tags <- c(
    "ml_dt", "ml_rf", "ml_xgboost", "ml_enet", "ml_rsvm", "ml_mlp", "ml_realmlp",
    "ml_logistic", "ml_lightgbm", "ml_knn", "ml_adaboost", "ml_catboost",
    "ml_tabpfn", "ml_tabpfnv2", "ml_realtabpfn_2_5", "ml_tablcl_v2",
    "ml_rsf", "ml_xgbsurv",
    "ml_coxboost", "ml_gbmsurv", "ml_ridge_cox", "ml_enet_cox",
    "ml_survivalsvm", "ml_mboost_cox"
  )
  tag_map <- stats::setNames(all_tags, sub("^ml_", "", all_tags))
  ## 别名：文献名 → tag
  alias <- c(
    "xgboost-cox" = "xgbsurv",
    "xgboost_cox" = "xgbsurv",
    "xgb_cox" = "xgbsurv",
    "gbm-cox" = "gbmsurv",
    "gbm_cox" = "gbmsurv",
    "random_survival_forest" = "rsf",
    "random-survival-forest" = "rsf",
    "ridge-cox" = "ridge_cox",
    "elasticnet-cox" = "enet_cox",
    "elastic_net_cox" = "enet_cox",
    "mboost-cox" = "mboost_cox"
  )
  if (is.null(use) || !length(use)) {
    use <- names(tag_map)
  }
  use <- tolower(as.character(use))
  use <- gsub("-", "_", use, fixed = TRUE)
  for (i in seq_along(use)) {
    ## 注意：原子命名向量上 [[未知名字]] 会直接报 subscript out of bounds（list 才返回 NULL），
    ## 必须先做名字存在性判断，否则任何非 survival 别名的方法名（如 "dt"）都会炸
    if (use[[i]] %in% names(alias)) use[[i]] <- alias[[use[[i]]]]
  }
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  for (u in use) {
    tag <- tag_map[[u]] %||% paste0("ml_", u)
    if (exists("pipeline_source_block", mode = "function") &&
        tag %in% names(pipeline_block_sources(root))) {
      pipeline_source_block(root, tag)
    }
    if (exists(tag, envir = .block_registry)) {
      ctx <- tryCatch(
        run_block(ctx, tag),
        error = function(e) {
          cli::cli_alert_warning("跳过 {tag}: {conditionMessage(e)}")
          ctx
        }
      )
    }
  }
  if (exists("pipeline_source_block", mode = "function") &&
      "ml_aggregate" %in% names(pipeline_block_sources(root))) {
    pipeline_source_block(root, "ml_aggregate")
  }
  if (exists("ml_aggregate", envir = .block_registry)) {
    ctx <- run_block(ctx, "ml_aggregate")
  }
  ctx
}

register_block(
  "ml_models_bundle",
  block_ml_models_bundle,
  "ML 多模型训练 + 汇总最优模型"
)
