###############################################################################
#  cross_lagged_sensitivity.R — 发病敏感性：共病 / 完整病例 / ≤2 年发病过滤
#
#  口径（决策树硬默认）：
#    - 慢性共病：基线计数 ≥ chronic_min_count（默认 2）则剔除
#    - 完整病例：插补前 dabiao；对 index+结局+Model2 做 listwise complete.cases；
#      不做 MI；N 允许 ≤ AfterMI（与 AfterMI 同 N 不是目标）
#    - ≤2 年发病：首次发病年 − 基线年 ≤ exclude_event_within_years 则剔除
#    - competing_risk：占位，默认 FALSE（无死亡变量时不跑）
###############################################################################

cross_lagged_sens_default_chronic_stems <- function() {
  c("hibpe", "diabe", "cancre", "arthre", "lunge", "psyche", "memrye")
}

#' Dementia 主分析 C00 波次年（early-event / Change 对齐）
cross_lagged_sens_dementia_wave_years <- function(db) {
  switch(toupper(as.character(db)),
    HRS   = list(baseline = 2010L, fu = c(2012L, 2014L, 2016L)),
    SHARE = list(baseline = 2015L, fu = c(2017L, 2019L, 2021L)),
    CLHLS = list(baseline = 2008L, fu = c(2012L, 2014L)),
    ELSA  = list(baseline = 2008L, fu = 2014L),
    stop("unknown db: ", db, call. = FALSE)
  )
}

#' 短码 / 临床名 → 数据中实际列名
cross_lagged_sens_resolve_comorbid_cols <- function(df, stems = NULL) {
  stems <- as.character(stems %||% cross_lagged_sens_default_chronic_stems())
  alias <- list(
    hibpe = c("hibpe", "Hypertension", "hypertension", "HTN"),
    diabe = c("diabe", "T2DM", "Diabetes", "diabetes", "Diabetes_mellitus"),
    cancre = c("cancre", "Cancer", "cancer"),
    arthre = c("arthre", "Arthritis", "arthritis"),
    lunge = c("lunge", "Lung", "Lung_disease", "lung", "Chronic_lung_disease"),
    psyche = c("psyche", "Psychiatric", "psychiatric", "Psych"),
    memrye = c("memrye", "Memory", "memory", "Memory_disease", "Alzheimer")
  )
  nms <- names(df)
  out <- character(0)
  for (s in stems) {
    cands <- unique(c(s, alias[[s]] %||% s))
    # T1_ 前缀（long/wide）
    cands <- unique(c(cands, paste0("T1_", cands)))
    hit <- cands[cands %in% nms]
    if (length(hit)) out <- c(out, hit[[1L]])
  }
  unique(out)
}

#' 0/1 共病指示（缺失当 0，避免整行被 NA 吃掉）
.cross_lagged_sens_col_positive <- function(x) {
  if (is.null(x)) return(rep(0L, 0L))
  if (is.logical(x)) return(as.integer(x))
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    xl <- tolower(trimws(x))
    return(as.integer(xl %in% c("1", "yes", "y", "true", "positive")))
  }
  xx <- suppressWarnings(as.numeric(x))
  as.integer(!is.na(xx) & xx > 0)
}

cross_lagged_sens_comorbid_count <- function(df, stems = NULL) {
  cols <- cross_lagged_sens_resolve_comorbid_cols(df, stems)
  if (!length(cols)) return(rep(0L, nrow(df)))
  mat <- vapply(cols, function(nm) .cross_lagged_sens_col_positive(df[[nm]]), integer(nrow(df)))
  if (is.null(dim(mat))) return(as.integer(mat))
  as.integer(rowSums(mat, na.rm = TRUE))
}

#' 场景 A：剔除基线共病数 ≥ min_count
cross_lagged_sens_filter_exclude_chronic <- function(df, stems = NULL, min_count = 2L) {
  cnt <- cross_lagged_sens_comorbid_count(df, stems)
  keep <- cnt < as.integer(min_count)
  list(
    data = df[keep, , drop = FALSE],
    n_before = nrow(df),
    n_after = sum(keep),
    n_excluded = sum(!keep),
    comorbid_cols = cross_lagged_sens_resolve_comorbid_cols(df, stems),
    min_count = as.integer(min_count)
  )
}

