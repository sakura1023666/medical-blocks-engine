#!/usr/bin/env Rscript
# 泛癌 ExWAS 发表图重绘：对齐 Dong 2026 EWAS-new 版式（Fig1 中栏+右侧排除肘形箭头；
# 其余图 Times 衬线、干净白底、统一配色）
#
#   Rscript redraw_pancancer_pub_figures.R --root <.../environment_41380607>
#
args <- commandArgs(trailingOnly = TRUE)
root <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--root" && i < length(args)) {
    root <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", args[[i]], call. = FALSE)
}
if (is.null(root)) {
  root <- "/mnt/g/02block_result/58_cancer/environment_41380607"
}
root <- normalizePath(root, winslash = "/", mustWork = TRUE)
sum_dir <- file.path(root, "summary_results")
fig_pdf <- file.path(sum_dir, "Figures", "pdf")
fig_md <- file.path(sum_dir, "Figures", "image_information")
tab_dir <- file.path(sum_dir, "Tables")
src_screen <- file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke_UCR_WTSA")
src_pub <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
})
if (requireNamespace("cowplot", quietly = TRUE)) library(cowplot)
if (requireNamespace("patchwork", quietly = TRUE)) library(patchwork)
if (requireNamespace("openxlsx", quietly = TRUE)) library(openxlsx)

# ---- theme ----
.font <- if ("Times New Roman" %in% systemfonts::system_fonts()$family) {
  "Times New Roman"
} else if (requireNamespace("extrafont", quietly = TRUE)) {
  "Times"
} else {
  "serif"
}
# safer: use cairo with Times/Liberation
.font <- "serif"
theme_pub <- function(base_size = 11) {
  theme_bw(base_size = base_size, base_family = .font) %+replace%
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "grey92", linewidth = 0.3),
      axis.title = element_text(face = "plain"),
      plot.title = element_text(face = "bold", hjust = 0, size = base_size + 1, margin = margin(b = 6)),
      plot.subtitle = element_text(color = "grey30", size = base_size - 1, hjust = 0, margin = margin(b = 8)),
      legend.background = element_blank(),
      strip.background = element_rect(fill = "grey96", color = "grey70"),
      plot.margin = margin(8, 10, 8, 10)
    )
}
col_sig <- "#B2182B"
col_ns <- "grey55"
col_accent <- "#2166AC"

save_pdf <- function(plot, path, w = 7, h = 5.5) {
  grDevices::cairo_pdf(path, width = w, height = h, family = .font)
  print(plot)
  grDevices::dev.off()
  message("wrote ", path)
}
write_md <- function(stem, face, ctx) {
  writeLines(c(
    paste0("# ", stem), "", "## 图面说明", face, "", "## 分析上下文", ctx
  ), file.path(fig_md, paste0(stem, ".md")))
}

fmt_n <- function(n) format(as.integer(n), big.mark = ",", scientific = FALSE)

