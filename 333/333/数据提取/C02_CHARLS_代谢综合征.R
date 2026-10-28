rm(list = ls())
gc()
# 兼容 RStudio 与命令行(Rscript)
if(rstudioapi::isAvailable() && rstudioapi::hasFun("getActiveDocumentContext")){
  script_path <- normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path))
} else {
  # 命令行运行时用命令行参数或默认路径
  args <- commandArgs(trailingOnly = TRUE)
  script_path <- if(length(args) >= 1 && nzchar(args[1])) dirname(normalizePath(args[1]))
                 else "d:/项目/复杂网络/保卫胡萝卜/数据提取"
}
setwd(script_path)

# ============================================================
# C03_CHARLS_代谢综合征_提取.R
# 从 CHARLS 2011 原始 .dta 提取代谢综合征(MetS)数据
#
# MetS 诊断标准(满足以下 5 项中 ≥3 项则 DN=1):
#   1. 腰围: 男≥90cm 或 女≥80cm
#   2. HDL-C: 男<40mg/dL 或 女<50mg/dL
#   3. TG:   ≥150mg/dL
#   4. 血压: 平均收缩压≥130 或 平均舒张压≥80 或 正在服降压药
#   5. 空腹血糖: ≥100mg/dL
#
# 纳排: 总人群 → 去<45岁 → 去性别缺失 → 去关键变量缺失(完整病例)
# ============================================================

library(haven); library(dplyr)
RAW <- "./CHARLS/charls原始数据"

# 原始 .dta 的 ID(如 01010410101) 与 baseline/抑郁数据的 ID(如 10104101001) 格式不同
# 验证过的变换: 去前导0 + 末尾前插0  →  命中 baseline 全量 16579
to_base_id <- function(x){
  y <- sub("^0+", "", as.character(x))            # 去前导0 → 10位
  paste0(substr(y, 1, nchar(y)-1), "0", substr(y, nchar(y), nchar(y)))  # 末尾前插0 → 11位(与baseline一致)
}

# ===================== 1. 读取原始数据 =====================
cat("========== 读取原始 .dta ==========\n")
demo <- read_dta(file.path(RAW, "demographic_background.dta"))   # rgender, ID
bio  <- read_dta(file.path(RAW, "biomarkers.dta"))               # qm002, qa003~qa012, ID
blood<- read_dta(file.path(RAW, "Blood_20140429.dta"))           # newglu, newtg, newhdl, ID
hsf  <- read_dta(file.path(RAW, "health_status_and_functioning.dta")) # da011s1/s2, ID

# 统一 ID 为 baseline 格式(character), 与下游抑郁数据/基线可直接对接
demo$ID  <- to_base_id(demo$ID)
bio$ID   <- to_base_id(bio$ID)
blood$ID <- to_base_id(blood$ID)
hsf$ID   <- to_base_id(hsf$ID)

# 从已有基线取清洗过的 Age
load("./CHARLS/D01_baseline_CHARLS_2011_0610.RData")
age_df <- data.frame(ID = as.character(baseline$ID),
                     Age = as.numeric(baseline$Age), stringsAsFactors = FALSE)
cat("demo:", nrow(demo), " bio:", nrow(bio),
    " blood:", nrow(blood), " hsf:", nrow(hsf), " baseline(取Age):", nrow(age_df), "\n")

# ===================== 2. 抽取所需变量并合并 =====================
# 统一 ID 为 character
to_char_id <- function(df) { df$ID <- as.character(df$ID); df }

mets <- demo %>% to_char_id() %>%
  select(ID, rgender)
bio_s <- bio %>% to_char_id() %>%
  select(ID, qm002, qa003, qa004, qa007, qa008, qa011, qa012)
blood_s <- blood %>% to_char_id() %>%
  select(ID, newglu, newtg, newhdl)
med_s <- hsf %>% to_char_id() %>%
  select(ID, da011s1, da011s2)

mets <- mets %>%
  left_join(bio_s,   by = "ID") %>%
  left_join(blood_s, by = "ID") %>%
  left_join(med_s,   by = "ID") %>%
  left_join(age_df,  by = "ID")

# 转数值
numcols <- c("rgender","qm002","qa003","qa004","qa007","qa008","qa011","qa012",
             "newglu","newtg","newhdl","Age")
mets[numcols] <- lapply(mets[numcols], as.numeric)
cat("合并后维度:", dim(mets), "\n")

# ===================== 3. 异常值/缺失码清洗 =====================
# CHARLS 缺失码: 993/997/998/999 等 → 置 NA; 并按临床合理范围过滤
set_na <- function(x, lo, hi){
  x[!is.na(x) & (x < lo | x > hi)] <- NA
  x
}
# 993/999 这类显式缺失码先清
for(v in c("qa003","qa004","qa007","qa008","qa011","qa012","qm002")){
  mets[[v]][!is.na(mets[[v]]) & mets[[v]] >= 990] <- NA
}
mets$qm002   <- set_na(mets$qm002,   40, 200)   # 腰围 cm
mets$qa003   <- set_na(mets$qa003,   40, 300)   # SBP
mets$qa004   <- set_na(mets$qa004,   20, 200)   # DBP
mets$qa007   <- set_na(mets$qa007,   40, 300)
mets$qa008   <- set_na(mets$qa008,   20, 200)
mets$qa011   <- set_na(mets$qa011,   40, 300)
mets$qa012   <- set_na(mets$qa012,   20, 200)
mets$newglu  <- set_na(mets$newglu,  10, 1000)  # 空腹血糖 mg/dL
mets$newtg   <- set_na(mets$newtg,    5, 2000)  # TG mg/dL
mets$newhdl  <- set_na(mets$newhdl,   1, 200)   # HDL mg/dL

