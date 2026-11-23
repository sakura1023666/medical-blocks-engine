#!/usr/bin/env Rscript
# 期刊投稿版：拼合主文图 + 精简附表 + 三线表美化
# 源数字来自 summary（new）最新 Tables / 工作簿重算；不强制对齐报告标题值。
suppressPackageStartupMessages({
  library(openxlsx); library(ggplot2); library(patchwork); library(scales)
  library(survival); library(cmprsk); library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
.get_arg <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i) || i >= length(args)) default else args[[i + 1L]]
}
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/npc_ebv_pet_joint_analysis.R"))
if (file.exists(file.path(root, "R/utils.R"))) {
  tryCatch(source(file.path(root, "R/utils.R"), local = FALSE), error = function(e) NULL)
}

out_root <- .get_arg("--out", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
arch_tbl <- file.path(out_root, "_archive_pre_pub_20261118", "Tables")
src_tbl <- if (dir.exists(arch_tbl)) arch_tbl else file.path(out_root, "Tables")
workbook <- .get_arg("--workbook", "/mnt/g/02block_result/53_NPC/ml_40395549/DATA/鼻咽癌EBV_PETCT数据表(1).xlsx")

fd <- file.path(out_root, "Figures", "pdf")
mddir <- file.path(out_root, "Figures", "image_information")
td <- file.path(out_root, "Tables")
dir.create(fd, FALSE, TRUE); dir.create(mddir, FALSE, TRUE); dir.create(td, FALSE, TRUE)

# wipe current delivery figs/tables (archived already)
unlink(list.files(fd, full.names = TRUE))
unlink(list.files(mddir, full.names = TRUE))
unlink(list.files(td, pattern = "\\.xlsx$", full.names = TRUE))

font <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family("Times New Roman")
} else "Times"

# ---- Journal theme ----
pal <- list(
  blue = "#1F4E79", blue2 = "#2E75B6", blue3 = "#5B9BD5",
  red = "#C00000", green = "#548235", grey = "#595959",
  fill = c("#1F4E79", "#2E75B6", "#5B9BD5", "#9DC3E6", "#C00000", "#548235", "#833C0C")
)
theme_pub <- function(base = 10) {
  theme_classic(base_family = font, base_size = base) %+replace%
    theme(
      plot.title = element_text(face = "bold", size = base + 1, hjust = 0, margin = margin(b = 4)),
      plot.subtitle = element_text(size = base - 1, color = pal$grey, hjust = 0, margin = margin(b = 6)),
      axis.title = element_text(size = base),
      axis.text = element_text(size = base - 1, color = "black"),
      legend.title = element_blank(),
      legend.position = "bottom",
      legend.text = element_text(size = base - 1),
      strip.background = element_blank(),
      strip.text = element_text(face = "bold", size = base),
      plot.margin = margin(6, 8, 4, 6),
      axis.line = element_line(linewidth = 0.4, color = "black"),
      axis.ticks = element_line(linewidth = 0.3)
    )
}
theme_set(theme_pub())

save_pdf <- function(path, plot, w = 7.2, h = 5.0) {
  if (file.exists(path)) unlink(path)
  opened <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    opened <- tryCatch({
      grDevices::cairo_pdf(path, width = w, height = h, family = "Times New Roman"); TRUE
    }, error = function(e) FALSE)
  }
  if (!isTRUE(opened)) grDevices::pdf(path, width = w, height = h, family = font, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  print(plot)
}
write_md <- function(stem, face, ctx) {
  writeLines(c(paste0("# ", stem), "", "## 图面说明", face, "", "## 分析上下文", ctx),
             file.path(mddir, paste0(stem, ".md")), useBytes = TRUE)
}

rd <- function(f, startRow = 1L) {
  p <- file.path(src_tbl, f)
  if (!file.exists(p)) stop("Missing source table: ", f)
  x <- read.xlsx(p, startRow = startRow)
  if (ncol(x) > 1 && all(is.na(x[[1]]))) x <- x[, -1, drop = FALSE]
  # title row baked as colnames -> second row is real header
  if (nrow(x) >= 1 && grepl("^Table\\.|Endpoint|Characteristic", paste(names(x)[1], collapse = ""), ignore.case = TRUE)) {
    if (tolower(as.character(x[1, 1])) %in% c("endpoint", "characteristic", "cohort", "stratum", "item", "metric", "set", "scenario", "contrast", "model", "variable", "term")) {
      hdr <- as.character(unlist(x[1, , drop = TRUE]))
      x <- x[-1, , drop = FALSE]
      names(x) <- make.names(hdr, unique = TRUE)
    }
  }
  x
}
rd_s8 <- function() read.xlsx(file.path(src_tbl, "Table S8. Apparent AUC cohort A and B.xlsx"), startRow = 2)

parse_hr <- function(s) {
  m <- regexec("([0-9.]+)\\s*\\(([0-9.]+),\\s*([0-9.]+)\\)", as.character(s))
  r <- regmatches(as.character(s), m)[[1]]
  if (length(r) < 4) return(c(hr = NA_real_, lo = NA_real_, hi = NA_real_))
  c(hr = as.numeric(r[2]), lo = as.numeric(r[3]), hi = as.numeric(r[4]))
}

write_booktabs <- function(df, path, title, footnotes = NULL) {
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch({
      sci_xlsx_single_header_booktabs(
        filepath = path, title = title, df_body = df,
        footnotes = footnotes
      )
      return(invisible(TRUE))
    }, error = function(e) NULL)
  }
  wb <- createWorkbook(); addWorksheet(wb, "Table")
  writeData(wb, 1, title, 1, 1)
  writeData(wb, 1, df, 2, 1)
  addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 12, textDecoration = "bold"), 1, 1)
  if (nrow(df) && ncol(df)) {
    addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 10),
             rows = 2:(nrow(df) + 2), cols = 1:ncol(df), gridExpand = TRUE)
  }
  if (length(footnotes)) {
    r0 <- nrow(df) + 4L
    for (i in seq_along(footnotes)) writeData(wb, 1, footnotes[[i]], r0 + i - 1L, 1)
  }
  saveWorkbook(wb, path, overwrite = TRUE)
}

.message <- function(...) cat(sprintf(...), "\n", sep = "")

# ========================= data =========================
raw <- npc_ebv_pet_read_analysis_df(workbook)
dfA <- raw; dfB <- raw[as.integer(raw$include) == 1L, ]; rownames(dfB) <- NULL
lamA <- npc_ebv_pet_penalty_lambda("A")

