###############################################################################
# Rebuild suicide Outpatient publication tables as SCI three-line xlsx
# (export_sci_table), strip junk from summary_result/table/
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  file.path(.engine, ".superpowers/sdd/study_mirror")
)
.tab <- file.path(.study, "summary_result", "table")
.support <- file.path(.study, "summary_result", "_support_clpn")
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.support, recursive = TRUE, showWarnings = FALSE)

setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
.table_queue_env$items <- list()

.fmt_p <- function(p) {
  p <- as.numeric(p)
  ifelse(is.na(p), "",
         ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
.fmt_est <- function(x, d = 3L) {
  x <- as.numeric(x)
  ifelse(is.na(x), "", sprintf(paste0("%.", d, "f"), x))
}
.fmt_est_ci <- function(est, lo, hi, d = 3L) {
  sprintf("%s (%s, %s)", .fmt_est(est, d), .fmt_est(lo, d), .fmt_est(hi, d))
}

# --- load analysis data ---
imp <- file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData")
load(imp)
stopifnot(exists("dabiao"), nrow(dabiao) == 649L)
n0 <- sum(dabiao$CSSRS_Index == 0, na.rm = TRUE)
n1 <- sum(dabiao$CSSRS_Index == 1, na.rm = TRUE)

m2 <- trimws(readLines(file.path(.study, "covariates/Model2Factors.txt"), warn = FALSE))
m2 <- m2[nzchar(m2)]

# =============================================================================
# Table 1 — hip-like baseline (Characteristic / Overall / No / Yes / p)
# =============================================================================
.cont_lab <- c(
  age = "Age, years", Weight = "Weight, kg", Height = "Height, m",
  age_onset = "Age at onset, years",
  No._hopitalization = "Number of hospitalizations",
  No._depressive_episode = "Number of depressive episodes",
  CGI_severiry_index = "CGI severity (Index)",
  HAMD_Index = "HAMD total (Index)", HAMA_Index = "HAMA total (Index)",
  year_education = "Years of education", BMI = "BMI"
)
.cat_lab <- c(
  sex = "Sex", education = "Education", marriage = "Marital status",
  First_episode = "First episode", form = "Form", Attack = "Attack",
  DrugNaive = "Drug naive",
  Familyhistory_3 = "Family history (depression)",
  Familyhistory_4 = "Family history (bipolar)",
  Familyhistory_6 = "Family history (suicide)",
  MASS_1 = "MASS item 1", MASS_2 = "MASS item 2", MASS_7 = "MASS item 7",
  medicine = "Any psychiatric medication",
  Moodstaberlizers = "Mood stabilizers",
  antipsychotics = "Antipsychotics", antidepressants = "Antidepressants",
  BZDs = "Benzodiazepines", ECT = "ECT",
  Smoke_1 = "Smoking", Alcohol_1 = "Alcohol"
)

.desc_cont <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (!length(x)) return("")
  sprintf("%s (%s)", .fmt_est(mean(x), 2L), .fmt_est(stats::sd(x), 2L))
}
.desc_cat_n <- function(x, level) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(x)] <- "(Missing)"
  n <- sum(x == level)
  sprintf("%s (%.1f%%)", format(n, big.mark = ","), 100 * n / length(x))
}

t1_rows <- list()
.push <- function(...) t1_rows[[length(t1_rows) + 1L]] <<- data.frame(..., check.names = FALSE, stringsAsFactors = FALSE)

cont_vars <- intersect(names(.cont_lab), names(dabiao))
# Prefer Model2 order then extras
cont_vars <- unique(c(intersect(m2, cont_vars), cont_vars))
for (v in cont_vars) {
  g0 <- as.numeric(dabiao[[v]][dabiao$CSSRS_Index == 0])
  g1 <- as.numeric(dabiao[[v]][dabiao$CSSRS_Index == 1])
  p <- tryCatch(stats::wilcox.test(g0, g1)$p.value, error = function(e) NA_real_)
  .push(
    Characteristic = unname(.cont_lab[[v]] %||% v),
    `Overall N = 649` = .desc_cont(dabiao[[v]]),
    `CSSRS item1 No N = 158` = .desc_cont(dabiao[[v]][dabiao$CSSRS_Index == 0]),
    `CSSRS item1 Yes N = 491` = .desc_cont(dabiao[[v]][dabiao$CSSRS_Index == 1]),
    `p-value` = .fmt_p(p)
  )
}

