###############################################################################
#  tst_train_eval — A2/B/基线/消融 训练评估（R 调 Py）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §3 §7
#
#  Worker 派发: config$tst_stroke$branch_map[[study_batch$active_unit]]$python_mode
#    例: tst_train_b / tst_train_a2 / tst_baselines / tst_ablation
#
#  Consumes:
#    ctx$results$tst_timeseries$hourly_long_path
#  Produces:
#    Tables/Table_TST_Metrics_{arch}.csv 或 Table_TST_Baselines.csv / Table_TST_Ablation.csv
#    ctx$results$tst_train_eval
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

.tst71_epochs <- function(cfg) as.integer(cfg$worker_epochs %||% cfg$epochs %||% 100L)[1L]

.tst71_patience <- function(cfg) as.integer(cfg$early_stop_patience %||% 15L)[1L]

# 100 epoch CPU 两阶段常 >1h；默认 12h，可用 config$tst_stroke$python_train_timeout_sec 覆盖
.tst71_train_timeout <- function(cfg) as.integer(cfg$python_train_timeout_sec %||% 43200L)[1L]

.tst71_seed <- function(cfg) as.integer((cfg$split %||% list())$seed %||% 42L)[1L]

.tst71_hourly_csv <- function(ctx) {
  path <- ctx$results$tst_timeseries$hourly_long_path %||% ""
  if (nzchar(path) && file.exists(path)) return(path)
  override <- (ctx$config$tst_stroke %||% list())$hourly_long_path %||% ""
  if (nzchar(override) && file.exists(override)) return(override)
  smoke <- file.path(
    .tst71_root(ctx),
    "Output/_smoke_task4_shared/step06_tst_timeseries/Tables/_tst_hourly_long.csv"
  )
  if (file.exists(smoke)) return(smoke)
  NULL
}

.tst71_npz_dir <- function(ctx) file.path(ctx$output_dir_tables, "npz")

.tst71_run_tst_python <- function(root, mode, args, timeout_sec = 1200L) {
  .tst71_ensure_py(root)
  run_literature_python(
    root, mode, args,
    timeout_sec = timeout_sec,
    script = "block_two_stage_transformer.py"
  )
}

.tst71_prepare_npz <- function(ctx, root, npz_dir, hourly_csv, seed, timeout_sec = 1200L) {
  dir.create(npz_dir, recursive = TRUE, showWarnings = FALSE)
  train_npz <- file.path(npz_dir, "train.npz")
  if (file.exists(train_npz)) return(invisible(train_npz))
  ts <- .tst71_tst_cfg(ctx)
  n_days <- as.integer(ceiling(max(as.integer(ts$landmarks %||% c(24L, 48L, 72L, 96L, 120L))) / 24))[1L]
  n_hours <- as.integer(ts$n_hours %||% 24L)[1L]
  max_cal <- as.integer(ts$max_calendar_day %||% 30L)[1L]
  args <- c(
    "--out-dir", npz_dir, "--data-path", hourly_csv,
    "--seed", as.character(seed),
    "--n-days", as.character(n_days),
    "--n-hours", as.character(n_hours),
    "--max-calendar-day", as.character(max_cal)
  )
  if (isTRUE(ts$sliding_window %||% TRUE)) args <- c(args, "--sliding-window") else args <- c(args, "--no-sliding-window")
  if (isTRUE(ts$expand_hours %||% TRUE)) args <- c(args, "--expand-hours") else args <- c(args, "--no-expand-hours")
  .tst71_run_tst_python(root, "tst_prepare", args, timeout_sec = timeout_sec)
  invisible(train_npz)
}

.tst71_branch_spec <- function(ctx) {
  cfg  <- .tst71_tst_cfg(ctx)
  unit <- (ctx$config$study_batch %||% list())$active_unit %||% ""
  bm   <- cfg$branch_map %||% list()
  if (nzchar(unit) && unit %in% names(bm)) return(bm[[unit]])
  list(
    python_mode = cfg$python_mode %||% "tst_train_b",
    landmark = cfg$active_landmark %||% 72L,
    model = cfg$baseline_model %||% NULL,
    ablation = cfg$ablation %||% NULL,
    arch = cfg$arch %||% "b"
  )
}

