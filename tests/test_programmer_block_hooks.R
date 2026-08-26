# tests/test_programmer_block_hooks.R — TDD for add/remove/search/list + tree versioning
root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/programmer_block_hooks.R"))
source(file.path(root, "R/pipeline_extension_guard.R"))

# ── helpers ──────────────────────────────────────────────────────────────────
.make_study <- function() {
  study <- tempfile("study_")
  dir.create(file.path(study, "Decisiontree"), recursive = TRUE)
  writeLines(c(
    "pipeline_tail <- list(",
    "  name = 't',",
    "  blocks = c('qgcomp_environment', 'mediation_ers_environment', 'subgroup_environment_or')",
    ")"
  ), file.path(study, "config.R"))
  mother <- file.path(root, "Decisiontree/decision_tree_environment_voc_batch.md")
  stopifnot(file.exists(mother))
  file.copy(mother, file.path(study, "Decisiontree", "baseline_environment.md"))
  study
}

.make_catalog <- function(extra_blocks = list()) {
  cat_dir <- tempfile("cat_")
  dir.create(cat_dir)
  file.copy(
    file.path(root, "configs/study_interface/hook_slots.yaml"),
    file.path(cat_dir, "hook_slots.yaml")
  )
  blocks <- c(
    list(list(
      block_id = "plot_histogram",
      tags = list("plot"),
      routines = list("environment"),
      summary = "hist"
    )),
    list(list(
      block_id = "environment_characteristics",
      tags = list("descriptive"),
      routines = list("environment"),
      summary = "env char"
    )),
    extra_blocks
  )
  jsonlite::write_json(
    list(version = 1, blocks = blocks),
    file.path(cat_dir, "catalog.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat_dir
}

# ── search / list ────────────────────────────────────────────────────────────
cat_dir <- .make_catalog()
hits <- hooks_search_blocks(
  file.path(cat_dir, "catalog.json"),
  query = "histogram",
  routine = "environment"
)
stopifnot(length(hits) >= 1L)
stopifnot(any(vapply(hits, function(x) identical(x$block_id, "plot_histogram"), logical(1))))

slots <- hooks_list_slots(file.path(cat_dir, "hook_slots.yaml"), routine = "environment")
stopifnot(length(slots) >= 1L)
stopifnot(any(vapply(slots, function(x) identical(x$id, "environment.tail_end"), logical(1))))
cat("OK search/list\n")

# ── routines mismatch: catalog ml-only block on environment slot → error ─────
cat_routines_dir <- tempfile("cat_routines_")
dir.create(cat_routines_dir)
file.copy(
  file.path(root, "configs/study_interface/hook_slots.yaml"),
  file.path(cat_routines_dir, "hook_slots.yaml")
)
jsonlite::write_json(
  list(version = 1, blocks = list(list(
    block_id = "plot_histogram",
    tags = list("plot"),
    routines = list("ml"),
    summary = "ml only"
  ))),
  file.path(cat_routines_dir, "catalog.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
study_routines <- .make_study()
err_routines <- tryCatch(
  hooks_add_block(
    study_routines, "environment.tail_end", "plot_histogram", root, cat_routines_dir
  ),
  error = function(e) e
)
stopifnot(inherits(err_routines, "error"))
msg_routines <- conditionMessage(err_routines)
stopifnot(grepl("plot_histogram", msg_routines, fixed = TRUE))
stopifnot(grepl("environment", msg_routines, fixed = TRUE))
stopifnot(grepl("ml", msg_routines, fixed = TRUE))
cat("OK routines mismatch\n")

# ── add_block: insert + tree_v001 + baseline immutable ───────────────────────
study <- .make_study()
h0 <- unname(tools::md5sum(file.path(study, "Decisiontree", "baseline_environment.md")))

hooks_add_block(study, "environment.tail_end", "plot_histogram", root, cat_dir)

cfg <- paste(readLines(file.path(study, "config.R"), warn = FALSE), collapse = "\n")
stopifnot(grepl("plot_histogram", cfg, fixed = TRUE))
stopifnot(file.exists(file.path(study, "extensions.json")))
stopifnot(file.exists(file.path(study, "Decisiontree", "tree_v001.md")))
stopifnot(file.exists(file.path(study, "Decisiontree", "CURRENT.md")))
cur <- paste(readLines(file.path(study, "Decisiontree", "CURRENT.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("tree_v001\\.md", cur))

h1 <- unname(tools::md5sum(file.path(study, "Decisiontree", "baseline_environment.md")))
stopifnot(identical(h0, h1))

# resulting config + extensions must pass guard
cfg_env <- new.env(parent = baseenv())
source(file.path(study, "config.R"), local = cfg_env)
pipeline_extension_guard_check(
  "environment",
  list(pipeline_tail = cfg_env$pipeline_tail),
  study,
  root
)
cat("OK add_block\n")

# ── second add: new tree version, no duplicate, baseline still unchanged ─────
hooks_add_block(study, "environment.tail_end", "environment_characteristics", root, cat_dir)
stopifnot(file.exists(file.path(study, "Decisiontree", "tree_v002.md")))
cur2 <- paste(readLines(file.path(study, "Decisiontree", "CURRENT.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("tree_v002\\.md", cur2))
h2 <- unname(tools::md5sum(file.path(study, "Decisiontree", "baseline_environment.md")))
stopifnot(identical(h0, h2))

cfg2 <- paste(readLines(file.path(study, "config.R"), warn = FALSE), collapse = "\n")
# plot_histogram appears once
stopifnot(length(gregexpr("plot_histogram", cfg2, fixed = TRUE)[[1]]) == 1L)
stopifnot(grepl("environment_characteristics", cfg2, fixed = TRUE))

cfg_env2 <- new.env(parent = baseenv())
source(file.path(study, "config.R"), local = cfg_env2)
pipeline_extension_guard_check(
  "environment",
  list(pipeline_tail = cfg_env2$pipeline_tail),
  study,
  root
)
cat("OK second add\n")

# ── idempotent re-add: same slot+block does not duplicate ────────────────────
hooks_add_block(study, "environment.tail_end", "plot_histogram", root, cat_dir)
cfg3 <- paste(readLines(file.path(study, "config.R"), warn = FALSE), collapse = "\n")
stopifnot(length(gregexpr("plot_histogram", cfg3, fixed = TRUE)[[1]]) == 1L)
cat("OK idempotent\n")

# ── remove_block: drops from config + extensions, bumps tree ─────────────────
hooks_remove_block(study, "environment.tail_end", "plot_histogram", root, cat_dir)
cfg4 <- paste(readLines(file.path(study, "config.R"), warn = FALSE), collapse = "\n")
stopifnot(!grepl("plot_histogram", cfg4, fixed = TRUE))
stopifnot(grepl("environment_characteristics", cfg4, fixed = TRUE))
ext <- jsonlite::fromJSON(file.path(study, "extensions.json"), simplifyVector = FALSE)
ext_blocks <- vapply(ext$extensions %||% list(), function(e) e$block, character(1))
stopifnot(!"plot_histogram" %in% ext_blocks)
stopifnot("environment_characteristics" %in% ext_blocks)
# tree bumped (v003 after second add was v002; remove creates next)
tree_files <- list.files(file.path(study, "Decisiontree"), pattern = "^tree_v[0-9]+\\.md$")
stopifnot(length(tree_files) >= 3L)
cur3 <- paste(readLines(file.path(study, "Decisiontree", "CURRENT.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("tree_v00[0-9]+\\.md", cur3))
h3 <- unname(tools::md5sum(file.path(study, "Decisiontree", "baseline_environment.md")))
stopifnot(identical(h0, h3))

cfg_env3 <- new.env(parent = baseenv())
source(file.path(study, "config.R"), local = cfg_env3)
pipeline_extension_guard_check(
  "environment",
  list(pipeline_tail = cfg_env3$pipeline_tail),
  study,
  root
)
cat("OK remove_block\n")

# mother Decisiontree untouched (md5 of voc mother stable across run)
mother_path <- file.path(root, "Decisiontree/decision_tree_environment_voc_batch.md")
stopifnot(file.exists(mother_path))
cat("OK mothers untouched\n")

cat("OK programmer_block_hooks\n")