cat_vars <- intersect(names(.cat_lab), names(dabiao))
cat_vars <- unique(c(intersect(m2, cat_vars), cat_vars))
for (v in cat_vars) {
  xx <- as.character(dabiao[[v]])
  xx[is.na(xx) | !nzchar(xx)] <- "(Missing)"
  levs <- names(sort(table(xx), decreasing = TRUE))
  ct <- table(xx, dabiao$CSSRS_Index)
  p <- tryCatch({
    if (any(ct < 5)) stats::fisher.test(ct, simulate.p.value = TRUE, B = 2000)$p.value
    else stats::chisq.test(ct)$p.value
  }, error = function(e) NA_real_)
  .push(
    Characteristic = unname(.cat_lab[[v]] %||% v),
    `Overall N = 649` = "",
    `CSSRS item1 No N = 158` = "",
    `CSSRS item1 Yes N = 491` = "",
    `p-value` = .fmt_p(p)
  )
  for (lv in levs) {
    .push(
      Characteristic = paste0("  ", lv),
      `Overall N = 649` = .desc_cat_n(dabiao[[v]], lv),
      `CSSRS item1 No N = 158` = .desc_cat_n(dabiao[[v]][dabiao$CSSRS_Index == 0], lv),
      `CSSRS item1 Yes N = 491` = .desc_cat_n(dabiao[[v]][dabiao$CSSRS_Index == 1], lv),
      `p-value` = ""
    )
  }
}
table1 <- do.call(rbind, t1_rows)
rownames(table1) <- NULL

t1_path <- file.path(.tab, "Table 1-Outpatient. Baseline characteristics of suicide ideation CLPM.xlsx")
export_sci_table(
  table1, t1_path,
  title = "Table 1-Outpatient. Baseline characteristics of suicide ideation CLPM",
  table_footnotes = c(
    "Continuous variables: mean (SD); categorical: n (%).",
    "Stratified by Index C-SSRS ideation item1 (Yes=1 / No=0).",
    "P: Wilcoxon (continuous) or chi-square / Fisher (categorical).",
    "Analysis N=649 outpatient six-node complete cases; nodes excluded from MICE."
  )
)

# =============================================================================
# Table 2 — cross-lagged paths (publication columns)
# =============================================================================
raw2 <- utils::read.csv(
  file.path(.tab, "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.csv"),
  stringsAsFactors = FALSE
)
# Prefer support path if already moved
if (!nrow(raw2) || !"path" %in% names(raw2)) {
  alt <- file.path(.support, "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.csv")
  if (file.exists(alt)) raw2 <- utils::read.csv(alt, stringsAsFactors = FALSE)
}
# Also try raw dump names from covariates era
if (!"path" %in% names(raw2)) {
  cand <- file.path(.study, "summary_result/_archive_old_table_names/Table2_CLPM_paths.csv")
  if (file.exists(cand)) raw2 <- utils::read.csv(cand, stringsAsFactors = FALSE)
}

.path_lab <- c(
  HAMD_AR = "HAMD Index → HAMD 1st (autoregressive)",
  HAMA_AR = "HAMA Index → HAMA 1st (autoregressive)",
  CSSRS_AR = "CSSRS item1 Index → CSSRS item1 1st (autoregressive)",
  HAMD_to_CSSRS = "HAMD Index → CSSRS item1 1st",
  HAMA_to_CSSRS = "HAMA Index → CSSRS item1 1st",
  CSSRS_to_HAMD = "CSSRS item1 Index → HAMD 1st",
  CSSRS_to_HAMA = "CSSRS item1 Index → HAMA 1st",
  HAMD_to_HAMA = "HAMD Index → HAMA 1st",
  HAMA_to_HAMD = "HAMA Index → HAMD 1st"
)
.eff_lab <- c(std_beta = "Standardized β", OR = "OR")

