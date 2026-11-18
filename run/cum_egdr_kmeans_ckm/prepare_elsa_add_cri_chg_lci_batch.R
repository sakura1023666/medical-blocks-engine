#!/usr/bin/env Rscript
# 向 ELSA 骨质疏松 cum×k-means 宽表追加 8 个未跑指标双波列 + cum
# CRI_II / CHG / LCI / TCBI / HGI / HbA1c_HDL_C / sdLDL_C / METS_VF
# 公式对齐 Blocks/00_index/01block_index.R
# 用法:
#   Rscript run/cum_egdr_kmeans_ckm/prepare_elsa_add_cri_chg_lci_batch.R

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
})

.block_result_root <- {
  if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result")
}
proj <- file.path(.block_result_root, "10_osteoporosis", "cum_egdr_kmeans_41654871")
data_dir <- file.path(proj, "data")
wide_path <- file.path(data_dir, "elsa_cum_kmeans_analysis_wide.csv")
rep_dir <- file.path(proj, "reports")
cum_mult <- 4
IDX <- c("CRI_II", "CHG", "LCI", "TCBI", "HGI", "HbA1c_HDL_C", "sdLDL_C", "METS_VF")

.load_bl <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  as.data.table(e$baseline)
}

.calc_wave <- function(df) {
  Age <- as.numeric(df$Age)
  Wt <- as.numeric(df$Weight)
  Ht <- as.numeric(df$Height)
  WC <- as.numeric(df$Waist_circumference)
  TG <- as.numeric(df$TG)
  TC <- as.numeric(df$TC)
  HDL <- as.numeric(df$HDL)
  LDL <- as.numeric(df$LDL)
  Glu <- as.numeric(df$Glucose)
  HbA1c <- as.numeric(df$HbA1c)
  sex <- as.character(df$Gender)
  BMI <- as.numeric(df$BMI)
  if (all(!is.finite(BMI)) || mean(is.finite(BMI)) < 0.5) {
    BMI <- Wt / (Ht / 100)^2
  }

  CRI_II <- LDL / HDL
  CHG <- log(TC * Glu / (2 * HDL))
  # 引擎 LCI：((TC/38.67)*(TG/88.57)*(LDL/38.67))/(HDL/38.67)
  LCI <- ((TC / 38.67) * (TG / 88.57) * (LDL / 38.67)) / (HDL / 38.67)
  TCBI <- TG * TC * Wt / 1000
  HGI <- HbA1c - (0.01 * Glu + 5.04)
  HbA1c_HDL_C <- HbA1c / HDL
  lbLDL_C <- 1.43 * LDL - 0.14 * log(TG) * LDL - 8.99
  sdLDL_C <- LDL - lbLDL_C

  # METSIR → METS_VF（引擎 Gender==1 按 Male=1）
  METSIR <- log((2 * Glu + TG) * (Wt / (Ht / 100)^2)) / log(HDL)
  male <- as.integer(sex == "Male")
  METS_VF <- 4.466 + 0.011 * (log(METSIR))^3 +
    3.239 * (log(WC / Ht))^3 +
    0.319 * male +
    0.594 * log(Age)

  data.table(
    ID = as.character(df$ID),
    CRI_II = CRI_II,
    CHG = CHG,
    LCI = LCI,
    TCBI = TCBI,
    HGI = HGI,
    HbA1c_HDL_C = HbA1c_HDL_C,
    sdLDL_C = sdLDL_C,
    METS_VF = METS_VF
  )
}

d4 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA4_2008_0813.RData"))
d6 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA6_2012_0813.RData"))
i4 <- .calc_wave(d4)
i6 <- .calc_wave(d6)
setnames(i4, IDX, paste0(IDX, "_t1"))
setnames(i6, IDX, paste0(IDX, "_t2"))

wide <- data.table::fread(wide_path, showProgress = FALSE)
wide[, ID := as.character(ID)]
drop_old <- unique(unlist(lapply(IDX, function(ix) {
  c(paste0(ix, "_t1"), paste0(ix, "_t2"), paste0("cum_", ix), ix)
})))
drop_old <- intersect(drop_old, names(wide))
if (length(drop_old)) wide[, (drop_old) := NULL]

wide <- merge(wide, i4, by = "ID", all.x = TRUE)
wide <- merge(wide, i6, by = "ID", all.x = TRUE)
for (ix in IDX) {
  wide[[paste0("cum_", ix)]] <-
    (wide[[paste0(ix, "_t1")]] + wide[[paste0(ix, "_t2")]]) / 2 * cum_mult
}

data.table::fwrite(wide, wide_path)

ok_base <- !is.na(wide$Osteoporosis) & (wide$free_t1 %in% TRUE)
pool <- rbindlist(lapply(IDX, function(ix) {
  t1 <- wide[[paste0(ix, "_t1")]]
  t2 <- wide[[paste0(ix, "_t2")]]
  both <- is.finite(t1) & is.finite(t2)
  free <- both & ok_base
  n_free <- sum(free)
  n_ev <- sum(free & wide$Osteoporosis == 1L, na.rm = TRUE)
  data.table(
    index = ix,
    both = as.integer(sum(both)),
    free_T1 = as.integer(n_free),
    fu = as.integer(n_free),
    lost = 0L,
    events = as.integer(n_ev),
    event_pct = if (n_free > 0) round(100 * n_ev / n_free, 2) else NA_real_
  )
}))
old_pool_path <- file.path(rep_dir, "elsa_only_dualwave_index_pool.csv")
if (file.exists(old_pool_path)) {
  old <- data.table::fread(old_pool_path)
  old <- old[!index %in% IDX]
  pool <- rbind(old, pool, fill = TRUE)
}
dir.create(rep_dir, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(pool, old_pool_path)
message("Wrote ", wide_path)
print(pool[index %in% IDX])
message("ALL DONE")
