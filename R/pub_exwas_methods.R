# 环境暴露 / ExWAS（泛癌毒物）发表 Methods + 软件版本（引擎级）
# 交付面禁止写迁移复现 / 对齐某文 / 作者名对照。

exwas_pancancer_methods_lines <- function(n_total = 11098L,
                                          n_cases = 1070L,
                                          n_exp = 63L,
                                          n_fam = 9L,
                                          model2 = c("sex", "race/ethnicity",
                                                     "poverty income ratio",
                                                     "alcohol use", "eGFR"),
                                          age_cut = 65L) {
  m2 <- paste(model2, collapse = ", ")
  c(
    "# Methods — Statistical analysis",
    "",
    "## Study population",
    paste0(
      "Adults aged ≥20 years were drawn from multi-cycle NHANES with environmental toxicant ",
      "linkage. Ever cancer was defined by MCQ220 (case = 1; control = 2). Participants were ",
      "excluded for missing or non-positive urinary creatinine, missing or non-positive WTSA2YR, ",
      "or missingness in more than one-third of the cycle toxicant panel. The analytic sample ",
      "comprised n = ", format(as.integer(n_total), big.mark = ","),
      " (cancer cases = ", format(as.integer(n_cases), big.mark = ","), ")."
    ),
    "",
    "## Toxicant processing",
    paste0(
      "Up to ", n_exp, " toxicants across ", n_fam, " chemical families entered ExWAS after ",
      "LOD screening (drop if missing >40% or under-LOD >90%; binary if under-LOD >30%; otherwise ",
      "natural-log transform) and urinary creatinine adjustment for urine analytes."
    ),
    "",
    "## Exposome-wide association study",
    paste0(
      "Primary ExWAS used unweighted logistic regression with odds ratios (ORs) per interquartile ",
      "range (IQR) for continuous exposures. Covariates were multiply imputed (MICE, m = 5, ",
      "maxit = 5, seed = 123456) with estimates pooled by Rubin's rules. Multiple testing was ",
      "controlled by Benjamini–Hochberg false discovery rate (FDR). Model 1 was unadjusted. ",
      "Model 2 used a literature-informed DAG candidate pool screened by univariate P < 0.05, ",
      "VIF < 4, and stepwise AIC, yielding: ", m2, ". Smoking status was omitted from the main ",
      "Model 2 and evaluated in sensitivity analyses (additional smoking adjustment; never-smokers). ",
      "Age was used for stratification (cut ", age_cut, " years), not as a Model 2 adjuster."
    ),
    "",
    "## Environmental risk score and mixtures",
    paste0(
      "An environmental risk score (ERS) was constructed by adaptive elastic-net (gcdnet) with ",
      "bootstrap inclusion (B = 1000; seed = 123456; α = 0.9). Survey-weighted logistic models ",
      "(WTSA2YR) estimated ERS–cancer associations (continuous per IQR and High vs Low) under the ",
      "same Model 2 set. Dose–response used a linear OR curve relative to the median with a ",
      "nonlinearity check. Weighted quantile sum (WQS) regression (gWQS, q = 4, bootstrap = 1000) ",
      "summarized mixture weights on the full screened panel."
    ),
    "",
    "## Sensitivity and stratified analyses",
    "Survey-weighted ExWAS, Model 2 plus smoking, never-smoker ExWAS, and sex-/age-stratified ExWAS were reported as sensitivity or stratified analyses.",
    "",
    "## Mediation (exploratory)",
    paste0(
      "Exploratory mediation used the R mediation package (B = 1000) on the risk-difference scale ",
      "with a probit outcome link for medsens surfaces. Clinical mediators with significant ",
      "indirect effects under Model 2 were retained. Analyses are exploratory."
    ),
    "",
    "## Numerical reporting",
    paste0(
      "ORs, 95% CIs, E-values, and mediation coefficients are reported to three decimal places; ",
      "P and FDR q values to three decimal places with values <0.001 shown as <0.001; descriptive ",
      "medians/IQRs to at most three decimals (trailing zeros trimmed); mixture weights to three ",
      "decimals. Counts use thousands separators."
    ),
    "",
    "## Software",
    "Analyses were performed in R. Package versions are listed in Methods_software_versions.txt and below."
  )
}

exwas_write_methods_md <- function(path, ...) {
  writeLines(exwas_pancancer_methods_lines(...), path)
  invisible(path)
}

exwas_write_software_versions <- function(path, extra = character(0)) {
  pkgs <- c(
    "mice", "survey", "glmnet", "gcdnet", "gWQS", "mediation",
    "ggplot2", "ggrepel", "haven", "splines", "car", "openxlsx", "data.table"
  )
  lines <- c(
    "Software versions (R packages used in this analysis)",
    paste0("R: ", paste(R.version$major, R.version$minor, sep = ".")),
    ""
  )
  for (pk in pkgs) {
    ver <- tryCatch(as.character(utils::packageVersion(pk)), error = function(e) NA_character_)
    if (is.finite(match(TRUE, TRUE)) && !is.na(ver)) {
      lines <- c(lines, sprintf("%s: %s", pk, ver))
    }
  }
  if (length(extra)) lines <- c(lines, "", extra)
  lines <- c(
    lines, "",
    "Display: Times New Roman (tables); Times-family serif for figures.",
    "Digit rules: R/exwas_pub_digits.R (OR/CI/E-value/P/q = 3 decimals)."
  )
  writeLines(lines, path)
  invisible(path)
}
