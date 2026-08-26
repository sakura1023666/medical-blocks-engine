#!/usr/bin/env Rscript
# 三库中介重跑：无协变量；best=Hematocrit；排除 UHR 组分；刷新 summary S3/S6
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
best_med <- "Hematocrit"
uhr_comps <- c("Uric_Acid", "UricAcid", "Uric Acid", "HDL", "HDL_C", "HDL-C")
dual_dir <- file.path(study, "by_index", "【success】UHR")
meds <- c("BUN", "Creatinine", "Hematocrit", "Platelet_Count",
          "Total_Cholesterol", "Triglycerides", "WBC")
covs <- character(0)  # 不加协变量

# 强制 preferred，避免旧 Triglycerides 覆盖
pref_path <- file.path(study, "checkpoints/_global_harmonization/preferred_mediator.rds")
dir.create(dirname(pref_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(mediator = best_med, saved_at = Sys.time()), pref_path)
dual_db_save_preferred_mediator(
  study,
  list(dual_db = list(enable = TRUE), project = list(root = study)),
  best_med
)

.strip_uhr_comps_xlsx <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE) || !file.exists(path)) return(invisible(FALSE))
  wb <- openxlsx::loadWorkbook(path)
  sh <- names(wb)[1]
  v <- openxlsx::read.xlsx(path, sheet = 1, colNames = FALSE)
  if (!nrow(v)) return(invisible(FALSE))
  keep <- vapply(seq_len(nrow(v)), function(i) {
    nm <- as.character(v[i, 1] %||% "")
    !any(tolower(gsub("[_-]", " ", nm)) %in% tolower(gsub("[_-]", " ", uhr_comps)))
  }, logical(1))
  if (!all(keep)) {
    v <- v[keep, , drop = FALSE]
    openxlsx::writeData(wb, sh, v, startCol = 1, startRow = 1, colNames = FALSE)
  }
  if (nrow(v) >= 1 && grepl("^Table S[0-9]+", as.character(v[1, 1] %||% ""))) {
    openxlsx::writeData(wb, sh, sub("^Table S[0-9]+", "Table S6", as.character(v[1, 1])),
                        startCol = 1, startRow = 1, colNames = FALSE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(TRUE)
}

.apply_med_cfg <- function(cfg) {
  cfg$mediation_nhanes_weighted$best_mediator <- best_med
  cfg$mediation_nhanes_weighted$mediators <- meds
  cfg$mediation_nhanes_weighted$lab_indicator_vars <- meds
  cfg$mediation_nhanes_weighted$covariates <- covs
  cfg$mediation_nhanes_weighted$auto_covariate_search <- FALSE
  cfg$mediation_incidence$best_mediator <- best_med
  cfg$mediation_incidence$mediators <- meds
  cfg$mediation_incidence$covariates <- covs
  cfg$mediation_incidence$auto_covariate_search <- FALSE
  cfg
}

# ── Dual ────────────────────────────────────────────────────────────────────
source(file.path(study, "config_incidence_dual_batch.R"))
config$incidence_batch$sensitivity_suite$enable <- FALSE
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config <- .apply_med_cfg(config)

for (db in c("nhanes", "mimic")) {
  cfg_db <- incidence_batch_apply_db_overrides(config, db, root, ix)
  cfg_db <- .apply_med_cfg(cfg_db)
  out_db <- file.path(dual_dir, dual_db_slot_path_name(cfg_db, db))
  cfg_db$project$output_dir <- out_db
  unlink(list.files(out_db, pattern = "Figure S3|mediation by laboratory",
                    recursive = TRUE, full.names = TRUE))
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
  pl$checkpoint$dir <- file.path(study, "checkpoints", "by_index", ix,
                                 dual_db_slot_path_name(config, db))
  cli::cli_h2("中介无协变量 [{toupper(db)}]")
  run_pipeline(root, config = cfg_db, pipeline = pl,
               run_opts = list(from = from_tok, only = only_blks))
  cat("preferred:", dual_db_load_preferred_mediator(
    study, list(dual_db = list(enable = TRUE), project = list(root = study))), "\n")
}

# ── Liling ──────────────────────────────────────────────────────────────────
cli::cli_h2("中介无协变量 [LILING]")
source(file.path(study, "config_incidence_liling.R"))
config$project$output_dir <- file.path(dual_dir, "Liling")
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config <- .apply_med_cfg(config)
unlink(list.files(file.path(dual_dir, "Liling"),
                  pattern = "Figure S3|mediation by laboratory",
                  recursive = TRUE, full.names = TRUE))
pipeline$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
from_tok <- if (file.exists(file.path(pipeline$checkpoint$dir, "subgroup_incidence.rds"))) {
  "subgroup_incidence"
} else {
  "logistic_binary_glm_rcs"
}
run_pipeline(root, config = config, pipeline = pipeline,
             run_opts = list(from = from_tok, only = "mediation_incidence"))

# ── summary ─────────────────────────────────────────────────────────────────
sum_fig <- file.path(study, "summary_result", "figure")
sum_tab <- file.path(study, "summary_result", "table")
dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(sum_fig, pattern = "Figure S3", full.names = TRUE))
unlink(list.files(sum_tab, pattern = "mediation by laboratory", full.names = TRUE))

for (db in c("NHANES", "CHARLS", "Liling")) {
  tabs <- list.files(file.path(dual_dir, db, "Tables"),
                     pattern = "mediation by laboratory.*\\.xlsx$", full.names = TRUE)
  for (t in tabs) .strip_uhr_comps_xlsx(t)

  figs <- list.files(file.path(dual_dir, db, "Figures"),
                     pattern = "^Figure S3", full.names = TRUE)
  figs <- figs[order(file.info(figs)$mtime, decreasing = TRUE)]
  if (length(figs)) {
    file.copy(figs[[1]], file.path(sum_fig, basename(figs[[1]])), overwrite = TRUE)
    cli::cli_alert_success("fig <- {basename(figs[[1]])}")
  }
  tabs <- tabs[order(file.info(tabs)$mtime, decreasing = TRUE)]
  if (length(tabs)) {
    bn <- sub("^Table S[0-9]+", "Table S6", basename(tabs[[1]]))
    dest <- file.path(sum_tab, bn)
    file.copy(tabs[[1]], dest, overwrite = TRUE)
    .strip_uhr_comps_xlsx(dest)
    if (!identical(basename(tabs[[1]]), bn)) {
      file.rename(tabs[[1]], file.path(dirname(tabs[[1]]), bn))
    }
    cli::cli_alert_success("tab <- {bn}")
  }
}

cli::cli_alert_success("完成：中介无协变量；best={best_med}")
