###############################################################################
#  ipw_weighted_km_pub — IPW 加权 KM 曲线 + IPW-Cox HR（对应文献 Figure 2 / Fig S2）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data    = ctx$data$iptw_weighted（须先运行 34_IPTW/01block_iptw_balance）
#  require_results = ctx$results$iptw_weight_col（可选；缺省回退 "weight"）
#
#  ipw_diabetes = list(               # 与 01block_ipw_diabetes_exposure 共用
#    exposure_var = "Diabetes_HbA1c",
#    time_var     = "surv_time_28d",  # NULL → ctx$config$survival$time_var
#    event_var    = "surv_event_28d"  # NULL → ctx$config$survival$event_var
#  )
#  ipw_weighted_km_pub = list(
#    weight_col        = NULL,        # NULL → ctx$results$iptw_weight_col %||% "weight"
#    level_low         = "No diabetes",
#    level_high        = "Diabetes (HbA1c \u2265 6.5%)",
#    palette           = c("#377EB8", "#E41A1C"),
#    xlim              = c(0, 28),
#    break_time_by     = 7,
#    xlab              = "Follow-up time (days)",
#    risk_table        = TRUE,
#    plot_width        = 8,
#    plot_height       = 7,
#    figure_number     = 2,           # 固定 Figure 2（主加权 KM）
#    figure_caption    = "IPW-weighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Diabetes_HbA1c",
#    supp_figure_caption = "Unweighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Diabetes_HbA1c",
#    table_filename    = "Table_IPW_Weighted_Cox_HR.csv",  # 固定名，不占发表表序号
#    pause_enable        = TRUE,
#    pause_on_no_output  = TRUE
#  )
#
#  register_block: "ipw_weighted_km_pub"
#  典型位置: iptw_balance → iptw_association → ipw_diabetes_flowchart → ipw_weighted_km_pub
#
#  读: ctx$data$iptw_weighted（IPTW 加权后数据，含权重列）
#  写: ctx$results$ipw_weighted_km_pub（加权/未加权 Cox HR、95% CI、P，pub_format_p 格式化）
#
#  产出:
#    - [main_figure] Figure_2_IPW_KM       → pub_figure_filepath_at（固定 Fig.2）
#    - [supp_figure] Figure_S2_Unweighted_KM → pub_figure_file("supp_figure", ...)
#      （本块在生成前用 .wkm03_ensure_supp_figure_min() 将 supp_figure 计数器
#       局部推进到"结果编号 >= 2"，避免本批次未真正产出 Figure S1 时该图被
#       误编号为 S1；不修改 R/utils.R 全局计数器逻辑，仅在本块内安全复用
#       现有 .pub_state / .pub_counters_snapshot() 工具）
#    - [固定名]      Table_IPW_Weighted_Cox_HR.csv（加权 vs 未加权 Cox HR 对照）
#
#  加权 Cox HR 使用 coxph(weights = IPTW 权重, robust = TRUE)（sandwich 稳健方差），
#  与加权 KM（survival::survfit(weights=)）方法一致；未加权侧作为对照（Fig S2）。
#
#  pause: config$ipw_weighted_km_pub$pause_enable
###############################################################################

.wkm03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.wkm03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_weighted_km_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_weighted_km_pub halted. See ctx$results$pause_point. / ",
    "IPW 加权 KM 异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.wkm03_pdf_ok <- function(path) {
  fi <- tryCatch(file.info(path), error = function(e) NULL)
  !is.null(fi) && isTRUE(nrow(fi) == 1L) && !is.na(fi$size) && fi$size > 10L
}