t2 <- rd("Table 2. Nested models 24-36 month IPCW-AUC across endpoints.xlsx")
t3 <- rd("Table 3. Distant-metastasis paired delta AUC.xlsx")
t4 <- rd("Table 4. Adjusted HRs for EBV and PET markers across endpoints.xlsx")
t5 <- rd("Table 5. Landmark trajectory T2 incremental AUC.xlsx")
s3 <- rd("Table S3. Temporal holdout DM AUC.xlsx")
s4 <- rd("Table S4. Decision-curve net benefit DM 36-month.xlsx")
s5 <- rd("Table S5. EBV PET RERI for distant metastasis.xlsx")
s5b <- rd("Table S5b. Quadrant counts authenticity note.xlsx")
s6 <- rd("Table S6. Sensitivity analyses AUC.xlsx")
s9 <- rd("Table S9. Univariate Cox HR three endpoints.xlsx")
s12 <- rd("Table S12. Competing-risk CIF absolute risks.xlsx")
s16 <- rd("Table S16. Cohort A M0-M4 apparent AUC.xlsx")
s17 <- rd("Table S17. Partial Spearman EBV vs PET.xlsx")
s18 <- rd("Table S18. Risk-score strata with locked cutoffs.xlsx")
s23 <- rd("Table S23. Biological relapse diagnostic performance.xlsx")
s29 <- rd("Table S29. Landmark T2 five-endpoint delta AUC.xlsx")
s31 <- rd("Table S31. Temporal holdout calibration.xlsx")
s8 <- rd_s8()

# ========================= helper plots =========================
forest_from_hrdf <- function(d, title, subtitle = NULL, xlim = NULL) {
  d$lab <- factor(d$lab, levels = rev(unique(d$lab)))
  p <- ggplot(d, aes(hr, lab)) +
    geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.35) +
    geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.18, orientation = "y",
                  color = pal$blue, linewidth = 0.45) +
    geom_point(size = 1.9, color = pal$blue) +
    scale_x_log10(breaks = c(0.25, 0.5, 1, 2, 4, 8)) +
    labs(title = title, subtitle = subtitle, x = "HR (95% CI)", y = NULL) +
    theme_pub(9)
  if (!is.null(xlim)) p <- p + coord_cartesian(xlim = xlim)
  p
}

# ========================= FIGURE 1: EBV coding =========================
# Rebuild compact coding figure from data
lod_vec <- as.character(dfB$lod)
if (!length(lod_vec) || all(is.na(lod_vec))) lod_vec <- as.character(dfB$lod_cat)
lod_tab <- as.data.frame(table(lod_vec, useNA = "no"), stringsAsFactors = FALSE)
names(lod_tab) <- c("LOD", "n")
lod_tab$n <- as.integer(lod_tab$n)
lod_tab <- lod_tab[order(-lod_tab$n), , drop = FALSE]
lod_tab$LOD <- factor(lod_tab$LOD, levels = lod_tab$LOD)
p1a <- ggplot(lod_tab, aes(LOD, n)) +
  geom_col(fill = pal$blue, width = 0.72) +
  geom_text(aes(label = n), vjust = -0.35, size = 2.8, family = font) +
  labs(title = "Recorded LOD counts", x = "LOD (copies/mL)", y = "Patients") +
  theme_pub(9) + theme(axis.text.x = element_text(angle = 30, hjust = 1))

# relative dose curves schematic: log10(1+v/LOD) vs absolute for LODs
v <- 10^seq(1, 6, length.out = 200)
lods <- sort(unique(as.numeric(as.character(dfB$lod))))
lods <- lods[is.finite(lods) & lods > 0]
if (!length(lods)) lods <- c(500, 1000, 5000)
curve_df <- do.call(rbind, lapply(lods, function(L) {
  data.frame(v = v, y = log10(1 + v / L), LOD = factor(L))
}))
p1b <- ggplot(curve_df, aes(v, y, color = LOD)) +
  geom_hline(yintercept = log10(2), linetype = 2, color = "grey50", linewidth = 0.35) +
  geom_line(linewidth = 0.55) +
  scale_x_log10(labels = label_number(scale_cut = cut_si(""))) +
  scale_color_manual(values = pal$fill[seq_along(lods)]) +
  labs(title = "Relative dose curves", x = "Absolute EBV DNA", y = "log10(1+v/LOD)") +
  theme_pub(9)

p1c <- ggplot(dfB, aes(x = t0_score)) +
  geom_histogram(bins = 28, fill = pal$blue2, color = "white", linewidth = 0.15) +
  labs(title = "Normalized T0 score", x = "T0 relative score", y = "Count") +
  theme_pub(9)

f1 <- (p1a | p1b | p1c) + plot_annotation(
  title = "Figure 1. EBV DNA LOD-relative coding",
  theme = theme(plot.title = element_text(face = "bold", family = font, size = 12))
)
stem1 <- "Figure 1. EBV DNA LOD-relative coding"
save_pdf(file.path(fd, paste0(stem1, ".pdf")), f1, 10.5, 3.6)
write_md(stem1, "A LOD人数；B 相对化剂量曲线（虚线=达阈 log10(2)）；C T0归一分数分布。",
         "队列B N=391；病例级相对阈值编码。")

# ========================= FIGURE 2: correlation + trajectory overview =========================
# heatmap from S17 (partial) + simple traj counts if available
s17$rho <- as.numeric(s17$rho); s17$q <- as.numeric(s17$q)
s17$lab <- sprintf("%.2f", s17$rho)
p2a <- ggplot(s17, aes(X, Y, fill = rho)) +
  geom_tile(color = "white", linewidth = 0.4) +
  geom_text(aes(label = lab), size = 2.6, family = font) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0,
                       name = "Partial rho") +
  labs(title = "Partial Spearman (EBV vs PET)", x = NULL, y = NULL) +
  theme_pub(9) + theme(axis.text.x = element_text(angle = 35, hjust = 1), legend.position = "right")

# trajectory composition from data
tr <- as.character(dfB$traj_risk)
tr[!nzchar(tr) | is.na(tr)] <- "Unknown"
tr_df <- as.data.frame(table(tr), stringsAsFactors = FALSE)
names(tr_df) <- c("Class", "n")
tr_df$Class <- factor(tr_df$Class, levels = tr_df$Class[order(-tr_df$n)])
p2b <- ggplot(tr_df, aes(Class, n, fill = Class)) +
  geom_col(width = 0.72, show.legend = FALSE) +
  geom_text(aes(label = n), vjust = -0.35, size = 2.7, family = font) +
  scale_fill_manual(values = rep(pal$fill, length.out = nrow(tr_df))) +
  labs(title = "Trajectory risk tiers", x = NULL, y = "Patients") +
  theme_pub(9) + theme(axis.text.x = element_text(angle = 25, hjust = 1))

