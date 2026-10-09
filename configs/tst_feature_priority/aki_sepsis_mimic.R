# sepsis-AKI / MIMIC — 本病动态特征白名单（院内死亡时序池）
# 【非通用模板】下一病禁止直接挂本文件；须先检索该病文献再新建
#   configs/tst_feature_priority/<disease>_<db>.R
#
# 病种：脓毒症相关急性肾损伤（SA-AKI / sepsis-associated AKI）ICU 院内死亡
# 数据库：MIMIC-IV 小时长表 item 名（378_mimic_sepsisAKI_hourly_full_5d.csv）
#
# 文献依据（动态特征，非照抄纯 AKI / 卒中名单）：
# 1) Front Med 2022 (doi:10.3389/fmed.2022.853102) SA-AKI 实时死亡：尿量、GCS、乳酸、
#    生命体征、Cr/BUN、血常规、血气、电解质为动态核心；SHAP 强调尿量↓、GCS↓、乳酸↑、BUN↑
# 2) Front Cell Infect Microbiol 2024 (doi:10.3389/fcimb.2024.1488505) SAKI+RRT：
#    乳酸、Hb/Plt/WBC、Cr、电解质、INR、肝酶/胆红素、CVP、升压药
# 3) Front Med 2024 (doi:10.3389/fmed.2024.1483710) S-AKI：最大乳酸、SpO2、肌酐分层重要
# 4) Shock 2021 SAKI 模型：乳酸、BUN/SCr、肌酐、AKI 分期相关信息 → 本池用 Cr/BUN/尿量代理
#
# 原则：
# - 只收时序数值槽；Age/Gender/Weight/Ventilation/CRRT 走 config$static_features
# - 不含诊断泄漏（Acute_Renal_Failure/CKD 等诊断旗标）
# - 不含 APSIII/SOFA 分数本身（与 Fig2 对照评分脱钩）
# - 排除报警/护理文书噪声（Heart Rate Alarm 等未列入）
# - 尿量：小时表以 Foley（mL）高覆盖为主，Urine Volume 作别名

tst_feature_priority_aki_sepsis_mimic <- function() {
  list(
    # --- 生命体征（SA-AKI 动态核心）---
    heart_rate = c("Heart Rate"),
    respiratory_rate = c("Respiratory Rate"),
    spo2 = c("O2 saturation pulseoxymetry"),
    temperature_c = c("Temperature Celsius", "Temperature Fahrenheit"),
    nibp_systolic = c("Non Invasive Blood Pressure systolic"),
    nibp_diastolic = c("Non Invasive Blood Pressure diastolic"),
    nibp_mean = c("Non Invasive Blood Pressure mean"),
    abp_systolic = c("Arterial Blood Pressure systolic"),
    abp_diastolic = c("Arterial Blood Pressure diastolic"),
    abp_mean = c("Arterial Blood Pressure mean"),
    cvp = c("Central Venous Pressure"),
    # --- 神经 ---
    gcs_eye = c("GCS - Eye Opening"),
    gcs_motor = c("GCS - Motor Response"),
    gcs_verbal = c("GCS - Verbal Response"),
    # --- 肾 / 尿量（KDIGO + SA-AKI 文献最强动态轴）---
    creatinine = c("Creatinine (serum)", "Creatinine"),
    bun = c("BUN", "Urea Nitrogen"),
    urine_output = c("Foley", "Urine Volume", "GU Irrigant/Urine Volume Out"),
    ultrafiltrate = c("Ultrafiltrate Output"),
    # --- 灌注 / 代谢（乳酸为 SA-AKI 死亡最强之一）---
    lactate = c("Lactate", "Lactic Acid"),
    glucose = c("Glucose (serum)", "Glucose", "Fingerstick Glucose"),
    # --- 电解质 / 酸碱 ---
    sodium = c("Sodium (serum)", "Sodium"),
    potassium = c("Potassium (serum)", "Potassium"),
    chloride = c("Chloride (serum)", "Chloride"),
    bicarbonate = c("HCO3 (serum)", "Bicarbonate"),
    anion_gap = c("Anion gap", "Anion Gap"),
    calcium = c("Calcium non-ionized", "Calcium, Total"),
    magnesium = c("Magnesium"),
    phosphate = c("Phosphorous", "Phosphate"),
    # --- 血常规 ---
    wbc = c("WBC", "White Blood Cells"),
    hgb = c("Hemoglobin"),
    hct = c("Hematocrit (serum)", "Hematocrit"),
    platelets = c("Platelet Count"),
    # --- 凝血 ---
    inr = c("INR", "INR(PT)"),
    pt = c("PT", "Prothrombin time"),
    ptt = c("PTT"),
    # --- 血气 / 通气 ---
    ph = c("pH", "PH (Arterial)"),
    base_excess = c("Base Excess", "Arterial Base Excess"),
    pao2 = c("pO2", "Arterial O2 pressure"),
    paco2 = c("pCO2", "Arterial CO2 Pressure"),
    fio2 = c("Inspired O2 Fraction"),
    peep = c("PEEP set", "PEEP"),
    # --- 肝（感染/低灌注相关）---
    albumin = c("Albumin"),
    total_bilirubin = c("Total Bilirubin", "Bilirubin, Total"),
    ast = c("AST", "Asparate Aminotransferase (AST)"),
    alt = c("ALT", "Alanine Aminotransferase (ALT)"),
    alkphos = c("Alkaline Phosphate", "Alkaline Phosphatase"),
    # --- 升压药 / 镇静（SAKI+RRT / 休克负荷）---
    norepinephrine = c("Norepinephrine"),
    phenylephrine = c("Phenylephrine", "Phenylephrine (50/250)", "Phenylephrine (200/250)"),
    vasopressin = c("Vasopressin"),
    epinephrine = c("Epinephrine"),
    dopamine = c("Dopamine"),
    dobutamine = c("Dobutamine"),
    propofol = c("Propofol"),
    fentanyl = c("Fentanyl", "Fentanyl (Concentrate)"),
    insulin = c("Insulin - Regular", "Insulin - Humalog")
  )
}
