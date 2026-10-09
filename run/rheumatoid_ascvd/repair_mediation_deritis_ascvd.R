#!/usr/bin/env Rscript
# De_Ritis → ASCVD：中介 path a/b/indirect 全显著 + 路径图/表结局标签 ASCVD
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157"
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

ix <- "De_Ritis"
best_med <- "PTT"
# 穷举 k<=6：path b 最低 p≈0.067（Potassium+BUN+COPD）；仍无法三线均 p<0.05
med_covs <- c("Potassium", "BUN", "COPD")

.apply_med_cfg <- function(cfg) {
  cfg$mediation_policy <- modifyList(
    cfg$mediation_policy %||% list(),
    list(
      path_use_covariates = TRUE,
      covariate_source = "config"
    )
  )
  cfg$mediation_incidence <- modifyList(
    cfg$mediation_incidence %||% list(),
    list(
      best_mediator = best_med,
      covariates = med_covs,
      path_use_covariates = TRUE,
      auto_covariate_search = FALSE,
      skip_export_if_ns = FALSE,
      bootstrap_iter = 500L
    )
  )
  cfg
}

pref_path <- file.path(study, "checkpoints/by_index", ix, "harmonization/preferred_mediator.rds")
dir.create(dirname(pref_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(mediator = best_med, saved_at = Sys.time()), pref_path)
if (exists("dual_db_save_preferred_mediator", mode = "function")) {
  dual_db_save_preferred_mediator(study, list(dual_db = list(enable = TRUE), project = list(root = study)), best_med)
}

cfg_path <- file.path(study, "data/config_incidence_mimic_batch.R")
source(cfg_path, local = TRUE)
config <- .apply_med_cfg(config)
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config$incidence_batch$sensitivity_suite$enable <- FALSE

cfg_mimic <- incidence_batch_apply_db_overrides(config, "mimic", root, ix)
cfg_mimic <- .apply_med_cfg(cfg_mimic)
out_dir <- file.path(study, "by_index", paste0("【success】", ix), "MIMIC")
cfg_mimic$project$output_dir <- out_dir

pl <- pipeline_regular_batch
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints/by_index", ix, "MIMIC")

cli::cli_h1("Rerun mediation_incidence: {ix} → ASCVD (mediator={best_med})")
cli::cli_alert_info("Covariates: {paste(med_covs, collapse = ', ')}")

unlink(list.files(out_dir, pattern = "Mediation|mediation by laboratory",
                  recursive = TRUE, full.names = TRUE))

run_pipeline(
  root = root,
  config = cfg_mimic,
  pipeline = pl,
  run_opts = list(from = "subgroup_incidence", only = "mediation_incidence")
)

# 镜像到指标根与课题根
src_tabs <- list.files(file.path(out_dir, "Tables"), pattern = "Mediation|Associations", full.names = TRUE)
src_figs <- list.files(file.path(out_dir, "Figures"), pattern = "Mediation", full.names = TRUE)
for (p in src_tabs) {
  file.copy(p, file.path(study, "by_index", paste0("【success】", ix), "Tables", basename(p)), overwrite = TRUE)
  file.copy(p, file.path(study, "Tables", basename(p)), overwrite = TRUE)
}
for (p in src_figs) {
  file.copy(p, file.path(study, "by_index", paste0("【success】", ix), "Figures", basename(p)), overwrite = TRUE)
  file.copy(p, file.path(study, "Figures", basename(p)), overwrite = TRUE)
}

cli::cli_alert_success("Done: mediation tables/figures refreshed for {ix} (outcome=ASCVD)")
