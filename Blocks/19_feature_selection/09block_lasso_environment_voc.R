###############################################################################
#  lasso_environment_voc — 环境暴露 VOC 单因素 GLM 预筛 + 1000次重复 LASSO 稳定性选择
#
#  register_block: "lasso_environment_voc"
#  典型流水线: process_environment_data → lasso_environment_voc → logistic_environment_glm
#
#  与通用 feature_selection_lasso block 的核心区别：
#    1. 专为环境暴露 (VOC / metals / phthalates 等) 设计，候选特征来自 ctx$results$select_vocs
#    2. 内置单因素 GLM 预筛（可选）：OR > or_min 且 p < p_cutoff 才进入 LASSO
#    3. Lambda = lambda.min × lambda_multiplier（默认 0.5，比 lambda.min 更宽松）
#    4. 频次阈值默认"自动取整法"：floor(最高频模式出现次数 / 100) × 100
#    5. 使用 parallel::parLapply 并行（跨 Windows/Unix；snowfall 的现代替代）
#    6. 无需 Model2Factors / VIF 上游 block
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = select_vocs（可选；若为 NULL 则使用 ctx$data 中所有数值列）
#
#  # ── 配置 config$lasso_environment ────────────────────────────────────────
#  lasso_environment = list(
#    env_cols                = NULL,            # 环境暴露列名向量；NULL = ctx$results$select_vocs
#    outcome_col             = NULL,            # 结局列名；NULL = config$data$outcome_column
#    analysis_group          = NULL,            # 病例组标签；NULL = config$project$analysis_group
#    reference_group         = NULL,            # 对照组标签；NULL = config$project$reference_group
#    # ── 单因素预筛（与 logistic_environment_glm 前的粗筛不同，这里是最简单的单因素）──
#    univariate_enable       = TRUE,            # 是否进行单因素 GLM 预筛
#    univariate_p_cutoff     = 0.05,            # p 值阈值
#    univariate_or_min       = 1.0,             # OR 最低值（> 1 保留正向关联；0 = 不限方向）
#    univariate_or_max       = 10.0,            # OR 最高值（过大可能为异常值，默认 10）
#    exclude_vars            = character(0),    # 手动排除的变量名（如已知无效暴露）
#    # ── LASSO 参数 ──────────────────────────────────────────────────────────
#    cv_times                = 1000L,           # cv.glmnet 重复迭代次数
#    lambda_multiplier       = 0.5,             # 最终 lambda = lambda.min × lambda_multiplier
#    cv_folds                = 10L,             # cv.glmnet 的折数
#    n_cores                 = NULL,            # 并行核数；NULL = floor(detectCores()/2)
#    seed                    = 123L,
#    # ── 频次阈值方法 ────────────────────────────────────────────────────────
#    freq_cutoff_method      = "auto_floor100", # "auto_floor100" | "fraction" | "manual"
#    freq_cutoff_frac        = 0.9,             # 仅 method="fraction" 时：cutoff = frac × cv_times
#    freq_cutoff_n           = NULL,            # 仅 method="manual" 时的固定阈值
#    # ── 图形 ────────────────────────────────────────────────────────────────
#    fig_top_patterns        = 6L,              # 热图显示前 N 个最常见模式
#    fig_label_mapping       = NULL             # 命名向量: c(内部列名 = "展示名")（可选）
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$select_vocs_lasso   — 最终 LASSO 筛出的 VOC 列名
#      ctx$results$select_vocs_univar  — 单因素预筛后的候选列名（若 univariate_enable=TRUE）
#      ctx$results$lasso_gene_sum      — 全部特征频次（命名整数向量，降序）
#      ctx$results$lasso_height        — 使用的频次阈值（整数）
#      ctx$results$lasso_cv_list       — 每次迭代选出的特征列表
#  文件: Figures/Figure_Lasso_A_Barplot.pdf
#        Figures/Figure_Lasso_B_Heatmap.pdf
###############################################################################

# ── 辅助函数 ────────────────────────────────────────────────────────────────

.lenv04_prepare_outcome_binary <- function(data, outcome_col,
                                           analysis_grp, reference_grp) {
  y <- data[[outcome_col]]
  if (is.numeric(y) && all(stats::na.omit(unique(y)) %in% c(0, 1))) {
    return(as.integer(y))
  }
  yc <- trimws(as.character(y))
  out <- rep(NA_integer_, length(yc))
  out[!is.na(yc) & yc == trimws(as.character(analysis_grp))]   <- 1L
  out[!is.na(yc) & yc == trimws(as.character(reference_grp))]  <- 0L
  out
}

.lenv04_univariate_screen <- function(data, env_cols, outcome_col,
                                      analysis_grp, reference_grp,
                                      p_cutoff, or_min, or_max) {
  y01 <- .lenv04_prepare_outcome_binary(data, outcome_col, analysis_grp, reference_grp)
  ok  <- !is.na(y01)
  keep <- character(0)
  rows <- list()

  for (col in env_cols) {
    if (!col %in% names(data)) next
    x <- data[[col]]
    df_uni <- data.frame(y = y01[ok], x = x[ok])
    df_uni <- df_uni[stats::complete.cases(df_uni), ]
    if (nrow(df_uni) < 20L || length(unique(df_uni$y)) < 2L) next

    fit <- tryCatch(
      stats::glm(y ~ x, data = df_uni, family = stats::binomial(link = "logit")),
      error = function(e) NULL
    )
    if (is.null(fit)) next

    sm  <- summary(fit)$coefficients
    if (nrow(sm) < 2L) next

    or   <- round(exp(stats::coef(fit)[2L]), 4)
    se   <- sm[2L, 2L]
    ci_l <- round(exp(stats::coef(fit)[2L] - 1.96 * se), 4)
    ci_u <- round(exp(stats::coef(fit)[2L] + 1.96 * se), 4)
    pval <- sm[2L, 4L]

    rows[[length(rows) + 1L]] <- data.frame(
      Environmental_Feature = col,
      OR  = or,
      CI  = paste0(ci_l, "-", ci_u),
      P   = round(pval, 4),
      stringsAsFactors = FALSE
    )

    pass_p  <- !is.na(pval) && pval < p_cutoff
    pass_or <- is.na(or_min) || (!is.na(or) && or > or_min)
    pass_ub <- is.na(or_max) || (!is.na(or) && or < or_max)

    if (pass_p && pass_or && pass_ub) keep <- c(keep, col)
  }

  uni_table <- if (length(rows)) do.call(rbind, rows) else data.frame()
  list(keep = keep, table = uni_table)
}

#' 与 VOC 最终/C01_Lasso.R 一致：gModel 字符串不 sort，仅 paste collapse
.lenv04_gmodel_str <- function(selected_features) {
  if (!length(selected_features) ||
      (length(selected_features) == 1L && identical(selected_features, "isNA"))) {
    return("isNA")
  }
  paste(selected_features, collapse = " ")
}

.lenv04_compute_freq_threshold <- function(cv_list, cv_times,
                                           method, frac, manual_n) {
  all_genes <- setdiff(unique(unlist(cv_list, use.names = FALSE)), "isNA")
  if (!length(all_genes)) return(list(height = 0L, gene_sum = integer(0)))

  hit_counts <- stats::setNames(integer(length(all_genes)), all_genes)
  for (si in cv_list) {
    if (!length(si) || (length(si) == 1L && identical(si, "isNA"))) next
    valid <- intersect(si, names(hit_counts))
    hit_counts[valid] <- hit_counts[valid] + 1L
  }
  gene_sum <- sort(hit_counts, decreasing = TRUE)

  gModel_str <- vapply(cv_list, .lenv04_gmodel_str, character(1L))
  gmodel_tbl <- sort(table(gModel_str), decreasing = TRUE)

  height <- switch(
    as.character(method),
    "auto_floor100" = {
      top_pattern_count <- max(as.integer(gmodel_tbl), na.rm = TRUE)
      floor(top_pattern_count / 100L) * 100L
    },
    "fraction" = {
      floor(as.numeric(frac %||% 0.9) * cv_times)
    },
    "manual" = {
      as.integer(manual_n %||% floor(0.9 * cv_times))
    },
    floor(0.9 * cv_times)
  )
  height <- max(0L, as.integer(height))
  list(height = height, gene_sum = gene_sum, gmodel_tbl = gmodel_tbl)
}

