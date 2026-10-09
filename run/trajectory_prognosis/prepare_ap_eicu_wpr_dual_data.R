#!/usr/bin/env Rscript

# Prepare eICU external-validation data for the AP WPR dual-database
# trajectory run. Writes ONLY into
#   41_AP/Prognosis_Trajectory_38882552_WPR_dual
# and never touches the existing MIMIC result folders.

suppressPackageStartupMessages(library(data.table))

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  script_dir <- if (length(f)) {
    dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  } else {
    normalizePath(getwd(), winslash = "/")
  }
  if (basename(script_dir) == "trajectory_prognosis" &&
      basename(dirname(script_dir)) == "run") {
    normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
  } else {
    script_dir
  }
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

engine_root <- .init_root()
setwd(engine_root)

root <- Sys.getenv("BLOCK_RESULT_ROOT", unset = "")
if (!nzchar(root) || !dir.exists(root)) {
  root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
}

src_root <- file.path(root, "41_AP/Prognosis_Trajectory_38882552")
dual_root <- file.path(root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual")
src_eicu <- file.path(src_root, "data/eicu")
src_mimic <- file.path(src_root, "data/mimic")
out_eicu <- file.path(dual_root, "data/eicu")
out_mimic <- file.path(dual_root, "data/mimic")
review_dir <- file.path(dual_root, "data")
# 优先用本课题已归档的 _source；缺则回退原课题 data/
.local_eicu_src <- file.path(out_eicu, "_source")
.local_mimic_src <- file.path(out_mimic, "_source")
dir.create(out_eicu, recursive = TRUE, showWarnings = FALSE)
dir.create(out_mimic, recursive = TRUE, showWarnings = FALSE)
dir.create(review_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(dual_root, "reports"), recursive = TRUE, showWarnings = FALSE)
dir.create(.local_eicu_src, recursive = TRUE, showWarnings = FALSE)
dir.create(.local_mimic_src, recursive = TRUE, showWarnings = FALSE)

.pick_src <- function(local_dir, remote_dir, name) {
  loc <- file.path(local_dir, name)
  rem <- file.path(remote_dir, name)
  if (file.exists(loc)) return(loc)
  if (file.exists(rem)) return(rem)
  stop("找不到数据文件: ", name, "\n  试过: ", loc, "\n  与: ", rem, call. = FALSE)
}

stay_file <- .pick_src(.local_eicu_src, src_eicu, "eicu_ap_stay_ids.csv")
prog_file <- .pick_src(.local_eicu_src, src_eicu, "EICU预后数据-all.csv")
demo_file <- .pick_src(.local_eicu_src, src_eicu, "D01_baseline_EICU_ICU_first_0626.RData")
daily_file <- .pick_src(.local_eicu_src, src_eicu, "eicu_ap_wbc_plt_daily.csv")
mimic_baseline <- {
  loc <- file.path(out_mimic, "D01_AP_MIMIC_surv28.csv")
  if (file.exists(loc)) loc else .pick_src(.local_mimic_src, src_mimic, "D01_AP_MIMIC_surv28.csv")
}
stopifnot(
  file.exists(stay_file), file.exists(prog_file),
  file.exists(demo_file), file.exists(daily_file),
  file.exists(mimic_baseline)
)

stay <- fread(stay_file, colClasses = "character", showProgress = FALSE)
stay_ids <- unique(as.character(stay[[1L]]))

# ── eICU prognosis: same 28-day administrative-censor rule as MIMIC AP ─────
prog <- fread(prog_file, showProgress = FALSE)
prog[, patientunitstayid := as.character(patientunitstayid)]
prog <- unique(prog, by = "patientunitstayid")
status <- tolower(trimws(as.character(prog$hospdischargestatus)))
los <- as.numeric(prog$hosplosday)
expired <- !is.na(status) & status == "expired"
prog[, survival_28d := as.integer(expired & is.finite(los) & los <= 28)]
prog[, survival_time_28d := fifelse(
  survival_28d == 1L & is.finite(los),
  pmax(0.01, pmin(28, los)),
  28
)]
prog[, outcome_ok := !is.na(status) & nzchar(status) & is.finite(los) & los >= 0]
n_prog_in_stay <- sum(prog$patientunitstayid %chin% stay_ids)
n_prog_bad <- sum(prog$patientunitstayid %chin% stay_ids & !prog$outcome_ok)

# ── eICU ICU first baseline, restricted to AP stay IDs ─────────────────────
demo_env <- new.env(parent = emptyenv())
load(demo_file, envir = demo_env)
demo <- as.data.table(get("baseline", envir = demo_env))
demo[, ID := as.character(ID)]
n_demo_all <- nrow(demo)
demo <- demo[ID %chin% stay_ids]
n_demo_ap <- nrow(demo)
n_stay_no_demo <- length(setdiff(stay_ids, demo$ID))

ap <- merge(
  demo,
  prog[, .(patientunitstayid, survival_28d, survival_time_28d, outcome_ok,
           hospdischargestatus, hosplosday)],
  by.x = "ID", by.y = "patientunitstayid", all.x = TRUE, sort = FALSE
)
n_before_outcome <- nrow(ap)
ap <- ap[!is.na(outcome_ok) & outcome_ok == TRUE]
n_drop_outcome <- n_before_outcome - nrow(ap)

# Standard engine names (do not keep alias columns).
rename_map <- c(
  PlateletCount = "Platelet_Count",
  NeutrophilCount = "Neutrophil_Count",
  BilirubinTotal = "Bilirubin_Total",
  UreaNitrogen = "BUN",
  TG = "Triglycerides",
  TC = "Total_Cholesterol",
  UricAcid = "Uric_Acid"
)
for (src in names(rename_map)) {
  dst <- unname(rename_map[[src]])
  if (src %in% names(ap)) {
    if (!dst %in% names(ap)) setnames(ap, src, dst) else ap[[src]] <- NULL
  }
}
ap[, subject_id := ID]
ap[, patientunitstayid := ID]

keep_cols <- unique(c(
  "subject_id", "patientunitstayid",
  "survival_time_28d", "survival_28d",
  "Age", "Gender", "Race", "Weight", "Height", "BMI",
  "HR", "RR", "SpO2", "Temperature", "NBPS", "NBPD", "NBPM", "ABPS", "ABPD", "ABPM",
  "WBC", "RBC", "Neutrophil_Count", "Lymphocytes", "Platelet_Count",
  "Hemoglobin", "RDW", "Hematocrit", "Albumin", "Globulin", "TotalProtein",
  "Sodium", "Potassium", "Glucose", "AnionGap", "Fibrinogen",
  "Triglycerides", "Total_Cholesterol", "HDL", "LDL",
  "Bilirubin_Total", "ALT", "AST", "BUN", "Creatinine", "Uric_Acid", "LD",
  "Hypertension", "T2DM", "T1DM", "Heart_Failure", "Myocardial_Infarction",
  "Malignant_Tumor", "CKD", "Liver_cirrhosis", "Hepatitis",
  "Pneumonia", "Stroke", "Hyperlipidemia", "COPD"
))
baseline <- ap[, intersect(keep_cols, names(ap)), with = FALSE]
out_baseline <- file.path(out_eicu, "D01_AP_EICU_surv28.csv")
fwrite(baseline, out_baseline, na = "")

# ── Long daily WBC/PLT → engine-wide lab{d}_lab* ───────────────────────────
daily <- fread(daily_file, showProgress = FALSE)
daily[, patientunitstayid := as.character(patientunitstayid)]
daily[, day := as.integer(day)]
daily <- daily[day >= 1L & day <= 28L]
daily[, suffix := fcase(
  indicator == "WBC", "labwbc",
  indicator == "Platelet_Count", "labplateletcount",
  default = NA_character_
)]
daily <- daily[!is.na(suffix)]
daily[, col := paste0("lab", day, "_", suffix)]
wide <- dcast(
  daily,
  patientunitstayid ~ col,
  value.var = "value",
  fun.aggregate = function(x) suppressWarnings(as.numeric(x)[1L])
)
wide[, subject_id := patientunitstayid]
# Keep only AP stays that entered the analysis baseline.
wide <- wide[subject_id %chin% baseline$subject_id]
out_labs <- file.path(out_eicu, "eicu-实验室指标-wbc-plt-1~28天.csv")
fwrite(wide, out_labs, na = "")

# ── WPR coverage on eICU (same ≥2 days / n≥50 / events≥10 rule) ────────────
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "configs/indices/composite_index_vars.R"), local = FALSE)
source(file.path(engine_root, "R/trajectory_28d_index_utils.R"), local = FALSE)
source(file.path(engine_root, "Blocks/00_index/01block_index.R"), local = FALSE)

