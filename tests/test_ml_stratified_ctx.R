# tests/test_ml_stratified_ctx.R
root <- normalizePath(".")
impl <- file.path(root, "R/ml_stratified_ctx.R")
stopifnot(file.exists(impl))
source(file.path(root, "R/utils.R"), local = FALSE)
source(impl, local = FALSE)

hash_object <- function(x) {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(x, path, version = 2)
  unname(tools::md5sum(path))
}

tmp <- tempfile("ml_stratified_ctx_")
dir.create(tmp, recursive = TRUE)
source_checkpoint <- file.path(tmp, "index.rds")
writeBin(charToRaw("immutable checkpoint"), source_checkpoint)
checkpoint_hash <- unname(tools::md5sum(source_checkpoint))

imputed <- data.frame(
  patient_id = paste0("p", 1:6),
  SOFA = c(8, 11, 10, NA, 14, 3),
  Group = c("Alive", "Death", "Death", "Alive", "Death", "Alive"),
  value = 1:6,
  row.names = paste0("imp_", 1:6),
  stringsAsFactors = FALSE
)
train <- imputed[c(1, 2, 4), , drop = FALSE]
internal <- imputed[c(3, 5, 6), , drop = FALSE]
non_patient_table <- data.frame(
  metric = c("AUC", "Accuracy"),
  value = c(0.8, 0.7),
  stringsAsFactors = FALSE
)
misleading_summary_table <- data.frame(
  patient_id = c("p1", "summary_total"),
  statistic = c("first", "all"),
  stringsAsFactors = FALSE
)

parent <- list(
  config = list(
    project = list(
      output_dir = file.path(tmp, "original-output"),
      analysis_group = "Death"
    ),
    data = list(id_column = "patient_id"),
    checkpoint = list(enable = TRUE, dir = dirname(source_checkpoint), path = source_checkpoint),
    dual_db = list(checkpoint_base = dirname(source_checkpoint)),
    ml_batch = list(
      index_ck_base = dirname(source_checkpoint),
      shared_ck_base = file.path(dirname(source_checkpoint), "_shared")
    ),
    feature_selection = list(persist_to_checkpoints = TRUE),
    ml_stratified_ctx = list(patient_slots = "custom_patients_v2"),
    train_validation = list(mode = "split"),
    runtime_version = package_version("1.0.0")
  ),
  pipeline = list(checkpoint = list(enable = TRUE, dir = dirname(source_checkpoint))),
  checkpoint_base = dirname(source_checkpoint),
  data = list(
    raw = imputed,
    mapped = imputed,
    cleaned = imputed,
    analysis = imputed,
    imputed = imputed,
    train = train,
    test = internal,
    val = internal,
    custom_patients_v2 = imputed,
    model_metrics = non_patient_table,
    cohort_summary_data = misleading_summary_table
  ),
  results = list(
    upstream_marker = "keep",
    modeling_note = "keep despite containing model",
    mice_model = "keep imputation state",
    selected_features = c("value"),
    Model1Factors = c("Age"),
    ml_models = list(rf = "stale"),
    ml_best_model_tag = "rf",
    cox_models = list(stale = TRUE),
    cox_interaction_fit_main = list(stale = TRUE),
    rcs_prognosis_res_crude = list(stale = TRUE),
    pause_point = list(block = "ml_models"),
    figure_queue = list("stale-figure"),
    table_queue = list("stale-table")
  ),
  models = list(rf = "stale"),
  queues = list(figures = list("stale"), tables = list("stale")),
  log = list(block_output_dirs = list(old = "old"), block_step_counter = 9L),
  root_output_dir = file.path(tmp, "original-output"),
  output_dir = file.path(tmp, "original-output", "step09"),
  output_dir_tables = file.path(tmp, "original-output", "step09", "Tables"),
  output_dir_figures = file.path(tmp, "original-output", "step09", "Figures"),
  current_block = "ml_models"
)

# --- 3-layer SOFA spec contract (breaks = 4, 10) ----------------------------
# fixture SOFA=(8,11,10,NA,14,3):
#   sofa_0_4={p6} sofa_5_10={p1,p3} sofa_11plus={p2,p5} missing={p4}
spec <- ml_stratum_spec_sofa(breaks = c(4, 10))
stopifnot(identical(names(spec$strata),
                    c("sofa_0_4", "sofa_5_10", "sofa_11plus")))
