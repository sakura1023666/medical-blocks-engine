###############################################################################
#  rcs_cox_models_panel — 多库 Cox 限制性立方样条面板（全项目复用）
#
#  用途：按 Model 1 / 2 / 3（或任意协变量清单）画连续暴露的 HR 曲线；
#        NHANES 等复杂抽样库可走 svycoxph，其余库走 coxph。
#  不是流水线 register_block；由课题脚本 source 后调用。
#
#  入口：
#    rcs_cox_models_panel_fit(...)
#    rcs_cox_models_panel_plot(fit, which_models = "Model 1", show_model_strip = FALSE)
#
#  兼容旧名：pv2_rcs_table3 / pv2_plot_rcs_table3
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

rcs_cox_models_panel_fit <- function(
    dbs,
    exposure = "Sleep_hours",
    time_var = "time",
    event_var = "event",
    models = list(
      "Model 1" = character(0),
      "Model 2" = c("Age", "Gender"),
      "Model 3" = c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI")
    ),
    survey_dbs = "NHANES",
    survey_weight = "survey_weight",
    survey_psu = "psu",
    survey_strata = "strata",
    knot_probs = c(0.05, 0.35, 0.65, 0.95),
    ref_value = 7.5,
    x_lim = c(4, 12),
    factor_vars = c("Gender", "Education", "Hypertension", "Alcohol", "Smoke"),
    db_levels = NULL) {
  suppressPackageStartupMessages({
    library(survival)
    library(survey)
  })
  options(survey.lonely.psu = "adjust")
  if (is.null(db_levels) || !length(db_levels)) db_levels <- names(dbs)

  fmt_p <- function(p) {
    if (!is.finite(p)) return("not estimated")
    if (p < 0.001) return("<0.001")
    sprintf("%.3f", p)
  }
  wald <- function(fit, prefix) {
    b <- stats::coef(fit)
    V <- stats::vcov(fit)
    idx <- grep(paste0("^", prefix), names(b))
    if (!length(idx)) return(NA_real_)
    bb <- b[idx]
    VV <- V[idx, idx, drop = FALSE]
    stat <- tryCatch(as.numeric(t(bb) %*% solve(VV, bb)), error = function(e) NA_real_)
    if (!is.finite(stat)) {
      stat <- tryCatch(as.numeric(t(bb) %*% MASS::ginv(VV) %*% bb), error = function(e) NA_real_)
    }
    if (!is.finite(stat)) return(NA_real_)
    stats::pchisq(stat, length(idx), lower.tail = FALSE)
  }
  curve_one <- function(fit, grid, nd, ref_value) {
    mm <- stats::model.matrix(fit, data = nd)
    b <- stats::coef(fit)
    V <- stats::vcov(fit)
    mm <- mm[, names(b), drop = FALSE]
    lp <- as.numeric(mm %*% b)
    ref_i <- which.min(abs(grid - ref_value))
    delta <- sweep(mm, 2, mm[ref_i, ], FUN = "-")
    se <- sqrt(pmax(0, rowSums((delta %*% V) * delta)))
    lp <- lp - lp[ref_i]
    data.frame(x = grid, HR = exp(lp), lo = exp(lp - 1.96 * se), hi = exp(lp + 1.96 * se))
  }

  all_cov <- unique(unlist(models, use.names = FALSE))
  rcs_df <- list()
  rcs_p <- list()
  for (nm in names(dbs)) {
    d <- as.data.frame(dbs[[nm]])
    if (!time_var %in% names(d) && "futime_years" %in% names(d)) d[[time_var]] <- d$futime_years
    if (!event_var %in% names(d) && "fustatus" %in% names(d)) d[[event_var]] <- d$fustatus
    need <- c(time_var, event_var, exposure, all_cov)
    weighted <- nm %in% survey_dbs
    if (weighted) need <- c(need, survey_weight, survey_psu, survey_strata)
    need <- intersect(need, names(d))
    d <- d[stats::complete.cases(d[, need]) & d[[time_var]] > 0, ]
    for (v in intersect(factor_vars, names(d))) d[[v]] <- factor(d[[v]])
    kts <- as.numeric(stats::quantile(d[[exposure]], knot_probs, na.rm = TRUE))
    bk <- range(d[[exposure]], na.rm = TRUE)
    B <- as.matrix(splines::ns(d[[exposure]], knots = kts, Boundary.knots = bk))
    colnames(B) <- paste0("sp", seq_len(ncol(B)))
    R <- qr.resid(qr(cbind(1, d[[exposure]])), B)
    keep <- apply(R, 2, stats::sd) > 1e-8
    R <- R[, keep, drop = FALSE]
    qrR <- qr(R)
    R <- R[, qrR$pivot[seq_len(qrR$rank)], drop = FALSE]
    colnames(R) <- paste0("nl", seq_len(ncol(R)))
    d <- cbind(d, B, R)
    ref <- d[which.min(abs(d[[exposure]] - stats::median(d[[exposure]]))), ]
    grid <- seq(max(x_lim[1], min(d[[exposure]])), min(x_lim[2], max(d[[exposure]])), length.out = 80)
    message(sprintf("%s n=%d events=%d", nm, nrow(d), sum(d[[event_var]] == 1)))
    for (mn in names(models)) {
      covs <- intersect(models[[mn]], names(d))
      sp <- colnames(B)
      nl <- colnames(R)
      f_sp <- stats::as.formula(paste(
        sprintf("Surv(%s, %s) ~", time_var, event_var),
        paste(c(sp, covs), collapse = " + ")
      ))
      f_lin <- stats::as.formula(paste(
        sprintf("Surv(%s, %s) ~", time_var, event_var),
        paste(c(exposure, covs), collapse = " + ")
      ))
      f_nl <- stats::as.formula(paste(
        sprintf("Surv(%s, %s) ~", time_var, event_var),
        paste(c(exposure, nl, covs), collapse = " + ")
      ))
      if (weighted) {
        des <- survey::svydesign(
          ids = stats::as.formula(paste("~", survey_psu)),
          strata = stats::as.formula(paste("~", survey_strata)),
          weights = stats::as.formula(paste("~", survey_weight)),
          data = d, nest = TRUE
        )
        fit <- survey::svycoxph(f_sp, design = des)
        fit_lin <- survey::svycoxph(f_lin, design = des)
        fit_nl <- survey::svycoxph(f_nl, design = des)
      } else {
        fit <- survival::coxph(f_sp, data = d, ties = "efron")
        fit_lin <- survival::coxph(f_lin, data = d, ties = "efron")
        fit_nl <- survival::coxph(f_nl, data = d, ties = "efron")
      }
      # P-overall = 样条整体；P-linear = 连续线性项（对齐 Table 3 per-SD 口径）；
      # P-nonlinear = 非线性增量。图面默认报 P-linear + P-nonlinear（Hip/Nature P0）。
      p_ov <- wald(fit, "sp")
      p_lin <- wald(fit_lin, exposure)
      p_nl <- wald(fit_nl, "nl")
      message(sprintf(
        "  %s P-overall %s P-linear %s P-nonlinear %s",
        mn, fmt_p(p_ov), fmt_p(p_lin), fmt_p(p_nl)
      ))
      nd <- ref[rep(1, length(grid)), ]
      nd[[exposure]] <- grid
      Bg <- as.matrix(splines::ns(grid, knots = kts, Boundary.knots = bk))
      colnames(Bg) <- sp
      for (j in sp) nd[[j]] <- Bg[, j]
      cv <- curve_one(fit, grid, nd, ref_value)
      names(cv)[names(cv) == "x"] <- "hours"
      cv$database <- nm
      cv$model <- mn
      rcs_df[[length(rcs_df) + 1L]] <- cv
      rcs_p[[length(rcs_p) + 1L]] <- data.frame(
        database = nm, model = mn,
        p_overall = p_ov, p_linear = p_lin, p_nonlinear = p_nl,
        stringsAsFactors = FALSE
      )
    }
  }
  rcs <- do.call(rbind, rcs_df)
  rp <- do.call(rbind, rcs_p)
  rp$lab <- paste0(
    "P-linear ", vapply(rp$p_linear, fmt_p, character(1)),
    "\nP-nonlinear ", vapply(rp$p_nonlinear, fmt_p, character(1))
  )
  rcs$database <- factor(rcs$database, levels = db_levels)
  rp$database <- factor(rp$database, levels = db_levels)
  rcs$model <- factor(rcs$model, levels = names(models))
  rp$model <- factor(rp$model, levels = names(models))
  list(
    rcs = rcs, rp = rp, exposure = exposure, ref_value = ref_value,
    models = models, survey_dbs = survey_dbs
  )
}

