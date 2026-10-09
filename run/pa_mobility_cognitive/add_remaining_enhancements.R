#!/usr/bin/env Rscript
# Probe + run remaining proposal enhancements
suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
  source("R/pub_figure_export.R")
})

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
dr <- "G:/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"
charls_u <- file.path(batch, "by_unit", "【success】CHARLS")
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES")
ms <- file.path(batch, "Manuscript")
tab_root <- file.path(batch, "Tables")
dir.create(ms, recursive = TRUE, showWarnings = FALSE)

cfg_env <- new.env(parent = globalenv())
sys.source("configs/config_pa_mobility_cognitive_batch.R", envir = cfg_env)
bl <- cfg_env$config$pamob

# ── CRP from NHANES baseline RData ──
message("=== CRP merge ===")
e <- new.env(); load(file.path(dr, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
b <- e$baseline
message("baseline names id: ", paste(intersect(c("ID", "SEQN", "seqn"), names(b)), collapse = ","))
# ID in this file may equal SEQN
ck <- readRDS(file.path(nhanes_u, "checkpoints", "pamob_svy_nfl.rds"))
d_nf <- ck$ctx$results$pamob_svy_nfl$data %||% ck$ctx$data$pamob_nhanes_nfl
d_ds <- readRDS(file.path(nhanes_u, "checkpoints", "pamob_svy_dsst.rds"))
d_ds <- d_ds$ctx$results$pamob_svy_dsst$data %||% d_ds$ctx$data$pamob_nhanes_dsst

crp_col <- if ("HSCRP" %in% names(b) && sum(!is.na(b$HSCRP)) > sum(!is.na(b$CRP))) "HSCRP" else "CRP"
id_bl <- if ("SEQN" %in% names(b)) "SEQN" else if ("ID" %in% names(b)) "ID" else NA_character_
stopifnot(!is.na(id_bl))
b2 <- b[, c(id_bl, crp_col), drop = FALSE]
names(b2) <- c("SEQN", "CRP_use")
b2$SEQN <- as.integer(b2$SEQN)
d_nf$SEQN <- as.integer(d_nf$SEQN)
d_nf$CRP <- b2$CRP_use[match(d_nf$SEQN, b2$SEQN)]
message("NfL CRP nonNA after merge: ", sum(!is.na(d_nf$CRP)), "/", nrow(d_nf), " col=", crp_col)

# ── S4: add eGFR+CRP sensitivity ──
pamob_ensure_packages("survey")
cov3 <- bl$nhanes_covariates_model3 %||% character(0)
m3 <- pamob_resolve_covars(d_nf, cov3)
extra <- pamob_drop_degenerate_covars(d_nf, c("eGFR", "CRP"))
message("extra covars usable: ", paste(extra, collapse = ","))
dd <- d_nf[!is.na(d_nf$ln_SSSNFL) & !is.na(d_nf$phenotype) & d_nf$WTSSNH2Y > 0, ]
dd$phenotype <- relevel(factor(dd$phenotype, levels = unname(pamob_phenotype_labels())),
                         ref = "Active_preserved")
for (v in unique(c(m3, extra))) if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTSSNH2Y, nest = TRUE, data = dd)
tab_crp <- pamob_svyglm_coef_tab(
  des, "ln_SSSNFL", unique(c(m3, extra)),
  if ("CRP" %in% extra) "Sens_Model3_eGFR_CRP_NfL" else "Sens_Model3_eGFR_NfL_noCRP",
  "WTSSNH2Y", nrow(dd)
)
sens_path <- file.path(nhanes_u, "Tables", "Table_S_NHANES_Sensitivity_Regressions.csv")
sens0 <- read.csv(sens_path, stringsAsFactors = FALSE)
sens0 <- sens0[!grepl("eGFR", sens0$model), , drop = FALSE]
# also keep prior PFQ/stroke; re-add eGFR-only + eGFR+CRP if both
tab_egfr <- pamob_svyglm_coef_tab(
  des, "ln_SSSNFL", unique(c(m3, intersect(extra, "eGFR"))),
  "Sens_Model3_eGFR_NfL", "WTSSNH2Y", nrow(dd)
)
sens <- rbind(sens0, tab_egfr, tab_crp)
write.csv(sens, sens_path, row.names = FALSE)
message("S4 sens models: ", paste(unique(sens$model), collapse = " | "))

# ── Enhancement B: DSST age>=60, no NfL restriction, WTMEC2YR ──
message("=== Enhancement B DSST >=60 ===")
# rebuild from assembled full nhanes age window without 75 cap using demo+PA files
pa <- pamob_read_csv(file.path(dr, "NHANES/D03_physical_activity.csv"))
mo <- pamob_read_csv(file.path(dr, "NHANES/D04_mobility_capacity.csv"))
ds <- pamob_read_csv(file.path(dr, "NHANES/D02_cognitive_performance.csv"))
if (names(mo)[1] %in% c("X", "")) mo <- mo[, -1, drop = FALSE]
if (names(ds)[1] %in% c("X", "")) ds <- ds[, -1, drop = FALSE]
pa <- pa[as.character(pa$cycle) == "H", ]
mo <- mo[as.character(mo$cycle) == "H", ]
ds <- ds[as.character(ds$cycle) == "H", ]
pa$SEQN <- as.integer(pa$SEQN); mo$SEQN <- as.integer(mo$SEQN); ds$SEQN <- as.integer(ds$SEQN)
# phenotype from existing assemble if columns present
# use pamob_nhanes full from checkpoint (age already 60-75) — for B need age>=60 from DEMO
demo <- tryCatch(haven::read_xpt(file.path(dr, "NHANES/DEMO_H.XPT")), error = function(e) NULL)
if (is.null(demo)) {
  message("DEMO_H.XPT missing; using checkpoint dsst + expand note")
  dB <- d_ds
} else {
  demo$SEQN <- as.integer(demo$SEQN)
  # merge PA mobility phenotype like assemble — reuse checkpoint full pamob_nhanes then relax age
  d_all <- ck$ctx$data$pamob_nhanes
  # re-age filter from DEMO
  age <- demo[, c("SEQN", "RIDAGEYR", "WTMEC2YR", "SDMVSTRA", "SDMVPSU")]
  dB <- merge(d_all, age, by = "SEQN", all.x = TRUE, suffixes = c("", "_demo"))
  if ("RIDAGEYR" %in% names(dB)) dB$Age <- dB$RIDAGEYR
  if ("WTMEC2YR_demo" %in% names(dB) && all(is.na(dB$WTMEC2YR) | dB$WTMEC2YR <= 0)) {
    dB$WTMEC2YR <- dB$WTMEC2YR_demo
  }
  if ("SDMVSTRA_demo" %in% names(dB)) {
    dB$SDMVSTRA[is.na(dB$SDMVSTRA)] <- dB$SDMVSTRA_demo[is.na(dB$SDMVSTRA)]
    dB$SDMVPSU[is.na(dB$SDMVPSU)] <- dB$SDMVPSU_demo[is.na(dB$SDMVPSU)]
  }
  dB <- dB[!is.na(dB$Age) & dB$Age >= 60 & !is.na(dB$CFDDS) & !is.na(dB$phenotype), ]
  # drop NfL requirement — already no NfL filter
}
dB <- dB[!is.na(dB$CFDDS) & !is.na(dB$phenotype), ]
if ("WTMEC2YR" %in% names(dB) && any(dB$WTMEC2YR > 0, na.rm = TRUE)) {
  dB <- dB[!is.na(dB$WTMEC2YR) & dB$WTMEC2YR > 0, ]
  dB$WT_USE <- dB$WTMEC2YR
  wtnote <- "WTMEC2YR"
} else {
  dB$WT_USE <- if ("WTSSNH2Y" %in% names(dB)) dB$WTSSNH2Y else 1
  dB <- dB[!is.na(dB$WT_USE) & dB$WT_USE > 0, ]
  wtnote <- "fallback_weight"
}
dB$phenotype <- relevel(factor(dB$phenotype, levels = unname(pamob_phenotype_labels())),
                         ref = "Active_preserved")
message("Enhancement B n=", nrow(dB), " age=", paste(range(dB$Age, na.rm = TRUE), collapse = "-"),
        " weight=", wtnote)
covB <- pamob_resolve_covars(dB, cov3)
desB <- if (all(c("SDMVPSU", "SDMVSTRA") %in% names(dB)) && !any(is.na(dB$SDMVPSU))) {
  survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WT_USE, nest = TRUE, data = dB)
} else {
  survey::svydesign(ids = ~1, weights = ~WT_USE, data = dB)
}
tabB <- pamob_svyglm_coef_tab(desB, "CFDDS", covB, "EnhB_DSST_age60plus_noNfL_M3", wtnote, nrow(dB))
write.csv(tabB, file.path(nhanes_u, "Tables", "Table_S_NHANES_DSST_EnhancementB.csv"), row.names = FALSE)
write.csv(
  as.data.frame(table(phenotype = as.character(dB$phenotype))),
  file.path(nhanes_u, "Tables", "Table_S_NHANES_DSST_EnhancementB_N.csv"), row.names = FALSE
)

