rm(list = ls()); gc()
################################################################################
# C04b_ELSA_基线标准化.R
# 将 ELSA_2012_wave6_baseline.RDATA 处理为 CHARLS 标准结构 (53 列, 同 D01_baseline_CHARLS)
# 映射规则 100% 沿用 C01_ELSA_数据提取.R 的 process_wave(2012)
# 输出: D01_baseline_ELSA_2012_0610.RData (对象 baseline)
################################################################################
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = FALSE))
} else if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  script_path <- normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path))
} else {
  script_path <- getwd()
}
setwd(script_path)
cat("工作目录:", getwd(), "\n")
options(width=220)
suppressPackageStartupMessages({ library(dplyr) })

# ---- 辅助函数 (与 C01 一致) ----
clean_neg  <- function(x){ x <- suppressWarnings(as.numeric(unclass(x))); x[x < 0] <- NA; x }
as_num     <- function(x) as.numeric(unclass(x))
clean_range<- function(x, lo, hi){ x[!is.na(x) & (x < lo | x > hi)] <- NA; x }
align_to_ref <- function(df, ref_cols, extra_cols = NULL){
  missing_cols <- setdiff(ref_cols, colnames(df))
  for (col in missing_cols) df[[col]] <- NA
  all_cols <- c(ref_cols, extra_cols[extra_cols %in% colnames(df)])
  all_cols <- all_cols[all_cols %in% colnames(df)]
  df[, all_cols]
}

# ---- CHARLS 参考列 (统一在 CHARLS/ 子目录) ----
charls_ref <- "./CHARLS/D01_baseline_CHARLS_2011_0610.RData"
if (!file.exists(charls_ref)) stop("找不到 CHARLS 基线参考文件")
load(charls_ref)
ref_cols <- colnames(baseline)
cat("CHARLS 参考列数:", length(ref_cols), "  来自:", charls_ref, "\n")

# ========================= 1) 读取 ELSA wave6 (ELSA/ 子目录) =========================
e1 <- new.env(); load("ELSA/ELSA_2012_wave6_baseline.RDATA", envir=e1)
b  <- get(ls(e1)[1], envir=e1)
cat("ELSA wave6 原始维度:", dim(b), "\n")

# ========================= 2) 人口学/疾病 (沿用 C01 映射) =========================
df <- data.frame(
  ID = as.character(b$idauniqc),
  Age = as_num(b$agey),
  Gender = factor(ifelse(as_num(b$ragender)==0, "Female", "Male"), levels=c("Female","Male")),
  Marital_Status = factor(ifelse(as_num(b$mstath)==1, "Married", "Unmarried"), levels=c("Unmarried","Married")),
  Education = factor(ifelse(as_num(b$raeduc_e) %in% 1, "Below High school",
                     ifelse(as_num(b$raeduc_e) %in% c(3,4,5), "High school and above", NA_character_)),
                     levels=c("Below High school","High school and above")),
  Smoke = factor(ifelse(as_num(b$smoken)==0, "Never",
                ifelse(as_num(b$smoken)==1, "Current", NA_character_)), levels=c("Never","Current")),
  Alcohol_drinking = factor(ifelse(as_num(b$drink)==0, "No ",
                          ifelse(as_num(b$drink)==1, "Yes ", NA_character_)), levels=c("No ","Yes ")),
  Hypertension = factor(ifelse(as_num(b$hibpe)==1, "Yes ", "No "), levels=c("No ","Yes ")),
  T2DM = factor(ifelse(as_num(b$diabe)==1, "Yes ", "No "), levels=c("No ","Yes ")),
  Malignant_Tumor = factor(ifelse(as_num(b$cancre)==1, "Yes ", "No "), levels=c("No ","Yes ")),
  stringsAsFactors = FALSE
)

