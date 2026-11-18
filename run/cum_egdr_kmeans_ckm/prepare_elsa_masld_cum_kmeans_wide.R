#!/usr/bin/env Rscript
###############################################################################
# prepare_elsa_masld_cum_kmeans_wide.R
# ELSA MASLD · 累积暴露 k-means 分析宽表
#
# 波次（对齐骨质疏松 W4/W6/W8 结构）:
#   W2(2004)=T0 暴露 · W4(2008)=T1 风险起点+暴露 · W6(2012)=T2 新发 MASLD
#   cum × 4（约 4 年）
#
# 纳排（项目说明 + 疾病提取口径）:
#   Age≥50；有 W4+W6 随访；严格可判且 W4 MASLD=0；W6 严格可判；双波 BMI 完整（流程图分母）
#
# 用法:
#   Rscript run/cum_egdr_kmeans_ckm/prepare_elsa_masld_cum_kmeans_wide.R
###############################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
})

.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else Sys.getenv("BLOCK_REPO_ROOT", "/mnt/e/01block/01Block-new-Final")
}
.res <- {
  if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result")
}
proj <- file.path(.res, "62_MASLD", "cum_egdr_kmeans_41654871")
data_dir <- file.path(proj, "data")
from34 <- file.path(data_dir, "from_34_ELSA")
rep_dir <- file.path(proj, "reports")
dir.create(rep_dir, recursive = TRUE, showWarnings = FALSE)
cum_mult <- 4

IDX <- c(
  "BMI", "WHtR", "WWI", "ABSI", "BRI", "RFM", "Conicity", "Ponderal",
  "AIP", "TG_HDL_C", "NHHR", "nonHDL", "AIP_WC", "RC", "eGDR",
  "AIP_BMI", "AIP_WHtR", "CMI", "VAI", "LAP", "CVAI",
  "TyG", "TyG_WC", "TyG_WWI", "TyG_BMI", "METSIR", "SHR",
  "TyG_WHtR", "MCMI", "TyG_ABSI",
  "ePWV",
  "CRI_II", "CHG", "LCI", "TCBI", "HGI", "HbA1c_HDL_C", "sdLDL_C", "METS_VF"
)

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "Blocks/00_index/01block_index.R"), local = FALSE)

.load_bl <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  as.data.table(e$baseline)
}

.prep_for_index <- function(dt) {
  dt <- copy(dt)
  dt[, ID := as.character(ID)]
  if (!"Triglycerides" %in% names(dt) && "TG" %in% names(dt)) {
    dt[, Triglycerides := as.numeric(TG)]
  }
  if (!"Total_Cholesterol" %in% names(dt) && "TC" %in% names(dt)) {
    dt[, Total_Cholesterol := as.numeric(TC)]
  }
  if (!"SBP" %in% names(dt) && "NBPS" %in% names(dt)) dt[, SBP := as.numeric(NBPS)]
  if (!"DBP" %in% names(dt) && "NBPD" %in% names(dt)) dt[, DBP := as.numeric(NBPD)]
  # Hypertension → Yes/No（eGDR）
  if ("Hypertension" %in% names(dt)) {
    v <- tolower(trimws(as.character(dt$Hypertension)))
    dt[, Hypertension := factor(
      ifelse(v %in% c("yes", "y", "1"), "Yes",
             ifelse(v %in% c("no", "n", "0"), "No", NA_character_)),
      levels = c("No", "Yes")
    )]
  }
  if ("Gender" %in% names(dt)) {
    dt[, Gender := as.character(Gender)]
  }
  # numeric labs
  for (cn in c(
    "Age", "Weight", "Height", "BMI", "Waist_circumference",
    "Glucose", "HbA1c", "TG", "TC", "HDL", "LDL", "Triglycerides",
    "Total_Cholesterol", "SBP", "DBP", "NBPS", "NBPD"
  )) {
    if (cn %in% names(dt)) dt[[cn]] <- as.numeric(dt[[cn]])
  }
  if (!"BMI" %in% names(dt) || mean(is.finite(dt$BMI)) < 0.5) {
    dt[, BMI := Weight / (Height / 100)^2]
  }
  dt
}

