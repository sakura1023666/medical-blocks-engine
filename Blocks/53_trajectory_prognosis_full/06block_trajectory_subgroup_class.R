###############################################################################
#  trajectory_subgroup_class — 潜类别（trajectory_class）亚组 Cox HR 森林图
#
#  参数化版 FigS3.R：以 class_factor（潜类别，非连续 index）为暴露做 Cox，在
#  可配置的亚组变量列表内逐一拟合 HR（相对 ref_class），输出"计数表+对数HR森林图"
#  拼图（有 patchwork 则拼图，否则仅出森林图）+ csv。与既有 18_subgroup/
#  01block_subgroup_prognosis.R（index 高低分组）功能互补，不修改后者。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#                 需含 trajectory_class（或 trajectory_class_{Index}）
#
#  trajectory_subgroup_class = list(
#    index_vars                    = NULL,   # NULL → 用裸列 trajectory_class
#    class_col                     = NULL,   # 显式指定类别列名，优先级最高
#    ref_class                     = NULL,   # NULL → 自动取样本量最大的类别
#    survival_time_var             = NULL,   # NULL → config$survival$time_var
#    survival_event_var            = NULL,   # NULL → config$survival$event_var
#    max_followup                  = 28,
#    subgroup_vars                 = character(0),  # 现成分类列（如 Gender/Stroke/COPD）
#    continuous_median_split_vars  = character(0),  # 数值列，按中位数二分
#    continuous_cutoffs            = list(),        # 可选：{var}=cutoff 覆盖中位数
#    age_var                       = NULL,           # 若提供，额外按 age_cutoff 分组
#    age_cutoff                    = 65,
#    auto_scan_categorical         = TRUE,   # 未显式配置 subgroup_vars 时，自动扫描分类列
#    min_n_per_subgroup            = 5L,
#    pause_enable                  = TRUE,
#    pause_on_no_output            = TRUE
#  ),
#
#  register_block: "trajectory_subgroup_class"
#  写: ctx$results$trajectory_subgroup_class[[Index]]
#  落盘: Figures/Figure_Subgroup_TrajectoryClass_{Index}.pdf
#        Tables/Table_Subgroup_TrajectoryClass_{Index}_HR.csv
###############################################################################

.tsc06_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tsc06_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_subgroup_class", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tsc06_get_hr_in_subset <- function(data_sub, ref_class, subgroup_var, subgroup_level) {
  if (nlevels(droplevels(data_sub$class_factor)) < 2) return(NULL)
  if (sum(data_sub$event) == 0) return(NULL)
  tab <- table(data_sub$class_factor, data_sub$event)
  if (any(rowSums(tab) == 0) || any(colSums(tab) == 0)) return(NULL)

  data_sub$class_factor <- stats::relevel(droplevels(data_sub$class_factor), ref = ref_class)
  fit <- tryCatch(
    survival::coxph(survival::Surv(survival_time, event) ~ class_factor, data = data_sub),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)

  ci <- as.data.frame(summary(fit)$conf.int)
  ci$term <- rownames(ci)
  ci$class_num <- suppressWarnings(as.integer(gsub("\\D+", "", ci$term)))
  ci <- ci[!is.na(ci$class_num), , drop = FALSE]
  if (!nrow(ci)) return(NULL)

  data.frame(
    subgroup_var = subgroup_var, subgroup_level = subgroup_level,
    n = nrow(data_sub), events = sum(data_sub$event),
    comparison = paste0("Class ", ci$class_num, " vs Class ", ref_class),
    estimate = ci[["exp(coef)"]], conf.low = ci[["lower .95"]], conf.high = ci[["upper .95"]],
    p.value = summary(fit)$coefficients[, "Pr(>|z|)"],
    stringsAsFactors = FALSE
  )
}

