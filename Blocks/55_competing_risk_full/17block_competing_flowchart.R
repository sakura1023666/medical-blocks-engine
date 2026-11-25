###############################################################################
#  competing_flowchart — Lai 2025 风格 Figure 1
#  主列纳入 → 右侧分项 Exclude → 分析集 → 底部分叉：
#    Cross-sectional analysis (Q1–Q4) | Longitudinal analysis (trajectory)
#  禁止：假池层、extreme 裁剪文案、Exclude n > 起点 n、把结局当排除框。
###############################################################################

.competing_fc_fmt_n <- function(x) {
  x <- suppressWarnings(as.integer(x)[1L])
  if (!is.finite(x)) return("—")
  format(max(0L, x), big.mark = ",", trim = TRUE)
}

.competing_fc_wrap <- function(txt, width = 42L) {
  txt <- as.character(txt %||% "")[1L]
  if (!nzchar(txt)) return("")
  paste(strwrap(txt, width = width), collapse = "\n")
}

#' Lai 2025 风格流程图（对齐文献 Fig1 排版：白底、左列主轴、右侧逐条 exclude、底部分叉紧凑叶框）
#' @param spec list with baseline_label/n, exclude_items (data.frame label,n),
#'   included_label/n, cross_title, cross_groups (named int), long_title,
#'   long_groups (named int), title
.competing_flowchart_draw <- function(spec, outfile, title = NULL) {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  title <- as.character(title %||% spec$title %||% "Figure 1. Flowchart of patient selection")[1L]

  excl <- spec$exclude_items
  if (is.null(excl) || !nrow(excl)) {
    excl <- data.frame(label = character(0), n = integer(0), stringsAsFactors = FALSE)
  }
  excl$label <- as.character(excl$label)
  excl$n <- as.integer(excl$n)
  excl <- excl[is.finite(excl$n) & excl$n >= 0L, , drop = FALSE]

  cross <- spec$cross_groups %||% integer(0)
  longg <- spec$long_groups %||% integer(0)
  cross <- cross[is.finite(as.integer(cross))]
  longg <- longg[is.finite(as.integer(longg))]

  font_family <- "sans"
  if (exists("resolve_plot_font_family", mode = "function")) {
    font_family <- tryCatch(resolve_plot_font_family(), error = function(e) "sans")
  }

  # 文献比例：偏横版；Exclude 行数少时也不挤
  fig_w <- 11.0
  fig_h <- 8.6
  if (exists("pipeline_pdf_device", mode = "function")) {
    pipeline_pdf_device(outfile, width = fig_w, height = fig_h)
  } else {
    grDevices::pdf(outfile, width = fig_w, height = fig_h)
  }
  on.exit(grDevices::dev.off(), add = TRUE)

  op <- par(mar = c(0.35, 0.35, 1.35, 0.35), family = font_family)
  on.exit(par(op), add = TRUE)
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i")
  title(main = title, cex.main = 1.05, font.main = 2, line = 0.25, family = font_family)

  lwd_box <- 1.1
  lwd_line <- 1.0
  arr_len <- 0.055

  .box <- function(x0, y0, x1, y1, fill = "white") {
    rect(x0, y0, x1, y1, border = "black", col = fill, lwd = lwd_box)
  }
  .center_txt <- function(x, y, lab, cex = 0.72, font = 1) {
    text(x, y, lab, cex = cex, font = font, family = font_family, adj = c(0.5, 0.5))
  }
  .arrow_v <- function(x, y0, y1) {
    arrows(x, y0, x, y1, length = arr_len, lwd = lwd_line, angle = 25)
  }
  .arrow_h <- function(x0, y, x1) {
    arrows(x0, y, x1, y, length = arr_len, lwd = lwd_line, angle = 25)
  }

  # ---- 坐标：主列略偏左；Exclude 加宽少折行（能两行绝不四行）----
  xc <- 0.32
  main_w <- 0.30
  y_top <- 0.905
  h_top <- 0.088
  y_inc <- 0.545
  h_inc <- 0.060

  # Exclude 文案：文献句式；宽框 + 大 wrap，每条尽量 ≤2 行
  excl_paras <- character(0)
  if (nrow(excl)) {
    for (i in seq_len(nrow(excl))) {
      reason <- trimws(as.character(excl$label[i])[1L])
      if (!grepl("^(?i)having\\s+", reason, perl = TRUE)) {
        reason <- paste("having", reason)
      }
      excl_paras <- c(
        excl_paras,
        sprintf(
          "%s patients were excluded for %s",
          .competing_fc_fmt_n(excl$n[i]),
          reason
        )
      )
    }
  } else {
    excl_paras <- "0 patients were excluded"
  }
  xe0 <- 0.535
  xe1 <- 0.992
  cex_ex <- 0.58
  # 尽量每条 1 行；估宽偏保守，宁可靠右也不无谓折行
  excl_wrap_w <- max(72L, as.integer((xe1 - xe0) * fig_w * 9.0 / cex_ex))
  excl_lines <- character(0)
  for (p in excl_paras) {
    wrapped <- strwrap(p, width = excl_wrap_w)
    if (length(wrapped) > 1L) {
      wrapped <- strwrap(p, width = excl_wrap_w + 20L)
    }
    if (length(wrapped) > 2L) {
      wrapped <- strwrap(p, width = excl_wrap_w + 36L)
    }
    excl_lines <- c(excl_lines, wrapped)
  }
  n_ex_lines <- length(excl_lines)
  line_h <- 0.028
  pad_ex <- 0.014
  h_ex <- pad_ex * 2 + line_h * n_ex_lines + 0.008 * max(0L, nrow(excl) - 1L)
  y_span_mid <- (y_top - h_top / 2 + y_inc + h_inc / 2) / 2
  y_ex_top <- y_span_mid + h_ex / 2
  y_ex_bot <- y_span_mid - h_ex / 2
  if (y_ex_top > y_top - 0.01) {
    y_ex_top <- y_top - 0.01
    y_ex_bot <- y_ex_top - h_ex
  }
  if (y_ex_bot < y_inc + h_inc / 2 + 0.02) {
    y_ex_bot <- y_inc + h_inc / 2 + 0.02
    y_ex_top <- y_ex_bot + h_ex
  }

  # 1) 起点：加宽 wrap，优先 2 行
  top_lab <- sprintf(
    "%s (n=%s)",
    as.character(spec$baseline_label %||% "Baseline cohort")[1L],
    .competing_fc_fmt_n(spec$baseline_n)
  )
  top_wrap <- max(42L, as.integer(main_w * 2 * fig_w * 6.5 / 0.70))
  .box(xc - main_w, y_top - h_top / 2, xc + main_w, y_top + h_top / 2)
  .center_txt(xc, y_top, .competing_fc_wrap(top_lab, top_wrap), cex = 0.70)

  y_branch <- y_span_mid
  .arrow_v(xc, y_top - h_top / 2, y_branch + 0.002)
  segments(xc, y_branch, xc, y_inc + h_inc / 2, lwd = lwd_line)
  .arrow_h(xc, y_branch, xe0)

  # 2) Exclude：框内水平+垂直居中
  .box(xe0, y_ex_bot, xe1, y_ex_top, fill = "white")
  x_ex_mid <- (xe0 + xe1) / 2
  block_h <- line_h * max(1L, n_ex_lines)
  y_first <- (y_ex_top + y_ex_bot) / 2 + block_h / 2 - line_h / 2
  for (i in seq_along(excl_lines)) {
    text(
      x_ex_mid, y_first - (i - 1L) * line_h, excl_lines[[i]],
      adj = c(0.5, 0.5), cex = cex_ex, font = 1, family = font_family
    )
  }

  # 3) 纳入：尽量单行
  inc_n <- .competing_fc_fmt_n(spec$included_n)
  inc_lab <- paste(inc_n, "patients were included in this study")
  inc_w <- main_w * 0.95
  .box(xc - inc_w, y_inc - h_inc / 2, xc + inc_w, y_inc + h_inc / 2)
  .center_txt(xc, y_inc, inc_lab, cex = 0.72)

  # 4) 底部分叉
  y_split <- y_inc - h_inc / 2 - 0.035
  y_arm <- 0.355
  h_arm <- 0.055
  xl <- 0.24
  xr <- 0.76
  arm_w <- 0.175

  .arrow_v(xc, y_inc - h_inc / 2, y_split)
  segments(xl, y_split, xr, y_split, lwd = lwd_line)
  .arrow_v(xl, y_split, y_arm + h_arm / 2)
  .arrow_v(xr, y_split, y_arm + h_arm / 2)

  .box(xl - arm_w, y_arm - h_arm / 2, xl + arm_w, y_arm + h_arm / 2)
  .center_txt(
    xl, y_arm,
    as.character(spec$cross_title %||% "Cross-sectional analysis")[1L],
    cex = 0.70, font = 2
  )
  .box(xr - arm_w, y_arm - h_arm / 2, xr + arm_w, y_arm + h_arm / 2)
  .center_txt(
    xr, y_arm,
    as.character(spec$long_title %||% "Longitudinal analysis")[1L],
    cex = 0.70, font = 2
  )

  # 叶框：文献式紧凑等高（Q1 (n=117)），禁止又高又空
  .draw_leaf_row <- function(x_center, groups) {
    if (!length(groups)) return(invisible(NULL))
    labs <- names(groups)
    if (is.null(labs) || !any(nzchar(labs))) labs <- as.character(seq_along(groups))
    k <- length(groups)
    gap <- 0.014
    total_w <- if (k >= 4L) 0.44 else 0.38
    leaf_w <- (total_w - gap * (k - 1L)) / k
    leaf_h <- 0.052
    y1 <- 0.220
    y0 <- y1 - leaf_h
    y_beam <- (y_arm - h_arm / 2 + y1) / 2
    segments(x_center, y_arm - h_arm / 2, x_center, y_beam, lwd = lwd_line)
    xs <- (x_center - total_w / 2) + leaf_w / 2 + (seq_len(k) - 1L) * (leaf_w + gap)
    if (k > 1L) segments(xs[1L], y_beam, xs[k], y_beam, lwd = lwd_line)
    for (i in seq_len(k)) {
      xi <- xs[i]
      segments(xi, y_beam, xi, y1, lwd = lwd_line)
      .box(xi - leaf_w / 2, y0, xi + leaf_w / 2, y1)
      # 文献式单行：Q1 (n=117)
      .center_txt(
        xi, (y0 + y1) / 2,
        sprintf("%s (n=%s)", labs[i], .competing_fc_fmt_n(groups[[i]])),
        cex = 0.60
      )
    }
  }

  .draw_leaf_row(xl, cross)
  .draw_leaf_row(xr, longg)

  invisible(NULL)
}

