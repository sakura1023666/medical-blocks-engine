# dbpool_metrics — 汇总 AUROC/AUPRC/MAPE/Mcomposite（从 unit work 或上游结果表）

block_dbpool_metrics <- function(ctx) {
  work <- ctx$results$dbpool_unit_work %||% (ctx$output_dir_data %||% file.path(ctx$output_dir, "Data"))
  hits <- list.files(work, pattern = "\\.(csv|json|parquet)$", recursive = TRUE, full.names = TRUE)
  man <- data.frame(path = hits, stringsAsFactors = FALSE)
  utils::write.csv(man, file.path(ctx$output_dir_tables, "Table_Metrics_Artifacts.csv"), row.names = FALSE)
  note <- c(
    "Primary metrics (paper): AUROC + AUPRC (mortality), MAPE (RLoS), Mcomposite",
    "AUROC CI: DeLong; MAPE/AUPRC CI: bootstrap 10,000 (paper Methods)",
    "Artifacts listed in Table_Metrics_Artifacts.csv; full tables rebuilt in dbpool_pub_tables"
  )
  writeLines(note, file.path(ctx$output_dir_tables, "Methods_metrics.txt"))
  ctx$results$dbpool_metric_files <- hits
  ctx
}

register_block(
  "dbpool_metrics", block_dbpool_metrics,
  "数据库池化：指标产物清单与方法脚注（AUROC/AUPRC/MAPE/Mcomposite）"
)
