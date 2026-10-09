###############################################################################
#  trajectory_dynpred_individual — 个体患者 dynpred vs Weibull 动态预测曲线（Fig4）
#
#  合并 run_Fig4_APRI.R（MIMIC）与 run_Fig4_APRI_eICU.R（eICU）：两队列版本代码几乎
#  完全相同，此处合并为单一 block，按 ctx 当前数据（哪个 cohort 由上游 row_filter /
#  worker 决定）自动挑选代表病例，不再区分 eICU/MIMIC 专用脚本。
#
#  自动选例逻辑：
#    - “存活代表”：指标随时间持续下降（线性斜率<0）、观测点数达标的存活者中，
#      斜率最负者（下降最快）；若配置了 min_index_baseline，还要求原始指标峰值超过该阈值。
#    - “非存活代表”：指标随时间持续上升（线性斜率>0）、观测点数达标的非存活者中，
#      首个 landmark 处 dynpred 风险最高者。
#    - 若按趋势方向筛不出候选，回退为仅按观测点数达标筛选（不看斜率方向）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_upstream = trajectory_jlcm（需要 ctx$results$trajectory_jlcm_models[[Index]]）
#  require_pkg  = lcmm, survival, flexsurv, dplyr, tidyr, ggplot2, MASS
#
#  trajectory_dynpred_individual = list(
#    index_vars              = NULL,        # NULL → names(ctx$results$trajectory_jlcm_models)
#    jlcm_ng                 = NULL,        # NULL → config$trajectory_jlcm$prefer_final_ng %||% 2L
#    horizon                 = NULL,        # NULL → config$trajectory_jlcm$max_followup %||% 28
#    final_landmarks         = c(2, 5, 8, 11),
#    covariate_vars          = NULL,        # NULL → 复用 trajectory_jlcm 的 covariate_vars_used
#    ndraws                  = 2000L,
#    boot_weibull            = 2000L,
#    require_survivor_dyn_better = TRUE,  # 存活代表：动态模型生存概率需优于静态 Weibull
#    survivor_dyn_better_min_margin = 0.02,
#    min_index_baseline      = NULL,        # 可选：过滤存活代表病例的原始指标峰值下限
#    seed                    = 1L,
#    pause_enable            = TRUE,
#    pause_on_no_output      = TRUE
#  ),
#
#  register_block: "trajectory_dynpred_individual"
#  写: ctx$results$trajectory_dynpred_individual[[Index]]
#  落盘: Figures/Figure_Dynpred_Individual_{Index}.pdf
###############################################################################

.tdi05_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tdi05_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_dynpred_individual", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tdi05_unwrap_model <- function(model_obj) {
  if (inherits(model_obj, "Jointlcmm")) return(model_obj)
  if (is.list(model_obj) && inherits(model_obj$best, "Jointlcmm")) return(model_obj$best)
  model_obj
}

.tdi05_to_prob01 <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(is.na(x), NA_real_, ifelse(x > 1.5, x / 100, x))
}

