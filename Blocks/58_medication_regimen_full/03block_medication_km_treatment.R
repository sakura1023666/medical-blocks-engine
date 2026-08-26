###############################################################################
#  medication_km_treatment — 无远处复发 KM（按治疗组）
###############################################################################

block_medication_km_treatment <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_km_treatment: 无数据", call. = FALSE)

  time_var  <- bl$time_var %||% (ctx$config$survival$time_var %||% "futime")
  event_var <- bl$event_var %||% (ctx$config$survival$event_var %||% "distant_recurrence")
  trt_var   <- bl$treatment_var %||% "Treatment"

  d <- data
  d$.time <- suppressWarnings(as.numeric(d[[time_var]]))
  d$.evt  <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  d <- d[is.finite(d$.time) & d$.time > 0 & !is.na(d[[trt_var]]), , drop = FALSE]
  if (!nrow(d)) stop("medication_km_treatment: 无有效数据", call. = FALSE)

  rates <- do.call(rbind, lapply(split(d, d[[trt_var]]), function(g) {
    fit1 <- survival::survfit(survival::Surv(.time, .evt) ~ 1, data = g)
    data.frame(
      Treatment = as.character(unique(g[[trt_var]]))[1L],
      n = fit1$n,
      events = fit1$n.event,
      freedom_rate = 1 - fit1$n.event / max(fit1$n, 1L),
      stringsAsFactors = FALSE
    )
  }))

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(rates, file.path(out_dir, "Table_Medication_KM_FreedomDR.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(rates, ggplot2::aes(x = Treatment, y = freedom_rate, fill = Treatment)) +
      ggplot2::geom_col() + ggplot2::theme_minimal() +
      ggplot2::labs(title = "Freedom from Distant Recurrence by Treatment", y = "Freedom rate")
    ggplot2::ggsave(file.path(fig_dir, "Figure_Medication_KM_Treatment.pdf"), p, width = 8, height = 6)
  }

  ctx$results$medication_km_treatment <- list(n = nrow(d), strata = levels(factor(d[[trt_var]])))
  cli::cli_alert_success("治疗组 KM 完成")
  ctx
}

register_block("medication_km_treatment", block_medication_km_treatment, "TEXT/SOFT 治疗组 KM")
