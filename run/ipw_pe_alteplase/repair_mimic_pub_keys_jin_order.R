#!/usr/bin/env Rscript
# Repair PE×alteplase MIMIC 【success】main publication keys to match
# Jin + stroke Medication_regimen_model_42118193 checklist.
# - Generate missing Figure S1 (Missing value overview) if absent
# - Restore Fig1–5 / S1–S4 numbering (undo compact renumber that made STEPP Fig6)
# - Curate Tables to T1 + S1–S4 Jin set; also copy Sens Cox / Overlap into Tables/
# - Rename residual "Diabetes HbA1c" captions → Alteplase
# - Refresh pdf/png/tiff/image_information

suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("need ggplot2")
  if (!requireNamespace("naniar", quietly = TRUE)) stop("need naniar")
})

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && is.na(x))) y else x

proj <- "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
if (!dir.exists(proj)) {
  proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
}
unit <- file.path(proj, "by_unit", "\u3010success\u3011main")
stopifnot(dir.exists(unit))

fig_root <- file.path(unit, "Figures")
tbl_root <- file.path(unit, "Tables")
dir.create(file.path(fig_root, "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(tbl_root, recursive = TRUE, showWarnings = FALSE)

.engine <- {
  cands <- c(
    Sys.getenv("BLOCK_REPO_ROOT", ""),
    "E:/01block/01Block-new-Final",
    "/mnt/e/01block/01Block-new-Final"
  )
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  if (!length(hit)) stop("engine root not found")
  hit[[1L]]
}

.fix_diabetes_name <- function(nm) {
  nm2 <- gsub("Diabetes HbA1c", "Alteplase", nm, fixed = TRUE)
  nm2 <- gsub("by Diabetes", "by Alteplase", nm2, fixed = TRUE)
  nm2 <- gsub("IPW diabetes cohort", "IPW alteplase cohort", nm2, fixed = TRUE)
  nm2
}

.copy_pdf <- function(src, dest_bn) {
  dest_bn <- .fix_diabetes_name(dest_bn)
  if (!grepl("\\.pdf$", dest_bn, ignore.case = TRUE)) dest_bn <- paste0(dest_bn, ".pdf")
  dest <- file.path(fig_root, "pdf", dest_bn)
  ok <- file.copy(src, dest, overwrite = TRUE)
  if (!isTRUE(ok)) stop("copy failed: ", src, " -> ", dest)
  cli::cli_alert_success("Figure: {dest_bn}")
  invisible(dest)
}

# ---------------------------------------------------------------------------
# 1) Figure S1 Missing value overview (was never exported: export_missing_fig=FALSE)
# ---------------------------------------------------------------------------
s1_dest <- file.path(fig_root, "pdf", "Figure S1-MIMIC. Missing value overview.pdf")
if (!file.exists(s1_dest)) {
  ck <- file.path(unit, "checkpoints", "imputation.rds")
  stopifnot(file.exists(ck))
  ctx <- readRDS(ck)$ctx
  dat <- ctx$data$mapped %||% ctx$data$cleaned
  stopifnot(is.data.frame(dat), nrow(dat) > 0)
  # drop ID-like / outcome-derived columns with near-zero missing for readability
  drop_pat <- "^(ID|subject_id|stay_id|hadm_id|patientunitstayid|database)$"
  keep <- setdiff(names(dat), names(dat)[grepl(drop_pat, names(dat))])
  data_plot <- dat[, keep, drop = FALSE]
  if (nrow(data_plot) > 5000L) {
    set.seed(1234L)
    data_plot <- data_plot[sample.int(nrow(data_plot), 5000L), , drop = FALSE]
  }
  n_vars <- ncol(data_plot)
  fig_height <- max(6, min(20, nrow(data_plot) / 50))
  fig_width <- max(8, min(30, n_vars * 0.35))
  p <- naniar::vis_miss(data_plot, cluster = FALSE, warn_large_data = FALSE) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5, size = 7)) +
    ggplot2::labs(title = "Missing value overview in MIMIC cohort")
  grDevices::pdf(s1_dest, width = fig_width, height = fig_height)
  print(p)
  grDevices::dev.off()
  cli::cli_alert_success("Generated {basename(s1_dest)}")
} else {
  cli::cli_alert_info("S1 Missing already exists")
}