table2 <- data.frame(
  Path = unname(.path_lab[raw2$path] %||% raw2$path),
  Effect = unname(.eff_lab[raw2$effect_type] %||% raw2$effect_type),
  `Estimate (95% CI)` = .fmt_est_ci(raw2$estimate, raw2$ci_low, raw2$ci_high, 3L),
  `P-value` = .fmt_p(raw2$p),
  N = as.integer(raw2$n),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
# preserve path order of raw2
t2_path <- file.path(.tab, "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.xlsx")
export_sci_table(
  table2, t2_path,
  title = "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS",
  table_footnotes = c(
    "Nine pre-registered Index→1st paths; outpatient n=649.",
    "Continuous outcomes: standardized β; CSSRS item1 outcome: odds ratio (OR).",
    paste0("Adjusted for Model 2 covariates: ", paste(m2, collapse = ", "), "."),
    "Cross-lagged CSSRS models mutually control the other mood node and baseline CSSRS as specified."
  )
)

# =============================================================================
# Table S1 — imputation note (structured)
# =============================================================================
note_path <- file.path(.study, "covariates/imputation_note.txt")
note_lines <- if (file.exists(note_path)) readLines(note_path, warn = FALSE) else character(0)
parse_kv <- function(key) {
  hit <- grep(paste0("^", key, "="), note_lines, value = TRUE)
  if (!length(hit)) return("")
  sub(paste0("^", key, "="), "", hit[[1L]])
}
s1 <- data.frame(
  Item = c(
    "Imputation method",
    "m / complete_action",
    "Variables entered into MICE",
    "Nodes excluded from MICE (listwise complete)",
    "Dropped high-missing covariates",
    "Analysis N after six-node complete case"
  ),
  Detail = c(
    parse_kv("IMPUTATION"),
    "m=5; complete_action=1 (first completed set)",
    parse_kv("MICE_VARS"),
    parse_kv("NODES_EXCLUDED_FROM_MICE"),
    parse_kv("DROPPED_HI_MISS"),
    "649"
  ),
  stringsAsFactors = FALSE
)
s1_path <- file.path(
  .tab,
  "Table S1-Outpatient. Baseline characteristics before and after multiple imputation.xlsx"
)
export_sci_table(
  s1, s1_path,
  title = "Table S1-Outpatient. Multiple imputation note (covariates only)",
  table_footnotes = c(
    "Six CLPM nodes were never imputed; only covariates used MICE.",
    "Table 1 describes the analysis set after covariate imputation (complete_action=1)."
  )
)

# =============================================================================
# Table S2 — node Spearman correlation (was mislabeled S6)
# =============================================================================
nodes <- c("HAMD_Index", "HAMD_1st", "HAMA_Index", "HAMA_1st", "CSSRS_Index", "CSSRS_1st")
node_lab <- c(
  HAMD_Index = "HAMD Index", HAMD_1st = "HAMD 1st",
  HAMA_Index = "HAMA Index", HAMA_1st = "HAMA 1st",
  CSSRS_Index = "CSSRS item1 Index", CSSRS_1st = "CSSRS item1 1st"
)
M <- suppressWarnings(stats::cor(dabiao[, nodes], method = "spearman", use = "pairwise.complete.obs"))
s2 <- data.frame(
  Variable = unname(node_lab[rownames(M)]),
  as.data.frame(lapply(as.data.frame(M), function(col) sprintf("%.3f", col))),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
names(s2)[-1] <- unname(node_lab[colnames(M)])
s2_path <- file.path(.tab, "Table S2-Outpatient. Correlation of HAMD HAMA CSSRS nodes.xlsx")
export_sci_table(
  s2, s2_path,
  title = "Table S2-Outpatient. Correlation of HAMD HAMA CSSRS nodes",
  table_footnotes = c(
    "Spearman correlations; outpatient six-node complete N=649.",
    "CSSRS columns are ideation item1 (0/1)."
  )
)

# =============================================================================
# Table S3 — univariate screen (SCI)
# =============================================================================
uv <- utils::read.csv(file.path(.study, "covariates/uv_table.csv"), stringsAsFactors = FALSE)
s3 <- data.frame(
  Variable = uv$variable,
  N = as.integer(uv$n),
  `P-value` = .fmt_p(uv$p_value),
  `Pass UV (p<0.10)` = ifelse(isTRUE(uv$pass_uv) | uv$pass_uv %in% c(TRUE, "TRUE", "True"), "Yes", "No"),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
s3_path <- file.path(.tab, "Table S3-Outpatient. Univariate Regression Analysis.xlsx")
export_sci_table(
  s3, s3_path,
  title = "Table S3-Outpatient. Univariate Regression Analysis",
  table_footnotes = c(
    "Univariate screen toward Model 2 covariate lock (p<0.10).",
    "Outcome context: Index CSSRS item1 / path covariate selection as in Methods."
  )
)

# =============================================================================
# Table S4 — VIF
# =============================================================================
vif <- utils::read.csv(file.path(.study, "covariates/vif_screen.csv"), stringsAsFactors = FALSE)
s4 <- data.frame(
  Variable = vif$variable,
  VIF = format_vif_pub_column(vif$VIF),
  Status = vif$status,
  `Removed in path` = ifelse(isTRUE(vif$removed_in_path) | vif$removed_in_path %in% TRUE, "Yes", "No"),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
s4_path <- file.path(.tab, "Table S4-Outpatient. Multicollinearity Analysis (VIF).xlsx")
export_sci_table(
  s4, s4_path,
  title = "Table S4-Outpatient. Multicollinearity Analysis (VIF)",
  table_footnotes = c(
    "VIF screen among univariate-pass covariates; threshold=4.",
    paste0("Final Model 2: ", paste(m2, collapse = ", "), ".")
  )
)

# =============================================================================
# Keep S8 adjacency csv only (hip style); ensure present
# =============================================================================
s8_src <- file.path(.tab, "Table S8-Outpatient. CLPN adjacency.csv")
if (!file.exists(s8_src)) {
  alt8 <- file.path(.support, "Table S8-Outpatient. CLPN adjacency.csv")
  if (file.exists(alt8)) file.copy(alt8, s8_src, overwrite = TRUE)
}

# Render all queued SCI xlsx
message("[rebuild] rendering queued SCI tables...")
render_queued_tables(list())

# =============================================================================
# Folder hygiene: move non-publication clutter to _support_clpn/
# Keep only SCI xlsx Table* + S8 csv + README (engine may shorten filenames)
# =============================================================================
keep_re <- paste(
  "^Table [12]-Outpatient\\..*\\.xlsx$",
  "^Table S[1-4]-Outpatient\\..*\\.xlsx$",
  "^Table S8-Outpatient\\. CLPN adjacency\\.csv$",
  "^README_summary_slots\\.txt$",
  sep = "|"
)
all_files <- list.files(.tab, full.names = TRUE)
for (f in all_files) {
  bn <- basename(f)
  if (grepl(keep_re, bn)) next
  if (!file.exists(f) || dir.exists(f)) next
  dest <- file.path(.support, bn)
  if (file.exists(dest)) file.remove(dest)
  file.rename(f, dest)
  message("[rebuild] moved to support: ", bn)
}

writeLines(c(
  "table/ = Outpatient publication xlsx only (SCI three-line via export_sci_table).",
  "",
  "Table 1-Outpatient. Baseline characteristics of suicide ideation CLPM.xlsx",
  "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.xlsx",
  "Table S1-Outpatient. Baseline characteristics before and after multiple imputation.xlsx",
  "Table S2-Outpatient. Correlation of HAMD HAMA CSSRS nodes.xlsx",
  "Table S3-Outpatient. Univariate Regression Analysis.xlsx",
  "Table S4-Outpatient. Multicollinearity Analysis.xlsx",
  "Table S8-Outpatient. CLPN adjacency.csv",
  "",
  "Raw dumps / CLPN bootstrap rds / duplicate csv/tex -> summary_result/_support_clpn/",
  "Ward exploratory -> summary_result/_archive_ward_exploratory/"
), file.path(.tab, "README_summary_slots.txt"))

message("[rebuild] remaining table/:")
print(sort(list.files(.tab)))
message("[rebuild] DONE")