# ============================================================================
# Figure 1 — paper-style flowchart (grid)
# ============================================================================
draw_fig1_paper <- function(pdf_path) {
  # numbers from attrition
  n0 <- 30200L; c0 <- 2732L
  n1 <- 20906L; c1 <- 1901L
  n2 <- 12484L; c2 <- 1195L
  n3 <- 11098L; c3 <- 1070L
  e1 <- n0 - n1; e2 <- n1 - n2; e3 <- n2 - n3

  main <- c(
    sprintf("Subjects from NHANES (multi-cycle)\naged \u2265 20 years with toxicant linkage\n(N=%s; cancer cases=%s)",
            fmt_n(n0), fmt_n(c0)),
    sprintf("Participants with urinary creatinine > 0\n(N=%s; cancer cases=%s)",
            fmt_n(n1), fmt_n(c1)),
    sprintf("Participants with WTSA2YR > 0\n(N=%s; cancer cases=%s)",
            fmt_n(n2), fmt_n(c2)),
    sprintf("Final participants\n(N=%s; cancer cases=%s)",
            fmt_n(n3), fmt_n(c3))
  )
  excl <- c(
    sprintf("Participants with missing or\nnon-positive urinary creatinine\n(N=%s)", fmt_n(e1)),
    sprintf("Participants with missing or\nnon-positive WTSA2YR weight\n(N=%s)", fmt_n(e2)),
    sprintf("Participants with missing values in\nmore than 1/3 of environmental toxicants\n(N=%s)", fmt_n(e3))
  )

  grDevices::cairo_pdf(pdf_path, width = 8.2, height = 9.2, family = .font)
  grid.newpage()
  # layout coordinates (npc)
  # main boxes centered at x=0.34; exclude at x=0.78
  mx <- 0.34; ex <- 0.78
  bw <- 0.42; bh <- 0.11
  ebw <- 0.38; ebh <- 0.10
  # y centers for 4 main boxes
  my <- c(0.88, 0.64, 0.40, 0.16)
  # exclude y = mid between mains
  ey <- c((my[1] + my[2]) / 2, (my[2] + my[3]) / 2, (my[3] + my[4]) / 2)

  roundrect <- function(x, y, w, h, gp = gpar(fill = "white", col = "black", lwd = 1.2)) {
    grid.roundrect(x = x, y = y, width = w, height = h,
                   r = unit(0.02, "npc"), gp = gp)
  }
  center_text <- function(x, y, label, cex = 0.95) {
    grid.text(label, x = x, y = y, gp = gpar(fontsize = 11 * cex, fontfamily = .font),
              just = "center")
  }

  # title
  grid.text("Figure 1. Flow chart of the study population",
            x = 0.5, y = 0.985,
            gp = gpar(fontsize = 13, fontface = "bold", fontfamily = .font))

  # draw main boxes
  for (i in seq_along(main)) {
    roundrect(mx, my[i], bw, bh)
    center_text(mx, my[i], main[i], cex = 0.92)
  }
  # vertical connectors + exclude elbows
  for (i in seq_len(3)) {
    y_top <- my[i] - bh / 2
    y_bot <- my[i + 1] + bh / 2
    y_mid <- ey[i]
    # vertical line full
    grid.lines(x = c(mx, mx), y = c(y_top, y_bot),
               gp = gpar(col = "black", lwd = 1.1),
               arrow = arrow(type = "open", length = unit(3.5, "mm"), angle = 22))
    # horizontal to exclude
    grid.lines(x = c(mx, ex - ebw / 2), y = c(y_mid, y_mid),
               gp = gpar(col = "black", lwd = 1.1),
               arrow = arrow(type = "open", length = unit(3.5, "mm"), angle = 22))
    roundrect(ex, y_mid, ebw, ebh)
    center_text(ex, y_mid, excl[i], cex = 0.88)
  }

  grid.text("Abbreviation: NHANES, National Health and Nutrition Examination Survey.",
            x = 0.05, y = 0.025, just = "left",
            gp = gpar(fontsize = 9, fontfamily = .font, col = "grey25"))
  grDevices::dev.off()
  message("wrote ", pdf_path)
}

draw_fig1_paper(file.path(fig_pdf, "Figure 1. Study flowchart.pdf"))
write_md(
  "Figure 1. Study flowchart",
  paste0(
    "中栏四框：Age\u226520 毒物联接 N=30,200 \u2192 尿肌酐>0 N=20,906 \u2192 WTSA2YR>0 N=12,484 \u2192 终分析 N=11,098（病例1,070）。",
    "右侧三排除框：无/非正尿肌酐 9,294；无/非正权重 8,422；毒物缺失>1/3 共 1,386。",
    "版式对齐 Dong 2026 Fig.1（中栏纳入 + 右侧排除 + 肘形箭头）。"
  ),
  "结局=泛癌(MCQ220)；多周期 NHANES；分析集与 Table 1 一致。"
)

# ============================================================================
# helpers to read tables
# ============================================================================
read_xlsx_df <- function(path, sheet = 1) {
  openxlsx::read.xlsx(path, sheet = sheet)
}

