#!/usr/bin/env Rscript
# 导出引擎复合指标定义 + 课题暴露说明 → markdown
args <- commandArgs(trailingOnly = TRUE)
out_path <- if (length(args)) args[[1L]] else
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/08_术中低体温症/指标定义与计算方法.md"

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
env <- new.env(parent = globalenv())
tryCatch(
  source(file.path(root, "Blocks/00_index/01block_index.R"), local = env),
  error = function(e) invisible(NULL)
)
if (!exists(".idx_definitions", envir = env, mode = "function")) {
  stop("无法加载 .idx_definitions()", call. = FALSE)
}
defs <- env$.idx_definitions()
`%||%` <- function(a, b) if (!is.null(a)) a else b

zh_name <- c(
  BMI = "体重指数", NLR = "中性粒细胞/淋巴细胞比值", PLR = "血小板/淋巴细胞比值",
  SII = "全身免疫炎症指数", NLPR = "中性粒细胞×100/(淋巴细胞×血小板)", ANLR = "白蛋白/NLR",
  LHR = "淋巴细胞/HDL 比值", PHR = "血小板/HDL 比值", HALP = "血红蛋白×白蛋白×淋巴细胞/血小板",
  GLR = "葡萄糖/淋巴细胞比值", WPR = "白细胞/血小板比值",
  AIP = "致动脉粥样硬化指数", TyG = "甘油三酯-葡萄糖指数", NHHR = "非HDL/HDL 比值",
  RC = "残余胆固醇", TG_HDL_C = "TG/HDL-C", TC_HDL = "TC/HDL-C", NHDL = "非 HDL 胆固醇",
  AC = "动脉粥样硬化系数", CRI_I = "Castelli 风险指数 I", CRI_II = "Castelli 风险指数 II",
  Periodontitis = "牙周炎分级（原生）", OAScore_z = "OAScore z 分", LCI = "脂质综合指数",
  CHG = "胆固醇-HDL-葡萄糖指数", AIP_BMI = "AIP×BMI", TyG_BMI = "TyG×BMI",
  TCBI = "甘油三酯-胆固醇-体重指数", HbA1c_HDL_C = "HbA1c/HDL-C", ALT_HDL_C = "ALT/HDL-C",
  SHR = "应激性高血糖比", HGI = "血红蛋白糖化指数", GPR = "葡萄糖/钾比值",
  De_Ritis = "De Ritis 比值 (AST/ALT)", FIB4 = "FIB-4 纤维化指数", APRI = "AST/血小板比值指数",
  ALBI = "白蛋白-胆红素评分", AGR = "白蛋白/球蛋白比值", BAR = "BUN/白蛋白比值",
  AFR = "纤维蛋白原/白蛋白比值", LAR = "LD/白蛋白比值", log2LAR = "log2(LAR)",
  ALI = "晚期肺癌炎症指数", CAR = "肌酐/白蛋白比值", UA_CR = "尿酸/肌酐比值",
  BUN_Cr = "BUN/肌酐比值", UACR = "尿白蛋白/肌酐比值", Hemoglobin = "血红蛋白（原生）",
  RAR = "RDW/白蛋白比值", MCH = "平均红细胞血红蛋白量", MCV = "平均红细胞体积",
  MCHC = "平均红细胞血红蛋白浓度", RDW_CV = "RDW 变异系数相关", HHR = "红细胞压积/血红蛋白",
  HRR = "血红蛋白/RDW", UHR = "尿酸/HDL 比值", PNI = "预后营养指数", METSIR = "METS-IR",
  EASIX = "内皮激活与应激指数", SOSM = "血清渗透压", ACAG = "白蛋白校正阴离子间隙",
  ABSI = "身体形态指数", BRI = "身体圆润度指数", WWI = "体重调整腰围指数",
  WHtR = "腰高比", CMI = "心脏代谢指数", AISI = "聚集炎症指数", SIRI = "全身炎症反应指数",
  LMR = "淋巴细胞/单核细胞比值", MLR = "单核细胞/淋巴细胞比值", PIV = "泛免疫炎症值",
  SIIR = "全身免疫炎症反应指数", SIS = "系统炎症评分", MHR = "单核细胞/HDL 比值",
  NMLR = "(单核+中性)/淋巴比值", CALLY = "CALLY 指数", CLR = "CRP-淋巴细胞相关",
  CTI = "心脏代谢炎症指数", hs_CRP_HDL_C = "hs-CRP/HDL-C", AIP_WC = "AIP×腰围",
  AIP_WHtR = "AIP×腰高比", WTI = "腰围-甘油三酯指数", TyG_WHtR = "TyG×腰高比",
  TyG_WC = "TyG×腰围", TyG_WWI = "TyG×WWI", TyG_ABSI = "TyG×ABSI",
  RCII = "残余胆固醇炎症指数", lnRCII = "ln(RCII)", HOMA_IR = "稳态模型胰岛素抵抗",
  MCMI = "代谢综合征相关", eGDR = "估算葡萄糖处置率", HSI = "肝脂肪变性指数",
  NFS = "NAFLD 纤维化评分", alb_score = "CONUT 白蛋白分", lymp_score = "CONUT 淋巴分",
  chol_score = "CONUT 胆固醇分", CONUT_score = "控制营养状态评分", MBP = "平均血压",
  ePWV = "估算脉搏波速度", lbLDL_C = "大而轻 LDL-C", sdLDL_C = "小而密 LDL-C",
  ALT_AST_ratio_flag = "ALT/AST 比值标志", FSI = "脂肪肝筛选指数", METS_VF = "METS 内脏脂肪",
  GNRI = "老年营养风险指数", ZJU = "浙大指数", VAI = "内脏脂肪指数", RFM = "相对脂肪质量",
  LAP = "脂质蓄积产物"
)

