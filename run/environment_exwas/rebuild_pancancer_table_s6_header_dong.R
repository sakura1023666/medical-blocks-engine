#!/usr/bin/env Rscript
# Table S6 双行表头对齐 Dong Supplementary Table 6：
# Mediator | Indirect effect [β (95% CI) | P] | Direct … | Total … | Proportion (%)
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
sum_tab <- file.path(BASE, "summary_results/Tables")
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/Tables")
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)

raw <- utils::read.csv(
  file.path(out_ds, "Table_S6_mediation_clinical_dong.csv"),
  stringsAsFactors = FALSE
)
keep <- c("TotalProtein", "Albumin")
raw <- raw[match(keep, raw$mediator), , drop = FALSE]
if (nrow(raw) != 2L || anyNA(raw$mediator)) {
  stop("需要 TotalProtein/Albumin 的 B=1000 结果", call. = FALSE)
}
lab <- c(TotalProtein = "Total protein", Albumin = "Albumin")
raw$mediator_lab <- unname(lab[raw$mediator])

.fmt_num3 <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x)) return("")
  if (abs(x) > 0 && abs(x) < 0.001) return(sprintf("%.2e", x))
  sprintf("%.3f", x)
}
.fmt_est_ci <- function(est, lo, hi) {
  est <- as.numeric(est); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(est)) return("")
  sprintf("%s (%s, %s)", .fmt_num3(est), .fmt_num3(lo), .fmt_num3(hi))
}
.fmt_p <- function(p) pub_format_p(as.numeric(p))
.fmt_prop <- function(prop) {
  x <- 100 * as.numeric(prop)
  if (!is.finite(x)) return("")
  sprintf("%.3f", x)
}

ide <- mapply(.fmt_est_ci, raw$IDE, raw$IDE_lo, raw$IDE_hi)
de <- mapply(.fmt_est_ci, raw$DE, raw$DE_lo, raw$DE_hi)
te <- mapply(.fmt_est_ci, raw$Total, raw$Total_lo, raw$Total_hi)
body <- data.frame(
  c1 = raw$mediator_lab,
  c2 = ide,
  c3 = vapply(raw$IDE_p, .fmt_p, character(1)),
  c4 = de,
  c5 = vapply(raw$DE_p, .fmt_p, character(1)),
  c6 = te,
  c7 = vapply(raw$Total_p, .fmt_p, character(1)),
  c8 = vapply(raw$Prop, .fmt_prop, character(1)),
  stringsAsFactors = FALSE
)

beta_ci <- paste0("\u03b2", " (95% CI)")
h1 <- c(
  "Mediator",
  "Indirect effect", "Indirect effect",
  "Direct effect", "Direct effect",
  "Total effect", "Total effect",
  "Proportion of mediation"
)
h2 <- c(
  NA,
  beta_ci, "P",
  beta_ci, "P",
  beta_ci, "P",
  "(%)"
)

title <- paste0(
  "Table S6. The mediating roles of clinical biomarkers in association ",
  "between environmental risk score and pan-cancer."
)
covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
footnotes <- c(
  "Effects are on the risk-difference scale from R mediation::mediate with bootstrap B = 1000 (percentile CI); treatment = ERS per IQR; outcome = pan-cancer.",
  paste0("Model 2 covariates (locked with Figure 4): ", paste(covars_m2, collapse = ", "), "."),
  "Mediator panel locked by significance under the current ERS (IDE P<0.05): Total protein and Albumin (nutrition/hepatic protein pathway).",
  "Mediators: Total protein and Albumin.",
  "Dong inflammatory biomarkers and Creatinine (eGFR overlap) were evaluated but not retained for the primary panel.",
  "Survey weights WTSA2YR entered as glm/lm weights normalized to mean 1.",
  "Header: Indirect effect, Direct effect, Total effect, and Proportion of mediation."
)

out_xlsx <- file.path(sum_tab, "Table S6. Mediation clinical biomarkers.xlsx")
.sci_xlsx_double_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  h1 = h1,
  h2 = h2,
  sheet = "Table S6",
  footnotes = footnotes,
  col_widths = c(14, 26, 10, 26, 10, 26, 10, 14),
  body_center_all = FALSE
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

body_csv <- data.frame(
  Mediator = raw$mediator_lab,
  Indirect_beta_CI = ide,
  Indirect_P = body$c3,
  Direct_beta_CI = de,
  Direct_P = body$c5,
  Total_beta_CI = te,
  Total_P = body$c7,
  Proportion_pct = body$c8,
  stringsAsFactors = FALSE
)
utils::write.csv(
  body_csv,
  file.path(src_tab, "Table S6. Mediation clinical Dong layout.csv"),
  row.names = FALSE
)

d <- openxlsx::read.xlsx(out_xlsx, sheet = 1, colNames = FALSE)
message("header check:")
print(d[1:4, , drop = FALSE])
message("wrote ", out_xlsx)
message("DONE")
