###############################################################################
#  boxplot — 按分组变量绘制连续变量箱线图，并做整体/两两组间检验。
#
#  register_block: "boxplot"
#  典型流水线: baseline 之后（可用 sig_vars 或 survival/logistic 指定指标）
#  源: Blocks/block_boxplot.R（父块保留；Blocks/05_boxplot 为目录化副本）
#
#  输入:
#    ctx$data$imputed（优先）或 ctx$data$cleaned
#    参数可覆盖 config$boxplot / survival / logistic / baseline
#
#  配置 (config$boxplot，均可选):
#    group_var           — 分组列名；缺省顺序: 参数 group_var → boxplot$group_var
#                          → baseline$strata → survival$event_var → data$outcome_column
#    response_vars       — 连续因变量名字符向量；缺省为 survival$index_var 或 logistic$index_var
#    use_continuous_from_baseline — TRUE 时用 ctx$results$continuous_vars 与数据交集作为 response_vars
#    pairwise_comparisons— 显式两两比较列表，如 list(c("Survivor","Non-survivor"))；NULL 且恰为 2 组时自动取水平
#    overall_method      — stat_compare_means 整体检验: "anova" 或 "kruskal.test"（默认 anova）
#    pairwise_method     — 成对比较: "t.test" 或 "wilcox.test"（默认 t.test）
#    brewer_palette      — "block"（默认，走 R/color_palettes.R）或 RColorBrewer 名（如 Set2）
#    relabel_binary_group— 分组列为 0/1 数值时是否用 project$reference_group / analysis_group 贴标签（默认 TRUE）
#    figure_width / figure_height — 英寸（默认 8 x 6）
#    y_max / y_limit_quantile / y_trans / auto_clip_skew — 右偏时避免箱体被压扁
#      （y_trans: identity|log1p|log10；默认 auto_clip_skew=TRUE 按 P99 裁显示）
#    pause_if_all_overall_ns — TRUE 且所有变量的整体 ANOVA/Kruskal p ≥ pause_p_threshold 时触发 pause_point
#    pause_p_threshold     — 默认 0.05（与 significance_alpha 缺省共用 0.05）
#    significance_alpha    — 判定「是否显著」的阈值（默认 0.05）；汇总表列 overall_significant / pairwise_significant
#    show_group_axis_title — 是否显示 x 轴分组标题；NULL 时：结局/fustatus 列默认 FALSE，其它 TRUE
#    group_axis_label      — 结局分组时标题文案（仅 show_group_axis_title=TRUE 时用；默认 "survival status"）
#
#  输出:
#    Figure_Boxplot_<response>_by_<group>.pdf（经 save_figure 入队，需 render_queued_figures）
#    Table_Boxplot_GroupComparisons.xlsx + .tex（Levene、整体/两两 p、是否显著、简述）
#    ctx$results$boxplot_summary — 汇总 data.frame
#    ctx$results$boxplot_group_var, ctx$results$boxplot_response_vars
#
#  依赖: ggplot2, ggpubr, car, rlang
#
#  使用:
#    ctx <- run_block(ctx, "boxplot")
#    ctx <- render_queued_figures(ctx)
###############################################################################

