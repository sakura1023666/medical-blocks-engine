#!/usr/bin/env Rscript
# =============================================================================
#  MCV 三类结果 — 复用已有 JLCM 模型，不重拟合
#
#  用法:
#    Rscript run/trajectory_prognosis/run_mcv_3class_from_existing.R \
#      --config "/mnt/g/.../config_trajectory_prognosis_stroke_batch.R"
#
#  产出目录（新建）:
#    by_index/MCV_3class/mimic/
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(
    config = NULL,
    src_unit = "MCV",
    out_unit = "MCV_3class",
    ng = 3L,
    db = "mimic"
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--src-unit" && i < length(args)) {
      opts$src_unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--out-unit" && i < length(args)) {
      opts$out_unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--ng" && i < length(args)) {
      opts$ng <- as.integer(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--db" && i < length(args)) {
      opts$db <- trimws(args[[i + 1L]]); i <- i + 2L
    } else {
      i <- i + 1L
    }
  }
  opts
}

.unwrap_jlcm <- function(m) {
  if (inherits(m, "Jointlcmm")) return(m)
  if (is.list(m) && inherits(m$best, "Jointlcmm")) return(m$best)
  m
}

.write_class_from_ng <- function(ctx, Index, ng, id_col = "subject_id") {
  pack <- ctx$results$trajectory_jlcm_models[[Index]]
  if (is.null(pack) || is.null(pack$models)) stop("无 JLCM 模型缓存: ", Index, call. = FALSE)
  m_raw <- pack$models[[paste0("m", ng)]]
  if (is.null(m_raw)) stop("缺少 m", ng, " 模型", call. = FALSE)
  m <- .unwrap_jlcm(m_raw)
  if (is.null(m$pprob)) stop("m", ng, " 无 pprob", call. = FALSE)

  pprob_df <- as.data.frame(m$pprob)
  class_assign <- pprob_df[, c("subject_id_num", "class")]
  model_data_final <- pack$model_data_final
  subj_class <- unique(model_data_final[, c(id_col, "subject_id_num")])
  subj_class <- dplyr::left_join(subj_class, class_assign, by = "subject_id_num")
  subj_class <- subj_class[, c(id_col, "class")]
  names(subj_class)[2] <- "trajectory_class"
  subj_class$trajectory_class <- as.integer(subj_class$trajectory_class)
  idx_col <- paste0("trajectory_class_", Index)
  subj_class[[idx_col]] <- subj_class$trajectory_class

  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]]) || !id_col %in% names(ctx$data[[slot]])) next
    tgt <- ctx$data[[slot]]
    tgt[[id_col]] <- as.character(tgt[[id_col]])
    tgt$trajectory_class <- NULL
    tgt[[idx_col]] <- NULL
    tgt <- dplyr::left_join(
      tgt,
      dplyr::mutate(subj_class, !!id_col := as.character(.data[[id_col]])),
      by = id_col
    )
    ctx$data[[slot]] <- tgt
  }

  # 确保 D={ng} 长数据可用（下游 plot/dynpred 有时按 D 读取）
  key <- paste0(Index, "_D", ng)
  if (is.null(ctx$data$trajectory_long[[key]]) && !is.null(model_data_final)) {
    long_with_class <- model_data_final |>
      dplyr::left_join(class_assign, by = "subject_id_num") |>
      dplyr::mutate(Class = paste0("Class", class)) |>
      dplyr::rename(Time = time_day, Value = scr_std)
    ctx$data$trajectory_long[[key]] <- long_with_class
  }

  ctx$results[[paste0("trajectory_optimal_ng_", Index)]] <- as.integer(ng)
  ctx$results$trajectory_optimal_ng <- as.integer(ng)
  cli::cli_alert_success("{Index}: 强制使用 ng={ng}，类别已回写")
  ctx
}

