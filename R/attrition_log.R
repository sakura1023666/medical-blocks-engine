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

#' 在 Starting cohort 主框补调查年份（如 2005-2023 / 2015），幂等。
attrition_annotate_starting_years <- function(rows, years) {
  years <- trimws(as.character(years %||% "")[1L])
  if (!nzchar(years) || is.null(rows) || !is.data.frame(rows) || !nrow(rows)) {
    return(rows)
  }
  if (!"step" %in% names(rows)) return(rows)
  sid <- if ("step_id" %in% names(rows)) as.character(rows$step_id) else rep("", nrow(rows))
  hit <- which(
    grepl("^starting", sid, ignore.case = TRUE) |
      grepl("^starting\\s+cohort", as.character(rows$step), ignore.case = TRUE)
  )
  if (!length(hit)) return(rows)
  i <- hit[[1L]]
  lab <- as.character(rows$step[[i]])[1L]
  if (!nzchar(lab) || identical(lab, "NA")) lab <- "Starting cohort"
  if (grepl(years, lab, fixed = TRUE)) return(rows)
  base <- sub("\\s*\\n.*$", "", lab)
  base <- sub("\\s*\\([^)]*\\)\\s*$", "", base)
  base <- trimws(base)
  if (!nzchar(base)) base <- "Starting cohort"
  rows$step[[i]] <- paste0(base, "\n(", years, ")")
  rows
}

