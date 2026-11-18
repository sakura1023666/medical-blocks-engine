#!/usr/bin/env Rscript
# 规格对齐收口：五终点×C–EP6、报告惩罚、OOF8/IC6、轨迹协议、IC对照、
# 四象限定义、双向三终点 LR、log2 Lnode、T2五终点、留出校准、生物复发日期、
# U/UP2/IUX、配对重估删失权重。数字独立重算，不强制对齐报告标题值。
suppressPackageStartupMessages({
  library(survival); library(glmnet); library(ggplot2); library(openxlsx)
  library(timeROC); library(grid)
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

workbook <- .get_arg("--workbook", "/mnt/g/02block_result/53_NPC/ml_40395549/DATA/鼻咽癌EBV_PETCT数据表(1).xlsx")
out_root <- .get_arg("--out", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
n_rep_main <- as.integer(.get_arg("--repeats", "8"))
n_rep_ic <- as.integer(.get_arg("--repeats-ic", "6"))
n_boot_pair <- as.integer(.get_arg("--boot-pair", "800"))
n_boot_lm <- as.integer(.get_arg("--boot-lm", "1000"))
n_boot_c <- as.integer(.get_arg("--boot-c", "200"))
if ("--quick" %in% args) {
  n_rep_main <- 2L; n_rep_ic <- 2L; n_boot_pair <- 120L; n_boot_lm <- 200L; n_boot_c <- 60L
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
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
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
  sm <- summary(fit)$coefficients
  i <- match(term, rownames(sm))
  if (is.na(i)) return(NULL)
  data.frame(Term = term, HR = exp(sm[i, "coef"]),
             lo = exp(sm[i, "coef"] - 1.96 * sm[i, "se(coef)"]),
             hi = exp(sm[i, "coef"] + 1.96 * sm[i, "se(coef)"]),
             p = sm[i, "Pr(>|z|)"], stringsAsFactors = FALSE)
}

# 配对 Δ：固定 OOF LP，每次 bootstrap 重估删失权重（经 timeROC / IPCW Brier）
paired_delta_h <- function(oof_a, oof_b, horizon, n_boot, seed) {
  n0 <- min(length(oof_a$lp), length(oof_b$lp))
  ma <- oof_a$lp[seq_len(n0)]; mb <- oof_b$lp[seq_len(n0)]
  tm <- oof_a$time[seq_len(n0)]; cs <- oof_a$cause[seq_len(n0)]
  ok <- is.finite(ma) & is.finite(mb) & is.finite(tm)
  ma <- ma[ok]; mb <- mb[ok]; tm <- tm[ok]; cs <- cs[ok]
  base <- .npc_ipcw_auc(tm, cs, ma, horizon)
  alt <- .npc_ipcw_auc(tm, cs, mb, horizon)
  set.seed(seed)
  dlt <- replicate(n_boot, {
    ii <- sample.int(length(tm), replace = TRUE)
    .npc_ipcw_auc(tm[ii], cs[ii], mb[ii], horizon)$auc -
      .npc_ipcw_auc(tm[ii], cs[ii], ma[ii], horizon)$auc
  })
  dlt <- dlt[is.finite(dlt)]
  list(auc_ref = base$auc, auc_new = alt$auc, delta = alt$auc - base$auc,
       brier_ref = base$brier, brier_new = alt$brier,
       lo = as.numeric(quantile(dlt, 0.025, na.rm = TRUE)),
       hi = as.numeric(quantile(dlt, 0.975, na.rm = TRUE)),
       n_boot = length(dlt))
}

.message("Reading...")
raw <- npc_ebv_pet_read_analysis_df(workbook)
rownames(raw) <- NULL
dfA <- raw
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
rownames(dfB) <- NULL
lamA <- npc_ebv_pet_penalty_lambda("A")
lamB <- npc_ebv_pet_penalty_lambda("B")
.message("A=%d B=%d | lambda A=%.3f B=%.3g | pet_high=%d ebv_high=%d",
         nrow(dfA), nrow(dfB), lamA, lamB,
         sum(dfB$pet_high == 1, na.rm = TRUE), sum(dfB$ebv_high == 1, na.rm = TRUE))
.message("quadrant: %s", paste(names(table(dfB$quadrant)), table(dfB$quadrant), collapse = "; "))

endpoints5 <- c("OS", "PFS", "DM", "DM+D", "LR")
models_full <- c("C", "E", "P2", "P6", "EP2", "EP6", "EP2X")
horizons <- c(24L, 36L)

# ===========================================================================
# 1) 五终点 × C–EP6(+EP2X) OOF，报告 B 惩罚，主模型 8 次重复
# ===========================================================================
.message("Five-endpoint nested OOF (repeats=%d, lambdaB=%g)...", n_rep_main, lamB)
oof_store <- list()
rows_auc <- list()
for (ep in endpoints5) {
  for (md in models_full) {
    .message("  OOF %s / %s", ep, md)
    oof <- tryCatch(
      npc_ebv_pet_oof_cv(dfB, endpoint = ep, model = md, n_repeats = n_rep_main,
                         n_folds = 5L, seed = 20261118L + match(ep, endpoints5) * 17L + match(md, models_full),
                         horizon = 36, lambda = lamB),
      error = function(e) { .message("    FAIL: %s", e$message); NULL }
    )
    if (is.null(oof)) next
    oof_store[[paste(ep, md, sep = "_")]] <- oof
    for (h in horizons) {
      met <- .npc_ipcw_auc(oof$time, oof$cause, oof$lp, horizon = h)
      rows_auc[[length(rows_auc) + 1L]] <- data.frame(
        Endpoint = ep, Model = md, Horizon_mo = h,
        N = oof$n, Events = oof$n_event,
        AUC = round(met$auc, 3), Brier = round(met$brier, 4),
        Lambda = sprintf("%.4g", lamB), Repeats = n_rep_main,
        stringsAsFactors = FALSE
      )
    }
  }
}
tab_auc <- do.call(rbind, rows_auc)
write_xlsx_simple(tab_auc,
  file.path(tbl_dir, "Table 2. Nested models 24-36 month IPCW-AUC across endpoints.xlsx"),
  "Table 2. Five-endpoint nested OOF IPCW-AUC/Brier at 24/36 months (C–EP6/EP2X; cohort-B ridge λ=5)")
write_xlsx_simple(tab_auc[tab_auc$Horizon_mo == 36, ],
  file.path(tbl_dir, "Table 2. Nested models 36-month IPCW-AUC across five endpoints.xlsx"),
  "Table 2. Five-endpoint nested OOF IPCW-AUC at 36 months")

# ===========================================================================
# 2) 配对 ΔAUC（800；每次重估删失权重）+ 乐观校正 C
# ===========================================================================
.message("Paired ΔAUC (n=%d, re-estimate censoring weights)...", n_boot_pair)
pair_rows <- list()
for (h in horizons) {
  for (contrast in list(c("C", "EP2"), c("C", "E"), c("C", "P2"), c("EP2", "EP6"), c("C", "EP2X"))) {
    oa <- oof_store[[paste("DM", contrast[1], sep = "_")]]
    ob <- oof_store[[paste("DM", contrast[2], sep = "_")]]
    if (is.null(oa) || is.null(ob)) next
    pd <- paired_delta_h(oa, ob, h, n_boot_pair, 20261118L + h + match(contrast[2], models_full))
    pair_rows[[length(pair_rows) + 1L]] <- data.frame(
      Contrast = paste(contrast[2], "-", contrast[1]), Horizon_mo = h,
      AUC_ref = round(pd$auc_ref, 3), AUC_new = round(pd$auc_new, 3),
      Delta_AUC = round(pd$delta, 3),
      CI_lo = round(pd$lo, 3), CI_hi = round(pd$hi, 3),
      Brier_ref = round(pd$brier_ref, 4), Brier_new = round(pd$brier_new, 4),
      n_boot = pd$n_boot,
      Note = "Paired patient bootstrap on fixed OOF LPs; IPCW censoring weights re-estimated each resample",
      stringsAsFactors = FALSE
    )
  }
}
tab_pair <- do.call(rbind, pair_rows)
write_xlsx_simple(tab_pair,
  file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC.xlsx"),
  sprintf("Table 3. DM paired ΔAUC/Brier (%d bootstraps; censoring weights re-estimated)", n_boot_pair))

.message("Bootstrap optimism-corrected C (n=%d)...", n_boot_c)
c_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  for (md in c("C", "P2", "EP2", "EP6", "EP2X")) {
    rr <- tryCatch(
      npc_ebv_pet_boot_cindex(dfB, endpoint = ep, model = md, n_boot = n_boot_c,
                              seed = 20261118L, lambda = lamB),
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
    sprintf("Table S19. Optimism-corrected Harrell C (λ=5; %d bootstrap refits)", n_boot_c))
}

# ===========================================================================
# 3) 口径 A M0–M4（λ=0.03）+ per-1SD；口径 B Lnode = log2(1+x) 标注
# ===========================================================================
.message("Cohort A M0–M4 with λ=0.03...")
# monkey-patch ridge inside apparent by reimplementing with lamA
m_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  d0 <- .npc_endpoint_df(dfA, endpoint = ep)
  rownames(d0) <- as.character(seq_len(nrow(d0)))
  if (!"traj_mid" %in% names(d0)) {
    tr <- as.character(d0$traj_risk)
    d0$traj_mid <- as.integer(tr %in% c("中危", "中"))
    d0$traj_high <- as.integer(tr %in% c("高危", "高"))
  }
  d0$ic_a <- as.integer(d0$ic_a %in% 1L); d0$immuno <- as.integer(d0$immuno %in% 1L)
  d0$ebv_pet <- as.numeric(d0$ebv_high) * as.numeric(d0$pet_high)
  specs <- list(
    M0 = c("age", "male", "t_ord", "n_ord", "ic_a", "immuno"),
    M1 = c("age", "male", "t_ord", "n_ord", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high"),
    M2 = c("age", "male", "t_ord", "n_ord", "ic_a", "immuno", "Lnode", "Ltlg", "Lntr"),
    M3 = c("age", "male", "t_ord", "n_ord", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high", "Lnode", "Ltlg", "Lntr"),
    M4 = c("age", "male", "t_ord", "n_ord", "ic_a", "immuno", "cum_trap", "t2_resid", "traj_mid", "traj_high", "Lnode", "Ltlg", "Lntr", "ebv_high", "pet_high", "ebv_pet")
  )
  for (h in horizons) {
    for (nm in names(specs)) {
      vars <- intersect(specs[[nm]], names(d0))
      mm <- tryCatch(model.matrix(as.formula(paste("~", paste(vars, collapse = "+"), "-1")), d0), error = function(e) NULL)
      if (is.null(mm) || nrow(mm) < 50) next
      keep <- as.integer(rownames(mm))
      ev <- if (ep %in% c("DM", "LR")) as.integer(d0$cause[keep] == 1L) else as.integer(d0$cause[keep] > 0)
      fit <- tryCatch(.npc_fit_ridge_cox(mm, Surv(d0$time[keep], ev), lambda = lamA), error = function(e) NULL)
      if (is.null(fit)) next
      lp <- .npc_predict_lp(fit, mm)
      met <- .npc_ipcw_auc(d0$time[keep], d0$cause[keep], lp, h)
      m_rows[[length(m_rows) + 1L]] <- data.frame(
        Cohort = "A", Endpoint = ep, Model = nm, Horizon_mo = h, N = length(keep),
        AUC = round(met$auc, 3), Brier = round(met$brier, 4), Lambda = lamA,
        stringsAsFactors = FALSE
      )
    }
  }
}
tab_m <- do.call(rbind, m_rows)
write_xlsx_simple(tab_m,
  file.path(tbl_dir, "Table S16. Cohort A M0-M4 apparent AUC.xlsx"),
  "Table S16. Cohort A M0–M4 apparent IPCW-AUC (IC+immuno in M0; ridge λ=0.03)")

# Table 4：明确 Lnode=log2(1+SUVmax) 每增加 1
.message("Table 4 HRs with log2(1+x) scale note...")
hr_rows <- list()
for (ep in endpoints5) {
  rr <- tryCatch(
    npc_ebv_pet_cause_specific_hr(dfB, endpoint = ep,
                                  vars = c("Lnode", "Lmtv", "Ltlg", "Lntr", "t0_pos", "t0_score")),
    error = function(e) NULL
  )
  if (!is.null(rr) && nrow(rr)) {
    rr$Scale <- ifelse(rr$variable %in% c("Lnode", "Lmtv", "Ltlg", "Lntr", "t0_score"),
                       "per 1 unit of log2(1+x) [cohort B nodal SUVmax scale]",
                       "as coded")
    rr$HR_CI <- mapply(fmt_hr, rr$HR, rr$lo, rr$hi)
    rr$P <- vapply(rr$p, fmt_p, character(1))
    hr_rows[[length(hr_rows) + 1L]] <- rr
  }
}
tab_hr <- do.call(rbind, hr_rows)
if (!is.null(tab_hr) && nrow(tab_hr)) {
  write_xlsx_simple(tab_hr[, c("endpoint", "variable", "Scale", "HR_CI", "P")],
    file.path(tbl_dir, "Table 4. Adjusted HRs for EBV and PET markers across endpoints.xlsx"),
    "Table 4. Age+Sex+T+N+year–adjusted cause-specific HRs; Lnode=log2(1+nodal SUVmax) per +1")
}

# ===========================================================================
# 4) 双向三终点 6 参数 LR（EBV简约+2PET；反向 PET+EBV）
# ===========================================================================
.message("Two-way three-endpoint parsimonious LR...")
lr_out <- list()
for (ep in c("OS", "PFS", "DM")) {
  d <- .npc_endpoint_df(dfA, ep)  # 报告：全队列样本内拟合
  d$age_z <- zscore(d$age); d$t0_z <- zscore(d$t0_score)
  d$Lmtv_z <- zscore(d$Lmtv); d$Lnode_z <- zscore(d$Lnode)
  ev <- if (ep == "DM") as.integer(d$cause == 1L) else as.integer(d$cause > 0)
  fit_ebv <- tryCatch(coxph(Surv(time, ev) ~ age_z + male + t_ord + n_ord + t0_z, data = d), error = function(e) NULL)
  fit_pet <- tryCatch(coxph(Surv(time, ev) ~ age_z + male + t_ord + n_ord + Lmtv_z + Lnode_z, data = d), error = function(e) NULL)
  fit_m6 <- tryCatch(coxph(Surv(time, ev) ~ age_z + male + t_ord + n_ord + t0_z + Lmtv_z + Lnode_z, data = d), error = function(e) NULL)
  if (!is.null(fit_ebv) && !is.null(fit_m6)) {
    a <- anova(fit_ebv, fit_m6, test = "LRT")
    lr_out[[length(lr_out) + 1L]] <- data.frame(
      Endpoint = ep, Comparison = "EBV-parsimonious + 2 PET vs EBV-parsimonious",
      LR = round(as.numeric(a$Chisq[2]), 3), df = as.numeric(a$Df[2]),
      P = as.numeric(a$`Pr(>|Chi|)`[2]), P_fmt = fmt_p(as.numeric(a$`Pr(>|Chi|)`[2])),
      stringsAsFactors = FALSE
    )
  }
  if (!is.null(fit_pet) && !is.null(fit_m6)) {
    a <- anova(fit_pet, fit_m6, test = "LRT")
    lr_out[[length(lr_out) + 1L]] <- data.frame(
      Endpoint = ep, Comparison = "PET-parsimonious + EBV vs PET-parsimonious (reverse)",
      LR = round(as.numeric(a$Chisq[2]), 3), df = as.numeric(a$Df[2]),
      P = as.numeric(a$`Pr(>|Chi|)`[2]), P_fmt = fmt_p(as.numeric(a$`Pr(>|Chi|)`[2])),
      stringsAsFactors = FALSE
    )
  }
}
tab_lr <- do.call(rbind, lr_out)
write_xlsx_simple(tab_lr,
  file.path(tbl_dir, "Table S11. Nested likelihood-ratio tests.xlsx"),
  "Table S11. Two-way parsimonious LR on cohort A (EBV+2PET vs reverse) for OS/PFS/DMFS")

# ===========================================================================
# 5) IC 双交互：对照 = 仅 T1 主效应 → 再加 T1×MTV + T1×Lnode（repeats=6）
# ===========================================================================
.message("IC double-interaction vs T1-main-only (repeats=%d)...", n_rep_ic)
ic <- dfB[(dfB$ic_a %in% 1L | dfB$ic %in% 1L) & is.finite(dfB$t1_score), , drop = FALSE]
rownames(ic) <- NULL
.message("  IC with T1 available n=%d", nrow(ic))
# 自定义变量：T1-only vs double-ix（均含临床）
vars_t1 <- c("age", "male", "t_ord", "n_ord", "t1_score")
# 为交互准备派生列
ic$t1_x_mtv <- as.numeric(ic$t1_score) * as.numeric(ic$Lmtv)
ic$t1_x_lnode <- as.numeric(ic$t1_score) * as.numeric(ic$Lnode)
vars_ix <- c("age", "male", "t_ord", "n_ord", "t1_score", "Lmtv", "Lnode", "t1_x_mtv", "t1_x_lnode")
# 也做「仅主效应 T1+MTV+Lnode」敏感性对照
oof_t1 <- tryCatch(
  npc_ebv_pet_oof_cv(ic, endpoint = "PFS", model = "C", n_repeats = n_rep_ic,
                     seed = 20261120L, horizon = 36, lambda = lamB, vars = vars_t1),
  error = function(e) NULL
)
oof_ix <- tryCatch(
  npc_ebv_pet_oof_cv(ic, endpoint = "PFS", model = "C", n_repeats = n_rep_ic,
                     seed = 20261120L, horizon = 36, lambda = lamB, vars = vars_ix),
  error = function(e) NULL
)
# 表观（报告叙述常用）对照：clinical+T1 vs +双交互
dIC <- .npc_endpoint_df(ic, "PFS")
dIC$t1_z <- zscore(dIC$t1_score); dIC$Lmtv_z <- zscore(dIC$Lmtv); dIC$Lnode_z <- zscore(dIC$Lnode)
dIC$age_z <- zscore(dIC$age)
evIC <- as.integer(dIC$cause > 0)
fit_t1only <- tryCatch(coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z, data = dIC), error = function(e) NULL)
fit_dbl <- tryCatch(
  coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z + Lmtv_z + Lnode_z + t1_z:Lmtv_z + t1_z:Lnode_z, data = dIC),
  error = function(e) NULL
)
ic_rows <- list()
if (!is.null(fit_t1only) && !is.null(fit_dbl)) {
  mf <- model.frame(fit_dbl); keep <- as.integer(rownames(mf))
  dICk <- dIC[keep, , drop = FALSE]
  lp0 <- predict(fit_t1only, newdata = dICk, type = "lp")
  lp1 <- predict(fit_dbl, newdata = dICk, type = "lp")
  a0 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp0, 36)
  a1 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp1, 36)
  set.seed(20261120L)
  dlt <- replicate(n_boot_pair, {
    ii <- sample.int(length(lp0), replace = TRUE)
    .npc_ipcw_auc(dICk$time[ii], dICk$cause[ii], lp1[ii], 36)$auc -
      .npc_ipcw_auc(dICk$time[ii], dICk$cause[ii], lp0[ii], 36)$auc
  })
  dlt <- dlt[is.finite(dlt)]
  lr <- anova(fit_t1only, fit_dbl, test = "LRT")
  sm <- summary(fit_dbl)$coefficients
  ix <- grep(":", rownames(sm), value = TRUE)
  ic_rows[[1]] <- data.frame(
    Block = "Apparent", N = length(keep),
    AUC_T1_main_only = round(a0$auc, 3),
    AUC_double_interaction = round(a1$auc, 3),
    Delta_AUC = round(a1$auc - a0$auc, 3),
    CI_lo = round(as.numeric(quantile(dlt, 0.025)), 3),
    CI_hi = round(as.numeric(quantile(dlt, 0.975)), 3),
    Brier_T1 = round(a0$brier, 4), Brier_ix = round(a1$brier, 4),
    LR_P = fmt_p(as.numeric(lr$`Pr(>|Chi|)`[2])),
    stringsAsFactors = FALSE
  )
  for (t in ix) {
    ic_rows[[length(ic_rows) + 1L]] <- data.frame(
      Block = "Interaction HR", N = length(keep),
      AUC_T1_main_only = NA, AUC_double_interaction = NA, Delta_AUC = NA,
      CI_lo = NA, CI_hi = NA, Brier_T1 = NA, Brier_ix = NA,
      LR_P = paste0(t, ": ", fmt_hr(exp(sm[t, "coef"]),
                                    exp(sm[t, "coef"] - 1.96 * sm[t, "se(coef)"]),
                                    exp(sm[t, "coef"] + 1.96 * sm[t, "se(coef)"])),
                    "; P=", fmt_p(sm[t, "Pr(>|z|)"])),
      stringsAsFactors = FALSE
    )
  }
}
if (!is.null(oof_t1) && !is.null(oof_ix)) {
  pd <- paired_delta_h(oof_t1, oof_ix, 36, n_boot_pair, 20261121L)
  ic_rows[[length(ic_rows) + 1L]] <- data.frame(
    Block = sprintf("OOF (%d repeats)", n_rep_ic), N = oof_t1$n,
    AUC_T1_main_only = round(pd$auc_ref, 3),
    AUC_double_interaction = round(pd$auc_new, 3),
    Delta_AUC = round(pd$delta, 3),
    CI_lo = round(pd$lo, 3), CI_hi = round(pd$hi, 3),
    Brier_T1 = round(pd$brier_ref, 4), Brier_ix = round(pd$brier_new, 4),
    LR_P = "OOF paired bootstrap", stringsAsFactors = FALSE
  )
}
tab_ic <- do.call(rbind, ic_rows)
write_xlsx_simple(tab_ic,
  file.path(tbl_dir, "Table S22. IC double interaction T1xMTV and T1xLnode.xlsx"),
  "Table S22. IC subcohort: T1-main-only vs T1×MTV + T1×nodal SUVmax (report contrast)")