.tsc06_build_subgroup_cols <- function(data, bl, id_col) {
  cols <- list()

  age_var <- bl$age_var %||% NULL
  if (!is.null(age_var) && age_var %in% names(data)) {
    age_cutoff <- as.numeric(bl$age_cutoff %||% 65)
    lv <- c(paste0("<", age_cutoff), paste0(">=", age_cutoff))
    cols[["Age"]] <- factor(
      ifelse(suppressWarnings(as.numeric(data[[age_var]])) < age_cutoff, lv[1], lv[2]),
      levels = lv
    )
  }

  cont_vars <- as.character(bl$continuous_median_split_vars %||% character(0))
  cutoffs   <- bl$continuous_cutoffs %||% list()
  for (v in intersect(cont_vars, names(data))) {
    x <- suppressWarnings(as.numeric(data[[v]]))
    cutoff <- as.numeric(cutoffs[[v]] %||% stats::median(x, na.rm = TRUE))
    lv <- c(paste0(v, " <=Median"), paste0(v, " >Median"))
    cols[[v]] <- factor(ifelse(x <= cutoff, lv[1], lv[2]), levels = lv)
  }

  explicit_vars <- as.character(bl$subgroup_vars %||% character(0))
  for (v in intersect(explicit_vars, names(data))) {
    cols[[v]] <- factor(data[[v]])
  }

  auto_scan <- if (is.null(bl$auto_scan_categorical)) TRUE else isTRUE(bl$auto_scan_categorical)
  if (!length(explicit_vars) && auto_scan) {
    reserved <- c(
      id_col, "trajectory_class", "class_factor", "survival_time", "event",
      # 结局/时间列不作亚组分层
      "survival_28d", "Mortality_28d", "survival_time_28d", "hosp_day", "icu_day"
    )
    cand <- setdiff(names(data), reserved)
    cand <- cand[!grepl("^trajectory_class", cand, ignore.case = TRUE)]
    cand <- cand[!grepl("survival|mortality|death|dead_time", cand, ignore.case = TRUE)]
    for (v in cand) {
      x <- data[[v]]
      if ((is.factor(x) || is.character(x) || is.logical(x)) && !v %in% names(cols)) {
        f <- factor(x)
        if (nlevels(f) >= 2 && nlevels(f) <= 6) cols[[v]] <- f
      }
    }
  }
  cols
}

