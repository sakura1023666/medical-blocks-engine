###############################################################################
#  bkmr_analysis — BKMR 结果分析：PIP 表、总体效应、单变量风险、剂量反应曲线
#
#  register_block: "bkmr_analysis"
#  典型流水线: bkmr_fit → bkmr_analysis
#
#  功能：
#    合并多链 BKMR 结果（kmbayes_combine）→
#    提取 PIP（Posterior Inclusion Probability）→ 导出 xlsx → Top-N 摘要文本；
#    计算总体联合效应（OverallRiskSummaries）→ 效应图（base R）；
#    计算单变量效应（SingVarRiskSummaries）→ ggplot2 条状图；
#    计算剂量-反应曲线（PredictorResponseUnivar）→ ggplot2 小图矩阵。
#
#  # ── Bug 修复说明（相对原 C01_BKMR_Analysis.R）────────────────────────────
#  Bug 1: top_5 <- BKMR_sorted[1:5,] 当 VOC 数 < 5 时越界产生 NA 行；
#         修复: head(..., min(top_n, nrow(...)))
#  Bug 2: plot(..., ph = 19, ...) 无 ph 参数（pch 的拼写错误）→ 改为 pch = 19
#  Bug 3: 死代码（stop() 后）kmbayes_parallel 参数 nchain → nchains（拼写错误）
#         修复: 此死代码已删除，仅保留分组 BKMR 作为可选功能
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = fit_bkmr, bkmr_Z, bkmr_y, bkmr_X
#                        （由 bkmr_fit block 写入；或通过 bkmr_fit_path 指定文件）
#
#  # ── 配置 config$bkmr_analysis ────────────────────────────────────────────
#  bkmr_analysis = list(
#    # ── 总体效应分位数范围 ────────────────────────────────────────────────
#    qs_overall        = NULL,   # NULL = seq(0.4, 0.6, by=0.02)
#    qs_diff           = NULL,   # NULL = c(0.4, 0.6)（单变量效应差值分位数）
#    q_fixed           = NULL,   # NULL = c(0.4, 0.5, 0.6)（固定其他变量的分位数）
#    # ── Top-N PIP 摘要 ─────────────────────────────────────────────────────
#    top_n_pip         = 5L,
#    # ── 标签映射（VOC 内部列名 → 显示名） ─────────────────────────────────
#    label_mapping     = NULL,   # 命名向量 c(URXBCD = "Cadmium", ...)
#    # ── 输出文件名 ─────────────────────────────────────────────────────────
#    table_pip_filename = NULL,  # NULL = "Table_BKMR_PIP.xlsx"
#    table_pip_title    = NULL,
#    fig_overall_filename = NULL, # NULL = "Figure_BKMR_Overall.pdf"
#    fig_singvar_filename = NULL, # NULL = "Figure_BKMR_SingVar.pdf"
#    fig_univar_filename  = NULL  # NULL = "Figure_BKMR_DoseResponse.pdf"
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$bkmr_combined     — kmbayes_combine 合并后的模型
#      ctx$results$bkmr_pip_table    — PIP data.frame
#      ctx$results$bkmr_top_pip_text — Top-N PIP 摘要文本
#      ctx$results$risks_overall     — OverallRiskSummaries 结果
#      ctx$results$risks_singvar     — SingVarRiskSummaries 结果
#      ctx$results$pred_resp_univar  — PredictorResponseUnivar 结果
#  文件: Figures/Figure_BKMR_Overall.pdf
#        Figures/Figure_BKMR_SingVar.pdf
#        Figures/Figure_BKMR_DoseResponse.pdf
#        Tables/Table_BKMR_PIP.xlsx
###############################################################################

# ── 辅助：应用标签映射到变量列 ──────────────────────────────────────────────
.bkmr38_as_numeric_matrix <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) {
    for (nm in names(x)) {
      if (!is.numeric(x[[nm]])) {
        x[[nm]] <- suppressWarnings(as.numeric(as.factor(trimws(as.character(x[[nm]])))))
      }
    }
    x <- as.matrix(x)
  } else {
    x <- as.matrix(x)
  }
  storage.mode(x) <- "double"
  x[!is.finite(x)] <- 0
  if (nrow(x) < 1L || ncol(x) < 1L) return(NULL)
  x
}

