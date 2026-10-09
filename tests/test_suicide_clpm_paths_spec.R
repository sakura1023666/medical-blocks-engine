#!/usr/bin/env Rscript
# Spec tests for suicide CLPM nine-path registry (Task 6).
# Run: Rscript tests/test_suicide_clpm_paths_spec.R

engine_root <- normalizePath(getwd(), winslash = "/")
# Allow running from engine root or tests/
if (basename(engine_root) == "tests") {
  engine_root <- normalizePath(file.path(engine_root, ".."), winslash = "/")
}
setwd(engine_root)

src <- file.path(engine_root, "run/cross_lagged/run_suicide_clpm_paths.R")
stopifnot(file.exists(src))

options(suicide_clpm_paths_specs_only = TRUE)
sys.source(src, envir = environment())
options(suicide_clpm_paths_specs_only = FALSE)

paths <- suicide_clpm_path_specs()
nodes <- suicide_clpm_nodes()

stopifnot(length(paths) == 9L)
expected_names <- c(
  "HAMD_AR", "HAMA_AR", "CSSRS_AR",
  "HAMD_to_CSSRS", "HAMA_to_CSSRS",
  "CSSRS_to_HAMD", "CSSRS_to_HAMA",
  "HAMD_to_HAMA", "HAMA_to_HAMD"
)
got_names <- vapply(paths, function(p) p$name, character(1))
stopifnot(identical(got_names, expected_names))

logit_paths <- Filter(function(p) identical(p$type, "logit"), paths)
stopifnot(length(logit_paths) >= 1L)
for (p in logit_paths) {
  focus <- if (!is.null(p$focus) && nzchar(p$focus)) p$focus else p$x[[1L]]
  stopifnot(is.character(focus), length(focus) == 1L, nzchar(focus))
  stopifnot(focus %in% p$x)
  # CSSRS outcome logit focuses must be among predictors
  stopifnot(identical(p$y, "CSSRS_1st"))
}

# Sample Model2 must not contain CLPM nodes
m2_candidates <- c(
  file.path(engine_root, ".superpowers/sdd/study_mirror/covariates/Model2Factors.txt"),
  file.path(engine_root, "covariates/Model2Factors.txt")
)
m2_path <- m2_candidates[file.exists(m2_candidates)][1L]
if (is.na(m2_path) || !nzchar(m2_path)) {
  # Synthetic sample (mirrors Task5 locked set shape)
  sample_m2 <- c("age", "sex", "education", "Weight", "Height")
} else {
  sample_m2 <- trimws(readLines(m2_path, warn = FALSE))
  sample_m2 <- sample_m2[nzchar(sample_m2)]
}
leak <- intersect(sample_m2, nodes)
if (length(leak)) {
  stop("Nodes leaked into Model2 sample: ", paste(leak, collapse = ", "))
}

message("OK suicide_clpm_paths_spec: n_paths=", length(paths),
        " logit=", length(logit_paths),
        " Model2_n=", length(sample_m2),
        " nodes_not_in_Model2=TRUE")
