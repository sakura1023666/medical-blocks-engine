rm(list = ls()); gc()
################################################################################
# C03b_ELSA_代谢综合征.R
# 从已标准化的 ELSA wave6 基线提取代谢综合征(MetS)
# 数据源: D01_baseline_ELSA_2012_0610.RData (单位已统一 mg/dL/cm/mmHg)
#
# ELSA MetS 标准(满足 5 项 ≥3 则 DN=1):
#   1. 腰围: 男≥102cm 或 女≥88cm         (ELSA/IDF 阈值, 与CHARLS的90/80不同)
#   2. HDL:  男<40mg/dL 或 女<50mg/dL
#   3. TG:   ≥150mg/dL
#   4. 血压: 收缩≥130 或 舒张≥80 或 在服降压药(代理: Hypertension=Yes)
#   5. 空腹血糖: ≥100mg/dL
# 纳排: 总人群 → 去<45岁 → 去性别缺失 → 去关键变量缺失(完整病例)
# 输出列名与 CHARLS_2011_代谢综合征.csv 完全一致, 下游 C04/C05/C06 通用
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

# ========================= 1) 读取已标准化基线 =========================
load("D01_baseline_ELSA_2012_0610.RData")   # 对象 baseline
df <- baseline %>%
  mutate(ID = as.character(ID),
         rgender = ifelse(as.character(Gender)=="Male", 1,
                   ifelse(as.character(Gender)=="Female", 2, NA_real_)),
         sex = as.character(Gender)) %>%
  rename(waist_cm = Waist_circumstance, hdl_mgdl = HDL, tg_mgdl = TG,
         meanSBP = NBPS, meanDBP = NBPD, glu_mgdl = Glucose) %>%
  select(ID, Age, sex, rgender, waist_cm, hdl_mgdl, tg_mgdl,
         meanSBP, meanDBP, glu_mgdl, Hypertension)
cat("ELSA 基线 N =", nrow(df), "\n")

# 降压药代理: HeMDa 不可得 → 用 Hypertension=Yes (曾被告知高血压) 近似"在治/血压异常"
df$on_med <- (trimws(as.character(df$Hypertension)) == "Yes")
df$on_med[is.na(df$Hypertension)] <- NA

# ========================= 2) 计算 5 项组分 =========================
df$c_waist <- with(df, (rgender==1 & waist_cm>=102) | (rgender==2 & waist_cm>=88))
df$c_hdl   <- with(df, (rgender==1 & hdl_mgdl<40)  | (rgender==2 & hdl_mgdl<50))
df$c_tg    <- with(df, tg_mgdl >= 150)
df$c_bp    <- with(df, (!is.na(meanSBP) & meanSBP>=130) |
                       (!is.na(meanDBP) & meanDBP>=80)  |
                       isTRUE(on_med))
df$c_glu   <- with(df, glu_mgdl >= 100)

# ========================= 3) 纳排 =========================
cat("\n========== 纳排流程 ==========\n")
N0 <- nrow(df); cat("0. 初始(全人群):", N0, "\n")
df <- df[!is.na(df$Age),];            cat("1. 去年龄缺失: 剩", nrow(df), "\n")
N1 <- nrow(df)
df <- df[df$Age >= 45,];              cat("2. 去<45岁: 剩", nrow(df), " (去", N1-nrow(df), ")\n")
N2 <- nrow(df)
df <- df[!is.na(df$sex),];            cat("3. 去性别缺失: 剩", nrow(df), "\n")
N3 <- nrow(df)
# 完整病例: 5 项底层变量都要有 (on_med 的NA若SBP/DBP有值仍可判c_bp, 但从严按"其他空值剔除")
keep <- complete.cases(df[, c("waist_cm","hdl_mgdl","tg_mgdl","glu_mgdl")]) &
        (!is.na(df$meanSBP) | !is.na(df$meanDBP))
df <- df[keep, ];                     cat("4. 去关键变量缺失(完整病例): 剩", nrow(df), " (去", N3-nrow(df), ")\n")

# ========================= 4) MetS 诊断 =========================
df$mets_count <- rowSums(df[, c("c_waist","c_hdl","c_tg","c_bp","c_glu")], na.rm=FALSE)
df$DN <- ifelse(df$mets_count >= 3, 1, 0)

cat("\n========== 结果汇总 ==========\n")
cat("最终样本 N =", nrow(df), "\n")
cat("性别:\n"); print(table(df$sex))
cat(sprintf("年龄: 均值=%.1f (SD=%.1f), 范围 %d-%d\n",
    mean(df$Age), sd(df$Age), min(df$Age), max(df$Age)))
cat("\n5 项组分阳性率:\n")
for(v in c("c_waist","c_hdl","c_tg","c_bp","c_glu"))
  cat(sprintf("  %-8s %.1f%%\n", v, 100*mean(df[[v]], na.rm=TRUE)))
cat("\n组分个数分布:\n"); print(table(df$mets_count, useNA="always"))
cat(sprintf("\n代谢综合征(DN=1, 组分≥3) 患病率: %.1f%% (%d/%d)\n",
    100*mean(df$DN==1), sum(df$DN==1), nrow(df)))
cat(sprintf("(注: 第4项降压药用 Hypertension=Yes 代理, 占%.1f%%)\n",
    100*mean(df$on_med, na.rm=TRUE)))

# ========================= 5) 输出 (列名同 CHARLS) =========================
out <- df %>% select(ID, Age, sex, rgender,
                     waist_cm, hdl_mgdl, tg_mgdl, meanSBP, meanDBP, on_med, glu_mgdl,
                     c_waist, c_hdl, c_tg, c_bp, c_glu, mets_count, DN)
write.csv(out, "ELSA_2012_代谢综合征.csv", row.names = FALSE)
mets_out <- out
save(mets_out, file = "D02_metabolic_ELSA_2012.RData")
cat("\n已保存: ELSA_2012_代谢综合征.csv  与  D02_metabolic_ELSA_2012.RData\n")
cat("\n==================== ELSA MetS 提取完成 ====================\n")