stopifnot(identical(spec$breaks, c(4L, 10L)))
stopifnot(identical(spec$strata$sofa_0_4$label, "SOFA 0\u20134"))
stopifnot(identical(spec$strata$sofa_5_10$label, "SOFA 5\u201310"))
stopifnot(identical(spec$strata$sofa_11plus$label, "SOFA \u226511"))
stopifnot(identical(which(ml_stratum_member(imputed$SOFA, spec$strata$sofa_0_4)), 6L))
stopifnot(identical(which(ml_stratum_member(imputed$SOFA, spec$strata$sofa_5_10)), c(1L, 3L)))
stopifnot(identical(which(ml_stratum_member(imputed$SOFA, spec$strata$sofa_11plus)), c(2L, 5L)))
# 单切点兼容旧 2 层口径
spec8 <- ml_stratum_spec_sofa(breaks = 8)
stopifnot(identical(names(spec8$strata), c("sofa_0_8", "sofa_9plus")))
stopifnot(identical(spec8$strata$sofa_0_8$label, "SOFA 0\u20138"))
stopifnot(identical(spec8$strata$sofa_9plus$label, "SOFA \u22659"))

before_hash <- hash_object(parent)
staging <- file.path(tmp, "staging", "sofa_5_10")
.table_queue_env$items <- list(list(filepath = "stale.xlsx"))
.figure_queue_env <- new.env(parent = emptyenv())
.figure_queue_env$items <- list(list(filepath = "stale.pdf"))
.pub_counters_restore(list(
  main_table = 9L, main_figure = 9L, supp_table = 9L, supp_figure = 9L
))
child <- ml_clone_ctx_for_stratum(parent, spec$strata$sofa_5_10, staging)
after_hash <- hash_object(parent)

# Deep-clone isolation: filtering and stale-state cleanup must not mutate parent.
stopifnot(identical(before_hash, after_hash))
stopifnot(identical(checkpoint_hash, unname(tools::md5sum(source_checkpoint))))
child$data$imputed$value[[1L]] <- 999
stopifnot(parent$data$imputed$value[[1L]] == 1)

# Patient-ID synchronized filtering and original train/internal assignment.
stopifnot(identical(child$data$imputed$patient_id, c("p1", "p3")))
stopifnot(identical(child$data$train$patient_id, "p1"))
stopifnot(identical(child$data$test$patient_id, "p3"))
stopifnot(all(child$data$train$patient_id %in% parent$data$train$patient_id))
stopifnot(all(child$data$test$patient_id %in% parent$data$test$patient_id))
stopifnot(!any(child$data$train$patient_id %in% parent$data$test$patient_id))
stopifnot(!any(child$data$test$patient_id %in% parent$data$train$patient_id))
for (slot in c("raw", "mapped", "cleaned", "analysis")) {
  if (!identical(child$data[[slot]]$patient_id, c("p1", "p3"))) {
    stop("Patient slot was not synchronized: ", slot)
  }
}
stopifnot(identical(child$data$val$patient_id, "p3"))
stopifnot(identical(
  child$data$custom_patients_v2$patient_id,
  c("p1", "p3")
))
stopifnot(identical(child$data$model_metrics, non_patient_table))
stopifnot(identical(child$data$cohort_summary_data, misleading_summary_table))

# Stale feature-selection/model/queue state is gone, while upstream state remains.
stopifnot(identical(child$results$upstream_marker, "keep"))
stopifnot(identical(
  child$results$modeling_note,
  "keep despite containing model"
))
stopifnot(identical(child$results$mice_model, "keep imputation state"))
stopifnot(is.null(child$results$selected_features))
stopifnot(is.null(child$results$Model1Factors))
stopifnot(is.null(child$results$ml_models))
stopifnot(is.null(child$results$ml_best_model_tag))
stopifnot(is.null(child$results$cox_models))
stopifnot(is.null(child$results$cox_interaction_fit_main))
stopifnot(is.null(child$results$rcs_prognosis_res_crude))
stopifnot(is.null(child$results$pause_point))
stopifnot(identical(child$results$figure_queue, list()))
stopifnot(identical(child$results$table_queue, list()))
stopifnot(identical(child$models, list()))
stopifnot(identical(child$queues, list()))
stopifnot(identical(.table_queue_env$items, list()))
stopifnot(identical(
  .pub_counters_snapshot(),
  list(main_table = 0L, main_figure = 1L, supp_table = 0L, supp_figure = 0L)
))
stopifnot(identical(child$log$pub_counters, .pub_counters_snapshot()))

