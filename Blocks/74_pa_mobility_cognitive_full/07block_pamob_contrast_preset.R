###############################################################################
# pamob_contrast_preset — 四组设计 pairwise：level + slope（global / episodic）
# 预设：Inactive–preserved vs Active–preserved；Active–limited vs Inactive–limited
###############################################################################

block_pamob_contrast_preset <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages(c("lme4", "lmerTest"))
  long <- ctx$data$pamob_lmm_fit_data %||% ctx$data$pamob_charls_long
  if (is.null(long)) stop("pamob_contrast_preset: 无数据", call. = FALSE)
  bl <- pamob_cfg(ctx)
  covs <- pamob_resolve_covars(long, bl$covariates_model3 %||% character(0))

  rows_all <- list()
  for (outcome in c("Global_cognition", "Episodic_memory")) {
    if (!outcome %in% names(long)) next
    d <- long[!is.na(long[[outcome]]) & !is.na(long$phenotype) & !is.na(long$Time_years), , drop = FALSE]
    d$phenotype <- relevel(factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
                             ref = "Active_preserved")
    rhs <- paste(c("Time_years * phenotype", covs), collapse = " + ")
    fml <- stats::as.formula(paste(outcome, "~", rhs, "+ (1 | ID_h)"))
    fit <- tryCatch(lmerTest::lmer(fml, data = d, REML = TRUE), error = function(e) e)
    if (inherits(fit, "error")) {
      rows_all[[length(rows_all) + 1L]] <- data.frame(
        outcome = outcome, contrast = NA_character_, type = NA_character_,
        estimate = NA_real_, se = NA_real_, p_wald = NA_real_,
        note = conditionMessage(fit), stringsAsFactors = FALSE
      )
      next
    }
    rows_all[[length(rows_all) + 1L]] <- pamob_lmm_pairwise_contrasts(fit, outcome = outcome)
  }

  rows <- do.call(rbind, rows_all)
  pamob_write_csv(rows, file.path(pamob_tables_dir(ctx), "Table 2b. CHARLS preset contrasts.csv"))
  # 兼容旧诊断字段：仅 global slope 两行
  g_slope <- rows[rows$outcome == "Global_cognition" & rows$type == "slope", , drop = FALSE]
  ctx$results$pamob_contrast_preset <- list(table = rows, global_slope = g_slope)
  cli::cli_alert_success(
    "预设对比完成 rows={nrow(rows)}; global slope P=[{paste(sprintf('%.4f', g_slope$p_wald), collapse=', ')}]"
  )
  ctx
}

register_block("pamob_contrast_preset", block_pamob_contrast_preset, "CHARLS 预设对比")
