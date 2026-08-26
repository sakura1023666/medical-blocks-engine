###############################################################################
#  network_temp_outcome_assoc — 网络温度与抑郁结局关联
###############################################################################

block_network_temp_outcome_assoc <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  data <- ctx$data$cleaned %||% ctx$data$imputed
  out_dir <- (ctx$results$network_temp_compute %||% list())$output_dir
  if (is.null(data)) stop("network_temp_outcome_assoc: 无数据", call. = FALSE)

  outcome_col <- bl$outcome_col %||% "Depression_dx"
  temp_col <- bl$temp_subject_col %||% "Network_temperature"
  if (!temp_col %in% names(data) && !is.null(out_dir)) {
    subj_path <- file.path(out_dir, "Table_Network_Temperature_Subject.csv")
    if (file.exists(subj_path)) {
      tsub <- utils::read.csv(subj_path, stringsAsFactors = FALSE)
      id_col <- bl$id_col %||% "ID"
      if (id_col %in% names(data) && id_col %in% names(tsub))
        data <- merge(data, tsub[, c(id_col, "network_temperature")], by = id_col, all.x = TRUE)
      names(data)[names(data) == "network_temperature"] <- temp_col
    }
  }

  rows <- list()
  if (temp_col %in% names(data) && outcome_col %in% names(data)) {
    d <- data[!is.na(data[[temp_col]]) & !is.na(data[[outcome_col]]), , drop = FALSE]
    if (nrow(d) >= 20L) {
      d$y <- as.integer(suppressWarnings(as.numeric(d[[outcome_col]])) >= 1L)
      fit <- tryCatch(stats::glm(y ~ get(temp_col), data = d, family = stats::binomial()), error = function(e) NULL)
      if (!is.null(fit)) {
        cf <- summary(fit)$coefficients
        if (temp_col %in% rownames(cf) || paste0("get(", temp_col, ")") %in% rownames(cf)) {
          rn <- rownames(cf)[grepl(temp_col, rownames(cf))][1L]
          rows[[1L]] <- data.frame(
            term = temp_col, OR = exp(cf[rn, 1]), p_value = cf[rn, 4], N = nrow(d),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  assoc_df <- if (length(rows)) do.call(rbind, rows) else data.frame()

  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(assoc_df, file.path(tab_dir, "Table_Network_Temperature_Outcome_Assoc.csv"), row.names = FALSE)

  ctx$results$network_temp_outcome_assoc <- list(n = nrow(assoc_df))
  cli::cli_alert_success("网络温度-结局关联完成")
  ctx
}

register_block("network_temp_outcome_assoc", block_network_temp_outcome_assoc, "网络温度结局关联")
