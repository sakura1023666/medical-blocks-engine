#!/usr/bin/env Rscript

# Prepare the single-database MIMIC acute-pancreatitis trajectory cohort.
# Inputs are the AP cohort IDs, MIMIC prognosis table, and 1-30 day lab table.

suppressPackageStartupMessages(library(data.table))

root <- Sys.getenv("BLOCK_RESULT_ROOT", unset = "")
if (!nzchar(root) || !dir.exists(root)) {
  root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
}
study_root <- file.path(root, "41_AP/Prognosis_Trajectory_38882552")
data_dir <- file.path(study_root, "data/mimic")
cohort_file <- file.path(data_dir, "MIMIC-ICU-急性胰腺炎.csv")
prognosis_file <- file.path(data_dir, "mimic预后数据-all.csv")
lab_file <- file.path(data_dir, "mimic-实验室指标-all-1~30天.csv")
out_file <- file.path(data_dir, "D01_AP_MIMIC_surv28.csv")
review_file <- file.path(study_root, "Data/_column_review.md")
raw_names_file <- file.path(study_root, "Data/_column_review_raw.txt")
coverage_file <- file.path(study_root, "Data/trajectory_index_coverage.csv")

stopifnot(file.exists(cohort_file), file.exists(prognosis_file), file.exists(lab_file))
dir.create(dirname(review_file), recursive = TRUE, showWarnings = FALSE)

cohort <- fread(cohort_file, colClasses = "character", showProgress = FALSE)
prognosis <- fread(prognosis_file, showProgress = FALSE)
lab_header <- names(fread(lab_file, nrows = 0L, showProgress = FALSE))

keys <- c("subject_id", "stay_id", "hadm_id")
if (!all(keys %in% names(cohort)) || !all(keys %in% names(prognosis))) {
  stop("AP cohort or prognosis table lacks subject_id/stay_id/hadm_id")
}
for (key in keys) {
  cohort[[key]] <- as.character(cohort[[key]])
  prognosis[[key]] <- as.character(prognosis[[key]])
}

ap <- merge(cohort, prognosis, by = keys, all.x = TRUE, sort = FALSE)
if (anyDuplicated(ap[, ..keys])) {
  setorder(ap, subject_id, stay_id, hadm_id)
  ap <- unique(ap, by = keys)
}
if (anyNA(ap$death_within_hosp_28days)) {
  stop("Some AP cohort members lack death_within_hosp_28days after prognosis merge")
}

# Event=death within 28 days after hospital admission. Non-events are censored at day 28.
ap[, survival_28d := as.integer(death_within_hosp_28days == 1)]
ap[, survival_time_28d := fifelse(
  survival_28d == 1L & is.finite(as.numeric(hosp_survival_day)),
  pmax(0.01, pmin(28, as.numeric(hosp_survival_day))),
  28
)]

# Read only the AP cohort's lab rows, then expose day-1 values under engine-standard names.
lab <- fread(lab_file, showProgress = FALSE)
for (key in intersect(keys, names(lab))) lab[[key]] <- as.character(lab[[key]])
lab <- lab[get("subject_id") %chin% unique(ap$subject_id)]
if (all(keys %in% names(lab))) {
  setorder(lab, subject_id, stay_id, hadm_id)
  lab <- unique(lab, by = keys)
  ap <- merge(ap, lab, by = keys, all.x = TRUE, sort = FALSE)
} else {
  lab <- unique(lab, by = "subject_id")
  ap <- merge(ap, lab, by = "subject_id", all.x = TRUE, sort = FALSE)
}

