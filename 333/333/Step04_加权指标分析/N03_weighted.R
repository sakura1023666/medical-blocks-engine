rm(list = ls()); gc()
################################################################################
# N03_weighted.R —— Step04 加权指标分析: Barrat 强度 + Onnela 加权(聚类系数)
# 输入: ../Step02/core_<cohort>.RData (W = net$graph 偏相关边权) + ../Step03/Table2_<coh>_centrality.csv
# 加权指标(igraph transitivity, 以 |边权| 为权重):
#   Barrat = transitivity(type="barrat")    (Barrat 2004 加权聚类系数)
#   Onnela = transitivity(type="weighted")  (Onnela 2005 加权聚类系数)
#   两者把"边权大小"纳入, 是 Strength 的有效补充; 两项均高 = 节点既连接多(邻居互联)又连接强.
#   注: 不用 igraph strength()(=Σ|w|, 与 Step03 Strength 重复), 用加权聚类系数才互补.
# 输出: Table2_<cohort>_centrality.{csv/xlsx}(Step03 中心性表 + Barrat/Onnela 两列) -> Step04/
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(igraph); library(openxlsx) })
STEP02 <- normalizePath(file.path(dirname(getwd()), "Step02"), mustWork = FALSE)
STEP03 <- normalizePath(file.path(dirname(getwd()), "Step03"), mustWork = FALSE)
COHORTS <- c("CHARLS","ELSA")

write_table <- function(df, stem) {
  wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
  hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border="bottom")
  writeData(wb, 1, df, startRow=1, colNames=TRUE, headerStyle=hs); setColWidths(wb, 1, cols=1:ncol(df), widths="auto")
  saveWorkbook(wb, paste0(stem, ".xlsx"), overwrite=TRUE); write.csv(df, paste0(stem, ".csv"), row.names=FALSE)
  cat("  [表]", stem, "\n")
}

for (coh in COHORTS) {
  cat("\n==================== ", coh, " ====================\n")
  load(file.path(STEP02, paste0("core_EBIC_", coh, ".RData")))   # -> L, net, r2 (EBIC稀疏)
  W  <- net$graph; nm <- L$Label
  g  <- graph_from_adjacency_matrix(abs(W), mode = "undirected", weighted = TRUE, diag = FALSE)
  barrat <- transitivity(g, type = "barrat",   weights = E(g)$weight)
  onnela <- transitivity(g, type = "weighted", weights = E(g)$weight)

  t3 <- read.csv(file.path(STEP03, paste0("Table2_", coh, "_centrality.csv")), check.names = FALSE)
  t3$Barrat <- round(barrat[match(t3$Label, nm)], 3)
  t3$Onnela <- round(onnela[match(t3$Label, nm)], 3)
  write_table(t3, paste0("Table2_", coh, "_centrality"))
  cat("  Barrat 最高:", nm[which.max(barrat)], "(", round(max(barrat, na.rm=TRUE), 3), ")",
      "| Onnela 最高:", nm[which.max(onnela)], "(", round(max(onnela, na.rm=TRUE), 3), ")\n")
}
cat("\n==================== Step04 加权指标完成 ====================\n")
