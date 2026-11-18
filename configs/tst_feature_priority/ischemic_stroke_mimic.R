# 缺血性脑卒中 / MIMIC-IV — 动态特征白名单（约 50 维）
# 依据：ICU 缺血性卒中院内/短期死亡文献高频因子（GCS/WBC/Age/Glucose/SpO2/BUN/
#   bicarbonate/RDW/Cr/机械通气/血压等）+ 本队列可算列；详见
#   reports/tst_feature_lit_ischemic_stroke_mimic_eicu.md（2026-11-18）。
# 样本：DN_first n≈3228 → 动态维数目标 50±10。
# 硬排除（不入本 list）：NIHSS/ASPECTS/梗死体积等疾病评分；SAPSII/APSIII/SOFA/OASIS/
#   APACHE 等综合严重度（对照评分由 config$tst_stroke$comparator_score 单独挂，默认 SAPSII）；
#   诊断码；st1–3；库内近空 troponin；重复 SpO2/HCO3/床旁糖。
# 静态 Age/Gender/Ht/Wt/GCS/vent/intubated/dialysis 由 config 静态广播，不在此 list。
# 别名 = 检测表 / 序列矩阵_72特征 列名（可直接子集）。

tst_feature_priority_ischemic_stroke_mimic <- function() {
  list(
    # --- 生命体征 / 血压 / 氧合 ---
    heartrate = c("heartrate"),
    respiration = c("respiration"),
    temperature = c("temperature"),
    systemicmean = c("systemicmean"),
    systemicsystolic = c("systemicsystolic"),
    systemicdiastolic = c("systemicdiastolic"),
    noninvasivemean = c("noninvasivemean"),
    noninvasivesystolic = c("noninvasivesystolic"),
    noninvasivediastolic = c("noninvasivediastolic"),
    sao2 = c("sao2"),
    total_rr = c("Total RR"),
    # --- 代谢 / 肾 / 电解质 ---
    glucose = c("glucose"),
    creatinine = c("creatinine"),
    bun = c("BUN"),
    bicarbonate = c("bicarbonate"),
    anion_gap = c("anion gap"),
    calcium = c("calcium"),
    sodium = c("sodium"),
    potassium = c("potassium"),
    chloride = c("chloride"),
    magnesium = c("magnesium"),
    phosphate = c("phosphate"),
    lactate = c("lactate"),
    albumin = c("albumin"),
    # --- 血细胞 ---
    wbc = c("WBC x 1000"),
    lymphs = c("-lymphs"),
    polys = c("-polys"),
    hgb = c("Hgb"),
    hct = c("Hct"),
    rdw = c("RDW"),
    platelets = c("platelets x 1000"),
    mcv = c("MCV"),
    # --- 凝血 / 血气 ---
    pt = c("PT"),
    ptt = c("PTT"),
    inr = c("PT - INR"),
    ph = c("pH"),
    paco2 = c("paCO2"),
    pao2 = c("paO2"),
    base_excess = c("Base Excess"),
    # --- 通气 ---
    fio2 = c("FiO2"),
    peep = c("PEEP"),
    lpm_o2 = c("LPM O2"),
    peak_insp_pressure = c("Peak Insp. Pressure"),
    plateau_pressure = c("Plateau Pressure"),
    mean_airway_pressure = c("Mean Airway Pressure"),
    tidal_volume_set = c("Tidal Volume (set)"),
    vent_rate = c("Vent Rate"),
    exhaled_mv = c("Exhaled MV"),
    # --- 肝酶 ---
    alt = c("ALT (SGPT)"),
    ast = c("AST (SGOT)")
  )
}
