#!/usr/bin/env Rscript
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/prognosis_reference_assoc.R"))
source(file.path(root, "R/prognosis_landmark_ph.R"))

expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(err, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(err), ignore.case = TRUE))
  }
  invisible(err)
}

# Engine-shape authority payload (pipeline_save_checkpoint): list(ctx, config,
# pipeline, step, block, step_index, saved_at, pub_counters) with NO
# split_role; identity lives in ctx$config$project$database.
make_authority <- function(train, split_role = NULL, database = "MIMIC_IV") {
  root <- tempfile("authority_ph_")
  path <- file.path(
    root, "checkpoints", "by_index", "SOSM_WPR", "MIMIC_IV",
    "step07_train_validation.rds"
  )
  dir.create(dirname(path), recursive = TRUE)
  payload <- list(
    ctx = list(
      config = list(
        project = list(
          database = database, study_type = "prognosis",
          analysis_group = "Non-survivor", reference_group = "Survivor"
        ),
        dual_db = list(current_db = "nhanes")
      ),
      data = list(train = train)
    ),
    config = NULL, pipeline = NULL,
    step = "step07_train_validation", block = "train_validation",
    step_index = 7L, saved_at = format(Sys.time()), pub_counters = NULL
  )
  if (!is.null(split_role)) payload$split_role <- split_role
  saveRDS(payload, path)
  path
}

make_ctx <- function(train, authority_path, db = "mimic") {
  list(
    config = list(
      project = list(
        current_db = db, study_type = "prognosis",
        analysis_group = "Non-survivor", reference_group = "Survivor"
      ),
      train_validation = list(mode = if (db == "mimic") "split" else "external_all"),
      data = list(outcome_column = "fustatus")
    ),
    data = list(train = train),
    results = list(authority_checkpoint_path = authority_path)
  )
}

# Piecewise hazards create genuine non-PH exposure effects in both SOFA layers.
simulate_layer <- function(n, layer, switch_day, seed) {
  set.seed(seed)
  x <- stats::rbinom(n, 1, 0.5)
  early <- stats::rexp(n, 0.035 * exp(1.6 * x))
  late <- stats::rexp(n, 0.035 * exp(-1.6 * x))
  event_time <- ifelse(early <= switch_day, early, switch_day + late)
  censor <- stats::runif(n, 12, 28)
  data.frame(
    id = paste0(layer, "_", seq_len(n)),
    SOFA_Group = layer,
    futime = pmin(event_time, censor),
    fustatus = as.integer(event_time <= censor),
    SOSM = x,
    Age = stats::rnorm(n, 65, 9),
    Gender = factor(sample(c("Female", "Male"), n, replace = TRUE))
  )
}

development <- rbind(
  simulate_layer(900, "SOFA <=10", 6, 11),
  simulate_layer(900, "SOFA >=11", 10, 19),
  data.frame(
    id = paste0("sparse_", 1:6),
    SOFA_Group = "SOFA sparse",
    futime = 1:6,
    fustatus = 0L,
    SOSM = rep(c(0, 1), 3),
    Age = 60:65,
    Gender = factor(rep(c("Female", "Male"), 3))
  )
)
authority <- make_authority(development)
ctx <- make_ctx(development, authority)
prov <- reference_trusted_development(development, ctx = ctx)
scan_input <- list(
  data = development,
  time = "futime",
  event = "fustatus",
  exposure = "SOSM",
  stratum = "SOFA_Group",
  covariates = c("Age", "Gender"),
  outcome_cfg = ctx$config,
  provenance = prov,
  max_day = 28
)

# Missing/forged/external provenance cannot initiate PH selection.
missing_source <- scan_input
missing_source$provenance <- NULL
expect_error(reference_ph_landmark_lock(missing_source), "provenance")
outside <- make_ctx(development, tempfile("not_authority_"), db = "mimic")
expect_error(reference_trusted_development(development, ctx = outside), "checkpoint|path")
forged <- scan_input
forged$provenance <- structure(
  list(checkpoint_path = authority, checkpoint_md5 = "fake", data_hash = "fake"),
  class = "reference_development_provenance"
)
expect_error(
  reference_ph_landmark_lock(forged), "checkpoint|MD5|hash|provenance"
)

