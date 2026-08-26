###############################################################################
#  performance_ml — ML 模型综合表现（平行线图、多模型 ROC、校准、DCA、
#        CV 箱线图、训练/验证集性能宽表、可选总览拼图）
#
#  register_block: "performance_ml"
#  典型流水线: train_validation → ml_models → performance_ml（勿与父块重复 source）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results$ml_eval_all, ctx$results$ml_models
#  require_data = ctx$data$train / test（ROC/校准/DCA）；Models/evalresult_<tag>.RData
#  发病: ROC/校准/DCA 真值为 Group；预后: survival$event_var，train/test 须与 imputed 对齐
#
#  # ── 配置 config$performance_ml ───────────────────────────────────────────
#  performance_ml = list(
#    enable = TRUE,
#    parallel_lines = TRUE, summary_tables = TRUE, cv_boxplot = TRUE,
#    roc_calibration_dca = TRUE, combined_panel = TRUE, ...
#  ),
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  平行线图、CV 箱线图、Table 4 宽表、多模型 ROC/校准/DCA PDF；combined_panel 时 2×4 总览
#  源: Blocks/23_ml_performance/01block_performance_ml.R
###############################################################################

# 本 block 全部图形统一 Times New Roman（新罗马）
.PM_FONT_FAMILY <- "Times New Roman"

.pm_font_family <- function(pm = NULL, cfg = NULL) {
  if (!is.null(cfg) && exists("plot_font_from_config", mode = "function")) {
    return(plot_font_from_config(cfg))
  }
  pref <- (cfg$plot %||% list())$font_family %||% .PM_FONT_FAMILY
  if (exists("resolve_plot_font_family", mode = "function")) {
    return(resolve_plot_font_family(pref))
  }
  pref
}

.pm_display_from_tag <- function(tag) {
  m <- c(
    dt = "DT", rf = "RF", xgboost = "XGBoost", enet = "ENet", rsvm = "RSVM",
    mlp = "MLP", logistic = "Logistic", lightgbm = "LightGBM", knn = "KNN",
    tabpfn = "TabPFN", adaboost = "AdaBoost", catboost = "CatBoost",
    tablcl_v2 = "TablCL_v2", rsf = "RSF", xgbsurv = "XGBSurv"
  )
  tg <- tolower(as.character(tag)[1L])
  v <- unname(m[tg])
  if (is.na(v)) toupper(tg) else v
}

.pm_match_rows <- function(d_tv, part) {
  cols <- names(part)
  if (!length(cols)) return(integer(0))
  if (!all(cols %in% names(d_tv))) {
    stop("block_performance_ml: train/test 列无法与 imputed 对齐。", call. = FALSE)
  }
  pc <- function(df, cn) {
    do.call(paste, c(lapply(cn, function(v) as.character(df[[v]])), list(sep = "\1")))
  }
  match(pc(part, cols), pc(d_tv, cols), nomatch = NA_integer_)
}

.pm_build_d_tv <- function(data, outcome_col, ref_group, ana_group) {
  d0 <- data
  if (!outcome_col %in% names(d0)) {
    stop("block_performance_ml: 结局列 ", outcome_col, " 不在 imputed 数据中。", call. = FALSE)
  }
  y_chr <- trimws(as.character(d0[[outcome_col]]))
  d0$Group <- factor(
    dplyr::case_when(
      y_chr == trimws(ana_group) ~ ana_group,
      y_chr == trimws(ref_group) ~ ref_group,
      TRUE ~ NA_character_
    ),
    levels = c(ref_group, ana_group)
  )
  d0[!is.na(d0$Group), , drop = FALSE]
}

.pm_resolve_models_dir_for_tag <- function(ctx, tag) {
  resolve_ml_models_dir_for_tag(ctx, tag)
}

.pm_load_evalresult <- function(models_dir, tag) {
  path <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  if (!file.exists(path)) return(NULL)
  env <- new.env(parent = emptyenv())
  tryCatch(
    load(path, envir = env),
    error = function(e) NULL
  )
  pt <- paste0("predtrain_", tag)
  pv <- paste0("predtest_", tag)
  e5 <- paste0("eval_best_cv5_", tag)
  e5s <- paste0("eval_best_cv5_", tag, "_spec")
  e5n <- paste0("eval_best_cv5_", tag, "_sens")
  if (!all(c(pt, pv) %in% names(env))) return(NULL)
  list(
    predtrain = get(pt, envir = env),
    predtest  = get(pv, envir = env),
    cv5_auc   = if (exists(e5, envir = env, inherits = FALSE)) get(e5, envir = env) else NULL,
    cv5_spec  = if (exists(e5s, envir = env, inherits = FALSE)) get(e5s, envir = env) else NULL,
    cv5_sens  = if (exists(e5n, envir = env, inherits = FALSE)) get(e5n, envir = env) else NULL
  )
}

.pm_default_colors <- function(n) {
  base <- c(
    "#223D6C", "#D20A13", "#088247", "#FFD121", "#6E568C", "#58CDD9",
    "#7A142C", "#91612D", "#377EB8", "#4DAF4A", "#984EA3", "#FF7F00"
  )
  if (n <= length(base)) base[seq_len(n)] else grDevices::colorRampPalette(base)(n)
}

.pm_plot_base_size <- function(pm, cfg) {
  x <- pm$plot_base_size %||% cfg$plot$base_size %||% 9
  sz <- suppressWarnings(as.numeric(x)[1L])
  if (!is.finite(sz) || sz <= 0) 9 else sz
}

# 各子图统一字号；图例默认放在绘图区内右下角，避免 PDF/拼图裁切
.pm_theme_ml <- function(font_family, base_size,
                         legend_position = c(0.72, 0.20),
                         legend_justification = c(1, 0)) {
  ggplot2::theme(
    text = ggplot2::element_text(size = base_size, family = font_family),
    axis.text = ggplot2::element_text(size = base_size * 0.95, family = font_family),
    axis.title = ggplot2::element_text(size = base_size, family = font_family),
    plot.title = ggplot2::element_text(
      size = base_size * 1.05, hjust = 0.5, family = font_family
    ),
    legend.text = ggplot2::element_text(size = base_size * 0.88, family = font_family),
    legend.title = ggplot2::element_text(size = base_size * 0.95, family = font_family),
    legend.position = legend_position,
    legend.justification = legend_justification,
    legend.background = ggplot2::element_blank(),
    legend.box.background = ggplot2::element_blank(),
    legend.key.size = ggplot2::unit(0.35, "lines"),
    plot.margin = ggplot2::margin(6, 12, 6, 6, "pt"),
    panel.grid.major = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    panel.background = ggplot2::element_blank()
  )
}

.pm_coord_clip_off <- function(p) {
  if (!inherits(p, "gg")) return(p)
  p + ggplot2::coord_cartesian(clip = "off")
}

