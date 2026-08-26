###############################################################################
#  composite_index_vars.R — 复合指标名单（与 Blocks/00_index/01block_index.R 对应）
#
#  用法：source("configs/indices/composite_index_vars.R")
#  产物：.composite_index_vars（字符向量，93 个指标名）
#
#  分组说明：
#    Group A  — 两库（NHANES + MIMIC）均可计算（基础炎症/脂代谢/肝肾/血液学）
#    Group B  — 含体型指标（Waist_circumference），仅 NHANES 可计算
#    Group C  — 含 NHANES 特有列（Insulin/HSCRP/Monocyte），需检查 MIMIC 可用性
#    Group D  — 链式依赖 / 条件评分（依赖 BMI 或其他指标先计算）
#  批量时 fail_policy="continue" 处理单库失败指标。
###############################################################################

# ── Group A：两库均可计算的基础比值指标 ──────────────────────────────────────
.idx_group_A <- c(
  # 炎症/免疫比值
  "NLR",          # Neutrophil_Count / Lymphocytes
  "PLR",          # Platelet_Count / Lymphocytes
  "SII",          # Platelet_Count * Neutrophil_Count / Lymphocytes
  "NLPR",         # Neutrophil_Count * 100 / (Lymphocytes * Platelet_Count)
  "ANLR",         # Albumin / NLR
  "PHR",          # Platelet_Count / HDL
  "HALP",         # Hemoglobin * Albumin * Lymphocytes / Platelet_Count
  "GLR",          # Glucose / Lymphocytes
  "WPR",          # WBC / Platelet_Count
  # 血脂比值
  "AIP",          # log10(Triglycerides / HDL)
  "TyG",          # log(Glucose * Triglycerides / 2)
  "NHHR",         # (Total_Cholesterol - HDL) / HDL
  "RC",           # Total_Cholesterol - HDL - LDL
  "TG_HDL_C",     # Triglycerides / HDL
  "TC_HDL",       # Total_Cholesterol / HDL
  "NHDL",         # Total_Cholesterol - HDL
  "AC",           # (Total_Cholesterol - HDL) / HDL
  "CRI_I",        # Total_Cholesterol / HDL
  "CRI_II",       # LDL / HDL
  "LCI",          # TG * TC * LDL / (HDL^4)
  "CHG",          # log(Total_Cholesterol * Glucose / (HDL/2))
  # 糖代谢
  "SHR",          # Glucose / (28.7 * HbA1c - 46.7)
  "HGI",          # HbA1c - (0.01 * Glucose + 5.04)
  "GPR",          # (Glucose/18) / Potassium
  # 肝功能
  "De_Ritis",     # AST / ALT
  "FIB4",         # Age * AST / (Platelet_Count * sqrt(ALT))；PLT = K/uL
  "APRI",         # (AST/40) / Platelet_Count * 100；PLT = K/uL（禁止误 ÷1000）
  "ALBI",         # log10(Bilirubin*17.1)*0.66 + (10*Albumin)*(-0.085)
  "AGR",          # Albumin / Globulin
  "BAR",          # BUN / Albumin
  "LAR",          # LD / Albumin
  "log2LAR",      # log2(LD / Albumin)
  # 肾功能
  "CAR",          # Creatinine / Albumin
  "UA_CrR",       # Uric_Acid / Creatinine（旧名）
  "UA_CR",        # UA/CR = Uric_Acid(mg/dL) / Creatinine(mg/dL)
  "BUN_Cr",       # BUN / Creatinine
  # 血液学
  "RAR",          # RDW / Albumin
  "HRR",          # Hemoglobin / RDW
  # 综合
  "PNI",          # 10*Albumin + 5*Lymphocytes
  "EASIX",        # LD * Creatinine / Platelet_Count
  "SOSM",         # 1.86*(Na+K) + 1.15*Glucose/18 + BUN*0.375 + 14
  # 人体测量（两库均有 BMI）
  "BMI"           # Weight / (Height/100)^2
)

# ── Group B：含 Waist_circumference，仅 NHANES 可计算 ──────────────────────
.idx_group_B <- c(
  "ABSI",         # Waist_circumference / (BMI^(2/3) * Height^(1/2))
  "BRI",          # 364.2 - 365.5 * sqrt(1 - (WC/(2*pi)/(0.5*H))^2)
  "WWI",          # Waist_circumference / sqrt(Weight)
  "WHtR",         # Waist_circumference / Height
  "CMI",          # (TG/HDL) * (WC/Height)
  "AIP_BMI",      # AIP * BMI
  "TyG_BMI",      # TyG * BMI
  "TCBI",         # TG * TC * Weight / 1000
  "AIP_WC",       # AIP * Waist_circumference
  "AIP_WHtR",     # AIP * WHtR
  "WTI",          # log(TG * WC / 2)
  "TyG_WHtR",     # TyG * WHtR
  "TyG_WC",       # TyG * Waist_circumference
  "TyG_WWI",      # TyG * WWI
  "TyG_ABSI",     # TyG * ABSI
  "MCMI",         # log(TG*Glucose/HDL) * WHtR
  "eGDR",         # 21.158 - 0.09*WC - 3.407*Hypertension - 0.551*HbA1c
  "GNRI",         # 性别条件：1.489*Albumin*10 + 41.7*(Weight/理想体重)
  "ZJU",          # 性别条件：Glucose/18 + BMI + 3*ALT/AST + TG
  "VAI",          # 性别条件：(WC/(39.68+1.88*BMI))*(TG/1.03)*(1.31/HDL)
  "RFM",          # 性别条件：64 - 20*(Height/WC) [Male]
  "LAP"           # 性别条件：(WC-65)*TG/88.57 [Male]
)

