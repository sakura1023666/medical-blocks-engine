###############################################################################
#  dynamic_causal_meta_merge — CHARLS + ELSA Cox HR 随机效应 meta
###############################################################################

block_dynamic_causal_meta_merge <- function(ctx, ...) {
  bl <- ctx$config$dynamic_causal_meta %||% list()
  sb <- ctx$config$study_batch %||% list()
  root <- ctx$config$project$root %||% getwd()
  base <- sb$output_base %||% ctx$config$project$output_dir
  cohorts <- as.character(bl$cohorts %||% c("CHARLS", "ELSA"))
  analysis <- bl$analysis_tag %||% "total_cmi"

  rows <- list()
  for (coh in cohorts) {
    for (tag in c("", paste0("_", analysis))) {
      p <- file.path(base, "by_unit", paste0(coh, tag), "Tables", "Table_Cox_Total_CMI.csv")
      if (!file.exists(p)) p <- file.path(base, "by_unit", coh, "Tables", "Table_Cox_Total_CMI.csv")
      if (!file.exists(p)) next
      tab <- utils::read.csv(p, stringsAsFactors = FALSE)
      hr_row <- tab[grepl("T3_high|Total_CMI_continuous", tab$term), , drop = FALSE][1, , drop = FALSE]
      if (nrow(hr_row)) {
        rows[[length(rows) + 1L]] <- data.frame(
          cohort = coh, term = hr_row$term, HR = hr_row$HR,
          lower = hr_row$lower, upper = hr_row$upper, p = hr_row$p,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) {
    cli::cli_alert_warning("dynamic_causal_meta_merge: 无分队列 Cox 表，跳过 meta（请先跑 batch worker）")
    return(ctx)
  }
  pool <- do.call(rbind, rows)
  loghr <- log(as.numeric(pool$HR))
  se <- (log(as.numeric(pool$upper)) - log(as.numeric(pool$lower))) / (2 * 1.96)
  w <- 1 / pmax(se^2, 1e-6)
  pooled_hr <- exp(sum(w * loghr) / sum(w))
  pooled_se <- sqrt(1 / sum(w))
  meta_tab <- data.frame(
    analysis = analysis,
    method = "Inverse_variance_fixed",
    k = nrow(pool),
    pooled_HR = round(pooled_hr, 3),
    lower = round(exp(log(pooled_hr) - 1.96 * pooled_se), 3),
    upper = round(exp(log(pooled_hr) + 1.96 * pooled_se), 3),
    stringsAsFactors = FALSE
  )
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(pool, file.path(out_dir, "Table_Meta_Input_Cohorts.csv"), row.names = FALSE)
  utils::write.csv(meta_tab, file.path(out_dir, "Table_Meta_Pooled_HR.csv"), row.names = FALSE)
  ctx$results$dynamic_causal_meta <- list(input = pool, pooled = meta_tab)
  cli::cli_alert_success("双库 meta 合并完成（k={nrow(pool)}）")
  ctx
}

register_block(
  "dynamic_causal_meta_merge",
  block_dynamic_causal_meta_merge,
  "CHARLS+ELSA Cox meta 合并"
)