# 局部工具（不修改 R/utils.R）：确保紧随其后调用的 pub_figure_file(ctx, "supp_figure", ...)
# 拿到的编号 >= min_result_id。做法是安全复用现有 .pub_state 计数器状态与
# .pub_counters_snapshot() 快照工具，把预增量前的 supp_figure 计数推进到
# (min_result_id - 1)（不足时才推进，已达到/超过则保持不变，不会消耗额外编号）。
# 背景：Figure S1 = 缺失热图；Figure S2 = PS+SMD（iptw_balance，对齐原文 S1）；
# 本块 unweighted KM 应为 Figure S3（对齐原文 S2）。
# 若不做该保护，本图会在 supp_figure 计数器上被错误编号。
.wkm03_ensure_supp_figure_min <- function(ctx, min_result_id) {
  min_result_id <- suppressWarnings(as.integer(min_result_id))[1L]
  if (!is.finite(min_result_id) || min_result_id < 1L) return(ctx)
  if (!exists(".pub_state", mode = "environment", inherits = TRUE)) return(ctx)
  pre_needed <- min_result_id - 1L
  cur <- suppressWarnings(as.integer(get0("supp_figure", envir = .pub_state, ifnotfound = 0L)))
  if (!is.finite(cur)) cur <- 0L
  if (cur < pre_needed) {
    assign("supp_figure", pre_needed, envir = .pub_state)
  }
  if (exists(".pub_counters_snapshot", mode = "function", inherits = TRUE)) {
    ctx$log$pub_counters <- .pub_counters_snapshot()
  }
  ctx
}

# IPW 调整 log-rank（优先 survey::svylogrank；否则回退稳健 Cox P）
.wkm03_ipw_logrank_p <- function(d, time_var, event_var, group_var, weight_col) {
  form <- stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", group_var))
  if (requireNamespace("survey", quietly = TRUE)) {
    des <- tryCatch(
      survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", weight_col)), data = d),
      error = function(e) NULL
    )
    if (!is.null(des)) {
      lr <- tryCatch(survey::svylogrank(form, design = des), error = function(e) NULL)
      # svylogrank 返回 list，p 常在 [[2]] 或 $p
      if (!is.null(lr)) {
        p <- NA_real_
        if (is.list(lr) && length(lr) >= 2L && is.numeric(lr[[2]])) {
          p <- as.numeric(lr[[2]])[1L]
        } else if (!is.null(lr$p)) {
          p <- as.numeric(lr$p)[1L]
        } else if (is.numeric(lr)) {
          p <- as.numeric(lr)[1L]
        }
        if (is.finite(p)) return(list(p = p, method = "IPW-adjusted log-rank"))
      }
    }
  }
  # 回退：稳健方差 Cox（与加权 KM 同权重）
  cox <- .wkm03_cox_hr(d, time_var, event_var, group_var, weight_col)
  list(p = cox$p, method = "IPW-adjusted Cox")
}

# 从 survfit 提取 landmark 时点生存率 + 95% CI（按 strata）
.wkm03_landmark_surv <- function(fit, time_point, legend_labs) {
  time_point <- as.numeric(time_point)[1L]
  s <- tryCatch(summary(fit, times = time_point, extend = TRUE), error = function(e) NULL)
  if (is.null(s)) return(character(0))
  labs <- as.character(legend_labs)
  n_str <- length(labs)
  surv <- as.numeric(s$surv)
  lo <- as.numeric(s$lower)
  hi <- as.numeric(s$upper)
  # 单时点多 strata：长度应 = n_str
  if (length(surv) < n_str) {
    surv <- rep(surv, length.out = n_str)
    lo <- rep(lo, length.out = n_str)
    hi <- rep(hi, length.out = n_str)
  }
  vapply(seq_len(n_str), function(i) {
    sprintf(
      "%s: %.1f%% (95%% CI, %.1f%% to %.1f%%)",
      labs[i],
      100 * surv[i], 100 * lo[i], 100 * hi[i]
    )
  }, character(1L))
}

# 从 survfit 提取各时点 n.risk（按 strata / legend_labs 顺序）
.wkm03_nrisk_df <- function(fit, times, legend_labs) {
  times <- as.numeric(times)
  s <- tryCatch(summary(fit, times = times, extend = TRUE), error = function(e) NULL)
  if (is.null(s)) return(NULL)
  labs <- as.character(legend_labs)
  n_str <- length(labs)
  n_t <- length(times)
  nr <- as.numeric(s$n.risk)
  # 多 strata：summary 通常按 strata 块排列
  if (!is.null(s$strata) && length(nr) >= n_str * n_t) {
    st <- as.character(s$strata)
    # strata 名常带 "Group=No" 前缀
    st_lab <- sub("^.*=", "", st)
    out <- lapply(seq_len(n_str), function(i) {
      idx <- which(st_lab == labs[i] | grepl(paste0("(^|,)", labs[i], "$"), st))
      if (!length(idx)) idx <- which(grepl(labs[i], st, fixed = TRUE))
      v <- nr[idx]
      if (length(v) < n_t) v <- rep(v, length.out = n_t)
      data.frame(
        time = times,
        strata = factor(labs[i], levels = labs),
        n = as.integer(v[seq_len(n_t)]),
        stringsAsFactors = FALSE
      )
    })
    return(do.call(rbind, out))
  }
  # 单层或长度刚好
  if (length(nr) == n_str * n_t) {
    return(data.frame(
      time = rep(times, times = n_str),
      strata = factor(rep(labs, each = n_t), levels = labs),
      n = as.integer(nr),
      stringsAsFactors = FALSE
    ))
  }
  NULL
}

