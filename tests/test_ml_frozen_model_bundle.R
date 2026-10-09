# tests/test_ml_frozen_model_bundle.R
# Task 5: stratified five-model frozen asset bundle (fit -> save -> load -> predict).
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

set.seed(20260917L)

make_fixture_ctx <- function(n = 90L, seed = 7L) {
  old <- set.seed(seed); on.exit(set.seed(old), add = TRUE)
  sofa <- sample(4:16, n, replace = TRUE)
  x1 <- round(rnorm(n, 60, 12), 2)
  x2 <- round(rnorm(n, 20, 5), 2)
  x3 <- round(rnorm(n, 100, 20), 2)
  f1 <- factor(sample(c("No", "Yes"), n, replace = TRUE), levels = c("No", "Yes"))
  noise <- as.data.frame(stats::setNames(
    lapply(1:11, function(k) round(rnorm(n, k * 10, 5), 2)),
    paste0("x", 3 + seq_len(11))
  ))
  lp <- -2.2 + 0.05 * (x1 - 60) + 0.06 * (x2 - 20) + 0.4 * (sofa > 10) +
    ifelse(f1 == "Yes", 0.5, 0)
  grp <- factor(ifelse(stats::rbinom(n, 1, plogis(lp)) == 1L,
                       "Non-survivor", "Survivor"),
                levels = c("Survivor", "Non-survivor"))
  d <- cbind(
    data.frame(
      patient_id = sprintf("P%03d", seq_len(n)),
      SOFA = sofa, Death_label = grp, x1 = x1, x2 = x2, f1 = f1,
      stringsAsFactors = FALSE
    ),
    noise,
    data.frame(Group = grp, stringsAsFactors = FALSE)
  )
  rownames(d) <- paste0("pat_", d$patient_id)
  idx <- seq_len(n)
  tr <- idx[vapply(idx, function(i) stats::runif(1) < 0.7, logical(1))]
  if (length(unique(d$Group[tr])) < 2L) tr <- idx[seq_len(70L)]
  te <- setdiff(idx, tr)
  cfg <- list(
    project = list(
      study_type = "prognosis", database = "MIMIC_IV",
      analysis_group = "Non-survivor", reference_group = "Survivor",
      output_dir = tempdir()
    ),
    data = list(id_column = "patient_id", outcome_column = "Death_label"),
    splitting = list(seed = 42L, train_ratio = 0.7),
    train_validation = list(mode = "split"),
    feature_selection = list(
      enable = TRUE, restrict_to_train = TRUE,
      target_n_features_min = 2L, target_n_features_max = 4L
    ),
    feature_selection_boruta = list(
      enable = TRUE, seed = 11L, boruta_max_runs = 25L, pause_enable = FALSE
    ),
    ml_models = list(cv_folds = 2L, methods = ml_frozen_default_methods()),
    ml_dt = list(pause_enable = FALSE, cv_folds = 2L),
    ml_rf = list(pause_enable = FALSE, cv_folds = 2L),
    ml_xgboost = list(pause_enable = FALSE, cv_folds = 2L),
    ml_lightgbm = list(pause_enable = FALSE, cv_folds = 2L),
    ml_logistic = list(pause_enable = FALSE, cv_folds = 2L),
    ml_stratified_ctx = list(patient_slots = character(0)),
    ml_frozen_bundle = list(sofa_breaks = 10L, never_features = "x10")
  )
  list(
    config = cfg,
    data = list(imputed = d, train = d[tr, , drop = FALSE],
                test = d[te, , drop = FALSE]),
    results = list(Model2Factors = c("SOFA", "x1", "x2", paste0("x", 3:13), "f1")),
    log = list(), models = list()
  )
}

tmp <- tempfile("frozen_bundle_")
dir.create(tmp, recursive = TRUE)
ctx <- make_fixture_ctx()
assets <- file.path(tmp, "model_assets")
methods <- ml_frozen_default_methods()
stopifnot(identical(
  sort(methods), sort(c("logistic", "dt", "rf", "xgboost", "lightgbm"))
))

bundle <- ml_fit_stratum_bundle(ctx, "sofa_0_10", methods,
                                assets_root = assets, quiet = TRUE)
stopifnot(identical(bundle$stratum$key, "sofa_0_10"))
stopifnot(identical(bundle$stratum$label, "SOFA 0–10"))
stopifnot(identical(as.numeric(bundle$stratum$upper), 10))
stopifnot(identical(bundle$stratum$operator, "range"))
stopifnot(all(methods %in% names(bundle$models)))
stopifnot(length(bundle$features) >= 2L)

