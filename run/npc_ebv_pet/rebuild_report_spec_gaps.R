#!/usr/bin/env Rscript
# 报告规格剩余缺口：方法齐全、本数据独立重算（不追求与方案数字逐位一致）
# - 24/36 月 IPCW-AUC/Brier 并列
# - Bootstrap 乐观校正 Harrell C（120–300）
# - 主模型配对重抽样 800 次；固定 λ（全样本 CV 锁定后套用）
# - 口径 A M0（IC+免疫）+ 连续变量 per-1SD HR
# - 6 参数简约联合模型 + 嵌套 LR
# - IC 亚组 T1×MTV + T1×淋巴结 SUVmax 双交互
# - 9 月界标三层轨迹 ΔAUC
# - 生物学复发 Sens/Spec/PPV/NPV / 提前中位天数 / 12 月界标 HR
# - 四象限分层 HR + 相加交互 RERI；MTV×SUVmax 中位交叉
# - 校准四分位；基线特征表；阈值×年代；HBsAg+BH；EP2X OOF
suppressPackageStartupMessages({
  library(survival); library(glmnet); library(ggplot2); library(openxlsx)
  library(timeROC); library(grid)
})
if (requireNamespace("cmprsk", quietly = TRUE)) library(cmprsk)

args <- commandArgs(trailingOnly = TRUE)
.get_arg <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i) || i >= length(args)) default else args[[i + 1L]]
}
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/npc_ebv_pet_joint_analysis.R"))
if (file.exists(file.path(root, "R/utils.R"))) {
  tryCatch(source(file.path(root, "R/utils.R"), local = FALSE), error = function(e) NULL)
}

workbook <- .get_arg("--workbook", "/mnt/g/02block_result/53_NPC/ml_40395549/DATA/鼻咽癌EBV_PETCT数据表(1).xlsx")
out_root <- .get_arg("--out", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
n_repeats <- as.integer(.get_arg("--repeats", "6"))
n_boot_c <- as.integer(.get_arg("--boot-c", "200"))
n_boot_pair <- as.integer(.get_arg("--boot-pair", "800"))
if ("--quick" %in% args) {
  n_repeats <- 2L; n_boot_c <- 80L; n_boot_pair <- 120L
}

.message <- function(...) cat(sprintf(...), "\n", sep = "")
tbl_dir <- file.path(out_root, "Tables")
fig_dir <- file.path(out_root, "Figures", "pdf")
md_dir <- file.path(out_root, "Figures", "image_information")
dir.create(tbl_dir, FALSE, TRUE); dir.create(fig_dir, FALSE, TRUE); dir.create(md_dir, FALSE, TRUE)

font_family <- if (exists("resolve_plot_font_family", mode = "function")) {
  resolve_plot_font_family("Times New Roman")
} else "Times"
theme_set(theme_bw(base_family = font_family, base_size = 11) + theme(panel.grid.minor = element_blank()))

save_pdf <- function(path, expr, w = 7, h = 5) {
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(path, width = w, height = h, family = "Times New Roman")
  } else if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(path, width = w, height = h, family = "Times New Roman")
  } else grDevices::pdf(path, width = w, height = h, family = "Times")
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
}
write_md <- function(stem, face, ctx) {
  writeLines(c(paste0("# ", stem), "", "## 图面说明", face, "", "## 分析上下文", ctx),
             file.path(md_dir, paste0(stem, ".md")), useBytes = TRUE)
}
write_xlsx_simple <- function(df, path, title) {
  wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
  writeData(wb, 1, title, 1, 1); writeData(wb, 1, df, 2, 1)
  addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 12, textDecoration = "bold"), 1, 1)
  if (nrow(df) && ncol(df)) {
    addStyle(wb, 1, createStyle(fontName = "Times New Roman", fontSize = 10),
             rows = 2:(nrow(df) + 2), cols = 1:ncol(df), gridExpand = TRUE)
  }
  saveWorkbook(wb, path, overwrite = TRUE)
  .message("Wrote %s", basename(path))
}
fmt_p <- function(p) {
  if (!is.finite(p)) return("NE")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}
fmt_hr <- function(est, lo, hi) {
  if (!all(is.finite(c(est, lo, hi)))) return("NE")
  sprintf("%.3f (%.3f, %.3f)", est, lo, hi)
}
zscore <- function(x) {
  x <- as.numeric(x); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}
cox_hr_row <- function(fit, term) {
  sm <- summary(fit)
  rn <- rownames(sm$coefficients)
  i <- match(term, rn)
  if (is.na(i)) return(NULL)
  data.frame(
    Term = term,
    HR = exp(sm$coefficients[i, "coef"]),
    lo = exp(sm$coefficients[i, "coef"] - 1.96 * sm$coefficients[i, "se(coef)"]),
    hi = exp(sm$coefficients[i, "coef"] + 1.96 * sm$coefficients[i, "se(coef)"]),
    p = sm$coefficients[i, "Pr(>|z|)"],
    stringsAsFactors = FALSE
  )
}

.message("Reading data...")
raw <- npc_ebv_pet_read_analysis_df(workbook)
rownames(raw) <- NULL
dfA <- raw
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
rownames(dfB) <- NULL
.message("A=%d B=%d immuno=%.0f ic_a=%.0f", nrow(dfA), nrow(dfB),
         sum(dfB$immuno %in% 1L, na.rm = TRUE), sum(dfB$ic_a %in% 1L, na.rm = TRUE))