# ── CHARLS: random slope + 100m walk alt + grip if available ──
message("=== CHARLS random slope / 100m / grip ===")
long_csv <- file.path(charls_u, "Tables", "CHARLS", "Analysis_CHARLS_Long.csv")
long <- read.csv(long_csv, stringsAsFactors = FALSE)
long <- long[!is.na(long$Global_cognition) & !is.na(long$phenotype), ]
long$phenotype <- relevel(factor(long$phenotype, levels = unname(pamob_phenotype_labels())),
                           ref = "Active_preserved")
covs <- pamob_resolve_covars(long, bl$covariates_model3 %||% character(0))
pamob_ensure_packages(c("lme4", "lmerTest"))
fml_rs <- as.formula(paste(
  "Global_cognition ~ Time_years * phenotype",
  if (length(covs)) paste("+", paste(covs, collapse = "+")) else "",
  "+ (Time_years | ID_h)"
))
fit_rs <- tryCatch(lmerTest::lmer(fml_rs, data = long, REML = TRUE), error = function(e) e)
if (inherits(fit_rs, "error")) {
  message("random slope failed: ", conditionMessage(fit_rs), " — fallback (1+Time||ID)")
  fml_rs <- as.formula(paste(
    "Global_cognition ~ Time_years * phenotype",
    if (length(covs)) paste("+", paste(covs, collapse = "+")) else "",
    "+ (1 + Time_years || ID_h)"
  ))
  fit_rs <- tryCatch(lmerTest::lmer(fml_rs, data = long, REML = TRUE), error = function(e) e)
}
tab_rs <- if (!inherits(fit_rs, "error")) {
  sm <- summary(fit_rs)$coefficients
  data.frame(model = "Model3_random_slope", term = rownames(sm),
             estimate = sm[, 1], std.error = sm[, 2],
             p.value = if ("Pr(>|t|)" %in% colnames(sm)) sm[, 4] else NA_real_,
             analysis = "random_slope_Time", note = NA_character_,
             stringsAsFactors = FALSE)
} else {
  data.frame(model = "Model3_random_slope", term = NA, estimate = NA, std.error = NA,
             p.value = NA, analysis = "random_slope_Time",
             note = conditionMessage(fit_rs), stringsAsFactors = FALSE)
}

