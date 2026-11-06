###############################################################################
#  trajectory_creatinine_pct — 肌酐百分比变化公式（文献 LCMM 输入）
#  ([Scr - ref] / ref) * 100
###############################################################################

block_trajectory_creatinine_pct <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_creatinine_pct: 无数据", call. = FALSE)

  prefix <- bl$raw_creatinine_prefix %||% "Cre_"
  time_cols <- grep(paste0("^", prefix), names(data), value = TRUE)
  if (!length(time_cols)) stop("trajectory_creatinine_pct: 未找到肌酐宽列", call. = FALSE)

  ref_col <- bl$baseline_creatinine_col %||% "baseline_creatinine"
  if (!ref_col %in% names(data)) {
    d0 <- paste0(prefix, "0")
    if (d0 %in% names(data)) {
      data[[ref_col]] <- as.numeric(data[[d0]])
    } else {
      data[[ref_col]] <- apply(data[time_cols], 1, function(r) min(as.numeric(r), na.rm = TRUE))
    }
  }
  ref <- pmax(as.numeric(data[[ref_col]]), 0.1)

  for (tc in time_cols) {
    day <- sub(paste0("^", prefix), "", tc)
    pct_name <- paste0("CrePct_", day)
    data[[pct_name]] <- (as.numeric(data[[tc]]) - ref) / ref * 100
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Baseline_Creatinine.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      variable = c(ref_col, "n"),
      value = c(mean(ref, na.rm = TRUE), nrow(data)),
      stringsAsFactors = FALSE
    ),
    out, row.names = FALSE
  )
  ctx$results$trajectory_creatinine_pct <- list(ref_col = ref_col, n_pct_cols = length(time_cols))
  cli::cli_alert_success("肌酐百分比变化列已生成（ref={ref_col}）")
  ctx
}

register_block("trajectory_creatinine_pct", block_trajectory_creatinine_pct, "肌酐百分比变化")
