#!/usr/bin/env Rscript
# PE × alteplase — 薄封装：双库拼图逻辑在 R/ipw_dual_db_pub.R（全项目复用）
#   Rscript run/ipw_pe_alteplase/remirror_dual_panel_figures.R --project <根>

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
  cands <- c(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""), Sys.getenv("BLOCK_REPO_ROOT", ""),
             "E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  hit[[1L]]
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
if (!nzchar(Sys.getenv("MEDICAL_BLOCKS_PYTHON", "")) && file.exists("/usr/bin/python3")) {
  Sys.setenv(MEDICAL_BLOCKS_PYTHON = "/usr/bin/python3")
}

source(file.path(engine, "R/utils.R"), local = TRUE)
source(file.path(engine, "R/pub_figure_export.R"), local = TRUE)
source(file.path(engine, "R/ipw_dual_db_pub.R"), local = TRUE)

spec <- ipw_jin_role_spec(
  exposure_lab = "Alteplase",
  cohort_lab = "IPW alteplase cohort",
  outcome_lab = "28-day all-cause mortality",
  skip_missing_overview = TRUE
)
res <- ipw_dual_panel_remirror(
  project_root = proj,
  unit_a = "main",
  unit_b = "eICU",
  label_a = "A. MIMIC",
  label_b = "B. eICU",
  role_spec = spec
)
print(list.files(file.path(res$out_figures, "pdf")))
if (!isTRUE(res$ok)) {
  print(res)
  quit(status = 1L)
}
cli::cli_alert_success("remirror done -> {res$out_figures}")
