###############################################################################
#  trajectory_wide_to_long — 宽格式时序列转长格式（肌酐/血小板等）
###############################################################################

block_trajectory_wide_to_long <- function(ctx, ...) {
  suppressPackageStartupMessages(library(tidyr))
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  bl <- ctx$config$trajectory %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_wide_to_long: 无数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  prefix <- bl$time_col_prefix %||% "Cre_d"
  time_cols <- grep(paste0("^", prefix), names(data), value = TRUE)
  if (!length(time_cols) && prefix != "CrePct_") {
    alt <- "CrePct_"
    alt_cols <- grep(paste0("^", alt), names(data), value = TRUE)
    if (length(alt_cols)) {
      prefix <- alt
      time_cols <- alt_cols
      if (is.null(bl$index_vars) || identical(bl$index_vars, "Creatinine"))
        bl$index_vars <- "CreatininePct"
    }
  }
  if (!length(time_cols)) {
    rp <- ctx$config$data$rawdata_path %||% NULL
    rob <- ctx$config$data$rawdata_obj %||% NULL
    if (!is.null(rp) && file.exists(rp) && !is.null(rob)) {
      e <- new.env(parent = emptyenv())
      load(rp, envir = e)
      if (exists(rob, envir = e)) {
        data <- get(rob, envir = e)
        time_cols <- grep(paste0("^", prefix), names(data), value = TRUE)
        cli::cli_alert_info("宽转长从 RData 回退加载: {.file {basename(rp)}}")
      }
    }
  }
  data <- literature_ensure_id_column(data, id_col)
  if (!length(time_cols)) stop("trajectory_wide_to_long: 未找到时序列 ", prefix, call. = FALSE)

  long <- tidyr::pivot_longer(
    data, tidyr::all_of(time_cols),
    names_to = "time_label", values_to = "Value"
  )
  long$Time <- suppressWarnings(as.numeric(sub(prefix, "", long$time_label, fixed = TRUE)))
  long <- long[!is.na(long$Value) & !is.na(long$Time), , drop = FALSE]
  if ("Cohort" %in% names(data) && id_col %in% names(long)) {
    long <- merge(long, unique(data[, c(id_col, "Cohort")]), by = id_col, all.x = TRUE)
  }

  if (is.null(ctx$data$trajectory_long)) ctx$data$trajectory_long <- list()
  idx <- bl$index_vars %||% c("Creatinine")
  key <- paste0(idx[1L], "_long")
  ctx$data$trajectory_long[[key]] <- long

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Trajectory_Long.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(utils::head(long, 5000L), out, row.names = FALSE)
  cli::cli_alert_success("宽转长完成: {nrow(long)} 行")
  ctx
}

register_block("trajectory_wide_to_long", block_trajectory_wide_to_long, "轨迹宽转长")
