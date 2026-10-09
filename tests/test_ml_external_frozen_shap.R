#!/usr/bin/env Rscript
# Task 6 TDD tests: SHAP from FROZEN MIMIC assets (eICU never retrains),
# paired survivor/non-survivor case picking, best-tag resolution.
# RED first: R/ml_external_frozen_shap.R must not exist / functions missing.
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
suppressWarnings(suppressMessages({
  source(file.path(root, "R/utils.R"), local = FALSE)
  source(file.path(root, "R/ml_stratified_ctx.R"), local = FALSE)
  source(file.path(root, "R/ml_dual_dev_ext.R"), local = FALSE)
  source(file.path(root, "R/ml_frozen_model_bundle.R"), local = FALSE)
  source(file.path(root, "R/ml_external_frozen_shap.R"), local = FALSE)
}))

expect_identical <- function(a, b) {
  stopifnot(identical(a, b))
  invisible(TRUE)
}
expect_true <- function(x, msg) {
  if (!isTRUE(x)) stop("expected TRUE: ", msg, call. = FALSE)
  invisible(TRUE)
}
expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(err, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(err), ignore.case = TRUE))
  }
  invisible(err)
}

# ---------------------------------------------------------------------------
# fixture ctx (Task5 shape, Boruta OFF for speed; logistic-only methods)
# ---------------------------------------------------------------------------
set.seed(20260917L)

make_frame <- function(n, seed, sofa_shift = 0) {
  old <- set.seed(seed); on.exit(set.seed(old), add = TRUE)
  sofa <- sample(4:16, n, replace = TRUE)
  if (sofa_shift != 0) sofa <- pmin(20L, pmax(0L, sofa + sofa_shift))
  x1 <- round(rnorm(n, 60, 12), 2)
  x2 <- round(rnorm(n, 20, 5), 2)
  f1 <- factor(sample(c("No", "Yes"), n, replace = TRUE), levels = c("No", "Yes"))
  lp <- -1.8 + 0.05 * (x1 - 60) + 0.06 * (x2 - 20) + 0.4 * (sofa > 10) +
    ifelse(f1 == "Yes", 0.5, 0)
  grp <- factor(ifelse(stats::rbinom(n, 1, plogis(lp)) == 1L,
                       "Non-survivor", "Survivor"),
                levels = c("Survivor", "Non-survivor"))
  data.frame(
    patient_id = sprintf("E%04d", seq_len(n)),
    SOFA = sofa, Death_label = grp, x1 = x1, x2 = x2, f1 = f1,
    Group = grp, stringsAsFactors = FALSE
  )
}

make_fixture_ctx <- function(n = 120L, seed = 7L) {
  d <- make_frame(n, seed)
  idx <- seq_len(n)
  tr <- idx[vapply(idx, function(i) stats::runif(1) < 0.7, logical(1))]
  if (length(unique(d$Group[tr])) < 2L) tr <- idx[seq_len(90L)]
  te <- setdiff(idx, tr)
  cfg <- list(
    project = list(
      study_type = "prognosis", database = "MIMIC_IV",
      analysis_group = "Non-survivor", reference_group = "Survivor",
      output_dir = tempdir()
    ),
    data = list(id_column = "patient_id", outcome_column = "Death_label"),
    splitting = list(seed = 42L, train_ratio = 0.7),
    feature_selection = list(enable = FALSE),
    ml_models = list(cv_folds = 2L, methods = "logistic"),
    ml_logistic = list(pause_enable = FALSE, cv_folds = 2L),
    ml_stratified_ctx = list(patient_slots = character(0)),
    ml_frozen_bundle = list(sofa_breaks = 10L, never_features = character(0))
  )
  list(
    config = cfg,
    data = list(imputed = d, train = d[tr, , drop = FALSE],
                test = d[te, , drop = FALSE]),
    results = list(Model2Factors = c("SOFA", "x1", "x2", "f1")),
    log = list(), models = list()
  )
}

tmp <- tempfile("frozen_shap_")
dir.create(tmp, recursive = TRUE)
ctx <- make_fixture_ctx()
assets <- file.path(tmp, "model_assets")
bundle <- ml_fit_stratum_bundle(ctx, "sofa_0_10", "logistic",
                                assets_root = assets, quiet = TRUE)
adir <- ml_save_frozen_bundle(bundle, file.path(assets, "sofa_0_10"))
frozen <- ml_load_frozen_bundle(adir, expected_stratum = "sofa_0_10")
manifest <- jsonlite::fromJSON(file.path(adir, "manifest.json"),
                               simplifyVector = FALSE)

