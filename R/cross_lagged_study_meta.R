###############################################################################
#  cross_lagged_study_meta.R — 交叉滞后课题元数据（髋部 / 昼夜 / 痴呆）
#
#  供 phase_sensitivity、collect、出版清单共用。禁止在引擎里写死糖尿病。
###############################################################################

cross_lagged_study_is_circadian <- function(study_root) {
  f <- file.path(as.character(study_root)[1L], "config_long_panel.R")
  if (!file.exists(f)) return(FALSE)
  any(grepl("circadian_index_var|ePWV", readLines(f, warn = FALSE)))
}

cross_lagged_study_is_dementia <- function(study_root) {
  sr <- as.character(study_root)[1L]
  grepl("Dementia", basename(dirname(sr)), ignore.case = TRUE) ||
    grepl("Dementia", sr, ignore.case = TRUE) ||
    file.exists(file.path(sr, "data/Step01_RawData/D01_AfterMI_Data_ELSA.RData"))
}

cross_lagged_discover_phase1_dbs <- function(study_root) {
  dn <- list.dirs(study_root, recursive = FALSE, full.names = FALSE)
  xs <- dn[grepl("^phase1_", dn) & !grepl("Pooled", dn, ignore.case = TRUE)]
  xs <- sub("^phase1_", "", xs)
  xs <- sub("_allages$", "", xs)
  unique(xs[nzchar(xs)])
}

cross_lagged_discover_long_dbs <- function(study_root) {
  dn <- list.dirs(study_root, recursive = FALSE, full.names = FALSE)
  lg <- dn[grepl("^phase3_long_", dn) & !grepl("Pooled", dn, ignore.case = TRUE)]
  lg <- sub("^phase3_long_", "", lg)
  unique(lg[nzchar(lg)])
}

#' 交叉滞后课题元数据
#'
#' @return list: kind, cohorts_xs, cohorts_long, index_var, grouping, labels, ...
cross_lagged_study_meta <- function(study_root) {
  study_root <- as.character(study_root)[1L]
  xs_found <- tryCatch(cross_lagged_discover_phase1_dbs(study_root), error = function(e) character(0))
  long_found <- tryCatch(cross_lagged_discover_long_dbs(study_root), error = function(e) character(0))

  if (isTRUE(cross_lagged_study_is_dementia(study_root))) {
    pref_xs <- c("CLHLS", "SHARE", "HRS", "ELSA")
    return(list(
      kind = "dementia",
      disease = "Dementia",
      disease_code = "20",
      analysis_group = "Dementia",
      reference_group = "Normal",
      index_var = "Leisure_activities",
      index_display = "Leisure_activities",
      disease_display = "Dementia",
      project_prefix = "Dementia_Leisure_sens_",
      grouping = "tertile",
      grouping_labels = c("T1", "T2", "T3"),
      tertile_right = FALSE,
      fi_t1 = "T1_le",
      fi_t2 = "T2_le",
      change_index_stem = "Leisure_activities",
      change_index_display = "Leisure_activities",
      table1_harmonize = FALSE,
      cohorts_xs = intersect(pref_xs, union(xs_found, pref_xs)),
      cohorts_long = intersect(pref_xs, union(long_found, pref_xs))
    ))
  }

  if (isTRUE(cross_lagged_study_is_circadian(study_root))) {
    pref_xs <- c("CHARLS", "ELSA", "NHANES")
    pref_long <- c("CHARLS", "ELSA")
    xs <- if (length(xs_found)) intersect(pref_xs, xs_found) else pref_xs
    lg <- if (length(long_found)) intersect(pref_long, long_found) else
      intersect(pref_long, xs)
    return(list(
      kind = "circadian",
      disease = "circadian_disorder",
      disease_code = "23",
      analysis_group = "Circadian_Disorder",
      reference_group = "No_Disorder",
      index_var = "ePWV",
      index_display = "ePWV",
      disease_display = "Circadian disorder",
      project_prefix = "Circadian_ePWV_sens_",
      grouping = "quartile",
      grouping_labels = c("Q1", "Q2", "Q3", "Q4"),
      tertile_right = TRUE,
      fi_t1 = "T1_FI",
      fi_t2 = "T2_FI",
      change_index_stem = "FI",
      change_index_display = "FI",
      table1_harmonize = FALSE,
      cohorts_xs = xs,
      cohorts_long = lg,
      # 协变量锁定：仅 CHARLS+ELSA；NHANES 外部验证套用锁定集
      cohorts_covariate_lock = c("CHARLS", "ELSA"),
      cohorts_main = c("CHARLS", "ELSA"),
      cohorts_pooled = c("CHARLS", "ELSA"),
      cohorts_validation = intersect("NHANES", xs),
      model1_locked = c("Gender", "Education")
    ))
  }

  pref_xs <- c("CHARLS", "ELSA", "HRS")
  xs <- if (length(xs_found)) {
    hit <- intersect(pref_xs, xs_found)
    if (length(hit)) hit else intersect(c("CHARLS", "ELSA", "HRS", "NHANES"), xs_found)
  } else pref_xs
  lg <- if (length(long_found)) intersect(c("CHARLS", "ELSA", "HRS"), long_found) else
    intersect(pref_xs, xs)
  list(
    kind = "hip",
    disease = "Hip_fracture",
    disease_code = "16",
    analysis_group = "Hip_Fracture",
    reference_group = "No_Fracture",
    index_var = "FI",
    index_display = "FI",
    disease_display = "Hip fracture",
    project_prefix = "Hip_Frailty_sens_",
    grouping = "tertile",
    grouping_labels = c("Q1", "Q2", "Q3"),
    tertile_right = TRUE,
    fi_t1 = "T1_FI",
    fi_t2 = "T2_FI",
    change_index_stem = "FI",
    change_index_display = "FI",
    table1_harmonize = TRUE,
    cohorts_xs = xs,
    cohorts_long = lg
  )
}

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

