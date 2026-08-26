###############################################################################
#  subgroup_treatment_forest — 多臂治疗/管理方案 × 分类亚组 Cox 森林图（ggplot）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_config = config$subgroup_treatment_forest, config$survival
#                   （time_var / event_var / event_value 三者必填，块内无兜底）
#
#  subgroup_treatment_forest = list(
#    treatment_var    = "Postop_Management_Group",
#    reference_level  = NULL,              # NULL = factor 第一水平为参照
#    subgroup_vars    = c(...),            # 亚组变量名向量（必填）
#    hr_coef_min      = 0.001,
#    hr_coef_max      = 100,
#    hr_upper_max     = 1000,
#    plot_colors      = c("#4E79A7", "#A0353B", "#1F9A8E", "#A65628", "#88419D"),
#    figure_width     = 12,
#    figure_height    = 10,
#    x_log_breaks     = c(0.1, 0.5, 1, 2, 5, 10),
#    figure_caption   = "Forest Plot Subgroup Analysis of RFS",  # pub_figure_file caption
#    table_filename   = "Table_Subgroup_Treatment_CoxHR.xlsx",
#    table_title      = "Subgroup Cox HR by treatment arm (95% CI)",
#    pause_enable     = TRUE,
#    pause_on_no_valid_hr = TRUE
#  ),
#
#  产出（发表序号 / 固定名）:
#    - [main_figure] Figure n.*  Subgroup forest (treatment arms) → pub_figure_file + save_figure
#    - [固定名]      Table_Subgroup_Treatment_CoxHR.xlsx + .tex   → export_sci_table（不占发表表序号）
#    - [固定名]      subgroup_treatment_plot_data.RData           → save_result
#
#  写: ctx$results$subgroup_treatment_forest, subgroup_treatment_ref, subgroup_treatment_vars
#
#  pause: config$subgroup_treatment_forest$pause_enable
###############################################################################

.stf07_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.stf07_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "subgroup_treatment_forest",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: Subgroup treatment forest halted. See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.stf07_event_indicator <- function(x, event_value) {
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    ev_chr <- as.character(event_value)
    return(as.integer(x == ev_chr))
  }
  as.integer(x == event_value)
}

.stf07_compute_subgroup_hr <- function(
    rt,
    idx,
    treat_var,
    treat_levels,
    time_col,
    status_col,
    hr_coef_min,
    hr_coef_max,
    hr_upper_max
) {
  orig_levels <- levels(factor(rt[[idx]], exclude = NULL))
  purrr::map_dfr(seq_along(orig_levels), function(i) {
    sub <- orig_levels[[i]]
    subset_data <- rt[rt[[idx]] == sub & !is.na(rt[[idx]]), , drop = FALSE]
    n_total <- nrow(subset_data)
    sub_label <- paste0(sub, " (n=", n_total, ")")

    placeholder <- data.frame(
      Variable = idx,
      Subgroup = sub_label,
      Treatment = treat_levels[-1L],
      HR = NA_real_,
      Lower = NA_real_,
      Upper = NA_real_,
      Level_Order = i,
      stringsAsFactors = FALSE
    )

    n_events <- sum(subset_data[[status_col]] == 1L, na.rm = TRUE)
    if (length(unique(subset_data[[treat_var]])) < 2L || n_events < 1L) {
      return(placeholder)
    }

    subset_data[[treat_var]] <- droplevels(subset_data[[treat_var]])
    cox_formula <- stats::as.formula(
      paste0("survival::Surv(", time_col, ", ", status_col, ") ~ ", treat_var)
    )

    fit <- tryCatch(
      survival::coxph(cox_formula, data = subset_data),
      error = function(e) NULL
    )
    if (is.null(fit)) return(placeholder)

    s <- summary(fit)
    res_raw <- as.data.frame(s$conf.int)
    if (nrow(res_raw) == 0L) return(placeholder)

    res_processed <- res_raw
    res_processed$is_bad <- (
      res_processed[["exp(coef)"]] < hr_coef_min |
        res_processed[["exp(coef)"]] > hr_coef_max |
        res_processed[["upper .95"]] > hr_upper_max
    )
    res_processed$HR <- ifelse(res_processed$is_bad, NA_real_, res_processed[["exp(coef)"]])
    res_processed$Lower <- ifelse(res_processed$is_bad, NA_real_, res_processed[["lower .95"]])
    res_processed$Upper <- ifelse(res_processed$is_bad, NA_real_, res_processed[["upper .95"]])
    res_processed$Treatment <- gsub(treat_var, "", rownames(res_raw), fixed = TRUE)
    res_processed$Variable <- idx
    res_processed$Subgroup <- sub_label
    res_processed$Level_Order <- i

    res_processed[, c("Variable", "Subgroup", "Treatment", "HR", "Lower", "Upper", "Level_Order")]
  })
}

