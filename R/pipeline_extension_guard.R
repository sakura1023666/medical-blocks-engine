###############################################################################
#  R/pipeline_extension_guard.R — hard-stop illegal pipeline extensions
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.pipeline_guard_load_baseline <- function(root) {
  path <- file.path(root, "configs/study_interface/baseline_pipelines.json")
  if (!file.exists(path)) {
    stop("缺少 baseline_pipelines.json: ", path, call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

.pipeline_guard_load_slots <- function(root) {
  path <- file.path(root, "configs/study_interface/hook_slots.yaml")
  if (!file.exists(path)) {
    stop("缺少 hook_slots.yaml: ", path, call. = FALSE)
  }
  if (requireNamespace("yaml", quietly = TRUE)) {
    raw <- yaml::read_yaml(path)
    slots <- raw$slots %||% list()
  } else {
    # Minimal fallback: only id/routine/pipeline_key/anchor_block/position lines
    lines <- readLines(path, warn = FALSE)
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
      }
    }
    flush_cur()
  }
  out <- list()
  for (s in slots) {
    sid <- s$id %||% NA_character_
    if (is.na(sid) || !nzchar(sid)) next
    out[[sid]] <- list(
      id = sid,
      routine = s$routine %||% NA_character_,
      pipeline_key = s$pipeline_key %||% NA_character_,
      anchor_block = s$anchor_block,
      position = s$position %||% NA_character_,
      max_extra = s$max_extra %||% 8L
    )
  }
  out
}

.pipeline_guard_load_extensions <- function(study_dir) {
  path <- file.path(study_dir, "extensions.json")
  if (!file.exists(path)) return(NULL)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
  }
  raw <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  exts <- raw$extensions %||% list()
  if (!length(exts)) return(list())
  lapply(exts, function(e) {
    list(
      slot = e$slot %||% NA_character_,
      block = e$block %||% NA_character_,
      pipeline_key = e$pipeline_key %||% NA_character_
    )
  })
}

.pipeline_guard_as_chr <- function(x) {
  if (is.null(x)) return(character(0))
  # Live configs use list(name=..., blocks=c(...), ...); unit tests may pass bare vectors.
  if (is.list(x) && !is.null(x$blocks)) {
    return(as.character(x$blocks))
  }
  if (is.character(x)) return(x)
  as.character(unlist(x, use.names = FALSE))
}

.pipeline_guard_strip_nulls <- function(pipelines) {
  if (is.null(pipelines) || !length(pipelines)) return(list())
  keep <- !vapply(pipelines, is.null, logical(1))
  pipelines[keep]
}

.pipeline_guard_check_pipeline <- function(pipeline_key, base_vec, live_vec,
                                          ext_records, slots, registered) {
  base_vec <- .pipeline_guard_as_chr(base_vec)
  live_vec <- .pipeline_guard_as_chr(live_vec)
  extras <- setdiff(live_vec, base_vec)

  for (e in ext_records) {
    if (!(e$block %in% live_vec)) {
      stop(
        "非法 pipeline 扩展: extensions.json 记录的 block '", e$block,
        "' 未出现在 ", pipeline_key, " 中（配置与 extensions 不一致）。",
        call. = FALSE
      )
    }
  }

  if (!length(extras) && !length(ext_records)) {
    if (!identical(live_vec, base_vec)) {
      stop(
        "非法 pipeline 扩展: ", pipeline_key,
        " 相对基线被重排或删改，且无 extensions.json 授权。",
        call. = FALSE
      )
    }
    return(invisible(TRUE))
  }

  ext_blocks <- vapply(ext_records, function(e) e$block, character(1))
  for (x in extras) {
    if (!(x %in% ext_blocks)) {
      stop(
        "非法 pipeline 扩展: '", x, "' 不在 extensions.json。",
        "请用 add_block.sh 挂接，勿手改。",
        call. = FALSE
      )
    }
    if (!(x %in% registered)) {
      stop(
        "非法 pipeline 扩展: '", x,
        "' 未在 pipeline_block_sources() 中注册。",
        call. = FALSE
      )
    }
  }

  # Core (live minus extras) must equal baseline exactly
  live_core <- live_vec[!live_vec %in% extras]
  if (!identical(live_core, base_vec)) {
    stop(
      "非法 pipeline 扩展: ", pipeline_key,
      " 基线顺序被破坏（删改/重排）。请用 CLI 挂接，勿手改。",
      call. = FALSE
    )
  }

  # Resolve slot metadata per extension
  end_blocks <- character(0)
  after_by_anchor <- list()
  for (e in ext_records) {
    slot <- slots[[e$slot]]
    if (is.null(slot)) {
      stop(
        "非法 pipeline 扩展: slot '", e$slot,
        "' 不在 hook_slots.yaml 中。",
        call. = FALSE
      )
    }
    if (!identical(slot$pipeline_key, pipeline_key)) {
      stop(
        "非法 pipeline 扩展: slot '", e$slot, "' 的 pipeline_key=",
        slot$pipeline_key, " 与记录 ", pipeline_key, " 不一致。",
        call. = FALSE
      )
    }
    pos <- slot$position
    if (identical(pos, "end")) {
      end_blocks <- c(end_blocks, e$block)
    } else if (identical(pos, "after")) {
      anchor <- slot$anchor_block %||% NA_character_
      if (is.na(anchor) || !nzchar(anchor)) {
        stop(
          "非法 pipeline 扩展: slot '", e$slot,
          "' 声明 position=after 但缺少 anchor_block。",
          call. = FALSE
        )
      }
      after_by_anchor[[anchor]] <- c(after_by_anchor[[anchor]], e$block)
    } else {
      stop(
        "非法 pipeline 扩展: slot '", e$slot,
        "' 的 position 无法识别: ", pos, call. = FALSE
      )
    }
  }

  # end extras must be a contiguous suffix
  if (length(end_blocks)) {
    n <- length(live_vec)
    k <- length(end_blocks)
    if (n < k) {
      stop(
        "非法 pipeline 扩展: ", pipeline_key,
        " 的 end 扩展无法构成末尾后缀。",
        call. = FALSE
      )
    }
    suffix <- live_vec[(n - k + 1L):n]
    if (!setequal(suffix, end_blocks) || length(unique(suffix)) != k) {
      stop(
        "非法 pipeline 扩展: end 槽位的多余 block 必须位于 ",
        pipeline_key, " 末尾（suffix）。位置不符合 slot。",
        call. = FALSE
      )
    }
    # No end-block may appear before the suffix
    if (n > k && any(live_vec[seq_len(n - k)] %in% end_blocks)) {
      stop(
        "非法 pipeline 扩展: end 槽位 block 出现在非末尾位置。",
        call. = FALSE
      )
    }
  }

  # after extras: contiguous immediately after anchor (before next baseline block)
  for (anchor in names(after_by_anchor)) {
    want <- after_by_anchor[[anchor]]
    aidx <- match(anchor, live_vec)
    if (is.na(aidx)) {
      stop(
        "非法 pipeline 扩展: anchor '", anchor,
        "' 不在 ", pipeline_key, " 中。",
        call. = FALSE
      )
    }
    run <- character(0)
    i <- aidx + 1L
    while (i <= length(live_vec) &&
           live_vec[[i]] %in% extras &&
           !(live_vec[[i]] %in% end_blocks)) {
      run <- c(run, live_vec[[i]])
      i <- i + 1L
    }
    if (!setequal(run, want) || length(run) != length(want)) {
      stop(
        "非法 pipeline 扩展: after '", anchor,
        "' 的扩展必须紧邻锚点且连续。位置不符合 slot。",
        call. = FALSE
      )
    }
  }

  # Extras that are neither in end_blocks nor in any after-run → already caught
  # by setequal checks if all ext_records classified.

  invisible(TRUE)
}

