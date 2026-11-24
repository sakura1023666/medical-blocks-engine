#!/usr/bin/env Rscript
# Figure S2：完全对齐 Dong Supp Fig2 版式
# - 左侧：分析物名（横排）
# - 顶部：仅化学族竖标（无底部/右侧分析物名）
# - 按族排序；无聚类树；无单元格边框
# - 色带：负红 / 零白 / 正蓝；图例 -1…1 步长 0.2
#
#   Rscript redraw_pancancer_fig_s2_correlation.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))

suppressPackageStartupMessages({
  library(ComplexHeatmap)
  library(circlize)
  library(grid)
})

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

message("[S2] build analytic frame")
built <- exwas_tox_build_cancer_table("pancancer", file.path(BASE, "data"), 20L)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox)$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, 1 / 3, "cycle", sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
cols <- intersect(scr$keep, names(df))
if (length(cols) < 2L) stop("exposure pool empty", call. = FALSE)

fam_map <- utils::read.csv(
  file.path(BASE, "data/toxicant_family_map.csv"), stringsAsFactors = FALSE
)
bare <- sub("_(ln|bin)$", "", cols)
mp_ex <- stats::setNames(as.character(fam_map$Family), as.character(fam_map$Exposure))
mp_lb <- stats::setNames(as.character(fam_map$Family), as.character(fam_map$Labels))
# 展示名优先用 family_map$Exposure，再做常见文献化改写
disp0 <- bare
hit_ex <- bare %in% names(mp_ex)
disp0[hit_ex] <- bare[hit_ex]
# 若 bare 对不上 Exposure，试 Labels→Exposure
for (i in seq_along(bare)) {
  if (bare[[i]] %in% fam_map$Exposure) {
    disp0[[i]] <- bare[[i]]
  } else if (bare[[i]] %in% fam_map$Labels) {
    disp0[[i]] <- fam_map$Exposure[match(bare[[i]], fam_map$Labels)]
  }
}
pretty_name <- function(x) {
  x <- as.character(x)
  repl <- c(
    "Aminonaphthalene_1" = "1-Aminonaphthalene",
    "Aminonaphthalene_2" = "2-Aminonaphthalene",
    "Aminobiphenyl_4" = "4-Aminobiphenyl",
    "Anisidine_o" = "o-Anisidine",
    "Toluidine_o" = "o-Toluidine",
    "Dimethylaniline_2_6" = "2,6-Dimethylaniline",
    "Napthol_1" = "1-Naphthol",
    "Napthol_2" = "2-Naphthol",
    "Hydroxypyrene_1" = "1-Hydroxypyrene",
    "Hydroxyphenanthrene_2_3" = "2&3-Hydroxyphenanthrene",
    "Monomethylarsonic_Acid" = "Monomethylarsonic acid",
    "Dimethylarsinic_Acid" = "Dimethylarsinic acid",
    "Arsenous_Acid" = "Arsenous acid",
    "Arsenic_acid" = "Arsenic acid",
    "Ethylene_Oxide" = "Ethylene oxide",
    "Total_Cotinine" = "Total Cotinine",
    "Total_Hydroxycotinine" = "Total Hydroxycotinine",
    "TNE_2" = "TNE-2"
  )
  out <- ifelse(x %in% names(repl), unname(repl[x]), gsub("_", " ", x))
  out
}
disp <- pretty_name(disp0)
fam <- ifelse(
  !is.na(mp_ex[bare]), unname(mp_ex[bare]),
  ifelse(!is.na(mp_lb[bare]), unname(mp_lb[bare]), "Other")
)

