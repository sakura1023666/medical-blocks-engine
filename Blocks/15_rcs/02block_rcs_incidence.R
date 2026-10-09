###############################################################################
#  rcs_incidence — 发病 Logistic RCS（Crude / Model1 / Model2），ggrcs 横排 ABC。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned（pipeline 决定数据源，块内不切换）
#  require_study  = project$study_type == "incidence"（非 incidence 则跳过）
#  协变量       = ctx$results$Model1Factors、Model2Factors（建议先 multicollinearity）
#  结局/暴露   = incidence$outcome_var、index_var；块内 Disease 0/1 按 project$disease 编码
#  cuttab       = 来自 24point_02_config.R；缺失时图例 Cutoff 用 OR=1 插值近似
#
#  register_block: "rcs_incidence"
#  # ── 配置 config$rcs_incidence（ri_cfg <- cfg$rcs_incidence %||% list()）────────
#  rcs_incidence = list(
#    index_var            = NULL,    # 连续暴露；NULL → incidence$index_var / logistic$index_var
#    crude_factors        = NULL,    # Fig 2A：NULL=完全不调整；如 "Country" → Crude 也调该列（Pooled 常用）
#    model1_factors       = NULL,    # Fig 2B：NULL → ctx$results$Model1Factors（完整列表）
#    model2_factors       = NULL,    # Fig 2C：NULL → ctx$results$Model2Factors（完整列表）
#    nk_range             = 3:5,     # rms::ols + rcs，AIC 在 3–5 结点间选 nk
#    pdf_color_config     = NULL,    # NULL 默认三色；或 list(list(color1,color2,color3),...)
#    color_seed           = 123,     # 多组配色时 sample 种子
#    histbin              = 0.01,    # ggrcs 直方图 bin 宽度（0704wx）
#    plot_x_quantiles     = NULL,    # 如 c(0.01, 0.99)：拟合仍用全样本，作图 x 轴限制在分位内（尾部稀疏时防曲线乱穿 OR=1）
#    figure_filename      = NULL,    # NULL → Fig 2. RCS of <Index> and <Disease>.pdf（双库对题统一）
#    cuttab_config_path   = "24point_02_config.R"  # 未加载 cuttab 时向上搜索并 source
#    group_cutoffs        = "primary", # <Index>_RCS_Group：primary=仅主 cutoff→二分（默认）；
#                                     # all=用全部 OR=1/峰值交点→可能多组（仅诊断用，不推荐进 Table S-XX）
#    cutoff_vlines        = "primary", # Model2 竖虚线：primary=仅主 cutoff 一条（发表默认）；
#                                     # all=标全部交点（调试）
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$rcs_cutoff_or1、rcs_cutoff_slope_zero、rcs_cutoffs_all（Model2）；
#      cutoff_value（主 cutoff：首个 OR=1，否则峰值）；<Index>_RCS_Group factor；
#      rcs_incidence_nk、res_crude|model1|model2、rcs_incidence_figure、model*_factors
#  cutoff 规则: 仅 1 个 OR=1 交点 → 该 x 为 cutoff；
#               ≥2 个 OR=1 交点 → 斜率=0 且 OR 最大的 x 仅当其落在某对 OR=1 交点之间才保留；
#               无 OR=1 交点 → 斜率=0 处 OR 最大的 x
#  分组: 默认仅用 primary cutoff → 2 组（<=c / >c），与 Table S-XX / logistic_*_glm_rcs 一致
#  图: 无背景直方图；Model 2（C）默认仅 primary 一条 cutoff 竖虚线；A/B 无竖线
#  文件: Figures/Fig 2. RCS plot ...pdf（15×5）；cutoff_<Index>.csv；rcs_cutoff_groups_<Index>.csv
#  源: C01_RCS_Logistic_model-调整cutoff-0704wx.R（不含 glm 直方图段）
#  依赖: ggrcs, rms, ggplot2, scales, patchwork
###############################################################################

.rci01_parse_factors <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  if (length(x) == 1L && is.character(x) && grepl("\\+", x, fixed = FALSE)) {
    return(trimws(unlist(strsplit(x, "\\s*\\+\\s*"))))
  }
  trimws(as.character(x))
}

.rci01_default_color3 <- function() {
  list(color1 = "#b0d5df", color2 = "#FF9999", color3 = "#FF9933")
}

.rci01_ensure_cuttab <- function(ri_cfg) {
  if (exists("cuttab", mode = "function")) return(invisible(TRUE))
  rel <- ri_cfg$cuttab_config_path %||% "24point_02_config.R"
  candidates <- unique(c(
    rel,
    file.path(getwd(), rel),
    file.path(getwd(), "..", rel),
    file.path(getwd(), "../..", rel)
  ))
  for (p in candidates) {
    if (nzchar(p) && file.exists(p)) {
      source(p, local = FALSE)
      if (exists("cuttab", mode = "function")) {
        cli::cli_alert_info("rcs_incidence: 已加载 cuttab（{normalizePath(p, winslash='/', mustWork=FALSE)}）")
        return(invisible(TRUE))
      }
    }
  }
  cli::cli_alert_warning(
    "rcs_incidence: 未找到 cuttab；图例 Cutoff 将使用 OR=1 插值值（请 source 24point_02_config.R）。"
  )
  invisible(FALSE)
}

.rci01_format_cutoff <- function(x, digits = 4L) {
  formatC(as.numeric(x), digits = digits, format = "f")
}

.rci01_find_roots_on_grid <- function(x, y, target = 0, tol = 1e-5) {
  if (length(x) < 2L) return(numeric(0))
  x <- as.numeric(x)
  y <- as.numeric(y)
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]
  if (length(x) < 2L) return(numeric(0))
  o <- order(x)
  x <- x[o]
  y <- y[o]
  f <- stats::approxfun(x, y, rule = 2)
  roots <- numeric(0)
  y_adj <- y - target
  for (i in seq_len(length(x) - 1L)) {
    if (abs(y_adj[i]) < tol) roots <- c(roots, x[i])
    if (y_adj[i] * y_adj[i + 1L] < 0) {
      r <- tryCatch(
        stats::uniroot(function(xi) f(xi) - target, c(x[i], x[i + 1L]))$root,
        error = function(e) NA_real_
      )
      if (is.finite(r)) roots <- c(roots, r)
    }
  }
  roots <- sort(unique(round(roots, 6)))
  if (length(roots) <= 1L) return(roots)
  tol_x <- max(diff(range(x)) * 1e-4, 1e-6)
  kept <- roots[1L]
  for (r in roots[-1L]) {
    if (r - tail(kept, 1L) > tol_x) kept <- c(kept, r)
  }
  kept
}

.rci01_find_slope_zero <- function(x, log_or, tol = 1e-4) {
  if (length(x) < 3L) return(numeric(0))
  x <- as.numeric(x)
  log_or <- as.numeric(log_or)
  ok <- is.finite(x) & is.finite(log_or)
  x <- x[ok]
  log_or <- log_or[ok]
  if (length(x) < 3L) return(numeric(0))
  o <- order(x)
  x <- x[o]
  log_or <- log_or[o]
  f <- stats::approxfun(x, log_or, rule = 2)
  span <- diff(range(x))
  eps <- max(span * 1e-6, 1e-6)
  deriv <- function(xi) (f(xi + eps) - f(xi - eps)) / (2 * eps)
  x_fine <- seq(min(x), max(x), length.out = max(500L, length(x) * 10L))
  d <- vapply(x_fine, deriv, numeric(1))
  roots <- numeric(0)
  for (i in seq_len(length(x_fine) - 1L)) {
    if (!is.finite(d[i]) || !is.finite(d[i + 1L])) next
    if (abs(d[i]) < tol) {
      roots <- c(roots, x_fine[i])
    } else if (d[i] * d[i + 1L] < 0) {
      r <- tryCatch(
        stats::uniroot(deriv, c(x_fine[i], x_fine[i + 1L]))$root,
        error = function(e) NA_real_
      )
      if (is.finite(r)) roots <- c(roots, r)
    }
  }
  roots <- sort(unique(round(roots, 6)))
  if (length(roots) <= 1L) return(roots)
  tol_x <- max(span * 1e-4, 1e-6)
  kept <- roots[1L]
  for (r in roots[-1L]) {
    if (r - tail(kept, 1L) > tol_x) kept <- c(kept, r)
  }
  kept
}

