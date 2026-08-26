###############################################################################
#  attrition_log.R — 通用纳排记账 / 合并 / 绘图
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

attrition_n_current <- function(ctx) {
  d <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.data.frame(d)) as.integer(nrow(d)) else NA_integer_
}

attrition_ensure_log <- function(ctx) {
  if (is.null(ctx$results) || !is.list(ctx$results)) ctx$results <- list()
  if (is.null(ctx$results$attrition) || !is.list(ctx$results$attrition)) {
    ctx$results$attrition <- list(log = list())
  } else if (is.null(ctx$results$attrition$log) || !is.list(ctx$results$attrition$log)) {
    ctx$results$attrition$log <- list()
  }
  ctx
}

attrition_record <- function(ctx, step_id, label, n, kind = "include", meta = list()) {
  step_id <- as.character(step_id)[1L]
  label <- as.character(label)[1L]
  n <- as.integer(n)[1L]
  kind <- as.character(kind)[1L]
  if (!is.list(meta)) meta <- list()
  ctx <- attrition_ensure_log(ctx)
  log <- ctx$results$attrition$log
  entry <- list(
    step_id = step_id,
    label = label,
    n = n,
    kind = kind,
    meta = meta,
    source = meta$source %||% "log"
  )
  idx <- which(vapply(log, function(x) identical(x$step_id, step_id), logical(1)))
  if (length(idx)) {
    log[[idx[1L]]] <- entry
  } else {
    log[[length(log) + 1L]] <- entry
  }
  ctx$results$attrition$log <- log
  ctx
}

attrition_auto_append_nrow <- function(ctx, block_id, n_before, n_after) {
  attr_cfg <- ctx$config$attrition %||% list()
  if (!isTRUE(attr_cfg$auto_append %||% TRUE)) return(ctx)
  n_before <- as.integer(n_before)[1L]
  n_after <- as.integer(n_after)[1L]
  if (!is.finite(n_before) || !is.finite(n_after) || n_before == n_after) return(ctx)

  ctx <- attrition_ensure_log(ctx)
  log <- ctx$results$attrition$log
  for (entry in log) {
    if (identical(entry$meta$block %||% NULL, block_id)) return(ctx)
  }

  step_id <- paste0("auto_", block_id)
  label <- paste("After", block_id)
  attrition_record(
    ctx, step_id, label, n_after, kind = "include",
    meta = list(block = block_id, n_before = n_before, source = "auto")
  )
}

attrition_warn <- function(msg) {
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_warning(msg)
  } else {
    warning(msg, call. = FALSE)
  }
}

attrition_load_frame_from_rdata <- function(path, obj = NULL) {
  if (!file.exists(path)) stop("file not found: ", path, call. = FALSE)
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  if (!is.null(obj) && nzchar(as.character(obj)[1L])) {
    obj <- as.character(obj)[1L]
    if (!exists(obj, envir = env, inherits = FALSE)) {
      stop("object not found in RData: ", obj, call. = FALSE)
    }
    d <- get(obj, envir = env)
  } else {
    objs <- ls(envir = env)
    if (length(objs) != 1L) stop("RData must contain exactly one object or specify obj", call. = FALSE)
    d <- get(objs[1L], envir = env)
  }
  if (!is.data.frame(d)) stop("loaded object is not a data.frame", call. = FALSE)
  d
}

attrition_load_table_df <- function(path, obj = NULL) {
  path <- as.character(path)[1L]
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    stop("table file missing or not found", call. = FALSE)
  }
  if (grepl("\\.rds$", path, ignore.case = TRUE)) {
    d <- readRDS(path)
    if (!is.data.frame(d)) stop("RDS object is not a data.frame", call. = FALSE)
  } else if (grepl("\\.(RData|rda)$", path, ignore.case = TRUE)) {
    d <- attrition_load_frame_from_rdata(path, obj)
  } else {
    d <- utils::read.csv(path, stringsAsFactors = FALSE)
  }
  d
}

attrition_load_n_from_table_file <- function(path, obj = NULL) {
  as.integer(nrow(attrition_load_table_df(path, obj)))
}

