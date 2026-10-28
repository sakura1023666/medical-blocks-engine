# prognosis_v2 发表方法学正文（交付根 Methods_statistical_analysis.md）
# 由 run/pub/finalize_delivery_root.R --study-type prognosis_v2 调用
# 画像：PV2_PROFILE=hip_aki（默认）| sleep_dyslipidemia

pub_prognosis_v2_methods_lines <- function(config = NULL) {
  cfg <- if (is.list(config)) config else list()
  proj <- cfg$project %||% list()
  profile <- tolower(as.character(
    proj$pv2_profile %||% Sys.getenv("PV2_PROFILE", unset = "hip_aki")
  )[1L])

  if (grepl("sleep|dyslipid", profile)) {
    return(.pub_pv2_methods_sleep_dyslipidemia(proj))
  }
  .pub_pv2_methods_hip_aki(proj)
}

.pub_pv2_methods_hip_aki <- function(proj) {
  exposure <- as.character(proj$exposure %||% "the inflammatory indices")[1L]
  outcome <- as.character(proj$analysis_group %||% proj$disease %||%
                            "365-day all-cause mortality")[1L]
  dbs <- proj$databases %||% "MIMIC-IV"
  if (is.character(dbs)) dbs <- paste(dbs, collapse = ", ")
  cohort <- as.character(proj$cohort %||% "the analytic cohort")[1L]
  m3 <- as.character(proj$model3_covs %||% "Age, Gender, CHARLSON")[1L]
  grouping <- as.character(proj$grouping %||% "binary (High vs Low)")[1L]
  sens <- as.character(proj$sensitivity %||%
                         "90-day all-cause mortality (Table S5)")[1L]
  mediator <- as.character(proj$mediator %||% "OASIS")[1L]

  c(
    "# Statistical analysis",
    "",
    sprintf(
      "We analysed %s in %s. The primary endpoint was %s after ICU admission.",
      cohort, dbs, outcome
    ),
    sprintf(
      "Exposures were %s, entered as continuous variables (per 1 SD) and as the locked grouping from an engine-level cascade (quartile \u2192 tertile \u2192 binary; pass_rule = all indices on the unadjusted highest-versus-lowest contrast). The locked grouping for this study was %s.",
      exposure, grouping
    ),
    "Candidate covariates were screened with Boruta and SHAP; multicollinearity was assessed with variance inflation factors (VIF < 5 considered acceptable).",
    "Missing covariates were handled with multiple imputation by chained equations (MICE, cart, m = 5). Inferential Cox models were fit on each completed dataset and pooled by Rubin\u2019s rules. Descriptive tables, figures, Boruta/SHAP, ROC, RCS, subgroup forests and mediation path diagrams used the first completed dataset (operational layer).",
    paste0(
      "Cox proportional hazards models reported hazard ratios (HRs) with 95% confidence intervals. ",
      "Model 1 was unadjusted. Model 2 was adjusted for Age and Gender. Model 3 was adjusted for ",
      m3, "."
    ),
    "Person-time and crude mortality rates were summarised by exposure group (Table 2). Cumulative incidence curves used Kaplan\u2013Meier estimators with log-rank tests. Restricted cubic splines evaluated dose\u2013response shape (P-linear and P-nonlinear). Youden-index cutoffs and AUC summarised discrimination (Table S4 / Figure 5).",
    "Subgroup analyses estimated High versus Low contrasts within strata on the full analytic sample, with the same Model 3 covariate set excluding the stratifying variable itself (Figure 7).",
    sprintf(
      "Mediation analyses used %s as the mediator with path models adjusted as in Table 3 Model 3 (mediator omitted from its own adjustment set). Path a was a linear coefficient of the exposure (per 1 SD) on the standardized mediator; path b and the direct effect were Cox log-hazard coefficients. The proportion mediated was (a\u00d7b)/total on the log-hazard scale with bootstrap confidence intervals (Table S8 / Figure 6).",
      mediator
    ),
    sprintf(
      "Sensitivity analysis redefined the endpoint as %s using the same Model 1\u2013Model 3 structure and the same exposure cut-points as Table 3 (Table S5). Cause-specific Fine\u2013Gray models were not performed because cause of death is unavailable in MIMIC-IV; no main-text Table 4 was presented.",
      sens
    ),
    "Baseline characteristics before and after imputation are in Table S6. Linear associations between each inflammatory index (per 1 SD) and the standardized mediator under Model 1\u2013Model 3 are in Table S7.",
    "Proportional hazards were assessed with Schoenfeld residuals (cox.zph).",
    "Software name and package versions are listed in Methods_software_versions.txt and in the Software subsection below.",
    ""
  )
}