#' 从 config$attrition 解析某库年份（years_by_db 优先，否则 years_label）。
attrition_years_for_db <- function(cfg, db_name = NULL) {
  att <- (cfg %||% list())$attrition %||% list()
  by <- att$years_by_db %||% list()
  db <- trimws(as.character(db_name %||% "")[1L])
  y <- ""
  if (length(by) && nzchar(db)) {
    if (!is.null(by[[db]])) y <- as.character(by[[db]])[1L]
    if (!nzchar(y)) {
      nms <- names(by)
      hit <- nms[tolower(nms) == tolower(db)]
      if (length(hit)) y <- as.character(by[[hit[[1L]]]])[1L]
    }
  }
  if (!nzchar(y)) y <- as.character(att$years_label %||% "")[1L]
  trimws(y)
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

  # Starting 框补年份：优先当前库 years_by_db，否则 years_label
  db_now <- tryCatch({
    dual <- (config %||% list())$dual_db %||% list()
    as.character(dual$current_db %||% (config$attrition %||% list())$db_label %||% "")[1L]
  }, error = function(e) "")
  rows_df <- attrition_annotate_starting_years(
    rows_df, attrition_years_for_db(config, db_now)
  )

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

#' 发病纳排版式（对齐预后 v2 Figure 1）：左列三框，右侧两格排除，底部分叉。
.attrition_pv2_collapse_rows <- function(rows) {
  if (is.null(rows) || !nrow(rows) || nrow(rows) <= 2L) return(rows)
  keep <- rep(TRUE, nrow(rows))
  for (i in seq.int(2L, nrow(rows) - 1L)) {
    dn <- suppressWarnings(as.integer(rows$n[i - 1L]) - as.integer(rows$n[i]))
    el <- if ("exclude_label" %in% names(rows)) as.character(rows$exclude_label[i])[1L] else ""
    if (is.na(el) || identical(el, "NA")) el <- ""
    sid <- if ("step_id" %in% names(rows)) as.character(rows$step_id[i])[1L] else ""
    if (is.na(sid) || identical(sid, "NA")) sid <- ""
    weight <- identical(sid, "after_survey_weight") ||
      grepl("survey weight", el, ignore.case = TRUE)
    if (is.finite(dn) && dn == 0L && !nzchar(trimws(el)) && !isTRUE(weight)) {
      keep[i] <- FALSE
    }
  }
  rows[keep, , drop = FALSE]
}

#' 指标算不出时，用公式里真正缺失的组成变量写排除框。
#' 一句里能排开就排开；画图端对多行左对齐。
attrition_key_missing_label_from_index <- function(df, index_name) {
  index_name <- as.character(index_name %||% "")[1L]
  if (!nzchar(index_name) || is.null(df) || !is.data.frame(df) || !index_name %in% names(df)) {
    return("")
  }
  comps <- character(0)
  if (exists("index_get_formula_components", mode = "function")) {
    comps <- tryCatch(index_get_formula_components(index_name), error = function(e) character(0))
  }
  comps <- unique(as.character(comps))
  comps <- intersect(comps, names(df))
  comps <- setdiff(comps, index_name)
  if (!length(comps)) return("")
  vals <- df[[index_name]]
  dropped <- if (is.numeric(vals)) !is.finite(vals) else is.na(vals) | !nzchar(trimws(as.character(vals)))
  if (!any(dropped)) return("")
  sub <- df[dropped, comps, drop = FALSE]
  hit <- comps[vapply(comps, function(v) {
    x <- sub[[v]]
    if (is.numeric(x)) any(!is.finite(x)) else any(is.na(x) | !nzchar(trimws(as.character(x))))
  }, logical(1L))]
  if (!length(hit)) hit <- comps
  labs <- if (exists("pipeline_display_label", mode = "function")) {
    pipeline_display_label(hit)
  } else {
    gsub("_", " ", hit, fixed = TRUE)
  }
  labs <- trimws(as.character(labs))
  labs <- labs[nzchar(labs)]
  if (!length(labs)) return("")
  if (length(labs) == 1L) return(paste0("Missing ", labs))
  if (length(labs) == 2L) return(paste0("Missing ", labs[1L], " or ", labs[2L]))
  paste0("Missing ", paste(labs[-length(labs)], collapse = ", "), ", or ", labs[length(labs)])
}

.attrition_pv2_fmt_n <- function(x) {
  x <- suppressWarnings(as.integer(x)[1L])
  if (!is.finite(x)) return("—")
  format(max(0L, x), big.mark = ",")
}

.attrition_pv2_reason <- function(rows, i) {
  el <- if ("exclude_label" %in% names(rows)) {
    raw <- rows$exclude_label[i]
    if (is.na(raw)) "" else as.character(raw)[1L]
  } else {
    ""
  }
  if (identical(el, "NA")) el <- ""
  sid <- if ("step_id" %in% names(rows)) {
    raw <- rows$step_id[i]
    if (is.na(raw)) "" else as.character(raw)[1L]
  } else {
    ""
  }
  if (!nzchar(el)) el <- .attrition_exclude_reason(sid, rows$step[i])
  if (!nzchar(el)) el <- as.character(rows$step[i])[1L]
  el <- sub("^[Ee]xclude[d]?[: ]*", "", el)
  el <- trimws(el)
  if (!nzchar(el) || identical(el, "NA")) el <- "Excluded"
  el <- gsub("_", " ", el, fixed = TRUE)
  el
}

.attrition_pv2_count_line <- function(label, n, width = 72L) {
  label <- as.character(label %||% "")[1L]
  bits <- strsplit(label, "\n", fixed = TRUE)[[1L]]
  bits <- trimws(gsub("[[:space:]]+", " ", bits))
  bits <- bits[nzchar(bits)]
  if (!length(bits)) bits <- ""
  bits[length(bits)] <- sprintf("%s (n = %s)", bits[length(bits)], .attrition_pv2_fmt_n(n))
  paste(vapply(bits, function(b) .attrition_wrap_label(b, width), character(1L)), collapse = "\n")
}

#' Figure 1 库名展示：保留 eICU / MIMIC_IV 等惯用大小写，勿整串 toupper 成 EICU。
.attrition_pv2_db_display <- function(db) {
  x <- trimws(as.character(db %||% "")[1L])
  if (!nzchar(x)) return("Cohort")
  key <- toupper(gsub("[^A-Za-z0-9]", "", x))
  map <- c(
    EICU = "eICU",
    MIMICIV = "MIMIC_IV",
    MIMIC = "MIMIC",
    NHANES = "NHANES",
    CHARLS = "CHARLS",
    ELSA = "ELSA",
    KNHANES = "KNHANES"
  )
  if (key %in% names(map)) return(unname(map[[key]]))
  x
}

#' 发病 Figure 1：第一框写数据库和年份，第一格排除年龄，其余排除编号放在第二格。
.attrition_pv2_panel_from_cohort <- function(rows, letter, cohort) {
  db <- .attrition_pv2_db_display(cohort$database %||% "NHANES")
  years <- trimws(as.character(cohort$years %||% "")[1L])
  ## 无年份时两行（Participants in DB / n=），与截图版式一致；有年份才三行
  top <- if (nzchar(years)) {
    sprintf(
      "Participants in %s\n%s\n(n = %s)",
      db, years, .attrition_pv2_fmt_n(cohort$n_source)
    )
  } else {
    sprintf(
      "Participants in %s\n(n = %s)",
      db, .attrition_pv2_fmt_n(cohort$n_source)
    )
  }
  sw <- suppressWarnings(as.integer(cohort$side_line_width)[1L])
  if (!is.finite(sw) || sw < 16L) sw <- 26L
  side1 <- .attrition_pv2_count_line(cohort$age_exclude_label, cohort$age_exclude_n, sw)
  mid <- sprintf(
    "%s\n(n = %s)",
    as.character(cohort$age_keep_label)[1L],
    .attrition_pv2_fmt_n(cohort$age_keep_n)
  )
  items <- list()
  pre <- cohort$pre_exclusions %||% list()
  if (is.data.frame(pre)) pre <- lapply(seq_len(nrow(pre)), function(i) as.list(pre[i, , drop = FALSE]))
  for (one in pre) {
    items[[length(items) + 1L]] <- list(
      label = as.character(one$label)[1L],
      n = one$n
    )
  }
  rows2 <- .attrition_pv2_collapse_rows(rows)
  if (nrow(rows2) >= 2L) {
    for (i in seq.int(2L, nrow(rows2))) {
      sid <- if ("step_id" %in% names(rows2)) as.character(rows2$step_id[i])[1L] else ""
      ## 年龄排除已在 side1（cohort$age_exclude_*），勿再塞进编号列表
      if (identical(sid, "after_age_filter") || identical(sid, "age_filter") ||
          grepl("(?i)^age\\s*filter", as.character(rows2$step[i])[1L])) {
        next
      }
      dn <- suppressWarnings(as.integer(rows2$n[i - 1L]) - as.integer(rows2$n[i]))
      el <- .attrition_pv2_reason(rows2, i)
      km <- trimws(as.character(cohort$key_missing_label %||% "")[1L])
      if (nzchar(km) && grepl("^Missing key variables$", el)) el <- km
      weight <- identical(sid, "after_survey_weight") ||
        grepl("survey weight", el, ignore.case = TRUE)
      wl <- trimws(as.character(cohort$survey_weight_label %||% "")[1L])
      if (isTRUE(weight) && nzchar(wl) && !identical(wl, "NA")) el <- wl
      if (!is.finite(dn)) dn <- 0L
      if (dn > 0L || isTRUE(weight)) {
        items[[length(items) + 1L]] <- list(label = el, n = max(0L, dn))
      }
    }
  }
  if (!length(items)) {
    side2 <- "No further exclusion\n(n = 0)"
  } else {
    lines <- vapply(seq_along(items), function(k) {
      .attrition_pv2_count_line(
        sprintf("%d. %s", k, items[[k]]$label),
        items[[k]]$n,
        max(16L, sw - 3L)
      )
    }, character(1L))
    side2 <- paste(lines, collapse = "\n")
  }
  inc_n <- if (nrow(rows2)) rows2$n[nrow(rows2)] else cohort$age_keep_n
  inc <- sprintf("Participants included\n(n = %s)", .attrition_pv2_fmt_n(inc_n))
  fork <- .attrition_fork_from_rows(rows)
  if (is.null(fork)) {
    left <- "Cases\n(n = —)"
    right <- "Controls\n(n = —)"
    has_fork <- FALSE
  } else {
    left <- sprintf("%s\n(n = %s)", .attrition_wrap_label(fork$left_label, 18L), .attrition_pv2_fmt_n(fork$left_n))
    right <- sprintf("%s\n(n = %s)", .attrition_wrap_label(fork$right_label, 18L), .attrition_pv2_fmt_n(fork$right_n))
    has_fork <- TRUE
  }
  list(
    letter = as.character(letter %||% "")[1L],
    top = top, mid = mid, inc = inc, side1 = side1, side2 = side2,
    death = left, alive = right, has_fork = has_fork
  )
}

#' 从 attrition 行 + config 年份自动拼 pv2 cohort（Participants in DB / 年份 版式）
attrition_pv2_cohort_from_rows <- function(rows, config = NULL, database = NULL) {
  if (!is.data.frame(rows) || !nrow(rows) || !"n" %in% names(rows)) return(NULL)
  db <- toupper(trimws(as.character(database %||% "")[1L]))
  if (!nzchar(db) && "database" %in% names(rows)) {
    db <- toupper(trimws(as.character(rows$database[1L])[1L]))
  }
  if (!nzchar(db)) db <- "COHORT"
  years <- ""
  if (!is.null(config) && exists("attrition_years_for_db", mode = "function")) {
    years <- as.character(attrition_years_for_db(config, db) %||% "")[1L]
  }
  if (!nzchar(years) || identical(years, "NA")) {
    years <- as.character((config$attrition %||% list())$years_label %||% "")[1L]
  }
  # 若 Starting 步已写成 "Starting cohort (2005-2023)"，可回退解析年份
  if ((!nzchar(years) || identical(years, "NA")) && "step" %in% names(rows)) {
    st0 <- as.character(rows$step[1L])[1L]
    m <- regmatches(st0, regexpr("\\(([0-9]{4}[^)]*)\\)", st0))
    if (length(m) && nzchar(m)) years <- gsub("[()]", "", m)
  }
  n0 <- suppressWarnings(as.integer(rows$n[1L])[1L])
  if (!is.finite(n0)) return(NULL)

  age_ex_n <- 0L
  age_keep_n <- n0
  # 发表固定文案（与截图一致）；禁止 exclude_label=NA 渗进侧框
  age_ex_lab <- "Age < 18 or missing age"
  age_keep_lab <- "Aged \u2265 18 years"
  if (nrow(rows) >= 2L) {
    sid2 <- if ("step_id" %in% names(rows)) as.character(rows$step_id[2L])[1L] else ""
    st2 <- as.character(rows$step[2L])[1L]
    is_age <- identical(sid2, "after_age_filter") || identical(sid2, "age_filter") ||
      grepl("(?i)age\\s*(filter|\u2265|>=)|Aged|Age outside", st2)
    if (is_age) {
      age_keep_n <- suppressWarnings(as.integer(rows$n[2L])[1L])
      if (!is.finite(age_keep_n)) age_keep_n <- n0
      age_ex_n <- max(0L, n0 - age_keep_n)
      if (grepl("Aged|Age\\s*\u2265|Age\\s*>=", st2, ignore.case = TRUE)) {
        age_keep_lab <- sub(";\\s*excluded.*$", "", st2, ignore.case = TRUE)
        age_keep_lab <- trimws(sub("\\s*\\(excluded[^)]*\\)\\s*", "", age_keep_lab, ignore.case = TRUE))
      }
    }
  }
  if (!nzchar(as.character(age_ex_lab %||% "")[1L]) ||
      grepl("(?i)^na$", trimws(as.character(age_ex_lab)[1L]))) {
    age_ex_lab <- "Age < 18 or missing age"
  }

  wt_lab <- "Missing or non-positive survey weights (new_weight from WTMEC2YR / WTMEC4YR)"
  key_lab <- "Missing key variables"
  ix <- as.character((config$incidence %||% list())$index_var %||%
    (config$project %||% list())$index %||% "")[1L]
  if (nzchar(ix) && !identical(ix, "NA")) key_lab <- paste0("Missing ", ix)

  list(
    database = db,
    years = years,
    n_source = n0,
    age_exclude_label = age_ex_lab,
    age_exclude_n = as.integer(age_ex_n)[1L],
    age_keep_label = age_keep_lab,
    age_keep_n = as.integer(age_keep_n)[1L],
    key_missing_label = key_lab,
    survey_weight_label = wt_lab,
    side_line_width = 26L
  )
}

.attrition_pv2_panel_spec <- function(rows, letter = "", cohort = NULL) {
  if (is.list(cohort) && is.finite(suppressWarnings(as.numeric(cohort$n_source)[1L]))) {
    return(.attrition_pv2_panel_from_cohort(rows, letter, cohort))
  }
  rows <- .attrition_pv2_collapse_rows(rows)
  n <- nrow(rows)
  plain <- function(i) {
    lab <- sub(";\\s*excluded.*$", "", as.character(rows$step[i])[1L], ignore.case = TRUE)
    lab <- sub("\\s*\\(excluded[^)]*\\)\\s*", "", lab, ignore.case = TRUE)
    trimws(lab)
  }
  box_lab <- function(i) {
    sprintf("%s\n(n = %s)", .attrition_wrap_label(plain(i), 32L), .attrition_pv2_fmt_n(rows$n[i]))
  }
  if (n <= 1L) {
    top <- mid <- inc <- box_lab(1L)
    side1 <- "No exclusion\n(n = 0)"
    side2 <- "No further exclusion\n(n = 0)"
  } else if (n == 2L) {
    dn <- suppressWarnings(as.integer(rows$n[1L]) - as.integer(rows$n[2L]))
    top <- box_lab(1L)
    mid <- box_lab(2L)
    inc <- sprintf("Participants included\n(n = %s)", .attrition_pv2_fmt_n(rows$n[2L]))
    side1 <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(.attrition_pv2_reason(rows, 2L), 28L),
      .attrition_pv2_fmt_n(dn)
    )
    side2 <- "No further exclusion\n(n = 0)"
  } else {
    top <- box_lab(1L)
    mid <- box_lab(2L)
    inc <- box_lab(n)
    dn1 <- suppressWarnings(as.integer(rows$n[1L]) - as.integer(rows$n[2L]))
    side1 <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(.attrition_pv2_reason(rows, 2L), 28L),
      .attrition_pv2_fmt_n(dn1)
    )
    lines <- character(0)
    k <- 0L
    for (i in seq.int(3L, n)) {
      k <- k + 1L
      dn <- suppressWarnings(as.integer(rows$n[i - 1L]) - as.integer(rows$n[i]))
      lines <- c(lines, sprintf(
        "%d. %s (n = %s)",
        k,
        .attrition_wrap_label(.attrition_pv2_reason(rows, i), 26L),
        .attrition_pv2_fmt_n(dn)
      ))
    }
    side2 <- paste(lines, collapse = "\n")
  }
  fork <- .attrition_fork_from_rows(rows)
  if (is.null(fork)) {
    left <- "Cases\n(n = —)"
    right <- "Controls\n(n = —)"
    has_fork <- FALSE
  } else {
    left <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(fork$left_label, 18L),
      .attrition_pv2_fmt_n(fork$left_n)
    )
    right <- sprintf(
      "%s\n(n = %s)",
      .attrition_wrap_label(fork$right_label, 18L),
      .attrition_pv2_fmt_n(fork$right_n)
    )
    has_fork <- TRUE
  }
  list(
    letter = as.character(letter %||% "")[1L],
    top = top, mid = mid, inc = inc,
    side1 = side1, side2 = side2,
    death = left, alive = right, has_fork = has_fork
  )
}

