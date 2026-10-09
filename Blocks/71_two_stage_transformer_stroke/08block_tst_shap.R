###############################################################################
#  tst_shap — 分日 SHAP 热图（R 调 Py tst_shap）
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

.tst71_npz_dir <- function(ctx) {
  prior <- ctx$results$tst_train_eval$npz_dir %||% ctx$results$tst_repo_a1$npz_dir %||% ""
  if (nzchar(prior) && dir.exists(prior)) return(prior)
  file.path(ctx$output_dir_tables, "npz")
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
  branch <- .tst71_branch_spec(ctx)
  arch <- as.character(cfg$shap_arch %||% ctx$results$tst_train_eval$arch %||% branch$arch %||% "b")[1L]
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(ctx$output_dir_figures %||% file.path(dirname(out), "Figures"), recursive = TRUE, showWarnings = FALSE)

  npz_dir <- .tst71_npz_dir(ctx)
  if (!file.exists(file.path(npz_dir, "test.npz"))) {
    hourly_csv <- .tst71_hourly_csv(ctx)
    if (is.null(hourly_csv) || !file.exists(hourly_csv)) {
      .tst71_pause(
        ctx, "tst_shap",
        "缺少 npz 数据且无法 prepare（无长表 CSV）",
        "请先运行 tst_timeseries + tst_train_eval。"
      )
    }
    .tst71_prepare_npz(ctx, root, npz_dir, hourly_csv, .tst71_seed(cfg), timeout_sec = 1200L, branch = branch)
  }

  model_path <- .tst71_resolve_model(ctx, arch)
  py_args <- c(
    "--out-dir", out, "--data-dir", npz_dir,
    "--arch", arch, "--split", cfg$shap_split %||% "test",
    "--seed", as.character(.tst71_seed(cfg))
  )
  if (nzchar(model_path)) py_args <- c(py_args, "--model-path", model_path)

  .tst71_run_tst_python(root, "tst_shap", py_args, timeout_sec = 3600L)

  shap_path <- file.path(out, "Table_TST_SHAP_Importance.csv")
  shap_df <- if (file.exists(shap_path)) utils::read.csv(shap_path, stringsAsFactors = FALSE) else data.frame()

  ctx$results$tst_shap <- list(
    arch = arch,
    model_path = if (nzchar(model_path)) model_path else NA_character_,
    npz_dir = npz_dir,
    shap_path = shap_path,
    shap = shap_df,
    landmark = as.integer(branch$landmark %||% NA_integer_)[1L]
  )
  cli::cli_alert_success("tst_shap: SHAP 完成 (arch={arch})")
  ctx
}

register_block(
  "tst_shap", block_tst_shap,
  "两阶段 Transformer 卒中：分日 SHAP 热图"
)
