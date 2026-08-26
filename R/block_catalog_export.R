###############################################################################
#  R/block_catalog_export.R — read-only block catalog from pipeline_block_sources
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

export_block_catalog <- function(root, out_dir, tags_map = list()) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
  }
  src <- pipeline_block_sources(root)
  blocks <- lapply(names(src), function(id) {
    list(
      block_id = id,
      path_rel = sub(
        paste0("^", root, "/?"),
        "",
        normalizePath(src[[id]], winslash = "/", mustWork = FALSE)
      ),
      tags = as.character(tags_map[[id]] %||% character(0)),
      routines = character(0),
      summary = id
    )
  })
  payload <- list(
    version = 1L,
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    blocks = blocks
  )
  jsonlite::write_json(
    payload,
    file.path(out_dir, "catalog.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  writeLines(
    c("# Block catalog (read-only)", "", paste0("- `", names(src), "`")),
    file.path(out_dir, "catalog.md")
  )
  hook_src <- file.path(root, "configs/study_interface/hook_slots.yaml")
  if (!file.exists(hook_src)) {
    stop("hook_slots.yaml 缺失: ", hook_src, call. = FALSE)
  }
  file.copy(hook_src, file.path(out_dir, "hook_slots.yaml"), overwrite = TRUE)
  writeLines(payload$generated_at, file.path(out_dir, "GENERATED_AT.txt"))
  invisible(out_dir)
}
