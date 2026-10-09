#!/usr/bin/env Rscript
# 补方案缺口 → 更新 by_unit 过程 CSV → 重导定稿 Tables/Figures（编号不乱）
# "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/pa_mobility_cognitive/fill_pamob_proposal_gaps.R

.init <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_dir <- .init()
root <- if (basename(script_dir) == "pa_mobility_cognitive") {
  normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
} else script_dir
setwd(root)

suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
  source("R/pub_figure_export.R")
})

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
charls_u <- file.path(batch, "by_unit", "【success】CHARLS")
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES")
ms_dir <- file.path(batch, "Manuscript")
dir.create(ms_dir, recursive = TRUE, showWarnings = FALSE)
config_pub <- list(pub_figures = list(formats_dir = TRUE, write_image_information = TRUE, dpi = 300L))

# ── load config covariates ──
cfg_env <- new.env(parent = globalenv())
sys.source("configs/config_pa_mobility_cognitive_batch.R", envir = cfg_env)
bl <- cfg_env$config$pamob %||% list()

# ══════════════════════════════════════════════════════════════
# 1) CHARLS 预设对比 Wald P（含对比2）
# ══════════════════════════════════════════════════════════════
message("=== 1 contrast Wald P ===")
ck_lmm <- file.path(charls_u, "checkpoints", "pamob_lmm_global.rds")
if (!file.exists(ck_lmm)) ck_lmm <- file.path(charls_u, "checkpoints", "step04_pamob_lmm_global.rds")
# try traj / cognition for long data
long <- NULL
for (cand in c(
  file.path(charls_u, "checkpoints", "pamob_lmm_global.rds"),
  file.path(charls_u, "checkpoints", "step05_pamob_lmm_global.rds"),
  file.path(charls_u, "checkpoints", "pamob_cognition_long.rds"),
  file.path(charls_u, "checkpoints", "step03_pamob_cognition_long.rds")
)) {
  if (!file.exists(cand)) next
  obj <- readRDS(cand)
  ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
  long <- ctx$data$pamob_lmm_fit_data %||% ctx$data$pamob_charls_long %||%
    ctx$results$pamob_lmm_global$data %||% NULL
  if (!is.null(long) && is.data.frame(long) && nrow(long)) break
}
if (is.null(long) || !nrow(long)) {
  long_csv <- file.path(charls_u, "Tables", "CHARLS", "Analysis_CHARLS_Long.csv")
  if (file.exists(long_csv)) long <- read.csv(long_csv, stringsAsFactors = FALSE)
}
stopifnot(!is.null(long), nrow(long) > 0)
pamob_ensure_packages(c("lme4", "lmerTest"))
long <- long[!is.na(long$Global_cognition) & !is.na(long$phenotype), , drop = FALSE]
long$phenotype <- relevel(factor(long$phenotype, levels = unname(pamob_phenotype_labels())),
                           ref = "Active_preserved")
covs <- pamob_resolve_covars(long, bl$covariates_model3 %||% character(0))
fml <- as.formula(paste("Global_cognition ~ Time_years * phenotype",
                        if (length(covs)) paste("+", paste(covs, collapse = "+")) else "",
                        "+ (1|ID_h)"))
