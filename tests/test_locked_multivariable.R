# tests/test_locked_multivariable.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"), local = FALSE)

# 单库：同名 / 同路径 / dual 未开 → Final multivariable model（与全池多因素区分）
stopifnot(identical(locked_mv_n_databases(list()), 1L))
stopifnot(identical(
  locked_multivariable_table_caption(list(dual_db = list(enable = FALSE))),
  "Final multivariable model"
))
cfg_same <- list(dual_db = list(
  enable = TRUE,
  primary = list(name = "MIMIC", rawdata_path = "/tmp/a.RData"),
  secondary = list(name = "MIMIC", rawdata_path = "/tmp/a.RData")
))
stopifnot(identical(locked_mv_n_databases(cfg_same), 1L))
stopifnot(identical(
  locked_multivariable_table_caption(cfg_same),
  "Final multivariable model"
))

# 双库：无括号，Final + harmonized 后缀
cfg_dual <- list(dual_db = list(
  enable = TRUE,
  primary = list(name = "eICU", rawdata_path = "/tmp/eicu.RData"),
  secondary = list(name = "MIMIC", rawdata_path = "/tmp/mimic.RData")
))
stopifnot(identical(locked_mv_n_databases(cfg_dual), 2L))
stopifnot(identical(
  locked_multivariable_table_caption(cfg_dual),
  "Final multivariable model harmonized"
))

# 文件名去括号 + 长度上限
stopifnot(identical(
  pub_caption_strip_parentheses(
    "Normality test results for continuous variables (n=262)"
  ),
  "Normality test results for continuous variables"
))
ex_max <- "Table S2-MIMIC. Normality test results for continuous variables (n=262).xlsx"
stopifnot(identical(nchar(ex_max, type = "chars"), pub_table_max_filename_n()))
fit <- pub_fit_table_stem(tools::file_path_sans_ext(ex_max), "xlsx")
stopifnot(!grepl("\\(", fit, fixed = TRUE))
stopifnot(nchar(paste0(fit, ".xlsx"), type = "chars") <= pub_table_max_filename_n())
stopifnot(identical(
  logistic_glm_pub_caption("De_Ritis", scheme = "quartile"),
  "Logistic regression of De Ritis quartile"
))

# 协变量铁律：vif_final_pass 优先于 preset Model2
ctx <- list(results = list(
  vif_final_pass = c("Hypertension", "Hyperlipidemia", "De_Ritis"),
  Model2Factors = c("Age", "Gender", "SBP", "Potassium", "BUN", "Hypertension")
))
cfg <- list(incidence = list(index_var = "De_Ritis"))
lk <- locked_multivariable_covariates(ctx, cfg)
stopifnot(identical(sort(lk$covariates), c("Hyperlipidemia", "Hypertension")))
stopifnot(identical(lk$index, "De_Ritis"))
stopifnot("De_Ritis" %in% lk$all)

# 默认强制集：仅 Age，不含 Gender
force_def <- pipeline_force_include_covariates(list())
stopifnot("Age" %in% force_def)
stopifnot(!"Gender" %in% force_def && !"Sex" %in% force_def)
force_sex_on <- pipeline_force_include_covariates(
  list(covariate_policy = list(force_sex = TRUE))
)
stopifnot("Gender" %in% force_sex_on || "Sex" %in% force_sex_on)
# 默认 merge：Gender 不会被塞进 Model2
merged_def <- pipeline_merge_force_covariates(
  character(0), "Hypertension",
  c("Age", "Gender", "Hypertension"),
  list()
)
stopifnot(identical(merged_def$M1, "Age"))
stopifnot("Age" %in% merged_def$M2)
stopifnot(!"Gender" %in% merged_def$M2)
stopifnot("Hypertension" %in% merged_def$M2)

