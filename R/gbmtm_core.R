###############################################################################
# gbmtm_core.R — Group-Based Multi-Trajectory Modeling (GBMTM) 双指标联合轨迹
#
# 统计内核（Nagin 多轨迹混合模型，EM 全信息；局部独立，支持任意缺失波次）：
#   长表 (id, t, ind, z)，z = 各指标全体观测统一标准化。
#   类 k × 指标 g 均值曲线 = deg 阶多项式（t_norm∈[0,1]）；残差方差 σ²[k,g] 独立。
#   每人对数似然 = 其全部观测行求和（局部独立假设）。
#   K 选择：AIC/BIC 主 + entropy/AvePP(≥0.70软)/OCC/最小类占比(≥5%)，多随机起始。
#
# 入口：
#   gbmtm_to_long(df_long)                 id,t,ind,y → +z,t_norm
#   gbmtm_fit(d, k, deg, n_start, seed)    单 K 拟合
#   gbmtm_select(d, k_range, ...)          逐 K + 最优选择
#   gbmtm_label(fit)                       升序风险命名表
###############################################################################

.gbmtm_basis <- function(t, deg) {
  do.call(cbind, lapply(0:deg, function(d) t^d))
}

#' 长表：列 id, t, ind, y → 追加 z（按指标全体观测标准化）与 t_norm
gbmtm_to_long <- function(df_long) {
  stopifnot(all(c("id", "t", "ind", "y") %in% names(df_long)))
  d <- df_long[!is.na(df_long$y), , drop = FALSE]
  d$z <- as.numeric(ave(d$y, d$ind, FUN = function(x) (x - mean(x)) / sd(x)))
  tt <- range(d$t)
  d$t_norm <- if (tt[1] == tt[2]) 0 else (d$t - tt[1]) / (tt[2] - tt[1])
  d
}

.gbmtm_init_resp <- function(d, K) {
  ids <- sort(unique(d$id)); nId <- length(ids)
  inds <- sort(unique(d$ind)); nInd <- length(inds)
  feats <- t(vapply(ids, function(i) {
    r <- d[d$id == i, ]
    unlist(lapply(inds, function(g) {
      x <- r[r$ind == g, ]
      if (nrow(x) >= 2) c(mean(x$z), as.numeric(stats::coef(lm(x$z ~ x$t_norm)))[2]) else c(mean(x$z), 0)
    }))
  }, numeric(2 * nInd)))
  km <- tryCatch(stats::kmeans(feats, centers = K, nstart = 5, iter.max = 50), error = function(e) NULL)
  resp <- matrix(1 / K, nId, K)
  if (!is.null(km)) {
    resp[cbind(seq_len(nId), km$cluster)] <- 0.9
    resp <- resp + 0.02 / K
    resp <- resp / rowSums(resp)
  }
  list(resp = resp, ids = ids)
}