# Jin 同构风险表：白底 + 灰网格；表顶刻度；标题 Number at risk；表下时间轴名
.wkm03_risk_table_jin <- function(fit, bl_cfg, palette, font_family,
                                  km_xlim, km_break, km_xlab,
                                  legend_title, legend_labs) {
  times <- seq(km_xlim[1L], km_xlim[2L], by = km_break)
  df <- .wkm03_nrisk_df(fit, times, legend_labs)
  if (is.null(df) || !nrow(df)) return(NULL)
  # 上 No 下 Yes
  df$strata <- factor(df$strata, levels = rev(as.character(legend_labs)))
  x_exp <- ggplot2::expansion(mult = c(0.02, 0.02))
  fs <- as.numeric(bl_cfg$risk_table_fontsize %||% 3.8)[1L]
  y_cols <- rev(palette[seq_along(legend_labs)])
  ggplot2::ggplot(df, ggplot2::aes(x = time, y = strata)) +
    ggplot2::geom_text(
      ggplot2::aes(label = n),
      size = fs,
      family = font_family,
      colour = "grey15"
    ) +
    ggplot2::scale_x_continuous(
      name = km_xlab,
      limits = km_xlim,
      breaks = times,
      expand = x_exp,
      # 表顶也要日期刻度（与主图 x 轴对齐），不重复数字标签
      sec.axis = ggplot2::dup_axis(name = NULL, labels = NULL)
    ) +
    ggplot2::scale_y_discrete(drop = FALSE) +
    ggplot2::coord_cartesian(clip = "off") +
    # 刻度下方、表格上方的名字（对应原文 Number at risk）
    ggplot2::labs(title = "Number at risk", y = legend_title) +
    ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(
      text = ggplot2::element_text(family = font_family),
      plot.title = ggplot2::element_text(
        face = "bold", size = 11, hjust = 0,
        margin = ggplot2::margin(2, 0, 4, 0)
      ),
      axis.title.x = ggplot2::element_text(size = 11, margin = ggplot2::margin(t = 2)),
      axis.title.y = ggplot2::element_text(size = 10),
      axis.title.x.top = ggplot2::element_blank(),
      # 日期数字已在主图刻度上，表底只留轴名，避免重复
      axis.text.x = ggplot2::element_blank(),
      axis.text.x.top = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(
        size = 10, face = "bold", colour = y_cols,
        margin = ggplot2::margin(r = 5)
      ),
      axis.line = ggplot2::element_blank(),
      axis.ticks.y = ggplot2::element_blank(),
      axis.ticks.x.bottom = ggplot2::element_blank(),
      axis.ticks.x.top = ggplot2::element_line(colour = "black", linewidth = 0.35),
      axis.ticks.length.x.top = grid::unit(3, "pt"),
      # 白底 + 灰色格子线
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.grid.major = ggplot2::element_line(colour = "grey70", linewidth = 0.35),
      panel.grid.minor = ggplot2::element_blank(),
      panel.border = ggplot2::element_rect(fill = NA, colour = "grey45", linewidth = 0.4),
      plot.margin = ggplot2::margin(0, 12, 2, 8)
    )
}

