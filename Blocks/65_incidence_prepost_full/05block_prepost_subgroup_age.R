###############################################################################
#  prepost_subgroup_age — 发病年龄亚组交互
###############################################################################

block_prepost_subgroup_age <- function(ctx, ...) {
  bl <- ctx$config$incidence_prepost %||% list()
  data <- ctx$data$prepost_long %||% ctx$data$cleaned
  cog <- bl$global_cog_col %||% "Global_cognition"
  time_col <- bl$time_col %||% "Years_from_baseline"
  age_col <- bl$age_col %||% "Age"
  if (!age_col %in% names(data)) { ctx$results$prepost_subgroup_age <- list(skipped = TRUE); return(ctx) }
  data$Age_group <- cut(data[[age_col]], breaks = c(44, 54, 64, 74, Inf),
                        labels = c("45-54", "55-64", "65-74", "75+"), right = FALSE)
  rows <- list()
  for (ag in levels(data$Age_group)) {
    sub <- data[data$Age_group == ag, , drop = FALSE]
    if (nrow(sub) < 20L) next
    fit <- tryCatch(stats::lm(stats::as.formula(paste(cog, "~", time_col, "* Post_diabetes")), data = sub), error = function(e) NULL)
    if (is.null(fit)) next
    ct <- summary(fit)$coefficients
    rows[[length(rows) + 1L]] <- data.frame(
      age_group = ag,
      post_slope_change = ct[paste0(time_col, ":Post_diabetes"), 1],
      p_interaction = ct[paste0(time_col, ":Post_diabetes"), 4],
      stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_PrePost_Age_Subgroup.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$prepost_subgroup_age <- list(table = tab)
  cli::cli_alert_success("发病年龄亚组完成")
  ctx
}

register_block("prepost_subgroup_age", block_prepost_subgroup_age, "发病年龄亚组")
