###############################################################################
# pamob_svy_nfl — Exploratory：log(sNfL) ~ phenotype（与 DSST 主样本分离）
###############################################################################

block_pamob_svy_nfl <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages("survey")
  bl <- pamob_cfg(ctx)
  d <- ctx$data$pamob_nhanes_nfl
  if (is.null(d) || !nrow(d)) stop("pamob_svy_nfl: 无 NfL 分析集（需 WTSSNH2Y>0）", call. = FALSE)
  d <- d[!is.na(d$ln_SSSNFL) & !is.na(d$phenotype) & d$WTSSNH2Y > 0, , drop = FALSE]
  d$phenotype <- relevel(factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
                          ref = "Active_preserved")
  des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSSNH2Y, nest = TRUE, data = d)

  m3 <- pamob_resolve_covars(d, bl$nhanes_covariates_model3 %||% bl$covariates_model3)
  m3e <- unique(c(m3, pamob_resolve_covars(d, "eGFR")))
  fit_models <- list(
    Model0 = character(0),
    Model1 = pamob_resolve_covars(d, bl$nhanes_covariates_model1 %||% bl$covariates_model1),
    Model2 = pamob_resolve_covars(d, bl$nhanes_covariates_model2 %||% bl$covariates_model2),
    Model3 = m3,
    Model3_eGFR = m3e
  )
  tabs <- list()
  fit_m3 <- NULL
  for (nm in names(fit_models)) {
    rhs <- pamob_fml_rhs(fit_models[[nm]])
    fml <- stats::as.formula(paste("ln_SSSNFL ~", rhs))
    fit <- tryCatch(survey::svyglm(fml, design = des), error = function(e) e)
    if (inherits(fit, "error")) {
      tabs[[nm]] <- data.frame(
        model = nm, outcome = "log_sNfL", term = NA_character_,
        estimate = NA_real_, std.error = NA_real_, p.value = NA_real_,
        weight = "WTSSNH2Y", n = nrow(d), design_df = NA_real_,
        note = conditionMessage(fit), stringsAsFactors = FALSE
      )
      next
    }
    if (identical(nm, "Model3")) fit_m3 <- fit
    sm <- summary(fit)$coefficients
    ddf <- tryCatch(as.numeric(fit$df.residual), error = function(e) NA_real_)
    tabs[[nm]] <- data.frame(
      model = nm, outcome = "log_sNfL", term = rownames(sm),
      estimate = sm[, 1], std.error = sm[, 2],
      p.value = pamob_extract_coef_p(sm, fit),
      weight = "WTSSNH2Y", n = nrow(d),
      design_df = if (length(ddf) == 1L) ddf else NA_real_,
      note = if (is.finite(ddf) && ddf <= 0) "P used normal approximation (design df<=0)" else "Exploratory",
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, tabs)
  # 不写入正文 Table 4；单独 exploratory
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx), "Table_S_NHANES_sNfL_exploratory.csv"))
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_NfL_Exploratory.csv"))

  n_strata <- length(unique(d$SDMVSTRA[!is.na(d$SDMVSTRA)]))
  n_psu <- length(unique(paste(d$SDMVSTRA, d$SDMVPSU)))
  design_info <- data.frame(
    sample = "sNfL_exploratory",
    n = nrow(d),
    weight = "WTSSNH2Y",
    n_strata = n_strata,
    n_psu = n_psu,
    design_df_model3 = if (!is.null(fit_m3)) tryCatch(as.numeric(fit_m3$df.residual), error = function(e) NA_real_) else NA_real_,
    stringsAsFactors = FALSE
  )
  pamob_write_csv(design_info, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_Design_Info_NfL.csv"))

  ctx$results$pamob_svy_nfl <- list(
    table = tab, design = des, data = d, models = fit_models,
    design_info = design_info, exploratory = TRUE
  )
  cli::cli_alert_success("svy NfL exploratory n={nrow(d)}; 未写入正文 Table 4")
  ctx
}

register_block("pamob_svy_nfl", block_pamob_svy_nfl, "NHANES svy NfL exploratory")