.tdi05_dynpred_curve <- function(model_obj, history_data, landmark, horizon_abs, ndraws = 2000) {
  hmax <- floor(horizon_abs - landmark)
  if (hmax < 1) return(NULL)
  h_rel <- 1:hmax
  res <- tryCatch(
    lcmm::dynpred(model_obj, newdata = history_data, landmark = landmark, horizon = h_rel,
                  var.time = "time_day", draws = TRUE, ndraws = ndraws),
    error = function(e) NULL
  )
  if (is.null(res)) {
    res <- tryCatch(
      lcmm::dynpred(model_obj, newdata = history_data, landmark = landmark, horizon = h_rel,
                    var.time = "time_day", draws = FALSE),
      error = function(e) NULL
    )
  }
  if (is.null(res)) return(NULL)

  pred_df <- as.data.frame(if (is.list(res) && !is.null(res$pred)) res$pred else res)
  if (nrow(pred_df) < 2) return(NULL)
  cn <- tolower(names(pred_df))
  h_idx <- which(cn %in% c("horizon", "time")); if (!length(h_idx)) h_idx <- 3
  p_idx <- which(cn %in% c("pred", "risk", "prob")); if (!length(p_idx)) p_idx <- 4

  h <- suppressWarnings(as.numeric(as.character(pred_df[[h_idx[1]]])))
  risk_med <- .tdi05_to_prob01(pred_df[[p_idx[1]]])
  keep <- is.finite(h) & is.finite(risk_med); h <- h[keep]; risk_med <- risk_med[keep]
  if (length(h) < 2) return(NULL)
  ord <- order(h); h <- h[ord]; risk_med <- risk_med[ord]

  risk_lo <- rep(NA_real_, length(h)); risk_hi <- rep(NA_real_, length(h))
  lcol <- which(grepl("lower|lcl|2\\.5", cn)); ucol <- which(grepl("upper|ucl|97\\.5", cn))
  if (length(lcol) >= 1 && length(ucol) >= 1) {
    risk_lo <- .tdi05_to_prob01(pred_df[[lcol[1]]])[keep][ord]
    risk_hi <- .tdi05_to_prob01(pred_df[[ucol[1]]])[keep][ord]
  }

  risk_med <- pmin(pmax(risk_med, 0), 1); risk_lo <- pmin(pmax(risk_lo, 0), 1); risk_hi <- pmin(pmax(risk_hi, 0), 1)
  surv_med <- 1 - risk_med
  surv_lo  <- ifelse(is.na(risk_hi), NA_real_, 1 - risk_hi)
  surv_hi  <- ifelse(is.na(risk_lo), NA_real_, 1 - risk_lo)

  rbind(
    data.frame(time = landmark, surv_prob = 1, surv_low = NA_real_, surv_high = NA_real_),
    data.frame(time = landmark + h, surv_prob = surv_med, surv_low = surv_lo, surv_high = surv_hi)
  )
}

.tdi05_weibull_curve <- function(weib_mod, landmark, horizon_abs, xrow, cov_use, B_boot, ngrid = 200) {
  tt <- seq(landmark, horizon_abs, length.out = ngrid)
  t_all <- c(landmark, tt)
  mu_par <- stats::coef(weib_mod); V <- stats::vcov(weib_mod)
  shape_idx <- which(names(mu_par) == "shape")
  scale_idx <- setdiff(seq_along(mu_par), shape_idx)
  X <- c(1, as.numeric(xrow[cov_use]))
  weib_S <- function(t, log_shape, log_scale_i) exp(-(t / exp(log_scale_i))^exp(log_shape))
  log_shape0 <- mu_par[shape_idx]; log_scale0 <- sum(mu_par[scale_idx] * X)
  s0 <- weib_S(t_all, log_shape0, log_scale0)
  s_cond0 <- pmin(pmax(s0[-1] / pmax(s0[1], 1e-12), 0), 1)

  if (!requireNamespace("MASS", quietly = TRUE)) {
    return(data.frame(time = tt, surv_prob = s_cond0, surv_low = NA_real_, surv_high = NA_real_))
  }
  theta <- MASS::mvrnorm(n = B_boot, mu = mu_par, Sigma = V)
  s_draws <- apply(theta, 1, function(par_b) {
    ls_b <- par_b[shape_idx]; lc_b <- sum(par_b[scale_idx] * X)
    sb <- weib_S(t_all, ls_b, lc_b)
    pmin(pmax(sb[-1] / pmax(sb[1], 1e-12), 0), 1)
  })
  if (is.vector(s_draws)) s_draws <- matrix(s_draws, nrow = length(tt))
  lo <- apply(s_draws, 1, stats::quantile, probs = 0.025, na.rm = TRUE)
  hi <- apply(s_draws, 1, stats::quantile, probs = 0.975, na.rm = TRUE)
  data.frame(time = tt, surv_prob = s_cond0, surv_low = pmin(pmax(lo, 0), 1), surv_high = pmin(pmax(hi, 0), 1))
}

