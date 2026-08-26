#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/cox_ph_test.R"), local = FALSE)

set.seed(1)
n <- 120
d <- data.frame(
  futime = rexp(n, 0.05),
  fustatus = rbinom(n, 1, 0.4),
  BAR = rnorm(n, 10, 3),
  Age = rnorm(n, 60, 10),
  BMI = rnorm(n, 25, 4),
  stringsAsFactors = FALSE
)
d$Group <- cut(d$BAR, breaks = quantile(d$BAR, probs = 0:4 / 4), include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4"))
d$Num <- as.numeric(d$Group)
suppressPackageStartupMessages(library(survival))
res <- coxph(Surv(futime, fustatus) ~ Group, data = d)
res2 <- coxph(Surv(futime, fustatus) ~ Group + Age, data = d)
res3 <- coxph(Surv(futime, fustatus) ~ Group + Age + BMI, data = d)
fits <- list(crude = res, model1 = res2, model2 = res2, model3 = res3)
tab <- cox_ph_fits_to_table(fits)
stopifnot(is.data.frame(tab), nrow(tab) >= 3L)
stopifnot(all(c("Model", "Term", "Chi-square", "df", "P value", "N", "Events") %in% names(tab)))
stopifnot(any(tab$Term == "GLOBAL"))
# 默认不含 Model 3
stopifnot(!"Model 3" %in% tab$Model)
tab_m3 <- cox_ph_fits_to_table(fits, include_model3 = TRUE)
stopifnot("Model 3" %in% tab_m3$Model)

td <- tempfile("ph_test_")
dir.create(td, recursive = TRUE)
ctx <- list(
  config = list(
    project = list(disease = "SAE", database = "MIMIC"),
    survival = list(index_var = "BAR")
  ),
  results = list(
    Model1Factors = "Age",
    Model2Factors = c("Age", "BMI"),
    cox_model1_covariates = "Age"
  ),
  output_dir_tables = td,
  output_dir = td
)
ctx$results$Model3Factors <- c("Age", "BMI", "Gender")
ctx$results$model3_significant <- TRUE
ctx <- cox_ph_export_supp_table(ctx, fits, "BAR", list(ph_table_number = 14L))
if (exists("render_queued_tables", mode = "function") && length(.table_queue_env$items %||% list())) {
  ctx <- render_queued_tables(ctx)
}
stopifnot(!is.null(ctx$results$cox_ph_test))
stopifnot(!"Model 3" %in% ctx$results$cox_ph_test$Model)
stopifnot(length(list.files(td, pattern = "S14|Proportional|hazards", ignore.case = TRUE)) >= 1L)
# 导出脚注不得出现 Model 3（抽查队列或磁盘 xlsx 旁 sidecar 难读，以 results 表行为准）
stopifnot(!"Model 3" %in% unique(as.character(ctx$results$cox_ph_test$Model)))

ctx_stale <- list(
  results = list(
    Model1Factors = "Age",
    Model2Factors = c("Age", "AnionGap", "SOFA", "GCS", "OASIS"),
    cox_model1_covariates = "Age",
    cox_model2_covariates = "GCS",
    Model3Factors = c("Age", "GCS", "Gender", "Hypertension", "T2DM"),
    model3_significant = TRUE
  )
)
fac <- cox_ph_resolve_footnote_factors(ctx_stale)
stopifnot(identical(fac$M1, "Age"))
stopifnot(identical(sort(fac$M2), c("Age", "GCS")))
stopifnot("Gender" %in% fac$M3)

message("test_cox_ph_test: OK")
