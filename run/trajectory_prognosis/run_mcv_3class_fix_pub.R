#!/usr/bin/env Rscript
# =============================================================================
#  MCV_3class 发表表/图修复（不重拟合 JLCM）
#
#  修复点：
#    1) Table1/S1/UV/MV/VIF：仅当前暴露 MCV + N 对齐 JLCM 队列
#    2) Table S7：与 Table1 变量/顺序一致（按类别）
#    3) Figure S4：三类双面板森林图
#    4) Figure S7–S9：Acc/Sens/Spec 独立线形图（复用已有 weibull 结果）
#
#  用法:
#    SMOKE_NO_FEISHU=1 Rscript run/trajectory_prognosis/run_mcv_3class_fix_pub.R \
#      --config ".../config_trajectory_prognosis_stroke_batch.R"
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(config = NULL, src_unit = "MCV", out_unit = "MCV_3class", ng = 3L, db = "mimic")
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
  ctx$results[[paste0("trajectory_optimal_ng_", Index)]] <- as.integer(ng)
  ctx$results$trajectory_optimal_ng <- as.integer(ng)
  ctx
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
source(file.path(root, "R/trajectory_survival_utils.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))
source(file.path(root, "Blocks/03_imputation/01block_imputation.R"))  # Table S1 重建需要 .imp01_build_table_s1
source(file.path(root, "Blocks/53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R"))

config_path <- normalizePath(opt$config, winslash = "/", mustWork = TRUE)
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1, pipeline.database_name = "MIMIC")

config_ix <- trajectory_batch_patch_config_for_index(config, ix_src)
config_ix$project$output_dir <- file.path(
  (config_ix$trajectory_batch %||% list())$output_base %||% config_ix$project$output_dir,
  "by_index", ix_out
)
config_ix$trajectory_jlcm$auto_select_class_ng <- FALSE
config_ix$trajectory_jlcm$assign_class_ng <- ng
config_ix$trajectory_baseline_by_class$vars_from <- "table1"
config_ix$trajectory_baseline_by_class$index_vars <- c(ix_src)
config_ix$trajectory_subgroup_class$index_vars <- c(ix_src)
config_ix$trajectory_weibull_compare$index_vars <- c(ix_src)
config_ix$trajectory_weibull_compare$jlcm_ng <- ng
config_ix$trajectory_weibull_compare$replay_from_results <- TRUE
config_ix$trajectory_weibull_compare$pause_enable <- FALSE
config_ix$trajectory_weibull_compare$pause_on_no_output <- FALSE
config_ix$trajectory_subgroup_class$pause_enable <- FALSE
config_ix$trajectory_baseline_by_class$pause_enable <- FALSE
config_ix$baseline_binary$pause_enable <- FALSE
config_ix$univariate_prognosis$pause_enable <- FALSE
config_ix$multivariate_prognosis$pause_enable <- FALSE
config_ix$multivariate_prognosis$fail_on_index_ns <- FALSE

src_ck <- trajectory_batch_index_ck_dir(
  trajectory_batch_patch_config_for_index(config, ix_src), ix_src, db
)
out_root <- file.path(config_ix$project$output_dir, db)
out_ck <- file.path(
  (config_ix$trajectory_batch %||% list())$index_ck_base %||%
    file.path((config_ix$trajectory_batch %||% list())$output_base, "checkpoints", "by_index"),
  ix_out, db
)
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ck, recursive = TRUE, showWarnings = FALSE)

cli::cli_h1("MCV_3class 发表修复（不重拟合 JLCM）")

