#!/usr/bin/env Rscript
# 补跑 WPR Weibull 对比 landmark 1:3（拼入已有 4:14），对齐文献 Days 1–14。
# Day1–2：ns(df=2) 下 lcmm::dynpred 常失败→保留 NA 行；Day3 一般可估。
#
#   Rscript run/trajectory_prognosis/append_wpr_weibull_landmarks_1to3.R

suppressPackageStartupMessages({ options(warn = 1) })

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

source("R/utils.R")
source("R/pipeline_runner.R")
source("configs/indices/composite_index_vars.R")
source("Blocks/53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R")
if (file.exists("R/trajectory_survival_utils.R")) source("R/trajectory_survival_utils.R")
Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}

ix <- "WPR"
ng <- 5L
boot_n <- as.integer(.get("--boot-n", "2000"))
perm_n <- as.integer(.get("--perm-n", "2000"))
new_lms <- as.integer(strsplit(.get("--landmarks", "1,2,3"), ",")[[1]])
proj <- .get("--proj", "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
if (!dir.exists(proj))
  proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"

out_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
ck_root <- file.path(proj, "checkpoints/by_index", ix)
disc_model_dir <- file.path(out_root, "mimic/step14_trajectory_jlcm/Data")
cov_lock <- as.character(config$trajectory_jlcm$covariate_vars)

.merge_write <- function(old_csv, new_df, outs) {
  old <- if (file.exists(old_csv)) utils::read.csv(old_csv, stringsAsFactors = FALSE) else NULL
  keep_old <- if (!is.null(old)) old[!old$landmark %in% new_df$landmark, , drop = FALSE] else NULL
  out <- if (is.null(keep_old) || !nrow(keep_old)) new_df else rbind(keep_old, new_df)
  out <- out[order(out$landmark), , drop = FALSE]
  rownames(out) <- NULL
  for (p in outs) {
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(out, p, row.names = FALSE)
    cli::cli_alert_info("写 {p} (n={nrow(out)})")
  }
  out
}

.run_db <- function(db) {
  cli::cli_h1("{toupper(db)} · landmarks {paste(new_lms, collapse=',')} · boot={boot_n}")
  db_out <- file.path(out_root, db)
  step_out <- file.path(db_out, "step21_trajectory_weibull_compare")
  dir.create(file.path(step_out, "Tables"), recursive = TRUE, showWarnings = FALSE)

  # 载入已有结果 ctx（含 model_data / 或从 dynpred+RData 组装）
  ck_w <- file.path(ck_root, db, "trajectory_weibull_compare.rds")
  if (!file.exists(ck_w) && identical(db, "mimic"))
    stop("缺 MIMIC weibull checkpoint")
  if (!file.exists(ck_w) && identical(db, "eicu"))
    stop("缺 eICU weibull checkpoint（请先跑 locked 全量）")

  packed <- readRDS(ck_w)
  ctx <- packed$ctx %||% packed

  # 保证 JLCM 包 + 锁定协变量
  e <- new.env(parent = emptyenv())
  load(file.path(disc_model_dir, paste0("D01_jlcm_", ix, "_models.RData")), envir = e)
  pack <- ctx$results$trajectory_jlcm_models[[ix]]
  md <- pack$model_data_final
  if (is.null(md) || !nrow(md)) stop(db, ": 无 model_data_final")
  # eICU：确保锁定列存在
  for (cv in cov_lock) {
    if (!cv %in% names(md) || all(!is.finite(suppressWarnings(as.numeric(md[[cv]]))))) {
      med <- stats::median(suppressWarnings(as.numeric(e$model_data_final[[cv]])), na.rm = TRUE)
      md[[cv]] <- med
    }
  }
  ctx$results$trajectory_jlcm_models[[ix]] <- list(
    models = e$models_list_with_cov,
    model_data_final = md,
    covariate_vars_used = cov_lock
  )

  cfg <- config
  cfg$trajectory_jlcm$covariate_vars <- cov_lock
  cfg$trajectory_jlcm$covariate_vars_from_vif <- FALSE
  cfg$trajectory_weibull_compare$index_vars <- ix
  cfg$trajectory_weibull_compare$jlcm_ng <- ng
  cfg$trajectory_weibull_compare$landmarks <- new_lms
  cfg$trajectory_weibull_compare$min_unique_time_for_dynpred <- 1L
  cfg$trajectory_weibull_compare$boot_n <- boot_n
  cfg$trajectory_weibull_compare$perm_n <- perm_n
  cfg$trajectory_weibull_compare$covariate_vars <- cov_lock
  cfg$trajectory_weibull_compare$pause_enable <- FALSE
  cfg$trajectory_weibull_compare$pause_on_no_output <- FALSE
  cfg$project$database <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  cfg$project$output_dir <- db_out
  cfg$trajectory$jlcm_model_dir <- disc_model_dir
  ctx$config <- cfg
  ctx$root_output_dir <- db_out
  ctx$output_dir <- step_out
  ctx$output_dir_tables <- file.path(step_out, "Tables")
  ctx$output_dir_figures <- file.path(step_out, "Figures")
  dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)

  # 只跑新 landmark：临时关掉 pause
  ctx <- block_trajectory_weibull_compare(ctx)
  new_df <- ctx$results$trajectory_weibull_compare[[ix]]
  if (is.null(new_df) || !nrow(new_df)) stop(db, ": 无新结果")

  old_csv <- if (identical(db, "mimic")) {
    file.path(db_out, "Tables/_archive/Table_Weibull_Dynamic_Compare_WPR.csv")
  } else {
    file.path(out_root, "summary_results/Tables/Table_Weibull_Dynamic_Compare_WPR_eICU.csv")
  }
  if (!file.exists(old_csv))
    old_csv <- file.path(db_out, "Tables/Table_Weibull_Dynamic_Compare_WPR.csv")

  outs <- unique(c(
    old_csv,
    file.path(step_out, "Tables/Table_Weibull_Dynamic_Compare_WPR.csv"),
    file.path(db_out, "Tables/Table_Weibull_Dynamic_Compare_WPR.csv"),
    file.path(db_out, "Tables/_archive/Table_Weibull_Dynamic_Compare_WPR.csv"),
    if (identical(db, "eicu"))
      file.path(out_root, "summary_results/Tables/Table_Weibull_Dynamic_Compare_WPR_eICU.csv")
    else
      file.path(out_root, "summary_results/Tables/Table_Weibull_Dynamic_Compare_WPR_MIMIC.csv")
  ))
  merged <- .merge_write(old_csv, new_df, outs)
  print(merged[, c("landmark", "n_landmark", "auc_dyn", "auc_weib", "p_auc")])

  # 更新 checkpoint 内结果表
  ctx$results$trajectory_weibull_compare[[ix]] <- merged
  saveRDS(
    list(ctx = ctx, saved_at = Sys.time(), block = "trajectory_weibull_compare"),
    file.path(ck_root, db, "trajectory_weibull_compare.rds")
  )
  invisible(merged)
}

.run_db("mimic")
.run_db("eicu")
cli::cli_alert_success("已拼入 landmarks {paste(new_lms, collapse=',')}；请重画 Figure S2")
