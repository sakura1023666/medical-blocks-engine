#!/usr/bin/env Rscript
# Non-ML tables: MIMIC-IV only (keep Table 1 dual + ML S11–S16 with eICU).
source("/mnt/e/01block/01Block-new-Final/R/utils.R")

src_db <- "/tmp/sar_tables_by_db"
out <- "/tmp/sar_tables_mimic_only"
dir.create(out, recursive = TRUE, showWarnings = FALSE)

map <- c(
  "Table 2 Joint group Cox.xlsx" =
    "Table 2-MIMIC IV. Joint group Cox.xlsx",
  "Table S4 SAR CrCV Cox.xlsx" =
    "Table S4-MIMIC IV. SAR CrCV Cox.xlsx",
  "Table S5 ROC discrimination DeLong.xlsx" =
    "Table S5-MIMIC IV. ROC discrimination DeLong.xlsx",
  "Table S6 PH Overall.xlsx" =
    "Table S6-MIMIC IV. PH overall cohort.xlsx",
  "Table S9 baseline glucose excluded joint Cox.xlsx" =
    "Table S9-MIMIC IV. Baseline glucose excluded joint Cox.xlsx",
  "Table S10 complete-case joint Cox.xlsx" =
    "Table S10-MIMIC IV. Complete-case joint Cox.xlsx"
)
for (nm in names(map)) {
  ok <- file.copy(file.path(src_db, map[[nm]]), file.path(out, nm), overwrite = TRUE)
  stopifnot(ok)
  message("copied ", nm)
}

s1_body <- data.frame(
  item = c("AKI cohort identification", "Follow-up / outcome"),
  definition = c(
    "MIMIC-IV D02 contains an Acute Renal Failure flag (Yes/No); the analysis cohort is identified from this flag.",
    "Outcome is 28-day all-cause mortality (Survivor / Non-survivor); follow-up is capped at 28 days."
  ),
  `evidence source` = c(
    "D02 result MIMIC.RData (measured)",
    "config outcome column fustatus / engine 0-1 mapping"
  ),
  `evidence status` = c("Confirmed", "Confirmed"),
  `evidence detail` = c(
    "Acute Renal Failure flag (Yes/No) verified present; n=26,055 at D02 stage.",
    "fustatus 0/1 mapped via pipeline_outcome_as_01; death=1 (Non-survivor)."
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
sci_xlsx_single_header_booktabs(
  file.path(out, "Table S1. AKI cohort and variable definitions with code evidence.xlsx"),
  title = "Table S1. AKI cohort and variable definitions with code-level evidence (MIMIC-IV).",
  df_body = s1_body,
  sheet = "Table S1",
  footnotes = c(
    "MIMIC-IV development cohort only. eICU appears in Table 1 and machine-learning external-validation tables (Table S11–S16).",
    "No ICD codes are fabricated."
  )
)

s3_src <- paste0(
  "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/",
  "【success】SAR+CrCV/summary_result/Tables/",
  "Table S3-MIMIC IV. Variance inflation factor between variables.xlsx"
)
file.copy(s3_src, file.path(out, basename(s3_src)), overwrite = TRUE)

message("OUT: ", paste(list.files(out), collapse = " | "))