# 从源指标 JLCM 检查点载入（含模型 + 插补后数据）
ctx <- study_batch_load_checkpoint_ctx(src_ck, "trajectory_jlcm")
# 若 MCV_3class 已有 weibull 结果，优先复用，避免重算
ck3 <- file.path(out_ck, "trajectory_weibull_compare.rds")
if (file.exists(ck3)) {
  ctx3 <- tryCatch(study_batch_load_checkpoint_ctx(out_ck, "trajectory_weibull_compare"), error = function(e) NULL)
  if (!is.null(ctx3$results$trajectory_weibull_compare)) {
    ctx$results$trajectory_weibull_compare <- ctx3$results$trajectory_weibull_compare
    cli::cli_alert_info("已复用 MCV_3class 既有 weibull 结果")
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
# 续跑时重置发表编号，避免 Table 1 被写成 Table 2/S9…
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)

id_col <- cfg_db$data$id_column %||% "subject_id"
# 合并暴露 + 过滤到 JLCM 队列
wide_tpl <- cfg_db$trajectory_jlcm$rawdata_path_template %||% NULL
wide_path <- if (!is.null(wide_tpl)) gsub("\\{Index\\}", ix_src, gsub("\\{db\\}", db, wide_tpl)) else NULL
other_ix <- trajectory_batch_other_index_vars(cfg_db, ix_src)
for (slot in c("imputed", "cleaned", "mapped")) {
  if (is.null(ctx$data[[slot]])) next
  d <- ctx$data[[slot]]
  if (exists("trajectory_coerce_vital_numeric", mode = "function"))
    d <- trajectory_coerce_vital_numeric(d)
  if (!is.null(wide_path) && file.exists(wide_path))
    d <- trajectory_merge_wide_baseline_index(d, wide_path, ix_src, id_col, day = 1L)
  # 优先按 JLCM subject 过滤（与轨迹图完全一致）
  pack <- ctx$results$trajectory_jlcm_models[[ix_src]]
  if (!is.null(pack$model_data_final) && id_col %in% names(pack$model_data_final)) {
    keep_ids <- unique(as.character(pack$model_data_final[[id_col]]))
    d[[id_col]] <- as.character(d[[id_col]])
    d <- d[d[[id_col]] %in% keep_ids, , drop = FALSE]
  } else {
    d <- trajectory_filter_to_index_cohort(d, ix_src, id_col)
  }
  # 剔除其它复合暴露指标（保留 trajectory_class* 供按类表/亚组）
  drop_cols <- intersect(other_ix, names(d))
  if (length(drop_cols)) d <- d[, setdiff(names(d), drop_cols), drop = FALSE]
  ctx$data[[slot]] <- d
}
# Table S1 的插补前数据也必须对齐同一 JLCM 队列
if (!is.null(ctx$results$data_before_mi)) {
  d0 <- ctx$results$data_before_mi
  pack <- ctx$results$trajectory_jlcm_models[[ix_src]]
  if (!is.null(pack$model_data_final) && id_col %in% names(pack$model_data_final)) {
    keep_ids <- unique(as.character(pack$model_data_final[[id_col]]))
    if (id_col %in% names(d0)) {
      d0[[id_col]] <- as.character(d0[[id_col]])
      d0 <- d0[d0[[id_col]] %in% keep_ids, , drop = FALSE]
    }
  } else if (ix_src %in% names(d0)) {
    d0 <- trajectory_filter_to_index_cohort(d0, ix_src, id_col)
  }
  drop_cols <- intersect(other_ix, names(d0))
  if (length(drop_cols)) d0 <- d0[, setdiff(names(d0), drop_cols), drop = FALSE]
  ctx$results$data_before_mi <- d0
  cli::cli_alert_info("队列过滤后 data_before_mi n = {nrow(d0)}")
}
cli::cli_alert_info("队列过滤后 imputed n = {nrow(ctx$data$imputed)}")

# 恢复 JLCM FinalCovariates（避免被后续 VIF Model2 覆盖语义混淆）
pack <- ctx$results$trajectory_jlcm_models[[ix_src]]
jlcm_cov <- as.character(pack$covariate_vars_used %||% character(0))
if (length(jlcm_cov)) {
  sum_dir <- file.path(out_root, "Tables", "Summary")
  dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
  cov_lines <- c(
    paste0("# Final covariates (JLCM survival submodel) — ", ix_src, " / MIMIC"),
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    jlcm_cov
  )
  writeLines(cov_lines, file.path(sum_dir, paste0("FinalCovariates_", ix_src, "_mimic.txt")))
}

ctx <- .write_class_from_ng(ctx, ix_src, ng, id_col = id_col)
# 再次重置计数器（write_class 后仍需从 Table 1 起算）
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)
writeLines(as.character(ng), file.path(out_root, "Tables", "Summary", paste0("optimal_ng_", ix_src, ".txt")))