write_xlsx_simple(tab_ic,
  file.path(tbl_dir, "Table S15. IC landmark T1xPET incremental AUC.xlsx"),
  "Table S15. IC T1 double-interaction incremental discrimination (aligned with S22)")

# ===========================================================================
# 6) 四象限（TLG>65|NTR>0.64）+ RERI
# ===========================================================================
.message("Quadrant HRs + RERI with report definitions...")
dQ <- .npc_endpoint_df(dfB, "DM")
dQ$eh <- as.integer(dQ$ebv_high %in% 1L)
dQ$ph <- as.integer(dQ$pet_high %in% 1L)
evQ <- as.integer(dQ$cause == 1L)
cnt <- as.data.frame(xtabs(~ eh + ph, data = dQ))
fit_q <- tryCatch(coxph(Surv(time, evQ) ~ eh + ph + eh:ph + age + male, data = dQ), error = function(e) NULL)
mk_rate <- function(e, p) {
  ii <- dQ$eh == e & dQ$ph == p
  c(n = sum(ii), events = sum(evQ[ii]), rate = mean(evQ[ii]))
}
r00 <- mk_rate(0, 0); r10 <- mk_rate(1, 0); r01 <- mk_rate(0, 1); r11 <- mk_rate(1, 1)
reri_risk <- as.numeric(r11["rate"] - r10["rate"] - r01["rate"] + r00["rate"])
q_tab <- data.frame(
  Stratum = c("EBV−/PET− (ref)", "EBV+/PET−", "EBV−/PET+", "EBV+/PET+"),
  N = c(r00["n"], r10["n"], r01["n"], r11["n"]),
  Events = c(r00["events"], r10["events"], r01["events"], r11["events"]),
  Crude_rate_pct = round(100 * c(r00["rate"], r10["rate"], r01["rate"], r11["rate"]), 1),
  HR_CI = "1 (Ref)", P = "—", stringsAsFactors = FALSE
)
reri_hr <- NA_real_
if (!is.null(fit_q)) {
  cf <- coef(fit_q); V <- vcov(fit_q); se <- sqrt(diag(V))
  b_e <- unname(cf["eh"]); b_p <- unname(cf["ph"]); b_x <- unname(cf["eh:ph"])
  s11 <- tryCatch(sqrt(V["eh", "eh"] + V["ph", "ph"] + V["eh:ph", "eh:ph"] +
                         2 * V["eh", "ph"] + 2 * V["eh", "eh:ph"] + 2 * V["ph", "eh:ph"]),
                  error = function(e) NA_real_)
  q_tab$HR_CI[2] <- fmt_hr(exp(b_e), exp(b_e - 1.96 * se["eh"]), exp(b_e + 1.96 * se["eh"]))
  q_tab$P[2] <- fmt_p(2 * pnorm(-abs(b_e / se["eh"])))
  q_tab$HR_CI[3] <- fmt_hr(exp(b_p), exp(b_p - 1.96 * se["ph"]), exp(b_p + 1.96 * se["ph"]))
  q_tab$P[3] <- fmt_p(2 * pnorm(-abs(b_p / se["ph"])))
  q_tab$HR_CI[4] <- fmt_hr(exp(b_e + b_p + b_x), exp(b_e + b_p + b_x - 1.96 * s11),
                           exp(b_e + b_p + b_x + 1.96 * s11))
  q_tab$P[4] <- fmt_p(2 * pnorm(-abs((b_e + b_p + b_x) / s11)))
  if (all(is.finite(c(b_e, b_p, b_x)))) reri_hr <- exp(b_e + b_p + b_x) - exp(b_e) - exp(b_p) + 1
}
q_tab <- rbind(q_tab,
  data.frame(Stratum = "RERI (risk difference)", N = NA, Events = NA, Crude_rate_pct = NA,
             HR_CI = sprintf("%.3f", reri_risk), P = "r11-r10-r01+r00", stringsAsFactors = FALSE),
  data.frame(Stratum = "RERI (HR scale)", N = NA, Events = NA, Crude_rate_pct = NA,
             HR_CI = if (is.finite(reri_hr)) sprintf("%.3f", reri_hr) else "NE",
             P = "HR11-HR10-HR01+1", stringsAsFactors = FALSE),
  data.frame(Stratum = "Definition", N = NA, Events = NA, Crude_rate_pct = NA,
             HR_CI = "PET high=TLG>65 or NTR>0.64; EBV high=T0 threshold / T2 residual / Persistent|Rebound",
             P = "", stringsAsFactors = FALSE)
)
write_xlsx_simple(q_tab,
  file.path(tbl_dir, "Table S5. EBV PET RERI for distant metastasis.xlsx"),
  "Table S5. Report-definition EBV×PET quadrant rates/HRs and additive RERI")

