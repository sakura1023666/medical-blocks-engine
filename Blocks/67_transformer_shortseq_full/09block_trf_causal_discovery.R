###############################################################################
#  trf_causal_discovery — REACT 因果图约束 + 6 因子筛选
###############################################################################

block_trf_causal_discovery <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  data <- ctx$data$trf_seq %||% ctx$data$cleaned
  in_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_react_causal_input.csv")
  dir.create(dirname(in_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, in_path, row.names = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  run_literature_python(root, "react_causal_discovery", c(
    "--out-dir", out, "--data-path", in_path,
    "--label-col", bl$label_col %||% "label", "--n-factors", "6"
  ), timeout_sec = 1200L)
  fac_path <- file.path(out, "Table_REACT_Causal_Factors.csv")
  factors <- if (file.exists(fac_path)) utils::read.csv(fac_path, stringsAsFactors = FALSE)$feature else character(0)
  ctx$config$transformer_aki$selected_features <- as.character(factors)
  ctx$results$trf_causal_discovery <- list(features = factors)
  cli::cli_alert_success("REACT 因果发现: {length(factors)} 因子")
  ctx
}

register_block("trf_causal_discovery", block_trf_causal_discovery, "REACT 因果发现")
