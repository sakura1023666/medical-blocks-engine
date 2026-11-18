###############################################################################
# HRS 累积暴露 × k-means · 新发癌症宽表
# 设计：T0=2012 暴露波1，T1=2016 风险起点（无癌），T2=2020 新发癌症结局
# 癌症 DN 来自 58_cancer 资料05 全波次；基线人体测量/血脂来自骨质疏松课题 HRS dabiao
# HRS 无 TG/空腹血糖 → 不可算 TyG/AIP/CMI/VAI 等；本脚本只预计算可算指标
###############################################################################

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !(length(a) == 1L && is.na(a))) a else b

hrs_bl_dir <- "/mnt/g/02block_result/10_osteoporosis/cum_egdr_kmeans_41654871/data"
cancer_dir <- paste0(
  "/mnt/g/02block_result/58_cancer/Multimorbidity_41083993/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师(1)/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师/",
  "虚弱与抑郁共病状态及联合纵向轨迹与癌症风险的关联-交付-开心乐老师/资料05-原始数据/hrs"
)
out_dir <- "/mnt/g/02block_result/58_cancer/cum_egdr_kmeans_hrs_cancer/data"
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

## ---- 指标公式（仅 HRS 可算：无 TG / Glucose / LDL）----
compute_indices <- function(df) {
  WC <- as.numeric(df$Waist_circumference)
  Ht <- as.numeric(df$Height)          # cm
  Wt <- as.numeric(df$Weight)          # kg
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
  if (any(is.finite(CRP))) {
    out$CRP_HDL <- CRP / (HDL / 1000)
  }
  out
}

INDEX_NAMES <- c(
  "BMI", "WHtR", "WWI", "ABSI", "BRI",
  "NHHR", "NHDL", "TC_HDL", "eGDR", "HbA1c_HDL_C"
)

B12 <- load_bl(2012L)
B16 <- load_bl(2016L)
i12 <- compute_indices(B12)
i16 <- compute_indices(B16)
names(i12)[-1] <- paste0(names(i12)[-1], "_t1")
names(i16)[-1] <- paste0(names(i16)[-1], "_t2")
# CRP_HDL only if present both waves
if ("CRP_HDL_t1" %in% names(i12) && "CRP_HDL_t2" %in% names(i16)) {
  INDEX_NAMES <- c(INDEX_NAMES, "CRP_HDL")
}

## 癌症：全波次可用；主设计 DN1=2016，DN2=2020；并附 ever_before_2016
ca_years <- c(2006, 2008, 2010, 2012, 2014, 2016, 2018, 2020)
ca_list <- lapply(ca_years, load_cancer)
names(ca_list) <- as.character(ca_years)
ca16 <- ca_list[["2016"]]
ca20 <- ca_list[["2020"]]
names(ca16)[2] <- "DN1"
names(ca20)[2] <- "DN2"

ever_before <- Reduce(function(a, b) {
  m <- merge(a, b, by = "ID", all = TRUE)
  m$ever <- as.integer((!is.na(m$ever) & m$ever == 1L) | (!is.na(m$DN) & m$DN == 1L))
  m$DN <- NULL
  m
}, lapply(ca_years[ca_years < 2016], function(y) {
  d <- ca_list[[as.character(y)]]
  names(d)[2] <- "DN"
  d
}), init = data.frame(ID = character(), ever = integer()))
names(ever_before)[2] <- "ever_ca_before_2016"

cov_keep <- c(
  "Age", "Gender", "Education", "Marital_Status", "Smoke", "Alcohol_drinking",
  "BMI", "Waist_circumference", "Weight", "Height", "Hypertension", "Diabetes",
  "Malignant_Tumor", "HbA1c", "TC", "HDL", "NBPS", "NBPD", "CRP"
)
cov_keep <- intersect(cov_keep, names(B16))
cov1 <- B16[, c("ID", cov_keep), drop = FALSE]

comp12 <- B12[, intersect(c("ID", "Waist_circumference", "Weight", "BMI", "Height",
                            "Hypertension", "HbA1c", "TC", "HDL", "CRP"), names(B12)), drop = FALSE]
names(comp12)[-1] <- paste0(names(comp12)[-1], "_w2012")

d <- data.frame(ID = B12$ID, stringsAsFactors = FALSE)
d <- merge(d, i12, by = "ID", all.x = TRUE)
d <- merge(d, i16, by = "ID", all.x = TRUE)
d <- merge(d, cov1, by = "ID", all.x = TRUE)
d <- merge(d, comp12, by = "ID", all.x = TRUE)
d <- merge(d, ca16, by = "ID", all.x = TRUE)
d <- merge(d, ca20, by = "ID", all.x = TRUE)
d <- merge(d, ever_before, by = "ID", all.x = TRUE)