#' 场景 B：未插补完整病例（listwise；不做 MI）
#'
#' 读插补前 dabiao 后调用。仅对分析变量
#' (`index_var` + `outcome_col` + Model2 covars) 做 `complete.cases`。
#' N 可小于 AfterMI；不以“与 AfterMI 同 N”为目标。
#' 完整病例：dabiao 缺暴露列时从 AfterMI 按 ID（其次行对齐）补上（ePWV 等指标常在 index 步才写出）
cross_lagged_sens_attach_index_from_imputed <- function(dab, study_root, db, index_var) {
  if (is.null(dab) || !nrow(dab)) return(dab)
  index_var <- as.character(index_var %||% "")[1L]
  if (!nzchar(index_var) || index_var %in% names(dab)) return(dab)
  imp <- tryCatch(cross_lagged_sens_load_imputed(study_root, db), error = function(e) NULL)
  if (is.null(imp) || !index_var %in% names(imp)) return(dab)
  if (!"ID" %in% names(dab) && "ID" %in% names(imp) && nrow(imp) == nrow(dab)) {
    dab$ID <- as.character(imp$ID)
  }
  if ("ID" %in% names(dab) && "ID" %in% names(imp)) {
    m <- match(as.character(dab$ID), as.character(imp$ID))
    dab[[index_var]] <- imp[[index_var]][m]
    return(dab)
  }
  if (nrow(imp) == nrow(dab)) dab[[index_var]] <- imp[[index_var]]
  dab
}

cross_lagged_sens_filter_complete_case <- function(df, covars, outcome_col = "Disease_Group",
                                                  index_var = "FI") {
  need <- unique(c(index_var, outcome_col, as.character(covars)))
  need <- need[need %in% names(df)]
  if (!length(need)) {
    return(list(data = df[0, , drop = FALSE], n_before = nrow(df), n_after = 0L,
                n_excluded = nrow(df), vars = character(0),
                rule = "listwise_on_analysis_vars_unimputed"))
  }
  ok <- stats::complete.cases(df[, need, drop = FALSE])
  list(
    data = df[ok, , drop = FALSE],
    n_before = nrow(df),
    n_after = sum(ok),
    n_excluded = sum(!ok),
    vars = need,
    rule = "listwise_on_analysis_vars_unimputed"
  )
}

#' 场景 C：剔除随访开始 within_years 年内发病者（保留更晚发病与未发病）
cross_lagged_sens_ids_early_event <- function(long_df, within_years = 2L,
                                             id_col = "ID", year_col = "year",
                                             event_cols = c("Disease", "Disease01", "Disease_Group"),
                                             baseline_year = NULL) {
  within_years <- as.integer(within_years)
  d <- as.data.frame(long_df)
  if (!id_col %in% names(d)) stop("early_event: 缺 ID 列", call. = FALSE)
  yc <- year_col
  if (!yc %in% names(d) && "Year" %in% names(d)) yc <- "Year"
  if (!yc %in% names(d)) stop("early_event: 缺 year/Year", call. = FALSE)
  ev <- event_cols[event_cols %in% names(d)]
  if (!length(ev)) stop("early_event: 缺结局列", call. = FALSE)
  d$.year <- suppressWarnings(as.integer(d[[yc]]))
  d$.ev <- 0L
  case_labels <- c(
    "1", "yes", "hip_fracture", "fracture", "hip fracture", "dementia",
    "circadian_disorder", "circadian disorder"
  )
  for (ec in ev) {
    x <- d[[ec]]
    if (is.factor(x)) x <- as.character(x)
    if (is.character(x)) {
      d$.ev <- pmax(d$.ev, as.integer(tolower(x) %in% case_labels))
    } else {
      d$.ev <- pmax(d$.ev, as.integer(suppressWarnings(as.numeric(x)) > 0))
    }
  }
  ids <- unique(as.character(d[[id_col]]))
  if (!is.null(baseline_year) && length(baseline_year) && is.finite(baseline_year[[1L]])) {
    base <- stats::setNames(rep(as.integer(baseline_year[[1L]]), length(ids)), ids)
  } else {
    base <- tapply(d$.year, d[[id_col]], function(z) min(z, na.rm = TRUE))
  }
  ev_years <- tapply(d$.year[d$.ev == 1L], d[[id_col]][d$.ev == 1L], function(z) {
    if (!length(z)) return(NA_integer_)
    min(z, na.rm = TRUE)
  })
  if (is.null(names(base))) names(base) <- ids
  early <- character(0)
  for (id in ids) {
    b <- as.integer(base[[id]])
    ey <- if (id %in% names(ev_years)) as.integer(ev_years[[id]]) else NA_integer_
    if (is.finite(b) && is.finite(ey) && (ey - b) <= within_years) early <- c(early, id)
  }
  unique(as.character(early))
}

