#!/usr/bin/env Rscript
# Rebuild Wang-2025 ESM-aligned Tables for SA-AKI TCF (Table 1–2, S1–S13).
#
# Usage (engine canonical):
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_tables.R --success-root PATH
#   Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_tables_core.R --success-root PATH --only "Table S10"
# Project scripts/rebuild_wang2025_tcf_tables.R is a thin redirect.
#
# Relies on engine export_sci_table → SCI three-line xlsx (Times New Roman).

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
success_root <- NA_character_
engine_root <- NA_character_
only_ids <- character(0)
if (length(args)) {
  for (i in seq_along(args)) {
    if (identical(args[[i]], "--success-root") && i < length(args)) {
      success_root <- args[[i + 1L]]
    }
    if (identical(args[[i]], "--engine-root") && i < length(args)) {
      engine_root <- args[[i + 1L]]
    }
    if (identical(args[[i]], "--only") && i < length(args)) {
      only_raw <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1]]
      only_ids <- trimws(only_raw)
    }
  }
}

.normalize_table_id <- function(x) {
  x <- trimws(as.character(x))
  if (grepl("^S[0-9]+$", x, ignore.case = TRUE)) {
    x <- paste0("Table ", toupper(substr(x, 1, 1)), substring(x, 2))
  }
  x <- gsub("^table\\s*", "Table ", x, ignore.case = TRUE)
  x <- gsub("^Table\\s*S\\s*", "Table S", x, ignore.case = TRUE)
  x <- gsub("^Table([0-9])", "Table \\1", x)
  x
}
if (length(only_ids)) {
  only_ids <- unique(vapply(only_ids, .normalize_table_id, character(1)))
}
if (is.na(success_root) || !nzchar(success_root)) {
  success_root <- "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/by_index/\u3010success\u3011ALLVARS"
}
if (is.na(engine_root) || !nzchar(engine_root)) {
  engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(engine_root)) {
    for (cand in c("/mnt/e/01block/01Block-new-Final", "E:/01block/01Block-new-Final")) {
      if (dir.exists(cand)) { engine_root <- cand; break }
    }
  }
}

stopifnot(dir.exists(success_root), dir.exists(engine_root))

utils_path <- file.path(engine_root, "R", "utils.R")
stopifnot(file.exists(utils_path))
source(utils_path)
options(pipeline.single_db = TRUE, pipeline.database_name = "")
if (exists("pipeline_apply_pub_digits", mode = "function")) {
  pipeline_apply_pub_digits(list(pub_digits = list(
    est = 3L, p = 3L, desc = 3L, cutoff = 3L,
    int_big_mark = TRUE, desc_trim = TRUE
  )))
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

sum_tables <- file.path(success_root, "summary_results", "Tables")
idx_tables <- file.path(success_root, "Tables")
dir.create(sum_tables, recursive = TRUE, showWarnings = FALSE)
dir.create(idx_tables, recursive = TRUE, showWarnings = FALSE)

rebuild_ws <- file.path(success_root, "_tables_rebuild_workspace")
dir.create(rebuild_ws, recursive = TRUE, showWarnings = FALSE)

archive_dir <- file.path(rebuild_ws, "archive_wrong_table_roles")
dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)

.archive_old_tables <- function(tables_dir, archive_dir, only_ids = character(0)) {
  if (!dir.exists(tables_dir)) return(invisible(character()))
  files <- list.files(tables_dir, pattern = "\\.(xlsx|tex)$", full.names = TRUE)
  files <- files[!grepl("/(_archive|_wang_payloads|_tables_rebuild_workspace)/", files)]
  moved <- character()
  stamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  for (f in files) {
    bn <- basename(f)
    hit <- grepl("^Table (1|2|S[0-9]+)\\b", bn) ||
      grepl("-(MIMIC|eICU)\\.", bn, ignore.case = TRUE)
    if (length(only_ids)) {
      hit <- any(vapply(only_ids, function(id) {
        grepl(paste0("^", gsub("([.\\(\\)])", "\\\\\\1", id), "\\b"), bn)
      }, logical(1)))
    }
    if (isTRUE(hit)) {
      dest <- file.path(archive_dir, paste0(
        tools::file_path_sans_ext(bn), "_", stamp, ".", tools::file_ext(bn)
      ))
      ok <- file.rename(f, dest)
      if (!isTRUE(ok)) {
        file.copy(f, dest, overwrite = TRUE)
        unlink(f)
      }
      moved <- c(moved, bn)
    }
  }
  moved
}

