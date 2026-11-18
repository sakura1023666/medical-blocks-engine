# dbpool_cohort_ingest — 读取 RealExtraction delivery 队列与 provenance
source_block_helpers <- function() {
  # sourced via pipeline; common loaded by runner
  invisible(TRUE)
}

block_dbpool_cohort_ingest <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  data_root <- .dbpool_data_root(ctx)
  delivery <- file.path(data_root, "out", "delivery")
  if (!dir.exists(delivery)) delivery <- file.path(data_root, "delivery")
  stops <- c(
    "00_README.txt", "01_data_provenance.csv", "02_stays.parquet",
    "03_cohort_flow.csv", "09_experiment_manifest.csv", "09_split_manifest.csv"
  )
  miss <- stops[!file.exists(file.path(delivery, stops))]
  if (length(miss)) stop("delivery 缺失: ", paste(miss, collapse = ", "), call. = FALSE)

  flow <- utils::read.csv(file.path(delivery, "03_cohort_flow.csv"), stringsAsFactors = FALSE)
  manif <- utils::read.csv(file.path(delivery, "09_experiment_manifest.csv"), stringsAsFactors = FALSE)
  utils::write.csv(flow, file.path(ctx$output_dir_tables, "Table_Cohort_Flow.csv"), row.names = FALSE)
  utils::write.csv(manif, file.path(ctx$output_dir_tables, "Table_Experiment_Manifest.csv"), row.names = FALSE)
  file.copy(file.path(delivery, "01_data_provenance.csv"),
            file.path(ctx$output_dir_tables, "Table_Data_Provenance.csv"), overwrite = TRUE)

  ctx$results$dbpool_delivery <- delivery
  ctx$results$dbpool_data_root <- data_root
  ctx$results$dbpool_flow <- flow
  ctx$results$dbpool_manifest <- manif
  cli::cli_alert_success("dbpool_cohort_ingest: delivery={delivery}")
  ctx
}

register_block(
  "dbpool_cohort_ingest", block_dbpool_cohort_ingest,
  "数据库池化：读取 RealExtraction delivery 队列/纳排/实验清单"
)
