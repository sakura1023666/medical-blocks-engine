###############################################################################
# HRS 四波探索 · 累计暴露 × k-means · 新发癌症
# 暴露：2010 + 2012 + 2014 + 2016（完整四波可算）
# 风险起点：2016 及以前无癌 → 结局 2020 新发癌症
# 累计：(mean of 4 waves) × 6；k-means 输入四维时点
# 输出独立目录，不覆盖两波主分析 cum_egdr_kmeans_hrs_cancer/
###############################################################################

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !(length(a) == 1L && is.na(a))) a else b

hrs_bl_dir <- "/mnt/g/02block_result/10_osteoporosis/cum_egdr_kmeans_41654871/data"
cancer_dir <- paste0(
  "/mnt/g/02block_result/58_cancer/Multimorbidity_41083993/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师(1)/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师/资料05-原始数据/hrs"
)
out_dir <- "/mnt/g/02block_result/58_cancer/cum_egdr_kmeans_hrs_cancer_4wave/data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

load_bl <- function(year) {
  f <- file.path(hrs_bl_dir, sprintf("D01_baseline_HRS_%d_0813.RData", year))
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  d <- e$baseline
  d$ID <- as.character(d$ID)
  d
}

load_cancer <- function(year) {
  f <- file.path(cancer_dir, sprintf("癌症_hrs_%d.csv", year))
  d <- utils::read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)
  idc <- intersect(c("hhidpn", "id", "ID"), names(d))[1]
  data.frame(
    ID = as.character(d[[idc]]),
    DN = as.integer(d$DN),
    stringsAsFactors = FALSE
  )
}

to_htn01 <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  ifelse(xc %in% c("1", "yes", "y", "true"), 1,
    ifelse(xc %in% c("0", "no", "n", "false"), 0, NA_real_))
}

yn_factor <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  if (any(xc %in% c("never", "current", "former", "ever"), na.rm = TRUE)) {
    return(factor(
      ifelse(xc %in% c("never", "no", "n", "0"), "No",
        ifelse(is.na(xc) | xc == "", NA_character_, "Yes")),
      levels = c("No", "Yes")
    ))
  }
  v <- to_htn01(x)
  factor(ifelse(v == 1, "Yes", ifelse(v == 0, "No", NA_character_)), levels = c("No", "Yes"))
}

compute_indices <- function(df) {
  WC <- as.numeric(df$Waist_circumference)
  Ht <- as.numeric(df$Height)
  Wt <- as.numeric(df$Weight)
  BMI <- as.numeric(df$BMI)
  if (all(is.na(BMI)) || mean(is.na(BMI)) > 0.5) {
    BMI <- Wt / (Ht / 100)^2
  }
  TC <- as.numeric(df$TC)
  HDL <- as.numeric(df$HDL)
  HbA1c <- as.numeric(df$HbA1c)
  HTN <- to_htn01(df$Hypertension)
  CRP <- if ("CRP" %in% names(df)) as.numeric(df$CRP) else rep(NA_real_, nrow(df))

  out <- data.frame(
    ID = as.character(df$ID),
    BMI = BMI,
    WHtR = WC / Ht,
    WWI = WC / sqrt(Wt),
    ABSI = WC / ((BMI^(2 / 3)) * (Ht^(1 / 2))),
    BRI = 364.2 - 365.5 * sqrt(pmax(0, 1 - ((WC / (2 * pi)) / (0.5 * Ht))^2)),
    NHHR = (TC - HDL) / HDL,
    NHDL = TC - HDL,
    TC_HDL = TC / HDL,
    eGDR = 21.158 - 0.09 * WC - 3.407 * HTN - 0.551 * HbA1c,
    HbA1c_HDL_C = HbA1c / HDL,
    stringsAsFactors = FALSE
  )
  if (any(is.finite(CRP))) out$CRP_HDL <- CRP / (HDL / 1000)
  out
}

INDEX_NAMES <- c(
  "BMI", "WHtR", "WWI", "ABSI", "BRI",
  "NHHR", "NHDL", "TC_HDL", "eGDR", "HbA1c_HDL_C", "CRP_HDL"
)
WAVE_YEARS <- c(2010L, 2012L, 2014L, 2016L)
mult <- 6  # 2010→2016

