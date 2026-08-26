###############################################################################
#  plot_cutoff — maxstat/surv_cutpoint 拐点展示图（已停产；默认 enable=FALSE）。
#
#  2026-08-21 起：预后双库不再导出 maxstat Cutoff 图；分段 Cox / Table S#
#  统一用 RCS 切点（ctx$results$cutoff_value）。本块保留仅供显式 enable=TRUE 的旧课题。
#
#  plot_cutoff = list(
#    enable     = FALSE,             # 默认跳过；TRUE 才画图
#    index_var  = NULL,
#    ...
#  ),
#
#  register_block: "plot_cutoff"
###############################################################################

.pc01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.pc01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "plot_cutoff", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.pc01_resolve_cutoff <- function(bl_cfg, ctx) {
  cv <- bl_cfg$cutoff %||% ctx$results$cutoff_value
  if (is.null(cv)) {
    sc <- ctx$results$segmented_cox_binary %||% ctx$results$segmented_cox %||% NULL
    if (!is.null(sc$cutoff)) cv <- sc$cutoff
  }
  if (is.null(cv)) {
    roc <- ctx$results$roc_summary %||% NULL
    if (!is.null(roc$cutoff)) cv <- roc$cutoff
  }
  cv <- suppressWarnings(as.numeric(cv)[1L])
  if (length(cv) == 1L && is.finite(cv)) return(cv)

  cf <- bl_cfg$cutoff_file %||% NULL
  if (!is.null(cf) && nzchar(as.character(cf)[1L])) {
    fp <- as.character(cf)[1L]
    if (!file.exists(fp)) {
      root <- ctx$root_output_dir %||% ctx$config$project$output_dir %||% NULL
      if (!is.null(root)) {
        fp2 <- file.path(root, fp)
        if (file.exists(fp2)) fp <- fp2
      }
    }
    if (file.exists(fp)) {
      ln <- tryCatch(trimws(readLines(fp, warn = FALSE, n = 1L)), error = function(e) NA_character_)
      cv2 <- suppressWarnings(as.numeric(ln))
      if (length(cv2) == 1L && is.finite(cv2)) return(cv2)
    }
  }
  if (!isTRUE(bl_cfg$auto_fallback %||% TRUE)) return(NULL)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  surv <- ctx$config$survival %||% list()
  idx <- bl_cfg$index_var %||% surv$index_var %||%
    (ctx$config$logistic %||% list())$index_var
  time_v <- bl_cfg$time_var %||% surv$time_var %||% "futime"
  event_v <- bl_cfg$event_var %||% surv$event_var %||% "fustatus"
  if (is.null(data) || is.null(idx) || !idx %in% names(data)) return(NULL)

  need <- c(time_v, event_v, idx)
  if (!all(need %in% names(data))) return(NULL)
  ad <- stats::na.omit(data[, need, drop = FALSE])
  if (nrow(ad) < 20L) return(NULL)

  minprop_cut <- suppressWarnings(as.numeric(
    bl_cfg$minprop %||% (ctx$config$weightplot %||% list())$minprop %||% 0.2
  ))
  if (length(minprop_cut) != 1L || !is.finite(minprop_cut) ||
      minprop_cut <= 0 || minprop_cut >= 0.5) {
    minprop_cut <- 0.2
  }
  res_cut <- tryCatch(
    survminer::surv_cutpoint(
      data = ad, time = time_v, event = event_v, variables = idx,
      minprop = minprop_cut, progressbar = FALSE
    ),
    error = function(e) NULL
  )
  if (!is.null(res_cut) && !is.null(res_cut$cutpoint)) {
    cv3 <- suppressWarnings(as.numeric(res_cut$cutpoint$cutpoint)[1L])
    if (length(cv3) == 1L && is.finite(cv3)) {
      cli::cli_alert_info("plot_cutoff: surv_cutpoint 自动 cutoff = {round(cv3, 4)}")
      return(cv3)
    }
  }

  xv <- suppressWarnings(as.numeric(ad[[idx]]))
  if (sum(is.finite(xv)) >= 10L) {
    med <- stats::median(xv, na.rm = TRUE)
    if (is.finite(med)) {
      cli::cli_alert_info("plot_cutoff: 使用指数中位数作为 cutoff = {round(med, 4)}")
      return(med)
    }
  }
  NULL
}

