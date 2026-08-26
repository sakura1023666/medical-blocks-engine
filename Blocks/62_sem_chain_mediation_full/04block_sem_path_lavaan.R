###############################################################################
#  sem_path_lavaan — SEM 路径模型 X→M1→M2→Y（lavaan 或 lm/glm 链式回退）
#  文献: Zhu 2025 J Adv Research
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

.sem_lm_chain <- function(d, x, m1, m2, y, covs) {
  adj <- intersect(covs, names(d))
  adj_rhs <- if (length(adj)) paste("+", paste(adj, collapse = " + ")) else ""
  f1 <- stats::as.formula(paste(m1, "~", x, adj_rhs))
  f2 <- stats::as.formula(paste(m2, "~", x, "+", m1, adj_rhs))
  fit1 <- stats::lm(f1, data = d)
  fit2 <- stats::lm(f2, data = d)
  if (is.numeric(d[[y]])) {
    fit3 <- stats::lm(stats::as.formula(paste(y, "~", x, "+", m1, "+", m2, adj_rhs)), data = d)
    est3 <- coef(fit3)
    se3 <- summary(fit3)$coefficients[, "Std. Error"]
  } else {
    fit3 <- stats::glm(stats::as.formula(paste(y, "~", x, "+", m1, "+", m2, adj_rhs)),
      data = d, family = stats::binomial())
    est3 <- coef(fit3)
    se3 <- summary(fit3)$coefficients[, "Std. Error"]
  }
  rows <- rbind(
    data.frame(lhs = m1, op = "~", rhs = x, est = coef(fit1)[x], se = summary(fit1)$coefficients[x, "Std. Error"]),
    data.frame(lhs = m2, op = "~", rhs = x, est = coef(fit2)[x], se = summary(fit2)$coefficients[x, "Std. Error"]),
    data.frame(lhs = m2, op = "~", rhs = m1, est = coef(fit2)[m1], se = summary(fit2)$coefficients[m1, "Std. Error"]),
    data.frame(lhs = y, op = "~", rhs = x, est = est3[x], se = se3[x]),
    data.frame(lhs = y, op = "~", rhs = m1, est = est3[m1], se = se3[m1]),
    data.frame(lhs = y, op = "~", rhs = m2, est = est3[m2], se = se3[m2])
  )
  fit_idx <- data.frame(
    index = c("method", "n", "r2_m1", "r2_m2"),
    value = c("lm_glm_chain", nrow(d),
      summary(fit1)$r.squared, summary(fit2)$r.squared),
    stringsAsFactors = FALSE
  )
  list(coef = rows, fit = fit_idx, method = "lm_glm_chain")
}

block_sem_path_lavaan <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_path_lavaan: 无数据", call. = FALSE)

  x <- bl$exposure_var %||% "Sarcopenia"
  m1 <- bl$m1_var %||% "Depression"
  m2 <- bl$m2_var %||% "Cognitive_score"
  y <- bl$event_var %||% "Frailty_event"
  covs <- bl$covariate_vars %||% c("Age", "Gender")
  need <- c(x, m1, m2, y)
  if (!all(need %in% names(data))) {
    cli::cli_alert_warning("SEM 路径: 变量缺失，跳过")
    return(ctx)
  }

  d <- data[complete.cases(data[need]), , drop = FALSE]
  if (nrow(d) < 30L) {
    cli::cli_alert_warning("SEM 路径: 样本不足 (n={nrow(d)})")
    return(ctx)
  }

  result <- if (requireNamespace("lavaan", quietly = TRUE)) {
    cov_str <- intersect(covs, names(d))
    cov_part <- if (length(cov_str)) paste0("\n  ", paste(cov_str, "~ 1", collapse = "\n  ")) else ""
    model <- paste0(
      m1, " ~ a*", x, "\n",
      m2, " ~ b*", x, " + c*", m1, "\n",
      y, " ~ d*", x, " + e*", m1, " + f*", m2, cov_part
    )
    fit <- tryCatch(
      lavaan::sem(model, data = d, estimator = bl$sem_estimator %||% "ML", std.lv = FALSE),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      .sem_lm_chain(d, x, m1, m2, y, covs)
    } else {
      pe <- lavaan::parameterEstimates(fit, standardized = TRUE)
      coef_tab <- pe[pe$op == "~", c("lhs", "op", "rhs", "est", "se", "pvalue", "std.all")]
      fm <- lavaan::fitMeasures(fit, c("cfi", "tli", "rmsea", "srmr", "chisq", "df", "pvalue"))
      fit_idx <- data.frame(
        index = c("method", names(fm)),
        value = c(NA_real_, as.numeric(fm)),
        stringsAsFactors = FALSE
      )
      fit_idx$method <- "lavaan"
      list(coef = coef_tab, fit = fit_idx, method = "lavaan", model = fit)
    }
  } else {
    .sem_lm_chain(d, x, m1, m2, y, covs)
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  coef_out <- file.path(out_dir, "Table_SEM_Path_Coefficients.csv")
  fit_out <- file.path(out_dir, "Table_SEM_Fit_Indices.csv")
  utils::write.csv(result$coef, coef_out, row.names = FALSE)
  utils::write.csv(result$fit, fit_out, row.names = FALSE)

  ctx$results$sem_path_lavaan <- list(
    method = result$method, coef = result$coef, fit = result$fit,
    coef_path = coef_out, fit_path = fit_out
  )
  cli::cli_alert_success("SEM 路径模型完成 ({result$method})")
  ctx
}

register_block("sem_path_lavaan", block_sem_path_lavaan, "SEM 路径系数与拟合指数")