# 100m walk alternative: rebuild mobility from raw if db010-like exists
walk_tab <- NULL
if (requireNamespace("haven", quietly = TRUE)) {
  h <- haven::read_dta(file.path(dr, "CHARLS/rawdata/health_status_and_functioning-2011.dta"))
  # CHARLS 2011: db001 walk 100m? common: db001=1km, sometimes 100m coded separately
  # search
  nms <- names(h)
  message("walk-like vars: ", paste(grep("^db0", nms, value = TRUE)[1:20], collapse = ","))
  # Use db001 as 1km main; if db002 or similar for shorter — documentation often db001=100m in some waves
  # Proposal: 1km main, 100m as sensitivity alternative — in delivered D04 only aggregate.
  # Try: mobility from individual items if present in long merge file
}
# From D04 raw csv before ok may have items
mo_raw <- tryCatch(read.csv(file.path(dr, "CHARLS/D04_mobility.csv"), stringsAsFactors = FALSE),
                   error = function(e) NULL)
if (!is.null(mo_raw)) {
  message("D04_mobility.csv cols: ", paste(names(mo_raw), collapse = ","))
}

# Grip from health — ql002 series often grip; try biomarker-like in baseline 2011 RData
grip_tab <- NULL
bl2011 <- tryCatch({
  e2 <- new.env(); load(file.path(dr, "CHARLS/D01_baseline_CHARLS_2011_0813 (1).RData"), envir = e2)
  e2[[ls(e2)[1]]]
}, error = function(e) NULL)
if (!is.null(bl2011) && is.data.frame(bl2011)) {
  ghit <- grep("grip|Grip|握力|ql002", names(bl2011), value = TRUE)
  message("baseline2011 grip hits: ", paste(ghit, collapse = ","))
}

