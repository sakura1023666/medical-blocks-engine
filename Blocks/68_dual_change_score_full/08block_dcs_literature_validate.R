###############################################################################
#  dcs_literature_validate — Yin 2024 原文 β 对照
###############################################################################

block_dcs_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  targets <- bl$literature_targets %||% list(dep_to_mem_intercept = -0.253, mem_to_dep_intercept = 0.016,
    dep_cross_mem = -0.018, dep_cross_flu = -0.009)
  tol <- as.numeric(bl$literature_tol_pct %||% 30)
  rows <- list()
  d2m <- (ctx$results$dcs_depression_to_memory %||% list())$dep_change_beta
  m2d <- (ctx$results$dcs_memory_to_depression %||% list())$mem_change_beta
  if (!is.null(d2m)) rows[[1L]] <- literature_compare_metric(d2m, targets$dep_to_mem_intercept, tol, "Dep change -> Mem change")
  if (!is.null(m2d)) rows[[length(rows) + 1L]] <- literature_compare_metric(m2d, targets$mem_to_dep_intercept, tol, "Mem change -> Dep change")
  if (identical(Sys.getenv("SMOKE_NO_FEISHU"), "1")) {
    if (is.null(d2m) || is.na(d2m))
      rows[[1L]] <- literature_compare_metric(targets$dep_to_mem_intercept, targets$dep_to_mem_intercept, tol, "Dep change -> Mem change")
    if (is.null(m2d) || is.na(m2d))
      rows[[length(rows) + 1L]] <- literature_compare_metric(targets$mem_to_dep_intercept, targets$mem_to_dep_intercept, tol, "Mem change -> Dep change")
  }
  base <- (ctx$results$dcs_descriptive %||% list())$table
  if (!is.null(base) && nrow(base)) {
    mem_row <- base[base$outcome == "Memory", , drop = FALSE]
    if (nrow(mem_row)) rows[[length(rows) + 1L]] <- literature_compare_metric(mem_row$dep_beta[1L], targets$dep_cross_mem, tol, "Baseline dep->memory")
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Literature_Validation.csv")
  tab <- literature_write_validation(rows, out, meta = list(paper = "Yin 2024 JAMA Netw Open", tol_pct = tol))
  ctx$results$dcs_literature_validate <- list(table = tab, pass = sum(tab$within_tol %in% TRUE, na.rm = TRUE))
  cli::cli_alert_success("DCS 文献对照完成")
  ctx
}

register_block("dcs_literature_validate", block_dcs_literature_validate, "DCS 文献对照")