#' VOC 最终 C01_Lasso.R：height = floor(最高模式次数 / 100) × 100
.lenv04_lasso_height_standard <- function(gmodel_tbl, cv_times) {
  if (is.null(gmodel_tbl) || !length(gmodel_tbl)) {
    return(max(0L, as.integer(floor(0.9 * cv_times))))
  }
  top_n <- as.integer(gmodel_tbl[1L])
  h <- floor(top_n / 100L) * 100L
  if (h >= cv_times && cv_times > 1L) {
    h <- max(0L, floor(0.9 * cv_times))
  }
  as.integer(h)
}

#' 按频次阈值筛选 LASSO 特征（>height；空则 >=；仍空则 Top-N）
.lenv04_select_by_frequency <- function(gene_sum, height, min_n, ranked_pool = names(gene_sum)) {
  if (!length(gene_sum)) {
    return(ranked_pool[seq_len(min(min_n, length(ranked_pool)))])
  }
  sel <- sort(names(gene_sum)[gene_sum > height])
  if (!length(sel)) sel <- sort(names(gene_sum)[gene_sum >= height])
  if (!length(sel)) {
    sel <- ranked_pool[seq_len(min(min_n, length(ranked_pool)))]
  }
  unique(sel[nzchar(sel)])
}

#' 统计 lambda.mult 下非零系数个数
.lenv04_lasso_nz_count <- function(cvfit, lambda_mult) {
  lam_use <- cvfit$lambda.min * as.numeric(lambda_mult)
  b_mat   <- as.matrix(glmnet::coef.glmnet(cvfit, s = lam_use))
  sum(abs(b_mat[-1L, 1L]) > 1e-10)
}

#' 扫描 lambda 路径，使非零特征数接近 target_n（移植自 feature_selection_lasso）
.lenv04_auto_calibrate_lambda_mult <- function(cvfit, target_n, init_mult = 0.5) {
  lam_min  <- cvfit$lambda.min
  lam_path <- cvfit$lambda
  if (is.null(lam_path) || !length(lam_path)) return(as.numeric(init_mult))
  target_n <- max(1L, as.integer(target_n)[1L])
  counts <- vapply(lam_path, function(lam) {
    b <- tryCatch(as.matrix(glmnet::coef.glmnet(cvfit, s = lam)), error = function(e) NULL)
    if (is.null(b)) return(NA_integer_)
    sum(abs(b[-1L, 1L]) > 1e-10)
  }, integer(1L))
  valid <- !is.na(counts) & counts > 0L
  if (!any(valid)) return(as.numeric(init_mult))
  idx <- which(valid)[which.min(abs(counts[valid] - target_n))]
  as.numeric(lam_path[idx] / lam_min)
}

#' 首次迭代：若 init_mult 特征不足，在 [0, init_mult] 网格搜索（移植自 feature_selection_lasso）
.lenv04_pick_lambda_mult <- function(cvfit, init_mult, min_features, search_n = 60L) {
  init_mult <- as.numeric(init_mult)[1L]
  if (is.na(init_mult) || init_mult < 0) init_mult <- 0.5
  min_features <- max(1L, as.integer(min_features)[1L])
  n_at <- .lenv04_lasso_nz_count(cvfit, init_mult)
  if (n_at >= min_features) {
    return(list(mult = init_mult, adjusted = FALSE, n_features = n_at))
  }
  n_grid <- max(5L, as.integer(search_n)[1L])
  cand <- unique(c(seq(init_mult, 0, length.out = n_grid), init_mult, 0))
  cand <- sort(cand, decreasing = TRUE)
  best_mult <- init_mult
  best_n    <- n_at
  for (m in cand) {
    n_m <- .lenv04_lasso_nz_count(cvfit, m)
    if (n_m > best_n) {
      best_n <- n_m
      best_mult <- m
    }
    if (n_m >= min_features) {
      return(list(mult = m, adjusted = TRUE, n_features = n_m))
    }
  }
  list(mult = best_mult, adjusted = TRUE, n_features = best_n)
}

#' 当 init_mult 下全/近全入选时，沿 lambda 路径自动收紧（至少剔除若干特征，不设固定目标个数）
.lenv04_auto_tighten_lambda_mult <- function(
    cvfit,
    init_mult,
    n_candidates,
    min_exclude = 1L,
    min_keep = 1L) {
  init_mult <- as.numeric(init_mult)[1L]
  if (is.na(init_mult) || init_mult < 0) init_mult <- 0.5
  lam_min <- cvfit$lambda.min
  lam_path <- cvfit$lambda
  if (is.null(lam_path) || !length(lam_path)) {
    return(list(
      mult = init_mult, n_features = NA_integer_, adjusted = FALSE, reason = "no_path"
    ))
  }

  n_init <- .lenv04_lasso_nz_count(cvfit, init_mult)
  n_candidates <- max(1L, as.integer(n_candidates)[1L])
  min_exclude <- max(1L, as.integer(min_exclude)[1L])
  min_keep <- max(1L, as.integer(min_keep)[1L])
  target_max <- max(min_keep, n_candidates - min_exclude)

  .count_at_lam <- function(lam) {
    b <- tryCatch(as.matrix(glmnet::coef.glmnet(cvfit, s = lam)), error = function(e) NULL)
    if (is.null(b)) return(NA_integer_)
    sum(abs(b[-1L, 1L]) > 1e-10)
  }
  counts <- vapply(lam_path, .count_at_lam, integer(1L))

  if (n_init <= target_max && n_init >= min_keep) {
    return(list(
      mult = init_mult, n_features = n_init, adjusted = FALSE, reason = "init_ok"
    ))
  }

  ok_idx <- which(!is.na(counts) & counts <= target_max & counts >= min_keep)
  if (length(ok_idx)) {
    pick_idx <- ok_idx[1L]
    mult <- lam_path[pick_idx] / lam_min
    return(list(
      mult = mult,
      n_features = counts[pick_idx],
      adjusted = TRUE,
      reason = "path_tighten"
    ))
  }

  lam_1se <- cvfit$lambda.1se
  if (!is.null(lam_1se) && is.finite(lam_1se)) {
    n_1se <- .lenv04_lasso_nz_count(cvfit, lam_1se / lam_min)
    if (is.finite(n_1se) && n_1se < n_init && n_1se >= min_keep) {
      return(list(
        mult = lam_1se / lam_min,
        n_features = n_1se,
        adjusted = TRUE,
        reason = "lambda.1se"
      ))
    }
  }

  ok_idx <- which(!is.na(counts) & counts < n_init & counts >= min_keep)
  if (length(ok_idx)) {
    pick_idx <- ok_idx[1L]
    mult <- lam_path[pick_idx] / lam_min
    return(list(
      mult = mult,
      n_features = counts[pick_idx],
      adjusted = TRUE,
      reason = "exclude_any"
    ))
  }

  list(
    mult = init_mult,
    n_features = n_init,
    adjusted = FALSE,
    reason = "cannot_tighten"
  )
}

.lenv04_plot_barplot <- function(gene_sum, height, cv_times, label_map = NULL) {
  if (!length(gene_sum)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No features selected")
    return(invisible())
  }
  display_names <- names(gene_sum)
  if (!is.null(label_map) && length(label_map)) {
    mapped <- label_map[display_names]
    display_names <- ifelse(!is.na(mapped) & nzchar(mapped), mapped, display_names)
  }
  cxa <- if (length(gene_sum) > 60) 0.32 else if (length(gene_sum) > 30) 0.5 else 0.7
  op <- graphics::par(mar = c(10, 4, 3, 1))
  on.exit(graphics::par(op), add = TRUE)
  graphics::barplot(
    height   = as.numeric(gene_sum),
    names.arg = display_names,
    col      = "cyan",
    border   = "black",
    las      = 2,
    ylim     = c(0, max(cv_times, max(gene_sum, na.rm = TRUE)) * 1.05),
    cex.names = cxa,
    main     = "LASSO feature selection frequency",
    ylab     = "Selection count"
  )
  graphics::abline(h = height, lty = 2, col = "red", lwd = 1.5)
  graphics::legend("topright", legend = paste0("Threshold = ", height),
                   lty = 2, col = "red", bty = "n", cex = 0.85)
  invisible()
}

