#!/usr/bin/env Rscript
# GBMTM 核心单元冒烟测试：合成双指标 3 时点数据（真值 K=3），
# 验证：EM 收敛、无退化类、选择 K、多数一致率、升序命名表。
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/gbmtm_core.R"))

set.seed(123)
n <- 900; truek <- 3
pi0 <- c(0.45, 0.35, 0.20)
cls <- sample.int(truek, n, TRUE, pi0)
shape <- list(
  TyG = rbind(c(-0.6,  0.0, 0.0), c(0.2, 0.7, -0.3), c(0.9, -0.5, 0.2)),
  BMI = rbind(c( 0.7, -0.1, 0.0), c(0.1, 0.4, -0.2), c(-0.8, 0.6, -0.1))
)
tm <- c(0, 0.5, 1)
mk <- function(ind) {
  m <- matrix(NA_real_, n, 3)
  for (k in 1:truek) {
    idx <- which(cls == k); b <- shape[[ind]][k, ]
    m[idx, ] <- matrix(b[1] + b[2] * tm + b[3] * tm^2, length(idx), 3, byrow = TRUE) +
      matrix(rnorm(length(idx) * 3, 0, 0.5), length(idx), 3)
  }
  m
}
tg <- mk("TyG"); bm <- mk("BMI")
# 10% MCAR 缺失
long <- data.frame(
  id = rep(seq_len(n), each = 6),
  t  = rep(rep(c(2, 4, 6), 2), times = n),
  ind = rep(c("TyG", "BMI"), each = 3, times = n),
  y = as.vector(t(cbind(as.vector(t(tg)), as.vector(t(bm)))))
)
# 重新正确组装：每人 TyG 3 点 + BMI 3 点
vals <- numeric(n * 6); ids <- integer(n * 6); ts <- numeric(n * 6); inds <- character(n * 6)
p <- 0
for (i in seq_len(n)) {
  vals[p + 1:3] <- tg[i, ]; vals[p + 4:6] <- bm[i, ]
  ids[p + 1:6] <- i; ts[p + 1:6] <- c(2, 4, 6, 2, 4, 6)
  inds[p + 1:6] <- c("TyG", "TyG", "TyG", "BMI", "BMI", "BMI")
  p <- p + 6
}
long <- data.frame(id = ids, t = ts, ind = inds, y = vals)
na_rows <- sample(nrow(long), floor(nrow(long) * 0.10))
long$y[na_rows] <- NA_real_

d <- gbmtm_to_long(long)
stopifnot(all(c("z", "t_norm") %in% names(d)), !any(is.na(d$z)))

fit1 <- gbmtm_fit(d, k = 3, deg = 1, n_start = 3, seed = 7L)
stopifnot(inherits(fit1, "gbmtm"), is.finite(fit1$LL), fit1$converged,
          fit1$min_prop >= 0.05, length(fit1$class_map) == length(unique(d$id)))

sel <- gbmtm_select(d, k_range = 2:4, deg = 1, n_start = 3, seed = 7L)
print(sel$table)
stopifnot(all(sel$table$converged))
stopifnot(sel$K_opt %in% 2:4)
f3 <- sel$fits[[which(sel$table$K == 3)]]
mcls <- f3$class_map[as.character(long$id[seq(1, length(ids), 6)])]
perms <- list(c(1,2,3), c(1,3,2), c(2,1,3), c(2,3,1), c(3,1,2), c(3,2,1))
best <- max(vapply(perms, function(pm) mean(unname(mcls) == pm[cls]), numeric(1)))
cat(sprintf("K=3 majority agreement = %.3f\n", best))
stopifnot(best >= 0.80)

lab <- gbmtm_label(f3)
stopifnot(nrow(lab) == 3, all(c("label", "n", "prop") %in% names(lab)),
          sum(lab$n) == n, all(lab$label == paste0("T", 1:3)))
cat("GBMTM UNIT TEST PASS\n")
