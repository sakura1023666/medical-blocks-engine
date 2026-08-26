###############################################################################
#  rcs_prognosis — 预后 Cox RCS（限制性立方样条 + smoothHR）：Crude / Model1 / Model2，
#                  base 图密度+HR 曲线，默认 cairo 横排 Fig 2 ABC。
#
#  register_block: "rcs_prognosis"
#  典型流水线: imputation → … → rcs_prognosis（study_type = prognosis）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_study  = config$project$study_type == "prognosis"（否则跳过）
#  时间/事件列   = config$survival$time_var / event_var（默认 futime / fustatus）
#  暴露指标     = config$survival$index_var 或 logistic$index_var
#  Model1/2     = ctx$results$Model1Factors|Model2Factors 或 config$rcs_prognosis$model*_factors
#                  或 config$cox$model*_covariates；Fig 2B=Model1 全量，Fig 2C=Model2 全量
#
#  # ── 配置 config$rcs_prognosis ─────────────────────────────────────────────
#  rcs_prognosis = list(
#    index_var                = NULL,    # 连续暴露；NULL → survival$index_var
#    model1_factors           = NULL,    # 覆盖 Model1Factors；NULL 用 ctx$results
#    model2_factors           = NULL,    # 覆盖 Model2Factors
#    nk_range                 = 3:5,     # coxph + rcspline.eval，AIC 选 nk
#    panel_color_seed         = 123,     # ABC 三面板各抽一组 pdf_color_config
#    pdf_color_config         = NULL,    # list(list(color1=密度色, color2=曲线色), ...)；NULL 内置 5 组
#    figure_filename          = NULL,    # NULL → "Fig 2. RCS Analysis ... Mortality ...pdf"
#    ylim                     = NULL,    # c(ymin, ymax)；如 c(0, 5) 固定纵轴，避免分离时 HR 撑爆
#    y_min / y_max            = NULL,    # ylim 的拆分写法
#    event_non_survivor_label = "Non-survivor"  # 字符型 event 时除 analysis_group 外的事件标签
#  ),
#
#  # ── 读写 ctx ─────────────────────────────────────────────────────────────
#  写: rcs_cutoff / cutoff_value = Model2 曲线切点（见 utils.R rcs_refined_cutoffs）；
#      rcs_prognosis_nk, res_crude|model1|model2, rcs_prognosis_figure
#  cutoff 规则: 仅 1 个 HR=1 → 该 x；≥2 个 HR=1 时斜率=0 峰值仅当其落在两 HR=1 之间才保留
#  图: 无背景密度；Model 2（C）HR=1/峰值竖虚线 + 右侧横向数值；A/B 无虚线
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  Figures/Fig 2. RCS Analysis ...pdf（15×5）；cutoff_<Index>.csv
#
#  源: C01_RCS_Survival_TypeII2/21.R（ABC 段）；无 glm 段
#  依赖: survival, smoothHR, Hmisc, ggplot2
###############################################################################

.rcp01_parse_factors <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  if (length(x) == 1L && is.character(x) && grepl("\\+", x, fixed = FALSE)) {
    return(trimws(unlist(strsplit(x, "\\s*\\+\\s*"))))
  }
  trimws(as.character(x))
}

.rcp01_default_pdf_color_config <- function() {
  list(
    list(color1 = "#9ECAE1", color2 = "#E41A1C"),
    list(color1 = "#B3CDE3", color2 = "#377EB8"),
    list(color1 = "#CCEBC5", color2 = "#4DAF4A"),
    list(color1 = "#FBB4AE", color2 = "#E41A1C"),
    list(color1 = "#DECBE4", color2 = "#984EA3")
  )
}

.rcp01_coerce_event_01 <- function(x, cfg, evname) {
  if (is.numeric(x)) {
    if (all(is.na(x))) return(as.numeric(x))
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
    stop("rcs_prognosis: ", evname, " 为数值但非 0/1 编码。")
  }
  if (is.logical(x)) return(as.integer(x))
  ns_lbl <- cfg$rcs_prognosis$event_non_survivor_label %||% "Non-survivor"
  ana_lbl <- trimws(cfg$project$analysis_group %||% "")
  xc <- trimws(as.character(x))
  out <- rep(NA_integer_, length(xc))
  not_na <- !is.na(xc) & nzchar(xc)
  is_event <- not_na & (
    xc == ns_lbl |
      tolower(xc) == tolower(ns_lbl) |
      (nzchar(ana_lbl) & (xc == ana_lbl | tolower(xc) == tolower(ana_lbl)))
  )
  out[is_event] <- 1L
  out[not_na & !is_event] <- 0L
  out
}