rcs_cox_models_panel_plot <- function(
    fit,
    which_models = "Model 1",
    show_model_strip = NULL,
    title = "Restricted cubic spline",
    xlab = NULL,
    ylab = NULL,
    vlines = NULL,
    subtitle = NULL) {
  rcs <- fit$rcs
  rp <- fit$rp
  if (!is.null(which_models) && length(which_models)) {
    rcs <- rcs[as.character(rcs$model) %in% which_models, , drop = FALSE]
    rp <- rp[as.character(rp$model) %in% which_models, , drop = FALSE]
  }
  if (is.null(show_model_strip)) {
    show_model_strip <- length(unique(as.character(rcs$model))) > 1L
  }
  if (is.null(xlab)) {
    xlab <- paste0(gsub("_", " ", fit$exposure %||% "Exposure"), ", hours")
  }
  if (is.null(ylab)) {
    ylab <- sprintf("Hazard ratio (reference %s)", format(fit$ref_value %||% 7.5))
  }
  p <- ggplot2::ggplot(rcs, ggplot2::aes(hours, HR)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo, ymax = hi), fill = "#9ecae1", alpha = 0.45) +
    ggplot2::geom_line(color = "#08519c", linewidth = 0.7) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2) +
    ggplot2::geom_text(
      data = rp, ggplot2::aes(x = -Inf, y = Inf, label = lab),
      inherit.aes = FALSE, hjust = -0.05, vjust = 1.2, size = 2.8
    ) +
    ggplot2::labs(x = xlab, y = ylab, title = title, subtitle = subtitle) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      strip.background = ggplot2::element_rect(fill = "grey95"),
      strip.text = ggplot2::element_text(face = "bold")
    )
  if (!is.null(vlines) && length(vlines)) {
    p <- p + ggplot2::geom_vline(xintercept = vlines, linetype = 3, color = "grey40")
  }
  if (isTRUE(show_model_strip)) {
    p <- p + ggplot2::facet_grid(database ~ model, scales = "free_y")
  } else {
    p <- p + ggplot2::facet_wrap(~database, nrow = 1, scales = "free_y")
  }
  p
}

# 旧课题名兼容
pv2_rcs_table3 <- function(dbs, ...) rcs_cox_models_panel_fit(dbs, ...)
pv2_plot_rcs_table3 <- function(fit, ...) {
  rcs_cox_models_panel_plot(
    fit,
    which_models = "Model 1",
    show_model_strip = FALSE,
    title = "Restricted cubic spline of sleep duration and all-cause mortality",
    xlab = "Sleep duration, hours",
    ylab = "Hazard ratio (reference 7.5 h)",
    vlines = c(7, 9),
    ...
  )
}
