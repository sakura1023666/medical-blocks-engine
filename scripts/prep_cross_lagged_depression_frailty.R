#!/usr/bin/env Rscript
# scripts/prep_cross_lagged_depression_frailty.R
# Depression × Frailty Index（交叉滞后 PMID 40595747 套路改编）
#
# 暴露：FI（ELSA 剔除 CES-D/psced 条目后重算，避免与结局内容重叠）
# 结局：Depression / No_Depression（来自 medition CES-D DN；FI/抑郁均不插补，缺失直接删）
# 基线波（横断面 Table 1，兼顾可合并 n 与 FI–抑郁分离）：
#   CHARLS 2011 | ELSA wave4(2008) | HRS 2012
#
# Usage:
#   Rscript scripts/prep_cross_lagged_depression_frailty.R
#   Rscript scripts/prep_cross_lagged_depression_frailty.R --study-root /path

suppressPackageStartupMessages({
  if (requireNamespace("dplyr", quietly = TRUE)) library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
study_root <- "/mnt/e/01block/01Block-new-Final/Output/22_depression_cross-laged_40595747"
if ("--study-root" %in% args) {
  i <- match("--study-root", args)
  study_root <- args[[i + 1L]]
}
if (!dir.exists(dirname(study_root))) {
  stop("study_root parent missing: ", study_root)
}
dir.create(study_root, recursive = TRUE, showWarnings = FALSE)

hip_raw <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data"
dep_raw <- "/mnt/g/02block_result/22_depression/cross-laged_40595747/data"
out <- file.path(study_root, "data", "harmonized")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

to_id <- function(x) as.character(as.vector(x))

load_df <- function(path, obj = NULL) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (is.null(obj)) {
    nms <- ls(e)
    if (length(nms) != 1L) {
      stop("期望单对象: ", path, " 有 ", paste(nms, collapse = ","))
    }
    obj <- nms[[1L]]
  }
  as.data.frame(e[[obj]])
}

recode_outcome <- function(dn) {
  dn <- suppressWarnings(as.integer(as.character(dn)))
  ifelse(
    is.na(dn), NA_character_,
    ifelse(dn == 1L, "Depression",
           ifelse(dn == 0L, "No_Depression", NA_character_))
  )
}

fi_p <- function(fi, y) {
  ok <- !is.na(fi) & !is.na(y)
  if (sum(ok) < 10L) return(NA_real_)
  suppressWarnings(wilcox.test(fi[ok] ~ factor(y[ok]))$p.value)
}

# ELSA：只保留近似 0/1 的非情绪缺损条目，重算 FI（剔除 psced / depression）
elsa_fi_mood_free <- function(fr) {
  ps <- grep("^psced", names(fr), ignore.case = TRUE, value = TRUE)
  skip <- unique(c(
    ps, "idauniq", "ID", "trig", "hdl", "Trig", "HDL",
    "AIP", "FI", "AIP_FI", "depression"
  ))
  keep <- setdiff(names(fr), skip)
  ok_keep <- vapply(keep, function(cn) {
    x <- suppressWarnings(as.numeric(as.character(fr[[cn]])))
    x <- x[is.finite(x)]
    if (!length(x)) return(FALSE)
    all(x >= 0 & x <= 1) && mean(x %in% c(0, 1)) > 0.85
  }, logical(1))
  keep <- keep[ok_keep]
  if (length(keep) < 10L) {
    stop("ELSA mood-free FI: 可用缺损列过少 (", length(keep), ")")
  }
  mm <- as.matrix(data.frame(lapply(fr[keep], function(z) {
    as.numeric(as.character(z))
  })))
  list(FI = rowMeans(mm, na.rm = TRUE), items = keep)
}

qc_row <- function(cohort, dabiao, note = "") {
  data.frame(
    cohort = cohort,
    n = nrow(dabiao),
    n_event = sum(dabiao$Disease_Group == "Depression", na.rm = TRUE),
    prev = mean(dabiao$Disease_Group == "Depression", na.rm = TRUE),
    fi_mean = mean(dabiao$FI, na.rm = TRUE),
    fi_mean_ctrl = mean(dabiao$FI[dabiao$Disease_Group == "No_Depression"], na.rm = TRUE),
    fi_mean_case = mean(dabiao$FI[dabiao$Disease_Group == "Depression"], na.rm = TRUE),
    frailty_prev = mean(dabiao$Frailty, na.rm = TRUE),
    fi_p_vs_outcome = fi_p(dabiao$FI, dabiao$Disease_Group),
    note = note,
    stringsAsFactors = FALSE
  )
}

finalize_dabiao <- function(bl, fi_df, dep_df, cohort) {
  dabiao <- bl %>%
    inner_join(fi_df, by = "ID") %>%
    inner_join(dep_df, by = "ID")
  dabiao$Disease_Group <- recode_outcome(dabiao$DN)
  # 铁律：FI 与抑郁缺失一律剔除，禁止进 MICE
  n0 <- nrow(dabiao)
  dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), , drop = FALSE]
  dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
  # 不把 CES-D 条目留在协变量池
  drop_cols <- intersect(
    c(
      "DN", "cesd10_total", "cesd8_total",
      paste0("dc0", sprintf("%02d", 9:18)),
      paste0("dc", 9:18),
      grep("^psced|^PSced|^[KLMNOPQR]D11", names(dabiao), value = TRUE)
    ),
    names(dabiao)
  )
  if (length(drop_cols)) {
    dabiao <- dabiao[, setdiff(names(dabiao), drop_cols), drop = FALSE]
  }
  attr(dabiao, "n_before_complete_fi_dep") <- n0
  attr(dabiao, "n_dropped_fi_or_dep_na") <- n0 - nrow(dabiao)
  dabiao
}

