###############################################################################
#  tst_repo_a1 — A1 公开仓库格式适配 + 训练（R 调 Py tst_train_a1）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §3
#    A1 单独命名，不与 A2/B 规范管线混名。
#
#  Consumes:
#    ctx$results$tst_timeseries$hourly_long_path（或 config$tst_stroke$hourly_long_path）
#  Produces:
#    Tables/npz/train|val|test.npz（tst_prepare）
#    Tables/Table_TST_Metrics_a1.csv、model_a1.pth
#    ctx$results$tst_repo_a1
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

block_tst_repo_a1 <- function(ctx, ...) {
  cfg  <- .tst71_tst_cfg(ctx)
  root <- .tst71_root(ctx)
  out  <- ctx$output_dir_tables
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  hourly_csv <- .tst71_hourly_csv(ctx)
  if (is.null(hourly_csv) || !file.exists(hourly_csv)) {
    .tst71_pause(
      ctx, "tst_repo_a1",
      "缺少小时/天长表 CSV（ctx$results$tst_timeseries$hourly_long_path 不存在）",
      "请先运行 tst_timeseries，或在 config$tst_stroke$hourly_long_path 指定 smoke 路径。"
    )
  }

  seed    <- .tst71_seed(cfg)
  epochs  <- .tst71_epochs(cfg)
  patience <- .tst71_patience(cfg)
  npz_dir <- .tst71_npz_dir(ctx)
  .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, seed, timeout_sec = 1200L)

  .tst71_run_tst_python(
    root, "tst_train_a1",
    c(
      "--out-dir", out, "--data-dir", npz_dir,
      "--seed", as.character(seed), "--epochs", as.character(epochs),
      "--patience", as.character(patience)
    ),
    timeout_sec = .tst71_train_timeout(cfg)
  )

  metrics_path <- file.path(out, "Table_TST_Metrics_a1.csv")
  metrics <- if (file.exists(metrics_path)) {
    utils::read.csv(metrics_path, stringsAsFactors = FALSE)
  } else {
    data.frame()
  }
  model_path <- file.path(out, "model_a1.pth")

  ctx$results$tst_repo_a1 <- list(
    arch = "a1",
    python_mode = "tst_train_a1",
    metrics_path = metrics_path,
    metrics = metrics,
    model_path = if (file.exists(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    hourly_csv = hourly_csv,
    epochs = epochs,
    seed = seed
  )
  cli::cli_alert_success("tst_repo_a1: A1 训练完成 (epochs={epochs})")
  ctx
}

register_block(
  "tst_repo_a1", block_tst_repo_a1,
  "两阶段 Transformer 卒中：A1 公开仓库格式适配 + 训练"
)
