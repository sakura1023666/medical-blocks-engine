###############################################################################
#  network_temp_compute — Python 计算网络温度（各波次/性别）
###############################################################################

block_network_temp_compute <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  wide_path <- (ctx$results$network_temp_prepare_long %||% list())$wide_path
  if (is.null(wide_path) || !file.exists(wide_path)) {
    sb <- ctx$config$study_batch %||% list()
    candidates <- c(
      file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_network_temp_wide.csv"),
      file.path(sb$output_base %||% "", "Tables", "_network_temp_wide.csv"),
      file.path(sb$output_base %||% "", "_shared", "Tables", "_network_temp_wide.csv"),
      file.path(sb$output_base %||% "", "_shared", "step03_network_temp_prepare_long", "Tables", "_network_temp_wide.csv")
    )
    wide_path <- candidates[file.exists(candidates)][1L]
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if ((is.null(wide_path) || !file.exists(wide_path)) && !is.null(data)) {
    sym_cols <- grep("^DEP_", names(data), value = TRUE)
    out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
    dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
    wide_path <- file.path(out_tab, "_network_temp_wide_unit.csv")
    export_cols <- intersect(c(bl$id_col %||% "ID", sym_cols, "Age", "Sex", "Cohort"), names(data))
    utils::write.csv(data[, export_cols, drop = FALSE], wide_path, row.names = FALSE)
  }

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "NetworkTemp")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  sg <- bl$subgroup_col %||% "Sex"
  run_literature_python(root, "network_temperature", c(
    "--out-dir", out, "--data-path", wide_path, "--subgroup-col", sg
  ))
  ctx$results$network_temp_compute <- list(output_dir = out)
  cli::cli_alert_success("网络温度计算完成")
  ctx
}

register_block("network_temp_compute", block_network_temp_compute, "网络温度 Python 计算")
