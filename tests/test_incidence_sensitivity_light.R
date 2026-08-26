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
stopifnot(identical(incidence_sensitivity_zh_desc("SA_complete_case"), "complete case unimputed"))

st <- incidence_sensitivity_pub_stem(
  12L, "eICU", "非高血压", "Baseline characteristics",
  label = "SA_no_Hypertension", role = "baseline"
)
stopifnot(identical(st, "Table S12-eICU. SA-no_Hypertension. Baseline"))
st13 <- incidence_sensitivity_pub_stem(
  13L, "MIMIC", "年龄≥65", "Cox regression of NLR quartile",
  label = "SA_age_ge_65", role = "association"
)
stopifnot(identical(st13, "Table S13-MIMIC. SA-age_ge_65. Association"))
stopifnot(grepl(
  "Sensitivity analysis-年龄≥65",
  incidence_sensitivity_pub_title(13L, "MIMIC", "年龄≥65", "Cox regression"),
  fixed = TRUE
))

# 表号顺延：无主附表 → 兜底 12/13；主 Tables 最大 S12 → 敏感性 13/14
stopifnot(identical(
  incidence_sensitivity_resolve_pub_s_nums(NULL)$baseline, 12L
))
stopifnot(identical(
  incidence_sensitivity_resolve_pub_s_nums(NULL)$association, 13L
))
td_main <- tempfile("sa_main_tab")
dir.create(file.path(td_main, "Tables"), recursive = TRUE)
file.create(file.path(td_main, "Tables", "Table S12-eICU. PH assumption.xlsx"))
file.create(file.path(td_main, "Tables", "Table S7-MIMIC. Final multivariable.xlsx"))
stopifnot(identical(incidence_sensitivity_main_max_supp_num(td_main), 12L))
sn <- incidence_sensitivity_resolve_pub_s_nums(td_main)
stopifnot(identical(sn$baseline, 13L), identical(sn$association, 14L))
td_cont <- tempfile("sa_cont")
dir.create(td_cont)
file.create(file.path(td_cont, "Table 1-eICU. Baseline characteristics.xlsx"))
file.create(file.path(td_cont, "Table 2-eICU. The Association Between NLR and death.xlsx"))
incidence_sensitivity_rename_pub_tables(
  td_cont, "eICU", "非高血压", "prognosis", parent_dir = td_main,
  label = "SA_no_Hypertension"
)
fns_cont <- list.files(td_cont)
stopifnot(any(grepl("^Table S13-eICU\\. SA-no_Hypertension\\. Baseline", fns_cont)))
stopifnot(any(grepl("^Table S14-eICU\\. SA-no_Hypertension\\. Association", fns_cont)))
unlink(td_cont, recursive = TRUE)
unlink(td_main, recursive = TRUE)

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
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, TRUE, 0.01, 0.20, 0.05, require_sig = FALSE),
  "success"
))
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, FALSE, 0.01, 0.02, 0.05, require_sig = FALSE),
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
writeLines(c("BMI", "Age"), file.path(db_dir, "Tables", "continuous_vars.txt"))
allv <- incidence_sensitivity_read_table1_analysis_vars(tmp_parent, "nhanes")
stopifnot(all(c("Hypertension", "Gender", "BMI", "Age") %in% allv))
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
stopifnot(file.exists(file.path(dst, "index.rds")))
stopifnot(!file.exists(file.path(dst, "baseline_binary.rds")))
stopifnot(!file.exists(file.path(dst, "logistic_quartile_glm.rds")))
idx <- readRDS(file.path(dst, "index.rds"))
stopifnot(!is.null(idx$ctx$data$imputed))
imp_left <- list.files(dst, pattern = "imputation\\.rds$")
if (length(imp_left)) {
  stopifnot(identical(
    readRDS(file.path(dst, imp_left[[1L]]))$ctx$data$imputed,
    idx$ctx$data$imputed
  ))
} else {
  stopifnot(!file.exists(file.path(dst, "imputation.rds")))
}
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
imp5 <- list.files(dst5, pattern = "imputation\\.rds$")
if (length(imp5)) {
  stopifnot(identical(
    readRDS(file.path(dst5, imp5[[1L]]))$ctx$data$imputed,
    idx5$ctx$data$imputed
  ))
} else {
  stopifnot(!file.exists(file.path(dst5, "imputation.rds")))
  stopifnot(!file.exists(file.path(dst5, "step05_imputation.rds")))
}
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
incidence_sensitivity_rename_pub_tables(
  td, "eICU", "非高血压", "incidence", label = "SA_no_Hypertension"
)
fns <- list.files(td)
stopifnot(any(grepl("^Table S12-eICU\\. SA-no_Hypertension\\. Baseline", fns)))
stopifnot(any(grepl("^Table S13-eICU\\. SA-no_Hypertension\\. Association", fns)))