.competing_fc_count_index_wide <- function(rdata_path, index_var, id_col = "ID", min_days = 2L) {
  out <- list(n_serial = NA_integer_, ids = character(0))
  if (is.null(rdata_path) || !file.exists(rdata_path)) return(out)
  env <- new.env(parent = emptyenv())
  ok <- tryCatch({ load(rdata_path, envir = env); TRUE }, error = function(e) FALSE)
  if (!isTRUE(ok)) return(out)
  wide <- if (exists("index_df", envir = env, inherits = FALSE)) {
    get("index_df", envir = env)
  } else {
    dfs <- ls(env)[vapply(ls(env), function(o) is.data.frame(get(o, envir = env)), logical(1))]
    if (!length(dfs)) return(out)
    get(dfs[[1L]], envir = env)
  }
  if (!is.data.frame(wide) || !nrow(wide)) return(out)
  day_cols <- grep(paste0("^", index_var, "_\\d+$"), names(wide), value = TRUE)
  if (!length(day_cols)) return(out)
  mat <- suppressWarnings(as.matrix(wide[, day_cols, drop = FALSE]))
  storage.mode(mat) <- "numeric"
  nn <- rowSums(is.finite(mat))
  keep <- nn >= as.integer(min_days)[1L]
  idv <- if (id_col %in% names(wide)) as.character(wide[[id_col]]) else {
    if ("ID" %in% names(wide)) as.character(wide$ID) else as.character(wide[[1L]])
  }
  out$n_serial <- as.integer(sum(keep))
  out$ids <- unique(idv[keep])
  out
}

