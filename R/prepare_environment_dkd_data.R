###############################################################################
#  prepare_environment_dkd_data.R — DKD × 环境 VOC 标准 Data/nhanes 合并
#
#  输入（固定约定，与 Data/nhanes/ 目录一致）:
#    D02_data.RData (data) + D02_environment_data.RData (environment_data)
#    D01_baseline_NHANES*.RData (baseline) → WTMEC* / Source_File
#    可选 D01_data.RData → Gender
#  输出: EnvResult + voc_columns 向量
###############################################################################

prepare_environment_dkd_load_cohort_filter <- function(nhanes_dir, cfg) {
  f <- cfg$cohort_filter_file %||% NULL
  if (is.null(f) || !nzchar(as.character(f)[1L])) return(NULL)
  path <- as.character(f)[1L]
  if (!is_absolute_path(path)) path <- file.path(nhanes_dir, path)
  if (!file.exists(path)) {
    stop("prepare_environment_dkd_data: cohort_filter_file 不存在: ", path, call. = FALSE)
  }
  obj_name <- as.character(cfg$cohort_filter_obj %||% "data_imp")[1L]
  id_col   <- as.character(cfg$cohort_id_col %||% "SEQN")[1L]
  e <- new.env()
  load(path, envir = e)
  if (!exists(obj_name, envir = e, inherits = FALSE)) {
    stop("prepare_environment_dkd_data: ", path, " 缺少对象 ", obj_name, call. = FALSE)
  }
  d <- get(obj_name, envir = e)
  if (!is.data.frame(d)) stop("cohort_filter 对象不是 data.frame", call. = FALSE)
  if (!id_col %in% names(d)) {
    stop("cohort_filter 缺少 ID 列 ", id_col, ": ", path, call. = FALSE)
  }
  ids <- unique(as.numeric(as.character(d[[id_col]])))
  ids <- ids[is.finite(ids)]
  if (!length(ids)) stop("cohort_filter SEQN 为空", call. = FALSE)
  list(ids = ids, path = path, obj = obj_name, id_col = id_col)
}

prepare_environment_dkd_load_env_weights <- function(nhanes_dir, cfg) {
  f <- cfg$env_weight_file %||% NULL
  if (is.null(f) || !nzchar(as.character(f)[1L])) return(NULL)
  path <- as.character(f)[1L]
  if (!is_absolute_path(path)) path <- file.path(nhanes_dir, path)
  if (!file.exists(path)) {
    stop("prepare_environment_dkd_data: env_weight_file 不存在: ", path, call. = FALSE)
  }
  obj_name <- as.character(cfg$env_weight_obj %||% "df")[1L]
  wt_col   <- as.character(cfg$env_weight_col %||% "WTSA2YR")[1L]
  id_col   <- as.character(cfg$env_weight_id_col %||% "SEQN")[1L]
  e <- new.env()
  load(path, envir = e)
  if (!exists(obj_name, envir = e, inherits = FALSE)) {
    stop("prepare_environment_dkd_data: ", path, " 缺少对象 ", obj_name, call. = FALSE)
  }
  d <- get(obj_name, envir = e)
  if (!is.data.frame(d)) stop("env_weight 对象不是 data.frame", call. = FALSE)
  if (!all(c(id_col, wt_col) %in% names(d))) {
    stop(
      "env_weight 缺少列 (需要 ", id_col, ", ", wt_col, "): ", path,
      call. = FALSE
    )
  }
  out <- unique(data.frame(
    SEQN = as.numeric(as.character(d[[id_col]])),
    WTSA2YR = as.numeric(d[[wt_col]]),
    stringsAsFactors = FALSE
  ))
  out <- out[is.finite(out$SEQN), , drop = FALSE]
  attr(out, "source_path") <- path
  out
}

prepare_environment_dkd_apply_pooled_weight <- function(df, wt2_col, wt_col = "new_Weight",
                                                        source_file_col = "Source_File",
                                                        fallback_wt2_col = "WTMEC2YR") {
  if (!source_file_col %in% names(df)) {
    stop("缺少 Source_File，无法计算 pooled ", wt_col, call. = FALSE)
  }
  if (!wt2_col %in% names(df)) {
    stop("缺少权重列 ", wt2_col, call. = FALSE)
  }
  cycles <- unique(as.character(df[[source_file_col]]))
  cycles <- cycles[nzchar(cycles) & !is.na(cycles)]
  num_cycles <- length(cycles)
  if (num_cycles < 1L) stop("Source_File 无有效周期", call. = FALSE)
  df[[wt_col]] <- as.numeric(df[[wt2_col]]) / num_cycles
  if (nzchar(fallback_wt2_col) && fallback_wt2_col %in% names(df)) {
    miss <- !is.finite(df[[wt_col]]) | df[[wt_col]] <= 0
    fb <- as.numeric(df[[fallback_wt2_col]]) / num_cycles
    n_fb <- sum(miss & is.finite(fb) & fb > 0, na.rm = TRUE)
    if (n_fb > 0L) {
      df[[wt_col]][miss] <- fb[miss]
      cli::cli_alert_warning(
        "{wt_col}: {n_fb} 行 {wt2_col} 缺失/无效，回退 {fallback_wt2_col}/周期数"
      )
    }
  }
  df
}

# WTSA2YR 无效时：fallback=FALSE 则剔除；require_env_weight=TRUE 且 fallback=TRUE 时允许 WTMEC 兜底
prepare_environment_filter_env_weight_rows <- function(df, cfg = list()) {
  wt_col <- as.character(cfg$env_weight_col %||% "WTSA2YR")[1L]
  use_fb <- isTRUE(cfg$env_weight_fallback_wtmec %||% TRUE)
  if (!wt_col %in% names(df)) return(df)

  wtsa_ok <- is.finite(df[[wt_col]]) & df[[wt_col]] > 0

  if (!use_fb) {
    if (any(!wtsa_ok)) {
      cli::cli_alert_warning(
        "环境权重: 剔除无有效 {wt_col} 的 {sum(!wtsa_ok)} 人（不回退 WTMEC2YR）"
      )
      df <- df[wtsa_ok, , drop = FALSE]
    }
    return(df)
  }

  if (isTRUE(cfg$require_env_weight %||% FALSE)) {
    wmec_ok <- "WTMEC2YR" %in% names(df) &
      is.finite(df$WTMEC2YR) & df$WTMEC2YR > 0
    keep <- wtsa_ok | wmec_ok
    if (any(!keep)) {
      cli::cli_alert_warning(
        "require_env_weight: 剔除无 WTSA2YR 且无 WTMEC2YR 的 {sum(!keep)} 人"
      )
      df <- df[keep, , drop = FALSE]
    }
    n_no_wtsa <- sum(!wtsa_ok & keep)
    if (n_no_wtsa > 0L) {
      cli::cli_alert_info(
        "require_env_weight: {n_no_wtsa} 人无 WTSA2YR，将用 WTMEC2YR 计算 new_Weight"
      )
    }
  }
  df
}