.pm_parallel_metric_plot <- function(eval_df, display_order, colors, title, font_family, split_key,
                                    base_size = 9) {
  sk <- tolower(split_key)
  eval_df <- eval_df[tolower(as.character(eval_df$dataset)) == sk, , drop = FALSE]
  eval_df <- eval_df[as.character(eval_df$model) %in% display_order, , drop = FALSE]
  eval_df$model <- factor(as.character(eval_df$model), levels = display_order)
  eval_df <- eval_df[is.finite(eval_df$.estimate) & !is.na(eval_df$model), , drop = FALSE]
  ggplot2::ggplot(eval_df, ggplot2::aes(x = .data$.metric, y = .data$.estimate, color = .data$model)) +
    ggplot2::geom_point() +
    ggplot2::geom_line(ggplot2::aes(group = .data$model)) +
    ggplot2::scale_color_manual(values = stats::setNames(colors[seq_along(display_order)], display_order)) +
    ggplot2::theme_bw(base_size = base_size, base_family = font_family) +
    .pm_theme_ml(font_family, base_size, legend_position = c(0.88, 0.05), legend_justification = c(1, 0)) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 30, hjust = 1, family = font_family),
      legend.direction = "vertical",
      legend.box = "vertical"
    ) +
    ggplot2::scale_x_discrete(name = "Model metric") +
    ggplot2::labs(title = title, x = NULL, y = "Estimate") %>%
    .pm_coord_clip_off()
}

.pm_eval_wide_table <- function(eval_all, dataset_key, digits = 3L) {
  key <- tolower(dataset_key)
  ev <- eval_all[tolower(as.character(eval_all$dataset)) == key,
                 c(".metric", ".estimate", "model"), drop = FALSE]
  ev <- ev[ev$.metric %in% c("roc_auc", "accuracy", "sens", "spec", "f_meas"), , drop = FALSE]
  if (!nrow(ev)) return(NULL)
  out <- ev %>%
    dplyr::rename(metric = .metric, estimate = .estimate) %>%
    tidyr::pivot_wider(names_from = metric, values_from = estimate, values_fn = mean) %>%
    dplyr::select(
      dplyr::any_of(c("model", "roc_auc", "accuracy", "sens", "spec", "f_meas"))
    )
  num_cols <- vapply(out, is.numeric, logical(1L))
  if (any(num_cols)) {
    for (cn in names(out)[num_cols]) {
      out[[cn]] <- round(out[[cn]], digits = as.integer(digits)[1L])
    }
  }
  cn <- names(out)
  cn[cn == "roc_auc"] <- "AUC"
  cn[cn == "sens"] <- "Sensitivity"
  cn[cn == "spec"] <- "Specificity"
  cn[cn == "f_meas"] <- "F1"
  names(out) <- cn
  if ("model" %in% names(out)) {
    out$Model <- pipeline_display_no_underscore(out$model)
    out$model <- NULL
  }
  if ("Model" %in% names(out)) {
    out <- out[, c("Model", setdiff(names(out), "Model")), drop = FALSE]
  }
  out
}

.pm_cv_boxplot_data <- function(ctx, tags) {
  rows <- list()
  for (tg in tags) {
    L <- .pm_load_evalresult(.pm_resolve_models_dir_for_tag(ctx, tg), tg)
    if (is.null(L)) next
    disp <- .pm_display_from_tag(tg)
    for (piece in list(L$cv5_auc, L$cv5_spec, L$cv5_sens)) {
      if (is.null(piece) || !nrow(piece)) next
      df <- piece[, intersect(names(piece), c(".metric", ".estimate", "model")), drop = FALSE]
      if (!ncol(df)) next
      names(df)[names(df) == ".metric"] <- "metric"
      names(df)[names(df) == ".estimate"] <- "value"
      if (!"model" %in% names(df)) df$model <- disp
      df$model <- disp
      rows[[length(rows) + 1L]] <- df
    }
  }
  if (!length(rows)) return(NULL)
  dplyr::bind_rows(rows)
}

.pm_cv_boxplot_gg <- function(combined_data, font_family) {
  new_data <- combined_data
  names(new_data)[names(new_data) == "metric"] <- "metric"
  new_data$metric <- tolower(as.character(new_data$metric))
  new_data$metric[new_data$metric == "roc_auc"] <- "ROC"
  new_data$metric[new_data$metric == "spec"] <- "Spec"
  new_data$metric[new_data$metric == "sens"] <- "Sens"
  ci_data <- new_data %>%
    dplyr::group_by(.data$metric, .data$model) %>%
    dplyr::summarise(
      is_constant = length(unique(.data$value)) == 1L,
      lower = ifelse(.data$is_constant, .data$value[1L], stats::t.test(.data$value)$conf.int[1L]),
      upper = ifelse(.data$is_constant, .data$value[1L], stats::t.test(.data$value)$conf.int[2L]),
      ci_value = paste0(
        "95%CI(", format(round(.data$lower, 3), nsmall = 3), "-",
        format(round(.data$upper, 3), nsmall = 3), ")"
      ),
      .groups = "drop"
    )
  mean_data <- stats::aggregate(value ~ model + metric, data = new_data, mean)
  names(mean_data) <- c("model", "metric", "mean_value")
  sd_data <- stats::aggregate(value ~ model + metric, data = new_data, stats::sd)
  names(sd_data) <- c("model", "metric", "sd_value")
  merged_data <- merge(mean_data, sd_data, by = c("model", "metric"))
  merged_data <- merge(merged_data, ci_data, by = c("model", "metric"))
  min_values <- new_data %>%
    dplyr::group_by(.data$model, .data$metric) %>%
    dplyr::summarise(min_value = min(.data$value), .groups = "drop")
  merged_data <- dplyr::left_join(merged_data, min_values, by = c("model", "metric"))
  roc_mean_data <- merged_data[merged_data$metric == "ROC", , drop = FALSE]
  if (!nrow(roc_mean_data)) return(NULL)
  roc_mean_data <- roc_mean_data[order(roc_mean_data$mean_value), , drop = FALSE]
  new_data$model <- factor(new_data$model, levels = roc_mean_data$model)
  merged_data$model <- factor(merged_data$model, levels = roc_mean_data$model)
  ggplot2::ggplot(new_data, ggplot2::aes(x = .data$value, y = .data$model, fill = .data$model)) +
    ggplot2::geom_boxplot() +
    ggplot2::geom_text(
      data = merged_data,
      ggplot2::aes(
        x = .data$mean_value, y = .data$model,
        label = paste0(
          round(.data$mean_value, 3), "\u00b1", round(.data$sd_value, 3), "\n", .data$ci_value
        )
      ),
      hjust = 2, size = 3, family = font_family, inherit.aes = FALSE
    ) +
    ggplot2::facet_wrap(~metric, scales = "free_x") +
    ggplot2::labs(title = "", x = "", y = "") +
    ggplot2::scale_fill_manual(values = rep("white", length(unique(as.character(merged_data$model))))) +
    ggplot2::theme_bw(base_family = font_family) +
    ggplot2::theme(
      axis.text = ggplot2::element_text(family = font_family),
      axis.text.y = ggplot2::element_text(angle = 0, hjust = 1, family = font_family),
      strip.text = ggplot2::element_text(family = font_family),
      legend.position = "none",
      panel.grid = ggplot2::element_blank(),
      text = ggplot2::element_text(family = font_family)
    )
}

