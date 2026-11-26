#!/usr/bin/env Rscript
# 重导关键发表图：Times 系 + 展示名去下划线 + 无图面 title/subtitle
#   Rscript run/environment_exwas/fix_pancancer_pub_display.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
setwd(ROOT)
source("R/utils.R")
source("R/exwas_pub_digits.R")
suppressPackageStartupMessages(library(ggplot2))

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/Tables")
.font <- resolve_plot_font_family("Times New Roman")
message("[fix-display] font=", .font)

save_pdf <- function(p, path, w, h) {
  pipeline_pdf_device(path, width = w, height = h, family = "Times New Roman")
  print(p)
  grDevices::dev.off()
  message("wrote ", basename(path))
}

fam_cols <- c(
  "Acrylamide & Glycidamide" = "#1f4e79", "Aromatic Amines" = "#5b9bd5",
  "Arsenics - Speciated" = "#ed7d31", "Ethylene Oxide" = "#70ad47",
  "Formaldehyde" = "#833c0c", "Metals" = "#00b0f0",
  "Nicotine Metabolites" = "#a9d08e",
  "Polycyclic Aromatic Hydrocarbons" = "#7030a0",
  "Volatile Organic Compound Metabolites" = "#c00000", "Other" = "grey50"
)

volcano_from_csv <- function(csv, out_pdf, out_md, title_md, n_lab = 14L) {
  d <- utils::read.csv(csv, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"OR" %in% names(d) && "M2_OR" %in% names(d)) {
    # flat may store formatted OR — prefer numeric bak
    stop("need numeric OR column")
  }
  if (!"family" %in% names(d) || all(is.na(d$family))) {
    fam <- utils::read.csv(file.path(BASE, "data/toxicant_family_map.csv"), stringsAsFactors = FALSE)
    mp <- stats::setNames(fam$Family, fam$Labels)
    raw <- sub("_(ln|bin)$", "", d$exposure)
    d$family <- unname(mp[raw])
  }
  d$family[is.na(d$family) | !nzchar(as.character(d$family))] <- "Other"
  d$OR <- as.numeric(d$OR)
  d$p <- as.numeric(d$p)
  d$q <- as.numeric(d$q)
  d$logp <- -log10(pmax(d$p, 1e-300))
  d$sig <- is.finite(d$q) & d$q < 0.05
  d$exposure_name <- exwas_display_label(
    if ("exposure_name" %in% names(d)) d$exposure_name else sub("_(ln|bin)$", "", d$exposure)
  )
  present <- intersect(names(fam_cols), unique(d$family))
  d$family <- factor(d$family, levels = present)
  lab_idx <- which(d$sig)
  if (length(lab_idx) > n_lab) {
    lab_idx <- lab_idx[order(d$q[lab_idx], d$p[lab_idx])][seq_len(n_lab)]
  }
  d$lab <- ""
  d$lab[lab_idx] <- d$exposure_name[lab_idx]
  or_rng <- range(d$OR[is.finite(d$OR)], na.rm = TRUE)
  pad <- max(0.03, diff(or_rng) * 0.08)
  xlim <- c(or_rng[1] - pad, or_rng[2] + pad)
  p <- ggplot(d, aes(OR, logp, color = family)) +
    geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.45) +
    geom_hline(yintercept = -log10(0.05), linetype = 2, color = "grey55", linewidth = 0.45) +
    geom_point(size = 2.2, alpha = 0.92) +
    scale_color_manual(values = fam_cols[present], name = NULL, drop = FALSE) +
    scale_x_continuous(limits = xlim, breaks = pretty(xlim, n = 6), expand = c(0.02, 0)) +
    labs(x = "Odds ratio (per IQR)", y = expression(-log[10](P-value))) +
    theme_bw(base_size = 11, base_family = .font) +
    theme(
      legend.position = "top", legend.text = element_text(size = 8, family = .font),
      axis.title = element_text(family = .font), axis.text = element_text(family = .font),
      plot.title = element_blank(), plot.subtitle = element_blank(), plot.caption = element_blank()
    ) +
    guides(color = guide_legend(nrow = 3, byrow = TRUE, override.aes = list(size = 2.5)))
  if (requireNamespace("ggrepel", quietly = TRUE) && any(nzchar(d$lab))) {
    p <- p + ggrepel::geom_text_repel(
      data = subset(d, lab != ""), aes(label = lab),
      size = 3, family = .font, fontface = "bold", max.overlaps = 30, seed = 42, show.legend = FALSE
    )
  }
  save_pdf(p, out_pdf, 9, 6.6)
  writeLines(c(
    paste0("# ", title_md), "", "## 图面说明",
    sprintf("火山图；FDR q<0.05 命中数 = %d。展示名已去下划线；无图面总标题。", sum(d$sig)),
    "", "## 分析上下文", "泛癌 ExWAS；字体 Times 系。"
  ), out_md)
  invisible(sum(d$sig))
}

