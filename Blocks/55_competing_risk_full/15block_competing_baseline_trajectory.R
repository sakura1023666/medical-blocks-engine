###############################################################################
#  competing_baseline_trajectory — Table 3（全变量）+ 暴露不显著早停
###############################################################################

block_competing_baseline_trajectory <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_baseline_trajectory: 无数据", call. = FALSE)
  if (!exists(".competing_baseline_table", mode = "function")) {
    root <- cfg$project$root %||% getwd()
    source(file.path(root, "Blocks/55_competing_risk_full/14block_competing_baseline_quartile.R"), local = FALSE)
  }
  index_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  group_var <- bl$trajectory_var %||% paste0(index_var, "_trajectory")
  if (!group_var %in% names(data)) {
    cli::cli_alert_warning("competing_baseline_trajectory: 缺少 {group_var}，跳过")
    return(ctx)
  }
  vars <- .competing_baseline_all_vars(data, cfg, bl, index_var, group_var)
  tab <- .competing_baseline_table(data, group_var, vars)
  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, paste0("Table3_Baseline_", index_var, "_Trajectory.csv")),
                   row.names = FALSE)
  db <- as.character(cfg$project$database %||% "MIMIC")[1L]
  title <- sprintf("Table 3-%s. Baseline characteristics by %s trajectory", db, index_var)
  dest <- file.path(out_dir, paste0(title, ".xlsx"))
  if (exists("export_sci_table", mode = "function")) {
    export_sci_table(tab, dest, title = title)
    if (exists("render_queued_tables", mode = "function")) {
      ctx <- tryCatch(render_queued_tables(ctx), error = function(e) ctx)
    }
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(tab, dest, overwrite = TRUE)
  }
  ctx$results$competing_baseline_trajectory <- list(table = tab, vars = vars)

  early_stop <- isTRUE(bl$early_stop_if_index_ns %||% TRUE)
  sig_cutoff <- as.numeric(bl$table3_sig_cutoff %||% bl$table1_sig_cutoff %||% 0.05)[1L]
  if (early_stop && index_var %in% names(data)) {
    event_col <- bl$event_type_col %||% "competing_status_28d"
    primary <- as.integer(bl$primary_cause %||% 1L)[1L]
    idx_p <- NA_real_
    if (event_col %in% names(data)) {
      y <- as.integer(data[[event_col]] == primary)
      x <- suppressWarnings(as.numeric(data[[index_var]]))
      ok <- is.finite(x) & !is.na(y)
      if (sum(ok) >= 20L && length(unique(y[ok])) >= 2L) {
        idx_p <- tryCatch(stats::wilcox.test(x[ok] ~ factor(y[ok]))$p.value, error = function(e) NA_real_)
      }
    }
    if (!is.finite(idx_p)) {
      hit <- grepl(paste0("^", index_var, "(,|$)"), tab$Variable %||% tab$variable)
      if (any(hit)) idx_p <- suppressWarnings(as.numeric((tab[["P value"]] %||% tab$p)[hit][1L]))
    }
    if (is.finite(idx_p) && idx_p >= sig_cutoff) {
      stop(
        "BASELINE_INDEX_NS_STOP: 暴露指标 ", index_var,
        " Table3 比较 P = ", format(round(idx_p, 4), scientific = FALSE),
        " >= ", sig_cutoff, "，按 early_stop_if_index_ns 早停（记为失败）。",
        call. = FALSE
      )
    }
    cli::cli_alert_info("Table3 早停检查通过: {index_var} P={format(round(idx_p, 4), scientific = FALSE)}")
  }
  cli::cli_alert_success("Table3 完成: {length(vars)} 变量 × {group_var}")
  ctx
}

register_block("competing_baseline_trajectory", block_competing_baseline_trajectory, "基线特征表（轨迹，全变量）")
