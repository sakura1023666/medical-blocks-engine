###############################################################################
#  trajectory_plot_jlcm — JLCM 轨迹分组可视化（predictY + facet）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_data    = ctx$data$trajectory_long（或 long_data_dir 磁盘兜底）
#  require_ctx_results = ctx$results$trajectory_jlcm_models（或 jlcm_model_dir 兜底）
#  require_upstream    = trajectory_jlcm
#
#  trajectory_plot_jlcm = list(
#    index_vars            = c("BAR"),
#    class_for_plot        = 2:8,
#    cycle                 = 28L,
#    plot_width            = 8,
#    plot_height           = 4,
#    id_column             = NULL,
#    long_data_dir         = NULL,
#    long_data_filename_template = "D01_long_{Index}_D_{D}.RData",
#    long_data_obj         = "long",
#    jlcm_model_dir        = NULL,
#    jlcm_model_filename_tpl = "D01_jlcm_{Index}_models.RData",
#    pause_enable          = TRUE,
#    pause_on_no_figures   = TRUE
#  ),
#
#  register_block: "trajectory_plot_jlcm"
#  输出: Figures/Figure_Trajectory_{Index}_D{D}.pdf
###############################################################################

.tpj04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tpj04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_plot_jlcm", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tpj04_resolve_path <- function(dir_path, fname) {
  if (grepl("^(/|[A-Za-z]:[/\\\\])", dir_path))
    file.path(dir_path, fname)
  else
    file.path(getwd(), dir_path, fname)
}

.tpj04_load_long_data <- function(ctx, key, Index, D, bl_cfg) {
  long_data <- ctx$data$trajectory_long[[key]]
  long_data_dir     <- bl_cfg$long_data_dir %||% NULL
  long_filename_tpl <- bl_cfg$long_data_filename_template %||%
    "D01_long_{Index}_D_{D}.RData"
  long_data_obj_nm  <- bl_cfg$long_data_obj %||% "long"

  if (!is.null(long_data) || is.null(long_data_dir)) return(long_data)

  fname <- gsub("\\{Index\\}", Index, gsub("\\{D\\}", as.character(D), long_filename_tpl))
  fpath <- .tpj04_resolve_path(long_data_dir, fname)
  if (!file.exists(fpath)) return(NULL)

  e <- new.env(parent = emptyenv())
  load(fpath, envir = e)
  long_data <- tryCatch(get(long_data_obj_nm, envir = e), error = function(e2) NULL)
  if (!is.null(long_data))
    cli::cli_alert_info("从磁盘加载长格式: {.file {fpath}}")
  long_data
}

.tpj04_load_jlcm_model <- function(ctx, Index, D, bl_cfg) {
  jlcm_entry <- ctx$results$trajectory_jlcm_models[[Index]]
  model_obj  <- if (!is.null(jlcm_entry))
    jlcm_entry$models[[paste0("m", D)]] else NULL

  if (!is.null(model_obj)) return(model_obj)

  jlcm_model_dir <- bl_cfg$jlcm_model_dir %||% NULL
  jlcm_model_tpl <- bl_cfg$jlcm_model_filename_tpl %||%
    "D01_jlcm_{Index}_models.RData"
  if (is.null(jlcm_model_dir)) return(NULL)

  mfname <- gsub("\\{Index\\}", Index, jlcm_model_tpl)
  mfpath <- .tpj04_resolve_path(jlcm_model_dir, mfname)
  if (!file.exists(mfpath)) return(NULL)

  e_m <- new.env(parent = emptyenv())
  load(mfpath, envir = e_m)
  mlist <- tryCatch(get("models_list_with_cov", envir = e_m), error = function(e2) NULL)
  if (is.null(mlist)) return(NULL)
  cli::cli_alert_info("从磁盘加载 JLCM 模型: {.file {mfpath}}")
  mlist[[paste0("m", D)]]
}

