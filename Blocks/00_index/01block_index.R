###############################################################################
#  index — 复合指标计算：BMI、SII、CONUT_score 等 ~65 个指标。
#
#  register_block: "index"
#  典型流水线: column_mapping → imputation → index（插补后计算指标，缺失列自动跳过）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
#  列名以用户公式为准（如 Neutrophil_Count, Platelet_Count, Lymphocytes），
#  column_mapping block 负责统一映射。
#
#  # ── 配置 config$index ─────────────────────────────────────────────────────
#  index = list(
#    enable  = TRUE,     # 总开关
#    only    = NULL,     # NULL=全部计算；字符向量=只计算指定指标
#    skip    = NULL,     # 跳过指定指标
#    digits  = 4L        # 全局默认小数位（单条可覆盖）
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$cleaned、ctx$data$imputed 中新增指标列；
#      ctx$results$computed_indices（已计算指标名 + 统计摘要）
#  文件: Tables/Table Index Summary.csv
#  依赖: dplyr（case_when 条件公式）
#
#  # ── 公式隐含单位假设 ────────────────────────────────────────────────────
#  所有公式基于以下标准单位（与 column_mapping 映射后的数据字典一致）：
#    血液学: WBC/Neutrophil_Count/Lymphocytes/Monocyte/Platelet_Count = K/uL（10^9/L）
#            Hemoglobin = g/dL, Hematocrit = %, RDW = %
#            自动校准见全局 R/hematology_units.R（Platelet 禁止 med>50 误 ÷1000）
#    生化:   Albumin/Globulin = g/dL, Creatinine/BUN/Uric_Acid = mg/dL
#            Glucose = mg/dL, HbA1c = %, Insulin = uU/mL
#            Bilirubin = mg/dL, ALT/AST/LD = IU/L
#            Sodium/Potassium/Chloride/AnionGap = mEq/L
#    血脂:   Total_Cholesterol/Triglycerides/HDL/LDL = mg/dL
#    炎症:   CRP/HSCRP = mg/L, Fibrinogen = mg/dL
#    体征:   Weight = kg, Height = cm, Waist_circumference = cm
#            SBP/DBP = mmHg
#    尿液:   Urine_Creatinine = mg/dL, AlbuminUrine = mg/L
#
#  公式中常见常数含义:
#    * 17.1   → Bilirubin mg/dL → μmol/L (ALBI)
#    * /18    → Glucose mg/dL → mmol/L (GPR, SOSM)
#    * *0.0259→ HDL mg/dL → mmol/L (LHR)
#    * 28.7 / 46.7 → eAG = 28.7*HbA1c - 46.7 (SHR)
#    * /22.5  → HOMA-IR 常数 (Glucose mg/dL * Insulin uU/mL)
#    * /40    → AST 正常值上限 ULN=40 IU/L (APRI = (AST/ULN)/Platelet(10^9/L)*100)
#
#  AFR = Fibrinogen(mg/dL)*10/Albumin(g/dL)，文献常用 ×1000 尺度 FAR
#  BUN_Cr = BUN(mg/dL)/Creatinine(mg/dL)，肾前性氮质血症常用比值
#  UA_CR  = Uric_Acid(mg/dL)/Creatinine(mg/dL)，即 UA/CR（无量纲比值；同 UA_CrR）
###############################################################################