# ============================================================================
# Figure 2 volcano (full ExWAS) — OR x-axis + family colors (Dong Fig.2 style)
# ============================================================================
t2 <- read_xlsx_df(file.path(tab_dir, "Table 2. ExWAS toxicant associations.xlsx"), sheet = "ExWAS_full")
t2$OR <- as.numeric(t2$OR)
t2$p <- as.numeric(t2$p)
t2$q <- as.numeric(t2$q)
t2$logp <- -log10(pmax(t2$p, 1e-300))
t2$sig <- is.finite(t2$q) & t2$q < 0.05
t2$exposure_name <- gsub("_", " ", as.character(t2$exposure_name))
raw <- if ("exposure_raw" %in% names(t2)) t2$exposure_raw else sub("_(ln|bin)$", "", t2$exposure)
fam_csv <- file.path(root, "data/toxicant_family_map.csv")
if (file.exists(fam_csv)) {
  fam_map <- utils::read.csv(fam_csv, stringsAsFactors = FALSE)
  mp <- stats::setNames(fam_map$Family, fam_map$Labels)
  t2$family <- unname(mp[raw])
} else if ("family" %in% names(t2)) {
  t2$family <- as.character(t2$family)
} else {
  t2$family <- "Other"
}
t2$family[is.na(t2$family) | !nzchar(t2$family)] <- "Other"
fam_levels <- c(
  "Acrylamide & Glycidamide", "Aromatic Amines", "Arsenics - Speciated",
  "Ethylene Oxide", "Formaldehyde", "Heterocyclic Aromatic Amines", "Iodine",
  "Metals", "Nicotine Metabolites", "Perchlorate, Nitrate & Thiocyanate",
  "Polycyclic Aromatic Hydrocarbons", "Volatile Organic Compound Metabolites", "Other"
)
fam_cols <- c(
  "Acrylamide & Glycidamide" = "#1f4e79",
  "Aromatic Amines" = "#5b9bd5",
  "Arsenics - Speciated" = "#ed7d31",
  "Ethylene Oxide" = "#70ad47",
  "Formaldehyde" = "#833c0c",
  "Heterocyclic Aromatic Amines" = "#9e7bb5",
  "Iodine" = "#ff66cc",
  "Metals" = "#00b0f0",
  "Nicotine Metabolites" = "#a9d08e",
  "Perchlorate, Nitrate & Thiocyanate" = "#c65911",
  "Polycyclic Aromatic Hydrocarbons" = "#7030a0",
  "Volatile Organic Compound Metabolites" = "#c00000",
  "Other" = "grey50"
)
present <- intersect(fam_levels, unique(t2$family))
t2$family <- factor(t2$family, levels = present)
lab_idx <- which(t2$sig)
if (length(lab_idx) > 14L) {
  lab_idx <- lab_idx[order(t2$q[lab_idx], t2$p[lab_idx])][seq_len(14L)]
}
t2$lab <- ""
t2$lab[lab_idx] <- t2$exposure_name[lab_idx]
# 横轴只按数据范围略留边，禁止硬拉到 1.8 造成右侧大片空白
or_rng <- range(t2$OR[is.finite(t2$OR)], na.rm = TRUE)
pad <- max(0.03, diff(or_rng) * 0.08)
xlim <- c(or_rng[1] - pad, or_rng[2] + pad)

p2 <- ggplot(t2, aes(x = OR, y = logp, color = family)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.45) +
  geom_hline(yintercept = -log10(0.05), linetype = 2, color = "grey55", linewidth = 0.45) +
  geom_point(size = 2.2, alpha = 0.92) +
  scale_color_manual(values = fam_cols[present], name = NULL, drop = FALSE) +
  scale_x_continuous(limits = xlim, breaks = pretty(xlim, n = 6), expand = c(0.02, 0)) +
  coord_cartesian(clip = "off") +
  labs(
    title = "Exposome-wide association study of environmental toxicants with pan-cancer",
    subtitle = "Unweighted logistic models; BH-FDR; points colored by chemical family; dashed lines: OR=1 and P=0.05",
    x = "Odds ratio (per IQR)",
    y = expression(-log[10](P-value))
  ) +
  theme_pub(11) +
  theme(
    legend.position = "top",
    legend.text = element_text(size = 8),
    legend.key.size = unit(0.35, "cm")
  ) +
  guides(color = guide_legend(nrow = 3, byrow = TRUE, override.aes = list(size = 2.5)))
if (requireNamespace("ggrepel", quietly = TRUE)) {
  p2 <- p2 + ggrepel::geom_text_repel(
    data = subset(t2, lab != ""),
    aes(label = lab),
    size = 3.0, family = .font, fontface = "bold",
    max.overlaps = 30, box.padding = 0.35, point.padding = 0.2,
    segment.color = "grey60", segment.size = 0.3, seed = 42, show.legend = FALSE
  )
} else {
  p2 <- p2 + geom_text(
    data = subset(t2, lab != ""), aes(label = lab),
    size = 2.6, vjust = -0.5, check_overlap = TRUE, show.legend = FALSE, color = "grey20"
  )
}
save_pdf(p2, file.path(fig_pdf, "Figure 2. ExWAS volcano.pdf"), w = 9.0, h = 6.6)
write_md(
  "Figure 2. ExWAS volcano",
  paste0(
    "火山图对齐 Dong 2026 Fig.2：横轴 Odds ratio（非 logOR），纵轴 -log10(P)；",
    "竖虚线 OR=1，横虚线 P=0.05。点按化学类别着色。",
    "横轴范围按数据 OR 收紧（约 ", sprintf("%.2f\u2013%.2f", xlim[1], xlim[2]), "），避免右侧空白。",
    "标注 FDR q<0.05 主要命中；命中数=", sum(t2$sig), "。"
  ),
  "泛癌；N=11,098；不加权 ExWAS + BH-FDR；全调整无 Smoke；URXUCR>0 与 WTSA2YR>0。"
)
message("Fig2 xlim = [", paste(round(xlim, 3), collapse = ", "), "]; OR data = [",
        paste(round(or_rng, 3), collapse = ", "), "]")

