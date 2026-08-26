###############################################################################
#  rcs_prognosis_by_group — 按分组变量各拟合 crude Cox+RCS，输出重叠区间叠加主图
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_study  = config$project$study_type == "prognosis"（非 prognosis 时 warning 跳过）
#  require_config = config$survival（time_var / event_var / event_value 必填，块内无兜底）
#                   config$rcs_prognosis_by_group
#
#  统计说明：各 stratum 内单独拟合 Surv ~ rcs(index)，非 treatment×RCS 交互模型；
#            统一参考点为全样本 index 中位数（组内 predict 时可 clip 到组内 min–max）。
#
#  rcs_prognosis_by_group = list(
#    index_var          = NULL,           # NULL → survival$index_var
#    stratum_var        = "Postop_Management_Group",
#    nk_range_global    = 3:5,
#    min_n_stratum      = 10L,
#    min_events_stratum = 2L,
#    min_index_sd       = 1e-8,
#    n_grid             = 1000L,
#    overlay_ylim       = c(0, 14),
#    overlay_colors     = list(...),      # 水平名 → 颜色；缺省按 factor 水平顺序配色
#    figure_width       = 7,
#    figure_height      = 5,
#    figure_caption     = NULL,           # pub_figure_file caption（不含 Figure n. 前缀）
#    pause_enable       = TRUE,
#    pause_on_no_strata_ok     = TRUE,
#    pause_on_no_overlap_range = TRUE
#  ),
#
#  产出（仅此一项落盘）:
#    - [main_figure] Figure n.*  RCS overlap overlay → pub_figure_file + save_figure
#
#  写: ctx$results$rcs_prognosis_by_group_curve, rcs_prognosis_by_group_nk_global,
#      rcs_prognosis_by_group_ref, rcs_prognosis_by_group_overlap_range,
#      rcs_prognosis_by_group_strata_ok, rcs_prognosis_by_group_fail_log（内存，不落盘）
#
#  pause: config$rcs_prognosis_by_group$pause_enable
###############################################################################

