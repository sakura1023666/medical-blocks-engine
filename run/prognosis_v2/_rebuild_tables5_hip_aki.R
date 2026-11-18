#!/usr/bin/env Rscript
# 薄封装：Hip AKI Table S5（90 天终点宽表）→ 引擎 R/pv2_literature_pub_tables.R
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
d0 <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$fustatus <- as.integer(d0$fustatus)
d0$Gender <- factor(d0$Gender)

cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE, try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05, pass_rule = "all", family = "cox",
  time_var = "futime_years", event_var = "fustatus"
))
resolved <- quantile_scheme_resolve_cascade(d0, c("SIRI", "PIV"), config = cfg)
d0 <- quantile_scheme_attach_groups(d0, resolved)
d <- pv2_censor_at_days(d0, 90L)
d <- quantile_scheme_attach_groups(d, resolved)
message(sprintf("S5: 90-day N=%d deaths=%d scheme=%s", nrow(d), sum(d$fustatus == 1L), resolved$scheme))

body <- pv2_cox_wide_m123_body(d, c("SIRI", "PIV"), resolved, mids = NULL, rubin = FALSE)
print(body)
olds <- list.files(.tab, pattern = "^Table S5\\.", full.names = TRUE)
for (f in olds) unlink(f)
path <- file.path(.tab, "Table S5. Sensitivity analysis using 90-day all-cause mortality.xlsx")
pv2_write_cox_wide_xlsx(
  path,
  title = "Table S5. Sensitivity analysis of the association between inflammatory indices and 90-day all-cause mortality",
  body = body,
  footnotes = c(
    "Layout aligned with reference Table S5 (Variable | Model 1-3 effect estimates with P; continuous per 1 SD and grouped contrasts).",
    "Reference Table S5 used Fine-Gray models for cardiovascular mortality; cause of death is unavailable in MIMIC-IV.",
    "This sensitivity redefines the endpoint as all-cause death within 90 days after ICU admission (follow-up censored at 90 days); the primary analysis remains 365-day all-cause mortality (Table 3).",
    sprintf("Analytic N = %d; 90-day deaths = %d.", nrow(d), sum(d$fustatus == 1L)),
    pv2_table3_covariate_footnotes(),
    sprintf(
      "Exposure grouping cut-points aligned with Table 3 via quantile_scheme_cascade: %s (%s).",
      resolved$meta$footnotes_scheme, resolved$meta$contrast_lab
    ),
    "Estimates use the first completed imputed dataset (operational layer)."
  )
)
message("OK ", path)
