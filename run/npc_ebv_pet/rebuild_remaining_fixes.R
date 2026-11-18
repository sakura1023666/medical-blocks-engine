#!/usr/bin/env Rscript
# 剩余收口（绝对守则：数据真实性——不凑报告人数/效应量）
# - 重画 Fig9/10（读最新 Table2）
# - IC：可复现完整病例（诚实 n，不硬凑 287）+ leave-one-out
# - 四象限：工作簿同源定义（真实 65/27/165/134；报告 65/28/173/146 仅脚注）
# - 留出多终点 ΔAUC；PET 逐项 BH；IC 交互 q；UP2 独立模型
# - M0 用 Stage；6 参数 LP 重算风险分；Breslow 已在引擎强制
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
n_rep <- as.integer(.get_arg("--repeats", "6"))
n_boot <- as.integer(.get_arg("--boot", "400"))
if ("--quick" %in% args) { n_rep <- 2L; n_boot <- 80L }

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
  if (file.exists(path)) unlink(path)
  opened <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    ok <- tryCatch({
      grDevices::cairo_pdf(path, width = w, height = h, family = "Times New Roman")
      TRUE
    }, error = function(e) FALSE)
    opened <- isTRUE(ok)
  }
  if (!opened) grDevices::pdf(path, width = w, height = h, family = "Times", useDingbats = FALSE)
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

lamA <- npc_ebv_pet_penalty_lambda("A")
lamB <- npc_ebv_pet_penalty_lambda("B")

.message("Reading...")
raw <- npc_ebv_pet_read_analysis_df(workbook)
rownames(raw) <- NULL
dfA <- raw
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
rownames(dfB) <- NULL
.message("B=%d | quadrant=%s | ebv_high=%d pet_high=%d | stage_num finite=%d",
         nrow(dfB),
         paste(sprintf("%s=%d", names(table(dfB$quadrant)), as.integer(table(dfB$quadrant))), collapse=", "),
         sum(dfB$ebv_high == 1, na.rm = TRUE), sum(dfB$pet_high == 1, na.rm = TRUE),
         sum(is.finite(dfB$stage_num)))

# ===========================================================================
# 1) 重画 Fig9 / Fig10（读最新 Table2；不编造数字）
# ===========================================================================
.message("Redraw Fig9/Fig10 from latest Table 2...")
t2_path <- file.path(tbl_dir, "Table 2. Nested models 24-36 month IPCW-AUC across endpoints.xlsx")
t2 <- read.xlsx(t2_path, startRow = 2)
# robust rename
nm <- names(t2)
# expected after title row: Endpoint Model Horizon N Events AUC Brier Lambda Repeats
if (ncol(t2) >= 7) {
  names(t2)[1:7] <- c("Endpoint", "Model", "Horizon_mo", "N", "Events", "AUC", "Brier")
}
t2$Horizon_mo <- as.integer(t2$Horizon_mo)
t2$AUC <- as.numeric(t2$AUC)
t2$Model <- factor(t2$Model, levels = c("C", "E", "P2", "P6", "EP2", "EP6", "EP2X"))
t2$Endpoint <- factor(t2$Endpoint, levels = c("OS", "PFS", "DM", "DM+D", "LR"))

t2_36 <- t2[!is.na(t2$Endpoint) & t2$Horizon_mo == 36, ]
t2_dm <- t2_36[t2_36$Endpoint == "DM", ]

