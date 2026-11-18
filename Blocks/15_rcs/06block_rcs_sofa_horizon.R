###############################################################################
#  rcs_sofa_horizon — Jin Fig1：SOFA 二分 × 院内/30d/365d 的 2×3 Cox RCS
#
#  原文版式：上排 High SOFA、下排 Low SOFA；列 = In-hospital / 30-day / 365-day；
#  面板内：暴露直方图（右轴 Frequency%）+ HR 曲线与 95%CI + HR=1 虚线 + Nonlinear P。
#
#  register_block: "rcs_sofa_horizon"
#  须在 derived_grouping 之后（需 SOFA_bin）；多时点列用 futime_*/event_* 或 time_d*/event_d*
#
#  config$rcs_sofa_horizon = list(
#    enable = TRUE,
#    index_var = NULL,              # NULL → survival$index_var
#    sofa_bin_var = "SOFA_bin",
#    high_level = "High",
#    low_level  = "Low",
#    horizons = c("hosp", "d30", "d365"),
#    nk = 4L,                       # 固定结点数（与原文 RCS 风格接近）；也可 nk_range=3:5
#    model = "crude",               # crude | model1 | model2
#    figure_number = 1L,
#    figure_kind = "main_figure",
#    plot_x_quantiles = c(0.01, 0.99), # 拟合仍用全样本；作图横轴/直方图裁到层内分位（防尾部极值撑轴）
#    xlim = NULL, ylim = NULL         # 显式 xlim 优先于 plot_x_quantiles
#  )
###############################################################################

.rsh06_cfg <- function(cfg) {
  top <- cfg$rcs_sofa_horizon %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$rcs_sofa_horizon %||% list()
}

.rsh06_fmt_p <- function(pv) {
  pv <- suppressWarnings(as.numeric(pv)[1L])
  if (!is.finite(pv)) return("NA")
  if (pv < 0.0001) return("<0.0001")
  if (pv < 0.001) return(formatC(pv, digits = 4, format = "f"))
  formatC(pv, digits = 3, format = "f")
}

.rsh06_horizon_specs <- function(data, mh_cfg = list()) {
  list(
    hosp = list(
      label = "In-hospital mortality",
      time = (mh_cfg$hosp %||% list())$time %||%
        if ("futime" %in% names(data)) "futime" else "futime",
      event = (mh_cfg$hosp %||% list())$event %||%
        if ("fustatus" %in% names(data)) "fustatus" else "fustatus"
    ),
    d30 = list(
      label = "30-day mortality",
      time = (mh_cfg$d30 %||% list())$time %||%
        if ("futime_30d" %in% names(data)) "futime_30d" else
          if ("time_d30" %in% names(data)) "time_d30" else "futime_30d",
      event = (mh_cfg$d30 %||% list())$event %||%
        if ("event_30d" %in% names(data)) "event_30d" else
          if ("event_d30" %in% names(data)) "event_d30" else "event_30d"
    ),
    d365 = list(
      label = "365-day mortality",
      time = (mh_cfg$d365 %||% list())$time %||%
        if ("futime_365d" %in% names(data)) "futime_365d" else
          if ("time_d365" %in% names(data)) "time_d365" else "futime_365d",
      event = (mh_cfg$d365 %||% list())$event %||%
        if ("event_365d" %in% names(data)) "event_365d" else
          if ("event_d365" %in% names(data)) "event_d365" else "event_365d"
    )
  )
}