.lenv04_plot_heatmap <- function(cv_list, height, gene_sum,
                                  top_patterns = NULL, label_map = NULL,
                                  all_input_genes = NULL) {
  selected_genes <- sort(setdiff(unique(unlist(cv_list, use.names = FALSE)), "isNA"))
  all_genes <- if (!is.null(all_input_genes) && length(all_input_genes)) {
    unique(as.character(all_input_genes[nzchar(all_input_genes)]))
  } else {
    selected_genes
  }
  if (!length(all_genes)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No features for heatmap")
    return(invisible())
  }

  gModel_str <- vapply(cv_list, .lenv04_gmodel_str, character(1L))

  gModel_tbl <- sort(table(gModel_str), decreasing = TRUE)
  yyy        <- names(gModel_tbl)[nzchar(names(gModel_tbl))]
  if (!length(yyy)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No model patterns")
    return(invisible())
  }

  yyy_df <- matrix(FALSE, nrow = length(yyy), ncol = length(all_genes),
                   dimnames = list(NULL, all_genes))
  rNames <- character(length(yyy))
  for (ii in seq_along(yyy)) {
    gm <- strsplit(yyy[ii], " ", fixed = TRUE)[[1L]]
    yyy_df[ii, ] <- FALSE
    yyy_df[ii, intersect(all_genes, gm)] <- TRUE
    rNames[ii] <- paste0(length(gm), " features")
  }
  for (ii in seq.int(2L, length(rNames))) {
    if (rNames[ii] %in% rNames[seq_len(ii - 1L)]) {
      rNames[ii] <- paste0(rNames[ii], "*")
    }
  }
  yyy_df <- yyy_df[, order(colnames(yyy_df)), drop = FALSE]
  rownames(yyy_df) <- rNames

  display_names <- colnames(yyy_df)
  if (!is.null(label_map) && length(label_map)) {
    mapped <- label_map[display_names]
    display_names <- ifelse(!is.na(mapped) & nzchar(mapped), mapped, display_names)
    display_names <- gsub("_", " ", display_names, fixed = TRUE)
    colnames(yyy_df) <- display_names
  }

  y_mat <- apply(yyy_df, 2, as.numeric)
  if (!is.matrix(y_mat)) {
    y_mat <- matrix(y_mat, nrow = nrow(yyy_df), ncol = ncol(yyy_df),
                    dimnames = dimnames(yyy_df))
  }
  rownames(y_mat) <- rNames

  gModel_cnt <- as.integer(gModel_tbl[yyy])
  nr  <- nrow(y_mat)
  ng  <- ncol(y_mat)
  cxa <- if (ng > 50) 0.35 else if (ng > 25) 0.5 else 0.65
  bmar <- max(7, min(14, 4 + ng * 0.08))

  op <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(op), add = TRUE)
  graphics::layout(matrix(1:2, nrow = 1L), widths = c(2.2, 1))
  graphics::par(mar = c(bmar, 7, 3, 1))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.5, ng + 0.5), ylim = c(0.5, nr + 0.5),
                        xaxs = "i", yaxs = "i")
  for (iy in seq_len(nr)) {
    for (ix in seq_len(ng)) {
      fill_col <- if (y_mat[nr - iy + 1L, ix] > 0) "yellow" else "white"
      graphics::rect(ix - 0.5, iy - 0.5, ix + 0.5, iy + 0.5,
                     col = fill_col, border = "grey72", lwd = 0.6)
    }
  }
  graphics::axis(1, at = seq_len(ng), labels = colnames(y_mat), las = 2, cex.axis = cxa)
  graphics::axis(2, at = seq_len(nr), labels = rev(rNames), las = 2, cex.axis = 0.72)
  graphics::box()
  graphics::par(mar = c(bmar, 0.5, 3, 4))
  cnt_labels <- paste0(gModel_cnt, " times")
  freq_cols <- grDevices::colorRampPalette(c("pink", "red"))(length(gModel_cnt))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.5, 2.5), ylim = c(0.5, nr + 0.5), xaxs = "i", yaxs = "i")
  for (iy in seq_len(nr)) {
    fill_col <- freq_cols[iy]
    graphics::rect(0.5, iy - 0.5, 1.5, iy + 0.5, col = fill_col, border = "grey72", lwd = 0.6)
    graphics::text(1.65, iy, cnt_labels[nr - iy + 1L], adj = c(0, 0.5), cex = 0.72)
  }
  graphics::box()
  invisible()
}

#' 构建 LASSO 热图矩阵（移植 VOC 最终/Step03_Lasso/C01_Lasso.R §yyy.df / y.df）
#' @param all_input_genes 热图列（默认 = cv 中至少出现一次的变量，同 C01 allGenes）
.lenv04_heatmap_matrix_data <- function(cv_list, label_map = NULL,
                                        all_input_genes = NULL) {
  selected_genes <- setdiff(unique(unlist(cv_list, use.names = FALSE)), "isNA")
  all_genes <- if (!is.null(all_input_genes) && length(all_input_genes)) {
    unique(as.character(all_input_genes[nzchar(all_input_genes)]))
  } else {
    selected_genes
  }
  if (!length(all_genes)) return(NULL)

  gModel_str <- vapply(cv_list, .lenv04_gmodel_str, character(1L))
  gModel_tbl <- sort(table(gModel_str), decreasing = TRUE)
  yyy <- names(gModel_tbl)[nzchar(names(gModel_tbl))]
  if (!length(yyy)) return(NULL)

  yyy_df <- matrix(FALSE, nrow = length(yyy), ncol = length(all_genes),
                   dimnames = list(NULL, all_genes))
  rNames <- character(length(yyy))
  for (ii in seq_along(yyy)) {
    gm <- strsplit(yyy[ii], " ", fixed = TRUE)[[1L]]
    if (length(gm) == 1L && identical(gm, "isNA")) next
    yyy_df[ii, ] <- FALSE
    yyy_df[ii, intersect(all_genes, gm)] <- TRUE
    rNames[ii] <- paste0(length(gm), " features")
  }
  for (ii in seq.int(2L, length(rNames))) {
    if (rNames[ii] %in% rNames[seq_len(ii - 1L)]) {
      rNames[ii] <- paste0(rNames[ii], "*")
    }
  }

  # C01: yyy.df <- yyy.df[, order(colnames(yyy.df))]
  yyy_df <- yyy_df[, order(colnames(yyy_df)), drop = FALSE]
  raw_genes <- colnames(yyy_df)

  display_names <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(raw_genes, label_map)
  } else {
    gsub("_", " ", raw_genes, fixed = TRUE)
  }
  if (!is.null(label_map) && length(label_map)) {
    mapped <- label_map[raw_genes]
    display_names <- ifelse(!is.na(mapped) & nzchar(mapped), mapped, display_names)
  }
  display_names <- ifelse(is.na(display_names) | !nzchar(display_names), raw_genes, display_names)
  display_names <- gsub("_", " ", display_names, fixed = TRUE)
  display_names <- gsub("\\bAMC\\b", "AMCC", display_names, perl = TRUE)
  colnames(yyy_df) <- display_names

  y_mat <- apply(yyy_df, 2, as.numeric)
  if (!is.matrix(y_mat)) {
    y_mat <- matrix(y_mat, nrow = nrow(yyy_df), ncol = ncol(yyy_df),
                    dimnames = list(rNames, display_names))
  } else {
    rownames(y_mat) <- rNames
  }

  list(
    y_mat       = y_mat,
    rNames      = rNames,
    col_names   = display_names,
    raw_genes   = raw_genes,
    gModel_cnt  = as.integer(gModel_tbl[yyy])
  )
}