.attrition_pv2_draw_panel <- function(p) {
  ff <- "Times"
  box <- function(x0, y0, x1, y1, lab, fs = 7.2, just = "centre") {
    if (!nzchar(lab %||% "")) return(invisible(NULL))
    grid::grid.roundrect(
      x = grid::unit((x0 + x1) / 2, "npc"), y = grid::unit((y0 + y1) / 2, "npc"),
      width = grid::unit(x1 - x0, "npc"), height = grid::unit(y1 - y0, "npc"),
      r = grid::unit(0.02, "npc"),
      gp = grid::gpar(fill = "white", col = "black", lwd = 0.8)
    )
    if (identical(just, "left")) {
      grid::grid.text(
        lab, x = x0 + 0.012, y = (y0 + y1) / 2, just = c("left", "centre"),
        gp = grid::gpar(fontsize = fs, fontfamily = ff, lineheight = 0.95)
      )
    } else {
      grid::grid.text(
        lab, x = (x0 + x1) / 2, y = (y0 + y1) / 2,
        gp = grid::gpar(fontsize = fs, fontfamily = ff, lineheight = 0.95)
      )
    }
  }
  varrow <- function(x, y1, y0) {
    grid::grid.lines(
      x = grid::unit(c(x, x), "npc"), y = grid::unit(c(y1, y0), "npc"),
      arrow = grid::arrow(length = grid::unit(0.09, "inches"), type = "closed"),
      gp = grid::gpar(fill = "black", col = "black", lwd = 0.7)
    )
  }
  harrow <- function(x0, x1, y) {
    grid::grid.lines(
      x = grid::unit(c(x0, x1), "npc"), y = grid::unit(c(y, y), "npc"),
      arrow = grid::arrow(length = grid::unit(0.09, "inches"), type = "closed"),
      gp = grid::gpar(fill = "black", col = "black", lwd = 0.7)
    )
  }
  ## 单栏 Fig1：整块流程图水平居中（旧版贴左 0.02，右侧大片留白）
  ## 主列 [ml, mr]、中轴 cx、排除列 [sx0, sx1_max] 对称落在画布中部。
  ml <- 0.14
  mr <- 0.54
  cx <- (ml + mr) / 2
  sx0 <- 0.60
  sx1_max <- 0.94
  fork_gap <- 0.04
  fork_w <- (mr - ml - fork_gap) / 2
  if (nzchar(p$letter %||% "")) {
    grid::grid.text(
      p$letter, x = ml - 0.06, y = 0.985, just = c("left", "top"),
      gp = grid::gpar(fontsize = 11, fontface = "bold", fontfamily = ff)
    )
  }
  # 左列主流程固定。右侧排除框按行数收高，避免大块空白。
  box(ml, 0.78, mr, 0.94, p$top, fs = 8)
  box(ml, 0.50, mr, 0.64, p$mid, fs = 8)
  box(ml, 0.22, mr, 0.36, p$inc, fs = 8)
  if (isTRUE(p$has_fork)) {
    box(ml, 0.02, ml + fork_w, 0.13, p$death, fs = 7.2)
    box(mr - fork_w, 0.02, mr, 0.13, p$alive, fs = 7.2)
  }
  nline <- function(lab) max(1L, length(strsplit(as.character(lab %||% ""), "\n", fixed = TRUE)[[1L]]))
  side_h <- function(lab) min(0.18, max(0.075, 0.028 * nline(lab) + 0.030))
  side_just <- function(lab) {
    if (grepl("\n", as.character(lab %||% ""), fixed = TRUE)) "left" else "centre"
  }
  # 排除框贴在箭头右侧。单行放不下就按剩余页宽换行，不把字画到页外。
  side_box <- function(y, lab, fs) {
    pad <- 0.028
    avail <- sx1_max - sx0 - pad
    lab <- .attrition_fit_side_text(lab, fs, ff, avail)
    lines <- strsplit(as.character(lab %||% ""), "\n", fixed = TRUE)[[1L]]
    gp <- grid::gpar(fontsize = fs, fontfamily = ff)
    tw <- max(vapply(lines, function(ln) {
      if (!nzchar(ln)) return(0)
      grid::convertWidth(
        grid::grobWidth(grid::textGrob(ln, gp = gp)),
        "npc", valueOnly = TRUE
      )
    }, numeric(1L)))
    x1 <- min(sx1_max, sx0 + tw + pad)
    h <- side_h(lab)
    box(sx0, y - h / 2, x1, y + h / 2, lab, fs = fs, just = side_just(lab))
    harrow(cx, sx0, y)
  }
  y1 <- 0.71
  y2 <- 0.43
  varrow(cx, 0.78, 0.64)
  side_box(y1, p$side1, 7.2)
  varrow(cx, 0.50, 0.36)
  side_box(y2, p$side2, 7)
  if (isTRUE(p$has_fork)) {
    fl <- ml + fork_w / 2
    fr <- mr - fork_w / 2
    grid::grid.lines(
      x = grid::unit(c(cx, cx), "npc"), y = grid::unit(c(0.22, 0.165), "npc"),
      gp = grid::gpar(col = "black", lwd = 0.7)
    )
    grid::grid.lines(
      x = grid::unit(c(fl, fr), "npc"), y = grid::unit(c(0.165, 0.165), "npc"),
      gp = grid::gpar(col = "black", lwd = 0.7)
    )
    varrow(fl, 0.165, 0.13)
    varrow(fr, 0.165, 0.13)
  }
}

