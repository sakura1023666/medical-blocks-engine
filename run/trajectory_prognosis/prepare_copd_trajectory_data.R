#!/usr/bin/env Rscript
# =============================================================================
#  COPD 轨迹预后：合并基线 + 28 天院内死亡 +（eICU）长表实验室 → 引擎宽表
#
#  输入: G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177/data/{mimic,eicu}
#  输出: 同目录 D02_COPD_*_surv28.RData + eicu/COPD_lab_daily_wide_d1-30.csv
#
#  Rscript run/trajectory_prognosis/prepare_copd_trajectory_data.R
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

.root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  # Windows R：忽略 .env 的 /mnt/g
  is_win <- identical(.Platform$OS.type, "windows")
  env_ok <- nzchar(env) && dir.exists(env) &&
    !(is_win && grepl("^/mnt/", env))
  if (env_ok) env
  else if (is_win) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else "G:/02block_result"
}
.study <- file.path(.root, "55_COPD/Prognosis_Trajectory_v2_42558177")
.data <- file.path(.study, "data")
dir.create(file.path(.study, "Data"), recursive = TRUE, showWarnings = FALSE)

.review <- file.path(.study, "Data/_column_review.md")

.message <- function(...) cat(paste0(...), "\n")

# ── MIMIC ────────────────────────────────────────────────────────────────────
.prepare_mimic <- function() {
  mim <- file.path(.data, "mimic")
  load(file.path(mim, "D01_baseline_MIMIC_ICU_1023 (1).RData")) # baseline
  stopifnot(exists("baseline"))
  b <- as.data.table(baseline)
  b[, subject_id := as.character(ID)]
  copd <- fread(file.path(mim, "COPD-预后(1).csv"))
  copd[, subject_id := as.character(subject_id)]
  ids <- unique(copd$subject_id)
  b <- b[subject_id %in% ids]
  # survival from COPD file (already has death_within_hosp_28days)
  keep <- c("subject_id", "hosp_survival_day", "death_within_hosp_28days",
            "icu_survival_day", "death_within_icu_28days", "stay_id.x", "hadm_id.x")
  keep <- intersect(keep, names(copd))
  s <- unique(copd[, ..keep], by = "subject_id")
  dt <- merge(b, s, by = "subject_id", all.x = FALSE)
  dt[, survival_28d := as.integer(death_within_hosp_28days == 1L)]
  dt[, survival_time_28d := {
    t <- as.numeric(hosp_survival_day)
    fifelse(survival_28d == 1L & is.finite(t), pmax(0.01, pmin(28, t)), 28)
  }]
  dt[is.na(survival_time_28d), survival_time_28d := 28]
  out <- file.path(mim, "D02_COPD_MIMIC_surv28.RData")
  data_imp <- as.data.frame(dt)
  save(data_imp, file = out)
  .message("[MIMIC] n=", nrow(data_imp), " events=", sum(data_imp$survival_28d == 1L), " -> ", out)
  invisible(list(n = nrow(data_imp), events = sum(data_imp$survival_28d == 1L), path = out))
}

# ── eICU lab item → engine suffix ────────────────────────────────────────────
.eicu_item_map <- function() {
  c(
    "WBC x 1000" = "labwbc",
    "RBC" = "labrbc",
    "-polys" = "labpolys",
    "-lymphs" = "lablymphocytes",
    "platelets x 1000" = "labplateletcount",
    "Hgb" = "labhgb",
    "RDW" = "labrdw",
    "Hct" = "labhct",
    "albumin" = "labalbumin",
    "total protein" = "labtotalprotein",
    "sodium" = "labsodium",
    "potassium" = "labpotassium",
    "glucose" = "labglucose",
    "bedside glucose" = "labbedglucose",
    "creatinine" = "labcreatinine",
    "BUN" = "labbun",
    "AST (SGOT)" = "labast",
    "ALT (SGPT)" = "labalt",
    "total bilirubin" = "labtotalbilirubin",
    "triglycerides" = "labtg",
    "HDL" = "labhdl",
    "LDL" = "labldl",
    "total cholesterol" = "labtc",
    "anion gap" = "labaniongap",
    "uric acid" = "laburicacid",
    "fibrinogen" = "labfibrinogen",
    "lactate" = "lablactate",
    "CRP" = "labcrp"
  )
}

