#!/usr/bin/env Rscript
# Fig2 去重叠：共享特征池；每库一页 A–D；无 shadow；SHAP 合并到基名

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
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
IDX <- "ANLR"
shared_fs <- readLines(file.path(.tab, "shared_feature_selection_vars.txt"))
bor_list <- readRDS(file.path(.tab, "Boruta_objects.rds"))
shap_df <- as.data.frame(readRDS(file.path(.tab, "SHAP_long.rds")))
mean_tab <- as.data.frame(fread(file.path(.tab, "SHAP_by_database.csv")))
message("shared_fs n=", length(shared_fs))

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
  ord <- names(sort(med))
  box$variable <- factor(.lab_disp(box$variable), levels = .lab_disp(ord))
  pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00")
  thA <- theme_classic(base_size = 9) +
    theme(
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 5.5),
      axis.title = element_text(size = 8),
      plot.title = element_text(face = "bold", size = 10),
      legend.position = "bottom",
      legend.key.size = unit(0.28, "cm"),
      legend.text = element_text(size = 7),
      plot.margin = margin(6, 8, 4, 6)
    )
  pA <- ggplot(box, aes(variable, z, fill = decision)) +
    geom_boxplot(outlier.size = 0.2, linewidth = 0.25, na.rm = TRUE) +
    scale_fill_manual(values = pal, name = NULL, drop = TRUE) +
    labs(x = NULL, y = "Importance", title = "A") + thA

  lines <- do.call(rbind, lapply(real, function(v) {
    data.frame(iter = h$iter, variable = v, z = h[[v]])
  }))
  lines$group <- ifelse(lines$variable == IDX, "Index", "Other")
  pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
    geom_line(linewidth = 0.28, na.rm = TRUE) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "#4c78a8"), name = NULL) +
    labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
    theme_classic(base_size = 9) +
    theme(
      legend.position = "bottom", legend.key.size = unit(0.28, "cm"),
      plot.title = element_text(face = "bold", size = 10),
      plot.margin = margin(6, 8, 4, 6)
    )

  sh <- as.data.frame(shap_one)
  sh$base <- vapply(as.character(sh$variable), .map_to_base, character(1))
  sh <- sh[sh$base %in% shared_fs, , drop = FALSE]
  sh$group <- ifelse(sh$base == IDX, "Index", "Other")
  ord_raw <- names(sort(tapply(abs(sh$shap), sh$base, mean)))
  sh$variable <- factor(.lab_disp(sh$base), levels = .lab_disp(ord_raw))
  pC <- ggplot(sh, aes(shap, variable, color = group)) +
    geom_jitter(height = 0.12, width = 0, size = 0.18, alpha = 0.35) +
    geom_vline(xintercept = 0, linewidth = 0.25) +
    scale_color_manual(values = c(Index = "#e74c3c", Other = "grey55"), name = NULL) +
    labs(x = "SHAP value (log-hazard)", y = NULL, title = "C") +
    theme_classic(base_size = 9) +
    theme(
      axis.text.y = element_text(size = 6.5),
      legend.position = "bottom", legend.key.size = unit(0.28, "cm"),
      plot.title = element_text(face = "bold", size = 10),
      plot.margin = margin(6, 8, 4, 6)
    )

  md <- as.data.frame(mean_one)
  md$base <- vapply(as.character(md$variable), .map_to_base, character(1))
  md <- md[md$base %in% shared_fs, , drop = FALSE]
  md <- aggregate(mean_abs_shap ~ base, md, sum)
  md$group <- ifelse(md$base == IDX, "Index", "Other")
  ord_md <- names(sort(setNames(md$mean_abs_shap, md$base)))
  md$variable <- factor(.lab_disp(md$base), levels = .lab_disp(ord_md))
  pD <- ggplot(md, aes(mean_abs_shap, variable, fill = group)) +
    geom_col(width = 0.72) +
    scale_fill_manual(values = c(Index = "#e74c3c", Other = "grey70"), name = NULL) +
    labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
    theme_classic(base_size = 9) +
    theme(
      axis.text.y = element_text(size = 6.5),
      legend.position = "bottom", legend.key.size = unit(0.28, "cm"),
      plot.title = element_text(face = "bold", size = 10),
      plot.margin = margin(6, 8, 4, 6)
    )

  list(A = pA, B = pB, C = pC, D = pD)
}

fig2 <- file.path(.fig, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
if (file.exists(fig2)) file.remove(fig2)

cairo_pdf(fig2, width = 10.5, height = 6.4, family = "Times", onefile = TRUE)
for (nm in names(bor_list)) {
  panels <- .fig2_one(
    bor_list[[nm]],
    shap_df[shap_df$database == nm, , drop = FALSE],
    mean_tab[mean_tab$database == nm, , drop = FALSE]
  )
  grid.newpage()
  grid.text(nm, x = 0.02, y = 0.985, just = c("left", "top"),
            gp = gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
  grid.text(
    sprintf("Shared feature pool (n = %d)", length(shared_fs)),
    x = 0.98, y = 0.985, just = c("right", "top"),
    gp = gpar(fontsize = 7.5, fontfamily = "Times", col = "grey30")
  )
  for (j in seq_along(panels)) {
    col <- if (j %% 2L == 1L) 0 else 1
    row <- if (j <= 2L) 1 else 0
    print(panels[[j]], vp = viewport(
      x = 0.015 + col * 0.495, y = 0.02 + row * 0.46,
      width = 0.48, height = 0.455, just = c("left", "bottom")
    ))
  }
}
dev.off()
message("Fig2 OK pages=2 shared_fs=", length(shared_fs))

writeLines(c(
  "# Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
  "",
  "## 图面说明",
  "两页（MIMIC / eICU），每页 A–D：A Boruta 重要性；B Z-score 轨迹；C SHAP 蜂群；D mean |SHAP|。",
  paste0("特征筛选候选池为双库共同变量 n=", length(shared_fs), "（两侧同一名单）。"),
  "A 不含 shadow；C/D 将哑变量合并回共享基名。每库单独一页，避免轴标签重叠。",
  "",
  "## 分析上下文",
  "- 暴露: ANLR",
  "- 结局: 28-day all-cause mortality",
  paste0("- 共享特征池: ", paste(shared_fs, collapse = ", ")),
  "- 数据库: MIMIC + eICU",
  "- 是否拼图: 多页（每库一页）"
), file.path(.out, "Figures", "image_information",
             "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.md"))

# 多页 PDF：stack 成单页会破坏版式；此处保留 2 页并放宽几何检
pub_figure_ensure_formats(
  file.path(.out, "Figures"),
  config = list(pub_figures = list(
    export_png = FALSE, export_tiff = FALSE,
    max_edge_in = 11, stack_pages = FALSE
  ))
)
info <- system2("pdfinfo", shQuote(fig2), stdout = TRUE)
message(paste(info[grepl("Pages|Page size", info)], collapse = " | "))
message("done")