# external (eICU-like) frame, same stratum membership (SOFA <= 10)
ext_all <- make_frame(260L, seed = 99L)
ext <- ext_all[ext_all$SOFA <= 10, , drop = FALSE]
stopifnot(any(ext$Group == "Non-survivor"), any(ext$Group == "Survivor"))

# ---------------------------------------------------------------------------
# 1) ml_shap_from_frozen_bundle — frozen model identity + bake identity
# ---------------------------------------------------------------------------
stopifnot(exists("ml_shap_from_frozen_bundle", mode = "function"))
res <- ml_shap_from_frozen_bundle(frozen, ext, sample_n = 80L)
stopifnot(inherits(res$shp, "shapviz"))
expect_identical(res$tag, "logistic")
expect_identical(res$stratum, "sofa_0_10")

# KEY assertion: explained model checksum == manifest frozen checksum
# (eICU explanation uses the MIMIC frozen model, never a retrained one)
want <- manifest$models$logistic$model_checksum
expect_identical(res$model_checksum, as.character(want))
expect_identical(res$manifest_checksum, as.character(want))

# explained rows: n == sample_n (external frame is larger)
n_sh <- nrow(shapviz::get_shap_values(res$shp))
expect_true(n_sh == 80L, "sample_n caps explained rows")
expect_true(all(res$row_index >= 1L) && all(res$row_index <= nrow(ext)),
            "row_index within external frame")

# SHAP columns backmap 1:1 onto bundle features (baked dummy names -> feature)
stopifnot(exists("ml_shap_backmap_features", mode = "function"))
bm <- ml_shap_backmap_features(colnames(shapviz::get_shap_values(res$shp)),
                               frozen$features)
expect_true(all(bm$feature[!is.na(bm$feature)] %in% frozen$features),
            "every SHAP column maps to a bundle feature")
expect_true(all(frozen$features %in% unique(bm$feature)),
            "every bundle feature represented in SHAP matrix")
expect_identical(res$features, as.character(frozen$features))

# determinism: same call twice -> identical contributions
res2 <- ml_shap_from_frozen_bundle(frozen, ext, sample_n = 80L)
expect_identical(as.matrix(shapviz::get_shap_values(res$shp)),
                 as.matrix(shapviz::get_shap_values(res2$shp)))

# predictions consistent with Task5 frozen predict on the same rows
ext_pred <- ml_predict_external_bundle(frozen, ext, stratum = "sofa_0_10",
                                       database = "eICU")
expect_identical(as.integer(res$row_index), as.integer(res2$row_index))
expect_true(isTRUE(all.equal(as.numeric(ext_pred$predictions$logistic[res$row_index]),
                             as.numeric(res$pred_prob))),
            "explained-frame probabilities equal frozen predictions")

# errors: unknown tag / cross-stratum membership violation
expect_error(ml_shap_from_frozen_bundle(frozen, ext, tag = "nope"),
             "not in frozen bundle")
bad <- ext_all[ext_all$SOFA > 10, , drop = FALSE]
expect_error(ml_shap_from_frozen_bundle(frozen, bad, stratum = "sofa_0_10"),
             "stratum membership violation")
# A tampered in-memory model (silent refit/swap after load) must be rejected:
# the file md5 still matches the manifest, so only the in-memory-vs-asset model
# digest guard can catch it. This is the core anti-refit assertion.
tampered <- frozen
attr(tampered$models$logistic$model, "mdl_tampered") <- TRUE
expect_error(
  ml_shap_from_frozen_bundle(tampered, ext, tag = "logistic",
                             stratum = "sofa_0_10"),
  "identity check failed"
)
# overall bundle: stratum check skipped, tag defaults to best available
ov_ctx <- ctx
ov_bundle <- ml_fit_stratum_bundle(ov_ctx, "overall", "logistic",
                                   assets_root = assets, quiet = TRUE)
ov_dir <- ml_save_frozen_bundle(ov_bundle, file.path(assets, "overall"))
ov_frozen <- ml_load_frozen_bundle(ov_dir)
ov_res <- ml_shap_from_frozen_bundle(ov_frozen, ext_all, sample_n = 60L)
expect_identical(ov_res$stratum, "overall")
expect_true(nrow(shapviz::get_shap_values(ov_res$shp)) == 60L,
            "overall explained rows == sample_n")

