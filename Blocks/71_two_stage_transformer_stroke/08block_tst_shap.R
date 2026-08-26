###############################################################################
#  tst_shap — 分日 SHAP 热图（R 调 Py tst_shap）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §7
#
#  Consumes:
#    ctx$results$tst_train_eval / tst_repo_a1 的 model_path；npz test 集
#  Produces:
#    Tables/Table_TST_SHAP_Importance.csv + Figures/*SHAP*.png
#    ctx$results$tst_shap
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

.tst71_npz_dir <- function(ctx) {
  prior <- ctx$results$tst_train_eval$npz_dir %||% ctx$results$tst_repo_a1$npz_dir %||% ""
  if (nzchar(prior) && dir.exists(prior)) return(prior)
  file.path(ctx$output_dir_tables, "npz")
}

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

.tst71_resolve_model <- function(ctx, arch) {
  for (key in c("tst_train_eval", "tst_repo_a1")) {
    mp <- ctx$results[[key]]$model_path %||% ""
    if (nzchar(mp) && file.exists(mp)) return(mp)
  }
  candidate <- file.path(ctx$output_dir_tables, paste0("model_", arch, ".pth"))
  if (file.exists(candidate)) candidate else ""
}

block_tst_shap <- function(ctx, ...) {
  cfg  <- .tst71_tst_cfg(ctx)
  root <- .tst71_root(ctx)
  out  <- ctx$output_dir_tables
  fig  <- ctx$output_dir_figures %||% file.path(dirname(out), "Figures")
  arch <- as.character(cfg$shap_arch %||% ctx$results$tst_train_eval$arch %||% "b")[1L]
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)

  npz_dir <- .tst71_npz_dir(ctx)
  if (!file.exists(file.path(npz_dir, "test.npz"))) {
    hourly_csv <- .tst71_hourly_csv(ctx)
    if (is.null(hourly_csv) || !file.exists(hourly_csv)) {
      .tst71_pause(
        ctx, "tst_shap",
        "缺少 npz 数据且无法 prepare（无长表 CSV）",
        "请先运行 tst_timeseries + tst_train_eval，或设置 hourly_long_path。"
      )
    }
    .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, .tst71_seed(cfg), timeout_sec = 1200L)
  }

  model_path <- .tst71_resolve_model(ctx, arch)
  py_args <- c(
    "--out-dir", out, "--data-dir", npz_dir,
    "--arch", arch, "--split", cfg$shap_split %||% "test",
    "--seed", as.character(.tst71_seed(cfg))
  )
  if (nzchar(model_path)) py_args <- c(py_args, "--model-path", model_path)

  .tst71_run_tst_python(root, "tst_shap", py_args, timeout_sec = 1800L)

  shap_path <- file.path(out, "Table_TST_SHAP_Importance.csv")
  shap_tbl  <- if (file.exists(shap_path)) utils::read.csv(shap_path, stringsAsFactors = FALSE) else data.frame()
  fig_files <- list.files(fig, pattern = "SHAP|shap", full.names = TRUE)

  ctx$results$tst_shap <- list(
    arch = arch,
    model_path = if (nzchar(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    shap_path = shap_path,
    shap = shap_tbl,
    figure_paths = fig_files
  )
  cli::cli_alert_success("tst_shap: SHAP 完成 (arch={arch}, rows={nrow(shap_tbl)})")
  ctx
}

register_block(
  "tst_shap", block_tst_shap,
  "两阶段 Transformer 卒中：分日 SHAP 热图"
)
