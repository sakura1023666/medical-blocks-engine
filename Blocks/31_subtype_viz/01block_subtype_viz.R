###############################################################################
#  subtype_viz — 亚型可视化（t-SNE + Z-score 轮廓图，Zhang 2025 Fig.3B）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = lca_results, lca_selected_vars, df_final, lca_optimal_k
#  require_block       = lca（须在 lca 之后）
#
#  subtype_viz = list(
#    k = NULL, perplexity = 30, max_iter = 500,
#    point_size = 1, point_alpha = 0.5, color_palette = "lancet",
#    fig_width = 10, fig_height = 12, output_dir = NULL
#  ),
#
#  输出: tsne_data, zprofile_data; Figure_Subtype_Viz_k{k}.pdf / .png
#  register_block: "subtype_viz"
###############################################################################

block_subtype_viz <- function(ctx, ...) {

  # ── 依赖包 ─────────────────────────────────────────────────────────────────
  needed <- c("Rtsne","ggplot2","dplyr","tidyr","patchwork","ggsci","showtext")
  missing_pkgs <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs)) {
    if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
      options(repos = c(CRAN = "https://cloud.r-project.org"))
    }
    install.packages(missing_pkgs, quiet = TRUE)
  }
  suppressPackageStartupMessages({
    library(Rtsne); library(ggplot2); library(dplyr)
    library(tidyr); library(patchwork); library(ggsci); library(showtext)
  })

  `%||%` <- function(a, b) if (!is.null(a)) a else b
  cfg     <- ctx$config
  viz_cfg <- cfg$subtype_viz %||% list()

  # ── 读取上游结果 ───────────────────────────────────────────────────────────
  results    <- ctx$results$lca_results
  sel_vars   <- ctx$results$lca_selected_vars
  df_final   <- ctx$results$df_final
  optimal_k  <- ctx$results$lca_optimal_k

  if (is.null(results) || is.null(sel_vars) || is.null(df_final)) {
    ctx$results$pause_point <- list(
      block      = "block_subtype_viz",
      reason     = "缺少上游 lca 结果（results / lca_selected_vars / df_final）",
      suggestion = "请先运行 block_lca。"
    )
    stop("PAUSE_FOR_USER_DECISION: 请先运行 block_lca，查看 ctx$results$pause_point。")
  }

  k_viz      <- as.integer(viz_cfg$k %||% optimal_k %||% 2)
  perplexity <- viz_cfg$perplexity   %||% 30
  max_iter   <- viz_cfg$max_iter     %||% 500
  pt_size    <- viz_cfg$point_size   %||% 1
  pt_alpha   <- viz_cfg$point_alpha  %||% 0.5
  palette    <- tolower(viz_cfg$color_palette %||% "lancet")
  fig_w      <- viz_cfg$fig_width    %||% 10
  fig_h      <- viz_cfg$fig_height   %||% 12
  out_dir    <- viz_cfg$output_dir   %||% cfg$lca$output_dir %||% "lca_output"
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  seed       <- cfg$seed             %||% 1234

  cli::cli_h1("[block_subtype_viz] 亚型可视化 (k={k_viz})")

  # 用配置的 k 重新设定 Subphenotype 标签
  cls_vec <- results[[k_viz]]$consensusClass
  if (length(cls_vec) != nrow(df_final)) {
    stop("[block_subtype_viz] df_final 行数与聚类标签长度不匹配，请检查 block_lca 输出。")
  }
  df_final$Subphenotype <- factor(cls_vec)

  # ── t-SNE 数据准备 ─────────────────────────────────────────────────────────
  cli::cli_h2("准备 t-SNE 输入（sel_vars 与 Subphenotype 对齐）")
  vars_exist <- intersect(sel_vars, colnames(df_final))
  if (length(vars_exist) < 2) {
    stop("[block_subtype_viz] df_final 中找不到足够的入模变量。")
  }

  df_tsne <- df_final %>%
    dplyr::select(all_of(vars_exist), Subphenotype) %>%
    mutate(across(all_of(vars_exist), ~ suppressWarnings(as.numeric(as.character(.))))) %>%
    tidyr::drop_na()

  cat("[block_subtype_viz] t-SNE 样本量：", nrow(df_tsne), "\n")

  if (nrow(df_tsne) < 10) {
    ctx$results$pause_point <- list(
      block = "block_subtype_viz", reason = "t-SNE 可用样本量不足 10",
      suggestion = "检查 df_final 是否含大量 NA，或先运行 imputation。"
    )
    stop("PAUSE_FOR_USER_DECISION: t-SNE 样本量不足，查看 ctx$results$pause_point。")
  }

  # perplexity 自动调整（不能超过 (n-1)/3）
  max_perp <- floor((nrow(df_tsne) - 1) / 3)
  if (perplexity > max_perp) {
    cli::cli_alert_warning("perplexity={perplexity} 超限，自动调整为 {max_perp}")
    perplexity <- max_perp
  }

  X <- scale(as.matrix(df_tsne[, vars_exist]))
  set.seed(seed)
  tsne_out <- Rtsne(X, dims = 2, perplexity = perplexity,
                    verbose = FALSE, max_iter = max_iter, check_duplicates = FALSE)

  tsne_df <- data.frame(
    tSNE1        = tsne_out$Y[, 1],
    tSNE2        = tsne_out$Y[, 2],
    Subphenotype = df_tsne$Subphenotype
  )
  ctx$results$tsne_data <- tsne_df

  # ── Z-score 轮廓数据 ────────────────────────────────────────────────────────
  cli::cli_h2("计算 Z-score 轮廓")
  df_z <- as.data.frame(scale(as.matrix(df_tsne[, vars_exist])))
  df_z$Subphenotype <- df_tsne$Subphenotype

  profile_data <- df_z %>%
    group_by(Subphenotype) %>%
    summarise(across(all_of(vars_exist), ~ mean(.x, na.rm = TRUE)), .groups = "drop") %>%
    pivot_longer(cols = all_of(vars_exist), names_to = "Variable", values_to = "Z_Score") %>%
    mutate(Variable = factor(Variable, levels = vars_exist))
  ctx$results$zprofile_data <- profile_data

  # ── 绘图主题 ───────────────────────────────────────────────────────────────
  plot_ff <- plot_font_from_config(cfg)
  showtext_auto()
  my_theme <- theme_bw(base_family = plot_ff) +
    theme(
      plot.title   = element_text(size = 14, face = "bold", hjust = 0.5),
      axis.title   = element_text(size = 12, face = "bold"),
      axis.text    = element_text(size = 10, color = "black"),
      legend.position = "top",
      panel.grid.minor = element_blank()
    )

  # 配色
  .color_scale <- switch(palette,
    "lancet" = scale_color_lancet(),
    "nejm"   = scale_color_nejm(),
    "jco"    = scale_color_jco(),
    "d3"     = scale_color_d3(),
    scale_color_lancet()
  )

  # ── Figure A: t-SNE ────────────────────────────────────────────────────────
  p_tsne <- ggplot(tsne_df, aes(tSNE1, tSNE2, color = Subphenotype)) +
    geom_point(alpha = pt_alpha, size = pt_size) +
    .color_scale +
    labs(
      title  = "A. t-SNE Visualization",
      x      = "t-SNE Dimension 1",
      y      = "t-SNE Dimension 2",
      color  = "Subphenotype"
    ) +
    my_theme +
    guides(color = guide_legend(override.aes = list(size = 3, alpha = 1)))

  # ── Figure B: Z-score Profile ──────────────────────────────────────────────
  p_profile <- ggplot(profile_data,
                      aes(Variable, Z_Score, group = Subphenotype, color = Subphenotype)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    geom_line(size = 1.2, alpha = 0.85) +
    geom_point(size = 3) +
    .color_scale +
    labs(
      title  = "B. Clinical Variable Z-score Profile",
      x      = "Clinical Parameters",
      y      = "Standardized Mean (Z-score)",
      color  = "Subphenotype"
    ) +
    my_theme +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 9))

  # ── 拼图并保存 ─────────────────────────────────────────────────────────────
  final_fig <- p_tsne / p_profile +
    plot_layout(heights = c(1, 0.85)) +
    plot_annotation(
      title  = paste0("Subphenotype Visualization (k=", k_viz, ")"),
      theme  = theme(plot.title = element_text(
        family = plot_ff, size = 16, face = "bold", hjust = 0.5))
    )

  fig_prefix <- file.path(out_dir, paste0("Figure_Subtype_Viz_k", k_viz))

  ctx <- save_figure(ctx, paste0(fig_prefix, ".pdf"),
                     function() print(final_fig), width = fig_w, height = fig_h)
  ggsave(paste0(fig_prefix, ".png"), final_fig,
         width = fig_w, height = fig_h, dpi = 300)
  cli::cli_alert_success("图形已保存：{fig_prefix}.pdf / .png")

  cli::cli_alert_success("[block_subtype_viz] 完成。")
  ctx
}

register_block("subtype_viz", block_subtype_viz,
               "亚型可视化：t-SNE 散点图 + Z-score 轮廓图（两图拼合输出 PDF/PNG）")
