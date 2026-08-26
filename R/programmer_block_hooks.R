###############################################################################
#  R/programmer_block_hooks.R — search / add / remove / versioned decision trees
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Mother decision-tree map (engine Decisiontree/; never mutate mothers)
.hooks_mother_rel <- list(
  environment = "Decisiontree/decision_tree_environment_voc_batch.md",
  incidence   = "Decisiontree/decision_tree_incidence_dual_batch.md",
  survival    = "Decisiontree/decision_tree_survival_dual_batch.md",
  ml          = "Decisiontree/decision_tree_ml_dual_batch.md",
  trajectory  = "Decisiontree/decision_tree_trajectory_prognosis_apri.md",
  competing   = "Decisiontree/decision_tree_competing_risk_stroke.md",
  ipw         = "Decisiontree/decision_tree_ipw_diabetes_stroke.md",
  crm         = "Decisiontree/decision_tree_crm_nhanes_mr.md",
  tst         = "Decisiontree/decision_tree_two_stage_transformer_stroke.md"
)

.hooks_require_jsonlite <- function() {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
  }
}

.hooks_load_catalog <- function(catalog_path) {
  .hooks_require_jsonlite()
  if (!file.exists(catalog_path)) {
    stop("catalog 不存在: ", catalog_path, call. = FALSE)
  }
  raw <- jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
  raw$blocks %||% list()
}

.hooks_load_slots_file <- function(slots_path) {
  if (!file.exists(slots_path)) {
    stop("hook_slots 不存在: ", slots_path, call. = FALSE)
  }
  if (requireNamespace("yaml", quietly = TRUE)) {
    raw <- yaml::read_yaml(slots_path)
    slots <- raw$slots %||% list()
  } else {
    lines <- readLines(slots_path, warn = FALSE)
    slots <- list()
    cur <- NULL
    flush_cur <- function() {
      if (!is.null(cur) && !is.null(cur$id)) slots[[length(slots) + 1L]] <<- cur
      cur <<- NULL
    }
    for (ln in lines) {
      if (grepl("^\\s*-\\s*id:", ln)) {
        flush_cur()
        cur <- list(id = sub("^\\s*-\\s*id:\\s*", "", ln))
      } else if (!is.null(cur) && grepl("^\\s+routine:", ln)) {
        cur$routine <- sub("^\\s+routine:\\s*", "", ln)
      } else if (!is.null(cur) && grepl("^\\s+pipeline_key:", ln)) {
        cur$pipeline_key <- sub("^\\s+pipeline_key:\\s*", "", ln)
      } else if (!is.null(cur) && grepl("^\\s+anchor_block:", ln)) {
        v <- sub("^\\s+anchor_block:\\s*", "", ln)
        cur$anchor_block <- if (identical(v, "null")) NULL else v
      } else if (!is.null(cur) && grepl("^\\s+position:", ln)) {
        cur$position <- sub("^\\s+position:\\s*", "", ln)
      } else if (!is.null(cur) && grepl("^\\s+max_extra:", ln)) {
        cur$max_extra <- as.integer(sub("^\\s+max_extra:\\s*", "", ln))
      } else if (!is.null(cur) && grepl("^\\s+allow_tags:", ln)) {
        # next lines may be YAML list; store raw for "*"-only fallback
        cur$allow_tags <- "*"
      } else if (!is.null(cur) && grepl("^\\s+description:", ln)) {
        cur$description <- sub("^\\s+description:\\s*\"?", "", ln)
        cur$description <- sub("\"\\s*$", "", cur$description)
      }
    }
    flush_cur()
  }
  lapply(slots, function(s) {
    list(
      id = s$id %||% NA_character_,
      routine = s$routine %||% NA_character_,
      pipeline_key = s$pipeline_key %||% NA_character_,
      anchor_block = s$anchor_block,
      position = s$position %||% NA_character_,
      allow_tags = {
        at <- s$allow_tags
        if (is.null(at)) "*" else as.character(unlist(at, use.names = FALSE))
      },
      max_extra = as.integer(s$max_extra %||% 8L),
      description = s$description %||% ""
    )
  })
}

.hooks_slot_by_id <- function(slots, slot_id) {
  for (s in slots) {
    if (identical(s$id, slot_id)) return(s)
  }
  NULL
}

