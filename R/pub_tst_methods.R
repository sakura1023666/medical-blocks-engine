###############################################################################
#  pub_tst_methods — 两阶段 Transformer 交付 Methods 文案（全项目复用）
#
#  由 run/pub/finalize_delivery_root.R / tst_summary_results 调用。
#  含「防再审」Reporting gates（Figure vs Table、外验首末数、负 NRI、
#  外验只报冻结模型、省略未记录超参、同 landmark 队列、Software 包白名单）。
#  数字只写可从 config / 课题产物脚注核对的口径句；禁止编造 AUC/N。
###############################################################################

#' TST Statistical analysis 正文行（写入 Methods_statistical_analysis.md）
#'
#' @param config 课题 config（可读 project / tst_stroke / imputation）
#' @return character 向量
pub_tst_methods_statistical_lines <- function(config = NULL) {
  cfg <- if (is.list(config)) config else list()
  prj <- cfg$project %||% list()
  tst <- cfg$tst_stroke %||% cfg$tst %||% list()
  outcome <- as.character(prj$analysis_group %||% prj$disease %||% "in-hospital mortality")[1L]
  dbs <- prj$databases %||% c("MIMIC", "eICU")
  if (is.character(dbs) && length(dbs) == 1L && grepl(",", dbs)) {
    dbs <- trimws(strsplit(dbs, ",", fixed = TRUE)[[1L]])
  }
  db_lab <- paste(dbs, collapse = " and ")
  min_age <- as.integer(tst$min_age %||% cfg$min_age %||% 18L)[1L]
  landmark_h <- as.integer(tst$summary_primary_landmark %||% tst$primary_landmark %||% 120L)[1L]
  comparator <- as.character(tst$comparator_score %||% "APSIII")[1L]
  fit_on <- as.character((cfg$imputation %||% list())$fit_on %||% "train")[1L]
  r_ver <- as.character(tst$r_version_note %||% "R version recorded in Methods_software_versions.txt")[1L]

  c(
    "# Statistical analysis",
    "",
    paste0(
      "This study developed a two-stage Transformer (hourly encoder followed by a day-level encoder) ",
      "to predict ", outcome, " among adults with sepsis-associated acute kidney injury. ",
      "Primary development used ", db_lab, ". Patients younger than ", min_age,
      " years were excluded on both the development and external-validation cohorts."
    ),
    "",
    paste0(
      "After cohort assembly, stays were split at the patient level into training, validation, and test sets ",
      "(7:2:1; split seed recorded in the project split ledger). Multiple imputation (MICE) was fit on the ",
      "training set only (`fit_on=", fit_on, "`) and applied to validation/test without refitting. ",
      "The outcome was not included in the imputation model. The primary modelling horizon used a landmark ",
      "of ", landmark_h, " hours. Day-1 through Day-5 metrics are evaluated on the same landmark test cohort; ",
      "findings are not extrapolated to shorter ICU stays."
    ),
    "",
    paste0(
      "Model discrimination (AUC), accuracy, and F1 in the main tables are patient-level bootstrap means (SD) ",
      "(default n_boot=400, seed=42 unless the project ledger records otherwise). ",
      "Day-5 Transformer table metrics use the full landmark test set; ", comparator,
      " table columns use the score-available subset when denominators differ. ",
      "Two-sided tests used α = 0.05. Classification thresholds used each model’s Youden index; ",
      "optimism of in-sample thresholds is a limitation. ",
      "Optimizer name and maximum training epochs are omitted unless recorded in the analysis ledger."
    ),
    "",
    paste0(
      "External validation applied development-cohort weights without retraining. ",
      "Methods report the assembled adult external cohort size after the age gate and the Day-5 evaluable n ",
      "(≥5 evaluable ICU days by the project day-mask); intermediate attrition counts are not invented. ",
      "The external narrative summarizes attenuation and calibration of the frozen Transformer; ",
      "severity-score comparators on the external set are optional supplemental analyses and are not ",
      "self-accused as “not done” in Limitations. ",
      "Calibration, decision-curve analysis, continuous NRI/IDI, stratified external AUC, and domain-shift summaries ",
      "are reported when produced. SHAP explanations target the validation-set best model when enabled."
    ),
    "",
    "## Reporting gates (required in every TST Methods — prevent re-review)",
    "",
    paste0(
      "1. **Figure vs table authority.** Main performance tables (Table 2/3 and aligned bar figures) are the ",
      "authoritative bootstrap summaries on the full landmark test set. Main ROC/confusion/comparison panels ",
      "(e.g. Figure 2), when drawn on the ", comparator, "-available subset, are representative single-run ",
      "snapshots. Snapshot n and point estimates may differ slightly from table bootstrap means; ",
      "figure values must not replace table values in Results."
    ),
    "",
    paste0(
      "2. **External attrition.** Report only ledger-supported endpoints: adult assembled n after the age gate, ",
      "and Day-5 evaluable n under the day-mask definition. Do not invent intermediate exclusion counts ",
      "(including patient-level missingness filters) until the author confirmation checklist is filled."
    ),
    "",
    paste0(
      "3. **External comparator policy.** Frozen-model external validation may report Transformer performance ",
      "alone. Describe site-shift attenuation and calibration. Do not claim superiority over clinical severity ",
      "scores on the external cohort unless those AUCs are tabulated. Do not write that comparators were “not performed.”"
    ),
    "",
    paste0(
      "4. **NRI/IDI and decision curves.** Positive NRI/IDI versus ", comparator,
      " indicate gain relative to the severity score only. Negative continuous NRI/IDI versus a strong tabular ",
      "baseline (e.g. XGBoost) are reported as no net reclassification/discrimination gain — never as clinical ",
      "superiority over that baseline. Mid-range decision-curve net benefit may favor the tabular baseline."
    ),
    "",
    paste0(
      "5. **Landmark cohort.** Day-1–Day-5 metrics share the same ≥landmark-horizon test cohort. ",
      "Limitations state that shorter stays are outside this analysis."
    ),
    "",
    paste0(
      "6. **Software sentence.** Cite ", r_ver, " (or the host-captured version in Methods_software_versions.txt). ",
      "List only packages used in the delivered analyses (typically mice, openxlsx, ggplot2, pROC on the R side). ",
      "Do not name unused packages (e.g. survival) in the manuscript Software paragraph. ",
      "Do not advertise unused baselines (e.g. LightGBM) unless they appear in tables."
    ),
    "",
    paste0(
      "7. **External tone.** Domain shift with attenuated discrimination or miscalibration is stated as such — ",
      "not as unqualified “successful external validation” or unmodified deployment readiness."
    ),
    "",
    "Reporting followed TRIPOD for the prediction model and STROBE for observational cohort description.",
    "Software name and package versions are listed in Methods_software_versions.txt and the Software subsection below.",
    ""
  )
}
