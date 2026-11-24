###############################################################################
#  trajectory_plot_gbmt_priori — GBMT 画风轨迹图，按先验分层（个体灰线 + LOESS）。
#  源自课题脚本 C02_Disease_Trajectories.R；不拟合 GBMT，仅复用其可视化套路。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # pipeline 决定，块内不选源
#  require_package = dplyr, tidyr, ggplot2, RColorBrewer
#
#  trajectory_plot_gbmt_priori = list(
#    strata_var    = "Group3",              # 先验分组列（非潜类 Class）
#    id_column     = "Admission_Num",
#    anthro_vars   = c("Weight", "BMI"),
#    anthro_times  = c("Pre", "Early", "Mid", "Late"),
#    blood_vars    = c("Total_Cholesterol", "Triglycerides",
#                      "HDL_Cholesterol", "LDL_Cholesterol", "FFA_Cholesterol"),
#    blood_times   = c("Early", "Mid", "Late"),
#    # 可选追加其它血检：Uric_Acid, Creatinine, Urea, Urine_Protein
#    y_q           = c(0.01, 0.99),
#    plot_width    = 8,
#    plot_height   = 4,
#    zero_as_na_for = c("BMI", "Weight"),   # 列名以 _BMI/_Weight 结尾且值为 0 → NA
#    force_numeric = c("Late_HDL_Cholesterol"),
#    pause_enable  = TRUE,
#    pause_on_no_figures = TRUE
#  ),
#
#  register_block: "trajectory_plot_gbmt_priori"
#  典型位置: 编码先验分组后；与 trajectory_plot_gbmt（潜类）二选一或并列
#  读: ctx$data$imputed|cleaned；写: Figures/Figure_Trajectory_*_by_*_priori_loess.pdf
#      ctx$results$trajectory_plot_gbmt_priori
###############################################################################

.tpgp30_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tpgp30_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_plot_gbmt_priori", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tpgp30_zero_to_na <- function(data, suffixes) {
  for (suf in suffixes) {
    cols <- grep(paste0("_", suf, "$"), names(data), value = TRUE)
    if (identical(suf, "Weight")) {
      cols <- setdiff(cols, "Newborn_Weight")
    }
    for (cl in cols) {
      z <- which(data[[cl]] == 0)
      if (length(z)) data[[cl]][z] <- NA_real_
    }
  }
  data
}

.tpgp30_to_long <- function(df, var, time_levels, id_col, strata_var) {
  cols_all <- paste0(time_levels, "_", var)
  cols <- intersect(cols_all, names(df))
  miss <- setdiff(cols_all, cols)
  if (!length(cols)) {
    stop("trajectory_plot_gbmt_priori: 指标 ", var, " 缺少全部波次列：",
         paste(cols_all, collapse = ", "), call. = FALSE)
  }
  if (length(miss)) {
    cli::cli_alert_warning(
      "trajectory_plot_gbmt_priori: {var} 缺波次 {paste(miss, collapse = ', ')}，仅用 {paste(cols, collapse = ', ')}"
    )
  }
  keep <- c(id_col, strata_var, cols)
  out <- df[, keep, drop = FALSE]
  names(out)[1:2] <- c("ID", "Strata")
  out <- tidyr::pivot_longer(
    out, cols = dplyr::all_of(cols),
    names_to = "Time_Label", values_to = "Value"
  )
  out$Value <- as.numeric(out$Value)
  used_times <- sub(paste0("_", var, "$"), "", cols)
  out$Time_Label <- factor(
    sub(paste0("_", var, "$"), "", out$Time_Label),
    levels = used_times
  )
  out$Time <- as.integer(out$Time_Label)
  out$Value[is.infinite(out$Value)] <- NA_real_
  out
}

.tpgp30_palette <- function(k) {
  RColorBrewer::brewer.pal(max(k, 3L), "Set2")[seq_len(k)]
}

.tpgp30_make_plot <- function(data, col, var_name, x_labels, y_q, font_family,
                              show_individual = TRUE) {
  cycle <- length(x_labels)
  class_info <- data |>
    dplyr::distinct(ID, Strata) |>
    dplyr::count(Strata, name = "N") |>
    dplyr::mutate(
      percent = round(N / sum(N) * 100, 2),
      label = paste0(as.character(Strata), ": N = ", N, " (", percent, "%)")
    ) |>
    dplyr::arrange(Strata) |>
    dplyr::mutate(label = factor(label, levels = label))

  data2 <- data |>
    dplyr::left_join(class_info |> dplyr::select(Strata, label), by = "Strata")

  y_lim <- stats::quantile(data2$Value, probs = y_q, na.rm = TRUE)

  p <- ggplot2::ggplot(data2, ggplot2::aes(x = Time, y = Value))
  if (isTRUE(show_individual)) {
    p <- p +
      ggplot2::geom_line(
        ggplot2::aes(group = ID), alpha = 0.15, color = "grey70"
      )
  }
  p +
    ggplot2::geom_smooth(
      ggplot2::aes(group = label, color = label),
      method = "loess", formula = y ~ x, se = TRUE, linewidth = 1
    ) +
    ggplot2::scale_color_manual(values = col, drop = FALSE) +
    ggplot2::scale_x_continuous(
      expand = c(0, 0), limits = c(1, cycle),
      breaks = seq_len(cycle), labels = x_labels
    ) +
    ggplot2::labs(x = "Wave", y = var_name, color = "Strata") +
    ggplot2::coord_cartesian(ylim = c(as.numeric(y_lim[1]), as.numeric(y_lim[2]))) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      text = ggplot2::element_text(family = font_family),
      legend.position = "right"
    )
}

