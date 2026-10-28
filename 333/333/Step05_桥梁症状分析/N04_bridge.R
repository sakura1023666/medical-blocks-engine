rm(list = ls()); gc()
################################################################################
# N04_bridge.R —— Step05 桥梁症状分析 (Bridge Centrality) + Fig.3
# 输入: ../Step02_网络构建/core_EBIC_<cohort>.RData (net$graph = EBIC 偏相关边权, L$Label/Items/ndep/nmets)
# 双社区: Depression(8 抑郁条目) <-> MetS(5 组分); 桥节点 = 连接两社区的关键症状.
# 指标: Bridge Strength / Closeness / Expected Influence(1-step) (表内另附 Betweenness), 均 z 标准化.
# 注: EBIC 稀疏图下, 节点与对侧社区完全无路径时 Closeness/Betweenness 返回 NaN → 表中留空(NA),
#     图中该点缺省(折线在此断开), 并在日志列出.
# 输出: Fig3_<cohort>_bridge.{pdf/svg/png}  +  Bridge_<cohort>.{csv/xlsx}  +  bridge_<cohort>.RData
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(qgraph); library(networktools); library(ggplot2); library(openxlsx) })

Step02_网络构建 <- normalizePath(file.path(dirname(getwd()), "Step02_网络构建"), mustWork = FALSE)
COHORTS <- c("CHARLS","ELSA")
# 本网络内 z 标准化(与 Step03 同); NaN/NA 输入保留为 NA
zscore <- function(x) { x <- as.numeric(x); s <- sd(x, na.rm=TRUE)
  if (is.na(s)||s==0) rep(0,length(x)) else { z <- (x-mean(x,na.rm=TRUE))/s; z[!is.finite(z)] <- NA_real_; z } }

save_plot <- function(stem, plotfun, width=12, height=6, res=300) {
  cairo_pdf(paste0(stem,".pdf"), width=width, height=height, family="sans"); plotfun(); dev.off()
  # svg(paste0(stem,".svg"),       width=width, height=height); plotfun(); dev.off()
  # png(paste0(stem,".png"),       width=width, height=height, units="in", res=res); plotfun(); dev.off()
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
  cat("\n==================== ", coh, " 桥症状分析 ====================\n")
  load(file.path(Step02_网络构建, paste0("core_EBIC_", coh, ".RData")))   # -> L, net, r2
  nm <- L$Label; items <- L$Items
  W  <- net$graph
  comm <- c(rep("Depression", L$ndep), rep("MetS", L$nmets))

  G  <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
  br <- networktools::bridge(G, communities = comm, useCommunities = "all")

  bstr <- as.numeric(br$`Bridge Strength`)
  be1  <- as.numeric(br$`Bridge Expected Influence (1-step)`)
  bcl  <- as.numeric(br$`Bridge Closeness`)
  btw  <- as.numeric(br$`Bridge Betweenness`)
  no_path <- nm[is.na(bcl)]                                  # 与对侧社区无路径 → Closeness/Betweenness 留空
  if (length(no_path) > 0) cat("  无桥接路径(Closeness/Betweenness 留空):", paste(no_path, collapse=", "), "\n")

  bridge_tab <- data.frame(
    Label = nm, Items = items, Community = comm,
    Bridge_Strength           = round(zscore(bstr), 3),
    Bridge_ExpectedInfluence  = round(zscore(be1),  3),
    Bridge_Closeness          = round(zscore(bcl),  3),
    Bridge_Betweenness        = round(zscore(btw),  3),
    stringsAsFactors = FALSE, check.names = FALSE)
  
  # ================= 新增：将所有 NA 填补为 0 =================
  bridge_tab$Bridge_Closeness[is.na(bridge_tab$Bridge_Closeness)] <- 0
  bridge_tab$Bridge_Betweenness[is.na(bridge_tab$Bridge_Betweenness)] <- 0
  # ============================================================
  
  # 节点固定 Table 2 行序: Depression_1..8, MetS_1..5 (而非按桥指标降序)
  bridge_tab$Label <- factor(bridge_tab$Label, levels = nm)
  bridge_tab <- bridge_tab[order(bridge_tab$Label), ]
  bridge_tab$Label <- as.character(bridge_tab$Label)
  print(bridge_tab)
  write_table(bridge_tab, paste0("Bridge_", coh))
  cat("  Top 桥节点(Bridge EI z 最高):",
      paste(head(bridge_tab$Label[order(bridge_tab$Bridge_ExpectedInfluence, decreasing=TRUE, na.last=NA)], 5), collapse=", "), "\n")

  # ---- Fig.3: 桥症状 3 分面, 直接按桥表 z 值画, 节点固定 Table 2 行序 ----
  # 图值 = 桥表(Bridge_<coh>) 的 z 分数值; 节点顺序 = Table 2 行序(Depression_1 顶 → MetS_5 底), 3 分面共用;
  # 折线沿行序连点 (geom_path); 保留 x=0 零线 (z 下 0 有意义). theme_bw, 无标题 (与 Fig.2 风格一致).
  save_plot(paste0("Fig3_", coh, "_bridge"), function() {
    measures <- c("Bridge Closeness", "Bridge Expected Influence (1-step)", "Bridge Strength")
    cols <- list(bridge_tab$Bridge_Closeness, bridge_tab$Bridge_ExpectedInfluence, bridge_tab$Bridge_Strength)
    long <- do.call(rbind, lapply(seq_along(measures), function(i)
      data.frame(measure = measures[[i]], value = cols[[i]], Label = bridge_tab$Label, stringsAsFactors = FALSE)))
    long$measure <- factor(long$measure, levels = measures)
    long$Label   <- factor(long$Label, levels = rev(nm))     # Table 2 行序: Depression_1 顶部 → MetS_5 底部
    long         <- long[order(long$measure, long$Label), ]  # 按 Label 重排 → 折线沿 Table 2 行序连接
    g <- ggplot2::ggplot(long, ggplot2::aes(x = value, y = Label)) +
      ggplot2::geom_path(ggplot2::aes(group = measure)) +    # 各分面沿 Table 2 行序连点
      ggplot2::geom_point() +
      # ggplot2::geom_vline(xintercept = 0, colour = "grey50") +  # ← 就是这一行，已经注释/删除了！
      ggplot2::facet_wrap(~ measure, nrow = 1, scales = "free_x") +
      ggplot2::labs(x = "z-score", y = NULL) +
      ggplot2::theme_bw(base_size = 11)
    print(g)
  })

  # save(bridge_tab, file = paste0("bridge_", coh, ".RData"))
}
cat("\n==================== Step05 桥症状分析完成 ====================\n")