# 缺年龄 → 补进 Model1（数据有 Age 列时）
ens0 <- pipeline_ensure_age_in_model1(
  character(0), c("Hypertension", "Hyperlipidemia"),
  c("Age", "Gender", "Hypertension", "Hyperlipidemia", "De_Ritis"),
  list()
)
stopifnot(identical(ens0$M1, "Age"))
stopifnot("Age" %in% ens0$M2)
stopifnot("Hypertension" %in% ens0$M2)
# 已有年龄则不重复、仍保证在 Model1
ens1 <- pipeline_ensure_age_in_model1(
  character(0), c("Age", "Hypertension"),
  c("Age", "Hypertension"),
  list()
)
stopifnot(identical(ens1$M1, "Age"))
# 无 Age 列则不动
ens2 <- pipeline_ensure_age_in_model1(
  character(0), c("Hypertension"),
  c("Gender", "Hypertension"),
  list()
)
stopifnot(!length(ens2$M1))
stopifnot(identical(ens2$M2, "Hypertension"))

# 已有 Age：UV 回退不再强加 Marital
uv0 <- pipeline_uv_demo_fallback_model1(
  c("Age", "Marital_Status"),
  c("Age", "Marital_Status", "Hypertension"),
  list(covariate_policy = list(force_age = TRUE, force_sex = FALSE))
)
stopifnot(identical(uv0$M1, "Age"))
stopifnot(identical(uv0$dropped, "Marital_Status"))
# 数据有 Age、UV 只有 Marital → 仍只留 Age
uv1 <- pipeline_uv_demo_fallback_model1(
  "Marital_Status",
  c("Age", "Marital_Status"),
  list()
)
stopifnot(identical(uv1$M1, "Age"))
stopifnot("Marital_Status" %in% uv1$dropped)
# 无 Age 列：保留原 UV 人口学
uv2 <- pipeline_uv_demo_fallback_model1(
  "Marital_Status",
  c("Gender", "Marital_Status"),
  list()
)
stopifnot(identical(uv2$M1, "Marital_Status"))
stopifnot(!length(uv2$dropped))
# force_sex=TRUE 时 UV 回退可保留 Gender
uv3 <- pipeline_uv_demo_fallback_model1(
  c("Age", "Gender", "Marital_Status"),
  c("Age", "Gender", "Marital_Status"),
  list(covariate_policy = list(force_age = TRUE, force_sex = TRUE))
)
stopifnot("Age" %in% uv3$M1)
stopifnot("Gender" %in% uv3$M1)
stopifnot("Marital_Status" %in% uv3$dropped)
# 强加 Age 不显著 → 恢复单因素人口学
uv4 <- pipeline_uv_demo_fallback_model1(
  c("Age", "Marital_Status"),
  c("Age", "Marital_Status"),
  list(),
  age_significant = FALSE
)
stopifnot(identical(sort(uv4$M1), c("Age", "Marital_Status")))
stopifnot(!length(uv4$dropped))
uv5 <- pipeline_uv_demo_fallback_model1(
  c("Age", "Marital_Status"),
  c("Age", "Marital_Status"),
  list(),
  age_significant = TRUE
)
stopifnot(identical(uv5$M1, "Age"))
stopifnot("Marital_Status" %in% uv5$dropped)

set.seed(1)
n <- 220L
age <- rnorm(n, 70, 8)
y_sig <- rbinom(n, 1L, plogis(-10 + 0.12 * age))
d_sig <- data.frame(
  Age = age, Disease_Group = y_sig, De_Ritis = rnorm(n),
  stringsAsFactors = FALSE
)
cfg_age <- list(
  data = list(outcome_column = "Disease_Group"),
  incidence = list(index_var = "De_Ritis"),
  multivariate_incidence_binary = list(sig_cutoff = 0.05)
)
stopifnot(isTRUE(pipeline_forced_age_is_significant(d_sig, cfg_age, "De_Ritis")))
y_ns <- rbinom(n, 1L, 0.25)
d_ns <- data.frame(
  Age = age, Disease_Group = y_ns, De_Ritis = rnorm(n),
  stringsAsFactors = FALSE
)
stopifnot(isFALSE(pipeline_forced_age_is_significant(d_ns, cfg_age, "De_Ritis")))

ctx2 <- list(
  results = list(vif_final_pass = c("Hypertension", "Hyperlipidemia", "De_Ritis")),
  data = list(imputed = data.frame(Age = 1, Hypertension = 0, Hyperlipidemia = 0, De_Ritis = 1))
)
lk2 <- locked_multivariable_covariates(ctx2, cfg)
stopifnot("Age" %in% lk2$all)
stopifnot("Age" %in% lk2$model1)

