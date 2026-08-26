###############################################################################
#  trajectory_prepare_wide_rdata — 为 JLCM/GBMT 块生成宽格式 RData（血小板轨迹）
###############################################################################

block_trajectory_prepare_wide_rdata <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_prepare_wide_rdata: 无数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  data <- literature_ensure_id_column(data, id_col)
  if (!id_col %in% names(data) || all(is.na(data[[id_col]]))) {
    rp <- ctx$config$data$rawdata_path %||% NULL
    rob <- ctx$config$data$rawdata_obj %||% NULL
    if (!is.null(rp) && file.exists(rp) && !is.null(rob)) {
      e <- new.env(parent = emptyenv())
      load(rp, envir = e)
      if (exists(rob, envir = e) && id_col %in% names(get(rob, envir = e))) {
        raw_ids <- get(rob, envir = e)[[id_col]]
        if (length(raw_ids) == nrow(data)) data[[id_col]] <- raw_ids
      }
    }
  }
  prefix <- bl$time_col_prefix %||% "PLT_d"
  time_cols <- grep(paste0("^", prefix), names(data), value = TRUE)
  if (!length(time_cols)) stop("未找到宽格式时序列", call. = FALSE)

  idx <- (bl$index_vars %||% c("Platelet"))[1L]
  keep <- unique(c(id_col, time_cols,
                   ctx$config$survival$time_var %||% "futime",
                   ctx$config$survival$event_var %||% "Mortality_28d",
                   bl$covariate_vars %||% character(0)))
  keep <- intersect(keep, names(data))
  index_df <- data[, keep, drop = FALSE]
  ctx$data$imputed_with_id <- data

  smoke_dir <- file.path(ctx$config$project$root %||% getwd(), "Data/smoke")
  dir.create(smoke_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(smoke_dir, paste0("D02_trajectory_", idx, ".RData"))
  obj_name <- bl$rawdata_obj %||% "index_df"
  assign(obj_name, index_df)
  save(list = obj_name, file = out_path)

  ctx$results$trajectory_wide_rdata <- list(path = out_path, n = nrow(index_df))
  if (is.null(ctx$config$trajectory_jlcm)) ctx$config$trajectory_jlcm <- list()
  ctx$config$trajectory_jlcm$rawdata_path_template <- out_path
  ctx$config$trajectory_jlcm$rawdata_obj <- bl$rawdata_obj %||% "index_df"
  ctx$config$trajectory_jlcm$index_vars <- bl$index_vars %||% c(idx)
  cli::cli_alert_success("宽格式 RData 已写入 {.file {basename(out_path)}}")
  ctx
}

register_block("trajectory_prepare_wide_rdata", block_trajectory_prepare_wide_rdata, "JLCM 宽格式 RData 准备")
