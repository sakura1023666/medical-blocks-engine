#!/usr/bin/env Rscript
# Continue eICU GAR repair after Table1 OK; early_stop off from baseline_trajectory
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
unit_dir <- file.path(config$study_batch$output_base, "by_unit", paste0("\u3010success\u3011", unit))
ck_dir <- file.path(unit_dir, "checkpoints")
ctx <- study_batch_load_checkpoint_ctx(ck_dir, "competing_baseline_quartile")
if (is.null(ctx)) stop("missing baseline_quartile ck")
ctx$config <- config
ctx$config$competing_risk$index_var <- unit
ctx$config$competing_risk$age_cutoff <- 65L
ctx$config$competing_risk$early_stop_if_index_ns <- FALSE
ctx$config$project$output_dir <- unit_dir
ctx$config$project$root <- root
ctx$config$project$database <- "eICU"

# verify GAR/CRRT still present
d <- ctx$data$imputed
message(sprintf("imputed n=%s GAR nonNA=%s CRRT among them=%s",
                nrow(d), sum(!is.na(d$GAR)),
                sum(!is.na(d$GAR) & d$competing_status_28d == 1L, na.rm = TRUE)))

blocks2 <- c(
  "competing_lmm_trajectory",
  "competing_baseline_trajectory",
  "univariate_prognosis",
  "feature_selection_lasso",
  "feature_selection_random_forest",
  "competing_finegray",
  "competing_mixed_cox",
  "competing_models_123",
  "competing_models_123_death",
  "competing_stratified",
  "competing_rcs",
  "competing_cif_plot",
  "competing_cox_sensitivity",
  "competing_ph_calibration",
  "competing_supp_tables",
  "competing_pub_export"
)
for (b in blocks2) {
  unlink(list.files(ck_dir, pattern = paste0("(", b, "|step[0-9]+_", b, ")\\.rds$"), full.names = TRUE))
}

pl2 <- list(name = "gar_eicu_continue", blocks = blocks2, checkpoint = list(enable = TRUE, dir = ck_dir))
message(">>> continue ", length(blocks2), " blocks")
ctx2 <- run_pipeline(root, config = ctx$config, pipeline = pl2, run_opts = list(initial_ctx = ctx))

tab_dir <- file.path(unit_dir, "Tables")
fig_dir <- file.path(unit_dir, "Figures")
role_moves <- c(
  "Subgroup analysis by quartile" = "Table S1-eICU. Subgroup analysis by quartile.xlsx",
  "Standard Cox by quartile \\(sensitivity\\)" = "Table S2-eICU. Standard Cox by quartile (sensitivity).xlsx",
  "Competing-risk Cox sensitivity \\(extremes handled\\)" = "Table S3-eICU. Competing-risk Cox sensitivity (extremes handled).xlsx",
  "Standard Cox sensitivity \\(extremes handled\\)" = "Table S4-eICU. Standard Cox sensitivity (extremes handled).xlsx",
  "Subgroup analysis by trajectory" = "Table S5-eICU. Subgroup analysis by trajectory.xlsx",
  "Standard Cox by trajectory" = "Table S6-eICU. Standard Cox by trajectory.xlsx"
)
fs <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
for (pat in names(role_moves)) {
  hit <- fs[grepl(pat, basename(fs), perl = TRUE) & grepl("-eICU\\.", basename(fs))]
  if (!length(hit)) next
  dest <- file.path(tab_dir, role_moves[[pat]])
  if (!identical(normalizePath(hit[1], mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) {
    if (file.exists(dest) && !identical(hit[1], dest)) unlink(dest)
    file.rename(hit[1], dest)
  }
}
ws <- file.path(dirname(unit_dir), paste0(basename(unit_dir), "_delivery_workspace"), "Tables_internal")
dir.create(ws, recursive = TRUE, showWarnings = FALSE)
keep_re <- "^(Table [1-4]-eICU\\.|Table S[1-6]-eICU\\.)"
for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
  if (!grepl(keep_re, basename(f), perl = TRUE)) {
    dest <- file.path(ws, basename(f))
    if (file.exists(dest)) unlink(dest)
    file.rename(f, dest)
  }
}
.purge_fig <- function(dir) {
  if (!dir.exists(dir)) return(invisible(NULL))
  fs <- list.files(dir, full.names = TRUE, recursive = FALSE)
  bn <- basename(fs)
  drop <- grepl("(?i)(^Figure\\s*S|Missing|Lasso|Random\\s*forest|S2[A-G]\\.)", bn, perl = TRUE)
  drop <- drop | (grepl("(?i)\\.pdf$", bn) & !grepl("^Figure [0-9]+-", bn) & !dir.exists(fs))
  if (any(drop)) unlink(fs[drop])
}
.purge_fig(fig_dir); .purge_fig(file.path(fig_dir, "pdf")); .purge_fig(file.path(fig_dir, "image_information"))
if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
  try(pub_sync_xlsx_a1_titles_to_filenames(tab_dir), silent = TRUE)
}
scrub <- file.path(root, "python/pub_xlsx_scrub_display.py")
for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
  system2("python3", c(shQuote(scrub), shQuote(f), "--times-only"))
}

st <- list(unit = unit, index = unit, status = "success", db_mode = "eICU",
           error_message = "repaired: GAR restored from mapped; early_stop off for ext val",
           finished_at = as.character(Sys.time()))
jsonlite::write_json(st, file.path(unit_dir, "_batch_status.json"), auto_unbox = TRUE, pretty = TRUE)
message("DONE continue eICU GAR")
print(list.files(tab_dir, pattern = "\\.xlsx$"))
