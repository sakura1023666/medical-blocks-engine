################################################################################
# N04_stability_accuracy.R  ——  稳定性(CS 系数) + 准确性(边权重 95%CI) + 差异检验
# 依赖: N01 产出的 output/core_<COHORT>.RData
# 论文步骤: §1.3 第8步(CS 稳定性) + 第9步(边权重 CI) + 第10步(差异检验) + Fig.5 + Suppl.3-4
# ⚠️ 最耗时段落: 每次 bootstrap 都重估 EBICglasso+Pearson(_00_config.R 的 net_estimator); FAST 模式分钟级, FULL 模式数小时
################################################################################
rm(list = ls()); gc()
{
  fa <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(fa)) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
}
COHORTS <- c("CHARLS","ELSA")
Step02_网络构建 <- normalizePath(file.path(dirname(getwd()), "Step02_网络构建"), mustWork = FALSE)

suppressPackageStartupMessages({ library(bootnet); library(qgraph) })

source(file.path(dirname(getwd()), "网络分析", "_00_config.R"), chdir = TRUE)

for (coh in COHORTS) {
  cat("\n==================== ", coh, " 稳定性/准确性 ====================\n")
  load(file.path(Step02_网络构建, paste0("core_EBIC_", coh, ".RData")))   # -> L, net, r2
  
  # net  <- core$net_full
  # info <- core$info

  # ---- 非参数 bootstrap: 边权重 + 中心性 准确性 (Fig.5B / Suppl.3-4 差异检验) ----
  cat("  非参数 bootstrap (nBoots =", NBOOTS_PARAM, ")...\n")
  boot_param <- bootnet(net,
                        statistics = c("edge", "strength", "closeness", "betweenness", "expectedInfluence"),
                        nBoots = NBOOTS_PARAM, nCores = NCORES, type = "nonparametric")

  # ---- case-dropping bootstrap: 中心性稳定性 CS 系数 (Fig.5A) ----
  cat("  case-dropping bootstrap (nBoots =", NBOOTS_CASE, ")...\n")
  boot_case <- bootnet(net,
                       statistics = c("strength", "closeness", "betweenness", "expectedInfluence"),
                       nBoots = NBOOTS_CASE, nCores = NCORES, type = "case")
  cs <- corStability(boot_case)
  cat("  CS 系数 (≥0.25 稳定, ≥0.5 理想):\n"); print(round(cs, 3))
  cs_df <- data.frame(Statistic = names(cs), CS_coefficient = round(unname(cs), 3),
                      Stable = ifelse(cs >= 0.25, "yes", "NO (<0.25)"),
                      stringsAsFactors = FALSE)
  write_table(cs_df, paste0("CS_", coh))

  # ---- Fig.5A: CS 稳定性 ----
  save_plot(paste0("Fig5A_", coh, "_stability"), function() {
    print(plot(boot_case, statistics = c("strength", "closeness", "betweenness", "expectedInfluence")))
  }, width = 9, height = 6)

  # ---- Fig.5B: 边权重 bootstrap 95%CI (order=sample 从正到负排列) ----
  save_plot(paste0("Fig5B_", coh, "_edgeweight_CI"), function() {
    print(plot(boot_param, labels = FALSE, order = "sample", statistics = "edge"))
  }, width = 10, height = 8)

  # ---- Suppl.3: 边权重差异检验 (onlyNonZero 去掉 0 边) ----
  save_plot(paste0("Suppl3_", coh, "_edge_diff"), function() {
    print(plot(boot_param, "edge", plot = "difference", onlyNonZero = TRUE, order = "sample"))
  }, width = 12, height = 12)

  # ---- Suppl.4: 中心性(强度)差异检验 ----
  save_plot(paste0("Suppl4_", coh, "_strength_diff"), function() {
    print(plot(boot_param, "strength", plot = "difference"))
  }, width = 10, height = 9)

  save(boot_param, boot_case, cs, file = file.path(OUT_DIR, paste0("boot_", coh, ".RData")))
  cat("  已保存 boot_", coh, ".RData\n", sep = "")
}

cat("\n==================== N04 完成 ====================\n")