# 清空根 Tables 多余文件，避免 curate 再混入旧错号表
tab_root <- file.path(out_root, "Tables")
dir.create(file.path(tab_root, "_archive"), recursive = TRUE, showWarnings = FALSE)
keep_names <- c(
  "Summary", "_archive",
  sprintf("Table 2-MIMIC. Metrics for determining the optimal number of classes.xlsx"),
  sprintf("Table 3-MIMIC. Time-dependent HR for trajectory classes.xlsx"),
  sprintf("Table S8-MIMIC. Posterior classification table.xlsx")
)
for (f in list.files(tab_root, full.names = TRUE)) {
  bn <- basename(f)
  if (bn %in% keep_names || bn == "Summary" || bn == "_archive") next
  dest <- file.path(tab_root, "_archive", bn)
  if (file.exists(dest)) unlink(dest, recursive = TRUE, force = TRUE)
  file.rename(f, dest)
}
cli::cli_alert_info("已将根 Tables 旧文件移入 _archive，准备重生")

# 关闭暂停
for (blk in names(cfg_db)) {
  if (is.list(cfg_db[[blk]]) && !is.null(cfg_db[[blk]]$pause_enable)) {
    cfg_db[[blk]]$pause_enable <- FALSE
    cfg_db[[blk]]$pause_on_no_output <- FALSE
  }
}
# 不重跑 weibull（慢且已修好）；只重生表 + 按类基线
cfg_db$trajectory_weibull_compare$replay_from_results <- TRUE
ctx$config <- cfg_db

blocks_fix <- c(
  "baseline_binary",
  "univariate_prognosis",
  "multicollinearity_screen",
  "multivariate_prognosis",
  "multivariate_covariate_resolve",
  "multicollinearity_final",
  "trajectory_baseline_by_class"
)

pl <- list(
  name = "mcv_3class_fix_pub",
  blocks = blocks_fix,
  render_tables_after = c(
    "baseline_binary", "univariate_prognosis", "multicollinearity_screen",
    "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
  ),
  checkpoint = list(enable = TRUE, dir = out_ck)
)

cli::cli_h2("重生发表表/亚组/Weibull图（不重拟合 JLCM）")
ctx <- run_pipeline(
  root, config = cfg_db, pipeline = pl,
  run_opts = list(initial_ctx = ctx, only = blocks_fix)
)

tryCatch({
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix_src,
    dbs = c(db),
    disease = "ischemic stroke"
  )
}, error = function(e) cli::cli_alert_warning("curate 失败: {e$message}"))

# curate / VIF 后再次写回 JLCM FinalCovariates
pack <- ctx$results$trajectory_jlcm_models[[ix_src]]
jlcm_cov <- as.character(pack$covariate_vars_used %||% character(0))
if (length(jlcm_cov)) {
  sum_dir <- file.path(out_root, "Tables", "Summary")
  writeLines(
    c(
      paste0("# Final covariates (JLCM survival submodel) — ", ix_src, " / MIMIC"),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      jlcm_cov
    ),
    file.path(sum_dir, paste0("FinalCovariates_", ix_src, "_mimic.txt"))
  )
}

cli::cli_alert_success("MCV_3class 发表修复完成 → {.file {out_root}}")
cli::cli_alert_info("Table1 n 应为 {nrow(ctx$data$imputed)}；optimal_ng={ng}")
