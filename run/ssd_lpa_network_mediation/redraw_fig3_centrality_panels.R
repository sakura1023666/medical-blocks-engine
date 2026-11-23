#!/usr/bin/env Rscript
# Figure 3: paper-role centrality 3×4 (class × Betweenness/Closeness/Strength/Expected Influence)
# Moves old Network C1–C3 singles → Figure S1–S3; renumbers ROC/DCA/Heatmap to Fig 4–9

suppressPackageStartupMessages({
  library(qgraph)
  library(ggplot2)
})

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}

ck <- readRDS(file.path(proj, "checkpoints/step10_correlation.rds"))
d <- ck$ctx$data$cleaned
nodes <- c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7")
lab_map <- c(
  PHQ15 = "PHQ-15", SSS8 = "SSS-8", SSD12 = "SSD-12", Whiteley8 = "Whiteley-8",
  WHODAS = "WHO-DAS", PHQ9 = "PHQ-9", GAD7 = "GAD-7"
)
nodes <- nodes[nodes %in% names(d)]
cls_col <- if ("LCA_class" %in% names(d)) "LCA_class" else "LPA_class"
stopifnot(cls_col %in% names(d))

ff <- tryCatch({
  tmp <- tempfile(fileext = ".pdf")
  grDevices::cairo_pdf(tmp, width = 1, height = 1, family = "Times New Roman")
  grDevices::dev.off()
  unlink(tmp)
  "Times New Roman"
}, error = function(e) "Liberation Serif")
message("font: ", ff)

.fit_adj <- function(df) {
  mat <- as.data.frame(lapply(df[nodes], function(z) suppressWarnings(as.numeric(z))))
  mat <- mat[stats::complete.cases(mat), , drop = FALSE]
  if (nrow(mat) < 30L) return(list(adj = NULL, n = nrow(mat)))
  adj <- qgraph::EBICglasso(
    stats::cor(mat, use = "pairwise.complete.obs"),
    n = nrow(mat), gamma = 0.5
  )
  list(adj = adj, n = nrow(mat))
}

.class_lab <- c(
  C1 = "C1: Low Disability \u2013 Mild Symptom Burden Group",
  C2 = "C2: Moderate Disability \u2013 Elevated Distress Group",
  C3 = "C3: High Disability \u2013 Severe Symptom Burden Group"
)

ks <- sort(unique(stats::na.omit(d[[cls_col]])))
tags <- paste0("C", ks)
cent_list <- list()
ns <- list()
for (k in ks) {
  tag <- paste0("C", k)
  sub <- d[!is.na(d[[cls_col]]) & d[[cls_col]] == k, , drop = FALSE]
  fit <- .fit_adj(sub)
  ns[[tag]] <- fit$n
  if (is.null(fit$adj)) next
  cent <- tryCatch(
    qgraph::centrality_auto(fit$adj)$node.centrality,
    error = function(e) as.data.frame(qgraph::centrality(fit$adj))
  )
  cent <- as.data.frame(cent)
  if (!"node" %in% names(cent)) {
    cent$node <- rownames(cent)
    if (all(is.na(cent$node)) || !length(cent$node)) {
      cent$node <- colnames(fit$adj)
    }
  }
  # ensure Expected Influence
  if (!"ExpectedInfluence" %in% names(cent) && "Expected Influence" %in% names(cent)) {
    names(cent)[names(cent) == "Expected Influence"] <- "ExpectedInfluence"
  }
  if (!"ExpectedInfluence" %in% names(cent)) {
    # signed strength fallback from adj rowSums
    cent$ExpectedInfluence <- as.numeric(rowSums(fit$adj))
  }
  cent$class <- tag
  cent_list[[tag]] <- cent
  message(tag, " n=", fit$n, " rows=", nrow(cent))
}

stopifnot(length(cent_list) >= 1L)

meas <- c("Betweenness", "Closeness", "Strength", "ExpectedInfluence")
meas_lab <- c(
  Betweenness = "Betweenness",
  Closeness = "Closeness",
  Strength = "Strength",
  ExpectedInfluence = "Expected Influence"
)

long <- do.call(rbind, lapply(cent_list, function(ct) {
  miss <- setdiff(meas, names(ct))
  if (length(miss)) stop("missing metrics: ", paste(miss, collapse = ", "))
  out <- data.frame(
    class = ct$class,
    node = as.character(ct$node),
    Betweenness = as.numeric(ct$Betweenness),
    Closeness = as.numeric(ct$Closeness),
    Strength = as.numeric(ct$Strength),
    ExpectedInfluence = as.numeric(ct$ExpectedInfluence),
    stringsAsFactors = FALSE
  )
  out
}))

