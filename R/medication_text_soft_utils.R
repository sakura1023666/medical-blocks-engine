###############################################################################
#  medication_text_soft_utils.R — TEXT/SOFT 试验特异性比较工具
###############################################################################

.med_ts_km_freedom <- function(data, time_var, event_var, eval_months = 96) {
  d <- data
  d$.time <- suppressWarnings(as.numeric(d[[time_var]]))
  d$.evt  <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  d <- d[is.finite(d$.time) & d$.time > 0, , drop = FALSE]
  if (!nrow(d)) return(NA_real_)
  fit <- survival::survfit(survival::Surv(.time, .evt) ~ 1, data = d)
  sm <- summary(fit, times = eval_months)
  if (length(sm$surv)) as.numeric(sm$surv[1L]) else NA_real_
}

.med_ts_absolute_benefit <- function(data, trt_var, trt_ref, trt_alt, time_var, event_var, eval_months = 96) {
  ref <- data[as.character(data[[trt_var]]) == trt_ref, , drop = FALSE]
  alt <- data[as.character(data[[trt_var]]) == trt_alt, , drop = FALSE]
  r_ref <- .med_ts_km_freedom(ref, time_var, event_var, eval_months)
  r_alt <- .med_ts_km_freedom(alt, time_var, event_var, eval_months)
  if (!is.finite(r_ref) || !is.finite(r_alt)) return(list(ref = r_ref, alt = r_alt, abs_benefit = NA_real_))
  list(ref = r_ref, alt = r_alt, abs_benefit = r_alt - r_ref, n_ref = nrow(ref), n_alt = nrow(alt))
}

.med_ts_stepp_windows <- function(data, index_var, trt_var, trt_a, trt_b, time_var, event_var,
                                  eval_months = 96, window = 50L, step = 10L) {
  d <- data[as.character(data[[trt_var]]) %in% c(trt_a, trt_b), , drop = FALSE]
  d <- d[order(d[[index_var]]), , drop = FALSE]
  if (nrow(d) < window) return(data.frame())
  rows <- list()
  for (start in seq(1L, nrow(d) - window + 1L, by = step)) {
    sub <- d[start:(start + window - 1L), , drop = FALSE]
    med_risk <- stats::median(sub[[index_var]], na.rm = TRUE)
    for (trt in c(trt_a, trt_b)) {
      g <- sub[as.character(sub[[trt_var]]) == trt, , drop = FALSE]
      if (nrow(g) < 5L) next
      fr <- .med_ts_km_freedom(g, time_var, event_var, eval_months)
      rows[[length(rows) + 1L]] <- data.frame(
        median_risk = med_risk, treatment = trt, freedom_rate = fr, n = nrow(g),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(data.frame())
  wide <- do.call(rbind, rows)
  out <- list()
  for (mr in unique(wide$median_risk)) {
    w <- wide[abs(wide$median_risk - mr) < 1e-8, , drop = FALSE]
    a <- w[w$treatment == trt_a, , drop = FALSE]
    b <- w[w$treatment == trt_b, , drop = FALSE]
    if (nrow(a) && nrow(b)) {
      out[[length(out) + 1L]] <- data.frame(
        median_risk = mr,
        freedom_a = a$freedom_rate[1L], freedom_b = b$freedom_rate[1L],
        abs_benefit = b$freedom_rate[1L] - a$freedom_rate[1L],
        compare = paste(trt_b, "vs", trt_a),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(out)) return(data.frame())
  do.call(rbind, out)
}
