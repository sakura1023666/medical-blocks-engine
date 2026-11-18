###############################################################################
#  multimorbidity_define_exposures — BMI/WHtR/WWI + 抑郁二分与连续列
#
#  register_block: "multimorbidity_define_exposures"
#  读: ctx$data$imputed|cleaned ; config$multimorbidity
#  写: 肥胖/抑郁二分列、WHtR/WWI、轨迹用连续列
###############################################################################

.mm_cfg <- function(ctx) ctx$config$multimorbidity %||% list()

.mm_to01 <- function(x, cutoff = 1) {
  if (is.logical(x)) return(as.integer(x))
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    xl <- tolower(trimws(x))
    out <- ifelse(xl %in% c("1", "yes", "y", "true", "case", "obese", "depression"), 1L,
                  ifelse(xl %in% c("0", "no", "n", "false", "control", "normal"), 0L, NA_integer_))
    return(out)
  }
  x <- suppressWarnings(as.numeric(x))
  as.integer(ifelse(is.na(x), NA_integer_, as.integer(x >= cutoff)))
}

block_multimorbidity_define_exposures <- function(ctx, ...) {
  bl <- .mm_cfg(ctx)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("multimorbidity_define_exposures: 无数据", call. = FALSE)
  }

  ind <- toupper(trimws(as.character(bl$obesity_indicator %||% "BMI")[1L]))
  bmi_col <- as.character(bl$bmi_col %||% "BMI")[1L]
  wc_col <- as.character(bl$wc_col %||% "WC")[1L]
  ht_col <- as.character(bl$height_col %||% "Height")[1L]
  wt_col <- as.character(bl$weight_col %||% "Weight")[1L]
  bmi_cut <- suppressWarnings(as.numeric(bl$bmi_cutoff %||% 30)[1L])
  whtr_cut <- suppressWarnings(as.numeric(bl$whtr_cutoff %||% 0.6)[1L])

  if (!bmi_col %in% names(data) && wt_col %in% names(data) && ht_col %in% names(data)) {
    ht_m <- suppressWarnings(as.numeric(data[[ht_col]]))
    # Height in cm if median > 3
    if (is.finite(stats::median(ht_m, na.rm = TRUE)) && stats::median(ht_m, na.rm = TRUE) > 3) {
      ht_m <- ht_m / 100
    }
    data[[bmi_col]] <- suppressWarnings(as.numeric(data[[wt_col]])) / (ht_m^2)
  }

  if (wc_col %in% names(data) && ht_col %in% names(data)) {
    wc <- suppressWarnings(as.numeric(data[[wc_col]]))
    ht <- suppressWarnings(as.numeric(data[[ht_col]]))
    if (is.finite(stats::median(ht, na.rm = TRUE)) && stats::median(ht, na.rm = TRUE) < 3) {
      ht <- ht * 100
    }
    data$WHtR <- wc / ht
  }
  if (wc_col %in% names(data) && wt_col %in% names(data)) {
    wc <- suppressWarnings(as.numeric(data[[wc_col]]))
    wt <- suppressWarnings(as.numeric(data[[wt_col]]))
    data$WWI <- wc / sqrt(pmax(wt, 1e-6))
  }

  ob_bin <- as.character(bl$obesity_binary_col %||% "Obesity")[1L]
  if (identical(ind, "WHTR")) {
    if (!"WHtR" %in% names(data)) stop("obesity_indicator=WHtR 但缺少 WC/Height", call. = FALSE)
    data[[ob_bin]] <- as.integer(data$WHtR >= whtr_cut)
    data[[as.character(bl$exposure_a_col %||% "BMI")[1L]]] <- data$WHtR
  } else if (identical(ind, "WWI")) {
    if (!"WWI" %in% names(data)) stop("obesity_indicator=WWI 但缺少 WC/Weight", call. = FALSE)
    wwi_cut <- suppressWarnings(as.numeric(bl$wwi_cutoff %||% stats::median(data$WWI, na.rm = TRUE))[1L])
    data[[ob_bin]] <- as.integer(data$WWI >= wwi_cut)
    data[[as.character(bl$exposure_a_col %||% "BMI")[1L]]] <- data$WWI
  } else {
    if (!bmi_col %in% names(data)) stop("缺 BMI 列: ", bmi_col, call. = FALSE)
    data[[ob_bin]] <- as.integer(suppressWarnings(as.numeric(data[[bmi_col]])) >= bmi_cut)
    ea <- as.character(bl$exposure_a_col %||% bmi_col)[1L]
    if (!identical(ea, bmi_col)) data[[ea]] <- data[[bmi_col]]
  }

  dep_score <- as.character(bl$depression_score_col %||% "Depression_Score")[1L]
  dep_bin <- as.character(bl$depression_binary_col %||% bl$depression_col %||% "Depression")[1L]
  dep_cut <- suppressWarnings(as.numeric(bl$depression_cutoff %||% 3)[1L])
  if (dep_score %in% names(data)) {
    data[[dep_bin]] <- .mm_to01(data[[dep_score]], cutoff = dep_cut)
    eb <- as.character(bl$exposure_b_col %||% dep_score)[1L]
    if (!identical(eb, dep_score)) data[[eb]] <- suppressWarnings(as.numeric(data[[dep_score]]))
  } else if (dep_bin %in% names(data)) {
    data[[dep_bin]] <- .mm_to01(data[[dep_bin]], cutoff = 1)
  } else {
    stop("缺抑郁列: ", dep_score, " / ", dep_bin, call. = FALSE)
  }

  # 兼容旧键
  bl$obesity_col <- ob_bin
  bl$depression_col <- dep_bin
  ctx$config$multimorbidity <- bl

  ctx$data$cleaned <- data
  ctx$data$imputed <- data
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      obesity_indicator = ind,
      n = nrow(data),
      n_obesity = sum(data[[ob_bin]] == 1L, na.rm = TRUE),
      n_depression = sum(data[[dep_bin]] == 1L, na.rm = TRUE)
    ),
    file.path(out, "Table_Multimorbidity_Exposure_Summary.csv"),
    row.names = FALSE
  )
  cli::cli_alert_success(
    "多病暴露定义完成（indicator={ind}; Obesity={sum(data[[ob_bin]]==1,na.rm=TRUE)}; Depression={sum(data[[dep_bin]]==1,na.rm=TRUE)}）"
  )
  ctx
}

register_block(
  "multimorbidity_define_exposures",
  block_multimorbidity_define_exposures,
  "多病叠加暴露定义（BMI/WHtR/抑郁）"
)