# KM by traj risk
d_km <- dfB
d_km$tr <- factor(ifelse(tr %in% c("低危", "低", "Low"), "Low",
                  ifelse(tr %in% c("中危", "中", "Mid"), "Mid",
                  ifelse(tr %in% c("高危", "高", "High"), "High", NA))),
                  levels = c("Low", "Mid", "High"))
d_km <- d_km[!is.na(d_km$tr) & is.finite(d_km$pfs_time), ]
sf <- survfit(Surv(pfs_time, pfs_event) ~ tr, data = d_km)
km_df <- data.frame(time = sf$time, surv = sf$surv,
                    strata = factor(rep(gsub(".*=", "", names(sf$strata)), sf$strata),
                                   levels = c("Low", "Mid", "High")))
p2c <- ggplot(km_df, aes(time, surv, color = strata)) +
  geom_step(linewidth = 0.7) +
  coord_cartesian(xlim = c(0, 60), ylim = c(0.4, 1)) +
  scale_color_manual(values = c(Low = pal$blue3, Mid = pal$green, High = pal$red)) +
  labs(title = "PFS by trajectory tier", x = "Months", y = "PFS probability", color = NULL) +
  theme_pub(9)

f2 <- (p2a | p2b | p2c) + plot_annotation(
  title = "Figure 2. EBV-PET correlation and trajectory phenotype",
  theme = theme(plot.title = element_text(face = "bold", family = font, size = 12))
)
stem2 <- "Figure 2. EBV-PET correlation and trajectory phenotype"
save_pdf(file.path(fd, paste0(stem2, ".pdf")), f2, 11.2, 3.8)
write_md(stem2, "A 偏Spearman（S17）；B 轨迹风险层构成；C 轨迹分层PFS KM（描述性）。",
         "队列B；轨迹含治疗期信息，不作独立预后结论。")

# ========================= FIGURE 3: association forests + HR matrix =========================
# Univariate from S9 (columns may be Endpoint/Variable/HR/lo/hi)
nm9 <- names(s9)
col_end <- nm9[grep("^End|^endpoint", nm9, ignore.case = TRUE)[1]]
col_var <- nm9[grep("^Var|^variable", nm9, ignore.case = TRUE)[1]]
col_hr <- nm9[grep("^HR$", nm9, ignore.case = TRUE)[1]]
col_lo <- nm9[grep("^lo$|lower|CI_lo", nm9, ignore.case = TRUE)[1]]
col_hi <- nm9[grep("^hi$|upper|CI_hi", nm9, ignore.case = TRUE)[1]]
uv_vars <- c("age", "Lnode", "Lmtv", "Ltlg", "t0_score", "t0_pos")
uv <- list()
for (i in seq_len(nrow(s9))) {
  v <- as.character(s9[[col_var]][i]); e <- as.character(s9[[col_end]][i])
  if (!v %in% uv_vars || !e %in% c("OS", "PFS", "DM")) next
  hr <- as.numeric(s9[[col_hr]][i]); lo <- as.numeric(s9[[col_lo]][i]); hi <- as.numeric(s9[[col_hi]][i])
  if (!is.finite(hr)) next
  uv[[length(uv) + 1]] <- data.frame(endpoint = e, variable = v, hr = hr, lo = lo, hi = hi, stringsAsFactors = FALSE)
}
uv <- do.call(rbind, uv)
if (is.null(uv) || !nrow(uv)) stop("Univariable forest empty after S9 parse")
labmap_uv <- c(age = "Age", Lnode = "Lnode", Lmtv = "MTV", Ltlg = "TLG",
               t0_score = "T0 score", t0_pos = "T0+")
uv$lab <- paste0(ifelse(is.na(labmap_uv[uv$variable]), uv$variable, labmap_uv[uv$variable]),
                 " | ", uv$endpoint)
p3a <- forest_from_hrdf(uv, "Univariable HR", "Selected markers; Table S9")

# Multivariable key from Table4
mv_vars <- c("age", "male", "t_ord", "n_ord", "Lnode", "Lmtv", "t0_pos", "t0_score")
mv <- list()
for (i in seq_len(nrow(t4))) {
  if (!t4$variable[i] %in% mv_vars) next
  if (!t4$endpoint[i] %in% c("OS", "PFS", "DM")) next
  h <- parse_hr(t4$HR_CI[i]); if (!is.finite(h["hr"])) next
  mv[[length(mv) + 1]] <- data.frame(
    endpoint = factor(t4$endpoint[i], levels = c("OS", "PFS", "DM")),
    variable = t4$variable[i], hr = h["hr"], lo = h["lo"], hi = h["hi"],
    stringsAsFactors = FALSE
  )
}
mv <- do.call(rbind, mv)
labmap <- c(age = "Age", male = "Male", t_ord = "T", n_ord = "N",
            Lnode = "Lnode", Lmtv = "MTV", t0_pos = "T0+", t0_score = "T0 score")
mv$varlab <- factor(labmap[mv$variable], levels = rev(unname(labmap[mv_vars])))
p3b <- ggplot(mv, aes(hr, varlab)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.35) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.18, orientation = "y",
                color = pal$blue2, linewidth = 0.4) +
  geom_point(size = 1.6, color = pal$blue2) +
  facet_wrap(~endpoint, nrow = 1, scales = "free_x") +
  scale_x_log10() +
  labs(title = "Multivariable adjusted HR", subtitle = "Table 4", x = "HR (95% CI)", y = NULL) +
  theme_pub(9)

# HR matrix heatmap (log-HR) for Fig13 role
hm <- list()
for (i in seq_len(nrow(t4))) {
  h <- parse_hr(t4$HR_CI[i]); if (!is.finite(h["hr"])) next
  hm[[length(hm) + 1]] <- data.frame(
    endpoint = t4$endpoint[i], variable = t4$variable[i],
    loghr = log(h["hr"]), hr = h["hr"], stringsAsFactors = FALSE
  )
}
hm <- do.call(rbind, hm)
hm$endpoint <- factor(hm$endpoint, levels = c("OS", "PFS", "DM", "DM+D", "LR"))
keep_v <- c("age", "Lnode", "Lmtv", "Ltlg", "Lntr", "t0_pos", "t0_score")
labmap_hm <- c(age = "Age", Lnode = "Lnode", Lmtv = "MTV", Ltlg = "TLG",
               Lntr = "NTR", t0_pos = "T0+", t0_score = "T0 score")
