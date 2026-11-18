#!/usr/bin/env Rscript
# 补齐方案缺口：编码敏感性 / 累积负荷·T1×PET / ΔBrier·LR / CIF·FG /
# 口径A M0–M4 / DCA主图 / 偏相关 / 风险切点 / Methods·表去重
suppressPackageStartupMessages({
  library(survival); library(glmnet); library(ggplot2); library(openxlsx)
  library(timeROC); library(grid)
})
if (requireNamespace("gridExtra", quietly = TRUE)) library(gridExtra)
if (requireNamespace("scales", quietly = TRUE)) library(scales)
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
n_boot <- as.integer(.get_arg("--boot", "300"))
if ("--quick" %in% args) { n_repeats <- 2L; n_boot <- 80L }

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

# 去重旧表
dup_kill <- c(
  "Table 3. Distant-metastasis paired delta AUC for EP2.xlsx",
  "Table 5. Landmark trajectory incremental AUC for distant metastasis.xlsx",
  "Table S6. Sensitivity DM EP2 AUC under EBV coding variants.xlsx",
  "Table S8. Apparent resubstitution nested-model AUC.xlsx"
)
for (f in dup_kill) {
  p <- file.path(tbl_dir, f); if (file.exists(p)) unlink(p)
}

.message("Reading data...")
raw <- npc_ebv_pet_read_analysis_df(workbook)
rownames(raw) <- NULL
dfA <- raw
dfB <- raw[as.integer(raw$include) == 1L, , drop = FALSE]
rownames(dfB) <- NULL
.message("A=%d B=%d", nrow(dfA), nrow(dfB))

# ===========================================================================
# 1) SUBLOD / 编码专表 + 左删失上界
# ===========================================================================
.message("EBV coding tables...")
kind_tab <- function(kind, pos, score, raw, ub, lod) {
  data.frame(
    Record_type = as.character(kind),
    N = 1L,
    Above_threshold = as.integer(pos == 1),
    Score = score, Raw = raw, Upper_bound = ub, LOD = lod,
    stringsAsFactors = FALSE
  )
}
sublod <- dfB[!is.na(dfB$t0_kind) & grepl("低于阈值|SUBLOD", as.character(dfB$t0_kind)), ]
sublod_sum <- data.frame(
  Timepoint = "T0",
  N_SUBLOD = nrow(sublod),
  Median_raw = if (nrow(sublod) && "t0_raw" %in% names(sublod)) median(sublod$t0_raw, na.rm = TRUE) else NA_real_,
  Median_score = median(sublod$t0_score, na.rm = TRUE),
  Median_LOD = median(sublod$lod, na.rm = TRUE),
  Note = "Positive quantitative values below recorded LOD; retained at face value in primary coding",
  stringsAsFactors = FALSE
)
# T1/T2 SUBLOD counts
for (tp in c("T1", "T2")) {
  kn <- paste0(tolower(tp), "_kind"); sc <- paste0(tolower(tp), "_score"); rw <- paste0(tolower(tp), "_raw")
  if (!kn %in% names(dfB)) next
  ss <- dfB[!is.na(dfB[[kn]]) & grepl("低于阈值|SUBLOD", as.character(dfB[[kn]])), ]
  sublod_sum <- rbind(sublod_sum, data.frame(
    Timepoint = tp, N_SUBLOD = nrow(ss),
    Median_raw = if (nrow(ss) && rw %in% names(ss)) median(ss[[rw]], na.rm = TRUE) else NA_real_,
    Median_score = if (nrow(ss)) median(ss[[sc]], na.rm = TRUE) else NA_real_,
    Median_LOD = median(ss$lod, na.rm = TRUE),
    Note = "SUBLOD retained", stringsAsFactors = FALSE
  ))
}
write_xlsx_simple(sublod_sum, file.path(tbl_dir, "Table S10. SUBLOD record summary.xlsx"),
                  "Table S10. SUBLOD (positive below LOD) counts and medians")

coding_census <- as.data.frame(table(Type = dfB$t0_kind), stringsAsFactors = FALSE)
coding_census$Timepoint <- "T0"
names(coding_census)[names(coding_census) == "Freq"] <- "N"
coding_census <- coding_census[, c("Timepoint", "Type", "N")]
for (tp in c("T1", "T2")) {
  kn <- paste0(tolower(tp), "_kind")
  if (!kn %in% names(dfB)) next
  tmp <- as.data.frame(table(Type = dfB[[kn]]), stringsAsFactors = FALSE)
  tmp$Timepoint <- tp
  names(tmp)[names(tmp) == "Freq"] <- "N"
  tmp <- tmp[, c("Timepoint", "Type", "N")]
  coding_census <- rbind(coding_census, tmp)
}
write_xlsx_simple(coding_census, file.path(tbl_dir, "Table S1b. EBV record-type census by timepoint.xlsx"),
                  "Table S1b. EBV DNA record-type census (BLQ/ZERO/SUBLOD/Q/MISSING)")

# ===========================================================================
# 2) 敏感性全家桶（折外 EP2 AUC）
# ===========================================================================
.message("Sensitivity suite (OOF EP2)...")
run_oof <- function(dat, label, seed = 401) {
  res <- tryCatch(
    npc_ebv_pet_oof_cv(dat, "DM", "EP2", n_repeats = n_repeats, n_folds = 5L, seed = seed, horizon = 36),
    error = function(e) NULL
  )
  if (is.null(res)) return(NULL)
  data.frame(Scenario = label, N = res$n, Events = res$n_event,
             AUC = round(res$auc, 3), Brier = round(res$brier, 4),
             stringsAsFactors = FALSE)
}
sens <- list()
sens[[1]] <- run_oof(dfB, "Primary relative-LOD", 401)