attrition_load_rawdata_n <- function(ctx) {
  data_cfg <- ctx$config$data %||% list()
  attrition_load_n_from_table_file(data_cfg$rawdata_path, data_cfg$rawdata_obj)
}

attrition_filter_source_file <- function(d, step) {
  if (!is.data.frame(d) || !"Source_File" %in% names(d)) return(d)
  excl <- as.character(step$source_file_exclude %||% character(0))
  keep <- as.character(step$source_file_keep %||% character(0))
  excl <- excl[nzchar(excl)]
  keep <- keep[nzchar(keep)]
  src <- as.character(d$Source_File)
  if (length(keep)) d <- d[src %in% keep, , drop = FALSE]
  if (length(excl)) d <- d[!src %in% excl, , drop = FALSE]
  d
}

attrition_interpolate_tokens <- function(x, cfg) {
  if (is.null(x)) return(x)
  x <- as.character(x)
  ix <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% ""
  )[1L]
  years <- as.character((cfg$attrition %||% list())$years_label %||% "")[1L]
  if (nzchar(ix)) x <- gsub("{index}", ix, x, fixed = TRUE)
  if (nzchar(years)) x <- gsub("{years}", years, x, fixed = TRUE)
  x
}

attrition_interpolate_index <- function(x, cfg) {
  attrition_interpolate_tokens(x, cfg)
}

attrition_load_id_universe <- function(ctx, step) {
  join_on <- step$join_on %||% (ctx$config$data %||% list())$id_column %||% "ID"
  join_on <- as.character(join_on)[1L]

  uni_path <- step$join_universe_path %||% NULL
  if (!is.null(uni_path) && nzchar(as.character(uni_path)[1L])) {
    uni_path <- as.character(uni_path)[1L]
    uni_obj <- step$join_universe_obj %||% NULL
    if (grepl("\\.(RData|rda)$", uni_path, ignore.case = TRUE)) {
      d <- attrition_load_frame_from_rdata(uni_path, uni_obj)
    } else {
      d <- utils::read.csv(uni_path, stringsAsFactors = FALSE)
    }
  } else {
    d <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
    if (!is.data.frame(d)) stop("no baseline data for join universe", call. = FALSE)
  }
  if (!join_on %in% names(d)) {
    stop("join_on column not found in universe: ", join_on, call. = FALSE)
  }
  unique(as.character(d[[join_on]]))
}

attrition_resolve_one_step <- function(ctx, step, id_sets) {
  step_id <- as.character(step$id %||% step$step_id)[1L]
  label <- as.character(step$label)[1L]
  source <- as.character(step$source)[1L]

  n <- NA_integer_
  store_ids <- NULL

  label <- attrition_interpolate_tokens(label, ctx$config %||% list())
  exclude_label <- attrition_interpolate_tokens(
    step$exclude_label %||% NA_character_, ctx$config %||% list()
  )

  if (identical(source, "rawdata")) {
    n <- attrition_load_rawdata_n(ctx)
  } else if (identical(source, "rdata")) {
    d <- attrition_load_table_df(step$path, step$obj)
    d <- attrition_filter_source_file(d, step)
    n <- as.integer(nrow(d))
  } else if (identical(source, "current")) {
    n <- attrition_n_current(ctx)
  } else if (identical(source, "fixed")) {
    n <- as.integer(step$n)[1L]
    if (!is.finite(n)) stop("fixed step requires finite n", call. = FALSE)
  } else if (identical(source, "id_file")) {
    path <- as.character(step$path)[1L]
    if (is.null(path) || !nzchar(path) || !file.exists(path)) {
      stop("id_file path missing or not found", call. = FALSE)
    }
    df <- utils::read.csv(path, stringsAsFactors = FALSE)
    filt <- step$filter %||% NULL
    if (!is.null(filt) && nzchar(as.character(filt)[1L])) {
      keep <- with(df, eval(parse(text = as.character(filt)[1L])))
      df <- df[keep, , drop = FALSE]
    }
    id_col <- as.character(step$id_col)[1L]
    if (is.null(id_col) || !id_col %in% names(df)) {
      stop("id_col not found in id_file", call. = FALSE)
    }
    file_ids <- unique(as.character(df[[id_col]]))
    if (!is.null(step$intersect_with) && nzchar(as.character(step$intersect_with)[1L])) {
      ref <- as.character(step$intersect_with)[1L]
      prior <- id_sets[[ref]]
      if (is.null(prior)) stop("intersect_with step not resolved: ", ref, call. = FALSE)
      file_ids <- intersect(file_ids, prior)
    }
    universe_ids <- attrition_load_id_universe(ctx, step)
    store_ids <- intersect(file_ids, universe_ids)
    n <- as.integer(length(store_ids))
  } else {
    stop("unknown source: ", source, call. = FALSE)
  }

  if (!is.null(store_ids) && nzchar(step_id)) {
    id_sets[[step_id]] <- store_ids
  }

  list(
    step_id = step_id, label = label, n = n, source = source,
    exclude_label = {
      el <- as.character(exclude_label %||% NA_character_)[1L]
      if (!is.na(el) && nzchar(el)) el else NA_character_
    }
  )
}

