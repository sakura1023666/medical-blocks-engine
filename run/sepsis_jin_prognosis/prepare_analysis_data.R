#!/usr/bin/env Rscript
###############################################################################
# prepare_analysis_data.R — 脓毒症 Jin 课题：D01+survival+ID → Data/*/D04_dabiao.RData
#
# 用法（Windows R 4.5.1）:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/sepsis_jin_prognosis/prepare_analysis_data.R \
#     --project "//192.168.68.133/02block_result/36_spesis/prediction_41194138"
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(a))) b else a

.parse <- function(args) {
  out <- list(project = NULL)
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--project" && i < length(args)) {
      out$project <- args[[i + 1L]]
      i <- i + 2L
    } else i <- i + 1L
  }
  out
}

.norm_root <- function(p) {
  p <- gsub("\\\\", "/", p)
  if (.Platform$OS.type != "windows") {
    p <- sub("^//192\\.168\\.68\\.133/02block_result", "/mnt/g/02block_result", p)
    p <- sub("^G:/02block_result", "/mnt/g/02block_result", p, ignore.case = TRUE)
  } else {
    p <- sub("^//192\\.168\\.68\\.133/02block_result", "G:/02block_result", p)
  }
  normalizePath(p, winslash = "/", mustWork = TRUE)
}

.age_ok <- function(age) {
  a <- suppressWarnings(as.numeric(age))
  !is.na(a) & a >= 18 & a <= 150
}

.build_mimic <- function(data_root) {
  load(file.path(data_root, "mimic", "D01_baseline_MIMIC_ICU_1023.RData"))
  base <- as.data.frame(baseline)
  surv <- utils::read.csv(file.path(data_root, "mimic", "MIMIC_ICU_survival_1023.csv"),
                          stringsAsFactors = FALSE)
  ids <- utils::read.csv(file.path(data_root, "_cohort_ids", "mimic_icu_sepsis_ids.csv"),
                         stringsAsFactors = FALSE)
  surv$subject_id <- as.character(surv$subject_id)
  surv$stay_id <- as.character(surv$stay_id)
  ids$subject_id <- as.character(ids$subject_id)
  ids$stay_id <- as.character(ids$stay_id)
  base$ID <- as.character(base$ID)

  surv_s <- surv[surv$stay_id %in% ids$stay_id, , drop = FALSE]
  ## dabiao ID = subject_id；本提取一人一行 stay
  m <- merge(base, surv_s, by.x = "ID", by.y = "subject_id", all = FALSE)
  m <- m[.age_ok(m$Age), , drop = FALSE]
  ## 主终点：院内死亡
  m$fustatus <- as.integer(m$is_hosp_dead == 1L)
  ft <- suppressWarnings(as.numeric(m$hosp_survival_day))
  ## 院内随访：死亡用住院生存日；存活用住院天数（下限 1/24 天）
  hosp_day <- suppressWarnings(as.numeric(m$hosp_day))
  m$futime <- ifelse(m$fustatus == 1L, pmax(ft, 1 / 24), pmax(hosp_day, 1 / 24))
  ## 次要时点（探索）
  m$event_30d <- as.integer(!is.na(ft) & ft <= 30 & m$is_dead == 1L)
  m$futime_30d <- pmin(pmax(ft, 1 / 24), 30)
  m$event_365d <- as.integer(!is.na(ft) & ft <= 365 & m$is_dead == 1L)
  m$futime_365d <- pmin(pmax(ft, 1 / 24), 365)
  m$icu_day_num <- suppressWarnings(as.numeric(m$icu_day))
  m <- m[!is.na(m$icu_day_num) & m$icu_day_num >= 1, , drop = FALSE]
  m <- m[!is.na(m$fustatus) & !is.na(m$futime) & m$futime > 0, , drop = FALSE]
  m$Disease_Group <- ifelse(m$fustatus == 1L, "Non-survivor", "Survivor")
  attr(m, "jin_prep") <- list(
    db = "MIMIC", n = nrow(m), n_event = sum(m$fustatus == 1L, na.rm = TRUE)
  )
  m
}