# Fig2 from Model2 numeric bak if available
m2 <- file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.bak.csv")
flat <- file.path(src_tab, "Table 2. ExWAS Model1 Model2 flat.csv")
if (file.exists(m2)) {
  d <- utils::read.csv(m2, stringsAsFactors = FALSE, check.names = FALSE)
  # normalize cols
  if (!"OR" %in% names(d)) {
    # expect OR/lo/hi/p/q style
  }
}
# Prefer S7-style columns from a built volcano source: use flat M2
if (file.exists(flat)) {
  fl <- utils::read.csv(flat, stringsAsFactors = FALSE, check.names = FALSE)
  # parse OR from "1.222 (1.094, 1.365)" if needed — use bak numeric
}
bak <- file.path(src_tab, "Table 2. ExWAS toxicant associations_model2_numeric.csv")
if (!file.exists(bak)) bak <- m2
if (file.exists(bak)) {
  d <- utils::read.csv(bak, stringsAsFactors = FALSE, check.names = FALSE)
  nm <- names(d)
  if (!"OR" %in% nm && "M2_OR" %in% nm) d$OR <- d$M2_OR
  if (!"p" %in% nm && "M2_p" %in% nm) d$p <- d$M2_p
  if (!"q" %in% nm && "M2_q" %in% nm) d$q <- d$M2_q
  if (!"exposure" %in% nm && "exposure" %in% nm) NULL
  utils::write.csv(d, file.path(tempdir(), "fig2_src.csv"), row.names = FALSE)
  # if OR is character formatted, read numeric bak fields
  if (is.character(d$OR[1]) && grepl("\\(", d$OR[1])) {
    # flat formatted — fall back to building from p columns only if numeric OR exists elsewhere
    message("WARN Fig2: OR formatted; try numeric columns")
  } else {
    volcano_from_csv(
      file.path(tempdir(), "fig2_src.csv"),
      file.path(fig_pdf, "Figure 2. ExWAS volcano.pdf"),
      file.path(fig_md, "Figure 2. ExWAS volcano.md"),
      "Figure 2. ExWAS volcano"
    )
  }
}

# S5 from survey weighted csv
s7 <- file.path(src_tab, "Table S7. ExWAS survey-weighted.csv")
if (file.exists(s7)) {
  volcano_from_csv(
    s7,
    file.path(fig_pdf, "Figure S5. ExWAS survey-weighted.pdf"),
    file.path(fig_md, "Figure S5. ExWAS survey-weighted.md"),
    "Figure S5. ExWAS survey-weighted"
  )
}

# S7 WQS bars
wqs <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream/Table_WQS_weights.csv")
if (!file.exists(wqs)) wqs <- file.path(src_tab, "Table. WQS mixture weights.csv")
if (file.exists(wqs)) {
  wt <- utils::read.csv(wqs, stringsAsFactors = FALSE, check.names = FALSE)
  wcol <- if ("mean_weight" %in% names(wt)) "mean_weight" else names(wt)[grep("weight", names(wt), ignore.case = TRUE)[1]]
  ncol <- if ("exposure_name" %in% names(wt)) "exposure_name" else if ("mix_name" %in% names(wt)) "mix_name" else names(wt)[1]
  wt$lab <- factor(exwas_display_label(wt[[ncol]]), levels = rev(exwas_display_label(wt[[ncol]][order(-as.numeric(wt[[wcol]]))])))
  wt$w <- as.numeric(wt[[wcol]])
  h <- max(8.5, 0.14 * nrow(wt) + 1.5)
  p <- ggplot(wt, aes(w, lab, fill = w)) +
    geom_col(width = 0.85) +
    scale_fill_gradientn(colours = c("#DEEBF7", "#9ECAE1", "#4292C6", "#2171B5", "#08306B"), guide = "none") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(x = "Weight", y = NULL) +
    theme_bw(base_size = 9, base_family = .font) +
    theme(
      panel.grid.major.y = element_blank(),
      axis.text.y = element_text(size = 6.5, family = .font),
      plot.title = element_blank(), plot.subtitle = element_blank()
    )
  save_pdf(p, file.path(fig_pdf, "Figure S7. WQS weights.pdf"), 7.2, h)
  writeLines(c(
    "# Figure S7. WQS weights", "", "## 图面说明",
    "gWQS 相对权重；展示名去下划线；无图面总标题。",
    "", "## 分析上下文", "泛癌；协变量同 Model 2。"
  ), file.path(fig_md, "Figure S7. WQS weights.md"))
}

message("[fix-display] DONE core volcano/WQS; run redraw scripts for S1/S2/S6/Fig4 if needed")
