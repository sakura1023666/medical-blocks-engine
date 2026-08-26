#!/usr/bin/env Rscript
# =============================================================================
#  MCV 二类结果 — 复用已有 JLCM(m2)，不重拟合；重跑其余发表表/图
#
#  约束与 3class 修复对齐：
#    - N 对齐 JLCM 队列（3119）
#    - 暴露 MCV 连续变量且放末行
#    - Acc/Sens/Spec 竖向散点图
#    - FinalCovariates = JLCM survival 协变量
#
#  用法:
#    SMOKE_NO_FEISHU=1 Rscript run/trajectory_prognosis/run_mcv_2class_from_existing.R \
#      --config ".../config_trajectory_prognosis_stroke_batch.R"
#
#  产出: by_index/MCV/mimic/
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(config = NULL, src_unit = "MCV", out_unit = "MCV", ng = 2L, db = "mimic")
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
    } else i <- i + 1L
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
  if (is.null(m_raw)) stop("缺少 m", ng, call. = FALSE)
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

.write_jlcm_final_covariates <- function(out_root, Index, cov) {
  cov <- as.character(cov %||% character(0))
  if (!length(cov)) return(invisible(FALSE))
  sum_dir <- file.path(out_root, "Tables", "Summary")
  dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c(
      paste0("# Final covariates (JLCM survival submodel) — ", Index, " / MIMIC"),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      cov
    ),
    file.path(sum_dir, paste0("FinalCovariates_", Index, "_mimic.txt"))
  )
  invisible(TRUE)
}

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
source(file.path(root, "Blocks/03_imputation/01block_imputation.R"))

config_path <- normalizePath(opt$config, winslash = "/", mustWork = TRUE)
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1, pipeline.database_name = "MIMIC")

config_ix <- trajectory_batch_patch_config_for_index(config, ix_src)
config_ix$project$output_dir <- file.path(
  (config_ix$trajectory_batch %||% list())$output_base %||% config_ix$project$output_dir,
  "by_index", ix_out
)
config_ix$prediction$index_vars <- c(ix_src)
config_ix$survival$index_var <- ix_src
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
config_ix$trajectory_weibull_compare$replay_from_results <- TRUE
config_ix$trajectory_baseline_by_class$vars_from <- "table1"

for (blk in c(
  "baseline_binary", "univariate_prognosis", "multicollinearity_screen",
  "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final",
  "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
  "trajectory_dynpred", "trajectory_dynpred_individual", "trajectory_piecewise_cox",
  "trajectory_weibull_compare", "trajectory_subgroup_class", "trajectory_chisq"
)) {
  if (is.null(config_ix[[blk]])) next
  config_ix[[blk]]$pause_enable <- FALSE
  config_ix[[blk]]$pause_on_no_output <- FALSE
  if (!is.null(config_ix[[blk]]$index_vars)) config_ix[[blk]]$index_vars <- c(ix_src)
}
config_ix$multivariate_prognosis$fail_on_index_ns <- FALSE

src_ck <- trajectory_batch_index_ck_dir(
  trajectory_batch_patch_config_for_index(config, ix_src), ix_src, db
)
out_root <- file.path(config_ix$project$output_dir, db)
# 下游检查点写到独立目录，避免覆盖源 JLCM
out_ck <- file.path(
  (config_ix$trajectory_batch %||% list())$index_ck_base %||%
    file.path((config_ix$trajectory_batch %||% list())$output_base, "checkpoints", "by_index"),
  paste0(ix_out, "_rerun_ng", ng), db
)
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ck, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_root, "Tables", "Summary"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_root, "Figures"), recursive = TRUE, showWarnings = FALSE)

cli::cli_h1("MCV 二类续跑（复用已有 JLCM，ng={ng}）")
cli::cli_alert_info("源检查点: {.file {src_ck}}")
cli::cli_alert_info("输出目录: {.file {out_root}}")
cli::cli_alert_info("续跑检查点: {.file {out_ck}}")

ctx <- study_batch_load_checkpoint_ctx(src_ck, "trajectory_jlcm")
# 复用已有 weibull（若有）
if (file.exists(file.path(src_ck, "trajectory_weibull_compare.rds"))) {
  ctx_w <- tryCatch(study_batch_load_checkpoint_ctx(src_ck, "trajectory_weibull_compare"), error = function(e) NULL)
  if (!is.null(ctx_w$results$trajectory_weibull_compare)) {
    ctx$results$trajectory_weibull_compare <- ctx_w$results$trajectory_weibull_compare
    cli::cli_alert_info("已复用既有 weibull 结果（仅重绘）")
  }
}

cfg_db <- config_ix
cfg_db$project$database <- "MIMIC"
cfg_db$project$output_dir <- out_root
ctx$config <- cfg_db
ctx$root_output_dir <- out_root
ctx$output_dir <- out_root
ctx$output_dir_tables <- file.path(out_root, "Tables")
ctx$output_dir_figures <- file.path(out_root, "Figures")
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)

id_col <- cfg_db$data$id_column %||% "subject_id"
wide_tpl <- cfg_db$trajectory_jlcm$rawdata_path_template %||% NULL
wide_path <- if (!is.null(wide_tpl)) gsub("\\{Index\\}", ix_src, gsub("\\{db\\}", db, wide_tpl)) else NULL
other_ix <- trajectory_batch_other_index_vars(cfg_db, ix_src)
pack <- ctx$results$trajectory_jlcm_models[[ix_src]]

