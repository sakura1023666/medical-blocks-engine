###############################################################################
#  rcs_iptw_weighted — MIMIC IPTW 加权发病 RCS（C01 rcspline+svyglm；图式对齐 rcs_incidence）。
#
#  register_block: "rcs_iptw_weighted"
#  典型流水线: iptw_balance → logistic_*_iptw_weighted（可选）→ rcs_iptw_weighted
#  依赖: 00logistic_iptw_weighted_common.R（pipeline 自动 source，复用 resolve_models）
#
#  config: config$rcs_iptw_weighted
#  读: ctx$results$iptw_design（须先 iptw_balance）
#  写: ctx$results$rcs_iptw_*、iptw_design_rcs、cutoff_value、<Index>_RCS_Group
#
#  统计（参照 C01_RCS——OR.R）:
#    Hmisc::rcspline.eval + svyglm(quasibinomial) + regTermTest
#    结点默认 unweighted quantile 0.1/0.5/0.9（与 C01 一致）
#
#  出图（参照 02block_rcs_incidence.R / rcs_nhanes）:
#    ggrcs 横排 A/B/C；Model C 竖虚线 cutoff；pub_figure_file main_figure
#
#  NHANES 路径跳过。
###############################################################################

block_rcs_iptw_weighted <- function(ctx, ...) {
  cfg <- ctx$config
  if (!.liw00_should_run(cfg, "rcs_iptw_weighted")) {
    cli::cli_alert_info("rcs_iptw_weighted: 已跳过（NHANES 或 enable=FALSE）。")
    return(ctx)
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% ""))
  if (!identical(study_type, "incidence")) {
    cli::cli_alert_info("rcs_iptw_weighted: study_type 非 incidence，跳过。")
    return(ctx)
  }

  ri_cfg <- cfg$rcs_iptw_weighted %||% list()
  proj_cfg <- cfg$project %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  index_var <- as.character(
    ri_cfg$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% ""
  )[1L]

  design <- .liw00_resolve_design(ctx, cfg)
  if (is.null(design)) {
    msg <- "ctx$results$iptw_design 为空（请先运行 iptw_balance）。"
    if (.liw00_should_pause(ri_cfg, "pause_on_missing_design", TRUE)) {
      .liw00_pause(ctx, "rcs_iptw_weighted", msg, "在 pipeline 中加入 iptw_balance。", NULL)
    }
    stop("rcs_iptw_weighted: ", msg, call. = FALSE)
  }

  if (!nzchar(index_var)) stop("rcs_iptw_weighted: index_var 未设置。", call. = FALSE)
  if (!index_var %in% names(design$variables)) {
    stop("rcs_iptw_weighted: index_var '", index_var, "' 不在 iptw_design 中。", call. = FALSE)
  }
  if (!outcome_col %in% names(design$variables)) {
    stop("rcs_iptw_weighted: outcome '", outcome_col, "' 不在 iptw_design 中。", call. = FALSE)
  }

  wt_col <- ctx$results$iptw_weight_col %||%
    (cfg$iptw_balance %||% list())$weight_col %||% "weight"
  if (!wt_col %in% names(design$variables)) {
    stop("rcs_iptw_weighted: 权重列 '", wt_col, "' 不在 iptw_design 中。", call. = FALSE)
  }

  for (pkg in c("survey", "rms", "ggrcs", "ggplot2", "Hmisc", "scales", "patchwork")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("rcs_iptw_weighted: 需要 ", pkg, " 包。", call. = FALSE)
    }
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(rms)
    library(ggrcs)
    library(ggplot2)
    library(Hmisc, warn.conflicts = FALSE)
    library(scales, warn.conflicts = FALSE)
    library(patchwork, warn.conflicts = FALSE)
  })

  plot_ff <- plot_font_from_config(cfg)

  design <- stats::update(
    design,
    Disease_Group = as.numeric(as.character(design$variables[[outcome_col]]) == as.character(disease_lbl))
  )

  models <- .liw00_resolve_models(ctx, cfg, ri_cfg, design, index_var, extra_excl = character(0))
  M1_vars <- models$M1
  M2_vars <- models$M2
  M3_vars <- if (exists("pipeline_rcs_model3_covs", mode = "function")) {
    pipeline_rcs_model3_covs(ctx, cfg, M2_vars, names(design$variables), index_var)
  } else {
    character(0)
  }
  M3_vars <- intersect(as.character(M3_vars %||% character(0)), names(design$variables))
  if (!length(setdiff(M3_vars, M2_vars))) M3_vars <- character(0)
  m3_sig <- isTRUE(ctx$results$model3_significant)
  if (!length(M1_vars) || !length(M2_vars)) {
    msg <- "Model1/Model2 协变量为空；请先运行 IPTW logistic 或设置 model1_factors。"
    if (.liw00_should_pause(ri_cfg, "pause_on_empty_models", TRUE)) {
      .liw00_pause(ctx, "rcs_iptw_weighted", msg, "检查 ctx$results$Model1Factors。", NULL)
    }
    stop("rcs_iptw_weighted: ", msg, call. = FALSE)
  }

  cli::cli_alert_info("rcs_iptw Model1: {paste(M1_vars, collapse = ', ')}")
  cli::cli_alert_info("rcs_iptw Model2: {paste(M2_vars, collapse = ', ')}")
  if (length(M3_vars)) {
    cli::cli_alert_info("rcs_iptw Model3: {paste(M3_vars, collapse = ', ')}")
  }

  knot_q <- ri_cfg$knot_quantiles %||% c(0.1, 0.5, 0.9)
  use_wt_knots <- isTRUE(ri_cfg$knot_use_weighted_quantile %||% FALSE)
  if (use_wt_knots && exists(".liw00_weighted_quantiles", mode = "function")) {
    knots <- .liw00_weighted_quantiles(design, index_var, knot_q)
  } else {
    knots <- stats::quantile(design$variables[[index_var]], knot_q, na.rm = TRUE)
  }
  knots <- as.numeric(knots)
  if (any(!is.finite(knots))) stop("rcs_iptw_weighted: RCS 结点计算失败。", call. = FALSE)

  n_rcs_cols <- length(knots) - 1L
  bn <- paste0("rcs_b", seq_len(n_rcs_cols))
  cli::cli_alert_info(
    "rcs_iptw knots ({if (use_wt_knots) 'weighted' else 'unweighted'}): ",
    "{paste(round(knots, 3), collapse = ', ')}"
  )

  .riw04_rcspline_basis <- function(x, knots_vec, inclx = TRUE) {
    as.matrix(Hmisc::rcspline.eval(x, knots = knots_vec, inclx = inclx))
  }

  .riw04_fill_pred_covariates <- function(pred_df, des, covs) {
    n <- nrow(pred_df)
    for (v in covs) {
      vd <- des$variables[[v]]
      if (is.numeric(vd)) {
        pred_df[[v]] <- rep(mean(vd, na.rm = TRUE), n)
      } else {
        xf <- if (is.factor(vd)) vd else factor(vd)
        lv <- levels(xf)[1L]
        pred_df[[v]] <- factor(rep(lv, n), levels = levels(xf))
      }
    }
    pred_df
  }

  .riw04_rebuild_design <- function(des, new_df) {
    survey::svydesign(
      ids = ~1,
      data = new_df,
      weights = stats::as.formula(paste0("~", wt_col))
    )
  }

  .riw04_get_rcs <- function(des, covs) {
    covs <- as.character(covs %||% character(0))
    covs <- covs[nzchar(covs)]
    basis <- .riw04_rcspline_basis(des$variables[[index_var]], knots, inclx = TRUE)
    colnames(basis) <- bn
    new_df <- cbind(as.data.frame(des$variables), as.data.frame(basis))
    tmp <- .riw04_rebuild_design(des, new_df)

    fml <- stats::as.formula(paste0(
      "Disease_Group ~ ", paste(bn, collapse = "+"),
      if (length(covs)) paste0(" + ", paste(covs, collapse = "+")) else ""
    ))
    fit <- tryCatch(
      survey::svyglm(fml, design = tmp, family = stats::quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)

    p_ov <- tryCatch(survey::regTermTest(fit, bn)$p, error = function(e) NA_real_)
    p_nl <- tryCatch(
      if (length(bn) > 1L) survey::regTermTest(fit, bn[-1L])$p else NA_real_,
      error = function(e) NA_real_
    )

    x_rng <- seq(
      min(des$variables[[index_var]], na.rm = TRUE),
      max(des$variables[[index_var]], na.rm = TRUE),
      length.out = 200L
    )
    pred_basis <- .riw04_rcspline_basis(x_rng, knots, inclx = TRUE)
    colnames(pred_basis) <- bn
    pred_df <- data.frame(setNames(list(x_rng), index_var))
    pred_df <- cbind(pred_df, as.data.frame(pred_basis))
    pred_df <- .riw04_fill_pred_covariates(pred_df, des, covs)

    ref_x <- stats::median(des$variables[[index_var]], na.rm = TRUE)
    ref_b <- .riw04_rcspline_basis(ref_x, knots, inclx = TRUE)
    ref_row <- pred_df[1L, , drop = FALSE]
    ref_row[[index_var]] <- ref_x
    ref_row[, bn] <- as.numeric(ref_b)
    ref_row <- .riw04_fill_pred_covariates(ref_row, des, covs)
    newdat_all <- rbind(ref_row, pred_df)

    pred_out <- tryCatch(
      predict(fit, newdata = newdat_all, type = "link", se.fit = TRUE),
      error = function(e) NULL
    )
    if (is.null(pred_out)) return(NULL)
    lv <- as.numeric(pred_out)
    sv <- as.numeric(survey::SE(pred_out))
    rl <- lv[-1L] - lv[1L]
    list(
      res = data.frame(
        x = x_rng,
        yhat = exp(rl),
        lower = exp(rl - 1.96 * sv[-1L]),
        upper = exp(rl + 1.96 * sv[-1L])
      ),
      p_overall = p_ov,
      p_nonlin = p_nl
    )
  }

  .riw04_default_color3 <- function() {
    list(color1 = "#b0d5df", color2 = "#FF9999", color3 = "#FF9933")
  }

  .riw04_resolve_plot_colors <- function() {
    color_cfg <- ri_cfg$pdf_color_config
    if (is.null(color_cfg)) return(.riw04_default_color3())
    if (is.list(color_cfg[[1L]])) {
      set.seed(ri_cfg$color_seed %||% 123)
      picked <- color_cfg[[sample(seq_along(color_cfg), 1L)]]
      return(list(color1 = picked$color1, color2 = picked$color2, color3 = picked$color3))
    }
    color_cfg
  }

  .riw04_cutoffs_from_res <- function(res) {
    if (is.null(res) || is.null(res$res) || !nrow(res$res)) {
      return(list(or1 = numeric(0), slope_zero = numeric(0), peak = numeric(0), all = numeric(0)))
    }
    rcs_find_cutoffs_from_or_curve(res$res$x, res$res$yhat)
  }

  .riw04_ggrcs_panel <- function(data_imp, fit, dl, Index, selected_colors3,
                                 title_label, cutoffs,
                                 histper = 50, histbinwidth = NULL,
                                 show_cutoff_lines = FALSE,
                                 cutoff_label_digits = 2L) {
    if (is.null(fit) || is.null(dl)) return(NULL)
    # ggrcs 默认 P.Nonlinear/lift 会与下方手动 annotate 重复；直方图已 strip
    ggrcs_args <- list(
      data = data_imp,
      fit = fit,
      x = Index,
      histcol = selected_colors3$color1,
      ribcol = scales::alpha(selected_colors3$color2, 0.8),
      linecol = selected_colors3$color3,
      lwd = 1.5,
      xlab = if (exists("pipeline_plot_axis_label", mode = "function")) {
        pipeline_plot_axis_label(Index)
      } else {
        gsub("_", " ", as.character(Index)[1L], fixed = TRUE)
      },
      ylab = "OR(95%CI)",
      fontsize = 12,
      fontfamily = plot_ff,
      px = 1.2,
      py = 4,
      P.Nonlinear = FALSE,
      lift = FALSE
    )
    if (!is.null(histbinwidth) && is.finite(histbinwidth) && histbinwidth > 0) {
      ggrcs_args$histbinwidth <- histbinwidth
    } else {
      ggrcs_args$histper <- histper
    }
    plot_obj <- do.call(ggrcs, ggrcs_args)
    plot_obj <- rcs_ggrcs_strip_histogram_layers(plot_obj)
    y_lim <- rcs_ggrcs_y_limits(plot_obj)
    x_min <- min(data_imp[[Index]], na.rm = TRUE)
    y_top <- y_lim$ymax_plot
    y_step <- y_lim$y_step
    p_ov <- dl$p_overall
    p_nl <- dl$p_nonlin

    plot_obj <- plot_obj +
      ggplot2::geom_hline(
        ggplot2::aes(yintercept = 1),
        linetype = "dashed", linewidth = 0.5, color = "gray50"
      )
    if (isTRUE(show_cutoff_lines)) {
      plot_obj <- rcs_ggrcs_add_cutoff_vlines(
        plot_obj, cutoffs, y_lim, plot_ff,
        label_digits = cutoff_label_digits,
        x_range = range(data_imp[[Index]], na.rm = TRUE),
        fit = fit,
        Index = Index
      )
    }
    plot_obj +
      ggplot2::theme_classic() +
      ggplot2::annotate(
        "text", x = x_min, y = y_top,
        label = paste0(
          "P for overall ",
          ifelse(is.na(p_ov) || round(p_ov, 3) == 0, "< 0.001",
                 paste0("= ", round(p_ov, 3)))
        ),
        family = plot_ff, hjust = 0, vjust = 1
      ) +
      ggplot2::annotate(
        "text", x = x_min, y = y_top - y_step,
        label = paste0(
          "P for nonlinear ",
          ifelse(is.na(p_nl) || round(p_nl, 3) == 0, "< 0.001",
                 paste0("= ", round(p_nl, 3)))
        ),
        family = plot_ff, hjust = 0, vjust = 1
      ) +
      ggplot2::coord_cartesian(ylim = c(y_lim$ymin, y_lim$ymax_plot)) +
      ggplot2::labs(
        title = title_label,
        x = if (exists("pipeline_plot_axis_label", mode = "function")) {
          pipeline_plot_axis_label(Index)
        } else {
          gsub("_", " ", as.character(Index)[1L], fixed = TRUE)
        },
        y = "OR (95%CI)"
      ) +
      ggplot2::theme_bw() +
      ggplot2::theme(
        legend.key = ggplot2::element_blank(),
        text = ggplot2::element_text(family = plot_ff),
        axis.title = ggplot2::element_text(family = plot_ff),
        axis.text = ggplot2::element_text(family = plot_ff),
        legend.text = ggplot2::element_text(family = plot_ff),
        panel.grid.major = ggplot2::element_blank(),
        panel.grid.minor = ggplot2::element_blank()
      )
  }

  .riw04_lrm_plot_data <- function(des, covs) {
    covs <- as.character(covs %||% character(0))
    covs <- covs[nzchar(covs)]
    need <- unique(c(outcome_col, index_var, covs))
    df <- as.data.frame(des$variables[, intersect(need, names(des$variables)), drop = FALSE])
    df <- stats::na.omit(df)
    oc <- df[[outcome_col]]
    if (is.numeric(oc) && all(na.omit(unique(oc)) %in% c(0, 1))) {
      df$Disease <- as.integer(oc)
    } else {
      df$Disease <- ifelse(as.character(oc) == as.character(disease_lbl), 1L, 0L)
    }
    df
  }

  .riw04_fit_lrm_for_plot <- function(data_imp, covs, nk) {
    covs <- intersect(as.character(covs %||% character(0)), names(data_imp))
    covs <- setdiff(covs, index_var)
    fml <- if (!length(covs)) {
      stats::as.formula(paste0("Disease ~ rcs(", index_var, ", ", nk, ")"))
    } else {
      stats::as.formula(paste0(
        "Disease ~ rcs(", index_var, ", ", nk, ")+", paste(covs, collapse = "+")
      ))
    }
    rms::lrm(fml, data = data_imp, x = TRUE, y = TRUE)
  }

  cli::cli_h2("rcs_iptw_weighted: IPTW RCS (C01 svyglm + rcs_incidence ggrcs)")
  resA <- tryCatch(.riw04_get_rcs(design, character(0)), error = function(e) {
    cli::cli_alert_warning("RCS Crude 失败: {e$message}")
    NULL
  })
  resB <- tryCatch(.riw04_get_rcs(design, M1_vars), error = function(e) {
    cli::cli_alert_warning("RCS Model1 失败: {e$message}")
    NULL
  })
  resC <- tryCatch(.riw04_get_rcs(design, M2_vars), error = function(e) {
    cli::cli_alert_warning("RCS Model2 失败: {e$message}")
    NULL
  })
  resD <- if (length(M3_vars)) {
    tryCatch(.riw04_get_rcs(design, M3_vars), error = function(e) {
      cli::cli_alert_warning("RCS Model3 失败: {e$message}")
      NULL
    })
  } else {
    NULL
  }

  cutA <- .riw04_cutoffs_from_res(resA)
  cutB <- .riw04_cutoffs_from_res(resB)
  cutC <- .riw04_cutoffs_from_res(resC)
  cutD <- .riw04_cutoffs_from_res(resD)
  if (!length(cutC$all) && length(cutB$all)) {
    cli::cli_alert_warning("Model2 RCS 无切点，回退使用 Model1 曲线切点。")
    cutC <- cutB
  } else if (!length(cutC$all) && length(cutA$all)) {
    cli::cli_alert_warning("Model2 RCS 无切点，回退使用 Crude 曲线切点。")
    cutC <- cutA
  }
  cut_use <- if (isTRUE(m3_sig) && length(cutD$all)) cutD else cutC
  primary_cutoff <- rcs_primary_cutoff(cut_use)

  plot_colors <- .riw04_resolve_plot_colors()
  histper <- as.numeric(ri_cfg$histper %||% ri_cfg$histbin %||% 50)[1L]
  histbinwidth <- ri_cfg$histbinwidth
  if (!is.null(histbinwidth)) histbinwidth <- as.numeric(histbinwidth)[1L]
  lrm_nk <- as.integer(ri_cfg$lrm_plot_nk %||% length(knot_q))[1L]
  if (!is.finite(lrm_nk) || lrm_nk < 3L) lrm_nk <- 3L
  cutoff_label_digits <- as.integer(ri_cfg$cutoff_label_digits %||% 2L)
  if (!is.finite(cutoff_label_digits) || cutoff_label_digits < 0L) {
    cutoff_label_digits <- 2L
  }

  data_lrm <- .riw04_lrm_plot_data(design, unique(c(M1_vars, M2_vars, M3_vars)))
  assign("dd_rcs_iptw_plot", rms::datadist(data_lrm), envir = .GlobalEnv)
  options(datadist = "dd_rcs_iptw_plot")

  fitA <- tryCatch(.riw04_fit_lrm_for_plot(data_lrm, character(0), lrm_nk), error = function(e) NULL)
  fitB <- tryCatch(.riw04_fit_lrm_for_plot(data_lrm, M1_vars, lrm_nk), error = function(e) NULL)
  fitC <- tryCatch(.riw04_fit_lrm_for_plot(data_lrm, M2_vars, lrm_nk), error = function(e) NULL)
  fitD <- if (length(M3_vars)) {
    tryCatch(.riw04_fit_lrm_for_plot(data_lrm, M3_vars, lrm_nk), error = function(e) NULL)
  } else {
    NULL
  }

  show_cut_c <- !length(M3_vars) || !isTRUE(m3_sig)
  show_cut_d <- length(M3_vars) && isTRUE(m3_sig)
  pA <- if (!is.null(resA) && !is.null(fitA)) {
    .riw04_ggrcs_panel(data_lrm, fitA, resA, index_var, plot_colors, "A.Crude Model", cutA,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = FALSE, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pB <- if (!is.null(resB) && !is.null(fitB)) {
    .riw04_ggrcs_panel(data_lrm, fitB, resB, index_var, plot_colors, "B.Model 1", cutB,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = FALSE, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pC <- if (!is.null(resC) && !is.null(fitC)) {
    .riw04_ggrcs_panel(data_lrm, fitC, resC, index_var, plot_colors, "C.Model 2", cutC,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = show_cut_c, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pD <- if (length(M3_vars) && !is.null(resD) && !is.null(fitD)) {
    .riw04_ggrcs_panel(data_lrm, fitD, resD, index_var, plot_colors, "D.Model 3", cutD,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = show_cut_d, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  panels <- Filter(Negate(is.null), list(pA, pB, pC, pD))

  if (length(panels) == 0L) {
    cli::cli_alert_warning("rcs_iptw_weighted: 未生成有效图面板。")
  } else {
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
    fig_caption <- paste0(
      "IPTW-adjusted RCS of ", gsub("_", " ", index_var, fixed = TRUE),
      " and ", gsub("_", " ", proj_cfg$disease %||% "outcome", fixed = TRUE)
    )
    fig_name <- if (!is.null(ri_cfg$figure_filename) && nzchar(ri_cfg$figure_filename)) {
      ri_cfg$figure_filename
    } else {
      pub_figure_file(ctx, "main_figure", fig_caption)
    }
    fig_path <- file.path(fig_dir, fig_name)
    if (exists(".pub_figure_filename", mode = "function")) {
      fig_path <- file.path(fig_dir, .pub_figure_filename(
        .inject_db_into_pub_label(fig_name, sanitize_for_file = TRUE)
      ))
    }
    tryCatch({
      comb_pack <- if (exists("pipeline_rcs_patchwork", mode = "function")) {
        pipeline_rcs_patchwork(panels)
      } else {
        list(
          plot = Reduce(`+`, panels) + patchwork::plot_layout(nrow = 1),
          width = 15, height = 5
        )
      }
      ggplot2::ggsave(
        filename = fig_path,
        plot = comb_pack$plot,
        width = comb_pack$width,
        height = comb_pack$height,
        device = function(filename, width, height, ...) {
          if (exists("pipeline_pdf_device", mode = "function")) {
            pipeline_pdf_device(filename, width = width, height = height, family = plot_ff)
          } else {
            grDevices::cairo_pdf(filename, width = width, height = height, family = plot_ff)
          }
        }
      )
      cli::cli_alert_success("rcs_iptw 图保存: {.file {basename(fig_path)}}")
      ctx$results$rcs_iptw_figure <- fig_path
      mirror_pub_output_to_root(ctx, fig_path)
    }, error = function(e) {
      cli::cli_alert_warning("rcs_iptw 图保存失败: {e$message}")
    })
  }

  p_table <- data.frame(
    Model = if (length(M3_vars)) c("Crude Model", "Model1", "Model2", "Model3") else c("Crude Model", "Model1", "Model2"),
    P_overall = vapply(
      if (length(M3_vars)) list(resA, resB, resC, resD) else list(resA, resB, resC),
      function(r) {
        if (is.null(r) || is.na(r$p_overall)) "NA"
        else ifelse(r$p_overall < 0.001, "<0.001", sprintf("%.3f", r$p_overall))
      }, character(1)
    ),
    P_nonlinear = vapply(
      if (length(M3_vars)) list(resA, resB, resC, resD) else list(resA, resB, resC),
      function(r) {
        if (is.null(r) || is.na(r$p_nonlin)) "NA"
        else ifelse(r$p_nonlin < 0.001, "<0.001", sprintf("%.3f", r$p_nonlin))
      }, character(1)
    ),
    stringsAsFactors = FALSE
  )

  ctx$results$rcs_iptw <- list(
    crude = resA, model1 = resB, model2 = resC, model3 = resD,
    cutoffs_crude = cutA, cutoffs_model1 = cutB, cutoffs_model2 = cutC,
    cutoffs_model3 = cutD, cutoffs = cut_use,
    primary_cutoff = primary_cutoff,
    p_table = p_table,
    knots = knots
  )
  ctx$results$rcs_iptw_cutoff_or1 <- cut_use$or1
  ctx$results$rcs_iptw_cutoff_slope_zero <- cut_use$peak
  ctx$results$rcs_iptw_cutoffs_all <- cut_use$all
  ctx$results$rcs_iptw_primary_cutoff <- primary_cutoff
  ctx$results$rcs_iptw_cutoff_index <- index_var
  ctx$results$rcs_iptw_model1_factors <- M1_vars
  ctx$results$rcs_iptw_model2_factors <- M2_vars
  ctx$results$rcs_iptw_model3_factors <- M3_vars

  if (!exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    pf_r <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
    if (file.exists(pf_r)) source(pf_r, local = FALSE)
  }
  .riw04_panel_stats <- function(res, cuts = numeric(0)) {
    cuts <- as.numeric(cuts)
    list(
      p_overall = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_overall)[1L]),
      p_nonlinear = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_nonlin)[1L]),
      cutoffs = cuts[is.finite(cuts)]
    )
  }
  # rcs_ggrcs_add_cutoff_vlines 画该面板 cutoffs$all；仅 show_cutoff_lines 的面板写入
  ctx$results$rcs_iptw_panel_stats <- list(
    Crude  = .riw04_panel_stats(resA, numeric(0)),
    Model1 = .riw04_panel_stats(resB, numeric(0)),
    Model2 = .riw04_panel_stats(
      resC, .pub_figure_rcs_panel_vline_cutoffs(cutC, show_cut_c, "all")
    )
  )
  if (length(M3_vars) && !is.null(resD)) {
    ctx$results$rcs_iptw_panel_stats$Model3 <- .riw04_panel_stats(
      resD, .pub_figure_rcs_panel_vline_cutoffs(cutD, show_cut_d, "all")
    )
  }

  ctx$results$rcs_cutoff <- primary_cutoff
  ctx$results$rcs_cutoff_index <- index_var
  ctx$results$rcs_cutoff_or1 <- cut_use$or1
  ctx$results$rcs_cutoff_slope_zero <- cut_use$peak
  ctx$results$rcs_cutoffs_all <- cut_use$all
  ctx$results$cutoff_value <- primary_cutoff
  ctx$results$cutoff_variable <- index_var

  grp_info <- rcs_cutoff_factor(design$variables[[index_var]], cut_use$all, index_var)
  ctx$results$rcs_iptw_group_col <- grp_info$col_name
  ctx$results$rcs_iptw_group_labels <- grp_info$labels
  ctx$results$rcs_cutoff_group_col <- grp_info$col_name

  design_rcs <- do.call(
    stats::update,
    c(list(design), setNames(list(grp_info$factor), grp_info$col_name))
  )
  ctx$results$iptw_design_rcs <- design_rcs

  if (!is.null(ctx$data$iptw_weighted) && is.data.frame(ctx$data$iptw_weighted)) {
    ctx$data$iptw_weighted[[grp_info$col_name]] <- grp_info$factor
  }

  cutoff_vals <- c(cut_use$or1, cut_use$peak)
  cutoff_types <- c(rep("or1", length(cut_use$or1)), rep("peak_or", length(cut_use$peak)))
  if (length(cutoff_vals)) {
    cutoff_detail <- data.frame(
      index = rep(index_var, length(cutoff_vals)),
      type = cutoff_types,
      cutoff = cutoff_vals,
      stringsAsFactors = FALSE
    )
    cutoff_detail <- cutoff_detail[order(cutoff_detail$cutoff), , drop = FALSE]
    ctx <- save_result(
      ctx, "rcs_iptw_cutoff",
      cutoff_detail,
      paste0("cutoff_", index_var, "_rcs_iptw.csv")
    )
  }

  group_counts <- as.data.frame(
    table(grp_info$factor, useNA = "ifany"),
    stringsAsFactors = FALSE
  )
  names(group_counts) <- c("group", "n")
  group_counts$index <- index_var
  group_counts$cutoffs <- if (length(cut_use$all)) {
    paste(rcs_format_cutoff(cut_use$all), collapse = "; ")
  } else "none"
  ctx <- save_result(
    ctx, "rcs_iptw_cutoff_groups",
    group_counts,
    paste0("rcs_cutoff_groups_", index_var, "_iptw.csv")
  )

  or1_txt <- if (length(cut_use$or1)) paste(rcs_format_cutoff(cut_use$or1), collapse = ", ") else "none"
  peak_txt <- if (length(cut_use$peak)) paste(rcs_format_cutoff(cut_use$peak), collapse = ", ") else "none"
  cli::cli_alert_info("Model2 RCS cutoffs — OR=1: {or1_txt}; peak OR: {peak_txt}")
  primary_txt <- if (is.finite(primary_cutoff)) rcs_format_cutoff(primary_cutoff) else "NA"
  cli::cli_alert_success(
    "rcs_iptw_weighted 完成（primary cutoff = {primary_txt}，共 {length(cut_use$all)} 个 cutoff）。"
  )
  ctx
}

register_block(
  "rcs_iptw_weighted",
  block_rcs_iptw_weighted,
  "MIMIC IPTW RCS: C01 svyglm+rcspline stats, rcs_incidence ggrcs ABC figure"
)