# 预后 Cox 表文件名不含 "Cox regression"，仍应打成 S13；Baseline 仍为 S12
td_cox <- tempfile("sa_cox")
dir.create(td_cox)
file.create(file.path(td_cox, "Table 1-MIMIC. Baseline characteristics.xlsx"))
file.create(file.path(
  td_cox,
  "Table 2-MIMIC. The Association Between NLR and death (Cox quartile).xlsx"
))
incidence_sensitivity_rename_pub_tables(
  td_cox, "MIMIC", "非高血压", "prognosis", label = "SA_no_Hypertension"
)
fns_cox <- list.files(td_cox)
stopifnot(any(grepl("^Table S12-MIMIC\\. SA-no_Hypertension\\. Baseline", fns_cox)))
stopifnot(any(grepl("^Table S13-MIMIC\\. SA-no_Hypertension\\. Association", fns_cox)))
unlink(td_cox, recursive = TRUE)

# Cox binary 已有 "Sensitivity analysis:" 前缀时不得叠成两段；文件名走短格式
td_sa <- tempfile("sa_coxbin")
dir.create(td_sa)
file.create(file.path(
  td_sa,
  "Table 2-MIMIC. Sensitivity analysis: Multivariable Cox.xlsx"
))
incidence_sensitivity_rename_pub_tables(
  td_sa, "MIMIC", "非高血压", "prognosis", label = "SA_no_Hypertension"
)
fns_sa <- list.files(td_sa)
stopifnot(length(fns_sa) == 1L)
stopifnot(grepl("^Table S13-MIMIC\\. SA-no_Hypertension\\. Association", fns_sa))
stopifnot(!grepl("Sensitivity analysis", fns_sa, fixed = TRUE))
unlink(td_sa, recursive = TRUE)

# 分位基线 / 正态性不得改名进 S10，汇总只留短名 S12/S13
td_extra <- tempfile("sa_extra")
dir.create(td_extra)
file.create(file.path(td_extra, "Table 1-eICU. Baseline characteristics of SAE.xlsx"))
file.create(file.path(td_extra, "Table 2-eICU. The Association Between BAR and SAE.xlsx"))
file.create(file.path(td_extra, "Table S1-eICU. Normality test results for continuous variables.xlsx"))
file.create(file.path(
  td_extra,
  "Table S10-eICU. Baseline characteristics by BAR quartile.xlsx"
))
incidence_sensitivity_rename_pub_tables(
  td_extra, "eICU", "complete case unimputed", "prognosis",
  label = "SA_complete_case"
)
fns_ex <- list.files(td_extra)
stopifnot(any(grepl("^Table S12-eICU\\. SA-complete_case\\. Baseline", fns_ex)))
stopifnot(any(grepl("^Table S13-eICU\\. SA-complete_case\\. Association", fns_ex)))
stopifnot(any(grepl("Normality test", fns_ex)))
stopifnot(any(grepl("by BAR quartile", fns_ex)))
stopifnot(!any(grepl("SA-complete_case.*by BAR quartile", fns_ex)))
dropped <- incidence_sensitivity_keep_pub_tables(td_extra)
stopifnot(any(grepl("Normality test", dropped)))
stopifnot(any(grepl("quartile", dropped)))
fns_kept <- list.files(td_extra)
stopifnot(length(fns_kept) == 2L)
stopifnot(all(grepl("^Table S1[23]-eICU\\. SA-complete_case\\.", fns_kept)))
unlink(td_extra, recursive = TRUE)

