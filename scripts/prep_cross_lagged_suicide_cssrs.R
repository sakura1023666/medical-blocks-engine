#!/usr/bin/env Rscript
# scripts/prep_cross_lagged_suicide_cssrs.R
# Suicide CSSRS × HAMA × HAMD CLPM: outpatient (main) + ward (exploratory) dabiao
#
# Nodes (verbatim source cols; do NOT "fix" HAMA intex spelling):
#   CSSRS_Index <- C_SSRS_Ideation_index_2   (D10_C_SSRS1)  # item2 主动自杀想法
#   CSSRS_1st   <- C_SSRS_Ideation_1st_2     (D10_C_SSRS2)  # item2（非 item1 希望死去）
#   HAMA_Index  <- HAMA_intex_all            (D07_HAMA1)
#   HAMA_1st    <- HAMA_1st_all              (D07_HAMA2)
#   HAMD_Index  <- HAMD_index_all            (D08_HAMD1)
#   HAMD_1st    <- HAMD_1st_all              (D08_HAMD2)
#
# Usage:
#   export CROSS_LAGGED_STUDY_ROOT=...
#   # optional: CROSS_LAGGED_RAW_DIR=... when 01RawData is mirrored separately
#   Rscript scripts/prep_cross_lagged_suicide_cssrs.R

suppressPackageStartupMessages({
  # base R only; no hard deps
})

