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

local({
  common <- file.path("Blocks/71_two_stage_transformer_stroke/00tst_common.R")
  root_guess <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  cands <- c(
    common,
    file.path(root_guess, common),
    "/mnt/e/01block/01Block-new-Final/Blocks/71_two_stage_transformer_stroke/00tst_common.R"
  )
  hit <- cands[file.exists(cands)][1L]
  if (length(hit) && !is.na(hit)) source(hit, local = FALSE)
})

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

.tst02_sanitize_feat_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  ifelse(nzchar(x), x, "feat")
}

.tst02_ffill_features <- function(long_df, keep_feat, order_cols, by_col = "patient") {
  if (!nrow(long_df) || !length(keep_feat)) return(long_df)
  long_df <- long_df[do.call(order, long_df[order_cols]), , drop = FALSE]
  if (requireNamespace("data.table", quietly = TRUE)) {
    dt <- data.table::as.data.table(long_df)
    for (cc in keep_feat) {
      data.table::set(dt, j = cc, value = as.numeric(dt[[cc]]))
    }
    dt[, (keep_feat) := lapply(.SD, function(x) {
      if (all(is.na(x))) return(x)
      last <- NA_real_
      out <- x
      for (i in seq_along(x)) {
        if (!is.na(x[i])) last <- x[i] else if (!is.na(last)) out[i] <- last
      }
      out
    }), by = by_col, .SDcols = keep_feat]
    as.data.frame(dt)
  } else {
    split_idx <- split(seq_len(nrow(long_df)), long_df[[by_col]])
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
    long_df
  }
}

.tst02_expand_dense_hour_grid <- function(long_df, feat_cols, max_day) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("dense hour grid 需要 data.table 包", call. = FALSE)
  }
  feat_cols <- intersect(feat_cols, names(long_df))
  dt <- data.table::as.data.table(long_df)
  if ("los_days" %in% names(dt)) {
    pd <- dt[, .(
      max_d = max(1L, min(as.integer(max(los_days, na.rm = TRUE)), max_day))
    ), by = patient]
  } else {
    pd <- dt[, .(max_d = max(1L, min(max(day, na.rm = TRUE), max_day))), by = patient]
  }
  grid <- pd[, {
    dd <- seq_len(max_d)
    .(day = rep(dd, each = 24L), hour = rep(0:23, times = length(dd)))
  }, by = patient]
  meta <- unique(dt[, intersect(c("patient", "label", "los_days"), names(dt)), with = FALSE],
                 by = "patient")
  grid <- merge(grid, meta, by = "patient", all.x = TRUE)
  obs <- dt[, c("patient", "day", "hour", feat_cols), with = FALSE]
  grid <- merge(grid, obs, by = c("patient", "day", "hour"), all.x = TRUE)
  as.data.frame(grid)
}

.tst02_day1_miss_rate <- function(long_df, feat_names) {
  day1 <- long_df[long_df$day == 1L, , drop = FALSE]
  vapply(feat_names, function(fnm) {
    if (!fnm %in% names(day1) || !nrow(day1)) return(1)
    mean(is.na(day1[[fnm]]))
  }, numeric(1))
}

