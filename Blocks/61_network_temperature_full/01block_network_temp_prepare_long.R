###############################################################################
#  network_temp_prepare_long — 纵向抑郁症状宽转长（多波次）
#  文献: Grimes 2025 Nat Mental Health — Network temperature
###############################################################################

block_network_temp_prepare_long <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  data <- ctx$data$cleaned %||% ctx$data$imputed
  if (is.null(data)) stop("network_temp_prepare_long: 无数据", call. = FALSE)

  id_col <- bl$id_col %||% (ctx$config$data$id_column %||% "ID")
  if (!id_col %in% names(data) && !is.null(rownames(data)) && nzchar(rownames(data)[1L])) {
    data[[id_col]] <- rownames(data)
  }
  wave_prefix <- bl$symptom_wave_prefix %||% "DEP_W"
  sym_cols <- grep("^DEP_", names(data), value = TRUE)
  if (!length(sym_cols)) sym_cols <- grep("^(CESD|GAD|dep)", names(data), ignore.case = TRUE, value = TRUE)
  if (length(sym_cols) < 3L) stop("network_temp_prepare_long: 症状列不足", call. = FALSE)

  wave_nums <- unique(as.integer(sub(".*_W([0-9]+)$", "\\1", sym_cols)))
  wave_nums <- wave_nums[!is.na(wave_nums)]
  if (!length(wave_nums)) wave_nums <- 1L

  long_rows <- list()
  for (i in seq_len(nrow(data))) {
    row <- data[i, , drop = FALSE]
    for (w in wave_nums) {
      wcols <- sym_cols[grepl(paste0("_W", w, "$"), sym_cols)]
      if (!length(wcols)) next
      for (sc in wcols) {
        if (!sc %in% names(row)) next
        long_rows[[length(long_rows) + 1L]] <- data.frame(
          ID = as.character(row[[id_col]][1L]),
          Wave = w, Symptom = sc,
          Value = suppressWarnings(as.numeric(row[[sc]][1L])),
          Age = suppressWarnings(as.numeric(row[["Age"]][1L])),
          Sex = as.character(if ("Sex" %in% names(row)) row[["Sex"]][1L] else row[["Gender"]][1L]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  long_df <- do.call(rbind, long_rows)
  ctx$data$network_long <- long_df

  wide_path <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "_network_temp_wide.csv")
  dir.create(dirname(wide_path), recursive = TRUE, showWarnings = FALSE)
  export_cols <- intersect(
    unique(c(id_col, sym_cols, "Age", "Sex", "Gender", "Depression_dx", "Cohort")),
    names(data)
  )
  utils::write.csv(data[, export_cols, drop = FALSE], wide_path, row.names = FALSE)

  ctx$results$network_temp_prepare_long <- list(
    n_long = nrow(long_df), n_waves = length(wave_nums), wide_path = wide_path
  )
  cli::cli_alert_success("网络温度纵向数据准备完成")
  ctx
}

register_block("network_temp_prepare_long", block_network_temp_prepare_long, "网络温度纵向准备")