.tpj04_make_plot <- function(model_obj, long_data, Index, D, cycle, id_col, font_family,
                             cov_cols = character(0)) {
  suppressPackageStartupMessages({
    library(ggplot2); library(dplyr); library(lcmm); library(RColorBrewer)
    library(splines)
  })

  if (!exists("trajectory_unwrap_jointlcmm", mode = "function")) {
    traj_util <- file.path(getwd(), "R/trajectory_survival_utils.R")
    if (file.exists(traj_util)) source(traj_util, local = FALSE)
  }

  m <- trajectory_unwrap_jointlcmm(model_obj)
  if (is.null(m$pprob)) return(NULL)

  # 与 Fig2A.R 一致：固定 Okabe-Ito 配色 + ng==2 时 Class1/2 交换（Class2=多数/低风险类）
  class_colors <- c(
    "Class 1" = "#D55E00", "Class 2" = "#E69F00", "Class 3" = "#56B4E9",
    "Class 4" = "#009E73", "Class 5" = "#E87A90", "Class 6" = "#7B68EE"
  )
  swap_map <- trajectory_class_swap_map(as.data.frame(m$pprob)$class)

  actual_classes <- sort(unique(trajectory_apply_class_swap(as.data.frame(m$pprob)$class, swap_map)))
  ng             <- length(actual_classes)
  class_levels   <- paste0("Class ", actual_classes)
  color_vec      <- class_colors[class_levels]
  if (any(is.na(color_vec)))
    color_vec[is.na(color_vec)] <- scales::hue_pal()(ng)[is.na(color_vec)]

  cov_src <- if (!is.null(long_data)) long_data else data.frame()
  cov_mean <- trajectory_jlcm_cov_grid(cov_src, cov_cols, time_var = "time_day",
                                       cycle = cycle, n = 100L)
  newtime  <- cov_mean$time_day

  pred_obj <- tryCatch(
    lcmm::predictY(m, newdata = cov_mean, var.time = "time_day", draws = FALSE),
    error = function(e) {
      cli::cli_alert_warning("{Index}_D{D}: predictY 失败 — {e$message}")
      NULL
    }
  )
  if (is.null(pred_obj)) return(NULL)

  pred_tidy <- as.data.frame(pred_obj$pred) |>
    dplyr::mutate(time = newtime) |>
    tidyr::pivot_longer(cols = dplyr::starts_with("Ypred"),
                        names_to = "class", names_prefix = "Ypred_class",
                        values_to = "Value") |>
    dplyr::filter(!is.na(class)) |>
    dplyr::mutate(
      class_num   = trajectory_apply_class_swap(class, swap_map),
      class_label = factor(paste0("Class ", class_num), levels = class_levels)
    )

  outcome_info <- NULL
  if (!is.null(long_data) && "Class" %in% names(long_data)) {
    surv_cols <- intersect(c("surv_time", "surv_event"), names(long_data))
    outcome_info <- long_data |>
      dplyr::select(dplyr::all_of(c(id_col, "Class")), dplyr::any_of(surv_cols)) |>
      dplyr::distinct() |>
      dplyr::mutate(class_num = trajectory_apply_class_swap(Class, swap_map)) |>
      dplyr::group_by(class_num) |>
      dplyr::summarise(
        n = dplyr::n(),
        death_rate = if ("surv_event" %in% names(long_data))
          mean(surv_event == 1, na.rm = TRUE) * 100 else NA_real_,
        median_surv = if ("surv_time" %in% names(long_data))
          median(surv_time, na.rm = TRUE) else NA_real_,
        .groups = "drop"
      ) |>
      dplyr::mutate(
        label_text = dplyr::case_when(
          !is.na(death_rate) & !is.na(median_surv) ~
            sprintf("N = %d\nDeath: %.1f%%\nMedian Survival: %.1f days", n, death_rate, median_surv),
          TRUE ~ sprintf("N = %d", n)
        ),
        class_label = factor(paste0("Class ", class_num), levels = class_levels)
      )
  }

  bg_data <- NULL
  if (!is.null(long_data) && all(c("Value", "Time", "Class") %in% names(long_data))) {
    bg_data <- long_data |>
      dplyr::rename(time_bg = Time, value_bg = Value) |>
      dplyr::mutate(
        class_num   = trajectory_apply_class_swap(Class, swap_map),
        class_label = factor(paste0("Class ", class_num), levels = class_levels)
      )
  }

  conv_flag <- isTRUE((m$conv %||% NA_integer_) == 1L)
  title_suffix <- if (conv_flag) "" else " (NOT CONVERGED)"

  p <- ggplot2::ggplot()
  if (!is.null(bg_data))
    p <- p + ggplot2::geom_line(
      data = bg_data,
      ggplot2::aes(x = time_bg, y = value_bg, group = .data[[id_col]]),
      color = "grey80", alpha = 0.3, linewidth = 0.5
    )
  p <- p +
    ggplot2::geom_line(
      data = pred_tidy,
      ggplot2::aes(x = time, y = Value, color = class_label),
      linewidth = 1.5
    ) +
    ggplot2::facet_wrap(~ class_label, ncol = ng) +
    ggplot2::scale_color_manual(values = color_vec) +
    ggplot2::labs(
      title = paste0(Index, " Trajectories by Latent Class (ng = ", ng, ")", title_suffix),
      x = "Day in ICU", y = Index
    ) +
    ggplot2::xlim(c(0, cycle)) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(
      legend.position = "none",
      text = ggplot2::element_text(family = font_family),
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold"),
      axis.title = ggplot2::element_text(size = 12),
      strip.text = ggplot2::element_text(size = 11, face = "bold")
    )

  if (!is.null(outcome_info)) {
    p <- p + ggplot2::geom_text(
      data = outcome_info,
      ggplot2::aes(x = Inf, y = Inf, label = label_text),
      hjust = 1.05, vjust = 1.2, size = 3, color = "black",
      lineheight = 0.9, inherit.aes = FALSE
    )
  }
  p
}

