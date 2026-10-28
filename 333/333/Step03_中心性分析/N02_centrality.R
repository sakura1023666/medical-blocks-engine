rm(list = ls()); gc()
################################################################################
# N02_centrality.R —— Step03 中心性分析: Strength / Closeness / Betweenness (+ EI)
# 输入: ../Step02_网络构建/core_<cohort>.RData (net$graph = 偏相关边权矩阵, L$Label, L$Items)
# 指标(用户定义):
#   Strength(强度)    = Σ|边权|(节点所有边绝对值之和)
#   Betweenness(中介) = 位于其他节点最短路径上的次数
#   Closeness(接近)   = 到各节点平均最短路径的倒数(qgraph Closeness, 差常数倍)
#   Expected Influence(EI, 补充) = Σ边权(带符号); 网络含负边时比 Strength 更合理
# z 标准化(本网络内); 值越大越核心.   输出: Fig2 + Table2 (直接放 Step03/)
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(qgraph); library(bootnet); library(ggplot2); library(tidyr); library(openxlsx) })

Step02_网络构建_DIR <- normalizePath(file.path(dirname(getwd()), "Step02_网络构建"), mustWork = FALSE)
COHORTS <- c("CHARLS","ELSA")
zscore <- function(x) { s <- sd(x, na.rm=TRUE); if (is.na(s)||s==0) rep(0,length(x)) else (x-mean(x,na.rm=TRUE))/s }
save_plot <- function(stem, plotfun, width=12, height=7, res=300) {
  cairo_pdf(paste0(stem,".pdf"), width=width, height=height, family="sans"); plotfun(); dev.off()
  # svg(paste0(stem,".svg"), width=width, height=height); plotfun(); dev.off()
  # png(paste0(stem,".png"), width=width, height=height, units="in", res=res); plotfun(); dev.off()
  cat("  [图]", stem, "\n")
}
write_table <- function(df, stem) {
  wb <- createWorkbook(); addWorksheet(wb,"Sheet1")
  hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border="bottom")
  writeData(wb, 1, df, startRow=1, colNames=TRUE, headerStyle=hs); setColWidths(wb, 1, cols=1:ncol(df), widths="auto")
  saveWorkbook(wb, paste0(stem,".xlsx"), overwrite=TRUE); write.csv(df, paste0(stem,".csv"), row.names=FALSE)
  cat("  [表]", stem, "\n")
}

for (coh in COHORTS) {
  cat("\n==================== ", coh, " ====================\n")
  load(file.path(Step02_网络构建_DIR, paste0("core_EBIC_", coh, ".RData")))   # -> L, net, r2 (EBIC稀疏, 拓扑指标有效)
  W <- net$graph; nm <- L$Label; items <- L$Items
  G <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
  c <- qgraph::centrality(G)
  Strength    <- rowSums(abs(W))                          # Σ|w|
  Closeness   <- c$Closeness
  Betweenness <- c$Betweenness
  EI          <- if (!is.null(c$ExpectedInfluence)) c$ExpectedInfluence else rowSums(W)   # Σw(带符号)

  tab <- data.frame(Label = nm, Items = items,
    Strength          = round(Strength, 3),
    Closeness         = round(Closeness, 3),
    Betweenness       = round(Betweenness, 3),
    ExpectedInfluence = round(EI, 3),
    # Strength_z        = round(zscore(Strength), 3),
    # Closeness_z       = round(zscore(Closeness), 3),
    # Betweenness_z     = round(zscore(Betweenness), 3),
    # EI_z              = round(zscore(EI), 3),
    check.names = FALSE, stringsAsFactors = FALSE)
  print(tab)
  write_table(tab, paste0("Table2_", coh, "_centrality"))

  save_plot(paste0("Fig2_", coh, "_centrality"), function() {
  # 只显示原始值，不显示标准化值
  p <- centralityPlot(G, 
                      scale = "raw",
                      standardized = FALSE,  # 关键：不显示标准化图
                      include = c("Strength", "Closeness", "Betweenness", "ExpectedInfluence"),
                      labels = nm) + 
    xlab("Centrality Value (Raw)")
  
  print(p)
})
  cat("  核心(Strength 最高):", nm[which.max(Strength)], "(", round(max(Strength),3), ")\n")
  cat("  核心(EI 最高, 含负边):", nm[which.max(EI)], "(", round(max(EI),3), ")\n")
}
cat("\n==================== Step03 中心性完成 ====================\n")
