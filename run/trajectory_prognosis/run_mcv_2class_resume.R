#!/usr/bin/env Rscript
# MCV 二类续跑：从 dynpred 起接着跑（不重拟合 JLCM）
# 个体 dynpred 图从 【success】MCV 复制；weibull 重放竖向 Acc/Sens/Spec

.ca <- commandArgs(trailingOnly = FALSE)
.f <- grep("^--file=", .ca, value = TRUE)
script_dir <- if (length(.f)) dirname(normalizePath(sub("^--file=", "", .f[[1]]), winslash = "/")) else getwd()
root <- if (basename(script_dir) == "trajectory_prognosis") {
  normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
} else normalizePath(getwd(), winslash = "/")
setwd(root)

source("R/feishu_env.R"); feishu_load_dotenv(root)
source("R/utils.R")
source("R/pipeline_runner.R")
source("R/study_batch_runner.R")
source("R/trajectory_prognosis_batch_runner.R")
source("configs/indices/composite_index_vars.R")
source("R/trajectory_paper_tables.R")
source("R/trajectory_pub_curate.R")
source("R/trajectory_survival_utils.R")

cfg_path <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/config_trajectory_prognosis_stroke_batch.R"
source(cfg_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1, pipeline.database_name = "MIMIC")

ix <- "MCV"; ng <- 2L; db <- "mimic"
out_root <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/by_index/MCV/mimic"
src_ck <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/checkpoints/by_index/MCV/mimic"
out_ck <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/checkpoints/by_index/MCV_rerun_ng2/mimic"
success_fig <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/by_index/【success】MCV/mimic/Figures"

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
config_ix$project$output_dir <- dirname(out_root)
config_ix$prediction$index_vars <- c(ix)
config_ix$survival$index_var <- ix
config_ix$trajectory_jlcm$auto_select_class_ng <- FALSE
config_ix$trajectory_jlcm$assign_class_ng <- ng
config_ix$trajectory_jlcm$prefer_final_ng <- ng
config_ix$trajectory_plot_jlcm$class_for_plot <- ng
config_ix$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
config_ix$trajectory_chisq$class_for_test <- ng
config_ix$trajectory_chisq$use_optimal_class_ng <- FALSE
if (is.null(config_ix$trajectory_dynpred$jlcm)) config_ix$trajectory_dynpred$jlcm <- list()
config_ix$trajectory_dynpred$jlcm$prefer_ng <- ng
config_ix$trajectory_weibull_compare$jlcm_ng <- ng
config_ix$trajectory_weibull_compare$replay_from_results <- TRUE
config_ix$trajectory_baseline_by_class$vars_from <- "table1"

for (blk in names(config_ix)) {
  if (!is.list(config_ix[[blk]])) next
  if (!is.null(config_ix[[blk]]$pause_enable)) config_ix[[blk]]$pause_enable <- FALSE
  if (!is.null(config_ix[[blk]]$pause_on_no_output)) config_ix[[blk]]$pause_on_no_output <- FALSE
  if (!is.null(config_ix[[blk]]$index_vars)) config_ix[[blk]]$index_vars <- c(ix)
}

# 从已完成的 km 检查点续跑
ctx <- study_batch_load_checkpoint_ctx(out_ck, "trajectory_km_class")
# 补 JLCM + weibull
ctx_j <- study_batch_load_checkpoint_ctx(src_ck, "trajectory_jlcm")
ctx$results$trajectory_jlcm_models <- ctx_j$results$trajectory_jlcm_models
if (file.exists(file.path(src_ck, "trajectory_weibull_compare.rds"))) {
  ctx_w <- study_batch_load_checkpoint_ctx(src_ck, "trajectory_weibull_compare")
  ctx$results$trajectory_weibull_compare <- ctx_w$results$trajectory_weibull_compare
}

cfg_db <- config_ix
cfg_db$project$database <- "MIMIC"
cfg_db$project$output_dir <- out_root
ctx$config <- cfg_db
ctx$root_output_dir <- out_root
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)

