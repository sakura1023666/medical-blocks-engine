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
  root <- ctx$config$project$root %||% getwd()
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
  ctx <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
  ctx$results$ml_assoc_covariate_resolved <- TRUE
  ctx
}

register_block(
  "ml_assoc_covariate_resolve",
  block_ml_assoc_covariate_resolve,
  "Cox/Logistic：Age 强制 Model1；Model2=UV显著且未进 ML"
)
