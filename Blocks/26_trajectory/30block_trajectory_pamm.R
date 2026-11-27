###############################################################################
#  trajectory_pamm — 连续复合指标时变非线性关联（PAMM；对齐 fcimb Fig5/6）
#
#  依据：piece-wise exponential additive mixed models（R 包 pammtools + mgcv）
#  公开作者脚本：未找到；实现走 pammtools 官方接口。
#
#  输出：
#    - 连续暴露 × 时间交互的平滑曲面/切片图（Fig5a–d 角色）
#    - 阈值异常（发现集锁定 lo/hi 分位）+ 暴露时间占比 + 累积负担 → Cox HR 表
#
#  config$trajectory_pamm = list(
#    index_vars = NULL,                 # NULL → 当前 Index / dual_safe 批跑 patch
#    discovery_db = "mimic",
#    threshold_probs = c(0.05, 0.95),    # 发现集锁定；过稀可降级 c(0.10,0.90)
#    threshold_fallback_probs = c(0.10, 0.90),
#    min_abnormal_person_days = 50L,
#    max_followup = 28L,
#    cut_points = seq(0, 28, by = 1),
#    survival_time_var = NULL,
#    survival_event_var = NULL,
#    covariate_vars = NULL,             # NULL → JLCM survival 协变量 / Model2
#    lock_thresholds_from_discovery = TRUE,
#    validation_apply_locked = TRUE,
#    export_figures = TRUE
#  )
#
#  register_block: "trajectory_pamm"
###############################################################################

.tpamm_is_discovery <- function(ctx, bl) {
  db <- tolower(as.character(ctx$config$project$database %||% ""))
  disc <- tolower(as.character(bl$discovery_db %||% "mimic"))
  grepl(disc, db, fixed = TRUE)
}

.tpamm_resolve_index <- function(ctx, bl) {
  ix <- bl$index_vars %||% ctx$config$trajectory_jlcm$index_vars %||%
    ctx$config$survival$index_var %||% character(0)
  as.character(ix)[1L]
}

.tpamm_covars <- function(ctx, bl, data) {
  covs <- bl$covariate_vars
  if (is.null(covs) || !length(covs)) {
    covs <- ctx$config$trajectory_jlcm$covariate_vars %||%
      ctx$results$Model2Factors %||%
      intersect(c("Age", "Gender"), names(data))
  }
  intersect(as.character(covs), names(data))
}

