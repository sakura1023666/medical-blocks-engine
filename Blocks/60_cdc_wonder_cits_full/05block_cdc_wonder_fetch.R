###############################################################################
#  cdc_wonder_fetch — CDC WONDER Natality 下载/缓存
###############################################################################

block_cdc_wonder_fetch <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/cdc_wonder_cits_utils.R"), local = FALSE)

  cache <- bl$monthly_cache %||% "Data/smoke/D01_cdc_wonder_monthly_rates.csv"
  raw_path <- bl$rawdata_path %||% ctx$config$data$rawdata_path
  if (file.exists(cache)) {
    monthly_src <- utils::read.csv(cache, stringsAsFactors = FALSE)
  } else if (!is.null(raw_path) && file.exists(file.path(root, raw_path))) {
    load(file.path(root, raw_path), envir = e <- new.env())
    obj <- bl$rawdata_obj %||% ctx$config$data$rawdata_obj
    monthly_src <- get(obj, envir = e)
  } else {
    monthly_src <- .cits_fetch_natality_monthly(cache_path = file.path(root, cache))
  }

  ctx$data$wonder_raw <- monthly_src
  ctx$results$cdc_wonder_fetch <- list(n = nrow(monthly_src), cache = cache)
  cli::cli_alert_success("CDC WONDER 数据加载 ({nrow(monthly_src)} 行)")
  ctx
}

register_block("cdc_wonder_fetch", block_cdc_wonder_fetch, "CDC WONDER 数据获取")