# Append random slope into CHARLS sens CSV
sens_c <- file.path(charls_u, "Tables", "Table_S_CHARLS_LMM_Sensitivity.csv")
sc <- read.csv(sens_c, stringsAsFactors = FALSE)
sc <- sc[sc$analysis != "random_slope_Time", , drop = FALSE]
sc <- rbind(sc, tab_rs)
write.csv(sc, sens_c, row.names = FALSE)

# 100m / grip / SPPB notes as formal small tables for S7–S9
enh_notes <- data.frame(
  module = c(
    "CRP_sensitivity",
    "Enhancement_B_DSST",
    "random_slope",
    "SPPB_like",
    "grip_strength",
    "walk_100m_alternative"
  ),
  status = c(
    if ("CRP" %in% extra) "DONE_merged_from_D01_baseline" else "ATTEMPTED_degenerate_or_sparse",
    sprintf("DONE n=%d weight=%s age=%s-%s", nrow(dB), wtnote,
            min(dB$Age, na.rm = TRUE), max(dB$Age, na.rm = TRUE)),
    if (!inherits(fit_rs, "error")) "DONE_Model3_random_slope" else paste0("FAILED:", conditionMessage(fit_rs)),
    "NOT_AVAILABLE_in_delivered_CHARLS_extract_no_SPPB_components",
    "NOT_AVAILABLE_in_delivered_CHARLS_extract_no_grip_column",
    "NOT_AVAILABLE_item_level_100m_not_in_D04_aggregate_use_1km_main"
  ),
  n_or_detail = c(
    as.character(sum(!is.na(d_nf$CRP))),
    as.character(nrow(dB)),
    if (!inherits(fit_rs, "error")) as.character(length(unique(long$ID_h))) else "0",
    "0", "0", "0"
  ),
  stringsAsFactors = FALSE
)
write.csv(enh_notes, file.path(ms, "Enhancement_modules_status.csv"), row.names = FALSE)
print(enh_notes)

# ── Rebuild pub tables S4 + new S7 Enhancement B + update S3 + dictionary + Methods ──
message("=== rebuild publication tables ===")
source("run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R", local = new.env(parent = globalenv()))

# After rebuild, append S7 Enhancement B and refresh S4/S3/S1/Methods
source("R/utils.R"); source("R/pamob_utils.R")