# 固定 λ：全样本 EP2 CV 锁定 lambda.min（报告「固定惩罚」口径的可复现近似）
.lock_lambda <- function(df, endpoint = "DM", model = "EP2") {
  d0 <- .npc_endpoint_df(df, endpoint)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  mm <- tryCatch(.npc_design_matrix(d0, .npc_model_vars(model)), error = function(e) NULL)
  if (is.null(mm)) return(NULL)
  keep <- as.integer(rownames(mm))
  ev <- if (endpoint %in% c("DM", "LR")) as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
  fit <- tryCatch(
    glmnet::cv.glmnet(mm, survival::Surv(d0$time[keep], ev), family = "cox", alpha = 0,
                      nfolds = 5, type.measure = "deviance", standardize = TRUE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  as.numeric(fit$lambda.min)
}
lam_ep2 <- .lock_lambda(dfB, "DM", "EP2")
.message("Locked EP2 lambda.min = %s", if (is.null(lam_ep2)) "NA" else sprintf("%.6g", lam_ep2))

# ===========================================================================
# 1) 24 + 36 月 IPCW-AUC/Brier（C/E/P2/EP2/EP2X）+ EP2X
# ===========================================================================
.message("24/36-mo OOF AUC + EP2X...")
models_nest <- c("C", "E", "P2", "EP2", "EP2X")
horizons <- c(24L, 36L)
oof_store <- list()
rows_auc <- list()
for (ep in c("DM", "PFS", "OS")) {
  for (md in models_nest) {
    oof <- tryCatch(
      npc_ebv_pet_oof_cv(dfB, endpoint = ep, model = md, n_repeats = n_repeats,
                         n_folds = 5L, seed = 20261118L, horizon = 36,
                         lambda = if (md %in% c("EP2", "EP2X") && !is.null(lam_ep2)) lam_ep2 else NULL),
      error = function(e) { .message("OOF fail %s/%s: %s", ep, md, e$message); NULL }
    )
    if (is.null(oof)) next
    oof_store[[paste(ep, md, sep = "_")]] <- oof
    for (h in horizons) {
      met <- .npc_ipcw_auc(oof$time, oof$cause, oof$lp, horizon = h)
      rows_auc[[length(rows_auc) + 1L]] <- data.frame(
        Endpoint = ep, Model = md, Horizon_mo = h,
        N = oof$n, Events = oof$n_event,
        AUC = round(met$auc, 3), Brier = round(met$brier, 4),
        Lambda = if (is.null(oof$lambda) || !is.finite(oof$lambda)) "cv.lambda.min" else sprintf("%.4g", oof$lambda),
        stringsAsFactors = FALSE
      )
    }
  }
}
tab_auc <- do.call(rbind, rows_auc)
write_xlsx_simple(tab_auc,
  file.path(tbl_dir, "Table 2. Nested models 24-36 month IPCW-AUC across endpoints.xlsx"),
  "Table 2. Nested OOF IPCW-AUC and Brier at 24 and 36 months (cohort B; fixed-lambda EP2/EP2X when locked)")

# 更新旧 Table 2 文件名提示：保留 36 月主文兼容副本
tab36 <- tab_auc[tab_auc$Horizon_mo == 36, ]
write_xlsx_simple(tab36,
  file.path(tbl_dir, "Table 2. Nested models 36-month IPCW-AUC across five endpoints.xlsx"),
  "Table 2. Nested OOF IPCW-AUC at 36 months (subset of 24/36 table)")

# ===========================================================================
# 2) Bootstrap 乐观校正 C-index + 800 配对 ΔAUC
# ===========================================================================
.message("Bootstrap optimism-corrected C-index (n=%d)...", n_boot_c)
c_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  for (md in c("C", "EP2", "EP2X")) {
    rr <- tryCatch(
      npc_ebv_pet_boot_cindex(dfB, endpoint = ep, model = md, n_boot = n_boot_c,
                              seed = 20261118L,
                              lambda = if (md %in% c("EP2", "EP2X") && !is.null(lam_ep2)) lam_ep2 else NULL),
      error = function(e) NULL
    )
    if (!is.null(rr)) c_rows[[length(c_rows) + 1L]] <- rr
  }
}
tab_c <- do.call(rbind, c_rows)
if (!is.null(tab_c) && nrow(tab_c)) {
  tab_c$C_apparent <- round(tab_c$C_apparent, 3)
  tab_c$optimism <- round(tab_c$optimism, 4)
  tab_c$C_corrected <- round(tab_c$C_corrected, 3)
  write_xlsx_simple(tab_c,
    file.path(tbl_dir, "Table S19. Bootstrap optimism-corrected Harrell C-index.xlsx"),
    sprintf("Table S19. Optimism-corrected Harrell C-index (%d bootstrap refits; apparent minus mean optimism)", n_boot_c))
}

.message("Paired bootstrap ΔAUC EP2 vs C (n=%d)...", n_boot_pair)
oof_c <- oof_store[["DM_C"]]; oof_ep2 <- oof_store[["DM_EP2"]]; oof_ep2x <- oof_store[["DM_EP2X"]]
pair_rows <- list()
if (!is.null(oof_c) && !is.null(oof_ep2)) {
  # 对齐行
  n0 <- min(length(oof_c$lp), length(oof_ep2$lp))
  for (h in horizons) {
    pb <- tryCatch(
      npc_ebv_pet_paired_delta(oof_c, oof_ep2, n_boot = n_boot_pair, seed = 20261118L),
      error = function(e) NULL
    )
    # 强制按 horizon 重算
    ma <- oof_c$lp[seq_len(n0)]; mb <- oof_ep2$lp[seq_len(n0)]
    tm <- oof_c$time[seq_len(n0)]; cs <- oof_c$cause[seq_len(n0)]
    base <- .npc_ipcw_auc(tm, cs, ma, h); alt <- .npc_ipcw_auc(tm, cs, mb, h)
    set.seed(20261118L + h)
    dlt <- replicate(n_boot_pair, {
      ii <- sample.int(n0, replace = TRUE)
      .npc_ipcw_auc(tm[ii], cs[ii], mb[ii], h)$auc - .npc_ipcw_auc(tm[ii], cs[ii], ma[ii], h)$auc
    })
    dlt <- dlt[is.finite(dlt)]
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Contrast = "EP2 - C", Horizon_mo = h,
      AUC_ref = round(base$auc, 3), AUC_new = round(alt$auc, 3),
      Delta_AUC = round(alt$auc - base$auc, 3),
      CI_lo = round(as.numeric(quantile(dlt, 0.025, na.rm = TRUE)), 3),
      CI_hi = round(as.numeric(quantile(dlt, 0.975, na.rm = TRUE)), 3),
      n_boot = length(dlt), stringsAsFactors = FALSE
    )
  }
}
if (!is.null(oof_c) && !is.null(oof_ep2x)) {
  n0 <- min(length(oof_c$lp), length(oof_ep2x$lp))
  for (h in horizons) {
    ma <- oof_c$lp[seq_len(n0)]; mb <- oof_ep2x$lp[seq_len(n0)]
    tm <- oof_c$time[seq_len(n0)]; cs <- oof_c$cause[seq_len(n0)]
    base <- .npc_ipcw_auc(tm, cs, ma, h); alt <- .npc_ipcw_auc(tm, cs, mb, h)
    set.seed(20261119L + h)
    dlt <- replicate(n_boot_pair, {
      ii <- sample.int(n0, replace = TRUE)
      .npc_ipcw_auc(tm[ii], cs[ii], mb[ii], h)$auc - .npc_ipcw_auc(tm[ii], cs[ii], ma[ii], h)$auc
    })
    dlt <- dlt[is.finite(dlt)]
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Contrast = "EP2X - C", Horizon_mo = h,
      AUC_ref = round(base$auc, 3), AUC_new = round(alt$auc, 3),
      Delta_AUC = round(alt$auc - base$auc, 3),
      CI_lo = round(as.numeric(quantile(dlt, 0.025, na.rm = TRUE)), 3),
      CI_hi = round(as.numeric(quantile(dlt, 0.975, na.rm = TRUE)), 3),
      n_boot = length(dlt), stringsAsFactors = FALSE
    )
  }
}
tab_pair <- do.call(rbind, pair_rows)
if (!is.null(tab_pair) && nrow(tab_pair)) {
  write_xlsx_simple(tab_pair,
    file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC.xlsx"),
    sprintf("Table 3. Paired bootstrap ΔAUC for distant metastasis (%d resamples; OOF linear predictors)", n_boot_pair))
}