.pm_truth_vector <- function(ctx, part_df, prognosis, outcome_ml, ev_var, ana_group, ref_group) {
  n <- nrow(part_df)
  if (!prognosis) {
    y <- as.integer(part_df$Group == ana_group)
    return(list(truth01 = y, ok = rep(TRUE, n)))
  }
  if (is.null(ev_var) || !nzchar(ev_var)) {
    stop("block_performance_ml（预后）: 请设置 config$survival$event_var。", call. = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("block_performance_ml: 无 imputed 数据。", call. = FALSE)
  d_tv <- .pm_build_d_tv(data, outcome_ml, ref_group, ana_group)
  if (!ev_var %in% names(d_tv)) {
    stop("block_performance_ml: event 列 ", ev_var, " 不在数据中。", call. = FALSE)
  }
  idx <- .pm_match_rows(d_tv, part_df)
  if (anyNA(idx) || length(idx) != n) {
    stop(
      "block_performance_ml（预后）: 无法将预测表与 imputed 行对齐；请确认 train/test 与插补数据一致。",
      call. = FALSE
    )
  }
  # 关键：不可 as.numeric(factor)——会得到 1/2 水平码，校准 meanobs≈1.x，图上像贴在底部。
  # 优先用 .pm_build_d_tv 已映射的 Group（ref=对照, ana=事件）→ 严格 0/1。
  if ("Group" %in% names(d_tv)) {
    y <- as.integer(as.character(d_tv$Group[idx]) == trimws(as.character(ana_group)[1L]))
  } else {
    ev <- d_tv[[ev_var]][idx]
    if (is.factor(ev) || is.character(ev)) {
      y <- as.integer(trimws(as.character(ev)) == trimws(as.character(ana_group)[1L]))
    } else {
      y <- suppressWarnings(as.numeric(ev))
      uy <- sort(unique(y[is.finite(y)]))
      if (length(uy) == 2L && all(uy %in% c(1, 2))) {
        y <- as.integer(y == 2)
      } else {
        y <- as.integer(y)
      }
    }
  }
  list(truth01 = y, ok = is.finite(y))
}

.pm_multi_roc_plot <- function(test_df, display_order, colors, title, font_family, base_size = 9) {
  if (!requireNamespace("ROCit", quietly = TRUE) || !requireNamespace("plotROC", quietly = TRUE)) {
    return(NULL)
  }
  cls <- test_df$D
  resci <- data.frame()
  for (j in seq_along(display_order)) {
    nm <- display_order[j]
    if (!nm %in% names(test_df)) next
    ROC <- ROCit::rocit(score = test_df[[nm]], class = cls)
    rt <- tryCatch(ROCit::ciAUC(ROC), error = function(e) NULL)
    if (is.null(rt)) next
    auc_v <- suppressWarnings(as.numeric(rt$AUC %||% rt$auc %||% NA_real_))
    lo <- suppressWarnings(as.numeric(rt$lower %||% NA_real_))
    hi <- suppressWarnings(as.numeric(rt$upper %||% NA_real_))
    if (any(!is.finite(c(auc_v, lo, hi)))) next
    resci <- rbind(
      resci,
      data.frame(
        algorithm = nm,
        ROC = round(auc_v, 4),
        Lower = round(lo, 4),
        Upper = round(hi, 4),
        stringsAsFactors = FALSE
      )
    )
  }
  if (!nrow(resci)) return(NULL)
  resci <- resci[order(resci$algorithm), , drop = FALSE]
  resci$AUC <- paste0(resci$algorithm, " AUC: ", resci$ROC, "(", resci$Lower, "-", resci$Upper, ")")
  dfd <- test_df[, c("D", resci$algorithm), drop = FALSE]
  longtest <- dplyr::bind_rows(lapply(resci$algorithm, function(nm) {
    data.frame(
      D = dfd$D,
      M = suppressWarnings(as.numeric(dfd[[nm]])),
      Model = nm,
      stringsAsFactors = FALSE
    )
  }))
  longtest <- longtest[is.finite(longtest$M), , drop = FALSE]
  if (!nrow(longtest)) return(NULL)
  longtest$D <- suppressWarnings(as.integer(as.character(longtest$D)))
  longtest$D[is.na(longtest$D)] <- 0L
  longtest$Model <- factor(
    longtest$Model,
    levels = resci$algorithm,
    labels = resci$AUC
  )
  model_levels <- levels(longtest$Model)
  p <- ggplot2::ggplot(longtest, ggplot2::aes(d = .data$D, m = .data$M, color = .data$Model)) +
    plotROC::geom_roc(n.cuts = 0) +
    ggplot2::theme_bw(base_size = base_size, base_family = font_family) +
    ggplot2::geom_abline(intercept = 0, slope = 1, linetype = 2, color = "gray") +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25), expand = c(0, 0)) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25), expand = c(0, 0)) +
    ggplot2::scale_color_manual(
      values = {
        cv <- colors[match(resci$algorithm, display_order)]
        na <- is.na(cv)
        if (any(na)) {
          repc <- .pm_default_colors(sum(na, na.rm = TRUE))
          cv[na] <- repc[seq_len(sum(na, na.rm = TRUE))]
        }
        stats::setNames(cv, model_levels)
      }
    ) +
    ggplot2::xlab("") + ggplot2::ylab("") +
    .pm_theme_ml(font_family, base_size, legend_position = c(0.7, 0.14), legend_justification = c(0.5, 0)) +
    ggplot2::labs(title = title)
  .pm_coord_clip_off(p)
}

