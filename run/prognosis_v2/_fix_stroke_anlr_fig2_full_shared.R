#!/usr/bin/env Rscript
# Fig2：共享池全变量（不做 top-k）；单页 = MIMIC 上半 + eICU 下半

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(grid)
  library(Boruta)
})

.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)

.out <- stroke_anlr_out()
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
IDX <- "ANLR"
shared_fs <- readLines(file.path(.tab, "shared_feature_selection_vars.txt"))
bor_list <- readRDS(file.path(.tab, "Boruta_objects.rds"))
shap_df <- as.data.frame(readRDS(file.path(.tab, "SHAP_long.rds")))
mean_tab <- as.data.frame(fread(file.path(.tab, "SHAP_by_database.csv")))
message("shared_fs n=", length(shared_fs), " (full pool, no top-k; single page)")

.lab_disp <- function(x) {
  x <- as.character(x)
  x <- gsub("^Gender(Male|Female)$", "Gender", x)
  x <- gsub("^Race.*$", "Race", x)
  x <- gsub(
    "^(Ventilation|Hypertension|Diabetes|Heart_Failure|Myocardial_Infarction|COPD|Pneumonia|Malignant_Tumor|CKD|Hyperlipidemia|Liver_cirrhosis|Hepatitis)(Yes|No)$",
    "\\1", x
  )
  pipeline_display_label(x)
}
.map_to_base <- function(v) {
  v <- as.character(v)
  hit <- shared_fs[vapply(shared_fs, function(b) identical(v, b) || startsWith(v, b), logical(1))]
  if (length(hit)) hit[[1]] else v
}

.fig2_one <- function(bor, shap_one, mean_one) {
  h <- as.data.frame(bor$ImpHistory)
  h$iter <- seq_len(nrow(h))
  st <- Boruta::attStats(bor)
  real <- intersect(intersect(rownames(st), colnames(h)), shared_fs)
  dec <- setNames(as.character(st$decision), rownames(st))

  box <- do.call(rbind, lapply(real, function(v) {
    data.frame(variable = v, z = h[[v]], stringsAsFactors = FALSE)
  }))
  box$decision <- dec[box$variable]
  box$z[!is.finite(box$z)] <- NA_real_
  med <- tapply(box$z, box$variable, median, na.rm = TRUE)
  box$variable <- factor(.lab_disp(box$variable), levels = .lab_disp(names(sort(med))))
  pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00")
  thA <- theme_classic(base_size = 7) +
    theme(
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 3.6),
      legend.position = "bottom", legend.key.size = unit(0.18, "cm"),
      legend.text = element_text(size = 5),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(-4, 0, 0, 0),
      plot.title = element_text(face = "bold", size = 8),
      plot.margin = margin(1, 2, 0, 1)
    )
  pA <- ggplot(box, aes(variable, z, fill = decision)) +
    geom_boxplot(outlier.size = 0.1, linewidth = 0.18, na.rm = TRUE) +
    scale_fill_manual(values = pal, name = NULL, drop = TRUE) +
    labs(x = NULL, y = "Importance", title = "A") + thA

  lines <- do.call(rbind, lapply(real, function(v) {
    data.frame(iter = h$iter, variable = v, z = h[[v]])
  }))
  lines$group <- ifelse(lines$variable == IDX, "Index", "Other")
  pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
    geom_line(linewidth = 0.18, na.rm = TRUE) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "#4c78a8"), name = NULL) +
    labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
    theme_classic(base_size = 7) +
    theme(
      legend.position = "bottom", legend.key.size = unit(0.18, "cm"),
      legend.text = element_text(size = 5),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(-4, 0, 0, 0),
      plot.title = element_text(face = "bold", size = 8),
      plot.margin = margin(1, 2, 0, 1)
    )

  sh <- as.data.frame(shap_one)
  sh$base <- vapply(as.character(sh$variable), .map_to_base, character(1))
  sh <- sh[sh$base %in% shared_fs, , drop = FALSE]
  sh$group <- ifelse(sh$base == IDX, "Index", "Other")
  ord_raw <- names(sort(tapply(abs(sh$shap), sh$base, mean)))
  sh$variable <- factor(.lab_disp(sh$base), levels = .lab_disp(ord_raw))
  pC <- ggplot(sh, aes(shap, variable, color = group)) +
    geom_jitter(height = 0.06, width = 0, size = 0.08, alpha = 0.28) +
    geom_vline(xintercept = 0, linewidth = 0.18) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "grey55"), name = NULL) +
    labs(x = "SHAP value (log-hazard)", y = NULL, title = "C") +
    theme_classic(base_size = 7) +
    theme(
      axis.text.y = element_text(size = 3.8),
      legend.position = "bottom", legend.key.size = unit(0.18, "cm"),
      legend.text = element_text(size = 5),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(-4, 0, 0, 0),
      plot.title = element_text(face = "bold", size = 8),
      plot.margin = margin(1, 2, 0, 1)
    )

  md <- as.data.frame(mean_one)
  md$base <- vapply(as.character(md$variable), .map_to_base, character(1))
  md <- md[md$base %in% shared_fs, , drop = FALSE]
  md <- aggregate(mean_abs_shap ~ base, md, sum)
  md$group <- ifelse(md$base == IDX, "Index", "Other")
  md$variable <- factor(
    .lab_disp(md$base),
    levels = .lab_disp(names(sort(setNames(md$mean_abs_shap, md$base))))
  )
  pD <- ggplot(md, aes(mean_abs_shap, variable, fill = group)) +
    geom_col(width = 0.72) +
    scale_fill_manual(values = c(Index = "#e74c3c", Other = "grey70"), name = NULL) +
    labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
    theme_classic(base_size = 7) +
    theme(
      axis.text.y = element_text(size = 3.8),
      legend.position = "bottom", legend.key.size = unit(0.18, "cm"),
      legend.text = element_text(size = 5),
      legend.margin = margin(0, 0, 0, 0),
      legend.box.margin = margin(-4, 0, 0, 0),
      plot.title = element_text(face = "bold", size = 8),
      plot.margin = margin(1, 2, 0, 1)
    )

  list(A = pA, B = pB, C = pC, D = pD)
}