# ============================================================================
# Figure 3 stratified — Dong Fig.3 style (OR + family + free scales)
# ============================================================================
s3 <- read_xlsx_df(file.path(tab_dir, "Table S3. ExWAS stratified by sex.xlsx"))
s4 <- read_xlsx_df(file.path(tab_dir, "Table S4. ExWAS stratified by age.xlsx"))
st <- rbind(s3, s4)
st <- st[!duplicated(paste(st$stratum, st$exposure)), , drop = FALSE]
st$OR <- as.numeric(st$OR)
st$p <- as.numeric(st$p)
st$logp <- -log10(pmax(st$p, 1e-300))
st$exposure_name <- gsub("_", " ", as.character(st$exposure_name))
raw3 <- if ("exposure_raw" %in% names(st)) st$exposure_raw else sub("_(ln|bin)$", "", st$exposure)
if (exists("mp") && length(mp)) {
  st$family <- unname(mp[raw3])
} else if (file.exists(file.path(root, "data/toxicant_family_map.csv"))) {
  fam_map3 <- utils::read.csv(file.path(root, "data/toxicant_family_map.csv"), stringsAsFactors = FALSE)
  mp3 <- stats::setNames(fam_map3$Family, fam_map3$Labels)
  st$family <- unname(mp3[raw3])
} else {
  st$family <- "Other"
}
st$family[is.na(st$family) | !nzchar(as.character(st$family))] <- "Other"
present3 <- intersect(names(fam_cols), unique(st$family))
st$family <- factor(st$family, levels = present3)
st$panel <- factor(
  st$stratum,
  levels = c("Male", "Female", "Age_lt60", "Age_ge60"),
  labels = c(
    "Stratification by sex (Male)", "Stratification by sex (Female)",
    "Stratification by age (<60 years)", "Stratification by age (\u226560 years)"
  )
)
st$lab <- ""
for (pn in levels(st$panel)) {
  idx <- which(st$panel == pn & is.finite(st$p) & st$p < 0.05)
  if (!length(idx)) next
  idx <- idx[order(st$p[idx])]
  if (length(idx) > 10L) idx <- idx[seq_len(10L)]
  st$lab[idx] <- st$exposure_name[idx]
}
p3 <- ggplot(st, aes(x = OR, y = logp, color = family)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.4) +
  geom_hline(yintercept = -log10(0.05), linetype = 2, color = "grey55", linewidth = 0.4) +
  geom_point(size = 1.9, alpha = 0.9) +
  scale_color_manual(values = fam_cols[present3], name = NULL, drop = FALSE) +
  facet_wrap(~panel, nrow = 2, scales = "free") +
  labs(
    title = "Stratified ExWAS of environmental toxicants with pan-cancer",
    subtitle = "Complete-case within stratum; dashed: OR=1 and P=0.05; labels: nominal P<0.05 (stratum FDR all q\u22650.05)",
    x = "Odds ratio (per IQR)", y = expression(-log[10](P-value))
  ) +
  theme_pub(10) +
  theme(
    legend.position = "top",
    legend.text = element_text(size = 7.5),
    legend.key.size = unit(0.32, "cm"),
    strip.text = element_text(face = "bold")
  ) +
  guides(color = guide_legend(nrow = 3, byrow = TRUE, override.aes = list(size = 2.3)))
if (requireNamespace("ggrepel", quietly = TRUE)) {
  p3 <- p3 + ggrepel::geom_text_repel(
    data = subset(st, lab != ""),
    aes(label = lab), size = 2.6, family = .font, fontface = "bold",
    max.overlaps = 25, box.padding = 0.28, point.padding = 0.15,
    segment.color = "grey65", segment.size = 0.25, seed = 42, show.legend = FALSE
  )
}
save_pdf(p3, file.path(fig_pdf, "Figure 3. Stratified ExWAS by sex and age.pdf"), w = 10.5, h = 8.2)
write_md(
  "Figure 3. Stratified ExWAS by sex and age",
  paste0(
    "四面板对齐 Dong 2026 Fig.3。横轴 OR、纵轴 -log10(P)、族着色、P=0.05 虚线；",
    "标注名义 P<0.05。本泛癌分层 BH-FDR 均不显著。",
    "数字不可与原文牙周炎 Fig.3 逐点对照。"
  ),
  "N=11,098；层内完整病例；协变量同主分析。"
)

# ============================================================================
# Figure 4 panels from tables
# ============================================================================
# 4A correlation from FDR hits — rebuild pairwise if needed from screen csv
hits <- read_xlsx_df(file.path(tab_dir, "Table 2. ExWAS toxicant associations.xlsx"), sheet = "FDR_hits")
# inclusion
inc <- read_xlsx_df(file.path(tab_dir, "Table S5. ERS bootstrap inclusion and selection.xlsx"),
                    sheet = "Bootstrap_inclusion")
