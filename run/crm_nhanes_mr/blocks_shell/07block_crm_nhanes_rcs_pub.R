###############################################################################
#  crm_nhanes_rcs_pub — NHANES 加权 RCS 发表级 Figure 3
#  （SUA \u2192 全因死亡 HR 剂量反应曲线，按 CRM_count 分层 + 总体面板；P for nonlinearity）
#
#  依据：Han et al. 2025 JAHA e038723；本仓库设计
#  docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md（Figure 3）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data      = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  requires_packages = c("survey", "Hmisc")；ggplot2/patchwork 可选（缺失时回退基础绘图）
#
#  说明（分析集口径，与 06block Cox 一致）：与 06block_crm_nhanes_cox_pub.R 完全一致的
#  死亡随访完整过滤（SUA 非缺失 → 死亡随访合格 → futime/fustatus/CRM_count 完整），
#  与 05block（Table 2，横断面）刻意不同。
#
#  说明（RCS 方法学，证据链）：原文 Figure 3 的确切结点位置/数目在本仓库可读文本证据中
#  未逐字确证——【证据不足】。本块采用与 Blocks/15_rcs/03block_rcs_nhanes.R 相同的既有
#  实现范式：Hmisc::rcspline.eval() 生成 RCS 基（默认结点分位数 0.1/0.5/0.9，3 列基，
#  与该文件默认一致）+ survey::svycoxph 加权 Cox 拟合 + survey::regTermTest 做
#  "P for overall"（全部 RCS 基列）与"P for nonlinearity"（剔除线性项后的非线性基列）
#  Wald 检验——不新增/不重写一套无关的 RCS 推断算法。曲线以样本中位 SUA 为参照
#  （HR=1），逐点 HR = exp(线性预测差)，95% CI 用 predict(..., se.fit=TRUE) 的
#  delta 近似正态区间，与既有 rcs_nhanes 图算法一致。
#
#  说明（分层面板，证据链）：按 CRM_count 各观测水平（0/1/2/3，数据中实际存在且样本量
#  ≥ min_stratum_n 的水平）分层拟合独立 RCS 曲线 + 一个不分层的 Overall 面板；不足样本量的
#  水平会被跳过并在 ctx$results$crm_nhanes_rcs_pub$skipped_strata 中记录原因，而不是强行
#  拟合出不稳定的曲线冒充"分层结果"。
#
#  crm_nhanes_rcs_pub = list(
#    sua_col          = "SUA",
#    time_var         = "futime",
#    event_var        = "fustatus",
#    crm_var          = "CRM_count",
#    eligibility_col  = "eligstat",
#    adjust_vars      = NULL,           # NULL → c("Age","Gender","BMI") ∩ 数据列
#    weight_col       = NULL,           # NULL → config$nhanes$survey_weight %||% "new_Weight"
#    cluster_col      = NULL,           # NULL → config$nhanes$survey_cluster %||% "SDMVPSU"
#    strata_col       = NULL,           # NULL → config$nhanes$survey_strata %||% "SDMVSTRA"
#    knot_quantiles   = c(0.1, 0.5, 0.9),
#    min_stratum_n    = 30L,            # 分层样本量下限（events 下限见 min_stratum_events）
#    min_stratum_events = 5L,
#    include_overall  = TRUE,           # 是否额外出一个不分层的 Overall 面板
#    n_points         = 100L,
#    figure_basename  = "Figure_3_RCS_NHANES",  # 固定名（文献 Figure 3，不经过发表编号计数器）
#    figure_caption   = "Restricted cubic spline of SUA and all-cause mortality by CRM count (NHANES)",
#    table_filename   = "Table_3_RCS_NHANES.csv",  # 固定名，Figure 3 的数值/P 值伴随表
#    plot_width       = 14, plot_height = 8,
#    also_run_thin57  = FALSE,          # TRUE → 额外调用 57 的 block_crm_rcs_sua() 冒烟对照
#    pause_enable         = TRUE,
#    pause_on_no_output   = TRUE
#  )
#
#  register_block: "crm_nhanes_rcs_pub"
#  典型位置: ... → crm_nhanes_cox_pub → crm_nhanes_rcs_pub（Figure 3）→ crm_nhanes_pub_align
#
#  读: ctx$data$cleaned %||% ctx$data$raw
#  写: ctx$results$crm_nhanes_rcs_pub（各分层曲线数据、P_overall/P_nonlinear、
#      skipped_strata、可选 thin57_comparison）
#
#  产出:
#    - [固定名] Figures/Figure_3_RCS_NHANES.pdf / .png
#    - [固定名] Tables/Table_3_RCS_NHANES.csv（Stratum/N/Events/P_overall/P_nonlinear/Ref_SUA）
#
#  pause: config$crm_nhanes_rcs_pub$pause_enable
###############################################################################

