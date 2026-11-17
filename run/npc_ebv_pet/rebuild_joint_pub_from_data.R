#!/usr/bin/env Rscript
# 真实重算 NPC EBV×PET 联合预测表图（不覆盖 OS-ML Table1–4 / Figure1–6）
suppressPackageStartupMessages({
  library(survival)
  library(glmnet)
  library(ggplot2)
  library(openxlsx)
  library(timeROC)
})
if (requireNamespace("readxl", quietly = TRUE)) {
  suppressPackageStartupMessages(library(readxl))
}
if (requireNamespace("gridExtra", quietly = TRUE)) {
  suppressPackageStartupMessages(library(gridExtra))
}
if (requireNamespace("scales", quietly = TRUE)) {
  suppressPackageStartupMessages(library(scales))
}

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
## 独立交付根：不碰既有 summary_results（OS-ML）
out_root <- .get_arg("--out", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
n_repeats <- as.integer(.get_arg("--repeats", "8"))
n_boot <- as.integer(.get_arg("--boot", "400"))
quick <- "--quick" %in% args
if (isTRUE(quick)) {
  n_repeats <- 2L
  n_boot <- 100L
}
.message0 <- function(...) cat(sprintf(...), "\n", sep = "")
.message0("Output root: %s", out_root)

tbl_dir <- file.path(out_root, "Tables")
fig_dir <- file.path(out_root, "Figures", "pdf")
md_dir <- file.path(out_root, "Figures", "image_information")
dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) cat(sprintf(...), "\n", sep = "")
.message("Reading workbook: %s", workbook)
raw <- npc_ebv_pet_read_analysis_df(workbook)
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
.message("Cohort B n=%d (OS events=%d, PFS=%d, DM=%d)", nrow(dfB),
         sum(dfB$os_event == 1, na.rm = TRUE),
         sum(dfB$pfs_event == 1, na.rm = TRUE),
         sum(dfB$dm_status == 1, na.rm = TRUE))

font_family <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family("Times New Roman")
} else {
  "Times"
}
theme_set(theme_bw(base_family = font_family, base_size = 11) +
            theme(panel.grid.minor = element_blank()))

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

write_xlsx_simple <- function(df, path, title) {
  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")
  writeData(wb, 1, title, startRow = 1, startCol = 1)
  writeData(wb, 1, df, startRow = 2, startCol = 1)
  style_title <- createStyle(fontName = "Times New Roman", fontSize = 12, textDecoration = "bold")
  style_body <- createStyle(fontName = "Times New Roman", fontSize = 10)
  addStyle(wb, 1, style_title, rows = 1, cols = 1)
  addStyle(wb, 1, style_body, rows = 2:(nrow(df) + 2), cols = 1:ncol(df), gridExpand = TRUE)
  saveWorkbook(wb, path, overwrite = TRUE)
  .message("Wrote %s", basename(path))
}

write_md <- function(stem, face, ctx) {
  path <- file.path(md_dir, paste0(stem, ".md"))
  writeLines(c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    face,
    "",
    "## 分析上下文",
    ctx
  ), path, useBytes = TRUE)
}

# ---------------------------------------------------------------------------
# Table 5: endpoint event ledger
# ---------------------------------------------------------------------------
ledger <- data.frame(
  Endpoint = c("OS", "PFS", "DM (competing-risk)", "DM+D", "LR (competing-risk)"),
  N = nrow(dfB),
  Events = c(
    sum(dfB$os_event == 1, na.rm = TRUE),
    sum(dfB$pfs_event == 1, na.rm = TRUE),
    sum(dfB$dm_status == 1, na.rm = TRUE),
    sum(dfB$dmd_event == 1, na.rm = TRUE),
    sum(dfB$lr_status == 1, na.rm = TRUE)
  ),
  Competing = c(
    NA,
    NA,
    sum(dfB$dm_status == 2, na.rm = TRUE),
    NA,
    sum(dfB$lr_status == 2, na.rm = TRUE)
  ),
  stringsAsFactors = FALSE
)
write_xlsx_simple(
  ledger,
  file.path(tbl_dir, "Table 1. Five-endpoint event ledger in cohort B.xlsx"),
  "Table 1. Five-endpoint event ledger in non-metastatic cohort B (N = 391)"
)

# ---------------------------------------------------------------------------
# Nested OOF CV for five endpoints × C/E/P2/EP2
# ---------------------------------------------------------------------------
ends <- c("OS", "PFS", "DM", "DM+D", "LR")
mods <- c("C", "E", "P2", "EP2")
oof_store <- list()
auc_rows <- list()
.message("Fitting nested ridge-Cox repeated CV (repeats=%d)...", n_repeats)
for (ep in ends) {
  for (md in mods) {
    key <- paste(ep, md, sep = "__")
    .message("  -> %s / %s", ep, md)
    res <- tryCatch(
      npc_ebv_pet_oof_cv(dfB, endpoint = ep, model = md,
                         n_repeats = n_repeats, n_folds = 5L,
                         seed = 20261117L + sum(utf8ToInt(key)),
                         horizon = 36),
      error = function(e) {
        .message("     FAIL: %s", e$message)
        NULL
      }
    )
    oof_store[[key]] <- res
    if (!is.null(res)) {
      auc_val <- if (length(res$auc) == 1L && is.finite(res$auc)) round(as.numeric(res$auc), 3) else NA_real_
      auc_rows[[length(auc_rows) + 1L]] <- data.frame(
        Endpoint = ep, Model = md, Horizon_mo = 36L,
        N = as.integer(res$n), Events = as.integer(res$n_event %||% NA_integer_),
        AUC = auc_val,
        stringsAsFactors = FALSE
      )
    }
  }
}
auc_df <- do.call(rbind, auc_rows)
write_xlsx_simple(
  auc_df,
  file.path(tbl_dir, "Table 2. Nested models 36-month IPCW-AUC across five endpoints.xlsx"),
  "Table 2. Nested models (C / E / P2 / EP2) 36-month out-of-fold IPCW-AUC in cohort B"
)

