#!/usr/bin/env Rscript
# =============================================================================
#  MCV 二类全量重跑（公式已修正为 Hematocrit/RBC*10）
#
#  步骤:
#    1) 将 data/mimic/12_MCV.RData 按 ×10 校正到 fL 尺度（与新公式等价）
#    2) 删除旧 by_index/MCV、【success】MCV 与相关检查点
#    3) 强制 ng=2，剔除 PlateletCount 别名列，完整重跑 unit pipeline
#
#  用法（仓库根目录）:
#    SMOKE_NO_FEISHU=1 Rscript run/trajectory_prognosis/run_mcv_2class_full_rerun.R \
#      --config "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/config_trajectory_prognosis_stroke_batch.R"
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(config = NULL, ng = 2L, db = "mimic", skip_delete = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--ng" && i < length(args)) {
      opts$ng <- as.integer(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--db" && i < length(args)) {
      opts$db <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--skip-delete") {
      opts$skip_delete <- TRUE; i <- i + 1L
    } else i <- i + 1L
  }
  opts
}

.drop_platelet_alias <- function(d) {
  if (is.null(d) || !is.data.frame(d)) return(d)
  if ("PlateletCount" %in% names(d) && "Platelet_Count" %in% names(d)) {
    d$PlateletCount <- NULL
  }
  d
}

script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix <- "MCV"
ng <- as.integer(opt$ng)
db <- opt$db

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/trajectory_survival_utils.R"))

config_path <- normalizePath(
  opt$config %||% file.path(
    "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552",
    "config_trajectory_prognosis_stroke_batch.R"
  ),
  winslash = "/", mustWork = TRUE
)
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

batch_root <- (config$trajectory_batch %||% list())$output_base %||% config$project$output_dir
wide_path <- file.path(batch_root, "data", db, "12_MCV.RData")
stopifnot(file.exists(wide_path))

cli::cli_h1("MCV 二类全量重跑（公式 ×10 / 去 PlateletCount）")

# ── 1) 校正 12_MCV.RData 到 fL ──────────────────────────────────────────────
cli::cli_h2("校正宽表尺度 → fL")
e <- new.env(parent = emptyenv())
load(wide_path, envir = e)
obj <- if (exists("index_df", envir = e, inherits = FALSE)) "index_df" else ls(e)[1L]
index_df <- e[[obj]]
day_cols <- grep("^MCV_[0-9]+$", names(index_df), value = TRUE)
med0 <- stats::median(index_df[[day_cols[1L]]], na.rm = TRUE)
if (is.finite(med0) && med0 < 30) {
  for (cc in day_cols) index_df[[cc]] <- as.numeric(index_df[[cc]]) * 10
  assign(obj, index_df, envir = e)
  save(list = obj, file = wide_path, envir = e)
  med1 <- stats::median(index_df[[day_cols[1L]]], na.rm = TRUE)
  cli::cli_alert_success(
    "12_MCV.RData 已 ×10：{day_cols[1L]} 中位数 {round(med0, 2)} → {round(med1, 2)} fL"
  )
} else {
  cli::cli_alert_info(
    "12_MCV.RData 似乎已是 fL 尺度（{day_cols[1L]} 中位数={round(med0, 2)}），跳过 ×10"
  )
}

# ── 2) 删除旧结果 / 检查点 ──────────────────────────────────────────────────
if (!isTRUE(opt$skip_delete)) {
  cli::cli_h2("删除旧 MCV 结果与检查点")
  del_paths <- c(
    file.path(batch_root, "by_index", "MCV"),
    file.path(batch_root, "by_index", "【success】MCV"),
    file.path(batch_root, "by_unit", "【success】MCV"),
    file.path(batch_root, "checkpoints", "by_index", "MCV"),
    file.path(batch_root, "checkpoints", "by_index", "MCV_rerun_ng2"),
    file.path(batch_root, "logs", "MCV.log")
  )
  for (p in del_paths) {
    if (file.exists(p) || dir.exists(p)) {
      unlink(p, recursive = TRUE, force = TRUE)
      cli::cli_alert_info("已删除 {.file {p}}")
    }
  }
}

