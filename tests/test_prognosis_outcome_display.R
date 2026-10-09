root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)

cfg_prognosis <- list(
  project = list(
    study_type = "prognosis",
    disease = "AKI",
    analysis_group = "1",
    reference_group = "0"
  ),
  survival = list(outcome_label = "28-day all-cause mortality")
)

prognosis_labels <- pipeline_resolve_outcome_display_labels(cfg_prognosis)
stopifnot(identical(prognosis_labels$analysis, "Non-survivor"))
stopifnot(identical(prognosis_labels$reference, "Survivor"))

for (field in c("reference_group_label", "control_group", "noncase_label")) {
  cfg_explicit <- cfg_prognosis
  cfg_explicit$project[[field]] <- paste("Explicit", field)
  explicit_labels <- pipeline_resolve_outcome_display_labels(cfg_explicit)
  stopifnot(identical(explicit_labels$reference, paste("Explicit", field)))
}

cfg_priority <- cfg_prognosis
cfg_priority$project$reference_group_label <- "Preferred survivor label"
cfg_priority$project$control_group <- "Lower-priority control label"
cfg_priority$project$noncase_label <- "Lower-priority noncase label"
priority_labels <- pipeline_resolve_outcome_display_labels(cfg_priority)
stopifnot(identical(priority_labels$reference, "Preferred survivor label"))

cfg_skip_codes <- cfg_prognosis
cfg_skip_codes$project$reference_group_label <- "0"
cfg_skip_codes$project$control_group <- "Readable control label"
skip_code_labels <- pipeline_resolve_outcome_display_labels(cfg_skip_codes)
stopifnot(identical(skip_code_labels$reference, "Readable control label"))

cfg_direct <- cfg_prognosis
cfg_direct$project$analysis_group <- "Death by day 28"
cfg_direct$project$reference_group <- "Alive by day 28"
direct_labels <- pipeline_resolve_outcome_display_labels(cfg_direct)
stopifnot(identical(direct_labels$analysis, "Death by day 28"))
stopifnot(identical(direct_labels$reference, "Alive by day 28"))

cfg_chain <- cfg_prognosis
cfg_chain$project$control_group <- "Alive at day 28"
normalized_cfg <- pipeline_normalize_project_outcome_labels(cfg_chain)
stopifnot(identical(normalized_cfg$project$analysis_group, "Non-survivor"))
stopifnot(identical(normalized_cfg$project$reference_group, "Alive at day 28"))

raw_outcome <- data.frame(fustatus = c(0L, 1L, 0L, 1L))
display_outcome <- pipeline_relabel_binary_outcome_column(
  raw_outcome,
  cfg_chain,
  col = "fustatus"
)
stopifnot(identical(
  levels(display_outcome$fustatus),
  c("Alive at day 28", "Non-survivor")
))
stopifnot(identical(
  as.character(display_outcome$fustatus),
  c("Alive at day 28", "Non-survivor", "Alive at day 28", "Non-survivor")
))
stopifnot(identical(
  pipeline_outcome_as_01(display_outcome$fustatus, normalized_cfg),
  c(0, 1, 0, 1)
))
stopifnot(identical(
  pipeline_outcome_as_01(raw_outcome$fustatus, cfg_chain),
  c(0, 1, 0, 1)
))

cfg_incidence <- list(
  project = list(
    study_type = "incidence",
    disease = "AKI",
    analysis_group = "1",
    reference_group = "0"
  )
)

incidence_labels <- pipeline_resolve_outcome_display_labels(cfg_incidence)
stopifnot(identical(incidence_labels$analysis, "AKI"))
stopifnot(identical(incidence_labels$reference, "No AKI"))

cat("test_prognosis_outcome_display.R: OK\n")
