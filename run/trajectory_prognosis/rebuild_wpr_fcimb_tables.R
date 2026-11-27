#!/usr/bin/env Rscript
# WPR summary Tables → fcimb 角色 + 引擎标准三线表（Times New Roman）
# Table 1 = 双库共有基线变量全集（Derivation | Validation）
#   Rscript run/trajectory_prognosis/rebuild_wpr_fcimb_tables.R

suppressPackageStartupMessages({ options(warn = 1) })
.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
source("R/utils.R")
source("R/trajectory_paper_tables.R")
source("R/baseline_dictionary_labels.R")
source("R/pv2_table1_smd.R")
suppressPackageStartupMessages({
  library(dplyr)
  library(gtsummary)
  library(survival)
  library(data.table)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

# 双库强对齐调整集（UV→VIF + 文献 + 双库可得性定稿；eICU 无 LymphocytePercent）
# S9/S10/S11 / PAMM / JLCM 共用；Methods 须写同一选型路径
.shared_covs <- c("CHARLSON", "Age", "RDW", "NeutrophilCount")
.shared_covs_methods_note <- paste0(
  "Adjusted covariates were selected by univariate screening followed by VIF ",
  "multicollinearity screening, then finalized with COPD ICU prognostic literature ",
  "and dual-database availability as a single shared set: ",
  paste(.shared_covs, collapse = ", "),
  " (LymphocytePercent excluded because unavailable in eICU)."
)

ix <- "WPR"
proj <- "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
if (!dir.exists(proj)) proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
tab_out <- file.path(ix_root, "summary_results/Tables")
dir.create(tab_out, recursive = TRUE, showWarnings = FALSE)

# 旧 xlsx 挪出交付
.ws <- file.path(ix_root, "summary_results_delivery_workspace")
dir.create(.ws, showWarnings = FALSE)
.arch <- file.path(.ws, paste0("tables_archive_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir.create(.arch, showWarnings = FALSE)
old <- list.files(tab_out, pattern = "\\.(xlsx|csv|md)$", full.names = TRUE)
# 不归档子目录
old <- old[file.info(old)$isdir %in% FALSE]
if (length(old)) {
  file.rename(old, file.path(.arch, basename(old)))
  cli::cli_alert_info("归档 {length(old)} → {.file {basename(.arch)}}")
}

.fmt_hr <- function(hr, lo, hi, digits = 2) {
  if (!is.finite(hr)) return("NE")
  sprintf(paste0("%.", digits, "f (%.", digits, "f\u2013%.", digits, "f)"), hr, lo, hi)
}
.event01 <- function(x) {
  if (is.numeric(x)) return(as.integer(x == 1))
  xc <- tolower(trimws(as.character(x)))
  as.integer(xc %in% c("1", "yes", "true", "non-survivor", "dead", "death", "expired"))
}
.load_imp <- function(db) {
  ck <- file.path(proj, "checkpoints/by_index", ix, db, "imputation.rds")
  d <- readRDS(ck)$ctx$data$imputed
  d$subject_id <- as.character(d$subject_id)
  d
}
.write_one <- function(df, path, title, footnotes = NULL, section_titles = NULL, level_row_idx = NULL) {
  sci_xlsx_single_header_booktabs(
    filepath = path,
    title = title,
    df_body = df,
    footnotes = footnotes,
    section_titles = section_titles,
    level_row_idx = level_row_idx
  )
  cli::cli_alert_success(basename(path))
}
.lab <- function(x) {
  out <- if (exists("pipeline_display_label", mode = "function"))
    pipeline_display_label(x)
  else gsub("_", " ", x, fixed = TRUE)
  # 字典驼峰列名（NeutrophilCount / CalciumTotal）拆成可读词
  if (!grepl(" ", out, fixed = TRUE) && grepl("[a-z][A-Z]", out))
    out <- gsub("([a-z])([A-Z])", "\\1 \\2", out)
  out
}

# ═══════════════════════════════════════════════════════════════════════════
# Table 1：双库共有基线全集（三线表）
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table 1 · dual shared baseline (SCI booktabs)")
.m <- .load_imp("mimic")
.e <- .load_imp("eicu")
cat_m <- trimws(readLines(file.path(ix_root, "mimic/step08_baseline_binary/categorical_vars.txt"), warn = FALSE))
con_m <- trimws(readLines(file.path(ix_root, "mimic/step08_baseline_binary/continuous_vars.txt"), warn = FALSE))
cat_e <- trimws(readLines(file.path(ix_root, "eicu/step08_baseline_binary/categorical_vars.txt"), warn = FALSE))
con_e <- trimws(readLines(file.path(ix_root, "eicu/step08_baseline_binary/continuous_vars.txt"), warn = FALSE))
cat_vars <- intersect(cat_m, cat_e)
con_vars <- intersect(con_m, con_e)
# 结局时间不进基线池；暴露 WPR 不进中间变量池，单独贴在表末
drop_bl <- c("survival_28d", "survival_time_28d", "surv_event", "surv_time", ix, "WPR")
cat_vars <- setdiff(cat_vars, drop_bl)
con_vars <- setdiff(con_vars, drop_bl)
.has_wpr <- ("WPR" %in% names(.m) && "WPR" %in% names(.e)) ||
  (ix %in% names(.m) && ix %in% names(.e))
.wpr_col <- if ("WPR" %in% names(.m) && "WPR" %in% names(.e)) "WPR" else ix
# 仅保留双库都真实存在的列
cat_vars <- cat_vars[cat_vars %in% names(.m) & cat_vars %in% names(.e)]
con_vars <- con_vars[con_vars %in% names(.m) & con_vars %in% names(.e)]
cli::cli_alert_info("共享分类 {length(cat_vars)} + 连续 {length(con_vars)}")

.prep <- function(d, cohort) {
  d <- as.data.frame(d)
  d$.cohort <- cohort
  for (v in cat_vars) {
    if (!v %in% names(d)) next
    d[[v]] <- factor(as.character(d[[v]]))
  }
  for (v in con_vars) {
    if (!v %in% names(d)) next
    d[[v]] <- suppressWarnings(as.numeric(d[[v]]))
  }
  if (.has_wpr && .wpr_col %in% names(d))
    d[[.wpr_col]] <- suppressWarnings(as.numeric(d[[.wpr_col]]))
  d$event28 <- .event01(d$survival_28d)
  d$Mortality_28d <- factor(
    ifelse(d$event28 == 1L, "Yes", "No"),
    levels = c("No", "Yes")
  )
  d
}
dm <- .prep(.m, "Derivation (MIMIC-IV)")
de <- .prep(.e, "Validation (eICU)")
keep_cols <- unique(c(".cohort", cat_vars, con_vars, "Mortality_28d",
                      if (.has_wpr) .wpr_col else character(0)))
both <- dplyr::bind_rows(
  dm[, intersect(keep_cols, names(dm)), drop = FALSE],
  de[, intersect(keep_cols, names(de)), drop = FALSE]
)
both$.cohort <- factor(both$.cohort, levels = c("Derivation (MIMIC-IV)", "Validation (eICU)"))

# 小节：人口学 / 生命体征 / 实验室 / 评分 / 共病 / 干预 / 结局 / 暴露(末)
sec_def <- .default_table1_sections()
sec_use <- list(
  "Demographics" = intersect(sec_def[["Demographics"]], c(cat_vars, con_vars)),
  "Vital Signs" = intersect(sec_def[["Vital Signs"]], c(cat_vars, con_vars)),
  "Laboratory Tests" = intersect(sec_def[["Laboratory Tests"]], c(cat_vars, con_vars)),
  "Clinical Scores" = intersect(
    c(sec_def[["Clinical Scores"]], "PLR", "Ponderal"),
    c(cat_vars, con_vars)
  ),
  "Comorbidities" = intersect(sec_def[["Comorbidities"]], c(cat_vars, con_vars)),
  "Interventions and Hospital Course" = intersect(
    c(sec_def[["Interventions and Hospital Course"]], "CRRT"),
    c(cat_vars, con_vars)
  ),
  "Outcomes" = "Mortality_28d",
  "Exposure" = if (.has_wpr) .wpr_col else character(0)
)
# 去掉空小节
sec_use <- sec_use[vapply(sec_use, length, 1L) > 0L]
# 未归入小节的共享变量补到最合适位置之前：挂到 Laboratory / Demographics 之后的 Other
assigned <- unique(unlist(sec_use, use.names = FALSE))
rest <- setdiff(c(cat_vars, con_vars), assigned)
if (length(rest)) {
  cli::cli_alert_info("未归类变量补入 Other clinical variables: {paste(rest, collapse=', ')}")
  sec_use <- c(
    sec_use[names(sec_use) != "Outcomes" & names(sec_use) != "Exposure"],
    list("Other clinical variables" = rest),
    sec_use[intersect(c("Outcomes", "Exposure"), names(sec_use))]
  )
}
vars_all <- unique(unlist(sec_use, use.names = FALSE))
vars_all <- vars_all[vars_all %in% names(both)]
# 按小节顺序展开
vars_ord <- unique(unlist(sec_use, use.names = FALSE))
vars_ord <- vars_ord[vars_ord %in% vars_all]

# 展示名 + 数据字典单位（Pretty,unit；无空格）
.unit_ov <- baseline_dictionary_unit_label_map(.root, vars_ord)
label_list <- setNames(lapply(vars_ord, function(v) {
  if (identical(v, "Mortality_28d")) return("28-day in-hospital mortality")
  disp <- .lab(v)
  u_lab <- .unit_ov[[v]]
  if (!is.null(u_lab) && nzchar(u_lab) && grepl(",", u_lab, fixed = TRUE)) {
    u <- sub("^[^,]*,\\s*", "", u_lab)
    if (nzchar(u) && !grepl(paste0(",", u, "$"), disp))
      return(paste0(disp, ",", u))
  }
  disp
}), vars_ord)

type_list <- list()
for (v in intersect(con_vars, vars_ord)) type_list[[v]] <- "continuous"
for (v in intersect(c(cat_vars, "Mortality_28d"), vars_ord)) type_list[[v]] <- "categorical"
if (.has_wpr && .wpr_col %in% vars_ord) type_list[[.wpr_col]] <- "continuous"

# 二分类共病/干预/结局：统一 Yes/No，两档都保留（不作 dichotomous Yes-only）
.dich_vars <- intersect(
  c(
    "Hypertension", "Diabetes", "T1DM", "T2DM", "Heart_Failure",
    "Myocardial_Infarction", "Stroke", "CKD", "Acute_Renal_Failure",
    "Malignant_Tumor", "Hyperlipidemia", "Liver_cirrhosis", "Hepatitis",
    "Pneumonia", "Ventilation", "CRRT", "Mortality_28d"
  ),
  vars_ord
)
for (v in .dich_vars) {
  type_list[[v]] <- "categorical"
  lv <- levels(factor(both[[v]]))
  pos <- intersect(c("Yes", "1", "TRUE", "True"), as.character(lv))
  if (length(pos) || any(as.character(both[[v]]) %in% c("Yes", "1", "TRUE", "True", "No", "0"))) {
    both[[v]] <- factor(
      ifelse(as.character(both[[v]]) %in% c("Yes", "1", "TRUE", "True"), "Yes", "No"),
      levels = c("No", "Yes")
    )
  }
}

tbl1 <- both %>%
  dplyr::select(dplyr::all_of(c(".cohort", vars_ord))) %>%
  tbl_summary(
    by = .cohort,
    include = dplyr::all_of(vars_ord),
    label = label_list,
    type = type_list,
    statistic = list(
      all_continuous() ~ "{median} ({p25}, {p75})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(
      all_continuous() ~ 2,
      all_categorical() ~ c(0, 1)
    ),
    missing = "no"
  ) %>%
  add_p(
    test = list(
      all_continuous() ~ "wilcox.test",
      all_categorical() ~ "chisq.test"
    ),
    pvalue_fun = function(x) {
      if (exists("fmt_pval", mode = "function")) fmt_pval(x) else style_pvalue(x, digits = 3)
    }
  ) %>%
  modify_header(
    label ~ "**Characteristic**",
    stat_1 ~ "**Derivation (MIMIC-IV)**\nN = {n}",
    stat_2 ~ "**Validation (eICU)**\nN = {n}",
    p.value ~ "**P value**"
  )

# 与 baseline_binary 同路径：as.data.frame(tbl) + section insert + guan-style
tbl_df <- as.data.frame(tbl1)
section_rows <- table1_section_insert_rows_from_gtsummary(tbl1, sec_use)
built <- table1_build_display_df(
  tbl_df,
  section_insert_rows = section_rows,
  gtsummary_tbl = tbl1,
  center_first_col_values = character(0)
)
t1_path <- file.path(
  tab_out,
  "Table 1. Baseline characteristics of the derivation and validation cohorts.xlsx"
)
write_table1_xlsx_guan_style(
  tbl_df = tbl_df,
  filepath = t1_path,
  title = "Table 1. Baseline characteristics of the derivation and validation cohorts",
  footnotes = c(
    table1_baseline_xlsx_footnotes(weighted = FALSE),
    "Aligned with fcimb-16-1871653 main-text Table 1 (Derivation = MIMIC-IV; Validation = eICU).",
    sprintf(
      "Variables = intersection of baseline pools in both databases (categorical n=%s; continuous n=%s).",
      length(cat_vars), length(con_vars)
    ),
    "Section headers: Demographics, Vital Signs, Laboratory Tests, Clinical Scores, Comorbidities, Interventions and Hospital Course, Outcomes, Exposure.",
    "Continuous labels append units from the baseline dictionary (e.g. Age,years; Hemoglobin,g/dL).",
    "Dichotomous covariates show both No and Yes levels as n (%).",
    sprintf("Last section = Exposure (%s).", .lab(.wpr_col))
  ),
  prebuilt = built
)
cli::cli_alert_success(basename(t1_path))
cli::cli_alert_info(
  "小节: {paste(names(sec_use), collapse=' | ')}; level rows={length(built$level_row_idx)}"
)
# ═══════════════════════════════════════════════════════════════════════════
# S1 / S2：Included vs Excluded + SMD（列角色对齐 data sheet；行序对齐 Table 1）
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table S1/S2 Included vs Excluded")

.med_iqr_br <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (!length(x)) return("")
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), names = FALSE, na.rm = TRUE)
  sprintf("%.2f [%.2f, %.2f]", q[2], q[1], q[3])
}
.n_pct2 <- function(k, n) {
  if (!is.finite(n) || n <= 0) return("")
  sprintf("%s (%.2f%%)", format(as.integer(k), big.mark = ",", scientific = FALSE), 100 * k / n)
}
.yes01 <- function(x) {
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x) || is.integer(x)) return(as.integer(as.numeric(x) == 1))
  xc <- tolower(trimws(as.character(x)))
  as.integer(xc %in% c("1", "yes", "true"))
}
.gender_t1 <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(xc))
  out[xc %in% c("f", "female")] <- "Female"
  out[xc %in% c("m", "male")] <- "Male"
  factor(out, levels = c("Female", "Male"))
}
.race_t1 <- function(x) {
  xc <- trimws(as.character(x))
  low <- tolower(xc)
  out <- rep(NA_character_, length(xc))
  out[low %in% c("asian")] <- "Asian"
  out[low %in% c("black", "black/african american", "african american")] <- "Black"
  out[low %in% c("hispanic", "hispanic/latino", "latino")] <- "Hispanic"
  out[low %in% c("other")] <- "Other"
  out[low %in% c("white", "caucasian")] <- "White"
  factor(out, levels = c("Asian", "Black", "Hispanic", "Other", "White"))
}
.resolve_col <- function(d, candidates) {
  hit <- candidates[candidates %in% names(d)]
  if (length(hit)) hit[[1L]] else NA_character_
}
.lab_with_unit <- function(v) {
  disp <- .lab(v)
  u_lab <- baseline_dictionary_unit_label_map(.root, v)[[v]]
  if (!is.null(u_lab) && nzchar(u_lab) && grepl(",", u_lab, fixed = TRUE)) {
    u <- sub("^[^,]*,\\s*", "", u_lab)
    if (nzchar(u) && !grepl(paste0(",", u, "$"), disp))
      return(paste0(disp, ",", u))
  }
  disp
}
.build_incl_excl_smd <- function(db) {
  ck <- file.path(proj, "checkpoints/by_index", ix, db, "imputation.rds")
  if (!file.exists(ck))
    ck <- file.path(proj, "checkpoints/by_index", paste0("\u3010success\u3011", ix), db, "imputation.rds")
  imp <- readRDS(ck)
  raw <- as.data.frame(imp$ctx$data$raw, stringsAsFactors = FALSE)
  inc <- as.data.frame(imp$ctx$data$imputed, stringsAsFactors = FALSE)
  raw$subject_id <- as.character(raw$subject_id)
  inc$subject_id <- as.character(inc$subject_id)
  # WPR：优先 imputed，回填 raw
  .wpr_src <- .resolve_col(inc, c("WPR", ix))
  if (!is.na(.wpr_src)) {
    raw$WPR <- NA_real_
    raw$WPR[match(inc$subject_id, raw$subject_id)] <- suppressWarnings(as.numeric(inc[[.wpr_src]]))
  }
  if (!"WPR" %in% names(raw) || all(is.na(raw$WPR))) {
    w0 <- .resolve_col(raw, c("WPR", ix))
    if (!is.na(w0)) raw$WPR <- suppressWarnings(as.numeric(raw[[w0]]))
  }
  # 列别名对齐 Table 1
  alias <- list(
    NeutrophilCount = c("NeutrophilCount", "Neutrophil_Count"),
    Lymphocytes = c("Lymphocytes", "Lymphocyte_Count"),
    CalciumTotal = c("CalciumTotal", "Calcium_Total"),
    AnionGap = c("AnionGap", "Anion_Gap"),
    PlateletCount = c("PlateletCount", "Platelet_Count"),
    BUN = c("BUN", "UreaNitrogen", "Urea_Nitrogen"),
    Heart_Failure = c("Heart_Failure", "CHF"),
    Malignant_Tumor = c("Malignant_Tumor", "Cancer"),
    Liver_cirrhosis = c("Liver_cirrhosis", "Liver_Cirrhosis"),
    Myocardial_Infarction = c("Myocardial_Infarction", "MI"),
    Acute_Renal_Failure = c("Acute_Renal_Failure", "AKI")
  )
  for (nm in names(alias)) {
    if (!nm %in% names(raw)) {
      src <- .resolve_col(raw, alias[[nm]])
      if (!is.na(src)) raw[[nm]] <- raw[[src]]
    }
  }
  # 仅 imputed 有的衍生列（PLR/Ponderal 等）回填到 Included 行
  for (v in c("PLR", "Ponderal", "BUN", "WPR")) {
    if (!v %in% names(inc)) next
    if (!v %in% names(raw)) raw[[v]] <- NA_real_
    idx <- match(inc$subject_id, raw$subject_id)
    ok <- !is.na(idx)
    raw[[v]][idx[ok]] <- suppressWarnings(as.numeric(inc[[v]][ok]))
  }

  raw$.group <- factor(
    ifelse(raw$subject_id %in% inc$subject_id, "Included", "Excluded"),
    levels = c("Excluded", "Included")
  )
  raw$Gender_f <- .gender_t1(raw$Gender)
  raw$Race_f <- .race_t1(raw$Race)
  if ("SIRS" %in% names(raw)) {
    raw$SIRS_f <- factor(as.character(raw$SIRS), levels = as.character(0:4))
  }
  .dich <- c(
    "Hypertension", "Diabetes", "T1DM", "T2DM", "Heart_Failure",
    "Myocardial_Infarction", "Stroke", "CKD", "Acute_Renal_Failure",
    "Malignant_Tumor", "Hyperlipidemia", "Liver_cirrhosis", "Hepatitis",
    "Pneumonia", "CRRT", "Ventilation"
  )
  for (v in .dich) {
    if (v %in% names(raw)) {
      raw[[v]] <- factor(
        ifelse(.yes01(raw[[v]]) == 1L, "Yes", "No"),
        levels = c("No", "Yes")
      )
    }
  }
  raw$Mortality_28d <- factor(
    ifelse(.yes01(raw$survival_28d) == 1L, "Yes", "No"),
    levels = c("No", "Yes")
  )

  n_ex <- sum(raw$.group == "Excluded")
  n_in <- sum(raw$.group == "Included")
  g_ex <- raw[raw$.group == "Excluded", , drop = FALSE]
  g_in <- raw[raw$.group == "Included", , drop = FALSE]

  rows <- list()
  level_idx <- integer(0)
  section_names <- character(0)
  add <- function(item, ex = "", inc = "", smd = "", level = FALSE) {
    rows[[length(rows) + 1L]] <<- c(item, ex, inc, smd)
    if (isTRUE(level)) level_idx <<- c(level_idx, length(rows))
  }
  add_sec <- function(lab) {
    section_names <<- c(section_names, lab)
    add(lab, "", "", "")
  }
  add_cont <- function(var, lab = NULL) {
    if (!var %in% names(raw)) return(invisible(NULL))
    if (is.null(lab)) lab <- .lab_with_unit(var)
    smd <- pv2_smd_continuous(g_ex[[var]], g_in[[var]])
    add(lab, .med_iqr_br(g_ex[[var]]), .med_iqr_br(g_in[[var]]), pv2_fmt_smd(abs(smd)))
  }
  add_cat <- function(var, lab, levels, smd_on = levels[[1L]], data_var = var) {
    if (!data_var %in% names(raw)) return(invisible(NULL))
    add(lab, "", "", "")
    for (lv in levels) {
      k0 <- sum(as.character(g_ex[[data_var]]) == lv, na.rm = TRUE)
      n0 <- sum(!is.na(g_ex[[data_var]]))
      k1 <- sum(as.character(g_in[[data_var]]) == lv, na.rm = TRUE)
      n1 <- sum(!is.na(g_in[[data_var]]))
      smd <- if (identical(lv, smd_on)) {
        pv2_fmt_smd(abs(pv2_smd_binary(g_ex[[data_var]], g_in[[data_var]], lv)))
      } else ""
      add(lv, .n_pct2(k0, n0), .n_pct2(k1, n1), smd, level = TRUE)
    }
  }
  add_ny <- function(var, lab = NULL) {
    if (!var %in% names(raw)) return(invisible(NULL))
    if (is.null(lab)) lab <- .lab(var)
    add_cat(var, lab, c("No", "Yes"), smd_on = "Yes")
  }

  # —— 行序严格跟 Table 1 ——
  add_sec("Demographics")
  add_cont("Age")
  add_cat("Gender", "Gender", c("Female", "Male"), smd_on = "Female", data_var = "Gender_f")
  add_cat("Race", "Race", c("Asian", "Black", "Hispanic", "Other", "White"),
          smd_on = "White", data_var = "Race_f")
  add_cont("Weight"); add_cont("Height"); add_cont("BMI")

  add_sec("Vital Signs")
  add_cont("HR"); add_cont("PP"); add_cont("RR"); add_cont("SpO2")
  add_cont("Temperature"); add_cont("NBPS"); add_cont("NBPD"); add_cont("NBPM")

  add_sec("Laboratory Tests")
  for (v in c(
    "RBC", "Hemoglobin", "Hematocrit", "NeutrophilCount", "Lymphocytes", "RDW",
    "BUN", "Creatinine", "Sodium", "Potassium", "Chloride", "CalciumTotal",
    "AnionGap", "Glucose"
  )) add_cont(v)

  add_sec("Clinical Scores")
  add_cont("APSIII"); add_cont("OASIS")
  add_cat("SIRS", .lab_with_unit("SIRS"), as.character(0:4), smd_on = "0", data_var = "SIRS_f")
  add_cont("SOFA"); add_cont("CHARLSON"); add_cont("PLR"); add_cont("Ponderal")

  add_sec("Comorbidities")
  for (v in c(
    "Hypertension", "Diabetes", "T1DM", "T2DM", "Heart_Failure",
    "Myocardial_Infarction", "Stroke", "CKD", "Acute_Renal_Failure",
    "Malignant_Tumor", "Hyperlipidemia", "Liver_cirrhosis", "Hepatitis",
    "Pneumonia", "CRRT"
  )) add_ny(v)

  add_sec("Interventions and Hospital Course")
  add_ny("Ventilation")

  add_sec("Outcomes")
  add_ny("Mortality_28d", "28-day in-hospital mortality")

  add_sec("Exposure")
  add_cont("WPR", "WPR")

  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c(
    "Items",
    sprintf("Excluded (n=%s)", format(n_ex, big.mark = ",", scientific = FALSE)),
    sprintf("Included (n=%s)", format(n_in, big.mark = ",", scientific = FALSE)),
    "SMD"
  )
  list(
    body = body,
    level_row_idx = level_idx,
    section_titles = section_names,
    n_ex = n_ex,
    n_in = n_in
  )
}

