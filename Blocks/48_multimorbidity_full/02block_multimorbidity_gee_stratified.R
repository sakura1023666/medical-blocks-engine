###############################################################################
#  multimorbidity_gee_stratified — 按基线分层重复 GEE
###############################################################################

block_multimorbidity_gee_stratified <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_stratified: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  strata <- as.character(bl$stratify_vars %||% c("Gender", "Age_group"))
  if (!"Age_group" %in% names(data) && "Age" %in% names(data)) {
    data$Age_group <- ifelse(data$Age >= 60, "Older", "Younger")
  }
  cat_col <- (ctx$config$multimorbidity %||% list())$category_col %||% "Multimorbidity_cat"
  cog_col <- bl$cognition_col %||% "Cognition_z"
  time_col <- bl$time_col %||% "Followup_wave"
  id_col <- ctx$config$data$id_column %||% "ID"

  all_tabs <- list()
  for (sv in strata) {
    if (!sv %in% names(data)) next
    for (lv in unique(stats::na.omit(data[[sv]]))) {
      sub <- data[data[[sv]] == lv, , drop = FALSE]
      if (nrow(sub) < 30L) next
      sub[[cat_col]] <- factor(as.character(sub[[cat_col]]))
      form <- as.formula(paste(cog_col, "~", cat_col, "+", time_col))
      fit <- tryCatch(
        geepack::geeglm(form, data = sub, id = sub[[id_col]], family = gaussian(), corstr = "exchangeable"),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      sm <- summary(fit)$coefficients
      tab <- data.frame(
        stratum_var = sv, stratum_level = as.character(lv),
        term = rownames(sm), beta = sm[, "Estimate"], p = sm[, "Pr(>|W|)"],
        stringsAsFactors = FALSE
      )
      all_tabs[[paste(sv, lv)]] <- tab
    }
  }
  if (!length(all_tabs)) stop("multimorbidity_gee_stratified: 无有效分层结果", call. = FALSE)
  res <- do.call(rbind, all_tabs)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  utils::write.csv(res, file.path(out_dir, "Table_GEE_Stratified.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee_stratified <- list(table = res)
  cli::cli_alert_success("分层 GEE 完成（{length(all_tabs)} 层）")
  ctx
}

register_block(
  "multimorbidity_gee_stratified",
  block_multimorbidity_gee_stratified,
  "分层 GEE 认知"
)