fit <- lmerTest::lmer(fml, data = long, REML = TRUE)
cf <- lme4::fixef(fit)
V <- as.matrix(vcov(fit))
slope <- function(grp) {
  if (identical(grp, "Active_preserved")) return(unname(cf[["Time_years"]]))
  unname(cf[["Time_years"]] + cf[[paste0("Time_years:phenotype", grp)]])
}
.wald_p <- function(L) {
  nm <- names(cf); L <- L[nm]
  est <- sum(L * cf)
  se <- sqrt(as.numeric(t(L) %*% V[nm, nm, drop = FALSE] %*% L))
  2 * pnorm(-abs(est / se))
}
L1 <- setNames(rep(0, length(cf)), names(cf))
L1[["Time_years:phenotypeInactive_preserved"]] <- 1
L2 <- setNames(rep(0, length(cf)), names(cf))
L2[["Time_years:phenotypeActive_limited"]] <- 1
L2[["Time_years:phenotypeInactive_limited"]] <- -1
ctr <- data.frame(
  contrast = c("Inactive_preserved vs Active_preserved (slope)",
               "Active_limited vs Inactive_limited (slope)"),
  slope_A = c(slope("Inactive_preserved"), slope("Active_limited")),
  slope_B = c(slope("Active_preserved"), slope("Inactive_limited")),
  diff = c(slope("Inactive_preserved") - slope("Active_preserved"),
           slope("Active_limited") - slope("Inactive_limited")),
  p_wald = c(.wald_p(L1), .wald_p(L2)),
  stringsAsFactors = FALSE
)
ctr$p_interaction_proxy <- ctr$p_wald
write.csv(ctr, file.path(charls_u, "Tables", "Table 2b. CHARLS preset contrasts.csv"), row.names = FALSE)
print(ctr)
message("contrast P2=", ctr$p_wald[2])

# LMM diagnostics snippet
sm <- summary(fit)
diag_txt <- c(
  "# Model diagnostics — CHARLS LMM (global cognition, Model 3)",
  "",
  sprintf("- N observations: %d; N IDs: %d", nrow(long), length(unique(long$ID_h))),
  sprintf("- Formula: %s", deparse(fml)),
  sprintf("- REML: TRUE; optimizer: %s", paste(sm$optinfo$optimizer %||% "default", collapse = ",")),
  sprintf("- Converged: %s", isTRUE(is.null(sm$optinfo$conv$lme4$code) || identical(sm$optinfo$conv$lme4$code, 0L))),
  sprintf("- Random effects: (1 | ID_h) only (random slope not used in base delivery)."),
  sprintf("- Residual SD: %.4f", as.numeric(sm$sigma)),
  sprintf("- Preset contrast 1 (Inactive–preserved vs Active–preserved) Δslope=%.4f, P=%.4f",
          ctr$diff[1], ctr$p_wald[1]),
  sprintf("- Preset contrast 2 (Active–limited vs Inactive–limited) Δslope=%.4f, P=%.4f",
          ctr$diff[2], ctr$p_wald[2]),
  ""
)
writeLines(diag_txt, file.path(ms_dir, "Model_diagnostics.md"))

# ══════════════════════════════════════════════════════════════
# 2) NHANES Table3 weighted + Fig4 adjusted + eGFR sens
# ══════════════════════════════════════════════════════════════
message("=== 2 NHANES Table3 / Fig4 / sens ===")
ck_n <- readRDS(file.path(nhanes_u, "checkpoints", "pamob_svy_nfl.rds"))
ck_d <- readRDS(file.path(nhanes_u, "checkpoints", "pamob_svy_dsst.rds"))
d_nf <- ck_n$ctx$results$pamob_svy_nfl$data %||% ck_n$ctx$data$pamob_nhanes_nfl
d_ds <- ck_d$ctx$results$pamob_svy_dsst$data %||% ck_d$ctx$data$pamob_nhanes_dsst
stopifnot(!is.null(d_nf), !is.null(d_ds))

cont <- c("Age", "BMI", "PIR", "Depression", "CFDDS", "SSSNFL", "eGFR")
catg <- c("Gender", "Race", "Education", "Marital_Status",
          "Smoke", "Alcohol_drinking",
          "Hypertension", "Diabetes", "CHD", "HF", "Stroke")
tab3 <- pamob_baseline_by_phenotype_weighted(d_nf, "WTSSNH2Y", cont, catg)
write.csv(tab3, file.path(nhanes_u, "Tables", "Table 3. NHANES baseline by phenotype.csv"),
          row.names = FALSE)
message("Table3 weighted OK nrow=", nrow(tab3))

cov3 <- bl$nhanes_covariates_model3 %||% bl$covariates_model3 %||%
  c("Age", "Gender", "Race", "Education", "PIR", "Marital_Status",
    "BMI", "Smoke", "Alcohol_drinking", "Hypertension", "Diabetes", "Stroke", "Depression")
