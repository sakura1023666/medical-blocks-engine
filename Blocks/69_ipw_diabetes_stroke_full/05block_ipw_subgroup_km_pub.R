###############################################################################
#  ipw_subgroup_km_pub — 年龄分层两联 KM（对应文献 Figure 4；格式对齐 Figure 2）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$iptw_weighted（须先 iptw_balance）
#  依赖: 03block_ipw_weighted_km_pub.R 中 .wkm03_* 绘图工具（同模块已 source）
#
#  ipw_subgroup_km_pub = list(
#    stratum_var     = "Age",          # 分层变量（默认 Age）
#    age_cutoff      = 65,             # 年龄二分阈值
#    level_low_label  = "< 65",
#    level_high_label = "\u2265 65",
#    weight_col       = NULL,          # NULL → ctx$results$iptw_weight_col
#    # 以下绘图参数默认与 ipw_weighted_km_pub（Fig2）对齐
#    legend_title = "Diabetes",
#    level_low = "No", level_high = "Yes",
#    legend_inset = c(0.98, 0.98),
#    palette = c("#377EB8", "#E41A1C"),
#    xlim = c(0, 28), ylim = c(0.28, 1.00),
#    break_time_by = 7,
#    landmark_day = 28,
#    risk_table = TRUE,
#    figure_number = 4,
#    figure_caption = "Subgroup Kaplan\u2013Meier curves of 28-day mortality by age",
#    pause_enable = FALSE
#  )
#
#  register_block: "ipw_subgroup_km_pub"
#  产出: [main_figure] Figure 4 两联 KM（左 <65 / 右 ≥65）
#        [固定名] Table_IPW_Subgroup_KM_HR.csv
###############################################################################

.skm05_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.skm05_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_subgroup_km_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_subgroup_km_pub halted. See ctx$results$pause_point. / ",
    "亚组 KM 异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.skm05_pdf_ok <- function(path) {
  fi <- tryCatch(file.info(path), error = function(e) NULL)
  !is.null(fi) && isTRUE(nrow(fi) == 1L) && !is.na(fi$size) && fi$size > 10L
}

.skm05_ensure_fig2_helpers <- function() {
  need <- c(
    ".wkm03_build_ggsurv", ".wkm03_combine_plot_table",
    ".wkm03_ipw_logrank_p", ".wkm03_landmark_surv", ".wkm03_cox_hr"
  )
  if (all(vapply(need, exists, logical(1), mode = "function", inherits = TRUE))) {
    return(invisible(TRUE))
  }
  root <- getwd()
  f <- file.path(root, "Blocks/69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R")
  if (!file.exists(f)) {
    stop("ipw_subgroup_km_pub: 找不到 Fig2 绘图工具文件: ", f, call. = FALSE)
  }
  sys.source(f, envir = .GlobalEnv)
  invisible(TRUE)
}

.skm05_resolve_age_var <- function(bl_cfg, data) {
  av <- as.character(bl_cfg$stratum_var %||% bl_cfg$age_var %||% "Age")[1L]
  if (nzchar(av) && av %in% names(data)) return(av)
  for (cand in c("Age", "age", "AGE")) {
    if (cand %in% names(data)) return(cand)
  }
  NA_character_
}

