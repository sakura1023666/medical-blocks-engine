# AKI/eICU — 629 人锁定口径下的精选特征（2026-08-31）
#
# 流程：44 项临床 whitelist → 剔除 day1 缺失>30%（审计）→ 再取 severity_mix 10 项
# （CV≈0.768 / test≈0.751，低缺失、适合 24×F×5 + 两阶段）
# 配合 config：patient_missing_threshold=1.0 保证 cohort n=629 不因患者层缺失剔除

tst_feature_priority_aki_eicu <- function() {
  list(
    lactate = c("lactate"),
    gcs_total = c("GCS Total"),
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    creatinine = c("creatinine"),
    bun = c("BUN"),
    wbc = c("WBC x 1000"),
    platelets = c("platelets x 1000"),
    bicarbonate = c("bicarbonate", "HCO3", "Total CO2"),
    spo2 = c("O2 Sat (%)", "SpO2", "O2 Saturation", "SaO2")
  )
}