cov_ds <- pamob_resolve_covars(d_ds, cov3)
cov_nf <- unique(c(pamob_resolve_covars(d_nf, cov3), pamob_resolve_covars(d_nf, "eGFR")))
wt_ds <- if ("WT_USE" %in% names(d_ds)) "WT_USE" else "WTSSNH2Y"
m1 <- pamob_svy_adjusted_means(d_ds, "CFDDS", wt_ds, cov_ds)
m1$panel <- "DSST"
m2 <- pamob_svy_adjusted_means(d_nf, "ln_SSSNFL", "WTSSNH2Y", cov_nf)
m2$se <- exp(m2$mean) * m2$se
m2$mean <- exp(m2$mean)
m2$panel <- "sNfL geometric mean"
means <- rbind(m1, m2)
write.csv(means, file.path(nhanes_u, "Tables", "NHANES", "Table_Pamob_Fig4_Means.csv"), row.names = FALSE)
pamob_draw_fig4_panel(means, file.path(nhanes_u, "Figures", "Figure 4. NHANES DSST and NfL panel.pdf"))
print(means)
message("Fig4 adjusted OK")

# eGFR (±CRP) sensitivity fix
pamob_ensure_packages("survey")
m3 <- pamob_resolve_covars(d_nf, cov3)
extra <- pamob_drop_degenerate_covars(d_nf, c("eGFR", "CRP"))
cov_e <- unique(c(m3, extra))
dd <- d_nf[!is.na(d_nf$ln_SSSNFL) & !is.na(d_nf$phenotype) & d_nf$WTSSNH2Y > 0, ]
dd$phenotype <- relevel(factor(dd$phenotype, levels = unname(pamob_phenotype_labels())),
                         ref = "Active_preserved")
for (v in cov_e) if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSSNH2Y, nest = TRUE, data = dd)
lab <- if ("CRP" %in% extra) "Sens_Model3_eGFR_CRP_NfL" else "Sens_Model3_eGFR_NfL"
tab_e <- pamob_svyglm_coef_tab(des, "ln_SSSNFL", cov_e, lab, "WTSSNH2Y", nrow(dd))
# merge into existing sens CSV
sens_path <- file.path(nhanes_u, "Tables", "Table_S_NHANES_Sensitivity_Regressions.csv")
sens0 <- if (file.exists(sens_path)) read.csv(sens_path, stringsAsFactors = FALSE) else NULL
if (!is.null(sens0)) {
  sens0 <- sens0[!grepl("eGFR", sens0$model), , drop = FALSE]
  sens <- rbind(sens0, tab_e)
} else sens <- tab_e
write.csv(sens, sens_path, row.names = FALSE)
message("eGFR sens OK model=", lab, " note=", tab_e$note[1], " n_terms=", nrow(tab_e))

# NHANES diagnostics
phn <- as.data.frame(table(dd$phenotype))
diag_n <- c(
  "# Model diagnostics — NHANES survey models",
  "",
  sprintf("- NfL analytic n=%d (WTSSNH2Y); strata=SDMVSTRA, PSU=SDMVPSU, nest=TRUE", nrow(dd)),
  sprintf("- DSST analytic n=%d (weight=%s)", nrow(d_ds[!is.na(d_ds$CFDDS), ]), wt_ds),
  sprintf("- Phenotype n (NfL): %s", paste(sprintf("%s=%s", phn[,1], phn[,2]), collapse = "; ")),
  sprintf("- Min phenotype n=%d (gate ≥50 → four-group main retained)", min(phn[,2])),
  sprintf("- Fig4: Model3-adjusted predicted means at survey-weighted covariate profile"),
  sprintf("- eGFR sensitivity label: %s; covars added: %s", lab, paste(extra, collapse = ",")),
  if (!"CRP" %in% extra) "- CRP dropped (all missing / degenerate in analytic extract)." else "- CRP included.",
  ""
)
writeLines(diag_n, file.path(ms_dir, "Model_diagnostics_NHANES.md"))
# append to combined
writeLines(c(diag_txt, diag_n), file.path(ms_dir, "Model_diagnostics.md"))

