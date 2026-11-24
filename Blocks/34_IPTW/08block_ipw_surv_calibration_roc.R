###############################################################################
#  ipw_surv_calibration_roc — 预后模型校准 + 时点 ROC（项目 Figure S4）
#
#  对齐 Jin 补充 Fig.S3：Calibration + ROC of the prediction model
#  本项目：28 天全因死亡 Cox 预后模型（PS 协变量 ± 当前复合指标）
#
#  ipw_surv_calibration_roc = list(
#    eval_time_days = 28,
#    n_cal_groups   = 3L,                 # 校准分组数（Jin 图约 3 点）
#    covariates     = "from_model2",      # 或字符向量
#    include_index  = TRUE,               # 把当前复合指标并入模型
#    figure_caption = "...",
#    pause_enable   = FALSE
#  )
#
#  产出: [supp_figure] Figure S4 Calibration + ROC
###############################################################################

.scr08_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.scr08_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_surv_calibration_roc",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_surv_calibration_roc halted. See ctx$results$pause_point.",
    call. = FALSE
  )
}

.scr08_resolve_covars <- function(data, cfg, ctx, bl_cfg) {
  cov <- bl_cfg$covariates %||% "from_model2"
  if (is.character(cov) && length(cov) == 1L && identical(tolower(cov), "from_model2")) {
    m1 <- ctx$results$Model1Factors %||% character(0)
    m2 <- ctx$results$Model2Factors %||% character(0)
    cov <- unique(c(as.character(m1), as.character(m2)))
  }
  cov <- as.character(cov)
  cov <- cov[nzchar(cov) & cov %in% names(data)]
  if (isTRUE(bl_cfg$include_index %||% TRUE)) {
    idx <- bl_cfg$index_var %||%
      cfg$analysis_exclusion$index_var %||%
      cfg$incidence$index_var %||%
      cfg$active_unit %||%
      cfg$stepp_prognosis$index_var
    idx <- as.character(idx)[1L]
    if (nzchar(idx) && idx %in% names(data) && !idx %in% cov) {
      cov <- c(cov, idx)
    }
  }
  # 排除暴露本身（预后模型预测死亡，不把糖尿病当结局标记混入也可保留；Jin 模型不含治疗）
  expv <- as.character(cfg$iptw_balance$exposure_var %||% "Diabetes_HbA1c")[1L]
  if (isTRUE(bl_cfg$exclude_exposure %||% TRUE)) {
    cov <- setdiff(cov, expv)
  }
  unique(cov)
}

.scr08_pred_surv <- function(fit, newdata, eval_time) {
  # 基线生存 ^ exp(lp)
  sfit <- survival::survfit(fit, newdata = newdata)
  # survfit with newdata returns matrix of curves
  summ <- summary(sfit, times = eval_time, extend = TRUE)
  surv <- as.numeric(summ$surv)
  if (length(surv) == 1L && nrow(newdata) > 1L) {
    # 单条基线时用 S0^exp(lp)
    lp <- as.numeric(stats::predict(fit, newdata = newdata, type = "lp"))
    s0 <- as.numeric(summary(survival::survfit(fit), times = eval_time, extend = TRUE)$surv)[1L]
    if (!is.finite(s0) || s0 <= 0) return(rep(NA_real_, nrow(newdata)))
    return(s0^exp(lp))
  }
  if (length(surv) != nrow(newdata)) {
    # 尝试按列取
    if (is.matrix(summ$surv) && ncol(summ$surv) == nrow(newdata)) {
      return(as.numeric(summ$surv[1L, ]))
    }
  }
  surv
}