# ===========================================================================
# 3) 口径 A：M0–M4 + per-1SD HR
# ===========================================================================
.message("Cohort A M0–M4 (IC+immuno) + 1SD HRs...")
m_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  for (h in horizons) {
    rr <- tryCatch(npc_ebv_pet_m01234_apparent(dfA, endpoint = ep, horizon = h), error = function(e) NULL)
    if (!is.null(rr) && nrow(rr)) {
      rr$Horizon_mo <- h
      m_rows[[length(m_rows) + 1L]] <- rr
    }
  }
}
tab_m <- do.call(rbind, m_rows)
if (!is.null(tab_m) && nrow(tab_m)) {
  write_xlsx_simple(tab_m,
    file.path(tbl_dir, "Table S16. Cohort A M0-M4 apparent AUC.xlsx"),
    "Table S16. Cohort A M0–M4 apparent IPCW-AUC (M0 includes induction chemotherapy + immunotherapy)")
}

# per-1SD Cox HR（口径 A，原因特异 DM）
dA <- .npc_endpoint_df(dfA, "DM")
dA$age_z <- zscore(dA$age)
dA$Lmtv_z <- zscore(dA$Lmtv)
dA$Lnode_z <- zscore(dA$Lnode)
dA$t0_score_z <- zscore(dA$t0_score)
dA$cum_trap_z <- zscore(dA$cum_trap)
dA$ic_a <- as.integer(dA$ic_a %in% 1L)
dA$immuno <- as.integer(dA$immuno %in% 1L)
evA <- as.integer(dA$cause == 1L)
fit_sd <- tryCatch(
  coxph(Surv(time, evA) ~ age_z + male + t_ord + n_ord + ic_a + immuno +
          t0_score_z + Lmtv_z + Lnode_z + cum_trap_z, data = dA),
  error = function(e) NULL
)
if (!is.null(fit_sd)) {
  sd_terms <- c("age_z", "t0_score_z", "Lmtv_z", "Lnode_z", "cum_trap_z", "ic_a", "immuno", "male", "t_ord", "n_ord")
  sd_rows <- do.call(rbind, lapply(sd_terms, function(t) cox_hr_row(fit_sd, t)))
  if (!is.null(sd_rows) && nrow(sd_rows)) {
    sd_rows$Scale <- ifelse(grepl("_z$", sd_rows$Term), "per 1 SD", "binary/ordinal")
    sd_rows$HR_CI <- mapply(fmt_hr, sd_rows$HR, sd_rows$lo, sd_rows$hi)
    sd_rows$P <- vapply(sd_rows$p, fmt_p, character(1))
    write_xlsx_simple(sd_rows[, c("Term", "Scale", "HR_CI", "P")],
      file.path(tbl_dir, "Table S20. Cohort A multivariable HRs per 1 SD.xlsx"),
      "Table S20. Cohort A cause-specific Cox HRs (continuous markers per 1 SD; M0-style adjustment + markers)")
  }
}

# ===========================================================================
# 4) 6 参数简约联合模型 + 嵌套 LR
# ===========================================================================
.message("Parsimonious 6-parameter model + LR...")
# 报告简约规格：Age, Sex, Stage(or T/N), EBV_T0, MTV, nodal SUVmax  → 6 个核心参数块
dB <- .npc_endpoint_df(dfB, "DM")
dB$age_z <- zscore(dB$age); dB$Lmtv_z <- zscore(dB$Lmtv); dB$Lnode_z <- zscore(dB$Lnode)
dB$t0_score_z <- zscore(dB$t0_score)
evB <- as.integer(dB$cause == 1L)
# 嵌套：M_clin (age+sex+T+N) ⊂ M6 ( + EBV + MTV + Lnode) ⊂ M6x (+ interactions)
fit_clin <- tryCatch(coxph(Surv(time, evB) ~ age_z + male + t_ord + n_ord, data = dB), error = function(e) NULL)
fit_m6 <- tryCatch(coxph(Surv(time, evB) ~ age_z + male + t_ord + n_ord + t0_score_z + Lmtv_z + Lnode_z, data = dB), error = function(e) NULL)
fit_m6x <- tryCatch(
  coxph(Surv(time, evB) ~ age_z + male + t_ord + n_ord + t0_score_z + Lmtv_z + Lnode_z +
          t0_score_z:Lnode_z, data = dB),
  error = function(e) NULL
)
lr_rows <- list()
if (!is.null(fit_clin) && !is.null(fit_m6)) {
  a1 <- anova(fit_clin, fit_m6, test = "LRT")
  lr_rows[[length(lr_rows) + 1L]] <- data.frame(
    Comparison = "M6 (Age Sex T N EBV MTV Lnode) vs clinical",
    LR_stat = as.numeric(a1$Chisq[2]), df = as.numeric(a1$Df[2]),
    P = as.numeric(a1$`Pr(>|Chi|)`[2]), stringsAsFactors = FALSE
  )
}
if (!is.null(fit_m6) && !is.null(fit_m6x)) {
  a2 <- anova(fit_m6, fit_m6x, test = "LRT")
  lr_rows[[length(lr_rows) + 1L]] <- data.frame(
    Comparison = "M6 + EBV×Lnode vs M6",
    LR_stat = as.numeric(a2$Chisq[2]), df = as.numeric(a2$Df[2]),
    P = as.numeric(a2$`Pr(>|Chi|)`[2]), stringsAsFactors = FALSE
  )
}
# vs full ridge EP2 nested clinical-only by LR on same unpenalized M6 path already covers report
if (length(lr_rows)) {
  tab_lr6 <- do.call(rbind, lr_rows)
  tab_lr6$LR_stat <- round(tab_lr6$LR_stat, 3)
  tab_lr6$P_fmt <- vapply(tab_lr6$P, fmt_p, character(1))
  write_xlsx_simple(tab_lr6,
    file.path(tbl_dir, "Table S11. Nested likelihood-ratio tests.xlsx"),
    "Table S11. Nested likelihood-ratio tests for parsimonious 6-parameter joint model (unpenalized Cox)")
  # 系数表
  if (!is.null(fit_m6)) {
    sm <- summary(fit_m6)$coefficients
    coef_df <- data.frame(
      Term = rownames(sm),
      HR = exp(sm[, "coef"]),
      lo = exp(sm[, "coef"] - 1.96 * sm[, "se(coef)"]),
      hi = exp(sm[, "coef"] + 1.96 * sm[, "se(coef)"]),
      p = sm[, "Pr(>|z|)"],
      stringsAsFactors = FALSE
    )
    coef_df$HR_CI <- mapply(fmt_hr, coef_df$HR, coef_df$lo, coef_df$hi)
    coef_df$P <- vapply(coef_df$p, fmt_p, character(1))
    write_xlsx_simple(coef_df[, c("Term", "HR_CI", "P")],
      file.path(tbl_dir, "Table S21. Parsimonious 6-parameter joint model HRs.xlsx"),
      "Table S21. Parsimonious 6-parameter model (Age_z Sex T N EBV_T0_z MTV_z Lnode_z) cause-specific DM")
  }
}

