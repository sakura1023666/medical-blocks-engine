#!/usr/bin/env Rscript
# Completes: EnhB age≥60 (no 75 cap); 100m walk (db003); CRP honesty; Methods/dict polish; clean Manuscript/_source
suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
})

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
dr <- "G:/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"
charls_u <- file.path(batch, "by_unit", "【success】CHARLS")
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES")
ms <- file.path(batch, "Manuscript")
tab_root <- file.path(batch, "Tables")

cfg_env <- new.env(parent = globalenv())
sys.source("configs/config_pa_mobility_cognitive_batch.R", envir = cfg_env)
bl <- cfg_env$config$pamob
cov3_n <- bl$nhanes_covariates_model3
cov3_c <- bl$covariates_model3

pamob_ensure_packages(c("haven", "survey", "lme4", "lmerTest", "openxlsx"))

# ════════════════ Enhancement B: age≥60, no NfL, no age_max=75 ════════════════
message("=== Enhancement B (age>=60, uncapped) ===")
pa <- pamob_read_csv(file.path(dr, "NHANES/D03_physical_activity.csv"))
mo <- pamob_read_csv(file.path(dr, "NHANES/D04_mobility_capacity.csv"))
ds <- pamob_read_csv(file.path(dr, "NHANES/D02_cognitive_performance.csv"))
if (names(mo)[1] %in% c("X", "")) mo <- mo[, -1, drop = FALSE]
if (names(ds)[1] %in% c("X", "")) ds <- ds[, -1, drop = FALSE]
# D02 has no cycle column — restrict via DEMO_H after merge
pa <- pa[as.character(pa$cycle) == "H", ]
mo <- mo[as.character(mo$cycle) == "H", ]
pa$SEQN <- as.integer(pa$SEQN); mo$SEQN <- as.integer(mo$SEQN); ds$SEQN <- as.integer(ds$SEQN)
pa$pa_sufficient <- suppressWarnings(as.integer(pa$pa_level))
mo$mobility_limited <- suppressWarnings(as.integer(mo$mobility_limited))
d <- merge(pa[, c("SEQN", "pa_sufficient")], mo[, c("SEQN", "mobility_limited")], by = "SEQN")
d$phenotype <- pamob_phenotype_factor(pamob_phenotype_key(d$pa_sufficient, d$mobility_limited))
d <- d[!is.na(d$phenotype), ]
d <- merge(d, ds[, c("SEQN", "CFDDS")], by = "SEQN")
d$CFDDS <- suppressWarnings(as.numeric(d$CFDDS))
d <- d[!is.na(d$CFDDS), ]

demo <- haven::read_xpt(file.path(dr, "NHANES/DEMO_H.XPT"))
demo$SEQN <- as.integer(demo$SEQN)
demo$WTMEC2YR <- suppressWarnings(as.numeric(demo$WTMEC2YR))
demo$RIDAGEYR <- suppressWarnings(as.numeric(demo$RIDAGEYR))
d <- merge(d, demo[, c("SEQN", "RIDAGEYR", "WTMEC2YR", "SDMVSTRA", "SDMVPSU", "RIAGENDR")], by = "SEQN")
d$Age <- d$RIDAGEYR
d <- d[!is.na(d$Age) & d$Age >= 60 & !is.na(d$WTMEC2YR) & d$WTMEC2YR > 0, ]
if (!nrow(d)) stop("EnhB analysis set empty after PA×mobility×DSST×DEMO age>=60 filter")

