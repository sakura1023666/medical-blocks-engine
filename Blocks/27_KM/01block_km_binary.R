###############################################################################
#  km_binary — 连续指标按 cutoff 二分后的 Kaplan–Meier 曲线（高低组）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  cutoff       = cfg$km_binary$cutoff → ctx$results$cutoff_value → segmented_cox 等
#
#  km_binary = list(
#    index_var     = NULL,              # NULL → survival$index_var
#    time_var      = NULL,
#    event_var     = NULL,
#    cutoff        = NULL,
#    level_low     = "low",
#    level_high    = "high",
#    palette       = NULL,               # NULL → R/color_palettes.R 统一双色
#    xlim          = NULL,              # NULL → config$km$xlim
#    break_time_by = NULL,
#    xlab          = NULL,
#    ylab          = NULL,
#    risk_table    = TRUE,
#    plot_width    = 8,
#    plot_height   = 7,
#    figure_filename = NULL,            # NULL → Figure 3. Kaplan–Meier ... {index}.pdf
#    pause_enable  = TRUE,
#    pause_on_no_output = TRUE
#  ),
#
#  register_block: "km_binary"
#  输出: Figures/Figure 3. Kaplan–Meier curves ... pdf
###############################################################################

.kmb01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.kmb01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "km_binary", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.kmb01_surv_pdf_ok <- function(path) {
  fi <- tryCatch(file.info(path), error = function(e) NULL)
  !is.null(fi) && isTRUE(nrow(fi) == 1L) && !is.na(fi$size) && fi$size > 10L
}

.kmb01_resolve_cutoff <- function(bl_cfg, ctx, index_var) {
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
  NULL
}

.kmb01_coerce_event_01 <- function(x, cfg, event_var) {
  if (is.numeric(x)) {
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
    stop("km_binary: ", event_var, " 非 0/1 数值编码。")
  }
  if (is.logical(x)) return(as.integer(x))
  xc <- trimws(as.character(x))
  ref_lbl <- trimws(cfg$project$reference_group %||% "")
  ana_lbl <- trimws(cfg$project$analysis_group %||% "")
  out <- rep(NA_integer_, length(xc))
  if (nzchar(ana_lbl)) out[xc == ana_lbl] <- 1L
  if (nzchar(ref_lbl)) out[xc == ref_lbl] <- 0L
  if (nzchar(ana_lbl)) out[tolower(xc) == tolower(ana_lbl) & is.na(out)] <- 1L
  if (nzchar(ref_lbl)) out[tolower(xc) == tolower(ref_lbl) & is.na(out)] <- 0L
  out[is.na(xc)] <- NA_integer_
  out
}

