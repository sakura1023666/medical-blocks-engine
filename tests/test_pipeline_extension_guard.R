# tests/test_pipeline_extension_guard.R — TDD for pipeline extension hard-stop guard
root <- normalizePath(".")
source(file.path(root, "R/pipeline_extension_guard.R"))

base <- list(pipeline_tail = c(
  "qgcomp_environment", "mediation_ers_environment", "subgroup_environment_or"
))

# illegal extra (no extensions.json)
bad <- list(pipeline_tail = c(base$pipeline_tail, "plot_histogram"))
study <- tempfile("st_")
dir.create(study)
err <- tryCatch(
  pipeline_extension_guard_check("environment", bad, study, root),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(err), grepl("extensions.json|非法", err))

# legal via extensions.json (tail_end → suffix OK)
ok_pipes <- bad
writeLines(jsonlite::toJSON(list(version = 1, extensions = list(list(
  slot = "environment.tail_end", block = "plot_histogram", pipeline_key = "pipeline_tail"
))), auto_unbox = TRUE, pretty = TRUE), file.path(study, "extensions.json"))
pipeline_extension_guard_check("environment", ok_pipes, study, root)

# mid-chain insert still illegal even with extensions.json claiming end
mid <- list(pipeline_tail = c(
  "qgcomp_environment", "plot_histogram",
  "mediation_ers_environment", "subgroup_environment_or"
))
err_mid <- tryCatch(
  pipeline_extension_guard_check("environment", mid, study, root),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(err_mid), grepl("位置|position|非法|suffix|末尾", err_mid, ignore.case = TRUE))

# baseline match + no extensions.json → OK
study2 <- tempfile("st2_")
dir.create(study2)
pipeline_extension_guard_check("environment", base, study2, root)

cat("OK guard\n")