cross_lagged_sens_filter_exclude_early_event <- function(df, early_ids, id_col = "ID") {
  if (!id_col %in% names(df)) {
    rn <- rownames(df)
    if (!is.null(rn) && length(rn) == nrow(df) &&
        !identical(rn, as.character(seq_len(nrow(df))))) {
      df[[id_col]] <- as.character(rn)
    }
  }
  if (!id_col %in% names(df)) stop("缺 ID 列", call. = FALSE)
  ids <- as.character(df[[id_col]])
  drop <- ids %in% as.character(early_ids)
  list(
    data = df[!drop, , drop = FALSE],
    n_before = nrow(df),
    n_after = sum(!drop),
    n_excluded = sum(drop),
    early_ids = early_ids
  )
}

#' 固定补充表文件名
cross_lagged_sens_table_basename <- function(scenario, kind, db = NULL,
                                             index_display = "FI",
                                             disease_display = "Hip fracture",
                                             grouping = "tertile",
                                             change_index_display = NULL) {
  # kind: baseline | logistic | change | change_twowave
  map <- list(
    exclude_chronic_ge2 = list(
      baseline = "S9", logistic = "S10", change = "S11", change_twowave = "S11.1",
      tag = "Sensitivity exclude chronic ge2"
    ),
    complete_case = list(
      baseline = "S12", logistic = "S13", change = "S14", change_twowave = "S14.1",
      tag = sprintf(
        "Sensitivity complete case unimputed listwise"
      )
    ),
    exclude_event_le_2y = list(
      baseline = "S15", logistic = "S16", change = "S17", change_twowave = "S17.1",
      tag = "Sensitivity exclude event within 2y"
    ),
    external_validation = list(
      baseline = "S18", logistic = "S19",
      tag = "External validation locked covariates CHARLS+ELSA"
    )
  )
  sc <- map[[scenario]]
  if (is.null(sc)) stop("未知敏感性场景: ", scenario, call. = FALSE)
  num <- sc[[kind]]
  tag <- sc$tag
  ch_disp <- change_index_display %||% index_display
  if (kind %in% c("change", "change_twowave")) {
    change_title <- sprintf("Mean %s and %s change", ch_disp, ch_disp)
    title <- sprintf("Table %s. %s — Change analysis %s", num, tag, change_title)
    return(paste0(title, ".xlsx"))
  }
  if (is.null(db) || !nzchar(db)) stop("baseline/logistic 需要 db", call. = FALSE)
  if (identical(kind, "baseline")) {
    return(sprintf(
      "Table %s-%s. %s — Baseline characteristics of %s.xlsx",
      num, db, tag, disease_display
    ))
  }
  if (identical(kind, "logistic")) {
    grp <- as.character(grouping %||% "tertile")[1L]
    return(sprintf(
      "Table %s-%s. %s — Logistic regression %s and %s - %s (GLM).xlsx",
      num, db, tag, index_display, disease_display, grp
    ))
  }
  stop("未知 kind: ", kind, call. = FALSE)
}

cross_lagged_sens_normalize_disease_group <- function(df, case_label = "Dementia",
                                                     control_label = "Normal") {
  d <- as.data.frame(df)
  if ("Disease_Group" %in% names(d) && any(d$Disease_Group %in% c(case_label, control_label), na.rm = TRUE))
    return(d)
  if (!"Disease" %in% names(d)) return(d)
  x <- d$Disease
  if (is.factor(x)) x <- as.character(x)
  if (is.numeric(x) || is.logical(x)) {
    d$Disease_Group <- ifelse(as.integer(x) == 1L, case_label, control_label)
  } else {
    xl <- as.character(x)
    d$Disease_Group <- ifelse(tolower(xl) %in% c("dementia", "1", "yes"), case_label, control_label)
  }
  d
}

cross_lagged_sens_db_aliases <- function(db) {
  db <- as.character(db)
  unique(c(db, toupper(db), tolower(db),
           if (toupper(db) == "SHARE") c("share", "SHARE"),
           if (toupper(db) == "CLHLS") c("clhls", "CLHLS", "Clhls")))
}