# ===========================================================================
# 5) IC 亚组：T1×MTV + T1×淋巴结 SUVmax 双交互
# ===========================================================================
.message("IC double interaction T1×MTV + T1×Lnode...")
ic <- dfB[dfB$ic_a %in% 1L | dfB$ic %in% 1L | dfB$ic_code %in% 1L, , drop = FALSE]
rownames(ic) <- NULL
dIC <- .npc_endpoint_df(ic, "PFS")
dIC$t1_z <- zscore(dIC$t1_score)
dIC$Lmtv_z <- zscore(dIC$Lmtv)
dIC$Lnode_z <- zscore(dIC$Lnode)
dIC$age_z <- zscore(dIC$age)
evIC <- as.integer(dIC$cause > 0)
fit_base <- tryCatch(
  coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z + Lmtv_z + Lnode_z, data = dIC),
  error = function(e) NULL
)
fit_ix <- tryCatch(
  coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z + Lmtv_z + Lnode_z +
          t1_z:Lmtv_z + t1_z:Lnode_z, data = dIC),
  error = function(e) NULL
)
# 表观 AUC 对比（全样本 LP）
auc_ic <- NULL
if (!is.null(fit_base) && !is.null(fit_ix)) {
  # 与模型完整病例对齐，避免 LP 与 time 长度不一致
  mf <- model.frame(fit_ix)
  keep_ix <- as.integer(rownames(mf))
  dICk <- dIC[keep_ix, , drop = FALSE]
  lp0 <- as.numeric(predict(fit_base, newdata = dICk, type = "lp"))
  lp1 <- as.numeric(predict(fit_ix, newdata = dICk, type = "lp"))
  a0 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp0, 36)
  a1 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp1, 36)
  lr_ic <- anova(fit_base, fit_ix, test = "LRT")
  auc_ic <- data.frame(
    Cohort = "IC subcohort", Endpoint = "PFS", N = nrow(dIC),
    AUC_base = round(a0$auc, 3), AUC_double_interaction = round(a1$auc, 3),
    Delta_AUC = round(a1$auc - a0$auc, 3),
    LR_P = fmt_p(as.numeric(lr_ic$`Pr(>|Chi|)`[2])),
    Note = "Base = Age Sex T N T1 MTV Lnode; Alt adds T1×MTV and T1×nodal SUVmax",
    stringsAsFactors = FALSE
  )
  # 交互系数
  sm <- summary(fit_ix)$coefficients
  ix_terms <- grep(":", rownames(sm), value = TRUE)
  ix_df <- data.frame(
    Term = ix_terms,
    HR = exp(sm[ix_terms, "coef"]),
    lo = exp(sm[ix_terms, "coef"] - 1.96 * sm[ix_terms, "se(coef)"]),
    hi = exp(sm[ix_terms, "coef"] + 1.96 * sm[ix_terms, "se(coef)"]),
    p = sm[ix_terms, "Pr(>|z|)"],
    stringsAsFactors = FALSE
  )
  ix_df$HR_CI <- mapply(fmt_hr, ix_df$HR, ix_df$lo, ix_df$hi)
  ix_df$P <- vapply(ix_df$p, fmt_p, character(1))
  write_xlsx_simple(cbind(auc_ic, ix_df[1, c("Term", "HR_CI", "P")],
                          if (nrow(ix_df) > 1) ix_df[2, c("Term", "HR_CI", "P")] else NULL),
    file.path(tbl_dir, "Table S15. IC landmark T1xPET incremental AUC.xlsx"),
    "Table S15. IC subcohort double interaction (T1×MTV + T1×nodal SUVmax) PFS discrimination")
  # 更清晰：两张相关块写一张整洁表
  write_xlsx_simple(
    rbind(
      data.frame(Block = "Discrimination", Item = "AUC base / double-ix / Δ",
                 Value = sprintf("%.3f / %.3f / %.3f", a0$auc, a1$auc, a1$auc - a0$auc),
                 stringsAsFactors = FALSE),
      data.frame(Block = "LR test", Item = "double-ix vs base",
                 Value = fmt_p(as.numeric(lr_ic$`Pr(>|Chi|)`[2])), stringsAsFactors = FALSE),
      data.frame(Block = "Interaction HR", Item = ix_df$Term, Value = paste0(ix_df$HR_CI, "; P=", ix_df$P),
                 stringsAsFactors = FALSE)
    ),
    file.path(tbl_dir, "Table S22. IC double interaction T1xMTV and T1xLnode.xlsx"),
    "Table S22. IC subcohort: T1×MTV and T1×lymph-node SUVmax double interaction (PFS)"
  )
}

# ===========================================================================
# 6) 9 月界标 + 三层轨迹 ΔAUC/Brier
# ===========================================================================
.message("9-month landmark trajectory ΔAUC...")
lm9 <- dfB[as.integer(dfB$lm9) == 1L | as.integer(dfB$ic_lm9) == 1L, , drop = FALSE]
if (!nrow(lm9)) lm9 <- dfB[is.finite(dfB$os_time) & dfB$os_time >= 9, , drop = FALSE]
rownames(lm9) <- NULL
# 剩余时间：从 9 月起
dL <- .npc_endpoint_df(lm9, "DM")
dL$time_lm <- pmax(dL$time - 9, 0.01)
dL <- dL[dL$time >= 9, , drop = FALSE]
# 轨迹三层
tr <- as.character(dL$traj_risk)
if (!length(tr) || all(is.na(tr))) tr <- as.character(dL$TRAJ_RISK)
dL$traj3 <- factor(tr)
# 临床基线 LP vs +轨迹
dL$age_z <- zscore(dL$age); dL$t0_z <- zscore(dL$t0_score); dL$Lnode_z <- zscore(dL$Lnode)
evL <- as.integer(dL$cause == 1L)
fit_l0 <- tryCatch(coxph(Surv(time_lm, evL) ~ age_z + male + t_ord + n_ord + t0_z + Lnode_z, data = dL), error = function(e) NULL)
fit_l1 <- tryCatch(coxph(Surv(time_lm, evL) ~ age_z + male + t_ord + n_ord + t0_z + Lnode_z + traj3, data = dL), error = function(e) NULL)
if (!is.null(fit_l0) && !is.null(fit_l1) && nrow(dL) >= 40) {
  lp0 <- predict(fit_l0, type = "lp"); lp1 <- predict(fit_l1, type = "lp")
  # cause 用原 cause；time 用 landmark 后
  a0 <- .npc_ipcw_auc(dL$time_lm, dL$cause, lp0, 36)
  a1 <- .npc_ipcw_auc(dL$time_lm, dL$cause, lp1, 36)
  set.seed(20261118L)
  n0 <- length(lp0)
  dlt <- replicate(n_boot_pair, {
    ii <- sample.int(n0, replace = TRUE)
    .npc_ipcw_auc(dL$time_lm[ii], dL$cause[ii], lp1[ii], 36)$auc -
      .npc_ipcw_auc(dL$time_lm[ii], dL$cause[ii], lp0[ii], 36)$auc
  })
  dlt <- dlt[is.finite(dlt)]
  tab_lm <- data.frame(
    Landmark_mo = 9, Endpoint = "DM", N = nrow(dL),
    AUC_base = round(a0$auc, 3), AUC_plus_traj3 = round(a1$auc, 3),
    Delta_AUC = round(a1$auc - a0$auc, 3),
    CI_lo = round(as.numeric(quantile(dlt, 0.025)), 3),
    CI_hi = round(as.numeric(quantile(dlt, 0.975)), 3),
    Brier_base = round(a0$brier, 4), Brier_plus = round(a1$brier, 4),
    Delta_Brier = round(a1$brier - a0$brier, 4),
    stringsAsFactors = FALSE
  )
  write_xlsx_simple(tab_lm,
    file.path(tbl_dir, "Table 5. Landmark trajectory T2 incremental AUC.xlsx"),
    sprintf("Table 5. 9-month landmark: three-tier trajectory incremental AUC/Brier (%d paired bootstrap)", n_boot_pair))
  # Fig16 刷新
  save_pdf(file.path(fig_dir, "Figure 16. Landmark 9-month risk and T2 incremental AUC.pdf"), {
    print(
      ggplot(data.frame(Model = c("Base", "+Traj3"), AUC = c(a0$auc, a1$auc)),
             aes(Model, AUC, fill = Model)) +
        geom_col(width = 0.55, show.legend = FALSE) +
        geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.4, family = font_family) +
        coord_cartesian(ylim = c(0.4, max(0.85, max(c(a0$auc, a1$auc), na.rm = TRUE) + 0.08))) +
        labs(title = "9-month landmark DM discrimination",
             subtitle = sprintf("ΔAUC = %.3f (%.3f, %.3f)", tab_lm$Delta_AUC, tab_lm$CI_lo, tab_lm$CI_hi),
             y = "IPCW-AUC", x = NULL) +
        theme(plot.title = element_text(face = "bold"))
    )
  }, w = 6.2, h = 4.8)
  write_md("Figure 16. Landmark 9-month risk and T2 incremental AUC",
           sprintf("9 月界标后远转 IPCW-AUC：基线 %.3f，加入三层轨迹后 %.3f；ΔAUC=%.3f（%d 次配对自助 %.3f–%.3f）。",
                   a0$auc, a1$auc, tab_lm$Delta_AUC, n_boot_pair, tab_lm$CI_lo, tab_lm$CI_hi),
           sprintf("暴露：界标后临床+EBV+淋巴结 SUV ± 三层轨迹；结局：远转；N=%d；Grouping：9-month landmark survivors。", nrow(dL)))
}