# 确保 ng=2 class 列存在
id_col <- cfg_db$data$id_column %||% "subject_id"
pack <- ctx$results$trajectory_jlcm_models[[ix]]
m <- pack$models$m2
if (is.list(m) && inherits(m$best, "Jointlcmm")) m <- m$best
pprob <- as.data.frame(m$pprob)
md <- unique(pack$model_data_final[, c(id_col, "subject_id_num")])
sc <- dplyr::left_join(md, pprob[, c("subject_id_num", "class")], by = "subject_id_num")
sc$trajectory_class <- as.integer(sc$class)
sc$trajectory_class_MCV <- sc$trajectory_class
for (slot in c("imputed", "cleaned", "mapped")) {
  if (is.null(ctx$data[[slot]])) next
  d <- ctx$data[[slot]]
  d[[id_col]] <- as.character(d[[id_col]])
  d$trajectory_class <- NULL
  d$trajectory_class_MCV <- NULL
  d <- dplyr::left_join(
    d,
    dplyr::mutate(sc[, c(id_col, "trajectory_class", "trajectory_class_MCV")],
                  !!id_col := as.character(.data[[id_col]])),
    by = id_col
  )
  # 队列过滤
  keep_ids <- unique(as.character(pack$model_data_final[[id_col]]))
  d <- d[d[[id_col]] %in% keep_ids, , drop = FALSE]
  ctx$data[[slot]] <- d
}
ctx$results$trajectory_optimal_ng <- ng
ctx$results$trajectory_optimal_ng_MCV <- ng
cli::cli_alert_info("续跑 imputed n={nrow(ctx$data$imputed)}")

blocks_run <- c(
  "trajectory_dynpred",
  "trajectory_piecewise_cox",
  "trajectory_weibull_compare",
  "trajectory_subgroup_class",
  "trajectory_chisq"
)

pl <- list(
  name = "mcv2_resume",
  blocks = blocks_run,
  checkpoint = list(enable = TRUE, dir = out_ck)
)

cli::cli_h2("续跑 dynpred / piecewise / weibull / subgroup / chisq")
ctx <- run_pipeline(
  root, config = cfg_db, pipeline = pl,
  run_opts = list(initial_ctx = ctx, only = blocks_run)
)

# 复制个体动态预测图（不重跑）
fig_dest <- file.path(out_root, "Figures")
dir.create(fig_dest, recursive = TRUE, showWarnings = FALSE)
cand <- list.files(success_fig, pattern = "Individual|Dynpred Individual|Figure 4", full.names = TRUE, ignore.case = TRUE)
cand <- c(cand, list.files(file.path(success_fig, "_raw"), pattern = "Individual|Dynpred", full.names = TRUE, ignore.case = TRUE))
for (f in unique(cand)) {
  if (file.exists(f) && grepl("\\.pdf$", f, ignore.case = TRUE)) {
    file.copy(f, file.path(fig_dest, basename(f)), overwrite = TRUE)
    cli::cli_alert_info("copied individual fig: {basename(f)}")
  }
}

tryCatch({
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix,
    dbs = c(db),
    disease = "ischemic stroke"
  )
}, error = function(e) cli::cli_alert_warning("curate: {e$message}"))

# JLCM FinalCovariates
writeLines(
  c(
    "# Final covariates (JLCM survival submodel) — MCV / MIMIC",
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    pack$covariate_vars_used
  ),
  file.path(out_root, "Tables", "Summary", "FinalCovariates_MCV_mimic.txt")
)
writeLines("2", file.path(out_root, "Tables", "Summary", "optimal_ng_MCV.txt"))

# 确保 S7 命名
s5 <- file.path(out_root, "Tables", "Table_S5_Baseline_By_Class_MCV.xlsx")
s7 <- file.path(out_root, "Tables", "Table S7-MIMIC. Baseline characteristics by trajectory class (MCV).xlsx")
if (file.exists(s5) && !file.exists(s7)) file.copy(s5, s7, overwrite = TRUE)
if (file.exists(s5) && file.exists(s7)) {
  # prefer newer
  if (file.info(s5)$mtime >= file.info(s7)$mtime) file.copy(s5, s7, overwrite = TRUE)
}

cli::cli_alert_success("MCV 二类续跑完成 → {out_root}")