src_ix <- tempfile("sa_sync")
dir.create(file.path(src_ix, "eICU", "Tables"), recursive = TRUE)
dir.create(file.path(src_ix, "MIMIC", "Tables"), recursive = TRUE)
dir.create(file.path(src_ix, "Tables"), recursive = TRUE)
file.create(file.path(src_ix, "Tables", "Table 1-eICU. Baseline characteristics of SAE.xlsx"))
file.create(file.path(src_ix, "Tables", "Table 3-MIMIC. Baseline characteristics of SAE.xlsx"))
file.create(file.path(src_ix, "Tables", "Table S1-eICU. Normality test results.xlsx"))
file.create(file.path(
  src_ix, "eICU", "Tables",
  "Table S12-eICU. SA-complete_case. Baseline.xlsx"
))
file.create(file.path(
  src_ix, "eICU", "Tables",
  "Table S13-eICU. SA-complete_case. Association.xlsx"
))
file.create(file.path(
  src_ix, "MIMIC", "Tables",
  "Table S12-MIMIC. SA-complete_case. Baseline.xlsx"
))
file.create(file.path(
  src_ix, "MIMIC", "Tables",
  "Table S13-MIMIC. SA-complete_case. Association.xlsx"
))
file.create(file.path(
  src_ix, "eICU", "Tables",
  "Table S10-eICU. Sensitivity analysis-complete case unimputed. Baseline characteristics by BAR quartile.xlsx"
))
incidence_sensitivity_sync_combined_tables(src_ix, c("eICU", "MIMIC"))
fns_sync <- list.files(file.path(src_ix, "Tables"))
stopifnot(length(fns_sync) == 4L)
stopifnot(all(grepl("^Table S1[23]-(eICU|MIMIC)\\. SA-", fns_sync)))
stopifnot(!any(grepl("S10|Normality|Table 1-|Table 3-", fns_sync)))
unlink(src_ix, recursive = TRUE)

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
stopifnot(grepl("config$incidence_batch$.sensitivity_complete_case <- FALSE", txt_w, fixed = TRUE))

r_sum <- list(
  ns = list(nhanes = 200L, mimic = 180L),
  n_nhanes_after = 80L,
  n_mimic_after = 70L
)
stopifnot(identical(as.integer(incidence_sensitivity_summary_n(r_sum, "nhanes")), 80L))
stopifnot(identical(as.integer(incidence_sensitivity_summary_n(r_sum, "mimic")), 70L))
stopifnot(isTRUE(is.na(incidence_sensitivity_summary_n(list(ns = list(nhanes = 9L)), "nhanes"))))
stopifnot(grepl("model1_factors", txt_w, fixed = TRUE))

# 完整病例：write_config 注入 TRUE
out_cfg_cc <- tempfile(fileext = ".R")
incidence_sensitivity_write_config(
  base_cfg, tempfile("stg"), tempfile("ck"),
  list(label = "SA_complete_case", expr = "", mode = "complete_case"),
  out_cfg_cc, scheme = "quartile", zh_desc = "未插补完整病例"
)
txt_cc <- paste(readLines(out_cfg_cc, warn = FALSE), collapse = "\n")
stopifnot(grepl("config$incidence_batch$.sensitivity_complete_case <- TRUE", txt_cc, fixed = TRUE))
unlink(c(base_cfg, out_cfg, out_cfg_cc))

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

# 轻量跳过 shared index availability；仍要求 per-index index.rds
stopifnot(grepl("if \\(light\\)", inc_w))
stopifnot(grepl("if \\(light\\)", surv_w))
stopifnot(grepl("avail\\[\\[db\\]\\] <- TRUE", inc_w, perl = TRUE))
stopifnot(grepl("avail\\[\\[db\\]\\] <- TRUE", surv_w, perl = TRUE))
stopifnot(grepl("incidence_batch_index_available", inc_w, fixed = TRUE))
stopifnot(grepl("incidence_batch_index_available", surv_w, fixed = TRUE))

