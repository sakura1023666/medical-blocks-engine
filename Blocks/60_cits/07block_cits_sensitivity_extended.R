###############################################################################
#  cits_sensitivity_extended — 截断日期 + 德州剔除 + 州分类变体
###############################################################################

block_cits_sensitivity_extended <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/cdc_wonder_cits_utils.R"), local = FALSE)

  records <- ctx$data$cleaned %||% ctx$data$wonder_raw
  if (is.null(records)) stop("cits_sensitivity_extended: 无数据", call. = FALSE)

  cutoffs <- bl$sensitivity_cutoffs %||% c("2022-09-01", "2022-10-01", "2022-11-01")
  state_col <- bl$state_col %||% "State"
  outcome <- bl$primary_outcome %||% "Congenital_anomaly"
  rows <- list()

  for (cut in cutoffs) {
    bl2 <- bl
    bl2$intervention_date <- cut
    mon <- .cits_prepare_monthly_rates(records, bl2)
    did <- .cits_did_change(mon, outcome)
    if (nrow(did)) {
      did$scenario <- paste0("cutoff_", cut)
      rows[[length(rows) + 1L]] <- did
    }
  }

  if (state_col %in% names(records)) {
    no_tx <- records[!records[[state_col]] %in% "TX", , drop = FALSE]
    mon2 <- .cits_prepare_monthly_rates(no_tx, bl)
    did2 <- .cits_did_change(mon2, outcome)
    if (nrow(did2)) {
      did2$scenario <- "exclude_Texas"
      rows[[length(rows) + 1L]] <- did2
    }

    total_ban <- .cits_total_ban_states()
    protected <- .cits_protected_states()
    rec3 <- records
    rec3$Ban_state <- ifelse(rec3[[state_col]] %in% total_ban, "Ban",
      ifelse(rec3[[state_col]] %in% protected, "No_ban", "Other"))
    rec3 <- rec3[rec3$Ban_state != "Other", , drop = FALSE]
    mon3 <- .cits_prepare_monthly_rates(rec3, bl)
    did3 <- .cits_did_change(mon3, outcome)
    if (nrow(did3)) {
      did3$scenario <- "total_ban_vs_protected"
      rows[[length(rows) + 1L]] <- did3
    }
  }

  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_CITS_Sensitivity_Extended.csv"), row.names = FALSE)

  ctx$results$cits_sensitivity_extended <- out_df
  cli::cli_alert_success("CITS 扩展敏感性（截断/德州/州分类）完成")
  ctx
}

register_block("cits_sensitivity_extended", block_cits_sensitivity_extended, "CITS 扩展敏感性")