# The lock itself performs coxph + cox.zph for Overall and both SOFA layers.
locked <- reference_ph_landmark_lock(scan_input, alpha = 0.05)
stopifnot(identical(locked$source, "MIMIC development/train"))
stopifnot(identical(
  sort(locked$scan$stratum),
  sort(c("Overall", "SOFA <=10", "SOFA >=11", "SOFA sparse"))
))
stopifnot(all(c("global_p", "exposure_p", "violation_p") %in% names(locked$scan)))
estimable_scan <- locked$scan$status == "estimable"
stopifnot(all(
  locked$scan$violation_p[estimable_scan] ==
    locked$scan$exposure_p[estimable_scan]
))
stopifnot(
  locked$scan$status[locked$scan$stratum == "SOFA sparse"] == "not_estimable"
)
violating <- locked$scan[
  locked$scan$status == "estimable" &
    is.finite(locked$scan$violation_p) &
    locked$scan$violation_p < 0.05, ,
  drop = FALSE
]
expected_selected <- violating$stratum[[which.min(violating$violation_p)]]
stopifnot(identical(locked$strata, expected_selected))
stopifnot(!anyDuplicated(locked$strata))
stopifnot(all(is.finite(locked$landmark_times)))
stopifnot(all(locked$landmark_times > 0 & locked$landmark_times < 28))
stopifnot(all(
  locked$scan$landmark_method[estimable_scan] %in%
    c("stable_zero_crossing", "minimum_absolute_beta")
))
stopifnot(all(
  locked$scan$approximate[estimable_scan] ==
    (locked$scan$landmark_method[estimable_scan] == "minimum_absolute_beta")
))
stopifnot(is.list(locked$beta_curves), length(locked$beta_curves) == 4L)
z_overall <- locked$fits$Overall$zph
smooth_overall <- stats::smooth.spline(
  z_overall$x, z_overall$y[, "SOSM"]
)
expected_beta <- stats::predict(
  smooth_overall, locked$beta_curves$Overall$day
)$y
stopifnot(isTRUE(all.equal(
  locked$beta_curves$Overall$beta, expected_beta, tolerance = 1e-10
)))

# Stable crossing requires two same-sign points on each side and is deterministic.
known_zph <- list(
  x = 1:10,
  y = cbind(SOSM = c(-2, -1.5, -1, -0.5, -0.2, 0.2, 0.5, 1, 1.5, 2))
)
known <- .reference_beta_landmark(
  known_zph, "SOSM", max_day = 12, tolerance = 0.05, stability_points = 2L
)
stopifnot(known$day == 5, known$method == "stable_zero_crossing")
stopifnot(isFALSE(known$approximate))
unstable_zph <- list(
  x = 1:10,
  y = cbind(SOSM = c(-1, -0.7, 0.1, -0.1, 0.1, -0.1, 0.2, 0.5, 0.8, 1))
)
unstable <- .reference_beta_landmark(
  unstable_zph, "SOSM", max_day = 12, tolerance = 0.15,
  stability_points = 2L
)
stopifnot(unstable$method == "minimum_absolute_beta")
stopifnot(isTRUE(unstable$approximate))

# Serialization must not depend on process memory; apply revalidates checkpoint.
saved_lock <- tempfile(fileext = ".rds")
saveRDS(locked, saved_lock)
# Validation re-reads the authority checkpoint from disk (no process-memory
# registry exists), so a reload behaves like a fresh session.
locked <- readRDS(saved_lock)