prepare_environment_dkd_load_baseline_survey <- function(dir_path, pattern = "baseline.*NHANES.*\\.RData$") {
  cands <- list.files(dir_path, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  if (!length(cands)) {
    stop(
      "prepare_environment_dkd_data: 未找到 baseline NHANES RData（pattern=",
      pattern, "）。", call. = FALSE
    )
  }
  path <- cands[1L]
  e <- new.env()
  load(path, envir = e)
  obj <- if (exists("baseline", envir = e, inherits = FALSE)) "baseline" else ls(e)[1L]
  bl <- get(obj, envir = e)
  if (!is.data.frame(bl)) stop("baseline 不是 data.frame: ", path, call. = FALSE)

  id_col <- if ("SEQN" %in% names(bl)) "SEQN" else if ("ID" %in% names(bl)) "ID" else {
    stop("baseline 缺少 SEQN/ID: ", path, call. = FALSE)
  }
  want <- c(
    "WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTINT4YR",
    "WTSAF2YR", "WTSAF4YR", "SDMVPSU", "SDMVSTRA",
    "Source_File", "SDDSRVYR", "Gender"
  )
  keep <- intersect(want, names(bl))
  if (!"WTMEC2YR" %in% keep) stop("baseline 缺少 WTMEC2YR: ", path, call. = FALSE)
  if (!"Source_File" %in% keep) stop("baseline 缺少 Source_File: ", path, call. = FALSE)

  bl[[id_col]] <- as.numeric(as.character(bl[[id_col]]))
  bl <- unique(bl[, c(id_col, keep), drop = FALSE])
  names(bl)[names(bl) == id_col] <- "SEQN"
  attr(bl, "source_path") <- path
  bl
}

prepare_environment_dkd_ensure_outcome_group <- function(d, cfg = list()) {
  prj <- cfg$project %||% list()
  analysis_grp <- as.character(prj$analysis_group %||% "DKD")[1L]
  reference_grp <- as.character(prj$reference_group %||% "Never DKD")[1L]
  outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Group")[1L]
  outcome_src <- as.character(
    (cfg$data %||% list())$outcome_source_column %||%
      cfg$outcome_source_column %||% ""
  )[1L]

  if (nzchar(outcome_src) && outcome_src %in% names(d)) {
    src <- trimws(as.character(d[[outcome_src]]))
    pos <- src %in% c("Yes", "yes", "YES", "1", "1.0", "TRUE", "True")
    neg <- src %in% c("No", "no", "NO", "0", "0.0", "FALSE", "False")
    d[[outcome_col]] <- NA_character_
    d[[outcome_col]][pos] <- analysis_grp
    d[[outcome_col]][neg] <- reference_grp
    n_na <- sum(is.na(d[[outcome_col]]))
    if (n_na > 0L) {
      cli::cli_alert_warning(
        "结局 {outcome_src}: 剔除 {n_na} 行无效/缺失结局"
      )
      d <- d[!is.na(d[[outcome_col]]), , drop = FALSE]
    }
    cli::cli_alert_info(
      "结局列 {outcome_col}: {outcome_src} → '{reference_grp}'/'{analysis_grp}'（n={nrow(d)}）"
    )
    return(d)
  }

  if (outcome_col %in% names(d)) {
    vals <- unique(stats::na.omit(d[[outcome_col]]))
    if (length(vals) && !(all(as.numeric(vals) %in% c(0, 1), na.rm = TRUE) && is.numeric(d[[outcome_col]]))) {
      return(d)
    }
  }
  dn <- NULL
  if ("DN" %in% names(d)) dn <- d$DN
  if (is.null(dn) && "Group.x" %in% names(d)) dn <- d$Group.x
  if (is.null(dn) && "Group.y" %in% names(d)) dn <- d$Group.y
  if (is.null(dn)) {
    stop("prepare_environment_dkd_data: 无法从 DN/Group.x/Group.y 构建结局列 ", outcome_col, call. = FALSE)
  }
  d[[outcome_col]] <- ifelse(as.numeric(dn) == 1L, analysis_grp, reference_grp)
  drop_g <- intersect(c("Group.x", "Group.y"), names(d))
  if (length(drop_g)) d[drop_g] <- NULL
  cli::cli_alert_info(
    "结局列 {outcome_col}: DN 0/1 → '{reference_grp}'/'{analysis_grp}'（n={nrow(d)}）"
  )
  d
}

prepare_environment_dkd_rename_clinical <- function(d) {
  .rename_if <- function(x, from, to) {
    if (from %in% names(x) && !to %in% names(x)) names(x)[names(x) == from] <- to
    x
  }
  d <- .rename_if(d, "Smoke", "Smoking")
  d <- .rename_if(d, "SBP", "NBPS")
  d <- .rename_if(d, "DBP", "NBPD")
  d <- .rename_if(d, "Uric_acid", "Uric_Acid")
  d <- .rename_if(d, "Blood_Urea_Nitrogen", "BUN")
  d <- .rename_if(d, "Serum_Creatinine", "Creatinine_refrigerated_serum")
  d <- .rename_if(d, "Albumin_urine", "Albumin_Urine")
  d <- .rename_if(d, "Fasting_Glucose", "Glucose")
  d <- .rename_if(d, "Glycated_hemoglobin", "HbA1c")
  d
}

prepare_environment_load_urinary_creatinine <- function(data_dir, cfg = list()) {
  cfg <- cfg %||% list()
  f <- cfg$urinary_creatinine_file %||% "尿肌酐_nhanes.csv"
  path <- as.character(f)[1L]
  if (!is_absolute_path(path)) path <- file.path(data_dir, path)
  if (!file.exists(path)) {
    stop("prepare_environment_dkd_data: 尿肌酐文件不存在: ", path, call. = FALSE)
  }
  id_col <- as.character(cfg$urinary_creatinine_id_col %||% "SEQN")[1L]
  val_col <- as.character(cfg$urinary_creatinine_col %||% "URXUCR")[1L]
  out_col <- as.character(cfg$urinary_creatinine_out_col %||% "Urinary_Creatinine")[1L]
  tab <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c(id_col, val_col) %in% names(tab))) {
    stop(
      "尿肌酐文件缺少列 ", id_col, "/", val_col, ": ", path,
      call. = FALSE
    )
  }
  tab[[id_col]] <- as.numeric(as.character(tab[[id_col]]))
  tab[[val_col]] <- as.numeric(as.character(tab[[val_col]]))
  tab <- tab[is.finite(tab[[id_col]]), , drop = FALSE]
  tab <- tab[!duplicated(tab[[id_col]]), , drop = FALSE]
  names(tab)[names(tab) == val_col] <- out_col
  tab[, c(id_col, out_col), drop = FALSE]
}

prepare_environment_adjust_voc_urinary_creatinine <- function(
    environment_data,
    urinary_creatinine,
    urine_vars = NULL,
    cfg = list()) {
  cfg <- cfg %||% list()
  if (is.null(environment_data) || !ncol(environment_data)) return(environment_data)
  if (is.null(urinary_creatinine) || !length(urinary_creatinine)) {
    return(environment_data)
  }
  ucr <- as.numeric(urinary_creatinine)
  if (is.null(urine_vars) || !length(urine_vars)) {
    pat <- as.character(cfg$urine_voc_pattern %||% "^URX")[1L]
    urine_vars <- grep(pat, names(environment_data), value = TRUE)
    urine_vars <- setdiff(urine_vars, c("URXUCR", "Urinary_Creatinine", "Urine_Creatinine"))
  }
  urine_vars <- intersect(as.character(urine_vars), names(environment_data))
  if (!length(urine_vars)) return(environment_data)

  ucr_valid <- ucr[is.finite(ucr) & ucr > 0]
  floor_pct <- as.numeric(cfg$urinary_creatinine_floor_pct %||% 0.05)
  floor_fixed <- cfg$urinary_creatinine_floor %||% NULL
  if (!is.null(floor_fixed) && is.finite(suppressWarnings(as.numeric(floor_fixed)))) {
    ucr_floor <- as.numeric(floor_fixed)
    floor_label <- sprintf("固定 %.2f mg/dL", ucr_floor)
  } else if (length(ucr_valid) >= 10L) {
    if (!is.finite(floor_pct) || floor_pct <= 0 || floor_pct >= 1) {
      stop("urinary_creatinine_floor_pct 须在 (0,1)", call. = FALSE)
    }
    ucr_floor <- unname(stats::quantile(ucr_valid, probs = floor_pct, na.rm = TRUE))
    floor_label <- sprintf("P%.0f=%.2f mg/dL", floor_pct * 100, ucr_floor)
  } else {
    ucr_floor <- 20
    floor_label <- "默认 20 mg/dL"
  }

  denom_ucr <- ifelse(is.finite(ucr) & ucr > 0, pmax(ucr, ucr_floor), NA_real_)
  denom <- denom_ucr / 100
  ok <- is.finite(denom) & denom > 0
  n_floored <- sum(is.finite(ucr) & ucr > 0 & ucr < ucr_floor, na.rm = TRUE)
  n_skip <- sum(!ok, na.rm = TRUE)
  if (n_floored > 0L) {
    cli::cli_alert_info(
      "尿肌酐校正分母下限: {floor_label}（{n_floored} 行 UCR 触底）"
    )
  }
  if (n_skip > 0L) {
    cli::cli_alert_warning(
      "尿肌酐校正: {n_skip}/{length(denom)} 行缺少有效 Urinary_Creatinine，对应 VOC 保留原值"
    )
  }
  for (v in urine_vars) {
    x <- as.numeric(environment_data[[v]])
    x[ok] <- x[ok] / denom[ok]
    x[!is.finite(x)] <- NA_real_
    environment_data[[v]] <- x
  }
  cli::cli_alert_success(
    "尿肌酐校正: {length(urine_vars)} 个 VOC ÷ (max(UCR, floor)/100)"
  )
  environment_data
}

