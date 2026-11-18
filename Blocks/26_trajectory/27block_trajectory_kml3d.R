###############################################################################
#  multimorbidity_kml3d_trajectory — 双纵向暴露联合轨迹聚类（CH 选 k）
#
#  register_block: "multimorbidity_kml3d_trajectory"
#  对齐 hrs/step03_kml3d + Wang 2025：禁止随机 proxy；需真实 long/宽表列
###############################################################################

.mm_calinski_harabasz <- function(x, cl) {
  cl <- as.integer(cl)
  ok <- is.finite(cl) & complete.cases(x)
  x <- x[ok, , drop = FALSE]
  cl <- cl[ok]
  k <- length(unique(cl))
  n <- nrow(x)
  if (k < 2L || n <= k) return(NA_real_)
  overall <- colMeans(x)
  ss_b <- 0
  ss_w <- 0
  for (g in unique(cl)) {
    xi <- x[cl == g, , drop = FALSE]
    ni <- nrow(xi)
    if (ni < 1L) next
    m <- colMeans(xi)
    ss_b <- ss_b + ni * sum((m - overall)^2)
    ss_w <- ss_w + sum(scale(xi, center = m, scale = FALSE)^2)
  }
  if (ss_w <= 0) return(NA_real_)
  (ss_b / (k - 1)) / (ss_w / (n - k))
}

.mm_build_joint_matrix <- function(data, id_col, wave_col, waves, col_a, col_b) {
  waves <- as.integer(waves)
  if (!id_col %in% names(data)) stop("kml3d: 缺 id 列 ", id_col, call. = FALSE)
  # 宽表：col_a_w8 风格
  wide_a <- paste0(col_a, "_w", waves)
  wide_b <- paste0(col_b, "_w", waves)
  if (all(wide_a %in% names(data)) && all(wide_b %in% names(data))) {
    ids <- data[[id_col]]
    mat <- cbind(
      as.matrix(data[, wide_a, drop = FALSE]),
      as.matrix(data[, wide_b, drop = FALSE])
    )
    storage.mode(mat) <- "double"
    colnames(mat) <- c(wide_a, wide_b)
    return(list(mat = mat, id = ids, format = "wide"))
  }
  # long 表
  if (!wave_col %in% names(data)) {
    stop("kml3d: 需要 long 表 wave 列或宽表 ", paste(wide_a, collapse = "/"), call. = FALSE)
  }
  if (!col_a %in% names(data) || !col_b %in% names(data)) {
    stop("kml3d: 缺轨迹列 ", col_a, " / ", col_b, "（禁止随机 proxy）", call. = FALSE)
  }
  d <- data[data[[wave_col]] %in% waves, c(id_col, wave_col, col_a, col_b), drop = FALSE]
  d[[col_a]] <- suppressWarnings(as.numeric(d[[col_a]]))
  d[[col_b]] <- suppressWarnings(as.numeric(d[[col_b]]))
  # 每人每波一行 → 宽拼
  ids <- unique(as.character(d[[id_col]]))
  mat <- matrix(NA_real_, nrow = length(ids), ncol = 2L * length(waves))
  colnames(mat) <- c(paste0(col_a, "_w", waves), paste0(col_b, "_w", waves))
  rownames(mat) <- ids
  for (i in seq_along(waves)) {
    w <- waves[[i]]
    sub <- d[d[[wave_col]] == w, , drop = FALSE]
    idx <- match(as.character(sub[[id_col]]), ids)
    mat[idx, i] <- sub[[col_a]]
    mat[idx, length(waves) + i] <- sub[[col_b]]
  }
  list(mat = mat, id = ids, format = "long")
}