# z-score within class × measure (paper x-axis)
long_z <- do.call(rbind, lapply(split(long, long$class), function(df) {
  for (m in meas) {
    x <- df[[m]]
    s <- stats::sd(x, na.rm = TRUE)
    if (is.na(s) || s < .Machine$double.eps) {
      df[[m]] <- 0
    } else {
      df[[m]] <- as.numeric(scale(x))
    }
  }
  df
}))

plot_df <- do.call(rbind, lapply(meas, function(m) {
  data.frame(
    class = long_z$class,
    node = long_z$node,
    measure = m,
    z = long_z[[m]],
    stringsAsFactors = FALSE
  )
}))

plot_df$node_lab <- unname(lab_map[plot_df$node])
plot_df$node_lab[is.na(plot_df$node_lab)] <- plot_df$node
# bottom → top like paper: first node at bottom
node_levels <- unname(lab_map[nodes])
node_levels[is.na(node_levels)] <- nodes[is.na(unname(lab_map[nodes]))]
plot_df$node_lab <- factor(plot_df$node_lab, levels = node_levels)
plot_df$measure <- factor(plot_df$measure, levels = meas, labels = unname(meas_lab[meas]))
plot_df$class_lab <- factor(
  unname(.class_lab[plot_df$class]),
  levels = unname(.class_lab[tags])
)

p <- ggplot(plot_df, aes(x = z, y = node_lab, group = 1)) +
  geom_vline(xintercept = 0, colour = "grey70", linewidth = 0.3) +
  geom_path(colour = "grey25", linewidth = 0.55) +
  geom_point(size = 1.7, colour = "black") +
  facet_grid(class_lab ~ measure, scales = "free_x") +
  labs(x = NULL, y = NULL) +
  theme_bw(base_family = ff, base_size = 10) +
  theme(
    strip.text.y = element_text(angle = 0, hjust = 0, face = "bold", size = 8.5, family = ff),
    strip.text.x = element_text(face = "bold", size = 10, family = ff),
    strip.background = element_rect(fill = "grey95", colour = "grey70"),
    axis.text = element_text(family = ff, colour = "black", size = 9),
    axis.text.y = element_text(hjust = 1),
    panel.grid.minor = element_blank(),
    panel.spacing = unit(0.35, "lines"),
    plot.margin = margin(6, 8, 6, 6)
  )

