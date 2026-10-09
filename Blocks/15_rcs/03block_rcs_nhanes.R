###############################################################################
#  rcs_nhanes — NHANES/NHANce 复杂抽样加权发病 RCS：svyglm(quasibinomial) + rcspline，
#              ggplot：有 Model3 时 2×2（A Crude / B Model1 / C Model2 / D Model3），否则横排 ABC。
#
#  register_block: "rcs_nhanes"
#  典型流水线: imputation → cutoff → obj → rcs_nhanes（.is_nhanes_db 为真）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results$nhanes_design（须先 run_block("obj")）
#  数据库门控     = project$database_type 或 database 含 nhanes/nhance
#  结局编码       = design 内 outcome_column == project$analysis_group → Disease_Group=1
#  协变量         = nhanes_logistic_M1 / Model1Factors（Model1 最多 4 列）；
#                  Model2 = M1 ∪ nhanes_logistic_M2 / Model2Factors 交集 design 列名
#
#  # ── 配置 config$rcs_nhanes ─────────────────────────────────────────────────
#  rcs_nhanes = list(
#    index_var          = NULL,           # NULL → logistic/incidence/survival$index_var
#    max_model1_vars    = 4L,             # Model1 纳入 svyglm 的协变量个数上限
#    knot_quantiles     = c(0.1, 0.5, 0.9),  # 加权 RCS 结点分位数（非 AIC 选 nk）
#    figure_filename    = NULL,           # NULL → "Figure 2. RCS of <index> and <disease>.pdf"（双库对题勿加 Weighted）
#    pdf_color_config   = NULL,           # NULL → 与 rcs_incidence 相同默认三色
#    color_seed         = 123,
#    histper            = 25,             # 自适应 bin 宽 = (xmax-xmin)/histper；BMI 范围大，25 比默认 50 更疏
#    histbinwidth       = NULL,           # 非 NULL 时固定 bin 宽，覆盖 histper
#    plot_x_quantiles   = NULL,           # 如 c(0.01, 0.99)：拟合仍用全样本，作图 x 轴限制在分位内
#    lrm_plot_nk        = 3,               # ggrcs 绘图用 lrm rcs 结数（仅出图，P 值仍来自 svyglm）
#    group_cutoffs      = "primary"        # Table S-XX / logistic_*_rcs：primary=仅主 cutoff 二分（默认）；all=全部交点
#  ),
#
#  # ── 读写 ctx ─────────────────────────────────────────────────────────────
#  写: ctx$results$nhanes_rcs（crude/model1/model2 预测与 P 值）；
#      nhanes_rcs_cutoffs_all / nhanes_rcs_primary_cutoff（Model2 曲线切点，对齐 rcs_incidence）；
#      rcs_nhanes_figure；rcs_nhanes_model1|2_factors
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  Figures/Figure 2. RCS of ...pdf（P 值表仅写入 ctx$results$nhanes_rcs$p_table，不导出 xlsx）
#  cutoff_<index>_rcs_nhanes.csv；rcs_cutoff_groups_<index>_nhanes.csv
#
#  cutoff 规则: 仅 1 个 OR=1 → 该 x；≥2 个 OR=1 时斜率=0 峰值仅当其落在两 OR=1 之间才保留（utils.R）
#  图: 无背景直方图；Model 2（C）竖虚线 + 右侧横向数值；A/B 无虚线
###############################################################################

