# tests/test_attrition_log.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/attrition_log.R"))

ctx <- list(
  config = list(
    data = list(outcome_column = "Disease_Group", id_column = "ID"),
    project = list(database = "MIMIC", analysis_group = "ASCVD", reference_group = "Non_ASCVD"),
    attrition = list(enable = TRUE, auto_append = TRUE, outcome_breakdown = TRUE, steps = list())
  ),
  data = list(
    imputed = data.frame(
      ID = 1:10,
      Disease_Group = factor(c(rep("ASCVD", 3), rep("Non_ASCVD", 7)),
                             levels = c("Non_ASCVD", "ASCVD"))
    )
  ),
  results = list()
)

# record + dedupe by step_id
ctx <- attrition_record(ctx, "after_clean", "After data_clean", 12L)
ctx <- attrition_record(ctx, "after_clean", "After data_clean", 10L) # update
stopifnot(length(ctx$results$attrition$log) == 1L)
stopifnot(identical(as.integer(ctx$results$attrition$log[[1]]$n), 10L))

# empty steps → at least current N
rows <- attrition_finalize_rows(ctx, ctx$config)
stopifnot(nrow(rows) >= 1L)
stopifnot(any(rows$n == 10L))
last <- rows[nrow(rows), , drop = FALSE]
stopifnot(!grepl("ASCVD:", last$step, fixed = TRUE))
stopifnot(identical(as.integer(last$fork_left_n), 3L))
stopifnot(identical(as.integer(last$fork_right_n), 7L))
stopifnot(grepl("ASCVD", last$fork_left_label, fixed = TRUE))
stopifnot(grepl("Non_ASCVD", last$fork_right_label, fixed = TRUE))

# auto append only when nrow changes
ctx2 <- ctx
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 10L)
stopifnot(length(ctx2$results$attrition$log) == 1L)
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 8L)
stopifnot(any(vapply(ctx2$results$attrition$log, function(x) identical(x$step_id, "auto_boxplot"), logical(1))))

# NHANES survey design eligibility must become an explicit attrition step
ctx_w <- ctx
ctx_w$results$attrition <- list(log = list())
ctx_w$results$nhanes_weight_info <- list(
  weight_col = "new_Weight", source = "WTMEC2YR / WTMEC4YR", n_dropped = 4L
)
ctx_w <- attrition_record_survey_weight_step(ctx_w, design_n = 6L)
weight_idx <- which(vapply(
  ctx_w$results$attrition$log,
  function(x) identical(x$step_id, "after_survey_weight"),
  logical(1)
))
stopifnot(length(weight_idx) == 1L)
weight_entry <- ctx_w$results$attrition$log[[weight_idx]]
stopifnot(identical(weight_entry$n, 6L))
stopifnot(grepl("new_Weight", weight_entry$meta$exclude_label, fixed = TRUE))
stopifnot(grepl("WTMEC", weight_entry$meta$exclude_label, fixed = TRUE))

# 0 人因权重剔除时仍须记账（标明权重名）
ctx_w0 <- ctx
ctx_w0$results$attrition <- list(log = list())
ctx_w0 <- attrition_record(ctx_w0, "after_imputation", "After imputation", 10L)
ctx_w0$results$nhanes_weight_info <- list(
  weight_col = "new_Weight", source = "WTMEC2YR / WTMEC4YR", n_dropped = 0L
)
ctx_w0 <- attrition_record_survey_weight_step(ctx_w0, design_n = 10L)
stopifnot(any(vapply(
  ctx_w0$results$attrition$log,
  function(x) identical(x$step_id, "after_survey_weight"),
  logical(1)
)))
w0 <- ctx_w0$results$attrition$log[[which(vapply(
  ctx_w0$results$attrition$log,
  function(x) identical(x$step_id, "after_survey_weight"),
  logical(1)
))[1L]]]
stopifnot(identical(w0$n, 10L))
stopifnot(grepl("new_Weight", w0$meta$exclude_label, fixed = TRUE))

# Outcome fork must use the same survey-eligible cohort as weighted Table 1
ctx_w$results$nhanes_design <- list(
  variables = data.frame(
    Disease_Group = factor(
      c(rep("ASCVD", 2), rep("Non_ASCVD", 4)),
      levels = c("Non_ASCVD", "ASCVD")
    )
  )
)
fork_w <- attrition_resolve_outcome_fork(ctx_w, ctx_w$config)
stopifnot(identical(fork_w$left_n, 2L))
stopifnot(identical(fork_w$right_n, 4L))
stopifnot(fork_w$left_n + fork_w$right_n == 6L)

# missing evidence step skipped (source=id_file bad path)
ctx$config$attrition$steps <- list(
  list(id = "bad", label = "Missing file", source = "id_file",
       path = "/no/such/file.csv", id_col = "subject_id", join_on = "ID")
)
rows2 <- attrition_finalize_rows(ctx, ctx$config)
stopifnot(!any(rows2$step == "Missing file"))

# draw pdf smoke
td <- tempfile("attr_")
dir.create(td)
pdf_path <- file.path(td, "Figure 1. Inclusion exclusion flowchart.pdf")
ok <- attrition_draw_pdf(
  data.frame(step = c("Baseline", "Analytic"), n = c(100L, 80L), stringsAsFactors = FALSE),
  title = "Figure 1. test",
  pdf_path = pdf_path
)
stopifnot(isTRUE(ok), file.exists(pdf_path), file.info(pdf_path)$size > 0)

# Times New Roman must not crash on Linux pdf()/cairo
ok_tnr <- attrition_draw_pdf(
  data.frame(step = c("A", "B"), n = c(10L, 8L), stringsAsFactors = FALSE),
  title = "Figure 1. TNR",
  pdf_path = file.path(td, "tnr.pdf"),
  font_family = "Times New Roman"
)
stopifnot(isTRUE(ok_tnr), file.exists(file.path(td, "tnr.pdf")))

# CONSORT fork boxes (incidence case / control)
ok_fork <- attrition_draw_pdf(
  data.frame(
    step = c("Admission records in MIMIC-IV", "The diagnosis includes SLE", "Included"),
    n = c(65366L, 271L, 264L),
    exclude_label = c(NA_character_, "Diagnosis does not include SLE", "Incomplete after imputation"),
    fork_left_label = c(NA, NA, "AKI group"),
    fork_left_n = c(NA, NA, 106L),
    fork_right_label = c(NA, NA, "No AKI group"),
    fork_right_n = c(NA, NA, 158L),
    stringsAsFactors = FALSE
  ),
  title = "Figure 1. CONSORT test",
  pdf_path = file.path(td, "consort.pdf")
)
stopifnot(isTRUE(ok_fork), file.exists(file.path(td, "consort.pdf")),
          file.info(file.path(td, "consort.pdf"))$size > 2000)

# Promote Inclusion-exclusion PDF → Figure 1. Flowchart.pdf
promoted <- attrition_promote_figure1(td)
stopifnot(isTRUE(promoted))
fig1 <- file.path(td, "Figure 1. Flowchart.pdf")
stopifnot(file.exists(fig1), file.info(fig1)$size > 0)

cat("OK attrition_log\n")