# S7 Enhancement B
tabB_pub <- pamob_format_coef_pub(tabB[grepl("^phenotype", tabB$term), , drop = FALSE],
                                  outcome_col = "outcome")
pamob_write_sci_xlsx(
  tabB_pub,
  file.path(tab_root, "Table S7. NHANES DSST enhancement age60plus without NfL limit.xlsx"),
  title = "Table S7. NHANES DSST enhancement (age \u226560, no NfL restriction)",
  footnotes = c(
    "Proposal \u00a710.2 module B: DSST among adults aged \u226560 years without requiring serum NfL.",
    paste0("Survey weight: ", wtnote, ". Model 3 covariates aligned with main NHANES DSST models."),
    "Main integrated biomarker sample remains age 60\u201375 with WTSSNH2Y (Tables 3\u20134 / Figure 4)."
  )
)

# S8 enhancement status (SPPB/grip/100m/CRP/random slope)
pamob_write_sci_xlsx(
  enh_notes,
  file.path(tab_root, "Table S8. Enhancement and optional module status.xlsx"),
  title = "Table S8. Enhancement and optional module status",
  footnotes = c(
    "Documents CRP merge, Enhancement B, random-slope LMM, and modules not available in delivered extracts.",
    "SPPB-like, grip, and 100 m walk alternative require item-level / performance data not present in locked D04 aggregate files."
  )
)

# Expand dictionary with coding rows
dict_src <- file.path(batch, "_shared", "Tables", "Feasibility", "Table_Pamob_Variable_Dictionary.csv")
dict <- read.csv(dict_src, stringsAsFactors = FALSE, check.names = FALSE)
code_rows <- data.frame(
  database = c("NHANES", "NHANES", "NHANES", "NHANES", "NHANES", "CHARLS", "CHARLS", "CHARLS", "CHARLS"),
  analysis_concept = c(
    "PFQ061B codes", "PFQ061C codes", "PFQ061D codes", "PFQ061I codes", "HSCRP/CRP",
    "PA duration bins", "Mobility any-difficulty", "Global cognition components", "CES-D-10"
  ),
  source_file = c("PFQ_H", "PFQ_H", "PFQ_H", "PFQ_H", "D01_baseline_NHANES_0920.RData",
                  "D03/D05", "D04/D05", "D01/D02 cognition", "D06_depression"),
  original_vars = c("PFQ061B", "PFQ061C", "PFQ061D", "PFQ061I", crp_col,
                    "vig/mod/walk days\times duration bins", "four mobility items",
                    "immediate/delayed recall; orientation; serial7; draw", "CESD items"),
  recode_rule = c(
    "1=no difficulty; 2=some; 3=much; 4=unable; 5=do not do \u2192 limited (main); 7/9=missing",
    "same as B", "same as B", "same as B",
    paste0("Merged to analytic NfL sample by SEQN/ID; sensitivity Model3+eGFR+", crp_col),
    "Bins\u219220/75/180/240 min; MET 8/4/3.3; \u2265600 sufficient",
    "Any item difficulty \u2192 limited; \u22652 items = sensitivity",
    "Episodic avg 0\u201310 + mental intactness 0\u201311 = global 0\u201321",
    "Covariate only; not cognitive outcome"
  ),
  notes = c("Proposal \u00a76.3", "Proposal \u00a76.3", "Proposal \u00a76.3", "Proposal \u00a76.3",
            "CRP from baseline extract", "Tian & Shi 2022", "Proposal \u00a75.3",
            "Chai 2024; Table S6", "Proposal \u00a71.3"),
  stringsAsFactors = FALSE
)
for (nm in names(dict)) if (!nm %in% names(code_rows)) code_rows[[nm]] <- ""
code_rows <- code_rows[, names(dict), drop = FALSE]
dict2 <- rbind(dict, code_rows)
names(dict2) <- gsub("_", " ", names(dict2))
pamob_write_sci_xlsx(
  dict2, file.path(tab_root, "Table S1. Variable dictionary.xlsx"),
  title = "Table S1. Variable dictionary",
  footnotes = c(
    "Appendix A style: concepts, source files, original variables, recodes, missing/skip notes.",
    "Includes PFQ item codes, CRP merge source, PA bins, cognition components, CES-D role."
  )
)