# ===========================================================================
# 7) 生物学复发诊断效能
# ===========================================================================
.message("Biological relapse diagnostic metrics...")
br <- dfB[is.finite(dfB$bio_time) | dfB$bio_relapse %in% 1L, , drop = FALSE]
# 诊断：BioRelapse=1 预测随后临床进展（PFS 事件），提前天数 = PFS_time - bio_time
diag_df <- dfB
diag_df$bio <- as.integer(diag_df$bio_relapse %in% 1L | diag_df$BioRelapse %in% 1L)
diag_df$clin <- as.integer(diag_df$pfs_event %in% 1L)
# 若有 Bio 时间与 PFS 时间
lead <- diag_df$pfs_time - diag_df$bio_time
lead_pos <- lead[diag_df$bio == 1L & diag_df$clin == 1L & is.finite(lead)]
tp <- sum(diag_df$bio == 1L & diag_df$clin == 1L, na.rm = TRUE)
fp <- sum(diag_df$bio == 1L & diag_df$clin == 0L, na.rm = TRUE)
fn <- sum(diag_df$bio == 0L & diag_df$clin == 1L, na.rm = TRUE)
tn <- sum(diag_df$bio == 0L & diag_df$clin == 0L, na.rm = TRUE)
sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
ppv <- if ((tp + fp) > 0) tp / (tp + fp) else NA_real_
npv <- if ((tn + fn) > 0) tn / (tn + fn) else NA_real_
# 12 月界标：生物复发阳性 vs 阴性的远转 HR
lm12 <- diag_df[is.finite(diag_df$dm_time) & diag_df$dm_time >= 12, , drop = FALSE]
lm12$time_lm <- pmax(lm12$dm_time - 12, 0.01)
lm12$ev <- as.integer(lm12$dm_status == 1L)
fit_bio <- tryCatch(coxph(Surv(time_lm, ev) ~ bio + age + male, data = lm12), error = function(e) NULL)
bio_hr <- if (!is.null(fit_bio)) cox_hr_row(fit_bio, "bio") else NULL
tab_bio <- data.frame(
  Metric = c("N", "BioRelapse+", "Clinical progression+", "TP", "FP", "FN", "TN",
             "Sensitivity", "Specificity", "PPV", "NPV",
             "Lead_time_median_days", "Lead_time_IQR",
             "Landmark12_HR_bio_vs_neg"),
  Value = c(
    nrow(diag_df), sum(diag_df$bio == 1L, na.rm = TRUE), sum(diag_df$clin == 1L, na.rm = TRUE),
    tp, fp, fn, tn,
    sprintf("%.3f", sens), sprintf("%.3f", spec), sprintf("%.3f", ppv), sprintf("%.3f", npv),
    if (length(lead_pos)) sprintf("%.1f", median(lead_pos) * 30.4375) else "NE",
    if (length(lead_pos) >= 4) sprintf("%.1f–%.1f", quantile(lead_pos, 0.25) * 30.4375, quantile(lead_pos, 0.75) * 30.4375) else "NE",
    if (!is.null(bio_hr)) fmt_hr(bio_hr$HR, bio_hr$lo, bio_hr$hi) else "NE"
  ),
  stringsAsFactors = FALSE
)
write_xlsx_simple(tab_bio,
  file.path(tbl_dir, "Table S23. Biological relapse diagnostic performance.xlsx"),
  "Table S23. Biological relapse vs subsequent clinical progression (Sens/Spec/PPV/NPV; lead time; 12-mo landmark HR)")

# 刷新 Fig18：诊断条形
save_pdf(file.path(fig_dir, "Figure 18. Biological relapse warning value and bias.pdf"), {
  dd <- data.frame(
    Metric = factor(c("Sensitivity", "Specificity", "PPV", "NPV"),
                    levels = c("Sensitivity", "Specificity", "PPV", "NPV")),
    Value = c(sens, spec, ppv, npv)
  )
  print(
    ggplot(dd, aes(Metric, Value, fill = Metric)) +
      geom_col(width = 0.6, show.legend = FALSE) +
      geom_text(aes(label = sprintf("%.3f", Value)), vjust = -0.35, family = font_family) +
      coord_cartesian(ylim = c(0, 1.05)) +
      labs(title = "Biological relapse diagnostic performance",
           subtitle = sprintf("Median lead time %.1f days (Bio+ & clinically progressed)",
                              if (length(lead_pos)) median(lead_pos) * 30.4375 else NA),
           y = "Proportion", x = NULL) +
      theme(plot.title = element_text(face = "bold"))
  )
}, w = 6.5, h = 4.8)
write_md("Figure 18. Biological relapse warning value and bias",
         sprintf("生物学复发相对随后临床进展：Sens=%.3f Spec=%.3f PPV=%.3f NPV=%.3f；阳性且进展者中位提前约 %.1f 天。",
                 sens, spec, ppv, npv, if (length(lead_pos)) median(lead_pos) * 30.4375 else NA),
         sprintf("队列 B N=%d；生物复发 n=%d；临床进展 n=%d。提前天数 = PFS 月 − 生物复发月，再 ×30.4375。",
                 nrow(diag_df), sum(diag_df$bio == 1), sum(diag_df$clin == 1)))