.calc_wave_indices <- function(dt, idx_names) {
  df <- as.data.frame(.prep_for_index(dt))
  defs <- .idx_definitions()
  def_map <- stats::setNames(defs, vapply(defs, function(d) d$name, character(1)))
  # dependency-first order for requested indices
  order_names <- unique(c("BMI", "MBP", "METSIR", "lbLDL_C", idx_names))
  for (nm in order_names) {
    def <- def_map[[nm]]
    if (is.null(def)) {
      # manual fallbacks for alias names used in OP pool
      if (identical(nm, "nonHDL") || identical(nm, "non_HDL")) {
        df[[nm]] <- as.numeric(df$Total_Cholesterol) - as.numeric(df$HDL)
        message(sprintf("  ok %s (manual) n=%d", nm, sum(is.finite(df[[nm]]))))
        next
      }
      message(sprintf("  missing def: %s", nm))
      next
    }
    tryCatch({
      vals <- with(df, eval(parse(text = def$expr)))
      vals[!is.finite(as.numeric(vals))] <- NA_real_
      dg <- def$digits
      if (!is.null(dg)) vals <- round(as.numeric(vals), as.integer(dg))
      df[[nm]] <- as.numeric(vals)
      message(sprintf("  ok %s n=%d", nm, sum(is.finite(df[[nm]]))))
    }, error = function(e) {
      message(sprintf("  FAIL %s: %s", nm, conditionMessage(e)))
      df[[nm]] <<- rep(NA_real_, nrow(df))
    })
  }
  # OP pool used nonHDL alias
  if ("non_HDL" %in% names(df) && !"nonHDL" %in% names(df)) {
    df[["nonHDL"]] <- df[["non_HDL"]]
  }
  out <- data.table(ID = as.character(df$ID))
  for (nm in idx_names) {
    out[[nm]] <- if (nm %in% names(df)) as.numeric(df[[nm]]) else NA_real_
  }
  out
}

message("== load baselines ==")
b2 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA2_2004_1028_1448.RData"))
b4 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA4_2008_1028_1448.RData"))
b6 <- .load_bl(file.path(data_dir, "D01_baseline_ELSA6_2012_1028_1448.RData"))
message(sprintf("n W2/W4/W6 = %d / %d / %d", nrow(b2), nrow(b4), nrow(b6)))

message("== compute dual-wave indices (W2=t1, W4=t2) ==")
i1 <- .calc_wave_indices(b2, IDX)
i2 <- .calc_wave_indices(b4, IDX)
setnames(i1, IDX, paste0(IDX, "_t1"))
setnames(i2, IDX, paste0(IDX, "_t2"))

message("== MASLD disease flags (strict) ==")
w2d <- fread(file.path(from34, "ELSA-MASLD-wave2004-全体人群_9432.csv"), showProgress = FALSE)
w4d <- fread(file.path(from34, "ELSA-MASLD-wave2008-全体人群_11050.csv"), showProgress = FALSE)
w6d <- fread(file.path(from34, "ELSA-MASLD-wave2012-全体人群_10601.csv"), showProgress = FALSE)
dn <- function(d, tag) {
  data.table(
    ID = as.character(d$idauniq),
    age = as.numeric(d$agey),
    strict = as.integer(d$strict == 1L),
    DN = as.integer(d$DN_loose == 1L)
  )[, setnames(.SD, c("age", "strict", "DN"), paste0(c("age", "strict", "DN"), "_", tag))]
}
d2 <- dn(w2d, "w2")
d4 <- dn(w4d, "w4")
d6 <- dn(w6d, "w6")
# DN0/1/2 mirror osteoporosis naming (T0/T1/T2 disease)
dn_map <- merge(d2, d4, by = "ID", all = TRUE)
dn_map <- merge(dn_map, d6, by = "ID", all = TRUE)
dn_map[, `:=`(
  DN0 = fifelse(strict_w2 == 1L, DN_w2, NA_integer_),
  DN1 = fifelse(strict_w4 == 1L, DN_w4, NA_integer_),
  DN2 = fifelse(strict_w6 == 1L, DN_w6, NA_integer_)
)]