# ── CHARLS 2011：髋部课题 frailty26（不含 CES-D 条目）+ medition 抑郁 ─────────
bl <- load_df(
  file.path(dep_raw, "charls/D01_baseline_CHARLS_2011_0813 (1).RData"),
  "baseline"
)
bl$ID <- to_id(bl$ID)
fr <- read.csv(
  file.path(hip_raw, "CHARLS/虚弱_charls_2011.csv"),
  check.names = FALSE
)
fr$ID <- to_id(fr$ID)
if (!"FI" %in% names(fr)) {
  if (!"frailty26_total" %in% names(fr)) stop("CHARLS 虚弱缺 FI/frailty26_total")
  fr$FI <- fr$frailty26_total / 26
}
dep <- read.csv(
  file.path(hip_raw, "medition/CHARLS_2011_抑郁_fixed.csv"),
  check.names = FALSE
)
dep$ID <- to_id(dep$ID)
dabiao_charls <- finalize_dabiao(
  bl,
  fr[, c("ID", "FI"), drop = FALSE],
  dep[, c("ID", "DN", "cesd10_total"), drop = FALSE],
  "CHARLS"
)
dabiao <- dabiao_charls
save(dabiao, file = file.path(out, "D04_CHARLS_depression_baseline.RData"))

# ── ELSA wave4：去 psced 重算 FI + medition wave4 抑郁 ───────────────────────
bl <- load_df(
  file.path(dep_raw, "elsa/D01_baseline_ELSA4_2008_0813.RData"),
  "baseline"
)
bl$ID <- to_id(bl$ID)
fr <- read.csv(
  file.path(hip_raw, "ELSA/虚弱_elsa_wave4.csv"),
  check.names = FALSE
)
fr$ID <- to_id(fr$idauniq)
fi_e <- elsa_fi_mood_free(fr)
fr$FI <- fi_e$FI
dep <- read.csv(
  file.path(hip_raw, "medition/ELSA_wave4_抑郁.csv"),
  check.names = FALSE
)
dep$ID <- to_id(dep$idauniq)
dabiao_elsa <- finalize_dabiao(
  bl,
  fr[, c("ID", "FI"), drop = FALSE],
  dep[, c("ID", "DN", "cesd8_total"), drop = FALSE],
  "ELSA"
)
dabiao <- dabiao_elsa
save(dabiao, file = file.path(out, "D04_ELSA_depression_baseline.RData"))
writeLines(
  c(
    "ELSA FI = mean of binary deficit items EXCLUDING CES-D (psced*) / depression column.",
    paste("items:", paste(fi_e$items, collapse = ", "))
  ),
  file.path(out, "ELSA_FI_mood_free_items.txt")
)

