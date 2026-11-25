#!/usr/bin/env Rscript
# eICU GAR: mapped 有 GAR+CRRT，index_exposure/插补后 GAR 丢失导致主事件=0。
# 从 analysis_exclusion 续跑：先跑 index_exposure，再用 mapped GAR 回填 NA，重建四分位，
# 然后轨迹→模型→supp→pub，rename success。
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
base <- config$study_batch$output_base
unit_dir <- file.path(base, "by_unit", paste0("\u3010success\u3011", unit))
if (!dir.exists(unit_dir)) unit_dir <- file.path(base, "by_unit", unit)
stopifnot(dir.exists(unit_dir))
ck_dir <- file.path(unit_dir, "checkpoints")

ctx <- study_batch_load_checkpoint_ctx(ck_dir, "analysis_exclusion")
if (is.null(ctx)) stop("need analysis_exclusion checkpoint")
ctx$config <- config
ctx$config$competing_risk$index_var <- unit
ctx$config$competing_risk$age_cutoff <- 65L
# 外验交付：禁止因轨迹基线 P≥0.05 早停（主分析仍以 CRRT Fine-Gray 为准）
ctx$config$competing_risk$early_stop_if_index_ns <- FALSE
ctx$config$project$output_dir <- unit_dir
ctx$config$project$root <- root
ctx$config$project$database <- "eICU"

id_col <- as.character(ctx$config$data$id_column %||% "ID")[1L]

