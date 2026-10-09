###############################################################################
# pamob_sensitivity_nhanes — PFQ5排除 / 卒中排除 / NfL+eGFR+CRP
###############################################################################

block_pamob_sensitivity_nhanes <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages("survey")
  bl <- pamob_cfg(ctx)
  d_nf <- ctx$data$pamob_nhanes_nfl
  d_ds <- ctx$data$pamob_nhanes_dsst
  if (is.null(d_nf)) {
    cli::cli_alert_warning("pamob_sensitivity_nhanes: 无 NfL 集，跳过")
    return(ctx)
  }

  phn <- as.data.frame(table(phenotype = as.character(d_nf$phenotype)), stringsAsFactors = FALSE)
  names(phn)[2] <- "n"
  phn$flag <- ifelse(phn$n < 30, "below_n30_exploratory",
                     ifelse(phn$n < 50, "caution_30_49", "ok_ge50"))
  pamob_write_csv(phn, file.path(pamob_tables_dir(ctx), "Table_S_NHANES_Phenotype_N_Gate.csv"))

  m3 <- pamob_resolve_covars(d_nf, bl$nhanes_covariates_model3 %||% character(0))
  tabs <- list()

  .des_nf <- function(dd) {
    dd <- dd[!is.na(dd$ln_SSSNFL) & !is.na(dd$phenotype) & dd$WTSSNH2Y > 0, , drop = FALSE]
    dd$phenotype <- relevel(factor(dd$phenotype, levels = unname(pamob_phenotype_labels())),
                             ref = "Active_preserved")
    list(data = dd,
         des = survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSSNH2Y,
                                 nest = TRUE, data = dd))
  }
  .des_ds <- function(dd) {
    dd <- dd[!is.na(dd$CFDDS) & !is.na(dd$phenotype), , drop = FALSE]
    # 敏感性 DSST 也优先完整 cognitive weight，禁止误绑 NfL 权重
    if ("WTMEC2YR" %in% names(dd) && any(dd$WTMEC2YR > 0, na.rm = TRUE)) {
      dd <- dd[!is.na(dd$WTMEC2YR) & dd$WTMEC2YR > 0, , drop = FALSE]
      wt <- "WTMEC2YR"
    } else if ("WTSSNH2Y" %in% names(dd) && any(dd$WTSSNH2Y > 0, na.rm = TRUE)) {
      dd <- dd[!is.na(dd$WTSSNH2Y) & dd$WTSSNH2Y > 0, , drop = FALSE]
      wt <- "WTSSNH2Y"
    } else {
      dd$WT_USE <- 1
      wt <- "WT_USE"
    }
    dd$WT_USE <- dd[[wt]]
    dd$phenotype <- relevel(factor(dd$phenotype, levels = unname(pamob_phenotype_labels())),
                             ref = "Active_preserved")
    list(data = dd,
         des = survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WT_USE,
                                 nest = TRUE, data = dd),
         wt = wt)
  }

  # 1) PFQ answer 5 exclude
  if ("pfq_any_do_not_do" %in% names(d_nf)) {
    nf1 <- d_nf[is.na(d_nf$pfq_any_do_not_do) | d_nf$pfq_any_do_not_do != 1L, , drop = FALSE]
    o1 <- .des_nf(nf1)
    tabs[[length(tabs) + 1L]] <- pamob_svyglm_coef_tab(
      o1$des, "ln_SSSNFL", m3, "Sens_PFQ5_exclude_NfL", "WTSSNH2Y", nrow(o1$data))
    if (!is.null(d_ds) && "pfq_any_do_not_do" %in% names(d_ds)) {
      ds1 <- d_ds[is.na(d_ds$pfq_any_do_not_do) | d_ds$pfq_any_do_not_do != 1L, , drop = FALSE]
      o1d <- .des_ds(ds1)
      tabs[[length(tabs) + 1L]] <- pamob_svyglm_coef_tab(
        o1d$des, "CFDDS", pamob_resolve_covars(o1d$data, m3),
        "Sens_PFQ5_exclude_DSST", o1d$wt, nrow(o1d$data))
    }
  }

  # 2) Stroke exclude
  if ("Stroke" %in% names(d_nf)) {
    nf2 <- d_nf[is.na(d_nf$Stroke) | as.integer(d_nf$Stroke) != 1L, , drop = FALSE]
    o2 <- .des_nf(nf2)
    tabs[[length(tabs) + 1L]] <- pamob_svyglm_coef_tab(
      o2$des, "ln_SSSNFL", pamob_resolve_covars(o2$data, m3),
      "Sens_exclude_stroke_NfL", "WTSSNH2Y", nrow(o2$data))
    if (!is.null(d_ds) && "Stroke" %in% names(d_ds)) {
      ds2 <- d_ds[is.na(d_ds$Stroke) | as.integer(d_ds$Stroke) != 1L, , drop = FALSE]
      o2d <- .des_ds(ds2)
      tabs[[length(tabs) + 1L]] <- pamob_svyglm_coef_tab(
        o2d$des, "CFDDS", pamob_resolve_covars(o2d$data, m3),
        "Sens_exclude_stroke_DSST", o2d$wt, nrow(o2d$data))
    }
  }

  # 3) NfL Model3 + eGFR (±CRP if usable)
  cov_extra <- pamob_drop_degenerate_covars(d_nf, c("eGFR", "CRP"))
  cov_crp <- unique(c(m3, cov_extra))
  o3 <- .des_nf(d_nf)
  # 保证 phenotype 因子水平完整
  o3$data$phenotype <- factor(o3$data$phenotype, levels = unname(pamob_phenotype_labels()))
  o3$data$phenotype <- stats::relevel(o3$data$phenotype, ref = "Active_preserved")
  tabs[[length(tabs) + 1L]] <- pamob_svyglm_coef_tab(
    o3$des, "ln_SSSNFL", cov_crp,
    if ("CRP" %in% cov_extra) "Sens_Model3_eGFR_CRP_NfL" else "Sens_Model3_eGFR_NfL",
    "WTSSNH2Y", nrow(o3$data)
  )

  tab <- do.call(rbind, tabs)
  pamob_write_csv(tab, file.path(pamob_tables_dir(ctx), "Table_S_NHANES_Sensitivity_Regressions.csv"))
  note <- sprintf(
    "NfL analytic n=%d; min phenotype n=%d (%s); PFQ5/stroke/CRP sensitivities written",
    nrow(d_nf), min(phn$n), phn$phenotype[which.min(phn$n)]
  )
  writeLines(c(note, pamob_pfq_coding_rules()),
            file.path(pamob_tables_dir(ctx), "NHANES_sensitivity_note.txt"))
  ctx$results$pamob_sensitivity_nhanes <- list(phenotype_n = phn, table = tab, note = note)
  cli::cli_alert_success("NHANES 敏感性: {note}")
  ctx
}

register_block("pamob_sensitivity_nhanes", block_pamob_sensitivity_nhanes, "NHANES 敏感性")
