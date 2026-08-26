# tests/test_incidence_sensitivity_light.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/incidence_sensitivity_suite.R"), local = FALSE)

stopifnot(isTRUE(incidence_sensitivity_is_yes_no(c("Yes", "No", "Yes", NA))))
stopifnot(isTRUE(incidence_sensitivity_is_yes_no(c(1, 0, 1))))
stopifnot(!isTRUE(incidence_sensitivity_is_yes_no(c("White", "Black", "Other"))))
stopifnot(!isTRUE(incidence_sensitivity_is_yes_no(c("Male", "Female"))))
stopifnot(identical(incidence_sensitivity_yes_n(c("Yes", "No", "Yes", "Yes ")), 3L))

ex <- incidence_sensitivity_exclude_yes_expr("Hypertension")
stopifnot(grepl("Hypertension", ex, fixed = TRUE))
stopifnot(grepl("Yes", ex, fixed = TRUE))

stopifnot(identical(incidence_sensitivity_zh_desc("SA_no_Hypertension"), "非高血压"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_no_T2DM"), "非糖尿病"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_age_ge_65", 65), "年龄≥65"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_age_lt_60", 60), "年龄<60"))

st <- incidence_sensitivity_pub_stem(
  12L, "eICU", "非高血压", "Baseline characteristics"
)
stopifnot(grepl("^Table S12-eICU\\. Sensitivity analysis-非高血压\\. Baseline characteristics$", st))
st13 <- incidence_sensitivity_pub_stem(
  13L, "MIMIC", "年龄≥65", "Cox regression of NLR quartile"
)
stopifnot(grepl("Table S13-MIMIC", st13, fixed = TRUE))
stopifnot(grepl("Sensitivity analysis-年龄≥65", st13, fixed = TRUE))

stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, TRUE, 0.01, 0.02, 0.05),
  "success"
))
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, TRUE, 0.01, 0.20, 0.05),
  "failed"
))
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, FALSE, 0.01, 0.02, 0.05),
  "failed"
))
cat("Task1 OK\n")