lab_df <- as.data.frame(wide)
components <- trajectory_28d_build_daily_components(
  lab_df, days = 1:28, db_type = "eicu",
  id_col = "subject_id", lab_id_col = "patientunitstayid"
)
components <- trajectory_28d_merge_baseline(
  components, as.data.frame(baseline), id_col = "subject_id"
)
definitions <- pipeline_index_definition_map()
wpr_def <- definitions[["WPR"]]
calculated <- calc_28d_index(
  components, "WPR",
  trajectory_28d_make_formula_func(as.character(wpr_def)[1L])
)
day_cols <- paste0("WPR_", 1:28)
n_days <- rowSums(!is.na(as.matrix(calculated[, day_cols, drop = FALSE])))
eligible_ids <- as.character(calculated$subject_id[n_days >= 2L])
n_eligible <- length(unique(eligible_ids))
n_events <- sum(
  baseline$survival_28d[match(unique(eligible_ids), baseline$subject_id)] == 1L,
  na.rm = TRUE
)
coverage <- data.table(
  database = c("MIMIC", "eICU"),
  index = "WPR",
  raw_components = "WBC+Platelet_Count",
  n_ge2_days = c(NA_integer_, n_eligible),
  events = c(NA_integer_, n_events),
  true_composite = TRUE,
  retained = c(TRUE, n_eligible >= 50L && n_events >= 10L),
  reason = c(
    "MIMIC 主分析已保留；本双库跑从原 12_WPR.RData / 基线重算，不覆盖旧 by_index",
    if (n_eligible >= 50L && n_events >= 10L) "保留" else "未达 n/事件门槛"
  )
)
if (file.exists(file.path(src_root, "data/trajectory_index_coverage.csv"))) {
  old <- fread(file.path(src_root, "data/trajectory_index_coverage.csv"))
  if ("WPR" %in% old$index) {
    coverage$n_ge2_days[1L] <- as.integer(old$n_ge2_days[old$index == "WPR"][1L])
    coverage$events[1L] <- as.integer(old$events[old$index == "WPR"][1L])
  }
} else if (file.exists(file.path(src_root, "Data/trajectory_index_coverage.csv"))) {
  old <- fread(file.path(src_root, "Data/trajectory_index_coverage.csv"))
  if ("WPR" %in% old$index) {
    coverage$n_ge2_days[1L] <- as.integer(old$n_ge2_days[old$index == "WPR"][1L])
    coverage$events[1L] <- as.integer(old$events[old$index == "WPR"][1L])
  }
}
fwrite(coverage, file.path(review_dir, "trajectory_index_coverage.csv"))

