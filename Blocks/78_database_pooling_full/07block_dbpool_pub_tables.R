# dbpool_pub_tables — Table 1–4、S1、S2 与 Figure 1–2
# 出表出图只走 scripts/build_publication.py，不要再写清单 csv 或另一套图。

block_dbpool_pub_tables <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  cfg <- .dbpool_cfg(ctx)
  pub_root <- ctx$results$dbpool_pub_root %||% file.path(ctx$root_output_dir %||% "Output", "summary_results")
  dir.create(pub_root, recursive = TRUE, showWarnings = FALSE)

  # tail 的 root_output_dir 是 summary_results，各单元在其上一级的 by_unit
  work <- as.character(cfg$results_work_root %||% "")[1L]
  if (!nzchar(work)) {
    work <- file.path(dirname(normalizePath(pub_root, winslash = "/", mustWork = FALSE)), "by_unit")
  }
  blended <- ctx$results$dbpool_blended_out %||% .dbpool_blended_out(ctx)
  script <- file.path(.dbpool_scripts_dir(ctx), "build_publication.py")
  .dbpool_run_py(
    ctx,
    script,
    args = c(
      "--work-root", work,
      "--blended-out", blended,
      "--out", pub_root
    ),
    timeout_sec = as.integer(cfg$table_timeout_sec %||% 7200L)
  )

  ctx$results$dbpool_pub_root <- pub_root
  cli::cli_alert_success("dbpool_pub_tables: {pub_root}")
  ctx
}

register_block(
  "dbpool_pub_tables", block_dbpool_pub_tables,
  "数据库池化：从各单元测试指标写出 Table 1–4、S1、S2 和 Figure 1–2"
)
