###############################################################################
#  cross_lagged_methods_pub.R — 交叉滞后课题 Methods md（引擎复用）
###############################################################################

#' 交叉滞后（虚弱条目 / 汇总 FI × 疾病）Methods 正文行
#' @param config 可选；读 project$analysis_group / databases / exposure
#' @return character 行向量（含标题）
cross_lagged_methods_statistical_lines <- function(config = NULL) {
  cfg <- config %||% list()
  proj <- cfg$project %||% list()
  outcome <- as.character(
    proj$analysis_group %||% proj$disease %||% "the study outcome"
  )[1L]
  exposure <- as.character(proj$exposure %||% "Frailty Index")[1L]
  dbs <- proj$databases %||% proj$cohorts %||% c("CHARLS", "ELSA", "HRS")
  dbs <- paste(as.character(dbs), collapse = ", ")

  c(
    "# Statistical analysis",
    "",
    paste0(
      "Participants were drawn from ", dbs,
      ". Baseline cross-sectional analyses used the first analytic wave after ",
      "inclusion/exclusion (Figure 1). Longitudinal change and cross-lagged ",
      "panel network (CLPN) analyses used two-wave wide tables (T1_/T2_)."
    ),
    "",
    "## Exposure and outcome",
    paste0(
      "The primary exposure was the ", exposure,
      " (mean of deficit items). When the outcome was hypertension, the ",
      "hypertension deficit item (hibpe) was excluded from the FI score and ",
      "from the CLPN frailty-item node set to avoid counting the outcome twice. ",
      "Blood lipids (triglycerides, HDL cholesterol) were not treated as ",
      "frailty deficits in the CLPN."
    ),
    paste0(
      "The outcome was ", outcome,
      ". Baseline tables report prevalent disease; change and CLPN models ",
      "use incident or follow-up status as defined in the study config."
    ),
    "",
    "## Descriptive and association models",
    paste0(
      "Continuous variables were summarized as mean (SD) or median (IQR); ",
      "categorical variables as n (%). Between-group tests followed the ",
      "engine Table 1 rules. Logistic models related FI (continuous and ",
      "quartiles; lowest quartile as reference) to ", outcome,
      ". Model 1 / Model 2 covariates are listed in the Table 2 footnotes. ",
      "Restricted cubic splines, ROC curves, and subgroup forests used the ",
      "same analytic sample and FI definition unless a sensitivity scenario ",
      "is named in the table title."
    ),
    "",
    "## Change analysis and mediation",
    "Mean FI and FI change tables followed the main logistic grouping scheme. ",
    "Cross-sectional mediation (exposure → BMI → outcome) used the product-of-coefficients ",
    "framework with bootstrap intervals when the mediation block exported tables. ",
    "A negative proportion mediated indicates suppression, not classical mediation.",
    "",
    "## Cross-lagged panel network",
    paste0(
      "CLPN edge weights were estimated with regularized regression (glmnet) of ",
      "each T2 node on all T1 nodes (and Age when included in the estimation script). ",
      "Binary nodes used binomial family; others used Gaussian. Coefficients with ",
      "|β| > 5 were set to 0. For plotting, weights were transformed to odds ratios ",
      "(exp(β)); self-loops were omitted; edges with OR in (0.95, 1.05) were omitted. ",
      "Networks were drawn with qgraph (spring layout, repulse.rad = 80). ",
      "Edge colour encodes OR > 1 vs OR < 1; line width and opacity scale with |log OR|."
    ),
    "",
    "## Sensitivity analyses",
    "Named sensitivity tables (exclude ≥2 chronic conditions; complete-case ",
    "unimputed; exclude events within 2 years) reused the main logistic and ",
    "change specifications on the restricted sample.",
    "",
    "Software versions are listed in Methods_software_versions.txt and the Software subsection below.",
    ""
  )
}
