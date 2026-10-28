# Methods text for database-pooling / BlendedLoS liver multi-DB packs.
# Used by run/pub/finalize_delivery_root.R when --study-type dbpool|database_pool|blendedlos

pub_dbpool_methods_statistical_lines <- function(config = list()) {
  proj <- config$project %||% list()
  cohort <- as.character(proj$cohort %||% proj$disease %||% "ICU enzyme-elevation cohort")[1L]
  dbs <- proj$databases %||% c("AmsterdamUMC", "MIMIC-IV", "eICU", "HiRID")
  if (is.character(dbs) && length(dbs) == 1L) {
    dbs <- trimws(unlist(strsplit(dbs, "[,;|]")))
  }
  db_lab <- paste(dbs, collapse = ", ")
  drop_feat <- as.character(proj$drop_features %||% "ALT and AST (inclusion enzymes)")[1L]
  model <- as.character(proj$model %||% "Temporal Pointwise Convolution (TPC) multitask network")[1L]
  split <- as.character(proj$split %||% "patient-level 70%/15%/15% (fixed seed)")[1L]

  c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    paste0(
      "This multi-database pooling study analysed adult ICU stays meeting the ",
      cohort, " definition in the BlendedICU harmonised extract (", db_lab, "). ",
      "Inclusion enzymes used only for cohort definition were excluded from model features (",
      drop_feat, ")."
    ),
    "",
    "## Preprocessing",
    paste0(
      "Continuous time-series values were clipped to a priori physiological ranges, ",
      "then scaled with training-set 5th/95th percentiles to the interval [−1, 1] between quantiles ",
      "and clipped to [−4, 4] after scaling. Missingness was handled with forward-fill and ",
      "observation masks (MNAR-aware layout). Quantiles were fitted on the training split only ",
      "and reused for validation and test."
    ),
    "",
    "## Model and endpoints",
    paste0(
      "The primary architecture was a ", model, " predicting hourly in-ICU death risk ",
      "and remaining length of stay (RLoS) among predicted survivors. ",
      "Data were split at the patient level (", split, "). ",
      "Main training strategies were: (1) AmsterdamUMC alone; (2) MIMIC-IV alone; ",
      "(3) transfer learning (pretrain on MIMIC-IV, fine-tune on AmsterdamUMC); ",
      "(4) pooling AmsterdamUMC with MIMIC-IV. Held-out generalization used eICU and HiRID ",
      "unless a strategy explicitly trained on all four databases (equal-n architecture benchmark)."
    ),
    "",
    "## Performance metrics and uncertainty",
    paste0(
      "Discrimination for mortality used the area under the receiver operating characteristic ",
      "curve (AUROC); precision–recall used AUPRC where reported. RLoS error used mean absolute ",
      "percentage error (MAPE). Unless noted, AUROC 95% confidence intervals used the DeLong ",
      "method at the stay level; MAPE and AUPRC intervals used patient-level percentile bootstrap ",
      "(10,000 resamples). A composite metric summarised MAPE and AUROC relative to a ",
      "pre-specified baseline arm. Architecture comparison (Table S2) used a single equal-n ",
      "training run across databases with validation reported separately by source database; ",
      "the best value per row is highlighted (lowest MAPE; highest AUROC)."
    ),
    "",
    "## Software",
    "(See Methods_software_versions.txt and the Software subsection appended at finalize.)",
    ""
  )
}
