###############################################################################
#  bayesian_health_octo_suite — Health Octo 8 指标汇总表 + 外验队列预测
###############################################################################

block_bayesian_health_octo_suite <- function(ctx, ...) {
  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("bayesian_health_octo_suite: 无数据", call. = FALSE)

  octo_metrics <- c(
    "Body_Clock", "Speed_Body_Clock", "Disability_Body_Clock",
    "Body_Age", "Speed_Body_Age", "Disability_Body_Age"
  )
  bsc <- grep("_BSC$", names(data), value = TRUE)
  if (length(bsc) >= 2L) {
    data$BSC_mean <- rowMeans(data[bsc], na.rm = TRUE)
    octo_metrics <- c("BSC_mean", octo_metrics)
  }
  if (length(bsc) >= 1L && "Age" %in% names(data)) {
    fit <- tryCatch(stats::lm(Age ~ BSC_mean, data = data), error = function(e) NULL)
    if (!is.null(fit)) data$BSC_Age <- stats::predict(fit)
    octo_metrics <- c(octo_metrics, "BSC_Age")
  }
  octo_metrics <- unique(intersect(octo_metrics, names(data)))

  cohorts <- bl$validate_cohorts %||% c("InCHIANTI", "NHANES")
  rows <- list()
  for (coh in c(bl$train_cohort %||% "BLSA", cohorts)) {
    if (!"Cohort" %in% names(data)) break
    sub <- data[data$Cohort == coh, , drop = FALSE]
    if (!nrow(sub)) next
    for (m in octo_metrics) {
      rows[[length(rows) + 1L]] <- data.frame(
        cohort = coh, metric = m,
        mean = mean(sub[[m]], na.rm = TRUE),
        sd = stats::sd(sub[[m]], na.rm = TRUE),
        n = nrow(sub),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    for (m in octo_metrics) {
      rows[[length(rows) + 1L]] <- data.frame(
        cohort = "All", metric = m,
        mean = mean(data[[m]], na.rm = TRUE),
        sd = stats::sd(data[[m]], na.rm = TRUE),
        n = nrow(data),
        stringsAsFactors = FALSE
      )
    }
  }
  tab <- do.call(rbind, rows)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Health_Octo_Suite_By_Cohort.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$bayesian_health_octo_suite <- tab
  cli::cli_alert_success("Health Octo 8 指标套件完成（{length(octo_metrics)} 指标）")
  ctx
}

register_block("bayesian_health_octo_suite", block_bayesian_health_octo_suite, "Health Octo 8 指标")
