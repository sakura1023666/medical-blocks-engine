###############################################################################
#  column_mapping — 将各数据库原始列名统一映射为流水线标准列名（ID、结局、生存等）。
#
#  register_block: "column_mapping"
#  典型流水线: data_clean 之前或之后（常紧接 data_clean 前，enable=TRUE 时）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$raw（来自 data_clean 加载）或已有 cleaned / imputed
#
#  # ── 配置 config$column_mapping ───────────────────────────────────────────
#  column_mapping = list(
#    enable        = TRUE,     # FALSE：不重命名，ctx$data$mapped 与输入列名一致
#    database_type = NULL,     # 仅日志标注，如 "MIMIC"/"NHANES"；映射规则在块内写死+可扩展
#    skip_rename   = character(0)  # 保留原名（如结局 AKI、暴露 AF），Gate A 同源
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$mapped；可选 Output/column_mapping_log.csv（记录改名对照）
#  源: Blocks/block_column_mappings.R（父块保留；Blocks/01_column_mappings 为目录化副本）
###############################################################################

auto_map_column_names <- function(data, db_type, skip_rename = character(0)) {
  data_mapped <- data
  skip_rename <- unique(as.character(skip_rename %||% character(0)))
  skip_rename <- skip_rename[nzchar(skip_rename)]

  # 每项: list(c("别名1", "别名2", ...), "标准列名")
  column_mappings <- list(
    list(c("futime", "follow_up_time", "followup_time", "survival_time", "os_time"), "futime"),
    list(c("fustatus", "follow_up_status", "status", "outcome", "event", "dead", "death"), "fustatus"),
    list(c("subject_id", "SEQN", "Admission_num", "hadm_id", "stay_id", "ID", "id", "patient_id", "Pat_ID"), "ID"),

    list(c("age", "Age", "AGE", "RIDAGEYR", "anchor_age"), "Age"),
    list(c("gender", "Gender", "GENDER", "sex", "Sex", "SEX", "RIAGENDR"), "Gender"),
    list(c("race", "Race", "RACE", "ethnicity", "Ethnicity", "RIDRETH1", "RIDRETH3"), "Race"),
    list(c("language", "Language", "LANG"), "Language"),
    list(c("weight", "Weight", "WEIGHT", "weight_kg", "BMXWT"), "Weight"),
    list(c("height", "Height", "HEIGHT", "height_cm", "BMXHT"), "Height"),
    list(c("bmi", "BMI", "body_mass_index", "BMXBMI"), "BMI"),
    list(c("education", "Education", "edu", "EDU", "DMDEDUC2"), "Education"),
    list(c("marital", "Marital", "marriage", "marital_status", "DMDMARTL","Marital_Status"), "Marital_Status"),
    list(c("income", "Income", "pir", "poverty_ratio", "INDFMPIR"), "PIR"),
    list(c("smoking", "Smoking", "smoke", "Smoke", "SMQ020", "tobacco"), "Smoking"),
    list(c("alcohol", "Alcohol", "drink", "ALQ", "ethanol", "Alcohol_drinking",
           "Drinking", "drinking", "drinkl"), "Alcohol_drinking"),
    # 腰围（修正拼写 circumstance → circumference）
    list(c("waist_circumference", "Waist_circumference", "Waist_circumstance", "waist_circumstance",
           "BMXWAIST", "waist", "waist"), "Waist_circumference"),

    list(c("wbc", "WBC", "white_blood_cell", "wbc_count", "White_blood_cell_count", "LBXWBCSI"), "WBC"),
    list(c("rbc", "RBC", "red_blood_cell", "rbc_count", "Red_blood_cell_count", "LBXRBCSI"), "RBC"),
    list(c("hemoglobin", "Hemoglobin", "HGB", "hb", "LBXHGB"), "Hemoglobin"),
    list(c("hematocrit", "Hematocrit", "HCT", "hct", "LBXHCT"), "Hematocrit"),
    # Platelet → K/uL（10^9/L）；缩放规则见 R/hematology_units.R（禁止 med>50 误÷1000）
    # 须含带空格 "Platelet Count"，否则会与 PlateletCount 并存进 Table1 双行
    list(c("plateletcount", "PlateletCount", "Platelet Count", "Platelet", "PLT", "platelet",
           "platelet_count", "Platelet_Count", "LBXPLTSI"), "Platelet_Count"),
    list(c("rdw", "RDW", "rdw_cv", "RDW_CV", "LBXRDW"), "RDW"),
    list(c("mcv", "MCV", "LBXMCVSI"), "MCV"),
    # MCH/MCHC 统一映射到 MCH/MCHC，与 index block 公式名称一致
    list(c("mch", "MCH", "Mean_cell_hemoglobin", "mean_cell_hemoglobin", "LBXMCHSI"), "MCH"),
    list(c("mchc", "MCHC", "Mean_Cell_Hgb_Conc", "mean_cell_hgb_conc", "LBXMCHCSI"), "MCHC"),
    list(c("mpv", "MPV", "Mean_platelet_volume"), "Mean_platelet_volume"),

    list(c("neutrophilcount", "NeutrophilCount", "Neutrophil", "neutrophil", "neutrophil_count", "neutrophils",
           "Polymorphonuclear_leukocytes", "Neutrophil_count", "LBDNENO", "NEU", "ANC"), "Neutrophil_Count"),
    list(c("neu_pct", "neutrophil_pct", "neutrophil_percent", "Percentage_of_neutrophils"), "Percentage_of_neutrophils"),
    list(c("lymphocytes", "Lymphocytes", "Lymphocyte", "lymphocyte", "lymphocyte_count",
           "Lymphs", "LBDLYMNO", "LYM"), "Lymphocytes"),
    # Monocyte 映射为公式所用的标准名 Monocyte（原来错映射到 Mononuclear_cell_count）
    list(c("monocyte", "Monocyte", "monocytes", "monocyte_count", "Monocytes",
           "LBDMONO", "MONO", "Mononuclear_cell_count", "mononuclear_cell_count"), "Monocyte"),
    list(c("eosinophil", "Eosinophil", "eosinophils", "EOS", "LBDEOSI"), "Eosinophil_Count"),
    list(c("basophil", "Basophil", "basophils", "BASO", "LBDBPSI"), "Basophil_Count"),

    # 糖化血红蛋白
    list(c("a1c", "HbA1c", "A1c", "Glycohemoglobin", "Glycated_hemoglobin",
           "hba1c", "HbA1C", "glycated_hemoglobin", "LBXGH"), "HbA1c"),
    list(c("albumin", "Albumin", "ALB", "LBXSAL"), "Albumin"),
    list(c("total_protein", "TotalProtein", "TP", "LBXSTP"), "TotalProtein"),
    list(c("dbil", "DBil", "direct_bilirubin", "BilirubinDirect", "LBXDB"), "Bilirubin_Direct"),
    list(c("ibil", "IBil", "indirect_bilirubin", "BilirubinIndirect"), "Bilirubin_Indirect"),
    list(c("globulin", "Globulin", "GLO", "glob", "serum_globulin", "LBXSGB"), "Globulin"),
    list(c("alt", "ALT", "sgpt", "alanine_aminotransferase", "Alanine_aminotransferase_ALT", "LBXSATSI"), "ALT"),
    list(c("ast", "AST", "sgot", "aspartate_aminotransferase", "Aspartate_aminotransferase_AST", "LBXSASSI"), "AST"),
    list(c("bilirubin", "Bilirubin", "TBL", "tbil", "total_bilirubin", "Total_Bilirubin", "LBXSTB", "LBXTB",
           "bilirubintotal", "bilirubin_total", "totalbilirubin", "BilirubinTotal", "Total_bilirubin"), "Bilirubin_Total"),
    # LD (Lactate Dehydrogenase) — 注意 LBXSLDSI 是乳酸脱氢酶，不是乳酸
    list(c("ld", "LD", "LDH", "ldh", "lactate_dehydrogenase", "Lactate_Dehydrogenase_LDH", "LBXSLD"), "LD"),
    list(c("ck", "CK", "creatine_kinase", "LBXCK"), "CK"),
    list(c("ckmb", "CKMb", "ck_mb"), "CKMb"),
    list(c("creatinine", "Creatinine", "CR", "cr", "Cr", "Serum_Creatinine", "Scr", "SCR", "LBXSCR"), "Creatinine"),
    list(c("UrineCreatinine", "urine_creatinine", "UCr", "u_creatinine", "ur_creat", "LBXUCR",
           "Urine_Creatinine", "Urinary_Creatinine", "urinary_creatinine", "URXUCR"), "Urine_Creatinine"),
    # UreaNitrogen / Urea Nitrogen 与 BUN 同义；标准名已存在时丢弃别名，避免 Table1 双行
    list(c("bun", "BUN", "blood_urea_nitrogen", "Blood_Urea_Nitrogen", "LBXSBU", "urea",
           "UreaNitrogen", "Urea Nitrogen", "urea_nitrogen"), "BUN"),
    list(c("glucose", "Glucose", "GLU", "glu", "blood_glucose", "Fasting_Glucose", "LBXGLU", "BG", "glucose_bg",
           "Fasting Glucose mg dL", "Fasting_Glucose_mg_dL", "newglu"), "Glucose"),
    list(c("sodium", "Sodium", "NA", "na", "Na", "LBXSNASI"), "Sodium"),
    list(c("potassium", "Potassium", "K", "k", "LBXSKSI"), "Potassium"),
    list(c("chloride", "Chloride", "CL", "cl", "LBXSCLSI"), "Chloride"),
    list(c("calcium", "Calcium", "CA", "LBXSCA"), "Calcium"),
    list(c("magnesium", "Magnesium", "MG", "LBXSMG"), "Magnesium"),
    list(c("phosphate", "Phosphate", "PHOS", "LBXSPH"), "Phosphate"),
    list(c("aniongap", "AnionGap", "anion_gap", "AG", "anion", "Anion_Gap"), "AnionGap"),
    list(c("tc", "TC", "Cholesterol","Cholesterol_total","Cholesteroltotal","CholesterolTotal", "cholesterol", "total_cholesterol", "Total_cholesterol", "Totalcholesterol", "LBXTC"), "Total_Cholesterol"),
    list(c("tg", "TG", "Triglycerides", "triglycerides", "LBXSTR"), "Triglycerides"),
    list(c("ldl", "LDL", "LDL_C", "ldl_cholesterol", "LBDLDL"), "LDL"),
    list(c("hdl_c", "HDL_C", "HDL", "hdl", "LBDHDD"), "HDL"),
    list(c("calcium", "Calcium", "CA", "LBXSCA", "CalciumTotal"), "CalciumTotal"),
    list(c("egfr", "eGFR", "GFR", "estimated_gfr", "MDRD", "CKD_EPI"), "eGFR"),
    list(c("inr", "INR", "pt_inr"), "INR"),
    list(c("fibrinogen", "Fibrinogen", "FIB", "fib", "LBXFIB"), "Fibrinogen"),
    list(c("lactate", "Lactate", "Lac", "lactic_acid", "LBXSLDSI"), "Lactate"),
    list(c("pao2", "PaO2", "pa_o2", "po2", "arterial_o2"), "PaO2"),
    list(c("fio2", "FiO2", "fi_o2"), "FiO2"),
    list(c("ph", "PH", "blood_ph"), "PH"),
    list(c("pco2", "PCO2", "co2_partial_pressure"), "PCO2"),
    list(c("pao2", "PaO2", "pa_o2", "po2", "PO2", "arterial_o2"), "PO2"),
    list(c("totalco2", "TotalCo2", "tco2"), "TotalCo2"),
    list(c("free_ca", "FreeCalcium", "ionized_calcium"), "Free_Calcium"),
    list(c("uricacid", "UricAcid", "UA", "uric_acid", "LBXSUA"), "Uric_Acid"),
    list(c("tt", "TT", "thrombin_time"), "TT"),
    list(c("pt", "PT", "prothrombin_time"), "PT"),
    list(c("ptt", "PTT", "aptt", "aPTT"), "PTT"),
    list(c("ddimer", "Ddimer", "d_dimer", "dimer"), "Ddimer"),
    list(c("tnt", "Troponint", "troponin_t"), "Troponint"),
    list(c("ntprobnp", "NTproBNP", "nt_pro_bnp"), "NTproBNP"),
    list(c("bnp", "BNP", "brain_natriuretic_peptide"), "BNP"),
    list(c("urine_protein", "UrineProtein", "u_protein"), "Urine_Protein"),
    list(c("urine_osm", "UrineOsmolality", "u_osmolality"), "Urine_Osmolality"),
    list(c("urine_glucose", "UrineGlucose", "u_glu"), "Urine_Glucose"),
    list(c("urine_alb", "AlbuminUrine", "u_albumin", "albumin_urine", "URXUMA", "Urinary_Albumin", "urinary_albumin"), "Albumin_Urine"),
    list(c("acr", "AlbuminCreatinine", "alb_creat_ratio"), "Albumin_Creatinine"),
    list(c("urine_vol", "UrineVolume", "urine_output"), "Urine_Volume"),
    list(c("urine_sg", "Urine_specific_gravity", "u_sg"), "Urine_specific_gravity"),
    list(c("crp", "CRP", "C_Reactive_Protein", "c_reactive_protein", "LBXCRP",
           "C reactive protein mg dL", "C_reactive_protein_mg_dL",
           "C-reactive protein", "newcrp"), "CRP"),
    list(c("hscrp", "HSCRP", "High_sensitivity_CRP"), "HSCRP"),
    list(c("procalcitonin", "PCT", "pct", "Procalcitonin"), "Procalcitonin"),
    list(c("serum_iron", "Serumiron", "iron"), "Serumiron"),
    list(c("ferritin", "Ferritin", "fer"), "Ferritin"),
    list(c("tibc", "TotalIronBindingCapacity", "total_iron_binding"), "TotalIronBindingCapacity"),
    list(c("transferrin", "Transferrin", "tf"), "Transferrin"),
    list(c("tsh", "Thyroid_stimulating_hormone", "TSH"), "Thyroid_stimulating_hormone"),

    list(c("ft4", "Thyroxine_free", "Thyroxine_free_T4", "free_t4"), "Thyroxine_free_T4"),
    list(c("tt3", "Thyroxine_total_T3", "total_t3"), "Thyroxine_total_T3"),
    list(c("tt4", "Thyroxine_total_T4", "total_t4"), "Thyroxine_total_T4"),
    list(c("ft3", "Triiodothyronine_T3_free", "free_t3"), "Triiodothyronine_T3_free"),

    list(c("t1dm", "T1DM", "dm1", "type1_diabetes"), "T1DM"),
    list(c("t2dm", "T2DM", "dm2", "type2_diabetes", "diabetes_type_2", "type_2_diabetes"), "T2DM"),
    list(c("hypertension", "Hypertension", "HTN", "htn"), "Hypertension"),
    list(c("diabetes", "Diabetes", "DM", "dm"), "Diabetes"),
    list(c("heart_failure", "Heart_Failure", "HF", "chf", "CHF"), "Heart_Failure"),
    list(c("stroke", "Stroke", "CVA", "cva"), "Stroke"),
    list(c("copd", "COPD", "chronic_obstructive"), "COPD"),
    list(c("atrial_fibrillation", "AF", "AFib", "afib", "atrial_fib"), "Atrial_Fibrillation"),
    list(c("ckd", "CKD", "chronic_kidney", "renal_failure", "aki"), "CKD"),
    list(c("cancer", "Cancer", "malignancy", "tumor","Malignant_Tumor"), "Cancer"),
    list(c("dementia", "Dementia"), "Dementia"),
    list(c("pvd", "PVD", "peripheral_vascular"), "PVD"),
    list(c("mi", "Myocardial_Infarction", "myocardial_infarct"), "Myocardial_Infarction"),
    list(c("cancer", "Cancer", "malignancy", "tumor","Malignant_Tumor"), "Malignant_Tumor"),
    list(c("akf", "Acute_Renal_Failure", "aki", "acute_kidney_injury"), "Acute_Renal_Failure"),
    list(c("cirrhosis", "Liver_cirrhosis", "cirrhosis_liver"), "Liver_cirrhosis"),
    list(c("hepatitis", "Hepatitis", "hep"), "Hepatitis"),
    list(c("tb", "Tuberculosis", "tuberculosis"), "Tuberculosis"),
    list(c("pneumonia", "Pneumonia", "pneu"), "Pneumonia"),
    list(c("hyperlipidemia", "Hyperlipidemia", "dyslipidemia"), "Hyperlipidemia"),
    list(c("anti_hypertensive", "Antihypertensive_agents", "bp_med"), "Antihypertensive_agents"),
    list(c("lipid_lower", "Lipid_lowering_agents", "statin", "lipid_med"), "Lipid_lowering_agents"),
    list(c("anti_diabetic", "Antidiabetic_agents", "glucose_med"), "Antidiabetic_agents"),

    # CHARLS 人口学 / 社会经济（Baseline数据字典）
    list(c("residence", "Residence", "Hukou", "hukou", "hukou_type"), "Residence"),
    list(c(
      "familysize", "Familysize", "family_size", "Family_Size",
      "Household_size", "household_size", "Household size", "household size"
    ), "Familysize"),
    list(c("incometotal", "Incometotal", "income_total", "Income_total"), "Incometotal"),
    list(c("family_per_capita_consumption", "Family_per_capita_consumption",
           "Family_per_capita_Consumption"), "Family_per_capita_consumption"),

    # CHARLS 合并症（问卷自报，Yes/No）
    list(c("pulmonary_disease", "Pulmonary_Disease"), "Pulmonary_Disease"),
    list(c("liver_disease", "Liver_Disease"), "Liver_Disease"),
    list(c("cardiopathy", "Cardiopathy"), "Cardiopathy"),
    list(c("kidney_disease", "Kidney_Disease"), "Kidney_Disease"),
    list(c("stomach_disease", "Stomach_Disease"), "Stomach_Disease"),
    list(c("psychiatric", "Psychiatric"), "Psychiatric"),
    list(c("amnesia", "Amnesia"), "Amnesia"),
    list(c("rheumatic_diseases", "Rheumatic_Diseases"), "Rheumatic_Diseases"),
    list(c("asthma", "Asthma"), "Asthma"),

    # CHARLS 预计算衍生指标
    list(c("TyG", "tyg", "TYG"), "TyG"),
    list(c("TyGBMI", "TyG_BMI", "tygbmi", "TygBMI"), "TyG_BMI"),

    # CHARLS 认知评分（Memeory 保留 CHARLS 原始拼写）
    list(c("totalcognition", "Totalcognition", "Total_cognition"), "Totalcognition"),
    list(c("executive", "Executive", "Executive_function"), "Executive"),
    list(c("memeory", "Memeory", "memory", "Memory"), "Memeory"),

    # ELSA8 独有（Baseline数据字典）
    list(c("vitd", "VitD", "vit_d", "Vitamin_D", "vitamin_d"), "VitD"),
    list(c("igf1", "IGF1", "IGF_1"), "IGF1"),
    list(c("mhip", "Hip", "hip_circumference", "Hip_circumference"), "Hip"),
    list(c("mwhratio", "WaistHipRatio", "waist_hip_ratio", "WHR", "whr"), "WaistHipRatio"),
    list(c("msithght", "SittingHeight", "sitting_height", "Sit_height"), "SittingHeight"),

    # 胰岛素
    list(c("insulin", "Insulin", "insulin_use", "INS", "LBXIN"), "Insulin"),

    list(c("hr", "HR", "heart_rate", "heartrate", "BPXHR", "Pulse", "pulse", "Pulse_rate"), "HR"),
    list(c("pp", "PP", "pulse_pressure"), "PP"),
    list(c("rr", "RR", "resp_rate", "respiratory_rate"), "RR"),
    list(c("spo2", "SpO2", "o2sat", "oxygen_saturation"), "SpO2"),
    list(c("gcs", "GCS", "glasgow"), "GCS"),
    list(c("temp", "Temperature", "temperature", "body_temp"), "Temperature"),
    # 血压：优先无创袖带 (NBPS/NBPM)，与 MIMIC 列名 Nbps/Nbpm 对齐；动脉压 (ABPS/ABPM) 作备选
    list(c("NBPS", "Nbps", "nbps", "ABPS", "Abps", "abps", "sbp", "SBP", "systolic_bp",
           "Systolic pressure", "Systolic_pressure", "systo"), "SBP"),
    list(c("NBPM", "Nbpm", "nbpm", "ABPM", "Abpm", "abpm", "map", "MAP", "mean_arterial_pressure"), "MAP"),
    list(c("NBPD", "Nbpd", "nbpd", "ABPD", "Abpd", "abpd", "dbp", "DBP",
           "Diastolic pressure", "Diastolic_pressure", "diasto"), "DBP"),
    # 无创收缩压
    list(c("NBPS", "Nbps", "nbps", "sbp", "SBP", "systolic_bp"), "NBPS"),
    # 有创动脉收缩压
    list(c("ABPS", "Abps", "abps"), "ABPS"),

    # 无创平均动脉压
    list(c("NBPM", "Nbpm", "nbpm", "map", "MAP", "mean_arterial_pressure"), "NBPM"),
    # 有创动脉平均压
    list(c("ABPM", "Abpm", "abpm"), "ABPM"),

    # 无创舒张压
    list(c("NBPD", "Nbpd", "nbpd", "dbp", "DBP"), "NBPD"),
    # 有创动脉舒张压
    list(c("ABPD", "Abpd", "abpd"), "ABPD"),
    list(c("OAScore", "OA_SCORE", "oa_score", "oa_score_z", "OAScore_z"), "OAScore_z"),
    list(c("sofa", "SOFA", "sofa_score"), "SOFA"),
    list(c("apache", "APACHE", "aps", "APS", "apache_ii"), "APACHE"),
    list(c("charlson", "Charlson", "cci", "charlson_index"), "Charlson"),
    list(c("apsiii", "APSIII", "aps3"), "APSIII"),

    list(c("sapsii", "SAPSII", "saps2"), "SAPSII"),
    list(c("oasis", "OASIS", "oasis_score"), "OASIS"),

    list(c("vent_hour", "Ventilation_Hour", "vent_hours", "VentilationHour"), "Ventilation_Hour"),
    list(c("Ventilation", "ventilation", "mechvent", "mechanical_ventilation"), "Ventilation"),

    list(c("crrt_day", "CRRT_Day"), "CRRT_Day"),
    list(c("crrt", "CRRT", "continuous_rrt"), "CRRT"),

    list(c("icu_los", "icu_los_days", "los_icu", "ICU_LOS"), "ICU_LOS"),
    list(c("hospital_los", "los_hospital", "Hosp_LOS", "length_of_stay"), "Hospital_LOS"),

    list(c("is_hosp_dead", "hospdischargestatus", "HospDischargeStatus", "hosp_discharge_status"),
         "in-hospital mortality")
  )

  cli::cli_alert_info("Auto-mapping columns for {db_type} database")

  mapping_log <- data.frame(
    original_name = character(),
    standard_name = character(),
    stringsAsFactors = FALSE
  )

  for (mapping in column_mappings) {
    possible_names <- mapping[[1]]
    standard_name <- mapping[[2]]

    matched_name <- NULL
    for (pname in possible_names) {
      if (pname %in% colnames(data)) {
        matched_name <- pname
        break
      }
      matched_idx <- grep(paste0("^", pname, "$"), colnames(data), ignore.case = TRUE)
      if (length(matched_idx) > 0) {
        matched_name <- colnames(data)[matched_idx[1]]
        break
      }
    }

    if (!is.null(matched_name)) {
      if (length(skip_rename) && (
        matched_name %in% skip_rename ||
        standard_name %in% skip_rename ||
        tolower(matched_name) %in% tolower(skip_rename) ||
        tolower(standard_name) %in% tolower(skip_rename)
      )) {
        cli::cli_alert_info(
          "Skip rename (config$column_mapping$skip_rename): '{matched_name}' stays"
        )
        next
      }
      # 需求：列名不一致时改名，而不是复制新增一列
      if (matched_name == standard_name) {
        next
      }
      if (standard_name %in% colnames(data_mapped)) {
        # 目标标准名已存在时丢弃别名列，避免 Table1 出现 Platelet Count / PlateletCount 双行
        if (!identical(matched_name, standard_name) && matched_name %in% names(data_mapped)) {
          data_mapped[[matched_name]] <- NULL
          cli::cli_alert_warning(
            "Dropped alias '{matched_name}' (standard '{standard_name}' already exists)"
          )
        } else {
          cli::cli_alert_warning(
            "Skip rename: '{matched_name}' -> '{standard_name}' (target name already exists)"
          )
        }
        next
      }
      names(data_mapped)[names(data_mapped) == matched_name] <- standard_name
      cli::cli_alert_success("Renamed: '{matched_name}' -> '{standard_name}'")
      mapping_log <- rbind(mapping_log, data.frame(
        original_name = matched_name,
        standard_name = standard_name,
        stringsAsFactors = FALSE
      ))
    }
  }

  # 部分库（如 eICU）血压列为字符，需转为数值才能进入连续变量/聚类池
  coerce_numeric_cols <- c(
    "SBP", "MAP", "DBP", "HR", "RR", "SpO2", "Temperature", "Weight", "Height", "BMI"
  )
  for (cn in intersect(coerce_numeric_cols, names(data_mapped))) {
    x <- data_mapped[[cn]]
    if (is.character(x) || is.factor(x)) {
      data_mapped[[cn]] <- suppressWarnings(as.numeric(as.character(x)))
    }
  }

  # 有身高/体重但无 BMI 时衍生（单库如 Liling/Single；双库 Gate A 亦同源逻辑）
  if (exists("dual_db_derive_bmi", mode = "function")) {
    data_mapped <- dual_db_derive_bmi(data_mapped, list(enable = TRUE))
  } else if (!("BMI" %in% names(data_mapped)) &&
             all(c("Height", "Weight") %in% names(data_mapped))) {
    hx <- suppressWarnings(as.numeric(as.character(data_mapped$Height)))
    wx <- suppressWarnings(as.numeric(as.character(data_mapped$Weight)))
    bmi <- wx / (hx / 100)^2
    bmi[!is.finite(bmi) | bmi <= 0 | bmi > 100] <- NA_real_
    data_mapped$BMI <- round(bmi, 2)
    cli::cli_alert_success(
      "已衍生 BMI = Weight/(Height/100)^2（有效 {sum(is.finite(data_mapped$BMI))}/{nrow(data_mapped)}）"
    )
  }

  attr(data_mapped, "mapping_log") <- mapping_log
  data_mapped
}