block_subgroup_treatment_forest <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(ggplot2)
    library(dplyr)
    library(purrr)
    library(survival)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$subgroup_treatment_forest %||% list()

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp) || !is.data.frame(data_imp)) {
    if (.stf07_should_pause(bl_cfg, "pause_on_missing_data", TRUE)) {
      .stf07_pause(
        ctx,
        reason = "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）",
        suggestion = "请先 load 数据至 ctx$data$cleaned 或运行上游 data_clean / imputation"
      )
    }
    stop("No data found in ctx$data$imputed or ctx$data$cleaned.", call. = FALSE)
  }
  rt <- as.data.frame(data_imp, stringsAsFactors = FALSE)

  surv <- cfg$survival
  if (is.null(surv) ||
      is.null(surv$time_var) ||
      is.null(surv$event_var) ||
      is.null(surv$event_value)) {
    stop(
      "config$survival 必须同时定义 time_var、event_var、event_value（块内不使用默认值）。",
      call. = FALSE
    )
  }
  time_col <- surv$time_var
  status_col <- surv$event_var
  event_value <- surv$event_value

  treat_var <- bl_cfg$treatment_var
  subgroup_vars <- bl_cfg$subgroup_vars
  if (is.null(treat_var) || !nzchar(as.character(treat_var)[1L])) {
    stop("config$subgroup_treatment_forest$treatment_var 必填。", call. = FALSE)
  }
  if (is.null(subgroup_vars) || !length(subgroup_vars)) {
    stop("config$subgroup_treatment_forest$subgroup_vars 必填（非空字符向量）。", call. = FALSE)
  }
  subgroup_vars <- as.character(subgroup_vars)

  miss_cols <- setdiff(c(treat_var, subgroup_vars, time_col, status_col), names(rt))
  if (length(miss_cols)) {
    stop(
      "下列列不在分析数据中: ",
      paste(miss_cols, collapse = ", "),
      call. = FALSE
    )
  }

  hr_coef_min <- bl_cfg$hr_coef_min %||% 0.001
  hr_coef_max <- bl_cfg$hr_coef_max %||% 100
  hr_upper_max <- bl_cfg$hr_upper_max %||% 1000

  rt[[time_col]] <- suppressWarnings(as.numeric(rt[[time_col]]))
  rt[[status_col]] <- .stf07_event_indicator(rt[[status_col]], event_value)

  if (!is.factor(rt[[treat_var]])) {
    rt[[treat_var]] <- factor(rt[[treat_var]])
  }
  rt[[treat_var]] <- droplevels(rt[[treat_var]])
  treat_levels <- levels(rt[[treat_var]])
  if (length(treat_levels) < 2L) {
    if (.stf07_should_pause(bl_cfg, "pause_on_insufficient_treatment_levels", TRUE)) {
      .stf07_pause(
        ctx,
        reason = paste0("治疗变量 ", treat_var, " 有效水平 < 2，无法估计 HR。"),
        suggestion = "检查 treatment_var 水平或扩大样本量",
        data_snapshot = rt[, c(treat_var, time_col, status_col), drop = FALSE]
      )
    }
    stop("Treatment variable has fewer than 2 levels.", call. = FALSE)
  }

  ref_level <- bl_cfg$reference_level
  if (!is.null(ref_level) && nzchar(as.character(ref_level)[1L])) {
    ref_level <- as.character(ref_level)[1L]
    if (!(ref_level %in% treat_levels)) {
      stop(
        "config$subgroup_treatment_forest$reference_level 不在 ",
        treat_var, " 的水平中: ", ref_level,
        call. = FALSE
      )
    }
    rt[[treat_var]] <- stats::relevel(rt[[treat_var]], ref = ref_level)
    treat_levels <- levels(rt[[treat_var]])
  }
  ref_group_name <- treat_levels[[1L]]

  cli::cli_alert_info("Treatment: {.field {treat_var}} (ref: {ref_group_name})")
  cli::cli_alert_info("Subgroup vars ({length(subgroup_vars)}): {paste(subgroup_vars, collapse = ', ')}")
  cli::cli_alert_info("Survival: Surv({time_col}, {status_col}==1), event_value={event_value}")

  plot_data <- purrr::map_dfr(subgroup_vars, function(idx) {
    .stf07_compute_subgroup_hr(
      rt = rt,
      idx = idx,
      treat_var = treat_var,
      treat_levels = treat_levels,
      time_col = time_col,
      status_col = status_col,
      hr_coef_min = hr_coef_min,
      hr_coef_max = hr_coef_max,
      hr_upper_max = hr_upper_max
    )
  })

  n_valid_hr <- sum(is.finite(plot_data$HR))
  if (n_valid_hr < 1L && .stf07_should_pause(bl_cfg, "pause_on_no_valid_hr", TRUE)) {
    .stf07_pause(
      ctx,
      reason = "所有亚组水平均未得到有效 HR 估计（事件不足、治疗水平不足或 Cox 拟合失败）。",
      suggestion = "检查 subgroup_vars、事件数与治疗分组；或设置 pause_on_no_valid_hr = FALSE 仅导出 NA 占位结果",
      data_snapshot = plot_data
    )
  }

  plot_data <- plot_data %>%
    dplyr::mutate(Var_Order = match(Variable, subgroup_vars)) %>%
    dplyr::arrange(Var_Order, Level_Order)

  final_subgroup_levels <- unique(plot_data$Subgroup)
  plot_data$Subgroup <- factor(plot_data$Subgroup, levels = rev(final_subgroup_levels))
  plot_data$Variable <- factor(plot_data$Variable, levels = subgroup_vars)

  plot_colors <- bl_cfg$plot_colors %||% block_default_palette(5L, cfg)
  x_log_breaks <- bl_cfg$x_log_breaks %||% c(0.1, 0.5, 1, 2, 5, 10)
  fig_w <- bl_cfg$figure_width %||% 12
  fig_h <- bl_cfg$figure_height %||% 10
  ff <- plot_font_from_config(cfg)

  disease_lab <- cfg$project$disease %||% "Outcome"
  fig_cap <- bl_cfg$figure_caption %||% paste0("Forest Plot Subgroup Analysis of ", disease_lab)
  fig_fn <- pub_figure_file(ctx, "main_figure", fig_cap)

  ctx <- save_figure(
    ctx,
    fig_fn,
    function() {
      ggplot2::ggplot(plot_data, ggplot2::aes(x = HR, y = Subgroup, color = Treatment)) +
        ggplot2::facet_grid(Variable ~ ., scales = "free_y", space = "free_y") +
        ggplot2::geom_errorbarh(
          ggplot2::aes(xmin = Lower, xmax = Upper),
          height = 0.4,
          position = ggplot2::position_dodge(width = 0.8),
          na.rm = TRUE
        ) +
        ggplot2::geom_point(
          position = ggplot2::position_dodge(width = 0.8),
          size = 2.5,
          na.rm = TRUE
        ) +
        ggplot2::geom_vline(
          xintercept = 1,
          linetype = "dashed",
          color = "darkred",
          alpha = 0.6
        ) +
        ggplot2::scale_x_log10(breaks = x_log_breaks) +
        ggplot2::scale_color_manual(values = plot_colors) +
        ggplot2::labs(
          x = "Hazard Ratio (95% CI, Log Scale)",
          y = "",
          title = paste0("Forest Plot: Subgroup Analysis of ", disease_lab),
          subtitle = paste0(
            "All comparisons are relative to Reference Group: ",
            ref_group_name
          )
        ) +
        ggplot2::theme_bw(base_family = ff) +
        ggplot2::theme(
          text = ggplot2::element_text(family = ff),
          strip.text.y = ggplot2::element_text(angle = 0, face = "bold", hjust = 0),
          panel.grid.minor = ggplot2::element_blank(),
          legend.position = "top",
          strip.background = ggplot2::element_rect(fill = "gray95")
        )
    },
    width = fig_w,
    height = fig_h
  )

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  tbl_fn <- bl_cfg$table_filename %||% "Table_Subgroup_Treatment_CoxHR.xlsx"
  tbl_fp <- file.path(tbl_dir, tbl_fn)
  tbl_title <- bl_cfg$table_title %||% "Subgroup Cox HR by treatment arm (95% CI)"

  tbl_export <- plot_data
  tbl_export$Variable <- as.character(tbl_export$Variable)
  tbl_export$Subgroup <- as.character(tbl_export$Subgroup)
  tbl_export$Treatment <- as.character(tbl_export$Treatment)
  tbl_export$HR <- ifelse(
    is.na(tbl_export$HR),
    "",
    fmt_num(as.numeric(tbl_export$HR))
  )
  tbl_export$Lower <- ifelse(
    is.na(plot_data$Lower),
    "",
    fmt_num(as.numeric(plot_data$Lower))
  )
  tbl_export$Upper <- ifelse(
    is.na(plot_data$Upper),
    "",
    fmt_num(as.numeric(plot_data$Upper))
  )
  tbl_export[["HR (95% CI)"]] <- ifelse(
    is.na(plot_data$HR),
    "",
    sprintf(
      "%s (%s\u2013%s)",
      fmt_num(as.numeric(plot_data$HR)),
      fmt_num(as.numeric(plot_data$Lower)),
      fmt_num(as.numeric(plot_data$Upper))
    )
  )

  tryCatch(
    export_sci_table(tbl_export, tbl_fp, title = tbl_title),
    error = function(e) cli::cli_alert_warning("亚组 HR 表导出失败: {e$message}")
  )
  cli::cli_alert_success("Subgroup HR table saved: {.file {basename(tbl_fp)}}")

  ctx <- save_result(
    ctx,
    "subgroup_treatment_forest",
    plot_data,
    "Data/subgroup_treatment_plot_data.RData"
  )

  ctx$results$subgroup_treatment_forest <- plot_data
  ctx$results$subgroup_treatment_ref <- ref_group_name
  ctx$results$subgroup_treatment_vars <- subgroup_vars
  ctx$results$subgroup_treatment_n_valid_hr <- n_valid_hr

  cli::cli_alert_success(
    "Subgroup treatment forest done ({n_valid_hr} valid HR rows, ref={ref_group_name})"
  )

  ctx
}

register_block(
  "subgroup_treatment_forest",
  block_subgroup_treatment_forest,
  "多臂治疗亚组 Cox 森林图（ggplot）"
)
