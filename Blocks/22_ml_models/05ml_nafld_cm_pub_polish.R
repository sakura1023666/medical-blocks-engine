###############################################################################
#  ml_nafld_cm 文献级发表辅助（Table2 横排 / probs / NRI-IDI / 期刊风图）
#  由 ml_nafld_pub_finalize source；不 register 为独立 block
###############################################################################

.nafld_cm_best_from_table4 <- function(cfg) {
  out <- .nafld_cm_out_dirs(cfg)
  p <- file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.csv")
  if (!file.exists(p)) return(NULL)
  tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  if (!nrow(tab) || !any(is.finite(tab$auc_mean))) return(NULL)
  tab[which.max(tab$auc_mean), , drop = FALSE]
}

.nafld_cm_split_train_val <- function(ctx, cfg) {
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) return(NULL)
  data <- .nafld_cm_load_metabolome(cfg, data)
  id <- cfg$data$id_column %||% "ID"
  tr <- ctx$data$train
  te <- ctx$data$test
  if (!is.null(tr) && is.data.frame(tr) && id %in% names(tr) && id %in% names(data)) {
    tr_df <- data[as.character(data[[id]]) %in% as.character(tr[[id]]), , drop = FALSE]
  } else {
    tr_df <- .nafld_cm_training_df(ctx, data)
  }
  if (!is.null(te) && is.data.frame(te) && id %in% names(te) && id %in% names(data)) {
    va_df <- data[as.character(data[[id]]) %in% as.character(te[[id]]), , drop = FALSE]
  } else {
    va_df <- data[!(as.character(data[[id]]) %in% as.character(tr_df[[id]])), , drop = FALSE]
  }
  list(all = data, train = tr_df, val = va_df)
}

.nafld_cm_cm_features <- function(ctx) {
  fe <- ctx$results$nafld_feature_spaces
  if (is.null(fe)) return(character(0))
  as.character(fe$CM$selected %||% character(0))
}

.nafld_cm_retrain_best_val <- function(ctx, cfg, best, feats) {
  if (is.null(best) || !length(feats)) return(NULL)
  split <- .nafld_cm_split_train_val(ctx, cfg)
  if (is.null(split)) return(NULL)
  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  mm_tr <- .nafld_cm_model_matrix(split$train, feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(split$val, feats, oc, pos)
  if (mm_tr$n < 20L || mm_va$n < 10L) return(NULL)
  feats <- intersect(feats, colnames(mm_tr$x))
  feats <- intersect(feats, colnames(mm_va$x))
  if (!length(feats)) return(NULL)
  xtr <- mm_tr$x[, feats, drop = FALSE]
  xva <- mm_va$x[, feats, drop = FALSE]
  mu <- colMeans(xtr, na.rm = TRUE)
  sdv <- apply(xtr, 2, stats::sd, na.rm = TRUE)
  sdv[!is.finite(sdv) | sdv == 0] <- 1
  xtr <- scale(xtr, center = mu, scale = sdv)
  xva <- scale(xva, center = mu, scale = sdv)
  algo <- as.character(best$algorithm)[1L]
  fp <- .nafld_cm_fit_pred(algo, xtr, mm_tr$y, xva, seed = 1234L, cfg = cfg)
  if (!isTRUE(fp$ok)) return(NULL)
  list(
    y = mm_va$y, pred = fp$pred, feats = feats, algo = algo,
    space = as.character(best$space)[1L],
    n_train = mm_tr$n, n_val = mm_va$n
  )
}

.nafld_cm_plot_figure3 <- function(ctx, cfg, fig_dir, best, refit) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(FALSE))
  out <- .nafld_cm_out_dirs(cfg)
  t4 <- utils::read.csv(
    file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.csv"),
    stringsAsFactors = FALSE
  )
  p_heat <- ggplot2::ggplot(t4, ggplot2::aes(algorithm, space, fill = auc_mean)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", auc_mean)), size = 2.8) +
    ggplot2::scale_fill_gradient(low = "#f7fbff", high = "#08306b") +
    ggplot2::labs(title = "Nested CV AUC", x = NULL, y = NULL, fill = "AUC") +
    ggplot2::theme_classic(base_size = 11, base_family = "serif") +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
  p_roc <- NULL
  if (!is.null(refit) && requireNamespace("pROC", quietly = TRUE)) {
    roc <- pROC::roc(refit$y, refit$pred, quiet = TRUE, direction = "<")
    rd <- data.frame(fpr = 1 - roc$specificities, tpr = roc$sensitivities)
    auc_v <- as.numeric(pROC::auc(roc))
    p_roc <- ggplot2::ggplot(rd, ggplot2::aes(fpr, tpr)) +
      ggplot2::geom_line(linewidth = 1, color = "#2166ac") +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
      ggplot2::labs(
        title = sprintf("Validation ROC (%s+%s)", refit$space, refit$algo),
        x = "1 - Specificity", y = "Sensitivity",
        subtitle = sprintf("AUC = %.3f (n=%d)", auc_v, refit$n_val)
      ) +
      ggplot2::theme_classic(base_size = 11, base_family = "serif")
  }
  fp <- file.path(fig_dir, "Figure 3. ML performance heatmap and ROC.pdf")
  if (!is.null(p_roc) && requireNamespace("gridExtra", quietly = TRUE)) {
    grDevices::pdf(fp, width = 11, height = 5)
    gridExtra::grid.arrange(p_heat, p_roc, ncol = 2, widths = c(1.2, 1))
    grDevices::dev.off()
  } else {
    ggplot2::ggsave(fp, p_heat, width = 9, height = 4)
  }
  invisible(file.exists(fp))
}

.nafld_fmt_or_ci <- function(or, lo, hi, digits = 2L) {
  or <- suppressWarnings(as.numeric(or)); lo <- suppressWarnings(as.numeric(lo)); hi <- suppressWarnings(as.numeric(hi))
  if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("")
  fmt <- sprintf("%%.%df (%%.%df-%%.%df)", digits, digits, digits)
  sprintf(fmt, or, lo, hi)
}

.nafld_fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (!is.finite(p)) return("")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}

.nafld_glm_or_row <- function(fit, var) {
  if (is.null(fit)) return(list(or = NA, lo = NA, hi = NA, p = NA))
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(sm)) return(list(or = NA, lo = NA, hi = NA, p = NA))
  rn <- rownames(sm)
  hit <- rn[rn == var | startsWith(rn, paste0(var))][1L]
  if (is.na(hit) || !nzchar(hit)) {
    # factor levels: take first non-intercept term matching prefix
    hit <- rn[grepl(paste0("^", var), rn)][1L]
  }
  if (is.na(hit) || !nzchar(as.character(hit))) return(list(or = NA, lo = NA, hi = NA, p = NA))
  b <- sm[hit, 1]; se <- sm[hit, 2]; p <- sm[hit, 4]
  list(or = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = p)
}