out_pdf <- file.path(proj, "summary_results/Figures/pdf")
out_md <- file.path(proj, "summary_results/Figures/image_information")
ws <- file.path(proj, "summary_results_delivery_workspace")
dir.create(out_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(out_md, recursive = TRUE, showWarnings = FALSE)
dir.create(ws, recursive = TRUE, showWarnings = FALSE)

tmp_pdf <- tempfile(fileext = ".pdf")
grDevices::cairo_pdf(tmp_pdf, width = 10.5, height = 8.2, family = ff)
print(p)
grDevices::dev.off()

fig3 <- file.path(out_pdf, "Figure 3. Centrality by LCA class.pdf")
ok <- file.copy(tmp_pdf, fig3, overwrite = TRUE)
if (!isTRUE(ok)) stop("copy Fig3 failed")
unlink(tmp_pdf)
message("wrote ", fig3)

n_str <- paste(sprintf("%s=%s", tags, unlist(ns[tags])), collapse = "; ")
writeLines(c(
  "# Figure 3. Centrality by LCA class",
  "",
  "## 图面说明",
  "",
  paste0(
    "按 LCA 三类分层的网络中心性 3×4 拼图（角色对齐参考文献 Fig 3）。",
    "行：C1/C2/C3；列：Betweenness、Closeness、Strength、Expected Influence。",
    "横轴为各类内 z-score；纵轴为 7 个量表总分节点。",
    "原文为 illness-perception/SOC 条目节点；本图为量表总分节点。"
  ),
  "",
  "## 分析上下文",
  "",
  "- 分层: polytomous LCA K=3（DAS1–12）",
  paste0("- 各类 n: ", n_str),
  "- 节点: 7 个量表总分",
  "- 中心性: qgraph::centrality_auto；类内 z-score",
  "- 数据库: Hospital outpatient",
  ""
), file.path(out_md, "Figure 3. Centrality by LCA class.md"))

# --- Move old Network C1–C3 → Figure S1–S3; renumber ROC/DCA/Heatmap ---
.rename_pair <- function(old_stem, new_stem) {
  for (dir in c(out_pdf, out_md)) {
    ext <- if (identical(dir, out_pdf)) ".pdf" else ".md"
    op <- file.path(dir, paste0(old_stem, ext))
    np <- file.path(dir, paste0(new_stem, ext))
    if (!file.exists(op)) next
    if (file.exists(np) && !identical(op, np)) unlink(np)
    file.rename(op, np)
    message("rename ", basename(op), " → ", basename(np))
  }
}

# archive previous Fig3 Network C1 if still present (before we overwrote role)
old_c1 <- file.path(out_pdf, "Figure 3. Network C1.pdf")
# already replaced by centrality; C1 may have been overwritten if same name — handle C1/C2/C3 nets
for (pair in list(
  c("Figure 3. Network C1", "Figure S1. Network C1"),
  c("Figure 4. Network C2", "Figure S2. Network C2"),
  c("Figure 5. Network C3", "Figure S3. Network C3")
)) {
  .rename_pair(pair[[1]], pair[[2]])
}

# If C1 was overwritten by earlier mistaken naming, redraw S1–S3 from ads quickly
need_s <- c(
  "Figure S1. Network C1.pdf",
  "Figure S2. Network C2.pdf",
  "Figure S3. Network C3.pdf"
)
missing_s <- need_s[!file.exists(file.path(out_pdf, need_s))]
if (length(missing_s)) {
  message("redraw missing S panels: ", paste(missing_s, collapse = ", "))
  for (k in ks) {
    tag <- paste0("C", k)
    sidx <- match(tag, tags)
    fp <- file.path(out_pdf, sprintf("Figure S%d. Network %s.pdf", sidx, tag))
    if (file.exists(fp) && !(basename(fp) %in% missing_s)) next
    sub <- d[!is.na(d[[cls_col]]) & d[[cls_col]] == k, , drop = FALSE]
    fit <- .fit_adj(sub)
    if (is.null(fit$adj)) next
    labs <- unname(lab_map[colnames(fit$adj)])
    labs[is.na(labs)] <- colnames(fit$adj)
    tpdf <- tempfile(fileext = ".pdf")
    grDevices::cairo_pdf(tpdf, width = 6, height = 6, family = ff)
    par(family = ff, mar = c(1, 1, 2.2, 1))
    qgraph::qgraph(
      fit$adj, labels = labs, layout = "spring", theme = "colorblind",
      title = paste0(tag, " (n = ", format(fit$n, big.mark = ","), ")"),
      label.cex = 0.95, vsize = 10
    )
    grDevices::dev.off()
    file.copy(tpdf, fp, overwrite = TRUE)
    unlink(tpdf)
    writeLines(c(
      paste0("# Figure S", sidx, ". Network ", tag),
      "", "## 图面说明", "",
      paste0("LCA ", tag, " 单类 EBICglasso 网络放大图（量表总分节点；主文中心性见 Figure 3）。"),
      "", "## 分析上下文", "",
      paste0("- n: ", fit$n),
      "- 布局: independent spring",
      ""
    ), file.path(out_md, sprintf("Figure S%d. Network %s.md", sidx, tag)))
    message("wrote ", fp)
  }
}

# Renumber main figures after Fig3: ROC 6–9 → 4–7; DCA 10→8; Heatmap 11→9
# Do high numbers first to avoid collisions
renumber <- list(
  c("Figure 11. Correlation Heatmap", "Figure 9. Correlation Heatmap"),
  c("Figure 10. Clinical DCA", "Figure 8. Clinical DCA"),
  c("Figure 9. ROC SSS-8", "Figure 7. ROC SSS-8"),
  c("Figure 8. ROC PHQ-15", "Figure 6. ROC PHQ-15"),
  c("Figure 7. ROC Whiteley-8", "Figure 5. ROC Whiteley-8"),
  c("Figure 6. ROC SSD-12", "Figure 4. ROC SSD-12")
)
for (pair in renumber) .rename_pair(pair[[1]], pair[[2]])

# scrub leftover Network C*.md with old Fig3 title if any
unlink(file.path(out_md, "Figure 3. Network C1.md"))

# Methods: mention Fig3 centrality
methods <- file.path(proj, "summary_results/Methods_statistical_analysis.md")
if (file.exists(methods)) {
  txt <- paste(readLines(methods, warn = FALSE), collapse = "\n")
  if (!grepl("Figure 3.*[Cc]entrality|centrality indices.*Figure 3", txt)) {
    insert <- paste0(
      " Node centrality indices (Betweenness, Closeness, Strength, and Expected Influence) ",
      "were computed within each LCA class and displayed as z-scores in Figure 3 ",
      "(scale-total nodes; role-aligned with the index paper's centrality Figure 3)."
    )
    if (grepl("independent spring layouts", txt)) {
      txt <- sub(
        "(independent spring layouts[^.]*\\.)",
        paste0("\\1", insert),
        txt
      )
    } else if (grepl("Psychological networks", txt)) {
      txt <- sub(
        "(## Psychological networks\\n\\n[^#]+)",
        paste0("\\1", insert, "\n"),
        txt
      )
    }
    writeLines(txt, methods)
    message("Methods patched for Fig3 centrality")
  }
}

message("DONE Fig3 centrality + S1–S3 nets + renumber ROC/DCA/Heatmap")
message("pdf dir:\n", paste(list.files(out_pdf), collapse = "\n"))
