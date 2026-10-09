###############################################################################
#  ml_inherit_primary_features — 验证库注入主库 feature_selection_final
#
#  register_block: "ml_inherit_primary_features"
#  典型流水线: imputation → 本块 → train_validation → ml_models_bundle …
#
#  读取 config$dual_db$harmonization_dir 下 feature_selection_final_primary.rds
#  （由主库 ml_feature_selection_bundle 或 run_ml_dual 导出）
###############################################################################

block_ml_inherit_primary_features <- function(ctx, ...) {
  bl <- ctx$config$ml_inherit_primary_features %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("ml_inherit_primary_features$enable=FALSE，跳过。")
    return(ctx)
  }
  root <- ctx$config$project$root %||% getwd()
  if (!exists("pipeline_inject_primary_features_to_ctx", mode = "function")) {
    source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)
  }
  db_tag <- ctx$config$project$database %||% "MIMIC"
  ctx <- pipeline_inject_primary_features_to_ctx(ctx, root, ctx$config, db_tag)
  ## 外验：用训练集选出的 VIF 变量，在本库 imputed 上出报告表
  if (exists("ml_vif_export_fixed_set", mode = "function") ||
      file.exists(file.path(root, "R/ml_assoc_data_slots.R"))) {
    if (!exists("ml_vif_export_fixed_set", mode = "function")) {
      source(file.path(root, "R/ml_assoc_data_slots.R"), local = FALSE)
    }
    vars <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
    dat <- ctx$data$imputed %||% ctx$data$cleaned
    if (length(vars) && is.data.frame(dat) && nrow(dat) > 0L) {
      cap <- if (exists("ml_vif_holdout_caption", mode = "function")) {
        ml_vif_holdout_caption("imputed", ctx$config)
      } else {
        "Multicollinearity Analysis VIF screen (external validation set)"
      }
      ml_vif_export_fixed_set(ctx, dat, vars, cap)
    }
  }
  ctx
}

register_block(
  "ml_inherit_primary_features",
  block_ml_inherit_primary_features,
  "验证库：注入主库 ML 特征清单"
)
