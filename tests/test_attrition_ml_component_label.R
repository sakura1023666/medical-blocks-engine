#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(getwd(), winslash = "/"))
if (!exists("%||%", mode = "function")) `%||%` <- function(x, y) if (is.null(x)) y else x
if (!exists("register_block", mode = "function")) register_block <- function(...) invisible(NULL)
source(file.path(root, "Blocks/00_index/01block_index.R"), local = FALSE)
source(file.path(root, "R/attrition_log.R"), local = FALSE)

df <- data.frame(
  TCBI = c(1, 2, NA_real_, 4),
  Triglycerides = c(100, NA_real_, 120, 130),
  Total_Cholesterol = c(200, 210, NA_real_, 220),
  Weight = c(60, 61, 62, NA_real_),
  stringsAsFactors = FALSE
)
lab <- attrition_index_component_missing_label(df, "TCBI")
stopifnot(grepl("Triglycerides \\(n = 1\\)", lab))
stopifnot(grepl("Total cholesterol \\(n = 1\\)", lab) || grepl("Total Cholesterol \\(n = 1\\)", lab))
stopifnot(grepl("Weight \\(n = 1\\)", lab))

# 全 0 也要出分项
df0 <- data.frame(
  TCBI = 1:3,
  Triglycerides = c(100, 110, 120),
  Total_Cholesterol = c(200, 210, 220),
  Weight = c(60, 61, 62)
)
lab0 <- attrition_index_component_missing_label(df0, "TCBI")
stopifnot(grepl("\\(n = 0\\)", lab0))
stopifnot(grepl("Triglycerides", lab0))

# config_steps_only 不被 log 覆盖
ctx <- list(
  config = list(
    attrition = list(
      config_steps_only = TRUE,
      steps = list(
        list(id = "starting_cohort", label = "Start", source = "fixed", n = 100L),
        list(
          id = "after_age_filter", label = "Age >= 45", source = "fixed",
          n = 80L, exclude_label = "Age < 45 years"
        )
      )
    ),
    data = list(outcome_column = "y"),
    project = list(analysis_group = "1", reference_group = "0")
  ),
  data = list(imputed = data.frame(y = factor(c(0, 1, 0, 1)))),
  results = list(
    attrition = list(log = list(
      list(
        step_id = "after_age_filter", label = "Age filter (excluded 0)",
        n = 80L, kind = "include",
        meta = list(exclude_label = NA_character_)
      )
    ))
  )
)
rows <- attrition_finalize_rows(ctx, ctx$config)
age <- rows[rows$step_id == "after_age_filter", , drop = FALSE]
stopifnot(nrow(age) == 1L)
stopifnot(identical(as.character(age$exclude_label[1L]), "Age < 45 years"))
stopifnot(identical(as.integer(rows$n[rows$step_id == "starting_cohort"][1L]), 100L))

cat("test_attrition_ml_component_label: OK\n")
