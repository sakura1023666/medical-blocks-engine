###############################################################################
#  trajectory_weibull_compare — JLCM 动态预测(dynpred) vs 静态 Weibull 生存模型对比
#
#  v2：替换 v1 的简化实现（原版仅用 trajectory_class 因子做 Cox C-index，并非真正的
#  动态预测，也没有 AUC / bootstrap CI / 显著性检验）。
#  合并 run_fig_APRI_v2.R（bootstrap CI + 配对 permutation 检验 + top-prop 分类指标 +
#  post-hoc 协变量增强）与 run_FigS7_APRI_v2.R（在此基础上追加 Youden 最优切点敏感度/
#  特异度，作为 include_youden_metrics 开关，不再单独建 block）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_upstream = trajectory_jlcm（需要 ctx$results$trajectory_jlcm_models[[Index]]）
#  require_pkg  = lcmm, survival, flexsurv, dplyr, tidyr, ggplot2, Hmisc
#  require_pkg（可选，提升 AUC 精度）= timeROC, pROC
#
#  trajectory_weibull_compare = list(
#    index_vars              = NULL,     # NULL → 用 names(ctx$results$trajectory_jlcm_models)
#    jlcm_ng                 = NULL,     # NULL → config$trajectory_jlcm$prefer_final_ng %||% 2L
#    landmarks               = 4:14,
#    horizon                 = NULL,     # NULL → config$trajectory_jlcm$max_followup %||% 28
#    covariate_vars          = NULL,     # NULL → 复用 trajectory_jlcm 存的 covariate_vars_used
#    include_index_baseline  = TRUE,     # Weibull/增强模型是否额外纳入指标基线值
#    augment_with_covariates = TRUE,     # dynpred 风险是否用协变量做 post-hoc glm 增强
#    top_prop                = 0.2,      # Top-k% 高危筛查（次要口径，写入 *_top 列）
#    class_metric            = "youden", # 主图 Acc/Sens/Spec 口径: "youden"（推荐）| "top_prop"
#    boot_n                  = 2000L,
#    perm_n                  = 2000L,
#    min_unique_time_for_dynpred = 4L,
#    min_n_landmark          = 30L,
#    include_youden_metrics  = TRUE,     # 始终计算 Youden；主图是否采用由 class_metric 决定
#    seed                    = 2025L,
#    pause_enable            = TRUE,
#    pause_on_no_output      = TRUE
#  ),
#
#  register_block: "trajectory_weibull_compare"
#  写: ctx$results$trajectory_weibull_compare[[Index]]
#  落盘: Tables/Table_Weibull_Dynamic_Compare_{Index}.csv
#        Figures/Figure_Weibull_Dynamic_Compare_{Index}_{AUC|Cindex|Accuracy|Sensitivity|Specificity}.pdf
###############################################################################

.twc02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.twc02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_weibull_compare", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.twc02_calc_auc_ipcw <- function(time, event, score, tau) {
  event <- as.integer(event); score <- suppressWarnings(as.numeric(score))
  time  <- suppressWarnings(as.numeric(time))
  ok <- is.finite(time) & is.finite(score) & !is.na(event)
  time <- time[ok]; event <- event[ok]; score <- score[ok]
  if (length(time) < 30 || length(unique(event)) < 2 || !is.finite(tau)) return(NA_real_)
  if (requireNamespace("timeROC", quietly = TRUE)) {
    roc <- tryCatch(
      timeROC::timeROC(T = time, delta = event, marker = score, cause = 1, times = tau, iid = FALSE),
      error = function(e) NULL
    )
    if (!is.null(roc)) { a <- as.numeric(roc$AUC[1]); if (is.finite(a)) return(a) }
  }
  if (!requireNamespace("pROC", quietly = TRUE)) return(NA_real_)
  is_case <- (event == 1L & time <= tau); is_ctrl <- (event == 0L & time >= tau)
  if (sum(is_case) < 5 || sum(is_ctrl) < 5) return(NA_real_)
  km <- tryCatch(survival::survfit(survival::Surv(time, 1L - event) ~ 1), error = function(e) NULL)
  if (is.null(km)) return(NA_real_)
  Ghat <- function(t) {
    s <- tryCatch(summary(km, times = t, extend = TRUE)$surv, error = function(e) rep(NA_real_, length(t)))
    s[!is.finite(s)] <- NA_real_
    pmax(s, 1e-6)
  }
  w <- rep(0, length(time)); w[is_case] <- 1 / Ghat(time[is_case]); w[is_ctrl] <- 1 / Ghat(tau)
  keep <- is_case | is_ctrl; y <- ifelse(is_case[keep], 1L, 0L); sc <- score[keep]; ww <- w[keep]
  rr <- tryCatch(pROC::roc(y, sc, weights = ww, quiet = TRUE, direction = "<"), error = function(e) NULL)
  if (is.null(rr)) return(NA_real_)
  as.numeric(pROC::auc(rr))
}

