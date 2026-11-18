# dbpool_labels — ICU 死亡 + 动态 RLoS（cap=10；死亡 mask）

block_dbpool_labels <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  delivery <- ctx$results$dbpool_delivery %||% file.path(.dbpool_data_root(ctx), "out", "delivery")
  lab <- file.path(delivery, "08_hourly_labels.parquet")
  if (!file.exists(lab)) stop("缺少 08_hourly_labels.parquet", call. = FALSE)
  # R 侧只登记路径与方法说明；大表由 Python 训练读取
  note <- c(
    "Labels: ICU mortality (pre-discharge) + dynamic RLoS",
    "RLoS capped at 10 days; mortality cases excluded from RLoS evaluation",
    "Training loss: conditional BCE + alpha*MSLE (alpha=20); Evaluation: MAPE for RLoS",
    "Do NOT confuse MAPE (metric) with MSLE (training loss)",
    paste0("source=", lab)
  )
  writeLines(note, file.path(ctx$output_dir_tables, "Methods_labels.txt"))
  data_dir <- ctx$output_dir_data %||% file.path(ctx$output_dir, "Data")
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  # 大文件只记路径，避免整表复制 ~1e8 行
  writeLines(normalizePath(lab, winslash = "/"), file.path(data_dir, "08_hourly_labels.path.txt"))
  ctx$results$dbpool_labels_path <- lab
  ctx
}

register_block(
  "dbpool_labels", block_dbpool_labels,
  "数据库池化：登记 ICU 死亡 + RLoS 标签口径（对齐原文 two-stage）"
)
