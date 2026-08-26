#!/usr/bin/env Rscript
# 听力损失 UHR：补跑三库 Figure 3（亚组）+ Figure S3（中介），变量强制统一
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
dual_cfg <- file.path(study, "config_incidence_dual_batch.R")
lil_cfg  <- file.path(study, "config_incidence_liling.R")
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

lock_sg <- c("Age_Group", "Gender", "Marital_Status", "Hypertension")
ix <- "UHR"
dual_dir <- file.path(study, "by_index", "【success】UHR")
if (!dir.exists(dual_dir)) dual_dir <- file.path(study, "by_index", "UHR")
stopifnot(dir.exists(dual_dir))

# ── Dual NHANES + CHARLS ────────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config$incidence_batch$output_base <- study
config$incidence_batch$sensitivity_suite$enable <- FALSE
config$project$root <- study

# 写 preferred mediator + Gate D 缓存，保证双库图一致
harm_dir <- file.path(study, "checkpoints", "_global_harmonization")
dir.create(harm_dir, recursive = TRUE, showWarnings = FALSE)
dual_db_save_preferred_mediator(study, config, "Triglycerides")
saveRDS(
  list(vars = lock_sg, eligible_by_db = list(nhanes = lock_sg, mimic = lock_sg), saved_at = Sys.time()),
  file.path(harm_dir, "gate_d_subgroup_vars.rds")
)
config$subgroup$locked_subgroup_vars <- lock_sg
config$subgroup$required_subgroup_vars <- lock_sg
config$subgroup$var_source <- "required"
config$incidence$index_var <- ix
config$logistic$index_var <- ix

rerun_dual_db <- function(db) {
  cfg_db <- incidence_batch_apply_db_overrides(config, db, root, ix)
  cfg_db$subgroup$var_source <- "required"
  cfg_db$subgroup$locked_subgroup_vars <- lock_sg
  cfg_db$subgroup$required_subgroup_vars <- lock_sg
  cfg_db$incidence$index_var <- ix
  cfg_db$logistic$index_var <- ix
  if (!is.null(cfg_db$prediction)) cfg_db$prediction$index_vars <- ix
  cfg_db$mediation_nhanes_weighted$best_mediator <- "Triglycerides"
  cfg_db$mediation_incidence$best_mediator <- "Triglycerides"
  out_db <- file.path(dual_dir, dual_db_slot_path_name(cfg_db, db))
  cfg_db$project$output_dir <- out_db
  # 清掉旧 Fig3/S3，避免 Index/旧 UHR 文件残留被镜像
  for (d in c(file.path(out_db, "Figures"),
              list.dirs(out_db, recursive = FALSE, full.names = TRUE))) {
    figs <- list.files(d, pattern = "Figure 3|Figure S3", full.names = TRUE, recursive = TRUE)
    if (length(figs)) unlink(figs)
  }

  if (dual_db_is_weighted(config, db)) {
    pl <- pipeline_nhanes_batch
    from_tok <- "logistic_quartile_nhanes_weighted_rcs"
    only_blks <- c("subgroup_nhanes_weighted", "mediation_nhanes_weighted")
  } else {
    pl <- pipeline_regular_batch
    from_tok <- "logistic_quartile_glm_rcs"
    only_blks <- c("subgroup_incidence", "mediation_incidence")
  }
  ck_dir <- file.path(study, "checkpoints", "by_index", ix, dual_db_slot_path_name(config, db))
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- ck_dir
  cli::cli_h2("补跑 dual [{toupper(db)}] only={paste(only_blks, collapse=',')} from={from_tok}")
  cli::cli_alert_info("ck={ck_dir}")
  run_pipeline(
    root, config = cfg_db, pipeline = pl,
    run_opts = list(from = from_tok, only = only_blks)
  )
}

for (db in c("nhanes", "mimic")) {
  tryCatch(rerun_dual_db(db), error = function(e) {
    cli::cli_alert_danger("dual {db} 失败: {e$message}")
    stop(e)
  })
}
tryCatch(
  incidence_batch_finalize_index_outputs(root, config, ix, c("nhanes", "mimic")),
  error = function(e) cli::cli_alert_warning("finalize: {e$message}")
)

# ── Liling ──────────────────────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(lil_cfg))
# 清掉 dual 的 pipeline 对象，避免污染
rm(list = intersect(c("pipeline_nhanes_batch", "pipeline_regular_batch", "pipeline"), ls(envir = .GlobalEnv)),
   envir = .GlobalEnv)
source(lil_cfg)
config$subgroup$var_source <- "required"
config$subgroup$locked_subgroup_vars <- lock_sg
config$subgroup$required_subgroup_vars <- lock_sg
config$mediation_incidence$best_mediator <- "Triglycerides"
config$incidence$index_var <- "UHR"
config$logistic$index_var <- "UHR"
lil_out <- file.path(study, "by_index", "UHR", "Liling")
config$project$output_dir <- lil_out
# 清旧图
unlink(list.files(lil_out, pattern = "Figure 3|Figure S3", full.names = TRUE, recursive = TRUE))
pl <- pipeline
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
cli::cli_h2("补跑 Liling only=subgroup+mediation")
run_pipeline(
  root, config = config, pipeline = pl,
  run_opts = list(
    from = "logistic_quartile_glm_rcs",
    only = c("subgroup_incidence", "mediation_incidence")
  )
)

cli::cli_alert_success("三库亚组/中介补跑完成")
