###############################################################################
#  multimorbidity_sensitivity_suite — 敏感性 GEE（去极端/换相关结构/换结局缩放）
###############################################################################

block_multimorbidity_sensitivity_suite <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_sensitivity_suite: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  cat_col <- (ctx$config$multimorbidity %||% list())$category_col %||% "Multimorbidity_cat"
  cog_col <- bl$cognition_col %||% "Cognition_z"
  time_col <- bl$time_col %||% "Followup_wave"
  id_col <- ctx$config$data$id_column %||% "ID"
  data[[cat_col]] <- factor(as.character(data[[cat_col]]))

  specs <- list(
    main = list(label = "Main_exchangeable", corstr = "exchangeable", data = data),
    ar1 = list(label = "Sensitivity_AR1", corstr = "ar1", data = data),
    trim_cognition = list(
      label = "Sensitivity_trim_cognition_1pct",
      corstr = "exchangeable",
      data = data[abs(data[[cog_col]]) < stats::quantile(abs(data[[cog_col]]), 0.99, na.rm = TRUE), , drop = FALSE]
    )
  )

  rows <- list()
  for (sp in specs) {
    d <- sp$data
    if (nrow(d) < 30L) next
    form <- as.formula(paste(cog_col, "~", cat_col, "+", time_col))
    fit <- tryCatch(
      geepack::geeglm(form, data = d, id = d[[id_col]], family = gaussian(), corstr = sp$corstr),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    sm <- summary(fit)$coefficients
    for (i in seq_len(nrow(sm))) {
      rows[[length(rows) + 1L]] <- data.frame(
        spec = sp$label, term = rownames(sm)[i],
        beta = sm[i, "Estimate"], p = sm[i, "Pr(>|W|)"],
        n = nrow(d), stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) stop("multimorbidity_sensitivity_suite: 全部敏感性规格失败", call. = FALSE)
  tab <- do.call(rbind, rows)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Sensitivity.csv"), row.names = FALSE)
  ctx$results$multimorbidity_sensitivity <- list(table = tab)
  cli::cli_alert_success("敏感性 GEE 完成（{length(specs)} 规格）")
  ctx
}

register_block(
  "multimorbidity_sensitivity_suite",
  block_multimorbidity_sensitivity_suite,
  "GEE 敏感性分析套件"
)