# ========================= 3) 人体测量/血压 (2012=偶数波, 有测量) =========================
df$Weight             <- as_num(b$mweight)
df$Height             <- as_num(b$mheight) * 100   # 米→厘米
df$BMI                <- as_num(b$mbmi)
df$Waist_circumstance <- as_num(b$mwaist)
df$HR                 <- as_num(b$pulse)
df$NBPS               <- as_num(b$systo)
df$NBPD               <- as_num(b$diasto)

# ========================= 4) 血液数据 (2012 wave6) =========================
# 自动找血检文件 (兼容两种命名)
BLOOD_FILE <- NULL
for (cand in c("ELSA/ELSA_2012-2013_wave6_blood.csv", "ELSA/D02_blood_ELSA_2012.csv")) {
  if (file.exists(cand)) { BLOOD_FILE <- cand; break }
}
# 与 CHARLS 对齐的血检变量 (统一名称 + 单位→mg/dL 或同等)
BLOOD_STD <- c("TC","HDL","TG","LDL","Glucose","HbA1c","Hemoglobin","CRP","WBC")
# ELSA 特有 (CHARLS 没有), 保留为额外列
EXTRA_BLOOD <- c("Ferritin","VitD","IGF1","Fibrinogen","MCH")
extra_blood_df <- NULL

if (!is.null(BLOOD_FILE)) {
  cat("找到血检文件:", BLOOD_FILE, " 合并中...\n")
  blood <- read.csv(BLOOD_FILE, stringsAsFactors=FALSE)
  blood$ID <- as.character(blood$idauniq)
  # --- 与 CHARLS 统一: 名称 + 单位换算 ---
  blood$TC         <- clean_neg(blood$chol) * 38.67          # mmol/L → mg/dL
  blood$HDL        <- clean_neg(blood$hdl)  * 38.67          # mmol/L → mg/dL
  blood$TG         <- clean_neg(blood$trig) * 88.57          # mmol/L → mg/dL
  blood$LDL        <- clean_neg(blood$ldl)  * 38.67          # mmol/L → mg/dL
  blood$Glucose    <- clean_neg(blood$fglu) * 18.02          # mmol/L → mg/dL
  blood$HbA1c      <- clean_neg(blood$hba1c) / 10.929 + 2.15 # IFCC mmol/mol → DCCT %
  blood$Hemoglobin <- clean_neg(blood$hgb)                    # g/dL (2012 直接)
  blood$CRP        <- clean_neg(blood$hscrp)                  # mg/L
  blood$WBC        <- clean_neg(blood$wbc)                    # 10^9/L = 1000/μL, 单位同 CHARLS
  # --- ELSA 特有血检 (保留原始单位, 仅去负值缺失码) ---
  if ("rtin" %in% colnames(blood)) blood$Ferritin   <- clean_neg(blood$rtin)   # ng/mL
  if ("VITD" %in% colnames(blood)) blood$VitD       <- clean_neg(blood$VITD)
  if ("igf1" %in% colnames(blood)) blood$IGF1       <- clean_neg(blood$igf1)   # nmol/L
  if ("cfib" %in% colnames(blood)) blood$Fibrinogen <- clean_neg(blood$cfib)   # g/L
  if ("mch"  %in% colnames(blood)) blood$MCH        <- clean_neg(blood$mch)    # pg/cell (注: 与CHARLS的MCV不同)
  keep_extra <- intersect(EXTRA_BLOOD, colnames(blood))
  df <- left_join(df, blood %>% select(ID, all_of(BLOOD_STD), all_of(keep_extra)), by = "ID")
  cat("血检合并完成: 对齐", length(BLOOD_STD), "项 + ELSA特有", length(keep_extra), "项\n")
} else {
  cat("⚠ 未找到血检文件 → 血检列留 NA\n")
  for (v in BLOOD_STD) df[[v]] <- NA_real_
}

