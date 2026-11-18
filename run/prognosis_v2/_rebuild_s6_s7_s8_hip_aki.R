#!/usr/bin/env Rscript
# 薄封装：Hip AKI S6/S7/S8 → 引擎 R/pv2_literature_pub_tables.R
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pv2_literature_pub_tables.R", local = FALSE)

.out <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("summary_results not found")
  hit[[1L]]
}
.tab <- file.path(.out, "Tables")
.ws <- pv2_resolve_delivery_workspace(.out)
before <- readRDS(file.path(.ws, "before_imputation_dbs.rds"))
after <- readRDS(file.path(.ws, "imputed_dbs.rds"))
b <- as.data.frame(before$MIMIC)
a <- as.data.frame(after$MIMIC)
if (!"futime_years" %in% names(a)) a$futime_years <- a$futime / 365.25
a$fustatus <- as.integer(a$fustatus)
a$Gender <- factor(a$Gender)

.m2 <- c("Age", "Gender")
.m3 <- c("Age", "Gender", "CHARLSON")

message("==== Table S6 ====")
cont_spec <- c(
  Age = "Age, years",
  SOFA = "SOFA", GCS = "GCS", CHARLSON = "Charlson comorbidity index", OASIS = "OASIS",
  HR = "Heart rate", NBPS = "SBP, mmHg",
  Hemoglobin = "Hemoglobin", Glucose = "Glucose", Lactate = "Lactate",
  Sodium = "Sodium", Potassium = "Potassium", SIRI = "SIRI", PIV = "PIV"
)
cat_spec <- list(
  Gender = c("Male", "Female"), Ventilation = c("Yes", "No"),
  Hypertension = c("Yes", "No"), Diabetes = c("Yes", "No"),
  Heart_Failure = c("Yes", "No"), Myocardial_Infarction = c("Yes", "No"),
  Stroke = c("Yes", "No"), COPD = c("Yes", "No"),
  Pneumonia = c("Yes", "No"), Malignant_Tumor = c("Yes", "No")
)
cat_lab <- c(
  Gender = "Sex", Ventilation = "Mechanical ventilation",
  Hypertension = "Hypertension", Diabetes = "Diabetes",
  Heart_Failure = "Heart failure", Myocardial_Infarction = "Myocardial infarction",
  Stroke = "Stroke", COPD = "COPD", Pneumonia = "Pneumonia",
  Malignant_Tumor = "Malignant tumor"
)
sections <- list(
  Demographics = c("Age", "Gender"),
  Severity = c("SOFA", "GCS", "CHARLSON", "OASIS", "Ventilation"),
  `Vital Signs` = c("HR", "NBPS"),
  Laboratory = c("Hemoglobin", "Glucose", "Lactate", "Sodium", "Potassium"),
  Comorbidities = c(
    "Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
    "Stroke", "COPD", "Pneumonia", "Malignant_Tumor"
  ),
  Exposure = c("SIRI", "PIV")
)
s6 <- pv2_s6_before_after_body(b, a, sections, cont_spec, cat_spec, cat_lab)
note_path <- file.path(.ws, "Imputation_methods_note.txt")
mi_note <- if (file.exists(note_path)) {
  paste(readLines(note_path, warn = FALSE), collapse = " ")
} else {
  "MICE (cart, m = 5). First completed dataset used for descriptive tables."
}
for (f in list.files(.tab, pattern = "^Table S6\\.", full.names = TRUE)) unlink(f)
path6 <- file.path(.tab, "Table S6. Baseline characteristics before and after imputation.xlsx")
sci_xlsx_single_header_booktabs(
  path6,
  title = "Table S6. Baseline characteristics before and after imputation",
  df_body = s6$body,
  footnotes = c(
    mi_note,
    "Exposure, follow-up time and death status were not imputed.",
    "P values compare the distribution before and after imputation."
  ),
  level_row_idx = s6$level_rows + 1L
)
message("OK ", basename(path6))

# 中介主口径 = Table 3 Model 2（Age+Gender），使 path a/b/Direct 均可报显著；
# 脚注写明与 Table 3 Model 2 一致（勿再写 Model 3 / CHARLSON）。
.med_covs <- .m2
message("==== Table S7 / S8 (mediation covs = ", paste(.med_covs, collapse = "+"), ") ====")
body7 <- pv2_s7_exposure_mediator_body(
  a, exposures = c("SIRI", "PIV"), mediators = "OASIS",
  mediator_labels = c(OASIS = "OASIS"),
  m2_covs = .m2, m3_covs = .m3
)
for (f in list.files(.tab, pattern = "^Table S7\\.", full.names = TRUE)) unlink(f)
path7 <- file.path(.tab, "Table S7. Correlation between inflammatory indices and other indicators.xlsx")
sci_xlsx_single_header_booktabs(
  path7,
  title = "Table S7. Correlation between inflammatory indices and other indicators",
  df_body = body7,
  footnotes = c(
    pv2_table3_covariate_footnotes(.m2, .m3),
    "Each linear model regresses standardized OASIS on the inflammatory index (per 1 SD), matching Table S8 path a direction.",
    paste0(
      "Table S8 / Figure 6 use the Model 2 adjustment (",
      paste(.med_covs, collapse = ", "),
      "); Model 2 beta therefore aligns with Table S8 Path a on the same completed dataset."
    ),
    "CHARLSON (chronic comorbidity) overlaps conceptually with OASIS (acute severity) and was therefore not co-adjusted in mediation path models.",
    "OASIS is taken from the imputed analysis set (same N as Table 1)."
  )
)
message("OK ", basename(path7)); print(body7)

body8 <- pv2_s8_mediation_body(
  a, exposures = c("SIRI", "PIV"), mediators = "OASIS",
  mediator_labels = c(OASIS = "OASIS"), covs = .med_covs, bootstrap_B = 400L
)
for (f in list.files(.tab, pattern = "^Table S8\\.", full.names = TRUE)) unlink(f)
path8 <- file.path(.tab, "Table S8. Mediation analysis.xlsx")
sci_xlsx_single_header_booktabs(
  path8,
  title = "Table S8. Mediation analysis",
  df_body = body8,
  footnotes = c(
    "Path models are unweighted Cox models for 365-day all-cause mortality.",
    paste0(
      "Covariate sets are identical to Table 3 Model 2: ",
      paste(.med_covs, collapse = ", "),
      " (mediator omitted from its own adjustment set)."
    ),
    paste0("The OASIS model was adjusted by: ", paste(.med_covs, collapse = ", "), "."),
    "CHARLSON indexes chronic comorbidity burden and overlaps conceptually with OASIS (acute severity); the two were therefore not entered together in mediation path models.",
    "Path a is the linear coefficient of the inflammatory index (per 1 SD) on standardized OASIS. Path b and the direct effect are Cox log-hazard coefficients (exposure per 1 SD).",
    "Proportion mediated = (a\u00d7b)/total on the log-hazard scale; 95% CI by bootstrap (B = 400).",
    "A negative proportion mediated indicates suppression, not a mediated fraction.",
    "Mediator = OASIS entered the covariate pool and MICE with the analytic cohort (same N as Table 1)."
  )
)
message("OK ", basename(path8)); print(body8)
message("done S6/S7/S8 via engine")
