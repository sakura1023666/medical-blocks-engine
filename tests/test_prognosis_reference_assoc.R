#!/usr/bin/env Rscript
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/ml_assoc_covariate_rule.R"))
source(file.path(root, "R/prognosis_reference_assoc.R"))

expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(err, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(err), ignore.case = TRUE))
  }
  invisible(err)
}

# Engine-shape authority payload: pipeline_save_checkpoint() writes
# list(ctx, config, pipeline, step, block, step_index, saved_at, pub_counters)
# with NO split_role field. Database identity lives in
# ctx$config$project$database (verified against the real study checkpoint
# checkpoints/by_index/SOSM+WPR/MIMIC_IV/step07_train_validation.rds).
make_authority <- function(train, combo = "SOSM_WPR", split_role = NULL,
                           database = "MIMIC_IV") {
  root <- tempfile("authority_")
  path <- file.path(
    root, "checkpoints", "by_index", combo, "MIMIC_IV",
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
        dual_db = list(current_db = "nhanes") # slot label, not db identity
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

make_ctx <- function(train, authority_path, db = "mimic", mode = "split") {
  list(
    config = list(
      project = list(
        current_db = db, study_type = "prognosis",
        analysis_group = "Non-survivor", reference_group = "Survivor"
      ),
      train_validation = list(mode = mode),
      assoc_covariate = list(
        enable = TRUE, force_model1 = "Age", demo_uv_to_model1 = FALSE
      ),
      data = list(outcome_column = "fustatus"),
      survival = list(time_var = "futime", event_var = "fustatus")
    ),
    data = list(train = train),
    results = list(authority_checkpoint_path = authority_path)
  )
}

# type=7 upper-tertile cutpoint and strict ties: equality remains low.
dev_cut <- data.frame(A = c(1, 1, 2, 2, 3, 3, 4), B = c(7, 6, 5, 4, 3, 2, 1))
authority_cut <- make_authority(dev_cut, "CUT_TEST")
ctx_cut <- make_ctx(dev_cut, authority_cut)
prov_cut <- reference_trusted_development(dev_cut, ctx = ctx_cut)
lock_cut <- reference_lock_tertile_cutpoints(dev_cut, "A", "B", prov_cut)
expected_a <- unname(stats::quantile(dev_cut$A, 2 / 3, type = 7))
expected_b <- unname(stats::quantile(dev_cut$B, 2 / 3, type = 7))
stopifnot(identical(lock_cut$quantile_type, 7L))
stopifnot(identical(unname(lock_cut$cutpoints), c(expected_a, expected_b)))
grp <- reference_joint_tertile_groups(
  c(expected_a, expected_a + 1, expected_a, expected_a + 1),
  c(expected_b, expected_b, expected_b + 1, expected_b + 1),
  expected_a, expected_b
)
stopifnot(identical(
  as.character(grp), c("Group1", "Group2", "Group3", "Group4")
))

# Provenance re-reads the authority checkpoint from disk on every use.
expect_error(
  reference_lock_tertile_cutpoints(dev_cut, "A", "B"),
  "provenance"
)
expect_error(
  reference_trusted_development(
    dev_cut, ctx = make_ctx(dev_cut, tempfile("outside_checkpoint_"))
  ),
  "checkpoint|path"
)
expect_error(
  reference_trusted_development(dev_cut[1:5, ], ctx = ctx_cut), "hash|train"
)
fake <- structure(list(
  checkpoint_path = authority_cut,
  checkpoint_md5 = unname(tools::md5sum(authority_cut)),
  data_hash = "fake"
), class = "reference_development_provenance")
expect_error(
  reference_lock_tertile_cutpoints(dev_cut, "A", "B", fake),
  "checkpoint|MD5|hash|provenance"
)
tampered <- lock_cut
tampered$cutpoints[["a"]] <- -999
expect_error(reference_apply_joint_tertiles(dev_cut, tampered), "tamper|trusted")

# --- Trust-root attacks -------------------------------------------------------
# (1) Forged checkpoint under checkpoints/by_index/X/MIMIC_IV with no legitimate
# database identity anywhere in ctx$config must be rejected.
forged_root <- tempfile("forged_authority_")
forged_path <- file.path(
  forged_root, "checkpoints", "by_index", "X", "MIMIC_IV",
  "step07_train_validation.rds"
)
dir.create(dirname(forged_path), recursive = TRUE)
saveRDS(list(
  ctx = list(config = list(project = list(name = "whatever")),
             data = list(train = dev_cut)),
  step = "step07_train_validation", block = "train_validation"
), forged_path)
expect_error(
  reference_trusted_development(dev_cut, checkpoint_path = forged_path),
  "database|MIMIC|identity|authority"
)

# (2) A self-declared split_role="train" alone is not sufficient: payload must
# carry cross-validated engine identity and a real ctx$data$train.
lie_root <- tempfile("lying_authority_")
lie_path <- file.path(
  lie_root, "checkpoints", "by_index", "X", "MIMIC_IV", "step07_train.rds"
)
dir.create(dirname(lie_path), recursive = TRUE)
saveRDS(list(split_role = "train"), lie_path)
expect_error(
  reference_trusted_development(dev_cut, checkpoint_path = lie_path),
  "database|MIMIC|identity|train|authority"
)

# (3) Path may say MIMIC_IV but a payload declaring another database is refused.
mismatch <- make_authority(dev_cut, "MISMATCH", database = "eICU")
expect_error(
  reference_trusted_development(dev_cut, checkpoint_path = mismatch),
  "database|MIMIC|identity|mismatch|authority"
)

# (3b) A per-DB checkpoint DIRECTORY under MIMIC_IV resolves to the latest
# step file whose payload carries train + MIMIC identity (worker landing
# point: checkpoints/by_index/<combo>/MIMIC_IV/), and an explicit file path
# stays preferred.
dir_root <- tempfile("dir_authority_")
dir_path <- file.path(dir_root, "checkpoints", "by_index", "DIR_TEST", "MIMIC_IV")
dir.create(dir_path, recursive = TRUE)
saveRDS(list(
  ctx = list(config = list(project = list(database = "MIMIC_IV")),
             data = list(train = dev_cut)),
  step = "step05_index", block = "index", step_index = 5L
), file.path(dir_path, "step05_index.rds"))
saveRDS(list(
  ctx = list(config = list(project = list(database = "MIMIC_IV")),
             data = list(train = dev_cut)),
  step = "step07_train_validation", block = "train_validation", step_index = 7L
), file.path(dir_path, "step07_train_validation.rds"))
dir_prov <- reference_trusted_development(dev_cut, checkpoint_path = dir_path)
stopifnot(grepl(
  "step07_train_validation[.]rds$", dir_prov$checkpoint_path, perl = TRUE
))

# (4) Real engine checkpoint (read-only): the trusted bootstrap must succeed on
# the genuine pipeline_save_checkpoint payload shape and lock cutpoints.
real_ck <- Sys.getenv(
  "REFERENCE_REAL_MIMIC_CHECKPOINT",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/17_AKI_院内28天死亡预测预后_静/checkpoints/by_index/SOSM+WPR/MIMIC_IV/step07_train_validation.rds"
)
if (file.exists(real_ck) && file.access(real_ck, 4) == 0) {
  real_payload <- readRDS(real_ck)
  real_train <- real_payload$ctx$data$train
  stopifnot(is.data.frame(real_train), nrow(real_train) > 0)
  stopifnot(is.null(real_payload$split_role)) # engine payload has no split_role
  real_prov <- reference_trusted_development(real_train, checkpoint_path = real_ck)
  real_lock <- reference_lock_tertile_cutpoints(real_train, "SOSM", "WPR", real_prov)
  expected_real_a <- unname(stats::quantile(
    as.numeric(as.character(real_train$SOSM)), 2 / 3, type = 7
  ))
  stopifnot(isTRUE(all.equal(
    unname(real_lock$cutpoints[["a"]]), expected_real_a, tolerance = 0
  )))
  stopifnot(identical(
    normalizePath(real_prov$checkpoint_path, winslash = "/", mustWork = FALSE),
    normalizePath(real_ck, winslash = "/", mustWork = FALSE)
  ))
  cat("test_prognosis_reference_assoc: real MIMIC_IV checkpoint bootstrap OK\n")
} else {
  # Real file unavailable in this environment; case (1)-(3) fixtures above use
  # the exact same engine payload shape (ctx/config/project/database, no
  # split_role) as the real checkpoint verified by readRDS inspection.
  cat("test_prognosis_reference_assoc: real checkpoint unreadable; SKIPPED (4)\n")
}

set.seed(731)
n <- 600L
dat <- data.frame(
  futime = stats::rexp(n, rate = 0.04),
  fustatus = stats::rbinom(n, 1, 0.65),
  SOSM = stats::rnorm(n),
  WPR = stats::rnorm(n),
  SOSM_extra = stats::rnorm(n),
  SOFA = rep(c(8, 12), each = n / 2),
  SOFA_Group = rep(c("SOFA <=10", "SOFA >=11"), each = n / 2),
  Age = stats::rnorm(n, 65, 10),
  Gender = factor(rep(c("Female", "Male"), n / 2)),
  Creatinine = stats::rnorm(n),
  Albumin = stats::rnorm(n)
)
authority <- make_authority(dat)
ctx <- make_ctx(dat, authority)
ctx$results$tb1 <- c(
  "Gender", "Creatinine", "Albumin", "SOSM", "WPR", "SOFA", "SOFA_Group",
  "SOSM_extra"
)
ctx$results$feature_selection_final <- "Albumin"
prov <- reference_trusted_development(dat, ctx = ctx)

# Model2 excludes both exposures and all SOFA/stratum variables before resolver.
cox <- reference_fit_cox_suite(
  dat, "futime", "fustatus", c("SOSM", "WPR"), "SOFA_Group", ctx
)
stopifnot(identical(
  unique(cox$model), c("Unadjusted", "Model1 Age+Gender", "Model2")
))
m2 <- cox$covariates[cox$model == "Model2"][[1L]]
stopifnot(all(c("Age", "Gender", "Creatinine", "SOSM_extra") %in% m2))
stopifnot(!any(c("SOSM", "WPR", "SOFA", "SOFA_Group", "Albumin") %in% m2))

# Exact terms/assign matching must not collect a similarly prefixed covariate.
sosm_rows <- cox[cox$index == "SOSM", ]
stopifnot(all(sosm_rows$term == "SOSM"))
stopifnot(!any(grepl("SOSM_extra", sosm_rows$term, fixed = TRUE)))

# Exact matching also supports non-syntactic exposure names.
space_dat <- dat
space_dat[["SOSM value"]] <- space_dat$SOSM
space_fit <- reference_fit_cox_suite(
  space_dat, "futime", "fustatus", "SOSM value", "SOFA_Group", ctx
)
stopifnot(all(gsub("`", "", space_fit$term, fixed = TRUE) == "SOSM value"))

# Every event representation is converted through pipeline_outcome_as_01.
event_versions <- list(
  numeric = dat$fustatus,
  character = ifelse(dat$fustatus == 1, "Non-survivor", "Survivor"),
  factor = factor(ifelse(dat$fustatus == 1, "Non-survivor", "Survivor"))
)
event_counts <- vapply(event_versions, function(y) {
  d <- dat
  d$fustatus <- y
  fit <- reference_fit_cox_suite(
    d, "futime", "fustatus", "SOSM", "SOFA_Group", ctx
  )
  fit$events[[1L]]
}, numeric(1))
stopifnot(length(unique(event_counts)) == 1L)
bad_event <- dat
bad_event$fustatus <- ifelse(dat$fustatus == 1, "Dead", "Alive")
expect_error(
  reference_fit_cox_suite(
    bad_event, "futime", "fustatus", "SOSM", "SOFA_Group", ctx
  ),
  "unknown|label|single"
)

# RCS knots, grid range, and reference are frozen on MIMIC train.
rcs_lock <- reference_lock_grouped_rcs(
  dat, "SOSM", prov, spline_df = 3L
)
dat$Age[c(3, 310)] <- NA
dat$Creatinine[c(4, 311)] <- NA
dat$SparseFactor <- factor(ifelse(
  dat$SOFA_Group == "SOFA <=10",
  rep(c("A", "B"), length.out = nrow(dat)),
  "A"
))
rcs <- reference_grouped_rcs(
  dat, "futime", "fustatus", "SOSM", "SOFA_Group",
  covariates = c("Age", "Gender", "Creatinine", "SparseFactor"),
  locked_spec = rcs_lock, outcome_cfg = ctx$config, grid_n = 12L
)
stopifnot(all(rcs$summary$n_null == rcs$summary$n_linear))
stopifnot(all(rcs$summary$n_linear == rcs$summary$n_spline))
stopifnot(length(unique(rcs$curve$reference)) == 1L)
stopifnot(identical(unique(rcs$curve$reference), rcs_lock$reference_value))
ref_rows <- rcs$curve[rcs$curve$value == rcs_lock$reference_value, ]
stopifnot(nrow(ref_rows) == length(unique(dat$SOFA_Group)))
stopifnot(all(ref_rows$hr == 1), all(ref_rows$conf_low == 1), all(ref_rows$conf_high == 1))
stopifnot(all(is.finite(rcs$summary$p_overall)))
stopifnot(all(is.finite(rcs$summary$p_nonlinear)))
stopifnot("SparseFactor" %in% rcs$covariate_audit$dropped)
stopifnot(!"SparseFactor" %in% rcs$covariate_audit$kept)
stopifnot(!anyNA(rcs$curve[, c("hr", "conf_low", "conf_high")]))

# External data may apply but cannot create or mutate the reference lock.
external <- dat[1:200, ]
external$SOSM <- external$SOSM + 20
applied_external <- reference_grouped_rcs(
  external, "futime", "fustatus", "SOSM", "SOFA_Group",
  covariates = c("Age", "Gender", "Creatinine", "SparseFactor"),
  locked_spec = rcs_lock, outcome_cfg = ctx$config, grid_n = 8L
)
stopifnot(identical(unique(applied_external$curve$reference), rcs_lock$reference_value))
eicu_path <- sub("MIMIC_IV", "eICU", make_authority(external, "EXT_TEST"), fixed = TRUE)
dir.create(dirname(eicu_path), recursive = TRUE)
invisible(file.copy(authority, eicu_path, overwrite = TRUE))
expect_error(
  reference_lock_grouped_rcs(
    external, "SOSM",
    reference_trusted_development(external, ctx = make_ctx(external, eicu_path))
  ),
  "MIMIC_IV|checkpoint|path"
)

# Locks survive serialization/new-session state because apply revalidates disk.
saved_locks <- tempfile(fileext = ".rds")
saveRDS(list(tertile = lock_cut, rcs = rcs_lock), saved_locks)
# No process-memory registry exists: provenance/lock validation always
# re-reads the authority checkpoint from disk, so a reload is equivalent to
# a fresh session by construction.
reloaded <- readRDS(saved_locks)
stopifnot(length(reference_apply_joint_tertiles(dev_cut, reloaded$tertile)$group) == nrow(dev_cut))
stopifnot(nrow(reference_grouped_rcs(
  dat, "futime", "fustatus", "SOSM", "SOFA_Group",
  covariates = c("Age", "Gender", "Creatinine", "SparseFactor"),
  locked_spec = reloaded$rcs, outcome_cfg = ctx$config, grid_n = 6L
)$curve) > 0L)

# Any authority checkpoint mutation invalidates previously serialized locks.
saveRDS(
  list(split_role = "internal", ctx = list(data = list(train = dev_cut))),
  authority_cut
)
expect_error(
  reference_apply_joint_tertiles(dev_cut, reloaded$tertile),
  "checkpoint|MD5|split"
)

cat("test_prognosis_reference_assoc: OK\n")
