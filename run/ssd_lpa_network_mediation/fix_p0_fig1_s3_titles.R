#!/usr/bin/env Rscript
# P0 fixes for SSD delivery: Fig1 DAS order; Fig S3 labels; Table A1 titles.
# Does not rewrite main Tables 1–6 numeric cells.

suppressPackageStartupMessages({
  library(ggplot2)
  library(openxlsx)
})

.root <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) normalizePath(file.path(dirname(sub("^--file=", "", f[1L])), "../.."), winslash = "/")
  else normalizePath(getwd(), winslash = "/")
})
setwd(.root)
source("R/utils.R")
source("R/pub_figure_export.R")
source("R/pub_xlsx_surgical.R")

sr <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160",
  "by_index", "main_full_sample", "summary_results"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--summary-root", args)
if (!is.na(i) && i < length(args)) sr <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
sr_pdf <- file.path(sr, "Figures", "pdf")
sr_md <- file.path(sr, "Figures", "image_information")
sr_tab <- file.path(sr, "Tables")
dir.create(sr_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(sr_md, recursive = TRUE, showWarnings = FALSE)

ff <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family()
} else {
  "Liberation Serif"
}

.theme_sci <- function(base_size = 10) {
  theme_bw(base_family = ff, base_size = base_size) %+replace%
    theme(
      plot.title = element_text(face = "bold", size = base_size + 1, hjust = 0, family = ff),
      plot.subtitle = element_text(size = base_size - 1, hjust = 0, family = ff, colour = "grey30"),
      axis.title = element_text(family = ff),
      axis.text = element_text(family = ff, colour = "grey10"),
      legend.text = element_text(family = ff),
      legend.title = element_text(family = ff),
      panel.grid.minor = element_blank(),
      strip.background = element_rect(fill = "grey95", colour = NA),
      strip.text = element_text(family = ff, face = "bold")
    )
}

# ── Fig 1: numeric DAS order ───────────────────────────────────────────────
unit <- dirname(sr)
ck_path <- file.path(unit, "checkpoints", "latent_profile_tidylpa.rds")
if (!file.exists(ck_path)) ck_path <- file.path(unit, "checkpoints", "step04_latent_profile_tidylpa.rds")
stopifnot(file.exists(ck_path))
ck <- readRDS(ck_path)
d <- NULL
if (is.list(ck) && !is.null(ck$ctx$data)) {
  d <- ck$ctx$data$cleaned %||% ck$ctx$data$imputed %||% ck$ctx$data$mapped
} else if (is.data.frame(ck)) {
  d <- ck
}
stopifnot(!is.null(d), is.data.frame(d))

items <- paste0("DAS", 1:12)
items <- items[items %in% names(d)]
cls_col <- if ("LCA_class" %in% names(d)) {
  "LCA_class"
} else if ("LPA_class" %in% names(d)) {
  "LPA_class"
} else {
  NA_character_
}
stopifnot(!is.na(cls_col))
cls_raw <- d[[cls_col]]
ok <- stats::complete.cases(d[items]) & !is.na(cls_raw)
Xc <- as.data.frame(lapply(d[items][ok, , drop = FALSE], function(z) suppressWarnings(as.numeric(z))))
cls <- as.integer(factor(cls_raw[ok]))
ks <- sort(unique(cls))
means <- lapply(ks, function(k) colMeans(Xc[cls == k, , drop = FALSE], na.rm = TRUE))
plot_df <- do.call(rbind, lapply(seq_along(means), function(i) {
  data.frame(
    class = paste0("C", ks[i]),
    item = factor(names(means[[i]]), levels = items),
    mean = as.numeric(means[[i]]),
    stringsAsFactors = FALSE
  )
}))
p1 <- ggplot(plot_df, aes(item, mean, group = class, colour = class)) +
  geom_line(linewidth = 0.75) +
  geom_point(size = 1.8) +
  scale_colour_manual(values = c(C1 = "#D55E00", C2 = "#009E73", C3 = "#0072B2")) +
  labs(
    title = paste0("LCA class profiles (K=", length(ks), ")"),
    subtitle = "WHO-DAS items in numeric order (DAS1–DAS12)",
    y = "Item mean", x = NULL, colour = "Class"
  ) +
  .theme_sci(10) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, family = ff))