#' 将 baseline/cohort 静态列广播到每个 patient×day×hour 行（数值化）
.tst02_broadcast_static_features <- function(long_df, cohort_df, static_cols) {
  static_cols <- unique(as.character(static_cols %||% character(0)))
  static_cols <- static_cols[nzchar(static_cols)]
  if (!length(static_cols) || !nrow(long_df) || !nrow(cohort_df)) {
    return(list(long_df = long_df, added = character(0)))
  }
  if (!"tst_patient_id" %in% names(cohort_df)) {
    cli::cli_alert_warning("static_features: cohort 无 tst_patient_id，跳过静态广播")
    return(list(long_df = long_df, added = character(0)))
  }
  present <- intersect(static_cols, names(cohort_df))
  missing <- setdiff(static_cols, present)
  if (length(missing)) {
    cli::cli_alert_warning("static_features 在 cohort 中缺失: {paste(missing, collapse = ', ')}")
  }
  if (!length(present)) {
    return(list(long_df = long_df, added = character(0)))
  }
  src <- cohort_df[, c("tst_patient_id", present), drop = FALSE]
  names(src)[1] <- "patient"
  src$patient <- as.character(src$patient)
  for (col in present) {
    v <- src[[col]]
    if (is.factor(v) || is.character(v)) {
      vl <- tolower(trimws(as.character(v)))
      mapped <- rep(NA_real_, length(vl))
      mapped[vl %in% c("1", "yes", "y", "true", "male", "m")] <- 1
      mapped[vl %in% c("0", "no", "n", "false", "female", "f")] <- 0
      if (mean(is.na(mapped)) > 0.5) {
        mapped <- as.numeric(factor(vl, levels = unique(vl[!is.na(vl) & nzchar(vl)]))) - 1
      }
      src[[col]] <- mapped
    } else {
      src[[col]] <- suppressWarnings(as.numeric(v))
    }
    new_name <- if (startsWith(col, "static_")) col else paste0("static_", col)
    names(src)[names(src) == col] <- new_name
  }
  added <- setdiff(names(src), "patient")
  for (col in added) {
    med <- stats::median(src[[col]], na.rm = TRUE)
    if (!is.finite(med)) med <- 0
    src[[col]][!is.finite(src[[col]])] <- med
  }
  long_df$patient <- as.character(long_df$patient)
  drop_old <- intersect(added, names(long_df))
  if (length(drop_old)) long_df[drop_old] <- NULL
  long_df <- merge(long_df, src, by = "patient", all.x = TRUE)
  for (col in added) {
    if (col %in% names(long_df)) {
      med <- stats::median(long_df[[col]], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      long_df[[col]][!is.finite(long_df[[col]])] <- med
    }
  }
  cli::cli_alert_info(
    "tst_timeseries: 静态广播 {length(added)} 列 → {paste(added, collapse = ', ')}"
  )
  list(long_df = long_df, added = added)
}

.tst02_build_eicu_hourly_long <- function(lab_path, cohort, patient_key, ts_cfg, max_day,
                                          project_root = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("eicu_hourly_long 需要 data.table 包", call. = FALSE)
  }
  if (!exists("tst_density_gate_select", mode = "function")) {
    cands <- c(
      file.path(as.character(project_root %||% "")[1L], "R/tst_feature_density_gate.R"),
      file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""), "R/tst_feature_density_gate.R"),
      "/mnt/e/01block/01Block-new-Final/R/tst_feature_density_gate.R"
    )
    dg <- cands[file.exists(cands)][1L]
    if (!length(dg) || is.na(dg)) {
      stop("找不到 R/tst_feature_density_gate.R", call. = FALSE)
    }
    source(dg, local = FALSE)
  }
  val_col <- as.character(ts_cfg$value_col %||% "mean")[1L]
  id_col <- as.character(ts_cfg$hourly_id_col %||% "patientunitstayid")[1L]
  lab <- data.table::as.data.table(data.table::fread(lab_path, showProgress = FALSE))
  if (!all(c(id_col, "item", "hour", val_col) %in% names(lab))) {
    stop(
      "eicu_hourly_long 缺少列: 需要 ", id_col, ", item, hour, ", val_col,
      call. = FALSE
    )
  }
  lab[[id_col]] <- as.character(lab[[id_col]])
  lab <- lab[lab[[id_col]] %in% as.character(cohort$tst_patient_id)]
  if (!nrow(lab)) {
    stop("eicu 小时长表与队列 ID 无交集", call. = FALSE)
  }
  lab[, hour := as.integer(hour)]
  lab <- lab[!is.na(hour) & hour >= 0L & hour < max_day * 24L]
  lab[, day := hour %/% 24L + 1L]
  lab[, hour_in_day := hour %% 24L]
  lab[, val := suppressWarnings(as.numeric(get(val_col)))]

  select_mode <- as.character(ts_cfg$feature_select_mode %||% "coverage")[1L]
  density_meta <- NULL
  skip_feature_drop <- FALSE

  if (select_mode %in% c("density_gate", "whitelist")) {
    priority <- tryCatch(
      tst_load_feature_priority(ts_cfg, project_root = project_root),
      error = function(e) stop(conditionMessage(e), call. = FALSE)
    )
    if (is.null(priority) || !length(priority)) {
      stop(
        "feature_select_mode=", select_mode,
        " 需要 config$tst_timeseries$feature_priority 或 feature_priority_file",
        call. = FALSE
      )
    }
    mp <- tst_priority_item_map(priority)
    lab[, .item_san := .tst02_sanitize_feat_name(item)]
    lab[, feature := {
      it <- as.character(item)
      cn <- unname(mp$item_to_canon[it])
      miss <- is.na(cn) | !nzchar(cn)
      if (any(miss)) {
        cn[miss] <- unname(mp$item_to_canon[.item_san[miss]])
      }
      as.character(cn)
    }]
    clinical_rows <- lab[!is.na(feature) & nzchar(feature) & feature != "NA"]
    available_canon <- unique(as.character(clinical_rows$feature))
    if (!length(available_canon)) {
      stop("density_gate/whitelist: 优先级名单与数据 item 无交集", call. = FALSE)
    }
    n_cohort <- nrow(cohort)

    if (identical(select_mode, "density_gate")) {
      lit_n <- as.numeric(ts_cfg$literature_n_patients %||% 13610L)[1L]
      lit_f <- as.numeric(ts_cfg$literature_n_features %||% 226L)[1L]
      # 补齐池：非临床名单 item，按 day1 患者覆盖率降序
      clinical_items <- names(mp$item_to_canon)
      other <- lab[is.na(feature) | !nzchar(feature) | feature == "NA"]
      other <- other[!.item_san %in% available_canon]
      pad_candidates <- character(0)
      if (nrow(other)) {
        d1 <- other[hour >= 0L & hour < 24L]
        if (nrow(d1)) {
          cov <- d1[, .(n_pat = data.table::uniqueN(get(id_col))), by = ".item_san"]
          data.table::setorder(cov, -n_pat)
          pad_candidates <- cov[[".item_san"]]
        }
      }
      density_meta <- tst_density_gate_select(
        n_cohort = n_cohort,
        available_canon = available_canon,
        canon_order = mp$canon_order,
        pad_candidates = pad_candidates,
        lit_n = lit_n,
        lit_f = lit_f,
        f_star_cap = ts_cfg$density_gate_f_star_cap %||% NULL
      )
      keep_canon <- density_meta$keep_canon
      cli::cli_alert_info(
        paste0(
          "density_gate: N=", density_meta$n_cohort,
          " F_cand=", density_meta$f_cand,
          " F*_ref=", density_meta$f_star,
          " → ", density_meta$decision,
          " n_kept=", density_meta$n_kept,
          if (isTRUE(density_meta$n_padded > 0L)) {
            paste0(" (pad=", density_meta$n_padded, ")")
          } else {
            ""
          },
          " [", paste(keep_canon, collapse = ", "), "]"
        )
      )
      # 临床 canonical + 补齐用 sanitize 名
      lab_clin <- clinical_rows[feature %in% keep_canon]
      pad_names <- setdiff(keep_canon, available_canon)
      if (length(pad_names)) {
        lab_pad <- other[.item_san %in% pad_names]
        lab_pad[, feature := .item_san]
        lab <- data.table::rbindlist(list(lab_clin, lab_pad), use.names = TRUE, fill = TRUE)
      } else {
        lab <- lab_clin
      }
    } else {
      keep_canon <- intersect(mp$canon_order, available_canon)
      density_meta <- list(
        decision = "whitelist_all",
        keep_canon = keep_canon,
        f_cand = length(keep_canon),
        f_star = length(keep_canon),
        n_kept = length(keep_canon),
        n_cohort = n_cohort,
        n_padded = 0L
      )
      cli::cli_alert_info(
        "whitelist: 保留 {length(keep_canon)}/{length(mp$canon_order)} 项（数据中存在）"
      )
      lab <- clinical_rows[feature %in% keep_canon]
    }
    skip_feature_drop <- TRUE
  } else {
    # coverage：不全量白名单限制；可选别名折叠去重，再按 day1 覆盖率预筛
    n_cohort <- nrow(cohort)
    cov_thr <- as.numeric(ts_cfg$feature_missing_threshold %||% 0.30)[1L]
    fold_aliases <- isTRUE(ts_cfg$coverage_fold_aliases %||% TRUE)
    n_folded <- 0L
    lab[, .item_san := .tst02_sanitize_feat_name(item)]
    lab[, feature := .item_san]
    if (fold_aliases) {
      # 别名文件仅用于「同义合并」，不限制只能保留名单内特征
      alias_cfg <- ts_cfg
      if (!nzchar(as.character(alias_cfg$feature_priority_file %||% "")[1L]) &&
            nzchar(as.character(ts_cfg$coverage_alias_file %||% "")[1L])) {
        alias_cfg$feature_priority_file <- ts_cfg$coverage_alias_file
      }
      priority <- tryCatch(
        tst_load_feature_priority(alias_cfg, project_root = project_root),
        error = function(e) NULL
      )
      if (is.list(priority) && length(priority)) {
        mp <- tst_priority_item_map(priority)
        # °F → °C：折叠进 temperature_c 前先换算，避免混单位均值
        if ("temperature_c" %in% mp$canon_order) {
          is_f <- grepl("temperature\\s*\\(f\\)|temp.*fahrenheit|^temperature_f$",
                        as.character(lab$item), ignore.case = TRUE) |
            grepl("^temperature_f$", lab$.item_san)
          if (any(is_f)) {
            lab[is_f & is.finite(val), val := (val - 32) * 5 / 9]
          }
        }
        mapped <- {
          it <- as.character(lab$item)
          cn <- unname(mp$item_to_canon[it])
          miss <- is.na(cn) | !nzchar(cn)
          if (any(miss)) {
            cn[miss] <- unname(mp$item_to_canon[lab$.item_san[miss]])
          }
          as.character(cn)
        }
        hit <- !is.na(mapped) & nzchar(mapped) & mapped != "NA"
        n_folded <- sum(hit)
        if (any(hit)) lab[hit, feature := mapped[hit]]
        cli::cli_alert_info(
          "coverage: 别名折叠 {n_folded} 行 → 标准名（未映射 item 仍保留 sanitize 名，非白名单截断）"
        )
      } else {
        cli::cli_alert_warning(
          "coverage_fold_aliases=TRUE 但无可用别名文件，跳过折叠（可能残留同义重复列）"
        )
      }
    }
    d1 <- lab[hour >= 0L & hour < 24L & is.finite(val)]
    if (!nrow(d1)) {
      stop("coverage: day1 无有效观测，无法按覆盖率选特征", call. = FALSE)
    }
    cov <- d1[, .(n_pat = data.table::uniqueN(get(id_col))), by = "feature"]
    cov[, miss_pct := 1 - n_pat / max(n_cohort, 1L)]
    data.table::setorder(cov, miss_pct, -n_pat)
    keep_pre <- cov[miss_pct <= cov_thr][["feature"]]
    max_f <- as.integer(ts_cfg$coverage_max_features %||% Inf)[1L]
    if (is.finite(max_f) && max_f > 0L && length(keep_pre) > max_f) {
      keep_pre <- keep_pre[seq_len(max_f)]
      cli::cli_alert_info(
        "coverage: day1 缺失≤{round(100 * cov_thr, 0)}% 有 {nrow(cov[miss_pct <= cov_thr])} 项，截断至 coverage_max_features={max_f}"
      )
    }
    if (!length(keep_pre)) {
      stop(
        "coverage: day1 缺失≤", round(100 * cov_thr, 0),
        "% 无可用特征（全队列 N=", n_cohort, "）",
        call. = FALSE
      )
    }
    n_all_feat <- data.table::uniqueN(lab$feature)
    lab <- lab[feature %in% keep_pre]
    density_meta <- list(
      decision = if (fold_aliases && n_folded > 0L) "coverage_prefilter_alias_fold" else "coverage_prefilter",
      keep_canon = keep_pre,
      f_cand = n_all_feat,
      f_star = length(keep_pre),
      n_kept = length(keep_pre),
      n_cohort = n_cohort,
      n_padded = 0L,
      coverage_threshold = cov_thr
    )
    cli::cli_alert_info(
      "coverage: day1 缺失≤{round(100 * cov_thr, 0)}% 预筛 {length(keep_pre)}/{n_all_feat} 项（非白名单限幅；已去同义重复）"
    )
    skip_feature_drop <- TRUE
  }

  wide <- data.table::dcast(
    lab,
    formula = as.formula(paste(id_col, "+ day + hour_in_day ~ feature")),
    value.var = "val",
    fun.aggregate = function(x) {
      x <- x[is.finite(x)]
      if (length(x)) mean(x) else NA_real_
    }
  )
  feat_names <- setdiff(names(wide), c(id_col, "day", "hour_in_day"))
  if (!length(feat_names)) {
    stop("eicu pivot 后无特征列", call. = FALSE)
  }
  if (!is.null(density_meta) && length(density_meta$keep_canon)) {
    feat_names <- intersect(density_meta$keep_canon, feat_names)
  }
  long_df <- as.data.frame(wide[, c(id_col, "day", "hour_in_day", feat_names), with = FALSE])
  names(long_df)[names(long_df) == id_col] <- "tst_patient_id"
  names(long_df)[names(long_df) == "hour_in_day"] <- "hour"
  list(
    long_df = long_df,
    keep_feat = feat_names,
    feat_names = feat_names,
    drop_feat = character(0),
    miss_rate = stats::setNames(rep(NA_real_, length(feat_names)), feat_names),
    lab_key = id_col,
    lab_format = "eicu_hourly_long",
    skip_feature_drop = skip_feature_drop,
    density_meta = density_meta,
    feature_select_mode = select_mode
  )
}

