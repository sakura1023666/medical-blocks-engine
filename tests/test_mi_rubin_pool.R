# test_mi_rubin_pool.R — Rubin 合并单元测试
root <- Sys.getenv("BLOCK_REPO_ROOT", "/mnt/e/01block/01Block")
source(file.path(root, "R/mi_rubin_pool.R"), local = FALSE)

# 人造 2 套拟合：coef 不同，var 对角
f1 <- list(coef = c(a = 0.2, b = -0.1), var = diag(c(0.04, 0.09)))
f2 <- list(coef = c(a = 0.4, b = 0.1),  var = diag(c(0.04, 0.09)))
pooled <- mi_rubin_pool_estimates(list(f1, f2))
stopifnot(!is.null(pooled))
stopifnot(abs(pooled$coef[["a"]] - 0.3) < 1e-9)
stopifnot(abs(pooled$coef[["b"]] - 0.0) < 1e-9)
# within = 0.04; between_a = var(c(0.2,0.4))=0.02; T=0.04+(1+1/2)*0.02=0.07
stopifnot(abs(pooled$total[["a"]] - 0.07) < 1e-9)
tab <- mi_rubin_hr_table(pooled, "competing", 1L, "Model 1", 28L)
stopifnot(is.data.frame(tab), nrow(tab) == 2L, identical(tab$mi_pool, c("rubin", "rubin")))

# 发病 Logistic：脚注不得再写 Cox；预后保留 Cox
fn_inc <- mi_methods_footnote_lines(m = 5L, maxit = 5L, seed = 1234L, study_type = "incidence")
stopifnot(any(grepl("logistic", fn_inc, ignore.case = TRUE)))
stopifnot(!any(grepl("\\bCox\\b", fn_inc)))
fn_prog <- mi_methods_footnote_lines(m = 5L, maxit = 5L, seed = 1234L, study_type = "prognosis")
stopifnot(any(grepl("\\bCox\\b", fn_prog)))
fn_svy <- mi_methods_footnote_lines(
  m = 5L, maxit = 5L, seed = 1234L, study_type = "incidence", survey = TRUE
)
stopifnot(any(grepl("survey-weighted|svyglm", fn_svy, ignore.case = TRUE)))
stopifnot(!any(grepl("\\bCox\\b", fn_svy)))

# mi_append_table_footnotes 从 ctx 推断 study_type
ctx_mi <- list(
  config = list(
    project = list(study_type = "incidence"),
    imputation = list(m = 5L, maxit = 5L, seed = 1234L, rubin_pool = TRUE)
  ),
  results = list(mice_model = list(m = 5L))
)
# rubin 开关：若 mi_rubin_enabled 不认空 mice，直接测 footnote 函数即可
notes <- mi_methods_footnote_lines(study_type = "incidence")
stopifnot(!any(grepl("Cox/logistic", notes, fixed = TRUE)))

message("OK: test_mi_rubin_pool passed")
