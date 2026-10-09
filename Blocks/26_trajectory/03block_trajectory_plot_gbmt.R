###############################################################################
#  trajectory_plot_gbmt — GBMT 轨迹分组可视化（个体线 + LOESS 趋势）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_data = ctx$data$trajectory_long（或 long_data_dir 磁盘兜底）
#  require_upstream = trajectory_gbmt（或已有 D01_long_*.RData）
#
#  trajectory_plot_gbmt = list(
#    index_vars            = c("BAR"),
#    class_for_plot        = 2:8,                   # NULL → class_range
#    cycle                 = 28L,
#    y_q                   = c(0.01, 0.99),
#    plot_width            = 8,
#    plot_height           = 4,
#    id_column             = NULL,
#    long_data_dir         = NULL,
#    long_data_filename_template = "D01_long_{Index}_D_{D}.RData",
#    long_data_obj         = "long",
#    pause_enable          = TRUE,
#    pause_on_no_figures   = TRUE
#  ),
#
#  register_block: "trajectory_plot_gbmt"
#  输出: Figures/Figure_Trajectory_{Index}_D{D}.pdf
###############################################################################

.tpg03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tpg03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_plot_gbmt", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tpg03_resolve_path <- function(dir_path, fname) {
  if (grepl("^(/|[A-Za-z]:[/\\\\])", dir_path))
    file.path(dir_path, fname)
  else
    file.path(getwd(), dir_path, fname)
}

.tpg03_load_long_data <- function(ctx, key, Index, D, bl_cfg) {
  long_data <- ctx$data$trajectory_long[[key]]
  long_data_dir     <- bl_cfg$long_data_dir %||% NULL
  long_filename_tpl <- bl_cfg$long_data_filename_template %||%
    "D01_long_{Index}_D_{D}.RData"
  long_data_obj_nm  <- bl_cfg$long_data_obj %||% "long"

  if (!is.null(long_data) || is.null(long_data_dir)) return(long_data)

  fname <- gsub("\\{Index\\}", Index, gsub("\\{D\\}", as.character(D), long_filename_tpl))
  fpath <- .tpg03_resolve_path(long_data_dir, fname)
  if (!file.exists(fpath)) return(NULL)

  e <- new.env(parent = emptyenv())
  load(fpath, envir = e)
  long_data <- tryCatch(get(long_data_obj_nm, envir = e), error = function(e2) NULL)
  if (!is.null(long_data))
    cli::cli_alert_info("从磁盘加载长格式: {.file {fpath}}")
  long_data
}

.tpg03_make_plot <- function(data, Index, D, cycle, y_q, id_col, font_family) {
  suppressPackageStartupMessages({
    library(ggplot2); library(dplyr); library(RColorBrewer)
  })

  n_cls  <- dplyr::n_distinct(data[["Class"]])
  col_n  <- max(3L, min(n_cls, 8L))
  colors <- RColorBrewer::brewer.pal(col_n, "Set3")[seq_len(n_cls)]

  class_info <- data |>
    dplyr::distinct(.data[[id_col]], Class) |>
    dplyr::count(Class, name = "N") |>
    dplyr::mutate(
      percent = round(N / sum(N) * 100, 2),
      label   = paste0(Class, ": N = ", N, " (", percent, "%)")
    ) |>
    dplyr::arrange(Class)

  data2 <- data |>
    dplyr::left_join(class_info |> dplyr::select(Class, label), by = "Class")

  y_lim <- quantile(data2[["Value"]], probs = y_q, na.rm = TRUE)
  x_breaks_auto <- unique(round(seq(1, cycle, length.out = min(8L, cycle))))
  x_breaks <- sort(unique(c(1L, x_breaks_auto, as.integer(cycle))))

  ggplot2::ggplot(data2, ggplot2::aes(x = Time, y = Value)) +
    ggplot2::geom_line(
      ggplot2::aes(group = .data[[id_col]]),
      alpha = 0.15, color = "grey70", linewidth = 0.3
    ) +
    ggplot2::geom_smooth(
      ggplot2::aes(group = label, color = label),
      method = "loess", formula = y ~ x, se = TRUE, linewidth = 1, alpha = 0.15
    ) +
    ggplot2::scale_color_manual(values = setNames(colors, class_info$label)) +
    ggplot2::scale_x_continuous(
      expand = c(0.01, 0), limits = c(1, cycle), breaks = x_breaks, labels = x_breaks
    ) +
    ggplot2::coord_cartesian(ylim = c(as.numeric(y_lim[1]), as.numeric(y_lim[2]))) +
    ggplot2::labs(
      x = "Wave", y = Index, color = "Trajectory Class",
      title = paste0(Index, " — Trajectory Patterns (", D, " Classes)")
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      text = ggplot2::element_text(family = font_family),
      axis.title = ggplot2::element_text(family = font_family, size = 11),
      axis.text = ggplot2::element_text(family = font_family, size = 9),
      legend.title = ggplot2::element_text(family = font_family, size = 10),
      legend.text = ggplot2::element_text(family = font_family, size = 9),
      plot.title = ggplot2::element_text(family = font_family, size = 12),
      legend.position = "right"
    )
}