.pm_calibration_plot <- function(pred_wide, display_order, colors, title, font_family, base_size = 9) {
  if (!requireNamespace("PredictABEL", quietly = TRUE)) return(NULL)
  calall <- data.frame()
  pred_cols <- intersect(display_order, names(pred_wide))
  .to_percent <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    x[!is.finite(x)] <- NA_real_
    # PredictABEL HL 与 predRisk 同量纲；ML 概率通常 0–1，坐标轴用 %
    xx <- x[is.finite(x)]
    if (length(xx) && max(xx) <= 1.5 && min(xx) >= -1e-8) x * 100 else x
  }
  # PredictABEL::plotCalibration 会用基绘图设备画图；重定向到 null 避免污染 PDF 队列
  null_pdf <- tempfile(fileext = ".pdf")
  grDevices::pdf(null_pdf)
  on.exit({
    try(grDevices::dev.off(), silent = TRUE)
    unlink(null_pdf)
  }, add = TRUE)
  for (nm in pred_cols) {
    cal <- tryCatch(
      PredictABEL::plotCalibration(
        data = as.data.frame(pred_wide),
        cOutcome = 1L,
        predRisk = as.numeric(pred_wide[[nm]])
      ),
      error = function(e) NULL
    )
    if (is.null(cal)) next
    caldf <- as.data.frame(cal$Table_HLtest, stringsAsFactors = FALSE)
    if (!all(c("meanpred", "meanobs") %in% names(caldf))) next
    caldf$meanpred <- .to_percent(caldf$meanpred)
    caldf$meanobs <- .to_percent(caldf$meanobs)
    caldf <- caldf[
      is.finite(caldf$meanpred) & is.finite(caldf$meanobs) &
        caldf$meanpred >= 0 & caldf$meanpred <= 100 &
        caldf$meanobs >= 0 & caldf$meanobs <= 100,
      ,
      drop = FALSE
    ]
    if (!nrow(caldf)) next
    caldf$pi <- rownames(caldf)
    caldf$model <- nm
    calall <- rbind(calall, caldf)
  }
  try(grDevices::dev.off(), silent = TRUE)
  if (!nrow(calall)) return(NULL)
  cli::cli_alert_info(
    paste0(
      "calibration points: models=", length(unique(calall$model)),
      ", meanpred=[", round(min(calall$meanpred), 1), ", ", round(max(calall$meanpred), 1), "]",
      ", meanobs=[", round(min(calall$meanobs), 1), ", ", round(max(calall$meanobs), 1), "]"
    )
  )
  mods <- unique(as.character(calall$model))
  idxm <- match(mods, display_order)
  cal_cols <- rep(grDevices::gray(0.45), length(mods))
  okm <- !is.na(idxm) & idxm > 0L
  cal_cols[okm] <- colors[idxm[okm]]
  names(cal_cols) <- mods
  p <- ggplot2::ggplot(calall, ggplot2::aes(x = .data$meanpred, y = .data$meanobs, colour = .data$model)) +
    ggplot2::xlab("Predicted risk (%)") + ggplot2::ylab("Observed frequency (%)") +
    ggplot2::geom_abline(intercept = 0, slope = 1, linetype = 2, color = "gray") +
    ggplot2::scale_y_continuous(breaks = seq(0, 100, 25)) +
    ggplot2::scale_x_continuous(breaks = seq(0, 100, 25)) +
    ggplot2::scale_color_manual(values = cal_cols) +
    ggplot2::geom_point(size = 1.6) +
    ggplot2::geom_line(linewidth = 0.4) +
    ggplot2::coord_cartesian(xlim = c(0, 100), ylim = c(0, 100), expand = FALSE, clip = "off") +
    ggplot2::theme_bw(base_size = base_size, base_family = font_family) +
    .pm_theme_ml(font_family, base_size, legend_position = c(0.9, 0.14), legend_justification = c(1, 0)) +
    ggplot2::labs(title = title)
  p
}

# ── 概率校准：在训练集上拟合，返回对训练/验证集校准后的 pred_wide ─────────────
# method: "platt"（逻辑回归）或 "isotonic"（保序回归）
.pm_calibrate_wide <- function(wide_tr, wide_te, method = "platt") {
  pred_cols <- setdiff(names(wide_tr), "Outcome")
  if (!length(pred_cols)) return(list(tr = wide_tr, te = wide_te))
  cal_tr <- wide_tr
  cal_te <- wide_te %||% wide_tr[integer(0), ]
  for (nm in pred_cols) {
    raw_tr <- as.numeric(wide_tr[[nm]])
    raw_te <- if (!is.null(wide_te) && nm %in% names(wide_te)) as.numeric(wide_te[[nm]]) else NULL
    y_tr   <- as.integer(wide_tr$Outcome)
    ok_tr  <- is.finite(raw_tr) & is.finite(y_tr)
    if (sum(ok_tr) < 10L || length(unique(y_tr[ok_tr])) < 2L) next
    if (identical(method, "platt")) {
      # Platt scaling：用逻辑回归把 logit(raw) 重映射到概率
      df_fit <- data.frame(y = y_tr[ok_tr], x = raw_tr[ok_tr])
      fit <- tryCatch(
        stats::glm(y ~ x, data = df_fit, family = stats::binomial()),
        error = function(e) NULL)
      if (is.null(fit)) next
      cal_tr[[nm]] <- as.numeric(stats::predict(
        fit, newdata = data.frame(x = raw_tr), type = "response"))
      if (!is.null(raw_te) && length(raw_te))
        cal_te[[nm]] <- as.numeric(stats::predict(
          fit, newdata = data.frame(x = raw_te), type = "response"))
    } else {
      # Isotonic regression（保序回归）
      iso <- stats::isoreg(x = raw_tr[ok_tr], y = y_tr[ok_tr])
      stepfun <- stats::as.stepfun(iso)
      cal_tr[[nm]] <- pmin(pmax(stepfun(raw_tr), 0), 1)
      if (!is.null(raw_te) && length(raw_te))
        cal_te[[nm]] <- pmin(pmax(stepfun(raw_te), 0), 1)
    }
  }
  list(tr = cal_tr, te = cal_te)
}

# ── DCA 自动阈值：上限 = min(3×事件率, max预测概率95分位, 0.5) ───────────────
.pm_dca_auto_thresholds <- function(pred_wide, step = 0.01) {
  y    <- as.integer(pred_wide$Outcome)
  ev_rate <- mean(y, na.rm = TRUE)
  pred_cols <- setdiff(names(pred_wide), "Outcome")
  if (!length(pred_cols)) return(seq(0, 0.3, by = step))
  p95 <- quantile(
    unlist(pred_wide[, pred_cols, drop = FALSE]),
    probs = 0.95, na.rm = TRUE
  )
  upper <- min(max(3 * ev_rate, 0.05), p95, 0.5)
  upper <- ceiling(upper / step) * step   # 对齐步长
  seq(0, upper, by = step)
}

.pm_dca_auto_xlim <- function(tmp, ymin, ymax, step = 0.01) {
  thr <- as.numeric(tmp$threshold)
  nb <- as.numeric(tmp$net_benefit)
  ok <- is.finite(thr) & is.finite(nb) & nb >= ymin & nb <= ymax
  if (!any(ok)) ok <- is.finite(thr) & is.finite(nb)
  if (!any(ok)) return(c(0, 0.3))
  x_hi <- max(thr[ok], na.rm = TRUE)
  pad <- max(step * 2, x_hi * 0.03)
  c(0, min(1, x_hi + pad))
}

