#!/usr/bin/env Rscript
# 重跑 GPR PAMM（修 offset/PED）并输出 fcimb Fig5/6 四面板
# Fig5 = MIMIC 发现集；Fig6 = eICU 外验（锁定发现集阈值）
#
#   Rscript run/trajectory_prognosis/rerun_gpr_pamm_fcimb.R

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
source("Blocks/26_trajectory/30block_trajectory_pamm.R")

Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

ix <- "GPR"
proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
ck_root <- file.path(proj, "checkpoints/by_index/GPR")
out_root <- file.path(proj, "by_index/\u3010success\u3011GPR")

config$trajectory_pamm$index_vars <- ix
config$trajectory_pamm$export_figures <- TRUE
config$trajectory_pamm$plot_landmarks <- c(2, 5, 12)
config$trajectory_jlcm$index_vars <- ix

.run_one <- function(db) {
  cli::cli_h1("PAMM {toupper(db)}")
  prev <- file.path(ck_root, db, "trajectory_pamm.rds")
  if (!file.exists(prev)) prev <- file.path(ck_root, db, "trajectory_km_class.rds")
  if (!file.exists(prev)) stop("无 checkpoint: ", db)
  packed <- readRDS(prev)
  ctx <- packed$ctx %||% packed
  ctx$config <- config
  ctx$config$project$database <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  db_out <- file.path(out_root, db)
  step_out <- file.path(db_out, "step25_trajectory_pamm")
  dir.create(file.path(step_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(step_out, "Tables", "PAMM"), recursive = TRUE, showWarnings = FALSE)
  ctx$root_output_dir <- db_out
  ctx$output_dir <- step_out
  ctx$output_dir_tables <- file.path(step_out, "Tables")
  ctx$output_dir_figures <- file.path(step_out, "Figures")
  ctx$config$project$output_dir <- db_out

  # 确保 imputed 在
  if (is.null(ctx$data$imputed) || !nrow(ctx$data$imputed)) {
    mi <- file.path(db_out, "step06_imputation/D01_AfterMI_Data.RData")
    if (file.exists(mi)) {
      e <- new.env(parent = emptyenv()); load(mi, envir = e)
      ctx$data$imputed <- e$imputed %||% e$data %||% e[[ls(e)[1]]]
    }
  }

  ctx <- block_trajectory_pamm(ctx)
  saveRDS(list(ctx = ctx, saved_at = Sys.time(), block = "trajectory_pamm"),
          file.path(ck_root, db, "trajectory_pamm.rds"))

  src <- list.files(file.path(step_out, "Figures"), pattern = "PAMM.*\\.pdf$", full.names = TRUE)
  if (!length(src)) {
    cli::cli_alert_danger("{toupper(db)}: 无 PAMM PDF")
    return(invisible(FALSE))
  }
  src <- src[which.max(file.info(src)$mtime)]
  dest_name <- if (identical(db, "mimic"))
    "Figure 5-MIMIC. PAMM time-varying association.pdf"
  else
    "Figure 6-eICU. PAMM time-varying association.pdf"
  dest <- file.path(db_out, "Figures", dest_name)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest, overwrite = TRUE)
  file.copy(src, file.path(db_out, "Figures", "Figure PAMM GPR fcimb panels.pdf"), overwrite = TRUE)
  cli::cli_alert_success("{toupper(db)} → {.file {dest}}")
  invisible(TRUE)
}

.run_one("mimic")
.run_one("eicu")
cli::cli_alert_success("PAMM Fig5/6 重跑完成")