# ── C01 共有拟合（smoothHR + predict）────────────────────────────────────────
.rcp01_fit_and_predict <- function(formula_str, Index, rt, x_min = NULL, x_max = NULL) {
  form_obj <- as.formula(formula_str)
  fit <- coxph(form_obj, data = rt, x = TRUE)
  fit$call$formula <- form_obj

  # 预测轴必须落在 Cox 实际用到的完整病例 Index 范围内（协变量 NA 会缩窄样本）
  used_vars <- intersect(all.vars(form_obj), names(rt))
  if (!length(used_vars)) used_vars <- Index
  cc <- stats::complete.cases(rt[, used_vars, drop = FALSE])
  rt_fit <- rt[cc, , drop = FALSE]
  if (!nrow(rt_fit)) rt_fit <- rt

  hr1 <- smoothHR(data = rt_fit, coxfit = fit)
  p   <- summary(hr1$coxfit)

  refvalue <- stats::median(rt_fit[[Index]], na.rm = TRUE)
  xmin_d <- min(rt_fit[[Index]], na.rm = TRUE)
  xmax_d <- max(rt_fit[[Index]], na.rm = TRUE)
  xmin_use <- xmin_d
  xmax_use <- xmax_d
  if (!is.null(x_min) && length(x_min) && is.finite(suppressWarnings(as.numeric(x_min)[1L]))) {
    xmin_use <- max(xmin_d, as.numeric(x_min)[1L])
  }
  if (!is.null(x_max) && length(x_max) && is.finite(suppressWarnings(as.numeric(x_max)[1L]))) {
    xmax_use <- min(xmax_d, as.numeric(x_max)[1L])
  }
  if (!is.finite(xmin_use) || !is.finite(xmax_use) || xmin_use >= xmax_use) {
    xmin_use <- xmin_d
    xmax_use <- xmax_d
  }
  # 参考点也夹在显示区间内，避免中位数落在裁切轴外
  if (is.finite(refvalue)) {
    refvalue <- min(max(refvalue, xmin_use), xmax_use)
  }
  # 略微内缩，避免浮点边界触发 smoothHR「prediction.values must be between…」
  span <- xmax_use - xmin_use
  pad <- if (is.finite(span) && span > 0) max(span * 1e-9, .Machine$double.eps * 100) else 0
  prediction_values <- seq(xmin_use + pad, xmax_use - pad, length.out = 1000)
  smoothlogHR.point <- tryCatch(
    as.data.frame(
      predict(hr1, predictor = Index, pred.value = refvalue, prob = 0.5,
              prediction.values = prediction_values, conf.level = 0.95)
    ),
    error = function(e) {
      # 再收紧到 1%–99% 分位重试
      qs <- as.numeric(stats::quantile(rt_fit[[Index]], probs = c(0.01, 0.99), na.rm = TRUE))
      if (length(qs) != 2L || !all(is.finite(qs)) || qs[1L] >= qs[2L]) stop(e)
      pv2 <- seq(qs[1L], qs[2L], length.out = 1000)
      ref2 <- min(max(refvalue, qs[1L]), qs[2L])
      as.data.frame(
        predict(hr1, predictor = Index, pred.value = ref2, prob = 0.5,
                prediction.values = pv2, conf.level = 0.95)
      )
    }
  )
  list(
    smoothlogHR.point = smoothlogHR.point, p = p, refvalue = refvalue,
    x_lim = c(xmin_use, xmax_use)
  )
}

.rcp01_find_hr_cutoffs <- function(smoothlogHR.point) {
  if (is.null(smoothlogHR.point) || !nrow(smoothlogHR.point)) {
    return(list(or1 = numeric(0), slope_zero = numeric(0), peak = numeric(0), all = numeric(0)))
  }
  x <- as.numeric(smoothlogHR.point[, 1L])
  lnhr <- as.numeric(smoothlogHR.point$LnHR)
  rcs_find_cutoffs_from_lnhr_curve(x, lnhr)
}