.rsh06_fit_panel <- function(rt, index_var, time_var, event_var, nk, covs = character(0),
                             x_min = NULL, x_max = NULL) {
  need <- c(index_var, time_var, event_var, covs)
  if (!all(need %in% names(rt))) return(NULL)
  d <- rt[, need, drop = FALSE]
  d[[time_var]] <- suppressWarnings(as.numeric(d[[time_var]]))
  d[[event_var]] <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  d[[index_var]] <- suppressWarnings(as.numeric(d[[index_var]]))
  ok <- stats::complete.cases(d) & is.finite(d[[time_var]]) & d[[time_var]] > 0 &
    is.finite(d[[index_var]])
  d <- d[ok, , drop = FALSE]
  if (nrow(d) < 30L || length(unique(d[[event_var]])) < 2L) return(NULL)
  if (diff(range(d[[index_var]], na.rm = TRUE)) <= 0) return(NULL)

  rhs <- paste0("rcspline.eval(", index_var, ", nk = ", as.integer(nk)[1L], ", inclx = TRUE)")
  if (length(covs)) rhs <- paste(c(rhs, covs), collapse = " + ")
  fml <- stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs))
  fit <- tryCatch(survival::coxph(fml, data = d, x = TRUE), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  fit$call$formula <- fml

  hr1 <- tryCatch(smoothHR::smoothHR(data = d, coxfit = fit), error = function(e) NULL)
  if (is.null(hr1)) return(NULL)
  ref <- stats::median(d[[index_var]], na.rm = TRUE)
  xmin_data <- min(d[[index_var]], na.rm = TRUE)
  xmax_data <- max(d[[index_var]], na.rm = TRUE)
  ## 作图窗口：显式 x_min/x_max（常来自层内 plot_x_quantiles）；拟合仍用全样本 d
  xmin <- xmin_data
  xmax <- xmax_data
  if (!is.null(x_min) && is.finite(as.numeric(x_min)[1L])) {
    xmin <- max(xmin_data, as.numeric(x_min)[1L])
  }
  if (!is.null(x_max) && is.finite(as.numeric(x_max)[1L])) {
    xmax <- min(xmax_data, as.numeric(x_max)[1L])
  }
  if (!is.finite(xmin) || !is.finite(xmax) || xmax <= xmin) {
    xmin <- xmin_data
    xmax <- xmax_data
  }
  span <- xmax - xmin
  pad <- if (is.finite(span) && span > 0) max(span * 1e-9, .Machine$double.eps * 100) else 0
  pv <- seq(xmin + pad, xmax - pad, length.out = 400L)
  pred <- tryCatch(
    as.data.frame(stats::predict(
      hr1, predictor = index_var, pred.value = ref, prob = 0.5,
      prediction.values = pv, conf.level = 0.95
    )),
    error = function(e) NULL
  )
  if (is.null(pred) || !nrow(pred)) return(NULL)
  psum <- tryCatch(summary(hr1$coxfit), error = function(e) NULL)
  pe <- tryCatch({
    if (exists(".pub_figure_extract_cox_rcs_p", mode = "function") && !is.null(psum)) {
      .pub_figure_extract_cox_rcs_p(psum)
    } else {
      coef_m <- tryCatch(as.matrix(psum$coefficients), error = function(e) NULL)
      list(
        p_overall = tryCatch(
          suppressWarnings(as.numeric(psum$logtest[3L]))[1L],
          error = function(e) NA_real_
        ),
        p_nonlinear = if (!is.null(coef_m) && nrow(coef_m) >= 2L && ncol(coef_m) >= 5L) {
          suppressWarnings(as.numeric(coef_m[2L, 5L]))[1L]
        } else {
          NA_real_
        }
      )
    }
  }, error = function(e) list(p_overall = NA_real_, p_nonlinear = NA_real_))
  list(
    data = d,
    pred = pred,
    ref = ref,
    p_nonlinear = pe$p_nonlinear,
    p_overall = pe$p_overall,
    x_lim = c(xmin, xmax),
    n = nrow(d),
    events = sum(d[[event_var]] == 1L, na.rm = TRUE)
  )
}

