###############################################################################
#  sensitivity_scenarios — 单库敏感性场景（默认仅年龄分层；Yes/No 由双库套件动态发现）
#
#  register_block: "sensitivity_scenarios"
###############################################################################

block_sensitivity_scenarios <- function(ctx, ...) {
  root <- (ctx$config$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))
  sens_fp <- file.path(root, "R/sensitivity_scenario_runner.R")
  if (file.exists(sens_fp) && !exists("sensitivity_single_study_pass", mode = "function")) {
    source(sens_fp, local = FALSE)
  }
  if (!exists("sensitivity_single_study_pass", mode = "function")) {
    cli::cli_alert_warning("sensitivity_scenarios: runner 未加载，跳过。")
    return(ctx)
  }
  sensitivity_single_study_pass(ctx, root = root)
}

register_block(
  "sensitivity_scenarios",
  block_sensitivity_scenarios,
  "通用敏感性场景：过滤队列并导出 n（可扩展完整重跑）"
)