block_km_binary <- function(ctx, time_var = NULL, event_var = NULL,
                            index_var = NULL, cutoff = NULL, ...) {
  suppressPackageStartupMessages({
    library(survival)
    library(survminer)
    library(ggplot2)
    library(cli)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$km_binary %||% list()
  km_cfg <- cfg$km %||% list()
  surv   <- cfg$survival %||% list()

  time_var  <- time_var  %||% bl_cfg$time_var  %||% surv$time_var  %||% "futime"
  event_var <- event_var %||% bl_cfg$event_var %||% surv$event_var %||% "fustatus"
  index_var <- index_var %||% bl_cfg$index_var %||% surv$index_var %||%
    stop("km_binary$index_var 未配置。")

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.kmb01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .kmb01_pause(ctx, "无分析数据（imputed / cleaned 均为空）。",
                   "请先运行 imputation 或 data_clean。", NULL)
    }
    stop("km_binary: 无分析数据。")
  }

  cutoff <- cutoff %||% .kmb01_resolve_cutoff(bl_cfg, ctx, index_var)
  if (is.null(cutoff)) {
    if (.kmb01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .kmb01_pause(
        ctx, "未找到 cutoff。",
        "设置 config$km_binary$cutoff，或先运行 RCS / ROC / segmented_cox 写入 ctx$results$cutoff_value。",
        NULL
      )
    }
    stop("km_binary: cutoff 未配置且上游无 cutoff_value。")
  }

  need <- c(time_var, event_var, index_var)
  miss <- setdiff(need, names(data))
  if (length(miss)) stop("km_binary: 数据中缺少列: ", paste(miss, collapse = ", "))

  lvl_lo <- bl_cfg$level_low  %||% "low"
  lvl_hi <- bl_cfg$level_high %||% "high"
  palette <- bl_cfg$palette %||% block_default_palette(2L, cfg)
  font_family <- plot_font_from_config(cfg)

  analysis_data <- stats::na.omit(data[, need, drop = FALSE])
  analysis_data[[event_var]] <- as.numeric(
    .kmb01_coerce_event_01(analysis_data[[event_var]], cfg, event_var)
  )
  data_categorized <- analysis_data
  data_categorized$Group <- ifelse(
    data_categorized[[index_var]] >= cutoff, lvl_hi, lvl_lo
  )
  data_categorized$Group <- factor(data_categorized$Group, levels = c(lvl_lo, lvl_hi))

  surv_grp_form <- stats::as.formula(paste0(
    "Surv(", time_var, ", ", event_var, ") ~ Group"
  ))
  .logrank_p <- tryCatch({
    sd <- survival::survdiff(surv_grp_form, data = data_categorized)
    stats::pchisq(sd$chisq, length(sd$n) - 1L, lower.tail = FALSE)
  }, error = function(e) NA_real_)
  fit_surv <- tryCatch(
    survminer::surv_fit(surv_grp_form, data = data_categorized),
    error = function(e) {
      tryCatch(survival::survfit(surv_grp_form, data = data_categorized),
               error = function(e2) NULL)
    }
  )

  saved <- FALSE
  if (!is.null(fit_surv)) {
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    disease <- gsub("_", " ", cfg$project$disease %||% cfg$project$analysis_group %||% "patients")
    cap_tpl <- as.character(bl_cfg$figure_caption_template %||% "")[1L]
    caption <- if (nzchar(cap_tpl)) {
      out <- gsub("\\{index\\}", index_var, cap_tpl, fixed = FALSE)
      out <- gsub("\\{method\\}", "binary", out, fixed = FALSE)
      gsub("\\{disease\\}", disease, out, fixed = FALSE)
    } else {
      paste0(
        "Kaplan\u2013Meier curves of ", index_var,
        " binary and mortality in ", disease
      )
    }
    fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% NA_integer_))
    fig_kind <- as.character(bl_cfg$figure_kind %||% "main_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "main_figure"
    fig_name <- if (!is.null(bl_cfg$figure_filename) && nzchar(bl_cfg$figure_filename)) {
      bl_cfg$figure_filename
    } else if (is.finite(fig_no) && fig_no >= 1L && exists("pub_figure_filepath_at", mode = "function")) {
      basename(pub_figure_filepath_at(
        fig_dir, fig_no, caption, ext = "pdf", bump_counter = TRUE, kind = fig_kind
      ))
    } else {
      pub_figure_file(ctx, fig_kind, caption)
    }
    if (exists(".pub_path_with_slot_label", mode = "function")) {
      fig_name <- basename(.pub_path_with_slot_label(ctx, fig_name))
    }
    fig_surv_file <- file.path(fig_dir, fig_name)

    time_div <- as.numeric(bl_cfg$time_divisor %||% km_cfg$time_divisor %||% surv$time_divisor %||% 1)
    if (exists(".kms02_resolve_time_axis", mode = "function")) {
      axis <- .kms02_resolve_time_axis(
        fit_surv, data_categorized, time_var, time_div, bl_cfg, km_cfg
      )
      km_xlim <- axis$xlim
      km_break <- axis$break_time_by
    } else {
      km_xlim <- bl_cfg$xlim %||% km_cfg$xlim
      km_break <- bl_cfg$break_time_by %||% km_cfg$break_time_by
      if (is.null(km_xlim)) km_xlim <- c(0, 180)
      if (is.null(km_break)) km_break <- 14
    }
    km_xlab  <- bl_cfg$xlab %||% km_cfg$xlab %||% "Follow-up time (days)"
    plot_w   <- bl_cfg$plot_width  %||% 8
    plot_h   <- bl_cfg$plot_height %||% 7
    risk_tbl <- isTRUE(bl_cfg$risk_table %||% TRUE)

    p <- tryCatch(
      ggsurvplot(
        fit_surv, data = data_categorized,
        risk.table = risk_tbl, conf.int = FALSE,
        surv.median.line = "hv",
        xlim = km_xlim, break.time.by = km_break, xlab = km_xlab,
        legend.title = "", pval = TRUE, palette = palette,
        ggtheme = ggplot2::theme_classic(base_family = font_family) +
          ggplot2::theme(
            text = ggplot2::element_text(family = font_family),
            plot.title = ggplot2::element_text(family = font_family, face = "bold", hjust = 0.5),
            legend.text = ggplot2::element_text(family = font_family),
            axis.text = ggplot2::element_text(family = font_family),
            axis.title = ggplot2::element_text(family = font_family)
          ),
        tables.theme = ggplot2::theme_classic(base_family = font_family) +
          ggplot2::theme(
            text = ggplot2::element_text(family = font_family),
            axis.text = ggplot2::element_text(family = font_family),
            axis.title = ggplot2::element_text(family = font_family)
          )
      ),
      error = function(e) {
        cli::cli_alert_warning("ggsurvplot 构建失败: {e$message}")
        NULL
      }
    )

    if (!is.null(p) &&
        exists("is_pub_profile", mode = "function") &&
        is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki") &&
        exists("pub_figure_profile_apply_ggplot", mode = "function")) {
      if (inherits(p$plot, "ggplot")) {
        p$plot <- pub_figure_profile_apply_ggplot(p$plot, ctx$config)
      }
      if (inherits(p$table, "ggplot")) {
        p$table <- pub_figure_profile_apply_ggplot(p$table, ctx$config)
      }
    }

    if (!is.null(p)) {
      fail_msgs <- character(0)
      comb <- tryCatch(
        survminer::arrange_ggsurvplot(p, print = FALSE),
        error = function(e) {
          fail_msgs <<- c(fail_msgs, paste0("arrange: ", e$message))
          NULL
        }
      )
      if (!is.null(comb)) {
        for (fam in unique(c(font_family, "Times New Roman", "Times", "Liberation Serif", "serif"))) {
          ok <- tryCatch({
            if (file.exists(fig_surv_file)) unlink(fig_surv_file)
            ggplot2::ggsave(fig_surv_file, plot = comb, width = plot_w, height = plot_h,
                            device = grDevices::cairo_pdf, family = fam)
            .kmb01_surv_pdf_ok(fig_surv_file)
          }, error = function(e) FALSE)
          if (isTRUE(ok)) { saved <- TRUE; break }
        }
      }
      if (!saved) {
        ok <- tryCatch({
          if (file.exists(fig_surv_file)) unlink(fig_surv_file)
          grDevices::cairo_pdf(fig_surv_file, width = plot_w, height = plot_h, family = "serif")
          tryCatch(print(p, newpage = FALSE), error = function(e) print(p))
          grDevices::dev.off()
          .kmb01_surv_pdf_ok(fig_surv_file)
        }, error = function(e) {
          try(grDevices::dev.off(), silent = TRUE)
          FALSE
        })
        if (isTRUE(ok)) saved <- TRUE
      }
      if (saved) {
        cli::cli_alert_success("KM 图已保存: {.file {basename(fig_surv_file)}}")
      }
    }
  }

  if (!saved && .kmb01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .kmb01_pause(
      ctx, "km_binary 未能生成 KM 图。",
      "检查 cutoff、样本量、time/event 列编码及 survfit 是否失败。", NULL
    )
  }

  ctx$results$km_binary <- list(
    index_var = index_var, cutoff = cutoff,
    n = nrow(data_categorized),
    level_low = lvl_lo, level_high = lvl_hi,
    logrank_p = .logrank_p
  )
  cli::cli_alert_success("km_binary 完成（cutoff = {round(cutoff, 4)}）。")
  ctx
}

register_block(
  "km_binary", block_km_binary,
  "cutoff 二分 Kaplan–Meier 曲线（高低组 + risk table）"
)