block_trajectory_plot_gbmt_priori <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr); library(tidyr); library(ggplot2); library(RColorBrewer); library(cli)
  })

  cfg <- ctx$config
  bl <- cfg$trajectory_plot_gbmt_priori %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("trajectory_plot_gbmt_priori: 无数据（需上游写入 imputed/cleaned）", call. = FALSE)
  }

  strata_var <- bl$strata_var %||% "Group3"
  id_col <- bl$id_column %||% cfg$data$id_column %||% "Admission_Num"
  if (!strata_var %in% names(data)) {
    stop("trajectory_plot_gbmt_priori: 缺少先验分层列 ", strata_var, call. = FALSE)
  }
  if (!id_col %in% names(data)) {
    stop("trajectory_plot_gbmt_priori: 缺少 id 列 ", id_col, call. = FALSE)
  }

  anthro_vars <- bl$anthro_vars %||% c("Weight", "BMI")
  anthro_times <- bl$anthro_times %||% c("Pre", "Early", "Mid", "Late")
  blood_vars <- bl$blood_vars %||% c(
    "Total_Cholesterol", "Triglycerides", "HDL_Cholesterol",
    "LDL_Cholesterol", "FFA_Cholesterol"
  )
  blood_times <- bl$blood_times %||% c("Early", "Mid", "Late")
  y_q <- bl$y_q %||% c(0.01, 0.99)
  plot_width <- bl$plot_width %||% 8
  plot_height <- bl$plot_height %||% 4
  zero_suf <- bl$zero_as_na_for %||% c("BMI", "Weight")
  force_num <- bl$force_numeric %||% c("Late_HDL_Cholesterol")
  show_indiv <- isTRUE(bl$show_individual_trajectories %||% TRUE)
  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else {
    "serif"
  }

  for (cn in intersect(force_num, names(data))) {
    data[[cn]] <- as.numeric(data[[cn]])
  }
  data <- .tpgp30_zero_to_na(data, zero_suf)
  if (!is.factor(data[[strata_var]])) {
    data[[strata_var]] <- factor(data[[strata_var]])
  }

  jobs <- list()
  for (v in anthro_vars) jobs[[length(jobs) + 1L]] <- list(var = v, times = anthro_times)
  for (v in blood_vars) jobs[[length(jobs) + 1L]] <- list(var = v, times = blood_times)

  n_queued <- 0L
  n_skip <- 0L
  out_files <- character(0)
  n_strata <- nlevels(droplevels(data[[strata_var]]))
  cols <- .tpgp30_palette(n_strata)

  for (i in seq_along(jobs)) {
    var <- jobs[[i]]$var
    times <- jobs[[i]]$times
    cli::cli_h2("[{i}/{length(jobs)}] trajectory_plot_gbmt_priori: {var}")
    long <- tryCatch(
      .tpgp30_to_long(data, var, times, id_col, strata_var),
      error = function(e) {
        cli::cli_alert_warning("{var}: {e$message}")
        NULL
      }
    )
    if (is.null(long) || !nrow(long)) {
      n_skip <- n_skip + 1L
      next
    }
    var_disp <- if (exists("pipeline_blocks_display_label", mode = "function")) {
      pipeline_blocks_display_label(var)
    } else {
      gsub("_", " ", var, fixed = TRUE)
    }
    x_labs <- levels(long$Time_Label)
    if (!length(x_labs)) x_labs <- times
    p <- .tpgp30_make_plot(
      long, cols, var_disp, x_labs, y_q, font_family,
      show_individual = show_indiv
    )
    fn <- paste0(
      "Figure_Trajectory_", gsub(" ", "_", var_disp, fixed = TRUE),
      "_by_", strata_var, "_priori_loess.pdf"
    )
    ctx <- save_figure(
      ctx, filename = fn,
      plot_fn = local({ pp <- p; function() pp }),
      width = plot_width, height = plot_height
    )
    n_queued <- n_queued + 1L
    out_files <- c(out_files, fn)
    cli::cli_alert_success("{var}: 先验 LOESS 轨迹图入队")
  }

  if (n_queued == 0L && .tpgp30_should_pause(bl, "pause_on_no_figures", TRUE)) {
    .tpgp30_pause(
      ctx,
      "trajectory_plot_gbmt_priori 无有效图形入队。",
      paste0(
        "请检查：① 是否已生成 ", strata_var, "；",
        "② anthro_vars/blood_vars 与宽表列名（如 Early_BMI）；",
        "③ 上游 imputed/cleaned 是否可读。"
      ),
      NULL
    )
  }

  ctx$results$trajectory_plot_gbmt_priori <- list(
    strata_var = strata_var,
    n_queued = n_queued,
    n_skip = n_skip,
    files = out_files
  )
  cli::cli_alert_success(
    "trajectory_plot_gbmt_priori 完成: {n_queued} 张入队，{n_skip} 跳过。"
  )
  ctx
}

register_block(
  "trajectory_plot_gbmt_priori",
  block_trajectory_plot_gbmt_priori,
  "GBMT画风+先验分层：个体线+LOESS"
)