.tpamm_long_from_wide <- function(index_df, id_col, index_name, time_start = 1L, time_end = 28L) {
  day_cols <- paste0(index_name, "_", seq.int(time_start, time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("trajectory_pamm: 宽表缺少 ", index_name, "_day 列", call. = FALSE)
  rows <- lapply(day_cols, function(dc) {
    day <- as.integer(sub(paste0("^", index_name, "_"), "", dc))
    data.frame(
      id = as.character(index_df[[id_col]]),
      time_day = day,
      expo = suppressWarnings(as.numeric(index_df[[dc]])),
      stringsAsFactors = FALSE
    )
  })
  long <- do.call(rbind, rows)
  long <- long[is.finite(long$expo), , drop = FALSE]
  names(long)[1L] <- id_col
  long
}

.tpamm_lock_thresholds <- function(expo, probs = c(0.05, 0.95)) {
  q <- as.numeric(stats::quantile(expo, probs = probs, na.rm = TRUE, names = FALSE, type = 7))
  list(lo = q[1L], hi = q[2L], probs = probs)
}

.tpamm_event_01 <- function(x, cfg = NULL) {
  # 插补后结局常被 relabel 为 Survivor / Non-survivor；禁止 status == 1L
  if (exists("pipeline_outcome_as_01", mode = "function")) {
    return(as.integer(pipeline_outcome_as_01(x, cfg)))
  }
  if (is.numeric(x) || is.integer(x) || is.logical(x)) return(as.integer(as.numeric(x) == 1))
  xs <- trimws(as.character(x))
  as.integer(xs %in% c("1", "Non-survivor", "Dead", "dead", "Yes") |
               grepl("non.?surv|dead|expir|death", xs, ignore.case = TRUE))
}

.tpamm_burden_table <- function(long, base, id_col, thr, time_var, event_var, covs, max_followup,
                                cfg = NULL) {
  # person-level metrics aligned with fcimb S9/S10:
  # continuous mean, ever beyond P5/P95, proportion of time, cumulative deviation
  agg <- stats::aggregate(
    expo ~ get(id_col), data = long,
    FUN = function(z) {
      n <- length(z)
      c(
        mean_expo = mean(z),
        ever_lo = as.integer(any(z <= thr$lo)),
        ever_hi = as.integer(any(z >= thr$hi)),
        prop_lo = mean(z <= thr$lo),
        prop_hi = mean(z >= thr$hi),
        cum_lo = sum(pmax(0, thr$lo - z)),
        cum_hi = sum(pmax(0, z - thr$hi)),
        n_obs = n
      )
    }
  )
  # aggregate with cbind returns matrix columns oddly; rebuild
  idv <- as.character(agg[[1L]])
  mat <- as.matrix(agg[[2L]])
  bur <- data.frame(
    id = idv,
    mean_expo = as.numeric(mat[, "mean_expo"]),
    ever_lo = as.numeric(mat[, "ever_lo"]),
    ever_hi = as.numeric(mat[, "ever_hi"]),
    prop_lo = as.numeric(mat[, "prop_lo"]),
    prop_hi = as.numeric(mat[, "prop_hi"]),
    cum_lo = as.numeric(mat[, "cum_lo"]),
    cum_hi = as.numeric(mat[, "cum_hi"]),
    n_obs = as.numeric(mat[, "n_obs"]),
    stringsAsFactors = FALSE
  )
  names(bur)[1L] <- id_col
  dd <- merge(base, bur, by = id_col, all.x = FALSE)
  dd$time <- pmin(as.numeric(dd[[time_var]]), max_followup)
  dd$event <- .tpamm_event_01(dd[[event_var]], cfg)
  dd <- dd[is.finite(dd$time) & dd$time > 0, , drop = FALSE]

  fit_one <- function(term, scale = 1) {
    dd$x <- as.numeric(dd[[term]]) * scale
    fml <- if (length(covs)) {
      stats::as.formula(paste("survival::Surv(time, event) ~ x +", paste(covs, collapse = " + ")))
    } else {
      survival::Surv(time, event) ~ x
    }
    m <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(m)) {
      return(data.frame(metric = term, HR = NA_real_, lo = NA_real_, hi = NA_real_,
                        p = NA_real_, n = nrow(dd), note = "fit_failed",
                        stringsAsFactors = FALSE))
    }
    sm <- summary(m)$coefficients
    ci <- tryCatch(exp(stats::confint(m)["x", ]), error = function(e) c(NA_real_, NA_real_))
    hr <- unname(exp(sm["x", "coef"]))
    lo <- unname(ci[1L]); hi <- unname(ci[2L])
    note <- ""
    # sparse low-burden / separation → mark unstable for pub tables
    if (is.finite(hr) && (hr < 0.01 || hr > 100 ||
                          (is.finite(lo) && is.finite(hi) &&
                           ((hi / pmax(lo, 1e-12)) > 1e4 || hi > 1e4)))) {
      note <- "NE_unstable"
    }
    data.frame(
      metric = term,
      HR = hr,
      lo = lo,
      hi = hi,
      p = unname(sm["x", "Pr(>|z|)"]),
      n = nrow(dd),
      note = note,
      stringsAsFactors = FALSE
    )
  }

  rbind(
    fit_one("mean_expo", scale = 100), # per 0.01 on raw WPR mean
    fit_one("ever_lo", scale = 1),
    fit_one("ever_hi", scale = 1),
    fit_one("prop_lo", scale = 20),  # per 5% → scale 20 on proportion-in-[0,1]
    fit_one("prop_hi", scale = 20),
    fit_one("cum_lo", scale = 1),
    fit_one("cum_hi", scale = 1)
  )
}

.tpamm_fill_expo_locf <- function(x) {
  ok <- which(is.finite(x))
  if (!length(ok)) return(x)
  for (i in seq_along(x)) {
    if (is.finite(x[i])) next
    j <- ok[ok <= i]
    if (length(j)) x[i] <- x[max(j)]
    else {
      j <- ok[ok >= i]
      if (length(j)) x[i] <- x[min(j)]
    }
  }
  x
}

.tpamm_build_ped <- function(surv_df, long, id_col, covs, cuts, max_fu) {
  # 稳健路径：先 as_ped(生存)，再按 tend→time_day 合并时变暴露（避免 concurrent 行数错位）
  common <- intersect(as.character(surv_df[[id_col]]), unique(as.character(long[[id_col]])))
  surv_df <- surv_df[as.character(surv_df[[id_col]]) %in% common, , drop = FALSE]
  long <- long[as.character(long[[id_col]]) %in% common, , drop = FALSE]
  long <- long[!duplicated(long[, c(id_col, "time_day")]), , drop = FALSE]
  ped <- pammtools::as_ped(
    data = surv_df,
    formula = survival::Surv(time, status) ~ .,
    cut = cuts,
    id = id_col
  )
  ped <- as.data.frame(ped)
  ped$time_day <- pmax(1L, as.integer(round(as.numeric(ped$tend))))
  ped$time_day[ped$time_day > as.integer(max_fu)] <- as.integer(max_fu)
  ped <- merge(ped, long[, c(id_col, "time_day", "expo"), drop = FALSE],
               by = c(id_col, "time_day"), all.x = TRUE)
  ped <- ped[order(ped[[id_col]], ped$tend), , drop = FALSE]
  ped$expo <- ave(ped$expo, ped[[id_col]], FUN = .tpamm_fill_expo_locf)
  ped <- ped[is.finite(ped$expo) & is.finite(ped$offset), , drop = FALSE]
  ped
}

.tpamm_fit_smooth <- function(ped, covs) {
  # pammtools::as_ped 的 offset 已是 log(dt)；禁止再 log(offset)（会 NaN → GAM 失败）
  rhs_cov <- if (length(covs)) paste("+", paste(covs, collapse = " + ")) else ""
  fml <- stats::as.formula(paste0(
    "ped_status ~ s(tend, k = 8) + s(expo, k = 10) + ti(tend, expo, k = c(5, 5))",
    rhs_cov
  ))
  mgcv::gam(fml, data = ped, family = stats::poisson(), offset = ped$offset, method = "REML")
}

.tpamm_predict_hr <- function(fit, nd, nd_ref, covs, ped) {
  for (cv in covs) {
    if (!cv %in% names(nd)) {
      if (is.numeric(ped[[cv]])) {
        med <- stats::median(as.numeric(ped[[cv]]), na.rm = TRUE)
        nd[[cv]] <- med
        nd_ref[[cv]] <- med
      } else {
        tab <- sort(table(ped[[cv]]), decreasing = TRUE)
        nd[[cv]] <- names(tab)[1L]
        nd_ref[[cv]] <- names(tab)[1L]
      }
    }
  }
  if (!"offset" %in% names(nd)) nd$offset <- 0
  if (!"offset" %in% names(nd_ref)) nd_ref$offset <- 0
  # 强制 mgcv::predict.gam：部分落盘 gam 缺 qr 时 stats::predict.glm 会失败
  .pred <- function(object, newdata, se.fit = FALSE) {
    if (inherits(object, "gam") && requireNamespace("mgcv", quietly = TRUE)) {
      mgcv::predict.gam(object, newdata = newdata, type = "link", se.fit = se.fit)
    } else {
      stats::predict(object, newdata = newdata, type = "link", se.fit = se.fit)
    }
  }
  pr <- .pred(fit, nd, se.fit = TRUE)
  pr0 <- as.numeric(.pred(fit, nd_ref, se.fit = FALSE))
  data.frame(
    fit = as.numeric(pr$fit),
    se = as.numeric(pr$se.fit),
    hr = exp(as.numeric(pr$fit) - pr0),
    hr_lo = exp(as.numeric(pr$fit) - pr0 - 1.96 * as.numeric(pr$se.fit)),
    hr_hi = exp(as.numeric(pr$fit) - pr0 + 1.96 * as.numeric(pr$se.fit)),
    stringsAsFactors = FALSE
  )
}

.tpamm_draw_fcimb_panels <- function(fit, ped, covs, Index, thr, landmarks, expo_levels,
                                     out_pdf, width = 10, height = 8,
                                     hr_ylab = "HR for in-hospital mortality") {
  # 对齐 fcimb Fig5/6：(a) HR~expo (b) 分层 landmark (c) HR~day (d) 分层 expo
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("trajectory_pamm 作图需要 ggplot2", call. = FALSE)
  }
  hr_ylab <- as.character(hr_ylab %||% "HR for in-hospital mortality")[1L]
  covs <- intersect(covs, names(ped))
  ref_expo <- as.numeric(stats::median(ped$expo, na.rm = TRUE))
  ref_day <- as.numeric(stats::median(ped$tend, na.rm = TRUE))
  expo_grid <- seq(
    as.numeric(stats::quantile(ped$expo, 0.02, na.rm = TRUE)),
    as.numeric(stats::quantile(ped$expo, 0.98, na.rm = TRUE)),
    length.out = 80L
  )
  day_grid <- seq(1, max(ped$tend, na.rm = TRUE), by = 0.5)
  landmarks <- as.numeric(landmarks)
  landmarks <- landmarks[is.finite(landmarks)]
  if (!length(expo_levels) || all(!is.finite(as.numeric(expo_levels)))) {
    expo_levels <- as.numeric(stats::quantile(ped$expo, c(0.1, 0.5, 0.9), na.rm = TRUE))
  }
  expo_levels <- as.numeric(expo_levels)
  names(expo_levels) <- paste0(Index, " = ", signif(expo_levels, 3))

  # (a) overall at ref_day
  nd_a <- data.frame(tend = ref_day, expo = expo_grid)
  nd_a0 <- data.frame(tend = ref_day, expo = ref_expo)
  ha <- .tpamm_predict_hr(fit, nd_a, nd_a0, covs, ped)
  df_a <- cbind(nd_a, ha)

  # (b) by landmark
  df_b <- do.call(rbind, lapply(landmarks, function(lm) {
    nd <- data.frame(tend = lm, expo = expo_grid)
    nd0 <- data.frame(tend = lm, expo = ref_expo)
    cbind(nd, .tpamm_predict_hr(fit, nd, nd0, covs, ped),
          landmark = paste0("Days = ", lm))
  }))

  # (c) time-varying at ref expo
  nd_c <- data.frame(tend = day_grid, expo = ref_expo)
  nd_c0 <- data.frame(tend = min(day_grid), expo = ref_expo)
  hc <- .tpamm_predict_hr(fit, nd_c, nd_c0, covs, ped)
  df_c <- cbind(nd_c, hc)

  # (d) by expo level
  df_d <- do.call(rbind, lapply(seq_along(expo_levels), function(i) {
    xv <- expo_levels[[i]]
    nd <- data.frame(tend = day_grid, expo = xv)
    nd0 <- data.frame(tend = min(day_grid), expo = ref_expo)
    cbind(nd, .tpamm_predict_hr(fit, nd, nd0, covs, ped),
          expo_lab = names(expo_levels)[i])
  }))

  cols_lm <- c("#009E73", "#E69F00", "#CC79A7", "#56B4E9", "#0072B2")
  cols_ex <- cols_lm
  # 发表字体 Times 系（cairo 优先 Liberation/DejaVu Serif；禁 NimbusSans/Helvetica）
  .font <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family()
  } else {
    "Liberation Serif"
  }
  theme_p <- ggplot2::theme_classic(base_size = 11, base_family = .font) +
    ggplot2::theme(
      legend.position = "top",
      plot.title = ggplot2::element_text(face = "bold", size = 10, family = .font),
      axis.title = ggplot2::element_text(size = 10, family = .font),
      axis.text = ggplot2::element_text(family = .font),
      legend.text = ggplot2::element_text(family = .font)
    )

  p_a <- ggplot2::ggplot(df_a, ggplot2::aes(expo, hr)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = hr_lo, ymax = hr_hi), fill = "#E69F00", alpha = 0.25) +
    ggplot2::geom_line(color = "#E69F00", linewidth = 1) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::labs(
      title = "(a) Adjusted relationship between time-varying exposure and mortality",
      x = Index, y = hr_ylab
    ) + theme_p

  p_b <- ggplot2::ggplot(df_b, ggplot2::aes(expo, hr, color = landmark, fill = landmark)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = hr_lo, ymax = hr_hi), alpha = 0.15, color = NA) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::scale_color_manual(values = cols_lm[seq_along(unique(df_b$landmark))]) +
    ggplot2::scale_fill_manual(values = cols_lm[seq_along(unique(df_b$landmark))]) +
    ggplot2::labs(
      title = "(b) Stratified by landmark time points",
      x = Index, y = hr_ylab, color = NULL, fill = NULL
    ) + theme_p

  p_c <- ggplot2::ggplot(df_c, ggplot2::aes(tend, hr)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = hr_lo, ymax = hr_hi), fill = "#E69F00", alpha = 0.25) +
    ggplot2::geom_line(color = "#E69F00", linewidth = 1) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::labs(
      title = "(c) Time-varying effect of exposure on mortality",
      x = "Days", y = hr_ylab
    ) + theme_p

  p_d <- ggplot2::ggplot(df_d, ggplot2::aes(tend, hr, color = expo_lab, fill = expo_lab)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = hr_lo, ymax = hr_hi), alpha = 0.12, color = NA) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::scale_color_manual(values = cols_ex[seq_along(unique(df_d$expo_lab))]) +
    ggplot2::scale_fill_manual(values = cols_ex[seq_along(unique(df_d$expo_lab))]) +
    ggplot2::labs(
      title = "(d) Stratified by exposure levels",
      x = "Days", y = hr_ylab, color = NULL, fill = NULL
    ) + theme_p

  if (requireNamespace("patchwork", quietly = TRUE)) {
    pp <- (p_a | p_b) / (p_c | p_d)
  } else {
    # fallback: save 4-page pdf（Times 系）
    grDevices::cairo_pdf(out_pdf, width = width, height = height / 2, family = .font)
    print(p_a); print(p_b); print(p_c); print(p_d)
    grDevices::dev.off()
    return(invisible(out_pdf))
  }
  ggplot2::ggsave(
    out_pdf, pp, width = width, height = height,
    device = function(...) grDevices::cairo_pdf(..., family = .font)
  )
  invisible(out_pdf)
}