attrition_pv2_letter <- function(rows, index = 1L) {
  db <- ""
  if (is.data.frame(rows) && "database" %in% names(rows)) {
    db <- toupper(trimws(as.character(rows$database[1L])[1L]))
  }
  db <- sub("_COPY$", "", db)
  lab <- c("A", "B", "C", "D", "E", "F")
  L <- if (index <= length(lab)) lab[[index]] else as.character(index)
  if (!nzchar(db)) return(L)
  paste(L, db)
}

#' 单库或双库发病纳排图，版式与预后 v2 Figure 1 相同。
attrition_draw_pv2_pdf <- function(rows_by_db, pdf_path, cohort = NULL, width = NULL,
                                   config = NULL) {
  if (is.data.frame(rows_by_db)) {
    rows_by_db <- list(rows_by_db)
  }
  if (is.null(rows_by_db) || !length(rows_by_db)) return(invisible(FALSE))
  rows_by_db <- rows_by_db[vapply(rows_by_db, function(x) {
    is.data.frame(x) && nrow(x) > 0L && all(c("step", "n") %in% names(x))
  }, logical(1L))]
  if (!length(rows_by_db)) return(invisible(FALSE))
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  n <- length(rows_by_db)
  w <- if (is.numeric(width) && is.finite(width[1L])) width[1L] else if (n == 1L) 5.6 else 5.2 * n
  h <- 6.35
  ok <- tryCatch({
    grDevices::cairo_pdf(pdf_path, width = w, height = h, family = "Times")
    TRUE
  }, error = function(e) {
    tryCatch({
      grDevices::pdf(pdf_path, width = w, height = h, family = "Times")
      TRUE
    }, error = function(e2) FALSE)
  })
  if (!isTRUE(ok)) return(invisible(FALSE))
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  # cohort 可为：单库 list；或按库名 named list；缺省时从 rows+config 自动拼 Participants in 版式
  cohorts_by_db <- NULL
  if (is.list(cohort) && !is.null(names(cohort)) &&
      any(vapply(cohort, function(x) is.list(x) && !is.null(x$n_source), logical(1L)))) {
    cohorts_by_db <- cohort
  }
  for (i in seq_len(n)) {
    grid::pushViewport(grid::viewport(
      x = (i - 0.5) / n, y = 0.5, width = 1 / n, height = 1
    ))
    rows_i <- rows_by_db[[i]]
    panel_db <- ""
    if (is.data.frame(rows_i) && "database" %in% names(rows_i)) {
      panel_db <- toupper(trimws(as.character(rows_i$database[1L])[1L]))
    }
    panel_nm <- toupper(trimws(as.character(names(rows_by_db)[i] %||% "")[1L]))
    if (!nzchar(panel_db)) panel_db <- panel_nm
    panel_db <- sub("_COPY$", "", panel_db)

    cohort_i <- NULL
    if (!is.null(cohorts_by_db) && nzchar(panel_db)) {
      hit <- names(cohorts_by_db)[toupper(names(cohorts_by_db)) == panel_db]
      if (length(hit)) cohort_i <- cohorts_by_db[[hit[[1L]]]]
    }
    if (is.null(cohort_i) && is.list(cohort) && is.null(cohorts_by_db)) {
      want_db <- toupper(trimws(as.character(cohort$database %||% "")[1L]))
      cohort_i <- cohort
      if (nzchar(want_db) && nzchar(panel_db) &&
          !identical(want_db, panel_db) &&
          !grepl(want_db, panel_db, fixed = TRUE) &&
          !grepl(panel_db, want_db, fixed = TRUE)) {
        cohort_i <- NULL
      }
    }
    if (is.null(cohort_i) || !is.finite(suppressWarnings(as.numeric(cohort_i$n_source)[1L]))) {
      cohort_i <- attrition_pv2_cohort_from_rows(rows_i, config = config, database = panel_db)
    }
    letter_i <- attrition_pv2_letter(rows_by_db[[i]], i)
    if (is.list(cohort_i) && nzchar(trimws(as.character(cohort_i$database %||% "")[1L]))) {
      lab <- c("A", "B", "C", "D", "E", "F")
      L <- if (i <= length(lab)) lab[[i]] else as.character(i)
      letter_i <- paste(
        L,
        .attrition_pv2_db_display(cohort_i$database)
      )
    }
    spec <- .attrition_pv2_panel_spec(
      rows_by_db[[i]], letter_i, cohort = cohort_i
    )
    .attrition_pv2_draw_panel(spec)
    grid::popViewport()
  }
  invisible(file.exists(pdf_path))
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

.attrition_fit_side_text <- function(txt, fontsize, family, avail_npc) {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt) || !is.finite(avail_npc) || avail_npc <= 0) return(txt)
  gp <- grid::gpar(fontsize = fontsize, fontfamily = family)
  widest <- function(block) {
    lines <- strsplit(block, "\n", fixed = TRUE)[[1L]]
    max(vapply(lines, function(ln) {
      if (!nzchar(ln)) return(0)
      grid::convertWidth(
        grid::grobWidth(grid::textGrob(ln, gp = gp)),
        "npc", valueOnly = TRUE
      )
    }, numeric(1L)))
  }
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1L]]
  out <- character(0)
  for (ln in lines) {
    if (!nzchar(ln) || widest(ln) <= avail_npc) {
      out <- c(out, ln)
      next
    }
    plain <- gsub("[[:space:]]+", " ", trimws(ln))
    fitted <- plain
    for (w in seq.int(max(16L, nchar(plain) - 4L), 16L, by = -2L)) {
      wrapped <- paste(strwrap(plain, width = w), collapse = "\n")
      fitted <- wrapped
      if (widest(wrapped) <= avail_npc) break
    }
    out <- c(out, strsplit(fitted, "\n", fixed = TRUE)[[1L]])
  }
  paste(out, collapse = "\n")
}

