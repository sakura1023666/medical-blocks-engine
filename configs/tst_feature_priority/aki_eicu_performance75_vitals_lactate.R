# AKI/eICU — 自 44 项 whitelist 筛出的高判别子集（2026-08-31）
# 5-fold CV + test（418 人、同一 split）：
#   主集 vitals_lactate 9 项：days1-3 CV=0.761, test=0.810
#   备选 severity_mix 10 项：days1-3 CV=0.768, test=0.751
# 勿用 rdw/tbil/magnesium/ptt 单变量 top（test 虚高、CV<0.6，过拟合）

tst_feature_priority_aki_eicu <- function() {
  list(
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 Sat (%)", "SpO2", "O2 Saturation", "SaO2"),
    nibp_mean = c("NIBP mean", "Non-Invasive BP Mean"),
    nibp_systolic = c("NIBP systolic", "Non-Invasive BP Systolic"),
    temperature_c = c("Temperature (C)", "Temperature"),
    gcs_total = c("GCS Total"),
    glucose = c("glucose", "bedside glucose", "Bedside Glucose"),
    lactate = c("lactate")
  )
}

# 备选 10 项（改 config 里 feature_priority_file 并替换为 severity_mix 版同名函数体）：
# tst_feature_priority_aki_eicu_severity_mix <- function() list(
#   lactate = c("lactate"),
#   gcs_total = c("GCS Total"),
#   heart_rate = c("Heart Rate"),
#   respiratory_rate = c("Respiratory Rate"),
#   creatinine = c("creatinine"),
#   bun = c("BUN"),
#   wbc = c("WBC x 1000"),
#   platelets = c("platelets x 1000"),
#   bicarbonate = c("bicarbonate", "HCO3", "Total CO2"),
#   spo2 = c("O2 Sat (%)", "SpO2", "O2 Saturation", "SaO2")
# )