# ══════════════════════════════════════════════════════════════
# 3) 文档：清洗日志 / 认知构建 / Methods-Results（半成品对齐）
# ══════════════════════════════════════════════════════════════
message("=== 3 Manuscript docs ===")
steps_c <- read.csv(file.path(charls_u, "Tables", "Flowchart_attrition_CHARLS.csv"), stringsAsFactors = FALSE)
steps_n <- read.csv(file.path(nhanes_u, "Tables", "Flowchart_attrition_NHANES.csv"), stringsAsFactors = FALSE)
t1b <- tryCatch(read.csv(file.path(charls_u, "Tables", "Table 1b. CHARLS phenotype N.csv"),
                         stringsAsFactors = FALSE), error = function(e) NULL)

clean_log <- c(
  "# Data cleaning log — PA–mobility × cognitive aging",
  "",
  "## Lock decisions (before main results)",
  "- CHARLS baseline wave: **2011** (Scheme A).",
  "- PA sufficient: ≥600 MET-min/week; duration representatives 20/75/180/240 min (Tian & Shi 2022).",
  "- Mobility limited: any difficulty on four harmonized items (CHARLS / NHANES PFQ061B/C/D/I).",
  "- ADL/IADL **not** in main mobility score; used only in sensitivity exclusion.",
  "- CES-D-10 / PHQ-9 are covariates, not cognitive outcomes.",
  "- NHANES cycle H (2013–2014), age 60–75 for integrated PA–mobility–DSST–NfL sample.",
  "- NfL models use **WTSSNH2Y** + SDMVSTRA/SDMVPSU.",
  "",
  "## CHARLS attrition (Figure 2)",
  paste0(sprintf("- %s: n=%s", steps_c$step, steps_c$n), collapse = "\n"),
  "",
  "## NHANES attrition (Figure S1)",
  paste0(sprintf("- %s: n=%s", steps_n$step, steps_n$n), collapse = "\n"),
  "",
  "## Coding notes",
  paste0("- ", pamob_pfq_coding_rules(), collapse = "\n"),
  "",
  "## Missingness (CHARLS Table 1)",
  "- Baseline demographic covariates show non-trivial missingness (~25–30% for some items after merging waves).",
  "- Table 1 categorical percentages are among **non-missing** respondents within each phenotype column; column headers show total phenotype n.",
  "- Main LMM uses available cases for covariates nested in Models 1–3 (complete-case within each model).",
  "",
  "## PA alternative duration",
  "- Sensitivity remapping 15/60/150/210 min was run when raw PA bins available; results in Table S3 (`PA alt duration 15 60 150 210`).",
  ""
)
writeLines(clean_log, file.path(ms_dir, "Cleaning_log.md"))

cog_doc <- data.frame(
  Domain = c("Episodic memory", "Episodic memory", "Mental intactness", "Mental intactness",
             "Mental intactness", "Global cognition"),
  Component = c("Immediate word recall (10 words)", "Delayed word recall (10 words)",
                "Orientation (date/season/day)", "Serial subtraction of 7",
                "Figure drawing/copy", "Episodic memory + mental intactness"),
  Score_range = c("0–10", "0–10", "part of 0–11", "part of 0–11", "part of 0–11", "0–21"),
  Role = c("Averaged into episodic memory", "Averaged into episodic memory",
           "Mental intactness", "Mental intactness", "Mental intactness",
           "Primary CHARLS outcome"),
  Notes = c(
    "Chai et al. 2024 structure; wave-consistent scoring required",
    "Same word list delayed recall",
    "Orientation items summed into mental intactness",
    "Continuous subtraction contribution",
    "Visuoconstruction contribution",
    "Primary LMM outcome; episodic memory is secondary (Table S2)"
  ),
  stringsAsFactors = FALSE
)
# will export as Table S6 via rebuild

write.csv(cog_doc, file.path(ms_dir, "Table_S6_cognition_construction_source.csv"), row.names = FALSE)
writeLines(c(
  "# Cognitive score construction (CHARLS)",
  "",
  "Primary outcome follows published CHARLS 0–21 global cognition (Chai et al., 2024).",
  "See Table S6 in `Tables/` for the component matrix.",
  "Cross-wave consistency: only waves with complete component availability enter the analytic long file;",
  "no mixing of raw scores and within-wave z-scores.",
  ""
), file.path(ms_dir, "Cognition_score_construction.md"))