.tdi05_run_one_index <- function(ctx, bl, Index) {
  jlcm_entry <- ctx$results$trajectory_jlcm_models[[Index]]
  if (is.null(jlcm_entry)) {
    cli::cli_alert_warning("trajectory_dynpred_individual: 无 {Index} 的 JLCM 模型，跳过"); return(NULL)
  }
  ng <- if (!is.null(bl$jlcm_ng)) {
    as.integer(bl$jlcm_ng)
  } else {
    trajectory_resolve_optimal_ng(ctx, Index, ctx$config, fallback = 2L)
  }
  cli::cli_alert_info("trajectory_dynpred_individual [{Index}]: 使用 ng={ng}")
  model_obj <- .tdi05_unwrap_model(jlcm_entry$models[[paste0("m", ng)]])
  model_data <- jlcm_entry$model_data_final
  if (is.null(model_obj) || is.null(model_data) || !nrow(model_data)) {
    cli::cli_alert_warning("trajectory_dynpred_individual: {Index} 模型/数据缺失，跳过"); return(NULL)
  }

  horizon <- as.numeric(bl$horizon %||% ctx$config$trajectory_jlcm$max_followup %||% 28)
  landmarks <- as.numeric(bl$final_landmarks %||% c(2, 5, 8, 11))
  ndraws <- as.integer(bl$ndraws %||% 2000L)
  boot_weibull <- as.integer(bl$boot_weibull %||% 2000L)
  min_pts_trend <- as.integer(bl$min_pts_trend %||% 6L)
  min_index_baseline <- bl$min_index_baseline %||% NULL
  set.seed(as.integer(bl$seed %||% 1L))

  # 协变量按项目流程（单因素→VIF→多因素→VIF）选出：复用 JLCM covariate_vars_used。
  # 泄漏/管理型变量已在上游 excluded_predictors + VIF exclude_vars 阶段剔除。
  pipe_covs <- as.character(bl$covariate_vars %||% jlcm_entry$covariate_vars_used %||% character(0))
  base_rows <- model_data |>
    dplyr::filter(is.finite(time_day)) |>
    dplyr::group_by(subject_id_num) |>
    dplyr::arrange(time_day, .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup()
  cov_use <- intersect(pipe_covs, names(base_rows))

  patient_level <- model_data |>
    dplyr::group_by(subject_id_num) |>
    dplyr::summarise(
      t28 = suppressWarnings(max(surv_time, na.rm = TRUE)),
      event28 = suppressWarnings(max(surv_event, na.rm = TRUE)),
      .groups = "drop"
    )
  if (length(cov_use)) {
    cov_tab <- base_rows[, c("subject_id_num", cov_use), drop = FALSE]
    for (v in cov_use) cov_tab[[v]] <- suppressWarnings(as.numeric(cov_tab[[v]]))
    patient_level <- dplyr::left_join(patient_level, cov_tab, by = "subject_id_num")
  }

  if (!length(cov_use)) {
    df_weib <- patient_level[, c("t28", "event28")]
  } else {
    df_weib <- patient_level[, c("t28", "event28", cov_use)]
  }
  df_weib <- df_weib[stats::complete.cases(df_weib) & df_weib$t28 > 0, , drop = FALSE]
  if (nrow(df_weib) < 30) {
    cli::cli_alert_warning("trajectory_dynpred_individual: {Index} 有效样本不足，跳过"); return(NULL)
  }
  weib_formula <- stats::as.formula(paste0(
    "survival::Surv(t28, event28) ~ ", if (length(cov_use)) paste(cov_use, collapse = " + ") else "1"
  ))
  weib_mod <- tryCatch(flexsurv::flexsurvreg(weib_formula, data = df_weib, dist = "weibull"),
                        error = function(e) NULL)
  if (is.null(weib_mod)) {
    cli::cli_alert_warning("trajectory_dynpred_individual: {Index} Weibull 拟合失败，跳过"); return(NULL)
  }

  trend_end <- max(landmarks)
  bar_trend_slope <- function(pid) {
    dd <- model_data[model_data$subject_id_num == pid & model_data$time_day <= trend_end, c("time_day", "scr_std")]
    dd <- unique(dd[stats::complete.cases(dd), ])
    if (nrow(dd) < min_pts_trend) return(NA_real_)
    stats::coef(stats::lm(scr_std ~ time_day, data = dd))[["time_day"]]
  }
  bar_npts <- function(pid) {
    dd <- model_data[model_data$subject_id_num == pid & model_data$time_day <= trend_end, "time_day"]
    length(unique(stats::na.omit(dd)))
  }
  score_pid_at_L <- function(pid, L) {
    hd <- model_data[model_data$subject_id_num == pid & model_data$time_day <= L, ]
    hd <- hd[order(hd$time_day), ]
    if (!nrow(hd)) return(NA_real_)
    r <- tryCatch({
      zz <- file(nullfile(), open = "wt")
      sink(zz); sink(zz, type = "message")
      on.exit({
        try(sink(type = "message"), silent = TRUE)
        try(sink(), silent = TRUE)
        try(close(zz), silent = TRUE)
      }, add = TRUE)
      out <- lcmm::dynpred(model_obj, newdata = hd, landmark = L, horizon = horizon - L,
                           var.time = "time_day", draws = FALSE)
      try(sink(type = "message"), silent = TRUE)
      try(sink(), silent = TRUE)
      try(close(zz), silent = TRUE)
      on.exit(NULL)
      out
    }, error = function(e) {
      try(sink(type = "message"), silent = TRUE)
      try(sink(), silent = TRUE)
      NULL
    })
    if (is.null(r)) return(NA_real_)
    pred_df <- as.data.frame(if (is.list(r) && !is.null(r$pred)) r$pred else r)
    if (!nrow(pred_df)) return(NA_real_)
    cn <- tolower(names(pred_df)); p_idx <- which(cn %in% c("pred", "risk", "prob")); if (!length(p_idx)) p_idx <- 4
    as.numeric(utils::tail(pred_df[[p_idx[1]]], 1))
  }

  L0 <- landmarks[1]; maxL <- max(landmarks)
  all_ids <- unique(patient_level$subject_id_num)
  survivor_ids0 <- patient_level$subject_id_num[patient_level$event28 == 0 & patient_level$t28 >= horizon]
  nonsurvivor_ids0 <- patient_level$subject_id_num[patient_level$event28 == 1 & patient_level$t28 > maxL]

  surv_slopes <- stats::setNames(sapply(survivor_ids0, bar_trend_slope), survivor_ids0)
  non_slopes  <- stats::setNames(sapply(nonsurvivor_ids0, bar_trend_slope), nonsurvivor_ids0)
  surv_npts   <- stats::setNames(sapply(survivor_ids0, bar_npts), survivor_ids0)
  non_npts    <- stats::setNames(sapply(nonsurvivor_ids0, bar_npts), nonsurvivor_ids0)

  survivor_ids <- names(surv_slopes)[is.finite(surv_slopes) & surv_slopes < 0 & surv_npts[names(surv_slopes)] >= min_pts_trend]
  nonsurvivor_ids <- names(non_slopes)[is.finite(non_slopes) & non_slopes > 0 & non_npts[names(non_slopes)] >= min_pts_trend]

  if (!is.null(min_index_baseline) && length(survivor_ids)) {
    survivor_ids <- survivor_ids[sapply(survivor_ids, function(pid) {
      vals <- model_data$scr_std[as.character(model_data$subject_id_num) == pid]
      any(exp(vals) > min_index_baseline, na.rm = TRUE)
    })]
  }
  if (!length(survivor_ids))
    survivor_ids <- intersect(as.character(survivor_ids0), names(surv_npts)[is.finite(surv_npts) & surv_npts >= min_pts_trend])
  if (!length(nonsurvivor_ids))
    nonsurvivor_ids <- intersect(as.character(nonsurvivor_ids0), names(non_npts)[is.finite(non_npts) & non_npts >= min_pts_trend])

  if (!length(survivor_ids) || !length(nonsurvivor_ids)) {
    cli::cli_alert_warning("trajectory_dynpred_individual: {Index} 找不到满足条件的代表病例，跳过")
    return(NULL)
  }

  # 存活代表：要求动态模型生存概率整体高于静态 Weibull（动态优于静态）
  .tdi05_surv_dyn_minus_weib <- function(pid) {
    xrow <- patient_level[as.character(patient_level$subject_id_num) == as.character(pid),
                          cov_use, drop = FALSE]
    diffs <- c()
    for (L in landmarks) {
      hd <- model_data[as.character(model_data$subject_id_num) == as.character(pid) &
                         model_data$time_day <= L, ]
      hd <- hd[order(hd$time_day), ]
      if (!nrow(hd)) next
      dyn <- tryCatch(.tdi05_dynpred_curve(model_obj, hd, L, horizon, max(200L, as.integer(ndraws / 5))),
                      error = function(e) NULL)
      w <- tryCatch({
        if (length(cov_use)) .tdi05_weibull_curve(weib_mod, L, horizon, xrow, cov_use, 200L)
        else .tdi05_weibull_curve(weib_mod, L, horizon, xrow, character(0), 200L)
      }, error = function(e) NULL)
      if (is.null(dyn) || is.null(w) || !nrow(dyn) || !nrow(w)) next
      # 对齐时间网格：取末点条件生存差（动态 − 静态）
      sd <- as.numeric(utils::tail(dyn$surv_prob, 1))
      sw <- as.numeric(utils::tail(w$surv_prob, 1))
      if (is.finite(sd) && is.finite(sw)) diffs <- c(diffs, sd - sw)
    }
    if (!length(diffs)) return(NA_real_)
    mean(diffs)
  }

  surv_margin <- suppressWarnings(sapply(survivor_ids, .tdi05_surv_dyn_minus_weib))
  names(surv_margin) <- as.character(survivor_ids)
  surv_margin <- surv_margin[is.finite(surv_margin)]
  prefer_dyn_better <- isTRUE(bl$require_survivor_dyn_better %||% TRUE)
  min_margin <- as.numeric(bl$survivor_dyn_better_min_margin %||% 0.02)

  surv_ok <- surv_margin[surv_margin > min_margin]
  if (prefer_dyn_better && length(surv_ok)) {
    # 在动态明显更好的候选中，优先斜率更负（指标下降）者
    cand <- intersect(names(surv_ok), names(surv_slopes))
    if (length(cand)) {
      final_survivor <- names(which.min(surv_slopes[cand]))
    } else {
      final_survivor <- names(which.max(surv_ok))
    }
    cli::cli_alert_info(
      "{Index}: 存活代表满足动态>静态 (margin={round(surv_margin[final_survivor], 3)}) → id={final_survivor}"
    )
  } else {
    surv_slope_cand <- surv_slopes[intersect(survivor_ids, names(surv_slopes))]
    surv_slope_cand <- surv_slope_cand[is.finite(surv_slope_cand)]
    final_survivor <- if (length(surv_slope_cand)) names(which.min(surv_slope_cand)) else survivor_ids[1]
    if (prefer_dyn_better) {
      cli::cli_alert_warning(
        "{Index}: 无存活候选满足动态>静态(margin>{min_margin})，回退斜率最负者 id={final_survivor}"
      )
    }
  }

  non_scores <- sapply(nonsurvivor_ids, score_pid_at_L, L = L0)
  non_scores <- non_scores[is.finite(non_scores)]
  if (!length(non_scores)) { cli::cli_alert_warning("trajectory_dynpred_individual: {Index} 打分失败"); return(NULL) }
  final_nonsurvivor <- names(which.max(non_scores))

  patient_info <- patient_level[patient_level$subject_id_num %in% c(final_survivor, final_nonsurvivor), ]
  patient_info$case_label <- ifelse(
    as.character(patient_info$subject_id_num) == as.character(final_survivor),
    "Case 1 (Survivor)", "Case 2 (Non-survivor)"
  )
  death_time <- patient_info$t28[patient_info$case_label == "Case 2 (Non-survivor)"]
  death_time <- if (length(death_time)) as.numeric(death_time[1]) else NA_real_

  pred_rows <- list()
  for (pid in c(final_survivor, final_nonsurvivor)) {
    xrow <- patient_level[as.character(patient_level$subject_id_num) == as.character(pid), cov_use, drop = FALSE]
    for (L in landmarks) {
      hd <- model_data[as.character(model_data$subject_id_num) == as.character(pid) & model_data$time_day <= L, ]
      hd <- hd[order(hd$time_day), ]
      dyn <- .tdi05_dynpred_curve(model_obj, hd, L, horizon, ndraws)
      if (is.null(dyn) || !nrow(dyn)) {
        dyn <- data.frame(time = NA_real_, surv_prob = NA_real_, surv_low = NA_real_, surv_high = NA_real_)
      }
      dyn$pid <- pid; dyn$landmark <- L; dyn$model <- "Dynamic prediction model"

      w <- if (length(cov_use)) .tdi05_weibull_curve(weib_mod, L, horizon, xrow, cov_use, boot_weibull)
           else .tdi05_weibull_curve(weib_mod, L, horizon, xrow, character(0), boot_weibull)
      w$pid <- pid; w$landmark <- L; w$model <- "Weibull survival model"
      pred_rows[[length(pred_rows) + 1L]] <- rbind(dyn, w)
    }
  }
  all_pred <- do.call(rbind, pred_rows)
  all_pred <- merge(all_pred, patient_info[, c("subject_id_num", "case_label")],
                     by.x = "pid", by.y = "subject_id_num", all.x = TRUE)
  all_pred <- all_pred[is.finite(all_pred$time), , drop = FALSE]

  raw_data <- model_data[as.character(model_data$subject_id_num) %in% c(final_survivor, final_nonsurvivor), ]
  scr_data <- merge(
    raw_data[, c("subject_id_num", "time_day", "scr_std")],
    patient_info[, c("subject_id_num", "case_label")], by = "subject_id_num"
  )
  scr_data <- tidyr::expand_grid(scr_data, landmark = landmarks)
  scr_data <- scr_data[scr_data$time_day <= scr_data$landmark, ]

  bar_min <- min(raw_data$scr_std, na.rm = TRUE); bar_max <- max(raw_data$scr_std, na.rm = TRUE)
  y_min <- floor(bar_min) - 0.5; y_max <- ceiling(bar_max) + 0.5; y_span <- y_max - y_min
  surv_to_y <- function(s) { s <- pmin(pmax(s, 0), 1); y_min + s * y_span }

  pred_med <- data.frame(case_label = all_pred$case_label, landmark = all_pred$landmark,
                          model = all_pred$model, time = all_pred$time, y = surv_to_y(all_pred$surv_prob))
  pred_ci <- tidyr::pivot_longer(
    all_pred[, c("case_label", "landmark", "model", "time", "surv_low", "surv_high")],
    cols = c("surv_low", "surv_high"), names_to = "band", values_to = "surv_ci"
  )
  pred_ci$y <- surv_to_y(pred_ci$surv_ci)
  pred_ci <- pred_ci[!is.na(pred_ci$y) & is.finite(pred_ci$y), ]

  landmark_df <- expand.grid(case_label = unique(patient_info$case_label), landmark = landmarks)
  death_df <- if (is.finite(death_time)) {
    d <- expand.grid(case_label = "Case 2 (Non-survivor)", landmark = landmarks)
    d$death_time <- death_time; d
  } else data.frame()

  p <- ggplot2::ggplot() +
    ggplot2::geom_line(data = pred_ci[pred_ci$model == "Weibull survival model", ],
                        ggplot2::aes(x = time, y = y, colour = model, group = interaction(model, band)),
                        linewidth = 0.8, linetype = "dashed", show.legend = FALSE) +
    ggplot2::geom_line(data = pred_med[pred_med$model == "Weibull survival model", ],
                        ggplot2::aes(x = time, y = y, colour = model), linewidth = 1.0) +
    ggplot2::geom_line(data = pred_ci[pred_ci$model == "Dynamic prediction model", ],
                        ggplot2::aes(x = time, y = y, colour = model, group = interaction(model, band)),
                        linewidth = 0.8, linetype = "dashed", show.legend = FALSE) +
    ggplot2::geom_line(data = pred_med[pred_med$model == "Dynamic prediction model", ],
                        ggplot2::aes(x = time, y = y, colour = model), linewidth = 1.3) +
    ggplot2::geom_point(data = scr_data, ggplot2::aes(x = time_day, y = scr_std),
                         shape = 8, size = 2.2, colour = "black",
                         position = ggplot2::position_jitter(width = 0.08, height = 0)) +
    ggplot2::geom_vline(data = landmark_df, ggplot2::aes(xintercept = landmark),
                         linetype = "dashed", linewidth = 0.8, colour = "black")
  if (nrow(death_df) > 0) {
    p <- p +
      ggplot2::geom_vline(data = death_df, ggplot2::aes(xintercept = death_time), linewidth = 0.9, colour = "black") +
      ggplot2::geom_text(data = death_df, ggplot2::aes(x = death_time, y = y_min + y_span * 0.06,
                                                        label = sprintf("%.2f", death_time)),
                          colour = "#982034", size = 3.0, vjust = 0)
  }
  x_breaks <- c(0, 2, 4, 8, 12, 16, 20, 24, 28)
  x_breaks <- x_breaks[x_breaks <= horizon]
  p <- p +
    ggplot2::scale_x_continuous(name = "Days after ICU entry", limits = c(0, horizon), breaks = x_breaks) +
    ggplot2::scale_y_continuous(name = Index, limits = c(y_min, y_max),
                                 sec.axis = ggplot2::sec_axis(transform = ~ ((. - y_min) / y_span) * 100,
                                                               name = "Survival probability %")) +
    ggplot2::scale_colour_manual(values = c("Dynamic prediction model" = "#982034", "Weibull survival model" = "#002C64")) +
    ggplot2::facet_grid(landmark ~ case_label, switch = "x") +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), legend.position = "top", legend.title = ggplot2::element_blank(),
                   strip.text.y = ggplot2::element_blank(), strip.background = ggplot2::element_blank(),
                   strip.text.x = ggplot2::element_text(face = "bold", size = 12),
                   panel.spacing = grid::unit(0.8, "lines"))

  list(plot = p, predictions = all_pred, patient_info = patient_info,
       final_survivor = final_survivor, final_nonsurvivor = final_nonsurvivor)
}

