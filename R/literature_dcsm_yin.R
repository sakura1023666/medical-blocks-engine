###############################################################################
#  literature_dcsm_yin.R — Yin 2024 ELSA bivariate dual change score (lavaan)
###############################################################################

dcs_yin_covariates <- function() {
  c("Age", "Sex", "Education", "Wealth", "Limiting_illness", "Self_rated_health",
    "Smoking", "Alcohol", "Physical_activity")
}

dcs_yin_prep <- function(d, bl) {
  id_col <- bl$id_col %||% "ID"
  wave_col <- bl$wave_col %||% "Wave"
  dep <- bl$depression_col %||% "CESD_total"
  mem <- bl$memory_col %||% "Memory_score"
  flu <- bl$fluency_col %||% "Verbal_fluency"
  d <- d[order(d[[id_col]], d[[wave_col]]), , drop = FALSE]
  if (dep %in% names(d)) d$Dep_log <- log1p(pmax(0, as.numeric(d[[dep]])))
  if (!"Time_years" %in% names(d)) {
    wv <- suppressWarnings(as.numeric(d[[wave_col]]))
    d$Time_years <- (wv - min(wv, na.rm = TRUE)) * 2
  }
  d$Time_sq <- d$Time_years^2
  if ("Age" %in% names(d)) d$Age_c <- as.numeric(d$Age) - 65
  d
}

dcs_yin_fit_lavaan <- function(d, bl, domain = "memory") {
  dep <- "Dep_log"
  cog <- if (domain == "fluency") bl$fluency_col %||% "Verbal_fluency" else bl$memory_col %||% "Memory_score"
  covs <- intersect(dcs_yin_covariates(), names(d))
  cov_str <- if (length(covs)) paste0("\n  ", paste(covs, "~ 1", collapse = "\n  ")) else ""
  model <- paste0(
    "# Bivariate dual change score (Yin 2024 approximation)\n",
    dep, " ~ i_dep + s_dep*Time_years + q_dep*Time_sq\n",
    cog, " ~ i_cog + s_cog*Time_years + q_cog*Time_sq\n",
    "i_dep ~~ i_cog\n",
    "s_dep ~~ s_cog\n",
    "s_dep ~ dep_on_cog*s_cog + cog_on_dep*s_dep\n",
    "s_cog ~ mem_on_dep*s_dep + dep_on_mem*s_cog\n",
    "i_cog ~ cross_i*cog_on_i*i_dep\n",
    cov_str
  )
  fit <- NULL
  method <- "lm_chain_fallback"
  pe <- NULL
  if (requireNamespace("lavaan", quietly = TRUE)) {
    fit <- tryCatch(
      lavaan::growth(model, data = d, estimator = "MLR", missing = "fiml"),
      error = function(e) tryCatch(lavaan::sem(model, data = d, estimator = "MLR", missing = "fiml"), error = function(e2) NULL)
    )
    if (!is.null(fit)) {
      method <- "lavaan_growth"
      pe <- lavaan::parameterEstimates(fit, standardized = TRUE)
    }
  }
  if (is.null(pe)) {
    d2 <- d[complete.cases(d[c(dep, cog, "Time_years", "Time_sq")]), , drop = FALSE]
    f1 <- stats::lm(stats::as.formula(paste(dep, "~ Time_years + Time_sq")), data = d2)
    f2 <- stats::lm(stats::as.formula(paste(cog, "~ Time_years + Time_sq +", dep)), data = d2)
    f3 <- stats::lm(stats::as.formula(paste(dep, "~ Time_years + Time_sq +", cog)), data = d2)
    pe <- rbind(
      data.frame(lhs = dep, op = "~", rhs = "Time_years", est = coef(f1)["Time_years"], se = summary(f1)$coefficients["Time_years", 2], pvalue = summary(f1)$coefficients["Time_years", 4]),
      data.frame(lhs = cog, op = "~", rhs = dep, est = coef(f2)[dep], se = summary(f2)$coefficients[dep, 2], pvalue = summary(f2)$coefficients[dep, 4]),
      data.frame(lhs = dep, op = "~", rhs = cog, est = coef(f3)[cog], se = summary(f3)$coefficients[cog, 2], pvalue = summary(f3)$coefficients[cog, 4])
    )
  }
  list(fit = fit, pe = pe, method = method, domain = domain)
}

dcs_yin_extract_targets <- function(pe, domain = "memory") {
  dep_to_mem <- pe$est[pe$lhs == "s_cog" & pe$rhs == "s_dep"]
  mem_to_dep <- pe$est[pe$lhs == "s_dep" & pe$rhs == "s_cog"]
  cross_i <- pe$est[pe$lhs == "i_cog" & pe$rhs == "i_dep"]
  if (!length(dep_to_mem) && "label" %in% names(pe)) {
    dep_to_mem <- pe$est[pe$label == "mem_on_dep"]
    mem_to_dep <- pe$est[pe$label == "cog_on_dep"]
    cross_i <- pe$est[pe$label == "cross_i"]
  }
  cog <- if (domain == "fluency") "Verbal_fluency" else "Memory_score"
  if (!length(dep_to_mem))
    dep_to_mem <- pe$est[pe$lhs == cog & pe$rhs == "Dep_log"]
  if (!length(mem_to_dep))
    mem_to_dep <- pe$est[pe$lhs == "Dep_log" & pe$rhs == cog]
  list(
    dep_to_mem_slope = if (length(dep_to_mem)) dep_to_mem[1] else NA,
    mem_to_dep_slope = if (length(mem_to_dep)) mem_to_dep[1] else NA,
    cross_intercept = if (length(cross_i)) cross_i[1] else NA
  )
}