#' LOD/MICE 前：肌酐校正后 VOC 按列分位 winsorize（默认 P1–P99）
prepare_environment_winsorize_voc_columns <- function(
    data,
    voc_cols = NULL,
    cfg = list()) {
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    return(list(data = data, n_winsorized = 0L, voc_cols = character(0)))
  }
  ep <- cfg$environment_prepare %||% cfg
  if (!isTRUE(ep$voc_adjusted_winsor_enable %||% FALSE)) {
    return(list(data = data, n_winsorized = 0L, voc_cols = character(0)))
  }
  lower <- as.numeric(ep$voc_adjusted_winsor_lower_pct %||% 0.01)
  upper <- as.numeric(ep$voc_adjusted_winsor_upper_pct %||% 0.99)
  if (!is.finite(lower) || !is.finite(upper) || lower < 0 || upper > 1 || lower >= upper) {
    stop("voc_adjusted_winsor_*_pct 须在 (0,1) 且 lower < upper", call. = FALSE)
  }
  if (is.null(voc_cols) || !length(voc_cols)) {
    pat <- as.character((cfg$environment %||% list())$voc_col_pattern %||% "^(URX|LBX)")[1L]
    voc_cols <- grep(pat, names(data), value = TRUE)
  }
  voc_cols <- intersect(as.character(voc_cols), names(data))
  if (!length(voc_cols)) {
    return(list(data = data, n_winsorized = 0L, voc_cols = character(0)))
  }

  n_winsor <- 0L
  use_log_scale <- isTRUE(ep$voc_adjusted_winsor_log_scale %||% TRUE)
  for (col in voc_cols) {
    x <- as.numeric(data[[col]])
    v <- x[is.finite(x)]
    if (length(v) < 10L) next
    if (use_log_scale) {
      pos <- is.finite(x) & x > 0
      if (sum(pos) < 10L) next
      lx <- log1p(x[pos])
      q_lo <- unname(stats::quantile(lx, probs = lower, na.rm = TRUE))
      q_hi <- unname(stats::quantile(lx, probs = upper, na.rm = TRUE))
      cap_lo <- expm1(q_lo)
      cap_hi <- expm1(q_hi)
      below <- pos & x < cap_lo
      above <- pos & x > cap_hi
    } else {
      q_lo <- unname(stats::quantile(v, probs = lower, na.rm = TRUE))
      q_hi <- unname(stats::quantile(v, probs = upper, na.rm = TRUE))
      below <- is.finite(x) & x < q_lo
      above <- is.finite(x) & x > q_hi
      cap_lo <- q_lo
      cap_hi <- q_hi
    }
    n_winsor <- n_winsor + sum(below, na.rm = TRUE) + sum(above, na.rm = TRUE)
    x[below] <- cap_lo
    x[above] <- cap_hi
    bad <- is.nan(x) | is.infinite(x)
    if (any(bad, na.rm = TRUE)) {
      x[bad] <- NA_real_
    }
    data[[col]] <- x
  }
  scale_label <- if (use_log_scale) "log1p 尺度" else "线性尺度"
  if (n_winsor > 0L) {
    cli::cli_alert_info(
      "肌酐校正 VOC winsorize ({scale_label} P{lower * 100}-P{upper * 100}): {length(voc_cols)} 列共 {n_winsor} 单元格"
    )
  }
  list(data = data, n_winsorized = n_winsor, voc_cols = voc_cols)
}

#' 按尿肌酐分位数剔除极端行（默认去掉最低/最高各 1%）
prepare_environment_filter_urinary_creatinine_percentile <- function(
    data,
    cfg = list(),
    ucr_col = NULL) {
  cfg <- cfg %||% list()
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    return(list(data = data, keep = rep(TRUE, nrow(data)), n_dropped = 0L))
  }
  trim_enable <- cfg$urinary_creatinine_trim_enable
  if (is.null(trim_enable)) {
    trim_enable <- isTRUE(cfg$adjust_voc_urinary_creatinine) &&
      (isTRUE(cfg$urinary_creatinine_trim_lower_pct %||% FALSE) ||
         isTRUE(cfg$urinary_creatinine_trim_upper_pct %||% FALSE))
  }
  if (!isTRUE(trim_enable)) {
    return(list(data = data, keep = rep(TRUE, nrow(data)), n_dropped = 0L))
  }

  out_ucr <- as.character(ucr_col %||% cfg$urinary_creatinine_out_col %||% "Urinary_Creatinine")[1L]
  if (!out_ucr %in% names(data)) {
    cli::cli_alert_warning("尿肌酐分位剔除: 未找到列 {out_ucr}，跳过")
    return(list(data = data, keep = rep(TRUE, nrow(data)), n_dropped = 0L))
  }

  lower <- as.numeric(cfg$urinary_creatinine_trim_lower_pct %||% 0.01)
  upper <- as.numeric(cfg$urinary_creatinine_trim_upper_pct %||% 0.99)
  if (!is.finite(lower) || !is.finite(upper) || lower < 0 || upper > 1 || lower >= upper) {
    stop("urinary_creatinine_trim_*_pct 须在 (0,1) 且 lower < upper", call. = FALSE)
  }

  ucr <- as.numeric(data[[out_ucr]])
  valid <- is.finite(ucr) & ucr > 0
  n_before <- nrow(data)
  if (sum(valid) < 10L) {
    cli::cli_alert_warning("尿肌酐分位剔除: 有效值不足 ({sum(valid)})，跳过")
    return(list(data = data, keep = rep(TRUE, n_before), n_dropped = 0L))
  }

  q_lo <- unname(stats::quantile(ucr[valid], probs = lower, na.rm = TRUE))
  q_hi <- unname(stats::quantile(ucr[valid], probs = upper, na.rm = TRUE))
  drop <- valid & (ucr < q_lo | ucr > q_hi)
  keep <- !drop
  n_drop <- sum(drop)
  if (n_drop > 0L) {
    data <- data[keep, , drop = FALSE]
    cli::cli_alert_info(
      "尿肌酐分位剔除: P{lower * 100}-P{upper * 100} [{round(q_lo, 2)}, {round(q_hi, 2)}]，删除 {n_drop} 行（{n_before} → {nrow(data)}）"
    )
  } else {
    cli::cli_alert_info(
      "尿肌酐分位剔除: P{lower * 100}-P{upper * 100} [{round(q_lo, 2)}, {round(q_hi, 2)}]，无行被删除"
    )
  }
  list(data = data, keep = keep, n_dropped = n_drop, q_lo = q_lo, q_hi = q_hi)
}

prepare_environment_local_bundle_resolve_seqn <- function(clin_rownames, env_rownames,
                                                          weight_seqn, baseline_ids) {
  clin <- suppressWarnings(as.numeric(as.character(clin_rownames)))
  env  <- suppressWarnings(as.numeric(as.character(env_rownames)))
  wset <- unique(as.numeric(as.character(weight_seqn)))
  wset <- wset[is.finite(wset)]
  bset <- unique(as.numeric(as.character(baseline_ids)))
  bset <- bset[is.finite(bset)]
  vapply(seq_along(clin), function(i) {
    c <- clin[i]
    e <- env[i]
    if (is.finite(c) && (c %in% wset || c %in% bset)) return(c)
    if (is.finite(e) && (e %in% wset || e %in% bset)) return(e)
    if (is.finite(c)) return(c)
    if (is.finite(e)) return(e)
    NA_real_
  }, numeric(1L))
}