# Every writable output points at staging, with execution log reset.
stopifnot(identical(child$root_output_dir, normalizePath(staging, winslash = "/", mustWork = FALSE)))
stopifnot(identical(child$output_dir, child$root_output_dir))
stopifnot(identical(child$config$project$output_dir, child$root_output_dir))
stopifnot(identical(child$output_dir_tables, file.path(child$root_output_dir, "Tables")))
stopifnot(identical(child$output_dir_figures, file.path(child$root_output_dir, "Figures")))
stopifnot(identical(child$log$block_output_dirs, list()))
stopifnot(identical(child$log$block_step_counter, 0L))
stopifnot(is.null(child$current_block))
staging_checkpoint <- file.path(child$root_output_dir, "checkpoints")
stopifnot(isFALSE(child$config$checkpoint$enable))
stopifnot(identical(child$config$checkpoint$dir, staging_checkpoint))
stopifnot(identical(child$config$dual_db$checkpoint_base, staging_checkpoint))
stopifnot(identical(child$config$ml_batch$index_ck_base, staging_checkpoint))
stopifnot(identical(child$config$ml_batch$shared_ck_base, staging_checkpoint))
stopifnot(isFALSE(child$config$feature_selection$persist_to_checkpoints))
stopifnot(isFALSE(child$pipeline$checkpoint$enable))
stopifnot(identical(child$pipeline$checkpoint$dir, staging_checkpoint))
stopifnot(identical(child$checkpoint_base, staging_checkpoint))
stopifnot(identical(child$config$runtime_version, package_version("1.0.0")))

# Audit reports stratum n/events/missing and split counts (3 SOFA layers + missing).
audit <- ml_stratum_audit(parent, spec)
stopifnot(identical(audit$stratum,
                    c("sofa_0_4", "sofa_5_10", "sofa_11plus", "sofa_missing")))
stopifnot(identical(audit$n, c(1L, 2L, 2L, 1L)))
stopifnot(identical(audit$events, c(0L, 1L, 2L, 0L)))
stopifnot(identical(audit$train_n, c(0L, 1L, 1L, 1L)))
stopifnot(identical(audit$internal_n, c(1L, 1L, 1L, 0L)))

# If no stable ID column exists, row names synchronize all slots.
rn_imputed <- imputed[, setdiff(names(imputed), "patient_id"), drop = FALSE]
rownames(rn_imputed) <- paste0("r", 1:6)
rn_parent <- parent
rn_parent$config$data$id_column <- NULL
rn_parent$config$ml_stratified_ctx$patient_slots <- character(0)
for (slot in c("raw", "mapped", "cleaned", "analysis", "imputed")) {
  rn_parent$data[[slot]] <- rn_imputed
}
rn_parent$data$train <- rn_imputed[c(1, 2, 4), , drop = FALSE]
rn_parent$data$test <- rn_imputed[c(3, 5, 6), , drop = FALSE]
rn_parent$data$validation <- rn_imputed[c(3, 5, 6), , drop = FALSE]
rn_parent$data$internal <- rn_imputed[c(3, 5, 6), , drop = FALSE]
rn_parent$data$val <- rn_imputed[c(3, 5, 6), , drop = FALSE]
# sofa_11plus = {p2,p5} -> rownames r2,r5
rn_child <- ml_clone_ctx_for_stratum(
  rn_parent,
  spec$strata$sofa_11plus,
  file.path(tmp, "staging", "sofa_11plus")
)
stopifnot(identical(rownames(rn_child$data$imputed), c("r2", "r5")))
stopifnot(identical(rownames(rn_child$data$train), "r2"))
stopifnot(identical(rownames(rn_child$data$test), "r5"))
for (slot in c("raw", "mapped", "cleaned", "analysis")) {
  stopifnot(identical(rownames(rn_child$data[[slot]]), c("r2", "r5")))
}
for (slot in c("validation", "internal", "val")) {
  stopifnot(identical(rownames(rn_child$data[[slot]]), "r5"))
}

# A known rowname-mapped slot with no reference overlap must hard fail.
no_overlap_parent <- rn_parent
rownames(no_overlap_parent$data$raw) <- paste0("foreign_", 1:6)
no_overlap_out <- file.path(tmp, "must-not-exist-no-overlap")
no_overlap_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    no_overlap_parent, spec$strata$sofa_11plus, no_overlap_out
  )
  NULL
}, error = identity)
stopifnot(inherits(no_overlap_error, "error"))
stopifnot(grepl("raw", conditionMessage(no_overlap_error), ignore.case = TRUE))
stopifnot(grepl("no overlap", conditionMessage(no_overlap_error), ignore.case = TRUE))
stopifnot(!dir.exists(no_overlap_out))