# ---------------------------------------------------------------------------
# 2) ml_frozen_best_tag — validation (internal) optimum, never train-only
# ---------------------------------------------------------------------------
stopifnot(exists("ml_frozen_best_tag", mode = "function"))
perf <- data.frame(
  model = rep(c("logistic", "xgboost", "rf"), each = 2L),
  dataset = rep(c("train", "internal_validation"), 3L),
  .metric = "roc_auc",
  .estimate = c(0.99, 0.70, 0.80, 0.86, 0.95, 0.75),
  stringsAsFactors = FALSE
)
fake <- frozen
fake$performance$train_internal <- perf
fake$models$rf <- fake$models$logistic
fake$models$xgboost <- fake$models$logistic
expect_identical(ml_frozen_best_tag(fake), "xgboost")
# tie/near-tie within tolerance picks tree-preferred model deterministically
perf2 <- perf
perf2$.estimate[4] <- 0.8600001
fake2 <- fake; fake2$performance$train_internal <- perf2
expect_identical(ml_frozen_best_tag(fake2), "xgboost")
# no performance -> NULL (caller must pass explicit tag)
fake3 <- fake; fake3$performance$train_internal <- NULL
expect_true(is.null(ml_frozen_best_tag(fake3)), "no perf -> NULL")

# ---------------------------------------------------------------------------
# 3) ml_pick_paired_cases — one survivor + one non-survivor per db x stratum
# ---------------------------------------------------------------------------
stopifnot(exists("ml_pick_paired_cases", mode = "function"))
set.seed(5L)
mk_preds <- function(db) {
  do.call(rbind, lapply(c("sofa_0_10", "sofa_11plus"), function(sk) {
    nn <- 40L
    data.frame(
      database = db, stratum = sk,
      row_id = seq_len(nn),
      truth = rep(c(0L, 1L), each = nn / 2L),
      prob = c(runif(nn / 2, 0.01, 0.30), runif(nn / 2, 0.60, 0.99)),
      stringsAsFactors = FALSE
    )
  }))
}
preds <- rbind(mk_preds("MIMIC-IV"), mk_preds("eICU"))
picks <- ml_pick_paired_cases(preds)
expect_true(nrow(picks) == 8L, "2 db x 2 strata x 2 outcome classes")
expect_true(all(c("database", "stratum", "outcome_class", "row_id") %in%
                  names(picks)), "pick columns")
expect_true(all(picks$outcome_class %in% c("Survivor", "Non-survivor")),
            "publication outcome labels")

# every pick lands on a row of the SAME db+stratum with the SAME outcome
ok <- vapply(seq_len(nrow(picks)), function(i) {
  p <- picks[i, ]
  sub <- preds[preds$database == p$database & preds$stratum == p$stratum, ]
  r <- sub[sub$row_id == p$row_id, ]
  nrow(r) == 1L && (as.integer(r$truth) == as.integer(p$outcome_class == "Non-survivor"))
}, logical(1))
expect_true(all(ok), "row_ids belong to own db+stratum and own outcome class")

# within a group, survivor/non-survivor rows must be distinct real rows
grp_dup <- anyDuplicated(picks[, c("database", "stratum", "row_id")])
expect_true(grp_dup == 0L, "no duplicated row within a db+stratum group")

# stratum filter + no cross-stratum reuse
picks_le <- ml_pick_paired_cases(preds, stratum = "sofa_0_10")
expect_true(all(picks_le$stratum == "sofa_0_10"), "stratum filter respected")
expect_true(nrow(picks_le) == 4L, "2 db x 2 outcome under filter")

# confident-case rule: non-survivor pick = highest prob, survivor = lowest
chk <- function(db, sk) {
  sub <- preds[preds$database == db & preds$stratum == sk, ]
  p_ns <- picks[picks$database == db & picks$stratum == sk &
                  picks$outcome_class == "Non-survivor", "row_id"]
  p_s  <- picks[picks$database == db & picks$stratum == sk &
                  picks$outcome_class == "Survivor", "row_id"]
  ns_rows <- sub[sub$truth == 1L, ]
  s_rows <- sub[sub$truth == 0L, ]
  expect_identical(p_ns, ns_rows$row_id[which.max(ns_rows$prob)])
  expect_identical(p_s, s_rows$row_id[which.min(s_rows$prob)])
}
invisible(lapply(c("MIMIC-IV", "eICU"), function(db) chk(db, "sofa_0_10")))
invisible(lapply(c("MIMIC-IV", "eICU"), function(db) chk(db, "sofa_11plus")))

# a group missing one class must fail loudly (no silent cross-stratum borrow)
lonely <- preds[preds$stratum == "sofa_0_10", ]
lonely <- lonely[lonely$truth == 1L, ]
expect_error(ml_pick_paired_cases(lonely), "no rows with outcome")

cat("TEST_OK test_ml_external_frozen_shap\n")