#' 单 K 拟合（全向量化 EM）
#' @param d gbmtm_to_long 输出；@param deg 类内多项式阶；n_start=1 用 kmeans 播种，其余随机 Dirichlet
gbmtm_fit <- function(d, k, deg = 2, n_start = 10, maxit = 400, tol = 1e-5, seed = 42L, verbose = FALSE) {
  d$id <- as.character(d$id)
  ids <- sort(unique(d$id)); nId <- length(ids)
  inds <- sort(unique(d$ind)); nInd <- length(inds)
  idx_p <- match(d$id, ids)
  idx_g <- match(d$ind, inds)
  Xfull <- .gbmtm_basis(d$t_norm, deg)               # Nobs × (deg+1)
  ncolb <- deg + 1
  z <- d$z

  ll_of <- function(beta, sigma, pik) {   # pik=类比例；勿用 pi 命名（遮蔽常数 π）
    # beta: k × (nInd*ncolb); sigma: k × nInd；每人 LL = 全部观测行求和
    LP <- matrix(0, nId, k)
    for (ki in seq_len(k)) {
      llp <- numeric(nId)
      for (g in seq_along(inds)) {
        sel <- idx_g == g
        if (!any(sel)) next
        cols <- seq.int((g - 1) * ncolb + 1, g * ncolb)
        mu <- as.numeric(Xfull[sel, , drop = FALSE] %*% beta[ki, cols])
        s2 <- sigma[ki, g]^2
        contrib <- -0.5 * (log(2 * base::pi * s2) + (z[sel] - mu)^2 / s2)
        agg <- stats::aggregate(contrib, list(p = idx_p[sel]), FUN = sum)
        llp[agg$p] <- llp[agg$p] + agg$x
      }
      LP[, ki] <- llp
    }
    LP <- LP + matrix(log(pik), nId, k, byrow = TRUE)
    mx <- apply(LP, 1, max)
    llv <- mx + log(rowSums(exp(LP - mx)))
    list(LP = LP, ll = sum(llv))
  }

  best <- NULL
  for (st in seq_len(n_start)) {
    if (st == 1) {
      ini <- .gbmtm_init_resp(d, k); resp <- ini$resp
    } else {
      set.seed(seed + st * 977L)
      resp <- matrix(stats::rexp(nId * k), nId, k); resp <- resp / rowSums(resp)
    }
    beta <- matrix(0, k, nInd * ncolb); sigma <- matrix(1, k, nInd); pi <- rep(1 / k, k)
    ll <- -Inf; converged <- FALSE
    for (it in seq_len(maxit)) {
      Wt <- resp
      # --- M-step beta（加权 OLS，按 类×指标）；sigma 跨类共享（每指标一个）：
      # 3 时点 × K>=4 的类特异方差是 Gaussian 混合奇异解的经典来源（LL 爆增、
      # 小类塌到 sigma->0），Nagin 多轨迹 STS 同款约束。地板 0.2（z 尺度）。
      ss_g <- numeric(nInd); w_g <- numeric(nInd)
      for (ki in seq_len(k)) {
        wobs <- Wt[idx_p, ki]
        for (g in seq_along(inds)) {
          sel <- idx_g == g
          if (!any(sel)) next
          Xg <- Xfull[sel, , drop = FALSE]; zg <- z[sel]; wg <- wobs[sel]
          cols <- seq.int((g - 1) * ncolb + 1, g * ncolb)
          if (sum(wg) < 1e-4 || length(zg) < ncolb + 1) { beta[ki, cols] <- 0; next }
          fit <- tryCatch(stats::lm.wfit(Xg, zg, w = wg)$coefficients,
                          error = function(e) rep(0, ncolb))
          if (any(!is.finite(fit))) fit <- rep(0, ncolb)
          beta[ki, cols] <- fit
          mu <- as.numeric(Xg %*% fit)
          ss_g[g] <- ss_g[g] + sum(wg * (zg - mu)^2); w_g[g] <- w_g[g] + sum(wg)
        }
      }
      for (g in seq_along(inds)) {
        sigma[, g] <- sqrt(max(ss_g[g] / max(w_g[g], 1e-6), 0.2))
      }
      pi <- pmax(colSums(Wt) / sum(Wt), 1e-6); pi <- pi / sum(pi)
      res <- ll_of(beta, sigma, pi)
      if (verbose) cat(sprintf("  k=%d st=%d it=%d ll=%.2f pi=[%s] cls=[%s]\n", k, st, it, res$ll,
          paste(round(pi,2),collapse=","), paste(tabulate(apply(resp,1,which.max),k),collapse=",")))
      gain <- if (is.finite(ll)) res$ll - ll else Inf
      ll <- res$ll
      mx <- apply(res$LP, 1, max); E <- exp(res$LP - mx); resp <- E / rowSums(E)
      if (it > 10 && is.finite(gain) && gain < tol * (abs(ll) + 1)) { converged <- TRUE; break }
    }
    np <- (k - 1) + k * nInd * ncolb + nInd
    cand <- list(LL = ll, np = np, AIC = -2 * ll + 2 * np, BIC = -2 * ll + log(nId) * np,
                 beta = beta, sigma = sigma, pi = pi, LP = res$LP, converged = converged, iters = it)
    if (is.null(best) || (is.finite(cand$LL) && (!is.finite(best$LL) || cand$LL > best$LL))) best <- cand
  }

  post <- exp(best$LP - apply(best$LP, 1, max)); post <- post / rowSums(post)
  map <- apply(post, 1, which.max)
  tab <- tabulate(map, k)
  min_prop <- min(tab) / nId
  avepp <- vapply(seq_len(k), function(ks) if (tab[ks] > 0) mean(post[map == ks, ks]) else NA_real_, numeric(1))
  occ <- vapply(seq_len(k), function(ks) {
    if (tab[ks] == 0 || avepp[ks] >= 1) return(NA_real_)
    (avepp[ks] / (1 - avepp[ks])) * (tab[ks] / (nId - tab[ks]))
  }, numeric(1))
  H <- -sum(post * log(pmax(post, 1e-300)))
  entropy <- 1 - H / (nId * log(k))
  tt_grid <- sort(unique(d$t_norm))
  pred <- array(NA, dim = c(k, nInd, length(tt_grid)))
  for (ki in seq_len(k)) for (g in seq_along(inds)) {
    cols <- seq.int((g - 1) * ncolb + 1, g * ncolb)
    pred[ki, g, ] <- as.numeric(.gbmtm_basis(tt_grid, deg) %*% best$beta[ki, cols])
  }
  out <- list(K = k, LL = best$LL, np = best$np, AIC = best$AIC, BIC = best$BIC,
              pi = best$pi, beta = best$beta, sigma = best$sigma,
              posterior = post, class_map = setNames(as.integer(map), ids),
              ids = ids, entropy = entropy, avepp = avepp, occ = occ,
              min_prop = min_prop, n = nId, indicators = inds,
              times = sort(unique(d$t)), t_grid = tt_grid, pred = pred,
              converged = best$converged, iters = best$iters, deg = deg)
  class(out) <- "gbmtm"
  out
}