#' 横排 SCI Table 2：临床入选特征 Crude / Model1 / Model2
.nafld_write_table2_sci <- function(ctx, cfg, out_tables) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (!exists("ml_resolve_assoc_covariates", mode = "function")) {
    f <- file.path(root, "R/ml_assoc_covariate_rule.R")
    if (file.exists(f)) source(f, local = FALSE)
  }
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }

  fe <- ctx$results$nafld_feature_spaces
  split <- .nafld_cm_split_train_val(ctx, cfg)
  if (is.null(fe) || is.null(split)) return(invisible(NULL))

  # 供铁律：最终 ML 特征 = CM（仍写入 ctx，便于审计）
  ctx$results$feature_selection_final <- as.character(fe$CM$selected %||% character(0))
  ctx$results$ml_feature_names <- ctx$results$feature_selection_final

  # 本课题 Table 2 人口学口径（用户确认）：Model1=Age；Model2=Age+Gender
  # （Gender 未进 CM；UV 不显著，但是常规强制人口学调整）
  sex_col <- intersect(c("Gender", "Sex"), names(split$train))[1L]
  m1 <- "Age"
  m2 <- unique(c("Age", if (!is.na(sex_col)) sex_col else character(0)))
  m1 <- intersect(m1, names(split$train))
  m2 <- intersect(m2, names(split$train))
  if (!length(m1)) m1 <- character(0)
  if (!length(m2)) m2 <- m1

  c_feats <- as.character(fe$C$selected %||% character(0))
  c_feats <- intersect(c_feats, names(split$train))
  # 排除已是协变量本身的重复当暴露
  c_feats <- setdiff(c_feats, c(m1, m2))
  if (!length(c_feats)) return(invisible(NULL))

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  d <- split$train
  d$y <- .nafld_cm_outcome01(d[[oc]], pos)

  body <- list()
  for (v in c_feats) {
    if (!v %in% names(d)) next
    keep <- c("y", v, intersect(m2, names(d)))
    df <- d[, unique(keep), drop = FALSE]
    df <- df[stats::complete.cases(df), , drop = FALSE]
    if (nrow(df) < 30L || length(unique(df$y)) < 2L) next

    fit0 <- tryCatch(stats::glm(stats::as.formula(paste("y ~", v)), data = df, family = binomial()),
                     error = function(e) NULL)
    others1 <- setdiff(intersect(m1, names(df)), v)
    fit1 <- if (length(others1)) {
      tryCatch(stats::glm(stats::as.formula(paste("y ~", paste(c(v, others1), collapse = "+"))),
                          data = df, family = binomial()), error = function(e) NULL)
    } else fit0
    others2 <- setdiff(intersect(m2, names(df)), v)
    fit2 <- if (length(others2)) {
      tryCatch(stats::glm(stats::as.formula(paste("y ~", paste(c(v, others2), collapse = "+"))),
                          data = df, family = binomial()), error = function(e) NULL)
    } else fit1

    r0 <- .nafld_glm_or_row(fit0, v)
    r1 <- .nafld_glm_or_row(fit1, v)
    r2 <- .nafld_glm_or_row(fit2, v)
    body[[length(body) + 1L]] <- data.frame(
      Characteristic = v,
      `Crude OR (95%CI)` = .nafld_fmt_or_ci(r0$or, r0$lo, r0$hi),
      `Crude P` = .nafld_fmt_p(r0$p),
      `Model1 OR (95%CI)` = .nafld_fmt_or_ci(r1$or, r1$lo, r1$hi),
      `Model1 P` = .nafld_fmt_p(r1$p),
      `Model2 OR (95%CI)` = .nafld_fmt_or_ci(r2$or, r2$lo, r2$hi),
      `Model2 P` = .nafld_fmt_p(r2$p),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if (!length(body)) return(invisible(NULL))
  tab <- do.call(rbind, body)

  fn <- c(
    "Outcome: NAFLD vs Normal (training set).",
    sprintf("Model 1 adjusted for: %s.", paste(m1, collapse = ", ")),
    sprintf(
      "Model 2 adjusted for: %s (forced demographic adjustment; Gender was not UV-significant and not in the CM ML feature set).",
      paste(m2, collapse = ", ")
    ),
    "ORs are from logistic regression; continuous predictors are per-unit increase (no quantile grouping)."
  )
  path <- file.path(out_tables, "Table 2. Clinical feature associations (Crude Model1 Model2).xlsx")
  sci_xlsx_single_header_booktabs(path, "Table 2. Association of clinical features with NAFLD", tab, footnotes = fn)
  # 同步 CSV 备份
  utils::write.csv(tab, file.path(out_tables, "Table 2. Clinical feature associations.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(path = path, model1 = m1, model2 = m2, n = nrow(tab)))
}

.nafld_pretty_metab_name <- function(x) {
  gsub("^U_", "", as.character(x))
}

.nafld_fmt_median_iqr <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return("—")
  qs <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE)
  sprintf("%.2f (%.2f, %.2f)", qs[2], qs[1], qs[3])
}

#' Table 1.1 — 全部尿代谢物基线（空间 M 候选池，非仅入选）
.nafld_write_table1_metabolite <- function(ctx, cfg, out_tables) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) return(invisible(NULL))
  data <- .nafld_cm_load_metabolome(cfg, data)
  # 全 M 池（prefix U_*），不是 consensus 入选子集
  m_feats <- .nafld_cm_metabolite_pool(cfg, data)
  if (!length(m_feats)) {
    pref <- as.character((cfg$feature_pools %||% list())$metabolite_prefix %||% "U_")[1L]
    m_feats <- grep(paste0("^", pref), names(data), value = TRUE)
  }
  m_feats <- sort(unique(as.character(m_feats)))
  if (!length(m_feats)) return(invisible(NULL))

  # 入选标记（脚注/可选列）
  fe <- ctx$results$nafld_feature_spaces
  selected <- as.character(fe$M$selected %||% character(0))

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  ref <- cfg$project$reference_group %||% "Normal"
  g <- as.character(data[[oc]])
  is_pos <- g == pos
  is_ref <- g == ref
  ok <- is_pos | is_ref
  data <- data[ok, , drop = FALSE]
  is_pos <- is_pos[ok]
  is_ref <- is_ref[ok]
  n_all <- nrow(data)
  n_pos <- sum(is_pos)
  n_ref <- sum(is_ref)

  rows <- list(data.frame(
    Characteristic = sprintf("Urine metabolites (full M pool, n=%d)", length(m_feats)),
    Overall = "", Normal = "", NAFLD = "", `p-value` = "", Selected = "",
    check.names = FALSE, stringsAsFactors = FALSE
  ))
  for (v in m_feats) {
    x <- as.numeric(data[[v]])
    p <- tryCatch(stats::wilcox.test(x[is_pos], x[is_ref])$p.value, error = function(e) NA_real_)
    rows[[length(rows) + 1L]] <- data.frame(
      Characteristic = .nafld_pretty_metab_name(v),
      Overall = .nafld_fmt_median_iqr(x),
      Normal = .nafld_fmt_median_iqr(x[is_ref]),
      NAFLD = .nafld_fmt_median_iqr(x[is_pos]),
      `p-value` = .nafld_fmt_p(p),
      Selected = if (v %in% selected) "Yes" else "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  tab <- do.call(rbind, rows)
  names(tab) <- c(
    "Characteristic",
    sprintf("Overall N = %d", n_all),
    sprintf("%s N = %d", ref, n_ref),
    sprintf("%s N = %d", pos, n_pos),
    "p-value",
    "In ML consensus (M)"
  )
  fn <- c(
    "Analytic cohort (same as clinical Table 1).",
    "Values are median (IQR). P values from Wilcoxon rank-sum test (NAFLD vs Normal).",
    sprintf("All urine metabolites in the M feature pool (n=%d), not limited to consensus-selected features.", length(m_feats)),
    sprintf("Column 'In ML consensus (M)': Yes = among the %d metabolites locked for ML space M (Table 3).", length(selected)),
    "Table 2.1 reports logistic associations for the consensus-selected subset only."
  )
  path <- file.path(out_tables, "Table 1.1 Metabolite baseline characteristics.xlsx")
  sci_xlsx_single_header_booktabs(
    path,
    "Table 1.1. Baseline characteristics of urine metabolites (full M pool)",
    tab,
    footnotes = fn
  )
  utils::write.csv(tab, file.path(out_tables, "Table 1.1 Metabolite baseline characteristics.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(path = path, n = length(m_feats), n_selected = length(selected)))
}

#' Table 2.1 — 入选代谢物逻辑回归（Crude / M1=Age / M2=Age+Gender）
.nafld_write_table2_metabolite <- function(ctx, cfg, out_tables) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  fe <- ctx$results$nafld_feature_spaces
  split <- .nafld_cm_split_train_val(ctx, cfg)
  if (is.null(fe) || is.null(split)) return(invisible(NULL))

  sex_col <- intersect(c("Gender", "Sex"), names(split$train))[1L]
  m1 <- intersect("Age", names(split$train))
  m2 <- unique(c("Age", if (!is.na(sex_col)) sex_col else character(0)))
  m2 <- intersect(m2, names(split$train))

  m_feats <- as.character(fe$M$selected %||% character(0))
  m_feats <- intersect(m_feats, names(split$train))
  m_feats <- setdiff(m_feats, c(m1, m2))
  if (!length(m_feats)) return(invisible(NULL))

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  d <- split$train
  d$y <- .nafld_cm_outcome01(d[[oc]], pos)

  body <- list()
  for (v in m_feats) {
    # 暴露以 log2(校正值+1) 进模：OR = 强度每翻倍(1 个 log2 单位)的关联，
    # 效应量可读；OR>1 = 该代谢物越高 NAFLD  odds 越高（与 log2FC(NAFLD/Normal) 同向）
    lv <- paste0(v, "__log2")
    dd <- d
    dd[[lv]] <- log2(pmax(suppressWarnings(as.numeric(d[[v]])), 0) + 1)
    keep <- c("y", lv, intersect(m2, names(dd)))
    df <- dd[, unique(keep), drop = FALSE]
    df <- df[stats::complete.cases(df), , drop = FALSE]
    if (nrow(df) < 30L || length(unique(df$y)) < 2L) next
    fit0 <- tryCatch(stats::glm(stats::as.formula(paste("y ~", lv)), data = df, family = binomial()),
                     error = function(e) NULL)
    others1 <- setdiff(intersect(m1, names(df)), lv)
    fit1 <- if (length(others1)) {
      tryCatch(stats::glm(stats::as.formula(paste("y ~", paste(c(lv, others1), collapse = "+"))),
                          data = df, family = binomial()), error = function(e) NULL)
    } else fit0
    others2 <- setdiff(intersect(m2, names(df)), lv)
    fit2 <- if (length(others2)) {
      tryCatch(stats::glm(stats::as.formula(paste("y ~", paste(c(lv, others2), collapse = "+"))),
                          data = df, family = binomial()), error = function(e) NULL)
    } else fit1
    r0 <- .nafld_glm_or_row(fit0, lv)
    r1 <- .nafld_glm_or_row(fit1, lv)
    r2 <- .nafld_glm_or_row(fit2, lv)
    body[[length(body) + 1L]] <- data.frame(
      Characteristic = .nafld_pretty_metab_name(v),
      `Crude OR (95%CI)` = .nafld_fmt_or_ci(r0$or, r0$lo, r0$hi, digits = 3L),
      `Crude P` = .nafld_fmt_p(r0$p),
      `Model1 OR (95%CI)` = .nafld_fmt_or_ci(r1$or, r1$lo, r1$hi, digits = 3L),
      `Model1 P` = .nafld_fmt_p(r1$p),
      `Model2 OR (95%CI)` = .nafld_fmt_or_ci(r2$or, r2$lo, r2$hi, digits = 3L),
      `Model2 P` = .nafld_fmt_p(r2$p),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if (!length(body)) return(invisible(NULL))
  tab <- do.call(rbind, body)
  fn <- c(
    "Outcome: NAFLD vs Normal (training set).",
    sprintf("Model 1 adjusted for: %s.", paste(m1, collapse = ", ")),
    sprintf("Model 2 adjusted for: %s (same demographic rule as clinical Table 2).", paste(m2, collapse = ", ")),
    "Exposures are consensus urine metabolites (space M / Table 3), creatinine-corrected.",
    "OR per 1-unit increase in log2(metabolite+1), i.e. per doubling of creatinine-corrected intensity; OR>1 = higher metabolite associated with NAFLD (same direction as log2FC NAFLD/Normal)."
  )
  path <- file.path(out_tables, "Table 2.1 Metabolite associations (Crude Model1 Model2).xlsx")
  sci_xlsx_single_header_booktabs(
    path,
    "Table 2.1. Association of selected metabolites with NAFLD",
    tab,
    footnotes = fn
  )
  utils::write.csv(tab, file.path(out_tables, "Table 2.1 Metabolite associations.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(path = path, model1 = m1, model2 = m2, n = nrow(tab)))
}

#' 传统评分箱线 2 联图（HSI / TyG）→ Figure S1（带 Wilcoxon 显著性括号）
.nafld_plot_boxplot_scores_s1 <- function(ctx, cfg, out_fig) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(FALSE))
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) return(invisible(FALSE))
  oc <- cfg$data$outcome_column %||% "Disease"
  ref <- cfg$project$reference_group %||% "Normal"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  scores <- intersect(c("HSI", "TyG"), names(data))
  if (!length(scores) || !oc %in% names(data)) return(invisible(FALSE))

  .star <- function(p) {
    if (!is.finite(p)) return("ns")
    if (p < 0.0001) return("****")
    if (p < 0.001) return("***")
    if (p < 0.01) return("**")
    if (p < 0.05) return("*")
    "ns"
  }

  long <- do.call(rbind, lapply(scores, function(s) {
    data.frame(
      Score = s,
      value = as.numeric(data[[s]]),
      Disease = as.character(data[[oc]]),
      stringsAsFactors = FALSE
    )
  }))
  long <- long[is.finite(long$value) & !is.na(long$Disease), , drop = FALSE]
  if (!nrow(long)) return(invisible(FALSE))
  long$Disease <- factor(long$Disease, levels = c(ref, pos))

  # 每面板：Wilcoxon + 括号位置
  ann <- do.call(rbind, lapply(scores, function(s) {
    sub <- long[long$Score == s, , drop = FALSE]
    x1 <- sub$value[as.character(sub$Disease) == ref]
    x2 <- sub$value[as.character(sub$Disease) == pos]
    p <- tryCatch(stats::wilcox.test(x1, x2)$p.value, error = function(e) NA_real_)
    ymax <- max(sub$value, na.rm = TRUE)
    ymin <- min(sub$value, na.rm = TRUE)
    rng <- ymax - ymin
    if (!is.finite(rng) || rng <= 0) rng <- abs(ymax) + 1
    y <- ymax + 0.08 * rng
    data.frame(
      Score = s,
      xmin = 1, xmax = 2, y = y,
      label = sprintf("%s\nP = %s", .star(p), .nafld_fmt_p(p)),
      stringsAsFactors = FALSE
    )
  }))

  p <- ggplot2::ggplot(long, ggplot2::aes(Disease, value, fill = Disease)) +
    ggplot2::geom_boxplot(outlier.size = 0.6, width = 0.55, alpha = 0.85) +
    ggplot2::facet_wrap(~Score, scales = "free_y", nrow = 1) +
    ggplot2::geom_segment(
      data = ann,
      ggplot2::aes(x = xmin, xend = xmax, y = y, yend = y),
      inherit.aes = FALSE, linewidth = 0.4
    ) +
    ggplot2::geom_segment(
      data = ann,
      ggplot2::aes(x = xmin, xend = xmin, y = y - 0.02 * abs(y), yend = y),
      inherit.aes = FALSE, linewidth = 0.4
    ) +
    ggplot2::geom_segment(
      data = ann,
      ggplot2::aes(x = xmax, xend = xmax, y = y - 0.02 * abs(y), yend = y),
      inherit.aes = FALSE, linewidth = 0.4
    ) +
    ggplot2::geom_text(
      data = ann,
      ggplot2::aes(x = 1.5, y = y, label = label),
      inherit.aes = FALSE, vjust = -0.15, size = 3.2, family = "serif", lineheight = 0.95
    ) +
    ggplot2::scale_fill_manual(values = c("#4C78A8", "#F58518")) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.22))) +
    ggplot2::labs(
      x = NULL, y = NULL,
      title = "Traditional NAFLD scores by disease group",
      subtitle = "Wilcoxon rank-sum test (Normal vs NAFLD)"
    ) +
    ggplot2::theme_classic(base_size = 11, base_family = "serif") +
    ggplot2::theme(
      legend.position = "none",
      strip.background = ggplot2::element_blank(),
      plot.subtitle = ggplot2::element_text(size = 9, color = "grey30")
    )
  out <- file.path(out_fig, "Figure S1. Traditional scores boxplot HSI TyG.pdf")
  ggplot2::ggsave(out, p, width = 7.2, height = 4.0)
  invisible(file.exists(out))
}

