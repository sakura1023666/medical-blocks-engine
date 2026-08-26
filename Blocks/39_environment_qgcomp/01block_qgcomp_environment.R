###############################################################################
#  qgcomp_environment — 环境混合暴露分位数 g-computation（qgcomp）分析
#
#  register_block: "qgcomp_environment"
#  典型流水线: glm_environment_quartile → qgcomp_environment
#
#  功能：
#    用 qgcomp::qgcomp.noboot 对环境暴露混合物做 Quantile g-computation 分析；
#    提取正向/负向权重 → 生成权重条形图（ggplot2）+ 导出系数表（xlsx）；
#    输出正向/负向前 N 名暴露文本（用于报告）。
#
#  # ── Bug 修复说明（相对原 C01_qgcomp.R）──────────────────────────────────
#  Bug 1: df[,-1] 按位置删列不稳定 → 改为按列名操作
#  Bug 2: 公式只含 VOC 无协变量（纯 crude）→ 新增 covariates 参数支持调整模型
#  Bug 3: scale_y_continuous(limits = c(-1,1)) 硬编码 y 轴 → 支持动态范围
#  Bug 4: 标注偏移量 Value*0.1 对接近 0 的权重会叠压 → 改为固定 offset
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = select_vocs_final（或 select_vocs）
#  可选 ctx_results    = final_features / Model2Factors
#
#  # ── 配置 config$qgcomp_environment ───────────────────────────────────────
#  qgcomp_environment = list(
#    select_vocs      = NULL,          # VOC 列名；NULL = ctx$results$select_vocs_final
#    covariates       = NULL,          # 协变量；NULL = ctx$results$final_features
#                                      # 不填则为 Crude Model（无协变量调整）
#    outcome_col      = NULL,          # 结局列名；NULL = config$data$outcome_column
#    analysis_group   = NULL,          # 病例组标签（编码为 1）
#    reference_group  = NULL,          # 对照组标签（编码为 0）
#    q                = 4L,            # 分位数 q（默认四分位）
#    seed             = 2023L,
#    label_mapping    = NULL,          # 命名向量 c(内部列名 = "展示名")，可选
#    top_n            = 3L,            # 正/负方向前 N 名文本摘要
#    y_limits         = NULL,          # NULL = 自动（±max(|weight|)+buffer）; c(-1,1) 固定
#    table_filename   = NULL,          # NULL = "Table_QGComp_Environment.xlsx"
#    table_title      = NULL,
#    fig_filename     = NULL           # NULL = "Figure_QGComp_Weights.pdf"
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$qgcomp_fit          — qgcomp.noboot 拟合对象
#      ctx$results$qgcomp_weights_df   — 权重 data.frame（Factors, Value, Direction）
#      ctx$results$qgcomp_top3_text    — 正向前 N 名文本
#      ctx$results$qgcomp_bottom3_text — 负向前 N 名文本
#      ctx$results$qgcomp_coef_table   — 系数/OR 表 data.frame
#  文件: Tables/Table_QGComp_Environment.xlsx
#        Figures/Figure_QGComp_Weights.pdf
###############################################################################

# ── 辅助：构建 qgcomp 公式 ───────────────────────────────────────────────────
.qgc39_build_formula <- function(outcome_col, select_vocs, covariates = NULL) {
  vars <- unique(c(select_vocs, as.character(covariates %||% character(0))))
  stats::as.formula(paste0(outcome_col, " ~ ", paste(vars, collapse = " + ")))
}

