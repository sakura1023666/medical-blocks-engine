###############################################################################
# model1_scheme_cascade — Model1 暴露不显著时换分位/换 k；仍 NS 则 failed
# 铁律：success_require_exposure_sig + exposure_sig_crude_model1
###############################################################################

block_model1_scheme_cascade <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  outcome <- ctx$config$data$outcome_column %||% "Stroke"
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("model1_scheme_cascade: 无数据", call. = FALSE)

  if (!ckm_stroke_is_full_depth(idx, bl)) {
    cli::cli_alert_info("model1_scheme_cascade: {idx} 跳过（非全深度）")
    ctx$results$model1_scheme_cascade <- list(skipped = TRUE)
    return(ctx)
  }

  require_sig <- isTRUE(bl$success_require_exposure_sig %||% TRUE) &&
    isTRUE(bl$exposure_sig_crude_model1 %||% TRUE)
  if (!require_sig && !isTRUE(bl$model1_cascade_enable %||% FALSE)) {
    cli::cli_alert_info("model1_scheme_cascade: 门控关闭，跳过")
    ctx$results$model1_scheme_cascade <- list(skipped = TRUE, gate_off = TRUE)
    return(ctx)
  }

  out_root <- ctx$config$project$output_dir %||% "Output"
  tab_dir <- file.path(out_root, "by_index", idx, "Tables")
  if (!dir.exists(tab_dir)) tab_dir <- file.path(out_root, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  n_waves <- as.integer(bl$n_exposure_waves %||% ctx$results$cum_exposure_n_waves %||% 2L)[1L]
  if (!is.finite(n_waves) || n_waves < 2L) n_waves <- 2L
  t_names <- paste0("eGDR_t", seq_len(n_waves))
  have <- t_names[t_names %in% names(data)]
  if (length(have) < 2L) {
    stop("model1_scheme_cascade: 缺少 eGDR_t* 列", call. = FALSE)
  }
  mat <- do.call(cbind, lapply(have, function(cn) as.numeric(data[[cn]])))

  current_k <- as.integer(ctx$results$kmeans_elbow_bivar$k %||% nlevels(factor(data$eGDR_Class)))[1L]
  current_n_q <- as.integer(
    ctx$results$cum_exposure_n_quantile %||%
      ckm_stroke_resolve_n_quantile(bl, idx)
  )[1L]

  cas <- ckm_stroke_model1_scheme_cascade(
    data = data,
    mat = mat,
    outcome = outcome,
    bl = bl,
    index_name = idx,
    current_k = current_k,
    current_n_q = current_n_q
  )

  if (!is.null(cas$trials) && nrow(cas$trials)) {
    utils::write.csv(
      cas$trials,
      file.path(tab_dir, "Model1_scheme_cascade_trials.csv"),
      row.names = FALSE
    )
  }

  if (isTRUE(cas$ok) && isTRUE(cas$changed)) {
    data <- cas$data
    ctx$data$cleaned <- data
    if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
    ctx$results$cum_exposure_n_quantile <- as.integer(cas$n_quantile)
    # 覆盖 kmeans 结果摘要，供下游 / rebuild 读取
    ctx$results$kmeans_elbow_bivar$k <- as.integer(cas$k)
    ctx$results$kmeans_elbow_bivar$cascade_locked <- TRUE
    ctx$results$kmeans_elbow_bivar$nclass <- table(data$eGDR_Class, useNA = "ifany")
    # 重写 elbow 表 chosen_k（保留原 WCSS 行）
    el_path <- file.path(tab_dir, "Kmeans_elbow_WCSS.csv")
    if (file.exists(el_path)) {
      el <- tryCatch(utils::read.csv(el_path, stringsAsFactors = FALSE), error = function(e) NULL)
      if (!is.null(el) && nrow(el)) {
        el$chosen_k <- as.integer(cas$k)
        el$cascade_locked <- TRUE
        utils::write.csv(el, el_path, row.names = FALSE)
      }
    }
    lock <- data.frame(
      index = idx,
      locked_k = as.integer(cas$k),
      locked_n_quantile = as.integer(cas$n_quantile),
      lock_reason = cas$lock_reason,
      min_p_model1 = cas$screen$min_p,
      alpha = cas$screen$alpha,
      stringsAsFactors = FALSE
    )
    utils::write.csv(lock, file.path(tab_dir, "Model1_scheme_lock.csv"), row.names = FALSE)
    cli::cli_alert_success(
      "Model1 级联锁定: k={cas$k}, n_quantile={cas$n_quantile} (minP={signif(cas$screen$min_p, 3)})"
    )
  } else if (isTRUE(cas$ok)) {
    lock <- data.frame(
      index = idx,
      locked_k = as.integer(cas$k),
      locked_n_quantile = as.integer(cas$n_quantile),
      lock_reason = cas$lock_reason,
      min_p_model1 = cas$screen$min_p,
      alpha = cas$screen$alpha,
      stringsAsFactors = FALSE
    )
    utils::write.csv(lock, file.path(tab_dir, "Model1_scheme_lock.csv"), row.names = FALSE)
    cli::cli_alert_success(
      "Model1 基线已显著: k={cas$k}, n_quantile={cas$n_quantile} (minP={signif(cas$screen$min_p, 3)})"
    )
  }

  ctx$results$model1_scheme_cascade <- list(
    ok = isTRUE(cas$ok),
    changed = isTRUE(cas$changed),
    k = cas$k,
    n_quantile = cas$n_quantile,
    lock_reason = cas$lock_reason,
    min_p = cas$screen$min_p,
    alpha = cas$screen$alpha
  )

  if (!isTRUE(cas$ok) && require_sig) {
    .why <- as.character(cas$lock_reason %||% "")
    if (identical(.why, "continuous_model1_ns")) {
      stop(
        sprintf(
          paste0(
            "MODEL1_EXPOSURE_NS: index=%s continuous Model1 non-significant ",
            "(contP=%s, alpha=%s); k/quantile cascade cannot change continuous OR. Mark as failed."
          ),
          idx,
          format(cas$screen$cont_p %||% cas$screen$min_p, digits = 4),
          cas$screen$alpha
        ),
        call. = FALSE
      )
    }
    stop(
      sprintf(
        paste0(
          "MODEL1_EXPOSURE_NS: index=%s Model1 gate failed after cascade ",
          "(tried k={%s} × n_q={%s}; contP=%s, minP=%s, alpha=%s, reason=%s). Mark as failed."
        ),
        idx,
        paste(unique(cas$trials$k), collapse = ","),
        paste(unique(cas$trials$n_quantile), collapse = ","),
        format(cas$screen$cont_p %||% NA_real_, digits = 4),
        format(cas$screen$min_p, digits = 4),
        cas$screen$alpha,
        .why
      ),
      call. = FALSE
    )
  }

  ctx
}

register_block(
  "model1_scheme_cascade",
  block_model1_scheme_cascade,
  "Model1不显著时换分位/换k，仍NS则failed"
)