block_multimorbidity_kml3d_trajectory <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_kml3d: 无数据", call. = FALSE)

  id_col <- as.character(bl$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  wave_col <- as.character(bl$wave_col %||% "Followup_wave")[1L]
  waves <- bl$waves %||% sort(unique(stats::na.omit(as.integer(data[[wave_col]]))))
  if (!length(waves)) waves <- 1:3
  col_a <- as.character(bl$exposure_a_col %||% bl$bmi_col %||% "BMI")[1L]
  col_b <- as.character(bl$exposure_b_col %||% bl$depression_score_col %||% "Depression_Score")[1L]
  cl_col <- as.character(bl$trajectory_cluster_col %||% "trajectory_cluster")[1L]
  min_prop <- suppressWarnings(as.numeric(bl$min_cluster_prop %||% 0.05)[1L])
  seed <- as.integer(bl$kml3d_seed %||% 20260331L)[1L]
  k_fix <- as.integer(bl$kml3d_clusters %||% NA_integer_)[1L]
  k_cand <- as.integer(bl$kml3d_k_candidates %||% 2:6)

  built <- .mm_build_joint_matrix(data, id_col, wave_col, waves, col_a, col_b)
  mat <- built$mat
  # 完整病例
  keep <- stats::complete.cases(mat)
  mat2 <- mat[keep, , drop = FALSE]
  ids2 <- built$id[keep]
  if (nrow(mat2) < 30L) stop("kml3d: 完整轨迹个体过少 n=", nrow(mat2), call. = FALSE)

  # 标准化各列
  mat_z <- scale(mat2)
  mat_z[!is.finite(mat_z)] <- 0

  ch_tab <- data.frame(k = integer(0), CH = numeric(0), ok = logical(0))
  fits <- list()
  for (k in k_cand) {
    set.seed(seed + k)
    km <- tryCatch(
      stats::kmeans(mat_z, centers = k, nstart = 25L, iter.max = 100L),
      error = function(e) NULL
    )
    if (is.null(km)) next
    prop <- min(tabulate(km$cluster, nbins = k)) / length(km$cluster)
    ch <- .mm_calinski_harabasz(mat_z, km$cluster)
    ok <- is.finite(ch) && prop >= min_prop
    ch_tab <- rbind(ch_tab, data.frame(k = k, CH = ch, ok = ok, min_prop = prop))
    if (isTRUE(ok)) fits[[as.character(k)]] <- km
  }
  if (is.finite(k_fix) && as.character(k_fix) %in% names(fits)) {
    best_k <- k_fix
  } else if (nrow(ch_tab)) {
    ok_rows <- ch_tab[isTRUE(ch_tab$ok) | ch_tab$ok, , drop = FALSE]
    if (!nrow(ok_rows)) ok_rows <- ch_tab
    best_k <- ok_rows$k[which.max(ok_rows$CH)]
  } else {
    stop("kml3d: 聚类失败", call. = FALSE)
  }
  km_best <- fits[[as.character(best_k)]]
  if (is.null(km_best)) {
    set.seed(seed)
    km_best <- stats::kmeans(mat_z, centers = best_k, nstart = 25L)
  }

  assign <- data.frame(
    id_tmp = as.character(ids2),
    cluster_tmp = factor(paste0("Group", km_best$cluster)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(assign) <- c(id_col, cl_col)

  # 合并回 data（按 id；long 则每人多行同簇）
  data[[id_col]] <- as.character(data[[id_col]])
  assign[[id_col]] <- as.character(assign[[id_col]])
  if (cl_col %in% names(data)) data[[cl_col]] <- NULL
  data <- merge(data, assign, by = id_col, all.x = TRUE)

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Trajectory")
  fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures", "pdf")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(assign, file.path(out, "Table_Kml3D_Trajectory_Assignment.csv"), row.names = FALSE)
  utils::write.csv(ch_tab, file.path(out, "Table_Kml3D_CH_Criterion.csv"), row.names = FALSE)

  # 轨迹均值图 Fig3
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    means <- list()
    for (g in levels(assign[[cl_col]])) {
      idx <- assign[[cl_col]] == g
      m <- colMeans(mat2[idx, , drop = FALSE], na.rm = TRUE)
      n_w <- length(waves)
      means[[length(means) + 1L]] <- data.frame(
        Group = g, Wave = waves, Series = col_a, Mean = as.numeric(m[seq_len(n_w)]),
        stringsAsFactors = FALSE
      )
      means[[length(means) + 1L]] <- data.frame(
        Group = g, Wave = waves, Series = col_b, Mean = as.numeric(m[n_w + seq_len(n_w)]),
        stringsAsFactors = FALSE
      )
    }
    md <- do.call(rbind, means)
    cols <- if (exists("block_colors", mode = "function")) {
      block_colors(nlevels(assign[[cl_col]]))
    } else {
      grDevices::hcl.colors(nlevels(assign[[cl_col]]), "Dark 3")
    }
    p <- ggplot2::ggplot(md, ggplot2::aes(Wave, Mean, color = Group, group = Group)) +
      ggplot2::geom_line(linewidth = 1) + ggplot2::geom_point(size = 2) +
      ggplot2::facet_wrap(~Series, scales = "free_y") +
      ggplot2::scale_color_manual(values = cols) +
      ggplot2::theme_bw(base_family = "serif") +
      ggplot2::labs(title = "Joint trajectories (Kml3D-style k-means)", y = "Mean")
    ggplot2::ggsave(file.path(fig, "Figure 3. Joint trajectories Kml3D.pdf"), p, width = 10, height = 4.5)
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$multimorbidity_kml3d <- list(
    output_dir = out, n_clusters = best_k, ch_table = ch_tab,
    cluster_col = cl_col, n_complete = nrow(mat2)
  )
  cli::cli_alert_success("Kml3D 联合轨迹完成（k={best_k}, n={nrow(mat2)}）")
  ctx
}

register_block(
  "multimorbidity_kml3d_trajectory",
  block_multimorbidity_kml3d_trajectory,
  "Kml3D 联合轨迹聚类"
)