.rsh06_draw_panel <- function(fit, index_lab, panel_letter, title_main,
                              xlim = NULL, ylim = NULL,
                              hist_col = "#F4A6A6", curve_col = "#1F3A5F",
                              plot_ff = "serif") {
  if (is.null(fit)) {
    plot.new()
    title(main = paste0(panel_letter, "  ", title_main), adj = 0, cex.main = 1)
    text(0.5, 0.5, "Not estimable", cex = 1.1)
    return(invisible(NULL))
  }
  pred <- fit$pred
  if (is.null(pred) || !is.data.frame(pred) || !nrow(pred) || !ncol(pred)) {
    plot.new()
    title(main = paste0(panel_letter, "  ", title_main), adj = 0, cex.main = 1)
    text(0.5, 0.5, "Not estimable", cex = 1.1)
    return(invisible(NULL))
  }
  x <- as.numeric(pred[[1L]])
  ln <- if ("LnHR" %in% names(pred)) as.numeric(pred$LnHR) else as.numeric(pred[[2L]])
  lo_nm <- grep("^lower", names(pred), value = TRUE)[1L]
  hi_nm <- grep("^upper", names(pred), value = TRUE)[1L]
  lo <- if (!is.na(lo_nm)) as.numeric(pred[[lo_nm]]) else rep(NA_real_, length(x))
  hi <- if (!is.na(hi_nm)) as.numeric(pred[[hi_nm]]) else rep(NA_real_, length(x))
  hr <- exp(ln); lo_hr <- exp(lo); hi_hr <- exp(hi)

  xl <- xlim
  if (is.null(xl) || length(xl) < 2L || !all(is.finite(xl))) xl <- fit$x_lim
  yl <- ylim
  finite_y <- c(hr, lo_hr, hi_hr)
  finite_y <- finite_y[is.finite(finite_y) & finite_y > 0]
  if (is.null(yl) || length(yl) < 2L || !all(is.finite(yl))) {
    q95 <- if (length(finite_y)) as.numeric(stats::quantile(finite_y, 0.95, na.rm = TRUE)) else 5
    yl <- c(0, max(2, q95 * 1.15, na.rm = TRUE))
  }

  ## 直方图（Frequency %）— 与原文红柱风格接近；仅计入作图横轴窗口内
  ## fit$data 列顺序 = need；第一列是 index（见 .rsh06_fit_panel）
  xv <- suppressWarnings(as.numeric(fit$data[[1L]]))
  xv <- xv[is.finite(xv) & xv >= xl[1L] & xv <= xl[2L]]
  br <- seq(xl[1L], xl[2L], length.out = 31L)
  h <- graphics::hist(xv, breaks = br, plot = FALSE)
  freq_pct <- 100 * h$counts / max(1, sum(h$counts))
  freq_max <- max(freq_pct, na.rm = TRUE)
  if (!is.finite(freq_max) || freq_max <= 0) freq_max <- 1

  graphics::par(mar = c(4.2, 4.2, 2.8, 3.8), family = plot_ff)
  graphics::plot(
    NA, xlim = xl, ylim = yl, xaxs = "i", yaxs = "i",
    xlab = index_lab, ylab = "Hazard Ratio (HR)",
    main = paste0(panel_letter, "  ", title_main),
    cex.main = 1.05, font.main = 2
  )
  ## 直方图映射到 HR 轴上半高度的约 35%
  hist_top <- yl[1L] + (yl[2L] - yl[1L]) * 0.38
  y_hist <- yl[1L] + freq_pct / freq_max * (hist_top - yl[1L])
  graphics::rect(
    h$breaks[-length(h$breaks)], yl[1L],
    h$breaks[-1L], y_hist,
    col = hist_col, border = NA
  )
  ## CI 带
  ok <- is.finite(x) & is.finite(hr) & is.finite(lo_hr) & is.finite(hi_hr)
  if (any(ok)) {
    graphics::polygon(
      c(x[ok], rev(x[ok])),
      c(pmin(hi_hr[ok], yl[2L]), rev(pmax(lo_hr[ok], yl[1L]))),
      col = grDevices::adjustcolor(curve_col, alpha.f = 0.18), border = NA
    )
    graphics::lines(x[ok], hr[ok], col = curve_col, lwd = 2.2)
  }
  graphics::abline(h = 1, lty = 2, col = "grey50", lwd = 1.2)
  if (is.finite(fit$ref) && fit$ref >= xl[1L] && fit$ref <= xl[2L]) {
    graphics::points(fit$ref, 1, pch = 16, cex = 0.9, col = curve_col)
  }
  ## Nonlinear P（原文右下；须在右轴 overlay 之前，坐标仍是 HR）
  lab <- paste0("Nonlinear P-value: ", .rsh06_fmt_p(fit$p_nonlinear))
  graphics::legend("bottomright", legend = lab, bty = "n", cex = 0.85, text.col = "grey20")
  ## 右轴 Frequency %
  graphics::par(new = TRUE)
  graphics::plot(
    NA, xlim = xl, ylim = c(0, freq_max * 1.15), axes = FALSE, xlab = "", ylab = "",
    xaxs = "i", yaxs = "i"
  )
  graphics::axis(4, col.axis = "grey40", cex.axis = 0.8)
  graphics::mtext("Frequency, %", side = 4, line = 2.2, cex = 0.85, col = "grey40")
  invisible(NULL)
}