# ===========================================================================
# 8) 四象限分层 HR + RERI；MTV/SUVmax 中位交叉
# ===========================================================================
.message("Quadrant HR + RERI + median cross-strata...")
# EBV high × PET high 四象限
dQ <- .npc_endpoint_df(dfB, "DM")
dQ$eh <- as.integer(dQ$ebv_high %in% 1L | dQ$t0_pos %in% 1L)
dQ$ph <- as.integer(dQ$pet_high %in% 1L)
if (all(dQ$ph == 0L | is.na(dQ$ph))) {
  med_n <- median(dQ$Lnode, na.rm = TRUE)
  dQ$ph <- as.integer(dQ$Lnode >= med_n)
}
dQ$quad <- factor(paste0("EBV", dQ$eh, "_PET", dQ$ph),
                  levels = c("EBV0_PET0", "EBV1_PET0", "EBV0_PET1", "EBV1_PET1"))
evQ <- as.integer(dQ$cause == 1L)
# 2×2 指示编码更稳：RERI = HR11 − HR10 − HR01 + 1
fit_q <- tryCatch(
  coxph(Surv(time, evQ) ~ eh + ph + eh:ph + age + male, data = dQ),
  error = function(e) NULL
)
reri_val <- NA_real_; hr11 <- hr10 <- hr01 <- NA_real_
q_rows <- list()
if (!is.null(fit_q)) {
  cf <- coef(fit_q); se <- sqrt(diag(vcov(fit_q)))
  b_e <- unname(cf["eh"]); b_p <- unname(cf["ph"]); b_x <- unname(cf["eh:ph"])
  if (all(is.finite(c(b_e, b_p, b_x)))) {
    hr10 <- exp(b_e); hr01 <- exp(b_p); hr11 <- exp(b_e + b_p + b_x)
    reri_val <- hr11 - hr10 - hr01 + 1
    mk <- function(nm, b, s) {
      data.frame(Stratum = nm, HR = exp(b), lo = exp(b - 1.96 * s), hi = exp(b + 1.96 * s),
                 p = 2 * pnorm(-abs(b / s)), stringsAsFactors = FALSE)
    }
    # 交互项 se：Var(b_e+b_p+b_x)
    V <- vcov(fit_q)
    s11 <- sqrt(V["eh", "eh"] + V["ph", "ph"] + V["eh:ph", "eh:ph"] +
                  2 * V["eh", "ph"] + 2 * V["eh", "eh:ph"] + 2 * V["ph", "eh:ph"])
    q_rows <- list(
      mk("EBV1_PET0", b_e, se["eh"]),
      mk("EBV0_PET1", b_p, se["ph"]),
      mk("EBV1_PET1", b_e + b_p + b_x, s11)
    )
  }
}
# 中位交叉：MTV × nodal SUVmax
dQ$mtv_hi <- as.integer(dQ$Lmtv >= median(dQ$Lmtv, na.rm = TRUE))
dQ$suv_hi <- as.integer(dQ$Lnode >= median(dQ$Lnode, na.rm = TRUE))
dQ$cross <- factor(paste0("MTV", dQ$mtv_hi, "_SUV", dQ$suv_hi),
                   levels = c("MTV0_SUV0", "MTV1_SUV0", "MTV0_SUV1", "MTV1_SUV1"))
fit_x <- tryCatch(coxph(Surv(time, evQ) ~ cross + age + male, data = dQ), error = function(e) NULL)
x_rows <- list()
if (!is.null(fit_x)) {
  for (lv in levels(dQ$cross)[-1]) {
    rr <- cox_hr_row(fit_x, paste0("cross", lv))
    if (!is.null(rr)) { rr$Stratum <- lv; x_rows[[length(x_rows) + 1L]] <- rr }
  }
}
tab_q <- data.frame(
  Analysis = c("EBV×PET quadrant", "EBV×PET quadrant", "EBV×PET quadrant", "RERI additive"),
  Stratum = c("EBV+/PET−", "EBV−/PET+", "EBV+/PET+", "RERI=HR11−HR10−HR01+1"),
  HR_CI = c(
    if (is.finite(hr10)) sprintf("%.3f", hr10) else "NE",
    if (is.finite(hr01)) sprintf("%.3f", hr01) else "NE",
    if (is.finite(hr11)) sprintf("%.3f", hr11) else "NE",
    if (is.finite(reri_val)) sprintf("%.3f", reri_val) else "NE"
  ),
  stringsAsFactors = FALSE
)
if (length(q_rows)) {
  qq <- do.call(rbind, q_rows)
  qq$HR_CI <- mapply(fmt_hr, qq$HR, qq$lo, qq$hi)
  qq$P <- vapply(qq$p, fmt_p, character(1))
  write_xlsx_simple(qq[, c("Stratum", "HR_CI", "P")],
    file.path(tbl_dir, "Table S5. EBV PET RERI for distant metastasis.xlsx"),
    sprintf("Table S5. EBV×PET quadrant stratified HRs (Age+Sex adjusted) and additive RERI=%.3f", reri_val))
}
if (length(x_rows)) {
  xx <- do.call(rbind, x_rows)
  xx$HR_CI <- mapply(fmt_hr, xx$HR, xx$lo, xx$hi)
  xx$P <- vapply(xx$p, fmt_p, character(1))
  write_xlsx_simple(xx[, c("Stratum", "HR_CI", "P")],
    file.path(tbl_dir, "Table S24. MTV SUVmax median cross-strata HRs.xlsx"),
    "Table S24. Primary MTV × nodal SUVmax median cross-strata HRs for distant metastasis (Age+Sex)")
}

# Fig14 刷新
save_pdf(file.path(fig_dir, "Figure 14. EBV PET quadrant distant-metastasis risk and interaction.pdf"), {
  rates <- as.data.frame(xtabs(~ eh + ph, data = dQ))
  # event rates
  er <- aggregate(evQ ~ eh + ph, data = dQ, FUN = function(z) mean(z))
  names(er)[3] <- "rate"
  er$label <- sprintf("EBV%s/PET%s\nHR context RERI=%.2f", er$eh, er$ph, reri_val)
  print(
    ggplot(er, aes(factor(eh), factor(ph), fill = rate)) +
      geom_tile(color = "white", linewidth = 0.6) +
      geom_text(aes(label = sprintf("%.1f%%\nn=%d", 100 * rate,
                                    as.integer(table(paste(dQ$eh, dQ$ph))[paste(eh, ph)]))),
                family = font_family, lineheight = 0.9) +
      scale_fill_gradient(low = "#f7fbff", high = "#08306b", name = "DM rate") +
      labs(title = "EBV × PET quadrant distant-metastasis rates",
           subtitle = sprintf("Additive RERI = %.3f (Age+Sex–adjusted HRs)", reri_val),
           x = "EBV high (0/1)", y = "PET high (0/1)") +
      theme(plot.title = element_text(face = "bold"))
  )
}, w = 6.5, h = 5)
write_md("Figure 14. EBV PET quadrant distant-metastasis risk and interaction",
         sprintf("EBV×PET 四象限远转粗率热图；相加交互 RERI=%.3f（基于 Age+Sex 调整分层 HR）。", reri_val),
         sprintf("队列 B；远转原因特异；PET high = 淋巴结 SUVmax ≥ 中位（若原 pet_high 缺失）。"))

