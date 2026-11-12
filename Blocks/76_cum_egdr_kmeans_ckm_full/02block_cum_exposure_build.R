###############################################################################
# cum_exposure_build — 当前指标累积暴露（eGDR 全深度；其它指标跳过）
###############################################################################

block_cum_exposure_build <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% ctx$config$logistic$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("cum_exposure_build: 无数据", call. = FALSE)

  if (!ckm_stroke_is_full_depth(idx, bl)) {
    cli::cli_alert_info("cum_exposure_build: {idx} 非全深度，跳过两波累积")
    ctx$results$cum_exposure_build <- list(index = idx, skipped = TRUE)
    return(ctx)
  }

  mult <- as.numeric(bl$cum_multiplier %||% 3)
  n_waves <- as.integer(bl$n_exposure_waves %||% 2L)[1L]
  if (!is.finite(n_waves) || n_waves < 2L) n_waves <- 2L
  t_cols <- paste0(idx, "_t", seq_len(n_waves))
  cum_col <- paste0("cum_", idx)

  # 多指标：把当前 index 的多波/累积列别名到 eGDR_*，复用下游 Blocks
  # 默认 n_exposure_waves=2（两波文献套路）；探索可设 3/4…
  if (all(t_cols %in% names(data))) {
    for (i in seq_len(n_waves)) {
      data[[paste0("eGDR_t", i)]] <- as.numeric(data[[t_cols[i]]])
    }
    # 下游仍大量读 eGDR_t1/t2：末波别名到 t2（保留真 t2 当 n>2 时另存 eGDR_t2 原值）
    if (n_waves == 2L) {
      data$eGDR_t1 <- as.numeric(data[[t_cols[1]]])
      data$eGDR_t2 <- as.numeric(data[[t_cols[2]]])
    }
    if (cum_col %in% names(data)) {
      data$cum_eGDR <- as.numeric(data[[cum_col]])
    } else {
      mat <- as.matrix(data[, paste0("eGDR_t", seq_len(n_waves)), drop = FALSE])
      data$cum_eGDR <- rowMeans(mat, na.rm = FALSE) * mult
      data[[cum_col]] <- data$cum_eGDR
    }
  } else if (all(c(paste0(idx, "_t1"), paste0(idx, "_t2")) %in% names(data))) {
    # 回退两波
    n_waves <- 2L
    data$eGDR_t1 <- as.numeric(data[[paste0(idx, "_t1")]])
    data$eGDR_t2 <- as.numeric(data[[paste0(idx, "_t2")]])
    if (cum_col %in% names(data)) {
      data$cum_eGDR <- as.numeric(data[[cum_col]])
    } else {
      data$cum_eGDR <- (data$eGDR_t1 + data$eGDR_t2) / 2 * mult
      data[[cum_col]] <- data$cum_eGDR
    }
  } else if (identical(toupper(idx), "EGDR")) {
    data <- ckm_stroke_recompute_egdr(data, bl)
    n_waves <- 2L
  } else {
    stop("cum_exposure_build: 缺少 ", paste(t_cols, collapse = "/"), call. = FALSE)
  }

  # 分析队列：各暴露波完整 +（若有）结局非缺失
  outcome <- ctx$config$data$outcome_column %||% "Osteoporosis"
  ok <- Reduce(`&`, lapply(seq_len(n_waves), function(i) {
    is.finite(as.numeric(data[[paste0("eGDR_t", i)]]))
  }))
  if (outcome %in% names(data)) ok <- ok & !is.na(data[[outcome]])
  data <- data[ok, , drop = FALSE]
  ctx$results$cum_exposure_n_waves <- n_waves

  # 指标级事先纳排：按 config$cum_egdr_kmeans$exclude_ids_by_index[[index]] 剔除（写进 Fig1）
  id_col <- ctx$config$data$id_column %||% "ID"
  ex_map <- bl$exclude_ids_by_index %||% list()
  ex_ids <- unique(as.character(ex_map[[idx]] %||% character(0)))
  ex_ids <- ex_ids[nzchar(ex_ids)]
  n_ex_id <- 0L
  if (length(ex_ids) && id_col %in% names(data)) {
    hit <- as.character(data[[id_col]]) %in% ex_ids
    n_ex_id <- sum(hit)
    if (n_ex_id > 0L) {
      data <- data[!hit, , drop = FALSE]
      cli::cli_alert_info(
        "cum_exposure_build: {idx} 纳排剔除 exclude_ids n={n_ex_id} (ids={paste(ex_ids, collapse=',')})"
      )
    }
  }
  ctx$results$cum_exposure_exclude_ids <- list(
    index = idx, ids = ex_ids, n_excluded = as.integer(n_ex_id), n_remain = nrow(data)
  )

  # 主分析暴露列别名 + 每 1 SD
  if ("cum_eGDR" %in% names(data)) {
    data[["eGDR"]] <- data$cum_eGDR
    data[[idx]] <- data$cum_eGDR
    data[["eGDR_baseline"]] <- data$eGDR_t1
    x <- as.numeric(data$cum_eGDR)
    sdx <- stats::sd(x, na.rm = TRUE)
    data$cum_eGDR_perSD <- if (is.finite(sdx) && sdx > 0) x / sdx else x
    data[[paste0(idx, "_perSD")]] <- data$cum_eGDR_perSD
    qs <- stats::quantile(x, probs = c(1 / 3, 2 / 3), na.rm = TRUE, names = FALSE)
    data$eGDR_tertile <- cut(x, breaks = c(-Inf, qs[1], qs[2], Inf),
                             labels = c("T1", "T2", "T3"), include.lowest = TRUE)
  }
  ctx$data$cleaned <- data
  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
  ctx$results$cum_exposure_build <- list(index = idx, skipped = FALSE, n = nrow(data))
  cli::cli_alert_success("累积暴露已构建: {idx} cum×{mult}; n={nrow(data)}")
  ctx
}

register_block("cum_exposure_build", block_cum_exposure_build, "两波累积暴露构建")
