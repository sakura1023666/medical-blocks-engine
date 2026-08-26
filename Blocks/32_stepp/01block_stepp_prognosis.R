###############################################################################
#  stepp_prognosis — 滑动窗口 STEPP：全人群 + 按组，合成 2×2 主图（A|B / C|D）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_study  = config$project$study_type == "prognosis"
#  require_config = config$survival（time_var / event_var / event_value 必填，块内无兜底）
#                   config$stepp_prognosis（eval_time_months / y_axis_label 等必填）
#
#  stepp_prognosis = list(
#    index_var        = NULL,
#    eval_time_months = 60L,              # 必填，单位与 survival$time_var 一致
#    y_axis_label     = "5-Year Freedom From Distant Recurrence (%)",
#    x_axis_label     = "Composite Risk (Subpopulation Median)",
#    hist_x_label     = "Composite Risk",
#    hist_binwidth    = 0.2,
#    show_median_vline = TRUE,
#    overall = list(
#      window_size           = 300L,
#      step_size             = 25L,
#      panel_title           = "A",       # 上排左：全样本趋势
#      panel_hist_title      = "B",       # 上排右：全样本直方图+窗口线
#      line_color            = "#1F77B4",
#      hist_fill             = "#4E79A7",
#      show_overall_hline    = TRUE,
#      panel_b_line_y_from   = 1.5,
#      panel_b_line_y_to     = 1.1,
#      panel_b_y_max_factor  = 1.6
#    ),
#    by_group = list(
#      stratum_var         = "Postop_Management_Group",
#      stratum_levels      = NULL,
#      stratum_colors      = list(...),
#      window_size         = 80L,
#      step_size           = 10L,
#      panel_title         = "C",         # 下排左：分组趋势
#      panel_hist_title    = "D",         # 下排右：分组直方图+窗口线
#      hist_fill           = "#AECCDA",
#      legend_title        = "Treatment Group",
#      panel_b_line_y_from = 1.8,
#      panel_b_line_y_to   = 1.1
#    ),
#    figure_width  = 12,
#    figure_height = 10,
#    figure_caption = NULL,
#    pause_enable  = TRUE
#  ),
#
#  布局: 上排 A（全样本趋势）| B（全样本分布）；下排 C（分组趋势）| D（分布+窗口线）
#
#  产出:
#    - [main_figure] Figure n.*  STEPP combined 2x2 → pub_figure_file + save_figure
#
#  写: ctx$results$stepp_prognosis_overall_results, stepp_prognosis_by_group_results,
#      stepp_prognosis_overall_rate, stepp_prognosis_index_median,
#      stepp_prognosis_by_group_fail_log, stepp_prognosis_figure
#
#  pause: config$stepp_prognosis$pause_enable
###############################################################################

.stp01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.stp01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "stepp_prognosis",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: stepp_prognosis halted. See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.stp01_coerce_event01 <- function(x, event_value) {
  if (is.logical(x)) {
    return(as.integer(x))
  }
  if (is.numeric(x) || is.integer(x)) {
    return(suppressWarnings(as.integer(x == event_value)))
  }
  if (is.factor(x)) {
    lab <- tolower(trimws(as.character(x)))
    ev_chr <- tolower(trimws(as.character(event_value)))
    v <- rep(0L, length(lab))
    v[lab == ev_chr] <- 1L
    v[grepl("^(yes|y|1|recurrence|是|复发)", lab, perl = TRUE)] <- 1L
    return(v)
  }
  xc <- tolower(trimws(as.character(x)))
  ev_chr <- tolower(trimws(as.character(event_value)))
  v <- rep(0L, length(xc))
  v[xc == ev_chr] <- 1L
  v[xc %in% c("1", "yes", "y", "recurrence", "true", "t", "是", "复发")] <- 1L
  v[grepl("^yes", xc, perl = TRUE)] <- 1L
  v
}

.stp01_km_rfs_rate <- function(time_vec, event_vec, eval_time_months) {
  fit <- survival::survfit(survival::Surv(time_vec, event_vec) ~ 1)
  s_fit <- summary(fit, times = eval_time_months, extend = TRUE)
  as.numeric(s_fit$surv) * 100
}