# ── 辅助：提取正/负权重 data.frame ──────────────────────────────────────────
.qgc39_extract_weights_df <- function(qgc_fit) {
  pos_wts <- qgc_fit[["pos.weights"]]
  neg_wts <- qgc_fit[["neg.weights"]]

  factors <- c(
    if (!is.null(pos_wts) && length(pos_wts)) names(pos_wts),
    if (!is.null(neg_wts) && length(neg_wts)) names(neg_wts)
  )
  values <- c(
    if (!is.null(pos_wts) && length(pos_wts)) as.numeric(pos_wts),
    if (!is.null(neg_wts) && length(neg_wts)) -as.numeric(neg_wts)
  )
  direction <- c(
    if (!is.null(pos_wts) && length(pos_wts)) rep("positive", length(pos_wts)),
    if (!is.null(neg_wts) && length(neg_wts)) rep("negative", length(neg_wts))
  )

  if (!length(factors)) return(data.frame())
  data.frame(
    Factors   = factors,
    Value     = values,
    Direction = direction,
    stringsAsFactors = FALSE
  )
}

# ── 辅助：提取 qgcomp 底层 glm 系数表（对齐 VOC 最终/C01_qgcomp.R Table S19 CSV）────
.qgc39_extract_coef_table <- function(qgc_fit) {
  fit <- qgc_fit$fit
  if (is.null(fit)) return(NULL)
  sm <- tryCatch(summary(fit), error = function(e) NULL)
  if (is.null(sm) || is.null(sm$coefficients)) return(NULL)
  df <- as.data.frame(sm$coefficients, stringsAsFactors = FALSE)
  df
}

# ── 辅助：提取 OR 表（qgcomp summary 的列顺序：Estimate, SE, Lower CI, Upper CI）
.qgc39_extract_or_table <- function(qgc_fit) {
  sm <- tryCatch(summary(qgc_fit), error = function(e) NULL)
  if (is.null(sm)) return(NULL)
  coef_mat <- tryCatch(sm$coefficients, error = function(e) NULL)
  if (is.null(coef_mat)) return(NULL)

  # 仅取 Estimate（1）、Lower CI（3）、Upper CI（4）并指数化为 OR
  if (ncol(coef_mat) >= 4L) {
    or_mat <- round(exp(coef_mat[, c(1L, 3L, 4L), drop = FALSE]), 2L)
    colnames(or_mat) <- c("OR", "Lower_CI", "Upper_CI")
  } else {
    or_mat <- round(exp(coef_mat[, 1L, drop = FALSE]), 2L)
    colnames(or_mat) <- "OR"
  }
  df <- as.data.frame(or_mat, stringsAsFactors = FALSE)
  df$Variable <- rownames(df)
  df <- df[, c("Variable", setdiff(names(df), "Variable"))]
  rownames(df) <- NULL
  df
}

# ── 辅助：正/负权重前 N 名文本 ───────────────────────────────────────────────
.qgc39_top_n_text <- function(wts_df, direction, n, label_map = NULL) {
  if (is.null(wts_df) || !nrow(wts_df)) return("")
  sub <- if (direction == "positive") {
    wts_df[wts_df$Direction == "positive" & wts_df$Value > 0, ]
  } else {
    wts_df[wts_df$Direction == "negative" & wts_df$Value < 0, ]
  }
  if (!nrow(sub)) return("")

  sorted <- if (direction == "positive") {
    sub[order(-sub$Value), ]
  } else {
    sub[order(sub$Value), ]
  }
  top <- head(sorted, min(as.integer(n), nrow(sorted)))

  # 应用标签映射
  if (!is.null(label_map) && length(label_map)) {
    top$Factors <- vapply(top$Factors, function(x) {
      if (x %in% names(label_map)) as.character(label_map[[x]]) else x
    }, character(1L))
  }

  parts <- vapply(seq_len(nrow(top)), function(i) {
    paste0(top$Factors[i], "\uff08", format(round(top$Value[i], 4L), nsmall = 4L), "\uff09")
  }, character(1L))
  paste(parts, collapse = "\u3001")
}