.restore_gar_from_mapped <- function(ctx, id_col, index_var = "GAR") {
  m <- ctx$data$mapped
  if (is.null(m) || !index_var %in% names(m)) {
    message("mapped 无 ", index_var, "，跳过回填")
    return(ctx)
  }
  map_df <- m[, c(id_col, index_var), drop = FALSE]
  names(map_df)[2] <- ".gar_src"
  map_df[[id_col]] <- as.character(map_df[[id_col]])
  for (slot in c("cleaned", "raw", "imputed", "mapped")) {
    d <- ctx$data[[slot]]
    if (is.null(d)) next
    d[[id_col]] <- as.character(d[[id_col]])
    na0 <- sum(is.na(d[[index_var]]))
    d <- merge(d, map_df, by = id_col, all.x = TRUE, sort = FALSE)
    fill <- is.na(d[[index_var]]) & !is.na(d[[".gar_src"]])
    d[[index_var]][fill] <- d[[".gar_src"]][fill]
    d[[".gar_src"]] <- NULL
    # rebuild quartile on non-NA
    qcol <- paste0(index_var, "_quartile")
    x <- d[[index_var]]
    ok <- is.finite(x)
    d[[qcol]] <- NA_character_
    if (sum(ok) >= 4L) {
      br <- unique(as.numeric(stats::quantile(x[ok], probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE, type = 7)))
      if (length(br) >= 3L) {
        d[[qcol]][ok] <- as.character(cut(x[ok], breaks = br, include.lowest = TRUE, labels = paste0("Q", seq_len(length(br) - 1L))))
        # force Q1-Q4 labels if 4 bins
        if (length(br) == 5L) {
          d[[qcol]][ok] <- as.character(cut(x[ok], breaks = br, include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4")))
        }
      }
    }
    ctx$data[[slot]] <- d
    st <- if ("competing_status_28d" %in% names(d)) {
      paste(capture.output(print(table(GAR_na = is.na(d[[index_var]]), status = d$competing_status_28d, useNA = "ifany"))), collapse = "\n")
    } else ""
    message(sprintf("[%s] GAR NA %s -> %s; CRRT among non-NA=%s\n%s",
                    slot, na0, sum(is.na(d[[index_var]])),
                    if ("competing_status_28d" %in% names(d)) sum(!is.na(d[[index_var]]) & d$competing_status_28d == 1L, na.rm = TRUE) else "NA",
                    st))
  }
  ctx
}

for (f in c(
  "Blocks/55_competing_risk/13block_competing_index_exposure.R",
  "Blocks/55_competing_risk/20block_competing_trajectory_cluster.R",
  "Blocks/55_competing_risk/17block_competing_flowchart.R",
  "Blocks/55_competing_risk/14block_competing_baseline_quartile.R",
  "Blocks/55_competing_risk/02block_competing_lmm_trajectory.R",
  "Blocks/55_competing_risk/15block_competing_baseline_trajectory.R",
  "Blocks/55_competing_risk/03block_competing_finegray.R",
  "Blocks/55_competing_risk/07block_competing_mixed_cox.R",
  "Blocks/55_competing_risk/09block_competing_models_123.R",
  "Blocks/55_competing_risk/16block_competing_models_123_death.R",
  "Blocks/55_competing_risk/10block_competing_stratified.R",
  "Blocks/55_competing_risk/05block_competing_rcs.R",
  "Blocks/55_competing_risk/06block_competing_cif_plot.R",
  "Blocks/55_competing_risk/11block_competing_cox_sensitivity.R",
  "Blocks/55_competing_risk/12block_competing_ph_calibration.R",
  "Blocks/55_competing_risk/19block_competing_supp_tables.R",
  "Blocks/55_competing_risk/18block_competing_pub_export.R",
  "R/competing_supp_fit.R", "R/competing_supp_xlsx.R", "R/competing_risk_pub.R",
  "R/pub_figure_export.R", "R/pub_xlsx_surgical.R"
)) if (file.exists(f)) try(source(f, local = FALSE), silent = TRUE)

# 1) index exposure (may wipe GAR) then restore from mapped
blocks1 <- c("competing_index_exposure")
unlink(list.files(ck_dir, pattern = "competing_index_exposure\\.rds$", full.names = TRUE))
pl1 <- list(name = "gar_eicu_idx", blocks = blocks1, checkpoint = list(enable = TRUE, dir = ck_dir))
message(">>> index_exposure")
ctx <- run_pipeline(root, config = ctx$config, pipeline = pl1, run_opts = list(initial_ctx = ctx))
message(">>> restore GAR from mapped")
ctx <- .restore_gar_from_mapped(ctx, id_col, unit)

# 2) rest of unit pipeline（含 UV/LASSO/RF，因分析集人数变了）
blocks2 <- c(
  "competing_trajectory_cluster",
  "competing_flowchart",
  "competing_baseline_quartile",
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
# clear checkpoints for these so they re-run
for (b in blocks2) {
  unlink(list.files(ck_dir, pattern = paste0("(", b, "|step[0-9]+_", b, ")\\.rds$"), full.names = TRUE))
}

pl2 <- list(name = "gar_eicu_repair", blocks = blocks2, checkpoint = list(enable = TRUE, dir = ck_dir))
message(">>> repair pipeline (", length(blocks2), " blocks)")
ctx2 <- run_pipeline(root, config = ctx$config, pipeline = pl2, run_opts = list(initial_ctx = ctx))

# Lai S1–S6 rename + prune (same as polish)
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
  system2("python3", c(scrub, shQuote(f), "--times-only"))
}

st <- list(unit = unit, index = unit, status = "success", db_mode = "eICU",
           error_message = "repaired: restored GAR from mapped after index_exposure",
           finished_at = as.character(Sys.time()))
jsonlite::write_json(st, file.path(unit_dir, "_batch_status.json"), auto_unbox = TRUE, pretty = TRUE)

success_dir <- file.path(dirname(unit_dir), paste0("\u3010success\u3011", unit))
if (!grepl("success", basename(unit_dir)) && !dir.exists(success_dir)) {
  file.rename(unit_dir, success_dir)
  unit_dir <- success_dir
}
message("DONE repair eICU GAR")
print(list.files(file.path(unit_dir, "Tables"), pattern = "\\.xlsx$"))
