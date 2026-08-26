###############################################################################
#  correlation — 连续变量 Spearman 相关矩阵热图 + 高相关变量对报告。
#
#  register_block: "correlation"
#  典型流水线: baseline / multicollinearity 附近；可选读 continuous_vars
#
#  # ── 配置 config$correlation ───────────────────────────────────────────────
#  high_cor_threshold = 0.8   # |r| 超过此阈值写入 high_cor_pairs
#  变量集: 默认除 ID/结局外数值列，或与 ctx$results$continuous_vars 交集
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: ctx$data$imputed %||% cleaned
#  写: correlation_matrix, correlation_pmat, high_cor_pairs
#  文件: Figure_Correlation_Heatmap.pdf
#  源: Blocks/block_correlation.R（Blocks/09_correlation）
###############################################################################

block_correlation <- function(ctx, ...) {
  if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }
  if (!requireNamespace("corrplot", quietly = TRUE)) install.packages("corrplot", quiet = TRUE)
  if (!requireNamespace("RColorBrewer", quietly = TRUE)) install.packages("RColorBrewer", quiet = TRUE)
  suppressPackageStartupMessages({
    library(corrplot)
    library(RColorBrewer)
  })

  `%||%` <- function(a, b) if (!is.null(a)) a else b
  cfg         <- ctx$config
  data        <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'data_clean' or 'imputation' first.")

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  id_col        <- cfg$data$id_column %||% "SEQN"
  high_cor_thr  <- cfg$correlation$high_cor_threshold %||% 0.8
  export_filtered_heatmap <- isTRUE(cfg$correlation$export_filtered_heatmap %||% TRUE)

  continuous <- ctx$results$continuous_vars
  if (is.null(continuous) || length(continuous) == 0) {
    continuous <- names(data)[sapply(data, is.numeric)]
    continuous <- setdiff(continuous, c(outcome_col, id_col))
  }
  continuous <- intersect(continuous, names(data))

  ## 可选：只用最终 ML 特征里的连续变量做共线检查（叙事与 LASSO/建模一致）
  cor_scope <- tolower(trimws(as.character(cfg$correlation$scope %||% "")[1L]))
  if (identical(cor_scope, "ml_final") || isTRUE(cfg$correlation$use_ml_features %||% FALSE)) {
    ml_feats <- unique(as.character(
      ctx$results$feature_selection_final %||%
        ctx$results$ml_feature_names %||%
        character(0)
    ))
    ml_feats <- ml_feats[nzchar(ml_feats)]
    if (length(ml_feats)) {
      ml_num <- ml_feats[vapply(ml_feats, function(v) {
        v %in% names(data) && is.numeric(data[[v]])
      }, logical(1L))]
      if (length(ml_num) >= 2L) {
        continuous <- ml_num
        cli::cli_alert_info(
          "相关矩阵：限定最终 ML 连续特征 {length(continuous)} 个: {paste(continuous, collapse = ', ')}"
        )
        cat_ml <- setdiff(ml_feats, ml_num)
        if (length(cat_ml)) {
          cli::cli_alert_info(
            "相关矩阵：ML 分类特征不进 Spearman 热图（另行记录）: {paste(cat_ml, collapse = ', ')}"
          )
          ctx$results$correlation_ml_categorical_skipped <- cat_ml
        }
      } else {
        cli::cli_alert_warning(
          "相关矩阵 scope=ml_final 但连续 ML 特征不足 2 个，回退默认变量集"
        )
      }
    }
  }

  cor_inc <- cfg$correlation$include_vars %||% character(0)
  if (!length(cor_inc) && exists("pipeline_dual_db_include_predictors", mode = "function") &&
      !identical(cor_scope, "ml_final") && !isTRUE(cfg$correlation$use_ml_features %||% FALSE)) {
    cor_inc <- pipeline_dual_db_include_predictors(cfg)
  }
  if (length(cor_inc)) {
    cor_inc <- as.character(cor_inc)
    ## 显式 include_vars：允许强制用数据中的数值列（不限于 continuous_vars 名单）
    cor_num <- cor_inc[cor_inc %in% names(data)]
    cor_num <- cor_num[vapply(cor_num, function(v) is.numeric(data[[v]]), logical(1L))]
    if (length(cor_num) >= 2L) {
      continuous <- cor_num
      cli::cli_alert_info("相关矩阵：使用 include_vars 数值列 {length(continuous)} 个")
    } else {
      cor_inc2 <- cor_inc[cor_inc %in% continuous]
      if (length(cor_inc2) >= 2L) {
        continuous <- cor_inc2[cor_inc2 %in% names(data)]
        cli::cli_alert_info("相关矩阵：使用双库统一变量 {length(continuous)} 个")
      }
    }
  }

  if (length(continuous) < 2) {
    cli::cli_alert_warning("Need at least 2 continuous variables. Skipping correlation block.")
    return(ctx)
  }

  cli::cli_h2("Spearman correlation analysis ({length(continuous)} variables)")

  num_data <- data[, continuous, drop = FALSE]
  
  cor_mat <- cor(num_data, use = "pairwise.complete.obs", method = "spearman")
  
  n_vars <- ncol(num_data)
  p_mat <- matrix(NA, n_vars, n_vars)
  rownames(p_mat) <- colnames(p_mat) <- colnames(num_data)
  
  for (i in 1:n_vars) {
    for (j in 1:n_vars) {
      if (i == j) {
        p_mat[i, j] <- 0
      } else if (i < j) {
        test_res <- tryCatch(
          cor.test(num_data[, i], num_data[, j], method = "spearman", exact = FALSE),
          error = function(e) NULL
        )
        p_mat[i, j] <- p_mat[j, i] <- if (!is.null(test_res)) test_res$p.value else NA
      }
    }
  }

  sig_mat <- matrix("", nrow = nrow(p_mat), ncol = ncol(p_mat))
  sig_mat[!is.na(p_mat) & p_mat < 0.05]  <- "*"
  sig_mat[!is.na(p_mat) & p_mat < 0.01]  <- "**"
  sig_mat[!is.na(p_mat) & p_mat < 0.001] <- "***"

  fig_size <- max(10, length(continuous) * 0.55)

  col_palette <- colorRampPalette(c("#BB4444", "#EE9988", "#FFFFFF", "#77AADD", "#4477AA"))(200)

  ctx <- save_figure(ctx, "Figure Correlation Heatmap.pdf", function() {
    ord     <- corrplot::corrMatOrder(cor_mat, order = "hclust")
    cor_ord <- cor_mat[ord, ord]
    p_ord   <- p_mat[ord, ord]
    n       <- nrow(cor_ord)

    label_mat <- matrix("", nrow = n, ncol = n)
    ns_idx  <- !is.na(p_ord) & p_ord >= 0.05
    s3_idx  <- !is.na(p_ord) & p_ord < 0.001
    s2_idx  <- !is.na(p_ord) & p_ord >= 0.001 & p_ord < 0.01
    s1_idx  <- !is.na(p_ord) & p_ord >= 0.01  & p_ord < 0.05
    label_mat[ns_idx] <- as.character(round(cor_ord[ns_idx], 2))
    label_mat[s3_idx] <- paste0(round(cor_ord[s3_idx], 2), "***")
    label_mat[s2_idx] <- paste0(round(cor_ord[s2_idx], 2), "**")
    label_mat[s1_idx] <- paste0(round(cor_ord[s1_idx], 2), "*")

    corrplot::corrplot(
      cor_ord,
      method      = "color",
      type        = "upper",
      order       = "original",
      tl.col      = "black",
      tl.srt      = 45,
      tl.cex      = 0.7,
      cl.cex      = 0.7,
      addCoef.col = NULL,
      col         = col_palette,
      title       = "Spearman Correlation Matrix",
      mar         = c(0, 0, 2, 0)
    )

    for (i in seq_len(n - 1)) {
      for (j in (i + 1):n) {
        lbl <- label_mat[i, j]
        if (nzchar(lbl)) {
          text(j, n + 1 - i, labels = lbl, cex = 0.62, col = "black")
        }
      }
    }
  }, width = fig_size, height = fig_size)

  cli::cli_h2("Checking high-correlation pairs (|r| > {high_cor_thr})")

  cor_upper <- cor_mat
  cor_upper[lower.tri(cor_upper, diag = TRUE)] <- NA
  high_idx <- which(abs(cor_upper) > high_cor_thr, arr.ind = TRUE)

  if (nrow(high_idx) > 0) {
    high_cor_df <- data.frame(
      var1      = rownames(cor_mat)[high_idx[, 1]],
      var2      = colnames(cor_mat)[high_idx[, 2]],
      spearman_r = round(cor_upper[high_idx], 3),
      p_value   = if (!all(is.na(p_mat))) round(p_mat[high_idx], 4) else NA,
      stringsAsFactors = FALSE
    )
    high_cor_df <- high_cor_df[order(-abs(high_cor_df$spearman_r)), ]

    cli::cli_alert_warning("{nrow(high_cor_df)} high-correlation pair(s) found")
    for (i in seq_len(nrow(high_cor_df))) {
      cli::cli_li("{high_cor_df$var1[i]} <-> {high_cor_df$var2[i]}: r = {high_cor_df$spearman_r[i]}")
    }

    ctx <- save_result(ctx, "high_cor_pairs", high_cor_df, "high_correlation_pairs.csv")
    ctx$results$high_cor_pairs <- high_cor_df
  } else {
    cli::cli_alert_success("No high-correlation pairs found (threshold = {high_cor_thr})")
    ctx$results$high_cor_pairs <- data.frame()
  }

  cli::cli_h2("Extracting significant correlation variables")
  
  index_var <- cfg$survival$index_var %||% cfg$logistic$index_var
  
  if (!is.null(index_var) && index_var %in% rownames(cor_mat)) {
    idx_cor <- cor_mat[index_var, ]
    idx_p   <- p_mat[index_var, ]

    significant_vars <- names(idx_cor)[!is.na(idx_p) & idx_p < 0.05 & abs(idx_cor) > 0.1]
    significant_vars <- setdiff(significant_vars, index_var)
    
    if (length(significant_vars) > 0) {
      cli::cli_alert_success("Found {length(significant_vars)} variables significantly correlated with {index_var}")
      cli::cli_alert_info("Significant variables: {paste(significant_vars, collapse = ', ')}")
      
      cor_with_index <- data.frame(
        variable = significant_vars,
        spearman_r = round(idx_cor[significant_vars], 3),
        p_value = round(idx_p[significant_vars], 4),
        stringsAsFactors = FALSE
      )
      cor_with_index <- cor_with_index[order(-abs(cor_with_index$spearman_r)), ]
      
      ctx <- save_result(ctx, "correlation_with_index", cor_with_index, "correlation_with_index.csv")
    } else {
      cli::cli_alert_warning("No variables significantly correlated with {index_var}")
      significant_vars <- character(0)
    }
  } else {
    cli::cli_alert_warning("Index variable '{index_var}' not found in correlation matrix")
    significant_vars <- character(0)
  }

  # ── 过滤后 circle 热图（Pearson，去掉每对中 VIF 较大者） ────────────────────
  if (export_filtered_heatmap && length(continuous) >= 2) {
    cli::cli_h2("Filtered circle heatmap (Pearson, |r| < {high_cor_thr})")

    ## 贪心去共线：每对 |r|>thr 去掉平均 |r| 更大的一方（可重复直到无高相关对）
    .drop_high_cor_greedy <- function(cor_m, thr) {
      keep <- colnames(cor_m)
      dropped <- character(0)
      repeat {
        if (length(keep) < 2L) break
        cm <- cor_m[keep, keep, drop = FALSE]
        cm[upper.tri(cm, diag = TRUE)] <- NA
        hi <- which(abs(cm) > thr, arr.ind = TRUE)
        if (!nrow(hi)) break
        mean_abs <- vapply(keep, function(v) {
          mean(abs(cor_m[v, setdiff(keep, v)]), na.rm = TRUE)
        }, numeric(1))
        cand <- unique(c(keep[hi[, 1]], keep[hi[, 2]]))
        drop1 <- cand[which.max(mean_abs[cand])]
        dropped <- c(dropped, drop1)
        keep <- setdiff(keep, drop1)
      }
      dropped
    }

    cor_pearson <- cor(num_data, use = "pairwise.complete.obs", method = "pearson")
    remove_vars <- .drop_high_cor_greedy(cor_pearson, high_cor_thr)
    keep_vars   <- setdiff(continuous, remove_vars)
    ctx$results$low_correlation_vars <- keep_vars
    writeLines(keep_vars, file.path(ctx$output_dir, "Low_Correlation_Vars.txt"))
    ctx <- save_result(ctx, "low_correlation_vars_rdata", keep_vars,
                       "Low_Correlation_Vars.RData")
    cli::cli_alert_info("低相关变量（Pearson |r|<{high_cor_thr}）：{length(keep_vars)} 个：{paste(keep_vars, collapse=', ')}")

    if (length(keep_vars) >= 2) {
      df_filtered  <- num_data[, keep_vars, drop = FALSE]
      cor_filtered <- cor(df_filtered, use = "pairwise.complete.obs", method = "pearson")
      fsz          <- max(8, length(keep_vars) * 0.6)
      ctx <- save_figure(ctx, "Figure Correlation Heatmap Filtered.pdf", function() {
        corrplot::corrplot(
          cor_filtered,
          method      = "circle",
          type        = "upper",
          order       = "original",
          col         = colorRampPalette(c("#BB4444","#EE9988","#FFFFFF","#77AADD","#4477AA"))(200),
          addCoef.col = "black",
          number.cex  = 0.7,
          tl.col      = "black",
          tl.srt      = 45,
          diag        = TRUE,
          insig       = "blank",
          mar         = c(0, 0, 2, 0)
        )
      }, width = fsz, height = fsz)
    }
  }

  ctx$results$correlation_matrix <- cor_mat
  ctx$results$correlation_pmat   <- p_mat
  ctx$results$significant_vars   <- significant_vars

  ctx
}

register_block("correlation", block_correlation,
               "Spearman correlation heatmap with significance labels and high-correlation report")
