###############################################################################
#  dual_db_logistic_branch_harmonize — 已废弃：请用 dual_db_logistic_scheme_harmonize
###############################################################################

block_dual_db_logistic_branch_harmonize <- function(ctx) {
  cfg <- ctx$config
  if (!isTRUE((cfg$dual_db %||% list())$enable)) return(ctx)
  cli::cli_alert_info(
    "dual_db_logistic_branch_harmonize 已废弃；分位统一改在 logistic 初筛后由 dual_db_logistic_scheme_harmonize 执行。"
  )
  ctx
}

register_block(
  "dual_db_logistic_branch_harmonize",
  block_dual_db_logistic_branch_harmonize,
  "DEPRECATED: use dual_db_logistic_scheme_harmonize after logistic screen"
)