# ── Column review (every source + analysis column) ─────────────────────────
mimic_cols <- names(fread(mimic_baseline, nrows = 0L, showProgress = FALSE))
eicu_src_cols <- unique(c(
  paste0("stay::", names(stay)),
  paste0("prognosis::", names(fread(prog_file, nrows = 0L, showProgress = FALSE))),
  paste0("demo::", names(get("baseline", envir = demo_env))),
  paste0("daily::", names(fread(daily_file, nrows = 0L, showProgress = FALSE))),
  paste0("analysis::", names(baseline)),
  paste0("labs_wide::", names(wide))
))
writeLines(
  unique(c(paste0("mimic::", mimic_cols), eicu_src_cols)),
  file.path(review_dir, "_column_review_raw.txt"),
  useBytes = TRUE
)

disease_terms <- c(
  "lipase", "amylase", "pancreatitis", "bisap", "ranson",
  "apache", "necrosis", "pseudocyst"
)
leak_terms <- c(
  "dead", "death", "survival", "disch", "outtime", "los", "icu_day",
  "hosp_day", "hosplos", "unitlos", "admit_time", "icu_intime",
  "hospitaldischarge", "unitdischarge", "unitstay", "unittype",
  "hospitaladmit"
)
severity_terms <- c("sofa", "apsiii", "oasis", "gcs")
review_one <- function(x) {
  bare <- sub("^[^:]+::", "", x)
  low <- tolower(bare)
  if (any(vapply(disease_terms, grepl, logical(1L), x = low, fixed = TRUE))) {
    return(c("硬排除", "急性胰腺炎诊断、分型、评分或核心病理标志物"))
  }
  if (any(vapply(severity_terms, grepl, logical(1L), x = low, fixed = TRUE))) {
    return(c("硬排除", "全身严重度评分，不作本课题协变量（双库对齐）"))
  }
  if (any(vapply(leak_terms, grepl, logical(1L), x = low, fixed = TRUE)) &&
      !bare %chin% c("survival_time_28d", "survival_28d")) {
    return(c("硬排除", "结局、随访后或住院流程信息，存在预后泄漏"))
  }
  if (bare %chin% c("Ventilation", "Diabetes", "PP", "PH", "PCO2", "PO2",
                    "Lactate", "TotalCo2", "FreeCalcium", "PT", "PTT", "INR",
                    "CK", "CKMb", "TroponinT", "BNP", "UrineOsmolality",
                    "CRP", "HSCRP", "UrineCreatinine", "CalciumTotal",
                    "Chloride", "BilirubinDirect", "BilirubinIndirect")) {
    return(c("不入本双库表", "eICU 独有或与 MIMIC Table1 不对齐；保留数据但不进双库主分析"))
  }
  if (grepl("_uom$", low)) return(c("不入分析", "实验室单位元数据"))
  if (bare %chin% c("ID", "subject_id", "patientunitstayid", "stay_id", "hadm_id")) {
    return(c("仅作键", "患者/住院/ICU 连接标识"))
  }
  if (bare %chin% c("survival_time_28d", "survival_28d")) {
    return(c("结局专用", "28天生存时间或事件列，不作协变量"))
  }
  if (startsWith(x, "daily::") || startsWith(x, "labs_wide::lab")) {
    return(c("纵向候选", "用于逐日 WPR 计算；不直接作为主暴露"))
  }
  c("保留候选", "双库共有人口学/生命体征/实验室/共病；仍受缺失率和 WPR 组成排除")
}
all_names <- unique(c(paste0("mimic::", mimic_cols), eicu_src_cols))
review <- t(vapply(all_names, review_one, character(2L)))
review_lines <- c(
  "# 急性胰腺炎 WPR 双库轨迹：原始列审阅",
  "",
  sprintf("- 生成时间：%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("- 源课题（只读）：%s", src_root),
  sprintf("- 本双库产出根（不覆盖旧结果）：%s", dual_root),
  sprintf("- eICU AP stay 名单：%d；基线打标命中：%d；名单无打标：%d",
          length(stay_ids), n_demo_ap, n_stay_no_demo),
  sprintf("- eICU 预后可合并：%d；结局缺失剔除：%d；分析 n=%d；28d 院内死亡=%d",
          n_prog_in_stay, n_drop_outcome + n_prog_bad, nrow(baseline),
          sum(baseline$survival_28d)),
  sprintf("- eICU WPR ≥2 天人数：%d；事件：%d", n_eligible, n_events),
  "- 年龄切点：65 岁（急性胰腺炎文献常用老年界值，PMID 36205509）。",
  "- 疾病硬排除：Lipase/Amylase、AP 诊断/分型、BISAP/Ranson/APACHE、坏死等。",
  "- 双库亚组只锁两库都有且最小类足够的变量（见 config 注释）。",
  "",
  "| 列名 | 处置 | 理由 |",
  "|---|---|---|",
  sprintf(
    "| `%s` | %s | %s |",
    gsub("\\|", "\\\\|", all_names),
    review[, 1L],
    review[, 2L]
  )
)
writeLines(review_lines, file.path(review_dir, "_column_review.md"), useBytes = TRUE)

attrition <- rbind(
  data.table(
    database = "eICU",
    step = c(
      "ap_stay_list", "merge_icu_baseline", "complete_28d_hosp_mortality",
      "wpr_ge2_days"
    ),
    n_remain = c(length(stay_ids), n_demo_ap, nrow(baseline), n_eligible),
    n_excluded = c(
      0L, n_stay_no_demo, n_before_outcome - nrow(baseline),
      nrow(baseline) - n_eligible
    ),
    note = c(
      "eicu_ap_stay_ids.csv",
      "D01_baseline_EICU_ICU_first_0626.RData",
      "Expired & hosplosday<=28 → event; non-events censored at day 28",
      "WPR = WBC/Platelet_Count, ≥2 observed days"
    )
  )
)
fwrite(attrition, file.path(review_dir, "Flowchart_attrition_prepare_eicu.csv"))

readme <- c(
  "# AP WPR dual-database trajectory (MIMIC + eICU)",
  "",
  "This folder is a **new** dual-database run. It does **not** overwrite",
  "`41_AP/Prognosis_Trajectory_38882552/by_index` or its checkpoints.",
  "",
  "- Index: WPR (WBC / Platelet_Count), same formula as MIMIC.",
  "- Classes: locked to MIMIC published `ng = 2`.",
  "- Endpoint: 28-day in-hospital death, administrative censoring at day 28.",
  "- Config: `configs/config_trajectory_prognosis_ap_wpr_dual.R`"
)
writeLines(readme, file.path(dual_root, "README.md"))

strat <- c(
  "# 疾病分层数值门控 — 急性胰腺炎 WPR 双库轨迹",
  "",
  "- 本课题主分层不是 AP 指南分期（BISAP/Ranson/坏死），那些列已列入 disease_vars。",
  "- 主结局与已发表 MIMIC 单库一致：入院/ICU 后 28 天院内死亡。",
  "- MIMIC：`death_within_hosp_28days` → `survival_28d`；非事件行政截尾至第 28 天。",
  "- eICU：`hospdischargestatus==Expired` 且 `hosplosday<=28` → 事件；非事件同样截尾至第 28 天。",
  "- 两库同一公式、同一切点、同一时间窗；eICU 缺预后/打标的 stay 已剔除，不改口径。",
  sprintf("- eICU 分析 n=%d，事件=%d；WPR≥2 天 n=%d，事件=%d。",
          nrow(baseline), sum(baseline$survival_28d), n_eligible, n_events),
  "- 年龄亚组：65 岁二分类（PMID 36205509）。"
)
writeLines(strat, file.path(review_dir, "disease_stratification_basis.md"))
writeLines(strat, file.path(dual_root, "reports/disease_stratification_basis_ap_wpr_dual.md"))

cat(sprintf(
  paste0(
    "Prepared eICU AP WPR dual data\n",
    "  baseline: %s (n=%d, events=%d)\n",
    "  labs: %s (n=%d)\n",
    "  WPR>=2d: n=%d events=%d retained=%s\n",
    "  dual_root: %s\n"
  ),
  out_baseline, nrow(baseline), sum(baseline$survival_28d),
  out_labs, nrow(wide),
  n_eligible, n_events, coverage$retained[2L],
  dual_root
))
