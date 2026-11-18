###############################################################################
#  multimorbidity_baseline_category — 抑郁×肥胖四分类基线状态
#
#  register_block: "multimorbidity_baseline_category"
#  对齐文献: Wang 2025 BMC Med — Neither / Depression_alone / Obesity_alone / Comorbidity
###############################################################################

block_multimorbidity_baseline_category <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_baseline_category: 无数据", call. = FALSE)

  dep_col <- as.character(bl$depression_col %||% bl$depression_binary_col %||% "Depression")[1L]
  ob_col <- as.character(bl$obesity_col %||% bl$obesity_binary_col %||% "Obesity")[1L]
  if (!dep_col %in% names(data)) stop("缺抑郁列: ", dep_col, call. = FALSE)
  if (!ob_col %in% names(data)) stop("缺肥胖列: ", ob_col, call. = FALSE)

  to01 <- function(x) {
    if (is.logical(x)) return(as.integer(x))
    if (is.factor(x)) x <- as.character(x)
    if (is.character(x)) {
      xl <- tolower(trimws(x))
      return(as.integer(xl %in% c("1", "yes", "y", "true", "case", "obese", "depression")))
    }
    x <- suppressWarnings(as.numeric(x))
    as.integer(ifelse(is.na(x), NA_integer_, as.integer(x >= 1)))
  }
  dep <- to01(data[[dep_col]])
  ob <- to01(data[[ob_col]])
  cat_var <- as.character(bl$category_col %||% "Multimorbidity_cat")[1L]
  data[[cat_var]] <- factor(
    ifelse(is.na(dep) | is.na(ob), NA_character_,
           ifelse(dep == 0L & ob == 0L, "Neither",
                  ifelse(dep == 1L & ob == 0L, "Depression_alone",
                         ifelse(dep == 0L & ob == 1L, "Obesity_alone", "Comorbidity")))),
    levels = c("Neither", "Depression_alone", "Obesity_alone", "Comorbidity")
  )

  wave_col <- as.character(bl$wave_col %||% "Followup_wave")[1L]
  base_w <- bl$baseline_wave
  if (!is.null(base_w) && wave_col %in% names(data)) {
    data$.mm_baseline_flag <- as.integer(data[[wave_col]] == base_w)
  }

  tab <- as.data.frame(table(Category = data[[cat_var]], useNA = "no"))
  names(tab) <- c("Category", "N")
  tab$Percent <- round(100 * tab$N / sum(tab$N), 2)

  ctx$data$cleaned <- data
  ctx$data$imputed <- data
  ctx$results$multimorbidity_baseline <- list(
    category_col = cat_var,
    table = tab
  )

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out, "Table_Multimorbidity_Baseline.csv"), row.names = FALSE)
  cli::cli_alert_success(
    "多病四分类完成（Neither={tab$N[tab$Category=='Neither'][1]}; Comorbidity={tab$N[tab$Category=='Comorbidity'][1]}）"
  )
  ctx
}

register_block(
  "multimorbidity_baseline_category",
  block_multimorbidity_baseline_category,
  "抑郁×肥胖四分类"
)
