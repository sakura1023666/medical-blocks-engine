###############################################################################
#  logistic_quartile_iptw_weighted — MIMIC IPTW 加权四分位 Logistic（svyglm Table 2）。
#
#  register_block: "logistic_quartile_iptw_weighted"
#  典型流水线: iptw_balance → logistic_quartile_iptw_weighted
#  依赖: 00logistic_iptw_weighted_common.R
#
#  config: config$logistic_quartile_iptw_weighted
#  group_mode:
#    quantile    — 加权四分位 Q1–Q4（默认）
#    predefined  — group_var（默认 Index_Group_Quartile）+ group_levels
#
#  产出: [main_table] Table n.* IPTW-adjusted OR + p for trend
###############################################################################

block_logistic_quartile_iptw_weighted <- function(ctx, ...) {
  .liw00_run_iptw_logistic(
    ctx,
    cfg_key      = "logistic_quartile_iptw_weighted",
    block_name   = "logistic_quartile_iptw_weighted",
    group_fn     = function(design, index_var, bl_cfg, ctx, cfg) {
      .liw00_apply_quartile_group(design, index_var, bl_cfg)
    },
    label_suffix = "quartile",
    result_key   = "logistic_quartile_iptw_table"
  )
}

register_block(
  "logistic_quartile_iptw_weighted",
  block_logistic_quartile_iptw_weighted,
  "MIMIC IPTW-weighted quartile logistic (svyglm Table 2)"
)