# MTV×SUVmax 中位交叉保留
dQ$mtv_hi <- as.integer(dQ$Lmtv >= median(dQ$Lmtv, na.rm = TRUE))
dQ$suv_hi <- as.integer(dQ$Lnode >= median(dQ$Lnode, na.rm = TRUE))
dQ$cross <- factor(paste0("MTV", dQ$mtv_hi, "_SUV", dQ$suv_hi),
                   levels = c("MTV0_SUV0", "MTV1_SUV0", "MTV0_SUV1", "MTV1_SUV1"))
fit_x <- tryCatch(coxph(Surv(time, evQ) ~ cross + age + male, data = dQ), error = function(e) NULL)
if (!is.null(fit_x)) {
  x_rows <- list()
  for (lv in levels(dQ$cross)[-1]) {
    rr <- cox_hr_row(fit_x, paste0("cross", lv))
    if (!is.null(rr)) {
      rr$Stratum <- lv; rr$HR_CI <- fmt_hr(rr$HR, rr$lo, rr$hi); rr$P <- fmt_p(rr$p)
      x_rows[[length(x_rows) + 1L]] <- rr
    }
  }
  if (length(x_rows)) {
    write_xlsx_simple(do.call(rbind, x_rows)[, c("Stratum", "HR_CI", "P")],
      file.path(tbl_dir, "Table S24. MTV SUVmax median cross-strata HRs.xlsx"),
      "Table S24. MTV × nodal SUVmax median cross-strata HRs (Age+Sex)")
  }
}