.pm_dca_plot <- function(pred_wide, display_order, font_family, y_max, y_min = 0,
                          title = "", thresholds = NULL, base_size = 9,
                          x_max = NULL, auto_xlim = FALSE) {
  if (!requireNamespace("dcurves", quietly = TRUE)) return(NULL)
  pred_cols <- intersect(display_order, names(pred_wide))
  if (!length(pred_cols)) return(NULL)
  # 自动计算阈值区间
  thr <- thresholds %||% .pm_dca_auto_thresholds(pred_wide)
  rhs <- paste(pred_cols, collapse = " + ")
  fml <- stats::as.formula(paste0("Outcome ~ ", rhs))
  dca_df <- pred_wide
  dca_obj <- tryCatch(
    dcurves::dca(fml, data = dca_df, thresholds = thr) %>% dcurves::as_tibble(),
    error = function(e) NULL
  )
  if (is.null(dca_obj)) return(NULL)
  tmp <- dca_obj[
    !is.nan(dca_obj$net_benefit) & !is.infinite(dca_obj$net_benefit) & dca_obj$net_benefit > -Inf,
    ,
    drop = FALSE
  ]
  if (!nrow(tmp)) return(NULL)
  ulev <- unique(as.character(dca_obj$variable))
  tmp$variable <- factor(tmp$variable, levels = ulev, ordered = TRUE)
  comb_names <- c("all", "none", display_order)
  comb_cols <- c(
    all = "#999999", none = "#666666",
    stats::setNames(.pm_default_colors(length(display_order)), display_order)
  )
  # 自适应窄范围：默认允许轻微负值；若传入 y_min（如 0），强制以下限为准
  if (!is.null(y_max) && is.finite(y_max)) {
    ymin <- if (!is.null(y_min) && is.finite(y_min)) as.numeric(y_min) else -abs(y_max) * 0.1
    ymax <- y_max
  } else {
    nb <- as.numeric(tmp$net_benefit)
    nb <- nb[is.finite(nb)]
    if (!length(nb)) return(NULL)
    q_lo <- as.numeric(stats::quantile(nb, 0.02, na.rm = TRUE))
    q_hi <- as.numeric(stats::quantile(nb, 0.98, na.rm = TRUE))
    ymin <- min(-0.005, q_lo - abs(q_lo) * 0.05 - 0.002)
    ymax <- max(0.05, q_hi + abs(q_hi) * 0.08 + 0.002)
    if (ymax <= ymin) {
      ymin <- min(nb, na.rm = TRUE) - 0.01
      ymax <- max(nb, na.rm = TRUE) + 0.01
    }
  }
  # 默认 y_min=0：不展示负净获益（treat-all 下穿部分截断）
  if (!is.null(y_min) && is.finite(y_min)) {
    ymin <- as.numeric(y_min)
    if (ymax <= ymin) ymax <- ymin + 0.01
  }
  if (isTRUE(auto_xlim) || is.null(x_max) || !is.finite(x_max)) {
    xlim <- .pm_dca_auto_xlim(tmp, ymin, ymax, step = 0.01)
  } else {
    xlim <- c(0, as.numeric(x_max))
  }
  ## 截断负值后再画，避免 scale limits 仍画出越界线段
  if (is.finite(ymin)) {
    tmp$net_benefit <- pmax(as.numeric(tmp$net_benefit), ymin)
  }
  col_values <- unname(comb_cols[ulev])
  col_values[is.na(col_values)] <- grDevices::gray(0.5)
  names(col_values) <- ulev
  p <- ggplot2::ggplot(tmp, ggplot2::aes(x = .data$threshold, y = .data$net_benefit)) +
    ggplot2::geom_line(ggplot2::aes(color = .data$variable), linewidth = 1) +
    ggplot2::scale_color_manual(name = "Models", values = col_values) +
    ggplot2::scale_x_continuous(
      limits = xlim,
      expand = ggplot2::expansion(mult = c(0.01, 0.02)),
      labels = scales::label_percent(accuracy = 1),
      name = "Threshold probability"
    ) +
    ggplot2::coord_cartesian(ylim = c(ymin, ymax), clip = "on") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.02, 0.04)), name = "Net benefit") +
    ggplot2::theme_bw(base_size = base_size, base_family = font_family) +
    .pm_theme_ml(font_family, base_size, legend_position = c(0.88, 0.98), legend_justification = c(1, 1)) +
    ggplot2::labs(title = as.character(title %||% ""))
  p
}

# C11 顺序：A 训练 ROC，B 验证 ROC，C 训练校准，D 验证校准，E 训练平行线，F 验证平行线，G 训练 DCA，H 验证 DCA
# 2×4 拼图：A/B c(0.7,0.14)；C/D c(0.9,0.14)；E/F 右下；G/H 右上
.pm_legend_combined_inset <- function(p, ncol_guide = 1L, base_size = 9,
                                      legend_position = c(0.97, 0.14),
                                      legend_justification = c(1, 0),
                                      font_family = .PM_FONT_FAMILY) {
  if (!inherits(p, "gg")) return(p)
  ncol_guide <- as.integer(ncol_guide[1L]); if (!is.finite(ncol_guide) || ncol_guide < 1L) ncol_guide <- 1L
  leg_sz <- base_size * 0.78
  p2 <- p + ggplot2::theme(
    text                  = ggplot2::element_text(family = font_family),
    axis.text             = ggplot2::element_text(family = font_family),
    axis.title            = ggplot2::element_text(family = font_family),
    plot.title            = ggplot2::element_blank(),
    strip.text            = ggplot2::element_text(family = font_family),
    legend.position       = legend_position,
    legend.justification  = legend_justification,
    legend.direction      = "vertical",
    legend.box            = "vertical",
    legend.text           = ggplot2::element_text(size = leg_sz, family = font_family),
    legend.title          = ggplot2::element_text(size = leg_sz * 1.05, family = font_family),
    legend.key.size       = ggplot2::unit(0.28, "lines"),
    legend.key.height     = ggplot2::unit(0.30, "lines"),
    legend.key.width      = ggplot2::unit(0.55, "lines"),
    legend.background     = ggplot2::element_blank(),
    legend.box.background = ggplot2::element_blank(),
    legend.margin         = ggplot2::margin(1, 2, 1, 1),
    legend.spacing.y      = ggplot2::unit(0, "cm"),
    plot.margin           = ggplot2::margin(5.5, 10, 5.5, 5.5, "pt")
  ) +
    ggplot2::guides(color = ggplot2::guide_legend(ncol = ncol_guide, byrow = TRUE))
  .pm_coord_clip_off(p2)
}

.pm_panel_labeled <- function(p, letter, subtitle, font_family, label_size,
                              title_strip = 0.07) {
  if (inherits(p, "gg")) {
    p <- p + ggplot2::theme(
      plot.title = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(4, 8, 6, 6, "pt")
    )
  }
  sub_size <- label_size * 0.82
  header <- cowplot::ggdraw() +
    cowplot::draw_label(
      letter, x = 0.01, y = 0.5, hjust = 0, vjust = 0.5,
      size = label_size, fontface = "bold", fontfamily = font_family
    ) +
    cowplot::draw_label(
      subtitle, x = 0.5, y = 0.5, hjust = 0.5, vjust = 0.5,
      size = sub_size, fontface = "plain", fontfamily = font_family
    )
  cowplot::plot_grid(header, p, ncol = 1L, rel_heights = c(title_strip, 1))
}