.scr08_calibration_df <- function(time, event, pred_surv, eval_time, n_groups = 3L) {
  ok <- is.finite(time) & !is.na(event) & is.finite(pred_surv)
  time <- time[ok]; event <- event[ok]; pred_surv <- pred_surv[ok]
  n_groups <- max(2L, as.integer(n_groups)[1L])
  qs <- stats::quantile(pred_surv, probs = seq(0, 1, length.out = n_groups + 1L), na.rm = TRUE)
  qs <- unique(qs)
  if (length(qs) < 3L) {
    return(data.frame())
  }
  grp <- cut(pred_surv, breaks = qs, include.lowest = TRUE, labels = FALSE)
  rows <- list()
  for (g in sort(unique(grp[!is.na(grp)]))) {
    idx <- which(grp == g)
    if (length(idx) < 5L) next
    pred_mean <- mean(pred_surv[idx], na.rm = TRUE)
    fit <- survival::survfit(survival::Surv(time[idx], event[idx]) ~ 1)
    s <- summary(fit, times = eval_time, extend = TRUE)
    obs <- as.numeric(s$surv)[1L]
    lo <- as.numeric(s$lower)[1L]
    hi <- as.numeric(s$upper)[1L]
    rows[[length(rows) + 1L]] <- data.frame(
      group = g,
      n = length(idx),
      predicted = pred_mean,
      observed = obs,
      lower = lo,
      upper = hi,
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(data.frame())
  dplyr::bind_rows(rows)
}

.scr08_timeroc_auc <- function(time, event, marker, eval_time) {
  ok <- is.finite(time) & !is.na(event) & is.finite(marker)
  time <- time[ok]; event <- as.integer(event[ok]); marker <- marker[ok]
  if (length(time) < 30L || length(unique(event)) < 2L) return(NA_real_)
  if (!requireNamespace("timeROC", quietly = TRUE)) return(NA_real_)
  # 随访在 eval_time 大量删失时，timeROC 在恰等于终点时常返回 NA；略提前评估
  t_try <- unique(c(
    as.numeric(eval_time),
    as.numeric(eval_time) - 1,
    as.numeric(eval_time) - 0.01,
    stats::median(time[event == 1L], na.rm = TRUE)
  ))
  t_try <- t_try[is.finite(t_try) & t_try > 0]
  t_try <- t_try[t_try < max(time, na.rm = TRUE) + 1e-8]
  for (tt in t_try) {
    roc <- tryCatch(
      timeROC::timeROC(
        T = time, delta = event, marker = marker, cause = 1L,
        times = tt, iid = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(roc)) next
    a <- as.numeric(roc$AUC)
    a <- a[is.finite(a)]
    if (length(a)) return(a[length(a)])
  }
  NA_real_
}

.scr08_timeroc_curve <- function(time, event, marker, eval_time) {
  ok <- is.finite(time) & !is.na(event) & is.finite(marker)
  time <- time[ok]; event <- as.integer(event[ok]); marker <- marker[ok]
  if (!requireNamespace("timeROC", quietly = TRUE)) return(NULL)
  t_try <- unique(c(
    as.numeric(eval_time),
    as.numeric(eval_time) - 1,
    as.numeric(eval_time) - 0.01
  ))
  t_try <- t_try[is.finite(t_try) & t_try > 0]
  for (tt in t_try) {
    roc <- tryCatch(
      timeROC::timeROC(
        T = time, delta = event, marker = marker, cause = 1L,
        times = tt, iid = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(roc)) next
    fp <- roc$FP
    tp <- roc$TP
    if (is.null(fp) || is.null(tp)) next
    j <- 1L
    if (is.matrix(fp)) {
      # 选 AUC 有限且 FP 有限的列
      auc <- as.numeric(roc$AUC)
      cand <- which(is.finite(auc))
      if (!length(cand) && !is.null(roc$times)) {
        cand <- which.min(abs(as.numeric(roc$times) - tt))
      }
      if (!length(cand)) cand <- ncol(fp)
      j <- cand[length(cand)]
      fp <- fp[, j]
      tp <- tp[, j]
    }
    out <- data.frame(
      fpr = as.numeric(fp),
      tpr = as.numeric(tp),
      stringsAsFactors = FALSE
    )
    out <- out[is.finite(out$fpr) & is.finite(out$tpr), , drop = FALSE]
    if (nrow(out) >= 5L) {
      attr(out, "roc_time") <- tt
      return(out)
    }
  }
  NULL
}

block_ipw_surv_calibration_roc <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    library(ggplot2)
    library(dplyr)
  })
  cfg <- ctx$config
  bl_cfg <- cfg$ipw_surv_calibration_roc %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.scr08_should_pause(bl_cfg, "pause_on_missing_data", TRUE)) {
      .scr08_pause(ctx, "无分析数据", "先跑 imputation")
    }
    stop("ipw_surv_calibration_roc: no data", call. = FALSE)
  }
  data <- as.data.frame(data)

  surv <- cfg$survival
  time_var <- as.character(surv$time_var %||% "surv_time_28d")[1L]
  event_var <- as.character(surv$event_var %||% "surv_event_28d")[1L]
  event_value <- surv$event_value %||% 1
  eval_time <- as.numeric(bl_cfg$eval_time_days %||% bl_cfg$eval_time_months %||% 28)[1L]
  n_groups <- as.integer(bl_cfg$n_cal_groups %||% 3L)[1L]

  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("ipw_surv_calibration_roc: 缺少生存列 ", time_var, "/", event_var, call. = FALSE)
  }

  covars <- .scr08_resolve_covars(data, cfg, ctx, bl_cfg)
  if (!length(covars)) {
    stop("ipw_surv_calibration_roc: 无可用协变量（检查 Model2Factors / covariates）", call. = FALSE)
  }

  # 事件 0/1
  ev <- data[[event_var]]
  if (is.logical(ev)) {
    data$.scr_event <- as.integer(ev)
  } else if (is.numeric(ev)) {
    data$.scr_event <- as.integer(ev == event_value)
  } else {
    data$.scr_event <- as.integer(as.character(ev) == as.character(event_value))
  }
  data$.scr_time <- suppressWarnings(as.numeric(data[[time_var]]))

  use_cols <- c(".scr_time", ".scr_event", covars)
  d <- data[, use_cols, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 50L || sum(d$.scr_event == 1L) < 10L) {
    stop("ipw_surv_calibration_roc: 有效样本或事件数不足", call. = FALSE)
  }

  # 因子化字符列
  for (cn in covars) {
    if (is.character(d[[cn]])) d[[cn]] <- factor(d[[cn]])
  }

  form <- stats::as.formula(
    paste0("survival::Surv(.scr_time, .scr_event) ~ ", paste(covars, collapse = " + "))
  )
  fit <- tryCatch(
    survival::coxph(form, data = d, x = TRUE, y = TRUE, model = TRUE),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    stop("ipw_surv_calibration_roc: Cox 拟合失败", call. = FALSE)
  }

  lp <- as.numeric(stats::predict(fit, type = "lp"))
  # 高 lp = 高死亡风险；校准用预测生存率；ROC marker 用 lp（或 -pred_surv）
  pred_surv <- .scr08_pred_surv(fit, d, eval_time)
  if (length(pred_surv) != nrow(d) || !any(is.finite(pred_surv))) {
    # 回退：基线生存 ^ exp(lp)
    s0 <- as.numeric(summary(survival::survfit(fit), times = eval_time, extend = TRUE)$surv)[1L]
    pred_surv <- s0^exp(lp)
  }

  cal_df <- .scr08_calibration_df(
    d$.scr_time, d$.scr_event, pred_surv, eval_time, n_groups = n_groups
  )
  if (!nrow(cal_df)) {
    stop("ipw_surv_calibration_roc: 校准分组为空", call. = FALSE)
  }

  auc <- .scr08_timeroc_auc(d$.scr_time, d$.scr_event, lp, eval_time)
  roc_df <- .scr08_timeroc_curve(d$.scr_time, d$.scr_event, lp, eval_time)

  ff <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else {
    "sans"
  }

  # Panel A: calibration
  lim_lo <- max(0, min(c(cal_df$predicted, cal_df$observed, cal_df$lower), na.rm = TRUE) - 0.02)
  lim_hi <- min(1, max(c(cal_df$predicted, cal_df$observed, cal_df$upper), na.rm = TRUE) + 0.02)
  # Jin 图轴较窄；若预测集中在高生存区，自动收紧
  if (lim_lo > 0.5) lim_lo <- max(0.5, lim_lo)

  xlab_a <- as.character(
    bl_cfg$cal_xlab %||% sprintf("Predicted %s-Day Survival", as.integer(eval_time))
  )[1L]
  ylab_a <- as.character(
    bl_cfg$cal_ylab %||% sprintf("Actual %s-Day Survival", as.integer(eval_time))
  )[1L]

  p_a <- ggplot2::ggplot(cal_df, ggplot2::aes(x = .data$predicted, y = .data$observed)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey55") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$lower, ymax = .data$upper),
      width = 0.01,
      color = "#4C72B0",
      linewidth = 0.6
    ) +
    ggplot2::geom_line(color = "#C0392B", linewidth = 0.8) +
    ggplot2::geom_point(color = "#C0392B", size = 2.8) +
    ggplot2::coord_cartesian(xlim = c(lim_lo, lim_hi), ylim = c(lim_lo, lim_hi)) +
    ggplot2::labs(title = "A", x = xlab_a, y = ylab_a) +
    ggplot2::theme_classic(base_size = 12, base_family = ff) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", hjust = 0))

  # rug of predicted values (Jin-style ticks at top)
  rug_df <- data.frame(x = pred_surv[is.finite(pred_surv)])
  if (nrow(rug_df) > 2000L) {
    set.seed(1)
    rug_df <- rug_df[sample.int(nrow(rug_df), 2000L), , drop = FALSE]
  }
  p_a <- p_a + ggplot2::geom_rug(
    data = rug_df,
    ggplot2::aes(x = .data$x),
    inherit.aes = FALSE,
    sides = "t",
    alpha = 0.25,
    length = grid::unit(0.02, "npc")
  )

  # Panel B: ROC
  auc_lab <- if (is.finite(auc)) sprintf("%.3f", auc) else "NA"
  title_b <- sprintf("ROC Curve at Time=%s days  AUC = %s", as.integer(eval_time), auc_lab)
  if (is.null(roc_df) || !nrow(roc_df)) {
    p_b <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, label = "ROC unavailable") +
      ggplot2::labs(title = "B", x = "1-Specificity", y = "Sensitivity") +
      ggplot2::theme_void()
  } else {
    p_b <- ggplot2::ggplot(roc_df, ggplot2::aes(x = .data$fpr, y = .data$tpr)) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey55") +
      ggplot2::geom_line(color = "#2C5F8A", linewidth = 1) +
      ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
      ggplot2::labs(title = "B", subtitle = title_b, x = "1-Specificity", y = "Sensitivity") +
      ggplot2::theme_classic(base_size = 12, base_family = ff) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", hjust = 0),
        plot.subtitle = ggplot2::element_text(size = 10, hjust = 0.5)
      )
  }

  fig_cap <- as.character(
    bl_cfg$figure_caption %||%
      sprintf(
        "Calibration and receiver operating characteristic curves of the prediction model at %s-day",
        as.integer(eval_time)
      )
  )[1L]
  fig_w <- as.numeric(bl_cfg$figure_width %||% 10)[1L]
  fig_h <- as.numeric(bl_cfg$figure_height %||% 5)[1L]

  # 强制 Figure S4 文件名（避免重绘时计数器从 0 起步变成 S1）
  fig_fn <- sprintf(
    "Figure S4. %s.pdf",
    fig_cap
  )
  if (exists(".inject_db_into_pub_label", mode = "function")) {
    fig_fn <- .pub_figure_filename(.inject_db_into_pub_label(fig_fn, sanitize_for_file = TRUE))
  }
  if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
    .pub_state$supp_figure <- max(4L, as.integer(.pub_state$supp_figure %||% 0L))
  }

  if (!requireNamespace("patchwork", quietly = TRUE)) {
    stop("ipw_surv_calibration_roc: 需要 patchwork", call. = FALSE)
  }

  roc_time_used <- if (!is.null(roc_df)) attr(roc_df, "roc_time") %||% eval_time else eval_time
  auc_lab <- if (is.finite(auc)) sprintf("%.3f", auc) else "NA"
  title_b <- sprintf(
    "ROC Curve at Time=%s days  AUC = %s",
    as.integer(round(roc_time_used)),
    auc_lab
  )
  if (!is.null(p_b) && inherits(p_b, "ggplot")) {
    p_b <- p_b + ggplot2::labs(subtitle = title_b)
  }

  ctx <- save_figure(
    ctx,
    fig_fn,
    function() {
      print(p_a + p_b + patchwork::plot_layout(widths = c(1, 1)))
      invisible(NULL)
    },
    width = fig_w,
    height = fig_h
  )

  ctx$results$ipw_surv_calibration_roc <- list(
    figure = fig_fn,
    auc = auc,
    eval_time = eval_time,
    n = nrow(d),
    n_events = sum(d$.scr_event == 1L),
    covariates = covars,
    calibration = cal_df,
    cox_call = deparse(fit$call)
  )

  # ── Table S1：Uno's concordance index（对齐 Jin 补充 Table S1）──────────────
  if (!isFALSE(bl_cfg$export_uno_cindex %||% TRUE)) {
    n_boot <- as.integer(bl_cfg$uno_n_perturbations %||% 100L)[1L]
    set.seed(as.integer(bl_cfg$uno_seed %||% 1234L)[1L])
    c_est <- NA_real_
    if (requireNamespace("Hmisc", quietly = TRUE)) {
      c_est <- tryCatch({
        as.numeric(Hmisc::rcorr.cens(-lp, survival::Surv(d$.scr_time, d$.scr_event))["C Index"])
      }, error = function(e) NA_real_)
    }
    if (!is.finite(c_est)) {
      c_est <- tryCatch({
        as.numeric(survival::concordance(fit)$concordance)
      }, error = function(e) NA_real_)
    }
    boot_vals <- replicate(n_boot, {
      ii <- sample.int(nrow(d), nrow(d), replace = TRUE)
      dd <- d[ii, , drop = FALSE]
      ff <- tryCatch(survival::coxph(form, data = dd), error = function(e) NULL)
      if (is.null(ff)) return(NA_real_)
      lpb <- tryCatch(as.numeric(stats::predict(ff, type = "lp")), error = function(e) NULL)
      if (is.null(lpb) || length(lpb) != nrow(dd)) return(NA_real_)
      if (requireNamespace("Hmisc", quietly = TRUE)) {
        tryCatch(
          as.numeric(Hmisc::rcorr.cens(-lpb, survival::Surv(dd$.scr_time, dd$.scr_event))["C Index"]),
          error = function(e) NA_real_
        )
      } else {
        tryCatch(as.numeric(survival::concordance(ff)$concordance), error = function(e) NA_real_)
      }
    })
    boot_vals <- boot_vals[is.finite(boot_vals)]
    ci_lo <- if (length(boot_vals) >= 20L) unname(stats::quantile(boot_vals, 0.025)) else NA_real_
    ci_hi <- if (length(boot_vals) >= 20L) unname(stats::quantile(boot_vals, 0.975)) else NA_real_
    horizon_lab <- sprintf("%s-Day", as.integer(eval_time))
    uno_df <- data.frame(
      Horizon = horizon_lab,
      `Uno's concordance index` = if (is.finite(c_est)) sprintf("%.2f", c_est) else "NA",
      `95% CI` = if (is.finite(ci_lo) && is.finite(ci_hi)) {
        sprintf("(%.2f, %.2f)", ci_lo, ci_hi)
      } else {
        "NA"
      },
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    uno_cap <- as.character(
      bl_cfg$uno_table_caption %||%
        sprintf("The Uno's concordance index at %s-day", as.integer(eval_time))
    )[1L]
    uno_fn <- sprintf("Table S1. %s.xlsx", uno_cap)
    if (exists(".inject_db_into_pub_label", mode = "function")) {
      uno_fn <- .pub_figure_filename(
        .inject_db_into_pub_label(uno_fn, sanitize_for_file = TRUE)
      )
    }
    uno_path <- file.path(ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables"), uno_fn)
    dir.create(dirname(uno_path), recursive = TRUE, showWarnings = FALSE)
    if (exists("export_sci_table", mode = "function")) {
      export_sci_table(
        uno_df,
        uno_path,
        title = paste0("Table S1. ", uno_cap),
        table_footnotes = sprintf(
          "The 95%% CI of Uno's concordance index was obtained by %s perturbations.",
          n_boot
        ),
        latex_include_colnames = TRUE
      )
    } else {
      utils::write.csv(uno_df, sub("\\.xlsx$", ".csv", uno_path), row.names = FALSE)
    }
    ctx$results$ipw_surv_calibration_roc$uno_cindex <- list(
      estimate = c_est, ci_low = ci_lo, ci_high = ci_hi,
      n_boot = n_boot, path = uno_path
    )
    if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
      .pub_state$supp_table <- max(1L, as.integer(.pub_state$supp_table %||% 0L))
    }
    cli::cli_alert_success(
      "Uno C-index Table S1: C={sprintf('%.2f', c_est)} ({sprintf('%.2f', ci_lo)}, {sprintf('%.2f', ci_hi)})"
    )
  }

  cli::cli_alert_success(
    "ipw_surv_calibration_roc: Figure S4 done (n={nrow(d)}, AUC={auc_lab}, groups={nrow(cal_df)})"
  )
  ctx
}

register_block(
  "ipw_surv_calibration_roc",
  block_ipw_surv_calibration_roc,
  "预后模型校准+ROC（Figure S4，对齐 Jin Fig.S3）"
)
