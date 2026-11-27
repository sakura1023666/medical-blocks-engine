#!/usr/bin/env Rscript
# =============================================================================
#  AHF 轨迹预后：合并最新基线 + 队列 30 天死亡 + 日级血钠/eGFR → 引擎宽表
#
#  输入: G:/02block_result/67_AHF/Prognosis_Trajectory_v2_42558177/data/{mimic,eicu}
#  输出:
#    D02_AHF_*_surv30.RData
#    AHF_lab_daily_wide_d1-30.csv（lab{d}_labsodium / lab{d}_labegfr）
#    Data/_column_review.md
#
#  Rscript run/trajectory_prognosis/prepare_ahf_trajectory_data.R
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

.root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  is_win <- identical(.Platform$OS.type, "windows")
  env_ok <- nzchar(env) && dir.exists(env) && !(is_win && grepl("^/mnt/", env))
  if (env_ok) env
  else if (is_win) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else "G:/02block_result"
}
.study <- file.path(.root, "67_AHF/Prognosis_Trajectory_v2_42558177")
.data <- file.path(.study, "data")
dir.create(file.path(.study, "Data"), recursive = TRUE, showWarnings = FALSE)
.review <- file.path(.study, "Data/_column_review.md")
.message <- function(...) cat(paste0(...), "\n")

.load_baseline <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  objs <- ls(e)
  hit <- intersect(objs, c("baseline", "b", "data_imp", "dt"))
  if (!length(hit)) hit <- objs[1L]
  as.data.table(get(hit[[1L]], envir = e))
}