# KM 时点生存率 + 95% CI（百分数）；n_arm 不足或无法估计时返回 NA
.stp01_km_surv_ci <- function(time_vec, event_vec, eval_time_months) {
  ok <- is.finite(time_vec) & !is.na(event_vec)
  time_vec <- time_vec[ok]
  event_vec <- event_vec[ok]
  n <- length(time_vec)
  if (n < 2L || sum(event_vec == 1L, na.rm = TRUE) < 1L) {
    return(list(rate = NA_real_, lower = NA_real_, upper = NA_real_, n = n))
  }
  fit <- survival::survfit(survival::Surv(time_vec, event_vec) ~ 1)
  s_fit <- summary(fit, times = eval_time_months, extend = TRUE)
  list(
    rate = as.numeric(s_fit$surv)[1L] * 100,
    lower = as.numeric(s_fit$lower)[1L] * 100,
    upper = as.numeric(s_fit$upper)[1L] * 100,
    n = n
  )
}

# Jin Fig.5 同构：在全队列复合风险上开共享滑动窗，窗内分别估计两臂绝对生存率
.stp01_calc_windows_treatment <- function(
    df,
    index_var,
    treatment_var,
    time_col,
    status_col,
    window_size,
    step_size,
    eval_time_months,
    groups
) {
  df <- df[order(df[[index_var]]), , drop = FALSE]
  n <- nrow(df)
  if (n < window_size) {
    return(data.frame())
  }
  rows <- list()
  idx <- 0L
  for (start in seq(1L, n - window_size + 1L, by = step_size)) {
    end <- start + window_size - 1L
    w <- df[start:end, , drop = FALSE]
    med <- stats::median(w[[index_var]], na.rm = TRUE)
    min_r <- min(w[[index_var]], na.rm = TRUE)
    max_r <- max(w[[index_var]], na.rm = TRUE)
    n_win <- nrow(w)
    for (g in groups) {
      wg <- w[as.character(w[[treatment_var]]) == as.character(g), , drop = FALSE]
      est <- .stp01_km_surv_ci(wg[[time_col]], wg[[status_col]], eval_time_months)
      idx <- idx + 1L
      rows[[idx]] <- data.frame(
        group = as.character(g),
        median_risk = med,
        min_risk = min_r,
        max_risk = max_r,
        n_window = n_win,
        n_arm = est$n,
        rfs_rate = est$rate,
        rfs_lower = est$lower,
        rfs_upper = est$upper,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    return(data.frame())
  }
  dplyr::bind_rows(rows)
}

.stp01_plot_jin_treatment <- function(
    stepp_tx,
    y_lab,
    x_lab,
    legend_title,
    group_labels,
    group_colors,
    font_family
) {
  d <- as.data.frame(stepp_tx, stringsAsFactors = FALSE)
  d$group <- factor(as.character(d$group), levels = names(group_labels))
  d$group_lab <- factor(
    group_labels[as.character(d$group)],
    levels = unname(group_labels)
  )
  # 每个共享窗取一行作 x 轴刻度（median + n）
  ticks <- d[!duplicated(d$median_risk), c("median_risk", "n_window"), drop = FALSE]
  ticks <- ticks[order(ticks$median_risk), , drop = FALSE]
  tick_labs <- sprintf("%.2f\nn=%d", ticks$median_risk, ticks$n_window)

  y_vals <- c(d$rfs_rate, d$rfs_lower, d$rfs_upper)
  y_vals <- y_vals[is.finite(y_vals)]
  if (!length(y_vals)) {
    y_lim <- c(0, 100)
  } else {
    pad <- max(2, diff(range(y_vals)) * 0.08)
    y_lim <- c(max(0, min(y_vals) - pad), min(100, max(y_vals) + pad))
  }

  ggplot2::ggplot(
    d,
    ggplot2::aes(
      x = .data$median_risk,
      y = .data$rfs_rate,
      color = .data$group_lab,
      group = .data$group_lab
    )
  ) +
    ggplot2::geom_vline(
      xintercept = ticks$median_risk,
      linetype = "dotted",
      color = "grey55",
      linewidth = 0.4
    ) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(shape = 15, size = 2.8) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$rfs_lower, ymax = .data$rfs_upper),
      width = diff(range(ticks$median_risk)) * 0.02,
      linewidth = 0.45
    ) +
    ggplot2::scale_color_manual(values = setNames(unname(group_colors), unname(group_labels))) +
    ggplot2::scale_x_continuous(
      breaks = ticks$median_risk,
      labels = tick_labs
    ) +
    ggplot2::scale_y_continuous(limits = y_lim) +
    ggplot2::labs(
      x = x_lab,
      y = y_lab,
      color = legend_title
    ) +
    ggplot2::theme_classic(base_size = 12, base_family = font_family) +
    ggplot2::theme(
      text = ggplot2::element_text(family = font_family),
      legend.position = "right",
      axis.text.x = ggplot2::element_text(size = 9, lineheight = 0.95),
      plot.margin = ggplot2::margin(8, 12, 8, 8)
    )
}