.crm70r_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70r_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_rcs_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_rcs_pub halted. See ctx$results$pause_point. / ",
    "NHANES 加权 RCS 发表图异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

#' 与 06block_crm_nhanes_cox_pub.R 完全一致的分析集过滤
.crm70r_apply_analytic_filters <- function(data, tvar, yvar, sua_col, elig_col) {
  d <- data
  if (sua_col %in% names(d)) d <- d[!is.na(d[[sua_col]]), , drop = FALSE]
  if (elig_col %in% names(data)) {
    d <- d[d[[elig_col]] %in% c(1, "1"), , drop = FALSE]
  }
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  if (!elig_col %in% names(data)) {
    keep_fu <- !is.na(d[[tvar]]) & !is.na(d[[yvar]]) & is.finite(d[[tvar]]) & d[[tvar]] >= 0
    keep_fu[is.na(keep_fu)] <- FALSE
    d <- d[keep_fu, , drop = FALSE]
  }
  d[is.finite(d[[tvar]]) & d[[tvar]] >= 0 & !is.na(d[[yvar]]), , drop = FALSE]
}

.crm70r_build_design <- function(d, wt_col, psu_col, str_col) {
  has_design_cols <- all(c(psu_col, str_col) %in% names(d))
  tryCatch({
    if (has_design_cols) {
      survey::svydesign(
        ids = stats::as.formula(paste0("~", psu_col)),
        strata = stats::as.formula(paste0("~", str_col)),
        weights = stats::as.formula(paste0("~", wt_col)),
        data = d, nest = TRUE
      )
    } else {
      survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt_col)), data = d)
    }
  }, error = function(e) NULL)
}