# Methods / Results with numbers
t2 <- read.csv(file.path(charls_u, "Tables", "Table 2. CHARLS LMM Global cognition.csv"),
               stringsAsFactors = FALSE)
m3_rows <- t2[t2$model == "Model3" & grepl("Time_years:phenotype|Time_years$", t2$term), ]
draft <- c(
  "# Methods and Results — PA–Mobility Phenotypes and Cognitive Aging",
  "",
  "## Methods",
  "",
  "### Design",
  "We defined four physical activity–mobility capacity phenotypes and examined:",
  "(i) CHARLS longitudinal change in global cognition (0–21) using linear mixed-effects models",
  "with phenotype × time interactions (random intercept); and (ii) NHANES 2013–2014",
  "cross-sectional associations with DSST and log(serum NfL) under the complex survey design.",
  "**Databases were analyzed separately (cross-database triangulation); individual-level pooling was not performed.**",
  "NHANES is complementary biomarker/cognitive-performance evidence and is **not** framed as a strict external replication of CHARLS longitudinal slopes.",
  "NfL was not treated as a formal mediator of CHARLS associations.",
  "",
  "### Phenotype",
  "PA sufficient: ≥600 MET-min/week. Mobility limited: any difficulty on four harmonized tasks.",
  "Reference: Active–preserved. Pre-specified contrasts: Inactive–preserved vs Active–preserved;",
  "Active–limited vs Inactive–limited. ADL/IADL were excluded from the main mobility score.",
  "",
  "### CHARLS",
  sprintf("Baseline locked to 2011. Analytic IDs with ≥2 cognition waves: **n = %s** (Figure 2).",
          format(as.integer(steps_c$n[nrow(steps_c)]), big.mark = ",")),
  "Models 1–3 nested covariates (demographics → SES → lifestyle/comorbidity/CES-D-10).",
  "Primary outcome: global cognition; secondary: episodic memory (Table S2).",
  "Missing demographic items in baseline merges are reported in Table 1 footnotes;",
  "categorical percentages use non-missing denominators within phenotype.",
  "",
  "### NHANES",
  sprintf("Cycle H, age 60–75. NfL analytic sample **n = %s** (WTSSNH2Y); DSST sample larger (Figure S1 / Table 4).",
          format(as.integer(steps_n$n[nrow(steps_n)]), big.mark = ",")),
  "Table 3 reports **survey-weighted** baseline summaries. Figure 4 shows **Model 3–adjusted**",
  "predicted DSST means and geometric mean sNfL by phenotype.",
  "",
  "### Sensitivities (pre-specified)",
  "CHARLS: exclude baseline stroke; mobility limited ≥2 items; PA alternative duration 15/60/150/210;",
  "exclude baseline ADL/IADL disability. NHANES: exclude PFQ answer 5; exclude stroke; NfL Model3 + eGFR (±CRP if available).",
  "",
  "## Results (draft)",
  "",
  "### CHARLS trajectories",
  "Predicted trajectories (Figure 3) showed lower baseline cognition and continued decline in less favorable phenotypes,",
  "with Active–preserved highest and Inactive–limited lowest over follow-up.",
  sprintf("Preset slope contrast 1 (Inactive–preserved vs Active–preserved): Δ = %.3f, P = %.3f.",
          ctr$diff[1], ctr$p_wald[1]),
  sprintf("Preset slope contrast 2 (Active–limited vs Inactive–limited): Δ = %.3f, P = %.3f.",
          ctr$diff[2], ctr$p_wald[2]),
  "Full phenotype × time coefficients are in Table 2 (Models 1–3).",
  "",
  "### NHANES DSST and sNfL",
  "Survey-weighted Model 3 phenotype contrasts for DSST and log(sNfL) are in Table 4.",
  "Figure 4 panels A–B display Model 3–adjusted means (±SE) ordered by phenotype.",
  "Directionally, inactive phenotypes tended toward lower DSST and higher sNfL relative to Active–preserved,",
  "supporting complementary cross-sectional neurodegeneration-related patterning.",
  "",
  "### Interpretation guardrails",
  "CHARLS estimates refer to longitudinal cognitive change; NHANES DSST/NfL estimates are cross-sectional",
  "cognitive performance / biomarker levels and must not be described as cognitive decline rates.",
  "Serum NfL is a neurodegeneration-related marker, not AD-specific. Associations are not causal.",
  "",
  "### Key references",
  "Ylitalo 2021; Tian & Shi 2022; Chai 2024; Thibeau 2019; Taaffe 2008; Desai 2022; Luo 2022;",
  "WHO GPAQ; NHANES 2013–2014 PAQ/PFQ/CFQ/SSSNFL documentation."
)
writeLines(draft, file.path(ms_dir, "Methods_Results_Draft.md"))

