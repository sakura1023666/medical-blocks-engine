# tests/test_ml_factor_schema_external.R
# Task 5: external factor schema audit — missing features hard-fail, unseen
# factor levels are recorded as level -> NA counts and never silently numericised.
root <- normalizePath(".")
impl <- file.path(root, "R/ml_frozen_model_bundle.R")
stopifnot(file.exists(impl))
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
suppressWarnings(suppressMessages({
  source(file.path(root, "R/utils.R"), local = FALSE)
  source(file.path(root, "R/ml_stratified_ctx.R"), local = FALSE)
  source(file.path(root, "R/ml_dual_dev_ext.R"), local = FALSE)
  source(impl, local = FALSE)
}))

set.seed(909L)

make_ctx <- function(n = 80L, seed = 5L) {
  old <- set.seed(seed); on.exit(set.seed(old), add = TRUE)
  d <- data.frame(
    patient_id = sprintf("F%03d", seq_len(n)),
    SOFA = sample(2:12, n, replace = TRUE),
    x1 = round(rnorm(n), 2), x2 = round(rnorm(n), 2), x3 = round(rnorm(n), 2),
    f1 = factor(sample(c("No", "Yes"), n, replace = TRUE), levels = c("No", "Yes")),
    f2 = factor(sample(c("A", "B", "C"), n, replace = TRUE), levels = c("A", "B", "C")),
    stringsAsFactors = FALSE
  )
  d$Death_label <- factor(ifelse(stats::rbinom(
    n, 1, plogis(-1 + 0.6 * d$x1 + 0.3 * d$x2)) == 1L,
    "Non-survivor", "Survivor"), levels = c("Survivor", "Non-survivor"))
  d$Group <- d$Death_label
  rownames(d) <- paste0("fr_", d$patient_id)
  cfg <- list(
    project = list(
      study_type = "prognosis", database = "MIMIC_IV",
      analysis_group = "Non-survivor", reference_group = "Survivor",
      output_dir = tempdir()
    ),
    data = list(id_column = "patient_id", outcome_column = "Death_label"),
    splitting = list(seed = 42L, train_ratio = 0.7),
    train_validation = list(mode = "split"),
    feature_selection = list(enable = FALSE),
    ml_models = list(cv_folds = 2L),
    ml_logistic = list(pause_enable = FALSE, cv_folds = 2L),
    ml_frozen_bundle = list(sofa_breaks = 10L),
    ml_stratified_ctx = list(patient_slots = character(0))
  )
  list(
    config = cfg, data = list(imputed = d, train = d[seq_len(56L), , drop = FALSE],
                              test = d[57:n, , drop = FALSE]),
    results = list(Model2Factors = c("x1", "x2", "x3", "f1", "f2")),
    log = list(), models = list()
  )
}

tmp <- tempfile("factor_schema_")
dir.create(tmp, recursive = TRUE)
ctx <- make_ctx()
bundle <- ml_fit_stratum_bundle(ctx, "sofa_0_10", "logistic",
                                assets_root = file.path(tmp, "model_assets"),
                                quiet = TRUE)
dir <- ml_save_frozen_bundle(bundle, file.path(tmp, "model_assets", "sofa_0_10"))
frozen <- ml_load_frozen_bundle(dir)
stopifnot(identical(unname(frozen$factor_levels$f1), c("No", "Yes")))
stopifnot(identical(unname(frozen$factor_levels$f2), c("A", "B", "C")))

ext <- ctx$data$imputed[ctx$data$imputed$SOFA <= 10, , drop = FALSE]
ext <- ext[seq_len(20L), , drop = FALSE]

# clean pass: no audit rows (factors carry only trained levels)
ext0 <- ctx$data$imputed[ctx$data$imputed$SOFA <= 10, , drop = FALSE]
ext0 <- ext0[seq_len(20L), , drop = FALSE]
clean <- ml_predict_external_bundle(frozen, ext0, stratum = "sofa_0_10")
stopifnot(nrow(clean$factor_audit) == 0L)
stopifnot(nrow(clean$predictions) == nrow(ext0))

# unseen factor levels are audited, never silently coerced
# (external data may arrive with its OWN level set, e.g. coded as character)
ext$f1 <- c(rep("Maybe", 3L), rep("No", 17L))
ext$f2 <- c(rep("Z", 2L), rep("A", 18L))
res <- ml_predict_external_bundle(frozen, ext, stratum = "sofa_0_10")
audit <- res$factor_audit
stopifnot(is.data.frame(audit), nrow(audit) >= 2L)
stopifnot(all(c("column", "level", "n_rows", "action") %in% names(audit)))
stopifnot(any(audit$column == "f1" & audit$level == "Maybe" & audit$n_rows == 3L))
stopifnot(any(audit$column == "f2" & audit$level == "Z" & audit$n_rows == 2L))
stopifnot(all(audit$action == "level->NA"))
stopifnot(identical(res$provenance$stratum, "sofa_0_10"))
# predictions still exist (recipe median/mode imputation downstream is engine
# standard), but the audit is explicit rather than silent
stopifnot(nrow(res$predictions) == nrow(ext))

# a character column that never existed in training must not be numericised:
# unknown levels -> audit rows
ext2 <- ext
ext2$f1 <- rep("Other", 20L)
ext2$f2 <- factor(rep("A", 20L), levels = c("A"))
res2 <- ml_predict_external_bundle(frozen, ext2, stratum = "sofa_0_10")
stopifnot(any(res2$factor_audit$column == "f1" &
                res2$factor_audit$level == "Other" &
                res2$factor_audit$n_rows == 20L))
stopifnot(all(res2$factor_audit$action == "level->NA"))
stopifnot(!isTRUE(res2$prepared$coerced_to_numeric))

# missing feature = hard failure listing the offending columns
missing <- ext[, setdiff(names(ext), c("x2", "f2")), drop = FALSE]
err <- tryCatch(ml_predict_external_bundle(frozen, missing, stratum = "sofa_0_10"),
                error = identity)
stopifnot(inherits(err, "error"))
msg <- conditionMessage(err)
stopifnot(grepl("missing", msg, ignore.case = TRUE) ||
            grepl("缺", msg))
stopifnot(grepl("x2", msg, fixed = TRUE), grepl("f2", msg, fixed = TRUE))

# the training factor levels themselves are frozen inside the manifest, so a
# fresh session can verify them without the original data object
man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
stopifnot(identical(unlist(man$factor_levels$f1), c("No", "Yes")))
stopifnot(identical(unlist(man$factor_levels$f2), c("A", "B", "C")))
stopifnot(all(unlist(man$features) %in% c("x1", "x2", "x3", "f1", "f2")))
stopifnot(identical(unlist(man$models$logistic$features), unlist(man$features)))

unlink(tmp, recursive = TRUE)
cat("test_ml_factor_schema_external: OK\n")
