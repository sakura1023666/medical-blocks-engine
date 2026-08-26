#!/usr/bin/env Rscript
# 对齐三库中介：Figure S3 底边用 Direct Effect；表首行=路径图中介(Triglycerides)
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

ix <- "UHR"
dual_dir <- file.path(study, "by_index", "【success】UHR")
lock <- jsonlite::fromJSON(file.path(study, "data/harmonized/covariate_lock.json"))
m1 <- as.character(lock$model1)
m2 <- as.character(lock$model2)

# 钉死三库同一中介
dual_db_save_preferred_mediator(study, list(dual_db = list(enable = TRUE), project = list(root = study)), "Triglycerides")

# ── Dual NHANES + CHARLS ────────────────────────────────────────────────────
source(file.path(study, "config_incidence_dual_batch.R"))
config$incidence_batch$sensitivity_suite$enable <- FALSE
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config$mediation_nhanes_weighted$best_mediator <- "Triglycerides"
config$mediation_incidence$best_mediator <- "Triglycerides"
config$mediation_nhanes_weighted$covariates <- m1
config$mediation_incidence$covariates <- m1
config$dual_db$harmonization$lock_covariates_preset <- TRUE
config$dual_db$harmonization$harmonized_model1_nhanes <- m1
config$dual_db$harmonization$harmonized_model2_nhanes <- m2
config$dual_db$harmonization$harmonized_model1_mimic <- m1
config$dual_db$harmonization$harmonized_model2_mimic <- m2

for (db in c("nhanes", "mimic")) {
  cfg_db <- incidence_batch_apply_db_overrides(config, db, root, ix)
  cfg_db$mediation_nhanes_weighted$best_mediator <- "Triglycerides"
  cfg_db$mediation_incidence$best_mediator <- "Triglycerides"
  cfg_db$mediation_nhanes_weighted$covariates <- m1
  cfg_db$mediation_incidence$covariates <- m1
  out_db <- file.path(dual_dir, dual_db_slot_path_name(cfg_db, db))
  cfg_db$project$output_dir <- out_db
  # 清旧 S3 / mediation 表，避免残留
  unlink(list.files(out_db, pattern = "Figure S3|mediation by laboratory", recursive = TRUE, full.names = TRUE))

  if (dual_db_is_weighted(config, db)) {
    pl <- pipeline_nhanes_batch
    from_tok <- "subgroup_nhanes_weighted"
    only_blks <- "mediation_nhanes_weighted"
  } else {
    pl <- pipeline_regular_batch
    from_tok <- "subgroup_incidence"
    only_blks <- "mediation_incidence"
  }
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- file.path(study, "checkpoints", "by_index", ix, dual_db_slot_path_name(config, db))
  cli::cli_h2("重跑中介 [{toupper(db)}]")
  run_pipeline(root, config = cfg_db, pipeline = pl,
               run_opts = list(from = from_tok, only = only_blks))
}

# ── Liling ──────────────────────────────────────────────────────────────────
cli::cli_h2("重跑中介 [LILING]")
source(file.path(study, "config_incidence_liling.R"))
config$project$output_dir <- file.path(dual_dir, "Liling")
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config$mediation_incidence$best_mediator <- "Triglycerides"
config$mediation_incidence$covariates <- m1
unlink(list.files(file.path(dual_dir, "Liling"), pattern = "Figure S3|mediation by laboratory", recursive = TRUE, full.names = TRUE))
pipeline$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
from_tok <- if (file.exists(file.path(pipeline$checkpoint$dir, "subgroup_incidence.rds"))) {
  "subgroup_incidence"
} else {
  "logistic_binary_glm_rcs"
}
run_pipeline(root, config = config, pipeline = pipeline,
             run_opts = list(from = from_tok, only = "mediation_incidence"))

# ── 收集 summary ────────────────────────────────────────────────────────────
sum_fig <- file.path(study, "summary_result", "figure")
sum_tab <- file.path(study, "summary_result", "table")
dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

.copy_latest <- function(pattern, dest_dir) {
  files <- list.files(dual_dir, pattern = pattern, recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/sensitivity/", files)]
  if (!length(files)) return(invisible(NULL))
  # 每库取最新
  by_db <- split(files, ifelse(grepl("NHANES", files), "NHANES",
                        ifelse(grepl("CHARLS", files), "CHARLS",
                        ifelse(grepl("Liling", files), "Liling", "other"))))
  for (db in names(by_db)) {
    if (db == "other") next
    fs <- by_db[[db]]
    fs <- fs[order(file.info(fs)$mtime, decreasing = TRUE)]
    f <- fs[[1L]]
    file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE)
    cli::cli_alert_success("summary <- {basename(f)}")
  }
}
.copy_latest("Figure S3.*\\.pdf$", sum_fig)
.copy_latest(".*mediation by laboratory.*\\.xlsx$", sum_tab)

cli::cli_alert_success("三库中介图/表已对齐并写入 summary_result")