fcol <- if ("inclusion_freq" %in% names(inc)) "inclusion_freq" else names(inc)[intersect(c("inclusion_freq","freq"), names(inc))][1]
ecol <- if ("exposure" %in% names(inc)) "exposure" else names(inc)[1]
inc$nm <- if ("exposure_name" %in% names(hits)) {
  mp <- setNames(hits$exposure_name, hits$exposure)
  ifelse(is.na(mp[inc[[ecol]]]), inc[[ecol]], unname(mp[inc[[ecol]]]))
} else inc[[ecol]]
inc$nm <- gsub("_", " ", sub("_(ln|bin)$", "", as.character(inc$nm)))
inc$selected <- if ("selected_final" %in% names(inc)) as.logical(inc$selected_final) else TRUE

p4bc <- ggplot(inc, aes(x = reorder(nm, .data[[fcol]]), y = .data[[fcol]], fill = selected)) +
  geom_col(width = 0.75) +
  coord_flip() +
  scale_fill_manual(values = c(`FALSE` = "grey70", `TRUE` = col_accent),
                    labels = c("Not selected", "Selected in final ERS"), name = NULL) +
  scale_y_continuous(limits = c(0, 1.05), expand = c(0, 0)) +
  labs(
    title = "Bootstrap inclusion frequencies for ERS candidate toxicants",
    subtitle = "Adaptive elastic-net; B = 1000",
    x = NULL, y = "Inclusion frequency"
  ) +
  theme_pub(10) +
  theme(legend.position = "bottom", panel.grid.major.y = element_blank())
save_pdf(p4bc, file.path(fig_pdf, "Figure 4B-C. ERS elastic-net inclusion.pdf"), w = 7.5, h = 6)