.as_posix <- function(x) {
  if (inherits(x, "POSIXt")) return(x)
  out <- suppressWarnings(as.POSIXct(x, tz = "UTC"))
  if (all(is.na(out)) && is.character(x)) {
    out <- suppressWarnings(as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  }
  out
}

.wide_to_lab_csv <- function(wide, id_col, out_csv, days = 1:30) {
  wide <- copy(as.data.table(wide))
  wide[[id_col]] <- as.character(wide[[id_col]])
  setnames(wide, id_col, "subject_id", skip_absent = TRUE)
  labs <- data.table(subject_id = wide$subject_id)
  for (d in days) {
    na_col <- paste0("sodium_d", d)
    eg_col <- paste0("egfr_d", d)
    labs[[paste0("lab", d, "_labsodium")]] <- if (na_col %in% names(wide)) as.numeric(wide[[na_col]]) else NA_real_
    labs[[paste0("lab", d, "_labegfr")]] <- if (eg_col %in% names(wide)) as.numeric(wide[[eg_col]]) else NA_real_
  }
  fwrite(labs, out_csv)
  .message("[labs] n=", nrow(labs), " cols=", ncol(labs), " -> ", out_csv)
  invisible(labs)
}

.prepare_mimic <- function() {
  mim <- file.path(.data, "mimic")
  b <- .load_baseline(file.path(mim, "D01_baseline_MIMIC_ICU_1023.RData"))
  b[, subject_id_person := as.character(ID)]

  cohort <- fread(file.path(mim, "MIMIC急性心力衰竭_队列_11621.csv"))
  cohort[, stay_id := as.character(stay_id)]
  cohort[, subject_id_person := as.character(subject_id)]

  wide <- fread(file.path(mim, "MIMIC每日30天_钠_eGFR_宽表_11621.csv"))
  wide[, stay_id := as.character(stay_id)]

  surv <- fread(file.path(mim, "MIMIC_ICU_survival_1023.csv"))
  surv[, stay_id := as.character(stay_id)]
  surv_keep <- intersect(
    c("stay_id", "hosp_survival_day", "death_within_hosp_28days", "hosp_day", "is_hosp_dead"),
    names(surv)
  )
  s <- unique(surv[, ..surv_keep], by = "stay_id")

  dt <- merge(cohort, b, by = "subject_id_person", all.x = FALSE, suffixes = c("", "_bl"))
  dt <- merge(dt, s, by = "stay_id", all.x = TRUE)
  dt <- merge(
    dt,
    wide[, .(stay_id, day_of_death, obs_days_na, obs_days_egfr, sodium_d1, egfr_d1)],
    by = "stay_id", all.x = TRUE
  )

  # 引擎 ID = stay 级（一人可多 stay；基线按 subject 合并）
  dt[, subject_id := stay_id]
  if ("Age" %in% names(dt) && "age" %in% names(dt)) {
    dt[is.na(Age), Age := as.numeric(age)]
  } else if (!"Age" %in% names(dt) && "age" %in% names(dt)) {
    dt[, Age := as.numeric(age)]
  }
  if ("Gender" %in% names(dt) && "gender" %in% names(dt)) {
    dt[is.na(Gender) | as.character(Gender) == "", Gender := fifelse(
      toupper(as.character(gender)) %in% c("M", "MALE"), "Male",
      fifelse(toupper(as.character(gender)) %in% c("F", "FEMALE"), "Female", as.character(gender))
    )]
  } else if (!"Gender" %in% names(dt) && "gender" %in% names(dt)) {
    dt[, Gender := fifelse(
      toupper(as.character(gender)) %in% c("M", "MALE"), "Male",
      fifelse(toupper(as.character(gender)) %in% c("F", "FEMALE"), "Female", as.character(gender))
    )]
  }

  # 30 天院内死亡（队列封板口径）+ 时间
  dt[, survival_30d := as.integer(died_30d_hosp == 1L)]
  t_admit <- .as_posix(dt$admittime)
  t_disch <- .as_posix(dt$dischtime)
  t_los <- as.numeric(difftime(t_disch, t_admit, units = "days"))
  t_event <- as.numeric(dt$day_of_death)
  t_surv <- as.numeric(dt$hosp_survival_day)
  t_fallback <- fifelse(is.finite(t_los), t_los, as.numeric(dt$hosp_day))
  t <- fifelse(is.finite(t_event) & t_event > 0, t_event,
               fifelse(is.finite(t_surv) & t_surv > 0, t_surv, t_fallback))
  t <- fifelse(is.finite(t) & t > 0, t, 30)
  dt[, survival_time_30d := fifelse(
    survival_30d == 1L, pmax(0.01, pmin(30, t)), pmin(30, pmax(0.01, t))
  )]
  dt[is.na(survival_time_30d), survival_time_30d := 30]

  # day-1 暴露进基线（供 index identity）
  dt[, Sodium := as.numeric(sodium_d1)]
  dt[, eGFR := as.numeric(egfr_d1)]
  dt[, AHF := 1L]

  lab_path <- file.path(mim, "AHF_lab_daily_wide_d1-30.csv")
  .wide_to_lab_csv(wide[stay_id %in% dt$stay_id], "stay_id", lab_path)

  out <- file.path(mim, "D02_AHF_MIMIC_surv30.RData")
  data_imp <- as.data.frame(dt)
  save(data_imp, file = out)
  .message("[MIMIC] n=", nrow(data_imp), " events=", sum(data_imp$survival_30d == 1L, na.rm = TRUE),
           " surv_join=", sum(!is.na(dt$hosp_survival_day)), " -> ", out)
  invisible(list(n = nrow(data_imp), events = sum(data_imp$survival_30d == 1L, na.rm = TRUE), path = out))
}

.prepare_eicu <- function() {
  eicu <- file.path(.data, "eicu")
  b <- .load_baseline(file.path(eicu, "D01_baseline_EICU_firstAll_ext_20261024.RData"))
  b[, subject_id := as.character(ID)]

  cohort <- fread(file.path(eicu, "eICU急性心力衰竭_队列_2685.csv"))
  cohort[, subject_id := as.character(patientunitstayid)]

  wide <- fread(file.path(eicu, "eICU每日30天_钠_eGFR_宽表_2685.csv"))
  # eICU 宽表可能无 patientunitstayid 列名；优先 stay 键
  if (!"patientunitstayid" %in% names(wide)) {
    id_candidates <- c("patientunitstayid", "subject_id", "stay_id", "ID")
    hit <- id_candidates[id_candidates %in% names(wide)][1]
    if (is.na(hit)) stop("eICU 宽表缺少 ID 列", call. = FALSE)
    setnames(wide, hit, "patientunitstayid")
  }
  wide[, subject_id := as.character(patientunitstayid)]

  surv <- fread(file.path(eicu, "eICU_ICU_survival_20261024.csv"))
  surv[, subject_id := as.character(patientunitstayid)]
  surv_keep <- intersect(
    c("subject_id", "hosp_survival_day", "death_within_hosp_28days", "hosp_day", "is_hosp_dead"),
    names(surv)
  )
  s <- unique(surv[, ..surv_keep], by = "subject_id")

  dt <- merge(cohort, b, by = "subject_id", all.x = FALSE, suffixes = c("", "_bl"))
  dt <- merge(dt, s, by = "subject_id", all.x = TRUE)
  dt <- merge(
    dt,
    wide[, .(subject_id, day_of_death, obs_days_na, obs_days_egfr, sodium_d1, egfr_d1)],
    by = "subject_id", all.x = TRUE
  )

  if ("Age" %in% names(dt) && "age" %in% names(dt)) {
    dt[is.na(Age), Age := as.numeric(age)]
  } else if (!"Age" %in% names(dt) && "age" %in% names(dt)) {
    dt[, Age := as.numeric(age)]
  }
  if ("Gender" %in% names(dt) && "gender" %in% names(dt)) {
    dt[is.na(Gender) | as.character(Gender) == "", Gender := fifelse(
      toupper(as.character(gender)) %in% c("M", "MALE"), "Male",
      fifelse(toupper(as.character(gender)) %in% c("F", "FEMALE"), "Female", as.character(gender))
    )]
  } else if (!"Gender" %in% names(dt) && "gender" %in% names(dt)) {
    dt[, Gender := fifelse(
      toupper(as.character(gender)) %in% c("M", "MALE"), "Male",
      fifelse(toupper(as.character(gender)) %in% c("F", "FEMALE"), "Female", as.character(gender))
    )]
  }

  dt[, survival_30d := as.integer(died_30d_hosp == 1L)]
  t_event <- as.numeric(dt$day_of_death)
  t_surv <- as.numeric(dt$hosp_survival_day)
  t_fallback <- if ("hosp_los_day" %in% names(dt)) as.numeric(dt$hosp_los_day) else as.numeric(dt$hosp_day)
  t <- fifelse(is.finite(t_event) & t_event > 0, t_event,
               fifelse(is.finite(t_surv) & t_surv > 0, t_surv, t_fallback))
  t <- fifelse(is.finite(t) & t > 0, t, 30)
  dt[, survival_time_30d := fifelse(
    survival_30d == 1L, pmax(0.01, pmin(30, t)), pmin(30, pmax(0.01, t))
  )]
  dt[is.na(survival_time_30d), survival_time_30d := 30]
  dt[, Sodium := as.numeric(sodium_d1)]
  dt[, eGFR := as.numeric(egfr_d1)]
  dt[, AHF := 1L]

  lab_path <- file.path(eicu, "AHF_lab_daily_wide_d1-30.csv")
  .wide_to_lab_csv(wide[subject_id %in% dt$subject_id], "subject_id", lab_path)

  out <- file.path(eicu, "D02_AHF_EICU_surv30.RData")
  data_imp <- as.data.frame(dt)
  save(data_imp, file = out)
  .message("[eICU] n=", nrow(data_imp), " events=", sum(data_imp$survival_30d == 1L, na.rm = TRUE),
           " surv_join=", sum(!is.na(dt$hosp_survival_day)), " -> ", out)
  invisible(list(n = nrow(data_imp), events = sum(data_imp$survival_30d == 1L, na.rm = TRUE), path = out))
}

.main <- function() {
  m <- .prepare_mimic()
  e <- .prepare_eicu()
  lines <- c(
    "# AHF Trajectory column review",
    "",
    paste0("- Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("- MIMIC analytic N=", m$n, " events=", m$events, " (30d hospital death)"),
    paste0("- eICU analytic N=", e$n, " events=", e$events),
    "",
    "## disease_vars (hard exclusion)",
    "",
    "- `AHF`（队列疾病标签）",
    "- 诊断泄漏列：`dx_codes_hit` / `dx_icd9_hit`（若进入 Table1 候选则排除）",
    "",
    "## exposures",
    "",
    "- `Sodium` / `eGFR`：住院日级中位数轨迹（30 天窗；建模 ≥3 观察日）",
    "- eGFR = CKD-EPI 2021 无种族式（取数端已算）",
    "",
    "## outcome",
    "",
    "- `died_30d_hosp` → `survival_30d` + `survival_time_30d`（院内/30 天窗口）",
    "",
    "## ID",
    "",
    "- MIMIC：`subject_id` = stay_id（基线按真人 subject 合并）",
    "- eICU：`subject_id` = patientunitstayid",
    "",
    "## notes",
    "",
    "- 套路对齐 COPD Prognosis_Trajectory_v2_42558177（JLCM + eICU predictClass + PAMM）",
    "- 仅跑 Sodium、eGFR 两指标"
  )
  writeLines(lines, .review)
  .message("列审阅: ", .review)
  invisible(NULL)
}

.main()