block_trajectory_plot_jlcm <- function(ctx, ...) {
  suppressPackageStartupMessages({ library(dplyr); library(cli) })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)

  cfg    <- ctx$config
  bl_cfg <- cfg$trajectory_plot_jlcm %||% list()

  index_vars <- bl_cfg$index_vars %||% stop("trajectory_plot_jlcm$index_vars 未配置。")
  cycle       <- as.integer(bl_cfg$cycle %||% 28L)
  plot_width  <- bl_cfg$plot_width %||% 8
  plot_height <- bl_cfg$plot_height %||% 4
  id_col      <- bl_cfg$id_column %||% cfg$data$id_column %||% "subject_id"
  font_family <- plot_font_from_config(cfg)

  n_total  <- 0L
  n_done   <- 0L
  n_skip   <- 0L
  n_queued <- 0L

  for (Index in index_vars) {
    class_for_plot <- trajectory_resolve_class_ng_spec(
      ctx, Index, cfg, bl_cfg, field = "class_for_plot", fallback = 2L
    )
    cli::cli_alert_info("trajectory_plot_jlcm [{Index}]: 使用 ng={paste(class_for_plot, collapse=', ')}")
    n_total <- n_total + length(class_for_plot)

    for (D in class_for_plot) {
      n_done <- n_done + 1L
      key    <- paste0(Index, "_D", D)
      cli::cli_h2("[{n_done}/{n_total}] trajectory_plot_jlcm: {key}")

      long_data <- .tpj04_load_long_data(ctx, key, Index, D, bl_cfg)
      if (is.null(long_data) || !"Class" %in% names(long_data) ||
          !"Value" %in% names(long_data)) {
        cli::cli_alert_warning("{key}: 长格式数据不可用或缺列，跳过")
        n_skip <- n_skip + 1L
        next
      }

      model_obj <- .tpj04_load_jlcm_model(ctx, Index, D, bl_cfg)
      if (is.null(model_obj)) {
        cli::cli_alert_warning("{key}: JLCM 模型不可用，跳过")
        n_skip <- n_skip + 1L
        next
      }

      jlcm_entry <- ctx$results$trajectory_jlcm_models[[Index]]
      cov_cols <- if (!is.null(jlcm_entry) && exists("trajectory_jlcm_cov_cols", mode = "function")) {
        trajectory_jlcm_cov_cols(jlcm_entry, model_obj)
      } else {
        as.character(jlcm_entry$covariate_vars_used %||% character(0))
      }

      queued_this <- FALSE
      local({
        mo <- model_obj; ld <- long_data; idx <- Index; d <- D
        cy <- cycle; ic <- id_col; ff <- font_family; cc <- cov_cols
        pw <- plot_width * max(1, d / 3)
        ph <- plot_height
        p <- .tpj04_make_plot(mo, ld, idx, d, cy, ic, ff, cc)
        if (is.null(p)) {
          cli::cli_alert_warning("{paste0(idx,'_D',d)}: predictY 失败，跳过")
          return()
        }
        fn <- paste0("Figure_Trajectory_", idx, "_D", d, ".pdf")
        ctx <<- save_figure(ctx, filename = fn,
                            plot_fn = (function(pp) function() print(pp))(p),
                            width = pw, height = ph)
        queued_this <<- TRUE
      })
      if (isTRUE(queued_this)) {
        n_queued <- n_queued + 1L
        cli::cli_alert_success("{key}: JLCM 图入队")
      }
    }
  }

  if (n_queued == 0L && .tpj04_should_pause(bl_cfg, "pause_on_no_figures", TRUE)) {
    .tpj04_pause(
      ctx,
      "trajectory_plot_jlcm 无有效图形入队。",
      paste0(
        "请检查：① 是否已运行 trajectory_jlcm；",
        "② trajectory_plot_jlcm$index_vars / class_for_plot；",
        "③ jlcm_model_dir 兜底路径。"
      ),
      NULL
    )
  }

  cli::cli_alert_success(
    "trajectory_plot_jlcm 完成: {n_queued} 张入队，{n_skip} 跳过。"
  )
  ctx
}

register_block(
  "trajectory_plot_jlcm", block_trajectory_plot_jlcm,
  "JLCM 轨迹可视化：predictY 预测曲线 + facet，SCI 风格 PDF"
)
