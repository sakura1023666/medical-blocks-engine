#!/usr/bin/env Rscript
# Figure 2: 7 scale-total nodes × LCA C1|C2|C3 three-panel
# Layout: independent spring per class (NOT averageLayout); paper-style bottom captions

suppressPackageStartupMessages(library(qgraph))

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

ks <- sort(unique(stats::na.omit(d[[cls_col]])))
tags <- paste0("C", ks)
ads <- list()
ns <- list()
layouts_in <- list()
for (k in ks) {
  tag <- paste0("C", k)
  sub <- d[!is.na(d[[cls_col]]) & d[[cls_col]] == k, , drop = FALSE]
  fit <- .fit_adj(sub)
  ads[[tag]] <- fit$adj
  ns[[tag]] <- fit$n
  if (!is.null(fit$adj)) layouts_in[[tag]] <- fit$adj
  message(tag, " n=", fit$n, " edges_ok=", !is.null(fit$adj))
}

# deliberately NOT averageLayout — each class gets its own spring layout

out_pdf <- file.path(proj, "summary_results/Figures/pdf")
out_md <- file.path(proj, "summary_results/Figures/image_information")
ws <- file.path(proj, "summary_results_delivery_workspace")
dir.create(out_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(out_md, recursive = TRUE, showWarnings = FALSE)
dir.create(ws, recursive = TRUE, showWarnings = FALSE)

# archive old Overall-as-Fig2
old2 <- file.path(out_pdf, "Figure 2. Network Overall.pdf")
if (file.exists(old2)) {
  file.copy(old2, file.path(ws, "Figure 2. Network Overall.archived.pdf"), overwrite = TRUE)
  unlink(old2)
}

# Two-line bottom captions (paper-like; not 3-line wraps)
.cap_lines <- list(
  C1 = c("C1: Low Disability \u2013", "Mild Symptom Burden Group"),
  C2 = c("C2: Moderate Disability \u2013", "Elevated Distress Group"),
  C3 = c("C3: High Disability \u2013", "Severe Symptom Burden Group")
)

out_fig2_tmp <- tempfile(fileext = ".pdf")
grDevices::cairo_pdf(out_fig2_tmp, width = 11, height = 4.4, family = ff)
par(mfrow = c(1, length(tags)), family = ff, mar = c(3.6, 0.6, 2.4, 0.6))
for (tag in tags) {
  adj <- ads[[tag]]
  n <- ns[[tag]]
  if (is.null(adj)) {
    plot.new()
    title(main = paste0(tag, " (insufficient n)"))
    next
  }
  labs <- unname(lab_map[colnames(adj)])
  labs[is.na(labs)] <- colnames(adj)
  qgraph::qgraph(
    adj,
    labels = labs,
    layout = "spring",
    theme = "colorblind",
    title = paste0(tag, " (n = ", format(n, big.mark = ","), ")"),
    title.cex = 1.15,
    label.cex = 0.9,
    vsize = 9
  )
  cap <- .cap_lines[[tag]]
  if (is.null(cap)) cap <- c(tag, "")
  mtext(cap[[1]], side = 1, line = 1.15, cex = 0.95, font = 2, family = ff)
  mtext(cap[[2]], side = 1, line = 2.35, cex = 0.95, font = 2, family = ff)
}
grDevices::dev.off()
out_fig2 <- file.path(out_pdf, "Figure 2. Network by LCA class.pdf")
ok <- file.copy(out_fig2_tmp, out_fig2, overwrite = TRUE)
if (!isTRUE(ok)) stop("copy Fig2 failed: ", out_fig2)
unlink(out_fig2_tmp)
message("wrote ", out_fig2)

# Single-class detail panels as Figure S1–S3 (main Fig 3 = centrality; see redraw_fig3_*)
for (idx in seq_along(tags)) {
  tag <- tags[[idx]]
  adj <- ads[[tag]]
  n <- ns[[tag]]
  if (is.null(adj)) next
  labs <- unname(lab_map[colnames(adj)])
  labs[is.na(labs)] <- colnames(adj)
  fp <- file.path(out_pdf, sprintf("Figure S%d. Network %s.pdf", idx, tag))
  tpdf <- tempfile(fileext = ".pdf")
  grDevices::cairo_pdf(tpdf, width = 6, height = 6, family = ff)
  par(family = ff, mar = c(1, 1, 2.2, 1))
  qgraph::qgraph(
    adj,
    labels = labs,
    layout = "spring",
    theme = "colorblind",
    title = paste0(tag, " (n = ", format(n, big.mark = ","), ")"),
    label.cex = 0.95,
    vsize = 10
  )
  grDevices::dev.off()
  file.copy(tpdf, fp, overwrite = TRUE)
  unlink(tpdf)
}

# Overall as Figure S or keep numbered after networks — put as Figure 2a archived; write Overall as unnumbered archive
fit_o <- .fit_adj(d)
if (!is.null(fit_o$adj)) {
  fp <- file.path(ws, "Figure Network Overall.scale_totals.pdf")
  labs <- unname(lab_map[colnames(fit_o$adj)])
  labs[is.na(labs)] <- colnames(fit_o$adj)
  grDevices::cairo_pdf(fp, width = 6, height = 6, family = ff)
  par(family = ff, mar = c(1, 1, 2.2, 1))
  qgraph::qgraph(
    fit_o$adj,
    labels = labs,
    layout = "spring",
    theme = "colorblind",
    title = paste0("Overall (n = ", format(fit_o$n, big.mark = ","), ")"),
    label.cex = 0.95,
    vsize = 10
  )
  grDevices::dev.off()
}

n_str <- paste(sprintf("%s=%s", tags, unlist(ns[tags])), collapse = "; ")
writeLines(c(
  "# Figure 2. Network by LCA class",
  "",
  "## 图面说明",
  "",
  paste0(
    "按 LCA 三类（C1/C2/C3）分层的 EBICglasso 心理网络三栏拼图。",
    "节点为 7 个量表总分：PHQ-15、SSS-8、SSD-12、Whiteley-8、WHO-DAS、PHQ-9、GAD-7。",
    "角色对齐参考文献 Fig2（按潜剖面分网）；原文为条目节点，本图为量表总分节点。",
    "每栏独立 spring 布局（非 averageLayout）。",
    "图下两行标注：C1 Low Disability – Mild Symptom Burden Group；",
    "C2 Moderate Disability – Elevated Distress Group；",
    "C3 High Disability – Severe Symptom Burden Group。"
  ),
  "",
  "## 分析上下文",
  "",
  "- 分层: polytomous LCA K=3（DAS1–12）",
  paste0("- 各类 n: ", n_str),
  "- 节点: 7 个量表总分",
  "- 布局: independent spring per class",
  "- 估计: EBICglasso, gamma=0.5",
  "- 数据库: Hospital outpatient",
  ""
), file.path(out_md, "Figure 2. Network by LCA class.md"))

# scrub old Overall fig md if present
unlink(file.path(out_md, "Figure 2. Network Overall.md"))

# Methods patch
methods <- file.path(proj, "summary_results/Methods_statistical_analysis.md")
if (file.exists(methods)) {
  txt <- paste(readLines(methods, warn = FALSE), collapse = "\n")
  net_sentence <- paste0(
    "EBICglasso networks (qgraph; γ = 0.5) were estimated within each LCA class (C1–C3) ",
    "using seven scale totals (PHQ-15, SSS-8, SSD-12, Whiteley-8, WHO-DAS, PHQ-9, GAD-7). ",
    "Figure 2 presents the three class-specific networks side-by-side with independent spring layouts ",
    "(role-aligned with the index paper's profile-stratified Figure 2; nodes are scale totals, not items). ",
    "Case-drop bootstrap summarized correlation stability (CS) for strength."
  )
  if (grepl("shared average layout", txt)) {
    txt <- gsub("shared average layout", "independent spring layouts", txt, fixed = TRUE)
    writeLines(txt, methods)
    message("Methods: averageLayout → independent spring")
  } else if (!grepl("independent spring layouts|Network by LCA class", txt)) {
    txt <- sub(
      "EBICglasso networks \\(bootnet/qgraph; γ = 0.5\\) were estimated overall and within LCA classes using scale totals \\(PHQ-15, SSS-8, SSD-12, Whiteley-8, WHO-DAS, PHQ-9, GAD-7\\)\\. Case-drop bootstrap \\(nBoots = 200\\) summarized correlation stability \\(CS\\) for strength\\. Strata below the configured minimum n were skipped for formal network reporting\\.",
      net_sentence,
      txt
    )
    if (!grepl("independent spring layouts", txt)) {
      txt <- sub(
        "(## Psychological networks\\n\\n)([^#]+)",
        paste0("\\1", net_sentence, "\n\n"),
        txt
      )
    }
    writeLines(txt, methods)
    message("Methods updated")
  }
}

message("DONE fig2 panels: ", paste(tags, collapse = ", "))
