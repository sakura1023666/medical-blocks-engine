#!/usr/bin/env Rscript
# Fix Table3 (weighted all 4 groups), Table4 Model3 P, Figure4 ABC letters + republish
suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
  source("R/pub_figure_export.R")
})

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES")
charls_u <- file.path(batch, "by_unit", "【success】CHARLS")
tab_root <- file.path(batch, "Tables")
options(survey.lonely.psu = "adjust")

# ── load NHANES analysis sets from checkpoints ──
ck_as <- readRDS(file.path(nhanes_u, "checkpoints", "pamob_assemble_nhanes.rds"))
d_nfl <- ck_as$ctx$data$pamob_nhanes_nfl
d_dsst <- ck_as$ctx$data$pamob_nhanes_dsst
cfg_env <- new.env(parent = globalenv())
sys.source("configs/config_pa_mobility_cognitive_batch.R", envir = cfg_env)
bl <- cfg_env$config$pamob
cov1 <- bl$nhanes_covariates_model1
cov2 <- bl$nhanes_covariates_model2
cov3 <- bl$nhanes_covariates_model3

# ════════════════ Table 3 ════════════════
message("=== Rebuild Table 3 ===")
cont <- c("Age", "BMI", "PIR", "Depression", "CFDDS", "SSSNFL", "eGFR")
catg <- c("Gender", "Race", "Education", "Marital_Status",
          "Smoke", "Alcohol_drinking",
          "Hypertension", "Diabetes", "CHD", "HF", "Stroke")
tab3 <- pamob_baseline_by_phenotype_weighted(
  d_nfl, wt_col = "WTSSNH2Y", continuous = cont, categorical = catg
)
print(tab3[1:12, ])
pamob_write_csv(tab3, file.path(nhanes_u, "Tables", "Table 3. NHANES baseline by phenotype.csv"))

# ════════════════ Table 4 (refit + P) ════════════════
message("=== Rebuild Table 4 ===")
.fit_svy <- function(d, y, wt, models, outcome_lab) {
  d <- d[!is.na(d[[y]]) & !is.na(d$phenotype) & !is.na(d[[wt]]) & d[[wt]] > 0, ]
  d$phenotype <- stats::relevel(
    factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
    ref = "Active_preserved"
  )
  if (all(c("SDMVPSU", "SDMVSTRA") %in% names(d))) {
    des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                             weights = stats::as.formula(paste0("~", wt)),
                             nest = TRUE, data = d)
  } else {
    des <- survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt)), data = d)
  }
  out <- list()
  for (nm in names(models)) {
    covs <- pamob_resolve_covars(d, models[[nm]])
    out[[nm]] <- pamob_svyglm_coef_tab(des, y, covs, nm, wt, nrow(d))
    out[[nm]]$outcome <- outcome_lab
  }
  do.call(rbind, out)
}

# DSST: prefer NfL-weight sample with CFDDS (same as main Table4)
d_ds <- d_dsst
if (!"WT_USE" %in% names(d_ds)) {
  if ("WTSSNH2Y" %in% names(d_ds) && any(d_ds$WTSSNH2Y > 0, na.rm = TRUE)) {
    d_ds$WT_USE <- d_ds$WTSSNH2Y
    wt_ds <- "WT_USE"
  } else {
    d_ds$WT_USE <- d_ds$WTMEC2YR
    wt_ds <- "WT_USE"
  }
} else wt_ds <- "WT_USE"

# Use same analytic sample as published Table4 if checkpoint exists
ck_ds <- file.path(nhanes_u, "checkpoints", "pamob_svy_dsst.rds")
if (file.exists(ck_ds)) {
  d_ds <- readRDS(ck_ds)$ctx$results$pamob_svy_dsst$data
  wt_ds <- if ("WT_USE" %in% names(d_ds)) "WT_USE" else "WTSSNH2Y"
}
ck_nf <- file.path(nhanes_u, "checkpoints", "pamob_svy_nfl.rds")
if (file.exists(ck_nf)) {
  d_nfl <- readRDS(ck_nf)$ctx$results$pamob_svy_nfl$data
}

mod_ds <- list(Model0 = character(0), Model1 = cov1, Model2 = cov2, Model3 = cov3)
tab_ds <- .fit_svy(d_ds, "CFDDS", wt_ds, mod_ds, "DSST")
mod_nf <- list(
  Model0 = character(0), Model1 = cov1, Model2 = cov2, Model3 = cov3,
  Model3_eGFR = unique(c(cov3, "eGFR"))
)
tab_nf <- .fit_svy(d_nfl, "ln_SSSNFL", "WTSSNH2Y", mod_nf, "log_sNfL")
tab4 <- rbind(tab_ds, tab_nf)
# sanity: Model3 phenotype P
print(tab4[tab4$model == "Model3" & grepl("^phenotype", tab4$term),
           c("outcome", "term", "estimate", "std.error", "p.value")])
