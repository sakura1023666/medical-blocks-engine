# test_mi_rubin_pool.R — Rubin 合并单元测试
root <- Sys.getenv("BLOCK_REPO_ROOT", "/mnt/e/01block/01Block-new-Final")
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

message("OK: test_mi_rubin_pool passed")