.cross_lagged_sens_first_existing <- function(candidates) {
  hits <- candidates[file.exists(candidates)]
  if (length(hits)) hits[[1L]] else NULL
}

.cross_lagged_sens_load_rdata_df <- function(f, prefer = c("data_imp", "dabiao", "object")) {
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  for (nm in prefer) {
    if (nm %in% ls(e)) return(as.data.frame(e[[nm]]))
  }
  as.data.frame(e[[ls(e)[1L]]])
}

.cross_lagged_sens_dementia_aftermi_path <- function(study_root, db) {
  root <- file.path(study_root, "data/Step01_RawData")
  .cross_lagged_sens_first_existing(vapply(
    cross_lagged_sens_db_aliases(db),
    function(a) file.path(root, paste0("D01_AfterMI_Data_", a, ".RData")),
    character(1)
  ))
}

.cross_lagged_sens_dementia_dabiao_path <- function(study_root, db) {
  root <- file.path(study_root, "data/Step01_RawData")
  # 优先 D01_dabiao_{db}.RData（与 AfterMI 同 ID）；排除 *_1106 等扩样草稿
  cands <- character(0)
  for (a in cross_lagged_sens_db_aliases(db)) {
    cands <- c(
      cands,
      file.path(root, paste0("D01_dabiao_", a, ".RData")),
      file.path(root, paste0("D04_dabiao_", a, ".RData"))
    )
  }
  cands <- unique(cands)
  cands <- cands[!grepl("_1106", basename(cands), fixed = TRUE)]
  .cross_lagged_sens_first_existing(cands)
}

.cross_lagged_sens_dementia_long_path <- function(study_root, db) {
  root <- file.path(study_root, "data/Step01_RawData")
  .cross_lagged_sens_first_existing(vapply(
    cross_lagged_sens_db_aliases(db),
    function(a) file.path(root, paste0("D05_long_", a, ".RData")),
    character(1)
  ))
}

.cross_lagged_sens_load_step05_wide_n <- function(study_root, db, n = 1L) {
  n <- as.integer(n)[1L]
  root <- file.path(study_root, "code/Step05_Change")
  f <- .cross_lagged_sens_first_existing(vapply(
    cross_lagged_sens_db_aliases(db),
    function(a) file.path(root, paste0(a, "_wide", n, ".RData")),
    character(1)
  ))
  if (is.null(f)) return(NULL)
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  nms <- ls(e)
  for (a in cross_lagged_sens_db_aliases(db)) {
    wn <- paste0(a, "_wide", n)
    if (wn %in% nms) return(as.data.frame(e[[wn]]))
  }
  for (nm in nms) {
    if (is.data.frame(e[[nm]])) return(as.data.frame(e[[nm]]))
  }
  NULL
}

cross_lagged_sens_load_wide <- function(study_root, db) {
  .cross_lagged_sens_load_step05_wide_n(study_root, db, 1L)
}

cross_lagged_sens_load_wide2 <- function(study_root, db) {
  .cross_lagged_sens_load_step05_wide_n(study_root, db, 2L)
}

#' long 基线波：优先 wave==1，否则 year==baseline_year / 最早年
.cross_lagged_sens_long_baseline_rows <- function(long_all, baseline_year = NULL) {
  if (is.null(long_all) || !is.data.frame(long_all) || !nrow(long_all)) return(NULL)
  d <- as.data.frame(long_all)
  if ("wave" %in% names(d)) {
    wv <- suppressWarnings(as.integer(d$wave))
    hit <- which(!is.na(wv) & wv == 1L)
    if (!length(hit)) hit <- which(as.character(d$wave) == "1")
    if (length(hit)) return(d[hit, , drop = FALSE])
  }
  if ("year" %in% names(d)) {
    yy <- suppressWarnings(as.numeric(d$year))
    if (!is.null(baseline_year) && length(baseline_year)) {
      by <- as.numeric(baseline_year)[1L]
      hit <- which(!is.na(yy) & yy == by)
      if (length(hit)) return(d[hit, , drop = FALSE])
    }
    ymin <- suppressWarnings(min(yy, na.rm = TRUE))
    if (is.finite(ymin)) {
      hit <- which(!is.na(yy) & yy == ymin)
      if (length(hit)) return(d[hit, , drop = FALSE])
    }
  }
  NULL
}