# Auto-selected ID cannot silently skip a known slot lacking that ID and rowname mapping.
auto_id_parent <- parent
auto_id_parent$config$data$id_column <- NULL
auto_id_parent$config$ml_stratified_ctx$patient_slots <- character(0)
auto_id_parent$data$cleaned$patient_id <- NULL
rownames(auto_id_parent$data$cleaned) <- paste0("unmapped_", 1:6)
auto_id_out <- file.path(tmp, "must-not-exist-auto-id-unmapped")
auto_id_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    auto_id_parent, spec$strata$sofa_5_10, auto_id_out
  )
  NULL
}, error = identity)
stopifnot(inherits(auto_id_error, "error"))
stopifnot(grepl("cleaned", conditionMessage(auto_id_error), ignore.case = TRUE))
stopifnot(grepl(
  "cannot be mapped|no overlap",
  conditionMessage(auto_id_error),
  ignore.case = TRUE
))
stopifnot(!dir.exists(auto_id_out))

# A configured duplicate patient ID must fail instead of falling back to another ID/rownames.
duplicate_parent <- parent
duplicate_parent$data$imputed$patient_id <- c("p1", "p1", "p3", "p4", "p5", "p6")
duplicate_parent$data$imputed$stay_id <- paste0("s", 1:6)
rownames(duplicate_parent$data$imputed) <- paste0("stable_", 1:6)
duplicate_out <- file.path(tmp, "must-not-exist-duplicate")
duplicate_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    duplicate_parent, spec$strata$sofa_5_10, duplicate_out
  )
  NULL
}, error = identity)
stopifnot(inherits(duplicate_error, "error"))
stopifnot(grepl("configured patient ID", conditionMessage(duplicate_error), ignore.case = TRUE))
stopifnot(!dir.exists(duplicate_out))

# A registered patient slot missing the configured ID must fail, not stay unfiltered.
missing_slot_id_parent <- parent
missing_slot_id_parent$data$cleaned$patient_id <- NULL
missing_slot_id_out <- file.path(tmp, "must-not-exist-missing-slot-id")
missing_slot_id_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    missing_slot_id_parent, spec$strata$sofa_5_10, missing_slot_id_out
  )
  NULL
}, error = identity)
stopifnot(inherits(missing_slot_id_error, "error"))
stopifnot(grepl(
  "configured patient ID.*cleaned",
  conditionMessage(missing_slot_id_error),
  ignore.case = TRUE
))
stopifnot(!dir.exists(missing_slot_id_out))

# Default 1:n row names are not stable patient identifiers.
default_rn_parent <- parent
default_rn_parent$config$data$id_column <- NULL
default_rn_parent$config$project$id_column <- NULL
drop_ids <- c("patient_id")
default_rn_parent$data <- lapply(default_rn_parent$data, function(x) {
  if (!is.data.frame(x) || !"patient_id" %in% names(x)) return(x)
  y <- x[, setdiff(names(x), drop_ids), drop = FALSE]
  rownames(y) <- NULL
  y
})
default_rn_out <- file.path(tmp, "must-not-exist-default-rn")
default_rn_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    default_rn_parent, spec$strata$sofa_5_10, default_rn_out
  )
  NULL
}, error = identity)
stopifnot(inherits(default_rn_error, "error"))
stopifnot(grepl("default row names", conditionMessage(default_rn_error), ignore.case = TRUE))
stopifnot(!dir.exists(default_rn_out))

# Empty strata fail before any staging directory is created.
empty_out <- file.path(tmp, "must-not-exist-empty")
empty_error <- tryCatch({
  ml_clone_ctx_for_stratum(
    parent, ml_stratum_spec_sofa(breaks = 99)$strata$sofa_100plus, empty_out
  )
  NULL
}, error = identity)
stopifnot(inherits(empty_error, "error"))
stopifnot(grepl("empty stratum", conditionMessage(empty_error), ignore.case = TRUE))
stopifnot(!dir.exists(empty_out))

# external_all is counted once as external, never mislabeled internal.
external_parent <- parent
external_parent$config$train_validation$mode <- "external_all"
external_parent$data$train <- imputed
external_parent$data$test <- imputed
external_audit <- ml_stratum_audit(external_parent, spec)
stopifnot("external_n" %in% names(external_audit))
stopifnot(!"internal_n" %in% names(external_audit))
stopifnot(!"train_n" %in% names(external_audit))
stopifnot(identical(external_audit$external_n, c(1L, 2L, 2L, 1L)))

# ml_stratum_member rejects an unsupported operator (fail-closed, not silent keep).
bad <- tryCatch(
  ml_stratum_member(imputed$SOFA,
                    list(variable = "SOFA", operator = "<>", lower = 1, upper = 2)),
  error = identity
)
stopifnot(inherits(bad, "error") || is.logical(bad))

unlink(tmp, recursive = TRUE)
cat("test_ml_stratified_ctx: OK\n")