fam_order <- c(
  "Acrylamide & Glycidamide",
  "Aromatic Amines",
  "Arsenics - Speciated",
  "Ethylene Oxide",
  "Formaldehyde",
  "Heterocyclic Aromatic Amines",
  "Iodine",
  "Metals",
  "Nicotine Metabolites",
  "Perchlorate, Nitrate & Thiocyanate",
  "Polycyclic Aromatic Hydrocarbons",
  "Volatile Organic Compound Metabolites",
  "Other"
)
fam <- factor(as.character(fam), levels = intersect(fam_order, unique(as.character(fam))))
ord <- order(as.integer(fam), disp)
cols <- cols[ord]
fam <- fam[ord]
disp <- make.unique(disp[ord])

Xm <- df[, cols, drop = FALSE]
for (nm in names(Xm)) Xm[[nm]] <- exwas_to_num(Xm[[nm]])
R <- suppressWarnings(stats::cor(Xm, use = "pairwise.complete.obs"))
rownames(R) <- colnames(R) <- disp

col_fun <- circlize::colorRamp2(
  c(-1, -0.5, 0, 0.5, 1),
  c("#67001F", "#B2182B", "#F7F7F7", "#4393C3", "#053061")
)

# 顶部族标：用 annotation block（竖排），矩阵保持连续（仅极细族间缝）
n_per <- as.integer(table(fam))
fam_lv <- levels(fam)
top_anno <- ComplexHeatmap::HeatmapAnnotation(
  foo = ComplexHeatmap::anno_block(
    gp = grid::gpar(fill = NA, col = NA, lwd = 0),
    labels = fam_lv,
    labels_gp = grid::gpar(fontsize = 7.5, fontfamily = "sans"),
    labels_rot = 90,
    labels_offset = grid::unit(2, "mm"),
    height = grid::unit(22, "mm")
  ),
  which = "column"
)

ht <- ComplexHeatmap::Heatmap(
  R,
  name = "r",
  col = col_fun,
  na_col = "grey85",
  cluster_rows = FALSE,
  cluster_columns = FALSE,
  # 原文：左侧分析物名；顶部仅族类竖标；无底部/右侧分析物名
  show_row_names = TRUE,
  show_column_names = FALSE,
  row_names_side = "left",
  row_names_gp = grid::gpar(fontsize = 5.5, fontfamily = "sans"),
  column_split = fam,
  column_gap = grid::unit(0.4, "mm"),
  column_title = NULL,
  top_annotation = top_anno,
  border = TRUE,
  rect_gp = grid::gpar(col = NA),
  width = grid::unit(15, "cm"),
  height = grid::unit(15, "cm"),
  heatmap_legend_param = list(
    title = "",
    at = seq(-1, 1, by = 0.2),
    labels = as.character(seq(-1, 1, by = 0.2)),
    legend_height = grid::unit(5, "cm"),
    grid_width = grid::unit(3.5, "mm"),
    labels_gp = grid::gpar(fontsize = 7, fontfamily = "sans")
  )
)

out <- file.path(fig_pdf, "Figure S2. Toxicant correlation.pdf")
grDevices::cairo_pdf(out, width = 10.5, height = 10.2, family = "sans")
ComplexHeatmap::draw(
  ht,
  padding = grid::unit(c(1, 1, 1, 1), "mm")
)
grDevices::dev.off()
message(
  "wrote ", out,
  " n=", length(cols),
  " families=", paste(levels(fam), collapse = " | ")
)

writeLines(c(
  "# Figure S2. Toxicant correlation",
  "",
  "## 图面说明",
  "对齐 Dong Supplementary Figure 2：左侧分析物名；顶部化学族竖标；无底部列名。",
  "行列按化学族排序；Pearson 相关；负红正蓝；图例 -1 至 1（步长 0.2）。",
  paste0("暴露数=", length(cols), "；族=", paste(levels(fam), collapse = "; "), "。"),
  "本队列无 Heterocyclic / Iodine / Perchlorate 族（筛入池不可得）。",
  "",
  "## 分析上下文",
  paste0("泛癌分析集 N=", nrow(df), "；描述性共线，不进 ERS 估计。")
), file.path(fig_md, "Figure S2. Toxicant correlation.md"))

message("DONE Fig S2 paper-matched")
