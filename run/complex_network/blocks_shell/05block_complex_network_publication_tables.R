###############################################################################
#  complex_network_publication_tables — Table1 基线 + 量表总分/条目均数（文献 Table 1）
###############################################################################

block_complex_network_publication_tables <- function(ctx, ...) {
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("complex_network_publication_tables: 无数据", call. = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  sym <- grep("^(CESD|GAD)[0-9]+$", names(data), value = TRUE)
  item_rows <- lapply(sym, function(v) {
    x <- as.numeric(data[[v]])
    data.frame(
      item = v,
      mean = mean(x, na.rm = TRUE),
      sd = stats::sd(x, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  item_tab <- do.call(rbind, item_rows)

  base_rows <- list()
  if ("Age" %in% names(data)) {
    base_rows[[length(base_rows) + 1L]] <- data.frame(
      variable = "Age", mean = mean(data$Age, na.rm = TRUE),
      sd = stats::sd(data$Age, na.rm = TRUE), stringsAsFactors = FALSE
    )
  }
  if ("Gender" %in% names(data)) {
    base_rows[[length(base_rows) + 1L]] <- data.frame(
      variable = "Male_n", mean = sum(data$Gender == "Male", na.rm = TRUE),
      sd = NA_real_, stringsAsFactors = FALSE
    )
  }
  for (tot in c("CESD_total", "GAD_total")) {
    if (tot %in% names(data)) {
      base_rows[[length(base_rows) + 1L]] <- data.frame(
        variable = tot, mean = mean(as.numeric(data[[tot]]), na.rm = TRUE),
        sd = stats::sd(as.numeric(data[[tot]]), na.rm = TRUE), stringsAsFactors = FALSE
      )
    }
  }
  base_tab <- if (length(base_rows)) do.call(rbind, base_rows) else data.frame()

  utils::write.csv(item_tab, file.path(out, "Table1_Symptom_Item_Mean_SD.csv"), row.names = FALSE)
  utils::write.csv(base_tab, file.path(out, "Table1_Baseline_Characteristics.csv"), row.names = FALSE)

  ctx$results$complex_network_publication_tables <- list(items = nrow(item_tab))
  cli::cli_alert_success("Table1 基线/量表表已输出")
  ctx
}

register_block("complex_network_publication_tables", block_complex_network_publication_tables,
               "文献 Table1 基线与量表")