.attrition_wrap_label <- function(txt, width = 32L) {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt)) return("")
  paste(strwrap(txt, width = as.integer(width)[1L]), collapse = "\n")
}

# 把人工换行收成逻辑行。编号项各自成句；同一句里的 (n =) 拼回这一句。
.attrition_logical_lines <- function(txt) {
  raw <- strsplit(as.character(txt %||% "")[1L], "\n", fixed = TRUE)[[1L]]
  blocks <- character(0)
  cur <- ""
  flush <- function() {
    if (nzchar(cur)) blocks <<- c(blocks, trimws(cur))
    cur <<- ""
  }
  for (ln in raw) {
    ln <- trimws(ln)
    if (!nzchar(ln)) {
      flush()
      next
    }
    new_item <- grepl("^[0-9]+\\.\\s", ln) || grepl("(?i)^exclude:", ln)
    if (new_item && nzchar(cur)) flush()
    cur <- if (!nzchar(cur)) ln else paste(cur, ln)
  }
  flush()
  blocks
}

#' 纳排文字在给定宽度下需要的框高（npc），含上下留白。
attrition_label_height_npc <- function(txt, width_npc, fontsize = 10, family = "Times",
                                       pad_npc = 0.012, min_npc = 0.045) {
  avail <- max(0.02, as.numeric(width_npc)[1L] - 2 * pad_npc)
  fitted <- attrition_reflow_label(txt, avail, fontsize, family)
  nln <- length(strsplit(fitted, "\n", fixed = TRUE)[[1L]])
  if (!nln) nln <- 1L
  lh <- grid::convertHeight(grid::stringHeight("Hg"), "npc", valueOnly = TRUE) * 1.15
  max(min_npc, lh * nln + 2 * pad_npc)
}

#' 纳排框文字：能放进宽度就一行，放不下再按词换行。返回带 \\n 的字符串。
attrition_reflow_label <- function(txt, width_npc, fontsize = 10, family = "Times") {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt)) return("")
  width_npc <- as.numeric(width_npc)[1L]
  if (!is.finite(width_npc) || width_npc <= 0) return(txt)
  blocks <- .attrition_logical_lines(txt)
  if (!length(blocks)) return("")
  fitted <- vapply(blocks, function(block) {
    .attrition_fit_side_text(block, fontsize, family, width_npc)
  }, character(1L))
  paste(fitted, collapse = "\n")
}

#' 框内文字。align = "centre" 为流程主框；"left" 为右侧排除框。
#' reflow = TRUE 时按框宽把能放下的句子收成一行。
attrition_draw_box_text <- function(text, x0, y0, x1, y1, fontsize = 10,
                                    family = "Times", fontface = "plain",
                                    pad_npc = 0.012, align = c("centre", "left"),
                                    reflow = FALSE) {
  align <- match.arg(align)
  avail <- max(0.02, abs(x1 - x0) - 2 * pad_npc)
  fitted <- if (isTRUE(reflow)) attrition_reflow_label(text, avail, fontsize, family) else as.character(text)[1L]
  lines <- strsplit(fitted, "\n", fixed = TRUE)[[1L]]
  lines <- lines[nzchar(lines)]
  if (!length(lines)) return(invisible(NULL))
  gp <- grid::gpar(fontsize = fontsize, fontface = fontface, fontfamily = family,
                   col = "#111111")
  lh <- grid::convertHeight(grid::stringHeight("Hg"), "npc", valueOnly = TRUE) * 1.15
  total <- lh * length(lines)
  box_h <- abs(y1 - y0)
  y_mid <- (y0 + y1) / 2
  y_first <- if (total < box_h - 2 * pad_npc) {
    y_mid + total / 2 - lh / 2
  } else {
    max(y0, y1) - pad_npc - lh / 2
  }
  x_pos <- if (align == "left") min(x0, x1) + pad_npc else (x0 + x1) / 2
  hjust <- if (align == "left") "left" else "centre"
  for (k in seq_along(lines)) {
    grid::grid.text(
      lines[k],
      x = grid::unit(x_pos, "npc"),
      y = grid::unit(y_first - (k - 1) * lh, "npc"),
      just = c(hjust, "centre"),
      gp = gp
    )
  }
  invisible(fitted)
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

#' 从步骤文案解析底部分叉（如 "Depression: 130; No Depression: 658"）
.attrition_parse_fork_from_step_text <- function(txt) {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt)) return(NULL)
  # Label: n; Label: n  （允许括号 / after excluding）
  m <- regexec(
    "(?i)([A-Za-z][A-Za-z0-9 /_-]{1,48})\\s*[:=]\\s*([0-9][0-9,]*)\\s*[;/,]\\s*([A-Za-z][A-Za-z0-9 /_-]{1,48})\\s*[:=]\\s*([0-9][0-9,]*)",
    txt,
    perl = TRUE
  )
  g <- regmatches(txt, m)[[1L]]
  if (length(g) < 5L) return(NULL)
  ll <- trimws(g[[2L]])
  ln <- suppressWarnings(as.integer(gsub(",", "", g[[3L]], fixed = TRUE)))
  rl <- trimws(g[[4L]])
  rn <- suppressWarnings(as.integer(gsub(",", "", g[[5L]], fixed = TRUE)))
  if (!is.finite(ln) || !is.finite(rn) || !nzchar(ll) || !nzchar(rl)) return(NULL)
  if (!grepl("(?i)group|case|control|depression|cataract|disease|death|surviv|yes|no|with|without",
             paste(ll, rl))) {
    # 仍接受常见结局对；否则也允许（数字可信即可）
  }
  list(left_label = ll, left_n = ln, right_label = rl, right_n = rn)
}

.attrition_infer_exclude_label <- function(step_label, n_drop) {
  lab <- as.character(step_label %||% "")[1L]
  n_drop <- suppressWarnings(as.integer(n_drop)[1L])
  if (!is.finite(n_drop) || n_drop <= 0L) return(NA_character_)
  el <- .attrition_exclude_reason("", lab)
  if (nzchar(el)) return(el)
  if (grepl("CKD|chronic kidney", lab, ignore.case = TRUE)) {
    return("Without chronic kidney disease")
  }
  if (grepl("periodontitis|depression outcome|available", lab, ignore.case = TRUE)) {
    return("Missing periodontitis grade or depression outcome")
  }
  if (grepl("extreme", lab, ignore.case = TRUE) ||
      grepl("final analytic|participants included", lab, ignore.case = TRUE)) {
    return("Extreme exposure or outcome values")
  }
  if (grepl("survey weight", lab, ignore.case = TRUE)) {
    return("Missing or non-positive survey weights")
  }
  # After excluding missing HHR / missing exposure index
  if (grepl("(?i)exclud(?:e|ing)\\s+missing\\s+([A-Za-z0-9_]+)", lab, perl = TRUE) ||
      grepl("(?i)missing\\s+([A-Za-z0-9_]+)", lab, perl = TRUE)) {
    m <- regmatches(
      lab,
      regexpr("(?i)(?:exclud(?:e|ing)\\s+)?missing\\s+([A-Za-z0-9_]+)", lab, perl = TRUE)
    )
    ix <- sub("(?i)^(?:exclud(?:e|ing)\\s+)?missing\\s+", "", m)
    ix <- gsub("_", " ", ix, fixed = TRUE)
    if (nzchar(ix) && !grepl("^(key|or)\\b", ix, ignore.case = TRUE)) {
      return(sprintf("Missing %s", ix))
    }
    return("Missing exposure index")
  }
  if (grepl("imput", lab, ignore.case = TRUE)) {
    return("Missing key variables")
  }
  if (grepl("age", lab, ignore.case = TRUE)) {
    return("Age not in eligible range")
  }
  if (grepl("clean", lab, ignore.case = TRUE)) {
    return("Incomplete covariates")
  }
  "Did not meet inclusion criteria"
}

