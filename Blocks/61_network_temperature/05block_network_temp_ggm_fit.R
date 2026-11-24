###############################################################################
#  network_temp_ggm_fit — 各波次 GGM/正则化网络估计（Grimes 2025 分析链）
###############################################################################

block_network_temp_ggm_fit <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  wide_path <- (ctx$results$network_temp_prepare_long %||% list())$wide_path
  if (is.null(wide_path) || !file.exists(wide_path)) {
    sb <- ctx$config$study_batch %||% list()
    candidates <- c(
      file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_network_temp_wide_unit.csv"),
      file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_network_temp_wide.csv"),
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
  if (is.null(wide_path) || !file.exists(wide_path))
    stop("network_temp_ggm_fit: 缺少宽表", call. = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "NetworkGGM")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "psych_network_ggm", c(
    "--out-dir", out, "--data-path", wide_path, "--n-boot", as.character(bl$n_boot %||% 100L)
  ))
  ctx$results$network_temp_ggm_fit <- list(output_dir = out)
  cli::cli_alert_success("GGM 正则化网络估计完成")
  ctx
}

register_block("network_temp_ggm_fit", block_network_temp_ggm_fit, "波次 GGM 网络估计")