# ── Group C：含 NHANES 特有列（Monocyte/HSCRP/Insulin/UACR）───────────────
.idx_group_C <- c(
  "AISI",         # Neutrophil_Count * Platelet_Count * Monocyte / Lymphocytes
  "SIRI",         # Neutrophil_Count * Monocyte / Lymphocytes
  "MHR",          # Monocyte / HDL
  "NMLR",         # (Monocyte + Neutrophil_Count) / Lymphocytes
  "CALLY",        # (Albumin/10) * Lymphocytes / (HSCRP*10)
  "CLR",          # (HSCRP/10) * Lymphocytes
  "CTI",          # 0.412*log(HSCRP/10) + log(Glucose*TG/2)
  "hs_CRP_HDL_C", # HSCRP / (HDL/1000)
  "RCII",         # (TC - HDL - LDL) * HSCRP / 10
  "lnRCII",       # log(RCII)
  "LHR",          # Lymphocytes / (HDL * 0.0259)
  "HbA1c_HDL_C",  # HbA1c / HDL
  "ALT_HDL_C",    # ALT / HDL
  "UHR",          # Uric_Acid / HDL
  "AFR",          # Fibrinogen * 10 / Albumin (FAR ×1000 尺度)
  "UACR",         # AlbuminUrine / (Urine_Creatinine * 0.01)
  "MCH",          # Hemoglobin / RBC * 10 (pg)
  "MCV",          # Hematocrit / RBC * 10 (fL)
  "MCHC",         # Hemoglobin / Hematocrit * 100 (g/dL)
  "RDW_CV",       # RDW * RBC / Hematocrit
  "HHR",          # Hemoglobin / Hematocrit
  "ACAG",         # (4.4 - Albumin) * 2.5 + AnionGap
  "METSIR",       # log((2*Glucose+TG)*BMI) / log(HDL)
  "HOMA_IR",      # Glucose * Insulin / 22.5
  "ALI"           # BMI * Albumin / NLR
)

# ── Group D：链式依赖（依赖上方指标先计算）─────────────────────────────────
.idx_group_D <- c(
  "ePWV",         # 依赖 DBP/SBP → MBP → ePWV（NHANES 有 NBPS/NBPD）
  "sdLDL_C",      # sdLDL = LDL - lbLDL_C (需 LDL + TG)
  "FSI",          # 依赖 ALT/AST 比值 flag + 人口学
  "METS_VF",      # 依赖 METSIR + WC/Height + Age + Gender
  "CONUT_score",  # 依赖 alb_score + lymp_score + chol_score
  "HSI",          # 8*(ALT/AST) + BMI + 性别 + 糖尿病
  "NFS"           # -1.675 + 0.037*Age + ... + 0.99*(ALT/AST) - 0.013*Platelet - 0.66*Albumin
)

# ── 全量指标向量（按组合并）────────────────────────────────────────────────
.composite_index_vars <- c(
  .idx_group_A,
  .idx_group_B,
  .idx_group_C,
  .idx_group_D
)

# ── 仅双库均可用的保守子集（推荐 dual 分析使用）────────────────────────────
.composite_index_vars_dual_safe <- c(
  .idx_group_A,
  # Group C 中不依赖 NHANES 专属列的指标（若 MIMIC 有 RBC/HbA1c 等则可用）
  "MCH", "MCV", "MCHC", "RDW_CV", "HHR",
  "LHR", "UHR", "ALI", "METSIR", "ACAG",
  "AFR", "HbA1c_HDL_C", "ALT_HDL_C",
  # Group D：不依赖 WC/Insulin/HSCRP
  "sdLDL_C", "CONUT_score", "HSI", "NFS", "FSI"
)


# ── 轨迹预后 APRI 研究专用子集（Index_All，见 decision_tree_trajectory_prognosis_apri.md）──
.composite_index_vars_trajectory_apri <- c("NLR", "APRI", "LAR", "CAR", "BUN_Cr", "BAR")

message(sprintf(
  "[composite_index_vars] 已加载：全量 %d 个指标 / 双库安全子集 %d 个 / 轨迹APRI子集 %d 个",
  length(.composite_index_vars),
  length(.composite_index_vars_dual_safe),
  length(.composite_index_vars_trajectory_apri)
))
