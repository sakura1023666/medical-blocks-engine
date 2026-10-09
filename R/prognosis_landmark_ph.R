# MIMIC-development PH scanning and frozen landmark application.

.reference_landmark_dep <- function(name) {
  if (!exists(name, mode = "function", inherits = TRUE)) {
    stop("Missing reference-association dependency: ", name, call. = FALSE)
  }
  get(name, mode = "function", inherits = TRUE)
}

.reference_landmark_required <- function(data, columns) {
  missing <- setdiff(columns, names(data))
  if (length(missing)) {
    stop("Missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

.reference_ph_p <- function(zph, term) {
  tab <- zph$table
  rn <- rownames(tab)
  exposure_row <- match(term, rn)
  global_row <- match("GLOBAL", rn)
  c(
    exposure = if (is.na(exposure_row)) NA_real_ else as.numeric(tab[exposure_row, "p"]),
    global = if (is.na(global_row)) NA_real_ else as.numeric(tab[global_row, "p"])
  )
}

.reference_beta_landmark <- function(
  zph, exposure, max_day, tolerance = 0.05, stability_points = 2L
) {
  x <- as.numeric(zph$x)
  y <- zph$y
  if (is.null(dim(y))) y <- matrix(y, ncol = 1L)
  col <- match(exposure, colnames(y))
  if (is.na(col)) {
    stop("cox.zph did not return the exposure residual curve.", call. = FALSE)
  }
  ok <- is.finite(x) & is.finite(y[, col])
  x <- x[ok]
  residual <- y[ok, col]
  if (length(unique(x)) < 4L) {
    stop("Insufficient Schoenfeld times for landmark selection.", call. = FALSE)
  }
  smoother <- stats::smooth.spline(x, residual)
  lower <- max(1L, as.integer(ceiling(min(x))))
  # 候选日上限留出至少 7 天「landmark 后」随访（对齐原文 ~day4 / 28 天窗口）
  upper <- min(as.integer(floor(max(x))), as.integer(floor(max_day)) - 7L)
  if (!is.finite(upper) || upper < 1L) {
    upper <- min(as.integer(floor(max(x))), as.integer(floor(max_day)) - 1L)
  }
  if (!is.finite(lower) || !is.finite(upper) || lower > upper) {
    stop("No valid positive landmark candidate day.", call. = FALSE)
  }
  days <- seq.int(lower, upper)
  beta <- stats::predict(smoother, days)$y
  stability_points <- as.integer(stability_points)[1L]
  tolerance <- as.numeric(tolerance)[1L]
  possible <- which(beta[-length(beta)] * beta[-1L] <= 0)
  stable <- possible[vapply(possible, function(j) {
    left <- seq.int(j - stability_points + 1L, j)
    right <- seq.int(j + 1L, j + stability_points)
    if (min(left) < 1L || max(right) > length(beta)) return(FALSE)
    all(beta[left] <= -tolerance) && all(beta[right] >= tolerance) ||
      all(beta[left] >= tolerance) && all(beta[right] <= -tolerance)
  }, logical(1))]
  if (length(stable)) {
    score <- abs(beta[stable]) + abs(beta[stable + 1L])
    j <- stable[[which.min(score)]]
    day <- days[[if (abs(beta[[j]]) <= abs(beta[[j + 1L]])) j else j + 1L]]
    method <- "stable_zero_crossing"
    approximate <- FALSE
  } else {
    day <- days[[which.min(abs(beta))]]
    method <- "minimum_absolute_beta"
    approximate <- TRUE
  }
  list(
    day = as.numeric(day),
    method = method,
    approximate = approximate,
    curve = data.frame(day = days, beta = beta, stringsAsFactors = FALSE)
  )
}

.reference_ph_formula <- function(time, event, exposure, covariates) {
  bt <- .reference_landmark_dep(".reference_bt")
  stats::as.formula(sprintf(
    "survival::Surv(%s, %s) ~ %s",
    bt(time), bt(event),
    paste(bt(c(exposure, covariates)), collapse = " + ")
  ))
}

#' Scan Overall and every SOFA layer using MIMIC development Cox/cox.zph.
#'
#' `mimic_fits` is a specification list containing data, time, event, exposure,
#' stratum, covariates, outcome_cfg, provenance, and optional max_day.
reference_ph_landmark_lock <- function(mimic_fits, alpha = 0.05) {
  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("Package 'survival' is required.", call. = FALSE)
  }
  if (!is.list(mimic_fits) || is.null(mimic_fits$data)) {
    stop("mimic_fits must contain MIMIC development scan inputs.", call. = FALSE)
  }
  data <- mimic_fits$data
  validate_provenance <- .reference_landmark_dep(
    ".reference_validate_provenance"
  )
  validate_provenance(mimic_fits$provenance, data)
  time <- as.character(mimic_fits$time)[1L]
  event <- as.character(mimic_fits$event)[1L]
  exposure <- as.character(mimic_fits$exposure)[1L]
  stratum <- as.character(mimic_fits$stratum)[1L]
  covariates <- as.character(mimic_fits$covariates)
  covariates <- covariates[nzchar(covariates)]
  max_day_input <- if (is.null(mimic_fits$max_day)) 28 else mimic_fits$max_day
  max_day <- suppressWarnings(as.numeric(as.character(max_day_input))[1L])
  alpha <- suppressWarnings(as.numeric(as.character(alpha))[1L])
  if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop("alpha must be between zero and one.", call. = FALSE)
  }
  if (!is.finite(max_day) || max_day <= 1) {
    stop("max_day must be a valid value > 1.", call. = FALSE)
  }
  needed <- unique(c(time, event, exposure, stratum, covariates))
  .reference_landmark_required(data, needed)
  numeric_safe <- .reference_landmark_dep(".reference_numeric")
  event01 <- .reference_landmark_dep(".reference_event01")
  data[[time]] <- numeric_safe(data[[time]], time, positive = TRUE)
  data[[event]] <- event01(data[[event]], cfg = mimic_fits$outcome_cfg)
  layers <- c("Overall", unique(as.character(data[[stratum]])))
  layers <- layers[!is.na(layers) & nzchar(layers)]
  rows <- vector("list", length(layers))
  beta_curves <- stats::setNames(vector("list", length(layers)), layers)
  fits <- stats::setNames(vector("list", length(layers)), layers)
  for (i in seq_along(layers)) {
    label <- layers[[i]]
    d <- if (identical(label, "Overall")) {
      data[, needed, drop = FALSE]
    } else {
      data[as.character(data[[stratum]]) == label, needed, drop = FALSE]
    }
    d <- d[stats::complete.cases(d), , drop = FALSE]
    estimate <- tryCatch({
      if (nrow(d) < 10L || length(unique(d[[event]])) < 2L ||
          length(unique(d[[exposure]])) < 2L) {
        stop("insufficient rows, events, or exposure variation")
      }
      fit <- survival::coxph(
        .reference_ph_formula(time, event, exposure, covariates),
        data = d, x = TRUE, y = TRUE, model = TRUE
      )
      if (anyNA(stats::coef(fit))) stop("aliased Cox coefficients")
      zph <- survival::cox.zph(fit, transform = "identity")
      p <- .reference_ph_p(zph, exposure)
      if (!is.finite(p[["exposure"]])) stop("exposure PH P is unavailable")
      candidate <- .reference_beta_landmark(zph, exposure, max_day)
      list(fit = fit, zph = zph, p = p, candidate = candidate)
    }, error = identity)
    if (inherits(estimate, "error")) {
      rows[[i]] <- data.frame(
        stratum = label, n = nrow(d), events = sum(d[[event]] == 1L),
        exposure_p = NA_real_, global_p = NA_real_,
        violation_p = NA_real_, landmark_time = NA_real_,
        landmark_method = NA_character_, approximate = NA,
        status = "not_estimable",
        reason = conditionMessage(estimate), stringsAsFactors = FALSE
      )
      beta_curves[label] <- list(NULL)
      fits[label] <- list(NULL)
    } else {
      candidate <- estimate$candidate
      p <- estimate$p
      rows[[i]] <- data.frame(
        stratum = label, n = estimate$fit$n, events = estimate$fit$nevent,
        exposure_p = unname(p[["exposure"]]),
        global_p = unname(p[["global"]]),
        violation_p = unname(p[["exposure"]]),
        landmark_time = candidate$day,
        landmark_method = candidate$method,
        approximate = candidate$approximate,
        status = "estimable", reason = "",
        stringsAsFactors = FALSE
      )
      beta_curves[[label]] <- candidate$curve
      fits[[label]] <- list(cox = estimate$fit, zph = estimate$zph)
    }
  }
  scan <- do.call(rbind, rows)
  if (!any(scan$status == "estimable")) {
    stop("No estimable PH candidate after scanning all layers.", call. = FALSE)
  }
  violating <- which(
    scan$status == "estimable" &
      is.finite(scan$violation_p) &
      scan$violation_p < alpha
  )
  selected_scan <- if (length(violating)) {
    best <- violating[[which.min(scan$violation_p[violating])]]
    scan[best, , drop = FALSE]
  } else {
    scan[FALSE, , drop = FALSE]
  }
  if (anyDuplicated(selected_scan$stratum)) {
    stop("Duplicate stratum in PH lock.", call. = FALSE)
  }
  times <- as.numeric(selected_scan$landmark_time)
  names(times) <- selected_scan$stratum
  if (length(times) && any(!is.finite(times) | times <= 0 | times >= max_day)) {
    stop("Selected landmark times are invalid.", call. = FALSE)
  }
  spec <- list(
    source = "MIMIC development/train",
    development_hash = .reference_landmark_dep(".reference_hash")(data),
    alpha = alpha,
    strata = selected_scan$stratum,
    landmark_times = times,
    time_var = time,
    event_var = event,
    stratum_var = stratum,
    exposure = exposure,
    covariates = covariates,
    max_day = max_day,
    outcome_cfg = mimic_fits$outcome_cfg,
    scan = scan,
    beta_curves = beta_curves,
    fits = fits
  )
  .reference_landmark_dep(".reference_sign_lock")(
    spec, "landmark_lock", "reference_landmark_lock",
    mimic_fits$provenance
  )
}

.reference_landmark_row <- function(row, start, stop, event, segment, landmark) {
  row$start <- as.numeric(start)
  row$stop <- as.numeric(stop)
  row$event <- as.integer(event)
  row$segment <- segment
  row$landmark_time <- as.numeric(landmark)
  row
}

#' Apply a signed MIMIC-development landmark lock without re-estimation.
reference_apply_landmark <- function(data, locked_spec) {
  authority <- .reference_landmark_dep(".reference_validate_lock")(
    locked_spec, "landmark_lock", "reference_landmark_lock"
  )
  provenance <- reference_trusted_development(
    authority$train, checkpoint_path = authority$checkpoint_path
  )
  expected <- reference_ph_landmark_lock(list(
    data = authority$train,
    time = locked_spec$time_var,
    event = locked_spec$event_var,
    exposure = locked_spec$exposure,
    stratum = locked_spec$stratum_var,
    covariates = locked_spec$covariates,
    outcome_cfg = locked_spec$outcome_cfg,
    provenance = provenance,
    max_day = locked_spec$max_day
  ), alpha = locked_spec$alpha)
  if (!identical(locked_spec$strata, expected$strata) ||
      !isTRUE(all.equal(
        locked_spec$landmark_times, expected$landmark_times, tolerance = 0
      ))) {
    stop("Landmark lock contents were tampered with.", call. = FALSE)
  }
  if (anyDuplicated(locked_spec$strata) ||
      anyDuplicated(names(locked_spec$landmark_times))) {
    stop("Duplicate stratum in landmark lock.", call. = FALSE)
  }
  time <- locked_spec$time_var
  event <- locked_spec$event_var
  stratum <- locked_spec$stratum_var
  .reference_landmark_required(data, c(time, event, stratum))
  event_value <- .reference_landmark_dep(".reference_event01")(
    data[[event]], cfg = locked_spec$outcome_cfg
  )
  time_value <- .reference_landmark_dep(".reference_numeric")(
    data[[time]], time, positive = TRUE
  )
  times <- suppressWarnings(as.numeric(as.character(locked_spec$landmark_times)))
  if (length(times) && anyNA(times)) {
    stop("Landmark times contain missing/non-numeric values.", call. = FALSE)
  }
  if (length(times) && any(
    !is.finite(times) | times <= 0 | times >= locked_spec$max_day
  )) {
    stop("Landmark times must be valid positive days below max_day.", call. = FALSE)
  }
  names(times) <- names(locked_spec$landmark_times)
  rows <- list()
  k <- 0L
  for (i in seq_len(nrow(data))) {
    row <- data[i, , drop = FALSE]
    t <- time_value[[i]]
    status <- event_value[[i]]
    layer <- as.character(data[[stratum]][[i]])
    landmark <- if (layer %in% names(times)) {
      unname(times[[layer]])
    } else if ("Overall" %in% names(times)) {
      unname(times[["Overall"]])
    } else {
      NA_real_
    }
    if (is.na(landmark)) {
      k <- k + 1L
      rows[[k]] <- .reference_landmark_row(row, 0, t, status, "all", NA_real_)
    } else if (t <= landmark) {
      k <- k + 1L
      rows[[k]] <- .reference_landmark_row(
        row, 0, t, status, "before", landmark
      )
    } else {
      k <- k + 1L
      rows[[k]] <- .reference_landmark_row(
        row, 0, landmark, 0L, "before", landmark
      )
      k <- k + 1L
      rows[[k]] <- .reference_landmark_row(
        row, landmark, t, status, "after", landmark
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  attr(out, "locked_source") <- locked_spec$source
  attr(out, "locked_spec") <- locked_spec
  out
}