day1_map <- c(
  WBC = "lab1_labwbc",
  RBC = "lab1_labrbc",
  Neutrophil_Count = "lab1_labneutrophilcount",
  Lymphocytes = "lab1_lablymphocytes",
  Platelet_Count = "lab1_labplateletcount",
  Hemoglobin = "lab1_labhemoglobin",
  RDW = "lab1_labrdw",
  Hematocrit = "lab1_labhematocrit",
  Albumin = "lab1_labalbumin",
  TotalProtein = "lab1_labtotalprotein",
  Sodium = "lab1_labsodium",
  Potassium = "lab1_labpotassium",
  Glucose = "lab1_labglucose",
  HbA1c = "lab1_laba1c",
  AnionGap = "lab1_labaniongap",
  Fibrinogen = "lab1_labfibrinogen",
  Triglycerides = "lab1_labtg",
  Total_Cholesterol = "lab1_labcholesteroltotal",
  HDL = "lab1_labhdl",
  LDL = "lab1_labldl",
  Bilirubin_Total = "lab1_labbilirubintotal",
  ALT = "lab1_labalt",
  AST = "lab1_labast",
  BUN = "lab1_labureanitrogen",
  Creatinine = "lab1_labcreatinine",
  Uric_Acid = "lab1_laburicacid",
  LD = "lab1_labld"
)
for (standard_name in names(day1_map)) {
  source_name <- unname(day1_map[[standard_name]])
  ap[[standard_name]] <- if (source_name %in% names(ap)) {
    suppressWarnings(as.numeric(ap[[source_name]]))
  } else {
    NA_real_
  }
}
ap[, Globulin := TotalProtein - Albumin]

# ── Merge ICU 打标基线表（人口学 + 生命体征 + 共病），使亚组/协变量可用 ──────
demo_file <- file.path(data_dir, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
stopifnot(file.exists(demo_file))
demo_env <- new.env(parent = emptyenv())
load(demo_file, envir = demo_env)
demo <- get("baseline", envir = demo_env)
demo_cols <- intersect(c(
  "Age", "Gender", "Race", "Language", "Marital_Status",
  "Weight", "Height", "BMI",
  "HR", "RR", "SpO2", "Temperature", "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM",
  "Hypertension", "T2DM", "T1DM", "Heart_Failure", "Myocardial_Infarction",
  "Malignant_Tumor", "CKD", "Acute_Renal_Failure", "Liver_cirrhosis", "Hepatitis",
  "Tuberculosis", "Pneumonia", "Stroke", "Hyperlipidemia", "COPD"
), names(demo))
demo$ID <- as.character(demo$ID)
demo <- demo[!duplicated(demo$ID), c("ID", demo_cols), drop = FALSE]
setnames(demo, "ID", "subject_id")
ap <- merge(ap, demo, by = "subject_id", all.x = TRUE, sort = FALSE)
n_age_na <- sum(is.na(ap$Age))
cat(sprintf("baseline demo merged: %d cols, Age NA=%d\n", length(demo_cols), n_age_na))

baseline_keep <- unique(c(
  keys, "survival_time_28d", "survival_28d", names(day1_map), "Globulin",
  demo_cols
))
baseline <- ap[, intersect(baseline_keep, names(ap)), with = FALSE]
fwrite(baseline, out_file, na = "")

# Audit every registered composite formula against this AP cohort. A retained
# trajectory needs at least two observed days in at least 50 patients. Raw
# passthrough entries (HDL/LDL) and one-component transforms are not composites.
engine_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "configs/indices/composite_index_vars.R"), local = FALSE)
source(file.path(engine_root, "R/trajectory_28d_index_utils.R"), local = FALSE)
source(file.path(engine_root, "Blocks/00_index/01block_index.R"), local = FALSE)

lab_for_components <- as.data.frame(lab)
components <- trajectory_28d_build_daily_components(
  lab_for_components,
  days = 1:28,
  db_type = "mimic",
  id_col = "subject_id",
  lab_id_col = "subject_id"
)
components <- trajectory_28d_merge_baseline(
  components,
  as.data.frame(baseline),
  id_col = "subject_id"
)
definitions <- pipeline_index_definition_map()
coverage <- rbindlist(lapply(.composite_index_vars, function(index_name) {
  definition <- definitions[[index_name]]
  raw_components <- if (!is.null(definition)) {
    pipeline_index_raw_components(index_name, definitions = definitions)
  } else {
    character(0)
  }
  true_composite <- length(unique(raw_components)) >= 2L
  if (is.null(definition)) {
    return(data.table(
      index = index_name, raw_components = "", n_components = 0L,
      n_ge2_days = 0L, events = 0L, true_composite = FALSE,
      retained = FALSE, reason = "指标公式未注册"
    ))
  }
  calculated <- calc_28d_index(
    components,
    index_name,
    trajectory_28d_make_formula_func(as.character(definition)[1L])
  )
  day_cols <- paste0(index_name, "_", 1:28)
  n_days <- rowSums(!is.na(as.matrix(calculated[, day_cols, drop = FALSE])))
  eligible_ids <- as.character(calculated$subject_id[n_days >= 2L])
  n_eligible <- length(unique(eligible_ids))
  n_events <- sum(
    baseline$survival_28d[match(unique(eligible_ids), baseline$subject_id)] == 1L,
    na.rm = TRUE
  )
  retained <- true_composite && n_eligible >= 50L && n_events >= 10L
  reason <- if (!true_composite) {
    "非复合：原始透传或单成分变换"
  } else if (n_eligible < 50L) {
    "至少2天有效值人数<50"
  } else if (n_events < 10L) {
    "至少2天有效值人群事件数<10"
  } else {
    "保留"
  }
  data.table(
    index = index_name,
    raw_components = paste(raw_components, collapse = "+"),
    n_components = length(unique(raw_components)),
    n_ge2_days = n_eligible,
    events = n_events,
    true_composite = true_composite,
    retained = retained,
    reason = reason
  )
}), fill = TRUE)
fwrite(coverage, coverage_file)