# ── 3) patch config：强制二类 + 关暂停 ──────────────────────────────────────
config_ix <- trajectory_batch_patch_config_for_index(config, ix)
config_ix$trajectory_jlcm$auto_select_class_ng <- FALSE
config_ix$trajectory_jlcm$assign_class_ng <- ng
config_ix$trajectory_jlcm$prefer_final_ng <- ng
config_ix$trajectory_jlcm$class_range <- seq_len(max(2L, ng))
config_ix$trajectory_jlcm$adaptive_class_cap <- FALSE
config_ix$trajectory_jlcm$pause_enable <- FALSE
config_ix$trajectory_jlcm$pause_on_no_output <- FALSE
config_ix$trajectory_jlcm$stop_on_ng1_fail <- TRUE
config_ix$trajectory_jlcm$stop_on_ng2_fail <- TRUE
config_ix$trajectory_plot_jlcm$class_for_plot <- ng
config_ix$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
config_ix$trajectory_chisq$class_for_test <- ng
config_ix$trajectory_chisq$use_optimal_class_ng <- FALSE
if (is.null(config_ix$trajectory_dynpred$jlcm)) config_ix$trajectory_dynpred$jlcm <- list()
config_ix$trajectory_dynpred$jlcm$prefer_ng <- ng
config_ix$trajectory_dynpred_individual$jlcm_ng <- ng
config_ix$trajectory_weibull_compare$jlcm_ng <- ng

for (blk in c(
  "baseline_binary", "univariate_prognosis", "multicollinearity_screen",
  "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
  "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
  "trajectory_dynpred", "trajectory_dynpred_individual", "trajectory_piecewise_cox",
  "trajectory_weibull_compare", "trajectory_subgroup_class", "trajectory_chisq",
  "trajectory_jlcm"
)) {
  if (is.null(config_ix[[blk]])) next
  config_ix[[blk]]$pause_enable <- FALSE
  config_ix[[blk]]$pause_on_no_output <- FALSE
}
config_ix$baseline_binary$early_stop_if_index_ns <- FALSE
config_ix$univariate_prognosis$fail_on_index_ns <- FALSE
config_ix$multivariate_prognosis$fail_on_index_ns <- FALSE
config_ix$baseline_binary$exclude_vars <- unique(c(
  as.character(config_ix$baseline_binary$exclude_vars %||% character(0)),
  "PlateletCount"
))
config_ix$univariate_prognosis$excluded_predictors <- unique(c(
  as.character(config_ix$univariate_prognosis$excluded_predictors %||% character(0)),
  "PlateletCount"
))
if (!is.null(config_ix$multicollinearity$exclude_vars)) {
  config_ix$multicollinearity$exclude_vars <- unique(c(
    as.character(config_ix$multicollinearity$exclude_vars),
    "PlateletCount"
  ))
}

# ── 4) 完整重跑（共享层 checkpoint + 新 12_MCV）────────────────────────────
cli::cli_h2("启动完整 unit pipeline（含 JLCM 重拟合，ng={ng}）")
tb <- config$trajectory_batch %||% list()
pl <- tb$pipeline_unit %||% pipeline_unit
# 注入：从共享 ctx 加载后丢弃 PlateletCount
# trajectory_batch_run_index_db 内部会 merge 宽表 day1；此处用包装确保别名列被删

# 直接调用底层，并在跑前清理共享 ctx 中的 PlateletCount
shared_ck <- trajectory_batch_shared_ck_dir(config_ix, db)
ctx0 <- study_batch_load_checkpoint_ctx(shared_ck, "trajectory_calc_28d_index")
for (slot in c("cleaned", "mapped", "imputed")) {
  if (!is.null(ctx0$data[[slot]])) ctx0$data[[slot]] <- .drop_platelet_alias(ctx0$data[[slot]])
}
if (!is.null(ctx0$results$data_before_mi)) {
  ctx0$results$data_before_mi <- .drop_platelet_alias(ctx0$results$data_before_mi)
}
# 把清理后的 ctx 写回临时 checkpoint，供 run_index_db 加载
# 更稳妥：在 run_index_db 同路径内联重写关键合并逻辑

db_cfg <- config_ix$dual_db$secondary
cfg_db <- config_ix
cfg_db$project$database   <- db_cfg$name %||% toupper(db)
cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, "by_index", ix, db)
# 注意：trajectory_batch_run_index_db 会把 output 设为 output_dir/db；
# patch 后 project$output_dir 已是 by_index/MCV，再拼 db → by_index/MCV/mimic