#' phase1 输出目录：优先 *_allages（髋部），否则 phase1_{db}
cross_lagged_phase1_dir <- function(study_root, db) {
  d1 <- file.path(study_root, paste0("phase1_", db, "_allages"))
  d2 <- file.path(study_root, paste0("phase1_", db))
  if (dir.exists(d1)) d1 else d2
}

#' Fig3 亚组锁定：同课题三库同一变量集、同一水平名；不含 Pooled
cross_lagged_fig3_lock <- function(meta) {
  meta <- meta %||% list()
  kind <- as.character(meta$kind %||% "hip")[1L]
  if (identical(kind, "circadian")) {
    # Age 是 ePWV 成分，不进亚组；Cancer 在 NHANES 无列，三库去掉才能列名一致
    # Alcohol_drinking：课题 config 在 data_clean 起整列删除，禁止 Fig3 lock 再从 D04 挂回
    return(list(
      vars = c(
        "Gender", "Education", "Marital_Status", "Smoking",
        "Hypertension", "Diabetes"
      ),
      age_cutoff = 70L,
      use_age_group = FALSE,
      index_var = as.character(meta$index_var %||% "ePWV")[1L],
      analysis_group = as.character(meta$analysis_group %||% "Circadian_Disorder")[1L],
      reference_group = as.character(meta$reference_group %||% "No_Disorder")[1L],
      outcome_column = "Disease_Group",
      level_order = list(
        Gender = c("Female", "Male"),
        Education = c("Below High school", "Above High school"),
        Marital_Status = c("Unmarried", "Married"),
        Smoking = c("Never", "Current"),
        Hypertension = c("No", "Yes"),
        Diabetes = c("No", "Yes")
      ),
      note = paste(
        "no Pooled;",
        "Age omitted (ePWV component);",
        "Cancer omitted (NHANES has no column);",
        "NHANES Education/Smoking attached from D04 by ID;",
        "Former smokers set to missing so Smoking is Never/Current like CHARLS/ELSA"
      )
    ))
  }
  t2dm <- if (identical(kind, "dementia")) "Diabetes" else "T2DM"
  list(
    vars = c(
      "Age_Group", "Gender", "Education", "Marital_Status", "Smoking",
      "Alcohol_drinking", "Hypertension", t2dm, "Cancer"
    ),
    age_cutoff = 70L,
    use_age_group = TRUE,
    index_var = as.character(meta$index_var %||% "FI")[1L],
    analysis_group = as.character(meta$analysis_group %||% "Hip_Fracture")[1L],
    reference_group = as.character(meta$reference_group %||% "No_Fracture")[1L],
    outcome_column = "Disease_Group",
    level_order = list(
      Age_Group = c("< 70", "\u2265 70"),
      Gender = c("Female", "Male"),
      Education = c("Below High school", "Above High school"),
      Marital_Status = c("Unmarried", "Married"),
      Smoking = c("Never", "Current"),
      Alcohol_drinking = c("No", "Yes"),
      Hypertension = c("No", "Yes"),
      T2DM = c("No", "Yes"),
      Diabetes = c("No", "Yes"),
      Cancer = c("No", "Yes")
    ),
    note = "no Pooled; Age_Group 70y; three single cohorts only"
  )
}

