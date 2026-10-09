###############################################################################
#  ipw_diabetes_exposure — HbA1c≥threshold → Diabetes_HbA1c；派生 28 天生存结局
#
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  ipw_diabetes = list(
#    hba1c_var = "HbA1c",
#    hba1c_threshold = 6.5,
#    exposure_var = "Diabetes_HbA1c",
#    followup_days = 28L,
#    time_source = "hosp_survival_day",
#    event_source = "death_within_hosp_28days",
#    time_var = "surv_time_28d",
#    event_var = "surv_event_28d",
#    pause_enable = TRUE,
#    pause_on_missing_hba1c = TRUE
#  )
###############################################################################

block_ipw_diabetes_exposure <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$ipw_diabetes %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("PAUSE_FOR_USER_DECISION: ipw_diabetes_exposure needs imputed/cleaned data", call. = FALSE)
  }
  hvar <- as.character(bl$hba1c_var %||% "HbA1c")[1L]
  thr  <- as.numeric(bl$hba1c_threshold %||% 6.5)[1L]
  evar <- as.character(bl$exposure_var %||% "Diabetes_HbA1c")[1L]
  if (!hvar %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: missing HbA1c column: ", hvar, call. = FALSE)
  }
  x <- suppressWarnings(as.numeric(data[[hvar]]))
  data[[evar]] <- as.integer(!is.na(x) & x >= thr)

  tsrc <- as.character(bl$time_source %||% "hosp_survival_day")[1L]
  esrc <- as.character(bl$event_source %||% "death_within_hosp_28days")[1L]
  tvar <- as.character(bl$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(bl$event_var %||% "surv_event_28d")[1L]
  days <- as.integer(bl$followup_days %||% 28L)[1L]
  if (!tsrc %in% names(data)) {
    # 回退：部分流水线会因缺失率剔除 hosp_survival_day，改用 hosp_day
    alt <- "hosp_day"
    if (alt %in% names(data)) {
      cli::cli_alert_warning("ipw_diabetes_exposure: 缺少 {tsrc}，回退使用 {alt}")
      tsrc <- alt
    }
  }
  if (!tsrc %in% names(data) || !esrc %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: missing survival source columns ", tsrc, "/", esrc, call. = FALSE)
  }
  tt <- suppressWarnings(as.numeric(data[[tsrc]]))
  data[[tvar]] <- pmin(tt, days, na.rm = FALSE)
  data[[tvar]][is.na(tt)] <- NA_real_
  # 插补后结局常被标成疾病显示名因子；禁止 as.numeric(factor)==1（会把参考组当成事件）
  if (exists("pipeline_outcome_as_01", mode = "function")) {
    data[[yvar]] <- as.integer(pipeline_outcome_as_01(data[[esrc]], cfg = cfg))
  } else {
    y_raw <- data[[esrc]]
    if (is.factor(y_raw) || is.character(y_raw)) {
      yc <- trimws(as.character(y_raw))
      case_labs <- unique(c(
        "1", "Yes", "yes", "TRUE", "True",
        as.character(cfg$project$analysis_group %||% "")[1L],
        as.character(cfg$project$disease %||% "")[1L]
      ))
      case_labs <- case_labs[nzchar(case_labs)]
      data[[yvar]] <- as.integer(yc %in% case_labs)
    } else {
      data[[yvar]] <- as.integer(suppressWarnings(as.numeric(y_raw)) == 1)
    }
  }

  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data else ctx$data$cleaned <- data
  ctx$config$survival$time_var  <- tvar
  ctx$config$survival$event_var <- yvar
  # 注意：不要把 survival$index_var 改成暴露列。
  # analysis_exclusion 会回退到 survival$index_var 解析复合指标组成变量；
  # 暴露固定写在 ipw_diabetes / iptw_balance 上。
  ctx$config$data$outcome_column <- yvar
  ctx$config$iptw_balance$exposure_var <- evar
  ctx$config$iptw_balance$index_var <- evar
  # 若 batch worker 已写入当前复合指标，则保留；否则不要用暴露列冒充
  ae <- ctx$config$analysis_exclusion %||% list()
  if (!nzchar(as.character(ae$index_var %||% "")[1L])) {
    # 兜底：优先 incidence / active_unit，绝不用 Diabetes_HbA1c
    unit_guess <- as.character(
      (ctx$config$study_batch %||% list())$active_unit %||%
        (ctx$config$incidence %||% list())$index_var %||% ""
    )[1L]
    if (nzchar(unit_guess)) {
      ctx$config$analysis_exclusion$index_var <- unit_guess
    }
  }
  ctx$results$ipw_diabetes_exposure <- list(
    n = nrow(data),
    n_diabetes = sum(data[[evar]] == 1L, na.rm = TRUE),
    n_event = sum(data[[yvar]] == 1L, na.rm = TRUE)
  )
  ctx
}

register_block("ipw_diabetes_exposure", block_ipw_diabetes_exposure,
               "Derive Diabetes_HbA1c and 28d survival outcome")