STUDY <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = "/mnt/e/01block/01Block-new-Final/.superpowers/sdd/study_mirror"
)
raw_override <- Sys.getenv("CROSS_LAGGED_RAW_DIR", unset = "")
raw_dir <- if (nzchar(raw_override)) {
  normalizePath(raw_override, mustWork = TRUE)
} else {
  file.path(STUDY, "data", "RDATA", "RDATA", "01RawData")
}
out_dir <- file.path(STUDY, "data", "harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("STUDY   = ", STUDY)
message("raw_dir = ", raw_dir)
message("out_dir = ", out_dir)
if (!dir.exists(raw_dir)) {
  stop("raw_dir does not exist: ", raw_dir, call. = FALSE)
}

# ---------- helpers ----------
load_one <- function(path) {
  if (!file.exists(path)) stop("missing RData: ", path, call. = FALSE)
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  nms <- ls(e)
  if (!length(nms)) stop("empty RData: ", path, call. = FALSE)
  as.data.frame(get(nms[[1L]], envir = e), stringsAsFactors = FALSE)
}

fix_id <- function(df, drop_patient_cols = TRUE) {
  stopifnot("新编号" %in% names(df))
  df$新编号 <- trimws(as.character(df$新编号))
  df$新编号[df$新编号 %in% c("", "NA", "NaN")] <- NA_character_
  df <- df[!is.na(df$新编号), , drop = FALSE]
  if (anyDuplicated(df$新编号)) {
    df <- df[!duplicated(df$新编号), , drop = FALSE]
  }
  if (isTRUE(drop_patient_cols)) {
    drop <- intersect(names(df), c("患者类别", "患者编号"))
    if (length(drop)) df <- df[, setdiff(names(df), drop), drop = FALSE]
  }
  df
}

safe_merge <- function(left, right, all_x = TRUE) {
  # Default left join on baseline ID spine so scale-only / history-only IDs
  # do not inflate the cohort without 患者类别.
  overlap <- setdiff(intersect(names(left), names(right)), "新编号")
  if (length(overlap)) {
    names(right)[names(right) %in% overlap] <- paste0(overlap, "_dup")
  }
  merge(left, right, by = "新编号", all.x = all_x, all.y = FALSE, sort = FALSE)
}

# C-SSRS Yes/No (A/B) → 0/1；编不成则 NA（listwise 删除）
cssrs_item_01 <- function(x) {
  x <- trimws(as.character(x))
  ifelse(
    x %in% c("Yes ", "Yes", "A", "是", "1"), 1L,
    ifelse(x %in% c("No ", "No", "B", "否", "0"), 0L, NA_integer_)
  )
}

pick_cols <- function(df, id_col = "新编号", keep) {
  miss <- setdiff(keep, names(df))
  if (length(miss)) {
    stop("columns missing in join: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  df[, c(id_col, keep), drop = FALSE]
}

node_cols <- c(
  "HAMD_Index", "HAMD_1st",
  "HAMA_Index", "HAMA_1st",
  "CSSRS_Index", "CSSRS_1st"
)

filter_cohort <- function(df, group_label) {
  steps <- list()
  d <- df
  n0 <- nrow(d)
  steps[[length(steps) + 1L]] <- data.frame(
    step = "has_ID",
    n_remain = n0,
    n_excluded = 0L,
    rule = "non-missing 新编号 after baseline merge",
    stringsAsFactors = FALSE
  )

  # NA == label is NA; data.frame[i] with NA keeps phantom rows — must exclude explicitly
  keep_group <- !is.na(d$patient_group) & d$patient_group == group_label
  d <- d[keep_group, , drop = FALSE]
  n1 <- nrow(d)
  steps[[length(steps) + 1L]] <- data.frame(
    step = paste0("group_", group_label),
    n_remain = n1,
    n_excluded = as.integer(n0 - n1),
    rule = paste0("patient_group == '", group_label, "' (NA group dropped)"),
    stringsAsFactors = FALSE
  )

  # 逐步累加完整：便于报告「每加一个节点要求」掉多少人（仍以最终六节点 listwise 为准）
  remaining <- d
  n_prev <- n1
  for (v in node_cols) {
    ok_v <- !is.na(remaining[[v]])
    remaining <- remaining[ok_v, , drop = FALSE]
    n_now <- nrow(remaining)
    steps[[length(steps) + 1L]] <- data.frame(
      step = paste0("require_", v),
      n_remain = n_now,
      n_excluded = as.integer(n_prev - n_now),
      rule = paste0("non-missing ", v, " (CSSRS = item2 0/1)"),
      stringsAsFactors = FALSE
    )
    n_prev <- n_now
  }

  ok <- stats::complete.cases(d[, node_cols, drop = FALSE])
  d <- d[ok, , drop = FALSE]
  n2 <- nrow(d)
  steps[[length(steps) + 1L]] <- data.frame(
    step = "six_nodes_complete",
    n_remain = n2,
    n_excluded = as.integer(n1 - n2),
    rule = "complete.cases on HAMD/HAMA/CSSRS Index+1st; CSSRS = item2 (主动自杀想法) 0/1",
    stringsAsFactors = FALSE
  )

  list(data = d, attrition = do.call(rbind, steps))
}

# ---------- 1. merge D01–D06 (+ CGI variants) ----------
f_merge <- c(
  "D01_baseline.RData",
  "D02_Disease_history.RData",
  "D03_Disease_current_related.RData",
  "D04_Full_Treatment_related_Information.RData",
  "D05_Lifestyle.RData",
  "D06_CGI.RData",
  "D06_CGI1.RData",
  "D06_CGI12.RData"
)

baseline <- load_one(file.path(raw_dir, "D01_baseline.RData"))
if (!"患者类别" %in% names(baseline) && "患者编号" %in% names(baseline)) {
  names(baseline)[names(baseline) == "患者编号"] <- "患者类别"
}
baseline <- fix_id(baseline, drop_patient_cols = FALSE)

merged <- baseline
for (fn in f_merge[-1L]) {
  path <- file.path(raw_dir, fn)
  if (!file.exists(path)) {
    message("skip missing merge file: ", fn)
    next
  }
  df <- fix_id(load_one(path), drop_patient_cols = TRUE)
  merged <- safe_merge(merged, df)
}

# ---------- 2. Index / 1st scale joins (must use *2 for 1st) ----------
# Index
cssrs_index <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D10_C_SSRS1.RData")), drop_patient_cols = TRUE),
  keep = "C_SSRS_Ideation_index_2"
)
hama_index <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D07_HAMA1.RData")), drop_patient_cols = TRUE),
  keep = "HAMA_intex_all"
)
hamd_index <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D08_HAMD1.RData")), drop_patient_cols = TRUE),
  keep = "HAMD_index_all"
)

# 1st (D*2 files — never reuse Index files)
cssrs_1st <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D10_C_SSRS2.RData")), drop_patient_cols = TRUE),
  keep = "C_SSRS_Ideation_1st_2"
)
hama_1st <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D07_HAMA2.RData")), drop_patient_cols = TRUE),
  keep = "HAMA_1st_all"
)
hamd_1st <- pick_cols(
  fix_id(load_one(file.path(raw_dir, "D08_HAMD2.RData")), drop_patient_cols = TRUE),
  keep = "HAMD_1st_all"
)

dabiao <- merged
for (piece in list(cssrs_index, hama_index, hamd_index, cssrs_1st, hama_1st, hamd_1st)) {
  dabiao <- safe_merge(dabiao, piece)
}

# ---------- 3. rename / encode nodes ----------
dabiao$ID <- dabiao$新编号
dabiao$patient_group <- trimws(as.character(dabiao$患者类别))

