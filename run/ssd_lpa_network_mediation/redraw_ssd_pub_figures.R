#!/usr/bin/env Rscript
# 重导 SSD 发表图：Times + 禁下划线展示名
# 从 checkpoints 读数据；写出 summary_results/Figures/pdf

.init <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
sp <- .init()
root <- if (basename(sp) == "ssd_lpa_network_mediation") {
  normalizePath(file.path(sp, "..", ".."), winslash = "/")
} else sp
setwd(root)
source(file.path(root, "R/utils.R"))
`%||%` <- function(a, b) if (!is.null(a)) a else b

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) proj <- normalizePath(args[[i + 1L]], winslash = "/")

out_pdf <- file.path(proj, "summary_results", "Figures", "pdf")
out_md <- file.path(proj, "summary_results", "Figures", "image_information")
dir.create(out_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(out_md, recursive = TRUE, showWarnings = FALSE)

ff <- "Times New Roman"
# 若系统无 TNR，回退 Liberation Serif
ff <- tryCatch({
  tmp <- tempfile(fileext = ".pdf")
  grDevices::cairo_pdf(tmp, width = 1, height = 1, family = "Times New Roman")
  grDevices::dev.off(); unlink(tmp); "Times New Roman"
}, error = function(e) "Liberation Serif")
message("font: ", ff)

# 取最新有数据的 checkpoint
ck_candidates <- c(
  "step10_correlation.rds",
  "step09_clinical_threshold_dca.rds",
  "step08_complex_network_profile_batch.rds",
  "step07_parallel_competing_mediation.rds",
  "step06_sem_cfa_discriminant.rds",
  "step04_latent_profile_tidylpa.rds"
)
ck <- NULL
for (nm in ck_candidates) {
  p <- file.path(proj, "checkpoints", nm)
  if (file.exists(p)) {
    ck <- readRDS(p)
    message("checkpoint: ", nm)
    break
  }
}
if (is.null(ck)) stop("无可用 checkpoint")
d <- ck$ctx$data$cleaned %||% ck$ctx$data$imputed
stopifnot(is.data.frame(d))

.pdf_dev <- function(path, w = 8, h = 6) {
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(path, width = w, height = h, family = ff)
  } else {
    grDevices::pdf(path, width = w, height = h)
  }
}

# --- LCA profiles (primary: LCA_class; alias LPA_class) ---
items <- paste0("DAS", 1:12)
items <- items[items %in% names(d)]
cls <- if ("LCA_class" %in% names(d)) d$LCA_class else d$LPA_class
ok <- stats::complete.cases(d[items]) & !is.na(cls)
Xc <- as.data.frame(lapply(d[items][ok, , drop = FALSE], as.numeric))
cls <- as.integer(cls[ok])
means <- lapply(sort(unique(cls)), function(k) colMeans(Xc[cls == k, , drop = FALSE], na.rm = TRUE))
plot_df <- do.call(rbind, lapply(seq_along(means), function(i) {
  data.frame(
    class = paste0("C", sort(unique(cls))[i]),
    item = names(means[[i]]),
    mean = as.numeric(means[[i]]),
    stringsAsFactors = FALSE
  )
}))
p_lpa <- ggplot2::ggplot(plot_df, ggplot2::aes(item, mean, group = class, colour = class)) +
  ggplot2::geom_line(linewidth = 0.7) + ggplot2::geom_point(size = 1.6) +
  ggplot2::theme_bw(base_family = ff) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, family = ff),
                 text = ggplot2::element_text(family = ff)) +
  ggplot2::labs(title = paste0("LCA class profiles (K=", length(unique(cls)), ")"),
                y = "Item mean", x = NULL, colour = "Class")
ggplot2::ggsave(file.path(out_pdf, "Figure 1. LCA profiles.pdf"), p_lpa, width = 9, height = 5, device = grDevices::cairo_pdf)

