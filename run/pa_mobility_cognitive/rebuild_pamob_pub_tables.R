#!/usr/bin/env Rscript
# 整理根目录 Tables：只留发表三线表 xlsx（Times New Roman），清掉过程 CSV/垃圾
# "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R

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
})

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
if (!dir.exists(batch)) {
  batch <- "/mnt/g/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
}
charls_u <- file.path(batch, "by_unit", "【success】CHARLS", "Tables")
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES", "Tables")
tab_root <- file.path(batch, "Tables")
dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)

# ── 清空根 Tables 中非定稿文件（过程 CSV / batch 摘要 / 超大明细）──
junk_pat <- paste0(
  "^(Batch_summary|Indicator_availability|Table_Pamob_ADL|Analysis_|",
  "Table 1b\\.|Table 3b\\.|Table 2b\\.|Flowchart_|.*\\.csv$)"
)
old <- list.files(tab_root, full.names = TRUE, recursive = FALSE)
# 先全部删掉根目录平铺文件，再只写 xlsx 定稿
unlink(old)
# 也清掉误放的子目录空壳
old_dirs <- list.dirs(tab_root, recursive = FALSE, full.names = TRUE)
# keep nothing under root Tables except what we write

written <- character(0)

# ── Table 1 CHARLS baseline ──
t1_raw <- read.csv(file.path(charls_u, "Table 1. CHARLS baseline by phenotype.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
t1 <- pamob_format_baseline_pub(t1_raw)
t1_path <- file.path(tab_root, "Table 1. CHARLS baseline characteristics by PA-mobility phenotype.xlsx")
pamob_write_sci_xlsx(
  t1, t1_path,
  title = "Table 1. CHARLS baseline characteristics by PA\u2013mobility phenotype",
  footnotes = c(
    "Values are mean (SD) for continuous variables and n (%) for categorical variables.",
    "Phenotypes: Active\u2013preserved (reference), Inactive\u2013preserved, Active\u2013limited, Inactive\u2013limited.",
    "PA sufficient = \u2265600 MET-min/week; mobility limited = any difficulty on four harmonized tasks.",
    "Categorical percentages use phenotype column N as denominator; (Missing) rows show covariate missingness after baseline merge.",
    "Baseline wave locked to 2011; age \u226545 years. See Table1 missing QC note if demographic complete-case N differs from phenotype N."
  )
)
written <- c(written, basename(t1_path))
message("OK ", basename(t1_path))

# ── Table 2 CHARLS LMM + preset contrasts ──
t2_raw <- read.csv(file.path(charls_u, "Table 2. CHARLS LMM Global cognition.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
t2_keep <- grepl("^(Time_years|phenotype|Time_years:phenotype)", t2_raw$term)
t2_mod <- t2_raw$model %in% c("Model1", "Model2", "Model3")
t2 <- pamob_format_coef_pub(t2_raw[t2_mod & t2_keep, , drop = FALSE])
ctr_path <- file.path(charls_u, "Table 2b. CHARLS preset contrasts.csv")
if (file.exists(ctr_path)) {
  ctr <- read.csv(ctr_path, stringsAsFactors = FALSE)
  ctr_g <- ctr[ctr$outcome == "Global_cognition" | is.null(ctr$outcome) | is.na(ctr$outcome), , drop = FALSE]
  if (!nrow(ctr_g) && "contrast" %in% names(ctr)) ctr_g <- ctr
  if (nrow(ctr_g)) {
    est_col <- if ("estimate" %in% names(ctr_g)) ctr_g$estimate else ctr_g$diff
    p_col <- if ("p_wald" %in% names(ctr_g)) ctr_g$p_wald else ctr_g$p_interaction_proxy
    tp <- if ("type" %in% names(ctr_g)) ctr_g$type else "slope"
    ctr_df <- data.frame(
      Model = "Preset contrast",
      Term = paste0(gsub("_", "\u2013", as.character(ctr_g$contrast)), " [", tp, "]"),
      `β (SE)` = sprintf(
        "%s",
        if (exists("pub_format_est", mode = "function")) pub_format_est(est_col) else sprintf("%.3f", est_col)
      ),
      P = if (exists("pub_format_p", mode = "function")) pub_format_p(p_col) else as.character(p_col),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    t2 <- rbind(t2, ctr_df)
  }
}
t2_path <- file.path(tab_root, "Table 2. CHARLS LMM of global cognition.xlsx")
pamob_write_sci_xlsx(
  t2, t2_path,
  title = "Table 2. CHARLS linear mixed-effects models of global cognition",
  footnotes = c(
    "Outcome: global cognition (0\u201321). Random intercept for ID. Reference phenotype: Active\u2013preserved.",
    "Primary scientific emphasis: between-phenotype differences in cognitive LEVEL and domain-specific patterns;",
    "global phenotype \u00d7 time / preset slope contrasts are reported for completeness and were not significant in Model 3.",
    "Model 1: age, sex. Model 2: + education, marital status, residence, income. Model 3: + lifestyle, comorbidities, CES-D-10.",
    "Preset contrasts: Inactive\u2013preserved vs Active\u2013preserved; Active\u2013limited vs Inactive\u2013limited (level and slope).",
    "β = fixed-effect estimate; SE = standard error."
  )
)
written <- c(written, basename(t2_path))
message("OK ", basename(t2_path))

# ── Table 3 CHARLS episodic（主文升格）──
epi_src <- file.path(charls_u, "Table 3. CHARLS LMM Episodic memory.csv")
if (!file.exists(epi_src)) epi_src <- file.path(charls_u, "Table_S_CHARLS_LMM_Episodic.csv")
if (file.exists(epi_src)) {
  epi_raw <- read.csv(epi_src, stringsAsFactors = FALSE, check.names = FALSE)
  epi_keep <- grepl("^(Time_years|phenotype|Time_years:phenotype)", epi_raw$term)
  epi_mod <- epi_raw$model %in% c("Model1", "Model2", "Model3")
  epi <- pamob_format_coef_pub(epi_raw[epi_mod & epi_keep, , drop = FALSE])
  if (file.exists(ctr_path)) {
    ctr <- read.csv(ctr_path, stringsAsFactors = FALSE)
    if ("outcome" %in% names(ctr)) {
      ctr_e <- ctr[ctr$outcome == "Episodic_memory", , drop = FALSE]
      if (nrow(ctr_e)) {
        ctr_df <- data.frame(
          Model = "Preset contrast",
          Term = paste0(gsub("_", "\u2013", as.character(ctr_e$contrast)), " [", ctr_e$type, "]"),
          `β (SE)` = if (exists("pub_format_est", mode = "function")) pub_format_est(ctr_e$estimate) else sprintf("%.3f", ctr_e$estimate),
          P = if (exists("pub_format_p", mode = "function")) pub_format_p(ctr_e$p_wald) else as.character(ctr_e$p_wald),
          check.names = FALSE, stringsAsFactors = FALSE
        )
        epi <- rbind(epi, ctr_df)
      }
    }
  }
  t3_path <- file.path(tab_root, "Table 3. CHARLS LMM of episodic memory.xlsx")
  pamob_write_sci_xlsx(
    epi, t3_path,
    title = "Table 3. CHARLS linear mixed-effects models of episodic memory",
    footnotes = c(
      "Key domain-specific finding: Active\u2013limited shows faster episodic-memory decline (phenotype \u00d7 time) despite relative preservation on global cognition/DSST.",
      "Same covariate nesting as Table 2. Preset pairwise contrasts (level and slope) appended when available.",
      "Stability across sensitivities: see Table S3 / Active\u2013limited slope stability CSV."
    )
  )
  written <- c(written, basename(t3_path))
  message("OK ", basename(t3_path))
}

# ── Table 4 NHANES baseline（DSST 主认知样本）──
t4b_raw <- read.csv(file.path(nhanes_u, "Table 3. NHANES baseline by phenotype.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
t4b <- pamob_format_baseline_pub(t4b_raw, drop_vars = c("Age_anal", "CRP", "SSSNFL", "eGFR"))
t4b_path <- file.path(tab_root, "Table 4. NHANES baseline characteristics by PA-mobility phenotype.xlsx")
pamob_write_sci_xlsx(
  t4b, t4b_path,
  title = "Table 4. NHANES survey-weighted baseline characteristics by PA\u2013mobility phenotype",
  footnotes = c(
    "NHANES 2013\u20132014 (Cycle H). Main cognitive sample: age \u226560 years with PA, mobility, and DSST; weight WTMEC2YR (not restricted to NfL).",
    "Continuous: survey-weighted mean (SE). Categorical: weighted % (SE) among non-missing.",
    "Serum NfL subsample is exploratory and reported separately (Table S-NfL)."
  )
)
written <- c(written, basename(t4b_path))
message("OK ", basename(t4b_path))

# ── Table 5 NHANES DSST（正文）──
t5_candidates <- c(
  file.path(nhanes_u, "Table 4. NHANES DSST regressions.csv"),
  file.path(nhanes_u, "NHANES", "Table_Pamob_NHANES_DSST.csv"),
  file.path(nhanes_u, "Table 4. NHANES DSST and NfL regressions.csv")
)
t5_src <- t5_candidates[file.exists(t5_candidates)][1]
if (!is.na(t5_src)) {
  t5_raw <- read.csv(t5_src, stringsAsFactors = FALSE, check.names = FALSE)
  t5_raw <- t5_raw[t5_raw$outcome %in% c("DSST", NA, "") | is.na(t5_raw$outcome) |
                     !grepl("NfL|nfl", t5_raw$outcome, ignore.case = TRUE), , drop = FALSE]
  if (!"outcome" %in% names(t5_raw)) t5_raw$outcome <- "DSST"
  t5_sub <- t5_raw[grepl("^phenotype", t5_raw$term) &
                     t5_raw$model %in% c("Model0", "Model1", "Model2", "Model3"), , drop = FALSE]
  t5 <- pamob_format_coef_pub(t5_sub, outcome_col = "outcome")
  t5_path <- file.path(tab_root, "Table 5. NHANES survey-weighted regressions for DSST.xlsx")
  n_note <- if ("n" %in% names(t5_raw)) paste0("Analytic n=", t5_raw$n[1], ".") else ""
  pamob_write_sci_xlsx(
    t5, t5_path,
    title = "Table 5. NHANES survey-weighted regressions for DSST",
    footnotes = c(
      paste("Main triangulation endpoint: DSST on the full cognitive sample (WTMEC2YR).", n_note),
      "Complex survey design: strata SDMVSTRA, PSU SDMVPSU. Design df and normal-approximation notes: Manuscript/Model_diagnostics.md.",
      "Reference phenotype: Active\u2013preserved. Model 1\u20133 covariates as specified in Methods.",
      "Preset pairwise contrasts (Inactive\u2013preserved vs Active\u2013preserved; Active\u2013limited vs Inactive\u2013limited) in by_unit NHANES contrast CSV."
    )
  )
  written <- c(written, basename(t5_path))
  message("OK ", basename(t5_path))
}

# ── Exploratory sNfL ──
nfl_src <- c(
  file.path(nhanes_u, "Table_S_NHANES_sNfL_exploratory.csv"),
  file.path(nhanes_u, "NHANES", "Table_Pamob_NHANES_NfL_Exploratory.csv")
)
nfl_src <- nfl_src[file.exists(nfl_src)][1]
if (!is.na(nfl_src)) {
  nf <- read.csv(nfl_src, stringsAsFactors = FALSE, check.names = FALSE)
  nf_sub <- nf[grepl("^phenotype", nf$term) & nf$model %in% c("Model0", "Model1", "Model2", "Model3", "Model3_eGFR"), ]
  nf_pub <- pamob_format_coef_pub(nf_sub, outcome_col = "outcome")
  snfl_path <- file.path(tab_root, "Table S6. NHANES exploratory sNfL regressions.xlsx")
  pamob_write_sci_xlsx(
    nf_pub, snfl_path,
    title = "Table S6. Exploratory NHANES survey-weighted regressions for log(serum NfL)",
    footnotes = c(
      "EXPLORATORY biomarker subsample (WTSSNH2Y; age 60\u201375; n = 440). Not the main NHANES cognitive analysis.",
      "Primary NHANES cognitive analysis is Table 5 (DSST; WTMEC2YR; n = 1,264).",
      "DSST and sNfL are not forced to share a complete-case sample."
    )
  )
  written <- c(written, basename(snfl_path))
  message("OK ", basename(snfl_path))
}

# (legacy dual Table3/4 NfL framing removed — see Table 4/5 + exploratory sNfL above)
# ── Table S1 Variable dictionary ──
dict_candidates <- c(
  file.path(batch, "_shared", "Tables", "Feasibility", "Table_Pamob_Variable_Dictionary.csv"),
  file.path(charls_u, "..", "..", "..", "_shared", "Tables", "Feasibility", "Table_Pamob_Variable_Dictionary.csv")
)
dict_path_src <- dict_candidates[file.exists(dict_candidates)][1]
if (!is.na(dict_path_src) && nzchar(dict_path_src)) {
  dict <- read.csv(dict_path_src, stringsAsFactors = FALSE, check.names = FALSE)
  names(dict) <- gsub("_", " ", names(dict))
  s1_path <- file.path(tab_root, "Table S1. Variable dictionary.xlsx")
  pamob_write_sci_xlsx(
    dict, s1_path,
    title = "Table S1. Variable dictionary",
    footnotes = c(
      "Dictionary assembled from delivered CHARLS/NHANES extracts and proposal Appendix A.",
      "Outcome columns are documented for transparency and are not used as covariates."
    )
  )
  written <- c(written, basename(s1_path))
  message("OK ", basename(s1_path))
}

# ── Table S2：保留 episodic 附表副本（主文已升格为 Table 3）──
epi_src <- file.path(charls_u, "Table_S_CHARLS_LMM_Episodic.csv")
if (file.exists(epi_src)) {
  epi_raw <- read.csv(epi_src, stringsAsFactors = FALSE, check.names = FALSE)
  epi_keep <- grepl("^(Time_years|phenotype|Time_years:phenotype)", epi_raw$term)
  epi_mod <- epi_raw$model %in% c("Model1", "Model2", "Model3")
  epi <- pamob_format_coef_pub(epi_raw[epi_mod & epi_keep, , drop = FALSE])
  s2_path <- file.path(tab_root, "Table S2. CHARLS LMM of episodic memory (mirror of Table 3).xlsx")
  pamob_write_sci_xlsx(
    epi, s2_path,
    title = "Table S2. CHARLS episodic memory LMM (mirror of main Table 3)",
    footnotes = c(
      "Identical model terms as main-text Table 3; retained for supplement numbering continuity."
    )
  )
  written <- c(written, basename(s2_path))
  message("OK ", basename(s2_path))
}

# ── Table S3 CHARLS sensitivity（仅 phenotype×time 关键项）──
sens_c <- file.path(charls_u, "Table_S_CHARLS_LMM_Sensitivity.csv")
if (file.exists(sens_c)) {
  sc <- read.csv(sens_c, stringsAsFactors = FALSE, check.names = FALSE)
  sc <- sc[grepl("Time_years:phenotype|phenotype", sc$term) &
             grepl("^Model3$|^Model2$", sc$model), , drop = FALSE]
  sc_pub <- pamob_format_coef_pub(sc)
  s3_path <- file.path(tab_root, "Table S3. CHARLS sensitivity analyses.xlsx")
  pamob_write_sci_xlsx(
    sc_pub, s3_path,
    title = "Table S3. CHARLS sensitivity analyses (selected terms)",
    footnotes = c(
      "Pre-specified sensitivities (e.g., mobility \u22652 items; exclude baseline stroke).",
      "Shown: phenotype and phenotype \u00d7 time terms from adjusted models. Full coefficient dumps retained in by_unit checkpoints."
    )
  )
  written <- c(written, basename(s3_path))
  message("OK ", basename(s3_path))
}

# ── Table S4 NHANES sensitivity ──
sens_n <- file.path(nhanes_u, "Table_S_NHANES_Sensitivity_Regressions.csv")
if (file.exists(sens_n)) {
  sn <- read.csv(sens_n, stringsAsFactors = FALSE, check.names = FALSE)
  sn <- sn[grepl("^phenotype", sn$term), , drop = FALSE]
  sn_pub <- pamob_format_coef_pub(sn, outcome_col = if ("outcome" %in% names(sn)) "outcome" else NULL)
  s4_path <- file.path(tab_root, "Table S4. NHANES sensitivity analyses.xlsx")
  pamob_write_sci_xlsx(
    sn_pub, s4_path,
    title = "Table S4. NHANES sensitivity analyses",
    footnotes = c(
      "Includes PFQ answer-5 exclusion, stroke exclusion, and NfL Model3 + eGFR \u00b1 CRP extensions as available.",
      "Coefficients are phenotype contrasts vs Active\u2013preserved under the survey design."
    )
  )
  written <- c(written, basename(s4_path))
  message("OK ", basename(s4_path))
}

# ── Table S5 PA duration map ──
pa_map <- file.path(charls_u, "CHARLS", "Table_S_PA_Duration_Alt_Map.csv")
if (!file.exists(pa_map)) pa_map <- file.path(batch, "Tables", "Table_S_PA_Duration_Alt_Map.csv")
# may have been deleted; try unit
if (!file.exists(pa_map)) {
  hits <- list.files(file.path(batch, "by_unit"), pattern = "PA_Duration_Alt_Map",
                     recursive = TRUE, full.names = TRUE)
  if (length(hits)) pa_map <- hits[[1L]]
}
if (file.exists(pa_map)) {
  pm <- read.csv(pa_map, stringsAsFactors = FALSE, check.names = FALSE)
  s5_path <- file.path(tab_root, "Table S5. PA duration representative minutes.xlsx")
  pamob_write_sci_xlsx(
    pm, s5_path,
    title = "Table S5. Physical activity duration representative minutes",
    footnotes = c(
      "Primary analysis uses 20/75/180/240 min representatives (Tian & Shi 2022).",
      "Alternative 15/60/150/210 mapping used in sensitivity when raw bins are available."
    )
  )
  written <- c(written, basename(s5_path))
  message("OK ", basename(s5_path))
}


# ── Table S7–S9 Contextual inventory (teacher item 5; no mediation) ──
ctx_dir <- file.path(tab_root, "Contextual")
ctx_inv <- file.path(ctx_dir, "Table_S_Contextual_variable_inventory.csv")
if (!file.exists(ctx_inv)) ctx_inv <- file.path(tab_root, "Table_S_Contextual_variable_inventory.csv")
ctx_by <- file.path(ctx_dir, "Table_S_Contextual_by_phenotype.csv")
if (!file.exists(ctx_by)) ctx_by <- file.path(tab_root, "Table_S_Contextual_by_phenotype.csv")
ctx_disc <- file.path(ctx_dir, "Table_S_Contextual_discordant_contrast.csv")
if (!file.exists(ctx_disc)) ctx_disc <- file.path(tab_root, "Table_S_Contextual_discordant_contrast.csv")
if (file.exists(ctx_inv)) {
  pamob_write_sci_xlsx(
    read.csv(ctx_inv, stringsAsFactors = FALSE, check.names = FALSE),
    file.path(tab_root, "Table S7. Contextual variable inventory.xlsx"),
    title = "Table S7. Contextual variable inventory (CHARLS and NHANES)",
    footnotes = c(
      "Availability, source/wave, and missingness only; no mediation or interaction in this revision.",
      "CHARLS 2011 has PA intensity (da051–da055) but not work/transport/recreation purpose domains."
    )
  )
  written <- c(written, "Table S7. Contextual variable inventory.xlsx")
  message("OK Table S7. Contextual variable inventory.xlsx")
}
if (file.exists(ctx_by)) {
  pamob_write_sci_xlsx(
    read.csv(ctx_by, stringsAsFactors = FALSE, check.names = FALSE),
    file.path(tab_root, "Table S8. Contextual distribution by phenotype.xlsx"),
    title = "Table S8. Contextual variable distribution by PA\u2013mobility phenotype",
    footnotes = c(
      "Binary: percent yes among non-missing; continuous: mean (SD)."
    )
  )
  written <- c(written, "Table S8. Contextual distribution by phenotype.xlsx")
  message("OK Table S8. Contextual distribution by phenotype.xlsx")
}
ctx_primary <- file.path(ctx_dir, "primary_mobility_stratum_PA_contrasts.csv")
if (!file.exists(ctx_primary) && file.exists(ctx_disc)) {
  dtmp <- read.csv(ctx_disc, stringsAsFactors = FALSE, check.names = FALSE)
  if ("role" %in% names(dtmp)) dtmp <- dtmp[grepl("^primary_", dtmp$role), , drop = FALSE]
  ctx_primary_data <- dtmp
} else if (file.exists(ctx_primary)) {
  ctx_primary_data <- read.csv(ctx_primary, stringsAsFactors = FALSE, check.names = FALSE)
} else {
  ctx_primary_data <- NULL
}
if (!is.null(ctx_primary_data) && nrow(ctx_primary_data)) {
  pamob_write_sci_xlsx(
    ctx_primary_data,
    file.path(tab_root, "Table S9. Contextual primary mobility-stratum PA contrasts.xlsx"),
    title = "Table S9. Contextual profiles: primary within-mobility PA contrasts",
    footnotes = c(
      "Primary 1: Inactive\u2013preserved vs Active\u2013preserved (mobility preserved) \u2014 correlates of inactivity.",
      "Primary 2: Active\u2013limited vs Inactive\u2013limited (mobility limited) \u2014 correlates of remaining active.",
      "Cross-discordant Active\u2013limited vs Inactive\u2013preserved is secondary only (see Contextual/*.csv); mediation deferred."
    )
  )
  written <- c(written, "Table S9. Contextual primary mobility-stratum PA contrasts.xlsx")
  message("OK Table S9 primary contextual contrasts")
}

# ── Table S10 NHANES DSST preset direct contrasts（正式附表）──
dsst_ctr <- file.path(nhanes_u, "NHANES", "Table_Pamob_NHANES_DSST_Contrasts.csv")
if (!file.exists(dsst_ctr)) {
  hits <- list.files(nhanes_u, pattern = "DSST_Contrasts", recursive = TRUE, full.names = TRUE)
  if (length(hits)) dsst_ctr <- hits[[1L]]
}
if (file.exists(dsst_ctr)) {
  dc <- read.csv(dsst_ctr, stringsAsFactors = FALSE, check.names = FALSE)
  # 正式展示两条预设 + 可选 vs Active-preserved
  keep <- grepl("Inactive_preserved vs Active_preserved|Active_limited vs Inactive_limited|Active_limited vs Active_preserved",
                dc$contrast)
  dc <- dc[keep, , drop = FALSE]
  pamob_write_sci_xlsx(
    dc,
    file.path(tab_root, "Table S10. NHANES DSST preset direct contrasts.xlsx"),
    title = "Table S10. NHANES DSST preset direct contrasts (survey-weighted)",
    footnotes = c(
      "Pre-specified pairwise mean differences on the DSST main cognitive sample (WTMEC2YR; n = 1,264).",
      "Primary design contrasts: Inactive\u2013preserved vs Active\u2013preserved; Active\u2013limited vs Inactive\u2013limited.",
      "Aligned with CHARLS preset contrasts (Table 2b / episodic slope contrasts)."
    )
  )
  written <- c(written, "Table S10. NHANES DSST preset direct contrasts.xlsx")
  message("OK Table S10 DSST direct contrasts")
}

# ── Table S11 Cognitive construction (optional source) ──
cog_src <- file.path(batch, "Manuscript", "Table_S6_cognition_construction_source.csv")
if (file.exists(cog_src)) {
  cog <- read.csv(cog_src, stringsAsFactors = FALSE)
  s11_path <- file.path(tab_root, "Table S11. CHARLS cognitive score construction.xlsx")
  pamob_write_sci_xlsx(
    cog, s11_path,
    title = "Table S11. CHARLS cognitive score construction",
    footnotes = c(
      "Global cognition (0\u201321) follows Chai et al. 2024.",
      "Episodic memory is Table 3 / Table S2. CES-D-10 is a covariate only."
    )
  )
  written <- c(written, basename(s11_path))
  message("OK ", basename(s11_path))
}

readme <- c(
  "# Publication tables (SCI three-line, Times New Roman)",
  "",
  "Generated by `run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R`.",
  "Process CSVs / QC dumps remain under `by_unit/**/Tables/` and are not mirrored here.",
  "",
  "## Contents",
  paste0("- ", written),
  ""
)
writeLines(readme, file.path(tab_root, "README.md"))
message("DONE root Tables: ", paste(written, collapse = "; "))
