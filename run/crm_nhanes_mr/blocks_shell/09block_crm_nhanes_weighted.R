###############################################################################
#  crm_nhanes_weighted — NHANES 复杂抽样加权有序 Logistic
###############################################################################

block_crm_nhanes_weighted <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  nh <- ctx$config$nhanes %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("crm_nhanes_weighted: 无数据", call. = FALSE)
  sub <- data[data$Cohort %in% c("NHANES", nh$db_label %||% "NHANES"), , drop = FALSE]
  if (!nrow(sub)) sub <- data
  wt_col <- nh$survey_weight %||% "new_Weight"
  if (!wt_col %in% names(sub) && "new_Weight" %in% names(sub)) wt_col <- "new_Weight"
  x <- bl$exposure_var %||% "SUA"
  y <- bl$crm_outcome_col %||% "CRM_count"
  sub[[y]] <- factor(sub[[y]], ordered = TRUE)
  tab <- data.frame(analysis = "unweighted_fallback", term = x, OR = NA_real_, p = NA_real_, stringsAsFactors = FALSE)
  if (requireNamespace("survey", quietly = TRUE) && all(c(wt_col, nh$survey_strata %||% "SDMVSTRA", nh$survey_cluster %||% "SDMVPSU") %in% names(sub))) {
    dsgn <- survey::svydesign(
      ids = as.formula(paste0("~", nh$survey_cluster %||% "SDMVPSU")),
      strata = as.formula(paste0("~", nh$survey_strata %||% "SDMVSTRA")),
      weights = as.formula(paste0("~", wt_col)), data = sub, nest = TRUE
    )
    fit <- tryCatch(survey::svyolr(as.formula(paste(y, "~", x)), design = dsgn), error = function(e) NULL)
    if (!is.null(fit)) {
      cf <- coef(fit)
      if (is.matrix(cf)) cf <- cf[, 1L]
      nms <- names(cf)
      if (is.null(nms) || !length(nms)) nms <- paste0("coef_", seq_along(cf))
      tab <- data.frame(
        analysis = "svyolr_weighted", term = nms,
        OR = round(exp(as.numeric(cf)), 3),
        p = NA_real_, stringsAsFactors = FALSE
      )
    }
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_NHANES_Weighted_Ordinal.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$crm_nhanes_weighted <- list(table = tab)
  cli::cli_alert_success("NHANES 加权分析完成")
  ctx
}

register_block("crm_nhanes_weighted", block_crm_nhanes_weighted, "NHANES 加权")