attrition_resolve_config_steps <- function(ctx, steps) {
  if (is.null(steps) || !length(steps)) return(list())
  id_sets <- new.env(parent = emptyenv())
  out <- list()
  for (step in steps) {
    sid <- as.character(step$id %||% step$step_id %||% "")[1L]
    lab <- as.character(step$label %||% sid)[1L]
    res <- tryCatch(
      attrition_resolve_one_step(ctx, step, id_sets),
      error = function(e) {
        attrition_warn(sprintf("attrition step skipped (%s): %s", lab, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(res) && is.finite(res$n)) {
      out[[length(out) + 1L]] <- res
    }
  }
  out
}

attrition_log_entry_to_row <- function(entry) {
  data.frame(
    step = as.character(entry$label)[1L],
    n = as.integer(entry$n)[1L],
    source = as.character(entry$source %||% "log")[1L],
    kind = as.character(entry$kind %||% "include")[1L],
    step_id = as.character(entry$step_id)[1L],
    exclude_label = as.character(entry$meta$exclude_label %||% NA_character_)[1L],
    stringsAsFactors = FALSE
  )
}

attrition_resolved_to_row <- function(res) {
  data.frame(
    step = as.character(res$label)[1L],
    n = as.integer(res$n)[1L],
    source = as.character(res$source)[1L],
    kind = "include",
    step_id = as.character(res$step_id)[1L],
    exclude_label = as.character(res$exclude_label %||% NA_character_)[1L],
    stringsAsFactors = FALSE
  )
}

attrition_apply_outcome_breakdown <- function(rows_df, ctx, config) {
  attr_cfg <- config$attrition %||% list()
  if (!isTRUE(attr_cfg$outcome_breakdown %||% FALSE)) return(rows_df)
  if (is.null(rows_df) || !nrow(rows_df)) return(rows_df)

  data_cfg <- config$data %||% list()
  oc <- data_cfg$outcome_column
  proj <- config$project %||% list()
  ag <- proj$analysis_group
  rg <- proj$reference_group
  d <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (!is.data.frame(d) || is.null(oc) || !oc %in% names(d)) return(rows_df)
  if (is.null(ag) || is.null(rg)) return(rows_df)

  vals <- as.character(d[[oc]])
  n_case <- sum(vals == as.character(ag), na.rm = TRUE)
  n_ctrl <- sum(vals == as.character(rg), na.rm = TRUE)
  last <- nrow(rows_df)
  rows_df$step[last] <- paste0(
    rows_df$step[last],
    sprintf(" (%s: %s; %s: %s)", ag, format(n_case, big.mark = ","),
            rg, format(n_ctrl, big.mark = ","))
  )
  rows_df
}

attrition_finalize_rows <- function(ctx, config) {
  config <- config %||% ctx$config %||% list()
  attr_cfg <- config$attrition %||% list()
  steps <- attr_cfg$steps %||% list()
  log <- ((ctx$results %||% list())$attrition %||% list())$log %||% list()

  if (!length(steps)) {
    attrition_warn("config$attrition$steps is empty; consider adding cohort queue steps")
  }

  resolved <- attrition_resolve_config_steps(ctx, steps)
  rows_list <- lapply(resolved, attrition_resolved_to_row)
  if (length(rows_list)) {
    rows_df <- do.call(rbind, rows_list)
  } else {
    rows_df <- data.frame(
      step = character(0), n = integer(0), source = character(0),
      kind = character(0), step_id = character(0),
      exclude_label = character(0), stringsAsFactors = FALSE
    )
  }

  if (length(log) && !isTRUE(attr_cfg$config_steps_only %||% FALSE)) {
    for (entry in log) {
      sid <- as.character(entry$step_id)[1L]
      new_row <- attrition_log_entry_to_row(entry)
      hit <- which(rows_df$step_id == sid)
      if (length(hit)) {
        rows_df[hit[1L], ] <- new_row
      } else {
        rows_df <- rbind(rows_df, new_row)
      }
    }
  } else if (length(log) && isTRUE(attr_cfg$config_steps_only %||% FALSE)) {
    for (entry in log) {
      sid <- as.character(entry$step_id)[1L]
      hit <- which(rows_df$step_id == sid)
      if (length(hit)) rows_df[hit[1L], ] <- attrition_log_entry_to_row(entry)
    }
  }

  if (!nrow(rows_df)) {
    n_cur <- attrition_n_current(ctx)
    if (is.finite(n_cur)) {
      rows_df <- data.frame(
        step = "Analytic cohort",
        n = n_cur,
        source = "current",
        kind = "include",
        step_id = "analytic_fallback",
        exclude_label = NA_character_,
        stringsAsFactors = FALSE
      )
    }
  }

  rows_df <- attrition_apply_outcome_breakdown(rows_df, ctx, config)
  keep <- intersect(c("step", "n", "source", "kind"), names(rows_df))
  rows_df[, keep, drop = FALSE]
}

.attrition_pdf_device <- function(pdf_path, width, height, family) {
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(pdf_path, width, height, family)
    return(invisible(TRUE))
  }
  family <- as.character(family %||% "serif")[1L]
  if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(pdf_path, width = width, height = height, family = family)
    return(invisible(TRUE))
  }
  if (identical(family, "Times New Roman")) family <- "Times"
  grDevices::pdf(pdf_path, width = width, height = height, family = family)
  invisible(TRUE)
}

#' Copy a drawn inclusion-exclusion PDF to canonical Figure 1. Flowchart.pdf
attrition_promote_figure1 <- function(figures_dir) {
  if (is.null(figures_dir) || !nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(FALSE))
  }
  dest <- file.path(figures_dir, "Figure 1. Flowchart.pdf")
  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(FALSE))
  bn <- basename(files)
  keep <- grepl(
    paste0(
      "(?i)^(Figure 1\\. Inclusion exclusion flowchart.*\\.pdf|",
      "Figure 1\\. Flowchart_.+\\.pdf|",
      "Figure 1-.+Inclusion.+\\.pdf)$"
    ),
    bn,
    perl = TRUE
  )
  cands <- files[keep]
  if (!length(cands)) return(invisible(FALSE))
  src <- cands[[which.max(file.info(cands)$size)]]
  if (identical(normalizePath(src, winslash = "/", mustWork = FALSE),
                normalizePath(dest, winslash = "/", mustWork = FALSE))) {
    return(invisible(TRUE))
  }
  ok <- file.copy(src, dest, overwrite = TRUE)
  if (isTRUE(ok) && file.exists(dest)) {
    extras <- setdiff(cands, dest)
    if (length(extras)) {
      unlink(extras)
    }
    return(invisible(TRUE))
  }
  invisible(FALSE)
}

