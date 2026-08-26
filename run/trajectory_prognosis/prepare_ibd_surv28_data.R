#!/usr/bin/env Rscript
# =============================================================================
#  IBD 轨迹预后：筛非 IBD + 合并 28 天院内死亡 → D04_rt_IBD_surv28.RData
#
#  用法（仓库根）:
#    Rscript run/trajectory_prognosis/prepare_ibd_surv28_data.R
# =============================================================================

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

.root <- .init_root()
setwd(.root)

.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

.study_root <- file.path(.block_result_root, "28_IBD/Prognosis_Trajectory_38882552")
.data_root <- file.path(.study_root, "data")
.stopif <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)

.stopif(dir.exists(.data_root), paste0("数据根不存在: ", .data_root))

.review_dir <- file.path(.study_root, "Data")
dir.create(.review_dir, recursive = TRUE, showWarnings = FALSE)

.as_chr <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(trimws(x))] <- NA_character_
  x
}

.mimic_prepare <- function() {
  dabiao_path <- file.path(.data_root, "mimic/D04_dabiao_MIMIC.RData")
  prog_path <- file.path(.data_root, "mimic/mimic预后数据-all.csv")
  .stopif(file.exists(dabiao_path), paste0("缺少: ", dabiao_path))
  .stopif(file.exists(prog_path), paste0("缺少: ", prog_path))

  env <- new.env(parent = emptyenv())
  load(dabiao_path, envir = env)
  dabiao <- env$dabiao
  n0 <- nrow(dabiao)

  if (!"IBD_subtype" %in% names(dabiao)) {
    stop("MIMIC dabiao 无 IBD_subtype 列", call. = FALSE)
  }
  keep <- dabiao$IBD_subtype %in% c("CD", "UC")
  n_drop <- sum(!keep)
  dabiao <- dabiao[keep, , drop = FALSE]

  prog <- utils::read.csv(prog_path, check.names = FALSE, stringsAsFactors = FALSE)
  m <- merge(
    dabiao,
    prog,
    by.x = "ID",
    by.y = "subject_id",
    all.x = TRUE,
    sort = FALSE
  )

  if (!"death_within_hosp_28days" %in% names(m)) {
    stop("MIMIC 预后 CSV 无 death_within_hosp_28days", call. = FALSE)
  }

  event <- as.integer(m$death_within_hosp_28days == 1L)
  # 事件优先用 hosp_survival_day；截尾且缺失时用 hosp_day
  t_raw <- as.numeric(m$hosp_survival_day)
  t_alt <- as.numeric(m$hosp_day)
  t_use <- ifelse(is.finite(t_raw), t_raw, t_alt)
  time28 <- pmin(t_use, 28)
  bad <- is.na(event) | !is.finite(time28) | time28 < 0
  n_bad <- sum(bad)
  if (n_bad) {
    message(sprintf("[MIMIC] 剔除结局/时间缺失 %d 人", n_bad))
    m <- m[!bad, , drop = FALSE]
    event <- event[!bad]
    time28 <- time28[!bad]
  }

  # 去掉合并进来的预后原始列，避免泄漏进 Table1
  drop_prog <- setdiff(names(prog), "subject_id")
  drop_prog <- intersect(drop_prog, names(m))
  if (length(drop_prog)) m <- m[, setdiff(names(m), drop_prog), drop = FALSE]

  m$subject_id <- m$ID
  m$survival_28d <- as.integer(event)
  m$survival_time_28d <- as.numeric(time28)
  m$Mortality_28d <- m$survival_28d

  list(
    db = "mimic",
    n0 = n0,
    n_drop_non_ibd = n_drop,
    n_drop_outcome = n_bad,
    n_final = nrow(m),
    n_event = sum(m$survival_28d == 1L, na.rm = TRUE),
    cols = names(m),
    rt = m
  )
}

.eicu_prepare <- function() {
  dabiao_path <- file.path(.data_root, "eicu/D04_dabiao_eICU.RData")
  prog_path <- file.path(.data_root, "eicu/EICU预后数据-all.csv")
  .stopif(file.exists(dabiao_path), paste0("缺少: ", dabiao_path))
  .stopif(file.exists(prog_path), paste0("缺少: ", prog_path))

  env <- new.env(parent = emptyenv())
  load(dabiao_path, envir = env)
  dabiao <- env$dabiao
  n0 <- nrow(dabiao)

  if (!"IBD_subtype" %in% names(dabiao)) {
    stop("eICU dabiao 无 IBD_subtype 列", call. = FALSE)
  }
  keep <- dabiao$IBD_subtype %in% c("CD", "UC")
  n_drop <- sum(!keep)
  dabiao <- dabiao[keep, , drop = FALSE]

  prog <- utils::read.csv(prog_path, check.names = FALSE, stringsAsFactors = FALSE)
  m <- merge(
    dabiao,
    prog,
    by.x = "ID",
    by.y = "patientunitstayid",
    all.x = TRUE,
    sort = FALSE
  )

  status <- tolower(trimws(.as_chr(m$hospdischargestatus)))
  los <- as.numeric(m$hosplosday)
  expired <- !is.na(status) & status == "expired"
  event <- as.integer(expired & is.finite(los) & los <= 28)
  time28 <- pmin(los, 28)
  bad <- is.na(status) | !is.finite(time28) | time28 < 0
  n_bad <- sum(bad)
  if (n_bad) {
    message(sprintf("[eICU] 剔除结局/时间缺失 %d 人", n_bad))
    m <- m[!bad, , drop = FALSE]
    event <- event[!bad]
    time28 <- time28[!bad]
  }

  drop_prog <- setdiff(names(prog), "patientunitstayid")
  drop_prog <- intersect(drop_prog, names(m))
  if (length(drop_prog)) m <- m[, setdiff(names(m), drop_prog), drop = FALSE]

  m$subject_id <- m$ID
  m$survival_28d <- as.integer(event)
  m$survival_time_28d <- as.numeric(time28)
  m$Mortality_28d <- m$survival_28d

  list(
    db = "eicu",
    n0 = n0,
    n_drop_non_ibd = n_drop,
    n_drop_outcome = n_bad,
    n_final = nrow(m),
    n_event = sum(m$survival_28d == 1L, na.rm = TRUE),
    cols = names(m),
    rt = m
  )
}