# 使用官方 runner（会从共享 ck 加载；我们先把共享 ck 里的 PlateletCount 清掉并另存临时？）
# 为避免污染共享层，不改写共享 rds，而在 runner 之后无法注入。
# 改为：复制一份临时共享 ck，清 PlateletCount 后指向它。

tmp_shared <- file.path(batch_root, "checkpoints", "_shared_mcv_rerun", db)
dir.create(tmp_shared, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(shared_ck, full.names = TRUE)) {
  file.copy(f, file.path(tmp_shared, basename(f)), overwrite = TRUE)
}
# 重写 trajectory_calc_28d_index.rds / 最新 step rds 中的 data
.scrub_ck <- function(path) {
  if (!file.exists(path)) return(invisible(FALSE))
  obj <- readRDS(path)
  if (!is.null(obj$ctx)) {
    for (slot in c("cleaned", "mapped", "imputed")) {
      if (!is.null(obj$ctx$data[[slot]]))
        obj$ctx$data[[slot]] <- .drop_platelet_alias(obj$ctx$data[[slot]])
    }
    if (!is.null(obj$ctx$results$data_before_mi))
      obj$ctx$results$data_before_mi <- .drop_platelet_alias(obj$ctx$results$data_before_mi)
  }
  saveRDS(obj, path)
  invisible(TRUE)
}
for (bn in c(
  "trajectory_calc_28d_index.rds", "step04_trajectory_calc_28d_index.rds",
  "index.rds", "step03_index.rds", "column_mapping.rds", "step02_column_mapping.rds",
  "data_clean.rds", "step01_data_clean.rds"
)) .scrub_ck(file.path(tmp_shared, bn))

config_ix$trajectory_batch$shared_ck_base <- file.path(batch_root, "checkpoints", "_shared_mcv_rerun")
# 确保 output 落在 by_index/MCV
config_ix$project$output_dir <- file.path(batch_root, "by_index", ix)
config_ix$trajectory_batch$index_ck_base <- file.path(batch_root, "checkpoints", "by_index")

dir.create(file.path(config_ix$project$output_dir, db), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(batch_root, "checkpoints", "by_index", ix, db), recursive = TRUE, showWarnings = FALSE)

status_dir <- file.path(config_ix$project$output_dir)
dir.create(status_dir, recursive = TRUE, showWarnings = FALSE)

t0 <- Sys.time()
ctx <- trajectory_batch_run_index_db(
  root, config_ix, ix, db,
  pipeline_unit = pl
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))

if (is.null(ctx)) {
  cli::cli_abort("MCV 重跑失败（trajectory_batch_run_index_db 返回 NULL）")
}

# 写 optimal_ng
out_root <- file.path(config_ix$project$output_dir, db)
sum_dir <- file.path(out_root, "Tables", "Summary")
dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(as.character(ng), file.path(sum_dir, "optimal_ng_MCV.txt"))

# 发表图表整理（与 MCV_3class 白名单顺序一致；缺项跳过）
tryCatch({
  source(file.path(root, "R/trajectory_pub_curate.R"), local = FALSE)
  disease <- (config_ix$feishu %||% list())$disease_label %||%
    config_ix$project$disease %||% "ischemic stroke"
  disease <- gsub("^\\d+_", "", as.character(disease)[1L])
  disease <- gsub("_", " ", disease)
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix,
    dbs = c(db),
    disease = disease
  )
}, error = function(e) {
  cli::cli_alert_warning("发表图表整理失败（不影响成功状态）: {conditionMessage(e)}")
})

# 快速校验
d <- ctx$data$imputed
mcv_med <- if ("MCV" %in% names(d)) stats::median(d$MCV, na.rm = TRUE) else NA_real_
has_plt_alias <- "PlateletCount" %in% names(d)
cli::cli_alert_success(
  "MCV 二类全量重跑完成（{round(elapsed, 1)} min）→ {.file {out_root}}"
)
cli::cli_alert_info(
  "校验: imputed n={nrow(d)}; MCV 中位数={round(mcv_med, 2)}; PlateletCount 仍在数据中={has_plt_alias}"
)

# 状态文件
tryCatch(
  study_batch_write_status(status_dir, list(
    index = ix, unit = ix, status = "success",
    db_done = db, elapsed_sec = round(elapsed * 60, 1),
    note = "full rerun ng=2 after MCV*10 formula fix"
  )),
  error = function(e) NULL
)
