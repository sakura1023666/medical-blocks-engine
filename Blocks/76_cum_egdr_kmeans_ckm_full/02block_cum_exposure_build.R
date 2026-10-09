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
  t1_col <- paste0(idx, "_t1")
  t2_col <- paste0(idx, "_t2")
  cum_col <- paste0("cum_", idx)

  # 多指标：把当前 index 的两波/累积列别名到 eGDR_*，复用下游 Blocks
  if (all(c(t1_col, t2_col) %in% names(data))) {
    data$eGDR_t1 <- as.numeric(data[[t1_col]])
    data$eGDR_t2 <- as.numeric(data[[t2_col]])
    if (cum_col %in% names(data)) {
      data$cum_eGDR <- as.numeric(data[[cum_col]])
    } else {
      data$cum_eGDR <- (data$eGDR_t1 + data$eGDR_t2) / 2 * mult
      data[[cum_col]] <- data$cum_eGDR
    }
  } else if (identical(toupper(idx), "EGDR")) {
    data <- ckm_stroke_recompute_egdr(data, bl)
  } else {
    stop("cum_exposure_build: 缺少 ", t1_col, "/", t2_col, call. = FALSE)
  }

  # 分析队列：两波完整 +（若有）结局非缺失
  outcome <- ctx$config$data$outcome_column %||% "Osteoporosis"
  ok <- is.finite(data$eGDR_t1) & is.finite(data$eGDR_t2)
  if (outcome %in% names(data)) ok <- ok & !is.na(data[[outcome]])
  data <- data[ok, , drop = FALSE]

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
