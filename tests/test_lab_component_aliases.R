#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(getwd(), winslash = "/"))
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(root, "Blocks/00_index/01block_index.R"), local = FALSE)
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "Blocks/03_imputation/03block_analysis_exclusion.R"), local = FALSE)

stopifnot(exists("pipeline_expand_lab_var_aliases", mode = "function"))
exp <- pipeline_expand_lab_var_aliases(c("Triglycerides", "Total_Cholesterol", "Weight"))
stopifnot(all(c("TG", "TC", "Weight", "Triglycerides", "Total_Cholesterol") %in% exp))

cfg <- list(
  incidence = list(index_var = "TCBI"),
  analysis_exclusion = list(
    enable = TRUE,
    disease_vars = character(0),
    protect_vars = c("Age", "Weight"),
    exclude_other_composite_indices = FALSE
  )
)
data_names <- c(
  "ID", "Age", "Gender", "TG", "TC", "Weight", "Triglycerides",
  "Total_Cholesterol", "Glucose", "TCBI", "dbp23"
)
man <- pipeline_analysis_exclusion_manifest(cfg, data_names)
# protect Weight：可留列；TG/TC 必须进 drop
stopifnot(all(c("TG", "TC", "Triglycerides", "Total_Cholesterol") %in% man$drop_vars))
stopifnot(!"Weight" %in% man$drop_vars)
stopifnot(!"TCBI" %in% man$drop_vars)

comps <- pipeline_index_component_vars_only(cfg)
stopifnot(all(c("TG", "TC", "Weight") %in% comps))

kept <- pipeline_strip_exposure_component_vars(
  c("Age", "Gender", "TC", "TG", "Glucose", "TCBI", "dbp23"),
  cfg,
  label = "test"
)
stopifnot(identical(sort(kept), sort(c("Age", "Gender", "Glucose", "TCBI", "dbp23"))))
stopifnot(!any(c("TC", "TG") %in% kept))

cat("test_lab_component_aliases: OK\n")