.prepare_eicu_labs_wide <- function(cohort_ids) {
  lab_dir <- file.path(.data, "eicu/1-30天实验室数据")
  files <- c(
    file.path(lab_dir, "eicu_全ICU_lab_daily_full_d1-10.csv"),
    file.path(lab_dir, "eicu_全ICU_lab_daily_full_d11-20.csv"),
    file.path(lab_dir, "eicu_全ICU_lab_daily_full_d21-30.csv")
  )
  files <- files[file.exists(files)]
  stopifnot(length(files) > 0L)
  imap <- .eicu_item_map()
  want_items <- names(imap)
  ids <- as.character(unique(cohort_ids))
  chunks <- lapply(files, function(f) {
    .message("读实验室: ", basename(f))
    dt <- fread(f, showProgress = FALSE)
    dt[, patientunitstayid := as.character(patientunitstayid)]
    dt <- dt[patientunitstayid %in% ids & item %in% want_items]
    dt
  })
  long <- rbindlist(chunks, use.names = TRUE, fill = TRUE)
  if (!nrow(long)) stop("eICU COPD 实验室过滤后为空", call. = FALSE)
  long[, sfx := imap[as.character(item)]]
  long <- long[!is.na(sfx) & is.finite(day) & day >= 1L & day <= 30L]
  long[, col := paste0("lab", as.integer(day), "_", sfx)]
  # 一人×列：取 median
  wide <- dcast(long, patientunitstayid ~ col, value.var = "median", fun.aggregate = function(z) {
    z <- z[is.finite(z)]
    if (!length(z)) NA_real_ else as.numeric(stats::median(z))
  })
  setnames(wide, "patientunitstayid", "subject_id")
  out <- file.path(.data, "eicu/COPD_lab_daily_wide_d1-30.csv")
  fwrite(wide, out)
  .message("[eICU labs] n=", nrow(wide), " cols=", ncol(wide), " -> ", out)
  invisible(out)
}

.prepare_eicu <- function() {
  eicu <- file.path(.data, "eicu")
  load(file.path(eicu, "D01_baseline_EICU_firstAll_ext_20261024 (1).RData"))
  stopifnot(exists("baseline"))
  b <- as.data.table(baseline)
  b[, subject_id := as.character(ID)]
  copd <- fread(file.path(eicu, "COPD-EICU预后数据(1).csv"))
  copd[, subject_id := as.character(patientunitstayid)]
  ids <- unique(copd$subject_id)
  b <- b[subject_id %in% ids]
  surv <- fread(file.path(eicu, "eICU_ICU_survival_20261024 (1).csv"))
  surv[, subject_id := as.character(patientunitstayid)]
  keep <- c("subject_id", "hosp_survival_day", "death_within_hosp_28days",
            "icu_survival_day", "death_within_icu_28days")
  keep <- intersect(keep, names(surv))
  s <- unique(surv[, ..keep], by = "subject_id")
  dt <- merge(b, s, by = "subject_id", all.x = FALSE)
  # fallback: hospital discharge status from COPD file if survival miss
  if (anyNA(dt$death_within_hosp_28days)) {
    .message("[eICU] survival 缺失 ", sum(is.na(dt$death_within_hosp_28days)), " 行，尝试 unitdischargestatus")
  }
  dt <- dt[!is.na(death_within_hosp_28days)]
  dt[, survival_28d := as.integer(death_within_hosp_28days == 1L)]
  dt[, survival_time_28d := {
    t <- as.numeric(hosp_survival_day)
    fifelse(survival_28d == 1L & is.finite(t), pmax(0.01, pmin(28, t)), 28)
  }]
  dt[is.na(survival_time_28d), survival_time_28d := 28]
  lab_path <- .prepare_eicu_labs_wide(dt$subject_id)
  out <- file.path(eicu, "D02_COPD_EICU_surv28.RData")
  data_imp <- as.data.frame(dt)
  save(data_imp, file = out)
  .message("[eICU] n=", nrow(data_imp), " events=", sum(data_imp$survival_28d == 1L), " -> ", out)
  invisible(list(n = nrow(data_imp), events = sum(data_imp$survival_28d == 1L), path = out, lab = lab_path))
}

.main <- function() {
  m <- .prepare_mimic()
  e <- .prepare_eicu()
  lines <- c(
    "# COPD Trajectory column review (auto)",
    "",
    paste0("- Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("- MIMIC analytic N=", m$n, " events=", m$events),
    paste0("- eICU analytic N=", e$n, " events=", e$events),
    "",
    "## disease_vars (hard exclusion)",
    "",
    "- `COPD`（队列疾病标签，禁止进 Model/亚组/中介）",
    "",
    "## outcome",
    "",
    "- `death_within_hosp_28days` → `survival_28d` + `survival_time_28d`（院内 28 天）",
    "",
    "## notes",
    "",
    "- 暴露为 dual_safe 复合指标日轨迹（非体温）；eICU 实验室已由长表 pivot 为 lab{d}_* 宽表。",
    "- PAMM 阈值：MIMIC P5/P95 锁定，外验套同一绝对切点。"
  )
  writeLines(lines, .review)
  .message("列审阅: ", .review)
  invisible(NULL)
}

.main()
