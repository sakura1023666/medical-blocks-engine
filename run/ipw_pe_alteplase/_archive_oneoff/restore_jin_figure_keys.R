#!/usr/bin/env Rscript
# Wipe scrambled unit Figures and restore Jin keys from step dirs.
# Fig1 Flow | Fig2 IPW-KM | Fig3 IPTW forest | Fig4 age KM | Fig5 STEPP
# Supp: S1=PS+SMD | S2=unweighted KM | S3=calib+ROC  (NO Missing)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

proj <- .arg("--project", "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw")
if (!dir.exists(proj)) proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
engine <- {
  cands <- c("E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")
  cands[dir.exists(cands)][[1L]]
}

.pick_latest <- function(paths) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(NULL)
  paths[ whiche.max(file.info(paths)$mtime) ]
}
whiche.max <- function(x) which.max(x)

.restore_unit <- function(unit_tag, db_lab) {
  root <- file.path(proj, "by_unit", unit_tag)
  stopifnot(dir.exists(root))
  fig_pdf <- file.path(root, "Figures", "pdf")
  dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)

  find_role <- function(pattern, prefer_step = NULL) {
    hits <- list.files(root, pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
    hits <- hits[grepl("Figures", hits, fixed = TRUE)]
    hits <- hits[!grepl("/png/|/tiff/", hits)]
    hits <- hits[grepl(pattern, basename(hits), ignore.case = TRUE, perl = TRUE)]
    # prefer step_* sources over already-scrambled Figures/pdf
    step_hits <- hits[grepl("step\\d+_", hits)]
    if (length(step_hits)) hits <- step_hits
    if (!is.null(prefer_step) && length(hits)) {
      pref <- hits[grepl(prefer_step, hits, fixed = TRUE)]
      if (length(pref)) hits <- pref
    }
    .pick_latest(hits)
  }

  # resolve ALL sources BEFORE wipe (Figures/pdf may hold only copies)
  map <- list(
    fig1 = find_role("Flowchart.*alteplase", "ipw_diabetes_flowchart"),
    fig2 = find_role("IPW-weighted.*Alteplase", "ipw_weighted_km"),
    fig3 = find_role("Subgroup analysis.*(Alteplase|pe ipw|and pe)", "subgroup_iptw_weighted"),
    fig4 = find_role("Subgroup Kaplan", "ipw_subgroup_km"),
    fig5 = find_role("STEPP", "stepp_prognosis"),
    s1 = find_role("propensity score", "iptw_balance"),
    s2 = find_role("Unweighted.*Alteplase", "ipw_weighted_km"),
    s3 = find_role("Calibration", "ipw_surv_calibration")
  )
  # fallback if Alteplase-named PDF not yet present (legacy Diabetes caption)
  if (is.null(map$fig1)) map$fig1 <- find_role("Flowchart.*(alteplase|diabetes)", "ipw_diabetes_flowchart")
  if (is.null(map$fig2)) map$fig2 <- find_role("IPW-weighted.*(Alteplase|Diabetes)", "ipw_weighted_km")
  if (is.null(map$s2)) map$s2 <- find_role("Unweighted.*(Alteplase|Diabetes)", "ipw_weighted_km")

  # wipe all figure formats AFTER sources resolved
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    d <- file.path(root, "Figures", sub)
    if (!dir.exists(d)) next
    unlink(list.files(d, full.names = TRUE))
  }
  unlink(list.files(file.path(root, "Figures"), pattern = "^Figure", full.names = TRUE))

  dests <- list(
    fig1 = sprintf("Figure 1-%s. Flowchart of patient selection (%s, IPW alteplase cohort).pdf", db_lab, db_lab),
    fig2 = sprintf("Figure 2-%s. IPW-weighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Alteplase.pdf", db_lab),
    fig3 = sprintf("Figure 3-%s. Subgroup analysis of Alteplase (IPTW-adjusted).pdf", db_lab),
    fig4 = sprintf("Figure 4-%s. Subgroup Kaplan\u2013Meier curves of 28-day mortality by age.pdf", db_lab),
    fig5 = sprintf("Figure 5-%s. STEPP of 28-day survival by Alteplase across composite risk.pdf", db_lab),
    s1 = sprintf("Figure S1-%s. The distribution of propensity score and standardized mean difference before and after weighting.pdf", db_lab),
    s2 = sprintf("Figure S2-%s. Unweighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Alteplase.pdf", db_lab),
    s3 = sprintf("Figure S3-%s. Calibration and receiver operating characteristic curves of the prediction model at 28-day.pdf", db_lab)
  )

  for (role in names(dests)) {
    src <- map[[role]]
    if (is.null(src)) {
      cli::cli_alert_danger("{db_lab} missing source for {role}")
      next
    }
    # if fig2/s2 only diabetes-named, still allow via looser search
    dest <- file.path(fig_pdf, dests[[role]])
    ok <- file.copy(src, dest, overwrite = TRUE)
    if (!isTRUE(ok)) stop("copy failed ", src)
    cli::cli_alert_success("{dests[[role]]} <- {basename(src)}")
  }

  source(file.path(engine, "R/utils.R"), local = TRUE)
  source(file.path(engine, "R/pub_figure_export.R"), local = TRUE)
  pub_figure_ensure_formats(file.path(root, "Figures"), config = list())
  invisible(TRUE)
}

suppressPackageStartupMessages(library(cli))
.restore_unit("\u3010success\u3011main", "MIMIC")
.restore_unit("\u3010success\u3011eICU", "eICU")
cli::cli_alert_success("Jin keys restored for both units")