ers <- read_xlsx_df(file.path(tab_dir, "Table S13. ERS weighted logistic Model1 Model2.xlsx"))
ers$label <- sprintf("%.3f (%.3f\u2013%.3f)", ers$OR, ers$lo, ers$hi)
ers$model <- factor(ers$model, levels = rev(ers$model))
p4d <- ggplot(ers, aes(x = OR, y = model, xmin = lo, xmax = hi)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey60") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.18, color = col_sig, linewidth = 0.7) +
  geom_point(size = 2.8, color = col_sig) +
  geom_text(aes(label = label), hjust = -0.08, size = 3.1, family = .font) +
  scale_x_continuous(limits = c(0.7, max(ers$hi, na.rm = TRUE) * 1.35)) +
  labs(
    title = "Association between ERS and pan-cancer",
    subtitle = "Survey-weighted logistic regression (WTSA2YR); Model 1 unadjusted, Model 2 fully adjusted",
    x = "Odds ratio", y = NULL
  ) +
  theme_pub(11) +
  theme(panel.grid.major.y = element_blank())
save_pdf(p4d, file.path(fig_pdf, "Figure 4D. ERS forest.pdf"), w = 8, h = 4.2)

# 4F / S3 subgroup
sg <- read_xlsx_df(file.path(tab_dir, "Table S15. ERS subgroup associations.xlsx"))
sg$stratum <- factor(sg$stratum, levels = rev(unique(sg$stratum)))
p4f <- ggplot(sg, aes(x = OR, y = stratum, xmin = lo, xmax = hi)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey60") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.2, color = col_sig, linewidth = 0.65) +
  geom_point(size = 2.5, color = col_sig) +
  labs(
    title = "Stratified associations of ERS with pan-cancer",
    subtitle = "Unadjusted OR per IQR of ERS",
    x = "Odds ratio (per IQR)", y = NULL
  ) +
  theme_pub(11) +
  theme(panel.grid.major.y = element_blank())
save_pdf(p4f, file.path(fig_pdf, "Figure 4F. ERS subgroup forest.pdf"), w = 7.5, h = 4.8)
file.copy(file.path(fig_pdf, "Figure 4F. ERS subgroup forest.pdf"),
          file.path(fig_pdf, "Figure S3. ERS subgroup forest.pdf"), overwrite = TRUE)

# 4E RCS — rebuild lightly from downstream note if curve data absent: keep polished restyle via existing if any
# Try regenerate from selected coefs + need raw data — skip heavy rebuild; restyle placeholder curve from S13 only if RCS pdf exists
# Mediation Fig5
med <- read_xlsx_df(file.path(tab_dir, "Table S6. Mediation exploratory.xlsx"))
if (nrow(med)) {
  med$prop <- ifelse(is.finite(med$direct + med$indirect) & abs(med$direct + med$indirect) > 1e-12,
                     100 * med$indirect / (med$direct + med$indirect), NA_real_)
  med$mediator <- factor(med$mediator, levels = med$mediator[order(abs(med$indirect))])
  p5 <- ggplot(med, aes(x = mediator, y = indirect)) +
    geom_hline(yintercept = 0, linetype = 2, color = "grey70") +
    geom_col(fill = "#D6604D", width = 0.7) +
    geom_text(aes(label = sprintf("%.1f%%", prop)), hjust = -0.1, size = 3, family = .font, na.rm = TRUE) +
    coord_flip() +
    labs(
      title = "Exploratory mediation by inflammatory biomarkers",
      subtitle = "Indirect effect (a\u00d7b) of ERS on pan-cancer; labels show proportion mediated",
      x = NULL, y = "Indirect effect"
    ) +
    theme_pub(11) +
    theme(panel.grid.major.y = element_blank())
  save_pdf(p5, file.path(fig_pdf, "Figure 5. Mediation inflammatory biomarkers.pdf"), w = 7.5, h = 5)
}

# S5 unimputed volcano
s7 <- read_xlsx_df(file.path(tab_dir, "Table S7. ExWAS without imputation.xlsx"))
s7$sig <- is.finite(as.numeric(s7$q)) & as.numeric(s7$q) < 0.05
p_s5 <- ggplot(s7, aes(x = log(pmax(as.numeric(OR), 1e-12)), y = -log10(pmax(as.numeric(p), 1e-300)), color = sig)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey75") +
  geom_point(size = 1.8, alpha = 0.9) +
  scale_color_manual(values = c(`FALSE` = col_ns, `TRUE` = col_sig),
                     labels = c("q \u2265 0.05", "q < 0.05"), name = NULL) +
  labs(title = "Sensitivity ExWAS without multiple imputation",
       x = "log(OR per IQR)", y = expression(-log[10](P))) +
  theme_pub(11) + theme(legend.position = "bottom")
save_pdf(p_s5, file.path(fig_pdf, "Figure S5. ExWAS without imputation.pdf"), w = 7.5, h = 5.5)

# S6 smoke corr
sm <- tryCatch(read_xlsx_df(file.path(src_pub, "Tables", "Table_S_smoke_toxicant_correlation.csv")), error = function(e) NULL)
# csv may not be xlsx — read csv from full_pub
sm_path <- file.path(src_pub, "Tables", "Table_S_smoke_toxicant_correlation.csv")
if (!file.exists(sm_path)) sm_path <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables", "Table_S_smoke_toxicant_correlation.csv")
if (file.exists(sm_path)) {
  sm <- utils::read.csv(sm_path, stringsAsFactors = FALSE)
  sm <- sm[is.finite(sm$r_smoke), ]
  sm$exposure_name <- as.character(sm$exposure_name)
  p_s6 <- ggplot(sm, aes(x = reorder(exposure_name, r_smoke), y = r_smoke)) +
    geom_col(fill = col_accent, width = 0.75) +
    coord_flip() +
    labs(title = "Correlation between smoking status and environmental toxicants",
         x = NULL, y = "Pearson r") +
    theme_pub(9) + theme(panel.grid.major.y = element_blank())
  save_pdf(p_s6, file.path(fig_pdf, "Figure S6. Smoke toxicant correlation.pdf"), w = 7.5, h = 9)
}

# S7 WQS
wqs <- read_xlsx_df(file.path(tab_dir, "Table S14. WQS mixture weights and coefficients.xlsx"), sheet = "Weights")
nm_col <- if ("mix_name" %in% names(wqs)) "mix_name" else names(wqs)[1]
w_col <- if ("mean_weight" %in% names(wqs)) "mean_weight" else names(wqs)[2]
wqs$lab <- gsub("_", " ", sub("_(ln|bin)$", "", as.character(wqs[[nm_col]])))
p_s7 <- ggplot(wqs, aes(x = reorder(lab, .data[[w_col]]), y = .data[[w_col]])) +
  geom_col(fill = "#1B7837", width = 0.75) +
  coord_flip() +
  labs(title = "Relative contribution weights of toxicants in the WQS mixture",
       subtitle = "gWQS; q = 4; bootstrap = 1000; candidates = ExWAS FDR hits",
       x = NULL, y = "Weight") +
  theme_pub(10) + theme(panel.grid.major.y = element_blank())
save_pdf(p_s7, file.path(fig_pdf, "Figure S7. WQS weights.pdf"), w = 7.5, h = 5.5)

# S1 DAG：专用脚本（圆形节点+有向边，对齐 Dong Supp Fig1）
message("Figure S1 DAG → redraw_pancancer_fig_s1_dag.R")
sys_s1 <- "/mnt/e/01block/01Block-new-Final/run/environment_exwas/redraw_pancancer_fig_s1_dag.R"
if (file.exists(sys_s1)) {
  system2("Rscript", sys_s1)
} else {
  warning("missing redraw_pancancer_fig_s1_dag.R")
}
# Rebuild Fig4 combined + 4A/4E if correlation/RCS sources exist
# 4A: use existing pairwise from full_pub internal if available; else skip keep old and restyle via pdf copy after regenerating from hits list only labels
# Attempt correlation from screen analytic is heavy; copy improved style by regenerating from saved cor csv if any
cor_csv <- file.path(src_pub, "Tables", "Table_S_toxicant_correlation.csv")
# may not exist — try hit-level from S0
# Leave 4A/4E/S2 as regenerated via a lighter call if data available in Output
message("Attempting Figure 4A / S2 / 4E from analytic rebuild...")

# Source toxicant helpers for 4A/4E
engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
suppressWarnings({
  source(file.path(engine, "R/environment_exwas_core.R"))
  source(file.path(engine, "R/environment_exwas_aligned.R"))
  source(file.path(engine, "R/environment_exwas_toxicant.R"))
  source(file.path(engine, "R/environment_exwas_toxicant_downstream.R"))
})
data_dir <- file.path(root, "data")
if (!dir.exists(data_dir)) {
  # data may still be under old gastric path or copied
  alt <- "/mnt/g/02block_result/51_gastric cancer/environment_41380607/data"
  if (dir.exists(file.path(root, "data"))) data_dir <- file.path(root, "data")
  else if (dir.exists(alt)) data_dir <- alt
  else data_dir <- file.path(root, "data")
}
ok_data <- dir.exists(data_dir) && file.exists(file.path(data_dir, "enviroment-factors.sav"))
if (ok_data) {
  built <- exwas_tox_build_cancer_table("pancancer", data_dir, 20L)
  d0 <- built$data
  d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
  d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
  tox <- intersect(built$tox_cols, names(d0))
  d1 <- exwas_tox_creatinine_adjust(d0, tox)$data
  scr <- exwas_tox_screen_transform(d1, tox)
  person <- exwas_tox_drop_person_missing(scr$data, scr$keep, 1/3, "cycle", sub("_(ln|bin)$", "", scr$keep))
  df <- person$data
  lab_map <- stats::setNames(built$code$Exposure, built$code$Labels)
  disp_of <- function(raw) ifelse(is.na(lab_map[raw]), raw, unname(lab_map[raw]))
  hit_cols <- intersect(hits$exposure, names(df))

  plot_cor <- function(cols, title, file, max_n = 80) {
    cols <- intersect(cols, names(df))
    if (length(cols) > max_n) cols <- cols[seq_len(max_n)]
    Xm <- df[, cols, drop = FALSE]
    for (nm in names(Xm)) Xm[[nm]] <- exwas_to_num(Xm[[nm]])
    R <- suppressWarnings(stats::cor(Xm, use = "pairwise.complete.obs"))
    raw <- sub("_(ln|bin)$", "", colnames(R))
    colnames(R) <- rownames(R) <- disp_of(raw)
    rdf <- as.data.frame(as.table(R), stringsAsFactors = FALSE)
    names(rdf) <- c("x", "y", "r")
    rdf$r[!is.finite(rdf$r)] <- NA
    p <- ggplot(rdf, aes(x, y, fill = r)) +
      geom_tile(color = NA) +
      scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                           midpoint = 0, limits = c(-1, 1), na.value = "grey90", name = "r") +
      coord_fixed() +
      labs(title = title, x = NULL, y = NULL) +
      theme_pub(8) +
      theme(
        axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6),
        axis.text.y = element_text(size = 6),
        panel.grid = element_blank()
      )
    save_pdf(p, file, w = 8.2, h = 7.6)
  }
  plot_cor(hit_cols, "Correlation among FDR-significant toxicants",
           file.path(fig_pdf, "Figure 4A. Toxicant correlation.pdf"))
  plot_cor(scr$keep, "Correlation among screened environmental toxicants",
           file.path(fig_pdf, "Figure S2. Toxicant correlation.pdf"), 63)

  # 4E RCS
  sel <- read_xlsx_df(file.path(tab_dir, "Table S5. ERS bootstrap inclusion and selection.xlsx"), sheet = "Selected")
  if (all(c("exposure", "coef") %in% names(sel)) && nrow(sel)) {
    beta <- stats::setNames(as.numeric(sel$coef), sel$exposure)
    df$ERS <- exwas_tox_score_ers(df, beta)
    use <- df[is.finite(df$ERS) & is.finite(exwas_to_num(df$WTSA2YR)) & exwas_to_num(df$WTSA2YR) > 0, ]
    iqr <- stats::IQR(use$ERS, na.rm = TRUE); if (!is.finite(iqr) || iqr == 0) iqr <- 1
    use$ERS_IQR <- use$ERS / iqr
    covars <- intersect(c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
                          "Alcohol_drinking", "eGFR"), names(use))
    use <- exwas_aligned_as_model_frame(use, covars)
    fit <- tryCatch(
      stats::glm(
        stats::as.formula(paste("DN ~ splines::ns(ERS_IQR, df=2)",
                                if (length(covars)) paste("+", paste(covars, collapse = "+")) else "")),
        data = use, family = stats::binomial(), weights = exwas_to_num(use$WTSA2YR)
      ),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      grid_x <- seq(stats::quantile(use$ERS_IQR, 0.05, na.rm = TRUE),
                    stats::quantile(use$ERS_IQR, 0.95, na.rm = TRUE), length.out = 100)
      nd <- data.frame(ERS_IQR = grid_x)
      for (cv in covars) {
        if (is.factor(use[[cv]]) || is.character(use[[cv]])) nd[[cv]] <- levels(factor(use[[cv]]))[1]
        else nd[[cv]] <- stats::median(exwas_to_num(use[[cv]]), na.rm = TRUE)
      }
      pr <- predict(fit, newdata = nd, type = "link", se.fit = TRUE)
      nd$fit <- stats::plogis(pr$fit)
      nd$lo <- stats::plogis(pr$fit - 1.96 * pr$se.fit)
      nd$hi <- stats::plogis(pr$fit + 1.96 * pr$se.fit)
      note <- file.path(src_pub, "_downstream", "Figure_4_RCS_note.txt")
      sub <- if (file.exists(note)) {
        ln <- readLines(note, warn = FALSE)
        hit <- grep("p_nonlinear", ln, value = TRUE)
        if (length(hit)) hit[[1]] else "RCS ns(df=2)"
      } else "RCS with 3 knots (ns df=2)"
      p4e <- ggplot(nd, aes(ERS_IQR, fit)) +
        geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#F4A582", alpha = 0.35) +
        geom_line(color = col_sig, linewidth = 1.05) +
        labs(
          title = "Restricted cubic spline of ERS and pan-cancer",
          subtitle = sub,
          x = "ERS (per IQR)", y = "Predicted probability"
        ) +
        theme_pub(11)
      save_pdf(p4e, file.path(fig_pdf, "Figure 4E. ERS RCS.pdf"), w = 7.2, h = 5.2)
    }
  }
} else {
  message("data dir missing; kept prior 4A/4E/S2 files if present")
}

