###############################################################################
#  cits_aggregate_monthly — CDC WONDER 月度结局率聚合
#  文献: Gressler 2025 BMC Public Health — Dobbs CITS
###############################################################################

block_cits_aggregate_monthly <- function(ctx, ...) {
  bl <- ctx$config$cdc_wonder %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/cdc_wonder_cits_utils.R"), local = FALSE)

  data <- ctx$data$cleaned %||% ctx$data$wonder_raw %||% ctx$data$raw
  if (is.null(data)) stop("cits_aggregate_monthly: 无数据", call. = FALSE)

  monthly <- .cits_prepare_monthly_rates(data, bl)
  if (!nrow(monthly)) {
    date_col <- bl$date_col %||% "Birth_month"
    group_col <- bl$group_col %||% "Ban_state"
    outcome_cols <- bl$outcome_cols %||% c("Nonliving_birth", "Congenital_anomaly", "Maternal_morbidity")
    d <- data
    d$month <- as.Date(paste0(d[[date_col]], "-01"))
    d$ban <- as.integer(as.character(d[[group_col]]) %in% c("Ban", "1", "Yes"))
    d$tau <- as.numeric(d$month - min(d$month, na.rm = TRUE)) / 30.44
    d$post <- as.integer(d$month >= as.Date(bl$intervention_date %||% "2022-11-01"))
    rows <- list()
    for (oc in intersect(outcome_cols, names(d))) {
      d$rate <- suppressWarnings(as.numeric(d[[oc]]))
      keys <- paste(d$month, d$ban, d$post, d$tau, sep = "|")
      for (k in unique(keys)) {
        sub <- d[keys == k, , drop = FALSE]
        rows[[length(rows) + 1L]] <- data.frame(
          month = sub$month[1L], ban = sub$ban[1L], post = sub$post[1L], tau = sub$tau[1L],
          rate = mean(sub$rate, na.rm = TRUE), n = nrow(sub), outcome = oc,
          stringsAsFactors = FALSE
        )
      }
    }
    monthly <- if (length(rows)) do.call(rbind, rows) else data.frame()
  }
  ctx$data$cits_monthly <- monthly

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(monthly, file.path(out_dir, "Table_CITS_Monthly_Aggregate.csv"), row.names = FALSE)

  ctx$results$cits_aggregate_monthly <- list(n_months = length(unique(monthly$month)))
  cli::cli_alert_success("CITS 月度聚合完成")
  ctx
}

register_block("cits_aggregate_monthly", block_cits_aggregate_monthly, "CDC WONDER 月度率聚合")