# 单层：Fig2 同构 KM（加权曲线 + 未加权风险表 + 注释）
.skm05_one_panel <- function(sub, panel_title, bl_cfg, km_cfg,
                             tvar, yvar, weight_col, has_weight,
                             palette, font_family, legend_title, legend_labs) {
  surv_form <- stats::as.formula("Surv(surv_time_use, surv_event_use) ~ Group")
  # 局部列名，避免与全局冲突
  sub$surv_time_use <- sub[[tvar]]
  sub$surv_event_use <- sub[[yvar]]
  .make_fit <- function(use_w) {
    if (requireNamespace("survminer", quietly = TRUE)) {
      if (isTRUE(use_w) && has_weight) {
        return(survminer::surv_fit(surv_form, data = sub, weights = sub[[weight_col]]))
      }
      return(survminer::surv_fit(surv_form, data = sub))
    }
    if (isTRUE(use_w) && has_weight) {
      return(survival::survfit(surv_form, data = sub, weights = sub[[weight_col]]))
    }
    survival::survfit(surv_form, data = sub)
  }
  fit <- .make_fit(TRUE)
  fit_risk <- .make_fit(FALSE)
  if (is.null(attr(fit, "formula", exact = TRUE))) attr(fit, "formula") <- surv_form
  if (is.null(attr(fit_risk, "formula", exact = TRUE))) attr(fit_risk, "formula") <- surv_form

  km_xlim <- km_cfg$xlim %||% c(0, 28)
  km_break <- km_cfg$break_time_by %||% 7
  landmark <- as.numeric(km_cfg$landmark_day %||% km_xlim[2L])[1L]
  if (!is.finite(landmark)) landmark <- 28

  if (has_weight) {
    lr <- .wkm03_ipw_logrank_p(sub, "surv_time_use", "surv_event_use", "Group", weight_col)
    pf <- pub_format_p(lr$p)
    p_lab <- if (grepl("^[<>]", pf)) {
      sprintf("%s P%s", lr$method, pf)
    } else {
      sprintf("%s P=%s", lr$method, pf)
    }
    rate_hdr <- sprintf("Weighted %s-day survival rate", as.integer(landmark))
  } else {
    sd <- tryCatch(survival::survdiff(surv_form, data = sub), error = function(e) NULL)
    p_uw <- if (!is.null(sd)) 1 - stats::pchisq(sd$chisq, length(sd$n) - 1L) else NA_real_
    pf <- pub_format_p(p_uw)
    p_lab <- if (grepl("^[<>]", pf)) sprintf("Log-rank P%s", pf) else sprintf("Log-rank P=%s", pf)
    rate_hdr <- sprintf("Unweighted %s-day survival rate", as.integer(landmark))
  }
  rate_lines <- .wkm03_landmark_surv(fit, landmark, legend_labs)
  annot <- c(rate_hdr, rate_lines)

  p <- .wkm03_build_ggsurv(
    fit, sub, km_cfg, palette, font_family,
    km_xlim, km_break,
    km_cfg$xlab %||% "Follow-up time (days)",
    km_cfg$ylab %||% "Survival Probability",
    legend_title, legend_labs,
    risk_tbl = isTRUE(km_cfg$risk_table %||% TRUE),
    conf_int = isTRUE(km_cfg$conf_int %||% TRUE),
    p_label = p_lab, annot_lines = annot,
    fit_risk = fit_risk
  )
  if (!is.null(p$plot)) {
    p$plot <- p$plot + ggplot2::ggtitle(panel_title) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0.5)
      )
  }
  .wkm03_combine_plot_table(p, km_cfg)
}