.twc02_calc_cindex <- function(time, event, risk_score) {
  if (!requireNamespace("Hmisc", quietly = TRUE)) return(NA_real_)
  event <- as.integer(event)
  out <- tryCatch(Hmisc::rcorr.cens(-risk_score, survival::Surv(time, event)), error = function(e) NULL)
  if (is.null(out)) return(NA_real_)
  as.numeric(out["C Index"])
}

.twc02_boot_ci <- function(df, metric_fun, B = 2000, conf = 0.95) {
  n <- nrow(df)
  if (n < 30) return(c(est = NA_real_, low = NA_real_, high = NA_real_))
  vals <- replicate(B, metric_fun(df[sample.int(n, n, replace = TRUE), , drop = FALSE]))
  vals <- vals[is.finite(vals)]
  if (length(vals) < 200) return(c(est = NA_real_, low = NA_real_, high = NA_real_))
  alpha <- (1 - conf) / 2
  c(est = metric_fun(df), low = unname(stats::quantile(vals, alpha)), high = unname(stats::quantile(vals, 1 - alpha)))
}

.twc02_perm_p_paired <- function(df_eval, s1, s2, tau, B = 2000, metric_fn) {
  score1 <- df_eval[[s1]]; score2 <- df_eval[[s2]]
  time <- df_eval$time_LM; event <- df_eval$future_event
  obs <- metric_fn(time, event, score1, score2, tau)
  if (!is.finite(obs)) return(NA_real_)
  n <- nrow(df_eval)
  diffs <- replicate(B, {
    swap <- stats::rbinom(n, 1, 0.5) == 1
    a <- ifelse(swap, score1, score2); b <- ifelse(swap, score2, score1)
    metric_fn(time, event, a, b, tau)
  })
  diffs <- diffs[is.finite(diffs)]
  if (length(diffs) < 200) return(NA_real_)
  mean(abs(diffs) >= abs(obs))
}

.twc02_metrics_top_prop <- function(y, score, top_prop = 0.2) {
  y <- as.integer(y); score <- suppressWarnings(as.numeric(score))
  ok <- is.finite(score) & !is.na(y); y <- y[ok]; score <- score[ok]
  if (length(y) == 0 || length(unique(y)) < 2) return(c(acc = NA_real_, sens = NA_real_, spec = NA_real_))
  n <- length(y); n_top <- max(1L, floor(n * top_prop))
  ord <- order(score, decreasing = TRUE, na.last = NA)
  if (length(ord) == 0) return(c(acc = NA_real_, sens = NA_real_, spec = NA_real_))
  idx_top <- ord[seq_len(min(n_top, length(ord)))]; pred <- integer(n); pred[idx_top] <- 1L
  tp <- sum(pred == 1L & y == 1L); fp <- sum(pred == 1L & y == 0L)
  tn <- sum(pred == 0L & y == 0L); fn <- sum(pred == 0L & y == 1L)
  c(acc = (tp + tn) / (tp + tn + fp + fn),
    sens = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
    spec = if (tn + fp > 0) tn / (tn + fp) else NA_real_)
}

.twc02_metrics_youden <- function(y, score) {
  y <- as.integer(y); score <- suppressWarnings(as.numeric(score))
  ok <- is.finite(score) & !is.na(y); y <- y[ok]; score <- score[ok]
  na_out <- c(thr = NA_real_, acc = NA_real_, sens = NA_real_, spec = NA_real_)
  if (length(unique(y)) < 2 || !requireNamespace("pROC", quietly = TRUE)) return(na_out)
  roc_obj <- tryCatch(pROC::roc(y, score, quiet = TRUE, direction = "<"), error = function(e) NULL)
  if (is.null(roc_obj)) return(na_out)
  co <- tryCatch(
    pROC::coords(roc_obj, x = "best", best.method = "youden",
                 ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE),
    error = function(e) NULL
  )
  if (is.null(co)) return(na_out)
  thr <- if (is.data.frame(co)) as.numeric(co$threshold[1]) else as.numeric(co[1, "threshold"])
  if (!is.finite(thr)) return(na_out)
  pred <- as.integer(score >= thr)
  tp <- sum(pred == 1L & y == 1L); fp <- sum(pred == 1L & y == 0L)
  tn <- sum(pred == 0L & y == 0L); fn <- sum(pred == 0L & y == 1L)
  den <- tp + tn + fp + fn
  c(thr = thr,
    acc = if (den > 0) (tp + tn) / den else NA_real_,
    sens = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
    spec = if (tn + fp > 0) tn / (tn + fp) else NA_real_)
}