# ===========================================================================
# 7) 9 月轨迹增量协议：参照=临床+T0+双PET+IC；OOF 岭；1000 配对；6/12 月
# ===========================================================================
.message("Landmark trajectory OOF protocol (1000 paired)...")
lm_rows <- list()
for (lm in c(6L, 9L, 12L)) {
  lm_col <- paste0("lm", lm)
  dL0 <- dfB
  if (lm_col %in% names(dL0)) {
    dL0 <- dL0[as.integer(dL0[[lm_col]]) == 1L | (is.finite(dL0$os_time) & dL0$os_time >= lm), , drop = FALSE]
  } else {
    dL0 <- dL0[is.finite(dL0$os_time) & dL0$os_time >= lm, , drop = FALSE]
  }
  # 有 T2
  dL0 <- dL0[is.finite(dL0$t2_score), , drop = FALSE]
  # 尚无目标事件/竞争死亡于界标前（用原因特异状态）
  dL0 <- dL0[is.finite(dL0$dm_time) & dL0$dm_time >= lm, , drop = FALSE]
  rownames(dL0) <- NULL
  # oof_cv 会重建 time：预先把各终点时间平移到界标后
  for (tc in c("os_time", "pfs_time", "dm_time", "dmd_time", "lr_time")) {
    if (tc %in% names(dL0)) dL0[[tc]] <- pmax(as.numeric(dL0[[tc]]) - lm, 0.01)
  }
  dL0$ic_a <- as.integer(dL0$ic_a %in% 1L)
  tr <- as.character(dL0$traj_risk)
  dL0$traj_mid <- as.integer(tr %in% c("中危", "中"))
  dL0$traj_high <- as.integer(tr %in% c("高危", "高"))
  vars_ref <- c("age", "male", "t_ord", "n_ord", "t0_score", "Lmtv", "Lnode", "ic_a")
  vars_tr <- c(vars_ref, "traj_mid", "traj_high")
  oof_ref <- tryCatch(
    npc_ebv_pet_oof_cv(dL0, endpoint = "DM", model = "C", n_repeats = n_rep_main,
                       seed = 20261122L + lm, horizon = 36, lambda = lamB, vars = vars_ref),
    error = function(e) NULL
  )
  oof_tr <- tryCatch(
    npc_ebv_pet_oof_cv(dL0, endpoint = "DM", model = "C", n_repeats = n_rep_main,
                       seed = 20261122L + lm, horizon = 36, lambda = lamB, vars = vars_tr),
    error = function(e) NULL
  )
  if (is.null(oof_ref) || is.null(oof_tr)) next
  pd <- paired_delta_h(oof_ref, oof_tr, 36, n_boot_lm, 20261122L + lm * 3L)
  lm_rows[[length(lm_rows) + 1L]] <- data.frame(
    Landmark_mo = lm, Endpoint = "DM", N = oof_ref$n, Events = oof_ref$n_event,
    AUC_ref = round(pd$auc_ref, 3), AUC_plus_traj = round(pd$auc_new, 3),
    Delta_AUC = round(pd$delta, 3), CI_lo = round(pd$lo, 3), CI_hi = round(pd$hi, 3),
    Brier_ref = round(pd$brier_ref, 4), Brier_plus = round(pd$brier_new, 4),
    Delta_Brier = round(pd$brier_new - pd$brier_ref, 4),
    n_boot = pd$n_boot,
    Ref_model = "Age Sex T N T0 MTV Lnode IC",
    stringsAsFactors = FALSE
  )
}
tab_lm <- do.call(rbind, lm_rows)
write_xlsx_simple(tab_lm,
  file.path(tbl_dir, "Table 5. Landmark trajectory T2 incremental AUC.xlsx"),
  sprintf("Table 5. Landmark trajectory incremental AUC (ref=clinical+T0+PET2+IC; OOF ridge λ=5; %d paired)", n_boot_lm))