.clear_old_pub_outputs <- function(out_root) {
  fig_dir <- file.path(out_root, "Figures")
  tab_dir <- file.path(out_root, "Tables")
  if (dir.exists(fig_dir)) {
    unlink(list.files(fig_dir, full.names = TRUE, recursive = TRUE), recursive = TRUE, force = TRUE)
  }
  if (dir.exists(tab_dir)) {
    # 保留 Summary（FinalCovariates / optimal_ng 等）
    keep_summary <- file.path(tab_dir, "Summary")
    tmp_summary <- tempfile("summary_")
    if (dir.exists(keep_summary)) {
      dir.create(tmp_summary, recursive = TRUE)
      file.copy(list.files(keep_summary, full.names = TRUE), tmp_summary, recursive = TRUE)
    }
    unlink(list.files(tab_dir, full.names = TRUE), recursive = TRUE, force = TRUE)
    dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
    if (dir.exists(tmp_summary)) {
      dir.create(keep_summary, recursive = TRUE, showWarnings = FALSE)
      file.copy(list.files(tmp_summary, full.names = TRUE), keep_summary, recursive = TRUE)
      unlink(tmp_summary, recursive = TRUE, force = TRUE)
    }
  }
  invisible(TRUE)
}

# ── main ──────────────────────────────────────────────────────────────────────
script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix_src <- opt$src_unit
ix_out <- opt$out_unit
ng <- as.integer(opt$ng)
db <- opt$db

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/trajectory_paper_tables.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))
source(file.path(root, "R/trajectory_survival_utils.R"))

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else {
  stop("--config 必填", call. = FALSE)
}
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1, pipeline.database_name = "MIMIC")

# patch：按源指标加载配置字段，但输出重定向到 out_unit
config_ix <- trajectory_batch_patch_config_for_index(config, ix_src)
config_ix$project$output_dir <- file.path(
  (config_ix$trajectory_batch %||% list())$output_base %||% config_ix$project$output_dir,
  "by_index", ix_out
)
# 下游块强制 ng=3 / 不做 auto（已手动指定）
config_ix$trajectory_jlcm$auto_select_class_ng <- FALSE
config_ix$trajectory_jlcm$assign_class_ng <- ng
config_ix$trajectory_jlcm$prefer_final_ng <- ng
config_ix$trajectory_plot_jlcm$class_for_plot <- ng
config_ix$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
config_ix$trajectory_chisq$class_for_test <- ng
config_ix$trajectory_chisq$use_optimal_class_ng <- FALSE
if (is.null(config_ix$trajectory_dynpred$jlcm)) config_ix$trajectory_dynpred$jlcm <- list()
config_ix$trajectory_dynpred$jlcm$prefer_ng <- ng
config_ix$trajectory_dynpred_individual$jlcm_ng <- ng
config_ix$trajectory_weibull_compare$jlcm_ng <- ng
config_ix$trajectory_km_class$index_vars <- c(ix_src)
config_ix$trajectory_baseline_by_class$index_vars <- c(ix_src)
config_ix$trajectory_piecewise_cox$index_vars <- c(ix_src)
config_ix$trajectory_subgroup_class$index_vars <- c(ix_src)
config_ix$trajectory_dynpred$index_vars <- c(ix_src)
config_ix$trajectory_dynpred_individual$index_vars <- c(ix_src)
config_ix$trajectory_weibull_compare$index_vars <- c(ix_src)
config_ix$trajectory_plot_jlcm$index_vars <- c(ix_src)
config_ix$trajectory_chisq$index_vars <- c(ix_src)
# 关闭可能打断续跑的 pause
for (blk in c(
  "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
  "trajectory_dynpred", "trajectory_dynpred_individual", "trajectory_piecewise_cox",
  "trajectory_weibull_compare", "trajectory_subgroup_class", "trajectory_chisq"
)) {
  if (!is.null(config_ix[[blk]])) {
    config_ix[[blk]]$pause_enable <- FALSE
    config_ix[[blk]]$pause_on_no_output <- FALSE
  }
}

# 源检查点（含 m1..m6） + 目标输出/检查点
src_ck <- trajectory_batch_index_ck_dir(trajectory_batch_patch_config_for_index(config, ix_src), ix_src, db)
out_root <- file.path(config_ix$project$output_dir, db)
out_ck <- file.path(
  (config_ix$trajectory_batch %||% list())$index_ck_base %||%
    file.path((config_ix$trajectory_batch %||% list())$output_base, "checkpoints", "by_index"),
  ix_out, db
)
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ck, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_root, "Tables", "Summary"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_root, "Figures"), recursive = TRUE, showWarnings = FALSE)