#' 本地 Data/ 行对齐合并（临床行名/环境行名 → SEQN + 环境 WTSA2YR + baseline 调查设计）
prepare_environment_local_bundle_merge <- function(root, cfg = list()) {
  cfg <- cfg %||% list()
  data_dir <- cfg$data_dir %||% file.path(root, "Data")
  if (!is_absolute_path(data_dir)) data_dir <- file.path(root, data_dir)

  clin_path <- file.path(data_dir, cfg$clinical_file %||% "D01_RawCleanData(1).RData")
  env_path  <- file.path(data_dir, cfg$environment_file %||% "D01_EnvCleanData(1).RData")
  clin_obj  <- cfg$clinical_obj %||% "data"
  env_obj   <- cfg$environment_obj %||% "environment_data"

  if (!file.exists(clin_path)) stop("local_bundle: 临床文件不存在: ", clin_path, call. = FALSE)
  if (!file.exists(env_path)) stop("local_bundle: 环境文件不存在: ", env_path, call. = FALSE)

  e1 <- new.env(); load(clin_path, envir = e1)
  e2 <- new.env(); load(env_path, envir = e2)
  if (!exists(clin_obj, envir = e1)) stop("local_bundle: 缺少 ", clin_obj, " in ", clin_path, call. = FALSE)
  if (!exists(env_obj, envir = e2)) stop("local_bundle: 缺少 ", env_obj, " in ", env_path, call. = FALSE)
  data <- get(clin_obj, envir = e1)
  environment_data <- get(env_obj, envir = e2)
  if (!is.data.frame(data) || !is.data.frame(environment_data)) {
    stop("local_bundle: 临床/环境对象须为 data.frame", call. = FALSE)
  }
  if (nrow(data) != nrow(environment_data)) {
    stop(
      "local_bundle: 临床 n=", nrow(data), " 与环境 n=", nrow(environment_data), " 不一致",
      call. = FALSE
    )
  }

  voc_cols <- setdiff(names(environment_data), c("Group", "SEQN", "DN"))
  voc_exclude <- unique(as.character(cfg$voc_exclude_fixed %||% character(0)))
  voc_exclude <- voc_exclude[nzchar(voc_exclude)]
  if (length(voc_exclude)) {
    voc_cols <- setdiff(voc_cols, voc_exclude)
  }
  if (!length(voc_cols)) stop("local_bundle: 环境文件无 VOC 列", call. = FALSE)

  nhanes_dir <- cfg$nhanes_dir %||% file.path(data_dir, "nhanes")
  if (!is_absolute_path(nhanes_dir)) nhanes_dir <- file.path(root, nhanes_dir)

  env_wt <- prepare_environment_dkd_load_env_weights(nhanes_dir, cfg)
  weight_seqn <- if (!is.null(env_wt)) env_wt$SEQN else numeric(0)

  survey_bl <- NULL
  bl_path <- "local_bundle"
  if (isTRUE(cfg$merge_baseline_survey %||% TRUE)) {
    survey_bl <- prepare_environment_dkd_load_baseline_survey(
      nhanes_dir, cfg$baseline_pattern %||% "baseline.*NHANES.*\\.RData$"
    )
    bl_path <- attr(survey_bl, "source_path")
    survey_bl$source_path <- NULL
  }
  baseline_ids <- if (!is.null(survey_bl) && "SEQN" %in% names(survey_bl)) {
    survey_bl$SEQN
  } else {
    numeric(0)
  }

  seqn <- prepare_environment_local_bundle_resolve_seqn(
    rownames(data), rownames(environment_data), weight_seqn, baseline_ids
  )
  if (any(!is.finite(seqn))) {
    stop(
      "local_bundle: 无法从临床/环境行名解析 SEQN（缺失 ",
      sum(!is.finite(seqn)), " 行）", call. = FALSE
    )
  }

  out_ucr <- as.character(cfg$urinary_creatinine_out_col %||% "Urinary_Creatinine")[1L]
  ucr_file <- cfg$urinary_creatinine_file %||% "尿肌酐_nhanes.csv"
  util_voc <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(util_voc)) source(util_voc, local = FALSE)

  kidney_wf <- if (exists("prepare_environment_kidney_voc_workflow", mode = "function")) {
    prepare_environment_kidney_voc_workflow(list(
      environment_prepare = cfg,
      project = cfg$project %||% list()
    ))
  } else {
    isTRUE(cfg$kidney_disease_voc_workflow %||% FALSE)
  }
  should_restore <- kidney_wf || isTRUE(cfg$restore_all_voc_to_ugl %||% FALSE)
  if (should_restore && exists("environment_restore_voc_to_ug_per_l", mode = "function")) {
    environment_data <- environment_restore_voc_to_ug_per_l(
      environment_data, voc_cols, list(environment_prepare = cfg, project = cfg$project %||% list()), root
    )
  }

  if (nzchar(ucr_file)) {
    ucr_tab <- prepare_environment_load_urinary_creatinine(data_dir, cfg)
    ucr_map <- setNames(
      as.numeric(ucr_tab[[out_ucr]]),
      as.character(ucr_tab[[cfg$urinary_creatinine_id_col %||% "SEQN"]])
    )
    data[[out_ucr]] <- as.numeric(ucr_map[as.character(seqn)])
    n_ucr <- sum(is.finite(data[[out_ucr]]) & data[[out_ucr]] > 0, na.rm = TRUE)
    cli::cli_alert_info(
      "尿肌酐合并: {basename(ucr_file)} → {out_ucr}（有效 {n_ucr}/{length(seqn)}）"
    )
  }
  if (out_ucr %in% names(data)) {
    trim <- prepare_environment_filter_urinary_creatinine_percentile(data, cfg, out_ucr)
    data <- trim$data
    if (trim$n_dropped > 0L) {
      environment_data <- environment_data[trim$keep, , drop = FALSE]
      seqn <- seqn[trim$keep]
    }
  }
  adjust_ucr <- if (!is.null(cfg$adjust_voc_urinary_creatinine)) {
    isTRUE(cfg$adjust_voc_urinary_creatinine)
  } else {
    kidney_wf
  }
  if (adjust_ucr) {
    urine_vars <- if (!is.null(cfg$urine_vars) && length(cfg$urine_vars)) {
      as.character(cfg$urine_vars)
    } else {
      voc_cols
    }
    environment_data <- prepare_environment_adjust_voc_urinary_creatinine(
      environment_data, data[[out_ucr]], urine_vars, cfg
    )
  } else {
    cli::cli_alert_info("VOC 保留原始尿浓度（μg/L），未做尿肌酐除法校正。")
  }

  EnvResult <- data
  add_voc <- setdiff(voc_cols, names(EnvResult))
  if (length(add_voc)) {
    EnvResult[add_voc] <- environment_data[add_voc]
  }
  EnvResult <- prepare_environment_dkd_rename_clinical(EnvResult)
  EnvResult <- prepare_environment_dkd_ensure_outcome_group(EnvResult, list(
    project = cfg$project %||% list(),
    data = cfg$data %||% list()
  ))

  EnvResult$SEQN <- seqn

  if (!is.null(survey_bl)) {
    drop_from_env <- setdiff(intersect(names(EnvResult), names(survey_bl)), "SEQN")
    if (length(drop_from_env)) EnvResult[drop_from_env] <- NULL
    EnvResult <- merge(EnvResult, survey_bl, by = "SEQN", all.x = TRUE, sort = FALSE)
    if (!"Source_File" %in% names(EnvResult)) {
      EnvResult$Source_File <- as.character(cfg$local_source_file %||% "Local")[1L]
    }
  } else {
    EnvResult$Source_File <- as.character(cfg$local_source_file %||% "Local")[1L]
  }

  if (!is.null(env_wt)) {
    wt_path <- attr(env_wt, "source_path")
    EnvResult$WTSA2YR <- NULL
    EnvResult <- merge(EnvResult, env_wt, by = "SEQN", all.x = TRUE, sort = FALSE)
    EnvResult <- prepare_environment_filter_env_weight_rows(EnvResult, cfg)
    nw_col <- cfg$merged_weight_col %||% "new_Weight"
    EnvResult <- prepare_environment_dkd_apply_pooled_weight(
      EnvResult,
      wt2_col = cfg$env_weight_col %||% "WTSA2YR",
      wt_col = nw_col,
      fallback_wt2_col = if (isTRUE(cfg$env_weight_fallback_wtmec %||% TRUE)) "WTMEC2YR" else ""
    )
    cli::cli_alert_success(
      "local_bundle 环境权重: {basename(wt_path)} → {cfg$env_weight_col %||% 'WTSA2YR'} → {nw_col}"
    )
  } else if (isTRUE(cfg$merge_baseline_survey %||% TRUE) &&
             "WTMEC2YR" %in% names(EnvResult)) {
    nw_col <- cfg$merged_weight_col %||% "new_Weight"
    EnvResult <- prepare_environment_dkd_apply_pooled_weight(
      EnvResult,
      wt2_col = "WTMEC2YR",
      wt_col = nw_col,
      fallback_wt2_col = ""
    )
    cli::cli_alert_info("local_bundle: 无 env_weight_file，使用 WTMEC2YR → {nw_col}")
  }

  if (!"SDMVPSU" %in% names(EnvResult)) EnvResult$SDMVPSU <- 1L
  if (!"SDMVSTRA" %in% names(EnvResult)) EnvResult$SDMVSTRA <- 1L

  n <- nrow(EnvResult)
  nw_col <- cfg$merged_weight_col %||% "new_Weight"
  if (nw_col %in% names(EnvResult)) {
    n_nw <- sum(is.finite(EnvResult[[nw_col]]) & EnvResult[[nw_col]] > 0, na.rm = TRUE)
    n_uni <- length(unique(EnvResult[[nw_col]][is.finite(EnvResult[[nw_col]]) &
                                                EnvResult[[nw_col]] > 0]))
    if (n_nw < n) {
      stop("local_bundle: ", nw_col, " 有效行仅 ", n_nw, " / ", n, call. = FALSE)
    }
    cli::cli_alert_info(
      "local_bundle {nw_col}: 有效 {n_nw}/{n}，唯一值 {n_uni}，中位数 {signif(stats::median(EnvResult[[nw_col]], na.rm=TRUE), 4)}"
    )
  }

  cli::cli_alert_info(
    "local_bundle: {basename(clin_path)} + {basename(env_path)} → n={n}, VOC={length(voc_cols)}"
  )

  save_dir <- cfg$merged_output_dir %||% file.path(data_dir, "nhanes")
  if (!is_absolute_path(save_dir)) save_dir <- file.path(root, save_dir)
  out_path <- NULL
  if (isTRUE(cfg$save_merged %||% TRUE)) {
    merged_file <- cfg$merged_file %||% "D03_EnvResultData.RData"
    merged_obj  <- cfg$merged_obj %||% "EnvResult"
    dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(save_dir, merged_file)
    tmp <- EnvResult
    assign(merged_obj, tmp)
    save(list = merged_obj, file = out_path)
    voc_path <- file.path(save_dir, cfg$voc_columns_file %||% "voc_columns.RData")
    save(voc_columns = voc_cols, file = voc_path)
  }

  list(
    EnvResult     = EnvResult,
    voc_columns   = voc_cols,
    baseline_path = bl_path,
    out_path      = out_path,
    nhanes_dir    = data_dir,
    cohort_audit  = NULL,
    cohort_filter = NULL
  )
}