#' 单个分层（或 Overall）的加权 RCS 拟合：返回曲线数据 + P_overall/P_nonlinear
.crm70r_fit_stratum_rcs <- function(d, sua_col, tvar, yvar, adjust_vars, knots,
                                     wt_col, psu_col, str_col, n_points) {
  basis <- as.matrix(Hmisc::rcspline.eval(d[[sua_col]], knots = knots, inclx = TRUE))
  bn <- paste0("rb", seq_len(ncol(basis)))
  colnames(basis) <- bn
  d2 <- cbind(d, as.data.frame(basis))
  design <- .crm70r_build_design(d2, wt_col, psu_col, str_col)
  if (is.null(design)) return(NULL)

  fml <- stats::as.formula(paste0(
    "survival::Surv(", tvar, ",", yvar, ") ~ ", paste(bn, collapse = " + "),
    if (length(adjust_vars)) paste0(" + ", paste(adjust_vars, collapse = " + ")) else ""
  ))
  fit <- tryCatch(survey::svycoxph(fml, design = design), error = function(e) {
    cli::cli_alert_warning("crm_nhanes_rcs_pub: svycoxph(RCS) 拟合失败: {e$message}")
    NULL
  })
  if (is.null(fit)) return(NULL)
  # 注：survey::summary.svycoxph() 会把 design 摘要打印到 stdout（副作用，见 06block 同类
  # 注释）；本函数只用 regTermTest()/predict()，不调用 summary(fit)，故不触发该噪声输出。

  p_overall <- tryCatch(survey::regTermTest(fit, bn)$p, error = function(e) NA_real_)
  p_nonlin <- tryCatch(
    if (length(bn) > 1L) survey::regTermTest(fit, bn[-1])$p else NA_real_,
    error = function(e) NA_real_
  )

  x_rng <- seq(min(d[[sua_col]], na.rm = TRUE), max(d[[sua_col]], na.rm = TRUE),
               length.out = n_points)
  ref_x <- stats::median(d[[sua_col]], na.rm = TRUE)
  pred_basis <- as.matrix(Hmisc::rcspline.eval(c(ref_x, x_rng), knots = knots, inclx = TRUE))
  colnames(pred_basis) <- bn
  newdat <- as.data.frame(pred_basis)
  for (v in adjust_vars) {
    vv <- d[[v]]
    newdat[[v]] <- if (is.numeric(vv)) {
      rep(mean(vv, na.rm = TRUE), nrow(newdat))
    } else {
      xf <- if (is.factor(vv)) vv else factor(vv)
      factor(rep(levels(xf)[1L], nrow(newdat)), levels = levels(xf))
    }
  }
  pred <- tryCatch(
    stats::predict(fit, newdata = newdat, type = "lp"),
    error = function(e) NULL
  )
  if (is.null(pred)) return(NULL)
  lp <- as.numeric(pred)
  rel <- lp[-1] - lp[1]

  # 关键修正（对比 SE，而非绝对水平 SE）：rel = lp(x) - lp(ref) 的 SE 不能用
  # predict(..., se.fit=TRUE) 给出的 se.fit ——那是每个点“绝对”线性预测值的
  # SE（Var(lp(x))），忽略了 lp(x) 与 lp(ref) 之间的协方差，会系统性地
  # 高估/歪曲差值的不确定性（正确公式需 Var(lp(x)-lp(ref)) =
  # Var(lp(x)) + Var(lp(ref)) - 2*Cov(lp(x),lp(ref))）。正确做法是用对比
  # 协方差：se = sqrt(diag(D %*% V %*% t(D)))，其中 D = X[x,] - X[ref,]，
  # V = vcov(fit)。
  # 注：newdat 中的协变量列（adjust_vars）在所有预测行（含 ref 行）都取值
  # 相同（数值型取均值、因子型取参照水平），因此 D 在这些列上恒为 0；
  # D %*% V %*% t(D) 精确等价于把 D、V 都限制到 RCS 基列（bn）子块后的
  # 结果，故下面直接用该等价子块计算，避免依赖 predict() 内部设计矩阵表示。
  V <- stats::vcov(fit)
  if (!all(bn %in% rownames(V))) return(NULL)
  V_bn <- V[bn, bn, drop = FALSE]
  D_bn <- pred_basis[-1L, bn, drop = FALSE] -
    matrix(pred_basis[1L, bn], nrow = nrow(pred_basis) - 1L, ncol = length(bn), byrow = TRUE)
  se_rel <- sqrt(pmax(rowSums((D_bn %*% V_bn) * D_bn), 0))

  list(
    curve = data.frame(
      SUA = x_rng,
      HR = exp(rel),
      Lower95 = exp(rel - 1.96 * se_rel),
      Upper95 = exp(rel + 1.96 * se_rel)
    ),
    p_overall = p_overall,
    p_nonlin = p_nonlin,
    ref_sua = ref_x,
    n = nrow(d),
    events = sum(d[[yvar]] == 1, na.rm = TRUE)
  )
}

.crm70r_plot_panel <- function(res, title_txt, xlab, ylab, font_family) {
  if (is.null(res) || !requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  df <- res$curve
  p_ov_txt <- pub_format_p(res$p_overall)
  p_nl_txt <- pub_format_p(res$p_nonlin)
  ggplot2::ggplot(df, ggplot2::aes(x = .data$SUA, y = .data$HR)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$Lower95, ymax = .data$Upper95),
                         fill = "#377EB8", alpha = 0.2) +
    ggplot2::geom_line(color = "#377EB8", linewidth = 1) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
    ggplot2::labs(title = title_txt, x = xlab, y = ylab) +
    ggplot2::annotate("text", x = min(df$SUA), y = max(df$Upper95, na.rm = TRUE),
                      label = paste0("P overall = ", p_ov_txt, "\nP nonlinear = ", p_nl_txt),
                      hjust = 0, vjust = 1, family = font_family, size = 3.2) +
    ggplot2::theme_classic(base_size = 12) +
    ggplot2::theme(text = ggplot2::element_text(family = font_family))
}