# --- Networks ---
nodes <- c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7")
nodes <- nodes[nodes %in% names(d)]
lab_map <- c(
  PHQ15 = "PHQ-15", SSS8 = "SSS-8", SSD12 = "SSD-12", Whiteley8 = "Whiteley-8",
  WHODAS = "WHO-DAS", PHQ9 = "PHQ-9", GAD7 = "GAD-7"
)
.fit_net <- function(df, tag) {
  mat <- as.data.frame(lapply(df[nodes], function(z) suppressWarnings(as.numeric(z))))
  mat <- mat[stats::complete.cases(mat), , drop = FALSE]
  if (nrow(mat) < 30L) return(invisible(NULL))
  adj <- tryCatch(
    qgraph::EBICglasso(stats::cor(mat, use = "pairwise.complete.obs"), n = nrow(mat), gamma = 0.5),
    error = function(e) NULL
  )
  if (is.null(adj)) return(invisible(NULL))
  labs <- unname(lab_map[colnames(adj)])
  labs[is.na(labs)] <- colnames(adj)
  path <- file.path(out_pdf, paste0("Figure Network ", tag, ".pdf"))
  .pdf_dev(path, 8, 8)
  qgraph::qgraph(adj, labels = labs, layout = "spring", theme = "colorblind",
                 title = paste0("Network: ", tag, " (n=", nrow(mat), ")"))
  grDevices::dev.off()
  invisible(TRUE)
}
.net_jobs <- list(Overall = d)
.class_col <- if ("LCA_class" %in% names(d)) "LCA_class" else "LPA_class"
if (.class_col %in% names(d)) {
  for (k in sort(unique(stats::na.omit(d[[.class_col]])))) {
    .net_jobs[[paste0("C", k)]] <- d[!is.na(d[[.class_col]]) & d[[.class_col]] == k, , drop = FALSE]
  }
}
for (nm in names(.net_jobs)) {
  message("network ", nm)
  .fit_net(.net_jobs[[nm]], nm)
}

# --- ROC + DCA ---
preds <- c("SSD12", "Whiteley8", "PHQ15", "SSS8")
preds <- preds[preds %in% names(d)]
yc <- suppressWarnings(as.numeric(d$WHODAS))
thr <- stats::median(yc, na.rm = TRUE)
ybin <- as.integer(yc >= thr)
for (p in preds) {
  x <- suppressWarnings(as.numeric(d[[p]]))
  ok2 <- is.finite(x) & !is.na(ybin)
  rr <- pROC::roc(ybin[ok2], x[ok2], quiet = TRUE, direction = "<")
  auc <- as.numeric(pROC::auc(rr))
  lab <- lab_map[[p]] %||% p
  path <- file.path(out_pdf, paste0("Figure ROC ", lab, ".pdf"))
  .pdf_dev(path, 6, 6)
  par(family = ff)
  plot(rr, main = paste0("ROC: ", lab, " (AUC=", sprintf("%.3f", auc), ")"),
       legacy.axes = TRUE)
  grDevices::dev.off()
}

# DCA
thr_grid <- seq(0.05, 0.95, by = 0.05)
preval <- mean(ybin == 1L, na.rm = TRUE)
dca_rows <- list()
for (p in preds) {
  x <- suppressWarnings(as.numeric(d[[p]]))
  ok2 <- is.finite(x) & !is.na(ybin)
  xs <- x[ok2]; ys <- ybin[ok2]
  rng <- range(xs, na.rm = TRUE)
  if (diff(rng) < .Machine$double.eps) next
  risk <- (xs - rng[1]) / (rng[2] - rng[1])
  lab <- lab_map[[p]] %||% p
  for (pt in thr_grid) {
    pred_pos <- risk >= pt
    tp <- sum(pred_pos & ys == 1L); fp <- sum(pred_pos & ys == 0L); n <- length(ys)
    nb <- tp / n - fp / n * (pt / (1 - pt))
    dca_rows[[length(dca_rows) + 1L]] <- data.frame(
      predictor = lab, threshold = pt, net_benefit = nb, stringsAsFactors = FALSE
    )
  }
}
for (pt in thr_grid) {
  dca_rows[[length(dca_rows) + 1L]] <- data.frame(
    predictor = "Treat all", threshold = pt,
    net_benefit = preval - (1 - preval) * (pt / (1 - pt)), stringsAsFactors = FALSE
  )
  dca_rows[[length(dca_rows) + 1L]] <- data.frame(
    predictor = "Treat none", threshold = pt, net_benefit = 0, stringsAsFactors = FALSE
  )
}
dca_df <- do.call(rbind, dca_rows)
p_dca <- ggplot2::ggplot(dca_df, ggplot2::aes(threshold, net_benefit, colour = predictor)) +
  ggplot2::geom_line(linewidth = 0.6) +
  ggplot2::theme_bw(base_family = ff) +
  ggplot2::theme(text = ggplot2::element_text(family = ff)) +
  ggplot2::labs(title = "Decision curve", x = "Threshold probability",
                y = "Net benefit", colour = NULL)
