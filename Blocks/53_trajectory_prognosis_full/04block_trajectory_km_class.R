###############################################################################
#  trajectory_km_class — 潜类别（trajectory_class）Kaplan-Meier 曲线 + log-rank
#
#  合并 Fig2B.R（自建模型直接出 KM）与 run_figS1_APRI.R（预计算 class 列出 KM）的逻辑：
#  统一按「事件截断在 max_followup 天、未发生事件者一律删失在 max_followup 天」的口径
#  处理生存时间，绘图时对恰好在随访终点死亡的样本做极小 epsilon 前移，避免刻度重叠。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#                 需含 trajectory_class（或 trajectory_class_{Index}，由 trajectory_jlcm
#                 的 assign_class_ng 回写）
#  require_pkg  = survival, survminer, dplyr, ggplot2
#
#  trajectory_km_class = list(
#    index_vars          = NULL,   # NULL → 用裸列 trajectory_class；否则遍历 trajectory_class_{Index}
#    class_col           = NULL,   # 显式指定类别列名，优先级最高
#    survival_time_var   = NULL,   # NULL → config$survival$time_var
#    survival_event_var  = NULL,   # NULL → config$survival$event_var
#    max_followup        = 28,
#    class_colors        = c("Class 1"="#D55E00","Class 2"="#E69F00","Class 3"="#56B4E9",
#                             "Class 4"="#009E73","Class 5"="#CC79A7","Class 6"="#999999"),
#    break_time_by       = NULL,   # NULL → round(max_followup/7) 天
#    risk_table          = TRUE,
#    pause_enable        = TRUE,
#    pause_on_no_output  = TRUE
#  ),
#
#  register_block: "trajectory_km_class"
#  写: ctx$results$trajectory_km_class[[Index]]
#  落盘: Figures/Figure_KM_TrajectoryClass_{Index}.pdf
#        Tables/Table_KM_TrajectoryClass_{Index}_Events.csv / _LogRank.csv
###############################################################################

.tkc04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tkc04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_km_class", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tkc04_to_event01 <- function(x) {
  xs <- trimws(as.character(x))
  dplyr::case_when(
    xs %in% c("1", "Non-survivor", "Dead", "dead", "DEAD", "Yes", "TRUE", "T") ~ 1L,
    xs %in% c("0", "Survivor", "Alive", "alive", "ALIVE", "No", "FALSE", "F") ~ 0L,
    TRUE ~ suppressWarnings(as.integer(xs))
  )
}

.tkc04_run_one <- function(ctx, data, bl, Index, class_col, time_var, event_var,
                            max_followup, class_colors, break_time_by, risk_table, font_family) {
  if (!class_col %in% names(data)) {
    cli::cli_alert_warning("trajectory_km_class: 缺少类别列 {class_col}，跳过 {Index %||% ''}")
    return(NULL)
  }
  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("trajectory_km_class: 缺少生存列 (", time_var, "/", event_var, ")", call. = FALSE)
  }

  km_data <- data.frame(
    class = data[[class_col]],
    raw_time = suppressWarnings(as.numeric(as.character(data[[time_var]]))),
    event = .tkc04_to_event01(data[[event_var]])
  )
  km_data <- km_data[!is.na(km_data$class) & !is.na(km_data$event), , drop = FALSE]
  km_data$survival_time <- ifelse(
    km_data$event == 0, max_followup,
    pmin(suppressWarnings(as.numeric(km_data$raw_time)), max_followup)
  )
  km_data <- km_data[!is.na(km_data$survival_time) & km_data$survival_time > 0, , drop = FALSE]

  # imputed$trajectory_class 已是展示编号时不再 majority-swap（否则双库对反）
  class_num0 <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(km_data$class))))
  swap_map   <- if (exists("trajectory_resolve_class_map", mode = "function")) {
    trajectory_resolve_class_map(class_num0, ctx$config, Index, source = "aligned")
  } else if (exists("trajectory_class_swap_map", mode = "function")) {
    trajectory_class_swap_map(class_num0)
  } else {
    stats::setNames(sort(unique(class_num0)), sort(unique(class_num0)))
  }
  class_num  <- if (exists("trajectory_apply_class_swap", mode = "function"))
    trajectory_apply_class_swap(class_num0, swap_map) else class_num0
  km_data$class <- factor(class_num, levels = sort(unique(class_num)),
                           labels = paste0("Class ", sort(unique(class_num))))
  km_data <- km_data[!is.na(km_data$class), , drop = FALSE]

  if (!nrow(km_data) || nlevels(droplevels(km_data$class)) < 2) {
    cli::cli_alert_warning("trajectory_km_class: {Index %||% ''} 有效数据不足或类别数<2，跳过")
    return(NULL)
  }

  eps <- 1e-3
  km_data$time_plot <- ifelse(
    km_data$event == 1 & km_data$survival_time >= max_followup,
    max_followup - eps, km_data$survival_time
  )

  events_by_class <- km_data |>
    dplyr::group_by(class) |>
    dplyr::summarise(
      n = dplyr::n(), events = sum(event == 1), censored = sum(event == 0),
      event_rate = round(mean(event == 1) * 100, 2), .groups = "drop"
    )

  sd_res <- tryCatch(
    survival::survdiff(survival::Surv(time_plot, event) ~ class, data = km_data),
    error = function(e) NULL
  )
  p_val <- if (!is.null(sd_res)) stats::pchisq(sd_res$chisq, df = length(sd_res$n) - 1, lower.tail = FALSE) else NA_real_

  km_fit <- survival::survfit(survival::Surv(time_plot, event) ~ class, data = km_data)

  class_labels <- levels(km_data$class)
  palette_use  <- unname(class_colors[class_labels])
  palette_use[is.na(palette_use)] <- scales::hue_pal()(length(class_labels))[is.na(palette_use)]

  if (!requireNamespace("survminer", quietly = TRUE)) {
    cli::cli_alert_warning("trajectory_km_class: 未安装 survminer，跳过绘图（仅输出统计表）")
    surv_plot <- NULL
  } else {
    # 与 Fig2B.R 一致：ggsurvplot 自带 log-rank p 值、conf.int 默认样式、风险表按 strata 着色
    surv_plot <- survminer::ggsurvplot(
      km_fit, data = km_data,
      xlim = c(0, max_followup), break.time.by = break_time_by,
      pval = TRUE, pval.coord = c(max_followup * 0.2, 0.2),
      conf.int = TRUE,
      legend.title = "Latent Class", legend.labs = class_labels,
      palette = palette_use,
      xlab = paste0("Time (Days, ", max_followup, "-day follow-up)"),
      ylab = "Survival Probability",
      ggtheme = ggplot2::theme_bw(base_size = 12),
      risk.table = isTRUE(risk_table), risk.table.col = "strata",
      risk.table.y.text.col = TRUE, risk.table.y.text = FALSE,
      risk.table.height = 0.25, ncensor.plot = FALSE
    )
    surv_plot$plot <- surv_plot$plot +
      ggplot2::theme(text = ggplot2::element_text(family = font_family))
  }

  list(
    events_by_class = events_by_class,
    logrank = data.frame(
      chisq = if (!is.null(sd_res)) round(sd_res$chisq, 3) else NA_real_,
      df = if (!is.null(sd_res)) length(sd_res$n) - 1 else NA_integer_,
      p_value = round(p_val, 6)
    ),
    plot = surv_plot
  )
}

