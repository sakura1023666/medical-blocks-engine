# Osteoporosis / MIMIC — TST 精简白名单（2026-09-01 实验）
# 仅保留 ICU 死亡最核心动态特征，减少小样本过拟合
# 依据：ICU 死亡常用生命体征+GCS+核心生化；排除冗余（如 MCV/MCH/MCHC 与 RBC/Hgb 重复）
tst_feature_priority_osteoporosis_mimic_lean <- function() {
  list(
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 saturation pulseoxymetry"),
    temperature_c = c("Temperature Fahrenheit", "Temperature Celsius"),
    nibp_mean = c("Non Invasive Blood Pressure mean"),
    gcs_eye = c("GCS - Eye Opening"),
    gcs_motor = c("GCS - Motor Response"),
    gcs_verbal = c("GCS - Verbal Response"),
    creatinine = c("Creatinine (serum)", "Creatinine"),
    bun = c("BUN", "Urea Nitrogen"),
    sodium = c("Sodium (serum)", "Sodium"),
    potassium = c("Potassium (serum)", "Potassium"),
    bicarbonate = c("HCO3 (serum)", "Bicarbonate"),
    anion_gap = c("Anion gap", "Anion Gap"),
    glucose = c("Glucose (serum)", "Glucose"),
    wbc = c("WBC", "White Blood Cells"),
    hgb = c("Hemoglobin"),
    platelets = c("Platelet Count"),
    inr = c("INR", "INR(PT)"),
    ph = c("pH", "PH (Arterial)")
  )
}