# 轻量跳过 Figure 1；预后轻量后走 Cox 双库对齐
stopifnot(grepl("if \\(!isTRUE\\(light\\)\\)", surv_w))
stopifnot(grepl("survival_batch_write_index_flowcharts", surv_w, fixed = TRUE))
stopifnot(grepl("survival_batch_realign_cox_to_unified", surv_w, fixed = TRUE))
fin_src <- paste(readLines("R/incidence_dual_batch_runner.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("\\.sensitivity_light", fin_src))
stopifnot(grepl("incidence_batch_ensure_figure1_placeholder", fin_src, fixed = TRUE))

cat("Task6 OK\n")

# ── Task CC: 未插补完整病例 ─────────────────────────────────────────────────
stopifnot(isTRUE(incidence_sensitivity_is_complete_case(
  list(label = "SA_complete_case", expr = "", mode = "complete_case")
)))
stopifnot(!isTRUE(incidence_sensitivity_is_complete_case(
  list(label = "SA_no_Hypertension", expr = "x")
)))

cc_vars <- incidence_sensitivity_complete_case_vars(
  list(survival = list(time_var = "futime", event_var = "fustatus")),
  "BAR", m1 = "Age", m2 = c("Age", "RDW")
)
stopifnot(all(c("BAR", "futime", "fustatus", "Age", "RDW") %in% cc_vars))

df_cc <- data.frame(
  BAR = c(1, 2, NA, 4, 5),
  Age = c(60, 70, 80, NA, 50),
  RDW = c(12, 13, 14, 15, 16),
  stringsAsFactors = FALSE
)
keep_cc <- incidence_sensitivity_complete_case_keep(df_cc, c("BAR", "Age"))
stopifnot(identical(as.integer(sum(keep_cc)), 3L))

src_cc <- tempfile("src_cc")
dst_cc <- tempfile("dst_cc")
dir.create(src_cc, recursive = TRUE)
mapped_cc <- data.frame(
  BAR = c(1, 2, NA, 4),
  Age = c(60, 70, 80, 90),
  futime = c(10, 20, 30, 40),
  fustatus = c(1, 0, 1, 0),
  stringsAsFactors = FALSE
)
imputed_cc <- mapped_cc
imputed_cc$BAR[is.na(imputed_cc$BAR)] <- 99
saveRDS(
  list(ctx = list(
    data = list(mapped = mapped_cc, imputed = imputed_cc),
    results = list(mice_model = "keep_me_not")
  )),
  file.path(src_cc, "imputation.rds")
)
saveRDS(list(dummy = TRUE), file.path(src_cc, "cox_quartile.rds"))
saveRDS(list(dummy = TRUE), file.path(src_cc, "baseline_binary.rds"))
incidence_sensitivity_copy_unimputed_cc_ck(src_cc, dst_cc, c("BAR", "Age", "futime", "fustatus"))
stopifnot(file.exists(file.path(dst_cc, "index.rds")))
stopifnot(file.exists(file.path(dst_cc, "imputation.rds")))
stopifnot(!file.exists(file.path(dst_cc, "cox_quartile.rds")))
stopifnot(!file.exists(file.path(dst_cc, "baseline_binary.rds")))
obj_cc <- readRDS(file.path(dst_cc, "index.rds"))
stopifnot(identical(nrow(obj_cc$ctx$data$mapped), 3L))
stopifnot(identical(nrow(obj_cc$ctx$data$imputed), 3L))
stopifnot(!any(obj_cc$ctx$data$imputed$BAR == 99, na.rm = TRUE))
stopifnot(isTRUE(obj_cc$ctx$results$sensitivity_complete_case))
stopifnot(is.null(obj_cc$ctx$results$mice_model))
st_cc <- incidence_sensitivity_pub_stem(
  12L, "eICU", "complete case unimputed", "Baseline characteristics",
  label = "SA_complete_case", role = "baseline"
)
stopifnot(identical(st_cc, "Table S12-eICU. SA-complete_case. Baseline"))
st_t2 <- incidence_sensitivity_pub_stem(
  13L, "MIMIC", "complete case unimputed", "The Association Between BAR and SAE",
  label = "SA_complete_case", role = "association"
)
stopifnot(identical(st_t2, "Table S13-MIMIC. SA-complete_case. Association"))
stopifnot(!grepl("未插补", st_t2, fixed = TRUE))
unlink(src_cc, recursive = TRUE)
unlink(dst_cc, recursive = TRUE)

cc_parent <- tempfile("cc_parent")
cc_ck <- tempfile("cc_ck")
dir.create(cc_parent)
ix_cc <- "BAR"
mk_cc_db <- function(db, n, n_na) {
  dir.create(file.path(cc_parent, db, "Tables"), recursive = TRUE)
  writeLines("Age", file.path(cc_parent, db, "Tables", "categorical_vars.txt"))
  d <- file.path(cc_ck, ix_cc, db)
  dir.create(d, recursive = TRUE)
  mapped <- data.frame(
    BAR = c(rep(1, n - n_na), rep(NA_real_, n_na)),
    Age = seq_len(n) + 40,
    futime = seq_len(n),
    fustatus = as.integer(seq_len(n) %% 2),
    stringsAsFactors = FALSE
  )
  imputed <- mapped
  imputed$BAR[is.na(imputed$BAR)] <- 1
  saveRDS(
    list(ctx = list(data = list(mapped = mapped, imputed = imputed))),
    file.path(d, "imputation.rds")
  )
}
mk_cc_db("nhanes", 80L, 5L)
mk_cc_db("mimic", 80L, 5L)
cfg_ok <- list(
  survival = list(time_var = "futime", event_var = "fustatus"),
  incidence_batch = list(sensitivity_suite = list(
    enable = TRUE, complete_case = TRUE, min_n_per_db = 50L,
    age_cutoff = 65L, min_yes_n = 999L
  ))
)
sc_ok <- incidence_sensitivity_scenarios_for_index(
  cfg_ok, cc_parent, cc_ck, ix_cc, c("nhanes", "mimic")
)
labs_ok <- vapply(sc_ok, `[[`, character(1), "label")
stopifnot("SA_complete_case" %in% labs_ok)

mk_cc_db("nhanes", 80L, 40L)
mk_cc_db("mimic", 80L, 40L)
sc_skip <- incidence_sensitivity_scenarios_for_index(
  cfg_ok, cc_parent, cc_ck, ix_cc, c("nhanes", "mimic")
)
labs_skip <- if (length(sc_skip)) vapply(sc_skip, `[[`, character(1), "label") else character(0)
stopifnot(!"SA_complete_case" %in% labs_skip)

cfg_off <- cfg_ok
cfg_off$incidence_batch$sensitivity_suite$complete_case <- FALSE
mk_cc_db("nhanes", 80L, 5L)
mk_cc_db("mimic", 80L, 5L)
sc_off <- incidence_sensitivity_scenarios_for_index(
  cfg_off, cc_parent, cc_ck, ix_cc, c("nhanes", "mimic")
)
labs_off <- if (length(sc_off)) vapply(sc_off, `[[`, character(1), "label") else character(0)
stopifnot(!"SA_complete_case" %in% labs_off)

cfg_def <- cfg_ok
cfg_def$incidence_batch$sensitivity_suite$complete_case <- NULL
sc_def <- incidence_sensitivity_scenarios_for_index(
  cfg_def, cc_parent, cc_ck, ix_cc, c("nhanes", "mimic")
)
labs_def <- if (length(sc_def)) vapply(sc_def, `[[`, character(1), "label") else character(0)
stopifnot("SA_complete_case" %in% labs_def)
unlink(cc_parent, recursive = TRUE)
unlink(cc_ck, recursive = TRUE)
cat("TaskCC OK\n")

# ── Table 2 脚注优先于 VIF FinalCovariates 长名单（禁止敏感性过度调整）──
ft <- incidence_sensitivity_parse_table2_footnotes(c(
  "Crude model was non-adjusted;",
  "Model 1 was adjusted by: Age",
  "Model 2 was adjusted by: Age, BMI, RDW"
))
stopifnot(identical(ft$m1, "Age"))
stopifnot(identical(ft$m2, c("Age", "BMI", "RDW")))
ft_the <- incidence_sensitivity_parse_table2_footnotes(
  "The Crude Model was non-adjusted.\\par\\noindent The Model 1 was adjusted by: Age.\\par\\noindent The Model 2 was adjusted by: Age, BMI, RDW."
)
stopifnot(identical(ft_the$m1, "Age"))
stopifnot(identical(ft_the$m2, c("Age", "BMI", "RDW")))

td_cov <- tempfile("sa_t2cov")
dir.create(file.path(td_cov, "eICU", "Tables", "Summary"), recursive = TRUE)
dir.create(file.path(td_cov, "eICU", "step14_cox_quartile", "Tables"), recursive = TRUE)
dir.create(file.path(td_cov, "MIMIC", "step14_cox_quartile", "Tables"), recursive = TRUE)
dir.create(file.path(td_cov, "sensitivity", "SA_complete_case", "eICU", "step07_cox_quartile", "Tables"), recursive = TRUE)
writeLines(
  c("Age", "BMI", "WBC", "Platelet_Count", "RDW", "Lactate", "PT", "Ventilation"),
  file.path(td_cov, "eICU", "Tables", "Summary", "FinalCovariates_BAR_eicu.txt")
)
writeLines(
  c(
    "Crude model was non-adjusted;\\par\\noindent Model 1 was adjusted by: Age\\par\\noindent Model 2 was adjusted by: Age, BMI, RDW"
  ),
  file.path(td_cov, "eICU", "step14_cox_quartile", "Tables",
            "Table 2-eICU. The Association Between BAR and SAE.tex")
)
writeLines(
  c(
    "Crude model was non-adjusted;\\par\\noindent Model 1 was adjusted by: Age\\par\\noindent Model 2 was adjusted by: Age, BMI, RDW"
  ),
  file.path(td_cov, "MIMIC", "step14_cox_quartile", "Tables",
            "Table 2-MIMIC. The Association Between BAR and SAE.tex")
)
writeLines(
  "The Model 2 was adjusted by: Age, BMI, WBC, Platelet Count, RDW, Lactate, PT, Mechanical ventilation (ever).",
  file.path(
    td_cov, "sensitivity", "SA_complete_case", "eICU", "step07_cox_quartile", "Tables",
    "Table 2-eICU. The Association Between BAR and SAE.tex"
  )
)
cov_locked <- incidence_sensitivity_load_main_covariates(td_cov, "BAR")
stopifnot(identical(cov_locked$m1, "Age"))
stopifnot(identical(cov_locked$m2, c("Age", "BMI", "RDW")))
stopifnot(!"WBC" %in% cov_locked$m2)
stopifnot(!"Lactate" %in% cov_locked$m2)
unlink(td_cov, recursive = TRUE)
cat("TaskTable2Cov OK\n")

# ── Task 7: Config / 能力层默认场景（仅年龄两场；无手写四场）──────────────
source(file.path(root, "R/pipeline_capability_layer.R"), local = FALSE)
src_tpl <- paste(readLines("configs/templates/config_incidence_dual_batch.template.R", warn = FALSE), collapse = "\n")
stopifnot(!grepl("SA_no_hypertension", src_tpl))
stopifnot(grepl("min_yes_n", src_tpl))
stopifnot(grepl("complete_case", src_tpl))
src_b <- paste(readLines("configs/study_interface/incidence_dual_batch_build.R", warn = FALSE), collapse = "\n")
stopifnot(!grepl("SA_no_hypertension", src_b))
src_st <- paste(readLines("configs/templates/config_survival_dual_batch.template.R", warn = FALSE), collapse = "\n")
src_sb <- paste(readLines("configs/study_interface/survival_dual_batch_build.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("complete_case", src_st))
stopifnot(grepl("complete_case", src_sb))
defs <- pipeline_default_sensitivity_scenarios(list())
labs <- vapply(defs, function(s) s$label, character(1))
stopifnot(any(grepl("age_lt", labs)))
stopifnot(!any(grepl("hypertension", labs, ignore.case = TRUE)))
cat("Task7 OK\n")