category_of <- function(nm) {
  if (nm %in% c("BMI", "ABSI", "BRI", "WWI", "WHtR", "CMI", "RFM", "LAP", "VAI",
                "METS_VF", "GNRI", "ZJU")) {
    return("人体测量 / 体脂体型")
  }
  if (nm %in% c("NLR", "PLR", "SII", "NLPR", "ANLR", "LHR", "PHR", "HALP", "GLR", "WPR",
                "AISI", "SIRI", "LMR", "MLR", "PIV", "SIIR", "SIS", "MHR", "NMLR",
                "CALLY", "CLR", "CTI", "hs_CRP_HDL_C", "ALI")) {
    return("炎症 / 免疫")
  }
  if (nm %in% c("AIP", "TyG", "NHHR", "RC", "TG_HDL_C", "TC_HDL", "NHDL", "AC", "CRI_I",
                "CRI_II", "LCI", "CHG", "AIP_BMI", "TyG_BMI", "TCBI", "HbA1c_HDL_C",
                "ALT_HDL_C", "AIP_WC", "AIP_WHtR", "WTI", "TyG_WHtR", "TyG_WC",
                "TyG_WWI", "TyG_ABSI", "RCII", "lnRCII", "lbLDL_C", "sdLDL_C", "UHR")) {
    return("血脂 / 脂代谢")
  }
  if (nm %in% c("SHR", "HGI", "GPR", "HOMA_IR", "MCMI", "eGDR", "HSI", "NFS", "FSI",
                "ALT_AST_ratio_flag")) {
    return("糖代谢 / 脂肪肝相关")
  }
  if (nm %in% c("De_Ritis", "FIB4", "APRI", "ALBI", "AGR", "BAR", "AFR", "LAR", "log2LAR")) {
    return("肝功能 / 营养炎症")
  }
  if (nm %in% c("CAR", "UA_CR", "BUN_Cr", "UACR", "EASIX")) return("肾功能相关")
  if (nm %in% c("Hemoglobin", "RAR", "MCH", "MCV", "MCHC", "RDW_CV", "HHR", "HRR")) {
    return("血液学")
  }
  if (nm %in% c("PNI", "CONUT_score", "alb_score", "lymp_score", "chol_score", "METSIR",
                "SOSM", "ACAG", "MBP", "ePWV", "OAScore_z", "Periodontitis")) {
    return("营养 / 综合评分 / 其他")
  }
  "其他"
}

unit_notes <- c(
  "血液学：WBC / Neutrophil_Count / Lymphocytes / Monocyte / Platelet_Count = K/µL（10^9/L）；Hemoglobin = g/dL；Hematocrit / RDW = %",
  "生化：Albumin / Globulin = g/dL；Creatinine / BUN / Uric_Acid = mg/dL；Glucose = mg/dL；HbA1c = %；Insulin = µU/mL；Bilirubin = mg/dL；ALT / AST / LD = IU/L",
  "血脂：Total_Cholesterol / Triglycerides / HDL / LDL = mg/dL",
  "炎症：CRP / HSCRP = mg/L；Fibrinogen = mg/dL",
  "体征：Weight = kg；Height = cm；Waist_circumference = cm；SBP / DBP = mmHg",
  "尿液：Urine_Creatinine = mg/dL；Albumin_Urine / AlbuminUrine = mg/L",
  "常见换算常数：×17.1（胆红素 mg/dL→µmol/L，ALBI）；/18（葡萄糖 mg/dL→mmol/L）；×0.0259（HDL mg/dL→mmol/L）；AST ULN=40 IU/L（APRI）；eAG=28.7×HbA1c−46.7（SHR）"
)

