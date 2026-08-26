###############################################################################
#  block_system_map_library.R — 生理系统自动映射库
#
#  对外接口（source 本文件后即可使用）:
#    get_system_map(vars, unknown_system="Other", verbose=TRUE)
#        → data.frame(Variable, System)，行顺序与 vars 一致
#    add_system_map(var, system)  — 运行时手动添加/覆盖映射（会话级有效）
#    print_system_map_db()        — 打印当前全量映射表（内置 + 自定义）
#    list_systems()               — 返回所有已知生理系统名称
#
#  调用方式（由 01block_chord_diagram.R 等同目录 block 内部 source）:
#    source("Blocks/29_chord_diagram/block_system_map_library.R")
#    smap <- get_system_map(my_vars)
#
#  优先级: 用户自定义精确 > 内置精确 > 大小写不敏感精确 > regex 关键词兜底
###############################################################################

# ── 1. 精确匹配表（大小写敏感，优先级最高）────────────────────────────────────
.SYSTEM_EXACT <- data.frame(stringsAsFactors = FALSE,
  Variable = c(
    # Respiratory
    "pO2","PaO2","po2","PO2","SpO2","spo2","FiO2","fiO2",
    "PF_ratio","P_F","PF","pf","RR","resp_rate","RespiratoryRate","respiratory_rate",
    "PEEP","peep","pco2","PCO2","PaCO2","TV","tidal_volume",
    # Cardiovascular
    "HR","HeartRate","heart_rate","MAP","map",
    "SBP","sbp","DBP","dbp","PP","pulse_pressure",
    "CVP","CO","cardiac_output","CI","cardiac_index",
    # Hematology / Inflammation
    "WBC","wbc","Leukocyte","leukocyte",
    "PlateletCount","Platelet","platelet","PLT","plt",
    "Hemoglobin","hemoglobin","HB","hb","Hgb","hgb",
    "INR","inr","PT","aPTT","aptt","Fibrinogen","fibrinogen",
    "Neutrophil","neutrophil","Lymphocyte","lymphocyte",
    "CRP","crp","PCT","pct","ESR","esr","IL6","il6",
    # Metabolic / Acid-Base
    "Lactate","lactate","LAC","lac",
    "pH","ph",
    "Glucose","glucose","GLU","glu","Blood_glucose",
    "Bicarbonate","bicarbonate","HCO3","hco3",
    "BaseExcess","base_excess","BE","be",
    "Sodium","sodium","Na","na",
    "Potassium","potassium","K","k_level",
    "Chloride","chloride","Cl","cl",
    "Calcium","calcium","Ca","ca",
    "Magnesium","magnesium","Mg","mg_level",
    "Phosphorus","phosphorus","Phos","phos",
    # Renal
    "Creatinine","creatinine","CR","cr","Scr","scr",
    "BUN","bun","Urea","urea","eGFR","egfr","GFR","gfr",
    "UrineOutput","urine_output","Urine","urine",
    "Cystatin","cystatin",
    # Hepatic
    "ALT","alt","AST","ast","ALP","alp",
    "Bilirubin","bilirubin","TBIL","tbil","DBIL","dbil",
    "Albumin","albumin","ALB","alb",
    "GGT","ggt","LDH","ldh",
    # Neurological
    "GCS","gcs","Glasgow","glasgow",
    "NIHSS","nihss","FOUR","four_score",
    "Consciousness","consciousness",
    # Temperature
    "Temperature","temperature","Temp","temp","T_core",
    # Severity Score
    "SOFA","sofa","APACHE","apache","SAPS","saps",
    "Charlson","charlson","SIRS","sirs",
    # Coagulation
    "APTT","Thrombin","thrombin","D_dimer","d_dimer","DDimer",
    # Endocrine
    "Cortisol","cortisol","Insulin","insulin","TSH","tsh",
    "HbA1c","hba1c","A1c","a1c"
  ),
  System = c(
    rep("Respiratory",     23),
    rep("Cardiovascular",  16),
    rep("Hematology/Inf",  34),
    rep("Metabolic/Base",  43),
    rep("Renal",           20),
    rep("Hepatic",         20),
    rep("Neurological",    10),
    rep("Temperature",      5),
    rep("Severity Score",  10),
    rep("Coagulation",      6),
    rep("Endocrine",       10)
  )
)

