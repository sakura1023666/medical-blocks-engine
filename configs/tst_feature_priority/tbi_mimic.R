# TBI / MIMIC — TST 特征白名单
# 依据：
#   - 创伤性脑损伤 ICU 院内死亡常用动态特征：GCS 三分量（严重度核心）、
#     生命体征、血压、常规实验室、凝血（出血风险）、血气/通气、升压药、镇静(RASS)、
#     尿量；TBI 特异候选 ICP/CPP/高渗盐水/甘露醇（覆盖不足时由 day1>30% 砍掉）
#   - ICU 通用核心底稿思想同 PMID 40041421 两阶段 Transformer 动态特征池，
#     已按本病改名/改函数/写 TBI 依据（禁止继续挂 aki_mimic / stroke）
# 禁止：Alarms / Braden / Dressing / 护理文书 / ICP Line Dressing 等噪声；
#       不含 APSIII/SOFA（对照评分由 comparator_score 单独用）；不含诊断泄漏列
# Spec: docs/superpowers/specs/2026-08-31-tst-disease-feature-whitelist-gate-design.md

tst_feature_priority_tbi_mimic <- function() {
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
    # --- 神经（TBI 核心）---
    gcs_eye = c("GCS - Eye Opening"),
    gcs_motor = c("GCS - Motor Response"),
    gcs_verbal = c("GCS - Verbal Response"),
    rass = c("Richmond-RAS Scale"),
    # TBI 特异（低覆盖，预期被 coverage 砍；保留在名单供日后扩队列）
    cpp = c("Cerebral Perfusion Pressure"),
    icp_ventricular = c("Cerebral Ventricular #1", "Cerebral Ventricular #2"),
    icp_subdural = c("Cerebral Subdural #1", "Cerebral Subdural #2"),
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
    # --- 凝血（TBI 出血风险）---
    inr = c("INR", "INR(PT)"),
    pt = c("PT", "Prothrombin time"),
    ptt = c("PTT"),
    # --- 血气 / 通气 ---
    ph = c("pH", "PH (Arterial)"),
    lactate = c("Lactate", "Lactic Acid"),
    base_excess = c("Base Excess", "Arterial Base Excess"),
    pao2 = c("pO2", "Arterial O2 pressure"),
    paco2 = c("pCO2", "Arterial CO2 Pressure"),
    total_co2 = c("Calculated Total CO2", "TCO2 (calc) Arterial"),
    fio2 = c("Inspired O2 Fraction"),
    peep = c("PEEP set", "PEEP"),
    # --- 升压药 / 镇静 / 胰岛素 / 降颅压（低覆盖可砍）---
    norepinephrine = c("Norepinephrine"),
    phenylephrine = c("Phenylephrine", "Phenylephrine (50/250)", "Phenylephrine (200/250)"),
    vasopressin = c("Vasopressin"),
    epinephrine = c("Epinephrine"),
    dopamine = c("Dopamine"),
    dobutamine = c("Dobutamine"),
    propofol = c("Propofol"),
    fentanyl = c("Fentanyl", "Fentanyl (Concentrate)"),
    insulin = c("Insulin - Regular", "Insulin - Humalog", "Insulin pump"),
    hypertonic_saline = c("NaCl 3% (Hypertonic Saline)"),
    mannitol = c("Mannitol"),
    # --- 肝酶（可被 coverage 砍）---
    total_bilirubin = c("Total Bilirubin", "Bilirubin, Total"),
    ast = c("AST", "Asparate Aminotransferase (AST)"),
    alt = c("ALT", "Alanine Aminotransferase (ALT)"),
    alkphos = c("Alkaline Phosphate", "Alkaline Phosphatase")
  )
}