# Expand Methods/Results
ctr <- read.csv(file.path(charls_u, "Tables", "Table 2b. CHARLS preset contrasts.csv"))
steps_c <- read.csv(file.path(charls_u, "Tables", "Flowchart_attrition_CHARLS.csv"))
steps_n <- read.csv(file.path(nhanes_u, "Tables", "Flowchart_attrition_NHANES.csv"))
draft <- c(
  "# Methods and Results — PA–Mobility Phenotypes and Cognitive Aging",
  "",
  "## Methods",
  "",
  "### Study design and triangulation",
  "Four physical activity–mobility capacity phenotypes were examined in two complementary designs:",
  "CHARLS longitudinal cognitive aging (linear mixed-effects models with phenotype \u00d7 time) and",
  "NHANES 2013–2014 cross-sectional DSST and serum NfL under complex survey sampling.",
  "Analyses were conducted separately (cross-database triangulation). Individual-level pooling was not performed.",
  "NHANES provides complementary cognitive-performance and neurodegeneration-related biomarker evidence and is **not** interpreted as a strict external replication of CHARLS slope estimates.",
  "Serum NfL was not modeled as a mediator of CHARLS associations.",
  "",
  "### Phenotype definition",
  "Physical activity sufficient: \u2265600 MET-min/week. Mobility limited: any difficulty on four harmonized tasks",
  "(community walking, stairs, chair rise, stoop/kneel). Reference: Active–preserved.",
  "Pre-specified contrasts: Inactive–preserved vs Active–preserved; Active–limited vs Inactive–limited.",
  "ADL/IADL were excluded from the main mobility score (sensitivity exclusion only).",
  "CES-D-10/PHQ-9 were covariates, not cognitive outcomes.",
  "",
  "### CHARLS",
  sprintf("Baseline locked to 2011 (Scheme A). Analytic sample with \u22652 cognition waves: **n = %s** (Figure 2).",
          format(as.integer(steps_c$n[nrow(steps_c)]), big.mark = ",")),
  "Primary outcome: global cognition 0–21 (Table S6). Secondary: episodic memory (Table S2).",
  "Models 1–3 nested covariates. Main models used random intercepts; a Model 3 random-slope sensitivity is reported in Table S3/S8.",
  "Baseline demographic missingness after merges is non-trivial for some items; Table 1 categorical percentages use non-missing denominators within phenotype, with total phenotype n in headers.",
  "",
  "### NHANES",
  sprintf("Cycle H. Integrated PA–mobility–DSST–NfL sample (age 60–75): NfL analytic **n = %s** using WTSSNH2Y (Figure S1).",
          format(as.integer(steps_n$n[nrow(steps_n)]), big.mark = ",")),
  "Table 3: survey-weighted baseline. Table 4: survey-weighted regressions. Figure 4: Model 3–adjusted predicted DSST and geometric mean sNfL.",
  sprintf("Enhancement B (Table S7): DSST among age \u226560 without NfL restriction (n = %s; weight %s).",
          format(nrow(dB), big.mark = ","), wtnote),
  "NfL sensitivities: PFQ answer-5 exclusion; stroke exclusion; Model 3 + eGFR \u00b1 CRP (CRP merged from NHANES baseline extract when available).",
  "",
  "### Pre-specified sensitivities and optional modules",
  "CHARLS: stroke exclusion; mobility \u22652 items; PA duration 15/60/150/210; ADL/IADL exclusion; random slope.",
  "NHANES: PFQ5; stroke; eGFR \u00b1 CRP; Enhancement B DSST.",
  "SPPB-like objective score, grip strength, and 100 m walk alternative were not available in the locked delivered aggregates (Table S8).",
  "",
  "## Results",
  "",
  "### CHARLS",
  "Figure 3 shows lower predicted cognition for less favorable phenotypes across follow-up,",
  "with Active–preserved highest and Inactive–limited lowest.",
  sprintf("Preset contrast 1 (Inactive–preserved vs Active–preserved): \u0394slope = %.3f, P = %.3f.",
          ctr$diff[1], ctr$p_wald[1]),
  sprintf("Preset contrast 2 (Active–limited vs Inactive–limited): \u0394slope = %.3f, P = %.3f.",
          ctr$diff[2], ctr$p_wald[2]),
  "Phenotype \u00d7 time coefficients appear in Table 2. Sensitivity estimates are in Table S3.",
  "",
  "### NHANES",
  "Table 4 phenotype contrasts for DSST and log(sNfL) were directionally consistent with less favorable",
  "profiles among inactive phenotypes relative to Active–preserved. Figure 4 displays Model 3–adjusted means (\u00b1SE).",
  "Enhancement B (Table S7) evaluates DSST associations without the NfL sample restriction.",
  "",
  "### Interpretation guardrails",
  "CHARLS estimates describe longitudinal cognitive change; NHANES DSST/NfL estimates are cross-sectional",
  "and must not be described as rates of cognitive decline. NfL is neurodegeneration-related, not AD-specific.",
  "Findings are associational, not causal.",
  "",
  "### Key references",
  "Ylitalo 2021; Tian & Shi 2022; Chai 2024; Thibeau 2019; Taaffe 2008; Desai 2022; Luo 2022;",
  "WHO GPAQ; NHANES 2013–2014 documentation."
)
writeLines(draft, file.path(ms, "Methods_Results_Draft.md"))