block_crm_nhanes_rcs_pub <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_rcs_pub %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70r_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_rcs_pub: 无分析数据。", call. = FALSE)
  }
  for (pkg in c("survey", "Hmisc")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      if (.crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
        .crm70r_pause(ctx, paste0("缺少 R 包 ", pkg, "，无法构建加权 RCS。"),
                     "安装依赖后重试，或设 pause_on_no_output = FALSE。", NULL)
      }
      stop(paste0("crm_nhanes_rcs_pub: 缺少 ", pkg, " 包。"), call. = FALSE)
    }
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(survival, warn.conflicts = FALSE)
    library(Hmisc, warn.conflicts = FALSE)
  })
  options(survey.lonely.psu = "adjust")

  sua_col <- as.character(bl_cfg$sua_col %||% "SUA")[1L]
  tvar <- as.character(bl_cfg$time_var %||% "futime")[1L]
  yvar <- as.character(bl_cfg$event_var %||% "fustatus")[1L]
  crm_var <- as.character(bl_cfg$crm_var %||% "CRM_count")[1L]
  elig_col <- as.character(bl_cfg$eligibility_col %||% "eligstat")[1L]
  wt_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]
  psu_col <- as.character(bl_cfg$cluster_col %||% nh_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(bl_cfg$strata_col %||% nh_cfg$survey_strata %||% "SDMVSTRA")[1L]

  need <- unique(c(sua_col, tvar, yvar, crm_var, wt_col))
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    msg <- paste0("crm_nhanes_rcs_pub: 数据缺少列: ", paste(miss, collapse = ", "))
    if (.crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70r_pause(ctx, msg, "检查 crm_nhanes_derive 是否已运行。", data)
    }
    stop(msg, call. = FALSE)
  }

  adjust_vars_cfg <- bl_cfg$adjust_vars
  m2_ctx <- setdiff(
    intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data)),
    c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
  )
  adjust_vars <- if (!is.null(adjust_vars_cfg) && length(adjust_vars_cfg)) {
    intersect(as.character(adjust_vars_cfg), names(data))
  } else if (length(m2_ctx)) {
    cli::cli_alert_info(
      "crm_nhanes_rcs_pub: 使用筛选 Model2Factors ({length(m2_ctx)}): {paste(m2_ctx, collapse=', ')}"
    )
    m2_ctx
  } else {
    intersect(c("Age", "Gender", "BMI"), names(data))
  }

  keep_cols <- unique(c(need, elig_col, psu_col, str_col, adjust_vars))
  keep_cols <- intersect(keep_cols, names(data))
  d0 <- data[, keep_cols, drop = FALSE]
  d0 <- .crm70r_apply_analytic_filters(d0, tvar, yvar, sua_col, elig_col)
  d0[[sua_col]] <- suppressWarnings(as.numeric(d0[[sua_col]]))
  d0[[wt_col]] <- suppressWarnings(as.numeric(d0[[wt_col]]))
  complete_cols <- intersect(c(sua_col, crm_var, tvar, yvar, wt_col, adjust_vars), names(d0))
  keep <- stats::complete.cases(d0[, complete_cols, drop = FALSE]) & is.finite(d0[[wt_col]])
  d <- d0[keep, , drop = FALSE]

  if (!nrow(d)) {
    msg <- "crm_nhanes_rcs_pub: 有效分析集为空。"
    if (.crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70r_pause(ctx, msg, "检查 SUA/futime/fustatus/CRM_count 缺失情况。", d0)
    }
    stop(msg, call. = FALSE)
  }

  knot_q <- as.numeric(bl_cfg$knot_quantiles %||% c(0.1, 0.5, 0.9))
  knots <- stats::quantile(d[[sua_col]], knot_q, na.rm = TRUE)
  n_points <- as.integer(bl_cfg$n_points %||% 100L)[1L]
  min_n <- as.integer(bl_cfg$min_stratum_n %||% 30L)[1L]
  min_events <- as.integer(bl_cfg$min_stratum_events %||% 5L)[1L]
  include_overall <- isTRUE(bl_cfg$include_overall %||% FALSE)
  # 原文 Figure 3（NHANES）：A=1 CRM, B=2 CRM, C=3 CRM, D=≥1 CRM（不含 0 CRM / Overall）
  panel_spec <- bl_cfg$panel_spec %||% list(
    list(label = "A. 1 CRM", crm_levels = 1L),
    list(label = "B. 2 CRM", crm_levels = 2L),
    list(label = "C. 3 CRM", crm_levels = 3L),
    list(label = "D. >=1 CRM", crm_levels = c(1L, 2L, 3L))
  )

  results_by_stratum <- list()
  skipped_strata <- list()

  if (isTRUE(include_overall)) {
    res_overall <- tryCatch(
      .crm70r_fit_stratum_rcs(d, sua_col, tvar, yvar, adjust_vars, knots, wt_col, psu_col, str_col, n_points),
      error = function(e) { cli::cli_alert_warning("crm_nhanes_rcs_pub Overall 拟合失败: {e$message}"); NULL }
    )
    if (!is.null(res_overall)) results_by_stratum[["Overall"]] <- res_overall
  }

  for (ps in panel_spec) {
    lv <- as.integer(ps$crm_levels)
    lbl <- as.character(ps$label %||% paste0("CRM=", paste(lv, collapse = "+")))[1L]
    dsub <- d[d[[crm_var]] %in% lv, , drop = FALSE]
    n_sub <- nrow(dsub)
    n_ev_sub <- sum(dsub[[yvar]] == 1, na.rm = TRUE)
    if (n_sub < min_n || n_ev_sub < min_events) {
      skipped_strata[[lbl]] <- list(n = n_sub, events = n_ev_sub, reason = "below min_stratum_n/min_stratum_events")
      cli::cli_alert_warning(
        "crm_nhanes_rcs_pub: 分层 {lbl} 样本量({n_sub})/事件数({n_ev_sub}) 不足，跳过。"
      )
      next
    }
    res_lv <- tryCatch(
      .crm70r_fit_stratum_rcs(dsub, sua_col, tvar, yvar, adjust_vars, knots, wt_col, psu_col, str_col, n_points),
      error = function(e) { cli::cli_alert_warning("crm_nhanes_rcs_pub {lbl} 拟合失败: {e$message}"); NULL }
    )
    if (!is.null(res_lv)) results_by_stratum[[lbl]] <- res_lv
  }

  if (!length(results_by_stratum)) {
    msg <- "crm_nhanes_rcs_pub: 所有分层面板均未能拟合有效 RCS。"
    if (.crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70r_pause(ctx, msg, "检查样本量/事件数是否过低。", d)
    }
    stop(msg, call. = FALSE)
  }

  font_family <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else "sans"
  xlab <- "Serum uric acid (mg/dL)"
  ylab <- "HR (95% CI) for all-cause mortality"

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)

  # NHANES-only：原文 Fig2=CHARLS 跳过 → 本图为正图 Figure 2
  fig_base <- as.character(bl_cfg$figure_basename %||%
    "Figure 2-NHANES-RCS_SUA_all-cause_mortality_by_CRM")[1L]
  pdf_path <- file.path(fig_dir, paste0(fig_base, ".pdf"))
  png_path <- file.path(fig_dir, paste0(fig_base, ".png"))
  write_png <- isTRUE(bl_cfg$write_png %||% FALSE)
  plot_w <- as.numeric(bl_cfg$plot_width %||% 10)[1L]
  plot_h <- as.numeric(bl_cfg$plot_height %||% 8)[1L]
  ncol_panels <- as.integer(bl_cfg$ncol %||% 2L)[1L]

  panels <- Filter(Negate(is.null), lapply(names(results_by_stratum), function(nm) {
    .crm70r_plot_panel(results_by_stratum[[nm]], nm, xlab, ylab, font_family)
  }))

  saved_pdf <- FALSE
  saved_png <- FALSE
  if (length(panels)) {
    comb <- if (requireNamespace("patchwork", quietly = TRUE)) {
      Reduce(`+`, panels) + patchwork::plot_layout(ncol = ncol_panels)
    } else if (requireNamespace("gridExtra", quietly = TRUE)) {
      gridExtra::arrangeGrob(grobs = panels, ncol = ncol_panels)
    } else {
      panels[[1L]]
    }
    saved_pdf <- tryCatch({
      if (file.exists(pdf_path)) unlink(pdf_path)
      ggplot2::ggsave(pdf_path, comb, width = plot_w, height = plot_h, device = grDevices::cairo_pdf)
      TRUE
    }, error = function(e) {
      tryCatch({
        grDevices::cairo_pdf(pdf_path, width = plot_w, height = plot_h)
        if (requireNamespace("patchwork", quietly = TRUE) || length(panels) == 1L) print(comb) else grid::grid.draw(comb)
        grDevices::dev.off()
        TRUE
      }, error = function(e2) { try(grDevices::dev.off(), silent = TRUE); FALSE })
    })
    if (isTRUE(write_png)) {
      saved_png <- tryCatch({
        ggplot2::ggsave(png_path, comb, width = plot_w, height = plot_h, dpi = 300)
        TRUE
      }, error = function(e) FALSE)
    } else if (file.exists(png_path)) {
      unlink(png_path)
    }
  }

  if (!isTRUE(saved_pdf) && !isTRUE(saved_png) &&
      .crm70r_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .crm70r_pause(ctx, "crm_nhanes_rcs_pub 未能生成 RCS 图 PDF/PNG。",
                 "检查 ggplot2/patchwork/gridExtra 是否可用。", d)
  }
  if (isTRUE(saved_pdf) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, pdf_path)
  }
  if (isTRUE(saved_png) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, png_path)
  }

  p_tab <- data.frame(
    Stratum = names(results_by_stratum),
    N = vapply(results_by_stratum, function(r) r$n, integer(1L)),
    Events = vapply(results_by_stratum, function(r) r$events, integer(1L)),
    Ref_SUA = vapply(results_by_stratum, function(r) round(r$ref_sua, 3), numeric(1L)),
    P_overall = pub_format_p(vapply(results_by_stratum, function(r) r$p_overall, numeric(1L))),
    P_nonlinear = pub_format_p(vapply(results_by_stratum, function(r) r$p_nonlin, numeric(1L))),
    stringsAsFactors = FALSE
  )
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_3_RCS_NHANES.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(p_tab, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_rcs_pub 数值表写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  thin57 <- NULL
  if (isTRUE(bl_cfg$also_run_thin57 %||% FALSE) &&
      exists("block_crm_rcs_sua", mode = "function")) {
    thin57 <- tryCatch({
      ctx_copy <- ctx
      ctx_copy <- block_crm_rcs_sua(ctx_copy)
      ctx_copy$results$crm_rcs
    }, error = function(e) {
      cli::cli_alert_warning("crm_nhanes_rcs_pub: also_run_thin57 冒烟对照失败: {e$message}")
      NULL
    })
  }

  ctx$results$crm_nhanes_rcs_pub <- list(
    strata = results_by_stratum,
    p_table = p_tab,
    skipped_strata = skipped_strata,
    adjust_vars = adjust_vars,
    figure_pdf = if (isTRUE(saved_pdf)) pdf_path else NA_character_,
    figure_png = if (isTRUE(saved_png)) png_path else NA_character_,
    table_path = tbl_path,
    thin57_comparison = thin57
  )
  cli::cli_alert_success(
    "crm_nhanes_rcs_pub 完成（strata={paste(names(results_by_stratum), collapse=',')}, skipped={paste(names(skipped_strata), collapse=',')}）"
  )
  ctx
}

register_block(
  "crm_nhanes_rcs_pub",
  block_crm_nhanes_rcs_pub,
  "NHANES 加权 RCS 发表图（正图 Figure 2：SUA vs 全因死亡，1/2/3/≥1 CRM 四面板）"
)