.pm_build_combined_2x4 <- function(panels, font_family, panel_titles = NULL,
                                    label_size = 12, legend_guide_ncol = 1L,
                                    base_size = 9) {
  if (!requireNamespace("cowplot", quietly = TRUE)) return(NULL)
  ord <- c("roc_tr", "roc_va", "cal_tr", "cal_va", "par_tr", "par_va", "dca_tr", "dca_va")
  default_titles <- c(
    "Training set", "Validation set",
    "Training set", "Validation set",
    "Training set — Model metrics", "Validation set — Model metrics",
    "Training set", "Validation set"
  )
  if (is.null(panel_titles) || length(panel_titles) != length(ord)) {
    panel_titles <- default_titles
  }
  plots <- lapply(ord, function(nm) panels[[nm]])
  if (any(vapply(plots, is.null, logical(1L)))) return(NULL)
  ncol <- 4L
  n <- length(plots)
  legend_layout <- list(
    list(pos = c(0.7, 0.14), just = c(0.5, 0)),   # A ROC
    list(pos = c(0.7, 0.14), just = c(0.5, 0)),   # B ROC
    list(pos = c(0.9, 0.14), just = c(1, 0)),     # C 校准
    list(pos = c(0.9, 0.14), just = c(1, 0)),     # D 校准
    list(pos = c(0.88, 0.05), just = c(1, 0)),   # E 平行线 — 右下
    list(pos = c(0.88, 0.05), just = c(1, 0)),   # F 平行线 — 右下
    list(pos = c(0.88, 0.98), just = c(1, 1)),   # G DCA — 右上
    list(pos = c(0.88, 0.98), just = c(1, 1))    # H DCA — 右上
  )
  plots <- lapply(seq_along(plots), function(i) {
    ly <- legend_layout[[i]]
    p <- plots[[i]]
    if (inherits(p, "gg")) {
      p <- p + ggplot2::theme(plot.title = ggplot2::element_blank())
    }
    .pm_legend_combined_inset(
      p,
      ncol_guide = legend_guide_ncol,
      base_size = base_size,
      legend_position = ly$pos,
      legend_justification = ly$just,
      font_family = font_family
    )
  })
  labeled <- lapply(seq_len(n), function(i) {
    title_strip <- if (i %in% c(5L, 6L)) 0.055 else 0.07
    .pm_panel_labeled(
      plots[[i]], letter = LETTERS[i], subtitle = panel_titles[i],
      font_family = font_family, label_size = label_size,
      title_strip = title_strip
    )
  })
  nrow_gr <- as.integer(ceiling(n / ncol))
  row_plots <- vector("list", nrow_gr)
  for (ri in seq_len(nrow_gr)) {
    si <- (ri - 1L) * ncol + 1L
    ei <- min(ri * ncol, n)
    row_plots[[ri]] <- cowplot::plot_grid(plotlist = labeled[si:ei], ncol = ncol, align = "hv")
  }
  cowplot::plot_grid(plotlist = row_plots, ncol = 1L, rel_heights = c(1, 1.02))
}

