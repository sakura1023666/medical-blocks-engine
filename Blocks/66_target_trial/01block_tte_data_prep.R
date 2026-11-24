###############################################################################
#  tte_data_prep — sequential clone person-trials + 双库列对齐
###############################################################################

block_tte_data_prep <- function(ctx, ...) {
  bl <- ctx$config$target_trial %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_tte_nie.R"), local = FALSE)
  data <- ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
  if (is.null(data)) stop("tte_data_prep: 无数据", call. = FALSE)

  if ("Database" %in% names(data)) {
    data <- tte_nie_harmonize_columns(data, bl$database_col %||% "Database")
  }
  pt <- tte_nie_sequential_clone(data, bl)
  pt$`.tte_out` <- as.integer(pt$Death_30d %||% pt[[bl$outcome_30d %||% "Death_30d"]])
  pt$`.tte_trt` <- as.integer(pt$Treatment_discontinue)
  pt$Patient_ID <- pt$Patient_ID %||% pt$ID
  ctx$data$tte_trials <- pt

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "TTE_person_trials_ready.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(pt, out, row.names = FALSE)
  ctx$results$tte_data_prep <- list(
    n_trials = nrow(pt), n_disc = sum(pt$`.tte_trt` == 1L, na.rm = TRUE),
    n_patients = length(unique(pt$Patient_ID))
  )
  cli::cli_alert_success("Sequential TTE person-trials: {nrow(pt)}")
  ctx
}

register_block("tte_data_prep", block_tte_data_prep, "TTE sequential clone")
