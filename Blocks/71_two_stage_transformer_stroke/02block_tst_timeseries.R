###############################################################################
#  tst_timeseries — 小时/天粒度长表整理、特征覆盖率审计、导出 Python 可读长表
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §2 §4
#
#  数据粒度说明【证据绑定，非臆造】：
#    mimic-实验室指标-all-1~30天.csv 实际是「宽表」，按 lab{D}_<feature>（D=1..30）
#    编码逐日快照（3423 列 = 3 个 ID 列 + 30 天 × 57 项特征 × 2（数值+单位 _uom））。
#    源数据本身不含小时级
#    时间戳，因此本块导出的 hour 列按 hour = day * 24（该日终点）编码，代表
#    landmark 24/48/72/96/120h 恰好对应 day 1..5，不做小时内插值/伪造。
#
#  Consumes:
#    ctx$data$tst_cohort（tst_cohort 之后；需 patient key / outcome / los 列）
#    ctx$config$data$lab_long_path
#    ctx$config$tst_stroke$landmarks（默认 24/48/72/96/120）
#
#  Produces:
#    ctx$data$tst_timeseries_long   长表（patient, day, hour, <kept 特征...>, label, los_days）
#    Tables/_tst_hourly_long.csv    同上，写在本块 step 子目录（不镜像根目录）
#    Tables/_tst_feature_coverage_audit.csv  57 项特征 day1 缺失率 + 保留/剔除决策
#    ctx$results$tst_timeseries = list(
#      n_rows=, n_patients=, n_features_total=, n_features_kept=,
#      features_kept=, features_dropped=, feature_missing_threshold=,
#      landmarks=, max_day=, hourly_long_path=, lab_key=, note=
#    )
#
#  config$tst_timeseries（可选，全部有默认值）：
#    feature_missing_threshold = 0.30  # day1 缺失率 > 阈值则剔除该特征（与插补 30% 对齐）
#    min_longitudinal_days = 1L       # 1=不按「≥2 观测日」剔除；仅保证至少有长表行
#    temporal_forward_fill = TRUE     # 时序特征按患者×天前向填充（对齐原文 Methods）
#    pause_enable = TRUE
###############################################################################

.tst02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block = "tst_timeseries", reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion, call. = FALSE)
}

.tst02_read_lab_header <- function(path) {
  con <- file(path, "r", encoding = "UTF-8")
  hdr <- readLines(con, n = 1L)
  close(con)
  strsplit(gsub("\"", "", hdr), ",")[[1]]
}

.tst02_read_lab_wide <- function(path, select_cols) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    as.data.frame(data.table::fread(path, select = select_cols, showProgress = FALSE))
  } else {
    all_cols <- .tst02_read_lab_header(path)
    cc <- rep("NULL", length(all_cols))
    cc[all_cols %in% select_cols] <- NA_character_
    names(cc) <- all_cols
    utils::read.csv(path, colClasses = cc, stringsAsFactors = FALSE)
  }
}

