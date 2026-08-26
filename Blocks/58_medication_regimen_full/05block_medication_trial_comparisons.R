###############################################################################
#  medication_trial_comparisons — TEXT/SOFT 试验特异性主比较
#  文献: Pagani 2020 J Clin Oncol
###############################################################################

block_medication_trial_comparisons <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/medication_text_soft_utils.R"), local = FALSE)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_trial_comparisons: 无数据", call. = FALSE)

  trt <- bl$treatment_var %||% "Treatment"
  trial <- bl$trial_var %||% "Trial"
  chemo <- bl$chemo_var %||% "Chemotherapy"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "distant_recurrence"
  eval_t <- bl$eval_time_months %||% 96L

  comparisons <- list(
    list(label = "TEXT_Chemo_ExeOFS_vs_TamOFS", filter = quote(Trial == "TEXT" & Chemotherapy == "Yes"),
         ref = "Tamoxifen_OFS", alt = "Exemestane_OFS"),
    list(label = "SOFT_ChemoPremeno_ExeOFS_vs_Tam", filter = quote(Trial == "SOFT" & Chemotherapy == "Yes"),
         ref = "Tamoxifen", alt = "Exemestane_OFS"),
    list(label = "SOFT_ChemoPremeno_TamOFS_vs_Tam", filter = quote(Trial == "SOFT" & Chemotherapy == "Yes"),
         ref = "Tamoxifen", alt = "Tamoxifen_OFS"),
    list(label = "NoChemo_ExeOFS_vs_Tam", filter = quote(Chemotherapy == "No"),
         ref = "Tamoxifen", alt = "Exemestane_OFS")
  )

  rows <- list()
  for (cmp in comparisons) {
    sub <- tryCatch(data[with(data, eval(cmp$filter)), , drop = FALSE], error = function(e) data.frame())
    if (nrow(sub) < 10L) next
    ab <- .med_ts_absolute_benefit(sub, trt, cmp$ref, cmp$alt, time_var, event_var, eval_t)
    rows[[length(rows) + 1L]] <- data.frame(
      comparison = cmp$label, treatment_ref = cmp$ref, treatment_alt = cmp$alt,
      freedom_ref = ab$ref, freedom_alt = ab$alt, abs_benefit_8y = ab$abs_benefit,
      n_ref = ab$n_ref %||% NA_integer_, n_alt = ab$n_alt %||% NA_integer_,
      stringsAsFactors = FALSE
    )
  }
  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Medication_TEXT_SOFT_Trial_Comparisons.csv"), row.names = FALSE)

  ctx$results$medication_trial_comparisons <- list(n = nrow(out_df), table = out_df)
  cli::cli_alert_success("TEXT/SOFT 试验特异性主比较完成 ({nrow(out_df)} 行)")
  ctx
}

register_block("medication_trial_comparisons", block_medication_trial_comparisons, "TEXT/SOFT 试验主比较")