ggsave(
  file.path(sr_pdf, "Figure 1. LCA profiles.pdf"),
  p1, width = 9, height = 5, device = grDevices::cairo_pdf
)
writeLines(c(
  "# Figure 1. LCA profiles",
  "",
  "## 图面说明",
  paste0(
    "LCA 三类（K=", length(ks), "）在 WHO-DAS 条目上的均分折线。",
    "横轴按 DAS1–DAS12 数值顺序（非字母序）。",
    "C1 低残疾、C2 中度、C3 高残疾。"
  ),
  "",
  "## 分析上下文",
  "- 暴露: PHQ-15（症状负荷）",
  "- 中介: SSD-12 ∥ Whiteley-8",
  "- 结局: WHO-DAS 12 总分",
  "- 样本量: N≈699；LCA 完整病例 n=698",
  "- Grouping: polytomous LCA K*=3 on DAS items (poLCA)",
  "- 数据库: Hospital outpatient",
  "- 拼图: 否（单库）"
), file.path(sr_md, "Figure 1. LCA profiles.md"))
message("Fig1 redrawn with numeric DAS order")

# ── Fig S3 from Table S4 Block B ───────────────────────────────────────────
s4p <- file.path(sr_tab, "Table S4. Moderated mediation.xlsx")
s4 <- openxlsx::read.xlsx(s4p, colNames = TRUE, startRow = 2)
if (!"Block" %in% names(s4)) {
  s4 <- openxlsx::read.xlsx(s4p, colNames = TRUE)
}
b <- s4[grepl("^B\\.", as.character(s4$Block)), , drop = FALSE]
# drop footnote-like rows (missing Estimate)
est_col <- if ("Estimate" %in% names(b)) "Estimate" else if ("ACME" %in% names(b)) "ACME" else NA
lev_col <- if ("Level.or.path" %in% names(b)) "Level.or.path" else if ("Level_or_path" %in% names(b)) "Level_or_path" else if ("Level" %in% names(b)) "Level" else NA
stopifnot(!is.na(est_col), !is.na(lev_col), "Moderator" %in% names(b))
b[[est_col]] <- suppressWarnings(as.numeric(b[[est_col]]))
b <- b[is.finite(b[[est_col]]), , drop = FALSE]
b$LLCI <- suppressWarnings(as.numeric(b$LLCI))
b$ULCI <- suppressWarnings(as.numeric(b$ULCI))
b$n <- suppressWarnings(as.integer(b$n))
# display labels: Moderator — Level (n=)
.mod_lab <- function(m) {
  m <- as.character(m)
  m <- gsub("PHQ9 high", "PHQ-9", m, fixed = TRUE)
  m <- gsub("GAD7 high", "GAD-7", m, fixed = TRUE)
  m <- gsub("PHQ9", "PHQ-9", m, fixed = TRUE)
  m <- gsub("GAD7", "GAD-7", m, fixed = TRUE)
  m <- gsub("Pain predominant", "Pain-predominant", m, fixed = TRUE)
  m <- gsub("_", " ", m, fixed = TRUE)
  m
}
.lev_lab <- function(L, mod) {
  L <- as.character(L)
  L <- gsub("_", " ", L, fixed = TRUE)
  # drop redundant moderator echo in level (e.g. "SSD Yes", "PHQ-9 high")
  for (tok in c(mod, "SSD", "PHQ-9", "GAD-7", "Persistent", "Pain")) {
    L <- sub(paste0("^", gsub("([\\W])", "\\\\\\1", tok), "\\s+"), "", L, ignore.case = TRUE, perl = TRUE)
  }
  L <- trimws(L)
  if (!nzchar(L)) L <- as.character(L)
  L
}
forest <- data.frame(
  label = {
    mods <- .mod_lab(b$Moderator)
    levs <- vapply(seq_len(nrow(b)), function(i) .lev_lab(b[[lev_col]][i], mods[i]), character(1))
    sprintf("%s: %s (n = %s)", mods, levs, format(b$n, big.mark = "", trim = TRUE))
  },
  est = b[[est_col]],
  lo = b$LLCI,
  hi = b$ULCI,
  txt = sprintf("%.3f (%.3f, %.3f)", b[[est_col]], b$LLCI, b$ULCI),
  stringsAsFactors = FALSE
)
forest$label <- factor(forest$label, levels = rev(forest$label))
xmax <- max(forest$hi, na.rm = TRUE) * 1.05
# left forest + right text as annotation outside panel via cowplot-like dual
p_left <- ggplot(forest, aes(est, label)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40", linewidth = 0.4) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.18, linewidth = 0.55, colour = "grey25") +
  geom_point(shape = 22, size = 2.4, fill = "#D55E00", colour = "grey20", stroke = 0.35) +
  scale_x_continuous(limits = c(min(0, min(forest$lo, na.rm = TRUE) - 0.02), xmax), expand = c(0.02, 0)) +
  labs(
    title = "Figure S3. Stratified indirect effects",
    subtitle = "PHQ-15 to SSD-12 to WHO-DAS | bootstrap ACME (95% CI)",
    x = "ACME", y = NULL
  ) +
  .theme_sci(9) +
  theme(
    panel.grid.major.y = element_blank(),
    plot.margin = margin(8, 4, 8, 8)
  )
p_right <- ggplot(forest, aes(x = 1, y = label)) +
  geom_text(aes(label = txt), hjust = 0, size = 2.7, family = ff) +
  scale_x_continuous(limits = c(1, 1.55)) +
  labs(title = " ", subtitle = "ACME (95% CI)", x = NULL, y = NULL) +
  .theme_sci(9) +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.border = element_blank(),
    panel.grid = element_blank(),
    plot.margin = margin(8, 8, 8, 0)
  )
