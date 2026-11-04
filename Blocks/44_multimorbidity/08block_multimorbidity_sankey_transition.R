###############################################################################
#  multimorbidity_sankey_transition — 基线→结局波四分类转移（S 图）
###############################################################################

block_multimorbidity_sankey_transition <- function(ctx, ...) {
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_sankey_transition: 无数据", call. = FALSE)

  cat_col <- as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  wave_col <- as.character(mm$wave_col %||% "Followup_wave")[1L]
  w0 <- mm$baseline_wave %||% min(as.integer(data[[wave_col]]), na.rm = TRUE)
  w1 <- mm$outcome_wave %||% max(as.integer(data[[wave_col]]), na.rm = TRUE)

  if (!all(c(cat_col, id_col, wave_col) %in% names(data))) {
    stop("sankey: 缺 category/id/wave 列", call. = FALSE)
  }
  a <- data[as.integer(data[[wave_col]]) == as.integer(w0), c(id_col, cat_col)]
  b <- data[as.integer(data[[wave_col]]) == as.integer(w1), c(id_col, cat_col)]
  names(a) <- c(id_col, "from")
  names(b) <- c(id_col, "to")
  ab <- merge(a, b, by = id_col)
  ab <- ab[!is.na(ab$from) & !is.na(ab$to), , drop = FALSE]
  flow <- as.data.frame(table(From = ab$from, To = ab$to))
  names(flow)[3] <- "N"
  flow <- flow[flow$N > 0, , drop = FALSE]

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures", "pdf")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(flow, file.path(out_dir, "Table_S_Multimorbidity_Sankey_Flow.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(flow)) {
    p <- ggplot2::ggplot(flow, ggplot2::aes(x = From, y = To, fill = N)) +
      ggplot2::geom_tile(color = "white") +
      ggplot2::geom_text(ggplot2::aes(label = N), size = 3) +
      ggplot2::scale_fill_gradient(low = "#F7FBFF", high = "#2A73BA") +
      ggplot2::theme_bw(base_family = "serif") +
      ggplot2::labs(
        title = "Figure S. Depression-obesity status transition",
        subtitle = paste0("Wave ", w0, " -> ", w1), x = "Baseline", y = "Outcome wave"
      )
    ggplot2::ggsave(file.path(fig, "Figure S. Multimorbidity Sankey heatmap.pdf"), p, width = 7, height = 5.5)
  }

  ctx$results$multimorbidity_sankey <- list(flow = flow, baseline_wave = w0, outcome_wave = w1)
  cli::cli_alert_success("四分类转移矩阵完成（pairs={nrow(ab)}）")
  ctx
}

register_block(
  "multimorbidity_sankey_transition",
  block_multimorbidity_sankey_transition,
  "四分类 Sankey/转移"
)
