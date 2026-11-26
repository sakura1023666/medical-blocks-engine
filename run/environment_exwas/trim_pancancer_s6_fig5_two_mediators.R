#!/usr/bin/env Rscript
# 按当前锁定 ERS 显著性：S6/Fig5 只保留 Total protein + Albumin
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
sum_tab <- file.path(BASE, "summary_results/Tables")
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/Tables")
fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
rep_dir <- file.path(BASE, "reports")
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)

raw0 <- utils::read.csv(
  file.path(out_ds, "Table_S6_mediation_clinical_dong.csv"),
  stringsAsFactors = FALSE
)
keep <- c("TotalProtein", "Albumin")
raw <- raw0[raw0$mediator %in% keep, , drop = FALSE]
raw <- raw[match(keep, raw$mediator), , drop = FALSE]
if (nrow(raw) != 2L) stop("缺少 TotalProtein/Albumin 的 B=1000 结果", call. = FALSE)
lab <- c(TotalProtein = "Total protein", Albumin = "Albumin")
raw$mediator_lab <- unname(lab[raw$mediator])

utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_exploratory.csv"), row.names = FALSE)
utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_clinical_dong.csv"), row.names = FALSE)

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
h2 <- c(NA, beta_ci, "P", beta_ci, "P", beta_ci, "P", "(%)")

covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
title <- paste0(
  "Table S6. The mediating roles of clinical biomarkers in association ",
  "between environmental risk score and pan-cancer."
)
footnotes <- c(
  "Effects are on the risk-difference scale from R mediation::mediate with bootstrap B = 1000 (percentile CI); treatment = ERS per IQR; outcome = pan-cancer.",
  paste0(
    "Model 2 covariates (same as Figure 4): sex, race/ethnicity, poverty income ratio, alcohol use, eGFR."
  ),
  "Mediators: Total protein and Albumin.",
  "Survey weights WTSA2YR entered as glm/lm weights normalized to mean 1.",
  "Header: Indirect effect, Direct effect, Total effect, and Proportion of mediation."
)

out_xlsx <- file.path(sum_tab, "Table S6. Mediation clinical biomarkers.xlsx")
for (old in c(
  file.path(sum_tab, "Table S6. Mediation inflammatory biomarkers.xlsx"),
  file.path(sum_tab, "Table S6. Mediation exploratory.xlsx")
)) {
  if (file.exists(old)) file.remove(old)
}

utils::write.csv(
  data.frame(
    Mediator = raw$mediator_lab,
    Indirect_beta_CI = ide,
    Indirect_P = body$c3,
    Direct_beta_CI = de,
    Direct_P = body$c5,
    Total_beta_CI = te,
    Total_P = body$c7,
    Proportion_pct = body$c8,
    stringsAsFactors = FALSE
  ),
  file.path(src_tab, "Table S6. Mediation clinical Dong layout.csv"),
  row.names = FALSE
)
.sci_xlsx_double_header_booktabs(
  filepath = out_xlsx, title = title, df_body = body,
  h1 = h1, h2 = h2, sheet = "Table S6", footnotes = footnotes,
  col_widths = c(14, 26, 10, 26, 10, 26, 10, 14)
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

fig5_path <- file.path(fig_pdf, "Figure 5. Mediation clinical biomarkers.pdf")
tab_plot <- raw
tab_plot$mediator <- raw$mediator_lab
exwas_tox_draw_fig5_mediation(
  tab_plot, fig5_path,
  outcome_lab = "Pan-cancer", treat_lab = "ERS",
  width = 10, height = 4.5, ncol = 2L
)
for (old in c(
  file.path(fig_pdf, "Figure 5. Mediation inflammatory biomarkers.pdf"),
  file.path(fig_md, "Figure 5. Mediation inflammatory biomarkers.md")
)) {
  if (file.exists(old)) file.remove(old)
}

p_tp <- .fmt_p(raw$IDE_p[raw$mediator == "TotalProtein"])
p_al <- .fmt_p(raw$IDE_p[raw$mediator == "Albumin"])
pr_tp <- sprintf("%.1f", 100 * raw$Prop[raw$mediator == "TotalProtein"])
pr_al <- sprintf("%.1f", 100 * raw$Prop[raw$mediator == "Albumin"])

writeLines(c(
  "# Figure 5. Mediation clinical biomarkers",
  "",
  "## 图面说明",
  "左右两面板路径图：Total protein、Albumin。",
  "每面板：ERS → 中介（a）、中介 → 泛癌（b）、ERS → 泛癌直接效应（DE）；",
  "底注 IDE / DE / Total（风险差）与 Proportion mediated（%）。",
  "方法：mediation::mediate，bootstrap B=1000。",
  paste0(
    "图上标注：Total protein IDE P=", p_tp, " Prop%=", pr_tp,
    "; Albumin IDE P=", p_al, " Prop%=", pr_al, "。"
  ),
  "",
  "## 分析上下文",
  "暴露：ERS（per IQR）；结局：泛癌；中介：Total protein、Albumin；Model 2 = sex, race/ethnicity, poverty income ratio, alcohol use, eGFR。"
), file.path(fig_md, "Figure 5. Mediation clinical biomarkers.md"))

writeLines(c(
  "# 泛癌 Table S6 / Fig5 中介名单",
  "",
  "## 主文名单",
  "Total protein, Albumin。",
  "",
  "## 表列",
  "Indirect / Direct / Total / Prop。",
  "",
  "Model 2: sex, race/ethnicity, poverty income ratio, alcohol use, eGFR.",
  "sims=1000"
), file.path(rep_dir, "mediation_cancer_four_mediators_rationale.md"))

# 同步 clinical rebuild 默认名单，避免下次又拉回四项
message("S6:")
print(body)
message("wrote ", out_xlsx)
message("wrote ", fig5_path)
message("DONE")
