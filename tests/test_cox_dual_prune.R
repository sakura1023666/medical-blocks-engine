root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/model3_required.R"), local = FALSE)
source(file.path(root, "R/cox_gate.R"), local = FALSE)

stopifnot(identical(
  cox_dual_order_extras_for_prune(c("SOFA", "AnionGap", "GCS")),
  c("AnionGap", "SOFA", "GCS")
))

set.seed(20260820)
.sim_one <- function(n) {
  Age <- rnorm(n, 65, 12)
  u <- rnorm(n)
  SOFA <- pmax(0, 4 + 2 * u)
  Gender <- factor(sample(c("Female", "Male"), n, TRUE))
  APRI <- pmax(0.05, 0.8 + 0.6 * u + rnorm(n, 0, 0.05))
  qs <- as.numeric(quantile(APRI, na.rm = TRUE))
  Group <- cut(APRI, breaks = qs, include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4"))
  lp <- 0.35 * as.numeric(Group == "Q4") + 0.55 * SOFA + 0.01 * Age
  time <- pmin(rexp(n, rate = exp(lp - 4)), 30)
  event <- as.numeric(time < 30)
  data.frame(Age, SOFA, Gender, APRI, Group, futime = time, fustatus = event)
}

mk_prep <- function(df) {
  df$Group <- droplevels(factor(df$Group, levels = c("Q1", "Q2", "Q3", "Q4")))
  list(dt = df, time_var = "futime", event_var = "fustatus", target = "Q4")
}

d1 <- .sim_one(900)
d2 <- .sim_one(900)
prepared <- list(nhanes = mk_prep(d1), mimic = mk_prep(d2))
cfg <- list(analysis_models = list(model3_required_factors = "Gender"))

prepared$nhanes$dt$AnionGap <- rnorm(nrow(prepared$nhanes$dt))
prepared$mimic$dt$AnionGap <- rnorm(nrow(prepared$mimic$dt))

p_full_1 <- cox_highest_group_p_for_covs(prepared$nhanes, c("Age", "SOFA"))
stopifnot(is.finite(p_full_1), p_full_1 >= 0.05)

pr <- cox_prune_dual_highest_group(
  prepared, "Age", c("Age", "AnionGap", "SOFA"), cfg, "APRI",
  p_threshold = 0.05, require_trend = FALSE
)
stopifnot("Age" %in% pr$M1)
stopifnot(isTRUE(pr$pruned), "SOFA" %in% pr$dropped, "AnionGap" %in% pr$M2)

pr_none <- cox_prune_dual_highest_group(
  prepared, "Age", "Age", cfg, "APRI", p_threshold = 0.05
)
stopifnot(identical(pr_none$reason, "no_extras"))

cat("test_cox_dual_prune: OK\n")