cli::cli_h1("MCV 三类续跑（复用已有模型）")
cli::cli_alert_info("源检查点: {.file {src_ck}}")
cli::cli_alert_info("输出目录: {.file {out_root}}")
cli::cli_alert_info("目标检查点: {.file {out_ck}}")

ctx <- study_batch_load_checkpoint_ctx(src_ck, "trajectory_jlcm")
cfg_db <- config_ix
cfg_db$project$database <- "MIMIC"
cfg_db$project$output_dir <- out_root
ctx$config <- cfg_db
ctx$root_output_dir <- out_root
ctx$output_dir <- out_root
ctx$output_dir_tables <- file.path(out_root, "Tables")
ctx$output_dir_figures <- file.path(out_root, "Figures")

# 清空旧两类发表产物（保留 Summary）
.clear_old_pub_outputs(out_root)

# 强制 ng=3 类别回写
id_col <- cfg_db$data$id_column %||% "subject_id"
ctx <- .write_class_from_ng(ctx, ix_src, ng, id_col = id_col)
writeLines(as.character(ng), file.path(out_root, "Tables", "Summary", paste0("optimal_ng_", ix_src, ".txt")))

# Table 2 + 后验分类（基于已有 models）
pack <- ctx$results$trajectory_jlcm_models[[ix_src]]
if (!is.null(pack) && !is.null(pack$models)) {
  options(pipeline.database_name = "MIMIC")
  fp_t2 <- file.path(ctx$output_dir_tables, "Table 2-MIMIC. Metrics for determining the optimal number of classes.xlsx")
  t2_title <- paste0("Table 2. Metrics for determining the optimal number of classes (", ix_src, ")")
  ok <- tryCatch({
    trajectory_export_table2_sci(ctx, pack$models, fp_t2, t2_title)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("Table2 SCI 导出失败，改用 xlsx 直写: {e$message}")
    FALSE
  })
  if (!ok) trajectory_export_table2_xlsx(pack$models, fp_t2, index_name = ix_src)
  utils::write.csv(
    trajectory_build_table2_from_models(pack$models),
    file.path(ctx$output_dir_tables, paste0("Table2_", ix_src, "_model_comparison_ALL.csv")),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  m_sel <- pack$models[[paste0("m", ng)]]
  fp_s8 <- file.path(ctx$output_dir_tables, "Table S8-MIMIC. Posterior classification table.xlsx")
  tryCatch(
    trajectory_export_posterior_classification_sci(
      ctx, m_sel, fp_s8,
      paste0("Table S8. Posterior classification table (", ix_src, ", MIMIC)")
    ),
    error = function(e) cli::cli_alert_warning("后验表导出失败: {e$message}")
  )
  cli::cli_alert_success("Table 2 / 后验表已写入")
}

downstream <- c(
  "trajectory_baseline_by_class",
  "trajectory_plot_jlcm",
  "trajectory_km_class",
  "trajectory_dynpred",
  "trajectory_dynpred_individual",
  "trajectory_piecewise_cox",
  "trajectory_weibull_compare",
  "trajectory_subgroup_class",
  "trajectory_chisq"
)

pl <- list(
  name = "trajectory_prognosis_mcv_3class",
  blocks = downstream,
  checkpoint = list(enable = TRUE, dir = out_ck)
)

cli::cli_h2("重跑下游（强制 ng={ng}）")
ctx <- run_pipeline(
  root,
  config = cfg_db,
  pipeline = pl,
  run_opts = list(initial_ctx = ctx, only = downstream)
)

# 发表图表整理
tryCatch({
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix_src,
    dbs = c(db),
    disease = "ischemic stroke"
  )
}, error = function(e) cli::cli_alert_warning("curate 失败: {e$message}"))

cli::cli_alert_success("MCV 三类结果完成 → {.file {out_root}}")