# 分类：全池 Multivariable = multivariate；Final/harmonized = multivariate_harmonized
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S6-MIMIC. Multivariable Regression Analysis.xlsx"
  ),
  "multivariate"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S8-MIMIC. Multivariable Regression Analysis (dual-database harmonized covariates).xlsx"
  ),
  "multivariate_harmonized"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S7-MIMIC. Multivariable Regression Analysis harmonized.xlsx"
  ),
  "multivariate_harmonized"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S7-MIMIC. Final multivariable model.xlsx"
  ),
  "multivariate_harmonized"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S7-MIMIC. Final multivariable model harmonized.xlsx"
  ),
  "multivariate_harmonized"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S9-MIMIC. Logistic regression analysis of De Ritis and Rheumatoid Arthritis - binary (GLM, RCS cutoff groups).xlsx"
  ),
  "rcs_logistic"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S-XX-MIMIC. Logistic regression of De Ritis RCS cutoff.xlsx"
  ),
  "rcs_logistic"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S4-MIMIC. Multicollinearity Analysis VIF screen.xlsx"
  ),
  "vif_screen"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S6-MIMIC. Multicollinearity Analysis VIF final.xlsx"
  ),
  "vif_final"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S1-MIMIC. Baseline characteristics before and after imputation.xlsx"
  ),
  "imputation"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S8-MIMIC. Associations of De Ritis with laboratory indicators.xlsx"
  ),
  "lab_assoc"
))
stopifnot(identical(
  incidence_batch_classify_dual_supp_table(
    "Table S9-MIMIC. Mediation analysis of De Ritis.xlsx"
  ),
  "mediation"
))

