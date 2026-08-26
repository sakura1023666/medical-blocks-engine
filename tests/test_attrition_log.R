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

# auto append only when nrow changes
ctx2 <- ctx
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 10L)
stopifnot(length(ctx2$results$attrition$log) == 1L)
ctx2 <- attrition_auto_append_nrow(ctx2, "boxplot", 10L, 8L)
stopifnot(any(vapply(ctx2$results$attrition$log, function(x) identical(x$step_id, "auto_boxplot"), logical(1))))

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

# Promote Inclusion-exclusion PDF → Figure 1. Flowchart.pdf
promoted <- attrition_promote_figure1(td)
stopifnot(isTRUE(promoted))
fig1 <- file.path(td, "Figure 1. Flowchart.pdf")
stopifnot(file.exists(fig1), file.info(fig1)$size > 0)

cat("OK attrition_log\n")