# C1: the stratification key must never enter its own stratum's model, even
# when it is in Model2Factors and even if Boruta would pick it.
stopifnot("SOFA" %in% ctx$results$Model2Factors)
stopifnot(!"SOFA" %in% bundle$features)
# C1: bundle$never_features applies on the MAIN path (Model2Factors non-empty).
stopifnot("x10" %in% names(ctx$data$imputed))
stopifnot(!"x10" %in% bundle$features)
# the saved feature_manifest of a stratified bundle must not carry the key
dir_pre <- ml_save_frozen_bundle(bundle, file.path(assets, "sofa_0_10"))
fm_pre <- readRDS(file.path(dir_pre, "feature_manifest.rds"))
stopifnot(!"SOFA" %in% fm_pre$features, !"x10" %in% fm_pre$features)
stopifnot(is.character(fm_pre$stratum$variable),
          identical(fm_pre$stratum$variable, "SOFA"))

# C1: overall is not stratified -> SOFA stays an ordinary predictor; a
# never_features column stays excluded on this main path too.
ctx_overall <- ctx
ctx_overall$config$feature_selection$enable <- FALSE
ov <- ml_fit_stratum_bundle(ctx_overall, "overall", "logistic",
                            assets_root = assets, quiet = TRUE)
stopifnot(identical(ov$stratum$key, "overall"))
stopifnot("SOFA" %in% ov$features)
stopifnot(!"x10" %in% ov$features)
# stratified main path (no Boruta): SOFA excluded, ordinary columns kept
ov2 <- ml_fit_stratum_bundle(ctx_overall, "sofa_11plus", "logistic",
                             assets_root = assets, quiet = TRUE)
stopifnot(!"SOFA" %in% ov2$features)
stopifnot("x12" %in% ov2$features)
dir_ov <- ml_save_frozen_bundle(ov, file.path(assets, "overall"))
man_ov <- jsonlite::fromJSON(file.path(dir_ov, "manifest.json"),
                             simplifyVector = FALSE)
stopifnot("SOFA" %in% unlist(man_ov$features))

# C2: enabling Boruta without restrict_to_train would resample inside the
# stratum (leakage) -> must hard fail instead of silently splitting.
ctx_bad <- ctx
ctx_bad$config$feature_selection$restrict_to_train <- FALSE
c2 <- tryCatch(ml_fit_stratum_bundle(ctx_bad, "sofa_0_10", "logistic",
                                     assets_root = assets, quiet = TRUE),
               error = identity)
stopifnot(inherits(c2, "error"))
stopifnot(grepl("restrict_to_train|重新抽样|resampl",
                conditionMessage(c2), ignore.case = TRUE))

# I2: an undeclared database identity must be refused (fail-closed).
ctx_noid <- ctx
ctx_noid$config$project$database <- NULL
i2 <- tryCatch(ml_fit_stratum_bundle(ctx_noid, "sofa_0_10", "logistic",
                                     assets_root = assets, quiet = TRUE),
               error = identity)
stopifnot(inherits(i2, "error"))
stopifnot(grepl("database|库身份|identity", conditionMessage(i2),
                ignore.case = TRUE))
stopifnot(isFALSE(.ml_frozen_is_primary_database(NULL)))

# every stratum keeps its own feature set and its own recipe
for (m in methods) {
  b <- bundle$models[[m]]
  if (is.null(b$model)) stop("missing fitted model: ", m)
  if (!identical(b$features, bundle$features)) stop("feature order drift: ", m)
  if (is.null(b$recipe) || is.null(b$baked_columns) ||
      !length(b$baked_columns)) stop("missing recipe for ", m)
  if (!is.finite(b$youden_train)) stop("missing Youden train threshold: ", m)
  if (is.null(b$factor_levels) || !length(b$factor_levels)) {
    stop("missing training factor levels: ", m)
  }
}
stopifnot(is.list(bundle$models$rf$factor_levels))

# bundle keeps the original train/internal split untouched
stopifnot(bundle$counts$n_train > 0L, bundle$counts$n_internal > 0L)
stopifnot(identical(
  sort(unique(c(bundle$train_ids, bundle$internal_ids))),
  sort(ctx$data$train$patient_id[ctx$data$train$SOFA <= 10] |>
         append(ctx$data$test$patient_id[ctx$data$test$SOFA <= 10]))
))

# train/internal performance long table (Table S11 rows) exists for 5 models
perf <- bundle$performance$train_internal
stopifnot(is.data.frame(perf), nrow(perf) > 0L)
stopifnot(all(methods %in% unique(as.character(perf$model))))
stopifnot(all(c("train", "test") %in% unique(as.character(perf$dataset))))

dir <- ml_save_frozen_bundle(bundle, file.path(assets, "sofa_0_10"))
stopifnot(dir.exists(dir))
need_files <- c("feature_manifest.rds", "manifest.json",
                paste0("model_", methods, ".rds"))