cross_lagged_find_baseline_rdata <- function(study_root, db) {
  cands <- c(
    file.path(study_root, "data/harmonized", sprintf("D04_%s_circadian_baseline.RData", db)),
    file.path(study_root, "data/harmonized", sprintf("D04_%s_hip_baseline.RData", db)),
    file.path(study_root, "data/harmonized", sprintf("D04_%s_baseline.RData", db))
  )
  extra <- Sys.glob(file.path(study_root, "data/harmonized", sprintf("D04_%s_*.RData", db)))
  extra <- extra[!grepl("Pooled|postvif", extra, ignore.case = TRUE)]
  hit <- unique(c(cands, extra))
  hit <- hit[file.exists(hit)]
  if (!length(hit)) NA_character_ else hit[[1L]]
}

#' 从课题基线表按 ID 补回亚组列，并统一 Education / Smoking 水平名
cross_lagged_attach_harmonize_fig3 <- function(data, study_root, db, lock) {
  data <- as.data.frame(data)
  vars <- as.character(lock$vars %||% character(0))
  if ("Smoking" %in% vars && !"Smoking" %in% names(data) && "Smoke" %in% names(data)) {
    data$Smoking <- data$Smoke
  }
  need <- setdiff(vars, names(data))
  src_path <- cross_lagged_find_baseline_rdata(study_root, db)
  if (length(need) && !is.na(src_path) && nzchar(src_path)) {
    e <- new.env(parent = emptyenv())
    ok <- tryCatch({ load(src_path, envir = e); TRUE }, error = function(err) FALSE)
    src <- NULL
    if (isTRUE(ok)) {
      for (nm in ls(e, all.names = FALSE)) {
        if (is.data.frame(e[[nm]])) { src <- e[[nm]]; break }
      }
    }
    if (!is.null(src)) {
      if ("Smoke" %in% names(src) && !"Smoking" %in% names(src)) src$Smoking <- src$Smoke
      take <- intersect(need, names(src))
      if (length(take)) {
        if ("ID" %in% names(data) && "ID" %in% names(src)) {
          m <- match(as.character(data$ID), as.character(src$ID))
          for (v in take) data[[v]] <- src[[v]][m]
        } else if (nrow(src) == nrow(data)) {
          for (v in take) data[[v]] <- src[[v]]
        }
      }
    }
  }
  if ("Education" %in% names(data)) {
    x <- trimws(as.character(data$Education))
    x[x %in% c("Higher education", "College and above", "College", "Above High school")] <-
      "Above High school"
    x[x %in% c("Non-higher education", "Less than high school", "Below High school")] <-
      "Below High school"
    x[!nzchar(x) | x %in% c("NA", "NaN")] <- NA_character_
    data$Education <- factor(x, levels = c("Below High school", "Above High school"))
  }
  if ("Smoking" %in% names(data)) {
    x <- trimws(as.character(data$Smoking))
    # 与 CHARLS/ELSA 二元 Never/Current 对齐：Former 不并入任一侧，记为缺失
    x[x %in% c("Former", "Ever", "Past", "Ex-smoker", "Ex smoker")] <- NA_character_
    x[x %in% c("No")] <- "Never"
    x[x %in% c("Yes")] <- "Current"
    x[!nzchar(x) | x %in% c("NA", "NaN")] <- NA_character_
    data$Smoking <- factor(x, levels = c("Never", "Current"))
  }
  for (vn in intersect(
    c("Alcohol_drinking", "Hypertension", "Diabetes", "T2DM", "Cancer",
      "Marital_Status", "Gender"),
    names(data)
  )) {
    v <- data[[vn]]
    if (is.factor(v) || is.character(v)) {
      data[[vn]] <- factor(trimws(as.character(v)))
    }
  }
  lo <- lock$level_order %||% list()
  for (vn in intersect(names(lo), names(data))) {
    present <- unique(trimws(as.character(stats::na.omit(data[[vn]]))))
    lev <- unique(c(intersect(as.character(lo[[vn]]), present), present))
    data[[vn]] <- factor(trimws(as.character(data[[vn]])), levels = lev)
  }
  data
}