.tsc06_run_one <- function(ctx, data, bl, Index, class_col, time_var, event_var, max_followup) {
  if (!class_col %in% names(data)) {
    cli::cli_alert_warning("trajectory_subgroup_class: 缺少类别列 {class_col}，跳过 {Index %||% ''}")
    return(NULL)
  }
  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("trajectory_subgroup_class: 缺少生存列 (", time_var, "/", event_var, ")", call. = FALSE)
  }

  id_col <- ctx$config$data$id_column %||% "subject_id"
  if (!exists("trajectory_class_swap_map", mode = "function")) {
    traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
    if (file.exists(traj_util)) source(traj_util, local = FALSE)
  }
  # 与 FigS3.R 一致：ng==2 时交换 Class1/2 标签（Class2=多数/低风险类，作参照）
  class_num0 <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(data[[class_col]]))))
  class_num  <- if (exists("trajectory_apply_class_swap", mode = "function"))
    trajectory_apply_class_swap(class_num0, trajectory_class_swap_map(class_num0)) else class_num0
  base <- data
  base$class_factor <- factor(class_num, levels = sort(unique(stats::na.omit(class_num))),
                               labels = as.character(sort(unique(stats::na.omit(class_num)))))
  base$survival_time <- pmin(suppressWarnings(as.numeric(as.character(data[[time_var]]))), max_followup)
  if (!exists("trajectory_coerce_event01", mode = "function")) {
    traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
    if (file.exists(traj_util)) source(traj_util, local = FALSE)
  }
  base$event <- trajectory_coerce_event01(data[[event_var]])
  base <- base[!is.na(base$class_factor) & !is.na(base$survival_time) & !is.na(base$event) &
                 base$survival_time > 0, , drop = FALSE]

  if (!nrow(base) || nlevels(droplevels(base$class_factor)) < 2) {
    cli::cli_alert_warning("trajectory_subgroup_class: {Index %||% ''} 有效数据不足或类别数<2，跳过")
    return(NULL)
  }

  # FigS3.R 以 Class 2（交换后=多数/低风险类）为参照；默认取样本量最大类别（交换后即 Class 2）
  ref_class <- if (!is.null(bl$ref_class))
    gsub("\\D+", "", as.character(bl$ref_class)) else
    names(sort(table(base$class_factor), decreasing = TRUE))[1]
  if (!ref_class %in% levels(base$class_factor)) ref_class <- levels(base$class_factor)[1]

  subgroup_cols <- .tsc06_build_subgroup_cols(base, bl, id_col)
  min_n   <- as.integer(bl$min_n_per_subgroup %||% 5L)
  N_total <- nrow(base)

  overall_res <- .tsc06_get_hr_in_subset(base, ref_class, "Overall", "Overall")
  rows <- list()
  if (!is.null(overall_res)) rows[[length(rows) + 1L]] <- overall_res

  # 计数表：Overall + 每个亚组变量（表头行 + 缩进水平行），对齐 FigS3.R mk_count_table
  count_rows <- list(data.frame(
    Variables = "Overall", subgroup_var = "Overall", subgroup_level = "Overall",
    Count = N_total, Percent = 100, is_header = FALSE, stringsAsFactors = FALSE
  ))
  for (vname in names(subgroup_cols)) {
    fcol <- subgroup_cols[[vname]]
    base[[paste0(".sg_", vname)]] <- fcol
    count_rows[[length(count_rows) + 1L]] <- data.frame(
      Variables = vname, subgroup_var = vname, subgroup_level = NA_character_,
      Count = NA_integer_, Percent = NA_real_, is_header = TRUE, stringsAsFactors = FALSE
    )
    for (lv in levels(fcol)) {
      sub <- base[!is.na(fcol) & fcol == lv, , drop = FALSE]
      count_rows[[length(count_rows) + 1L]] <- data.frame(
        Variables = paste0("  ", lv), subgroup_var = vname, subgroup_level = lv,
        Count = nrow(sub), Percent = round(100 * nrow(sub) / N_total, 1),
        is_header = FALSE, stringsAsFactors = FALSE
      )
      if (nrow(sub) < min_n) next
      res <- tryCatch(.tsc06_get_hr_in_subset(sub, ref_class, vname, lv), error = function(e) NULL)
      if (!is.null(res)) rows[[length(rows) + 1L]] <- res
    }
  }

  if (!length(rows)) {
    cli::cli_alert_warning("trajectory_subgroup_class: {Index %||% ''} 所有亚组均无法拟合 Cox")
    return(NULL)
  }
  forest_df <- do.call(rbind, rows)
  count_tbl <- do.call(rbind, count_rows)
  count_tbl$row_order <- seq_len(nrow(count_tbl))

  # 左表用唯一行；森林图按 comparison 展开（ng≥3 时多面板）
  plot_dat_tbl <- count_tbl
  plot_dat_tbl$Count_str   <- ifelse(is.na(plot_dat_tbl$Count), "", as.character(plot_dat_tbl$Count))
  plot_dat_tbl$Percent_str <- ifelse(is.na(plot_dat_tbl$Percent), "", sprintf("%.1f", plot_dat_tbl$Percent))
  y_levels <- rev(as.character(plot_dat_tbl$row_order))
  plot_dat_tbl$row_lab_f <- factor(as.character(plot_dat_tbl$row_order), levels = y_levels)
  plot_dat_tbl$bg_id   <- as.numeric(plot_dat_tbl$row_lab_f)
  plot_dat_tbl$bg_fill <- ifelse(plot_dat_tbl$bg_id %% 2 == 0, "grey95", "white")

  plot_dat <- merge(count_tbl, forest_df, by = c("subgroup_var", "subgroup_level"), all.x = TRUE)
  plot_dat <- plot_dat[order(plot_dat$row_order), , drop = FALSE]
  plot_dat$row_lab_f <- factor(as.character(plot_dat$row_order), levels = y_levels)
  plot_dat$bg_id   <- as.numeric(plot_dat$row_lab_f)
  plot_dat$bg_fill <- ifelse(plot_dat$bg_id %% 2 == 0, "grey95", "white")

  brk    <- c(0.1, 0.25, 0.5, 1, 2, 4, 8)
  brk_lb <- c("0.1", "0.25", "0.5", "1", "2", "4", "8")
  fp <- plot_dat[!is.na(plot_dat$estimate) & is.finite(plot_dat$estimate) &
                   plot_dat$estimate > 0 &
                   is.finite(plot_dat$conf.low) & plot_dat$conf.low > 0 &
                   is.finite(plot_dat$conf.high) & plot_dat$conf.high > 0, , drop = FALSE]
  n_comp <- if (nrow(fp)) length(unique(as.character(fp$comparison))) else 1L
  comp_levels <- if (nrow(fp)) unique(as.character(fp$comparison)) else character(0)
  # 稳定排序：Class 数字升序
  if (length(comp_levels) > 1L) {
    ord <- order(suppressWarnings(as.integer(gsub("\\D+", "", sub(" vs.*", "", comp_levels)))))
    comp_levels <- comp_levels[ord]
    fp$comparison <- factor(as.character(fp$comparison), levels = comp_levels)
  }
  palette <- c("#D55E00", "#0072B2", "#009E73", "#CC79A7", "#E69F00")
  comp_cols <- setNames(palette[seq_along(comp_levels)], comp_levels)

  make_forest <- function(fp_use, bg_dat, facet = FALSE) {
    x_min <- min(c(fp_use$conf.low, 0.5), na.rm = TRUE) * 0.8
    x_max <- max(c(fp_use$conf.high, 2), na.rm = TRUE) * 1.2
    if (!is.finite(x_min)) x_min <- 0.1
    if (!is.finite(x_max)) x_max <- 8
    p <- ggplot2::ggplot(fp_use, ggplot2::aes(x = estimate, y = row_lab_f)) +
      ggplot2::geom_rect(
        data = bg_dat, inherit.aes = FALSE, colour = NA,
        ggplot2::aes(ymin = as.numeric(row_lab_f) - 0.5, ymax = as.numeric(row_lab_f) + 0.5,
                     xmin = x_min, xmax = x_max, fill = bg_fill)
      ) +
      ggplot2::scale_fill_identity() +
      ggplot2::geom_vline(xintercept = 1, linetype = "dashed", colour = "grey70", linewidth = 0.4)
    # 与三类版式一致：始终按 comparison 分面并显示标题条（ng=2 时为单面板 “Class 1 vs Class 2”）
    use_facet <- isTRUE(facet) || (length(unique(as.character(fp_use$comparison))) >= 1L)
    if (use_facet) {
      if (!is.factor(fp_use$comparison)) {
        fp_use$comparison <- factor(as.character(fp_use$comparison), levels = comp_levels)
      }
      p <- p +
        ggplot2::geom_errorbarh(
          ggplot2::aes(xmin = conf.low, xmax = conf.high, colour = comparison),
          height = 0.25, linewidth = 0.7
        ) +
        ggplot2::geom_point(ggplot2::aes(colour = comparison), size = 2.3) +
        ggplot2::scale_colour_manual(values = comp_cols, drop = FALSE, name = NULL) +
        ggplot2::facet_grid(. ~ comparison)
    } else {
      p <- p +
        ggplot2::geom_errorbarh(
          ggplot2::aes(xmin = conf.low, xmax = conf.high),
          height = 0.25, linewidth = 0.7, colour = "#D55E00"
        ) +
        ggplot2::geom_point(size = 2.3, colour = "#D55E00")
    }
    p +
      ggplot2::scale_x_log10(limits = c(x_min, x_max), breaks = brk, labels = brk_lb) +
      ggplot2::scale_y_discrete(limits = y_levels, drop = FALSE) +
      ggplot2::labs(x = "Hazard Ratio (log scale)", y = NULL) +
      ggplot2::theme_bw(base_size = 11) +
      ggplot2::theme(
        panel.grid.major = ggplot2::element_blank(), panel.grid.minor = ggplot2::element_blank(),
        strip.background = ggplot2::element_rect(fill = "white", colour = NA),
        strip.text = ggplot2::element_text(face = "bold"),
        axis.text.y = ggplot2::element_blank(), axis.ticks.y = ggplot2::element_blank(),
        legend.position = "none"
      )
  }

  p_combined <- NULL
  if (nrow(fp) && requireNamespace("patchwork", quietly = TRUE)) {
    # 始终分面，保证与三类相同的「左表 + 带标题森林面板」版式
    p_forest <- make_forest(fp, plot_dat_tbl, facet = TRUE)
    p_table <- ggplot2::ggplot(plot_dat_tbl, ggplot2::aes(y = row_lab_f)) +
      ggplot2::geom_rect(
        ggplot2::aes(ymin = as.numeric(row_lab_f) - 0.5, ymax = as.numeric(row_lab_f) + 0.5,
                     xmin = 0.5, xmax = 3.5, fill = bg_fill), colour = NA
      ) +
      ggplot2::scale_fill_identity() +
      ggplot2::geom_text(ggplot2::aes(x = 1, label = Variables), hjust = 0, size = 3.2) +
      ggplot2::geom_text(ggplot2::aes(x = 2, label = Count_str), hjust = 1, size = 3.0) +
      ggplot2::geom_text(ggplot2::aes(x = 3, label = Percent_str), hjust = 1, size = 3.0) +
      ggplot2::annotate("text", x = 1, y = Inf, vjust = -0.5, label = "Variables", fontface = "bold", size = 3.3) +
      ggplot2::annotate("text", x = 2, y = Inf, vjust = -0.5, label = "Count", fontface = "bold", size = 3.3) +
      ggplot2::annotate("text", x = 3, y = Inf, vjust = -0.5, label = "Percent (%)", fontface = "bold", size = 3.3) +
      ggplot2::scale_x_continuous(limits = c(0.5, 3.5)) +
      ggplot2::scale_y_discrete(limits = y_levels, drop = FALSE) +
      ggplot2::coord_cartesian(clip = "off") +
      ggplot2::theme_void(base_size = 11) +
      ggplot2::theme(plot.margin = ggplot2::margin(t = 20, r = 5, b = 5, l = 5))
    forest_w <- if (n_comp > 1L) 0.35 + 0.30 * n_comp else 0.55
    p_combined <- p_table + p_forest + patchwork::plot_layout(widths = c(0.45, forest_w))
  } else if (nrow(fp)) {
    cli::cli_alert_warning("trajectory_subgroup_class: 未安装 patchwork，退化为单张森林图")
    p_combined <- make_forest(fp, plot_dat_tbl, facet = TRUE) +
      ggplot2::theme(axis.text.y = ggplot2::element_text()) +
      ggplot2::scale_y_discrete(
        limits = y_levels, drop = FALSE,
        labels = setNames(plot_dat_tbl$Variables, as.character(plot_dat_tbl$row_order))
      )
  }

  list(forest_table = forest_df, count_table = count_tbl, plot = p_combined, ref_class = ref_class)
}

