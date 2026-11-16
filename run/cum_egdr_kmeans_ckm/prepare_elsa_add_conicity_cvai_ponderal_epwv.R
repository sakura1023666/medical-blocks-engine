#!/usr/bin/env Rscript
# 向 ELSA 骨质疏松 cum×k-means 宽表追加 Conicity / CVAI / Ponderal / ePWV 双波列
# 公式对齐 Blocks/00_index/01block_index.R（ePWV：NBPS/NBPD → MBP）
# 用法:
#   Rscript run/cum_egdr_kmeans_ckm/prepare_elsa_add_conicity_cvai_ponderal_epwv.R

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
IDX <- c("Conicity", "CVAI", "Ponderal", "ePWV")

.load_bl <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  as.data.table(e$baseline)
}

.calc_wave <- function(df) {
  WC <- as.numeric(df$Waist_circumference)
  Ht <- as.numeric(df$Height)
  Wt <- as.numeric(df$Weight)
  BMI <- as.numeric(df$BMI)
  Age <- as.numeric(df$Age)
  TG <- as.numeric(df$TG)
  HDL <- as.numeric(df$HDL)
  sex <- as.character(df$Gender)
  SBP <- as.numeric(df$NBPS)
  DBP <- as.numeric(df$NBPD)

  Ht_m <- Ht / 100
  Conicity <- (WC / 100) / (0.109 * sqrt(Wt / Ht_m))
  Ponderal <- Wt / (Ht_m^3)
  TG_mmol <- TG / 88.57
  HDL_mmol <- HDL / 38.67
  CVAI <- dplyr::case_when(
    sex == "Male" ~
      -267.93 + 0.68 * Age + 0.03 * BMI + 4 * WC +
      22 * log10(TG_mmol) - 16.32 * HDL_mmol,
    sex == "Female" ~
      -187.32 + 1.71 * Age + 4.23 * BMI + 1.12 * WC +
      39.76 * log10(TG_mmol) - 11.66 * HDL_mmol,
    TRUE ~ NA_real_
  )
  MBP <- DBP + 0.4 * (SBP - DBP)
  ePWV <- 9.587 - 0.402 * Age + 0.00456 * Age^2 -
    0.00002621 * Age^2 * MBP + 0.003176 * Age * MBP - 0.01832

  data.table(
    ID = as.character(df$ID),
    Conicity = Conicity,
    CVAI = CVAI,
    Ponderal = Ponderal,
    ePWV = ePWV
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
drop_old <- grep(
  paste0("^(", paste(IDX, collapse = "|"), ")(_t[12]|)$|^cum_(", paste(IDX, collapse = "|"), ")$"),
  names(wide), value = TRUE
)
# also drop bare if any
drop_old <- unique(c(
  drop_old,
  unlist(lapply(IDX, function(ix) c(paste0(ix, "_t1"), paste0(ix, "_t2"), paste0("cum_", ix))))
))
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
  pool_all <- rbind(old, pool)
} else {
  pool_all <- pool
}
data.table::fwrite(pool_all, old_pool_path)

message(sprintf("已写入 %s；nrow=%d ncol=%d", wide_path, nrow(wide), ncol(wide)))
print(pool)