# 对齐 fcimb Supplementary Figure 3：Days × 暴露 Log(HR) 填色等高面（单库一页）
.tpamm_draw_fcimb_loghr_contour <- function(fit, ped = NULL, Index = "Index",
                                            out_pdf, width = 7.2, height = 4.6) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("trajectory_pamm contour 需要 ggplot2", call. = FALSE)
  }
  mf <- if (!is.null(ped) && is.data.frame(ped) && nrow(ped)) ped else fit$model
  tend_rng <- range(mf$tend, na.rm = TRUE)
  expo_q <- as.numeric(stats::quantile(mf$expo, c(0.02, 0.98), na.rm = TRUE))
  days <- seq(0, 28, length.out = 57L)
  days_pred <- pmin(pmax(days, tend_rng[1]), tend_rng[2])
  expos <- seq(expo_q[1], expo_q[2], length.out = 80L)
  grid <- expand.grid(tend = days_pred, expo = expos)
  eta <- as.numeric(stats::predict(fit, newdata = grid, type = "link"))
  loghr <- eta - min(eta, na.rm = TRUE)
  loghr[!is.finite(loghr)] <- NA_real_
  df <- data.frame(day = rep(days, times = length(expos)), expo = grid$expo, loghr = loghr)
  vmax <- as.numeric(stats::quantile(df$loghr, 0.995, na.rm = TRUE))
  if (!is.finite(vmax) || vmax <= 0) vmax <- max(df$loghr, na.rm = TRUE)
  cols <- c("#2166AC", "#67A9CF", "#D1E5F0", "#F7F7F7", "#FDDBC7", "#EF8A62", "#B2182B")
  .font <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family()
  } else {
    "Liberation Serif"
  }
  p <- ggplot2::ggplot(df, ggplot2::aes(day, expo, z = loghr)) +
    ggplot2::geom_contour_filled(bins = 16) +
    ggplot2::geom_contour(color = "black", linewidth = 0.35, bins = 8) +
    ggplot2::scale_fill_manual(
      values = grDevices::colorRampPalette(cols)(16),
      name = "Log(HR)",
      guide = ggplot2::guide_colorsteps(barwidth = 0.6, barheight = 8)
    ) +
    ggplot2::coord_cartesian(xlim = c(0, 28), expand = FALSE) +
    ggplot2::scale_x_continuous(breaks = c(0, 7, 14, 21, 28)) +
    ggplot2::labs(x = "Days", y = Index) +
    ggplot2::theme_classic(base_size = 11, base_family = .font) +
    ggplot2::theme(
      legend.position = "right",
      axis.title = ggplot2::element_text(face = "bold", family = .font),
      axis.text = ggplot2::element_text(family = .font),
      legend.text = ggplot2::element_text(family = .font)
    )
  ggplot2::ggsave(
    out_pdf, p, width = width, height = height,
    device = function(...) grDevices::cairo_pdf(..., family = .font)
  )
  invisible(out_pdf)
}

