# 毒物 ExWAS 下游：对齐 Dong 2026 EWAS-new
# ExWAS FDR 命中 → adaptive elastic-net ERS（gcdnet/glmnet）→ 加权 logistic
# → RCS(3 knots) → WQS(gWQS q=4) → 探索性炎症中介

exwas_tox_merge_inflam <- function(df, data_dir) {
  base_r <- file.path(data_dir, "D01_baseline_NHANES_0920.RData")
  if (!file.exists(base_r)) return(df)
  e <- new.env()
  load(base_r, envir = e)
  b <- e$baseline
  b$cycle <- as.character(b$Source_File)
  b$SEQN <- as.character(b$ID)
  keep <- c(
    "cycle", "SEQN", "WBC", "NeutrophilCount", "Lymphocytes",
    "Mononuclear_cell_count", "PlateletCount", "Platelet", "CRP", "HSCRP"
  )
  keep <- intersect(keep, names(b))
  m <- merge(df, b[, keep, drop = FALSE], by = c("cycle", "SEQN"), all.x = TRUE,
             suffixes = c("", "_inf"))
  # 合成文献六中介（能算则算）
  wbc <- exwas_to_num(m$WBC)
  neu <- exwas_to_num(m$NeutrophilCount)
  lym <- exwas_to_num(m$Lymphocytes)
  mono <- exwas_to_num(m$Mononuclear_cell_count)
  m$NEUT <- neu
  m$MONO <- mono
  m$NLR <- ifelse(is.finite(neu) & is.finite(lym) & lym > 0, neu / lym, NA_real_)
  # SII ≈ NEUT * PLT / LYM；无血小板则跳过
  if ("Platelet" %in% names(m) || "PlateletCount" %in% names(m)) {
    plt <- if ("PlateletCount" %in% names(m)) exwas_to_num(m$PlateletCount) else exwas_to_num(m$Platelet)
    m$SII <- ifelse(is.finite(neu) & is.finite(plt) & is.finite(lym) & lym > 0,
                    neu * plt / lym, NA_real_)
  } else {
    m$SII <- NA_real_
  }
  # SIRI ≈ NEUT * MONO / LYM
  m$SIRI <- ifelse(is.finite(neu) & is.finite(mono) & is.finite(lym) & lym > 0,
                   neu * mono / lym, NA_real_)
  # 癌症常用补充指数（NHANES CBC 可算）
  if ("Platelet" %in% names(m) || "PlateletCount" %in% names(m)) {
    plt2 <- if ("PlateletCount" %in% names(m)) exwas_to_num(m$PlateletCount) else exwas_to_num(m$Platelet)
    m$PLR <- ifelse(is.finite(plt2) & is.finite(lym) & lym > 0, plt2 / lym, NA_real_)
  } else {
    m$PLR <- NA_real_
  }
  m$LMR <- ifelse(is.finite(lym) & is.finite(mono) & mono > 0, lym / mono, NA_real_)
  m
}

# 泛癌探索性中介：临床筛后 IDE 显著的 4 项（锁定 Model2；非牙周炎症六项照搬）
# TotalProtein / Albumin（营养-肝蛋白）；MCH（造血）；WHtR（中心性肥胖）
# Creatinine 虽 IDE 显著但与 Model2 eGFR 同域，不入主文
exwas_tox_cancer_mediators_default <- function() {
  c("TotalProtein", "Albumin", "Mean_cell_hemoglobin", "WHtR")
}

