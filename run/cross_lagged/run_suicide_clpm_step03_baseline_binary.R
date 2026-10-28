#!/usr/bin/env Rscript
# step03_baseline_binary — Table 1 by Index C-SSRS ideation item2.
# Input: step02_imputation/dabiao.RData (covariates imputed; scales frozen).
# CGI/EI, follow-up nodes, and design columns stay out of the table.

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  engine_root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  engine_root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(engine_root)

`%||%` <- function(a, b) if (is.null(a)) b else a

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

step_dir <- file.path(study_root, "step03_baseline_binary")
tab_dir <- file.path(step_dir, "Tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

cfg_path <- file.path(study_root, "config_suicide_clpm.R")
.cfg_env <- new.env(parent = globalenv())
sys.source(cfg_path, envir = .cfg_env)
config <- .cfg_env$config

src <- file.path(study_root, "step02_imputation/dabiao.RData")
if (!file.exists(src)) stop("Missing step02 dabiao: ", src, call. = FALSE)
e <- new.env(parent = emptyenv())
load(src, envir = e)
df <- e$dabiao
stopifnot(is.data.frame(df), nrow(df) > 0L)

for (v in names(df)) {
  if (is.character(df[[v]])) df[[v]] <- trimws(df[[v]])
  if (is.factor(df[[v]])) df[[v]] <- droplevels(df[[v]])
}

cands <- as.character(config$suicide_cssrs$covariate_candidate_vars %||% character(0))
cands <- intersect(cands, names(df))
miss_rate <- vapply(cands, function(v) mean(is.na(df[[v]])), numeric(1))
drop_hi <- names(miss_rate)[miss_rate >= 0.4]
cands <- setdiff(cands, drop_hi)
# Baseline mood totals belong in Table 1; follow-up nodes and CSSRS Index (strata) do not.
include_vars <- unique(c(cands, intersect(c("HAMD-17 total, Index", "HAMA-14 total, Index"), names(df))))
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_indicator_names.R"), local = FALSE)
include_vars <- suicide_order_table_vars(include_vars)

config$baseline_binary$include_vars <- include_vars
config$baseline_binary$table1_sections <- suicide_table1_sections()
config$baseline_binary$table1_sections_disable_default <- TRUE
# Keep the Index HAMD total with HAMA under Index assessment, not in an Exposure section.
config$incidence$index_var <- NULL
config$logistic$index_var <- NULL
config$baseline_binary$exclude_vars <- unique(c(
  as.character(config$suicide_cssrs$table1_forbid_vars %||% character(0)),
  as.character(config$suicide_cssrs$design_exclude_vars %||% character(0)),
  "HAMD-17 total, 1st", "HAMA-14 total, 1st", "C-SSRS ideation, 1st",
  paste("Familyhistory", 1:6),
  "Forgets medication", "Missed doses in 2 weeks", "Reduced dose alone",
  "Forgets medication away", "Took medication yesterday", "Stopped when better",
  "Hard to adhere",
  "HAMD Index All", "HAMD 1st All", "HAMA Intex All", "HAMA 1st All",
  "C-SSRS Ideation Index 2", "C-SSRS Ideation 1st 2"
))
config$baseline_binary$strata <- "C-SSRS ideation, Index"
config$baseline_binary$strata_level_labels <- list("0" = "No", "1" = "Yes")
config$baseline_binary$early_stop_if_index_ns <- FALSE
config$baseline_binary$export_train_val_baseline <- FALSE
config$baseline_binary$reexport_table_s1 <- FALSE
config$baseline_binary$table_title <-
  "Baseline characteristics by Index C-SSRS ideation item2"
config$baseline_binary$table1_append_units_from_dictionary <- FALSE
config$baseline_binary$table1_label_overrides <- list(
  Age = "Age, years",
  Weight = "Weight, kg",
  Height = "Height, m",
  BMI = "BMI, kg/m2"
)
config$baseline_binary$table1_xlsx_footnotes <- c(
  paste0("Outpatient N = ", nrow(df), " (six-node complete; covariates after MICE)."),
  "Stratified by C-SSRS ideation, Index (item2, active suicidal thoughts; Yes = 1, No = 0).",
  "HAMD-17 total, Index and HAMA-14 total, Index are Index-wave totals (17-item and 14-item), not the admission baseline scales, and were not imputed.",
  "Family history: Yes if any of the six relative slots recorded a psychiatric diagnosis other than none.",
  "Medication adherence: MMAS-8 total (0-8, higher = better adherence), built before imputation. Items 1-4, 6 and 7: No = 1. Item 5: Yes = 1. Item 8: A = 1, B = 0.75, C = 0.5, D = 0.25, E = 0.",
  "Marriage: married (n = 3) was pooled with in a relationship as Partnered.",
  "Education: illiterate, primary school and junior high were pooled as Before high school; senior high and college or above were pooled as High school or above.",
  "Ever hospitalized and Manic episode: any count greater than 0 was coded Yes, and 0 was coded No, before imputation. No. Depressive Episode remains a count.",
  "Current medication is medication in use at baseline (Yes / No).",
  "Mode of onset is the form of illness onset (acute or slow).",
  "CGI and EI are omitted.",
  "Continuous variables are presented as mean (standard deviation) or median (interquartile range) depending on their distribution. Categorical variables are presented as count (percentage).",
  "Statistical comparisons were performed using the t test or Wilcoxon rank-sum test, and Pearson's chi-squared test or Fisher's exact test."
)
config$project$database <- "Outpatient"
options(pipeline.database_name = "Outpatient")

if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "Blocks/04_baseline/01block_baseline_binary.R"), local = FALSE)

ctx <- list(
  config = config,
  data = list(imputed = df),
  results = list(table_s1_exported = TRUE),
  output_dir = step_dir,
  output_dir_tables = tab_dir
)

message("[step03_baseline_binary] n=", nrow(df), " include=", length(include_vars))
message("[step03_baseline_binary] vars: ", paste(include_vars, collapse = ", "))
ctx <- block_baseline_binary(ctx)

dabiao <- df
save(dabiao, file = file.path(step_dir, "dabiao.RData"))
utils::write.csv(
  data.frame(variable = ctx$results$sig_vars %||% character(0), stringsAsFactors = FALSE),
  file.path(step_dir, "sig_vars.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
meta <- data.frame(
  step = "step03_baseline_binary",
  n = nrow(df),
  strata = "C-SSRS ideation, Index",
  n_include = length(include_vars),
  n_sig = length(ctx$results$sig_vars %||% character(0)),
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
utils::write.csv(meta, file.path(step_dir, "step_meta.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# openxlsx leaves a dangling drawing relation; strip so Excel can open the file.
strip_py <- file.path(engine_root, "R/pub_xlsx_tools/xlsx_strip.py")
if (file.exists(strip_py)) {
  xlsx <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
  for (f in xlsx) {
    system2("python3", c(strip_py, shQuote(f)))
  }
}

message("[step03_baseline_binary] sig_vars: ",
        paste(ctx$results$sig_vars %||% character(0), collapse = ", "))
message("[step03_baseline_binary] DONE ", step_dir)
