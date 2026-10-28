###############################################################################
#  cross_lagged_study_meta.R — 交叉滞后课题元数据
#  （自杀 CSSRS CLPM / 髋部 / 昼夜 / 痴呆）
#
#  供 phase_sensitivity、collect、出版清单共用。禁止在引擎里写死糖尿病。
###############################################################################

cross_lagged_study_is_circadian <- function(study_root) {
  f <- file.path(as.character(study_root)[1L], "config_long_panel.R")
  if (!file.exists(f)) return(FALSE)
  any(grepl("circadian_index_var|ePWV|Leisure_score", readLines(f, warn = FALSE)))
}

#' 从课题 config_long_panel.R 读取 .circadian_* 赋值（无文件则空 list）
cross_lagged_read_panel_assigns <- function(study_root) {
  f <- file.path(as.character(study_root)[1L], "config_long_panel.R")
  if (!file.exists(f)) return(list())
  e <- new.env(parent = baseenv())
  e$data_root <- file.path(as.character(study_root)[1L], "data")
  ok <- tryCatch({
    sys.source(f, envir = e, keep.source = FALSE)
    TRUE
  }, error = function(err) FALSE)
  if (!isTRUE(ok)) return(list())
  idx <- as.character(e$.circadian_index_var %||% "ePWV")[1L]
  grp <- as.character(e$.circadian_main_grouping %||% "quartile")[1L]
  dbs <- as.character(e$.circadian_dbs %||% c("CHARLS", "ELSA"))
  list(
    index_var = idx,
    grouping = grp,
    dbs = dbs,
    exposure_label = as.character(e$.circadian_exposure_label %||% idx)[1L],
    mediator_label = as.character(e$.circadian_mediator_label %||% "Frailty Index")[1L],
    outcome_label = as.character(e$.circadian_outcome_label %||% "Circadian disorder")[1L],
    change_index_stem = if (identical(idx, "Leisure_score")) idx else "FI",
    change_index_display = if (identical(idx, "Leisure_score")) {
      as.character(e$.circadian_exposure_label %||% "Leisure activity score")[1L]
    } else {
      "FI"
    },
    project_prefix = if (identical(idx, "Leisure_score")) {
      "Circadian_Leisure_sens_"
    } else {
      "Circadian_ePWV_sens_"
    },
    index_display = if (identical(idx, "Leisure_score")) {
      as.character(e$.circadian_exposure_label %||% "Leisure activity score")[1L]
    } else {
      "ePWV"
    },
    fig3_include_age = identical(idx, "Leisure_score"),
    covariate_lock_rule = as.character(e$.circadian_covariate_lock %||% "vif_screen")[1L],
    pooled_harmonize = as.character(e$.circadian_pooled_harmonize %||% "")[1L],
    pooled_index = as.character(e$.circadian_pooled_index %||% "")[1L]
  )
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

cross_lagged_study_is_suicide_cssrs <- function(study_root) {
  sr <- as.character(study_root)[1L]
  grepl("43_Suicide|suicide_cssrs|suicide_clpm", sr, ignore.case = TRUE) ||
    file.exists(file.path(sr, "config_suicide_clpm.R"))
}

#' 抑郁人群 × 高血压结局 × 虚弱交叉滞后
cross_lagged_study_is_depression_htn_frailty <- function(study_root) {
  sr <- as.character(study_root)[1L]
  grepl("22_depression|depression_htn|depression_cross-laged", sr, ignore.case = TRUE) ||
    file.exists(file.path(sr, "README_DEPRESSION_HTN_FRAILTY.txt")) ||
    file.exists(file.path(sr, "data/harmonized/D04_CHARLS_depression_htn_baseline.RData"))
}

#' AIP × FI × 肌少症（HRS+SHARE 同波横断）
cross_lagged_study_is_aip_sarcopenia <- function(study_root) {
  sr <- as.character(study_root)[1L]
  grepl("54_Sarcopenia|aip_sarcopenia|AIP.*[Ss]arcopenia", sr) ||
    file.exists(file.path(sr, "README_AIP_SARCOPENIA.txt")) ||
    file.exists(file.path(sr, "data/harmonized/D04_HRS_aip_sarcopenia_baseline.RData"))
}

#' 交叉滞后课题元数据
#'
#' @return list: kind, cohorts_xs, cohorts_long, index_var, grouping, labels, ...
cross_lagged_study_meta <- function(study_root) {
  study_root <- as.character(study_root)[1L]
  xs_found <- tryCatch(cross_lagged_discover_phase1_dbs(study_root), error = function(e) character(0))
  long_found <- tryCatch(cross_lagged_discover_long_dbs(study_root), error = function(e) character(0))

  # AIP×肌少症 须在 hip / depression 默认之前
  if (isTRUE(cross_lagged_study_is_aip_sarcopenia(study_root))) {
    # 交付：横断面 CHARLS+ELSA+HRS；纵向 change / CLPN 仅 CHARLS+ELSA（HRS 横断面）
    # SHARE 不进汇总
    pref_xs <- c("CHARLS", "ELSA", "HRS")
    pref_long <- c("CHARLS", "ELSA")
    xs <- if (length(xs_found)) {
      hit <- intersect(pref_xs, xs_found)
      if (length(hit)) hit else pref_xs
    } else pref_xs
    lg <- if (length(long_found)) {
      hit <- intersect(pref_long, long_found)
      if (length(hit)) hit else pref_long
    } else pref_long
    return(list(
      kind = "aip_sarcopenia",
      disease = "Sarcopenia",
      disease_code = "54",
      analysis_group = "Sarcopenia",
      reference_group = "No_Sarcopenia",
      index_var = "AIP_FI",
      index_display = "AIP × FI",
      disease_display = "Sarcopenia",
      project_prefix = "AIP_FI_Sarcopenia_sens_",
      # 主文 Table2 交付为 quintile；敏感性 logistic 跟主文
      grouping = "quintile",
      grouping_labels = c("Q1", "Q2", "Q3", "Q4", "Q5"),
      tertile_right = TRUE,
      fi_t1 = "T1_AIP_FI",
      fi_t2 = "T2_AIP_FI",
      change_index_stem = "AIP_FI",
      change_index_display = "AIP × FI",
      table1_harmonize = TRUE,
      cohorts_xs = xs,
      cohorts_long = lg,
      cohorts_covariate_lock = c("CHARLS", "ELSA", "HRS"),
      cohorts_pooled = character(0),
      # 中期 CHARLS Table2：M1=Age+Gender+Marital+Education；M2=+Hemoglobin
      # Hemoglobin 缺测走 MICE m=5 + Rubin（不删人）
      model1_locked = c("Age", "Gender", "Marital_Status", "Education"),
      model2_locked = c("Age", "Gender", "Marital_Status", "Education", "Hemoglobin"),
      covariate_lock_source = "midterm_charls_table2",
      covariate_lock_note = paste(
        "中期 CHARLS Model1=Age+Gender+Marital_Status+Education;",
        "Model2=+Hemoglobin；横断面三库，纵向 CHARLS+ELSA。"
      ),
      labels = list(
        exposure_label = "AIP × FI",
        mediator_label = "Frailty Index",
        outcome_label = "Sarcopenia"
      )
    ))
  }

  # depression×HTN×FI 须在 hip 默认之前
  if (isTRUE(cross_lagged_study_is_depression_htn_frailty(study_root))) {
    pref_xs <- c("CHARLS", "ELSA", "HRS")
    xs <- if (length(xs_found)) {
      hit <- intersect(pref_xs, xs_found)
      if (length(hit)) hit else pref_xs
    } else pref_xs
    lg <- if (length(long_found)) intersect(pref_xs, long_found) else xs
    # CHARLS 本课题不做纵向（见 LONGITUDINAL_NO_CHARLS.txt / 交付约定）
    if (file.exists(file.path(study_root, "LONGITUDINAL_NO_CHARLS.txt")) ||
        file.exists(file.path(study_root, "LONGITUDINAL_NO_CHARLS"))) {
      lg <- setdiff(lg, "CHARLS")
    } else {
      # 即使残留 phase3_long_CHARLS，抑郁×HTN 默认纵向仅 ELSA+HRS
      lg <- intersect(lg, c("ELSA", "HRS"))
    }
    return(list(
      kind = "depression_htn_frailty",
      disease = "Hypertension",
      disease_code = "22",
      analysis_group = "Hypertension",
      reference_group = "No_Hypertension",
      index_var = "FI",
      index_display = "FI",
      disease_display = "Hypertension",
      project_prefix = "Depression_HTN_Frailty_sens_",
      # 主文分位跟 logistic 闸门 4→3→2→5：本课题 CHARLS/ELSA/HRS/Pooled 均为 extend_quartile
      grouping = "quartile",
      grouping_labels = c("Q1", "Q2", "Q3", "Q4"),
      tertile_right = TRUE,
      fi_t1 = "T1_FI",
      fi_t2 = "T2_FI",
      change_index_stem = "FI",
      change_index_display = "FI",
      table1_harmonize = TRUE,
      cohorts_xs = xs,
      cohorts_long = lg,
      labels = list(
        exposure_label = "Frailty Index",
        mediator_label = "Depressive symptom score",
        outcome_label = "Hypertension"
      )
    ))
  }

  # suicide_cssrs 必须在 hip 默认之前（亦先于 dementia/circadian）
  if (isTRUE(cross_lagged_study_is_suicide_cssrs(study_root))) {
    return(list(
      kind = "suicide_cssrs",
      disease = "suicide_ideation_cssrs",
      disease_code = "43",
      analysis_group = "1",
      reference_group = "0",
      cohorts_xs = "outpatient",
      cohorts_long = "outpatient",
      index_var = "HAMD_Index",  # 占位；主分析不走分位闸门
      index_display = "HAMD_Index",
      disease_display = "C-SSRS item1 ideation",
      project_prefix = "Suicide_CSSRS_CLPM_",
      grouping = "binary",
      grouping_labels = c("0", "1"),
      change_index_stem = "HAMD_Index",
      change_index_display = "HAMD",
      table1_harmonize = FALSE,
      labels = list(
        exposure_label = "Mood/anxiety symptoms",
        outcome_label = "C-SSRS item1 ideation"
      )
    ))
  }

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
    .pa <- cross_lagged_read_panel_assigns(study_root)
    pref_xs <- c("CHARLS", "ELSA", "NHANES")
    pref_long <- as.character(.pa$dbs %||% c("CHARLS", "ELSA"))
    xs <- if (length(xs_found)) intersect(pref_xs, xs_found) else pref_long
    lg <- if (length(long_found)) intersect(pref_long, long_found) else
      intersect(pref_long, xs)
    grp <- as.character(.pa$grouping %||% "quartile")[1L]
    grp_labels <- if (identical(grp, "quartile")) {
      c("Q1", "Q2", "Q3", "Q4")
    } else if (identical(grp, "tertile")) {
      c("T1", "T2", "T3")
    } else {
      c("Q1", "Q2", "Q3", "Q4")
    }
    return(list(
      kind = "circadian",
      disease = "circadian_disorder",
      disease_code = "23",
      analysis_group = "Circadian_Disorder",
      reference_group = "No_Disorder",
      index_var = as.character(.pa$index_var %||% "ePWV")[1L],
      index_display = as.character(.pa$index_display %||% .pa$index_var %||% "ePWV")[1L],
      disease_display = "Circadian disorder",
      project_prefix = as.character(.pa$project_prefix %||% "Circadian_ePWV_sens_")[1L],
      grouping = grp,
      grouping_labels = grp_labels,
      tertile_right = TRUE,
      fi_t1 = "T1_FI",
      fi_t2 = "T2_FI",
      change_index_stem = as.character(.pa$change_index_stem %||% "FI")[1L],
      change_index_display = as.character(.pa$change_index_display %||% "FI")[1L],
      table1_harmonize = FALSE,
      cohorts_xs = xs,
      cohorts_long = lg,
      cohorts_covariate_lock = intersect(c("CHARLS", "ELSA"), xs),
      cohorts_main = intersect(c("CHARLS", "ELSA"), xs),
      cohorts_pooled = intersect(c("CHARLS", "ELSA"), xs),
      cohorts_validation = intersect("NHANES", xs),
      covariate_lock_rule = as.character(.pa$covariate_lock_rule %||% "vif_screen")[1L],
      pooled_harmonize = as.character(.pa$pooled_harmonize %||% "")[1L],
      pooled_index = as.character(.pa$pooled_index %||% "")[1L],
      # mv_sig_intersect：Model1 只从多因素显著交集里取，不再强制 Gender+Education
      model1_locked = if (identical(as.character(.pa$covariate_lock_rule %||% "")[1L], "mv_sig_intersect")) {
        character(0)
      } else {
        c("Gender", "Education")
      },
      fig3_include_age = isTRUE(.pa$fig3_include_age)
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

#' Pooled / 模板用的 phase1 config：优先 CHARLS，否则 meta$cohorts_xs 首个存在的
cross_lagged_phase1_template_config <- function(study_root, meta = NULL) {
  study_root <- as.character(study_root)[1L]
  pref <- c("CHARLS", "ELSA", "HRS", "SHARE", "NHANES", "CLHLS")
  if (!is.null(meta) && length(meta$cohorts_xs)) {
    pref <- unique(c(as.character(meta$cohorts_xs), pref))
  }
  for (db in pref) {
    f <- file.path(study_root, paste0("config_phase1_", db, ".R"))
    if (file.exists(f)) return(f)
  }
  stop("cross_lagged_phase1_template_config: 无可用 config_phase1_*.R in ", study_root,
       call. = FALSE)
}

#' Fig3 亚组锁定：同课题三库同一变量集、同一水平名；不含 Pooled
cross_lagged_fig3_lock <- function(meta) {
  meta <- meta %||% list()
  kind <- as.character(meta$kind %||% "hip")[1L]
  if (identical(kind, "circadian")) {
    idx <- as.character(meta$index_var %||% "ePWV")[1L]
    include_age <- isTRUE(meta$fig3_include_age) || identical(idx, "Leisure_score")
    # 年龄切点依据：老年队列常用 65（Leisure 暴露非 ePWV 成分时可进亚组）
    age_cut <- if (isTRUE(include_age)) 65L else 70L
    base_vars <- c(
      "Gender", "Education", "Marital_Status", "Smoking",
      "Hypertension", "Diabetes"
    )
    # Leisure 的结局包含高血压、糖尿病，这两项不进亚组
    if (identical(idx, "Leisure_score")) {
      base_vars <- setdiff(base_vars, c("Hypertension", "Diabetes", "T2DM"))
    }
    if (isTRUE(include_age)) base_vars <- c("Age_Group", base_vars)
    return(list(
      vars = base_vars,
      age_cutoff = age_cut,
      use_age_group = isTRUE(include_age),
      index_var = idx,
      analysis_group = as.character(meta$analysis_group %||% "Circadian_Disorder")[1L],
      reference_group = as.character(meta$reference_group %||% "No_Disorder")[1L],
      outcome_column = "Disease_Group",
      level_order = list(
        Age_Group = c("< 65", "\u2265 65"),
        Gender = c("Female", "Male"),
        Education = c("Below High school", "Above High school"),
        Marital_Status = c("Unmarried", "Married"),
        Smoking = c("Never", "Current"),
        Hypertension = c("No", "Yes"),
        Diabetes = c("No", "Yes")
      ),
      note = paste(
        "no Pooled;",
        if (isTRUE(include_age)) "Age_Group 65y (Leisure exposure);" else "Age omitted (ePWV component);",
        "Cancer omitted (NHANES has no column);",
        "NHANES Education/Smoking attached from D04 by ID;",
        "Former smokers set to missing so Smoking is Never/Current like CHARLS/ELSA"
      )
    ))
  }
  # 痴呆/抑郁×高血压/AIP×肌少症基线表用 Diabetes；髋部等用 T2DM
  t2dm <- if (identical(kind, "dementia") || identical(kind, "depression_htn_frailty") ||
               identical(kind, "aip_sarcopenia")) {
    "Diabetes"
  } else {
    "T2DM"
  }
  # 抑郁×高血压课题：高血压是结局，禁止进亚组分层
  # AIP×肌少症：身高体重进 SMI，亚组不用体测；结局相关不分层
  base_vars <- c(
    "Age_Group", "Gender", "Education", "Marital_Status", "Smoking",
    "Alcohol_drinking", "Hypertension", t2dm, "Cancer"
  )
  if (identical(kind, "depression_htn_frailty")) {
    base_vars <- setdiff(base_vars, "Hypertension")
  }
  if (identical(kind, "aip_sarcopenia")) {
    # SHARE 吸烟几乎全缺，亚组不锁 Smoking
    base_vars <- intersect(base_vars, c(
      "Age_Group", "Gender", "Education", "Marital_Status",
      "Alcohol_drinking", "Hypertension", "Diabetes", "Cancer"
    ))
  }
  list(
    vars = base_vars,
    age_cutoff = if (identical(kind, "depression_htn_frailty") || identical(kind, "aip_sarcopenia")) 65L else 70L,
    use_age_group = TRUE,
    index_var = as.character(meta$index_var %||% "FI")[1L],
    analysis_group = as.character(meta$analysis_group %||% "Hip_Fracture")[1L],
    reference_group = as.character(meta$reference_group %||% "No_Fracture")[1L],
    outcome_column = "Disease_Group",
    level_order = list(
      Age_Group = if (identical(kind, "depression_htn_frailty")) {
        c("< 65", "\u2265 65")
      } else {
        c("< 70", "\u2265 70")
      },
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
    note = if (identical(kind, "depression_htn_frailty")) {
      "depression pop; HTN=outcome excluded from subgroups; Age_Group 65y"
    } else {
      "no Pooled; Age_Group 70y; three single cohorts only"
    }
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
  # Diabetes / T2DM 互为别名（抑郁/痴呆基线常用 Diabetes）
  if ("T2DM" %in% vars && !"T2DM" %in% names(data) && "Diabetes" %in% names(data)) {
    data$T2DM <- data$Diabetes
  }
  if ("Diabetes" %in% vars && !"Diabetes" %in% names(data) && "T2DM" %in% names(data)) {
    data$Diabetes <- data$T2DM
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