pamob_write_csv(tab4, file.path(nhanes_u, "Tables", "Table 4. NHANES DSST and NfL regressions.csv"))
# also refresh NHANES subfolder copy used by some scripts
pamob_write_csv(tab_ds, file.path(nhanes_u, "Tables", "NHANES", "Table_Pamob_NHANES_DSST.csv"))

# ════════════════ Figure 4 + CLD ════════════════
message("=== Rebuild Figure 4 with ABC ===")
cov_ds <- pamob_resolve_covars(d_ds, cov3)
cov_nf <- unique(c(pamob_resolve_covars(d_nfl, cov3), pamob_resolve_covars(d_nfl, "eGFR")))
m1 <- pamob_svy_adjusted_means(d_ds, "CFDDS", wt_ds, cov_ds, add_cld = TRUE)
m1$panel <- "DSST"
m2 <- pamob_svy_adjusted_means(d_nfl, "ln_SSSNFL", "WTSSNH2Y", cov_nf, add_cld = TRUE)
# letters from log-scale; display geometric mean
m2$se <- exp(m2$mean) * m2$se
m2$mean <- exp(m2$mean)
m2$panel <- "sNfL geometric mean"
plot_df <- rbind(m1, m2)
print(plot_df[, c("panel", "phenotype", "mean", "se", "cld")])
pamob_write_csv(plot_df, file.path(nhanes_u, "Tables", "NHANES", "Table_Pamob_Fig4_Means.csv"))

fig_u <- file.path(nhanes_u, "Figures")
dir.create(fig_u, recursive = TRUE, showWarnings = FALSE)
pdf4 <- file.path(fig_u, "Figure 4. NHANES DSST and NfL panel.pdf")
pamob_draw_fig4_panel(plot_df, pdf4)
# also under pdf/ if export expects
dir.create(file.path(fig_u, "pdf"), recursive = TRUE, showWarnings = FALSE)
file.copy(pdf4, file.path(fig_u, "pdf", basename(pdf4)), overwrite = TRUE)

# collect to batch Figures + 四目录
coll <- pamob_collect_main_figures(batch)
export_pub_figures(coll$figures_dir, config = cfg_env$config)

# ════════════════ republish Table 3 / 4 xlsx (keep other S tables) ════════════════
message("=== Write Table 3/4 xlsx ===")
# Preserve other xlsx: only replace T3 T4
t3_pub <- pamob_format_baseline_pub(tab3, drop_vars = c("Age_anal", "CRP"),
                                    drop_missing_level = FALSE)
pamob_write_sci_xlsx(
  t3_pub,
  file.path(tab_root, "Table 3. NHANES baseline characteristics by PA-mobility phenotype.xlsx"),
  title = "Table 3. NHANES survey-weighted baseline characteristics by PA\u2013mobility phenotype",
  footnotes = c(
    "NHANES 2013\u20132014 (Cycle H), age 60\u201375 years; NfL analytic sample with WTSSNH2Y.",
    "Continuous: survey-weighted mean (SE). Categorical: weighted % (SE) among non-missing.",
    "Phenotype definitions parallel CHARLS. Unweighted n in column headers.",
    "Lonely PSU handled with survey.lonely.psu = adjust. Regression estimates: Table 4; Model3-adjusted means: Figure 4."
  )
)

t4_keep <- grepl("^phenotype", tab4$term)
t4_mod <- tab4$model %in% c("Model0", "Model1", "Model2", "Model3")
t4_pub <- pamob_format_coef_pub(
  tab4[t4_mod & t4_keep, , drop = FALSE],
  outcome_col = "outcome"
)
# map outcome labels
if ("Outcome" %in% names(t4_pub)) {
  t4_pub$Outcome <- ifelse(t4_pub$Outcome == "DSST", "DSST",
                           ifelse(t4_pub$Outcome == "log_sNfL", "log(sNfL)", t4_pub$Outcome))
}
pamob_write_sci_xlsx(
  t4_pub,
  file.path(tab_root, "Table 4. NHANES survey-weighted regressions for DSST and sNfL.xlsx"),
  title = "Table 4. NHANES survey-weighted regressions for DSST and serum NfL",
  footnotes = c(
    "Complex survey design with WTSSNH2Y (NfL) / corresponding DSST weights; strata SDMVSTRA, PSU SDMVPSU.",
    "Reference phenotype: Active\u2013preserved. Coefficients are phenotype contrasts vs reference.",
    "DSST models use available DSST sample; sNfL models use log(serum NfL) in the weighted NfL analytic sample.",
    "Model 1: age, sex, race. Model 2: + SES. Model 3: + lifestyle/comorbidity/depression.",
    "When survey residual df is non-positive, P values use a normal approximation to the Wald statistic.",
    "\u03b2 = survey-weighted estimate; SE = design-based standard error."
  )
)

message("DONE")
message("Fig4: ", pdf4)
message("T3 empty cells check:")
print(colSums(tab3 == "" | is.na(tab3)))