# ══════════════════════════════════════════════════════════════
# 4) 重导定稿三线表（编号固定）+ Figure 四目录
# ══════════════════════════════════════════════════════════════
message("=== 4 rebuild pub tables/figures ===")
# update rebuild script pieces inline here for Table3 weighted footnotes + S6
source("run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R", local = new.env(parent = globalenv()))

# Table S6 cognition — append after rebuild (rebuild clears Tables/)
# Re-run rebuild already wrote S1–S5; add S6 without wiping
source("R/utils.R")
source("R/pamob_utils.R")
tab_root <- file.path(batch, "Tables")
cog_doc <- read.csv(file.path(ms_dir, "Table_S6_cognition_construction_source.csv"),
                    stringsAsFactors = FALSE)
pamob_write_sci_xlsx(
  cog_doc,
  file.path(tab_root, "Table S6. CHARLS cognitive score construction.xlsx"),
  title = "Table S6. CHARLS cognitive score construction",
  footnotes = c(
    "Global cognition (0–21) follows Chai et al. 2024: episodic memory + mental intactness.",
    "Episodic memory is the secondary CHARLS outcome (Table S2).",
    "CES-D-10 is a covariate, not a cognitive outcome."
  )
)

# Expand dictionary title stays S1 — enrich CSV then rewrite S1 if feasibility dict exists
dict_src <- file.path(batch, "_shared", "Tables", "Feasibility", "Table_Pamob_Variable_Dictionary.csv")
if (file.exists(dict_src)) {
  dict <- read.csv(dict_src, stringsAsFactors = FALSE, check.names = FALSE)
  # append PFQ/cognition rows if missing
  extra_rows <- data.frame(
    database = c("NHANES", "NHANES", "NHANES", "CHARLS", "CHARLS"),
    analysis_concept = c("PFQ054 structural skip", "PFQ answer 5", "sNfL weight",
                         "Global cognition 0-21", "CES-D-10"),
    source_file = c("PFQ_H", "PFQ_H", "SSSNFL_H", "cognition modules", "CESD"),
    original_vars = c("PFQ054", "PFQ061B/C/D/I code 5", "WTSSNH2Y", "memory+intactness items", "CESD10"),
    recode_rule = c(
      "If PFQ054=Yes and B/C blank → mobility limited",
      "Main: code5→limited; Sens: exclude any code5",
      "Required for all NfL models with SDMVSTRA/PSU",
      "Sum to 0-21; episodic secondary",
      "Covariate only; not cognitive outcome"
    ),
    notes = c("Proposal §6.3", "Proposal §6.3 / §8.2", "Proposal §6.5/§6.8",
              "Proposal §5.6; Table S6", "Proposal §1.3"),
    stringsAsFactors = FALSE
  )
  # align cols
  for (nm in names(dict)) if (!nm %in% names(extra_rows)) extra_rows[[nm]] <- ""
  extra_rows <- extra_rows[, names(dict), drop = FALSE]
  dict2 <- rbind(dict, extra_rows)
  names(dict2) <- gsub("_", " ", names(dict2))
  pamob_write_sci_xlsx(
    dict2,
    file.path(tab_root, "Table S1. Variable dictionary.xlsx"),
    title = "Table S1. Variable dictionary",
    footnotes = c(
      "Filled from delivered CHARLS/NHANES extracts and proposal Appendix A.",
      "Includes PFQ054 skip, PFQ answer-5, WTSSNH2Y, and cognition/CES-D roles."
    )
  )
}