# ===========================================================================
# 9) 校准四分位
# ===========================================================================
.message("Calibration quartiles...")
if (!is.null(oof_ep2)) {
  lp <- oof_ep2$lp; tm <- oof_ep2$time; cs <- oof_ep2$cause
  ok <- is.finite(lp) & is.finite(tm)
  lp <- lp[ok]; tm <- tm[ok]; cs <- cs[ok]
  # 36 月预测风险：1 - S0(t)^exp(lp-mean)
  ev <- as.integer(cs == 1L)
  sf <- survfit(Surv(tm, ev) ~ 1)
  s0 <- approx(sf$time, sf$surv, xout = 36, rule = 2, yleft = 1, yright = min(sf$surv))$y
  risk <- 1 - s0^exp(lp - mean(lp, na.rm = TRUE))
  q <- cut(risk, breaks = quantile(risk, probs = seq(0, 1, 0.25), na.rm = TRUE),
           include.lowest = TRUE, labels = paste0("Q", 1:4))
  cal <- data.frame(Q = q, risk = risk, event36 = as.integer(cs == 1L & tm <= 36))
  cal_sum <- aggregate(cbind(Predicted = risk, Observed = event36) ~ Q, data = cal, FUN = mean)
  cal_sum$N <- as.integer(table(q)[as.character(cal_sum$Q)])
  cal_sum$Predicted <- round(100 * cal_sum$Predicted, 1)
  cal_sum$Observed <- round(100 * cal_sum$Observed, 1)
  write_xlsx_simple(cal_sum,
    file.path(tbl_dir, "Table S25. EP2 calibration quartiles at 36 months.xlsx"),
    "Table S25. EP2 OOF predicted vs observed 36-month distant-metastasis risk by prediction quartile")
  save_pdf(file.path(fig_dir, "Figure 17. Temporal holdout calibration and risk strata.pdf"), {
    print(
      ggplot(cal_sum, aes(Predicted, Observed, label = Q)) +
        geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey50") +
        geom_point(size = 3, color = "#08519c") +
        geom_text(vjust = -0.8, family = font_family) +
        coord_equal(xlim = c(0, max(cal_sum$Predicted, cal_sum$Observed) * 1.2),
                    ylim = c(0, max(cal_sum$Predicted, cal_sum$Observed) * 1.2)) +
        labs(title = "EP2 OOF calibration by risk quartile (36-month DM)",
             x = "Predicted risk (%)", y = "Observed event rate (%)") +
        theme(plot.title = element_text(face = "bold"))
    )
  }, w = 5.8, h = 5.5)
  write_md("Figure 17. Temporal holdout calibration and risk strata",
           paste0("EP2 OOF 36 月远转风险按预测四分位：",
                  paste(sprintf("%s 预测 %.1f%% / 观察 %.1f%%", cal_sum$Q, cal_sum$Predicted, cal_sum$Observed), collapse = "；"),
                  "。"),
           sprintf("队列 B；模型 EP2；基准生存取整体 KM 在 36 月；风险 = 1−S0^exp(LP−mean)。N=%d。", sum(ok)))
}

# ===========================================================================
# 10) 基线特征表（替换 Table 1 角色：保留事件账本为 S 或另存）
# ===========================================================================
.message("Baseline characteristics table...")
# 原 Table 1 事件账本改存 S26，主 Table 1 改为基线特征
old_t1 <- file.path(tbl_dir, "Table 1. Five-endpoint event ledger in cohort B.xlsx")
if (file.exists(old_t1)) {
  file.copy(old_t1, file.path(tbl_dir, "Table S26. Five-endpoint event ledger in cohort B.xlsx"), overwrite = TRUE)
}
desc_cat <- function(x, lvl = NULL) {
  x <- as.character(x); x[is.na(x) | x == ""] <- "Missing"
  tb <- table(x); n <- sum(tb)
  paste(sprintf("%s %d (%.1f%%)", names(tb), as.integer(tb), 100 * as.integer(tb) / n), collapse = "; ")
}
desc_cont <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (!length(x)) return("NE")
  sprintf("%.1f (%.1f–%.1f)", median(x), quantile(x, 0.25), quantile(x, 0.75))
}
base_rows <- data.frame(
  Characteristic = c(
    "N", "Age, years, median (IQR)", "Sex male, n (%)",
    "AJCC8 stage", "T category", "N category",
    "Induction chemotherapy, n (%)", "Immunotherapy combination, n (%)",
    "HBsAg positive, n (%)",
    "EBV T0 above threshold, n (%)", "EBV T0 score, median (IQR)",
    "Primary MTV (log), median (IQR)", "Nodal SUVmax (log), median (IQR)",
    "Follow-up OS months, median (IQR)",
    "DM events, n (%)", "PFS events, n (%)", "OS deaths, n (%)"
  ),
  Overall = c(
    nrow(dfB),
    desc_cont(dfB$age),
    sprintf("%d (%.1f%%)", sum(dfB$male == 1, na.rm = TRUE), 100 * mean(dfB$male == 1, na.rm = TRUE)),
    desc_cat(dfB$ajcc8),
    desc_cat(dfB$T),
    desc_cat(dfB$N),
    sprintf("%d (%.1f%%)", sum(dfB$ic_a %in% 1L, na.rm = TRUE), 100 * mean(dfB$ic_a %in% 1L, na.rm = TRUE)),
    sprintf("%d (%.1f%%)", sum(dfB$immuno %in% 1L, na.rm = TRUE), 100 * mean(dfB$immuno %in% 1L, na.rm = TRUE)),
    sprintf("%d (%.1f%%)", sum(dfB$hbsag_pos %in% 1L, na.rm = TRUE), 100 * mean(dfB$hbsag_pos %in% 1L, na.rm = TRUE)),
    sprintf("%d (%.1f%%)", sum(dfB$t0_pos == 1, na.rm = TRUE), 100 * mean(dfB$t0_pos == 1, na.rm = TRUE)),
    desc_cont(dfB$t0_score),
    desc_cont(dfB$Lmtv),
    desc_cont(dfB$Lnode),
    desc_cont(dfB$os_time),
    sprintf("%d (%.1f%%)", sum(dfB$dm_status == 1, na.rm = TRUE), 100 * mean(dfB$dm_status == 1, na.rm = TRUE)),
    sprintf("%d (%.1f%%)", sum(dfB$pfs_event == 1, na.rm = TRUE), 100 * mean(dfB$pfs_event == 1, na.rm = TRUE)),
    sprintf("%d (%.1f%%)", sum(dfB$os_event == 1, na.rm = TRUE), 100 * mean(dfB$os_event == 1, na.rm = TRUE))
  ),
  stringsAsFactors = FALSE
)
write_xlsx_simple(base_rows,
  file.path(tbl_dir, "Table 1. Baseline characteristics of cohort B.xlsx"),
  "Table 1. Baseline characteristics of analysis cohort B (include==1)")
