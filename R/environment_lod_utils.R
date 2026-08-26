###############################################################################
#  environment_lod_utils.R — 官方 LOD 筛查（插补前）
###############################################################################

environment_lod_resolve_paths <- function(cfg, root) {
  lod_cfg <- cfg$environment_lod %||% list()
  root <- root %||% cfg$project$root %||% getwd()
  .resolve <- function(p) {
    if (!nzchar(p)) return(NA_character_)
    if (file.exists(p)) return(normalizePath(p, winslash = "/", mustWork = FALSE))
    p2 <- file.path(root, p)
    if (file.exists(p2)) return(normalizePath(p2, winslash = "/", mustWork = FALSE))
    p3 <- file.path(root, "Data", "nhanes", basename(p))
    if (file.exists(p3)) return(normalizePath(p3, winslash = "/", mustWork = FALSE))
    NA_character_
  }
  list(
    lookup = .resolve(lod_cfg$lookup_csv %||% "D02_OfficialLOD_Lookup_RespiratoryCancer(1).csv"),
    per_cycle = .resolve(lod_cfg$per_cycle_csv %||% "D02_OfficialLOD_PerCycle_RespiratoryCancer(1).csv")
  )
}

environment_lod_normalize_cycle <- function(x) {
  x <- trimws(as.character(x))
  x <- gsub("_", "-", x, fixed = TRUE)
  if (grepl("^\\d{4}-\\d{4}$", x)) return(x)
  if (grepl("^P_", x, ignore.case = TRUE)) {
    yr <- suppressWarnings(as.integer(sub(".*([0-9]{4}).*", "\\1", x)))
    if (!is.na(yr) && yr >= 2017L) return("2017-2018")
    if (!is.na(yr) && yr >= 2015L) return("2015-2016")
  }
  x
}

environment_lod_lookup_values <- function(feature, lookup_df) {
  if (is.null(lookup_df) || !nrow(lookup_df)) return(numeric(0))
  hit <- lookup_df[lookup_df$feature == feature, , drop = FALSE]
  if (!nrow(hit)) return(numeric(0))
  vals <- suppressWarnings(as.numeric(trimws(unlist(strsplit(as.character(hit$official_lod[1L]), ";")))))
  vals[is.finite(vals)]
}

environment_lod_for_row <- function(feature, cycle, lookup_df, per_cycle_df,
                                    cfg = NULL, root = NULL) {
  cycle <- environment_lod_normalize_cycle(cycle)
  if (!is.null(per_cycle_df) && nrow(per_cycle_df) && nzchar(cycle)) {
    hit <- per_cycle_df[
      per_cycle_df$feature == feature & per_cycle_df$cycle == cycle,
      , drop = FALSE
    ]
    if (nrow(hit)) {
      v <- suppressWarnings(as.numeric(hit$official_lod[1L]))
      if (is.finite(v)) return(v)
    }
  }
  vals <- environment_lod_lookup_values(feature, lookup_df)
  if (length(vals)) return(vals[1L])
  if (!is.null(cfg) && exists("environment_lod_legacy_stats_lod", mode = "function")) {
    root <- root %||% (cfg$project %||% list())$root %||% getwd()
    leg <- environment_lod_legacy_stats_lod(feature, cfg, root)
    if (is.finite(leg) && leg > 0) return(leg)
  }
  NA_real_
}

environment_lod_official_display <- function(feature, lookup_df, fill_lod = NA_real_) {
  vals <- environment_lod_lookup_values(feature, lookup_df)
  if (length(vals)) {
    return(paste(round(vals, 4), collapse = "; "))
  }
  if (is.finite(fill_lod) && fill_lod > 0) {
    return(paste(round(fill_lod * sqrt(2), 4), collapse = "; "))
  }
  "\u2014"
}

