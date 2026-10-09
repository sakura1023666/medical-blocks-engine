###############################################################################
# pamob_sensitivity_charls — global + episodic 同套敏感性（Active–limited × time 稳定性）
###############################################################################

block_pamob_sensitivity_charls <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  long <- ctx$data$pamob_charls_long
  if (is.null(long)) stop("pamob_sensitivity_charls: 无长表", call. = FALSE)
  bl <- pamob_cfg(ctx)
  charls_dir <- file.path(pamob_data_root(ctx), "CHARLS")
  baseline_wave <- as.integer(bl$baseline_wave %||% 2011L)[1L]
  met_thr <- as.numeric(bl$pa_met_threshold %||% 600)[1L]

  .run_both <- function(dat, analysis_lab) {
    out <- list()
    for (oc in c("Global_cognition", "Episodic_memory")) {
      if (!oc %in% names(dat)) next
      res <- pamob_fit_lmm(dat, oc, bl)
      res$table$analysis <- analysis_lab
      res$table$outcome <- oc
      out[[length(out) + 1L]] <- res$table
    }
    out
  }

  tabs <- list()
  long2 <- long
  long2$phenotype <- factor(long2$phenotype_2_bl, levels = unname(pamob_phenotype_labels()))
  tabs <- c(tabs, .run_both(long2, "phenotype_2_mobility_ge2"))

  n_obs <- table(long$ID_h)
  keep_ids <- names(n_obs)[as.integer(n_obs) >= 2L]
  long3 <- long[long$ID_h %in% keep_ids, , drop = FALSE]
  tabs <- c(tabs, .run_both(long3, "ids_with_ge2_waves"))

  if ("Stroke" %in% names(long)) {
    long4 <- long[is.na(long$Stroke) | as.integer(long$Stroke) != 1L, , drop = FALSE]
    tabs <- c(tabs, .run_both(long4, "exclude_baseline_stroke"))
  }

  pa_alt <- pamob_compute_pa_sufficient_from_raw(
    charls_dir, wave = baseline_wave,
    min_map = c(15, 60, 150, 210), met_threshold = met_thr
  )
  if (!is.null(pa_alt) && nrow(pa_alt)) {
    long5 <- merge(long, pa_alt, by = "ID_h", all.x = TRUE)
    long5 <- long5[!is.na(long5$pa_sufficient_alt) & !is.na(long5$mobility_limited), , drop = FALSE]
    long5$phenotype_code_alt <- pamob_phenotype_key(long5$pa_sufficient_alt, long5$mobility_limited)
    long5$phenotype <- pamob_phenotype_factor(long5$phenotype_code_alt)
    long5 <- long5[!is.na(long5$phenotype), , drop = FALSE]
    tabs <- c(tabs, .run_both(long5, "PA_alt_duration_15_60_150_210"))
    pamob_write_csv(
      data.frame(
        n_ids_alt = length(unique(long5$ID_h)),
        n_rows_alt = nrow(long5),
        pct_sufficient_alt = round(100 * mean(long5$pa_sufficient_alt == 1L, na.rm = TRUE), 1),
        stringsAsFactors = FALSE
      ),
      file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_S_PA_Alt_Duration_Summary.csv")
    )
  }

  if ("adl_iadl_disabled" %in% names(long)) {
    long6 <- long[is.na(long$adl_iadl_disabled) | as.integer(long$adl_iadl_disabled) != 1L, , drop = FALSE]
    tabs <- c(tabs, .run_both(long6, "exclude_baseline_ADL_IADL"))
  } else {
    adl <- pamob_build_adl_iadl_flag(charls_dir, wave = baseline_wave)
    if (!is.null(adl) && nrow(adl)) {
      long6 <- merge(long, adl, by = "ID_h", all.x = TRUE)
      long6 <- long6[is.na(long6$adl_iadl_disabled) | as.integer(long6$adl_iadl_disabled) != 1L, , drop = FALSE]
      tabs <- c(tabs, .run_both(long6, "exclude_baseline_ADL_IADL"))
    }
  }

  # random slope（Model3 only，global + episodic）
  pamob_ensure_packages(c("lme4", "lmerTest"))
  for (oc in c("Global_cognition", "Episodic_memory")) {
    if (!oc %in% names(long)) next
    d <- long[!is.na(long[[oc]]) & !is.na(long$phenotype), , drop = FALSE]
    d$phenotype <- stats::relevel(factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
                                   ref = "Active_preserved")
    covs <- pamob_resolve_covars(d, bl$covariates_model3 %||% character(0))
    rhs <- paste(c("Time_years * phenotype", covs), collapse = " + ")
    fml <- stats::as.formula(paste(oc, "~", rhs, "+ (Time_years | ID_h)"))
    fit <- tryCatch(lmerTest::lmer(fml, data = d, REML = TRUE), error = function(e) e)
    if (inherits(fit, "error")) {
      tabs[[length(tabs) + 1L]] <- data.frame(
        model = "Model3_random_slope", term = NA_character_,
        estimate = NA_real_, std.error = NA_real_, p.value = NA_real_,
        note = conditionMessage(fit), analysis = "random_slope_Time",
        outcome = oc, stringsAsFactors = FALSE
      )
    } else {
      sm <- summary(fit)$coefficients
      tabs[[length(tabs) + 1L]] <- data.frame(
        model = "Model3_random_slope", term = rownames(sm),
        estimate = sm[, "Estimate"], std.error = sm[, "Std. Error"],
        p.value = if ("Pr(>|t|)" %in% colnames(sm)) sm[, "Pr(>|t|)"] else NA_real_,
        note = NA_character_, analysis = "random_slope_Time",
        outcome = oc, stringsAsFactors = FALSE
      )
    }
  }

  tab <- do.call(rbind, tabs)
  # Active–limited × time 稳定性摘要
  al <- tab[grepl("Time_years:phenotypeActive_limited", tab$term) &
              tab$model %in% c("Model3", "Model3_random_slope"),
            c("outcome", "analysis", "model", "estimate", "std.error", "p.value"),
            drop = FALSE]
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx), "Table_S_CHARLS_LMM_Sensitivity.csv"))
  pamob_write_csv(al, file.path(pamob_tables_dir(ctx, "CHARLS"),
                                "Table_S_Active_limited_slope_stability.csv"))
  pamob_write_csv(pamob_pa_duration_map(),
                  file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_S_PA_Duration_Representatives.csv"))
  pamob_write_csv(pamob_pa_duration_map_alt(),
                  file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_S_PA_Duration_Alt_Map.csv"))
  ctx$results$pamob_sensitivity_charls <- list(
    n_ge2 = length(keep_ids), analyses = unique(tab$analysis),
    active_limited_slope = al
  )
  cli::cli_alert_success(
    "CHARLS 敏感性完成: {paste(unique(tab$analysis), collapse=', ')}; AL-slope rows={nrow(al)}"
  )
  ctx
}

register_block("pamob_sensitivity_charls", block_pamob_sensitivity_charls, "CHARLS 敏感性")