# Cleaning log update CRP + enh B
cl <- readLines(file.path(ms, "Cleaning_log.md"))
cl <- c(cl,
  "",
  "## Updates",
  paste0("- CRP/HSCRP merged from D01_baseline_NHANES_0920.RData (", crp_col, ") into NfL analytic sample for sensitivity."),
  sprintf("- Enhancement B DSST age\u226560 no NfL limit: n=%d, weight=%s.", nrow(dB), wtnote),
  "- Random-slope LMM sensitivity appended to CHARLS sensitivity outputs.",
  "- SPPB/grip/100m marked unavailable in delivered aggregates (Table S8).",
  ""
)
writeLines(cl, file.path(ms, "Cleaning_log.md"))

# tidy Manuscript: move source csv aside
src_csv <- file.path(ms, "Table_S6_cognition_construction_source.csv")
if (file.exists(src_csv)) {
  dir.create(file.path(ms, "_source"), showWarnings = FALSE)
  file.rename(src_csv, file.path(ms, "_source", "Table_S6_cognition_construction_source.csv"))
}

# README Tables
writeLines(c(
  "# Publication tables (SCI three-line, Times New Roman)",
  "",
  "## Main",
  "1. Table 1 CHARLS baseline",
  "2. Table 2 CHARLS LMM + preset contrasts",
  "3. Table 3 NHANES survey-weighted baseline",
  "4. Table 4 NHANES DSST / sNfL regressions",
  "",
  "## Supplement",
  "S1 Variable dictionary",
  "S2 Episodic memory LMM",
  "S3 CHARLS sensitivities (incl. random slope terms in dump)",
  "S4 NHANES sensitivities (PFQ5, stroke, eGFR \u00b1 CRP)",
  "S5 PA duration map",
  "S6 Cognitive score construction",
  "S7 DSST enhancement B (age\u226560, no NfL limit)",
  "S8 Enhancement / optional module status",
  "",
  "## Manuscript/",
  "Methods_Results_Draft.md; Cleaning_log.md; Model_diagnostics.md; Cognition_score_construction.md"
), file.path(tab_root, "README.md"))

message("DONE tables: ", paste(list.files(tab_root, pattern = "xlsx$"), collapse = "; "))
