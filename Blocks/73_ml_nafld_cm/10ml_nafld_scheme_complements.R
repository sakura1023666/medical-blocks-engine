###############################################################################
#  方案缺口补齐：SHAP 单病例 / DeLong·H-L·Brier·PPV·NPV / 院内 FLI·LAP
#
#  由 ml_nafld_pub_finalize / omics_display source；不单独 register。
#  院内无实测腰围 → 用 NHANES Non-Hispanic Asian 拟合 WC~BMI+Age+Height（分性别），
#  再算 Bedogni FLI 与 Kahn LAP；表脚注必须写 est. WC。
###############################################################################

#' 从 NHANES 亚裔拟合腰围估计，写入院内数据框
.nafld_attach_fli_lap_est <- function(dat, cfg, logger = message) {
  if (is.null(dat) || !nrow(dat)) return(dat)
  if (all(c("FLI", "LAP") %in% names(dat)) &&
      mean(is.finite(dat$FLI), na.rm = TRUE) > 0.5 &&
      mean(is.finite(dat$LAP), na.rm = TRUE) > 0.5) {
    logger("FLI/LAP 已存在，跳过估计腰围")
    return(dat)
  }
  # 实测腰围优先
  wc_col <- intersect(c("Waist", "Waist_circumference", "WC", "腰围"), names(dat))
  if (length(wc_col)) {
    dat$Waist_cm <- suppressWarnings(as.numeric(dat[[wc_col[1L]]]))
    dat$Waist_source <- "measured"
  } else {
    dat$Waist_cm <- NA_real_
    dat$Waist_source <- "missing"
  }
  need_est <- !is.finite(dat$Waist_cm)
  if (any(need_est)) {
    fit <- .nafld_fit_wc_from_nhanes(cfg, logger = logger)
    if (!is.null(fit)) {
      gen <- as.character(dat$Gender)
      male <- grepl("^M|男", gen, ignore.case = TRUE)
      bmi <- suppressWarnings(as.numeric(dat$BMI))
      age <- suppressWarnings(as.numeric(dat$Age))
      ht <- suppressWarnings(as.numeric(dat$Height))
      wc_hat <- rep(NA_real_, nrow(dat))
      ok_m <- need_est & male & is.finite(bmi) & is.finite(age) & is.finite(ht)
      ok_f <- need_est & !male & is.finite(bmi) & is.finite(age) & is.finite(ht)
      if (sum(ok_m)) {
        wc_hat[ok_m] <- as.numeric(stats::predict(
          fit$male, newdata = data.frame(BMI = bmi[ok_m], Age = age[ok_m], Height = ht[ok_m])
        ))
      }
      if (sum(ok_f)) {
        wc_hat[ok_f] <- as.numeric(stats::predict(
          fit$female, newdata = data.frame(BMI = bmi[ok_f], Age = age[ok_f], Height = ht[ok_f])
        ))
      }
      dat$Waist_cm[need_est] <- wc_hat[need_est]
      dat$Waist_source[need_est & is.finite(wc_hat)] <- "NHANES_Asian_linear"
      attr(dat, "waist_est_fit") <- fit$meta
    }
  }
  tg <- suppressWarnings(as.numeric(dat$Triglycerides)) # mg/dL
  ggt <- suppressWarnings(as.numeric(dat$GGT))
  bmi <- suppressWarnings(as.numeric(dat$BMI))
  wc <- suppressWarnings(as.numeric(dat$Waist_cm))
  # Bedogni FLI（TG mg/dL, GGT U/L, BMI, WC cm）—— 必须用 base::log，勿被 logger 参数遮蔽
  L <- 0.953 * base::log(pmax(tg, 1e-6)) + 0.139 * bmi + 0.718 * base::log(pmax(ggt, 1e-6)) +
    0.053 * wc - 15.745
  dat$FLI <- 100 * exp(L) / (1 + exp(L))
  # Kahn LAP：引擎口径（TG mg/dL → /88.57 = mmol/L）
  gen <- as.character(dat$Gender)
  male <- grepl("^M|男", gen, ignore.case = TRUE)
  tg_mmol <- tg / 88.57
  dat$LAP <- ifelse(male, (wc - 65) * tg_mmol, (wc - 58) * tg_mmol)
  dat$LAP[!is.finite(dat$LAP) | dat$LAP < 0] <- NA_real_
  n_fli <- sum(is.finite(dat$FLI))
  n_lap <- sum(is.finite(dat$LAP))
  src <- paste(unique(dat$Waist_source[is.finite(dat$Waist_cm)]), collapse = "+")
  logger(sprintf("院内 FLI/LAP 已挂上：FLI n=%d, LAP n=%d, Waist_source=%s", n_fli, n_lap, src))
  dat
}