block_performance_ml <- function(ctx, ...) {
  if (!requireNamespace("magrittr", quietly = TRUE)) {
    stop("block_performance_ml: 需要 magrittr 包（提供 %>%）。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(magrittr))

  cfg <- ctx$config
  pm <- cfg$performance_ml %||% list()
  if (isFALSE(pm$enable %||% TRUE)) {
    cli::cli_alert_info("config$performance_ml$enable=FALSE，跳过 performance_ml。")
    return(ctx)
  }

  if (is.null(ctx$results$ml_eval_all) || !nrow(ctx$results$ml_eval_all)) {
    stop("block_performance_ml: 缺少 ctx$results$ml_eval_all，请先运行 ml_models。", call. = FALSE)
  }
  models <- ctx$results[["ml_models"]] %||% list()
  tags <- names(models)
  if (!length(tags)) {
    stop("block_performance_ml: ctx$results$ml_models 为空。", call. = FALSE)
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  prognosis <- identical(study_type, "prognosis")
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group <- cfg$project$reference_group %||% "Control"
  outcome_ml <- cfg$data$outcome_column %||% "Disease"
  ev_var <- cfg$survival$event_var %||% NULL
  pred_ana <- ctx$results$ml_pred_ana_col %||% paste0(".pred_", ana_group)

  font_family <- .pm_font_family(pm, cfg)
  if (!identical(font_family, .PM_FONT_FAMILY)) {
    cli::cli_alert_info(
      "block_performance_ml: Times New Roman 不可用，ggplot/PDF 将使用 '{font_family}'（与 render_queued_figures 一致）。"
    )
  }
  plot_base <- .pm_plot_base_size(pm, cfg)
  disease_lbl <- pm$disease_label %||% cfg$project$disease %||% cfg$project$analysis_group %||% "Outcome"

  display_order <- pm$model_display_order %||% vapply(tags, .pm_display_from_tag, character(1L))
  display_order <- unique(as.character(display_order))
  n_mod <- length(display_order)
  colors <- pm$model_colors %||% .pm_default_colors(n_mod)
  if (length(colors) < n_mod) {
    colors <- .pm_default_colors(n_mod)
  }

  ## ── 加载各模型 predtrain / predtest ─────────────────────────────────────
  loaded <- list()
  for (tg in tags) {
    models_dir <- .pm_resolve_models_dir_for_tag(ctx, tg)
    L <- .pm_load_evalresult(models_dir, tg)
    if (!is.null(L)) loaded[[tg]] <- L
  }
  if (!length(loaded)) {
    stop("block_performance_ml: 未在 Models/ 下找到 evalresult_<tag>.RData。", call. = FALSE)
  }
  tags_ok <- names(loaded)
  display_order <- display_order[vapply(display_order, function(d) {
    any(vapply(tags_ok, function(tg) identical(.pm_display_from_tag(tg), d), logical(1L)))
  }, logical(1L))]
  if (!length(display_order)) {
    display_order <- vapply(tags_ok, .pm_display_from_tag, character(1L))
  }

  want_combined <- isTRUE(pm$combined_panel %||% FALSE)
  pm_panels <- list(
    roc_tr = NULL, roc_va = NULL, cal_tr = NULL, cal_va = NULL,
    par_tr = NULL, par_va = NULL, dca_tr = NULL, dca_va = NULL
  )

  ## ── 平行线图 + 宽表（C11/C13 指标表）────────────────────────────────────
  if (isTRUE(pm$parallel_lines %||% TRUE)) {
    g_tr <- .pm_parallel_metric_plot(
      ctx$results$ml_eval_all, display_order, colors,
      "Training set — Model metrics", font_family, "train",
      base_size = plot_base
    )
    g_va <- .pm_parallel_metric_plot(
      ctx$results$ml_eval_all, display_order, colors,
      "Validation set — Model metrics", font_family, "test",
      base_size = plot_base
    )
    ctx <- save_figure(ctx, "Figure S. ML performance parallel train.pdf", function() g_tr, width = 6, height = 6)
    ctx <- save_figure(ctx, "Figure S. ML performance parallel validation.pdf", function() g_va, width = 6, height = 6)
    if (want_combined) {
      pm_panels$par_tr <- g_tr
      pm_panels$par_va <- g_va
    }
  }

  if (isTRUE(pm$summary_tables %||% TRUE)) {
    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    wt_tr <- .pm_eval_wide_table(ctx$results$ml_eval_all, "train", digits = as.integer(pm$table_digits %||% 3L)[1L])
    wt_va <- .pm_eval_wide_table(ctx$results$ml_eval_all, "test", digits = as.integer(pm$table_digits %||% 3L)[1L])
    if (!is.null(wt_tr)) {
      tr_pub <- pub_pair(
        ctx, tbl_dir, "main_table",
        title_caption = paste0("ML model performance (training) — ", disease_lbl),
        file_caption = "ML performance wide training",
        ext = "xlsx"
      )
      export_sci_table(wt_tr, tr_pub$filepath, title = tr_pub$title)
    }
    if (!is.null(wt_va)) {
      va_pub <- pub_pair(
        ctx, tbl_dir, "main_table",
        title_caption = paste0("ML model performance (validation) — ", disease_lbl),
        file_caption = "ML performance wide validation",
        ext = "xlsx"
      )
      export_sci_table(wt_va, va_pub$filepath, title = va_pub$title)
    }
    ctx <- render_queued_tables(ctx)
  }

  ## ── CV 箱线图（C12）──────────────────────────────────────────────────────
  if (isTRUE(pm$cv_boxplot %||% TRUE)) {
    cvdf <- .pm_cv_boxplot_data(ctx, tags_ok)
    if (!is.null(cvdf) && nrow(cvdf)) {
      g_cv <- .pm_cv_boxplot_gg(cvdf, font_family)
      if (!is.null(g_cv)) {
        ctx <- save_figure(
          ctx,
          "Figure S.ML internal validation ROC Sens Spec boxplot.pdf",
          function() g_cv,
          width = pm$cv_boxplot_width %||% 12,
          height = pm$cv_boxplot_height %||% 12
        )
        ctx$results$ml_performance_cv_metrics <- cvdf
      }
    } else {
      cli::cli_alert_warning("block_performance_ml: 无 CV 折指标可画箱线图（eval_best_cv5_* 缺失）。")
    }
  }

  ## ── ROC / 校准 / DCA（需扩展包）──────────────────────────────────────────
  do_roc <- isTRUE(pm$roc_calibration_dca %||% TRUE)
  cal_method <- tolower(trimws(pm$calibration_method %||% "platt"))
  if (!cal_method %in% c("platt", "isotonic", "none")) cal_method <- "platt"
  if (do_roc) {
    need <- c("ROCit", "plotROC", "PredictABEL", "dcurves")
    miss <- need[!vapply(need, requireNamespace, logical(1L), quietly = TRUE)]
    if (length(miss)) {
      cli::cli_alert_warning(
        "block_performance_ml: 缺少包 {paste(miss, collapse = ', ')}，",
        "已自动跳过 ROC/校准/DCA（其余并行线图/宽表仍照常输出）。"
      )
      do_roc <- FALSE
    }
  }

  if (do_roc) {
    .one_split <- function(split_name, ref_part_df) {
      n_ref <- nrow(ref_part_df)
      mats <- list()
      for (tg in tags_ok) {
        pr <- if (identical(split_name, "train")) loaded[[tg]]$predtrain else loaded[[tg]]$predtest
        if (is.null(pr) || !pred_ana %in% names(pr)) next
        if (nrow(pr) != n_ref) {
          cli::cli_alert_warning(
            "block_performance_ml: 模型 {tg} 预测行数 ({nrow(pr)}) 与 {split_name} ({n_ref}) 不一致（可能含 NA 行被丢弃），已跳过该模型的 ROC/DCA。"
          )
          next
        }
        mats[[.pm_display_from_tag(tg)]] <- as.numeric(pr[[pred_ana]])
      }
      tv <- .pm_truth_vector(ctx, ref_part_df, prognosis, outcome_ml, ev_var, ana_group, ref_group)
      truth01 <- tv$truth01
      ok <- tv$ok
      if (prognosis) {
        truth01 <- ifelse(ok, truth01, NA_real_)
      }
      D <- as.integer(if (prognosis) truth01 else as.integer(ref_part_df$Group == ana_group))
      test_df <- as.data.frame(mats, check.names = FALSE)
      test_df$D <- D
      ok2 <- is.finite(test_df$D) & apply(test_df[, names(mats), drop = FALSE], 1L, function(r) all(is.finite(r)))
      test_df <- test_df[ok2, , drop = FALSE]
      if (nrow(test_df) < 10L || length(unique(test_df$D)) < 2L) {
        cli::cli_alert_warning("block_performance_ml: {split_name} 有效样本不足，跳过多模型 ROC。")
        return(list(test_df = NULL))
      }
      list(test_df = test_df)
    }

    tr <- ctx$data$train
    te <- ctx$data$test
    if (is.null(tr) || is.null(te)) {
      stop("block_performance_ml: 需要 ctx$data$train / test。", call. = FALSE)
    }

    out_tr <- .one_split("train", tr)
    out_te <- .one_split("test", te)

    if (!is.null(out_tr$test_df)) {
      p_roc_tr <- .pm_multi_roc_plot(
        out_tr$test_df, display_order, colors, "Training set", font_family, base_size = plot_base
      )
      if (!is.null(p_roc_tr)) {
        ctx <- save_figure(ctx, "Figure S. ML performance ROC train.pdf", function() p_roc_tr, width = 6, height = 6)
        if (want_combined) pm_panels$roc_tr <- p_roc_tr
      }
    }
    if (!is.null(out_te$test_df)) {
      p_roc_va <- .pm_multi_roc_plot(
        out_te$test_df, display_order, colors, "Validation set", font_family, base_size = plot_base
      )
      if (!is.null(p_roc_va)) {
        ctx <- save_figure(ctx, "Figure S. ML performance ROC validation.pdf", function() p_roc_va, width = 6, height = 6)
        if (want_combined) pm_panels$roc_va <- p_roc_va
      }
    }

    ## 校准 + DCA：宽表 pred + outcome
    .wide_calib_dca <- function(split_name, ref_part_df) {
      n0 <- nrow(ref_part_df)
      tv <- .pm_truth_vector(ctx, ref_part_df, prognosis, outcome_ml, ev_var, ana_group, ref_group)
      y01 <- if (prognosis) tv$truth01 else as.integer(ref_part_df$Group == ana_group)
      if (prognosis) y01[!tv$ok] <- NA_real_
      wide <- data.frame(Outcome = y01, check.names = FALSE)
      for (tg in tags_ok) {
        pr <- if (identical(split_name, "train")) loaded[[tg]]$predtrain else loaded[[tg]]$predtest
        if (is.null(pr) || nrow(pr) != n0) next
        wide[[.pm_display_from_tag(tg)]] <- as.numeric(pr[[pred_ana]])
      }
      wide <- wide[is.finite(wide$Outcome) & apply(wide[, -1, drop = FALSE], 1L, function(z) all(is.finite(z))), ]
      if (nrow(wide) < 15L) return(NULL)
      wide
    }

    w_tr <- .wide_calib_dca("train", tr)
    w_te <- .wide_calib_dca("test", te)

    # ── 概率校准（Platt + Isotonic）：在训练集上拟合，分别应用到训练/验证集 ──
    if (!identical(cal_method, "none") && !is.null(w_tr)) {
      cli::cli_alert_info("概率校准（{cal_method}）：在训练集上拟合，应用于训练/验证集...")
      cal_res <- tryCatch(
        .pm_calibrate_wide(w_tr, w_te, method = cal_method),
        error = function(e) {
          cli::cli_alert_warning("概率校准失败（{e$message}），使用原始概率。")
          list(tr = w_tr, te = w_te)
        }
      )
      w_tr_cal <- cal_res$tr
      w_te_cal <- cal_res$te
      cli::cli_alert_success("概率校准完成（{cal_method}）。")
    } else {
      w_tr_cal <- w_tr
      w_te_cal <- w_te
    }

    # 自动计算 DCA 阈值（基于验证集或训练集的事件率）
    dca_thr <- tryCatch(
      .pm_dca_auto_thresholds(w_te_cal %||% w_tr_cal %||% w_tr),
      error = function(e) seq(0, 0.3, by = 0.01)
    )
    cli::cli_alert_info("DCA 阈值范围: 0 ~ {round(max(dca_thr)*100,1)}%（自动检测）")

    if (!is.null(w_tr)) {
      # 原始校准图（未校准）
      p_cal_tr <- .pm_calibration_plot(
        w_tr, display_order, colors, "Training set (Raw)", font_family, base_size = plot_base
      )
      if (!is.null(p_cal_tr)) {
        ctx <- save_figure(ctx, "Figure S. ML performance calibration train.pdf", function() p_cal_tr, width = 6, height = 6)
      }
      # 校准后校准图（2×4 组合图 C 格用校准后，与 DCA 一致；none 时回退 Raw）
      p_cal_tr2 <- NULL
      if (!identical(cal_method, "none")) {
        p_cal_tr2 <- .pm_calibration_plot(
          w_tr_cal, display_order, colors,
          paste0("Training set (", tools::toTitleCase(cal_method), " calibrated)"),
          font_family, base_size = plot_base
        )
        if (!is.null(p_cal_tr2))
          ctx <- save_figure(ctx, paste0("Figure S. ML performance calibration train calibrated.pdf"),
                             function() p_cal_tr2, width = 6, height = 6)
      }
      if (want_combined) pm_panels$cal_tr <- p_cal_tr2 %||% p_cal_tr
      # DCA 用校准后概率，自动阈值
      p_dca_tr <- .pm_dca_plot(
        w_tr_cal, display_order, font_family,
        if (isTRUE(pm$combined_dca_auto_ylim %||% TRUE) && want_combined) NULL else pm$dca_y_max,
        y_min = as.numeric(pm$dca_y_min %||% 0),
        title = "Training set", thresholds = dca_thr, base_size = plot_base,
        auto_xlim = isTRUE(pm$combined_dca_auto_xlim %||% pm$dca_auto_xlim %||% TRUE)
      )
      if (!is.null(p_dca_tr)) {
        ctx <- save_figure(ctx, "Figure S. ML performance DCA train.pdf", function() p_dca_tr, width = 6, height = 6)
        if (want_combined) {
          dca_thr_comb <- seq(0, 1, by = 0.01)
          pm_panels$dca_tr <- .pm_dca_plot(
            w_tr_cal, display_order, font_family,
            if (isTRUE(pm$combined_dca_auto_ylim %||% TRUE)) NULL else pm$dca_y_max,
            y_min = as.numeric(pm$dca_y_min %||% 0),
            title = "", thresholds = dca_thr_comb, base_size = plot_base,
            auto_xlim = FALSE, x_max = 1
          )
        }
      }
    }
    if (!is.null(w_te)) {
      # 原始校准图（未校准）
      p_cal_te <- .pm_calibration_plot(
        w_te, display_order, colors, "Validation set (Raw)", font_family, base_size = plot_base
      )
      if (!is.null(p_cal_te)) {
        ctx <- save_figure(ctx, "Figure S. ML performance calibration validation.pdf", function() p_cal_te, width = 6, height = 6)
      }
      # 校准后校准图（2×4 组合图 D 格用校准后；none 时回退 Raw）
      p_cal_te2 <- NULL
      if (!identical(cal_method, "none")) {
        p_cal_te2 <- .pm_calibration_plot(
          w_te_cal, display_order, colors,
          paste0("Validation set (", tools::toTitleCase(cal_method), " calibrated)"),
          font_family, base_size = plot_base
        )
        if (!is.null(p_cal_te2))
          ctx <- save_figure(ctx, paste0("Figure S. ML performance calibration validation calibrated.pdf"),
                             function() p_cal_te2, width = 6, height = 6)
      }
      if (want_combined) pm_panels$cal_va <- p_cal_te2 %||% p_cal_te
      # DCA 用校准后概率，自动阈值
      p_dca_te <- .pm_dca_plot(
        w_te_cal, display_order, font_family,
        if (isTRUE(pm$combined_dca_auto_ylim %||% TRUE) && want_combined) NULL else pm$dca_y_max,
        y_min = as.numeric(pm$dca_y_min %||% 0),
        title = "Validation set", thresholds = dca_thr, base_size = plot_base,
        auto_xlim = isTRUE(pm$combined_dca_auto_xlim %||% pm$dca_auto_xlim %||% TRUE)
      )
      if (!is.null(p_dca_te)) {
        ctx <- save_figure(ctx, "Figure S. ML performance DCA validation.pdf", function() p_dca_te, width = 6, height = 6)
        if (want_combined) {
          dca_thr_comb <- seq(0, 1, by = 0.01)
          pm_panels$dca_va <- .pm_dca_plot(
            w_te_cal, display_order, font_family,
            if (isTRUE(pm$combined_dca_auto_ylim %||% TRUE)) NULL else pm$dca_y_max,
            y_min = as.numeric(pm$dca_y_min %||% 0),
            title = "", thresholds = dca_thr_comb, base_size = plot_base,
            auto_xlim = FALSE, x_max = 1
          )
        }
      }
    }
  }

  ## ── 2×4 总览拼图（与 C11 相同：A–H，cowplot）────────────────────────────
  if (want_combined) {
    cal_cap <- if (!identical(cal_method, "none")) {
      tools::toTitleCase(cal_method)
    } else {
      "Raw"
    }
    comb_panel_titles <- c(
      "Training set", "Validation set",
      if (identical(cal_method, "none")) {
        c("Training set (Raw)", "Validation set (Raw)")
      } else {
        c(paste0("Training set (", cal_cap, " calibrated)"),
          paste0("Validation set (", cal_cap, " calibrated)"))
      },
      "Training set — Model metrics", "Validation set — Model metrics",
      "Training set", "Validation set"
    )
    comb <- .pm_build_combined_2x4(
      pm_panels, font_family,
      panel_titles = comb_panel_titles,
      label_size = as.numeric(pm$combined_label_size %||% 12)[1L],
      legend_guide_ncol = as.integer(pm$combined_legend_guide_ncol %||% 1L)[1L],
      base_size = plot_base
    )
    if (!is.null(comb)) {
      comb_fn <- pm$combined_filename %||%
        pub_figure_file(ctx, "main_figure", "ML performance combined 2x4")
      ctx <- save_figure(
        ctx,
        comb_fn,
        function() comb,
        width = as.numeric(pm$combined_width %||% 24)[1L],
        height = as.numeric(pm$combined_height %||% 12)[1L]
      )
      ctx$results$performance_ml_combined_grob <- TRUE
    } else {
      if (!requireNamespace("cowplot", quietly = TRUE)) {
        cli::cli_alert_warning("combined_panel=TRUE 需要安装 cowplot 包，已跳过 2×4 拼图。")
      } else {
        cli::cli_alert_warning(
          "combined_panel=TRUE 但 8 张子图未齐（需 parallel_lines 与 roc_calibration_dca 均成功，且 ROC/校准/DCA 数据充足），已跳过拼图。"
        )
      }
    }
  }

  ctx <- render_queued_figures(ctx)

  ctx$results$performance_ml_done <- TRUE
  cli::cli_alert_success("block_performance_ml 完成（study_type={study_type}）。")
  ctx
}

register_block(
  "performance_ml",
  block_performance_ml,
  "ML 综合表现：平行线图、多模型 ROC/校准/DCA、CV 箱线图、性能宽表（发病/预后）"
)