# ===========================================================================
# 8) 界标 T2 五终点 ΔAUC（U 模型：参照 vs +T2）
# ===========================================================================
.message("Landmark T2 five-endpoint ΔAUC (U family)...")
t2_rows <- list()
u_rows <- list()
for (ep in endpoints5) {
  dL0 <- dfB[as.integer(dfB$lm9) == 1L & is.finite(dfB$t2_score), , drop = FALSE]
  # 按终点过滤界标前已发生者
  tcol <- switch(ep, OS = "os_time", PFS = "pfs_time", DM = "dm_time", `DM+D` = "dmd_time", LR = "lr_time")
  dL0 <- dL0[is.finite(dL0[[tcol]]) & dL0[[tcol]] >= 9, , drop = FALSE]
  rownames(dL0) <- NULL
  for (tc in c("os_time", "pfs_time", "dm_time", "dmd_time", "lr_time")) {
    if (tc %in% names(dL0)) dL0[[tc]] <- pmax(as.numeric(dL0[[tc]]) - 9, 0.01)
  }
  dL0$ic_a <- as.integer(dL0$ic_a %in% 1L)
  vars_u0 <- c("age", "male", "t_ord", "n_ord", "t0_score", "Lmtv", "Lnode", "ic_a")
  vars_u <- c(vars_u0, "t2_score")                 # U: +T2
  o0 <- tryCatch(npc_ebv_pet_oof_cv(dL0, ep, "C", n_rep_main, 5L, 20261123L, 36, lamB, vars_u0), error = function(e) NULL)
  oU <- tryCatch(npc_ebv_pet_oof_cv(dL0, ep, "C", n_rep_main, 5L, 20261123L, 36, lamB, vars_u), error = function(e) NULL)
  if (is.null(o0) || is.null(oU)) next
  pd <- paired_delta_h(o0, oU, 36, n_boot_pair, 20261123L + match(ep, endpoints5))
  t2_rows[[length(t2_rows) + 1L]] <- data.frame(
    Model_family = "U", Landmark_mo = 9, Endpoint = ep, N = o0$n, Events = o0$n_event,
    AUC_ref = round(pd$auc_ref, 3), AUC_plus_T2 = round(pd$auc_new, 3),
    Delta_AUC = round(pd$delta, 3), CI_lo = round(pd$lo, 3), CI_hi = round(pd$hi, 3),
    stringsAsFactors = FALSE
  )
  u_rows[[length(u_rows) + 1L]] <- data.frame(
    Family = "U", Endpoint = ep, Description = "9-mo landmark + T2 vs clinical+T0+PET2+IC",
    AUC_ref = round(pd$auc_ref, 3), AUC_new = round(pd$auc_new, 3),
    Delta = round(pd$delta, 3), stringsAsFactors = FALSE
  )
}
# IUX = IC 双交互（上面 S22 OOF 行）
if (!is.null(oof_t1) && !is.null(oof_ix)) {
  pd <- paired_delta_h(oof_t1, oof_ix, 36, n_boot_pair, 20261124L)
  u_rows[[length(u_rows) + 1L]] <- data.frame(
    Family = "IUX", Endpoint = "PFS",
    Description = "IC subcohort: T1-main-only vs T1×MTV+T1×Lnode",
    AUC_ref = round(pd$auc_ref, 3), AUC_new = round(pd$auc_new, 3),
    Delta = round(pd$delta, 3), stringsAsFactors = FALSE
  )
  u_rows[[length(u_rows) + 1L]] <- data.frame(
    Family = "UP2", Endpoint = "DM",
    Description = "9-mo landmark base already includes PET2; UP2≡U with PET2 retained",
    AUC_ref = NA_real_, AUC_new = NA_real_, Delta = NA_real_, stringsAsFactors = FALSE
  )
}
tab_t2 <- do.call(rbind, t2_rows)
write_xlsx_simple(tab_t2,
  file.path(tbl_dir, "Table S29. Landmark T2 five-endpoint delta AUC.xlsx"),
  "Table S29. 9-month landmark +T2 incremental AUC across five endpoints (U family)")
