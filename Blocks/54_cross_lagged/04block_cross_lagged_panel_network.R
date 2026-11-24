###############################################################################
#  cross_lagged_panel_network — 交叉滞后面板网络（Python 正则化 logistic 边权）
###############################################################################

block_cross_lagged_panel_network <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_panel_network: 无数据", call. = FALSE)
  in_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_cross_lagged_input.csv")
  dir.create(dirname(in_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, in_path, row.names = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CrossLagged")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "cross_lagged_panel_glmnet", c(
    "--out-dir", out, "--data-path", in_path,
    "--subgroup-col", bl$cohort_col %||% "Cohort",
    "--n-boot", as.character(bl$panel_boot_n %||% 200L)
  ), timeout_sec = 1200L)
  ctx$results$cross_lagged_panel <- list(output_dir = out)
  cli::cli_alert_success("交叉滞后面板网络完成")
  ctx
}

register_block("cross_lagged_panel_network", block_cross_lagged_panel_network, "交叉滞后面板网络")
