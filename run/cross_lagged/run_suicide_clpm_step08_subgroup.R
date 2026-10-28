#!/usr/bin/env Rscript
# step08 — subgroup forest for Index HAMD-17 and HAMA-14 vs C-SSRS ideation, 1st.
# Uses block_subgroup_incidence (Q4 vs Q1, full analysis set).
# Age cutoff is 18: this outpatient cohort is age 1–29, so the template cutoff 65 has an empty upper group.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step08_subgroup.R

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

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(engine_root, "Blocks/18_subgroup/02block_subgroup_incidence.R"), local = FALSE)

.cfg_env <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_suicide_clpm.R"), envir = .cfg_env)
config <- .cfg_env$config
if (exists("pipeline_apply_pub_digits", mode = "function")) pipeline_apply_pub_digits(config)
options(pipeline.database_name = "Outpatient")

y_col <- "C-SSRS ideation, 1st"
y_safe <- "CSSRS_1st"
exposures <- c("HAMD-17 total, Index", "HAMA-14 total, Index")
safe_index <- c("HAMD-17 total, Index" = "HAMD17_Index", "HAMA-14 total, Index" = "HAMA14_Index")
rename_sub <- c(
  "Family history" = "Family_history",
  "First Episode" = "First_Episode",
  "Ever hospitalized" = "Ever_hospitalized",
  "Current medication" = "Current_medication"
)
subgroup_vars <- c(
  "Age", "Sex", "Education", "Marriage", "Smoke",
  "Family_history", "First_Episode", "Ever_hospitalized",
  "Current_medication", "Moodstaberlizers", "BZDs"
)

step_dir <- file.path(study_root, "step08_subgroup")
tab_dir <- file.path(step_dir, "Tables")
fig_dir <- file.path(step_dir, "Figures")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(study_root, "step02_imputation/dabiao.RData"), envir = e)
df <- e$dabiao
if (!y_col %in% names(df)) stop("Missing outcome", call. = FALSE)
if (is.character(df[[y_col]]) || is.factor(df[[y_col]])) {
  lab <- trimws(as.character(df[[y_col]]))
  df[[y_col]] <- as.integer(lab %in% c("1", "Yes", "yes", "YES", "A", "是"))
}
df[[y_col]] <- as.integer(df[[y_col]])
if (nrow(df) != 643L) stop("Expected N=643, got ", nrow(df), call. = FALSE)
df[[y_safe]] <- df[[y_col]]
for (i in names(rename_sub)) {
  if (i %in% names(df)) names(df)[names(df) == i] <- unname(rename_sub[[i]])
}
for (i in names(safe_index)) df[[safe_index[[i]]]] <- as.numeric(df[[i]])

config$incidence$outcome_var <- y_safe
config$data$outcome_column <- y_safe
config$project$disease <- "C-SSRS ideation at 1st"
config$project$analysis_group <- "1"
config$subgroup$var_source <- "required"
config$subgroup$required_subgroup_vars <- subgroup_vars
config$subgroup$age_cutoff <- 18L
config$subgroup$level_order <- list(Age_Group = c("< 18", "\u2265 18"))
config$subgroup$continuous_index_mode <- "highest_vs_lowest"
config$subgroup$forest_n_source <- "full_stratum"
config$subgroup$export_table <- TRUE
config$subgroup$exclude_levels <- list(
  Education = "Before high school",
  Marriage = "Partnered",
  Current_medication = "No"
)
config$subgroup$forest_arrow_lab <- c("Q1", "Q4")
config$logistic_quartile_glm <- list(scheme = "quartile")

for (x in exposures) {
  x_safe <- unname(safe_index[[x]])
  config$logistic$index_var <- x_safe
  config$incidence$index_var <- x_safe
  config$prediction$index_vars <- x_safe
  short <- if (grepl("^HAMD", x)) "HAMD-17" else "HAMA-14"
  config$subgroup$figure_caption <- paste0("Subgroup Forest analyses of ", x)
  config$subgroup$table_filename <- paste0(
    "Table. Subgroup analysis of ", short, " total, Index.xlsx"
  )
  config$subgroup$table_title <- paste0(
    "Subgroup analysis of ", x, " for C-SSRS ideation at 1st (OR, Q4 vs Q1)"
  )
  ctx <- list(
    config = config,
    data = list(imputed = df),
    results = list(),
    output_dir = step_dir,
    output_dir_tables = tab_dir,
    output_dir_figures = fig_dir,
    current_block = "subgroup_incidence"
  )
  ctx <- block_subgroup_incidence(ctx)
  if (is.null(ctx$results$subgroup)) stop("Subgroup failed for ", x, call. = FALSE)
  message("[step08] ", x, " vars: ", paste(ctx$results$subgroup_vars_used, collapse = ", "))
}
suicide_clpm_flush_sci_tables()

export_pub_figures(fig_dir, meta = list(
  exposure = "HAMD-17 total, Index and HAMA-14 total, Index",
  outcome = "C-SSRS ideation at 1st",
  outcome_column = y_col,
  grouping = "quartile, Q4 vs Q1",
  n_by_db = c(Outpatient = nrow(df)),
  n_total = nrow(df),
  combined = FALSE,
  databases = "Outpatient",
  tables_dir = tab_dir
), config = config, purge = TRUE)
st <- pub_figure_formats_status(fig_dir)
if (length(st$bad_dpi)) stop("DPI below 600: ", paste(st$bad_dpi, collapse = ", "), call. = FALSE)
message("[step08] DONE ", step_dir)
