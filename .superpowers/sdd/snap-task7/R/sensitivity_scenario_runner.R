###############################################################################
#  sensitivity_scenario_runner.R — 发病/预后通用敏感性场景 runner
#
#  默认场景：Age <65 / Age >=65 / 排除高血压 / 排除糖尿病
#  - 双库批量：复用 incidence_sensitivity_suite 的 worker 过滤机制
#  - 单库研究：就地过滤 imputed 数据并可选重跑指定 blocks
###############################################################################

sensitivity_resolve_scenarios <- function(config, data = NULL) {
  if (exists("pipeline_sensitivity_scenarios_for_data", mode = "function")) {
    return(pipeline_sensitivity_scenarios_for_data(config, data))
  }
  if (exists("pipeline_default_sensitivity_scenarios", mode = "function")) {
    return(pipeline_default_sensitivity_scenarios(config))
  }
  list()
}

#' 单库敏感性：对过滤后数据跑指定 blocks（默认只记录队列 n）
sensitivity_single_study_pass <- function(ctx, root = NULL) {
  cfg <- ctx$config %||% list()
  sens <- (cfg$capability %||% list())$sensitivity_suite %||%
    (cfg$sensitivity_suite %||% list())
  if (!isTRUE(sens$enable %||% FALSE)) {
    cli::cli_alert_info("sensitivity_suite$enable 未开启，跳过单库敏感性。")
    return(ctx)
  }
  data0 <- ctx$data$imputed %||% ctx$data$cleaned
  scenarios <- sensitivity_resolve_scenarios(cfg, data0)
  if (!length(scenarios)) {
    cli::cli_alert_info("无可用敏感性场景（变量缺失或未配置）。")
    return(ctx)
  }
  out_dir <- file.path(ctx$output_dir %||% ".", "sensitivity")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  summary_rows <- list()
  for (sg in scenarios) {
    d1 <- if (exists("pipeline_apply_row_filter_expr", mode = "function")) {
      pipeline_apply_row_filter_expr(data0, sg$expr)
    } else {
      data0
    }
    n0 <- if (is.null(data0)) NA_integer_ else nrow(data0)
    n1 <- if (is.null(d1)) NA_integer_ else nrow(d1)
    lab <- gsub("[^A-Za-z0-9._-]+", "_", sg$label)
    dest <- file.path(out_dir, lab)
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(
      data.frame(scenario = sg$label, expr = sg$expr, n_before = n0, n_after = n1,
                 stringsAsFactors = FALSE),
      file.path(dest, "cohort_n.csv"),
      row.names = FALSE
    )
    if (isTRUE(sens$export_filtered_data %||% FALSE) && !is.null(d1)) {
      utils::write.csv(d1, file.path(dest, "filtered_imputed.csv"), row.names = FALSE)
    }
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      scenario = sg$label, expr = sg$expr, n_before = n0, n_after = n1,
      status = if (is.finite(n1) && n1 >= as.integer(sens$min_n %||% 30L)) "ok" else "too_small",
      stringsAsFactors = FALSE
    )
    cli::cli_alert_info("sensitivity [{sg$label}]: n {n0} → {n1}")
  }
  tab <- do.call(rbind, summary_rows)
  ctx$results$sensitivity_scenarios_summary <- tab
  utils::write.csv(tab, file.path(out_dir, "sensitivity_scenarios_summary.csv"), row.names = FALSE)
  ctx
}