.wkm03_build_ggsurv <- function(fit, d, bl_cfg, palette, font_family,
                                km_xlim, km_break, km_xlab, km_ylab,
                                legend_title, legend_labs,
                                risk_tbl, conf_int, p_label, annot_lines,
                                fit_risk = NULL) {
  # Jin 同构主图：classic 半开框、嵌图例、手写注释；风险表另绘格子
  show_censor <- if (is.null(bl_cfg$show_censor)) TRUE else isTRUE(bl_cfg$show_censor)
  leg_cfg <- bl_cfg$legend_inset %||% c(0.98, 0.85)
  if (is.numeric(leg_cfg) && length(leg_cfg) >= 2L) {
    legend_arg <- as.numeric(leg_cfg[1:2])
    inset_leg <- TRUE
  } else {
    legend_arg <- as.character(leg_cfg %||% "right")[1L]
    inset_leg <- FALSE
  }
  ylim_use <- bl_cfg$ylim %||% NULL
  leg_title_use <- as.character(legend_title %||% "")[1L]
  brks <- seq(km_xlim[1L], km_xlim[2L], by = km_break)
  x_exp <- ggplot2::expansion(mult = c(0.02, 0.02))

  p <- survminer::ggsurvplot(
    fit,
    data = d,
    risk.table = FALSE,
    conf.int = isTRUE(conf_int),
    conf.int.alpha = as.numeric(bl_cfg$conf_int_alpha %||% 0.15)[1L],
    censor = show_censor,
    censor.size = as.numeric(bl_cfg$censor_size %||% 2.2)[1L],
    surv.median.line = "none",
    xlim = km_xlim,
    ylim = ylim_use,
    break.time.by = km_break,
    xlab = NULL,
    ylab = km_ylab,
    legend.title = leg_title_use,
    legend.labs = legend_labs,
    legend = legend_arg,
    pval = FALSE,
    palette = palette,
    ggtheme = ggplot2::theme_classic(base_size = as.numeric(bl_cfg$base_size %||% 12)[1L]),
    ncensor.plot = FALSE
  )

  # 注释：Jin 在空白区无衬底；本数据终点生存率低，浅白底防压 CI
  if ((length(annot_lines) || (is.character(p_label) && nzchar(p_label))) && !is.null(p$plot)) {
    lines <- character(0)
    if (is.character(p_label) && nzchar(p_label[1L])) lines <- c(lines, p_label[1L])
    if (length(annot_lines)) lines <- c(lines, annot_lines)
    lab <- paste(lines, collapse = "\n")
    y0 <- as.numeric(bl_cfg$annot_y %||% 0.32)[1L]
    x0 <- as.numeric(bl_cfg$annot_x %||% (km_xlim[1L] + diff(range(km_xlim)) * 0.02))[1L]
    y_span <- diff(range(ylim_use %||% c(0, 1)))
    n_lines <- length(lines)
    line_h <- y_span * 0.048
    p$plot <- p$plot +
      ggplot2::annotate(
        "rect",
        xmin = x0 - 0.2,
        xmax = min(km_xlim[2L], x0 + diff(range(km_xlim)) * 0.58),
        ymin = y0 - 0.008,
        ymax = y0 + n_lines * line_h + 0.015,
        fill = "white", alpha = 0.82, colour = NA
      ) +
      ggplot2::annotate(
        "text",
        x = x0, y = y0,
        label = lab,
        hjust = 0, vjust = 0,
        size = as.numeric(bl_cfg$annot_size %||% 3.5)[1L],
        lineheight = as.numeric(bl_cfg$annot_lineheight %||% 1.15)[1L],
        family = font_family
      )
  }

  if (!is.null(p$plot)) {
    # 上部分日期刻度（0/7/14…）在主图底；其下接风险表名 Number at risk
    th <- ggplot2::theme(
      text = ggplot2::element_text(family = font_family),
      legend.title = ggplot2::element_text(face = "bold", size = 10),
      legend.text = ggplot2::element_text(size = 10),
      legend.background = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank(),
      legend.key.width = grid::unit(1.15, "lines"),
      legend.key.height = grid::unit(0.7, "lines"),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      panel.grid = ggplot2::element_blank(),
      axis.title.x = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(size = 10, colour = "black",
                                         margin = ggplot2::margin(t = 2)),
      axis.ticks.x = ggplot2::element_line(colour = "black", linewidth = 0.4),
      axis.ticks.length.x = grid::unit(3.5, "pt"),
      axis.line.x = ggplot2::element_line(colour = "black", linewidth = 0.5),
      plot.margin = ggplot2::margin(6, 12, 1, 8)
    )
    if (isTRUE(inset_leg)) {
      th <- th + ggplot2::theme(
        legend.justification = bl_cfg$legend_justification %||% c(1, 1)
      )
    }
    p$plot <- tryCatch(
      p$plot +
        ggplot2::scale_x_continuous(limits = km_xlim, breaks = brks, expand = x_exp) +
        th +
        ggplot2::guides(
          fill = "none",
          colour = ggplot2::guide_legend(override.aes = list(linetype = 1, shape = NA, alpha = 1))
        ),
      error = function(e) p$plot
    )
  }

  # 自定义 Jin 格子风险表（不用 survminer 自带表）
  if (isTRUE(risk_tbl)) {
    fr <- fit_risk %||% fit
    p$table <- tryCatch(
      .wkm03_risk_table_jin(
        fr, bl_cfg, palette, font_family,
        km_xlim, km_break, km_xlab,
        leg_title_use, legend_labs
      ),
      error = function(e) {
        cli::cli_alert_warning("Jin 风险表构建失败: {e$message}")
        NULL
      }
    )
  } else {
    p$table <- NULL
  }
  p
}