all_raw_names <- unique(c(
  paste0("cohort::", names(cohort)),
  paste0("prognosis::", names(prognosis)),
  paste0("labs::", lab_header),
  paste0("analysis::", names(baseline))
))
writeLines(all_raw_names, raw_names_file, useBytes = TRUE)

disease_terms <- c(
  "lipase", "amylase", "pancreatitis", "bisap", "ranson",
  "apache", "necrosis", "pseudocyst"
)
leak_terms <- c(
  "dead", "death", "survival", "disch", "outtime", "los", "icu_day",
  "hosp_day", "admit_time", "icu_intime"
)
review_one <- function(x) {
  bare <- sub("^[^:]+::", "", x)
  low <- tolower(bare)
  if (any(vapply(disease_terms, grepl, logical(1L), x = low, fixed = TRUE))) {
    return(c("硬排除", "急性胰腺炎诊断、分型、评分或核心病理标志物"))
  }
  if (any(vapply(leak_terms, grepl, logical(1L), x = low, fixed = TRUE)) &&
      !bare %chin% c("survival_time_28d", "survival_28d")) {
    return(c("硬排除", "结局、随访后或住院流程信息，存在预后泄漏"))
  }
  if (grepl("_uom$", low)) return(c("不入分析", "实验室单位元数据"))
  if (bare %chin% keys) return(c("仅作键", "患者/住院/ICU连接标识"))
  if (bare %chin% c("survival_time_28d", "survival_28d")) {
    return(c("结局专用", "28天生存时间或事件列，不作协变量"))
  }
  if (startsWith(x, "labs::lab") && grepl("^lab[0-9]+_", bare)) {
    return(c("纵向候选", "用于逐日复合指标计算；不直接作为主暴露"))
  }
  c("保留候选", "通用基线实验室变量；仍受缺失率和当前指标组成排除")
}
review <- t(vapply(all_raw_names, review_one, character(2L)))
review_lines <- c(
  "# 急性胰腺炎 MIMIC 单库轨迹：原始列审阅",
  "",
  sprintf("- AP队列人数：%d", nrow(cohort)),
  sprintf("- 成功合并28天结局人数：%d；事件数：%d", nrow(baseline), sum(baseline$survival_28d)),
  "- 年龄切点：65岁（急性胰腺炎文献常用老年界值）；当前数据未提供Age，亚组块不强行构造。",
  "- 疾病硬排除原则：Lipase/Amylase、AP诊断/分型、BISAP/Ranson/APACHE、坏死等若出现均不进协变量。",
  "",
  "| 列名 | 处置 | 理由 |",
  "|---|---|---|",
  sprintf(
    "| `%s` | %s | %s |",
    gsub("\\|", "\\\\|", all_raw_names),
    review[, 1L],
    review[, 2L]
  )
)
writeLines(review_lines, review_file, useBytes = TRUE)

cat(sprintf(
  "Prepared %s: n=%d, events=%d; retained_indices=%d; review=%s; coverage=%s\n",
  out_file, nrow(baseline), sum(baseline$survival_28d),
  sum(coverage$retained), review_file, coverage_file
))
