# Methods text for database-pooling / multi-DB ICU packs.
# Used by run/pub/finalize_delivery_root.R when --study-type dbpool|database_pool|blendedlos
#
# Delivery wording rule (2026-11 ICUAKI): do NOT mention "Allyn", "版式", or
# "BlendedLoS layout" in customer-facing Methods. Describe feature selection as
# following prior published multi-database ICU mortality / LoS literature.

pub_dbpool_methods_statistical_lines <- function(config = list()) {
  proj <- config$project %||% list()
  cohort <- as.character(proj$cohort %||% proj$disease %||% "ICU enzyme-elevation cohort")[1L]
  dbs <- proj$databases %||% c("AmsterdamUMC", "MIMIC-IV", "eICU", "HiRID")
  if (is.character(dbs) && length(dbs) == 1L) {
    dbs <- trimws(unlist(strsplit(dbs, "[,;|]")))
  }
  db_lab <- paste(dbs, collapse = ", ")
  n_boot <- suppressWarnings(as.integer(
    proj$n_boot %||% Sys.getenv("ICUAKI_N_BOOT", unset = Sys.getenv("DBPOOL_N_BOOT", unset = "2000"))
  )[1L])
  if (!is.finite(n_boot) || n_boot < 1L) n_boot <- 2000L

  kind <- tolower(as.character(
    proj$kind %||% Sys.getenv("DBPOOL_KIND", unset = "")
  )[1L])
  is_icuaaki <- grepl("icuaaki|icu.?aki|kdigo", kind) ||
    grepl("ICU-AKI|KDIGO|DN=1", cohort, ignore.case = TRUE)

  default_feat <- if (isTRUE(is_icuaaki)) {
    paste0(
      "Candidate predictors followed prior published multi-database ICU mortality and ",
      "length-of-stay modelling inventories: bedside vitals, common laboratories, selected ",
      "medications, and static age/sex/height/weight (respiratory waveform channels off unless ",
      "explicitly enabled). Creatinine and urine output were excluded because they enter the ",
      "KDIGO AKI definition. Blood glucose was analysed in mmol/L and haemoglobin in g/dL after ",
      "cross-database units harmonisation. No additional data-driven feature hunting was used ",
      "beyond this literature-aligned inventory and the leakage exclusions above."
    )
  } else {
    paste0(
      "Model inputs followed prior published multi-database ICU modelling inventories ",
      "(vitals + laboratories + selected medications + static age/sex/height/weight; ",
      "respiratory off unless enabled); laboratories used only to define the cohort were ",
      "dropped from predictors."
    )
  }
  feature_set <- as.character(
    proj$feature_set %||% Sys.getenv("DBPOOL_FEATURE_SET", unset = default_feat)
  )[1L]

  model <- as.character(proj$model %||% "Temporal Pointwise Convolution (TPC) multitask network")[1L]
  split <- as.character(proj$split %||% "patient-level 70%/15%/15% (fixed seed 974)")[1L]
  t0_hours <- as.integer(proj$time_before_pred %||% 5L)[1L]
  max_los <- as.numeric(proj$max_los_days %||% 10)[1L]
  transfer_note <- as.character(
    proj$transfer_blank_note %||%
      paste0(
        "Transfer learning (pretrain MIMIC-IV, fine-tune AmsterdamUMC) reports AmsterdamUMC ",
        "specialisation; MIMIC-IV specialisation and eICU/HiRID generalisation cells for the ",
        "Transfer arm are left blank by design (dashes), as stated in Table 3 footnotes. ",
        "Off-diagonal single-database specialisation (Amsterdam model on MIMIC-IV test and ",
        "vice versa) uses peer-database cross-evaluation when available."
      )
  )[1L]

  sens_lines <- if (isTRUE(is_icuaaki)) {
    c(
      "## Sensitivity and clinical extras",
      paste0(
        "Supplementary tables report DeLong/bootstrap intervals (Table S3), an Age+Sex logistic ",
        "baseline versus TPC on shared external stays (Table S4), and pooling-model risk tertiles ",
        "with Youden and fixed operating points (Table S5). Calibration and decision-curve analyses ",
        "compare MIMIC-IV alone with pooling on eICU and HiRID (Figures 3–4); Figure 5 shows ",
        "observed mortality by predicted-risk tertile. Decision-curve panels display net benefit ",
        "with the y-axis starting at zero (values below treat-none are omitted from the plot)."
      ),
      ""
    )
  } else {
    c(
      "## Sensitivity analyses",
      paste0(
        "When packed, single-enzyme ULN definitions (total bilirubin, ALT, or AST alone) are ",
        "reported as numbered sensitivity tables and figures parallel to the primary all-three ",
        "ULN cohort, using the same TPC arms, metrics, and confidence-interval methods."
      ),
      ""
    )
  }

  c(
    "# Statistical analysis",
    "",
    "## Study design, data provenance, and cohort",
    paste0(
      "This multi-database pooling study analysed adult ICU stays meeting the ",
      cohort, ". Hourly tensors were built as a harmonized extract with a self-built variable ",
      "mapping from ", db_lab,
      " source tables (patient-level split seed 974). Source databases were accessed under the ",
      "PhysioNet Credentialed Health Data Use Agreement; credentialed raw tables are not ",
      "redistributed. ",
      feature_set
    ),
    "",
    "## Time zero and prediction window",
    paste0(
      "Time zero (t0) was ICU admission (hour index 0 on the harmonised hourly timeline). ",
      "The first ", t0_hours,
      " hours after admission provided context only; the multitask model emitted hourly ",
      "predictions from hour ", t0_hours,
      " onward through the end of the observed ICU stay (sequence truncated by stay length). ",
      "No hospital-ward hours after ICU discharge entered the prediction window."
    ),
    "",
    "## Preprocessing",
    paste0(
      "Continuous time-series values were clipped to a priori physiological ranges taken from ",
      "the reference multi-database ICU modelling protocol supplementary tables, then scaled with ",
      "training-set 5th/95th percentiles to the interval [−1, 1] between quantiles and clipped to ",
      "[−4, 4] after scaling. Table S1 “N clipped” counts post-normalisation outliers (|scaled| > 4), ",
      "not hard-clip rewrite counts; Before/After medians reflect the hard clip. Missingness was ",
      "handled with forward-fill and observation masks. Quantiles were fitted on the training ",
      "split only and reused for validation and test."
    ),
    "",
    "## Model and endpoints",
    paste0(
      "The primary architecture was a ", model, " predicting, at each eligible hour, ",
      "(i) ICU mortality risk and (ii) remaining ICU length of stay (RLoS) among stays that ",
      "did not die in the ICU. TPC was pre-specified as the primary architecture following prior ",
      "published multi-database ICU modelling work; Table S2 architecture screens are descriptive ",
      "(single equal-n run; LSTM/Transformer may lead individual cells without overturning TPC ",
      "as primary). ",
      "ICU mortality was the harmonised stay-level mortality label used consistently in Table 1 ",
      "and in model targets (not hospital-wide mortality after ICU discharge). ",
      "Source databases may encode death with different raw discharge-status fields before ",
      "harmonisation; this pack did not re-derive death from unharmonised hospital ",
      "discharge tables, and cross-database absolute mortality rates should be interpreted with ",
      "that limitation. ",
      "RLoS labels were dynamic remaining ICU stay: true ICU length of stay (days) minus elapsed ",
      "time since t0, clamped to [0, ", max_los, "] days (max LoS = ", max_los,
      "). Deaths were excluded from RLoS loss and MAPE. ",
      "RLoS is therefore remaining ICU duration, not remaining hospital length of stay. ",
      "Data were split at the patient level (", split, "). ",
      "Main training strategies were: (1) AmsterdamUMC alone; (2) MIMIC-IV alone; ",
      "(3) transfer learning (pretrain on MIMIC-IV, fine-tune on AmsterdamUMC); ",
      "(4) pooling AmsterdamUMC with MIMIC-IV. Held-out generalization used eICU and HiRID ",
      "unless a strategy explicitly trained on all four databases (equal-n architecture benchmark). ",
      transfer_note
    ),
    "",
    "## Performance metrics and uncertainty",
    paste0(
      "Discrimination for mortality used the area under the receiver operating characteristic ",
      "curve (AUROC); precision–recall used AUPRC where reported. RLoS error used mean absolute ",
      "percentage error (MAPE). Unless noted, AUROC 95% confidence intervals used the DeLong ",
      "method at the ICU-stay level; MAPE and AUPRC intervals used patient-level percentile ",
      "bootstrap (", format(n_boot, big.mark = ","),
      " resamples). Point estimates are single fixed-seed runs (seed 974), ",
      "not multi-seed means. ",
      "AUPRC Baseline is class prevalence in the same prediction stay frame as that cell ",
      "(not Table 1 all-stays mortality of complementary databases). ",
      "A composite metric summarised MAPE and AUROC relative to a pre-specified baseline arm. ",
      "Architecture comparison (Table S2) used a single equal-n training run across databases ",
      "with validation reported separately by source database; the best value per row is ",
      "highlighted (lowest MAPE; highest AUROC)."
    ),
    "",
    "## Table 2 versus Table 3 versus Figure 2 (do not equate cells)",
    paste0(
      "Table 2, Table 3 and Figure 2 answer different questions. ",
      "Table 2 is the single-database 100% trainval benchmark. ",
      "Table 3 is the four-strategy matrix under the ", split,
      " protocol (training N in column headers). ",
      "Figure 2 is a separate MIMIC training-size sweep (mean of eICU+HiRID); ",
      "matching endpoint train N does not imply the same checkpoint as Table 3 MIMIC-alone ",
      "Generalization—do not cross-read. ",
      "Rounding also differs (Table 2 mortality AUROC three decimals; Table 3 two)."
    ),
    "",
    "## Feature selection",
    paste0(feature_set),
    "",
    sens_lines,
    "## Numeric reporting",
    paste0(
      "Publication rounding follows the reference multi-database ICU modelling tables: ",
      "Table 2 mortality AUROC three decimals and MAPE one decimal; Table 3 AUROC two decimals ",
      "and MAPE two decimals; supplementary CI tables use three-decimal AUROC/AUPRC and ",
      "two-decimal MAPE; counts use thousands separators; P values use <0.001 / >0.999 caps."
    ),
    "",
    "## Software",
    "(See the companion software-versions text file in the delivery folder.)",
    ""
  )
}
