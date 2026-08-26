###############################################################################
#  dcs_sensitivity — Yin 2024 三项敏感性（孤独/低认知/卒中痴呆）
###############################################################################

block_dcs_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$dual_change_score %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_dcsm_yin.R"), local = FALSE)
  data <- ctx$data$dcs_long %||% ctx$data$cleaned
  scenarios <- list(
    full = data,
    exclude_low_cognition = if ("Memory_score" %in% names(data)) {
      q20 <- stats::quantile(data$Memory_score, 0.2, na.rm = TRUE)
      data[data$Memory_score > q20, , drop = FALSE]
    } else data,
    exclude_stroke_dementia = if ("Stroke_dementia" %in% names(data)) data[data$Stroke_dementia == 0L, , drop = FALSE] else data
  )
  rows <- list()
  for (nm in names(scenarios)) {
    sub <- scenarios[[nm]]
    if (nrow(sub) < 50L) next
    res <- tryCatch(dcs_yin_fit_lavaan(sub, bl, "memory"), error = function(e) NULL)
    if (is.null(res)) next
    tgt <- dcs_yin_extract_targets(res$pe, "memory")
    rows[[length(rows) + 1L]] <- data.frame(
      scenario = nm, dep_to_mem = tgt$dep_to_mem_slope, mem_to_dep = tgt$mem_to_dep_slope,
      method = res$method, stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_DCS_Sensitivity.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$dcs_sensitivity <- list(table = tab)
  cli::cli_alert_success("Yin DCSM 敏感性完成")
  ctx
}

register_block("dcs_sensitivity", block_dcs_sensitivity, "DCSM 敏感性")