if (length(only_ids) && ("Table 1" %in% only_ids) && !("Table S1" %in% only_ids)) {
  only_ids <- c(only_ids, "Table S1")
  message("--only Table1: also refreshing Table S1")
}

moved_sum <- .archive_old_tables(sum_tables, archive_dir, only_ids = only_ids)
moved_idx <- .archive_old_tables(idx_tables, archive_dir, only_ids = only_ids)
message("Archived summary Tables: ", length(moved_sum), "; index Tables: ", length(moved_idx))
message("Rebuild workspace: ", rebuild_ws)

py_compute <- file.path(engine_root, "python", "ml_tcf", "pub", "rebuild_wang2025_tables_compute.py")
if (!file.exists(py_compute)) {
  # legacy project copy (pre-2026-11-02 engine lift)
  py_compute <- normalizePath(
    file.path(dirname(dirname(success_root)), "scripts", "rebuild_wang2025_tcf_tables_compute.py"),
    mustWork = FALSE
  )
}
if (!file.exists(py_compute)) {
  stop("Missing tables_compute.py under engine python/ml_tcf/pub/ or project scripts/")
}

payload_dir <- file.path(rebuild_ws, "wang_payloads")
dir.create(payload_dir, recursive = TRUE, showWarnings = FALSE)

py_bin <- if (file.exists("/tmp/tcf_np2_venv/bin/python")) {
  "/tmp/tcf_np2_venv/bin/python"
} else {
  "python3"
}
only_baseline <- length(only_ids) > 0L &&
  all(only_ids %in% c("Table 1", "Table S1"))
only_s12 <- length(only_ids) > 0L &&
  all(only_ids %in% c("Table S12"))
py_extra <- if (isTRUE(only_baseline)) {
  "--only-baseline"
} else if (isTRUE(only_s12)) {
  "--only-s12"
} else {
  ""
}
cmd <- paste(
  shQuote(py_bin), shQuote(py_compute),
  "--success-root", shQuote(success_root),
  "--out-dir", shQuote(payload_dir),
  py_extra
)
message("Running: ", cmd)
st <- system(cmd)
if (!identical(as.integer(st), 0L)) {
  stop("Python compute failed with status ", st, call. = FALSE)
}

.read_payload <- function(name, all_character = FALSE) {
  fp <- file.path(payload_dir, name)
  if (!file.exists(fp)) stop("Missing payload: ", fp, call. = FALSE)
  if (isTRUE(all_character)) {
    utils::read.csv(fp, check.names = FALSE, stringsAsFactors = FALSE, colClasses = "character")
  } else {
    utils::read.csv(fp, check.names = FALSE, stringsAsFactors = FALSE)
  }
}

.export_one <- function(df, title, footnotes = NULL,
                        header_row1 = NULL, header_row2 = NULL,
                        header_row3 = NULL,
                        col_widths = NULL, body_center_all = FALSE) {
  fp <- file.path(sum_tables, paste0(title, ".xlsx"))
  export_sci_table(
    df = df,
    filepath = fp,
    title = title,
    sheet = "Table",
    table_footnotes = footnotes,
    header_row1 = header_row1,
    header_row2 = header_row2,
    header_row3 = header_row3,
    col_widths = col_widths,
    body_center_all = body_center_all
  )
  invisible(fp)
}

