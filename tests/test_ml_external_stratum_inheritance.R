# tests/test_ml_external_stratum_inheritance.R
# Task 5: an external stratum may only inherit the MIMIC assets of the SAME stratum.
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

set.seed(4242L)

make_ctx <- function(n = 80L, seed = 3L) {
  old <- set.seed(seed); on.exit(set.seed(old), add = TRUE)
  sofa <- sample(3:18, n, replace = TRUE)
  d <- data.frame(
    patient_id = sprintf("Q%03d", seq_len(n)),
    SOFA = sofa,
    x1 = round(rnorm(n), 2), x2 = round(rnorm(n), 2), x3 = round(rnorm(n), 2),
    f1 = factor(sample(c("No", "Yes"), n, replace = TRUE), levels = c("No", "Yes")),
    stringsAsFactors = FALSE
  )
  d$Death_label <- factor(ifelse(stats::rbinom(
    n, 1, plogis(-1.5 + 0.5 * d$x1 + 0.2 * sofa / 10)) == 1L,
    "Non-survivor", "Survivor"), levels = c("Survivor", "Non-survivor"))
  d$Group <- d$Death_label
  rownames(d) <- paste0("row_", d$patient_id)
  tr <- seq_len(56L); te <- 57:n
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
    config = cfg,
    data = list(imputed = d, train = d[tr, , drop = FALSE],
                test = d[te, , drop = FALSE]),
    results = list(Model2Factors = c("x1", "x2", "x3", "f1")),
    log = list(), models = list()
  )
}

tmp <- tempfile("stratum_inherit_")
dir.create(tmp, recursive = TRUE)
assets <- file.path(tmp, "model_assets")
ctx <- make_ctx()

low <- ml_fit_stratum_bundle(ctx, "sofa_0_10", "logistic",
                             assets_root = assets, quiet = TRUE)
high <- ml_fit_stratum_bundle(ctx, "sofa_11plus", "logistic",
                              assets_root = assets, quiet = TRUE)
dir_low <- ml_save_frozen_bundle(low, file.path(assets, "sofa_0_10"))
dir_high <- ml_save_frozen_bundle(high, file.path(assets, "sofa_11plus"))
stopifnot(dir_low != dir_high)
stopifnot(identical(low$stratum$key, "sofa_0_10"))
stopifnot(identical(high$stratum$key, "sofa_11plus"))

# external data: eICU rows must belong to the SAME stratum as the asset
eicu_low <- ctx$data$imputed[ctx$data$imputed$SOFA <= 10, , drop = FALSE]
eicu_low$patient_id <- paste0("E", sub("^Q", "", eicu_low$patient_id))
rownames(eicu_low) <- paste0("ei_", eicu_low$patient_id)
eicu_high <- ctx$data$imputed[ctx$data$imputed$SOFA >= 11, , drop = FALSE]
eicu_high$patient_id <- paste0("H", sub("^Q", "", eicu_high$patient_id))
rownames(eicu_high) <- paste0("ei_", eicu_high$patient_id)

b_low <- ml_load_frozen_bundle(dir_low)
b_high <- ml_load_frozen_bundle(dir_high)

# eICU sofa_0_10 request must load the sofa_0_10 asset only
res <- ml_predict_external_bundle(b_low, eicu_low, stratum = "sofa_0_10",
                                  database = "eICU")
stopifnot(res$provenance$stratum == "sofa_0_10")
stopifnot(res$provenance$asset_dir == normalizePath(dir_low, winslash = "/",
                                                    mustWork = FALSE))
stopifnot(res$provenance$external_database == "eICU")
stopifnot(nrow(res$predictions) == nrow(eicu_low))

# requesting the other stratum's asset must hard fail
cross <- tryCatch(
  ml_predict_external_bundle(b_high, eicu_low, stratum = "sofa_0_10",
                             database = "eICU"),
  error = identity
)
stopifnot(inherits(cross, "error"))
stopifnot(grepl("stratum", conditionMessage(cross), ignore.case = TRUE))

