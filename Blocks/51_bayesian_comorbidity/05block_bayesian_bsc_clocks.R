###############################################################################
#  bayesian_bsc_clocks — 11 个 BSC + Speed/Disability Clock（后验预测）
###############################################################################

block_bayesian_bsc_clocks <- function(ctx, ...) {
  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("bayesian_bsc_clocks: 无数据", call. = FALSE)

  sys_cols <- bl$system_severity_cols %||% grep("_sev$", names(data), value = TRUE)
  age_col <- bl$age_col %||% "Age"
  bodn <- as.numeric(data$BODN)

  for (sc in sys_cols) {
    bsc_name <- sub("_sev$", "_BSC", sc)
    sev <- as.numeric(data[[sc]])
    data[[bsc_name]] <- bodn * (sev / pmax(1, rowSums(data[sys_cols] >= 1, na.rm = TRUE)))
    data[[bsc_name]][is.na(data[[bsc_name]])] <- sev[is.na(data[[bsc_name]])]
  }

  if ("Body_Clock" %in% names(data)) {
    bc <- data$Body_Clock
    if ("Walk_speed" %in% names(data)) {
      fit_sp <- tryCatch(stats::lm(Walk_speed ~ Body_Clock, data = data), error = function(e) NULL)
      data$Speed_Body_Clock <- if (!is.null(fit_sp)) stats::predict(fit_sp) else data$Walk_speed
    }
    if ("Disability" %in% names(data)) {
      fit_di <- tryCatch(stats::glm(Disability ~ Body_Clock, data = data, family = stats::binomial()),
                         error = function(e) NULL)
      data$Disability_Body_Clock <- if (!is.null(fit_di)) stats::predict(fit_di, type = "response") else data$Disability
    }
    if (age_col %in% names(data)) {
      fit_ba <- tryCatch(stats::lm(stats::as.formula(paste(age_col, "~ Body_Clock")), data = data),
                         error = function(e) NULL)
      data$Body_Age <- if (!is.null(fit_ba)) stats::predict(fit_ba) else data[[age_col]]
      if ("Speed_Body_Clock" %in% names(data)) {
        fit_sa <- tryCatch(stats::lm(stats::as.formula(paste(age_col, "~ Speed_Body_Clock")), data = data),
                           error = function(e) NULL)
        data$Speed_Body_Age <- if (!is.null(fit_sa)) stats::predict(fit_sa) else data[[age_col]]
      }
      if ("Disability_Body_Clock" %in% names(data)) {
        fit_da <- tryCatch(stats::lm(stats::as.formula(paste(age_col, "~ Disability_Body_Clock")), data = data),
                           error = function(e) NULL)
        data$Disability_Body_Age <- if (!is.null(fit_da)) stats::predict(fit_da) else data[[age_col]]
      }
    }
  }

  bsc_cols <- grep("_BSC$", names(data), value = TRUE)
  clock_cols <- c(
    bsc_cols, "Body_Clock", "Speed_Body_Clock", "Disability_Body_Clock",
    "Body_Age", "Speed_Body_Age", "Disability_Body_Age"
  )
  clock_cols <- intersect(clock_cols, names(data))
  summ <- data.frame(
    metric = clock_cols,
    mean = vapply(clock_cols, function(cn) mean(data[[cn]], na.rm = TRUE), numeric(1)),
    sd = vapply(clock_cols, function(cn) stats::sd(data[[cn]], na.rm = TRUE), numeric(1)),
    stringsAsFactors = FALSE
  )

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Health_Octo_8_Metrics.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(summ, out, row.names = FALSE)

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$bayesian_bsc_clocks <- list(n_metrics = nrow(summ), bsc_n = length(bsc_cols))
  cli::cli_alert_success("11 BSC + Body/Speed/Disability Clock 完成（{length(bsc_cols)} BSC）")
  ctx
}

register_block("bayesian_bsc_clocks", block_bayesian_bsc_clocks, "BSC 与 Speed/Disability Clock")