#' ComplexHeatmap 双面板（移植 C01_Lasso.R：hp1 + hp2，左 features / 右 times）
.lenv04_complex_heatmap_draw <- function(hm, draw = TRUE) {
  if (is.null(hm) || !requireNamespace("ComplexHeatmap", quietly = TRUE)) return(NULL)
  y_mat <- hm$y_mat
  if ("isNA" %in% colnames(y_mat)) {
    y_mat <- y_mat[, setdiff(colnames(y_mat), "isNA"), drop = FALSE]
  }
  gModel_cnt <- as.integer(hm$gModel_cnt)
  if (!nrow(y_mat) || !ncol(y_mat) || !length(gModel_cnt)) return(NULL)

  gModel_mat <- matrix(gModel_cnt, ncol = 1L)
  rownames(gModel_mat) <- paste0(gModel_cnt, " times")

  y_vals <- unique(as.vector(y_mat[is.finite(y_mat)]))
  if (!length(y_vals)) y_vals <- 0
  col_hit <- if (length(y_vals) >= 2L) {
    c("0" = "white", "1" = "yellow")
  } else if (y_vals[1L] > 0) {
    c("1" = "yellow")
  } else {
    c("0" = "white")
  }

  hp1 <- ComplexHeatmap::Heatmap(
    y_mat,
    col = col_hit,
    cluster_rows = FALSE,
    cluster_columns = FALSE,
    rect_gp = grid::gpar(col = "grey", lty = 1, lwd = 2),
    row_names_side = "left",
    show_heatmap_legend = FALSE
  )

  cnt_unique <- unique(gModel_cnt[!is.na(gModel_cnt)])
  hp2 <- if (length(cnt_unique) >= 2L) {
    ComplexHeatmap::Heatmap(
      gModel_mat,
      col = grDevices::colorRampPalette(c("pink", "red"))(length(cnt_unique)),
      cluster_rows = FALSE,
      cluster_columns = FALSE,
      row_names_side = "right",
      show_column_names = FALSE,
      show_heatmap_legend = FALSE
    )
  } else {
    ComplexHeatmap::Heatmap(
      gModel_mat,
      col = c("1" = "pink"),
      cluster_rows = FALSE,
      cluster_columns = FALSE,
      row_names_side = "right",
      show_column_names = FALSE,
      show_heatmap_legend = FALSE,
      cell_fun = function(j, i, x, y, w, h, fill) {
        grid::grid.rect(x, y, w, h, gp = grid::gpar(fill = "pink", col = "grey", lwd = 2))
      }
    )
  }
  hp_list <- hp1 + hp2
  if (isTRUE(draw)) ComplexHeatmap::draw(hp_list, newpage = FALSE)
  hp_list
}

#' Figure 2A：热图（ggplot 子面板；优先 ComplexHeatmap + 右侧频次列）
.lenv04_build_heatmap_ggplots <- function(hm) {
  if (is.null(hm)) return(NULL)

  if (requireNamespace("ComplexHeatmap", quietly = TRUE) &&
      requireNamespace("ggplotify", quietly = TRUE)) {
    p_hm <- tryCatch(
      ggplotify::as.ggplot(function() .lenv04_complex_heatmap_draw(hm, draw = TRUE)),
      error = function(e) {
        cli::cli_alert_warning("ComplexHeatmap 热图回退 ggplot: {e$message}")
        NULL
      }
    )
    if (!is.null(p_hm)) {
      heat_w_inches <- max(12, min(22, 4 + length(hm$col_names) * 0.42))
      return(list(heatmap = p_hm, heat_w_inches = heat_w_inches, use_complex = TRUE))
    }
  }

  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  y_mat  <- hm$y_mat
  rNames <- as.character(hm$rNames)
  rNames <- rNames[nzchar(rNames) & !is.na(rNames)]
  col_names <- as.character(hm$col_names)
  col_names <- col_names[nzchar(col_names) & !is.na(col_names)]
  nr     <- nrow(y_mat)
  ng     <- ncol(y_mat)
  if (!nr || !ng || !length(rNames) || !length(col_names)) return(NULL)

  hm_rows <- vector("list", nr * ng)
  k <- 0L
  for (pi in seq_len(nr)) {
    for (pj in seq_len(ng)) {
      k <- k + 1L
      val <- y_mat[pi, pj]
      hm_rows[[k]] <- data.frame(
        row = rNames[pi],
        col = col_names[pj],
        hit = isTRUE(val) || (is.numeric(val) && val > 0),
        stringsAsFactors = FALSE
      )
    }
  }
  hm_df <- do.call(rbind, hm_rows)
  hm_df$row <- as.character(hm_df$row)
  hm_df$col <- as.character(hm_df$col)
  hm_df <- hm_df[nzchar(hm_df$row) & !is.na(hm_df$row) &
                  nzchar(hm_df$col) & !is.na(hm_df$col), , drop = FALSE]
  if (!nrow(hm_df)) return(NULL)
  rNames <- unique(hm_df$row)
  col_names <- unique(hm_df$col)
  hm_df$row <- factor(hm_df$row, levels = rev(rNames))
  hm_df$col <- factor(hm_df$col, levels = col_names)
  hm_df$fill_status <- factor(
    ifelse(hm_df$hit, "selected", "not"),
    levels = c("not", "selected")
  )

  cxa <- if (length(col_names) > 50) 5 else if (length(col_names) > 25) 5.5 else 6
  heat_w_inches <- max(12, min(22, 4 + length(col_names) * 0.42))
  p_hm <- ggplot2::ggplot(hm_df, ggplot2::aes(x = .data$col, y = .data$row, fill = .data$fill_status)) +
    ggplot2::geom_tile(colour = "grey72", linewidth = 0.35) +
    ggplot2::scale_fill_manual(values = c("not" = "white", "selected" = "yellow"), guide = "none") +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_family = "serif") +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(
        angle = 90, hjust = 1, vjust = 0.5, size = cxa,
        margin = ggplot2::margin(t = 2)
      )
    )

  gModel_cnt <- as.integer(hm$gModel_cnt)
  freq_df <- data.frame(
    row = factor(rNames, levels = rev(rNames)),
    count = gModel_cnt,
    label = paste0(gModel_cnt, " times"),
    stringsAsFactors = FALSE
  )
  if (length(unique(gModel_cnt)) < 2L) {
    p_freq <- ggplot2::ggplot(freq_df, ggplot2::aes(x = 1, y = .data$row)) +
      ggplot2::geom_tile(fill = "pink", colour = "grey72", linewidth = 0.35) +
      ggplot2::geom_text(
        ggplot2::aes(label = .data$label),
        x = 1.08, hjust = 0, size = 3.2, family = "serif"
      ) +
      ggplot2::scale_x_continuous(limits = c(0.5, 2.2), expand = c(0, 0)) +
      ggplot2::labs(x = NULL, y = NULL) +
      ggplot2::theme_void(base_family = "serif") +
      ggplot2::theme(plot.margin = ggplot2::margin(5.5, 8, 5.5, 0, "pt"))
  } else {
    p_freq <- ggplot2::ggplot(freq_df, ggplot2::aes(x = 1, y = .data$row, fill = .data$count)) +
      ggplot2::geom_tile(colour = "grey72", linewidth = 0.35) +
      ggplot2::scale_fill_gradient(low = "pink", high = "red", guide = "none") +
      ggplot2::geom_text(
        ggplot2::aes(label = .data$label),
        x = 1.08, hjust = 0, size = 3.2, family = "serif"
      ) +
      ggplot2::scale_x_continuous(limits = c(0.5, 2.2), expand = c(0, 0)) +
      ggplot2::labs(x = NULL, y = NULL) +
      ggplot2::theme_void(base_family = "serif") +
      ggplot2::theme(plot.margin = ggplot2::margin(5.5, 8, 5.5, 0, "pt"))
  }

  p_combined <- if (requireNamespace("patchwork", quietly = TRUE)) {
    p_hm + p_freq + patchwork::plot_layout(widths = c(4, 1.1), guides = "collect")
  } else if (requireNamespace("cowplot", quietly = TRUE)) {
    cowplot::plot_grid(p_hm, p_freq, ncol = 2, rel_widths = c(4, 1.1), align = "h")
  } else {
    p_hm
  }

  list(heatmap = p_combined, heat_w_inches = heat_w_inches, use_complex = FALSE)
}