.stp01_calc_windows <- function(
    df,
    index_var,
    time_col,
    status_col,
    window_size,
    step_size,
    eval_time_months
) {
  df <- df[order(df[[index_var]]), , drop = FALSE]
  n <- nrow(df)
  if (n < window_size) {
    return(data.frame())
  }
  results <- list()
  idx <- 0L
  for (start in seq(1L, n - window_size + 1L, by = step_size)) {
    end <- start + window_size - 1L
    w <- df[start:end, , drop = FALSE]
    idx <- idx + 1L
    rfs_rate <- .stp01_km_rfs_rate(w[[time_col]], w[[status_col]], eval_time_months)
    results[[idx]] <- data.frame(
      median_risk = stats::median(w[[index_var]], na.rm = TRUE),
      min_risk = min(w[[index_var]], na.rm = TRUE),
      max_risk = max(w[[index_var]], na.rm = TRUE),
      rfs_rate = rfs_rate[1L],
      stringsAsFactors = FALSE
    )
  }
  if (!length(results)) {
    return(data.frame())
  }
  dplyr::bind_rows(results)
}

.stp01_calc_windows_by_group <- function(
    df,
    index_var,
    stratum_var,
    time_col,
    status_col,
    window_size,
    step_size,
    eval_time_months,
    groups
) {
  all_results <- list()
  fail_rows <- list()
  idx <- 0L

  for (g in groups) {
    sub_data <- df[as.character(df[[stratum_var]]) == as.character(g), , drop = FALSE]
    sub_data <- sub_data[order(sub_data[[index_var]]), , drop = FALSE]
    n <- nrow(sub_data)

    if (n < window_size) {
      fail_rows[[length(fail_rows) + 1L]] <- data.frame(
        group = g,
        reason = paste0("n=", n, " < window_size=", window_size),
        stringsAsFactors = FALSE
      )
      cli::cli_alert_warning("[skip] {g} — n={n} < window_size={window_size}")
      next
    }

    for (start in seq(1L, n - window_size + 1L, by = step_size)) {
      end <- start + window_size - 1L
      w <- sub_data[start:end, , drop = FALSE]
      idx <- idx + 1L
      rfs_rate <- .stp01_km_rfs_rate(w[[time_col]], w[[status_col]], eval_time_months)
      all_results[[idx]] <- data.frame(
        group = g,
        median_risk = stats::median(w[[index_var]], na.rm = TRUE),
        min_risk = min(w[[index_var]], na.rm = TRUE),
        max_risk = max(w[[index_var]], na.rm = TRUE),
        rfs_rate = rfs_rate[1L],
        stringsAsFactors = FALSE
      )
    }
  }

  list(
    results = if (length(all_results)) dplyr::bind_rows(all_results) else data.frame(),
    fail_log = if (length(fail_rows)) dplyr::bind_rows(fail_rows) else data.frame(
      group = character(0),
      reason = character(0)
    )
  )
}

.stp01_resolve_stratum_colors <- function(levels_ok, grp_cfg) {
  cfg_cols <- grp_cfg$stratum_colors
  if (is.null(cfg_cols)) cfg_cols <- list()
  if (!is.list(cfg_cols)) {
    stop("config$stepp_prognosis$by_group$stratum_colors 须为命名 list。", call. = FALSE)
  }
  default_palette <- if (exists("block_default_palette", mode = "function")) {
    block_default_palette(max(6L, length(levels_ok)))
  } else {
    c("#7F7F7F", "#1F77B4", "#D62728", "#2CA02C", "#9467BD", "#8C564B")
  }
  out <- character(length(levels_ok))
  names(out) <- levels_ok
  for (i in seq_along(levels_ok)) {
    lv <- levels_ok[[i]]
    if (!is.null(cfg_cols[[lv]]) && nzchar(as.character(cfg_cols[[lv]])[1L])) {
      out[[i]] <- as.character(cfg_cols[[lv]])[1L]
    } else {
      out[[i]] <- default_palette[((i - 1L) %% length(default_palette)) + 1L]
    }
  }
  out
}

