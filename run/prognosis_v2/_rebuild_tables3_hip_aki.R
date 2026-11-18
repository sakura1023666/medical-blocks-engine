#!/usr/bin/env Rscript
# 薄封装：Hip AKI Table S3（Model 4 = Table3 Model3 + comorbidity count）
# 宽表核心仍走引擎；Model4 为单列 HR|P（文献 S3 版式）
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/cox_gate.R", local = FALSE)
source("R/quantile_scheme_cascade.R", local = FALSE)
source("R/pv2_literature_pub_tables.R", local = FALSE)
source("run/prognosis_v2/pv2_mi_cox.R", local = FALSE)

.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.tab <- file.path(.out, "Tables")
.ws <- pv2_resolve_delivery_workspace(.out)
d <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
mids <- tryCatch(readRDS(file.path(.ws, "imputed_mids.rds"))$MIMIC, error = function(e) NULL)
if (!"futime_years" %in% names(d)) d$futime_years <- d$futime / 365.25
d$fustatus <- as.integer(d$fustatus)
d$Gender <- factor(d$Gender)

cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE, try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05, pass_rule = "all", family = "cox",
  time_var = "futime_years", event_var = "fustatus"
))
resolved <- quantile_scheme_resolve_cascade(d, c("SIRI", "PIV"), config = cfg)
d <- quantile_scheme_attach_groups(d, resolved)
meta <- resolved$meta
sch <- resolved$scheme

comorb_vars <- c(
  "Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
  "Stroke", "COPD", "Pneumonia", "Malignant_Tumor"
)
d$comorb_n <- rowSums(sapply(comorb_vars, function(v) {
  if (!v %in% names(d)) return(rep(0L, nrow(d)))
  as.integer(as.character(d[[v]]) %in% c("Yes", "1", "TRUE"))
}))

m4_cov <- c("Age", "Gender", "CHARLSON", "comorb_n")
get_row <- function(expo, term_pat) {
  rhs <- paste(c(expo, m4_cov), collapse = " + ")
  res <- tryCatch(
    pv2_cox_extract(
      d, rhs, mids = mids, time_var = "futime_years", event_var = "fustatus",
      exposure_keep = c(
        "SIRI", "PIV", "SIRI_Group", "PIV_Group", "SIRI_z", "PIV_z",
        "comorb_n", "qnum"
      ),
      rubin = !is.null(mids)
    ),
    error = function(e) NULL
  )
  if (is.null(res) || !nrow(res)) return(c(HR = "", P = ""))
  r <- res[grepl(term_pat, res$term), , drop = FALSE]
  if (!nrow(r)) return(c(HR = "", P = ""))
  c(HR = pv2_hr_cell(r$hr[1], r$lo[1], r$hi[1]), P = pv2_fmt_p(r$p[1]))
}
get_trend <- function(idx) {
  qv <- paste0(idx, "_Group")
  dd <- d
  dd$qnum <- as.integer(dd[[qv]])
  rhs <- paste(c("qnum", m4_cov), collapse = " + ")
  fit <- tryCatch(
    survival::coxph(stats::as.formula(paste("Surv(futime_years, fustatus) ~", rhs)), data = dd),
    error = function(e) NULL
  )
  if (is.null(fit)) return("")
  sm <- summary(fit)$coefficients
  if (!"qnum" %in% rownames(sm)) return("")
  pv2_fmt_p(sm["qnum", "Pr(>|z|)"])
}

rows <- list()
for (idx in c("SIRI", "PIV")) {
  d[[paste0(idx, "_z")]] <- as.numeric(scale(d[[idx]]))
  rows[[length(rows) + 1L]] <- c(Variable = idx, HR = "", P = "")
  z <- get_row(paste0(idx, "_z"), "_z")
  rows[[length(rows) + 1L]] <- c(Variable = paste0("  ", idx, " (per 1 SD)"), HR = z["HR"], P = z["P"])
  rows[[length(rows) + 1L]] <- c(
    Variable = quantile_scheme_level_display(meta$ref, sch), HR = "Reference", P = ""
  )
  for (lv in meta$labels[-1L]) {
    r <- get_row(paste0(idx, "_Group"), lv)
    rows[[length(rows) + 1L]] <- c(
      Variable = quantile_scheme_level_display(lv, sch), HR = r["HR"], P = r["P"]
    )
  }
  rows[[length(rows) + 1L]] <- c(Variable = "  P for trend", HR = "", P = get_trend(idx))
}
body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
names(body) <- c("Variable", "HR (95% CI)", "P")
for (f in list.files(.tab, pattern = "^Table S3\\.", full.names = TRUE)) unlink(f)
path <- file.path(.tab, "Table S3. Cox model including comorbidity count (Model 4).xlsx")
sci_xlsx_single_header_booktabs(
  path,
  title = "Table S3. Cox model including comorbidity count (Model 4)",
  df_body = body,
  footnotes = c(
    "Model 4 further adjusts the Table 3 Model 3 set by adding a comorbidity count (0-8).",
    "Comorbidities counted: Hypertension, Diabetes, Heart Failure, Myocardial Infarction, Stroke, COPD, Pneumonia, Malignant tumor.",
    "Analogous to the reference Table S3; this cohort has no CKM stage, so comorbidity count is used.",
    "The Model 4 covariates are: Age, Gender, CHARLSON, comorbidity count.",
    sprintf("Exposure grouping aligned with Table 3: %s (%s).", meta$footnotes_scheme, meta$contrast_lab),
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules when mids are available."
  ),
  level_row_idx = which(startsWith(body$Variable, "  ")) + 1L
)
message("OK ", path)
