#!/usr/bin/env Rscript
###############################################################################
# R/pub_reference_lit_tables.R
# 发表级「文献 wide 版式」表构建内核（全项目复用）
#
# 沉淀自 17_AKI / SOSM+WPR 等双库预后 ML 的审稿返工：
#   Table2 联合分组 Cox（Overall + SOFA 层，M1/M2/M3 三栏）
#   S4  单指标三分位 Cox（T1-T3 + P for trend）
#   S5  判别力 AUC/95%CI/DeLong（vs 联合参考）
#   S6-S8 各 SOFA 层 PH（cox.zph Variable|P）
#   S9/S10 敏感性 wide（排除 Glucose<70 / complete-case）
#   S2  单因素 Cox、S3 GVIF（含 Diabetes/T1DM/T2DM 别名保护）
#   S11 分层五模型性能宽表重塑（train / internal / external）
#
# 依赖引擎 utils.R / ml_assoc_covariate_rule.R / ml_stratified_ctx.R /
#   prognosis_reference_assoc.R / ml_reference_assoc_figures.R。
# 通用 wide 表逻辑集中在此，课题脚本只做「取 config + 落盘」的薄驱动。
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.pub_lit_need <- function() {
  need <- c("pub_format_est", "pub_format_p_cell",
            "sci_xlsx_single_header_booktabs",
            "ref_assoc_sofa_layer", ".ref_assoc_layer_masks",
            ".ref_assoc_models", "reference_joint_tertile_groups",
            ".reference_numeric", ".reference_bt", "ml_resolve_assoc_covariates")
  miss <- need[!vapply(need, exists, logical(1), mode = "function")]
  if (length(miss)) {
    stop("pub_reference_lit_tables 依赖缺失（先 source 引擎 R/）：",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  suppressPackageStartupMessages(requireNamespace("survival", quietly = TRUE))
  invisible(TRUE)
}

# ---- 协变量方案注入（把 study config 的 literature_m123 写进 assoc ctx）----
#' @return 注入 scheme 后的 assoc_ctx（results$assoc_model1/2/3_factors 已刷新）
pub_lit_inject_assoc <- function(assoc_ctx, study_config, data_names = NULL) {
  .pub_lit_need()
  ac <- study_config$assoc_covariate %||% list()
  assoc_ctx$config$assoc_covariate <-
    modifyList(assoc_ctx$config$assoc_covariate %||% list(), ac)
  dn <- data_names %||% names(assoc_ctx$data$imputed)
  res <- ml_resolve_assoc_covariates(assoc_ctx, data_names = dn)
  assoc_ctx$results$assoc_model1_factors <- res$M1
  assoc_ctx$results$assoc_model2_factors <- res$M2
  assoc_ctx$results$assoc_model3_factors <- res$M3 %||% res$M2
  assoc_ctx$results$assoc_covariate_scheme <- ac$scheme %||% "literature_m123"
  assoc_ctx$results$assoc_covariate_note <- res$note
  attr(assoc_ctx, "pub_lit_resolve") <- res
  assoc_ctx
}

#' 用参考库（通常主库 MIMIC）的 M1/M2/M3 名单套到外验库 ctx（同口径）
pub_lit_share_assoc_models <- function(primary_ctx, secondary_ctx) {
  r <- primary_ctx$results
  secondary_ctx$results$assoc_model1_factors <- r$assoc_model1_factors
  secondary_ctx$results$assoc_model2_factors <- r$assoc_model2_factors
  secondary_ctx$results$assoc_model3_factors <- r$assoc_model3_factors
  secondary_ctx$results$assoc_covariate_scheme <- r$assoc_covariate_scheme
  secondary_ctx$results$tb1 <- r$tb1 %||% secondary_ctx$results$tb1
  secondary_ctx$results$vif_screen_pass <-
    r$vif_screen_pass %||% secondary_ctx$results$vif_screen_pass
  secondary_ctx
}

# ---- 数据准备：time/event/SOFA 层 ----
#' @param event_labels 判为事件(=1)的 fustatus 显示标签
pub_lit_prep <- function(data, time_col = "futime", event_col = "fustatus",
                         cutoff = c(4L, 10L),
                         event_labels = c("1", "AKI", "Yes", "Non-survivor",
                                          "non-survivor", "Dead", "dead")) {
  .pub_lit_need()
  d <- as.data.frame(data)
  lab <- as.character(d[[event_col]])
  num <- suppressWarnings(as.numeric(lab))
  d$.__ev <- as.integer(lab %in% event_labels |
                          (!is.na(num) & num == 1L))
  d$.__tm <- suppressWarnings(as.numeric(as.character(d[[time_col]])))
  d$SOFA_layer <- ref_assoc_sofa_layer(d, cutoff)
  d
}

#' 主库训练集冻结的「上三分位」联合切点（type-7，与主文 Table2 同源）
pub_lit_joint_cuts <- function(train, index_a, index_b) {
  .pub_lit_need()
  av <- .reference_numeric(train[[index_a]], index_a)
  bv <- .reference_numeric(train[[index_b]], index_b)
  list(a = unname(stats::quantile(av, 2 / 3, type = 7)),
       b = unname(stats::quantile(bv, 2 / 3, type = 7)))
}

# ---- 低血糖 / complete-case 敏感性过滤 ----
pub_lit_exclude_glucose <- function(dat, col = "Glucose", threshold = 70,
                                    na_keep = TRUE) {
  g <- suppressWarnings(as.numeric(as.character(dat[[col]])))
  drop <- is.finite(g) & g < threshold
  if (!isTRUE(na_keep)) drop <- drop | !is.finite(g)
  dat[!drop, , drop = FALSE]
}
pub_lit_complete_case <- function(dat, cols) {
  cols <- intersect(cols, names(dat))
  dat[stats::complete.cases(dat[, cols, drop = FALSE]), , drop = FALSE]
}

# ---- 内部 Cox 拟合小工具 --------------------------------------------------
.pub_blank7 <- function(lab) {
  data.frame(
    Variables = lab,
    `Model 1 HR (95% CI)` = "", `Model 1 P` = "",
    `Model 2 HR (95% CI)` = "", `Model 2 P` = "",
    `Model 3 HR (95% CI)` = "", `Model 3 P` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
.pub_cell7 <- function(lab, cells) {
  data.frame(
    Variables = lab,
    `Model 1 HR (95% CI)` = cells$Model1$hr, `Model 1 P` = cells$Model1$p,
    `Model 2 HR (95% CI)` = cells$Model2$hr, `Model 2 P` = cells$Model2$p,
    `Model 3 HR (95% CI)` = cells$Model3$hr, `Model 3 P` = cells$Model3$p,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
.pub_fmt_hr <- function(hr, lo, hi) {
  if (!is.finite(hr)) return("NE")
  if (isTRUE(tryCatch(pub_est_ci_not_estimable(hr, lo, hi),
                      error = function(e) FALSE))) return("NE")
  paste0(pub_format_est(hr), " (", pub_format_est(lo), "\u2013",
         pub_format_est(hi), ")")
}
.pub_coef_hit <- function(fit, pat) {
  if (is.null(fit)) return(list(hr = NA, lo = NA, hi = NA, p = NA))
  cn <- names(stats::coef(fit))
  hit <- which(grepl(pat, gsub("`", "", cn)))
  if (!length(hit)) return(list(hr = NA, lo = NA, hi = NA, p = NA))
  term <- names(stats::coef(fit))[hit[1]]
  b <- unname(stats::coef(fit)[term])
  ci <- tryCatch(stats::confint(fit)[term, ], error = function(e) c(NA, NA))
  sm <- summary(fit)$coefficients
  pv <- if (term %in% rownames(sm)) unname(sm[term, "Pr(>|z|)"]) else NA_real_
  list(hr = exp(b), lo = exp(ci[1]), hi = exp(ci[2]), p = pv)
}
#' 分组 Cox：group_col 为 factor 列；trend=TRUE 用有序 1..k
.pub_fit_group_cox <- function(dd, group_col, covs, group_levels = NULL,
                              trend = FALSE) {
  if (is.null(dd) || nrow(dd) < 20L) return(NULL)
  if (sum(dd$.__ev == 1L, na.rm = TRUE) < 5L) return(NULL)
  lv <- group_levels %||% levels(droplevels(dd[[group_col]]))
  dd$g <- factor(as.character(dd[[group_col]]), levels = lv)
  dd <- dd[!is.na(dd$g) & is.finite(dd$.__tm) & dd$.__tm > 0 &
             !is.na(dd$.__ev), , drop = FALSE]
  if (nrow(dd) < 20L || sum(dd$.__ev == 1L) < 5L ||
      nlevels(droplevels(dd$g)) < 2L) return(NULL)
  terms <- if (isTRUE(trend)) {
    dd$gnum <- as.integer(dd$g)
    if (length(unique(dd$gnum)) < 2L) return(NULL)
    c("gnum", covs)
  } else c("g", covs)
  fml <- stats::as.formula(
    sprintf("survival::Surv(.__tm, .__ev) ~ %s",
            paste(.reference_bt(terms), collapse = " + ")))
  tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
}

# ==========================================================================
# 1) 联合分组 Cox wide 表（Table2 / S9 / S10 同布局）
#    columns: Variables | Model 1/2/3 HR (95% CI) | P
# ==========================================================================
pub_lit_table_joint <- function(dat, index_a, index_b, cut_a, cut_b,
                                models, cutoff = c(4L, 10L),
                                outcome_label = NULL) {
  .pub_lit_need()
  d <- dat
  d$JointGroup <- reference_joint_tertile_groups(
    d[[index_a]], d[[index_b]], cut_a, cut_b)
  masks <- .ref_assoc_layer_masks(d, cutoff)
  gl <- c("Group1", "Group2", "Group3", "Group4")
  parts <- list(.pub_blank7(outcome_label %||% "Outcome"))
  for (ly in names(masks)) {
    parts[[length(parts) + 1L]] <- .pub_blank7(
      if (identical(ly, "Overall")) "Overall" else ly)
    dd <- d[masks[[ly]], , drop = FALSE]
    fits <- lapply(c("Model1", "Model2", "Model3"),
                   function(m) .pub_fit_group_cox(dd, "JointGroup",
                                                  models[[m]], gl, FALSE))
    names(fits) <- c("Model1", "Model2", "Model3")
    trends <- lapply(c("Model1", "Model2", "Model3"),
                     function(m) .pub_fit_group_cox(dd, "JointGroup",
                                                    models[[m]], gl, TRUE))
    names(trends) <- c("Model1", "Model2", "Model3")
    for (g in gl) {
      cells <- list()
      for (m in names(fits)) {
        if (identical(g, "Group1")) {
          cells[[m]] <- list(hr = "1.00 (Reference)", p = "")
        } else {
          co <- .pub_coef_hit(fits[[m]], paste0("g", g, "$"))
          cells[[m]] <- list(hr = .pub_fmt_hr(co$hr, co$lo, co$hi),
                             p = if (is.finite(co$p)) pub_format_p_cell(co$p) else "")
        }
      }
      parts[[length(parts) + 1L]] <- .pub_cell7(g, cells)
    }
    tc <- list()
    for (m in names(trends)) {
      co <- .pub_coef_hit(trends[[m]], "gnum")
      tc[[m]] <- list(hr = .pub_fmt_hr(co$hr, co$lo, co$hi),
                      p = if (is.finite(co$p)) pub_format_p_cell(co$p) else "")
    }
    parts[[length(parts) + 1L]] <- .pub_cell7("P for trend", tc)
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

# ==========================================================================
# 2) 单指标三分位 Cox wide 表（S4：每指标 T1-T3 + P for trend，各层）
# ==========================================================================
pub_lit_table_index_tertile <- function(dat, indices, models,
                                        cutoff = c(4L, 10L),
                                        outcome_label = NULL) {
  .pub_lit_need()
  masks <- .ref_assoc_layer_masks(dat, cutoff)
  build <- function(dd, index) {
    out <- .pub_blank7(index)
    fits <- lapply(c("Model1", "Model2", "Model3"),
                   function(m) .pub_fit_tert(dd, index, models[[m]], FALSE))
    names(fits) <- c("Model1", "Model2", "Model3")
    trends <- lapply(c("Model1", "Model2", "Model3"),
                     function(m) .pub_fit_tert(dd, index, models[[m]], TRUE))
    names(trends) <- c("Model1", "Model2", "Model3")
    for (tlev in c("T1", "T2", "T3")) {
      cells <- list()
      for (m in names(fits)) {
        if (identical(tlev, "T1")) {
          cells[[m]] <- list(hr = "1.00 (Reference)", p = "")
        } else {
          co <- .pub_coef_hit(fits[[m]], paste0("g?", tlev, "$"))
          if (!is.finite(co$hr)) co <- .pub_coef_hit(fits[[m]], paste0("g", tlev))
          cells[[m]] <- list(hr = .pub_fmt_hr(co$hr, co$lo, co$hi),
                             p = if (is.finite(co$p)) pub_format_p_cell(co$p) else "")
        }
      }
      out <- rbind(out, .pub_cell7(tlev, cells))
    }
    tc <- list()
    for (m in names(trends)) {
      co <- .pub_coef_hit(trends[[m]], "gnum")
      tc[[m]] <- list(hr = .pub_fmt_hr(co$hr, co$lo, co$hi),
                      p = if (is.finite(co$p)) pub_format_p_cell(co$p) else "")
    }
    rbind(out, .pub_cell7("P for trend", tc))
  }
  parts <- list(.pub_blank7(outcome_label %||% "Outcome"))
  for (ly in names(masks)) {
    parts[[length(parts) + 1L]] <- .pub_blank7(
      if (identical(ly, "Overall")) "Overall" else ly)
    dd <- dat[masks[[ly]], , drop = FALSE]
    for (index in indices) parts[[length(parts) + 1L]] <- build(dd, index)
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}
.pub_fit_tert <- function(dd, index, covs, trend) {
  x <- suppressWarnings(as.numeric(as.character(dd[[index]])))
  ok <- is.finite(x) & is.finite(dd$.__tm) & !is.na(dd$.__ev) & dd$.__tm > 0
  dd <- dd[ok, , drop = FALSE]; x <- x[ok]
  if (nrow(dd) < 40L || sum(dd$.__ev == 1L) < 5L) return(NULL)
  cuts <- as.numeric(stats::quantile(x, c(1 / 3, 2 / 3), type = 7))
  if (length(unique(cuts)) < 2L) return(NULL)
  g <- cut(x, breaks = c(-Inf, cuts[1], cuts[2], Inf),
           labels = c("T1", "T2", "T3"), right = TRUE, include.lowest = TRUE)
  dd$g <- factor(as.character(g), levels = c("T1", "T2", "T3"))
  if (isTRUE(trend)) {
    dd$gnum <- as.integer(dd$g)
    terms <- c("gnum", covs)
  } else terms <- c("g", covs)
  fml <- stats::as.formula(
    sprintf("survival::Surv(.__tm, .__ev) ~ %s",
            paste(.reference_bt(terms), collapse = " + ")))
  tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
}

# ==========================================================================
# 3) 各 SOFA 层 PH 表（S6/S7/S8：Variable | P，cox.zph on 全 Model3+暴露）
# ==========================================================================
pub_lit_table_ph_layer <- function(dat, index_a, index_b, models,
                                   layer_label, cutoff = c(4L, 10L),
                                   alias = NULL) {
  .pub_lit_need()
  masks <- .ref_assoc_layer_masks(dat, cutoff)
  if (!layer_label %in% names(masks)) {
    stop("未知层：", layer_label, " 可用：", paste(names(masks), collapse = ", "),
         call. = FALSE)
  }
  covs <- unique(c(index_a, index_b, models$Model3))
  need <- unique(c(".__tm", ".__ev", covs))
  need <- need[need %in% names(dat)]
  dd <- dat[masks[[layer_label]], need, drop = FALSE]
  for (v in setdiff(need, c(".__tm", ".__ev"))) {
    if (is.character(dd[[v]]) || is.factor(dd[[v]])) {
      if (!is.factor(dd[[v]])) dd[[v]] <- factor(dd[[v]])
    } else dd[[v]] <- suppressWarnings(as.numeric(as.character(dd[[v]])))
  }
  dd <- dd[stats::complete.cases(dd) & dd$.__tm > 0, , drop = FALSE]
  rv <- setdiff(names(dd), c(".__tm", ".__ev"))
  fit <- survival::coxph(
    stats::as.formula(sprintf("survival::Surv(.__tm, .__ev) ~ %s",
                              paste(sprintf("`%s`", rv), collapse = " + "))),
    data = dd, x = TRUE)
  zph <- survival::cox.zph(fit)
  tn <- rownames(zph$table); pv <- zph$table[, "p"]
  disp <- gsub("^`|`$", "", tn)
  if (!is.null(alias)) for (k in names(alias)) disp[disp == k] <- alias[[k]]
  data.frame(
    `Variable Name` = disp,
    P = vapply(pv, function(p) if (is.finite(p)) pub_format_p_cell(p) else "",
               character(1)),
    check.names = FALSE, stringsAsFactors = FALSE)
}

# ==========================================================================
# 4) 判别力 wide 表（S5：AUC(95%CI) | Sens | Spec | DeLong P vs 参考）
# ==========================================================================
pub_lit_table_discrimination <- function(dat, predictors, reference,
                                         cutoff = c(4L, 10L),
                                         outcome_label = "28-day mortality",
                                         lower_risk = NULL) {
  .pub_lit_need()
  if (!requireNamespace("pROC", quietly = TRUE))
    stop("S5 需要 pROC 包", call. = FALSE)
  masks <- .ref_assoc_layer_masks(dat, cutoff)
  blank <- function(lab) data.frame(
    Models = lab, `AUC(95% CI)` = "", Sensitivity = "", Specificity = "",
    P = "", check.names = FALSE, stringsAsFactors = FALSE)
  metrics <- function(y, s) {
    ok <- is.finite(s) & !is.na(y); y <- y[ok]; s <- s[ok]
    if (length(unique(y)) < 2L || length(s) < 20L)
      return(list(auc = NA, lo = NA, hi = NA, sens = NA, spec = NA))
    roc <- suppressWarnings(pROC::roc(y, s, quiet = TRUE, direction = "<"))
    auc <- as.numeric(pROC::auc(roc))
    ci <- tryCatch(as.numeric(pROC::ci.auc(roc)), error = function(e) c(NA, NA, NA))
    co <- tryCatch(pROC::coords(roc, "best",
             ret = c("sensitivity", "specificity"), best.method = "youden",
             transpose = FALSE), error = function(e) NULL)
    list(auc = auc, lo = ci[1], hi = ci[3],
         sens = if (!is.null(co)) as.numeric(co[["sensitivity"]][1]) else NA,
         spec = if (!is.null(co)) as.numeric(co[["specificity"]][1]) else NA)
  }
  delong <- function(y, s_ref, s_new) {
    ok <- is.finite(s_ref) & is.finite(s_new) & !is.na(y)
    if (sum(ok) < 30L || length(unique(y[ok])) < 2L) return(NA_real_)
    tryCatch({
      r1 <- suppressWarnings(pROC::roc(y[ok], s_ref[ok], quiet = TRUE, direction = "<"))
      r2 <- suppressWarnings(pROC::roc(y[ok], s_new[ok], quiet = TRUE, direction = "<"))
      as.numeric(pROC::roc.test(r1, r2, method = "delong")$p.value)
    }, error = function(e) NA_real_)
  }
  orient <- function(nm, v) if (nm %in% (lower_risk %||% character(0))) -v else v
  rows <- list(blank(outcome_label))
  for (ly in names(masks)) {
    rows[[length(rows) + 1L]] <- blank(if (identical(ly, "Overall")) "Overall" else ly)
    dd <- dat[masks[[ly]], , drop = FALSE]
    y <- dd$.__ev
    preds <- lapply(predictors, function(f) f(dd))
    names(preds) <- names(predictors)
    o <- lapply(names(preds), function(nm) orient(nm, suppressWarnings(as.numeric(preds[[nm]]))))
    names(o) <- names(preds)
    ref_s <- o[[reference]]
    for (nm in names(preds)) {
      m <- metrics(y, o[[nm]])
      auc_ci <- if (is.finite(m$auc))
        paste0(pub_format_est(m$auc), " (", pub_format_est(m$lo), "\u2013",
               pub_format_est(m$hi), ")") else "NE"
      pv <- if (identical(nm, reference)) "1.00 (Reference)" else
        { dp <- delong(y, ref_s, o[[nm]]); if (is.finite(dp)) pub_format_p_cell(dp) else "" }
      rows[[length(rows) + 1L]] <- data.frame(
        Models = nm, `AUC(95% CI)` = auc_ci,
        Sensitivity = if (is.finite(m$sens)) pub_format_est(m$sens) else "",
        Specificity = if (is.finite(m$spec)) pub_format_est(m$spec) else "",
        P = pv, check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL; out
}

# ==========================================================================
# 5) 单因素 Cox（S2）+ GVIF（S3，含别名保护）
# ==========================================================================
#' 单因素 Cox（S2 文献版式，忠实移植 AKAG 定稿构建逻辑）
#' 列 = Characteristics | Number(%) | Hazard Ratio(HR) | 95% CI Lower | 95% CI Upper | P
#' @param spec list of list(label, col（可为候选向量）, type=continuous|categorical)
#'   —— 顺序/标签对齐 Table1；缺省 NULL 时取 data 列名自动全列（不推荐）
pub_lit_table_uni_cox <- function(dat, spec) {
  .pub_lit_need()
  resolve_col <- function(cands, nm) {
    cands <- as.character(cands)
    hit <- cands[cands %in% nm][1]
    if (!is.na(hit) && nzchar(hit)) return(hit)
    for (c in cands) {
      h <- nm[tolower(gsub("[^A-Za-z0-9]", "", nm)) ==
                tolower(gsub("[^A-Za-z0-9]", "", c))]
      if (length(h)) return(h[1])
    }
    NA_character_
  }
  fmt_mean_sd <- function(x) {
    x <- suppressWarnings(as.numeric(as.character(x))); x <- x[is.finite(x)]
    if (!length(x)) return("")
    sprintf("%s (%s)", pub_format_est(mean(x)), pub_format_est(stats::sd(x)))
  }
  fmt_n_pct <- function(n, N)
    sprintf("%s (%s)", format(n, big.mark = ","), pub_format_est(100 * n / N))
  cox_one <- function(d, col, type) {
    dd <- d[is.finite(d$.__tm) & !is.na(d$.__ev) & !is.na(d[[col]]), , drop = FALSE]
    if (nrow(dd) < 30L || sum(dd$.__ev == 1L) < 5L)
      return(list(hr = NA, lo = NA, hi = NA, p = NA))
    if (identical(type, "continuous")) {
      dd$.x <- suppressWarnings(as.numeric(as.character(dd[[col]])))
      dd <- dd[is.finite(dd$.x), , drop = FALSE]
    } else {
      dd$.x <- factor(as.character(dd[[col]]))
      if (nlevels(droplevels(dd$.x)) < 2L)
        return(list(hr = NA, lo = NA, hi = NA, p = NA))
    }
    fit <- tryCatch(survival::coxph(survival::Surv(.__tm, .__ev) ~ .x, data = dd),
                    error = function(e) NULL)
    if (is.null(fit)) return(list(hr = NA, lo = NA, hi = NA, p = NA))
    sm <- summary(fit); cf <- sm$coefficients
    ci <- tryCatch(exp(stats::confint(fit)), error = function(e) NULL)
    list(fit = fit, coef = cf, ci = ci,
         levels = if (identical(type, "categorical")) levels(dd$.x) else NULL)
  }
  blank_row <- function(name) data.frame(
    Characteristics = name, `Number(%)` = "", `Hazard Ratio(HR)` = "",
    `95% CI Lower` = "", `95% CI Upper` = "", P = "",
    check.names = FALSE, stringsAsFactors = FALSE)
  cell_row <- function(name, num, hr, lo, hi, p) data.frame(
    Characteristics = name, `Number(%)` = num %||% "",
    `Hazard Ratio(HR)` = if (is.finite(hr)) pub_format_est(hr) else "",
    `95% CI Lower` = if (is.finite(lo)) pub_format_est(lo) else "",
    `95% CI Upper` = if (is.finite(hi)) pub_format_est(hi) else "",
    P = if (is.finite(p)) pub_format_p_cell(p) else "",
    check.names = FALSE, stringsAsFactors = FALSE)

  if (is.null(spec)) {
    spec <- lapply(setdiff(names(dat), c("fustatus", "futime", ".__ev", ".__tm",
                                         "SOFA_layer")),
                   function(v) list(label = v, col = v,
                     type = if (is.numeric(dat[[v]])) "continuous" else "categorical"))
  }
  rows <- list(); N <- nrow(dat)
  for (sp in spec) {
    col <- resolve_col(sp$col, names(dat))
    if (is.na(col)) { message("skip missing: ", sp$label); next }
    if (identical(sp$type, "continuous")) {
      co <- cox_one(dat, col, "continuous")
      hr <- lo <- hi <- p <- NA_real_
      if (!is.null(co$coef) && nrow(co$coef) >= 1L) {
        hr <- exp(co$coef[1, "coef"]); p <- co$coef[1, "Pr(>|z|)"]
        if (!is.null(co$ci)) { lo <- co$ci[1, 1]; hi <- co$ci[1, 2] }
      }
      rows[[length(rows) + 1L]] <- cell_row(sp$label, fmt_mean_sd(dat[[col]]),
                                            hr, lo, hi, p)
    } else {
      x <- factor(as.character(dat[[col]]))
      if (all(c("No", "Yes") %in% levels(x)))
        x <- factor(x, levels = c("No", "Yes"))
      if (identical(col, "Gender") && all(c("Female", "Male") %in% levels(x)))
        x <- factor(as.character(dat[[col]]), levels = c("Female", "Male"))
      lv <- levels(droplevels(x))
      if (!length(lv)) next
      rows[[length(rows) + 1L]] <- blank_row(sp$label)
      co <- cox_one(dat, col, "categorical")
      for (i in seq_along(lv)) {
        lev <- lv[i]
        n_i <- sum(as.character(x) == lev, na.rm = TRUE)
        num <- fmt_n_pct(n_i, sum(!is.na(x)))
        if (i == 1L) {
          rows[[length(rows) + 1L]] <- cell_row(lev, num, NA, NA, NA, NA)
          next
        }
        hr <- lo <- hi <- p <- NA_real_
        if (!is.null(co$coef)) {
          rn <- gsub("^\\.x", "", rownames(co$coef))
          j <- which(rn == lev | grepl(paste0(lev, "$"), rownames(co$coef)))
          if (!length(j)) j <- i - 1L
          if (length(j) && j[1] <= nrow(co$coef)) {
            j <- j[1]
            hr <- exp(co$coef[j, "coef"]); p <- co$coef[j, "Pr(>|z|)"]
            if (!is.null(co$ci) && j <= nrow(co$ci)) { lo <- co$ci[j, 1]; hi <- co$ci[j, 2] }
          }
        }
        rows[[length(rows) + 1L]] <- cell_row(lev, num, hr, lo, hi, p)
      }
    }
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

#' GVIF 表（car::vif）；自动剔除会造成 alias 的共线子叶（如 Diabetes + T1DM/T2DM）
pub_lit_table_vif <- function(train, vif_vars, alias_groups = NULL,
                              label_map = NULL) {
  .pub_lit_need()
  if (!requireNamespace("car", quietly = TRUE)) stop("S3 需要 car 包", call. = FALSE)
  vif_vars <- intersect(vif_vars, names(train))
  vif_vars <- setdiff(vif_vars, c("fustatus", "futime", ".__ev", ".__tm"))
  # 别名保护：若某组同时入选，只留组内第一个（父类）
  for (g in (alias_groups %||% list())) {
    g <- intersect(g, vif_vars)
    if (length(g) > 1L) vif_vars <- setdiff(vif_vars, g[-1L])
  }
  dd <- train[, vif_vars, drop = FALSE]
  for (v in names(dd)) {
    if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
    if (is.factor(dd[[v]])) {
      if (all(c("No", "Yes") %in% levels(dd[[v]])))
        dd[[v]] <- factor(dd[[v]], levels = c("No", "Yes"))
    } else dd[[v]] <- suppressWarnings(as.numeric(as.character(dd[[v]])))
  }
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  # 逐列剔除导致 alias 的项，直到无 alias
  set.seed(42L)   # dummy y 固定种子 → GVIF 跨进程完全可复现
  repeat {
    cur <- setdiff(names(dd), ".__y")
    fml <- stats::as.formula(paste(".__y ~",
             paste(sprintf("`%s`", cur), collapse = " + ")))
    dd$.__y <- stats::rnorm(nrow(dd))
    fit <- stats::lm(fml, data = dd)
    al <- stats::na.action(fit$coefficients)
    if (is.null(al) || !length(al)) break
    drop_nm <- gsub("^`|`$", "", names(al))
    drop_nm <- intersect(drop_nm, names(dd))
    if (!length(drop_nm)) break
    dd[[drop_nm[1]]] <- NULL
  }
  cur <- setdiff(names(dd), ".__y")
  vif_mat <- car::vif(fit)
  if (is.matrix(vif_mat) || is.data.frame(vif_mat)) {
    nm <- rownames(vif_mat); gvif <- as.numeric(vif_mat[, 1])
    dfv <- as.numeric(vif_mat[, 2]); adj <- as.numeric(vif_mat[, 3])
  } else {
    nm <- names(vif_mat); gvif <- as.numeric(vif_mat)
    dfv <- rep(1, length(gvif)); adj <- sqrt(gvif)
  }
  nm <- gsub("^`|`$", "", nm)
  out <- data.frame(Variable = nm, GVIF = gvif, Df = dfv,
                    `GVIF^(1/(2*Df))` = adj,
                    check.names = FALSE, stringsAsFactors = FALSE)
  if (!is.null(label_map)) {
    disp <- ifelse(out$Variable %in% names(label_map),
                   unname(label_map[out$Variable]), out$Variable)
    out$Variable <- disp
  } else {
    # 发表显示别名（文献版式）
    alias_disp <- list(Heart_Failure = "Heart Failure",
                       Ventilation = "Mechanical ventilation")
    for (k in names(alias_disp))
      out$Variable[out$Variable == k] <- alias_disp[[k]]
  }
  out
}

# ==========================================================================
# 6) 分层五模型性能宽表重塑（S11：层 × 数据集块 × 模型 → AUC/Sens/Spec/Acc/F1）
# ==========================================================================
#' @param raw long frame：Stratum / Database / Dataset / Model / Metric / Estimate
#' @param blocks list of list(db, ds, lab) —— 每层内顺序展示的三块
pub_lit_reshape_ml_perf <- function(raw, strata, blocks,
                                    model_map, metric_map) {
  raw <- raw[!is.na(raw$Stratum) & raw$Stratum %in% strata, , drop = FALSE]
  raw <- raw[!is.na(raw$Model) & !is.na(raw$Metric) &
               !is.na(raw$Database) & !is.na(raw$Dataset), , drop = FALSE]
  for (k in c("Model", "Metric", "Dataset", "Database", "Stratum"))
    raw[[k]] <- tolower(trimws(as.character(raw[[k]])))
  want_metrics <- unname(metric_map)
  blank <- function(lab) {
    df <- data.frame(Models = lab, check.names = FALSE, stringsAsFactors = FALSE)
    for (m in want_metrics) df[[m]] <- ""
    df
  }
  parts <- list()
  for (st in strata) {
    parts[[length(parts) + 1L]] <- blank(st)
    for (b in blocks) {
      parts[[length(parts) + 1L]] <- blank(b$lab)
      sub <- raw[raw$Stratum == tolower(st) &
                   raw$Database == tolower(b$db) &
                   raw$Dataset == tolower(b$ds), , drop = FALSE]
      for (m_raw in names(model_map)) {
        m_lab <- unname(model_map[[m_raw]])
        cells <- setNames(rep("", length(want_metrics)), want_metrics)
        for (met_raw in names(metric_map)) {
          met_lab <- unname(metric_map[[met_raw]])
          hit <- sub[tolower(sub$Model) == m_raw &
                      tolower(sub$Metric) == met_raw, , drop = FALSE]
          if (nrow(hit)) {
            val <- suppressWarnings(as.numeric(hit$Estimate[1]))
            cells[[met_lab]] <- if (is.finite(val)) pub_format_est(val) else ""
          }
        }
        df <- data.frame(Models = m_lab, check.names = FALSE, stringsAsFactors = FALSE)
        for (m in want_metrics) df[[m]] <- cells[[m]]
        parts[[length(parts) + 1L]] <- df
      }
    }
  }
  out <- do.call(rbind, parts); rownames(out) <- NULL; out
}

# ==========================================================================
# 7) Figure S1 原文样式：plot.cox.zph β(t) 趋势（双库 A/B 一面）
#    Group = 联合三分位评分；Age+Gender 调整；KM 默认时间变换；粉色虚线 y=0
# ==========================================================================
#' @return list(path, mimic, eicu, resid_csv, summary_csv)
pub_lit_fig_ph_beta_trends_original <- function(
  mimic_ctx, eicu_ctx = NULL, index_a, index_b, out_pdf,
  train = NULL, cutoff = c(4L, 10L),
  covariates = c("Age", "Gender"), max_time = 28
) {
  .pub_lit_need()
  train <- train %||% mimic_ctx$data$train
  cuts <- pub_lit_joint_cuts(as.data.frame(train), index_a, index_b)
  fit_db <- function(ctx, db_lab) {
    d <- pub_lit_prep(ctx$data$imputed, cutoff = cutoff)
    jt <- reference_joint_tertile_groups(d[[index_a]], d[[index_b]],
                                         cuts$a, cuts$b)
    d$Group <- as.numeric(jt)
    covs <- intersect(covariates, names(d))
    need <- c(".__tm", ".__ev", "Group", covs)
    dd <- d[stats::complete.cases(d[, need, drop = FALSE]), , drop = FALSE]
    dd <- dd[is.finite(dd$.__tm) & dd$.__tm > 0 & dd$.__tm <= max_time, ,
             drop = FALSE]
    if (nrow(dd) < 50L || sum(dd$.__ev == 1L) < 10L)
      stop("样本不足，无法画 PH 趋势（", db_lab, "）", call. = FALSE)
    form <- stats::as.formula(sprintf("survival::Surv(.__tm, .__ev) ~ %s",
      paste(.reference_bt(c("Group", covs)), collapse = " + ")))
    fit <- survival::coxph(form, data = dd, x = TRUE, y = TRUE,
                           model = TRUE, ties = "efron")
    zph <- survival::cox.zph(fit)   # transform=km（默认）与原文刻度一致
    p_g <- tryCatch({
      tb <- as.data.frame(zph$table)
      as.numeric(tb[match("Group", rownames(tb)), "p"])
    }, error = function(e) NA_real_)
    list(fit = fit, zph = zph, n = nrow(dd), events = sum(dd$.__ev == 1L),
         p_group = p_g, database = db_lab, covs = covs)
  }
  mi_z <- fit_db(mimic_ctx, "MIMIC-IV")
  ei_z <- if (!is.null(eicu_ctx)) fit_db(eicu_ctx, "eICU") else NULL

  plot_one <- function(z, letter) {
    idx <- match("Group", colnames(z$zph$y)); if (is.na(idx)) idx <- 1L
    survival:::plot.cox.zph(
      z$zph, resid = TRUE, se = TRUE, df = 4, nsmo = 40, var = idx,
      xlab = "Time", ylab = "Beta(t) for Group",
      main = sprintf("%s  %s\nCOX Regression PH Test Trend Plot_Group",
                     letter, z$database),
      col = 1, lwd = 1, lty = 1:2, pch = 1, cex = 0.45, hr = FALSE)
    graphics::abline(h = 0, col = "pink", lty = 2, lwd = 1.5)
    graphics::mtext(sprintf("Schoenfeld P (Group) = %s",
      if (is.finite(z$p_group))
        format.pval(z$p_group, digits = 3, eps = 1e-3) else "NE"),
      side = 1, line = 3.2, cex = 0.7, adj = 0)
  }
  dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(out_pdf, width = 11.2, height = 5.6, onefile = TRUE)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(1, 2), mar = c(5.2, 4.2, 3.8, 1.2),
                oma = c(2.8, 0.2, 0.2, 0.2))
  plot_one(mi_z, "A")
  if (is.null(ei_z)) graphics::plot.new() else plot_one(ei_z, "B")
  graphics::mtext(paste0(
    "Fig. S1  The trends of the proportional-hazards assumption test based on ",
    "the COX regression model. Group = ", index_a, "+", index_b,
    " joint tertile score; adjusted for ",
    paste(covariates, collapse = " and "), ". Pink dashed line: Beta(t)=0."),
    side = 1, outer = TRUE, line = 1.4, cex = 0.78, adj = 0)
  stopifnot(file.exists(out_pdf))

  # 审计 CSV（写在 out_pdf 同目录；调用方可再拷入 _assets）
  stem <- sub("\\.pdf$", "", basename(out_pdf))
  dir_out <- dirname(out_pdf)
  extract <- function(z) {
    idx <- match("Group", colnames(z$zph$y)); if (is.na(idx)) idx <- 1L
    data.frame(database = z$database, time_transform = z$zph$x,
               time = z$zph$time, schoenfeld = z$zph$y[, idx],
               p_group = z$p_group, n = z$n, events = z$events,
               stringsAsFactors = FALSE)
  }
  resid_csv <- file.path(dir_out, paste0(stem, "_schoenfeld_points.csv"))
  write.csv(if (is.null(ei_z)) extract(mi_z) else rbind(extract(mi_z), extract(ei_z)),
            resid_csv, row.names = FALSE)
  sum_csv <- file.path(dir_out, paste0(stem, "_ph_summary.csv"))
  write.csv(data.frame(
    database = c(mi_z$database, if (!is.null(ei_z)) ei_z$database),
    n = c(mi_z$n, if (!is.null(ei_z)) ei_z$n),
    events = c(mi_z$events, if (!is.null(ei_z)) ei_z$events),
    ph_p_group = c(mi_z$p_group, if (!is.null(ei_z)) ei_z$p_group),
    covariates = paste(c("Group", mi_z$covs), collapse = "+"),
    transform = "km (cox.zph default)", stringsAsFactors = FALSE),
    sum_csv, row.names = FALSE)

  invisible(list(path = out_pdf, mimic = mi_z, eicu = ei_z,
                 resid_csv = resid_csv, summary_csv = sum_csv))
}

# ==========================================================================
# 8) Table 1 文献版式：分库表 Survivor/Non-survivor + Exposures 末节
#    读取任意已导出的分库 Table1 xlsx（引擎默认可能用 No AKI/AKI 标签），
#    重命名结局列、剔除 Group 假分层、把暴露移到末节 Exposures（A→B 顺序），
#    按标准节序重排并写加粗三线表。
# ==========================================================================
.pub_t1_is_foot <- function(x) {
  grepl("are presented|Statistical comparisons|Outcome:|Exposures section|test\\.?$",
        as.character(x), ignore.case = TRUE)
}

pub_lit_style_table1 <- function(path_src, dest, index_a, index_b,
                                 section_order = c("Demographics", "Vital Signs",
                                   "Laboratory Tests", "Clinical Scores",
                                   "Interventions and Hospital Course",
                                   "Comorbidities", "Exposures"),
                                 title = "Table 1.",
                                 footnotes = NULL) {
  .pub_lit_need()
  stopifnot(file.exists(path_src))
  d <- as.data.frame(openxlsx::read.xlsx(path_src, colNames = FALSE,
                                         check.names = FALSE),
                     stringsAsFactors = FALSE)
  d <- d[, seq_len(min(5L, ncol(d))), drop = FALSE]
  colnames(d) <- c("Characteristic", "Overall", "Survivor", "Non_survivor", "p_value")
  for (j in names(d)) {
    d[[j]] <- trimws(as.character(d[[j]]))
    d[[j]][is.na(d[[j]]) | d[[j]] %in% c("NA", "NaN")] <- ""
  }
  if (grepl("^Table 1", d$Characteristic[1], ignore.case = TRUE))
    d <- d[-1L, , drop = FALSE]
  hdr_i <- which(grepl("^\\s*Characteristic\\s*$", d$Characteristic))[1]
  stopifnot(is.finite(hdr_i))
  hd <- unlist(d[hdr_i, ], use.names = FALSE)
  # 结局标签归一：No AKI→Survivor、AKI→Non-survivor
  n_sur <- suppressWarnings(as.integer(gsub("[^0-9]", "", hd[3])))
  n_non <- suppressWarnings(as.integer(gsub("[^0-9]", "", hd[4])))
  n_ov  <- suppressWarnings(as.integer(gsub("[^0-9]", "", hd[2])))
  stopifnot(is.finite(n_sur), n_sur > 0, is.finite(n_non), n_non > 0)
  body <- d[-seq_len(hdr_i), , drop = FALSE]
  fi <- which(.pub_t1_is_foot(body$Characteristic))
  if (length(fi)) body <- body[seq_len(min(fi) - 1L), , drop = FALSE]
  body$Characteristic[body$Characteristic == "Exposure"] <- "Exposures"
  # 剔除 Group 假分层（No AKI/AKI 水平行）
  g0 <- which(body$Characteristic == "Group")[1]
  if (is.finite(g0)) {
    drop <- rep(FALSE, nrow(body)); j <- g0
    while (j <= nrow(body) && (j == g0 || body$Characteristic[j] %in%
             c("No AKI", "AKI", "Survivor", "Non-survivor"))) {
      drop[j] <- TRUE; j <- j + 1L
    }
    body <- body[!drop, , drop = FALSE]
  }
  exp_rows <- body[body$Characteristic %in% c(index_a, index_b), , drop = FALSE]
  ord <- match(c(index_a, index_b), exp_rows$Characteristic)
  exp_rows <- exp_rows[ord[is.finite(ord)], , drop = FALSE]
  if (!nrow(exp_rows)) stop("Table1 缺暴露行 ", index_a, "/", index_b, call. = FALSE)
  # 丢旧 Exposures 块与散落暴露行
  drop2 <- rep(FALSE, nrow(body)); in_exp <- FALSE
  known_secs <- setdiff(section_order, "Exposures")
  for (i in seq_len(nrow(body))) {
    ch <- body$Characteristic[i]
    if (identical(ch, "Exposures")) { in_exp <- TRUE; drop2[i] <- TRUE; next }
    if (in_exp) {
      if (ch %in% c(known_secs, "Group", "Exposure")) { in_exp <- FALSE }
      else { drop2[i] <- TRUE; next }
    }
    if (ch %in% c(index_a, index_b)) drop2[i] <- TRUE
  }
  body <- body[!drop2, , drop = FALSE]
  # 按节切分重排
  sec_idx <- which(body$Characteristic %in% known_secs)
  blocks <- list()
  if (length(sec_idx) && sec_idx[1] > 1L)
    blocks[["_pre"]] <- body[seq_len(sec_idx[1] - 1L), , drop = FALSE]
  for (k in seq_along(sec_idx)) {
    i0 <- sec_idx[k]
    i1 <- if (k < length(sec_idx)) sec_idx[k + 1L] - 1L else nrow(body)
    blocks[[body$Characteristic[i0]]] <- body[i0:i1, , drop = FALSE]
  }
  out <- NULL
  for (nm in known_secs) if (!is.null(blocks[[nm]])) out <- rbind(out, blocks[[nm]])
  for (nm in setdiff(names(blocks), c(known_secs, "_pre"))) out <- rbind(out, blocks[[nm]])
  if (!is.null(blocks[["_pre"]])) out <- rbind(blocks[["_pre"]], out)
  exp_block <- rbind(
    data.frame(Characteristic = "Exposures", Overall = "", Survivor = "",
               Non_survivor = "", p_value = "", stringsAsFactors = FALSE),
    exp_rows)
  out <- rbind(out, exp_block)
  rownames(out) <- NULL
  # 表头 N 行 → 列名
  cols <- c("Characteristic",
            if (grepl("^Overall", hd[2])) hd[2] else "Overall",
            sub("^No AKI N", "Survivor N", hd[3]),
            sub("^AKI N", "Non-survivor N", hd[4]),
            "p-value")
  if (!grepl("Survivor", cols[3])) cols[3] <- hd[3]
  if (!grepl("Non-survivor|Non_survivor", cols[4])) cols[4] <- hd[4]
  colnames(out) <- cols
  blob <- paste(out[[1]], collapse = " ")
  if (grepl("No AKI", blob) || any(out[[1]] == "Group"))
    stop("仍含 Group/AKI 残留: ", path_src, call. = FALSE)
  if (!"Exposures" %in% out[[1]]) stop("缺 Exposures 节", call. = FALSE)
  # 写加粗三线表（insert_map 命中已存在节标题加粗；水平行居中）
  insert_map <- stats::setNames(seq_along(section_order), section_order)
  lvl_labs <- c("Female", "Male", "Asian", "Black", "Hispanic", "Other", "White",
                "No", "Yes")
  # .sci_xlsx_write_three_line_workbook 的 tbl_df_new 第 1 行必须是列头
  hdr_df <- as.data.frame(as.list(cols), stringsAsFactors = FALSE)
  names(hdr_df) <- cols
  tbl <- rbind(hdr_df, out)
  level_row_idx <- which(tbl[[1]] %in% lvl_labs)   # tbl 内含 header 行
  if (is.null(footnotes)) footnotes <- c(
    "Continuous variables are presented as mean (SD) or median (IQR) depending on distribution; categorical as n (%).",
    "Comparisons between Survivor and Non-survivor used the Wilcoxon rank-sum or Pearson chi-squared test.",
    "Outcome: 28-day all-cause mortality (Survivor / Non-survivor).",
    paste0("Exposures: ", index_a, " and ", index_b, "."))
  .sci_xlsx_write_three_line_workbook(
    filepath = dest, title = title, tbl_df_new = tbl,
    sheet = "Table 1", footnotes = footnotes,
    insert_map = insert_map, level_row_idx = level_row_idx)
  stopifnot(file.exists(dest), file.info(dest)$size > 2000)
  message("pub_lit_style_table1 OK ", basename(dest),
          " sections=", paste(intersect(section_order, out[[1]]), collapse = "→"))
  invisible(dest)
}

# ==========================================================================
# 5b) 从定稿 Table1 xlsx 派生 S2/S3 变量 spec（label / 类型 / 水平顺序）
# ==========================================================================
pub_lit_spec_from_table1 <- function(table1_xlsx,
                                     level_labs = c("Female", "Male", "Asian",
                                       "Black", "Hispanic", "Other", "White",
                                       "No", "Yes", "Never", "Current")) {
  .pub_lit_need()
  stopifnot(file.exists(table1_xlsx))
  d <- openxlsx::read.xlsx(table1_xlsx, colNames = FALSE, startRow = 1)
  v <- trimws(as.character(d[[1]])); v[is.na(v)] <- ""
  # 去标题（Table 1...）与表头（Characteristic...）
  st <- which(grepl("^Table 1", v, ignore.case = TRUE))[1]
  hd <- which(grepl("^Characteristic$", v, ignore.case = TRUE))[1]
  start <- max(c(st, hd), na.rm = TRUE)
  body <- v[seq.int(min(start + 1L, length(v)), length(v))]
  # 去脚注（长文本且其余列空）
  body <- body[seq_len(min(length(body),
    (max(which(grepl("are presented|Comparisons between|^Outcome:|^Exposures:",
                     body, ignore.case = TRUE))) - 1L)))]
  sec_titles <- c("Demographics", "Vital Signs", "Laboratory Tests",
    "Clinical Scores", "Interventions and Hospital Course", "Interventions",
    "Hospital Course", "Comorbidities", "Exposures")
  spec <- list()
  i <- 1L
  while (i <= length(body)) {
    lab0 <- body[i]
    if (!nzchar(lab0)) { i <- i + 1L; next }
    if (lab0 %in% sec_titles) { i <- i + 1L; next }
    # 去单位/括号后缀作为显示 label 与列名候选
    lab <- re2_remove <- sub("\\s*\\((ever|at any time)\\)\\s*$", "", lab0)
    lab <- trimws(strsplit(lab, ",", fixed = TRUE)[[1L]][1])
    nxt <- if (i < length(body)) body[i + 1L] else ""
    is_cat <- nzchar(nxt) && (trimws(nxt) %in% level_labs)
    if (is_cat) {
      # 吞掉水平行
      j <- i + 1L
      while (j <= length(body) && trimws(body[j]) %in% level_labs) j <- j + 1L
      i <- j - 1L
    }
    spec[[length(spec) + 1L]] <- list(label = lab,
                                      col = unique(c(lab, lab0)),
                                      type = if (is_cat) "categorical" else "continuous")
    i <- i + 1L
  }
  spec
}

message("loaded R/pub_reference_lit_tables.R")
