#!/usr/bin/env Rscript
# Hip AKI prognosis_v2：只重修 Table1（全变量+SMD）与 Table2（观察死亡数+RD/NNT）
# + 重写 Methods / 软件版本（踢 cmprsk）。可复用逻辑在 R/pv2_table1_smd.R。

suppressPackageStartupMessages({
  library(data.table)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/pv2_table1_smd.R"), local = FALSE)

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
dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
if (!"MIMIC" %in% names(dbs)) names(dbs) <- "MIMIC"
d0 <- as.data.frame(dbs$MIMIC)
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$time <- d0$futime_years
d0$event <- as.integer(d0$fustatus)
n_death <- sum(d0$event == 1L)

.qsc_cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE,
  try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05,
  pass_rule = "all",
  on_none_pass = "best_n_pass",
  family = "cox",
  time_var = "futime_years",
  event_var = "fustatus"
))
.qsc <- quantile_scheme_resolve_cascade(d0, c("SIRI", "PIV"), config = .qsc_cfg)
d0 <- quantile_scheme_attach_groups(d0, .qsc)
.qsc_meta <- .qsc$meta

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
mean_sd <- function(x) sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
med_iqr <- function(x) {
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f%%)", k, if (n > 0) 100 * k / n else NA_real_)
is_normal_vec <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3L) return(FALSE)
  p <- tryCatch(
    if (length(x) > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value,
    error = function(e) 0
  )
  is.finite(p) && p >= 0.05
}

message("==== Table 1 ====")
d <- d0
d$status <- factor(ifelse(d$event == 1, "Non-survivor", "Survivor"),
                   levels = c("Survivor", "Non-survivor"))
.race_lv <- if ("Race" %in% names(d)) as.character(unique(stats::na.omit(d$Race))) else character(0)
.demo_cats <- list(Gender = c("Male", "Female"))
if (length(.race_lv)) .demo_cats$Race <- .race_lv
layout <- list(
  Demographics = list(cont = c(Age = "Age, years"), cats = .demo_cats),
  Severity = list(
    cont = c(
      SOFA = "SOFA", GCS = "GCS", CHARLSON = "Charlson comorbidity index",
      OASIS = "OASIS"
    ),
    cats = list(Ventilation = c("Yes", "No"))
  ),
  `Vital Signs` = list(
    cont = c(
      HR = "Heart rate", NBPS = "SBP, mmHg", NBPD = "DBP, mmHg",
      RR = "Respiratory rate", SpO2 = "SpO2, %", Temperature = "Temperature, \u00b0C"
    ),
    cats = list()
  ),
  Laboratory = list(
    cont = c(
      Hemoglobin = "Hemoglobin", Glucose = "Glucose", Lactate = "Lactate",
      Sodium = "Sodium", Potassium = "Potassium"
    ),
    cats = list()
  ),
  Comorbidities = list(
    cont = c(),
    cats = list(
      Hypertension = c("Yes", "No"), Diabetes = c("Yes", "No"),
      Heart_Failure = c("Yes", "No"), Myocardial_Infarction = c("Yes", "No"),
      Stroke = c("Yes", "No"), COPD = c("Yes", "No"), Pneumonia = c("Yes", "No"),
      Malignant_Tumor = c("Yes", "No")
    )
  ),
  Exposure = list(cont = c(SIRI = "SIRI", PIV = "PIV"), cats = list())
)
cat_lab <- c(
  Gender = "Sex", Race = "Race", Ventilation = "Mechanical ventilation",
  Hypertension = "Hypertension", Diabetes = "Diabetes",
  Heart_Failure = "Heart failure", Myocardial_Infarction = "Myocardial infarction",
  Stroke = "Stroke", COPD = "COPD", Pneumonia = "Pneumonia",
  Malignant_Tumor = "Malignant tumor"
)
t1 <- pv2_baseline_survivor_smd_body(
  d, layout, cat_lab = cat_lab,
  fmt_p = fmt_p, mean_sd = mean_sd, med_iqr = med_iqr,
  n_pct = n_pct, is_normal_vec = is_normal_vec
)
body <- t1$body
hdr <- stats::setNames(as.data.frame(t(names(body)), stringsAsFactors = FALSE), names(body))
show <- rbind(hdr, body); show[1, ] <- as.character(show[1, ])
path_t1 <- file.path(.tab, "Table 1. Baseline characteristics.xlsx")
.sci_xlsx_write_three_line_workbook(
  path_t1, title = "Table 1. Baseline characteristics", tbl_df_new = show,
  footnotes = c(
    "Continuous variables are mean (SD) if approximately normal, otherwise median (IQR). Categorical variables are n (%).",
    "P values compare Survivor vs Non-survivor (Wilcoxon or chi-square/Fisher).",
    "SMD = standardized mean difference (Survivor vs Non-survivor; Austin 2009).",
    sprintf(
      "Analytic cohort: hip arthroplasty with AKI, Age\u226565, MIMIC-IV; primary endpoint 365-day all-cause mortality (N=%d, observed deaths=%d).",
      nrow(d), n_death
    )
  ),
  insert_map = stats::setNames(rep(1L, length(t1$section_names)), t1$section_names),
  level_row_idx = t1$level_rows + 1L
)
message("Table 1 rows=", nrow(body), " cols=", paste(names(body), collapse = " | "))