tab_u <- do.call(rbind, u_rows)
write_xlsx_simple(tab_u,
  file.path(tbl_dir, "Table S30. Landmark IC model family U UP2 IUX.xlsx"),
  "Table S30. Appendix-B model family U / UP2 / IUX summary")

# ===========================================================================
# 9) 年代留出校准
# ===========================================================================
.message("Temporal holdout calibration...")
train <- dfB[dfB$dx_year <= 2022, , drop = FALSE]
test <- dfB[dfB$dx_year >= 2023, , drop = FALSE]
rownames(train) <- NULL; rownames(test) <- NULL
hold_rows <- list()
cal_hold <- NULL
for (md in c("C", "E", "P2", "EP2")) {
  dtr <- .npc_endpoint_df(train, "DM"); dte <- .npc_endpoint_df(test, "DM")
  rownames(dtr) <- as.character(seq_len(nrow(dtr)))
  rownames(dte) <- as.character(seq_len(nrow(dte)))
  mm_tr <- tryCatch(.npc_design_matrix(dtr, .npc_model_vars(md)), error = function(e) NULL)
  mm_te <- tryCatch(.npc_design_matrix(dte, .npc_model_vars(md)), error = function(e) NULL)
  if (is.null(mm_tr) || is.null(mm_te)) next
  # 对齐列
  cols <- intersect(colnames(mm_tr), colnames(mm_te))
  if (!length(cols)) next
  xtr <- mm_tr[, cols, drop = FALSE]; xte <- mm_te[, cols, drop = FALSE]
  ktr <- as.integer(rownames(xtr)); kte <- as.integer(rownames(xte))
  ev <- as.integer(dtr$cause[ktr] == 1L)
  fit <- tryCatch(.npc_fit_ridge_cox(xtr, Surv(dtr$time[ktr], ev), lambda = lamB), error = function(e) NULL)
  if (is.null(fit)) next
  lp <- .npc_predict_lp(fit, xte)
  met <- .npc_ipcw_auc(dte$time[kte], dte$cause[kte], lp, 36)
  hold_rows[[length(hold_rows) + 1L]] <- data.frame(
    Model = md, N_train = length(ktr), N_test = length(kte),
    Events_test = sum(dte$cause[kte] == 1L), AUC = round(met$auc, 3), Brier = round(met$brier, 4),
    stringsAsFactors = FALSE
  )
  if (md == "EP2") {
    # 校准：预测 vs 观察（检验集）
    sf <- survfit(Surv(dtr$time[ktr], ev) ~ 1)
    s0 <- approx(sf$time, sf$surv, xout = 36, rule = 2, yleft = 1, yright = min(sf$surv))$y
    risk <- 1 - s0^exp(lp - mean(lp, na.rm = TRUE))
    obs <- as.integer(dte$cause[kte] == 1L & dte$time[kte] <= 36)
    cal_hold <- data.frame(
      Set = c("Holdout overall", "Holdout Q1", "Holdout Q2", "Holdout Q3", "Holdout Q4"),
      N = c(length(risk), NA, NA, NA, NA),
      Predicted_pct = round(100 * c(mean(risk), NA, NA, NA, NA), 1),
      Observed_pct = round(100 * c(mean(obs), NA, NA, NA, NA), 1),
      stringsAsFactors = FALSE
    )
    q <- cut(risk, breaks = quantile(risk, probs = seq(0, 1, 0.25), na.rm = TRUE),
             include.lowest = TRUE, labels = paste0("Q", 1:4))
    for (qi in 1:4) {
      ii <- which(q == paste0("Q", qi))
      cal_hold$N[qi + 1L] <- length(ii)
      cal_hold$Predicted_pct[qi + 1L] <- round(100 * mean(risk[ii]), 1)
      cal_hold$Observed_pct[qi + 1L] <- round(100 * mean(obs[ii]), 1)
    }
  }
}
write_xlsx_simple(do.call(rbind, hold_rows),
  file.path(tbl_dir, "Table S3. Temporal holdout DM AUC.xlsx"),
  "Table S3. Temporal holdout (train ≤2022 / test 2023–2025) DM 36-month AUC")
