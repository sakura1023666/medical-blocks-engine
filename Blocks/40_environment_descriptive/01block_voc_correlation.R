###############################################################################
#  voc_correlation — 环境暴露 VOC 相关矩阵热图（corrplot）+ 相关系数范围摘要
#
#  register_block: "voc_correlation"
#  典型流水线: process_environment_data → voc_correlation
#
#  功能：
#    对 select_vocs 中的 VOC 计算 Pearson 相关矩阵 + 显著性 p 值矩阵；
#    应用标签映射（内部列名 → 展示名）；
#    生成 corrplot 热图（PDF）；
#    输出相关系数最小/最大值到 ctx$results。
#
#  与现有 09_correlation/01block_correlation.R 的区别：
#    - 现有 block：通用临床变量相关分析
#    - 本 block：专用于环境 VOC 混合物，含标签映射，适配 environment pipeline
#
#  # ── Bug 修复说明（相对原 C01_CorAnalysis_VOCs.R）────────────────────────
#  Bug 1: library(xlsx) 加载但完全未使用 → 删除
#  Bug 2: cor() 未指定 use 参数，数据含 NA 时整列返回 NA → 加 use="complete.obs"
#  Bug 3: cor.mtest() 结果 res.cor$p 只打印不使用，显著性星号未展示 →
#         在 corrplot 中加入 p.mat 参数（可配置开关）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = select_vocs_final（或 select_vocs）
#
#  # ── 配置 config$voc_correlation ──────────────────────────────────────────
#  voc_correlation = list(
#    select_vocs      = NULL,          # VOC 列名；NULL = ctx$results$select_vocs_final
#    label_mapping    = NULL,          # 命名向量 c(内部列名 = "展示名")，可选
#    cor_method       = "pearson",     # "pearson" | "spearman" | "kendall"
#    conf_level       = 0.95,          # cor.mtest 置信水平
#    show_sig_stars   = FALSE,         # 是否在热图中展示显著性星号
#    sig_level        = c(0.001, 0.01, 0.05),  # 显著性阈值（show_sig_stars=TRUE时）
#    col_low          = "#134B87",     # 负相关颜色
#    col_high         = "red",         # 正相关颜色
#    n_colors         = 200L,          # 颜色梯度数量
#    fig_width        = 12,
#    fig_height       = 12,
#    tl_cex           = 1,             # 变量名字号
#    tl_srt           = 45,            # 变量名旋转角度
#    fig_filename     = NULL           # NULL = "Figure_VOC_Correlation.pdf"
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$voc_corr_matrix    — 相关矩阵
#      ctx$results$voc_corr_pmat      — p 值矩阵
#      ctx$results$voc_corr_min       — 非对角线最小相关系数（保留2位）
#      ctx$results$voc_corr_max       — 非对角线最大相关系数（保留2位）
#  文件: Figures/Figure_VOC_Correlation.pdf
###############################################################################