.hooks_load_extensions <- function(study_dir) {
  .hooks_require_jsonlite()
  path <- file.path(study_dir, "extensions.json")
  if (!file.exists(path)) {
    return(list(version = 1L, extensions = list()))
  }
  raw <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  list(
    version = as.integer(raw$version %||% 1L),
    extensions = raw$extensions %||% list()
  )
}

.hooks_write_extensions <- function(study_dir, doc) {
  .hooks_require_jsonlite()
  path <- file.path(study_dir, "extensions.json")
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(doc, tmp, auto_unbox = TRUE, pretty = TRUE)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  invisible(path)
}

.hooks_registered_ids <- function(root) {
  if (!exists("pipeline_block_sources", mode = "function")) {
    pr <- file.path(root, "R/pipeline_runner.R")
    if (!file.exists(pr)) {
      stop("无法加载 pipeline_block_sources: 缺少 ", pr, call. = FALSE)
    }
    source(pr, local = FALSE)
  }
  names(pipeline_block_sources(root))
}

.hooks_parse_c_strings <- function(content) {
  # Extract '...' or "..." tokens from blocks = c(...) body
  m <- gregexpr("(['\"])([^'\"]*)\\1", content, perl = TRUE)
  if (m[[1]][1] < 0) return(character(0))
  starts <- as.integer(m[[1]])
  lens <- attr(m[[1]], "match.length")
  vapply(seq_along(starts), function(i) {
    tok <- substr(content, starts[i], starts[i] + lens[i] - 1L)
    substr(tok, 2L, nchar(tok) - 1L)
  }, character(1))
}

.hooks_find_blocks_c_span <- function(full, pipeline_key) {
  start_pat <- paste0(pipeline_key, "\\s*<-\\s*list\\s*\\(")
  m <- regexpr(start_pat, full, perl = TRUE)
  if (m < 1) {
    stop(
      "无法安全解析 config: 未找到 ", pipeline_key, " <- list(",
      call. = FALSE
    )
  }
  after_list <- as.integer(m) + attr(m, "match.length")
  rest <- substr(full, after_list, nchar(full))
  bm <- regexpr("blocks\\s*=\\s*c\\s*\\(", rest, perl = TRUE)
  if (bm < 1) {
    stop(
      "无法安全解析 config: 在 ", pipeline_key,
      " 中未找到 blocks = c(",
      call. = FALSE
    )
  }
  # bm is 1-based within `rest`; absolute start of "blocks..." match:
  c_kw_start <- after_list + as.integer(bm) - 1L
  # absolute position of '(' closing the regex match:
  c_open <- after_list + as.integer(bm) + attr(bm, "match.length") - 2L
  # c_open points at '(' of c(
  i <- c_open + 1L
  depth <- 1L
  n <- nchar(full)
  in_squote <- FALSE
  in_dquote <- FALSE
  while (i <= n && depth > 0L) {
    ch <- substr(full, i, i)
    if (in_squote) {
      if (ch == "'") in_squote <- FALSE
    } else if (in_dquote) {
      if (ch == "\"") in_dquote <- FALSE
    } else if (ch == "'") {
      in_squote <- TRUE
    } else if (ch == "\"") {
      in_dquote <- TRUE
    } else if (ch == "(") {
      depth <- depth + 1L
    } else if (ch == ")") {
      depth <- depth - 1L
      if (depth == 0L) break
    }
    i <- i + 1L
  }
  if (depth != 0L) {
    stop("无法安全解析 config: blocks = c(...) 括号不匹配", call. = FALSE)
  }
  list(
    c_kw_start = c_kw_start,
    c_open = c_open,
    c_close = i,
    content = substr(full, c_open + 1L, i - 1L)
  )
}

.hooks_format_blocks_c <- function(blocks) {
  if (!length(blocks)) return("c()")
  paste0("c(", paste(sprintf("'%s'", blocks), collapse = ", "), ")")
}

.hooks_atomic_write <- function(path, lines) {
  tmp <- paste0(path, ".tmp")
  writeLines(lines, tmp, useBytes = FALSE)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  invisible(path)
}

