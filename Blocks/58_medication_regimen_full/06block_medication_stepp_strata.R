###############################################################################
#  medication_stepp_strata — 化疗分层 STEPP 绝对获益曲线
###############################################################################

block_medication_stepp_strata <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/medication_text_soft_utils.R"), local = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_stepp_strata: 无数据", call. = FALSE)

  index_var <- bl$index_var %||% "composite_risk"
  trt <- bl$treatment_var %||% "Treatment"
  chemo <- bl$chemo_var %||% "Chemotherapy"
  trial <- bl$trial_var %||% "Trial"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "distant_recurrence"
  eval_t <- bl$eval_time_months %||% 96L
  stepp_cfg <- bl$stepp_strata %||% list(window = 20L, step = 5L)

  strata <- list(
    list(name = "TEXT_Chemo", filter = quote(Trial == "TEXT" & Chemotherapy == "Yes"),
         ref = "Tamoxifen_OFS", alt = "Exemestane_OFS"),
    list(name = "SOFT_ChemoPremeno", filter = quote(Trial == "SOFT" & Chemotherapy == "Yes"),
         ref = "Tamoxifen", alt = "Exemestane_OFS"),
    list(name = "No_Chemo", filter = quote(Chemotherapy == "No"),
         ref = "Tamoxifen", alt = "Exemestane_OFS")
  )

  all_rows <- list()
  for (st in strata) {
    sub <- tryCatch(data[with(data, eval(st$filter)), , drop = FALSE], error = function(e) data.frame())
    if (nrow(sub) < stepp_cfg$window %||% 20L) next
    sw <- .med_ts_stepp_windows(
      sub, index_var, trt, st$ref, st$alt, time_var, event_var, eval_t,
      window = stepp_cfg$window %||% 20L, step = stepp_cfg$step %||% 5L
    )
    if (nrow(sw)) {
      sw$stratum <- st$name
      all_rows[[length(all_rows) + 1L]] <- sw
    }
  }
  out_df <- if (length(all_rows)) do.call(rbind, all_rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Medication_STEPP_AbsoluteBenefit_byStratum.csv"), row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(out_df)) {
    fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    p <- ggplot2::ggplot(out_df, ggplot2::aes(x = median_risk, y = abs_benefit, color = stratum)) +
      ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 1.5) +
      ggplot2::labs(x = "Composite Risk", y = "8y Absolute Benefit (Freedom DR)",
                    title = "STEPP-style Absolute Benefit by Chemo Stratum") +
      ggplot2::theme_minimal()
    ggplot2::ggsave(file.path(fig_dir, "Figure_Medication_STEPP_AbsBenefit_Strata.pdf"), p, width = 9, height = 5)
  }

  ctx$results$medication_stepp_strata <- list(n = nrow(out_df))
  cli::cli_alert_success("化疗分层 STEPP 绝对获益完成")
  ctx
}

register_block("medication_stepp_strata", block_medication_stepp_strata, "化疗分层 STEPP 绝对获益")