environment_lod_compute_stats <- function(data, voc_cols, cfg, lookup_df, per_cycle_df) {
  id_col <- cfg$data$id_column %||% "SEQN"
  cycle_col <- (cfg$environment_lod %||% list())$cycle_col %||% "Source_File"
  miss_cut <- as.numeric((cfg$environment_lod %||% list())$missing_cutoff %||% 0.2)
  under_cut <- as.numeric((cfg$environment_lod %||% list())$under_lod_cutoff %||% 0.8)
  root <- (cfg$project %||% list())$root %||% getwd()
  n <- nrow(data)
  rows <- vector("list", length(voc_cols))
  for (i in seq_along(voc_cols)) {
    col <- voc_cols[[i]]
    x <- suppressWarnings(as.numeric(data[[col]]))
    valid <- is.finite(x)
    n_valid <- sum(valid)
    miss_pct <- if (n > 0L) sum(is.na(x)) / n * 100 else 100
    if (n_valid == 0L) {
      rows[[i]] <- data.frame(
        Abbreviation = col, Under_LOD = 100, Missing = miss_pct,
        Abnormal_value = 0, Median_IQR = "—", X_SD = "—",
        LOD_fill = NA_real_, Process = "removed", stringsAsFactors = FALSE
      )
      next
    }
    if (cycle_col %in% names(data)) {
      cycles <- data[[cycle_col]]
      lod_vec <- vapply(seq_len(n), function(r) {
        environment_lod_for_row(col, cycles[[r]], lookup_df, per_cycle_df, cfg, root)
      }, numeric(1))
    } else {
      lod_vec <- rep(
        environment_lod_for_row(col, NA_character_, lookup_df, per_cycle_df, cfg, root),
        n
      )
    }
    lod_use <- lod_vec[is.finite(lod_vec) & valid]
    lod_ref <- if (length(lod_use)) stats::median(lod_use, na.rm = TRUE) else NA_real_
    below <- is.finite(x) & is.finite(lod_vec) & x <= lod_vec
    under_pct <- if (n_valid > 0L) sum(below, na.rm = TRUE) / n_valid * 100 else 100
    mean_val <- mean(x[valid], na.rm = TRUE)
    sd_val <- sd(x[valid], na.rm = TRUE)
    abn <- sum((x > mean_val + 3 * sd_val) | (x < mean_val - 3 * sd_val), na.rm = TRUE)
    proc <- "retained"
    if (miss_pct / 100 > miss_cut || under_pct / 100 > under_cut) proc <- "removed"
    rows[[i]] <- data.frame(
      Abbreviation = col,
      Under_LOD = round(under_pct, 2),
      Missing = round(miss_pct, 2),
      Abnormal_value = round(abn / n_valid * 1000, 2),
      Median_IQR = paste0(round(median(x[valid], na.rm = TRUE), 2), "(",
                          round(IQR(x[valid], na.rm = TRUE), 2), ")"),
      X_SD = paste0(round(mean_val, 4), "\u00b1", round(sd_val, 4)),
      LOD_fill = lod_ref,
      Process = proc,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

#' 样本→列迭代缺失筛查：A = n_VOC × frac；样本 VOC 缺失数 > A 删行；列缺失 > cutoff 删列；直至 VOC ≥ min_vocs
environment_voc_iterative_sample_column_filter <- function(data, voc_cols, cfg) {
  lod_cfg <- cfg$environment_lod %||% list()
  voc_cols <- intersect(as.character(voc_cols), names(data))
  n_voc <- length(voc_cols)
  if (!n_voc || !nrow(data)) {
    return(list(
      data = data, keep = voc_cols, drop = character(0),
      audit = NULL, frac_used = NA_real_, A_used = NA_real_
    ))
  }

  initial_frac <- as.numeric(lod_cfg$sample_miss_frac_initial %||% 0.8)
  frac_step    <- abs(as.numeric(lod_cfg$sample_miss_frac_step %||% 0.05))
  frac_min     <- as.numeric(lod_cfg$sample_miss_frac_min %||% 0.5)
  col_cut      <- as.numeric(lod_cfg$column_missing_cutoff %||% 0.4)
  min_vocs     <- as.integer(lod_cfg$min_retained_vocs %||% 10L)

  fracs <- unique(c(
    seq(initial_frac, frac_min, by = -frac_step),
    frac_min
  ))
  fracs <- fracs[fracs > 0 & fracs <= 1]

  .eval_one <- function(frac) {
    A <- n_voc * frac
    miss_count <- rowSums(is.na(data[, voc_cols, drop = FALSE]))
    keep_row <- miss_count <= A
    d <- data[keep_row, , drop = FALSE]
    if (!nrow(d)) {
      return(list(
        keep_voc = character(0), n_rows_out = 0L, A = A, frac = frac,
        rows_dropped = sum(!keep_row)
      ))
    }
    col_miss <- colMeans(is.na(d[, voc_cols, drop = FALSE]))
    keep_voc <- names(col_miss)[col_miss <= col_cut]
    list(
      keep_voc = keep_voc,
      n_rows_out = nrow(d),
      A = A,
      frac = frac,
      rows_dropped = sum(!keep_row),
      row_keep = keep_row
    )
  }

  best <- NULL
  chosen <- NULL
  for (frac in fracs) {
    res <- .eval_one(frac)
    if (length(res$keep_voc) >= min_vocs) {
      chosen <- res
      break
    }
    if (is.null(best) || length(res$keep_voc) > length(best$keep_voc)) {
      best <- res
    }
  }
  if (is.null(chosen)) chosen <- best
  if (is.null(chosen)) {
    return(list(
      data = data, keep = voc_cols, drop = character(0),
      audit = NULL, frac_used = initial_frac, A_used = n_voc * initial_frac
    ))
  }

  A <- chosen$A
  miss_count <- rowSums(is.na(data[, voc_cols, drop = FALSE]))
  keep_row <- miss_count <= A
  d <- data[keep_row, , drop = FALSE]
  col_miss <- colMeans(is.na(d[, voc_cols, drop = FALSE]))
  keep_voc <- names(col_miss)[col_miss <= col_cut]
  drop_voc <- setdiff(voc_cols, keep_voc)
  non_voc <- setdiff(names(d), voc_cols)
  d <- d[, c(non_voc, keep_voc), drop = FALSE]

  audit <- data.frame(
    step = c("sample_filter", "column_filter", "result"),
    sample_miss_frac = chosen$frac,
    A_threshold = round(A, 4),
    n_voc_start = n_voc,
    n_rows_in = nrow(data),
    n_rows_dropped = sum(!keep_row),
    n_rows_out = nrow(d),
    n_voc_kept = length(keep_voc),
    n_voc_dropped = length(drop_voc),
    column_missing_cutoff_pct = round(col_cut * 100, 1),
    min_retained_vocs = min_vocs,
    stringsAsFactors = FALSE
  )

  list(
    data = d,
    keep = keep_voc,
    drop = drop_voc,
    audit = audit,
    frac_used = chosen$frac,
    A_used = A
  )
}

environment_lod_apply_mask <- function(data, voc_cols, stats_df, cfg) {
  cycle_col <- (cfg$environment_lod %||% list())$cycle_col %||% "Source_File"
  lod_cfg <- cfg$environment_lod %||% list()
  drop_by_stats <- isTRUE(lod_cfg$drop_analytes_by_stats %||% TRUE)
  lookup_df <- attr(stats_df, "lookup_df")
  per_cycle_df <- attr(stats_df, "per_cycle_df")
  root <- (cfg$project %||% list())$root %||% getwd()
  keep <- character(0)
  drop <- character(0)
  for (col in voc_cols) {
    row <- stats_df[stats_df$Abbreviation == col, , drop = FALSE]
    if (!nrow(row) || (drop_by_stats && identical(row$Process[[1L]], "removed"))) {
      if (col %in% names(data)) data[[col]] <- NULL
      drop <- c(drop, col)
      next
    }
    x <- suppressWarnings(as.numeric(data[[col]]))
    if (cycle_col %in% names(data)) {
      lod_vec <- vapply(seq_len(nrow(data)), function(r) {
        environment_lod_for_row(col, data[[cycle_col]][[r]], lookup_df, per_cycle_df, cfg, root)
      }, numeric(1))
    } else {
      lod_vec <- rep(row$LOD_fill[[1L]], nrow(data))
    }
    below <- is.finite(x) & is.finite(lod_vec) & x <= lod_vec
    x[below] <- NA_real_
    data[[col]] <- x
    keep <- c(keep, col)
  }
  list(data = data, keep = keep, drop = drop)
}

environment_lod_write_titled_table <- function(df, title, file, note = NULL, note_height = 200) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    utils::write.csv(df, sub("\\.xlsx$", ".csv", file), row.names = FALSE)
    return(invisible(file))
  }
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", df, startRow = 2L, startCol = 1L)
  openxlsx::writeData(wb, "Sheet1", title, startRow = 1L, startCol = 1L)
  openxlsx::mergeCells(wb, "Sheet1", cols = seq_len(ncol(df)), rows = 1L)
  title_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    border = "bottom", halign = "center", valign = "center"
  )
  header_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "center", valign = "center"
  )
  body_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, halign = "center", valign = "center"
  )
  openxlsx::addStyle(wb, "Sheet1", body_style, rows = 1:(nrow(df) + 1L),
                     cols = seq_len(ncol(df)), gridExpand = TRUE)
  openxlsx::addStyle(wb, "Sheet1", title_style, rows = 1L, cols = seq_len(ncol(df)))
  openxlsx::addStyle(wb, "Sheet1", header_style, rows = 2L, cols = seq_len(ncol(df)))
  if (!is.null(note) && nzchar(note)) {
    note_row <- nrow(df) + 4L
    openxlsx::writeData(wb, "Sheet1", note, startRow = note_row, startCol = 1L)
    openxlsx::mergeCells(wb, "Sheet1", cols = seq_len(ncol(df)), rows = note_row)
    note_style <- openxlsx::createStyle(
      fontName = "Times New Roman", fontSize = 10, halign = "left",
      valign = "top", wrapText = TRUE
    )
    openxlsx::addStyle(wb, "Sheet1", note_style, rows = note_row,
                       cols = seq_len(ncol(df)), gridExpand = TRUE)
    openxlsx::setRowHeights(wb, "Sheet1", rows = note_row, heights = note_height)
  }
  openxlsx::showGridLines(wb, "Sheet1", showGridLines = FALSE)
  openxlsx::setColWidths(wb, "Sheet1", cols = seq_len(ncol(df)), widths = "auto")
  openxlsx::saveWorkbook(wb, file, overwrite = TRUE)
  invisible(file)
}