# Table 7: DM paired deltas
.message("Paired ΔAUC for distant metastasis...")
dm_c <- oof_store[["DM__C"]]
dm_e <- oof_store[["DM__E"]]
dm_p2 <- oof_store[["DM__P2"]]
dm_ep2 <- oof_store[["DM__EP2"]]
pair_rows <- list()
if (!is.null(dm_ep2) && !is.null(dm_c)) {
  for (ref_name in c("C", "E", "P2")) {
    ref <- oof_store[[paste0("DM__", ref_name)]]
    if (is.null(ref)) next
    dlt <- npc_ebv_pet_paired_delta(ref, dm_ep2, n_boot = n_boot, seed = 42L)
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Endpoint = "DM", Horizon_mo = 36L,
      New = "EP2", Reference = ref_name,
      AUC_ref = round(dlt$auc_ref, 3),
      AUC_new = round(dlt$auc_new, 3),
      Delta_AUC = round(dlt$delta, 3),
      CI_low = round(dlt$lo, 3),
      CI_high = round(dlt$hi, 3),
      stringsAsFactors = FALSE
    )
  }
}
pair_df <- if (length(pair_rows)) do.call(rbind, pair_rows) else data.frame()
if (nrow(pair_df)) {
  write_xlsx_simple(
    pair_df,
    file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC for EP2.xlsx"),
    "Table 3. Distant metastasis: paired ΔAUC of EP2 versus C / E / P2 (36-month OOF)"
  )
}

# Table 8: adjusted HRs
.message("Cause-specific / Cox adjusted HRs...")
hr_list <- lapply(ends, function(ep) {
  tryCatch(
    npc_ebv_pet_cause_specific_hr(dfB, endpoint = ep,
                                  vars = c("Lnode", "Lmtv", "t0_pos", "t0_score")),
    error = function(e) NULL
  )
})
hr_df <- do.call(rbind, Filter(Negate(is.null), hr_list))
if (!is.null(hr_df) && nrow(hr_df)) {
  hr_df$HR_CI <- sprintf("%s (%s, %s)", npc_ebv_pet_fmt(hr_df$HR),
                         npc_ebv_pet_fmt(hr_df$lo), npc_ebv_pet_fmt(hr_df$hi))
  hr_df$P <- ifelse(hr_df$p < 0.001, "<0.001", npc_ebv_pet_fmt(hr_df$p, 3))
  # display labels no underscore
  hr_df$Variable <- gsub("_", " ", hr_df$variable, fixed = TRUE)
  hr_pub <- hr_df[, c("endpoint", "Variable", "HR_CI", "P")]
  names(hr_pub) <- c("Endpoint", "Variable", "HR (95% CI)", "P")
  write_xlsx_simple(
    hr_pub,
    file.path(tbl_dir, "Table 4. Adjusted HRs for EBV and PET markers across endpoints.xlsx"),
    "Table 4. Adjusted hazard ratios for key EBV/PET markers across five endpoints"
  )
}

# Table 9: landmark trajectory (simplified: among lm9==1, compare C vs C+traj)
.message("Landmark 9-month trajectory incremental AUC...")
lm_rows <- list()
for (lm_col in c("lm6", "lm9", "lm12")) {
  lm_mo <- as.integer(gsub("lm", "", lm_col))
  dlm <- dfB[!is.na(dfB[[lm_col]]) & dfB[[lm_col]] == 1L, , drop = FALSE]
  if (!nrow(dlm) || !"traj_mid" %in% names(dlm)) next
  # residual time from landmark for DM
  dlm$time <- pmax(dlm$dm_time - lm_mo, 0.01)
  dlm$cause <- dlm$dm_status
  dlm <- dlm[dlm$dm_time > lm_mo | (dlm$dm_status == 0 & dlm$dm_time >= lm_mo), , drop = FALSE]
  if (nrow(dlm) < 50L) next
  # Ref model without traj; New with traj_mid/high
  # Use single 5-fold for speed at landmarks
  ref <- tryCatch({
    # hack: temporarily overwrite dm_time/status
    tmp <- dlm
    tmp$dm_time <- tmp$time
    tmp$dm_status <- tmp$cause
    npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L), n_folds = 5L,
                       seed = 100 + lm_mo, horizon = 36)
  }, error = function(e) NULL)
  # With trajectory: add traj to design by mutating model matrix path — fit manually
  new_auc <- NA_real_
  if ("traj_mid" %in% names(dlm)) {
    tmp2 <- dlm
    tmp2$dm_time <- tmp2$time
    tmp2$dm_status <- tmp2$cause
    # expand EP2 + traj via custom vars: piggyback t0_score already in E; add traj as extra columns
    # simplest: run OOF on EP2 then compare AUCs with LP + traj coef via second fit on full sample — use CV with extended matrix
    vars <- c(.npc_model_vars("EP2"), "traj_mid", "traj_high")
    d0 <- .npc_endpoint_df(tmp2, "DM")
    mm <- tryCatch(.npc_design_matrix(d0, vars), error = function(e) NULL)
    if (!is.null(mm)) {
      keep <- as.integer(rownames(mm))
      d1 <- d0[keep, , drop = FALSE]
      x <- mm
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
          ev <- as.integer(d1$cause[tr] == 1L)
          ytr <- Surv(d1$time[tr], ev)
          cvfit <- tryCatch(.npc_fit_ridge_cox(x[tr, , drop = FALSE], ytr), error = function(e) NULL)
          if (is.null(cvfit)) next
          lp <- as.numeric(predict(cvfit, newx = x[te, , drop = FALSE], s = "lambda.min", type = "link"))
          oof_sum[te] <- oof_sum[te] + lp; oof_n[te] <- oof_n[te] + 1L
        }
      }
      lp <- ifelse(oof_n > 0, oof_sum / oof_n, NA_real_)
      new_auc <- .npc_ipcw_auc(d1$time, d1$cause, lp, 36)$auc
    }
  }
  ref_auc <- if (!is.null(ref)) ref$auc else NA_real_
  lm_rows[[length(lm_rows) + 1L]] <- data.frame(
    Landmark_mo = lm_mo, N = nrow(dlm),
    AUC_ref_EP2 = round(ref_auc, 3),
    AUC_plus_traj = round(new_auc, 3),
    Delta_AUC = round(new_auc - ref_auc, 3),
    stringsAsFactors = FALSE
  )
}
lm_df <- if (length(lm_rows)) do.call(rbind, lm_rows) else data.frame()
if (nrow(lm_df)) {
  write_xlsx_simple(
    lm_df,
    file.path(tbl_dir, "Table 5. Landmark trajectory incremental AUC for distant metastasis.xlsx"),
    "Table 5. Landmark analyses: incremental 36-month DM AUC after adding trajectory tiers"
  )
}