#' 逐 K 拟合 + 选择（AIC/BIC 主判据；min AvePP≥0.70 且最小类占比≥5% 为软门槛）
gbmtm_select <- function(d, k_range = 2:6, deg = 2, n_start = 10, seed = 42L) {
  fits <- lapply(k_range, function(k) {
    message("GBMTM K=", k)
    gbmtm_fit(d, k = k, deg = deg, n_start = n_start, seed = seed)
  })
  tab <- do.call(rbind, lapply(fits, function(f) {
    data.frame(K = f$K, LL = round(f$LL, 1), np = f$np, AIC = round(f$AIC, 1), BIC = round(f$BIC, 1),
               entropy = round(f$entropy, 3), min_avepp = round(min(f$avepp, na.rm = TRUE), 3),
               min_occ = round(min(f$occ, na.rm = TRUE), 1), min_prop = round(f$min_prop, 4),
               converged = f$converged)
  }))
  ok <- tab$min_avepp >= 0.70 & tab$min_prop >= 0.05
  pick_aic <- tab$K[which.min(tab$AIC)]; pick_bic <- tab$K[which.min(tab$BIC)]
  Kopt <- if (any(ok)) {
    tabo <- tab[ok, ]
    if (pick_aic %in% tabo$K) pick_aic else tabo$K[which.min(tabo$BIC)]
  } else pick_bic
  list(table = tab, fits = fits, K_opt = Kopt, pick_aic = pick_aic, pick_bic = pick_bic)
}

#' 升序风险命名：按基线（t_grid 首点）两指标 z 均值之和排序
gbmtm_label <- function(fit) {
  k <- fit$K
  base0 <- vapply(seq_len(k), function(ks) sum(fit$pred[ks, , 1]), numeric(1))
  # 类 i 的升序风险标签 = T(rank of base0[i])：最低 base_z → T1（参照组）
  mapping <- paste0("T", rank(base0, ties.method = "first"))
  tab <- tabulate(unname(fit$class_map), k)
  data.frame(class = seq_len(k), n = as.integer(tab), prop = round(tab / sum(tab), 4),
             base_z = round(base0, 3), label = mapping, stringsAsFactors = FALSE)
}
