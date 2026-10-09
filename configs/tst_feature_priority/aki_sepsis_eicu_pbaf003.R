# sepsis-AKI / eICU — 本课题对标 Yang et al. PCM 2025 pbaf003 后采用的动态特征
# 【非通用模板】下一病种禁止直接复用本文件；须先检索该病文献再新建
#   configs/tst_feature_priority/<disease>_<db>.R
# 依据：pbaf003 Supplementary Table 1（docs/literature_assets/pbaf003_supplemental_file.docx）
# 原文 226 = 时序生理/实验室/通气 + 同数 _mask + 人口学/unit/医师专科 one-hot 等。
# 本文件只收「时序数值」槽位；人口学走 config$static_features。
# Methods：固定清单；>30% 缺失剔人；whitelist_apply_coverage_drop=FALSE。
# 别名：同一 Supp 槽位在 378 小时表中的写法；不把原文多列近义项强行合并。

tst_feature_priority_aki_sepsis_eicu_pbaf003 <- function() {
  list(
    # --- differential / CBC extras（原文字面）---
    basos = c("-basos"),
    eos = c("-eos"),
    lymphs = c("-lymphs"),
    monos = c("-monos"),
    polys = c("-polys"),
    alt = c("ALT (SGPT)"),
    ast = c("AST (SGOT)"),
    bun = c("BUN"),
    base_excess = c("Base Excess"),
    exhaled_mv = c("Exhaled MV"),
    fio2 = c("FiO2", "FIO2 (%)", "Set Fraction of Inspired Oxygen (FIO2)"),
    hco3 = c("HCO3"),
    hct = c("Hct"),
    hgb = c("Hgb"),
    lpm_o2 = c("LPM O2"),
    mch = c("MCH"),
    mchc = c("MCHC"),
    mcv = c("MCV"),
    mpv = c("MPV"),
    mean_airway_pressure = c("Mean Airway Pressure"),
    o2_sat_pct = c("O2 Sat (%)"),
    peep = c("PEEP", "PEEP/CPAP"),
    pt = c("PT"),
    inr = c("PT - INR"),
    ptt = c("PTT"),
    peak_insp_pressure = c("Peak Insp. Pressure", "Peak Airway/Pressure"),
    plateau_pressure = c("Plateau Pressure"),
    rbc = c("RBC"),
    rdw = c("RDW"),
    rr_patient = c("RR (patient)"),
    sao2_chart = c("SaO2"),
    tv_kg_ibw = c("TV/kg IBW"),
    tidal_volume_set = c("Tidal Volume (set)"),
    total_rr = c("Total RR"),
    vent_rate = c("Vent Rate"),
    wbc = c("WBC x 1000"),
    albumin = c("albumin"),
    alkaline_phos = c("alkaline phos."),
    anion_gap = c("anion gap"),
    bedside_glucose = c("bedside glucose", "Bedside Glucose"),
    bicarbonate = c("bicarbonate"),
    calcium = c("calcium"),
    chloride = c("chloride"),
    creatinine = c("creatinine"),
    cvp = c("cvp", "CVP"),
    glucose = c("glucose"),
    # vitalPeriodic 风格名 → 本库 nurseCharting 别名（同一 Supp 槽）
    heart_rate = c("heartrate", "Heart Rate"),
    lactate = c("lactate"),
    magnesium = c("magnesium", "Magnesium"),
    nibp_diastolic = c(
      "noninvasivediastolic", "NIBP diastolic", "Non-Invasive BP Diastolic"
    ),
    nibp_mean = c("noninvasivemean", "NIBP mean", "Non-Invasive BP Mean"),
    nibp_systolic = c(
      "noninvasivesystolic", "NIBP systolic", "Non-Invasive BP Systolic"
    ),
    ph = c("pH"),
    paco2 = c("paCO2"),
    pao2 = c("paO2"),
    phosphate = c("phosphate"),
    platelets = c("platelets x 1000"),
    potassium = c("potassium"),
    respiration = c("respiration", "Respiratory Rate"),
    sao2_periodic = c("sao2"),
    sodium = c("sodium"),
    # ST / 有创压：优先原文字面，其次本库常见写法
    st1 = c("st1", "ST1"),
    st2 = c("st2", "ST2"),
    st3 = c("st3", "ST3"),
    abp_diastolic = c(
      "systemicdiastolic", "Arterial BP Diastolic", "Arterial BP diastolic",
      "Invasive BP Diastolic"
    ),
    abp_mean = c(
      "systemicmean", "Arterial BP mean", "Arterial BP Mean", "Invasive BP Mean"
    ),
    abp_systolic = c(
      "systemicsystolic", "Arterial BP Systolic", "Arterial BP systolic",
      "Invasive BP Systolic"
    ),
    temperature = c("temperature", "Temperature (C)", "Temperature"),
    total_bilirubin = c("total bilirubin"),
    total_protein = c("total protein"),
    troponin_i = c("troponin - I", "Troponin - I"),
    urinary_sg = c("urinary specific gravity"),
    # GCS 分量（原文 eyes/motor/verbal）
    gcs_eye = c("eyes", "Eyes", "GCS Eye Opening"),
    gcs_motor = c("motor", "Motor", "GCS Motor Response"),
    gcs_verbal = c("verbal", "Verbal", "GCS Verbal Response")
  )
}
