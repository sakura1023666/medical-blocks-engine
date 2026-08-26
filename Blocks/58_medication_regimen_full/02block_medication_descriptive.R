###############################################################################
#  medication_descriptive — TEXT/SOFT 治疗组与化疗分层描述表
###############################################################################

block_medication_descriptive <- function(ctx, ...) {
  bl <- ctx$config$medication_regimen %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("medication_descriptive: 无数据", call. = FALSE)

  trt <- bl$treatment_var %||% "Treatment"
  chemo <- bl$chemo_var %||% "Chemotherapy"
  cols <- unique(c(trt, chemo, "Trial", "Age", "composite_risk"))
  cols <- intersect(cols, names(data))

  tab <- as.data.frame(table(data[[trt]], data[[chemo]]))
  names(tab) <- c("Treatment", "Chemotherapy", "N")

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_Medication_Descriptive.csv"), row.names = FALSE)

  if ("composite_risk" %in% names(data)) {
    summ <- stats::aggregate(composite_risk ~ get(trt), data = data, FUN = function(x) c(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE)))
    names(summ)[1] <- trt
    utils::write.csv(summ, file.path(out_dir, "Table_Medication_CompositeRisk_by_Treatment.csv"), row.names = FALSE)
  }

  ctx$results$medication_descriptive <- list(n = nrow(data), cols = cols)
  cli::cli_alert_success("用药方案描述表完成")
  ctx
}

register_block("medication_descriptive", block_medication_descriptive, "TEXT/SOFT 描述统计")
