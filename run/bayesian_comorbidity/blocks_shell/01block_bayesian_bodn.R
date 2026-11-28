###############################################################################
#  bayesian_bodn — Body Organ Disease Number（器官系统受累数）
#  文献: Salimi 2025 Nat Commun — Health Octo Tool / BODN
###############################################################################

block_bayesian_bodn <- function(ctx, ...) {
  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("bayesian_bodn: 无数据", call. = FALSE)

  sys_cols <- bl$system_severity_cols %||% grep("_sev$", names(data), value = TRUE)
  if (!length(sys_cols)) stop("bayesian_bodn: 未找到器官系统严重度列", call. = FALSE)

  sev_mat <- as.data.frame(lapply(data[sys_cols], function(x) as.integer(as.numeric(x) >= 1)))
  data$BODN <- rowSums(sev_mat, na.rm = TRUE)
  data$BODN <- pmin(data$BODN, length(sys_cols))

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  tab <- as.data.frame(table(BODN = data$BODN))
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_BODN_Distribution.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$bayesian_bodn <- list(system_cols = sys_cols, table = tab)
  cli::cli_alert_success("BODN 计算完成（{length(sys_cols)} 个器官系统）")
  ctx
}

register_block("bayesian_bodn", block_bayesian_bodn, "BODN 器官受累数")