# mediation::mediate + bootstrap（对齐 Dong：sims=1000；连续中介 lm / 二分类结局 glm）
# 返回 list(table, mediate, a, b)；失败返回 NULL
exwas_tox_mediate_one <- function(df, treat, mediator, outcome = "DN",
                                  covars = character(0),
                                  weight_col = "WTSA2YR",
                                  sims = 1000L, seed = 123456L) {
  if (!requireNamespace("mediation", quietly = TRUE)) {
    stop("需要 mediation 包", call. = FALSE)
  }
  need <- unique(c(treat, mediator, outcome, covars, weight_col))
  need <- need[nzchar(need)]
  use <- df[, intersect(need, names(df)), drop = FALSE]
  for (nm in c(treat, mediator, outcome)) use[[nm]] <- exwas_to_num(use[[nm]])
  if (weight_col %in% names(use)) use[[weight_col]] <- exwas_to_num(use[[weight_col]])
  ok <- stats::complete.cases(use[, intersect(c(treat, mediator, outcome, covars), names(use)), drop = FALSE])
  if (weight_col %in% names(use)) {
    ok <- ok & is.finite(use[[weight_col]]) & use[[weight_col]] > 0
  }
  use <- use[ok, , drop = FALSE]
  if (nrow(use) < 200L || length(unique(use[[outcome]])) < 2L) {
    return(NULL)
  }
  rhs <- if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""
  f_m <- stats::as.formula(paste(mediator, "~", treat, rhs))
  f_y <- stats::as.formula(paste(outcome, "~", treat, "+", mediator, rhs))
  # 调查权重归一化到 mean=1，避免 binomial glm 把大权重当频数导致系数爆炸
  wts <- NULL
  if (weight_col %in% names(use)) {
    w_raw <- exwas_to_num(use[[weight_col]])
    wts <- w_raw / mean(w_raw, na.rm = TRUE)
  }
  set.seed(as.integer(seed))
  # do.call 把公式对象写入 call，避免 bootstrap 时找不到局部符号 f_m
  model.m <- do.call(stats::lm, list(formula = f_m, data = use, weights = wts))
  # 二分类结局用 probit：与 mediation::medsens 兼容（logit 会报 only valid for probit）
  model.y <- do.call(
    stats::glm,
    list(
      formula = f_y,
      data = use,
      family = stats::binomial(link = "probit"),
      weights = wts
    )
  )
  med <- tryCatch(
    mediation::mediate(
      model.m, model.y,
      treat = treat, mediator = mediator,
      boot = TRUE, sims = as.integer(sims),
      boot.ci.type = "perc"
    ),
    error = function(e) e
  )
  if (inherits(med, "error")) {
    warning("mediate failed for ", mediator, ": ", conditionMessage(med), call. = FALSE)
    return(NULL)
  }
  cm <- stats::coef(model.m)
  cy <- stats::coef(model.y)
  a_hat <- unname(cm[treat])
  b_hat <- unname(cy[mediator])
  # mediation 4.x：Total = tau.coef / tau.ci / tau.p（无 total.avg）
  .ci1 <- function(x) {
    if (is.null(x) || !length(x)) return(c(NA_real_, NA_real_))
    as.numeric(x)[1:2]
  }
  tot_ci <- .ci1(med$tau.ci)
  # ACME = IDE, ADE = DE；二分类结局默认风险差尺度
  tab <- data.frame(
    mediator = mediator,
    n = nrow(use),
    a = a_hat,
    b = b_hat,
    IDE = as.numeric(med$d.avg),
    IDE_lo = .ci1(med$d.avg.ci)[1],
    IDE_hi = .ci1(med$d.avg.ci)[2],
    IDE_p = as.numeric(med$d.avg.p),
    DE = as.numeric(med$z.avg),
    DE_lo = .ci1(med$z.avg.ci)[1],
    DE_hi = .ci1(med$z.avg.ci)[2],
    DE_p = as.numeric(med$z.avg.p),
    Total = as.numeric(med$tau.coef),
    Total_lo = tot_ci[1],
    Total_hi = tot_ci[2],
    Total_p = as.numeric(med$tau.p),
    Prop = as.numeric(med$n.avg),
    Prop_lo = .ci1(med$n.avg.ci)[1],
    Prop_hi = .ci1(med$n.avg.ci)[2],
    Prop_p = as.numeric(med$n.avg.p),
    method = "mediation_boot",
    sims = as.integer(sims),
    treat = treat,
    weight_norm = "mean1",
    exploratory = TRUE,
    stringsAsFactors = FALSE
  )
  list(table = tab, mediate = med, model.m = model.m, model.y = model.y, a = a_hat, b = b_hat)
}

