###############################################################################
# pamob_baseline_nhanes — Table 3：DSST 主认知样本加权基线（非 NfL subsample）
###############################################################################

block_pamob_baseline_nhanes <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  d <- ctx$data$pamob_nhanes_dsst %||% ctx$data$pamob_nhanes
  if (is.null(d) || !nrow(d)) stop("pamob_baseline_nhanes: 无 NHANES DSST 主样本", call. = FALSE)

  cont <- c("Age", "BMI", "Depression", "CFDDS", "PIR")
  catg <- c("Gender", "Race", "Education", "Marital_Status",
            "Smoke", "Alcohol_drinking",
            "Hypertension", "Diabetes", "CHD", "HF", "Stroke")
  if ("WTMEC2YR" %in% names(d) && any(d$WTMEC2YR > 0, na.rm = TRUE)) {
    d <- d[!is.na(d$WTMEC2YR) & d$WTMEC2YR > 0, , drop = FALSE]
    tab <- pamob_baseline_by_phenotype_weighted(
      d, wt_col = "WTMEC2YR", continuous = cont, categorical = catg
    )
    note <- "survey_weighted_WTMEC2YR_DSST_main"
  } else {
    tab <- pamob_baseline_by_phenotype(d, continuous = cont, categorical = catg)
    note <- "unweighted_fallback"
  }

  simp <- as.data.frame(table(phenotype = as.character(d$phenotype)), stringsAsFactors = FALSE)
  names(simp)[2] <- "n"
  simp$pct_unweighted <- round(100 * simp$n / sum(simp$n), 1)
  if ("WTMEC2YR" %in% names(d) && any(d$WTMEC2YR > 0, na.rm = TRUE)) {
    wsum <- tapply(d$WTMEC2YR, as.character(d$phenotype), sum, na.rm = TRUE)
    simp$pct_weighted <- round(100 * as.numeric(wsum[simp$phenotype]) / sum(wsum, na.rm = TRUE), 1)
  }

  out_dir <- pamob_tables_dir(ctx)
  pamob_write_csv(tab, file.path(out_dir, "Table 3. NHANES baseline by phenotype.csv"))
  pamob_write_csv(simp, file.path(out_dir, "Table 3b. NHANES phenotype N weighted.csv"))

  # NfL subsample N（exploratory 附表用）
  d_nf <- ctx$data$pamob_nhanes_nfl
  if (!is.null(d_nf) && nrow(d_nf)) {
    snf <- as.data.frame(table(phenotype = as.character(d_nf$phenotype)), stringsAsFactors = FALSE)
    names(snf)[2] <- "n"
    pamob_write_csv(snf, file.path(out_dir, "Table_S_NHANES_NfL_sample_N.csv"))
  }

  ctx$results$pamob_baseline_nhanes <- list(table = tab, simple = simp, n = nrow(d), note = note)
  cli::cli_alert_success("Table 3 NHANES DSST-main n={nrow(d)} ({note})")
  ctx
}

register_block("pamob_baseline_nhanes", block_pamob_baseline_nhanes, "NHANES Table3")
