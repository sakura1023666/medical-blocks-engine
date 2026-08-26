#!/usr/bin/env Rscript
# smoke_dementia_sens_anchor_elsa.R — Task 6: unfiltered ELSA AfterMI anchor concordance
# Loads AfterMI ELSA, prints tertile cuts (right=FALSE, 1/3+2/3), lock Model1/Model2;
# optionally runs one logistic_tertile_glm smoke and prints table footnotes.

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    return(normalizePath(
      file.path(dirname(sub("^--file=", "", f[1L])), ".."),
      winslash = "/"
    ))
  }
  normalizePath(getwd(), winslash = "/")
}

root <- .init_root()
setwd(root)

study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"
)
study <- normalizePath(study, winslash = "/", mustWork = TRUE)

suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("需要 cli")
})
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/cross_lagged_sensitivity.R"), local = FALSE)

cli::cli_h1("Task 6 — ELSA anchor concordance (unfiltered AfterMI)")

lock <- cross_lagged_sens_read_lock(study)
M1 <- lock$model1
M2 <- lock$model2
cat("lock Model1=", paste(M1, collapse = "+"), "\n", sep = "")
cat("lock Model2=", paste(M2, collapse = "+"), "\n", sep = "")

d <- cross_lagged_sens_load_imputed(study, "ELSA")
d <- cross_lagged_sens_normalize_disease_group(d)

if (!"Leisure_activities" %in% names(d)) stop("缺 Leisure_activities 列", call. = FALSE)

qs <- as.numeric(stats::quantile(d$Leisure_activities, probs = c(1 / 3, 2 / 3), na.rm = TRUE))
cat("n=", nrow(d), " cuts=", paste(round(qs, 6), collapse = ","), "\n", sep = "")

bl_tert <- list(tertile_right = FALSE, tertile_labels = c("T1", "T2", "T3"))
if (exists(".lqg05_tertile_from_cfg", mode = "function")) {
  tert <- .lqg05_tertile_from_cfg(d$Leisure_activities, bl_tert)
  cat("tertile_labels=", paste(levels(tert$group), collapse = "/"), "\n", sep = "")
  cat("cutoff_display=", paste(tert$cutoffs, collapse = " | "), "\n", sep = "")
} else {
  register_block <- function(...) invisible(NULL)
  source(file.path(root, "Blocks/11_logistic/05block_logistic_tertile_glm.R"), local = FALSE)
  tert <- .lqg05_tertile_from_cfg(d$Leisure_activities, bl_tert)
  cat("tertile_labels=", paste(levels(tert$group), collapse = "/"), "\n", sep = "")
  cat("cutoff_display=", paste(tert$cutoffs, collapse = " | "), "\n", sep = "")
}

stopifnot(nrow(d) == 5049L)
stopifnot(all(is.finite(qs)))

# --- Optional: one logistic_tertile_glm smoke (dementia bl_cfg, no random search) ---
logistic_ok <- FALSE
logistic_note <- character(0)
tryCatch({
  if (!exists(".lqg05_tertile_from_cfg", mode = "function")) {
    register_block <- function(...) invisible(NULL)
    source(file.path(root, "Blocks/11_logistic/05block_logistic_tertile_glm.R"), local = FALSE)
  }
  if (file.exists(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")))
    source(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"), local = FALSE)
  if (file.exists(file.path(root, "Blocks/11_logistic/00logistic_glm_common.R")))
    source(file.path(root, "Blocks/11_logistic/00logistic_glm_common.R"), local = FALSE)
  if (!exists("block_logistic_tertile_glm", mode = "function"))
    source(file.path(root, "Blocks/11_logistic/05block_logistic_tertile_glm.R"), local = FALSE)

  out_dir <- file.path(study, "sensitivity", "_smoke_anchor_elsa")
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  cfg <- list(
    project = list(
      name = "Dementia_Leisure_smoke_ELSA",
      disease = "Dementia",
      database = "ELSA",
      database_type = "regular",
      study_type = "incidence",
      classification_mode = "binary",
      analysis_group = "Dementia",
      reference_group = "Normal",
      output_dir = out_dir
    ),
    data = list(outcome_column = "Disease_Group", id_column = "ID"),
    incidence = list(outcome_var = "Disease_Group", index_var = "Leisure_activities"),
    logistic = list(index_var = "Leisure_activities", index_var_display_name = "Leisure_activities"),
    logistic_tertile_glm = list(
      pause_enable = FALSE,
      pause_on_search_fail = FALSE,
      gate_enable = FALSE,
      force_export = TRUE,
      index_var = "Leisure_activities",
      tertile_right = FALSE,
      tertile_labels = c("T1", "T2", "T3"),
      model1_factors = M1,
      model2_factors = M2,
      random_search = list(enable = FALSE),
      table_filename = "Table_smoke_anchor_ELSA_tertile.xlsx"
    ),
    logistic_covariates = list(
      model1_factors = M1,
      model2_factors = M2,
      random_search = list(enable = FALSE)
    ),
    covariate_policy = list(force_age = "Age" %in% M2 || "Age" %in% M1, force_sex = FALSE)
  )

  ctx <- list(
    config = cfg,
    data = list(imputed = d, cleaned = d, raw = d),
    results = list(Model1Factors = M1, Model2Factors = M2, vif_final_pass = M2),
    output_dir_tables = tab_dir,
    output_dir_figures = file.path(out_dir, "Figures"),
    current_block = "logistic_tertile_glm"
  )

  t0 <- Sys.time()
  ctx <- block_logistic_tertile_glm(ctx)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat("logistic_tertile_glm elapsed_sec=", round(elapsed, 2), "\n", sep = "")

  m1_used <- ctx$results$logistic_model1_factors %||% M1
  m2_used <- ctx$results$logistic_model2_factors %||% M2
  cat("used Model1=", paste(m1_used, collapse = "+"), "\n", sep = "")
  cat("used Model2=", paste(m2_used, collapse = "+"), "\n", sep = "")

  if (exists("logistic_glm_table_footnotes", mode = "function")) {
    fn <- logistic_glm_table_footnotes(m1_used, m2_used)
    cat("table_footnotes:\n")
    for (ln in fn) cat("  ", ln, "\n", sep = "")
  }

  xlsx <- file.path(tab_dir, cfg$logistic_tertile_glm$table_filename)
  if (file.exists(xlsx)) cat("xlsx=", xlsx, "\n", sep = "")

  logistic_ok <- TRUE
}, error = function(e) {
  logistic_note <<- c(logistic_note, conditionMessage(e))
  cli::cli_alert_warning("logistic_tertile_glm smoke skipped/failed: {e$message}")
})

if (logistic_ok) {
  cat("STATUS=DONE\n")
} else if (length(logistic_note)) {
  cat("STATUS=DONE_WITH_CONCERNS\n")
  cat("concern=", logistic_note[[1L]], "\n", sep = "")
} else {
  cat("STATUS=DONE_WITH_CONCERNS\n")
  cat("concern=logistic block not attempted\n")
}
