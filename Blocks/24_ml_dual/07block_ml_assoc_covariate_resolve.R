###############################################################################
#  ml_assoc_covariate_resolve — 在特征选择之后锁定 Cox/Logistic 协变量
#
#  register_block: "ml_assoc_covariate_resolve"
#  典型位置: ml_feature_selection_bundle 之后、ml_assoc_bundle 之前
#
#  铁律（全项目复用）:
#    Model 1 = Age（强制）
#    Model 2 = Age + 单因素显著且未进最终 ML 特征的变量
#
#  config$assoc_covariate = list(
#    enable = TRUE,
#    force_model1 = "Age",
#    uv_source = "tb1",
#    max_model2_extra = Inf,   # 小样本可设 1～2
#    exclude_extra = c(),
#    allow_m2_eq_m1 = TRUE
#  )
###############################################################################

block_ml_assoc_covariate_resolve <- function(ctx, ...) {
  ## 引擎根：worker cwd 常为课题目录，勿用 project$root/getwd() 找 R/
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  helper <- file.path(root, "R/ml_assoc_covariate_rule.R")
  if (file.exists(helper)) source(helper, local = FALSE)
  if (!exists("ml_apply_assoc_covariate_rule_to_ctx", mode = "function")) {
    stop("ml_assoc_covariate_resolve: missing R/ml_assoc_covariate_rule.R", call. = FALSE)
  }
  ml_feats <- as.character(ctx$results$feature_selection_final %||% character(0))
  if (!length(ml_feats)) {
    cli::cli_alert_warning(
      "ml_assoc_covariate_resolve: 尚无 feature_selection_final；仍按 UV 解析（ML 排除集为空）。"
    )
  }
  helper_pipe <- file.path(root, "R/ml_dual_pipeline_helpers.R")
  if (file.exists(helper_pipe)) source(helper_pipe, local = FALSE)
  inherited <- identical(ctx$results$feature_selection_inherited_from, "primary") ||
    identical(ctx$results$assoc_covariates_inherited_from, "primary")
  if (inherited && exists("pipeline_inject_primary_assoc_covariates", mode = "function") &&
      !identical(ctx$results$assoc_covariates_inherited_from, "primary")) {
    db_tag <- ctx$config$project$database %||% "DB2"
    ctx <- pipeline_inject_primary_assoc_covariates(ctx, root, ctx$config, db_tag)
  }
  ctx <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
  ctx$results$ml_assoc_covariate_resolved <- TRUE
  ## 主库：把训练集锁定的 M1/M2/VIF 写给次库（已按插补后双库交集裁剪）
  if (!inherited && exists("pipeline_export_primary_assoc_covariates", mode = "function")) {
    exported <- tryCatch(
      pipeline_export_primary_assoc_covariates(ctx, root, ctx$config),
      error = function(e) {
        cli::cli_alert_warning("导出主库 assoc 协变量失败: {e$message}")
        NULL
      }
    )
    if (!is.null(exported) && length(exported$model1)) {
      ctx$results$assoc_model1_factors <- exported$model1
      ctx$results$assoc_model2_factors <- exported$model2
      ctx$results$logistic_model1_factors <- exported$model1
      ctx$results$logistic_model2_factors <- exported$model2
      if (length(exported$vif_screen_pass)) {
        ctx$results$vif_screen_pass <- exported$vif_screen_pass
      }
    }
  }
  ctx
}

register_block(
  "ml_assoc_covariate_resolve",
  block_ml_assoc_covariate_resolve,
  "Cox/Logistic：Age 强制 Model1；Model2=UV显著且未进 ML（预后可改 VIF 池）"
)