block_trajectory_subgroup_class <- function(ctx, ...) {
  suppressPackageStartupMessages({ library(dplyr); library(cli); library(ggplot2) })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)
  bl <- ctx$config$trajectory_subgroup_class %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_subgroup_class: 无数据", call. = FALSE)

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

  time_var  <- bl$survival_time_var  %||% ctx$config$survival$time_var  %||% "futime"
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% "Mortality_28d"
  max_followup <- as.numeric(bl$max_followup %||% 28)

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
      .tsc06_run_one(ctx, data, bl, t$Index, t$col, time_var, event_var, max_followup),
      error = function(e) { cli::cli_alert_danger("trajectory_subgroup_class {key}: {e$message}"); NULL }
    )
    if (is.null(res)) next
    results_all[[key]] <- res
    suffix <- if (is.null(t$Index)) "" else paste0("_", t$Index)
    utils::write.csv(res$forest_table, file.path(out_tab, paste0("Table_Subgroup_TrajectoryClass", suffix, "_HR.csv")), row.names = FALSE)
    utils::write.csv(res$count_table, file.path(out_tab, paste0("Table_Subgroup_TrajectoryClass", suffix, "_Counts.csv")), row.names = FALSE)
    if (!is.null(res$plot)) {
      fn <- paste0("Figure_Subgroup_TrajectoryClass", suffix, ".pdf")
      n_rows <- nrow(res$count_table)
      ctx <- save_figure(ctx, fn, (function(pp) function() print(pp))(res$plot),
                          width = 14, height = max(6, n_rows * 0.35))
    }
  }

  if (!length(results_all)) {
    if (.tsc06_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tsc06_pause(
        ctx, "trajectory_subgroup_class: 未产出任何亚组结果。",
        "请确认 trajectory_jlcm 已配置 assign_class_ng 回写 trajectory_class，且亚组样本量足够。", NULL
      )
    }
    cli::cli_alert_warning("trajectory_subgroup_class: 无有效输出")
    return(ctx)
  }

  ctx$results$trajectory_subgroup_class <- results_all
  cli::cli_alert_success("trajectory_subgroup_class 完成：{length(results_all)} 组结果")
  ctx
}

register_block(
  "trajectory_subgroup_class", block_trajectory_subgroup_class,
  "潜类别亚组 Cox HR 森林图（计数表+对数HR拼图，亚组变量可配置）"
)