#' 在 CM 特征上生成 OOF+val 概率（供 Table4/5 与 2×4 图）
.nafld_write_ml_probs <- function(ctx, cfg, algos = c("RF", "XGBoost", "LightGBM"),
                                  folds = 5L, seed = 1234L) {
  split <- .nafld_cm_split_train_val(ctx, cfg)
  feats <- .nafld_cm_cm_features(ctx)
  if (is.null(split) || !length(feats)) return(invisible(NULL))
  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"

  mm_tr <- .nafld_cm_model_matrix(split$train, feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(split$val, feats, oc, pos)
  feats <- intersect(feats, colnames(mm_tr$x))
  feats <- intersect(feats, colnames(mm_va$x))
  if (!length(feats) || mm_tr$n < 40L) return(invisible(NULL))

  xtr_raw <- mm_tr$x[, feats, drop = FALSE]
  xva_raw <- mm_va$x[, feats, drop = FALSE]
  ytr <- mm_tr$y
  yva <- mm_va$y

  set.seed(seed)
  fold_id <- NULL
  if (requireNamespace("caret", quietly = TRUE)) {
    fold_id <- tryCatch(
      caret::createFolds(factor(ytr), k = folds, list = FALSE),
      error = function(e) NULL
    )
  }
  if (is.null(fold_id) || length(fold_id) != length(ytr)) {
    # 分层手工折：按结局分别轮转
    fold_id <- integer(length(ytr))
    for (cls in unique(ytr)) {
      ii <- which(ytr == cls)
      fold_id[ii] <- sample(rep(seq_len(folds), length.out = length(ii)))
    }
  }

  rows <- list()
  for (algo in algos) {
    oof <- rep(NA_real_, length(ytr))
    for (f in seq_len(folds)) {
      tr_i <- which(fold_id != f)
      te_i <- which(fold_id == f)
      x_a <- xtr_raw[tr_i, , drop = FALSE]
      x_b <- xtr_raw[te_i, , drop = FALSE]
      mu <- colMeans(x_a, na.rm = TRUE)
      sdv <- apply(x_a, 2, stats::sd, na.rm = TRUE)
      sdv[!is.finite(sdv) | sdv == 0] <- 1
      x_a <- scale(x_a, center = mu, scale = sdv)
      x_b <- scale(x_b, center = mu, scale = sdv)
      fp <- .nafld_cm_fit_pred(algo, x_a, ytr[tr_i], x_b, seed = seed + f, cfg = cfg)
      if (isTRUE(fp$ok)) oof[te_i] <- fp$pred
    }
    # val：全训练集重训
    mu <- colMeans(xtr_raw, na.rm = TRUE)
    sdv <- apply(xtr_raw, 2, stats::sd, na.rm = TRUE)
    sdv[!is.finite(sdv) | sdv == 0] <- 1
    x_tr_s <- scale(xtr_raw, center = mu, scale = sdv)
    x_va_s <- scale(xva_raw, center = mu, scale = sdv)
    fp_v <- .nafld_cm_fit_pred(algo, x_tr_s, ytr, x_va_s, seed = seed + 99L, cfg = cfg)
    val_p <- if (isTRUE(fp_v$ok)) fp_v$pred else rep(NA_real_, length(yva))

    rows[[length(rows) + 1L]] <- data.frame(
      model = algo, idx = seq_along(ytr), y = ytr, p = oof, split = "oof",
      stringsAsFactors = FALSE
    )
    rows[[length(rows) + 1L]] <- data.frame(
      model = algo, idx = seq_along(yva), y = yva, p = val_p, split = "val",
      stringsAsFactors = FALSE
    )
  }
  allp <- do.call(rbind, rows)
  allp <- allp[is.finite(allp$p), , drop = FALSE]
  out <- .nafld_cm_out_dirs(cfg)
  utils::write.csv(allp, file.path(out$root, "ml_python_results.csv"), row.names = FALSE)
  utils::write.csv(data.frame(feature = feats, stringsAsFactors = FALSE),
                   file.path(out$root, "ml_final_features.csv"), row.names = FALSE)
  invisible(list(n_oof = sum(allp$split == "oof"), n_val = sum(allp$split == "val"),
                 algos = unique(allp$model), feats = feats,
                 n_train = length(ytr), n_val_n = length(yva),
                 events_train = sum(ytr == 1L), events_val = sum(yva == 1L)))
}

#' Table 6 + NRI/IDI（相对 HSI/ZJU/TyG）
.nafld_write_table6_nri <- function(ctx, cfg, out_tables, best_algo = "LightGBM") {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  sm_path <- file.path(root, "Blocks/24_ml_supplementary/01block_supplementary_ml.R")
  if (file.exists(sm_path) && !exists(".sm_nri_idi_one", mode = "function")) {
    source(sm_path, local = FALSE)
  }

  split <- .nafld_cm_split_train_val(ctx, cfg)
  feats <- .nafld_cm_cm_features(ctx)
  if (is.null(split) || !length(feats)) return(invisible(NULL))
  # 院内无实测腰围时挂 NHANES 亚裔估计 WC → FLI/LAP（脚注必写 est. WC）
  if (exists(".nafld_attach_fli_lap_est", mode = "function")) {
    split$train <- .nafld_attach_fli_lap_est(split$train, cfg, logger = function(m, ...) cli::cli_alert_info(m))
    split$val   <- .nafld_attach_fli_lap_est(split$val, cfg, logger = function(m, ...) cli::cli_alert_info(m))
  }
  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  scores <- as.character((cfg$baseline_scores %||% list())$scores %||% c("HSI", "ZJU", "TyG", "FLI", "LAP"))
  scores <- intersect(scores, names(split$val))

  mm_tr <- .nafld_cm_model_matrix(split$train, feats, oc, pos)
  mm_va <- .nafld_cm_model_matrix(split$val, feats, oc, pos)
  feats <- intersect(feats, colnames(mm_tr$x))
  feats <- intersect(feats, colnames(mm_va$x))
  xtr <- mm_tr$x[, feats, drop = FALSE]
  xva <- mm_va$x[, feats, drop = FALSE]
  mu <- colMeans(xtr, na.rm = TRUE)
  sdv <- apply(xtr, 2, stats::sd, na.rm = TRUE)
  sdv[!is.finite(sdv) | sdv == 0] <- 1
  xtr <- scale(xtr, center = mu, scale = sdv)
  xva <- scale(xva, center = mu, scale = sdv)
  fp <- .nafld_cm_fit_pred(best_algo, xtr, mm_tr$y, xva, seed = 42L, cfg = cfg)
  if (!isTRUE(fp$ok)) return(invisible(NULL))
  ml_p <- as.numeric(fp$pred)
  y <- mm_va$y

  # 评分 → 风险：用训练集拟合简单 logistic(score)
  score_p <- list()
  auc_rows <- list()
  # 与 mm_va 同一 complete-case 行序
  dval <- split$val
  cc_va <- stats::complete.cases(dval[, c(feats, oc), drop = FALSE])
  dval_cc <- dval[cc_va, , drop = FALSE]
  if (nrow(dval_cc) != length(y)) {
    cli::cli_alert_warning("Table6: val 行数与模型矩阵不一致 ({nrow(dval_cc)} vs {length(y)})")
  }
  for (sc in scores) {
    tr_sc <- suppressWarnings(as.numeric(split$train[[sc]]))
    y_tr <- .nafld_cm_outcome01(split$train[[oc]], pos)
    ok <- is.finite(tr_sc) & is.finite(y_tr)
    df_tr <- data.frame(y = y_tr[ok], s = tr_sc[ok])
    fit <- tryCatch(stats::glm(y ~ s, data = df_tr, family = binomial()), error = function(e) NULL)
    if (is.null(fit)) next
    va_s <- suppressWarnings(as.numeric(dval_cc[[sc]]))
    if (length(va_s) != length(y)) va_s <- va_s[seq_len(min(length(va_s), length(y)))]
    n_use <- min(length(va_s), length(y))
    pr <- as.numeric(stats::predict(fit, newdata = data.frame(s = va_s[seq_len(n_use)]), type = "response"))
    if (n_use < length(y)) {
      pr_full <- rep(NA_real_, length(y))
      pr_full[seq_len(n_use)] <- pr
      pr <- pr_full
    }
    score_p[[sc]] <- pr
    yy <- y[seq_len(n_use)]
    m <- .nafld_cm_youden_metrics(yy, pr[seq_len(n_use)])
    auc_rows[[length(auc_rows) + 1L]] <- data.frame(
      Model = sc, Type = "Traditional score",
      AUC = sprintf("%.3f", m$auc),
      Sensitivity = sprintf("%.3f", m$sens),
      Specificity = sprintf("%.3f", m$spec),
      Threshold = sprintf("%.3f", m$thr),
      stringsAsFactors = FALSE
    )
  }
  m_ml <- .nafld_cm_youden_metrics(y, ml_p)
  auc_rows[[length(auc_rows) + 1L]] <- data.frame(
    Model = paste0("CM+", best_algo), Type = "ML (hold-out)",
    AUC = sprintf("%.3f", m_ml$auc),
    Sensitivity = sprintf("%.3f", m_ml$sens),
    Specificity = sprintf("%.3f", m_ml$spec),
    Threshold = sprintf("%.3f", m_ml$thr),
    stringsAsFactors = FALSE
  )
  # nested CV best mean from Table4
  best <- .nafld_cm_best_from_table4(cfg)
  if (!is.null(best) && nrow(best)) {
    auc_rows[[length(auc_rows) + 1L]] <- data.frame(
      Model = paste0(best$space, "+", best$algorithm),
      Type = "ML (nested CV mean)",
      AUC = sprintf("%.3f", best$auc_mean),
      # 嵌套 CV 是折均 AUC，无单一 Youden 切点 → 用 em dash，勿留空白
      Sensitivity = "\u2014", Specificity = "\u2014", Threshold = "\u2014",
      stringsAsFactors = FALSE
    )
  }
  tab_auc <- do.call(rbind, auc_rows)

  # NRI/IDI
  .fmt_p_nri <- function(p) {
    pv <- suppressWarnings(as.numeric(p))
    if (!length(pv) || !is.finite(pv[1L])) {
      ps <- as.character(p)[1L]
      if (!nzchar(ps) || is.na(ps)) return(NA_character_)
      pv2 <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", ps)))
      if (is.finite(pv2) && pv2 <= 0) return("<0.001")
      return(ps)
    }
    if (pv[1L] < 0.001 || pv[1L] <= 0) "<0.001" else sprintf("%.3f", pv[1L])
  }
  nri_rows <- list()
  if (exists(".sm_nri_idi_one", mode = "function") && length(score_p)) {
    for (sc in names(score_p)) {
      ok <- is.finite(score_p[[sc]]) & is.finite(ml_p) & is.finite(y)
      if (sum(ok) < 30L) next
      df_rc <- data.frame(Group = as.integer(y[ok]))
      pr <- tryCatch(
        .sm_nri_idi_one(df_rc, predrisk1 = score_p[[sc]][ok], predrisk2 = ml_p[ok], cutoffs = c(0, 0.5, 1)),
        error = function(e) NULL
      )
      if (is.null(pr)) next
      nri_rows[[length(nri_rows) + 1L]] <- data.frame(
        Comparison = paste0("CM+", best_algo, " vs ", sc),
        NRI = pr$nri$val %||% NA_character_,
        `P for NRI` = .fmt_p_nri(pr$nri$p),
        IDI = pr$idi$val %||% NA_character_,
        `P for IDI` = .fmt_p_nri(pr$idi$p),
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  tab_nri <- if (length(nri_rows)) do.call(rbind, nri_rows) else NULL

  waist_ft <- if (any(c("FLI", "LAP") %in% scores)) {
    src <- unique(as.character(split$val$Waist_source %||% character(0)))
    if (any(grepl("NHANES_Asian", src))) {
      "FLI/LAP: hospital lacks measured waist; WC estimated by sex-specific NHANES Non-Hispanic Asian lm(WC~BMI+Age+Height). Interpret as sensitivity."
    } else {
      "FLI/LAP included when waist circumference is available."
    }
  } else {
    "FLI/LAP omitted (waist unavailable and estimation failed)."
  }
  sci_xlsx_single_header_booktabs(
    file.path(out_tables, "Table 6. Best model vs HSI ZJU TyG.xlsx"),
    sprintf("Table 6. Discrimination of CM+%s versus traditional scores", best_algo),
    tab_auc,
    footnotes = c(
      "Hold-out rows: Youden threshold on the validation set.",
      "Traditional scores converted to risk via logistic regression fitted on the training set.",
      "Nested CV mean AUC is the outer-loop average from Table 4; Sensitivity/Specificity/Threshold are not applicable (shown as —).",
      waist_ft,
      "FLI = Bedogni 2006; LAP = Kahn (WC−65 men / WC−58 women) × TG mmol/L."
    )
  )
  if (!is.null(tab_nri)) {
    sci_xlsx_single_header_booktabs(
      file.path(out_tables, "Table 6.1 NRI and IDI versus traditional scores.xlsx"),
      sprintf("Table 6.1 NRI and IDI (CM+%s vs traditional scores, hold-out)", best_algo),
      tab_nri,
      footnotes = c(
        "NRI/IDI from PredictABEL::reclassification with cutoffs 0/0.5/1.",
        sprintf("New model = CM+%s; baseline = each traditional score risk.", best_algo),
        "P values of 0 from the software are reported as <0.001."
      )
    )
  }
  utils::write.csv(tab_auc, file.path(out_tables, "Table 6. Best model vs HSI ZJU TyG.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(auc = tab_auc, nri = tab_nri, ml_p = ml_p, score_p = score_p, y = y, algo = best_algo))
}

.nafld_plot_figure2_journal <- function(ctx, cfg, fig_dir) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(FALSE))
  fe <- ctx$results$nafld_feature_spaces
  out <- .nafld_cm_out_dirs(cfg)
  if (is.null(fe)) return(invisible(FALSE))

  # A：三空间计数
  summ <- data.frame(
    space = factor(c("C", "M", "C+M"), levels = c("C", "M", "C+M")),
    n = c(length(fe$C$selected %||% 0), length(fe$M$selected %||% 0), length(fe$CM$selected %||% 0)),
    stringsAsFactors = FALSE
  )
  p1 <- ggplot2::ggplot(summ, ggplot2::aes(space, n, fill = space)) +
    ggplot2::geom_col(width = 0.62, color = NA) +
    ggplot2::geom_text(ggplot2::aes(label = n), vjust = -0.35, size = 3.5,
                       family = "sans") +
    ggplot2::scale_fill_manual(values = c(C = "#0072B2", M = "#E69F00", `C+M` = "#009E73")) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.14))) +
    ggplot2::labs(x = NULL, y = "Consensus features (n)", title = "a") +
    ggplot2::theme_classic(base_size = 11, base_family = "sans") +
    ggplot2::theme(
      legend.position = "none",
      plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0),
      axis.line = ggplot2::element_line(linewidth = 0.4),
      axis.ticks = ggplot2::element_line(linewidth = 0.4)
    )

  # B：用 LightGBM / RF 的连续重要性（方法命中只有 2–3，柱长几乎相同，不适合作图）
  cm <- as.character(fe$CM$selected %||% character(0))
  imp_df <- NULL
  split <- tryCatch(.nafld_cm_split_train_val(ctx, cfg), error = function(e) NULL)
  if (!is.null(split) && length(cm) && requireNamespace("lightgbm", quietly = TRUE)) {
    oc <- cfg$data$outcome_column %||% "Disease"
    pos <- cfg$project$analysis_group %||% "NAFLD"
    mm <- tryCatch(.nafld_cm_model_matrix(split$train, cm, oc, pos), error = function(e) NULL)
    if (!is.null(mm) && mm$n > 30L) {
      feats <- intersect(cm, colnames(mm$x))
      x <- mm$x[, feats, drop = FALSE]
      dtr <- lightgbm::lgb.Dataset(as.matrix(x), label = mm$y)
      fit <- tryCatch(lightgbm::lgb.train(
        params = list(objective = "binary", metric = "auc", num_leaves = 15L,
                      learning_rate = 0.05, verbosity = -1L, num_threads = 1L),
        data = dtr, nrounds = 120L, verbose = -1L
      ), error = function(e) NULL)
      if (!is.null(fit)) {
        im <- tryCatch(lightgbm::lgb.importance(fit, percentage = TRUE), error = function(e) NULL)
        if (!is.null(im) && nrow(im)) {
          imp_df <- data.frame(
            feature = as.character(im$Feature),
            importance = as.numeric(im$Gain),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  # fallback: |univariate AUC−0.5| on train
  if (is.null(imp_df) || !nrow(imp_df)) {
    if (!is.null(split) && length(cm)) {
      oc <- cfg$data$outcome_column %||% "Disease"
      pos <- cfg$project$analysis_group %||% "NAFLD"
      y <- .nafld_cm_outcome01(split$train[[oc]], pos)
      rows <- lapply(cm, function(v) {
        if (!v %in% names(split$train)) return(NULL)
        x <- suppressWarnings(as.numeric(split$train[[v]]))
        if (sum(is.finite(x)) < 30L) return(NULL)
        a <- tryCatch(.nafld_cm_auc(y[is.finite(x)], x[is.finite(x)]), error = function(e) NA_real_)
        data.frame(feature = v, importance = abs(a - 0.5), stringsAsFactors = FALSE)
      })
      imp_df <- do.call(rbind, rows)
    }
  }
  if (is.null(imp_df) || !nrow(imp_df)) return(invisible(FALSE))

  imp_df$grp <- ifelse(grepl("^U_", imp_df$feature), "Metabolite", "Clinical")
  imp_df <- imp_df[order(-imp_df$importance), , drop = FALSE]
  # top 12 clinical + top 12 metabolite（保证两边都有、长度明显不同）
  clin <- imp_df[imp_df$grp == "Clinical", , drop = FALSE]
  meta <- imp_df[imp_df$grp == "Metabolite", , drop = FALSE]
  show <- rbind(utils::head(clin, 12L), utils::head(meta, 12L))
  show <- show[order(show$importance), , drop = FALSE]
  show$feature <- factor(show$feature, levels = show$feature)

  p2 <- ggplot2::ggplot(show, ggplot2::aes(feature, importance, fill = grp)) +
    ggplot2::geom_col(width = 0.78, color = NA) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(Clinical = "#0072B2", Metabolite = "#E69F00")) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.06))) +
    ggplot2::labs(
      x = NULL, y = "LightGBM gain importance (training)",
      fill = NULL, title = "b"
    ) +
    ggplot2::theme_classic(base_size = 10, base_family = "sans") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0),
      legend.position = "bottom",
      legend.key.size = grid::unit(0.35, "cm"),
      axis.line = ggplot2::element_line(linewidth = 0.4),
      axis.ticks = ggplot2::element_line(linewidth = 0.4),
      axis.text.y = ggplot2::element_text(size = 7.5)
    )

  outf <- file.path(fig_dir, "Figure 2. Feature selection by space.pdf")
  if (requireNamespace("gridExtra", quietly = TRUE)) {
    grDevices::pdf(outf, width = 10.2, height = 5.8, useDingbats = FALSE)
    gridExtra::grid.arrange(p1, p2, ncol = 2, widths = c(1, 1.7))
    grDevices::dev.off()
  } else {
    ggplot2::ggsave(outf, p2, width = 6.5, height = 5.5)
  }
  # png companion
  if (requireNamespace("ragg", quietly = TRUE) && requireNamespace("gridExtra", quietly = TRUE)) {
    pngf <- sub("\\.pdf$", ".png", outf)
    ragg::agg_png(pngf, width = 10.2, height = 5.8, units = "in", res = 300)
    gridExtra::grid.arrange(p1, p2, ncol = 2, widths = c(1, 1.7))
    grDevices::dev.off()
  }
  invisible(file.exists(outf))
}