e <- new.env(parent = emptyenv())
load(file.path(dr, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
base <- e$baseline
bh <- base[as.character(base$Source_File) == "2013-2014", ]
bh$SEQN <- as.integer(bh$ID)
cov_keep <- setdiff(
  intersect(unique(c(cov3_n, "Gender", "Race", "Education", "PIR", "Marital_Status",
                     "BMI", "Smoke", "Alcohol_drinking", "Hypertension", "Diabetes",
                     "CHD", "HF", "Stroke", "Depression", "Creatinine")), names(bh)),
  c("SEQN", "Age", "ID", "WTMEC2YR", "SDMVSTRA", "SDMVPSU", "RIAGENDR", "CFDDS",
    "phenotype", "pa_sufficient", "mobility_limited")
)
dB <- merge(d, bh[, c("SEQN", cov_keep), drop = FALSE], by = "SEQN", all.x = TRUE)
# ensure Age retained from DEMO
dB$Age <- dB$RIDAGEYR
if (!"Gender" %in% names(dB) || all(is.na(dB$Gender))) {
  dB$Gender <- ifelse(dB$RIAGENDR == 1, "Male", ifelse(dB$RIAGENDR == 2, "Female", NA_character_))
}
dB$WT_USE <- as.numeric(dB$WTMEC2YR)
dB$phenotype <- stats::relevel(
  factor(as.character(dB$phenotype), levels = unname(pamob_phenotype_labels())),
  ref = "Active_preserved"
)
if (!nrow(dB) || all(is.na(dB$Age))) stop("EnhB dB empty/Age lost after covariate merge")
message(sprintf(
  "EnhB n=%d age %s-%s (>75 n=%d)",
  nrow(dB),
  as.integer(min(dB$Age, na.rm = TRUE)),
  as.integer(max(dB$Age, na.rm = TRUE)),
  sum(dB$Age > 75, na.rm = TRUE)
))
covB <- pamob_resolve_covars(dB, cov3_n)
desB <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WT_USE,
                          nest = TRUE, data = dB)
tabB <- pamob_svyglm_coef_tab(desB, "CFDDS", covB, "EnhB_DSST_age60plus_noNfL_M3",
                              "WTMEC2YR", nrow(dB))
write.csv(tabB, file.path(nhanes_u, "Tables", "Table_S_NHANES_DSST_EnhancementB.csv"),
          row.names = FALSE)
write.csv(
  as.data.frame(table(
    AgeGroup = ifelse(dB$Age > 75, ">75", "60-75"),
    phenotype = as.character(dB$phenotype)
  )),
  file.path(nhanes_u, "Tables", "Table_S_NHANES_DSST_EnhancementB_N.csv"),
  row.names = FALSE
)

tabB_pub <- pamob_format_coef_pub(
  tabB[grepl("^phenotype", tabB$term), , drop = FALSE],
  outcome_col = "outcome"
)
pamob_write_sci_xlsx(
  tabB_pub,
  file.path(tab_root, "Table S7. NHANES DSST enhancement age60plus without NfL limit.xlsx"),
  title = "Table S7. NHANES DSST enhancement (age \u226560, no NfL restriction)",
  footnotes = c(
    sprintf(
      "n = %s; age range %s\u2013%s years (age >75: n = %s).",
      format(nrow(dB), big.mark = ","), min(dB$Age), max(dB$Age),
      format(sum(dB$Age > 75, na.rm = TRUE), big.mark = ",")
    ),
    "Survey weight: WTMEC2YR. Serum NfL not required. Model 3 covariates when available.",
    "Main integrated NfL sample remains age 60\u201375 with WTSSNH2Y (Tables 3\u20134 / Figure 4).",
    "Proposal \u00a710.2 module B."
  )
)

# ════════════════ 100 m walk alternative (db003 from raw dta) ════════════════
message("=== 100m walk (db003) ===")
.diff <- function(x) {
  x <- suppressWarnings(as.integer(x))
  ifelse(is.na(x), NA_integer_, as.integer(x >= 2L))
}
# Hierarchical skip: if not asked, treat as no difficulty (code 1), matching D04 fill logic
.fill1 <- function(x) {
  x <- suppressWarnings(as.integer(x))
  ifelse(is.na(x), 1L, x)
}

h <- haven::read_dta(
  file.path(dr, "CHARLS/rawdata/health_status_and_functioning-2011.dta"),
  col_select = c("ID", "db002", "db003", "db004", "db005", "db006")
)
h$ID_h <- pamob_charls_id_h(h$ID)
h$db003_use <- .fill1(h$db003)
h$lim_100m <- as.integer(
  rowSums(cbind(
    .diff(h$db003_use), .diff(h$db004), .diff(h$db005), .diff(h$db006)
  ), na.rm = TRUE) > 0
)
h$lim_main_chk <- as.integer(
  rowSums(cbind(
    .diff(.fill1(h$db002)), .diff(h$db004), .diff(h$db005), .diff(h$db006)
  ), na.rm = TRUE) > 0
)
m100 <- h[!duplicated(h$ID_h), c("ID_h", "lim_100m")]

long <- read.csv(file.path(charls_u, "Tables", "CHARLS", "Analysis_CHARLS_Long.csv"),
                 stringsAsFactors = FALSE)
long$ID_h <- pamob_pad_id12(long$ID_h)
long2 <- merge(long, m100, by = "ID_h", all.x = TRUE)
# keep PA from baseline phenotype components already on long
long2$pheno_100 <- pamob_phenotype_factor(
  pamob_phenotype_key(long2$pa_sufficient, long2$lim_100m)
)
long2a <- long2[!is.na(long2$pheno_100) & !is.na(long2$Global_cognition) &
                  !is.na(long2$Time_years), ]
long2a$phenotype <- stats::relevel(
  factor(as.character(long2a$pheno_100), levels = unname(pamob_phenotype_labels())),
  ref = "Active_preserved"
)
covs <- pamob_resolve_covars(long2a, cov3_c)
fml <- stats::as.formula(paste(
  "Global_cognition ~ Time_years * phenotype",
  if (length(covs)) paste("+", paste(covs, collapse = "+")) else "",
  "+ (1|ID_h)"
))
fit100 <- tryCatch(lmerTest::lmer(fml, data = long2a, REML = TRUE), error = function(e) e)
if (!inherits(fit100, "error")) {
  sm <- summary(fit100)$coefficients
  tab100 <- data.frame(
    model = "Model3", term = rownames(sm),
    estimate = sm[, 1], std.error = sm[, 2], p.value = sm[, 4],
    note = NA_character_, analysis = "mobility_walk_100m_alt",
    stringsAsFactors = FALSE
  )
  message(sprintf("100m OK n_obs=%d n_id=%d", nrow(long2a), length(unique(long2a$ID_h))))
} else {
  tab100 <- data.frame(
    model = "Model3", term = NA_character_, estimate = NA_real_,
    std.error = NA_real_, p.value = NA_real_,
    note = conditionMessage(fit100), analysis = "mobility_walk_100m_alt",
    stringsAsFactors = FALSE
  )
  message("100m FAIL: ", conditionMessage(fit100))
}

sens_c <- file.path(charls_u, "Tables", "Table_S_CHARLS_LMM_Sensitivity.csv")
sc <- read.csv(sens_c, stringsAsFactors = FALSE)
sc <- sc[sc$analysis != "mobility_walk_100m_alt", , drop = FALSE]
sc <- rbind(sc, tab100)
write.csv(sc, sens_c, row.names = FALSE)

# refresh S3
sc2 <- sc[sc$analysis %in% c(
  "phenotype_2_mobility_ge2", "ids_with_ge2_waves", "exclude_baseline_stroke",
  "PA_alt_duration_15_60_150_210", "exclude_baseline_ADL_IADL",
  "random_slope_Time", "mobility_walk_100m_alt"
), , drop = FALSE]
sc2 <- sc2[grepl("Time_years|phenotype", sc2$term) | is.na(sc2$term), , drop = FALSE]
sc_pub <- pamob_format_coef_pub(sc2)
pamob_write_sci_xlsx(
  sc_pub,
  file.path(tab_root, "Table S3. CHARLS sensitivity analyses.xlsx"),
  title = "Table S3. CHARLS sensitivity analyses (selected terms)",
  footnotes = c(
    "Analyses: mobility \u22652 items; \u22652 cognition waves; exclude stroke; PA alt duration; exclude ADL/IADL;",
    "Model 3 random slope for Time_years; walk 100 m (db003) mobility alternative (NA skip filled as no difficulty).",
    "Displayed terms: phenotype / time / interaction from adjusted models.",
    sprintf("100 m alternative: n_id = %s.", format(length(unique(long2a$ID_h)), big.mark = ","))
  )
)

# ════════════════ CRP honesty already in S4; strengthen diagnostic note ════════════════
crp_note <- paste(
  "CRP/HSCRP: delivered D01 baseline has CRP in 1999–2010 and HSCRP from 2015+;",
  "2013–2014 (cycle H) CRP and HSCRP are entirely missing after SEQN=ID match.",
  "NfL sensitivity therefore uses Model 3 + eGFR only (Table S4)."
)
diag_path <- file.path(ms, "Model_diagnostics.md")
diag <- if (file.exists(diag_path)) readLines(diag_path, warn = FALSE) else character(0)
if (!any(grepl("2013.2014.*CRP|cycle H.*CRP", diag, ignore.case = TRUE))) {
  diag <- c(diag, "", "## CRP availability (cycle H)", crp_note, "")
  writeLines(diag, diag_path)
}

# ════════════════ Table S8 status ════════════════
enh_notes <- data.frame(
  module = c(
    "CRP sensitivity",
    "Enhancement B DSST",
    "random slope",
    "walk 100m alternative",
    "SPPB like",
    "grip strength"
  ),
  status = c(
    "NOT AVAILABLE — cycle H (2013–2014) has no CRP/HSCRP in delivered baseline",
    sprintf("DONE — n=%d, age %d–%d (>%d: n=%d), WTMEC2YR, no NfL",
            nrow(dB), min(dB$Age), max(dB$Age), 75L, sum(dB$Age > 75)),
    "DONE — Model3 random slope (Table S3)",
    if (!inherits(fit100, "error"))
      sprintf("DONE — db003 replaces db002; n_id=%d (Table S3)", length(unique(long2a$ID_h)))
    else paste0("FAILED — ", conditionMessage(fit100)),
    "NOT AVAILABLE — no balance/gait timed components in delivered CHARLS extract",
    "NOT AVAILABLE — no grip column in delivered CHARLS baseline"
  ),
  proposal_ref = c(
    "§8 / Supplement ‘may further add CRP’",
    "§10.2 B",
    "§10 optional",
    "§5.4 / Methods walk alternative",
    "§5.4 optional strengthen",
    "§5.4 optional"
  ),
  stringsAsFactors = FALSE
)
pamob_write_sci_xlsx(
  enh_notes,
  file.path(tab_root, "Table S8. Enhancement and optional module status.xlsx"),
  title = "Table S8. Enhancement and optional module status",
  footnotes = c(
    "Honest availability against delivered extracts and proposal optional modules.",
    "CRP cannot be added for the 2013–2014 NfL sample without an external CRP XPT not in the locked data package.",
    "100 m walk uses raw health_status_and_functioning-2011.dta db003 (not in D04 aggregate)."
  )
)
write.csv(enh_notes, file.path(ms, "Enhancement_modules_status.csv"), row.names = FALSE)

# ════════════════ S1: add original coding granularity sheet ════════════════
message("=== S1 coding table ===")
coding <- data.frame(
  database = c(
    rep("CHARLS", 10),
    rep("NHANES", 8)
  ),
  variable = c(
    "db001", "db002", "db003", "db004", "db005", "db006",
    "PA duration bins", "pa_sufficient", "mobility_limited (main)", "Global_cognition",
    "PFQ061B/C/D/I", "PFQ answer 5", "PFQ054 skip", "PA Guidelines MET",
    "SSSNFL", "CFDDS (DSST)", "WTSSNH2Y", "WTMEC2YR"
  ),
  original_coding = c(
    "1=No difficulty; 2=Some; 3=Much; 4=Unable; (skip if prior item allows)",
    "Same 1–4; main walk-1km item",
    "Same 1–4; walk ~100 m (sensitivity replaces db002)",
    "Same 1–4; rise from chair",
    "Same 1–4; climb several flights",
    "Same 1–4; stoop/kneel/crouch",
    "Questionnaire intervals → 20/75/180/240 min (Tian & Shi 2022)",
    "1 if MET-min/week \u2265600 else 0",
    "1 if any of db002/db004/db005/db006 \u22652 (skip filled as 1=no difficulty)",
    "Episodic memory + mental intactness (see Table S6 / Cognition md)",
    "1=no; 2=some; 3=much; 4=unable; 5=do not do; 7/9=RF/DK",
    "Main: treat as limited; sensitivity: exclude any item=5",
    "If walking difficulty without device → treat blank PFQ061B/C as limited",
    "Sufficient PA if meets adult guideline threshold in D03",
    "Serum NfL (pg/mL); analysis uses log(SSSNFL)",
    "Digit Symbol Substitution Test score",
    "NfL subsample weight (main Tables 3–4 / Fig 4)",
    "MEC exam weight (Enhancement B DSST, age \u226560)"
  ),
  analysis_use = c(
    "Not in main 4-item mobility (run/jog)",
    "Main mobility walk domain",
    "Sensitivity: 100 m walk alternative",
    "Main mobility",
    "Main mobility",
    "Main mobility",
    "MET calculation",
    "Phenotype axis 1",
    "Phenotype axis 2",
    "LMM outcome",
    "NHANES mobility items",
    "Main vs sensitivity",
    "Structural missingness",
    "Phenotype axis 1",
    "Secondary outcome",
    "Primary NHANES cognition",
    "Main integrated sample",
    "Enhancement B only"
  ),
  source_file = c(
    rep("health_status_and_functioning-2011.dta / D04", 6),
    "D03 / D05", "D05", "D04 / D05", "D01 episodic + MI",
    "PFQ_H / D04_mobility_capacity", "same", "same", "D03",
    "SSSNFL_H", "CFQ_H / D02", "DEMO/SSSNFL docs", "DEMO_H"
  ),
  stringsAsFactors = FALSE
)

# rebuild S1 workbook: keep existing body + coding sheet via openxlsx carefully
# Use surgical approach: write new xlsx with two logical tables via sci for sheet1,
# and append coding as second export file name... Better: one book two sheets with openxlsx
# but preserve booktabs style on sheet1 by re-calling pamob_write then openpyxl add sheet.

s1_path <- file.path(tab_root, "Table S1. Variable dictionary.xlsx")
dict_body <- tryCatch(
  openxlsx::read.xlsx(s1_path, sheet = 1, startRow = 2),
  error = function(e) NULL
)
# normalize names
if (!is.null(dict_body)) {
  names(dict_body) <- gsub("\\.", " ", names(dict_body))
}
# Write dictionary main (existing content if readable)
if (!is.null(dict_body) && nrow(dict_body) > 0) {
  # drop footnote-like trailing rows (NA-heavy)
  dict_body <- dict_body[rowSums(!is.na(dict_body) & dict_body != "") > 0, , drop = FALSE]
  pamob_write_sci_xlsx(
    dict_body,
    s1_path,
    title = "Table S1. Variable dictionary",
    footnotes = c(
      "Concepts, source files, and recode rules for CHARLS and NHANES analyses.",
      "See companion sheet / Table S1b for original questionnaire coding.",
      "CRP not available for NHANES 2013–2014 in the delivered baseline (see Table S8)."
    )
  )
}

# Table S1b original coding (separate file keeps booktabs single-header engine happy)
pamob_write_sci_xlsx(
  coding,
  file.path(tab_root, "Table S1b. Original coding crosswalk.xlsx"),
  title = "Table S1b. Original coding crosswalk",
  footnotes = c(
    "Original questionnaire codes and analysis mapping (proposal §9.1 item 7 granularity).",
    "CHARLS mobility skip: unasked items filled as 1 (no difficulty), consistent with D04 fill.",
    "db003 (100 m) used only in sensitivity; main walk domain remains db002 (1 km)."
  )
)

# ════════════════ Methods / Results polish (expand draft) ════════════════
methods <- c(
  "# Methods and Results Draft",
  "",
  "## Study design",
  "Dual-database observational study of physical activity (PA)–mobility joint phenotypes and cognitive aging.",
  "CHARLS provides longitudinal linear mixed models (LMM) of global cognition; NHANES 2013–2014 provides",
  "survey-weighted cross-sectional associations of the same four phenotypes with DSST and serum NfL (log).",
  "",
  "## Phenotypes",
  "Four mutually exclusive groups from PA sufficiency (\u2265600 MET-min/week) \u00d7 mobility limitation",
  "(any difficulty on walk 1 km / chair / stairs / stoop in CHARLS; PFQ items in NHANES):",
  "Active–preserved (reference), Inactive–preserved, Active–limited, Inactive–limited (Figure 1).",
  "",
  "## CHARLS analysis set",
  "Baseline 2011 PA–mobility phenotype; repeated cognitive assessments with Time_years from baseline.",
  "Primary LMM: Global_cognition ~ Time_years \u00d7 phenotype + covariates + (1|ID_h).",
  "Model 3 covariates follow the locked config; early-stop / MI leakage gates do not apply (non-TST study).",
  "Figure 2 flowchart and Table 1 baseline characteristics; Table 2 interaction and two preset contrasts;",
  "Figure 3 adjusted trajectories.",
  "",
  "## NHANES analysis set",
  "Cycle H (2013–2014). Main integrated sample for DSST + sNfL: age 60–75 with positive WTSSNH2Y",
  "(Tables 3–4, Figure 4 dual panel of Model-3-adjusted predicted means).",
  "PFQ answer 5 and structural skips coded per Methods rules (Table S5 PA map; Cleaning_log).",
  "",
  "## Sensitivity and enhancements (proposal alignment)",
  "- CHARLS Table S3: \u22652 mobility items; \u22652 cognition waves; exclude stroke; PA duration alternative;",
  "  exclude ADL/IADL disability; **random-slope** Time_years; **100 m walk (db003)** mobility alternative.",
  "- NHANES Table S4: PFQ-5 exclusion; exclude stroke; NfL Model 3 + **eGFR**.",
  "  **CRP:** not available for 2013–2014 in the delivered baseline (CRP earlier cycles; HSCRP from 2015+);",
  "  documented in Model_diagnostics and Table S8. Proposal allows ‘may further add CRP’ when data exist.",
  "- **Enhancement B (Table S7):** DSST among adults aged \u226560 **without** NfL requirement, weight WTMEC2YR,",
  "  age uncapped (includes >75).",
  "- SPPB-like and grip strength: not present in delivered CHARLS extracts (Table S8).",
  "",
  "## Results (brief)",
  "Primary CHARLS phenotype \u00d7 time interactions and NHANES phenotype contrasts are reported in Tables 2 and 4;",
  "point estimates and P values should be read from the locked xlsx (not retyped here to avoid transcription drift).",
  "Enhancement B and 100 m sensitivity coefficients: Tables S7 and S3.",
  "Optional modules without source variables remain NOT AVAILABLE in Table S8 rather than imputed.",
  "",
  "## Deliverables map",
  "| Item | File |",
  "|------|------|",
  "| Fig 1–4, Fig S1 | Figures/pdf|png|tiff|image_information |",
  "| Tables 1–4 | Tables/ |",
  "| S1 dictionary + S1b coding | Tables/ |",
  "| S2 episodic; S3–S8 | Tables/ |",
  "| Methods/diagnostics/cleaning | Manuscript/ |",
  "",
  paste0("_Updated ", format(Sys.time(), "%Y-%m-%d %H:%M"), "_"),
  ""
)
writeLines(methods, file.path(ms, "Methods_Results_Draft.md"))

# ════════════════ Clean Manuscript leftovers ════════════════
src_csv <- file.path(ms, "_source", "Table_S6_cognition_construction_source.csv")
if (file.exists(src_csv)) {
  unlink(src_csv)
  # remove empty dir if empty
  src_dir <- file.path(ms, "_source")
  if (dir.exists(src_dir) && !length(list.files(src_dir, all.files = TRUE, no.. = TRUE))) {
    unlink(src_dir, recursive = TRUE)
  }
  message("Removed Manuscript/_source S6 csv leftover")
}

writeLines(c(
  "# Publication tables",
  "Main: Table 1–4",
  "Supplement: S1 dictionary · S1b original coding · S2 episodic · S3 CHARLS sens · S4 NHANES sens ·",
  "S5 PA map · S6 cognition · S7 DSST EnhB · S8 module status"
), file.path(tab_root, "README.md"))

message("=== DONE ===")
print(enh_notes)
print(list.files(tab_root, pattern = "xlsx$"))
print(list.files(ms, recursive = TRUE))