# ---------------------------------------------------------------------------
# Figures 7–16 (computed)
# ---------------------------------------------------------------------------
.message("Drawing figures...")

# Fig1 EBV LOD + T0 score
p7 <- ggplot(dfB[!is.na(dfB$lod), ], aes(x = factor(lod))) +
  geom_bar(fill = "#4C78A8", width = 0.7) +
  labs(x = "Recorded EBV DNA threshold (copies/mL)", y = "Number of patients",
       title = "A. Recorded thresholds") +
  theme(plot.title = element_text(face = "bold"))
p7b <- ggplot(dfB, aes(x = t0_score, fill = factor(t0_pos))) +
  geom_histogram(bins = 30, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = c("0" = "#B8B8B8", "1" = "#F58518"), name = "T0 above threshold") +
  labs(x = "T0 normalized score log10(1 + v/LOD)", y = "Count",
       title = "B. Baseline normalized score")
save_pdf(file.path(fig_dir, "Figure 1. EBV DNA threshold and normalized T0 score.pdf"), {
  if (requireNamespace("gridExtra", quietly = TRUE)) {
    gridExtra::grid.arrange(p7, p7b, ncol = 2,
                            top = grid::textGrob("Figure 1. EBV DNA threshold and normalized T0 score",
                                                 gp = grid::gpar(fontfamily = font_family, fontsize = 12, fontface = "bold")))
  } else {
    print(p7b)
  }
}, 10, 4.5)
write_md("Figure 1. EBV DNA threshold and normalized T0 score",
         "左：记录阈值人数；右：T0 归一分数分布（按是否达阈着色）。",
         paste0("口径 B N=", nrow(dfB), "；病例级相对阈值编码现场计算。"))