# Wang S1: three-level header
.prepare_s1_hypothesis <- function(df) {
  cohort_order <- c(
    "Training", "Internal validation",
    "Cohort 1 Med-Surg", "Cohort 2 other",
    "Cohort 1", "Cohort 2"
  )
  cn <- names(df)
  prefixes <- unique(sub("__.*$", "", cn[grepl("__", cn)]))
  prefixes <- prefixes[prefixes %in% cohort_order]
  # stable order
  want <- c("Training", "Internal validation", "Cohort 1 Med-Surg", "Cohort 2 other")
  prefixes <- c(intersect(want, prefixes), setdiff(prefixes, want))
  if (!length(prefixes)) stop("S1 hypothesis payload missing cohort__* columns", call. = FALSE)
  body <- data.frame(Variable = as.character(df[["Variable"]]), stringsAsFactors = FALSE)
  h1 <- c("Variable")
  h2 <- c(NA_character_)
  h3 <- c(NA_character_)
  for (pfx in prefixes) {
    cols <- paste0(pfx, c("__Levene_F", "__Levene_p", "__Stat", "__Stat_p"))
    miss <- setdiff(cols, cn)
    if (length(miss)) stop("S1 missing columns: ", paste(miss, collapse = ", "), call. = FALSE)
    for (c in cols) body[[c]] <- as.character(df[[c]])
    h1 <- c(h1, rep(pfx, 4L))
    h2 <- c(h2, "Levene's Test", "Levene's Test", "t-test chi-square test", "t-test chi-square test")
    h3 <- c(h3, "F-value", "p-value", "t-value (or \u03c7\u00b2)", "p-value")
  }
  names(body) <- paste0("V", seq_len(ncol(body)))
  list(df = body, header_row1 = h1, header_row2 = h2, header_row3 = h3, cohorts = prefixes)
}

