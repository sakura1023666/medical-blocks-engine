###############################################################################
# ml_bootstrap_pub_tables.R — 发表用 bootstrap 表现表 / 校准表（预后 ML）
#
# performance_ml$bootstrap_ci_table = TRUE
#   → Train + Validation：TD-AUC / C-Index / Brier + 95%CI + Valid Bootstrap Iterations
# supplementary_ml methods 含 "calibration_boot"
#   → Validation：Calibration intercept / slope + 95%CI
#
# 口径：在已拟合预测上对评价集做非参数 bootstrap（不重训模型）。
###############################################################################

.mlboot_source_cindex <- function() {
  if (!exists(".mlsurv_cindex", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    hp <- if (nzchar(root)) file.path(root, "R/ml_survival_model_helpers.R") else "R/ml_survival_model_helpers.R"
    if (file.exists(hp)) source(hp, local = FALSE)
  }
}

.mlboot_td_auc <- function(time, event, risk, t_hor) {
  ok <- is.finite(time) & is.finite(risk) & !is.na(event)
  if (sum(ok) < 20L || sum(event[ok] == 1L) < 5L) return(NA_real_)
  df <- data.frame(time = time[ok], event = as.integer(event[ok]), risk = risk[ok])
  case <- df$event == 1L & df$time <= t_hor
  ctrl <- df$time > t_hor
  if (sum(case) < 2L || sum(ctrl) < 2L) return(NA_real_)
  rc <- df$risk[case]; rt <- df$risk[ctrl]
  u <- sum(outer(rc, rt, `>`)) + 0.5 * sum(outer(rc, rt, `==`))
  as.numeric(u / (length(rc) * length(rt)))
}

.mlboot_brier_at <- function(time, event, p_event, t_hor) {
  ok <- is.finite(time) & is.finite(p_event) & !is.na(event)
  if (sum(ok) < 20L) return(NA_real_)
  time <- time[ok]; event <- as.integer(event[ok]); p <- p_event[ok]
  keep <- (time > t_hor) | (event == 1L & time <= t_hor)
  if (sum(keep) < 10L) return(NA_real_)
  y <- as.integer(event[keep] == 1L & time[keep] <= t_hor)
  p <- pmin(pmax(p[keep], 0), 1)
  mean((p - y)^2)
}

.mlboot_orient_risk <- function(time, event, risk) {
  .mlboot_source_cindex()
  if (exists(".mlsurv_orient_risk", mode = "function")) {
    o <- .mlsurv_orient_risk(time, event, risk, NULL)
    return(list(risk = o$train, flipped = isTRUE(o$flipped)))
  }
  list(risk = as.numeric(risk), flipped = FALSE)
}

.mlboot_cindex <- function(time, event, risk) {
  .mlboot_source_cindex()
  if (exists(".mlsurv_cindex", mode = "function")) {
    return(as.numeric(.mlsurv_cindex(time, event, risk)))
  }
  if (requireNamespace("survival", quietly = TRUE)) {
    return(as.numeric(survival::concordance(survival::Surv(time, event) ~ risk)$concordance))
  }
  NA_real_
}

.mlboot_fmt_ci <- function(est, lo, hi, digits = 3L) {
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return(NA_character_)
  sprintf(paste0("%.", digits, "f (%.", digits, "f–%.", digits, "f)"), est, lo, hi)
}

.mlboot_pred_col <- function(df) {
  cn <- names(df)
  hit <- cn[grepl("_predicted_value$", cn)]
  if (!length(hit)) stop("ml_bootstrap: 无 *_predicted_value 列", call. = FALSE)
  hit[1L]
}

.mlboot_split_frame <- function(df, dataset_prefer = c("Validation set", "test", "validation")) {
  if (is.null(df) || !nrow(df)) return(NULL)
  if (!"dataset" %in% names(df)) return(df)
  te <- df[df$dataset %in% dataset_prefer, , drop = FALSE]
  if (nrow(te)) return(te)
  ## 英文/中文兜底
  te <- df[grepl("valid|test|验证", df$dataset, ignore.case = TRUE), , drop = FALSE]
  if (nrow(te)) return(te)
  df
}

.mlboot_eval_metrics <- function(time, event, risk0, horizon) {
  o <- .mlboot_orient_risk(time, event, risk0)
  risk <- o$risk
  ## 预后流水线 predicted_value 已为 scale01；否则才压缩
  p <- as.numeric(risk0)
  okp <- is.finite(p)
  if (any(okp) && min(p[okp]) >= 0 && max(p[okp]) <= 1) {
    p[!okp] <- NA_real_
  } else if (any(okp)) {
    p[okp] <- stats::plogis(p[okp] - mean(p[okp]))
  }
  p <- pmin(pmax(p, 1e-6), 1 - 1e-6)
  c(
    auc = .mlboot_td_auc(time, event, risk, horizon),
    cindex = .mlboot_cindex(time, event, risk),
    brier = .mlboot_brier_at(time, event, p, horizon)
  )
}

.mlboot_boot_one_model <- function(time, event, risk0, horizon, B, label) {
  pe <- .mlboot_eval_metrics(time, event, risk0, horizon)
  mat <- matrix(NA_real_, B, 3L, dimnames = list(NULL, c("auc", "cindex", "brier")))
  n <- length(time)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    if (sum(event[idx] == 1L, na.rm = TRUE) < 5L) next
    v <- tryCatch(
      .mlboot_eval_metrics(time[idx], event[idx], risk0[idx], horizon),
      error = function(e) c(auc = NA_real_, cindex = NA_real_, brier = NA_real_)
    )
    mat[b, ] <- v[c("auc", "cindex", "brier")]
  }
  q <- function(col) {
    x <- mat[, col]; x <- x[is.finite(x)]
    if (length(x) < 30L) return(c(NA_real_, NA_real_))
    as.numeric(stats::quantile(x, c(0.025, 0.975), names = FALSE, type = 7))
  }
  qa <- q("auc"); qc <- q("cindex"); qb <- q("brier")
  data.frame(
    Dataset = label,
    Model = NA_character_,
    `Time-Dependent AUC, 95% CI` = .mlboot_fmt_ci(pe["auc"], qa[1], qa[2], 3L),
    `C-Index, 95% CI` = .mlboot_fmt_ci(pe["cindex"], qc[1], qc[2], 3L),
    `Brier Score, 95% CI` = .mlboot_fmt_ci(pe["brier"], qb[1], qb[2], 4L),
    `Valid Bootstrap Iterations` = sum(stats::complete.cases(mat)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

#' 从 ctx$results$ml_predictions_all 生成 Train+Val bootstrap 表现表
mlboot_build_performance_table <- function(preds_by_tag, display_names = NULL,
                                           horizon = 48, B = 1000L, seed = 42L,
                                           model_order = NULL) {
  if (!length(preds_by_tag)) return(NULL)
  set.seed(as.integer(seed)[1L])
  B <- as.integer(B)[1L]
  horizon <- as.numeric(horizon)[1L]
  rows <- list()
  for (tg in names(preds_by_tag)) {
    df <- preds_by_tag[[tg]]
    if (is.null(df) || !nrow(df)) next
    disp <- if (!is.null(display_names) && tg %in% names(display_names)) {
      display_names[[tg]]
    } else tg
    pc <- .mlboot_pred_col(df)
    for (lab in c("Training set", "Validation set")) {
      prefer <- if (identical(lab, "Training set")) {
        c("Training set", "train", "training")
      } else {
        c("Validation set", "test", "validation")
      }
      sub <- .mlboot_split_frame(df, prefer)
      if (is.null(sub) || nrow(sub) < 20L) next
      if (!all(c(".time", ".event") %in% names(sub))) next
      time <- as.numeric(sub$.time)
      event <- as.integer(sub$.event)
      risk0 <- as.numeric(sub[[pc]])
      r <- .mlboot_boot_one_model(time, event, risk0, horizon, B, lab)
      r$Model <- disp
      rows[[length(rows) + 1L]] <- r
    }
  }
  if (!length(rows)) return(NULL)
  tab <- do.call(rbind, rows)
  if (!is.null(model_order) && length(model_order)) {
    tab$Model <- factor(tab$Model, levels = unique(c(model_order, tab$Model)))
  }
  tab$Dataset <- factor(tab$Dataset, levels = c("Training set", "Validation set"))
  tab <- tab[order(tab$Dataset, tab$Model), , drop = FALSE]
  tab$Model <- as.character(tab$Model)
  tab$Dataset <- as.character(tab$Dataset)
  rownames(tab) <- NULL
  tab
}

#' 文献分段 SCI 表：Training / Validation 段标题行
mlboot_performance_sci_df <- function(tab) {
  if (is.null(tab) || !nrow(tab)) return(NULL)
  mk <- function(label = "") {
    data.frame(
      Model = label,
      `Time-Dependent AUC, 95% CI` = "",
      `C-Index, 95% CI` = "",
      `Brier Score, 95% CI` = "",
      `Valid Bootstrap Iterations` = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  body_cols <- c(
    "Model", "Time-Dependent AUC, 95% CI", "C-Index, 95% CI",
    "Brier Score, 95% CI", "Valid Bootstrap Iterations"
  )
  tr <- tab[tab$Dataset == "Training set", body_cols, drop = FALSE]
  te <- tab[tab$Dataset == "Validation set", body_cols, drop = FALSE]
  out <- rbind(mk("Training set"), tr, mk(""), mk("Validation set"), te)
  rownames(out) <- NULL
  out
}

.mlboot_cal_once <- function(time, event, p, t_hor) {
  ok <- is.finite(time) & is.finite(p) & !is.na(event)
  time <- time[ok]; event <- as.integer(event[ok]); p <- p[ok]
  ## 行政截尾时点（如 28 天）上 time>t_hor 常为 0；用全分析行估 intercept/slope
  keep <- (time > t_hor) | (time <= t_hor)
  n_keep <- sum(keep)
  n_ev <- sum(event[keep] == 1L & time[keep] <= t_hor)
  if (n_keep < 10L || n_ev < 3L) {
    return(c(intercept = NA_real_, slope = NA_real_, n_event = n_ev))
  }
  y <- as.integer(event[keep] == 1L & time[keep] <= t_hor)
  p2 <- pmin(pmax(p[keep], 1e-6), 1 - 1e-6)
  if (length(unique(y)) < 2L) {
    return(c(intercept = NA_real_, slope = NA_real_, n_event = sum(y)))
  }
  fit <- tryCatch(stats::glm(y ~ qlogis(p2), family = binomial), error = function(e) NULL)
  if (is.null(fit) || !isTRUE(fit$converged) || length(stats::coef(fit)) < 2L) {
    return(c(intercept = NA_real_, slope = NA_real_, n_event = sum(y)))
  }
  cf <- stats::coef(fit)
  c(intercept = unname(cf[1]), slope = unname(cf[2]), n_event = sum(y))
}

#' 验证集校准 intercept / slope bootstrap 表
mlboot_build_calibration_table <- function(preds_by_tag, display_names = NULL,
                                           horizon = 48, B = 1000L, seed = 42L,
                                           model_order = NULL) {
  if (!length(preds_by_tag)) return(NULL)
  set.seed(as.integer(seed)[1L])
  B <- as.integer(B)[1L]
  horizon <- as.numeric(horizon)[1L]
  rows <- list()
  for (tg in names(preds_by_tag)) {
    df <- preds_by_tag[[tg]]
    if (is.null(df) || !nrow(df)) next
    disp <- if (!is.null(display_names) && tg %in% names(display_names)) {
      display_names[[tg]]
    } else tg
    te <- .mlboot_split_frame(df, c("Validation set", "test", "validation"))
    if (is.null(te) || nrow(te) < 10L) next
    if (!all(c(".time", ".event") %in% names(te))) next
    pc <- .mlboot_pred_col(te)
    time <- as.numeric(te$.time)
    event <- as.integer(te$.event)
    p <- as.numeric(te[[pc]])
    okp <- is.finite(p)
    if (!(any(okp) && min(p[okp]) >= 0 && max(p[okp]) <= 1)) {
      if (any(okp)) p[okp] <- stats::plogis(p[okp] - mean(p[okp]))
    }
    point <- .mlboot_cal_once(time, event, p, horizon)
    mat <- matrix(NA_real_, B, 3L)
    n <- length(time)
    for (b in seq_len(B)) {
      idx <- sample.int(n, n, replace = TRUE)
      mat[b, ] <- .mlboot_cal_once(time[idx], event[idx], p[idx], horizon)
    }
    ok <- is.finite(mat[, 1]) & is.finite(mat[, 2])
    n_ok <- sum(ok)
    qi <- if (n_ok >= 30L) stats::quantile(mat[ok, 1], c(0.025, 0.975), names = FALSE, type = 7) else c(NA, NA)
    qs <- if (n_ok >= 30L) stats::quantile(mat[ok, 2], c(0.025, 0.975), names = FALSE, type = 7) else c(NA, NA)
    med_ev <- if (n_ok >= 1L) as.integer(stats::median(mat[ok, 3])) else NA_integer_
    rows[[tg]] <- data.frame(
      Model = disp,
      `Calibration intercept, mean (95% CI)` = .mlboot_fmt_ci(point["intercept"], qi[1], qi[2], 3L),
      `Calibration slope, mean (95% CI)` = .mlboot_fmt_ci(point["slope"], qs[1], qs[2], 3L),
      `Valid bootstrap iterations` = n_ok,
      `Median number of events before horizon` = med_ev,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(NULL)
  tab <- do.call(rbind, rows)
  if (!is.null(model_order) && length(model_order)) {
    tab$Model <- factor(tab$Model, levels = unique(c(model_order, as.character(tab$Model))))
    tab <- tab[order(tab$Model), , drop = FALSE]
    tab$Model <- as.character(tab$Model)
  }
  rownames(tab) <- NULL
  tab
}