.pub_pv2_methods_sleep_dyslipidemia <- function(proj) {
  exposure <- as.character(proj$exposure %||% "sleep duration")[1L]
  outcome <- as.character(proj$analysis_group %||% proj$disease %||%
                            "all-cause mortality")[1L]
  dbs <- proj$databases %||% c("NHANES", "SHHS", "CHARLS")
  if (is.character(dbs)) dbs <- paste(dbs, collapse = ", ")
  cohort <- as.character(
    proj$cohort %||%
      "adults aged 45 years or older with dyslipidemia"
  )[1L]
  m3 <- as.character(
    proj$model3_covs %||%
      "Age, Gender, SBP, Education, Diabetes, Hypertension, Alcohol, Smoke, BMI"
  )[1L]
  grouping <- as.character(
    proj$grouping %||%
      "five mutually exclusive categories (<5 h, 5-6 h, 6-7 h, 7-8 h, >=9 h; reference 7-8 h)"
  )[1L]
  sens <- as.character(
    proj$sensitivity %||%
      "exclusion of deaths within the first year (Table S5) and a 5-year administrative horizon (Table S3)"
  )[1L]
  mediator <- as.character(proj$mediator %||% "diastolic blood pressure (DBP)")[1L]
  primary <- as.character(proj$primary_dbs %||% "NHANES and SHHS")[1L]
  validation <- as.character(proj$validation_dbs %||% "CHARLS")[1L]

  c(
    "# Statistical analysis",
    "",
    sprintf(
      "We analysed %s in %s. %s were the primary cohorts used to select Model 3 covariates; %s was the external validation cohort that applied the same Model 3 specification. The primary endpoint was %s.",
      cohort, dbs, primary, validation, outcome
    ),
    sprintf(
      "The exposure was %s, analysed as a continuous variable (per 1 SD within each cohort) and as %s. Extreme short-sleep contrasts (<5 h and <6 h versus 7-8 h) and a clinical cut-point of 465 minutes (7.75 h) were reported as supplementary analyses and did not replace the pre-specified five-level grouping.",
      exposure, grouping
    ),
    "Candidate covariates were screened with Boruta and SHAP on the primary cohorts only; multicollinearity was assessed with variance inflation factors (VIF < 5 considered acceptable). The intersection of Boruta-confirmed covariates across primary cohorts with VIF < 5 defined Model 3.",
    "Missing covariates were handled with multiple imputation by chained equations (MICE, cart, m = 5, maxit = 5, seed = 1234). Exposure, follow-up time, death status and survey design variables were not imputed. Inferential Cox models were fit on each completed dataset and pooled by Rubin\u2019s rules. Descriptive tables, Boruta/SHAP, Kaplan\u2013Meier, RCS, ROC, subgroup forests and mediation diagrams used the first completed dataset for operational consistency.",
    paste0(
      "Cox proportional hazards models reported hazard ratios (HRs) with 95% confidence intervals. ",
      "Model 1 was unadjusted. Model 2 was adjusted for Age and Gender. Model 3 was adjusted for ",
      m3, ". NHANES models used survey weights (WTMEC2YR), PSU and strata; CHARLS and SHHS models were unweighted."
    ),
    "Person-time and crude mortality rates were summarised by sleep category (Table 2). A linear ordinal P for trend across sleep categories was not reported because sleep duration and mortality typically follow a U-shaped association; dose\u2013response shape was evaluated with restricted cubic splines reporting P-linear and P-nonlinear (Figure 4). Cumulative incidence used Kaplan\u2013Meier estimators with log-rank tests (Figure 3).",
    "Competing-risk Fine\u2013Gray models treated cardiovascular death as the event and other deaths as competing events (Table 4). CHARLS cardiovascular death used Harmonized End of Life ragcod = 2.",
    "Subgroup analyses estimated category-specific contrasts versus 7-8 h within strata of age, sex, BMI, smoking, hypertension and diabetes (Figure 7).",
    sprintf(
      "Mediation analyses used %s as the mediator. In pre-specified screening, unadjusted path models (no covariates) had significant paths a, b and c in both primary cohorts; adding age removed joint significance. Path a was the linear coefficient of sleep duration on standardized DBP; path b and the direct effect were Cox log-hazard coefficients. The proportion mediated was (a\u00d7b)/total on the log-hazard scale with bootstrap confidence intervals (Table S8 / Figure 6). Path models were unweighted, including in NHANES, and are not the survey-weighted Cox models in Table 3.",
      mediator
    ),
    sprintf(
      "Sensitivity analyses included %s. Additional clinical explorations used RCS-derived minimum-risk cutoffs (Table S10), multi-horizon prediction (Table S11 / Figure S1), and a 465-minute (7.75 h) package comprising Cox with population attributable risk (Table S12), diagnostic yield (Table S13) and joint stratification with age and hypertension (Table S14).",
      sens
    ),
    "Proportional hazards assumptions were assessed with Schoenfeld residuals (cox.zph; Table S15).",
    "Baseline characteristics before and after imputation are in Table S6. Correlations between sleep duration and other indicators are in Table S7.",
    "Software name and package versions are listed in Methods_software_versions.txt and in the Software subsection below.",
    ""
  )
}
