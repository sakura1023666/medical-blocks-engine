#!/usr/bin/env Rscript
# =============================================================================
# 按分析报告 Fig1–20 体系，真实重算写入 summary（new）
# 不覆盖既有 summary_results（OS-ML）
# =============================================================================
suppressPackageStartupMessages({
  library(survival)
  library(glmnet)
  library(ggplot2)
  library(openxlsx)
  library(timeROC)
  library(grid)
})
if (requireNamespace("gridExtra", quietly = TRUE)) library(gridExtra)
if (requireNamespace("scales", quietly = TRUE)) library(scales)
if (requireNamespace("cmprsk", quietly = TRUE)) library(cmprsk)

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (!is.null(a) && length(a) && !is.na(a)[1] && nzchar(as.character(a)[1])) a else b
.get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/npc_ebv_pet_joint_analysis.R"))
if (file.exists(file.path(root, "R/utils.R"))) {
  tryCatch(source(file.path(root, "R/utils.R"), local = FALSE), error = function(e) NULL)
}

workbook <- .get_arg("--workbook", "/mnt/g/02block_result/53_NPC/ml_40395549/DATA/鼻咽癌EBV_PETCT数据表(1).xlsx")
out_root <- .get_arg("--out", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
n_repeats <- as.integer(.get_arg("--repeats", "8"))
n_boot <- as.integer(.get_arg("--boot", "400"))
if ("--quick" %in% args) { n_repeats <- 2L; n_boot <- 100L }

.message <- function(...) cat(sprintf(...), "\n", sep = "")
.message("Fig1-20 output: %s", out_root)

tbl_dir <- file.path(out_root, "Tables")
fig_dir <- file.path(out_root, "Figures", "pdf")
md_dir <- file.path(out_root, "Figures", "image_information")
dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)

# 清掉旧 Figure*.pdf / md，避免短编号残留混进 1–20
old_pdf <- list.files(fig_dir, pattern = "^Figure .*\\.pdf$", full.names = TRUE)
old_md <- list.files(md_dir, pattern = "^Figure .*\\.md$", full.names = TRUE)
if (length(old_pdf)) unlink(old_pdf)
if (length(old_md)) unlink(old_md)

font_family <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family("Times New Roman")
} else "Times"
theme_set(theme_bw(base_family = font_family, base_size = 11) + theme(panel.grid.minor = element_blank()))

save_pdf <- function(path, expr, w = 7, h = 5) {
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(path, width = w, height = h, family = "Times New Roman")
  } else if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(path, width = w, height = h, family = "Times New Roman")
  } else {
    grDevices::pdf(path, width = w, height = h, family = "Times")
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
}

write_md <- function(stem, face, ctx) {
  writeLines(c(paste0("# ", stem), "", "## 图面说明", face, "", "## 分析上下文", ctx),
             file.path(md_dir, paste0(stem, ".md")), useBytes = TRUE)
}

write_xlsx_simple <- function(df, path, title) {
  wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
  writeData(wb, 1, title, startRow = 1, startCol = 1)
  writeData(wb, 1, df, startRow = 2, startCol = 1)
  addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 12, textDecoration = "bold"), 1, 1)
  addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 10),
           rows = 2:(nrow(df) + 2), cols = 1:max(1, ncol(df)), gridExpand = TRUE)
  saveWorkbook(wb, path, overwrite = TRUE)
  .message("Wrote %s", basename(path))
}

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------
.message("Reading workbook...")
raw <- npc_ebv_pet_read_analysis_df(workbook)
rownames(raw) <- NULL
dfA <- raw  # 口径 A：412
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
rownames(dfB) <- NULL
.message("Cohort A n=%d; Cohort B n=%d (DM events B=%d)",
         nrow(dfA), nrow(dfB), sum(dfB$dm_status == 1, na.rm = TRUE))

ends5 <- c("OS", "PFS", "DM", "DM+D", "LR")
ends3 <- c("OS", "PFS", "DM")
mods6 <- c("C", "E", "P2", "P6", "EP2", "EP6")
mods4 <- c("C", "E", "P2", "EP2")