.rci01_slope_zero_peak <- function(x, log_or, slope_zero) {
  slope_zero <- unique(as.numeric(slope_zero[is.finite(slope_zero)]))
  if (!length(slope_zero) || length(x) < 2L) return(NA_real_)
  f <- stats::approxfun(as.numeric(x), as.numeric(log_or), rule = 2)
  or_at <- exp(f(slope_zero))
  slope_zero[which.max(or_at)]
}

.rci01_is_between_or1_roots <- function(x, or1) {
  or1 <- sort(unique(as.numeric(or1[is.finite(or1)])))
  if (length(or1) < 2L || !is.finite(x)) return(FALSE)
  any(vapply(
    seq_len(length(or1) - 1L),
    function(i) x > or1[i] && x < or1[i + 1L],
    logical(1L)
  ))
}

.rci01_refined_cutoffs <- function(x, log_or, or1, slope_zero) {
  or1 <- sort(unique(as.numeric(or1[is.finite(or1)])))
  peak_x <- .rci01_slope_zero_peak(x, log_or, slope_zero)

  kept_peak <- NA_real_
  if (length(or1) == 1L) {
    all_cutoffs <- or1
  } else if (length(or1) >= 2L) {
    if (is.finite(peak_x) && .rci01_is_between_or1_roots(peak_x, or1)) {
      kept_peak <- peak_x
    }
    all_cutoffs <- sort(unique(c(or1, kept_peak[is.finite(kept_peak)])))
  } else {
    kept_peak <- if (is.finite(peak_x)) {
      peak_x
    } else if (length(x) >= 1L) {
      as.numeric(x)[which.max(as.numeric(log_or))]
    } else {
      NA_real_
    }
    all_cutoffs <- sort(unique(as.numeric(kept_peak[is.finite(kept_peak)])))
  }

  kept_peak_vec <- as.numeric(kept_peak[is.finite(kept_peak)])
  list(or1 = or1, slope_zero = kept_peak_vec, peak = kept_peak_vec, all = all_cutoffs)
}

.rci01_find_rcs_cutoffs <- function(fit, Index) {
  pred <- do.call(rms::Predict, list(fit, as.name(Index), ref.zero = TRUE))
  x <- as.numeric(pred[[Index]])
  log_or <- as.numeric(pred$yhat)
  or1 <- .rci01_find_roots_on_grid(x, log_or, target = 0)
  slope_zero_raw <- .rci01_find_slope_zero(x, log_or)
  .rci01_refined_cutoffs(x, log_or, or1, slope_zero_raw)
}

.rci01_primary_cutoff <- function(cutoffs) {
  if (length(cutoffs$or1) == 1L) return(cutoffs$or1[1L])
  if (length(cutoffs$peak)) return(cutoffs$peak[1L])
  if (length(cutoffs$or1)) return(cutoffs$or1[1L])
  if (length(cutoffs$all)) return(cutoffs$all[1L])
  NA_real_
}

.rci01_cutoff_or1 <- function(fit, Index) {
  .rci01_primary_cutoff(.rci01_find_rcs_cutoffs(fit, Index))
}

.rci01_cutoff_factor <- function(x, cutoffs, index_name = "Index") {
  col_name <- paste0(index_name, "_RCS_Group")
  x_num <- suppressWarnings(as.numeric(x))
  cutoffs <- sort(unique(as.numeric(cutoffs[is.finite(cutoffs)])))
  if (!length(cutoffs)) {
    lbl <- "All (no cutoff)"
    return(list(
      factor = factor(rep(lbl, length(x_num)), levels = lbl),
      col_name = col_name,
      labels = lbl,
      n_groups = 1L,
      cutoffs = numeric(0)
    ))
  }
  breaks <- c(-Inf, cutoffs, Inf)
  n_grp <- length(breaks) - 1L
  labels <- character(n_grp)
  # Convention A: x < cut → lower group; x >= cut → higher group (equals → high)
  for (i in seq_len(n_grp)) {
    if (i == 1L) {
      labels[i] <- paste0("<", .rci01_format_cutoff(cutoffs[1L]))
    } else if (i == n_grp) {
      labels[i] <- paste0(">=", .rci01_format_cutoff(cutoffs[length(cutoffs)]))
    } else {
      labels[i] <- paste0(
        ">=", .rci01_format_cutoff(cutoffs[i - 1L]),
        " & <", .rci01_format_cutoff(cutoffs[i])
      )
    }
  }
  f <- cut(
    x_num,
    breaks = breaks,
    labels = labels,
    include.lowest = TRUE,
    right = FALSE
  )
  list(
    factor = f,
    col_name = col_name,
    labels = labels,
    n_groups = n_grp,
    cutoffs = cutoffs
  )
}

.rci01_add_group_column <- function(df, Index, cutoffs) {
  if (is.null(df) || !is.data.frame(df) || !Index %in% names(df)) return(df)
  grp <- .rci01_cutoff_factor(df[[Index]], cutoffs, Index)
  df[[grp$col_name]] <- grp$factor
  df
}

.rci01_cutoff_label_text <- function(cutoffs) {
  primary <- .rci01_primary_cutoff(cutoffs)
  if (!is.finite(primary)) return("Cutoff: NA")
  paste0("Cutoff: ", formatC(as.numeric(primary), digits = 4, format = "f"))
}

.rci01_cuttab_out <- function(fit1, Index, data_imp, cutpoint) {
  if (exists("cuttab", mode = "function")) {
    return(cuttab(fit1, Index, data_imp, cutpoint = cutpoint))
  }
  dat <- matrix(NA_character_, 6, 2)
  dat[3, 1] <- "Inflection point"
  dat[3, 2] <- as.character(cutpoint)
  dat
}

.rci01_strip_histogram_layers <- function(plot_obj) {
  if (is.null(plot_obj$layers) || !length(plot_obj$layers)) return(plot_obj)
  is_hist <- vapply(plot_obj$layers, function(ly) {
    grepl("GeomBar|GeomHistogram", class(ly$geom)[1])
  }, logical(1))
  if (any(is_hist)) plot_obj$layers <- plot_obj$layers[!is_hist]
  plot_obj
}

.rci01_clip_ggrcs_layers <- function(plot_obj, y_cap = NULL, x_range = NULL) {
  xr <- suppressWarnings(as.numeric(x_range)[1:2])
  use_x <- length(xr) >= 2L && all(is.finite(xr)) && xr[2L] > xr[1L]
  for (i in seq_along(plot_obj$layers)) {
    ly <- plot_obj$layers[[i]]$data
    if (is.null(ly) || !is.data.frame(ly)) next
    if (use_x && "x" %in% names(ly)) {
      out_x <- is.finite(ly$x) & (ly$x < xr[1L] | ly$x > xr[2L])
      for (nm in c("y", "ymin", "ymax")) {
        if (nm %in% names(ly)) ly[[nm]][out_x] <- NA_real_
      }
    }
    if (is.finite(y_cap) && y_cap > 0) {
      for (nm in c("y", "ymin", "ymax")) {
        if (nm %in% names(ly)) {
          v <- ly[[nm]]
          v[!is.finite(v)] <- NA_real_
          v[v > y_cap] <- NA_real_
          ly[[nm]] <- v
        }
      }
    }
    plot_obj$layers[[i]]$data <- ly
  }
  plot_obj
}

.rci01_window_y_quantile <- function(plot_obj, x_range = NULL, q = 0.95) {
  bd <- ggplot2::ggplot_build(plot_obj)
  xr <- suppressWarnings(as.numeric(x_range)[1:2])
  use_x <- length(xr) >= 2L && all(is.finite(xr)) && xr[2L] > xr[1L]
  vals <- numeric(0)
  for (i in seq_along(bd$data)) {
    ly <- bd$data[[i]]
    if ("count" %in% names(ly) && "xmin" %in% names(ly)) next
    if (use_x && "x" %in% names(ly)) {
      keep <- is.finite(ly$x) & ly$x >= xr[1L] & ly$x <= xr[2L]
      if (!any(keep)) next
      ly <- ly[keep, , drop = FALSE]
    }
    for (nm in c("y", "ymax")) {
      if (nm %in% names(ly)) {
        v <- ly[[nm]]
        vals <- c(vals, v[is.finite(v) & v > 0])
      }
    }
  }
  if (!length(vals)) return(NA_real_)
  as.numeric(stats::quantile(vals, probs = q, na.rm = TRUE, names = FALSE))
}

