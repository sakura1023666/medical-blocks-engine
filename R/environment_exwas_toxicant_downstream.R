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
  m
}

# Adaptive elastic-net（优先 gcdnet；否则 glmnet + penalty.factor）
# 对齐原文：11 个 α∈[0,1]，λ 网格，5-fold CV；bootstrap 入选频率
exwas_tox_fit_adaptive_enet <- function(df, y, exposures,
                                        alphas = seq(0, 1, length.out = 11),
                                        nfolds = 5L, seed = 123456L,
                                        n_boot = 200L,
                                        use_gcdnet = TRUE,
                                        max_miss = 0.55,
                                        impute_exposures = TRUE) {
  exposures <- intersect(exposures, names(df))
  if (!length(exposures)) stop("ERS 无可用暴露列", call. = FALSE)
  # 多周期命中常跨面板：先丢掉缺失过高的列，再对剩余暴露中位数填补（原文单周期无需此步）
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
  # 结局缺失剔除
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
  X <- as.matrix(dd[, exposures, drop = FALSE])
  yy <- dd[[y]]
  set.seed(as.integer(seed))

  # ---- 主拟合：glmnet α 网格（与原文 11×λ / 5-fold 同构）----
  best <- NULL
  for (a in alphas) {
    cv <- tryCatch(
      glmnet::cv.glmnet(X, yy, family = "binomial", alpha = a, nfolds = as.integer(nfolds)),
      error = function(e) NULL
    )
    if (is.null(cv)) next
    dev <- min(cv$cvm, na.rm = TRUE)
    if (is.null(best) || isTRUE(dev < best$dev)) {
      best <- list(alpha = a, cv = cv, dev = dev)
    }
  }
  if (is.null(best)) stop("elastic-net CV 失败", call. = FALSE)

  b1 <- as.matrix(stats::coef(best$cv, s = "lambda.min"))
  b1 <- b1[setdiff(rownames(b1), "(Intercept)"), , drop = FALSE]
  # adaptive 权重
  pf <- 1 / pmax(abs(as.numeric(b1[, 1])), 1e-6)
  names(pf) <- rownames(b1)

  # 第二阶段 adaptive
  cv2 <- tryCatch(
    glmnet::cv.glmnet(
      X, yy, family = "binomial", alpha = best$alpha, nfolds = as.integer(nfolds),
      penalty.factor = pf[colnames(X)]
    ),
    error = function(e) NULL
  )
  if (is.null(cv2)) cv2 <- best$cv
  coefs <- as.matrix(stats::coef(cv2, s = "lambda.min"))
  sel <- setdiff(rownames(coefs)[abs(coefs[, 1]) > 0], "(Intercept)")
  beta <- coefs[sel, 1]

  # 可选：gcdnet 再校准（同 λ2≈(1-α)）
  gcdnet_used <- FALSE
  if (isTRUE(use_gcdnet) && requireNamespace("gcdnet", quietly = TRUE) && length(sel) >= 1L) {
    lam2 <- max(1e-6, (1 - best$alpha))
    pf_g <- pf[colnames(X)]
    fit_g <- tryCatch(
      gcdnet::cv.gcdnet(
        X, yy, method = "logit", lambda2 = lam2, pf = pf_g,
        nfolds = as.integer(nfolds), pred.loss = "loss"
      ),
      error = function(e) NULL
    )
    if (!is.null(fit_g)) {
      cg <- tryCatch(as.matrix(stats::coef(fit_g$gcdnet.fit, s = fit_g$lambda.min)),
                     error = function(e) NULL)
      if (!is.null(cg)) {
        # gcdnet coef 结构可能是矩阵列=lambda
        if (ncol(cg) > 1L) cg <- cg[, which.min(abs(fit_g$gcdnet.fit$lambda - fit_g$lambda.min)), drop = FALSE]
        rn <- rownames(cg)
        if (is.null(rn)) rn <- c("(Intercept)", colnames(X))
        names(cg) <- NULL
        vec <- as.numeric(cg)
        names(vec) <- rn[seq_along(vec)]
        sel_g <- setdiff(names(vec)[is.finite(vec) & abs(vec) > 0], "(Intercept)")
        if (length(sel_g)) {
          sel <- intersect(sel_g, colnames(X))
          beta <- vec[sel]
          gcdnet_used <- TRUE
        }
      }
    }
  }

  # Bootstrap 入选频率
  n_boot <- as.integer(n_boot)
  inc <- setNames(integer(length(exposures)), exposures)
  if (n_boot > 0L) {
    for (b in seq_len(n_boot)) {
      idx <- sample.int(nrow(X), replace = TRUE)
      Xb <- X[idx, , drop = FALSE]
      yb <- yy[idx]
      if (length(unique(yb)) < 2L) next
      cvb <- tryCatch(
        glmnet::cv.glmnet(
          Xb, yb, family = "binomial", alpha = best$alpha, nfolds = min(5L, nfolds),
          penalty.factor = pf[colnames(X)]
        ),
        error = function(e) NULL
      )
      if (is.null(cvb)) next
      cb <- as.matrix(stats::coef(cvb, s = "lambda.min"))
      sb <- setdiff(rownames(cb)[abs(cb[, 1]) > 0], "(Intercept)")
      inc[sb] <- inc[sb] + 1L
    }
  }
  freq <- data.frame(
    exposure = exposures,
    inclusion_n = as.integer(inc[exposures]),
    inclusion_freq = as.numeric(inc[exposures]) / max(n_boot, 1L),
    selected_final = exposures %in% sel,
    coef = unname(beta[match(exposures, names(beta))]),
    stringsAsFactors = FALSE
  )
  freq <- freq[order(-freq$inclusion_freq, -freq$selected_final), ]

  list(
    alpha = best$alpha,
    lambda = as.numeric(cv2$lambda.min),
    selected = sel,
    beta = beta,
    freq = freq,
    n_model = nrow(dd),
    n_events = sum(yy == 1),
    gcdnet_used = gcdnet_used,
    n_boot = n_boot
  )
}

exwas_tox_score_ers <- function(df, beta, impute_median = TRUE) {
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
  # 加权关联：仅保留正权重 + PSU/层
  ww <- exwas_to_num(use[[weight_col]])
  use <- use[is.finite(ww) & ww > 0 &
               is.finite(exwas_to_num(use[[psu]])) &
               is.finite(exwas_to_num(use[[strata]])), , drop = FALSE]
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