idx_by_year <- lapply(WAVE_YEARS, function(y) {
  ix <- compute_indices(load_bl(y))
  names(ix)[-1] <- paste0(names(ix)[-1], "_", y)
  ix
})

d <- Reduce(function(a, b) merge(a, b, by = "ID", all = TRUE), idx_by_year)
crp_cols <- paste0("CRP_HDL_", WAVE_YEARS)
if (!all(crp_cols %in% names(d))) {
  INDEX_NAMES <- setdiff(INDEX_NAMES, "CRP_HDL")
  for (cn in intersect(crp_cols, names(d))) d[[cn]] <- NULL
}

# covariates / labs from 2016 (risk origin wave)
B16 <- load_bl(2016L)
cov_keep <- c(
  "Age", "Gender", "Education", "Marital_Status", "Smoke", "Alcohol_drinking",
  "BMI", "Waist_circumference", "Hypertension", "Diabetes",
  "HbA1c", "TC", "HDL", "NBPS", "NBPD", "CRP"
)
cov_keep <- intersect(cov_keep, names(B16))
cov16 <- B16[, c("ID", cov_keep), drop = FALSE]
d <- merge(d, cov16, by = "ID", all.x = TRUE)

# cancer
ca_years <- c(2006, 2008, 2010, 2012, 2014, 2016, 2018, 2020)
ca_list <- setNames(lapply(ca_years, load_cancer), as.character(ca_years))
ca16 <- ca_list[["2016"]]
ca20 <- ca_list[["2020"]]
names(ca16)[2] <- "DN1"
names(ca20)[2] <- "DN2"
d <- merge(d, ca16, by = "ID", all.x = TRUE)
d <- merge(d, ca20, by = "ID", all.x = TRUE)

ever_before <- Reduce(function(a, b) {
  merge(a, b, by = "ID", all = TRUE)
}, lapply(ca_years[ca_years < 2016], function(y) {
  z <- ca_list[[as.character(y)]]
  names(z)[2] <- paste0("DN_", y)
  z
}))
ever_before$ever_ca_before_2016 <- as.integer(rowSums(
  ever_before[, grepl("^DN_", names(ever_before)), drop = FALSE] == 1, na.rm = TRUE
) > 0)
d <- merge(d, ever_before[, c("ID", "ever_ca_before_2016")], by = "ID", all.x = TRUE)

d$Cancer <- as.integer(d$DN2 == 1L)
d$in_2016 <- as.integer(d$ID %in% B16$ID)
d$in_2020_ca <- as.integer(d$ID %in% ca20$ID)
d$free_t1 <- !is.na(d$DN1) & d$DN1 == 0L &
  (is.na(d$ever_ca_before_2016) | d$ever_ca_before_2016 == 0L)
d$fu_ok <- d$in_2016 == 1L & d$free_t1 & !is.na(d$DN2)

d$Marital <- d$Marital_Status
d$Drink <- d$Alcohol_drinking
g <- tolower(as.character(d$Gender))
d$Gender <- factor(
  ifelse(g %in% c("male", "m", "1"), "Male",
    ifelse(g %in% c("female", "f", "2"), "Female", NA_character_)),
  levels = c("Male", "Female")
)
for (bc in c("Smoke", "Drink", "Diabetes", "Hypertension", "Malignant_Tumor")) {
  if (bc %in% names(d)) d[[bc]] <- yn_factor(d[[bc]])
}
if ("Marital" %in% names(d)) {
  m <- tolower(as.character(d$Marital))
  d$Marital <- factor(
    ifelse(grepl("married|partner", m), "Married",
      ifelse(is.na(m) | m == "", NA_character_, "Other")),
    levels = c("Married", "Other")
  )
}
if ("Education" %in% names(d)) {
  ed <- as.character(d$Education)
  d$Education <- factor(
    ifelse(grepl("below", ed, ignore.case = TRUE), "Below High school",
      ifelse(is.na(ed) | ed == "", NA_character_, "High school and above")),
    levels = c("Below High school", "High school and above")
  )
}
hdl <- as.numeric(d$HDL); tc <- as.numeric(d$TC)
d$Dyslipidemia <- factor(
  ifelse(is.na(hdl) & is.na(tc), NA_character_,
    ifelse((!is.na(hdl) & hdl < 40) | (!is.na(tc) & tc >= 240), "Yes", "No")),
  levels = c("No", "Yes")
)

