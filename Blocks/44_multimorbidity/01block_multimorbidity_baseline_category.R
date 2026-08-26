###############################################################################
#  multimorbidity_baseline_category — 抑郁×腹型肥胖四分类基线状态
#
#  register_block: "multimorbidity_baseline_category"
#  对齐文献: Wang 2025 BMC Med 04298 — Neither / Depression alone / Obesity alone / Comorbidity
###############################################################################

block_multimorbidity_baseline_category <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_baseline_category: 无数据", call. = FALSE)

  dep_col <- bl$depression_col %||% "Depression"
  ob_col  <- bl$obesity_col %||% "Abdominal_obesity"
  if (!dep_col %in% names(data)) stop("缺抑郁列: ", dep_col, call. = FALSE)
  if (!ob_col %in% names(data)) stop("缺肥胖列: ", ob_col, call. = FALSE)

  dep <- as.integer(as.character(data[[dep_col]]) %in% c("1", "Yes", "Case") | as.numeric(data[[dep_col]]) >= 1)
  ob  <- as.integer(as.character(data[[ob_col]]) %in% c("1", "Yes", "Case") | as.numeric(data[[ob_col]]) >= 1)
  cat_var <- bl$category_col %||% "Multimorbidity_cat"
  data[[cat_var]] <- factor(
    ifelse(dep == 0 & ob == 0, "Neither",
           ifelse(dep == 1 & ob == 0, "Depression_alone",
                  ifelse(dep == 0 & ob == 1, "Obesity_alone", "Comorbidity"))),
    levels = c("Neither", "Depression_alone", "Obesity_alone", "Comorbidity")
  )

  ctx$data$cleaned <- data
  ctx$data$imputed <- data
  ctx$results$multimorbidity_baseline <- list(
    category_col = cat_var,
    table = as.data.frame(table(data[[cat_var]]))
  )

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Multimorbidity_Baseline.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(ctx$results$multimorbidity_baseline$table, out, row.names = FALSE)
  cli::cli_alert_success("多病叠加四分类完成")
  ctx
}

register_block(
  "multimorbidity_baseline_category",
  block_multimorbidity_baseline_category,
  "抑郁×腹型肥胖四分类"
)