# 画单块路径图（对齐 Dong Fig5：ERS → Mediator → Outcome；底注 IDE/DE/Total/Prop）
exwas_tox_draw_mediation_panel <- function(row, panel_lab, outcome_lab = "Pan-cancer",
                                           treat_lab = "ERS") {
  fmt <- function(x, d = 3) {
    if (!is.finite(x)) return("NA")
    sprintf(paste0("%.", d, "f"), x)
  }
  fmt_p <- function(p) {
    if (!is.finite(p)) return("NA")
    if (p < 0.001) return("<0.001")
    sprintf("%.3f", p)
  }
  med_lab <- as.character(row$mediator[[1]])
  grid::pushViewport(grid::viewport(width = 0.92, height = 0.88))
  # 三框坐标
  boxes <- list(
    treat = list(x = 0.18, y = 0.42, w = 0.22, h = 0.16, lab = treat_lab),
    med   = list(x = 0.50, y = 0.78, w = 0.28, h = 0.16, lab = med_lab),
    out   = list(x = 0.82, y = 0.42, w = 0.26, h = 0.16, lab = outcome_lab)
  )
  for (bx in boxes) {
    grid::grid.roundrect(
      x = bx$x, y = bx$y, width = bx$w, height = bx$h,
      r = grid::unit(0.08, "snpc"),
      gp = grid::gpar(fill = "white", col = "grey25", lwd = 1.4)
    )
    grid::grid.text(
      bx$lab, x = bx$x, y = bx$y,
      gp = grid::gpar(fontsize = 10, fontface = "bold", fontfamily = "serif")
    )
  }
  # 箭头：treat→med (a), med→out (b), treat→out (DE)
  arr <- function(x0, y0, x1, y1, lab, lab_off = c(0, 0.04)) {
    grid::grid.lines(
      x = c(x0, x1), y = c(y0, y1),
      arrow = grid::arrow(type = "closed", length = grid::unit(0.12, "inches")),
      gp = grid::gpar(col = "grey20", fill = "grey20", lwd = 1.2)
    )
    grid::grid.text(
      lab, x = mean(c(x0, x1)) + lab_off[1], y = mean(c(y0, y1)) + lab_off[2],
      gp = grid::gpar(fontsize = 8.5, fontfamily = "serif", col = "#B2182B")
    )
  }
  arr(0.29, 0.50, 0.40, 0.70, paste0("a=", fmt(row$a)), c(-0.06, 0.02))
  arr(0.60, 0.70, 0.71, 0.50, paste0("b=", fmt(row$b)), c(0.06, 0.02))
  arr(0.29, 0.42, 0.69, 0.42, paste0("DE=", fmt(row$DE)), c(0, -0.05))
  # 底注效应量
  note <- paste0(
    panel_lab, "  IDE=", fmt(row$IDE), " (", fmt(row$IDE_lo), ", ", fmt(row$IDE_hi), ")",
    "; P=", fmt_p(row$IDE_p), "\n",
    "DE=", fmt(row$DE), " (", fmt(row$DE_lo), ", ", fmt(row$DE_hi), ")",
    "; Total=", fmt(row$Total), " (", fmt(row$Total_lo), ", ", fmt(row$Total_hi), ")\n",
    "Proportion mediated=", fmt(100 * row$Prop, 1), "%",
    " (P=", fmt_p(row$Prop_p), "); n=", format(as.integer(row$n), big.mark = ",")
  )
  grid::grid.text(
    note, x = 0.5, y = 0.12,
    gp = grid::gpar(fontsize = 7.5, fontfamily = "serif", lineheight = 1.1)
  )
  grid::popViewport()
}

exwas_tox_draw_fig5_mediation <- function(tab, path, outcome_lab = "Pan-cancer",
                                          treat_lab = "ERS",
                                          width = 11, height = 8,
                                          ncol = NULL) {
  stopifnot(is.data.frame(tab), nrow(tab) >= 1L)
  n <- nrow(tab)
  if (is.null(ncol)) ncol <- if (n <= 4L) 2L else 3L
  ncol <- as.integer(ncol)
  nrow_g <- as.integer(ceiling(n / ncol))
  grDevices::cairo_pdf(path, width = width, height = height, family = "serif")
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(nrow_g, ncol)))
  labs <- LETTERS[seq_len(n)]
  for (i in seq_len(n)) {
    rr <- ((i - 1L) %/% ncol) + 1L
    cc <- ((i - 1L) %% ncol) + 1L
    grid::pushViewport(grid::viewport(layout.pos.row = rr, layout.pos.col = cc))
    exwas_tox_draw_mediation_panel(tab[i, , drop = FALSE], labs[[i]],
                                   outcome_lab = outcome_lab, treat_lab = treat_lab)
    grid::popViewport()
  }
  grid::popViewport()
  grDevices::dev.off()
  invisible(path)
}

