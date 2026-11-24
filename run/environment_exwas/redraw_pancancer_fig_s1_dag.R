#!/usr/bin/env Rscript
# Figure S1：对齐 Dong Supp Fig1 画风（实心黑点 + 旁注标签 + 细黑箭头）
# 节点仅最终 Model2：Gender, Race, PIR, Alcohol, eGFR + Toxicants + Pan-cancer
#
#   Rscript redraw_pancancer_fig_s1_dag.R
#
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages(library(ggplot2))

# 布局：暴露偏上、结局居中偏右、协变量环绕（仿原文疏密）
nodes <- data.frame(
  id = c("Gender", "Race", "PIR", "Alcohol", "eGFR", "Toxicants", "Cancer"),
  label = c(
    "Gender", "Race", "Poverty", "Alcohol use", "eGFR",
    "Environmental Toxicants", "Pan-cancer"
  ),
  x = c(0.12, 0.12, 0.22, 0.38, 0.88, 0.48, 0.58),
  y = c(0.82, 0.48, 0.18, 0.12, 0.55, 0.78, 0.48),
  # 标签相对圆点的偏移（npc）
  lx = c(-0.02, -0.02, 0.00, 0.00, 0.06, 0.00, 0.00),
  ly = c(0.07, 0.07, -0.07, -0.07, 0.00, 0.08, -0.08),
  stringsAsFactors = FALSE
)

edges <- rbind(
  data.frame(from = "Gender", to = "Toxicants"),
  data.frame(from = "Gender", to = "Cancer"),
  data.frame(from = "Race", to = "Toxicants"),
  data.frame(from = "Race", to = "Cancer"),
  data.frame(from = "PIR", to = "Toxicants"),
  data.frame(from = "PIR", to = "Cancer"),
  data.frame(from = "PIR", to = "Alcohol"),
  data.frame(from = "Alcohol", to = "Cancer"),
  data.frame(from = "eGFR", to = "Cancer"),
  data.frame(from = "Toxicants", to = "Cancer"),
  data.frame(from = "Toxicants", to = "eGFR")
)

pos <- setNames(lapply(seq_len(nrow(nodes)), function(i) c(nodes$x[i], nodes$y[i])), nodes$id)
ed <- edges
ed$x <- vapply(ed$from, function(z) pos[[z]][1], numeric(1))
ed$y <- vapply(ed$from, function(z) pos[[z]][2], numeric(1))
ed$xend <- vapply(ed$to, function(z) pos[[z]][1], numeric(1))
ed$yend <- vapply(ed$to, function(z) pos[[z]][2], numeric(1))

# 箭头停在圆点边缘（圆点半径约 0.018 npc）
r_node <- 0.022
for (i in seq_len(nrow(ed))) {
  dx <- ed$xend[i] - ed$x[i]
  dy <- ed$yend[i] - ed$y[i]
  len <- sqrt(dx * dx + dy * dy)
  if (is.finite(len) && len > 1e-6) {
    ux <- dx / len
    uy <- dy / len
    ed$x[i] <- ed$x[i] + ux * r_node
    ed$y[i] <- ed$y[i] + uy * r_node
    ed$xend[i] <- ed$xend[i] - ux * r_node
    ed$yend[i] <- ed$yend[i] - uy * r_node
  }
}

nodes$tx <- nodes$x + nodes$lx
nodes$ty <- nodes$y + nodes$ly

p <- ggplot() +
  geom_segment(
    data = ed,
    aes(x = x, y = y, xend = xend, yend = yend),
    arrow = arrow(type = "closed", length = unit(0.10, "inches"), angle = 16),
    linewidth = 0.35, color = "black", lineend = "butt", linejoin = "mitre"
  ) +
  # 实心黑圆（对齐原文）
  geom_point(
    data = nodes,
    aes(x = x, y = y),
    shape = 16, size = 5.5, color = "black"
  ) +
  # 标签在圆旁，不写进圆内
  geom_text(
    data = nodes,
    aes(x = tx, y = ty, label = label),
    size = 3.6, family = "sans", color = "black",
    hjust = 0.5, vjust = 0.5
  ) +
  coord_cartesian(xlim = c(0.00, 1.00), ylim = c(0.00, 1.00), expand = FALSE) +
  theme_void() +
  theme(plot.margin = margin(8, 8, 8, 8), plot.background = element_rect(fill = "white", color = NA))

out <- file.path(fig_pdf, "Figure S1. DAG covariates.pdf")
grDevices::cairo_pdf(out, width = 9.5, height = 6.2, family = "sans")
print(p)
grDevices::dev.off()
message("wrote ", out)

writeLines(c(
  "# Figure S1. DAG covariates",
  "",
  "## 图面说明",
  "画风对齐 Dong Supplementary Figure 1：实心黑圆节点、旁注标签、细黑箭头、白底。",
  "节点仅为最终 Model 2：Gender, Race, Poverty(PIR), Alcohol use, eGFR,",
  "Environmental Toxicants, Pan-cancer。",
  "",
  "## 分析上下文",
  "Model2 stepwise 锁定集；无 Age/Smoke；无牙科节点。"
), file.path(fig_md, "Figure S1. DAG covariates.md"))

message("DONE Fig S1 Dong-style")
