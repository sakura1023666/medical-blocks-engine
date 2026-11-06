###############################################################################
# competing_trajectory_cluster — trim 后用保留样本拟合 LMM BLUP + mclust
###############################################################################

competing_filter_long_to_analysis_ids <- function(long, analysis_data, id_col) {
  if (!is.data.frame(long) || !is.data.frame(analysis_data)) {
    stop("轨迹长表和分析数据必须为 data.frame", call. = FALSE)
  }
  if (!id_col %in% names(long) || !id_col %in% names(analysis_data)) {
    stop("轨迹数据缺少 ID 列: ", id_col, call. = FALSE)
  }
  ids <- unique(as.character(analysis_data[[id_col]]))
  long[as.character(long[[id_col]]) %in% ids, , drop = FALSE]
}

block_competing_trajectory_cluster <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  index_var <- as.character(bl$index_var %||% bl$tyg_var %||% "TyG")[1L]
  id_col <- ctx$config$data$id_column %||% "ID"
  data <- ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
  long_info <- ctx$results$competing_index_long %||% NULL
  if (is.null(data) || !is.data.frame(data)) {
    stop("competing_trajectory_cluster: trim 后分析数据不存在", call. = FALSE)
  }
  if (!index_var %in% names(data)) {
    stop("competing_trajectory_cluster: 分析数据缺少指标 ", index_var, call. = FALSE)
  }
  if (is.null(long_info) || !is.data.frame(long_info$long)) {
    stop("competing_trajectory_cluster: 缺少 competing_index_long", call. = FALSE)
  }

  long <- competing_filter_long_to_analysis_ids(long_info$long, data, id_col)
  long[[id_col]] <- as.character(long[[id_col]])
  long <- long[is.finite(suppressWarnings(as.numeric(long$value))), , drop = FALSE]
  ctx$results$competing_index_long$long <- long

  by_id <- split(long, long[[id_col]])
  slope <- vapply(by_id, function(d) {
    ok <- is.finite(d$day) & is.finite(d$value)
    if (sum(ok) < 2L) return(NA_real_)
    unname(stats::coef(stats::lm(value ~ day, data = d[ok, , drop = FALSE]))[2L])
  }, numeric(1))
  ids <- names(slope)
  baseline <- suppressWarnings(as.numeric(data[[index_var]][match(ids, as.character(data[[id_col]]))]))
  ok_slope <- is.finite(slope) & is.finite(baseline)
  if (sum(ok_slope) < 40L) {
    stop(
      "TRAJECTORY_CLUSTER_FAIL: 指标 ", index_var,
      " trim 后可用于轨迹分类的样本量 ", sum(ok_slope), " < 40，记为失败。",
      call. = FALSE
    )
  }

  blups <- data.frame(
    id = ids[ok_slope],
    intercept = baseline[ok_slope],
    slope = slope[ok_slope],
    stringsAsFactors = FALSE
  )
  traj_info <- list(
    method = "slope_blup",
    optimal_K = NA_integer_,
    labels = character(0),
    n_post_trim = nrow(data)
  )

  if (requireNamespace("lme4", quietly = TRUE) && nrow(long) > 50L) {
    long2 <- long
    names(long2)[names(long2) == id_col] <- "ID"
    names(long2)[names(long2) == "value"] <- "y"
    fit_lmm <- tryCatch(
      lme4::lmer(y ~ day + (1 + day | ID), data = long2),
      error = function(e) tryCatch(
        lme4::lmer(y ~ day + (1 | ID), data = long2),
        error = function(e2) NULL
      )
    )
    if (!is.null(fit_lmm)) {
      re <- tryCatch(as.data.frame(lme4::ranef(fit_lmm)$ID), error = function(e) NULL)
      if (!is.null(re) && nrow(re)) {
        re$ID <- rownames(re)
        blups <- data.frame(
          id = as.character(re$ID),
          intercept = if ("(Intercept)" %in% names(re)) re[["(Intercept)"]] else re[[1L]],
          slope = if ("day" %in% names(re)) re[["day"]] else 0,
          stringsAsFactors = FALSE
        )
        traj_info$method <- "lmm_blup"
      }
    }
  }

  X <- scale(cbind(blups$intercept, blups$slope))
  X[!is.finite(X)] <- 0
  min_prop <- as.numeric(bl$trajectory_min_class_prop %||% 0.05)[1L]
  allow_fb <- isTRUE(bl$trajectory_allow_tercile_fallback %||% FALSE)
  assigned <- NULL
  opt_k <- NA_integer_
  fail_reason <- NULL

  if (!requireNamespace("mclust", quietly = TRUE)) {
    fail_reason <- "未安装 mclust"
  } else if (nrow(X) < 40L) {
    fail_reason <- paste0("聚类样本量 ", nrow(X), " < 40")
  } else {
    suppressPackageStartupMessages(library(mclust))
    best_mc <- NULL
    best_bic <- -Inf
    fail_details <- character(0)
    for (g in 2:4) {
      mcg <- tryCatch(mclust::Mclust(X, G = g, verbose = FALSE), error = function(e) NULL)
      if (is.null(mcg) || is.null(mcg$classification)) {
        fail_details <- c(fail_details, sprintf("K=%d:未收敛", g))
        next
      }
      props <- as.numeric(prop.table(table(mcg$classification)))
      if (any(props < min_prop)) {
        fail_details <- c(fail_details, sprintf("K=%d:min_prop=%.3f", g, min(props)))
        next
      }
      bic_g <- suppressWarnings(as.numeric(mcg$bic)[1L])
      if (!is.finite(bic_g)) bic_g <- -Inf
      if (bic_g > best_bic) {
        best_bic <- bic_g
        best_mc <- mcg
      }
    }
    if (is.null(best_mc)) {
      fail_reason <- paste0(
        "G=2:4 无满足最小类占比≥", min_prop, " 的模型 (",
        paste(fail_details, collapse = "; "), ")"
      )
    } else {
      assigned <- as.integer(best_mc$classification)
      opt_k <- as.integer(best_mc$G)[1L]
    }
  }

  if (is.null(assigned) && allow_fb) {
    st <- stats::quantile(blups$slope, probs = c(1 / 3, 2 / 3), na.rm = TRUE, type = 7)
    if (length(unique(st)) >= 2L) {
      assigned <- as.integer(cut(
        blups$slope, breaks = c(-Inf, st[1L], st[2L], Inf), labels = FALSE
      ))
      opt_k <- 3L
      traj_info$method <- paste0(traj_info$method, "+tercile_fallback")
      fail_reason <- NULL
    }
  }
  if (is.null(assigned)) {
    stop(
      "TRAJECTORY_CLUSTER_FAIL: 指标 ", index_var, " — ",
      fail_reason %||% "自动分类失败", "；按配置不回退三分位，记为失败。",
      call. = FALSE
    )
  }

  mean_slope <- tapply(blups$slope, assigned, mean, na.rm = TRUE)
  ord <- order(mean_slope)
  label_map <- setNames(paste0("T", seq_along(ord)), names(mean_slope)[ord])
  labels <- unname(label_map[as.character(assigned)])
  if (length(ord) == 3L) {
    alias <- c(T1 = "Decreasing", T2 = "Stable", T3 = "Increasing")
    labels <- unname(alias[labels])
  }
  traj_col <- paste0(index_var, "_trajectory")
  traj_df <- data.frame(id_tmp = blups$id, trajectory = labels, stringsAsFactors = FALSE)
  names(traj_df) <- c(id_col, traj_col)

  for (slot in c("cleaned", "imputed", "raw")) {
    d <- ctx$data[[slot]]
    if (is.null(d) || !is.data.frame(d) || !id_col %in% names(d)) next
    d[[id_col]] <- as.character(d[[id_col]])
    d[[traj_col]] <- NULL
    ctx$data[[slot]] <- merge(d, traj_df, by = id_col, all.x = TRUE, sort = FALSE)
  }

  traj_info$optimal_K <- as.integer(opt_k)
  traj_info$labels <- sort(unique(labels[!is.na(labels)]))
  ctx$results$competing_trajectory_class <- traj_info
  ctx$results$competing_index_exposure$n_trajectory_ok <- sum(!is.na(labels))
  ctx$results$competing_index_exposure$trajectory <- traj_info
  cli::cli_alert_success(
    "trim 后轨迹分类完成: method={traj_info$method}, optimal_K={traj_info$optimal_K}, n={length(labels)}"
  )
  ctx
}

register_block(
  "competing_trajectory_cluster",
  block_competing_trajectory_cluster,
  "Post-trim LMM BLUP and mclust trajectory classification"
)
