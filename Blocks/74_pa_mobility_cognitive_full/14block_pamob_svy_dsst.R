###############################################################################
# pamob_svy_dsst — 正文主分析：完整 cognitive sample（WTMEC2YR，不绑 NfL）
###############################################################################

block_pamob_svy_dsst <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages("survey")
  bl <- pamob_cfg(ctx)
  d <- ctx$data$pamob_nhanes_dsst %||% ctx$data$pamob_nhanes
  if (is.null(d) || !nrow(d)) stop("pamob_svy_dsst: 无数据", call. = FALSE)
  d <- d[!is.na(d$CFDDS) & !is.na(d$phenotype), , drop = FALSE]

  # 铁律：正文 DSST 不得用 WTSSNH2Y 筛样本（那是 NfL subsample）
  if (!"WTMEC2YR" %in% names(d) || all(is.na(d$WTMEC2YR)) || all(d$WTMEC2YR <= 0, na.rm = TRUE)) {
    stop("pamob_svy_dsst: 主分析需要 WTMEC2YR>0（完整 cognitive sample）", call. = FALSE)
  }
  d <- d[!is.na(d$WTMEC2YR) & d$WTMEC2YR > 0, , drop = FALSE]
  d$WT_USE <- d$WTMEC2YR
  note <- "WTMEC2YR"
  d$phenotype <- relevel(factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
                          ref = "Active_preserved")
  if (!all(c("SDMVPSU", "SDMVSTRA") %in% names(d)) ||
      any(is.na(d$SDMVPSU)) || any(is.na(d$SDMVSTRA))) {
    des <- survey::svydesign(ids = ~1, weights = ~WT_USE, data = d)
  } else {
    des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WT_USE, nest = TRUE, data = d)
  }

  fit_models <- list(
    Model0 = character(0),
    Model1 = pamob_resolve_covars(d, bl$nhanes_covariates_model1 %||% bl$covariates_model1),
    Model2 = pamob_resolve_covars(d, bl$nhanes_covariates_model2 %||% bl$covariates_model2),
    Model3 = pamob_resolve_covars(d, bl$nhanes_covariates_model3 %||% bl$covariates_model3)
  )
  tabs <- list()
  fit_m3 <- NULL
  for (nm in names(fit_models)) {
    rhs <- pamob_fml_rhs(fit_models[[nm]])
    fml <- stats::as.formula(paste("CFDDS ~", rhs))
    fit <- tryCatch(survey::svyglm(fml, design = des), error = function(e) e)
    if (inherits(fit, "error")) {
      tabs[[nm]] <- data.frame(
        model = nm, outcome = "DSST", term = NA_character_,
        estimate = NA_real_, std.error = NA_real_, p.value = NA_real_,
        weight = note, n = nrow(d), note = conditionMessage(fit),
        stringsAsFactors = FALSE
      )
      next
    }
    if (identical(nm, "Model3")) fit_m3 <- fit
    sm <- summary(fit)$coefficients
    ddf <- tryCatch(as.numeric(fit$df.residual), error = function(e) NA_real_)
    tabs[[nm]] <- data.frame(
      model = nm, outcome = "DSST", term = rownames(sm),
      estimate = sm[, 1], std.error = sm[, 2],
      p.value = pamob_extract_coef_p(sm, fit),
      weight = note, n = nrow(d),
      design_df = if (length(ddf) == 1L) ddf else NA_real_,
      note = if (is.finite(ddf) && ddf <= 0) "P used normal approximation (design df<=0)" else NA_character_,
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, tabs)
  ctr <- if (!is.null(fit_m3)) {
    pamob_svy_pairwise_contrasts(fit_m3, outcome = "DSST")
  } else {
    data.frame()
  }
  if (nrow(ctr)) {
    ctr$weight <- note
    ctr$n <- nrow(d)
    pamob_write_csv(ctr, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_DSST_Contrasts.csv"))
  }

  # 设计信息（老师审稿 §6）
  n_strata <- if ("SDMVSTRA" %in% names(d)) length(unique(d$SDMVSTRA[!is.na(d$SDMVSTRA)])) else NA_integer_
  n_psu <- if ("SDMVPSU" %in% names(d)) length(unique(paste(d$SDMVSTRA, d$SDMVPSU))) else NA_integer_
  design_info <- data.frame(
    sample = "DSST_main_cognitive",
    n = nrow(d),
    weight = note,
    n_strata = n_strata,
    n_psu = n_psu,
    design_df_model3 = if (!is.null(fit_m3)) tryCatch(as.numeric(fit_m3$df.residual), error = function(e) NA_real_) else NA_real_,
    stringsAsFactors = FALSE
  )
  pamob_write_csv(design_info, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_Design_Info_DSST.csv"))

  ctx$results$pamob_svy_dsst <- list(
    table = tab, design = des, data = d, models = fit_models,
    contrasts = ctr, design_info = design_info
  )
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_DSST.csv"))
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx), "Table 4. NHANES DSST regressions.csv"))
  cli::cli_alert_success("svy DSST main n={nrow(d)}; weight={note}; contrasts={nrow(ctr)}")
  ctx
}

register_block("pamob_svy_dsst", block_pamob_svy_dsst, "NHANES svy DSST")
