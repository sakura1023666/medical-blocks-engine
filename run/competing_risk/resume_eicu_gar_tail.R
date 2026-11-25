#!/usr/bin/env Rscript
# Resume eICU GAR from competing_cox_sensitivity → ph_cal → supp → pub_export
root <- "/mnt/e/01block/01Block-new-Final"
setwd(root)
options(warn = 1)
source("R/utils.R")
source("R/mi_rubin_pool.R")
source("R/pipeline_runner.R")
source("R/study_batch_runner.R")
source("configs/indices/composite_index_vars.R")

cfg_path <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d/config_competing_risk_aki_crrt_eicu.R"
sys.source(cfg_path, envir = environment())
unit <- "GAR"
unit_dir <- file.path(config$study_batch$output_base, "by_unit", unit)
if (!dir.exists(unit_dir)) {
  alt <- file.path(config$study_batch$output_base, "by_unit", paste0("\u3010success\u3011", unit))
  if (dir.exists(alt)) unit_dir <- alt else stop("missing unit dir")
}
ck_dir <- file.path(unit_dir, "checkpoints")
message("unit_dir=", unit_dir)

ctx <- tryCatch(study_batch_load_checkpoint_ctx(ck_dir, "competing_cox_sensitivity"), error = function(e) NULL)
if (is.null(ctx)) {
  ctx <- tryCatch(study_batch_load_checkpoint_ctx(ck_dir, "competing_cif_plot"), error = function(e) NULL)
}
if (is.null(ctx)) stop("no checkpoint to resume")
message("loaded checkpoint OK; n=", nrow(ctx$data$imputed %||% data.frame()))

ctx$config <- config
ctx$config$competing_risk$index_var <- unit
ctx$config$competing_risk$age_cutoff <- 65L
ctx$config$project$output_dir <- unit_dir
ctx$config$project$root <- root
ctx$config$project$database <- "eICU"

for (f in c(
  "Blocks/55_competing_risk/12block_competing_ph_calibration.R",
  "Blocks/55_competing_risk/19block_competing_supp_tables.R",
  "Blocks/55_competing_risk/18block_competing_pub_export.R",
  "Blocks/55_competing_risk/14block_competing_baseline_quartile.R",
  "Blocks/55_competing_risk/15block_competing_baseline_trajectory.R",
  "R/competing_supp_fit.R", "R/competing_supp_xlsx.R", "R/competing_risk_pub.R",
  "R/pub_figure_export.R", "R/dual_db_combine_figures.R", "R/pub_xlsx_surgical.R"
)) {
  if (file.exists(f)) try(source(f, local = FALSE), silent = TRUE)
}

blocks_needed <- c("competing_ph_calibration", "competing_supp_tables", "competing_pub_export")
for (b in blocks_needed) {
  unlink(list.files(ck_dir, pattern = paste0(b, "\\.rds$"), full.names = TRUE))
}

pl <- list(
  name = "gar_eicu_tail",
  blocks = blocks_needed,
  checkpoint = list(enable = TRUE, dir = ck_dir)
)
message(">>> run_pipeline")
ctx2 <- run_pipeline(root, config = ctx$config, pipeline = pl, run_opts = list(initial_ctx = ctx))

st <- list(
  unit = unit, index = unit, status = "success", db_mode = "eICU",
  error_message = "", finished_at = as.character(Sys.time())
)
jsonlite::write_json(st, file.path(unit_dir, "_batch_status.json"), auto_unbox = TRUE, pretty = TRUE)

success_dir <- file.path(dirname(unit_dir), paste0("\u3010success\u3011", unit))
if (!grepl("success", basename(unit_dir)) && !dir.exists(success_dir)) {
  file.rename(unit_dir, success_dir)
  message("renamed -> ", success_dir)
  unit_dir <- success_dir
}
message("DONE eICU GAR; tables:")
print(list.files(file.path(unit_dir, "Tables"), pattern = "\\.xlsx$"))