# 性别: 只保留 1(男)/2(女)
mets$rgender[!mets$rgender %in% c(1,2)] <- NA
mets$sex <- ifelse(mets$rgender==1, "Male", ifelse(mets$rgender==2, "Female", NA))

# ===================== 4. 计算 5 项组分 =====================
# 平均血压 (取 3 次读数均值; 缺失用可用读数)
mets$meanSBP <- rowMeans(mets[, c("qa003","qa007","qa011")], na.rm = TRUE)
mets$meanSBP[is.nan(mets$meanSBP)] <- NA
mets$meanDBP <- rowMeans(mets[, c("qa004","qa008","qa012")], na.rm = TRUE)
mets$meanDBP[is.nan(mets$meanDBP)] <- NA
# 重命名便于阅读
mets <- mets %>% rename(waist_cm = qm002, glu_mgdl = newglu, tg_mgdl = newtg, hdl_mgdl = newhdl)

# 降压药: da011s1(中药)、da011s2(西药) 任一选中 = 在服降压药
# (s1 仅含值1=中药, s2 仅含值2=西药; 任一非空即用药)
mets$on_med <- (!is.na(mets$da011s1)) | (!is.na(mets$da011s2))
mets$on_med[is.na(mets$da011s1) & is.na(mets$da011s2)] <- NA

# --- 5 项判定 ---
mets$c_waist <- with(mets, (rgender==1 & waist_cm>=90) | (rgender==2 & waist_cm>=80))
mets$c_hdl   <- with(mets, (rgender==1 & hdl_mgdl<40)  | (rgender==2 & hdl_mgdl<50))
mets$c_tg    <- with(mets, tg_mgdl >= 150)
mets$c_bp    <- with(mets, (!is.na(meanSBP) & meanSBP>=130) |
                            (!is.na(meanDBP) & meanDBP>=80) |
                            (isTRUE(on_med)))
mets$c_glu   <- with(mets, glu_mgdl >= 100)

# ===================== 5. 纳排 =====================
cat("\n========== 纳排流程 ==========\n")
N0 <- nrow(mets); cat("0. 初始(全人群):", N0, "\n")
mets <- mets[!is.na(mets$Age),]
cat("1. 去年龄缺失: 剩", nrow(mets), " (去", N0-nrow(mets), ")\n")
N1 <- nrow(mets)
mets <- mets[mets$Age >= 45,]
cat("2. 去<45岁: 剩", nrow(mets), " (去", N1-nrow(mets), ")\n")
N2 <- nrow(mets)
mets <- mets[!is.na(mets$sex),]
cat("3. 去性别缺失: 剩", nrow(mets), " (去", N2-nrow(mets), ")\n")
N3 <- nrow(mets)
# 关键变量完整病例 (5 项判定所需的底层变量都要有)
key_vars <- c("waist_cm","hdl_mgdl","tg_mgdl","meanSBP","glu_mgdl","on_med")
# on_med 的 NA 表示血压药物信息缺失 → 若 SBP/DBP 有值仍可判 c_bp, 但按"其他空值剔除"从严
keep <- complete.cases(mets[, c("waist_cm","hdl_mgdl","tg_mgdl","glu_mgdl")]) &
        (!is.na(mets$meanSBP) | !is.na(mets$meanDBP) | !is.na(mets$on_med))
mets <- mets[keep, ]
cat("4. 去关键变量缺失(完整病例): 剩", nrow(mets), " (去", N3-nrow(mets), ")\n")

# ===================== 6. MetS 诊断 =====================
mets$mets_count <- rowSums(mets[, c("c_waist","c_hdl","c_tg","c_bp","c_glu")], na.rm=FALSE)
mets$DN <- ifelse(mets$mets_count >= 3, 1, 0)

cat("\n========== 结果汇总 ==========\n")
cat("最终样本 N =", nrow(mets), "\n")
cat("性别:\n"); print(table(mets$sex))
cat(sprintf("\n年龄: 均值=%.1f (SD=%.1f), 范围 %d-%d\n",
    mean(mets$Age), sd(mets$Age), min(mets$Age), max(mets$Age)))
cat("\n5 项组分阳性率:\n")
for(v in c("c_waist","c_hdl","c_tg","c_bp","c_glu"))
  cat(sprintf("  %-8s %.1f%%\n", v, 100*mean(mets[[v]], na.rm=TRUE)))
cat(sprintf("\n组分个数分布:\n")); print(table(mets$mets_count, useNA="always"))
cat(sprintf("\n代谢综合征(DN=1, 组分≥3) 患病率: %.1f%% (%d/%d)\n",
    100*mean(mets$DN==1), sum(mets$DN==1), nrow(mets)))

# ===================== 7. 输出 =====================
out <- mets %>%
  select(ID, Age, sex, rgender,
         waist_cm, hdl_mgdl, tg_mgdl, meanSBP, meanDBP, on_med, glu_mgdl,
         c_waist, c_hdl, c_tg, c_bp, c_glu, mets_count, DN)
write.csv(out, "CHARLS_2011_代谢综合征.csv", row.names = FALSE)
mets_out <- out
save(mets_out, file = "D02_metabolic_CHARLS_2011.RData")
cat("\n已保存: CHARLS_2011_代谢综合征.csv  与  D02_metabolic_CHARLS_2011.RData\n")
cat("\n==================== 完成 ====================\n")