.tst02_build_mimic_day_wide <- function(lab_path, cohort, patient_key, ts_cfg, max_day) {
  all_cols <- .tst02_read_lab_header(lab_path)
  id_cols <- intersect(c("subject_id", "stay_id", "hadm_id"), all_cols)
  day_prefixes <- paste0("^lab", seq_len(max_day), "_")
  val_cols <- all_cols[grepl(paste(day_prefixes, collapse = "|"), all_cols) & !grepl("_uom$", all_cols)]
  if (!length(val_cols)) {
    stop("长表未匹配到 lab{d}_* 数值列", call. = FALSE)
  }
  select_cols <- unique(c(id_cols, val_cols))
  lab_wide <- .tst02_read_lab_wide(lab_path, select_cols)
  lab_key <- intersect(c(patient_key, "stay_id", "subject_id"), names(lab_wide))[1L]
  if (is.na(lab_key) || !length(lab_key)) {
    stop("MIMIC 长表无可用 ID 列", call. = FALSE)
  }
  day1_cols <- val_cols[grepl("^lab1_", val_cols)]
  feat_names <- sub("^lab1_", "", day1_cols)
  lab_in_cohort <- lab_wide[lab_wide[[lab_key]] %in% cohort$tst_patient_id, , drop = FALSE]
  if (!nrow(lab_in_cohort)) {
    stop("MIMIC 长表与队列 ID 无交集", call. = FALSE)
  }
  miss_rate <- vapply(day1_cols, function(cc) {
    if (!cc %in% names(lab_in_cohort)) return(1)
    mean(is.na(lab_in_cohort[[cc]]))
  }, numeric(1))
  cov_threshold <- as.numeric(ts_cfg$feature_missing_threshold %||% 0.30)[1L]
  keep_feat <- feat_names[miss_rate <= cov_threshold]
  drop_feat <- setdiff(feat_names, keep_feat)
  if (!length(keep_feat)) {
    stop(sprintf("day1 覆盖率阈值 %.0f%% 下无保留特征", 100 * cov_threshold), call. = FALSE)
  }
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
  list(
    long_df = long_df,
    keep_feat = keep_feat,
    feat_names = feat_names,
    drop_feat = drop_feat,
    miss_rate = stats::setNames(miss_rate, feat_names),
    lab_key = lab_key,
    lab_format = "mimic_day_wide"
  )
}