.nafld_plot_figure4_shap <- function(ctx, cfg, fig_dir, algo = "LightGBM") {
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
  feats <- intersect(feats, colnames(mm_tr$x))
  feats <- intersect(feats, colnames(mm_va$x))
  xtr <- mm_tr$x[, feats, drop = FALSE]
  xva <- mm_va$x[, feats, drop = FALSE]
  dtr <- lightgbm::lgb.Dataset(data = as.matrix(xtr), label = mm_tr$y)
  fit <- lightgbm::lgb.train(
    params = list(objective = "binary", metric = "auc", num_leaves = 15L,
                  learning_rate = 0.05, verbosity = -1L, num_threads = 1L),
    data = dtr, nrounds = 120L, verbose = -1L
  )
  out <- file.path(fig_dir, "Figure 4. SHAP summary.pdf")
  ok <- tryCatch({
    sv <- shapviz::shapviz(fit, X_pred = as.matrix(xva), X = as.data.frame(xva))
    grDevices::pdf(out, width = 11, height = 5.2)
    if (requireNamespace("patchwork", quietly = TRUE) || requireNamespace("gridExtra", quietly = TRUE)) {
      p_bee <- shapviz::sv_importance(sv, kind = "beeswarm", max_display = min(15L, ncol(xva))) +
        ggplot2::labs(title = "A") +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", family = "serif"))
      p_bar <- shapviz::sv_importance(sv, kind = "bar", max_display = min(15L, ncol(xva))) +
        ggplot2::labs(title = "B") +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", family = "serif"))
      if (requireNamespace("patchwork", quietly = TRUE)) {
        print(p_bee + p_bar)
      } else {
        gridExtra::grid.arrange(p_bee, p_bar, ncol = 2)
      }
    } else {
      print(shapviz::sv_importance(sv, kind = "beeswarm", max_display = min(15L, ncol(xva))))
    }
    grDevices::dev.off()
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("SHAP: {conditionMessage(e)}")
    FALSE
  })
  invisible(ok)
}