# ── 辅助：权重条形图 ─────────────────────────────────────────────────────────
.qgc39_plot_weights <- function(wts_df, label_map = NULL, y_limits = NULL) {
  df <- wts_df
  if (!nrow(df)) {
    ggplot2::ggplot() + ggplot2::labs(title = "No weights available")
    return()
  }

  # 应用标签映射
  if (!is.null(label_map) && length(label_map)) {
    df$Factors <- vapply(df$Factors, function(x) {
      if (x %in% names(label_map)) as.character(label_map[[x]]) else x
    }, character(1L))
  }

  df <- df[order(df$Value), ]
  df$Factors <- factor(df$Factors, levels = df$Factors, ordered = TRUE)

  # 动态 y 轴范围（修复 Bug 3）
  max_abs <- max(abs(df$Value), na.rm = TRUE)
  if (!is.null(y_limits) && length(y_limits) == 2L) {
    ylim_val <- y_limits
  } else {
    buf      <- max(max_abs * 0.15, 0.05)
    ylim_val <- c(-(max_abs + buf), max_abs + buf)
  }
  y_breaks <- pretty(ylim_val, n = 5)

  # 文字偏移（修复 Bug 4：固定偏移避免小值时叠压）
  offset <- max_abs * 0.08
  label_pos <- ifelse(df$Value >= 0, df$Value + offset, df$Value - offset)

  ggplot2::ggplot(df, ggplot2::aes(x = Factors, y = Value)) +
    ggplot2::geom_bar(
      stat = "identity",
      ggplot2::aes(fill = Direction)
    ) +
    ggplot2::scale_fill_manual(
      values = c(positive = "#e56b6f", negative = "#6d9dc5"),
      guide  = "none"
    ) +
    ggplot2::coord_flip() +
    ggplot2::geom_text(
      ggplot2::aes(y = label_pos, label = format(round(Value, 4L), nsmall = 4L)),
      color = "black", size = 3.5, fontface = "bold"
    ) +
    ggplot2::scale_y_continuous(
      limits = ylim_val,
      breaks = y_breaks,
      labels = scales::label_number(accuracy = 0.01)
    ) +
    ggplot2::labs(
      x    = "",
      y    = "Negative weights                    Positive weights"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      panel.grid.major  = ggplot2::element_blank(),
      panel.grid.minor  = ggplot2::element_blank(),
      text              = ggplot2::element_text(family = "serif", size = 12),
      legend.position   = "none"
    )
}