block_trajectory_pamm <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  bl <- ctx$config$trajectory_pamm %||% list()
  if (!requireNamespace("pammtools", quietly = TRUE))
    stop("trajectory_pamm: 请安装 pammtools", call. = FALSE)
  if (!requireNamespace("mgcv", quietly = TRUE))
    stop("trajectory_pamm: 请安装 mgcv", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE))
    stop("trajectory_pamm: 请安装 survival", call. = FALSE)

  if (is.null(ctx$results$trajectory_pamm) || !is.list(ctx$results$trajectory_pamm))
    ctx$results$trajectory_pamm <- list()

  Index <- .tpamm_resolve_index(ctx, bl)
  if (!nzchar(Index)) stop("trajectory_pamm: 未解析到 Index", call. = FALSE)

  id_col <- ctx$config$data$id_column %||% "subject_id"
  time_var <- bl$survival_time_var %||% ctx$config$survival$time_var %||% "survival_time_28d"
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% "survival_28d"
  max_fu <- as.integer(bl$max_followup %||% 28L)
  cuts <- as.numeric(bl$cut_points %||% seq(0, max_fu, by = 1))

  base <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(base) || !nrow(base)) stop("trajectory_pamm: 无基线/插补数据", call. = FALSE)
  if (!all(c(time_var, event_var) %in% names(base)))
    stop("trajectory_pamm: 缺少生存列 ", time_var, " / ", event_var, call. = FALSE)

  # wide index from JLCM rawdata or results
  wide_path <- NULL
  tpl <- ctx$config$trajectory_jlcm$rawdata_path_template %||% NULL
  if (!is.null(tpl)) {
    db_tag <- if (grepl("mimic", tolower(ctx$config$project$database %||% ""), fixed = TRUE)) "mimic" else "eicu"
    wide_path <- gsub("\\{Index\\}", Index, gsub("\\{db\\}", db_tag, tpl))
  }
  index_df <- NULL
  if (!is.null(wide_path) && file.exists(wide_path)) {
    e <- new.env(parent = emptyenv())
    load(wide_path, envir = e)
    obj <- ctx$config$trajectory_jlcm$rawdata_obj %||% "index_df"
    index_df <- e[[obj]]
  }
  if (is.null(index_df)) {
    stop("trajectory_pamm: 找不到纵向宽表 ", wide_path %||% "(no path)", call. = FALSE)
  }
  if (!id_col %in% names(index_df) && "subject_id" %in% names(index_df)) id_col <- "subject_id"
  if (!id_col %in% names(index_df) && "ID" %in% names(index_df)) {
    index_df[[id_col]] <- as.character(index_df$ID)
  }

  long <- .tpamm_long_from_wide(index_df, id_col, Index, 1L, max_fu)
  covs <- .tpamm_covars(ctx, bl, base)

  # thresholds: discovery locks; validation applies locked file
  out_tab <- file.path(ctx$output_dir_tables %||% file.path(ctx$config$project$output_dir, "Tables"), "PAMM")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  thr_path <- file.path(out_tab, paste0("PAMM_thresholds_", Index, ".rds"))
  root_thr <- file.path(ctx$root_output_dir %||% ctx$config$project$output_dir, "Tables", "PAMM",
                        paste0("PAMM_thresholds_", Index, "_locked.rds"))

  is_disc <- .tpamm_is_discovery(ctx, bl)
  probs <- as.numeric(bl$threshold_probs %||% c(0.05, 0.95))
  fb_probs <- as.numeric(bl$threshold_fallback_probs %||% c(0.10, 0.90))
  min_abn <- as.integer(bl$min_abnormal_person_days %||% 50L)

  if (is_disc || !isTRUE(bl$validation_apply_locked %||% TRUE)) {
    thr <- .tpamm_lock_thresholds(long$expo, probs = probs)
    n_abn <- sum(long$expo <= thr$lo | long$expo >= thr$hi, na.rm = TRUE)
    if (is.finite(n_abn) && n_abn < min_abn) {
      cli::cli_alert_warning(
        "trajectory_pamm [{Index}]: P{100*probs[1]}/P{100*probs[2]} 异常人天={n_abn} < {min_abn}，降级 P{100*fb_probs[1]}/P{100*fb_probs[2]}"
      )
      thr <- .tpamm_lock_thresholds(long$expo, probs = fb_probs)
      thr$fallback <- TRUE
    } else thr$fallback <- FALSE
    saveRDS(thr, thr_path)
    dir.create(dirname(root_thr), recursive = TRUE, showWarnings = FALSE)
    saveRDS(thr, root_thr)
  } else {
    # 外验：config 注入路径优先；再扫同指标 mimic / 【failed】mimic 的 locked / 未加锁文件
    out_ix <- dirname(ctx$config$project$output_dir %||% ".")  # .../by_index/NLPR
    by_index <- dirname(out_ix)
    ix_nm <- basename(out_ix)
    disc_db <- as.character(bl$discovery_db %||% "mimic")[1L]
    thr_fns <- c(
      paste0("PAMM_thresholds_", Index, "_locked.rds"),
      paste0("PAMM_thresholds_", Index, ".rds")
    )
    sibling_roots <- unique(c(
      file.path(by_index, ix_nm, disc_db),
      file.path(by_index, paste0("\u3010success\u3011", ix_nm), disc_db),
      file.path(by_index, paste0("\u3010failed\u3011", ix_nm), disc_db),
      file.path(dirname(out_ix), disc_db)
    ))
    sibling_hits <- character(0)
    for (sr in sibling_roots) {
      for (fn in thr_fns) {
        sibling_hits <- c(
          sibling_hits,
          file.path(sr, "Tables", "PAMM", fn),
          file.path(sr, "step25_trajectory_pamm", "Tables", "PAMM", fn)
        )
      }
    }
    lock_candidates <- c(bl$locked_threshold_path %||% "", root_thr, sibling_hits)
    lock_candidates <- unique(lock_candidates[nzchar(lock_candidates) & file.exists(lock_candidates)])
    if (!length(lock_candidates))
      stop("trajectory_pamm: 外验缺少发现集锁定阈值文件 ", root_thr, call. = FALSE)
    thr <- readRDS(lock_candidates[[1L]])
    cli::cli_alert_info("trajectory_pamm [{Index}]: 使用发现集锁定阈值 lo={thr$lo}, hi={thr$hi}")
  }

  # ped data for PAMM
  surv_df <- base[, c(id_col, time_var, event_var, covs), drop = FALSE]
  names(surv_df)[names(surv_df) == time_var] <- "time"
  names(surv_df)[names(surv_df) == event_var] <- "status"
  surv_df$time <- pmin(as.numeric(surv_df$time), max_fu)
  n_ev_raw <- sum(.tpamm_event_01(base[[event_var]], ctx$config), na.rm = TRUE)
  surv_df$status <- .tpamm_event_01(surv_df$status, ctx$config)
  surv_df <- surv_df[is.finite(surv_df$time) & surv_df$time > 0, , drop = FALSE]
  n_ev <- sum(surv_df$status == 1L, na.rm = TRUE)
  cli::cli_alert_info(
    "trajectory_pamm [{Index}]: n={nrow(surv_df)}, events={n_ev} (raw_encode_check={n_ev_raw})"
  )
  if (!n_ev) {
    stop(
      "trajectory_pamm: 编码后仍无事件。event_var=", event_var,
      " levels=", paste(unique(as.character(base[[event_var]])), collapse = ","),
      call. = FALSE
    )
  }

  # 数值协变量（因子进 GAM 易炸）
  for (cv in covs) {
    if (!is.numeric(surv_df[[cv]])) {
      surv_df[[cv]] <- suppressWarnings(as.numeric(as.character(surv_df[[cv]])))
    }
  }
  covs <- covs[vapply(covs, function(cv) is.numeric(surv_df[[cv]]), logical(1))]

  ped <- tryCatch(
    .tpamm_build_ped(surv_df, long, id_col, covs, cuts, max_fu),
    error = function(e) {
      cli::cli_alert_danger("trajectory_pamm PED 构建失败: {conditionMessage(e)}")
      NULL
    }
  )
  if (is.null(ped) || !nrow(ped))
    stop("trajectory_pamm: PED 为空", call. = FALSE)

  fit <- tryCatch(.tpamm_fit_smooth(ped, intersect(covs, names(ped))), error = function(e) {
    cli::cli_alert_danger("trajectory_pamm GAM 失败: {conditionMessage(e)}")
    NULL
  })

  bur <- .tpamm_burden_table(long, base, id_col, thr, time_var, event_var, covs, max_fu,
                            cfg = ctx$config)
  bur$Index <- Index
  bur$db <- ctx$config$project$database %||% ""
  utils::write.csv(bur, file.path(out_tab, paste0("Table_PAMM_burden_HR_", Index, ".csv")),
                   row.names = FALSE)

  fig_dir <- file.path(ctx$output_dir_figures %||% file.path(ctx$config$project$output_dir, "Figures"))
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  # 落盘 gam 供重绘
  if (!is.null(fit)) {
    saveRDS(
      list(gam = fit, ped_n = nrow(ped), covs = intersect(covs, names(ped)),
           thr = thr, Index = Index, is_discovery = is_disc),
      file.path(out_tab, paste0("PAMM_gam_", Index, ".rds"))
    )
  }

  if (!is.null(fit) && isTRUE(bl$export_figures %||% TRUE)) {
    landmarks <- as.numeric(bl$plot_landmarks %||% c(3, 5, 12))
    # day2 与 dynpred 同理可留；PAMM 对 tend 平滑通常可估
    expo_levels <- as.numeric(bl$plot_expo_levels %||%
      stats::quantile(ped$expo, c(0.1, 0.5, 0.9), na.rm = TRUE))
    pdf_path <- file.path(fig_dir, paste0("Figure PAMM ", Index, " fcimb panels.pdf"))
    tryCatch({
      .tpamm_draw_fcimb_panels(
        fit = fit, ped = ped, covs = intersect(covs, names(ped)),
        Index = Index, thr = thr, landmarks = landmarks,
        expo_levels = expo_levels, out_pdf = pdf_path,
        hr_ylab = bl$hr_ylab %||% "HR for in-hospital mortality"
      )
      cli::cli_alert_success("trajectory_pamm 图已写: {.file {basename(pdf_path)}}")
    }, error = function(e) {
      cli::cli_alert_warning("trajectory_pamm 作图失败: {conditionMessage(e)}")
    })
  }

  ctx$results$trajectory_pamm[[Index]] <- list(
    thresholds = thr,
    burden_hr = bur,
    gam = fit,
    n_long = nrow(long),
    n_ped = if (!is.null(ped)) nrow(ped) else NA_integer_,
    is_discovery = is_disc
  )
  cli::cli_alert_success("trajectory_pamm [{Index}] 完成（discovery={is_disc}）")
  ctx
}

register_block(
  "trajectory_pamm",
  block_trajectory_pamm,
  "PAMM 连续指标时变非线性 + P5/P95 占比/累积负担（Fig5/6）"
)