block_voc_correlation <- function(ctx, ...) {
  suppressPackageStartupMessages(library(corrplot))

  cfg    <- ctx$config
  bl_cfg <- cfg$voc_correlation %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("voc_correlation: \u672a\u627e\u5230\u6570\u636e\uff0c\u8bf7\u5148\u8fd0\u884c\u4e0a\u6e38\u6570\u636e\u51c6\u5907 block\u3002")
  }

  # ── 获取 VOC 列表 ─────────────────────────────────────────────────────────
  select_vocs <- as.character(
    bl_cfg$select_vocs %||%
    ctx$results$select_vocs_final %||%
    ctx$results$select_vocs %||%
    character(0)
  )
  select_vocs <- intersect(select_vocs, names(data))
  if (length(select_vocs) < 2L) {
    cli::cli_alert_warning("voc_correlation: select_vocs 有效列不足 2 个，跳过。")
    return(ctx)
  }

  # ── 子集 + 标签映射 ───────────────────────────────────────────────────────
  data_voc <- data[, select_vocs, drop = FALSE]
  label_map <- bl_cfg$label_mapping
  if (!is.null(label_map) && length(label_map)) {
    colnames(data_voc) <- vapply(colnames(data_voc), function(x) {
      if (x %in% names(label_map)) as.character(label_map[[x]]) else x
    }, character(1L))
  }

  cli::cli_alert_info(
    "voc_correlation: {length(select_vocs)} \u4e2a VOC, \u65b9\u6cd5={bl_cfg$cor_method %||% 'pearson'}"
  )

  # ── 计算相关矩阵（修复 Bug 2：加 use="complete.obs"）─────────────────────
  cor_method <- as.character(bl_cfg$cor_method %||% "pearson")
  corr_matrix <- tryCatch(
    stats::cor(data_voc, method = cor_method, use = "complete.obs"),
    error = function(e) stop("voc_correlation: cor() \u5931\u8d25: ", e$message, call. = FALSE)
  )

  # 相关系数范围（非对角线）
  diag_mask   <- corr_matrix != 1
  non_diag    <- corr_matrix[diag_mask]
  corr_min    <- round(min(non_diag, na.rm = TRUE), 2L)
  corr_max    <- round(max(non_diag, na.rm = TRUE), 2L)
  ctx$results$voc_corr_matrix <- corr_matrix
  ctx$results$voc_corr_min    <- corr_min
  ctx$results$voc_corr_max    <- corr_max
  cli::cli_alert_success(
    "voc_correlation: \u76f8\u5173\u7cfb\u6570\u8303\u56f4 [{corr_min}, {corr_max}]"
  )

  # ── 计算 p 值矩阵 (修复 Bug 3：存储并可选展示) ────────────────────────────
  conf_level <- as.numeric(bl_cfg$conf_level %||% 0.95)
  res_cor <- tryCatch(
    corrplot::cor.mtest(data_voc, conf.level = conf_level),
    error = function(e) {
      cli::cli_alert_warning("cor.mtest \u5931\u8d25: {e$message}")
      NULL
    }
  )
  if (!is.null(res_cor)) {
    ctx$results$voc_corr_pmat <- res_cor$p
  }

  # ── 生成 corrplot 图 ──────────────────────────────────────────────────────
  col_low  <- as.character(bl_cfg$col_low   %||% "#134B87")
  col_high <- as.character(bl_cfg$col_high  %||% "red")
  n_col    <- as.integer(bl_cfg$n_colors    %||% 200L)
  col_pal  <- grDevices::colorRampPalette(c(col_low, "#FFFFFF", col_high))(n_col)

  show_sig   <- isTRUE(bl_cfg$show_sig_stars %||% FALSE)
  sig_levels <- bl_cfg$sig_level %||% c(0.001, 0.01, 0.05)
  tl_cex     <- as.numeric(bl_cfg$tl_cex %||% 1)
  tl_srt     <- as.numeric(bl_cfg$tl_srt %||% 45)
  fig_w      <- as.numeric(bl_cfg$fig_width  %||% 12)
  fig_h      <- as.numeric(bl_cfg$fig_height %||% 12)

  output_dir_figures <- file.path(ctx$output_dir %||% ".", "Figures")
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)
  fig_fn   <- as.character(bl_cfg$fig_filename %||% "Figure_VOC_Correlation.pdf")
  fig_path <- file.path(output_dir_figures, fig_fn)

  tryCatch({
    grDevices::pdf(fig_path, width = fig_w, height = fig_h)
    if (show_sig && !is.null(res_cor)) {
      corrplot::corrplot(
        corr_matrix,
        method    = "circle",
        addCoef.col = "black",
        tl.srt    = tl_srt,
        tl.col    = "black",
        tl.cex    = tl_cex,
        col       = col_pal,
        p.mat     = res_cor$p,
        insig     = "label_sig",
        sig.level = sig_levels,
        pch.cex   = 1
      )
    } else {
      corrplot::corrplot(
        corr_matrix,
        method      = "circle",
        addCoef.col = "black",
        tl.srt      = tl_srt,
        tl.col      = "black",
        tl.cex      = tl_cex,
        col         = col_pal
      )
    }
    grDevices::dev.off()
    cli::cli_alert_success("{fig_fn} \u5df2\u4fdd\u5b58")
  }, error = function(e) {
    try(grDevices::dev.off(), silent = TRUE)
    cli::cli_alert_warning("voc_correlation: \u56fe\u5f62\u4fdd\u5b58\u5931\u8d25: {e$message}")
  })

  cli::cli_alert_success("voc_correlation \u5b8c\u6210\u3002")
  ctx
}

register_block(
  "voc_correlation",
  block_voc_correlation,
  "VOC \u6df7\u5408\u7269\u76f8\u5173\u77e9\u9635\u70ed\u56fe\uff08corrplot\uff09+ \u76f8\u5173\u7cfb\u6570\u8303\u56f4\u6458\u8981"
)
