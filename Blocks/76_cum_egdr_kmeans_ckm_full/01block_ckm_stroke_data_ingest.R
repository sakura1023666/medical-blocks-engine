###############################################################################
# ckm_stroke_data_ingest — 读 4d 宽表、列对齐、可选重算 eGDR/cum
###############################################################################

block_ckm_stroke_data_ingest <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  path <- bl$data_csv %||% ctx$config$data$rawdata_path
  df <- ckm_stroke_read_wide(path)
  if (isTRUE(bl$filter_cohort_final) && "cohort_final" %in% names(df)) {
    df <- df[as.integer(df$cohort_final) == 1L, , drop = FALSE]
  }
  # 本流水线未挂 data_clean block：在此落实 config$data_clean$age_filter
  age_filter <- ctx$config$data_clean$age_filter
  if (!is.null(age_filter) && nzchar(as.character(age_filter)[1L])) {
    n_before_age <- nrow(df)
    df <- df[with(df, eval(parse(text = as.character(age_filter)[1L]))), , drop = FALSE]
    cli::cli_alert_info(
      "age_filter '{age_filter}': {n_before_age} -> {nrow(df)} (excluded {n_before_age - nrow(df)})"
    )
  }
  df <- ckm_stroke_harmonize_columns(df)
  if (isTRUE(bl$recompute_egdr %||% TRUE)) {
    df <- ckm_stroke_recompute_egdr(df, bl)
  }
  # 结局别名
  oc <- ctx$config$data$outcome_column %||% "Stroke"
  if (!oc %in% names(df) && "Stroke" %in% names(df)) df[[oc]] <- df$Stroke
  ctx$data$raw <- df
  ctx$data$cleaned <- df
  ctx$results$ckm_stroke_data_ingest <- list(n = nrow(df), cols = names(df))
  cli::cli_alert_success("CKM stroke 宽表入库: n={nrow(df)}")
  ctx
}

register_block("ckm_stroke_data_ingest", block_ckm_stroke_data_ingest, "CKM卒中4d宽表入库对齐")
