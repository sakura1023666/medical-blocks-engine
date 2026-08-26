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
    "ml_rsf", "ml_xgbsurv"
  )
  tag_map <- stats::setNames(all_tags, sub("^ml_", "", all_tags))
  if (is.null(use) || !length(use)) {
    use <- names(tag_map)
  }
  use <- tolower(as.character(use))
  root <- ctx$config$project$root %||% getwd()
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
