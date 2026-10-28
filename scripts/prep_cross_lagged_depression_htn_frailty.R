#!/usr/bin/env Rscript
# 抑郁人群 × 高血压结局 × 虚弱(FI) — 交叉滞后（对齐 PMID 40595747 表图套路）
#
# 分析集：基线 CES-D 抑郁阳性
# 暴露：FI（剔除高血压/血压诊断条目 + ELSA 再剔 CES-D，避免与结局/入组重叠）
# 结局：Disease_Group = Hypertension / No_Hypertension
# FI 与结局不插补（缺失 listwise）
#
# Usage:
#   Rscript scripts/prep_cross_lagged_depression_htn_frailty.R
#   Rscript scripts/prep_cross_lagged_depression_htn_frailty.R --study-root /path

suppressPackageStartupMessages({
  if (requireNamespace("dplyr", quietly = TRUE)) library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
study_root <- "/mnt/e/01block/01Block-new-Final/Output/22_depression_cross-laged_40595747"
if ("--study-root" %in% args) {
  study_root <- args[[match("--study-root", args) + 1L]]
}
dir.create(study_root, recursive = TRUE, showWarnings = FALSE)

hip_raw <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data"
dep_raw <- "/mnt/g/02block_result/22_depression/cross-laged_40595747/data"
out <- file.path(study_root, "data", "harmonized")
med_out <- file.path(study_root, "data", "medition")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
dir.create(med_out, recursive = TRUE, showWarnings = FALSE)
for (db in c("CHARLS", "ELSA", "HRS")) {
  dir.create(file.path(study_root, "data", db), recursive = TRUE, showWarnings = FALSE)
}

to_id <- function(x) as.character(as.vector(x))
yes_no <- function(x) {
  s <- trimws(as.character(x))
  ifelse(s %in% c("Yes", "1", "TRUE", "True"), TRUE,
         ifelse(s %in% c("No", "0", "FALSE", "False"), FALSE, NA))
}

load_df <- function(path, obj = NULL) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (is.null(obj)) obj <- ls(e)[[1L]]
  as.data.frame(e[[obj]])
}

fi_from_deficits <- function(fr, skip_cols) {
  keep <- setdiff(names(fr), skip_cols)
  ok <- vapply(keep, function(cn) {
    x <- suppressWarnings(as.numeric(as.character(fr[[cn]])))
    x <- x[is.finite(x)]
    if (!length(x)) return(FALSE)
    all(x >= 0 & x <= 1) && mean(x %in% c(0, 1)) > 0.85
  }, logical(1))
  keep <- keep[ok]
  if (length(keep) < 8L) stop("FI deficits too few: ", length(keep))
  mm <- as.matrix(data.frame(lapply(fr[keep], function(z) as.numeric(as.character(z)))))
  list(FI = as.numeric(rowMeans(mm, na.rm = TRUE)), items = keep)
}

fi_p <- function(fi, y) {
  ok <- !is.na(fi) & !is.na(y)
  if (sum(ok) < 10L) return(NA_real_)
  suppressWarnings(wilcox.test(fi[ok] ~ factor(y[ok]))$p.value)
}

recode_htn <- function(ht) {
  yn <- yes_no(ht)
  ifelse(is.na(yn), NA_character_,
         ifelse(yn, "Hypertension", "No_Hypertension"))
}

qc_row <- function(cohort, dabiao, note = "") {
  data.frame(
    cohort = cohort,
    n = nrow(dabiao),
    n_event = sum(dabiao$Disease_Group == "Hypertension", na.rm = TRUE),
    prev = mean(dabiao$Disease_Group == "Hypertension", na.rm = TRUE),
    fi_mean = mean(dabiao$FI, na.rm = TRUE),
    fi_mean_ctrl = mean(dabiao$FI[dabiao$Disease_Group == "No_Hypertension"], na.rm = TRUE),
    fi_mean_case = mean(dabiao$FI[dabiao$Disease_Group == "Hypertension"], na.rm = TRUE),
    frailty_prev = mean(dabiao$Frailty, na.rm = TRUE),
    fi_p_vs_outcome = fi_p(dabiao$FI, dabiao$Disease_Group),
    note = note,
    stringsAsFactors = FALSE
  )
}

# 拷贝抑郁 CSV 到本课题 medition（纵向中介用连续 CES-D）
med_src <- file.path(hip_raw, "medition")
for (f in list.files(med_src, pattern = "抑郁", full.names = TRUE)) {
  file.copy(f, file.path(med_out, basename(f)), overwrite = TRUE)
}

# ── CHARLS 2011：抑郁人群；FI = frailty26 去掉 hibpe ─────────────────────────
bl <- load_df(file.path(dep_raw, "charls/D01_baseline_CHARLS_2011_0813 (1).RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- read.csv(file.path(hip_raw, "CHARLS/虚弱_charls_2011.csv"), check.names = FALSE)
fr$ID <- to_id(fr$ID)
skip_c <- c(
  "ID", "hibpe", "frailty26_total", "newtg", "newhdl", "AIP", "FI", "AIP_FI"
)
fi_c <- fi_from_deficits(fr, skip_c)
fr$FI <- fi_c$FI
dep <- read.csv(file.path(hip_raw, "medition/CHARLS_2011_抑郁_fixed.csv"), check.names = FALSE)
dep$ID <- to_id(dep$ID)
dep <- dep[!is.na(dep$DN) & as.integer(dep$DN) == 1L, c("ID", "DN", "cesd10_total"), drop = FALSE]

dabiao <- bl %>%
  inner_join(fr[, c("ID", "FI"), drop = FALSE], by = "ID") %>%
  inner_join(dep, by = "ID")
dabiao$Disease_Group <- recode_htn(dabiao$Hypertension)
dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), , drop = FALSE]
dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
# 结局列已写入 Disease_Group；协变量池去掉 Hypertension / 抑郁相关
dabiao$Hypertension <- NULL
dabiao$DN <- NULL
dabiao$cesd10_total <- NULL
dabiao_charls <- dabiao
save(dabiao, file = file.path(out, "D04_CHARLS_depression_htn_baseline.RData"))
# 兼容旧文件名（部分脚本扫 D04_*_depression_baseline）
save(dabiao, file = file.path(out, "D04_CHARLS_depression_baseline.RData"))

# 2015 高血压结局（纵向 Y）
bl15 <- load_df(file.path(dep_raw, "charls/D01_baseline_CHARLS_2015_0813.RData"), "baseline")
bl15$ID <- to_id(bl15$ID)
yo <- data.frame(
  ID = bl15$ID,
  Disease_Group = recode_htn(bl15$Hypertension),
  stringsAsFactors = FALSE
)
yo <- yo[!is.na(yo$Disease_Group), , drop = FALSE]
save(yo, file = file.path(study_root, "data/CHARLS/D03_result_CHARLS_2015_htn.RData"))
# long_prepare 默认名
yo_save <- yo
names_env <- new.env(parent = emptyenv())
names_env$dabiao <- yo_save
# 存成单对象 yo
save(yo, file = file.path(study_root, "data/CHARLS/D03_result_CHARLS_2015.RData"))

# ── ELSA wave4：抑郁人群；FI 去 psced + hypertension/BP 诊断 ─────────────────
bl <- load_df(file.path(dep_raw, "elsa/D01_baseline_ELSA4_2008_0813.RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- read.csv(file.path(hip_raw, "ELSA/虚弱_elsa_wave4.csv"), check.names = FALSE)
fr$ID <- to_id(fr$idauniq)
ps <- grep("^psced", names(fr), ignore.case = TRUE, value = TRUE)
skip_e <- unique(c(
  ps, "idauniq", "ID", "trig", "hdl", "Trig", "HDL", "AIP", "FI", "AIP_FI",
  "depression", "hypertension",
  grep("hedacbp|hediabp|bp$", names(fr), ignore.case = TRUE, value = TRUE)
))
fi_e <- fi_from_deficits(fr, skip_e)
fr$FI <- fi_e$FI
dep <- read.csv(file.path(hip_raw, "medition/ELSA_wave4_抑郁.csv"), check.names = FALSE)
dep$ID <- to_id(dep$idauniq)
dep <- dep[!is.na(dep$DN) & as.integer(dep$DN) == 1L, c("ID", "DN", "cesd8_total"), drop = FALSE]

dabiao <- bl %>%
  inner_join(fr[, c("ID", "FI"), drop = FALSE], by = "ID") %>%
  inner_join(dep, by = "ID")
dabiao$Disease_Group <- recode_htn(dabiao$Hypertension)
dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), , drop = FALSE]
dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
dabiao$Hypertension <- NULL
dabiao$DN <- NULL
dabiao$cesd8_total <- NULL
dabiao_elsa <- dabiao
save(dabiao, file = file.path(out, "D04_ELSA_depression_htn_baseline.RData"))
save(dabiao, file = file.path(out, "D04_ELSA_depression_baseline.RData"))
writeLines(
  c("ELSA FI excludes CES-D (psced*) and hypertension/BP diagnosis columns.",
    paste("items:", paste(fi_e$items, collapse = ", "))),
  file.path(out, "ELSA_FI_no_htn_items.txt")
)

# ELSA wave6 HTN outcome
bl6 <- load_df(file.path(dep_raw, "elsa/D01_baseline_ELSA6_2012_0813.RData"), "baseline")
bl6$ID <- to_id(bl6$ID)
yo <- data.frame(ID = bl6$ID, Disease_Group = recode_htn(bl6$Hypertension), stringsAsFactors = FALSE)
yo <- yo[!is.na(yo$Disease_Group), , drop = FALSE]
save(yo, file = file.path(study_root, "data/ELSA/D03_result_ELSA6.RData"))

# ── HRS 2012：抑郁人群；FI 用髋部文件（条目无独立高血压列）────────────────────
bl <- load_df(file.path(dep_raw, "hrs/D01_baseline_HRS_2012_0813.RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- read.csv(file.path(hip_raw, "HRS/虚弱_hrs_2012.csv"), check.names = FALSE)
fr$ID <- to_id(fr$hhidpn)
if (!"FI" %in% names(fr)) stop("HRS 缺 FI")
dep <- read.csv(file.path(hip_raw, "medition/HRS_2012_抑郁.csv"), check.names = FALSE)
dep$ID <- to_id(as.numeric(dep$HHID) * 1000 + as.numeric(dep$PN))
if (length(intersect(fr$ID, dep$ID)) < 1000L) {
  dep$ID <- paste0(to_id(dep$HHID), to_id(dep$PN))
}
dep <- dep[!is.na(dep$DN) & as.integer(dep$DN) == 1L, c("ID", "DN", "cesd8_total"), drop = FALSE]

dabiao <- bl %>%
  inner_join(fr[, c("ID", "FI"), drop = FALSE], by = "ID") %>%
  inner_join(dep, by = "ID")
dabiao$Disease_Group <- recode_htn(dabiao$Hypertension)
dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), , drop = FALSE]
dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
dabiao$Hypertension <- NULL
dabiao$DN <- NULL
dabiao$cesd8_total <- NULL
dabiao_hrs <- dabiao
save(dabiao, file = file.path(out, "D04_HRS_depression_htn_baseline.RData"))
save(dabiao, file = file.path(out, "D04_HRS_depression_baseline.RData"))

# HRS 2016 HTN outcome
bl16 <- load_df(file.path(dep_raw, "hrs/D01_baseline_HRS_2016_0813.RData"), "baseline")
bl16$ID <- to_id(bl16$ID)
yo <- data.frame(ID = bl16$ID, Disease_Group = recode_htn(bl16$Hypertension), stringsAsFactors = FALSE)
yo <- yo[!is.na(yo$Disease_Group), , drop = FALSE]
save(yo, file = file.path(study_root, "data/HRS/D03_result_HRS16.RData"))

writeLines(
  c("CHARLS FI excludes hibpe:", paste(fi_c$items, collapse = ", ")),
  file.path(out, "CHARLS_FI_no_htn_items.txt")
)

qc <- rbind(
  qc_row("CHARLS", dabiao_charls, "depressed-only; FI excl hibpe; outcome=Hypertension"),
  qc_row("ELSA", dabiao_elsa, paste0("depressed-only; FI excl psced+HTN (", length(fi_e$items), " items)")),
  qc_row("HRS", dabiao_hrs, "depressed-only; FI=hip frailty; outcome=Hypertension")
)
write.csv(qc, file.path(out, "prep_qc.csv"), row.names = FALSE)

writeLines(c(
  "# Design: depression population × FI (no HTN items) × Hypertension outcome",
  "# Cross-sectional baselines: CHARLS2011 / ELSA w4 / HRS2012",
  "# Longitudinal (hip spacing):",
  "#   CHARLS: FI_2011 → DepSeverity_2013 → HTN_2015 (baseline HTN-free)",
  "#   ELSA:   FI_w4 → Dep_w5 → HTN_w6",
  "#   HRS:    FI_2012 → Dep_2014 → HTN_2016",
  "# Full table/figure set aligned to hip summary_result MANIFEST"
), file.path(out, "WAVE_PLAN.md"))

message("Wrote depression×HTN×FI dabiao to ", out)
print(qc)
