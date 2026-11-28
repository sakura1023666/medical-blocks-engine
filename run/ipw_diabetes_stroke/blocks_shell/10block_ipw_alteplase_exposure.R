###############################################################################
#  ipw_alteplase_exposure — 阿替普酶暴露（处方∪输液）+ 派生 28 天生存结局
#
#  register_block: "ipw_alteplase_exposure"
#  典型位置: imputation → ipw_alteplase_exposure → analysis_exclusion → …
#  （替换卒中链中的 ipw_diabetes_exposure）
#
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  ipw_alteplase = list(
#    exposure_var = "Alteplase",
#    prefer_precomputed = TRUE,   # Task2 宽表已有 Alteplase=0/1 → 只校验
#    rx_flag_var = "ymtmd",       # prefer_precomputed=FALSE 时：处方列（库特异）
#    iv_flag_var = NULL,          # prefer_precomputed=FALSE 时：输液列（库特异）
#    followup_days = 28L,
#    time_source = "hosp_survival_day",
#    event_source = "death_within_hosp_28days",
#    time_var = "surv_time_28d",
#    event_var = "surv_event_28d",
#    pause_enable = TRUE
#  )
#
#  读: imputed/cleaned；写: Alteplase + surv_*；挂 survival / iptw_balance 暴露字段
#  MAIN 暴露 = prescription OR infusion；rx-only 敏感性由 Task4 config 另开，本块不默认算
###############################################################################

.ipw_alt_as01_flag <- function(x) {
  if (is.null(x)) return(rep(NA_integer_, 0L))
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x) || is.integer(x)) {
    return(as.integer(suppressWarnings(as.numeric(x)) == 1))
  }
  xc <- trimws(as.character(x))
  pos <- c("1", "Yes", "yes", "Y", "TRUE", "True", "true")
  as.integer(xc %in% pos)
}

