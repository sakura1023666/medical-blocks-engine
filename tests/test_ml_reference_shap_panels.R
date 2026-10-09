#!/usr/bin/env Rscript
# Task 6 TDD tests: reference-paper SHAP/Boruta panel assembly
# (Figure 7, Figure 8, S2-S5). Fixture-driven counts + single-PDF outputs.
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
suppressWarnings(suppressMessages({
  library(ggplot2)
  source(file.path(root, "R/utils.R"), local = FALSE)
  source(file.path(root, "R/ml_stratified_ctx.R"), local = FALSE)
  source(file.path(root, "R/ml_dual_dev_ext.R"), local = FALSE)
  source(file.path(root, "R/ml_frozen_model_bundle.R"), local = FALSE)
  source(file.path(root, "R/ml_external_frozen_shap.R"), local = FALSE)
}))

expect_true <- function(x, msg) {
  if (!isTRUE(x)) stop("expected TRUE: ", msg, call. = FALSE)
  invisible(TRUE)
}
expect_identical <- function(a, b) {
  stopifnot(identical(a, b))
  invisible(TRUE)
}

out_dir <- tempfile("shap_panels_")
dir.create(out_dir, recursive = TRUE)
pdf_ok <- function(path) {
  expect_true(file.exists(path), paste("pdf exists:", basename(path)))
  expect_true(file.info(path)$size > 1000, paste("pdf non-empty:", basename(path)))
}

# ---------------------------------------------------------------------------
# fake SHAP objects (real shapviz, deterministic)
# ---------------------------------------------------------------------------
set.seed(42L)
feats <- c("Age", "MAP", "Creatinine", "Gender_Male", "Lactate")
make_shp <- function(n = 60L, p = 5L, sd = 0.4, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  X <- as.data.frame(stats::setNames(
    lapply(seq_len(p), function(j) rnorm(n, 50 + 10 * j, 10)), feats[seq_len(p)]
  ))
  S <- matrix(rnorm(n * p, 0, sd), nrow = n, ncol = p,
              dimnames = list(NULL, feats[seq_len(p)]))
  shapviz::shapviz(S, X = X)
}

# fake Boruta importance history (features + shadow columns)
make_boruta <- function(seed = 1L, n_feat = 6L, n_shadow = 3L, n_row = 40L) {
  set.seed(seed)
  cn <- c(paste0("f", seq_len(n_feat)),
          paste0("shadow_attribute_", seq_len(n_shadow)))
  m <- matrix(rnorm(n_row * length(cn)), nrow = n_row, ncol = length(cn))
  colnames(m) <- cn
  # true features carry signal above all shadows
  max_shadow <- max(apply(m, 2, median)[paste0("shadow_attribute_", seq_len(n_shadow))])
  m[, paste0("f", 1:2)] <- m[, paste0("f", 1:2)] + max_shadow + 2
  m[, paste0("f", 3)] <- m[, paste0("f", 3)] - 1
  list(
    imp = m,
    selected = c("f1", "f2"),
    shadow_prefix = "shadow_attribute_"
  )
}

stopifnot(exists("ml_ref_boruta_panels", mode = "function"))
stopifnot(exists("ml_ref_boruta_run", mode = "function"))

# real Boruta fit helper (small): MIMIC-only guard + ImpHistory shape
if (requireNamespace("Boruta", quietly = TRUE)) {
  set.seed(9L)
  nn <- 80L
  y <- factor(sample(c("Survivor", "Non-survivor"), nn, TRUE),
              levels = c("Survivor", "Non-survivor"))
  dd <- data.frame(
    Group = y,
    a = as.numeric(y == "Non-survivor") + rnorm(nn, 0, 0.6),
    b = rnorm(nn),
    C = factor(sample(c("No", "Yes"), nn, TRUE))
  )
  bo <- ml_ref_boruta_run(dd, max_runs = 25L, seed = 3L)
  expect_true(inherits(bo, "Boruta"), "Boruta object returned")
  expect_true(any(grepl("^shadow", colnames(bo$ImpHistory))),
              "ImpHistory carries shadow columns")
  bp <- ml_ref_boruta_panels(list(`SOFA <=10` = bo))
  expect_true(all(bp$plot_df$state %in%
                    c("Confirmed", "Rejected", "Shadow")),
            "real Boruta maps to state labels")
  err_db <- tryCatch(ml_ref_boruta_run(dd, database = "eICU"), error = identity)
  expect_true(inherits(err_db, "error"), "eICU must never re-run Boruta")
}
stopifnot(exists("ml_ref_fig7_boruta", mode = "function"))
stopifnot(exists("ml_ref_s2_boruta", mode = "function"))
stopifnot(exists("ml_ref_fig8_grid", mode = "function"))
stopifnot(exists("ml_ref_s3_roc", mode = "function"))
stopifnot(exists("ml_ref_s4_shap", mode = "function"))
stopifnot(exists("ml_ref_s5_waterfalls", mode = "function"))