#' 旧版仅 step/n 的纳排 CSV → pv2 所需列（exclude_label + fork）
#' @param rows data.frame
#' @param database 库名标签
#' @return 增强后的 rows
attrition_enrich_rows_for_pv2 <- function(rows, database = NULL) {
  if (is.null(rows) || !is.data.frame(rows) || !nrow(rows)) return(rows)
  if (!all(c("step", "n") %in% names(rows))) return(rows)
  rows <- rows[is.finite(suppressWarnings(as.integer(rows$n))), , drop = FALSE]
  if (!nrow(rows)) return(rows)
  rows$step <- as.character(rows$step)
  rows$n <- as.integer(rows$n)
  if (!"database" %in% names(rows) || all(!nzchar(as.character(rows$database %||% "")))) {
    db <- as.character(database %||% "NHANES")[1L]
    rows$database <- db
  }
  for (nm in c(
    "exclude_label", "fork_left_label", "fork_left_n",
    "fork_right_label", "fork_right_n"
  )) {
    if (!nm %in% names(rows)) {
      rows[[nm]] <- if (grepl("_n$", nm)) NA_integer_ else NA_character_
    }
  }
  # 逐步补 exclude_label（NA / "NA" / "" 均视为缺失；nzchar(NA)=TRUE 勿误判）
  for (i in seq_len(nrow(rows))) {
    el_raw <- rows$exclude_label[i]
    el <- if (is.na(el_raw)) "" else trimws(as.character(el_raw)[1L])
    if (identical(el, "NA")) el <- ""
    if (nzchar(el)) next
    if (i == 1L) {
      rows$exclude_label[i] <- NA_character_
      next
    }
    dn <- as.integer(rows$n[i - 1L]) - as.integer(rows$n[i])
    rows$exclude_label[i] <- .attrition_infer_exclude_label(rows$step[i], dn)
  }
  # 末步 fork：列已有则用列；否则从 step 文案解析
  last <- nrow(rows)
  fork <- .attrition_fork_from_rows(rows)
  if (is.null(fork)) {
    fork <- .attrition_parse_fork_from_step_text(rows$step[last])
  }
  if (!is.null(fork)) {
    rows$fork_left_label[last] <- fork$left_label
    rows$fork_left_n[last] <- fork$left_n
    rows$fork_right_label[last] <- fork$right_label
    rows$fork_right_n[last] <- fork$right_n
    # 清理末框文案，去掉括号内结局计数
    clean <- sub("\\s*\\([^)]*[:=]\\s*[0-9].*\\)\\s*$", "", rows$step[last])
    clean <- sub(
      "(?i)\\s*(after\\s+)?excluding\\s+extreme\\s+values\\s*.*$",
      "",
      clean,
      perl = TRUE
    )
    clean <- trimws(clean)
    if (!nzchar(clean) || grepl("(?i)^final analytic", clean)) {
      clean <- "Final analytic cohort"
    }
    rows$step[last] <- clean
  }
  rows
}

