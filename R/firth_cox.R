###############################################################################
#  firth_cox.R — Firth 罚似然 Cox（准完全分离 / 0 事件段可估 HR）
#
#  背景（SOSM 2026-09 审稿）：分段 Cox 某段内对照类 0 事件 → 标准 coxph 给出
#  1e9 级 HR 或 NE。logistf 对单协变量 Cox 数值失败（chol 非正定），故引擎内置
#  一维 Firth 罚似然：penalized partial loglik = l_Efron(b) + 0.5*log I(b)，
#  CI 用 profile penalized likelihood（LR 法），P 用 penalized LR test。
#
#  入口：
#    firth_cox1d(time, event, x)                 单协变量（0/1）
#    firth_cox_piecewise(t, e, class, ref)       多类：每类 vs ref 两两一维
#  依赖：仅 stats/utils/survival（不依赖 logistf）。
#
#  调用方：Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R
#    （NE 行自动回退 Firth，输出 "HR (lo, hi)‡" + 脚注 ‡）。
###############################################################################

# Efron 偏似然（单协变量 x，时间 t，事件 e）
.firth_efron_ll <- function(beta, t, e, x) {
  ord <- order(t)
  t <- t[ord]; e <- e[ord]; x <- x[ord]
  eta <- exp(beta * x)
  ev_t <- unique(t[e == 1])
  ll <- 0
  for (tk in ev_t) {
    D_idx <- which(t == tk & e == 1)
    R_idx <- which(t >= tk)
    d <- length(D_idx)
    if (!d || !length(R_idx)) next
    S_R <- sum(eta[R_idx]); S_D <- sum(eta[D_idx])
    ll <- ll + sum(beta * x[D_idx])
    if (d == 1L) {
      ll <- ll - log(S_R)
    } else {
      for (l in seq_len(d) - 1L) {
        v <- S_R - (l / d) * S_D
        if (v <= 0) return(-Inf)
        ll <- ll - log(v)
      }
    }
  }
  ll
}

# 数值二阶导 → Fisher 信息 I(b) = -l''(b)
.firth_info <- function(beta, t, e, x, h = 1e-4) {
  lp <- .firth_efron_ll(beta + h, t, e, x)
  l0 <- .firth_efron_ll(beta, t, e, x)
  lm <- .firth_efron_ll(beta - h, t, e, x)
  if (!all(is.finite(c(lp, l0, lm)))) return(NA_real_)
  -(lp - 2 * l0 + lm) / h^2
}

.firth_penll <- function(beta, t, e, x) {
  I <- .firth_info(beta, t, e, x)
  if (!is.finite(I) || I <= 0) return(-Inf)
  v <- .firth_efron_ll(beta, t, e, x)
  if (!is.finite(v)) return(-Inf)
  v + 0.5 * log(I)
}

#' 一维 Firth 罚似然 Cox
#' @return list(beta,HR,lo,hi,p,converged)；失败 converged=FALSE
firth_cox1d <- function(time, event, x) {
  keep <- is.finite(time) & !is.na(event) & !is.na(x) & time > 0
  t <- time[keep]; e <- as.integer(event[keep]); x <- as.numeric(x[keep])
  if (length(unique(x)) < 2L || sum(e == 1) == 0L) {
    return(list(converged = FALSE))
  }
  r <- tryCatch(
    stats::optimize(function(b) -.firth_penll(b, t, e, x), interval = c(-15, 15)),
    error = function(err) NULL
  )
  if (is.null(r) || !is.finite(r$minimum)) return(list(converged = FALSE))
  bhat <- r$minimum
  pen_max <- .firth_penll(bhat, t, e, x)
  if (!is.finite(pen_max)) return(list(converged = FALSE))
  target <- pen_max - stats::qchisq(0.975, 1) / 2
  f <- function(b) .firth_penll(b, t, e, x) - target
  # profile CI：向两侧搜索符号变化
  hi_root <- tryCatch({
    b <- bhat
    while (f(b) > 0 && b < 40) b <- b + 0.05
    if (f(b) > 0) NA_real_ else stats::uniroot(f, c(bhat, b), tol = 1e-6)$root
  }, error = function(err) NA_real_)
  lo_root <- tryCatch({
    b <- bhat
    while (f(b) > 0 && b > -40) b <- b - 0.05
    if (f(b) > 0) NA_real_ else stats::uniroot(f, c(b, bhat), tol = 1e-6)$root
  }, error = function(err) NA_real_)
  lr <- 2 * (pen_max - .firth_penll(0, t, e, x))
  p <- if (is.finite(lr) && lr > 0) stats::pchisq(lr, df = 1, lower.tail = FALSE) else 1
  list(
    beta = bhat, HR = exp(bhat),
    lo = if (is.finite(lo_root)) exp(lo_root) else NA_real_,
    hi = if (is.finite(hi_root)) exp(hi_root) else NA_real_,
    p = p, converged = TRUE
  )
}

#' 多类分段 Firth：每个非参照类 vs 参照类两两一维拟合
#' @param t,e 时间/事件向量；class 因子或整数；ref 参照类水平
#' @return data.frame(class,HR,lo,hi,p,method)；失败行 method="fail"
firth_cox_piecewise <- function(t, e, class, ref) {
  cl <- as.character(class)
  lv <- unique(cl)
  if (!ref %in% lv) ref <- lv[which.max(table(cl[cl %in% lv]))]
  out <- lapply(setdiff(lv, ref), function(k) {
    sel <- cl %in% c(k, ref)
    x <- as.integer(cl[sel] == k)
    r <- tryCatch(firth_cox1d(t[sel], e[sel], x), error = function(err) list(converged = FALSE))
    if (!isTRUE(r$converged)) {
      return(data.frame(class = k, HR = NA_real_, lo = NA_real_, hi = NA_real_,
                        p = NA_real_, method = "fail", stringsAsFactors = FALSE))
    }
    data.frame(class = k, HR = r$HR, lo = r$lo, hi = r$hi, p = r$p,
               method = "firth", stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}