# Combine Figure 4 multipage
panels <- c(
  "Figure 4A. Toxicant correlation.pdf",
  "Figure 4B-C. ERS elastic-net inclusion.pdf",
  "Figure 4D. ERS forest.pdf",
  "Figure 4E. ERS RCS.pdf",
  "Figure 4F. ERS subgroup forest.pdf"
)
panel_paths <- file.path(fig_pdf, panels)
panel_paths <- panel_paths[file.exists(panel_paths)]
if (length(panel_paths) >= 2L) {
  out4 <- file.path(fig_pdf, "Figure 4. ERS panels A-F.pdf")
  cmd <- paste("pdfunite", paste(shQuote(panel_paths), collapse = " "), shQuote(out4))
  system(cmd)
  message("wrote ", out4)
}

# S4 sensitivity one-page clean
grDevices::cairo_pdf(file.path(fig_pdf, "Figure S4. Mediation sensitivity.pdf"),
                     width = 8.5, height = 6, family = .font)
grid.newpage()
grid.text("Figure S4. Sensitivity considerations for mediation analysis",
          x = 0.5, y = 0.9, gp = gpar(fontsize = 13, fontface = "bold", fontfamily = .font))
txt <- paste(
  "Dong et al. reported formal mediation sensitivity surfaces (unmeasured confounding).",
  "In this pan-cancer delivery, mediation is exploratory (product method; Table S6 / Figure 5).",
  "Cross-sectional NHANES cannot establish temporal order (Exposure -> Mediator -> Outcome).",
  "Interpretation is associative; residual confounding (e.g., unmeasured lifestyle) remains possible.",
  sep = "\n\n"
)
grid.text(txt, x = 0.08, y = 0.55, just = c("left", "center"),
          gp = gpar(fontsize = 11, fontfamily = .font))
grDevices::dev.off()

message("DONE redraw -> ", fig_pdf)