.rci01_ggrcs_y_limits <- function(plot_obj, ann_frac = 0.18, x_range = NULL) {
  bd <- ggplot2::ggplot_build(plot_obj)
  xr <- suppressWarnings(as.numeric(x_range)[1:2])
  use_x <- length(xr) >= 2L && all(is.finite(xr)) && xr[2L] > xr[1L]
  ymaxs <- numeric(0)
  ymins <- numeric(0)
  for (i in seq_along(bd$data)) {
    ly <- bd$data[[i]]
    if ("count" %in% names(ly) && "xmin" %in% names(ly)) next
    if (use_x && "x" %in% names(ly)) {
      keep <- is.finite(ly$x) & ly$x >= xr[1L] & ly$x <= xr[2L]
      if (!any(keep)) next
      ly <- ly[keep, , drop = FALSE]
    }
    if ("y" %in% names(ly)) {
      ymaxs <- c(ymaxs, ly$y)
      ymins <- c(ymins, ly$y)
    }
    if ("ymax" %in% names(ly)) ymaxs <- c(ymaxs, ly$ymax)
    if ("ymin" %in% names(ly)) ymins <- c(ymins, ly$ymin)
  }
  ymax_data <- max(ymaxs, na.rm = TRUE)
  if (!is.finite(ymax_data) || ymax_data <= 0) ymax_data <- 1
  ymin <- min(ymins, na.rm = TRUE)
  if (!is.finite(ymin) || ymin > 0) ymin <- 0
  y_span <- max(ymax_data - ymin, ymax_data * 0.05, 1e-6)
  ymax_plot <- ymax_data + y_span * ann_frac
  y_step <- y_span * ann_frac / 2.5
  list(ymin = ymin, ymax_data = ymax_data, ymax_plot = ymax_plot, y_step = y_step)
}

.rci01_add_cutoff_vlines <- function(plot_obj, cutoffs, y_lim, plot_ff, label_digits = 2L,
                                      x_range = NULL, fit = NULL, Index = NULL,
                                      vline_mode = c("primary", "all")) {
  # primary：仅主 cutoff 一条竖虚线（发表默认）；all：全部 OR=1/峰点交点
  vline_mode <- match.arg(vline_mode)
  xs <- if (exists(".pub_figure_rcs_vline_cutoffs", mode = "function")) {
    .pub_figure_rcs_vline_cutoffs(cutoffs, vline_mode)
  } else if (identical(vline_mode, "all")) {
    sort(unique(as.numeric(cutoffs$all[is.finite(cutoffs$all)])))
  } else {
    primary <- .rci01_primary_cutoff(cutoffs)
    if (is.finite(primary)) primary else numeric(0)
  }
  if (!length(xs)) return(plot_obj)

  plot_obj <- plot_obj + ggplot2::geom_vline(
    xintercept = xs,
    linetype   = "dashed",
    linewidth  = 0.45,
    color      = "gray35"
  )

  if (is.null(x_range)) x_range <- xs
  x_rng <- range(x_range, na.rm = TRUE)
  x_span <- diff(x_rng)
  if (!is.finite(x_span) || x_span <= 0) x_span <- max(abs(xs), 1)
  x_off <- x_span * 0.015

  ys <- rep(y_lim$ymax_data * 0.88, length(xs))
  if (!is.null(fit) && !is.null(Index) && nzchar(as.character(Index)[1L])) {
    pred <- tryCatch(
      do.call(rms::Predict, list(fit, as.name(Index), ref.zero = TRUE)),
      error = function(e) NULL
    )
    if (!is.null(pred)) {
      px <- as.numeric(pred[[Index]])
      por <- exp(as.numeric(pred$yhat))
      ok <- is.finite(px) & is.finite(por)
      if (sum(ok) >= 2L) {
        f_or <- stats::approxfun(px[ok], por[ok], rule = 2)
        ys <- pmax(f_or(xs), y_lim$ymin + 0.02 * diff(c(y_lim$ymin, y_lim$ymax_data)))
      }
    }
  }

  y_drop <- max(y_lim$y_step * 0.45, y_lim$ymax_data * 0.03, 0.04)
  for (i in seq_along(xs)) {
    plot_obj <- plot_obj + ggplot2::annotate(
      "text",
      x      = xs[i] + x_off,
      y      = ys[i] - (i - 1L) %% 3L * y_drop,
      label  = .rci01_format_cutoff(xs[i], digits = label_digits),
      angle  = 0,
      hjust  = 0,
      vjust  = 0.5,
      size   = 3.2,
      family = plot_ff,
      color  = "gray20"
    )
  }
  plot_obj
}

