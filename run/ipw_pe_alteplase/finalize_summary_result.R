#!/usr/bin/env Rscript
# PE × alteplase — 薄封装：收口逻辑在 R/ipw_dual_db_pub.R；本文件只写课题 Methods 文案
#   Rscript run/ipw_pe_alteplase/finalize_summary_result.R --project <根>

suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
})

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

proj <- .arg("--project", "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw")
if (!dir.exists(proj)) {
  proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
}
stopifnot(dir.exists(proj))

engine <- {
  cands <- c(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""), "E:/01block/01Block-new-Final",
             "/mnt/e/01block/01Block-new-Final")
  cands[dir.exists(cands) & nzchar(cands)][[1L]]
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
if (!nzchar(Sys.getenv("MEDICAL_BLOCKS_PYTHON", "")) && file.exists("/usr/bin/python3")) {
  Sys.setenv(MEDICAL_BLOCKS_PYTHON = "/usr/bin/python3")
}

source(file.path(engine, "R/utils.R"), local = TRUE)
source(file.path(engine, "R/pub_software_versions.R"), local = TRUE)
source(file.path(engine, "R/pub_figure_export.R"), local = TRUE)
source(file.path(engine, "R/ipw_dual_db_pub.R"), local = TRUE)

methods_lines <- c(
  "# Methods — Statistical analysis",
  "",
  "## Study question",
  "",
  paste0(
    "Among adults with pulmonary embolism (PE) in ICU databases (MIMIC and eICU), ",
    "we estimated the association between **alteplase prescription (yes vs no)** and ",
    "**28-day all-cause mortality**, using propensity-score inverse probability weighting (IPW) ",
    "aligned with Jin et al. (2026) medication-regimen / sIPTW reporting."
  ),
  "",
  "## Data and cohorts",
  "",
  "- **Primary database:** MIMIC (unit `main`).",
  "- **External database:** eICU.",
  "- **Exposure (MAIN):** prescription-only alteplase (`Alteplase` / `Alteplase_rx`); infusion-only flags were not used as the primary exposure.",
  "- **Outcome:** 28-day all-cause death (`futime` censored at 28 days; `fustatus`).",
  "- Dual-database column harmonization preceded modeling; Table 1 variables were locked to a shared list and order.",
  "",
  "## Missing data",
  "",
  "Multiple imputation by chained equations (MICE) was used for covariates with missingness ",
  "(see Table S2). Analyses used the completed analysis set after imputation.",
  "",
  "## Propensity score and weighting",
  "",
  paste0(
    "A logistic propensity-score model for alteplase used Model-2 prognostic covariates ",
    "(from the univariate → VIF → multivariable path). Stabilized IPTW (sIPTW) was applied ",
    "for the primary weighted analyses. Covariate balance before/after weighting is reported ",
    "in Table 1 (Overall / No alteplase / Alteplase / P / SMD unweighted & weighted) and Figure S1 ",
    "(PS distribution + SMD Love plot)."
  ),
  "",
  "## Primary association",
  "",
  paste0(
    "IPW-weighted Kaplan–Meier curves and log-rank summaries (Figure 2); ",
    "unweighted KM as sensitivity display (Figure S2). ",
    "Multivariable Cox models (Crude / Model 1 = Age / Model 2 = full adjustment) ",
    "and overlap-weighted Cox (ATO via WeightIt) are reported under `Table Sens-*`."
  ),
  "",
  "## Subgroup, STEPP, calibration",
  "",
  "- **Figure 3:** IPTW-adjusted subgroup forest (locked variables dual-DB aligned).",
  "- **Figure 4:** Age-stratified IPW KM (<65 / ≥65), dual-panel stacked.",
  "- **Figure 5:** STEPP of 28-day survival across Cox linear-predictor composite risk, dual-panel stacked.",
  "- **Figure S3:** Calibration and ROC of the 28-day prediction model, dual-panel stacked.",
  "",
  "## Supplementary tables (Jin four-pack)",
  "",
  "| Table | Content |",
  "|-------|---------|",
  "| Table 1 | Baseline before/after sIPTW |",
  "| Table S1 | Uno concordance at 28 days |",
  "| Table S2 | Baseline before/after multiple imputation |",
  "| Table S3 | Univariate regression |",
  "| Table S4 | Multicollinearity (VIF) |",
  "| Table Sens | Multivariable Cox; Overlap weights |",
  "",
  "## Software",
  "",
  "See `Methods_software_versions.txt` and `Methods_software_section.md` in this folder.",
  "",
  paste0("- Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  ""
)

readme_lines <- c(
  "# summary_result — PE × alteplase IPW (MIMIC + eICU)",
  "",
  "Publication bundle after dual-unit Path-1 run + dual-panel remirror.",
  "",
  "## Contents",
  "",
  "- `Tables/` — Table 1, S1–S4, Sens (Cox + Overlap), both databases",
  "- `Figures/` — Fig 1–5 + S1–S3 (pdf/png/tiff + image_information) @ ≥600 dpi",
  "- `Methods_statistical_analysis.md`",
  "- `Methods_software_versions.txt` / `Methods_software_section.md`",
  "",
  "## QC",
  "",
  "```bash",
  "Rscript run/pub/run_pub_qc_after_project.R --project <project_root>",
  "```",
  "",
  "Then Agent Layer D: nature-statistics + nature-figure (fix all P0; DPI≥600).",
  ""
)

res <- ipw_finalize_summary_result(
  project_root = proj,
  methods_lines = methods_lines,
  readme_lines = readme_lines
)
cli::cli_alert_success("summary_result ready -> {res$summary_root}")
print(list(
  tables = list.files(file.path(res$summary_root, "Tables")),
  figures_pdf = list.files(file.path(res$summary_root, "Figures", "pdf"))
))
if (!isTRUE(res$ok)) quit(status = 1L)