.competing_fc_group_counts <- function(data, col) {
  if (is.null(data) || !is.data.frame(data) || !col %in% names(data)) return(integer(0))
  x <- as.character(data[[col]])
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(integer(0))
  tab <- table(x, useNA = "no")
  # Q1..Q4 优先按编号排序；轨迹按 Decreasing/Stable/Increasing 或字母
  nms <- names(tab)
  if (all(grepl("^Q[0-9]+$", nms))) {
    nms <- nms[order(as.integer(sub("^Q", "", nms)))]
  } else {
    pref <- c("Decreasing", "Stable", "Increasing", "Low", "Middle", "High", "T1", "T2", "T3", "T4")
    ord <- order(match(nms, pref, nomatch = 99L), nms)
    nms <- nms[ord]
  }
  stats::setNames(as.integer(tab[nms]), nms)
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
  fc_cfg <- cfg$competing_flowchart %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_flowchart: 无数据", call. = FALSE)

  index_var <- as.character(bl$index_var %||% bl$tyg_var %||% "TyG")[1L]
  event_col <- bl$event_type_col %||% "competing_status_28d"
  id_col <- cfg$data$id_column %||% "ID"
  if (!id_col %in% names(data)) {
    alt <- intersect(c("ID", "subject_id", "stay_id"), names(data))
    if (length(alt)) id_col <- alt[[1L]]
  }

  # ---- 起点：只用 rawdata（D01 等可核实体）；禁止用更大 dabiao 当排除分母 ----
  n_raw <- NA_integer_
  raw_path <- cfg$data$rawdata_path %||% NULL
  raw_df <- NULL
  if (!is.null(raw_path) && file.exists(raw_path)) {
    env <- new.env(parent = emptyenv())
    ok <- tryCatch({ load(raw_path, envir = env); TRUE }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      obj <- cfg$data$rawdata_obj %||% NULL
      raw_df <- if (!is.null(obj) && exists(obj, envir = env, inherits = FALSE)) {
        get(obj, envir = env)
      } else {
        dfs <- ls(env)[vapply(ls(env), function(o) is.data.frame(get(o, envir = env)), logical(1))]
        if (length(dfs)) get(dfs[[1L]], envir = env) else NULL
      }
      if (is.data.frame(raw_df)) n_raw <- nrow(raw_df)
    }
  }
  if (!is.finite(n_raw)) n_raw <- nrow(data)

  # 分析集 = 基线指标非缺失（与 Table1 / 四分位一致）
  n_analytic <- if (index_var %in% names(data)) {
    as.integer(sum(!is.na(data[[index_var]])))
  } else {
    nrow(data)
  }
  n_excl_total <- max(0L, as.integer(n_raw) - as.integer(n_analytic))

  # 逐日宽表：≥min_non_na_days 可算序列
  min_days <- as.integer((cfg$trajectory_calc_28d_index %||% list())$min_non_na_days %||% 2L)[1L]
  data_dir <- bl$index_data_dir %||% NULL
  rdata_path <- if (!is.null(data_dir)) file.path(data_dir, paste0("12_", index_var, ".RData")) else NULL
  serial <- .competing_fc_count_index_wide(rdata_path, index_var, id_col = id_col, min_days = min_days)
  n_serial <- serial$n_serial
  n_no_serial <- if (is.finite(n_serial)) max(0L, as.integer(n_raw) - as.integer(n_serial)) else NA_integer_
  n_no_baseline <- if (is.finite(n_serial)) max(0L, as.integer(n_serial) - as.integer(n_analytic)) else NA_integer_

  # 成分缺失分项（在起点表上计，供 Exclude 诚实列出；可与序列缺失并存）
  comp_counts <- integer(0)
  if (!is.null(raw_df) && exists("attrition_index_component_missing_counts", mode = "function")) {
    comp_counts <- tryCatch(
      attrition_index_component_missing_counts(raw_df, index_var),
      error = function(e) integer(0)
    )
  }

  exclude_items <- data.frame(label = character(0), n = integer(0), stringsAsFactors = FALSE)
  .push_ex <- function(label, n) {
    n <- suppressWarnings(as.integer(n)[1L])
    if (!is.finite(n) || n < 0L) return()
    exclude_items <<- rbind(
      exclude_items,
      data.frame(label = as.character(label)[1L], n = n, stringsAsFactors = FALSE)
    )
  }

  # 优先：可加总的两步（序列不足 + 无事件前基线）——与 n_excl_total 对齐
  # 文案宜短，图面逐条「原因 (n = …)」
  if (is.finite(n_no_serial) && is.finite(n_no_baseline) &&
      (n_no_serial + n_no_baseline) == n_excl_total) {
    .push_ex(
      sprintf("having fewer than %d ICU days with computable %s", min_days, index_var),
      n_no_serial
    )
    if (n_no_baseline > 0L) {
      .push_ex(
        sprintf("having no usable pre-event baseline %s", index_var),
        n_no_baseline
      )
    }
  } else if (n_excl_total > 0L) {
    .push_ex(sprintf("having missing key variables for baseline %s", index_var), n_excl_total)
    if (length(comp_counts)) {
      labs <- if (exists("pipeline_display_label", mode = "function")) {
        pipeline_display_label(names(comp_counts))
      } else {
        gsub("_", " ", names(comp_counts), fixed = TRUE)
      }
      for (i in seq_along(comp_counts)) {
        .push_ex(sprintf("having missing %s", labs[[i]]), comp_counts[[i]])
      }
    }
  }

  # 禁止残留 extreme 文案
  exclude_items$label <- gsub("(?i)\\s*/\\s*extreme\\b", "", exclude_items$label, perl = TRUE)
  exclude_items$label <- gsub("(?i)\\bextreme\\b\\s*", "", exclude_items$label, perl = TRUE)

  q_col <- paste0(index_var, "_quartile")
  t_col <- paste0(index_var, "_trajectory")
  analytic <- if (index_var %in% names(data)) data[!is.na(data[[index_var]]), , drop = FALSE] else data
  cross_groups <- .competing_fc_group_counts(analytic, q_col)
  long_groups <- .competing_fc_group_counts(analytic, t_col)

  db_lab <- as.character(cfg$project$database %||% "MIMIC")[1L]
  baseline_label <- as.character(
    fc_cfg$baseline_label %||%
      sprintf(
        "Adult patients with AKI in %s (ICU baseline extract for CRRT competing-risk analysis)",
        db_lab
      )
  )[1L]
  included_label <- as.character(
    fc_cfg$included_label %||%
      sprintf("%s patients were included in this study", .competing_fc_fmt_n(n_analytic))
  )[1L]
  # included_label 若已含人数则去掉重复 n 行——抽屉统一追加 (n=)
  if (grepl("(?i)\\bn\\s*=", included_label, perl = TRUE) || grepl("were included", included_label, fixed = TRUE)) {
    included_label <- as.character(
      fc_cfg$included_label_short %||% "Patients included in this study"
    )[1L]
  }

  spec <- list(
    title = sprintf("Figure 1-%s. Flowchart of patient selection", db_lab),
    baseline_label = baseline_label,
    baseline_n = as.integer(n_raw),
    exclude_items = exclude_items,
    included_label = included_label,
    included_n = as.integer(n_analytic),
    cross_title = as.character(fc_cfg$cross_title %||% "Cross-sectional analysis")[1L],
    long_title = as.character(fc_cfg$long_title %||% "Longitudinal analysis")[1L],
    cross_groups = cross_groups,
    long_groups = long_groups
  )

  # ---- 计数表（逐步 + 分叉人数）----
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
  .add("include", baseline_label, n_raw)
  if (nrow(exclude_items)) {
    for (i in seq_len(nrow(exclude_items))) {
      .add("exclude", exclude_items$label[i], exclude_items$n[i])
    }
  }
  .add("include", included_label, n_analytic)
  if (length(cross_groups)) {
    for (nm in names(cross_groups)) .add("cross_quartile", nm, cross_groups[[nm]])
  }
  if (length(long_groups)) {
    for (nm in names(long_groups)) .add("long_trajectory", nm, long_groups[[nm]])
  }

  status_tab <- if (event_col %in% names(analytic)) {
    table(analytic[[event_col]], useNA = "ifany")
  } else {
    table(character(0))
  }
  primary_lbl <- as.character(bl$primary_event_label %||% "primary event")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "primary event"
  discharge_censor <- isTRUE(bl$discharge_as_censor %||% FALSE)
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
  for (i in seq_along(outcome_labels)) {
    key <- c("1", "2", "3", "0")[i]
    .add("outcome", outcome_labels[[i]], as.integer(status_tab[key] %||% 0L))
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  fig_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
  # unit worker 常把 output 指到 by_unit/... ；优先写当前 ctx$output_dir
  if (!is.null(ctx$output_dir_tables)) out_dir <- ctx$output_dir_tables
  if (!is.null(ctx$output_dir_figures)) fig_dir <- ctx$output_dir_figures
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  utils::write.csv(
    steps,
    file.path(out_dir, paste0("Table_Flowchart_Counts_", index_var, ".csv")),
    row.names = FALSE
  )

  raw_pdf <- file.path(fig_dir, "Fig1_Flowchart_raw.pdf")
  .competing_flowchart_draw(spec, raw_pdf, title = spec$title)

  # 同步发表名（pub_export 也会再拷一次）
  pub_pdf <- file.path(fig_dir, sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
  if (!identical(normalizePath(raw_pdf, mustWork = FALSE), normalizePath(pub_pdf, mustWork = FALSE))) {
    file.copy(raw_pdf, pub_pdf, overwrite = TRUE)
  }

  ctx$results$competing_flowchart <- list(
    table = steps,
    spec = spec,
    n_raw = n_raw,
    n_analytic = n_analytic,
    n_serial = n_serial
  )
  cli::cli_alert_success(
    "流程图完成: {index_var}（start={n_raw}, analytic={n_analytic}, Q={length(cross_groups)}, traj={length(long_groups)}）"
  )
  ctx
}

register_block(
  "competing_flowchart",
  block_competing_flowchart,
  "Lai 风格研究流程图（Exclude 分项 + Cross-sectional/Longitudinal 分叉）"
)