# ── HRS 2012：虚弱 FI（条目为健康/功能，非 CES-D）+ medition 抑郁 ───────────
bl <- load_df(
  file.path(dep_raw, "hrs/D01_baseline_HRS_2012_0813.RData"),
  "baseline"
)
bl$ID <- to_id(bl$ID)
fr <- read.csv(
  file.path(hip_raw, "HRS/虚弱_hrs_2012.csv"),
  check.names = FALSE
)
fr$ID <- to_id(fr$hhidpn)
if (!"FI" %in% names(fr)) stop("HRS 虚弱缺 FI")
dep <- read.csv(
  file.path(hip_raw, "medition/HRS_2012_抑郁.csv"),
  check.names = FALSE
)
dep$ID <- to_id(as.numeric(dep$HHID) * 1000 + as.numeric(dep$PN))
# 若 *1000 对不上则回退拼接（极少）
if (length(intersect(fr$ID, dep$ID)) < 1000L) {
  dep$ID <- paste0(to_id(dep$HHID), to_id(dep$PN))
}
dabiao_hrs <- finalize_dabiao(
  bl,
  fr[, c("ID", "FI"), drop = FALSE],
  dep[, c("ID", "DN", "cesd8_total"), drop = FALSE],
  "HRS"
)
dabiao <- dabiao_hrs
save(dabiao, file = file.path(out, "D04_HRS_depression_baseline.RData"))

qc <- rbind(
  qc_row("CHARLS", dabiao_charls, "baseline=2011; FI=hip frailty26 (no CES-D items)"),
  qc_row("ELSA", dabiao_elsa, paste0("baseline=wave4; FI=mood-free (", length(fi_e$items), " items)")),
  qc_row("HRS", dabiao_hrs, "baseline=2012; FI=hip frailty file; dep ID=HHID*1000+PN")
)
write.csv(qc, file.path(out, "prep_qc.csv"), row.names = FALSE)

wave_plan <- c(
  "# Longitudinal wave plan (after Table 1; maximize waves with clean FI+depression)",
  "# Cross-sectional Table1 baselines locked above.",
  "#",
  "# CHARLS FI: 2011 / 2013 / 2015 (depression project CSVs; prefer hip-style FI without CES-D)",
  "# CHARLS depression: 2011 / 2013 / 2015 / 2018 / 2020 (hip medition)",
  "# ELSA FI mood-free: wave2 / 4 / 6 / 8 (hip 虚弱_elsa_wave*); depression medition wave3–7",
  "# HRS FI: 2006–2020 even years (hip 虚弱_hrs_*); depression medition 2006–2020",
  "#",
  "# Primary long (align hip spacing ~2y):",
  "#   CHARLS: FI_2011 → Dep_2013 → Dep_2015 (or FI change 2011→2015)",
  "#   ELSA:   FI_w4 → Dep_w5 → Dep_w6",
  "#   HRS:    FI_2012 → Dep_2014 → Dep_2016",
  "# Extra waves only if complete-case FI+Dep still yields stable models."
)
writeLines(wave_plan, file.path(out, "WAVE_PLAN.md"))

message("Wrote harmonized dabiao + prep_qc to ", out)
print(qc)
