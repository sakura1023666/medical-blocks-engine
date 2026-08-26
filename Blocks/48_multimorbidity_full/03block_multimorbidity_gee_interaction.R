###############################################################################
#  multimorbidity_gee_interaction — 抑郁×肥胖交互 + 时间交互 GEE
###############################################################################

block_multimorbidity_gee_interaction <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_interaction: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  dep <- (ctx$config$multimorbidity %||% list())$depression_col %||% "Depression"
  ob <- (ctx$config$multimorbidity %||% list())$obesity_col %||% "Abdominal_obesity"
  cog_col <- bl$cognition_col %||% "Cognition_z"
  time_col <- bl$time_col %||% "Followup_wave"
  id_col <- ctx$config$data$id_column %||% "ID"

  for (v in c(dep, ob, cog_col, time_col, id_col)) {
    if (!v %in% names(data)) stop("multimorbidity_gee_interaction: 缺列 ", v, call. = FALSE)
  }
  data$Dep_x_Ob <- as.integer(data[[dep]]) * as.integer(data[[ob]])
  form <- as.formula(paste(
    cog_col, "~", dep, "+", ob, "+ Dep_x_Ob +", time_col, "+", dep, ":", time_col
  ))
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
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Interaction.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee_interaction <- list(table = tab, model = fit)
  cli::cli_alert_success("交互 GEE 完成")
  ctx
}

register_block(
  "multimorbidity_gee_interaction",
  block_multimorbidity_gee_interaction,
  "交互项 GEE 认知"
)