block_plot_cutoff <- function(ctx, time_var = NULL, event_var = NULL,
                              index_var = NULL, cutoff = NULL, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$plot_cutoff %||% list()
  # 默认停产：分段 Cox 改用 RCS 切点，不再出 maxstat Figure S1
  if (!isTRUE(bl_cfg$enable %||% FALSE)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("plot_cutoff: enable=FALSE，跳过 maxstat Cutoff 图（切点以 RCS 为准）")
    }
    ctx$results$plot_cutoff <- list(skipped = TRUE, reason = "disabled")
    return(ctx)
  }

  suppressPackageStartupMessages({
    library(survival)
    library(survminer)
    library(cli)
  })

  wp_cfg <- cfg$weightplot %||% list()
  surv   <- cfg$survival %||% list()

  time_var  <- time_var  %||% bl_cfg$time_var  %||% surv$time_var  %||% "futime"
  event_var <- event_var %||% bl_cfg$event_var %||% surv$event_var %||% "fustatus"
  index_var <- index_var %||% bl_cfg$index_var %||% surv$index_var %||%
    stop("plot_cutoff: index_var 未配置。")

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.pc01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .pc01_pause(ctx, "无分析数据（imputed / cleaned 均为空）。",
                  "请先运行 imputation 或 data_clean。", NULL)
    }
    stop("plot_cutoff: 无分析数据。")
  }

  cutoff <- cutoff %||% .pc01_resolve_cutoff(bl_cfg, ctx)
  if (is.null(cutoff)) {
    if (.pc01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .pc01_pause(
        ctx, "未找到 cutoff。",
        "设置 config$plot_cutoff$cutoff，或先运行 RCS / segmented_cox 写入 ctx$results$cutoff_value。",
        NULL
      )
    }
    stop("plot_cutoff: cutoff 未配置且上游无 cutoff_value。")
  }

  need <- c(time_var, event_var, index_var)
  miss <- setdiff(need, names(data))
  if (length(miss)) stop("plot_cutoff: 数据中缺少列: ", paste(miss, collapse = ", "))

  font_family <- plot_font_from_config(cfg)
  palette     <- bl_cfg$palette %||% block_default_palette(2L, cfg)
  plot_w      <- bl_cfg$plot_width  %||% 8
  plot_h      <- bl_cfg$plot_height %||% 8

  analysis_data <- stats::na.omit(data[, need, drop = FALSE])

  minprop_cut <- suppressWarnings(as.numeric(bl_cfg$minprop %||% wp_cfg$minprop %||% 0.2))
  if (length(minprop_cut) != 1L || !is.finite(minprop_cut) ||
      minprop_cut <= 0 || minprop_cut >= 0.5) {
    cli::cli_alert_warning("minprop 无效，surv_cutpoint 作图改用 0.2")
    minprop_cut <- 0.2
  }
  # 图上默认标真实 maxstat 最优点；上游 RCS/配置切点仅作对照，不钉虚线
  # annotate_cutoff: "maxstat"（默认）| "upstream"（旧行为：钉 RCS/配置）
  annotate_src <- tolower(trimws(as.character(
    bl_cfg$annotate_cutoff %||% "maxstat"
  )[1L]))
  if (!annotate_src %in% c("maxstat", "upstream", "rcs", "config")) {
    annotate_src <- "maxstat"
  }
  use_upstream_mark <- annotate_src %in% c("upstream", "rcs", "config")

  cli::cli_alert_info(
    "Cutoff 点图 surv_cutpoint: minprop = {minprop_cut}；上游切点 = {round(cutoff, 4)}；标注 = {annotate_src}"
  )

  res_cut <- tryCatch(
    survminer::surv_cutpoint(
      data = analysis_data,
      time = time_var,
      event = event_var,
      variables = index_var,
      minprop = minprop_cut,
      progressbar = FALSE
    ),
    error = function(e) NULL
  )

  saved <- FALSE
  maxstat_cut <- NA_real_
  display_cut <- cutoff
  if (!is.null(res_cut)) {
    maxstat_cut <- suppressWarnings(as.numeric(res_cut$cutpoint$cutpoint)[1L])
    if (isTRUE(use_upstream_mark)) {
      res_cut$cutpoint$cutpoint <- cutoff
      if (!is.null(res_cut[[index_var]])) {
        res_cut[[index_var]]$estimate <- cutoff
      }
      display_cut <- cutoff
      cli::cli_alert_info(
        "Figure S1 钉上游切点 = {round(cutoff, 4)}（maxstat 最优点 = {round(maxstat_cut, 4)}）"
      )
    } else {
      display_cut <- if (length(maxstat_cut) == 1L && is.finite(maxstat_cut)) {
        maxstat_cut
      } else {
        cutoff
      }
      cli::cli_alert_info(
        "Figure S1 标注 maxstat 最优点 = {round(display_cut, 4)}（上游 RCS/配置 = {round(cutoff, 4)} 不钉图）"
      )
    }

    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    fig_cap <- paste0(
      "Cutoff Point for ", index_var,
      " Based on Maximally Selected Rank Statistics Using the maxstat Package"
    )
    fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% NA_integer_)[1L])
    fig_kind <- as.character(bl_cfg$figure_kind %||% "main_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "main_figure"
    fig_cutoff_path <- if (!is.null(bl_cfg$figure_filename) &&
                           nzchar(as.character(bl_cfg$figure_filename)[1L])) {
      file.path(fig_dir, as.character(bl_cfg$figure_filename)[1L])
    } else if (is.finite(fig_no) && fig_no >= 1L &&
               exists("pub_figure_filepath_at", mode = "function")) {
      pub_figure_filepath_at(
        fig_dir, fig_no, fig_cap, ext = "pdf",
        bump_counter = isTRUE(bl_cfg$bump_counter %||% TRUE),
        kind = fig_kind
      )
    } else {
      file.path(fig_dir, pub_figure_file(ctx, fig_kind, fig_cap))
    }

    saved <- tryCatch({
      p_cut <- plot(res_cut, index_var, palette = palette)
      pin <- if (is.list(p_cut) && !inherits(p_cut, "plot_surv_cutpoint")) {
        if (index_var %in% names(p_cut)) p_cut[[index_var]] else p_cut[[1L]]
      } else {
        p_cut
      }
      # survminer 默认无衬线；强制 Times New Roman（cairo 可嵌）
      if (inherits(pin, "ggplot")) {
        pin <- pin + ggplot2::theme(
          text = ggplot2::element_text(family = font_family),
          axis.title = ggplot2::element_text(family = font_family),
          axis.text = ggplot2::element_text(family = font_family),
          plot.title = ggplot2::element_text(family = font_family),
          legend.text = ggplot2::element_text(family = font_family),
          legend.title = ggplot2::element_text(family = font_family)
        )
        if (exists("is_pub_profile", mode = "function") &&
            is_pub_profile(cfg, "mimic_inc_prog_sle_aki") &&
            exists("pub_figure_profile_apply_ggplot", mode = "function")) {
          pin <- pub_figure_profile_apply_ggplot(pin, cfg)
        }
      }
      if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(fig_cutoff_path, width = plot_w, height = plot_h, family = font_family)
      } else {
        grDevices::pdf(fig_cutoff_path, width = plot_w, height = plot_h, family = font_family)
      }
      print(pin, newpage = FALSE)
      grDevices::dev.off()
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("Cutoff plot failed: {e$message}")
      try(grDevices::dev.off(), silent = TRUE)
      FALSE
    })
    if (saved) {
      if (exists("mirror_pub_output_to_root", mode = "function")) {
        mirror_pub_output_to_root(ctx, fig_cutoff_path)
      }
      cli::cli_alert_success("Cutoff plot saved: {.file {basename(fig_cutoff_path)}}")
    }
  }

  if (!saved && .pc01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .pc01_pause(
      ctx,
      "plot_cutoff 未能生成 cutoff 图（surv_cutpoint 或 PDF 写出失败）。",
      "检查样本量、time/event/index 列及 minprop 设置。",
      utils::head(analysis_data, 5L)
    )
  }

  ctx$results$plot_cutoff <- list(
    index_var = index_var,
    cutoff = display_cut,
    maxstat_cutoff = maxstat_cut,
    upstream_cutoff = cutoff,
    annotate_cutoff = annotate_src,
    minprop = minprop_cut
  )
  # 下游分段 Cox 等仍认上游 RCS/配置切点；图上标注与 cutoff_value 解耦
  if (length(cutoff) == 1L && is.finite(cutoff)) {
    ctx$results$cutoff_value <- cutoff
  }
  cli::cli_alert_success("plot_cutoff 完成。")
  ctx
}

register_block(
  "plot_cutoff", block_plot_cutoff,
  "maxstat cutoff 展示图（默认标 surv_cutpoint 最优点；上游 RCS 可另存）"
)