environment_lod_build_table_s1 <- function(stats_df, env_code, lookup_df, n_kept) {
  # 仅展示可检出环境毒物；n_valid=0 / Process=removed 的不进入 LOD 表
  if ("Process" %in% names(stats_df)) {
    stats_df <- stats_df[stats_df$Process != "removed", , drop = FALSE]
  }
  if (!nrow(stats_df)) {
    return(data.frame(
      Abbreviation = character(0),
      Family = character(0),
      `environment feature` = character(0),
      `Official Instrument LOD` = character(0),
      `Under LOD(%)` = numeric(0),
      `Missing(%)` = numeric(0),
      `Abnormal value(‰)` = numeric(0),
      `Median(IQR)` = character(0),
      `Mean±SD` = character(0),
      Process = character(0),
      check.names = FALSE, stringsAsFactors = FALSE
    ))
  }
  labs <- stats_df$Abbreviation
  if (!is.null(env_code) && nrow(env_code)) {
    id_col <- if ("Labels" %in% names(env_code)) "Labels" else names(env_code)[1L]
    TableS1 <- merge(
      env_code, stats_df, by.x = id_col, by.y = "Abbreviation", all.y = TRUE
    )
    if ("Family" %in% names(TableS1)) {
      TableS1 <- TableS1[order(TableS1$Family, TableS1[[id_col]]), , drop = FALSE]
    }
    exposure_col <- if ("Exposure" %in% names(TableS1)) "Exposure" else id_col
    abbr_col <- id_col
  } else {
    TableS1 <- stats_df
    exposure_col <- "Abbreviation"
    abbr_col <- "Abbreviation"
  }
  lod_official <- vapply(TableS1[[abbr_col]], function(a) {
    environment_lod_official_display(a, lookup_df, TableS1$LOD_fill[TableS1[[abbr_col]] == a][1L])
  }, character(1L))
  proc <- ifelse(TableS1$Process == "retained", "ug_per_l", "removed")
  # env_code 字典缺失的毒物（如 URXUAS 总砷）merge 后 Family/feature 为 NA，
  # 用默认族名与缩写回填，避免最后一行格式空缺
  abbr_vec <- as.character(TableS1[[abbr_col]])
  family_vec <- if ("Family" %in% names(TableS1)) as.character(TableS1$Family) else rep(NA_character_, nrow(TableS1))
  family_vec[is.na(family_vec) | !nzchar(trimws(family_vec))] <- "Environmental Toxicants"
  feature_vec <- as.character(TableS1[[exposure_col]])
  feature_vec[is.na(feature_vec) | !nzchar(trimws(feature_vec))] <-
    abbr_vec[is.na(feature_vec) | !nzchar(trimws(feature_vec))]
  data.frame(
    Abbreviation = abbr_vec,
    Family = family_vec,
    `environment feature` = feature_vec,
    `Official Instrument LOD` = lod_official,
    `Under LOD(%)` = TableS1$Under_LOD,
    `Missing(%)` = TableS1$Missing,
    `Abnormal value(‰)` = TableS1$Abnormal_value,
    `Median(IQR)` = TableS1$Median_IQR,
    `Mean±SD` = TableS1$X_SD,
    Process = proc,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