if (requireNamespace("openxlsx", quietly = TRUE)) {
  tmpc <- tempfile("compact"); dir.create(tmpc)
  for (nm in c(
    "Table S1-MIMIC. A.xlsx",
    "Table S2-MIMIC. B.xlsx",
    "Table S4-MIMIC. C.xlsx",
    "Table S10-MIMIC. D.xlsx"
  )) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Sheet1")
    openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
    openxlsx::saveWorkbook(wb, file.path(tmpc, nm), overwrite = TRUE)
  }
  incidence_batch_compact_supp_s_numbers(tmpc, list())
  stopifnot(file.exists(file.path(tmpc, "Table S3-MIMIC. C.xlsx")))
  stopifnot(file.exists(file.path(tmpc, "Table S4-MIMIC. D.xlsx")))
  stopifnot(!file.exists(file.path(tmpc, "Table S4-MIMIC. C.xlsx")))
  stopifnot(!file.exists(file.path(tmpc, "Table S10-MIMIC. D.xlsx")))
  unlink(tmpc, recursive = TRUE)

  # 双库根目录：同一角色两库共用 S 号（不得压成 S1…S4 一库一号）
  tmpd <- tempfile("compact_dual"); dir.create(tmpd)
  for (nm in c(
    "Table S1-eICU. Baseline characteristics before and after imputation.xlsx",
    "Table S2-MIMIC. Baseline characteristics before and after imputation.xlsx",
    "Table S3-eICU. Normality test results for continuous variables.xlsx",
    "Table S4-MIMIC. Normality test results for continuous variables.xlsx"
  )) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Sheet1")
    openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
    openxlsx::saveWorkbook(wb, file.path(tmpd, nm), overwrite = TRUE)
  }
  incidence_batch_compact_supp_s_numbers(tmpd, list())
  stopifnot(file.exists(file.path(
    tmpd, "Table S1-eICU. Baseline characteristics before and after imputation.xlsx"
  )))
  stopifnot(file.exists(file.path(
    tmpd, "Table S1-MIMIC. Baseline characteristics before and after imputation.xlsx"
  )))
  stopifnot(file.exists(file.path(
    tmpd, "Table S2-eICU. Normality test results for continuous variables.xlsx"
  )))
  stopifnot(file.exists(file.path(
    tmpd, "Table S2-MIMIC. Normality test results for continuous variables.xlsx"
  )))
  stopifnot(!file.exists(file.path(
    tmpd, "Table S2-MIMIC. Baseline characteristics before and after imputation.xlsx"
  )))
  stopifnot(!file.exists(file.path(
    tmpd, "Table S3-eICU. Normality test results for continuous variables.xlsx"
  )))
  stopifnot(!any(grepl("^Table S[34]-", list.files(tmpd))))
  unlink(tmpd, recursive = TRUE)

  tmp <- tempfile("sxx"); dir.create(tmp)
  old_f <- file.path(
    tmp,
    "Table S9-MIMIC. Logistic regression analysis of De Ritis and Rheumatoid Arthritis - binary (GLM, RCS cutoff groups).xlsx"
  )
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", data.frame(x = 1))
  openxlsx::saveWorkbook(wb, old_f, overwrite = TRUE)
  incidence_batch_rename_rcs_tables_to_sxx(tmp, list())
  stopifnot(file.exists(file.path(
    tmp,
    "Table S-XX-MIMIC. Logistic regression analysis of De Ritis and Rheumatoid Arthritis - binary (GLM, RCS cutoff groups).xlsx"
  )))
  incidence_batch_shorten_pub_table_names(tmp, list(incidence = list(index_var = "De_Ritis")))
  sxx <- list.files(tmp, pattern = "^Table S-XX")
  stopifnot(length(sxx) == 1L)
  stopifnot(!grepl("\\(", sxx, fixed = TRUE))
  stopifnot(nchar(sxx, type = "chars") <= pub_table_max_filename_n())
  stopifnot(grepl("RCS cutoff", sxx, ignore.case = TRUE))
  unlink(tmp, recursive = TRUE)

  tmp2 <- tempfile("curate"); dir.create(tmp2)
  for (nm in c(
    "Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx",
    "Table S2-MIMIC. Normality test results for continuous variables (n=262).xlsx",
    "Table S3-MIMIC. ROC Multivariable NLR.xlsx",
    "Table S4-MIMIC. Univariate Regression Analysis.xlsx",
    "Table S5-MIMIC. Multicollinearity Analysis (VIF, univariate p 0.1 screen).xlsx",
    "Table S6-MIMIC. Multivariable Regression Analysis.xlsx",
    "Table S7-MIMIC. Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx",
    "Table S8-MIMIC. Multivariable Regression Analysis.xlsx",
    "Table S9-MIMIC. The associations between De Ritis and laboratory indicators.xlsx",
    "Table S10-MIMIC. Analysis of the mediation by laboratory indicators of the associations of De Ritis.xlsx",
    "Table 2-MIMIC. Logistic regression analysis of De Ritis and Rheumatoid Arthritis - quartile (GLM).xlsx"
  )) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Sheet1")
    openxlsx::writeData(wb, "Sheet1", nm)
    openxlsx::saveWorkbook(wb, file.path(tmp2, nm), overwrite = TRUE)
  }
  cfg_ix <- list(incidence = list(index_var = "De_Ritis"))
  incidence_batch_purge_aggregate_roc_tables(tmp2)
  incidence_batch_compact_supp_s_numbers(tmp2, cfg_ix)
  incidence_batch_shorten_pub_table_names(tmp2, cfg_ix)
  stopifnot(!any(grepl("ROC", list.files(tmp2), ignore.case = TRUE)))
  stopifnot(file.exists(file.path(tmp2, "Table S3-MIMIC. Univariate Regression Analysis.xlsx")))
  stopifnot(file.exists(file.path(tmp2, "Table S4-MIMIC. Multicollinearity Analysis VIF screen.xlsx")))
  stopifnot(file.exists(file.path(tmp2, "Table S9-MIMIC. Mediation analysis of De Ritis.xlsx")))
  stopifnot(file.exists(file.path(tmp2, "Table 2-MIMIC. Logistic regression of De Ritis quartile.xlsx")))
  bns <- list.files(tmp2, pattern = "\\.xlsx$")
  stopifnot(!any(grepl("\\(", bns)))
  stopifnot(all(nchar(bns, type = "chars") <= pub_table_max_filename_n()))
  t2 <- file.path(tmp2, "Table 2-MIMIC. Logistic regression of De Ritis quartile.xlsx")
  wb2 <- openxlsx::loadWorkbook(t2)
  title2 <- as.character(openxlsx::read.xlsx(wb2, sheet = 1, colNames = FALSE, rows = 1)[1, 1])
  stopifnot(identical(title2, tools::file_path_sans_ext(basename(t2))))
  unlink(tmp2, recursive = TRUE)
}

cat("OK locked_multivariable\n")
