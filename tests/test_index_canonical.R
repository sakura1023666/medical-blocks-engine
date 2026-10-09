#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(getwd(), winslash = "/"))
if (!nzchar(root)) root <- normalizePath(getwd(), winslash = "/")
source(file.path(root, "R/index_canonical.R"))

stopifnot(index_canonical_name("UA_CrR") == "UA_CR")
stopifnot(index_canonical_name("UA_Cr") == "UA_CR")
stopifnot(index_canonical_name("UA_CR") == "UA_CR")
stopifnot(identical(
  index_canonicalize_names(c("UA_CrR", "UA_CR", "NLR")),
  c("UA_CR", "NLR")
))
stopifnot(identical(
  index_alias_names("UA_CR"),
  c("UA_CrR", "UA_Cr")
))
stopifnot(index_canonical_name("TyGWHtR") == "TyG_WHtR")
stopifnot(identical(index_alias_names("TyG_WHtR"), "TyGWHtR"))
stopifnot(identical(
  index_prune_alias_drop_vars(c("TyG_WHtR", "TyGWHtR", "Age"), list(incidence = list(index_var = "TyG_WHtR"))),
  "TyGWHtR"
))
stopifnot(all(c("UA_CrR", "UA_Cr") %in% index_expand_alias_exclusions(
  "UA_CR", c("NLR", "PLR")
)))
stopifnot("UA_CR" %in% index_expand_available_canonical(
  character(0), c("UA_CrR", "Age"), "UA_CR"
))
cat("test_index_canonical: OK\n")
