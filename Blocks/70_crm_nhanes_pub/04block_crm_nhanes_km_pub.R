###############################################################################
#  crm_nhanes_km_pub — NHANES 全因死亡 Kaplan-Meier 曲线（对应文献 Figure 1）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data      = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  requires_packages = c("survival")；survminer/gridExtra 可选，缺失时回退基础绘图设备
#
#  说明（加权口径证据链）：原文（Han et al. 2025 JAHA e038723）未在本仓库可读取的
#  文本证据中明确 Figure 1 的 KM 曲线是否为加权口径——【证据不足】，因此本块默认按
#  未加权 survfit() 展示（与文献常见"KM 用于直观展示、加权仅用于 Cox/有序 logistic"
#  的通行做法一致），不强行套用 survey 加权 KM。若用户已核实原文为加权 KM，可设
#  config$crm_nhanes_km_pub$weighted = TRUE 切换为 survival::survfit(weights=) 加权曲线
#  （非 survey::svykm，因 survey 包官方未提供加权 KM 估计量；此口径差异记录在
#  ctx$results$crm_nhanes_km_pub$weighted 中，不冒充与原文完全一致）。
#
#  说明（P 值口径，Task 3 fix）：survminer::ggsurvplot(pval=TRUE)／survival::survdiff()
#  的 log-rank 检验本身不支持加权（不同于 survfit/coxph 可以吃 weights=）。因此当
#  weighted = TRUE 时，图上不再显示裸的 pval=TRUE（那会让人误以为该 P 值也是加权
#  口径），而是显示自定义文字"Unweighted log-rank P = ...（weights unused for p）"；
#  可设 weighted_pval_label = FALSE 改为直接隐藏该 P 值（而不是标注）。weighted =
#  FALSE（默认）时完全不受影响，行为与之前一致。ctx$results$crm_nhanes_km_pub 中
#  始终记录 logrank_p_is_weighted = FALSE 与 logrank_p_note 供下游/报告核对口径。
#
#  crm_nhanes_km_pub = list(
#    time_var        = "futime",
#    event_var       = "fustatus",
#    group_var       = "CRM_count",
#    sua_col         = "SUA",
#    eligibility_col = "eligstat",
#    weighted        = FALSE,
#    weight_col      = NULL,
#    # 对齐原文 Figure 1：Non-CRM / 1 CRM / 2 CRM / 3 CRM
#    group_labels    = c("Non-CRM", "1 CRM", "2 CRM", "3 CRM"),
#    force_levels    = c(0, 1, 2, 3),
#    palette         = c("#E7B800", "#2E9FDF", "#FC4E07", "#00A087"),
#    xlab            = "Time",
#    ylab            = "Survival probability",
#    risk_table      = TRUE,
#    conf_int        = TRUE,
#    plot_width      = 8,
#    plot_height     = 7.5,
#    figure_basename = "Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count",
#    figure_caption  = "Kaplan-Meier survival curve for all-cause mortality by CRM conditions (NHANES)",
#    hr_table_filename = "Table 1-NHANES-KM_Cox_HR_by_CRM_count.csv",
#    write_png       = FALSE,
#    stratify_by_gout = FALSE,
#    weighted_pval_label = TRUE,
#    pause_enable = TRUE,
#    pause_on_no_output = TRUE
#  )
#
#  register_block: "crm_nhanes_km_pub"
#  典型位置: crm_nhanes_derive → ... → crm_nhanes_km_pub
#
#  读: ctx$data$cleaned %||% ctx$data$raw
#  写: ctx$results$crm_nhanes_km_pub
#
#  产出:
#    - Figures/Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count.pdf
#    - Tables/Table 1-NHANES-KM_Cox_HR_by_CRM_count.csv
#
#  pause: config$crm_nhanes_km_pub$pause_enable
###############################################################################

.crm70k_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70k_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_km_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_km_pub halted. See ctx$results$pause_point. / ",
    "NHANES KM 曲线异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.crm70k_file_ok <- function(path) {
  fi <- tryCatch(file.info(path), error = function(e) NULL)
  !is.null(fi) && isTRUE(nrow(fi) == 1L) && !is.na(fi$size) && fi$size > 10L
}