# ── ggrcs 面板：OR 曲线；可选 cutoff 竖虚线（仅 Model 2）────────────────────
.rci01_ggrcs_panel <- function(data_imp, fit, Index, selected_colors3, an, out,
                               title_label, cutoffs, histbin = 1, plot_ff = NULL,
                               cutoff_label_digits = 2L, show_cutoff_lines = FALSE,
                               cutoff_vline_mode = c("primary", "all", "none"),
                               xlab_display = NULL, ylim = NULL, y_min = 0, y_max = NULL,
                               ylim_force = FALSE, config = NULL, x_range = NULL,
                               p_overall = NULL, p_nonlinear = NULL) {
  cutoff_vline_mode <- match.arg(cutoff_vline_mode)
  if (is.null(plot_ff)) {
    plot_ff <- if (exists("plot_font_from_config", mode = "function")) {
      plot_font_from_config(list(plot = list(font_family = "Times New Roman")))
    } else if (exists("resolve_plot_font_family", mode = "function")) {
      resolve_plot_font_family("Times New Roman")
    } else {
      "serif"
    }
  }
  xlab_display <- as.character(xlab_display %||% "")[1L]
  if (!nzchar(xlab_display)) {
    xlab_display <- if (exists("pipeline_plot_axis_label", mode = "function")) {
      pipeline_plot_axis_label(Index)
    } else {
      gsub("_", " ", as.character(Index)[1L], fixed = TRUE)
    }
  }
  # ggrcs 默认 P.Nonlinear=TRUE、lift=TRUE 会自带 P 值标注与右侧 density 副轴；
  # 本块已 strip 直方图并手动 annotate P for overall / nonlinear，须关闭以免重复图注。
  plot_obj <- ggrcs(
    data = data_imp,
    fit = fit,
    x = Index,
    histcol = selected_colors3$color1,
    ribcol = scales::alpha(selected_colors3$color2, 0.8),
    linecol = selected_colors3$color3,
    lwd = 1.5,
    xlab = xlab_display,
    ylab = "OR(95%CI)",
    fontsize = 12,
    fontfamily = plot_ff,
    px = 1.2,
    py = 4,
    histbin = histbin,
    P.Nonlinear = FALSE,
    lift = FALSE
  )

  plot_obj <- .rci01_strip_histogram_layers(plot_obj)
  ylim_fixed <- suppressWarnings(as.numeric(ylim %||% numeric(0)))
  y_max_cap <- suppressWarnings(as.numeric(y_max %||% NA_real_)[1L])
  if (length(ylim_fixed) >= 2L && all(is.finite(ylim_fixed[1:2]))) {
    y_max_cap <- ylim_fixed[2L]
  }
  plot_obj <- .rci01_clip_ggrcs_layers(plot_obj, y_cap = y_max_cap, x_range = x_range)
  ## 去掉 ggrcs 可能写入的 y 轴 limits（否则 CI 会被硬裁到 ~5）
  if (!is.null(plot_obj$scales) && length(plot_obj$scales$scales)) {
    keep_sc <- vapply(plot_obj$scales$scales, function(s) {
      aes <- tryCatch(s$aesthetics, error = function(e) character(0))
      !(inherits(s, "ScaleContinuous") && any(aes %in% c("y", "ymin", "ymax")))
    }, logical(1L))
    plot_obj$scales$scales <- plot_obj$scales$scales[keep_sc]
  }
  y_lim <- .rci01_ggrcs_y_limits(plot_obj, x_range = x_range)
  y_max_cap <- suppressWarnings(as.numeric(y_max %||% NA_real_)[1L])
  y_min_cap <- suppressWarnings(as.numeric(y_min %||% 0)[1L])
  ylim_fixed <- suppressWarnings(as.numeric(ylim %||% numeric(0)))
  y_q <- suppressWarnings(as.numeric(config$rcs_incidence$ylim_auto_quantile %||% 0.95)[1L])
  if (!is.finite(y_q) || y_q <= 0 || y_q > 1) y_q <- 0.95
  win_q <- .rci01_window_y_quantile(plot_obj, x_range = x_range, q = y_q)
  if (length(ylim_fixed) >= 2L && all(is.finite(ylim_fixed[1:2]))) {
    y_min_cap <- ylim_fixed[1L]
    y_max_cap <- ylim_fixed[2L]
  }
  ## 未指定 ylim：按作图窗内 CI 分位数自动定轴，避免贴顶假横线
  auto_from_win <- if (is.finite(win_q)) max(win_q * 1.12, 2, na.rm = TRUE) else NA_real_
  auto_max <- max(
    c(y_lim$ymax_data * 1.12, y_lim$ymax_data + 0.8, auto_from_win, 2),
    na.rm = TRUE
  )
  ylim_locked <- isTRUE(ylim_force) ||
    (length(ylim_fixed) >= 2L && all(is.finite(ylim_fixed[1:2])))
  if (!is.finite(y_max_cap) || y_max_cap <= 0) {
    y_max_cap <- auto_max
  } else if (y_lim$ymax_data > y_max_cap * 1.05 && !ylim_locked) {
    cli::cli_alert_warning(
      "RCS y_max={y_max_cap} < 数据/CI 峰值 {round(y_lim$ymax_data, 2)}，自动抬高 y 轴至 {round(auto_max, 2)}"
    )
    y_max_cap <- auto_max
  } else if (ylim_locked && y_lim$ymax_data > y_max_cap * 1.05) {
    cli::cli_alert_info(
      "RCS ylim_force：保留 y_max={y_max_cap}（窗内 CI 峰值 {round(y_lim$ymax_data, 2)} 已裁剪）"
    )
  } else if (y_max_cap + 1e-8 < y_lim$ymax_data && !isTRUE(ylim_force)) {
    cli::cli_alert_warning(
      "RCS y_max={y_max_cap} < 窗内 CI max={round(y_lim$ymax_data,2)}，自动抬高到 {round(auto_max,2)}"
    )
    y_max_cap <- auto_max
  } else if (isTRUE(ylim_force) && is.finite(auto_from_win) &&
             auto_from_win + 1e-8 < y_max_cap &&
             !(length(ylim_fixed) >= 2L && all(is.finite(ylim_fixed[1:2])))) {
    y_max_cap <- auto_from_win
    cli::cli_alert_info(
      "RCS y 轴按窗内 P{round(y_q*100)} CI 定至 {round(y_max_cap, 2)}（裁剪极端外推）"
    )
  }
  if (is.finite(y_max_cap) && y_max_cap > 0) {
    y_min_cap <- if (is.finite(y_min_cap)) y_min_cap else 0
    y_lim$ymin <- y_min_cap
    y_lim$ymax_plot <- y_max_cap
    y_lim$y_step <- max((y_lim$ymax_plot - y_lim$ymin) * 0.06, 0.15)
  }
  y_breaks <- if (is.finite(y_lim$ymax_plot) && y_lim$ymax_plot > y_lim$ymin) {
    by <- max(1, floor((y_lim$ymax_plot - y_lim$ymin) / 5))
    seq(y_lim$ymin, y_lim$ymax_plot, by = by)
  } else {
    NULL
  }
  cli::cli_alert_info(
    "RCS y-axis: data_max={round(y_lim$ymax_data, 2)}, plot_max={round(y_lim$ymax_plot, 2)}"
  )

  x_min <- min(data_imp[[Index]], na.rm = TRUE)
  y_top <- y_lim$ymax_plot
  y_step <- y_lim$y_step

  plot_obj <- plot_obj +
    ggplot2::geom_hline(
      ggplot2::aes(yintercept = 1),
      linetype = "dashed", linewidth = 0.5, color = "gray50"
    )
  if (isTRUE(show_cutoff_lines)) {
    plot_obj <- .rci01_add_cutoff_vlines(
      plot_obj, cutoffs, y_lim, plot_ff,
      label_digits = cutoff_label_digits,
      x_range = range(data_imp[[Index]], na.rm = TRUE),
      fit = fit,
      Index = Index,
      vline_mode = cutoff_vline_mode
    )
  }
  p_ov_val <- suppressWarnings(as.numeric(p_overall %||% an[nrow(an), 3]))
  p_nl_val <- suppressWarnings(as.numeric(p_nonlinear %||% an[2, 3]))
  fmt_p_annot <- function(p) {
    if (!is.finite(p)) return("NA")
    if (p < 0.001) "< 0.001" else paste0("= ", sprintf("%.3f", as.numeric(p)))
  }
  kn_lab <- ""
  if (isTRUE((config$rcs_incidence %||% list())$annotate_knots %||% FALSE)) {
    kn <- tryCatch(as.numeric(fit$Design$parms[[Index]]), error = function(e) numeric(0))
    kn <- kn[is.finite(kn)]
    if (length(kn)) {
      kn_lab <- paste0(
        "Knots (", length(kn), "): ",
        paste(formatC(kn, digits = 1L, format = "f"), collapse = ", ")
      )
    }
  }
  ref_lab <- ""
  if (isTRUE((config$rcs_incidence %||% list())$annotate_reference %||% FALSE)) {
    ref_v <- tryCatch(
      as.numeric(fit$Design$limits["Adjust to", Index]),
      error = function(e) NA_real_
    )
    if (!is.finite(ref_v)) {
      ref_v <- suppressWarnings(stats::median(as.numeric(data_imp[[Index]]), na.rm = TRUE))
    }
    if (is.finite(ref_v)) {
      ref_lab <- paste0(
        "Reference (OR=1): ",
        formatC(ref_v, digits = 1L, format = "f"),
        " (median)"
      )
    }
  }
  plot_obj <- plot_obj +
    ggplot2::annotate(
      "text", x = x_min, y = y_top * 0.98,
      label = paste0("P for overall ", fmt_p_annot(p_ov_val)),
      family = plot_ff, hjust = 0, vjust = 1
    ) +
    ggplot2::annotate(
      "text", x = x_min, y = y_top * 0.98 - y_step,
      label = paste0("P for nonlinear ", fmt_p_annot(p_nl_val)),
      family = plot_ff, hjust = 0, vjust = 1
    ) +
    {
      extra <- list()
      if (nzchar(kn_lab)) {
        extra[[length(extra) + 1L]] <- ggplot2::annotate(
          "text", x = x_min, y = y_top * 0.98 - 2 * y_step,
          label = kn_lab,
          family = plot_ff, hjust = 0, vjust = 1, size = 3.2
        )
      }
      if (nzchar(ref_lab)) {
        extra[[length(extra) + 1L]] <- ggplot2::annotate(
          "text", x = x_min, y = y_top * 0.98 - 3 * y_step,
          label = ref_lab,
          family = plot_ff, hjust = 0, vjust = 1, size = 3.2
        )
      }
      if (!length(extra)) ggplot2::geom_blank() else extra
    } +
    ggplot2::scale_y_continuous(
      breaks = y_breaks,
      oob = scales::oob_squish,
      expand = ggplot2::expansion(mult = c(0.02, 0.06))
    ) +
    ggplot2::coord_cartesian(
      ylim = c(y_lim$ymin, y_lim$ymax_plot),
      clip = "on"
    ) +
    ggplot2::labs(title = title_label, x = xlab_display, y = "OR (95%CI)") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      legend.key = element_blank(),
      text = ggplot2::element_text(family = plot_ff),
      axis.title = ggplot2::element_text(family = plot_ff),
      axis.text = ggplot2::element_text(family = plot_ff),
      legend.text = ggplot2::element_text(family = plot_ff),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )
  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(config, "mimic_inc_prog_sle_aki")) {
    kn <- tryCatch(as.numeric(fit$Design$parms[[Index]]), error = function(e) numeric(0))
    kn <- kn[is.finite(kn)]
    if (length(kn)) {
      plot_obj <- plot_obj + ggplot2::geom_rug(
        data = data.frame(.kn = kn),
        ggplot2::aes(x = .kn),
        inherit.aes = FALSE, sides = "b", color = "#2874C5", linewidth = 0.7
      )
    }
    if (exists("pub_figure_profile_apply_ggplot", mode = "function")) {
      plot_obj <- pub_figure_profile_apply_ggplot(plot_obj, config)
    }
  }
  plot_obj <- plot_obj +
    ggplot2::coord_cartesian(
      ylim = c(y_lim$ymin, y_lim$ymax_plot),
      clip = "on"
    )
}

