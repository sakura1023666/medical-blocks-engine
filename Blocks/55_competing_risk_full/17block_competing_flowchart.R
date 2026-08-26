###############################################################################
#  competing_flowchart — CONSORT 风格入选流程图（对应文献 Figure 1）
#  逐步显示纳入/剔除人数，而非事件计数柱状图。
###############################################################################

.competing_flowchart_draw <- function(steps, outfile, title = "Flowchart of patient selection") {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  pdf(outfile, width = 8.5, height = max(6, 1.1 * nrow(steps) + 2))
  on.exit(dev.off(), add = TRUE)
  op <- par(mar = c(1, 1, 2.5, 1))
  on.exit(par(op), add = TRUE)
  plot.new()
  title(main = title, cex.main = 1.05)

  n_box <- sum(steps$kind == "include")
  y_pos <- seq(0.88, 0.12, length.out = max(1L, n_box))
  box_i <- 0L
  prev_yc <- NA_real_

  for (i in seq_len(nrow(steps))) {
    kind <- steps$kind[i]
    lab <- steps$label[i]
    n <- steps$n[i]
    if (kind == "include") {
      box_i <- box_i + 1L
      yc <- y_pos[box_i]
      xc <- 0.38
      rect(xc - 0.28, yc - 0.055, xc + 0.28, yc + 0.055, border = "black", lwd = 1.4, col = "white")
      text(xc, yc, sprintf("%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.78)
      if (is.finite(prev_yc)) {
        arrows(xc, prev_yc - 0.055, xc, yc + 0.055, length = 0.08, lwd = 1.2)
      }
      prev_yc <- yc
    } else if (kind == "exclude" && is.finite(prev_yc)) {
      # 侧向剔除框
      xe <- 0.78
      ye <- prev_yc - 0.02
      rect(xe - 0.18, ye - 0.045, xe + 0.18, ye + 0.045, border = "grey30", lwd = 1, col = grDevices::adjustcolor("grey90", 0.8))
      text(xe, ye, sprintf("Excluded\n%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.65)
      arrows(0.38 + 0.28, prev_yc, xe - 0.18, ye, length = 0.07, lwd = 1)
    }
  }
  invisible(NULL)
}

block_competing_flowchart <- function(ctx, ...) {
  mode <- (ctx$config$attrition %||% list())$specialty_figure_mode %||% "skip_if_generic"
  pipe_blocks <- ctx$pipeline_blocks %||% character(0)
  if (identical(mode, "skip_if_generic") && "attrition_flowchart" %in% pipe_blocks) {
    cli::cli_alert_info("pipeline 含 attrition_flowchart，跳过专用 Figure 1")
    return(ctx)
  }

  bl <- ctx$config$competing_risk %||% list()
  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_flowchart: 无数据", call. = FALSE)
  index_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  event_col <- bl$event_type_col %||% "event_type"
  id_col <- cfg$data$id_column %||% "ID"
  if (!id_col %in% names(data)) {
    alt <- intersect(c("ID", "subject_id"), names(data))
    if (length(alt)) id_col <- alt[1L]
  }

  # ---- 逐步计数（尽量从源文件重算）----
  n_raw <- NA_integer_
  n_after_cohort <- NA_integer_
  n_excluded_cohort <- NA_integer_
  raw_path <- cfg$data$rawdata_path %||% NULL
  if (!is.null(raw_path) && file.exists(raw_path)) {
    env <- new.env()
    ok <- tryCatch({ load(raw_path, envir = env); TRUE }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      obj <- cfg$data$rawdata_obj %||% NULL
      df0 <- if (!is.null(obj) && exists(obj, envir = env, inherits = FALSE)) get(obj, envir = env) else {
        dfs <- ls(env)[vapply(ls(env), function(o) is.data.frame(get(o, envir = env)), logical(1))]
        if (length(dfs)) get(dfs[1L], envir = env) else NULL
      }
      if (is.data.frame(df0)) n_raw <- nrow(df0)
    }
  }
  if (!is.finite(n_raw)) n_raw <- nrow(data)

  cohort_path <- (cfg$data_clean %||% list())$cohort_id_path %||% NULL
  if (!is.null(cohort_path) && file.exists(cohort_path) && is.finite(n_raw)) {
    cdf <- tryCatch(utils::read.csv(cohort_path, stringsAsFactors = FALSE), error = function(e) NULL)
    cid <- (cfg$data_clean %||% list())$cohort_id_column %||% "subject_id"
    if (!is.null(cdf) && cid %in% names(cdf)) {
      keep_ids <- unique(as.character(cdf[[cid]]))
      # 近似：dabiao 人数作为纳入后上限；剔除 = 原始 - 当前分析集前的队列规模
      n_after_cohort <- length(keep_ids)
      # 更准：用当前 data 前的 shared cleaned 规模；若无则用 dabiao ∩ raw 近似
      n_excluded_cohort <- max(0L, as.integer(n_raw) - as.integer(n_after_cohort))
    }
  }

  n_final <- nrow(data)
  n_index_ok <- if (index_var %in% names(data)) sum(!is.na(data[[index_var]])) else n_final
  n_analytic <- n_index_ok
  # dabiao 后 → 有指标分析集：缺失/极端值剔除
  n_cohort_ref <- if (is.finite(n_after_cohort)) as.integer(n_after_cohort) else NA_integer_
  n_excl_index <- if (is.finite(n_cohort_ref)) max(0L, n_cohort_ref - n_analytic) else max(0L, n_final - n_index_ok)

  status_tab <- if (event_col %in% names(data)) {
    dd <- if (index_var %in% names(data)) data[!is.na(data[[index_var]]), , drop = FALSE] else data
    table(dd[[event_col]], useNA = "ifany")
  } else table(character(0))

  steps <- data.frame(
    step = integer(0), kind = character(0), label = character(0), n = integer(0),
    stringsAsFactors = FALSE
  )
  .add <- function(kind, label, n) {
    steps <<- rbind(steps, data.frame(
      step = nrow(steps) + 1L, kind = kind, label = label, n = as.integer(n),
      stringsAsFactors = FALSE
    ))
  }

  # 文案可配置；禁止把内部文件名 dabiao / 全库误写成「卒中总人数」
  fc_cfg <- (cfg$competing_flowchart %||% list())
  db_lab0 <- as.character(cfg$project$database %||% "MIMIC")[1L]
  lab_baseline <- as.character(
    fc_cfg$baseline_label %||%
      sprintf("%s ICU baseline admissions (all diagnoses)", db_lab0)
  )[1L]
  lab_excl_cohort <- as.character(
    fc_cfg$exclude_cohort_label %||%
      "not in pre-specified ischemic stroke cohort"
  )[1L]
  lab_matched <- as.character(
    fc_cfg$cohort_label %||% "Matched ischemic stroke cohort"
  )[1L]

  .add("include", lab_baseline, n_raw)
  if (is.finite(n_excluded_cohort) && n_excluded_cohort > 0L) {
    .add("exclude", lab_excl_cohort, n_excluded_cohort)
    .add("include", lab_matched, n_cohort_ref %||% (n_raw - n_excluded_cohort))
  }
  if (is.finite(n_excl_index) && n_excl_index > 0L) {
    .add("exclude", paste0("missing / extreme ", index_var), n_excl_index)
  }
  .add("include", paste0("Final analytic cohort with ", index_var), n_analytic)

  steps_draw <- steps
  outcome_row <- NULL

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  primary_lbl <- as.character((cfg$competing_risk %||% list())$primary_event_label %||% "diabetes")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "diabetes"
  discharge_censor <- isTRUE((cfg$competing_risk %||% list())$discharge_as_censor %||% FALSE)
  outcome_labels <- if (discharge_censor) {
    c(
      paste0("status=1 ", primary_lbl),
      "status=2 death (competing)",
      "status=3 discharge (unused; discharge censored as 0)",
      "status=0 censored (incl. discharge)"
    )
  } else {
    c(
      paste0("status=1 ", primary_lbl),
      "status=2 death",
      "status=3 discharge",
      "status=0 censored"
    )
  }
  counts <- rbind(
    steps_draw[, c("step", "kind", "label", "n")],
    data.frame(
      step = nrow(steps_draw) + seq_len(4L),
      kind = "outcome",
      label = outcome_labels,
      n = c(
        as.integer(status_tab["1"] %||% 0L),
        as.integer(status_tab["2"] %||% 0L),
        as.integer(status_tab["3"] %||% 0L),
        as.integer(status_tab["0"] %||% 0L)
      ),
      stringsAsFactors = FALSE
    )
  )
  utils::write.csv(counts, file.path(out_dir, paste0("Table_Flowchart_Counts_", index_var, ".csv")),
                   row.names = FALSE)

  db_lab <- as.character(cfg$project$database %||% "MIMIC")[1L]
  fig_title <- sprintf("Figure 1-%s. Flowchart of patient selection", db_lab)
  .competing_flowchart_draw(steps_draw, file.path(fig_dir, "Fig1_Flowchart_raw.pdf"), title = fig_title)

  ctx$results$competing_flowchart <- list(table = counts, steps_draw = steps_draw)
  cli::cli_alert_success("流程图完成: {index_var}（analytic n={n_analytic}）")
  ctx
}

register_block("competing_flowchart", block_competing_flowchart, "研究流程图与逐步剔除计数（对应 Figure 1）")
