###############################################################################
#  literature_prepost_chen.R — Chen 2024 Neurology CHARLS piecewise LMM
###############################################################################

prepost_chen_domain_raw_cols <- function() {
  list(
    Episodic_memory = c("Immediate_recall", "Delayed_recall"),
    Visuospatial = "Visuospatial_draw",
    Orientation = c("Orient_year", "Orient_month", "Orient_day", "Orient_weekday", "Orient_season"),
    Attention_calc = c("Serial7_1", "Serial7_2", "Serial7_3", "Serial7_4", "Serial7_5")
  )
}

prepost_chen_zscore_baseline <- function(x, baseline_idx) {
  mu <- mean(x[baseline_idx], na.rm = TRUE)
  sdv <- stats::sd(x[baseline_idx], na.rm = TRUE)
  if (!is.finite(sdv) || sdv < 1e-8) sdv <- 1
  (x - mu) / sdv
}

prepost_chen_build_composite <- function(d, bl) {
  id_col <- bl$id_col %||% "ID"
  wave_col <- bl$wave_col %||% "Wave"
  domains <- prepost_chen_domain_raw_cols()
  base_wave <- min(d[[wave_col]], na.rm = TRUE)
  is_base <- d[[wave_col]] == base_wave
  for (dom in names(domains)) {
    cols <- domains[[dom]]
    cols <- intersect(as.character(cols), names(d))
    if (!length(cols) && dom %in% names(d)) {
      d[[paste0(dom, "_z")]] <- prepost_chen_zscore_baseline(d[[dom]], is_base)
    } else if (length(cols)) {
      raw <- rowMeans(d[, cols, drop = FALSE], na.rm = TRUE)
      d[[paste0(dom, "_z")]] <- prepost_chen_zscore_baseline(raw, is_base)
    }
  }
  zcols <- grep("_z$", names(d), value = TRUE)
  if (length(zcols)) {
    d$Global_cognition_z <- rowMeans(d[, zcols, drop = FALSE], na.rm = TRUE)
    d$Global_cognition_z <- prepost_chen_zscore_baseline(d$Global_cognition_z, is_base)
  } else if ("Global_cognition" %in% names(d)) {
    d$Global_cognition_z <- prepost_chen_zscore_baseline(d$Global_cognition, is_base)
  }
  d
}

prepost_chen_piecewise_vars <- function(d, bl) {
  id_col <- bl$id_col %||% "ID"
  wave_col <- bl$wave_col %||% "Wave"
  time_col <- bl$time_col %||% "Years_from_baseline"
  if (!time_col %in% names(d) && wave_col %in% names(d)) {
    wv <- suppressWarnings(as.numeric(d[[wave_col]]))
    d[[time_col]] <- (wv - min(wv, na.rm = TRUE)) / 2
  }
  onset_col <- bl$onset_wave_col %||% "Diabetes_onset_wave"
  if ("Diabetes_group" %in% names(d)) {
    d$diabetes_grp <- as.integer(d$Diabetes_group)
  } else if (onset_col %in% names(d)) {
    d$diabetes_grp <- as.integer(!is.na(d[[onset_col]]) & d[[onset_col]] > 0)
  } else {
    d$diabetes_grp <- as.integer(d$Diabetes %||% d[[bl$ever_diabetes_col %||% "Ever_diabetes"]] %in% c(1L, "1", TRUE))
  }
  d$years_after_diabetes <- 0
  if (onset_col %in% names(d)) {
    for (uid in unique(d[[id_col]])) {
      idx <- d[[id_col]] == uid
      sub <- d[idx, , drop = FALSE]
      ow <- sub[[onset_col]][1L]
      if (is.na(ow) || ow <= 0 || !d$diabetes_grp[idx][1L]) next
      t_on <- (ow - min(d[[wave_col]], na.rm = TRUE)) / 2
      d$years_after_diabetes[idx] <- pmax(0, sub[[time_col]] - t_on)
    }
  }
  d$diabetes_years <- d$diabetes_grp * d[[time_col]]
  d$diabetes_years_after <- d$diabetes_grp * d$years_after_diabetes
  d
}