#' 仅 1 种 LASSO 模式时：按特征频次绘制更直观的热图（避免单行全黄“空白”感）
.lenv04_plot_feature_freq_heatmap_gg <- function(gene_sum, cv_times, label_map = NULL,
                                                  all_input_genes = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  feats <- if (!is.null(all_input_genes) && length(all_input_genes)) {
    as.character(all_input_genes)
  } else {
    names(gene_sum)
  }
  feats <- feats[nzchar(feats)]
  if (!length(feats)) return(NULL)
  gs <- setNames(rep(0L, length(feats)), feats)
  for (nm in intersect(names(gene_sum), feats)) {
    gs[nm] <- as.integer(gene_sum[[nm]])
  }
  disp <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(names(gs), label_map)
  } else {
    gsub("_", " ", names(gs), fixed = TRUE)
  }
  df <- data.frame(
    feature = factor(disp, levels = rev(disp)),
    count = as.numeric(gs),
    pct = round(100 * as.numeric(gs) / max(1L, cv_times), 1),
    label = paste0(gs, "/", cv_times, " (", round(100 * as.numeric(gs) / max(1L, cv_times), 1), "%)"),
    stringsAsFactors = FALSE
  )
  cnt_range <- range(df$count, na.rm = TRUE)
  fill_scale <- if (diff(cnt_range) < 1e-9) {
    ggplot2::scale_fill_gradient(
      low = "#E6B800", high = "#E6B800",
      limits = c(cnt_range[1L] - 1, cnt_range[1L] + 1),
      name = "Count"
    )
  } else {
    ggplot2::scale_fill_gradient(low = "#FFF7CC", high = "#E6B800", name = "Count")
  }
  ggplot2::ggplot(df, ggplot2::aes(x = "LASSO selection", y = .data$feature, fill = .data$count)) +
    ggplot2::geom_tile(colour = "grey40", linewidth = 0.5) +
    ggplot2::geom_text(ggplot2::aes(label = .data$label), colour = "black", size = 3.2) +
    fill_scale +
    ggplot2::labs(
      title = "LASSO stability (single model pattern)",
      subtitle = paste0("All ", cv_times, " iterations retained the same feature set"),
      x = NULL, y = NULL
    ) +
    ggplot2::theme_minimal(base_family = "serif") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 11),
      plot.subtitle = ggplot2::element_text(size = 9),
      axis.text.x = ggplot2::element_text(size = 10),
      axis.text.y = ggplot2::element_text(size = 9)
    )
}

.lenv04_save_heatmap_pdf <- function(hm_data, hm_gg, fig_path, width = 12, height = 8) {
  if (is.null(hm_data) && (is.null(hm_gg) || is.null(hm_gg$heatmap))) return(FALSE)
  if (isTRUE(hm_gg$single_pattern %||% FALSE) && !is.null(hm_gg$heatmap)) {
    return(tryCatch({
      ggplot2::ggsave(fig_path, plot = hm_gg$heatmap, width = width, height = height)
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("单模式热图保存失败: {e$message}")
      FALSE
    }))
  }
  if (is.null(hm_data)) return(FALSE)
  saved <- FALSE
  if (requireNamespace("ComplexHeatmap", quietly = TRUE)) {
    saved <- tryCatch({
      grDevices::pdf(fig_path, width = width, height = height)
      .lenv04_complex_heatmap_draw(hm_data, draw = TRUE)
      grDevices::dev.off()
      TRUE
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("ComplexHeatmap 热图保存失败: {e$message}")
      FALSE
    })
  }
  if (saved) return(TRUE)
  if (!is.null(hm_gg) && !is.null(hm_gg$heatmap) && requireNamespace("ggplot2", quietly = TRUE)) {
    saved <- tryCatch({
      ggplot2::ggsave(fig_path, plot = hm_gg$heatmap, width = width, height = height)
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("ggplot 热图保存失败: {e$message}")
      FALSE
    })
  }
  saved
}

.lenv04_ggplot_heatmap_panel <- function(hm) {
  parts <- .lenv04_build_heatmap_ggplots(hm)
  if (is.null(parts)) return(NULL)
  parts$heatmap
}

#' Figure 2B：LASSO 入选频次柱状图（ggplot；列与热图一致，含 0 次入选变量）
.lenv04_ggplot_barplot_panel <- function(gene_sum, height, cv_times, label_map = NULL,
                                         all_input_genes = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  gs <- gene_sum
  gs <- gs[names(gs) != "isNA"]
  if (is.null(all_input_genes) || !length(all_input_genes)) {
    all_genes <- names(gs)
  } else {
    all_genes <- unique(as.character(all_input_genes[nzchar(all_input_genes)]))
  }
  if (!length(all_genes)) return(NULL)
  gs_full <- setNames(rep(0L, length(all_genes)), all_genes)
  for (nm in names(gs)) {
    if (nm %in% names(gs_full)) gs_full[nm] <- as.integer(gs[[nm]])
  }
  gs <- gs_full
  gs <- sort(gs, decreasing = TRUE)
  disp_names <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(names(gs), label_map)
  } else {
    gsub("_", " ", names(gs), fixed = TRUE)
  }
  df_bar <- data.frame(
    gene  = factor(disp_names, levels = disp_names),
    value = as.numeric(gs),
    stringsAsFactors = FALSE
  )
  ng <- length(all_genes)
  bar_w <- max(10, min(22, 4 + ng * 0.42))
  cxb <- if (ng > 50) 5 else if (ng > 25) 5.5 else 6
  p <- ggplot2::ggplot(df_bar, ggplot2::aes(x = .data$gene, y = .data$value)) +
    ggplot2::geom_col(fill = "cyan", colour = "black") +
    ggplot2::geom_hline(yintercept = height, linetype = "dashed", colour = "red") +
    ggplot2::scale_y_continuous(limits = c(0, cv_times)) +
    ggplot2::theme_minimal(base_family = "serif") +
    ggplot2::theme(
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(
        angle = 90, vjust = 0.5, hjust = 1, size = cxb,
        margin = ggplot2::margin(t = 2)
      )
    ) +
    ggplot2::labs(x = NULL, y = NULL)
  attr(p, "bar_w_inches") <- bar_w
  p
}

