#!/usr/bin/env Rscript
# Table S12 → 对齐原文 Supplementary Table 12 四列版式：
# Aspect | Previous Studies | Current Study | Advancement/Novelty
# 内容按本泛癌分析写实（n、毒物数、类别数）；交付面不写参考作者名。
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s12_dong_style.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
sum_tab <- file.path(BASE, "summary_results", "Tables")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)

# ---- 写实参数（可从产物推断）----
n_total <- 11098L
n_exp <- 63L
n_fam <- 9L
s7 <- file.path(src_tab, "Table S7. ExWAS survey-weighted.csv")
if (file.exists(s7)) {
  d <- utils::read.csv(s7, stringsAsFactors = FALSE, check.names = FALSE)
  n_exp <- nrow(d)
  if ("family" %in% names(d)) {
    n_fam <- length(unique(stats::na.omit(as.character(d$family))))
  }
}
t1 <- file.path(sum_tab, "Table 1. Baseline characteristics by cancer status.xlsx")
# Table1 标题已含 n；保持默认 11098 即可

body <- data.frame(
  Aspect = c(
    "Study Design",
    "Analytical Approach",
    "Exposure Assessment",
    "Population Representation",
    "Statistical Power",
    "Methodological Rigor"
  ),
  `Previous Studies` = c(
    "Mostly focused on single or limited classes of environmental toxicants",
    "Primarily single-pollutant models; limited handling of multicollinearity",
    "Targeted analysis of specific chemical classes",
    "Varied sampling methods, often limited in generalizability",
    "Limited by smaller sample sizes and selective exposure assessment",
    "Limited adjustment for multiple testing in most studies"
  ),
  `Current Study` = c(
    sprintf(
      paste0(
        "Comprehensive exposome-wide association study of environmental toxicants ",
        "with pan-cancer (self-reported ever cancer), examining %d toxicants across %d categories"
      ),
      n_exp, n_fam
    ),
    paste0(
      "Advanced statistical methods including adaptive elastic-net environmental risk score (ERS) ",
      "and weighted quantile sum (WQS) regression, alongside single-toxicant ExWAS"
    ),
    paste0(
      "Systematic evaluation of diverse environmental exposures including metals, ",
      "volatile organic compound metabolites, polycyclic aromatic hydrocarbons, ",
      "aromatic amines, arsenic species, and related contaminant classes"
    ),
    paste0(
      "Uses nationally representative NHANES multi-cycle data with complex survey design; ",
      "main ExWAS reported unweighted with survey-weighted and smoking-related sensitivity analyses"
    ),
    sprintf(
      "Leverages a large analytic sample (n=%s) with comprehensive exposure assessment",
      format(n_total, big.mark = ",")
    ),
    paste0(
      "Implements Benjamini–Hochberg false discovery rate (FDR) correction and ",
      "comprehensive sensitivity analyses (survey weighting, additional smoking adjustment, ",
      "never-smokers, stratified ExWAS)"
    )
  ),
  `Advancement/Novelty` = c(
    "Provides a systematic, unbiased assessment of multiple simultaneous exposures in relation to pan-cancer",
    "Effectively addresses multicollinearity and assesses combined effects of environmental mixtures",
    "Captures the real-world complexity of co-exposure to multiple environmental toxicants",
    "Enhances generalizability of findings to the U.S. adult population",
    "Increases detection power for identifying true associations",
    "Reduces false positive findings and enhances result robustness"
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

title <- paste0(
  "Table S12. Comparison of methodological approaches between previous studies ",
  "and the current investigation."
)
footnotes <- c(
  sprintf(
    "Current study: NHANES adults aged \u226520 years; analytic n=%s; pan-cancer outcome; %d toxicants in %d families.",
    format(n_total, big.mark = ","), n_exp, n_fam
  ),
  "Main ExWAS used unweighted logistic models with BH-FDR; ERS associations used survey weights (WTSA2YR).",
  "Abbreviation: ExWAS, exposome-wide association study; ERS, environmental risk score; WQS, weighted quantile sum; FDR, false discovery rate."
)

out_xlsx <- file.path(sum_tab, "Table S12. Comparison of methodological approaches.xlsx")
# 兼容旧文件名：写新名并删旧「Methodological comparison」壳表
old_xlsx <- file.path(sum_tab, "Table S12. Methodological comparison.xlsx")

sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S12",
  footnotes = footnotes
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

# 表头加粗；正文左对齐换行友好
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  hdr <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", textDecoration = "bold",
    wrapText = TRUE, valign = "center", halign = "center"
  )
  body_st <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    wrapText = TRUE, valign = "top", halign = "left"
  )
  openxlsx::addStyle(wb, sh, hdr, rows = 2, cols = 1:4, gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, sh, body_st, rows = 3:(2 + nrow(body)), cols = 1:4, gridExpand = TRUE, stack = TRUE)
  openxlsx::setRowHeights(wb, sh, rows = 3:(2 + nrow(body)), heights = 48)
  openxlsx::setColWidths(wb, sh, cols = 1:4, widths = c(22, 36, 42, 36))
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

utils::write.csv(body, file.path(src_tab, "Table S12. Methodological comparison Dong layout.csv"),
                 row.names = FALSE)
utils::write.csv(body, file.path(src_tab, "Table S12. Methodological comparison.csv"),
                 row.names = FALSE)

if (file.exists(old_xlsx) && !identical(normalizePath(old_xlsx), normalizePath(out_xlsx))) {
  unlink(old_xlsx)
}

message("[s12] n=", n_total, " exp=", n_exp, " fam=", n_fam)
message("[s12] wrote ", out_xlsx)
message("[s12] DONE")