# BLQ = LOD/2
tmp <- dfB; tmp$t0_score <- tmp$t0_score_half
sens[[length(sens) + 1]] <- run_oof(tmp, "BLQ = LOD/2 fill", 402)

# left-censor upper bound score
tmp <- dfB; tmp$t0_score <- ifelse(is.finite(tmp$t0_score_with_ub), tmp$t0_score_with_ub, tmp$t0_score)
sens[[length(sens) + 1]] <- run_oof(tmp, "BLQ uses left-censor upper bound", 403)

# strict detectability
tmp <- dfB; tmp$t0_score <- 0; # keep t0_pos
sens[[length(sens) + 1]] <- run_oof(tmp, "Strict detectability (score zeroed)", 404)

# any positive quantitative as positive
if ("t0_anypos" %in% names(dfB)) {
  tmp <- dfB; tmp$t0_pos <- tmp$t0_anypos
  sens[[length(sens) + 1]] <- run_oof(tmp, "Any positive quantitative as positive", 405)
}

# unified LOD 5000
tmp <- dfB
rel <- pmax(10^pmax(tmp$t0_score, 0) - 1, 0) * tmp$lod / 5000
tmp$t0_score <- log10(1 + rel); tmp$t0_pos <- as.integer(rel >= 1)
sens[[length(sens) + 1]] <- run_oof(tmp, "Unified LOD 5000", 406)

# exclude LOD=5000 cases
tmp <- dfB[is.na(dfB$lod) | dfB$lod != 5000, ]
sens[[length(sens) + 1]] <- run_oof(tmp, "Exclude LOD=5000 cases", 407)

# III–IVA only
tmp <- dfB
if ("ajcc8" %in% names(tmp)) {
  tmp <- tmp[grepl("III|IVA|IVB", as.character(tmp$ajcc8)) | tmp$t_ord >= 3 | tmp$n_ord >= 2, ]
  # better: AJCC III or IVA
  tmp <- dfB[grepl("^III$|^IVA$", as.character(dfB$ajcc8)) | grepl("III|IVA", as.character(dfB$ajcc8)), ]
  if (nrow(tmp) >= 80) sens[[length(sens) + 1]] <- run_oof(tmp, "III–IVA only", 408)
}

# drop TLG discrepancy
if ("tlg_flag" %in% names(dfB)) {
  tmp <- dfB[is.na(dfB$tlg_flag) | dfB$tlg_flag != 1, ]
  sens[[length(sens) + 1]] <- run_oof(tmp, "Exclude TLG discrepancy >5%", 409)
}

# recalculate TLG from formula value
if ("tlg_formula" %in% names(dfB) && any(is.finite(dfB$tlg_formula))) {
  tmp <- dfB
  tmp$tlg <- ifelse(is.finite(tmp$tlg_formula), tmp$tlg_formula, tmp$tlg)
  tmp$Ltlg <- log2(1 + pmax(tmp$tlg, 0))
  tmp$tlg_high <- as.integer(tmp$tlg > 65)
  tmp$pet_high <- as.integer(tmp$tlg_high == 1 | tmp$ntr_high == 1)
  sens[[length(sens) + 1]] <- run_oof(tmp, "TLG replaced by formula check value", 410)
}

