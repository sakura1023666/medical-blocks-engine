###############################################################################
#  tst_train_eval — A2/B/基线/消融 训练评估（R 调 Py）
###############################################################################

local({
  common <- file.path("Blocks/71_two_stage_transformer_stroke/00tst_common.R")
  root_guess <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  cands <- c(
    common,
    file.path(root_guess, common),
    "/mnt/e/01block/01Block-new-Final/Blocks/71_two_stage_transformer_stroke/00tst_common.R"
  )
  hit <- cands[file.exists(cands)][1L]
  if (!length(hit) || is.na(hit)) stop("找不到 00tst_common.R", call. = FALSE)
  source(hit, local = FALSE)
})

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
  # 训练种子可与划分种子分离；划分始终用 split$seed。禁止写入图注/表注。
  train_seed <- as.integer(cfg$train_seed %||% seed)[1L]
  if (is.na(train_seed) || train_seed < 1L) train_seed <- seed
  mode    <- as.character(branch$python_mode %||% "tst_train_b")[1L]
  epochs  <- if (identical(mode, "tst_baselines")) .tst71_baseline_epochs(cfg) else .tst71_epochs(cfg)
  patience <- .tst71_patience(cfg)
  npz_dir <- .tst71_npz_dir(ctx)
  .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, seed, timeout_sec = 1200L, branch = branch)

  py_args <- c(
    "--out-dir", out, "--data-dir", npz_dir,
    "--seed", as.character(train_seed), "--epochs", as.character(epochs),
    "--patience", as.character(patience)
  )
  # 可选训练超参（冲 Day5 AUC；缺省走 Python 默认）
  .add_opt <- function(flag, val) {
    if (is.null(val) || length(val) < 1L || is.na(val[[1L]])) return(invisible(NULL))
    py_args <<- c(py_args, flag, as.character(val[[1L]]))
  }
  .add_opt("--batch-size", cfg$batch_size)
  .add_opt("--lr", cfg$lr)
  .add_opt("--d-model", cfg$d_model)
  .add_opt("--heads", cfg$heads)
  .add_opt("--n-layers", cfg$n_layers)
  .add_opt("--dropout", cfg$dropout)
  .add_opt("--day5-loss-weight", cfg$day5_loss_weight)
  .add_opt("--input-noise", cfg$input_noise)
  .add_opt("--tab-dim", cfg$tab_dim)
  .add_opt("--focal-alpha", cfg$focal_alpha)
  .add_opt("--focal-gamma", cfg$focal_gamma)

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
  landmark <- as.integer(branch$landmark %||% cfg$active_landmark %||% 72L)[1L]

  # stamp landmark into train_meta if present
  meta_path <- file.path(out, paste0("train_meta_", arch, ".json"))
  if (file.exists(meta_path)) {
    tryCatch({
      meta <- jsonlite::fromJSON(meta_path)
      meta$landmark_hours <- landmark
      meta$n_days_landmark <- .tst71_landmark_n_days(landmark)
      jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
    }, error = function(e) invisible(NULL))
  }

  ctx$results$tst_train_eval <- list(
    python_mode = mode,
    active_unit = (ctx$config$study_batch %||% list())$active_unit %||% NA_character_,
    landmark = landmark,
    arch = arch,
    metrics_path = metrics_path,
    metrics = metrics,
    model_path = if (file.exists(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    hourly_csv = hourly_csv,
    epochs = epochs,
    seed = seed,
    train_seed = train_seed,
    branch = branch
  )
  nd <- .tst71_landmark_n_days(landmark)
  cli::cli_alert_success("tst_train_eval: {mode} 完成 (epochs={epochs}, landmark={landmark}h, n_days={nd})")
  ctx
}

register_block(
  "tst_train_eval", block_tst_train_eval,
  "两阶段 Transformer 卒中：A2/B/基线/消融 训练评估"
)