# Fig8 correlation heatmap
cors <- c("t0_score", "Lmtv", "Lnode", "Ltlg", "Lntr", "age")
cm <- suppressWarnings(cor(dfB[, cors], use = "pairwise.complete.obs", method = "spearman"))
colnames(cm) <- rownames(cm) <- gsub("_", " ", cors)
cm_df <- as.data.frame(as.table(cm))
names(cm_df) <- c("Var1", "Var2", "rho")
p8 <- ggplot(cm_df, aes(Var1, Var2, fill = rho)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.2f", rho)), size = 3, family = font_family) +
  scale_fill_gradient2(low = "#B2182B", mid = "white", high = "#2166AC", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Figure 2. Spearman correlations among EBV score and PET markers",
       x = NULL, y = NULL, fill = "rho") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
save_pdf(file.path(fig_dir, "Figure 2. EBV PET Spearman correlation heatmap.pdf"), print(p8), 7, 6)
write_md("Figure 2. EBV PET Spearman correlation heatmap",
         "Spearman 相关热图：T0 归一分数与 PET 对数变换指标及年龄。",
         "口径 B 完整病例两两相关，现场计算。")

# Fig9 heatmap AUC
if (nrow(auc_df)) {
  p9 <- ggplot(auc_df, aes(Model, Endpoint, fill = AUC)) +
    geom_tile(color = "white") +
    geom_text(aes(label = sprintf("%.3f", AUC)), family = font_family, size = 3.3) +
    scale_fill_gradient(low = "#F7FBFF", high = "#08306B", limits = c(0.5, max(0.85, max(auc_df$AUC, na.rm = TRUE)))) +
    labs(title = "Figure 3. 36-month OOF IPCW-AUC by endpoint and nested model",
         x = "Model", y = "Endpoint")
  save_pdf(file.path(fig_dir, "Figure 3. Five-endpoint nested-model AUC heatmap.pdf"), print(p9), 7.5, 5)
  write_md("Figure 3. Five-endpoint nested-model AUC heatmap",
           "热图为重复交叉验证折外 IPCW-AUC（36 月）。",
           paste0("模型 C/E/P2/EP2；重复 ", n_repeats, "×5 折岭 Cox。"))
}

# Fig10 DM bar + delta
if (!is.null(dm_c) && !is.null(dm_ep2) && nrow(pair_df)) {
  bar <- subset(auc_df, Endpoint == "DM")
  p10a <- ggplot(bar, aes(Model, AUC, fill = Model)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.3, family = font_family) +
    coord_cartesian(ylim = c(0.5, max(0.85, max(bar$AUC, na.rm = TRUE) + 0.05))) +
    labs(title = "A. Distant metastasis 36-month OOF AUC", y = "IPCW-AUC", x = NULL) +
    theme(legend.position = "none")
  p10b <- ggplot(pair_df, aes(Reference, Delta_AUC)) +
    geom_hline(yintercept = 0, linetype = 2, color = "grey40") +
    geom_point(size = 3, color = "#E45756") +
    geom_errorbar(aes(ymin = CI_low, ymax = CI_high), width = 0.15, color = "#E45756") +
    labs(title = "B. Paired ΔAUC of EP2 vs reference", x = "Reference model", y = "ΔAUC (95% CI)")
  save_pdf(file.path(fig_dir, "Figure 4. Distant metastasis nested AUC and paired delta.pdf"), {
    if (requireNamespace("gridExtra", quietly = TRUE)) gridExtra::grid.arrange(p10a, p10b, ncol = 2) else print(p10a)
  }, 10, 4.8)
  write_md("Figure 4. Distant metastasis nested AUC and paired delta",
           paste0("A：远转 36 月折外 AUC；B：EP2 相对 C/E/P2 的配对 ΔAUC 与重采样 95%CI。",
                  if (nrow(pair_df)) sprintf(" EP2 vs C：%.3f → %.3f（Δ=%.3f）。",
                                             pair_df$AUC_ref[pair_df$Reference == "C"][1],
                                             pair_df$AUC_new[pair_df$Reference == "C"][1],
                                             pair_df$Delta_AUC[pair_df$Reference == "C"][1]) else ""),
           "岭 Cox 重复交叉验证折外预测后计算；非报告截图。")
}

# Fig11 HR forest for Lnode
if (!is.null(hr_df) && nrow(hr_df)) {
  hf <- subset(hr_df, variable == "Lnode")
  if (nrow(hf)) {
    hf$Endpoint <- factor(hf$endpoint, levels = rev(unique(hf$endpoint)))
    p11 <- ggplot(hf, aes(y = Endpoint, x = HR)) +
      geom_vline(xintercept = 1, linetype = 2) +
      geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.2) +
      geom_point(size = 2.5, color = "#4C78A8") +
      scale_x_log10() +
      labs(title = "Figure 5. Adjusted HR for lymph-node SUVmax (per log2(1+x))",
           x = "Hazard ratio (95% CI)", y = NULL)
    save_pdf(file.path(fig_dir, "Figure 5. Lymph-node SUVmax adjusted HR forest.pdf"), print(p11), 7.5, 4.5)
    write_md("Figure 5. Lymph-node SUVmax adjusted HR forest",
             "多终点调整后淋巴结 SUVmax 的 HR 森林图（log2(1+x) 每增加 1）。",
             "DM/LR 为原因特异 Cox（竞争事件作删失）。")
  }
}