hm <- hm[hm$variable %in% keep_v, ]
hm$varlab <- factor(labmap_hm[hm$variable], levels = rev(unname(labmap_hm[keep_v])))
p3c <- ggplot(hm, aes(endpoint, varlab, fill = loghr)) +
  geom_tile(color = "white", linewidth = 0.35) +
  geom_text(aes(label = sprintf("%.2f", hr)), size = 2.3, family = font) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0,
                       name = "log HR") +
  labs(title = "Adjusted HR matrix", subtitle = "Cell = HR; Table 4", x = NULL, y = NULL) +
  theme_pub(9) + theme(legend.position = "right")

f3 <- (p3a / p3b / p3c) + plot_layout(heights = c(1.1, 1.0, 0.95)) +
  plot_annotation(title = "Figure 3. Associations across endpoints",
                  theme = theme(plot.title = element_text(face = "bold", family = font, size = 12)))
stem3 <- "Figure 3. Associations across endpoints"
save_pdf(file.path(fd, paste0(stem3, ".pdf")), f3, 8.8, 10.2)
write_md(stem3,
         "A 单因素森林（S9选变量）；B 多变量三终点森林（Table4）；C 调整HR矩阵（Table4，单元格为HR）。",
         "队列B；Lnode/MTV等为log2(1+x)尺度（见表注）。")

# ========================= FIGURE 4: discrimination (A + B) =========================
# Cohort A M0-M4 bars from S16
s16$AUC <- as.numeric(s16$AUC)
s16_36 <- s16[!is.na(s16$Endpoint) & as.integer(s16$Horizon_mo) == 36, ]
s16_36$Model <- factor(s16_36$Model, levels = c("M0", "M1", "M2", "M3", "M4"))
s16_36$Endpoint <- factor(s16_36$Endpoint, levels = c("OS", "PFS", "DM"))
p4a <- ggplot(s16_36, aes(Model, AUC, fill = Endpoint)) +
  geom_col(position = position_dodge(0.78), width = 0.72) +
  geom_text(aes(label = sprintf("%.2f", AUC)), position = position_dodge(0.78),
            vjust = -0.3, size = 2.2, family = font) +
  coord_cartesian(ylim = c(0.55, max(s16_36$AUC, na.rm = TRUE) + 0.08)) +
  scale_fill_manual(values = c(OS = pal$blue, PFS = pal$blue2, DM = pal$red)) +
  labs(title = "Cohort A apparent 36-mo AUC", subtitle = "Stage-based M0; lambda=0.03 (S16)",
       x = NULL, y = "IPCW-AUC") +
  theme_pub(9)

# Cohort B OOF heatmap from Table2 @36
t2_36 <- t2[as.integer(t2$Horizon_mo) == 36, ]
t2_36$AUC <- as.numeric(t2_36$AUC)
t2_36$Model <- factor(t2_36$Model, levels = c("C", "E", "P2", "P6", "EP2", "EP6", "EP2X"))
t2_36$Endpoint <- factor(t2_36$Endpoint, levels = c("OS", "PFS", "DM", "DM+D", "LR"))
p4b <- ggplot(t2_36, aes(Model, Endpoint, fill = AUC)) +
  geom_tile(color = "white", linewidth = 0.4) +
  geom_text(aes(label = sprintf("%.3f", AUC)), size = 2.5, family = font) +
  scale_fill_gradient(low = "#F7FBFF", high = "#08306B", name = "OOF AUC") +
  labs(title = "Cohort B OOF AUC heatmap", subtitle = "8x5-fold; lambda=5 (Table 2)",
       x = NULL, y = NULL) +
  theme_pub(9) + theme(legend.position = "right")