#' A/B 标注合并（移植 C01_Lasso.R：cowplot + A/B，width=8 height=12）
#'
#' 字体优先 Times New Roman；若未嵌入/不可用则回退 serif，避免
#' ``invalid font type`` 导致只保留热图、缺条形图下半部分。
.lenv04_lasso_combine_panels <- function(hm_data, hm_gg, p_bar, fig_path,
                                         width = 8, height = 12) {
  if (is.null(p_bar)) return(invisible(FALSE))
  if (!requireNamespace("cowplot", quietly = TRUE)) {
    cli::cli_alert_warning("LASSO 合并图需要 cowplot 包。")
    return(invisible(FALSE))
  }
  font_candidates <- c("serif")
  if (requireNamespace("extrafont", quietly = TRUE)) {
    avail <- tryCatch(extrafont::fonts(), error = function(e) character(0))
    if ("Times New Roman" %in% avail) {
      font_candidates <- c("Times New Roman", "serif")
    }
  }
  panel_a <- NULL
  if (requireNamespace("ggplotify", quietly = TRUE) &&
      !is.null(hm_data) &&
      requireNamespace("ComplexHeatmap", quietly = TRUE)) {
    panel_a <- tryCatch(
      ggplotify::as.ggplot(function() .lenv04_complex_heatmap_draw(hm_data, draw = TRUE)),
      error = function(e) NULL
    )
  }
  if (is.null(panel_a) && !is.null(hm_gg) && !is.null(hm_gg$heatmap)) {
    panel_a <- hm_gg$heatmap
  }
  if (is.null(panel_a)) {
    cli::cli_alert_warning("LASSO 合并图：无法构建面板 A（需 ComplexHeatmap + ggplotify，或 ggplot 回退）。")
    return(invisible(FALSE))
  }

  .save_with_font <- function(ff) {
    labeled <- list(
      cowplot::ggdraw(panel_a) +
        cowplot::draw_label("A", x = 0.02, y = 0.98, hjust = 0, vjust = 1,
                            size = 10, fontfamily = ff, fontface = "bold"),
      cowplot::ggdraw(p_bar) +
        cowplot::draw_label("B", x = 0.02, y = 0.98, hjust = 0, vjust = 1,
                            size = 10, fontfamily = ff, fontface = "bold")
    )
    comb <- cowplot::plot_grid(labeled[[1L]], labeled[[2L]], ncol = 1L, rel_heights = c(1, 1))
    ggplot2::ggsave(fig_path, plot = comb, width = width, height = height)
    invisible(TRUE)
  }

  for (ff in font_candidates) {
    ok <- tryCatch(.save_with_font(ff), error = function(e) {
      cli::cli_alert_warning("LASSO 合并图字体 {ff} 失败: {e$message}")
      FALSE
    })
    if (isTRUE(ok)) return(invisible(TRUE))
  }

  # 最终回退：无 A/B 标签，仍保证热图+条形图上下拼接
  ok_plain <- tryCatch({
    comb <- cowplot::plot_grid(panel_a, p_bar, ncol = 1L, rel_heights = c(1, 1),
                               labels = c("A", "B"), label_size = 10)
    ggplot2::ggsave(fig_path, plot = comb, width = width, height = height)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("LASSO 合并图无标签回退失败: {e$message}")
    FALSE
  })
  invisible(isTRUE(ok_plain))
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────

block_lasso_environment_voc <- function(ctx, ...) {
  suppressPackageStartupMessages(library(glmnet))

  cfg    <- ctx$config
  bl_cfg <- cfg$lasso_environment %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("lasso_environment_voc: 未找到数据，请先运行 process_environment_data block。")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group  %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")

  if (!outcome_col %in% names(data)) {
    stop("lasso_environment_voc: 结局列 '", outcome_col, "' 不在数据中。")
  }

  # ── 确定候选 VOC 列（须先通过 environment_voc_clinical_gate）──────────────
  gate_vocs <- as.character(ctx$results$select_vocs_clinical_gate %||% character(0))
  gate_vocs <- gate_vocs[nzchar(gate_vocs)]

  env_cols <- bl_cfg$env_cols %||% character(0)
  env_cols <- as.character(env_cols[nzchar(env_cols)])

  if (!length(env_cols) && exists("environment_voc_allowlist", mode = "function")) {
    env_cols <- environment_voc_allowlist(data, cfg)
  }
  if (!length(env_cols)) {
    env_cols <- as.character(ctx$results$voc_columns %||% character(0))
  }
  if (!length(env_cols) && exists("environment_resolve_voc_columns", mode = "function")) {
    env_cols <- environment_resolve_voc_columns(data, cfg)
  }

  if (exists("environment_intersect_voc_only", mode = "function")) {
    env_cols <- environment_intersect_voc_only(env_cols, data, cfg)
  }

  if (length(gate_vocs)) {
    env_cols <- intersect(env_cols, gate_vocs)
    cli::cli_alert_info(
      "lasso_environment_voc: 临床四门禁后候选 {length(env_cols)} 个 VOC"
    )
  } else if (isTRUE((cfg$environment_voc_clinical_gate %||% list())$enable %||% TRUE)) {
    gate_cfg <- cfg$environment_voc_clinical_gate %||% list()
    require_gate <- isTRUE(bl_cfg$require_clinical_gate %||%
      gate_cfg$require_pass_for_lasso %||% TRUE)
    if (!is.null(ctx$results$select_vocs_clinical_gate) && require_gate) {
      cli::cli_alert_warning(
        "lasso_environment_voc: select_vocs_clinical_gate 为空（单因素门禁 0 个通过），跳过 LASSO，不进入 GLM。"
      )
      ctx$results$select_vocs_lasso <- character(0)
      ctx$results$select_vocs <- character(0)
      ctx$results$lasso_environment_voc_skipped <- TRUE
      return(ctx)
    }
    if (!is.null(ctx$results$select_vocs_clinical_gate)) {
      cli::cli_alert_warning(
        "lasso_environment_voc: select_vocs_clinical_gate 为空，回退使用全部 env_cols（recovery 模式）。"
      )
    } else {
      cli::cli_alert_warning(
        "lasso_environment_voc: select_vocs_clinical_gate 未设置，请确认 environment_voc_clinical_gate 已运行。回退使用全部 env_cols。"
      )
    }
  }

  if (!length(env_cols)) {
    stop(
      "lasso_environment_voc: 未找到环境毒物/VOC 列；请确认 Step00 已写入 voc_columns。",
      call. = FALSE
    )
  }
  cli::cli_alert_info("lasso_environment_voc: 环境毒物候选 {length(env_cols)} 个。")
  env_cols <- intersect(env_cols, names(data))

  # 手动排除
  exclude_vars <- as.character(bl_cfg$exclude_vars %||% character(0))
  if (length(exclude_vars)) {
    removed <- intersect(exclude_vars, env_cols)
    if (length(removed)) {
      cli::cli_alert_info(
        "lasso_environment_voc: 手动排除: {paste(removed, collapse = ', ')}"
      )
    }
    env_cols <- setdiff(env_cols, exclude_vars)
  }

  if (length(env_cols) < 2L) {
    cli::cli_alert_warning(
      "lasso_environment_voc: 候选 VOC 仅 {length(env_cols)} 个（<2），跳过 LASSO；GLM 不接收未跑 LASSO 的 VOC。"
    )
    ctx$results$select_vocs_lasso <- character(0)
    ctx$results$select_vocs <- character(0)
    ctx$results$lasso_gene_sum <- NULL
    ctx$results$lasso_height <- NA_integer_
    ctx$results$lasso_cv_list <- NULL
    ctx$results$lasso_environment_voc_skipped <- TRUE
    return(ctx)
  }

  cli::cli_alert_info("lasso_environment_voc: 初始候选 {length(env_cols)} 个 VOC。")

  # ── 单因素 GLM 预筛 ───────────────────────────────────────────────────────
  p_cutoff <- as.numeric(bl_cfg$univariate_p_cutoff %||% 0.05)
  or_min   <- as.numeric(bl_cfg$univariate_or_min   %||% 1.0)
  or_max   <- as.numeric(bl_cfg$univariate_or_max   %||% 10.0)
  uni_enable <- isTRUE(bl_cfg$univariate_enable %||% TRUE)

  if (uni_enable) {
    cli::cli_h2("lasso_environment_voc: 单因素 GLM 预筛 (p<{p_cutoff}, OR>{or_min})")
    uni_res <- .lenv04_univariate_screen(
      data, env_cols, outcome_col, analysis_grp, reference_grp,
      p_cutoff, or_min, or_max
    )
    sig_table <- uni_res$table
    if (nrow(sig_table)) {
      sig_fn <- if (exists("environment_is_p_significant", mode = "function")) {
        environment_is_p_significant
      } else {
        function(p, thr) {
          p_num <- suppressWarnings(as.numeric(p))
          !is.na(p_num) && p_num < thr
        }
      }
      sig_mask <- vapply(sig_table$P, function(p) sig_fn(p, p_cutoff), logical(1L))
      sig_table <- sig_table[sig_mask, , drop = FALSE]
    }
    ctx$results$select_vocs_univar   <- uni_res$keep
    ctx$results$univariate_env_table <- sig_table

    cli::cli_alert_success(
      "  单因素预筛: {length(env_cols)} → {length(uni_res$keep)} 个特征通过"
    )
    lasso_input_cols <- uni_res$keep

    if (length(lasso_input_cols) < 2L) {
      cli::cli_alert_warning(
        "lasso_environment_voc: 预筛后候选仅 {length(lasso_input_cols)} 个，跳过 LASSO；GLM 不接收未跑 LASSO 的 VOC。"
      )
      ctx$results$select_vocs_lasso <- character(0)
      ctx$results$select_vocs <- character(0)
      ctx$results$lasso_environment_voc_skipped <- TRUE
      return(ctx)
    }
  } else {
    lasso_input_cols <- env_cols
    ctx$results$select_vocs_univar <- lasso_input_cols
  }

  # ── 准备 LASSO 输入矩阵 ───────────────────────────────────────────────────
  y01 <- .lenv04_prepare_outcome_binary(data, outcome_col, analysis_grp, reference_grp)
  cols_use <- unique(c(outcome_col, lasso_input_cols))
  d0   <- data[, cols_use, drop = FALSE]
  d0$`.y01` <- y01
  d0 <- d0[stats::complete.cases(d0), , drop = FALSE]

  if (nrow(d0) < 20L) {
    stop("lasso_environment_voc: 完整样本不足 20 行（current: ", nrow(d0), "）。")
  }

  if (length(lasso_input_cols) < 2L) {
    cli::cli_alert_warning(
      "lasso_environment_voc: 候选仅 {length(lasso_input_cols)} 个（<2），跳过 LASSO；GLM 不接收未跑 LASSO 的 VOC。"
    )
    ctx$results$select_vocs_lasso <- character(0)
    ctx$results$select_vocs <- character(0)
    ctx$results$lasso_environment_voc_skipped <- TRUE
    return(ctx)
  }

  y_vec <- d0$`.y01`
  feats <- intersect(lasso_input_cols, names(d0))
  lasso_heatmap_cols <- feats
  xx    <- as.matrix(d0[, feats, drop = FALSE])

  # ── 调查权重（与 d0 行对齐，仅保留 complete.cases 对应行）─────────────────
  lasso_wt_col <- as.character(
    bl_cfg$weight_col %||% (cfg$nhanes %||% list())$survey_weight %||% "new_Weight"
  )[1L]
  lasso_weights <- NULL
  if (nzchar(lasso_wt_col) && lasso_wt_col %in% names(data)) {
    # d0 是 data[complete.cases(data[, cols_use]), ]；需用原始行索引对齐
    orig_cc <- which(stats::complete.cases(data[, cols_use, drop = FALSE]))
    w_all <- as.numeric(data[[lasso_wt_col]])
    w_sub <- w_all[orig_cc]
    w_sub[!is.finite(w_sub) | w_sub <= 0] <- NA_real_
    if (any(is.finite(w_sub))) {
      # 归一化到均值=1，避免数量级影响 lambda 选择
      w_mean <- mean(w_sub, na.rm = TRUE)
      lasso_weights <- w_sub / w_mean
      lasso_weights[is.na(lasso_weights)] <- 1
      cli::cli_alert_info(
        "lasso_environment_voc: 加权 LASSO（weights = {lasso_wt_col}，归一化后均值=1）"
      )
    }
  }

  # ── 并行 LASSO ───────────────────────────────────────────────────────────
  cv_times         <- as.integer(bl_cfg$cv_times %||% 1000L)
  lambda_mult      <- as.numeric(bl_cfg$lambda_multiplier %||% 0.5)
  cv_folds         <- as.integer(bl_cfg$cv_folds %||% 10L)
  seed             <- as.integer(bl_cfg$seed %||% 123L)
  min_n <- if (exists("environment_min_mixture_n", mode = "function")) {
    environment_min_mixture_n(cfg, "lasso_environment", 7L)
  } else {
    as.integer(bl_cfg$min_select_vocs %||% 7L)
  }
  n_cores_cfg      <- bl_cfg$n_cores
  n_cores          <- if (is.null(n_cores_cfg)) {
    max(1L, floor(parallel::detectCores(logical = FALSE) / 2L))
  } else {
    as.integer(n_cores_cfg)
  }
  n_cores <- max(1L, min(n_cores, parallel::detectCores(logical = TRUE), cv_times))

  auto_tighten <- isTRUE(bl_cfg$auto_lambda_tighten %||% TRUE)
  if (auto_tighten && length(feats) >= 2L) {
    set.seed(seed)
    cvfit0 <- glmnet::cv.glmnet(
      xx, y_vec, family = "binomial", weights = lasso_weights,
      nfolds = min(cv_folds, max(3L, nrow(xx) %/% 5L))
    )
    tighten <- .lenv04_auto_tighten_lambda_mult(
      cvfit0,
      init_mult = lambda_mult,
      n_candidates = length(feats),
      min_exclude = as.integer(bl_cfg$auto_lambda_min_exclude %||% 1L),
      min_keep = min_n
    )
    if (isTRUE(tighten$adjusted)) {
      lambda_mult <- tighten$mult
      cli::cli_alert_info(
        "LASSO lambda 自动收紧: mult={round(lambda_mult, 4)} → 预计 {tighten$n_features}/{length(feats)} 个非零（{tighten$reason}）"
      )
    } else {
      cli::cli_alert_info(
        "LASSO lambda 自动校准: 保持 mult={round(lambda_mult, 4)}（{tighten$n_features} 个非零，{tighten$reason}）"
      )
    }
    # 若 lambda_mult=0 导致全选，改用 lambda.1se
    n_with_mult <- .lenv04_lasso_nz_count(cvfit0, lambda_mult)
    if (is.finite(n_with_mult) && n_with_mult >= length(feats) && length(feats) > 1L) {
      lam_1se <- cvfit0$lambda.1se
      if (!is.null(lam_1se) && is.finite(lam_1se)) {
        lambda_mult <- lam_1se / cvfit0$lambda.min
        cli::cli_alert_info(
          "LASSO lambda 二次调整（全选回退lambda.1se）: mult={round(lambda_mult, 4)}"
        )
      }
    }
    ctx$results$lasso_lambda_mult <- lambda_mult
    ctx$results$lasso_lambda_auto_reason <- tighten$reason
  }

  cli::cli_h2(
    "lasso_environment_voc: 运行 {cv_times} 次 cv.glmnet (lambda.min × {round(lambda_mult, 4)}, 同 VOC 最终/C01_Lasso.R)"
  )

  set.seed(seed)

  .one_lasso_iter <- function(iter_idx) {
    set.seed(seed + as.integer(iter_idx))
    cvfit <- glmnet::cv.glmnet(xx, y_vec, family = "binomial",
                               weights = lasso_weights)
    lam_use <- cvfit$lambda.min * lambda_mult
    b_mat   <- as.matrix(glmnet::coef.glmnet(cvfit, s = lam_use))
    keep    <- abs(b_mat[, 1L]) > 0 & rownames(b_mat) != "(Intercept)"
    b_sub   <- b_mat[keep, , drop = FALSE]
    if (!nrow(b_sub)) return("isNA")
    rownames(b_sub)
  }

  cv_list <- tryCatch({
    if (n_cores > 1L) {
      cl <- parallel::makeCluster(n_cores)
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterExport(
        cl,
        varlist = c("xx", "y_vec", "lambda_mult", "seed", "lasso_weights", ".one_lasso_iter"),
        envir   = environment()
      )
      parallel::clusterEvalQ(cl, { library(glmnet); NULL })
      parallel::parLapply(cl, seq_len(cv_times), .one_lasso_iter)
    } else {
      lapply(seq_len(cv_times), function(ii) {
        if (ii %% 100L == 0L) {
          cli::cli_alert_info("  LASSO 进度: {ii}/{cv_times}")
        }
        .one_lasso_iter(ii)
      })
    }
  }, error = function(e) {
    cli::cli_alert_warning("lasso_environment_voc: 并行失败，回退串行: {e$message}")
    lapply(seq_len(cv_times), .one_lasso_iter)
  })

  # ── 频次与入选（VOC 最终：floor(最高模式次数/100)×100，geneSum > height）──
  freq_res  <- .lenv04_compute_freq_threshold(
    cv_list, cv_times,
    as.character(bl_cfg$freq_cutoff_method %||% "auto_floor100"),
    as.numeric(bl_cfg$freq_cutoff_frac %||% 0.9),
    bl_cfg$freq_cutoff_n
  )
  gene_sum  <- freq_res$gene_sum
  freq_method <- as.character(bl_cfg$freq_cutoff_method %||% "auto_floor100")
  height    <- if (identical(freq_method, "auto_floor100")) {
    .lenv04_lasso_height_standard(freq_res$gmodel_tbl, cv_times)
  } else {
    freq_res$height
  }
  n_patterns <- length(freq_res$gmodel_tbl)
  top_pat_n <- if (n_patterns) as.integer(freq_res$gmodel_tbl[[1L]]) else NA_integer_
  cli::cli_alert_info(
    "LASSO 模式数={n_patterns}，最高模式出现 {top_pat_n} 次，频次阈值={height}"
  )

  ranked_pool <- names(sort(gene_sum, decreasing = TRUE))
  ranked_pool <- intersect(ranked_pool, feats)
  if (length(ranked_pool) < min_n) {
    uni_keep <- as.character(ctx$results$select_vocs_univar %||% character(0))
    ranked_pool <- unique(c(ranked_pool, intersect(uni_keep, feats)))
  }

  select_vocs_lasso <- sort(names(gene_sum)[gene_sum > height])
  select_vocs_lasso <- intersect(select_vocs_lasso, feats)

  if (length(select_vocs_lasso) < min_n &&
      exists("environment_enforce_min_selection", mode = "function")) {
    select_vocs_lasso <- environment_enforce_min_selection(
      select_vocs_lasso, ranked_pool, min_n
    )
  } else if (length(select_vocs_lasso) < min_n) {
    select_vocs_lasso <- unique(c(
      select_vocs_lasso,
      ranked_pool[seq_len(min(min_n, length(ranked_pool)))]
    ))[seq_len(min(min_n, length(ranked_pool)))]
  }

  if (!length(select_vocs_lasso)) {
    cli::cli_alert_warning(
      "lasso_environment_voc: 频次阈值 {height}/{cv_times} 下无特征，已回退 Top-{min_n}。"
    )
    select_vocs_lasso <- ranked_pool[seq_len(min(min_n, length(ranked_pool)))]
  }

  ctx$results$select_vocs_lasso <- select_vocs_lasso
  ctx$results$lasso_gene_sum    <- gene_sum
  ctx$results$lasso_height      <- height
  ctx$results$lasso_cv_list     <- cv_list

  # 同时写入通用的 select_vocs 供下游 block 使用
  ctx$results$select_vocs <- select_vocs_lasso

  cli::cli_alert_success(
    "lasso_environment_voc: 频次阈值={height}，筛出 {length(select_vocs_lasso)} 个特征: {paste(select_vocs_lasso, collapse=', ')}"
  )

  # ── 单因素显著表（P<cutoff）──────────────────────────────────────────────
  uni_export <- ctx$results$univariate_env_table
  if (!is.null(uni_export) && nrow(uni_export)) {
    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    tbl_path <- file.path(tbl_dir, as.character(bl_cfg$table_filename %||% "Table_Lasso_Univariate_Screen.xlsx"))
    tryCatch({
      if (requireNamespace("openxlsx", quietly = TRUE)) {
        wb <- openxlsx::createWorkbook()
        openxlsx::addWorksheet(wb, "Sheet1")
        openxlsx::writeData(wb, "Sheet1", uni_export, startRow = 1L)
        openxlsx::saveWorkbook(wb, tbl_path, overwrite = TRUE)
      } else {
        utils::write.csv(uni_export, sub("\\.xlsx$", ".csv", tbl_path), row.names = FALSE)
      }
      cli::cli_alert_success("单因素表已保存: {basename(tbl_path)}")
    }, error = function(e) {
      cli::cli_alert_warning("LASSO 单因素表导出失败: {e$message}")
    })
  }

  # ── 图形（对齐 VOC 最终：Figure 2A=heatmap, Figure 2B=barplot）────────────
  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$fig_label_mapping)
  } else {
    bl_cfg$fig_label_mapping
  }
  top_n_pat <- as.integer(bl_cfg$fig_top_patterns %||% 6L)

  output_dir_figures <- file.path(ctx$output_dir %||% ".", "Figures")
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)

  fig_heat_name <- as.character(
    bl_cfg$fig_heatmap_filename %||% "Figure 2A. Lasso heatmap.pdf"
  )
  fig_bar_name  <- as.character(
    bl_cfg$fig_barplot_filename %||% "Figure 2B. Lasso barplot.pdf"
  )
  fig_comb_name <- as.character(
    bl_cfg$fig_combined_filename %||%
      "Figure 2. Selection of Environmental exposure variables for 1000 Lasso regression.pdf"
  )
  fig_heat_path <- file.path(output_dir_figures, fig_heat_name)
  fig_bar_path  <- file.path(output_dir_figures, fig_bar_name)
  fig_comb_path <- file.path(output_dir_figures, fig_comb_name)

  # 若全部迭代选出相同模式（热图只有1行），展示所有非 isNA 模式，不过滤
  unique_models <- length(unique(vapply(cv_list, .lenv04_gmodel_str, character(1L))))
  cli::cli_alert_info("LASSO 模式多样性: {unique_models} 个不同模式（共 {cv_times} 次）")
  hm_data   <- .lenv04_heatmap_matrix_data(cv_list, label_map, all_input_genes = lasso_heatmap_cols)
  hm_gg     <- if (unique_models <= 1L) {
    p_single <- .lenv04_plot_feature_freq_heatmap_gg(
      gene_sum, cv_times, label_map, all_input_genes = lasso_heatmap_cols
    )
    if (!is.null(p_single)) {
      list(heatmap = p_single, heat_w_inches = max(8, 3 + length(lasso_heatmap_cols) * 0.5),
           use_complex = FALSE, single_pattern = TRUE)
    } else {
      .lenv04_build_heatmap_ggplots(hm_data)
    }
  } else {
    .lenv04_build_heatmap_ggplots(hm_data)
  }
  p_bar   <- .lenv04_ggplot_barplot_panel(gene_sum, height, cv_times, label_map,
                                        all_input_genes = lasso_heatmap_cols)
  n_pat   <- if (!is.null(hm_data)) length(hm_data$rNames) else 6L
  ng_feat <- length(feats)
  heat_w  <- 12
  heat_h  <- 8
  bar_w   <- 8
  bar_h   <- 6
  comb_h  <- 12
  comb_w  <- 8

  if (!is.null(hm_data)) {
    n_pat_base <- length(hm_data$rNames)
    heat_h <- max(5, min(20, n_pat_base * 0.55 + 3))
    tryCatch({
      saved <- .lenv04_save_heatmap_pdf(hm_data, hm_gg, fig_heat_path, heat_w, heat_h)
      if (!saved) {
        grDevices::pdf(fig_heat_path, width = heat_w, height = heat_h)
        .lenv04_plot_heatmap(cv_list, height, gene_sum, label_map = label_map,
                             all_input_genes = feats)
        grDevices::dev.off()
        cli::cli_alert_info("热图已用 base graphics 回退保存")
      }
      file.copy(fig_heat_path,
                file.path(output_dir_figures, "Figure_Lasso_B_Heatmap.pdf"),
                overwrite = TRUE)
      cli::cli_alert_success("{fig_heat_name} 已保存")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("热图保存失败: {e$message}")
    })
  } else {
    tryCatch({
      n_pat_base <- length(freq_res$gmodel_tbl)
      h_fig <- max(8, min(20, n_pat_base * 0.45 + 3))
      grDevices::pdf(fig_heat_path, width = 12, height = h_fig)
      .lenv04_plot_heatmap(cv_list, height, gene_sum, label_map = label_map,
                           all_input_genes = feats)
      grDevices::dev.off()
      cli::cli_alert_success("{fig_heat_name} 已保存（base 回退）")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("热图保存失败: {e$message}")
    })
  }

  if (!is.null(p_bar)) {
    tryCatch({
      ggplot2::ggsave(fig_bar_path, plot = p_bar, width = bar_w, height = bar_h)
      file.copy(fig_bar_path,
                file.path(output_dir_figures, "Figure_Lasso_A_Barplot.pdf"),
                overwrite = TRUE)
      cli::cli_alert_success("{fig_bar_name} 已保存")
    }, error = function(e) {
      cli::cli_alert_warning("条形图保存失败: {e$message}")
    })
  }

  if (!is.null(p_bar) && (!is.null(hm_data) || !is.null(hm_gg))) {
    tryCatch({
      if (isTRUE(hm_gg$single_pattern %||% FALSE) && !is.null(hm_gg$heatmap)) {
        ggplot2::ggsave(fig_comb_path, plot = hm_gg$heatmap, width = comb_w,
                        height = max(6, 2 + length(lasso_heatmap_cols) * 0.45))
        cli::cli_alert_success("{fig_comb_name} 已保存（单模式频次图）")
      } else {
        ok <- .lenv04_lasso_combine_panels(hm_data, hm_gg, p_bar, fig_comb_path,
                                           width = comb_w, height = comb_h)
        if (isTRUE(ok)) {
          cli::cli_alert_success("{fig_comb_name} 已保存")
        }
      }
    }, error = function(e) {
      cli::cli_alert_warning("LASSO 合并图保存失败: {e$message}")
    })
  } else {
    cli::cli_alert_warning("LASSO 合并图跳过：热图或条形图面板未生成。")
  }

  ctx
}

register_block(
  "lasso_environment_voc",
  block_lasso_environment_voc,
  "\u73af\u5883\u66b4\u9732 VOC \u5355\u56e0\u7d20 GLM \u9884\u7b5b + 1000\u6b21\u5e76\u884c LASSO \u7a33\u5b9a\u6027\u9009\u62e9\uff08Figure_Lasso_A/B\uff09"
)
