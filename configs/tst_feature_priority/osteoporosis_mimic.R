# Osteoporosis / MIMIC — TST 特征白名单
# 依据：ICU 院内死亡通用动态特征（生命体征/GCS/常规实验室/凝血）
#       + 骨质疏松相关骨代谢候选（覆盖不足时由 day1>30% 自动砍掉）
# 禁止：报警、敷料、护理评分、治疗用药文书项
# Spec: docs/superpowers/specs/2026-08-31-tst-disease-feature-whitelist-gate-design.md

tst_feature_priority_osteoporosis_mimic <- function() {
  list(
    # --- ICU 临床核心（院内死亡）---
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 saturation pulseoxymetry"),
    temperature_c = c("Temperature Fahrenheit", "Temperature Celsius"),
    nibp_systolic = c("Non Invasive Blood Pressure systolic"),
    nibp_diastolic = c("Non Invasive Blood Pressure diastolic"),
    nibp_mean = c("Non Invasive Blood Pressure mean"),
    gcs_eye = c("GCS - Eye Opening"),
    gcs_motor = c("GCS - Motor Response"),
    gcs_verbal = c("GCS - Verbal Response"),
    creatinine = c("Creatinine (serum)", "Creatinine"),
    bun = c("BUN", "Urea Nitrogen"),
    sodium = c("Sodium (serum)", "Sodium"),
    potassium = c("Potassium (serum)", "Potassium"),
    chloride = c("Chloride (serum)", "Chloride"),
    bicarbonate = c("HCO3 (serum)", "Bicarbonate"),
    anion_gap = c("Anion gap", "Anion Gap"),
    calcium = c("Calcium non-ionized", "Calcium, Total"),
    magnesium = c("Magnesium"),
    phosphate = c("Phosphorous", "Phosphate"),
    glucose = c("Glucose (serum)", "Glucose"),
    wbc = c("WBC", "White Blood Cells"),
    hgb = c("Hemoglobin"),
    hct = c("Hematocrit (serum)", "Hematocrit"),
    platelets = c("Platelet Count"),
    rbc = c("Red Blood Cells"),
    mcv = c("MCV"),
    mch = c("MCH"),
    mchc = c("MCHC"),
    rdw = c("RDW"),
    inr = c("INR", "INR(PT)"),
    pt = c("PT", "Prothrombin time"),
    ptt = c("PTT"),
    ph = c("pH", "PH (Arterial)"),
    lactate = c("Lactate", "Lactic Acid"),
    base_excess = c("Base Excess", "Arterial Base Excess"),
    pao2 = c("pO2", "Arterial O2 pressure"),
    paco2 = c("pCO2", "Arterial CO2 Pressure"),
    total_co2 = c("Calculated Total CO2", "TCO2 (calc) Arterial"),
    fio2 = c("Inspired O2 Fraction"),
    peep = c("PEEP set"),
    abp_mean = c("Arterial Blood Pressure mean"),
    total_bilirubin = c("Total Bilirubin", "Bilirubin, Total"),
    ast = c("AST", "Asparate Aminotransferase (AST)"),
    alt = c("ALT", "Alanine Aminotransferase (ALT)"),
    alkphos = c("Alkaline Phosphate", "Alkaline Phosphatase"),
    # --- 骨质疏松相关候选（覆盖不足则被 30% 闸门砍掉）---
    albumin = c("Albumin"),
    ionized_calcium = c("Ionized Calcium", "Free Calcium"),
    vitamin_d_25oh = c("25-OH Vitamin D"),
    pth = c("Parathyroid Hormone")
  )
}