.draw_db_block <- function(panels, db_lab, y0, h) {
  grid.text(db_lab, x = 0.02, y = y0 + h - 0.012, just = c("left", "top"),
            gp = gpar(fontsize = 9, fontface = "bold", fontfamily = "Times"))
  # 2x2 within [y0, y0+h]: top A B, bottom C D
  panel_h <- (h - 0.03) / 2
  panel_w <- 0.48
  coords <- list(
    A = c(x = 0.015, y = y0 + panel_h + 0.005),
    B = c(x = 0.505, y = y0 + panel_h + 0.005),
    C = c(x = 0.015, y = y0 + 0.005),
    D = c(x = 0.505, y = y0 + 0.005)
  )
  for (nm in names(coords)) {
    print(panels[[nm]], vp = viewport(
      x = coords[[nm]][["x"]], y = coords[[nm]][["y"]],
      width = panel_w, height = panel_h, just = c("left", "bottom")
    ))
  }
}

fig2 <- file.path(.fig, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
if (file.exists(fig2)) file.remove(fig2)

# 单页：上 MIMIC、下 eICU；加高画布以容纳共享池全变量
cairo_pdf(fig2, width = 10.5, height = 10.8, family = "Times", onefile = TRUE)
grid.newpage()
grid.text(
  sprintf("Shared feature pool (n = %d, all variables)", length(shared_fs)),
  x = 0.98, y = 0.992, just = c("right", "top"),
  gp = gpar(fontsize = 7, fontfamily = "Times", col = "grey30")
)
db_order <- intersect(c("MIMIC", "eICU"), names(bor_list))
if (!length(db_order)) db_order <- names(bor_list)
# 上半 / 下半各留一点顶栏给库名
half <- 0.485
for (i in seq_along(db_order)) {
  nm <- db_order[[i]]
  panels <- .fig2_one(
    bor_list[[nm]],
    shap_df[shap_df$database == nm, , drop = FALSE],
    mean_tab[mean_tab$database == nm, , drop = FALSE]
  )
  y0 <- if (i == 1L) 0.505 else 0.01
  .draw_db_block(panels, nm, y0 = y0, h = half)
}
dev.off()
message("Fig2 rewritten: 1 page, full shared pool n=", length(shared_fs))

writeLines(c(
  "# Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
  "",
  "## 图面说明",
  "单页上下两区：上 MIMIC、下 eICU；每区 A–D（Boruta box / Boruta 轨迹 / SHAP beeswarm / mean |SHAP|）。",
  "特征筛选候选池为双库共同变量，A/C/D **展示该池全部变量**（不做 top-k）。",
  "A 不含 shadow；C/D 将哑变量合并回共享基名；ANLR 标为 Index（红）。",
  paste0("共享池 n=", length(shared_fs), "：", paste(shared_fs, collapse = ", "), "。"),
  "",
  "## 分析上下文",
  "- 暴露: ANLR",
  paste0("- 结局: ", .endpoint),
  "- 数据库: MIMIC + eICU（平权；共享特征池）",
  "- 是否拼图: 单页上下分库"
), file.path(.out, "Figures", "image_information",
             "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.md"))

cfg <- list(pub_figures = list(
  export_png = FALSE, export_tiff = FALSE,
  max_edge_in = 11, stack_pages = TRUE
))
pub_figure_ensure_formats(file.path(.out, "Figures"), config = cfg)
info <- system2("pdfinfo", shQuote(fig2), stdout = TRUE)
message(paste(info[grepl("Pages|Page size", info)], collapse = " | "))
message("done")