lines <- c(
  "# 指标定义与计算方法",
  "",
  paste0("> 生成时间：", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "> 公式来源：Medical Blocks 引擎 `Blocks/00_index/01block_index.R` → `.idx_definitions()`",
  "",
  "---",
  "",
  "## 一、课题 08 术中低体温症 — 当前暴露指标",
  "",
  "| 项目 | 说明 |",
  "|---|---|",
  "| 指标名 | `Preop_Cr`（术前肌酐） |",
  "| 类型 | **原始实验室变量**，非复合指标（不经 `.idx_definitions` 公式计算） |",
  "| 定义 | 术前血清肌酐（Serum creatinine before surgery） |",
  "| 计算方法 | 直接取原始数据列 `Preop_Cr`；引擎 `config$index$only = \"Preop_Cr\"`，registry 无此名则保留原列 |",
  "| 常用单位 | 本数据集与映射口径一致时多为 **mg/dL**（以 Data 字典 / 原始表为准） |",
  "| 结局 | `hypothermia`：术中低体温（1 = Hypothermia，0 = Non-hypothermia） |",
  "| 关联分析 | Logistic 四分位（Q4 vs Q1）+ RCS 连续效应；Grouping = quartile |",
  "| ML 角色 | 同时作为暴露与最终 ML 特征之一进入预测模型 |",
  "",
  "### 本课题相关实验室列（非复合公式，直接使用）",
  "",
  "| 列名 | 含义（据变量名） |",
  "|---|---|",
  "| Preop_Cr | 术前肌酐 |",
  "| Preop_Na | 术前钠 |",
  "| Preop_Plt | 术前血小板 |",
  "| Preop_Hb | 术前血红蛋白 |",
  "| Preop_Alb | 术前白蛋白 |",
  "| Preop_Aptt | 术前 APTT |",
  "| Preop_K | 术前钾 |",
  "| Preop_Dm | 术前糖尿病史（0/1） |",
  "| Preop_Htn | 术前高血压史（0/1） |",
  "",
  "---",
  "",
  "## 二、引擎复合指标公式总表",
  "",
  paste0("以下为引擎可计算的全部复合指标（共 **", length(defs), "** 个）。缺失组成变量时该指标自动跳过。"),
  "",
  "### 单位假设（公式隐含）",
  "",
  paste0("- ", unit_notes),
  "",
  "### 公式表",
  ""
)

cats <- vapply(defs, function(d) category_of(d$name), character(1))
for (cat in unique(cats)) {
  lines <- c(lines, paste0("#### ", cat), "")
  lines <- c(lines, "| 指标 | 中文/说明 | 计算公式 | 小数位 |", "|---|---|---|---|")
  for (d in defs[cats == cat]) {
    nm <- d$name
    zh <- if (!is.null(zh_name[[nm]]) && nzchar(zh_name[[nm]])) zh_name[[nm]] else nm
    expr <- gsub("\\|", "\\\\|", as.character(d$expr)[1L])
    expr <- gsub("\n", " ", expr, fixed = TRUE)
    dig <- as.character(d$digits %||% 4L)[1L]
    lines <- c(lines, sprintf("| `%s` | %s | `%s` | %s |", nm, zh, expr, dig))
  }
  lines <- c(lines, "")
}

lines <- c(
  lines,
  "---",
  "",
  "## 三、使用说明",
  "",
  "1. **本课题主指标**为 `Preop_Cr`（原始列），不走复合公式。",
  "2. 其它课题若启用 `config$index$enable = TRUE`，由 `index` block 按上表计算并写入数据。",
  "3. `config$index$only` / `skip` 可限制计算范围；`digits` 控制舍入。",
  "4. 组成变量进入协变量池时须遵守疾病变量与指标组成硬排除铁律（`analysis_exclusion`）。",
  "5. 源文件更新后请重新运行：`Rscript run/pub/export_index_definitions_md.R <输出路径>`。",
  "",
  "---",
  "",
  "*自动生成自 Medical Blocks 引擎，请以 `Blocks/00_index/01block_index.R` 为准。*"
)

dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
writeLines(lines, out_path, useBytes = TRUE)

# 同步一份到 docs/
out_docs <- "/mnt/g/DockerHome/5003/medical-blocks-studies/docs/指标定义与计算方法.md"
dir.create(dirname(out_docs), recursive = TRUE, showWarnings = FALSE)
writeLines(lines, out_docs, useBytes = TRUE)

message("已写出: ", out_path, " (", file.info(out_path)$size, " bytes)")
message("已写出: ", out_docs, " (", file.info(out_docs)$size, " bytes)")
message("复合指标数: ", length(defs))
