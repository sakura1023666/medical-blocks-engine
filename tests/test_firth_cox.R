#!/usr/bin/env Rscript
# tests/test_firth_cox.R — R/firth_cox.R 数值回归（SOSM 2026-09 沉淀）
# 用法: Rscript tests/test_firth_cox.R   （引擎根目录）
# 校验一维 Firth 罚 Cox 与已发表数字一致：(0,6] HR≈35.3 p≈0.019；(6,28] HR≈2.74。
# 无 SOSM 结果目录时自动 SKIP（不算失败）。

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), ".."), winslash = "/", mustWork = FALSE)
source(file.path(root, "R/firth_cox.R"))

sosm <- "/mnt/g/DockerHome/5006/medical-blocks-studies/02_fuzhumailiu/tr/by_index/【success】SOSM"
rd <- file.path(sosm, "mimic/step14_trajectory_jlcm/Data/D01_jlcm_SOSM_models.RData")
if (!file.exists(rd)) { cat("SKIP: SOSM models not found\n"); quit(status = 0) }

suppressPackageStartupMessages(library(lcmm))
e <- new.env(); load(rd, envir = e)
m2 <- e$models_list_with_cov$m2
dat <- e$model_data_final
pp <- m2$pprob
asg <- data.frame(subject_id_num = pp$subject_id_num,
                  class = ifelse(pp$probYT1 >= 0.5, 1L, 2L))
su <- aggregate(cbind(surv_time, surv_event) ~ subject_id_num, data = dat, FUN = function(z) z[1])
dd <- merge(su, asg, by = "subject_id_num")
dd$event <- as.integer(dd$surv_event); dd$time <- as.numeric(dd$surv_time)
x <- as.integer(dd$class == 1)

r1 <- firth_cox1d(pmin(dd$time, 6), as.integer(dd$event == 1 & dd$time <= 6), x)
stopifnot(r1$converged, abs(r1$HR - 35.28) < 1, abs(r1$p - 0.019) < 0.005)
k <- dd$time > 6
r2 <- firth_cox1d(pmin(dd$time[k], 28) - 6,
                  as.integer(dd$event[k] == 1 & dd$time[k] <= 28), x[k])
stopifnot(r2$converged, abs(r2$HR - 2.74) < 0.1, abs(r2$p - 0.0145) < 0.005)
pw <- firth_cox_piecewise(pmin(dd$time, 6), as.integer(dd$event == 1 & dd$time <= 6),
                          dd$class, ref = "2")
stopifnot(nrow(pw) == 1L, pw$method == "firth")
cat("PASS: firth_cox1d / firth_cox_piecewise match SOSM reference values\n")