block_column_mapping <- function(ctx) {
  cli::cli_h1("Column Name Mapping Block")

  cfg <- ctx$config
  cm <- cfg$column_mapping %||% list()

  data_src <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data_src)) {
    cli::cli_alert_danger("No data available")
    return(ctx)
  }

  if (identical(cm$enable, FALSE)) {
    cli::cli_alert_info("config$column_mapping$enable 为 FALSE，跳过重命名，mapped 与当前输入一致。")
    ctx$data$mapped <- data_src
    return(ctx)
  }

  db_type <- cm$database_type
  if (is.null(db_type)) {
    db_type <- "Unknown"
  }

  cli::cli_alert_info("Database type: {db_type}")
  cli::cli_alert_info("Original columns: {ncol(data_src)}")

  data_mapped <- auto_map_column_names(
    data_src, db_type,
    skip_rename = as.character(cm$skip_rename %||% character(0))
  )
  if (exists("pipeline_split_ventilation_mapping", mode = "function")) {
    data_mapped <- pipeline_split_ventilation_mapping(data_mapped)
  }
  mapping_log <- attr(data_mapped, "mapping_log")

  ctx$data$mapped <- data_mapped

  if (nrow(mapping_log) > 0) {
    ctx <- save_result(ctx, "column_mapping_log", mapping_log, "column_mapping_log.csv")
  }

  cli::cli_alert_success("Column mapping completed: {nrow(mapping_log)} columns mapped")
  cli::cli_alert_info("Final columns: {ncol(data_mapped)}")

  ctx
}

register_block("column_mapping", block_column_mapping,
               "Map column names to standard names across databases")
