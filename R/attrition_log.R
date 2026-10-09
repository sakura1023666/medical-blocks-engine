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

#' Record the cohort eligible for a complex-survey design.
#' Keep ctx$data unchanged; the survey design remains the analysis-set authority.
#' Always records when design_n <= n_before (incl. 0 dropped), and names the weight.
attrition_record_survey_weight_step <- function(ctx, design_n) {
  n_before <- attrition_n_current(ctx)
  design_n <- as.integer(design_n)[1L]
  if (!is.finite(n_before) || !is.finite(design_n) ||
      design_n < 0L || design_n > n_before) {
    return(ctx)
  }
  wi <- ((ctx$results %||% list())$nhanes_weight_info) %||% NULL
  wt <- as.character(wi$weight_col %||% "")[1L]
  src <- as.character(wi$source %||% "")[1L]
  if (!nzchar(wt)) {
    wt <- as.character(
      ((ctx$config %||% list())$nhanes %||% list())$survey_weight %||% "new_Weight"
    )[1L]
  }
  exclude_label <- if (nzchar(src)) {
    sprintf("Missing or non-positive survey weights (%s from %s)", wt, src)
  } else {
    sprintf("Missing or non-positive survey weights (%s)", wt)
  }
  n_drop_meta <- if (is.finite(wi$n_dropped %||% NA_integer_)) {
    as.integer(wi$n_dropped)[1L]
  } else {
    as.integer(n_before - design_n)
  }
  attrition_record(
    ctx,
    "after_survey_weight",
    "Eligible survey-weighted cohort",
    design_n,
    meta = list(
      block = "obj",
      source = "survey_design",
      exclude_label = exclude_label,
      weight_col = wt,
      weight_source = src,
      n_dropped_weight = n_drop_meta,
      always_show_exclude = TRUE
    )
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

#' 解析纳排图底部分叉：发病=病例/对照；预后=死亡/存活。
#' 人数不写进末步标题，供 CONSORT 左右两框使用。
attrition_resolve_outcome_fork <- function(ctx, config) {
  attr_cfg <- config$attrition %||% list()
  if (identical(attr_cfg$outcome_breakdown, FALSE)) return(NULL)

  design_vars <- tryCatch(
    (ctx$results$nhanes_design %||% list())$variables,
    error = function(e) NULL
  )
  d <- if (is.data.frame(design_vars) && nrow(design_vars)) {
    design_vars
  } else {
    ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  }
  if (!is.data.frame(d) || !nrow(d)) return(NULL)

  proj <- config$project %||% list()
  data_cfg <- config$data %||% list()
  surv <- config$survival %||% list()
  study_type <- tolower(as.character(proj$study_type %||% "")[1L])
  oc <- as.character(
    data_cfg$outcome_column %||%
      (config$incidence %||% list())$outcome_var %||% ""
  )[1L]
  ag <- proj$analysis_group
  rg <- proj$reference_group
  is_prognosis <- identical(study_type, "prognosis") ||
    identical(study_type, "survival") ||
    isTRUE(attr_cfg$fork_mode %||% "" == "prognosis")

  if (!is_prognosis && nzchar(oc) && oc %in% names(d) &&
      !is.null(ag) && !is.null(rg)) {
    vals <- as.character(d[[oc]])
    n_case <- sum(vals == as.character(ag)[1L], na.rm = TRUE)
    n_ctrl <- sum(vals == as.character(rg)[1L], na.rm = TRUE)
    if (is.finite(n_case) && is.finite(n_ctrl) && (n_case + n_ctrl) > 0L) {
      left_lab <- as.character(attr_cfg$fork_case_label %||%
                                 sprintf("%s group", as.character(ag)[1L]))[1L]
      right_lab <- as.character(attr_cfg$fork_ctrl_label %||%
                                  sprintf("%s group", as.character(rg)[1L]))[1L]
      return(list(
        left_label = left_lab, left_n = as.integer(n_case),
        right_label = right_lab, right_n = as.integer(n_ctrl),
        mode = "incidence"
      ))
    }
  }

  ev <- as.character(surv$event_var %||% data_cfg$event_var %||% "fustatus")[1L]
  if (nzchar(ev) && ev %in% names(d)) {
    raw <- d[[ev]]
    evv <- suppressWarnings(as.integer(as.character(raw)))
    if (!length(evv) || all(is.na(evv))) {
      ch <- tolower(trimws(as.character(raw)))
      evv <- ifelse(ch %in% c("1", "true", "dead", "expired", "death", "yes"), 1L,
                    ifelse(ch %in% c("0", "false", "alive", "censor", "censored", "no"), 0L, NA_integer_))
    }
    n_dead <- sum(evv == 1L, na.rm = TRUE)
    n_alive <- sum(evv == 0L, na.rm = TRUE)
    if (is.finite(n_dead) && is.finite(n_alive) && (n_dead + n_alive) > 0L) {
      left_lab <- as.character(attr_cfg$fork_event_label %||% "Expired group")[1L]
      right_lab <- as.character(attr_cfg$fork_censor_label %||% "Alive group")[1L]
      return(list(
        left_label = left_lab, left_n = as.integer(n_dead),
        right_label = right_lab, right_n = as.integer(n_alive),
        mode = "prognosis"
      ))
    }
  }
  NULL
}

attrition_apply_outcome_breakdown <- function(rows_df, ctx, config) {
  if (is.null(rows_df) || !nrow(rows_df)) return(rows_df)
  fork <- attrition_resolve_outcome_fork(ctx, config)
  rows_df$fork_left_label <- NA_character_
  rows_df$fork_left_n <- NA_integer_
  rows_df$fork_right_label <- NA_character_
  rows_df$fork_right_n <- NA_integer_
  if (is.null(fork)) return(rows_df)
  last <- nrow(rows_df)
  rows_df$fork_left_label[last] <- as.character(fork$left_label)[1L]
  rows_df$fork_left_n[last] <- as.integer(fork$left_n)[1L]
  rows_df$fork_right_label[last] <- as.character(fork$right_label)[1L]
  rows_df$fork_right_n[last] <- as.integer(fork$right_n)[1L]
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

  # 发表口径：无任何起点行时，自动前置 "Starting cohort"（原始队列 n）
  if (!any(grepl("^starting", tolower(rows_df$step_id)))) {
    n_raw <- tryCatch(attrition_load_rawdata_n(ctx), error = function(e) NA_integer_)
    n_first <- if (nrow(rows_df)) suppressWarnings(as.integer(rows_df$n)[1L]) else NA_integer_
    if (is.finite(n_raw) && is.finite(n_first) && n_raw >= n_first && n_raw > 0L) {
      rows_df <- rbind(
        data.frame(
          step = "Starting cohort", n = n_raw, source = "rawdata",
          kind = "include", step_id = "starting_cohort",
          exclude_label = NA_character_, stringsAsFactors = FALSE
        ),
        rows_df
      )
    }
  }

  rows_df <- attrition_apply_outcome_breakdown(rows_df, ctx, config)
  keep <- intersect(
    c("step", "n", "source", "kind", "step_id", "exclude_label",
      "fork_left_label", "fork_left_n", "fork_right_label", "fork_right_n"),
    names(rows_df)
  )
  rows_df[, keep, drop = FALSE]
}

#' 双库 CONSORT 纳排：各库先画单页，再横排 A|B（禁止旧式 mfrow 方框）。
attrition_draw_dual_panel_pdf <- function(rows_by_db, dest, titles = NULL,
                                          font_family = "Times New Roman",
                                          footnotes_by_db = NULL) {
  if (is.null(rows_by_db) || !length(rows_by_db)) return(invisible(FALSE))
  nms <- names(rows_by_db)
  if (is.null(nms) || !any(nzchar(nms))) nms <- as.character(seq_along(rows_by_db))
  tmp <- character(0)
  on.exit({
    if (length(tmp)) unlink(tmp)
  }, add = TRUE)
  for (i in seq_along(rows_by_db)) {
    p <- tempfile(fileext = ".pdf")
    title <- if (!is.null(titles) && length(titles) >= i && nzchar(as.character(titles[[i]])[1L])) {
      as.character(titles[[i]])[1L]
    } else {
      nms[[i]]
    }
    fn <- character(0)
    if (!is.null(footnotes_by_db)) {
      key <- nms[[i]]
      if (!is.null(footnotes_by_db[[key]])) {
        fn <- as.character(footnotes_by_db[[key]])
      } else if (length(footnotes_by_db) >= i) {
        fn <- as.character(footnotes_by_db[[i]])
      }
      fn <- fn[nzchar(fn)]
    }
    ok <- isTRUE(attrition_draw_pdf(
      rows_by_db[[i]], title, p, font_family = font_family, footnote = fn
    ))
    if (!isTRUE(ok) || !file.exists(p)) return(invisible(FALSE))
    tmp <- c(tmp, p)
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (length(tmp) == 1L) {
    ok <- file.copy(tmp[[1L]], dest, overwrite = TRUE)
    return(invisible(isTRUE(ok) && file.exists(dest)))
  }
  if (length(tmp) >= 2L && exists("pub_figure_combine_ab_pdfs", mode = "function")) {
    ok <- isTRUE(tryCatch(
      pub_figure_combine_ab_pdfs(tmp[[1L]], tmp[[2L]], dest, stack = FALSE),
      error = function(e) FALSE
    ))
    if (isTRUE(ok) && file.exists(dest)) return(invisible(TRUE))
  }
  if (requireNamespace("pdftools", quietly = TRUE)) {
    ok <- tryCatch({
      pdftools::pdf_combine(tmp, output = dest)
      file.exists(dest)
    }, error = function(e) FALSE)
    return(invisible(isTRUE(ok)))
  }
  invisible(FALSE)
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

.attrition_wrap_label <- function(txt, width = 32L) {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt)) return("")
  paste(strwrap(txt, width = as.integer(width)[1L]), collapse = "\n")
}

.attrition_fork_from_rows <- function(rows) {
  if (is.null(rows) || !is.data.frame(rows) || !nrow(rows)) return(NULL)
  need <- c("fork_left_label", "fork_left_n", "fork_right_label", "fork_right_n")
  if (!all(need %in% names(rows))) return(NULL)
  last <- nrow(rows)
  ln <- suppressWarnings(as.integer(rows$fork_left_n[last])[1L])
  rn <- suppressWarnings(as.integer(rows$fork_right_n[last])[1L])
  ll <- as.character(rows$fork_left_label[last])[1L]
  rl <- as.character(rows$fork_right_label[last])[1L]
  if (!is.finite(ln) || !is.finite(rn) || !nzchar(ll) || !nzchar(rl)) return(NULL)
  list(left_label = ll, left_n = ln, right_label = rl, right_n = rn)
}

.attrition_grid_roundbox <- function(x0, y0, x1, y1, fill, family, text,
                                     fontsize = 10, fontface = "bold") {
  grid::grid.roundrect(
    x = grid::unit((x0 + x1) / 2, "npc"),
    y = grid::unit((y0 + y1) / 2, "npc"),
    width = grid::unit(abs(x1 - x0), "npc"),
    height = grid::unit(abs(y1 - y0), "npc"),
    r = grid::unit(0.012, "npc"),
    gp = grid::gpar(fill = fill, col = "#222222", lwd = 1.2)
  )
  grid::grid.text(
    text,
    x = grid::unit((x0 + x1) / 2, "npc"),
    y = grid::unit((y0 + y1) / 2, "npc"),
    gp = grid::gpar(
      fontsize = fontsize, fontface = fontface, fontfamily = family,
      lineheight = 1.15, col = "#111111"
    )
  )
}

#' 从 step_id / 步骤标签推断「本步排除了什么」的可读原因
.attrition_exclude_reason <- function(step_id, step_label) {
  sid <- tolower(trimws(as.character(step_id %||% "")[1L]))
  lab <- as.character(step_label %||% "")[1L]
  hit <- switch(sid,
    after_age_filter = , age_filter = "Age not in eligible range",
    after_data_clean = , data_clean = "Incomplete covariates",
  starting_cohort = "Missing exposure or key covariates",
    after_imputation = , imputation = "Missing key variables",
    after_index = , index = "Index not computable",
    analysis_exclusion = , after_analysis_exclusion = "Disease-related variables",
    ""
  )
  if (nzchar(hit)) return(hit)
  # 从标签兜底（"After data cleaning" → data cleaning 相关）
  if (grepl("clean", lab, ignore.case = TRUE)) return("Incomplete covariates after data cleaning")
  if (grepl("imput", lab, ignore.case = TRUE)) return("Missing exposure or key covariates")
  if (grepl("age", lab, ignore.case = TRUE)) return("Age outside inclusion criteria")
  ""
}

.attrition_grid_arrow <- function(x0, y0, x1, y1, family = "Times", lty = 1) {
  grid::grid.lines(
    x = grid::unit(c(x0, x1), "npc"),
    y = grid::unit(c(y0, y1), "npc"),
    arrow = grid::arrow(type = "closed", length = grid::unit(7, "pt"), angle = 20),
    gp = grid::gpar(col = "#222222", fill = "#222222", lwd = 1.15, lty = lty)
  )
}

#' CONSORT 纳排图（对齐 TST Figure 1）：主列圆角纳入框、右侧 Exclude、
#' 底部分叉为发病病例/对照或预后 Expired/Alive。
attrition_draw_pdf <- function(rows, title, pdf_path, font_family = "Times New Roman",
                               footnote = character(0), box_fill = "#FFFFFF",
                               fork = NULL) {
  if (is.null(rows) || !is.data.frame(rows) || !nrow(rows)) return(invisible(FALSE))
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family(font_family)
  } else {
    font_family
  }
  footnote <- as.character(footnote %||% character(0))
  footnote <- footnote[nzchar(footnote)]
  if (is.null(fork)) fork <- .attrition_fork_from_rows(rows)
  n_box <- nrow(rows)
  has_fork <- is.list(fork) &&
    is.finite(fork$left_n %||% NA_real_) && is.finite(fork$right_n %||% NA_real_)
  w <- 7.6
  h <- max(8.2, 1.55 * n_box + if (has_fork) 3.1 else 1.6 + if (length(footnote)) 0.7 else 0)
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
  if (identical(ff, "Times New Roman") && !isTRUE(capabilities("cairo"))) ff <- "Times"

  grid::grid.newpage()
  if (nzchar(as.character(title %||% "")[1L])) {
    grid::grid.text(
      as.character(title)[1L],
      x = grid::unit(0.5, "npc"),
      y = grid::unit(0.975, "npc"),
      gp = grid::gpar(fontsize = 12, fontface = "bold", fontfamily = ff)
    )
  }

  y_top <- 0.93
  y_foot <- if (length(footnote)) 0.04 + 0.028 * length(footnote) else 0.03
  y_fork_top <- if (has_fork) 0.22 else y_foot + 0.02
  span <- max(0.35, y_top - y_fork_top - 0.02)
  # 主框略收矮、间隙加大：Exclude 框须完整放进间隙内（旧版 eh=0.12 > gap=0.048 会压住主框）
  box_h <- min(0.095, span / (n_box + max(n_box - 1L, 1L) * 0.85))
  gap <- min(0.085, max(0.06, box_h * 0.85))
  box_h <- min(box_h, (span - (n_box - 1L) * gap) / n_box)
  cx <- 0.30
  mw <- 0.44
  x0 <- cx - mw / 2
  x1 <- cx + mw / 2
  # Exclude 框加宽：文字尽量横排一行（对齐 12_AKI/AF），勿挤成竖排
  ex0 <- 0.565
  ex1 <- 0.985
  fill_main <- if (identical(box_fill, "#F7F7F7")) "#FFFFFF" else box_fill
  if (!nzchar(as.character(fill_main %||% "")[1L])) fill_main <- "#FFFFFF"

  ys0 <- numeric(n_box)
  ys1 <- numeric(n_box)
  for (i in seq_len(n_box)) {
    y1i <- y_top - (i - 1) * (box_h + gap)
    y0i <- y1i - box_h
    ys0[i] <- y0i
    ys1[i] <- y1i
    fill_i <- if (i == n_box) "#eef6ff" else fill_main
    # 主框标签去掉「; excluded N」冗余（排除数已由右侧 Exclude 框说明），避免折行
    step_lab <- sub(";\\s*excluded[^)]*", "", as.character(rows$step[i]), ignore.case = TRUE)
    step_lab <- sub("\\s*\\(excluded[^)]*\\)\\s*", "", step_lab, ignore.case = TRUE)
    step_lab <- trimws(step_lab)
    if (!nzchar(step_lab)) step_lab <- as.character(rows$step[i])
    lab <- sprintf(
      "%s\nn = %s",
      .attrition_wrap_label(step_lab, 36L),
      format(as.integer(rows$n[i]), big.mark = ",")
    )
    .attrition_grid_roundbox(x0, y0i, x1, y1i, fill_i, ff, lab, fontsize = 10.5)
    if (i < n_box) {
      ymid <- (y0i + (y0i - gap)) / 2
      .attrition_grid_arrow(cx, y0i - 0.004, cx, y0i - gap + 0.006, ff)
      drop_n <- as.integer(rows$n[i]) - as.integer(rows$n[i + 1L])
      el <- NA_character_
      if ("exclude_label" %in% names(rows)) {
        el <- as.character(rows$exclude_label[i + 1L])[1L]
      }
      sid <- if ("step_id" %in% names(rows)) as.character(rows$step_id[i + 1L])[1L] else NA_character_
      is_weight_step <- identical(sid, "after_survey_weight") ||
        grepl("survey weight", el %||% "", ignore.case = TRUE) ||
        grepl("Eligible survey-weighted", as.character(rows$step[i + 1L])[1L], ignore.case = TRUE)
      # 调查权重步即使剔除 0 人也要画 Exclude 框（标明权重名与 n=0）
      show_exclude <- is.finite(drop_n) && (drop_n > 0L || isTRUE(is_weight_step))
      if (isTRUE(show_exclude)) {
        # 每步写清「排除了什么」：优先 exclude_label → step_id 语义 → 步骤标签抽取
        if (is.na(el) || !nzchar(el)) el <- .attrition_exclude_reason(sid, rows$step[i + 1L])
        if (is.na(el) || !nzchar(el)) {
          nxt <- as.character(rows$step[i + 1L])[1L]
          el <- sub("\\s*\\((?:[^()]*excluded[^()]*|[0-9,]+)\\)\\s*$", "", nxt, ignore.case = TRUE)
          el <- sub("\\s*[;,]\\s*excluded.*$", "", el, ignore.case = TRUE)
          el <- trimws(el)
          if (!nzchar(el) || grepl("^(after|starting)", el, ignore.case = TRUE)) el <- "Excluded"
        }
        el <- sub("^[Ee]xclude[d]?[: ]*", "", el)
        if (!nzchar(el)) el <- "Excluded"
        # 两行横排：原因一行、人数一行；框宽约 0.42npc，单行 45+ 字会溢出
        ex_lab <- sprintf(
          "Exclude: %s\n(n = %s)",
          .attrition_wrap_label(el, 30L),
          format(max(0L, as.integer(drop_n)), big.mark = ",")
        )
        eh <- min(gap * 0.92, 0.075)
        .attrition_grid_roundbox(
          ex0, ymid - eh / 2, ex1, ymid + eh / 2,
          "#f7f7f7", ff, ex_lab, fontsize = 8, fontface = "plain"
        )
        # 横向虚线箭头（对齐参考图）：从主列分叉水平指向 Exclude 框
        .attrition_grid_arrow(cx, ymid, ex0 - 0.006, ymid, ff, lty = 2)
      }
    }
  }

  if (has_fork) {
    last_y0 <- ys0[n_box]
    oh <- 0.11
    gapf <- 0.06
    # 分叉双框必须完整落在画布内：旧版 ow=0.28 时 left_x0=cx-0.03-0.28<0，
    # 粉色病例框左缘被裁切（用户反馈「最下面左面的粉色框没画全」）。
    ow <- min(0.28, cx - gapf / 2 - 0.02)
    left_x0 <- cx - gapf / 2 - ow
    right_x0 <- cx + gapf / 2
    y_out <- max(y_foot + 0.02, last_y0 - 0.08 - oh)
    t_y <- y_out + oh + 0.025
    grid::grid.lines(
      x = grid::unit(c(cx, cx), "npc"),
      y = grid::unit(c(last_y0, t_y), "npc"),
      gp = grid::gpar(col = "#222222", lwd = 1.15)
    )
    grid::grid.lines(
      x = grid::unit(c(left_x0 + ow / 2, right_x0 + ow / 2), "npc"),
      y = grid::unit(c(t_y, t_y), "npc"),
      gp = grid::gpar(col = "#222222", lwd = 1.15)
    )
    .attrition_grid_arrow(left_x0 + ow / 2, t_y, left_x0 + ow / 2, y_out + oh, ff)
    .attrition_grid_arrow(right_x0 + ow / 2, t_y, right_x0 + ow / 2, y_out + oh, ff)
    left_txt <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(fork$left_label, 22L),
      format(as.integer(fork$left_n), big.mark = ",")
    )
    right_txt <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(fork$right_label, 22L),
      format(as.integer(fork$right_n), big.mark = ",")
    )
    .attrition_grid_roundbox(
      left_x0, y_out, left_x0 + ow, y_out + oh,
      "#fff5f5", ff, left_txt, fontsize = 10
    )
    .attrition_grid_roundbox(
      right_x0, y_out, right_x0 + ow, y_out + oh,
      "#f3fff5", ff, right_txt, fontsize = 10
    )
  }

  if (length(footnote)) {
    fn_txt <- paste(footnote, collapse = "\n")
    grid::grid.text(
      fn_txt,
      x = grid::unit(0.5, "npc"),
      y = grid::unit(0.035, "npc"),
      gp = grid::gpar(fontsize = 8, fontfamily = ff, col = "#333333", lineheight = 1.15)
    )
  }
  invisible(TRUE)
}