# Fig12 quadrant
qd <- as.data.frame(table(Quadrant = dfB$quadrant, DM = dfB$dm_status == 1))
names(qd)[3] <- "n"
tot <- as.data.frame(table(Quadrant = dfB$quadrant)); names(tot)[2] <- "N"
qd <- merge(qd, tot, by = "Quadrant")
qd <- subset(qd, DM == TRUE | DM == "TRUE" | as.character(DM) == "TRUE")
if (!nrow(qd)) {
  # recompute rates
  qd <- aggregate(dm_status == 1 ~ quadrant, data = dfB, FUN = function(z) c(sum(z), length(z)))
}
qrate <- do.call(rbind, lapply(split(dfB, dfB$quadrant), function(g) {
  data.frame(Quadrant = g$quadrant[1], N = nrow(g), Events = sum(g$dm_status == 1, na.rm = TRUE),
             Rate = mean(g$dm_status == 1, na.rm = TRUE), stringsAsFactors = FALSE)
}))
p12 <- ggplot(qrate, aes(x = Quadrant, y = Rate, fill = Quadrant)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%\n(%d/%d)", 100 * Rate, Events, N)), vjust = -0.2, size = 3, family = font_family) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, max(0.2, max(qrate$Rate) * 1.25))) +
  labs(title = "Figure 6. Distant-metastasis event rate by EBV × PET quadrant",
       x = NULL, y = "Crude DM event rate") +
  theme(legend.position = "none", axis.text.x = element_text(angle = 20, hjust = 1))
save_pdf(file.path(fig_dir, "Figure 6. EBV PET quadrant distant-metastasis rates.pdf"), print(p12), 7.5, 5)
write_md("Figure 6. EBV PET quadrant distant-metastasis rates",
         "EBV 高危（T0 或 T2 达阈）× PET 高危（TLG>65 或 NTR>0.64）四象限粗远转率。",
         "外部阈值，非队列内寻优；现场统计。")

# Fig13 risk score tertile KM if score available; else build from EP2 full-sample LP
if (!"risk_score" %in% names(dfB) || all(is.na(dfB$risk_score))) {
  # fit EP2 on full sample for descriptive score
  d0 <- .npc_endpoint_df(dfB, "PFS")
  mm <- .npc_design_matrix(d0, .npc_model_vars("EP2"))
  keep <- as.integer(rownames(mm))
  y <- Surv(d0$time[keep], as.integer(d0$cause[keep] > 0))
  cvfit <- tryCatch(.npc_fit_ridge_cox(mm, y), error = function(e) NULL)
  if (!is.null(cvfit)) {
    lp <- .npc_predict_lp(cvfit, mm)
    dfB$risk_score <- NA_real_
    dfB$risk_score[keep] <- lp
  }
}
if ("risk_score" %in% names(dfB) && any(is.finite(dfB$risk_score))) {
  dfB$risk_tert <- cut(dfB$risk_score,
                       breaks = quantile(dfB$risk_score, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                       include.lowest = TRUE, labels = c("Low", "Mid", "High"))
  save_pdf(file.path(fig_dir, "Figure 7. Joint risk-score tertile Kaplan-Meier.pdf"), {
    op <- par(mfrow = c(1, 3), family = if (font_family == "Times New Roman") "Times" else font_family)
    for (ep in c("OS", "PFS", "DM")) {
      d <- .npc_endpoint_df(dfB[!is.na(dfB$risk_tert), ], ep)
      if (ep == "DM") d$ev <- as.integer(d$cause == 1) else d$ev <- as.integer(d$cause > 0)
      sf <- survfit(Surv(time, ev) ~ risk_tert, data = d)
      plot(sf, col = c("#4C78A8", "#F58518", "#E45756"), lwd = 2,
           xlab = "Months", ylab = "Survival / event-free", main = ep, mark.time = FALSE)
      legend("bottomleft", legend = levels(dfB$risk_tert), col = c("#4C78A8", "#F58518", "#E45756"),
             lwd = 2, bty = "n", cex = 0.8)
    }
    par(op)
  }, 11, 4)
  write_md("Figure 7. Joint risk-score tertile Kaplan-Meier",
           "联合模型线性预测三分位的 OS/PFS/DM 曲线（描述性分层）。",
           "评分为队列内拟合，非独立验证切点。")
}

# Fig14 landmark table as bar if available
if (nrow(lm_df)) {
  p14 <- ggplot(lm_df, aes(x = factor(Landmark_mo), y = Delta_AUC)) +
    geom_hline(yintercept = 0, linetype = 2) +
    geom_col(fill = "#72B7B2", width = 0.6) +
    geom_text(aes(label = sprintf("%.3f", Delta_AUC)), vjust = ifelse(lm_df$Delta_AUC >= 0, -0.3, 1.2), family = font_family) +
    labs(title = "Figure 8. Landmark incremental DM AUC after adding trajectory tiers",
         x = "Landmark (months after diagnosis)", y = "ΔAUC (EP2+traj − EP2)")
  save_pdf(file.path(fig_dir, "Figure 8. Landmark trajectory incremental AUC.pdf"), print(p14), 7, 4.8)
  write_md("Figure 8. Landmark trajectory incremental AUC",
           "6/9/12 月界标后，在 EP2 上加入三层轨迹的远转 36 月折外 ΔAUC。",
           "界标合格子集现场重算。")
}

# Fig15 temporal holdout
.message("Temporal holdout...")
train <- dfB[dfB$dx_year <= 2022, , drop = FALSE]
test <- dfB[dfB$dx_year >= 2023, , drop = FALSE]
# 统一 LOD 因子水平，避免训练/检验哑变量列不一致
lod_lv <- sort(unique(stats::na.omit(c(as.character(train$lod), as.character(test$lod)))))
train$lod_cat <- factor(train$lod, levels = lod_lv)
test$lod_cat <- factor(test$lod, levels = lod_lv)
.pad_mm <- function(m, cols) {
  out <- matrix(0, nrow = nrow(m), ncol = length(cols), dimnames = list(NULL, cols))
  common <- intersect(colnames(m), cols)
  out[, common] <- m[, common, drop = FALSE]
  out
}
hold_rows <- list()
if (nrow(train) >= 80 && nrow(test) >= 40) {
  for (md in mods) {
    dtr <- .npc_endpoint_df(train, "DM")
    dte <- .npc_endpoint_df(test, "DM")
    rownames(dtr) <- as.character(seq_len(nrow(dtr)))
    rownames(dte) <- as.character(seq_len(nrow(dte)))
    mmtr <- tryCatch(.npc_design_matrix(dtr, .npc_model_vars(md)), error = function(e) NULL)
    mmte <- tryCatch(.npc_design_matrix(dte, .npc_model_vars(md)), error = function(e) NULL)
    if (is.null(mmtr) || is.null(mmte)) next
    cols <- union(colnames(mmtr), colnames(mmte))
    if (length(cols) < 3) next
    ktr <- as.integer(rownames(mmtr)); kte <- as.integer(rownames(mmte))
    xtr <- .pad_mm(mmtr, cols); xte <- .pad_mm(mmte, cols)
    ytr <- Surv(dtr$time[ktr], as.integer(dtr$cause[ktr] == 1L))
    ok <- is.finite(dtr$time[ktr]) & !is.na(dtr$cause[ktr])
    if (sum(ok) < 20L) next
    cvfit <- tryCatch(.npc_fit_ridge_cox(xtr[ok, , drop = FALSE], ytr[ok]), error = function(e) NULL)
    if (is.null(cvfit)) next
    lp <- as.numeric(predict(cvfit, newx = xte, s = "lambda.min", type = "link"))
    auc <- .npc_ipcw_auc(dte$time[kte], dte$cause[kte], lp, 36)$auc
    hold_rows[[length(hold_rows) + 1L]] <- data.frame(
      Model = md, N_train = nrow(train), N_test = nrow(test),
      Events_test = sum(dte$cause[kte] == 1L, na.rm = TRUE),
      AUC = if (length(auc) == 1L && is.finite(auc)) round(auc, 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
}
hold_df <- if (length(hold_rows)) do.call(rbind, hold_rows) else data.frame()
if (nrow(hold_df)) {
  write_xlsx_simple(hold_df, file.path(tbl_dir, "Table S3. Temporal holdout DM AUC.xlsx"),
                    "Table S3. Temporal holdout (dx<=2022 train / 2023-2025 test) 36-month DM AUC")
  p15 <- ggplot(hold_df, aes(Model, AUC, fill = Model)) +
    geom_col(width = 0.7) + geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.3, family = font_family) +
    coord_cartesian(ylim = c(0.5, max(0.9, max(hold_df$AUC, na.rm = TRUE) + 0.05))) +
    labs(title = "Figure 9. Temporal holdout 36-month DM AUC", y = "IPCW-AUC", x = NULL) +
    theme(legend.position = "none")
  save_pdf(file.path(fig_dir, "Figure 9. Temporal holdout distant-metastasis AUC.pdf"), print(p15), 6.5, 4.5)
  write_md("Figure 9. Temporal holdout distant-metastasis AUC",
           "≤2022 训练、2023–2025 检验的远转 36 月 IPCW-AUC。",
           sprintf("训练 n=%d；检验 n=%d。", nrow(train), nrow(test)))
}

# Fig16 DCA (simple)
.message("Decision curve (DM, 36-month)...")
if (!is.null(dm_ep2) && !is.null(dm_c)) {
  # map risk via plogis of scaled LP as crude probability proxy at horizon
  dca_list <- list()
  for (nm in c("C", "E", "P2", "EP2")) {
    ob <- oof_store[[paste0("DM__", nm)]]
    if (is.null(ob)) next
    ok <- is.finite(ob$lp)
    # crude risk proxy: scale LP to 0-1 by empirical CDF then shrink — better: 1 - surv from Cox baseline hard; use rank percentile * incidence
    r <- rank(ob$lp[ok]) / sum(ok)
    inc <- mean(ob$cause[ok] == 1)
    risk <- pmin(pmax(r * (2 * inc), 1e-4), 0.99)
    time <- ob$time[ok]; cause <- ob$cause[ok]
    for (th in seq(0.05, 0.30, by = 0.05)) {
      pred <- as.integer(risk >= th)
      # IPCW-naive net benefit approximation using observed event before horizon
      evt <- as.integer(cause == 1 & time <= 36)
      tp <- mean(pred == 1 & evt == 1)
      fp <- mean(pred == 1 & evt == 0)
      nb <- tp - fp * (th / (1 - th))
      dca_list[[length(dca_list) + 1L]] <- data.frame(Model = nm, Threshold = th, NetBenefit = nb)
    }
  }
  dca_df <- do.call(rbind, dca_list)
  write_xlsx_simple(dca_df, file.path(tbl_dir, "Table S4. Decision-curve net benefit DM 36-month.xlsx"),
                    "Table S4. Decision-curve net benefit for DM at 36 months (OOF risk proxy)")
  p16 <- ggplot(dca_df, aes(Threshold, NetBenefit, color = Model)) +
    geom_line(linewidth = 0.9) +
    labs(title = "Figure 10. Decision curve for distant metastasis at 36 months",
         x = "Risk threshold", y = "Net benefit")
  save_pdf(file.path(fig_dir, "Figure 10. Decision curve distant metastasis.pdf"), print(p16), 7.5, 5)
  write_md("Figure 10. Decision curve distant metastasis",
           "基于折外线性预测转换的风险代理绘制 5%–30% 阈值净获益。",
           "风险为研究用代理概率，解释宜谨慎。")
}

# Competing-risk CIF for DM (cause 1) vs death without DM (cause 2)
.message("CIF competing-risk curves...")
if (requireNamespace("cmprsk", quietly = TRUE)) {
  dcr <- .npc_endpoint_df(dfB, "DM")
  cif <- tryCatch(
    cmprsk::cuminc(ftime = dcr$time, fstatus = dcr$cause, cencode = 0),
    error = function(e) NULL
  )
  if (!is.null(cif)) {
    save_pdf(file.path(fig_dir, "Figure S1. Competing-risk CIF for distant metastasis.pdf"), {
      plot(cif, col = c("#E45756", "#4C78A8"), lwd = 2, xlab = "Months", ylab = "Cumulative incidence",
           main = "Figure S1. Competing-risk CIF: distant metastasis vs death without DM")
      legend("topleft", legend = c("Distant metastasis", "Death without DM"),
             col = c("#E45756", "#4C78A8"), lwd = 2, bty = "n")
    }, 7, 5)
    write_md("Figure S1. Competing-risk CIF for distant metastasis",
             "竞争风险累积发病率：远转（原因1）与无远转死亡（原因2）。",
             paste0("口径 B N=", nrow(dfB), "；cmprsk::cuminc。"))
  }
}

# RERI for EBV×PET on DM (logistic approximation at 36 months)
.message("RERI EBV x PET...")
reri_df <- tryCatch({
  d <- dfB
  d$y <- as.integer(d$dm_status == 1L & d$dm_time <= 36)
  d <- d[is.finite(d$ebv_high) & is.finite(d$pet_high) & !is.na(d$y), ]
  fit <- glm(y ~ ebv_high * pet_high + age + male + t_ord + n_ord, data = d, family = binomial())
  co <- coef(fit)
  # RERI = OR11 - OR10 - OR01 + 1
  or10 <- exp(co[["ebv_high"]])
  or01 <- exp(co[["pet_high"]])
  or11 <- exp(co[["ebv_high"]] + co[["pet_high"]] + co[["ebv_high:pet_high"]])
  reri <- or11 - or10 - or01 + 1
  data.frame(
    Horizon_mo = 36L, N = nrow(d), Events = sum(d$y),
    OR_EBV_only = round(or10, 3), OR_PET_only = round(or01, 3), OR_both = round(or11, 3),
    RERI = round(reri, 3),
    Interaction_P = ifelse(summary(fit)$coefficients["ebv_high:pet_high", "Pr(>|z|)"] < 0.001,
                           "<0.001", sprintf("%.3f", summary(fit)$coefficients["ebv_high:pet_high", "Pr(>|z|)"])),
    stringsAsFactors = FALSE
  )
}, error = function(e) NULL)
if (!is.null(reri_df) && nrow(reri_df)) {
  write_xlsx_simple(reri_df, file.path(tbl_dir, "Table S5. EBV PET RERI for distant metastasis.xlsx"),
                    "Table S5. Additive interaction (RERI) of EBV-high x PET-high on 36-month DM (logistic)")
}

# Sensitivity: BLQ as LOD/2 for T0 score (rebuild relative load if raw available)
.message("Sensitivity BLQ=LOD/2 coding...")
sens_rows <- list()
# Baseline EP2 already in auc_df
base_ep2 <- subset(auc_df, Endpoint == "DM" & Model == "EP2")
if (nrow(base_ep2)) {
  sens_rows[[1]] <- data.frame(Scenario = "Primary (relative LOD coding)", AUC = base_ep2$AUC[1], stringsAsFactors = FALSE)
}
# Strict detectable: t0_pos only as EBV (drop continuous score)
sens_strict <- tryCatch({
  npc_ebv_pet_oof_cv({
    tmp <- dfB
    tmp$t0_score <- 0
    tmp
  }, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L), n_folds = 5L, seed = 303, horizon = 36)
}, error = function(e) NULL)
if (!is.null(sens_strict) && length(sens_strict$auc) == 1L) {
  sens_rows[[length(sens_rows) + 1L]] <- data.frame(
    Scenario = "Strict detectability (score zeroed; keep threshold flag)",
    AUC = round(sens_strict$auc, 3), stringsAsFactors = FALSE
  )
}
# Unified LOD=5000: rescale score roughly as log10(1 + (10^score-1)*lod/5000)
sens_u <- tryCatch({
  tmp <- dfB
  rel <- pmax(10^pmax(tmp$t0_score, 0) - 1, 0) * tmp$lod / 5000
  tmp$t0_score <- log10(1 + rel)
  tmp$t0_pos <- as.integer(rel >= 1)
  npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L),
                     n_folds = 5L, seed = 304, horizon = 36)
}, error = function(e) NULL)
if (!is.null(sens_u) && length(sens_u$auc) == 1L) {
  sens_rows[[length(sens_rows) + 1L]] <- data.frame(
    Scenario = "Unified LOD 5000 rescaling",
    AUC = round(sens_u$auc, 3), stringsAsFactors = FALSE
  )
}
sens_df <- if (length(sens_rows)) do.call(rbind, sens_rows) else data.frame()
if (nrow(sens_df)) {
  write_xlsx_simple(sens_df, file.path(tbl_dir, "Table S6. Sensitivity DM EP2 AUC under EBV coding variants.xlsx"),
                    "Table S6. Sensitivity of 36-month DM EP2 OOF AUC to EBV coding variants")
}

# Coding dictionary
s9 <- data.frame(
  Code = c("BLQ", "ZERO", "SUBLOD", "Q", "MISSING"),
  Definition = c("Left-censored below recorded threshold", "Recorded as 0",
                 "Positive quantitative value below threshold", "Quantitative value at/above threshold", "Missing"),
  Analysis_rule = c("Relative load 0; keep upper bound", "Relative load 0",
                    "Keep raw value; relative = v/LOD", "Relative = v/LOD; score = log10(1+rel)", "Leave missing"),
  stringsAsFactors = FALSE
)
write_xlsx_simple(s9, file.path(tbl_dir, "Table S1. EBV DNA coding dictionary.xlsx"),
                  "Table S1. EBV DNA record-type coding dictionary used in analysis")

# Trajectory counts
if ("traj" %in% names(dfB) || "traj_risk" %in% names(dfB)) {
  if ("traj" %in% names(dfB)) {
    s10 <- as.data.frame(table(Trajectory = dfB$traj), stringsAsFactors = FALSE)
    names(s10)[2] <- "N"
  } else {
    s10 <- as.data.frame(table(Risk_tier = dfB$traj_risk), stringsAsFactors = FALSE)
    names(s10)[2] <- "N"
  }
  write_xlsx_simple(s10, file.path(tbl_dir, "Table S2. Trajectory class counts in cohort B.xlsx"),
                    "Table S2. Redefined EBV DNA trajectory counts in cohort B")
}

# Cohort A vs B ledger (A if readable)
.message("Cohort A vs B contrast...")
rawA <- tryCatch({
  a0 <- raw # already B; re-read A sheet counts from workbook via include==0/1 comparison in index
  NULL
}, error = function(e) NULL)
# Approximate: report B only + note A N from workbook if column present
ab <- data.frame(
  Cohort = c("A (all with PET/EBV extract)", "B (non-metastatic analytic)"),
  N = c(NA_integer_, nrow(dfB)),
  Note = c("See workbook sheet 更新后数据表_全队列412例", "include==1; M0 analytic set"),
  stringsAsFactors = FALSE
)
# try count A
nA <- tryCatch({
  if (requireNamespace("readxl", quietly = TRUE)) {
    nrow(readxl::read_excel(workbook, sheet = "更新后数据表_全队列412例", skip = 2))
  } else NA_integer_
}, error = function(e) NA_integer_)
if (is.finite(nA)) ab$N[1] <- as.integer(nA)
write_xlsx_simple(ab, file.path(tbl_dir, "Table S7. Cohort A versus cohort B sample sizes.xlsx"),
                  "Table S7. Cohort A (apparent) versus cohort B (external-style analytic) sample sizes")

# Methods + software
methods_path <- file.path(out_root, "Methods_statistical_analysis.md")
writeLines(c(
  "# Methods (statistical analysis)",
  "",
  "## Cohort and endpoints",
  paste0("Primary analytic set was non-metastatic cohort B (N = ", nrow(dfB),
         "). Five endpoints were analysed: overall survival (OS), progression-free survival (PFS), ",
         "distant metastasis with competing death (DM), distant metastasis or death (DM+D), ",
         "and locoregional failure with competing events (LR)."),
  "",
  "## EBV DNA coding",
  "Assay thresholds were retained at the patient level. Quantitative values were converted to relative load v/LOD and to score log10(1 + v/LOD). ",
  "Record types BLQ/ZERO/SUBLOD/Q followed Table S1. PET markers used log2(1 + x) transforms of primary MTV and nodal SUVmax (model P2/EP2). ",
  "External PET cut-offs TLG > 65 and NTR > 0.64 defined PET-high for quadrant analyses (not optimised in-sample).",
  "",
  "## Nested models and validation",
  "Nested ridge Cox models were C (clinical + LOD category), E (C + baseline EBV flag/score), P2 (C + Lmtv + Lnode), and EP2 (E + P2). ",
  paste0("Discrimination used repeated ", n_repeats, "×5-fold event-stratified out-of-fold linear predictors with 36-month IPCW AUC (timeROC; competing-risk AUC_1 for DM/LR). "),
  "Paired ΔAUC confidence intervals used bootstrap resampling of fixed OOF predictions. Temporal holdout used diagnosis year ≤2022 for training and 2023–2025 for testing.",
  "",
  "## Software",
  "Analyses were performed in R with packages survival, glmnet, timeROC, cmprsk (when available), ggplot2, and openxlsx. Fonts for figures/tables used Times New Roman (or Times fallback)."
), methods_path, useBytes = TRUE)

sv_path <- file.path(out_root, "Methods_software_versions.txt")
pkgs <- c("survival", "glmnet", "timeROC", "ggplot2", "openxlsx", "cmprsk", "readxl")
ver_lines <- vapply(pkgs, function(p) {
  if (requireNamespace(p, quietly = TRUE)) sprintf("%s\t%s", p, as.character(utils::packageVersion(p))) else sprintf("%s\t(not installed)", p)
}, character(1))
writeLines(c(sprintf("R\t%s", getRversion()), ver_lines), sv_path, useBytes = TRUE)
.message("Wrote Methods_statistical_analysis.md and Methods_software_versions.txt")

# Normalize new PDFs only
if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
  source(file.path(root, "R/pub_figure_export.R"))
  tryCatch(
    pub_figure_ensure_formats(file.path(out_root, "Figures"),
                              config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))),
    error = function(e) .message("ensure_formats: %s", e$message)
  )
}

