###############################################################################
#  lca — 共识聚类亚型发现（VIF + 相关性筛选 → ConsensusClusterPlus → 诊断图 + Table 1）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#
#  lca = list(
#    candidate_vars = NULL, vif_threshold = 4, cor_threshold = 0.5,
#    min_vars = 6, max_vars = 18, max_k = 6, reps = 50, pItem = 0.8,
#    optimal_k = NULL, swap_label_1_2 = FALSE,
#    outcome_col = NULL, time_col = NULL, factor_vars = character(0),
#    required_vars = character(0), required_any_of = list(),
#    output_dir = "lca_output"
#  ),
#
#  输出: lca_results, lca_selected_vars, lca_optimal_k, df_final, lca_metrics, ...
#  register_block: "lca"
###############################################################################

block_lca <- function(ctx, ...) {

  # ── 依赖包 ─────────────────────────────────────────────────────────────────
  needed_pkgs <- c("ConsensusClusterPlus","ComplexHeatmap","circlize","RColorBrewer",
                   "grid","mclust","patchwork","ggplot2","dplyr","tidyr",
                   "tableone","openxlsx","ggrastr")
  missing_pkgs <- needed_pkgs[!vapply(needed_pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs)) {
    stop(
      "[block_lca] 缺少 R 包: ", paste(missing_pkgs, collapse = ", "),
      "\n请在 R 4.5.1 中预先安装（Bioconductor: ConsensusClusterPlus, ComplexHeatmap）。",
      call. = FALSE
    )
  }
  suppressPackageStartupMessages({
    library(ConsensusClusterPlus); library(ComplexHeatmap)
    library(circlize); library(RColorBrewer); library(grid)
    library(mclust); library(patchwork); library(ggplot2)
    library(dplyr); library(tidyr)
    library(tableone); library(openxlsx)
  })

  # ── 工具函数 ───────────────────────────────────────────────────────────────
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  cfg     <- ctx$config
  lca_cfg <- cfg$lca %||% list()
  data    <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("[block_lca] 无数据，请先运行 imputation 或 data_clean。")

  id_col      <- cfg$data$id_column %||% NULL
  outcome_col <- lca_cfg$outcome_col %||% cfg$data$outcome_column %||% NULL
  time_col    <- lca_cfg$time_col    %||% cfg$survival$time_column %||% NULL
  factor_vars <- lca_cfg$factor_vars %||% character(0)

  vif_threshold <- lca_cfg$vif_threshold %||% 4
  cor_threshold <- lca_cfg$cor_threshold %||% 0.5
  min_vars      <- lca_cfg$min_vars      %||% 6
  max_vars      <- lca_cfg$max_vars      %||% 18
  max_k         <- lca_cfg$max_k         %||% 6
  reps          <- lca_cfg$reps          %||% 50
  pItem         <- lca_cfg$pItem         %||% 0.8
  optimal_k_cfg <- lca_cfg$optimal_k     %||% NULL
  swap_labels   <- isTRUE(lca_cfg$swap_label_1_2)

  out_sub <- lca_cfg$output_dir %||% "lca_output"
  out_dir <- file.path(ctx$output_dir %||% ".", out_sub)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  seed <- cfg$seed %||% 1234

  # ── Step 1: 确定候选连续变量 ───────────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 1: 确定候选连续变量")

  exclude_cols <- unique(c(id_col, outcome_col, time_col,
                           if (!is.null(cfg$data)) unlist(cfg$data[c("id_column","outcome_column")]) else NULL))
  exclude_cols <- exclude_cols[!is.na(exclude_cols) & nzchar(exclude_cols)]

  candidate_raw <- lca_cfg$candidate_vars
  if (!is.null(candidate_raw) && length(candidate_raw) > 0) {
    candidate_vars <- intersect(as.character(candidate_raw), colnames(data))
    if (length(candidate_vars) < length(candidate_raw)) {
      missing_c <- setdiff(as.character(candidate_raw), colnames(data))
      cli::cli_alert_warning("候选变量中以下列在数据中不存在，已跳过：{paste(missing_c, collapse=', ')}")
    }
  } else {
    candidate_vars <- names(data)[sapply(data, is.numeric)]
    candidate_vars <- setdiff(candidate_vars, exclude_cols)
  }

  # 确保全为连续数值型
  is_continuous <- sapply(candidate_vars, function(v) {
    x <- data[[v]]
    is.numeric(x) && length(unique(na.omit(x))) > 5
  })
  candidate_vars <- candidate_vars[is_continuous]
  vif_excl <- as.character(cfg$multicollinearity$exclude_vars %||% character(0))
  lca_excl <- as.character(lca_cfg$exclude_vars %||% character(0))
  drop_cand <- unique(c(vif_excl, lca_excl))
  drop_cand <- drop_cand[nzchar(drop_cand)]
  if (length(drop_cand)) {
    dropped_cand <- intersect(candidate_vars, drop_cand)
    if (length(dropped_cand)) {
      cli::cli_alert_info("聚类候选 exclude_vars 排除: {paste(dropped_cand, collapse = ', ')}")
    }
    candidate_vars <- setdiff(candidate_vars, drop_cand)
  }
  cli::cli_alert_info("候选连续变量：{length(candidate_vars)} 个")

  # 构建完整样本矩阵（na.omit）
  df_cand <- data[, candidate_vars, drop = FALSE]
  df_cand[] <- lapply(df_cand, function(x) suppressWarnings(as.numeric(as.character(x))))
  df_clean  <- na.omit(df_cand)
  cli::cli_alert_info("完整样本量（na.omit 后）：{nrow(df_clean)}")

  if (nrow(df_clean) < 30) {
    ctx$results$pause_point <- list(
      block = "block_lca", reason = "完整样本量不足 30，无法聚类",
      suggestion = "检查缺失值比例，或先运行 imputation block。",
      data_snapshot = head(df_clean, 5)
    )
    stop("PAUSE_FOR_USER_DECISION: 样本量不足，查看 ctx$results$pause_point。")
  }

  # ── Step 2: VIF 迭代筛选 ───────────────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 2: VIF 迭代筛选 (阈值 < {vif_threshold})")

  .compute_vif <- function(mat) {
    vars_nm <- colnames(mat)
    vif_v   <- setNames(numeric(length(vars_nm)), vars_nm)
    for (i in seq_along(vars_nm)) {
      y  <- mat[, i]
      xdf <- as.data.frame(mat[, -i, drop = FALSE])
      if (ncol(xdf) == 0) { vif_v[i] <- 1; next }
      r2 <- tryCatch(summary(lm(y ~ ., data = xdf))$r.squared, error = function(e) 0)
      vif_v[i] <- if (r2 >= 1) 999 else 1 / (1 - r2)
    }
    vif_v
  }

  active_vars <- candidate_vars
  vif_removed <- character(0)

  repeat {
    if (length(active_vars) < 2) break
    mat_v <- as.matrix(df_clean[, active_vars, drop = FALSE])
    vif_v <- .compute_vif(mat_v)
    max_vif <- max(vif_v, na.rm = TRUE)
    if (max_vif < vif_threshold) break
    worst <- names(which.max(vif_v))
    cli::cli_alert_warning("  剔除 VIF={round(max_vif,2)} 最高变量：{worst}")
    vif_removed  <- c(vif_removed, worst)
    active_vars  <- setdiff(active_vars, worst)
  }

  vif_final <- if (length(active_vars) >= 2) .compute_vif(as.matrix(df_clean[, active_vars])) else NULL
  vif_report <- data.frame(
    Variable = active_vars,
    VIF      = if (!is.null(vif_final)) round(vif_final[active_vars], 3) else NA,
    stringsAsFactors = FALSE
  )

  cli::cli_alert_success("VIF 筛选后保留 {length(active_vars)} 个变量（剔除 {length(vif_removed)} 个）")
  ctx$results$lca_vif_report <- vif_report
  ctx <- save_result(ctx, "lca_vif_report", vif_report, "lca_vif_report.csv")

  # ── Step 3: 相关性迭代筛选 ─────────────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 3: 相关性迭代筛选")

  # 内部函数：给定阈值执行迭代
  .apply_cor_filter <- function(vars_in, threshold) {
    vars_work  <- vars_in
    cor_removed <- character(0)
    repeat {
      if (length(vars_work) < 2) break
      mat_c  <- as.matrix(df_clean[, vars_work, drop = FALSE])
      cor_m  <- cor(mat_c, method = "spearman", use = "pairwise.complete.obs")
      diag(cor_m) <- 0
      max_cor <- max(abs(cor_m), na.rm = TRUE)
      if (max_cor < threshold) break
      # 找最高相关对
      idx <- which(abs(cor_m) == max_cor, arr.ind = TRUE)[1, ]
      v1  <- vars_work[idx[1]]; v2 <- vars_work[idx[2]]
      # 剔除 VIF 较大的那个（若无 VIF 信息则剔除第一个）
      vif_v1 <- vif_report$VIF[vif_report$Variable == v1]
      vif_v2 <- vif_report$VIF[vif_report$Variable == v2]
      if (length(vif_v1) == 0 || is.na(vif_v1)) vif_v1 <- 0
      if (length(vif_v2) == 0 || is.na(vif_v2)) vif_v2 <- 0
      drop_v <- if (vif_v1 >= vif_v2) v1 else v2
      cli::cli_alert_warning("  剔除相关性|r|={round(max_cor,3)} 较高VIF变量：{drop_v}  ({v1} <-> {v2})")
      cor_removed <- c(cor_removed, drop_v)
      vars_work   <- setdiff(vars_work, drop_v)
    }
    list(vars = vars_work, removed = cor_removed)
  }

  # 首先使用默认阈值
  cor_res     <- .apply_cor_filter(active_vars, cor_threshold)
  final_vars  <- cor_res$vars
  cor_removed <- cor_res$removed

  # 若变量数不够或超过，尝试自动调整阈值
  n_final <- length(final_vars)
  if (n_final < min_vars) {
    cli::cli_alert_warning(
      "相关性阈值={cor_threshold} 后仅剩 {n_final} 个变量（< min_vars={min_vars}），自动放宽阈值...")
    for (thr in c(0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9)) {
      res2 <- .apply_cor_filter(active_vars, thr)
      if (length(res2$vars) >= min_vars) {
        final_vars  <- res2$vars; cor_removed <- res2$removed
        cor_threshold <- thr
        cli::cli_alert_success("放宽至阈值={thr}，最终 {length(final_vars)} 个变量。")
        break
      }
    }
  }
  if (n_final > max_vars) {
    cli::cli_alert_warning(
      "相关性阈值={cor_threshold} 后仍有 {n_final} 个变量（> max_vars={max_vars}），自动收紧阈值...")
    for (thr in c(0.45, 0.40, 0.35, 0.30)) {
      res2 <- .apply_cor_filter(active_vars, thr)
      if (length(res2$vars) <= max_vars) {
        final_vars  <- res2$vars; cor_removed <- res2$removed
        cor_threshold <- thr
        cli::cli_alert_success("收紧至阈值={thr}，最终 {length(final_vars)} 个变量。")
        break
      }
    }
  }

  # 强制纳入变量（VIF/相关性筛选后补回）
  required_vars <- as.character(lca_cfg$required_vars %||% character(0))
  for (rv in required_vars) {
    if (!nzchar(rv)) next
    if (rv %in% candidate_vars && !rv %in% final_vars) {
      final_vars <- unique(c(final_vars, rv))
      cli::cli_alert_warning("强制纳入聚类变量 (required_vars): {rv}")
    } else if (!rv %in% candidate_vars) {
      cli::cli_alert_warning("required_vars 中变量不在候选集，已跳过: {rv}")
    }
  }
  required_any_of <- lca_cfg$required_any_of %||% list()
  if (length(required_any_of) > 0) {
    for (group in required_any_of) {
      group <- as.character(group)
      group <- group[nzchar(group)]
      if (length(group) == 0) next
      if (length(intersect(group, final_vars)) > 0) next
      avail <- intersect(group, active_vars)
      if (length(avail) == 0) avail <- intersect(group, candidate_vars)
      if (length(avail) > 0) {
        pick <- avail[1]
        final_vars <- unique(c(final_vars, pick))
        cli::cli_alert_warning("强制纳入聚类变量 (required_any_of): {pick}")
      } else {
        cli::cli_alert_warning(
          "required_any_of 组内变量均不可用: {paste(group, collapse = ', ')}"
        )
      }
    }
  }

  # 最终检查
  n_final <- length(final_vars)
  cli::cli_alert_success("最终入模变量：{n_final} 个（VIF < {vif_threshold}，|r| < {cor_threshold}）")
  cli::cli_alert_info("变量列表：{paste(final_vars, collapse=', ')}")

  if (n_final < 2) {
    ctx$results$pause_point <- list(
      block = "block_lca", reason = "筛选后变量不足2个，无法聚类",
      suggestion = "放宽 vif_threshold 或 cor_threshold，或手动指定 candidate_vars。"
    )
    stop("PAUSE_FOR_USER_DECISION: 筛选后变量不足，查看 ctx$results$pause_point。")
  }

  # 保存相关性筛选报告
  cor_report <- data.frame(
    Variable     = c(final_vars, cor_removed),
    Status       = c(rep("保留", length(final_vars)), rep("剔除（相关性）", length(cor_removed))),
    stringsAsFactors = FALSE
  )
  ctx$results$lca_cor_report   <- cor_report
  ctx$results$lca_selected_vars <- final_vars
  ctx <- save_result(ctx, "lca_cor_report", cor_report, "lca_cor_report.csv")

  # ── Step 4: 构建聚类输入矩阵 ──────────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 4: 构建聚类矩阵")
  df_cluster <- df_clean[, final_vars, drop = FALSE]
  df_scaled  <- scale(df_cluster)
  input_mat  <- t(df_scaled)
  cli::cli_alert_info("输入矩阵：{nrow(input_mat)} 变量 × {ncol(input_mat)} 样本")

  # ── Step 5: ConsensusClusterPlus ──────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 5: 运行共识聚类 (maxK={max_k}, reps={reps})")
  ccp_dir <- file.path(out_dir, "consensus_plots")
  if (!dir.exists(ccp_dir)) dir.create(ccp_dir, recursive = TRUE)

  set.seed(seed)
  results <- ConsensusClusterPlus(
    d = input_mat, maxK = max_k, reps = reps, pItem = pItem, pFeature = 1,
    title = ccp_dir, clusterAlg = "km", distance = "euclidean",
    seed = seed, plot = NULL, writeTable = FALSE
  )

  # 标签交换（若配置）
  if (swap_labels) {
    cli::cli_alert_info("交换 k=2 的 Cluster 1/2 标签...")
    for (k in 2:length(results)) {
      if (!is.null(results[[k]])) {
        cls <- results[[k]]$consensusClass
        new_cls <- cls
        new_cls[cls == 1] <- 2; new_cls[cls == 2] <- 1
        results[[k]]$consensusClass <- new_cls
      }
    }
  }

  # ── Step 6: 诊断指标 ──────────────────────────────────────────────────────
  cli::cli_h1("[block_lca] Step 6: 计算诊断指标")

  .get_cdf <- function(cm) {
    v <- cm[lower.tri(cm, diag = FALSE)]
    x <- seq(0, 1, by = 0.01)
    data.frame(x = x, y = sapply(x, function(i) mean(v <= i)))
  }

  k_range     <- 2:max_k
  PAC_vals    <- numeric(length(k_range))
  Cons_vals   <- numeric(length(k_range))
  BIC_vals    <- numeric(length(k_range))
  cdf_list    <- vector("list", length(k_range))

  for (i in seq_along(k_range)) {
    k  <- k_range[i]
    cm <- results[[k]]$consensusMatrix
    lt <- cm[lower.tri(cm, diag = FALSE)]

    # PAC (0.1~0.9)
    PAC_vals[i] <- mean(lt > 0.1 & lt < 0.9)

    # Mean cluster consensus
    cls <- results[[k]]$consensusClass
    intra <- numeric(k)
    for (cl in 1:k) {
      idx_cl <- which(cls == cl)
      if (length(idx_cl) > 1) {
        sub_cm <- cm[idx_cl, idx_cl, drop = FALSE]
        intra[cl] <- mean(sub_cm[lower.tri(sub_cm, diag = FALSE)])
      } else intra[cl] <- 1
    }
    Cons_vals[i] <- mean(intra)

    # BIC (mclust，取负值方便"越低越好"展示)
    tryCatch({
      mod <- Mclust(df_scaled, G = k, verbose = FALSE)
      BIC_vals[i] <- -max(mod$bic)
    }, error = function(e) { BIC_vals[i] <<- NA })

    # CDF
    cdf_df <- .get_cdf(cm)
    cdf_df$k <- factor(k)
    cdf_list[[i]] <- cdf_df
  }

  metrics_df <- data.frame(k = k_range, PAC = PAC_vals,
                            MeanConsensus = Cons_vals, BIC = BIC_vals)
  cdf_all    <- do.call(rbind, cdf_list)
  ctx$results$lca_metrics <- metrics_df

  # 自动最优 k：PAC 最低
  if (!is.null(optimal_k_cfg)) {
    optimal_k <- as.integer(optimal_k_cfg)
    cli::cli_alert_info("使用配置指定的 optimal_k = {optimal_k}")
  } else {
    optimal_k <- k_range[which.min(PAC_vals)]
    cli::cli_alert_success("自动选定 optimal_k = {optimal_k}（PAC 最低 = {round(min(PAC_vals),4)}）")
  }
  ctx$results$lca_optimal_k <- optimal_k

  # ── Step 7: 共识矩阵拼图（6面板 A-F）─────────────────────────────────────
  cli::cli_h1("[block_lca] Step 7: 生成共识矩阵拼图")
  plot_ff <- plot_font_from_config(cfg)

  blue_pal      <- colorRamp2(c(0, 1), c("#FFFFFF", "#084594"))
  safe_cols     <- c("#A6CEE3","#1F78B4","#B2DF8A","#33A02C","#CAB2D6","#6A3D9A")
  ht_opt$message <- FALSE

  ht_list <- list()
  # A: 图例
  leg_mat <- matrix(rep(seq(1, 0, length.out = 11), each = 10), nrow = 11, byrow = TRUE)
  ht_list[[1]] <- Heatmap(leg_mat, cluster_rows = FALSE, cluster_columns = FALSE,
                          col = blue_pal, show_heatmap_legend = FALSE,
                          row_names_side = "right", show_column_names = FALSE,
                          column_title = "consensus matrix legend",
                          rect_gp = gpar(col = NA))
  # B-F: k=2~max_k
  for (k in 2:max_k) {
    mat_k     <- results[[k]]$consensusMatrix
    cls_k     <- factor(results[[k]]$consensusClass, levels = 1:k)
    ann_cols  <- safe_cols[1:k]; names(ann_cols) <- levels(cls_k)
    top_ann   <- HeatmapAnnotation(
      Cluster = cls_k, col = list(Cluster = ann_cols),
      show_annotation_name = FALSE, simple_anno_size = unit(0.4, "cm"))
    ccp_tree  <- as.dendrogram(results[[k]]$consensusTree)
    ht_list[[k]] <- Heatmap(
      mat_k, col = blue_pal, top_annotation = top_ann,
      cluster_rows = ccp_tree, cluster_columns = ccp_tree,
      use_raster = TRUE, raster_quality = 3, raster_device = "png",
      border = NA, rect_gp = gpar(col = NA),
      show_row_names = FALSE, show_column_names = FALSE,
      show_row_dend = FALSE, show_column_dend = TRUE,
      show_heatmap_legend = FALSE, column_title = paste0("k=", k))
  }

  out_cm <- file.path(out_dir, "Fig_LCA_ConsensusMatrix.png")
  png(out_cm, width = 16, height = 10, units = "in", res = 300)
  grid.newpage()
  pushViewport(viewport(layout = grid.layout(nrow = 2, ncol = 3)))
  panel_labs <- c("A","B","C","D","E","F")
  for (i in 1:6) {
    ri <- ifelse(i <= 3, 1, 2)
    ci <- ifelse(i %% 3 == 0, 3, i %% 3)
    pushViewport(viewport(layout.pos.row = ri, layout.pos.col = ci))
    draw(ht_list[[i]], newpage = FALSE)
    grid.text(panel_labs[i], x = unit(0.02,"npc"), y = unit(0.98,"npc"),
              just = c("left","top"), gp = gpar(fontsize = 26, fontface = "bold",
              fontfamily = plot_ff))
    popViewport()
  }
  dev.off()
  cli::cli_alert_success("共识矩阵拼图：{normalizePath(out_cm, mustWork=FALSE)}")

  # ── Step 8: 诊断四联图 ────────────────────────────────────────────────────
  my_theme <- theme_bw(base_family = plot_ff) +
    theme(panel.grid.minor = element_blank(),
          axis.title = element_text(size = 10, face = "bold"),
          plot.title = element_text(hjust = 0.5, size = 12, face = "bold"))

  p1 <- ggplot(metrics_df, aes(k, MeanConsensus)) +
    geom_line(size = 1) + geom_point(size = 3) +
    geom_vline(xintercept = optimal_k, linetype = "dashed", color = "red", alpha = 0.6) +
    labs(title = "Cluster Consensus", y = "Score") + my_theme

  p2 <- ggplot(metrics_df, aes(k, PAC)) +
    geom_line(size = 1) + geom_point(size = 3) +
    geom_vline(xintercept = optimal_k, linetype = "dashed", color = "red", alpha = 0.6) +
    labs(title = "PAC (Ambiguity)", y = "PAC Score") + my_theme

  p3 <- ggplot(metrics_df %>% filter(!is.na(BIC)), aes(k, BIC)) +
    geom_line(size = 1) + geom_point(size = 3) +
    geom_vline(xintercept = optimal_k, linetype = "dashed", color = "red", alpha = 0.6) +
    labs(title = "BIC (negative)", y = "-BIC") + my_theme

  p4 <- ggplot(cdf_all, aes(x, y, color = k)) +
    geom_line(size = 1) +
    scale_color_brewer(palette = "Set1") +
    labs(title = "Consensus CDF", x = "Consensus Index", y = "CDF") + my_theme

  diag_panel <- (p1 | p2) / (p3 | p4) +
    plot_annotation(title = paste0("Optimal k = ", optimal_k, " (red dashed)"),
                    theme = theme(plot.title = element_text(family = plot_ff,
                                                            size = 14, face = "bold", hjust = 0.5)))

  ctx <- save_figure(ctx, file.path(out_dir, "Fig_LCA_OptimalK.pdf"),
                     function() print(diag_panel), width = 9, height = 8)

  # ── Step 9: Delta Area + Tracking 图 ──────────────────────────────────────
  areas <- sapply(2:max_k, function(k) {
    v <- results[[k]]$consensusMatrix; v <- v[lower.tri(v, diag = FALSE)]
    sum(ecdf(v)(seq(0, 1, 0.01))) / 100
  })
  delta_area <- c(areas[1], diff(areas) / areas[-length(areas)])
  delta_df   <- data.frame(k = 2:max_k, DeltaArea = delta_area)

  p_delta <- ggplot(delta_df, aes(k, DeltaArea)) +
    geom_line(size = 1) + geom_point(size = 3) +
    scale_x_continuous(breaks = 2:max_k) +
    labs(title = "Delta Area Plot", x = "k", y = "Relative Change") +
    my_theme

  track_mat <- do.call(cbind, lapply(2:max_k, function(k) results[[k]]$consensusClass))
  colnames(track_mat) <- paste0("k=", 2:max_k)
  track_long <- as.data.frame(track_mat) %>%
    mutate(ID = seq_len(n())) %>%
    pivot_longer(cols = starts_with("k="), names_to = "k", values_to = "cluster") %>%
    mutate(cluster = factor(cluster))

  p_tracking <- ggplot(track_long, aes(k, ID, fill = cluster)) +
    tryCatch(ggrastr::geom_tile_rast(), error = function(e) geom_tile()) +
    theme_minimal(base_family = plot_ff) +
    theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
          panel.grid = element_blank()) +
    labs(title = "Tracking Plot", x = "k", y = "Samples")

  ctx <- save_figure(ctx, file.path(out_dir, "Fig_LCA_DeltaTracking.pdf"),
                     function() print(p_delta / p_tracking + plot_layout(heights = c(1, 1.5))),
                     width = 8, height = 10)

  # ── Step 10: 指标表格导出 ─────────────────────────────────────────────────
  ctx <- save_result(ctx, "lca_metrics", metrics_df,
                     file.path(out_dir, "Table_LCA_Metrics.csv"))
  export_sci_table(
    metrics_df,
    file.path(out_dir, "Table_LCA_Metrics.xlsx"),
    title = "Table. Consensus Clustering Validation Metrics"
  )

  # ── Step 11: 构建 df_final + Table 1 ──────────────────────────────────────
  cli::cli_h1("[block_lca] Step 11: 构建 df_final + Table 1 (k={optimal_k})")

  df_final              <- as.data.frame(df_clean)
  df_final$Subphenotype <- factor(results[[optimal_k]]$consensusClass)

  # 合并结局列
  extra_cols <- c(outcome_col, time_col)
  extra_cols <- extra_cols[!sapply(extra_cols, is.null) & extra_cols %in% colnames(data)]
  if (length(extra_cols) > 0) {
    extra_df <- data[rownames(df_clean), extra_cols, drop = FALSE]
    for (ec in extra_cols) {
      if (ec == outcome_col) {
        extra_df[[ec]] <- as.factor(extra_df[[ec]])
      } else {
        extra_df[[ec]] <- suppressWarnings(as.numeric(as.character(extra_df[[ec]])))
      }
    }
    df_final <- cbind(df_final, extra_df)
  }

  # 双库亚型语义对齐：最低事件率亚型 → Class 1（与 eICU 参照逻辑一致）
  harm_cfg <- cfg$dual_db$harmonization %||% list()
  align_sem <- isTRUE(harm_cfg$align_subtype_semantics)
  align_col <- outcome_col
  if (align_sem && !is.null(align_col) && align_col %in% names(df_final)) {
    cli::cli_h2("align_subtype_semantics: 按 {align_col} 粗事件率重排亚型编号")
    ev01 <- suppressWarnings(as.numeric(as.character(df_final[[align_col]])))
    aligned <- pipeline_remap_subphenotype_by_risk(results, df_final, ev01, align = TRUE)
    results   <- aligned$results
    df_final  <- aligned$df_final
  }

  ctx$results$df_final <- df_final

  # Table 1
  all_t1_vars <- c(final_vars, extra_cols)
  all_t1_vars <- intersect(all_t1_vars, colnames(df_final))
  fv_t1       <- intersect(factor_vars, all_t1_vars)
  if (!is.null(outcome_col) && outcome_col %in% all_t1_vars) fv_t1 <- unique(c(fv_t1, outcome_col))

  tab1_obj <- CreateTableOne(vars = all_t1_vars, strata = "Subphenotype",
                             data = df_final, factorVars = fv_t1, test = TRUE)
  tb_matrix <- print(tab1_obj, showAllLevels = TRUE, quote = FALSE,
                     noSpaces = TRUE, printToggle = FALSE)
  tb_df <- as.data.frame(tb_matrix)
  tb_df <- cbind(Variable = rownames(tb_df), tb_df)
  rownames(tb_df) <- NULL

  wb <- createWorkbook()
  addWorksheet(wb, "Table1")
  hdr_style  <- createStyle(fontSize = 12, fontName = "Times New Roman",
                             halign = "center", textDecoration = "bold", border = "bottom")
  body_style <- createStyle(fontSize = 12, fontName = "Times New Roman",
                             halign = "center", valign = "center")
  writeData(wb, 1, x = pub_title(ctx, "main_table", paste0(
    "Baseline characteristics (k=", optimal_k, ")"
  )), startRow = 1); mergeCells(wb, 1, rows = 1, cols = 1:ncol(tb_df))
  addStyle(wb, 1, style = hdr_style, rows = 1, cols = 1:ncol(tb_df), gridExpand = TRUE)
  writeData(wb, 1, x = tb_df, startRow = 3, startCol = 1, colNames = TRUE)
  addStyle(wb, 1, style = hdr_style,  rows = 3, cols = 1:ncol(tb_df), gridExpand = TRUE)
  addStyle(wb, 1, style = body_style, rows = 4:(nrow(tb_df)+3),
           cols = 1:ncol(tb_df), gridExpand = TRUE)
  setColWidths(wb, 1, cols = 1:ncol(tb_df), widths = "auto")
  t1_path <- file.path(out_dir, paste0("Table1_Subphenotypes_k", optimal_k, ".xlsx"))
  saveWorkbook(wb, file = t1_path, overwrite = TRUE)
  cli::cli_alert_success("Table 1 已保存：{t1_path}")

  # ── Step 12: 保存全局 RData ────────────────────────────────────────────────
  rdata_path <- file.path(out_dir, "Subphenotype_Analysis_Results.RData")
  save(results, df_final, metrics_df, final_vars, df_scaled,
       optimal_k, file = rdata_path)
  cli::cli_alert_success("RData 已保存：{rdata_path}")

  ctx$results$lca_results <- results
  ctx$data$lca_scaled      <- as.data.frame(df_scaled)

  cli::cli_alert_success("[block_lca] 全部完成。最优 k={optimal_k}，入模变量 {length(final_vars)} 个。")
  ctx
}

register_block("lca", block_lca,
               "共识聚类亚型发现：VIF+相关性自动筛选连续变量 → ConsensusClusterPlus → 诊断图表 + Table 1")