.build_eicu <- function(data_root) {
  load(file.path(data_root, "eicu", "D01_baseline_EICU_firstAll_ext_20261024.RData"))
  base <- as.data.frame(baseline)
  surv <- utils::read.csv(file.path(data_root, "eicu", "eICU_ICU_survival_20261024.csv"),
                          stringsAsFactors = FALSE)
  ids <- utils::read.csv(file.path(data_root, "_cohort_ids", "eicu_sepsis_ids.csv"),
                         stringsAsFactors = FALSE)
  base$ID <- as.character(base$ID)
  surv$patientunitstayid <- as.character(surv$patientunitstayid)
  ids$patientunitstayid <- as.character(ids$patientunitstayid)

  surv_s <- surv[surv$patientunitstayid %in% ids$patientunitstayid, , drop = FALSE]
  m <- merge(base, surv_s, by.x = "ID", by.y = "patientunitstayid", all = FALSE)
  m <- m[.age_ok(m$Age), , drop = FALSE]
  m$fustatus <- as.integer(m$is_hosp_dead == 1L)
  ft <- suppressWarnings(as.numeric(m$hosp_survival_day))
  hosp_day <- suppressWarnings(as.numeric(m$hosp_day))
  m$futime <- ifelse(m$fustatus == 1L, pmax(ft, 1 / 24), pmax(hosp_day, 1 / 24))
  m$event_30d <- as.integer(!is.na(ft) & ft <= 30 & (m$is_hosp_dead == 1L | m$is_icu_dead == 1L))
  ## eICU 无统一 is_dead 时用院内/ICU 死亡近似 30/365
  dead_flag <- as.integer(m$is_hosp_dead == 1L | m$is_icu_dead == 1L)
  m$event_30d <- as.integer(!is.na(ft) & ft <= 30 & dead_flag == 1L)
  m$futime_30d <- pmin(pmax(ft, 1 / 24), 30)
  m$event_365d <- as.integer(!is.na(ft) & ft <= 365 & dead_flag == 1L)
  m$futime_365d <- pmin(pmax(ft, 1 / 24), 365)
  m$icu_day_num <- suppressWarnings(as.numeric(m$icu_day))
  m <- m[!is.na(m$icu_day_num) & m$icu_day_num >= 1, , drop = FALSE]
  m <- m[!is.na(m$fustatus) & !is.na(m$futime) & m$futime > 0, , drop = FALSE]
  m$Disease_Group <- ifelse(m$fustatus == 1L, "Non-survivor", "Survivor")
  attr(m, "jin_prep") <- list(
    db = "eICU", n = nrow(m), n_event = sum(m$fustatus == 1L, na.rm = TRUE)
  )
  m
}

.save_dabiao <- function(df, out_dir, db_lab) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dabiao <- df
  out <- file.path(out_dir, "D04_dabiao.RData")
  save(dabiao, file = out)
  meta <- attr(df, "jin_prep")
  utils::write.csv(
    data.frame(db = db_lab, n = meta$n, n_event = meta$n_event, path = out),
    file.path(out_dir, "_prep_summary.csv"),
    row.names = FALSE
  )
  message(sprintf("[%s] n=%s events=%s -> %s", db_lab, meta$n, meta$n_event, out))
}

main <- function() {
  opts <- .parse(commandArgs(trailingOnly = TRUE))
  if (is.null(opts$project) || !nzchar(opts$project)) {
    stop("请传 --project <prediction_41194138 根目录>", call. = FALSE)
  }
  root <- .norm_root(opts$project)
  data_in <- file.path(root, "data")
  data_out <- file.path(root, "Data")
  if (!dir.exists(data_in)) stop("缺少 data/: ", data_in, call. = FALSE)

  mimic <- .build_mimic(data_in)
  eicu <- .build_eicu(data_in)
  .save_dabiao(mimic, file.path(data_out, "mimic"), "MIMIC")
  .save_dabiao(eicu, file.path(data_out, "eicu"), "eICU")
  message("prepare_analysis_data 完成: ", data_out)
}

main()