# Fig9: DM nested AUC bars + paired gains annotation from Table3 if present
t3 <- tryCatch(read.xlsx(file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC.xlsx"), startRow = 2), error = function(e) NULL)
save_pdf(file.path(fig_dir, "Figure 9. Distant-metastasis nested AUC and paired gains.pdf"), {
  p <- ggplot(t2_dm, aes(Model, AUC, fill = Model)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    geom_text(aes(label = sprintf("%.3f", AUC)), vjust = -0.35, size = 3.2, family = font_family) +
    coord_cartesian(ylim = c(0.55, max(t2_dm$AUC, na.rm = TRUE) + 0.08)) +
    labs(title = "Distant-metastasis 36-month OOF IPCW-AUC",
         subtitle = "Models C / E / P2 / P6 / EP2 / EP6 / EP2X (cohort B, ridge λ=5, 8 repeats)",
         y = "IPCW-AUC", x = NULL) +
    theme(plot.title = element_text(face = "bold"))
  print(p)
}, w = 8, h = 5)
write_md("Figure 9. Distant-metastasis nested AUC and paired gains",
         paste0("远处转移 36 月折外 IPCW-AUC（读自最新 Table 2）：",
                paste(sprintf("%s=%.3f", t2_dm$Model, t2_dm$AUC), collapse = "；"), "。"),
         sprintf("队列 B；岭回归 λ=5；Breslow；模型含 P6/EP6/EP2X。数字来自 %s。", basename(t2_path)))

# Fig10 heatmap five endpoints × seven models
fig10_name <- "Figure 10. Five-endpoint seven-model OOF AUC heatmap.pdf"
# remove old six-model file
old10 <- file.path(fig_dir, "Figure 10. Five-endpoint six-model OOF AUC heatmap.pdf")
if (file.exists(old10)) unlink(old10)
old10md <- file.path(md_dir, "Figure 10. Five-endpoint six-model OOF AUC heatmap.md")
if (file.exists(old10md)) unlink(old10md)

save_pdf(file.path(fig_dir, fig10_name), {
  print(
    ggplot(t2_36, aes(Model, Endpoint, fill = AUC)) +
      geom_tile(color = "white", linewidth = 0.5) +
      geom_text(aes(label = sprintf("%.3f", AUC)), size = 3, family = font_family) +
      scale_fill_gradient(low = "#f7fbff", high = "#08306b",
                          limits = c(0.5, max(0.9, max(t2_36$AUC, na.rm = TRUE)))) +
      labs(title = "Five-endpoint × seven-model 36-month OOF AUC",
           subtitle = "OS / PFS / DM / DM+D / LR × C–EP6 / EP2X",
           x = NULL, y = NULL) +
      theme(plot.title = element_text(face = "bold"), panel.grid = element_blank())
  )
}, w = 9, h = 4.8)
write_md(gsub("\\.pdf$", "", fig10_name),
         paste0("五终点×七模型 36 月折外 AUC 热图（含 P6/EP6/EP2X），单元格数字与最新 Table 2 一致。"),
         "队列 B；OOF 岭回归 λ=5；Breslow 结点。")

# ===========================================================================
# 2) 口径 A M0–M4（Stage）重算
# ===========================================================================
.message("Cohort A M0–M4 with Stage...")
m_rows <- list()
for (ep in c("DM", "PFS", "OS")) {
  rr <- tryCatch(npc_ebv_pet_m01234_apparent(dfA, endpoint = ep, horizon = 36), error = function(e) NULL)
  if (!is.null(rr) && nrow(rr)) {
    rr$Horizon_mo <- 36L; rr$Lambda <- lamA; rr$Stage_coding <- "stage_num (AJCC I–IVA)"
    m_rows[[length(m_rows) + 1L]] <- rr
  }
}
if (length(m_rows)) {
  write_xlsx_simple(do.call(rbind, m_rows),
    file.path(tbl_dir, "Table S16. Cohort A M0-M4 apparent AUC.xlsx"),
    "Table S16. Cohort A M0–M4 (Age+Sex+Stage+IC+immuno; ridge λ=0.03)")
}

# ===========================================================================
# 3) IC 诚实 n + leave-one-out + 交互 BH q
# ===========================================================================
.message("IC authentic cohort + LOO + BH q...")
# 诚实定义：IC 且 T1 记录非缺失且 t1_score 有限且 MTV/Lnode 完整
ic <- dfB[
  (dfB$ic_a %in% 1L | dfB$ic_code %in% 1L) &
    is.finite(dfB$t1_score) &
    !is.na(dfB$t1_kind) & !grepl("MISSING|缺失", as.character(dfB$t1_kind), ignore.case = TRUE) &
    is.finite(dfB$Lmtv) & is.finite(dfB$Lnode),
  , drop = FALSE
]
rownames(ic) <- NULL
.message("IC analysis n=%d (NOT forced to report 287)", nrow(ic))

dIC <- .npc_endpoint_df(ic, "PFS")
dIC$age_z <- zscore(dIC$age); dIC$t1_z <- zscore(dIC$t1_score)
dIC$Lmtv_z <- zscore(dIC$Lmtv); dIC$Lnode_z <- zscore(dIC$Lnode)
evIC <- as.integer(dIC$cause > 0)
fit_t1 <- coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z, data = dIC)
fit_ix <- coxph(Surv(time, evIC) ~ age_z + male + t_ord + n_ord + t1_z + Lmtv_z + Lnode_z +
                  t1_z:Lmtv_z + t1_z:Lnode_z, data = dIC)
mf <- model.frame(fit_ix); keep <- as.integer(rownames(mf))
dICk <- dIC[keep, , drop = FALSE]
lp0 <- predict(fit_t1, newdata = dICk, type = "lp")
lp1 <- predict(fit_ix, newdata = dICk, type = "lp")
a0 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp0, 36)
a1 <- .npc_ipcw_auc(dICk$time, dICk$cause, lp1, 36)
sm <- summary(fit_ix)$coefficients
ix <- grep(":", rownames(sm), value = TRUE)
ix_p <- sm[ix, "Pr(>|z|)"]
ix_q <- p.adjust(ix_p, method = "BH")
ic_sum <- data.frame(
  Item = c("N_IC_T1_complete", "Note_vs_report_287",
           "AUC_T1_main_only", "AUC_double_interaction", "Delta_AUC",
           paste0("HR_", ix), paste0("P_", ix), paste0("q_BH_", ix)),
  Value = c(
    nrow(ic),
    "Report cited 287; recomputed complete IC+T1+PET cases = this N (not forced)",
    sprintf("%.3f", a0$auc), sprintf("%.3f", a1$auc), sprintf("%.3f", a1$auc - a0$auc),
    vapply(ix, function(t) fmt_hr(exp(sm[t, "coef"]),
                                  exp(sm[t, "coef"] - 1.96 * sm[t, "se(coef)"]),
                                  exp(sm[t, "coef"] + 1.96 * sm[t, "se(coef)"])), character(1)),
    vapply(ix_p, fmt_p, character(1)),
    vapply(ix_q, fmt_p, character(1))
  ),
  stringsAsFactors = FALSE
)
write_xlsx_simple(ic_sum,
  file.path(tbl_dir, "Table S22. IC double interaction T1xMTV and T1xLnode.xlsx"),
  sprintf("Table S22. IC T1-main-only vs double interaction (authentic N=%d; BH q for interactions)", nrow(ic)))
write_xlsx_simple(ic_sum,
  file.path(tbl_dir, "Table S15. IC landmark T1xPET incremental AUC.xlsx"),
  "Table S15. Same as S22 (IC T1 contrast)")

# Leave-one-out：T1 达阈且 PFS 事件者逐一删除（真实命中数，不凑 6）
loo_ids <- which(ic$t1_pos == 1L & ic$pfs_event == 1L)
.message("LOO candidates T1+ & PFS event: %d", length(loo_ids))
loo_rows <- list()
base_delta <- a1$auc - a0$auc
loo_rows[[1]] <- data.frame(Dropped = "none (full IC set)", N = nrow(ic),
                            AUC_T1 = round(a0$auc, 3), AUC_ix = round(a1$auc, 3),
                            Delta = round(base_delta, 3), stringsAsFactors = FALSE)
for (j in loo_ids) {
  ic2 <- ic[-j, , drop = FALSE]
  d2 <- .npc_endpoint_df(ic2, "PFS")
  d2$age_z <- zscore(d2$age); d2$t1_z <- zscore(d2$t1_score)
  d2$Lmtv_z <- zscore(d2$Lmtv); d2$Lnode_z <- zscore(d2$Lnode)
  ev2 <- as.integer(d2$cause > 0)
  f0 <- tryCatch(coxph(Surv(time, ev2) ~ age_z + male + t_ord + n_ord + t1_z, data = d2), error = function(e) NULL)
  f1 <- tryCatch(coxph(Surv(time, ev2) ~ age_z + male + t_ord + n_ord + t1_z + Lmtv_z + Lnode_z +
                         t1_z:Lmtv_z + t1_z:Lnode_z, data = d2), error = function(e) NULL)
  if (is.null(f0) || is.null(f1)) next
  kk <- as.integer(rownames(model.frame(f1)))
  d2k <- d2[kk, , drop = FALSE]
  p0 <- predict(f0, newdata = d2k, type = "lp"); p1 <- predict(f1, newdata = d2k, type = "lp")
  m0 <- .npc_ipcw_auc(d2k$time, d2k$cause, p0, 36)
  m1 <- .npc_ipcw_auc(d2k$time, d2k$cause, p1, 36)
  loo_rows[[length(loo_rows) + 1L]] <- data.frame(
    Dropped = sprintf("PID=%s (T1+ & PFS)", as.character(ic$PID[j])),
    N = nrow(ic2), AUC_T1 = round(m0$auc, 3), AUC_ix = round(m1$auc, 3),
    Delta = round(m1$auc - m0$auc, 3), stringsAsFactors = FALSE
  )
}
tab_loo <- do.call(rbind, loo_rows)
write_xlsx_simple(tab_loo,
  file.path(tbl_dir, "Table S32. IC leave-one-out T1-positive PFS cases.xlsx"),
  sprintf("Table S32. Leave-one-out deleting each T1-threshold & PFS case (n_candidates=%d; not forced to 6)", length(loo_ids)))

# ===========================================================================
# 4) 四象限脚注（真实人数）+ PET 逐项 BH
# ===========================================================================
.message("Quadrant note + PET itemwise BH...")
q_counts <- as.data.frame(table(Quadrant = dfB$quadrant), stringsAsFactors = FALSE)
q_counts$Note <- "Derived from workbook EBV_high × (TLG>65 | NTR>0.64); report headline 65/28/173/146 not forced"
write_xlsx_simple(q_counts,
  file.path(tbl_dir, "Table S5b. Quadrant counts authenticity note.xlsx"),
  "Table S5b. Authentic quadrant counts (do not force report 65/28/173/146)")

# refresh S5 HRs with current defs + note
dQ <- .npc_endpoint_df(dfB, "DM")
dQ$eh <- as.integer(dQ$ebv_high %in% 1L); dQ$ph <- as.integer(dQ$pet_high %in% 1L)
evQ <- as.integer(dQ$cause == 1L)
fit_q <- tryCatch(coxph(Surv(time, evQ) ~ eh + ph + eh:ph + age + male, data = dQ), error = function(e) NULL)
# PET 逐项：Lmtv Ltlg Lntr Lsuv_p Lnode — Age+Sex 调整，BH
pet_vars <- c("Lmtv", "Ltlg", "Lntr", "Lsuv_p", "Lsuvmean_p", "Lnode")
pet_rows <- list()
for (ep in c("OS", "PFS", "DM")) {
  d <- .npc_endpoint_df(dfB, ep)
  ev <- if (ep == "DM") as.integer(d$cause == 1L) else as.integer(d$cause > 0)
  for (v in pet_vars) {
    if (!v %in% names(d)) next
    fml <- as.formula(paste0("Surv(time, ev) ~ ", v, " + age + male"))
    fit <- tryCatch(coxph(fml, data = d), error = function(e) NULL)
    if (is.null(fit)) next
    sm <- summary(fit)$coefficients
    if (!v %in% rownames(sm)) next
    pet_rows[[length(pet_rows) + 1L]] <- data.frame(
      Endpoint = ep, Variable = v,
      HR = exp(sm[v, "coef"]),
      lo = exp(sm[v, "coef"] - 1.96 * sm[v, "se(coef)"]),
      hi = exp(sm[v, "coef"] + 1.96 * sm[v, "se(coef)"]),
      p = sm[v, "Pr(>|z|)"],
      stringsAsFactors = FALSE
    )
  }
}
tab_pet <- do.call(rbind, pet_rows)
tab_pet$q_BH <- p.adjust(tab_pet$p, method = "BH")
tab_pet$HR_CI <- mapply(fmt_hr, tab_pet$HR, tab_pet$lo, tab_pet$hi)
tab_pet$P <- vapply(tab_pet$p, fmt_p, character(1))
tab_pet$q <- vapply(tab_pet$q_BH, fmt_p, character(1))
write_xlsx_simple(tab_pet[, c("Endpoint", "Variable", "HR_CI", "P", "q")],
  file.path(tbl_dir, "Table S33. PET markers Age-Sex HRs with BH adjustment.xlsx"),
  "Table S33. PET itemwise Age+Sex–adjusted HRs with Benjamini–Hochberg q (family=all rows)")

# ===========================================================================
# 5) 年代留出多终点 ΔAUC
# ===========================================================================
.message("Temporal holdout multi-endpoint...")
train <- dfB[dfB$dx_year <= 2022, , drop = FALSE]
test <- dfB[dfB$dx_year >= 2023, , drop = FALSE]
rownames(train) <- NULL; rownames(test) <- NULL
hold_rows <- list()
for (ep in c("OS", "PFS", "DM", "DM+D", "LR")) {
  for (md in c("C", "E", "P2", "EP2")) {
    dtr <- .npc_endpoint_df(train, ep); dte <- .npc_endpoint_df(test, ep)
    rownames(dtr) <- as.character(seq_len(nrow(dtr)))
    rownames(dte) <- as.character(seq_len(nrow(dte)))
    mm_tr <- tryCatch(.npc_design_matrix(dtr, .npc_model_vars(md)), error = function(e) NULL)
    mm_te <- tryCatch(.npc_design_matrix(dte, .npc_model_vars(md)), error = function(e) NULL)
    if (is.null(mm_tr) || is.null(mm_te)) next
    cols <- intersect(colnames(mm_tr), colnames(mm_te))
    if (!length(cols)) next
    xtr <- mm_tr[, cols, drop = FALSE]; xte <- mm_te[, cols, drop = FALSE]
    ktr <- as.integer(rownames(xtr)); kte <- as.integer(rownames(xte))
    ev <- if (ep %in% c("DM", "LR")) as.integer(dtr$cause[ktr] == 1L) else as.integer(dtr$cause[ktr] > 0)
    fit <- tryCatch(.npc_fit_ridge_cox(xtr, Surv(dtr$time[ktr], ev), lambda = lamB), error = function(e) NULL)
    if (is.null(fit)) next
    lp <- .npc_predict_lp(fit, xte)
    met <- .npc_ipcw_auc(dte$time[kte], dte$cause[kte], lp, 36)
    hold_rows[[length(hold_rows) + 1L]] <- data.frame(
      Endpoint = ep, Model = md, N_train = length(ktr), N_test = length(kte),
      Events_test = sum(if (ep %in% c("DM", "LR")) dte$cause[kte] == 1L else dte$cause[kte] > 0),
      AUC = round(met$auc, 3), Brier = round(met$brier, 4),
      stringsAsFactors = FALSE
    )
  }
}
tab_hold <- do.call(rbind, hold_rows)
# Δ vs C
delta_rows <- list()
for (ep in unique(tab_hold$Endpoint)) {
  ref <- tab_hold$AUC[tab_hold$Endpoint == ep & tab_hold$Model == "C"]
  if (!length(ref) || !is.finite(ref[1])) next
  sub <- tab_hold[tab_hold$Endpoint == ep & tab_hold$Model != "C", ]
  for (i in seq_len(nrow(sub))) {
    delta_rows[[length(delta_rows) + 1L]] <- data.frame(
      Endpoint = ep, Contrast = paste(sub$Model[i], "- C"),
      AUC_C = ref[1], AUC_new = sub$AUC[i], Delta_AUC = round(sub$AUC[i] - ref[1], 3),
      Events_test = sub$Events_test[i], stringsAsFactors = FALSE
    )
  }
}
write_xlsx_simple(tab_hold,
  file.path(tbl_dir, "Table S3. Temporal holdout DM AUC.xlsx"),
  "Table S3. Temporal holdout AUC by endpoint and model (train ≤2022 / test 2023–2025)")
write_xlsx_simple(do.call(rbind, delta_rows),
  file.path(tbl_dir, "Table S34. Temporal holdout multi-endpoint delta AUC.xlsx"),
  "Table S34. Temporal holdout ΔAUC vs clinical (OS/PFS/DM/DM+D/LR)")

# ===========================================================================
# 6) U / UP2 / IUX 独立定义
# ===========================================================================
.message("U / UP2 / IUX distinct models...")
# 9 月界标、有 T2、时间平移
mk_lm <- function(df, lm = 9L) {
  d <- df[as.integer(df$lm9) == 1L & is.finite(df$t2_score), , drop = FALSE]
  d <- d[is.finite(d$dm_time) & d$dm_time >= lm, , drop = FALSE]
  rownames(d) <- NULL
  for (tc in c("os_time", "pfs_time", "dm_time", "dmd_time", "lr_time")) {
    if (tc %in% names(d)) d[[tc]] <- pmax(as.numeric(d[[tc]]) - lm, 0.01)
  }
  d$ic_a <- as.integer(d$ic_a %in% 1L)
  d
}
dL <- mk_lm(dfB, 9L)
# U: 参照=临床+T0+IC → +T2（无基线 PET）
vars_u0 <- c("age", "male", "t_ord", "n_ord", "t0_score", "ic_a")
vars_u1 <- c(vars_u0, "t2_score")
# UP2: 参照=临床+T0+IC+PET2 → +T2
vars_up0 <- c("age", "male", "t_ord", "n_ord", "t0_score", "ic_a", "Lmtv", "Lnode")
vars_up1 <- c(vars_up0, "t2_score")
fam_rows <- list()
for (spec in list(
  list(fam = "U", v0 = vars_u0, v1 = vars_u1, desc = "Landmark: clinical+T0+IC ± T2 (no baseline PET)"),
  list(fam = "UP2", v0 = vars_up0, v1 = vars_up1, desc = "Landmark: clinical+T0+IC+PET2 ± T2")
)) {
  o0 <- tryCatch(npc_ebv_pet_oof_cv(dL, "DM", "C", n_rep, 5L, 20261125L, 36, lamB, spec$v0), error = function(e) NULL)
  o1 <- tryCatch(npc_ebv_pet_oof_cv(dL, "DM", "C", n_rep, 5L, 20261125L, 36, lamB, spec$v1), error = function(e) NULL)
  if (is.null(o0) || is.null(o1)) next
  m0 <- .npc_ipcw_auc(o0$time, o0$cause, o0$lp, 36)
  m1 <- .npc_ipcw_auc(o1$time, o1$cause, o1$lp, 36)
  fam_rows[[length(fam_rows) + 1L]] <- data.frame(
    Family = spec$fam, Endpoint = "DM", Description = spec$desc,
    N = o0$n, AUC_ref = round(m0$auc, 3), AUC_new = round(m1$auc, 3),
    Delta = round(m1$auc - m0$auc, 3), stringsAsFactors = FALSE
  )
}
# IUX from IC numbers above
fam_rows[[length(fam_rows) + 1L]] <- data.frame(
  Family = "IUX", Endpoint = "PFS",
  Description = sprintf("IC complete-case N=%d: T1-main-only vs T1×MTV+T1×Lnode", nrow(ic)),
  N = nrow(ic), AUC_ref = round(a0$auc, 3), AUC_new = round(a1$auc, 3),
  Delta = round(a1$auc - a0$auc, 3), stringsAsFactors = FALSE
)
write_xlsx_simple(do.call(rbind, fam_rows),
  file.path(tbl_dir, "Table S30. Landmark IC model family U UP2 IUX.xlsx"),
  "Table S30. Distinct U (no PET) / UP2 (+PET2) / IUX (IC double interaction)")

# ===========================================================================
# 7) 风险评分：6 参数 LP → 0–100 线性拉伸后用锁定切点
# ===========================================================================
.message("Risk score from recomputed 6-parameter LP...")
bb <- dfB
bb$age_z <- zscore(bb$age); bb$t0_z <- zscore(bb$t0_score)
bb$Lmtv_z <- zscore(bb$Lmtv); bb$Lnode_z <- zscore(bb$Lnode)
fit6 <- coxph(Surv(pfs_time, pfs_event) ~ age_z + male + t_ord + n_ord + t0_z + Lmtv_z + Lnode_z, data = bb)
lp <- as.numeric(predict(fit6, newdata = bb, type = "lp"))
# 透明缩放：min-max 到 [0,100]
lp_ok <- lp[is.finite(lp)]
score <- 100 * (lp - min(lp_ok)) / (max(lp_ok) - min(lp_ok))
cut1 <- 45.9; cut2 <- 58.71
tert <- cut(score, breaks = c(-Inf, cut1, cut2, Inf), labels = c("Low", "Mid", "High"), right = FALSE)
bb$risk_score_recalc <- score
bb$risk_tert_recalc <- tert
# 事件率
rs_rows <- list()
for (ep in c("OS", "PFS", "DM")) {
  ev <- if (ep == "OS") bb$os_event else if (ep == "PFS") bb$pfs_event else as.integer(bb$dm_status == 1L)
  for (lv in c("Low", "Mid", "High")) {
    ii <- which(bb$risk_tert_recalc == lv)
    rs_rows[[length(rs_rows) + 1L]] <- data.frame(
      Endpoint = ep, Tertile = lv, N = length(ii), Events = sum(ev[ii], na.rm = TRUE),
      Event_rate = round(mean(ev[ii], na.rm = TRUE), 4),
      Cutoffs = "45.9 / 58.71 on min-max scaled 6-parameter LP (0–100)",
      stringsAsFactors = FALSE
    )
  }
}
tab_rs <- do.call(rbind, rs_rows)
# log-rank
lr_os <- survdiff(Surv(os_time, os_event) ~ risk_tert_recalc, data = bb)
lr_pfs <- survdiff(Surv(pfs_time, pfs_event) ~ risk_tert_recalc, data = bb)
tab_rs$Logrank_note <- sprintf("OS chi2=%.2f p=%s; PFS chi2=%.2f p=%s",
                               lr_os$chisq, fmt_p(pchisq(lr_os$chisq, length(lr_os$n) - 1, lower.tail = FALSE)),
                               lr_pfs$chisq, fmt_p(pchisq(lr_pfs$chisq, length(lr_pfs$n) - 1, lower.tail = FALSE)))
write_xlsx_simple(tab_rs,
  file.path(tbl_dir, "Table S18. Risk-score strata with locked cutoffs.xlsx"),
  "Table S18. Risk tertiles from recomputed 6-parameter LP (min-max 0–100) with locked cuts 45.9/58.71")

# ===========================================================================
# 8) Methods 补记真实性声明
# ===========================================================================
meth_path <- file.path(out_root, "Methods_statistical_analysis.md")
extra <- c(
  "",
  "## Authenticity notes (this rebuild)",
  "- IC complete-case N is recomputed (IC + non-missing T1 + MTV/Lnode); report headline 287 is **not forced**.",
  "- Quadrant counts follow workbook EBV_high × (TLG>65 | NTR>0.64); report 65/28/173/146 is **not forced** (observed counts tabulated in S5b).",
  "- Leave-one-out deletes every observed T1-threshold & PFS case (true count, not forced to 6).",
  "- Risk score = min-max(0–100) of unpenalized 6-parameter Cox LP; locked cuts 45.9/58.71 applied to that scale.",
  "- glmnet Cox uses cox.ties = 'breslow'. Cohort A M0 uses AJCC stage_num (not separate T/N).",
  "- Figures 9–10 redrawn from the latest Table 2 (seven models including P6/EP6/EP2X)."
)
if (file.exists(meth_path)) {
  writeLines(c(readLines(meth_path, warn = FALSE), extra), meth_path, useBytes = TRUE)
}

.message("DONE remaining fixes → %s", out_root)