# Adaptive elastic-net（Dong 2026：gcdnet 主路径；11 α × 50 λ；5-fold；Z-score）
# 原文：α∈[0,1]×11，λ 网格 50 点，bootstrap 入选频率；连续暴露 Z-score，二分类 0/1
exwas_tox_fit_adaptive_enet <- function(df, y, exposures,
                                        alphas = seq(0, 1, length.out = 11),
                                        nfolds = 5L, seed = 123456L,
                                        n_boot = 200L,
                                        use_gcdnet = TRUE,
                                        max_miss = 0.55,
                                        impute_exposures = TRUE,
                                        nlambda = 50L,
                                        lambda_min = 1e-3,
                                        lambda_max = 1e2) {
  exposures <- intersect(exposures, names(df))
  if (!length(exposures)) stop("ERS 无可用暴露列", call. = FALSE)
  miss <- vapply(exposures, function(nm) {
    mean(!is.finite(exwas_to_num(df[[nm]])))
  }, numeric(1))
  keep_x <- names(miss)[is.finite(miss) & miss <= as.numeric(max_miss)]
  dropped <- setdiff(exposures, keep_x)
  if (length(dropped)) {
    exwas_log("ERS 剔除高缺失暴露(", length(dropped), "): ",
              paste(utils::head(dropped, 12), collapse = ","),
              if (length(dropped) > 12) "..." else "")
  }
  if (length(keep_x) < 2L) {
    stop("ERS 可用暴露<2（max_miss=", max_miss, "）", call. = FALSE)
  }
  need <- unique(c(y, keep_x))
  dd <- df[, need, drop = FALSE]
  for (nm in names(dd)) dd[[nm]] <- exwas_to_num(dd[[nm]])
  dd <- dd[is.finite(dd[[y]]), , drop = FALSE]
  if (isTRUE(impute_exposures)) {
    for (nm in keep_x) {
      v <- dd[[nm]]
      med <- stats::median(v[is.finite(v)], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      v[!is.finite(v)] <- med
      dd[[nm]] <- v
    }
  }
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 80L || sum(dd[[y]] == 1) < 15L) {
    stop("ERS 建模样本量不足: n=", nrow(dd), " events=", sum(dd[[y]] == 1), call. = FALSE)
  }
  exposures <- keep_x
  Xraw <- as.matrix(dd[, exposures, drop = FALSE])
  yy <- dd[[y]]
  # 原文：连续 Z-score；二分类保持 0/1（≤2 个有限水平视为二分类）
  is_bin <- vapply(exposures, function(nm) {
    u <- unique(Xraw[, nm][is.finite(Xraw[, nm])])
    length(u) <= 2L
  }, logical(1))
  center <- setNames(rep(0, length(exposures)), exposures)
  scalev <- setNames(rep(1, length(exposures)), exposures)
  X <- Xraw
  for (nm in exposures) {
    if (isTRUE(is_bin[[nm]])) {
      # keep 0/1
      X[, nm] <- Xraw[, nm]
    } else {
      mu <- mean(Xraw[, nm], na.rm = TRUE)
      sdv <- stats::sd(Xraw[, nm], na.rm = TRUE)
      if (!is.finite(sdv) || sdv == 0) sdv <- 1
      center[[nm]] <- mu
      scalev[[nm]] <- sdv
      X[, nm] <- (Xraw[, nm] - mu) / sdv
    }
  }
  set.seed(as.integer(seed))
  # glmnet/gcdnet 惯例：λ 递减序列（原文 0.001–100，此处按对数等距递减）
  lambda_seq <- exp(seq(log(as.numeric(lambda_max)), log(as.numeric(lambda_min)),
                        length.out = as.integer(nlambda)))
  .alpha_to_lambda2 <- function(a) {
    if (!is.finite(a)) return(1)
    if (a >= 1) return(0)
    if (a <= 0) return(1e3)
    (1 - a) / (2 * a)
  }
  .gcdnet_coef_vec <- function(cvfit) {
    fit <- if (!is.null(cvfit$gcdnet.fit)) cvfit$gcdnet.fit else cvfit
    if (is.null(fit) || is.null(fit$beta)) return(NULL)
    lam <- as.numeric(fit$lambda)
    target <- if (!is.null(cvfit$lambda.min)) as.numeric(cvfit$lambda.min) else NA_real_
    j <- if (is.finite(target)) which.min(abs(lam - target)) else NA_integer_
    if (!length(j) || !is.finite(j)) {
      j <- if (!is.null(cvfit$cvm)) which.min(cvfit$cvm) else length(lam)
    }
    j <- as.integer(j[[1L]])
    bmat <- tryCatch(as.matrix(fit$beta), error = function(e) NULL)
    if (is.null(bmat) || j < 1L || j > ncol(bmat)) return(NULL)
    rn_x <- rownames(bmat)
    if (is.null(rn_x) || !length(rn_x)) rn_x <- colnames(X)
    b0 <- as.numeric(fit$b0[j])
    if (!is.finite(b0)) b0 <- 0
    vec <- c("(Intercept)" = b0, setNames(as.numeric(bmat[, j]), rn_x))
    vec
  }

  use_g <- isTRUE(use_gcdnet) && requireNamespace("gcdnet", quietly = TRUE)
  if (use_g) {
    # 必须 attach：gcdnet 用 S3method 覆盖 stats::coef/predict，仅 requireNamespace 时 coef() 会坏
    suppressPackageStartupMessages(require("gcdnet", quietly = TRUE, character.only = TRUE))
  } else if (isTRUE(use_gcdnet)) {
    exwas_log("警告：gcdnet 不可用，回退 glmnet（与 Dong 2026 不完全一致）")
  }

  alpha_path <- data.frame(
    alpha = as.numeric(alphas), lambda2 = NA_real_, cvm = NA_real_,
    cvsd = NA_real_, lambda_min = NA_real_, nzero = NA_integer_,
    stringsAsFactors = FALSE
  )
  best <- NULL
  cv_by_alpha <- list()

  if (use_g) {
    for (i in seq_along(alphas)) {
      a <- alphas[[i]]
      l2 <- .alpha_to_lambda2(a)
      cv <- tryCatch(
        gcdnet::cv.gcdnet(
          X, yy, method = "logit", lambda = lambda_seq, lambda2 = l2,
          nfolds = as.integer(nfolds), pred.loss = "loss",
          standardize = FALSE, intercept = TRUE
        ),
        error = function(e) NULL
      )
      if (is.null(cv)) next
      j <- which.min(cv$cvm)
      alpha_path$lambda2[i] <- l2
      alpha_path$cvm[i] <- cv$cvm[j]
      alpha_path$cvsd[i] <- cv$cvsd[j]
      alpha_path$lambda_min[i] <- cv$lambda.min
      nz <- tryCatch({
        v <- .gcdnet_coef_vec(cv)
        sum(abs(v[setdiff(names(v), "(Intercept)")]) > 0, na.rm = TRUE)
      }, error = function(e) NA_integer_)
      alpha_path$nzero[i] <- nz
      cv_by_alpha[[as.character(a)]] <- cv
      if (is.null(best) || isTRUE(cv$cvm[j] < best$dev)) {
        best <- list(alpha = a, lambda2 = l2, cv = cv, dev = cv$cvm[j])
      }
    }
  }
  if (is.null(best)) {
    # glmnet 回退（仅当 gcdnet 全失败）
    for (i in seq_along(alphas)) {
      a <- alphas[[i]]
      cv <- tryCatch(
        glmnet::cv.glmnet(X, yy, family = "binomial", alpha = a,
                          lambda = lambda_seq, nfolds = as.integer(nfolds)),
        error = function(e) NULL
      )
      if (is.null(cv)) next
      j <- which.min(cv$cvm)
      alpha_path$cvm[i] <- cv$cvm[j]
      alpha_path$cvsd[i] <- cv$cvsd[j]
      alpha_path$lambda_min[i] <- cv$lambda.min
      alpha_path$nzero[i] <- cv$nzero[j]
      if (is.null(best) || isTRUE(cv$cvm[j] < best$dev)) {
        best <- list(alpha = a, lambda2 = NA_real_, cv = cv, dev = cv$cvm[j], engine = "glmnet")
      }
    }
  }
  if (is.null(best)) stop("elastic-net CV 失败", call. = FALSE)
  engine1 <- if (!is.null(best$engine)) best$engine else "gcdnet"

  # adaptive weights from stage-1
  b1_abs <- setNames(rep(0, length(exposures)), exposures)
  if (identical(engine1, "gcdnet")) {
    v1 <- .gcdnet_coef_vec(best$cv)
    if (!is.null(v1) && length(v1)) {
      nm <- intersect(setdiff(names(v1), "(Intercept)"), exposures)
      if (length(nm)) b1_abs[nm] <- abs(as.numeric(v1[nm]))
    }
  } else {
    b1m <- as.matrix(coef(best$cv, s = "lambda.min"))
    rn <- setdiff(rownames(b1m), "(Intercept)")
    rn <- intersect(rn, exposures)
    if (length(rn)) b1_abs[rn] <- abs(as.numeric(b1m[rn, 1]))
  }
  # 若 stage-1 全零，adaptive 退化为等权（仍可跑 stage-2）
  if (!any(b1_abs > 0)) b1_abs[] <- 1
  pf <- 1 / pmax(b1_abs, 1e-6)

  # stage-2 adaptive at best alpha
  gcdnet_used <- FALSE
  cv2 <- NULL
  beta <- numeric(0)
  if (identical(engine1, "gcdnet") || use_g) {
    l2 <- .alpha_to_lambda2(best$alpha)
    cv2 <- tryCatch(
      gcdnet::cv.gcdnet(
        X, yy, method = "logit", lambda = lambda_seq, lambda2 = l2,
        nfolds = as.integer(nfolds), pred.loss = "loss",
        pf = as.numeric(pf), standardize = FALSE, intercept = TRUE
      ),
      error = function(e) NULL
    )
    if (!is.null(cv2)) {
      v2 <- .gcdnet_coef_vec(cv2)
      if (!is.null(v2)) {
        sel <- setdiff(names(v2)[is.finite(v2) & abs(v2) > 0], "(Intercept)")
        sel <- intersect(sel, exposures)
        beta <- v2[sel]
        gcdnet_used <- TRUE
      }
    }
  }
  if (!gcdnet_used) {
    cv2 <- tryCatch(
      glmnet::cv.glmnet(
        X, yy, family = "binomial", alpha = best$alpha, lambda = lambda_seq,
        nfolds = as.integer(nfolds), penalty.factor = as.numeric(pf)
      ),
      error = function(e) best$cv
    )
    coefs <- as.matrix(coef(cv2, s = "lambda.min"))
    sel <- setdiff(rownames(coefs)[abs(coefs[, 1]) > 0], "(Intercept)")
    beta <- coefs[sel, 1]
  }
  if (!length(beta)) stop("ERS 未选出任何暴露", call. = FALSE)

  lam_final <- as.numeric(cv2$lambda.min)
  if (!is.finite(lam_final)) lam_final <- as.numeric(lambda_seq[length(lambda_seq)])

  # Bootstrap 入选频率（固定主分析最优 α/λ2，在 bootstrap 样本上拟合路径，
  # 取与主分析 lambda.min 最近的系数；对齐原文 B=1000 稳定性评估，避免每次全 CV）
  n_boot <- as.integer(n_boot)
  inc <- setNames(integer(length(exposures)), exposures)
  lam_star <- as.numeric(lam_final)
  l2_star <- .alpha_to_lambda2(best$alpha)
  if (n_boot > 0L) {
    for (b in seq_len(n_boot)) {
      idx <- sample.int(nrow(X), replace = TRUE)
      Xb <- X[idx, , drop = FALSE]
      yb <- yy[idx]
      if (length(unique(yb)) < 2L) next
      if (gcdnet_used) {
        fitb <- tryCatch(
          gcdnet::gcdnet(
            Xb, yb, method = "logit", lambda = lambda_seq, lambda2 = l2_star,
            pf = pf, standardize = FALSE, intercept = TRUE
          ),
          error = function(e) NULL
        )
        if (is.null(fitb)) next
        vec <- .gcdnet_coef_vec(list(gcdnet.fit = fitb, lambda.min = lam_star))
        if (is.null(vec)) next
        sb <- intersect(setdiff(names(vec)[is.finite(vec) & abs(vec) > 0], "(Intercept)"), exposures)
      } else {
        fitb <- tryCatch(
          glmnet::glmnet(
            Xb, yb, family = "binomial", alpha = best$alpha,
            lambda = lambda_seq, penalty.factor = pf
          ),
          error = function(e) NULL
        )
        if (is.null(fitb)) next
        cb <- as.matrix(stats::coef(fitb, s = lam_star))
        sb <- intersect(setdiff(rownames(cb)[abs(cb[, 1]) > 0], "(Intercept)"), exposures)
      }
      inc[sb] <- inc[sb] + 1L
      if (b %% 100L == 0L) {
        exwas_log("ERS bootstrap ", b, "/", n_boot)
      }
    }
  }
  freq <- data.frame(
    exposure = exposures,
    inclusion_n = as.integer(inc[exposures]),
    inclusion_freq = as.numeric(inc[exposures]) / max(n_boot, 1L),
    selected_final = exposures %in% names(beta),
    coef = unname(beta[match(exposures, names(beta))]),
    is_binary = unname(is_bin[exposures]),
    stringsAsFactors = FALSE
  )
  freq <- freq[order(-freq$inclusion_freq, -freq$selected_final), ]

  list(
    alpha = best$alpha,
    lambda = lam_final,
    lambda2 = .alpha_to_lambda2(best$alpha),
    selected = names(beta),
    beta = beta,
    freq = freq,
    n_model = nrow(dd),
    n_events = sum(yy == 1),
    gcdnet_used = gcdnet_used,
    n_boot = n_boot,
    alpha_path = alpha_path,
    cv_final = cv2,
    center = center,
    scale = scalev,
    is_binary = is_bin,
    lambda_seq = lambda_seq
  )
}