#' Hard-stop guard: live pipelines must match baseline + legal extensions.json
#'
#' @param routine One of environment / incidence / survival / ml
#' @param pipelines Named list of character vectors (NULL entries stripped)
#' @param study_dir Directory containing optional extensions.json (usually dirname(config))
#' @param root Project root
#' @return invisible(TRUE) or stop()
pipeline_extension_guard_check <- function(routine, pipelines, study_dir, root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  study_dir <- normalizePath(study_dir, winslash = "/", mustWork = TRUE)
  pipelines <- .pipeline_guard_strip_nulls(pipelines)

  if (!exists("pipeline_block_sources", mode = "function")) {
    pr <- file.path(root, "R/pipeline_runner.R")
    if (!file.exists(pr)) {
      stop("无法加载 pipeline_block_sources: 缺少 ", pr, call. = FALSE)
    }
    source(pr, local = FALSE)
  }
  registered <- names(pipeline_block_sources(root))

  baseline_doc <- .pipeline_guard_load_baseline(root)
  base_routine <- baseline_doc[[routine]]
  if (is.null(base_routine)) {
    stop("baseline_pipelines.json 中无 routine: ", routine, call. = FALSE)
  }

  slots <- .pipeline_guard_load_slots(root)
  extensions <- .pipeline_guard_load_extensions(study_dir)

  # Gather extras across baseline keys present in live pipelines
  any_extra <- FALSE
  for (key in names(base_routine)) {
    live <- pipelines[[key]]
    if (is.null(live)) next
    extra <- setdiff(.pipeline_guard_as_chr(live), .pipeline_guard_as_chr(base_routine[[key]]))
    if (length(extra)) any_extra <- TRUE
  }

  if (any_extra && is.null(extensions)) {
    stop(
      "非法 pipeline 扩展: 发现相对基线的多余 block，但缺少 extensions.json。",
      "请用 add_block.sh 挂接，勿手改。",
      call. = FALSE
    )
  }

  ext_list <- extensions %||% list()

  for (key in names(base_routine)) {
    live <- pipelines[[key]]
    if (is.null(live)) next
    key_exts <- Filter(function(e) identical(e$pipeline_key, key), ext_list)
    # Also accept records that omit pipeline_key but whose slot maps to this key
    if (!length(key_exts) && length(ext_list)) {
      key_exts <- Filter(function(e) {
        if (!is.na(e$pipeline_key) && nzchar(e$pipeline_key) &&
            !identical(e$pipeline_key, key)) {
          return(FALSE)
        }
        sl <- slots[[e$slot]]
        !is.null(sl) && identical(sl$pipeline_key, key)
      }, ext_list)
    }
    .pipeline_guard_check_pipeline(
      pipeline_key = key,
      base_vec = base_routine[[key]],
      live_vec = live,
      ext_records = key_exts,
      slots = slots,
      registered = registered
    )
  }

  # Extension records for this routine whose pipeline_key is absent from live
  # still require their block to be present when that pipeline object exists;
  # if the pipeline object is missing entirely, skip (config may not define it).

  invisible(TRUE)
}