# ========================= 5) 异常值清洗 (与 C01 同范围) =========================
df$Weight             <- clean_range(df$Weight, 30, 250)
df$Height             <- clean_range(df$Height, 100, 220)
df$BMI                <- clean_range(df$BMI, 12, 60)
df$Waist_circumstance <- clean_range(df$Waist_circumstance, 50, 180)
df$HR                 <- clean_range(df$HR, 30, 200)
df$NBPS               <- clean_range(df$NBPS, 60, 300)
df$NBPD               <- clean_range(df$NBPD, 30, 200)
df$Age                <- clean_range(df$Age, 18, 120)
df$WBC                <- clean_range(df$WBC, 1, 50)
df$Hemoglobin         <- clean_range(df$Hemoglobin, 5, 25)
df$Glucose            <- clean_range(df$Glucose, 30, 600)
df$HbA1c              <- clean_range(df$HbA1c, 2, 20)
df$TG                 <- clean_range(df$TG, 10, 2000)
df$TC                 <- clean_range(df$TC, 50, 600)
df$HDL                <- clean_range(df$HDL, 5, 150)
df$LDL                <- clean_range(df$LDL, 5, 500)
df$CRP                <- clean_range(df$CRP, 0, 100)
# ELSA 特有血检的合理范围清洗
if ("Ferritin"   %in% colnames(df)) df$Ferritin   <- clean_range(df$Ferritin, 0.1, 3000)
if ("VitD"       %in% colnames(df)) df$VitD       <- clean_range(df$VitD, 1, 200)
if ("IGF1"       %in% colnames(df)) df$IGF1       <- clean_range(df$IGF1, 1, 500)
if ("Fibrinogen" %in% colnames(df)) df$Fibrinogen <- clean_range(df$Fibrinogen, 1, 15)
if ("MCH"        %in% colnames(df)) df$MCH        <- clean_range(df$MCH, 15, 40)

# ========================= 6) 对齐 CHARLS 53 列 + 衍生指标 + 追加 ELSA 特有 =========================
# 先保存 ELSA 特有血检列 (align_to_ref 会按 ref_cols 截断)
extra_present <- intersect(EXTRA_BLOOD, colnames(df))
extra_blood_df <- df[, extra_present, drop = FALSE]
df <- align_to_ref(df, ref_cols)
df$PP     <- df$NBPS - df$NBPD
df$TyG    <- log(df$TG * df$Glucose / 2)
df$TyGBMI <- df$TyG * df$BMI
df <- df[, ref_cols]
# 追加 ELSA 特有血检列 (CHARLS 没有的, 放在标准 53 列之后)
if (!is.null(extra_blood_df) && ncol(extra_blood_df) > 0) {
  df <- cbind(df, extra_blood_df)
}

cat("\nELSA wave6 标准化后维度:", dim(df), "\n")
cat("前", length(ref_cols), "列与CHARLS一致:", identical(colnames(df)[1:length(ref_cols)], ref_cols),
    " | ELSA特有附加列:", paste(extra_present, collapse=","), "\n")

# ========================= 7) 汇总验证 =========================
cat("\n--- 关键变量分布 ---\n")
cat(sprintf("Age: 均值=%.1f 范围[%g,%g]  (≥45者 %.1f%%)\n",
    mean(df$Age,na.rm=T), min(df$Age,na.rm=T), max(df$Age,na.rm=T),
    100*mean(df$Age>=45,na.rm=T)))
cat("Gender:\n"); print(table(df$Gender, useNA="always"))
cat("MetS 组分缺失率(血检依赖):\n")
for(v in c("Waist_circumstance","NBPS","NBPD","Glucose","HDL","TG","HbA1c","CRP"))
  cat(sprintf("  %-20s %g%%\n", v, round(100*mean(is.na(df[[v]])),1)))

# ========================= 8) 保存 =========================
baseline <- df
save(baseline, file="D01_baseline_ELSA_2012_0610.RData")
cat("\n已保存: D01_baseline_ELSA_2012_0610.RData (N=", nrow(df), ", 53列)\n", sep="")
cat("\n==================== ELSA wave6 标准化完成 ====================\n")
