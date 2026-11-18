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

  n_q <- ckm_stroke_resolve_n_quantile(bl, idx)
  tert_col <- if (ckm_stroke_is_full_depth(idx, bl) && "eGDR_tertile" %in% names(data)) {
    # 若 config 分位数与已有列档数不一致，按当前 n_q 重切
    n_have <- nlevels(factor(data$eGDR_tertile))
    if (is.finite(n_q) && n_have != n_q && "cum_eGDR" %in% names(data)) {
      data$eGDR_tertile <- ckm_stroke_cut_quantile(as.numeric(data$cum_eGDR), n = n_q)
      if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data else ctx$data$cleaned <- data
    }
    "eGDR_tertile"
  } else if (idx %in% names(data)) {
    data[[paste0(idx, "_tertile")]] <- ckm_stroke_cut_quantile(as.numeric(data[[idx]]), n = n_q)
    ctx$data$cleaned <- data
    if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
    paste0(idx, "_tertile")
  } else NULL

  if (!is.null(tert_col) && tert_col %in% names(data)) {
    d <- data
    .tlv <- levels(factor(d[[tert_col]]))
    if (!length(.tlv)) .tlv <- sort(unique(as.character(stats::na.omit(d[[tert_col]]))))
    d[[tert_col]] <- stats::relevel(factor(d[[tert_col]], levels = .tlv), ref = .tlv[[1L]])
    for (mn in model_names) {
      rr <- ckm_stroke_fit_or_row(d, tert_col, outcome, models[[mn]])
      if (!is.null(rr)) {
        rr$block <- if (identical(as.integer(n_q), 3L)) "Tertile" else "Quantile"
        rr$model <- mn
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

  # 收口闸门：Model1 暴露仍不显著 → failed（级联应已在 model1_scheme_cascade 尝试）
  require_sig <- isTRUE(bl$success_require_exposure_sig %||% TRUE) &&
    isTRUE(bl$exposure_sig_crude_model1 %||% TRUE)
  if (require_sig && nrow(tab)) {
    sg <- ckm_stroke_model1_sig_from_bundle_tab(
      tab,
      alpha = bl$exposure_sig_alpha %||% 0.05,
      require_continuous = isTRUE(bl$exposure_sig_require_continuous %||% TRUE)
    )
    ctx$results$logistic_model1_exposure_sig <- sg
    if (!isTRUE(sg$ok)) {
      stop(
        sprintf(
          "MODEL1_EXPOSURE_NS: index=%s continuous Model1 non-significant in logistic bundle (contP=%s, minP=%s, alpha=%s).",
          idx,
          format(sg$cont_p %||% NA_real_, digits = 4),
          format(sg$min_p, digits = 4),
          sg$alpha
        ),
        call. = FALSE
      )
    }
  }
  ctx
}

register_block("logistic_cum_index_bundle", block_logistic_cum_index_bundle, "Class/连续/三分位 logistic 捆表")
