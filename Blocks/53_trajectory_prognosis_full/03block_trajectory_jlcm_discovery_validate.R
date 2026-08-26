###############################################################################
#  trajectory_jlcm_discovery_validate — eICU 发现 + MIMIC 验证（固定参数迁移）
###############################################################################

block_trajectory_jlcm_discovery_validate <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  dv <- bl$discovery_validate %||% list()
  disc <- dv$discovery_cohort %||% "eICU"
  val <- dv$validation_cohort %||% "MIMIC"
  cohort_col <- bl$cohort_col %||% "Cohort"

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !cohort_col %in% names(data))
    stop("trajectory_jlcm_discovery_validate: 缺少 Cohort", call. = FALSE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  tab <- data.frame(
    stage = c("discovery", "validation"),
    cohort = c(disc, val),
    n = c(sum(data[[cohort_col]] == disc), sum(data[[cohort_col]] == val)),
    role = c("JLCM development (eICU)", "External validation (MIMIC)"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(tab, file.path(out, "Table_Discovery_Validation_Split.csv"), row.names = FALSE)

  ctx$results$trajectory_jlcm_discovery_validate <- tab
  cli::cli_alert_success("发现/验证队列拆分: {disc} → {val}")
  ctx
}

register_block("trajectory_jlcm_discovery_validate", block_trajectory_jlcm_discovery_validate,
               "eICU 发现 MIMIC 验证")
