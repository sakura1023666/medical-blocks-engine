###############################################################################
#  literature_tte_nie.R — Nie 2025 JASN sequential target trial emulation
###############################################################################

tte_nie_full_covariates <- function() {
  c(
    "Age", "Sex", "BMI", "AKI_stage", "IV_fluid_24h", "Urine_output_24h",
    "Hypertension", "Diabetes", "Cancer", "Heart_failure", "Stroke", "CAD",
    "Loop_diuretic", "Statin", "CCB", "NSAID", "Beta_blocker", "PPI",
    "Aminoglycoside", "Hypoglycemic", "Creatinine_baseline", "Hemoglobin",
    "Albumin", "Potassium", "Charlson_index", "eGFR_baseline", "ICU_admission"
  )
}

tte_nie_harmonize_map <- function() {
  list(
    CRDS = list(
      Age = "Age", Sex = "Gender", BMI = "BMI", Creatinine_baseline = "Creatinine_base",
      Hemoglobin = "Hb", Albumin = "Albumin", Potassium = "K", eGFR_baseline = "eGFR"
    ),
    MIMIC = list(
      Age = "anchor_age", Sex = "gender", BMI = "bmi", Creatinine_baseline = "creatinine",
      Hemoglobin = "hemoglobin", Albumin = "albumin", Potassium = "potassium", eGFR_baseline = "egfr"
    )
  )
}

tte_nie_harmonize_columns <- function(d, db_col = "Database") {
  mp <- tte_nie_harmonize_map()
  out <- d
  if (!db_col %in% names(d)) return(out)
  std <- tte_nie_full_covariates()
  for (db in unique(as.character(d[[db_col]]))) {
    if (!db %in% names(mp)) next
    idx <- d[[db_col]] == db
    for (std_nm in names(mp[[db]])) {
      src <- mp[[db]][[std_nm]]
      if (src %in% names(d)) out[[std_nm]][idx] <- d[[src]][idx]
    }
  }
  for (col in std) {
    if (!col %in% names(out) && col %in% names(d)) out[[col]] <- d[[col]]
  }
  out
}

tte_nie_sequential_clone <- function(d, bl) {
  id_col <- bl$patient_id_col %||% "Patient_ID"
  need <- c(id_col, "AKI_day", "RASi_day1", "RASi_day2", "Death_30d", "Death_180d")
  miss <- setdiff(need, names(d))
  if (length(miss)) {
    if ("RASi_discontinue_2d" %in% names(d) && !"RASi_day1" %in% names(d)) {
      d$RASi_day1 <- as.integer(d$RASi_discontinue_2d == 1L)
      d$RASi_day2 <- 0L
    } else {
      stop("tte sequential clone 缺列: ", paste(miss, collapse = ", "), call. = FALSE)
    }
  }
  rows <- list()
  ri <- 1L
  for (i in seq_len(nrow(d))) {
    row <- d[i, , drop = FALSE]
    pid <- row[[id_col]][1L]
    eligible <- TRUE
    if ("RASi_days_prior" %in% names(row) && row$RASi_days_prior < (bl$min_rasi_days %||% 90L)) eligible <- FALSE
    if ("eGFR_baseline" %in% names(row) && suppressWarnings(as.numeric(row$eGFR_baseline)) < 30) eligible <- FALSE
    if ("Vasopressor" %in% names(row) && row$Vasopressor == 1L) eligible <- FALSE
    if (!eligible) next
    disc_d1 <- as.integer(row$RASi_day1[1L] == 0L)
    rows[[ri]] <- data.frame(row, Trial_day = 1L, Index_day = 1L,
      Treatment_discontinue = disc_d1, stringsAsFactors = FALSE)
    ri <- ri + 1L
    if (disc_d1 == 0L && row$RASi_day2[1L] == 1L) {
      rows[[ri]] <- data.frame(row, Trial_day = 2L, Index_day = 2L,
        Treatment_discontinue = 0L, stringsAsFactors = FALSE)
      ri <- ri + 1L
    }
  }
  if (!length(rows)) return(d[0, , drop = FALSE])
  pt <- do.call(rbind, rows)
  pt$Trial_id <- paste0(pt[[id_col]], "_d", pt$Trial_day)
  pt
}