.nafld_plot_figure5_scores <- function(t6, fig_dir) {
  if (is.null(t6) || is.null(t6$auc) || !requireNamespace("ggplot2", quietly = TRUE)) {
    return(invisible(FALSE))
  }
  tab <- t6$auc
  tab$auc_num <- suppressWarnings(as.numeric(tab$AUC))
  tab <- tab[is.finite(tab$auc_num), , drop = FALSE]
  tab$label <- paste0(tab$Model, "\n(", tab$Type, ")")
  tab$label <- factor(tab$label, levels = rev(unique(tab$label)))
  p1 <- ggplot2::ggplot(tab, ggplot2::aes(label, auc_num, fill = Type)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::coord_flip() +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", auc_num)),
                       hjust = -0.1, size = 3.2, family = "serif") +
    ggplot2::scale_y_continuous(limits = c(0, max(1.05, max(tab$auc_num) + 0.08)), expand = c(0, 0)) +
    ggplot2::scale_fill_manual(values = c(
      "Traditional score" = "#9ECAE1",
      "ML (hold-out)" = "#2171B5",
      "ML (nested CV mean)" = "#08306B"
    )) +
    ggplot2::labs(x = NULL, y = "AUC", title = "A  Discrimination", fill = NULL) +
    ggplot2::theme_classic(base_size = 12, base_family = "serif") +
    ggplot2::theme(legend.position = "bottom", plot.title = ggplot2::element_text(face = "bold"))

  # B：画 ΔAUC + IDI（连续 NRI 三者几乎都 ~1.4，柱形会看起来一样）
  p2 <- NULL
  ml_auc <- tab$auc_num[tab$Type == "ML (hold-out)"][1]
  score_tab <- tab[tab$Type == "Traditional score", , drop = FALSE]
  if (is.finite(ml_auc) && nrow(score_tab)) {
    delta <- data.frame(
      Score = score_tab$Model,
      Delta_AUC = ml_auc - score_tab$auc_num,
      stringsAsFactors = FALSE
    )
    # 解析 IDI
    if (!is.null(t6$nri) && nrow(t6$nri)) {
      nr <- t6$nri
      idi_num <- suppressWarnings(as.numeric(sub(
        ".*IDI \\[95% CI\\]: ([0-9.]+).*", "\\1", as.character(nr$IDI)
      )))
      if (all(!is.finite(idi_num))) {
        idi_num <- suppressWarnings(as.numeric(gsub("[^0-9.]+", " ", as.character(nr$IDI))))
        # take first number per row if vectorized poorly
        idi_num <- vapply(as.character(nr$IDI), function(s) {
          m <- regmatches(s, regexpr("[0-9]+\\.[0-9]+", s))
          if (length(m)) as.numeric(m[1]) else NA_real_
        }, numeric(1))
      }
      sc_from_cmp <- sub(".* vs ", "", as.character(nr$Comparison))
      idi_df <- data.frame(Score = sc_from_cmp, IDI = idi_num, stringsAsFactors = FALSE)
      delta <- merge(delta, idi_df, by = "Score", all.x = TRUE)
    } else {
      delta$IDI <- NA_real_
    }
    long <- rbind(
      data.frame(Score = delta$Score, metric = "Delta AUC (ML - score)", value = delta$Delta_AUC),
      data.frame(Score = delta$Score, metric = "IDI", value = delta$IDI)
    )
    long <- long[is.finite(long$value), , drop = FALSE]
    if (nrow(long)) {
      p2 <- ggplot2::ggplot(long, ggplot2::aes(Score, value, fill = metric)) +
        ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.7), width = 0.65) +
        ggplot2::geom_text(
          ggplot2::aes(label = sprintf("%.3f", value)),
          position = ggplot2::position_dodge(width = 0.7),
          vjust = -0.3, size = 3, family = "serif"
        ) +
        ggplot2::scale_fill_manual(values = c(
          "Delta AUC (ML - score)" = "#3182BD", IDI = "#74C476"
        )) +
        ggplot2::labs(x = NULL, y = NULL, fill = NULL, title = "B  Improvement vs traditional scores") +
        ggplot2::theme_classic(base_size = 11, base_family = "serif") +
        ggplot2::theme(legend.position = "bottom", plot.title = ggplot2::element_text(face = "bold")) +
        ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.15)))
    }
  }
  out <- file.path(fig_dir, "Figure 5. AUC vs traditional scores.pdf")
  if (!is.null(p2) && requireNamespace("gridExtra", quietly = TRUE)) {
    grDevices::pdf(out, width = 11, height = 4.8)
    gridExtra::grid.arrange(p1, p2, ncol = 2, widths = c(1.15, 1))
    grDevices::dev.off()
  } else {
    ggplot2::ggsave(out, p1, width = 7, height = 4.2)
  }
  invisible(file.exists(out))
}

