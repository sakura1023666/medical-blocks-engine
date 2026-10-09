###############################################################################
# gallstone_assoc_or_panels — 当前 unit 连续特征 × Model1–3 OR（Fig2 单元）
###############################################################################

block_gallstone_assoc_or_panels <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  expose <- as.character(ctx$config$incidence$index_var %||%
                           ctx$config$gallstone_nomogram$current_feature %||% "")[1L]
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  if (!nzchar(expose) || is.null(data) || !expose %in% names(data)) {
    cli::cli_alert_warning("assoc_or: 跳过，无暴露列 {expose}")
    return(ctx)
  }
  models <- gallstone_nomogram_model_sets(
    ctx$config, data, expose = expose,
    uv = gallstone_nomogram_load_uv(ctx)
  )
  rows <- list()
  for (mn in names(models)) {
    rr <- gallstone_nomogram_fit_or_row(data, expose, outcome, models[[mn]])
    if (!is.null(rr)) {
      rr$model <- mn
      rr$covariates <- paste(models[[mn]], collapse = "+")
      rows[[length(rows) + 1L]] <- rr
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  dirs <- gallstone_nomogram_out_dirs(ctx, expose)
  gallstone_nomogram_ensure_dirs(dirs)
  utils::write.csv(tab, file.path(dirs$tables, "Table_assoc_OR_Model123.csv"), row.names = FALSE)

  # 简单森林式点估计图（单特征三模型）
  if (nrow(tab)) {
    pdf(file.path(dirs$figures, sprintf("Figure 2. Associations %s.pdf", expose)),
        width = 7, height = 4)
    op <- par(mar = c(5, 8, 3, 2))
    ys <- seq_len(nrow(tab))
    plot(tab$OR, ys, pch = 16, xlim = range(c(tab$CI_low, tab$CI_high, 1), finite = TRUE),
         ylim = range(ys) + c(-0.5, 0.5), xlab = "OR (per 1 SD)", ylab = "",
         yaxt = "n", main = sprintf("Associations: %s ~ Success", expose))
    axis(2, at = ys, labels = tab$model, las = 1)
    arrows(tab$CI_low, ys, tab$CI_high, ys, angle = 90, code = 3, length = 0.05)
    abline(v = 1, lty = 2, col = "grey40")
    par(op)
    dev.off()
  }
  ctx$results$gallstone_assoc_or_panels <- tab
  cli::cli_alert_success("Fig2 assoc OR: {expose} rows={nrow(tab)}")
  ctx
}

register_block("gallstone_assoc_or_panels", block_gallstone_assoc_or_panels,
               "胆结石连续特征Model1-3 OR")