# I1: data-level stratum check — feeding SOFA>=11 rows to the sofa_0_10 asset
# (WITHOUT the explicit stratum argument) must hard fail with a violation count.
n_viol <- nrow(eicu_high)
stopifnot(n_viol > 0L)
soft <- tryCatch(
  ml_predict_external_bundle(b_low, eicu_high, database = "eICU"),
  error = identity
)
stopifnot(inherits(soft, "error"))
stopifnot(grepl("stratum", conditionMessage(soft), ignore.case = TRUE))
stopifnot(grepl(as.character(n_viol), conditionMessage(soft), fixed = TRUE))
# and rows from the wrong stratum never slip through a matching stratum arg
mixed <- rbind(eicu_low, eicu_high[seq_len(3L), , drop = FALSE])
mixed_viol <- tryCatch(
  ml_predict_external_bundle(b_low, mixed, stratum = "sofa_0_10"),
  error = identity
)
stopifnot(inherits(mixed_viol, "error"))
stopifnot(grepl("3", conditionMessage(mixed_viol), fixed = TRUE))
# overall asset skips the membership check (no cutoff to enforce)
res_any <- ml_predict_external_bundle(b_high, eicu_high, database = "eICU")
stopifnot(nrow(res_any$predictions) == nrow(eicu_high))

# and loading by key through the directory resolver must pick the right asset
resolved <- ml_resolve_stratum_asset(assets, "sofa_11plus")
stopifnot(normalizePath(resolved, winslash = "/", mustWork = FALSE) ==
            normalizePath(dir_high, winslash = "/", mustWork = FALSE))
unknown <- tryCatch(ml_resolve_stratum_asset(assets, "sofa_ge99"),
                    error = identity)
stopifnot(inherits(unknown, "error"))

# the bundle refuses to answer for a stratum that is not its own
mislabel <- b_low
mislabel$stratum$key <- "sofa_11plus"
bad <- tryCatch(ml_predict_external_bundle(mislabel, eicu_low,
                                           stratum = "sofa_0_10"),
                error = identity)
stopifnot(inherits(bad, "error"))
stopifnot(grepl("stratum", conditionMessage(bad), ignore.case = TRUE))

# manifest records the stratum definition (variable + cutoff + label)
man <- jsonlite::fromJSON(file.path(dir_low, "manifest.json"),
                          simplifyVector = FALSE)
stopifnot(identical(as.character(man$stratum$variable), "SOFA"))
stopifnot(identical(as.numeric(man$stratum$upper), 10))
stopifnot(identical(as.character(man$stratum$label), "SOFA 0–10"))
man_h <- jsonlite::fromJSON(file.path(dir_high, "manifest.json"),
                            simplifyVector = FALSE)
stopifnot(identical(as.character(man_h$stratum$label), "SOFA ≥11"))

# no recursive evalresult scanning is allowed to invent strata
stale <- file.path(tmp, "Models")
dir.create(stale, recursive = TRUE)
fake <- new.env(parent = emptyenv())
assign("final_logistic", "junk", envir = fake)
save(list = ls(fake), file = file.path(stale, "evalresult_logistic.RData"),
     envir = fake)
scanned <- tryCatch(ml_fit_stratum_bundle(ctx, "sofa_0_10", "logistic",
                                          assets_root = file.path(tmp, "na"),
                                          quiet = TRUE),
                    error = function(e) e)
stopifnot(inherits(scanned, "ml_frozen_bundle"))
# the fit never reads the stray evalresult dump: scan guard returns empty
hits <- ml_frozen_scan_evalresults(stale)
stopifnot(is.character(hits), length(hits) == 0L)
stopifnot(!isTRUE(getOption("ml_frozen_allow_evalresult_scan", FALSE)))

unlink(tmp, recursive = TRUE)
cat("test_ml_external_stratum_inheritance: OK\n")
