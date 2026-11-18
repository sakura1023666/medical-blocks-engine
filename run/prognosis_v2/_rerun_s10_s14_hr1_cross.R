#!/usr/bin/env Rscript
# One-off / trial: binary cut = Model 1 RCS nearest HR=1 crossing (around 7.5 h).
# Backs up current Model1-min CSVs as *.model1_min.bak.csv, then re-runs extension
# with PV2_RCS_CUT_MODE=model1_hr1 (S9–S14; S10/S12–S14 use HR=1 cut).
suppressPackageStartupMessages({
  library(data.table); library(survival); library(survey); library(pROC)
})
engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else {
  "E:/01block/01Block-new-Final"
}
Sys.setenv(
  MEDICAL_BLOCKS_ROOT = engine,
  PV2_PROFILE = "sleep_dyslipidemia",
  PV2_RCS_CUT_MODE = "model1_hr1"
)
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")

.message_cut_table <- function() {
  p <- file.path(pv2_ckpt_dir, "Table S10. RCS cutoffs.csv")
  if (!file.exists(p)) {
    message("no live S10 cutoffs yet")
    return(invisible(NULL))
  }
  cut <- data.table::fread(p, data.table = FALSE)
  message("==== Table S10. RCS cutoffs (min_risk vs nearest_HR1) ====")
  print(cut)
  m1 <- cut[cut$model == "Model 1", , drop = FALSE]
  for (i in seq_len(nrow(m1))) {
    message(sprintf(
      "  %s Model1: min_risk=%.3f  nearest_HR1=%s",
      m1$database[i], m1$min_risk_hours[i],
      ifelse(is.finite(m1$nearest_HR1_hours[i]), sprintf("%.3f", m1$nearest_HR1_hours[i]), "NA")
    ))
  }
  invisible(cut)
}

.ws_latest <- function() {
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  if (!dir.exists(ws)) return(NA_character_)
  stamps <- list.dirs(ws, full.names = TRUE, recursive = FALSE)
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(file.path(stamps, "checkpoints"), stamps)) {
    if (file.exists(file.path(d, "imputed_dbs.rds"))) return(d)
  }
  NA_character_
}

# Restore imputed artifacts if missing
need <- c("imputed_dbs.rds", "imputed_mids.rds", "Covariate_selection_note.txt")
miss <- need[!file.exists(file.path(pv2_ckpt_dir, need))]
if (length(miss)) {
  w <- .ws_latest()
  if (is.na(w)) stop("missing artifacts and no delivery_workspace: ", paste(miss, collapse = ", "))
  for (f in miss) {
    src <- file.path(w, f)
    if (!file.exists(src)) src <- file.path(dirname(w), "checkpoints", f)
    if (!file.exists(src)) stop("cannot restore ", f)
    file.copy(src, file.path(pv2_ckpt_dir, f), overwrite = TRUE)
    message("restored ", f, " from ", src)
  }
}

# Backup current Model1-min results before overwrite
.bak_pairs <- c(
  "Table S10. RCS cutoff Cox.csv" = "Table S10. RCS cutoff Cox.model1_min.bak.csv",
  "Table S12. RCS cutoff Cox PAR.csv" = "Table S12. RCS cutoff Cox PAR.model1_min.bak.csv",
  "Table S13. RCS cutoff diagnostic.csv" = "Table S13. RCS cutoff diagnostic.model1_min.bak.csv",
  "Table S14. RCS cutoff joint strata.csv" = "Table S14. RCS cutoff joint strata.model1_min.bak.csv"
)
for (src_nm in names(.bak_pairs)) {
  src <- file.path(pv2_ckpt_dir, src_nm)
  dst <- file.path(pv2_ckpt_dir, .bak_pairs[[src_nm]])
  if (file.exists(src)) {
    # Only write bak once if bak already exists and looks like min-risk (keep first bak)
    if (!file.exists(dst)) {
      file.copy(src, dst, overwrite = FALSE)
      message("backed up ", src_nm, " -> ", basename(dst))
    } else {
      message("bak already exists, keep: ", basename(dst))
    }
  } else {
    message("skip bak (missing): ", src_nm)
  }
}

cut_before <- .message_cut_table()
# Preflight: Model1 nearest_HR1; note fallbacks that extension will apply
if (!is.null(cut_before)) {
  m1 <- cut_before[cut_before$model == "Model 1", , drop = FALSE]
  fb <- m1$database[!is.finite(m1$nearest_HR1_hours)]
  if (length(fb)) {
    message("WILL FALLBACK to Model1 min_risk for: ", paste(fb, collapse = ", "))
  } else {
    message("No Model1 nearest_HR1 NA — all cohorts use HR=1 cross hours")
  }
}

message("==== Extension with PV2_RCS_CUT_MODE=model1_hr1 ====")
source(file.path(engine, "run/prognosis_v2/pv2_mainval_extension.R"), local = FALSE)

cut_df <- data.table::fread(file.path(pv2_ckpt_dir, "Table S10. RCS cutoffs.csv"), data.table = FALSE)
s10 <- data.table::fread(file.path(pv2_ckpt_dir, "Table S10. RCS cutoff Cox.csv"), data.table = FALSE)
s12 <- data.table::fread(file.path(pv2_ckpt_dir, "Table S12. RCS cutoff Cox PAR.csv"), data.table = FALSE)
m1 <- cut_df[cut_df$model == "Model 1", , drop = FALSE]

message("==== cuts used (expect Model1 nearest_HR1, else min_risk fallback) ====")
for (nm in unique(s12$database)) {
  expect_hr1 <- m1$nearest_HR1_hours[m1$database == nm][1]
  expect_min <- m1$min_risk_hours[m1$database == nm][1]
  got <- unique(s12$cutoff_hours[s12$database == nm])[1]
  used <- if (is.finite(expect_hr1) && abs(got - expect_hr1) < 1e-6) {
    "nearest_HR1"
  } else if (is.finite(expect_min) && abs(got - expect_min) < 1e-6) {
    "FALLBACK min_risk"
  } else {
    "UNEXPECTED"
  }
  message(sprintf("  %s: cut=%.3f (%s); min_risk=%.3f nearest_HR1=%s",
                  nm, got, used, expect_min,
                  ifelse(is.finite(expect_hr1), sprintf("%.3f", expect_hr1), "NA")))
}

message("==== Model3 HR/CI/P/PAR (new HR=1 cut) ====")
m3 <- s12[s12$model == "Model3", , drop = FALSE]
for (i in seq_len(nrow(m3))) {
  message(sprintf(
    "  %s: cut=%.3f  HR=%.3f (%.3f–%.3f)  P=%.3f  PAR=%.1f%%",
    m3$database[i], m3$cutoff_hours[i], m3$HR[i], m3$lo[i], m3$hi[i], m3$P[i],
    100 * m3$PAR[i]
  ))
}

# Briefing PDF
build_py <- file.path(engine, "run/prognosis_v2/_build_rcs_briefing_pdf.py")
if (file.exists(build_py)) {
  Sys.setenv(PV2_RCS_CUT_MODE = "model1_hr1")
  st <- system2("python3", shQuote(build_py))
  message("briefing PDF status=", st)
} else {
  message("briefing builder missing: ", build_py)
}
message("ALL DONE model1_hr1-cut")