# ── Cox smoothHR 面板（无密度背景；可选 cutoff 竖虚线）──────────────────────
.rcp01_panel_usr <- function() {
  u <- par("usr")
  if (length(u) != 4L || !all(is.finite(u))) return(NULL)
  u
}

.rcp01_hline_panel <- function(y, lty = 3, col = "grey40", lwd = 1.3) {
  usr <- .rcp01_panel_usr()
  if (is.null(usr)) return(invisible(NULL))
  graphics::segments(usr[1L], y, usr[2L], y, lty = lty, col = col, lwd = lwd, xpd = FALSE)
  invisible(NULL)
}

.rcp01_vline_panel <- function(x, lty = 2, col = "gray35", lwd = 1) {
  usr <- .rcp01_panel_usr()
  if (is.null(usr)) return(invisible(NULL))
  graphics::segments(x, usr[3L], x, usr[4L], lty = lty, col = col, lwd = lwd, xpd = FALSE)
  invisible(NULL)
}

.rcp01_draw_panel <- function(panel_letter, Index, smoothlogHR.point, p, refvalue, cfg,
                              plot_ff = "serif", show_cutoff_lines = FALSE, cutoffs = NULL,
                              label_digits = 2L, xlim = NULL, ylim = NULL) {
  par(family = plot_ff, mar = c(5, 4, 4, 2) + 0.3, xpd = FALSE)

  x_vec <- as.numeric(smoothlogHR.point[, 1L])
  hr_vec <- exp(as.numeric(smoothlogHR.point$LnHR))
  lo_vec <- exp(as.numeric(smoothlogHR.point$`lower .95`))
  hi_vec <- exp(as.numeric(smoothlogHR.point$`upper .95`))
  # Cox 不收敛时 LnHR 可为 ±Inf；ylim 只取有限正值
  finite_y <- c(hr_vec, lo_vec, hi_vec)
  finite_y <- finite_y[is.finite(finite_y) & finite_y > 0]
  if (!length(finite_y)) {
    ylim.bot <- 0.1
    ylim.top <- 10
    hr_vec[!is.finite(hr_vec)] <- NA_real_
  } else {
    ylim.bot <- min(finite_y, na.rm = TRUE)
    ylim.top <- max(finite_y, na.rm = TRUE)
    if (!is.finite(ylim.bot) || !is.finite(ylim.top) || ylim.top <= ylim.bot) {
      ylim.bot <- 0.1
      ylim.top <- 10
    }
    # 极端尾巴压到 99% 分位，避免单点 Inf 撑爆轴
    q99 <- as.numeric(stats::quantile(finite_y, 0.99, na.rm = TRUE))
    if (is.finite(q99) && q99 > ylim.bot) {
      ylim.top <- min(ylim.top, max(q99 * 1.2, ylim.bot * 1.5))
    }
  }
  y_pad <- max((ylim.top - ylim.bot) * 0.12, 0.05)
  ylim_user <- suppressWarnings(as.numeric(ylim)[1:2])
  if (length(ylim_user) >= 2L && all(is.finite(ylim_user)) && ylim_user[2L] > ylim_user[1L]) {
    ylim.bot <- ylim_user[1L]
    ylim.top <- ylim_user[2L]
    y_pad <- 0
  }

  y_lim_final <- c(max(0, ylim.bot - y_pad), ylim.top + y_pad)
  if (!all(is.finite(y_lim_final)) || y_lim_final[2L] <= y_lim_final[1L]) {
    y_lim_final <- c(0.1, 10)
  }
  # 裁切展示用序列，避免 CI 线在 ylim 外「冒出」图框
  .rcp01_clip_y <- function(y) {
    y <- as.numeric(y)
    y[!is.finite(y)] <- NA_real_
    y[y < y_lim_final[1L] | y > y_lim_final[2L]] <- NA_real_
    y
  }
  hr_plot <- .rcp01_clip_y(hr_vec)
  lo_plot <- .rcp01_clip_y(lo_vec)
  hi_plot <- .rcp01_clip_y(hi_vec)

  plot_args <- list(
    x = x_vec, y = hr_plot,
    xlab = if (exists("pipeline_plot_axis_label", mode = "function")) {
      pipeline_plot_axis_label(Index)
    } else {
      gsub("_", " ", as.character(Index)[1L], fixed = TRUE)
    },
    ylab = "HR (95%CI)",
    type = "l",
    ylim = y_lim_final,
    col = cfg$color2, lwd = 2,
    xaxs = "i", yaxs = "i"
  )
  if (!is.null(xlim) && length(xlim) >= 2L &&
      all(is.finite(as.numeric(xlim[1:2])))) {
    plot_args$xlim <- as.numeric(xlim[1:2])
  }
  do.call(plot, plot_args)
  lines(x_vec, lo_plot, lty = 2, lwd = 1.5)
  lines(x_vec, hi_plot, lty = 2, lwd = 1.5)
  .rcp01_hline_panel(1, lty = 3, col = "grey40", lwd = 1.3)
  if (is.finite(refvalue) &&
      (is.null(xlim) || (refvalue >= as.numeric(xlim[1L]) && refvalue <= as.numeric(xlim[2L])))) {
    points(refvalue, 1, pch = 16, cex = 1.2)
  }

  if (isTRUE(show_cutoff_lines) && !is.null(cutoffs) && length(cutoffs$all)) {
    xs <- sort(unique(as.numeric(cutoffs$all[is.finite(cutoffs$all)])))
    # 裁切轴：只标注画布内 cutoff
    if (!is.null(xlim) && length(xlim) >= 2L && all(is.finite(as.numeric(xlim[1:2])))) {
      xs <- xs[xs >= as.numeric(xlim[1L]) & xs <= as.numeric(xlim[2L])]
    }
    x_rng <- range(x_vec, na.rm = TRUE)
    x_off <- diff(x_rng) * 0.015
    f_hr <- stats::approxfun(x_vec, hr_vec, rule = 2)
    y_drop <- max((ylim.top - ylim.bot) * 0.06, 0.04)
    for (i in seq_along(xs)) {
      .rcp01_vline_panel(xs[i], lty = 2, col = "gray35", lwd = 1)
      y_at <- f_hr(xs[i])
      if (!is.finite(y_at)) y_at <- ylim.top
      y_at <- min(max(y_at, ylim.bot), ylim.top)
      par(xpd = NA)
      text(
        xs[i] + x_off,
        y_at - (i - 1L) %% 3L * y_drop,
        labels = rcs_format_cutoff(xs[i], digits = label_digits),
        adj = c(0, 0.5),
        cex = 0.75,
        col = "gray20"
      )
      par(xpd = FALSE)
    }
  }

  .fmt_p_leg <- function(label, pv) {
    pv <- suppressWarnings(as.numeric(pv)[1L])
    if (!is.finite(pv)) return(paste0(label, " = NA"))
    # p < 0.001 → "P-overall < 0.001"；否则保留 3 位小数
    if (pv < 0.001) return(paste0(label, " < 0.001"))
    paste0(label, " = ", formatC(pv, digits = 3, format = "f"))
  }

  legend(
    "topright",
    paste0(
      .fmt_p_leg("P-overall", p$logtest[3]),
      "\n",
      .fmt_p_leg("P-non-linear", p$coefficients[2, 5])
    ),
    bty = "n", cex = 0.8
  )
  legend("topleft", lty = c(1, 2), col = c(cfg$color2, "black"),
         c("Estimation", "95% CI"), bty = "n", cex = 0.8)

  mtext(panel_letter, side = 3, adj = 0, line = 1, cex = 1.1, font = 2)
}