prepare_environment_read_sav_df <- function(path) {
  path <- as.character(path)[1L]
  if (!file.exists(path)) {
    stop("prepare_environment_dkd_data: SAV 文件不存在: ", path, call. = FALSE)
  }
  if (!requireNamespace("haven", quietly = TRUE)) {
    stop("prepare_environment_dkd_data: 读取 .sav 需要 haven 包", call. = FALSE)
  }
  as.data.frame(haven::read_sav(path), stringsAsFactors = FALSE)
}

prepare_environment_dkd_load_env_weight_full <- function(nhanes_dir, cfg) {
  f <- cfg$env_weight_file %||% NULL
  if (is.null(f) || !nzchar(as.character(f)[1L])) return(NULL)
  path <- as.character(f)[1L]
  if (!is_absolute_path(path)) path <- file.path(nhanes_dir, path)
  if (!file.exists(path)) {
    stop("prepare_environment_dkd_data: env_weight_file 不存在: ", path, call. = FALSE)
  }
  obj_name <- as.character(cfg$env_weight_obj %||% "df")[1L]
  id_col   <- as.character(cfg$env_weight_id_col %||% "SEQN")[1L]
  e <- new.env()
  load(path, envir = e)
  if (!exists(obj_name, envir = e, inherits = FALSE)) {
    stop("prepare_environment_dkd_data: ", path, " 缺少对象 ", obj_name, call. = FALSE)
  }
  d <- get(obj_name, envir = e)
  if (!is.data.frame(d)) stop("env_weight 对象不是 data.frame", call. = FALSE)
  if (!id_col %in% names(d)) {
    stop("env_weight 缺少 ID 列 ", id_col, ": ", path, call. = FALSE)
  }
  d[[id_col]] <- as.numeric(as.character(d[[id_col]]))
  d <- d[is.finite(d[[id_col]]), , drop = FALSE]
  d <- d[!duplicated(d[[id_col]]), , drop = FALSE]
  names(d)[names(d) == id_col] <- "SEQN"
  attr(d, "source_path") <- path
  d
}