block_tst_timeseries <- function(ctx, ...) {
  cfg    <- ctx$config
  dc     <- cfg$data %||% list()
  ts_cfg <- cfg$tst_timeseries %||% list()

  # 病种白名单闸门：禁止他病 priority 文件（见 2026-08-31 design）
  if (!exists("tst_assert_disease_feature_priority", mode = "function")) {
    cands <- c(
      file.path(as.character(cfg$project$root %||% "")[1L], "R/tst_feature_density_gate.R"),
      file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""), "R/tst_feature_density_gate.R"),
      "/mnt/e/01block/01Block-new-Final/R/tst_feature_density_gate.R"
    )
    dg <- cands[file.exists(cands)][1L]
    if (length(dg) && !is.na(dg)) source(dg, local = FALSE)
  }
  if (exists("tst_assert_disease_feature_priority", mode = "function")) {
    tryCatch(
      tst_assert_disease_feature_priority(cfg, ts_cfg),
      error = function(e) {
        .tst02_pause(ctx, conditionMessage(e), "按本病种新建 tst_feature_priority 并改 config。")
      }
    )
  }

  # 文献口径：imputation 在 timeseries 前时，用插补后队列做静态广播
  cohort <- ctx$data$imputed %||% ctx$data$tst_cohort
  if (is.null(cohort) || !is.data.frame(cohort) || nrow(cohort) == 0L) {
    .tst02_pause(
      ctx, "tst_timeseries 无 ctx$data$imputed/tst_cohort（tst_cohort 或 imputation 未运行或队列为空）",
      "请先运行 tst_cohort（建议再跑 imputation）。"
    )
  }
  patient_key <- ctx$results$tst_cohort$patient_key %||% "tst_patient_id"
  outcome_col <- ctx$results$tst_cohort$outcome_column %||% dc$outcome_column %||% "is_hosp_dead"
  if (!"tst_patient_id" %in% names(cohort) || !outcome_col %in% names(cohort)) {
    .tst02_pause(
      ctx, "分析队列缺少 tst_patient_id 或结局列",
      "检查 tst_cohort / imputation 产出是否被下游改写。", utils::head(cohort, 5L)
    )
  }
  los_col <- intersect(c("icu_day", "hosp_day", "unitlosday", "hosplosday"), names(cohort))[1L]
  if (is.na(los_col) || is.null(los_col) || !length(los_col)) {
    cli::cli_alert_warning("tst_timeseries: 队列无 icu_day/hosp_day/unitlosday，los_days 列将缺失（【证据不足】不臆造住院时长）")
    los_col <- NULL
  }

  lab_path <- as.character(dc$lab_long_path %||% "")[1L]
  if (!nzchar(lab_path) || !file.exists(lab_path)) {
    .tst02_pause(ctx, paste0("lab_long_path 无效或不存在: ", lab_path),
                 "检查 config$data$lab_long_path。")
  }

  landmarks <- as.integer(cfg$tst_stroke$landmarks %||% c(24L, 48L, 72L, 96L, 120L))
  max_day_landmark <- as.integer(ceiling(max(landmarks) / 24))
  max_day_cfg <- as.integer(ts_cfg$max_export_day %||% cfg$tst_stroke$max_calendar_day %||% max_day_landmark)[1L]
  sliding <- isTRUE(ts_cfg$sliding_window %||% cfg$tst_stroke$sliding_window %||% TRUE)
  max_day <- if (sliding) max(max_day_landmark, max_day_cfg) else max_day_landmark
  cli::cli_alert_info(
    "tst_timeseries: max_day={max_day}（landmark_max={max_day_landmark}, sliding={sliding}）"
  )

  lab_format <- as.character(ts_cfg$lab_format %||% "mimic_day_wide")[1L]
  cli::cli_alert_info("tst_timeseries: lab_format={lab_format}")

  built <- tryCatch(
    if (identical(lab_format, "eicu_hourly_long")) {
      .tst02_build_eicu_hourly_long(
        lab_path, cohort, patient_key, ts_cfg, max_day,
        project_root = cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
      )
    } else {
      .tst02_build_mimic_day_wide(lab_path, cohort, patient_key, ts_cfg, max_day)
    },
    error = function(e) {
      .tst02_pause(ctx, conditionMessage(e), "检查 lab_long_path / lab_format / ID 列。")
    }
  )

  long_df <- built$long_df
  feat_names <- built$feat_names
  lab_key <- built$lab_key
  cov_threshold <- as.numeric(ts_cfg$feature_missing_threshold %||% 0.30)[1L]

  cohort_small_cols <- unique(c("tst_patient_id", outcome_col, los_col))
  cohort_small <- cohort[, cohort_small_cols, drop = FALSE]
  names(cohort_small)[names(cohort_small) == outcome_col] <- "label"
  # 插补 finalize 可能把 0/1 重标成 "Disease"/"No Disease"；训练必须数值 0/1
  if (exists(".tst71_coerce_binary01", mode = "function")) {
    cohort_small$label <- .tst71_coerce_binary01(cohort_small$label, cfg)
  } else {
    cohort_small$label <- suppressWarnings(as.integer(as.character(cohort_small$label)))
  }
  n_lab_na <- sum(is.na(cohort_small$label))
  if (n_lab_na > 0L) {
    cli::cli_alert_warning("tst_timeseries: label 无法解析为 0/1 的行 {n_lab_na}，将随 merge 剔除")
  }
  if (!is.null(los_col)) names(cohort_small)[names(cohort_small) == los_col] <- "los_days"

  long_df <- merge(long_df, cohort_small, by = "tst_patient_id", all.x = FALSE)
  long_df <- long_df[!is.na(long_df$label), , drop = FALSE]
  names(long_df)[names(long_df) == "tst_patient_id"] <- "patient"

  do_ffill <- isTRUE(ts_cfg$temporal_forward_fill %||% TRUE)
  patient_miss_thr <- as.numeric(ts_cfg$patient_missing_threshold %||% 0.30)[1L]
  patient_miss_days <- as.integer(ts_cfg$patient_missing_days %||% 5L)[1L]
  patient_miss_days <- max(1L, min(patient_miss_days, max_day))

  if (identical(lab_format, "eicu_hourly_long")) {
    skip_feat_drop <- isTRUE(built$skip_feature_drop)
    # density_gate：默认仍按 day1 覆盖率砍高缺失列（可用 density_gate_apply_coverage_drop=FALSE 关闭）
    if (identical(as.character(built$feature_select_mode %||% ""), "density_gate")) {
      apply_cov <- isTRUE(ts_cfg$density_gate_apply_coverage_drop %||% TRUE)
      if (apply_cov) skip_feat_drop <- FALSE
    }
    if (identical(as.character(built$feature_select_mode %||% ""), "whitelist")) {
      if (isTRUE(ts_cfg$whitelist_apply_coverage_drop %||% FALSE)) {
        skip_feat_drop <- FALSE
      }
    }
    cli::cli_alert_info(
      if (skip_feat_drop) {
        "eicu_hourly_long: dense 24h 网格 → forward-fill → 特征审计(不砍列) → 患者缺失（density_gate/whitelist）"
      } else {
        "eicu_hourly_long: dense 24h 网格 → forward-fill → day1 特征覆盖率砍列 → 患者缺失"
      }
    )
    long_df <- .tst02_expand_dense_hour_grid(long_df, feat_names, max_day)
    # 逐特征缺失指示（ffill 前）：对齐原文 Supp Table 1 的 *_mask
    add_value_masks <- isTRUE(ts_cfg$feature_value_masks %||% FALSE)
    pre_ffill_mask <- NULL
    if (add_value_masks && length(feat_names)) {
      pre_ffill_mask <- data.frame(
        lapply(feat_names, function(f) as.integer(is.na(long_df[[f]]))),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      names(pre_ffill_mask) <- paste0(feat_names, "_mask")
    }
    n_na_before_ffill <- sum(is.na(long_df[, feat_names, drop = FALSE]))
    if (do_ffill && length(feat_names) && nrow(long_df)) {
      long_df <- .tst02_ffill_features(long_df, feat_names, c("patient", "day", "hour"))
    }
    n_na_after_ffill <- sum(is.na(long_df[, feat_names, drop = FALSE]))
    cli::cli_alert_info(
      "eicu ffill（patient>day>hour）: 特征 NA {n_na_before_ffill} → {n_na_after_ffill}"
    )

    # 可选：先删高缺失患者，再按剩余患者 day1 缺失率砍特征（保留更多高临床价值列）
    drop_patient_before_feat <- isTRUE(ts_cfg$patient_missing_drop_before_feature %||% FALSE)
    if (drop_patient_before_feat) {
      n_before_pd <- length(unique(long_df$patient))
      miss_eval_pd <- long_df[long_df$day <= patient_miss_days, c("patient", feat_names), drop = FALSE]
      feat_mat_pd <- as.matrix(miss_eval_pd[, feat_names, drop = FALSE])
      storage.mode(feat_mat_pd) <- "numeric"
      miss_by_row_pd <- rowMeans(is.na(feat_mat_pd))
      miss_by_pat_pd <- tapply(miss_by_row_pd, miss_eval_pd$patient, mean)
      eligible_pd <- names(miss_by_pat_pd)[as.numeric(miss_by_pat_pd) <= patient_miss_thr]
      long_df <- long_df[as.character(long_df$patient) %in% eligible_pd, , drop = FALSE]
      n_after_pd <- length(unique(long_df$patient))
      cli::cli_alert_info(
        "tst_timeseries: 先删高缺失患者（≤{round(100 * patient_miss_thr, 0)}%，前 {patient_miss_days} 天 × {length(feat_names)} 特征）{n_before_pd} → {n_after_pd} 人（剔除 {n_before_pd - n_after_pd}），再按剩余患者 day1 缺失率砍特征"
      )
    }

    miss_rate <- .tst02_day1_miss_rate(long_df, feat_names)
    if (skip_feat_drop) {
      keep_feat <- feat_names
      drop_feat <- character(0)
      action_vec <- rep("KEPT", length(feat_names))
      audit_stage <- paste0(
        "after_dense_grid_ffill_",
        as.character(built$feature_select_mode %||% "density_gate")
      )
      cli::cli_alert_info(
        "tst_timeseries: {built$feature_select_mode} 保留全部 {length(keep_feat)} 项（day1 缺失仅审计，不砍列）"
      )
    } else {
      force_keep <- unique(as.character(ts_cfg$force_keep_features %||% character(0)))
      force_keep <- force_keep[nzchar(force_keep) & force_keep %in% feat_names]
      keep_feat <- unique(c(feat_names[miss_rate <= cov_threshold], force_keep))
      drop_feat <- setdiff(feat_names, keep_feat)
      action_vec <- ifelse(feat_names %in% keep_feat, "KEPT", "DROPPED")
      # 标注强制保留
      action_vec[feat_names %in% force_keep & miss_rate > cov_threshold] <- "KEPT_FORCE"
      audit_stage <- paste0(
        "after_dense_grid_ffill",
        if (identical(as.character(built$feature_select_mode %||% ""), "density_gate")) {
          "_density_gate_coverage_drop"
        } else {
          ""
        },
        if (length(force_keep)) "_force_keep" else ""
      )
      if (!length(keep_feat)) {
        .tst02_pause(
          ctx,
          sprintf("eicu day1 覆盖率（ffill 后）阈值 %.0f%% 下无保留特征", 100 * cov_threshold),
          "放宽 feature_missing_threshold 或检查小时长表。", utils::head(as.data.frame(t(miss_rate)), 5L)
        )
      }
      cli::cli_alert_info(
        "tst_timeseries: eicu day1 覆盖率（ffill 后）<={round(100 * cov_threshold, 0)}% 保留 {length(keep_feat)}/{length(feat_names)} 项（砍掉 {length(drop_feat)}；force_keep={length(force_keep)}）"
      )
      # 回写 density_gate meta
      if (!is.null(built$density_meta) && is.list(built$density_meta)) {
        built$density_meta$n_kept_after_coverage <- length(keep_feat)
        built$density_meta$n_dropped_coverage <- length(drop_feat)
        built$density_meta$coverage_threshold <- cov_threshold
        built$density_meta$decision <- paste0(
          as.character(built$density_meta$decision %||% "density_gate"),
          "+coverage_drop"
        )
      }
    }
    coverage_audit <- data.frame(
      feature = feat_names,
      day1_missing_pct = round(miss_rate * 100, 1),
      threshold_pct = round(cov_threshold * 100, 1),
      action = action_vec,
      audit_stage = audit_stage,
      stringsAsFactors = FALSE
    )
    coverage_audit <- coverage_audit[order(coverage_audit$day1_missing_pct), ]
    ctx <- save_result(ctx, "tst_feature_coverage_audit", coverage_audit,
                        "_tst_feature_coverage_audit.csv")
    if (!is.null(built$density_meta)) {
      dm <- built$density_meta
      dg_df <- data.frame(
        decision = as.character(dm$decision %||% NA_character_),
        f_cand = as.integer(dm$f_cand %||% NA_integer_),
        f_star = as.integer(dm$f_star %||% NA_integer_),
        n_kept_gate = as.integer(dm$n_kept %||% NA_integer_),
        n_kept = as.integer(length(keep_feat)),
        n_dropped_coverage = as.integer(dm$n_dropped_coverage %||% 0L),
        n_padded = as.integer(dm$n_padded %||% 0L),
        n_cohort = as.integer(dm$n_cohort %||% NA_integer_),
        ratio = as.numeric(length(unique(long_df$patient)) / max(length(keep_feat), 1L)),
        lit_ratio = as.numeric(dm$lit_ratio %||% NA_real_),
        coverage_threshold = as.numeric(dm$coverage_threshold %||% cov_threshold),
        features_kept = paste(keep_feat, collapse = "|"),
        stringsAsFactors = FALSE
      )
      ctx <- save_result(ctx, "tst_density_gate", dg_df, "_tst_density_gate.csv")
    }

    n_before_patient <- length(unique(long_df$patient))
    if (drop_patient_before_feat) {
      # 已在 feature drop 前删过患者，此处仅按 keep_feat 复核（不再重复剔除）
      n_after_patient <- n_before_patient
      cli::cli_alert_info(
        "tst_timeseries: 患者缺失已在特征砍列前处理（{n_after_patient} 人保留，按 {length(keep_feat)} 特征复核）"
      )
    } else {
      # 原文对齐：不砍维时挂 *_mask，剔人分母 = 临床 + mask + 计划静态维（mask/静态视为已观测，稀释缺失率）
      denom_mode <- as.character(ts_cfg$patient_missing_denominator %||% "all_kept")[1L]
      mask_feat <- character(0)
      if (add_value_masks && !is.null(pre_ffill_mask)) {
        mask_feat <- paste0(keep_feat, "_mask")
        miss_m <- setdiff(mask_feat, names(pre_ffill_mask))
        if (length(miss_m)) {
          stop("feature_value_masks: 缺少预计算 mask 列: ", paste(miss_m, collapse = ", "), call. = FALSE)
        }
        for (mf in mask_feat) {
          long_df[[mf]] <- pre_ffill_mask[[mf]]
        }
        cli::cli_alert_info(
          "tst_timeseries: 已挂 {length(mask_feat)} 个特征值 *_mask（ffill 前缺失=1；进模型，对齐原文）"
        )
      }
      static_pad <- as.character(ts_cfg$static_features %||% character(0))
      static_pad <- static_pad[nzchar(static_pad)]
      n_static_pad <- length(static_pad)
      n_clin <- length(keep_feat)
      n_mask <- length(mask_feat)
      use_paper_dilute <- identical(denom_mode, "paper_mask_demo")

      denom_feat <- keep_feat
      if (identical(denom_mode, "day1_core")) {
        cap <- as.numeric(ts_cfg$patient_missing_denom_day1_max %||% 0.40)[1L]
        core <- keep_feat[is.finite(miss_rate[keep_feat]) & miss_rate[keep_feat] <= cap]
        if (length(core) >= 3L) {
          denom_feat <- core
          cli::cli_alert_info(
            "tst_timeseries: 患者缺失分母=day1缺失≤{round(100 * cap, 0)}% 的 {length(denom_feat)}/{length(keep_feat)} 项（稀疏特征仍进模型，不参与剔人）"
          )
        } else {
          cli::cli_alert_warning(
            "patient_missing_denominator=day1_core 不足 3 项，退回全部 {length(keep_feat)} 特征"
          )
        }
      }

      miss_eval <- long_df[long_df$day <= patient_miss_days, , drop = FALSE]
      if (use_paper_dilute && n_mask > 0L) {
        # 剔人用 ffill 后临床 NA（与 all_kept 一致）；*_mask 仍按 ffill 前挂进模型。
        # 禁止用 pre-ffill mask 均值：密网格下几乎人人 >30%，会误剔到个位数。
        # 分母 = 临床 + mask + 静态计划维（后两者视为已观测 → 稀释）
        feat_mat0 <- as.matrix(miss_eval[, keep_feat, drop = FALSE])
        storage.mode(feat_mat0) <- "numeric"
        miss_clin_row <- rowMeans(is.na(feat_mat0))
        n_denom_dim <- n_clin + n_mask + n_static_pad
        miss_by_row <- miss_clin_row * (n_clin / max(n_denom_dim, 1L))
        cli::cli_alert_info(
          "tst_timeseries: 患者缺失分母=paper_mask_demo（ffill后临床缺失×{n_clin}/{n_denom_dim}；mask{n_mask}+静态垫{n_static_pad}）"
        )
      } else if (identical(denom_mode, "day1_core")) {
        feat_mat0 <- as.matrix(miss_eval[, denom_feat, drop = FALSE])
        storage.mode(feat_mat0) <- "numeric"
        miss_by_row <- rowMeans(is.na(feat_mat0))
      } else {
        feat_mat0 <- as.matrix(miss_eval[, keep_feat, drop = FALSE])
        storage.mode(feat_mat0) <- "numeric"
        miss_by_row <- rowMeans(is.na(feat_mat0))
      }
      miss_by_pat <- tapply(miss_by_row, miss_eval$patient, mean)
      eligible_by_miss <- names(miss_by_pat)[as.numeric(miss_by_pat) <= patient_miss_thr]
      keep_cols <- unique(c("patient", "day", "hour", keep_feat, mask_feat, "label", "los_days"))
      keep_cols <- intersect(keep_cols, names(long_df))
      long_df <- long_df[as.character(long_df$patient) %in% eligible_by_miss, keep_cols, drop = FALSE]
      n_after_patient <- length(unique(long_df$patient))
      if (length(mask_feat)) {
        keep_feat <- unique(c(keep_feat, mask_feat))
      }
      cli::cli_alert_info(
        "tst_timeseries: 患者缺失≤{round(100 * patient_miss_thr, 0)}%（前 {patient_miss_days} 天，mode={denom_mode}）{n_before_patient} → {n_after_patient} 人（剔除 {n_before_patient - n_after_patient}）；模型动态维={length(keep_feat)}"
      )
    }
    ffill_order <- c("patient", "day", "hour")
  } else {
    keep_feat <- built$keep_feat
    drop_feat <- built$drop_feat
    coverage_audit <- data.frame(
      feature = feat_names,
      day1_missing_pct = round(unname(built$miss_rate[feat_names]) * 100, 1),
      threshold_pct = round(cov_threshold * 100, 1),
      action = ifelse(feat_names %in% keep_feat, "KEPT", "DROPPED"),
      audit_stage = "before_ffill_mimic_day_wide",
      stringsAsFactors = FALSE
    )
    coverage_audit <- coverage_audit[order(coverage_audit$day1_missing_pct), ]
    ctx <- save_result(ctx, "tst_feature_coverage_audit", coverage_audit,
                        "_tst_feature_coverage_audit.csv")
    cli::cli_alert_info(
      "tst_timeseries: 特征覆盖率筛选（day1 缺失率<={round(100 * cov_threshold, 0)}%）保留 {length(keep_feat)}/{length(feat_names)} 项"
    )

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

    n_na_before_ffill <- sum(is.na(long_df[, keep_feat, drop = FALSE]))
    ffill_order <- c("patient", "day")
    if (do_ffill && length(keep_feat) && nrow(long_df)) {
      long_df <- .tst02_ffill_features(long_df, keep_feat, ffill_order)
    }
    n_na_after_ffill <- sum(is.na(long_df[, keep_feat, drop = FALSE]))
    cli::cli_alert_info(
      "tst_timeseries: 时序前向填充={do_ffill}（order={paste(ffill_order, collapse='>')}）；特征 NA {n_na_before_ffill} → {n_na_after_ffill}"
    )
  }

  if (n_after_patient == 0L) {
    .tst02_pause(
      ctx,
      sprintf("患者缺失≤%.0f%% 入排后队列为空", 100 * patient_miss_thr),
      "检查特征筛选与 patient_missing_threshold / patient_missing_days。"
    )
  }

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

  # 同步收紧队列，供后续 baseline / Table1 只用入选患者
  # 必须同时裁 imputed：baseline_binary 优先读 imputed，否则会残留删人前 N（如 15519 vs 14450）
  cohort2 <- cohort[as.character(cohort$tst_patient_id) %in% eligible_ids, , drop = FALSE]
  ctx$data$tst_cohort <- cohort2
  ctx$data$cleaned <- cohort2
  if (!is.null(ctx$data$mapped)) ctx$data$mapped <- cohort2
  if (!is.null(ctx$data$imputed) && is.data.frame(ctx$data$imputed) && nrow(ctx$data$imputed)) {
    imp <- ctx$data$imputed
    id_col_imp <- if ("tst_patient_id" %in% names(imp)) {
      "tst_patient_id"
    } else if ("stay_id" %in% names(imp)) {
      "stay_id"
    } else {
      NA_character_
    }
    if (!is.na(id_col_imp)) {
      n_imp0 <- nrow(imp)
      ctx$data$imputed <- imp[as.character(imp[[id_col_imp]]) %in% eligible_ids, , drop = FALSE]
      cli::cli_alert_info(
        "tst_timeseries: 同步裁剪 imputed {n_imp0} → {nrow(ctx$data$imputed)}（与分析队列一致，供 Table 1）"
      )
    } else {
      cli::cli_alert_warning("tst_timeseries: imputed 无 tst_patient_id/stay_id，未能同步裁剪（Table 1 可能仍用删人前 N）")
    }
  }
  if (!is.null(ctx$results$tst_cohort) && is.list(ctx$results$tst_cohort)) {
    ctx$results$tst_cohort$n_out <- nrow(cohort2)
    ctx$results$tst_cohort$n_longitudinal_ge_min <- n_after_long
    ctx$results$tst_cohort$min_longitudinal_days <- min_days
    ctx$results$tst_cohort$n_before_longitudinal <- n_before_patient
    ctx$results$tst_cohort$n_after_patient_missing <- n_after_patient
    ctx$results$tst_cohort$patient_missing_threshold <- patient_miss_thr
  }

  # 静态特征广播（不参与 day1 coverage 砍列；写在动态 keep_feat 之后）
  static_cfg <- ts_cfg$static_features %||% character(0)
  static_res <- .tst02_broadcast_static_features(long_df, cohort2, static_cfg)
  long_df <- static_res$long_df
  static_added <- static_res$added
  if (length(static_added)) {
    keep_feat <- unique(c(keep_feat, static_added))
  }

  col_order <- c("patient", "day", "hour", keep_feat, "label",
                 if (!is.null(los_col)) "los_days")
  col_order <- intersect(col_order, names(long_df))
  long_df <- long_df[, col_order, drop = FALSE]
  long_df <- long_df[do.call(order, long_df[c("patient", "day", "hour")]), , drop = FALSE]

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
    lab_format = lab_format,
    note = if (identical(lab_format, "eicu_hourly_long")) {
      paste0(
        "eicu_hourly_long; dense 24h grid → ffill → day1 feature audit; value=",
        as.character(ts_cfg$value_col %||% "mean")[1L],
        "; day1 feature thr<=", round(100 * cov_threshold, 0), "% AFTER ffill; ",
        "patient miss<=", round(100 * patient_miss_thr, 0), "% on day1..", patient_miss_days,
        " AFTER ffill; expand_hours=FALSE; offset-nearest not reconstructed"
      )
    } else {
      paste0(
        "mimic_day_wide; day1 feature thr<=", round(100 * cov_threshold, 0), "%; ",
        "patient miss<=", round(100 * patient_miss_thr, 0), "% on day1..", patient_miss_days,
        " BEFORE forward-fill; then ffill; expand_hours+sliding in Python; Day-k = prior k-1 days"
      )
    }
  )

  # Figure 1：在 cohort 纳排后追加时序删人 + 最终分析队列（含存活/死亡，与 Table 1 一致）
  outcome_col_fc <- as.character(cfg$data$outcome_column %||% "is_hosp_dead")[1L]
  n_final_fc <- nrow(cohort2)
  # 用 0/1 强制解析，避免因子/文字标签把存活/死亡写反
  y_fc <- if (exists(".tst71_coerce_binary01", mode = "function")) {
    .tst71_coerce_binary01(cohort2[[outcome_col_fc]], cfg)
  } else {
    suppressWarnings(as.integer(as.character(cohort2[[outcome_col_fc]])))
  }
  n_death_fc <- sum(y_fc == 1L, na.rm = TRUE)
  n_alive_fc <- sum(y_fc == 0L, na.rm = TRUE)
  miss_pct_fc <- round(100 * patient_miss_thr, 0)
  flow_base <- ctx$results$tst_cohort$flowchart
  if (is.null(flow_base) || !is.data.frame(flow_base)) {
    flow_base <- data.frame(stage = character(), n = integer(), stringsAsFactors = FALSE)
  }
  if (!"n_alive" %in% names(flow_base)) flow_base$n_alive <- NA_integer_
  if (!"n_dead" %in% names(flow_base)) flow_base$n_dead <- NA_integer_
  flow_extra <- data.frame(
    stage = c(
      sprintf("exclude_patient_missing_gt%d%%_day1_%d", miss_pct_fc, patient_miss_days),
      "final_analysis_cohort_n_out"
    ),
    n = c(n_final_fc, n_final_fc),
    n_alive = c(NA_integer_, n_alive_fc),
    n_dead = c(NA_integer_, n_death_fc),
    stringsAsFactors = FALSE
  )
  flow_full <- rbind(flow_base[, c("stage", "n", "n_alive", "n_dead"), drop = FALSE], flow_extra)
  ctx$results$tst_cohort$flowchart <- flow_full
  ctx$results$tst_cohort$n_out <- n_final_fc
  ctx$results$tst_cohort$n_death <- n_death_fc
  ctx$results$tst_cohort$n_alive <- n_alive_fc
  ctx <- save_result(ctx, "tst_cohort_flowchart", flow_full, "_tst_cohort_flowchart.csv")
  out_root_fc <- as.character(config$project$output_dir %||% "")[1L]
  if (nzchar(out_root_fc)) {
    cohort_fc <- file.path(out_root_fc, "_shared", "step03_tst_cohort", "Tables", "_tst_cohort_flowchart.csv")
    dir.create(dirname(cohort_fc), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(flow_full, cohort_fc, row.names = FALSE)
  }
  cli::cli_alert_info(
    "tst_timeseries: Figure1 flowchart 终点 n={n_final_fc}（存活={n_alive_fc}，院内死亡={n_death_fc}）"
  )

  ctx
}

register_block(
  "tst_timeseries", block_tst_timeseries,
  "两阶段 Transformer 卒中：day-level 长表整理 + 特征覆盖率审计 + Python 可读导出"
)
