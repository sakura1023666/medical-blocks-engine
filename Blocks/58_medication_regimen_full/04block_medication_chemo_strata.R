###############################################################################
#  medication_chemo_strata — 化疗分层绝对获益（TEXT vs SOFT 风格）
###############################################################################

block_medication_chemo_strata <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_chemo_strata: 无数据", call. = FALSE)

  chemo_var <- bl$chemo_var %||% "Chemotherapy"
  trt_var   <- bl$treatment_var %||% "Treatment"
  time_var  <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "distant_recurrence"
  eval_t    <- bl$eval_time_months %||% 96L

  rows <- list()
  for (chemo_lvl in unique(as.character(data[[chemo_var]]))) {
    sub <- data[as.character(data[[chemo_var]]) == chemo_lvl, , drop = FALSE]
    if (nrow(sub) < 20L) next
    sub$.time <- suppressWarnings(as.numeric(sub[[time_var]]))
    sub$.evt  <- as.integer(suppressWarnings(as.numeric(sub[[event_var]])) == 1L)
    for (trt in unique(as.character(sub[[trt_var]]))) {
      g <- sub[as.character(sub[[trt_var]]) == trt, , drop = FALSE]
      if (nrow(g) < 10L) next
      fit <- survival::survfit(survival::Surv(.time, .evt) ~ 1, data = g)
      sm <- summary(fit, times = eval_t)
      rate <- if (length(sm$surv)) as.numeric(sm$surv[1L]) else NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        Chemotherapy = chemo_lvl, Treatment = trt, N = nrow(g),
        Freedom_DR = rate, stringsAsFactors = FALSE
      )
    }
  }
  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Medication_ChemoStrata_AbsoluteBenefit.csv"), row.names = FALSE)

  ctx$results$medication_chemo_strata <- list(n_strata = nrow(out_df))
  cli::cli_alert_success("化疗分层绝对获益表完成")
  ctx
}

register_block("medication_chemo_strata", block_medication_chemo_strata, "TEXT/SOFT 化疗分层获益")