.prepare_s2_combo <- function(df) {
  # Delete variables | Delete variables | AUC | Final scheme
  # Engine multi-header requires ≥2 header rows; single custom row → set colnames.
  nm <- names(df)
  d1 <- if ("Delete variables" %in% nm) df[["Delete variables"]] else df[[1]]
  d2 <- if ("Delete variables_2" %in% nm) df[["Delete variables_2"]] else if (ncol(df) >= 2) df[[2]] else ""
  auc <- if ("AUC" %in% nm) df[["AUC"]] else df[[3]]
  fin <- if ("Final scheme" %in% nm) df[["Final scheme"]] else df[[ncol(df)]]
  body <- data.frame(
    `Delete variables` = as.character(d1),
    `Delete variables ` = as.character(d2),  # trailing space keeps unique colnames
    AUC = as.character(auc),
    `Final scheme` = as.character(fin),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  list(df = body, header_row1 = NULL, header_row2 = NULL, header_row3 = NULL)
}

.prepare_s3_pairwise <- function(df) {
  # Wang ESM: Variable 1 | Variable 2 | AUC (span 2) | Final retained
  #           (blank)     | (blank)    | Retention of variable 1 | Retention of variable 2 | (blank)
  need <- c("Variable_1", "Variable_2", "AUC retention_1", "AUC retention_2", "Final retained")
  for (c in need) if (!c %in% names(df)) stop("S3 missing column: ", c, call. = FALSE)
  body <- data.frame(
    V1 = as.character(df$Variable_1),
    V2 = as.character(df$Variable_2),
    V3 = as.character(df[["AUC retention_1"]]),
    V4 = as.character(df[["AUC retention_2"]]),
    V5 = as.character(df[["Final retained"]]),
    stringsAsFactors = FALSE
  )
  list(
    df = body,
    # Display names without underscores (pub_no_underscore); vertical span via h2=NA
    header_row1 = c("Variable 1", "Variable 2", "AUC", "AUC", "Final retained variables"),
    header_row2 = c(NA_character_, NA_character_, "Retention of variable 1", "Retention of variable 2", NA_character_),
    header_row3 = NULL,
    col_widths = c(16, 16, 24, 24, 22),
    body_center_all = TRUE
  )
}

.prepare_s5_twin <- function(df) {
  body <- data.frame(
    `Top n variables` = as.character(df[[1]]),
    AUC = as.character(df[[2]]),
    `Top n variables ` = as.character(df[[3]]),
    `AUC ` = as.character(df[[4]]),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  list(df = body, header_row1 = NULL, header_row2 = NULL, header_row3 = NULL)
}

.prepare_s11_twin <- function(df) {
  body <- data.frame(
    Number = as.character(df[[1]]),
    Feature = as.character(df[[2]]),
    `Missing rate (%)` = as.character(df[[3]]),
    `Number ` = as.character(df[[4]]),
    `Feature ` = as.character(df[[5]]),
    `Missing rate (%) ` = as.character(df[[6]]),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  list(df = body, header_row1 = NULL, header_row2 = NULL, header_row3 = NULL)
}

.prepare_s12_auc <- function(df) {
  body <- data.frame(
    V1 = as.character(df[[1]]),
    V2 = as.character(df[[2]]),
    V3 = as.character(df[[3]]),
    V4 = as.character(df[[4]]),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  # Reject NA sea before export
  auc_cols <- body[, 3:4, drop = FALSE]
  na_like <- function(x) {
    x <- trimws(as.character(x))
    !nzchar(x) | toupper(x) %in% c("NA", "N/A", "NAN") | grepl("^N/A", x, ignore.case = TRUE)
  }
  n_na <- sum(vapply(auc_cols, function(col) sum(na_like(col)), integer(1)))
  if (n_na > 2L) {
    stop(
      "Table S12 has ", n_na,
      " NA-like AUC cells — re-run rebuild_wang2025_tcf_tables_compute.py --only-s12",
      call. = FALSE
    )
  }
  list(
    df = body,
    header_row1 = c("Cohort", "Sample Size (No. of Positives)", "AUC", "AUC"),
    header_row2 = c(NA_character_, NA_character_, "Before Sampling", "After Sampling"),
    header_row3 = NULL
  )
}

specs <- list(
  list(
    id = "Table 1",
    file = "table1_baseline.csv",
    title = "Table 1. Baseline characteristics of the study population",
    footnotes = c(
      "Values are median (IQR) for continuous variables and n (%) for categorical variables.",
      "Columns: MIMIC training, MIMIC internal validation, and eICU external cohort.",
      "Feature columns reflect the final TCF feature set after entropy stepwise selection."
    )
  ),
  list(
    id = "Table 2",
    file = "table2_internal_performance.csv",
    title = "Table 2. Internal validation performance of seven sub-models and TCF",
    footnotes = c(
      "Metrics: AUC, F1, ACC, PRE, SEN, SPE with bootstrap 95% CI.",
      paste0("Bootstrap n_boot=", 400, ", seed=", 42, "; classification threshold=", 0.5, " (prob >= thr)."),
      "Source: proba_valid/*.csv with labels from valid.csv."
    )
  ),
  list(
    id = "Table S1",
    file = "table_s1_hypothesis.csv",
    title = "Table S1. Hypothesis testing results for Training, Internal validation, Cohort 1 Med-Surg, and Cohort 2 other",
    footnotes = c(
      "Within each cohort, final TCF model features were compared between in-hospital death and survivors.",
      "Levene's test for continuous variables; Student or Welch t-test (Levene P threshold 0.05). Categorical: '/' under Levene; chi-square or Fisher exact.",
      "Cohort 1 Med-Surg = eICU Med-Surg ICU; Cohort 2 other = remaining eICU unit types.",
      "Three-level header aligned with Wang 2025 Supplementary Table 1.",
      "Rows restricted to the final 30 model features (not a full demographics dump)."
    ),
    prepare = "s1_hypothesis"
  ),
  list(
    id = "Table S2",
    file = "table_s2_corr_combo.csv",
    title = "Table S2. Comparison of highly correlated variable combinations",
    footnotes = c(
      "Wang ESM layout: each row deletes two variables from a triad and reports univariable training AUC of the retained variable; √ marks the final scheme.",
      "No size≥3 clique at |Pearson r|≥0.7 in this cohort. Exploratory shock-index triad SI/HR/PP used (only SI–HR exceeded 0.7); see table_s2_meta.json.",
      "Production pairwise drops (Hematocrit/RBC, Chloride/Sodium, SI/HR) are reported in Table S3."
    ),
    prepare = "s2_combo"
  ),
  list(
    id = "Table S3",
    file = "table_s3_corr_auc_pairwise.csv",
    title = "Table S3. Results of pairwise comparisons of highly correlated variables",
    footnotes = c(
      "Exhaustive pairwise screen among the 33 candidates entering the |Pearson r|≥0.7 filter (before corr drop); univariable training AUC bake-off retains the higher-AUC variable.",
      "Only 3 pairs met |r|≥0.7 in this cohort (same as production greedy drops): Hematocrit–RBC, Chloride–Sodium, SI–HR. SI–PP and HR–PP were below 0.7; AST–ALT max |r|≈0.61."
    ),
    prepare = "s3_pairwise"
  ),
  list(
    id = "Table S4",
    file = "table_s4_imputation_methods.csv",
    title = "Table S4. Comparison of results from different methods of imputing missing values",
    footnotes = c(
      "Training-set 3-fold stratified CV ROC-AUC of logistic regression after each imputation method.",
      "k-NN AUC used an n=2,500 training subsample for computational feasibility.",
      "Production pipeline used MICE logistic_mi (m=5, fit_on=train, complete_action=1); that row is the operational choice.",
      "No fabricated AUCs; methods not computed are omitted rather than invented."
    )
  ),
  list(
    id = "Table S5",
    file = "table_s5_entropy_path.csv",
    title = "Table S5. Stepwise inclusion of variables based on entropy ranking for modeling",
    footnotes = c(
      "Features prioritized by information entropy; AUC tracked as top-n grows (source: tcf_entropy_path.csv).",
      "Asterisk (*) marks the optimal feature count (maximum AUC on the path).",
      "Twin-panel layout aligned with Wang 2025 Supplementary Table 5."
    ),
    prepare = "s5_twin"
  ),
  list(
    id = "Table S6",
    file = "table_s6_hyperparameters.csv",
    title = "Table S6. Hyperparameter tuning information for various models on the training set",
    footnotes = c(
      "All parameters obtained via RandomizedSearchCV (cv=5, scoring=roc_auc).",
      "Range = search space from train_tcf_bundle.py; Optimum value = get_params() of fitted joblib models."
    )
  ),
  list(
    id = "Table S7",
    file = "table_s7_submodels_train.csv",
    title = "Table S7. Evaluation of classification performance for seven sub-models on the training set",
    footnotes = c(
      "Performance of seven sub-models on the TRAINING set (Wang 2025 ESM caption); bootstrap 95% CI (n_boot=400, seed=42).",
      "Predictions: MinMaxScaler.transform(analytic training rows) → fitted base learners (models were fit on SMOTE-resampled training).",
      "Column order: AUC, F1-score, ACC, PRE, SEN, SPE. Threshold=0.5."
    )
  ),
  list(
    id = "Table S8",
    file = "table_s8_topsis.csv",
    title = "Table S8. TOPSIS integration components for the TCF model",
    footnotes = c(
      "TOPSIS on six internal-validation metrics (AUC, F1, ACC, PRE, SEN, SPE) with equal weights.",
      "PIS/NIS = distances to positive/negative ideal solutions; α_i = normalized TOPSIS score used as TCF fusion weight; Ranking_min_max = α_i.",
      "This is NOT a classification-performance table (see Table S10 for TCF metrics across datasets)."
    )
  ),
  list(
    id = "Table S9",
    file = "table_s9_feature_importance.csv",
    title = "Table S9. TCF feature importance ranking",
    footnotes = c(
      "Built-in feature_importances_ from tree models (normalized to sum 1 per model), then SUM and Rank.",
      "Columns: DT, RF, XGB, LGBM, GBDT (SVM/NB have no impurity importance)."
    )
  ),
  list(
    id = "Table S10",
    file = "table_s10_tcf_across_datasets.csv",
    title = "Table S10. Performance of the TCF across different datasets",
    footnotes = c(
      "Datasets: Training (apparent, in-sample), Internal validation, Cohort 1 (Med-Surg ICU), Cohort 2 (other unit types), and eICU overall.",
      "Bootstrap 95% CI (n_boot=400; seed Internal=42+0, Cohort1=42+2, Cohort2=42+3, eICU overall=42+4; Training=42+0 on a different sample); threshold=0.5.",
      "Internal TCF AUC/CI strings lock with Table 2 TCF and Figure 5 / Figure 6.",
      "Wang ESM reported six strata; this study has four primary strata (+ optional eICU overall).",
      "Training-set AUC near 1.000 is apparent in-sample optimism and is omitted from Figure 6; primary inference is internal validation and eICU."
    )
  ),
  list(
    id = "Table S11",
    file = "table_s11_train_missing_before_imputation.csv",
    title = "Table S11. The missing rate of the training dataset",
    footnotes = c(
      "Missing rates of the final TCF features on the MIMIC training set before imputation.",
      "Twin-panel Number | Feature | Missing rate (%) layout aligned with Wang 2025 Supplementary Table 11."
    ),
    prepare = "s11_twin"
  ),
  list(
    id = "Table S12",
    file = "table_s12_oversampling_validation.csv",
    title = "Table S12. Validation results related to oversampling",
    footnotes = c(
      "Wang ESM Supplementary Table 12 compared TCF AUC before vs after oversampling validation cohorts with <100 positives.",
      "In this study every evaluation cohort has ≥100 events, so validation rows were not resampled; SMOTE (1:1) was applied on the MIMIC training set only (after MinMax).",
      "AUC Before Sampling = TCF fused from seven base learners re-fit with Table S6 optima on non-SMOTE MinMax-scaled MIMIC training, using production TOPSIS α; scored on each cohort.",
      "AUC After Sampling = production SMOTE-trained TCF probabilities (same as Table S10 AUC for Internal / Cohort 1 / Cohort 2 / Training).",
      "Training-set AUCs are in-sample under the same Before/After definitions (for completeness; primary inference uses Internal validation and eICU cohorts).",
      paste0("Bootstrap n_boot=", 400, ", seed=", 42, "; After column uses the same bootstrap offsets as Table S10.")
    ),
    prepare = "s12_auc"
  ),
  list(
    id = "Table S13",
    file = "table_s13_tripod_ai.csv",
    title = "Table S13. TRIPOD+AI guidelines checklist for this study",
    footnotes = c(
      "TRIPOD+AI self-assessment for the present SA-AKI TCF delivery (development + evaluation).",
      "Reported = ✓ / Partial / N/A. Unchecked/N/A items are inapplicable or not documented in the delivery folder.",
      "Location/note points to delivery artefacts (Tables/Figures/Methods), not journal page numbers."
    )
  )
)

produced <- list()
gaps <- character()

meta_fp <- file.path(payload_dir, "_compute_meta.json")
if (file.exists(meta_fp)) {
  meta <- jsonlite::fromJSON(meta_fp)
  if (!is.null(meta$gaps) && length(meta$gaps)) {
    gaps <- c(gaps, as.character(meta$gaps))
  }
}
if (!isTRUE(only_baseline)) {
  gaps <- c(
    gaps,
    paste0(
      "Table S10 Training-set TCF AUC near 1.000 from in-sample fused predictions; ",
      "primary metrics = Internal + eICU / Cohort1–2"
    )
  )
}

if (length(only_ids)) {
  specs <- Filter(function(sp) sp$id %in% only_ids, specs)
  if (!length(specs)) {
    stop("No matching specs for --only: ", paste(only_ids, collapse = ", "), call. = FALSE)
  }
}

for (sp in specs) {
  message("Exporting ", sp$id, " …")
  payload_file <- sp$file
  # Fallbacks for renamed payloads
  if (!file.exists(file.path(payload_dir, payload_file))) {
    alts <- switch(
      sp$id,
      "Table S1" = c("table_s1_group_comparison.csv"),
      "Table S2" = c("table_s2_corr_pairs.csv"),
      "Table S4" = c("table_s4_imputation_note.csv"),
      "Table S7" = c("table_s7_submodels_valid.csv"),
      "Table S8" = c("table_s8_tcf_performance.csv"),
      character(0)
    )
    for (alt in alts) {
      if (file.exists(file.path(payload_dir, alt))) {
        payload_file <- alt
        message("  (fallback payload ", alt, ")")
        break
      }
    }
  }
  read_as_chr <- identical(sp$prepare %||% "", "s1_hypothesis") ||
    identical(sp$id, "Table S1")
  df <- tryCatch(.read_payload(payload_file, all_character = read_as_chr), error = function(e) {
    gaps <<- c(gaps, paste0(sp$id, ": missing payload ", payload_file, " — ", e$message))
    NULL
  })
  if (is.null(df) || !nrow(df)) {
    gaps <- c(gaps, paste0(sp$id, ": empty payload"))
    next
  }
  hdr1 <- NULL
  hdr2 <- NULL
  hdr3 <- NULL
  col_w <- NULL
  body_c_all <- FALSE
  prep_name <- sp$prepare %||% ""
  if (identical(prep_name, "s1_hypothesis") ||
      (identical(sp$id, "Table S1") && any(grepl("__Levene_F$", names(df))))) {
    prep <- .prepare_s1_hypothesis(df)
    df <- prep$df; hdr1 <- prep$header_row1; hdr2 <- prep$header_row2; hdr3 <- prep$header_row3
    message("  S1 cohorts: ", paste(prep$cohorts, collapse = " | "))
  } else if (identical(prep_name, "s2_combo")) {
    prep <- .prepare_s2_combo(df)
    df <- prep$df; hdr1 <- prep$header_row1
  } else if (identical(prep_name, "s3_pairwise")) {
    prep <- .prepare_s3_pairwise(df)
    df <- prep$df; hdr1 <- prep$header_row1; hdr2 <- prep$header_row2
    col_w <- prep$col_widths %||% NULL
    body_c_all <- isTRUE(prep$body_center_all %||% FALSE)
  } else if (identical(prep_name, "s5_twin")) {
    prep <- .prepare_s5_twin(df)
    df <- prep$df; hdr1 <- prep$header_row1
  } else if (identical(prep_name, "s11_twin")) {
    prep <- .prepare_s11_twin(df)
    df <- prep$df; hdr1 <- prep$header_row1
  } else if (identical(prep_name, "s12_auc")) {
    prep <- .prepare_s12_auc(df)
    df <- prep$df; hdr1 <- prep$header_row1; hdr2 <- prep$header_row2
  }
  if (exists("pipeline_scrub_pub_df", mode = "function")) {
    # Keep √ checkmarks — scrub may strip symbols; protect Final scheme column
    df <- pipeline_scrub_pub_df(df)
  }
  .export_one(
    df, sp$title, footnotes = sp$footnotes,
    header_row1 = hdr1, header_row2 = hdr2, header_row3 = hdr3,
    col_widths = col_w, body_center_all = body_c_all
  )
  produced[[sp$id]] <- list(
    title = sp$title,
    rows = nrow(df),
    cols = ncol(df),
    payload = payload_file,
    header_row1 = hdr1
  )
}

message("Flushing queued tables via render_queued_tables …")
invisible(render_queued_tables(list()))

.surg <- file.path(engine_root, "R", "pub_xlsx_surgical.R")
if (file.exists(.surg)) {
  try(source(.surg, local = FALSE), silent = TRUE)
}
if (exists("pub_xlsx_strip", mode = "function")) {
  for (xp in list.files(sum_tables, pattern = "^Table .*\\.xlsx$", full.names = TRUE)) {
    try(pub_xlsx_strip(xp), silent = TRUE)
  }
}

.mirror_tables <- function(from_dir, to_dir) {
  xlsx <- list.files(from_dir, pattern = "^Table .*\\.xlsx$", full.names = TRUE)
  copied <- character()
  for (f in xlsx) {
    file.copy(f, file.path(to_dir, basename(f)), overwrite = TRUE)
    copied <- c(copied, basename(f))
  }
  tex <- list.files(from_dir, pattern = "^Table .*\\.tex$", full.names = TRUE)
  for (f in tex) {
    file.copy(f, file.path(to_dir, basename(f)), overwrite = TRUE)
  }
  copied
}

copied <- .mirror_tables(sum_tables, idx_tables)
message("Mirrored ", length(copied), " xlsx tables to index Tables/")

actual <- list.files(sum_tables, pattern = "^Table .*\\.xlsx$")
bad_tag <- actual[grepl("-(MIMIC|eICU|UnknownDB)\\.", actual, ignore.case = TRUE)]
if (length(bad_tag)) {
  gaps <- c(gaps, paste0("Filename still has DB tag: ", bad_tag))
}

id_present <- function(id_pat) any(grepl(id_pat, actual, perl = TRUE))
checklist <- list(
  "Table 1" = id_present("^Table 1\\."),
  "Table 2" = id_present("^Table 2\\."),
  "Table S1" = id_present("^Table S1\\."),
  "Table S2" = id_present("^Table S2\\."),
  "Table S3" = id_present("^Table S3\\."),
  "Table S4" = id_present("^Table S4\\."),
  "Table S5" = id_present("^Table S5\\."),
  "Table S6" = id_present("^Table S6\\."),
  "Table S7" = id_present("^Table S7\\."),
  "Table S8" = id_present("^Table S8\\."),
  "Table S9" = id_present("^Table S9\\."),
  "Table S10" = id_present("^Table S10\\."),
  "Table S11" = id_present("^Table S11\\."),
  "Table S12" = id_present("^Table S12\\."),
  "Table S13" = id_present("^Table S13\\.")
)
check_ids <- if (length(only_ids)) only_ids else names(checklist)
missing <- check_ids[!vapply(check_ids, function(nm) isTRUE(checklist[[nm]]), logical(1))]
if (length(missing)) gaps <- c(gaps, paste0("Missing: ", paste(missing, collapse = ", ")))

# Role checks
.verify_roles <- function() {
  notes <- character()
  # S8 must be TOPSIS
  s8 <- actual[grepl("^Table S8\\.", actual)][1]
  if (!is.na(s8)) {
    notes <- c(notes, paste0("S8 file: ", s8))
    if (!grepl("TOPSIS", s8, ignore.case = TRUE)) {
      notes <- c(notes, "WARN: S8 filename should mention TOPSIS")
    }
  }
  s7 <- actual[grepl("^Table S7\\.", actual)][1]
  if (!is.na(s7) && !grepl("training", s7, ignore.case = TRUE)) {
    notes <- c(notes, "WARN: S7 filename should say training set")
  }
  notes
}
role_notes <- .verify_roles()

manifest <- list(
  generated_at = as.character(Sys.time()),
  success_root = success_root,
  summary_tables = sum_tables,
  index_tables = idx_tables,
  rebuild_workspace = rebuild_ws,
  archive_dir = archive_dir,
  payload_dir = payload_dir,
  archived_summary = moved_sum,
  archived_index = moved_idx,
  produced = produced,
  actual_xlsx = actual,
  checklist = checklist,
  role_notes = role_notes,
  gaps = gaps,
  n_boot = 400L,
  seed = 42L,
  threshold = 0.5,
  wang_esm_aligned = TRUE,
  engine_utils = utils_path
)

manifest_fp <- file.path(rebuild_ws, "rebuild_wang2025_tables_manifest.json")
jsonlite::write_json(manifest, manifest_fp, auto_unbox = TRUE, pretty = TRUE)

message("=== Wang 2025 tables rebuild checklist ===")
for (nm in names(checklist)) {
  message(sprintf("  %s: %s", nm, if (isTRUE(checklist[[nm]])) "PRESENT" else "MISSING"))
}
if (length(role_notes)) {
  message("Role notes:")
  for (g in role_notes) message("  - ", g)
}
if (length(gaps)) {
  message("Gaps:")
  for (g in gaps) message("  - ", g)
}
message("Manifest: ", manifest_fp)
message("Done.")