.nafld_nested_cv_table4_sci <- function(cfg, out_tables) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R/utils.R"), local = FALSE)
    source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  }
  p <- file.path(out_tables, "Table 4. Nested CV performance by space and algorithm.csv")
  if (!file.exists(p)) return(invisible(NULL))
  tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  if (!nrow(tab)) return(invisible(NULL))
  out <- tab
  if (all(c("auc_mean", "auc_sd") %in% names(out))) {
    out$`AUC (mean ± SD)` <- sprintf("%.3f ± %.3f", out$auc_mean, out$auc_sd)
  }
  keep <- intersect(c("space", "algorithm", "n_eval", "AUC (mean ± SD)", "auc_mean", "auc_sd"), names(out))
  body <- out[, keep, drop = FALSE]
  names(body)[names(body) == "space"] <- "Feature space"
  names(body)[names(body) == "algorithm"] <- "Algorithm"
  names(body)[names(body) == "n_eval"] <- "Outer folds"
  ml <- cfg$ml_small_sample %||% list()
  fn <- c(
    sprintf(
      "Nested cross-validation: outer %d-fold × %d repeats; inner %d-fold for tuning; feature selection repeated within each outer training fold.",
      as.integer(ml$cv_folds %||% 5L), as.integer(ml$cv_repeats %||% 10L), as.integer(ml$inner_folds %||% 5L)
    ),
    "Feature spaces: C = clinical; M = metabolomic; CM = clinical + metabolomic consensus features.",
    "Values are mean ± SD of AUCs across outer test folds.",
    "Best model selected by highest mean outer-loop AUC (used for Table 5–6 and Figures 3–5)."
  )
  sci_xlsx_single_header_booktabs(
    file.path(out_tables, "Table 4. Nested CV performance by space and algorithm.xlsx"),
    "Table 4. Nested CV performance by feature space and algorithm",
    body,
    footnotes = fn
  )
  invisible(TRUE)
}