block_boxplot <- function(ctx, group_var = NULL, response_vars = NULL, ...) {
  suppressPackageStartupMessages({
    library(ggplot2)
    library(ggpubr)
    library(dplyr)
    library(rlang)
  })
  if (!requireNamespace("car", quietly = TRUE)) {
    stop("block_boxplot 需要 car 包（Levene 检验）", call. = FALSE)
  }

  cfg  <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'data_clean' or 'imputation' first.")
  data <- pipeline_ensure_outcome_group_column(data, cfg)

  bx  <- cfg$boxplot %||% list()
  prj <- cfg$project %||% list()
  bl  <- cfg$baseline %||% list()
  sv  <- cfg$survival %||% list()
  lg  <- cfg$logistic %||% list()
  oc  <- cfg$data$outcome_column %||% "Disease"

  analysis_grp  <- pipeline_outcome_case_label(cfg)
  reference_grp <- pipeline_outcome_reference_label(cfg)

  study_type <- tolower(trimws(as.character(prj$study_type %||% "incidence")))
  if (study_type %in% c("incidence", "prediction")) {
    group_var <- group_var %||% bx$group_var %||% bl$strata %||% oc
  } else {
    group_var <- group_var %||% bx$group_var %||% bl$strata %||% sv$event_var %||% oc
  }
  group_var <- as.character(group_var)[1L]
  if (!nzchar(group_var) || !group_var %in% names(data)) {
    stop("block_boxplot: 分组变量无效或不在数据中: ", group_var, call. = FALSE)
  }

  dat <- as.data.frame(data, stringsAsFactors = FALSE)

  if (isTRUE(bx$relabel_binary_group %||% TRUE)) {
    if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
      dat <- pipeline_relabel_binary_outcome_column(dat, cfg, col = group_var)
    } else {
      gv0 <- dat[[group_var]]
      strata_vals <- stats::na.omit(unique(gv0))
      if (is.numeric(gv0) && length(strata_vals) && all(strata_vals %in% c(0, 1))) {
        dat[[group_var]] <- ifelse(gv0 == 1, analysis_grp, reference_grp)
      }
    }
  }

  dat[[group_var]] <- factor(dat[[group_var]])
  levs <- levels(dat[[group_var]])
  if (length(levs) < 2L) {
    ctx$results$pause_point <- list(
      block = "block_boxplot",
      reason = paste0("分组变量 ", group_var, " 的有效水平数 < 2，无法绘制组间箱线图"),
      suggestion = "检查数据或更换 group_var / 插补结果",
      data_snapshot = utils::head(dat, 5L)
    )
    stop("PAUSE_FOR_USER_DECISION: 分组水平不足，请查看 `ctx$results$pause_point`。", call. = FALSE)
  }

  if (isTRUE(bx$use_continuous_from_baseline %||% FALSE)) {
    cv <- ctx$results$continuous_vars
    if (is.null(cv) || !length(cv)) {
      stop("block_boxplot: 已设置 use_continuous_from_baseline=TRUE 但 ctx$results$continuous_vars 为空，请先运行 baseline", call. = FALSE)
    }
    response_vars <- intersect(cv, names(dat))
  } else {
    response_vars <- response_vars %||% bx$response_vars
    if (is.null(response_vars)) {
      response_vars <- sv$index_var %||% lg$index_var
    }
    if (is.null(response_vars)) {
      stop("block_boxplot: 请指定 response_vars 或 config$boxplot$response_vars，或设置 survival$index_var / logistic$index_var", call. = FALSE)
    }
    if (is.character(response_vars) && length(response_vars) == 1L) {
      response_vars <- c(response_vars)
    }
    response_vars <- as.character(response_vars)
  }

  id_col <- cfg$data$id_column %||% NULL
  nhanes_excl <- as.character((cfg$nhanes %||% list())$exclude_cols %||% character(0))
  drop_cols <- unique(c(group_var, id_col, "ID", nhanes_excl))
  drop_cols <- drop_cols[nzchar(drop_cols)]
  response_vars <- setdiff(response_vars, drop_cols)
  response_vars <- intersect(response_vars, names(dat))
  if (!length(response_vars)) {
    stop("block_boxplot: 没有可用的连续反应变量列", call. = FALSE)
  }

  pairwise_comparisons <- bx$pairwise_comparisons %||% NULL
  if (is.null(pairwise_comparisons) && length(levs) == 2L) {
    pairwise_comparisons <- list(c(levs[1L], levs[2L]))
  }
  if (is.null(pairwise_comparisons)) {
    pairwise_comparisons <- list()
  }

  overall_method  <- tolower(as.character(bx$overall_method %||% "anova")[1L])
  pairwise_method <- tolower(as.character(bx$pairwise_method %||% "t.test")[1L])
  # 默认走统一配色库；brewer_palette="Set2" 等可显式切回 RColorBrewer
  pal_name <- as.character(bx$brewer_palette %||% "block")[1L]
  fig_w <- as.numeric(bx$figure_width %||% 6)[1L]
  fig_h <- as.numeric(bx$figure_height %||% 5.6)[1L]
  strict_pause <- isTRUE(bx$pause_if_all_overall_ns %||% FALSE)
  pause_thr <- as.numeric(bx$pause_p_threshold %||% 0.05)[1L]
  alpha <- as.numeric(bx$significance_alpha %||% pause_thr)[1L]
  if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) alpha <- 0.05

  .sig_yes_no <- function(p) {
    if (length(p) != 1L || is.na(p)) return("\u2014")
    if (p < alpha) "Yes" else "No"
  }

  .fmt_p <- function(p) {
    if (length(p) != 1L || is.na(p)) return(NA_character_)
    if (p < 0.001) return("<0.001")
    sprintf("%.3f", p)
  }

  .safe_stub <- function(s) {
    s <- gsub("[^A-Za-z0-9_.-]+", "_", s, perl = TRUE)
    gsub("_+", "_", s, perl = TRUE)
  }

  summary_rows <- list()
  overall_ps <- numeric(0)

  cli::cli_h2("Boxplot: {length(response_vars)} variable(s) by {.val {group_var}}")

  for (resp in response_vars) {
    y <- dat[[resp]]
    if (!is.numeric(y)) {
      cli::cli_alert_warning("跳过非数值列: {.val {resp}}")
      next
    }
    d1 <- dat[!is.na(dat[[group_var]]) & !is.na(y), , drop = FALSE]
    if (nrow(d1) < 4L) {
      cli::cli_alert_warning("有效样本过少，跳过: {.val {resp}}")
      next
    }

    formula_lev <- stats::reformulate(group_var, response = resp)
    levene_p <- tryCatch({
      lt <- car::leveneTest(formula_lev, data = d1)
      pv <- lt[["Pr(>F)"]]
      pv <- pv[!is.na(pv)]
      if (length(pv)) as.numeric(pv[1L]) else NA_real_
    }, error = function(e) NA_real_)

    ov_p <- tryCatch({
      if (identical(overall_method, "kruskal.test")) {
        kt <- stats::kruskal.test(formula_lev, data = d1)
        as.numeric(kt$p.value)
      } else {
        fit <- stats::aov(formula_lev, data = d1)
        sm <- summary(fit)
        pp <- sm[[1L]][["Pr(>F)"]]
        pp <- pp[!is.na(pp)]
        if (length(pp)) as.numeric(pp[1L]) else NA_real_
      }
    }, error = function(e) NA_real_)

    overall_ps <- c(overall_ps, ov_p)
    ov_sig <- .sig_yes_no(ov_p)

    cm <- tryCatch(
      ggpubr::compare_means(formula_lev, data = d1, method = pairwise_method),
      error = function(e) NULL
    )
    cm_txt <- if (is.null(cm) || !nrow(cm)) {
      ""
    } else {
      paste(
        apply(cm, 1L, function(r) {
          paste0(as.character(r[["group1"]]), " vs ", as.character(r[["group2"]]),
                 ": p=", .fmt_p(as.numeric(r[["p"]])))
        }),
        collapse = "; "
      )
    }
    pw_sig <- if (is.null(cm) || !nrow(cm)) {
      "\u2014"
    } else {
      pcol <- if ("p" %in% names(cm)) cm[["p"]] else if ("p.value" %in% names(cm)) cm[["p.value"]] else NA_real_
      ps <- suppressWarnings(as.numeric(pcol))
      if (length(ps) == 0L || all(is.na(ps))) {
        "\u2014"
      } else if (any(ps < alpha, na.rm = TRUE)) {
        "Yes"
      } else {
        "No"
      }
    }

    summary_rows[[length(summary_rows) + 1L]] <- data.frame(
      response_variable = resp,
      n_valid           = nrow(d1),
      levene_p          = .fmt_p(levene_p),
      overall_p         = .fmt_p(ov_p),
      overall_significant = ov_sig,
      pairwise_significant = pw_sig,
      overall_method    = overall_method,
      pairwise_method   = pairwise_method,
      pairwise_details  = cm_txt,
      stringsAsFactors  = FALSE
    )

    resp_lab  <- if (exists("pipeline_plot_axis_label", mode = "function")) {
      pipeline_plot_axis_label(resp, cfg)
    } else if (exists("pipeline_var_display_name", mode = "function")) {
      pipeline_display_no_underscore(pipeline_var_display_name(resp, cfg))
    } else {
      gsub("_", " ", as.character(resp), fixed = TRUE)
    }
    # 预后按结局列分组时：轴标题勿写 fustatus；默认隐藏 x 轴标题（全局可复用）
    event_cols <- unique(c(
      as.character(sv$event_var %||% character(0)),
      as.character(sv$status_column %||% character(0)),
      as.character(sv$event_column %||% character(0)),
      "fustatus", "Fustatus", "status"
    ))
    outcome_cols <- unique(c(
      as.character((cfg$data %||% list())$outcome_column %||% character(0)),
      as.character((cfg$incidence %||% list())$outcome_var %||% character(0)),
      as.character(prj$outcome %||% character(0))
    ))
    group_cols <- unique(c(event_cols, outcome_cols))
    group_cols <- group_cols[nzchar(group_cols)]
    is_event_group <- tolower(group_var) %in% tolower(event_cols)
    is_outcome_group <- tolower(group_var) %in% tolower(outcome_cols)
    outcome_cap <- if (is_outcome_group &&
        exists("pipeline_outcome_case_label", mode = "function")) {
      as.character(pipeline_outcome_case_label(cfg))[1L]
    } else if (is_outcome_group) {
      as.character((prj$disease %||% group_var)[1L])
    } else {
      NA_character_
    }
    show_x_lab <- if (!is.null(bx$show_group_axis_title)) {
      isTRUE(bx$show_group_axis_title)
    } else {
      # 默认：结局/状态列不显示轴标题（分组水平名已可读；旧版把列名 DN
      # 露到 x 轴底部，发表图禁止）；其它分层仍显示
      !is_event_group && !is_outcome_group
    }
    group_lab <- if (is_outcome_group && nzchar(outcome_cap %||% "")) {
      # 疾病名下划线→空格（Uterine_fibroids → Uterine fibroids），与刻度一致
      gsub("_", " ", outcome_cap, fixed = TRUE)
    } else if (is_event_group) {
      as.character(bx$group_axis_label %||% "survival status")[1L]
    } else if (exists("pipeline_plot_axis_label", mode = "function")) {
      pipeline_plot_axis_label(group_var, cfg)
    } else {
      gsub("_", " ", as.character(group_var), fixed = TRUE)
    }
    # 刻度：Non_ASCVD → Non ASCVD（仅展示；数据因子水平不变）
    .bp_tick_lab <- function(x) {
      if (exists("pipeline_factor_tick_labels", mode = "function")) {
        pipeline_factor_tick_labels(x)
      } else {
        gsub("_", " ", as.character(x), fixed = TRUE)
      }
    }
    plot_title <- if (is_event_group) {
      paste0("Comparison of ", resp_lab, " by ", group_lab)
    } else {
      paste0("Comparison of ", resp_lab, " by ", group_lab)
    }
    xlab_plot <- if (isTRUE(show_x_lab)) group_lab else NULL
    # 结局分组：文件名/标题/轴一律用疾病显示名（如 Uterine fibroids），
    # 禁止把数据列名（DN/fustatus 等）漏到发表文件名与图内文字。
    .bp_outcome_stub <- if (is_outcome_group && nzchar(outcome_cap %||% "")) {
      .safe_stub(outcome_cap)
    } else {
      .safe_stub(group_var)
    }
    fig_cap <- if (is_event_group && !is_outcome_group) {
      paste0("Boxplot ", .safe_stub(resp), " by survival status")
    } else if (is_outcome_group && nzchar(outcome_cap %||% "")) {
      paste0("Boxplot ", .safe_stub(resp), " by ", .bp_outcome_stub)
    } else {
      paste0("Boxplot ", .safe_stub(resp), " by ", .safe_stub(group_var))
    }
    # 发表规范：默认 Figure S*；figure_number 可固定（预后双库 S2）
    fig_kind <- as.character(bx$figure_kind %||% "supp_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "supp_figure"
    fig_no <- suppressWarnings(as.integer(bx$figure_number %||% NA_integer_)[1L])
    fig_dir_bp <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    fn <- if (is.finite(fig_no) && fig_no >= 1L &&
              exists("pub_figure_filepath_at", mode = "function")) {
      basename(pub_figure_filepath_at(
        fig_dir_bp, fig_no, fig_cap, ext = "pdf",
        bump_counter = isTRUE(bx$bump_counter %||% FALSE),
        kind = fig_kind
      ))
    } else {
      pub_figure_file(ctx, fig_kind, fig_cap)
    }
    fig_path_bp <- file.path(fig_dir_bp, fn)
    dir.create(dirname(fig_path_bp), recursive = TRUE, showWarnings = FALSE)

    # 直接 cairo_pdf 单次 print，避免 save_figure 队列路径偶发双页
    # 右偏指标（如 APRI）全范围会把箱体压成一条线 → y_max / log1p / 分位裁剪
    y_vals <- as.numeric(d1[[resp]])
    y_med  <- stats::median(y_vals, na.rm = TRUE)
    y_maxv <- max(y_vals, na.rm = TRUE)
    y_max_cfg <- suppressWarnings(as.numeric(bx$y_max %||% NA_real_)[1L])
    y_q_cfg <- suppressWarnings(as.numeric(bx$y_limit_quantile %||% NA_real_)[1L])
    y_trans <- tolower(trimws(as.character(bx$y_trans %||% "identity")[1L]))
    if (!y_trans %in% c("identity", "log1p", "log10")) y_trans <- "identity"
    auto_clip <- isTRUE(bx$auto_clip_skew %||% TRUE)
    ylim_hi <- NA_real_
    if (is.finite(y_max_cfg) && y_max_cfg > 0) {
      ylim_hi <- y_max_cfg
    } else if (is.finite(y_q_cfg) && y_q_cfg > 0 && y_q_cfg < 1) {
      ylim_hi <- as.numeric(stats::quantile(y_vals, probs = y_q_cfg, na.rm = TRUE, names = FALSE))
    } else if (auto_clip && y_trans == "identity" &&
               is.finite(y_med) && y_med > 0 && is.finite(y_maxv) &&
               (y_maxv / y_med) >= 20) {
      ylim_hi <- as.numeric(stats::quantile(y_vals, probs = 0.99, na.rm = TRUE, names = FALSE))
      cli::cli_alert_info(
        "{resp}: 右偏严重 (max/median={round(y_maxv / y_med, 1)})，箱线图显示上限裁至 P99={signif(ylim_hi, 3)}"
      )
    }
    if (is.finite(ylim_hi) && is.finite(y_med) && ylim_hi <= y_med) {
      ylim_hi <- as.numeric(stats::quantile(y_vals, probs = 0.99, na.rm = TRUE, names = FALSE))
    }

    out_shape <- bx$outlier_shape %||% 16L
    # 注意：coord_cartesian 会裁掉超出显示范围的离群点；勿默认 outlier.shape=NA
    # （否则连范围内离群点也不画）。仅当显式 hide_outliers=TRUE 时隐藏全部离群点。
    if (isTRUE(bx$hide_outliers %||% FALSE)) out_shape <- NA
    out_size  <- as.numeric(bx$outlier_size %||% 1.1)[1L]
    out_alpha <- as.numeric(bx$outlier_alpha %||% 0.45)[1L]
    box_w     <- as.numeric(bx$box_width %||% 0.55)[1L]

    # 显示用数据：有 y_max 时截断到上限，避免上须顶穿图顶、与显著性括号粘连
    d_plot <- d1
    if (is.finite(ylim_hi) && identical(y_trans, "identity")) {
      d_plot[[resp]] <- pmin(as.numeric(d_plot[[resp]]), ylim_hi)
    }

    g <- ggplot2::ggplot(d_plot, ggplot2::aes(x = !!rlang::sym(group_var), y = !!rlang::sym(resp),
                                           fill = !!rlang::sym(group_var))) +
      ggplot2::geom_boxplot(
        width = box_w,
        outlier.shape = out_shape,
        outlier.size = out_size,
        outlier.alpha = out_alpha,
        median.linewidth = 1.8,
        linewidth = 0.55
      ) +
      ggplot2::labs(title = plot_title, x = xlab_plot, y = resp_lab) +
      ggplot2::scale_x_discrete(labels = .bp_tick_lab) +
      ggplot2::theme_classic(base_family = if (isTRUE(capabilities("cairo"))) {
        "Times New Roman"
      } else {
        plot_font_from_config(cfg)
      }) +
      ggplot2::theme(
        text = ggplot2::element_text(
          family = if (isTRUE(capabilities("cairo"))) "Times New Roman" else plot_font_from_config(cfg),
          size = 12
        ),
        legend.position = "none",
        plot.title = ggplot2::element_text(
          hjust = 0.5, face = "bold", size = 13,
          margin = ggplot2::margin(b = 6)
        ),
        axis.title.x = if (is.null(xlab_plot)) ggplot2::element_blank() else ggplot2::element_text(size = 12),
        axis.title.y = ggplot2::element_text(size = 12),
        axis.title.y.right = ggplot2::element_blank(),
        axis.text = ggplot2::element_text(color = "black", size = 11),
        axis.text.y.right = ggplot2::element_blank(),
        axis.ticks.y.right = ggplot2::element_blank(),
        axis.line = ggplot2::element_line(linewidth = 0.6, colour = "black"),
        axis.line.y.right = ggplot2::element_blank(),
        axis.ticks = ggplot2::element_line(linewidth = 0.5, colour = "black"),
        panel.grid.major.x = ggplot2::element_blank(),
        panel.grid.major.y = ggplot2::element_blank(),
        panel.border = ggplot2::element_blank(),
        plot.margin = ggplot2::margin(24, 8, 6, 8)
      )
    if (identical(y_trans, "log1p")) {
      g <- g + ggplot2::scale_y_continuous(trans = "log1p")
      g <- g + ggplot2::labs(y = paste0(resp_lab, " (log1p)"))
    } else if (identical(y_trans, "log10")) {
      # log10 需 y>0
      d1_pos <- d1[d1[[resp]] > 0, , drop = FALSE]
      if (nrow(d1_pos) >= 4L) {
        g <- ggplot2::ggplot(d1_pos, ggplot2::aes(x = !!rlang::sym(group_var), y = !!rlang::sym(resp),
                                                   fill = !!rlang::sym(group_var))) +
          ggplot2::geom_boxplot(
            width = box_w, outlier.shape = out_shape, outlier.size = out_size,
            outlier.alpha = out_alpha, median.linewidth = 1.8, linewidth = 0.45
          ) +
          ggplot2::scale_y_log10() +
          ggplot2::labs(title = plot_title, x = xlab_plot, y = paste0(resp_lab, " (log10)")) +
          ggplot2::scale_x_discrete(labels = .bp_tick_lab) +
          ggplot2::theme_classic(base_family = if (isTRUE(capabilities("cairo"))) "Times New Roman" else plot_font_from_config(cfg)) +
          ggplot2::theme(
        legend.position = "none",
        plot.title = ggplot2::element_text(hjust = 0.5, face = "bold", margin = ggplot2::margin(b = 6)),
        axis.title.x = if (is.null(xlab_plot)) ggplot2::element_blank() else ggplot2::element_text(),
        axis.title.y.right = ggplot2::element_blank(),
        axis.text.y.right = ggplot2::element_blank(),
        axis.ticks.y.right = ggplot2::element_blank(),
        axis.line.y.right = ggplot2::element_blank(),
        panel.grid.major.x = ggplot2::element_blank()
      )
      } else {
        cli::cli_alert_warning("{resp}: log10 有效点过少，回退线性轴")
      }
    }
    # 纵轴显示：数据区上限 ylim_hi；顶部留空给括号+星号，并与标题拉开距离
    y_lo <- 0
    y_plot_top <- NA_real_
    label_y <- NA_real_
    if (is.finite(ylim_hi) && identical(y_trans, "identity")) {
      y_lo <- min(0, min(y_vals, na.rm = TRUE), na.rm = TRUE)
      y_plot_top <- ylim_hi * 1.28
      label_y <- ylim_hi * 1.10
    }

    # 显著性括号：右偏数据时 ggsignif/ggpubr 会把括号画到全样本极值高度，
    # 再被 coord_cartesian 裁掉。改为在显示范围内用 annotate 手动画括号+星号。
    .p_to_stars <- function(p) {
      if (length(p) != 1L || is.na(p)) return("ns")
      if (p < 1e-4) return("****")
      if (p < 1e-3) return("***")
      if (p < 1e-2) return("**")
      if (p < 0.05) return("*")
      "ns"
    }
    .pair_p <- function(dat, gv, rv, a, b, method) {
      xa <- as.numeric(dat[[rv]][as.character(dat[[gv]]) == a])
      xb <- as.numeric(dat[[rv]][as.character(dat[[gv]]) == b])
      xa <- xa[is.finite(xa)]; xb <- xb[is.finite(xb)]
      if (length(xa) < 2L || length(xb) < 2L) return(NA_real_)
      tryCatch({
        if (identical(method, "t.test")) stats::t.test(xa, xb)$p.value
        else stats::wilcox.test(xa, xb, exact = FALSE)$p.value
      }, error = function(e) NA_real_)
    }
    y_star <- if (is.finite(label_y)) label_y else max(y_vals, na.rm = TRUE) * 1.05
    if (!length(pairwise_comparisons)) {
      levs_g <- levels(d1[[group_var]])
      p0 <- tryCatch({
        if (identical(overall_method, "anova")) {
          stats::anova(stats::lm(stats::reformulate(group_var, resp), data = d1))$`Pr(>F)`[1L]
        } else {
          stats::kruskal.test(stats::reformulate(group_var, resp), data = d1)$p.value
        }
      }, error = function(e) NA_real_)
      g <- g + ggplot2::annotate(
        "text", x = mean(seq_along(levs_g)), y = y_star,
        label = .p_to_stars(p0), size = 4.8, vjust = 0.5
      )
    } else {
      levs_g <- levels(d1[[group_var]])
      step <- if (is.finite(ylim_hi)) ylim_hi * 0.06 else {
        diff(range(y_vals, na.rm = TRUE)) * 0.06
      }
      tip <- if (is.finite(ylim_hi)) ylim_hi * 0.035 else step * 0.4
      for (i in seq_along(pairwise_comparisons)) {
        ab <- pairwise_comparisons[[i]]
        if (length(ab) < 2L) next
        a <- as.character(ab[[1L]]); b <- as.character(ab[[2L]])
        if (!all(c(a, b) %in% levs_g)) next
        y1 <- y_star + (i - 1L) * step
        y0 <- y1 - tip
        lab <- .p_to_stars(.pair_p(d1, group_var, resp, a, b, pairwise_method))
        # 用水平名定位，避免数值 x 在离散轴上越界拉出多余横线
        seg <- data.frame(
          x = factor(c(a, a, b), levels = levs_g),
          xend = factor(c(b, a, b), levels = levs_g),
          y = c(y1, y0, y0),
          yend = c(y1, y1, y1),
          stringsAsFactors = FALSE
        )
        ia <- match(a, levs_g); ib <- match(b, levs_g)
        g <- g +
          ggplot2::geom_segment(
            data = seg,
            ggplot2::aes(x = .data$x, xend = .data$xend, y = .data$y, yend = .data$yend),
            inherit.aes = FALSE,
            linewidth = 0.55,
            colour = "black",
            lineend = "butt"
          ) +
          ggplot2::annotate(
            "text",
            x = (ia + ib) / 2,
            y = y1, label = lab, size = 5.0, vjust = 0.5
          )
      }
    }

    if (is.finite(y_plot_top)) {
      g <- g + ggplot2::coord_cartesian(ylim = c(y_lo, y_plot_top), clip = "on")
      brks <- pretty(c(y_lo, ylim_hi), n = 5L)
      brks <- brks[brks >= y_lo & brks <= ylim_hi + 1e-9]
      g <- g + ggplot2::scale_y_continuous(
        breaks = brks,
        expand = ggplot2::expansion(mult = c(0.02, 0.06))
      )
    } else if (identical(y_trans, "identity")) {
      g <- g + ggplot2::scale_y_continuous(
        expand = ggplot2::expansion(mult = c(0.02, 0.06))
      )
    }
    if (identical(tolower(trimws(pal_name)), "block") || !nzchar(trimws(pal_name))) {
      nlev <- length(levels(d1[[group_var]]))
      cols <- if (exists("block_default_palette", mode = "function")) {
        block_default_palette(nlev, cfg)
      } else if (exists("block_colors", mode = "function")) {
        block_colors(nlev)
      } else {
        grDevices::hcl.colors(nlev, "Set 2")
      }
      g <- g + ggplot2::scale_fill_manual(values = cols)
    } else if (requireNamespace("RColorBrewer", quietly = TRUE) && pal_name %in% rownames(RColorBrewer::brewer.pal.info)) {
      nlev <- length(levels(d1[[group_var]]))
      mxc <- as.integer(RColorBrewer::brewer.pal.info[pal_name, "maxcolors"])[1L]
      cols <- if (nlev <= mxc) {
        RColorBrewer::brewer.pal(max(3L, nlev), pal_name)[seq_len(nlev)]
      } else {
        base <- RColorBrewer::brewer.pal(min(8L, mxc), pal_name)
        grDevices::colorRampPalette(base)(nlev)
      }
      g <- g + ggplot2::scale_fill_manual(values = cols)
    } else {
      g <- g + ggplot2::scale_fill_hue()
    }
    ff_bp <- if (isTRUE(capabilities("cairo"))) "Times New Roman" else plot_font_from_config(cfg)
    tryCatch({
      if (file.exists(fig_path_bp)) unlink(fig_path_bp)
      grDevices::cairo_pdf(fig_path_bp, width = fig_w, height = fig_h, family = ff_bp)
      print(g)
      grDevices::dev.off()
      cli::cli_alert_success("Boxplot saved: {.file {basename(fig_path_bp)}}")
      if (exists("mirror_pub_output_to_root", mode = "function")) {
        mirror_pub_output_to_root(ctx, fig_path_bp)
      }
      # SVG 旁路：默认关闭
      if (isTRUE(pub_export_figure_svg(ctx)) && requireNamespace("svglite", quietly = TRUE)) {
        svg_bp <- sub("\\.pdf$", ".svg", fig_path_bp, ignore.case = TRUE)
        svglite::svglite(svg_bp, width = fig_w, height = fig_h)
        print(g)
        grDevices::dev.off()
      }
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("Boxplot save failed: {e$message}")
    })
  }

  if (!length(summary_rows)) {
    # 分类暴露（如 Periodontitis 0–3 factor）无连续反应变量：跳过而非打挂整指标
    cli::cli_alert_warning(
      "boxplot: 无可绘制的连续反应变量（可能均为分类暴露），跳过本块"
    )
    ctx$results$boxplot_summary <- NULL
    ctx$results$boxplot_skipped_reason <- "no_numeric_response"
    return(ctx)
  }

  summary_df <- dplyr::bind_rows(summary_rows)
  ctx$results$boxplot_summary       <- summary_df
  ctx$results$boxplot_group_var     <- group_var
  ctx$results$boxplot_response_vars <- response_vars

  cli::cli_h2("Boxplot 显著性摘要（整体 / 两两，α = {alpha}）")
  for (k in seq_len(nrow(summary_df))) {
    cli::cli_alert_info(
      "{summary_df$response_variable[k]}: 整体组间 = {summary_df$overall_significant[k]} (p = {summary_df$overall_p[k]})；两两 = {summary_df$pairwise_significant[k]}"
    )
  }

  if (strict_pause && length(overall_ps)) {
    all_ns <- all(!is.na(overall_ps) & overall_ps >= pause_thr)
    if (all_ns) {
      ctx$results$pause_point <- list(
        block = "block_boxplot",
        reason = paste0("config$boxplot$pause_if_all_overall_ns=TRUE：所有变量的整体检验 p ≥ ", pause_thr),
        suggestion = "若仍希望保留图形，请将 pause_if_all_overall_ns 设为 FALSE 或调整分组/变量",
        data_snapshot = utils::head(summary_df, 10L)
      )
      stop("PAUSE_FOR_USER_DECISION: 组间整体比较均为阴性，请查看 `ctx$results$pause_point`。", call. = FALSE)
    }
  }

  cli::cli_alert_success("Boxplot 块完成：已保存 {nrow(summary_df)} 个图")
  ctx
}

register_block("boxplot", block_boxplot,
               "分组箱线图 + Levene/ANOVA 与 ggpubr 组间比较，输出 PDF 与汇总表")
