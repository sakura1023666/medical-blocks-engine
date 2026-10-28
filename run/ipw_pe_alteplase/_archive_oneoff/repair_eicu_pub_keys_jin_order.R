#!/usr/bin/env Rscript
# Repair PE×alteplase eICU 【success】eICU publication keys (Jin + stroke checklist).
# Parallel to repair_mimic_pub_keys_jin_order.R — does NOT touch by_unit/【success】main.
# Root Tables/: only add/overwrite *-eICU.* files; never delete *-MIMIC.* tables.

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

.unit_candidates <- c(
  file.path(proj, "by_unit", "\u3010success\u3011eICU"),
  file.path(proj, "by_unit", "eICU")
)
unit <- .unit_candidates[dir.exists(.unit_candidates)][1L]
if (is.na(unit) || !nzchar(unit)) stop("eICU unit dir not found under by_unit/")
# Hard stop if somehow pointed at MIMIC main
if (grepl("main$", basename(unit)) || grepl("success.main", basename(unit))) {
  stop("Refuse to repair MIMIC main unit from eICU repair script: ", unit)
}

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
# 1) Figure S1 Missing
# ---------------------------------------------------------------------------
s1_dest <- file.path(fig_root, "pdf", "Figure S1-eICU. Missing value overview.pdf")
if (!file.exists(s1_dest)) {
  ck <- file.path(unit, "checkpoints", "imputation.rds")
  if (!file.exists(ck)) {
    # step-prefixed checkpoint
    ck2 <- Sys.glob(file.path(unit, "checkpoints", "*imputation*.rds"))
    ck <- if (length(ck2)) ck2[[1L]] else ck
  }
  stopifnot(file.exists(ck))
  ctx <- readRDS(ck)$ctx
  dat <- ctx$data$mapped %||% ctx$data$cleaned
  stopifnot(is.data.frame(dat), nrow(dat) > 0)
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
    ggplot2::labs(title = "Missing value overview in eICU cohort")
  grDevices::pdf(s1_dest, width = fig_width, height = fig_height)
  print(p)
  grDevices::dev.off()
  cli::cli_alert_success("Generated {basename(s1_dest)}")
} else {
  cli::cli_alert_info("S1 Missing already exists")
}

# ---------------------------------------------------------------------------
# 2) Restore figures from step folders
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
  list(bn = "Figure 1-eICU. Flowchart of patient selection (eICU, IPW alteplase cohort).pdf",
       src = pick_step_fig("step*flowchart*", "Figure 1|Flowchart")),
  list(bn = "Figure 2-eICU. IPW-weighted Kaplan–Meier curves of 28-day all-cause mortality by Alteplase.pdf",
       src = pick_step_fig("step*weighted_km*", "Figure 2|IPW.?weighted")),
  list(bn = "Figure 3-eICU. Subgroup analysis of pe ipw alteplase (IPTW-adjusted).pdf",
       src = pick_step_fig("step*subgroup_iptw*", "Figure 3|Subgroup analysis")),
  list(bn = "Figure 4-eICU. Forest Plot Subgroup Analysis of pe ipw alteplase.pdf",
       src = pick_step_fig("step*treatment_forest*", "Forest Plot")),
  list(bn = "Figure 4-eICU. Subgroup Kaplan–Meier curves of 28-day mortality by age.pdf",
       src = pick_step_fig("step*subgroup_km*", "by age|Subgroup Kaplan")),
  list(bn = "Figure 5-eICU. STEPP of 28-day survival by Alteplase across composite risk.pdf",
       src = pick_step_fig("step*stepp*", "STEPP")),
  list(bn = "Figure S2-eICU. The distribution of propensity score and standardized mean difference before and after weighting.pdf",
       src = pick_step_fig("step*iptw_balance*", "propensity|SMD|standardized mean")),
  list(bn = "Figure S3-eICU. Unweighted Kaplan–Meier curves of 28-day all-cause mortality by Alteplase.pdf",
       src = pick_step_fig("step*weighted_km*", "Unweighted")),
  list(bn = "Figure S4-eICU. Calibration and receiver operating characteristic curves of the prediction model at 28-day.pdf",
       src = pick_step_fig("step*calibration*", "Calibration|ROC"))
)

old_pdfs <- list.files(file.path(fig_root, "pdf"), pattern = "^Figure ", full.names = TRUE)
keep_s1 <- basename(old_pdfs) == "Figure S1-eICU. Missing value overview.pdf"
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
# Prefer step*/Tables (never pick from unit Tables first — unlink would delete source)
.pick_tbl <- function(pattern) {
  fs <- unlist(lapply(Sys.glob(file.path(unit, "step*")), function(d) {
    list.files(file.path(d, "Tables"), pattern = "\\.xlsx$", full.names = TRUE)
  }), use.names = FALSE)
  fs <- fs[file.exists(fs)]
  fs <- fs[grepl(pattern, basename(fs), ignore.case = TRUE, perl = TRUE)]
  if (!length(fs)) return(NA_character_)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][[1L]]
}