# ---------------------------------------------------------------------------
# Boruta Z-score panels: 2 strata -> Figure 7; 1 overall -> S2
# ---------------------------------------------------------------------------
b_le <- make_boruta(1L); b_ge <- make_boruta(2L); b_ov <- make_boruta(3L)
boruta_in <- list(
  "SOFA <=10" = b_le,
  "SOFA >=11" = b_ge
)
f7 <- ml_ref_fig7_boruta(boruta_in,
                         out_pdf = file.path(out_dir, "Figure 7. strata Boruta.pdf"))
expect_identical(nrow(f7$panels), 2L)
expect_identical(as.character(f7$panels$panel), c("SOFA <=10", "SOFA >=11"))
expect_true(all(f7$panels$n_selected == 2L), "selected counts flow through")
expect_true(all(f7$panels$n_shadow == 3L), "shadow columns counted separately")
pdf_ok(f7$path)

f7z <- ml_ref_boruta_panels(boruta_in)
expect_true(is.data.frame(f7z$plot_df) && nrow(f7z$plot_df) > 0L, "z-score df")
expect_true("z" %in% names(f7z$plot_df), "z-score column")
expect_true(any(f7z$plot_df$state == "Shadow") && any(f7z$plot_df$state == "Confirmed"),
            "states labelled vs shadow distribution")

s2 <- ml_ref_s2_boruta(b_ov, out_pdf = file.path(out_dir, "Figure S2. overall Boruta.pdf"))
expect_identical(nrow(s2$panels), 1L)
pdf_ok(s2$path)

# ---------------------------------------------------------------------------
# Figure 8: database x SOFA stratum cells, each ROC + beeswarm + importance
# ---------------------------------------------------------------------------
mk_roc <- function(n = 120L, sep = 1.1, seed = 11L) {
  set.seed(seed)
  truth <- rep(c(0L, 1L), each = n / 2L)
  prob <- plogis(rnorm(n, ifelse(truth == 1L, sep, -sep), 1))
  list(prob = prob, truth = truth)
}
cells <- list()
k <- 0L
for (db in c("MIMIC-IV", "eICU")) {
  for (sk in c("SOFA <=10", "SOFA >=11")) {
    k <- k + 1L
    r <- mk_roc(seed = 11L + k)
    cells[[k]] <- list(
      database = db, stratum = sk, tag = "logistic",
      roc = ml_ref_roc_rows(r$prob, r$truth),
      shp = make_shp(sd = 0.4 + 0.1 * k)
    )
  }
}
f8 <- ml_ref_fig8_grid(cells, out_pdf = file.path(out_dir, "Figure 8. stratified ROC+SHAP.pdf"))
expect_identical(nrow(f8$panels), 4L)
expect_identical(as.character(f8$panels$database),
                 rep(c("MIMIC-IV", "eICU"), each = 2L))
expect_identical(as.character(f8$panels$stratum),
                 rep(c("SOFA <=10", "SOFA >=11"), 2L))
expect_true(all(is.finite(f8$panels$auc)), "per-cell AUC computed")
expect_true(all(f8$panels$auc > 0.5 & f8$panels$auc < 1), "AUC sane")
expect_true(all(as.integer(f8$panels$n_parts) == 3L), "three parts per cell")
# backward compatibility: single-model roc list still accepted
expect_true(exists(".ml_fig8_norm_roc", mode = "function"),
            "fig8 roc normalizer present")
expect_identical(nrow(f8$auc), 4L)
expect_true(all(f8$panels$n_models == 1L), "legacy cells report one model")
pdf_ok(f8$path)

# ---------------------------------------------------------------------------
# Figure 8 MULTI: every cell overlays the five-model ROCs (colour=model),
# SHAP sub-panels stay on the best tag; legend labels carry per-model AUC.
# ---------------------------------------------------------------------------
models5 <- c("logistic", "dt", "rf", "xgboost", "lightgbm")
cells_multi <- list()
k <- 0L
for (db in c("MIMIC-IV", "eICU")) {
  for (sk in c("SOFA <=10", "SOFA >=11")) {
    k <- k + 1L
    roc_list <- list()
    for (j in seq_along(models5)) {
      r <- mk_roc(seed = 41L + 5L * k + j, sep = 0.8 + 0.08 * j)
      roc_list[[j]] <- list(
        model = models5[j],
        roc = ml_ref_roc_rows(r$prob, r$truth, model = models5[j],
                              stratum = sk, database = db))
    }
    cells_multi[[k]] <- list(
      database = db, stratum = sk, tag = "xgboost",
      roc = roc_list, shp = make_shp(sd = 0.4 + 0.1 * k))
  }
}
f8m <- ml_ref_fig8_grid(cells_multi,
                        out_pdf = file.path(out_dir, "Figure 8. five-model ROC+SHAP.pdf"))
expect_identical(nrow(f8m$panels), 4L)
expect_true(all(as.integer(f8m$panels$n_models) == 5L),
            "each multi cell reports five models")