# 主图 + 风险表竖排对齐（左右轴对齐）
.wkm03_combine_plot_table <- function(p, bl_cfg) {
  if (is.null(p) || is.null(p$plot)) return(NULL)
  if (is.null(p$table)) return(p$plot)
  h_tbl <- as.numeric(bl_cfg$risk_table_height %||% 0.22)[1L]
  if (!is.finite(h_tbl) || h_tbl <= 0 || h_tbl >= 1) h_tbl <- 0.22
  if (requireNamespace("cowplot", quietly = TRUE)) {
    return(cowplot::plot_grid(
      p$plot, p$table,
      ncol = 1L, align = "v", axis = "lr",
      rel_heights = c(1 - h_tbl, h_tbl)
    ))
  }
  if (requireNamespace("gridExtra", quietly = TRUE)) {
    return(gridExtra::arrangeGrob(
      p$plot, p$table,
      ncol = 1L,
      heights = grid::unit(c(1 - h_tbl, h_tbl), "null")
    ))
  }
  tryCatch(survminer::arrange_ggsurvplot(p, print = FALSE), error = function(e) p$plot)
}

# 拟合 Cox HR（可选权重 + 稳健方差），失败时返回 NA 占位，不中断流程
.wkm03_cox_hr <- function(d, time_var, event_var, group_var, weight_col = NULL) {
  form <- stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", group_var))
  fit <- tryCatch({
    if (!is.null(weight_col) && weight_col %in% names(d)) {
      survival::coxph(form, data = d, weights = d[[weight_col]], robust = TRUE)
    } else {
      survival::coxph(form, data = d)
    }
  }, error = function(e) NULL)
  if (is.null(fit)) {
    return(list(hr = NA_real_, lower = NA_real_, upper = NA_real_, p = NA_real_, n = nrow(d), n_event = NA_integer_))
  }
  s <- summary(fit)
  ci <- s$conf.int
  coefs <- s$coefficients
  p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
  list(
    hr = unname(ci[1L, "exp(coef)"]),
    lower = unname(ci[1L, grep("lower", colnames(ci))[1L]]),
    upper = unname(ci[1L, grep("upper", colnames(ci))[1L]]),
    p = unname(coefs[1L, p_col]),
    n = fit$n,
    n_event = fit$nevent
  )
}

