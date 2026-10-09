###############################################################################
# logistic_cum_index_bundle — Table2 工作底稿: Class + continuous + tertile × Model1–3
# 发表版式 Variable/Total/Events/Model1–3 由 ckm_stroke_build_table2_assoc()
# （R/cum_egdr_kmeans_pub.R）在 rebuild_publication.R 中写出。
###############################################################################

block_logistic_cum_index_bundle <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Stroke"
  if (is.null(data) || !outcome %in% names(data)) stop("logistic bundle: 无数据/结局", call. = FALSE)
  # 与 uv_vif 解析一致：把 Hypertension_w4 等别名落到 Hypertension，再写回 ctx
  data <- ckm_stroke_harmonize_columns(data)
  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data else ctx$data$cleaned <- data

  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  # covariate_mode=fixed：文献固定名单；uv_vif：单因素显著→VIF→M2人口学/M3+其他
  models <- ckm_stroke_model_sets(bl, data, index_name = idx, outcome = outcome)
  ctx$results$ckm_model_sets <- models
  if (!is.null(models$uv_vif$uv_table)) {
    utils::write.csv(
      models$uv_vif$uv_table,
      file.path(tab_dir, "Covariate_UV_VIF_selection.csv"),
      row.names = FALSE
    )
  }
  cli::cli_alert_info(
    "Table2 covariates [{bl$covariate_mode %||% 'fixed'}]: M2={paste(models$Model2, collapse='+')}; M3={paste(models$Model3, collapse='+')}"
  )
  rows <- list()
  model_names <- c("Model1", "Model2", "Model3")

  if (ckm_stroke_is_full_depth(idx, bl) && "eGDR_Class" %in% names(data)) {
    d <- data
    d$eGDR_Class <- stats::relevel(factor(d$eGDR_Class), ref = bl$class_ref %||% "Persistent_low")
    for (mn in model_names) {
      rr <- ckm_stroke_fit_or_row(d, "eGDR_Class", outcome, models[[mn]])
      if (!is.null(rr)) {
        rr$block <- "Class"; rr$model <- mn
        rows[[length(rows) + 1L]] <- rr
      }
    }
  }

  cont_col <- if (ckm_stroke_is_full_depth(idx, bl) && "cum_eGDR" %in% names(data)) "cum_eGDR" else idx
  if (cont_col %in% names(data)) {
    for (mn in model_names) {
      rr <- ckm_stroke_fit_or_row(data, cont_col, outcome, models[[mn]])
      if (!is.null(rr)) {
        rr$block <- "Continuous"; rr$model <- mn
        rows[[length(rows) + 1L]] <- rr
      }
    }
  }
  # 每 1 SD（跨队列可比）
  if (ckm_stroke_is_full_depth(idx, bl) && "cum_eGDR_perSD" %in% names(data)) {
    for (mn in model_names) {
      rr <- ckm_stroke_fit_or_row(data, "cum_eGDR_perSD", outcome, models[[mn]])
      if (!is.null(rr)) {
        rr$block <- "Continuous_perSD"; rr$model <- mn
        rows[[length(rows) + 1L]] <- rr
      }
    }
  }

  tert_col <- if (ckm_stroke_is_full_depth(idx, bl) && "eGDR_tertile" %in% names(data)) {
    "eGDR_tertile"
  } else if (idx %in% names(data)) {
    x <- as.numeric(data[[idx]])
    qs <- stats::quantile(x, c(1/3, 2/3), na.rm = TRUE, names = FALSE)
    data[[paste0(idx, "_tertile")]] <- cut(x, c(-Inf, qs[1], qs[2], Inf),
                                           labels = c("T1", "T2", "T3"), include.lowest = TRUE)
    ctx$data$cleaned <- data
    if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
    paste0(idx, "_tertile")
  } else NULL

  if (!is.null(tert_col) && tert_col %in% names(data)) {
    d <- data
    d[[tert_col]] <- stats::relevel(factor(d[[tert_col]]), ref = "T1")
    for (mn in model_names) {
      rr <- ckm_stroke_fit_or_row(d, tert_col, outcome, models[[mn]])
      if (!is.null(rr)) {
        rr$block <- "Tertile"; rr$model <- mn
        rows[[length(rows) + 1L]] <- rr
      }
    }
  }

  if (!length(rows)) {
    tab <- data.frame()
  } else {
    tab <- do.call(rbind, rows)
    rownames(tab) <- NULL
  }
  utils::write.csv(tab, file.path(tab_dir, "Table 2. Logistic Class Continuous Tertile.csv"), row.names = FALSE)
  ctx$results$logistic_cum_index_bundle <- tab
  cli::cli_alert_success("Table 2 bundle: {nrow(tab)} 行")
  ctx
}

register_block("logistic_cum_index_bundle", block_logistic_cum_index_bundle, "Class/连续/三分位 logistic 捆表")