stopifnot(all(need_files %in% list.files(dir)))
stopifnot(!any(grepl("^evalresult_", list.files(dir))))

manifest <- jsonlite::fromJSON(file.path(dir, "manifest.json"),
                              simplifyVector = FALSE)
stopifnot(identical(manifest$stratum$key, "sofa_0_10"))
stopifnot(identical(manifest$stratum$label, "SOFA 0–10"))
stopifnot(identical(as.numeric(manifest$stratum$upper), 10))
stopifnot(identical(as.character(manifest$stratum$variable), "SOFA"))
stopifnot(identical(unlist(manifest$features), bundle$features))
stopifnot(identical(as.character(manifest$outcome$analysis), "Non-survivor"))
stopifnot(identical(as.character(manifest$outcome$reference), "Survivor"))
stopifnot(is.list(manifest$factor_levels),
          identical(unlist(manifest$factor_levels$f1), c("No", "Yes")))
stopifnot(all(methods %in% names(manifest$models)))
for (m in methods) {
  mm <- manifest$models[[m]]
  stopifnot(identical(unlist(mm$features), bundle$features))
  stopifnot(identical(unlist(mm$baked_columns),
                      bundle$models[[m]]$baked_columns))
  stopifnot(is.finite(as.numeric(mm$youden_train)))
  stopifnot(nzchar(as.character(mm$model_checksum)))
}
stopifnot(nzchar(as.character(manifest$r_version)))
stopifnot(all(c("parsnip", "recipes", "workflows", "yardstick") %in%
                names(manifest$package_versions)))

loaded <- ml_load_frozen_bundle(dir)
stopifnot(identical(loaded$stratum$key, "sofa_0_10"))
stopifnot(identical(loaded$features, bundle$features))
stopifnot(identical(loaded$outcome$analysis, "Non-survivor"))
stopifnot(identical(loaded$outcome$reference, "Survivor"))
stopifnot(identical(loaded$factor_levels$f1, levels(ctx$data$train$f1)))
for (m in methods) {
  stopifnot(identical(loaded$models[[m]]$baked_columns,
                      bundle$models[[m]]$baked_columns))
  stopifnot(isTRUE(all.equal(loaded$models[[m]]$youden_train,
                             bundle$models[[m]]$youden_train)))
  stopifnot(identical(loaded$models[[m]]$scale_type,
                      bundle$models[[m]]$scale_type))
  stopifnot(!is.null(loaded$models[[m]]$model))
}

# round-trip predictions must be element-wise identical
inner <- ctx$data$train[ctx$data$train$SOFA <= 10, , drop = FALSE]
p_ref <- ml_predict_external_bundle(bundle, inner, stratum = "sofa_0_10")
p_new <- ml_predict_external_bundle(loaded, inner, stratum = "sofa_0_10")
stopifnot(is.data.frame(p_ref$predictions), nrow(p_ref$predictions) == nrow(inner))
stopifnot(all(methods %in% names(p_ref$predictions)))
for (m in methods) {
  stopifnot(isTRUE(all.equal(p_ref$predictions[[m]], p_new$predictions[[m]])))
}
# and the saved model_rds alone must reproduce the same probabilities
for (m in methods) {
  solo <- readRDS(file.path(dir, paste0("model_", m, ".rds")))
  obj <- solo$model
  pr <- as.data.frame(stats::predict(obj, new_data = p_new$prepared[[m]]$baked,
                                     type = "prob"))
  stopifnot(isTRUE(all.equal(ml_dual_dev_ext_prob_ana(pr, "Non-survivor"),
                             p_ref$predictions[[m]], tolerance = 1e-12)))
}

# tampered checksums must be refused
json_path <- file.path(dir, "manifest.json")
tampered <- manifest
tampered$models$logistic$model_checksum <- paste0(
  substr(tampered$models$logistic$model_checksum, 1L, 30L), "ab"
)
writeLines(jsonlite::toJSON(tampered, auto_unbox = TRUE, pretty = TRUE), json_path)
bad <- tryCatch({ ml_load_frozen_bundle(dir); NULL }, error = identity)
stopifnot(inherits(bad, "error"))
stopifnot(grepl("checksum|integrity", conditionMessage(bad), ignore.case = TRUE))

# tampering the payload (not the manifest) must also be caught
good_json <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE)
writeLines(good_json, json_path)
saveRDS(NULL, file.path(dir, "model_dt.rds"))
bad2 <- tryCatch({ ml_load_frozen_bundle(dir); NULL }, error = identity)
stopifnot(inherits(bad2, "error"))
stopifnot(grepl("checksum|integrity", conditionMessage(bad2), ignore.case = TRUE))

unlink(tmp, recursive = TRUE)
cat("test_ml_frozen_model_bundle: OK\n")