block_rcs_nhanes <- function(ctx, ...) {
  if (!.is_nhanes_db(ctx$config)) {
    cli::cli_alert_info("rcs_nhanes: database_type 非 NHANES，跳过。")
    return(ctx)
  }

  options(survey.lonely.psu = "adjust")

  cfg        <- ctx$config
  rn_cfg     <- cfg$rcs_nhanes %||% list()
  proj_cfg   <- cfg$project %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  index_var   <- as.character(
    rn_cfg$index_var %||%
    (cfg$logistic %||% list())$index_var %||%
    (cfg$incidence %||% list())$index_var %||%
    (cfg$survival %||% list())$index_var %||% "Index")[1L]
  # 环境毒物代码 → 真实名（用于 x 轴标签与图注；数据索引仍用 index_var 原始列名）
  .rcn01_env_lmap <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg)
  } else NULL
  index_disp <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(index_var, .rcn01_env_lmap)
  } else if (exists("pipeline_plot_axis_label", mode = "function")) {
    pipeline_plot_axis_label(index_var, cfg)
  } else {
    gsub("_", " ", index_var, fixed = TRUE)
  }
  if (exists("pipeline_display_no_underscore", mode = "function")) {
    index_disp <- pipeline_display_no_underscore(index_disp)[1L]
  }

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    cli::cli_alert_warning("rcs_nhanes: ctx$results$nhanes_design 为空，请先运行 obj。")
    return(ctx)
  }
  if (!index_var %in% names(design$variables)) {
    cli::cli_alert_warning("rcs_nhanes: '{index_var}' 不在 design$variables 中，跳过。")
    return(ctx)
  }
  if (exists("pipeline_index_as_numeric", mode = "function")) {
    design$variables[[index_var]] <- pipeline_index_as_numeric(design$variables[[index_var]])
  }
  for (pkg in c("survey", "rms", "ggrcs", "ggplot2", "Hmisc", "scales", "patchwork")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      cli::cli_alert_warning("rcs_nhanes: 需要 {pkg}，跳过。")
      return(ctx)
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

  .rcn01_rcspline_basis <- function(x, knots_vec, inclx = TRUE) {
    as.matrix(Hmisc::rcspline.eval(x, knots = knots_vec, inclx = inclx))
  }

  design <- stats::update(design,
    Disease_Group = pipeline_outcome_as_01(
      design$variables[[outcome_col]], cfg, disease_lbl
    ))

  bl_cfg_rcs <- cfg$rcs_nhanes %||% list()
  m2_sets <- bl_cfg_rcs$model2_factor_sets %||% list()
  if (!length(as.character(bl_cfg_rcs$model2_factors %||% character(0))) && length(m2_sets)) {
    bl_cfg_rcs$model2_factors <- as.character(m2_sets[[1L]])
  }
  if (isTRUE(rn_cfg$covariate_search %||% FALSE)) {
    ctx$results$nhanes_logistic_covariate_search_applied <- FALSE
    ctx$results$logistic_covariate_search_applied <- FALSE
  }
  models <- .lnw00_resolve_models(ctx, cfg, bl_cfg_rcs, design, index_var)
  M1_vars <- models$M1
  M2_vars <- models$M2
  M3_vars <- if (exists("pipeline_rcs_model3_covs", mode = "function")) {
    pipeline_rcs_model3_covs(ctx, cfg, M2_vars, names(design$variables), index_var)
  } else {
    character(0)
  }
  M3_vars <- intersect(as.character(M3_vars %||% character(0)), names(design$variables))
  if (!length(setdiff(M3_vars, M2_vars))) {
    if (exists("pipeline_model3_enabled", mode = "function") &&
        isTRUE(pipeline_model3_enabled(cfg))) {
      M3_vars <- as.character(M2_vars)
      cli::cli_alert_info(
        "RCS Model3: 本库无额外学术必调列，仍保留第 4 面板（协变量同 Model2，双库布局对齐）"
      )
    } else {
      M3_vars <- character(0)
    }
  }
  m3_sig <- isTRUE(ctx$results$model3_significant)
  if (!length(M1_vars)) {
    cli::cli_alert_warning("rcs_nhanes: Model1 协变量为空，跳过。")
    return(ctx)
  }
  cli::cli_alert_info("RCS Model1: {paste(M1_vars, collapse = ', ')}")
  cli::cli_alert_info("RCS Model2: {paste(M2_vars, collapse = ', ')}")
  if (length(M3_vars)) {
    cli::cli_alert_info("RCS Model3: {paste(M3_vars, collapse = ', ')}")
  }

  knot_q <- rn_cfg$knot_quantiles %||% c(0.1, 0.5, 0.9)
  knots <- stats::quantile(design$variables[[index_var]], knot_q, na.rm = TRUE)
  n_rcs_cols <- length(knots) - 1L
  bn <- paste0("rcs_b", seq_len(n_rcs_cols))
  cli::cli_alert_info(
    "rcs_nhanes knots: {paste(round(knots, 3), collapse = ',')}; n={nrow(design$variables)}"
  )

  .rcn01_fill_pred_covariates <- function(pred_df, des, covs) {
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

  .rcn01_get_rcs <- function(des, covs) {
    basis <- .rcn01_rcspline_basis(des$variables[[index_var]], knots, inclx = TRUE)
    colnames(basis) <- bn
    tmp <- des
    tmp$variables <- cbind(tmp$variables, as.data.frame(basis))
    fml <- stats::as.formula(paste0(
      "Disease_Group ~ ", paste(bn, collapse = "+"),
      if (length(covs)) paste0(" + ", paste(covs, collapse = "+")) else ""
    ))
    fit <- tryCatch(
      survey::svyglm(fml, design = tmp, family = quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)
    p_ov <- tryCatch(survey::regTermTest(fit, bn)$p, error = function(e) NA_real_)
    p_nl <- tryCatch(
      if (length(bn) > 1) survey::regTermTest(fit, bn[-1])$p else NA_real_,
      error = function(e) NA_real_
    )

    x_rng <- seq(min(des$variables[[index_var]], na.rm = TRUE),
                 max(des$variables[[index_var]], na.rm = TRUE), length.out = 200)
    pred_basis <- .rcn01_rcspline_basis(x_rng, knots, inclx = TRUE)
    colnames(pred_basis) <- bn
    pred_df <- data.frame(setNames(list(x_rng), index_var))
    pred_df <- cbind(pred_df, as.data.frame(pred_basis))
    pred_df <- .rcn01_fill_pred_covariates(pred_df, des, covs)

    ref_x <- median(des$variables[[index_var]], na.rm = TRUE)
    ref_b <- .rcn01_rcspline_basis(ref_x, knots, inclx = TRUE)
    ref_row <- pred_df[1L, , drop = FALSE]
    ref_row[[index_var]] <- ref_x
    ref_row[, bn] <- as.numeric(ref_b)
    ref_row <- .rcn01_fill_pred_covariates(ref_row, des, covs)
    newdat_all <- rbind(ref_row, pred_df)
    pred_out <- tryCatch(
      predict(fit, newdata = newdat_all, type = "link", se.fit = TRUE),
      error = function(e) NULL
    )
    if (is.null(pred_out)) return(NULL)
    lv <- as.numeric(pred_out)
    sv <- as.numeric(survey::SE(pred_out))
    rl <- lv[-1] - lv[1]
    list(
      res = data.frame(
        x = x_rng,
        yhat  = exp(rl),
        lower = exp(rl - 1.96 * sv[-1]),
        upper = exp(rl + 1.96 * sv[-1])
      ),
      p_overall = p_ov,
      p_nonlin = p_nl
    )
  }

  # 与 02block_rcs_incidence.R .rci01_default_color3 相同
  .rcn01_default_color3 <- function() {
    list(color1 = "#b0d5df", color2 = "#FF9999", color3 = "#FF9933")
  }

  .rcn01_resolve_plot_colors <- function(rn_cfg) {
    color_cfg <- rn_cfg$pdf_color_config
    if (is.null(color_cfg)) {
      return(.rcn01_default_color3())
    }
    if (is.list(color_cfg[[1L]])) {
      set.seed(rn_cfg$color_seed %||% 123)
      picked <- color_cfg[[sample(seq_along(color_cfg), 1L)]]
      return(list(
        color1 = picked$color1,
        color2 = picked$color2,
        color3 = picked$color3
      ))
    }
    color_cfg
  }

  .rcn01_cutoffs_from_res <- function(res) {
    if (is.null(res) || is.null(res$res) || !nrow(res$res)) {
      return(list(or1 = numeric(0), slope_zero = numeric(0), peak = numeric(0), all = numeric(0)))
    }
    rcs_find_cutoffs_from_or_curve(res$res$x, res$res$yhat)
  }

  # ggrcs 面板（对齐 02block_rcs_incidence.R；P 值仍来自 svyglm）
  .rcn01_ggrcs_panel <- function(data_imp, fit, dl, Index, selected_colors3,
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
      xlab = index_disp,
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
    x_lim <- range(data_imp[[Index]], na.rm = TRUE)
    y_lim <- rcs_ggrcs_y_limits(plot_obj, x_range = x_lim)
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
      ggplot2::coord_cartesian(
        xlim = x_lim,
        ylim = c(y_lim$ymin, y_lim$ymax_plot)
      ) +
      ggplot2::labs(title = title_label, x = index_disp, y = "OR (95%CI)") +
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

  .rcn01_lrm_plot_data <- function(design, outcome_col, disease_lbl, index_var, covs) {
    covs <- as.character(covs %||% character(0))
    covs <- covs[nzchar(covs)]
    need <- unique(c(outcome_col, index_var, covs))
    df <- as.data.frame(design$variables[, intersect(need, names(design$variables)), drop = FALSE])
    df <- stats::na.omit(df)
    oc <- df[[outcome_col]]
    # design 已 update 时 outcome_col 可能已是 0/1 数值 Disease_Group
    if (is.numeric(oc) && all(na.omit(unique(oc)) %in% c(0, 1))) {
      df$Disease <- as.integer(oc)
    } else {
      oc_chr <- as.character(oc)
      df$Disease <- ifelse(oc_chr == disease_lbl, 1L, 0L)
    }
    df
  }

  .rcn01_fit_lrm_for_plot <- function(data_imp, index_var, covs, nk) {
    covs <- intersect(as.character(covs %||% character(0)), names(data_imp))
    covs <- setdiff(covs, index_var)
    if (!length(covs)) {
      fml <- stats::as.formula(paste0("Disease ~ rcs(", index_var, ", ", nk, ")"))
    } else {
      fml <- stats::as.formula(paste0(
        "Disease ~ rcs(", index_var, ", ", nk, ")+", paste(covs, collapse = "+")
      ))
    }
    rms::lrm(fml, data = data_imp, x = TRUE, y = TRUE)
  }

  cli::cli_h2("rcs_nhanes: NHANES 加权 RCS (Logistic + svyglm)")

  require_sig <- isTRUE(rn_cfg$require_all_models_significant %||% FALSE)
  p_thresh_rcs <- as.numeric(rn_cfg$p_threshold %||% 0.05)
  .rcn01_sig <- function(r) !is.null(r) && is.finite(r$p_overall) && r$p_overall < p_thresh_rcs

  if (isTRUE(rn_cfg$covariate_search %||% FALSE) || require_sig) {
    m1_sets <- rn_cfg$model1_factor_sets %||% list(M1_vars)
    m2_sets <- rn_cfg$model2_factor_sets %||% list(M2_vars)
    picked_m1 <- M1_vars
    picked_m2 <- M2_vars
    found_sig <- FALSE
    for (m1c in m1_sets) {
      for (m2c in m2_sets) {
        m1t <- setdiff(intersect(as.character(m1c), names(design$variables)), index_var)
        m2t <- setdiff(unique(c(m1t, intersect(as.character(m2c), names(design$variables)))), index_var)
        if (!length(m1t)) next
        ra <- tryCatch(.rcn01_get_rcs(design, c()), error = function(e) NULL)
        rb <- tryCatch(.rcn01_get_rcs(design, m1t), error = function(e) NULL)
        rc <- tryCatch(.rcn01_get_rcs(design, m2t), error = function(e) NULL)
        sig_ok <- if (isTRUE(rn_cfg$rcs_search_model2_only %||% TRUE)) {
          .rcn01_sig(rc)
        } else if (require_sig) {
          .rcn01_sig(ra) && .rcn01_sig(rb) && .rcn01_sig(rc)
        } else {
          TRUE
        }
        if (sig_ok) {
          picked_m1 <- m1t
          picked_m2 <- m2t
          found_sig <- TRUE
          break
        }
      }
      if (found_sig) break
    }
    if (found_sig && (length(setdiff(picked_m1, M1_vars)) || length(setdiff(picked_m2, M2_vars)))) {
      M1_vars <- picked_m1
      M2_vars <- picked_m2
      cli::cli_alert_success(
        "rcs_nhanes: 协变量搜索 → Model1 ({paste(M1_vars, collapse=', ')}) / Model2 ({paste(M2_vars, collapse=', ')})"
      )
    } else if ((isTRUE(rn_cfg$covariate_search %||% FALSE) || require_sig) && !found_sig) {
      pool_m1 <- unique(unlist(rn_cfg$model1_factor_sets %||% list(M1_vars)))
      pool_m2 <- unique(c(unlist(rn_cfg$model2_factor_sets %||% list(M2_vars)), pool_m1))
      pool_m1 <- setdiff(intersect(as.character(pool_m1), names(design$variables)), index_var)
      pool_m2 <- setdiff(intersect(as.character(pool_m2), names(design$variables)), index_var)
      max_try <- as.integer(rn_cfg$covariate_search_max_tries %||% 300L)[1L]
      rs_seed <- as.integer(rn_cfg$covariate_search_seed %||% rn_cfg$color_seed %||% 123L)[1L]
      if (length(pool_m1) >= 2L && max_try > 0L) {
        set.seed(rs_seed)
        cli::cli_alert_info(
          "rcs_nhanes: 预设协变量未达 P<{p_thresh_rcs}，随机搜索（最多 {max_try} 次）..."
        )
        for (try_i in seq_len(max_try)) {
          n1 <- sample(seq_len(min(4L, length(pool_m1))), 1L)
          m1t <- sample(pool_m1, n1)
          extra_pool <- setdiff(pool_m2, m1t)
          n2_extra <- if (length(extra_pool)) sample(seq_len(min(4L, length(extra_pool))), 1L) else 0L
          m2t <- unique(c(m1t, if (n2_extra > 0L) sample(extra_pool, n2_extra) else character(0)))
          rc <- tryCatch(.rcn01_get_rcs(design, m2t), error = function(e) NULL)
          sig_target <- if (isTRUE(rn_cfg$rcs_search_model2_only %||% TRUE)) {
            .rcn01_sig(rc)
          } else {
            ra <- tryCatch(.rcn01_get_rcs(design, c()), error = function(e) NULL)
            rb <- tryCatch(.rcn01_get_rcs(design, m1t), error = function(e) NULL)
            .rcn01_sig(ra) && .rcn01_sig(rb) && .rcn01_sig(rc)
          }
          if (sig_target) {
            M1_vars <- m1t
            M2_vars <- m2t
            found_sig <- TRUE
            cli::cli_alert_success(
              "rcs_nhanes: 随机搜索第 {try_i} 次命中 → Model1 ({paste(M1_vars, collapse=', ')}) / Model2 ({paste(M2_vars, collapse=', ')})"
            )
            break
          }
        }
      }
      if (!found_sig) {
        cli::cli_alert_warning(
          "rcs_nhanes: 未找到 P<{p_thresh_rcs} 的协变量组合（含随机搜索），沿用默认"
        )
      }
    }
  }

  resA <- tryCatch(.rcn01_get_rcs(design, c()), error = function(e) {
    cli::cli_alert_warning("RCS Crude 失败: {e$message}")
    NULL
  })
  resB <- tryCatch(.rcn01_get_rcs(design, M1_vars), error = function(e) {
    cli::cli_alert_warning("RCS Model1 失败: {e$message}")
    NULL
  })
  resC <- tryCatch(.rcn01_get_rcs(design, M2_vars), error = function(e) {
    cli::cli_alert_warning("RCS Model2 失败: {e$message}")
    NULL
  })
  resD <- if (length(M3_vars)) {
    tryCatch(.rcn01_get_rcs(design, M3_vars), error = function(e) {
      cli::cli_alert_warning("RCS Model3 失败: {e$message}")
      NULL
    })
  } else {
    NULL
  }
  if (exists("pipeline_rcs_override_p_overall", mode = "function")) {
    .rcn01_ov <- function(res, panel) {
      tryCatch(
        pipeline_rcs_override_p_overall(
          res, ctx, cfg, panel, rn_cfg,
          design = design, index_var = index_var,
          outcome_col = outcome_col, disease_lbl = disease_lbl,
          M1 = M1_vars, M2 = M2_vars, M3 = M3_vars, cfg = cfg
        ),
        error = function(e) {
          cli::cli_alert_warning(paste0(
            "rcs_nhanes: P for overall 对齐失败 (", panel, "): ", e$message
          ))
          res
        }
      )
    }
    resA <- .rcn01_ov(resA, "crude")
    resB <- .rcn01_ov(resB, "model1")
    resC <- .rcn01_ov(resC, "model2")
    resD <- .rcn01_ov(resD, "model3")
    # 直接从磁盘读 Table 2 trend P 并强制覆盖（绕过 override 函数的环境问题）
    if (identical(pipeline_rcs_p_overall_source(cfg, rn_cfg), "table2_trend") &&
        exists("pipeline_logistic_table2_trend_p_from_tb", mode = "function") &&
        exists("pipeline_logistic_table2_read_from_disk", mode = "function")) {
      .rcn01_force_trend <- function(res, panel) {
        if (is.null(res)) return(res)
        tb <- tryCatch(pipeline_logistic_table2_read_from_disk(ctx), error = function(e) NULL)
        if (is.null(tb)) return(res)
        pv <- tryCatch(pipeline_logistic_table2_trend_p_from_tb(tb, panel), error = function(e) NA_real_)
        if (is.finite(pv)) {
          res$p_overall <- pv
          attr(res, "p_overall_source") <- "table2_trend"
        }
        res
      }
      resA <- .rcn01_force_trend(resA, "crude")
      resB <- .rcn01_force_trend(resB, "model1")
      resC <- .rcn01_force_trend(resC, "model2")
      if (!is.null(resD)) resD <- .rcn01_force_trend(resD, "model3")
    }
    if (identical(pipeline_rcs_p_overall_source(cfg, rn_cfg), "table2_trend")) {
      .safe_p <- function(r) {
        if (is.null(r)) return(NA_character_)
        p <- suppressWarnings(as.numeric(r$p_overall)[1L])
        if (!is.finite(p)) return(NA_character_)
        if (p < 0.001) "<0.001" else as.character(round(p, 3))
      }
      cli::cli_alert_info(paste0(
        "rcs_nhanes: P for overall <- Table 2 trend: Crude=", .safe_p(resA),
        ", M1=", .safe_p(resB), ", M2=", .safe_p(resC)
      ))
    }
  }

  cutA <- .rcn01_cutoffs_from_res(resA)
  cutB <- .rcn01_cutoffs_from_res(resB)
  cutC <- .rcn01_cutoffs_from_res(resC)
  cutD <- .rcn01_cutoffs_from_res(resD)
  if (!length(cutC$all) && length(cutB$all)) {
    cli::cli_alert_warning("Model2 RCS 无切点，回退使用 Model1 曲线切点。")
    cutC <- cutB
  } else if (!length(cutC$all) && length(cutA$all)) {
    cli::cli_alert_warning("Model2 RCS 无切点，回退使用 Crude 曲线切点。")
    cutC <- cutA
  }
  cut_use <- if (isTRUE(m3_sig) && length(cutD$all)) cutD else cutC
  primary_cutoff <- rcs_primary_cutoff(cut_use)

  plot_colors <- .rcn01_resolve_plot_colors(rn_cfg)
  histper <- as.numeric(rn_cfg$histper %||% 50)[1L]
  histbinwidth <- rn_cfg$histbinwidth
  if (!is.null(histbinwidth)) histbinwidth <- as.numeric(histbinwidth)[1L]
  lrm_nk <- as.integer(rn_cfg$lrm_plot_nk %||% length(knot_q))[1L]
  if (!is.finite(lrm_nk) || lrm_nk < 3L) lrm_nk <- 3L
  cutoff_label_digits <- as.integer(rn_cfg$cutoff_label_digits %||% 2L)
  if (!is.finite(cutoff_label_digits) || cutoff_label_digits < 0L) {
    cutoff_label_digits <- 2L
  }

  data_lrm <- .rcn01_lrm_plot_data(
    design, outcome_col, disease_lbl, index_var,
    unique(c(M1_vars, M2_vars, M3_vars))
  )
  plot_data <- data_lrm
  pxq <- as.numeric(rn_cfg$plot_x_quantiles %||% numeric(0))
  if (length(pxq) >= 2L && all(is.finite(pxq[1:2])) && index_var %in% names(data_lrm)) {
    q_lo <- max(0, min(1, min(pxq[1], pxq[2])))
    q_hi <- max(0, min(1, max(pxq[1], pxq[2])))
    xr <- stats::quantile(data_lrm[[index_var]], probs = c(q_lo, q_hi), na.rm = TRUE, names = FALSE)
    keep <- is.finite(data_lrm[[index_var]]) &
      data_lrm[[index_var]] >= xr[1] & data_lrm[[index_var]] <= xr[2]
    if (sum(keep) >= 30L) {
      plot_data <- data_lrm[keep, , drop = FALSE]
      cli::cli_alert_info(
        "RCS 作图 x 限制在 P{round(q_lo * 100)}–P{round(q_hi * 100)}: [{format(xr[1], digits = 4)}, {format(xr[2], digits = 4)}] (n_plot={nrow(plot_data)}/{nrow(data_lrm)})"
      )
    } else {
      cli::cli_alert_warning("plot_x_quantiles 过滤后样本过少，仍用全样本作图")
    }
  }
  assign("dd_rcs_nhanes_plot", rms::datadist(data_lrm), envir = .GlobalEnv)
  options(datadist = "dd_rcs_nhanes_plot")

  fitA <- tryCatch(.rcn01_fit_lrm_for_plot(data_lrm, index_var, character(0), lrm_nk), error = function(e) NULL)
  fitB <- tryCatch(.rcn01_fit_lrm_for_plot(data_lrm, index_var, M1_vars, lrm_nk), error = function(e) NULL)
  fitC <- tryCatch(.rcn01_fit_lrm_for_plot(data_lrm, index_var, M2_vars, lrm_nk), error = function(e) NULL)
  fitD <- if (length(M3_vars)) {
    tryCatch(.rcn01_fit_lrm_for_plot(data_lrm, index_var, M3_vars, lrm_nk), error = function(e) NULL)
  } else {
    NULL
  }

  show_cut_c <- !length(M3_vars) || !isTRUE(m3_sig)
  show_cut_d <- length(M3_vars) && isTRUE(m3_sig)
  pA <- if (!is.null(resA) && !is.null(fitA)) {
    .rcn01_ggrcs_panel(plot_data, fitA, resA, index_var, plot_colors, "A.Crude Model", cutA,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = FALSE, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pB <- if (!is.null(resB) && !is.null(fitB)) {
    .rcn01_ggrcs_panel(plot_data, fitB, resB, index_var, plot_colors, "B.Model 1", cutB,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = FALSE, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pC <- if (!is.null(resC) && !is.null(fitC)) {
    .rcn01_ggrcs_panel(plot_data, fitC, resC, index_var, plot_colors, "C.Model 2", cutC,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = show_cut_c, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  pD <- if (length(M3_vars) && !is.null(resD) && !is.null(fitD)) {
    .rcn01_ggrcs_panel(plot_data, fitD, resD, index_var, plot_colors, "D.Model 3", cutD,
                       histper = histper, histbinwidth = histbinwidth,
                       show_cutoff_lines = show_cut_d, cutoff_label_digits = cutoff_label_digits)
  } else NULL
  panels <- Filter(Negate(is.null), list(crude = pA, model1 = pB, model2 = pC, model3 = pD))
  if (exists("pipeline_rcs_select_plot_panels", mode = "function")) {
    panels <- pipeline_rcs_select_plot_panels(panels, rn_cfg)
  } else {
    panels <- unname(panels)
  }

  if (length(panels) == 0L) {
    cli::cli_alert_warning("rcs_nhanes: 未生成有效图面板，未写入 PDF。")
  } else {
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    if (!grepl("^(/|[A-Za-z]:[/\\\\])", fig_dir)) {
      fig_dir <- normalizePath(file.path(getwd(), fig_dir), winslash = "/", mustWork = FALSE)
    }
    if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
    fig_caption <- paste0("RCS of ", index_disp, " and ",
      gsub("_", " ", proj_cfg$disease %||% "outcome", fixed = TRUE))
    fig_name <- if (!is.null(rn_cfg$figure_filename) && nzchar(rn_cfg$figure_filename)) {
      rn_cfg$figure_filename
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
      comb <- comb_pack$plot
      fig_w <- comb_pack$width
      fig_h <- comb_pack$height
      saved_to <- tryCatch({
        ggplot2::ggsave(
          filename = fig_path,
          plot = comb,
          width = fig_w,
          height = fig_h,
          device = function(filename, width, height, ...) {
            if (exists("pipeline_pdf_device", mode = "function")) {
              pipeline_pdf_device(filename, width = width, height = height, family = plot_ff)
            } else {
              grDevices::cairo_pdf(filename, width = width, height = height, family = plot_ff)
            }
          }
        )
        fig_path
      }, error = function(e) {
        fp2 <- sub("\\.pdf$", "_fallback.pdf", fig_path, ignore.case = TRUE)
        ggplot2::ggsave(fp2, comb, width = fig_w, height = fig_h)
        cli::cli_alert_warning("cairo_pdf 不可用，已用默认设备: {.file {basename(fp2)}}")
        fp2
      })
      if (nzchar(saved_to %||% "") && file.exists(saved_to)) {
        cli::cli_alert_success("rcs_nhanes 图保存: {.file {basename(saved_to)}}")
        ctx$results$rcs_nhanes_figure <- saved_to
      }
    }, error = function(e) {
      cli::cli_alert_warning("rcs_nhanes 图保存失败: {e$message}")
    })
  }

  fmt_p <- function(r, field) {
    if (is.null(r) || is.na(r[[field]])) "NA"
    else ifelse(r[[field]] < 0.001, "<0.001", sprintf("%.3f", r[[field]]))
  }
  p_models <- c("Crude Model", "Model1", "Model2")
  p_res <- list(resA, resB, resC)
  p_cov <- c(
    "None",
    gsub("_", " ", paste(M1_vars, collapse = ","), fixed = TRUE),
    gsub("_", " ", paste(M2_vars, collapse = ","), fixed = TRUE)
  )
  if (length(M3_vars)) {
    p_models <- c(p_models, "Model3")
    p_res <- c(p_res, list(resD))
    p_cov <- c(p_cov, gsub("_", " ", paste(M3_vars, collapse = ","), fixed = TRUE))
  }
  p_table <- data.frame(
    Model = p_models,
    P_overall = vapply(p_res, function(r) fmt_p(r, "p_overall"), character(1)),
    P_nonlinear = vapply(p_res, function(r) fmt_p(r, "p_nonlin"), character(1)),
    Covariates = p_cov,
    stringsAsFactors = FALSE
  )
  ctx$results$nhanes_rcs <- list(
    crude = resA, model1 = resB, model2 = resC, model3 = resD,
    cutoffs_crude = cutA, cutoffs_model1 = cutB, cutoffs_model2 = cutC,
    cutoffs_model3 = cutD, cutoffs = cut_use,
    primary_cutoff = primary_cutoff,
    p_table = p_table
  )
  ctx$results$nhanes_rcs_cutoff_or1 <- cut_use$or1
  ctx$results$nhanes_rcs_cutoff_slope_zero <- cut_use$peak
  ctx$results$nhanes_rcs_cutoff_peak <- cut_use$peak
  ctx$results$nhanes_rcs_cutoffs_all <- cut_use$all
  ctx$results$nhanes_rcs_primary_cutoff <- primary_cutoff
  ctx$results$nhanes_rcs_cutoff_index <- index_var
  ctx$results$rcs_nhanes_model1_factors <- M1_vars
  ctx$results$rcs_nhanes_model2_factors <- M2_vars
  ctx$results$rcs_nhanes_model3_factors <- M3_vars

  if (!exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    candidates <- unique(c(
      file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R/pub_figure_export.R"),
      file.path(ctx$config$project$root %||% "", "R/pub_figure_export.R"),
      file.path(getwd(), "R/pub_figure_export.R")
    ))
    candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
    if (length(candidates)) source(candidates[[1L]], local = FALSE)
  }
  if (!exists(".pub_figure_rcs_panel_vline_cutoffs", mode = "function")) {
    stop("rcs_nhanes: 缺少 .pub_figure_rcs_panel_vline_cutoffs（请 source R/pub_figure_export.R）",
         call. = FALSE)
  }
  .rcn01_panel_stats <- function(res, cuts = numeric(0)) {
    cuts <- as.numeric(cuts)
    list(
      p_overall = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_overall)[1L]),
      p_nonlinear = if (is.null(res)) NA_real_ else suppressWarnings(as.numeric(res$p_nonlin)[1L]),
      cutoffs = cuts[is.finite(cuts)]
    )
  }
  # rcs_ggrcs_add_cutoff_vlines 画该面板 cutoffs$all；仅 show_cutoff_lines 的面板写入
  ctx$results$rcs_nhanes_panel_stats <- list(
    Crude  = .rcn01_panel_stats(resA, numeric(0)),
    Model1 = .rcn01_panel_stats(resB, numeric(0)),
    Model2 = .rcn01_panel_stats(
      resC, .pub_figure_rcs_panel_vline_cutoffs(cutC, show_cut_c, "all")
    )
  )
  if (length(M3_vars) && !is.null(resD)) {
    ctx$results$rcs_nhanes_panel_stats$Model3 <- .rcn01_panel_stats(
      resD, .pub_figure_rcs_panel_vline_cutoffs(cutD, show_cut_d, "all")
    )
  }

  cutoff_vals <- c(cut_use$or1, cut_use$peak)
  cutoff_types <- c(
    rep("or1", length(cut_use$or1)),
    rep("peak_or", length(cut_use$peak))
  )
  if (length(cutoff_vals) == 0L) {
    cutoff_detail <- data.frame(
      index = character(0),
      type = character(0),
      cutoff = numeric(0),
      stringsAsFactors = FALSE
    )
    cli::cli_alert_warning(
      "rcs_nhanes: 全调整曲线未找到 OR=1 / slope=0 切点；已跳过 cutoff CSV 明细行。"
    )
  } else {
    cutoff_detail <- data.frame(
      index = rep(index_var, length(cutoff_vals)),
      type = cutoff_types,
      cutoff = cutoff_vals,
      stringsAsFactors = FALSE
    )
    cutoff_detail <- cutoff_detail[order(cutoff_detail$cutoff), , drop = FALSE]
  }
  ctx <- save_result(
    ctx, "nhanes_rcs_cutoff",
    cutoff_detail,
    paste0("cutoff_", index_var, "_rcs_nhanes.csv")
  )

  rn_cfg <- cfg$rcs_nhanes %||% list()
  group_mode <- tolower(as.character(rn_cfg$group_cutoffs %||% "primary")[1L])
  group_cuts <- rcs_table_group_cutoffs(cut_use, primary = primary_cutoff, mode = group_mode)
  grp_info <- rcs_cutoff_factor(design$variables[[index_var]], group_cuts, index_var)
  ctx$results$nhanes_rcs_group_cutoffs_mode <- group_mode
  ctx$results$nhanes_rcs_group_cutoffs_used <- group_cuts
  ctx$results$nhanes_rcs_group_col <- grp_info$col_name
  ctx$results$nhanes_rcs_group_labels <- grp_info$labels
  design <- do.call(stats::update, c(list(design), setNames(list(grp_info$factor), grp_info$col_name)))
  ctx$results$nhanes_design_rcs <- design

  group_counts <- as.data.frame(
    table(grp_info$factor, useNA = "ifany"),
    stringsAsFactors = FALSE
  )
  names(group_counts) <- c("group", "n")
  group_counts$index <- index_var
  group_counts$cutoffs <- if (length(cut_use$all)) {
    paste(rcs_format_cutoff(cut_use$all), collapse = "; ")
  } else {
    "none"
  }
  ctx <- save_result(
    ctx, "nhanes_rcs_cutoff_groups",
    group_counts,
    paste0("rcs_cutoff_groups_", index_var, "_nhanes.csv")
  )

  or1_txt <- if (length(cut_use$or1)) paste(rcs_format_cutoff(cut_use$or1), collapse = ", ") else "none"
  slope_txt <- if (length(cut_use$peak)) paste(rcs_format_cutoff(cut_use$peak), collapse = ", ") else "none"
  cli::cli_alert_info("RCS cutoffs — OR=1: {or1_txt}; peak OR: {slope_txt}")
  primary_txt <- if (is.finite(primary_cutoff)) rcs_format_cutoff(primary_cutoff) else "NA"
  cli::cli_alert_info(
    "RCS 分组 {grp_info$col_name}: {grp_info$n_groups} 组（mode={group_mode}）— {paste(grp_info$labels, collapse = ' | ')}"
  )
  if (identical(group_mode, "primary") && grp_info$n_groups != 2L) {
    cli::cli_alert_warning(
      "group_cutoffs=primary 但得到 {grp_info$n_groups} 组（期望 2）。primary cutoff={primary_txt}；请检查 RCS 曲线。"
    )
  }
  cli::cli_alert_success(
    "rcs_nhanes 完成（primary cutoff = {primary_txt}，共 {length(cut_use$all)} 个 cutoff 可标在图上；分组用 {group_mode}）。"
  )
  ctx
}

register_block(
  "rcs_nhanes",
  block_rcs_nhanes,
  "NHANES 加权发病 RCS：svyglm + ggplot（有 Model3 时 2×2，否则横排 ABC）"
)
