#!/usr/bin/env Rscript
# 向 ELSA 骨质疏松 cum×k-means 宽表追加 BRI / RFM / LAP 双波列
# 成分来自 D01_baseline ELSA4(W4=t1) / ELSA6(W6=t2)；公式对齐 Blocks/00_index/01block_index.R
# 用法:
#   Rscript run/cum_egdr_kmeans_ckm/prepare_elsa_add_bri_rfm_lap.R

suppressPackageStartupMessages({
  if (!requireNamespace("data.table", quietly = TRUE)) stop("需要 data.table")
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("需要 dplyr（RFM/LAP case_when）")
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

.load_bl <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  as.data.table(e$baseline)
}

.calc_wave <- function(df) {
  WC <- as.numeric(df$Waist_circumference)
  Ht <- as.numeric(df$Height)
  TG <- as.numeric(df$TG)
  sex <- as.character(df$Gender)
  ratio <- (WC / (2 * pi)) / (0.5 * Ht)
  inside <- pmax(0, 1 - ratio^2)
  BRI <- 364.2 - 365.5 * sqrt(inside)
  RFM <- dplyr::case_when(
    sex == "Male" ~ 64 - 20 * (Ht / WC),
    sex == "Female" ~ 76 - 20 * (Ht / WC),
    TRUE ~ NA_real_
  )
  LAP <- dplyr::case_when(
    sex == "Male" ~ (WC - 65) * TG / 88.57,
    sex == "Female" ~ (WC - 85) * TG / 88.57,
    TRUE ~ NA_real_
  )
  data.table(
    ID = as.character(df$ID),
    BRI = BRI,
    RFM = RFM,
    LAP = LAP,
    Height = Ht,
    Weight = as.numeric(df$Weight)
  )
}

d4 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA4_2008_0813.RData"))
d6 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA6_2012_0813.RData"))
i4 <- .calc_wave(d4)
i6 <- .calc_wave(d6)
setnames(i4, c("BRI", "RFM", "LAP", "Height", "Weight"),
         c("BRI_t1", "RFM_t1", "LAP_t1", "Height_w4", "Weight_w4"))
setnames(i6, c("BRI", "RFM", "LAP", "Height", "Weight"),
         c("BRI_t2", "RFM_t2", "LAP_t2", "Height", "Weight"))

wide <- data.table::fread(wide_path, showProgress = FALSE)
wide[, ID := as.character(ID)]
drop_old <- intersect(
  c("BRI_t1", "BRI_t2", "cum_BRI", "RFM_t1", "RFM_t2", "cum_RFM",
    "LAP_t1", "LAP_t2", "cum_LAP", "Height", "Weight", "Height_w4", "Weight_w4"),
  names(wide)
)
if (length(drop_old)) wide[, (drop_old) := NULL]

wide <- merge(wide, i4, by = "ID", all.x = TRUE)
wide <- merge(wide, i6, by = "ID", all.x = TRUE)
wide[, cum_BRI := (BRI_t1 + BRI_t2) / 2 * cum_mult]
wide[, cum_RFM := (RFM_t1 + RFM_t2) / 2 * cum_mult]
wide[, cum_LAP := (LAP_t1 + LAP_t2) / 2 * cum_mult]

data.table::fwrite(wide, wide_path)

# 刷新 dual-wave 可算池（free_t1=TRUE 且结局非缺失）
ok_base <- !is.na(wide$Osteoporosis) & (wide$free_t1 %in% TRUE)
pool <- rbindlist(lapply(c("BRI", "RFM", "LAP"), function(ix) {
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
  old <- old[!index %in% c("BRI", "RFM", "LAP")]
  pool_all <- rbind(old, pool)
} else {
  pool_all <- pool
}
data.table::fwrite(pool_all, old_pool_path)

message(sprintf(
  "已写入 %s；BRI dual=%d RFM dual=%d LAP dual=%d；nrow=%d ncol=%d",
  wide_path,
  sum(is.finite(wide$BRI_t1) & is.finite(wide$BRI_t2)),
  sum(is.finite(wide$RFM_t1) & is.finite(wide$RFM_t2)),
  sum(is.finite(wide$LAP_t1) & is.finite(wide$LAP_t2)),
  nrow(wide), ncol(wide)
))
print(pool)
