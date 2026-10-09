# CART 交叉验证剪枝：1-SE / min 选 CP，xval=0 保持旧行为
source(file.path("R", "utils.R"), local = FALSE)
source(file.path("Blocks", "22_ml_models", "21block_cart_decision_path.R"), local = FALSE)

# 构造一张假 cptable：min xerror 在 nsplit=2，1-SE 应退回更简单的 nsplit=0
cp_tab <- data.frame(
  CP = c(0.10, 0.04, 0.01),
  nsplit = c(0, 1, 2),
  `rel error` = c(1.00, 0.80, 0.70),
  xerror = c(1.05, 0.95, 0.90),
  xstd = c(0.10, 0.08, 0.10),
  check.names = FALSE
)
pick_min <- .cdp21_pick_cp(cp_tab, "min")
stopifnot(identical(pick_min$nsplit, 2L))
pick_1se <- .cdp21_pick_cp(cp_tab, "1se")
# min xerror + 1SE = 1.00；nsplit=0 的 1.05 > 1.00，nsplit=1 的 0.95 ≤ 1.00 → 选最简单 nsplit=1
stopifnot(identical(pick_1se$nsplit, 1L))

# 拟合：xval=0 且 prune=FALSE 时不剪枝
set.seed(1)
n <- 80
dat <- data.frame(
  Group = factor(c(rep("0", 50), rep("1", 30))),
  Age = c(rnorm(50, 60, 8), rnorm(30, 72, 8)),
  BMI = c(rnorm(50, 22, 3), rnorm(30, 28, 3))
)
fit0 <- .cdp21_fit(dat, "Group", c("Age", "BMI"),
                   list(maxdepth = 3L, minsplit = 10L, minbucket = 5L, cp = 0.01,
                        xval = 0L, prune = FALSE), 1L)
stopifnot(isTRUE(fit0$ok), isFALSE(fit0$prune$applied), identical(fit0$xval, 0L))

fit1 <- .cdp21_fit(dat, "Group", c("Age", "BMI"),
                   list(maxdepth = 3L, minsplit = 10L, minbucket = 5L, cp = 0.01,
                        xval = 5L, prune = TRUE, prune_rule = "1se"), 1L)
stopifnot(isTRUE(fit1$ok), isTRUE(fit1$prune$applied), fit1$xval >= 2L)

nodes <- .cdp21_node_table(fit0$fit, leaf_labels = c("0" = "A", "1" = "B"))
er <- nodes$event_rate[is.finite(nodes$event_rate)]
stopifnot(length(er) > 0L, all(er >= 0, er <= 1))

# 分层划分可复现，且两侧都有两类
y <- c(rep("0", 70), rep("1", 30))
sp1 <- .cdp21_stratified_split(y, 0.3, 42L)
sp2 <- .cdp21_stratified_split(y, 0.3, 42L)
stopifnot(identical(sp1$test, sp2$test))
stopifnot(length(intersect(sp1$train, sp1$test)) == 0L)
stopifnot(all(c("0", "1") %in% y[sp1$train]), all(c("0", "1") %in% y[sp1$test]))

# 已知 2×2：10 阳中 8 检出，90 阴中 5 假阳
yt <- c(rep("1", 10), rep("0", 90))
pr <- c(rep("1", 8), rep("0", 2), rep("1", 5), rep("0", 85))
mm <- .cdp21_class_metrics(yt, pr)
stopifnot(abs(mm$Sensitivity - 0.8) < 1e-12, abs(mm$Specificity - 85 / 90) < 1e-12)

cat("OK test_cart_decision_path_prune\n")
