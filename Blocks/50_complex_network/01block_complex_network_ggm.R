###############################################################################
#  complex_network_ggm — 抑郁/焦虑症状 GGM 网络（Python LASSO-GGM + EI/Bridge EI）
#  文献: Chang 2025 BMC Psychiatry — CLHLS 独居老人 CESD-10 × GAD-7
###############################################################################

block_complex_network_ggm <- function(ctx, ...) {
  bl <- ctx$config$complex_network %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("complex_network_ggm: 无数据", call. = FALSE)

  in_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_network_input.csv")
  dir.create(dirname(in_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, in_path, row.names = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Network")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  sg <- bl$subgroup_col %||% "Gender"
  run_literature_python(root, "psych_network_ggm", c(
    "--out-dir", out, "--data-path", in_path, "--subgroup-col", sg
  ))
  ctx$results$complex_network_ggm <- list(output_dir = out)
  cli::cli_alert_success("GGM 症状网络分析完成")
  ctx
}

register_block("complex_network_ggm", block_complex_network_ggm, "GGM 抑郁焦虑症状网络")
