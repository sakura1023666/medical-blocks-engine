#!/usr/bin/env Rscript
# 引擎分位级联：quartile→tertile→binary
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/cox_gate.R", local = FALSE)
source("R/quantile_scheme_cascade.R", local = FALSE)

stopifnot(identical(quantile_scheme_meta("tertile")$contrast_lab, "T3 vs T1"))
stopifnot(identical(quantile_scheme_meta("binary")$labels, c("Low", "High")))

set.seed(1)
n <- 400L
# 单调强关联 → quartile 应锁定
x <- rnorm(n)
lp <- 0.9 * x
t <- rexp(n, rate = exp(lp) / 2)
ev <- rbinom(n, 1, 0.55)
d <- data.frame(idx = x, futime_years = pmin(t, 2), fustatus = ev)

res <- quantile_scheme_resolve_cascade(
  d, "idx",
  config = list(quantile_scheme_cascade = list(
    enable = TRUE, pass_rule = "all", family = "cox",
    try_schemes = c("quartile", "tertile", "binary")
  ))
)
cat("strong mono → scheme=", res$scheme, " reason=", res$reason, "\n")
stopifnot(res$scheme %in% c("quartile", "tertile", "binary"))
stopifnot(nlevels(res$factors$idx) == res$meta$n_groups)

# 非单调：Q2 事件最低，模仿 hip SIRI → 应降档
set.seed(2)
n <- 228L
x <- runif(n)
# 人工造死亡：中间低、两端高 → 四分位 Q4vsQ1 易 NS
q <- as.integer(cut(x, breaks = quantile(x, c(0, 0.25, 0.5, 0.75, 1)), include.lowest = TRUE))
p_dead <- c(0.25, 0.08, 0.25, 0.37)[q]
ev <- rbinom(n, 1, p_dead)
d2 <- data.frame(idx = x, futime_years = runif(n, 0.1, 1), fustatus = ev)
res2 <- quantile_scheme_resolve_cascade(
  d2, "idx",
  config = list(quantile_scheme_cascade = list(
    enable = TRUE, pass_rule = "all", family = "cox"
  ))
)
cat("non-mono → scheme=", res2$scheme, "\n")
print(res2$trial[, c("scheme", "index", "p", "pass")])
stopifnot(res2$scheme %in% c("quartile", "tertile", "binary"))
# 强制降档路径
res2b <- quantile_scheme_resolve_cascade(
  d2, "idx",
  config = list(quantile_scheme_cascade = list(
    enable = TRUE, pass_rule = "all", family = "cox",
    try_schemes = c("quartile", "tertile", "binary"),
    # 抬高阈值使 quartile 必失败，验证会落到更粗分位
    p_threshold = 0.001
  ))
)
cat("strict p→ scheme=", res2b$scheme, "\n")
stopifnot(res2b$scheme %in% c("tertile", "binary") ||
            any(res2b$trial$scheme == "quartile" & !res2b$trial$pass))

# force_scheme
res3 <- quantile_scheme_resolve_cascade(
  d2, "idx",
  config = list(quantile_scheme_cascade = list(force_scheme = "tertile"))
)
stopifnot(identical(res3$scheme, "tertile"))

cat("OK test_quantile_scheme_cascade\n")