message("== attrition from W2 baseline ==")
# Start pool = W2 baseline
att <- data.table(ID = as.character(b2$ID), Age_w2 = as.numeric(b2$Age))
att <- merge(att, dn_map[, .(ID, age_w2, age_w4, age_w6, strict_w2, strict_w4, strict_w6,
                             DN_w2, DN_w4, DN_w6, DN0, DN1, DN2)],
             by = "ID", all.x = TRUE)
# present W4/W6 = appeared in those baselines
att[, in_w4 := ID %in% as.character(b4$ID)]
att[, in_w6 := ID %in% as.character(b6$ID)]
att[, age50 := Age_w2 >= 50]
att[, ex_E1 := as.integer(!(in_w4 & in_w6))]                 # missing follow-up W4 or W6
att[, in3 := as.integer(in_w4 & in_w6)]
att[, free_t1 := as.integer(strict_w4 == 1L & DN_w4 == 0L)] # no MASLD at W4 (strict)
att[, ex_E2 := as.integer(in3 == 1L & free_t1 != 1L)]       # prevalent / not judgable at W4
att[, out_ok := as.integer(strict_w6 == 1L)]                # W6 MASLD judgable
att[, ex_E3 := as.integer(in3 == 1L & free_t1 == 1L & out_ok != 1L)]
# BMI both waves for flowchart denom
bmi1 <- i1[, .(ID, BMI_t1)]
bmi2 <- i2[, .(ID, BMI_t2)]
att <- merge(att, bmi1, by = "ID", all.x = TRUE)
att <- merge(att, bmi2, by = "ID", all.x = TRUE)
att[, bmi_ok := as.integer(is.finite(BMI_t1) & is.finite(BMI_t2))]
att[, ex_E4 := as.integer(in3 == 1L & free_t1 == 1L & out_ok == 1L & bmi_ok != 1L)]
att[, cohort_final := as.integer(
  age50 == TRUE & in3 == 1L & free_t1 == 1L & out_ok == 1L & bmi_ok == 1L
)]
# restrict attrition file to age≥50 starters (flowchart n0)
att_age <- att[age50 == TRUE]
fwrite(att_age[, .(ID, ex_E1, in3, ex_E2, ex_E3, ex_E4, cohort_final)],
       file.path(data_dir, "elsa_masld_attrition_pool.csv"))

message(sprintf(
  "attrition Age≥50: n0=%d; after FU=%d; free W4=%d; out ok=%d; BMI both(cohort_final)=%d; events=%d",
  nrow(att_age),
  sum(att_age$in3 == 1L),
  sum(att_age$in3 == 1L & att_age$free_t1 == 1L),
  sum(att_age$in3 == 1L & att_age$free_t1 == 1L & att_age$out_ok == 1L),
  sum(att_age$cohort_final == 1L),
  sum(att_age$cohort_final == 1L & att_age$DN_w6 == 1L, na.rm = TRUE)
))

message("== assemble analysis wide ==")
# covariates from risk-origin wave (W4), fall back W2
cov4 <- b4[, .(
  ID = as.character(ID),
  Age = as.numeric(Age),
  Gender = as.character(Gender),
  Education = Education,
  Marital_Status = Marital_Status,
  Smoke = Smoke,
  Alcohol_drinking = Alcohol_drinking,
  BMI = as.numeric(BMI),
  Waist_circumference = as.numeric(Waist_circumference),
  Hypertension = Hypertension,
  Diabetes = Diabetes,
  Malignant_Tumor = Malignant_Tumor,
  HbA1c = as.numeric(HbA1c),
  TG = as.numeric(TG),
  TC = as.numeric(TC),
  HDL = as.numeric(HDL),
  LDL = as.numeric(LDL),
  Glucose = as.numeric(Glucose),
  NBPS = as.numeric(NBPS),
  NBPD = as.numeric(NBPD),
  Height = as.numeric(Height),
  Weight = as.numeric(Weight),
  Waist_circumference_w4 = as.numeric(Waist_circumference),
  Hypertension_w4 = Hypertension,
  HbA1c_w4 = as.numeric(HbA1c),
  BMI_w4 = as.numeric(BMI),
  TG_w4 = as.numeric(TG),
  HDL_w4 = as.numeric(HDL),
  Glucose_w4 = as.numeric(Glucose),
  Height_w4 = as.numeric(Height),
  Weight_w4 = as.numeric(Weight)
)]
cov2 <- b2[, .(
  ID = as.character(ID),
  Age_bl2 = as.numeric(Age),
  Gender_w2 = as.character(Gender)
)]