# R-D leakage contrast: add traj_high (follow-up biology) into EP2 as "leak" control
if (all(c("traj_mid", "traj_high") %in% names(dfB))) {
  # compare primary vs EP2+traj on same OOF machinery via custom vars
  leak <- tryCatch({
    d0 <- .npc_endpoint_df(dfB, "DM"); rownames(d0) <- as.character(seq_len(nrow(d0)))
    vars <- c(.npc_model_vars("EP2"), "traj_mid", "traj_high")
    mm <- .npc_design_matrix(d0, vars)
    keep <- as.integer(rownames(mm)); d1 <- d0[keep, ]; x <- mm; rownames(x) <- NULL
    set.seed(411)
    strata <- as.integer(d1$cause)
    oof_sum <- rep(0, nrow(d1)); oof_n <- rep(0, nrow(d1))
    for (r in seq_len(n_repeats)) {
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
    met <- .npc_ipcw_auc(d1$time, d1$cause, lp, 36)
    data.frame(Scenario = "R-D leakage control (EP2+trajectory)", N = nrow(d1),
               Events = sum(d1$cause == 1), AUC = round(met$auc, 3), Brier = round(met$brier, 4),
               stringsAsFactors = FALSE)
  }, error = function(e) NULL)
  if (!is.null(leak)) sens[[length(sens) + 1]] <- leak
}

# drop T1-above-threshold cases who had PFS (report sensitivity)
if (all(c("t1_pos", "pfs_event") %in% names(dfB))) {
  drop_id <- which(dfB$t1_pos == 1 & dfB$pfs_event == 1)
  if (length(drop_id) > 0 && length(drop_id) <= 20) {
    tmp <- dfB[-drop_id, ]
    sens[[length(sens) + 1]] <- run_oof(tmp, sprintf("Drop %d T1+ PFS cases", length(drop_id)), 412)
  }
}

sens_df <- do.call(rbind, Filter(Negate(is.null), sens))
write_xlsx_simple(sens_df, file.path(tbl_dir, "Table S6. Sensitivity analyses AUC.xlsx"),
                  "Table S6. Full sensitivity suite: 36-month DM EP2 OOF AUC/Brier")

# Fig19 refresh
p19 <- ggplot(sens_df, aes(y = reorder(Scenario, AUC), x = AUC)) +
  geom_point(size = 3, color = "#4C78A8") +
  geom_text(aes(label = sprintf("%.3f", AUC)), hjust = -0.15, size = 3, family = font_family) +
  coord_cartesian(xlim = c(0.5, max(0.95, max(sens_df$AUC, na.rm = TRUE) + 0.08))) +
  labs(title = "Figure 19. Sensitivity analyses (coding, population, leakage)",
       x = "36-month OOF IPCW-AUC", y = NULL)
save_pdf(file.path(fig_dir, "Figure 19. Sensitivity analyses coding population endpoints.pdf"), print(p19), 10, 6.5)
write_md("Figure 19. Sensitivity analyses coding population endpoints",
         "多编码（BLQ=LOD/2、左删失上界、严格检出、任意正定量、统一5000）、人群（剔5000、III–IVA）、TLG、R-D 泄漏对照等折外 AUC。",
         paste0("口径 B；重复 ", n_repeats, "×5 折。"))

# ===========================================================================
# 3) ΔBrier + 似然比嵌套
# ===========================================================================
.message("ΔBrier + nested LR...")
oof_c <- npc_ebv_pet_oof_cv(dfB, "DM", "C", n_repeats = n_repeats, seed = 501, horizon = 36)
oof_e <- npc_ebv_pet_oof_cv(dfB, "DM", "E", n_repeats = n_repeats, seed = 502, horizon = 36)
oof_p2 <- npc_ebv_pet_oof_cv(dfB, "DM", "P2", n_repeats = n_repeats, seed = 503, horizon = 36)
oof_ep2 <- npc_ebv_pet_oof_cv(dfB, "DM", "EP2", n_repeats = n_repeats, seed = 504, horizon = 36)

pair_rows <- list()
for (nm in c("C", "E", "P2")) {
  ref <- switch(nm, C = oof_c, E = oof_e, P2 = oof_p2)
  if (is.null(ref) || is.null(oof_ep2)) next
  dlt <- npc_ebv_pet_paired_delta_full(ref, oof_ep2, n_boot = n_boot, seed = 42L)
  pair_rows[[length(pair_rows) + 1]] <- data.frame(
    Endpoint = "DM", New = "EP2", Reference = nm,
    AUC_ref = round(dlt$auc_ref, 3), AUC_new = round(dlt$auc_new, 3),
    Delta_AUC = round(dlt$delta_auc, 3), AUC_CI_low = round(dlt$auc_lo, 3), AUC_CI_high = round(dlt$auc_hi, 3),
    Brier_ref = round(dlt$brier_ref, 4), Brier_new = round(dlt$brier_new, 4),
    Delta_Brier = round(dlt$delta_brier, 4), Brier_CI_low = round(dlt$brier_lo, 4), Brier_CI_high = round(dlt$brier_hi, 4),
    stringsAsFactors = FALSE
  )
}
pair_df <- do.call(rbind, pair_rows)
write_xlsx_simple(pair_df, file.path(tbl_dir, "Table 3. Distant-metastasis paired delta AUC.xlsx"),
                  "Table 3. Distant metastasis paired ΔAUC and ΔBrier (36-month OOF)")

lr_rows <- list(
  npc_ebv_pet_nested_lr(dfB, "DM", character(0), c("t0_pos", "t0_score")),
  npc_ebv_pet_nested_lr(dfB, "DM", character(0), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "DM", c("t0_pos", "t0_score"), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "DM", c("Lmtv", "Lnode"), c("t0_pos", "t0_score")),
  npc_ebv_pet_nested_lr(dfB, "OS", c("t0_pos", "t0_score"), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "PFS", c("t0_pos", "t0_score"), c("Lmtv", "Lnode"))
)
# fix empty small model - use clinical base always
lr_rows <- list(
  npc_ebv_pet_nested_lr(dfB, "DM", c("age"), c("t0_pos", "t0_score")), # will still add clinical in function
  npc_ebv_pet_nested_lr(dfB, "DM", c("t0_pos", "t0_score"), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "DM", c("Lmtv", "Lnode"), c("t0_pos", "t0_score")),
  npc_ebv_pet_nested_lr(dfB, "OS", c("t0_pos", "t0_score"), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "PFS", c("t0_pos", "t0_score"), c("Lmtv", "Lnode")),
  npc_ebv_pet_nested_lr(dfB, "DM", c("t0_pos", "t0_score", "Lmtv", "Lnode"), c("cum_trap", "t2_resid"))
)
lr_df <- do.call(rbind, Filter(Negate(is.null), lr_rows))
if (!is.null(lr_df) && nrow(lr_df)) {
  lr_df$P <- ifelse(lr_df$p < 0.001, "<0.001", sprintf("%.3f", lr_df$p))
  write_xlsx_simple(lr_df, file.path(tbl_dir, "Table S11. Nested likelihood-ratio tests.xlsx"),
                    "Table S11. Nested Cox likelihood-ratio tests (unpenalized, clinical base always included)")
}

# ===========================================================================
# 4) CIF 绝对风险 + Fine–Gray
# ===========================================================================
.message("CIF + Fine-Gray...")
cif_dm <- npc_ebv_pet_cif_table(dfB, "DM")
cif_lr <- npc_ebv_pet_cif_table(dfB, "LR")
cif_df <- rbind(cif_dm, cif_lr)
if (!is.null(cif_df) && nrow(cif_df)) {
  cif_df$CIF_pct <- round(100 * cif_df$CIF, 1)
  cif_df$CI <- sprintf("%.1f (%.1f–%.1f)", 100 * cif_df$CIF, 100 * cif_df$CI_low, 100 * cif_df$CI_high)
  write_xlsx_simple(cif_df, file.path(tbl_dir, "Table S12. Competing-risk CIF absolute risks.xlsx"),
                    "Table S12. Competing-risk CIF absolute risks (DM and LR)")
}
fg <- npc_ebv_pet_finegray_hr(dfB, "DM", c("Lnode", "Lmtv", "t0_pos", "t0_score", "cum_trap"))
cs <- npc_ebv_pet_cause_specific_hr(dfB, "DM", c("Lnode", "Lmtv", "t0_pos", "t0_score", "cum_trap"))
if (!is.null(fg)) {
  fg$Method <- "Fine-Gray"
  fg$HR_CI <- sprintf("%s (%s, %s)", npc_ebv_pet_fmt(fg$HR), npc_ebv_pet_fmt(fg$lo), npc_ebv_pet_fmt(fg$hi))
  fg$P <- ifelse(fg$p < 0.001, "<0.001", npc_ebv_pet_fmt(fg$p, 3))
}
if (!is.null(cs)) {
  cs$Method <- "Cause-specific Cox"
  cs$HR_CI <- sprintf("%s (%s, %s)", npc_ebv_pet_fmt(cs$HR), npc_ebv_pet_fmt(cs$lo), npc_ebv_pet_fmt(cs$hi))
  cs$P <- ifelse(cs$p < 0.001, "<0.001", npc_ebv_pet_fmt(cs$p, 3))
}
cr_cmp <- rbind(
  if (!is.null(cs)) cs[, c("Method", "endpoint", "variable", "HR_CI", "P")] else NULL,
  if (!is.null(fg)) fg[, c("Method", "endpoint", "variable", "HR_CI", "P")] else NULL
)
if (!is.null(cr_cmp) && nrow(cr_cmp)) {
  names(cr_cmp)[2:3] <- c("Endpoint", "Variable")
  cr_cmp$Variable <- gsub("_", " ", cr_cmp$Variable)
  write_xlsx_simple(cr_cmp, file.path(tbl_dir, "Table S13. Cause-specific vs Fine-Gray HRs for DM.xlsx"),
                    "Table S13. Cause-specific Cox versus Fine-Gray HRs for distant metastasis")
}

# ===========================================================================
# 5) 累积负荷 / T2 / IC 后 T1×PET
# ===========================================================================
.message("Trapezoid load + IC T1×PET...")
load_tab <- data.frame(
  Variable = c("cum_trap", "t2_resid", "log_drop", "t0_score", "t1_score", "t2_score"),
  Mean = sapply(c("cum_trap", "t2_resid", "log_drop", "t0_score", "t1_score", "t2_score"),
                function(v) mean(dfB[[v]], na.rm = TRUE)),
  SD = sapply(c("cum_trap", "t2_resid", "log_drop", "t0_score", "t1_score", "t2_score"),
              function(v) sd(dfB[[v]], na.rm = TRUE)),
  stringsAsFactors = FALSE
)
write_xlsx_simple(load_tab, file.path(tbl_dir, "Table S14. EBV cumulative trapezoid load summary.xlsx"),
                  "Table S14. Trapezoidal cumulative EBV load and T2 residual (cohort B)")

# IC landmark: among IC recipients with lm9, model EP2 vs EP2+T1×PET
ic_df <- dfB
if (!"ic" %in% names(ic_df)) ic_df$ic <- as.integer(!is.na(ic_df$ic_code) & !(as.character(ic_df$ic_code) %in% c("", "0", "无", "否")))
ic_sub <- ic_df[!is.na(ic_df$lm9) & ic_df$lm9 == 1 & ic_df$ic == 1, ]
ic_sub <- ic_sub[ic_sub$dm_time > 9 | (ic_sub$dm_status == 0 & ic_sub$dm_time >= 9), ]
ic_rows <- list()
if (nrow(ic_sub) >= 60) {
  ic_sub$time <- pmax(ic_sub$dm_time - 9, 0.01)
  ic_sub$cause <- ic_sub$dm_status
  ic_sub$t1_pet <- as.numeric(ic_sub$t1_pos) * as.numeric(ic_sub$pet_high)
  ic_sub$t1_Lnode <- as.numeric(ic_sub$t1_score) * as.numeric(ic_sub$Lnode)
  tmp <- ic_sub; tmp$dm_time <- tmp$time; tmp$dm_status <- tmp$cause
  ref <- tryCatch(npc_ebv_pet_oof_cv(tmp, "DM", "EP2", n_repeats = max(2L, n_repeats %/% 2L),
                                     seed = 601, horizon = 36), error = function(e) NULL)
  # extended
  d0 <- .npc_endpoint_df(tmp, "DM"); rownames(d0) <- as.character(seq_len(nrow(d0)))
  d0$t1_pet <- as.numeric(d0$t1_pos) * as.numeric(d0$pet_high)
  d0$t1_Lnode <- as.numeric(d0$t1_score) * as.numeric(d0$Lnode)
  vars <- c(.npc_model_vars("EP2"), "t1_pos", "t1_score", "t1_pet", "t1_Lnode")
  mm <- tryCatch(.npc_design_matrix(d0, vars), error = function(e) NULL)
  new_auc <- NA_real_; new_brier <- NA_real_
  if (!is.null(mm)) {
    keep <- as.integer(rownames(mm)); d1 <- d0[keep, ]; x <- mm; rownames(x) <- NULL
    set.seed(602)
    strata <- as.integer(d1$cause)
    oof_sum <- rep(0, nrow(d1)); oof_n <- rep(0, nrow(d1))
    nrep <- max(2L, n_repeats %/% 2L)
    for (r in seq_len(nrep)) {
      fold <- rep(NA_integer_, nrow(d1))
      for (s in sort(unique(strata))) {
        ii <- which(strata == s); fold[ii] <- sample(rep(1:5, length.out = length(ii)))
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
    met <- .npc_ipcw_auc(d1$time, d1$cause, lp, 36)
    new_auc <- met$auc; new_brier <- met$brier
  }
  ic_rows[[1]] <- data.frame(
    Landmark = "9-month IC subcohort",
    N = nrow(ic_sub),
    AUC_EP2 = if (!is.null(ref)) round(ref$auc, 3) else NA_real_,
    AUC_EP2_T1xPET = round(new_auc, 3),
    Delta_AUC = round(new_auc - (if (!is.null(ref)) ref$auc else NA_real_), 3),
    Brier_EP2_T1xPET = round(new_brier, 4),
    stringsAsFactors = FALSE
  )
  # Cox interaction p
  dcox <- ic_sub
  dcox$ev <- as.integer(dcox$cause == 1)
  fit_int <- tryCatch(
    coxph(Surv(time, ev) ~ age + male + t_ord + n_ord + t1_pos * pet_high + Lnode + Lmtv + t0_score, data = dcox),
    error = function(e) NULL
  )
  if (!is.null(fit_int)) {
    s <- summary(fit_int)$coefficients
    hit <- grep("t1_pos:pet_high|t1_pos:pet", rownames(s))
    if (length(hit)) {
      ic_rows[[1]]$Interaction_P <- sprintf("%.3f", s[hit[1], "Pr(>|z|)"])
    }
  }
}
ic_tab <- if (length(ic_rows)) do.call(rbind, ic_rows) else data.frame(Note = "IC landmark subset too small")
write_xlsx_simple(ic_tab, file.path(tbl_dir, "Table S15. IC landmark T1xPET incremental AUC.xlsx"),
                  "Table S15. Post-IC landmark: T1 × PET incremental DM AUC")

# ===========================================================================
# 6) 口径 A M0–M4
# ===========================================================================
.message("Cohort A M0-M4 apparent...")
m_rows <- list()
for (ep in c("OS", "PFS", "DM")) {
  m_rows[[length(m_rows) + 1]] <- npc_ebv_pet_m01234_apparent(dfA, ep, 36)
}
m_df <- do.call(rbind, Filter(Negate(is.null), m_rows))
write_xlsx_simple(m_df, file.path(tbl_dir, "Table S16. Cohort A M0-M4 apparent AUC.xlsx"),
                  "Table S16. Cohort A nested M0–M4 apparent 36-month IPCW-AUC (includes trajectory/interaction in M1–M4)")

p_m <- ggplot(m_df, aes(Model, AUC, fill = Endpoint)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.2f", AUC)), position = position_dodge(0.8), vjust = -0.3, size = 2.4, family = font_family) +
  coord_cartesian(ylim = c(0.5, max(0.95, max(m_df$AUC, na.rm = TRUE) + 0.05))) +
  labs(title = "Cohort A apparent M0–M4 nested models", y = "IPCW-AUC", x = NULL)
save_pdf(file.path(fig_dir, "Figure S2. Cohort A M0-M4 apparent nested AUC.pdf"), print(p_m), 9, 5)
write_md("Figure S2. Cohort A M0-M4 apparent nested AUC",
         "口径 A：M0 临床 → M1+EBV轨迹 → M2+PET → M3 联合 → M4+交互 的样本内 36 月 AUC。",
         "含治疗期 EBV/轨迹，描述性；主结论仍以口径 B 折外为准。")

# ===========================================================================
# 7) DCA 主图
# ===========================================================================
.message("DCA main figure...")
dca_list <- list()
for (nm in c("C", "E", "P2", "EP2")) {
  ob <- switch(nm, C = oof_c, E = oof_e, P2 = oof_p2, EP2 = oof_ep2)
  if (is.null(ob)) next
  ok <- is.finite(ob$lp)
  r <- rank(ob$lp[ok]) / sum(ok)
  inc <- mean(ob$cause[ok] == 1)
  risk <- pmin(pmax(r * (2 * inc), 1e-4), 0.99)
  evt <- as.integer(ob$cause[ok] == 1 & ob$time[ok] <= 36)
  for (th in seq(0.02, 0.30, by = 0.01)) {
    pred <- as.integer(risk >= th)
    nb <- mean(pred == 1 & evt == 1) - mean(pred == 1 & evt == 0) * (th / (1 - th))
    # treat-all / treat-none
    dca_list[[length(dca_list) + 1]] <- data.frame(Model = nm, Threshold = th, NetBenefit = nb)
  }
}
# treat all/none
if (!is.null(oof_ep2)) {
  ok <- is.finite(oof_ep2$lp)
  evt <- as.integer(oof_ep2$cause[ok] == 1 & oof_ep2$time[ok] <= 36)
  prev <- mean(evt)
  for (th in seq(0.02, 0.30, by = 0.01)) {
    dca_list[[length(dca_list) + 1]] <- data.frame(Model = "Treat all", Threshold = th,
                                                   NetBenefit = prev - (1 - prev) * (th / (1 - th)))
    dca_list[[length(dca_list) + 1]] <- data.frame(Model = "Treat none", Threshold = th, NetBenefit = 0)
  }
}
dca_df <- do.call(rbind, dca_list)
write_xlsx_simple(dca_df, file.path(tbl_dir, "Table S4. Decision-curve net benefit DM 36-month.xlsx"),
                  "Table S4. Decision-curve net benefit for DM at 36 months")
p_dca <- ggplot(dca_df, aes(Threshold, NetBenefit, color = Model, linetype = Model)) +
  geom_line(linewidth = 0.9) +
  coord_cartesian(ylim = c(-0.01, max(0.05, max(dca_df$NetBenefit, na.rm = TRUE) * 1.1))) +
  labs(title = "Figure S3. Decision curve: cross-model net benefit (DM, 36 months)",
       x = "Risk threshold", y = "Net benefit") +
  theme(legend.position = "bottom")
save_pdf(file.path(fig_dir, "Figure S3. Decision curve cross-model net benefit DM.pdf"), print(p_dca), 8, 5.5)
write_md("Figure S3. Decision curve cross-model net benefit DM",
         "折外风险代理下 C/E/P2/EP2 与 treat-all/none 在 2%–30% 阈值的净获益。",
         "风险为研究用代理概率；解释宜谨慎。")

# ===========================================================================
# 8) 偏秩相关 → 刷新 Fig2 旁路表 + 可选重画注释
# ===========================================================================
.message("Partial Spearman...")
pcor <- npc_ebv_pet_partial_spearman(
  dfB,
  xvars = c("t0_score", "cum_trap", "t2_resid"),
  yvars = c("Lnode", "Ltlg", "Lntr", "Lmtv"),
  adjust = c("age", "male", "t_ord", "n_ord", "lod")
)
if (!is.null(pcor) && nrow(pcor)) {
  pcor$rho <- round(pcor$rho, 3)
  pcor$p <- ifelse(pcor$p < 0.001, "<0.001", sprintf("%.4f", pcor$p))
  pcor$q <- ifelse(pcor$q < 0.001, "<0.001", sprintf("%.4f", pcor$q))
  write_xlsx_simple(pcor, file.path(tbl_dir, "Table S17. Partial Spearman EBV vs PET.xlsx"),
                    "Table S17. Partial Spearman (rank-residualized for age/sex/T/N/LOD): EBV vs PET")
}

# ordinary + partial heatmap companion fig
cm_vars <- c("t0_score", "cum_trap", "Lmtv", "Lnode", "Ltlg", "Lntr")
cm <- suppressWarnings(cor(dfB[, cm_vars], use = "pairwise.complete.obs", method = "spearman"))
dimnames(cm) <- list(gsub("_", " ", cm_vars), gsub("_", " ", cm_vars))
cm_df <- as.data.frame(as.table(cm)); names(cm_df) <- c("Var1", "Var2", "rho")
p2 <- ggplot(cm_df, aes(Var1, Var2, fill = rho)) +
  geom_tile() + geom_text(aes(label = sprintf("%.2f", rho)), size = 2.8, family = font_family) +
  scale_fill_gradient2(low = "#B2182B", mid = "white", high = "#2166AC", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Figure 2. Spearman correlations (see Table S17 for partial)",
       x = NULL, y = NULL, fill = "rho") +
  theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8))
save_pdf(file.path(fig_dir, "Figure 2. EBV PET clinical Spearman correlation heatmap.pdf"), print(p2), 8, 7)
write_md("Figure 2. EBV PET clinical Spearman correlation heatmap",
         "普通 Spearman 热图；调整年龄/性别/T/N/LOD 后的偏秩相关见 Table S17。",
         paste0("口径 B N=", nrow(dfB)))

# ===========================================================================
# 9) 风险评分固定切点 45.9 / 58.71
# ===========================================================================
.message("Locked risk-score cutoffs...")
# Prefer workbook RiskScore if present; else EP2 LP rescaled
if ("risk_score" %in% names(dfB) && any(is.finite(dfB$risk_score))) {
  score <- dfB$risk_score
} else {
  d0 <- .npc_endpoint_df(dfB, "PFS"); rownames(d0) <- as.character(seq_len(nrow(d0)))
  mm <- .npc_design_matrix(d0, .npc_model_vars("EP2"))
  keep <- as.integer(rownames(mm))
  fit <- .npc_fit_ridge_cox(mm, Surv(d0$time[keep], as.integer(d0$cause[keep] > 0)))
  lp <- .npc_predict_lp(fit, mm)
  score <- rep(NA_real_, nrow(dfB)); score[keep] <- lp
}
# If score scale is LP (centered ~0), map to report-like scale via percentile matching is wrong;
# Use workbook RiskScore when available from merge; else use cutoffs on available score with note.
cut_lo <- 45.9; cut_hi <- 58.71
rng <- range(score, na.rm = TRUE)
use_locked <- is.finite(rng[1]) && rng[1] > 5 && rng[2] < 200  # heuristic: report-like scale
if (use_locked) {
  risk_grp <- cut(score, breaks = c(-Inf, cut_lo, cut_hi, Inf), labels = c("Low", "Mid", "High"))
  cut_note <- "Locked cutoffs 45.9 / 58.71 from analysis report"
} else {
  # affine map LP to approximate report scale using tertile anchors, THEN apply locked cuts on mapped? 
  # Better: report both locked-on-workbook-score if present, else tertile + disclose
  qs <- quantile(score, c(1/3, 2/3), na.rm = TRUE)
  risk_grp <- cut(score, breaks = c(-Inf, qs[1], qs[2], Inf), labels = c("Low", "Mid", "High"))
  cut_note <- sprintf("Score appears LP-scaled [%.2f, %.2f]; tertile cuts used. Locked 45.9/58.71 require workbook RiskScore scale.", rng[1], rng[2])
  # If index has 风险评分 on original scale, prefer that
  if ("风险评分" %in% names(dfB)) {
    sc2 <- suppressWarnings(as.numeric(dfB[["风险评分"]]))
    if (sum(is.finite(sc2)) > 100 && median(sc2, na.rm = TRUE) > 10) {
      score <- sc2
      risk_grp <- cut(score, breaks = c(-Inf, cut_lo, cut_hi, Inf), labels = c("Low", "Mid", "High"))
      use_locked <- TRUE
      cut_note <- "Locked cutoffs 45.9 / 58.71 on workbook risk score"
    }
  }
}
dfB$risk_grp_locked <- risk_grp
evt_tab <- do.call(rbind, lapply(c("OS", "PFS", "DM"), function(ep) {
  d <- .npc_endpoint_df(dfB[!is.na(dfB$risk_grp_locked), ], ep)
  d$g <- dfB$risk_grp_locked[!is.na(dfB$risk_grp_locked)][seq_len(nrow(d))]
  # align carefully
  d <- .npc_endpoint_df(dfB, ep)
  d$g <- risk_grp[match(rownames(dfB), rownames(dfB))]
  d$g <- risk_grp
  d <- d[!is.na(d$g), ]
  d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
  do.call(rbind, lapply(split(d, d$g), function(g) {
    data.frame(Endpoint = ep, Risk = as.character(g$g[1]), N = nrow(g),
               Events = sum(g$ev), Rate = mean(g$ev), stringsAsFactors = FALSE)
  }))
}))
write_xlsx_simple(
  cbind(evt_tab, Note = cut_note),
  file.path(tbl_dir, "Table S18. Risk-score strata with locked cutoffs.xlsx"),
  paste0("Table S18. Risk-score strata (", cut_note, ")")
)

save_pdf(file.path(fig_dir, "Figure 15. Joint risk-score tertile Kaplan-Meier three endpoints.pdf"), {
  op <- par(mfrow = c(1, 3), family = if (grepl("Times", font_family)) "Times" else font_family)
  for (ep in c("OS", "PFS", "DM")) {
    d <- .npc_endpoint_df(dfB, ep)
    d$g <- risk_grp
    d <- d[!is.na(d$g), ]
    d$ev <- if (ep == "DM") as.integer(d$cause == 1) else as.integer(d$cause > 0)
    sf <- survfit(Surv(time, ev) ~ g, data = d)
    plot(sf, col = c("#4C78A8", "#F58518", "#E45756"), lwd = 2, mark.time = FALSE,
         xlab = "Months", ylab = "Event-free",
         main = paste0(ep, if (use_locked) " (cuts 45.9/58.71)" else " (tertiles)"))
    legend("bottomleft", legend = c("Low", "Mid", "High"), col = c("#4C78A8", "#F58518", "#E45756"),
           lwd = 2, bty = "n", cex = 0.75)
  }
  par(op)
}, 11, 4)
write_md("Figure 15. Joint risk-score tertile Kaplan-Meier three endpoints",
         paste0("联合风险评分三分层 KM。", cut_note),
         paste0("口径 B N=", nrow(dfB)))

# ===========================================================================
# 10) Methods 加长 + NUMBERING 更新
# ===========================================================================
.message("Methods + numbering...")
dm_line <- if (nrow(pair_df)) pair_df[pair_df$Reference == "C", ][1, ] else NULL
methods <- c(
  "# Methods (statistical analysis)",
  "",
  "## Cohorts and endpoints",
  paste0("Cohort A included all extracted cases (N = ", nrow(dfA), ", including M1). ",
         "Cohort B was the non-metastatic analytic set (N = ", nrow(dfB), "; include==1). ",
         "Five endpoints were analysed: OS, PFS, distant metastasis with competing death (DM), ",
         "distant metastasis or death (DM+D), and locoregional failure with competing events (LR)."),
  "",
  "## EBV DNA scientific coding",
  "Case-level assay thresholds (LOD) were retained. Records were classified as BLQ (left-censored), ZERO, SUBLOD (positive below LOD), Q (at/above LOD), or MISSING (Table S1/S1b/S10). ",
  "Primary relative load was v/LOD with score log10(1+v/LOD); BLQ/ZERO mapped to 0 while retaining the left-censor upper bound as a sensitivity encoding. ",
  "Trapezoidal cumulative load assumed T0=0, T1=2, T2=4 months (AUC = logT0+2·logT1+logT2 if T1 observed; otherwise 2·(logT0+logT2)). T2 residual and log-drop were derived similarly.",
  "",
  "## Nested models",
  "Cohort B baseline nested ridge-Cox models: C (clinical + LOD category), E (+T0 flag/score), P2 (+primary MTV and nodal SUVmax), P6 (+extended PET), EP2/EP6 (joint). ",
  "Cohort A descriptive M0–M4 models added cumulative load, T2 residual, trajectory tiers, PET block, and EBV×PET interaction (Table S16 / Figure S2).",
  "",
  "## Validation and incremental value",
  paste0("Primary validation used repeated ", n_repeats, "×5-fold event-stratified out-of-fold linear predictors with 36-month IPCW AUC (timeROC; competing-risk AUC_1 for DM/LR) and an IPCW-style Brier score. ",
         "Paired ΔAUC and ΔBrier used bootstrap resampling of fixed OOF predictions (Table 3). ",
         "Unpenalized nested Cox likelihood-ratio tests evaluated incremental blocks on the clinical base (Table S11)."),
  if (!is.null(dm_line)) sprintf(
    "Headline DM OOF contrast EP2 versus C: AUC %.3f → %.3f (Δ=%.3f, 95%% CI %.3f to %.3f); ΔBrier %.4f (95%% CI %.4f to %.4f).",
    dm_line$AUC_ref, dm_line$AUC_new, dm_line$Delta_AUC, dm_line$AUC_CI_low, dm_line$AUC_CI_high,
    dm_line$Delta_Brier, dm_line$Brier_CI_low, dm_line$Brier_CI_high
  ) else "",
  "",
  "## Competing risks",
  "For DM and LR, cause-specific Cox models censored competing events; Fine–Gray subdistribution hazards were reported in parallel (Table S13). ",
  "Absolute risks used Aalen–Johansen / cmprsk cumulative incidence at 12–60 months (Table S12; Figure S1).",
  "",
  "## Interaction, landmarks, and decision analysis",
  "EBV-high × PET-high quadrants used external PET cut-offs TLG>65 or NTR>0.64. Risk-scale RERI was reported. ",
  "Landmarks at 6/9/12 months evaluated T2/trajectory increments; the IC subcohort evaluated T1×PET increments after the 9-month landmark (Table S15). ",
  "Decision curves compared OOF risk proxies across nested models at 2%–30% thresholds (Figure S3 / Table S4). Temporal holdout used diagnosis year ≤2022 for training and 2023–2025 for testing.",
  "",
  "## Sensitivities",
  "Sensitivities covered BLQ=LOD/2, left-censor upper-bound coding, strict detectability, any-positive quantitative labelling, unified LOD 5000, exclusion of LOD=5000 cases, III–IVA restriction, TLG discrepancy exclusion / formula replacement, trajectory leakage control, and deletion of selected T1-positive PFS cases (Table S6 / Figure 19).",
  "",
  "## Partial correlation and risk strata",
  "Partial Spearman correlations residualized ranks for age, sex, T, N, and LOD (Table S17). ",
  paste0("Risk-score strata used ", if (use_locked) "locked cut-offs 45.9 and 58.71" else "tertiles with disclosure when score scale differed from the report", " (Table S18 / Figure 15)."),
  "",
  "## Software",
  paste0("Analyses used R ", getRversion(), " with survival, glmnet, timeROC, cmprsk, ggplot2, and openxlsx. Figure/table fonts used Times New Roman (Times fallback). ",
         "Figures 1–20 follow the analysis-report numbering; all values were recomputed from case-level data (not screenshots).")
)
writeLines(methods, file.path(out_root, "Methods_statistical_analysis.md"), useBytes = TRUE)

pkgs <- c("survival", "glmnet", "timeROC", "ggplot2", "openxlsx", "cmprsk")
writeLines(c(sprintf("R\t%s", getRversion()),
             vapply(pkgs, function(p) sprintf("%s\t%s", p, if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "NA"), character(1))),
           file.path(out_root, "Methods_software_versions.txt"), useBytes = TRUE)

guide <- readLines(file.path(out_root, "NUMBERING_AND_ROLE.md"), warn = FALSE, encoding = "UTF-8")
guide <- c(guide,
  "",
  "## 本次补齐（方案缺口）",
  "- Table S1b / S10：记录类型普查与 SUBLOD 专表",
  "- Table S6 / Figure 19：敏感性全家桶（含 BLQ=LOD/2、上界、任意正定量、R-D 泄漏等）",
  "- Table 3：ΔAUC **与 ΔBrier**",
  "- Table S11：嵌套似然比",
  "- Table S12–S13：CIF 绝对风险 + Fine–Gray vs 原因特异",
  "- Table S14–S15：梯形累积负荷 + IC 后 T1×PET",
  "- Table S16 / Figure S2：口径 A M0–M4",
  "- Figure S3：DCA 跨模型净获益主图",
  "- Table S17：偏秩相关",
  "- Table S18 / Figure 15：风险切点（锁定 45.9/58.71 或披露）",
  "- Methods：加长至可审稿规格；重复旧表文件已删除"
)
writeLines(guide, file.path(out_root, "NUMBERING_AND_ROLE.md"), useBytes = TRUE)
file.copy(file.path(out_root, "NUMBERING_AND_ROLE.md"),
          file.path(root, "reports/npc_ebv_pet_summary_new_numbering.md"), overwrite = TRUE)

if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
  source(file.path(root, "R/pub_figure_export.R"))
  tryCatch(pub_figure_ensure_formats(file.path(out_root, "Figures"),
                                     config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))),
           error = function(e) .message("ensure_formats: %s", e$message))
}

.message("DONE fill-gaps. Tables now:")
.message("%s", paste(list.files(tbl_dir), collapse = "\n"))
invisible(TRUE)