.hooks_rewrite_pipeline_blocks <- function(config_path, pipeline_key, new_blocks) {
  full <- paste(readLines(config_path, warn = FALSE), collapse = "\n")
  span <- tryCatch(
    .hooks_find_blocks_c_span(full, pipeline_key),
    error = function(e) stop(conditionMessage(e), call. = FALSE)
  )
  new_c <- .hooks_format_blocks_c(new_blocks)
  # Replace from "blocks = c(" through closing ")"
  # span$c_kw_start is start of "blocks"; find exact "blocks = c(" start
  prefix <- substr(full, 1L, span$c_kw_start - 1L)
  # Reconstruct "blocks = " + new_c — keep original "blocks = " keyword spacing
  rest_from_kw <- substr(full, span$c_kw_start, nchar(full))
  kw_m <- regexpr("^blocks\\s*=\\s*", rest_from_kw, perl = TRUE)
  if (kw_m < 1) {
    stop("无法安全解析 config: blocks = 前缀丢失", call. = FALSE)
  }
  kw <- substr(rest_from_kw, 1L, attr(kw_m, "match.length"))
  suffix <- substr(full, span$c_close + 1L, nchar(full))
  new_full <- paste0(prefix, kw, new_c, suffix)
  .hooks_atomic_write(config_path, strsplit(new_full, "\n", fixed = TRUE)[[1]])
  invisible(new_blocks)
}

.hooks_read_pipeline_blocks <- function(config_path, pipeline_key) {
  full <- paste(readLines(config_path, warn = FALSE), collapse = "\n")
  span <- .hooks_find_blocks_c_span(full, pipeline_key)
  .hooks_parse_c_strings(span$content)
}

.hooks_config_has_object <- function(config_path, obj_name) {
  full <- paste(readLines(config_path, warn = FALSE), collapse = "\n")
  grepl(paste0(obj_name, "\\s*<-\\s*list\\s*\\("), full, perl = TRUE)
}