block_trajectory_dynpred_individual <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr); library(cli); library(tidyr); library(ggplot2)
    if (requireNamespace("lcmm", quietly = TRUE)) library(lcmm)
    if (requireNamespace("flexsurv", quietly = TRUE)) library(flexsurv)
  })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)

  bl <- ctx$config$trajectory_dynpred_individual %||% list()

  index_vars <- as.character(bl$index_vars %||% names(ctx$results$trajectory_jlcm_models %||% list()))
  if (!length(index_vars)) {
    cli::cli_alert_warning("trajectory_dynpred_individual: 无可用 Index")
    if (.tdi05_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tdi05_pause(ctx, "trajectory_dynpred_individual: 无可用 JLCM 模型。", "请确认 trajectory_jlcm 已先运行。", NULL)
    }
    return(ctx)
  }

  results_all <- list()
  for (Index in index_vars) {
    cli::cli_h1("trajectory_dynpred_individual: {Index}")
    res <- tryCatch(.tdi05_run_one_index(ctx, bl, Index),
                     error = function(e) { cli::cli_alert_danger("{Index}: {e$message}"); NULL })
    if (is.null(res)) next
    results_all[[Index]] <- res
    ctx <- save_figure(
      ctx, paste0("Figure_Dynpred_Individual_", Index, ".pdf"),
      local({ pp <- res$plot; function() pp }), width = 10, height = 12
    )
    cli::cli_alert_success("{Index}: 代表病例 存活={res$final_survivor} / 非存活={res$final_nonsurvivor}")
  }

  if (!length(results_all)) {
    if (.tdi05_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tdi05_pause(ctx, "trajectory_dynpred_individual: 所有 Index 均未找到代表病例。",
                   "请检查 min_pts_trend / min_index_baseline 设置是否过严。", NULL)
    }
    cli::cli_alert_warning("trajectory_dynpred_individual: 无有效输出")
    return(ctx)
  }

  ctx$results$trajectory_dynpred_individual <- results_all
  cli::cli_alert_success("trajectory_dynpred_individual 完成：{length(results_all)} 个 Index")
  ctx
}

register_block(
  "trajectory_dynpred_individual", block_trajectory_dynpred_individual,
  "个体患者 dynpred vs Weibull 动态预测曲线（自动选代表存活/非存活病例）"
)