.nafld_fit_wc_from_nhanes <- function(cfg, logger = message) {
  roots <- unique(c(
    (cfg$external_bridge %||% list())$data_root,
    file.path(dirname((cfg$project %||% list())$output_dir %||% "."), "Custom/data"),
    "/mnt/g/02block_result/34_Fatty liver/Custom/data"
  ))
  rds <- NULL
  for (r in roots) {
    cand <- c(
      file.path(r, "NHANES", "D02_model_dataset_NHANES.RData"),
      file.path(r, "D02_model_dataset_NHANES.RData")
    )
    hit <- cand[file.exists(cand)]
    if (length(hit)) { rds <- hit[1L]; break }
  }
  if (is.null(rds)) {
    logger("未找到 NHANES D02，无法估计腰围 → 跳过院内 FLI/LAP")
    return(NULL)
  }
  e <- new.env(parent = emptyenv())
  load(rds, envir = e)
  ana <- e$ana
  if (is.null(ana)) {
    dfs <- ls(e)[vapply(ls(e), function(x) is.data.frame(e[[x]]), logical(1))]
    if (!length(dfs)) return(NULL)
    ana <- e[[dfs[1L]]]
  }
  race <- as.character(ana$Race %||% ana$RaceCode %||% "")
  keep <- grepl("Asian|亚洲", race, ignore.case = TRUE)
  if (sum(keep, na.rm = TRUE) < 80L) keep <- rep(TRUE, nrow(ana)) # 回退全样本
  d <- ana[keep, , drop = FALSE]
  wc <- suppressWarnings(as.numeric(d$WCRaw %||% d$Waist %||% d$Waist_circumference))
  bmi <- suppressWarnings(as.numeric(d$BMIRaw %||% d$BMI))
  age <- suppressWarnings(as.numeric(d$Age %||% d$AgeRaw))
  ht <- suppressWarnings(as.numeric(d$BMXHT %||% d$Height))
  gen <- as.character(d$Gender %||% d$Sex)
  male <- grepl("^M|男", gen, ignore.case = TRUE)
  ok <- is.finite(wc) & is.finite(bmi) & is.finite(age) & is.finite(ht)
  dfm <- data.frame(WC = wc, BMI = bmi, Age = age, Height = ht)[ok & male, , drop = FALSE]
  dff <- data.frame(WC = wc, BMI = bmi, Age = age, Height = ht)[ok & !male, , drop = FALSE]
  if (nrow(dfm) < 40L || nrow(dff) < 40L) {
    logger(sprintf("NHANES WC 拟合样本不足 male=%d female=%d", nrow(dfm), nrow(dff)))
    return(NULL)
  }
  fit_m <- stats::lm(WC ~ BMI + Age + Height, data = dfm)
  fit_f <- stats::lm(WC ~ BMI + Age + Height, data = dff)
  meta <- list(
    source = rds,
    subset = if (sum(grepl("Asian", race, ignore.case = TRUE), na.rm = TRUE) >= 80L)
      "Non-Hispanic Asian" else "all NHANES analytic",
    n_male = nrow(dfm), n_female = nrow(dff),
    r2_male = summary(fit_m)$r.squared,
    r2_female = summary(fit_f)$r.squared,
    formula = "WC_cm ~ BMI + Age + Height (sex-specific lm)"
  )
  logger(sprintf(
    "WC 估计方程：%s；male n=%d R2=%.3f；female n=%d R2=%.3f",
    meta$subset, meta$n_male, meta$r2_male, meta$n_female, meta$r2_female
  ))
  list(male = fit_m, female = fit_f, meta = meta)
}