if (!is.null(cal_hold)) {
  # 全队列 EP2 OOF 校准四分位一并
  oof_ep2 <- oof_store[["DM_EP2"]]
  if (!is.null(oof_ep2)) {
    lp <- oof_ep2$lp; tm <- oof_ep2$time; cs <- oof_ep2$cause
    ok <- is.finite(lp) & is.finite(tm)
    ev <- as.integer(cs[ok] == 1L)
    sf <- survfit(Surv(tm[ok], ev) ~ 1)
    s0 <- approx(sf$time, sf$surv, xout = 36, rule = 2, yleft = 1, yright = min(sf$surv))$y
    risk <- 1 - s0^exp(lp[ok] - mean(lp[ok], na.rm = TRUE))
    obs <- as.integer(cs[ok] == 1L & tm[ok] <= 36)
    q <- cut(risk, breaks = quantile(risk, probs = seq(0, 1, 0.25), na.rm = TRUE),
             include.lowest = TRUE, labels = paste0("Q", 1:4))
    cal_full <- data.frame(
      Set = c("Full-cohort OOF overall", paste0("Full-cohort OOF Q", 1:4)),
      N = c(sum(ok), as.integer(table(q))),
      Predicted_pct = round(100 * c(mean(risk), tapply(risk, q, mean)), 1),
      Observed_pct = round(100 * c(mean(obs), tapply(obs, q, mean)), 1),
      stringsAsFactors = FALSE
    )
    cal_all <- rbind(cal_full, cal_hold)
  } else cal_all <- cal_hold
  write_xlsx_simple(cal_all,
    file.path(tbl_dir, "Table S25. EP2 calibration quartiles at 36 months.xlsx"),
    "Table S25. EP2 calibration: full-cohort OOF quartiles + temporal-holdout predicted vs observed")
  write_xlsx_simple(cal_hold,
    file.path(tbl_dir, "Table S31. Temporal holdout calibration.xlsx"),
    "Table S31. Temporal holdout EP2 36-month calibration (predicted vs observed)")
}