wide <- merge(att[, .(ID, DN0, DN1, DN2, free_t1, out_ok, cohort_final,
                      ex_E1, ex_E2, ex_E3, ex_E4, Age_w2, in3)],
              i1, by = "ID", all.x = TRUE)
wide <- merge(wide, i2, by = "ID", all.x = TRUE)
wide <- merge(wide, cov4, by = "ID", all.x = TRUE)
wide <- merge(wide, cov2, by = "ID", all.x = TRUE)
# Age: prefer W4 (risk origin); else W2
wide[, Age := {
  a4 <- as.numeric(Age)
  a2 <- as.numeric(Age_w2)
  fifelse(is.finite(a4), a4, a2)
}]
wide[, Gender := {
  g4 <- as.character(Gender)
  g2 <- as.character(Gender_w2)
  fifelse(!is.na(g4) & nzchar(g4), g4, g2)
}]
wide[, MASLD := as.integer(DN2)]
wide[, free_t1 := free_t1 == 1L]
wide[, fu_ok := out_ok == 1L]
wide[, futime := 4]
wide[, status := MASLD]
wide[, Drink := Alcohol_drinking]
wide[, Marital := Marital_Status]
wide[, Triglycerides := as.numeric(TG)]
wide[, Total_Cholesterol := as.numeric(TC)]
# Dyslipidemia from labs at W4
wide[, Dyslipidemia := {
  tg <- as.numeric(TG)
  hdl <- as.numeric(HDL)
  flag <- as.integer(tg >= 150 | (!is.na(hdl) & hdl < 40))
  factor(ifelse(is.na(tg) & is.na(hdl), NA_character_,
                ifelse(flag == 1L, "Yes", "No")), levels = c("No", "Yes"))
}]
# WC_t2 / HTN_t2 / HbA1c_t2 aliases for eGDR recompute path
wide[, WC_t2 := Waist_circumference_w4]
wide[, Hypertension_t2 := Hypertension_w4]
wide[, HbA1c_t2 := HbA1c_w4]
wide[, Hypertension_t1_raw := Hypertension]

for (ix in IDX) {
  wide[[paste0("cum_", ix)]] <-
    (as.numeric(wide[[paste0(ix, "_t1")]]) + as.numeric(wide[[paste0(ix, "_t2")]])) / 2 * cum_mult
}

# Age≥50 at W2 baseline（与 attrition / 项目纳排一致）
wide_out <- wide[is.finite(Age_w2) & Age_w2 >= 50]

wide_path <- file.path(data_dir, "elsa_masld_cum_kmeans_analysis_wide.csv")
fwrite(wide_out, wide_path)

# index pool among cohort_final
ok <- wide_out$cohort_final == 1L & !is.na(wide_out$MASLD) & wide_out$free_t1 %in% TRUE
pool <- rbindlist(lapply(IDX, function(ix) {
  t1 <- wide_out[[paste0(ix, "_t1")]]
  t2 <- wide_out[[paste0(ix, "_t2")]]
  both <- is.finite(t1) & is.finite(t2)
  free <- both & ok
  n_free <- sum(free, na.rm = TRUE)
  n_ev <- sum(free & wide_out$MASLD == 1L, na.rm = TRUE)
  data.table(
    index = ix,
    both = as.integer(sum(both, na.rm = TRUE)),
    free_T1 = as.integer(n_free),
    fu = as.integer(n_free),
    lost = 0L,
    events = as.integer(n_ev),
    event_pct = if (n_free > 0) round(100 * n_ev / n_free, 2) else NA_real_
  )
}))
fwrite(pool, file.path(rep_dir, "elsa_masld_dualwave_index_pool.csv"))

message(sprintf("Wrote %s nrow=%d ncol=%d", wide_path, nrow(wide_out), ncol(wide_out)))
message(sprintf("cohort_final=%d events=%d", sum(wide_out$cohort_final == 1L),
                sum(wide_out$cohort_final == 1L & wide_out$MASLD == 1L, na.rm = TRUE)))
print(pool[order(-free_T1)])
message("ALL DONE")