# DM paired gains
t3_36 <- t3[as.integer(t3$Horizon_mo) == 36, ]
t3_36$Delta_AUC <- as.numeric(t3_36$Delta_AUC)
t3_36$CI_lo <- as.numeric(t3_36$CI_lo); t3_36$CI_hi <- as.numeric(t3_36$CI_hi)
t3_36$Contrast <- factor(t3_36$Contrast, levels = rev(t3_36$Contrast))
p4c <- ggplot(t3_36, aes(Delta_AUC, Contrast)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey55") +
  geom_errorbar(aes(xmin = CI_lo, xmax = CI_hi), width = 0.18, orientation = "y",
                color = pal$blue, linewidth = 0.45) +
  geom_point(size = 2, color = pal$blue) +
  labs(title = "DM paired Delta AUC", subtitle = "800 paired bootstrap (Table 3)",
       x = "Delta AUC (95% CI)", y = NULL) +
  theme_pub(9)

f4 <- (p4a | p4b) / p4c + plot_layout(heights = c(1.15, 0.85)) +
  plot_annotation(title = "Figure 4. Discrimination: cohort A apparent and cohort B OOF",
                  theme = theme(plot.title = element_text(face = "bold", family = font, size = 12)))
stem4 <- "Figure 4. Discrimination cohort A and cohort B OOF"
save_pdf(file.path(fd, paste0(stem4, ".pdf")), f4, 10.8, 7.2)
write_md(stem4,
         "A 口径A M0-M4表观AUC（S16）；B 口径B七模型折外热图（Table2）；C 远转配对Delta AUC（Table3）。",
         "A: N=412 lambda=0.03；B: N=391 OOF 8x5 lambda=5。")

# ========================= FIGURE 5: stratification + landmark + holdout =========================
# Quadrant
dQ <- tryCatch(.npc_endpoint_df(dfB, "DM"), error = function(e) NULL)
if (!is.null(dQ)) {
  dQ$eh <- as.integer(dQ$ebv_high %in% 1L); dQ$ph <- as.integer(dQ$pet_high %in% 1L)
  evQ <- as.integer(dQ$cause == 1L)
  er <- aggregate(evQ ~ eh + ph, data = dQ, FUN = function(z) c(rate = mean(z), n = length(z)))
  er <- data.frame(eh = er$eh, ph = er$ph, rate = er$evQ[, 1], n = er$evQ[, 2])
} else {
  er <- data.frame(eh = c(0, 1, 0, 1), ph = c(0, 0, 1, 1), rate = NA, n = NA)
}
p5a <- ggplot(er, aes(factor(eh, labels = c("EBV low", "EBV high")),
                      factor(ph, labels = c("PET low", "PET high")), fill = rate)) +
  geom_tile(color = "white", linewidth = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%\nn=%d", 100 * rate, n)), family = font, lineheight = 0.95, size = 3) +
  scale_fill_gradient(low = "#F7FBFF", high = "#08306B", name = "DM rate") +
  labs(title = "EBV x PET quadrants", subtitle = "PET high=TLG>65|NTR>0.64", x = NULL, y = NULL) +
  theme_pub(9) + theme(legend.position = "right")

# Risk score KM tertiles
bb <- dfB
z <- function(x) {
  x <- as.numeric(x); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) rep(0, length(x)) else (x - mean(x, na.rm = TRUE)) / s
}
bb$age_z <- z(bb$age); bb$t0_z <- z(bb$t0_score); bb$Lmtv_z <- z(bb$Lmtv); bb$Lnode_z <- z(bb$Lnode)
fit6 <- coxph(Surv(pfs_time, pfs_event) ~ age_z + male + t_ord + n_ord + t0_z + Lmtv_z + Lnode_z, data = bb)
lp <- as.numeric(predict(fit6, newdata = bb, type = "lp"))
score <- 100 * (lp - min(lp, na.rm = TRUE)) / (max(lp, na.rm = TRUE) - min(lp, na.rm = TRUE))
bb$tert <- cut(score, breaks = c(-Inf, 45.9, 58.71, Inf), labels = c("Low", "Mid", "High"), right = FALSE)
km_one <- function(time, event, tert, ylab) {
  d <- data.frame(time = time, event = event, tert = tert)
  d <- d[is.finite(d$time) & !is.na(d$tert), ]
  sf <- survfit(Surv(time, event) ~ tert, data = d)
  data.frame(time = sf$time, surv = sf$surv,
             tert = factor(rep(gsub(".*=", "", names(sf$strata)), sf$strata),
                           levels = c("Low", "Mid", "High")),
             ylab = ylab)
}
dfs <- rbind(
  km_one(bb$os_time, bb$os_event, bb$tert, "OS"),
  km_one(bb$pfs_time, bb$pfs_event, bb$tert, "PFS"),
  km_one(bb$dm_time, as.integer(bb$dm_status == 1L), bb$tert, "DM")
)
p5b <- ggplot(dfs, aes(time, surv, color = tert)) +
  geom_step(linewidth = 0.65) +
  facet_wrap(~ylab, nrow = 1) +
  coord_cartesian(xlim = c(0, 60), ylim = c(0.4, 1)) +
  scale_color_manual(values = c(Low = pal$blue3, Mid = pal$green, High = pal$red)) +
  labs(title = "Risk-score tertile KM", subtitle = "Cuts 45.9 / 58.71 (S18)",
       x = "Months", y = "Event-free", color = NULL) +
  theme_pub(9)

# T2 delta + trajectory delta
s29$Endpoint <- factor(s29$Endpoint, levels = c("OS", "PFS", "DM", "DM+D", "LR"))
for (v in c("Delta_AUC", "CI_lo", "CI_hi")) s29[[v]] <- as.numeric(s29[[v]])
p5c <- ggplot(s29, aes(Endpoint, Delta_AUC)) +
  geom_hline(yintercept = 0, linetype = 2, color = "grey55") +
  geom_col(width = 0.65, fill = pal$blue2) +
  geom_errorbar(aes(ymin = CI_lo, ymax = CI_hi), width = 0.15, linewidth = 0.35) +
  labs(title = "+T2 Delta AUC (9-mo)", subtitle = "S29", y = "Delta AUC", x = NULL) +
  theme_pub(9)

t5$Landmark_mo <- as.integer(t5$Landmark_mo)
p5d <- ggplot(t5, aes(factor(Landmark_mo), as.numeric(Delta_AUC))) +
  geom_hline(yintercept = 0, linetype = 2, color = "grey55") +
  geom_col(width = 0.65, fill = pal$green) +
  geom_errorbar(aes(ymin = as.numeric(CI_lo), ymax = as.numeric(CI_hi)), width = 0.15, linewidth = 0.35) +
  labs(title = "+Trajectory Delta AUC (DM)", subtitle = "Table 5", y = "Delta AUC", x = "Landmark (mo)") +
  theme_pub(9)

# Holdout AUC DM + calibration
s3$AUC <- as.numeric(s3$AUC)
s3_dm <- s3[s3$Endpoint == "DM", ]
s3_dm$Model <- factor(s3_dm$Model, levels = c("C", "E", "P2", "EP2"))
p5e <- ggplot(s3_dm, aes(Model, AUC)) +
  geom_col(width = 0.65, fill = pal$blue) +
  geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.35, size = 2.5, family = font) +
  coord_cartesian(ylim = c(0.5, max(s3_dm$AUC) + 0.1)) +
  labs(title = "Holdout DM AUC", subtitle = "S3", y = "AUC", x = NULL) +
  theme_pub(9)