#' baseline NHANES + 环境 SAV + 环境子样本权重（WTSA2YR）三表合并
prepare_environment_baseline_sav_merge <- function(root, cfg = list()) {
  cfg <- cfg %||% list()
  data_dir <- cfg$data_dir %||% file.path(root, "Data")
  if (!is_absolute_path(data_dir)) data_dir <- file.path(root, data_dir)
  nhanes_dir <- cfg$nhanes_dir %||% file.path(data_dir, "nhanes")
  if (!is_absolute_path(nhanes_dir)) nhanes_dir <- file.path(root, nhanes_dir)

  bl_file <- cfg$baseline_file %||% "D01_baseline_NHANES_0610(2).RData"
  bl_path <- as.character(bl_file)[1L]
  if (!is_absolute_path(bl_path)) bl_path <- file.path(nhanes_dir, bl_path)
  bl_obj <- cfg$baseline_obj %||% "baseline"
  e_bl <- new.env()
  load(bl_path, envir = e_bl)
  if (!exists(bl_obj, envir = e_bl, inherits = FALSE)) {
    stop("baseline_sav: 缺少对象 ", bl_obj, " in ", bl_path, call. = FALSE)
  }
  baseline <- get(bl_obj, envir = e_bl)
  if (!is.data.frame(baseline)) stop("baseline 不是 data.frame", call. = FALSE)
  bl_id <- if ("SEQN" %in% names(baseline)) "SEQN" else if ("ID" %in% names(baseline)) "ID" else {
    stop("baseline 缺少 SEQN/ID: ", bl_path, call. = FALSE)
  }
  baseline$SEQN <- as.numeric(as.character(baseline[[bl_id]]))
  baseline <- baseline[is.finite(baseline$SEQN), , drop = FALSE]
  baseline <- baseline[!duplicated(baseline$SEQN), , drop = FALSE]

  sav_path <- cfg$environment_sav_file %||% file.path(data_dir, "enviroment-factors(1).sav")
  if (!is_absolute_path(sav_path)) sav_path <- file.path(root, sav_path)
  env_df <- prepare_environment_read_sav_df(sav_path)
  if (!"SEQN" %in% names(env_df)) stop("environment SAV 缺少 SEQN: ", sav_path, call. = FALSE)
  env_df$SEQN <- as.numeric(as.character(env_df$SEQN))
  env_df <- env_df[is.finite(env_df$SEQN), , drop = FALSE]
  env_meta <- c("SEQN", "cycle")
  env_meta <- intersect(env_meta, names(env_df))
  env_cols <- setdiff(names(env_df), env_meta)

  wt_full <- prepare_environment_dkd_load_env_weight_full(nhanes_dir, cfg)
  if (is.null(wt_full)) stop("baseline_sav: 需要 env_weight_file（WTSA2YR）", call. = FALSE)
  wt_path <- attr(wt_full, "source_path")
  wt_col <- as.character(cfg$env_weight_col %||% "WTSA2YR")[1L]
  if (!wt_col %in% names(wt_full)) {
    stop("env_weight 缺少列 ", wt_col, call. = FALSE)
  }
  extra_wt_cols <- as.character(cfg$env_weight_extra_cols %||% c("URXUAS"))
  extra_wt_cols <- intersect(extra_wt_cols, names(wt_full))
  extra_wt_cols <- setdiff(extra_wt_cols, c("SEQN", wt_col))

  util_voc <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(util_voc)) source(util_voc, local = FALSE)

  n_before <- nrow(wt_full)
  merged <- merge(wt_full, baseline, by = "SEQN", all.x = FALSE, sort = FALSE)
  cli::cli_alert_info(
    "baseline_sav: 权重×临床 {n_before} → {nrow(merged)}（内连接 SEQN）"
  )
  merged <- merge(merged, env_df, by = "SEQN", all.x = FALSE, sort = FALSE)
  if ("cycle" %in% names(merged) && "Source_File" %in% names(merged)) {
    n_pre <- nrow(merged)
    merged <- merged[
      as.character(merged$cycle) == as.character(merged$Source_File),
      ,
      drop = FALSE
    ]
    cli::cli_alert_info(
      "baseline_sav: cycle=Source_File 对齐 {n_pre} → {nrow(merged)}"
    )
  }
  if (!nrow(merged)) stop("baseline_sav: 三表合并后为空", call. = FALSE)

  for (ec in extra_wt_cols) {
    if (!ec %in% names(merged) && ec %in% names(wt_full)) {
      wt_map <- setNames(as.numeric(wt_full[[ec]]), as.character(wt_full$SEQN))
      merged[[ec]] <- as.numeric(wt_map[as.character(merged$SEQN)])
    }
    if (ec %in% names(merged) && !ec %in% env_cols) env_cols <- c(env_cols, ec)
  }
  env_cols <- unique(env_cols[nzchar(env_cols)])

  environment_data <- merged[, env_cols, drop = FALSE]
  voc_cols <- env_cols

  kidney_wf <- if (exists("prepare_environment_kidney_voc_workflow", mode = "function")) {
    prepare_environment_kidney_voc_workflow(list(
      environment_prepare = cfg,
      project = cfg$project %||% list()
    ))
  } else {
    isTRUE(cfg$kidney_disease_voc_workflow %||% FALSE)
  }
  should_restore <- kidney_wf || isTRUE(cfg$restore_all_voc_to_ugl %||% FALSE)
  if (should_restore && exists("environment_restore_voc_to_ug_per_l", mode = "function")) {
    environment_data <- environment_restore_voc_to_ug_per_l(
      environment_data, voc_cols,
      list(environment_prepare = cfg, project = cfg$project %||% list()),
      root
    )
  }

  out_ucr <- as.character(cfg$urinary_creatinine_out_col %||% "Urinary_Creatinine")[1L]
  ucr_file <- cfg$urinary_creatinine_file %||% NULL
  if (nzchar(ucr_file %||% "")) {
    ucr_tab <- prepare_environment_load_urinary_creatinine(data_dir, cfg)
    ucr_map <- setNames(
      as.numeric(ucr_tab[[out_ucr]]),
      as.character(ucr_tab[[cfg$urinary_creatinine_id_col %||% "SEQN"]])
    )
    merged[[out_ucr]] <- as.numeric(ucr_map[as.character(merged$SEQN)])
  }
  if (out_ucr %in% names(merged)) {
    trim <- prepare_environment_filter_urinary_creatinine_percentile(merged, cfg, out_ucr)
    merged <- trim$data
    if (trim$n_dropped > 0L) {
      environment_data <- environment_data[trim$keep, , drop = FALSE]
    }
  }
  adjust_ucr <- if (!is.null(cfg$adjust_voc_urinary_creatinine)) {
    isTRUE(cfg$adjust_voc_urinary_creatinine)
  } else {
    kidney_wf
  }
  if (adjust_ucr && out_ucr %in% names(merged)) {
    environment_data <- prepare_environment_adjust_voc_urinary_creatinine(
      environment_data, merged[[out_ucr]], voc_cols, cfg
    )
  } else if (!adjust_ucr) {
    cli::cli_alert_info("VOC 保留原始浓度，未做尿肌酐除法校正。")
  }

  drop_env <- intersect(names(merged), env_cols)
  if (length(drop_env)) merged[drop_env] <- NULL
  merged[env_cols] <- environment_data

  EnvResult <- prepare_environment_dkd_rename_clinical(merged)
  EnvResult <- prepare_environment_dkd_ensure_outcome_group(EnvResult, list(
    project = cfg$project %||% list(),
    data = cfg$data %||% list(),
    outcome_source_column = cfg$outcome_source_column %||%
      (cfg$data %||% list())$outcome_source_column
  ))

  EnvResult <- prepare_environment_filter_env_weight_rows(EnvResult, cfg)
  nw_col <- cfg$merged_weight_col %||% "new_Weight"
  EnvResult <- prepare_environment_dkd_apply_pooled_weight(
    EnvResult,
    wt2_col = wt_col,
    wt_col = nw_col,
    fallback_wt2_col = if (isTRUE(cfg$env_weight_fallback_wtmec %||% TRUE)) "WTMEC2YR" else ""
  )
  cli::cli_alert_success(
    "baseline_sav 环境权重: {basename(wt_path)} → {wt_col} → {nw_col}"
  )

  if (!"SDMVPSU" %in% names(EnvResult)) EnvResult$SDMVPSU <- 1L
  if (!"SDMVSTRA" %in% names(EnvResult)) EnvResult$SDMVSTRA <- 1L

  n <- nrow(EnvResult)
  if (nw_col %in% names(EnvResult)) {
    n_nw <- sum(is.finite(EnvResult[[nw_col]]) & EnvResult[[nw_col]] > 0, na.rm = TRUE)
    n_uni <- length(unique(EnvResult[[nw_col]][is.finite(EnvResult[[nw_col]]) &
                                                  EnvResult[[nw_col]] > 0]))
    if (n_nw < n) {
      stop("baseline_sav: ", nw_col, " 有效行仅 ", n_nw, " / ", n, call. = FALSE)
    }
    cli::cli_alert_info(
      "baseline_sav {nw_col}: 有效 {n_nw}/{n}，唯一值 {n_uni}，中位数 {signif(stats::median(EnvResult[[nw_col]], na.rm=TRUE), 4)}"
    )
  }

  cli::cli_alert_info(
    "baseline_sav: {basename(bl_path)} + {basename(sav_path)} + {basename(wt_path)} → n={n}, 环境变量={length(voc_cols)}"
  )

  save_dir <- cfg$merged_output_dir %||% file.path(data_dir, "nhanes")
  if (!is_absolute_path(save_dir)) save_dir <- file.path(root, save_dir)
  out_path <- NULL
  if (isTRUE(cfg$save_merged %||% TRUE)) {
    merged_file <- cfg$merged_file %||% "D03_EnvResultData.RData"
    merged_obj  <- cfg$merged_obj %||% "EnvResult"
    dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(save_dir, merged_file)
    tmp <- EnvResult
    assign(merged_obj, tmp)
    save(list = merged_obj, file = out_path)
    voc_path <- file.path(save_dir, cfg$voc_columns_file %||% "voc_columns.RData")
    save(voc_columns = voc_cols, file = voc_path)
  }

  list(
    EnvResult     = EnvResult,
    voc_columns   = voc_cols,
    baseline_path = bl_path,
    out_path      = out_path,
    nhanes_dir    = data_dir,
    cohort_audit  = NULL,
    cohort_filter = NULL
  )
}