dest_tbl <- list(
  t1 = "Table 1-eICU. Baseline characteristics before and after sIPTW.xlsx",
  s1 = "Table S1-eICU. The Uno's concordance index at 28-day.xlsx",
  s2 = "Table S2-eICU. Baseline characteristics of patients before and after multiple imputation.xlsx",
  s3 = "Table S3-eICU. Univariate Regression Analysis.xlsx",
  s4 = "Table S4-eICU. Multicollinearity Analysis (VIF, univariate screen) for pe_ipw_alteplase.xlsx",
  sens_cox = "Table Sens-eICU. Multivariable Cox for Alteplase and 28-day mortality.xlsx",
  sens_ow = "Table Sens-eICU. Overlap Weights.xlsx"
)

src_tbl <- list(
  t1 = .pick_tbl("Table 1.*sIPTW"),
  s1 = .pick_tbl("Uno|concordance index"),
  s2 = .pick_tbl("before and after (?:multiple )?imputation"),
  s3 = .pick_tbl("Univariate Regression"),
  s4 = .pick_tbl("Multicollinearity|VIF screen"),
  sens_cox = .pick_tbl("Sens.*Multivariable Cox|Table Sens Multivariable Cox"),
  sens_ow = .pick_tbl("Sens.*Overlap|Table Sens Overlap")
)

# Copy into unit Tables first, then remove non-dest leftovers
for (k in names(dest_tbl)) {
  src <- src_tbl[[k]]
  if (is.na(src) || !file.exists(src)) {
    cli::cli_alert_danger("MISSING table {k}: {dest_tbl[[k]]}")
    next
  }
  file.copy(src, file.path(tbl_root, dest_tbl[[k]]), overwrite = TRUE)
  cli::cli_alert_success("Table: {dest_tbl[[k]]} <- {basename(src)}")
}
keep_bn <- unname(unlist(dest_tbl, use.names = FALSE))
old_t <- list.files(tbl_root, pattern = "^Table.*\\.xlsx$", full.names = TRUE)
unlink(old_t[!basename(old_t) %in% keep_bn])

# Mirror eICU tables to project root WITHOUT deleting MIMIC tables
root_tbl <- file.path(proj, "Tables")
dir.create(root_tbl, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(root_tbl, pattern = "^Table.*-eICU\\.", full.names = TRUE))
for (nm in dest_tbl) {
  src <- file.path(tbl_root, nm)
  if (file.exists(src)) file.copy(src, file.path(root_tbl, nm), overwrite = TRUE)
}

# ---------------------------------------------------------------------------
# 4) Four formats + STEPP footnote in image_information if present
# ---------------------------------------------------------------------------
src_export <- file.path(.engine, "R", "pub_figure_export.R")
if (file.exists(src_export)) {
  source(file.path(.engine, "R", "utils.R"), local = TRUE)
  source(src_export, local = TRUE)
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    st <- pub_figure_ensure_formats(fig_root, config = list())
    cli::cli_alert_info("pub_figure_ensure_formats done")
  }
}

# Annotate Fig5 STEPP image_information if window was adjusted
img_dir <- file.path(fig_root, "image_information")
if (dir.exists(img_dir)) {
  fig5_md <- list.files(img_dir, pattern = "Figure 5-eICU.*STEPP", full.names = TRUE)
  for (md in fig5_md) {
    txt <- paste(readLines(md, warn = FALSE), collapse = "\n")
    note <- "\n\nSTEPP window note: eICU exposed n≈70; config uses window_size=400 / step_size=100 (may be further adjusted if unstable).\n"
    if (!grepl("STEPP window note", txt, fixed = TRUE)) {
      writeLines(paste0(txt, note), md, useBytes = TRUE)
      cli::cli_alert_info("Annotated STEPP window note in {basename(md)}")
    }
  }
}

need_fig <- c(
  "Figure 1-eICU. Flowchart",
  "Figure 2-eICU. IPW-weighted",
  "Figure 3-eICU. Subgroup analysis",
  "Figure 4-eICU. Forest Plot",
  "Figure 4-eICU. Subgroup Kaplan",
  "Figure 5-eICU. STEPP",
  "Figure S1-eICU. Missing",
  "Figure S2-eICU. The distribution of propensity",
  "Figure S3-eICU. Unweighted",
  "Figure S4-eICU. Calibration"
)
have <- list.files(file.path(fig_root, "pdf"), pattern = "\\.pdf$")
cli::cli_h2("Figure checklist")
for (pat in need_fig) {
  ok <- any(vapply(have, function(h) grepl(pat, h, fixed = TRUE), logical(1)))
  if (ok) cli::cli_alert_success("{pat}") else cli::cli_alert_danger("MISSING {pat}")
}
cli::cli_h2("Tables/")
print(list.files(tbl_root, pattern = "^Table"))
cli::cli_alert_success("repair done: {unit}")
# Safety echo
cli::cli_alert_info("MIMIC dir left untouched: {file.path(proj, 'by_unit', '\u3010success\u3011main')}")