.tst71_metrics_path <- function(out, mode, branch) {
  if (mode == "tst_baselines") {
    return(file.path(out, "Table_TST_Baselines.csv"))
  }
  if (mode == "tst_ablation") {
    return(file.path(out, "Table_TST_Ablation.csv"))
  }
  arch <- switch(
    mode,
    tst_train_a1 = "a1",
    tst_train_a2 = "a2",
    tst_train_b  = "b",
    branch$arch %||% "b"
  )
  file.path(out, paste0("Table_TST_Metrics_", arch, ".csv"))
}

block_tst_train_eval <- function(ctx, ...) {
  cfg    <- .tst71_tst_cfg(ctx)
  root   <- .tst71_root(ctx)
  out    <- ctx$output_dir_tables
  branch <- .tst71_branch_spec(ctx)
  mode   <- as.character(branch$python_mode %||% "tst_train_b")[1L]

  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  hourly_csv <- .tst71_hourly_csv(ctx)
  if (is.null(hourly_csv) || !file.exists(hourly_csv)) {
    .tst71_pause(
      ctx, "tst_train_eval",
      "缺少小时/天长表 CSV（ctx$results$tst_timeseries$hourly_long_path 不存在）",
      "请先运行 tst_timeseries，或在 config$tst_stroke$hourly_long_path 指定 smoke 路径。"
    )
  }

  seed    <- .tst71_seed(cfg)
  epochs  <- .tst71_epochs(cfg)
  patience <- .tst71_patience(cfg)
  npz_dir <- .tst71_npz_dir(ctx)
  .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, seed, timeout_sec = 1200L)

  py_args <- c(
    "--out-dir", out, "--data-dir", npz_dir,
    "--seed", as.character(seed), "--epochs", as.character(epochs),
    "--patience", as.character(patience)
  )

  if (mode == "tst_baselines") {
    model <- as.character(branch$model %||% "logistic")[1L]
    py_args <- c(py_args, "--baseline-models", model)
  } else if (mode == "tst_ablation") {
    arch <- as.character(branch$arch %||% "b")[1L]
    abl  <- as.character(branch$ablation %||% "mask")[1L]
    py_args <- c(py_args, "--arch", arch, "--ablations", abl)
  }

  .tst71_run_tst_python(root, mode, py_args, timeout_sec = .tst71_train_timeout(cfg))

  metrics_path <- .tst71_metrics_path(out, mode, branch)
  metrics <- if (file.exists(metrics_path)) {
    utils::read.csv(metrics_path, stringsAsFactors = FALSE)
  } else {
    data.frame()
  }

  arch <- switch(
    mode,
    tst_train_a1 = "a1",
    tst_train_a2 = "a2",
    tst_train_b  = "b",
    branch$arch %||% "b"
  )
  model_path <- file.path(out, paste0("model_", arch, ".pth"))

  ctx$results$tst_train_eval <- list(
    python_mode = mode,
    active_unit = (ctx$config$study_batch %||% list())$active_unit %||% NA_character_,
    landmark = as.integer(branch$landmark %||% cfg$active_landmark %||% 72L)[1L],
    arch = arch,
    metrics_path = metrics_path,
    metrics = metrics,
    model_path = if (file.exists(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    hourly_csv = hourly_csv,
    epochs = epochs,
    seed = seed,
    branch = branch
  )
  cli::cli_alert_success("tst_train_eval: {mode} 完成 (epochs={epochs}, landmark={branch$landmark %||% cfg$active_landmark %||% 72})")
  ctx
}

register_block(
  "tst_train_eval", block_tst_train_eval,
  "两阶段 Transformer 卒中：A2/B/基线/消融 训练评估"
)