#' D04 等预合并 RData（临床 + 环境 + 权重列已在表内）
prepare_environment_premerged_rdata_merge <- function(root, cfg = list()) {
  cfg <- cfg %||% list()
  data_dir <- cfg$data_dir %||% file.path(root, "Data")
  if (!is_absolute_path(data_dir)) data_dir <- file.path(root, data_dir)

  pre_file <- cfg$premerged_file %||% "D04_环境_删除尼古丁空缺值(2).RData"
  pre_obj  <- cfg$premerged_obj %||% "dabiao4"
  pre_path <- as.character(pre_file)[1L]
  if (!is_absolute_path(pre_path)) pre_path <- file.path(data_dir, pre_path)
  if (!file.exists(pre_path)) {
    stop("premerged_rdata: 文件不存在: ", pre_path, call. = FALSE)
  }

  e <- new.env()
  load(pre_path, envir = e)
  if (!exists(pre_obj, envir = e, inherits = FALSE)) {
    stop("premerged_rdata: ", pre_path, " 缺少对象 ", pre_obj, call. = FALSE)
  }
  EnvResult <- get(pre_obj, envir = e)
  if (!is.data.frame(EnvResult)) stop("premerged 对象须为 data.frame", call. = FALSE)
  if (!"SEQN" %in% names(EnvResult)) {
    stop("premerged_rdata: 缺少 SEQN 列: ", pre_path, call. = FALSE)
  }
  EnvResult$SEQN <- as.numeric(as.character(EnvResult$SEQN))
  EnvResult <- EnvResult[is.finite(EnvResult$SEQN), , drop = FALSE]
  EnvResult <- EnvResult[!duplicated(EnvResult$SEQN), , drop = FALSE]

  voc_pat <- cfg$env_voc_pattern %||% cfg$voc_col_pattern %||% "^(URX|LBX)"
  voc_exclude <- as.character(cfg$voc_exclude_fixed %||% character(0))
  voc_cols <- grep(voc_pat, names(EnvResult), value = TRUE)
  voc_cols <- setdiff(voc_cols, voc_exclude)
  if (!length(voc_cols)) stop("premerged_rdata: 未识别环境变量列", call. = FALSE)

  util_voc <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(util_voc)) source(util_voc, local = FALSE)

  kidney_wf <- if (exists("prepare_environment_kidney_voc_workflow", mode = "function")) {
    prepare_environment_kidney_voc_workflow(list(
      environment_prepare = cfg,
      project = cfg$project %||% list()
    ))
  } else {
    isTRUE(cfg$kidney_disease_voc_workflow %||% FALSE)
  }
  should_restore <- kidney_wf || isTRUE(cfg$restore_all_voc_to_ugl %||% FALSE)
  if (should_restore && exists("environment_restore_voc_to_ug_per_l", mode = "function")) {
    env_sub <- EnvResult[, voc_cols, drop = FALSE]
    env_sub <- environment_restore_voc_to_ug_per_l(
      env_sub, voc_cols,
      list(environment_prepare = cfg, project = cfg$project %||% list()),
      root
    )
    EnvResult[voc_cols] <- env_sub
  }

  out_ucr <- as.character(cfg$urinary_creatinine_out_col %||% "Urinary_Creatinine")[1L]
  ucr_file <- cfg$urinary_creatinine_file %||% NULL
  adjust_ucr <- if (!is.null(cfg$adjust_voc_urinary_creatinine)) {
    isTRUE(cfg$adjust_voc_urinary_creatinine)
  } else {
    kidney_wf
  }
  if (adjust_ucr) {
    if (nzchar(ucr_file %||% "")) {
      ucr_tab <- prepare_environment_load_urinary_creatinine(data_dir, cfg)
      ucr_map <- setNames(
        as.numeric(ucr_tab[[out_ucr]]),
        as.character(ucr_tab[[cfg$urinary_creatinine_id_col %||% "SEQN"]])
      )
      EnvResult[[out_ucr]] <- as.numeric(ucr_map[as.character(EnvResult$SEQN)])
      n_ucr <- sum(is.finite(EnvResult[[out_ucr]]) & EnvResult[[out_ucr]] > 0, na.rm = TRUE)
      cli::cli_alert_info(
        "尿肌酐合并: {basename(ucr_file)} → {out_ucr}（有效 {n_ucr}/{nrow(EnvResult)}）"
      )
    } else if (!out_ucr %in% names(EnvResult) && "UrineCreatinine" %in% names(EnvResult)) {
      EnvResult[[out_ucr]] <- as.numeric(EnvResult$UrineCreatinine)
    } else if (!out_ucr %in% names(EnvResult) && "URXUCR" %in% names(EnvResult)) {
      EnvResult[[out_ucr]] <- as.numeric(EnvResult$URXUCR)
    }
    trim <- prepare_environment_filter_urinary_creatinine_percentile(EnvResult, cfg, out_ucr)
    EnvResult <- trim$data
    if (out_ucr %in% names(EnvResult)) {
      env_sub <- EnvResult[, voc_cols, drop = FALSE]
      env_sub <- prepare_environment_adjust_voc_urinary_creatinine(
        env_sub, EnvResult[[out_ucr]], voc_cols, cfg
      )
      EnvResult[voc_cols] <- env_sub
    } else {
      cli::cli_alert_warning("尿肌酐校正: 未找到 {out_ucr}，VOC 保留原浓度")
    }
  } else {
    cli::cli_alert_info("VOC 保留原始尿浓度（μg/L），未做尿肌酐除法校正。")
  }

  EnvResult <- prepare_environment_dkd_rename_clinical(EnvResult)
  EnvResult <- prepare_environment_dkd_ensure_outcome_group(EnvResult, list(
    project = cfg$project %||% list(),
    data = cfg$data %||% list(),
    outcome_source_column = cfg$outcome_source_column %||% (cfg$data %||% list())$outcome_source_column
  ))

  wt_col <- as.character(cfg$env_weight_col %||% "WTSA2YR")[1L]
  nw_col <- cfg$merged_weight_col %||% "new_Weight"
  if (!nw_col %in% names(EnvResult) || !all(is.finite(EnvResult[[nw_col]]) & EnvResult[[nw_col]] > 0)) {
    if (!wt_col %in% names(EnvResult)) {
      nhanes_dir <- cfg$nhanes_dir %||% file.path(data_dir, "nhanes")
      if (!is_absolute_path(nhanes_dir)) nhanes_dir <- file.path(root, nhanes_dir)
      env_wt <- prepare_environment_dkd_load_env_weight_full(nhanes_dir, cfg)
      if (!is.null(env_wt)) {
        EnvResult[[wt_col]] <- NULL
        EnvResult <- merge(EnvResult, env_wt[, c("SEQN", wt_col), drop = FALSE],
                           by = "SEQN", all.x = TRUE, sort = FALSE)
      }
    }
    if ("Source_File" %in% names(EnvResult) && wt_col %in% names(EnvResult)) {
      EnvResult <- prepare_environment_filter_env_weight_rows(EnvResult, cfg)
      EnvResult <- prepare_environment_dkd_apply_pooled_weight(
        EnvResult,
        wt2_col = wt_col,
        wt_col = nw_col,
        fallback_wt2_col = if (isTRUE(cfg$env_weight_fallback_wtmec %||% TRUE)) "WTMEC2YR" else ""
      )
    }
  }

  if (!"SDMVPSU" %in% names(EnvResult)) EnvResult$SDMVPSU <- 1L
  if (!"SDMVSTRA" %in% names(EnvResult)) EnvResult$SDMVSTRA <- 1L

  n <- nrow(EnvResult)
  if (nw_col %in% names(EnvResult)) {
    n_nw <- sum(is.finite(EnvResult[[nw_col]]) & EnvResult[[nw_col]] > 0, na.rm = TRUE)
    if (n_nw < n) {
      stop("premerged_rdata: ", nw_col, " 有效行仅 ", n_nw, " / ", n, call. = FALSE)
    }
    cli::cli_alert_info(
      "premerged {nw_col}: 有效 {n_nw}/{n}，中位数 {signif(stats::median(EnvResult[[nw_col]], na.rm=TRUE), 4)}"
    )
  }

  cli::cli_alert_info(
    "premerged_rdata: {basename(pre_path)} ({pre_obj}) → n={n}, 环境变量={length(voc_cols)}"
  )

  save_dir <- cfg$merged_output_dir %||% file.path(data_dir, "nhanes")
  if (!is_absolute_path(save_dir)) save_dir <- file.path(root, save_dir)
  out_path <- NULL
  if (isTRUE(cfg$save_merged %||% TRUE)) {
    merged_file <- cfg$merged_file %||% "D03_EnvResultData.RData"
    merged_obj  <- cfg$merged_obj %||% "EnvResult"
    dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(save_dir, merged_file)
    tmp <- EnvResult
    assign(merged_obj, tmp)
    save(list = merged_obj, file = out_path)
    voc_path <- file.path(save_dir, cfg$voc_columns_file %||% "voc_columns.RData")
    save(voc_columns = voc_cols, file = voc_path)
  }

  list(
    EnvResult     = EnvResult,
    voc_columns   = voc_cols,
    baseline_path = pre_path,
    out_path      = out_path,
    nhanes_dir    = data_dir,
    cohort_audit  = NULL,
    cohort_filter = NULL
  )
}

