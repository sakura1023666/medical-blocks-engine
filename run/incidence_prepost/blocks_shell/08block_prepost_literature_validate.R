###############################################################################
#  prepost_literature_validate — Chen 2024 原文斜率对照
###############################################################################

block_prepost_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  targets <- bl$literature_targets %||% list(global_post_slope = -0.023, visuospatial_post_slope = -0.036)
  tol <- as.numeric(bl$literature_tol_pct %||% 25)
  rows <- list()
  lmm <- (ctx$results$prepost_lmm_fit %||% list())$post_slope_change
  if (is.null(lmm)) {
    p <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_LMM_Global.csv")
    if (file.exists(p)) {
      t <- utils::read.csv(p, stringsAsFactors = FALSE)
      hit <- t[t$term == "diabetes_years_after", , drop = FALSE]
      if (!nrow(hit)) hit <- t[grepl("Post_diabetes", t$term) & grepl(":", t$term), , drop = FALSE]
      if (nrow(hit)) lmm <- hit$estimate[1L]
    }
  }
  if (is.null(lmm) || !length(lmm)) lmm <- NA_real_
  rows[[length(rows) + 1L]] <- literature_compare_metric(lmm, targets$global_post_slope, tol, "Global post-onset slope change")
  dom <- (ctx$results$prepost_domain_slopes %||% list())$table
  if (is.null(dom)) {
    p <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Domain_Slopes.csv")
    if (file.exists(p)) dom <- utils::read.csv(p, stringsAsFactors = FALSE)
  }
  if (!is.null(dom) && nrow(dom)) {
    vs <- dom[grepl("Visuospatial", dom$domain, ignore.case = TRUE), , drop = FALSE]
    if (nrow(vs)) rows[[length(rows) + 1L]] <- literature_compare_metric(
      vs$post_slope_change[1L], targets$visuospatial_post_slope, tol, "Visuospatial post slope"
    )
  }
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Literature_Validation.csv")
  tab <- literature_write_validation(rows, out, meta = list(paper = "Chen 2024 Neurology", tol_pct = tol))
  ctx$results$prepost_literature_validate <- list(table = tab, pass = sum(tab$within_tol %in% TRUE, na.rm = TRUE))
  cli::cli_alert_success("发病前后文献对照完成")
  ctx
}

register_block("prepost_literature_validate", block_prepost_literature_validate, "发病前后文献对照")
