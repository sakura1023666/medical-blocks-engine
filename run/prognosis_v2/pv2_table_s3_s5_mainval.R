engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"))
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"))
source(file.path(engine, "run/prognosis_v2/pv2_mi_cox.R"))
pv2_ensure_dirs()
suppressPackageStartupMessages({ library(data.table); library(survival); library(survey) })
options(survey.lonely.psu = "adjust")
dbs <- pv2_apply_sleep_group5(readRDS(pv2_artifact("imputed_dbs.rds")))
mids_all <- readRDS(pv2_artifact("imputed_mids.rds"))
note <- readLines(file.path(pv2_ckpt_dir, "Covariate_selection_note.txt"), warn = FALSE)
m3 <- trimws(strsplit(sub("^Model 3 =\\s*", "", grep("^Model 3 =", note, value = TRUE)[1]), "\\s*\\+\\s*")[[1]])
fmt_p <- function(p) if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
nonref <- setdiff(pv2_sleep_levels_cox, "7-8")

for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$database <- nm
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d5 <- d[!(d$fustatus == 1 & d$futime_years <= 1), ]
  need <- c("futime_years", "fustatus", "Sleep_Group", m3)
  d5 <- d5[stats::complete.cases(d5[, need]) & d5$futime_years > 0, ]
  rhs <- paste(c("Sleep_Group", m3), collapse = " + ")
  fit <- pv2_cox_extract(
    d5, rhs,
    mids = if (nm %in% names(mids_all)) mids_all[[nm]] else NULL,
    weighted = identical(nm, "NHANES"), rubin = TRUE,
    exposure_keep = c("Sleep_Group", "Sleep_hours", "futime_years", "fustatus", "ID")
  )
  get <- function(key) {
    i <- grep(key, fit$term, fixed = TRUE)
    if (!length(i)) return(c("", ""))
    r <- fit[i[1], ]
    c(sprintf("%.3f (%.3f–%.3f)", r$hr, r$lo, r$hi), fmt_p(r$p))
  }
  body2 <- data.frame(
    Variable = unname(pv2_sleep_labels[nonref]),
    `HR (95% CI)` = vapply(nonref, function(g) get(paste0("Sleep_Group", g))[1], character(1)),
    P = vapply(nonref, function(g) get(paste0("Sleep_Group", g))[2], character(1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(pv2_tab_dir, sprintf("Table S5-%s. Sensitivity excluding deaths within 1 year.xlsx", nm)),
    title = "Table S5. Cox models excluding deaths within the first year",
    df_body = body2,
    footnotes = c(
      sprintf("Analytic N=%d, deaths=%d after excluding deaths in year 1.", nrow(d5), sum(d5$fustatus == 1)),
      paste0("Model 3 adjusted by: ", paste(m3, collapse = ", "), "."),
      "Sleep groups: <5 h, 5-6 h, 6-7 h, 7-8 h (reference) and >=9 h.",
      sprintf("Cohort role: %s.", pv2_role_label(nm))
    )
  )
  message("S5 ", nm)
}

# Rebuild 5-year horizon Cox with 5-level sleep, then write S3 xlsx
horizon_rows <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$database <- nm
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d$futime_years <- pmin(d$futime_years, 5)
  need <- c("futime_years", "fustatus", "Sleep_Group", m3)
  d <- d[stats::complete.cases(d[, need]) & d$futime_years > 0, ]
  rhs <- paste(c("Sleep_Group", m3), collapse = " + ")
  fit <- pv2_cox_extract(
    d, rhs,
    mids = if (nm %in% names(mids_all)) mids_all[[nm]] else NULL,
    weighted = identical(nm, "NHANES"), rubin = TRUE,
    exposure_keep = c("Sleep_Group", "Sleep_hours", "futime_years", "fustatus", "ID")
  )
  hit <- fit[grepl("^Sleep_Group", fit$term), , drop = FALSE]
  if (!nrow(hit)) next
  horizon_rows[[length(horizon_rows) + 1L]] <- data.frame(
    database = nm, term = hit$term, HR = hit$hr, lo = hit$lo, hi = hit$hi, p = hit$p,
    stringsAsFactors = FALSE
  )
  body <- data.frame(
    Term = hit$term,
    `HR (95% CI)` = sprintf("%.3f (%.3f–%.3f)", hit$hr, hit$lo, hit$hi),
    P = vapply(hit$p, fmt_p, character(1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(pv2_tab_dir, sprintf("Table S3-%s. Cox model with 5-year horizon.xlsx", nm)),
    title = "Table S3. Cox models with administrative 5-year follow-up horizon",
    df_body = body,
    footnotes = c(
      "Events after 5 years are censored at 5 years.",
      paste0("Model 3 covariates: ", paste(m3, collapse = ", "), "."),
      "Sleep groups: <5 h, 5-6 h, 6-7 h, 7-8 h (reference) and >=9 h."
    )
  )
  message("S3 ", nm)
}
if (length(horizon_rows)) {
  fwrite(do.call(rbind, horizon_rows), file.path(pv2_ckpt_dir, "Table S3. Cox 5-year horizon.csv"))
}
message("done")