message("==== Table 2 ====")
t2_rows <- list()
.abs_notes <- character(0)
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(d)) qv <- paste0(idx, "_Q")
  dd <- d[!is.na(d[[qv]]), ]
  dd$ord <- as.integer(dd[[qv]])
  tr <- tryCatch(
    stats::glm(event ~ ord, offset = log(pmax(time, 1e-8)), family = poisson(), data = dd),
    error = function(e) NULL
  )
  p_tr <- if (!is.null(tr)) summary(tr)$coefficients["ord", "Pr(>|z|)"] else NA_real_
  t2_rows[[length(t2_rows) + 1L]] <- c(idx, "", "", "", "")
  n_by <- integer(0); ev_by <- integer(0)
  for (g in .qsc_meta$labels) {
    sub <- dd[as.character(dd[[qv]]) == g, , drop = FALSE]
    n <- nrow(sub); ev <- sum(sub$event == 1L); pyrs <- sum(sub$time)
    ci <- stats::poisson.test(ev, T = max(pyrs, .Machine$double.eps))$conf.int * 1e2
    t2_rows[[length(t2_rows) + 1L]] <- c(
      quantile_scheme_level_display(g, .qsc$scheme), as.character(n), as.character(ev),
      sprintf("%.2f", 100 * ev / max(n, 1L)),
      sprintf("%.2f (%.2f\u2013%.2f)", 100 * ev / max(pyrs, .Machine$double.eps), ci[1], ci[2])
    )
    n_by <- c(n_by, n); ev_by <- c(ev_by, ev)
  }
  t2_rows[[length(t2_rows) + 1L]] <- c("P for trend", "", fmt_p(p_tr), "", "")
  ar <- pv2_absolute_risk_from_events(n_by[1], ev_by[1], n_by[length(n_by)], ev_by[length(ev_by)])
  t2_rows[[length(t2_rows) + 1L]] <- c(
    "Absolute risk difference (High\u2212Low), %", "", "", sprintf("%.2f", ar$rd_pct), ""
  )
  t2_rows[[length(t2_rows) + 1L]] <- c(
    "NNT (=1/|RD|)", "", "", sprintf("%.1f", ar$nnt), ""
  )
  .abs_notes <- c(.abs_notes, sprintf(
    "%s: observed deaths Low=%d/%d (%.2f%%), High=%d/%d (%.2f%%); RD=%.2f%%; NNT=%.1f.",
    idx, ar$deaths_low, ar$n_low, ar$risk_low_pct,
    ar$deaths_high, ar$n_high, ar$risk_high_pct, ar$rd_pct, ar$nnt
  ))
}
body2 <- as.data.frame(do.call(rbind, t2_rows), stringsAsFactors = FALSE)
names(body2) <- c(
  "Variable", "Participants", "Observed deaths (n)", "Cumulative incidence (%)",
  "Per 100 person-year (95% CI)"
)
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 2. Incidence of all-cause mortality.xlsx"),
  title = "Table 2. Incidence of all-cause mortality",
  df_body = body2,
  footnotes = c(
    "Observed deaths (n) are counted from the 365-day landmark fustatus on the analytic sample (not back-calculated from percentages).",
    "Cumulative incidence (%) = observed deaths / participants within the group.",
    "Absolute risk difference and NNT are shown under Cumulative incidence (%); other cells in those rows are intentionally blank.",
    "Absolute risk difference = High minus Low cumulative incidence; NNT = 1/|RD| (crude, unadjusted).",
    .abs_notes,
    "Per 100 person-year is events / person-years x 100. Interval is the exact Poisson 95% CI.",
    sprintf(
      "P for trend is from an unadjusted Poisson model with %s coded 1-%d.",
      .qsc_meta$legend_title, .qsc_meta$n_groups
    ),
    "Primary outcome: all-cause death within 365 days after ICU admission.",
    quantile_scheme_footnote_lines(.qsc)
  )
)
message("Table 2 OK")
print(body2)