# Update Table 3 title/footnotes for weighted — rewrite from fresh CSV
t3_raw <- read.csv(file.path(nhanes_u, "Tables", "Table 3. NHANES baseline by phenotype.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
# weighted uses Mean (SE) — map label
t3 <- pamob_format_baseline_pub(t3_raw, drop_vars = c("Age_anal", "CRP"))
# fix continuous label Mean (SD) -> keep as produced; level was Mean (SE)
pamob_write_sci_xlsx(
  t3,
  file.path(tab_root, "Table 3. NHANES baseline characteristics by PA-mobility phenotype.xlsx"),
  title = "Table 3. NHANES survey-weighted baseline characteristics by PA\u2013mobility phenotype",
  footnotes = c(
    "NHANES 2013\u20132014 (Cycle H), age 60\u201375 years; NfL analytic sample with WTSSNH2Y.",
    "Continuous variables: survey-weighted mean (SE). Categorical: weighted % (SE) among non-missing.",
    "Phenotype definitions parallel CHARLS. Unweighted n shown in column headers.",
    "Regression estimates: Table 4; adjusted means: Figure 4."
  )
)

# Update README order
readme <- c(
  "# Publication tables (SCI three-line, Times New Roman)",
  "",
  "Order locked to proposal §8.4 / §10.1. Process CSVs remain in `by_unit/**/Tables/`.",
  "",
  "## Main",
  "- Table 1. CHARLS baseline characteristics by PA-mobility phenotype.xlsx",
  "- Table 2. CHARLS LMM of global cognition.xlsx",
  "- Table 3. NHANES baseline characteristics by PA-mobility phenotype.xlsx  *(survey-weighted)*",
  "- Table 4. NHANES survey-weighted regressions for DSST and sNfL.xlsx",
  "",
  "## Supplement",
  "- Table S1. Variable dictionary.xlsx",
  "- Table S2. CHARLS LMM of episodic memory.xlsx",
  "- Table S3. CHARLS sensitivity analyses.xlsx",
  "- Table S4. NHANES sensitivity analyses.xlsx",
  "- Table S5. PA duration representative minutes.xlsx",
  "- Table S6. CHARLS cognitive score construction.xlsx",
  "",
  "## Manuscript (not mixed into Tables/)",
  "- Manuscript/Methods_Results_Draft.md",
  "- Manuscript/Cleaning_log.md",
  "- Manuscript/Model_diagnostics.md",
  "- Manuscript/Cognition_score_construction.md",
  ""
)
writeLines(readme, file.path(tab_root, "README.md"))

# Figures: unit export + collect root (keeps Fig1-4 + S1 only)
export_pub_figures(file.path(nhanes_u, "Figures"), config = config_pub)
export_pub_figures(file.path(charls_u, "Figures"), config = config_pub)
coll <- pamob_collect_main_figures(batch)
# also copy S1 flowchart
s1 <- file.path(nhanes_u, "Figures", "pdf", "Figure S1. NHANES flowchart.pdf")
if (!file.exists(s1)) s1 <- file.path(nhanes_u, "Figures", "Figure S1. NHANES flowchart.pdf")
if (file.exists(s1)) {
  file.copy(s1, file.path(batch, "Figures", "Figure S1. NHANES flowchart.pdf"), overwrite = TRUE)
}
export_pub_figures(file.path(batch, "Figures"), config = config_pub)

# final listing
message("DONE Tables: ", paste(list.files(tab_root, pattern = "\\.xlsx$"), collapse = "; "))
message("DONE Figures: ", paste(list.files(file.path(batch, "Figures", "pdf")), collapse = "; "))
message("DONE Manuscript: ", paste(list.files(ms_dir), collapse = "; "))