# 删除旧 Table 1 事件账本主名（已拷到 S26）
if (file.exists(old_t1)) unlink(old_t1)

# ===========================================================================
# 11) 阈值 × 年代；HBsAg 探索 + BH
# ===========================================================================
.message("LOD×era and HBsAg BH...")
dfB$era <- cut(dfB$dx_year, breaks = c(-Inf, 2016, 2019, Inf),
               labels = c("≤2016", "2017–2019", "≥2020"))
lod_era <- as.data.frame(xtabs(~ lod_cat + era, data = dfB))
names(lod_era) <- c("LOD", "Era", "N")
lod_era$Pct_within_era <- round(100 * ave(lod_era$N, lod_era$Era, FUN = function(z) z / sum(z)), 1)
write_xlsx_simple(lod_era,
  file.path(tbl_dir, "Table S27. EBV LOD threshold by diagnosis era.xlsx"),
  "Table S27. Overlap of EBV DNA assay LOD categories with diagnosis era")

# HBsAg 探索：与 DM / PFS / OS 单因素 + BH
hb_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  d <- .npc_endpoint_df(dfB, ep)
  d$hb <- as.integer(d$hbsag_pos %in% 1L)
  ev <- if (ep %in% c("DM", "LR")) as.integer(d$cause == 1L) else as.integer(d$cause > 0)
  fit <- tryCatch(coxph(Surv(time, ev) ~ hb + age + male, data = d), error = function(e) NULL)
  if (is.null(fit)) next
  rr <- cox_hr_row(fit, "hb")
  if (is.null(rr)) next
  rr$Endpoint <- ep
  hb_rows[[length(hb_rows) + 1L]] <- rr
}
if (length(hb_rows)) {
  hb <- do.call(rbind, hb_rows)
  hb$q_BH <- p.adjust(hb$p, method = "BH")
  hb$HR_CI <- mapply(fmt_hr, hb$HR, hb$lo, hb$hi)
  hb$P <- vapply(hb$p, fmt_p, character(1))
  hb$q <- vapply(hb$q_BH, fmt_p, character(1))
  write_xlsx_simple(hb[, c("Endpoint", "HR_CI", "P", "q")],
    file.path(tbl_dir, "Table S28. HBsAg exploratory Cox with BH adjustment.xlsx"),
    "Table S28. Exploratory HBsAg association (Age+Sex adjusted) with Benjamini–Hochberg q-values")
}

# ===========================================================================
# 12) Methods / NUMBERING 更新
# ===========================================================================
.message("Updating Methods and NUMBERING...")
methods <- c(
  "# Statistical analysis (NPC EBV DNA × PET/CT joint prediction)",
  "",
  "## Cohorts",
  "Cohort A is the full curated workbook cohort; cohort B is the primary analysis set with include==1. Baseline characteristics (Table 1) summarise cohort B.",
  "",
  "## Endpoints and horizons",
  "Primary discrimination uses repeated event-stratified 5-fold out-of-bag (OOF) ridge Cox linear predictors with IPCW time-dependent AUC and Brier score at **24 and 36 months** (timeROC; competing-risk AUC_1 when applicable).",
  "",
  "## Models",
  "Nested clinical (C), EBV-augmented (E), PET-2 (P2), joint EP2, and EP2X (EP2 plus EBV×nodal SUVmax interaction) were fit. Ridge penalty for EP2/EP2X used a **fixed λ locked from full-sample CV (lambda.min)** then applied inside each OOF fold (report-style fixed penalty). Unpenalized nested likelihood-ratio tests used a parsimonious six-parameter block (Age_z, Sex, T, N, EBV_T0_z, MTV_z, nodal SUVmax_z).",
  "",
  "## Validation metrics",
  sprintf("Optimism-corrected Harrell C-index used %d bootstrap refits (apparent C minus mean optimism). Paired bootstrap ΔAUC used %d resamples on locked OOF predictors.", n_boot_c, n_boot_pair),
  "",
  "## Cohort A M0–M4",
  "Apparent M0–M4 models on cohort A include induction chemotherapy and immunotherapy indicators in M0; continuous markers are also reported as HR per 1 SD.",
  "",
  "## Interactions and landmarks",
  "IC subcohort evaluated simultaneous T1×MTV and T1×nodal SUVmax interactions for PFS. Nine-month landmark analyses added three-tier EBV trajectory to clinical+EBV+PET predictors. EBV×PET quadrant stratified HRs and additive RERI, plus MTV×SUVmax median cross-strata, are reported.",
  "",
  "## Biological relapse",
  "Diagnostic Sens/Spec/PPV/NPV treat biological relapse as the index test for subsequent clinical progression; lead time uses PFS time minus biological-relapse time; 12-month landmark Cox HR compares bio-positive vs bio-negative survivors.",
  "",
  "## Calibration and exploration",
  "EP2 OOF predicted 36-month risk was binned into quartiles (predicted vs observed). LOD×diagnosis-era overlap and exploratory HBsAg associations (BH q-values) are supplementary.",
  "",
  "## Software",
  paste(readLines(file.path(out_root, "Methods_software_versions.txt"), warn = FALSE), collapse = " "),
  "",
  "## Note on report digits",
  "All estimates are recomputed from case-level workbook data. Numerical values are **not forced** to match any prior report headline (e.g. 0.634→0.711); methodological specifications above are authoritative."
)
writeLines(methods, file.path(out_root, "Methods_statistical_analysis.md"), useBytes = TRUE)

num <- c(
  "# Numbering and role (summary（new）)",
  "",
  "## Main tables",
  "- Table 1: Baseline characteristics (cohort B)",
  "- Table 2: Nested OOF IPCW-AUC/Brier at 24 and 36 months (incl. EP2X)",
  "- Table 3: Paired bootstrap ΔAUC (800 resamples; fixed-λ EP2/EP2X)",
  "- Table 4: Adjusted HRs for EBV/PET markers",
  "- Table 5: 9-month landmark trajectory incremental AUC/Brier",
  "",
  "## Key supplements added for report-spec gaps",
  "- S11: Parsimonious 6-parameter nested LR",
  "- S15/S22: IC double interaction T1×MTV + T1×Lnode",
  "- S16: Cohort A M0–M4 (IC+immuno)",
  "- S19: Bootstrap optimism-corrected C-index",
  "- S20: Cohort A HR per 1 SD",
  "- S21: Parsimonious 6-parameter HR table",
  "- S23: Biological relapse diagnostic table",
  "- S24: MTV×SUVmax median cross-strata",
  "- S25: Calibration quartiles",
  "- S26: Event ledger (former Table 1)",
  "- S27: LOD × era",
  "- S28: HBsAg + BH",
  "",
  "## Figures",
  "Fig1–20 retained; Fig14/16/17/18 refreshed to match new tables where applicable."
)
writeLines(num, file.path(out_root, "NUMBERING_AND_ROLE.md"), useBytes = TRUE)

.message("DONE. Output root: %s", out_root)