#' 合并 D02 临床 + 环境 + baseline 调查权重
#'
#' @param root 项目根目录
#' @param cfg config$environment_prepare 列表
#' @return list(EnvResult, voc_columns, baseline_path, out_path)
prepare_environment_dkd_merge <- function(root, cfg = list()) {
  cfg <- cfg %||% list()
  mode <- tolower(as.character(cfg$mode %||% "nhanes")[1L])
  if (identical(mode, "local_bundle")) {
    return(prepare_environment_local_bundle_merge(root, cfg))
  }
  if (identical(mode, "baseline_sav")) {
    return(prepare_environment_baseline_sav_merge(root, cfg))
  }
  if (identical(mode, "premerged_rdata")) {
    return(prepare_environment_premerged_rdata_merge(root, cfg))
  }
  nhanes_dir <- cfg$nhanes_dir %||% "Data/nhanes"
  if (!is_absolute_path(nhanes_dir)) nhanes_dir <- file.path(root, nhanes_dir)

  clin_path <- file.path(nhanes_dir, cfg$clinical_file %||% "D02_data.RData")
  env_path  <- file.path(nhanes_dir, cfg$environment_file %||% "D02_environment_data.RData")
  clin_obj  <- cfg$clinical_obj %||% "data"
  env_obj   <- cfg$environment_obj %||% "environment_data"

  e1 <- new.env(); load(clin_path, envir = e1)
  e2 <- new.env(); load(env_path, envir = e2)
  if (!exists(clin_obj, envir = e1)) stop("缺少 ", clin_obj, " in ", clin_path, call. = FALSE)
  if (!exists(env_obj, envir = e2)) stop("缺少 ", env_obj, " in ", env_path, call. = FALSE)
  data <- get(clin_obj, envir = e1)
  environment_data <- get(env_obj, envir = e2)

  if (!"Group" %in% names(environment_data) && "DN" %in% names(environment_data)) {
    environment_data$Group <- environment_data$DN
  }
  if (!"Group" %in% names(data) && "DN" %in% names(data)) {
    data$Group <- data$DN
  }

  voc_cols <- setdiff(names(environment_data), c("Group", "SEQN", "DN"))
  voc_exclude <- unique(as.character(cfg$voc_exclude_fixed %||% character(0)))
  voc_exclude <- voc_exclude[nzchar(voc_exclude)]
  if (length(voc_exclude)) {
    dropped_ex <- intersect(voc_cols, voc_exclude)
    if (length(dropped_ex)) {
      cli::cli_alert_warning(
        "prepare nhanes: voc_exclude_fixed 剔除 {length(dropped_ex)} 个: {paste(dropped_ex, collapse = ', ')}"
      )
    }
    voc_cols <- setdiff(voc_cols, voc_exclude)
  }
  env_voc_cols <- voc_cols
  if (isTRUE(cfg$include_tne2_in_voc %||% TRUE) &&
      "TNE_2" %in% names(data) && !"TNE_2" %in% voc_cols) {
    voc_cols <- c(voc_cols, "TNE_2")
  }

  data$SEQN <- as.numeric(as.character(data$SEQN))
  environment_data$SEQN <- as.numeric(as.character(environment_data$SEQN))

  if (!"Gender" %in% names(data)) {
    g_path <- file.path(nhanes_dir, cfg$gender_file %||% "D01_data.RData")
    if (file.exists(g_path)) {
      eg <- new.env(); load(g_path, envir = eg)
      g_obj <- cfg$gender_obj %||% "data"
      if (exists(g_obj, envir = eg) && "Gender" %in% names(get(g_obj, envir = eg))) {
        gender_df <- unique(get(g_obj, envir = eg)[, c("SEQN", "Gender"), drop = FALSE])
        gender_df$SEQN <- as.numeric(as.character(gender_df$SEQN))
        gtab <- table(gender_df$Gender)
        if (length(gtab) >= 2L && min(gtab) > 0L) {
          data <- merge(data, gender_df, by = "SEQN", all.x = TRUE, sort = FALSE)
        } else {
          cli::cli_alert_warning(
            "prepare_environment_dkd_data: D01 Gender 仅单一水平，跳过；将使用 baseline Gender。"
          )
        }
      }
    }
  }

  env_keep <- c("SEQN", env_voc_cols)
  if ("Group" %in% names(environment_data) && !"DN" %in% names(data)) {
    env_keep <- c("SEQN", "Group", env_voc_cols)
  }
  EnvResult <- merge(
    data,
    environment_data[, env_keep, drop = FALSE],
    by = "SEQN", all = FALSE, sort = FALSE
  )
  if (!nrow(EnvResult)) stop("临床与环境 SEQN 合并后为空", call. = FALSE)

  EnvResult <- prepare_environment_dkd_rename_clinical(EnvResult)

  survey_bl <- prepare_environment_dkd_load_baseline_survey(
    nhanes_dir, cfg$baseline_pattern %||% "baseline.*NHANES.*\\.RData$"
  )
  bl_path <- attr(survey_bl, "source_path")
  survey_bl$source_path <- NULL

  drop_from_env <- setdiff(intersect(names(EnvResult), names(survey_bl)), "SEQN")
  if (length(drop_from_env)) EnvResult[drop_from_env] <- NULL
  EnvResult <- merge(EnvResult, survey_bl, by = "SEQN", all.x = TRUE, sort = FALSE)
  EnvResult <- prepare_environment_dkd_ensure_outcome_group(EnvResult, list(
    project = cfg$project %||% list(),
    data = cfg$data %||% list()
  ))

  merge_seqn <- EnvResult$SEQN
  cohort_audit <- NULL
  cohort_info <- prepare_environment_dkd_load_cohort_filter(nhanes_dir, cfg)
  if (!is.null(cohort_info)) {
    n_before <- nrow(EnvResult)
    keep_ids <- cohort_info$ids
    excl <- as.numeric(cfg$cohort_exclude_seqn %||% c(81715L, 82257L))
    excl <- excl[is.finite(excl)]
    if (length(excl)) {
      keep_ids <- setdiff(keep_ids, excl)
      cli::cli_alert_info(
        "cohort_exclude_seqn: 剔除 {length(excl)} 人 → {paste(excl, collapse = ', ')}"
      )
    }
    removed_from_merge <- setdiff(merge_seqn, keep_ids)
    added_vs_merge <- setdiff(keep_ids, merge_seqn)
    EnvResult <- EnvResult[EnvResult$SEQN %in% keep_ids, , drop = FALSE]
    target_n <- as.integer(cfg$cohort_target_n %||% NA_integer_)[1L]
    if (!is.na(target_n) && nrow(EnvResult) != target_n) {
      stop(
        "cohort_target_n=", target_n, " 但过滤后为 ", nrow(EnvResult),
        " 人；请检查 D01/D02 源文件与 cohort_filter / cohort_exclude_seqn。",
        call. = FALSE
      )
    }
    cohort_audit <- data.frame(
      SEQN = c(removed_from_merge, added_vs_merge),
      Change = c(
        rep("removed_from_D02_merge", length(removed_from_merge)),
        rep("added_in_cohort_filter", length(added_vs_merge))
      ),
      stringsAsFactors = FALSE
    )
    cli::cli_alert_info(
      "cohort_filter: {basename(cohort_info$path)} → {nrow(EnvResult)} 行（合并后 {n_before} → 过滤后 {nrow(EnvResult)}）"
    )
    if (length(removed_from_merge)) {
      cli::cli_alert_info(
        "相对合并队列移除 {length(removed_from_merge)} 人: {paste(removed_from_merge, collapse = ', ')}"
      )
    }
    if (length(added_vs_merge)) {
      cli::cli_alert_warning(
        "cohort_filter 含合并队列中不存在的 {length(added_vs_merge)} 人: {paste(added_vs_merge, collapse = ', ')}"
      )
    }
  }

  env_wt <- prepare_environment_dkd_load_env_weights(nhanes_dir, cfg)
  if (!is.null(env_wt)) {
    wt_path <- attr(env_wt, "source_path")
    EnvResult$WTSA2YR <- NULL
    EnvResult <- merge(EnvResult, env_wt, by = "SEQN", all.x = TRUE, sort = FALSE)
    EnvResult <- prepare_environment_filter_env_weight_rows(EnvResult, cfg)
    EnvResult <- prepare_environment_dkd_apply_pooled_weight(
      EnvResult,
      wt2_col = "WTSA2YR",
      wt_col = cfg$merged_weight_col %||% "new_Weight",
      fallback_wt2_col = if (isTRUE(cfg$env_weight_fallback_wtmec %||% TRUE)) "WTMEC2YR" else ""
    )
    cli::cli_alert_success(
      "环境权重: {basename(wt_path)} → WTSA2YR → {cfg$merged_weight_col %||% 'new_Weight'}"
    )
  }

  n_wt <- sum(is.finite(EnvResult$WTMEC2YR) & EnvResult$WTMEC2YR > 0, na.rm = TRUE)
  if (n_wt < nrow(EnvResult)) {
    stop(
      "权重合并后 ", nrow(EnvResult) - n_wt, " 行缺少 WTMEC2YR（共 ", nrow(EnvResult), " 行）",
      call. = FALSE
    )
  }
  nw_col <- cfg$merged_weight_col %||% "new_Weight"
  if (nw_col %in% names(EnvResult)) {
    n_nw <- sum(is.finite(EnvResult[[nw_col]]) & EnvResult[[nw_col]] > 0, na.rm = TRUE)
    if (n_nw < nrow(EnvResult)) {
      stop(
        "分析权重 ", nw_col, " 有效行仅 ", n_nw, " / ", nrow(EnvResult),
        call. = FALSE
      )
    }
  }

  out_path <- NULL
  if (isTRUE(cfg$save_merged %||% TRUE)) {
    merged_file <- cfg$merged_file %||% "D03_EnvResultData.RData"
    merged_obj  <- cfg$merged_obj %||% "EnvResult"
    save_dir <- cfg$merged_output_dir %||% nhanes_dir
    if (!is_absolute_path(save_dir)) save_dir <- file.path(root, save_dir)
    dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(save_dir, merged_file)
    tmp <- EnvResult
    assign(merged_obj, tmp)
    save(list = merged_obj, file = out_path)
    voc_path <- file.path(save_dir, cfg$voc_columns_file %||% "voc_columns.RData")
    save(voc_columns = voc_cols, file = voc_path)
  }

  list(
    EnvResult      = EnvResult,
    voc_columns    = voc_cols,
    baseline_path  = bl_path,
    out_path       = out_path,
    nhanes_dir     = nhanes_dir,
    cohort_audit   = cohort_audit,
    cohort_filter  = cohort_info
  )
}