.hooks_detect_dual_db_primary <- function(config_path) {
  # Best-effort: source into isolated env; failures → NULL
  env <- new.env(parent = baseenv())
  ok <- tryCatch({
    source(config_path, local = env)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) return(NULL)
  dual <- env$dual_db
  if (is.null(dual) || is.null(dual$primary)) return(NULL)
  as.character(dual$primary$db_type %||% dual$primary$type %||% NA_character_)
}

.hooks_resolve_pipeline_key <- function(slot, config_path) {
  key <- slot$pipeline_key
  if (!identical(slot$routine, "ml")) return(key)
  if (!identical(key, "pipeline_regular_primary_ml_batch")) return(key)
  primary <- .hooks_detect_dual_db_primary(config_path)
  if (!is.null(primary) && identical(tolower(primary), "nhanes") &&
      .hooks_config_has_object(config_path, "pipeline_nhanes_batch")) {
    return("pipeline_nhanes_batch")
  }
  key
}

.hooks_insert_block <- function(blocks, block_id, position, anchor_block) {
  if (identical(position, "end")) {
    return(c(blocks, block_id))
  }
  if (identical(position, "after")) {
    if (is.null(anchor_block) || !nzchar(anchor_block)) {
      stop("slot position=after 但缺少 anchor_block", call. = FALSE)
    }
    idx <- match(anchor_block, blocks)
    if (is.na(idx)) {
      stop("锚点 block 不在 pipeline 中: ", anchor_block, call. = FALSE)
    }
    if (idx >= length(blocks)) {
      return(c(blocks, block_id))
    }
    return(c(blocks[seq_len(idx)], block_id, blocks[(idx + 1L):length(blocks)]))
  }
  stop("未知 position: ", position, call. = FALSE)
}

.hooks_next_tree_version <- function(dt_dir) {
  files <- list.files(dt_dir, pattern = "^tree_v[0-9]+\\.md$")
  if (!length(files)) return(1L)
  nums <- as.integer(sub("^tree_v0*([0-9]+)\\.md$", "\\1", files))
  max(nums, na.rm = TRUE) + 1L
}

.hooks_tree_filename <- function(n) {
  sprintf("tree_v%03d.md", as.integer(n))
}

.hooks_ensure_baseline <- function(study_dir, routine, root) {
  dt_dir <- file.path(study_dir, "Decisiontree")
  if (!dir.exists(dt_dir)) dir.create(dt_dir, recursive = TRUE)
  baseline <- file.path(dt_dir, paste0("baseline_", routine, ".md"))
  if (file.exists(baseline)) return(baseline)

  rel <- .hooks_mother_rel[[routine]]
  if (is.null(rel)) {
    stop("无 routine 母版映射: ", routine, call. = FALSE)
  }
  candidates <- c(
    file.path(root, rel),
    file.path(root, "docs", rel),
    file.path(dirname(study_dir), "docs", rel)
  )
  src <- candidates[file.exists(candidates)][1]
  if (is.na(src) || !nzchar(src)) {
    stop(
      "缺少决策树母版，无法复制 baseline_", routine, ".md。候选: ",
      paste(candidates, collapse = " | "),
      call. = FALSE
    )
  }
  if (!file.copy(src, baseline)) {
    stop("复制 baseline 失败: ", src, " -> ", baseline, call. = FALSE)
  }
  baseline
}

.hooks_write_tree <- function(study_dir, routine, ext_doc, tree_name, baseline_path) {
  dt_dir <- file.path(study_dir, "Decisiontree")
  tree_path <- file.path(dt_dir, tree_name)
  baseline_body <- if (file.exists(baseline_path)) {
    readLines(baseline_path, warn = FALSE)
  } else {
    character(0)
  }
  exts <- ext_doc$extensions %||% list()
  rows <- if (!length(exts)) {
    "| _(none)_ | | |"
  } else {
    vapply(exts, function(e) {
      sprintf(
        "| `%s` | `%s` | `%s` |",
        e$slot %||% "",
        e$block %||% "",
        e$pipeline_key %||% ""
      )
    }, character(1))
  }
  mermaid_nodes <- if (!length(exts)) {
    "  NONE[no extensions]"
  } else {
    paste0("  E", seq_along(exts), "[", vapply(exts, function(e) e$block, character(1)), "]")
  }
  lines <- c(
    paste0("# Decision tree ", sub("\\.md$", "", tree_name), " — ", routine),
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
    paste0("Baseline: `", basename(baseline_path), "` (immutable; not modified by this version)"),
    "",
    "## Extensions",
    "",
    "| slot | block | pipeline_key |",
    "|------|-------|--------------|",
    rows,
    "",
    "## 挂接节点",
    "",
    "```mermaid",
    "flowchart LR",
    mermaid_nodes,
    "```",
    "",
    "## Baseline (reference; do not treat as editable)",
    "",
    "<details>",
    paste0("<summary>", basename(baseline_path), "</summary>"),
    "",
    baseline_body,
    "",
    "</details>",
    "",
    "---",
    "Generated by add_block; do not edit Blocks/. Mother Decisiontree/*.md and baseline_*.md are untouched."
  )
  .hooks_atomic_write(tree_path, lines)
  .hooks_atomic_write(
    file.path(dt_dir, "CURRENT.md"),
    paste0("current: ", tree_name)
  )
  invisible(tree_path)
}

.hooks_guard_after_edit <- function(study_dir, routine, root, pipeline_key) {
  if (!exists("pipeline_extension_guard_check", mode = "function")) {
    gf <- file.path(root, "R/pipeline_extension_guard.R")
    if (file.exists(gf)) source(gf, local = FALSE)
  }
  if (!exists("pipeline_extension_guard_check", mode = "function")) return(invisible(FALSE))
  env <- new.env(parent = baseenv())
  source(file.path(study_dir, "config.R"), local = env)
  live <- env[[pipeline_key]]
  if (is.null(live)) {
    stop("config 中缺少 ", pipeline_key, "（挂接后校验失败）", call. = FALSE)
  }
  pipes <- list()
  pipes[[pipeline_key]] <- live
  pipeline_extension_guard_check(routine, pipes, study_dir, root)
  invisible(TRUE)
}

#' Search catalog blocks by query / routine / tag
hooks_search_blocks <- function(catalog_path, query = NULL, routine = NULL, tag = NULL) {
  blocks <- .hooks_load_catalog(catalog_path)
  keep <- vapply(blocks, function(b) {
    if (!is.null(routine) && nzchar(routine)) {
      rts <- as.character(unlist(b$routines %||% list(), use.names = FALSE))
      if (length(rts) && !(routine %in% rts)) return(FALSE)
    }
    if (!is.null(tag) && nzchar(tag)) {
      tags <- as.character(unlist(b$tags %||% list(), use.names = FALSE))
      if (length(tags) && !(tag %in% tags)) return(FALSE)
    }
    if (!is.null(query) && nzchar(query)) {
      hay <- paste(
        c(
          b$block_id %||% "",
          b$summary %||% "",
          as.character(unlist(b$tags %||% list(), use.names = FALSE)),
          as.character(unlist(b$routines %||% list(), use.names = FALSE))
        ),
        collapse = " "
      )
      if (!grepl(query, hay, ignore.case = TRUE, fixed = FALSE)) return(FALSE)
    }
    TRUE
  }, logical(1))
  blocks[keep]
}

#' List hook slots (optionally filtered by routine)
hooks_list_slots <- function(slots_path, routine = NULL) {
  slots <- .hooks_load_slots_file(slots_path)
  if (!is.null(routine) && nzchar(routine)) {
    slots <- Filter(function(s) identical(s$routine, routine), slots)
  }
  slots
}

#' Attach a registered block into a slot (writes under study_dir only)
hooks_add_block <- function(study_dir, slot_id, block_id, root, catalog_dir) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  study_dir <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  catalog_dir <- normalizePath(catalog_dir, winslash = "/", mustWork = TRUE)

  config_path <- file.path(study_dir, "config.R")
  if (!file.exists(config_path)) stop("缺少 config.R: ", config_path, call. = FALSE)

  slots_path <- file.path(catalog_dir, "hook_slots.yaml")
  if (!file.exists(slots_path)) {
    slots_path <- file.path(root, "configs/study_interface/hook_slots.yaml")
  }
  slots <- .hooks_load_slots_file(slots_path)
  slot <- .hooks_slot_by_id(slots, slot_id)
  if (is.null(slot)) stop("未知 slot: ", slot_id, call. = FALSE)

  catalog_path <- file.path(catalog_dir, "catalog.json")
  cat_blocks <- .hooks_load_catalog(catalog_path)
  cat_ids <- vapply(cat_blocks, function(b) b$block_id, character(1))
  if (!(block_id %in% cat_ids)) {
    stop("block 不在 catalog: ", block_id, call. = FALSE)
  }
  registered <- .hooks_registered_ids(root)
  if (!(block_id %in% registered)) {
    stop("block 未在 pipeline_block_sources() 注册: ", block_id, call. = FALSE)
  }

  entry <- cat_blocks[[match(block_id, cat_ids)]]

  # catalog routines vs slot routine (empty routines → allow all; backward compatible)
  cat_routines <- as.character(unlist(entry$routines %||% list(), use.names = FALSE))
  if (length(cat_routines)) {
    slot_routine <- slot$routine
    if (!("*" %in% cat_routines) && !(slot_routine %in% cat_routines)) {
      stop(
        "block '", block_id, "' 的 catalog routines [",
        paste(cat_routines, collapse = ", "),
        "] 不包含 slot '", slot_id, "' 的 routine '", slot_routine,
        "' / catalog routines for block '", block_id, "' [",
        paste(cat_routines, collapse = ", "),
        "] do not include slot '", slot_id, "' routine '", slot_routine, "'",
        call. = FALSE
      )
    }
  }

  # allow_tags
  allow <- slot$allow_tags %||% "*"
  if (!("*" %in% allow)) {
    tags <- as.character(unlist(entry$tags %||% list(), use.names = FALSE))
    if (!length(intersect(tags, allow))) {
      stop(
        "block '", block_id, "' 的 tags 不符合 slot '", slot_id,
        "' 的 allow_tags",
        call. = FALSE
      )
    }
  }

  pipeline_key <- .hooks_resolve_pipeline_key(slot, config_path)
  if (!.hooks_config_has_object(config_path, pipeline_key)) {
    stop("config 中无 ", pipeline_key, " <- list(...)", call. = FALSE)
  }

  ext_doc <- .hooks_load_extensions(study_dir)
  already <- any(vapply(ext_doc$extensions, function(e) {
    identical(e$slot, slot_id) && identical(e$block, block_id)
  }, logical(1)))
  if (already) {
    message("已存在挂接 slot=", slot_id, " block=", block_id, "；跳过写入。")
    return(invisible(list(skipped = TRUE, slot = slot_id, block = block_id)))
  }

  slot_count <- sum(vapply(ext_doc$extensions, function(e) identical(e$slot, slot_id), logical(1)))
  max_extra <- as.integer(slot$max_extra %||% 8L)
  if (slot_count >= max_extra) {
    stop(
      "slot '", slot_id, "' 已达 max_extra=", max_extra,
      call. = FALSE
    )
  }

  blocks <- .hooks_read_pipeline_blocks(config_path, pipeline_key)
  if (block_id %in% blocks) {
    stop(
      "block '", block_id, "' 已在 ", pipeline_key,
      "$blocks 中（与 extensions 不一致或重复）。",
      call. = FALSE
    )
  }
  new_blocks <- .hooks_insert_block(
    blocks, block_id, slot$position, slot$anchor_block
  )

  baseline_path <- .hooks_ensure_baseline(study_dir, slot$routine, root)
  ver_n <- .hooks_next_tree_version(file.path(study_dir, "Decisiontree"))
  tree_name <- .hooks_tree_filename(ver_n)

  # Write config first, then extensions, then tree (extensions is source of truth)
  .hooks_rewrite_pipeline_blocks(config_path, pipeline_key, new_blocks)

  ext_doc$extensions <- c(ext_doc$extensions, list(list(
    slot = slot_id,
    block = block_id,
    pipeline_key = pipeline_key,
    added_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    tree_version = tree_name
  )))
  .hooks_write_extensions(study_dir, ext_doc)
  .hooks_write_tree(study_dir, slot$routine, ext_doc, tree_name, baseline_path)

  .hooks_guard_after_edit(study_dir, slot$routine, root, pipeline_key)

  invisible(list(
    skipped = FALSE,
    slot = slot_id,
    block = block_id,
    pipeline_key = pipeline_key,
    tree = tree_name
  ))
}

