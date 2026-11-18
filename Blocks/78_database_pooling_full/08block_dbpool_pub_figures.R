# dbpool_pub_figures — 四目录补齐
# Figure 1–2 已由 dbpool_pub_tables 调用 build_publication.py 写出。
# 这里只补 png / tiff / image_information，不再另画一排方框。

block_dbpool_pub_figures <- function(ctx) {
  if (!exists(".dbpool_scripts_dir", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  pub_root <- ctx$results$dbpool_pub_root %||% file.path(ctx$root_output_dir %||% "Output", "summary_results")
  fig_dir <- file.path(pub_root, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  if (exists("pub_figure_ensure_formats", mode = "function")) {
    try(pub_figure_ensure_formats(fig_dir, config = ctx$config), silent = TRUE)
  } else {
    for (d in c("pdf", "png", "tiff", "image_information")) {
      dir.create(file.path(fig_dir, d), recursive = TRUE, showWarnings = FALSE)
    }
  }

  ctx$results$dbpool_figures <- fig_dir
  cli::cli_alert_success("dbpool_pub_figures: {fig_dir}")
  ctx
}

register_block(
  "dbpool_pub_figures", block_dbpool_pub_figures,
  "数据库池化：发表图四目录补齐（图由 build_publication.py 写出）"
)