# Build exact boundary fixtures from a selected layer/time; repeated observations
# in the same stratum are valid and no external PH columns can change the lock.
specific <- intersect(locked$strata, c("SOFA <=10", "SOFA >=11"))
layer <- if (length(specific)) specific[[1L]] else "SOFA <=10"
L <- if (layer %in% names(locked$landmark_times)) {
  unname(locked$landmark_times[[layer]])
} else {
  unname(locked$landmark_times[["Overall"]])
}
external <- data.frame(
  id = 1:5,
  SOFA_Group = rep(layer, 5),
  futime = as.character(c(L - 1, L, L, L + 3, L + 4)),
  fustatus = c(1L, 1L, 0L, 1L, 0L),
  ph_p = c(0.9, 0.9, 0.9, 0.001, 0.001),
  candidate_landmark = 2,
  stringsAsFactors = FALSE
)
applied <- reference_apply_landmark(external, locked)
stopifnot(identical(attr(applied, "locked_source"), "MIMIC development/train"))
stopifnot(all(applied$landmark_time == L))

p1 <- applied[applied$id == 1, ]
p2 <- applied[applied$id == 2, ]
p3 <- applied[applied$id == 3, ]
p4 <- applied[applied$id == 4, ]
p5 <- applied[applied$id == 5, ]
stopifnot(nrow(p1) == 1L, p1$segment == "before", p1$event == 1L)
stopifnot(nrow(p2) == 1L, p2$stop == L, p2$event == 1L)
stopifnot(nrow(p3) == 1L, p3$stop == L, p3$event == 0L) # censored at landmark
stopifnot(nrow(p4) == 2L, identical(p4$segment, c("before", "after")))
stopifnot(p4$start[2] == L, p4$stop[2] == L + 3, p4$event[2] == 1L)
stopifnot(nrow(p5) == 2L, p5$event[2] == 0L)

# Character/factor/numeric event encodings have identical piecewise events.
event_versions <- list(
  numeric = external$fustatus,
  character = ifelse(external$fustatus == 1, "Non-survivor", "Survivor"),
  factor = factor(ifelse(external$fustatus == 1, "Non-survivor", "Survivor"))
)
piece_events <- lapply(event_versions, function(y) {
  d <- external
  d$fustatus <- y
  reference_apply_landmark(d, locked)$event
})
stopifnot(identical(piece_events$numeric, piece_events$character))
stopifnot(identical(piece_events$numeric, piece_events$factor))
unknown_event <- external
unknown_event$fustatus <- ifelse(external$fustatus == 1, "Dead", "Alive")
expect_error(
  reference_apply_landmark(unknown_event, locked),
  "unknown|label|single"
)

# Safe numeric conversion uses factor labels, and invalid survival values fail.
factor_time <- external
factor_time$futime <- factor(external$futime)
stopifnot(identical(
  reference_apply_landmark(factor_time, locked)$stop,
  applied$stop
))
bad_na <- external
bad_na$futime[1] <- NA
expect_error(reference_apply_landmark(bad_na, locked), "missing|NA")
bad_zero <- external
bad_zero$futime[1] <- "0"
expect_error(reference_apply_landmark(bad_zero, locked), "positive|> 0")
tampered <- locked
tampered$landmark_times[[1L]] <- NA_real_
expect_error(reference_apply_landmark(external, tampered), "tamper|trusted")
duplicated <- locked
duplicated$strata <- c(duplicated$strata, duplicated$strata[[1L]])
expect_error(reference_apply_landmark(external, duplicated), "tamper|duplicate|trusted")

# If every layer is non-estimable, scanning fails only after auditing all layers.
all_sparse <- development[development$SOFA_Group == "SOFA sparse", ]
all_sparse_authority <- make_authority(all_sparse)
all_sparse_ctx <- make_ctx(all_sparse, all_sparse_authority)
all_sparse_input <- scan_input
all_sparse_input$data <- all_sparse
all_sparse_input$provenance <- reference_trusted_development(
  all_sparse, ctx = all_sparse_ctx
)
expect_error(
  reference_ph_landmark_lock(all_sparse_input),
  "no estimable|not estimable"
)

# Checkpoint mutation invalidates a deserialized landmark lock.
saveRDS(
  list(split_role = "internal", ctx = list(data = list(train = development))),
  authority
)
expect_error(
  reference_apply_landmark(external, locked),
  "checkpoint|MD5|split"
)

cat("test_prognosis_landmark_ph: OK\n")