.write_rt <- function(res) {
  out_path <- file.path(.data_root, res$db, "D04_rt_IBD_surv28.RData")
  rt <- res$rt
  save(rt, file = out_path)
  message(sprintf(
    "[%s] 写出 %s | n=%d | events=%d (%.1f%%) | 排除非IBD=%d | 排除结局缺失=%d",
    toupper(res$db), out_path, res$n_final, res$n_event,
    100 * res$n_event / max(res$n_final, 1), res$n_drop_non_ibd, res$n_drop_outcome
  ))
  invisible(out_path)
}

.write_column_review <- function(mimic_res, eicu_res) {
  all_cols <- sort(unique(c(mimic_res$cols, eicu_res$cols)))
  lines <- c(
    "# IBD 轨迹预后 — 原始/分析列审阅",
    "",
    paste0("生成时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "## 纳排摘要",
    "",
    "| 库 | 原始 n | 排除非 IBD | 排除结局缺失 | 分析 n | 28d 院内死亡 |",
    "|----|--------|------------|--------------|--------|--------------|",
    sprintf(
      "| MIMIC | %d | %d | %d | %d | %d (%.1f%%) |",
      mimic_res$n0, mimic_res$n_drop_non_ibd, mimic_res$n_drop_outcome,
      mimic_res$n_final, mimic_res$n_event,
      100 * mimic_res$n_event / max(mimic_res$n_final, 1)
    ),
    sprintf(
      "| eICU | %d | %d | %d | %d | %d (%.1f%%) |",
      eicu_res$n0, eicu_res$n_drop_non_ibd, eicu_res$n_drop_outcome,
      eicu_res$n_final, eicu_res$n_event,
      100 * eicu_res$n_event / max(eicu_res$n_final, 1)
    ),
    "",
    "## 本课题例外",
    "",
    "- Table1：**不**做 Gate A 两库列交集（两库各自保留本库变量）",
    "- `disease_vars`：仅 `IBD_subtype`（纳排键）；CRP/HSCRP/Albumin **保留**",
    "",
    "## 全列审阅（以合并后分析表为准）",
    "",
    "| 列名 | MIMIC | eICU | 处置 | 理由 |",
    "|------|-------|------|------|------|"
  )

  for (col in all_cols) {
    in_m <- col %in% mimic_res$cols
    in_e <- col %in% eicu_res$cols
    if (identical(col, "IBD_subtype")) {
      action <- "排除"
      reason <- "纳排键；本课题 disease_vars"
    } else if (col %in% c("ID", "subject_id", "DN")) {
      action <- "保留(ID类)"
      reason <- "标识列，不进协变量模型"
    } else if (col %in% c("survival_28d", "survival_time_28d", "Mortality_28d")) {
      action <- "保留(结局)"
      reason <- "28天院内死亡结局/时间"
    } else {
      action <- "保留"
      reason <- "人口学/生命体征/实验室/共病（本课题不因 IBD 排除 CRP）"
    }
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s |",
      col,
      if (in_m) "Y" else "",
      if (in_e) "Y" else "",
      action,
      reason
    ))
  }

  out <- file.path(.review_dir, "_column_review.md")
  writeLines(lines, out, useBytes = TRUE)
  message("写出审阅: ", out)
  invisible(out)
}

.write_attrition_csv <- function(mimic_res, eicu_res) {
  rows <- rbind(
    data.frame(
      database = "MIMIC",
      step = c("raw_dabiao", "keep_IBD_CD_UC", "complete_28d_hosp_mortality"),
      n_remain = c(mimic_res$n0, mimic_res$n0 - mimic_res$n_drop_non_ibd, mimic_res$n_final),
      n_excluded = c(0L, mimic_res$n_drop_non_ibd, mimic_res$n_drop_outcome),
      note = c("D04_dabiao", "IBD_subtype in {CD,UC}", "survival_28d/time defined"),
      stringsAsFactors = FALSE
    ),
    data.frame(
      database = "eICU",
      step = c("raw_dabiao", "keep_IBD_CD_UC", "complete_28d_hosp_mortality"),
      n_remain = c(eicu_res$n0, eicu_res$n0 - eicu_res$n_drop_non_ibd, eicu_res$n_final),
      n_excluded = c(0L, eicu_res$n_drop_non_ibd, eicu_res$n_drop_outcome),
      note = c("D04_dabiao", "IBD_subtype in {CD,UC}", "Expired & los<=28 → event"),
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(.review_dir, "Flowchart_attrition_prepare.csv")
  utils::write.csv(rows, out, row.names = FALSE)
  message("写出纳排: ", out)
  invisible(out)
}

message("=== IBD surv28 数据准备 ===")
message("study_root = ", .study_root)

mimic_res <- .mimic_prepare()
eicu_res <- .eicu_prepare()
.write_rt(mimic_res)
.write_rt(eicu_res)
.write_column_review(mimic_res, eicu_res)
.write_attrition_csv(mimic_res, eicu_res)

message("完成。下一步: Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R --config configs/config_trajectory_prognosis_ibd_batch.R")