# ---------------------------------------------------------------------------
# 2) Restore main/supp figures from step folders (correct roles)
# ---------------------------------------------------------------------------
pick_step_fig <- function(step_glob, pattern) {
  dirs <- Sys.glob(file.path(unit, step_glob))
  fs <- unlist(lapply(dirs, function(d) {
    list.files(file.path(d, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  }), use.names = FALSE)
  fs <- fs[grepl(pattern, basename(fs), ignore.case = TRUE)]
  if (!length(fs)) return(NA_character_)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][[1L]]
}

fig_map <- list(
  list(bn = "Figure 1-MIMIC. Flowchart of patient selection (MIMIC, IPW alteplase cohort).pdf",
       src = pick_step_fig("step*flowchart*", "Figure 1|Flowchart")),
  list(bn = "Figure 2-MIMIC. IPW-weighted Kaplan–Meier curves of 28-day all-cause mortality by Alteplase.pdf",
       src = pick_step_fig("step*weighted_km*", "Figure 2|IPW.?weighted")),
  list(bn = "Figure 3-MIMIC. Subgroup analysis of pe ipw alteplase (IPTW-adjusted).pdf",
       src = pick_step_fig("step*subgroup_iptw*", "Figure 3|Subgroup analysis")),
  list(bn = "Figure 4-MIMIC. Forest Plot Subgroup Analysis of pe ipw alteplase.pdf",
       src = pick_step_fig("step*treatment_forest*", "Forest Plot")),
  list(bn = "Figure 4-MIMIC. Subgroup Kaplan–Meier curves of 28-day mortality by age.pdf",
       src = pick_step_fig("step*subgroup_km*", "by age|Subgroup Kaplan")),
  list(bn = "Figure 5-MIMIC. STEPP of 28-day survival by Alteplase across composite risk.pdf",
       src = pick_step_fig("step*stepp*", "STEPP")),
  list(bn = "Figure S2-MIMIC. The distribution of propensity score and standardized mean difference before and after weighting.pdf",
       src = pick_step_fig("step*iptw_balance*", "propensity|SMD|standardized mean")),
  list(bn = "Figure S3-MIMIC. Unweighted Kaplan–Meier curves of 28-day all-cause mortality by Alteplase.pdf",
       src = pick_step_fig("step*weighted_km*", "Unweighted")),
  list(bn = "Figure S4-MIMIC. Calibration and receiver operating characteristic curves of the prediction model at 28-day.pdf",
       src = pick_step_fig("step*calibration*", "Calibration|ROC"))
)

# wipe wrong-numbered pdfs (keep regenerating set)
old_pdfs <- list.files(file.path(fig_root, "pdf"), pattern = "^Figure ", full.names = TRUE)
# keep S1 Missing we just made
keep_s1 <- basename(old_pdfs) == "Figure S1-MIMIC. Missing value overview.pdf"
unlink(old_pdfs[!keep_s1])

for (it in fig_map) {
  if (is.na(it$src) || !file.exists(it$src)) {
    cli::cli_alert_danger("MISSING source for {it$bn}")
    next
  }
  .copy_pdf(it$src, it$bn)
}

# ---------------------------------------------------------------------------
# 3) Curate Tables (Jin 5 + Sens)
# ---------------------------------------------------------------------------
.pick_tbl <- function(pattern) {
  # search unit Tables + step Tables
  fs <- c(
    list.files(tbl_root, pattern = "\\.xlsx$", full.names = TRUE),
    unlist(lapply(Sys.glob(file.path(unit, "step*")), function(d) {
      list.files(file.path(d, "Tables"), pattern = "\\.xlsx$", full.names = TRUE)
    }), use.names = FALSE)
  )
  fs <- fs[file.exists(fs)]
  fs <- fs[grepl(pattern, basename(fs), ignore.case = TRUE)]
  if (!length(fs)) return(NA_character_)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][[1L]]
}