expect_identical(nrow(f8m$auc), 20L)
expect_true(all(f8m$auc$model %in% models5), "auc rows only known tags")
expect_identical(as.character(f8m$panels$tag), rep("xgboost", 4L))
expect_true(all(f8m$auc$best == (f8m$auc$model == "xgboost")),
            "best flag marks SHAP tag only")
# curve: every (cell, model) combination present => 5 model levels per cell
cu <- f8m$curve
expect_true(all(c("model", "database", "stratum") %in% names(cu)),
            "curve carries model + cell keys")
per_cell <- split(cu, list(cu$database, cu$stratum), drop = TRUE)
expect_identical(length(per_cell), 4L)
expect_true(all(vapply(per_cell, function(d)
  length(unique(as.character(d$model))) == 5L, logical(1))),
  "each cell curve holds five model levels")
# legend: 4 cells x 5 AUC-labelled entries
expect_true(is.list(f8m$legend_labels) && length(f8m$legend_labels) == 4L,
            "legend labels per cell")
expect_true(all(vapply(f8m$legend_labels, function(l)
  length(l) == 5L && all(grepl("^[a-z0-9]+: AUC [0-9.]+ \\(95%CI [0-9.]+-[0-9.]+\\)$", l)),
  logical(1))),
  "legend labels each model AUC (95%CI)")
pdf_ok(f8m$path)

# ---------------------------------------------------------------------------
# S3: overall five-model ROC, internal + external
# ---------------------------------------------------------------------------
models5 <- c("logistic", "dt", "rf", "xgboost", "lightgbm")
s3_cells <- list()
j <- 0L
for (m in models5) {
  for (ds in c("internal_validation", "external_validation")) {
    j <- j + 1L
    r <- mk_roc(seed = 21L + j, sep = 0.9 + 0.05 * j)
    s3_cells[[j]] <- list(
      model = m, dataset = ds,
      roc = ml_ref_roc_rows(r$prob, r$truth)
    )
  }
}
s3 <- ml_ref_s3_roc(s3_cells, out_pdf = file.path(out_dir, "Figure S3. overall ROC.pdf"))
expect_identical(nrow(s3$panels), 5L)
expect_identical(as.character(s3$panels$model), models5)
expect_true(all(c("internal_auc", "external_auc") %in% names(s3$panels)),
            "wide panels carry both datasets")
expect_true(all(is.finite(s3$panels$internal_auc)) &&
              all(is.finite(s3$panels$external_auc)), "both AUCs computed")
expect_identical(nrow(s3$auc), 10L)
expect_true(all(c("internal_validation", "external_validation") %in%
                  as.character(s3$auc$dataset)), "long auc both datasets")
pdf_ok(s3$path)

# ---------------------------------------------------------------------------
# S4: overall best frozen model SHAP, both databases
# ---------------------------------------------------------------------------
s4_in <- list(
  list(database = "MIMIC-IV", tag = "logistic", shp = make_shp(seed = 3L)),
  list(database = "eICU", tag = "logistic", shp = make_shp(seed = 4L))
)
s4 <- ml_ref_s4_shap(s4_in, out_pdf = file.path(out_dir, "Figure S4. overall SHAP.pdf"))
expect_identical(nrow(s4$panels), 2L)
expect_identical(as.character(s4$panels$database), c("MIMIC-IV", "eICU"))
expect_true(all(s4$panels$n_features == 5L), "feature count from shap matrix")
pdf_ok(s4$path)

# ---------------------------------------------------------------------------
# S5: individual waterfalls — 2 db x 2 strata x 2 outcome classes = 8
# ---------------------------------------------------------------------------
s5_items <- list()
idx <- 0L
for (db in c("MIMIC-IV", "eICU")) {
  for (sk in c("SOFA <=10", "SOFA >=11")) {
    for (oc in c("Survivor", "Non-survivor")) {
      idx <- idx + 1L
      s5_items[[idx]] <- list(
        database = db, stratum = sk, outcome_class = oc,
        row_id = 3L, prob = if (oc == "Survivor") 0.07 else 0.92,
        shp = make_shp(seed = 100L + idx)
      )
    }
  }
}
s5 <- ml_ref_s5_waterfalls(
  s5_items,
  out_pdf = file.path(out_dir, "Figure S5. individual SHAP.pdf")
)
expect_identical(nrow(s5$panels), 8L)
expect_true(all(s5$panels$outcome_class %in% c("Survivor", "Non-survivor")),
            "publication labels only")
expect_identical(nrow(unique(s5$panels[, c("database", "stratum", "outcome_class")])), 8L)
pdf_ok(s5$path)

# row_id beyond shp rows must fail loudly (no silent clamp)
bad_items <- s5_items[1:2]
bad_items[[1]]$row_id <- 9999L
err <- tryCatch(ml_ref_s5_waterfalls(bad_items), error = identity)
expect_true(inherits(err, "error"), "invalid waterfall row_id rejected")

cat("TEST_OK test_ml_reference_shap_panels\n")