dabiao$HAMD_Index <- suppressWarnings(as.numeric(dabiao$HAMD_index_all))
dabiao$HAMD_1st   <- suppressWarnings(as.numeric(dabiao$HAMD_1st_all))
dabiao$HAMA_Index <- suppressWarnings(as.numeric(dabiao$HAMA_intex_all))
dabiao$HAMA_1st   <- suppressWarnings(as.numeric(dabiao$HAMA_1st_all))
dabiao$CSSRS_Index <- cssrs_item_01(dabiao$C_SSRS_Ideation_index_2)
dabiao$CSSRS_1st   <- cssrs_item_01(dabiao$C_SSRS_Ideation_1st_2)

# drop empty-ID rows for attrition start
dabiao <- dabiao[!is.na(dabiao$ID) & nzchar(dabiao$ID), , drop = FALSE]

req <- c("ID", "patient_group", node_cols)
miss_req <- setdiff(req, names(dabiao))
if (length(miss_req)) {
  stop("dabiao missing required columns: ", paste(miss_req, collapse = ", "), call. = FALSE)
}

# ---------- 4. cohort filters ----------
out_f <- filter_cohort(dabiao, "门诊入组")
ward_f <- filter_cohort(dabiao, "病房入组")

dabiao_out <- out_f$data
dabiao_ward <- ward_f$data

# ---------- 5. write products ----------
attr_out_path <- file.path(out_dir, "attrition_outpatient.csv")
attr_ward_path <- file.path(out_dir, "attrition_ward.csv")
utils::write.csv(out_f$attrition, attr_out_path, row.names = FALSE, fileEncoding = "UTF-8")
utils::write.csv(ward_f$attrition, attr_ward_path, row.names = FALSE, fileEncoding = "UTF-8")

dabiao <- dabiao_out
save(dabiao, file = file.path(out_dir, "D04_outpatient_clpm.RData"))
dabiao <- dabiao_ward
save(dabiao, file = file.path(out_dir, "D04_ward_clpm.RData"))

# QC
qc_row <- function(label, d, attr_tbl) {
  n_complete <- if (nrow(attr_tbl)) {
    attr_tbl$n_remain[attr_tbl$step == "six_nodes_complete"][1L]
  } else {
    NA_integer_
  }
  data.frame(
    cohort = label,
    n_has_id = attr_tbl$n_remain[attr_tbl$step == "has_ID"][1L],
    n_group = attr_tbl$n_remain[grepl("^group_", attr_tbl$step)][1L],
    n_nodes_complete = n_complete,
    mean_HAMD_Index = if (nrow(d)) mean(d$HAMD_Index, na.rm = TRUE) else NA_real_,
    mean_HAMD_1st = if (nrow(d)) mean(d$HAMD_1st, na.rm = TRUE) else NA_real_,
    mean_HAMA_Index = if (nrow(d)) mean(d$HAMA_Index, na.rm = TRUE) else NA_real_,
    mean_HAMA_1st = if (nrow(d)) mean(d$HAMA_1st, na.rm = TRUE) else NA_real_,
    cssrs_index_yes = if (nrow(d)) sum(d$CSSRS_Index == 1L, na.rm = TRUE) else 0L,
    cssrs_1st_yes = if (nrow(d)) sum(d$CSSRS_1st == 1L, na.rm = TRUE) else 0L,
    hamd_index_eq_1st = if (nrow(d)) {
      isTRUE(all.equal(mean(d$HAMD_Index), mean(d$HAMD_1st)))
    } else {
      NA
    },
    stringsAsFactors = FALSE
  )
}

prep_qc <- rbind(
  qc_row("门诊入组", dabiao_out, out_f$attrition),
  qc_row("病房入组", dabiao_ward, ward_f$attrition)
)
qc_path <- file.path(out_dir, "prep_qc.csv")
utils::write.csv(prep_qc, qc_path, row.names = FALSE, fileEncoding = "UTF-8")

message("\n========== prep_qc ==========")
print(prep_qc, row.names = FALSE)
message("\nWrote:")
message("  ", file.path(out_dir, "D04_outpatient_clpm.RData"), " n=", nrow(dabiao_out))
message("  ", file.path(out_dir, "D04_ward_clpm.RData"), " n=", nrow(dabiao_ward))
message("  ", attr_out_path)
message("  ", attr_ward_path)
message("  ", qc_path)

if (isTRUE(prep_qc$n_nodes_complete[prep_qc$cohort == "门诊入组"] > 0) &&
    isTRUE(prep_qc$hamd_index_eq_1st[prep_qc$cohort == "门诊入组"] == FALSE)) {
  message("\nSanity OK: outpatient n_nodes_complete > 0; HAMD Index vs 1st means differ.")
} else {
  warning(
    "Sanity check failed: expect outpatient n_nodes_complete > 0 and HAMD means differ.",
    call. = FALSE
  )
}
