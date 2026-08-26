#!/usr/bin/env Rscript
# 听力损失 UHR：按三库单因素 VIF 交集锁定 Model2，跳过多因素/最终 VIF，重跑 logistic+RCS+亚组+中介
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

lock <- jsonlite::fromJSON(file.path(study, "data/harmonized/covariate_lock.json"))
m1 <- as.character(lock$model1)
m2 <- as.character(lock$model2)
lock_sg <- c("Age_Group", "Gender", "Marital_Status", "Hypertension")
ix <- "UHR"
dual_dir <- file.path(study, "by_index", "【success】UHR")
if (!dir.exists(dual_dir)) dual_dir <- file.path(study, "by_index", "UHR")
stopifnot(dir.exists(dual_dir))

cli::cli_alert_info("Model1={paste(m1, collapse=',')} | Model2={paste(m2, collapse=',')}")

# 删除旧多因素/最终 VIF 表，避免编号错位
drop_old_s56 <- function(tab_dir) {
  if (!dir.exists(tab_dir)) return(invisible())
  old <- list.files(
    tab_dir,
    pattern = "Table S5-.*Multivariable|Table S6-.*multivariate|Table S6-.*Multicollinearity Analysis \\(VIF, multivariate",
    full.names = TRUE, ignore.case = TRUE
  )
  if (length(old)) {
    unlink(old)
    cli::cli_alert_info("dropped {length(old)} old S5/S6 under {tab_dir}")
  }
}

force_lock_cfg <- function(cfg) {
  cfg$logistic$model1_factors <- m1
  cfg$logistic$model2_factors <- m2
  cfg$logistic$model2_max_covariates <- 20L
  for (nm in c(
    "logistic_nhanes_weighted",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted"
  )) {
    if (!is.null(cfg[[nm]])) {
      cfg[[nm]]$model1_factors <- m1
      cfg[[nm]]$model2_factors <- m2
      if (!is.null(cfg[[nm]]$random_search)) {
        cfg[[nm]]$random_search$enable <- FALSE
        cfg[[nm]]$random_search$max_attempts <- 1L
        cfg[[nm]]$random_search$max_outer_attempts <- 1L
      }
    }
  }
  if (!is.null(cfg$logistic_quartile_nhanes_weighted)) {
    cfg$logistic_quartile_nhanes_weighted$gate_enable <- FALSE
    cfg$logistic_quartile_nhanes_weighted$extend_branch <- "extend_quartile"
  }
  if (!is.null(cfg$dual_db$harmonization)) {
    cfg$dual_db$harmonization$lock_covariates_preset <- TRUE
    cfg$dual_db$harmonization$covariate_source <- "vif_screen"
    cfg$dual_db$harmonization$sync_after_vif_final <- FALSE
    cfg$dual_db$harmonization$harmonized_model1_nhanes <- m1
    cfg$dual_db$harmonization$harmonized_model2_nhanes <- m2
    cfg$dual_db$harmonization$harmonized_model1_mimic <- m1
    cfg$dual_db$harmonization$harmonized_model2_mimic <- m2
    cfg$dual_db$harmonization$common_model_factors <- as.character(lock$common_model_factors)
  }
  cfg$subgroup$var_source <- "required"
  cfg$subgroup$locked_subgroup_vars <- lock_sg
  cfg$subgroup$required_subgroup_vars <- lock_sg
  cfg$mediation_nhanes_weighted$best_mediator <- "Triglycerides"
  cfg$mediation_incidence$best_mediator <- "Triglycerides"
  cfg$mediation_nhanes_weighted$covariates <- m1
  cfg$mediation_incidence$covariates <- m1
  cfg$incidence$index_var <- ix
  cfg$logistic$index_var <- ix
  if (!is.null(cfg$prediction)) cfg$prediction$index_vars <- ix
  cfg
}

# ── Dual NHANES + CHARLS ────────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config$incidence_batch$output_base <- study
config$incidence_batch$sensitivity_suite$enable <- FALSE
config$project$root <- study
config <- force_lock_cfg(config)

harm_dir <- file.path(study, "checkpoints", "_global_harmonization")
dir.create(harm_dir, recursive = TRUE, showWarnings = FALSE)
dual_db_save_preferred_mediator(study, config, "Triglycerides")
saveRDS(
  list(vars = lock_sg, eligible_by_db = list(nhanes = lock_sg, mimic = lock_sg), saved_at = Sys.time()),
  file.path(harm_dir, "gate_d_subgroup_vars.rds")
)

rerun_dual_db <- function(db) {
  cfg_db <- force_lock_cfg(incidence_batch_apply_db_overrides(config, db, root, ix))
  out_db <- file.path(dual_dir, dual_db_slot_path_name(cfg_db, db))
  cfg_db$project$output_dir <- out_db
  drop_old_s56(file.path(out_db, "Tables"))

  if (dual_db_is_weighted(config, db)) {
    pl <- pipeline_nhanes_batch
    # from = 某步「之后」续跑；要真正执行 dual_db_covariate_harmonize，须 from=其前一步
    from_tok <- "multicollinearity_nhanes_screen"
    only_blks <- c(
      "dual_db_covariate_harmonize",
      "logistic_quartile_nhanes_weighted",
      "logistic_tertile_nhanes_weighted",
      "logistic_binary_nhanes_weighted",
      "dual_db_logistic_scheme_harmonize",
      "dual_db_logistic_main_table_realign",
      "rcs_nhanes",
      "logistic_quartile_nhanes_weighted_rcs",
      "logistic_tertile_nhanes_weighted_rcs",
      "logistic_binary_nhanes_weighted_rcs",
      "subgroup_nhanes_weighted",
      "mediation_nhanes_weighted"
    )
  } else {
    pl <- pipeline_regular_batch
    from_tok <- "multicollinearity_screen"
    only_blks <- c(
      "dual_db_covariate_harmonize",
      "logistic_quartile_glm",
      "logistic_tertile_glm",
      "logistic_binary_glm",
      "dual_db_logistic_scheme_harmonize",
      "dual_db_logistic_main_table_realign",
      "rcs_incidence",
      "logistic_quartile_glm_rcs",
      "logistic_tertile_glm_rcs",
      "logistic_binary_glm_rcs",
      "subgroup_incidence",
      "mediation_incidence"
    )
  }
  ck_dir <- file.path(study, "checkpoints", "by_index", ix, dual_db_slot_path_name(config, db))
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- ck_dir
  cli::cli_h2("补跑 dual [{toupper(db)}] logistic+RCS+SG+med from={from_tok}")
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
rm(list = intersect(c("pipeline_nhanes_batch", "pipeline_regular_batch", "pipeline", "config"), ls(envir = .GlobalEnv)),
   envir = .GlobalEnv)
source(lil_cfg)
config <- force_lock_cfg(config)
lil_out <- if (dir.exists(file.path(dual_dir, "Liling"))) {
  file.path(dual_dir, "Liling")
} else {
  file.path(study, "by_index", "UHR", "Liling")
}
config$project$output_dir <- lil_out
drop_old_s56(file.path(lil_out, "Tables"))
pl <- pipeline
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
cli::cli_h2("补跑 Liling logistic+RCS+SG+med")
run_pipeline(
  root, config = config, pipeline = pl,
  run_opts = list(
    # from=前一步，才能真正执行 logistic_quartile_glm
    from = "multicollinearity_screen",
    only = c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "rcs_incidence",
      "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
      "subgroup_incidence", "mediation_incidence"
    )
  )
)

cli::cli_alert_success("三库 logistic（单因素 VIF 交集协变量）补跑完成")
