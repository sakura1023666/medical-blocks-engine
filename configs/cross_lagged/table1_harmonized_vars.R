###############################################################################
#  configs/cross_lagged/table1_harmonized_vars.R
#  三库 Table 1：只用交集变量，保证 CHARLS/ELSA/HRS 行顺序与显示名完全一致
#  （Race、Waist 等非共有列一律不进统一 Table 1）
#
#  血检：仅纳入三库均存在、且缺失率 ≤ 69% 的指标（HRS 约 68–69% 仍保留并插补；
#        CRP 在 HRS 约 69.5% → 不纳入）。超 69% 不 force-keep。
#  mapping 后标准名：HbA1c, HDL, Total_Cholesterol
###############################################################################

# 三库均有且 miss≤69% 的共有血检（post column_mapping）
.CROSS_LAGGED_SHARED_LAB_VARS <- c(
  "HbA1c",
  "HDL",
  "Total_Cholesterol"
)

# 原始/别名：data_clean / MICE 强制保留时兼容 rename 前
.CROSS_LAGGED_SHARED_LAB_VARS_ALIASES <- c(
  "HbA1c", "HDL", "Total_Cholesterol", "TC"
)

.CROSS_LAGGED_TABLE1_INCLUDE_VARS <- c(
  "Age",
  "Gender",
  "Education",
  "Marital_Status",
  "Smoking",
  "Alcohol_drinking",
  "Weight",
  "Height",
  "BMI",
  "Hypertension",
  "T2DM",
  "Cancer",
  # 共有血检（miss≤69% 规则）
  "HbA1c",
  "HDL",
  "Total_Cholesterol",
  "FI"
)

.CROSS_LAGGED_TABLE1_LABELS <- list(
  Age                = "Age, years",
  Gender             = "Gender",
  Education          = "Education",
  Marital_Status     = "Marital status",
  Smoking            = "Smoking",
  Alcohol_drinking   = "Alcohol drinking",
  Weight             = "Weight, kg",
  Height             = "Height, cm",
  BMI                = "BMI, kg/m²",
  Hypertension       = "Hypertension",
  T2DM               = "T2DM",
  Cancer             = "Cancer",
  HbA1c              = "HbA1c, %",
  HDL                = "HDL-C, mg/dL",
  Total_Cholesterol  = "Total cholesterol, mg/dL",
  FI                 = "Frailty Index"
)

# 显式排除非共有 / 库特异 / 三库 miss>69%（如 HRS CRP≈69.5%）
.CROSS_LAGGED_TABLE1_EXCLUDE_VARS <- c(
  "Frailty", "ID", "SEQN", "Age_Group", "Cohort", "Country",
  "Race", "Waist_circumference",
  "Familysize", "Family_per_capita_consumption", "Executive", "Memeory",
  "Hip", "WaistHipRatio", "SittingHeight",
  "HR", "PP", "SBP", "DBP",
  "WBC", "Hemoglobin", "Hematocrit", "Platelet_Count", "MCV",
  "BUN", "Creatinine", "Uric_Acid", "Glucose",
  "Triglycerides", "LDL", "TyG", "TyG_BMI",
  "CRP", "HSCRP", "Fibrinogen", "Ferritin",
  "Stroke", "Hyperlipidemia", "Pulmonary_Disease", "Liver_Disease",
  "Cardiopathy", "Kidney_Disease", "Stomach_Disease", "Psychiatric",
  "Amnesia", "Rheumatic_Diseases", "Asthma"
)

# logistic / RCS / 图题等展示名（数据列仍为 FI）
.CROSS_LAGGED_INDEX_DISPLAY_NAME <- "Frailty Index"