block_rcs_prognosis <- function(ctx, ...) {
  cfg <- ctx$config
  study_type <- tolower(trimws(cfg$project$study_type %||% ""))
  surv_cfg_early <- cfg$survival %||% list()
  has_time <- nzchar(as.character(surv_cfg_early$time_var %||% "")[1L])
  assoc_cox <- identical(
    tolower(trimws(as.character((cfg$ml_batch %||% list())$assoc_model %||% "")[1L])),
    "cox"
  )
  if (!identical(study_type, "prognosis") && !isTRUE(has_time) && !isTRUE(assoc_cox)) {
    cli::cli_alert_info("rcs_prognosis: 无生存时间且非 Cox 关联，跳过。")
    return(ctx)
  }

  suppressPackageStartupMessages({
    library(survival)
    library(smoothHR)
    library(Hmisc)
    library(ggplot2)
  })

  rp_cfg <- cfg$rcs_prognosis %||% list()
  surv_cfg <- cfg$survival %||% list()
  cox_legacy <- cfg$cox %||% list()

  rt <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(rt) || !is.data.frame(rt)) {
    stop("rcs_prognosis: 无分析数据，请先运行 data_clean / imputation。")
  }

  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  Index <- rp_cfg$index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(Index) || !nzchar(Index)) {
    stop("rcs_prognosis: 未设置 index_var（config$survival$index_var 或 rcs_prognosis$index_var）。")
  }
  Disease <- cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"

  for (v in c(time_var, event_var, Index)) {
    if (!v %in% names(rt)) stop("rcs_prognosis: 变量 '", v, "' 不在数据中。")
  }

  rt <- as.data.frame(rt)
  rt[[event_var]] <- as.numeric(.rcp01_coerce_event_01(rt[[event_var]], cfg, event_var))

  cfg_m1 <- as.character(cox_legacy$model1_covariates %||% character(0))
  cfg_m2 <- as.character(cox_legacy$model2_covariates %||% character(0))
  Model1Factors <- .rcp01_parse_factors(
    rp_cfg$model1_factors %||% ctx$results$Model1Factors %||% cfg_m1
  )
  Model2Factors <- .rcp01_parse_factors(
    rp_cfg$model2_factors %||% ctx$results$Model2Factors %||% cfg_m2
  )
  if (length(Model1Factors) == 0L) {
    stop("rcs_prognosis: Model1Factors 为空，请先运行 multicollinearity 或在 config$rcs_prognosis 中指定 model1_factors。")
  }
  if (length(Model2Factors) == 0L) {
    stop("rcs_prognosis: Model2Factors 为空，请先运行 multicollinearity 或在 config$rcs_prognosis 中指定 model2_factors。")
  }

  Model1Factors <- setdiff(Model1Factors, Index)
  Model2Factors <- setdiff(Model2Factors, Index)
  Model1Factors <- intersect(Model1Factors, names(rt))
  Model2Factors <- intersect(Model2Factors, names(rt))
  if (length(Model1Factors) == 0L) stop("rcs_prognosis: Model1Factors 在数据中无可用列。")
  if (length(Model2Factors) == 0L) stop("rcs_prognosis: Model2Factors 在数据中无可用列。")
  Model3Factors <- if (exists("pipeline_rcs_model3_covs", mode = "function")) {
    pipeline_rcs_model3_covs(ctx, cfg, Model2Factors, names(rt), Index)
  } else {
    character(0)
  }
  Model3Factors <- intersect(setdiff(as.character(Model3Factors %||% character(0)), Index), names(rt))
  if (!length(setdiff(Model3Factors, Model2Factors))) Model3Factors <- character(0)
  m3_sig <- isTRUE(ctx$results$model3_significant)

  cli::cli_h2("RCS prognosis (Cox + smoothHR)")
  cli::cli_alert_info("Index={Index}, time={time_var}, event={event_var}, n={nrow(rt)}")
  cli::cli_alert_info("Model1: {paste(Model1Factors, collapse = ', ')}")
  cli::cli_alert_info("Model2: {paste(Model2Factors, collapse = ', ')}")
  if (length(Model3Factors)) {
    cli::cli_alert_info("Model3: {paste(Model3Factors, collapse = ', ')}")
  }

  nk_range <- rp_cfg$nk_range %||% (cfg$rcs %||% list())$nk_range %||% 3:5
  nk_range <- as.integer(nk_range)
  if (!length(nk_range)) nk_range <- 3:5

  AIC_best <- Inf
  nk <- NA_integer_
  for (i in nk_range) {
    fml_i <- as.formula(paste0(
      "Surv(", time_var, ", ", event_var, ") ~ rcspline.eval(", Index, ", nk = ", i, ", inclx = TRUE)"
    ))
    fit_i <- tryCatch(coxph(fml_i, data = rt, x = TRUE), error = function(e) NULL)
    if (is.null(fit_i)) next
    AIC_i <- extractAIC(fit_i)[2]
    if (AIC_i < AIC_best) {
      AIC_best <- AIC_i
      nk <- i
    }
  }
  if (is.na(nk)) stop("rcs_prognosis: 无法在 nk_range 内拟合 Cox RCS 模型。")
  cli::cli_alert_success("Selected nk = {nk}")

  knots_values <- attr(rcspline.eval(rt[[Index]], nk = nk), "knots")
  cli::cli_alert_info("Knots: {paste(round(knots_values, 4), collapse = ', ')}")

  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")

  x_min_cfg <- suppressWarnings(as.numeric(rp_cfg$x_min %||% NA_real_)[1L])
  x_max_cfg <- suppressWarnings(as.numeric(rp_cfg$x_max %||% NA_real_)[1L])
  if (!is.finite(x_min_cfg)) x_min_cfg <- NULL
  if (!is.finite(x_max_cfg)) x_max_cfg <- NULL
  pq <- suppressWarnings(as.numeric(rp_cfg$plot_x_quantiles %||% numeric(0)))
  if (length(pq) >= 2L && all(is.finite(pq[1:2])) &&
      is.null(x_min_cfg) && is.null(x_max_cfg) && Index %in% names(rt)) {
    qs <- as.numeric(stats::quantile(rt[[Index]], probs = pq[1:2], na.rm = TRUE))
    if (all(is.finite(qs)) && qs[2L] > qs[1L]) {
      x_min_cfg <- qs[1L]
      x_max_cfg <- qs[2L]
    }
  }
  if (!is.null(x_max_cfg) || !is.null(x_min_cfg)) {
    cli::cli_alert_info(
      "RCS 横轴显示范围: [{if (is.null(x_min_cfg)) 'data_min' else x_min_cfg}, {if (is.null(x_max_cfg)) 'data_max' else x_max_cfg}]"
    )
  }

  form_A <- paste0(surv_lhs, " ~ rcspline.eval(", Index, ", nk = ", nk, ", inclx = TRUE)")
  resA <- .rcp01_fit_and_predict(form_A, Index, rt, x_min = x_min_cfg, x_max = x_max_cfg)

  model1_list <- .rcp01_parse_factors(Model1Factors)
  var_names1 <- paste(model1_list, collapse = " + ")
  form_B <- paste0(surv_lhs, " ~ rcspline.eval(", Index, ", nk = ", nk, ", inclx = TRUE) + ", var_names1)
  resB <- .rcp01_fit_and_predict(form_B, Index, rt, x_min = x_min_cfg, x_max = x_max_cfg)

  model2_list <- .rcp01_parse_factors(Model2Factors)
  var_names2 <- paste(model2_list, collapse = " + ")
  form_C <- paste0(surv_lhs, " ~ rcspline.eval(", Index, ", nk = ", nk, ", inclx = TRUE) + ", var_names2)
  resC <- .rcp01_fit_and_predict(form_C, Index, rt, x_min = x_min_cfg, x_max = x_max_cfg)
  resD <- NULL
  if (length(Model3Factors)) {
    model3_list <- .rcp01_parse_factors(Model3Factors)
    var_names3 <- paste(model3_list, collapse = " + ")
    form_D <- paste0(surv_lhs, " ~ rcspline.eval(", Index, ", nk = ", nk, ", inclx = TRUE) + ", var_names3)
    resD <- .rcp01_fit_and_predict(form_D, Index, rt, x_min = x_min_cfg, x_max = x_max_cfg)
  }

  x_lim_plot <- resC$x_lim %||% resA$x_lim
  if (!is.null(resD)) x_lim_plot <- resD$x_lim %||% x_lim_plot
  ctx$results$rcs_prognosis_x_lim <- x_lim_plot

  color_cfg <- rp_cfg$pdf_color_config %||% .rcp01_default_pdf_color_config()
  if (!is.list(color_cfg[[1]])) {
    stop("rcs_prognosis: pdf_color_config 须为 list(color1=, color2=) 的列表。")
  }
  set.seed(rp_cfg$panel_color_seed %||% 123)
  n_panel <- if (length(Model3Factors) && !is.null(resD)) 4L else 3L
  K <- length(color_cfg)
  pick <- if (K >= n_panel) {
    sample(seq_len(K), n_panel, replace = FALSE)
  } else {
    rep(seq_len(K), length.out = n_panel)
  }
  cfgA <- color_cfg[[pick[1]]]
  cfgB <- color_cfg[[pick[2]]]
  cfgC <- color_cfg[[pick[3]]]
  cfgD <- if (n_panel >= 4L) color_cfg[[pick[4]]] else NULL

  fig_caption <- paste0(
    "RCS Analysis of the Association Between ",
    pipeline_index_display_name(cfg, Index),
    " and Mortality in ", Disease
  )
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  fig_no <- suppressWarnings(as.integer(rp_cfg$figure_number %||% 2L)[1L])
  fig_kind <- as.character(rp_cfg$figure_kind %||% "main_figure")[1L]
  if (!nzchar(fig_kind)) fig_kind <- "main_figure"
  outfile <- if (is.finite(fig_no) && fig_no >= 1L &&
                 exists("pub_figure_filepath_at", mode = "function")) {
    pub_figure_filepath_at(
      fig_dir, fig_no, fig_caption, ext = "pdf",
      bump_counter = isTRUE(rp_cfg$bump_counter %||% TRUE),
      kind = fig_kind
    )
  } else if (!is.null(rp_cfg$figure_filename) && nzchar(rp_cfg$figure_filename)) {
    file.path(fig_dir, rp_cfg$figure_filename)
  } else {
    file.path(fig_dir, pub_figure_file(ctx, fig_kind, fig_caption))
  }
  if (exists(".pub_figure_filename", mode = "function")) {
    outfile <- file.path(fig_dir, .pub_figure_filename(basename(outfile)))
  }

  ff <- if (isTRUE(capabilities("cairo"))) "Times New Roman" else plot_font_from_config(cfg)
  label_digits <- as.integer(rp_cfg$cutoff_label_digits %||% 2L)
  if (!is.finite(label_digits) || label_digits < 0L) label_digits <- 2L

  cutA <- .rcp01_find_hr_cutoffs(resA$smoothlogHR.point)
  cutB <- .rcp01_find_hr_cutoffs(resB$smoothlogHR.point)
  cutC <- .rcp01_find_hr_cutoffs(resC$smoothlogHR.point)
  cutD <- if (!is.null(resD)) .rcp01_find_hr_cutoffs(resD$smoothlogHR.point) else list(or1 = numeric(0), peak = numeric(0), all = numeric(0))
  cut_use <- if (isTRUE(m3_sig) && length(cutD$all)) cutD else cutC
  show_cut_c <- n_panel < 4L || !isTRUE(m3_sig)
  show_cut_d <- n_panel >= 4L && isTRUE(m3_sig)

  if (!exists(".pub_figure_extract_cox_rcs_p", mode = "function") ||
      !exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    pf_r <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
    if (file.exists(pf_r)) source(pf_r, local = FALSE)
  }
  .rcp01_panel_stats <- function(res, cuts = numeric(0)) {
    pe <- .pub_figure_extract_cox_rcs_p(res$p)
    cuts <- as.numeric(cuts)
    list(
      p_overall = pe$p_overall,
      p_nonlinear = pe$p_nonlinear,
      cutoffs = cuts[is.finite(cuts)]
    )
  }
  # 竖线画 cutoffs$all；仅出现 vline 的面板写入 cutoff（Model2 iff show_cut_c，Model3 iff show_cut_d）
  ctx$results$rcs_prognosis_panel_stats <- list(
    Crude = .rcp01_panel_stats(resA, numeric(0)),
    Model1 = .rcp01_panel_stats(resB, numeric(0)),
    Model2 = .rcp01_panel_stats(
      resC, .pub_figure_rcs_panel_vline_cutoffs(cutC, show_cut_c, "all")
    )
  )
  if (!is.null(resD) && n_panel >= 4L) {
    ctx$results$rcs_prognosis_panel_stats$Model3 <- .rcp01_panel_stats(
      resD, .pub_figure_rcs_panel_vline_cutoffs(cutD, show_cut_d, "all")
    )
  }

  lay <- if (exists("pipeline_rcs_layout", mode = "function")) {
    pipeline_rcs_layout(n_panel)
  } else {
    list(width = 15, height = 5, base_matrix = matrix(seq_len(n_panel), nrow = 1L))
  }
  grDevices::cairo_pdf(outfile, width = lay$width, height = lay$height, family = ff)
  plot_ok <- tryCatch({
    par(family = ff)
    if (exists("is_pub_profile", mode = "function") &&
        is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
      par(lwd = 1.15, cex.lab = 1.05, cex.axis = 0.95)
    }
    layout(lay$base_matrix)

    y_lim_plot <- rp_cfg$ylim
    if (is.null(y_lim_plot) && !is.null(rp_cfg$y_max)) {
      y_lim_plot <- c(as.numeric(rp_cfg$y_min %||% 0)[1L], as.numeric(rp_cfg$y_max)[1L])
    }

    .rcp01_draw_panel("Crude Model", Index, resA$smoothlogHR.point, resA$p, resA$refvalue, cfgA, ff,
                      show_cutoff_lines = FALSE, cutoffs = cutA, label_digits = label_digits,
                      xlim = x_lim_plot, ylim = y_lim_plot)
    .rcp01_draw_panel("Model 1", Index, resB$smoothlogHR.point, resB$p, resB$refvalue, cfgB, ff,
                      show_cutoff_lines = FALSE, cutoffs = cutB, label_digits = label_digits,
                      xlim = x_lim_plot, ylim = y_lim_plot)
    .rcp01_draw_panel("Model 2", Index, resC$smoothlogHR.point, resC$p, resC$refvalue, cfgC, ff,
                      show_cutoff_lines = show_cut_c, cutoffs = cutC, label_digits = label_digits,
                      xlim = x_lim_plot, ylim = y_lim_plot)
    if (n_panel >= 4L) {
      .rcp01_draw_panel("Model 3", Index, resD$smoothlogHR.point, resD$p, resD$refvalue, cfgD, ff,
                        show_cutoff_lines = show_cut_d, cutoffs = cutD, label_digits = label_digits,
                        xlim = x_lim_plot, ylim = y_lim_plot)
    }
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("rcs_prognosis 绘图失败（继续写 cutoff）: {conditionMessage(e)}")
    FALSE
  })
  invisible(grDevices::dev.off())
  if (isTRUE(plot_ok)) {
    cli::cli_alert_success("Saved: {basename(outfile)}")
    if (exists("pub_mirror_saved", mode = "function")) {
      pub_mirror_saved(ctx, outfile)
    }
  }

  cutoff <- rcs_primary_cutoff(cut_use)
  if (!is.finite(cutoff)) {
    cutoff <- stats::median(rt[[Index]], na.rm = TRUE)
    cli::cli_alert_warning(
      "RCS primary cutoff 无效，回退 Index 中位数 = {round(cutoff, 4)}"
    )
  }
  ctx$results$rcs_cutoff <- cutoff
  ctx$results$rcs_cutoff_index <- Index
  ctx$results$rcs_cutoff_or1 <- cut_use$or1
  ctx$results$rcs_cutoff_peak <- cut_use$peak
  ctx$results$rcs_cutoffs_all <- cut_use$all
  ctx$results$cutoff_value <- cutoff
  ctx$results$cutoff_variable <- Index
  ctx$results$rcs_prognosis_nk <- nk
  ctx$results$rcs_prognosis_knots <- knots_values
  ctx$results$rcs_prognosis_res_crude <- resA
  ctx$results$rcs_prognosis_res_model1 <- resB
  ctx$results$rcs_prognosis_res_model2 <- resC
  ctx$results$rcs_prognosis_res_model3 <- resD
  ctx$results$rcs_prognosis_model1_factors <- model1_list
  ctx$results$rcs_prognosis_model2_factors <- model2_list
  ctx$results$rcs_prognosis_model3_factors <- Model3Factors
  ctx$results$rcs_prognosis_figure <- outfile

  cutoff_detail <- data.frame(
    index = Index,
    type = c(
      rep("hr1", length(cut_use$or1)),
      rep("peak_hr", length(cut_use$peak))
    ),
    cutoff = c(cut_use$or1, cut_use$peak),
    stringsAsFactors = FALSE
  )
  if (nrow(cutoff_detail)) {
    cutoff_detail <- cutoff_detail[order(cutoff_detail$cutoff), , drop = FALSE]
  }
  ctx <- save_result(
    ctx, "rcs_cutoff",
    cutoff_detail,
    paste0("cutoff_", Index, ".csv")
  )
  or1_txt <- if (length(cut_use$or1)) paste(rcs_format_cutoff(cut_use$or1), collapse = ", ") else "none"
  peak_txt <- if (length(cut_use$peak)) paste(rcs_format_cutoff(cut_use$peak), collapse = ", ") else "none"
  cli::cli_alert_info("RCS cutoffs — HR=1: {or1_txt}; peak HR: {peak_txt}")
  cli::cli_alert_success(
    "rcs_prognosis 完成（primary cutoff = {if (is.finite(cutoff)) round(cutoff, 4) else 'NA'}，共 {length(cut_use$all)} 个 cutoff）"
  )
  ctx
}

register_block(
  "rcs_prognosis",
  block_rcs_prognosis,
  "预后 Cox RCS：有 Model3 时 2×2，否则横排 ABC（C01 风格）"
)