exwas_tox_score_ers <- function(df, beta, impute_median = TRUE,
                                center = NULL, scale = NULL, is_binary = NULL) {
  sel <- names(beta)
  sel <- sel[sel %in% names(df)]
  ers <- rep(NA_real_, nrow(df))
  if (!length(sel)) return(ers)
  Xm <- sapply(sel, function(v) exwas_to_num(df[[v]]))
  if (!is.matrix(Xm)) Xm <- matrix(Xm, ncol = length(sel), dimnames = list(NULL, sel))
  if (isTRUE(impute_median)) {
    for (j in seq_len(ncol(Xm))) {
      med <- stats::median(Xm[, j][is.finite(Xm[, j])], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      Xm[!is.finite(Xm[, j]), j] <- med
    }
  }
  # 若提供训练标准化参数，按原文对连续列做 Z-score
  if (!is.null(center) && !is.null(scale)) {
    for (nm in sel) {
      bin <- if (!is.null(is_binary) && nm %in% names(is_binary)) isTRUE(is_binary[[nm]]) else FALSE
      if (bin) next
      mu <- center[[nm]]; sdv <- scale[[nm]]
      if (!is.finite(mu)) mu <- 0
      if (!is.finite(sdv) || sdv == 0) sdv <- 1
      Xm[, nm] <- (Xm[, nm] - mu) / sdv
    }
  }
  ok <- rowSums(!is.finite(Xm)) == 0
  if (any(ok)) {
    ers[ok] <- as.numeric(Xm[ok, , drop = FALSE] %*% as.numeric(beta[sel]))
  }
  ers
}

.exwas_tox_svy_or_row <- function(df, y, x, covars, cfg) {
  if (!exwas_has_survey(df, cfg)) return(NULL)
  des <- exwas_design(df, cfg)
  rhs <- c(x, covars)
  fml <- stats::as.formula(paste(y, "~", paste(rhs, collapse = " + ")))
  fit <- tryCatch(
    survey::svyglm(fml, design = des, family = stats::quasibinomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  cf <- summary(fit)$coefficients
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) return(NULL)
  b <- cf[hit[1], 1]; se <- cf[hit[1], 2]
  data.frame(
    OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
    p = cf[hit[1], 4], stringsAsFactors = FALSE
  )
}

exwas_tox_ers_assoc_table <- function(df, covars,
                                      weight_col = "WTSA2YR",
                                      psu = "SDMVPSU", strata = "SDMVSTRA_cyc") {
  use <- df[is.finite(df$ERS), , drop = FALSE]
  if (!strata %in% names(use) && "SDMVSTRA" %in% names(use)) {
    use[[strata]] <- use$SDMVSTRA
  }
  if (!psu %in% names(use) && "SDMVPSU" %in% names(use)) {
    use[[psu]] <- use$SDMVPSU
  }
  # 加权关联：仅保留正权重 + PSU/层；缺设计变量时退回正权重子集（仍可 unweighted fit）
  ww <- exwas_to_num(use[[weight_col]])
  keep_w <- is.finite(ww) & ww > 0
  if (psu %in% names(use) && strata %in% names(use)) {
    keep_w <- keep_w &
      is.finite(exwas_to_num(use[[psu]])) &
      is.finite(exwas_to_num(use[[strata]]))
  }
  use <- use[keep_w, , drop = FALSE]
  if (!nrow(use)) {
    stop("ERS 关联表无可用行（检查 ERS/权重/PSU/strata）", call. = FALSE)
  }
  iqr <- stats::IQR(use$ERS, na.rm = TRUE)
  if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(use$ERS, na.rm = TRUE)
  if (!is.finite(iqr) || iqr == 0) iqr <- 1
  use$ERS_IQR <- use$ERS / iqr
  med <- stats::median(use$ERS, na.rm = TRUE)
  use$ERS_group <- factor(
    ifelse(use$ERS >= med, "High", "Low"),
    levels = c("Low", "High")
  )
  sw <- list(survey_weight = weight_col, survey_psu = psu, survey_strata = strata)
  rows <- list()
  specs <- list(
    list(model = "Model1_continuous", x = "ERS_IQR", covars = character(0)),
    list(model = "Model2_continuous", x = "ERS_IQR", covars = covars),
    list(model = "Model1_High_vs_Low", x = "ERS_group", covars = character(0)),
    list(model = "Model2_High_vs_Low", x = "ERS_group", covars = covars)
  )
  for (sp in specs) {
    est <- .exwas_tox_svy_or_row(use, "DN", sp$x, sp$covars, sw)
    weighted <- TRUE
    if (is.null(est)) {
      est <- exwas_fit_one(use, "DN", sp$x, sp$covars)
      weighted <- FALSE
      est <- data.frame(OR = est$OR, lo = est$lo, hi = est$hi, p = est$p)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      model = sp$model, exposure = sp$x, weighted = weighted,
      OR = est$OR, lo = est$lo, hi = est$hi, p = est$p,
      n = nrow(use), n_events = sum(use$DN == 1, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  list(table = do.call(rbind, rows), data = use, ers_median = med, ers_iqr = iqr)
}

exwas_tox_ers_rcs_note <- function(use, covars, sw, out_file) {
  if (!exwas_has_survey(use, sw) || !requireNamespace("splines", quietly = TRUE)) {
    writeLines("RCS skipped (no survey design or splines)", out_file)
    return(invisible(NULL))
  }
  des <- exwas_design(use, sw)
  rhs_c <- if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""
  f_lin <- stats::as.formula(paste("DN ~ ERS_IQR", rhs_c))
  f_rcs <- stats::as.formula(paste("DN ~ splines::ns(ERS_IQR, df = 2)", rhs_c))
  fit_l <- tryCatch(survey::svyglm(f_lin, design = des, family = stats::quasibinomial()),
                    error = function(e) NULL)
  fit_s <- tryCatch(survey::svyglm(f_rcs, design = des, family = stats::quasibinomial()),
                    error = function(e) NULL)
  p_nl <- NA_real_
  if (!is.null(fit_l) && !is.null(fit_s)) {
    p_nl <- tryCatch(
      stats::pchisq(max(0, fit_l$deviance - fit_s$deviance), df = 1, lower.tail = FALSE),
      error = function(e) NA_real_
    )
  }
  writeLines(
    c(
      "RCS: 3 knots via splines::ns(ERS_IQR, df=2); survey-weighted quasibinomial",
      paste0("weight=", sw$survey_weight, "; psu=", sw$survey_psu, "; strata=", sw$survey_strata),
      paste0("p_nonlinear_approx=", p_nl),
      paste0("covars=", if (length(covars)) paste(covars, collapse = "+") else "(none)")
    ),
    out_file
  )
  invisible(p_nl)
}