# ---------------------------------------------------------------------------
# Nested OOF (cohort B, 6 models × 5 endpoints)
# ---------------------------------------------------------------------------
.message("OOF CV repeats=%d models=%s ...", n_repeats, paste(mods6, collapse = "/"))
oof_store <- list()
auc_rows <- list()
for (ep in ends5) {
  for (md in mods6) {
    key <- paste(ep, md, sep = "__")
    .message("  %s", key)
    res <- tryCatch(
      npc_ebv_pet_oof_cv(dfB, ep, md, n_repeats = n_repeats, n_folds = 5L,
                         seed = 20261117L + sum(utf8ToInt(key)), horizon = 36),
      error = function(e) { .message("    FAIL %s", e$message); NULL }
    )
    oof_store[[key]] <- res
    if (!is.null(res)) {
      auc_rows[[length(auc_rows) + 1L]] <- data.frame(
        Endpoint = ep, Model = md, Horizon_mo = 36L,
        N = as.integer(res$n), Events = as.integer(res$n_event),
        AUC = if (length(res$auc) == 1L && is.finite(res$auc)) round(res$auc, 3) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
}
auc_df <- do.call(rbind, auc_rows)
write_xlsx_simple(
  auc_df,
  file.path(tbl_dir, "Table 2. Nested models 36-month IPCW-AUC across five endpoints.xlsx"),
  "Table 2. Nested models (C/E/P2/P6/EP2/EP6) 36-month OOF IPCW-AUC in cohort B"
)

# Paired ΔAUC DM
pair_rows <- list()
dm_ep2 <- oof_store[["DM__EP2"]]
if (!is.null(dm_ep2)) {
  for (ref_name in c("C", "E", "P2", "P6")) {
    ref <- oof_store[[paste0("DM__", ref_name)]]
    if (is.null(ref)) next
    dlt <- npc_ebv_pet_paired_delta(ref, dm_ep2, n_boot = n_boot, seed = 42L)
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Endpoint = "DM", New = "EP2", Reference = ref_name,
      AUC_ref = round(dlt$auc_ref, 3), AUC_new = round(dlt$auc_new, 3),
      Delta_AUC = round(dlt$delta, 3), CI_low = round(dlt$lo, 3), CI_high = round(dlt$hi, 3),
      stringsAsFactors = FALSE
    )
  }
  # also EP6 vs C
  dm_ep6 <- oof_store[["DM__EP6"]]
  if (!is.null(dm_ep6) && !is.null(oof_store[["DM__C"]])) {
    dlt6 <- npc_ebv_pet_paired_delta(oof_store[["DM__C"]], dm_ep6, n_boot = n_boot, seed = 43L)
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Endpoint = "DM", New = "EP6", Reference = "C",
      AUC_ref = round(dlt6$auc_ref, 3), AUC_new = round(dlt6$auc_new, 3),
      Delta_AUC = round(dlt6$delta, 3), CI_low = round(dlt6$lo, 3), CI_high = round(dlt6$hi, 3),
      stringsAsFactors = FALSE
    )
  }
}
pair_df <- if (length(pair_rows)) do.call(rbind, pair_rows) else data.frame()
if (nrow(pair_df)) {
  write_xlsx_simple(pair_df, file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC.xlsx"),
                    "Table 3. Distant metastasis paired ΔAUC (36-month OOF)")
}

# Ledger + HR tables
ledger <- data.frame(
  Endpoint = c("OS", "PFS", "DM", "DM+D", "LR"),
  N = nrow(dfB),
  Events = c(sum(dfB$os_event == 1, na.rm = TRUE), sum(dfB$pfs_event == 1, na.rm = TRUE),
             sum(dfB$dm_status == 1, na.rm = TRUE), sum(dfB$dmd_event == 1, na.rm = TRUE),
             sum(dfB$lr_status == 1, na.rm = TRUE)),
  Competing = c(NA, NA, sum(dfB$dm_status == 2, na.rm = TRUE), NA, sum(dfB$lr_status == 2, na.rm = TRUE)),
  stringsAsFactors = FALSE
)
write_xlsx_simple(ledger, file.path(tbl_dir, "Table 1. Five-endpoint event ledger in cohort B.xlsx"),
                  "Table 1. Five-endpoint event ledger in non-metastatic cohort B (N = 391)")

hr_df <- do.call(rbind, Filter(Negate(is.null), lapply(ends5, function(ep) {
  tryCatch(npc_ebv_pet_cause_specific_hr(dfB, ep, c("Lnode", "Lmtv", "t0_pos", "t0_score", "cum_ebv")),
           error = function(e) NULL)
})))
if (!is.null(hr_df) && nrow(hr_df)) {
  hr_df$HR_CI <- sprintf("%s (%s, %s)", npc_ebv_pet_fmt(hr_df$HR), npc_ebv_pet_fmt(hr_df$lo), npc_ebv_pet_fmt(hr_df$hi))
  hr_df$P <- ifelse(hr_df$p < 0.001, "<0.001", npc_ebv_pet_fmt(hr_df$p, 3))
  hr_df$Variable <- gsub("_", " ", hr_df$variable, fixed = TRUE)
  write_xlsx_simple(hr_df[, c("endpoint", "Variable", "HR_CI", "P")],
                    file.path(tbl_dir, "Table 4. Adjusted HRs for EBV and PET markers across endpoints.xlsx"),
                    "Table 4. Adjusted HRs across five endpoints")
}

# Apparent cohort A (for Fig7/8/20)
.message("Apparent AUC cohort A...")
app_rows <- list()
for (ep in ends3) {
  for (md in mods4) {
    d0 <- .npc_endpoint_df(dfA, ep)
    rownames(d0) <- as.character(seq_len(nrow(d0)))
    mm <- tryCatch(.npc_design_matrix(d0, .npc_model_vars(md)), error = function(e) NULL)
    if (is.null(mm)) next
    keep <- as.integer(rownames(mm))
    ev <- if (ep == "DM") as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
    fit <- tryCatch(.npc_fit_ridge_cox(mm, Surv(d0$time[keep], ev)), error = function(e) NULL)
    if (is.null(fit)) next
    lp <- .npc_predict_lp(fit, mm)
    auc <- .npc_ipcw_auc(d0$time[keep], d0$cause[keep], lp, 36)$auc
    app_rows[[length(app_rows) + 1L]] <- data.frame(
      Cohort = "A", Endpoint = ep, Model = md, N = length(keep),
      AUC = if (length(auc) == 1L && is.finite(auc)) round(auc, 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
}
# Apparent B too
for (ep in ends3) {
  for (md in mods4) {
    d0 <- .npc_endpoint_df(dfB, ep)
    rownames(d0) <- as.character(seq_len(nrow(d0)))
    mm <- tryCatch(.npc_design_matrix(d0, .npc_model_vars(md)), error = function(e) NULL)
    if (is.null(mm)) next
    keep <- as.integer(rownames(mm))
    ev <- if (ep == "DM") as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
    fit <- tryCatch(.npc_fit_ridge_cox(mm, Surv(d0$time[keep], ev)), error = function(e) NULL)
    if (is.null(fit)) next
    lp <- .npc_predict_lp(fit, mm)
    auc <- .npc_ipcw_auc(d0$time[keep], d0$cause[keep], lp, 36)$auc
    app_rows[[length(app_rows) + 1L]] <- data.frame(
      Cohort = "B", Endpoint = ep, Model = md, N = length(keep),
      AUC = if (length(auc) == 1L && is.finite(auc)) round(auc, 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
}
app_df <- do.call(rbind, app_rows)
write_xlsx_simple(app_df, file.path(tbl_dir, "Table S8. Apparent AUC cohort A and B.xlsx"),
                  "Table S8. Apparent (resubstitution) 36-month IPCW-AUC")

# ---------------------------------------------------------------------------
# FIGURES 1–20
# ---------------------------------------------------------------------------
.message("Drawing Figures 1-20...")

# Fig1: LOD + relative curves + T0 score
lod_tab <- as.data.frame(table(LOD = dfB$lod), stringsAsFactors = FALSE)
names(lod_tab)[2] <- "N"
p1a <- ggplot(lod_tab, aes(x = factor(LOD), y = N)) +
  geom_col(fill = "#4C78A8", width = 0.7) +
  labs(title = "A. Recorded thresholds", x = "LOD (copies/mL)", y = "N")
# relative dose curves: v = seq, score = log10(1+v/LOD) for each LOD
curve_df <- do.call(rbind, lapply(sort(unique(stats::na.omit(dfB$lod))), function(L) {
  v <- exp(seq(log(1), log(1e6), length.out = 80))
  data.frame(v = v, score = log10(1 + v / L), LOD = factor(L))
}))
p1b <- ggplot(curve_df, aes(v, score, color = LOD)) +
  geom_line(linewidth = 0.8) + scale_x_log10() +
  geom_hline(yintercept = log10(2), linetype = 2, color = "grey40") +
  labs(title = "B. Relative load curves", x = "Absolute copies/mL", y = "log10(1+v/LOD)")
p1c <- ggplot(dfB, aes(x = t0_score, fill = factor(t0_pos))) +
  geom_histogram(bins = 28, color = "white", linewidth = 0.15) +
  scale_fill_manual(values = c("0" = "#B8B8B8", "1" = "#F58518"), name = "T0 above LOD") +
  labs(title = "C. Normalized T0 score", x = "log10(1+v/LOD)", y = "Count")
save_pdf(file.path(fig_dir, "Figure 1. EBV threshold relative curves and normalized T0.pdf"), {
  gridExtra::grid.arrange(p1a, p1b, p1c, ncol = 3,
                          top = textGrob("Figure 1. Recorded thresholds, relative-load curves, normalized T0",
                                        gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
}, 12, 4.2)
write_md("Figure 1. EBV threshold relative curves and normalized T0",
         "A 记录阈值人数；B 各阈值相对化剂量曲线（虚线=达阈 log10(2)）；C T0 归一分数分布。",
         paste0("口径 B N=", nrow(dfB), "；病例级相对阈值编码。"))

# Fig2 correlation
cors <- c("t0_score", "cum_ebv", "Lmtv", "Lnode", "Ltlg", "Lntr", "age", "t_ord", "n_ord")
cors <- cors[cors %in% names(dfB)]
cm <- suppressWarnings(cor(dfB[, cors], use = "pairwise.complete.obs", method = "spearman"))
lab <- gsub("_", " ", cors)
dimnames(cm) <- list(lab, lab)
cm_df <- as.data.frame(as.table(cm)); names(cm_df) <- c("Var1", "Var2", "rho")
p2 <- ggplot(cm_df, aes(Var1, Var2, fill = rho)) +
  geom_tile() + geom_text(aes(label = sprintf("%.2f", rho)), size = 2.6, family = font_family) +
  scale_fill_gradient2(low = "#B2182B", mid = "white", high = "#2166AC", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Figure 2. Spearman correlations: EBV, PET and stage", x = NULL, y = NULL, fill = "rho") +
  theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 8), axis.text.y = element_text(size = 8))
save_pdf(file.path(fig_dir, "Figure 2. EBV PET clinical Spearman correlation heatmap.pdf"), print(p2), 8, 7)
write_md("Figure 2. EBV PET clinical Spearman correlation heatmap",
         "EBV 归一/累积负荷与 PET、分期的 Spearman 相关热图。",
         paste0("口径 B N=", nrow(dfB)))

# Fig3 trajectory composition
tr <- dfB[!is.na(dfB$traj), ]
tr_n <- as.data.frame(table(Trajectory = tr$traj), stringsAsFactors = FALSE); names(tr_n)[2] <- "N"
tr_n$pct <- tr_n$N / sum(tr_n$N)
# mean load by traj × time
load_long <- do.call(rbind, lapply(c("t0_score", "t1_score", "t2_score"), function(v) {
  data.frame(Trajectory = tr$traj, Time = toupper(substr(v, 1, 2)), Score = tr[[v]], stringsAsFactors = FALSE)
}))
load_m <- aggregate(Score ~ Trajectory + Time, data = load_long, FUN = function(z) mean(z, na.rm = TRUE))
ev_tr <- aggregate(dm_status == 1 ~ traj, data = tr, FUN = mean)
names(ev_tr) <- c("Trajectory", "DM_rate")
p3a <- ggplot(tr_n, aes(x = Trajectory, y = N, fill = Trajectory)) +
  geom_col() + theme(legend.position = "none", axis.text.x = element_text(angle = 25, hjust = 1, size = 7)) +
  labs(title = "A. Composition", y = "N", x = NULL)
p3b <- ggplot(load_m, aes(Time, Score, group = Trajectory, color = Trajectory)) +
  geom_line() + geom_point(size = 1.5) +
  labs(title = "B. Mean molecular load", y = "Normalized score", x = NULL) +
  theme(legend.position = "bottom", legend.text = element_text(size = 7))
p3c <- ggplot(ev_tr, aes(Trajectory, DM_rate, fill = Trajectory)) +
  geom_col() + scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  theme(legend.position = "none", axis.text.x = element_text(angle = 25, hjust = 1, size = 7)) +
  labs(title = "C. Crude DM rate", y = "Rate", x = NULL)
save_pdf(file.path(fig_dir, "Figure 3. Redefined EBV trajectory composition load and event rates.pdf"), {
  gridExtra::grid.arrange(p3a, p3b, p3c, ncol = 3,
                          top = textGrob("Figure 3. Six-class trajectory: composition, mean load, DM rate",
                                        gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
}, 12, 4.5)
write_md("Figure 3. Redefined EBV trajectory composition load and event rates",
         "重定义 6 类轨迹构成、三时点平均分子负荷与粗远转率。轨迹用治疗期信息，不作纯基线暴露。",
         paste0("口径 B；轨迹非缺失 n=", nrow(tr)))
write_xlsx_simple(tr_n, file.path(tbl_dir, "Table S2. Trajectory class counts in cohort B.xlsx"),
                  "Table S2. Redefined EBV DNA trajectory counts")

# Fig4 descriptive KM by traj_risk + robust
save_pdf(file.path(fig_dir, "Figure 4. Descriptive KM by trajectory risk and robust class.pdf"), {
  op <- par(mfrow = c(2, 3), family = if (grepl("Times", font_family)) "Times" else font_family, mar = c(4, 4, 3, 1))
  for (ep in ends3) {
    d <- .npc_endpoint_df(dfB[!is.na(dfB$traj_risk), ], ep)
    d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
    d$g <- factor(d$traj_risk, levels = c("低危", "中危", "高危"))
    sf <- survfit(Surv(time, ev) ~ g, data = d)
    plot(sf, col = c("#4C78A8", "#F58518", "#E45756"), lwd = 2, mark.time = FALSE,
         xlab = "Months", ylab = "Event-free", main = paste0(ep, " by risk tier"))
    legend("bottomleft", legend = levels(d$g), col = c("#4C78A8", "#F58518", "#E45756"), lwd = 2, bty = "n", cex = 0.7)
  }
  if ("traj_robust" %in% names(dfB) && any(!is.na(dfB$traj_robust) & nzchar(dfB$traj_robust))) {
    for (ep in ends3) {
      d <- .npc_endpoint_df(dfB[!is.na(dfB$traj_robust) & nzchar(dfB$traj_robust), ], ep)
      d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
      # collapse rare levels
      tab <- sort(table(d$traj_robust), decreasing = TRUE)
      keep <- names(tab)[seq_len(min(4L, length(tab)))]
      d <- d[d$traj_robust %in% keep, ]
      d$g <- factor(d$traj_robust, levels = keep)
      sf <- survfit(Surv(time, ev) ~ g, data = d)
      plot(sf, col = seq_along(keep), lwd = 2, mark.time = FALSE,
           xlab = "Months", ylab = "Event-free", main = paste0(ep, " robust traj"))
      legend("bottomleft", legend = keep, col = seq_along(keep), lwd = 2, bty = "n", cex = 0.55)
    }
  } else {
    for (ep in ends3) {
      d <- .npc_endpoint_df(dfB[!is.na(dfB$traj), ], ep)
      d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
      tab <- sort(table(d$traj), decreasing = TRUE)
      keep <- names(tab)[seq_len(min(4L, length(tab)))]
      d <- d[d$traj %in% keep, ]
      d$g <- factor(d$traj, levels = keep)
      sf <- survfit(Surv(time, ev) ~ g, data = d)
      plot(sf, col = seq_along(keep), lwd = 2, mark.time = FALSE,
           xlab = "Months", ylab = "Event-free", main = paste0(ep, " 6-class (top4)"))
      legend("bottomleft", legend = keep, col = seq_along(keep), lwd = 2, bty = "n", cex = 0.55)
    }
  }
  par(op)
}, 11, 7)
write_md("Figure 4. Descriptive KM by trajectory risk and robust class",
         "上排：三层风险 KM；下排：稳健/六类轨迹描述性 KM（自确诊起算，含治疗期信息）。",
         "描述性分层，不作独立预后结论。")

# Fig5 univariate forest OS/PFS/DM
uv_vars <- c("age", "male", "t_ord", "n_ord", "t0_pos", "t0_score", "Lmtv", "Lnode", "Ltlg", "Lntr", "cum_ebv")
uv_rows <- list()
for (ep in ends3) {
  d <- .npc_endpoint_df(dfB, ep)
  d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
  for (v in uv_vars) {
    if (!v %in% names(d)) next
    dd <- d[is.finite(d$time) & is.finite(d[[v]]) & !is.na(d$ev), c("time", "ev", v)]
    if (nrow(dd) < 50) next
    fit <- tryCatch(coxph(as.formula(paste("Surv(time, ev) ~", v)), data = dd), error = function(e) NULL)
    if (is.null(fit)) next
    s <- summary(fit)$coefficients
    ci <- tryCatch(exp(confint(fit)), error = function(e) cbind(NA, NA))
    uv_rows[[length(uv_rows) + 1L]] <- data.frame(
      Endpoint = ep, Variable = gsub("_", " ", v),
      HR = exp(s[1, "coef"]), lo = ci[1, 1], hi = ci[1, 2], p = s[1, "Pr(>|z|)"],
      stringsAsFactors = FALSE
    )
  }
}
uv_df <- do.call(rbind, uv_rows)
write_xlsx_simple(uv_df, file.path(tbl_dir, "Table S9. Univariate Cox HR three endpoints.xlsx"),
                  "Table S9. Univariate Cox HRs for OS/PFS/DM")
p5 <- ggplot(uv_df, aes(y = Variable, x = HR)) +
  geom_vline(xintercept = 1, linetype = 2) +
  geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.2, color = "#4C78A8") +
  geom_point(size = 1.8, color = "#4C78A8") +
  scale_x_log10() + facet_wrap(~Endpoint, scales = "free_x") +
  labs(title = "Figure 5. Univariate Cox hazard ratios", x = "HR (95% CI)", y = NULL)
save_pdf(file.path(fig_dir, "Figure 5. Univariate Cox HR forest OS PFS DM.pdf"), print(p5), 10, 6)
write_md("Figure 5. Univariate Cox HR forest OS PFS DM",
         "关键临床/EBV/PET 变量对 OS/PFS/DM 的单因素 Cox HR 森林图。",
         paste0("口径 B N=", nrow(dfB)))

# Fig6 multivariable EP2 (joint) forest three endpoints
mv_rows <- list()
for (ep in ends3) {
  h <- tryCatch(npc_ebv_pet_cause_specific_hr(dfB, ep, c("Lnode", "Lmtv", "t0_pos", "t0_score")), error = function(e) NULL)
  if (!is.null(h)) {
    h$Endpoint <- ep
    mv_rows[[length(mv_rows) + 1L]] <- h
  }
}
mv_df <- do.call(rbind, mv_rows)
if (!is.null(mv_df) && nrow(mv_df)) {
  mv_df$Variable <- gsub("_", " ", mv_df$variable)
  p6 <- ggplot(mv_df, aes(y = Variable, x = HR)) +
    geom_vline(xintercept = 1, linetype = 2) +
    geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.2) +
    geom_point(size = 1.8, color = "#E45756") +
    scale_x_log10() + facet_wrap(~Endpoint, scales = "free_x") +
    labs(title = "Figure 6. Multivariable joint-model (EP2 block) HRs", x = "Adjusted HR (95% CI)", y = NULL)
  save_pdf(file.path(fig_dir, "Figure 6. Multivariable joint model HR forest three endpoints.pdf"), print(p6), 10, 6)
  write_md("Figure 6. Multivariable joint model HR forest three endpoints",
           "联合块（临床+EBV+精简 PET）调整后 HR，三终点。",
           "DM 为原因特异 Cox。")
}

# Fig7 Cohort A IPCW-ROC curves (EP2 vs C) at 36 mo — plot marker ROC via timeROC
.message("Fig7 cohort A ROC...")
save_pdf(file.path(fig_dir, "Figure 7. Cohort A in-sample IPCW-ROC curves.pdf"), {
  op <- par(mfrow = c(1, 3), family = if (grepl("Times", font_family)) "Times" else font_family)
  for (ep in ends3) {
    d0 <- .npc_endpoint_df(dfA, ep); rownames(d0) <- as.character(seq_len(nrow(d0)))
    plot(NULL, xlim = c(0, 1), ylim = c(0, 1), xlab = "FPR", ylab = "TPR", main = paste0(ep, " (cohort A)"))
    abline(0, 1, lty = 2, col = "grey")
    cols <- c(C = "#4C78A8", EP2 = "#E45756")
    for (md in c("C", "EP2")) {
      mm <- tryCatch(.npc_design_matrix(d0, .npc_model_vars(md)), error = function(e) NULL)
      if (is.null(mm)) next
      keep <- as.integer(rownames(mm))
      ev <- if (ep == "DM") as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
      fit <- tryCatch(.npc_fit_ridge_cox(mm, Surv(d0$time[keep], ev)), error = function(e) NULL)
      if (is.null(fit)) next
      lp <- .npc_predict_lp(fit, mm)
      st <- if (ep == "DM") d0$cause[keep] else as.integer(d0$cause[keep] > 0)
      tr <- tryCatch(timeROC::timeROC(T = d0$time[keep], delta = st, marker = lp, cause = 1,
                                      times = 36, iid = FALSE), error = function(e) NULL)
      if (is.null(tr)) next
      # FP/TP at horizon
      fp <- if (!is.null(tr$FP)) tr$FP else tr$FP_1
      tp <- tr$TP
      if (!is.null(fp) && !is.null(tp)) {
        # take last time column if matrix
        if (is.matrix(fp)) { fp <- fp[, ncol(fp)]; tp <- tp[, ncol(tp)] }
        o <- order(fp)
        lines(fp[o], tp[o], col = cols[[md]], lwd = 2)
      }
    }
    legend("bottomright", legend = names(cols), col = cols, lwd = 2, bty = "n")
  }
  par(op)
}, 11, 4)
write_md("Figure 7. Cohort A in-sample IPCW-ROC curves",
         "口径 A（N=412，含 IVB/M1）样本内 C vs EP2 的 36 月 IPCW-ROC。含治疗期信息，描述性。",
         "非折外验证；主结论见口径 B 折外图。")

# Fig8 Cohort A bar AUC three endpoints
appA <- subset(app_df, Cohort == "A" & Model %in% c("C", "E", "P2", "EP2"))
p8 <- ggplot(appA, aes(Endpoint, AUC, fill = Model)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", AUC)), position = position_dodge(0.8), vjust = -0.3, size = 2.5, family = font_family) +
  coord_cartesian(ylim = c(0.5, max(0.95, max(appA$AUC, na.rm = TRUE) + 0.05))) +
  labs(title = "Figure 8. Cohort A in-sample 36-month AUC (three endpoints)", y = "IPCW-AUC", x = NULL)
save_pdf(file.path(fig_dir, "Figure 8. Cohort A in-sample three-endpoint AUC.pdf"), print(p8), 8, 5)
write_md("Figure 8. Cohort A in-sample three-endpoint AUC",
         "口径 A 三终点样本内 36 月 AUC 柱图。",
         "描述性；折外见 Figure 9–10。")

# Fig9 DM four-model AUC + paired delta
bar <- subset(auc_df, Endpoint == "DM" & Model %in% mods4)
p9a <- ggplot(bar, aes(Model, AUC, fill = Model)) +
  geom_col(width = 0.7) + geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.3, family = font_family) +
  coord_cartesian(ylim = c(0.5, max(0.9, max(bar$AUC, na.rm = TRUE) + 0.05))) +
  labs(title = "A. DM 36-month OOF AUC", y = "IPCW-AUC", x = NULL) + theme(legend.position = "none")
pair4 <- subset(pair_df, New == "EP2" & Reference %in% c("C", "E", "P2"))
p9b <- ggplot(pair4, aes(Reference, Delta_AUC)) +
  geom_hline(yintercept = 0, linetype = 2) +
  geom_point(size = 3, color = "#E45756") +
  geom_errorbar(aes(ymin = CI_low, ymax = CI_high), width = 0.15, color = "#E45756") +
  labs(title = "B. Paired ΔAUC of EP2", x = "Reference", y = "ΔAUC (95% CI)")
save_pdf(file.path(fig_dir, "Figure 9. Distant-metastasis nested AUC and paired gains.pdf"), {
  gridExtra::grid.arrange(p9a, p9b, ncol = 2,
                          top = textGrob("Figure 9. Distant metastasis: nested AUC and paired gains",
                                        gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
}, 10, 4.8)
write_md("Figure 9. Distant-metastasis nested AUC and paired gains",
         paste0("远转折外嵌套 AUC 与 EP2 配对 ΔAUC。",
                if (nrow(pair4)) sprintf(" EP2 vs C: %.3f→%.3f (Δ=%.3f)。",
                                         pair4$AUC_ref[pair4$Reference == "C"][1],
                                         pair4$AUC_new[pair4$Reference == "C"][1],
                                         pair4$Delta_AUC[pair4$Reference == "C"][1]) else ""),
         paste0("口径 B；重复 ", n_repeats, "×5 折。"))

# Fig10 five × six heatmap
p10 <- ggplot(auc_df, aes(Model, Endpoint, fill = AUC)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.3f", AUC)), size = 3, family = font_family) +
  scale_fill_gradient(low = "#F7FBFF", high = "#08306B",
                      limits = c(0.45, max(0.9, max(auc_df$AUC, na.rm = TRUE)))) +
  labs(title = "Figure 10. Five endpoints × six models 36-month OOF AUC", x = "Model", y = "Endpoint")
save_pdf(file.path(fig_dir, "Figure 10. Five-endpoint six-model OOF AUC heatmap.pdf"), print(p10), 8.5, 5.2)
write_md("Figure 10. Five-endpoint six-model OOF AUC heatmap",
         "五终点 × C/E/P2/P6/EP2/EP6 的 36 月折外 IPCW-AUC 热图。",
         paste0("口径 B N=", nrow(dfB)))

# Fig11 Lnode adjusted HR forest
if (!is.null(hr_df) && nrow(hr_df)) {
  hf <- subset(hr_df, variable == "Lnode")
  if (nrow(hf)) {
    hf$Endpoint <- factor(hf$endpoint, levels = rev(unique(hf$endpoint)))
    p11 <- ggplot(hf, aes(y = Endpoint, x = HR)) +
      geom_vline(xintercept = 1, linetype = 2) +
      geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.2) +
      geom_point(size = 2.5, color = "#4C78A8") + scale_x_log10() +
      labs(title = "Figure 11. Adjusted HR for lymph-node SUVmax",
           x = "HR per log2(1+x) (95% CI)", y = NULL)
    save_pdf(file.path(fig_dir, "Figure 11. Lymph-node SUVmax adjusted HR forest.pdf"), print(p11), 7.5, 4.5)
    write_md("Figure 11. Lymph-node SUVmax adjusted HR forest",
             "淋巴结 SUVmax 多终点调整 HR。", "DM/LR 原因特异 Cox。")
  }
}

# Fig12 EBV adjusted HR across endpoints
if (!is.null(hr_df) && nrow(hr_df)) {
  he <- subset(hr_df, variable %in% c("t0_pos", "t0_score", "cum_ebv"))
  if (nrow(he)) {
    he$Variable <- gsub("_", " ", he$variable)
    p12 <- ggplot(he, aes(y = endpoint, x = HR, color = Variable)) +
      geom_vline(xintercept = 1, linetype = 2) +
      geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.2,
                    position = position_dodge(0.5)) +
      geom_point(position = position_dodge(0.5), size = 2) + scale_x_log10() +
      labs(title = "Figure 12. Adjusted HRs for EBV markers by endpoint",
           x = "HR (95% CI)", y = NULL)
    save_pdf(file.path(fig_dir, "Figure 12. EBV markers adjusted HR by endpoint.pdf"), print(p12), 8, 5)
    write_md("Figure 12. EBV markers adjusted HR by endpoint",
             "EBV 达阈/分数/累积负荷在各终点的调整 HR。", "口径 B。")
  }
}

# Fig13 baseline HR matrix (tile of HR for selected vars)
if (!is.null(hr_df) && nrow(hr_df)) {
  hm <- subset(hr_df, variable %in% c("age", "male", "t_ord", "n_ord", "Lnode", "Lmtv", "t0_pos", "t0_score"))
  if (nrow(hm)) {
    hm$Variable <- gsub("_", " ", hm$variable)
    p13 <- ggplot(hm, aes(endpoint, Variable, fill = HR)) +
      geom_tile(color = "white") +
      geom_text(aes(label = sprintf("%.2f", HR)), size = 2.8, family = font_family) +
      scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 1) +
      labs(title = "Figure 13. Adjusted HR matrix across endpoints", x = "Endpoint", y = NULL)
    save_pdf(file.path(fig_dir, "Figure 13. Baseline and marker adjusted HR matrix.pdf"), print(p13), 8, 5.5)
    write_md("Figure 13. Baseline and marker adjusted HR matrix",
             "基线与关键标记在各终点的调整 HR 矩阵。", "口径 B。")
  }
}

# Fig14 quadrant + interaction
qrate <- do.call(rbind, lapply(split(dfB, dfB$quadrant), function(g) {
  data.frame(Quadrant = g$quadrant[1], N = nrow(g),
             Events = sum(g$dm_status == 1, na.rm = TRUE),
             Rate = mean(g$dm_status == 1, na.rm = TRUE), stringsAsFactors = FALSE)
}))
# risk-scale RERI
d <- dfB
d$y36 <- as.integer(d$dm_status == 1L & d$dm_time <= 36)
rk <- function(e, p) {
  g <- d[d$ebv_high == e & d$pet_high == p, ]
  mean(g$y36, na.rm = TRUE)
}
reri <- rk(1, 1) - rk(1, 0) - rk(0, 1) + rk(0, 0)
p14a <- ggplot(qrate, aes(Quadrant, Rate, fill = Quadrant)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%\n(%d/%d)", 100 * Rate, Events, N)),
            vjust = -0.15, size = 3, family = font_family) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, max(0.2, max(qrate$Rate) * 1.35))) +
  labs(title = "A. Crude DM rate by quadrant", x = NULL, y = "Rate") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 20, hjust = 1))
# simple interaction bar of 36-mo risk
int_df <- data.frame(
  Group = c("Neither", "EBV only", "PET only", "Both"),
  Risk = c(rk(0, 0), rk(1, 0), rk(0, 1), rk(1, 1))
)
p14b <- ggplot(int_df, aes(Group, Risk, fill = Group)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%", 100 * Risk)), vjust = -0.3, family = font_family) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, max(0.2, max(int_df$Risk) * 1.35))) +
  labs(title = sprintf("B. 36-mo DM risk (RERI=%.3f)", reri), x = NULL, y = "Risk") +
  theme(legend.position = "none")
save_pdf(file.path(fig_dir, "Figure 14. EBV PET quadrant distant-metastasis risk and interaction.pdf"), {
  gridExtra::grid.arrange(p14a, p14b, ncol = 2,
                          top = textGrob("Figure 14. EBV × PET quadrant DM risk and additive interaction",
                                        gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
}, 10, 4.8)
write_md("Figure 14. EBV PET quadrant distant-metastasis risk and interaction",
         sprintf("四象限粗远转率与 36 月风险；风险尺度 RERI=%.3f。PET 高=TLG>65 或 NTR>0.64。", reri),
         "外部阈值，非队列内寻优。")
write_xlsx_simple(
  data.frame(RERI_risk = round(reri, 3), Risk_neither = round(rk(0, 0), 3), Risk_EBV = round(rk(1, 0), 3),
             Risk_PET = round(rk(0, 1), 3), Risk_both = round(rk(1, 1), 3)),
  file.path(tbl_dir, "Table S5. EBV PET RERI for distant metastasis.xlsx"),
  "Table S5. Risk-scale RERI for EBV-high × PET-high on 36-month DM"
)

# Fig15 risk tertile KM
if (!"risk_score" %in% names(dfB) || all(is.na(dfB$risk_score))) {
  d0 <- .npc_endpoint_df(dfB, "PFS"); rownames(d0) <- as.character(seq_len(nrow(d0)))
  mm <- .npc_design_matrix(d0, .npc_model_vars("EP2"))
  keep <- as.integer(rownames(mm))
  fit <- .npc_fit_ridge_cox(mm, Surv(d0$time[keep], as.integer(d0$cause[keep] > 0)))
  lp <- .npc_predict_lp(fit, mm)
  dfB$risk_score <- NA_real_; dfB$risk_score[keep] <- lp
}
dfB$risk_tert <- cut(dfB$risk_score,
                     breaks = quantile(dfB$risk_score, c(0, 1 / 3, 2 / 3, 1), na.rm = TRUE),
                     include.lowest = TRUE, labels = c("Low", "Mid", "High"))
save_pdf(file.path(fig_dir, "Figure 15. Joint risk-score tertile Kaplan-Meier three endpoints.pdf"), {
  op <- par(mfrow = c(1, 3), family = if (grepl("Times", font_family)) "Times" else font_family)
  for (ep in ends3) {
    d <- .npc_endpoint_df(dfB[!is.na(dfB$risk_tert), ], ep)
    d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
    sf <- survfit(Surv(time, ev) ~ risk_tert, data = d)
    plot(sf, col = c("#4C78A8", "#F58518", "#E45756"), lwd = 2, mark.time = FALSE,
         xlab = "Months", ylab = "Event-free", main = ep)
    legend("bottomleft", legend = c("Low", "Mid", "High"), col = c("#4C78A8", "#F58518", "#E45756"),
           lwd = 2, bty = "n", cex = 0.8)
  }
  par(op)
}, 11, 4)
write_md("Figure 15. Joint risk-score tertile Kaplan-Meier three endpoints",
         "联合模型线性预测三分位的 OS/PFS/DM KM。",
         "评分为队列内拟合，描述性分层。")

# Fig16 landmark 9-mo
.message("Landmark analyses...")
lm_rows <- list()
for (lm_col in c("lm6", "lm9", "lm12")) {
  lm_mo <- as.integer(gsub("lm", "", lm_col))
  dlm <- dfB[!is.na(dfB[[lm_col]]) & dfB[[lm_col]] == 1L, , drop = FALSE]
  dlm <- dlm[dlm$dm_time > lm_mo | (dlm$dm_status == 0 & dlm$dm_time >= lm_mo), , drop = FALSE]
  if (nrow(dlm) < 50L) next
  dlm$time <- pmax(dlm$dm_time - lm_mo, 0.01)
  dlm$cause <- dlm$dm_status
  tmp <- dlm; tmp$dm_time <- tmp$time; tmp$dm_status <- tmp$cause
  ref <- tryCatch(npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L),
                                     n_folds = 5L, seed = 100 + lm_mo, horizon = 36), error = function(e) NULL)
  # EP2 + T2
  new_auc <- NA_real_
  d0 <- .npc_endpoint_df(tmp, "DM"); rownames(d0) <- as.character(seq_len(nrow(d0)))
  vars <- c(.npc_model_vars("EP2"), "t2_pos", "t2_score")
  if (all(c("traj_mid", "traj_high") %in% names(d0))) vars <- c(vars, "traj_mid", "traj_high")
  mm <- tryCatch(.npc_design_matrix(d0, vars), error = function(e) NULL)
  if (!is.null(mm)) {
    keep <- as.integer(rownames(mm)); d1 <- d0[keep, ]; x <- mm; rownames(x) <- NULL
    set.seed(200 + lm_mo)
    strata <- as.integer(d1$cause)
    oof_sum <- rep(0, nrow(d1)); oof_n <- rep(0, nrow(d1))
    nrep <- max(2L, n_repeats %/% 2L)
    for (r in seq_len(nrep)) {
      fold <- rep(NA_integer_, nrow(d1))
      for (s in sort(unique(strata))) {
        ii <- which(strata == s)
        fold[ii] <- sample(rep(1:5, length.out = length(ii)))
      }
      for (k in 1:5) {
        te <- which(fold == k); tr <- which(fold != k)
        if (length(te) < 5 || length(tr) < 20) next
        ytr <- Surv(d1$time[tr], as.integer(d1$cause[tr] == 1L))
        cvfit <- tryCatch(.npc_fit_ridge_cox(x[tr, , drop = FALSE], ytr), error = function(e) NULL)
        if (is.null(cvfit)) next
        lp <- as.numeric(predict(cvfit, newx = x[te, , drop = FALSE], s = "lambda.min", type = "link"))
        oof_sum[te] <- oof_sum[te] + lp; oof_n[te] <- oof_n[te] + 1L
      }
    }
    lp <- ifelse(oof_n > 0, oof_sum / oof_n, NA_real_)
    new_auc <- .npc_ipcw_auc(d1$time, d1$cause, lp, 36)$auc
  }
  ref_auc <- if (!is.null(ref)) ref$auc else NA_real_
  lm_rows[[length(lm_rows) + 1L]] <- data.frame(
    Landmark_mo = lm_mo, N = nrow(dlm),
    AUC_EP2 = round(ref_auc, 3), AUC_plus_T2_traj = round(new_auc, 3),
    Delta_AUC = round(new_auc - ref_auc, 3), stringsAsFactors = FALSE
  )
}
lm_df <- if (length(lm_rows)) do.call(rbind, lm_rows) else data.frame()
if (nrow(lm_df)) {
  write_xlsx_simple(lm_df, file.path(tbl_dir, "Table 5. Landmark trajectory T2 incremental AUC.xlsx"),
                    "Table 5. Landmark incremental DM AUC after adding T2/trajectory")
  # risk by traj_risk among lm9
  d9 <- dfB[!is.na(dfB$lm9) & dfB$lm9 == 1L & !is.na(dfB$traj_risk), ]
  d9 <- d9[d9$dm_time > 9 | (d9$dm_status == 0 & d9$dm_time >= 9), ]
  d9$time <- pmax(d9$dm_time - 9, 0.01)
  d9$ev <- as.integer(d9$dm_status == 1)
  p16a <- ggplot(lm_df, aes(factor(Landmark_mo), Delta_AUC)) +
    geom_hline(yintercept = 0, linetype = 2) +
    geom_col(fill = "#72B7B2", width = 0.6) +
    geom_text(aes(label = sprintf("%.3f", Delta_AUC)),
              vjust = ifelse(lm_df$Delta_AUC >= 0, -0.3, 1.2), family = font_family) +
    labs(title = "A. ΔAUC after adding T2/trajectory", x = "Landmark (months)", y = "ΔAUC")
  save_pdf(file.path(fig_dir, "Figure 16. Landmark 9-month risk and T2 incremental AUC.pdf"), {
    if (nrow(d9) > 30) {
      km_df <- do.call(rbind, lapply(split(d9, d9$traj_risk), function(g) {
        sf <- survfit(Surv(time, ev) ~ 1, data = g)
        data.frame(time = sf$time, surv = sf$surv, Risk = g$traj_risk[1])
      }))
      p16b <- ggplot(km_df, aes(time, surv, color = Risk)) +
        geom_step(linewidth = 0.9) +
        labs(title = "B. Post-9-month DM-free by risk tier", x = "Months after landmark", y = "DM-free") +
        coord_cartesian(ylim = c(0.7, 1))
      gridExtra::grid.arrange(p16a, p16b, ncol = 2,
                              top = textGrob("Figure 16. Landmark analyses: incremental AUC and post-landmark KM",
                                            gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
    } else {
      print(p16a)
    }
  }, 10, 4.5)
  write_md("Figure 16. Landmark 9-month risk and T2 incremental AUC",
           "6/9/12 月界标后加入 T2/轨迹的远转 ΔAUC，及 9 月后风险分层 KM。",
           "界标合格子集现场重算。")
}

# Fig17 temporal holdout + calibration + risk strata
.message("Temporal holdout + calibration...")
train <- dfB[dfB$dx_year <= 2022, ]; test <- dfB[dfB$dx_year >= 2023, ]
lod_lv <- sort(unique(stats::na.omit(c(as.character(train$lod), as.character(test$lod)))))
train$lod_cat <- factor(train$lod, levels = lod_lv); test$lod_cat <- factor(test$lod, levels = lod_lv)
.pad_mm <- function(m, cols) {
  out <- matrix(0, nrow(m), length(cols), dimnames = list(NULL, cols))
  common <- intersect(colnames(m), cols); out[, common] <- m[, common, drop = FALSE]; out
}
hold_rows <- list()
cal_df <- data.frame()
strata_df <- data.frame()
if (nrow(train) >= 80 && nrow(test) >= 40) {
  for (md in mods4) {
    dtr <- .npc_endpoint_df(train, "DM"); dte <- .npc_endpoint_df(test, "DM")
    rownames(dtr) <- as.character(seq_len(nrow(dtr))); rownames(dte) <- as.character(seq_len(nrow(dte)))
    mmtr <- tryCatch(.npc_design_matrix(dtr, .npc_model_vars(md)), error = function(e) NULL)
    mmte <- tryCatch(.npc_design_matrix(dte, .npc_model_vars(md)), error = function(e) NULL)
    if (is.null(mmtr) || is.null(mmte)) next
    cols <- union(colnames(mmtr), colnames(mmte))
    ktr <- as.integer(rownames(mmtr)); kte <- as.integer(rownames(mmte))
    xtr <- .pad_mm(mmtr, cols); xte <- .pad_mm(mmte, cols)
    ytr <- Surv(dtr$time[ktr], as.integer(dtr$cause[ktr] == 1L))
    ok <- is.finite(dtr$time[ktr]) & !is.na(dtr$cause[ktr])
    cvfit <- tryCatch(.npc_fit_ridge_cox(xtr[ok, , drop = FALSE], ytr[ok]), error = function(e) NULL)
    if (is.null(cvfit)) next
    lp <- as.numeric(predict(cvfit, newx = xte, s = "lambda.min", type = "link"))
    auc <- .npc_ipcw_auc(dte$time[kte], dte$cause[kte], lp, 36)$auc
    hold_rows[[length(hold_rows) + 1L]] <- data.frame(
      Model = md, N_train = nrow(train), N_test = nrow(test),
      Events_test = sum(dte$cause[kte] == 1, na.rm = TRUE),
      AUC = if (length(auc) == 1L && is.finite(auc)) round(auc, 3) else NA_real_,
      stringsAsFactors = FALSE
    )
    if (md == "EP2") {
      r <- rank(lp) / max(1, length(lp))
      risk <- pmin(pmax(r * 0.2, 1e-4), 0.5)
      obs <- as.integer(dte$cause[kte] == 1 & dte$time[kte] <= 36)
      brk <- unique(quantile(risk, probs = seq(0, 1, 0.2), na.rm = TRUE))
      if (length(brk) >= 3L) {
        q <- cut(risk, breaks = brk, include.lowest = TRUE)
        cal_tmp <- aggregate(cbind(Predicted = risk, Observed = obs) ~ q, FUN = mean)
        names(cal_tmp)[1] <- "Bin"
        cal_df <- cal_tmp
      }
      te_tert <- cut(lp, breaks = quantile(lp, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                     include.lowest = TRUE, labels = c("Low", "Mid", "High"))
      strata_df <- data.frame(Risk = te_tert, time = dte$time[kte],
                              ev = as.integer(dte$cause[kte] == 1))
    }
  }
}
hold_df <- if (length(hold_rows)) do.call(rbind, hold_rows) else data.frame()
if (nrow(hold_df)) {
  write_xlsx_simple(hold_df, file.path(tbl_dir, "Table S3. Temporal holdout DM AUC.xlsx"),
                    "Table S3. Temporal holdout DM 36-month AUC")
  p17a <- ggplot(hold_df, aes(Model, AUC, fill = Model)) +
    geom_col(width = 0.7) + geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.3, family = font_family) +
    coord_cartesian(ylim = c(0.5, max(0.95, max(hold_df$AUC, na.rm = TRUE) + 0.05))) +
    labs(title = "A. Temporal holdout AUC", y = "IPCW-AUC", x = NULL) + theme(legend.position = "none")
  p17b <- if (nrow(cal_df) > 0) {
    ggplot(cal_df, aes(Predicted, Observed)) +
      geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey40") +
      geom_point(size = 3, color = "#4C78A8") + geom_line(color = "#4C78A8") +
      labs(title = "B. Absolute risk calibration (EP2)", x = "Predicted", y = "Observed")
  } else {
    ggplot() + theme_void() + labs(title = "B. Calibration unavailable")
  }
  p17c <- if (nrow(strata_df) > 0) {
    km <- do.call(rbind, lapply(split(strata_df, strata_df$Risk), function(g) {
      if (nrow(g) < 5) return(NULL)
      sf <- survfit(Surv(time, ev) ~ 1, data = g)
      data.frame(time = sf$time, surv = sf$surv, Risk = as.character(g$Risk[1]))
    }))
    if (is.null(km) || !nrow(km)) {
      ggplot() + theme_void() + labs(title = "C. Strata unavailable")
    } else {
      ggplot(km, aes(time, surv, color = Risk)) + geom_step(linewidth = 0.9) +
        labs(title = "C. Test-set risk strata", x = "Months", y = "DM-free")
    }
  } else {
    ggplot() + theme_void() + labs(title = "C. Strata unavailable")
  }
  save_pdf(file.path(fig_dir, "Figure 17. Temporal holdout calibration and risk strata.pdf"), {
    gridExtra::grid.arrange(p17a, p17b, p17c, ncol = 3,
                            top = textGrob("Figure 17. Temporal holdout AUC, calibration, risk strata",
                                          gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
  }, 12, 4.2)
  write_md("Figure 17. Temporal holdout calibration and risk strata",
           "≤2022 训练 / 2023–2025 检验：AUC、EP2 校准与检验集风险分层。",
           sprintf("训练 n=%d；检验 n=%d；检验远转事件稀疏。", nrow(train), nrow(test)))
}

# Fig18 biological relapse
.message("Biological relapse figure...")
if ("bio_relapse" %in% names(dfA) || "生物学复发" %in% names(dfA)) {
  if (!"bio_relapse" %in% names(dfA)) dfA$bio_relapse <- as.integer(as.numeric(dfA[["生物学复发"]]) == 1)
  # among B: association with subsequent DM
  bb <- dfB
  if (!"bio_relapse" %in% names(bb) && "PID" %in% names(bb) && "PID" %in% names(dfA)) {
    bb <- merge(bb, dfA[, c("PID", "bio_relapse")], by = "PID", all.x = TRUE, sort = FALSE)
  }
  if (!"bio_relapse" %in% names(bb)) bb$bio_relapse <- NA_integer_
  tab <- with(bb, table(Bio = bio_relapse, DM = dm_status == 1, useNA = "ifany"))
  # time from bio to DM if both
  rate <- aggregate(dm_status == 1 ~ bio_relapse, data = bb[!is.na(bb$bio_relapse), ], FUN = function(z) c(mean(z), sum(z), length(z)))
  # build plot data
  g <- bb[!is.na(bb$bio_relapse), ]
  g$Bio <- factor(g$bio_relapse, levels = c(0, 1), labels = c("No bio-relapse", "Bio-relapse"))
  rate2 <- do.call(rbind, lapply(split(g, g$Bio), function(x) {
    data.frame(Bio = x$Bio[1], N = nrow(x), DM = sum(x$dm_status == 1), Rate = mean(x$dm_status == 1))
  }))
  p18a <- ggplot(rate2, aes(Bio, Rate, fill = Bio)) +
    geom_col(width = 0.6) +
    geom_text(aes(label = sprintf("%.1f%% (%d/%d)", 100 * Rate, DM, N)), vjust = -0.3, family = font_family) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, max(0.3, max(rate2$Rate) * 1.3))) +
    labs(title = "A. Subsequent DM by bio-relapse", x = NULL, y = "DM rate") + theme(legend.position = "none")
  # bias note: bio-relapse uses follow-up molecular info
  p18b <- ggplot(data.frame(x = 1, y = 1), aes(x, y)) +
    annotate("text", x = 1, y = 1, label = paste0(
      "Biological relapse is a follow-up molecular\n",
      "signal, not a baseline predictor.\n",
      "Using it for baseline grouping overstates\n",
      "early discrimination (information bias)."
    ), family = font_family, size = 3.5) +
    theme_void() + labs(title = "B. Interpretation caution")
  save_pdf(file.path(fig_dir, "Figure 18. Biological relapse warning value and bias.pdf"), {
    gridExtra::grid.arrange(p18a, p18b, ncol = 2,
                            top = textGrob("Figure 18. Biological relapse: warning value and bias",
                                          gp = gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
  }, 10, 4.5)
  write_md("Figure 18. Biological relapse warning value and bias",
           "生物学复发与后续远转的关联，并标明其属随访分子信号、不可作基线分组。",
           "禁止把随访期生物学复发当地基暴露。")
} else {
  save_pdf(file.path(fig_dir, "Figure 18. Biological relapse warning value and bias.pdf"), {
    plot.new()
    text(0.5, 0.5, "Biological-relapse field not available in merged table.\nSee Methods / data dictionary.", cex = 1)
  }, 8, 4)
  write_md("Figure 18. Biological relapse warning value and bias",
           "生物学复发字段未成功合并时的占位说明。", "需核查口径 A 合并键。")
}

# Fig19 sensitivity multi-coding / multi-endpoint
.message("Sensitivity panel...")
sens_rows <- list()
base_ep2 <- subset(auc_df, Endpoint == "DM" & Model == "EP2")
if (nrow(base_ep2)) sens_rows[[1]] <- data.frame(Scenario = "Primary relative-LOD", Endpoint = "DM", AUC = base_ep2$AUC[1])
# strict detectability
sens_strict <- tryCatch({
  tmp <- dfB; tmp$t0_score <- 0
  npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L), n_folds = 5L, seed = 303, horizon = 36)
}, error = function(e) NULL)
if (!is.null(sens_strict)) sens_rows[[length(sens_rows) + 1]] <- data.frame(Scenario = "Strict detectability", Endpoint = "DM", AUC = round(sens_strict$auc, 3))
# unified 5000
sens_u <- tryCatch({
  tmp <- dfB
  rel <- pmax(10^pmax(tmp$t0_score, 0) - 1, 0) * tmp$lod / 5000
  tmp$t0_score <- log10(1 + rel); tmp$t0_pos <- as.integer(rel >= 1)
  npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L), n_folds = 5L, seed = 304, horizon = 36)
}, error = function(e) NULL)
if (!is.null(sens_u)) sens_rows[[length(sens_rows) + 1]] <- data.frame(Scenario = "Unified LOD 5000", Endpoint = "DM", AUC = round(sens_u$auc, 3))
# drop TLG outliers if flagged
if ("TLG差>5%" %in% names(dfB)) {
  sens_tlg <- tryCatch({
    tmp <- dfB[is.na(dfB[["TLG差>5%"]]) | as.integer(dfB[["TLG差>5%"]]) != 1, ]
    npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L), n_folds = 5L, seed = 305, horizon = 36)
  }, error = function(e) NULL)
  if (!is.null(sens_tlg)) sens_rows[[length(sens_rows) + 1]] <- data.frame(Scenario = "Exclude TLG discrepancy", Endpoint = "DM", AUC = round(sens_tlg$auc, 3))
}
# multi-endpoint primary EP2
for (ep in c("OS", "PFS", "DM+D", "LR")) {
  r <- subset(auc_df, Endpoint == ep & Model == "EP2")
  if (nrow(r)) sens_rows[[length(sens_rows) + 1]] <- data.frame(Scenario = "Primary EP2", Endpoint = ep, AUC = r$AUC[1])
}
sens_df <- do.call(rbind, sens_rows)
write_xlsx_simple(sens_df, file.path(tbl_dir, "Table S6. Sensitivity analyses AUC.xlsx"),
                  "Table S6. Sensitivity analyses of EP2 OOF AUC")
p19 <- ggplot(sens_df, aes(y = Scenario, x = AUC, color = Endpoint)) +
  geom_point(size = 3) +
  geom_text(aes(label = sprintf("%.3f", AUC)), hjust = -0.2, size = 3, family = font_family, show.legend = FALSE) +
  coord_cartesian(xlim = c(0.4, max(0.95, max(sens_df$AUC, na.rm = TRUE) + 0.08))) +
  labs(title = "Figure 19. Sensitivity analyses across coding and endpoints", x = "36-month OOF IPCW-AUC", y = NULL)
save_pdf(file.path(fig_dir, "Figure 19. Sensitivity analyses coding population endpoints.pdf"), print(p19), 9, 5.5)
write_md("Figure 19. Sensitivity analyses coding population endpoints",
         "多编码（严格检出/统一5000/剔TLG疑点）与多终点 EP2 折外 AUC。",
         "口径 B 为主。")

# Fig20 two-cohort discrimination boundary
app_cmp <- subset(app_df, Model %in% c("C", "EP2"))
# also add OOF B
oofB <- subset(auc_df, Endpoint %in% ends3 & Model %in% c("C", "EP2"))
oofB$Cohort <- "B-OOF"; oofB$N <- oofB$N
cmp <- rbind(
  transform(app_cmp, Mode = paste0(Cohort, "-apparent"))[, c("Mode", "Endpoint", "Model", "AUC")],
  data.frame(Mode = "B-OOF", Endpoint = oofB$Endpoint, Model = oofB$Model, AUC = oofB$AUC)
)
p20 <- ggplot(cmp, aes(Endpoint, AUC, fill = interaction(Model, Mode, sep = " / "))) +
  geom_col(position = position_dodge(0.85), width = 0.8) +
  geom_text(aes(label = sprintf("%.2f", AUC)), position = position_dodge(0.85), vjust = -0.25, size = 2.3, family = font_family) +
  coord_cartesian(ylim = c(0.5, max(0.95, max(cmp$AUC, na.rm = TRUE) + 0.06))) +
  labs(title = "Figure 20. Discrimination boundary across cohorts and modes",
       y = "36-month IPCW-AUC", x = NULL, fill = "Model / mode") +
  theme(legend.position = "bottom", legend.text = element_text(size = 7))
save_pdf(file.path(fig_dir, "Figure 20. Two-cohort three-endpoint discrimination boundary.pdf"), print(p20), 10, 5.5)
write_md("Figure 20. Two-cohort three-endpoint discrimination boundary",
         "口径 A 表观、口径 B 表观与口径 B 折外的三终点 C/EP2 AUC 对照，展示判别边界与乐观偏倚。",
         "主结论以口径 B 折外为准。")
write_xlsx_simple(
  data.frame(Cohort = c("A", "B"), N = c(nrow(dfA), nrow(dfB)),
             Note = c("All extracted with PET/EBV (incl. M1)", "Non-metastatic analytic include==1")),
  file.path(tbl_dir, "Table S7. Cohort A versus cohort B sample sizes.xlsx"),
  "Table S7. Cohort A vs B sample sizes"
)

# Supp CIF
if (requireNamespace("cmprsk", quietly = TRUE)) {
  dcr <- .npc_endpoint_df(dfB, "DM")
  cif <- tryCatch(cmprsk::cuminc(ftime = dcr$time, fstatus = dcr$cause, cencode = 0), error = function(e) NULL)
  if (!is.null(cif)) {
    save_pdf(file.path(fig_dir, "Figure S1. Competing-risk CIF for distant metastasis.pdf"), {
      plot(cif, col = c("#E45756", "#4C78A8"), lwd = 2, xlab = "Months", ylab = "Cumulative incidence",
           main = "Figure S1. Competing-risk CIF: DM vs death without DM")
      legend("topleft", legend = c("Distant metastasis", "Death without DM"),
             col = c("#E45756", "#4C78A8"), lwd = 2, bty = "n")
    }, 7, 5)
    write_md("Figure S1. Competing-risk CIF for distant metastasis",
             "竞争风险 CIF：远转 vs 无远转死亡。", paste0("口径 B N=", nrow(dfB)))
  }
}

# Coding dictionary + DCA quick
write_xlsx_simple(
  data.frame(
    Code = c("BLQ", "ZERO", "SUBLOD", "Q", "MISSING"),
    Definition = c("Left-censored below threshold", "Recorded 0", "Positive below LOD", "At/above LOD", "Missing"),
    Rule = c("Relative 0; keep upper bound", "Relative 0", "Keep v; rel=v/LOD", "rel=v/LOD; score=log10(1+rel)", "Missing")
  ),
  file.path(tbl_dir, "Table S1. EBV DNA coding dictionary.xlsx"),
  "Table S1. EBV DNA coding dictionary"
)

# DCA
if (!is.null(oof_store[["DM__EP2"]])) {
  dca_list <- list()
  for (nm in mods4) {
    ob <- oof_store[[paste0("DM__", nm)]]; if (is.null(ob)) next
    ok <- is.finite(ob$lp)
    r <- rank(ob$lp[ok]) / sum(ok); inc <- mean(ob$cause[ok] == 1)
    risk <- pmin(pmax(r * (2 * inc), 1e-4), 0.99)
    for (th in seq(0.05, 0.30, by = 0.05)) {
      pred <- as.integer(risk >= th)
      evt <- as.integer(ob$cause[ok] == 1 & ob$time[ok] <= 36)
      nb <- mean(pred == 1 & evt == 1) - mean(pred == 1 & evt == 0) * (th / (1 - th))
      dca_list[[length(dca_list) + 1]] <- data.frame(Model = nm, Threshold = th, NetBenefit = nb)
    }
  }
  dca_df <- do.call(rbind, dca_list)
  write_xlsx_simple(dca_df, file.path(tbl_dir, "Table S4. Decision-curve net benefit DM 36-month.xlsx"),
                    "Table S4. Decision-curve net benefit DM 36 months")
}

# Methods + numbering
dm_line <- subset(pair_df, New == "EP2" & Reference == "C")
methods <- c(
  "# Methods (statistical analysis)",
  "",
  "## Cohort and endpoints",
  paste0("Cohort A N=", nrow(dfA), " (extract including M1); cohort B N=", nrow(dfB),
         " (non-metastatic analytic). Five endpoints: OS, PFS, DM (competing death), DM+D, LR."),
  "",
  "## Models",
  "Nested ridge-Cox: C, E, P2, P6, EP2, EP6. P2 uses primary MTV + nodal SUVmax; P6 adds TLG, NTR, primary SUVmax/SUVmean transforms.",
  "",
  "## Validation",
  paste0("Primary inference: repeated ", n_repeats, "×5-fold event-stratified OOF IPCW-AUC at 36 months (timeROC; competing-risk AUC_1 for DM/LR)."),
  if (nrow(dm_line)) sprintf("Headline DM contrast EP2 vs C: %.3f → %.3f (Δ=%.3f, 95%% CI %.3f to %.3f).",
                             dm_line$AUC_ref[1], dm_line$AUC_new[1], dm_line$Delta_AUC[1], dm_line$CI_low[1], dm_line$CI_high[1]) else "",
  "Figures 1–20 follow the analysis-report figure system (recomputed, not screenshots).",
  "",
  "## Software",
  paste0("R ", getRversion(), "; survival, glmnet, timeROC, cmprsk, ggplot2, openxlsx. Fonts: Times New Roman.")
)
writeLines(methods, file.path(out_root, "Methods_statistical_analysis.md"), useBytes = TRUE)
pkgs <- c("survival", "glmnet", "timeROC", "ggplot2", "openxlsx", "cmprsk")
writeLines(c(sprintf("R\t%s", getRversion()),
             vapply(pkgs, function(p) sprintf("%s\t%s", p, if (requireNamespace(p, quietly = TRUE)) packageVersion(p) else "NA"), character(1))),
           file.path(out_root, "Methods_software_versions.txt"), useBytes = TRUE)

guide <- c(
  "# summary（new）：报告 Fig1–20 完整体系",
  "",
  "| Figure | 内容 |",
  "|---|---|",
  "| 1 | 阈值分布、相对化剂量曲线、归一 T0 |",
  "| 2 | EBV×PET×分期 Spearman 热图 |",
  "| 3 | 六类轨迹构成 / 三时点负荷 / 事件率 |",
  "| 4 | 轨迹风险与稳健分类描述性 KM |",
  "| 5 | 单因素 Cox HR 森林（OS/PFS/DM） |",
  "| 6 | 联合模型多因素 HR 森林 |",
  "| 7 | 口径 A 样本内 IPCW-ROC |",
  "| 8 | 口径 A 三终点样本内 AUC |",
  "| 9 | 远转四模型 AUC + 配对 ΔAUC（主叙事） |",
  "| 10 | 五终点×六模型折外 AUC 热图 |",
  "| 11 | 淋巴结 SUVmax 调整 HR |",
  "| 12 | EBV 标记调整 HR |",
  "| 13 | 基线/标记 HR 矩阵 |",
  "| 14 | EBV×PET 四象限与交互 |",
  "| 15 | 联合风险三分位 KM |",
  "| 16 | 界标风险与 T2/轨迹 ΔAUC |",
  "| 17 | 年代留出 + 校准 + 分层 |",
  "| 18 | 生物学复发预警与偏倚 |",
  "| 19 | 多编码/多终点敏感性 |",
  "| 20 | 两套口径判别边界 |",
  "",
  "主结论以 **Figure 9–10（口径 B 折外）** 为准；Figure 7–8（口径 A 表观）仅描述。",
  "旧 summary_results OS-ML 不覆盖。"
)
writeLines(guide, file.path(out_root, "NUMBERING_AND_ROLE.md"), useBytes = TRUE)
file.copy(file.path(out_root, "NUMBERING_AND_ROLE.md"),
          file.path(root, "reports/npc_ebv_pet_summary_new_numbering.md"), overwrite = TRUE)

# ensure formats
if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
  source(file.path(root, "R/pub_figure_export.R"))
  tryCatch(pub_figure_ensure_formats(file.path(out_root, "Figures"),
                                     config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))),
           error = function(e) .message("ensure_formats: %s", e$message))
}

nfig <- length(list.files(fig_dir, pattern = "^Figure [0-9]+"))
.message("DONE. Main figures matched: %d files in pdf/. Expect Figure 1-20 (+S1).", nfig)
invisible(TRUE)