.bkmr38_apply_label_map <- function(x, label_map) {
  if (is.null(label_map) || !length(label_map)) return(x)
  vapply(as.character(x), function(v) {
    if (v %in% names(label_map)) as.character(label_map[[v]]) else v
  }, character(1L))
}

# ── 辅助：Top-N PIP 文本（修复 Bug 1：head 替代硬编码 [1:5,]）────────────────
.bkmr38_top_pip_text <- function(pip_df, label_map = NULL, top_n = 5L) {
  if (is.null(pip_df) || !nrow(pip_df)) return("")
  sorted  <- pip_df[order(pip_df$PIP, decreasing = TRUE), , drop = FALSE]
  # 修复 Bug 1：避免越界
  top_n   <- min(as.integer(top_n), nrow(sorted))
  top_df  <- head(sorted, top_n)
  top_df$variable <- .bkmr38_apply_label_map(top_df$variable, label_map)
  parts <- vapply(seq_len(nrow(top_df)), function(i) {
    paste0(top_df$variable[i], " (", round(top_df$PIP[i], 4L), ")")
  }, character(1L))
  paste(parts, collapse = "\u3001")
}

# ── 辅助：总体联合效应图（修复 Bug 2：ph → pch）────────────────────────────
.bkmr38_plot_overall <- function(risks_overall, disease_name = "") {
  with(risks_overall, {
    y_lo <- min(est - 1.96 * sd, na.rm = TRUE)
    y_hi <- max(est + 1.96 * sd, na.rm = TRUE)
    graphics::plot(
      quantile, est,
      pch  = 19,         # 修复 Bug 2：原代码为 ph = 19（无效参数）
      ylim = c(y_lo, y_hi),
      axes = FALSE,
      ylab = "Mean difference",
      xlab = "Joint quantile",
      main = if (nzchar(disease_name)) paste0("Overall effect (", disease_name, ")") else "Overall joint effect"
    )
    graphics::segments(x0 = quantile, x1 = quantile,
                       y0 = est - 1.96 * sd, y1 = est + 1.96 * sd)
    graphics::abline(h = 0, lty = 2, col = "grey60")
    graphics::axis(1)
    graphics::axis(2)
    graphics::box(bty = "l")
  })
}

# ── 辅助：单变量效应 ggplot ──────────────────────────────────────────────────
.bkmr38_plot_singvar <- function(risks_singvar, label_map = NULL) {
  df <- risks_singvar
  df$variable <- .bkmr38_apply_label_map(as.character(df$variable), label_map)
  df$q.fixed  <- as.factor(df$q.fixed)
  ggplot2::ggplot(df,
    ggplot2::aes(x = variable, y = est,
                 ymin = est - 1.96 * sd, ymax = est + 1.96 * sd,
                 col = q.fixed)) +
    ggplot2::geom_pointrange(position = ggplot2::position_dodge(width = 0.75)) +
    ggplot2::coord_flip() +
    ggplot2::labs(x = "", y = "Estimate", color = "q.fixed") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.title  = ggplot2::element_text(family = "serif", size = 12),
      axis.text   = ggplot2::element_text(family = "serif", size = 11),
      legend.title = ggplot2::element_text(family = "serif", size = 11),
      legend.text  = ggplot2::element_text(family = "serif", size = 11),
      legend.position = "top"
    )
}

# ── 辅助：剂量-反应曲线 ggplot（单变量，正方形）────────────────────────────
.bkmr38_plot_doseresponse_one <- function(pred_resp, voc_name, label_map = NULL) {
  df <- pred_resp[pred_resp$variable == voc_name, , drop = FALSE]
  if (!nrow(df)) return(NULL)
  df$variable <- .bkmr38_apply_label_map(as.character(df$variable), label_map)
  ggplot2::ggplot(df,
    ggplot2::aes(x = z, y = est,
                 ymin = est - 1.96 * se, ymax = est + 1.96 * se)) +
    ggplot2::geom_ribbon(fill = "grey85", alpha = 0.6) +
    ggplot2::geom_line(colour = "#223D6C", linewidth = 0.9) +
    ggplot2::labs(
      title = unique(df$variable)[1L],
      y = "h(z)", x = "Standardized exposure"
    ) +
    ggplot2::coord_fixed(ratio = 1, xlim = range(df$z, na.rm = TRUE),
                         ylim = range(c(df$est - 1.96 * df$se, df$est + 1.96 * df$se), na.rm = TRUE)) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      plot.title  = ggplot2::element_text(family = "serif", size = 11, hjust = 0.5),
      axis.title  = ggplot2::element_text(family = "serif", size = 11),
      axis.text   = ggplot2::element_text(family = "serif", size = 10)
    )
}

