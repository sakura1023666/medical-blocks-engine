###############################################################################
#  logistic_tertile_iptw_weighted — MIMIC IPTW 加权三分位 Logistic（svyglm Table 2）。
#
#  register_block: "logistic_tertile_iptw_weighted"
#  典型流水线: iptw_balance → logistic_tertile_iptw_weighted
#  依赖: 00logistic_iptw_weighted_common.R
#
#  config: config$logistic_tertile_iptw_weighted
#  group_mode:
#    quantile    — 加权三分位 T1–T3（默认）
#    predefined  — group_var（默认 Index_Group_Tertile）+ group_levels
#
#  产出: [main_table] Table n.* IPTW-adjusted OR + p for trend
###############################################################################

block_logistic_tertile_iptw_weighted <- function(ctx, ...) {
  .liw00_run_iptw_logistic(
    ctx,
    cfg_key      = "logistic_tertile_iptw_weighted",
    block_name   = "logistic_tertile_iptw_weighted",
    group_fn     = function(design, index_var, bl_cfg, ctx, cfg) {
      .liw00_apply_tertile_group(design, index_var, bl_cfg)
    },
    label_suffix = "tertile",
    result_key   = "logistic_tertile_iptw_table"
  )
}

register_block(
  "logistic_tertile_iptw_weighted",
  block_logistic_tertile_iptw_weighted,
  "MIMIC IPTW-weighted tertile logistic (svyglm Table 2)"
)