#' Dementia Step05 wide1 连续性补齐：ID（long wave1 行对齐）+ T2_Disease/T2_time（wide2）
.cross_lagged_sens_prepare_dementia_wide <- function(wide, long_all, study_root, db) {
  if (is.null(wide) || !is.data.frame(wide)) return(wide)
  w <- as.data.frame(wide)

  if (!"ID" %in% names(w) && !is.null(long_all) && "ID" %in% names(long_all)) {
    w1 <- .cross_lagged_sens_long_baseline_rows(long_all)
    if (!is.null(w1) && nrow(w1) == nrow(w)) {
      # 可选 Age 校验：T1_Age 与 wave1 Age 应对齐（允许全 NA 跳过）
      age_ok <- TRUE
      if ("Age" %in% names(w1) && "T1_Age" %in% names(w)) {
        a1 <- suppressWarnings(as.numeric(w1$Age))
        a2 <- suppressWarnings(as.numeric(w$T1_Age))
        both <- !is.na(a1) & !is.na(a2)
        if (any(both)) age_ok <- isTRUE(all.equal(a1[both], a2[both]))
      }
      if (age_ok) w$ID <- w1$ID
    }
  }

  if ((!("T2_Disease" %in% names(w)) || !("T2_time" %in% names(w)) ||
       !("T2_Age" %in% names(w)) || !("T2_Alcohol_drinking" %in% names(w))) &&
      !missing(study_root) && !is.null(study_root)) {
    w2 <- tryCatch(cross_lagged_sens_load_wide2(study_root, db), error = function(e) NULL)
    if (!is.null(w2) && nrow(w2) == nrow(w)) {
      for (nm in c("T2_Disease", "T2_time", "T2_Age", "T2_Education",
                   "T2_Alcohol_drinking", "T2_Gender",
                   "mean_Index", "mean_Index_q3", "Index_change", "Index_change_q3")) {
        if (!(nm %in% names(w)) && nm %in% names(w2)) w[[nm]] <- w2[[nm]]
      }
    }
  }

  if (!("T2_Disease_Group" %in% names(w)) && "T2_Disease" %in% names(w)) {
    x <- w$T2_Disease
    if (is.factor(x)) x <- as.character(x)
    if (is.numeric(x) || is.logical(x)) {
      w$T2_Disease_Group <- ifelse(as.integer(x) == 1L, "Dementia", "Normal")
    } else {
      xl <- as.character(x)
      w$T2_Disease_Group <- ifelse(
        tolower(xl) %in% c("dementia", "1", "yes"), "Dementia", "Normal"
      )
    }
  }
  w
}

.cross_lagged_sens_aftermi_path <- function(study_root, db) {
  p1 <- if (exists("cross_lagged_phase1_dir", mode = "function")) {
    cross_lagged_phase1_dir(study_root, db)
  } else {
    cands <- c(
      file.path(study_root, paste0("phase1_", db, "_allages")),
      file.path(study_root, paste0("phase1_", db))
    )
    hit <- cands[dir.exists(cands)]
    if (length(hit)) hit[[1L]] else cands[[1L]]
  }
  hits <- c(
    file.path(p1, "step03_imputation", "D01_AfterMI_Data.RData"),
    file.path(p1, "step05_imputation", "D01_AfterMI_Data.RData"),
    Sys.glob(file.path(p1, "step*", "D01_AfterMI_Data.RData"))
  )
  .cross_lagged_sens_first_existing(unique(hits))
}

.cross_lagged_sens_attach_id <- function(d, study_root, db) {
  if ("ID" %in% names(d)) return(d)
  # AfterMI 常把 ID 写成行名（strip_id_columns_after_imputation）
  rn <- rownames(d)
  if (!is.null(rn) && length(rn) == nrow(d) &&
      !identical(rn, as.character(seq_len(nrow(d))))) {
    d$ID <- as.character(rn)
    return(d)
  }
  dab <- tryCatch(cross_lagged_sens_load_dabiao(study_root, db), error = function(e) NULL)
  if (!is.null(dab) && nrow(dab) == nrow(d) && "ID" %in% names(dab)) {
    d$ID <- as.character(dab$ID)
  }
  d
}