ggplot2::ggsave(file.path(out_pdf, "Figure clinical DCA.pdf"), p_dca,
                width = 7, height = 5, device = grDevices::cairo_pdf)

# --- Correlation heatmap (if package available) ---
cors_vars <- nodes
cm <- stats::cor(as.data.frame(lapply(d[cors_vars], as.numeric)),
                 use = "pairwise.complete.obs", method = "spearman")
cn <- unname(lab_map[colnames(cm)]); cn[is.na(cn)] <- colnames(cm)
colnames(cm) <- rownames(cm) <- cn
cdf <- as.data.frame(as.table(cm))
names(cdf) <- c("Var1", "Var2", "rho")
p_cor <- ggplot2::ggplot(cdf, ggplot2::aes(Var1, Var2, fill = rho)) +
  ggplot2::geom_tile() +
  ggplot2::scale_fill_gradient2(limits = c(-1, 1), midpoint = 0) +
  ggplot2::theme_bw(base_family = ff) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, family = ff),
                 text = ggplot2::element_text(family = ff)) +
  ggplot2::labs(title = "Spearman correlation (scale totals)", x = NULL, y = NULL, fill = "rho")
ggplot2::ggsave(file.path(out_pdf, "Figure Correlation Heatmap.pdf"), p_cor,
                width = 7, height = 6, device = grDevices::cairo_pdf)

# 删除旧带下划线文件名
old <- list.files(out_pdf, pattern = "_", full.names = TRUE)
if (length(old)) unlink(old)
old_md <- list.files(out_md, pattern = "_", full.names = TRUE)
if (length(old_md)) unlink(old_md)
# 也删旧 Correlation Filtered
unlink(list.files(out_pdf, pattern = "Filtered", full.names = TRUE))

k_star <- length(unique(cls))
# image_information（正文无下划线）
.write_md <- function(stem, face) {
  writeLines(c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    "",
    face,
    "",
    "## 分析上下文",
    "",
    "- 暴露: PHQ-15（症状负荷）",
    "- 中介: SSD-12 与 Whiteley-8（平行）",
    "- 结局: WHO-DAS 12 总分",
    "- 样本量: N=699；LCA 完整病例 n=698",
    paste0("- Grouping: polytomous LCA K=", k_star, "（DAS1–12；poLCA）"),
    "- 数据库: Hospital outpatient",
    "- 拼图: 否（单库）",
    ""
  ), file.path(out_md, paste0(stem, ".md")))
}
for (f in list.files(out_pdf, pattern = "\\.pdf$")) {
  stem <- sub("\\.pdf$", "", f)
  face <- paste0("见图面 PDF「", stem, "」。关键数字见 Tables 中对应结果表。")
  if (grepl("LCA|LPA", stem, ignore.case = TRUE)) {
    face <- paste0("LCA 类别条目均值折线（WHO-DAS × 类别）。主分析 poLCA；锁定 K=", k_star, "。")
  } else if (grepl("Network", stem, ignore.case = TRUE)) {
    face <- "EBICglasso 心理网络（量表总分节点）。标签为 Overall 或 LCA 类别。"
  } else if (grepl("ROC", stem, ignore.case = TRUE)) {
    face <- "ROC：预测因子对 WHO-DAS 中位数二分结局；AUC 见临床 ROC 表。"
  } else if (grepl("DCA", stem, ignore.case = TRUE)) {
    face <- "决策曲线：各预测因子净获益，对照 Treat all / Treat none。"
  } else if (grepl("Correlation", stem, ignore.case = TRUE)) {
    face <- "量表总分 Spearman 相关热图。"
  }
  .write_md(stem, face)
}

message("redraw done → ", out_pdf)
message("pdfs: ", paste(list.files(out_pdf), collapse = " | "))
