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

# ── Task 5: rename S12/S13, Model2 p, dir name ─────────────────────────────
td <- tempfile("sa_tab")
dir.create(td)
file.create(file.path(td, "Table 1-eICU. Baseline characteristics.xlsx"))
file.create(file.path(td, "Table 2-eICU. Logistic regression of NLR quartile.xlsx"))
incidence_sensitivity_rename_pub_tables(td, "eICU", "非高血压", "incidence")
fns <- list.files(td)
stopifnot(any(grepl("^Table S12-eICU\\. Sensitivity analysis-非高血压", fns)))
stopifnot(any(grepl("^Table S13-eICU\\. Sensitivity analysis-非高血压", fns)))

# 预后 Cox 表文件名不含 "Cox regression"，仍应打成 S13；Baseline 仍为 S12
td_cox <- tempfile("sa_cox")
dir.create(td_cox)
file.create(file.path(td_cox, "Table 1-MIMIC. Baseline characteristics.xlsx"))
file.create(file.path(
  td_cox,
  "Table 2-MIMIC. The Association Between NLR and death (Cox quartile).xlsx"
))
incidence_sensitivity_rename_pub_tables(td_cox, "MIMIC", "非高血压", "prognosis")
fns_cox <- list.files(td_cox)
stopifnot(any(grepl("^Table S12-MIMIC\\. Sensitivity analysis-", fns_cox)))
stopifnot(any(grepl(
  "^Table S13-MIMIC\\. Sensitivity analysis-非高血压\\. The Association Between NLR and death \\(Cox quartile\\)",
  fns_cox
)))
unlink(td_cox, recursive = TRUE)

# 12 列 logistic 表：第 12 列是 Model2 P，最后一行是最高组
rt <- as.data.frame(matrix("0.40", 3, 12), stringsAsFactors = FALSE)
rt[3, 12] <- "0.012"
ctx <- list(results = list(logistic_table2 = rt))
p <- incidence_sensitivity_model2_primary_p(ctx)
stopifnot(abs(p - 0.012) < 1e-8)

rt_lt <- as.data.frame(matrix("0.40", 3, 12), stringsAsFactors = FALSE)
rt_lt[3, 12] <- "<0.001"
p_lt <- incidence_sensitivity_model2_primary_p(list(results = list(logistic_table2 = rt_lt)))
stopifnot(abs(p_lt - 0.0005) < 1e-8)

# 末行若是 p for trend，取最后一个非趋势/非 Ref/非表头行（最高组）
rt_tr <- as.data.frame(matrix("0.40", 4, 12), stringsAsFactors = FALSE)
rt_tr[3, 12] <- "0.20"
rt_tr[4, 1] <- "p for trend"
rt_tr[4, 12] <- "0.01"
p_tr <- incidence_sensitivity_model2_primary_p(list(results = list(logistic_table2 = rt_tr)))
stopifnot(abs(p_tr - 0.20) < 1e-8)

stopifnot(grepl(
  "【success】SA_no_Hypertension",
  incidence_batch_output_dir_name("SA_no_Hypertension", "success"),
  fixed = TRUE
))

# drop_constant 后同步 common_model_factors = setdiff(m2, m1)
cfg_cm <- incidence_sensitivity_drop_constant_from_config(cfg, df)
stopifnot(identical(
  cfg_cm$dual_db$harmonization$common_model_factors,
  setdiff(
    cfg_cm$dual_db$harmonization$harmonized_model2_nhanes,
    cfg_cm$dual_db$harmonization$harmonized_model1_nhanes
  )
))

# scenarios_for_index：主分析 categorical_vars + imputed（非 shared）
sa_parent <- tempfile("sa_parent")
sa_ck <- tempfile("sa_ck")
dir.create(sa_parent)
sa_ix <- "NLR"
for (db in c("nhanes", "mimic")) {
  dir.create(file.path(sa_parent, db, "Tables"), recursive = TRUE)
  writeLines(c("Hypertension", "Age"),
             file.path(sa_parent, db, "Tables", "categorical_vars.txt"))
  d <- file.path(sa_ck, sa_ix, db)
  dir.create(d, recursive = TRUE)
  df_imp <- data.frame(
    Hypertension = c(rep("Yes", 51), rep("No", 60)),
    Age = c(rep(70, 60), rep(50, 51)),
    stringsAsFactors = FALSE
  )
  saveRDS(list(ctx = list(data = list(imputed = df_imp))),
          file.path(d, "imputation.rds"))
}
cfg_sc <- list(incidence_batch = list(sensitivity_suite = list(
  enable = TRUE, age_cutoff = 65L, min_n_per_db = 50L, min_yes_n = 50L
)))
sc5 <- incidence_sensitivity_scenarios_for_index(
  cfg_sc, sa_parent, sa_ck, sa_ix, c("nhanes", "mimic")
)
labs5 <- vapply(sc5, `[[`, character(1), "label")
stopifnot("SA_no_Hypertension" %in% labs5)
stopifnot("SA_age_ge_65" %in% labs5)
unlink(sa_parent, recursive = TRUE)
unlink(sa_ck, recursive = TRUE)

