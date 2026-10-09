###############################################################################
# gallstone_data_ingest — 读胆结石 xlsx，列对齐，写入 ctx$data
###############################################################################

block_gallstone_data_ingest <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  bl <- ctx$config$gallstone_nomogram %||% list()
  path <- bl$data_xlsx %||% ctx$config$data$rawdata_path
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    stop("gallstone_data_ingest: 找不到数据文件: ", path %||% "<NULL>", call. = FALSE)
  }
  df <- gallstone_nomogram_read_xlsx(path)
  oc <- ctx$config$data$outcome_column %||% "Success"
  if (!oc %in% names(df) && "Success" %in% names(df)) df[[oc]] <- df$Success
  ctx$data$raw <- df
  ctx$data$cleaned <- df
  ctx$data$imputed <- df
  ctx$results$gallstone_data_ingest <- list(n = nrow(df), cols = names(df), path = path)
  cli::cli_alert_success("胆结石数据入库: n={nrow(df)} cols={ncol(df)}")
  ctx
}

register_block("gallstone_data_ingest", block_gallstone_data_ingest, "胆结石xlsx入库对齐")
