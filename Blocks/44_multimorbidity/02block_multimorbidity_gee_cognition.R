###############################################################################
#  multimorbidity_gee_cognition — GEE 纵向认知 z 分与多病状态
#
#  register_block: "multimorbidity_gee_cognition"
###############################################################################

block_multimorbidity_gee_cognition <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_cognition: 无数据", call. = FALSE)

  cat_col <- (ctx$config$multimorbidity %||% list())$category_col %||% "Multimorbidity_cat"
  cog_col <- bl$cognition_col %||% "Cognition_z"
  time_col <- bl$time_col %||% "Followup_wave"
  id_col <- ctx$config$data$id_column %||% "ID"

  for (v in c(cat_col, cog_col, time_col, id_col, "Age", "Gender")) {
    if (!v %in% names(data)) stop("multimorbidity_gee_cognition: 缺列 ", v, call. = FALSE)
  }

  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  data[[cat_col]] <- factor(as.character(data[[cat_col]]),
    levels = c("Neither", "Depression_alone", "Obesity_alone", "Comorbidity"))
  if (nlevels(droplevels(data[[cat_col]])) < 2L) {
    cli::cli_alert_warning("GEE: 四分类仅 {nlevels(droplevels(data[[cat_col]]))} 水平，改用二分类 Depression")
    data[[cat_col]] <- factor(ifelse(data$Depression >= 1, "Depressed", "Not_Depressed"))
    form <- as.formula(paste(cog_col, "~", cat_col, "+", time_col, "+ Age"))
  } else {
    form <- as.formula(paste(cog_col, "~", cat_col, "+", time_col, "+ Age"))
  }
  fit <- geepack::geeglm(form, data = data, id = data[[id_col]], family = gaussian(), corstr = "exchangeable")

  sm <- summary(fit)$coefficients
  tab <- data.frame(
    term = rownames(sm),
    beta = round(sm[, "Estimate"], 4),
    se = round(sm[, "Std.err"], 4),
    p = signif(sm[, "Pr(>|W|)"], 4),
    stringsAsFactors = FALSE
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Cognition_Multimorbidity.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee <- list(table = tab, model = fit)
  cli::cli_alert_success("GEE 认知纵向分析完成（n={nrow(data)}）")
  ctx
}

register_block(
  "multimorbidity_gee_cognition",
  block_multimorbidity_gee_cognition,
  "多病叠加 GEE 认知纵向"
)
