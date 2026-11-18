###############################################################################
#  multimorbidity_gee_interaction — 抑郁×肥胖交互 + 时间交互 GEE
###############################################################################

block_multimorbidity_gee_interaction <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_interaction: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  dep <- as.character(mm$depression_col %||% mm$depression_binary_col %||% "Depression")[1L]
  ob <- as.character(mm$obesity_col %||% mm$obesity_binary_col %||% "Obesity")[1L]
  out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
  time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  fam <- if (identical(bl$family %||% "gaussian", "binomial")) stats::binomial() else stats::gaussian()

  for (v in c(dep, ob, out_col, time_col, id_col)) {
    if (!v %in% names(data)) stop("multimorbidity_gee_interaction: 缺列 ", v, call. = FALSE)
  }
  data[[dep]] <- as.integer(as.numeric(data[[dep]]) >= 1)
  data[[ob]] <- as.integer(as.numeric(data[[ob]]) >= 1)
  data$Dep_x_Ob <- data[[dep]] * data[[ob]]
  form <- stats::as.formula(paste(
    out_col, "~", dep, "+", ob, "+ Dep_x_Ob +", time_col, "+", dep, ":", time_col
  ))
  fit <- geepack::geeglm(form, data = data, id = data[[id_col]], family = fam, corstr = "exchangeable")
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
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Interaction.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee_interaction <- list(table = tab)
  cli::cli_alert_success("交互 GEE 完成")
  ctx
}

register_block(
  "multimorbidity_gee_interaction",
  block_multimorbidity_gee_interaction,
  "交互项 GEE"
)
