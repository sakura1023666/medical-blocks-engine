# svyglm Model3：df.residual<=0 时 Pr(>|t|) 为 NaN，OR/CI 仍用正态近似；
# 表内 P 须回退 Wald z，避免 Model3 空 P。
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
src <- file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")
stopifnot(file.exists(src))
source(src, local = FALSE)

stopifnot(exists(".lnw00_pvalue_from_coef", mode = "function"))

# 有限 Pr 原样返回
stopifnot(isTRUE(all.equal(.lnw00_pvalue_from_coef(1, 0.5, 0.042), 0.042)))

# NaN / NA → Wald z = 2 * pnorm(-|est/se|)
est <- -0.5343943
se <- 0.1232778
expect_w <- 2 * stats::pnorm(-abs(est / se))
got_nan <- .lnw00_pvalue_from_coef(est, se, NaN)
got_na <- .lnw00_pvalue_from_coef(est, se, NA_real_)
stopifnot(is.finite(got_nan), isTRUE(all.equal(got_nan, expect_w)))
stopifnot(is.finite(got_na), isTRUE(all.equal(got_na, expect_w)))

# se 无效 → 仍 NA
stopifnot(is.na(.lnw00_pvalue_from_coef(1, 0, NA_real_)))
stopifnot(is.na(.lnw00_pvalue_from_coef(1, NA_real_, NaN)))

message("OK: test_lnw00_wald_pvalue_fallback")