.ipw_alt_derive_28d <- function(data, bl, cfg) {
  tsrc <- as.character(bl$time_source %||% "hosp_survival_day")[1L]
  esrc <- as.character(bl$event_source %||% "death_within_hosp_28days")[1L]
  tvar <- as.character(bl$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(bl$event_var %||% "surv_event_28d")[1L]
  days <- as.integer(bl$followup_days %||% 28L)[1L]

  need_time <- !(tvar %in% names(data)) || all(is.na(data[[tvar]]))
  need_event <- !(yvar %in% names(data)) || all(is.na(data[[yvar]]))

  if (need_time || need_event) {
    if (!tsrc %in% names(data)) {
      alt <- "hosp_day"
      if (alt %in% names(data)) {
        cli::cli_alert_warning("ipw_alteplase_exposure: 缺少 {tsrc}，回退使用 {alt}")
        tsrc <- alt
      }
    }
    if (!tsrc %in% names(data) || !esrc %in% names(data)) {
      stop(
        "PAUSE_FOR_USER_DECISION: ipw_alteplase_exposure missing survival source ",
        tsrc, "/", esrc, " and precomputed ", tvar, "/", yvar,
        call. = FALSE
      )
    }
    if (need_time) {
      tt <- suppressWarnings(as.numeric(data[[tsrc]]))
      data[[tvar]] <- pmin(tt, days, na.rm = FALSE)
      data[[tvar]][is.na(tt)] <- NA_real_
    }
    if (need_event) {
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
    }
  } else {
    # 已有 precomputed：规范为 numeric / 0-1 integer
    data[[tvar]] <- suppressWarnings(as.numeric(data[[tvar]]))
    if (exists("pipeline_outcome_as_01", mode = "function")) {
      data[[yvar]] <- as.integer(pipeline_outcome_as_01(data[[yvar]], cfg = cfg))
    } else {
      data[[yvar]] <- .ipw_alt_as01_flag(data[[yvar]])
    }
  }

  list(data = data, time_var = tvar, event_var = yvar)
}

block_ipw_alteplase_exposure <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$ipw_alteplase %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("PAUSE_FOR_USER_DECISION: ipw_alteplase_exposure needs imputed/cleaned data", call. = FALSE)
  }

  evar <- as.character(bl$exposure_var %||% "Alteplase")[1L]
  prefer <- isTRUE(bl$prefer_precomputed %||% TRUE)

  if (prefer && evar %in% names(data)) {
    raw <- data[[evar]]
    raw_num <- suppressWarnings(as.numeric(raw))
    allowed_chr <- c("0", "1", "Yes", "No", "yes", "no", "Y", "N", "TRUE", "FALSE", "True", "False")
    illegal <- which(
      !is.na(raw) &
        !(raw_num %in% c(0, 1)) &
        !(trimws(as.character(raw)) %in% allowed_chr)
    )
    if (length(illegal) > 0L) {
      stop(
        "PAUSE_FOR_USER_DECISION: Alteplase must be in {0,1} (prefer_precomputed); ",
        "n_illegal=", length(illegal),
        call. = FALSE
      )
    }
    flag <- .ipw_alt_as01_flag(raw)
    data[[evar]] <- flag
    cli::cli_alert_info(
      "ipw_alteplase_exposure: prefer_precomputed — validated {evar} (n1={sum(flag == 1L, na.rm = TRUE)})"
    )
  } else {
    rxv <- as.character(bl$rx_flag_var %||% "")[1L]
    ivv <- as.character(bl$iv_flag_var %||% "")[1L]
    if (!nzchar(rxv) || !rxv %in% names(data)) {
      stop(
        "PAUSE_FOR_USER_DECISION: Alteplase missing and rx_flag_var unavailable: ",
        rxv, call. = FALSE
      )
    }
    rx <- .ipw_alt_as01_flag(data[[rxv]])
    iv <- if (nzchar(ivv) && ivv %in% names(data)) {
      .ipw_alt_as01_flag(data[[ivv]])
    } else {
      rep(0L, nrow(data))
    }
    # MAIN = prescription OR infusion
    data[[evar]] <- as.integer((!is.na(rx) & rx == 1L) | (!is.na(iv) & iv == 1L))
    cli::cli_alert_info(
      "ipw_alteplase_exposure: built {evar} = rx({rxv}) OR iv({ivv}) (n1={sum(data[[evar]] == 1L, na.rm = TRUE)})"
    )
  }

  der <- .ipw_alt_derive_28d(data, bl, cfg)
  data <- der$data
  tvar <- der$time_var
  yvar <- der$event_var

  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data else ctx$data$cleaned <- data
  ctx$config$survival$time_var  <- tvar
  ctx$config$survival$event_var <- yvar
  # 注意：不要把 survival$index_var 改成暴露列（同 diabetes 块）
  ctx$config$data$outcome_column <- yvar
  ctx$config$iptw_balance$exposure_var <- evar
  ctx$config$iptw_balance$index_var <- evar

  ae <- ctx$config$analysis_exclusion %||% list()
  if (!nzchar(as.character(ae$index_var %||% "")[1L])) {
    unit_guess <- as.character(
      (ctx$config$study_batch %||% list())$active_unit %||%
        (ctx$config$incidence %||% list())$index_var %||% ""
    )[1L]
    if (nzchar(unit_guess)) {
      ctx$config$analysis_exclusion$index_var <- unit_guess
    }
  }

  ctx$results$ipw_alteplase_exposure <- list(
    n = nrow(data),
    n_exposed = sum(data[[evar]] == 1L, na.rm = TRUE),
    n_event = sum(data[[yvar]] == 1L, na.rm = TRUE),
    prefer_precomputed = prefer,
    exposure_var = evar,
    time_var = tvar,
    event_var = yvar
  )
  ctx
}

register_block("ipw_alteplase_exposure", block_ipw_alteplase_exposure,
               "Validate/build Alteplase (rx OR infusion) and 28d survival outcome")
