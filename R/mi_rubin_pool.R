###############################################################################
#  mi_rubin_pool.R — 多重插补 Rubin 合并（全项目复用）
#
#  原则（2026-10 铁律）：
#    - 有插补时默认 m=5 + rubin_pool=TRUE
#    - 操作流水线（trim / FS / 轨迹 / 描述表 / KM）仍可用 complete_action 单套
#    - 推断回归（Cox / Fine-Gray / GLM）必须跨 m 套拟合再 Rubin 合并
#    - 禁止 m=5 只取 complete#1 当主推断还写「多重插补」
#
#  主要 API：
#    mi_rubin_normalize_config(config)
#    mi_rubin_enabled(ctx)
#    mi_complete_aligned(ctx, data_template, k, keep_vars)
#    mi_coxph / mi_glm_binomial
#    mi_rubin_pool_estimates / mi_rubin_hr_table
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

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

# ---- 全项目默认：m=5 + Rubin（2026-10 铁律）----

#' 规范化 imputation 配置：有插补时强制 m>=5、rubin_pool=TRUE
mi_rubin_normalize_config <- function(config) {
  if (is.null(config) || !is.list(config)) return(config)
  imp <- config$imputation %||% list()
  meth <- tolower(as.character(imp$method %||% "cart")[1L])
  if (identical(meth, "none") || identical(meth, "skip")) {
    config$imputation <- imp
    return(config)
  }
  m <- as.integer(imp$m %||% 5L)[1L]
  if (!is.finite(m) || m < 5L) {
    cli::cli_alert_warning(
      "imputation$m={m} < 5；全项目铁律改为 m=5（真 MI + Rubin）"
    )
    m <- 5L
  }
  imp$m <- m
  if (is.null(imp$rubin_pool)) imp$rubin_pool <- TRUE
  if (!isTRUE(imp$rubin_pool)) {
    cli::cli_alert_warning(
      "imputation$rubin_pool=FALSE 已覆盖为 TRUE（禁止 m>1 只取 complete#1 当推断）"
    )
    imp$rubin_pool <- TRUE
  }
  if (is.null(imp$complete_action)) imp$complete_action <- 1L
  if (is.null(imp$max_iter) && is.null(imp$maxit)) imp$max_iter <- 5L
  if (is.null(imp$seed)) imp$seed <- 1234L
  config$imputation <- imp
  config
}

#' Rubin 合并后的伪 coxph：供 pub_hr_ci_p / summary / coef / vcov / confint 使用
mi_as_coxph_like <- function(pooled, n = NA_integer_, nevent = NA_integer_) {
  if (is.null(pooled) || !length(pooled$coef)) return(NULL)
  coef <- pooled$coef
  se <- pooled$se
  V <- diag(as.numeric(pooled$total %||% (se^2)), nrow = length(coef))
  dimnames(V) <- list(names(coef), names(coef))
  z <- coef / se
  p <- 2 * stats::pnorm(-abs(z))
  co_mat <- cbind(
    coef = coef,
    `exp(coef)` = exp(coef),
    `se(coef)` = se,
    z = z,
    `Pr(>|z|)` = p
  )
  ci_mat <- cbind(exp(coef - 1.96 * se), exp(coef + 1.96 * se))
  colnames(ci_mat) <- c("2.5 %", "97.5 %")
  rownames(ci_mat) <- names(coef)
  obj <- list(
    coefficients = coef,
    var = V,
    n = n,
    nevent = nevent,
    mi_m = as.integer(pooled$m %||% NA_integer_),
    mi_pool = if (isTRUE(as.integer(pooled$m %||% 1L) > 1L)) "rubin" else "single",
    .coef_mat = co_mat,
    .ci_mat = ci_mat
  )
  class(obj) <- c("mi_pooled_cox", "coxph")
  obj
}

coef.mi_pooled_cox <- function(object, ...) object$coefficients
vcov.mi_pooled_cox <- function(object, ...) object$var
nobs.mi_pooled_cox <- function(object, ...) object$n
confint.mi_pooled_cox <- function(object, parm, level = 0.95, ...) {
  se <- sqrt(diag(as.matrix(object$var)))
  z <- stats::qnorm(1 - (1 - level) / 2)
  cf <- object$coefficients
  out <- cbind(cf - z * se, cf + z * se)
  colnames(out) <- c(paste0((1 - level) / 2 * 100, " %"), paste0((1 - (1 - level) / 2) * 100, " %"))
  rownames(out) <- names(cf)
  if (!missing(parm)) out <- out[parm, , drop = FALSE]
  out
}
summary.mi_pooled_cox <- function(object, ...) {
  list(
    coefficients = object$.coef_mat,
    conf.int = cbind(
      `exp(coef)` = exp(object$coefficients),
      exp(-object$coefficients),
      object$.ci_mat
    ),
    n = object$n,
    nevent = object$nevent
  )
}

