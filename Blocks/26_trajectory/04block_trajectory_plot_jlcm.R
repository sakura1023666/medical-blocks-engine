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
                             cov_cols = character(0), class_map = NULL, ylim = NULL) {
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

  # 与 Fig2A.R 一致：固定 Okabe-Ito 配色；双库对齐时用 class_map（原始 JLCM class → 展示 class）
  class_colors <- c(
    "Class 1" = "#D55E00", "Class 2" = "#E69F00", "Class 3" = "#56B4E9",
    "Class 4" = "#009E73", "Class 5" = "#E87A90", "Class 6" = "#7B68EE"
  )
  if (!is.null(class_map) && length(class_map)) {
    swap_map <- class_map
  } else {
    swap_map <- trajectory_class_swap_map(as.data.frame(m$pprob)$class)
  }

  actual_classes <- sort(unique(trajectory_apply_class_swap(as.data.frame(m$pprob)$class, swap_map)))
  ng             <- length(actual_classes)
  class_levels   <- paste0("Class ", actual_classes)
  color_vec      <- class_colors[class_levels]
  if (any(is.na(color_vec)))
    color_vec[is.na(color_vec)] <- scales::hue_pal()(ng)[is.na(color_vec)]

  cov_src <- if (!is.null(long_data)) long_data else data.frame()
  # long 数据常用 Time；predictY 需要 time_day
  if (!"time_day" %in% names(cov_src) && "Time" %in% names(cov_src))
    cov_src$time_day <- cov_src$Time
  if (!length(cov_cols) && exists("trajectory_jlcm_cov_cols", mode = "function")) {
    cov_cols <- trajectory_jlcm_cov_cols(list(), m)
  }
  if (!length(cov_cols) && !is.null(m$Names$Xnames2)) {
    cov_cols <- setdiff(as.character(m$Names$Xnames2),
                        c("time_day", "intercept", "(Intercept)", "scr_std"))
  }
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
    patient_df <- long_data |>
      dplyr::select(dplyr::all_of(c(id_col, "Class")), dplyr::any_of(surv_cols)) |>
      dplyr::distinct() |>
      dplyr::mutate(class_num = trajectory_apply_class_swap(Class, swap_map)) |>
      dplyr::filter(!is.na(class_num))

    outcome_info <- patient_df |>
      dplyr::group_by(class_num) |>
      dplyr::summarise(
        n = dplyr::n(),
        death_rate = if ("surv_event" %in% names(patient_df))
          mean(surv_event == 1, na.rm = TRUE) * 100 else NA_real_,
        .groups = "drop"
      )

    # 真正的 KM 中位生存；28 天内未降至 0.5 → NR（禁止 median(surv_time) 冒充）
    if (all(c("surv_time", "surv_event") %in% names(patient_df)) &&
        requireNamespace("survival", quietly = TRUE)) {
      km_dat <- patient_df |>
        dplyr::mutate(
          event01 = as.integer(surv_event == 1L),
          time_km = ifelse(
            event01 == 0L, as.numeric(cycle),
            pmin(suppressWarnings(as.numeric(surv_time)), as.numeric(cycle))
          ),
          class_label = factor(
            paste0("Class ", class_num),
            levels = class_levels
          )
        ) |>
        dplyr::filter(is.finite(time_km), time_km > 0, !is.na(event01), !is.na(class_label))
      med_map <- stats::setNames(rep(NA_real_, length(class_levels)), class_levels)
      if (nrow(km_dat) >= 2L && nlevels(droplevels(km_dat$class_label)) >= 1L) {
        km_fit <- tryCatch(
          survival::survfit(survival::Surv(time_km, event01) ~ class_label, data = km_dat),
          error = function(e) NULL
        )
        if (!is.null(km_fit)) {
          tab <- tryCatch(as.data.frame(summary(km_fit)$table), error = function(e) NULL)
          if (!is.null(tab) && "median" %in% names(tab)) {
            rn <- gsub(".*=", "", rownames(tab))
            for (i in seq_len(nrow(tab))) {
              lab <- rn[i]
              if (lab %in% names(med_map)) med_map[[lab]] <- suppressWarnings(as.numeric(tab$median[i]))
            }
          }
        }
      }
      outcome_info$median_surv <- unname(med_map[paste0("Class ", outcome_info$class_num)])
    } else {
      outcome_info$median_surv <- NA_real_
    }

    outcome_info <- outcome_info |>
      dplyr::mutate(
        median_text = ifelse(
          is.finite(median_surv),
          sprintf("%.1f days", median_surv),
          sprintf("NR (>%g d)", cycle)
        ),
        label_text = dplyr::case_when(
          !is.na(death_rate) ~
            sprintf("N = %d\nDeath: %.1f%%\nMedian Survival: %s", n, death_rate, median_text),
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

  if (is.null(ylim) || length(ylim) < 2L || !all(is.finite(ylim[1:2]))) {
    obs <- if (!is.null(bg_data)) bg_data$value_bg else pred_tidy$Value
    vv <- c(as.numeric(obs), as.numeric(pred_tidy$Value))
    vv <- vv[is.finite(vv)]
    if (length(vv) && min(vv) > 10) {
      # 大尺度指标（如 SOSM≈300）：按数据范围留白，禁止 ymin=1 把曲线顶到图顶
      lo <- as.numeric(stats::quantile(vv, 0.01, na.rm = TRUE))
      hi <- as.numeric(stats::quantile(vv, 0.99, na.rm = TRUE))
      pad <- max((hi - lo) * 0.12, 1)
      ylim <- c(floor(lo - pad), ceiling(hi + pad))
    } else {
      # 含小尺度比值（WPR≈0.05）：trajectory_shared_ylim 会在 max<1 时改数据驱动，勿硬 ymin=1
      ylim <- trajectory_shared_ylim(obs, pred_tidy$Value, ymin = 1)
    }
  }
  ylim <- as.numeric(ylim[1:2])
  # 仅裁极端离群；若整段预测已落在轴内则不动。禁止把 <ymin 的真曲线抬成平线。
  pred_in_range <- is.finite(pred_tidy$Value) &
    pred_tidy$Value >= ylim[1] & pred_tidy$Value <= ylim[2]
  if (mean(pred_in_range, na.rm = TRUE) < 0.5) {
    # ylim 与预测严重错位时，改用预测+观察重算（再防一次硬 ymin=1）
    ylim <- trajectory_shared_ylim(
      if (!is.null(bg_data)) bg_data$value_bg else pred_tidy$Value,
      pred_tidy$Value,
      ymin = 1
    )
  }
  pred_tidy$Value <- pmin(pmax(pred_tidy$Value, ylim[1]), ylim[2])

  # facet 用 Class 标签；N/死亡率/KM 中位生存用面板内标注（对齐 Fig2A）
  pred_tidy$facet_lab <- pred_tidy$class_label
  if (!is.null(bg_data)) bg_data$facet_lab <- bg_data$class_label

  y_span <- diff(ylim)
  if (!is.finite(y_span) || y_span <= 0) y_span <- 1
  if (!is.null(outcome_info) && nrow(outcome_info)) {
    outcome_info <- outcome_info |>
      dplyr::mutate(
        facet_lab = class_label,
        x_pos = cycle * 0.98,
        y_pos = ylim[2] - 0.02 * y_span
      )
  }

  p <- ggplot2::ggplot()
  # ng≥3 用 2 列网格；大类灰线抽样放在入图之前
  ncol_facet <- if (ng <= 2L) as.integer(ng) else 2L
  max_bg_ids <- 120L
  if (!is.null(bg_data) && id_col %in% names(bg_data) && "class_num" %in% names(bg_data)) {
    set.seed(42L)
    keep_ids <- bg_data |>
      dplyr::distinct(.data[[id_col]], class_num) |>
      dplyr::group_by(class_num) |>
      dplyr::group_modify(function(.x, .y) {
        if (nrow(.x) <= max_bg_ids) .x else dplyr::slice_sample(.x, n = max_bg_ids)
      }) |>
      dplyr::ungroup()
    bg_data <- dplyr::semi_join(bg_data, keep_ids, by = c(id_col, "class_num"))
  }
  if (!is.null(bg_data))
    p <- p + ggplot2::geom_line(
      data = bg_data,
      ggplot2::aes(x = time_bg, y = value_bg, group = .data[[id_col]]),
      color = "grey75", alpha = 0.12, linewidth = 0.18
    )
  p <- p +
    ggplot2::geom_line(
      data = pred_tidy,
      ggplot2::aes(x = time, y = Value, color = class_label),
      linewidth = 1.05
    )
  if (!is.null(outcome_info) && nrow(outcome_info)) {
    p <- p + ggplot2::geom_text(
      data = outcome_info,
      ggplot2::aes(x = x_pos, y = y_pos, label = label_text),
      hjust = 1, vjust = 1, size = 2.8, lineheight = 0.95,
      color = "black", family = font_family
    )
  }

  p <- p +
    ggplot2::facet_wrap(~ facet_lab, ncol = ncol_facet) +
    ggplot2::scale_color_manual(values = color_vec, guide = "none") +
    ggplot2::scale_x_continuous(breaks = seq(0, cycle, by = 7)) +
    ggplot2::scale_y_continuous(breaks = pretty(ylim, n = 4)) +
    ggplot2::labs(
      title = paste0(Index, " Trajectories by Latent Class (ng = ", ng, ")", title_suffix),
      x = "Day in ICU", y = Index
    ) +
    ggplot2::coord_cartesian(xlim = c(0, cycle), ylim = ylim, expand = FALSE) +
    ggplot2::theme_classic(base_size = 10, base_family = font_family) +
    ggplot2::theme(
      legend.position = "none",
      plot.title = ggplot2::element_text(hjust = 0.5, size = 11, face = "bold"),
      axis.title = ggplot2::element_text(size = 10),
      axis.title.x = ggplot2::element_text(margin = ggplot2::margin(5, 0, 0, 0)),
      axis.text = ggplot2::element_text(size = 9, color = "black"),
      strip.text = ggplot2::element_text(size = 9, face = "bold",
                                         margin = ggplot2::margin(4, 3, 4, 3)),
      strip.background = ggplot2::element_rect(fill = "grey96", color = "grey80", linewidth = 0.25),
      panel.border = ggplot2::element_rect(fill = NA, color = "grey45", linewidth = 0.35),
      panel.spacing = grid::unit(0.55, "lines"),
      plot.margin = ggplot2::margin(4, 6, 2, 6)
    )
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
  plot_width  <- bl_cfg$plot_width %||% NULL
  plot_height <- bl_cfg$plot_height %||% 3.45
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

      class_map <- NULL
      ylim_plot <- NULL
      if (!is.null(bl_cfg$class_align_maps) && !is.null(bl_cfg$class_align_maps[[Index]])) {
        class_map <- bl_cfg$class_align_maps[[Index]]
      }
      if (!is.null(bl_cfg$ylim)) ylim_plot <- as.numeric(bl_cfg$ylim)

      queued_this <- FALSE
      local({
        mo <- model_obj; ld <- long_data; idx <- Index; d <- D
        cy <- cycle; ic <- id_col; ff <- font_family; cc <- cov_cols
        cm <- class_map; yl <- ylim_plot
        pw <- if (!is.null(plot_width)) plot_width else (3.35 * as.numeric(d) + 1.1)
        ph <- plot_height %||% 3.45
        p <- .tpj04_make_plot(mo, ld, idx, d, cy, ic, ff, cc, class_map = cm, ylim = yl)
        if (is.null(p)) {
          cli::cli_alert_warning("{paste0(idx,'_D',d)}: predictY 失败，跳过")
          return()
        }
        fn <- paste0("Figure Trajectory ", idx, " D", d, ".pdf")
        ctx <<- save_figure(ctx, filename = fn,
                            plot_fn = local({ pp <- p; function() pp }),
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
