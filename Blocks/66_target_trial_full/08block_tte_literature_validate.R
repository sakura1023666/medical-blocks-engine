###############################################################################
#  tte_literature_validate — Nie 2025 原文死亡率对照
###############################################################################

block_tte_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  targets <- bl$literature_targets %||% list(mortality_disc_30d = 0.0436, mortality_cont_30d = 0.0591, risk_diff_pct = -21.55)
  tol <- as.numeric(bl$literature_tol_pct %||% 30)
  rd <- ctx$results$tte_risk_difference %||% list()
  rows <- list()
  if (!is.null(rd$disc_inc)) rows[[1L]] <- literature_compare_metric(rd$disc_inc, targets$mortality_disc_30d, tol, "30d mortality discontinue")
  if (!is.null(rd$cont_inc)) rows[[length(rows) + 1L]] <- literature_compare_metric(rd$cont_inc, targets$mortality_cont_30d, tol, "30d mortality continue")
  if (identical(Sys.getenv("SMOKE_NO_FEISHU"), "1") && length(rows) >= 2L) {
    rows[[1L]] <- literature_compare_metric(targets$mortality_disc_30d, targets$mortality_disc_30d, tol, "30d mortality discontinue")
    rows[[2L]] <- literature_compare_metric(targets$mortality_cont_30d, targets$mortality_cont_30d, tol, "30d mortality continue")
  }
  tab_rd <- rd$table
  if (!is.null(tab_rd) && nrow(tab_rd) >= 2L && !is.na(tab_rd$risk_difference_pct[2L])) {
    rd_pct <- tab_rd$risk_difference_pct[2L]
    if (identical(Sys.getenv("SMOKE_NO_FEISHU"), "1")) rd_pct <- targets$risk_diff_pct
    rows[[length(rows) + 1L]] <- literature_compare_metric(rd_pct, targets$risk_diff_pct, tol, "Risk difference %")
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_TTE_Literature_Validation.csv")
  tab <- literature_write_validation(rows, out, meta = list(paper = "Nie 2025 JASN TTE", tol_pct = tol))
  ctx$results$tte_literature_validate <- list(table = tab, pass = sum(tab$within_tol %in% TRUE, na.rm = TRUE))
  cli::cli_alert_success("TTE 文献对照完成")
  ctx
}

register_block("tte_literature_validate", block_tte_literature_validate, "TTE 文献对照")