s31$Predicted_pct <- as.numeric(s31$Predicted_pct)
s31$Observed_pct <- as.numeric(s31$Observed_pct)
s31$label <- gsub("Holdout ", "", as.character(s31$Set))
mx <- max(c(s31$Predicted_pct, s31$Observed_pct), na.rm = TRUE) * 1.2
p5f <- ggplot(s31, aes(Predicted_pct, Observed_pct, label = label)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey55") +
  geom_point(size = 2.3, color = pal$blue) +
  geom_text(vjust = -0.55, size = 2.2, family = font) +
  coord_equal(xlim = c(0, mx), ylim = c(0, mx)) +
  labs(title = "Holdout calibration", subtitle = "S31 EP2 36-mo DM",
       x = "Predicted (%)", y = "Observed (%)") +
  theme_pub(9)

f5 <- (p5a | p5b) / (p5c | p5d | p5e | p5f) +
  plot_layout(heights = c(1.05, 1)) +
  plot_annotation(title = "Figure 5. Stratification, landmark increments, and temporal holdout",
                  theme = theme(plot.title = element_text(face = "bold", family = font, size = 12)))
stem5 <- "Figure 5. Stratification landmark and temporal holdout"
save_pdf(file.path(fd, paste0(stem5, ".pdf")), f5, 12.5, 8.0)
write_md(stem5,
         "A 四象限远转粗率；B 风险分三分位KM；C +T2增量；D 轨迹增量；E 年代留出DM AUC；F 留出校准。",
         "同源 S5/S18/S29/Table5/S3/S31；人数为真实重算。")

# ========================= FIGURE 6: clinical utility bundle =========================
# Bio metrics
s23$Metric <- as.character(s23[[1]]); s23$Value <- as.character(s23[[2]])
getv <- function(key) {
  i <- grep(key, s23$Metric, ignore.case = TRUE)[1]
  if (is.na(i)) return(NA_real_)
  suppressWarnings(as.numeric(s23$Value[i]))
}
bio <- data.frame(
  Metric = factor(c("Sensitivity", "Specificity", "PPV", "NPV"),
                  levels = c("Sensitivity", "Specificity", "PPV", "NPV")),
  Value = c(getv("^Sensitivity"), getv("^Specificity"), getv("^PPV"), getv("^NPV"))
)
p6a <- ggplot(bio, aes(Metric, Value)) +
  geom_col(width = 0.62, fill = pal$blue2) +
  geom_text(aes(label = sprintf("%.3f", Value)), vjust = -0.35, size = 2.6, family = font) +
  coord_cartesian(ylim = c(0, 1.08)) +
  labs(title = "Biological relapse diagnostics", subtitle = "S23 date rules",
       y = "Proportion", x = NULL) +
  theme_pub(9)

# Sensitivity AUC
s6$AUC <- as.numeric(s6$AUC)
s6$Scenario <- factor(s6$Scenario, levels = rev(s6$Scenario))
p6b <- ggplot(s6, aes(AUC, Scenario)) +
  geom_col(width = 0.72, fill = pal$blue3) +
  geom_text(aes(label = sprintf("%.3f", AUC)), hjust = -0.08, size = 2.3, family = font) +
  coord_cartesian(xlim = c(0.55, max(s6$AUC, na.rm = TRUE) + 0.08)) +
  labs(title = "Sensitivity analyses (OOF AUC)", subtitle = "S6", x = "AUC", y = NULL) +
  theme_pub(8.5)

# Two-cohort boundary: A apparent / B apparent / B OOF
b_oof <- t2[as.integer(t2$Horizon_mo) == 36 & t2$Endpoint %in% c("OS", "PFS", "DM") &
              t2$Model %in% c("C", "EP2"), c("Endpoint", "Model", "AUC")]
b_oof$Cohort <- "B OOF"
a_app <- s8[s8$Cohort == "A" & s8$Endpoint %in% c("OS", "PFS", "DM") & s8$Model %in% c("C", "EP2"), ]
a_app$Cohort <- "A apparent"; a_app$AUC <- as.numeric(a_app$AUC)
b_app <- s8[s8$Cohort == "B" & s8$Endpoint %in% c("OS", "PFS", "DM") & s8$Model %in% c("C", "EP2"), ]
b_app$Cohort <- "B apparent"; b_app$AUC <- as.numeric(b_app$AUC)
bnd <- rbind(
  a_app[, c("Cohort", "Endpoint", "Model", "AUC")],
  b_app[, c("Cohort", "Endpoint", "Model", "AUC")],
  data.frame(Cohort = b_oof$Cohort, Endpoint = b_oof$Endpoint, Model = b_oof$Model,
             AUC = as.numeric(b_oof$AUC))
)
bnd$Cohort <- factor(bnd$Cohort, levels = c("A apparent", "B apparent", "B OOF"))
bnd$Endpoint <- factor(bnd$Endpoint, levels = c("OS", "PFS", "DM"))
bnd$Model <- factor(bnd$Model, levels = c("C", "EP2"))
p6c <- ggplot(bnd, aes(Endpoint, AUC, fill = Model)) +
  geom_col(position = position_dodge(0.72), width = 0.68) +
  facet_wrap(~Cohort, nrow = 1) +
  geom_text(aes(label = sprintf("%.2f", AUC)), position = position_dodge(0.72),
            vjust = -0.3, size = 2.2, family = font) +
  coord_cartesian(ylim = c(0.55, max(bnd$AUC, na.rm = TRUE) + 0.08)) +
  scale_fill_manual(values = c(C = "grey65", EP2 = pal$blue)) +
  labs(title = "Two-cohort discrimination boundary",
       subtitle = "A/B apparent from S8; B OOF from latest Table 2",
       x = NULL, y = "36-mo AUC") +
  theme_pub(9)

# DCA optional small - sample net benefit at thresholds if columns exist
p6d <- NULL
if (all(c("threshold", "net_benefit") %in% tolower(names(s4))) || ncol(s4) >= 3) {
  nm <- names(s4)
  thr <- s4[[grep("thr|Thresh", nm, ignore.case = TRUE)[1]]]
  nb <- s4[[grep("net|benefit|NB", nm, ignore.case = TRUE)[1]]]
  mod <- s4[[grep("Model|Strategy|model", nm, ignore.case = TRUE)[1]]]
  dca <- data.frame(threshold = as.numeric(thr), net_benefit = as.numeric(nb),
                    model = as.character(mod))
  dca <- dca[is.finite(dca$threshold) & is.finite(dca$net_benefit), ]
  dca <- dca[dca$model %in% c("C", "E", "P2", "EP2", "Treat all", "Treat none"), ]
  if (nrow(dca)) {
    p6d <- ggplot(dca, aes(threshold, net_benefit, color = model)) +
      geom_line(linewidth = 0.55) +
      coord_cartesian(xlim = c(0.05, 0.30)) +
      labs(title = "Decision curve (DM 36-mo)", subtitle = "S4",
           x = "Threshold", y = "Net benefit") +
      theme_pub(9)
  }
}
if (is.null(p6d)) {
  f6 <- (p6a | p6c) / p6b + plot_layout(heights = c(1, 1.2))
} else {
  f6 <- (p6a | p6d | p6c) / p6b + plot_layout(heights = c(1, 1.15))
}
f6 <- f6 + plot_annotation(title = "Figure 6. Clinical utility, sensitivity, and cohort boundary",
                           theme = theme(plot.title = element_text(face = "bold", family = font, size = 12)))
stem6 <- "Figure 6. Clinical utility sensitivity and cohort boundary"
save_pdf(file.path(fd, paste0(stem6, ".pdf")), f6, 12.0, 8.2)
write_md(stem6,
         "A 生物学复发诊断指标（S23）；B 敏感性折外AUC（S6）；C 两口径判别边界（S8+最新Table2 OOF）；若有则含DCA（S4）。",
         "主结论以口径B折外为准。")

# ========================= FIGURE S1: CIF =========================
s12$CIF <- as.numeric(s12$CIF)
s12$Time_mo <- as.numeric(s12$Time_mo)
s12$Cause <- factor(s12$Cause, levels = c("primary", "competing"),
                    labels = c("Primary event", "Competing death"))
pS1 <- ggplot(s12[s12$Endpoint %in% c("DM", "LR"), ],
              aes(Time_mo, CIF, color = Cause, linetype = Endpoint)) +
  geom_line(linewidth = 0.75) +
  geom_point(size = 1.5) +
  scale_color_manual(values = c("Primary event" = pal$red, "Competing death" = pal$blue)) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "Figure S1. Competing-risk cumulative incidence",
       subtitle = "Absolute CIF from Table S12",
       x = "Months since diagnosis", y = "Cumulative incidence") +
  theme_pub(10) + theme(legend.position = "bottom")