# ── 指标定义（按依赖顺序）─────────────────────────────────────────────────────
.idx_definitions <- function() {

  # ──────────────── 第一组：基础指标（无依赖）───────────────────────
  basic <- list(
    # --- 人体测量 ---
    list(name = "BMI",
         expr = "Weight / (Height / 100)^2",
         digits = 2),

    # --- 炎症 / 免疫比值 ---
    list(name = "NLR",
         expr = "Neutrophil_Count / Lymphocytes",
         digits = 4),
    list(name = "PLR",
         expr = "Platelet_Count / Lymphocytes",
         digits = 4),
    list(name = "SII",
         expr = "Platelet_Count * Neutrophil_Count / Lymphocytes",
         digits = 4),
    list(name = "NLPR",
         expr = "Neutrophil_Count * 100 / (Lymphocytes * Platelet_Count)",
         digits = 4),
    list(name = "ANLR",
         expr = "Albumin / (Neutrophil_Count / Lymphocytes)",
         digits = 4),
    list(name = "LHR",
         expr = "Lymphocytes / (HDL * 0.0259)",
         digits = 4),
    list(name = "PHR",
         expr = "Platelet_Count / HDL",
         digits = 4),
    list(name = "HALP",
         expr = "((Hemoglobin * 10) * (Albumin * 10) * Lymphocytes) / Platelet_Count",
         digits = 4),
    list(name = "GLR",
         expr = "Glucose / Lymphocytes",
         digits = 4),
    list(name = "WPR",
         expr = "WBC / Platelet_Count",
         digits = 4),

    # --- 血脂 / 脂代谢 ---
    list(name = "AIP",
         expr = "log10(Triglycerides / HDL)",
         digits = 4),
    list(name = "TyG",
         expr = "log(Glucose * Triglycerides / 2)",
         digits = 4),
    list(name = "NHHR",
         expr = "(Total_Cholesterol - HDL) / HDL",
         digits = 4),
    list(name = "RC",
         expr = "Total_Cholesterol - HDL - LDL",
         digits = 4),
    list(name = "TG_HDL_C",
         expr = "Triglycerides / HDL",
         digits = 4),
    list(name = "TC_HDL",
         expr = "Total_Cholesterol / HDL",
         digits = 4),
    list(name = "NHDL",
         expr = "Total_Cholesterol - HDL",
         digits = 4),
    list(name = "AC",
         expr = "(Total_Cholesterol - HDL) / HDL",
         digits = 4),
    list(name = "CRI_I",
         expr = "Total_Cholesterol / HDL",
         digits = 4),
    list(name = "CRI_II",
         expr = "LDL / HDL",
         digits = 4),
    # 22_depression 课题：牙周炎分级（原生列，0=无 1=轻 2=中 3=重）按原生指标注册，
    # 供 analysis_exclusion / pipeline_indices_using_vars 解析组成变量（=自身）
    list(name = "Periodontitis",
         expr = "Periodontitis",
         digits = 0L),
  # HRS OAScore_z：由 Age + HbA1c + Total_Cholesterol 线性组合（与 D08 标定一致）
    list(name = "OAScore_z",
         expr = "-3.4545580572 + 0.0878582042*Age - 0.4612526460*HbA1c + 0.0005126326*Total_Cholesterol",
         digits = 6),
    list(name = "LCI",
         expr = "((Total_Cholesterol / 38.67) * (Triglycerides / 88.57) * (LDL / 38.67)) / (HDL / 38.67)",
         digits = 4),
    list(name = "CHG",
         expr = "log(Total_Cholesterol * Glucose / (HDL / 2))",
         digits = 4),
    list(name = "AIP_BMI",
         expr = "log10(Triglycerides / HDL) * Weight / (Height / 100)^2",
         digits = 4),
    list(name = "TyG_BMI",
         expr = "log(Triglycerides * Glucose / 2) * Weight / (Height / 100)^2",
         digits = 4),
    list(name = "TCBI",
         expr = "Triglycerides * Total_Cholesterol * Weight / 1000",
         digits = 4),
    list(name = "HbA1c_HDL_C",
         expr = "HbA1c / HDL",
         digits = 4),
    list(name = "ALT_HDL_C",
         expr = "ALT / HDL",
         digits = 4),

    # --- 糖代谢 ---
    list(name = "SHR",
         expr = "Glucose / (28.7 * HbA1c - 46.7)",
         digits = 4),
    list(name = "HGI",
         expr = "HbA1c - (0.01 * Glucose + 5.04)",
         digits = 4),
    list(name = "GPR",
         expr = "(Glucose / 18) / Potassium",
         digits = 4),

    # --- 肝功能 ---
    list(name = "De_Ritis",
         expr = "AST / ALT",
         digits = 4),
    list(name = "FIB4",
         expr = "Age * AST / (Platelet_Count * sqrt(ALT))",
         digits = 4),
    list(name = "APRI",
         expr = "(AST / 40) / Platelet_Count * 100",
         digits = 4),
    list(name = "ALBI",
         expr = "log10(Bilirubin_Total * 17.1) * 0.66 + (10 * Albumin) * (-0.085)",
         digits = 4),
    list(name = "AGR",
         expr = "Albumin / Globulin",
         digits = 4),
    list(name = "BAR",
         expr = "BUN / Albumin",
         digits = 4),
    list(name = "AFR",
         expr = "Fibrinogen * 10 / Albumin",
         digits = 4),
    list(name = "LAR",
         expr = "LD / Albumin",
         digits = 4),
    list(name = "log2LAR",
         expr = "log2(LD / Albumin)",
         digits = 4),
    list(name = "ALI",
         expr = "(Weight / (Height / 100)^2) * Albumin / (Neutrophil_Count / Lymphocytes)",
         digits = 4),

    # --- 肾功能 ---
    list(name = "CAR",
         expr = "Creatinine / Albumin",
         digits = 4),
    list(name = "UA_CrR",
         expr = "Uric_Acid / Creatinine",
         digits = 4),
    list(name = "UA_CR",
         expr = "Uric_Acid / Creatinine",
         digits = 4),
    list(name = "BUN_Cr",
         expr = "BUN / Creatinine",
         digits = 4),
    list(name = "UACR",
         expr = "if (exists('Urine_Creatinine')) get(if (exists('Albumin_Urine')) 'Albumin_Urine' else 'AlbuminUrine') / (Urine_Creatinine * 0.01) else get(if (exists('Albumin_Creatinine')) 'Albumin_Creatinine' else 'AlbuminCreatinine')",
         digits = 4),

    # --- 血液学 ---
    # 实验室原生血红蛋白：identity，供轨迹/ML 单指标全流程（日列来自 labhemoglobin）
    list(name = "Hemoglobin",
         expr = "Hemoglobin",
         digits = 4),
    list(name = "RAR",
         expr = "RDW / Albumin",
         digits = 4),
    list(name = "MCH",
         expr = "Hemoglobin / RBC * 10",
         digits = 4),
    list(name = "MCV",
         expr = "Hematocrit / RBC * 10",
         digits = 4),
    list(name = "MCHC",
         expr = "Hemoglobin / Hematocrit * 100",
         digits = 4),
    list(name = "RDW_CV",
         expr = "RDW * RBC / Hematocrit",
         digits = 4),
    list(name = "HHR",
         expr = "Hemoglobin / Hematocrit",
         digits = 4),
    list(name = "HRR",
         expr = "Hemoglobin / RDW",
         digits = 4),

    # --- 尿酸 / 其他 ---
    list(name = "UHR",
         expr = "Uric_Acid / HDL",
         digits = 4),
    list(name = "PNI",
         expr = "10 * Albumin + Lymphocytes * 5",
         digits = 4),
    list(name = "METSIR",
         expr = "log((2 * Glucose + Triglycerides) * (Weight / (Height / 100)^2)) / log(HDL)",
         digits = 4),
    list(name = "EASIX",
         expr = "LD * Creatinine / Platelet_Count",
         digits = 4),
    list(name = "SOSM",
         expr = "1.86 * (Sodium + Potassium) + 1.15 * Glucose / 18 + BUN * 0.375 + 14",
         digits = 4),
    list(name = "ACAG",
         expr = "(4.4 - Albumin) * 2.5 + AnionGap",
         digits = 4),

    # --- 体脂 / 体型 ---
    list(name = "ABSI",
         expr = "Waist_circumference / ((BMI^(2/3)) * (Height^(1/2)))",
         digits = 4),
    list(name = "BRI",
         expr = paste0(
           "364.2 - 365.5 * sqrt(1 - ",
           "((Waist_circumference / (2 * pi)) / (0.5 * Height))^2)"
         ),
         digits = 4),
    list(name = "WWI",
         expr = "Waist_circumference / sqrt(Weight)",
         digits = 4),
    list(name = "WHtR",
         expr = "Waist_circumference / Height",
         digits = 4),
    list(name = "CMI",
         expr = "(Triglycerides / HDL) * (Waist_circumference / Height)",
         digits = 4),

    # --- 炎症 / 免疫（新增）---
    list(name = "AISI",
         expr = paste0(
           "Neutrophil_Count * Platelet_Count * ",
           "Monocyte / Lymphocytes"
         ),
         digits = 4),
    list(name = "SIRI",
         expr = "Neutrophil_Count * Monocyte / Lymphocytes",
         digits = 4),
    list(name = "LMR",
         expr = "Lymphocytes / Monocyte",
         digits = 4),
    list(name = "MLR",
         expr = "Monocyte / Lymphocytes",
         digits = 4),
    list(name = "PIV",
         expr = paste0(
           "Platelet_Count * Neutrophil_Count * ",
           "Monocyte / Lymphocytes"
         ),
         digits = 4),
    list(name = "SIIR",
         expr = paste0(
           "Neutrophil_Count * Monocyte * ",
           "Platelet_Count / Lymphocytes"
         ),
         digits = 4),
    list(name = "SIS",
         expr = paste0(
           "dplyr::case_when(",
           "Lymphocytes / Monocyte > 4.44 & Albumin > 4.0 ~ 0, ",
           "Lymphocytes / Monocyte <= 4.44 & Albumin <= 4.0 ~ 2, ",
           "TRUE ~ 1)"
         ),
         digits = 0L),
    list(name = "MHR",
         expr = "Monocyte / HDL",
         digits = 4),
    list(name = "NMLR",
         expr = paste0(
           "(Monocyte + Neutrophil_Count) ",
           "/ Lymphocytes"
         ),
         digits = 4),
    list(name = "CALLY",
         expr = "(Albumin / 10) * Lymphocytes / (HSCRP * 10)",
         digits = 4),
    list(name = "CLR",
         expr = "(HSCRP / 10) * Lymphocytes",
         digits = 4),
    list(name = "CTI",
         expr = paste0(
           "0.412 * log(HSCRP / 10) + ",
           "log((Glucose * Triglycerides) / 2)"
         ),
         digits = 4),
    list(name = "hs_CRP_HDL_C",
         expr = "HSCRP / (HDL / 1000)",
         digits = 4),

    # --- 脂代谢衍生 ---
    list(name = "AIP_WC",
         expr = "log10(Triglycerides / HDL) * Waist_circumference",
         digits = 4),
    list(name = "AIP_WHtR",
         expr = "log10(Triglycerides / HDL) * (Waist_circumference / Height)",
         digits = 4),
    list(name = "WTI",
         expr = "log((Triglycerides * Waist_circumference) / 2)",
         digits = 4),

    # --- TyG 衍生 ---
    list(name = "TyG_WHtR",
         expr = paste0(
           "log((Glucose * Triglycerides) / 2) * ",
           "(Waist_circumference / Height)"
         ),
         digits = 4),
    list(name = "TyG_WC",
         expr = "log((Glucose * Triglycerides) / 2) * Waist_circumference",
         digits = 4),
    list(name = "TyG_WWI",
         expr = paste0(
           "log((Glucose * Triglycerides) / 2) * ",
           "(Waist_circumference / sqrt(Weight))"
         ),
         digits = 4),
    list(name = "TyG_ABSI",
         expr = paste0(
           "log((Glucose * Triglycerides) / 2) * ",
           "(Waist_circumference / ((BMI^(2/3)) * (Height^(1/2))))"
         ),
         digits = 4),

    # --- RC 衍生 ---
    list(name = "RCII",
         expr = "(Total_Cholesterol - HDL - LDL) * HSCRP / 10",
         digits = 4),
    list(name = "lnRCII",
         expr = "log((Total_Cholesterol - HDL - LDL) * HSCRP / 10)",
         digits = 4),

    # --- 糖代谢衍生 ---
    list(name = "HOMA_IR",
         expr = "Glucose * Insulin / 22.5",
         digits = 4),
    list(name = "MCMI",
         expr = paste0(
           "log(Triglycerides * Glucose / HDL) * ",
           "(Waist_circumference / Height)"
         ),
         digits = 4),
    list(name = "eGDR",
         expr = paste0(
           "21.158 - (0.09 * Waist_circumference) - ",
           "(3.407 * ifelse(Hypertension == 'Yes', 1, 0)) - ",
           "(0.551 * HbA1c)"
         ),
         digits = 4),

    # --- 肝功能衍生 ---
    list(name = "HSI",
         expr = paste0(
           "8 * (ALT / AST) + BMI + ",
           "ifelse(Gender == 'Female', 2, 0) + ",
           "ifelse(Diabetes == 'Yes', 2, 0)"
         ),
         digits = 4),
    list(name = "NFS",
         expr = paste0(
           "-1.675 + 0.037 * Age + 0.094 * BMI + ",
           "1.13 * ifelse(Diabetes == 'Yes', 1, 0) + ",
           "0.99 * (ALT / AST) - 0.013 * Platelet_Count - ",
           "0.66 * Albumin"
         ),
         digits = 4)
  )

  # ──────────────── 第二组：条件评分中间变量 ────────────────
  conut_intermediates <- list(
    list(name = "alb_score",
         expr = paste0(
           "dplyr::case_when(",
           "Albumin > 3.5 ~ 0, ",
           "Albumin >= 3.0 & Albumin <= 3.49 ~ 2, ",
           "Albumin >= 2.5 & Albumin <= 2.99 ~ 4, ",
           "Albumin < 2.5 ~ 6, ",
           "TRUE ~ NA_real_)"
         ),
         digits = NULL,
         intermediate = TRUE),

    list(name = "lymp_score",
         expr = paste0(
           "dplyr::case_when(",
           "Lymphocytes * 1000 > 1600 ~ 0, ",
           "Lymphocytes * 1000 >= 1200 & Lymphocytes * 1000 <= 1599 ~ 1, ",
           "Lymphocytes * 1000 >= 800 & Lymphocytes * 1000 <= 1199 ~ 2, ",
           "Lymphocytes * 1000 < 800 ~ 3, ",
           "TRUE ~ NA_real_)"
         ),
         digits = NULL,
         intermediate = TRUE),

    list(name = "chol_score",
         expr = paste0(
           "dplyr::case_when(",
           "Total_Cholesterol > 180 ~ 0, ",
           "Total_Cholesterol >= 140 & Total_Cholesterol <= 179 ~ 1, ",
           "Total_Cholesterol >= 100 & Total_Cholesterol <= 139 ~ 2, ",
           "Total_Cholesterol < 100 ~ 3, ",
           "TRUE ~ NA_real_)"
         ),
         digits = NULL,
         intermediate = TRUE)
  )

  # ──────────────── 第三组：依赖评分的指标 ────────────────
  conut_final <- list(
    list(name = "CONUT_score",
         expr = "alb_score + lymp_score + chol_score",
         digits = NULL)
  )

  # ──────────────── 第四组：链式依赖 ────────────────
  chain <- list(
    list(name = "MBP",
         expr = "DBP + 0.4 * (SBP - DBP)",
         digits = 4,
         intermediate = TRUE),

    list(name = "ePWV",
         expr = paste0(
           "9.587 - 0.402 * Age + 0.00456 * Age^2 ",
           "- 0.00002621 * Age^2 * MBP ",
           "+ 0.003176 * Age * MBP - 0.01832"
         ),
         digits = 4),

    list(name = "lbLDL_C",
         expr = "1.43 * LDL - 0.14 * log(Triglycerides) * LDL - 8.99",
         digits = 4,
         intermediate = TRUE),

    list(name = "sdLDL_C",
         expr = "LDL - lbLDL_C",
         digits = 4),

    # ALT_AST_ratio_flag → FSI
    list(name = "ALT_AST_ratio_flag",
         expr = "ifelse((ALT / AST) >= 1.33, 1, 0)",
         digits = NULL,
         intermediate = TRUE),
    list(name = "FSI",
         expr = paste0(
           "-7.981 + 0.011 * Age + ",
           "(-0.146) * ifelse(Gender == 'Female', 1, 0) + ",
           "0.173 * BMI + 0.007 * Triglycerides + ",
           "0.593 * ifelse(Hypertension == 'Yes', 1, 0) + ",
           "0.789 * ifelse(Diabetes == 'Yes', 1, 0) + ",
           "1.1 * ALT_AST_ratio_flag"
         ),
         digits = 4),

    # METSIR → METS_VF
    list(name = "METS_VF",
         expr = paste0(
           "4.466 + 0.011 * (log(METSIR))^3 + ",
           "3.239 * (log(Waist_circumference / Height))^3 + ",
           "0.319 * ifelse(Gender == 1, 1, 0) + ",
           "0.594 * log(Age)"
         ),
         digits = 4)
  )

  # ──────────────── 第五组：性别条件指标 ────────────────
  gender_conditional <- list(
    list(name = "GNRI",
         expr = paste0(
           "dplyr::case_when(",
           "Gender == 'Male' ~ (1.489 * Albumin * 10) + 41.7 * (Weight / (0.75 * Height - 62.5)), ",
           "Gender == 'Female' ~ (1.489 * Albumin * 10) + 41.7 * (Weight / (0.60 * Height - 40)), ",
           "TRUE ~ NA_real_)"
         ),
         digits = 4),

    list(name = "ZJU",
         expr = paste0(
           "dplyr::case_when(",
           "Gender == 'Male' ~ Glucose / 18 + Weight / (Height / 100)^2 + 3 * ALT / AST + Triglycerides, ",
           "Gender == 'Female' ~ Glucose / 18 + Weight / (Height / 100)^2 + 3 * ALT / AST + 2 + Triglycerides, ",
           "TRUE ~ NA_real_)"
         ),
         digits = 4),

    list(name = "VAI",
         expr = paste0(
           "dplyr::case_when(",
           "Gender == 'Male' ~ (Waist_circumference / (39.68 + 1.88 * BMI)) * ",
           "(Triglycerides / 1.03) * (1.31 / HDL), ",
           "Gender == 'Female' ~ (Waist_circumference / (36.58 + 1.89 * BMI)) * ",
           "(Triglycerides / 0.81) * (1.52 / HDL), ",
           "TRUE ~ NA_real_)"
         ),
         digits = 4),

    list(name = "RFM",
         expr = paste0(
           "dplyr::case_when(",
           "Gender == 'Male' ~ 64 - 20 * (Height / Waist_circumference), ",
           "Gender == 'Female' ~ 76 - 20 * (Height / Waist_circumference), ",
           "TRUE ~ NA_real_)"
         ),
         digits = 4),

    list(name = "LAP",
         expr = paste0(
           "dplyr::case_when(",
           "Gender == 'Male' ~ (Waist_circumference - 65) * Triglycerides / 88.57, ",
           "Gender == 'Female' ~ (Waist_circumference - 85) * Triglycerides / 88.57, ",
           "TRUE ~ NA_real_)"
         ),
         digits = 4)
  )
  c(basic, conut_intermediates, conut_final, chain, gender_conditional)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_index <- function(ctx, ...) {
  cfg     <- ctx$config
  idx_cfg <- cfg$index %||% list()

  if (!isTRUE(idx_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("index: enable = FALSE，跳过。")
    return(ctx)
  }

  # ── 依赖检查 ──
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("index: 需要 dplyr 包（case_when 条件公式）。")
  }

  # ── 确定数据槽 ──
  data_slots <- list()
  if (!is.null(ctx$data$imputed) && is.data.frame(ctx$data$imputed))
    data_slots$imputed <- ctx$data$imputed
  if (!is.null(ctx$data$mapped) && is.data.frame(ctx$data$mapped))
    data_slots$mapped <- ctx$data$mapped
  if (!is.null(ctx$data$cleaned) && is.data.frame(ctx$data$cleaned))
    data_slots$cleaned <- ctx$data$cleaned
  if (!length(data_slots)) {
    rawdata_path <- cfg$data$rawdata_path
    if (!is.null(rawdata_path) && file.exists(rawdata_path)) {
      rawdata_obj <- cfg$data$rawdata_obj %||% NULL
      env <- new.env()
      load(rawdata_path, envir = env)
      if (!is.null(rawdata_obj) && exists(rawdata_obj, envir = env)) {
        df <- get(rawdata_obj, envir = env)
      } else {
        df <- env[[ls(env)[1]]]
      }
      data_slots$imputed <- df
      ctx$data$imputed <- df
      cli::cli_alert_info("index: 从 rawdata_path 加载数据。")
    } else {
      stop("index: 无可用数据（ctx$data$imputed / mapped / cleaned 均为空）。")
    }
  }

  # ── 获取指标列表 ──
  all_defs  <- .idx_definitions()
  only      <- idx_cfg$only
  skip      <- idx_cfg$skip
  global_dg <- idx_cfg$digits %||% 4L

  # 筛选
  if (!is.null(only) && length(only)) {
    all_defs <- Filter(function(d) d$name %in% only, all_defs)
  }
  if (!is.null(skip) && length(skip)) {
    all_defs <- Filter(function(d) !(d$name %in% skip), all_defs)
  }

  cli::cli_h2("Computing derived indices ({length(all_defs)} definitions)")

  # ── 血液学单位自动校正（全局：R/hematology_units.R）─────────────────────
  if (!exists("scale_hematology_dataframe", mode = "function")) {
    .root_hema <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% getwd()
    .hu <- file.path(.root_hema, "R", "hematology_units.R")
    if (file.exists(.hu)) source(.hu, local = FALSE)
  }
  if (!exists("scale_hematology_dataframe", mode = "function")) {
    stop(
      "index: 缺少 scale_hematology_dataframe（请 source R/hematology_units.R 或 R/utils.R）",
      call. = FALSE
    )
  }
  for (sn in names(data_slots)) {
    data_slots[[sn]] <- scale_hematology_dataframe(data_slots[[sn]], verbose = TRUE)
  }
  traj_util <- file.path(cfg$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) {
    source(traj_util, local = FALSE)
    if (exists("trajectory_index_column_aliases", mode = "function")) {
      for (sn in names(data_slots)) {
        data_slots[[sn]] <- trajectory_index_column_aliases(data_slots[[sn]])
      }
    }
  }

  # ── 逐个计算 ──
  computed     <- character(0)
  skipped      <- character(0)
  intermediate <- character(0)
  summary_rows <- list()

  for (def in all_defs) {
    idx_name    <- def$name
    idx_expr    <- def$expr
    idx_digits  <- def$digits %||% global_dg
    is_intermed <- isTRUE(def$intermediate %||% FALSE)

    success <- FALSE
    for (slot_name in names(data_slots)) {
      df <- data_slots[[slot_name]]

      tryCatch({
        values <- with(df, eval(parse(text = idx_expr)))
        values[!is.finite(values)] <- NA_real_

        if (!is.null(idx_digits) && is.numeric(idx_digits))
          values <- round(values, as.integer(idx_digits))

        df[[idx_name]] <- values
        data_slots[[slot_name]] <- df
        success <- TRUE

        # 只为第一个 slot 记录摘要（避免重复）
        if (slot_name == names(data_slots)[1]) {
          n_valid <- sum(!is.na(values))
          n_na    <- sum(is.na(values))

          if (is_intermed) {
            intermediate <- c(intermediate, idx_name)
            cli::cli_alert_info("  [intermediate] {idx_name}: n={n_valid}, NA={n_na}")
          } else {
            rng <- range(values, na.rm = TRUE)
            cli::cli_alert_success("  {idx_name}: n={n_valid}, range=[{round(rng[1],4)}, {round(rng[2],4)}]")
            summary_rows[[length(summary_rows) + 1L]] <- data.frame(
              index   = idx_name,
              formula = idx_expr,
              n_valid = n_valid,
              n_na    = n_na,
              min     = round(rng[1], 4),
              median  = round(stats::median(values, na.rm = TRUE), 4),
              max     = round(rng[2], 4),
              stringsAsFactors = FALSE
            )
          }
        }
      }, error = function(e) {
        if (slot_name == names(data_slots)[1]) {
          cli::cli_alert_warning("  {idx_name}: skipped ({conditionMessage(e)})")
        }
      })
    }

    if (success) {
      computed <- c(computed, idx_name)
    } else {
      skipped <- c(skipped, idx_name)
    }
  }

  # ── 写回 ctx ──
  for (slot_name in names(data_slots)) {
    ctx$data[[slot_name]] <- data_slots[[slot_name]]
  }
  # harmonize 后指标写在 mapped；同步 cleaned 供下游兼容（imputation 亦读 mapped）
  if (!is.null(ctx$data$mapped) && is.data.frame(ctx$data$mapped))
    ctx$data$cleaned <- ctx$data$mapped

  # ── 保存摘要 ──
  if (length(summary_rows)) {
    summary_df <- do.call(rbind, summary_rows)
    ctx$results$computed_indices      <- summary_df
    ctx$results$computed_index_names   <- computed
    ctx$results$computed_index_intermediate <- intermediate

    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    tbl_path <- file.path(tbl_dir, "Table Index Summary.csv")
    tryCatch({
      utils::write.csv(summary_df, tbl_path, row.names = FALSE)
      cli::cli_alert_success("Saved: {basename(tbl_path)}")
    }, error = function(e) {
      cli::cli_alert_warning("index: 摘要表保存失败: {e$message}")
    })
  }

  cli::cli_h2("Index summary")
  cli::cli_alert_success(
    "Computed: {length(setdiff(computed, intermediate))} indices, "
  )
  if (length(intermediate))
    cli::cli_alert_info("Intermediate: {length(intermediate)} ({paste(intermediate, collapse=', ')})")
  if (length(skipped))
    cli::cli_alert_warning("Skipped: {length(skipped)} ({paste(skipped, collapse=', ')})")

  ctx
}

# ── 从指标公式递归解析原始计算组分 ──────────────────────────────────────────
pipeline_index_definition_map <- function() {
  if (!exists(".idx_definitions", mode = "function")) {
    stop("EXCLUSION_COMPONENT_RESOLVE_FAIL: .idx_definitions 不可用", call. = FALSE)
  }
  defs <- .idx_definitions()
  nms <- vapply(defs, function(d) as.character(d$name)[1L], character(1))
  exprs <- vapply(defs, function(d) as.character(d$expr)[1L], character(1))
  stats::setNames(exprs, nms)
}

pipeline_exclusion_normalize_name <- function(x) {
  tolower(gsub("[^[:alnum:]]", "", as.character(x)))
}

pipeline_index_raw_components <- function(
    index_var,
    definitions = pipeline_index_definition_map(),
    visited = character(0)) {
  index_var <- as.character(index_var)[1L]
  if (is.na(index_var) || !nzchar(index_var)) {
    stop(
      "EXCLUSION_COMPONENT_RESOLVE_FAIL: 无法解析指标 ", index_var,
      call. = FALSE
    )
  }
  # 原始血检/临床列：不在复合指标公式表中，自身即暴露成分
  if (!index_var %in% names(definitions)) {
    return(index_var)
  }
  if (index_var %in% visited) {
    stop(
      "EXCLUSION_COMPONENT_RESOLVE_FAIL: 指标公式存在循环依赖: ",
      paste(c(visited, index_var), collapse = " -> "),
      call. = FALSE
    )
  }

  expr_txt <- as.character(definitions[[index_var]])[1L]
  parsed <- tryCatch(parse(text = expr_txt), error = function(e) NULL)
  if (is.null(parsed)) {
    stop(
      "EXCLUSION_COMPONENT_RESOLVE_FAIL: 指标 ", index_var, " 公式解析失败",
      call. = FALSE
    )
  }
  vars <- unique(all.vars(parsed))
  nested <- vars[vars %in% names(definitions)]
  raw <- vars[!vars %in% names(definitions)]
  for (nm in nested) {
    # 原生 identity 指标（如 Periodontitis = Periodontitis）：自身即原始列，
    # 计入 raw、不再递归，避免被误判为循环依赖
    if (identical(nm, index_var)) {
      raw <- c(raw, nm)
      next
    }
    raw <- c(
      raw,
      pipeline_index_raw_components(
        nm,
        definitions = definitions,
        visited = c(visited, index_var)
      )
    )
  }
  unique(raw[nzchar(raw)])
}

pipeline_indices_using_vars <- function(
    vars,
    indices = names(pipeline_index_definition_map()),
    definitions = pipeline_index_definition_map()) {
  vars_norm <- unique(pipeline_exclusion_normalize_name(vars))
  vars_norm <- vars_norm[nzchar(vars_norm)]
  indices <- intersect(as.character(indices), names(definitions))
  indices[vapply(indices, function(ix) {
    components <- pipeline_index_raw_components(ix, definitions = definitions)
    any(pipeline_exclusion_normalize_name(components) %in% vars_norm)
  }, logical(1))]
}

# 兼容旧接口；现在只返回递归展开后的原始组成变量，不再混入函数名/字符串。
index_get_formula_components <- function(index_name, visited = character(0)) {
  pipeline_index_raw_components(index_name, visited = visited)
}

register_block(
  "index",
  block_index,
  "复合指标计算：BMI, SII, CONUT_score 等 ~65 个指标，公式驱动、可扩展"
)
