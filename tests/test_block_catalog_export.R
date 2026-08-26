# tests/test_block_catalog_export.R
root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/block_catalog_export.R"))
tmpdir <- tempfile("cat_")
dir.create(tmpdir)
export_block_catalog(root, tmpdir)

# All four expected outputs must exist
expected_files <- c(
  "catalog.json",
  "catalog.md",
  "hook_slots.yaml",
  "GENERATED_AT.txt"
)
stopifnot(all(file.exists(file.path(tmpdir, expected_files))))

j <- jsonlite::fromJSON(file.path(tmpdir, "catalog.json"), simplifyVector = FALSE)
reg <- names(pipeline_block_sources(root))
ids <- vapply(j$blocks, function(x) x$block_id, character(1))

# Catalog ids must match registry exactly (same length and same set)
stopifnot(length(ids) == length(reg))
stopifnot(setequal(ids, reg))

stopifnot(!"__not_a_real_block__" %in% ids)

# Each block entry must expose required schema fields
required_fields <- c("block_id", "path_rel", "tags", "routines", "summary")
stopifnot(all(vapply(j$blocks, function(x) {
  all(required_fields %in% names(x))
}, logical(1))))

# Must not create files under Blocks/
stopifnot(!file.exists(file.path(root, "Blocks", ".catalog_write_probe")))
cat("OK catalog export\n")