# ===========================================================================
# 10) 生物复发日期规则
# ===========================================================================
.message("Biological relapse with date rules...")
diag <- dfB
diag$bio <- as.integer(diag$bio_relapse %in% 1L | diag$BioRelapse %in% 1L)
diag$clin <- as.integer(diag$pfs_event %in% 1L)
# 报告：缺日期；日期 ≥ PFS 事件日 → 不计入提前/诊断配对
has_date <- is.finite(diag$bio_time)
late_or_eq <- has_date & is.finite(diag$pfs_time) & diag$bio_time >= diag$pfs_time
# 诊断指标：有日期且不晚于临床进展者，作为「有效生物学阳性」；无日期的生物+单独计数
bio_valid <- diag$bio == 1L & has_date & !late_or_eq
bio_invalid_date <- diag$bio == 1L & (!has_date | late_or_eq)
# 以有效生物+ 对临床进展
tp <- sum(bio_valid & diag$clin == 1L)
fp <- sum(bio_valid & diag$clin == 0L)
# 阴性：非生物，或生物但无效日期（不作为阳性检测）
pred_pos <- bio_valid
fn <- sum(!pred_pos & diag$clin == 1L)
tn <- sum(!pred_pos & diag$clin == 0L)
sens <- tp / (tp + fn); spec <- tn / (tn + fp)
ppv <- tp / (tp + fp); npv <- tn / (tn + fn)
lead <- (diag$pfs_time - diag$bio_time)[bio_valid & diag$clin == 1L & is.finite(diag$pfs_time)]
lead_pos <- lead[is.finite(lead) & lead > 0]
# 12 月界标 HR：仅用有效日期生物标记
lm12 <- diag[is.finite(diag$dm_time) & diag$dm_time >= 12, , drop = FALSE]
lm12$time_lm <- pmax(lm12$dm_time - 12, 0.01)
lm12$ev <- as.integer(lm12$pfs_event == 1L)  # 报告写后续 PFS
lm12$bio_v <- as.integer(lm12$bio == 1L & is.finite(lm12$bio_time) & lm12$bio_time < 12)
fit_bio <- tryCatch(coxph(Surv(time_lm, ev) ~ bio_v + age + male, data = lm12), error = function(e) NULL)
bio_hr <- if (!is.null(fit_bio)) cox_hr_row(fit_bio, "bio_v") else NULL
tab_bio <- data.frame(
  Metric = c(
    "N", "BioRelapse+", "Bio+ missing date", "Bio+ date >= PFS (excluded)",
    "Bio+ valid for diagnostics", "Clinical progression+",
    "TP", "FP", "FN", "TN",
    "Sensitivity", "Specificity", "PPV", "NPV",
    "Lead_time_median_days (valid early pairs)", "Lead_time_IQR_days",
    "Landmark12_HR_valid_bio_vs_neg"
  ),
  Value = c(
    nrow(diag), sum(diag$bio == 1L), sum(diag$bio == 1L & !has_date),
    sum(diag$bio == 1L & late_or_eq, na.rm = TRUE),
    sum(bio_valid), sum(diag$clin == 1L),
    tp, fp, fn, tn,
    sprintf("%.3f", sens), sprintf("%.3f", spec), sprintf("%.3f", ppv), sprintf("%.3f", npv),
    if (length(lead_pos)) sprintf("%.1f", median(lead_pos) * 30.4375) else "NE",
    if (length(lead_pos) >= 4) sprintf("%.1f–%.1f", quantile(lead_pos, .25) * 30.4375, quantile(lead_pos, .75) * 30.4375) else "NE",
    if (!is.null(bio_hr)) fmt_hr(bio_hr$HR, bio_hr$lo, bio_hr$hi) else "NE"
  ),
  stringsAsFactors = FALSE
)
write_xlsx_simple(tab_bio,
  file.path(tbl_dir, "Table S23. Biological relapse diagnostic performance.xlsx"),
  "Table S23. Biological relapse diagnostics with date rules (exclude missing date / date≥PFS)")

# ===========================================================================
# 11) Methods / NUMBERING
# ===========================================================================
methods <- c(
  "# Statistical analysis (spec-aligned recomputation)",
  "",
  "## Penalty",
  "Cohort A ridge λ = 0.03; cohort B ridge λ = 5 (report form 5×Σβ_std²/2 under glmnet standardize).",
  "",
  "## Nested discrimination",
  sprintf("Five endpoints (OS/PFS/DM/DM+D/LR) × models C/E/P2/P6/EP2/EP6/EP2X; repeated event-stratified 5-fold OOF (%d repeats); IPCW AUC/Brier at 24 and 36 months.", n_rep_main),
  "",
  "## Uncertainty",
  sprintf("Paired patient bootstrap on fixed OOF linear predictors (%d for main ΔAUC; %d for landmark trajectory); IPCW censoring weights re-estimated each resample. Optimism-corrected Harrell C uses %d full-refit bootstraps.", n_boot_pair, n_boot_lm, n_boot_c),
  "",
  "## Interactions / landmarks / IC",
  "Quadrants: PET high = TLG>65 or NTR>0.64; EBV high = T0 threshold / T2 residual / Persistent|Rebound. Landmark trajectory ref = Age+Sex+T+N+T0+MTV+Lnode+IC, then + mid/high trajectory (6/9/12 mo). IC contrast = T1-main-only → + T1×MTV + T1×Lnode (IUX). U/UP2/IUX tabulated.",
  "",
  "## Association scale",
  "Cohort B nodal SUVmax enters as log2(1+x); HR per +1 on that scale.",
  "",
  "## Biological relapse",
  "Diagnostics exclude missing bio dates and dates ≥ clinical PFS time before Sens/Spec/lead-time; 12-month landmark HR uses valid bio markers only.",
  "",
  "## Note",
  "All estimates recomputed from case-level data; headline digits are not forced to match the prior report."
)
writeLines(methods, file.path(out_root, "Methods_statistical_analysis.md"), useBytes = TRUE)

num <- c(
  "# Numbering (spec-aligned)",
  "- Table 1 baseline; Table 2 five-endpoint×C–EP6 24/36 AUC; Table 3 paired ΔAUC; Table 4 log2 HRs; Table 5 landmark trajectory",
  "- S3 holdout AUC; S5 quadrant/RERI; S11 two-way LR; S15/S22 IC T1-main-only contrast; S16 A M0–M4 λ=0.03",
  "- S19 optimism C; S23 bio date rules; S24 MTV×SUV; S25/S31 calibration (+holdout); S29 T2 five-endpoint; S30 U/UP2/IUX"
)
writeLines(num, file.path(out_root, "NUMBERING_AND_ROLE.md"), useBytes = TRUE)

.message("DONE spec-align → %s", out_root)