.s1 <- .build_incl_excl_smd("mimic")
.write_one(
  .s1$body,
  file.path(tab_out, "Table S1. Included vs excluded baseline comparison in the derivation cohort.xlsx"),
  "Table S1. Included vs excluded baseline comparison in the derivation cohort",
  footnotes = c(
    "Columns follow fcimb data sheet Table S1 (Excluded | Included | SMD).",
    "Row order and section headers align with main-text Table 1.",
    sprintf(
      "Derivation (MIMIC-IV): Excluded n=%s; Included n=%s (analysis set after missingness filter / imputation).",
      .s1$n_ex, .s1$n_in
    ),
    "Continuous: median [IQR]. Categorical: n (%). SMD = absolute standardized mean difference (on the first listed level for multi-level variables; Yes for dichotomous)."
  ),
  section_titles = .s1$section_titles,
  level_row_idx = .s1$level_row_idx
)

.s2 <- .build_incl_excl_smd("eicu")
.write_one(
  .s2$body,
  file.path(tab_out, "Table S2. Included vs excluded baseline comparison in the validation cohort.xlsx"),
  "Table S2. Included vs excluded baseline comparison in the validation cohort",
  footnotes = c(
    "Columns follow fcimb data sheet Table S2 (Excluded | Included | SMD).",
    "Row order and section headers align with main-text Table 1.",
    sprintf(
      "Validation (eICU): Excluded n=%s; Included n=%s (analysis set after missingness filter / imputation).",
      .s2$n_ex, .s2$n_in
    ),
    "Continuous: median [IQR]. Categorical: n (%). SMD = absolute standardized mean difference (on the first listed level for multi-level variables; Yes for dichotomous)."
  ),
  section_titles = .s2$section_titles,
  level_row_idx = .s2$level_row_idx
)

