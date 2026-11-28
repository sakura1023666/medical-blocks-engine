###############################################################################
#  trf_train_eval — Python 短序列 Transformer 训练评估
###############################################################################

block_trf_train_eval <- function(ctx, ...) {
  bl <- ctx$config$transformer_aki %||% list()
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function"))
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  data <- ctx$data$trf_seq %||% ctx$data$cleaned
  in_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_transformer_train_input.csv")
  dir.create(dirname(in_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, in_path, row.names = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Transformer")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  unit <- ctx$config$study_batch$active_unit %||% "Internal"
  variant <- if (unit == "LSTM_baseline") "lstm" else if (unit == "MLP_baseline") "mlp" else "transformer"
  if (!is.null(bl$model_variant) && unit == "Internal") variant <- bl$model_variant
  run_literature_python(root, "react_transformer_train", c(
    "--out-dir", out, "--data-path", in_path,
    "--model", variant, "--n-folds", as.character(bl$n_folds %||% 3L),
    "--seed", as.character(bl$seed %||% 42L),
    "--seq-len", as.character(bl$seq_len %||% 24L),
    "--label-col", bl$label_col %||% "label"
  ), timeout_sec = 2400L)
  metrics_path <- file.path(out, "Table_Transformer_Metrics.csv")
  metrics <- if (file.exists(metrics_path)) utils::read.csv(metrics_path, stringsAsFactors = FALSE) else data.frame()
  ctx$results$trf_train_eval <- list(metrics = metrics, variant = variant)
  cli::cli_alert_success("Transformer 训练评估完成 ({variant})")
  ctx
}

register_block("trf_train_eval", block_trf_train_eval, "Transformer 训练")
