# tests/test_hook_slots_schema.R
source("R/utils.R")  # if %||% needed; else pure base
path <- "configs/study_interface/hook_slots.yaml"
stopifnot(file.exists(path))
# Prefer yaml::read_yaml if installed; else stop with install hint in real impl.
# Minimal assertion without yaml: file must contain these slot ids as text for Task1 bootstrap,
# replaced by structured parse in Task2.
txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
need <- c(
  "environment.tail_after_mediation",
  "incidence.nhanes_after_mediation",
  "survival.after_subgroup_prognosis",
  "ml.primary_after_shap"
)
for (id in need) stopifnot(grepl(id, txt, fixed = TRUE))
cat("OK schema text presence\n")
