#!/usr/bin/env Rscript
###############################################################################
#  scripts/run_programmer_block_hooks_cli.R
#
#  CLI dispatcher for programmer block hooks.
#  Subcommands: search | list-slots | add | remove
#
#  Usage:
#    Rscript run_programmer_block_hooks_cli.R search --catalog DIR [--routine R] [--tag T] [query]
#    Rscript run_programmer_block_hooks_cli.R list-slots --catalog DIR [--routine R]
#    Rscript run_programmer_block_hooks_cli.R add --study-dir DIR --catalog-dir DIR --slot ID --block ID
#    Rscript run_programmer_block_hooks_cli.R remove --study-dir DIR --catalog-dir DIR --slot ID --block ID
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.args_usage <- function() {
  cat(
    "用法:\n",
    "  search      --catalog DIR [--routine R] [--tag T] [query]\n",
    "  list-slots  --catalog DIR [--routine R]\n",
    "  add         --study-dir DIR --catalog-dir DIR --slot ID --block ID\n",
    "  remove      --study-dir DIR --catalog-dir DIR --slot ID --block ID\n",
    sep = ""
  )
}

.parse_flags <- function(args, required = character(), optional = character()) {
  out <- as.list(setNames(rep(list(NULL), length(c(required, optional))),
                 c(required, optional)))
  pos <- character(0)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      if (!(key %in% c(required, optional))) {
        stop("未知参数: --", key, call. = FALSE)
      }
      if (i >= length(args)) {
        stop("参数 --", key, " 缺少值", call. = FALSE)
      }
      out[[key]] <- args[[i + 1L]]
      i <- i + 2L
    } else {
      pos <- c(pos, a)
      i <- i + 1L
    }
  }
  missing <- required[vapply(required, function(k) {
    is.null(out[[k]]) || !nzchar(out[[k]])
  }, logical(1))]
  if (length(missing)) {
    stop("缺少必需参数: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  list(flags = out, positional = pos)
}

.fmt_vec <- function(x) {
  if (is.null(x) || !length(x)) return("-")
  paste(as.character(unlist(x, use.names = FALSE)), collapse = ", ")
}

.cmd_search <- function(catalog_dir, flags, positional) {
  catalog_path <- file.path(catalog_dir, "catalog.json")
  query <- if (length(positional)) positional[[1]] else NULL
  hits <- hooks_search_blocks(
    catalog_path,
    query = query,
    routine = flags$routine,
    tag = flags$tag
  )
  if (!length(hits)) {
    cat("(无匹配 block)\n")
    return(invisible(hits))
  }
  for (b in hits) {
    cat(sprintf(
      "%-40s  %s\n  routines: %s  tags: %s\n",
      b$block_id %||% "",
      b$summary %||% "",
      .fmt_vec(b$routines),
      .fmt_vec(b$tags)
    ))
  }
  cat(sprintf("\n共 %d 个 block\n", length(hits)))
  invisible(hits)
}

.cmd_list_slots <- function(catalog_dir, flags) {
  slots_path <- file.path(catalog_dir, "hook_slots.yaml")
  slots <- hooks_list_slots(slots_path, routine = flags$routine)
  if (!length(slots)) {
    cat("(无匹配 slot)\n")
    return(invisible(slots))
  }
  for (s in slots) {
    anchor <- s$anchor_block
    if (is.null(anchor) || !nzchar(anchor)) anchor <- "-"
    cat(sprintf(
      "%-40s  routine=%s  pipeline=%s  position=%s  anchor=%s\n  %s\n",
      s$id,
      s$routine,
      s$pipeline_key,
      s$position,
      anchor,
      s$description %||% ""
    ))
  }
  cat(sprintf("\n共 %d 个 slot\n", length(slots)))
  invisible(slots)
}

.study_name_from_dir <- function(study_dir) {
  basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE))
}

.cmd_add <- function(flags) {
  root <- normalizePath(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
    winslash = "/",
    mustWork = TRUE
  )
  study_dir <- normalizePath(flags$`study-dir`, winslash = "/", mustWork = TRUE)
  catalog_dir <- normalizePath(flags$`catalog-dir`, winslash = "/", mustWork = TRUE)
  res <- hooks_add_block(
    study_dir = study_dir,
    slot_id = flags$slot,
    block_id = flags$block,
    root = root,
    catalog_dir = catalog_dir
  )
  study <- .study_name_from_dir(study_dir)
  if (isTRUE(res$skipped)) {
    cat(sprintf(
      "已存在挂接 slot=%s block=%s；未写入。\n",
      res$slot, res$block
    ))
  } else {
    cat(sprintf(
      "已挂接 slot=%s block=%s → %s\n决策树: %s\n",
      res$slot, res$block, res$pipeline_key, res$tree
    ))
  }
  cat(sprintf("\n下次运行: ./run_study.sh %s\n", study))
  invisible(res)
}

.cmd_remove <- function(flags) {
  root <- normalizePath(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
    winslash = "/",
    mustWork = TRUE
  )
  study_dir <- normalizePath(flags$`study-dir`, winslash = "/", mustWork = TRUE)
  catalog_dir <- normalizePath(flags$`catalog-dir`, winslash = "/", mustWork = TRUE)
  res <- hooks_remove_block(
    study_dir = study_dir,
    slot_id = flags$slot,
    block_id = flags$block,
    root = root,
    catalog_dir = catalog_dir
  )
  study <- .study_name_from_dir(study_dir)
  cat(sprintf(
    "已移除 slot=%s block=%s（%s）\n决策树: %s\n",
    res$slot, res$block, res$pipeline_key, res$tree
  ))
  cat(sprintf("\n下次运行: ./run_study.sh %s\n", study))
  invisible(res)
}

# ── main ─────────────────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  .args_usage()
  stop("缺少子命令", call. = FALSE)
}

cmd <- args[[1]]
rest <- args[-1]

root <- normalizePath(
  Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
  winslash = "/",
  mustWork = TRUE
)
source(file.path(root, "R/programmer_block_hooks.R"))

switch(
  cmd,
  search = {
    parsed <- .parse_flags(
      rest,
      required = "catalog",
      optional = c("routine", "tag")
    )
    .cmd_search(parsed$flags$catalog, parsed$flags, parsed$positional)
  },
  `list-slots` = {
    parsed <- .parse_flags(rest, required = "catalog", optional = "routine")
    .cmd_list_slots(parsed$flags$catalog, parsed$flags)
  },
  add = {
    parsed <- .parse_flags(
      rest,
      required = c("study-dir", "catalog-dir", "slot", "block"),
      optional = character(0)
    )
    .cmd_add(parsed$flags)
  },
  remove = {
    parsed <- .parse_flags(
      rest,
      required = c("study-dir", "catalog-dir", "slot", "block"),
      optional = character(0)
    )
    .cmd_remove(parsed$flags)
  },
  {
    .args_usage()
    stop("未知子命令: ", cmd, call. = FALSE)
  }
)