prepost_chen_covariates <- function(bl) {
  bl$covariates %||% c(
    "Age", "Sex", "Education", "Marital_status", "Residential_area",
    "Smoking", "Drinking", "IADL_score", "Hypertension", "Hypercholesterol",
    "Lung_disease", "Heart_problem", "Cancer", "Depressive_symptoms"
  )
}

prepost_chen_fit_lmm <- function(d, outcome, bl) {
  id_col <- bl$id_col %||% "ID"
  time_col <- bl$time_col %||% "Years_from_baseline"
  covs <- intersect(prepost_chen_covariates(bl), names(d))
  cov_rhs <- if (length(covs)) paste("+", paste(covs, collapse = " + ")) else ""
  form <- stats::as.formula(paste(
    outcome, "~ diabetes_grp +", time_col, "+ diabetes_years + diabetes_years_after",
    cov_rhs, "+ (1 +", time_col, "+ diabetes_years_after |", id_col, ")"
  ))
  fit <- NULL
  method <- "lm_fallback"
  if (requireNamespace("lme4", quietly = TRUE)) {
    fit <- tryCatch(lme4::lmer(form, data = d, REML = TRUE), error = function(e) NULL)
    if (!is.null(fit)) method <- "lme4_lmer"
  }
  if (is.null(fit)) {
    form2 <- stats::as.formula(paste(
      outcome, "~ diabetes_grp +", time_col, "+ diabetes_years + diabetes_years_after", cov_rhs
    ))
    fit <- stats::lm(form2, data = d)
    method <- "lm_cluster_se"
  }
  ct <- as.data.frame(summary(fit)$coefficients)
  nc <- ncol(ct)
  if (nc >= 4L) names(ct)[1:4] <- c("estimate", "std_error", "statistic", "p_value")
  else if (nc == 3L) names(ct)[1:3] <- c("estimate", "std_error", "statistic")
  ct$term <- rownames(ct)
  rownames(ct) <- NULL
  if (method == "lm_cluster_se" && requireNamespace("sandwich", quietly = TRUE) &&
      requireNamespace("lmtest", quietly = TRUE)) {
    vcv <- tryCatch(sandwich::vcovCL(fit, cluster = d[[id_col]]), error = function(e) NULL)
    if (!is.null(vcv)) {
      ct$std_error <- sqrt(diag(vcv))[match(ct$term, names(coef(fit)))]
      ct$statistic <- ct$estimate / ct$std_error
      ct$p_value <- 2 * stats::pt(abs(ct$statistic), df = fit$df.residual, lower.tail = FALSE)
    }
  }
  ps_idx <- match("diabetes_years_after", ct$term)
  list(fit = fit, table = ct, method = method,
       post_slope = if (!is.na(ps_idx)) as.numeric(ct$estimate[ps_idx]) else NA_real_)
}

prepost_chen_predict_trajectory <- function(d, fit, bl, ref_row = NULL) {
  time_col <- bl$time_col %||% "Years_from_baseline"
  grid <- data.frame(
    Years_from_baseline = rep(seq(0, 7, by = 0.5), each = 3L),
    diabetes_grp = rep(c(0L, 1L, 1L), times = length(seq(0, 7, by = 0.5))),
    stringsAsFactors = FALSE
  )
  grid$years_after_diabetes <- ifelse(grid$diabetes_grp == 1L, pmax(0, grid$Years_from_baseline - 2), 0)
  grid$diabetes_years <- grid$diabetes_grp * grid$Years_from_baseline
  grid$diabetes_years_after <- grid$diabetes_grp * grid$years_after_diabetes
  if (!is.null(ref_row)) {
    for (cv in prepost_chen_covariates(bl)) {
      if (cv %in% names(ref_row)) grid[[cv]] <- ref_row[[cv]][1L]
    }
  }
  grid$predicted <- stats::predict(fit, newdata = grid, allow.new.levels = TRUE)
  grid
}