cross_lagged_sens_load_imputed <- function(study_root, db) {
  f <- .cross_lagged_sens_aftermi_path(study_root, db)
  if (!is.null(f)) {
    e <- new.env(parent = emptyenv())
    load(f, envir = e)
    d <- if ("object" %in% ls(e)) as.data.frame(e$object) else if ("dabiao" %in% ls(e)) {
      as.data.frame(e$dabiao)
    } else {
      as.data.frame(e[[ls(e)[1L]]])
    }
    return(.cross_lagged_sens_attach_id(d, study_root, db))
  }
  f2 <- .cross_lagged_sens_dementia_aftermi_path(study_root, db)
  if (is.null(f2)) stop("缺插补后数据: phase1_", db, " / D01_AfterMI_Data.RData", call. = FALSE)
  d <- .cross_lagged_sens_load_rdata_df(f2, prefer = c("data_imp", "dabiao", "object"))
  d <- .cross_lagged_sens_attach_id(d, study_root, db)
  cross_lagged_sens_normalize_disease_group(d)
}

cross_lagged_sens_load_dabiao <- function(study_root, db) {
  harm <- file.path(study_root, "data/harmonized")
  cands <- c(
    file.path(harm, paste0("D04_", db, "_hip_baseline.RData")),
    file.path(harm, paste0("D04_", db, "_circadian_baseline.RData")),
    Sys.glob(file.path(harm, paste0("D04_", db, "_*_baseline.RData")))
  )
  cands <- unique(cands[!grepl("Pooled", basename(cands), ignore.case = TRUE)])
  f <- .cross_lagged_sens_first_existing(cands)
  if (!is.null(f)) {
    e <- new.env(parent = emptyenv())
    load(f, envir = e)
    if (!"dabiao" %in% ls(e)) stop("RData 无 dabiao: ", f, call. = FALSE)
    return(as.data.frame(e$dabiao))
  }
  f2 <- .cross_lagged_sens_dementia_dabiao_path(study_root, db)
  if (is.null(f2)) stop("缺 dabiao: D04_", db, "_*_baseline.RData", call. = FALSE)
  d <- .cross_lagged_sens_load_rdata_df(f2, prefer = c("data_imp", "dabiao", "object"))
  cross_lagged_sens_normalize_disease_group(d)
}

cross_lagged_sens_load_long <- function(study_root, db) {
  f <- file.path(study_root, paste0("phase3_long_", db),
                 paste0("D05_long_", db, ".RData"))
  if (file.exists(f)) {
    e <- new.env(parent = emptyenv())
    load(f, envir = e)
    return(list(
      long_all = if (!is.null(e$long_all)) as.data.frame(e$long_all) else NULL,
      wide = if (!is.null(e$wide)) as.data.frame(e$wide) else e$wide_clpn,
      env = e
    ))
  }
  f2 <- .cross_lagged_sens_dementia_long_path(study_root, db)
  if (is.null(f2)) stop("缺纵向: ", f, call. = FALSE)
  e <- new.env(parent = emptyenv())
  load(f2, envir = e)
  long_all <- NULL
  for (a in cross_lagged_sens_db_aliases(db)) {
    ln <- paste0(a, "_long")
    if (ln %in% ls(e)) {
      long_all <- as.data.frame(e[[ln]])
      break
    }
  }
  if (is.null(long_all) && "long_all" %in% ls(e)) long_all <- as.data.frame(e$long_all)
  wide <- cross_lagged_sens_load_wide(study_root, db)
  # Dementia Step05: wide1 无 ID/T2_Disease → 行对齐补齐（与主分析 long/wide2 连续）
  wide <- .cross_lagged_sens_prepare_dementia_wide(wide, long_all, study_root, db)
  list(long_all = long_all, wide = wide, env = e)
}

.cross_lagged_sens_parse_lock_lines <- function(ln) {
  m1 <- character(0)
  m2 <- character(0)
  g1 <- grep("^Model1=", ln, value = TRUE)
  g2 <- grep("^Model2_single=", ln, value = TRUE)
  if (!length(g2)) g2 <- grep("^Model2=", ln, value = TRUE)
  .split_vars <- function(s) {
    x <- trimws(unlist(strsplit(s, "\\+|,")))
    x[nzchar(x)]
  }
  if (length(g1)) m1 <- .split_vars(sub("^Model1=", "", g1[[1]]))
  if (length(g2)) m2 <- .split_vars(sub("^Model2(_single)?=", "", g2[[1]]))
  list(m1 = m1, m2 = m2)
}

