###############################################################################
#  mi_rubin_pool.R — 多重插补 Rubin 合并（全项目复用）
#
#  原则：
#    - 操作流水线（trim / 特征选择 / 轨迹）仍可用 complete_action 单套数据框
#    - 推断性回归（Cox / Fine-Gray / GLM）在 m>1 且有 mice mids 时按 Rubin 合并
#    - 默认：config$imputation$rubin_pool = TRUE（m>1 时生效）；可显式 FALSE 关闭
#
#  主要 API：
#    mi_rubin_enabled(ctx)
#    mi_complete_aligned(ctx, data_template, k, keep_vars)
#    mi_rubin_pool_estimates(fit_list)   # fit_list: list of list(coef=, var=)
#    mi_rubin_hr_table(pooled, ...)     # 写成 HR / CI / p 表
###############################################################################

mi_rubin_enabled <- function(ctx) {
  if (is.null(ctx)) return(FALSE)
  imp <- ctx$config$imputation %||% list()
  mm <- ctx$results$mice_model
  if (is.null(mm) || !inherits(mm, "mids")) return(FALSE)
  m <- as.integer(mm$m %||% imp$m %||% 1L)[1L]
  if (!is.finite(m) || m <= 1L) return(FALSE)
  flag <- imp$rubin_pool
  if (is.null(flag)) return(TRUE) # 默认开启
  isTRUE(flag)
}

#' 取第 k 套完整插补，按分析队列 ID 对齐；keep_vars 列强制用模板值（暴露/结局/时间）
mi_complete_aligned <- function(ctx, data_template, k, keep_vars = character(0)) {
  mm <- ctx$results$mice_model
  if (is.null(mm) || !inherits(mm, "mids")) return(NULL)
  k <- as.integer(k)[1L]
  if (!is.finite(k) || k < 1L || k > as.integer(mm$m %||% 0L)) return(NULL)
  if (!requireNamespace("mice", quietly = TRUE)) return(NULL)

  dk <- tryCatch(mice::complete(mm, action = k), error = function(e) NULL)
  if (!is.data.frame(dk) || !nrow(dk)) return(NULL)

  id_col <- as.character((ctx$config$data %||% list())$id_column %||% "ID")[1L]
  # 优先用插补时锁定的行序 ID（不受 trim 缩小 data_before_mi 影响）
  row_ids <- as.character(ctx$results$mice_row_ids %||% character(0))
  if (length(row_ids) == nrow(dk)) {
    dk[[id_col]] <- row_ids
  } else if (!id_col %in% names(dk)) {
    pre <- ctx$results$data_before_mi
    if (is.data.frame(pre) && id_col %in% names(pre) && nrow(pre) == nrow(dk)) {
      dk[[id_col]] <- as.character(pre[[id_col]])
    } else if (is.data.frame(mm$data) && id_col %in% names(mm$data) && nrow(mm$data) == nrow(dk)) {
      dk[[id_col]] <- as.character(mm$data[[id_col]])
    }
  }
  if (!id_col %in% names(data_template) || !id_col %in% names(dk)) return(NULL)

  ids <- as.character(data_template[[id_col]])
  idx <- match(ids, as.character(dk[[id_col]]))
  ok <- !is.na(idx)
  if (!any(ok)) return(NULL)
  out <- dk[idx[ok], , drop = FALSE]
  tpl <- data_template[ok, , drop = FALSE]

  keep_vars <- unique(c(as.character(keep_vars %||% character(0)), id_col))
  for (v in keep_vars) {
    if (v %in% names(tpl)) out[[v]] <- tpl[[v]]
  }
  # 模板有、插补集没有的分析列（四分位/轨迹等）一并带回
  extra <- setdiff(names(tpl), names(out))
  for (v in extra) out[[v]] <- tpl[[v]]
  rownames(out) <- NULL
  out
}

#' Rubin 合并一组同模型拟合：每个元素 list(coef=named numeric, var=matrix)
mi_rubin_pool_estimates <- function(fit_list) {
  fit_list <- Filter(function(f) {
    is.list(f) && !is.null(f$coef) && length(f$coef) &&
      !is.null(f$var) && is.matrix(f$var)
  }, fit_list)
  m <- length(fit_list)
  if (m < 1L) return(NULL)

  # 统一系数名与 var 行列名
  fit_list <- lapply(fit_list, function(f) {
    cf <- f$coef
    nm <- names(cf)
    if (is.null(nm) || !any(nzchar(nm))) {
      nm <- paste0("b", seq_along(cf))
      names(cf) <- nm
    }
    v <- as.matrix(f$var)
    if (is.null(colnames(v)) || is.null(rownames(v))) {
      if (nrow(v) == length(nm) && ncol(v) == length(nm)) {
        dimnames(v) <- list(nm, nm)
      }
    }
    list(coef = cf, var = v)
  })

  if (m == 1L) {
    coef <- fit_list[[1L]]$coef
    se <- sqrt(diag(as.matrix(fit_list[[1L]]$var)))
    names(se) <- names(coef)
    return(list(coef = coef, se = se, m = 1L, within = se^2, between = se * 0, total = se^2))
  }

  term_sets <- lapply(fit_list, function(f) intersect(names(f$coef), colnames(f$var)))
  terms <- Reduce(intersect, term_sets)
  if (!length(terms)) return(NULL)

  Q <- do.call(rbind, lapply(fit_list, function(f) as.numeric(f$coef[terms])))
  colnames(Q) <- terms
  U <- lapply(fit_list, function(f) {
    v <- as.matrix(f$var)[terms, terms, drop = FALSE]
    diag(v)
  })
  U_mat <- do.call(rbind, U)
  colnames(U_mat) <- terms

  q_bar <- colMeans(Q)
  u_bar <- colMeans(U_mat)
  b <- apply(Q, 2L, stats::var)
  t_var <- u_bar + (1 + 1 / m) * b
  se <- sqrt(pmax(t_var, 0))
  names(q_bar) <- names(se) <- terms
  list(
    coef = q_bar,
    se = se,
    m = m,
    within = u_bar,
    between = b,
    total = t_var
  )
}

#' 将 pooled coef/se 写成 HR 表行
mi_rubin_hr_table <- function(pooled, method, model_id, model_label, horizon) {
  if (is.null(pooled) || !length(pooled$coef)) return(NULL)
  coef <- pooled$coef
  se <- pooled$se
  z <- coef / se
  data.frame(
    method = method,
    model_id = as.integer(model_id),
    model = model_label,
    horizon = as.integer(horizon),
    horizon_label = paste0(horizon, "-day"),
    term = names(coef),
    HR = round(exp(coef), 3),
    HR_low = round(exp(coef - 1.96 * se), 3),
    HR_high = round(exp(coef + 1.96 * se), 3),
    p = signif(2 * stats::pnorm(-abs(z)), 3),
    mi_m = as.integer(pooled$m %||% NA_integer_),
    mi_pool = "rubin",
    stringsAsFactors = FALSE
  )
}
