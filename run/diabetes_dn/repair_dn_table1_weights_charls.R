#!/usr/bin/env Rscript
# 24_diabetes：去掉 NHANES 表权重行；Linux 路径下刷新 Gate A；重跑 WPR baseline→Table2
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/24_diabetes/incidence_38341157"
cfg_path <- file.path(study, "config_incidence_dual_batch.R")
ix <- "WPR"

.write_linux_config <- function() {
  txt <- readLines(cfg_path, warn = FALSE)
  txt <- gsub("G:/02block_result", "/mnt/g/02block_result", txt, fixed = TRUE)
  tmp <- file.path(study, ".config_linux_repair.R")
  writeLines(txt, tmp)
  tmp
}

.linux_study_paths <- function(cfg) {
  lr <- "/mnt/g/02block_result/24_diabetes/incidence_38341157"
  cfg$project$output_dir <- lr
  cfg$data$rawdata_path <- file.path(lr, "Data/nhanes/dabiao.RData")
  cfg$dual_db$primary$rawdata_path <- file.path(lr, "Data/nhanes/dabiao.RData")
  cfg$dual_db$secondary$rawdata_path <- file.path(lr, "Data/charls/dabiao.RData")
  cfg$dual_db$checkpoint_base <- file.path(lr, "checkpoints")
  cfg$dual_db$harmonization_dir <- file.path(lr, "checkpoints/_global_harmonization")
  cfg$incidence_batch$output_base <- lr
  cfg$incidence_batch$shared_ck_base <- file.path(lr, "checkpoints/_shared")
  cfg$incidence_batch$index_ck_base <- file.path(lr, "checkpoints/by_index")
  cfg
}

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/pipeline_runner.R"))

strip_weights_python <- function() {
  py <- sprintf(
    "python3 %s",
    shQuote(file.path(root, "run/diabetes_dn/strip_nhanes_weight_rows_xml.py"), type = "sh")
  )
  message(py)
  status <- system(py)
  if (status != 0L) stop("weight strip python failed", call. = FALSE)
}

refresh_gate_a_local <- function(linux_cfg) {
  ga <- file.path(study, "checkpoints/_global_harmonization/gate_a_columns.rds")
  if (file.exists(ga)) file.remove(ga)
  for (db in c("CHARLS", "NHANES")) {
    for (bn in c("step03_dual_db_column_harmonize.rds", "dual_db_column_harmonize.rds")) {
      p <- file.path(study, "checkpoints/_shared", db, bn)
      if (file.exists(p)) file.remove(p)
    }
  }
  local_env <- new.env(parent = globalenv())
  source(linux_cfg, local = local_env)
  cfg <- local_env$config
  owd <- getwd()
  on.exit(setwd(owd), add = TRUE)
  setwd(root)
  ga_res <- incidence_batch_ensure_gate_a(cfg, root = study, force = TRUE)
  ga_new <- ga_res$gate_a
  message("Gate A mimic keep (", length(ga_new$column_keep_mimic), "): ",
          paste(ga_new$column_keep_mimic, collapse = ", "))
  message("Gate A nhanes keep (", length(ga_new$column_keep_nhanes), ")")
  invisible(ga_new)
}

rerun_shared_harmonize <- function(linux_cfg) {
  cmd <- sprintf(
    "MEDICAL_BLOCKS_ROOT=%s Rscript %s --config %s --shared-only --no-skip",
    shQuote(root, type = "sh"),
    shQuote(file.path(root, "run/incidence/run_incidence_dual_batch.R"), type = "sh"),
    shQuote(linux_cfg, type = "sh")
  )
  message("shared harmonize: ", cmd)
  status <- system(cmd)
  if (status != 0L) stop("shared-only failed exit=", status, call. = FALSE)
}

purge_wpr_checkpoints <- function() {
  ck <- file.path(study, "checkpoints/by_index", ix)
  if (dir.exists(ck)) unlink(ck, recursive = TRUE)
  message("removed checkpoint dir: ", ck)
}

rerun_wpr <- function(linux_cfg) {
  env <- paste0(
    "MEDICAL_BLOCKS_ROOT=", shQuote(root, type = "sh"), " ",
    "INCIDENCE_BATCH_ROOT=", shQuote(study, type = "sh")
  )
  cmd <- paste(
    env,
    "Rscript", shQuote(file.path(root, "run/incidence/run_incidence_dual_batch_worker.R"), type = "sh"),
    "--index", ix,
    "--config", shQuote(linux_cfg, type = "sh")
  )
  message("rerun: ", cmd)
  status <- system(cmd)
  if (status != 0L) stop("WPR worker failed exit=", status, call. = FALSE)
}

linux_cfg <- .write_linux_config()
strip_weights_python()
refresh_gate_a_local(linux_cfg)
rerun_shared_harmonize(linux_cfg)
purge_wpr_checkpoints()
rerun_wpr(linux_cfg)
message("done")