# ── 辅助：openxlsx SCI 三线表导出 ─────────────────────────────────────────────
.qgc39_export_xlsx <- function(df, filepath, title) {
  library(openxlsx)
  wb <- createWorkbook()
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

  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_qgcomp_environment <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(qgcomp)
    library(ggplot2)
    library(scales)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$qgcomp_environment %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("qgcomp_environment: \u672a\u627e\u5230\u6570\u636e\uff0c\u8bf7\u5148\u8fd0\u884c\u4e0a\u6e38\u6570\u636e\u51c6\u5907 block\u3002")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")

  if (!outcome_col %in% names(data)) {
    stop("qgcomp_environment: \u7ed3\u5c40\u5217 '", outcome_col, "' \u4e0d\u5728\u6570\u636e\u4e2d\u3002")
  }

  # ── 读取 VOC 和协变量 ─────────────────────────────────────────────────────
  select_vocs <- as.character(
    bl_cfg$select_vocs %||%
    ctx$results$select_vocs_final %||%
    ctx$results$select_vocs %||%
    character(0)
  )
  select_vocs <- intersect(select_vocs, names(data))
  if (length(select_vocs) < 2L) {
    cli::cli_alert_warning("qgcomp_environment: select_vocs 有效列不足 2 个，跳过。")
    return(ctx)
  }

  cov_cfg <- bl_cfg$covariates
  if (is.null(cov_cfg)) {
    covariates <- character(0)
  } else {
    covariates <- as.character(cov_cfg)
    covariates <- intersect(covariates, names(data))
  }

  if (length(covariates)) {
    cli::cli_alert_info(
      "qgcomp_environment: \u8c03\u6574\u6a21\u578b\uff08\u542b {length(covariates)} \u4e2a\u534f\u53d8\u91cf\uff09"
    )
  } else {
    cli::cli_alert_info("qgcomp_environment: Crude Model\uff08\u65e0\u534f\u53d8\u91cf\u8c03\u6574\uff09")
  }

  # ── 二值化结局 ───────────────────────────────────────────────────────────
  y <- data[[outcome_col]]
  if (!(is.numeric(y) && all(stats::na.omit(unique(y)) %in% c(0, 1)))) {
    yc <- trimws(as.character(y))
    data[[outcome_col]] <- as.integer(
      ifelse(yc == trimws(analysis_grp), 1L,
             ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
    )
  } else {
    data[[outcome_col]] <- as.integer(y)
  }

  # ── 子集并清理 ───────────────────────────────────────────────────────────
  keep_cols <- unique(c(outcome_col, covariates, select_vocs))
  data_qgc  <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  data_qgc  <- data_qgc[stats::complete.cases(data_qgc), , drop = FALSE]
  if (nrow(data_qgc) < 30L) {
    stop("qgcomp_environment: \u5b8c\u6574\u6837\u672c\u4e0d\u8db3 30 \u884c\u3002")
  }
  cli::cli_alert_info("qgcomp_environment: n = {nrow(data_qgc)}, VOC = {length(select_vocs)}")

  # ── 构建公式 ─────────────────────────────────────────────────────────────
  fml <- .qgc39_build_formula(outcome_col, select_vocs, covariates)
  cli::cli_alert_info("qgcomp_environment: formula = {deparse(fml)}")

  # ── 拟合模型 ─────────────────────────────────────────────────────────────
  q    <- as.integer(bl_cfg$q    %||% 4L)
  seed <- as.integer(bl_cfg$seed %||% 2023L)
  set.seed(seed)

  cli::cli_h2("qgcomp_environment: qgcomp.noboot (q={q})")
  qgc_fit <- tryCatch(
    qgcomp::qgcomp.noboot(
      f      = fml,
      expnms = select_vocs,
      data   = data_qgc,
      family = stats::binomial(),
      q      = q
    ),
    error = function(e) {
      stop("qgcomp_environment: qgcomp.noboot \u5931\u8d25: ", e$message, call. = FALSE)
    }
  )
  ctx$results$qgcomp_fit <- qgc_fit

  # ── 提取系数表（glm 系数 + OR）──────────────────────────────────────────
  coef_table <- .qgc39_extract_coef_table(qgc_fit)
  or_table   <- .qgc39_extract_or_table(qgc_fit)
  ctx$results$qgcomp_coef_table <- coef_table
  ctx$results$qgcomp_or_table   <- or_table
  if (!is.null(coef_table) && nrow(coef_table)) {
    cli::cli_alert_success("qgcomp_environment: glm 系数表提取完成（{nrow(coef_table)} 行）")
  } else if (!is.null(or_table) && nrow(or_table)) {
    cli::cli_alert_success("qgcomp_environment: OR 表提取完成")
  }

  # ── 提取权重 data.frame ───────────────────────────────────────────────────
  label_map <- bl_cfg$label_mapping
  wts_df    <- .qgc39_extract_weights_df(qgc_fit)

  if (nrow(wts_df)) {
    # 应用标签映射
    if (!is.null(label_map) && length(label_map)) {
      wts_df$Factors <- vapply(wts_df$Factors, function(x) {
        if (x %in% names(label_map)) as.character(label_map[[x]]) else x
      }, character(1L))
    }
    ctx$results$qgcomp_weights_df <- wts_df
  }

  # ── 生成文本摘要 ─────────────────────────────────────────────────────────
  top_n   <- as.integer(bl_cfg$top_n %||% 3L)
  top3_txt <- .qgc39_top_n_text(wts_df, "positive", top_n, label_map)
  bot3_txt <- .qgc39_top_n_text(wts_df, "negative", top_n, label_map)
  ctx$results$qgcomp_top3_text    <- top3_txt
  ctx$results$qgcomp_bottom3_text <- bot3_txt
  cli::cli_alert_info("qgcomp_environment: \u6b63\u5411\u524d{top_n}: {top3_txt}")
  cli::cli_alert_info("qgcomp_environment: \u8d1f\u5411\u524d{top_n}: {bot3_txt}")

  # ── 图形：权重条形图 ──────────────────────────────────────────────────────
  output_dir_figures <- file.path(ctx$output_dir %||% ".", "Figures")
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)

  fig_fn   <- as.character(bl_cfg$fig_filename %||% "Figure_QGComp_Weights.pdf")
  fig_path <- file.path(output_dir_figures, fig_fn)

  if (nrow(wts_df)) {
    tryCatch({
      p_wgt <- .qgc39_plot_weights(wts_df, label_map, bl_cfg$y_limits)
      n_vars <- nrow(wts_df)
      ggplot2::ggsave(
        filename = fig_path,
        plot     = p_wgt,
        height   = max(4, min(12, n_vars * 0.35 + 1.5)),
        width    = 6
      )
      cli::cli_alert_success("{fig_fn} \u5df2\u4fdd\u5b58")
    }, error = function(e) {
      cli::cli_alert_warning("qgcomp_environment: \u6743\u91cd\u56fe\u4fdd\u5b58\u5931\u8d25: {e$message}")
    })
  }

  # ── 导出 CSV 系数表（对齐 VOC 最终 Table S19 格式）────────────────────────
  disease_name <- as.character(
    cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  )
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_fn <- as.character(
    bl_cfg$table_filename %||%
      paste0(
        "Table S12. Associations of Environmental Toxicants with ",
        disease_name, " by using Quantile g-Computation.csv"
      )
  )
  tbl_path <- file.path(tbl_dir, tbl_fn)

  if (!is.null(coef_table) && nrow(coef_table)) {
    tryCatch({
      utils::write.csv(coef_table, tbl_path, row.names = FALSE)
      cli::cli_alert_success("{tbl_fn} 已导出")
    }, error = function(e) {
      cli::cli_alert_warning("qgcomp_environment: CSV 导出失败: {e$message}")
    })
  } else if (!is.null(or_table) && nrow(or_table)) {
    tryCatch({
      utils::write.csv(or_table, tbl_path, row.names = FALSE)
      cli::cli_alert_warning("qgcomp_environment: 已回退导出 OR 表至 {tbl_fn}")
    }, error = function(e) {
      cli::cli_alert_warning("qgcomp_environment: CSV 导出失败: {e$message}")
    })
  }

  # ── 可选：OR 表 xlsx（保留供调试，默认关闭）────────────────────────────────
  if (isTRUE(bl_cfg$export_or_xlsx %||% FALSE) && !is.null(or_table) && nrow(or_table)) {
    xlsx_fn <- sub("\\.csv$", ".xlsx", tbl_fn, ignore.case = TRUE)
    if (identical(xlsx_fn, tbl_fn)) xlsx_fn <- paste0(tools::file_path_sans_ext(tbl_fn), ".xlsx")
    xlsx_path <- file.path(tbl_dir, xlsx_fn)
    tbl_title <- as.character(
      bl_cfg$table_title %||%
        paste0("Table S12. Associations of Environmental Toxicants with ",
               disease_name, " by using Quantile g-Computation")
    )
    tryCatch({
      .qgc39_export_xlsx(or_table, xlsx_path, tbl_title)
    }, error = function(e) {
      cli::cli_alert_warning("qgcomp_environment: Excel 导出失败: {e$message}")
    })
  }

  cli::cli_alert_success("qgcomp_environment \u5b8c\u6210\u3002")
  ctx
}

register_block(
  "qgcomp_environment",
  block_qgcomp_environment,
  "\u73af\u5883\u6df7\u5408\u66b4\u9732 Quantile g-computation\uff08qgcomp.noboot\uff09+ \u6743\u91cd\u56fe + \u7cfb\u6570\u8868"
)