dest_tbl <- list(
  t1 = "Table 1-MIMIC. Baseline characteristics before and after sIPTW.xlsx",
  s1 = "Table S1-MIMIC. The Uno's concordance index at 28-day.xlsx",
  s2 = "Table S2-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx",
  s3 = "Table S3-MIMIC. Univariate Regression Analysis.xlsx",
  s4 = "Table S4-MIMIC. Multicollinearity Analysis (VIF, univariate screen) for pe_ipw_alteplase.xlsx",
  sens_cox = "Table Sens-MIMIC. Multivariable Cox for Alteplase and 28-day mortality.xlsx",
  sens_ow = "Table Sens-MIMIC. Overlap Weights.xlsx"
)

src_tbl <- list(
  t1 = .pick_tbl("Table 1.*sIPTW"),
  s1 = .pick_tbl("Uno|concordance index"),
  s2 = .pick_tbl("before and after (multiple )?imputation"),
  s3 = .pick_tbl("Univariate Regression"),
  s4 = .pick_tbl("Multicollinearity|VIF screen"),
  sens_cox = .pick_tbl("Sens.*Multivariable Cox|Multivariable Cox"),
  sens_ow = .pick_tbl("Sens.*Overlap|Overlap Weights")
)

# clear old Table* in unit Tables (keep CSV manifests)
old_t <- list.files(tbl_root, pattern = "^Table.*\\.xlsx$", full.names = TRUE)
unlink(old_t)

for (k in names(dest_tbl)) {
  src <- src_tbl[[k]]
  if (is.na(src) || !file.exists(src)) {
    cli::cli_alert_danger("MISSING table {k}: {dest_tbl[[k]]}")
    next
  }
  file.copy(src, file.path(tbl_root, dest_tbl[[k]]), overwrite = TRUE)
  cli::cli_alert_success("Table: {dest_tbl[[k]]} <- {basename(src)}")
}

# mirror curated set to project root Tables/
root_tbl <- file.path(proj, "Tables")
dir.create(root_tbl, recursive = TRUE, showWarnings = FALSE)
# remove old Table* only
unlink(list.files(root_tbl, pattern = "^Table.*\\.xlsx$", full.names = TRUE))
for (nm in dest_tbl) {
  src <- file.path(tbl_root, nm)
  if (file.exists(src)) file.copy(src, file.path(root_tbl, nm), overwrite = TRUE)
}

# ---------------------------------------------------------------------------
# 4) Four formats
# ---------------------------------------------------------------------------
src_export <- file.path(.engine, "R", "pub_figure_export.R")
if (file.exists(src_export)) {
  source(file.path(.engine, "R", "utils.R"), local = TRUE)
  source(src_export, local = TRUE)
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    # flatten pdfs already in pdf/; ensure from that dir
    st <- pub_figure_ensure_formats(fig_root, config = list())
    cli::cli_alert_info("pub_figure_ensure_formats done")
  }
}

# checklist
need_fig <- c(
  "Figure 1-MIMIC. Flowchart",
  "Figure 2-MIMIC. IPW-weighted",
  "Figure 3-MIMIC. Subgroup analysis",
  "Figure 4-MIMIC. Forest Plot",
  "Figure 4-MIMIC. Subgroup Kaplan",
  "Figure 5-MIMIC. STEPP",
  "Figure S1-MIMIC. Missing",
  "Figure S2-MIMIC. The distribution of propensity",
  "Figure S3-MIMIC. Unweighted",
  "Figure S4-MIMIC. Calibration"
)
have <- list.files(file.path(fig_root, "pdf"), pattern = "\\.pdf$")
cli::cli_h2("Figure checklist")
for (pat in need_fig) {
  ok <- any(grepl(pat, have, fixed = TRUE) | grepl(gsub("\\.", "\\\\.", pat), have))
  # simpler: substring
  ok <- any(vapply(have, function(h) grepl(pat, h, fixed = TRUE), logical(1)))
  if (ok) cli::cli_alert_success("{pat}") else cli::cli_alert_danger("MISSING {pat}")
}
cli::cli_h2("Tables/")
print(list.files(tbl_root, pattern = "^Table"))
cli::cli_alert_success("repair done: {unit}")