block_ipw_subgroup_km_pub <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
    if (requireNamespace("survminer", quietly = TRUE)) library(survminer)
    if (requireNamespace("ggplot2", quietly = TRUE)) library(ggplot2)
    library(cli)
  })
  .skm05_ensure_fig2_helpers()

  cfg <- ctx$config
  bl_cfg <- cfg$ipw_subgroup_km_pub %||% list()
  ipw_cfg <- cfg$ipw_diabetes %||% list()
  # 绘图默认对齐 Fig2；本块覆盖可写在 ipw_subgroup_km_pub
  km_cfg <- modifyList(cfg$ipw_weighted_km_pub %||% list(), bl_cfg)

  data <- ctx$data$iptw_weighted %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.skm05_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .skm05_pause(ctx, "未找到分析数据（iptw_weighted / imputed / cleaned 均为空）。",
                  "请先运行 imputation / iptw_balance。", NULL)
    }
    stop("ipw_subgroup_km_pub: 无分析数据。", call. = FALSE)
  }

  exp_var <- as.character(ipw_cfg$exposure_var %||% cfg$iptw_balance$exposure_var %||% "Diabetes_HbA1c")[1L]
  tvar <- as.character(ipw_cfg$time_var %||% cfg$survival$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(ipw_cfg$event_var %||% cfg$survival$event_var %||% "surv_event_28d")[1L]
  weight_col <- as.character(bl_cfg$weight_col %||% ctx$results$iptw_weight_col %||% "weight")[1L]
  has_weight <- weight_col %in% names(data)

  age_var <- .skm05_resolve_age_var(bl_cfg, data)
  if (is.na(age_var)) {
    msg <- "ipw_subgroup_km_pub: 未找到年龄列（config$ipw_subgroup_km_pub$stratum_var / Age）。"
    if (.skm05_should_pause(bl_cfg, "pause_on_missing_stratum_var", TRUE)) {
      .skm05_pause(ctx, msg, "在 config$ipw_subgroup_km_pub$stratum_var 设置年龄列名。", data)
    }
    stop(msg, call. = FALSE)
  }

  age_cut <- suppressWarnings(as.numeric(bl_cfg$age_cutoff %||%
    (cfg$subgroup_iptw_weighted %||% list())$age_cutoff %||% 65))[1L]
  if (!is.finite(age_cut)) age_cut <- 65
  lbl_lo <- as.character(bl_cfg$level_low_label %||% paste0("< ", age_cut))[1L]
  lbl_hi <- as.character(bl_cfg$level_high_label %||% paste0("\u2265 ", age_cut))[1L]

  need <- unique(c(tvar, yvar, exp_var, age_var))
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    msg <- paste0("ipw_subgroup_km_pub: 数据缺少列: ", paste(miss, collapse = ", "))
    if (.skm05_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .skm05_pause(ctx, msg, "检查 ipw_diabetes_exposure / iptw_balance。", data)
    }
    stop(msg, call. = FALSE)
  }

  keep_cols <- unique(c(need, if (has_weight) weight_col else NULL))
  d <- data[, keep_cols, drop = FALSE]
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  d[[exp_var]] <- suppressWarnings(as.numeric(d[[exp_var]]))
  d$.age_num <- suppressWarnings(as.numeric(d[[age_var]]))
  if (has_weight) d[[weight_col]] <- suppressWarnings(as.numeric(d[[weight_col]]))
  d <- d[is.finite(d[[tvar]]) & d[[tvar]] >= 0 & !is.na(d[[yvar]]) &
           !is.na(d[[exp_var]]) & is.finite(d$.age_num), , drop = FALSE]
  if (has_weight) d <- d[is.finite(d[[weight_col]]), , drop = FALSE]

  if (!nrow(d)) {
    msg <- "ipw_subgroup_km_pub: 年龄/生存列过滤后无有效样本。"
    if (.skm05_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .skm05_pause(ctx, msg, "检查 Age 缺失比例。", data)
    }
    stop(msg, call. = FALSE)
  }

  d$Stratum_Group <- factor(
    ifelse(d$.age_num >= age_cut, lbl_hi, lbl_lo),
    levels = c(lbl_lo, lbl_hi)
  )
  legend_labs <- c(
    as.character(km_cfg$level_low %||% "No")[1L],
    as.character(km_cfg$level_high %||% "Yes")[1L]
  )
  legend_title <- as.character(km_cfg$legend_title %||% "Diabetes")[1L]
  d$Group <- factor(
    ifelse(d[[exp_var]] == 1L, legend_labs[2L], legend_labs[1L]),
    levels = legend_labs
  )
  d <- d[!is.na(d$Group) & !is.na(d$Stratum_Group), , drop = FALSE]

  stratum_levels <- levels(d$Stratum_Group)
  tab_n <- table(d$Stratum_Group)
  if (length(stratum_levels) < 2L || any(tab_n < 2L)) {
    msg <- sprintf(
      "ipw_subgroup_km_pub: 年龄二分（cutoff=%s）后某层样本不足: %s",
      age_cut, paste(names(tab_n), "=", as.integer(tab_n), collapse = ", ")
    )
    if (.skm05_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .skm05_pause(ctx, msg, "检查 Age 分布或调整 age_cutoff。", d)
    }
    stop(msg, call. = FALSE)
  }

  .cox_hr_one <- function(sub) {
    form <- stats::as.formula(paste0("survival::Surv(", tvar, ", ", yvar, ") ~ Group"))
    fit <- tryCatch({
      if (has_weight) survival::coxph(form, data = sub, weights = sub[[weight_col]], robust = TRUE)
      else survival::coxph(form, data = sub)
    }, error = function(e) NULL)
    if (is.null(fit) || length(unique(sub$Group)) < 2L) {
      return(list(hr = NA_real_, lower = NA_real_, upper = NA_real_, p = NA_real_,
                  n = nrow(sub), n_event = sum(sub[[yvar]] == 1, na.rm = TRUE)))
    }
    s <- summary(fit)
    ci <- s$conf.int
    coefs <- s$coefficients
    p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
    list(
      hr = unname(ci[1L, "exp(coef)"]), lower = unname(ci[1L, grep("lower", colnames(ci))[1L]]),
      upper = unname(ci[1L, grep("upper", colnames(ci))[1L]]), p = unname(coefs[1L, p_col]),
      n = fit$n, n_event = fit$nevent
    )
  }

  by_stratum <- lapply(stratum_levels, function(l) {
    .cox_hr_one(d[d$Stratum_Group == l, , drop = FALSE])
  })
  names(by_stratum) <- stratum_levels

  inter_form <- stats::as.formula(
    paste0("survival::Surv(", tvar, ", ", yvar, ") ~ Group * Stratum_Group")
  )
  fit_inter <- tryCatch({
    if (has_weight) survival::coxph(inter_form, data = d, weights = d[[weight_col]], robust = TRUE)
    else survival::coxph(inter_form, data = d)
  }, error = function(e) NULL)
  p_inter <- NA_real_
  if (!is.null(fit_inter)) {
    coefs_i <- summary(fit_inter)$coefficients
    hit <- grep(":", rownames(coefs_i), fixed = TRUE)
    if (length(hit)) {
      p_col_i <- if ("Pr(>|z|)" %in% colnames(coefs_i)) "Pr(>|z|)" else colnames(coefs_i)[ncol(coefs_i)]
      p_inter <- unname(coefs_i[hit[1L], p_col_i])
    }
  }

  hr_tab <- do.call(rbind, lapply(stratum_levels, function(l) {
    r <- by_stratum[[l]]
    data.frame(
      Stratum = l, N = r$n, Events = r$n_event, HR = r$hr,
      Lower95 = r$lower, Upper95 = r$upper, P = pub_format_p(r$p),
      P_interaction = "", stringsAsFactors = FALSE
    )
  }))
  hr_tab$P_interaction[1L] <- pub_format_p(p_inter)

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_IPW_Subgroup_KM_HR.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(hr_tab, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("亚组 KM HR 表写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    try(mirror_pub_output_to_root(ctx, tbl_path), silent = TRUE)
  }

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  palette <- km_cfg$palette %||% block_default_palette(2L, cfg)
  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else {
    "sans"
  }
  fig_cap <- as.character(bl_cfg$figure_caption %||%
    sprintf("Subgroup Kaplan\u2013Meier curves of 28-day mortality by age (cutoff %s)", age_cut))[1L]
  fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% 4L))[1L]
  fig_path <- if (exists("pub_figure_filepath_at", mode = "function") && is.finite(fig_no) && fig_no >= 1L) {
    pub_figure_filepath_at(fig_dir, fig_no, fig_cap, ext = "pdf", bump_counter = TRUE)
  } else {
    file.path(fig_dir, pub_figure_file(ctx, "main_figure", fig_cap))
  }

  panel_titles <- paste0(stratum_levels, " years")
  # 避免 "≥ 65 years" 重复；若标签已含 years 则不加
  panel_titles <- vapply(stratum_levels, function(l) {
    if (grepl("year", l, ignore.case = TRUE)) l else paste0("Age ", l)
  }, character(1))

  grobs <- lapply(seq_along(stratum_levels), function(i) {
    l <- stratum_levels[i]
    sub <- d[d$Stratum_Group == l, , drop = FALSE]
    tryCatch(
      .skm05_one_panel(
        sub, panel_titles[i], bl_cfg, km_cfg,
        tvar, yvar, weight_col, has_weight,
        palette, font_family, legend_title, legend_labs
      ),
      error = function(e) {
        cli::cli_alert_warning("亚组面板 '{l}' 构建失败: {e$message}")
        NULL
      }
    )
  })

  plot_w <- as.numeric(bl_cfg$plot_width %||% 14)[1L]
  plot_h <- as.numeric(bl_cfg$plot_height %||% 7.2)[1L]
  saved <- FALSE
  if (all(!vapply(grobs, is.null, logical(1L)))) {
    comb <- if (requireNamespace("cowplot", quietly = TRUE)) {
      cowplot::plot_grid(plotlist = grobs, ncol = 2L, align = "h", axis = "tb")
    } else if (requireNamespace("gridExtra", quietly = TRUE)) {
      gridExtra::arrangeGrob(grobs = grobs, ncol = 2L)
    } else {
      NULL
    }
    if (!is.null(comb)) {
      for (fam in unique(c(font_family, "sans", "serif"))) {
        ok <- tryCatch({
          if (file.exists(fig_path)) unlink(fig_path)
          ggplot2::ggsave(
            fig_path, plot = comb, width = plot_w, height = plot_h,
            device = grDevices::cairo_pdf, family = fam
          )
          .skm05_pdf_ok(fig_path)
        }, error = function(e) FALSE)
        if (isTRUE(ok)) { saved <- TRUE; break }
      }
    }
  }

  if (!isTRUE(saved)) {
    # 兜底：基础 graphics 两联
    ok <- tryCatch({
      if (file.exists(fig_path)) unlink(fig_path)
      grDevices::pdf(fig_path, width = plot_w, height = plot_h)
      graphics::par(mfrow = c(1, 2))
      surv_form0 <- stats::as.formula(paste0("Surv(", tvar, ", ", yvar, ") ~ Group"))
      for (i in seq_along(stratum_levels)) {
        sub <- d[d$Stratum_Group == stratum_levels[i], , drop = FALSE]
        fit <- if (has_weight) {
          survival::survfit(surv_form0, data = sub, weights = sub[[weight_col]])
        } else {
          survival::survfit(surv_form0, data = sub)
        }
        plot(fit, col = palette, xlim = km_cfg$xlim %||% c(0, 28),
             xlab = "Follow-up time (days)", ylab = "Survival Probability",
             main = panel_titles[i], conf.int = TRUE)
        graphics::legend("topright", legend = legend_labs, col = palette, lty = 1, bty = "n",
                         title = legend_title)
      }
      grDevices::dev.off()
      .skm05_pdf_ok(fig_path)
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      FALSE
    })
    if (isTRUE(ok)) saved <- TRUE
  }

  if (isTRUE(saved) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, fig_path)
  }
  if (!isTRUE(saved) && .skm05_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .skm05_pause(ctx, "ipw_subgroup_km_pub 未能生成年龄分层两联 KM。",
                "检查 survminer/cowplot 与各层样本量。", d)
  }

  ctx$results$ipw_subgroup_km_pub <- list(
    stratum_var = age_var,
    age_cutoff = age_cut,
    stratum_levels = stratum_levels,
    hr_by_stratum = by_stratum,
    p_interaction = p_inter,
    hr_table = hr_tab,
    figure_path = if (isTRUE(saved)) fig_path else NA_character_,
    n = nrow(d),
    n_by_stratum = as.list(tab_n)
  )
  cli::cli_alert_success(
    "ipw_subgroup_km_pub 完成（Age cutoff={age_cut}; n={paste(names(tab_n), as.integer(tab_n), sep='=', collapse=', ')}; P-inter={pub_format_p(p_inter)}）"
  )
  ctx
}

register_block(
  "ipw_subgroup_km_pub",
  block_ipw_subgroup_km_pub,
  "年龄（65 岁）分层两联 KM，格式对齐 Figure 2（Figure 4）"
)