d$Cancer <- as.integer(d$DN2 == 1L)
d$in_2016 <- as.integer(d$ID %in% B16$ID)
d$in_2020_ca <- as.integer(d$ID %in% ca20$ID)
## 风险起点无癌：2016 DN=0（且可选：2016 前各波从未报癌）
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

mult <- 4  # 2012→2016
for (nm in INDEX_NAMES) {
  c1 <- paste0(nm, "_t1"); c2 <- paste0(nm, "_t2")
  if (c1 %in% names(d) && c2 %in% names(d)) {
    d[[paste0("cum_", nm)]] <- (as.numeric(d[[c1]]) + as.numeric(d[[c2]])) / 2 * mult
  }
}
d$Hypertension_w4 <- d$Hypertension
d$futime <- 4
d$status <- d$Cancer
d$iwy1 <- 2012L
d$iwy4 <- 2020L
d$Stroke <- d$Cancer  # 引擎个别处默认 Stroke 别名
d$Osteoporosis <- d$Cancer

## 双波主指标齐全标志：用 BMI 作 flowchart 分母（各 index worker 再筛自身）
d$ex_E1 <- as.integer(d$in_2016 != 1L)
d$ex_E2 <- as.integer(d$in_2016 == 1L & (is.na(d$DN1) | d$DN1 == 1L |
  (!is.na(d$ever_ca_before_2016) & d$ever_ca_before_2016 == 1L)))
d$ex_E3 <- as.integer(d$free_t1 & d$in_2016 == 1L & is.na(d$DN2))
d$ex_E4 <- as.integer(
  d$fu_ok & !(is.finite(d$BMI_t1) & is.finite(d$BMI_t2))
)
d$cohort_final <- as.integer(
  d$fu_ok & is.finite(d$BMI_t1) & is.finite(d$BMI_t2)
)

## 可算性报告
cov_n <- vapply(INDEX_NAMES, function(nm) {
  sum(is.finite(d[[paste0(nm, "_t1")]]) & is.finite(d[[paste0(nm, "_t2")]]) &
        d$cohort_final == 1L, na.rm = TRUE)
}, integer(1))
pool <- data.frame(
  index = INDEX_NAMES,
  n_dual_wave_in_cohort = as.integer(cov_n),
  excluded_reason_if_zero = ifelse(cov_n == 0L, "insufficient dual-wave values", ""),
  stringsAsFactors = FALSE
)
utils::write.csv(pool, file.path(out_dir, "hrs_cancer_index_pool.csv"),
                 row.names = FALSE, fileEncoding = "UTF-8")

wide_path <- file.path(out_dir, "hrs_cancer_cum_kmeans_analysis_wide.csv")
utils::write.csv(d, wide_path, row.names = FALSE, fileEncoding = "UTF-8")

age12 <- as.numeric(B12$Age[match(d$ID, B12$ID)])
att <- data.frame(
  ID = d$ID,
  ex_E1 = d$ex_E1, ex_E2 = d$ex_E2, ex_E3 = d$ex_E3, ex_E4 = d$ex_E4,
  cohort_final = d$cohort_final,
  Age_2012 = age12,
  stringsAsFactors = FALSE
)
att50 <- att[!is.na(att$Age_2012) & att$Age_2012 >= 50, , drop = FALSE]
att_path <- file.path(out_dir, "hrs_cancer_attrition_pool.csv")
utils::write.csv(att50[, setdiff(names(att50), "Age_2012"), drop = FALSE],
                 att_path, row.names = FALSE, fileEncoding = "UTF-8")

cat("INDEX_NAMES:", paste(INDEX_NAMES, collapse = ", "), "\n")
print(pool)
cat("Wrote", wide_path, "n=", nrow(d),
    " cohort_final=", sum(d$cohort_final, na.rm = TRUE),
    " events=", sum(d$Cancer[d$cohort_final == 1L] == 1L, na.rm = TRUE), "\n")
cat("Attrition Age2012>=50 N0=", nrow(att50),
    " final=", sum(att50$cohort_final, na.rm = TRUE),
    " events_final=", sum(d$Cancer[d$ID %in% att50$ID[att50$cohort_final == 1L]] == 1L, na.rm = TRUE), "\n")