# write_config 注入轻量标记
base_cfg <- tempfile(fileext = ".R")
writeLines(
  "config <- list(project = list(output_dir = '.'), incidence_batch = list(), dual_db = list(harmonization = list()), feishu = list(enable = TRUE))",
  base_cfg
)
out_cfg <- tempfile(fileext = ".R")
sg_w <- list(
  label = "SA_no_Hypertension",
  expr = 'is.na(Hypertension) | trimws(as.character(Hypertension)) != "Yes"'
)
incidence_sensitivity_write_config(
  base_cfg, tempfile("stg"), tempfile("ck"), sg_w, out_cfg,
  scheme = "quartile", zh_desc = "非高血压"
)
txt_w <- paste(readLines(out_cfg, warn = FALSE), collapse = "\n")
stopifnot(grepl("config$incidence_batch$.sensitivity_light <- TRUE", txt_w, fixed = TRUE))
stopifnot(grepl(".sensitivity_scheme", txt_w, fixed = TRUE))
stopifnot(grepl(".sensitivity_zh_desc", txt_w, fixed = TRUE))
unlink(c(base_cfg, out_cfg))

cat("Task5 OK\n")

# ── Task 6: Worker 轻量路径源码守卫（避免再走 shared + imputation）──────────
inc_w <- paste(readLines("run/incidence/run_incidence_dual_batch_worker.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("\\.sensitivity_light", inc_w))
stopifnot(grepl("incidence_sensitivity_copy_imputed_ck|sensitivity_light", inc_w))
# 轻量分支不得在 light 为 TRUE 时无条件 copy shared
surv_w <- paste(readLines("run/survival/run_survival_dual_batch_worker.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("\\.sensitivity_light", surv_w))

.light_before_copy_in_else <- function(src) {
  light_m <- gregexpr(
    "if\\s*\\(\\s*isTRUE\\s*\\([^)]*\\.sensitivity_light",
    src, perl = TRUE
  )[[1L]]
  copy_m <- gregexpr("incidence_batch_copy_shared_ck", src, perl = TRUE)[[1L]]
  if (length(light_m) < 1L || light_m[[1L]] < 0L) return(FALSE)
  if (length(copy_m) < 1L || copy_m[[1L]] < 0L) return(FALSE)
  if (light_m[[1L]] >= copy_m[[1L]]) return(FALSE)
  between <- substr(src, light_m[[1L]], copy_m[[1L]])
  grepl("\\}\\s*else", between, perl = TRUE)
}
stopifnot(.light_before_copy_in_else(inc_w))
stopifnot(.light_before_copy_in_else(surv_w))

stopifnot(grepl("incidence_sensitivity_light_blocks", inc_w, fixed = TRUE))
stopifnot(grepl("incidence_sensitivity_trim_pipeline", inc_w, fixed = TRUE))
stopifnot(grepl("incidence_sensitivity_light_blocks", surv_w, fixed = TRUE))
stopifnot(grepl("incidence_sensitivity_trim_pipeline", surv_w, fixed = TRUE))
stopifnot(grepl(
  "incidence_sensitivity_light_blocks\\(\\s*[\"']incidence[\"']",
  inc_w, perl = TRUE
))
stopifnot(grepl(
  "incidence_sensitivity_light_blocks\\(\\s*[\"']prognosis[\"']",
  surv_w, perl = TRUE
))

# 轻量必须要求已有 per_index_ck/index.rds；从过滤后 index 起步，不续跑 leftover imputation
stopifnot(grepl("index\\.rds", inc_w))
stopifnot(grepl("index\\.rds", surv_w))
stopifnot(grepl("initial_ctx", inc_w, fixed = TRUE))
stopifnot(grepl("initial_ctx", surv_w, fixed = TRUE))
stopifnot(grepl("pipe$blocks[1]", inc_w, fixed = TRUE) ||
            grepl("pipe$blocks[[1", inc_w, fixed = TRUE))
stopifnot(grepl("tail(pipe$blocks", inc_w, fixed = TRUE))
stopifnot(grepl("pipe$blocks[1]", surv_w, fixed = TRUE) ||
            grepl("pipe$blocks[[1", surv_w, fixed = TRUE))
stopifnot(grepl("tail(pipe$blocks", surv_w, fixed = TRUE))

# 截断管线上关 logistic / cox 闸门
stopifnot(grepl("logistic_gate$enable <- FALSE", inc_w, fixed = TRUE))
stopifnot(grepl("cox_gate$enable <- FALSE", surv_w, fixed = TRUE))

# 预后：.sensitivity_light 来自 survival_batch %||% incidence_batch；scheme 缺省 quartile
stopifnot(grepl(
  "survival_batch %||% config$incidence_batch",
  surv_w, fixed = TRUE
))
stopifnot(grepl("\\.sensitivity_scheme", surv_w))
stopifnot(grepl("quartile", surv_w, fixed = TRUE))

# 非轻量路径仍保留 copy shared
stopifnot(grepl("incidence_batch_copy_shared_ck", inc_w, fixed = TRUE))
stopifnot(grepl("incidence_batch_copy_shared_ck", surv_w, fixed = TRUE))

cat("Task6 OK\n")
