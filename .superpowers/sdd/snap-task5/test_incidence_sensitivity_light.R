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

# ── Task 3: copy_imputed_ck — strip post-imputation blocks ─────────────────
src <- tempfile("ck_src")
dst <- tempfile("ck_dst")
dir.create(src)
saveRDS(list(ctx = list(data = list(imputed = data.frame(Age = 1:3)))),
        file.path(src, "imputation.rds"))
saveRDS(list(marker = "later"), file.path(src, "baseline_binary.rds"))
saveRDS(list(marker = "later"), file.path(src, "logistic_quartile_glm.rds"))
saveRDS(list(marker = "stale_index"), file.path(src, "index.rds"))
incidence_sensitivity_copy_imputed_ck(src, dst)
stopifnot(file.exists(file.path(dst, "imputation.rds")))
stopifnot(file.exists(file.path(dst, "index.rds")))
stopifnot(!file.exists(file.path(dst, "baseline_binary.rds")))
stopifnot(!file.exists(file.path(dst, "logistic_quartile_glm.rds")))
idx <- readRDS(file.path(dst, "index.rds"))
stopifnot(!is.null(idx$ctx$data$imputed))
unlink(src, recursive = TRUE)
unlink(dst, recursive = TRUE)

cat("Task3 OK\n")

# ── Task 3b: copy_imputed_ck — production step05_ prefix ─────────────────────
src5 <- tempfile("ck_src5")
dst5 <- tempfile("ck_dst5")
dir.create(src5)
saveRDS(list(ctx = list(data = list(imputed = data.frame(Age = 1:3)))),
        file.path(src5, "step05_imputation.rds"))
saveRDS(list(marker = "later"), file.path(src5, "baseline_binary.rds"))
incidence_sensitivity_copy_imputed_ck(src5, dst5)
stopifnot(file.exists(file.path(dst5, "index.rds")))
stopifnot(!file.exists(file.path(dst5, "baseline_binary.rds")))
idx5 <- readRDS(file.path(dst5, "index.rds"))
stopifnot(!is.null(idx5$ctx$data$imputed))
unlink(src5, recursive = TRUE)
unlink(dst5, recursive = TRUE)

cat("Task3b OK\n")

# ── Task 4: light_blocks / trim_pipeline / constant_vars / drop_constant ───
inc_w <- incidence_sensitivity_light_blocks("incidence", TRUE, "quartile")
stopifnot(identical(inc_w[1:3], c("obj", "baseline_nhanes", "logistic_quartile_nhanes_weighted")))
stopifnot("dual_db_logistic_main_table_realign" %in% inc_w)
stopifnot(!"imputation" %in% inc_w)
stopifnot(!"rcs_nhanes" %in% inc_w)

inc_u <- incidence_sensitivity_light_blocks("incidence", FALSE, "tertile")
stopifnot("baseline_binary" %in% inc_u)
stopifnot("logistic_tertile_glm" %in% inc_u)

surv <- incidence_sensitivity_light_blocks("prognosis", FALSE, "binary")
stopifnot(identical(surv, c("baseline_binary", "cox_binary")))

pipe <- list(blocks = c("imputation", "baseline_binary", "boxplot", "cox_quartile", "rcs_prognosis"),
             render_tables_after = c("imputation", "baseline_binary", "cox_quartile"))
tr <- incidence_sensitivity_trim_pipeline(pipe, c("baseline_binary", "cox_quartile"))
stopifnot(identical(tr$blocks, c("baseline_binary", "cox_quartile")))
stopifnot(!"imputation" %in% tr$render_tables_after)

df <- data.frame(
  Age = 1:10,
  Hypertension = factor(rep("No", 10), levels = c("No", "Yes")),
  WBC = rnorm(10)
)
stopifnot(identical(incidence_sensitivity_constant_vars(df, c("Age", "Hypertension", "WBC")),
                    "Hypertension"))

cfg <- list(
  dual_db = list(harmonization = list(
    harmonized_model1_nhanes = c("Age", "Hypertension"),
    harmonized_model1_mimic = c("Age", "Hypertension"),
    harmonized_model2_nhanes = c("Age", "Hypertension", "WBC"),
    harmonized_model2_mimic = c("Age", "Hypertension", "WBC")
  )),
  baseline_binary = list(include_vars = c("Age", "Hypertension", "WBC")),
  baseline_nhanes = list(include_vars = c("Age", "Hypertension"))
)
cfg2 <- incidence_sensitivity_drop_constant_from_config(cfg, df)
stopifnot(!"Hypertension" %in% cfg2$dual_db$harmonization$harmonized_model2_nhanes)
stopifnot(all(c("Age", "WBC") %in% cfg2$dual_db$harmonization$harmonized_model2_nhanes))
stopifnot(!"Hypertension" %in% cfg2$baseline_binary$include_vars)
stopifnot(!"Hypertension" %in% cfg2$baseline_nhanes$include_vars)

cat("Task4 OK\n")