block_trajectory_km_class <- function(ctx, ...) {
  suppressPackageStartupMessages({ library(dplyr); library(cli) })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)
  bl <- ctx$config$trajectory_km_class %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_km_class: 无数据", call. = FALSE)

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  font_family <- if (exists("plot_font_from_config", mode = "function")) plot_font_from_config(ctx$config) else "sans"

  time_var  <- bl$survival_time_var  %||% ctx$config$survival$time_var  %||% "futime"
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% "Mortality_28d"
  max_followup <- as.numeric(bl$max_followup %||% 28)
  # 与 Fig2B.R 一致：28 天随访默认 7 天刻度
  break_time_by <- as.numeric(bl$break_time_by %||% max(1, round(max_followup / 4)))
  risk_table <- if (is.null(bl$risk_table)) TRUE else isTRUE(bl$risk_table)
  class_colors <- bl$class_colors %||% c(
    "Class 1" = "#D55E00", "Class 2" = "#E69F00", "Class 3" = "#56B4E9",
    "Class 4" = "#009E73", "Class 5" = "#CC79A7", "Class 6" = "#999999"
  )

  index_vars <- bl$index_vars %||% NULL
  explicit_col <- bl$class_col %||% NULL

  targets <- if (!is.null(explicit_col)) {
    list(list(Index = NULL, col = explicit_col))
  } else if (!is.null(index_vars) && length(index_vars)) {
    lapply(index_vars, function(ix) {
      col <- paste0("trajectory_class_", ix)
      if (!col %in% names(data)) col <- "trajectory_class"
      list(Index = ix, col = col)
    })
  } else {
    list(list(Index = NULL, col = "trajectory_class"))
  }

  results_all <- list()
  for (t in targets) {
    key <- t$Index %||% "_"
    res <- tryCatch(
      .tkc04_run_one(ctx, data, bl, t$Index, t$col, time_var, event_var,
                      max_followup, class_colors, break_time_by, risk_table, font_family),
      error = function(e) { cli::cli_alert_danger("trajectory_km_class {key}: {e$message}"); NULL }
    )
    if (is.null(res)) next
    results_all[[key]] <- res

    suffix <- if (is.null(t$Index)) "" else paste0("_", t$Index)
    utils::write.csv(res$events_by_class, file.path(out_tab, paste0("Table_KM_TrajectoryClass", suffix, "_Events.csv")), row.names = FALSE)
    utils::write.csv(res$logrank, file.path(out_tab, paste0("Table_KM_TrajectoryClass", suffix, "_LogRank.csv")), row.names = FALSE)

    if (!is.null(res$plot)) {
      fn <- paste0("Figure_KM_TrajectoryClass", suffix, ".pdf")
      ctx <- save_figure(ctx, fn, local({ pp <- res$plot; function() pp }), width = 8, height = 6)
    }
  }

  if (!length(results_all)) {
    if (.tkc04_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tkc04_pause(
        ctx, "trajectory_km_class: 未产出任何 KM 结果。",
        "请确认 trajectory_jlcm 已配置 assign_class_ng 回写 trajectory_class。", NULL
      )
    }
    cli::cli_alert_warning("trajectory_km_class: 无有效输出")
    return(ctx)
  }

  ctx$results$trajectory_km_class <- results_all
  cli::cli_alert_success("trajectory_km_class 完成：{length(results_all)} 组结果")
  ctx
}

register_block(
  "trajectory_km_class", block_trajectory_km_class,
  "潜类别 28 天口径 KM 曲线 + log-rank（Class 配色 + 风险表）"
)
