#!/usr/bin/env Rscript
# 构建脓毒症∩AKI 分析 dabiao（Age≥18；stay 与结局对齐）
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/ml_tcf_sepsis_aki/01_prepare_analytic_dabiao.R

suppressPackageStartupMessages({
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = "") {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) args[[i + 1L]] else default
}

proj <- get_arg(
  "--project",
  "G:/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871"
)
# WSL fallback
if (!dir.exists(proj) && dir.exists("/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871")) {
  proj <- "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871"
}

data_dir <- file.path(proj, "data")
out_data <- file.path(proj, "Data")
dir.create(file.path(out_data, "mimic"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_data, "eicu"), recursive = TRUE, showWarnings = FALSE)

# Windows R path for RData in cache if G: slow
cache <- "E:/01block/01Block-new-Final/.cache/tmp_rdata"
mim_rdata <- file.path(data_dir, "mimic", "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
eic_rdata <- file.path(data_dir, "eicu", "D01_baseline_EICU_ICU_first_0626.RData")
if (!file.exists(mim_rdata) && file.exists(file.path(cache, "D01_mimic.RData"))) {
  mim_rdata <- file.path(cache, "D01_mimic.RData")
  eic_rdata <- file.path(cache, "D01_eicu.RData")
}

load_df <- function(path) {
  e <- new.env()
  load(path, envir = e)
  e$baseline
}

message("Loading baselines…")
mim <- as.data.table(load_df(mim_rdata))
eic <- as.data.table(load_df(eic_rdata))
ids_m <- fread(file.path(data_dir, "mimic", "mimic_icu_sepsis_aki_ids.csv"))
ids_e <- fread(file.path(data_dir, "eicu", "eicu_sepsis_aki_ids.csv"))
out_m <- fread(file.path(data_dir, "mimic", "mimic预后数据-all.csv"))
out_e <- fread(file.path(data_dir, "eicu", "EICU预后数据-all.csv"))

# MIMIC: SA-AKI stays present in outcome; one earliest stay per subject
m_stay <- merge(ids_m, out_m, by = c("subject_id", "stay_id", "hadm_id"), all = FALSE)
m_stay <- m_stay[order(stay_id)][, .SD[1], by = subject_id]
mim2 <- merge(mim, m_stay, by.x = "ID", by.y = "subject_id", all = FALSE)
mim2 <- mim2[is.na(Age) | Age >= 18]
mim2[, `:=`(
  DN = as.integer(death_within_hosp_28days == 1),
  fustatus = as.integer(death_within_hosp_28days == 1),
  futime = pmin(as.numeric(hosp_survival_day), 28, na.rm = FALSE)
)]
# NLR/PLR/LMR/PAR/SI if components exist
if (all(c("NeutrophilCount", "Lymphocytes") %in% names(mim2))) {
  mim2[, NLR := NeutrophilCount / pmax(Lymphocytes, 1e-6)]
}
if (all(c("PlateletCount", "Lymphocytes") %in% names(mim2))) {
  mim2[, PLR := PlateletCount / pmax(Lymphocytes, 1e-6)]
}
if (all(c("Lymphocytes") %in% names(mim2)) && "Monocyte" %in% names(mim2)) {
  mim2[, LMR := Lymphocytes / pmax(Monocyte, 1e-6)]
}
if (all(c("PlateletCount", "Albumin") %in% names(mim2))) {
  mim2[, PAR := PlateletCount / pmax(Albumin, 1e-6)]
}
if (all(c("HR", "NBPS") %in% names(mim2))) {
  mim2[, SI := HR / pmax(NBPS, 1e-6)]
}
mim2 <- mim2[!is.na(DN)]
message("MIMIC analytic n=", nrow(mim2), " events=", sum(mim2$DN == 1L))

# eICU
ee <- merge(eic, out_e, by.x = "ID", by.y = "patientunitstayid", all = FALSE)
ee <- ee[ID %in% ids_e$patientunitstayid]
ee <- ee[is.na(Age) | Age >= 18]
ee[, DN := as.integer(
  tolower(as.character(hospdischargestatus)) == "expired" &
    !is.na(hosplosday) & hosplosday <= 28
)]
if (all(c("NeutrophilCount", "Lymphocytes") %in% names(ee))) {
  ee[, NLR := NeutrophilCount / pmax(Lymphocytes, 1e-6)]
}
if (all(c("PlateletCount", "Lymphocytes") %in% names(ee))) {
  ee[, PLR := PlateletCount / pmax(Lymphocytes, 1e-6)]
}
if (all(c("PlateletCount", "Albumin") %in% names(ee))) {
  ee[, PAR := PlateletCount / pmax(Albumin, 1e-6)]
}
if (all(c("HR", "NBPS") %in% names(ee))) {
  ee[, SI := HR / pmax(NBPS, 1e-6)]
}
ee <- ee[!is.na(DN)]
message("eICU analytic n=", nrow(ee), " events=", sum(ee$DN == 1L))

dabiao <- as.data.frame(mim2)
save(dabiao, file = file.path(out_data, "mimic", "D04_dabiao.RData"))
dabiao <- as.data.frame(ee)
save(dabiao, file = file.path(out_data, "eicu", "D04_dabiao.RData"))

fwrite(mim2, file.path(out_data, "mimic", "analytic_sa_aki.csv"))
fwrite(ee, file.path(out_data, "eicu", "analytic_sa_aki.csv"))
message("Wrote Data/mimic|eicu/D04_dabiao.RData")