# ── 2. 关键词 regex 兜底匹配表（转小写后匹配，精确表未命中时使用）─────────────
.SYSTEM_REGEX <- data.frame(stringsAsFactors = FALSE,
  pattern = c(
    "o2|fio2|pao2|spo2|peep|resp|breath|ventil|tidal|pco2",
    "heart|cardiac|\\bmap\\b|\\bhr\\b|\\bsbp|\\bdbp|blood.?pres|pulse|arteri",
    "wbc|leuko|neutro|lympho|platelet|\\bplt\\b|hemoglobin|\\bhb\\b|hgb|inr|fibrin|crp|\\bpct\\b|il.?6|esr",
    "lactat|\\bph\\b|glucose|gluco|bicarbonate|hco3|base.?excess|sodium|\\bna\\b|potassium|chloride|calcium|magnesium|phospho",
    "creatinin|\\bcr\\b|\\bscr\\b|\\bbun\\b|\\burea\\b|egfr|urine|cystat",
    "\\balt\\b|\\bast\\b|\\balp\\b|bilirub|tbil|albumin|\\balb\\b|\\bggt\\b|\\bldh\\b|liver|hepat",
    "gcs|glasgow|nihss|neuro|conscious|cognit",
    "temp|fever|hypotherm",
    "sofa|apache|saps|charlson|sirs|severity",
    "aptt|thrombin|d.?dimer|coagul|fibrinol",
    "cortisol|insulin|tsh|hba1c|thyroid|endocrin|hormone"
  ),
  System = c(
    "Respiratory","Cardiovascular","Hematology/Inf",
    "Metabolic/Base","Renal","Hepatic",
    "Neurological","Temperature","Severity Score",
    "Coagulation","Endocrine"
  )
)

# ── 3. 用户自定义表（运行时 add_system_map 写入，初始为空）────────────────────
.SYSTEM_CUSTOM <- data.frame(
  Variable = character(0), System = character(0),
  stringsAsFactors = FALSE
)

# ── 4. 核心映射函数 ───────────────────────────────────────────────────────────

#' 获取变量的生理系统映射
#'
#' @param vars          character vector：待映射变量名
#' @param unknown_system 无法识别时的归类名（默认 "Other"）
#' @param verbose       是否打印未识别变量警告
#' @return data.frame(Variable, System)，行顺序与 vars 一致
get_system_map <- function(vars, unknown_system = "Other", verbose = TRUE) {
  vars   <- as.character(vars)
  result <- data.frame(Variable = vars, System = NA_character_,
                       stringsAsFactors = FALSE)

  # 优先级1：用户自定义精确
  for (i in seq_along(vars)) {
    hit <- .SYSTEM_CUSTOM$System[.SYSTEM_CUSTOM$Variable == vars[i]]
    if (length(hit) == 1L) result$System[i] <- hit
  }

  # 优先级2：内置精确（大小写敏感）
  for (i in seq_along(vars)) {
    if (!is.na(result$System[i])) next
    hit <- .SYSTEM_EXACT$System[.SYSTEM_EXACT$Variable == vars[i]]
    if (length(hit) >= 1L) result$System[i] <- hit[1L]
  }

  # 优先级3：大小写不敏感精确
  exact_lower <- tolower(.SYSTEM_EXACT$Variable)
  for (i in seq_along(vars)) {
    if (!is.na(result$System[i])) next
    hit_idx <- which(exact_lower == tolower(vars[i]))
    if (length(hit_idx) >= 1L) result$System[i] <- .SYSTEM_EXACT$System[hit_idx[1L]]
  }

  # 优先级4：regex 关键词兜底（转小写后匹配）
  for (i in seq_along(vars)) {
    if (!is.na(result$System[i])) next
    v_lower <- tolower(vars[i])
    for (j in seq_len(nrow(.SYSTEM_REGEX))) {
      if (grepl(.SYSTEM_REGEX$pattern[j], v_lower, perl = TRUE)) {
        result$System[i] <- .SYSTEM_REGEX$System[j]
        break
      }
    }
  }

  # 兜底：归入 unknown_system
  unrecognized <- vars[is.na(result$System)]
  if (length(unrecognized) > 0) {
    if (verbose)
      message("[system_map] 以下变量未能自动识别系统，已归入 '", unknown_system, "'：\n  ",
              paste(unrecognized, collapse = ", "),
              "\n  可用 add_system_map() 手动添加映射。")
    result$System[is.na(result$System)] <- unknown_system
  }
  result
}

#' 运行时添加/覆盖自定义变量→系统映射（会话级有效）
#'
#' @param var    character vector：变量名
#' @param system character：系统名（长度为 1 或与 var 等长）
#' @examples
#'   add_system_map("MyBiomarker", "Cardiovascular")
#'   add_system_map(c("X1","X2"), c("Renal","Hepatic"))
add_system_map <- function(var, system) {
  var    <- as.character(var)
  system <- as.character(system)
  if (length(system) == 1L) system <- rep(system, length(var))
  stopifnot(length(var) == length(system))
  new_rows        <- data.frame(Variable = var, System = system, stringsAsFactors = FALSE)
  .SYSTEM_CUSTOM <<- .SYSTEM_CUSTOM[!.SYSTEM_CUSTOM$Variable %in% var, , drop = FALSE]
  .SYSTEM_CUSTOM <<- rbind(.SYSTEM_CUSTOM, new_rows)
  invisible(.SYSTEM_CUSTOM)
}

#' 打印当前完整映射库（内置精确 + 用户自定义）
print_system_map_db <- function() {
  combined <- rbind(
    cbind(.SYSTEM_EXACT,  Source = "内置"),
    cbind(.SYSTEM_CUSTOM, Source = "自定义")
  )
  combined <- combined[order(combined$System, combined$Variable), ]
  print(combined, row.names = FALSE)
  invisible(combined)
}

#' 返回当前库已知的所有生理系统名称
list_systems <- function() sort(unique(c(.SYSTEM_EXACT$System, .SYSTEM_REGEX$System)))