.crm70k_cox_hr <- function(d, time_var, event_var, group_var, weight_col = NULL) {
  form <- stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", group_var))
  fit <- tryCatch({
    if (!is.null(weight_col) && weight_col %in% names(d)) {
      survival::coxph(form, data = d, weights = d[[weight_col]], robust = TRUE)
    } else {
      survival::coxph(form, data = d)
    }
  }, error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  ci <- s$conf.int
  coefs <- s$coefficients
  p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
  data.frame(
    term = rownames(ci),
    HR = unname(ci[, "exp(coef)"]),
    Lower95 = unname(ci[, grep("lower", colnames(ci))[1L]]),
    Upper95 = unname(ci[, grep("upper", colnames(ci))[1L]]),
    P = unname(coefs[, p_col]),
    N = fit$n,
    Events = fit$nevent,
    stringsAsFactors = FALSE
  )
}

.crm70k_render_km <- function(d, surv_form, group_var, palette, legend_labs, legend_title,
                              km_xlab, km_ylab, risk_tbl, conf_int, plot_w, plot_h,
                              out_path, title_txt, font_family, weight_col = NULL,
                              pval_arg = TRUE, xlim_max = 160) {
  .make_fit <- function() {
    if (requireNamespace("survminer", quietly = TRUE)) {
      # survminer::surv_fit 保留公式，避免 ggsurvplot 内部取 call$formula/data 时
      # 报 "object of type 'symbol' is not subsettable"
      if (!is.null(weight_col) && weight_col %in% names(d)) {
        return(survminer::surv_fit(surv_form, data = d, weights = d[[weight_col]]))
      }
      return(survminer::surv_fit(surv_form, data = d))
    }
    if (!is.null(weight_col) && weight_col %in% names(d)) {
      return(survival::survfit(surv_form, data = d, weights = d[[weight_col]]))
    }
    survival::survfit(surv_form, data = d)
  }
  fit <- tryCatch(.make_fit(), error = function(e) NULL)
  if (is.null(fit)) return(FALSE)
  if (is.null(attr(fit, "formula", exact = TRUE))) attr(fit, "formula") <- surv_form

  saved <- FALSE
  xmax <- as.numeric(xlim_max %||% 160)[1L]
  if (!is.finite(xmax) || xmax <= 0) xmax <- 160
  p <- tryCatch(
    if (requireNamespace("survminer", quietly = TRUE)) {
      survminer::ggsurvplot(
        fit, data = d, risk.table = isTRUE(risk_tbl), conf.int = isTRUE(conf_int),
        surv.median.line = "none", xlab = km_xlab, ylab = km_ylab,
        legend.title = legend_title, legend.labs = legend_labs,
        pval = pval_arg, palette = palette,
        xlim = c(0, xmax),
        break.time.by = 40,
        risk.table.height = 0.28,
        ggtheme = ggplot2::theme_classic(base_size = 12)
      )
    } else NULL,
    error = function(e) {
      cli::cli_alert_warning("crm_nhanes_km_pub ggsurvplot 构建失败: {e$message}")
      NULL
    }
  )
  if (!is.null(p)) {
    # 强制坐标范围，避免风险表最右列被裁切
    p$plot <- p$plot +
      ggplot2::coord_cartesian(xlim = c(0, xmax), ylim = c(0, 1), expand = FALSE) +
      ggplot2::theme(plot.margin = ggplot2::margin(8, 14, 4, 8))
    if (!is.null(p$table) && isTRUE(risk_tbl)) {
      p$table <- p$table +
        ggplot2::coord_cartesian(xlim = c(0, xmax), expand = FALSE) +
        ggplot2::theme(plot.margin = ggplot2::margin(0, 14, 8, 8))
    }
    # 组装主图 + risk table（避免 print(ggsurvplot) / arrange_ggsurvplot 在部分设备上出空白页）
    comb <- tryCatch({
      if (!is.null(p$table) && isTRUE(risk_tbl)) {
        if (requireNamespace("cowplot", quietly = TRUE)) {
          cowplot::plot_grid(p$plot, p$table, ncol = 1, align = "v", axis = "lr",
                             rel_heights = c(2.2, 1))
        } else if (requireNamespace("patchwork", quietly = TRUE)) {
          p$plot / p$table + patchwork::plot_layout(heights = c(2.2, 1))
        } else if (requireNamespace("gridExtra", quietly = TRUE)) {
          gridExtra::arrangeGrob(p$plot, p$table, nrow = 2, heights = c(2.2, 1))
        } else {
          p$plot
        }
      } else {
        p$plot
      }
    }, error = function(e) p$plot)

    for (fam in unique(c(font_family, "sans", "serif"))) {
      ok <- tryCatch({
        if (file.exists(out_path)) unlink(out_path)
        if (grepl("\\.png$", out_path, ignore.case = TRUE)) {
          ggplot2::ggsave(out_path, comb, width = plot_w, height = plot_h, dpi = 300)
        } else {
          ggplot2::ggsave(out_path, comb, width = plot_w, height = plot_h,
                          device = grDevices::cairo_pdf)
        }
        .crm70k_file_ok(out_path)
      }, error = function(e) {
        cli::cli_alert_warning("crm_nhanes_km_pub 出图失败({fam}): {conditionMessage(e)}")
        FALSE
      })
      if (isTRUE(ok)) { saved <- TRUE; break }
    }
  }
  if (!saved) {
    ok <- tryCatch({
      if (file.exists(out_path)) unlink(out_path)
      if (grepl("\\.png$", out_path, ignore.case = TRUE)) {
        grDevices::png(out_path, width = plot_w * 200, height = plot_h * 200, res = 200)
      } else {
        grDevices::pdf(out_path, width = plot_w, height = plot_h)
      }
      plot(fit, col = palette, xlab = km_xlab, ylab = km_ylab, main = title_txt,
          conf.int = isTRUE(conf_int))
      graphics::legend("bottomleft", legend = legend_labs, col = palette, lty = 1, bty = "n",
                       title = legend_title)
      grDevices::dev.off()
      .crm70k_file_ok(out_path)
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      FALSE
    })
    if (isTRUE(ok)) saved <- TRUE
  }
  saved
}

block_crm_nhanes_km_pub <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    if (requireNamespace("survminer", quietly = TRUE)) library(survminer)
    library(cli)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_km_pub %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70k_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70k_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_km_pub: 无分析数据。", call. = FALSE)
  }

  tvar <- as.character(bl_cfg$time_var %||% "futime")[1L]
  yvar <- as.character(bl_cfg$event_var %||% "fustatus")[1L]
  gvar <- as.character(bl_cfg$group_var %||% "CRM_count")[1L]
  sua_col <- as.character(bl_cfg$sua_col %||% "SUA")[1L]
  elig_col <- as.character(bl_cfg$eligibility_col %||% "eligstat")[1L]
  weighted <- isTRUE(bl_cfg$weighted %||% FALSE)
  weight_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]

  need <- unique(c(tvar, yvar, gvar))
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    msg <- paste0("crm_nhanes_km_pub: 数据缺少列: ", paste(miss, collapse = ", "))
    if (.crm70k_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70k_pause(ctx, msg, "检查 crm_nhanes_derive 是否已运行。", data)
    }
    stop(msg, call. = FALSE)
  }
  if (isTRUE(weighted) && !weight_col %in% names(data)) {
    cli::cli_alert_warning("crm_nhanes_km_pub: weighted=TRUE 但权重列 {weight_col} 不存在，回退未加权 KM。")
    weighted <- FALSE
  }

  keep_cols <- unique(c(need, sua_col, elig_col, if (isTRUE(weighted)) weight_col else NULL))
  keep_cols <- intersect(keep_cols, names(data))
  d <- data[, keep_cols, drop = FALSE]

  # 分析队列与 flowchart 最终分析集一致：SUA 非缺失 → 死亡随访合格 → CRM_count/随访列完整
  if (sua_col %in% names(d)) {
    d <- d[!is.na(d[[sua_col]]), , drop = FALSE]
  }
  if (elig_col %in% names(data)) {
    d <- d[d[[elig_col]] %in% c(1, "1"), , drop = FALSE]
  }

  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  if (isTRUE(weighted)) d[[weight_col]] <- suppressWarnings(as.numeric(d[[weight_col]]))

  if (!elig_col %in% names(data)) {
    keep_fu <- !is.na(d[[tvar]]) & !is.na(d[[yvar]]) &
      is.finite(d[[tvar]]) & d[[tvar]] >= 0
    keep_fu[is.na(keep_fu)] <- FALSE
    d <- d[keep_fu, , drop = FALSE]
  }

  d <- d[is.finite(d[[tvar]]) & d[[tvar]] >= 0 & !is.na(d[[yvar]]) & !is.na(d[[gvar]]), , drop = FALSE]
  if (isTRUE(weighted)) d <- d[is.finite(d[[weight_col]]), , drop = FALSE]

  # 强制 0–3 四档（对齐原文 Non-CRM / 1 / 2 / 3 CRM）；缺失档仍保留在因子水平中
  force_lv <- bl_cfg$force_levels %||% c(0, 1, 2, 3)
  force_lv <- as.character(force_lv)
  d$Group <- factor(as.character(d[[gvar]]), levels = force_lv)

  if (!nrow(d) || sum(table(d$Group) > 0) < 2L) {
    msg <- "crm_nhanes_km_pub: 有效数据不足或分组变量水平不足 2 个。"
    if (.crm70k_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70k_pause(ctx, msg, "检查 CRM_count 分布与生存列缺失情况。", d)
    }
    stop(msg, call. = FALSE)
  }

  lvls <- levels(d$Group)
  default_labs <- c("0" = "Non-CRM", "1" = "1 CRM", "2" = "2 CRM", "3" = "3 CRM")
  group_labels <- bl_cfg$group_labels
  if (is.null(group_labels) || length(group_labels) != length(lvls)) {
    group_labels <- unname(ifelse(lvls %in% names(default_labs), default_labs[lvls], paste0("CRM ", lvls)))
  }
  levels(d$Group) <- group_labels

  # 统一配色库（config$km / bl_cfg$palette 可覆盖）
  default_palette <- block_default_palette(max(6L, length(lvls)), cfg)
  palette <- as.character(bl_cfg$palette %||% default_palette)
  if (length(palette) < length(lvls)) palette <- rep(palette, length.out = length(lvls))
  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else {
    "serif"
  }

  km_xlab <- as.character(bl_cfg$xlab %||% "Time")[1L]
  km_ylab <- as.character(bl_cfg$ylab %||% "Survival probability")[1L]
  plot_w <- as.numeric(bl_cfg$plot_width %||% 8)[1L]
  plot_h <- as.numeric(bl_cfg$plot_height %||% 7.2)[1L]
  risk_tbl <- isTRUE(bl_cfg$risk_table %||% FALSE)  # 原文 Figure 1 无 risk table
  conf_int <- isTRUE(bl_cfg$conf_int %||% TRUE)
  write_png <- isTRUE(bl_cfg$write_png %||% FALSE)
  # 原文 Figure 1 横轴约至 160；避免随访更长时右侧裁切/溢出
  xlim_max <- as.numeric(bl_cfg$xlim_max %||% 160)[1L]
  surv_form <- stats::as.formula(paste0("Surv(", tvar, ", ", yvar, ") ~ Group"))

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)

  fig_base <- as.character(
    bl_cfg$figure_basename %||%
      "Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count"
  )[1L]
  fig_caption <- as.character(bl_cfg$figure_caption %||%
    "Kaplan-Meier survival curve for all-cause mortality by CRM conditions (NHANES)")[1L]
  pdf_path <- file.path(fig_dir, paste0(fig_base, ".pdf"))
  png_path <- file.path(fig_dir, paste0(fig_base, ".png"))

  cli::cli_alert_info(
    "KM 分组 n: {paste(paste0(group_labels, '=', as.integer(table(d$Group))), collapse = ', ')}"
  )
  # 注意（加权 KM 的 P 值口径，Task 3 fix）：survminer::ggsurvplot(pval=TRUE) 与下方
  # survival::survdiff() 内部均为未加权 log-rank 检验——即便 weighted=TRUE 时
  # survfit()/coxph() 已按 weight_col 加权拟合曲线/HR，log-rank 检验本身并不支持
  # survey 加权（本仓库未使用 svykm/svylogrank）。因此 weighted=TRUE 时改为在图上
  # 显示明确标注"Unweighted log-rank"的自定义文字（而不是 pval=TRUE 让人误以为
  # 该 P 值也是加权口径）；weighted=FALSE（默认）时行为不变，仍显示常规 pval=TRUE。
  logrank_p <- tryCatch({
    sd <- survival::survdiff(surv_form, data = d)
    1 - stats::pchisq(sd$chisq, length(sd$n) - 1L)
  }, error = function(e) NA_real_)

  show_weighted_pval_label <- isTRUE(bl_cfg$weighted_pval_label %||% TRUE)
  pval_arg <- if (isTRUE(weighted)) {
    if (isTRUE(show_weighted_pval_label)) {
      paste0("Unweighted log-rank P = ", pub_format_p(logrank_p), "\n(weights unused for p)")
    } else {
      FALSE
    }
  } else {
    TRUE
  }

  saved_pdf <- .crm70k_render_km(
    d, surv_form, "Group", palette, group_labels, "CRM", km_xlab, km_ylab,
    risk_tbl, conf_int, plot_w, plot_h, pdf_path, paste0("Figure 1. ", fig_caption),
    font_family, weight_col = if (isTRUE(weighted)) weight_col else NULL,
    pval_arg = pval_arg, xlim_max = xlim_max
  )
  saved_png <- FALSE
  if (isTRUE(write_png)) {
    saved_png <- .crm70k_render_km(
      d, surv_form, "Group", palette, group_labels, "CRM", km_xlab, km_ylab,
      risk_tbl, conf_int, plot_w, plot_h, png_path, paste0("Figure 1. ", fig_caption),
      font_family, weight_col = if (isTRUE(weighted)) weight_col else NULL,
      pval_arg = pval_arg, xlim_max = xlim_max
    )
  } else if (file.exists(png_path)) {
    unlink(png_path)
  }

  if (isTRUE(saved_pdf) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, pdf_path)
  }
  if (isTRUE(saved_png) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, png_path)
  }

  hr_tab <- tryCatch(
    .crm70k_cox_hr(d, tvar, yvar, "Group", weight_col = if (isTRUE(weighted)) weight_col else NULL),
    error = function(e) NULL
  )
  if (!is.null(hr_tab)) {
    hr_tab$P <- pub_format_p(hr_tab$P)
    hr_tab$Analysis <- if (isTRUE(weighted)) "Weighted Cox" else "Unweighted Cox"
    tbl_fn <- as.character(
      bl_cfg$hr_table_filename %||% "Table 1-NHANES-KM_Cox_HR_by_CRM_count.csv"
    )[1L]
    tbl_path <- file.path(tbl_dir, tbl_fn)
    tryCatch(
      utils::write.csv(hr_tab, tbl_path, row.names = FALSE),
      error = function(e) cli::cli_alert_warning("crm_nhanes_km_pub Cox HR 表写出失败: {e$message}")
    )
    if (exists("mirror_pub_output_to_root", mode = "function")) {
      mirror_pub_output_to_root(ctx, tbl_path)
    }
  } else {
    tbl_path <- NA_character_
    cli::cli_alert_warning("crm_nhanes_km_pub: Cox HR 拟合失败，仅补充证据缺失，不影响 KM 图产出。")
  }

  # 补充：痛风分层 KM（仅当显式开启且数据确有 gout 列时才产出；不臆造缺失痛风数据）
  gout_saved <- NA
  if (isTRUE(bl_cfg$stratify_by_gout %||% FALSE) && "gout" %in% names(data)) {
    dg <- data[, intersect(unique(c(need, sua_col, elig_col, "gout")), names(data)), drop = FALSE]
    if (sua_col %in% names(dg)) {
      dg <- dg[!is.na(dg[[sua_col]]), , drop = FALSE]
    }
    if (elig_col %in% names(data)) {
      dg <- dg[dg[[elig_col]] %in% c(1, "1"), , drop = FALSE]
    }
    dg[[tvar]] <- suppressWarnings(as.numeric(dg[[tvar]]))
    dg[[yvar]] <- suppressWarnings(as.numeric(dg[[yvar]]))
    if (!elig_col %in% names(data)) {
      keep_fu <- !is.na(dg[[tvar]]) & !is.na(dg[[yvar]]) &
        is.finite(dg[[tvar]]) & dg[[tvar]] >= 0
      keep_fu[is.na(keep_fu)] <- FALSE
      dg <- dg[keep_fu, , drop = FALSE]
    }
    dg <- dg[is.finite(dg[[tvar]]) & dg[[tvar]] >= 0 & !is.na(dg[[yvar]]) &
               !is.na(dg[[gvar]]) & !is.na(dg$gout), , drop = FALSE]
    dg$Group <- factor(ifelse(dg$gout == 1L, "Gout", "No gout"))
    if (nrow(dg) && nlevels(dg$Group) >= 2L) {
      gout_form <- stats::as.formula(paste0("Surv(", tvar, ", ", yvar, ") ~ Group"))
      gout_path <- file.path(fig_dir, paste0(fig_base, "_gout.pdf"))
      gout_saved <- .crm70k_render_km(
        dg, gout_form, "Group", palette[1:2], levels(dg$Group), "Gout",
        km_xlab, km_ylab, risk_tbl, conf_int, plot_w, plot_h, gout_path,
        "Figure 1 (supp). KM by gout status", font_family, weight_col = NULL
      )
      if (isTRUE(gout_saved) && exists("mirror_pub_output_to_root", mode = "function")) {
        mirror_pub_output_to_root(ctx, gout_path)
      }
    }
  }

  if (!isTRUE(saved_pdf) && !isTRUE(saved_png) &&
      .crm70k_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .crm70k_pause(ctx, "crm_nhanes_km_pub 未能生成 KM 图 PDF/PNG。",
                 "检查 survival/survminer 是否可用及数据有效性。", d)
  }

  ctx$results$crm_nhanes_km_pub <- list(
    group_var = gvar,
    weighted = weighted,
    logrank_p = logrank_p,
    logrank_p_is_weighted = FALSE,  # log-rank 检验始终未加权（见上方说明），与 weighted 开关无关
    logrank_p_note = if (isTRUE(weighted)) {
      "weighted=TRUE：曲线/Cox 已加权，但此 log-rank P 为未加权口径（weights unused for p）"
    } else {
      "weighted=FALSE：曲线与 log-rank P 均为未加权口径"
    },
    plot_pval_label = if (is.character(pval_arg)) pval_arg else NA_character_,
    hr_table = hr_tab,
    figure_pdf = if (isTRUE(saved_pdf)) pdf_path else NA_character_,
    figure_png = if (isTRUE(saved_png)) png_path else NA_character_,
    gout_supplement_saved = gout_saved,
    n = nrow(d)
  )
  cli::cli_alert_success(paste0(
    "crm_nhanes_km_pub 完成（n={nrow(d)}, groups={length(lvls)}, weighted={weighted}, ",
    "logrank P={pub_format_p(logrank_p)} [always unweighted]）"
  ))
  ctx
}

register_block(
  "crm_nhanes_km_pub",
  block_crm_nhanes_km_pub,
  "NHANES 全因死亡 Kaplan-Meier 曲线（Figure 1）"
)