attrition_weight_footnote <- function(ctx) {
  wi <- ((ctx$results %||% list())$nhanes_weight_info) %||% NULL
  if (is.null(wi)) return(character(0))
  wt <- as.character(wi$weight_col %||% "")[1L]
  if (!nzchar(wt)) return(character(0))
  src <- as.character(wi$source %||% "")[1L]
  ncyc <- suppressWarnings(as.integer(wi$n_cycles %||% NA_integer_)[1L])
  cyc_txt <- if (is.finite(ncyc) && ncyc > 0L) sprintf("%d NHANES cycles", ncyc) else ""
  desc <- as.character(wi$source_desc %||% "")[1L]
  used <- if (is.finite(wi$n_used %||% NA_integer_)) sprintf("n = %s weighted", format(as.integer(wi$n_used), big.mark = ",")) else ""
  line1 <- paste(Filter(nzchar, c(
    "Survey weights:", wt, if (nzchar(src)) paste0("(from ", src, ")"),
    if (nzchar(desc)) paste0("[", desc, "]"), cyc_txt, used
  )), collapse = " ")
  if (isTRUE(wi$dropped_any %||% FALSE)) {
    nd <- as.integer(wi$n_dropped %||% 0L)
    line2 <- sprintf(
      "%s participant(s) were excluded due to missing or non-positive survey weights.",
      format(nd, big.mark = ",")
    )
  } else {
    line2 <- "No participants were excluded due to survey weights."
  }
  c(line1, line2)
}