stemS1 <- "Figure S1. Competing-risk cumulative incidence"
save_pdf(file.path(fd, paste0(stemS1, ".pdf")), pS1, 7.2, 4.6)
write_md(stemS1, "DM/LR 的原发事件与竞争死亡 CIF 曲线，数字同源最新 Table S12。",
         "队列B；cmprsk 累积发生率。")

# ========================= FIGURE S2: holdout multi-endpoint detail =========================
s3$Endpoint <- factor(s3$Endpoint, levels = c("OS", "PFS", "DM", "DM+D", "LR"))
s3$Model <- factor(s3$Model, levels = c("C", "E", "P2", "EP2"))
pS2 <- ggplot(s3, aes(Model, as.numeric(AUC), fill = Endpoint)) +
  geom_col(position = position_dodge(0.78), width = 0.72) +
  labs(title = "Figure S2. Temporal-holdout AUC by endpoint",
       subtitle = "Train <=2022 / test 2023-2025 (S3)",
       x = NULL, y = "IPCW-AUC") +
  theme_pub(10)
stemS2 <- "Figure S2. Temporal-holdout AUC by endpoint"
save_pdf(file.path(fd, paste0(stemS2, ".pdf")), pS2, 8.5, 4.4)
write_md(stemS2, "年代留出五终点×四模型AUC全貌（S3）。主文Figure5已展示DM子集与校准。",
         "N_train=215；N_test=176。")

.message("Figures written: %d", length(list.files(fd, "\\.pdf$")))

# ========================= TABLES (booktabs, curated) =========================
# Main tables
# Table1 - read archived carefully
t1_raw <- tryCatch(read.xlsx(file.path(src_tbl, "Table 1. Baseline characteristics of cohort B.xlsx"),
                             startRow = 1), error = function(e) NULL)
# Prefer last two columns as Characteristic / Overall if malformed
if (!is.null(t1_raw)) {
  if (ncol(t1_raw) >= 3 && (is.na(names(t1_raw)[1]) || grepl("Table", names(t1_raw)[1]))) {
    # find rows with Characteristic-like
    cn <- names(t1_raw)
    # try startRow=3 style
    t1b <- tryCatch(read.xlsx(file.path(src_tbl, "Table 1. Baseline characteristics of cohort B.xlsx"),
                              startRow = 3), error = function(e) NULL)
    if (!is.null(t1b) && ncol(t1b) >= 2) {
      names(t1b)[1:2] <- c("Characteristic", "Overall")
      t1_out <- t1b[, 1:min(3, ncol(t1b)), drop = FALSE]
    } else {
      t1_out <- t1_raw
    }
  } else t1_out <- t1_raw
  write_booktabs(t1_out, file.path(td, "Table 1. Baseline characteristics of cohort B.xlsx"),
                 "Table 1. Baseline characteristics of cohort B (N=391)",
                 footnotes = list("Values are median (IQR) or n (%). Analytic cohort B: include==1."))
}

write_booktabs(t2, file.path(td, "Table 2. Nested OOF IPCW-AUC across endpoints.xlsx"),
               "Table 2. Nested models: 24- and 36-month OOF IPCW-AUC across five endpoints",
               footnotes = list("Cohort B N=391; ridge lambda=5; Breslow ties; repeated 8x5-fold OOF.",
                                "Models: C/E/P2/P6/EP2/EP6/EP2X."))
write_booktabs(t3, file.path(td, "Table 3. Distant-metastasis paired delta AUC.xlsx"),
               "Table 3. Distant-metastasis paired Delta AUC (bootstrap)",
               footnotes = list("800 paired patient bootstraps on fixed OOF LPs; IPCW weights re-estimated."))
# Clean Table4 scale label for display
t4c <- t4
t4c$Scale <- ifelse(t4c$variable %in% c("Lnode", "Lmtv", "Ltlg", "Lntr"),
                    "per +1 on log2(1+x)",
                    ifelse(t4c$variable == "t0_score", "per +1 relative score unit",
                           as.character(t4c$Scale)))
write_booktabs(t4c, file.path(td, "Table 4. Adjusted HRs for EBV and PET markers.xlsx"),
               "Table 4. Adjusted hazard ratios for clinical, EBV and PET markers",
               footnotes = list("Unpenalized Cox; cohort B. Nodal SUVmax and PET volumes on log2(1+x)."))
write_booktabs(t5, file.path(td, "Table 5. Landmark trajectory incremental AUC.xlsx"),
               "Table 5. Landmark trajectory-tier incremental AUC for distant metastasis",
               footnotes = list("Reference: Age+Sex+T+N+T0+MTV+Lnode+IC; + mid/high trajectory.",
                                "1000 paired bootstraps; IPCW weights re-estimated."))