# ═══════════════════════════════════════════════════════════════════════════
# S3–S6：对齐 data sheet 单行表头
#   S3/S4 = 发现集 JLCM ng=1..5
#   S5/S6 = 外验：发现集参数 predictClass（非独立重拟合；LL/BIC 记 —）
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table S3–S6 (data-sheet layout)")

.jlcm_models_load <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  list(models = e$models_list_with_cov, model_data = e$model_data_final)
}
.fmt_ll <- function(x) {
  x <- suppressWarnings(as.numeric(x)[1L])
  if (!is.finite(x)) return("\u2014")
  if (abs(x - round(x)) < 1e-6) as.character(as.integer(round(x))) else sprintf("%.1f", x)
}
.fmt_bic <- function(x) {
  x <- suppressWarnings(as.numeric(x)[1L])
  if (!is.finite(x)) return("\u2014")
  sprintf("%.1f", x)
}
.jlcm_sheet_s3 <- function(models_list, max_ng = 5L) {
  body <- trajectory_build_table2_from_models(models_list, max_classes = max_ng)
  body <- body[as.integer(body[["No. of classes"]]) <= max_ng, , drop = FALSE]
  out <- data.frame(
    `No. of classes` = body[["No. of classes"]],
    `Log likelihood` = vapply(body[["Log likelihood"]], function(z) {
      # body 已是字符串；保持
      as.character(z)
    }, character(1)),
    BIC = body[["BIC"]],
    Entropy = body[["Entropy"]],
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  # 文献单元格更接近裸数字：重取模型写 LL/BIC
  for (k in seq_len(max_ng)) out[[paste0("Class ", k)]] <- ""
  for (i in seq_len(nrow(out))) {
    ng <- as.integer(out[["No. of classes"]][i])
    m <- trajectory_unwrap_jointlcmm(models_list[[paste0("m", ng)]])
    out[["Log likelihood"]][i] <- .fmt_ll(m$loglik)
    out[["BIC"]][i] <- .fmt_bic(m$BIC)
    out[["Entropy"]][i] <- sprintf("%.6f", trajectory_jlcm_entropy(m))
    props <- trajectory_jlcm_class_props_pct(m, max_classes = max_ng)
    for (k in seq_len(max_ng)) {
      pk <- props[k]
      out[[paste0("Class ", k)]][i] <- if (nzchar(pk)) pk else ""
    }
  }
  out
}
.jlcm_sheet_s4 <- function(models_list, max_ng = 5L) {
  rows <- list()
  for (ng in seq_len(max_ng)) {
    nm <- paste0("m", ng)
    if (!nm %in% names(models_list)) next
    m <- trajectory_unwrap_jointlcmm(models_list[[nm]])
    pp <- as.data.frame(m$pprob)
    py <- grep("^probYT", names(pp), value = TRUE)
    if (!length(py)) py <- grep("^prob", names(pp), value = TRUE)
    probs <- as.matrix(pp[, py, drop = FALSE])
    cls <- as.integer(pp$class)
    row <- data.frame(`No. of classes` = ng, check.names = FALSE, stringsAsFactors = FALSE)
    for (k in seq_len(max_ng)) {
      if (k > ng) {
        row[[paste0("Class ", k)]] <- ""
      } else {
        idx <- which(cls == k)
        row[[paste0("Class ", k)]] <- if (!length(idx) || k > ncol(probs)) ""
        else sprintf("%.6f", mean(probs[idx, k], na.rm = TRUE))
      }
    }
    rows[[length(rows) + 1L]] <- row
  }
  dplyr::bind_rows(rows)
}

# —— S3 / S4 发现集 ——
.mim <- .jlcm_models_load(
  file.path(ix_root, "mimic/step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData")
)
.opt_ng_paths <- c(
  file.path(ix_root, "mimic/step14_trajectory_jlcm/Tables/Summary/optimal_ng_WPR.txt"),
  file.path(ix_root, "mimic/Tables/Summary/optimal_ng_WPR.txt")
)
.opt_ng <- suppressWarnings(as.integer(trimws(readLines(
  .opt_ng_paths[file.exists(.opt_ng_paths)][1L], warn = FALSE
)[1L])))
if (!is.finite(.opt_ng) || .opt_ng < 2L) .opt_ng <- 4L
s3 <- .jlcm_sheet_s3(.mim$models, max(5L, .opt_ng))
.write_one(
  s3,
  file.path(tab_out, "Table S3. Model fit metrics for determining the optimal number of classes in the derivation cohort.xlsx"),
  "Table S3. Model fit metrics for determining the optimal number of classes in the derivation cohort",
  footnotes = c(
    "Layout aligned with fcimb data sheet Table S3 (No. of classes | Log likelihood | BIC | Entropy | Class proportions).",
    sprintf(
      "Class columns = proportion of people (%%). Primary solution: ng = %s (selected by BIC among high-entropy solutions after dual-database covariate lock; min-class <5%% disclosed).",
      .opt_ng
    )
  )
)

s4 <- .jlcm_sheet_s4(.mim$models, 5L)
.write_one(
  s4,
  file.path(tab_out, "Table S4. Mean posterior probabilities for candidate latent class solutions in the derivation cohort.xlsx"),
  "Table S4. Mean posterior probabilities for candidate latent class solutions in the derivation cohort",
  footnotes = c(
    "Layout aligned with fcimb data sheet Table S4.",
    "Cells = mean posterior probability of the assigned class among individuals allocated to that class."
  )
)

# —— S5 / S6 外验：对各 ng 发现模型 predictClass ——
cli::cli_alert_info("S5/S6: predictClass on eICU for ng=1..5")
suppressPackageStartupMessages({
  library(lcmm)
  library(splines)
  library(survival)
})
.ext_ck <- file.path(proj, "checkpoints/by_index", ix, "eicu", "trajectory_lcmm_external_validate.rds")
if (!file.exists(.ext_ck))
  stop("缺少 eICU external_validate checkpoint: ", .ext_ck)
.ext <- readRDS(.ext_ck)
.idx_wide <- {
  p12 <- file.path(proj, "data/eicu/12_WPR.RData")
  ee <- new.env(parent = emptyenv()); load(p12, envir = ee); ee$index_df
}
.tlcev_wide_to_long <- function(index_df, id_col, Index, time_end = 28L) {
  day_cols <- paste0(Index, "_", seq_len(time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("宽表无日列 ", Index, "_*")
  wide <- as.data.frame(index_df[, c(id_col, day_cols), drop = FALSE], stringsAsFactors = FALSE)
  long <- data.table::melt(
    data.table::as.data.table(wide),
    id.vars = id_col,
    measure.vars = day_cols,
    variable.name = "day_lab",
    value.name = "Value"
  )
  long <- as.data.frame(long)
  long$time_day <- as.integer(sub(paste0("^", Index, "_"), "", as.character(long$day_lab)))
  long <- long[is.finite(as.numeric(long$Value)), , drop = FALSE]
  long
}
.id_col <- "subject_id"
.base_imp <- .ext$ctx$data$imputed %||% .ext$ctx$data$cleaned
.s5_rows <- list(); .s6_rows <- list()
for (ng in 1:5) {
  # ng=1：单类无需 predictClass
  if (identical(as.integer(ng), 1L)) {
    n_val <- length(unique(as.character(.idx_wide[[.id_col]])))
    row5 <- data.frame(
      `No. of classes` = 1L,
      Entropy = "1.000000", `Class 1` = "100.00", `Class 2` = "", `Class 3` = "",
      `Class 4` = "", `Class 5` = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
    row6 <- data.frame(
      `No. of classes` = 1L, `Class 1` = "1.000000", `Class 2` = "", `Class 3` = "",
      `Class 4` = "", `Class 5` = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
    .s5_rows[[length(.s5_rows) + 1L]] <- row5
    .s6_rows[[length(.s6_rows) + 1L]] <- row6
    cli::cli_alert_success("ng=1: n={n_val}, entropy=1 (single class)")
    next
  }
  m <- trajectory_unwrap_jointlcmm(.mim$models[[paste0("m", ng)]])
  nm <- m$Names
  y_col <- as.character(nm$Yname %||% "scr_std")[1L]
  subj_col <- as.character(nm$ID %||% "subject_id_num")[1L]
  x_need <- as.character(nm$Xnames2 %||% character(0))
  t_surv <- as.character(nm$Tnames %||% c("surv_time", "surv_event"))
  long <- .tlcev_wide_to_long(.idx_wide, .id_col, "WPR", 28L)
  id_chr <- as.character(long[[.id_col]])
  id_levels <- unique(id_chr)
  newdata <- data.frame(
    time_day = as.numeric(long$time_day),
    stringsAsFactors = FALSE
  )
  newdata[[y_col]] <- as.numeric(long$Value)
  newdata[[subj_col]] <- as.integer(match(id_chr, id_levels))
  newdata[[.id_col]] <- id_chr
  cov_need <- unique(c(setdiff(x_need, "time_day"), t_surv))
  if (!is.null(.base_imp) && .id_col %in% names(.base_imp)) {
    keep <- intersect(c(.id_col, cov_need), names(.base_imp))
    b1 <- unique(.base_imp[, keep, drop = FALSE])
    if (!"surv_time" %in% names(b1) && "survival_time_28d" %in% names(.base_imp)) {
      b1$surv_time <- pmin(as.numeric(.base_imp$survival_time_28d[match(b1[[.id_col]], .base_imp[[.id_col]])]), 28)
    }
    if (!"surv_event" %in% names(b1) && "survival_28d" %in% names(.base_imp)) {
      b1$surv_event <- as.integer(as.character(.base_imp$survival_28d[match(b1[[.id_col]], .base_imp[[.id_col]])]) %in% c("1", "Yes"))
    }
    newdata <- merge(newdata, b1, by = .id_col, all.x = TRUE)
  }
  mdata <- .mim$model_data
  for (cv in setdiff(x_need, "time_day")) {
    if (!cv %in% names(newdata) || all(!is.finite(as.numeric(newdata[[cv]])))) {
      if (cv %in% names(mdata) && is.numeric(mdata[[cv]]))
        newdata[[cv]] <- stats::median(as.numeric(mdata[[cv]]), na.rm = TRUE)
    } else {
      v <- as.numeric(newdata[[cv]])
      if (any(!is.finite(v)) && cv %in% names(mdata) && is.numeric(mdata[[cv]])) {
        v[!is.finite(v)] <- stats::median(as.numeric(mdata[[cv]]), na.rm = TRUE)
        newdata[[cv]] <- v
      }
    }
  }
  newdata[[subj_col]] <- as.integer(newdata[[subj_col]])
  .pc_call <- list(model = m, newdata = newdata, subject = subj_col, var.time = "time_day")
  .pc_args <- names(formals(lcmm::predictClass))
  .pc_call <- .pc_call[names(.pc_call) %in% c("model", "newdata", intersect(c("subject", "var.time"), .pc_args))]
  pred <- tryCatch(do.call(lcmm::predictClass, .pc_call), error = function(err) {
    cli::cli_alert_danger("predictClass ng={ng} 失败: {conditionMessage(err)}")
    NULL
  })
  if (is.null(pred)) {
    row5 <- data.frame(`No. of classes` = ng, Entropy = "\u2014",
                       check.names = FALSE, stringsAsFactors = FALSE)
    row6 <- data.frame(`No. of classes` = ng, check.names = FALSE, stringsAsFactors = FALSE)
    for (k in 1:5) {
      row5[[paste0("Class ", k)]] <- ""
      row6[[paste0("Class ", k)]] <- ""
    }
    .s5_rows[[length(.s5_rows) + 1L]] <- row5
    .s6_rows[[length(.s6_rows) + 1L]] <- row6
    next
  }
  pred <- as.data.frame(pred)
  if (!is.null(pred[["subject_id_num"]])) {
    pred[[.id_col]] <- id_levels[as.integer(pred[["subject_id_num"]])]
  }
  pred <- pred[!duplicated(pred[[.id_col]]), , drop = FALSE]
  cls <- as.integer(pred[["class"]] %||% pred[["class.pred"]])
  py <- grep("^probYT", names(pred), value = TRUE)
  if (!length(py)) py <- grep("^prob", names(pred), value = TRUE)
  P <- as.matrix(pred[, py, drop = FALSE])
  # Entropy（外验后验）
  ent <- if (ng <= 1L) 1 else {
    Pp <- pmax(P, .Machine$double.eps)
    round(1 - (-sum(Pp * log(Pp), na.rm = TRUE) / (nrow(Pp) * log(ng))), 6)
  }
  tab <- table(factor(cls, levels = seq_len(ng)))
  props <- as.numeric(100 * prop.table(tab))
  row5 <- data.frame(
    `No. of classes` = ng,
    Entropy = sprintf("%.6f", ent),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  row6 <- data.frame(`No. of classes` = ng, check.names = FALSE, stringsAsFactors = FALSE)
  for (k in 1:5) {
    row5[[paste0("Class ", k)]] <- if (k <= ng) sprintf("%.2f", props[k]) else ""
    if (k > ng || !ncol(P) || k > ncol(P)) {
      row6[[paste0("Class ", k)]] <- ""
    } else {
      idx <- which(cls == k)
      row6[[paste0("Class ", k)]] <- if (!length(idx)) "" else sprintf("%.6f", mean(P[idx, k], na.rm = TRUE))
    }
  }
  .s5_rows[[length(.s5_rows) + 1L]] <- row5
  .s6_rows[[length(.s6_rows) + 1L]] <- row6
  cli::cli_alert_success("ng={ng}: n={nrow(pred)}, entropy={ent}")
}
s5 <- dplyr::bind_rows(.s5_rows)
s6 <- dplyr::bind_rows(.s6_rows)
# 清旧文件名
old_s5 <- list.files(tab_out, pattern = "^Table S5\\.", full.names = TRUE)
old_s6 <- list.files(tab_out, pattern = "^Table S6\\.", full.names = TRUE)
unlink(c(old_s5, old_s6))
.write_one(
  s5,
  file.path(tab_out, "Table S5. Model fit metrics for determining the optimal number of classes in the validation cohort.xlsx"),
  "Table S5. Model fit metrics for determining the optimal number of classes in the validation cohort",
  footnotes = c(
    "Entropy and Class 1–5 = transferred posterior entropy and class percentages (%) on the validation cohort."
  )
)
.write_one(
  s6,
  file.path(tab_out, "Table S6. Mean posterior probabilities for candidate latent class solutions in the validation cohort.xlsx"),
  "Table S6. Mean posterior probabilities for candidate latent class solutions in the validation cohort",
  footnotes = c(
    "Layout aligned with fcimb data sheet Table S6.",
    "Cells = mean predictClass posterior probability of the assigned class (discovery parameters applied to eICU).",
    "Not from an independently re-fitted validation JLCM."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# S7 / S8 时依 HR
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table S7/S8")
.pw_csv <- function(db) {
  cands <- c(
    file.path(ix_root, db, "Tables/Table_Piecewise_Cox_By_Class.csv"),
    file.path(ix_root, db, "Tables/_archive/Table_Piecewise_Cox_By_Class.csv"),
    file.path(ix_root, db, "step20_trajectory_piecewise_cox/Tables/Table_Piecewise_Cox_By_Class.csv")
  )
  hit <- cands[file.exists(cands)]
  if (!length(hit)) stop("缺少 Piecewise Cox By Class CSV: ", db)
  hit[[1L]]
}
hr_m <- utils::read.csv(.pw_csv("mimic"), stringsAsFactors = FALSE, check.names = FALSE)
cut_v <- as.integer(hr_m$cut[1])
ref_v <- as.integer(hr_m$ref_class[1])
lab_early <- sprintf("(0,%s]", cut_v)
lab_late <- sprintf("(%s,28]", cut_v)
s7 <- data.frame(
  `Trajectory class` = hr_m$class_label,
  check.names = FALSE, stringsAsFactors = FALSE
)
s7[[lab_early]] <- as.character(hr_m[[lab_early]])
s7[[lab_late]] <- as.character(hr_m[[lab_late]])
.ref7 <- data.frame(
  `Trajectory class` = paste0("Class ", ref_v, " (Reference)"),
  check.names = FALSE, stringsAsFactors = FALSE
)
.ref7[[lab_early]] <- "1 (Reference)"
.ref7[[lab_late]] <- "1 (Reference)"
s7 <- rbind(.ref7, s7)
# 双行表头：Groups | HR (95% CI) spanning
.h1 <- c("Trajectory class", "HR (95% CI)", "HR (95% CI)")
.h2 <- c("", lab_early, lab_late)
.sci_xlsx_double_header_booktabs(
  filepath = file.path(tab_out, "Table S7. Time-dependent HR for trajectory classes in the derivation cohort.xlsx"),
  title = "Table S7. Time-dependent HR for trajectory classes in the derivation cohort",
  df_body = s7,
  h1 = .h1, h2 = .h2,
  footnotes = c(
    "Aligned with data sheet Table S7.",
    sprintf("Piecewise Cox; cutpoint = %s days; reference = Class %s; outcome = 28-day in-hospital death.", cut_v, ref_v)
  )
)
cli::cli_alert_success("Table S7")

# S8 rebuild eICU（assignment CSV 为唯一外验类别来源；禁止未定义 asg）
.asg_cands <- c(
  file.path(ix_root, "eicu/step16_trajectory_lcmm_external_validate/Tables/LCMM/Table_LCMM_Assignment_External_WPR.csv"),
  file.path(ix_root, "eicu/step15_trajectory_lcmm_external_validate/Tables/LCMM/Table_LCMM_Assignment_External_WPR.csv"),
  file.path(ix_root, "eicu/step14_trajectory_lcmm_external_validate/Tables/LCMM/Table_LCMM_Assignment_External_WPR.csv")
)
.asg_cands <- .asg_cands[file.exists(.asg_cands)]
.asg_path <- if (!length(.asg_cands)) {
  NA_character_
} else if (is.finite(.opt_ng)) {
  .sc <- vapply(.asg_cands, function(f) {
    a <- tryCatch(utils::read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.null(a) || !"trajectory_class" %in% names(a)) return(-Inf)
    mx <- suppressWarnings(max(as.integer(a$trajectory_class), na.rm = TRUE))
    base <- as.numeric(file.mtime(f))
    if (is.finite(mx) && identical(as.integer(mx), as.integer(.opt_ng))) base + 1e12 else base
  }, numeric(1))
  .asg_cands[[which.max(.sc)]]
} else {
  .asg_cands[[1L]]
}
if (is.na(.asg_path) || !nzchar(.asg_path))
  stop("S8: 缺少 eICU LCMM assignment CSV", call. = FALSE)
asg <- utils::read.csv(.asg_path, stringsAsFactors = FALSE)
asg$subject_id <- as.character(asg$subject_id)
asg <- asg[is.finite(asg$trajectory_class), , drop = FALSE]
.e2 <- merge(.e, asg[, c("subject_id", "trajectory_class")], by = "subject_id")
.e2$event <- .event01(.e2$survival_28d)
.e2$time <- if ("survival_time_28d" %in% names(.e2))
  pmin(as.numeric(.e2$survival_time_28d), 28) else 28
.e2 <- .e2[is.finite(.e2$time) & .e2$time > 0 & !is.na(.e2$trajectory_class), ]
.e2$class <- factor(.e2$trajectory_class)
.e2$class <- stats::relevel(.e2$class, ref = as.character(ref_v))
d1 <- .e2
d1$event1 <- as.integer(d1$event == 1L & d1$time <= cut_v)
d1$time1 <- pmin(d1$time, cut_v)
d2 <- .e2[.e2$time > cut_v, ]
d2$event2 <- d2$event
d2$time2 <- d2$time - cut_v
fit1 <- coxph(Surv(time1, event1) ~ class, data = d1)
fit2 <- coxph(Surv(time2, event2) ~ class, data = d2)
.cell <- function(fit, cl) {
  co <- summary(fit)$conf.int
  rn <- grep(paste0("class", cl, "$"), rownames(co))
  if (!length(rn)) return("NE")
  .fmt_hr(co[rn, 1], co[rn, 3], co[rn, 4])
}
lev <- setdiff(levels(.e2$class), as.character(ref_v))
s8 <- do.call(rbind, lapply(lev, function(cl) {
  data.frame(
    `Trajectory class` = paste0("Class ", cl, " (ref = Class ", ref_v, ")"),
    a = .cell(fit1, cl),
    b = .cell(fit2, cl),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))
names(s8) <- c("Trajectory class", lab_early, lab_late)
.ref8 <- data.frame(
  `Trajectory class` = paste0("Class ", ref_v, " (Reference)"),
  check.names = FALSE, stringsAsFactors = FALSE
)
.ref8[[lab_early]] <- "1 (Reference)"
.ref8[[lab_late]] <- "1 (Reference)"
s8 <- rbind(.ref8, s8)
.sci_xlsx_double_header_booktabs(
  filepath = file.path(tab_out, "Table S8. Time-dependent HR for trajectory classes in the validation cohort.xlsx"),
  title = "Table S8. Time-dependent HR for trajectory classes in the validation cohort",
  df_body = s8,
  h1 = .h1, h2 = .h2,
  footnotes = c(
    "Aligned with data sheet Table S8.",
    sprintf("Cutpoint locked to derivation (%s d); reference = Class %s.", cut_v, ref_v),
    sprintf("n = %s; events = %s.", format(nrow(.e2), big.mark = ","), sum(.e2$event == 1L))
  )
)
cli::cli_alert_success("Table S8")

# ═══════════════════════════════════════════════════════════════════════════
# S9 / S10 PAMM — 对齐 data sheet：Continuous + Threshold + Proportion + Cumulative
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table S9/S10")
.pamm_long_from_wide <- function(index_df, id_col, index_name, time_end = 28L) {
  day_cols <- paste0(index_name, "_", seq.int(1L, time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("S9/S10: wide 表缺 ", index_name, "_day 列", call. = FALSE)
  rows <- lapply(day_cols, function(dc) {
    day <- as.integer(sub(paste0("^", index_name, "_"), "", dc))
    data.frame(
      id = as.character(index_df[[id_col]]),
      time_day = day,
      expo = suppressWarnings(as.numeric(index_df[[dc]])),
      stringsAsFactors = FALSE
    )
  })
  long <- do.call(rbind, rows)
  long <- long[is.finite(long$expo), , drop = FALSE]
  names(long)[1L] <- id_col
  long
}
.pamm_hr_cell <- function(hr, lo, hi) {
  # 尺度崩坏 / 分离 → NE（文献表只留 HR，不另开 P 列）
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) return("NE")
  if (hr < 0.01 || hr > 100 || (hi / pmax(lo, 1e-12)) > 1e4 || hi > 1e4) return("NE")
  .fmt_hr(hr, lo, hi)
}
.pamm_fit_cox <- function(dd, x, covs) {
  dd$x <- as.numeric(x)
  if (!all(is.finite(dd$x))) {
    return(list(HR = NA_real_, lo = NA_real_, hi = NA_real_))
  }
  fml <- if (length(covs)) {
    stats::as.formula(paste("survival::Surv(time, event) ~ x +", paste(covs, collapse = " + ")))
  } else {
    survival::Surv(time, event) ~ x
  }
  m <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
  if (is.null(m)) return(list(HR = NA_real_, lo = NA_real_, hi = NA_real_))
  sm <- summary(m)$coefficients
  ci <- tryCatch(exp(stats::confint(m)["x", ]), error = function(e) c(NA_real_, NA_real_))
  list(
    HR = unname(exp(sm["x", "coef"])),
    lo = unname(ci[1L]),
    hi = unname(ci[2L])
  )
}
.pamm_build <- function(db, thr_path, title, dest, role) {
  thr <- readRDS(thr_path)
  lo <- as.numeric(thr$lo)
  hi <- as.numeric(thr$hi)
  wide_path <- file.path(proj, "data", db, "12_WPR.RData")
  if (!file.exists(wide_path)) stop("缺宽表: ", wide_path, call. = FALSE)
  e <- new.env(parent = emptyenv())
  load(wide_path, envir = e)
  index_df <- e$index_df
  if (is.null(index_df)) stop("12_WPR.RData 无 index_df", call. = FALSE)
  long <- .pamm_long_from_wide(index_df, "subject_id", "WPR", 28L)
  agg <- stats::aggregate(
    expo ~ subject_id, data = long,
    FUN = function(z) {
      c(
        mean_expo = mean(z),
        ever_lo = as.integer(any(z <= lo)),
        ever_hi = as.integer(any(z >= hi)),
        prop_lo = mean(z <= lo),
        prop_hi = mean(z >= hi),
        cum_lo = sum(pmax(0, lo - z)),
        cum_hi = sum(pmax(0, z - hi))
      )
    }
  )
  idv <- as.character(agg[[1L]])
  mat <- as.matrix(agg[[2L]])
  bur <- data.frame(
    subject_id = idv,
    mean_expo = as.numeric(mat[, "mean_expo"]),
    ever_lo = as.numeric(mat[, "ever_lo"]),
    ever_hi = as.numeric(mat[, "ever_hi"]),
    prop_lo = as.numeric(mat[, "prop_lo"]),
    prop_hi = as.numeric(mat[, "prop_hi"]),
    cum_lo = as.numeric(mat[, "cum_lo"]),
    cum_hi = as.numeric(mat[, "cum_hi"]),
    stringsAsFactors = FALSE
  )
  base <- .load_imp(db)
  dd <- merge(base, bur, by = "subject_id", all.x = FALSE)
  dd$time <- pmin(as.numeric(dd$survival_time_28d), 28)
  dd$event <- .event01(dd$survival_28d)
  dd <- dd[is.finite(dd$time) & dd$time > 0, , drop = FALSE]
  # 双库强对齐：固定共享协变量（缺任一库则硬失败）
  covs <- .shared_covs
  miss_cov <- setdiff(covs, names(dd))
  if (length(miss_cov))
    stop("S9/S10: ", db, " 缺共享协变量: ", paste(miss_cov, collapse = ", "), call. = FALSE)
  for (cv in covs) {
    if (!is.numeric(dd[[cv]]))
      dd[[cv]] <- suppressWarnings(as.numeric(as.character(dd[[cv]])))
    if (!is.numeric(dd[[cv]]) || all(!is.finite(dd[[cv]])))
      stop("S9/S10: ", db, " 协变量非数值: ", cv, call. = FALSE)
  }
  lo_lab <- signif(lo, 3)
  hi_lab <- signif(hi, 3)
  specs <- list(
    list("Continuous effect", "WPR", "Per 0.01 increase", dd$mean_expo * 100),
    list("Threshold effect", "Low WPR",
         sprintf("WPR \u2264 %s", lo_lab), dd$ever_lo),
    list("Threshold effect", "High WPR",
         sprintf("WPR \u2265 %s", hi_lab), dd$ever_hi),
    list("Exposure proportion", "Low-WPR proportion",
         sprintf("Per 5%% increase in time spent with WPR \u2264 %s", lo_lab),
         dd$prop_lo * 20),
    list("Exposure proportion", "High-WPR proportion",
         sprintf("Per 5%% increase in time spent with WPR \u2265 %s", hi_lab),
         dd$prop_hi * 20),
    list("Cumulative burden", "Low-WPR burden",
         sprintf("Cumulative exposure \u2264 %s", lo_lab), dd$cum_lo),
    list("Cumulative burden", "High-WPR burden",
         sprintf("Cumulative exposure \u2265 %s", hi_lab), dd$cum_hi)
  )
  out <- do.call(rbind, lapply(specs, function(sp) {
    fit <- .pamm_fit_cox(dd, sp[[4]], covs)
    data.frame(
      Item = sp[[1]],
      `Exposure metric` = sp[[2]],
      Definition = sp[[3]],
      `HR (95% CI)` = .pamm_hr_cell(fit$HR, fit$lo, fit$hi),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }))
  .write_one(
    out, dest, title,
    footnotes = c(
      sprintf("Aligned with data sheet Table S9/S10 layout (%s cohort).", role),
      sprintf(
        "P5/P95 thresholds locked on derivation (WPR \u2264 %s / \u2265 %s).",
        lo_lab, hi_lab
      ),
      paste0(
        .shared_covs_methods_note,
        " Same set as Tables S9–S11."
      ),
      "Continuous = person-mean WPR (per 0.01); threshold = ever beyond cut; proportion = per 5% of observed days; cumulative = sum of absolute deviations beyond cut.",
      "NE = not estimable (quasi-complete separation or unstable scale for sparse low-WPR burden).",
      sprintf("n = %s.", format(nrow(dd), big.mark = ","))
    )
  )
}
.thr_mimic <- file.path(ix_root, "mimic/step25_trajectory_pamm/Tables/PAMM/PAMM_thresholds_WPR.rds")
.pamm_build(
  "mimic", .thr_mimic,
  "Table S9. Associations between WPR exposure metrics and in-hospital mortality in the derivation cohort",
  file.path(tab_out, "Table S9. Associations between WPR exposure metrics and in-hospital mortality in the derivation cohort.xlsx"),
  "derivation"
)
.thr_e <- file.path(ix_root, "eicu/step25_trajectory_pamm/Tables/PAMM/PAMM_thresholds_WPR.rds")
if (!file.exists(.thr_e))
  .thr_e <- file.path(ix_root, "mimic/step25_trajectory_pamm/Tables/PAMM/PAMM_thresholds_WPR_locked.rds")
if (!file.exists(.thr_e))
  .thr_e <- file.path(ix_root, "mimic/Tables/PAMM/PAMM_thresholds_WPR_locked.rds")
if (!file.exists(.thr_e)) .thr_e <- .thr_mimic
.pamm_build(
  "eicu", .thr_e,
  "Table S10. Associations between WPR exposure metrics and in-hospital mortality in the validation cohort",
  file.path(tab_out, "Table S10. Associations between WPR exposure metrics and in-hospital mortality in the validation cohort.xlsx"),
  "validation"
)

# ═══════════════════════════════════════════════════════════════════════════
# S11：与主文 28 天对齐的 cause-specific vs Fine-Gray
# 事件 = survival_28d；竞争 = 28 天前存活出院；仍在院至 28 天 = 删失
# ═══════════════════════════════════════════════════════════════════════════
cli::cli_h1("Table S11")
suppressPackageStartupMessages(library(cmprsk))
.m_s11 <- .mim$models[[paste0("m", .opt_ng)]]
if (is.null(.m_s11))
  stop("S11 找不到 primary JLCM m", .opt_ng, call. = FALSE)
pp_s11 <- as.data.frame(trajectory_unwrap_jointlcmm(.m_s11)$pprob)
md <- .mim$model_data
id_map <- unique(md[, c("subject_id", "subject_id_num")])
id_map$subject_id <- as.character(id_map$subject_id)
map_m <- merge(
  data.frame(subject_id_num = pp_s11$subject_id_num, trajectory_class = pp_s11$class),
  id_map, by = "subject_id_num"
)
.surv_csv <- file.path(proj, "data/mimic/MIMIC_ICU_survival_1023 (1).csv")
if (!file.exists(.surv_csv)) {
  alt <- list.files(file.path(proj, "data/mimic"), pattern = "MIMIC_ICU_survival.*\\.csv$", full.names = TRUE)
  if (!length(alt)) stop("缺 MIMIC survival CSV（hosp_day）", call. = FALSE)
  .surv_csv <- alt[[1L]]
}
sv <- as.data.frame(data.table::fread(.surv_csv), stringsAsFactors = FALSE)
sv$subject_id <- as.character(sv$subject_id)
sv <- sv[!duplicated(sv$subject_id), , drop = FALSE]
if (!"hosp_day" %in% names(sv))
  stop("survival CSV 缺 hosp_day", call. = FALSE)
.s11 <- merge(map_m[, c("subject_id", "trajectory_class")], .m, by = "subject_id")
.s11 <- merge(.s11, sv[, c("subject_id", "hosp_day")], by = "subject_id")
.s11$hosp_day <- as.numeric(.s11$hosp_day)
.s11$t_surv <- pmin(as.numeric(.s11$survival_time_28d), 28)
.s11$event28 <- .event01(.s11$survival_28d)
# ftime / fstatus：1=28d 死亡；2=28d 前存活出院；0=删失于 28d
.s11$ftime <- ifelse(
  .s11$event28 == 1L, .s11$t_surv,
  ifelse(is.finite(.s11$hosp_day) & .s11$hosp_day < 28 & .s11$event28 == 0L,
         .s11$hosp_day, 28)
)
.s11$fstatus <- 0L
.s11$fstatus[.s11$event28 == 1L] <- 1L
.s11$fstatus[.s11$event28 == 0L & is.finite(.s11$hosp_day) & .s11$hosp_day < 28] <- 2L
.s11 <- .s11[is.finite(.s11$ftime) & .s11$ftime > 0 & !is.na(.s11$trajectory_class), ]
.s11$class <- factor(.s11$trajectory_class)
.s11$class <- stats::relevel(.s11$class, ref = as.character(ref_v))
# 共享协变量
miss_cov <- setdiff(.shared_covs, names(.s11))
if (length(miss_cov))
  stop("S11 缺共享协变量: ", paste(miss_cov, collapse = ", "), call. = FALSE)
for (cv in .shared_covs) {
  if (!is.numeric(.s11[[cv]]))
    .s11[[cv]] <- suppressWarnings(as.numeric(as.character(.s11[[cv]])))
}
# Cause-specific：死亡为事件，出院/删失均作删失
.s11$event_cs <- as.integer(.s11$fstatus == 1L)
.fml_cs <- stats::as.formula(
  paste("survival::Surv(ftime, event_cs) ~ class +", paste(.shared_covs, collapse = " + "))
)
fit_cs <- survival::coxph(.fml_cs, data = .s11)
co_cs <- summary(fit_cs)$conf.int
# Fine-Gray：failcode=28d 死亡；竞争=存活出院；调整同一套协变量
X <- stats::model.matrix(
  stats::as.formula(paste("~ class +", paste(.shared_covs, collapse = " + "))),
  data = .s11
)[, -1L, drop = FALSE]
fg <- cmprsk::crr(
  ftime = .s11$ftime, fstatus = .s11$fstatus, cov1 = X, failcode = 1L, cencode = 0L
)
fg_hr <- exp(as.numeric(fg$coef))
fg_se <- sqrt(diag(as.matrix(fg$var)))
fg_lo <- exp(as.numeric(fg$coef) - 1.96 * fg_se)
fg_hi <- exp(as.numeric(fg$coef) + 1.96 * fg_se)
names(fg_hr) <- names(fg_lo) <- names(fg_hi) <- colnames(X)
lev <- as.character(sort(as.integer(setdiff(levels(.s11$class), as.character(ref_v)))))
s11 <- do.call(rbind, lapply(lev, function(cl) {
  rn_cs <- grep(paste0("^class", cl, "$"), rownames(co_cs))
  rn_fg <- paste0("class", cl)
  data.frame(
    Item = paste("Class", cl),
    `HR (95% CI)` = if (length(rn_cs))
      .fmt_hr(co_cs[rn_cs, 1], co_cs[rn_cs, 3], co_cs[rn_cs, 4]) else "NE",
    `sHR (95% CI)` = if (rn_fg %in% names(fg_hr))
      .fmt_hr(fg_hr[[rn_fg]], fg_lo[[rn_fg]], fg_hi[[rn_fg]]) else "NE",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}))
.s11_title <- paste0(
  "Table S11. Association between WPR trajectory classes and in-hospital mortality: ",
  "comparison of cause-specific and competing-risk models"
)
.s11_path <- file.path(
  tab_out,
  "Table S11. Association between WPR trajectory classes and in-hospital mortality.xlsx"
)
.h1_s11 <- c("Item", "Cause-specific hazard models", "Fine-Gray competing-risk model")
.h2_s11 <- c("", "HR (95% CI)", "sHR (95% CI)")
.sci_xlsx_double_header_booktabs(
  filepath = .s11_path,
  title = .s11_title,
  df_body = s11,
  h1 = .h1_s11, h2 = .h2_s11,
  footnotes = c(
    "HR indicates cause-specific hazard ratio; sHR indicates subdistribution hazard ratio accounting for the competing event of alive hospital discharge before day 28.",
    sprintf(
      "Aligned with primary 28-day in-hospital death (survival_28d). Event = death by day 28; competing = alive discharge with hosp_day < 28; censored = still hospitalized at day 28. Reference = Class %s.",
      ref_v
    ),
    paste0(.shared_covs_methods_note, " Same set as Tables S9/S10."),
    sprintf(
      "n = %s; 28-day deaths = %s; competing discharges = %s; censored at day 28 = %s.",
      format(nrow(.s11), big.mark = ","),
      format(sum(.s11$fstatus == 1L), big.mark = ","),
      format(sum(.s11$fstatus == 2L), big.mark = ","),
      format(sum(.s11$fstatus == 0L), big.mark = ",")
    )
  )
)
cli::cli_alert_success("Table S11")

# Methods：协变量选型写实（单因素 → VIF + 文献 + 双库可得性）
.meth_dir <- file.path(ix_root, "summary_results")
dir.create(.meth_dir, recursive = TRUE, showWarnings = FALSE)
.meth_path <- file.path(.meth_dir, "Methods_statistical_analysis.md")
writeLines(
  c(
    "# Statistical analysis (WPR trajectory — COPD)",
    "",
    paste0(
      "Joint latent class mixed models (JLCM) identified longitudinal WPR trajectories in the ",
      "MIMIC-IV derivation cohort; the primary solution used ", .opt_ng,
      " latent classes (selected by BIC among high-entropy candidates after dual-database ",
      "covariate lock; solutions with a class <5% of the cohort are disclosed). Class membership ",
      "was applied to eICU with fixed discovery parameters. Associations with 28-day in-hospital ",
      "mortality used piecewise Cox models and dynamic prediction. Piece-wise exponential additive ",
      "mixed models (PAMM) summarized continuous WPR–mortality associations (burden tables)."
    ),
    "",
    paste0(
      "Covariate selection for adjusted JLCM, PAMM burden models, and class–mortality models ",
      "(Tables S9–S11) followed univariate screening, VIF multicollinearity screening, and ",
      "literature-informed finalization with dual-database availability. The locked shared set was ",
      paste(.shared_covs, collapse = ", "),
      "; LymphocytePercent was excluded because it is unavailable in eICU, so derivation and ",
      "validation used one identical adjustment set."
    ),
    "",
    "Figure/table order follows Frontiers CIMB fcimb-16-1871653 where counterparts exist:",
    "",
    "- Figure 1: trajectory classes (derivation)",
    "- Figure 2: Kaplan–Meier by class (derivation + validation)",
    "- Figure 3: dynamic prediction (MIMIC derivation; mortality secondary axis; landmarks 3/5/7/12 d)",
    "- Figure 4: dynamic prediction (eICU external; same landmarks; discovery JLCM fixed)",
    "- Figure 5–6: PAMM time-varying association panels (derivation / external)",
    "- Figure S1: flowchart (literature Supplementary Figure 1)",
    "- Figure S4: dynamic vs static AUC (supplement; not main-text Figure 4)",
    "",
    "Full mapping: reports/WPR_FIGURE_TABLE_MANIFEST_fcimb.md",
    "",
    "## Software",
    paste0("- R ", paste(R.version$major, R.version$minor, sep = "."), " (", R.version$string, ")")
  ),
  .meth_path
)
cli::cli_alert_success("Methods: {.file {(.meth_path)}}")

cli::cli_alert_success("全部表已按三线表 + Times New Roman 重建")
print(list.files(tab_out, pattern = "\\.xlsx$"))