.twc02_weibull_cond_risk <- function(weib_mod, newdata_base, t_LM, horizon_abs) {
  s <- summary(weib_mod, newdata = newdata_base, t = c(t_LM, horizon_abs), type = "survival")
  matS <- do.call(rbind, lapply(s, function(x) x$est))
  pmax(pmin(1 - matS[, 2] / pmax(matS[, 1], 1e-12), 1), 0)
}

.twc02_unwrap_model <- function(model_obj) {
  if (inherits(model_obj, "Jointlcmm")) return(model_obj)
  if (is.list(model_obj) && inherits(model_obj$best, "Jointlcmm")) return(model_obj$best)
  model_obj
}

# 每个受试者取 time_day 最小（基线）那一行
.twc02_baseline_rows <- function(model_data, id_col = "subject_id_num", time_col = "time_day") {
  model_data |>
    dplyr::group_by(.data[[id_col]]) |>
    dplyr::arrange(.data[[time_col]], .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup()
}

.twc02_run_one_index <- function(ctx, bl, Index, root) {
  jlcm_entry <- ctx$results$trajectory_jlcm_models[[Index]]
  if (is.null(jlcm_entry)) {
    cli::cli_alert_warning("trajectory_weibull_compare: 无 {Index} 的 JLCM 模型，跳过")
    return(NULL)
  }
  ng <- if (!is.null(bl$jlcm_ng)) {
    as.integer(bl$jlcm_ng)
  } else {
    trajectory_resolve_optimal_ng(ctx, Index, ctx$config, fallback = 2L)
  }
  cli::cli_alert_info("trajectory_weibull_compare [{Index}]: 使用 ng={ng}")
  model_obj_raw <- jlcm_entry$models[[paste0("m", ng)]]
  if (is.null(model_obj_raw)) {
    cli::cli_alert_warning("trajectory_weibull_compare: {Index} 缺少 ng={ng} 模型，跳过")
    return(NULL)
  }
  model_obj <- .twc02_unwrap_model(model_obj_raw)
  model_data <- jlcm_entry$model_data_final
  if (is.null(model_data) || !nrow(model_data)) {
    cli::cli_alert_warning("trajectory_weibull_compare: {Index} 缺少 model_data_final，跳过")
    return(NULL)
  }

  # 协变量按项目流程（单因素→VIF→多因素→VIF）选出：直接复用 trajectory_jlcm 落定的
  # covariate_vars_used（= Model1∪Model2 经连续型/上限筛选）。不再写死 age+baseline。
  # 注：泄漏/管理型变量（出科死亡状态、住院天数等）已在 univariate/VIF 阶段通过
  # config$univariate_prognosis$excluded_predictors + multicollinearity$exclude_vars 剔除，
  # 因此此处拿到的均为合法基线协变量，不会再出现 auc_weib=1 的泄漏性虚高。
  include_baseline <- if (is.null(bl$include_index_baseline)) TRUE else isTRUE(bl$include_index_baseline)

  horizon   <- as.numeric(bl$horizon %||% ctx$config$trajectory_jlcm$max_followup %||% 28)
  landmarks <- as.numeric(bl$landmarks %||% 4:14)
  top_prop  <- as.numeric(bl$top_prop %||% 0.2)
  class_metric <- tolower(as.character(bl$class_metric %||% "youden")[1L])
  if (!class_metric %in% c("youden", "top_prop")) class_metric <- "youden"
  B_boot    <- as.integer(bl$boot_n %||% 2000L)
  B_perm    <- as.integer(bl$perm_n %||% 2000L)
  min_unique_time <- as.integer(bl$min_unique_time_for_dynpred %||% 4L)
  min_n_landmark  <- as.integer(bl$min_n_landmark %||% 30L)
  augment   <- if (is.null(bl$augment_with_covariates)) TRUE else isTRUE(bl$augment_with_covariates)
  # Youden 为默认主口径；仅当显式关闭且 class_metric=top_prop 时跳过
  youden    <- if (identical(class_metric, "youden")) TRUE else
    if (is.null(bl$include_youden_metrics)) TRUE else isTRUE(bl$include_youden_metrics)
  set.seed(as.integer(bl$seed %||% 2025L))
  cli::cli_alert_info("{Index}: Acc/Sens/Spec 主口径 = {class_metric}")

  base_all <- .twc02_baseline_rows(model_data)
  base_all$index_baseline <- suppressWarnings(as.numeric(base_all$scr_std))

  # 项目流程选出的协变量（覆盖优先级：显式配置 > JLCM covariate_vars_used）
  pipe_covs <- if (!is.null(bl$covariate_vars)) {
    as.character(bl$covariate_vars)
  } else {
    as.character(jlcm_entry$covariate_vars_used %||% character(0))
  }
  cov_use_weib <- intersect(pipe_covs, names(base_all))
  for (v in cov_use_weib) base_all[[v]] <- suppressWarnings(as.numeric(base_all[[v]]))
  # 可选：额外纳入指标基线值
  if (include_baseline) cov_use_weib <- c(cov_use_weib, "index_baseline")
  cov_use_weib <- unique(cov_use_weib)
  if (!length(cov_use_weib)) cov_use_weib <- "index_baseline"
  cli::cli_alert_info("{Index}: Weibull/增强协变量（流程 VIF 选出）= {paste(cov_use_weib, collapse=' + ')}")

  df_base_weib <- base_all[, c("subject_id_num", "surv_time", "surv_event", cov_use_weib), drop = FALSE]
  for (v in cov_use_weib) df_base_weib[[v]] <- suppressWarnings(as.numeric(df_base_weib[[v]]))
  df_base_weib <- df_base_weib[stats::complete.cases(df_base_weib), , drop = FALSE]
  if (nrow(df_base_weib) < 30) {
    cli::cli_alert_warning("trajectory_weibull_compare: {Index} 基线协变量完整样本不足，跳过")
    return(NULL)
  }

  weib_formula <- if (length(cov_use_weib)) {
    stats::as.formula(paste0("survival::Surv(surv_time, surv_event) ~ ", paste(cov_use_weib, collapse = " + ")))
  } else {
    stats::as.formula("survival::Surv(surv_time, surv_event) ~ 1")
  }
  weib_mod <- tryCatch(
    flexsurv::flexsurvreg(weib_formula, data = df_base_weib, dist = "weibull"),
    error = function(e) { cli::cli_alert_danger("{Index}: Weibull 拟合失败: {e$message}"); NULL }
  )
  if (is.null(weib_mod)) return(NULL)

  res_rows <- list()
  for (t_LM in landmarks) {
    tau <- horizon - t_LM
    na_row <- data.frame(
      Index = Index, landmark = t_LM, n_landmark = NA_integer_, events_future = NA_integer_,
      auc_dyn = NA_real_, auc_dyn_low = NA_real_, auc_dyn_high = NA_real_,
      auc_weib = NA_real_, auc_weib_low = NA_real_, auc_weib_high = NA_real_,
      c_dyn = NA_real_, c_dyn_low = NA_real_, c_dyn_high = NA_real_,
      c_weib = NA_real_, c_weib_low = NA_real_, c_weib_high = NA_real_,
      p_auc = NA_real_, p_cindex = NA_real_,
      acc_dyn = NA_real_, acc_weib = NA_real_, sens_dyn = NA_real_, sens_weib = NA_real_,
      spec_dyn = NA_real_, spec_weib = NA_real_,
      acc_dyn_top = NA_real_, acc_weib_top = NA_real_,
      sens_dyn_top = NA_real_, sens_weib_top = NA_real_,
      spec_dyn_top = NA_real_, spec_weib_top = NA_real_,
      sens_dyn_youden = NA_real_, sens_weib_youden = NA_real_,
      spec_dyn_youden = NA_real_, spec_weib_youden = NA_real_,
      acc_dyn_youden = NA_real_, acc_weib_youden = NA_real_
    )
    if (!is.finite(tau) || tau <= 0) { res_rows[[length(res_rows) + 1L]] <- na_row; next }

    df_eval <- df_base_weib[df_base_weib$surv_time > t_LM, , drop = FALSE]
    df_eval$future_event <- as.integer(df_eval$surv_event == 1 & df_eval$surv_time <= horizon)
    df_eval$time_LM <- pmax(pmin(df_eval$surv_time, horizon) - t_LM, 0.001)
    if (nrow(df_eval) < min_n_landmark || length(unique(df_eval$future_event)) < 2) {
      na_row$n_landmark <- nrow(df_eval); res_rows[[length(res_rows) + 1L]] <- na_row; next
    }

    newdata_model <- model_data[
      model_data$subject_id_num %in% df_eval$subject_id_num & model_data$time_day <= t_LM,
      , drop = FALSE
    ]
    tvals <- newdata_model$time_day[is.finite(newdata_model$time_day)]
    if (length(unique(tvals)) < min_unique_time) {
      na_row$n_landmark <- nrow(df_eval); res_rows[[length(res_rows) + 1L]] <- na_row; next
    }

    dp <- tryCatch(
      lcmm::dynpred(model_obj, newdata = newdata_model, landmark = t_LM, horizon = horizon, var.time = "time_day"),
      error = function(e) { cli::cli_alert_danger("{Index} day={t_LM}: dynpred 失败: {e$message}"); NULL }
    )
    if (is.null(dp)) { na_row$n_landmark <- nrow(df_eval); res_rows[[length(res_rows) + 1L]] <- na_row; next }

    dp_pred <- if (is.list(dp) && !is.null(dp$pred)) as.data.frame(dp$pred) else as.data.frame(dp)
    id_c   <- intersect(c("subject_id_num", "subject_id", "id"), names(dp_pred))[1]
    pred_c <- intersect(c("pred", "risk", "prob", "surv"), names(dp_pred))[1]
    if (is.na(id_c) || is.na(pred_c) || !nrow(dp_pred)) {
      na_row$n_landmark <- nrow(df_eval); res_rows[[length(res_rows) + 1L]] <- na_row; next
    }
    dp_pred <- dp_pred[, c(id_c, pred_c), drop = FALSE]
    names(dp_pred) <- c("subject_id_num", "risk_dyn")
    dp_pred$risk_dyn <- as.numeric(dp_pred$risk_dyn)

    df_eval <- merge(df_eval, dp_pred, by = "subject_id_num", all.x = TRUE)
    df_eval <- df_eval[is.finite(df_eval$risk_dyn), , drop = FALSE]
    if (nrow(df_eval) < min_n_landmark || length(unique(df_eval$future_event)) < 2) {
      res_rows[[length(res_rows) + 1L]] <- na_row; next
    }

    if (augment && length(cov_use_weib)) {
      aug_formula <- stats::as.formula(paste("future_event ~ risk_dyn +", paste(cov_use_weib, collapse = " + ")))
      aug_fit <- tryCatch(stats::glm(aug_formula, family = stats::binomial, data = df_eval), error = function(e) NULL)
      if (!is.null(aug_fit)) df_eval$risk_dyn <- stats::predict(aug_fit, newdata = df_eval, type = "response")
    }

    df_eval$risk_weib <- tryCatch(
      .twc02_weibull_cond_risk(weib_mod, df_eval[, cov_use_weib, drop = FALSE], t_LM, horizon),
      error = function(e) rep(NA_real_, nrow(df_eval))
    )
    df_eval <- df_eval[is.finite(df_eval$risk_weib), , drop = FALSE]
    if (nrow(df_eval) < min_n_landmark || length(unique(df_eval$future_event)) < 2) {
      res_rows[[length(res_rows) + 1L]] <- na_row; next
    }

    ci_auc_dyn <- .twc02_boot_ci(df_eval, function(d) .twc02_calc_auc_ipcw(d$time_LM, d$future_event, d$risk_dyn, tau), B_boot)
    ci_auc_w   <- .twc02_boot_ci(df_eval, function(d) .twc02_calc_auc_ipcw(d$time_LM, d$future_event, d$risk_weib, tau), B_boot)
    ci_c_dyn   <- .twc02_boot_ci(df_eval, function(d) .twc02_calc_cindex(d$time_LM, d$future_event, d$risk_dyn), B_boot)
    ci_c_w     <- .twc02_boot_ci(df_eval, function(d) .twc02_calc_cindex(d$time_LM, d$future_event, d$risk_weib), B_boot)

    auc_diff_fn <- function(time, event, a, b, tau) .twc02_calc_auc_ipcw(time, event, a, tau) - .twc02_calc_auc_ipcw(time, event, b, tau)
    c_diff_fn   <- function(time, event, a, b, tau) .twc02_calc_cindex(time, event, a) - .twc02_calc_cindex(time, event, b)
    p_auc_val <- tryCatch(.twc02_perm_p_paired(df_eval, "risk_dyn", "risk_weib", tau, B_perm, auc_diff_fn), error = function(e) NA_real_)
    p_c_val   <- tryCatch(.twc02_perm_p_paired(df_eval, "risk_dyn", "risk_weib", tau, B_perm, c_diff_fn), error = function(e) NA_real_)

    m_dyn  <- .twc02_metrics_top_prop(df_eval$future_event, df_eval$risk_dyn, top_prop)
    m_weib <- .twc02_metrics_top_prop(df_eval$future_event, df_eval$risk_weib, top_prop)
    y_dyn  <- if (youden) .twc02_metrics_youden(df_eval$future_event, df_eval$risk_dyn) else
      c(thr = NA_real_, acc = NA_real_, sens = NA_real_, spec = NA_real_)
    y_weib <- if (youden) .twc02_metrics_youden(df_eval$future_event, df_eval$risk_weib) else
      c(thr = NA_real_, acc = NA_real_, sens = NA_real_, spec = NA_real_)

    if (identical(class_metric, "youden")) {
      acc_d <- unname(y_dyn["acc"]);   acc_w <- unname(y_weib["acc"])
      sen_d <- unname(y_dyn["sens"]);  sen_w <- unname(y_weib["sens"])
      spe_d <- unname(y_dyn["spec"]);  spe_w <- unname(y_weib["spec"])
    } else {
      acc_d <- unname(m_dyn["acc"]);   acc_w <- unname(m_weib["acc"])
      sen_d <- unname(m_dyn["sens"]);  sen_w <- unname(m_weib["sens"])
      spe_d <- unname(m_dyn["spec"]);  spe_w <- unname(m_weib["spec"])
    }

    res_rows[[length(res_rows) + 1L]] <- data.frame(
      Index = Index, landmark = t_LM, n_landmark = nrow(df_eval), events_future = sum(df_eval$future_event),
      auc_dyn = ci_auc_dyn["est"], auc_dyn_low = ci_auc_dyn["low"], auc_dyn_high = ci_auc_dyn["high"],
      auc_weib = ci_auc_w["est"], auc_weib_low = ci_auc_w["low"], auc_weib_high = ci_auc_w["high"],
      c_dyn = ci_c_dyn["est"], c_dyn_low = ci_c_dyn["low"], c_dyn_high = ci_c_dyn["high"],
      c_weib = ci_c_w["est"], c_weib_low = ci_c_w["low"], c_weib_high = ci_c_w["high"],
      p_auc = p_auc_val, p_cindex = p_c_val,
      acc_dyn = acc_d, acc_weib = acc_w,
      sens_dyn = sen_d, sens_weib = sen_w,
      spec_dyn = spe_d, spec_weib = spe_w,
      acc_dyn_top = unname(m_dyn["acc"]), acc_weib_top = unname(m_weib["acc"]),
      sens_dyn_top = unname(m_dyn["sens"]), sens_weib_top = unname(m_weib["sens"]),
      spec_dyn_top = unname(m_dyn["spec"]), spec_weib_top = unname(m_weib["spec"]),
      sens_dyn_youden = unname(y_dyn["sens"]), sens_weib_youden = unname(y_weib["sens"]),
      spec_dyn_youden = unname(y_dyn["spec"]), spec_weib_youden = unname(y_weib["spec"]),
      acc_dyn_youden = unname(y_dyn["acc"]), acc_weib_youden = unname(y_weib["acc"]),
      row.names = NULL
    )
  }

  res <- do.call(rbind, res_rows)
  rownames(res) <- NULL
  res
}

# 与 run_fig_APRI_v2.R 完全对齐：Dynamic vs Weibull 双线 + 0.5 参考线 + 95%CI 误差棒 +
# 配对 permutation p 值标注 + x 轴按 landmark 天数 + coord_cartesian 收紧 y 轴。
.twc02_make_line_plot <- function(res, metric, ylab, title, p_col, landmarks, font_family) {
  suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(tidyr) })
  model_colors <- c("Dynamic prediction model" = "#D55E00", "Weibull survival model" = "#0072B2")
  dyn_col  <- paste0(metric, "_dyn");      weib_col <- paste0(metric, "_weib")
  lo_dyn   <- paste0(metric, "_dyn_low");  lo_weib  <- paste0(metric, "_weib_low")
  hi_dyn   <- paste0(metric, "_dyn_high"); hi_weib  <- paste0(metric, "_weib_high")
  has_ci <- all(c(lo_dyn, lo_weib, hi_dyn, hi_weib) %in% names(res))

  long_v <- res |>
    dplyr::select(landmark, dplyr::all_of(c(dyn_col, weib_col))) |>
    tidyr::pivot_longer(-landmark, names_to = "model", values_to = "val") |>
    dplyr::mutate(model = ifelse(grepl("_dyn$", model), "Dynamic prediction model", "Weibull survival model"))

  if (has_ci) {
    lo_v <- res |>
      dplyr::select(landmark, dplyr::all_of(c(lo_dyn, lo_weib))) |>
      tidyr::pivot_longer(-landmark, names_to = "model", values_to = "low") |>
      dplyr::mutate(model = ifelse(grepl("_dyn_low$", model), "Dynamic prediction model", "Weibull survival model"))
    hi_v <- res |>
      dplyr::select(landmark, dplyr::all_of(c(hi_dyn, hi_weib))) |>
      tidyr::pivot_longer(-landmark, names_to = "model", values_to = "high") |>
      dplyr::mutate(model = ifelse(grepl("_dyn_high$", model), "Dynamic prediction model", "Weibull survival model"))
    ci_v <- dplyr::left_join(lo_v, hi_v, by = c("landmark", "model"))
    all_high <- suppressWarnings(max(c(res[[hi_dyn]], res[[hi_weib]]), na.rm = TRUE))
    all_low  <- suppressWarnings(min(c(res[[lo_dyn]], res[[lo_weib]]), na.rm = TRUE))
  } else {
    ci_v <- NULL
    all_high <- suppressWarnings(max(c(res[[dyn_col]], res[[weib_col]]), na.rm = TRUE))
    all_low  <- suppressWarnings(min(c(res[[dyn_col]], res[[weib_col]]), na.rm = TRUE))
  }
  if (!is.finite(all_high)) all_high <- 1
  if (!is.finite(all_low))  all_low  <- 0.35
  y_max <- max(0.85, min(1.0, all_high + 0.03))
  y_min <- if (identical(metric, "auc")) 0.35 else max(0, min(0.35, all_low - 0.02))

  p_col_use <- if (!is.null(p_col) && p_col %in% names(res)) p_col else NA_character_
  p_labels <- res |>
    dplyr::mutate(
      .pv     = if (!is.na(p_col_use)) .data[[p_col_use]] else NA_real_,
      p_label = ifelse(is.na(.pv), "", ifelse(.pv < 0.001, "<0.001", sprintf("%.3f", .pv))),
      y_text  = pmin(pmax(.data[[dyn_col]], .data[[weib_col]], na.rm = TRUE) + 0.015, 0.995)
    )

  p <- ggplot2::ggplot() +
    ggplot2::geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey50", linewidth = 0.6) +
    ggplot2::geom_line(data = long_v, ggplot2::aes(x = landmark, y = val, colour = model), linewidth = 1) +
    ggplot2::geom_point(data = long_v, ggplot2::aes(x = landmark, y = val, colour = model, shape = model), size = 2)
  if (!is.null(ci_v)) {
    p <- p + ggplot2::geom_errorbar(
      data = ci_v, ggplot2::aes(x = landmark, ymin = low, ymax = high, colour = model),
      width = 0.15, linewidth = 0.5
    )
  }
  if (!is.na(p_col_use) && any(nzchar(p_labels$p_label))) {
    p <- p + ggplot2::geom_text(
      data = p_labels, ggplot2::aes(x = landmark, y = y_text, label = p_label),
      size = 2.8, vjust = 0, color = "#D55E00"
    )
  }
  p +
    ggplot2::scale_colour_manual(values = model_colors, name = NULL) +
    ggplot2::scale_shape_manual(values = c("Dynamic prediction model" = 17, "Weibull survival model" = 16), name = NULL) +
    ggplot2::scale_x_continuous(breaks = landmarks) +
    ggplot2::coord_cartesian(ylim = c(y_min, y_max)) +
    ggplot2::labs(title = title, x = "Days after ICU entry", y = ylab) +
    ggplot2::theme_bw(base_size = 13) +
    ggplot2::theme(legend.position = "top", plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
                   text = ggplot2::element_text(family = font_family))
}