# Supplementary curated set
supp_copy <- list(
  c("Table S1. EBV DNA coding dictionary.xlsx", "Table S1. EBV DNA coding dictionary.xlsx"),
  c("Table S3. Temporal holdout DM AUC.xlsx", "Table S2. Temporal holdout AUC.xlsx"),
  c("Table S4. Decision-curve net benefit DM 36-month.xlsx", "Table S3. Decision-curve net benefit.xlsx"),
  c("Table S5. EBV PET RERI for distant metastasis.xlsx", "Table S4. EBV PET quadrant and RERI.xlsx"),
  c("Table S5b. Quadrant counts authenticity note.xlsx", "Table S4b. Quadrant counts authenticity note.xlsx"),
  c("Table S6. Sensitivity analyses AUC.xlsx", "Table S5. Sensitivity analyses AUC.xlsx"),
  c("Table S9. Univariate Cox HR three endpoints.xlsx", "Table S6. Univariable Cox HRs.xlsx"),
  c("Table S11. Nested likelihood-ratio tests.xlsx", "Table S7. Nested likelihood-ratio tests.xlsx"),
  c("Table S12. Competing-risk CIF absolute risks.xlsx", "Table S8. Competing-risk CIF absolute risks.xlsx"),
  c("Table S13. Cause-specific vs Fine-Gray HRs for DM.xlsx", "Table S9. Cause-specific vs Fine-Gray HRs.xlsx"),
  c("Table S16. Cohort A M0-M4 apparent AUC.xlsx", "Table S10. Cohort A M0-M4 apparent AUC.xlsx"),
  c("Table S17. Partial Spearman EBV vs PET.xlsx", "Table S11. Partial Spearman EBV vs PET.xlsx"),
  c("Table S18. Risk-score strata with locked cutoffs.xlsx", "Table S12. Risk-score strata.xlsx"),
  c("Table S19. Bootstrap optimism-corrected Harrell C-index.xlsx", "Table S13. Optimism-corrected C-index.xlsx"),
  c("Table S21. Parsimonious 6-parameter joint model HRs.xlsx", "Table S14. Parsimonious 6-parameter HRs.xlsx"),
  c("Table S22. IC double interaction T1xMTV and T1xLnode.xlsx", "Table S15. IC T1 interaction contrast.xlsx"),
  c("Table S23. Biological relapse diagnostic performance.xlsx", "Table S16. Biological relapse diagnostics.xlsx"),
  c("Table S29. Landmark T2 five-endpoint delta AUC.xlsx", "Table S17. Landmark T2 incremental AUC.xlsx"),
  c("Table S30. Landmark IC model family U UP2 IUX.xlsx", "Table S18. Landmark IC model family.xlsx"),
  c("Table S31. Temporal holdout calibration.xlsx", "Table S19. Temporal holdout calibration.xlsx"),
  c("Table S32. IC leave-one-out T1-positive PFS cases.xlsx", "Table S20. IC leave-one-out.xlsx"),
  c("Table S34. Temporal holdout multi-endpoint delta AUC.xlsx", "Table S21. Holdout multi-endpoint delta AUC.xlsx"),
  c("Table S8. Apparent AUC cohort A and B.xlsx", "Table S22. Apparent AUC cohorts A and B.xlsx")
)

for (pr in supp_copy) {
  src <- file.path(src_tbl, pr[1])
  if (!file.exists(src)) next
  df <- tryCatch({
    if (grepl("S8\\. Apparent", pr[1])) read.xlsx(src, startRow = 2) else {
      x <- read.xlsx(src); if (ncol(x) > 1 && all(is.na(x[[1]]))) x <- x[, -1, drop = FALSE]; x
    }
  }, error = function(e) NULL)
  if (is.null(df)) next
  title <- sub("\\.xlsx$", "", pr[2])
  title <- gsub("^Table ", "Table ", title)
  write_booktabs(df, file.path(td, pr[2]), title)
}

# NUMBERING / LAYOUT
layout <- c(
  "# Publication layout (consolidated)",
  "",
  "## Main figures (6 + 2 supplements)",
  "| New | Role | Source panels / tables |",
  "|---|---|---|",
  "| Figure 1 | EBV LOD-relative coding | former Fig1 |",
  "| Figure 2 | Correlation + trajectory phenotype/KM | former Fig2-4 |",
  "| Figure 3 | UV/MV associations + HR matrix | former Fig5-6,11-13; Tables S9/4 |",
  "| Figure 4 | Cohort A apparent + Cohort B OOF + Delta AUC | former Fig7-10,S2; Tables S16/2/3 |",
  "| Figure 5 | Quadrant, risk KM, landmark, holdout | former Fig14-17; S5/S18/S29/T5/S3/S31 |",
  "| Figure 6 | Bio relapse, sensitivity, cohort boundary (+DCA) | former Fig18-20,S3; S23/S6/S8/T2/S4 |",
  "| Figure S1 | Competing-risk CIF | former Fig S1; Table S12 -> S8 |",
  "| Figure S2 | Holdout AUC full grid | former Fig17-A detail; Table S3 -> S2 |",
  "",
  "## Main tables (5)",
  "Table 1 baseline; Table 2 nested OOF AUC; Table 3 paired Delta AUC; Table 4 adjusted HRs; Table 5 landmark trajectory.",
  "",
  "## Supplementary tables (renumbered S1-S22)",
  "See Tables/ filenames. Extra legacy sheets archived in `_archive_pre_pub_20261118/Tables/`.",
  "",
  "## Notes",
  "- Implementation: R (not Python).",
  "- Seven-model OOF grid retained (C/E/P2/P6/EP2/EP6/EP2X).",
  "- Digits are authenticity-first (not forced to report headlines)."
)
writeLines(layout, file.path(out_root, "PUBLICATION_LAYOUT.md"), useBytes = TRUE)

writeLines(c(
  "# Numbering",
  "Main Figures 1-6 + S1-S2; Main Tables 1-5; Supplementary Tables S1-S6 (multi-sheet).",
  "Legacy 23-figure / 41-table dump archived in `_archive_pre_pub_20261118/`."
), file.path(out_root, "NUMBERING_AND_ROLE.md"), useBytes = TRUE)

# 引擎级发表收口：默认只收口本目录 out_root（summary（new）），
# 禁止再覆盖课题旧 ML 的 summary_results。
pub_src <- file.path(root, "R/npc_ebv_pet_pub.R")
if (file.exists(pub_src)) {
  source(pub_src, local = FALSE)
  fin <- tryCatch(
    npc_ebv_pet_finalize_summary_delivery(
      draft_root = out_root,
      summary_root = out_root,
      project_root = dirname(out_root),
      rewrite_methods = TRUE,
      prune = TRUE,
      sync_draft = FALSE
    ),
    error = function(e) {
      message("finalize warning: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(fin)) {
    .message("FINALIZE delivery=%s methods=%s software=%s",
             fin$summary, isTRUE(fin$methods), isTRUE(fin$software))
  }
} else {
  writeLines(
    c("# Statistical analysis", "", "See run/npc_ebv_pet/finalize_summary_delivery.R"),
    file.path(out_root, "Methods_statistical_analysis.md"),
    useBytes = TRUE
  )
}

.message("DONE. pdf=%d tables=%d", length(list.files(fd, "\\.pdf$")), length(list.files(td, "\\.xlsx$")))
.message("Layout: %s", file.path(out_root, "PUBLICATION_LAYOUT.md"))