#' Remove a previously attached block (new tree version; baseline untouched)
hooks_remove_block <- function(study_dir, slot_id, block_id, root, catalog_dir) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  study_dir <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  catalog_dir <- normalizePath(catalog_dir, winslash = "/", mustWork = TRUE)

  config_path <- file.path(study_dir, "config.R")
  if (!file.exists(config_path)) stop("缺少 config.R: ", config_path, call. = FALSE)

  slots_path <- file.path(catalog_dir, "hook_slots.yaml")
  if (!file.exists(slots_path)) {
    slots_path <- file.path(root, "configs/study_interface/hook_slots.yaml")
  }
  slots <- .hooks_load_slots_file(slots_path)
  slot <- .hooks_slot_by_id(slots, slot_id)
  if (is.null(slot)) stop("未知 slot: ", slot_id, call. = FALSE)

  pipeline_key <- .hooks_resolve_pipeline_key(slot, config_path)
  ext_doc <- .hooks_load_extensions(study_dir)
  idx <- which(vapply(ext_doc$extensions, function(e) {
    identical(e$slot, slot_id) && identical(e$block, block_id)
  }, logical(1)))
  if (!length(idx)) {
    stop(
      "extensions.json 中无挂接记录: slot=", slot_id, " block=", block_id,
      call. = FALSE
    )
  }

  blocks <- .hooks_read_pipeline_blocks(config_path, pipeline_key)
  if (!(block_id %in% blocks)) {
    stop(
      "config 中无 block '", block_id, "'（与 extensions 不一致）",
      call. = FALSE
    )
  }
  new_blocks <- blocks[blocks != block_id]

  baseline_path <- .hooks_ensure_baseline(study_dir, slot$routine, root)
  ver_n <- .hooks_next_tree_version(file.path(study_dir, "Decisiontree"))
  tree_name <- .hooks_tree_filename(ver_n)

  .hooks_rewrite_pipeline_blocks(config_path, pipeline_key, new_blocks)
  ext_doc$extensions <- ext_doc$extensions[-idx]
  .hooks_write_extensions(study_dir, ext_doc)
  .hooks_write_tree(study_dir, slot$routine, ext_doc, tree_name, baseline_path)
  .hooks_guard_after_edit(study_dir, slot$routine, root, pipeline_key)

  invisible(list(
    slot = slot_id,
    block = block_id,
    pipeline_key = pipeline_key,
    tree = tree_name
  ))
}