message("==== Methods + software versions (exclude cmprsk) ====")
cmd <- sprintf(
  paste(
    "Rscript %s --dir %s --study-type prognosis_v2",
    "--prune-only=FALSE"
  ),
  shQuote(file.path(.engine, "run/pub/finalize_delivery_root.R")),
  shQuote(.out)
)
# finalize_delivery_root 用命令行参数；直接 source 调用更稳
Sys.setenv(PV2_PROFILE = "hip_aki")
args_bak <- commandArgs
# 直接写 methods + software
source(file.path(.engine, "R/pub_prognosis_v2_methods.R"), local = FALSE)
source(file.path(.engine, "R/pub_software_versions.R"), local = FALSE)
cfg <- list(
  project = list(
    pv2_profile = "hip_aki",
    cohort = "adults aged 65 years or older with hip arthroplasty and AKI",
    databases = "MIMIC-IV",
    exposure = "SIRI and PIV",
    analysis_group = "365-day all-cause mortality",
    model3_covs = "Age, Gender, CHARLSON",
    grouping = "binary (High vs Low)",
    sensitivity = "90-day all-cause mortality (Table S5)",
    mediator = "OASIS"
  ),
  software_versions = list(
    extra_pkgs = c(
      "mice", "survival", "rms", "car", "pROC", "Boruta", "fastshap",
      "ggplot2", "patchwork", "openxlsx", "data.table", "tableone", "mediation"
    ),
    exclude_pkgs = c("cmprsk")
  )
)
writeLines(pub_prognosis_v2_methods_lines(cfg), file.path(.out, "Methods_statistical_analysis.md"), useBytes = TRUE)
pub_write_software_versions(index_root = .out, config = cfg)
# append Software section
roles <- c(
  mice = "Multiple imputation (m = 5; Rubin pool for Cox)",
  survival = "Cox / Kaplan-Meier / cox.zph",
  rms = "Restricted cubic splines",
  car = "Variance inflation factors",
  Boruta = "Feature confirmation",
  pROC = "ROC / AUC / Youden",
  ggplot2 = "Publication figures",
  patchwork = "Multi-panel figures",
  openxlsx = "SCI three-line xlsx",
  tableone = "Baseline Table 1 helpers / SMD reference",
  mediation = "Mediation path models"
)
soft_tmp <- tempfile(fileext = ".md")
pub_write_methods_software_section(
  out_path = soft_tmp, roles = roles,
  extra_pkgs = cfg$software_versions$extra_pkgs,
  append_to = file.path(.out, "Methods_statistical_analysis.md")
)
# strip cmprsk if software section collector reintroduced it via core list
md <- readLines(file.path(.out, "Methods_statistical_analysis.md"), warn = FALSE)
md <- md[!grepl("\\bcmprsk\\b", md, ignore.case = TRUE)]
writeLines(md, file.path(.out, "Methods_statistical_analysis.md"), useBytes = TRUE)
txt <- readLines(file.path(.out, "Methods_software_versions.txt"), warn = FALSE)
txt <- txt[!grepl("\\bcmprsk\\b", txt, ignore.case = TRUE)]
writeLines(txt, file.path(.out, "Methods_software_versions.txt"), useBytes = TRUE)
message("DONE: ", .out)