#' 跨 m 套拟合 coxph 并 Rubin 合并；未启用时退回单套 coxph
mi_coxph <- function(ctx, formula, data, keep_vars = character(0), ties = "efron") {
  data <- as.data.frame(data)
  if (!isTRUE(mi_rubin_enabled(ctx))) {
    return(survival::coxph(formula, data = data, ties = ties))
  }
  mm <- ctx$results$mice_model
  m <- as.integer(mm$m %||% 1L)[1L]
  keep_vars <- unique(c(
    as.character(keep_vars),
    all.vars(formula),
    as.character((ctx$config$data %||% list())$id_column %||% "ID")
  ))
  fits <- list()
  for (k in seq_len(m)) {
    dk <- mi_complete_aligned(ctx, data, k, keep_vars = keep_vars)
    if (is.null(dk)) next
    fit <- tryCatch(
      survival::coxph(formula, data = dk, ties = ties),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    cf <- stats::coef(fit)
    V <- tryCatch(as.matrix(stats::vcov(fit)), error = function(e) NULL)
    if (is.null(V) || !length(cf)) next
    fits[[length(fits) + 1L]] <- list(coef = cf, var = V)
  }
  pooled <- mi_rubin_pool_estimates(fits)
  if (is.null(pooled)) {
    cli::cli_alert_warning("mi_coxph: Rubin 失败（{length(fits)}/{m}），回退单套 complete")
    return(survival::coxph(formula, data = data, ties = ties))
  }
  mi_as_coxph_like(pooled, n = nrow(data))
}

#' Rubin 合并后的伪 glm（二项）
mi_as_glm_like <- function(pooled, n = NA_integer_) {
  if (is.null(pooled) || !length(pooled$coef)) return(NULL)
  coef <- pooled$coef
  se <- pooled$se
  V <- diag(as.numeric(pooled$total %||% (se^2)), nrow = length(coef))
  dimnames(V) <- list(names(coef), names(coef))
  z <- coef / se
  p <- 2 * stats::pnorm(-abs(z))
  co_mat <- cbind(Estimate = coef, `Std. Error` = se, `z value` = z, `Pr(>|z|)` = p)
  obj <- list(
    coefficients = coef,
    vcov = V,
    n = n,
    mi_m = as.integer(pooled$m %||% NA_integer_),
    mi_pool = if (isTRUE(as.integer(pooled$m %||% 1L) > 1L)) "rubin" else "single",
    family = stats::binomial(),
    .coef_mat = co_mat
  )
  class(obj) <- c("mi_pooled_glm", "glm", "lm")
  obj
}
coef.mi_pooled_glm <- function(object, ...) object$coefficients
vcov.mi_pooled_glm <- function(object, ...) object$vcov
nobs.mi_pooled_glm <- function(object, ...) object$n
summary.mi_pooled_glm <- function(object, ...) {
  list(coefficients = object$.coef_mat)
}
confint.mi_pooled_glm <- function(object, parm, level = 0.95, ...) {
  se <- sqrt(diag(as.matrix(object$vcov)))
  z <- stats::qnorm(1 - (1 - level) / 2)
  cf <- object$coefficients
  out <- cbind(cf - z * se, cf + z * se)
  colnames(out) <- c(paste0((1 - level) / 2 * 100, " %"), paste0((1 - (1 - level) / 2) * 100, " %"))
  rownames(out) <- names(cf)
  if (!missing(parm)) out <- out[parm, , drop = FALSE]
  out
}

#' 跨 m 套拟合二项 glm 并 Rubin 合并
mi_glm_binomial <- function(ctx, formula, data, keep_vars = character(0),
                            fit_fun = NULL) {
  data <- as.data.frame(data)
  if (is.null(fit_fun)) {
    fit_fun <- function(fml, d) stats::glm(fml, data = d, family = stats::binomial)
  }
  if (!isTRUE(mi_rubin_enabled(ctx))) {
    return(fit_fun(formula, data))
  }
  mm <- ctx$results$mice_model
  m <- as.integer(mm$m %||% 1L)[1L]
  keep_vars <- unique(c(
    as.character(keep_vars),
    all.vars(formula),
    as.character((ctx$config$data %||% list())$id_column %||% "ID")
  ))
  fits <- list()
  for (k in seq_len(m)) {
    dk <- mi_complete_aligned(ctx, data, k, keep_vars = keep_vars)
    if (is.null(dk)) next
    fit <- tryCatch(fit_fun(formula, dk), error = function(e) NULL)
    if (is.null(fit) || inherits(fit, "error")) next
    cf <- tryCatch(stats::coef(fit), error = function(e) NULL)
    V <- tryCatch(as.matrix(stats::vcov(fit)), error = function(e) NULL)
    if (is.null(cf) || is.null(V) || !length(cf)) next
    fits[[length(fits) + 1L]] <- list(coef = cf, var = V)
  }
  pooled <- mi_rubin_pool_estimates(fits)
  if (is.null(pooled)) {
    cli::cli_alert_warning("mi_glm_binomial: Rubin 失败（{length(fits)}/{m}），回退单套")
    return(fit_fun(formula, data))
  }
  mi_as_glm_like(pooled, n = nrow(data))
}

mi_methods_footnote_lines <- function(m = 5L, maxit = 5L, seed = 1234L) {
  c(
    sprintf(
      "Multiple imputation by chained equations (m = %d, maxit = %d, seed = %d).",
      as.integer(m), as.integer(maxit), as.integer(seed)
    ),
    "Regression estimates (Cox/logistic) were pooled across imputations using Rubin's rules.",
    "Operational steps (feature selection, KM/RCS plots, descriptive tables) used the first completed dataset."
  )
}

#' 若 ctx 启用 Rubin，把 MI 方法脚注接到发表表脚注末尾（全项目复用）
mi_append_table_footnotes <- function(notes, ctx = NULL) {
  notes <- as.character(notes %||% character(0))
  if (is.null(ctx) || !isTRUE(mi_rubin_enabled(ctx))) return(notes)
  if (!exists("mi_methods_footnote_lines", mode = "function")) return(notes)
  imp <- ctx$config$imputation %||% list()
  mi_lines <- mi_methods_footnote_lines(
    m = as.integer(imp$m %||% ctx$results$mice_model$m %||% 5L)[1L],
    maxit = as.integer(imp$maxit %||% 5L)[1L],
    seed = as.integer(imp$seed %||% 1234L)[1L]
  )
  # 幂等：已含 Rubin 句则不再追加
  if (any(grepl("Rubin's rules", notes, fixed = TRUE))) return(notes)
  c(notes, mi_lines)
}
