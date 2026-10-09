# tests/test_univariate_binary_or_display.R
# numeric 0/1 二元变量：glm 系数名与发表表 OR 行匹配
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/univariate_or_helpers.R"), local = FALSE)

set.seed(42)
n <- 400
df <- data.frame(
  outcome = rbinom(n, 1, 0.2),
  Preop_Dm = rbinom(n, 1, 0.11),
  Gender = sample(c("F", "M"), n, replace = TRUE),
  stringsAsFactors = FALSE
)

# numeric 0/1 → factor，系数名为 Preop_Dm1
x <- univar_coerce_binary_predictor(df$Preop_Dm)
stopifnot(is.factor(x), identical(levels(x), c("0", "1")))
fit <- glm(outcome ~ Preop_Dm, data = transform(df, Preop_Dm = x), family = binomial)
coef_nm <- rownames(summary(fit)$coefficients)
stopifnot("Preop_Dm1" %in% coef_nm)

sub_u <- data.frame(
  Variable = coef_nm[coef_nm != "(Intercept)"],
  OR = exp(coef(fit)[coef_nm != "(Intercept)"]),
  CI_lo = 0.5, CI_hi = 2.0, P = 0.01,
  stringsAsFactors = FALSE
)
mr <- univar_match_coef_row(sub_u, "Preop_Dm", "1")
stopifnot(nrow(mr) == 1L, identical(mr$Variable[[1L]], "Preop_Dm1"))

# 未转 factor 时系数名为 Preop_Dm，匹配仍应成功
fit2 <- glm(outcome ~ Preop_Dm, data = df, family = binomial)
sub_u2 <- data.frame(
  Variable = "Preop_Dm",
  OR = exp(coef(fit2)[["Preop_Dm"]]),
  CI_lo = 0.5, CI_hi = 2.0, P = 0.02,
  stringsAsFactors = FALSE
)
mr2 <- univar_match_coef_row(sub_u2, "Preop_Dm", "1")
stopifnot(nrow(mr2) == 1L, identical(mr2$Variable[[1L]], "Preop_Dm"))

# factor 分类变量仍按 VarLevel 匹配
sub_g <- data.frame(
  Variable = "GenderM",
  OR = 1.5, CI_lo = 1.1, CI_hi = 2.0, P = 0.001,
  stringsAsFactors = FALSE
)
mr_g <- univar_match_coef_row(sub_g, "Gender", "M")
stopifnot(nrow(mr_g) == 1L)

cat("test_univariate_binary_or_display.R: OK\n")