for (slot in c("imputed", "cleaned", "mapped")) {
  if (is.null(ctx$data[[slot]])) next
  d <- ctx$data[[slot]]
  if (exists("trajectory_coerce_vital_numeric", mode = "function"))
    d <- trajectory_coerce_vital_numeric(d)
  if (!is.null(wide_path) && file.exists(wide_path))
    d <- trajectory_merge_wide_baseline_index(d, wide_path, ix_src, id_col, day = 1L)
  if (!is.null(pack$model_data_final) && id_col %in% names(pack$model_data_final)) {
    keep_ids <- unique(as.character(pack$model_data_final[[id_col]]))
    d[[id_col]] <- as.character(d[[id_col]])
    d <- d[d[[id_col]] %in% keep_ids, , drop = FALSE]
  } else {
    d <- trajectory_filter_to_index_cohort(d, ix_src, id_col)
  }
  drop_cols <- intersect(other_ix, names(d))
  if (length(drop_cols)) d <- d[, setdiff(names(d), drop_cols), drop = FALSE]
  ctx$data[[slot]] <- d
}

if (!is.null(ctx$results$data_before_mi)) {
  d0 <- ctx$results$data_before_mi
  if (!is.null(pack$model_data_final) && id_col %in% names(pack$model_data_final) && id_col %in% names(d0)) {
    keep_ids <- unique(as.character(pack$model_data_final[[id_col]]))
    d0[[id_col]] <- as.character(d0[[id_col]])
    d0 <- d0[d0[[id_col]] %in% keep_ids, , drop = FALSE]
  }
  drop_cols <- intersect(other_ix, names(d0))
  if (length(drop_cols)) d0 <- d0[, setdiff(names(d0), drop_cols), drop = FALSE]
  if (!ix_src %in% names(d0) && ix_src %in% names(ctx$data$imputed)) {
    d0 <- dplyr::left_join(d0, ctx$data$imputed[, c(id_col, ix_src), drop = FALSE], by = id_col)
  }
  ctx$results$data_before_mi <- d0
  cli::cli_alert_info("队列过滤后 data_before_mi n = {nrow(d0)}")
}
cli::cli_alert_info("队列过滤后 imputed n = {nrow(ctx$data$imputed)}")
stopifnot(nrow(ctx$data$imputed) > 0L)

ctx <- .write_class_from_ng(ctx, ix_src, ng, id_col = id_col)
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)
writeLines(as.character(ng), file.path(out_root, "Tables", "Summary", paste0("optimal_ng_", ix_src, ".txt")))
.write_jlcm_final_covariates(out_root, ix_src, pack$covariate_vars_used)

# 清空根 Tables/Figures 旧发表物（保留 Summary）
tab_root <- file.path(out_root, "Tables")
fig_root <- file.path(out_root, "Figures")
arch <- file.path(tab_root, "_archive")
dir.create(arch, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(tab_root, full.names = TRUE)) {
  bn <- basename(f)
  if (bn %in% c("Summary", "_archive")) next
  dest <- file.path(arch, bn)
  if (file.exists(dest)) unlink(dest, recursive = TRUE, force = TRUE)
  file.rename(f, dest)
}
if (dir.exists(fig_root)) {
  raw <- file.path(fig_root, "_raw")
  dir.create(raw, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(fig_root, full.names = TRUE)) {
    bn <- basename(f)
    if (bn %in% c("_raw", "_archive")) next
    if (dir.exists(f)) next
    file.copy(f, file.path(raw, bn), overwrite = TRUE)
    unlink(f)
  }
}

# Table 2 + 后验分类（不重拟合）
if (!is.null(pack$models)) {
  options(pipeline.database_name = "MIMIC")
  fp_t2 <- file.path(ctx$output_dir_tables, "Table 2-MIMIC. Metrics for determining the optimal number of classes.xlsx")
  t2_title <- paste0("Table 2. Metrics for determining the optimal number of classes (", ix_src, ")")
  ok <- tryCatch({
    trajectory_export_table2_sci(ctx, pack$models, fp_t2, t2_title)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("Table2 SCI 导出失败: {e$message}")
    FALSE
  })
  if (!ok && exists("trajectory_export_table2_xlsx", mode = "function")) {
    trajectory_export_table2_xlsx(pack$models, fp_t2, index_name = ix_src)
  }
  m_sel <- pack$models[[paste0("m", ng)]]
  fp_s8 <- file.path(ctx$output_dir_tables, "Table S8-MIMIC. Posterior classification table.xlsx")
  tryCatch(
    trajectory_export_posterior_classification_sci(
      ctx, m_sel, fp_s8,
      paste0("Table S8. Posterior classification table (", ix_src, ", MIMIC)")
    ),
    error = function(e) cli::cli_alert_warning("后验表导出失败: {e$message}")
  )
}

blocks_run <- c(
  "baseline_binary",
  "univariate_prognosis",
  "multicollinearity_screen",
  "multivariate_prognosis",
  "multivariate_covariate_resolve",
  "multicollinearity_final",
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
  name = paste0("trajectory_prognosis_mcv_ng", ng),
  blocks = blocks_run,
  render_tables_after = c(
    "baseline_binary", "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE, dir = out_ck)
)

cli::cli_h2("重跑下游（不重拟合 JLCM；ng={ng}）")
ctx$config <- cfg_db
ctx <- run_pipeline(
  root, config = cfg_db, pipeline = pl,
  run_opts = list(initial_ctx = ctx, only = blocks_run)
)

tryCatch({
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix_src,
    dbs = c(db),
    disease = "ischemic stroke"
  )
}, error = function(e) cli::cli_alert_warning("curate 失败: {e$message}"))

# curate 后再次写回 JLCM FinalCovariates，避免被 VIF Model2 覆盖
.write_jlcm_final_covariates(out_root, ix_src, pack$covariate_vars_used)

cli::cli_alert_success("MCV 二类续跑完成 → {.file {out_root}}")
cli::cli_alert_info("Table1 n 应为 {nrow(ctx$data$imputed)}；optimal_ng={ng}")