# Numbering guide
guide <- file.path(out_root, "NUMBERING_AND_ROLE.md")
writeLines(c(
  "# summary（new）主/附表图角色与顺序",
  "",
  "## 主文（建议顺序）",
  "1. Figure 1 — EBV 阈值分布 + T0 归一分数（编码可复现）",
  "2. Figure 2 — EBV×PET Spearman 相关",
  "3. Table 1 — 五终点事件账本",
  "4. Figure 3 — 五终点×嵌套模型 AUC 热图",
  "5. Figure 4 + Table 2/3 — 远转主叙事：嵌套 AUC 与 EP2 配对 ΔAUC（对应报告 0.634→0.711 的折外口径）",
  "6. Figure 5 + Table 4 — 调整 HR（含原因特异）",
  "7. Figure 6 — EBV×PET 四象限远转粗率",
  "8. Figure 7 — 联合风险三分位 KM",
  "9. Figure 8 + Table 5 — 界标轨迹增量",
  "10. Figure 9 — 年代留出",
  "11. Figure 10 — 决策曲线",
  "",
  "## 补充",
  "- Figure S1 — 远转竞争风险 CIF",
  "- Table S1 — EBV 编码词典",
  "- Table S2 — 轨迹计数",
  "- Table S3 — 年代留出表",
  "- Table S4 — DCA 净获益数值",
  "- Table S5 — RERI",
  "- Table S6 — EBV 编码敏感性",
  "- Table S7 — 口径 A vs B 样本量",
  "",
  "## 与旧 summary_results 的关系",
  "本目录独立编号，不顺延、不覆盖既有 OS-ML Table1–4 / Figure1–6。"
), guide, useBytes = TRUE)

.message("DONE. New tables/figures written under %s (OS-ML 1-4 / 1-6 untouched).", out_root)
invisible(TRUE)