# combine with patchwork or base
if (requireNamespace("patchwork", quietly = TRUE)) {
  pS3 <- p_left + p_right + patchwork::plot_layout(widths = c(3.2, 1.35))
} else {
  # fallback: annotate text inside with clip off
  pS3 <- p_left +
    geom_text(aes(x = xmax * 1.02, label = txt), hjust = 0, size = 2.6, family = ff) +
    coord_cartesian(clip = "off") +
    theme(plot.margin = margin(8, 80, 8, 8))
}
h <- max(4.4, 0.38 * nrow(forest) + 1.6)
ggsave(
  file.path(sr_pdf, "Figure S3. Stratified mediation ACME forest.pdf"),
  pS3, width = 9.2, height = h, device = grDevices::cairo_pdf
)
writeLines(c(
  "# Figure S3. Stratified mediation ACME forest",
  "",
  "## 图面说明",
  "按调节变量分层的间接效应（ACME）森林图；左侧为点估计与 95% CI，右侧为数值。",
  "分层标签格式为「调节变量: 水平 (n = …)」，与 Table S4 Block B 同源。",
  "",
  "### 图上标注",
  paste0("- ", forest$label[length(forest$label):1], ": ", rev(forest$txt), collapse = "\n"),
  "",
  "## 分析上下文",
  "- 路径: PHQ-15 → SSD-12 → WHO-DAS",
  "- 推断: nonparametric bootstrap ACME",
  "- 对应表: Table S4 Block B",
  "- 数据库: Hospital outpatient"
), file.path(sr_md, "Figure S3. Stratified mediation ACME forest.md"))
message("Fig S3 redrawn from Table S4 Block B")

# ── Sync A1 titles to filenames (surgical) ─────────────────────────────────
if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
  tryCatch(
    pub_sync_xlsx_a1_titles_to_filenames(sr_tab),
    error = function(e) message("title sync: ", conditionMessage(e))
  )
} else {
  # manual: Table 3
  t3 <- file.path(sr_tab, "Table 3. Multivariate analysis of LCA membership.xlsx")
  if (file.exists(t3) && exists("pub_xlsx_edit_cells", mode = "function")) {
    pub_xlsx_edit_cells(t3, data.frame(
      row = 1L, col = 1L,
      value = "Table 3. Multivariate analysis of LCA membership.",
      stringsAsFactors = FALSE
    ))
  }
}

# ensure formats
if (exists("pub_figure_ensure_formats", mode = "function")) {
  pub_figure_ensure_formats(file.path(sr, "Figures"), config = list(
    pub_figures = list(export_png = FALSE, export_tiff = FALSE)
  ))
}

message("P0 fig/title fixes done: ", sr)