.rcbg04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.rcbg04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "rcs_prognosis_by_group",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: rcs_prognosis_by_group halted. See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.rcbg04_coerce_event01 <- function(x, event_value) {
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

.rcbg04_pick_nk <- function(dat, index_var, time_col, status_col, nk_candidates) {
  aic_best <- Inf
  nk_best <- 3L
  for (i in nk_candidates) {
    f <- stats::as.formula(paste0(
      "Surv(", time_col, ", ", status_col, ") ~ rcspline.eval(",
      index_var, ", nk = ", i, ", inclx = TRUE)"
    ))
    fit <- tryCatch(survival::coxph(f, data = dat, x = TRUE), error = function(e) NULL)
    if (is.null(fit)) next
    tmp <- tryCatch(stats::extractAIC(fit)[2], error = function(e) Inf)
    if (is.finite(tmp) && tmp < aic_best) {
      aic_best <- tmp
      nk_best <- as.integer(i)
    }
  }
  nk_best
}

.rcbg04_resolve_overlay_colors <- function(levels_ok, bl_cfg) {
  cfg_cols <- bl_cfg$overlay_colors
  if (is.null(cfg_cols)) {
    cfg_cols <- list()
  }
  if (!is.list(cfg_cols)) {
    stop("config$rcs_prognosis_by_group$overlay_colors 须为命名 list（水平名 → 颜色）。", call. = FALSE)
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

block_rcs_prognosis_by_group <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    library(smoothHR)
    library(ggplot2)
    library(dplyr)
    library(purrr)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$rcs_prognosis_by_group %||% list()

  study_type <- cfg$project$study_type %||% "prognosis"
  if (!identical(study_type, "prognosis")) {
    cli::cli_alert_warning("rcs_prognosis_by_group: study_type 非 prognosis，跳过。")
    return(ctx)
  }

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp) || !is.data.frame(data_imp)) {
    if (.rcbg04_should_pause(bl_cfg, "pause_on_missing_data", TRUE)) {
      .rcbg04_pause(
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

  index_var <- bl_cfg$index_var %||% surv$index_var
  stratum_var <- bl_cfg$stratum_var
  if (is.null(index_var) || !nzchar(as.character(index_var)[1L])) {
    stop("rcs_prognosis_by_group: index_var 未设置（config$rcs_prognosis_by_group 或 survival$index_var）。", call. = FALSE)
  }
  if (is.null(stratum_var) || !nzchar(as.character(stratum_var)[1L])) {
    stop("config$rcs_prognosis_by_group$stratum_var 必填。", call. = FALSE)
  }

  miss_cols <- setdiff(c(index_var, stratum_var, time_col, status_col), names(rt))
  if (length(miss_cols)) {
    stop(
      "下列列不在分析数据中: ",
      paste(miss_cols, collapse = ", "),
      call. = FALSE
    )
  }

  min_n <- bl_cfg$min_n_stratum %||% 10L
  min_ev <- bl_cfg$min_events_stratum %||% 2L
  min_sd <- bl_cfg$min_index_sd %||% 1e-8
  n_grid <- bl_cfg$n_grid %||% 1000L
  nk_range <- bl_cfg$nk_range_global %||% 3:5
  nk_range <- as.integer(nk_range)
  if (!length(nk_range)) nk_range <- 3:5

  rt[[time_col]] <- suppressWarnings(as.numeric(rt[[time_col]]))
  rt[[status_col]] <- .rcbg04_coerce_event01(rt[[status_col]], event_value)
  if (all(rt[[status_col]] == 0L, na.rm = TRUE)) {
    if (.rcbg04_should_pause(bl_cfg, "pause_on_all_censored", TRUE)) {
      .rcbg04_pause(
        ctx,
        reason = "结局经 event_value 转换后全为 0（无事件）",
        suggestion = "检查 config$survival$event_var 与 event_value 是否与数据编码一致",
        data_snapshot = rt[, c(status_col, time_col), drop = FALSE]
      )
    }
    stop("rcs_prognosis_by_group: no events after outcome conversion.", call. = FALSE)
  }

  rt[[stratum_var]] <- droplevels(as.factor(rt[[stratum_var]]))
  groups <- levels(rt[[stratum_var]])
  if (length(groups) == 0L) {
    stop("rcs_prognosis_by_group: stratum_var 无有效水平。", call. = FALSE)
  }

  cli::cli_alert_info("rcs_prognosis_by_group: index={index_var}, stratum={stratum_var}, n={nrow(rt)}")
  diag_tbl <- rt %>%
    dplyr::group_by(.data[[stratum_var]]) %>%
    dplyr::summarise(
      n = dplyr::n(),
      events = sum(.data[[status_col]] == 1L, na.rm = TRUE),
      .groups = "drop"
    )
  cli::cli_alert_info("Stratum n/events:")
  print(as.data.frame(diag_tbl))

  nk_global <- .rcbg04_pick_nk(rt, index_var, time_col, status_col, nk_range)
  cli::cli_alert_info("Global crude RCS selected nk = {nk_global}")

  ref_global <- stats::median(rt[[index_var]], na.rm = TRUE)
  cli::cli_alert_info(
    "Unified reference {index_var} (full-sample median) = {formatC(ref_global, digits = 4, format = 'f')}"
  )

  plot_list <- list()
  fail_rows <- list()

  log_fail <- function(g, reason) {
    fail_rows[[length(fail_rows) + 1L]] <<- data.frame(
      group = g,
      reason = reason,
      stringsAsFactors = FALSE
    )
    cli::cli_alert_warning("[skip] {g} — {reason}")
  }

  for (g in groups) {
    rt_g <- rt[as.character(rt[[stratum_var]]) == as.character(g), , drop = FALSE]
    n_g <- nrow(rt_g)
    ev_g <- sum(rt_g[[status_col]] == 1L, na.rm = TRUE)

    if (n_g < min_n) {
      log_fail(g, paste0("n=", n_g, " < min_n_stratum=", min_n))
      next
    }
    if (ev_g < min_ev) {
      log_fail(g, paste0("events=", ev_g, " < min_events_stratum=", min_ev))
      next
    }

    cr_sd <- stats::sd(rt_g[[index_var]], na.rm = TRUE)
    if (!is.finite(cr_sd) || cr_sd < min_sd) {
      log_fail(g, paste0(index_var, " within-stratum sd≈0 (sd=", cr_sd, ")"))
      next
    }

    nk_try <- bl_cfg$nk_try_stratum
    if (is.null(nk_try) || !length(nk_try)) {
      nk_try <- unique(c(3L, nk_global, 4L, 5L))
    } else {
      nk_try <- as.integer(nk_try)
    }

    fit_g <- NULL
    nk_used <- NA_integer_
    last_cox_err <- "unknown"
    for (nk_i in nk_try) {
      f_g <- stats::as.formula(paste0(
        "Surv(", time_col, ", ", status_col, ") ~ rcspline.eval(",
        index_var, ", nk = ", nk_i, ", inclx = TRUE)"
      ))
      fit_try <- tryCatch(
        survival::coxph(f_g, data = rt_g, x = TRUE),
        error = function(e) {
          last_cox_err <<- conditionMessage(e)
          NULL
        }
      )
      if (!is.null(fit_try)) {
        fit_g <- fit_try
        nk_used <- nk_i
        break
      }
    }
    if (is.null(fit_g)) {
      log_fail(g, paste0("coxph+RCS failed: ", last_cox_err))
      next
    }

    fit_g$call$formula <- stats::formula(fit_g)

    hr1 <- tryCatch(
      smoothHR(data = rt_g, coxfit = fit_g),
      error = function(e) {
        log_fail(g, paste0("smoothHR: ", conditionMessage(e)))
        NULL
      }
    )
    if (is.null(hr1)) next

    rg <- range(rt_g[[index_var]], na.rm = TRUE)
    ref_use <- min(max(ref_global, rg[1]), rg[2])
    if (!isTRUE(all.equal(ref_use, ref_global))) {
      cli::cli_alert_info(
        "Stratum {g}: reference clipped from {formatC(ref_global, digits = 4, format = 'f')} to {formatC(ref_use, digits = 4, format = 'f')}"
      )
    }

    x_grid_g <- seq(rg[1], rg[2], length.out = n_grid)

    pred_df <- tryCatch(
      as.data.frame(predict(
        hr1,
        predictor = index_var,
        pred.value = ref_use,
        prob = 0.5,
        prediction.values = x_grid_g,
        conf.level = 0.95
      )),
      error = function(e) {
        log_fail(g, paste0("predict: ", conditionMessage(e)))
        NULL
      }
    )
    if (is.null(pred_df)) next

    xcol <- names(pred_df)[1L]
    pred_df <- pred_df %>%
      dplyr::mutate(
        x = .data[[xcol]],
        hr = exp(LnHR),
        lo = exp(`lower .95`),
        hi = exp(`upper .95`)
      )
    pred_df[[stratum_var]] <- g
    pred_df <- pred_df %>% dplyr::select(dplyr::all_of(c(stratum_var, "x", "hr", "lo", "hi")))

    plot_list[[length(plot_list) + 1L]] <- pred_df
    cli::cli_alert_success("Stratum {g}: curve OK (nk={nk_used}, n={n_g}, events={ev_g})")
  }

  fail_df <- if (length(fail_rows)) dplyr::bind_rows(fail_rows) else data.frame(group = character(0), reason = character(0))
  ctx$results$rcs_prognosis_by_group_fail_log <- fail_df

  if (length(plot_list) == 0L) {
    if (.rcbg04_should_pause(bl_cfg, "pause_on_no_strata_ok", TRUE)) {
      .rcbg04_pause(
        ctx,
        reason = "所有 stratum 均未得到可用 RCS 曲线（见 ctx$results$rcs_prognosis_by_group_fail_log）",
        suggestion = "检查 min_n_stratum / min_events_stratum、组内 index 变异或调小 nk",
        data_snapshot = fail_df
      )
    }
    stop("rcs_prognosis_by_group: no stratum curves available.", call. = FALSE)
  }

  curve_df <- dplyr::bind_rows(plot_list)
  strata_ok <- unique(as.character(curve_df[[stratum_var]]))
  curve_df[[stratum_var]] <- factor(curve_df[[stratum_var]], levels = groups)

  xr <- curve_df %>%
    dplyr::group_by(.data[[stratum_var]]) %>%
    dplyr::summarise(
      minx = min(x, na.rm = TRUE),
      maxx = max(x, na.rm = TRUE),
      .groups = "drop"
    )
  xmin_ov <- max(xr$minx, na.rm = TRUE)
  xmax_ov <- min(xr$maxx, na.rm = TRUE)

  ctx$results$rcs_prognosis_by_group_curve <- curve_df
  ctx$results$rcs_prognosis_by_group_nk_global <- nk_global
  ctx$results$rcs_prognosis_by_group_ref <- ref_global
  ctx$results$rcs_prognosis_by_group_strata_ok <- strata_ok
  ctx$results$rcs_prognosis_by_group_overlap_range <- c(xmin = xmin_ov, xmax = xmax_ov)

  if (!is.finite(xmin_ov) || !is.finite(xmax_ov) || xmin_ov >= xmax_ov) {
    if (.rcbg04_should_pause(bl_cfg, "pause_on_no_overlap_range", TRUE)) {
      .rcbg04_pause(
        ctx,
        reason = paste0(
          "各组 ", index_var, " 支持区间无足够重叠（max(各组min)=", xmin_ov,
          " >= min(各组max)=", xmax_ov, "），无法绘制叠加主图。"
        ),
        suggestion = "扩大样本、检查 index 分布，或改用分 stratum 单独展示（本 block 仅输出重叠叠加图）",
        data_snapshot = xr
      )
    }
    stop("rcs_prognosis_by_group: insufficient overlap range for overlay plot.", call. = FALSE)
  }

  curve_ov <- curve_df %>%
    dplyr::filter(x >= xmin_ov, x <= xmax_ov)

  grp_cols <- .rcbg04_resolve_overlay_colors(strata_ok, bl_cfg)
  overlay_ylim <- bl_cfg$overlay_ylim %||% c(0, 14)
  overlay_ylim <- suppressWarnings(as.numeric(overlay_ylim))
  if (length(overlay_ylim) != 2L || any(!is.finite(overlay_ylim)) || overlay_ylim[2] <= overlay_ylim[1]) {
    overlay_ylim <- c(0, 14)
  }

  ff <- plot_font_from_config(cfg)
  fig_w <- bl_cfg$figure_width %||% 7
  fig_h <- bl_cfg$figure_height %||% 5
  fig_cap <- bl_cfg$figure_caption %||% paste0(
    "RCS overlay of ", index_var, " by ", stratum_var,
    " (crude Cox per stratum, unified reference)"
  )
  fig_fn <- pub_figure_file(ctx, "main_figure", fig_cap)

  ctx <- save_figure(
    ctx,
    fig_fn,
    function() {
      p <- ggplot2::ggplot(
        curve_ov,
        ggplot2::aes(
          x = x,
          y = hr,
          color = .data[[stratum_var]],
          fill = .data[[stratum_var]]
        )
      ) +
        ggplot2::geom_ribbon(
          ggplot2::aes(ymin = lo, ymax = hi),
          alpha = 0.12,
          color = NA
        ) +
        ggplot2::geom_line(linewidth = 1) +
        ggplot2::geom_hline(yintercept = 1, linetype = 3, color = "grey40") +
        ggplot2::scale_color_manual(values = grp_cols, drop = FALSE) +
        ggplot2::scale_fill_manual(values = grp_cols, drop = FALSE) +
        ggplot2::coord_cartesian(ylim = overlay_ylim) +
        ggplot2::labs(
          title = paste0("RCS overlay (same axes): ", index_var, " vs HR by ", stratum_var),
          subtitle = paste0(
            "Overlap of group-wise ", index_var, " ranges [",
            formatC(xmin_ov, digits = 3, format = "f"), ", ",
            formatC(xmax_ov, digits = 3, format = "f"),
            "] — crossing here means HR order reverses at the same ", index_var,
            "  |  unified ref (median) = ",
            formatC(ref_global, digits = 4, format = "f"),
            "  |  global nk = ", nk_global
          ),
          x = index_var,
          y = "Hazard ratio (vs unified reference)",
          color = stratum_var,
          fill = stratum_var
        ) +
        ggplot2::theme_bw(base_size = 11, base_family = ff) +
        ggplot2::theme(
          text = ggplot2::element_text(family = ff),
          plot.title = ggplot2::element_text(face = "bold"),
          legend.position = "bottom"
        )

      if (is.finite(ref_global) && ref_global >= xmin_ov && ref_global <= xmax_ov) {
        p <- p + ggplot2::geom_vline(
          xintercept = ref_global,
          linetype = 2,
          color = "grey35"
        )
      }
      p
    },
    width = fig_w,
    height = fig_h
  )

  ctx$results$rcs_prognosis_by_group_figure <- fig_fn
  cli::cli_alert_success(
    "rcs_prognosis_by_group done ({length(strata_ok)} strata, overlap [{formatC(xmin_ov, digits = 3, format = 'f')}, {formatC(xmax_ov, digits = 3, format = 'f')}])"
  )

  ctx
}

register_block(
  "rcs_prognosis_by_group",
  block_rcs_prognosis_by_group,
  "按分组变量 crude Cox RCS 重叠区间叠加主图"
)
