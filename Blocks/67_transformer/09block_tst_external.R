###############################################################################
#  tst_external — 地理外推（默认合成随机数据；R 调 Py）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §0 §9
#    无第二中心真实数据时 config$tst_stroke$external$mode=="synthetic" 强制
#    tst_external_synthetic，结果标 is_synthetic=TRUE，不得写入正式主文结论。
#
#  Produces:
#    Tables/Table_External_Synthetic_Metrics.csv 或 Table_External_Real_Metrics.csv
#    meta.json（is_synthetic）
#    ctx$results$tst_external
###############################################################################

.tst71_pause <- function(ctx, block, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block = block, reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion, call. = FALSE)
}

.tst71_root <- function(ctx) ctx$config$project$root %||% getwd()

.tst71_ensure_py <- function(root) {
  if (!exists("run_literature_python", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
}

.tst71_tst_cfg <- function(ctx) ctx$config$tst_stroke %||% list()

.tst71_epochs <- function(cfg) as.integer(cfg$worker_epochs %||% cfg$epochs %||% 1L)[1L]

.tst71_seed <- function(cfg) {
  ext <- cfg$external %||% list()
  as.integer(ext$seed %||% (cfg$split %||% list())$seed %||% 42L)[1L]
}

.tst71_run_tst_python <- function(root, mode, args, timeout_sec = 1200L) {
  .tst71_ensure_py(root)
  run_literature_python(
    root, mode, args,
    timeout_sec = timeout_sec,
    script = "block_two_stage_transformer.py"
  )
}

.tst71_resolve_model <- function(ctx, arch) {
  for (key in c("tst_train_eval", "tst_repo_a1")) {
    mp <- ctx$results[[key]]$model_path %||% ""
    if (nzchar(mp) && file.exists(mp)) return(mp)
  }
  candidate <- file.path(ctx$output_dir_tables, paste0("model_", arch, ".pth"))
  if (file.exists(candidate)) candidate else ""
}

.tst71_read_json_flag <- function(path, field) {
  if (!file.exists(path)) return(NA)
  txt <- tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (!length(txt)) return(NA)
  obj <- tryCatch(jsonlite::fromJSON(paste(txt, collapse = "\n")), error = function(e) NULL)
  if (is.null(obj) || is.null(obj[[field]])) return(NA)
  obj[[field]]
}

block_tst_external <- function(ctx, ...) {
  cfg  <- .tst71_tst_cfg(ctx)
  root <- .tst71_root(ctx)
  out  <- ctx$output_dir_tables
  ext  <- cfg$external %||% list()
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  ext_mode   <- tolower(as.character(ext$mode %||% "synthetic")[1L])
  force_syn  <- identical(ext_mode, "synthetic")
  py_mode    <- if (force_syn) "tst_external_synthetic" else "tst_external"
  arch       <- as.character(ext$arch %||% ctx$results$tst_train_eval$arch %||% "b")[1L]
  seed       <- .tst71_seed(cfg)
  epochs     <- .tst71_epochs(cfg)
  n_syn      <- as.integer(ext$n %||% 200L)[1L]
  n_features <- as.integer(ext$n_features %||% 16L)[1L]
  model_path <- .tst71_resolve_model(ctx, arch)

  py_args <- c(
    "--out-dir", out, "--arch", arch,
    "--seed", as.character(seed), "--epochs", as.character(epochs),
    "--n", as.character(n_syn), "--n-features", as.character(n_features)
  )
  if (nzchar(model_path)) py_args <- c(py_args, "--model-path", model_path)

  if (!force_syn) {
    data_path <- as.character(ext$data_path %||% "")[1L]
    if (nzchar(data_path) && file.exists(data_path)) {
      py_args <- c(py_args, "--data-path", data_path)
    }
  }

  .tst71_run_tst_python(root, py_mode, py_args, timeout_sec = 1200L)

  metrics_name <- if (force_syn) {
    "Table_External_Synthetic_Metrics.csv"
  } else if (file.exists(file.path(out, "Table_External_Real_Metrics.csv"))) {
    "Table_External_Real_Metrics.csv"
  } else {
    "Table_External_Synthetic_Metrics.csv"
  }
  metrics_path <- file.path(out, metrics_name)
  metrics <- if (file.exists(metrics_path)) {
    utils::read.csv(metrics_path, stringsAsFactors = FALSE)
  } else {
    data.frame()
  }

  meta_path <- file.path(out, "meta.json")
  is_synthetic <- force_syn
  if (file.exists(meta_path)) {
    if (requireNamespace("jsonlite", quietly = TRUE)) {
      flag <- .tst71_read_json_flag(meta_path, "is_synthetic")
      if (!is.na(flag)) is_synthetic <- isTRUE(flag) || identical(as.character(flag), "TRUE")
    } else {
      raw <- paste(readLines(meta_path, warn = FALSE), collapse = "\n")
      if (grepl('"is_synthetic"\\s*:\\s*true', raw, ignore.case = TRUE)) is_synthetic <- TRUE
    }
  }
  if ("is_synthetic" %in% names(metrics) && nrow(metrics) > 0L) {
    is_synthetic <- all(toupper(as.character(metrics$is_synthetic)) == "TRUE")
  }

  stamp_path <- file.path(out, "_tst_external_stamp.csv")
  utils::write.csv(
    data.frame(
      mode = py_mode, ext_config_mode = ext_mode, is_synthetic = is_synthetic,
      arch = arch, metrics_path = metrics_path, model_path = model_path,
      stringsAsFactors = FALSE
    ),
    stamp_path, row.names = FALSE
  )

  ctx$results$tst_external <- list(
    python_mode = py_mode,
    ext_config_mode = ext_mode,
    is_synthetic = is_synthetic,
    arch = arch,
    metrics_path = metrics_path,
    metrics = metrics,
    meta_path = if (file.exists(meta_path)) meta_path else NA_character_,
    stamp_path = stamp_path,
    model_path = if (nzchar(model_path)) model_path else NA_character_,
    seed = seed,
    epochs = epochs,
    n = n_syn
  )
  cli::cli_alert_success(
    "tst_external: {py_mode} 完成 (is_synthetic={is_synthetic})"
  )
  ctx
}

register_block(
  "tst_external", block_tst_external,
  "两阶段 Transformer 卒中：地理外推（默认合成，is_synthetic 标注）"
)
