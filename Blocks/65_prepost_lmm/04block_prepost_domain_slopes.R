###############################################################################
#  prepost_domain_slopes — 四认知域 Chen piecewise LMM
###############################################################################

block_prepost_domain_slopes <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_prepost_chen.R"), local = FALSE)
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  if (!"diabetes_grp" %in% names(data)) {
    data <- prepost_chen_build_composite(data, bl)
    data <- prepost_chen_piecewise_vars(data, bl)
    ctx$data$prepost_long <- data
  }
  domains <- bl$domain_cols %||% c("Episodic_memory_z", "Visuospatial_z", "Attention_calc_z", "Orientation_z")
  domains <- intersect(domains, names(data))
  if (!length(domains)) domains <- intersect(c("Episodic_memory", "Visuospatial", "Attention_calc", "Orientation"), names(data))
  rows <- list()
  for (dom in domains) {
    res <- tryCatch(prepost_chen_fit_lmm(data, dom, bl), error = function(e) NULL)
    if (is.null(res)) next
    ps <- res$post_slope
    rows[[length(rows) + 1L]] <- data.frame(
      domain = dom,
      post_slope_change = if (length(ps)) ps[1L] else NA_real_,
      method = res$method,
      stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Domain_Slopes.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$prepost_domain_slopes <- list(table = tab)
  cli::cli_alert_success("四认知域 piecewise LMM 完成")
  ctx
}

register_block("prepost_domain_slopes", block_prepost_domain_slopes, "分域 Chen LMM")
