# AKI / eICU — 扩特征白名单（与 MIMIC 对齐，2026-09-02）
# 依据同 aki_mimic.R；别名对齐 374_eicu_aki_hourly_full_10d.csv。
# 尿量用 Urine；GCS 仅有 Total（外验脚本可拆分）；静态广播见 config。

tst_feature_priority_aki_eicu <- function() {
  list(
    # --- 生命体征 ---
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 Sat (%)", "SpO2", "O2 Saturation", "SaO2"),
    temperature_c = c("Temperature (C)", "Temperature", "Temperature (F)"),
    nibp_mean = c("NIBP mean", "Non-Invasive BP Mean"),
    nibp_systolic = c("NIBP systolic", "Non-Invasive BP Systolic"),
    nibp_diastolic = c("NIBP diastolic", "Non-Invasive BP Diastolic"),
    abp_mean = c("Arterial BP mean", "Invasive BP Mean"),
    cvp = c("CVP"),
    daily_weight = c("Bodyweight (kg)", "Bodyweight (lb)"),
    # --- 神经 ---
    gcs_total = c("GCS Total"),
    gcs_eye = c("GCS Eye Opening", "Eyes"),
    gcs_motor = c("GCS Motor Response", "Motor"),
    gcs_verbal = c("GCS Verbal Response", "Verbal"),
    # --- 肾 / 尿量 ---
    creatinine = c("creatinine"),
    bun = c("BUN"),
    urine_output = c("Urine", "Urine Output (mL)-Urethral Catheter", "URINE CATHETER"),
    albumin = c("albumin"),
    # --- 电解质 / 酸碱 ---
    potassium = c("potassium"),
    sodium = c("sodium"),
    chloride = c("chloride"),
    bicarbonate = c("bicarbonate", "HCO3", "Total CO2"),
    calcium = c("calcium"),
    magnesium = c("magnesium", "Magnesium"),
    phosphate = c("phosphate"),
    anion_gap = c("anion gap"),
    lactate = c("lactate"),
    glucose = c("glucose", "bedside glucose", "Bedside Glucose"),
    # --- 血常规 ---
    hgb = c("Hgb"),
    hct = c("Hct"),
    wbc = c("WBC x 1000"),
    platelets = c("platelets x 1000"),
    rbc = c("RBC"),
    rdw = c("RDW"),
    mcv = c("MCV"),
    # --- 血气 / 通气 ---
    ph = c("pH"),
    pao2 = c("paO2"),
    paco2 = c("paCO2"),
    base_excess = c("Base Excess"),
    fio2 = c("FiO2", "Set Fraction of Inspired Oxygen (FIO2)", "FIO2 (%)"),
    peep = c("PEEP", "PEEP/CPAP"),
    # --- 凝血 / 肝 ---
    inr = c("PT - INR"),
    pt = c("PT"),
    ptt = c("PTT"),
    ast = c("AST (SGOT)"),
    alt = c("ALT (SGPT)"),
    total_bilirubin = c("total bilirubin"),
    # --- 升压药 / 镇静 / 胰岛素 ---
    norepinephrine = c(
      "Norepinephrine (mcg/kg/min)", "Norepinephrine (mcg/min)",
      "Norepinephrine (ml/hr)", "norepinephrine", "Norepinephrine"
    ),
    phenylephrine = c(
      "Phenylephrine (mcg/min)", "Phenylephrine (mcg/kg/min)",
      "Phenylephrine (ml/hr)", "phenylephrine"
    ),
    vasopressin = c(
      "Vasopressin (units/min)", "Vasopressin (ml/hr)", "Vasopressin",
      "vasopressin (units/min)", "VASOPRESSIN"
    ),
    epinephrine = c(
      "Epinephrine (mcg/min)", "Epinephrine (mcg/kg/min)",
      "Epinephrine (ml/hr)", "Epinephrine drip", "EPINEPHrine"
    ),
    dopamine = c("Dopamine (mcg/kg/min)", "Dopamine (ml/hr)", "Dopamine"),
    dobutamine = c("Dobutamine (mcg/kg/min)", "Dobutamine", "DOBUTamine"),
    propofol = c(
      "Propofol (mcg/kg/min)", "Propofol (ml/hr)", "Propofol", "propofol"
    ),
    fentanyl = c(
      "Fentanyl (mcg/hr)", "Fentanyl (ml/hr)", "Fentanyl", "fentanyl", "Fentanyl IV"
    ),
    insulin = c(
      "Insulin (units/hr)", "Insulin (ml/hr)", "Insulin", "insulin regular", "INsulin IV"
    )
  )
}