.attrition_grid_roundbox <- function(x0, y0, x1, y1, fill, family, text,
                                     fontsize = 10, fontface = "bold",
                                     align = c("centre", "left"), reflow = FALSE) {
  align <- match.arg(align)
  grid::grid.roundrect(
    x = grid::unit((x0 + x1) / 2, "npc"),
    y = grid::unit((y0 + y1) / 2, "npc"),
    width = grid::unit(abs(x1 - x0), "npc"),
    height = grid::unit(abs(y1 - y0), "npc"),
    r = grid::unit(0.012, "npc"),
    gp = grid::gpar(fill = fill, col = "#222222", lwd = 1.2)
  )
  attrition_draw_box_text(
    text, x0, y0, x1, y1,
    fontsize = fontsize, family = family, fontface = fontface,
    align = align, reflow = reflow
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
  # after_index_missing_HHR / after_index_extreme_HHR
  if (grepl("^after_index_missing", sid)) {
    ix <- sub("^after_index_missing_?", "", sid)
    ix <- gsub("_", " ", ix, fixed = TRUE)
    if (nzchar(ix)) return(sprintf("Missing %s", ix))
    return("Missing exposure index")
  }
  if (grepl("^after_index_extreme", sid) || grepl("extreme", lab, ignore.case = TRUE)) {
    return("Extreme exposure or outcome values")
  }
  # 从标题兜底（"After data cleaning" → data cleaning 相关）
  if (grepl("clean", lab, ignore.case = TRUE)) return("Incomplete covariates after data cleaning")
  if (grepl("(?i)exclud(?:e|ing)\\s+missing\\s+([A-Za-z0-9_]+)", lab, perl = TRUE)) {
    m <- regmatches(
      lab,
      regexpr("(?i)exclud(?:e|ing)\\s+missing\\s+([A-Za-z0-9_]+)", lab, perl = TRUE)
    )
    ix <- sub("(?i)^exclud(?:e|ing)\\s+missing\\s+", "", m)
    return(sprintf("Missing %s", gsub("_", " ", ix, fixed = TRUE)))
  }
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

#' 画粉/绿结局分叉（主列中点 cx 下方）。返回 list(y_bottom=分叉框底缘)。
.attrition_draw_outcome_fork_boxes <- function(cx, y_from, left_label, left_n,
                                              right_label, right_n, ff,
                                              y_floor = 0.03, oh = 0.11,
                                              gapf = 0.06) {
  ow <- min(0.28, cx - gapf / 2 - 0.02)
  left_x0 <- cx - gapf / 2 - ow
  right_x0 <- cx + gapf / 2
  y_out <- max(y_floor, y_from - 0.06 - oh)
  t_y <- y_out + oh + 0.022
  grid::grid.lines(
    x = grid::unit(c(cx, cx), "npc"),
    y = grid::unit(c(y_from, t_y), "npc"),
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
    left_label,
    format(as.integer(left_n), big.mark = ",")
  )
  right_txt <- sprintf(
    "%s\n(n = %s)",
    right_label,
    format(as.integer(right_n), big.mark = ",")
  )
  .attrition_grid_roundbox(
    left_x0, y_out, left_x0 + ow, y_out + oh,
    "#fff5f5", ff, left_txt, fontsize = 10
  )
  .attrition_grid_roundbox(
    right_x0, y_out, right_x0 + ow, y_out + oh,
    "#f3fff5", ff, right_txt, fontsize = 10
  )
  list(y_bottom = y_out, right_cx = right_x0 + ow / 2, oh = oh)
}

#' CONSORT 纳排图（对齐 TST Figure 1）：主列圆角纳入框、右侧 Exclude、
#' 底部分叉为发病病例/对照或预后 Expired/Alive。
#'
#' @param mid_fork 可选中间分叉，如基线 Hypertension / No Hypertension。
#'   `list(after=1L, left_label, left_n, right_label, right_n)`；
#'   `after` 为主列第几框之后；该步不再画右侧 Exclude，续行从右臂（无病）往下。
attrition_draw_pdf <- function(rows, title, pdf_path, font_family = "Times New Roman",
                               footnote = character(0), box_fill = "#FFFFFF",
                               fork = NULL, mid_fork = NULL) {
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
  has_mid <- is.list(mid_fork) &&
    is.finite(suppressWarnings(as.integer(mid_fork$after %||% NA_integer_))[1L]) &&
    is.finite(mid_fork$left_n %||% NA_real_) && is.finite(mid_fork$right_n %||% NA_real_)
  mid_after <- if (has_mid) as.integer(mid_fork$after)[1L] else NA_integer_
  if (has_mid && (mid_after < 1L || mid_after >= n_box)) has_mid <- FALSE
  w <- 7.6
  # 画布高度按内容估算，避免少步数时底部大片空白（勿再强制 4.6/8.2 寸底）
  need_h <- 0.50 +
    1.12 * n_box +
    0.90 * max(n_box - 1L, 0L) +
    if (has_fork) 1.55 else 0.18 +
    if (has_mid) 1.50 else 0 +
    if (length(footnote)) 0.55 else 0.08
  h <- max(2.4, need_h)
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
  # 按步数自上而下收紧：有无分叉都按 pack 落底，避免少框时把 span 拉满整页
  n_gap <- n_box - 1L + if (has_mid) 1L else 0L
  mid_slot <- if (has_mid) 0.20 else 0
  pack_npc <- n_box * 0.105 + max(n_gap, 0L) * 0.078 +
    if (has_fork) 0.22 else 0.04 + mid_slot
  y_fork_top <- max(
    if (length(footnote)) y_foot + 0.02 else 0.04,
    min(if (has_fork) 0.18 else 0.12, y_top - pack_npc - 0.02)
  )
  span <- max(0.22, y_top - y_fork_top - 0.02 - mid_slot)
  # 主框略收矮、间隙加大：Exclude 框须完整放进间隙内（旧版 eh=0.12 > gap=0.048 会压住主框）
  box_h <- min(0.11, span / (n_box + max(n_gap, 1L) * 0.85))
  gap <- min(0.085, max(0.055, box_h * 0.85))
  box_h <- min(box_h, (span - n_gap * gap - mid_slot) / n_box)
  if (!is.finite(box_h) || box_h < 0.05) box_h <- 0.07
  # 若全程无右侧 Exclude（相邻步 n 不降且无权重步），主列居中，避免左偏留白
  .need_exclude_col <- FALSE
  if (n_box >= 2L) {
    for (.i in seq_len(n_box - 1L)) {
      .dn <- as.integer(rows$n[.i]) - as.integer(rows$n[.i + 1L])
      .el <- if ("exclude_label" %in% names(rows)) {
        as.character(rows$exclude_label[.i + 1L])[1L]
      } else {
        NA_character_
      }
      .sid <- if ("step_id" %in% names(rows)) {
        as.character(rows$step_id[.i + 1L])[1L]
      } else {
        NA_character_
      }
      .wt <- identical(.sid, "after_survey_weight") ||
        grepl("survey weight", .el %||% "", ignore.case = TRUE) ||
        grepl(
          "Eligible survey-weighted",
          as.character(rows$step[.i + 1L])[1L],
          ignore.case = TRUE
        )
      if ((is.finite(.dn) && .dn > 0L) || isTRUE(.wt)) {
        .need_exclude_col <- TRUE
        break
      }
    }
  }
  if (isTRUE(.need_exclude_col)) {
    cx <- 0.30
    mw <- 0.44
    ex0 <- 0.565
    ex1 <- 0.985
  } else {
    cx <- 0.50
    mw <- 0.50
    ex0 <- 0.78
    ex1 <- 0.98
  }
  x0 <- cx - mw / 2
  x1 <- cx + mw / 2
  # Exclude 框加宽：文字尽量横排一行（对齐 12_AKI/AF），勿挤成竖排
  fill_main <- if (identical(box_fill, "#F7F7F7")) "#FFFFFF" else box_fill
  if (!nzchar(as.character(fill_main %||% "")[1L])) fill_main <- "#FFFFFF"

  ys0 <- numeric(n_box)
  ys1 <- numeric(n_box)
  y_cursor <- y_top
  for (i in seq_len(n_box)) {
    y1i <- y_cursor
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
      step_lab,
      format(as.integer(rows$n[i]), big.mark = ",")
    )
    .attrition_grid_roundbox(x0, y0i, x1, y1i, fill_i, ff, lab, fontsize = 10.5)

    if (has_mid && identical(i, mid_after)) {
      # 基线后：高血压 / 无高血压分叉；续行从右臂往下
      mf <- .attrition_draw_outcome_fork_boxes(
        cx, y0i,
        mid_fork$left_label, mid_fork$left_n,
        mid_fork$right_label, mid_fork$right_n,
        ff, y_floor = y_fork_top + 0.02
      )
      if (i < n_box) {
        # 右臂 → 下一主框；Exclude 用「无病臂 n − 下一步 n」（勿用基线总 n）
        y_gap_top <- mf$y_bottom - 0.01
        y_next_top <- y_gap_top - gap
        ymid <- (y_gap_top + y_next_top) / 2
        .attrition_grid_arrow(mf$right_cx, mf$y_bottom - 0.002, cx, y_next_top + 0.006, ff)
        drop_n <- as.integer(mid_fork$right_n) - as.integer(rows$n[i + 1L])
        el <- if ("exclude_label" %in% names(rows)) {
          as.character(rows$exclude_label[i + 1L])[1L]
        } else {
          NA_character_
        }
        sid <- if ("step_id" %in% names(rows)) {
          as.character(rows$step_id[i + 1L])[1L]
        } else {
          NA_character_
        }
        show_exclude <- is.finite(drop_n) && drop_n > 0L
        if (isTRUE(show_exclude)) {
          if (is.na(el) || !nzchar(el)) el <- .attrition_exclude_reason(sid, rows$step[i + 1L])
          if (is.na(el) || !nzchar(el)) el <- "Excluded"
          el <- sub("^[Ee]xclude[d]?[: ]*", "", el)
          if (!nzchar(el)) el <- "Excluded"
          ex_lab <- sprintf(
            "Exclude: %s\n(n = %s)",
            el,
            format(as.integer(drop_n), big.mark = ",")
          )
          eh <- min(gap * 0.92, 0.075)
          .attrition_grid_roundbox(
            ex0, ymid - eh / 2, ex1, ymid + eh / 2,
            "#f7f7f7", ff, ex_lab, fontsize = 8, fontface = "plain",
            align = "left", reflow = TRUE
          )
          .attrition_grid_arrow(cx, ymid, ex0 - 0.006, ymid, ff, lty = 2)
        }
        y_cursor <- y_next_top
      }
      next
    }

    if (i < n_box) {
      ymid <- y0i - gap / 2
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
        # 原因能一行就一行，放不下再换行；框内左对齐
        ex_lab <- sprintf(
          "Exclude: %s\n(n = %s)",
          el,
          format(max(0L, as.integer(drop_n)), big.mark = ",")
        )
        eh <- min(gap * 0.92, 0.075)
        .attrition_grid_roundbox(
          ex0, ymid - eh / 2, ex1, ymid + eh / 2,
          "#f7f7f7", ff, ex_lab, fontsize = 8, fontface = "plain",
          align = "left", reflow = TRUE
        )
        # 横向虚线箭头（对齐参考图）：从主列分叉水平指向 Exclude 框
        .attrition_grid_arrow(cx, ymid, ex0 - 0.006, ymid, ff, lty = 2)
      }
      y_cursor <- y0i - gap
    }
  }

  if (has_fork) {
    last_y0 <- ys0[n_box]
    .attrition_draw_outcome_fork_boxes(
      cx, last_y0,
      fork$left_label, fork$left_n,
      fork$right_label, fork$right_n,
      ff, y_floor = y_foot + 0.02
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

#' 预后 Figure 1 的单库面板。
#' 左列主流程居中、保留调用方换行；右侧排除框左对齐，能一行则一行，框高贴文字。
#' 纳入框下分出两个结局框。panel 字段：letter, top, mid, inc, side1, side2, death, alive。
attrition_draw_outcome_panel <- function(panel, family = "Times") {
  panel <- as.list(panel)
  ff <- as.character(family %||% "Times")[1L]
  box <- function(x0, y0, x1, y1, lab, fs = 7.2, align = "centre", reflow = FALSE) {
    grid::grid.roundrect(
      x = grid::unit((x0 + x1) / 2, "npc"), y = grid::unit((y0 + y1) / 2, "npc"),
      width = grid::unit(x1 - x0, "npc"), height = grid::unit(y1 - y0, "npc"),
      r = grid::unit(0.02, "npc"),
      gp = grid::gpar(fill = "white", col = "black", lwd = 0.8)
    )
    attrition_draw_box_text(
      lab, x0, y0, x1, y1, fontsize = fs, family = ff, fontface = "plain",
      pad_npc = 0.015, align = align, reflow = reflow
    )
  }
  varrow <- function(x, y1, y0) {
    grid::grid.lines(
      x = grid::unit(c(x, x), "npc"), y = grid::unit(c(y1, y0), "npc"),
      arrow = grid::arrow(length = grid::unit(0.09, "inches"), type = "closed"),
      gp = grid::gpar(fill = "black", col = "black", lwd = 0.7)
    )
  }
  harrow <- function(x0, x1, y) {
    grid::grid.lines(
      x = grid::unit(c(x0, x1), "npc"), y = grid::unit(c(y, y), "npc"),
      arrow = grid::arrow(length = grid::unit(0.09, "inches"), type = "closed"),
      gp = grid::gpar(fill = "black", col = "black", lwd = 0.7)
    )
  }
  ## 与 pv2 单栏一致：主列/排除列整体水平居中，避免贴左
  ml <- 0.14
  mr <- 0.54
  cx <- (ml + mr) / 2
  side_x0 <- 0.60
  side_x1 <- 0.94
  fork_gap <- 0.04
  fork_w <- (mr - ml - fork_gap) / 2
  if (nzchar(as.character(panel$letter %||% "")[1L])) {
    grid::grid.text(
      as.character(panel$letter)[1L], x = ml - 0.06, y = 0.985, just = c("left", "top"),
      gp = grid::gpar(fontsize = 11, fontface = "bold", fontfamily = ff)
    )
  }
  box(ml, 0.82, mr, 0.955, panel$top, fs = 7.4)
  box(ml, 0.52, mr, 0.67, panel$mid, fs = 7.2)
  box(ml, 0.22, mr, 0.35, panel$inc, fs = 7.4)
  box(ml, 0.02, ml + fork_w, 0.13, panel$death, fs = 6.8)
  box(mr - fork_w, 0.02, mr, 0.13, panel$alive, fs = 6.8)
  side_fs <- 6.5
  side_h <- function(lab) {
    attrition_label_height_npc(
      lab, side_x1 - side_x0, fontsize = side_fs, family = ff, pad_npc = 0.012
    )
  }
  h1 <- side_h(panel$side1)
  h2 <- side_h(panel$side2)
  box(side_x0, 0.81 - h1 / 2, side_x1, 0.81 + h1 / 2, panel$side1,
      fs = side_fs, align = "left", reflow = TRUE)
  box(side_x0, 0.51 - h2 / 2, side_x1, 0.51 + h2 / 2, panel$side2,
      fs = side_fs, align = "left", reflow = TRUE)
  varrow(cx, 0.82, 0.67)
  harrow(cx, side_x0, 0.81)
  varrow(cx, 0.52, 0.35)
  harrow(cx, side_x0, 0.51)
  fl <- ml + fork_w / 2
  fr <- mr - fork_w / 2
  grid::grid.lines(
    x = grid::unit(c(cx, cx), "npc"), y = grid::unit(c(0.22, 0.165), "npc"),
    gp = grid::gpar(col = "black", lwd = 0.7)
  )
  grid::grid.lines(
    x = grid::unit(c(fl, fr), "npc"), y = grid::unit(c(0.165, 0.165), "npc"),
    gp = grid::gpar(col = "black", lwd = 0.7)
  )
  varrow(fl, 0.165, 0.13)
  varrow(fr, 0.165, 0.13)
  invisible(panel)
}

.attrition_first_n <- function(txt) {
  m <- regexpr("(?i)n\\s*=\\s*[0-9][0-9,]*", as.character(txt %||% "")[1L], perl = TRUE)
  if (is.na(m) || m < 0) return(NA_integer_)
  as.integer(gsub("[^0-9]", "", regmatches(as.character(txt)[1L], m)))
}

.attrition_step_label <- function(txt) {
  txt <- gsub("\\s+", " ", as.character(txt %||% "")[1L])
  txt <- sub("(?i)\\s*\\(n\\s*=\\s*[0-9,]+\\)\\s*$", "", txt, perl = TRUE)
  trimws(txt)
}

#' 与预后纳排图同一套人数。逐步 n 递减，排除人数由相邻步相减得到。
attrition_outcome_ledger <- function(panels) {
  rows <- list()
  for (p in panels) {
    p <- as.list(p)
    db <- trimws(sub("^[[:space:]]*[A-Za-z][[:space:]]+", "", as.character(p$letter %||% "")[1L]))
    if (!nzchar(db)) db <- "Cohort"
    death_n <- .attrition_first_n(p$death)
    alive_n <- .attrition_first_n(p$alive)
    push <- function(step, n) {
      rows[[length(rows) + 1L]] <<- data.frame(
        database = db, step = step, n = as.integer(n),
        fork_left_label = .attrition_step_label(p$death),
        fork_left_n = death_n,
        fork_right_label = .attrition_step_label(p$alive),
        fork_right_n = alive_n,
        ledger_source = "outcome_figure",
        stringsAsFactors = FALSE
      )
    }
    push(.attrition_step_label(p$top), .attrition_first_n(p$top))
    mid_n <- .attrition_first_n(p$mid)
    push(.attrition_step_label(p$mid), mid_n)
    left <- mid_n
    blocks <- .attrition_logical_lines(p$side2)
    for (b in blocks) {
      ex <- .attrition_first_n(b)
      if (!is.finite(ex) || !is.finite(left)) next
      left <- left - ex
      push(.attrition_step_label(b), left)
    }
    inc_n <- .attrition_first_n(p$inc)
    if (is.finite(inc_n) && (!is.finite(left) || inc_n != left)) {
      push(.attrition_step_label(p$inc), inc_n)
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

attrition_write_outcome_ledger <- function(panels, csv_path) {
  dir.create(dirname(csv_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(attrition_outcome_ledger(panels), csv_path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(csv_path)
}

#' 多库并排的预后纳排图。每个 panel 用 attrition_draw_outcome_panel。
#' csv_path 给定时，底账与图面人数同一来源，不再另写一套旧筛选。
attrition_draw_outcome_figure <- function(pdf_path, panels, width = 15.6, height = 6.35,
                                          family = "Times", csv_path = NULL) {
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  ff <- as.character(family %||% "Times")[1L]
  grDevices::cairo_pdf(pdf_path, width = width, height = height, family = ff)
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  n <- length(panels)
  if (!n) return(invisible(pdf_path))
  for (i in seq_len(n)) {
    grid::pushViewport(grid::viewport(
      x = (i - 0.5) / n, y = 0.5, width = 1 / n, height = 1
    ))
    attrition_draw_outcome_panel(panels[[i]], family = ff)
    grid::popViewport()
  }
  if (nzchar(as.character(csv_path %||% "")[1L])) {
    attrition_write_outcome_ledger(panels, csv_path)
  }
  invisible(pdf_path)
}