block_trajectory_plot_gbmt <- function(ctx, ...) {
  suppressPackageStartupMessages({ library(dplyr); library(cli) })

  cfg    <- ctx$config
  bl_cfg <- cfg$trajectory_plot_gbmt %||% list()

  index_vars <- bl_cfg$index_vars %||% stop("trajectory_plot_gbmt$index_vars 未配置。")
  class_for_plot <- as.integer(
    bl_cfg$class_for_plot %||% bl_cfg$class_range %||%
      stop("trajectory_plot_gbmt$class_for_plot 未配置。")
  )
  cycle       <- as.integer(bl_cfg$cycle %||% 28L)
  y_q         <- bl_cfg$y_q %||% c(0.01, 0.99)
  plot_width  <- bl_cfg$plot_width %||% 8
  plot_height <- bl_cfg$plot_height %||% 4
  id_col      <- bl_cfg$id_column %||% cfg$data$id_column %||% "subject_id"
  font_family <- plot_font_from_config(cfg)

  n_total  <- length(index_vars) * length(class_for_plot)
  n_done   <- 0L
  n_skip   <- 0L
  n_queued <- 0L

  for (Index in index_vars) {
    for (D in class_for_plot) {
      n_done <- n_done + 1L
      key    <- paste0(Index, "_D", D)
      cli::cli_h2("[{n_done}/{n_total}] trajectory_plot_gbmt: {key}")

      long_data <- .tpg03_load_long_data(ctx, key, Index, D, bl_cfg)
      if (is.null(long_data) || !"Class" %in% names(long_data) ||
          !"Value" %in% names(long_data)) {
        cli::cli_alert_warning("{key}: 长格式数据不可用或缺列，跳过")
        n_skip <- n_skip + 1L
        next
      }

      local({
        ld <- long_data; idx <- Index; d <- D
        cy <- cycle; yq <- y_q; ic <- id_col; ff <- font_family
        pw <- plot_width; ph <- plot_height
        p <- .tpg03_make_plot(ld, idx, d, cy, yq, ic, ff)
        fn <- paste0("Figure_Trajectory_", idx, "_D", d, ".pdf")
        ctx <<- save_figure(ctx, filename = fn,
                            plot_fn = local({ pp <- p; function() pp }),
                            width = pw, height = ph)
      })
      n_queued <- n_queued + 1L
      cli::cli_alert_success("{key}: GBMT 图入队 ({plot_width}×{plot_height} in)")
    }
  }

  if (n_queued == 0L && .tpg03_should_pause(bl_cfg, "pause_on_no_figures", TRUE)) {
    .tpg03_pause(
      ctx,
      "trajectory_plot_gbmt 无有效图形入队。",
      paste0(
        "请检查：① 是否已运行 trajectory_gbmt；",
        "② trajectory_plot_gbmt$index_vars / class_for_plot；",
        "③ long_data_dir 兜底路径。"
      ),
      NULL
    )
  }

  cli::cli_alert_success(
    "trajectory_plot_gbmt 完成: {n_queued} 张入队，{n_skip} 跳过。"
  )
  ctx
}

register_block(
  "trajectory_plot_gbmt", block_trajectory_plot_gbmt,
  "GBMT 轨迹可视化：个体背景线 + LOESS 趋势，SCI 风格 PDF"
)