# Map year columns → t1..t4 + cum
year_to_t <- setNames(paste0("t", seq_along(WAVE_YEARS)), as.character(WAVE_YEARS))
for (nm in INDEX_NAMES) {
  cols <- paste0(nm, "_", WAVE_YEARS)
  if (!all(cols %in% names(d))) next
  for (i in seq_along(WAVE_YEARS)) {
    d[[paste0(nm, "_t", i)]] <- as.numeric(d[[cols[i]]])
  }
  mat <- as.matrix(d[, cols, drop = FALSE])
  d[[paste0("cum_", nm)]] <- rowMeans(mat, na.rm = FALSE) * mult
}

d$Hypertension_w4 <- d$Hypertension
d$futime <- 4
d$status <- d$Cancer
d$iwy1 <- 2010L
d$iwy4 <- 2020L
d$Stroke <- d$Cancer
d$Osteoporosis <- d$Cancer

# complete 4-wave BMI = flowchart denom
bmi_ok <- is.finite(d$BMI_t1) & is.finite(d$BMI_t2) &
  is.finite(d$BMI_t3) & is.finite(d$BMI_t4)
d$ex_E1 <- as.integer(d$in_2016 != 1L)
d$ex_E2 <- as.integer(d$in_2016 == 1L & (is.na(d$DN1) | d$DN1 == 1L |
  (!is.na(d$ever_ca_before_2016) & d$ever_ca_before_2016 == 1L)))
d$ex_E3 <- as.integer(d$free_t1 & d$in_2016 == 1L & is.na(d$DN2))
d$ex_E4 <- as.integer(d$fu_ok & !bmi_ok)
d$cohort_final <- as.integer(d$fu_ok & bmi_ok)

cov_n <- vapply(INDEX_NAMES, function(nm) {
  sum(
    is.finite(d[[paste0(nm, "_t1")]]) & is.finite(d[[paste0(nm, "_t2")]]) &
      is.finite(d[[paste0(nm, "_t3")]]) & is.finite(d[[paste0(nm, "_t4")]]) &
      d$cohort_final == 1L,
    na.rm = TRUE
  )
}, integer(1))
pool <- data.frame(
  index = INDEX_NAMES,
  n_four_wave_in_cohort = as.integer(cov_n),
  excluded_reason_if_zero = ifelse(cov_n == 0L, "insufficient four-wave values", ""),
  stringsAsFactors = FALSE
)
utils::write.csv(pool, file.path(out_dir, "hrs_cancer_4wave_index_pool.csv"),
                 row.names = FALSE, fileEncoding = "UTF-8")

wide_path <- file.path(out_dir, "hrs_cancer_cum_kmeans_4wave_analysis_wide.csv")
utils::write.csv(d, wide_path, row.names = FALSE, fileEncoding = "UTF-8")

age16 <- as.numeric(d$Age)
att <- data.frame(
  ID = d$ID,
  ex_E1 = d$ex_E1, ex_E2 = d$ex_E2, ex_E3 = d$ex_E3, ex_E4 = d$ex_E4,
  cohort_final = d$cohort_final,
  Age = age16,
  stringsAsFactors = FALSE
)
att50 <- att[!is.na(att$Age) & att$Age >= 50, , drop = FALSE]
utils::write.csv(
  att50[, setdiff(names(att50), "Age"), drop = FALSE],
  file.path(out_dir, "hrs_cancer_4wave_attrition_pool.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

cat("INDEX_NAMES:", paste(INDEX_NAMES, collapse = ", "), "\n")
print(pool)
cat(
  "Wrote", wide_path, "n=", nrow(d),
  " cohort_final=", sum(d$cohort_final, na.rm = TRUE),
  " events=", sum(d$Cancer[d$cohort_final == 1L] == 1L, na.rm = TRUE), "\n"
)
cat(
  "Attrition Age>=50 N0=", nrow(att50),
  " final=", sum(att50$cohort_final, na.rm = TRUE),
  " events_final=", sum(d$Cancer[d$ID %in% att50$ID[att50$cohort_final == 1L]] == 1L, na.rm = TRUE), "\n"
)
