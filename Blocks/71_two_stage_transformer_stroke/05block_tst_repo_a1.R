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

local({
  cands <- c(
    "Blocks/71_two_stage_transformer_stroke/00tst_common.R",
    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""), "Blocks/71_two_stage_transformer_stroke/00tst_common.R"),
    "/mnt/e/01block/01Block-new-Final/Blocks/71_two_stage_transformer_stroke/00tst_common.R"
  )
  hit <- cands[file.exists(cands)][1L]
  if (!length(hit) || is.na(hit)) stop("找不到 00tst_common.R", call. = FALSE)
  source(hit, local = FALSE)
})

block_tst_repo_a1 <- function(ctx, ...) {
  cfg  <- .tst71_tst_cfg(ctx)
  root <- .tst71_root(ctx)
  out  <- ctx$output_dir_tables
  branch <- .tst71_branch_spec(ctx)
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
  .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, seed, timeout_sec = 1200L, branch = branch)

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
  landmark <- as.integer(branch$landmark %||% cfg$active_landmark %||% 72L)[1L]

  ctx$results$tst_repo_a1 <- list(
    arch = "a1",
    python_mode = "tst_train_a1",
    landmark = landmark,
    metrics_path = metrics_path,
    metrics = metrics,
    model_path = if (file.exists(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    hourly_csv = hourly_csv,
    epochs = epochs,
    seed = seed
  )
  cli::cli_alert_success("tst_repo_a1: A1 训练完成 (epochs={epochs}, landmark={landmark}h)")
  ctx
}

register_block(
  "tst_repo_a1", block_tst_repo_a1,
  "两阶段 Transformer 卒中：A1 公开仓库格式适配 + 训练"
)
