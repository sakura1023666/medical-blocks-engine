###############################################################################
#  medication_composite_risk — TEXT/SOFT 复合复发风险 Cox 评分
#  文献: Pagani 2020 J Clin Oncol — STEPP 辅助内分泌治疗
###############################################################################

block_medication_composite_risk <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  time_var  <- bl$time_var %||% (ctx$config$survival$time_var %||% "futime")
  event_var <- bl$event_var %||% (ctx$config$survival$event_var %||% "distant_recurrence")
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_composite_risk: 无数据", call. = FALSE)
  if (!time_var %in% names(data) && !is.null(ctx$data$cleaned))
    data[[time_var]] <- ctx$data$cleaned[[time_var]]
  if (!event_var %in% names(data) && !is.null(ctx$data$cleaned))
    data[[event_var]] <- ctx$data$cleaned[[event_var]]

  covars <- bl$composite_covars %||% c(
    "Age", "Nodal_status", "Tumor_size", "Grade",
    "ER_pct", "PR_pct", "Ki67"
  )
  covars <- intersect(covars, names(data))
  if (length(covars) < 2L) stop("medication_composite_risk: 协变量不足", call. = FALSE)

  if (!all(c(time_var, event_var) %in% names(data)))
    stop("medication_composite_risk: 缺少时间/事件列", call. = FALSE)

  d <- data
  d$.event01 <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  d$.time    <- suppressWarnings(as.numeric(d[[time_var]]))
  d <- d[is.finite(d$.time) & d$.time > 0, , drop = FALSE]
  if (!nrow(d)) stop("medication_composite_risk: 无有效随访", call. = FALSE)

  fml <- stats::as.formula(paste("survival::Surv(.time, .event01) ~", paste(covars, collapse = " + ")))
  fit <- tryCatch(survival::coxph(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) stop("medication_composite_risk: Cox 拟合失败", call. = FALSE)

  lp <- as.numeric(stats::predict(fit, type = "lp"))
  data$composite_risk <- lp
  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$medication_composite_risk <- list(
    n = nrow(d), covars = covars, median_risk = stats::median(lp, na.rm = TRUE)
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  coef_df <- as.data.frame(summary(fit)$coefficients)
  coef_df$term <- rownames(coef_df)
  utils::write.csv(coef_df, file.path(out_dir, "Table_Medication_CompositeRisk_Cox.csv"), row.names = FALSE)
  cli::cli_alert_success("复合复发风险 Cox 评分完成 (n={nrow(d)})")
  ctx
}

register_block("medication_composite_risk", block_medication_composite_risk, "TEXT/SOFT 复合复发风险 Cox")