# Acc/Sens/Spec：与 run_fig_APRI_v2.R 对齐的竖向散点图
# X = 指标值，Y = Days after ICU entry（不要用横向折线图）
.twc02_make_vertical_scatter <- function(res, metric, xlab, title, landmarks, font_family) {
  suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(tidyr) })
  model_colors <- c("Dynamic prediction model" = "#D55E00", "Weibull survival model" = "#0072B2")
  dyn_col  <- paste0(metric, "_dyn")
  weib_col <- paste0(metric, "_weib")
  if (!all(c(dyn_col, weib_col) %in% names(res))) {
    stop(sprintf("缺少列 %s / %s", dyn_col, weib_col), call. = FALSE)
  }
  long_v <- res |>
    dplyr::select(landmark, dplyr::all_of(c(dyn_col, weib_col))) |>
    tidyr::pivot_longer(-landmark, names_to = "model", values_to = "val") |>
    dplyr::mutate(
      model = ifelse(grepl("_dyn$", model), "Dynamic prediction model", "Weibull survival model")
    )
  ggplot2::ggplot(long_v, ggplot2::aes(x = val, y = landmark, colour = model, shape = model)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::scale_y_continuous(breaks = landmarks) +
    ggplot2::scale_colour_manual(values = model_colors, name = NULL) +
    ggplot2::scale_shape_manual(
      values = c("Dynamic prediction model" = 17, "Weibull survival model" = 16),
      name = NULL
    ) +
    ggplot2::labs(title = title, x = xlab, y = "Days after ICU entry") +
    ggplot2::theme_bw(base_size = 13) +
    ggplot2::theme(
      legend.position = "top",
      plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
      text = ggplot2::element_text(family = font_family)
    )
}