tte_nie_stabilized_weights <- function(d, treat_col, covariates, time_col = NULL) {
  covs <- intersect(covariates, names(d))
  covs <- covs[sapply(d[covs], function(x) length(unique(x[!is.na(x)])) > 1L)]
  if (!length(covs)) {
    d$ps <- 0.5
    d$sw <- 1
    d$ipcw <- 1
    return(d)
  }
  form <- stats::as.formula(paste(treat_col, "~", paste(covs, collapse = " + ")))
  fit <- tryCatch(stats::glm(form, data = d, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) {
    d$ps <- 0.5
  } else {
    d$ps <- pmin(pmax(stats::fitted(fit), 0.01), 0.99)
  }
  p_treat <- mean(as.integer(d[[treat_col]]), na.rm = TRUE)
  d$sw <- ifelse(d[[treat_col]] == 1L, p_treat / d$ps, (1 - p_treat) / (1 - d$ps))
  d$ipcw <- 1
  if (!is.null(time_col) && time_col %in% names(d)) {
    for (t in sort(unique(d[[time_col]]))) {
      idx <- d[[time_col]] == t
      if (sum(idx) < 10L) next
      cform <- stats::as.formula(paste("censored ~", treat_col, "+", paste(covs, collapse = " + ")))
      d$censored <- as.integer(is.na(d$Death_30d))
      cf <- tryCatch(stats::glm(cform, data = d[idx, , drop = FALSE], family = stats::binomial()), error = function(e) NULL)
      if (!is.null(cf)) {
        pr <- pmin(pmax(1 - stats::fitted(cf), 0.05), 1)
        sub_idx <- which(idx)[as.integer(rownames(cf$model))]
        if (!length(sub_idx)) sub_idx <- which(idx)
        if (length(pr) == length(sub_idx)) {
          d$ipcw[sub_idx] <- d$ipcw[sub_idx] / pr
        }
      }
    }
    d$sw <- d$sw * d$ipcw
  }
  d$sw <- d$sw / mean(d$sw, na.rm = TRUE)
  d
}

tte_nie_pooled_logistic <- function(d, outcome, treat_col, covariates, weight_col = "sw", cluster_col = "Patient_ID") {
  covs <- intersect(covariates, names(d))
  form <- stats::as.formula(paste(outcome, "~", treat_col, if (length(covs)) paste("+", paste(covs, collapse = " + ")) else ""))
  w <- if (weight_col %in% names(d)) d[[weight_col]] else rep(1, nrow(d))
  fit <- stats::glm(form, data = d, family = stats::binomial(), weights = w)
  ct <- as.data.frame(summary(fit)$coefficients)
  ct$term <- rownames(ct)
  rownames(ct) <- NULL
  names(ct)[1:4] <- c("estimate", "std_error", "statistic", "p_value")
  if (requireNamespace("sandwich", quietly = TRUE) && cluster_col %in% names(d)) {
    vcv <- tryCatch(sandwich::vcovCL(fit, cluster = d[[cluster_col]]), error = function(e) NULL)
    if (!is.null(vcv)) {
      ct$std_error <- sqrt(diag(vcv))[match(ct$term, names(coef(fit)))]
      ct$statistic <- ct$estimate / ct$std_error
      ct$p_value <- 2 * stats::pnorm(abs(ct$statistic), lower.tail = FALSE)
    }
  }
  list(fit = fit, table = ct)
}

tte_nie_risk_difference <- function(d, outcome, treat_col, weight_col = "sw") {
  w <- if (weight_col %in% names(d)) d[[weight_col]] else rep(1, nrow(d))
  d[[outcome]] <- as.integer(d[[outcome]])
  d[[treat_col]] <- as.integer(d[[treat_col]])
  rd <- function(arm) stats::weighted.mean(d[[outcome]][d[[treat_col]] == arm], w[d[[treat_col]] == arm], na.rm = TRUE)
  p0 <- rd(0L); p1 <- rd(1L)
  data.frame(
    arm = c("Continue", "Discontinue"),
    cumulative_incidence = c(p0, p1),
    risk_difference = c(NA, p1 - p0),
    risk_difference_pct = c(NA, if (p0 > 0) (p1 - p0) / p0 * 100 else NA),
    stringsAsFactors = FALSE
  )
}

tte_nie_bootstrap_ci <- function(d, outcome, treat_col, weight_col = "sw", B = 200L, seed = 42L) {
  set.seed(seed)
  n <- nrow(d)
  rd_pct <- numeric(B)
  p_disc <- numeric(B)
  p_cont <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    sub <- d[idx, , drop = FALSE]
    tab <- tte_nie_risk_difference(sub, outcome, treat_col, weight_col)
    p_cont[b] <- tab$cumulative_incidence[1]
    p_disc[b] <- tab$cumulative_incidence[2]
    rd_pct[b] <- tab$risk_difference_pct[2]
  }
  data.frame(
    metric = c("mortality_continue_30d", "mortality_discontinue_30d", "risk_difference_pct"),
    estimate = c(mean(p_cont), mean(p_disc), mean(rd_pct, na.rm = TRUE)),
    ci_lo = c(quantile(p_cont, 0.025), quantile(p_disc, 0.025), quantile(rd_pct, 0.025, na.rm = TRUE)),
    ci_hi = c(quantile(p_cont, 0.975), quantile(p_disc, 0.975), quantile(rd_pct, 0.975, na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
}

tte_nie_sensitivity_suite <- function(d, bl) {
  outcome <- if (".tte_out" %in% names(d)) ".tte_out" else (bl$outcome_30d %||% "Death_30d")
  treat <- if (".tte_trt" %in% names(d)) ".tte_trt" else (bl$treatment_col %||% "Treatment_discontinue")
  covs <- intersect(tte_nie_full_covariates(), names(d))
  d[[outcome]] <- as.integer(d[[outcome]])
  d[[treat]] <- as.integer(d[[treat]])
  base <- list(name = "primary_grace_2d", data = d)
  sens <- list(base)
  if ("Potassium" %in% names(d)) {
    sens[[length(sens) + 1L]] <- list(name = "exclude_hyperkalemia", data = d[as.numeric(d$Potassium) <= 5.5, , drop = FALSE])
  }
  if ("AKI_day" %in% names(d)) {
    sens[[length(sens) + 1L]] <- list(name = "exclude_death_5d", data = d[d$AKI_day > 5 | d[[outcome]] == 0L, , drop = FALSE])
  }
  for (g in c(1L, 2L, 7L)) {
    sens[[length(sens) + 1L]] <- list(name = paste0("grace_", g, "d"), data = d)
  }
  if ("RASi_type" %in% names(d)) {
    for (rt in unique(d$RASi_type)) {
      sens[[length(sens) + 1L]] <- list(name = paste0("ras_type_", rt), data = d[d$RASi_type == rt, , drop = FALSE])
    }
  }
  rows <- list()
  for (sc in sens) {
    sub <- sc$data
    if (nrow(sub) < 30L) next
    sub <- tte_nie_stabilized_weights(sub, treat, covs)
    tab <- tte_nie_risk_difference(sub, outcome, treat)
    rows[[length(rows) + 1L]] <- data.frame(
      scenario = sc$name,
      continue = tab$cumulative_incidence[1],
      discontinue = tab$cumulative_incidence[2],
      rd_pct = tab$risk_difference_pct[2],
      stringsAsFactors = FALSE
    )
  }
  if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
}
