###############################################################################
# kmeans_elbow_bivar — 二维 k-means + elbow；Class 语义锚定
###############################################################################

block_kmeans_elbow_bivar <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("kmeans_elbow_bivar: 无数据", call. = FALSE)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  if (!ckm_stroke_is_full_depth(idx, bl)) {
    cli::cli_alert_info("kmeans_elbow_bivar: {idx} 跳过")
    ctx$results$kmeans_elbow_bivar <- list(skipped = TRUE)
    return(ctx)
  }
  if (!all(c("eGDR_t1", "eGDR_t2") %in% names(data))) {
    stop("缺少 eGDR_t1/eGDR_t2", call. = FALSE)
  }

  mat <- cbind(as.numeric(data$eGDR_t1), as.numeric(data$eGDR_t2))
  colnames(mat) <- c("t1", "t2")

  # 外验模式：固定发现队列中心，跳过本库重拟合
  fc_path <- bl$fixed_centers_csv %||% ""
  if (nzchar(as.character(fc_path)[1L])) {
    centers <- ckm_stroke_read_fixed_centers_csv(fc_path)
    cls <- ckm_stroke_kmeans_assign_centers(mat, centers)
    data$eGDR_Class <- cls
    data$Subphenotype <- cls
    k_use <- nrow(centers)
    utils::write.csv(
      data.frame(class = rownames(centers), t1 = centers[, 1], t2 = centers[, 2],
                 stringsAsFactors = FALSE),
      file.path(tab_dir, "Kmeans_fixed_centers_used.csv"), row.names = FALSE
    )
    # 外验仍写占位 elbow 表，标明 fixed_assign
    utils::write.csv(
      data.frame(
        k = k_use, WCSS = NA_real_, chosen_k = k_use,
        auto_elbow = NA_integer_, visual_cap = NA_integer_,
        mode = "fixed_centers_assign",
        centers_csv = as.character(fc_path)[1L]
      ),
      file.path(tab_dir, "Kmeans_elbow_WCSS.csv"), row.names = FALSE
    )
    ctx$data$cleaned <- data
    if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
    ctx$results$kmeans_elbow_bivar <- list(
      k = k_use, elbow = NA_integer_, mode = "fixed_centers_assign",
      centers_csv = as.character(fc_path)[1L],
      nclass = table(cls, useNA = "ifany")
    )
    cli::cli_alert_success(
      "k-means 外验固定中心分配: k={k_use}; nclass={paste(names(table(cls)), as.integer(table(cls)), collapse=', ')}"
    )
    return(ctx)
  }

  el <- ckm_stroke_kmeans_elbow(
    mat, k_max = as.integer(bl$k_max %||% 10L),
    seed = as.integer(bl$seed %||% 2026L),
    nstart = as.integer(bl$nstart %||% 25L)
  )
  # 选 k：force_k 优先；否则肘部自动；若肘点 > elbow_visual_cap 则目视取 cap（对齐原文 Fig2A）
  k_auto <- as.integer(el$elbow_k %||% 4L)
  if (!is.null(bl$force_k) && is.finite(as.numeric(bl$force_k)[1L])) {
    k_use <- as.integer(bl$force_k)[1L]
  } else {
    k_use <- k_auto
    cap <- bl$elbow_visual_cap
    if (!is.null(cap) && is.finite(as.numeric(cap)[1L]) && k_use > as.integer(cap)[1L]) {
      cli::cli_alert_info(
        "肘点自动 k={k_auto} > visual_cap={as.integer(cap)[1L]} → 目视取 k={as.integer(cap)[1L]}（对齐原文）"
      )
      k_use <- as.integer(cap)[1L]
    }
  }

  fit <- ckm_stroke_kmeans_fit(mat, k = k_use, seed = bl$seed %||% 2026L, nstart = bl$nstart %||% 25L)
  cls <- ckm_stroke_anchor_classes(fit$cluster, data$eGDR_t1, data$eGDR_t2)
  data$eGDR_Class <- cls
  data$Subphenotype <- cls

  # 发现队列：落盘语义类中心，供外验固定分配
  if (!is.null(fit$centers)) {
    cen_sem <- ckm_stroke_centers_by_semantic(fit$centers, fit$cluster, cls)
    utils::write.csv(
      data.frame(
        class = rownames(cen_sem),
        t1 = cen_sem[, 1], t2 = cen_sem[, 2],
        stringsAsFactors = FALSE
      ),
      file.path(tab_dir, "Kmeans_semantic_centers.csv"), row.names = FALSE
    )
  }

  # Elbow 图
  pdf(file.path(out_dir, "Figure 2A. Elbow method WCSS.pdf"), width = 5, height = 4)
  plot(seq_along(el$wcss), el$wcss, type = "b", xlab = "k", ylab = "WCSS",
       main = sprintf("Elbow (chosen=%s, auto=%s)", k_use, el$elbow_k))
  abline(v = k_use, lty = 2, col = "red")
  dev.off()

  utils::write.csv(
    data.frame(
      k = seq_along(el$wcss), WCSS = el$wcss,
      chosen_k = k_use, auto_elbow = el$elbow_k,
      visual_cap = as.integer(bl$elbow_visual_cap %||% NA_integer_)[1L]
    ),
    file.path(tab_dir, "Kmeans_elbow_WCSS.csv"), row.names = FALSE
  )

  ctx$data$cleaned <- data
  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
  ctx$results$kmeans_elbow_bivar <- list(
    k = k_use, elbow = el$elbow_k,
    visual_cap = bl$elbow_visual_cap %||% NULL,
    nclass = table(cls, useNA = "ifany")
  )
  cli::cli_alert_success("k-means 完成: k={k_use} (auto_elbow={el$elbow_k})")
  ctx
}

register_block("kmeans_elbow_bivar", block_kmeans_elbow_bivar, "二维kmeans+elbow+Class锚定")