block_stepp_prognosis <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    library(ggplot2)
    library(dplyr)
    library(patchwork)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$stepp_prognosis %||% list()
  ov_cfg <- bl_cfg$overall %||% list()
  grp_cfg <- bl_cfg$by_group %||% list()

  study_type <- cfg$project$study_type %||% "prognosis"
  if (!identical(study_type, "prognosis")) {
    cli::cli_alert_warning("stepp_prognosis: study_type 非 prognosis，跳过。")
    return(ctx)
  }

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp) || !is.data.frame(data_imp)) {
    if (.stp01_should_pause(bl_cfg, "pause_on_missing_data", TRUE)) {
      .stp01_pause(
        ctx,
        reason = "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）",
        suggestion = "请先 load 数据至 ctx$data$cleaned 或运行上游 data_clean / imputation"
      )
    }
    stop("No data found in ctx$data$imputed or ctx$data$cleaned.", call. = FALSE)
  }
  rt <- as.data.frame(data_imp, stringsAsFactors = FALSE)

  surv <- cfg$survival
  if (is.null(surv) ||
      is.null(surv$time_var) ||
      is.null(surv$event_var) ||
      is.null(surv$event_value)) {
    stop(
      "config$survival 必须同时定义 time_var、event_var、event_value（块内不使用默认值）。",
      call. = FALSE
    )
  }
  time_col <- surv$time_var
  status_col <- surv$event_var
  event_value <- surv$event_value

  if (is.null(bl_cfg$eval_time_months)) {
    stop(
      "config$stepp_prognosis$eval_time_months 必填（KM 评估时间点，单位与 time_var 一致）。",
      call. = FALSE
    )
  }
  eval_time_months <- suppressWarnings(as.numeric(bl_cfg$eval_time_months)[1L])
  if (!is.finite(eval_time_months) || eval_time_months < 0) {
    stop("config$stepp_prognosis$eval_time_months 须为有限非负数值。", call. = FALSE)
  }

  index_var <- bl_cfg$index_var %||% surv$index_var
  if (is.null(index_var) || !nzchar(as.character(index_var)[1L])) {
    stop("stepp_prognosis: index_var 未设置。", call. = FALSE)
  }

  stratum_var <- grp_cfg$stratum_var
  if (is.null(stratum_var) || !nzchar(as.character(stratum_var)[1L])) {
    stop("config$stepp_prognosis$by_group$stratum_var 必填。", call. = FALSE)
  }

  miss_cols <- setdiff(c(index_var, stratum_var, time_col, status_col), names(rt))
  if (length(miss_cols)) {
    stop("下列列不在分析数据中: ", paste(miss_cols, collapse = ", "), call. = FALSE)
  }

  ov_window <- ov_cfg$window_size %||% 300L
  ov_step <- ov_cfg$step_size %||% 25L
  grp_window <- grp_cfg$window_size %||% 80L
  grp_step <- grp_cfg$step_size %||% 10L
  ov_window <- as.integer(ov_window)
  ov_step <- as.integer(ov_step)
  grp_window <- as.integer(grp_window)
  grp_step <- as.integer(grp_step)
  if (ov_window < 2L || ov_step < 1L || grp_window < 2L || grp_step < 1L) {
    stop("stepp_prognosis: overall/by_group 的 window_size 须 >= 2，step_size 须 >= 1。", call. = FALSE)
  }

  rt[[time_col]] <- suppressWarnings(as.numeric(rt[[time_col]]))
  rt[[status_col]] <- .stp01_coerce_event01(rt[[status_col]], event_value)
  if (all(rt[[status_col]] == 0L, na.rm = TRUE)) {
    if (.stp01_should_pause(bl_cfg, "pause_on_all_censored", TRUE)) {
      .stp01_pause(
        ctx,
        reason = "结局经 event_value 转换后全为 0（无事件）",
        suggestion = "检查 config$survival$event_var 与 event_value",
        data_snapshot = rt[, c(status_col, time_col), drop = FALSE]
      )
    }
    stop("stepp_prognosis: no events after outcome conversion.", call. = FALSE)
  }

  rt[[stratum_var]] <- droplevels(as.factor(rt[[stratum_var]]))
  level_cfg <- grp_cfg$stratum_levels
  if (!is.null(level_cfg) && length(level_cfg)) {
    level_cfg <- as.character(level_cfg)
    rt[[stratum_var]] <- factor(rt[[stratum_var]], levels = level_cfg)
    rt[[stratum_var]] <- droplevels(rt[[stratum_var]])
  }
  groups <- levels(rt[[stratum_var]])
  if (length(groups) == 0L) {
    stop("stepp_prognosis: by_group$stratum_var 无有效水平。", call. = FALSE)
  }

  df_overall <- rt[, c(index_var, time_col, status_col), drop = FALSE]
  df_overall <- df_overall[stats::complete.cases(df_overall), , drop = FALSE]
  df_group <- rt[, c(stratum_var, index_var, time_col, status_col), drop = FALSE]
  df_group <- df_group[stats::complete.cases(df_group), , drop = FALSE]

  n_ov <- nrow(df_overall)
  if (n_ov < ov_window) {
    if (.stp01_should_pause(bl_cfg, "pause_on_insufficient_n", TRUE)) {
      .stp01_pause(
        ctx,
        reason = paste0("全样本有效 n=", n_ov, " < overall$window_size=", ov_window),
        suggestion = "减小 overall$window_size 或扩大样本",
        data_snapshot = utils::head(df_overall, 5L)
      )
    }
    stop("stepp_prognosis: overall n < window_size.", call. = FALSE)
  }

  cli::cli_alert_info(
    "stepp_prognosis: index={index_var}, stratum={stratum_var}, eval_time={eval_time_months}, overall window={ov_window}/{ov_step}, by_group window={grp_window}/{grp_step}"
  )

  plot_style <- tolower(trimws(as.character(bl_cfg$plot_style %||% "composite_2x2")[1L]))
  is_jin <- identical(plot_style, "jin_treatment") || identical(plot_style, "jin") ||
    identical(plot_style, "treatment")

  y_lab <- bl_cfg$y_axis_label
  if (is.null(y_lab) || !nzchar(as.character(y_lab)[1L])) {
    stop("config$stepp_prognosis$y_axis_label 必填（须与 eval_time_months 对应）。", call. = FALSE)
  }
  ff <- plot_font_from_config(cfg)

  if (is_jin) {
    # ── Jin Fig.5：共享滑动窗 × 两臂绝对生存率（含 95% CI）────────────────
    stepp_tx <- .stp01_calc_windows_treatment(
      df = df_group,
      index_var = index_var,
      treatment_var = stratum_var,
      time_col = time_col,
      status_col = status_col,
      window_size = ov_window,
      step_size = ov_step,
      eval_time_months = eval_time_months,
      groups = groups
    )
    if (nrow(stepp_tx) == 0L || !any(is.finite(stepp_tx$rfs_rate))) {
      stop("stepp_prognosis: jin_treatment 窗口结果为空或无法估计生存率。", call. = FALSE)
    }

    # 兼容旧字段：overall = 窗中位数汇总；by_group = 两臂长表
    stepp_overall <- unique(stepp_tx[, c("median_risk", "min_risk", "max_risk", "n_window"), drop = FALSE])
    stepp_overall <- stepp_overall[order(stepp_overall$median_risk), , drop = FALSE]
    stepp_group <- stepp_tx
    stepp_group$group <- factor(stepp_group$group, levels = groups)
    overall_rate <- .stp01_km_rfs_rate(
      df_overall[[time_col]], df_overall[[status_col]], eval_time_months
    )[1L]
    overall_median_risk <- stats::median(df_overall[[index_var]], na.rm = TRUE)
    strata_ok <- as.character(groups)
    ctx$results$stepp_prognosis_by_group_fail_log <- data.frame(
      group = character(0), reason = character(0)
    )

    # 图例标签：stratum_labels 与 stratum_levels 一一对应
    lab_cfg <- grp_cfg$stratum_labels
    if (is.null(lab_cfg) || length(lab_cfg) != length(groups)) {
      group_labels <- setNames(as.character(groups), as.character(groups))
    } else {
      group_labels <- setNames(as.character(lab_cfg), as.character(groups))
    }
    grp_cols_raw <- .stp01_resolve_stratum_colors(strata_ok, grp_cfg)
    # 默认 Jin 配色：对照蓝 / 暴露橙
    if (is.null(grp_cfg$stratum_colors) && length(strata_ok) >= 2L) {
      grp_cols_raw[1L] <- "#4C72B0"
      grp_cols_raw[2L] <- "#E17C39"
    }
    legend_title <- grp_cfg$legend_title %||% stratum_var
    x_lab <- bl_cfg$x_axis_label %||% "Subpopulations by median composite risk"
    fig_w <- bl_cfg$figure_width %||% 8
    fig_h <- bl_cfg$figure_height %||% 5.5
    fig_cap <- bl_cfg$figure_caption %||% paste0(
      "STEPP of ", as.character(y_lab)[1L], " by ", legend_title,
      " across ", index_var, " composite risk"
    )
    fig_fn <- pub_figure_file(ctx, "main_figure", fig_cap)

    ctx$results$stepp_prognosis_overall_results <- stepp_overall
    ctx$results$stepp_prognosis_by_group_results <- stepp_group
    ctx$results$stepp_prognosis_overall_rate <- overall_rate
    ctx$results$stepp_prognosis_index_median <- overall_median_risk
    ctx$results$stepp_prognosis_by_group_strata_ok <- strata_ok
    ctx$results$stepp_prognosis_eval_time_months <- eval_time_months
    ctx$results$stepp_prognosis_plot_style <- "jin_treatment"

    ctx <- save_figure(
      ctx,
      fig_fn,
      function() {
        print(.stp01_plot_jin_treatment(
          stepp_tx = stepp_tx,
          y_lab = as.character(y_lab)[1L],
          x_lab = as.character(x_lab)[1L],
          legend_title = as.character(legend_title)[1L],
          group_labels = group_labels,
          group_colors = grp_cols_raw,
          font_family = ff
        ))
        invisible(NULL)
      },
      width = fig_w,
      height = fig_h
    )
    ctx$results$stepp_prognosis_figure <- fig_fn
  } else {
  stepp_overall <- .stp01_calc_windows(
    df = df_overall,
    index_var = index_var,
    time_col = time_col,
    status_col = status_col,
    window_size = ov_window,
    step_size = ov_step,
    eval_time_months = eval_time_months
  )
  if (nrow(stepp_overall) == 0L) {
    if (.stp01_should_pause(bl_cfg, "pause_on_empty_windows", TRUE)) {
      .stp01_pause(
        ctx,
        reason = "全样本滑动窗口未产生任何有效结果行",
        suggestion = "调整 overall$window_size / step_size",
        data_snapshot = utils::head(df_overall, 5L)
      )
    }
    stop("stepp_prognosis: empty overall window results.", call. = FALSE)
  }

  calc_grp <- .stp01_calc_windows_by_group(
    df = df_group,
    index_var = index_var,
    stratum_var = stratum_var,
    time_col = time_col,
    status_col = status_col,
    window_size = grp_window,
    step_size = grp_step,
    eval_time_months = eval_time_months,
    groups = groups
  )
  stepp_group <- calc_grp$results
  fail_df <- calc_grp$fail_log
  ctx$results$stepp_prognosis_by_group_fail_log <- fail_df

  if (nrow(stepp_group) == 0L) {
    if (.stp01_should_pause(bl_cfg, "pause_on_no_strata_ok", TRUE)) {
      .stp01_pause(
        ctx,
        reason = "所有 stratum 均未产生 STEPP 窗口结果（见 stepp_prognosis_by_group_fail_log）",
        suggestion = "减小 by_group$window_size 或检查各组 n",
        data_snapshot = fail_df
      )
    }
    stop("stepp_prognosis: no by_group window results.", call. = FALSE)
  }

  overall_rate <- .stp01_km_rfs_rate(
    df_overall[[time_col]],
    df_overall[[status_col]],
    eval_time_months
  )[1L]
  overall_median_risk <- stats::median(df_overall[[index_var]], na.rm = TRUE)
  strata_ok <- unique(as.character(stepp_group$group))
  stepp_group$group <- factor(stepp_group$group, levels = groups)

  ctx$results$stepp_prognosis_overall_results <- stepp_overall
  ctx$results$stepp_prognosis_by_group_results <- stepp_group
  ctx$results$stepp_prognosis_overall_rate <- overall_rate
  ctx$results$stepp_prognosis_index_median <- overall_median_risk
  ctx$results$stepp_prognosis_by_group_strata_ok <- strata_ok
  ctx$results$stepp_prognosis_eval_time_months <- eval_time_months
  ctx$results$stepp_prognosis_plot_style <- "composite_2x2"

  hist_binwidth <- bl_cfg$hist_binwidth %||% 0.2
  x_lab <- bl_cfg$x_axis_label %||% paste0(index_var, " (Subpopulation Median)")
  hist_x_lab <- bl_cfg$hist_x_label %||% index_var
  show_median_vline <- !isFALSE(bl_cfg$show_median_vline)

  title_a <- ov_cfg$panel_title %||% "A"
  title_b <- ov_cfg$panel_hist_title %||% "B"
  title_c <- grp_cfg$panel_title %||% "C"
  title_d <- grp_cfg$panel_hist_title %||% "D"

  line_color <- ov_cfg$line_color %||% "#1F77B4"
  hist_fill_a <- ov_cfg$hist_fill %||% "#4E79A7"
  hist_fill_d <- grp_cfg$hist_fill %||% "#AECCDA"
  ov_line_from <- ov_cfg$panel_b_line_y_from %||% 1.5
  ov_line_to <- ov_cfg$panel_b_line_y_to %||% 1.1
  ov_y_max <- ov_cfg$panel_b_y_max_factor %||% 1.6
  grp_line_from <- grp_cfg$panel_b_line_y_from %||% 1.8
  grp_line_to <- grp_cfg$panel_b_line_y_to %||% 1.1
  show_overall_hline <- !isFALSE(ov_cfg$show_overall_hline)
  legend_title <- grp_cfg$legend_title %||% stratum_var
  grp_cols <- .stp01_resolve_stratum_colors(strata_ok, grp_cfg)

  fig_w <- bl_cfg$figure_width %||% 12
  fig_h <- bl_cfg$figure_height %||% 10
  fig_cap <- bl_cfg$figure_caption %||% paste0(
    "STEPP sliding-window analysis of ", index_var, " (overall and by ", stratum_var, ")"
  )
  fig_fn <- pub_figure_file(ctx, "main_figure", fig_cap)

  ctx <- save_figure(
    ctx,
    fig_fn,
    function() {
      max_hist_ov <- max(table(cut(df_overall[[index_var]], breaks = 30)), na.rm = TRUE)
      stepp_overall$custom_y <- seq(
        from = max_hist_ov * ov_line_from,
        to = max_hist_ov * ov_line_to,
        length.out = nrow(stepp_overall)
      )

      p_a <- ggplot2::ggplot(stepp_overall, ggplot2::aes(x = median_risk, y = rfs_rate)) +
        ggplot2::geom_line(color = line_color, linewidth = 1) +
        ggplot2::geom_point(color = line_color, size = 2) +
        ggplot2::scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
        ggplot2::labs(title = title_a, x = x_lab, y = y_lab) +
        ggplot2::theme_classic(base_size = 12, base_family = ff) +
        ggplot2::theme(text = ggplot2::element_text(family = ff))

      if (show_overall_hline) {
        p_a <- p_a + ggplot2::geom_hline(
          yintercept = overall_rate,
          linetype = "dashed",
          color = "gray50"
        )
      }
      if (show_median_vline) {
        p_a <- p_a + ggplot2::geom_vline(
          xintercept = overall_median_risk,
          linetype = "dashed",
          color = "gray50"
        )
      }

      p_b <- ggplot2::ggplot(df_overall, ggplot2::aes(x = .data[[index_var]])) +
        ggplot2::geom_histogram(
          binwidth = hist_binwidth,
          fill = hist_fill_a,
          color = "white",
          alpha = 0.8
        ) +
        ggplot2::geom_segment(
          data = stepp_overall,
          ggplot2::aes(x = min_risk, xend = max_risk, y = custom_y, yend = custom_y),
          color = "black",
          linewidth = 0.5,
          inherit.aes = FALSE
        ) +
        ggplot2::labs(title = title_b, x = hist_x_lab, y = "Patients (No.)") +
        ggplot2::theme_classic(base_size = 12, base_family = ff) +
        ggplot2::theme(text = ggplot2::element_text(family = ff)) +
        ggplot2::coord_cartesian(ylim = c(0, max_hist_ov * ov_y_max))

      if (show_median_vline) {
        p_b <- p_b + ggplot2::geom_vline(
          xintercept = overall_median_risk,
          linetype = "dashed",
          color = "black"
        )
      }

      p_c <- ggplot2::ggplot(
        stepp_group,
        ggplot2::aes(x = median_risk, y = rfs_rate, color = group)
      ) +
        ggplot2::geom_line(linewidth = 1.2) +
        ggplot2::geom_point(size = 2) +
        ggplot2::scale_color_manual(values = grp_cols, drop = FALSE) +
        ggplot2::scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
        ggplot2::labs(title = title_c, x = x_lab, y = y_lab, color = legend_title) +
        ggplot2::theme_classic(base_size = 12, base_family = ff) +
        ggplot2::theme(
          text = ggplot2::element_text(family = ff),
          legend.position = "bottom"
        )

      if (show_median_vline) {
        p_c <- p_c + ggplot2::geom_vline(
          xintercept = overall_median_risk,
          linetype = "dashed",
          color = "gray60"
        )
      }

      max_hist_grp <- max(table(cut(df_group[[index_var]], breaks = 30)), na.rm = TRUE)
      stepp_plot_d <- stepp_group %>% dplyr::arrange(median_risk)
      stepp_plot_d$step_y <- seq(
        from = max_hist_grp * grp_line_from,
        to = max_hist_grp * grp_line_to,
        length.out = nrow(stepp_plot_d)
      )

      p_d <- ggplot2::ggplot(df_group, ggplot2::aes(x = .data[[index_var]])) +
        ggplot2::geom_histogram(
          binwidth = hist_binwidth,
          fill = hist_fill_d,
          color = "white"
        ) +
        ggplot2::geom_segment(
          data = stepp_plot_d,
          ggplot2::aes(x = min_risk, xend = max_risk, y = step_y, yend = step_y),
          color = "black",
          linewidth = 0.3,
          inherit.aes = FALSE
        ) +
        ggplot2::labs(title = title_d, x = hist_x_lab, y = "Patients (No.)") +
        ggplot2::theme_classic(base_size = 12, base_family = ff) +
        ggplot2::theme(text = ggplot2::element_text(family = ff))

      if (show_median_vline) {
        p_d <- p_d + ggplot2::geom_vline(
          xintercept = overall_median_risk,
          linetype = "dashed",
          color = "black"
        )
      }

      # 显式 print 后返回 NULL，避免 render_queued_figures 对 ggplot 返回值再 print 成双页
      print((p_a | p_b) / (p_c | p_d) + patchwork::plot_layout(heights = c(1, 1.15)))
      invisible(NULL)
    },
    width = fig_w,
    height = fig_h
  )

  ctx$results$stepp_prognosis_figure <- fig_fn
  } # end else composite_2x2

  # Table S1: STEPP composite coefficients / window results（文献审计 Table_S1_STEPP_Composite）
  if (!isFALSE(bl_cfg$export_stepp_table %||% TRUE)) {
    ov_tbl <- as.data.frame(ctx$results$stepp_prognosis_overall_results, stringsAsFactors = FALSE)
    if (!"stratum" %in% names(ov_tbl)) ov_tbl$stratum <- "Overall"
    if (!"rfs_rate" %in% names(ov_tbl)) ov_tbl$rfs_rate <- NA_real_
    grp_tbl <- as.data.frame(ctx$results$stepp_prognosis_by_group_results, stringsAsFactors = FALSE)
    if (!"stratum" %in% names(grp_tbl) && "group" %in% names(grp_tbl)) {
      grp_tbl$stratum <- as.character(grp_tbl$group)
    }
    common <- intersect(names(ov_tbl), names(grp_tbl))
    if (!length(common)) {
      stepp_tbl <- rbind(
        cbind(ov_tbl, data.frame(stratum = ov_tbl$stratum %||% "Overall")),
        grp_tbl
      )
    } else {
      stepp_tbl <- rbind(ov_tbl[, common, drop = FALSE], grp_tbl[, common, drop = FALSE])
    }
    # jin 模式优先导出完整两臂表（含 CI）
    if (isTRUE(is_jin) && all(c("rfs_rate", "rfs_lower", "rfs_upper") %in% names(grp_tbl))) {
      stepp_tbl <- grp_tbl
    }
    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
    stepp_fn <- as.character(
      bl_cfg$stepp_table_filename %||% "Table_S1_STEPP_Composite.csv"
    )[1L]
    stepp_path <- file.path(tbl_dir, stepp_fn)
    tryCatch({
      utils::write.csv(stepp_tbl, stepp_path, row.names = FALSE)
      if (exists("mirror_pub_output_to_root", mode = "function")) {
        mirror_pub_output_to_root(ctx, stepp_path)
      }
      # 同步 SCI 表（文件名含 STEPP Composite，便于审计）
      if (exists("export_sci_table", mode = "function") && exists("pub_paths", mode = "function")) {
        cap_s1 <- as.character(
          bl_cfg$stepp_table_caption %||%
            paste0("STEPP Composite window coefficients for ", index_var)
        )[1L]
        pub_s1 <- pub_paths(ctx, tbl_dir, "supp_table", cap_s1, "xlsx")
        # 强制文件名可匹配 STEPP.*Composite
        if (!grepl("STEPP.*Composite|Composite.*STEPP", basename(pub_s1$filepath), ignore.case = TRUE)) {
          pub_s1$filepath <- file.path(tbl_dir, "Table_S1_STEPP_Composite.xlsx")
          pub_s1$title <- paste0("Table S1. ", cap_s1)
        }
        export_sci_table(stepp_tbl, pub_s1$filepath, title = pub_s1$title)
      }
      ctx$results$stepp_prognosis_table <- stepp_tbl
      ctx$results$stepp_prognosis_table_path <- stepp_path
      cli::cli_alert_success("stepp_prognosis: STEPP Composite 表 → {.file {basename(stepp_path)}}")
    }, error = function(e) {
      cli::cli_alert_warning("STEPP 系数表写出失败: {e$message}")
    })
  }

  n_win_msg <- if (is_jin) {
    length(unique(ctx$results$stepp_prognosis_by_group_results$median_risk))
  } else {
    nrow(ctx$results$stepp_prognosis_overall_results)
  }
  cli::cli_alert_success(
    "stepp_prognosis done (style={plot_style}, windows={n_win_msg}, eval_time={eval_time_months})"
  )

  ctx
}

register_block(
  "stepp_prognosis",
  block_stepp_prognosis,
  "STEPP：Jin 治疗双臂 或 2x2 合成主图"
)
