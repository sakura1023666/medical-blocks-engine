###############################################################################
# gallstone_rcs_panels — 当前连续特征 RCS(4 knots)（Fig3 单元）
###############################################################################

block_gallstone_rcs_panels <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  expose <- as.character(ctx$config$incidence$index_var %||% "")[1L]
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  if (!nzchar(expose) || is.null(data) || !expose %in% names(data)) return(ctx)

  if (!requireNamespace("rms", quietly = TRUE)) {
    cli::cli_alert_warning("rcs: 未安装 rms，跳过")
    return(ctx)
  }
  d <- data
  y <- d[[outcome]]
  if (is.factor(y)) {
    d$.y <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
  } else d$.y <- as.integer(as.numeric(y) == 1L)
  d$.x <- suppressWarnings(as.numeric(d[[expose]]))
  ok <- is.finite(d$.x) & is.finite(d$.y)
  d <- d[ok, , drop = FALSE]
  models <- gallstone_nomogram_model_sets(
    ctx$config, d, expose = expose,
    uv = gallstone_nomogram_load_uv(ctx)
  )
  cov <- models$Model3
  dd <- rms::datadist(d)
  options(datadist = "dd")
  assign("dd", dd, envir = .GlobalEnv)
  rhs <- paste(c(sprintf("rcs(.x, 4)"), cov), collapse = " + ")
  fml <- stats::as.formula(paste(".y ~", rhs))
  fit <- tryCatch(rms::lrm(fml, data = d, x = TRUE, y = TRUE), error = function(e) NULL)
  dirs <- gallstone_nomogram_out_dirs(ctx, expose)
  gallstone_nomogram_ensure_dirs(dirs)
  pdf(file.path(dirs$figures, sprintf("Figure 3. RCS %s.pdf", expose)), width = 6, height = 5)
  if (!is.null(fit)) {
    pred <- tryCatch(rms::Predict(fit, .x, fun = plogis, ref.zero = TRUE), error = function(e) NULL)
    if (!is.null(pred)) {
      plot(pred, xlab = expose, ylab = "Predicted probability (ref.zero)",
           main = sprintf("RCS (4 knots): %s", expose))
    } else {
      plot.new(); title(sprintf("RCS failed for %s", expose))
    }
    # 非线性近似：比较 rcs vs 线性 AIC
    fit_lin <- tryCatch(stats::glm(stats::as.formula(paste(".y ~ .x +", paste(cov, collapse = "+"))),
                                   data = d, family = binomial()), error = function(e) NULL)
    p_nonlin <- NA_real_
    note <- "p for nonlinearity: see anova(rcs) if available"
    if (!is.null(fit) && requireNamespace("rms", quietly = TRUE)) {
      av <- tryCatch(anova(fit), error = function(e) NULL)
      if (!is.null(av)) {
        utils::write.csv(as.data.frame(av),
                         file.path(dirs$tables, "Table_RCS_anova.csv"), row.names = TRUE)
      }
    }
  } else {
    plot.new(); title(sprintf("RCS fit failed: %s", expose))
  }
  dev.off()
  options(datadist = NULL)
  ctx$results$gallstone_rcs_panels <- list(feature = expose, n = nrow(d))
  cli::cli_alert_success("Fig3 RCS: {expose}")
  ctx
}

register_block("gallstone_rcs_panels", block_gallstone_rcs_panels, "胆结石连续特征RCS")