#' R 版 2×4 表现图（对齐 python/ml_figure_combined_2x4.py；无 matplotlib 时兜底）
.nafld_plot_figure3_2x4_r <- function(study_root, out_pdf, algos = c("RF", "XGBoost", "LightGBM"), B = 500L) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || !requireNamespace("pROC", quietly = TRUE)) {
    return(invisible(FALSE))
  }
  if (!exists("ml_youden_threshold", mode = "function") || !exists("ml_bootstrap_metrics", mode = "function")) {
    return(invisible(FALSE))
  }
  csv <- file.path(study_root, "ml_python_results.csv")
  if (!file.exists(csv)) return(invisible(FALSE))
  allp <- utils::read.csv(csv, stringsAsFactors = FALSE)
  algos <- intersect(algos, unique(allp$model))
  if (!length(algos)) return(invisible(FALSE))
  cols <- c(
    Logistic = "#1B9E77", LASSO = "#D95F02", ElasticNet = "#7570B3",
    RF = "#A65628", XGBoost = "#FF7F00", LightGBM = "#984EA3",
    SVM = "#E41A1C", TabNet = "#377EB8"
  )

  .roc_df <- function(y, p, model) {
    r <- pROC::roc(y, p, quiet = TRUE, direction = "<")
    data.frame(fpr = 1 - r$specificities, tpr = r$sensitivities,
               model = model, auc = as.numeric(pROC::auc(r)), stringsAsFactors = FALSE)
  }
  .cal_df <- function(y, p, model, n_bins = 5L) {
    ok <- is.finite(y) & is.finite(p)
    y <- y[ok]; p <- p[ok]
    if (length(y) < 20L || sum(y) < 2L) return(NULL)
    br <- pretty(range(p), n = n_bins)
    if (length(br) < 3L) br <- seq(min(p), max(p), length.out = n_bins + 1L)
    g <- cut(p, breaks = unique(br), include.lowest = TRUE)
    mp <- tapply(p, g, mean, na.rm = TRUE)
    fr <- tapply(y, g, mean, na.rm = TRUE)
    data.frame(mp = as.numeric(mp), fr = as.numeric(fr), model = model, stringsAsFactors = FALSE)
  }
  .nb <- function(y, p, thr) {
    sapply(thr, function(t) {
      pred <- as.integer(p >= t)
      tp <- sum(pred == 1L & y == 1L)
      fp <- sum(pred == 1L & y == 0L)
      n <- length(y)
      tp / n - fp / n * (t / (1 - t))
    })
  }

  panels <- list()
  metrics_rows <- list()
  for (split_nm in c("oof", "val")) {
    lab <- if (identical(split_nm, "oof")) "Internal CV" else "Hold-out"
    roc_l <- list(); cal_l <- list()
    y0 <- NULL
    for (a in algos) {
      s <- allp[allp$model == a & allp$split == split_nm, , drop = FALSE]
      s <- s[order(s$idx), , drop = FALSE]
      if (!nrow(s)) next
      if (is.null(y0)) y0 <- s$y
      roc_l[[a]] <- .roc_df(s$y, s$p, a)
      cal_l[[a]] <- .cal_df(s$y, s$p, a)
      thr <- ml_youden_threshold(s$y, s$p)
      # use same thr from oof for val metrics when possible
      if (identical(split_nm, "val")) {
        so <- allp[allp$model == a & allp$split == "oof", , drop = FALSE]
        if (nrow(so)) thr <- ml_youden_threshold(so$y, so$p)
      }
      bm <- ml_bootstrap_metrics(s$y, s$p, thr, B = B, seed = if (split_nm == "oof") 1000L else 2000L)
      metrics_rows[[length(metrics_rows) + 1L]] <- data.frame(
        split = lab, model = a,
        metric = c("AUC", "Acc", "Sens", "Spec", "F1"),
        est = c(bm$point$auc, bm$point$acc, bm$point$sens, bm$point$spec, bm$point$f1),
        lo = c(bm$ci$auc[1], bm$ci$acc[1], bm$ci$sens[1], bm$ci$spec[1], bm$ci$f1[1]),
        hi = c(bm$ci$auc[2], bm$ci$acc[2], bm$ci$sens[2], bm$ci$spec[2], bm$ci$f1[2]),
        stringsAsFactors = FALSE
      )
    }
    roc_df <- do.call(rbind, roc_l)
    cal_df <- do.call(rbind, cal_l[!vapply(cal_l, is.null, logical(1))])
    # labels with AUC
    lab_map <- vapply(algos, function(a) {
      aa <- roc_df$auc[roc_df$model == a][1]
      sprintf("%s %.3f", a, aa)
    }, character(1))
    roc_df$model_lab <- lab_map[roc_df$model]
    p_roc <- ggplot2::ggplot(roc_df, ggplot2::aes(fpr, tpr, color = model_lab)) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey70", linewidth = 0.4) +
      ggplot2::geom_line(linewidth = 0.9) +
      ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::scale_color_manual(values = setNames(unname(cols[algos]), lab_map[algos])) +
      ggplot2::labs(x = "1 - Specificity", y = "Sensitivity", color = NULL, title = paste0(lab, " ROC")) +
      ggplot2::theme_classic(base_size = 9, base_family = "serif") +
      ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 6),
                     plot.title = ggplot2::element_text(face = "bold", size = 10))
    p_cal <- ggplot2::ggplot() +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey70") +
      ggplot2::labs(x = "Predicted risk", y = "Observed", title = paste0(lab, " calibration"), color = NULL) +
      ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::theme_classic(base_size = 9, base_family = "serif") +
      ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 6),
                     plot.title = ggplot2::element_text(face = "bold", size = 10))
    if (!is.null(cal_df) && nrow(cal_df)) {
      p_cal <- p_cal +
        ggplot2::geom_line(data = cal_df, ggplot2::aes(mp, fr, color = model), linewidth = 0.8) +
        ggplot2::geom_point(data = cal_df, ggplot2::aes(mp, fr, color = model), size = 1.6) +
        ggplot2::scale_color_manual(values = cols[intersect(names(cols), unique(cal_df$model))])
    }
    # DCA
    thr_grid <- seq(0.05, 0.80, length.out = 16)
    dca_l <- list()
    if (!is.null(y0)) {
      prev <- mean(y0)
      treat_all <- pmax(prev - (1 - prev) * (thr_grid / (1 - thr_grid)), 0)
      dca_l[[1]] <- data.frame(thr = thr_grid, nb = 0, model = "Treat none")
      dca_l[[2]] <- data.frame(thr = thr_grid, nb = treat_all, model = "Treat all")
      for (a in algos) {
        s <- allp[allp$model == a & allp$split == split_nm, , drop = FALSE]
        s <- s[order(s$idx), , drop = FALSE]
        if (!nrow(s)) next
        dca_l[[length(dca_l) + 1L]] <- data.frame(
          thr = thr_grid, nb = pmax(.nb(s$y, s$p, thr_grid), 0), model = a
        )
      }
    }
    dca_df <- do.call(rbind, dca_l)
    p_dca <- ggplot2::ggplot(dca_df, ggplot2::aes(thr, nb, color = model, linetype = model %in% c("Treat none", "Treat all"))) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::scale_linetype_manual(values = c(`TRUE` = "dashed", `FALSE` = "solid"), guide = "none") +
      ggplot2::labs(x = "Threshold", y = "Net benefit", color = NULL, title = paste0(lab, " DCA")) +
      ggplot2::theme_classic(base_size = 9, base_family = "serif") +
      ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 6),
                     plot.title = ggplot2::element_text(face = "bold", size = 10)) +
      ggplot2::coord_cartesian(ylim = c(0, NA))
    panels[[paste0(split_nm, "_roc")]] <- p_roc
    panels[[paste0(split_nm, "_cal")]] <- p_cal
    panels[[paste0(split_nm, "_dca")]] <- p_dca
  }
  met <- do.call(rbind, metrics_rows)
  p_met_oof <- ggplot2::ggplot(met[met$split == "Internal CV", ], ggplot2::aes(metric, est, color = model, group = model)) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi), width = 0.15, linewidth = 0.4) +
    ggplot2::scale_color_manual(values = cols[intersect(names(cols), unique(met$model))]) +
    ggplot2::labs(x = NULL, y = NULL, color = NULL, title = "Internal CV metrics (95% CI)") +
    ggplot2::theme_classic(base_size = 9, base_family = "serif") +
    ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 6),
                   plot.title = ggplot2::element_text(face = "bold", size = 10),
                   axis.text.x = ggplot2::element_text(angle = 20, hjust = 1))
  p_met_val <- ggplot2::ggplot(met[met$split == "Hold-out", ], ggplot2::aes(metric, est, color = model, group = model)) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi), width = 0.15, linewidth = 0.4) +
    ggplot2::scale_color_manual(values = cols[intersect(names(cols), unique(met$model))]) +
    ggplot2::labs(x = NULL, y = NULL, color = NULL, title = "Hold-out metrics (95% CI)") +
    ggplot2::theme_classic(base_size = 9, base_family = "serif") +
    ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 6),
                   plot.title = ggplot2::element_text(face = "bold", size = 10),
                   axis.text.x = ggplot2::element_text(angle = 20, hjust = 1))

  # Layout: row1 ROC_oof ROC_val cal_oof cal_val; row2 met_oof met_val dca_oof dca_val
  # Match python order more closely: ROC/ROC/cal/cal ; met/met/dca/dca
  plist <- list(
    panels$oof_roc, panels$val_roc, panels$oof_cal, panels$val_cal,
    p_met_oof, p_met_val, panels$oof_dca, panels$val_dca
  )
  labels <- LETTERS[1:8]
  if (requireNamespace("gridExtra", quietly = TRUE)) {
    grDevices::pdf(out_pdf, width = 14.2, height = 7.2)
    gridExtra::grid.arrange(
      grobs = lapply(seq_along(plist), function(i) {
        p <- plist[[i]] + ggplot2::labs(tag = labels[i]) +
          ggplot2::theme(plot.tag = ggplot2::element_text(face = "bold", size = 11))
        p
      }),
      ncol = 4
    )
    grDevices::dev.off()
  } else {
    return(invisible(FALSE))
  }
  invisible(file.exists(out_pdf))
}