block_tst_timeseries <- function(ctx, ...) {
  cfg    <- ctx$config
  dc     <- cfg$data %||% list()
  ts_cfg <- cfg$tst_timeseries %||% list()

  cohort <- ctx$data$tst_cohort
  if (is.null(cohort) || !is.data.frame(cohort) || nrow(cohort) == 0L) {
    .tst02_pause(
      ctx, "tst_timeseries 无 ctx$data$tst_cohort（tst_cohort 未运行或队列为空）",
      "请先运行 tst_cohort。"
    )
  }
  patient_key <- ctx$results$tst_cohort$patient_key %||% "tst_patient_id"
  outcome_col <- ctx$results$tst_cohort$outcome_column %||% dc$outcome_column %||% "is_hosp_dead"
  if (!"tst_patient_id" %in% names(cohort) || !outcome_col %in% names(cohort)) {
    .tst02_pause(
      ctx, "ctx$data$tst_cohort 缺少 tst_patient_id 或结局列",
      "检查 tst_cohort 的产出是否被下游改写。", utils::head(cohort, 5L)
    )
  }
  los_col <- intersect(c("icu_day", "hosp_day"), names(cohort))[1L]
  if (is.na(los_col) || is.null(los_col) || !length(los_col)) {
    cli::cli_alert_warning("tst_timeseries: 队列无 icu_day/hosp_day，los_days 列将缺失（【证据不足】不臆造住院时长）")
    los_col <- NULL
  }

  lab_path <- as.character(dc$lab_long_path %||% "")[1L]
  if (!nzchar(lab_path) || !file.exists(lab_path)) {
    .tst02_pause(ctx, paste0("lab_long_path 无效或不存在: ", lab_path),
                 "检查 config$data$lab_long_path。")
  }

  landmarks <- as.integer(cfg$tst_stroke$landmarks %||% c(24L, 48L, 72L, 96L, 120L))
  # 滑动窗口需要对 >5 天导出更长日历日；默认 30（与 lab1_..lab30_ 对齐）
  max_day_landmark <- as.integer(ceiling(max(landmarks) / 24))
  max_day_cfg <- as.integer(ts_cfg$max_export_day %||% cfg$tst_stroke$max_calendar_day %||% max_day_landmark)[1L]
  sliding <- isTRUE(ts_cfg$sliding_window %||% cfg$tst_stroke$sliding_window %||% TRUE)
  if (sliding) {
    max_day <- max(max_day_landmark, max_day_cfg)
  } else {
    max_day <- max_day_landmark
  }
  cli::cli_alert_info(
    "tst_timeseries: max_day={max_day}（landmark_max={max_day_landmark}, sliding={sliding}）"
  )

  all_cols <- .tst02_read_lab_header(lab_path)
  id_cols <- intersect(c("subject_id", "stay_id", "hadm_id"), all_cols)
  day_prefixes <- paste0("^lab", seq_len(max_day), "_")
  val_cols <- all_cols[grepl(paste(day_prefixes, collapse = "|"), all_cols) & !grepl("_uom$", all_cols)]
  if (!length(val_cols)) {
    .tst02_pause(ctx, "长表未匹配到任何 day1..maxday 数值列（lab{d}_*，非 _uom）",
                 "检查 lab_long_path 表头命名规则是否变化。")
  }
  select_cols <- unique(c(id_cols, val_cols))
  lab_wide <- .tst02_read_lab_wide(lab_path, select_cols)

  lab_key <- intersect(c(patient_key, "stay_id", "subject_id"), names(lab_wide))[1L]
  if (is.na(lab_key) || !length(lab_key)) {
    .tst02_pause(ctx, "长表与队列 patient_key 无可用交集列（stay_id/subject_id）",
                 "检查 tst_cohort$patient_key 与长表 ID 列是否一致。", utils::head(lab_wide, 5L))
  }

  day1_cols <- val_cols[grepl("^lab1_", val_cols)]
  feat_names <- sub("^lab1_", "", day1_cols)
  # 覆盖率在「已 merge 的队列患者」上算，避免全库稀释
  lab_in_cohort <- lab_wide[lab_wide[[lab_key]] %in% cohort$tst_patient_id, , drop = FALSE]
  if (!nrow(lab_in_cohort)) {
    .tst02_pause(ctx, "长表与队列 ID 无交集，无法计算纵向覆盖率",
                 "检查 tst_cohort$patient_key 与 lab 表 ID。", utils::head(lab_wide, 5L))
  }
  miss_rate <- vapply(day1_cols, function(cc) {
    if (!cc %in% names(lab_in_cohort)) return(1)
    mean(is.na(lab_in_cohort[[cc]]))
  }, numeric(1))
  cov_threshold <- as.numeric(ts_cfg$feature_missing_threshold %||% 0.30)[1L]
  keep_feat <- feat_names[miss_rate <= cov_threshold]
  drop_feat <- setdiff(feat_names, keep_feat)

  coverage_audit <- data.frame(
    feature = feat_names,
    day1_missing_pct = round(miss_rate * 100, 1),
    threshold_pct = round(cov_threshold * 100, 1),
    action = ifelse(feat_names %in% keep_feat, "KEPT", "DROPPED"),
    stringsAsFactors = FALSE
  )
  coverage_audit <- coverage_audit[order(coverage_audit$day1_missing_pct), ]
  ctx <- save_result(ctx, "tst_feature_coverage_audit", coverage_audit,
                      "_tst_feature_coverage_audit.csv")

  if (!length(keep_feat)) {
    .tst02_pause(
      ctx, sprintf("覆盖率阈值 %.0f%% 下无任何特征通过筛选", 100 * cov_threshold),
      "放宽 config$tst_timeseries$feature_missing_threshold。", coverage_audit
    )
  }
  cli::cli_alert_info(
    "tst_timeseries: 特征覆盖率筛选（day1 缺失率<={round(100 * cov_threshold, 0)}%）保留 {length(keep_feat)}/{length(feat_names)} 项"
  )

  day_frames <- vector("list", max_day)
  n_lab_rows <- nrow(lab_wide)
  for (d in seq_len(max_day)) {
    cols_d <- paste0("lab", d, "_", keep_feat)
    present <- cols_d %in% names(lab_wide)
    m <- matrix(NA_real_, nrow = n_lab_rows, ncol = length(keep_feat))
    if (any(present)) {
      sub_vals <- lab_wide[, cols_d[present], drop = FALSE]
      m[, present] <- vapply(sub_vals, function(x) suppressWarnings(as.numeric(x)), numeric(n_lab_rows))
    }
    df_d <- as.data.frame(m)
    names(df_d) <- keep_feat
    df_d$tst_patient_id <- lab_wide[[lab_key]]
    df_d$day <- d
    df_d$hour <- d * 24L
    day_frames[[d]] <- df_d
  }
  long_df <- do.call(rbind, day_frames)

  cohort_small_cols <- unique(c("tst_patient_id", outcome_col, los_col))
  cohort_small <- cohort[, cohort_small_cols, drop = FALSE]
  names(cohort_small)[names(cohort_small) == outcome_col] <- "label"
  if (!is.null(los_col)) names(cohort_small)[names(cohort_small) == los_col] <- "los_days"

  long_df <- merge(long_df, cohort_small, by = "tst_patient_id", all.x = FALSE)
  names(long_df)[names(long_df) == "tst_patient_id"] <- "patient"

  # —— 患者级缺失剔除（对齐原文 Methods：records with >30% missing 排除）——
  # 在「已保留特征 × 前 patient_missing_days 天」上、前向填充之前计算缺失率。
  # 先做特征可用性（day1≤30%）再剔患者，避免 57 维全上导致 0 人。
  patient_miss_thr <- as.numeric(ts_cfg$patient_missing_threshold %||% 0.30)[1L]
  patient_miss_days <- as.integer(ts_cfg$patient_missing_days %||% 5L)[1L]
  patient_miss_days <- max(1L, min(patient_miss_days, max_day))
  n_before_patient <- length(unique(long_df$patient))
  miss_eval <- long_df[long_df$day <= patient_miss_days, , drop = FALSE]
  feat_mat0 <- as.matrix(miss_eval[, keep_feat, drop = FALSE])
  storage.mode(feat_mat0) <- "numeric"
  miss_by_row <- rowMeans(is.na(feat_mat0))
  miss_by_pat <- tapply(miss_by_row, miss_eval$patient, mean)
  eligible_by_miss <- names(miss_by_pat)[as.numeric(miss_by_pat) <= patient_miss_thr]
  long_df <- long_df[as.character(long_df$patient) %in% eligible_by_miss, , drop = FALSE]
  n_after_patient <- length(unique(long_df$patient))
  cli::cli_alert_info(
    "tst_timeseries: 患者缺失≤{round(100 * patient_miss_thr, 0)}%（前 {patient_miss_days} 天 × {length(keep_feat)} 特征，前向填前）{n_before_patient} → {n_after_patient} 人（剔除 {n_before_patient - n_after_patient}）"
  )
  if (n_after_patient == 0L) {
    .tst02_pause(
      ctx,
      sprintf("患者缺失≤%.0f%% 入排后队列为空", 100 * patient_miss_thr),
      "检查特征筛选与 patient_missing_threshold / patient_missing_days。"
    )
  }

  # 时序前向填充（对齐原文 Methods：temporal forward imputation）
  # 按 patient × day 升序，对保留特征列做 na.locf；首日仍缺失则保留 NA（不后向填，不臆造）。
  do_ffill <- isTRUE(ts_cfg$temporal_forward_fill %||% TRUE)
  n_na_before_ffill <- sum(is.na(long_df[, keep_feat, drop = FALSE]))
  if (do_ffill && length(keep_feat) && nrow(long_df)) {
    long_df <- long_df[order(long_df$patient, long_df$day), , drop = FALSE]
    if (requireNamespace("data.table", quietly = TRUE)) {
      dt <- data.table::as.data.table(long_df)
      for (cc in keep_feat) {
        data.table::set(dt, j = cc, value = as.numeric(dt[[cc]]))
      }
      dt[, (keep_feat) := lapply(.SD, function(x) {
        # 组内前向填充
        if (all(is.na(x))) return(x)
        last <- NA_real_
        out <- x
        for (i in seq_along(x)) {
          if (!is.na(x[i])) last <- x[i] else if (!is.na(last)) out[i] <- last
        }
        out
      }), by = patient, .SDcols = keep_feat]
      long_df <- as.data.frame(dt)
    } else {
      # 无 data.table 时按患者循环（较慢，仅兜底）
      split_idx <- split(seq_len(nrow(long_df)), long_df$patient)
      for (ix in split_idx) {
        for (cc in keep_feat) {
          x <- long_df[[cc]][ix]
          last <- NA_real_
          for (j in seq_along(x)) {
            if (!is.na(x[j])) last <- x[j] else if (!is.na(last)) x[j] <- last
          }
          long_df[[cc]][ix] <- x
        }
      }
    }
  }
  n_na_after_ffill <- sum(is.na(long_df[, keep_feat, drop = FALSE]))
  cli::cli_alert_info(
    "tst_timeseries: 时序前向填充={do_ffill}；特征 NA {n_na_before_ffill} → {n_na_after_ffill}"
  )

  # 纵向观测日入排：默认关闭「≥2 天」硬门槛（min_longitudinal_days=1）
  min_days <- as.integer(ts_cfg$min_longitudinal_days %||% 1L)[1L]
  n_before_long <- n_after_patient
  if (min_days > 1L) {
    feat_mat <- as.matrix(long_df[, keep_feat, drop = FALSE])
    storage.mode(feat_mat) <- "numeric"
    day_has <- rowSums(!is.na(feat_mat)) > 0
    n_obs_days <- tapply(day_has, long_df$patient, sum)
    eligible_ids <- names(n_obs_days)[as.integer(n_obs_days) >= min_days]
    long_df <- long_df[as.character(long_df$patient) %in% eligible_ids, , drop = FALSE]
    n_after_long <- length(unique(long_df$patient))
    cli::cli_alert_info(
      "tst_timeseries: 纵向≥{min_days} 天入排 {n_before_long} → {n_after_long} 人（剔除 {n_before_long - n_after_long}）"
    )
  } else {
    eligible_ids <- as.character(unique(long_df$patient))
    n_after_long <- n_before_long
    cli::cli_alert_info(
      "tst_timeseries: 不按≥2 观测日剔除（min_longitudinal_days={min_days}），保留 {n_after_long} 人"
    )
  }
  if (n_after_long == 0L) {
    .tst02_pause(
      ctx,
      sprintf("纵向入排后队列为空（min_longitudinal_days=%d）", min_days),
      "检查 lab 长表覆盖，或调整 config$tst_timeseries$min_longitudinal_days。"
    )
  }

  # 同步收紧队列，供后续 imputation / baseline 只用入选患者
  cohort2 <- cohort[as.character(cohort$tst_patient_id) %in% eligible_ids, , drop = FALSE]
  ctx$data$tst_cohort <- cohort2
  ctx$data$cleaned <- cohort2
  if (!is.null(ctx$data$mapped)) ctx$data$mapped <- cohort2
  if (!is.null(ctx$results$tst_cohort) && is.list(ctx$results$tst_cohort)) {
    ctx$results$tst_cohort$n_out <- nrow(cohort2)
    ctx$results$tst_cohort$n_longitudinal_ge_min <- n_after_long
    ctx$results$tst_cohort$min_longitudinal_days <- min_days
    ctx$results$tst_cohort$n_before_longitudinal <- n_before_patient
    ctx$results$tst_cohort$n_after_patient_missing <- n_after_patient
    ctx$results$tst_cohort$patient_missing_threshold <- patient_miss_thr
  }

  col_order <- c("patient", "day", "hour", keep_feat, "label",
                 if (!is.null(los_col)) "los_days")
  long_df <- long_df[, col_order, drop = FALSE]
  long_df <- long_df[order(long_df$patient, long_df$day), , drop = FALSE]

  out_path <- file.path(ctx$output_dir_tables, "_tst_hourly_long.csv")
  utils::write.csv(long_df, out_path, row.names = FALSE)
  cli::cli_alert_success("tst_timeseries: 导出长表 {.file {out_path}}（{nrow(long_df)} 行 x {ncol(long_df)} 列）")

  ctx$data$tst_timeseries_long <- long_df
  ctx$results$tst_timeseries <- list(
    n_rows = nrow(long_df),
    n_patients = length(unique(long_df$patient)),
    n_patients_before_patient_missing = n_before_patient,
    n_patients_after_patient_missing = n_after_patient,
    n_patients_before_long_filter = n_before_long,
    n_features_total = length(feat_names),
    n_features_kept = length(keep_feat),
    features_kept = keep_feat,
    features_dropped = drop_feat,
    feature_missing_threshold = cov_threshold,
    patient_missing_threshold = patient_miss_thr,
    patient_missing_days = patient_miss_days,
    min_longitudinal_days = min_days,
    temporal_forward_fill = do_ffill,
    n_na_before_ffill = n_na_before_ffill,
    n_na_after_ffill = n_na_after_ffill,
    landmarks = landmarks,
    max_day = max_day,
    hourly_long_path = out_path,
    lab_key = lab_key,
    note = paste0(
      "day1 feature thr<=", round(100 * cov_threshold, 0), "%; ",
      "patient miss<=", round(100 * patient_miss_thr, 0), "% on day1..", patient_miss_days,
      " BEFORE forward-fill; then ffill; expand_hours+sliding in Python; Day-k = prior k-1 days"
    )
  )
  ctx
}

register_block(
  "tst_timeseries", block_tst_timeseries,
  "两阶段 Transformer 卒中：day-level 长表整理 + 特征覆盖率审计 + Python 可读导出"
)
