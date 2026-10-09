# AKI/eICU — severity_mix 10 项（CV=0.768, test=0.751 days1-3 logistic）

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