#' Table 5.2：方案点名 DeLong / H-L / Brier / PPV / NPV（hold-out，CM+最优）
.nafld_write_scheme_metrics <- function(ctx, cfg, out_tables, best_algo = "LightGBM",
                                        scores = c("HSI", "ZJU", "TyG", "FLI", "LAP")) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    cli::cli_alert_warning("无 pROC，跳过 Table 5.2")
    return(invisible(NULL))
  }
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  split <- .nafld_cm_split_train_val(ctx, cfg)
  feats <- .nafld_cm_cm_features(ctx)
  if (is.null(split) || !length(feats)) return(invisible(NULL))

  # 挂 FLI/LAP（估腰围）到 split
  split$train <- .nafld_attach_fli_lap_est(split$train, cfg, logger = function(m, ...) cli::cli_alert_info(m))
  split$val   <- .nafld_attach_fli_lap_est(split$val, cfg, logger = function(m, ...) cli::cli_alert_info(m))
  # 同步回 ctx 便于 Table6
  if (!is.null(ctx$data$imputed)) {
    ctx$data$imputed <- .nafld_attach_fli_lap_est(ctx$data$imputed, cfg, logger = function(...) invisible())
  }

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  mm_tr <- .nafld_cm_model_matrix(split$train, feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(split$val, feats, oc, pos)
  feats <- intersect(intersect(feats, colnames(mm_tr$x)), colnames(mm_va$x))
  xtr <- mm_tr$x[, feats, drop = FALSE]
  xva <- mm_va$x[, feats, drop = FALSE]
  mu <- colMeans(xtr, na.rm = TRUE)
  sdv <- apply(xtr, 2, stats::sd, na.rm = TRUE)
  sdv[!is.finite(sdv) | sdv == 0] <- 1
  xtr_s <- scale(xtr, center = mu, scale = sdv)
  xva_s <- scale(xva, center = mu, scale = sdv)
  fp <- .nafld_cm_fit_pred(best_algo, xtr_s, mm_tr$y, xva_s, seed = 42L, cfg = cfg)
  if (!isTRUE(fp$ok)) return(invisible(NULL))
  ml_p <- as.numeric(fp$pred)
  y <- as.integer(mm_va$y)

  dval <- split$val
  cc <- stats::complete.cases(dval[, c(feats, oc), drop = FALSE])
  dval_cc <- dval[cc, , drop = FALSE]
  n_use <- min(nrow(dval_cc), length(y))
  y <- y[seq_len(n_use)]
  ml_p <- ml_p[seq_len(n_use)]
  dval_cc <- dval_cc[seq_len(n_use), , drop = FALSE]

  roc_ml <- pROC::roc(y, ml_p, quiet = TRUE, direction = "<")
  youden <- pROC::coords(roc_ml, "best", ret = c("threshold", "sensitivity", "specificity",
                                                 "ppv", "npv"),
                         best.method = "youden", transpose = FALSE)
  thr <- as.numeric(youden$threshold[1L])
  pred01 <- as.integer(ml_p >= thr)
  tp <- sum(pred01 == 1L & y == 1L); tn <- sum(pred01 == 0L & y == 0L)
  fp_n <- sum(pred01 == 1L & y == 0L); fn <- sum(pred01 == 0L & y == 1L)
  ppv <- if ((tp + fp_n) > 0) tp / (tp + fp_n) else NA_real_
  npv <- if ((tn + fn) > 0) tn / (tn + fn) else NA_real_
  brier <- mean((ml_p - y)^2)
  hl <- .nafld_hosmer_lemeshow(y, ml_p, g = 10L)

  rows <- list(data.frame(
    Model = paste0("CM+", best_algo),
    Comparator = "—",
    AUC = sprintf("%.3f", as.numeric(pROC::auc(roc_ml))),
    DeLong_P = "—",
    Brier = sprintf("%.4f", brier),
    Hosmer_Lemeshow_P = {
      if (!is.finite(hl$p)) "NA"
      else if (hl$p < 0.001) "<0.001"
      else sprintf("%.3f", hl$p)
    },
    HL_chi2_df = sprintf("%.2f (%d)", hl$chi2, hl$df),
    Sensitivity = sprintf("%.3f", as.numeric(youden$sensitivity[1L])),
    Specificity = sprintf("%.3f", as.numeric(youden$specificity[1L])),
    PPV = sprintf("%.3f", ppv),
    NPV = sprintf("%.3f", npv),
    Youden_threshold = sprintf("%.3f", thr),
    n = n_use,
    stringsAsFactors = FALSE
  ))

  scores <- intersect(scores, names(dval_cc))
  y_tr <- .nafld_cm_outcome01(split$train[[oc]], pos)
  for (sc in scores) {
    tr_sc <- suppressWarnings(as.numeric(split$train[[sc]]))
    ok <- is.finite(tr_sc) & is.finite(y_tr)
    fit <- tryCatch(
      stats::glm(y ~ s, data = data.frame(y = y_tr[ok], s = tr_sc[ok]), family = binomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    va_s <- suppressWarnings(as.numeric(dval_cc[[sc]]))
    okv <- is.finite(va_s) & is.finite(ml_p) & is.finite(y)
    if (sum(okv) < 30L) next
    pr <- as.numeric(stats::predict(fit, newdata = data.frame(s = va_s[okv]), type = "response"))
    roc_sc <- pROC::roc(y[okv], pr, quiet = TRUE, direction = "<")
    roc_ml_sub <- pROC::roc(y[okv], ml_p[okv], quiet = TRUE, direction = "<")
    dl <- tryCatch(
      pROC::roc.test(roc_ml_sub, roc_sc, method = "delong"),
      error = function(e) NULL
    )
    p_dl <- if (!is.null(dl)) as.numeric(dl$p.value) else NA_real_
    p_dl_s <- if (!is.finite(p_dl)) "NA" else if (p_dl < 0.001) "<0.001" else sprintf("%.3f", p_dl)
    m_sc <- .nafld_cm_youden_metrics(y[okv], pr)
    pred_sc <- as.integer(pr >= m_sc$thr)
    tp2 <- sum(pred_sc == 1L & y[okv] == 1L); tn2 <- sum(pred_sc == 0L & y[okv] == 0L)
    fp2 <- sum(pred_sc == 1L & y[okv] == 0L); fn2 <- sum(pred_sc == 0L & y[okv] == 1L)
    ppv2 <- if ((tp2 + fp2) > 0) tp2 / (tp2 + fp2) else NA_real_
    npv2 <- if ((tn2 + fn2) > 0) tn2 / (tn2 + fn2) else NA_real_
    rows[[length(rows) + 1L]] <- data.frame(
      Model = sc,
      Comparator = paste0("DeLong vs CM+", best_algo),
      AUC = sprintf("%.3f", m_sc$auc),
      DeLong_P = p_dl_s,
      Brier = sprintf("%.4f", mean((pr - y[okv])^2)),
      Hosmer_Lemeshow_P = "—",
      HL_chi2_df = "—",
      Sensitivity = sprintf("%.3f", m_sc$sens),
      Specificity = sprintf("%.3f", m_sc$spec),
      PPV = sprintf("%.3f", ppv2),
      NPV = sprintf("%.3f", npv2),
      Youden_threshold = sprintf("%.3f", m_sc$thr),
      n = sum(okv),
      stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, rows)
  waist_note <- {
    src <- unique(as.character(dval_cc$Waist_source %||% "unknown"))
    if (any(grepl("NHANES_Asian", src))) {
      "Hospital FLI/LAP use waist estimated from sex-specific NHANES Non-Hispanic Asian lm(WC~BMI+Age+Height); not measured WC."
    } else if (any(src == "measured")) {
      "Hospital FLI/LAP use measured waist circumference."
    } else {
      "Hospital waist source mixed/unknown; see Waist_source column in audit CSV."
    }
  }
  sci_xlsx_single_header_booktabs(
    file.path(out_tables, "Table 5.2 Scheme metrics DeLong HL Brier PPV NPV.xlsx"),
    sprintf("Table 5.2. Scheme-named metrics (DeLong, Hosmer-Lemeshow, Brier, PPV, NPV) — CM+%s hold-out", best_algo),
    tab,
    footnotes = c(
      "Primary ML row: hold-out probabilities from CM consensus features; Youden threshold on the same set.",
      "DeLong P compares each traditional-score risk (train-fitted logistic) with CM+ML on paired hold-out subjects.",
      "Hosmer-Lemeshow: 10-group chi-square on CM+ML only (P>0.05 suggests adequate calibration).",
      "Brier score = mean((p-y)^2); lower is better.",
      waist_note,
      "FLI = Bedogni 2006; LAP = Kahn sex-specific (WC-65 men / WC-58 women) × TG(mmol/L)."
    )
  )
  utils::write.csv(tab, file.path(out_tables, "Table 5.2 Scheme metrics DeLong HL Brier PPV NPV.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  # 腰围估计审计
  audit <- data.frame(
    ID = dval_cc$ID %||% seq_len(nrow(dval_cc)),
    Waist_cm = dval_cc$Waist_cm %||% NA_real_,
    Waist_source = dval_cc$Waist_source %||% NA_character_,
    FLI = dval_cc$FLI %||% NA_real_,
    LAP = dval_cc$LAP %||% NA_real_,
    stringsAsFactors = FALSE
  )
  utils::write.csv(audit, file.path(out_tables, "Audit_hospital_FLI_LAP_estWC_holdout.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(tab = tab, split = split, ml_p = ml_p, y = y, thr = thr, algo = best_algo))
}

.nafld_hosmer_lemeshow <- function(y, p, g = 10L) {
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  if (length(y) < 40L || length(unique(y)) < 2L) {
    return(list(chi2 = NA_real_, df = NA_integer_, p = NA_real_))
  }
  qs <- unique(stats::quantile(p, probs = seq(0, 1, length.out = g + 1L), na.rm = TRUE))
  if (length(qs) < 3L) return(list(chi2 = NA_real_, df = NA_integer_, p = NA_real_))
  grp <- cut(p, breaks = qs, include.lowest = TRUE)
  obs <- as.numeric(tapply(y, grp, sum))
  exp <- as.numeric(tapply(p, grp, sum))
  n <- as.numeric(tapply(y, grp, length))
  keep <- is.finite(obs) & is.finite(exp) & is.finite(n) & n > 0 & exp > 0 & (n - exp) > 0
  if (sum(keep) < 3L) return(list(chi2 = NA_real_, df = NA_integer_, p = NA_real_))
  chi2 <- sum((obs[keep] - exp[keep])^2 / (exp[keep] * (1 - exp[keep] / n[keep])))
  df <- sum(keep) - 2L
  if (df < 1L) return(list(chi2 = chi2, df = df, p = NA_real_))
  list(chi2 = chi2, df = df, p = stats::pchisq(chi2, df, lower.tail = FALSE))
}

#' 扩展 SHAP：dependence（S4）+ 低/中/高风险 waterfall（S5）
.nafld_plot_shap_extended <- function(ctx, cfg, fig_dir, supp_fig, algo = "LightGBM") {
  if (!requireNamespace("lightgbm", quietly = TRUE) || !requireNamespace("shapviz", quietly = TRUE)) {
    return(invisible(FALSE))
  }
  split <- .nafld_cm_split_train_val(ctx, cfg)
  feats <- .nafld_cm_cm_features(ctx)
  if (is.null(split) || !length(feats)) return(invisible(FALSE))
  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  mm_tr <- .nafld_cm_model_matrix(split$train, feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(split$val, feats, oc, pos)
  feats <- intersect(intersect(feats, colnames(mm_tr$x)), colnames(mm_va$x))
  xtr <- mm_tr$x[, feats, drop = FALSE]
  xva <- mm_va$x[, feats, drop = FALSE]
  dtr <- lightgbm::lgb.Dataset(data = as.matrix(xtr), label = mm_tr$y)
  fit <- lightgbm::lgb.train(
    params = list(objective = "binary", metric = "auc", num_leaves = 15L,
                  learning_rate = 0.05, verbosity = -1L, num_threads = 1L),
    data = dtr, nrounds = 120L, verbose = -1L
  )
  sv <- tryCatch(
    shapviz::shapviz(fit, X_pred = as.matrix(xva), X = as.data.frame(xva)),
    error = function(e) NULL
  )
  if (is.null(sv)) return(invisible(FALSE))

  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(supp_fig, recursive = TRUE, showWarnings = FALSE)

  # ── S4 dependence：|mean SHAP| top 6 ──
  imp <- colMeans(abs(sv$S))
  top <- names(sort(imp, decreasing = TRUE))[seq_len(min(6L, length(imp)))]
  ok_dep <- tryCatch({
    plots <- lapply(top, function(v) {
      shapviz::sv_dependence(sv, v) +
        ggplot2::labs(title = v) +
        ggplot2::theme_classic(base_size = 9, base_family = "serif") +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 9))
    })
    outf <- file.path(supp_fig, "Figure S4. SHAP dependence top features.pdf")
    grDevices::pdf(outf, width = 10.5, height = 7.2, useDingbats = FALSE)
    if (requireNamespace("patchwork", quietly = TRUE)) {
      print(Reduce(`+`, plots) + patchwork::plot_layout(ncol = 3))
    } else if (requireNamespace("gridExtra", quietly = TRUE)) {
      do.call(gridExtra::grid.arrange, c(plots, list(ncol = 3)))
    } else {
      for (p in plots) print(p)
    }
    grDevices::dev.off()
    file.copy(outf, file.path(fig_dir, basename(outf)), overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("SHAP dependence: {conditionMessage(e)}")
    FALSE
  })

  # ── S5 waterfall：按预测概率选低/中/高各 1 例 ──
  pred <- as.numeric(stats::predict(fit, as.matrix(xva)))
  # lightgbm binary predict 可能是 margin；用概率
  if (max(pred, na.rm = TRUE) > 1.01 || min(pred, na.rm = TRUE) < -0.01) {
    pred <- 1 / (1 + exp(-pred))
  }
  qs <- stats::quantile(pred, probs = c(1 / 6, 0.5, 5 / 6), na.rm = TRUE)
  pick_one <- function(target) {
    which.min(abs(pred - target))
  }
  idx <- c(
    Low = pick_one(qs[1L]),
    Moderate = pick_one(qs[2L]),
    High = pick_one(qs[3L])
  )
  ok_wf <- tryCatch({
    outf <- file.path(supp_fig, "Figure S5. SHAP waterfall low mid high cases.pdf")
    grDevices::pdf(outf, width = 11, height = 9.5, useDingbats = FALSE)
    if (requireNamespace("patchwork", quietly = TRUE)) {
      plist <- lapply(names(idx), function(lab) {
        i <- idx[[lab]]
        shapviz::sv_waterfall(sv, row_id = i, max_display = 12L) +
          ggplot2::labs(title = sprintf(
            "%s risk case (p=%.3f, y=%s)", lab, pred[i],
            c("Normal", "NAFLD")[mm_va$y[i] + 1L]
          )) +
          ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 10, family = "serif"))
      })
      print(plist[[1]] / plist[[2]] / plist[[3]])
    } else {
      for (lab in names(idx)) {
        i <- idx[[lab]]
        print(shapviz::sv_waterfall(sv, row_id = i, max_display = 12L) +
                ggplot2::labs(title = sprintf("%s (p=%.3f)", lab, pred[i])))
      }
    }
    grDevices::dev.off()
    # force plot 同三例 → S6（连续编号，禁止 S5.1）
    outf2 <- file.path(supp_fig, "Figure S6. SHAP force low mid high cases.pdf")
    unlink(file.path(supp_fig, "Figure S5.1 SHAP force low mid high cases.pdf"))
    unlink(file.path(fig_dir, "Figure S5.1 SHAP force low mid high cases.pdf"))
    grDevices::pdf(outf2, width = 11, height = 8.5, useDingbats = FALSE)
    for (lab in names(idx)) {
      i <- idx[[lab]]
      if (isTRUE(exists("sv_force", where = asNamespace("shapviz"), mode = "function"))) {
        print(shapviz::sv_force(sv, row_id = i) +
                ggplot2::labs(title = sprintf("%s risk (p=%.3f)", lab, pred[i])))
      } else {
        # shapviz 新版用 sv_waterfall 风格 force；退回 waterfall 标注 force
        print(shapviz::sv_waterfall(sv, row_id = i, max_display = 10L) +
                ggplot2::labs(title = sprintf("Force-style waterfall — %s (p=%.3f)", lab, pred[i])))
      }
    }
    grDevices::dev.off()
    file.copy(outf, file.path(fig_dir, basename(outf)), overwrite = TRUE)
    file.copy(outf2, file.path(fig_dir, basename(outf2)), overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("SHAP waterfall/force: {conditionMessage(e)}")
    FALSE
  })

  invisible(isTRUE(ok_dep) || isTRUE(ok_wf))
}