# ── 辅助：剂量-反应曲线 ggplot（分面，等宽高 panel）──────────────────────────
.bkmr38_plot_doseresponse <- function(pred_resp, label_map = NULL) {
  df <- pred_resp
  df$variable <- .bkmr38_apply_label_map(as.character(df$variable), label_map)
  ggplot2::ggplot(df,
    ggplot2::aes(x = z, y = est,
                 ymin = est - 1.96 * se, ymax = est + 1.96 * se)) +
    ggplot2::geom_ribbon(fill = "grey85", alpha = 0.5) +
    ggplot2::geom_line(colour = "#223D6C", linewidth = 0.8) +
    ggplot2::facet_wrap(~ variable, scales = "free") +
    ggplot2::labs(y = "h(z)", x = "Standardized exposure") +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.title  = ggplot2::element_text(family = "serif", size = 12),
      axis.text   = ggplot2::element_text(family = "serif", size = 9),
      strip.text  = ggplot2::element_text(family = "serif", size = 10),
      aspect.ratio = 1
    )
}

# ── 辅助：openxlsx SCI 三线表导出 ─────────────────────────────────────────────
.bkmr38_export_xlsx <- function(df, filepath, title) {
  library(openxlsx)
  wb  <- createWorkbook()
  addWorksheet(wb, "Sheet1")
  writeData(wb, "Sheet1", df,    startRow = 2L, startCol = 1L, rowNames = FALSE)
  writeData(wb, "Sheet1", title, startRow = 1L, startCol = 1L)

  n_col <- ncol(df)
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12)
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  mergeCells(wb, "Sheet1", cols = 1:n_col, rows = 1L)
  addStyle(wb, "Sheet1", title_style,  rows = 1L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", header_style, rows = 2L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,
           rows = 3L:(nrow(df) + 2L), cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = nrow(df) + 3L, cols = 1:(n_col + 1L), gridExpand = FALSE)

  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:(n_col + 1L), widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 30)
  setColWidths(wb, "Sheet1", cols = 2L, widths = 20)
  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_bkmr_analysis <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(bkmr)
    library(bkmrhat)
    library(ggplot2)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$bkmr_analysis %||% list()

  # ── 读取拟合结果 ─────────────────────────────────────────────────────────
  fit_bkmr <- ctx$results$fit_bkmr
  if (is.null(fit_bkmr) || isTRUE(ctx$results$bkmr_fit_skipped)) {
    cli::cli_alert_warning("bkmr_analysis: fit_bkmr 为空，跳过 BKMR 分析。")
    return(ctx)
  }
  bkmr_Z       <- ctx$results$bkmr_Z
  bkmr_y       <- ctx$results$bkmr_y
  bkmr_X       <- ctx$results$bkmr_X
  select_vocs  <- as.character(ctx$results$bkmr_select_vocs %||% character(0))

  Z_mat <- .bkmr38_as_numeric_matrix(bkmr_Z)
  y_vec <- as.numeric(bkmr_y)
  X_mat <- .bkmr38_as_numeric_matrix(bkmr_X)
  if (is.null(Z_mat) || length(y_vec) != nrow(Z_mat)) {
    stop("bkmr_analysis: Z/y 维度不一致或为空。", call. = FALSE)
  }
  if (!is.null(X_mat) && nrow(X_mat) != length(y_vec)) {
    cli::cli_alert_warning("bkmr_analysis: X 行数与 y 不一致，将不使用协变量矩阵。")
    X_mat <- NULL
  }

  disease_name <- as.character(
    cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  )
  label_map    <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$label_mapping)
  } else bl_cfg$label_mapping
  top_n        <- as.integer(bl_cfg$top_n_pip %||% 5L)

  # ── 合并多链 MCMC ────────────────────────────────────────────────────────
  cli::cli_h2("bkmr_analysis: \u5408\u5e76\u591a\u94fe MCMC \u7ed3\u679c")
  fitkmccomb <- tryCatch(
    bkmrhat::kmbayes_combine(fit_bkmr),
    error = function(e) stop("bkmr_analysis: kmbayes_combine \u5931\u8d25: ", e$message, call. = FALSE)
  )
  ctx$results$bkmr_combined <- fitkmccomb

  # ── 提取 PIP 并导出 ───────────────────────────────────────────────────────
  cli::cli_h2("bkmr_analysis: \u63d0\u53d6 PIP")
  pip_raw <- tryCatch(
    data.frame(bkmr::ExtractPIPs(fitkmccomb)),
    error = function(e) {
      cli::cli_alert_warning("ExtractPIPs \u5931\u8d25: {e$message}")
      NULL
    }
  )

  pip_df <- NULL
  if (!is.null(pip_raw)) {
    pip_df <- pip_raw
    pip_df$variable <- .bkmr38_apply_label_map(pip_df$variable, label_map)
    ctx$results$bkmr_pip_table <- pip_df

    top_text <- .bkmr38_top_pip_text(pip_raw, label_map, top_n)
    ctx$results$bkmr_top_pip_text <- top_text
    cli::cli_alert_info("bkmr_analysis Top-{top_n} PIP: {top_text}")

    # 导出 xlsx
    tbl_dir  <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    tbl_fn   <- as.character(bl_cfg$table_pip_filename %||% "Table_BKMR_PIP.xlsx")
    tbl_title <- as.character(bl_cfg$table_pip_title %||%
      paste0("Table. PIP values in BKMR model (", disease_name, ")"))
    tryCatch({
      .bkmr38_export_xlsx(pip_df, file.path(tbl_dir, tbl_fn), tbl_title)
      cli::cli_alert_success("{tbl_fn} \u5df2\u5c55\u5b58")
    }, error = function(e) {
      cli::cli_alert_warning("PIP \u8868\u5c55\u5b58\u5931\u8d25: {e$message}")
    })
  }

  output_dir_figures <- file.path(ctx$output_dir %||% ".", "Figures")
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)

  # ── 总体联合效应（OverallRiskSummaries）──────────────────────────────────
  cli::cli_h2("bkmr_analysis: \u8ba1\u7b97\u603b\u4f53\u8054\u5408\u6548\u5e94")
  qs_overall <- bl_cfg$qs_overall %||% seq(0.4, 0.6, by = 0.02)

  risks_overall <- tryCatch(
    bkmr::OverallRiskSummaries(
      fit    = fitkmccomb,
      X      = X_mat,
      y      = y_vec,
      Z      = Z_mat,
      qs     = qs_overall,
      method = "exact"
    ),
    error = function(e) {
      cli::cli_alert_warning("OverallRiskSummaries \u5931\u8d25: {e$message}")
      NULL
    }
  )

  if (!is.null(risks_overall)) {
    ctx$results$risks_overall <- risks_overall
    fig_fn  <- as.character(bl_cfg$fig_overall_filename %||% "Figure_BKMR_Overall.pdf")
    fig_path <- file.path(output_dir_figures, fig_fn)
    tryCatch({
      grDevices::pdf(fig_path, height = 4, width = 6)
      .bkmr38_plot_overall(risks_overall, disease_name)
      grDevices::dev.off()
      cli::cli_alert_success("{fig_fn} \u5df2\u4fdd\u5b58")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("\u603b\u4f53\u6548\u5e94\u56fe\u5931\u8d25: {e$message}")
    })
  }

  # ── 单变量效应（SingVarRiskSummaries）────────────────────────────────────
  cli::cli_h2("bkmr_analysis: \u8ba1\u7b97\u5355\u53d8\u91cf\u6548\u5e94")
  qs_diff <- as.numeric(bl_cfg$qs_diff  %||% c(0.4, 0.6))
  q_fixed <- as.numeric(bl_cfg$q_fixed  %||% c(0.4, 0.5, 0.6))

  risks_singvar <- tryCatch(
    bkmr::SingVarRiskSummaries(
      fit     = fitkmccomb,
      X       = X_mat,
      y       = y_vec,
      Z       = Z_mat,
      qs.diff = qs_diff,
      q.fixed = q_fixed
    ),
    error = function(e) {
      cli::cli_alert_warning("SingVarRiskSummaries \u5931\u8d25: {e$message}")
      NULL
    }
  )

  if (!is.null(risks_singvar)) {
    # 应用标签映射
    risks_singvar$variable <- .bkmr38_apply_label_map(
      as.character(risks_singvar$variable), label_map
    )
    ctx$results$risks_singvar <- risks_singvar
    fig_fn   <- as.character(bl_cfg$fig_singvar_filename %||% "Figure_BKMR_SingVar.pdf")
    fig_path <- file.path(output_dir_figures, fig_fn)
    n_vars   <- length(unique(risks_singvar$variable))
    sq_side  <- as.numeric(bl_cfg$fig_square_inches %||% 5)[1L]
    tryCatch({
      ggplot2::ggsave(
        filename = fig_path,
        plot     = .bkmr38_plot_singvar(risks_singvar) +
          ggplot2::theme(aspect.ratio = 1),
        width    = sq_side,
        height   = sq_side
      )
      cli::cli_alert_success("{fig_fn} \u5df2\u4fdd\u5b58")
      if (isTRUE(bl_cfg$export_per_voc_figures %||% FALSE)) {
        for (v in unique(risks_singvar$variable)) {
          v_safe <- gsub("[^A-Za-z0-9_]+", "_", v)
          v_path <- file.path(output_dir_figures,
            paste0("Figure_BKMR_SingVar_", v_safe, ".pdf"))
          ggplot2::ggsave(
            filename = v_path,
            plot     = .bkmr38_plot_singvar(
              risks_singvar[risks_singvar$variable == v, , drop = FALSE]
            ) + ggplot2::theme(aspect.ratio = 1),
            width = sq_side, height = sq_side
          )
        }
      }
    }, error = function(e) {
      cli::cli_alert_warning("\u5355\u53d8\u91cf\u6548\u5e94\u56fe\u5931\u8d25: {e$message}")
    })
  }

  # ── 剂量-反应曲线（PredictorResponseUnivar）──────────────────────────────
  cli::cli_h2("bkmr_analysis: \u8ba1\u7b97\u5269\u91cf-\u53cd\u5e94\u66f2\u7ebf")
  pred_resp <- tryCatch(
    bkmr::PredictorResponseUnivar(fit = fitkmccomb),
    error = function(e) {
      cli::cli_alert_warning("PredictorResponseUnivar \u5931\u8d25: {e$message}")
      NULL
    }
  )

  if (!is.null(pred_resp)) {
    pred_resp$variable <- .bkmr38_apply_label_map(
      as.character(pred_resp$variable), label_map
    )
    ctx$results$pred_resp_univar <- pred_resp
    fig_fn   <- as.character(bl_cfg$fig_univar_filename %||% "Figure_BKMR_DoseResponse.pdf")
    fig_path <- file.path(output_dir_figures, fig_fn)
    n_vars   <- length(unique(pred_resp$variable))
    n_cols   <- min(4L, n_vars)
    n_rows   <- ceiling(n_vars / n_cols)
    sq_side  <- as.numeric(bl_cfg$fig_square_inches %||% 5)[1L]
    tryCatch({
      ggplot2::ggsave(
        filename = fig_path,
        plot     = .bkmr38_plot_doseresponse(pred_resp, label_map),
        width    = n_cols * sq_side,
        height   = n_rows * sq_side
      )
      raw_vars <- unique(as.character(pred_resp$variable))
      if (isTRUE(bl_cfg$export_per_voc_figures %||% FALSE)) {
        for (v in raw_vars) {
          v_safe <- gsub("[^A-Za-z0-9_]+", "_", v)
          one_plot <- .bkmr38_plot_doseresponse_one(pred_resp, v, label_map)
          if (!is.null(one_plot)) {
            ggplot2::ggsave(
              filename = file.path(output_dir_figures,
                paste0("Figure_BKMR_DoseResponse_", v_safe, ".pdf")),
              plot = one_plot, width = sq_side, height = sq_side
            )
          }
        }
      }
      cli::cli_alert_success("{fig_fn} \u5df2\u4fdd\u5b58")
    }, error = function(e) {
      cli::cli_alert_warning("\u5265\u91cf\u53cd\u5e94\u56fe\u5931\u8d25: {e$message}")
    })
  }

  cli::cli_alert_success("bkmr_analysis \u5b8c\u6210\u3002")
  ctx
}

register_block(
  "bkmr_analysis",
  block_bkmr_analysis,
  "BKMR \u7ed3\u679c\u5206\u6790: PIP \u8868\u3001\u603b\u4f53\u6548\u5e94\u56fe\u3001\u5355\u53d8\u91cf\u98ce\u9669\u56fe\u3001\u5265\u91cf\u53cd\u5e94\u66f2\u7ebf"
)
