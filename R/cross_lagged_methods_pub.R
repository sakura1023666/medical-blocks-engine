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
  age_filter <- as.character(
    cfg$data_clean$age_filter %||% proj$age_filter %||% ""
  )[1L]
  age_block <- character(0)
  if (nzchar(age_filter)) {
    age_block <- c(
      "",
      "## Cohort age restriction",
      paste0(
        "The analytic sample was restricted by ", age_filter,
        " at baseline (non-finite ages excluded). ",
        "Separate deliveries may be produced for alternative age cutoffs."
      )
    )
  }
  med_cov <- cfg$mediation$shared_model2 %||% cfg$mediation$model2_factors %||%
    c("Age", "Alcohol drinking")
  med_cov <- paste(vapply(as.character(med_cov), function(x) {
    if (exists("pipeline_display_label", mode = "function")) {
      pipeline_display_label(x)
    } else {
      gsub("_", " ", x, fixed = TRUE)
    }
  }, character(1)), collapse = ", ")

  c(
    "# Statistical analysis",
    "",
    paste0(
      "Participants were drawn from ", dbs,
      ". Baseline cross-sectional analyses used the first analytic wave after ",
      "inclusion/exclusion (Figure 1). Longitudinal change and cross-lagged ",
      "panel network (CLPN) analyses used adjacent survey waves."
    ),
    age_block,
    "",
    "## Exposure and outcome",
    paste0(
      "The primary exposure was the ", exposure,
      " (mean of deficit items; Rockwood cumulative-deficit Frailty Index on a 0–1 scale). ",
      "When the outcome was hypertension, the hypertension deficit item was excluded ",
      "from the FI score and from the CLPN frailty-item node set to avoid counting ",
      "the outcome twice. Blood lipids (triglycerides, HDL cholesterol) were not ",
      "treated as frailty deficits in the CLPN."
    ),
    paste0(
      "The outcome was ", outcome,
      ". Baseline tables report disease status in the analytic sample; change and ",
      "CLPN models use follow-up status as defined in the study config."
    ),
    "",
    "## Descriptive and association models",
    paste0(
      "Continuous variables were summarized as mean (SD) or median (IQR); ",
      "categorical variables as n (%). Between-group tests followed the ",
      "engine Table 1 rules. Logistic models related FI (continuous and ",
      "tertiles; lowest tertile as reference) to ", outcome,
      ". Continuous FI odds ratios are per 1.0 unit on the 0–1 Frailty Index scale ",
      "(not per 0.1); tertile contrasts are the preferred headline effects. ",
      "Model 1 / Model 2 covariates are listed in the Table 2 footnotes; ",
      "pooled models additionally adjust for Country when shown. ",
      "Multiple imputation by chained equations used m = 5; primary logistic ",
      "estimates were pooled across imputations with Rubin rules when table ",
      "footnotes state so. Descriptive tables, RCS, ROC, and subgroup forests ",
      "used the first completed dataset. Restricted cubic splines (Figure 2) ",
      "and subgroup forests (Figure 3) used the same analytic sample and FI ",
      "definition unless a sensitivity scenario is named in the table title."
    ),
    "",
    "## Change analysis and mediation",
    paste0(
      "Mean FI and FI change tables followed the main logistic grouping scheme ",
      "(tertile unless otherwise locked). Mean FI is the mean of FI across ",
      "adjacent survey waves; FI change is the difference between those waves. ",
      "Change estimates are hazard ratios from Cox models ",
      "(survival::coxph; Surv(follow-up time in years, incident event)) with ",
      "covariates listed in the table footnotes."
    ),
    paste0(
      "Cross-sectional mediation used BMI as the exposure and Frailty Index as ",
      "the mediator (BMI → Frailty Index → ", outcome,
      ") on the Table 1 analytic sample, with the product-of-coefficients ",
      "framework and bootstrap intervals when exported. Correlation regressions ",
      "preceded mediation. Shared Model 2 covariates were: ", med_cov,
      ". Path diagrams place the Direct effect (c′) on the bottom arrow, ",
      "aligned with the mediation table. A negative proportion mediated ",
      "indicates suppression, not classical mediation."
    ),
    "",
    "## Cross-lagged panel network",
    paste0(
      "CLPN edge weights were estimated with regularized regression (glmnet) of ",
      "each follow-up node on all baseline nodes. ",
      "Binary nodes used binomial family; others used Gaussian. Coefficients with ",
      "|β| > 5 were set to 0. For plotting, weights were transformed to odds ratios ",
      "(exp(β)); self-loops were omitted; edges with OR in (0.95, 1.05) were omitted. ",
      "Networks were drawn with qgraph (spring layout, repulse.rad = 80). ",
      "Edge colour encodes OR > 1 vs OR < 1; line width and opacity scale with |log OR|. ",
      "Delivered adjacency tables (Table S8) define the node set."
    ),
    "",
    "## Sensitivity analyses",
    "Named sensitivity tables reused the main logistic and ",
    "change specifications on the restricted sample when exported.",
    "",
    "Software versions are listed in the companion software-versions text file and the Software subsection below.",
    ""
  )
}
