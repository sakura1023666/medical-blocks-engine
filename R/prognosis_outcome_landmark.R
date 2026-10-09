###############################################################################
#  prognosis_outcome_landmark — 预后结局行政截尾（默认 28 天全因死亡）
###############################################################################

#' 将生存事件列规范为 0/1（1=死亡/事件）
#'
#' 禁止对 Survivor/Non-survivor 因子直接 as.integer：
#' 因子水平顺序常为 Survivor=1, Non-survivor=2，会把存活误判成事件。
prognosis_event_to_01 <- function(dead, config = NULL) {
  if (is.null(dead)) return(integer(0))
  surv <- (config %||% list())$survival %||% list()
  proj <- (config %||% list())$project %||% list()
  event_value <- surv$event_value %||% 1
  ana_lbl <- trimws(as.character(proj$analysis_group %||% "Non-survivor")[1L])
  ref_lbl <- trimws(as.character(proj$reference_group %||% "Survivor")[1L])

  if (is.factor(dead) || is.character(dead)) {
    lab <- trimws(as.character(dead))
    # 优先按 analysis_group / 常见死亡标签判定
    death_labs <- unique(c(
      ana_lbl,
      "Non-survivor", "Nonsurvivor", "Dead", "Death", "Died",
      "1", "TRUE", "Yes", "yes"
    ))
    death_labs <- death_labs[nzchar(death_labs)]
    out <- as.integer(lab %in% death_labs)
    # 若 analysis_group 未命中但 reference_group 命中，则非参考=事件
    if (!any(lab %in% death_labs, na.rm = TRUE) && nzchar(ref_lbl) && any(lab == ref_lbl, na.rm = TRUE)) {
      out <- as.integer(lab != ref_lbl & !is.na(lab))
    }
    out[is.na(lab)] <- 0L
    return(out)
  }

  if (is.logical(dead)) {
    return(as.integer(isTRUE(dead) | dead %in% TRUE))
  }

  num <- suppressWarnings(as.numeric(dead))
  # 数值：优先 event_value；否则把 1 当事件
  ev <- suppressWarnings(as.numeric(event_value)[1L])
  if (!is.finite(ev)) ev <- 1
  out <- as.integer(is.finite(num) & num == ev)
  out[is.na(num)] <- 0L
  out
}

prognosis_admin_censor_outcome <- function(t_days, dead, landmark_days = 28L, config = NULL) {
  landmark_days <- as.integer(landmark_days)[1L]
  if (!is.finite(landmark_days) || landmark_days <= 0L) {
    stop("prognosis_admin_censor_outcome: landmark_days 须为正整数", call. = FALSE)
  }
  dead01 <- prognosis_event_to_01(dead, config = config)
  t_days <- as.numeric(t_days)
  fustatus <- as.integer(!is.na(t_days) & dead01 == 1L & t_days <= landmark_days)
  futime <- pmin(t_days, landmark_days)
  data.frame(futime = futime, fustatus = fustatus, stringsAsFactors = FALSE)
}

prognosis_apply_outcome_landmark <- function(df, config) {
  if (is.null(df) || !is.data.frame(df) || !nrow(df)) return(df)
  po <- config$prognosis_outcome %||% list()
  if (isFALSE(po$enable)) return(df)

  study_type <- tolower(trimws(as.character((config$project %||% list())$study_type %||% "")[1L]))
  if (!identical(study_type, "prognosis")) return(df)

  surv <- config$survival %||% list()
  time_var <- as.character(surv$time_var %||% "futime")[1L]
  event_var <- as.character(surv$event_var %||% "fustatus")[1L]
  if (!time_var %in% names(df) || !event_var %in% names(df)) {
    stop(
      "prognosis_apply_outcome_landmark: 缺少 ", time_var, " / ", event_var,
      call. = FALSE
    )
  }

  landmark_days <- as.integer(po$landmark_days %||% 28L)[1L]
  cen <- prognosis_admin_censor_outcome(
    df[[time_var]], df[[event_var]], landmark_days, config = config
  )
  out <- df
  out[[time_var]] <- cen$futime
  out[[event_var]] <- cen$fustatus
  out
}