.rci01_fit_panel <- function(data_imp, Index, nk, covar_rhs = NULL) {
  if (is.null(covar_rhs) || !nzchar(covar_rhs)) {
    formula1 <- stats::as.formula(paste0("Disease ~ rcs(", Index, ",", nk, ")"))
    manual_rhs <- paste(Index, collapse = " + ")
  } else {
    formula1 <- stats::as.formula(paste0(
      "Disease ~ rcs(", Index, ",", nk, ")+", covar_rhs
    ))
    manual_rhs <- paste(c(Index, covar_rhs), collapse = "+")
  }
  fit <- rms::lrm(formula1, x = TRUE, y = TRUE, data = data_imp)
  cutoffs <- .rci01_find_rcs_cutoffs(fit, Index)
  cutoff_or1 <- .rci01_primary_cutoff(cutoffs)
  manual_formula <- stats::as.formula(paste("Disease ~", manual_rhs))
  fit1 <- stats::glm(manual_formula, data = data_imp, family = "binomial")
  out <- .rci01_cuttab_out(fit1, Index, data_imp, cutoff_or1)
  an <- anova(fit)
  list(fit = fit, fit1 = fit1, out = out, an = an, cutoff_or1 = cutoff_or1, cutoffs = cutoffs)
}

block_rcs_incidence <- function(ctx, ...) {
  cfg <- ctx$config
  study_type <- tolower(trimws(cfg$project$study_type %||% ""))
  if (!identical(study_type, "incidence")) {
    cli::cli_alert_info("rcs_incidence: study_type 非 incidence，跳过。")
    return(ctx)
  }

  for (pkg in c("ggrcs", "rms", "ggplot2", "scales")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("rcs_incidence: 需要 ", pkg, " 包。")
    }
  }
  suppressPackageStartupMessages({
    library(ggrcs)
    library(rms)
    library(ggplot2)
    library(scales)
  })

  ri_cfg <- cfg$rcs_incidence %||% list()
  inc_cfg <- cfg$incidence %||% list()
  cox_legacy <- cfg$cox %||% list()

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp) || !is.data.frame(data_imp)) {
    stop("rcs_incidence: 无分析数据，请先运行 data_clean / imputation。")
  }

  Index <- as.character(
    ri_cfg$index_var %||% inc_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  )[1L]
  if (is.null(Index) || !nzchar(Index)) {
    stop("rcs_incidence: 未设置 index_var。")
  }
  if (exists("pipeline_index_is_categorical", mode = "function") &&
      Index %in% names(data_imp) &&
      isTRUE(pipeline_index_is_categorical(data_imp[[Index]]))) {
    cli::cli_alert_info("分类暴露：跳过 rcs_incidence（RCS 仅适用于连续暴露）")
    return(ctx)
  }
  Disease <- cfg$project$analysis_group %||% cfg$project$disease %||% "Disease"
  outcome_col <- inc_cfg$outcome_var %||% cfg$data$outcome_column %||% "Disease"

  if (!outcome_col %in% names(data_imp)) {
    stop("rcs_incidence: 结局列 '", outcome_col, "' 不在数据中。")
  }
  if (!Index %in% names(data_imp)) {
    stop("rcs_incidence: 指标列 '", Index, "' 不在数据中。")
  }

  .rci01_ensure_cuttab(ri_cfg)

  cfg_m1 <- as.character(cox_legacy$model1_covariates %||% character(0))
  cfg_m2 <- as.character(cox_legacy$model2_covariates %||% character(0))
  gate_m1 <- .rci01_parse_factors(ctx$results$Model1Factors)
  gate_m2 <- .rci01_parse_factors(ctx$results$Model2Factors)
  ac_on <- isTRUE((cfg$assoc_covariate %||% list())$enable %||% TRUE)
  assoc_m1 <- .rci01_parse_factors(
    ctx$results$assoc_model1_factors %||% ctx$results$logistic_model1_factors
  )
  assoc_m2 <- .rci01_parse_factors(
    ctx$results$assoc_model2_factors %||% ctx$results$logistic_model2_factors
  )
  # 闸门 B / VIF-final 锁定后：禁止 preset 覆盖
  if (isTRUE(ctx$results$dual_db_covariate_harmonized) &&
      length(gate_m1) && length(gate_m2)) {
    Model1Factors <- gate_m1
    Model2Factors <- gate_m2
    cli::cli_alert_info("rcs_incidence: 使用闸门 B 锁定 Model1/Model2")
  } else if (ac_on && length(assoc_m1)) {
    Model1Factors <- assoc_m1
    Model2Factors <- if (length(assoc_m2)) assoc_m2 else gate_m2
    cli::cli_alert_info("rcs_incidence: 使用 assoc 协变量铁律 Model1/Model2（与 Table 2 一致）")
  } else {
    Model1Factors <- .rci01_parse_factors(
      ri_cfg$model1_factors %||% ctx$results$Model1Factors %||% cfg_m1
    )
    Model2Factors <- .rci01_parse_factors(
      ri_cfg$model2_factors %||% ctx$results$Model2Factors %||% cfg_m2
    )
  }
  if (length(Model1Factors) == 0L) {
    stop("rcs_incidence: Model1Factors 为空。")
  }
  if (length(Model2Factors) == 0L) {
    stop("rcs_incidence: Model2Factors 为空。")
  }
  if ("Age_Years" %in% Model1Factors && "Age_Group" %in% Model1Factors) {
    Model1Factors <- Model1Factors[Model1Factors != "Age_Group"]
  }

  Model1Factors <- setdiff(Model1Factors, Index)
  Model2Factors <- setdiff(Model2Factors, Index)
  Model1Factors <- intersect(Model1Factors, names(data_imp))
  Model2Factors <- intersect(Model2Factors, names(data_imp))
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    merged <- pipeline_merge_force_covariates(
      Model1Factors, Model2Factors, names(data_imp), cfg
    )
    Model1Factors <- merged$M1
    Model2Factors <- merged$M2
  }
  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(Model1Factors, Model2Factors, cfg, Index)
    Model1Factors <- cn$M1
    Model2Factors <- cn$M2
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      merged2 <- pipeline_merge_force_covariates(
        Model1Factors, Model2Factors, names(data_imp), cfg
      )
      Model1Factors <- merged2$M1
      Model2Factors <- merged2$M2
    }
  }
  if (length(Model1Factors) == 0L) stop("rcs_incidence: Model1Factors 无可用列。")
  if (length(Model2Factors) == 0L) stop("rcs_incidence: Model2Factors 无可用列。")
  if (length(Model1Factors) && length(Model2Factors) &&
      setequal(Model1Factors, Model2Factors) && length(Model1Factors) > 3L) {
    demo <- intersect(c("Age", "Gender", "Sex", "Race"), Model2Factors)
    if (length(demo)) {
      cli::cli_alert_warning(
        "rcs_incidence: Model1 与 Model2 相同，Model1 回退为 {paste(demo, collapse = ', ')}"
      )
      Model1Factors <- demo
    }
  }
  Model3Factors <- if (exists("pipeline_rcs_model3_covs", mode = "function")) {
    pipeline_rcs_model3_covs(ctx, cfg, Model2Factors, names(data_imp), Index)
  } else {
    character(0)
  }
  Model3Factors <- intersect(setdiff(as.character(Model3Factors %||% character(0)), Index), names(data_imp))
  if (!length(setdiff(Model3Factors, Model2Factors))) {
    if (exists("pipeline_model3_enabled", mode = "function") &&
        isTRUE(pipeline_model3_enabled(cfg))) {
      Model3Factors <- as.character(Model2Factors)
      cli::cli_alert_info(
        "rcs_incidence Model3: 本库无额外学术必调列，仍保留第 4 面板（协变量同 Model2，双库布局对齐）"
      )
    } else {
      Model3Factors <- character(0)
    }
  }
  m3_sig <- isTRUE(ctx$results$model3_significant)

  CrudeFactors <- .rci01_parse_factors(ri_cfg$crude_factors %||% character(0))
  CrudeFactors <- setdiff(intersect(CrudeFactors, names(data_imp)), Index)

  need_cols <- unique(c(outcome_col, Index, CrudeFactors, Model1Factors, Model2Factors, Model3Factors))
  data_imp <- as.data.frame(data_imp[, need_cols, drop = FALSE])
  data_imp <- stats::na.omit(data_imp)
  names(data_imp)[names(data_imp) == outcome_col] <- "Disease"

  data_imp$Disease <- as.character(data_imp$Disease)
  data_imp$Disease <- ifelse(data_imp$Disease == Disease, 1, 0)

  cli::cli_h2("rcs_incidence (lrm + ggrcs)")
  cli::cli_alert_info("Index={Index}, n={nrow(data_imp)}")
  if (length(CrudeFactors)) {
    cli::cli_alert_info("Crude(+): {paste(CrudeFactors, collapse = ', ')}")
  }
  cli::cli_alert_info("Model1: {paste(Model1Factors, collapse = ', ')}")
  cli::cli_alert_info("Model2: {paste(Model2Factors, collapse = ', ')}")
  if (length(Model3Factors)) {
    cli::cli_alert_info("Model3: {paste(Model3Factors, collapse = ', ')}")
  }

  assign("dd", rms::datadist(data_imp), envir = .GlobalEnv)
  options(datadist = "dd")

  nk_range <- as.integer(ri_cfg$nk_range %||% (cfg$rcs %||% list())$nk_range %||% 3:5)
  if (!length(nk_range)) nk_range <- 3:5
  AIC_val <- Inf
  nk <- NA_integer_
  for (i in nk_range) {
    formula <- stats::as.formula(paste("Disease ~ rcs(", Index, ", ", i, ")", sep = ""))
    fit <- rms::ols(formula, data = data_imp)
    tmp <- stats::AIC(fit)
    if (i == nk_range[1]) {
      AIC_val <- tmp
      nk <- i
    }
    if (tmp < AIC_val) {
      AIC_val <- tmp
      nk <- i
    }
  }
  if (is.na(nk)) stop("rcs_incidence: nk 选择失败。")
  cli::cli_alert_success("Selected nk = {nk}")

  color_cfg <- ri_cfg$pdf_color_config
  if (is.null(color_cfg)) {
    selected_colors3 <- .rci01_default_color3()
  } else if (is.list(color_cfg[[1]])) {
    set.seed(ri_cfg$color_seed %||% 123)
    selected_colors3 <- color_cfg[[sample(seq_along(color_cfg), 1)]]
    selected_colors3 <- list(
      color1 = selected_colors3$color1,
      color2 = selected_colors3$color2,
      color3 = selected_colors3$color3
    )
  } else {
    selected_colors3 <- color_cfg
  }

  histbin <- ri_cfg$histbin %||% 0.01
  cutoff_label_digits <- as.integer(ri_cfg$cutoff_label_digits %||% 2L)
  if (!is.finite(cutoff_label_digits) || cutoff_label_digits < 0L) {
    cutoff_label_digits <- 2L
  }
  # Model2/3 竖虚线：默认 primary；all=全部交点；none=不画阈值竖线（完整剂量–反应为主时）
  cutoff_vline_mode <- tolower(as.character(ri_cfg$cutoff_vlines %||% "primary")[1L])
  if (!cutoff_vline_mode %in% c("primary", "all", "none")) cutoff_vline_mode <- "primary"
  plot_ff <- plot_font_from_config(cfg)

  # 作图 x 轴限制：小样本尾部稀疏时避免曲线外推到空区乱穿 OR=1
  plot_data <- data_imp
  pxq <- as.numeric(ri_cfg$plot_x_quantiles %||% numeric(0))
  if (length(pxq) >= 2L && all(is.finite(pxq[1:2]))) {
    q_lo <- max(0, min(1, min(pxq[1], pxq[2])))
    q_hi <- max(0, min(1, max(pxq[1], pxq[2])))
    xr <- stats::quantile(data_imp[[Index]], probs = c(q_lo, q_hi), na.rm = TRUE, names = FALSE)
    keep <- is.finite(data_imp[[Index]]) &
      data_imp[[Index]] >= xr[1] & data_imp[[Index]] <= xr[2]
    if (sum(keep) >= 30L) {
      plot_data <- data_imp[keep, , drop = FALSE]
      cli::cli_alert_info(
        "RCS 作图 x 限制在 P{round(q_lo*100)}–P{round(q_hi*100)}: [{format(xr[1], digits=4)}, {format(xr[2], digits=4)}] (n_plot={nrow(plot_data)}/{nrow(data_imp)})"
      )
    } else {
      cli::cli_alert_warning("plot_x_quantiles 过滤后样本过少，仍用全样本作图")
    }
  }

  CrudeFactors <- .rci01_parse_factors(ri_cfg$crude_factors %||% character(0))
  CrudeFactors <- setdiff(intersect(CrudeFactors, names(data_imp)), Index)
  crude_rhs <- if (length(CrudeFactors)) paste(CrudeFactors, collapse = "+") else NULL
  resA <- .rci01_fit_panel(data_imp, Index, nk, covar_rhs = crude_rhs)
  var_names1 <- paste(Model1Factors, collapse = "+")
  resB <- .rci01_fit_panel(data_imp, Index, nk, covar_rhs = var_names1)
  var_names2 <- paste(Model2Factors, collapse = "+")
  resC <- .rci01_fit_panel(data_imp, Index, nk, covar_rhs = var_names2)
  resD <- if (length(Model3Factors)) {
    var_names3 <- paste(Model3Factors, collapse = "+")
    .rci01_fit_panel(data_imp, Index, nk, covar_rhs = var_names3)
  } else {
    NULL
  }

  if (!exists(".pub_figure_extract_lrm_anova_p", mode = "function") ||
      !exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    candidates <- unique(c(
      file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R/pub_figure_export.R"),
      file.path(ctx$config$project$root %||% "", "R/pub_figure_export.R"),
      file.path(getwd(), "R/pub_figure_export.R")
    ))
    candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
    if (length(candidates)) source(candidates[[1L]], local = FALSE)
  }
  if (!exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    stop("rcs_incidence: 缺少 .pub_figure_rcs_panel_vline_cutoffs（请 source R/pub_figure_export.R）",
         call. = FALSE)
  }
  show_cut_c <- !identical(cutoff_vline_mode, "none") &&
    (!length(Model3Factors) || !isTRUE(m3_sig))
  show_cut_d <- !identical(cutoff_vline_mode, "none") &&
    length(Model3Factors) && isTRUE(m3_sig)
  .panel_from_res <- function(res, show_cuts = FALSE, panel = NULL) {
    pe <- .pub_figure_extract_lrm_anova_p(res$an)
    p_ov <- pe$p_overall
    if (exists("pipeline_rcs_p_overall_source", mode = "function") &&
        exists("pipeline_logistic_table2_trend_p", mode = "function") &&
        !is.null(panel) &&
        identical(pipeline_rcs_p_overall_source(cfg, ri_cfg), "table2_trend")) {
      pt <- if (exists("pipeline_rcs_table2_trend_p", mode = "function")) {
        pipeline_rcs_table2_trend_p(ctx, panel)
      } else {
        pipeline_logistic_table2_trend_p(ctx, panel)
      }
      if (!is.finite(pt) && exists("pipeline_rcs_incidence_trend_p", mode = "function")) {
        covs <- switch(panel,
          crude = character(0),
          model1 = Model1Factors,
          model2 = Model2Factors,
          model3 = Model3Factors,
          character(0)
        )
        pt <- pipeline_rcs_incidence_trend_p(
          data_imp, covs, Index, "Disease"
        )
      }
      if (is.finite(pt)) p_ov <- pt
    }
    cuts <- .pub_figure_rcs_panel_vline_cutoffs(
      res$cutoffs, show_cuts, cutoff_vline_mode
    )
    list(
      p_overall = p_ov,
      p_nonlinear = pe$p_nonlinear,
      cutoffs = cuts
    )
  }
  .rci01_panel_p_overall <- function(panel) {
    if (!identical(pipeline_rcs_p_overall_source(cfg, ri_cfg), "table2_trend")) {
      return(NULL)
    }
    # 直接从磁盘读 Table 2 trend P
    if (exists("pipeline_logistic_table2_read_from_disk", mode = "function") &&
        exists("pipeline_logistic_table2_trend_p_from_tb", mode = "function")) {
      tb <- tryCatch(pipeline_logistic_table2_read_from_disk(ctx), error = function(e) NULL)
      if (!is.null(tb)) {
        pv <- tryCatch(pipeline_logistic_table2_trend_p_from_tb(tb, panel), error = function(e) NA_real_)
        if (is.finite(pv)) return(pv)
      }
    }
    # 从 ctx$results 读
    tp <- tryCatch(ctx[["results"]][["logistic_table2_trend_p"]], error = function(e) NULL)
    if (!is.null(tp) && is.list(tp)) {
      pv <- suppressWarnings(as.numeric(tp[[panel]]))
      if (length(pv) > 0 && is.finite(pv[1])) return(pv[1])
    }
    # 从数据算
    if (!is.finite(pv)) {
      covs <- switch(panel,
        crude = character(0),
        model1 = Model1Factors,
        model2 = Model2Factors,
        model3 = Model3Factors,
        character(0)
      )
      pt <- pipeline_rcs_incidence_trend_p(data_imp, covs, Index, "Disease")
      if (is.finite(pt)) return(pt)
    }
    NULL
  }
  if (identical(pipeline_rcs_p_overall_source(cfg, ri_cfg), "table2_trend")) {
    pts <- c(
      if (exists("pipeline_rcs_table2_trend_p", mode = "function")) {
        pipeline_rcs_table2_trend_p(ctx, "crude")
      } else {
        pipeline_logistic_table2_trend_p(ctx, "crude")
      },
      if (exists("pipeline_rcs_table2_trend_p", mode = "function")) {
        pipeline_rcs_table2_trend_p(ctx, "model1")
      } else {
        pipeline_logistic_table2_trend_p(ctx, "model1")
      },
      if (exists("pipeline_rcs_table2_trend_p", mode = "function")) {
        pipeline_rcs_table2_trend_p(ctx, "model2")
      } else {
        pipeline_logistic_table2_trend_p(ctx, "model2")
      }
    )
    if (!any(is.finite(pts))) {
      pts <- c(
        .rci01_panel_p_overall("crude") %||% NA_real_,
        .rci01_panel_p_overall("model1") %||% NA_real_,
        .rci01_panel_p_overall("model2") %||% NA_real_
      )
    }
    if (any(is.finite(pts))) {
      cli::cli_alert_info(
        "rcs_incidence: P for overall ← Table 2 trend: Crude={pts[1]}, M1={pts[2]}, M2={pts[3]}"
      )
    } else {
      cli::cli_alert_warning("rcs_incidence: table2_trend 对齐失败，仍用样条联合检验 P。")
    }
  }
  ctx$results$rcs_incidence_panel_stats <- list(
    Crude  = .panel_from_res(resA, FALSE, "crude"),
    Model1 = .panel_from_res(resB, FALSE, "model1"),
    Model2 = .panel_from_res(resC, show_cut_c, "model2")
  )
  if (!is.null(resD)) {
    ctx$results$rcs_incidence_panel_stats$Model3 <- .panel_from_res(resD, show_cut_d)
  }

  xlab_disp <- if (exists("pipeline_plot_axis_label", mode = "function")) {
    pipeline_plot_axis_label(Index, cfg)
  } else {
    gsub("_", " ", as.character(Index)[1L], fixed = TRUE)
  }
  title_A <- if (length(CrudeFactors)) {
    paste0("A.Crude (+", paste(CrudeFactors, collapse = "+"), ")")
  } else {
    "A.Crude Model"
  }
  x_plot_range <- range(plot_data[[Index]], na.rm = TRUE)
  plot_A <- .rci01_ggrcs_panel(
    plot_data, resA$fit, Index, selected_colors3, resA$an, resA$out,
    title_A, resA$cutoffs, histbin = histbin, plot_ff = plot_ff,
    cutoff_label_digits = cutoff_label_digits, show_cutoff_lines = FALSE,
    xlab_display = xlab_disp,
    ylim = ri_cfg$ylim, y_min = ri_cfg$y_min, y_max = ri_cfg$y_max,
    ylim_force = isTRUE(ri_cfg$ylim_force),
    config = cfg, x_range = x_plot_range,
    p_overall = .rci01_panel_p_overall("crude")
  )
  plot_B <- .rci01_ggrcs_panel(
    plot_data, resB$fit, Index, selected_colors3, resB$an, resB$out,
    "B.Model 1", resB$cutoffs, histbin = histbin, plot_ff = plot_ff,
    cutoff_label_digits = cutoff_label_digits, show_cutoff_lines = FALSE,
    xlab_display = xlab_disp,
    ylim = ri_cfg$ylim, y_min = ri_cfg$y_min, y_max = ri_cfg$y_max,
    ylim_force = isTRUE(ri_cfg$ylim_force),
    config = cfg, x_range = x_plot_range,
    p_overall = .rci01_panel_p_overall("model1")
  )
  plot_C <- .rci01_ggrcs_panel(
    plot_data, resC$fit, Index, selected_colors3, resC$an, resC$out,
    "C.Model 2", resC$cutoffs, histbin = histbin, plot_ff = plot_ff,
    cutoff_label_digits = cutoff_label_digits, show_cutoff_lines = show_cut_c,
    cutoff_vline_mode = cutoff_vline_mode,
    xlab_display = xlab_disp,
    ylim = ri_cfg$ylim, y_min = ri_cfg$y_min, y_max = ri_cfg$y_max,
    ylim_force = isTRUE(ri_cfg$ylim_force),
    config = cfg, x_range = x_plot_range,
    p_overall = .rci01_panel_p_overall("model2")
  )
  plot_D <- if (!is.null(resD)) {
    .rci01_ggrcs_panel(
      plot_data, resD$fit, Index, selected_colors3, resD$an, resD$out,
      "D.Model 3", resD$cutoffs, histbin = histbin, plot_ff = plot_ff,
      cutoff_label_digits = cutoff_label_digits, show_cutoff_lines = show_cut_d,
      cutoff_vline_mode = cutoff_vline_mode,
      xlab_display = xlab_disp,
      ylim = ri_cfg$ylim, y_min = ri_cfg$y_min, y_max = ri_cfg$y_max,
      ylim_force = isTRUE(ri_cfg$ylim_force),
      config = cfg, x_range = x_plot_range
    )
  } else {
    NULL
  }

  if (!requireNamespace("patchwork", quietly = TRUE)) {
    stop("rcs_incidence: 需要 patchwork 包用于拼图。")
  }
  suppressPackageStartupMessages(library(patchwork, warn.conflicts = FALSE))

  comb_pack <- if (exists("pipeline_rcs_patchwork", mode = "function")) {
    rcs_panels <- list(crude = plot_A, model1 = plot_B, model2 = plot_C, model3 = plot_D)
    if (exists("pipeline_rcs_select_plot_panels", mode = "function")) {
      rcs_panels <- pipeline_rcs_select_plot_panels(rcs_panels, ri_cfg)
    }
    pipeline_rcs_patchwork(rcs_panels)
  } else {
    list(
      plot = plot_A + plot_B + plot_C + patchwork::plot_layout(nrow = 1),
      width = 15, height = 5
    )
  }
  combined_plot <- comb_pack$plot
  fig_w <- comb_pack$width
  fig_h <- comb_pack$height

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  fig_caption <- paste0(
    "RCS of ", pipeline_index_display_name(cfg, Index), " and ", Disease
  )
  fig_stem <- if (!is.null(ri_cfg$figure_filename) && nzchar(ri_cfg$figure_filename)) {
    ri_cfg$figure_filename
  } else {
    fig_no <- suppressWarnings(as.integer(ri_cfg$figure_number %||% NA_integer_)[1L])
    fig_kind <- as.character(ri_cfg$figure_kind %||% "main_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "main_figure"
    if (is.finite(fig_no) && fig_no >= 1L &&
        exists("pub_figure_filepath_at", mode = "function")) {
      basename(pub_figure_filepath_at(
        fig_dir, fig_no, fig_caption, ext = "pdf",
        bump_counter = isTRUE(ri_cfg$bump_counter %||% TRUE),
        kind = fig_kind
      ))
    } else {
      pub_figure_file(ctx, fig_kind, fig_caption)
    }
  }
  fig_path <- file.path(fig_dir, fig_stem)
  if (exists(".pub_figure_filename", mode = "function")) {
    fig_path <- file.path(fig_dir, .pub_figure_filename(
      .inject_db_into_pub_label(fig_stem, sanitize_for_file = TRUE)
    ))
  }
  if (exists(".pub_path_with_slot_label", mode = "function")) {
    fig_path <- .pub_path_with_slot_label(ctx, fig_path)
  }

  if (exists("pipeline_ggsave_pdf", mode = "function")) {
    pipeline_ggsave_pdf(
      fig_path, combined_plot, width = fig_w, height = fig_h, family = plot_ff, cfg = cfg
    )
  } else {
    ggplot2::ggsave(
      filename = fig_path,
      height = fig_h, width = fig_w,
      plot = combined_plot,
      device = function(filename, width, height, ...) {
        grDevices::cairo_pdf(filename, width = width, height = height, family = plot_ff)
      }
    )
  }
  cli::cli_alert_success("Saved: {basename(fig_path)}")
  mirror_pub_output_to_root(ctx, fig_path)

  cutoffs_m2 <- resC$cutoffs
  cutoffs_m3 <- if (!is.null(resD)) resD$cutoffs else NULL
  cut_use <- if (isTRUE(m3_sig) && !is.null(cutoffs_m3) && length(cutoffs_m3$all)) {
    cutoffs_m3
  } else {
    cutoffs_m2
  }
  cutoff <- .rci01_primary_cutoff(cut_use)
  # Table S-XX / logistic_*_glm_rcs 需要二分：默认只用 primary cutoff
  # （ELSA/HRS 往往只有 1 个 OR=1 → 碰巧已是 2 组；CHARLS/Pooled 多交点时若用 all 会变成 3–4 组）
  ri_cfg <- cfg$rcs_incidence %||% list()
  group_mode <- tolower(as.character(ri_cfg$group_cutoffs %||% "primary")[1L])
  group_cuts <- if (identical(group_mode, "all")) {
    cut_use$all
  } else {
    if (is.finite(cutoff)) cutoff else cut_use$all
  }
  group_info <- .rci01_cutoff_factor(data_imp[[Index]], group_cuts, Index)
  data_imp[[group_info$col_name]] <- group_info$factor

  if (!is.null(ctx$data$imputed) && is.data.frame(ctx$data$imputed)) {
    ctx$data$imputed <- .rci01_add_group_column(ctx$data$imputed, Index, group_cuts)
  }
  if (!is.null(ctx$data$cleaned) && is.data.frame(ctx$data$cleaned)) {
    ctx$data$cleaned <- .rci01_add_group_column(ctx$data$cleaned, Index, group_cuts)
  }

  ctx$results$rcs_cutoff <- cutoff
  ctx$results$rcs_cutoff_index <- Index
  ctx$results$rcs_cutoff_or1 <- cut_use$or1
  ctx$results$rcs_cutoff_slope_zero <- cut_use$slope_zero
  ctx$results$rcs_cutoffs_all <- cut_use$all
  ctx$results$rcs_group_cutoffs_mode <- group_mode
  ctx$results$rcs_group_cutoffs_used <- group_cuts
  ctx$results$rcs_cutoff_group_col <- group_info$col_name
  ctx$results$rcs_cutoff_group_labels <- group_info$labels
  ctx$results$rcs_incidence_grouped_data <- data_imp
  ctx$results$cutoff_value <- cutoff
  ctx$results$cutoff_variable <- Index
  ctx$results$rcs_incidence_nk <- nk
  ctx$results$rcs_incidence_res_crude <- resA
  ctx$results$rcs_incidence_res_model1 <- resB
  ctx$results$rcs_incidence_res_model2 <- resC
  ctx$results$rcs_incidence_res_model3 <- resD
  ctx$results$rcs_incidence_crude_factors <- CrudeFactors
  ctx$results$rcs_incidence_model1_factors <- Model1Factors
  ctx$results$rcs_incidence_model2_factors <- Model2Factors
  ctx$results$rcs_incidence_model3_factors <- Model3Factors
  ctx$results$rcs_incidence_figure <- fig_path

  cutoff_detail <- data.frame(
    index = Index,
    type = c(
      rep("or1", length(cut_use$or1)),
      rep("peak_or", length(cut_use$peak))
    ),
    cutoff = c(cut_use$or1, cut_use$peak),
    stringsAsFactors = FALSE
  )
  if (nrow(cutoff_detail)) {
    cutoff_detail <- cutoff_detail[order(cutoff_detail$cutoff), , drop = FALSE]
  }

  # 勿用 key "rcs_cutoff"：上面已写入 primary 标量；CSV 明细另存，避免覆盖
  ctx <- save_result(
    ctx, "rcs_cutoff_detail",
    cutoff_detail,
    paste0("cutoff_", Index, ".csv")
  )
  # 再次钉死 primary，防止其它步骤误覆盖
  ctx$results$rcs_cutoff <- cutoff
  ctx$results$cutoff_value <- cutoff

  group_counts <- as.data.frame(
    table(data_imp[[group_info$col_name]], useNA = "ifany"),
    stringsAsFactors = FALSE
  )
  names(group_counts) <- c("group", "n")
  group_counts$index <- Index
  group_counts$cutoffs <- paste(.rci01_format_cutoff(cut_use$all), collapse = "; ")

  ctx <- save_result(
    ctx, "rcs_cutoff_groups",
    group_counts,
    paste0("rcs_cutoff_groups_", Index, ".csv")
  )

  or1_txt <- if (length(cut_use$or1)) {
    paste(.rci01_format_cutoff(cut_use$or1), collapse = ", ")
  } else {
    "none"
  }
  slope_txt <- if (length(cut_use$peak)) {
    paste(.rci01_format_cutoff(cut_use$peak), collapse = ", ")
  } else {
    "none"
  }
  cli::cli_alert_info("RCS cutoffs — OR=1: {or1_txt}; peak OR: {slope_txt}")
  cli::cli_alert_info(
    "分组 {group_info$col_name}: {group_info$n_groups} 组（mode={group_mode}）— {paste(group_info$labels, collapse = ' | ')}"
  )
  primary_txt <- if (is.finite(cutoff)) as.character(cutoff) else "NA"
  if (identical(group_mode, "primary") && group_info$n_groups != 2L) {
    cli::cli_alert_warning(
      "group_cutoffs=primary 但得到 {group_info$n_groups} 组（期望 2）。primary cutoff={primary_txt}；请检查 RCS 曲线。"
    )
  }
  if (identical(group_mode, "all") && group_info$n_groups > 2L) {
    cli::cli_alert_warning(
      "group_cutoffs=all → {group_info$n_groups} 组；Table S-XX / logistic_*_glm_rcs 应改用 primary（二分）。"
    )
  }
  cli::cli_alert_success(
    "rcs_incidence 完成（primary cutoff = {primary_txt}，共 {length(cut_use$all)} 个 cutoff 可标在图上；分组用 {group_mode}）"
  )
  ctx
}

register_block(
  "rcs_incidence",
  block_rcs_incidence,
  "发病 Logistic RCS：有 Model3 时 2×2，否则 ggrcs 横排 ABC"
)
