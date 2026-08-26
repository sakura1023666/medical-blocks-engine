###############################################################################
#  logistic_binary_iptw_weighted — MIMIC IPTW 加权二分位 Logistic（svyglm Table 2）。
#
#  register_block: "logistic_binary_iptw_weighted"
#  典型流水线: iptw_balance → logistic_binary_iptw_weighted
#  依赖: 00logistic_iptw_weighted_common.R（pipeline 自动 source）
#
#  config: config$logistic_binary_iptw_weighted
#  读: ctx$results$iptw_design
#
#  group_mode（默认 median）:
#    median      — 加权中位数二分 Q1/Q2（默认）
#    cutoff      — 自定义/ROC cutoff（cutoff_value 或 ctx$results$roc_cutoff）
#    predefined  — 使用已有列 group_var（如 Index_Group）+ 可选 group_levels
#
#  产出: [main_table] Table n.* IPTW-adjusted OR（Crude / Model1 / Model2）
###############################################################################

block_logistic_binary_iptw_weighted <- function(ctx, ...) {
  .liw00_run_iptw_logistic(
    ctx,
    cfg_key      = "logistic_binary_iptw_weighted",
    block_name   = "logistic_binary_iptw_weighted",
    group_fn     = .liw00_apply_binary_group,
    label_suffix = "binary",
    result_key   = "logistic_binary_iptw_table"
  )
}

register_block(
  "logistic_binary_iptw_weighted",
  block_logistic_binary_iptw_weighted,
  "MIMIC IPTW-weighted binary logistic (median/cutoff/predefined, svyglm Table 2)"
)