block_trajectory_weibull_compare <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr); library(cli); library(splines)
    if (requireNamespace("lcmm", quietly = TRUE)) library(lcmm)
    if (requireNamespace("flexsurv", quietly = TRUE)) library(flexsurv)
  })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)

  bl <- ctx$config$trajectory_weibull_compare %||% list()
  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  font_family <- if (exists("plot_font_from_config", mode = "function")) plot_font_from_config(ctx$config) else "sans"

  landmarks_vec <- as.numeric(bl$landmarks %||% 4:14)
  horizon_val   <- as.numeric(bl$horizon %||% ctx$config$trajectory_jlcm$max_followup %||% 28)
  top_prop_val  <- as.numeric(bl$top_prop %||% 0.2)
  class_metric  <- tolower(as.character(bl$class_metric %||% "youden")[1L])
  if (!class_metric %in% c("youden", "top_prop")) class_metric <- "youden"

  index_vars <- as.character(bl$index_vars %||% names(ctx$results$trajectory_jlcm_models %||% list()))
  if (!length(index_vars)) {
    cli::cli_alert_warning("trajectory_weibull_compare: 无可用 Index（未找到 trajectory_jlcm_models）")
    if (.twc02_should_pause(bl, "pause_on_no_output", TRUE)) {
      .twc02_pause(ctx, "trajectory_weibull_compare: 无可用 JLCM 模型。", "请确认 trajectory_jlcm 已先运行。", NULL)
    }
    return(ctx)
  }

  if (isTRUE(bl$replay_from_results) && length(ctx$results$trajectory_weibull_compare %||% list())) {
    all_res <- ctx$results$trajectory_weibull_compare
    cli::cli_alert_info("trajectory_weibull_compare: replay_from_results — 仅重绘 {length(all_res)} 个 Index")
  } else {
    all_res <- list()
    for (Index in index_vars) {
      cli::cli_h1("trajectory_weibull_compare: {Index}")
      res <- tryCatch(
        .twc02_run_one_index(ctx, bl, Index, ctx$config$project$root %||% getwd()),
        error = function(e) { cli::cli_alert_danger("{Index}: {e$message}"); NULL }
      )
      if (is.null(res) || !nrow(res)) next
      all_res[[Index]] <- res
    }
  }

  for (Index in names(all_res)) {
    res <- all_res[[Index]]
    if (is.null(res) || !nrow(res)) next
    out_csv <- file.path(out_tab, paste0("Table_Weibull_Dynamic_Compare_", Index, ".csv"))
    utils::write.csv(res, out_csv, row.names = FALSE)
    cli::cli_alert_success("{Index}: 落盘 {.file {basename(out_csv)}}")

    p_auc <- .twc02_make_line_plot(res, "auc", sprintf("AUC (landmark -> day %g)", horizon_val),
                                   Index, "p_auc", landmarks_vec, font_family)
    ctx <- save_figure(ctx, paste0("Figure_Weibull_Dynamic_Compare_", Index, "_AUC.pdf"),
                        local({ pp <- p_auc; function() pp }), width = 6.5, height = 4.8)

    p_c <- .twc02_make_line_plot(res, "c", sprintf("C-index (landmark -> day %g)", horizon_val),
                                 Index, "p_cindex", landmarks_vec, font_family)
    ctx <- save_figure(ctx, paste0("Figure_Weibull_Dynamic_Compare_", Index, "_Cindex.pdf"),
                        local({ pp <- p_c; function() pp }), width = 6.5, height = 4.8)

    for (metric_name in c("acc", "sens", "spec")) {
      metric_label <- if (identical(class_metric, "youden")) {
        switch(metric_name,
          acc  = "Accuracy (Youden)",
          sens = "Sensitivity (Youden)",
          spec = "Specificity (Youden)"
        )
      } else {
        switch(metric_name,
          acc  = sprintf("Accuracy (Top %.0f%%)", 100 * top_prop_val),
          sens = sprintf("Sensitivity (Top %.0f%%)", 100 * top_prop_val),
          spec = sprintf("Specificity (Top %.0f%%)", 100 * top_prop_val)
        )
      }
      p_m <- .twc02_make_vertical_scatter(
        res, metric_name, metric_label, Index, landmarks_vec, font_family
      )
      suffix <- switch(metric_name, acc = "Accuracy", sens = "Sensitivity", spec = "Specificity")
      # 竖向构图：与 run_fig_APRI_v2.R 一致用 5.5 x 6.2
      ctx <- save_figure(
        ctx,
        paste0("Figure_Weibull_Dynamic_Compare_", Index, "_", suffix, ".pdf"),
        local({ pp <- p_m; function() pp }),
        width = 5.5, height = 6.2
      )
    }
  }

  if (!length(all_res)) {
    if (.twc02_should_pause(bl, "pause_on_no_output", TRUE)) {
      .twc02_pause(ctx, "trajectory_weibull_compare: 所有 Index 均无有效结果。",
                   "请检查各 Index 的 JLCM 模型是否收敛、landmark 是否合理。", NULL)
    }
    cli::cli_alert_warning("trajectory_weibull_compare: 无有效输出")
    return(ctx)
  }

  ctx$results$trajectory_weibull_compare <- all_res
  cli::cli_alert_success("trajectory_weibull_compare 完成：{length(all_res)} 个 Index")
  ctx
}

register_block(
  "trajectory_weibull_compare", block_trajectory_weibull_compare,
  "JLCM dynpred(+协变量增强) vs Weibull：landmark AUC/C-index/bootstrap CI/permutation检验；Acc/Sens/Spec 默认 Youden（可选 Top-k%）"
)