block_rcs_sofa_horizon <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    library(smoothHR)
    library(Hmisc)
  })
  ## 助手
  .cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(ctx$config$project$root %||% "")[1L],
    getwd()
  ))
  for (.r in .cands[nzchar(as.character(.cands))]) {
    for (.rel in c("R/pub_figure_export.R", "R/literature_jin_index_sofa.R")) {
      .p <- file.path(.r, .rel)
      if (file.exists(.p)) try(source(.p, local = FALSE), silent = TRUE)
    }
  }

  cfg <- ctx$config
  bl <- .rsh06_cfg(cfg)
  if (!is.null(bl$enable) && !isTRUE(bl$enable)) {
    cli::cli_alert_info("rcs_sofa_horizon: enable=FALSE，跳过")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    stop("rcs_sofa_horizon: 无分析数据", call. = FALSE)
  }
  if (exists("jin_ensure_horizon_columns", mode = "function")) {
    .db_hz <- tolower(as.character(cfg$dual_db$current_db %||% cfg$project$database %||% "mimic")[1L])
    if (grepl("eicu", .db_hz)) .db_hz <- "eicu" else .db_hz <- "mimic"
    data <- jin_ensure_horizon_columns(data, db = .db_hz)
  }

  index_var <- as.character(
    bl$index_var %||% cfg$survival$index_var %||% cfg$incidence$index_var %||%
      ctx$results$derived_grouping$index_var %||% ""
  )[1L]
  if (!nzchar(index_var) || !index_var %in% names(data)) {
    stop("rcs_sofa_horizon: index_var 不存在: ", index_var, call. = FALSE)
  }
  sofa_bin <- as.character(
    bl$sofa_bin_var %||% ctx$results$derived_grouping$sofa_bin_var %||% "SOFA_bin"
  )[1L]
  if (!sofa_bin %in% names(data)) {
    stop("rcs_sofa_horizon: 缺 SOFA 二分列 ", sofa_bin, "（请先跑 derived_grouping）", call. = FALSE)
  }

  high_lv <- as.character(bl$high_level %||% "High")[1L]
  low_lv <- as.character(bl$low_level %||% "Low")[1L]
  data[[sofa_bin]] <- as.character(data[[sofa_bin]])
  ## 兼容其它标签
  if (!any(data[[sofa_bin]] %in% c(high_lv, low_lv), na.rm = TRUE)) {
    u <- unique(stats::na.omit(data[[sofa_bin]]))
    if (length(u) >= 2L) {
      ## 尝试按 SOFA 均值判断高低
      sofa_raw <- ctx$results$derived_grouping$sofa_var %||% "SOFA"
      if (sofa_raw %in% names(data)) {
        mu <- tapply(as.numeric(data[[sofa_raw]]), data[[sofa_bin]], mean, na.rm = TRUE)
        high_lv <- names(mu)[which.max(mu)]
        low_lv <- names(mu)[which.min(mu)]
      } else {
        high_lv <- u[[length(u)]]
        low_lv <- u[[1L]]
      }
      cli::cli_alert_info("rcs_sofa_horizon: 自动映射 High={high_lv}, Low={low_lv}")
    }
  }

  mh <- cfg$cox_multi_horizon %||% list()
  hspecs <- .rsh06_horizon_specs(data, mh)
  want <- as.character(bl$horizons %||% c("hosp", "d30", "d365"))
  want <- intersect(want, names(hspecs))
  if (!length(want)) stop("rcs_sofa_horizon: 无可用 horizon", call. = FALSE)

  nk <- suppressWarnings(as.integer(bl$nk %||% 4L)[1L])
  if (!is.finite(nk) || nk < 3L) nk <- 4L
  model <- tolower(as.character(bl$model %||% "crude")[1L])
  covs <- character(0)
  if (identical(model, "model1")) {
    covs <- as.character(bl$model1_factors %||% ctx$results$Model1Factors %||% c("Age", "Gender"))
  } else if (identical(model, "model2")) {
    covs <- as.character(bl$model2_factors %||% ctx$results$Model2Factors %||% c("Age", "Gender"))
  }
  covs <- intersect(setdiff(covs, c(index_var, sofa_bin)), names(data))

  row_levels <- c(high_lv, low_lv)
  row_labs <- c("High SOFA", "Low SOFA")
  letters_mat <- matrix(LETTERS[1:6], nrow = 2, ncol = 3, byrow = TRUE)

  ## 横轴：config$xlim 优先；否则层内 plot_x_quantiles（默认 P1–P99）
  xlim_cfg <- bl$xlim
  use_fixed_xlim <- !is.null(xlim_cfg) && length(xlim_cfg) >= 2L &&
    all(is.finite(as.numeric(xlim_cfg[1:2])))
  pq <- suppressWarnings(as.numeric(bl$plot_x_quantiles %||% c(0.01, 0.99)))
  if (!use_fixed_xlim && length(pq) >= 2L && all(is.finite(pq[1:2])) &&
      pq[2L] > pq[1L] && pq[1L] >= 0 && pq[2L] <= 1) {
    cli::cli_alert_info(
      "rcs_sofa_horizon: 作图横轴 = 层内 P{round(100 * pq[1L])}–P{round(100 * pq[2L])}（拟合仍用全样本）"
    )
  } else if (!use_fixed_xlim) {
    pq <- numeric(0)
  }

  fits <- vector("list", 6L)
  k <- 0L
  for (ri in seq_along(row_levels)) {
    for (hi in seq_along(want)) {
      k <- k + 1L
      sp <- hspecs[[want[[hi]]]]
      sub <- data[data[[sofa_bin]] == row_levels[[ri]], , drop = FALSE]
      x_min_i <- NULL
      x_max_i <- NULL
      if (use_fixed_xlim) {
        x_min_i <- as.numeric(xlim_cfg[1L])
        x_max_i <- as.numeric(xlim_cfg[2L])
      } else if (length(pq) >= 2L && index_var %in% names(sub)) {
        qs <- as.numeric(stats::quantile(
          suppressWarnings(as.numeric(sub[[index_var]])),
          probs = pq[1:2], na.rm = TRUE, names = FALSE
        ))
        if (all(is.finite(qs)) && qs[2L] > qs[1L]) {
          x_min_i <- qs[1L]
          x_max_i <- qs[2L]
        }
      }
      fits[[k]] <- tryCatch(
        .rsh06_fit_panel(
          sub, index_var, sp$time, sp$event, nk, covs,
          x_min = x_min_i, x_max = x_max_i
        ),
        error = function(e) {
          cli::cli_alert_warning(
            "rcs_sofa_horizon: {row_labs[[ri]]} × {sp$label} 拟合失败: {conditionMessage(e)}"
          )
          NULL
        }
      )
      if (is.null(fits[[k]])) {
        cli::cli_alert_warning(
          "rcs_sofa_horizon: 跳过 {row_labs[[ri]]} × {sp$label}（不可估）"
        )
      } else {
        cli::cli_alert_info(
          "{row_labs[[ri]]} × {want[[hi]]}: n={fits[[k]]$n}, events={fits[[k]]$events}, P-nl={(.rsh06_fmt_p(fits[[k]]$p_nonlinear))}, x=[{round(fits[[k]]$x_lim[1], 3)}, {round(fits[[k]]$x_lim[2], 3)}]"
        )
      }
    }
  }

  index_lab <- if (exists("pipeline_index_display_name", mode = "function")) {
    pipeline_index_display_name(cfg, index_var)
  } else index_var
  disease <- as.character(cfg$project$disease %||% "Sepsis")[1L]
  fig_caption <- paste0(
    "RCS of ", index_lab, " by SOFA and mortality horizon in ", disease
  )
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  fig_no <- suppressWarnings(as.integer(bl$figure_number %||% 1L)[1L])
  fig_kind <- as.character(bl$figure_kind %||% "main_figure")[1L]
  outfile <- if (is.finite(fig_no) && exists("pub_figure_filepath_at", mode = "function")) {
    pub_figure_filepath_at(
      fig_dir, fig_no, fig_caption, ext = "pdf",
      bump_counter = isTRUE(bl$bump_counter %||% TRUE),
      kind = fig_kind
    )
  } else {
    file.path(fig_dir, paste0("Figure ", fig_no, ". ", fig_caption, ".pdf"))
  }

  ## 面板已各自带 x_lim（分位窗口）；此处不再用全局 xlim 覆盖，除非显式固定
  ylim <- bl$ylim
  xlim_draw <- if (use_fixed_xlim) as.numeric(xlim_cfg[1:2]) else NULL
  ff <- if (isTRUE(capabilities("cairo"))) "Times New Roman" else "serif"
  if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(outfile, width = 12, height = 8, family = ff)
  } else {
    grDevices::pdf(outfile, width = 12, height = 8, family = "serif")
  }
  on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
  graphics::par(mfrow = c(2, 3), oma = c(0.5, 0.5, 1.5, 0.5))
  k <- 0L
  for (ri in 1:2) {
    for (hi in seq_along(want)) {
      k <- k + 1L
      sp <- hspecs[[want[[hi]]]]
      tryCatch(
        .rsh06_draw_panel(
          fits[[k]], index_lab = index_lab,
          panel_letter = letters_mat[ri, min(hi, ncol(letters_mat))],
          title_main = paste0(row_labs[[ri]], " — ", sp$label),
          xlim = xlim_draw, ylim = ylim, plot_ff = ff
        ),
        error = function(e) {
          plot.new()
          title(
            main = paste0(letters_mat[ri, min(hi, ncol(letters_mat))], "  ",
                          row_labs[[ri]], " — ", sp$label),
            adj = 0, cex.main = 1
          )
          text(0.5, 0.5, "Not estimable", cex = 1.1)
          cli::cli_alert_warning(
            "rcs_sofa_horizon: 面板绘制失败 {row_labs[[ri]]} × {sp$label}: {conditionMessage(e)}"
          )
        }
      )
    }
  }
  graphics::mtext(
    paste0("Association of ", index_lab, " with mortality, stratified by SOFA"),
    outer = TRUE, cex = 1.05, font = 2
  )
  try(grDevices::dev.off(), silent = TRUE)
  on.exit(NULL)

  ctx$results$rcs_sofa_horizon_figure <- outfile
  ctx$results$rcs_sofa_horizon_panel_stats <- lapply(seq_along(fits), function(i) {
    f <- fits[[i]]
    if (is.null(f)) return(NULL)
    list(p_overall = f$p_overall, p_nonlinear = f$p_nonlinear, n = f$n, events = f$events)
  })
  if (exists("pub_mirror_saved", mode = "function")) {
    try(pub_mirror_saved(ctx, outfile), silent = TRUE)
  }
  cli::cli_alert_success("rcs_sofa_horizon: 已写出 {basename(outfile)}")
  ctx
}

register_block(
  "rcs_sofa_horizon",
  block_rcs_sofa_horizon,
  "Jin Fig1：SOFA×多时点 2×3 Cox RCS"
)
