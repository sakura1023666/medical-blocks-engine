###############################################################################
#  baseline_node_means — 网络分析基线描述 + 量表汇总
###############################################################################

block_baseline_node_means <- function(ctx, ...) {
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("baseline_node_means: 无数据", call. = FALSE)
  sym <- grep("^(CESD|GAD)", names(data), value = TRUE)
  if (!length(sym)) sym <- setdiff(names(data), c("ID", "Gender", "Living_alone", "Age"))
  summ <- data.frame(
    variable = sym,
    mean = vapply(sym, function(v) mean(as.numeric(data[[v]]), na.rm = TRUE), numeric(1)),
    sd = vapply(sym, function(v) stats::sd(as.numeric(data[[v]]), na.rm = TRUE), numeric(1)),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Network_Descriptive.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(summ, out, row.names = FALSE)
  ctx$results$baseline_node_means <- summ
  cli::cli_alert_success("网络分析描述统计完成（{nrow(summ)} 节点）")
  ctx
}

register_block("baseline_node_means", block_baseline_node_means, "网络节点描述统计")
