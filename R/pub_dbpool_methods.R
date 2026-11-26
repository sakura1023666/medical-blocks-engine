# Methods text for database-pooling / multi-DB ICU packs.
# Used by run/pub/finalize_delivery_root.R when --study-type dbpool|database_pool|blendedlos
#
# Delivery wording rule (2026-11 ICUAKI): do NOT mention prior-paper proper names,
# "版式", or "BlendedLoS layout" in customer-facing Methods. Describe feature
# selection as following prior published multi-database ICU mortality / LoS literature.

pub_dbpool_methods_statistical_lines <- function(config = list()) {
  proj <- config$project %||% list()
  cohort <- as.character(proj$cohort %||% proj$disease %||% "ICU enzyme-elevation cohort")[1L]
  dbs <- proj$databases %||% c("AmsterdamUMC", "MIMIC-IV", "eICU", "HiRID")
  if (is.character(dbs) && length(dbs) == 1L) {
    dbs <- trimws(unlist(strsplit(dbs, "[,;|]")))
  }
  db_lab <- paste(dbs, collapse = ", ")
  # BlendedLoS / ULN paper CI path uses patient-level bootstrap 10,000 (eval_liver_paper_ci).
  n_boot <- suppressWarnings(as.integer(
    proj$n_boot %||% Sys.getenv("ICUAKI_N_BOOT", unset = Sys.getenv("DBPOOL_N_BOOT", unset = "10000"))
  )[1L])
  if (!is.finite(n_boot) || n_boot < 1L) n_boot <- 10000L

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
      "(hourly vitals + laboratories + selected medications; respiratory channels off unless ",
      "enabled; static age/sex/height/weight). Laboratories used only to define the cohort ",
      "were dropped from predictors. Variable-level inventory is Table S9 (written at ",
      "pack/finalize by dbpool_feature_inventory.py). No additional data-driven feature ",
      "hunting was performed beyond this literature-aligned inventory and the leakage exclusions."
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
        "Sensitivity analyses used three separate single-analyte ULN cohorts—total bilirubin ",
        "≥1.3 mg/dL alone, ALT ≥41 U/L alone, and AST ≥38 U/L alone—each re-run with the same ",
        "TPC arms, metrics, and confidence-interval methods as the primary all-three (AND) gate. ",
        "Delivered tables/figures are Tables S3–S8 and Figures S1–S3. These are not a union ",
        "(“any one of three”) cohort: each sensitivity pack admits stays that meet that one ",
        "threshold only; the primary analysis remains the intersection of all three."
      ),
      ""
    )
  }

  uln_first_lines <- if (isTRUE(is_icuaaki)) {
    character(0)
  } else {
    c(
      "",
      "## ULN gate operational definition (\"first\")",
      paste0(
        "For each of AST, ALT and total bilirubin, the gate used the first positive post-admission ",
        "hourly value (time ≥ 0 and value > 0) on the BlendedICU long timeseries via arg_min(value, time). ",
        "The three analytes are evaluated separately: the three “first” values may come from different ",
        "hours or specimens and are not required to share a single laboratory panel. The primary ",
        "ULN-all3 cohort required first AST ≥38 U/L AND first ALT ≥41 U/L AND first total bilirubin ",
        "≥1.3 mg/dL (22.23 µmol/L). Stays lacking a positive post-admission value for a required ",
        "analyte, age <18, or ICU length of stay ≤0.5 h were excluded. This “first” rule is a ",
        "study-specific operationalisation of laboratory ULN thresholds (not a simultaneous-panel rule)."
      )
    )
  }

  c(
    "# Statistical analysis",
    "",
    "## Study design, data provenance, and cohort",
    paste0(
      "This multi-database pooling study analysed adult ICU stays meeting the ",
      cohort, ". Hourly tensors and stay-level labels were taken from the BlendedICU ",
      "harmonized long-format extract covering ", db_lab,
      " (BlendedICU blended long timeseries + preprocessed labels), with a study-specific ",
      "eligibility filter and in-house unit harmonisation (blood glucose mmol/L; haemoglobin g/dL). ",
      "BlendedICU denotes this multi-database harmonized extract—not a separate undocumented ",
      "self-built mapping that bypasses BlendedICU. Source databases were accessed under the ",
      "PhysioNet Credentialed Health Data Use Agreement; credentialed raw tables are not ",
      "redistributed. Analytic N for the primary pack is reported in Table 1 (patients and ICU stays ",
      "by database); Figure 1 is a study-pipeline schematic and does not redraw a CONSORT-style ",
      "per-database attrition cascade. Predictor inventory is summarised under Feature selection ",
      "(Table S9)."
    ),
    uln_first_lines,
    "",
    "## Time zero and prediction window",
    paste0(
      "Time zero (t0) was ICU admission (hour index 0 on the BlendedICU hourly timeline). ",
      "The first ", t0_hours,
      " hours after admission provided context only; the multitask model emitted hourly ",
      "predictions from hour ", t0_hours,
      " onward through the end of the observed ICU stay (sequence truncated by stay length). ",
      "No hospital-ward hours after ICU discharge entered the prediction window."
    ),
    "",
    "## Preprocessing",
    paste0(
      "Continuous time-series values were clipped to a priori physiological ranges transcribed ",
      "from the reference multi-database ICU modelling protocol supplementary table (MOESM1-style ",
      "bounds), then scaled with training-set 5th/95th percentiles to [−1, 1] between quantiles and ",
      "clipped to [−4, 4] after scaling. Some transcribed lower bounds are non-physiological ",
      "(e.g. negative BUN or GCS total); they were applied as published in that reference table and ",
      "are reported transparently in Table S1. Hard clipping can pin medians to the bound when the ",
      "unclipped cohort median lies outside the interval (notable for lactate, creatinine, platelets, ",
      "urine output). Table S1 “N clipped” counts post-normalisation outliers (|scaled| > 4), not ",
      "hard-clip rewrite counts; Before/After medians reflect the hard clip. Missingness used ",
      "forward-fill with observation masks (values + masks channels; MNAR here means missingness ",
      "handled by mask indicators rather than a formal MNAR likelihood model). Quantiles were ",
      "fitted on the training split only and reused for validation and test."
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
      "ICU mortality was the BlendedICU stay-level mortality label used consistently in Table 1 ",
      "and in model targets (not hospital-wide mortality after ICU discharge). ",
      "Source databases may encode death with different raw discharge-status fields before ",
      "harmonisation; this pack did not re-derive death from unharmonised hospital ",
      "discharge tables, and cross-database absolute mortality rates should be interpreted with ",
      "that limitation. ",
      "RLoS labels were dynamic remaining ICU stay: true ICU length of stay (days) minus elapsed ",
      "time since t0, clamped to [0, ", max_los, "] days (max LoS = ", max_los,
      "). Deaths were excluded from RLoS loss and MAPE. ",
      "RLoS is therefore remaining ICU duration, not remaining hospital length of stay. ",
      "Data were split at the patient (uniquepid) level with fixed seed 974: within each training ",
      "database, test and validation each took int(0.15 × n_persons) persons and the remainder ",
      "formed the training set (so Amsterdam 624 persons → test 93 + val 93 + train 438, not ",
      "round(0.70 × 624)). eICU and HiRID were held out as test-only for the four-strategy matrix. ",
      "Main training strategies were: (1) AmsterdamUMC alone; (2) MIMIC-IV alone; ",
      "(3) transfer learning (pretrain on MIMIC-IV, fine-tune on AmsterdamUMC); ",
      "(4) pooling AmsterdamUMC with MIMIC-IV. Held-out generalization used eICU and HiRID ",
      "unless a strategy explicitly trained on all four databases (equal-n architecture benchmark). ",
      transfer_note
    ),
    "",
    "## TPC training hyperparameters",
    paste0(
      "Unless overridden, TPC multitask training used Adam (learning rate 1e−4), batch size 32 ",
      "(train/val/test), up to 200 epochs with early stopping patience 5 on validation loss, ",
      "loss = mortality binary cross-entropy + α × RLoS MSLE with α = 20, max LoS = ", max_los,
      " days, TPC depth n_layers = 9 with n_temp_kernels = 12 and point_size = 13, main dropout ",
      "0.45 and temporal dropout 0.05, kernel size 4. Training used CUDA (torch cu124) on an ",
      "NVIDIA RTX 5880 Ada Generation GPU."
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
      "Two composite scores share the same algebraic form 0.5×[(MAPE/MAPE₀)+((1−AUROC)/(1−AUROC₀))] ",
      "but different baselines and must not be cross-read: Table 3 / S4 / S6 / S8 Mcomposite uses ",
      "Amsterdam-alone on Amsterdam as (AUROC₀, MAPE₀); Figure 2 / S1–S3 Mscan uses the largest ",
      "training-size point on that scan as the baseline (endpoint = 1.000 by construction). ",
      "Architecture comparison (Table S2) used a single equal-n training run: each database was ",
      "capped at the Amsterdam training person count (438) before BlendedLoS inclusion filters ",
      "(e.g. min LoS); the metrics file n_train is the post-filter training headcount (e.g. 1,713), ",
      "not 4 × 438 stays. Validation is reported separately by source database; the best value ",
      "per row is highlighted (lowest MAPE; highest AUROC)."
    ),
    "",
    "## Table 2 versus Table 3 versus Figure 2 (do not equate cells)",
    paste0(
      "Table 2, Table 3 and Figure 2 answer different questions. ",
      "Table 2 is the single-database 100% trainval benchmark. ",
      "Table 3 is the four-strategy matrix under the patient-level split above ",
      "(training N in column headers). ",
      "Figure 2 is a separate MIMIC training-size sweep (mean of eICU+HiRID) with Mscan ",
      "(max-N baseline), not Table 3 Mcomposite (Amsterdam-alone baseline); ",
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
    "## Limitations (clip bounds and schematic Figure 1)",
    paste0(
      "Physiological clip bounds follow the reference MOESM1 transcription, including bounds that ",
      "are not clinically realistic at the lower end; heavy clipping for some laboratories compresses ",
      "information and is disclosed in Table S1. Figure 1 does not enumerate per-database raw→gate→final ",
      "attrition counts; those denominators are carried by Table 1 and the Methods N statements above."
    ),
    "",
    "## Software",
    "(See the companion software-versions text file in the delivery folder.)",
    ""
  )
}
