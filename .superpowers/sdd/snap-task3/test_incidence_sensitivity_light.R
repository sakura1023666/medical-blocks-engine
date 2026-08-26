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

# ── Task 2: discover_yesno / age_scenarios / read_table1_vars ───────────────
nh <- data.frame(
  Hypertension = c(rep("Yes", 51), rep("No", 60)),
  T2DM = c(rep("Yes", 40), rep("No", 71)),
  Race = c(rep("White", 80), rep("Black", 31)),
  Age = c(rep(70, 40), rep(50, 71)),
  stringsAsFactors = FALSE
)
mi <- data.frame(
  Hypertension = c(rep("Yes", 55), rep("No", 50)),
  T2DM = c(rep("Yes", 60), rep("No", 45)),
  Race = c(rep("White", 70), rep("Black", 35)),
  Age = c(rep(70, 80), rep(50, 25)),
  stringsAsFactors = FALSE
)
t1 <- list(nhanes = c("Hypertension", "T2DM", "Race", "Age"),
           mimic  = c("Hypertension", "T2DM", "Race", "Age"))
sc <- incidence_sensitivity_discover_yesno(
  t1, list(nhanes = nh, mimic = mi), min_yes_n = 50L
)
labs <- vapply(sc, `[[`, character(1), "label")
stopifnot("SA_no_Hypertension" %in% labs)
stopifnot(!"SA_no_T2DM" %in% labs)
stopifnot(!"SA_no_Race" %in% labs)

age_sc <- incidence_sensitivity_age_scenarios(
  65L, list(nhanes = nh, mimic = mi), min_n = 50L
)
age_labs <- vapply(age_sc, `[[`, character(1), "label")
stopifnot(!"SA_age_ge_65" %in% age_labs)
stopifnot(!"SA_age_lt_65" %in% age_labs)

d_ok <- list(
  nhanes = data.frame(Age = c(rep(70, 60), rep(50, 60))),
  mimic  = data.frame(Age = c(rep(70, 60), rep(50, 60)))
)
age_ok <- incidence_sensitivity_age_scenarios(65L, d_ok, min_n = 50L)
stopifnot(length(age_ok) == 2L)
d_bad <- list(
  nhanes = data.frame(Age = c(rep(70, 40), rep(50, 80))),
  mimic  = data.frame(Age = c(rep(70, 80), rep(50, 40)))
)
age_bad <- incidence_sensitivity_age_scenarios(65L, d_bad, min_n = 50L)
stopifnot(length(age_bad) == 0L)

tmp_parent <- tempfile("t1vars_")
dir.create(tmp_parent)
db_dir <- file.path(tmp_parent, "nhanes")
dir.create(file.path(db_dir, "Tables"), recursive = TRUE)
writeLines(c("Hypertension", "Age", "Gender"), file.path(db_dir, "Tables", "categorical_vars.txt"))
vars <- incidence_sensitivity_read_table1_vars(tmp_parent, "nhanes")
stopifnot(all(c("Hypertension", "Age", "Gender") %in% vars))
unlink(tmp_parent, recursive = TRUE)

cat("Task2 OK\n")
