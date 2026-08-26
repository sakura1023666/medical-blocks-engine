###############################################################################
#  prepost_data_prep — Chen 2024 入排、composite Z、piecewise 时间变量
###############################################################################

block_prepost_data_prep <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_prepost_chen.R"), local = FALSE)
  data <- ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
  if (is.null(data)) stop("prepost_data_prep: 无数据", call. = FALSE)

  id_col <- bl$id_col %||% "ID"
  wave_col <- bl$wave_col %||% "Wave"
  if ("Age" %in% names(data)) data <- data[as.numeric(data$Age) >= (bl$min_age %||% 45), , drop = FALSE]
  if ("Ever_diabetes_baseline" %in% names(data)) {
    data <- data[data$Ever_diabetes_baseline == 0L, , drop = FALSE]
  }

  data <- prepost_chen_build_composite(data, bl)
  data <- prepost_chen_piecewise_vars(data, bl)
  ctx$data$prepost_long <- data

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "PrePost_long_ready.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, out, row.names = FALSE)
  ctx$results$prepost_data_prep <- list(
    n = nrow(data), n_id = length(unique(data[[id_col]])),
    n_diabetes = sum(data$diabetes_grp == 1L, na.rm = TRUE)
  )
  cli::cli_alert_success("Chen piecewise 数据准备: {nrow(data)} 行")
  ctx
}

register_block("prepost_data_prep", block_prepost_data_prep, "发病前后 Chen 数据准备")
