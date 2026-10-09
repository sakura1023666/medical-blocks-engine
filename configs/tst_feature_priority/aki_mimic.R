# AKI / MIMIC — 白名单（定稿口径：纯 TF Day5≈0.822 五模型最优那版）
# 依据：KDIGO AKI（Cr/尿量）+ ICU 预后常用生命体征/血气/通气/升压药/镇静；
# 文献两阶段 Transformer 动态特征池思想（PMID 40041421）迁移至 AKI 院内死亡。
# 尿量：本课题小时表无标准 Urine Output，Foley 数值为 mL 级尿量（高覆盖）→ urine_output。
# 不含诊断泄漏（Acute_Renal_Failure/CKD 等）；不含 APSIII/SOFA（与 Fig2 对照评分脱钩）。
# 静态 Age/Gender/Weight/Ventilation/CRRT/GCS 由 config$tst_timeseries$static_features 广播，不在此 list。
# 注：2026-09-03 v2 过度 force_keep 血气/潮气量后纯 TF 掉到 0.769；本文件回退定稿池。

tst_feature_priority_aki_mimic <- function() {
  list(
    # --- 生命体征 ---
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 saturation pulseoxymetry"),
    temperature_c = c("Temperature Fahrenheit", "Temperature Celsius"),
    nibp_systolic = c("Non Invasive Blood Pressure systolic"),
    nibp_diastolic = c("Non Invasive Blood Pressure diastolic"),
    nibp_mean = c("Non Invasive Blood Pressure mean"),
    abp_mean = c("Arterial Blood Pressure mean"),
    cvp = c("Central Venous Pressure"),
    daily_weight = c("Daily Weight", "Admission Weight (Kg)"),
    # --- 神经 ---
    gcs_eye = c("GCS - Eye Opening"),
    gcs_motor = c("GCS - Motor Response"),
    gcs_verbal = c("GCS - Verbal Response"),
    # --- 肾 / 尿量 ---
    creatinine = c("Creatinine (serum)", "Creatinine"),
    bun = c("BUN", "Urea Nitrogen"),
    urine_output = c("Foley", "GU Irrigant/Urine Volume Out", "Urine Volume"),
    ultrafiltrate = c("Ultrafiltrate Output"),
    # --- 电解质 / 酸碱 ---
    sodium = c("Sodium (serum)", "Sodium"),
    potassium = c("Potassium (serum)", "Potassium"),
    chloride = c("Chloride (serum)", "Chloride"),
    bicarbonate = c("HCO3 (serum)", "Bicarbonate"),
    anion_gap = c("Anion gap", "Anion Gap"),
    calcium = c("Calcium non-ionized", "Calcium, Total"),
    magnesium = c("Magnesium"),
    phosphate = c("Phosphorous", "Phosphate"),
    glucose = c("Glucose (serum)", "Glucose"),
    # --- 血常规 ---
    wbc = c("WBC", "White Blood Cells"),
    hgb = c("Hemoglobin"),
    hct = c("Hematocrit (serum)", "Hematocrit"),
    platelets = c("Platelet Count"),
    rbc = c("Red Blood Cells"),
    mcv = c("MCV"),
    mch = c("MCH"),
    mchc = c("MCHC"),
    rdw = c("RDW"),
    # --- 凝血 ---
    inr = c("INR", "INR(PT)"),
    pt = c("PT", "Prothrombin time"),
    ptt = c("PTT"),
    # --- 血气 / 通气（force_keep）---
    ph = c("pH", "PH (Arterial)"),
    lactate = c("Lactate", "Lactic Acid"),
    base_excess = c("Base Excess", "Arterial Base Excess"),
    pao2 = c("pO2", "Arterial O2 pressure"),
    paco2 = c("pCO2", "Arterial CO2 Pressure"),
    total_co2 = c("Calculated Total CO2", "TCO2 (calc) Arterial"),
    fio2 = c("Inspired O2 Fraction"),
    peep = c("PEEP set", "PEEP"),
    # --- 升压药 / 镇静 / 胰岛素 ---
    norepinephrine = c("Norepinephrine"),
    phenylephrine = c("Phenylephrine", "Phenylephrine (50/250)", "Phenylephrine (200/250)"),
    vasopressin = c("Vasopressin"),
    epinephrine = c("Epinephrine"),
    dopamine = c("Dopamine"),
    dobutamine = c("Dobutamine"),
    propofol = c("Propofol"),
    fentanyl = c("Fentanyl", "Fentanyl (Concentrate)"),
    insulin = c("Insulin - Regular", "Insulin - Humalog", "Insulin pump"),
    # --- 肝酶（可被 coverage 砍）---
    total_bilirubin = c("Total Bilirubin", "Bilirubin, Total"),
    ast = c("AST", "Asparate Aminotransferase (AST)"),
    alt = c("ALT", "Alanine Aminotransferase (ALT)"),
    alkphos = c("Alkaline Phosphate", "Alkaline Phosphatase")
  )
}