cross_lagged_sens_read_lock <- function(study_root) {
  m1 <- "Age"
  m2 <- c("Age", "Alcohol_drinking")
  acc <- file.path(study_root, "phase3_relock_acceptance.txt")
  lockf <- file.path(study_root, "phase2_Pooled", "locked_covariates.txt")
  parsed <- NULL
  if (file.exists(acc)) {
    parsed <- .cross_lagged_sens_parse_lock_lines(readLines(acc, warn = FALSE))
  } else if (file.exists(lockf)) {
    parsed <- .cross_lagged_sens_parse_lock_lines(readLines(lockf, warn = FALSE))
  }
  if (!is.null(parsed) && length(parsed$m1)) m1 <- parsed$m1
  if (!is.null(parsed) && length(parsed$m2)) m2 <- parsed$m2
  if (length(m2) <= 1L && exists("cross_lagged_resolve_covariate_lock", mode = "function")) {
    meta <- if (exists("cross_lagged_study_meta", mode = "function")) {
      tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
    } else NULL
    lock <- tryCatch(
      cross_lagged_resolve_covariate_lock(study_root, meta),
      error = function(e) NULL
    )
    if (!is.null(lock)) {
      if (length(lock$model1)) m1 <- lock$model1
      if (length(lock$model2)) m2 <- lock$model2
    }
  }
  list(model1 = m1, model2 = m2, model2_pooled = unique(c(m2, "Country")))
}

#' 把 xlsx 表内标题（首个非空单元格，通常 A1）改成与文件名一致（去 .xlsx）
cross_lagged_sens_relabel_xlsx_title <- function(path, title = NULL) {
  path <- as.character(path)[1L]
  if (!nzchar(path) || !file.exists(path)) return(invisible(FALSE))
  if (is.null(title) || !nzchar(as.character(title)[1L])) {
    title <- sub("\\.xlsx$", "", basename(path), ignore.case = TRUE)
  } else {
    title <- as.character(title)[1L]
  }
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    warning("cross_lagged_sens_relabel_xlsx_title: 需要 openxlsx", call. = FALSE)
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    wb <- openxlsx::loadWorkbook(path)
    sheets <- openxlsx::getSheetNames(path)
    if (!length(sheets)) return(FALSE)
    sh <- sheets[[1L]]
    # 找标题单元格：优先 A1；若空则扫首行/首列第一个非空
    cur <- tryCatch(openxlsx::read.xlsx(path, sheet = 1L, colNames = FALSE,
                                        rows = 1L, cols = 1L),
                    error = function(e) NULL)
    openxlsx::writeData(wb, sheet = sh, x = title, startCol = 1L, startRow = 1L,
                        colNames = FALSE)
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
    TRUE
  }, error = function(e) {
    warning("relabel title failed for ", path, ": ", conditionMessage(e), call. = FALSE)
    FALSE
  })
  invisible(isTRUE(ok))
}

#' 批量：sensitivity / summary 下 S9–S17.1 表内标题对齐文件名
cross_lagged_sens_relabel_sensitivity_titles <- function(study_root) {
  roots <- c(
    file.path(study_root, "sensitivity"),
    file.path(study_root, "summary_result", "table")
  )
  n <- 0L
  for (root in roots) {
    if (!dir.exists(root)) next
    files <- list.files(
      root, pattern = "^Table S(9|1[0-7])(\\.1)?[-.].*\\.xlsx$",
      full.names = TRUE, recursive = TRUE, ignore.case = TRUE
    )
    for (f in files) {
      if (cross_lagged_sens_relabel_xlsx_title(f)) n <- n + 1L
    }
  }
  n
}

#' 从目录中挑最新 Table 1 xlsx 并复制为固定名
cross_lagged_sens_promote_table1 <- function(tables_dir, dest_path) {
  hits <- list.files(tables_dir, pattern = "^Table 1.*\\.xlsx$", full.names = TRUE)
  if (!length(hits)) {
    hits <- list.files(tables_dir, pattern = "Baseline characteristics.*\\.xlsx$",
                       full.names = TRUE)
  }
  if (!length(hits)) return(FALSE)
  info <- file.info(hits)
  src <- rownames(info)[which.max(info$mtime)]
  dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest_path, overwrite = TRUE)
  cross_lagged_sens_relabel_xlsx_title(dest_path)
  invisible(TRUE)
}