attrition_draw_pdf <- function(rows, title, pdf_path, font_family = "Times New Roman",
                               footnote = character(0), box_fill = "#F7F7F7") {
  if (is.null(rows) || !is.data.frame(rows) || !nrow(rows)) return(invisible(FALSE))
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family(font_family)
  } else {
    font_family
  }
  n_box <- nrow(rows)
  w <- 8.5
  h <- max(6.5, 1.15 * n_box + 1.8 + if (length(footnote)) 0.9 else 0)
  footnote <- as.character(footnote %||% character(0))
  footnote <- footnote[nzchar(footnote)]
  opened <- tryCatch({
    .attrition_pdf_device(pdf_path, w, h, ff)
    TRUE
  }, error = function(e) {
    tryCatch({
      .attrition_pdf_device(pdf_path, w, h, "Times")
      TRUE
    }, error = function(e2) FALSE)
  })
  if (!isTRUE(opened)) return(invisible(FALSE))
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- graphics::par(mar = c(0.4, 0.4, 2.2, 0.4))
  on.exit(graphics::par(op), add = TRUE)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
  graphics::title(main = title, cex.main = 1.05)
  y_top <- 0.94
  # 预留脚注空间（权重说明）
  if (length(footnote)) y_top <- y_top - 0.02 * length(footnote)
  box_h <- min(0.11, 0.82 / (n_box * 1.35))
  gap <- box_h * 0.32
  for (i in seq_len(n_box)) {
    y1 <- y_top - (i - 1) * (box_h + gap)
    y0 <- y1 - box_h
    graphics::rect(0.16, y0, 0.84, y1, border = "black", col = box_fill, lwd = 1.4)
    lab <- sprintf(
      "%s\nN = %s",
      rows$step[i],
      format(as.integer(rows$n[i]), big.mark = ",")
    )
    graphics::text(0.5, (y0 + y1) / 2, lab, cex = 0.85)
    if (i < n_box) {
      graphics::arrows(0.5, y0 - 0.004, 0.5, y0 - gap + 0.008, length = 0.07, lwd = 1.1)
      drop_n <- as.integer(rows$n[i]) - as.integer(rows$n[i + 1L])
      if (is.finite(drop_n) && drop_n > 0L) {
        graphics::text(
          0.87, y0 - gap / 2,
          sprintf("-%s", format(drop_n, big.mark = ",")),
          cex = 0.72, col = "#555555", adj = 0
        )
      }
    }
  }

  # 权重脚注（底部左对齐；说明用了哪个权重、是否因权重删人）
  if (length(footnote)) {
    fn_y <- max(0.03, 0.30 - 0.05 * length(footnote))
    for (k in seq_along(footnote)) {
      graphics::text(
        0.03, fn_y + (length(footnote) - k) * 0.045,
        footnote[[k]], cex = 0.68, col = "#333333", adj = 0
      )
    }
  }
  invisible(TRUE)
}