block_ipw_weighted_km_pub <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    if (requireNamespace("survminer", quietly = TRUE)) library(survminer)
    library(cli)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$ipw_weighted_km_pub %||% list()
  ipw_cfg <- cfg$ipw_diabetes %||% list()

  data <- ctx$data$iptw_weighted
  if (is.null(data) || !is.data.frame(data)) {
    if (.wkm03_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .wkm03_pause(ctx, "未找到 IPTW 加权数据（ctx$data$iptw_weighted 为空）。",
                  "请先运行 34_IPTW/01block_iptw_balance。", NULL)
    }
    stop("ipw_weighted_km_pub: 无 IPTW 加权数据。", call. = FALSE)
  }

  exp_var <- as.character(ipw_cfg$exposure_var %||% cfg$iptw_balance$exposure_var %||% "Diabetes_HbA1c")[1L]
  tvar <- as.character(ipw_cfg$time_var %||% cfg$survival$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(ipw_cfg$event_var %||% cfg$survival$event_var %||% "surv_event_28d")[1L]
  weight_col <- as.character(bl_cfg$weight_col %||% ctx$results$iptw_weight_col %||% "weight")[1L]

  need <- c(tvar, yvar, exp_var, weight_col)
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    msg <- paste0("ipw_weighted_km_pub: 数据缺少列: ", paste(miss, collapse = ", "))
    if (.wkm03_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .wkm03_pause(ctx, msg, "检查 ipw_diabetes_exposure / iptw_balance 是否已运行。", data)
    }
    stop(msg, call. = FALSE)
  }

  # Jin 同构图例：标题 + No/Yes；完整描述可在 caption
  lvl_lo <- as.character(bl_cfg$level_low %||% "No")[1L]
  lvl_hi <- as.character(bl_cfg$level_high %||% "Yes")[1L]
  legend_title <- as.character(
    bl_cfg$legend_title %||% "Diabetes (HbA1c \u2265 6.5%)"
  )[1L]
  palette <- bl_cfg$palette %||% block_default_palette(2L, cfg)
  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else {
    "serif"
  }

  d <- data[, unique(c(tvar, yvar, exp_var, weight_col)), drop = FALSE]
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  d[[weight_col]] <- suppressWarnings(as.numeric(d[[weight_col]]))
  d <- d[is.finite(d[[tvar]]) & d[[tvar]] >= 0 & !is.na(d[[yvar]]) &
           is.finite(d[[weight_col]]) & !is.na(d[[exp_var]]), , drop = FALSE]
  d$Group <- factor(ifelse(as.numeric(d[[exp_var]]) == 1L, lvl_hi, lvl_lo), levels = c(lvl_lo, lvl_hi))
  d <- d[!is.na(d$Group), , drop = FALSE]

  if (!nrow(d) || length(unique(d$Group)) < 2L) {
    msg <- "ipw_weighted_km_pub: 有效数据不足或暴露组不足 2 个水平。"
    if (.wkm03_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .wkm03_pause(ctx, msg, "检查 Diabetes_HbA1c 分布与生存列缺失情况。", d)
    }
    stop(msg, call. = FALSE)
  }

  cox_weighted <- .wkm03_cox_hr(d, tvar, yvar, "Group", weight_col)
  cox_unweighted <- .wkm03_cox_hr(d, tvar, yvar, "Group", NULL)

  hr_tab <- data.frame(
    Analysis = c("IPW-weighted Cox", "Unweighted Cox"),
    N = c(cox_weighted$n, cox_unweighted$n),
    Events = c(cox_weighted$n_event, cox_unweighted$n_event),
    HR = c(cox_weighted$hr, cox_unweighted$hr),
    Lower95 = c(cox_weighted$lower, cox_unweighted$lower),
    Upper95 = c(cox_weighted$upper, cox_unweighted$upper),
    P = pub_format_p(c(cox_weighted$p, cox_unweighted$p)),
    stringsAsFactors = FALSE
  )
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_IPW_Weighted_Cox_HR.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(hr_tab, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("IPW-Cox HR 表写出失败: {e$message}")
  )

  footnote <- sprintf(
    "IPW-weighted HR = %.2f (95%% CI %.2f\u2013%.2f), P%s; unweighted HR = %.2f (95%% CI %.2f\u2013%.2f), P%s",
    cox_weighted$hr, cox_weighted$lower, cox_weighted$upper,
    pub_format_p(cox_weighted$p),
    cox_unweighted$hr, cox_unweighted$lower, cox_unweighted$upper,
    pub_format_p(cox_unweighted$p)
  )

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  km_xlim <- bl_cfg$xlim %||% c(0, 28)
  km_break <- bl_cfg$break_time_by %||% 7
  km_xlab <- bl_cfg$xlab %||% "Follow-up time (days)"
  km_ylab <- bl_cfg$ylab %||% "Survival Probability"
  plot_w <- bl_cfg$plot_width %||% 8
  plot_h <- bl_cfg$plot_height %||% 7.5
  risk_tbl <- isTRUE(bl_cfg$risk_table %||% TRUE)
  conf_int <- isTRUE(bl_cfg$conf_int %||% TRUE)
  landmark <- as.numeric(bl_cfg$landmark_day %||% km_xlim[2L])[1L]
  if (!is.finite(landmark)) landmark <- 28
  surv_form <- stats::as.formula(paste0("Surv(", tvar, ", ", yvar, ") ~ Group"))
  legend_labs <- levels(d$Group)

  .render_km <- function(weighted, out_path, title_txt) {
    .make_fit <- function(use_w) {
      if (requireNamespace("survminer", quietly = TRUE)) {
        # survminer::surv_fit 保留 formula，避免 ggsurvplot 中 x$formula 报 symbol 不可子集
        if (isTRUE(use_w)) {
          return(survminer::surv_fit(surv_form, data = d, weights = d[[weight_col]]))
        }
        return(survminer::surv_fit(surv_form, data = d))
      }
      if (isTRUE(use_w)) {
        return(survival::survfit(surv_form, data = d, weights = d[[weight_col]]))
      }
      survival::survfit(surv_form, data = d)
    }
    fit <- tryCatch(.make_fit(weighted), error = function(e) NULL)
    if (is.null(fit)) return(FALSE)
    # 风险表用未加权例数（Jin Number at risk），曲线/CI 用加权 fit
    fit_risk <- tryCatch(.make_fit(FALSE), error = function(e) fit)
    # 兜底：把公式挂到 fit 上，防止 ggsurvplot 取 call 失败
    if (is.null(attr(fit, "formula", exact = TRUE))) attr(fit, "formula") <- surv_form
    if (is.null(attr(fit_risk, "formula", exact = TRUE))) attr(fit_risk, "formula") <- surv_form

    if (isTRUE(weighted)) {
      lr <- .wkm03_ipw_logrank_p(d, tvar, yvar, "Group", weight_col)
      pf <- pub_format_p(lr$p)
      p_lab <- if (grepl("^[<>]", pf)) {
        sprintf("%s P%s", lr$method, pf)
      } else {
        sprintf("%s P=%s", lr$method, pf)
      }
      rate_hdr <- sprintf("Weighted %s-day survival rate", as.integer(landmark))
    } else {
      sd <- tryCatch(survival::survdiff(surv_form, data = d), error = function(e) NULL)
      p_uw <- if (!is.null(sd)) {
        1 - stats::pchisq(sd$chisq, length(sd$n) - 1L)
      } else {
        cox_unweighted$p
      }
      pf <- pub_format_p(p_uw)
      p_lab <- if (grepl("^[<>]", pf)) sprintf("Log-rank P%s", pf) else sprintf("Log-rank P=%s", pf)
      rate_hdr <- sprintf("Unweighted %s-day survival rate", as.integer(landmark))
    }
    rate_lines <- .wkm03_landmark_surv(fit, landmark, legend_labs)
    annot <- c(rate_hdr, rate_lines)

    saved_local <- FALSE
    p <- tryCatch(
      if (requireNamespace("survminer", quietly = TRUE)) {
        p_main <- .wkm03_build_ggsurv(
          fit, d, bl_cfg, palette, font_family,
          km_xlim, km_break, km_xlab, km_ylab,
          legend_title, legend_labs,
          risk_tbl = isTRUE(risk_tbl), conf_int = conf_int,
          p_label = p_lab, annot_lines = annot,
          fit_risk = fit_risk
        )
        p_main
      } else NULL,
      error = function(e) {
        cli::cli_alert_warning("ggsurvplot 构建失败: {e$message}")
        cli::cli_alert_warning("call: {paste(deparse(conditionCall(e)), collapse=' ')}")
        NULL
      }
    )
    if (!is.null(p)) {
      comb <- .wkm03_combine_plot_table(p, bl_cfg)
      if (!is.null(comb)) {
        for (fam in unique(c(font_family, "sans", "serif"))) {
          ok <- tryCatch({
            if (file.exists(out_path)) unlink(out_path)
            ggplot2::ggsave(
              out_path, plot = comb, width = plot_w, height = plot_h,
              device = grDevices::cairo_pdf, family = fam
            )
            .wkm03_pdf_ok(out_path)
          }, error = function(e) FALSE)
          if (isTRUE(ok)) { saved_local <- TRUE; break }
        }
      }
      if (!saved_local) {
        ok <- tryCatch({
          if (file.exists(out_path)) unlink(out_path)
          grDevices::pdf(out_path, width = plot_w, height = plot_h, onefile = TRUE)
          tryCatch(print(p, newpage = FALSE), error = function(e) print(p))
          grDevices::dev.off()
          .wkm03_pdf_ok(out_path)
        }, error = function(e) {
          try(grDevices::dev.off(), silent = TRUE)
          FALSE
        })
        if (isTRUE(ok)) saved_local <- TRUE
      }
    }
    if (!saved_local) {
      ok <- tryCatch({
        if (file.exists(out_path)) unlink(out_path)
        grDevices::pdf(out_path, width = plot_w, height = plot_h)
        plot(
          fit, col = palette, xlim = km_xlim, xlab = km_xlab, ylab = km_ylab,
          main = title_txt, conf.int = isTRUE(conf_int)
        )
        graphics::legend("bottomleft", legend = legend_labs, col = palette, lty = 1, bty = "n",
                         title = legend_title)
        graphics::mtext(paste(c(p_lab, annot), collapse = "; "), side = 1, line = 4, cex = 0.65)
        grDevices::dev.off()
        .wkm03_pdf_ok(out_path)
      }, error = function(e) {
        try(grDevices::dev.off(), silent = TRUE)
        FALSE
      })
      if (isTRUE(ok)) saved_local <- TRUE
    }
    saved_local
  }

  fig_cap_main <- as.character(bl_cfg$figure_caption %||%
    "IPW-weighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Diabetes_HbA1c")[1L]
  fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% 2L))[1L]
  fig2_path <- if (exists("pub_figure_filepath_at", mode = "function") && is.finite(fig_no) && fig_no >= 1L) {
    pub_figure_filepath_at(fig_dir, fig_no, fig_cap_main, ext = "pdf", bump_counter = TRUE)
  } else {
    file.path(fig_dir, pub_figure_file(ctx, "main_figure", fig_cap_main))
  }
  saved_main <- .render_km(TRUE, fig2_path, paste0("Figure 2. ", fig_cap_main))
  if (isTRUE(saved_main) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, fig2_path)
  }

  fig_cap_supp <- as.character(bl_cfg$supp_figure_caption %||%
    "Unweighted Kaplan\u2013Meier curves of 28-day all-cause mortality by Diabetes_HbA1c")[1L]
  # 局部保护：确保本图编号最终 >= 3（Figure S3）
  # S1=缺失热图；S2=PS+SMD（对齐原文 Fig.S1）
  ctx <- .wkm03_ensure_supp_figure_min(ctx, 3L)
  figs3_path <- file.path(fig_dir, pub_figure_file(ctx, "supp_figure", fig_cap_supp))
  saved_supp <- .render_km(FALSE, figs3_path, paste0("Figure S3. ", fig_cap_supp))
  if (isTRUE(saved_supp) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, figs3_path)
  }

  if (!isTRUE(saved_main) && !isTRUE(saved_supp) &&
      .wkm03_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .wkm03_pause(ctx, "ipw_weighted_km_pub 未能生成加权/未加权 KM 图。",
                "检查 survival/survminer 是否可用及数据有效性。", d)
  }

  ctx$results$ipw_weighted_km_pub <- list(
    cox_weighted = cox_weighted,
    cox_unweighted = cox_unweighted,
    hr_table = hr_tab,
    footnote = footnote,
    figure_main_path = if (isTRUE(saved_main)) fig2_path else NA_character_,
    figure_supp_path = if (isTRUE(saved_supp)) figs3_path else NA_character_,
    weight_col = weight_col,
    n = nrow(d)
  )
  cli::cli_alert_success(
    "ipw_weighted_km_pub 完成（IPW HR={round(cox_weighted$hr, 2)}, P={pub_format_p(cox_weighted$p)}）"
  )
  ctx
}

register_block(
  "ipw_weighted_km_pub",
  block_ipw_weighted_km_pub,
  "IPW 加权 KM 曲线 + IPW-Cox HR（Figure 2 + Figure S3 未加权）"
)
