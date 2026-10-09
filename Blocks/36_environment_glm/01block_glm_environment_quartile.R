###############################################################################
#  glm_environment_quartile — 环境暴露 VOC 四分位 GLM（Crude / Model1 / Model2）
#
#  register_block: "glm_environment_quartile"
#  典型流水线: lasso_environment_voc → glm_environment_quartile
#
#  功能：
#    对 ctx$results$select_vocs 中每个 VOC 执行 Q1~Q4 四分位分组 logistic GLM；
#    三个模型：Crude（无调整）、Model1（基础人口学协变量）、Model2（全量协变量）；
#    按 GLM 三门禁筛选显著 VOC（均须 P < screening_p_threshold，默认 0.05）：
#      1) continuous：Crude 显著且 Model1、Model2 均显著
#      2) Q2/Q3/Q4 至少一个：Model2 显著
#      3) p for trend：Crude、Model1、Model2 均显著
#    未通过者不写入 select_vocs_final，下游 WQS/BKMR/RCS 等不再运行；全无通过则写空（report_all_vocs=TRUE 时仍导出全表）。
#    导出 SCI 三线格式表格（xlsx）。
#
#  # ── Bug 修复说明（相对原 C01_GLM.R）─────────────────────────────────────
#  Bug 1: data2[,i] → data2[[i]]（字符列名索引，更安全）
#  Bug 2: 四分位初始化为 'Q'，NA 或边界行不匹配时残留 'Q' 而非 NA；
#         修复: 改用 cut(right = FALSE, include.lowest = TRUE)，NA 自动为 NA
#  Bug 3: tmp$X12 < 0.05 对 character 型会静默返回 NA；
#         修复: suppressWarnings(as.numeric(...)) 先转换再比较
#  Bug 4: df[-c(seq(11, nrow(df), 10)), ] 行删除极脆弱，假设每 VOC 恰好 10 行；
#         修复: 通过模式匹配识别并移除重复表头行
#  Bug 5: source('./Step04_GLM/Tb_ModelGroup3_OR.R') 硬编码外部依赖；
#         修复: 函数内联（.env36_tb_model_3or）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data         = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results  = select_vocs   # 上游 lasso_environment_voc 写入
#  可选 ctx_results     = Model1Factors, final_features（亦可由 config 指定）
#
#  # ── 配置 config$glm_environment_quartile ─────────────────────────────────
#  glm_environment_quartile = list(
#    outcome_col           = NULL,            # 结局列名；NULL = config$data$outcome_column
#    analysis_group        = NULL,            # 病例组标签（编码为 1）
#    reference_group       = NULL,            # 对照组标签（编码为 0）
#    select_vocs           = NULL,            # VOC 列名；NULL = ctx$results$select_vocs
#    model1_factors        = NULL,            # Model1 协变量；NULL = ctx$results$Model1Factors
#    model2_factors        = NULL,            # Model2 协变量；NULL = ctx$results$final_features
#    locked_covariates     = NULL,            # 敏感性锁协变量（审稿口径：协变量集与主分析一致，仅换样本）：
#                                            #   命中 VOC 后跳过 covariate_search / force_report，直接沿用锁定的 Model1/Model2
#    screening_p_threshold = 0.05,           # continuous 行 Model2 p 筛选阈值
#    report_all_vocs       = FALSE,           # TRUE：不显著 VOC 仍写入 GLM 表（敏感性）；下游 select_vocs 仍只含过门禁者
#    label_mapping         = NULL,            # 命名向量 c(内部列名 = "展示名")，可选
#    table_filename        = NULL,            # NULL = "Table_GLM_Environment_Quartile.xlsx"
#    table_title           = NULL             # 表格标题；NULL = 自动生成
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$glm_environment_table  — 完整堆叠结果表（data.frame）
#      ctx$results$select_vocs_glm        — 通过 GLM 三门禁的 VOC
#      ctx$results$select_vocs_final      — 与 LASSO 候选池取交集后的最终 VOC（= select_vocs）
#  文件: Tables/Table_GLM_Environment_Quartile.xlsx
###############################################################################

# ── 辅助：暴露分组（四分位 / 五分位 / 三分位 / 二分位）────────────────────────
.env36_exposure_scheme_specs <- function() {
  list(
    quartile = list(n = 4L, probs = c(0, 0.25, 0.5, 0.75, 1), prefix = "Q"),
    quintile = list(n = 5L, probs = c(0, 0.2, 0.4, 0.6, 0.8, 1), prefix = "Q"),
    tertile  = list(n = 3L, probs = c(0, 1 / 3, 2 / 3, 1), prefix = "Q"),
    binary   = list(n = 2L, probs = c(0, 0.5, 1), prefix = "Q")
  )
}

.env36_format_cutoff_range <- function(lo, hi, is_last = FALSE) {
  if (isTRUE(is_last)) return(paste0("\u2265 ", round(hi, 2)))
  if (!is.finite(lo)) return(paste0("< ", round(hi, 2)))
  paste0(round(lo, 2), " -< ", round(hi, 2))
}

.env36_assign_exposure_groups <- function(data, col, scheme = "quartile") {
  scheme <- tolower(as.character(scheme %||% "quartile")[1L])
  specs <- .env36_exposure_scheme_specs()
  if (!scheme %in% names(specs)) scheme <- "quartile"
  sp <- specs[[scheme]]

  x  <- data[[col]]
  qs <- stats::quantile(x, probs = sp$probs, na.rm = TRUE)
  if (length(unique(qs)) < length(sp$probs)) {
    cli::cli_alert_warning(
      "  [{col}] {scheme} 分位点存在重复值，该 VOC 可能偏态严重，跳过。"
    )
    return(NULL)
  }

  labels <- paste0(sp$prefix, seq_len(sp$n))
  data$NewGroup <- cut(
    x,
    breaks = qs,
    labels = labels,
    right = FALSE,
    include.lowest = TRUE
  )
  data$NewNum <- as.numeric(data$NewGroup)

  cutoffs <- setNames(character(sp$n), labels)
  for (k in seq_len(sp$n)) {
    lo <- if (k == 1L) NA_real_ else qs[k]
    hi <- qs[k + 1L]
    cutoffs[[k]] <- .env36_format_cutoff_range(lo, hi, is_last = k == sp$n)
  }

  list(
    data = data,
    cutoffs = cutoffs,
    group_labels = labels,
    scheme = scheme,
    non_ref_groups = labels[-1L]
  )
}

.env36_assign_quartiles <- function(data, col) {
  .env36_assign_exposure_groups(data, col, "quartile")
}

# 静默探测某 VOC 在指定分位方案下能否成功分组（用于全局方案选择）
.env36_probe_exposure_groups <- function(data, col, scheme = "quartile") {
  scheme <- tolower(as.character(scheme %||% "quartile")[1L])
  specs <- .env36_exposure_scheme_specs()
  if (!scheme %in% names(specs)) return(FALSE)
  if (!as.character(col)[1L] %in% names(data)) return(FALSE)
  sp <- specs[[scheme]]
  x <- data[[col]]
  qs <- stats::quantile(x, probs = sp$probs, na.rm = TRUE)
  length(unique(qs)) >= length(sp$probs)
}

# 全队列 VOC 共用同一暴露分位方案（协变量仍可逐 VOC 独立）
.env36_select_global_exposure_scheme <- function(vocs, data, bl_cfg) {
  fixed <- as.character(bl_cfg$exposure_scheme %||% "")[1L]
  if (nzchar(fixed)) {
    cli::cli_alert_info("glm 全局暴露分位: 固定为 {fixed}（config$exposure_scheme）")
    return(fixed)
  }

  primary <- as.character(bl_cfg$exposure_schemes_primary %||% "quartile")
  fallback <- as.character(bl_cfg$exposure_schemes_fallback %||% character(0))
  schemes <- unique(c(primary, fallback))
  schemes <- schemes[nzchar(schemes)]
  vocs <- as.character(vocs[nzchar(vocs)])
  if (!length(schemes) || !length(vocs)) return("quartile")

  best <- NULL
  best_n <- -1L
  for (scheme in schemes) {
    n <- sum(vapply(
      vocs,
      function(v) .env36_probe_exposure_groups(data, v, scheme),
      logical(1L)
    ))
    if (n == length(vocs)) {
      cli::cli_alert_info(
        "glm 全局暴露分位: 选用 {scheme}（全部 {length(vocs)} 个 VOC 可分组）"
      )
      return(scheme)
    }
    if (n > best_n) {
      best_n <- n
      best <- scheme
    }
  }
  if (!is.null(best) && best_n > 0L) {
    cli::cli_alert_warning(
      "glm 全局暴露分位: 选用 {best}（{best_n}/{length(vocs)} 个 VOC 可分组；其余 VOC 将跳过）"
    )
    return(best)
  }
  cli::cli_alert_warning("glm 全局暴露分位: 无可用方案，回退 quartile")
  "quartile"
}

# ── 辅助：三模型 OR 表（内联自 Tb_ModelGroup3_OR，修复 data[,i] 为 data[[col]]）
.env36_tb_model_3or <- function(ResultName, ContinuousName, FactorName, TrendName,
                                 Data, Model1Factors, Model2Factors,
                                 cutoffs, group_labels, include_continuous = TRUE,
                                 use_wald_ci = FALSE,
                                 wt_col = "new_Weight") {
  # 移除模型协变量中与主暴露、分组变量冲突的列
  M1 <- setdiff(Model1Factors, c(ContinuousName, FactorName, TrendName, ResultName))
  M2 <- setdiff(Model2Factors, c(ContinuousName, FactorName, TrendName, ResultName))
  M1 <- intersect(M1, names(Data))
  M2 <- intersect(M2, names(Data))

  # 调查权重（加权 logistic）
  wts <- if (!is.null(wt_col) && nzchar(wt_col) && wt_col %in% names(Data)) {
    w <- as.numeric(Data[[wt_col]])
    w[!is.finite(w) | w <= 0] <- NA_real_
    # 归一化至均值=1，避免 glm() 将大数值调查权重误作频次权重，导致 OR=Inf
    w_mean <- mean(w, na.rm = TRUE)
    if (is.finite(w_mean) && w_mean > 0) w <- w / w_mean
    w
  } else {
    NULL
  }

  fml_f01 <- stats::as.formula(paste0(ResultName, "~", FactorName))
  fml_f02 <- stats::as.formula(paste0(ResultName, "~", paste(c(FactorName, M1), collapse = "+")))
  fml_f03 <- stats::as.formula(paste0(ResultName, "~", paste(c(FactorName, M2), collapse = "+")))
  fml_t01 <- stats::as.formula(paste0(ResultName, "~", TrendName))
  fml_t02 <- stats::as.formula(paste0(ResultName, "~", paste(c(TrendName, M1), collapse = "+")))
  fml_t03 <- stats::as.formula(paste0(ResultName, "~", paste(c(TrendName, M2), collapse = "+")))

  mf  <- stats::glm(fml_f01, data = Data, family = stats::binomial, weights = wts)
  mf2 <- stats::glm(fml_f02, data = Data, family = stats::binomial, weights = wts)
  mf3 <- stats::glm(fml_f03, data = Data, family = stats::binomial, weights = wts)
  mt  <- stats::glm(fml_t01, data = Data, family = stats::binomial, weights = wts)
  mt2 <- stats::glm(fml_t02, data = Data, family = stats::binomial, weights = wts)
  mt3 <- stats::glm(fml_t03, data = Data, family = stats::binomial, weights = wts)

  n_total <- nrow(Data)
  cnt     <- table(Data[[FactorName]])

  .ci <- function(m, row) {
    if (isTRUE(use_wald_ci)) {
      se <- summary(m)$coefficients[row, 2L]
      b  <- stats::coef(m)[row]
      paste0("(", round(exp(b - 1.96 * se), 3), ",", round(exp(b + 1.96 * se), 3), ")")
    } else {
      ci <- tryCatch(suppressMessages(stats::confint(m)), error = function(e) NULL)
      if (is.null(ci) || nrow(ci) < row || !all(is.finite(ci[row, ]))) {
        se <- summary(m)$coefficients[row, 2L]
        b  <- stats::coef(m)[row]
        paste0("(", round(exp(b - 1.96 * se), 3), ",", round(exp(b + 1.96 * se), 3), ")")
      } else {
        paste0("(", round(exp(ci[row, 1L]), 3), ",", round(exp(ci[row, 2L]), 3), ")")
      }
    }
  }
  .pct <- function(lv) {
    n <- as.numeric(cnt[lv])
    paste0(n, "(", round(n / n_total * 100, 2), "%)")
  }

  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)",
             "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11L))

  ref_lv   <- group_labels[1L]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")

  non_ref_lvs  <- group_labels[-1L]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(ii) {
    lv  <- non_ref_lvs[ii]
    idx <- ii + 1L
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(stats::coef(mf)[idx]),  3), .ci(mf,  idx),
      .env36_fmt_glm_p(summary(mf)$coefficients[idx, 4L]),
      round(exp(stats::coef(mf2)[idx]), 3), .ci(mf2, idx),
      .env36_fmt_glm_p(summary(mf2)$coefficients[idx, 4L]),
      round(exp(stats::coef(mf3)[idx]), 3), .ci(mf3, idx),
      .env36_fmt_glm_p(summary(mf3)$coefficients[idx, 4L]))
  })

  Line_trend <- c("p for trend", rep("", 4L),
                  .env36_fmt_glm_p(summary(mt)$coefficients[2L, 4L]),
                  "", "",
                  .env36_fmt_glm_p(summary(mt2)$coefficients[2L, 4L]),
                  "", "",
                  .env36_fmt_glm_p(summary(mt3)$coefficients[2L, 4L]))

  if (include_continuous) {
    fml_c01 <- stats::as.formula(paste0(ResultName, "~", ContinuousName))
    fml_c02 <- stats::as.formula(paste0(ResultName, "~",
      paste(c(ContinuousName, M1), collapse = "+")))
    fml_c03 <- stats::as.formula(paste0(ResultName, "~",
      paste(c(ContinuousName, M2), collapse = "+")))
    mc  <- stats::glm(fml_c01, data = Data, family = stats::binomial, weights = wts)
    mc2 <- stats::glm(fml_c02, data = Data, family = stats::binomial, weights = wts)
    mc3 <- stats::glm(fml_c03, data = Data, family = stats::binomial, weights = wts)

    .ci_c <- function(m) {
      if (isTRUE(use_wald_ci)) {
        se <- summary(m)$coefficients[2L, 2L]
        b  <- stats::coef(m)[2L]
        paste0("(", round(exp(b - 1.96 * se), 3), ",", round(exp(b + 1.96 * se), 3), ")")
      } else {
        ci <- tryCatch(suppressMessages(stats::confint(m)), error = function(e) NULL)
        if (is.null(ci) || nrow(ci) < 2L || !all(is.finite(ci[2L, ]))) {
          se <- summary(m)$coefficients[2L, 2L]
          b  <- stats::coef(m)[2L]
          paste0("(", round(exp(b - 1.96 * se), 3), ",", round(exp(b + 1.96 * se), 3), ")")
        } else {
          paste0("(", round(exp(ci[2L, 1L]), 3), ",", round(exp(ci[2L, 2L]), 3), ")")
        }
      }
    }
    Line3 <- c(ContinuousName,                    rep("", 11L))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(stats::coef(mc)[2L]),  3), .ci_c(mc),
               .env36_fmt_glm_p(summary(mc)$coefficients[2L, 4L]),
               round(exp(stats::coef(mc2)[2L]), 3), .ci_c(mc2),
               .env36_fmt_glm_p(summary(mc2)$coefficients[2L, 4L]),
               round(exp(stats::coef(mc3)[2L]), 3), .ci_c(mc3),
               .env36_fmt_glm_p(summary(mc3)$coefficients[2L, 4L]))
    rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref),
                            lines_nonref, list(Line_trend)))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref),
                            lines_nonref, list(Line_trend)))
  }
  rownames(rt) <- NULL
  rt
}

# ── 辅助：P 值列格式化（0 / 极小值 → 'P < 0.001'）──────────────────────────
.env36_fmt_glm_p <- function(p) {
  if (length(p) != 1L || is.na(p)) return("")
  p <- suppressWarnings(as.numeric(p))
  if (!is.finite(p)) return(as.character(p))
  if (p < 0.001) return("P < 0.001")
  pub_format_p_cell(p)
}

.env36_format_pval_cols <- function(rt) {
  for (col in c("X6", "X9", "X12")) {
    if (!col %in% names(rt)) next
    rt[[col]] <- vapply(rt[[col]], function(v) {
      if (is.character(v) && v %in% c("0", "0.0000", "0.000")) return("P < 0.001")
      num <- suppressWarnings(as.numeric(v))
      if (!is.na(num) && is.finite(num) && num == 0) return("P < 0.001")
      if (!is.na(num) && is.finite(num) && num < 0.001) return("P < 0.001")
      if (is.character(v) && nzchar(v)) return(v)
      .env36_fmt_glm_p(num)
    }, character(1L))
  }
  rt
}

# ── 辅助：从堆叠表格中提取 continuous 行并筛选显著 VOC（三模型均显著）────────
.env36_screen_continuous_p <- function(tab, p_threshold) {
  if (exists("environment_screen_glm_continuous_table", mode = "function")) {
    return(environment_screen_glm_continuous_table(tab, p_threshold))
  }
  if (is.null(tab) || !nrow(tab)) return(character(0))
  x1       <- as.character(tab$X1)
  cont_idx <- grepl(" continuous", x1, fixed = TRUE)
  if (!any(cont_idx)) return(character(0))

  keep <- character(0)
  for (i in which(cont_idx)) {
    rt <- tab[i, , drop = FALSE]
    if (!environment_is_p_significant(rt$X6[i], p_threshold)) next
    if (!environment_is_p_significant(rt$X9[i], p_threshold)) next
    if (!environment_is_p_significant(rt$X12[i], p_threshold)) next
    keep <- c(keep, gsub(" continuous", "", x1[i], fixed = TRUE))
  }
  unique(keep[nzchar(keep)])
}

# ── 辅助：构建单 VOC GLM 堆叠表 ─────────────────────────────────────────────
.env36_build_glm_rt <- function(i, qres, outcome_col, m1, m2, use_wald_ci = FALSE,
                                wt_col = "new_Weight") {
  m1 <- intersect(as.character(m1), names(qres$data))
  m2 <- intersect(as.character(m2), names(qres$data))
  if (!length(m1)) m1 <- m2
  if (!length(m2)) return(NULL)
  gl <- qres$group_labels %||% c("Q1", "Q2", "Q3", "Q4")
  tb01 <- tryCatch(
    .env36_tb_model_3or(
      ResultName = outcome_col, ContinuousName = i,
      FactorName = "NewGroup", TrendName = "NewNum",
      Data = qres$data, Model1Factors = m1, Model2Factors = m2,
      cutoffs = qres$cutoffs, group_labels = gl,
      include_continuous = TRUE, use_wald_ci = use_wald_ci,
      wt_col = wt_col
    ),
    error = function(e) NULL
  )
  if (is.null(tb01)) return(NULL)
  rt <- .env36_format_pval_cols(data.frame(tb01, stringsAsFactors = FALSE))
  rownames(rt) <- NULL
  names(rt) <- paste0("X", seq_len(ncol(rt)))
  rt
}

.env36_glm_screen_chk <- function(rt, bl_cfg, p_threshold, non_ref_groups = NULL) {
  nrg <- non_ref_groups %||% c("Q2", "Q3", "Q4")
  if (exists("environment_glm_screen_pass", mode = "function")) {
    environment_glm_screen_pass(
      rt,
      p_threshold = p_threshold,
      require_quartile_any = isTRUE(bl_cfg$require_quartile_any_significant %||% TRUE),
      require_trend = isTRUE(bl_cfg$require_trend_significant %||% TRUE),
      non_ref_groups = nrg
    )
  } else if (exists("environment_glm_continuous_pass", mode = "function")) {
    environment_glm_continuous_pass(rt, p_threshold)
  } else {
    list(pass = TRUE, reason = "ok")
  }
}

.env36_continuous_adjusted_significant <- function(rt, p_threshold) {
  if (!exists("environment_glm_continuous_pvals", mode = "function")) return(FALSE)
  pv <- environment_glm_continuous_pvals(rt)
  if (!environment_is_p_significant(pv$crude, p_threshold)) return(FALSE)
  environment_glm_pvals_significant(pv, c("model1", "model2"), p_threshold)
}

.env36_split_demo_clinical <- function(vars, cfg, data, bl_cfg = list()) {
  vars <- unique(intersect(as.character(vars), names(data)))
  if (!length(vars)) {
    return(list(demo_pool = character(0), clinical_pool = character(0)))
  }
  mv_cfg <- cfg$multivariate_nhanes %||% list()
  demo_keywords <- as.character(mv_cfg$demo_keywords %||% c(
    "Age", "Gender", "Sex", "Race", "Ethnic", "PIR", "Education", "Income", "Marital"
  ))
  idx_excl <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      character(0)
  )
  if (exists(".lnw00_split_vif_final_models", mode = "function")) {
    split <- .lnw00_split_vif_final_models(vars, cfg, data, idx_excl[1L] %||% "BMI", bl_cfg)
    demo <- intersect(split$M1, names(data))
    clin <- setdiff(intersect(split$M2, names(data)), demo)
    return(list(demo_pool = demo, clinical_pool = clin))
  }
  demo_pattern <- paste(demo_keywords, collapse = "|")
  demo <- vars[grepl(demo_pattern, vars, ignore.case = TRUE)]
  clin <- setdiff(vars, demo)
  list(demo_pool = demo, clinical_pool = clin)
}

.env36_table1_var_pool <- function(ctx, data, cfg, voc = NULL) {
  t1 <- unique(as.character(ctx$results$table1_var_order %||% character(0)))
  if (!length(t1)) {
    t1 <- unique(c(
      as.character(ctx$results$continuous_vars %||% character(0)),
      as.character(ctx$results$categorical_vars %||% character(0))
    ))
  }
  if (!length(t1)) {
    t1 <- unique(as.character(ctx$results$sig_vars %||% character(0)))
  }
  t1 <- intersect(t1, names(data))
  voc_cols <- if (exists("environment_voc_allowlist", mode = "function")) {
    environment_voc_allowlist(data, cfg)
  } else {
    as.character((cfg$environment %||% list())$voc_columns %||% character(0))
  }
  outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Group")
  idx_excl <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      voc %||%
      character(0)
  )
  setdiff(t1, unique(c(voc_cols, outcome_col, idx_excl)))
}

.env36_univariate_outcome_p <- function(data, outcome_col, vars) {
  vars <- unique(intersect(as.character(vars), names(data)))
  vars <- setdiff(vars, outcome_col)
  if (!length(vars)) return(setNames(numeric(0), character(0)))
  pvals <- vapply(vars, function(v) {
    suppressWarnings(tryCatch({
      fml <- stats::as.formula(paste(outcome_col, "~", v))
      summary(stats::glm(fml, data = data, family = stats::binomial))$coefficients[2L, 4L]
    }, error = function(e) NA_real_))
  }, numeric(1))
  pvals <- pvals[is.finite(pvals)]
  if (!length(pvals)) return(setNames(numeric(0), character(0)))
  pvals[order(pvals)]
}

.env36_prefilter_clinical_pool <- function(ctx, data, cfg, clinical_pool, outcome_col,
                                           voc = NULL, bl_cfg = list()) {
  clinical_pool <- unique(intersect(as.character(clinical_pool), names(data)))
  if (!length(clinical_pool)) return(clinical_pool)

  max_n <- as.integer(bl_cfg$table1_clinical_prefilter_n %||% 15L)[1L]
  pre_p <- as.numeric(bl_cfg$table1_prefilter_p %||% 0.20)[1L]

  p_out <- .env36_univariate_outcome_p(data, outcome_col, clinical_pool)
  keep <- names(p_out)[p_out <= pre_p]
  if (!length(keep)) keep <- names(p_out)[seq_len(min(max_n, length(p_out)))]

  boost <- unique(c(
    as.character(ctx$results$sig_vars %||% character(0)),
    as.character(ctx$results$vif_final_pass %||% character(0)),
    as.character(ctx$results$tb1 %||% character(0))
  ))
  boost <- intersect(boost, clinical_pool)
  ranked <- c(
    intersect(names(p_out), boost),
    setdiff(names(p_out), boost)
  )
  ranked <- ranked[nzchar(ranked)]
  if (length(ranked) > max_n) ranked <- ranked[seq_len(max_n)]
  unique(intersect(ranked, clinical_pool))
}

.env36_rank_clinical_for_forward <- function(data, outcome_col, clinical_pool, exposure_col) {
  clinical_pool <- unique(intersect(as.character(clinical_pool), names(data)))
  clinical_pool <- setdiff(clinical_pool, c(outcome_col, exposure_col))
  if (!length(clinical_pool)) return(clinical_pool)
  p_out <- .env36_univariate_outcome_p(data, outcome_col, clinical_pool)
  names(p_out)
}

.env36_lite_continuous_score <- function(lite) {
  if (!isTRUE(lite$ok)) return(-Inf)
  pmax <- max(
    suppressWarnings(as.numeric(lite$p_crude)),
    suppressWarnings(as.numeric(lite$p_m1)),
    suppressWarnings(as.numeric(lite$p_m2)),
    na.rm = TRUE
  )
  if (!is.finite(pmax) || pmax <= 0) return(100)
  -log10(pmax)
}

.env36_try_m1_m2_lite <- function(i, qres, outcome_col, m1_try, m2_try, p_threshold) {
  m1_try <- unique(intersect(as.character(m1_try), names(qres$data)))
  m2_try <- unique(intersect(as.character(m2_try), names(qres$data)))
  if (!length(m1_try) || !length(m2_try)) return(NULL)
  lite <- .env36_light_continuous_significant(i, qres, outcome_col, m1_try, m2_try, p_threshold)
  if (!isTRUE(lite$ok)) return(NULL)
  list(
    m1 = m1_try, m2 = m2_try,
    clinical = setdiff(m2_try, m1_try),
    lite = lite,
    score = .env36_lite_continuous_score(lite)
  )
}

.env36_try_m1_m2_finalize <- function(i, qres, outcome_col, m1_try, m2_try, bl_cfg, p_threshold) {
  lite <- .env36_try_m1_m2_lite(i, qres, outcome_col, m1_try, m2_try, p_threshold)
  if (is.null(lite)) return(NULL)
  fin <- .env36_finalize_glm_fit(i, qres, outcome_col, m1_try, m2_try, bl_cfg)
  if (is.null(fin$rt)) return(NULL)
  chk <- .env36_glm_screen_chk(
    fin$rt, bl_cfg, p_threshold, non_ref_groups = qres$non_ref_groups
  )
  if (!isTRUE(chk$pass)) return(NULL)
  list(rt = fin$rt, model1 = m1_try, model2 = m2_try)
}

.env36_forward_clinical_select <- function(i, qres, outcome_col, m1_try, clinical_ranked,
                                           bl_cfg, p_threshold) {
  m1_try <- unique(intersect(as.character(m1_try), names(qres$data)))
  clin_ranked <- setdiff(unique(as.character(clinical_ranked)), m1_try)
  max_k <- as.integer(bl_cfg$clinical_forward_max %||% 8L)[1L]
  if (!length(clin_ranked)) {
    return(list(clinical = character(0), m2 = m1_try))
  }

  selected <- character(0)
  best_p2 <- Inf
  for (cv in clin_ranked) {
    trial <- c(selected, cv)
    m2 <- unique(c(m1_try, trial))
    lite <- .env36_light_continuous_significant(
      i, qres, outcome_col, m1_try, m2, p_threshold
    )
    p2 <- suppressWarnings(as.numeric(lite$p_m2))
    if (!is.finite(p2)) next
    improves <- is.finite(best_p2) && (
      p2 < best_p2 * 0.99 ||
        (environment_is_p_significant(p2, p_threshold) &&
           !environment_is_p_significant(best_p2, p_threshold))
    )
    if (length(selected) == 0L || improves) {
      selected <- trial
      best_p2 <- p2
    }
    if (isTRUE(lite$ok)) break
    if (length(selected) >= max_k) break
  }
  list(clinical = selected, m2 = unique(c(m1_try, selected)))
}

.env36_demo_m1_candidates <- function(demo_pool, bl_cfg) {
  demo_pool <- unique(as.character(demo_pool))
  demo_pool <- demo_pool[nzchar(demo_pool)]
  if (!length(demo_pool)) return(list())
  rs_cfg <- bl_cfg$random_search %||% list()
  max_size <- as.integer(bl_cfg$demo_search_max_size %||% 3L)[1L]
  max_size <- min(max_size, length(demo_pool))
  rand_n <- as.integer(bl_cfg$demo_random_attempts %||% 50L)[1L]
  out <- list()
  for (k in seq_len(max_size)) {
    n_comb <- as.numeric(choose(length(demo_pool), k))
    if (n_comb > 0 && n_comb <= 20) {
      out <- c(out, utils::combn(demo_pool, k, simplify = FALSE))
    }
  }
  if (!length(out)) {
    for (j in seq_len(rand_n)) {
      out[[j]] <- sample(demo_pool, max(1L, min(max_size, length(demo_pool))), replace = FALSE)
    }
  }
  out
}

.env36_per_voc_covariates_enabled <- function(bl_cfg) {
  isTRUE(bl_cfg$per_voc_covariates %||% TRUE)
}

# 敏感性锁协变量：命中 VOC → 直接用主分析 Model1/Model2（不搜协变量）
# locked_covariates = list(URX2MH = list(model1 = c("Percentage_of_neutrophils"), model2 = c("Percentage_of_neutrophils","SBP")), ...)
.env36_locked_covs_for_voc <- function(i, bl_cfg, data) {
  lk <- bl_cfg$locked_covariates
  if (is.null(lk) || !is.list(lk)) return(NULL)
  ent <- lk[[i]]
  if (is.null(ent)) ent <- lk[["*"]]
  if (is.null(ent)) return(NULL)
  m1 <- unique(intersect(as.character(ent$model1 %||% character(0)), names(data)))
  m2 <- unique(intersect(as.character(ent$model2 %||% character(0)), names(data)))
  if (!length(m1) && !length(m2)) return(NULL)
  if (!length(m1)) m1 <- intersect(m2, names(data))[seq_len(min(1L, length(m2)))] %||% character(0)
  if (!length(m1)) return(NULL)
  if (!length(m2)) m2 <- m1
  m2 <- unique(c(m1, setdiff(m2, m1)))
  list(model1 = m1, model2 = m2)
}

.env36_fit_glm_locked_covariates <- function(i, data, outcome_col, bl_cfg,
                                             fixed_scheme = NULL, wt_col = "new_Weight") {
  lk <- .env36_locked_covs_for_voc(i, bl_cfg, data)
  if (is.null(lk)) return(NULL)
  scheme <- as.character(fixed_scheme %||% "quartile")[1L]
  if (!nzchar(scheme)) scheme <- "quartile"
  qres <- .env36_assign_exposure_groups(data, i, scheme)
  if (is.null(qres)) return(NULL)
  fin <- .env36_finalize_glm_fit(i, qres, outcome_col, lk$model1, lk$model2, bl_cfg, wt_col = wt_col)
  if (is.null(fin)) return(NULL)
  c(fin, list(
    covariate_source = "locked_main",
    pool_tag = "主分析锁定",
    exposure_scheme = scheme,
    covariate_search = FALSE,
    locked_cov = TRUE
  ))
}

.env36_crude_continuous_p <- function(i, data, outcome_col, wt_col = "new_Weight") {
  wts <- if (!is.null(wt_col) && nzchar(wt_col) && wt_col %in% names(data)) {
    w <- as.numeric(data[[wt_col]])
    w[!is.finite(w) | w <= 0] <- NA_real_
    w
  } else NULL
  suppressWarnings(tryCatch({
    fml <- stats::as.formula(paste(outcome_col, "~", i))
    summary(stats::glm(fml, data = data, family = stats::binomial,
                       weights = wts))$coefficients[2L, 4L]
  }, error = function(e) NA_real_))
}

.env36_crude_significant <- function(i, data, outcome_col, p_threshold, wt_col = "new_Weight") {
  p_crude <- .env36_crude_continuous_p(i, data, outcome_col, wt_col = wt_col)
  environment_is_p_significant(p_crude, p_threshold)
}

.env36_try_upstream_covariates <- function(i, qres, outcome_col, ctx, data, bl_cfg, p_threshold) {
  if (.env36_per_voc_covariates_enabled(bl_cfg)) return(NULL)
  if (!isTRUE(bl_cfg$use_final_covariates %||% TRUE)) return(NULL)
  m1 <- unique(intersect(as.character(ctx$results$Model1Factors %||% character(0)), names(data)))
  m2 <- unique(intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data)))
  m2 <- unique(c(m1, setdiff(m2, m1)))
  if (!length(m1) || !length(m2)) return(NULL)
  hit <- .env36_try_m1_m2_finalize(i, qres, outcome_col, m1, m2, bl_cfg, p_threshold)
  if (is.null(hit)) return(NULL)
  c(hit, list(
    covariate_source = "upstream",
    pool_tag = "上游多因素",
    covariate_search = FALSE,
    sample_factors = m1,
    sample_clinical = setdiff(m2, m1)
  ))
}

.env36_fast_covariate_search <- function(i, qres, outcome_col, pools, bl_cfg, p_threshold) {
  if (!isTRUE(bl_cfg$covariate_search %||% TRUE)) return(NULL)

  top_n <- as.integer(bl_cfg$full_screen_top_n %||% 5L)[1L]
  demo_pool <- unique(intersect(as.character(pools$demo_pool), names(qres$data)))
  clinical_pool <- unique(intersect(as.character(pools$clinical_pool), names(qres$data)))
  pool_tag <- pools$pool_tag %||% pools$source %||% "covariate"

  lite_candidates <- list()
  add_lite <- function(m1, m2, clinical = setdiff(m2, m1)) {
    ent <- .env36_try_m1_m2_lite(i, qres, outcome_col, m1, m2, p_threshold)
    if (is.null(ent)) return()
    lite_candidates[[length(lite_candidates) + 1L]] <<- ent
  }

  add_lite(pools$model1_default, pools$model2_default)

  clin_ranked <- .env36_rank_clinical_for_forward(
    qres$data, outcome_col, clinical_pool, i
  )
  for (m1_try in .env36_demo_m1_candidates(demo_pool, bl_cfg)) {
    fwd <- .env36_forward_clinical_select(
      i, qres, outcome_col, m1_try, clin_ranked, bl_cfg, p_threshold
    )
    add_lite(m1_try, fwd$m2, fwd$clinical)
  }

  if (!length(lite_candidates)) return(NULL)

  scores <- vapply(lite_candidates, function(x) x$score, numeric(1))
  ord <- order(scores, decreasing = TRUE)
  for (j in ord[seq_len(min(top_n, length(ord)))]) {
    cnd <- lite_candidates[[j]]
    hit <- .env36_try_m1_m2_finalize(
      i, qres, outcome_col, cnd$m1, cnd$m2, bl_cfg, p_threshold
    )
    if (!is.null(hit)) {
      cli::cli_alert_success(
        "  [{i}] 快速协变量命中 ({pool_tag}, M1={paste(cnd$m1, collapse=', ')}, M2+临床={paste(cnd$clinical, collapse=', ')})"
      )
      return(c(hit, list(
        sample_factors = cnd$m1,
        sample_clinical = cnd$clinical,
        covariate_search = TRUE
      )))
    }
  }
  NULL
}

.env36_resolve_covariate_pools <- function(ctx, bl_cfg, data, voc = NULL, source = "vif_uni",
                                           outcome_col = NULL) {
  cfg <- ctx$config %||% list()
  source <- tolower(as.character(source %||% "vif_uni")[1L])
  outcome_col <- as.character(
    outcome_col %||% (cfg$data %||% list())$outcome_column %||% "Group"
  )[1L]

  if (identical(source, "table1")) {
    base_pool <- .env36_table1_var_pool(ctx, data, cfg, voc = voc)
    split <- .env36_split_demo_clinical(base_pool, cfg, data, bl_cfg)
    demo_pool <- split$demo_pool
    clinical_pool <- .env36_prefilter_clinical_pool(
      ctx, data, cfg, split$clinical_pool, outcome_col, voc = voc, bl_cfg = bl_cfg
    )
    pool_tag <- sprintf("Table1预筛(%d)", length(clinical_pool))
  } else {
    mv_cfg <- cfg$multivariate_nhanes %||% list()
    demo_keywords <- as.character(mv_cfg$demo_keywords %||% c(
      "Age", "Gender", "Sex", "Race", "Ethnic", "PIR", "Education", "Income", "Marital"
    ))

    vif_pool <- unique(as.character(ctx$results$vif_final_pass %||% character(0)))
    uni_pool <- unique(as.character(ctx$results$tb1 %||% ctx$results$sig_vars %||% character(0)))
    if (length(uni_pool)) {
      vif_pool <- intersect(vif_pool, uni_pool)
    }
    if (!length(vif_pool)) {
      vif_pool <- unique(as.character(
        ctx$results$final_features %||% ctx$results$Model2Factors %||% character(0)
      ))
    }
    vif_pool <- intersect(vif_pool, names(data))
    # 排除当前 VOC 及全部 VOC 列，避免 VOC 进入协变量池
    voc_excl <- unique(c(
      as.character(voc %||% character(0)),
      as.character((cfg$incidence %||% list())$index_exclude_vars %||% character(0)),
      as.character(ctx$results$voc_columns %||% character(0)),
      as.character((cfg$incidence %||% list())$index_var %||% character(0)),
      as.character((cfg$logistic %||% list())$index_var %||% character(0))
    ))
    voc_excl <- voc_excl[nzchar(voc_excl)]
    idx_excl <- voc_excl
    vif_pool <- setdiff(vif_pool, idx_excl)

    m1_ctx <- intersect(as.character(ctx$results$Model1Factors %||% character(0)), names(data))
    m2_ctx <- intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data))

    if (length(m1_ctx)) {
      demo_pool <- intersect(m1_ctx, vif_pool)
      if (!length(demo_pool)) demo_pool <- setdiff(m1_ctx, idx_excl)
    } else if (exists(".lnw00_split_vif_final_models", mode = "function") && length(vif_pool)) {
      # 环境流水线无单一 index_var，用第一个非空 demo 关键词作占位（不用 "BMI"）
      split_ref <- if (length(voc_excl)) voc_excl[1L] else ""
      split <- .lnw00_split_vif_final_models(vif_pool, cfg, data, split_ref, bl_cfg)
      demo_pool <- intersect(split$M1, names(data))
      if (!length(m2_ctx)) m2_ctx <- intersect(split$M2, names(data))
    } else {
      demo_pattern <- paste(demo_keywords, collapse = "|")
      demo_pool <- vif_pool[grepl(demo_pattern, vif_pool, ignore.case = TRUE)]
    }

    if (length(m2_ctx)) {
      clinical_pool <- setdiff(m2_ctx, demo_pool)
    } else {
      clinical_pool <- setdiff(vif_pool, demo_pool)
    }
    pool_tag <- "VIF+单因素"
  }

  rs_cfg <- bl_cfg$random_search %||% list()
  rs_seed <- rs_cfg$seed
  voc_key <- sum(utf8ToInt(as.character(voc %||% "voc")), na.rm = TRUE)
  if (!is.null(rs_seed)) set.seed(as.integer(rs_seed)[1L] + voc_key)

  n_init <- max(1L, as.integer(rs_cfg$initial_sample_n %||% 1L))
  n_init <- min(n_init, length(demo_pool))
  model1_default <- if (length(demo_pool) && n_init > 0L) {
    sample(demo_pool, n_init, replace = FALSE)
  } else {
    demo_pool
  }
  use_clin_search <- identical(source, "table1") ||
    length(clinical_pool) > as.integer(bl_cfg$clinical_search_if_pool_gt %||% 5L)
  if (isTRUE(use_clin_search) && length(clinical_pool)) {
    n_clin_init <- min(
      length(clinical_pool),
      max(1L, as.integer((bl_cfg$random_search %||% list())$initial_clinical_n %||% 3L))
    )
    clin_init <- sample(clinical_pool, n_clin_init, replace = FALSE)
    model2_default <- unique(c(model1_default, clin_init))
  } else {
    model2_default <- unique(c(model1_default, clinical_pool))
  }

  list(
    demo_pool = demo_pool,
    clinical_pool = clinical_pool,
    model1_default = model1_default,
    model2_default = model2_default,
    source = source,
    pool_tag = pool_tag,
    search_clinical_subset = isTRUE(use_clin_search)
  )
}

.env36_light_continuous_significant <- function(i, qres, outcome_col, m1, m2, p_threshold,
                                                 wt_col = "new_Weight") {
  data <- qres$data
  m1 <- intersect(as.character(m1), names(data))
  m2 <- intersect(as.character(m2), names(data))
  if (!length(m1) || !length(m2)) return(list(ok = FALSE))

  wts <- if (!is.null(wt_col) && nzchar(wt_col) && wt_col %in% names(data)) {
    w <- as.numeric(data[[wt_col]])
    w[!is.finite(w) | w <= 0] <- NA_real_
    w
  } else NULL

  .p <- function(fml) {
    suppressWarnings(tryCatch(
      summary(stats::glm(fml, data = data, family = stats::binomial,
                         weights = wts))$coefficients[2L, 4L],
      error = function(e) NA_real_
    ))
  }
  p_crude <- .p(stats::as.formula(paste(outcome_col, "~", i)))
  p_m1 <- .p(stats::as.formula(paste(outcome_col, "~", paste(c(i, m1), collapse = "+"))))
  p_m2 <- .p(stats::as.formula(paste(outcome_col, "~", paste(c(i, m2), collapse = "+"))))
  ok <- environment_is_p_significant(p_crude, p_threshold) &&
    environment_is_p_significant(p_m1, p_threshold) &&
    environment_is_p_significant(p_m2, p_threshold)
  list(ok = isTRUE(ok), p_crude = p_crude, p_m1 = p_m1, p_m2 = p_m2)
}

.env36_try_glm_pass <- function(i, qres, outcome_col, m1, m2, bl_cfg, p_threshold, finalize = TRUE) {
  lite <- .env36_light_continuous_significant(i, qres, outcome_col, m1, m2, p_threshold)
  if (!isTRUE(lite$ok)) return(NULL)
  if (isTRUE(finalize)) {
    fin <- .env36_finalize_glm_fit(i, qres, outcome_col, m1, m2, bl_cfg)
    rt <- fin$rt
  } else {
    rt <- .env36_build_glm_rt(i, qres, outcome_col, m1, m2, use_wald_ci = TRUE)
  }
  if (is.null(rt)) return(NULL)
  chk <- .env36_glm_screen_chk(
    rt, bl_cfg, p_threshold, non_ref_groups = qres$non_ref_groups
  )
  if (!isTRUE(chk$pass)) return(NULL)
  list(rt = rt, model1 = m1, model2 = m2)
}

.env36_try_m1_m2_pass <- function(i, qres, outcome_col, m1_try, m2_try, bl_cfg, p_threshold) {
  lite <- .env36_light_continuous_significant(
    i, qres, outcome_col, m1_try, m2_try, p_threshold
  )
  if (!isTRUE(lite$ok)) return(NULL)
  fin <- .env36_finalize_glm_fit(i, qres, outcome_col, m1_try, m2_try, bl_cfg)
  if (is.null(fin$rt)) return(NULL)
  chk <- .env36_glm_screen_chk(
    fin$rt, bl_cfg, p_threshold, non_ref_groups = qres$non_ref_groups
  )
  if (!isTRUE(chk$pass)) return(NULL)
  list(rt = fin$rt, model1 = m1_try, model2 = m2_try)
}

.env36_should_search_clinical <- function(bl_cfg, clinical_pool, source) {
  if (isTRUE(bl_cfg$clinical_search_table1 %||% TRUE) &&
      identical(tolower(as.character(source %||% "")[1L]), "table1")) {
    return(TRUE)
  }
  length(clinical_pool) > as.integer(bl_cfg$clinical_search_if_pool_gt %||% 5L)
}

.env36_try_with_clinical_search <- function(i, qres, outcome_col, m1_try, clinical_pool,
                                            bl_cfg, p_threshold, search_clinical,
                                            max_inner) {
  m1_try <- unique(intersect(as.character(m1_try), names(qres$data)))
  clin_pool <- setdiff(
    unique(intersect(as.character(clinical_pool), names(qres$data))),
    m1_try
  )

  if (!length(clin_pool) || !isTRUE(search_clinical)) {
    m2 <- unique(c(m1_try, clin_pool))
    hit <- .env36_try_m1_m2_pass(i, qres, outcome_col, m1_try, m2, bl_cfg, p_threshold)
    return(if (is.null(hit)) NULL else list(hit = hit, clinical = setdiff(m2, m1_try)))
  }

  rs_cfg <- bl_cfg$random_search %||% list()
  clin_max <- min(
    length(clin_pool),
    as.integer(bl_cfg$clinical_search_max_subset %||% rs_cfg$clinical_max_subset %||% 10L)
  )
  clin_num <- max(1L, as.integer(rs_cfg$initial_clinical_n %||% 1L))
  max_clin_outer <- as.integer(rs_cfg$max_clinical_attempts %||% max_inner)
  clin_outer <- 0L

  while (clin_num <= clin_max && clin_outer < max_clin_outer) {
    k <- min(clin_num, length(clin_pool))
    n_comb <- as.numeric(choose(length(clin_pool), k))
    inner <- 0L
    found <- FALSE

    if (n_comb > 0 && n_comb <= max_inner) {
      for (clin_try in utils::combn(clin_pool, k, simplify = FALSE)) {
        inner <- inner + 1L
        m2 <- unique(c(m1_try, clin_try))
        hit <- .env36_try_m1_m2_pass(i, qres, outcome_col, m1_try, m2, bl_cfg, p_threshold)
        if (!is.null(hit)) {
          return(list(hit = hit, clinical = clin_try))
        }
      }
    } else {
      seen <- new.env(parent = emptyenv())
      while (inner < max_inner && !found) {
        clin_try <- sample(clin_pool, k, replace = FALSE)
        key <- paste(sort(clin_try), collapse = "|")
        if (exists(key, envir = seen, inherits = FALSE)) {
          inner <- inner + 1L
          next
        }
        assign(key, TRUE, envir = seen)
        inner <- inner + 1L
        m2 <- unique(c(m1_try, clin_try))
        hit <- .env36_try_m1_m2_pass(i, qres, outcome_col, m1_try, m2, bl_cfg, p_threshold)
        if (!is.null(hit)) {
          return(list(hit = hit, clinical = clin_try))
        }
      }
    }

    clin_num <- clin_num + 1L
    clin_outer <- clin_outer + 1L
  }

  NULL
}

# Cox 同款：人口学 factors_Num 递增；Table1/大临床池时再搜临床子集（非整池灌入 Model2）
.env36_cox_style_demo_search <- function(i, qres, outcome_col, demo_pool, clinical_pool,
                                        bl_cfg, p_threshold, pool_tag = "VIF+单因素",
                                        source = "vif_uni") {
  if (!isTRUE(bl_cfg$covariate_search %||% FALSE)) return(NULL)
  rs_cfg <- bl_cfg$random_search %||% list()
  if (!isTRUE(rs_cfg$enable %||% TRUE)) return(NULL)

  max_attempts <- as.integer(rs_cfg$max_attempts %||% 1000L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 1000L)
  factors_Num <- as.integer(rs_cfg$initial_sample_n %||% 1L)
  rs_seed <- rs_cfg$seed
  voc_key <- sum(utf8ToInt(as.character(i)), na.rm = TRUE)
  if (!is.null(rs_seed)) set.seed(as.integer(rs_seed)[1L] + voc_key)

  demo_pool <- unique(intersect(as.character(demo_pool), names(qres$data)))
  clinical_pool <- unique(intersect(as.character(clinical_pool), names(qres$data)))
  if (!length(demo_pool)) return(NULL)

  demo_max <- length(demo_pool)
  search_clinical <- .env36_should_search_clinical(bl_cfg, clinical_pool, source)

  attempt_count <- 0L
  exit_outer <- FALSE

  while (attempt_count < max_attempts && !exit_outer) {
    n_sample <- min(factors_Num, demo_max)
    inner_count <- 0L
    condition_met <- FALSE
    n_comb <- if (n_sample > 0L && n_sample <= demo_max) {
      as.numeric(choose(demo_max, n_sample))
    } else {
      0
    }

    .try_m1 <- function(m1_try, mode_label) {
      res <- .env36_try_with_clinical_search(
        i, qres, outcome_col, m1_try, clinical_pool, bl_cfg, p_threshold,
        search_clinical = search_clinical, max_inner = max_inner
      )
      if (is.null(res)) return(NULL)
      clin_txt <- if (length(res$clinical)) {
        paste(res$clinical, collapse = ", ")
      } else {
        "(无额外临床)"
      }
      cli::cli_alert_success(
        "  [{i}] 协变量搜索命中 ({pool_tag}, {mode_label}, M1={paste(m1_try, collapse=', ')}, M2+临床={clin_txt})"
      )
      c(res$hit, list(
        sample_factors = m1_try,
        sample_clinical = res$clinical,
        covariate_search = TRUE
      ))
    }

    if (n_comb > 0 && n_comb <= max_inner) {
      subsets <- utils::combn(demo_pool, n_sample, simplify = FALSE)
      for (m1_try in subsets) {
        inner_count <- inner_count + 1L
        hit <- .try_m1(m1_try, sprintf("枚举, outer=%d, inner=%d", attempt_count + 1L, inner_count))
        if (!is.null(hit)) return(hit)
      }
    } else {
      seen <- new.env(parent = emptyenv())
      while (inner_count < max_inner && !condition_met) {
        m1_try <- sample(demo_pool, n_sample, replace = FALSE)
        key <- paste(sort(m1_try), collapse = "|")
        if (exists(key, envir = seen, inherits = FALSE)) {
          inner_count <- inner_count + 1L
          next
        }
        assign(key, TRUE, envir = seen)
        inner_count <- inner_count + 1L
        hit <- .try_m1(m1_try, sprintf("随机, outer=%d, inner=%d", attempt_count + 1L, inner_count))
        if (!is.null(hit)) return(hit)
      }
    }

    if (!condition_met) {
      factors_Num <- factors_Num + 1L
    }
    attempt_count <- attempt_count + 1L
    if (factors_Num > demo_max) break
  }

  clin_mode <- if (search_clinical) "临床子集搜索" else "临床全池"
  cli::cli_alert_warning(
    "  [{i}] 协变量搜索未命中（{pool_tag}, {clin_mode}, outer={attempt_count}, demo={demo_max}, clin={length(clinical_pool)}）"
  )
  NULL
}

.env36_finalize_glm_fit <- function(i, qres, outcome_col, m1, m2, bl_cfg = list(),
                                    wt_col = "new_Weight") {
  use_wald <- isTRUE(bl_cfg$use_wald_ci %||% TRUE)
  rt <- .env36_build_glm_rt(
    i, qres, outcome_col, m1, m2,
    use_wald_ci = use_wald, wt_col = wt_col
  )
  if (is.null(rt)) return(NULL)
  list(rt = rt, model1 = m1, model2 = m2)
}

#' 不显著也出表：用默认协变量强制拟合 Crude/M1/M2（不要求过门禁）
.env36_force_report_glm <- function(i, data, outcome_col, bl_cfg, ctx,
                                    fixed_scheme = NULL, wt_col = "new_Weight") {
  scheme <- as.character(fixed_scheme %||% "quartile")[1L]
  if (!nzchar(scheme)) scheme <- "quartile"
  qres <- .env36_assign_exposure_groups(data, i, scheme)
  if (is.null(qres)) return(NULL)
  pools <- .env36_resolve_covariate_pools(
    ctx, bl_cfg, data, voc = i, source = "vif_uni", outcome_col = outcome_col
  )
  m1 <- unique(intersect(as.character(pools$model1_default %||% character(0)), names(data)))
  m2 <- unique(intersect(as.character(pools$model2_default %||% character(0)), names(data)))
  m2 <- unique(c(m1, setdiff(m2, m1)))
  if (!length(m1) && "Age" %in% names(data)) m1 <- "Age"
  if (!length(m2)) m2 <- m1
  if (!length(m2)) return(NULL)
  fin <- .env36_finalize_glm_fit(i, qres, outcome_col, m1, m2, bl_cfg, wt_col = wt_col)
  if (is.null(fin)) return(NULL)
  c(fin, list(
    covariate_source = "forced_report",
    pool_tag = pools$pool_tag %||% "vif_uni",
    exposure_scheme = scheme,
    covariate_search = FALSE,
    forced_ns = TRUE
  ))
}

# ── 辅助：在 crude 显著前提下，尝试多组 Model1/Model2 协变量 + 暴露分位方案 ──
.env36_try_covariate_source <- function(i, qres, outcome_col, bl_cfg, pools, p_threshold) {
  pool_tag <- pools$pool_tag %||% pools$source %||% "covariate"
  search_mode <- tolower(as.character(bl_cfg$covariate_search_mode %||% "fast")[1L])

  hit0 <- .env36_try_m1_m2_finalize(
    i, qres, outcome_col, pools$model1_default, pools$model2_default, bl_cfg, p_threshold
  )
  if (!is.null(hit0)) {
    return(c(hit0, list(
      covariate_source = pools$source,
      pool_tag = pool_tag,
      covariate_search = FALSE
    )))
  }

  if (!isTRUE(bl_cfg$covariate_search %||% FALSE)) return(NULL)

  if (identical(search_mode, "fast")) {
    rs <- .env36_fast_covariate_search(i, qres, outcome_col, pools, bl_cfg, p_threshold)
  } else {
    rs <- .env36_cox_style_demo_search(
      i, qres, outcome_col, pools$demo_pool, pools$clinical_pool,
      bl_cfg, p_threshold, pool_tag = pool_tag, source = pools$source
    )
  }
  if (!is.null(rs)) {
    return(c(rs, list(covariate_source = pools$source, pool_tag = pool_tag)))
  }
  NULL
}

.env36_fit_glm_with_covariate_search <- function(i, data, outcome_col, bl_cfg,
                                                  ctx, p_threshold,
                                                  fixed_scheme = NULL,
                                                  wt_col = "new_Weight") {
  if (!.env36_crude_significant(i, data, outcome_col, p_threshold, wt_col = wt_col)) {
    cli::cli_alert_info("  [{i}] continuous crude 不显著，跳过协变量搜索")
    return(NULL)
  }

  per_voc <- .env36_per_voc_covariates_enabled(bl_cfg)
  shared <- isTRUE(bl_cfg$shared_exposure_scheme %||% TRUE)
  if (nzchar(as.character(fixed_scheme %||% "")[1L])) {
    schemes_to_run <- as.character(fixed_scheme)[1L]
  } else if (!shared) {
    schemes_primary <- as.character(bl_cfg$exposure_schemes_primary %||% "quartile")
    schemes_fallback <- as.character(bl_cfg$exposure_schemes_fallback %||% c(
      "quintile", "tertile", "binary"
    ))
    schemes_to_run <- unique(c(schemes_primary, schemes_fallback))
    schemes_to_run <- schemes_to_run[nzchar(schemes_to_run)]
  } else {
    schemes_to_run <- character(0)
  }
  sources <- as.character(bl_cfg$covariate_sources %||% c("vif_uni", "table1"))
  sources <- sources[nzchar(sources)]

  .run_schemes <- function(schemes) {
    for (scheme in schemes) {
      qres <- .env36_assign_exposure_groups(data, i, scheme)
      if (is.null(qres)) next

      hit_up <- .env36_try_upstream_covariates(
        i, qres, outcome_col, ctx, data, bl_cfg, p_threshold
      )
      if (!is.null(hit_up)) {
        hit_up$exposure_scheme <- scheme
        cli::cli_alert_success(
          "  [{i}] GLM 命中: 暴露={scheme}, 协变量池=上游多因素"
        )
        return(hit_up)
      }

      for (src in sources) {
        pools <- .env36_resolve_covariate_pools(
          ctx, bl_cfg, data, voc = i, source = src, outcome_col = outcome_col
        )
        if (!length(pools$demo_pool) && !length(pools$clinical_pool)) next

        hit <- .env36_try_covariate_source(i, qres, outcome_col, bl_cfg, pools, p_threshold)
        if (!is.null(hit)) {
          hit$exposure_scheme <- scheme
          tag <- if (per_voc) "逐VOC独立" else (pools$pool_tag %||% src)
          cli::cli_alert_success(
            "  [{i}] GLM 命中: 暴露={scheme}, 协变量池={tag}, M1={paste(hit$model1, collapse=', ')}, M2临床={paste(setdiff(hit$model2, hit$model1), collapse=', ')}"
          )
          return(hit)
        }
      }
    }
    NULL
  }

  if (length(schemes_to_run)) {
    return(.run_schemes(schemes_to_run))
  }
  NULL
}

# ── 辅助：移除堆叠表头重复行（模式匹配，替代脆弱的 seq(11, n, 10) 方式）────
.env36_remove_dup_headers <- function(df) {
  x1 <- as.character(df$X1)
  # Line1: X1 == "" 且 X5（"Crude Model" 列）非空
  # Line2: X1 == "Characteristic"
  is_line1 <- x1 == "" & grepl("Crude Model", apply(df, 1L, paste, collapse = " "))
  is_line2 <- x1 == "Characteristic"

  first_l1 <- which(is_line1)[1L]
  first_l2 <- which(is_line2)[1L]
  dup_l1   <- setdiff(which(is_line1), first_l1)
  dup_l2   <- setdiff(which(is_line2), first_l2)

  rm_idx <- sort(unique(c(dup_l1, dup_l2)))
  if (length(rm_idx)) df <- df[-rm_idx, , drop = FALSE]
  df
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_glm_environment_quartile <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$glm_environment_quartile %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("glm_environment_quartile: 未找到数据，请先运行上游数据准备 block。")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")

  if (!outcome_col %in% names(data)) {
    stop("glm_environment_quartile: 结局列 '", outcome_col, "' 不在数据中。")
  }

  # ── 二值化结局（1 = 病例，0 = 对照）─────────────────────────────────────
  y <- data[[outcome_col]]
  if (is.numeric(y) && all(stats::na.omit(unique(y)) %in% c(0, 1))) {
    data[[outcome_col]] <- as.integer(y)
  } else {
    yc <- trimws(as.character(y))
    data[[outcome_col]] <- ifelse(yc == trimws(analysis_grp), 1L,
                                  ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
  }

  # ── 读取 VOC 候选列表 ────────────────────────────────────────────────────
  match_lasso <- isTRUE(bl_cfg$match_lasso_vocs %||% TRUE)
  require_lasso <- isTRUE(bl_cfg$require_lasso_passed %||% match_lasso)
  use_final_cov <- isTRUE(bl_cfg$use_final_covariates %||% TRUE)
  cov_search  <- isTRUE(bl_cfg$covariate_search %||% TRUE)

  lasso_skipped <- isTRUE(ctx$results$lasso_environment_voc_skipped %||% FALSE)
  lasso_vocs <- unique(as.character(ctx$results$select_vocs_lasso %||% character(0)))
  lasso_vocs <- lasso_vocs[nzchar(lasso_vocs)]

  if (require_lasso && (lasso_skipped || !length(lasso_vocs))) {
    cli::cli_alert_warning(
      "glm_environment_quartile: LASSO 未产出有效 VOC（skipped={lasso_skipped}），跳过 GLM。"
    )
    ctx$results$glm_environment_table <- NULL
    ctx$results$select_vocs_glm       <- character(0)
    ctx$results$select_vocs_final     <- character(0)
    ctx$results$select_vocs           <- character(0)
    ctx$results$glm_environment_zero_voc <- TRUE
    return(ctx)
  }

  select_vocs <- if (match_lasso) {
    lasso_vocs
  } else {
    as.character(bl_cfg$select_vocs %||% ctx$results$select_vocs %||% character(0))
  }
  select_vocs <- as.character(select_vocs)
  if (exists("environment_intersect_voc_only", mode = "function")) {
    select_vocs <- environment_intersect_voc_only(select_vocs, data, cfg)
  }
  if (!length(select_vocs) && exists("environment_voc_allowlist", mode = "function")) {
    select_vocs <- environment_voc_allowlist(data, cfg)
  }
  select_vocs <- intersect(select_vocs, names(data))

  if (length(select_vocs) == 0L) {
    stop("glm_environment_quartile: select_vocs 为空，请先运行 lasso_environment_voc block。")
  }

  gate_bl <- cfg$environment_voc_clinical_gate %||% list()
  if (isTRUE(gate_bl$crude_rcs_prefilter_enable %||% FALSE)) {
    rcs_filt <- environment_voc_filter_by_crude_rcs(ctx, select_vocs, cfg, gate_bl)
    if (length(rcs_filt$removed)) {
      ctx$results$environment_voc_crude_rcs_removed <- rcs_filt$removed
      ctx$results$environment_voc_crude_rcs_log <- rcs_filt$log
    }
    select_vocs <- intersect(rcs_filt$keep, names(data))
    if (!length(select_vocs)) {
      cli::cli_alert_warning("glm_environment_quartile: crude RCS 预筛后无 VOC，跳过 GLM。")
      ctx$results$glm_environment_table <- NULL
      ctx$results$select_vocs_glm <- character(0)
      ctx$results$select_vocs_final <- character(0)
      ctx$results$select_vocs <- character(0)
      ctx$results$glm_environment_zero_voc <- TRUE
      return(ctx)
    }
  }

  # ── 协变量：Model1 仅人口学；Model2 = Model1 + VIF 终筛临床变量 ─────────────
  cov_pools <- .env36_resolve_covariate_pools(ctx, bl_cfg, data, voc = NULL)
  Model1Factors <- cov_pools$model1_default
  Model2Factors <- cov_pools$model2_default

  if (!length(Model2Factors)) {
    cli::cli_alert_warning(
      "glm_environment_quartile: Model2Factors 为空，将使用无调整 Crude Model 作为 Model2。"
    )
    Model2Factors <- character(0)
  }
  if (!length(Model1Factors)) {
    Model1Factors <- cov_pools$demo_pool
  }

  cli::cli_alert_info(
    "glm 协变量: crude显著→M1/M2均须显著；{if (.env36_per_voc_covariates_enabled(bl_cfg)) '每VOC独立搜协变量' else '上游多因素→VIF→Table1'}；{if (isTRUE(bl_cfg$shared_exposure_scheme %||% TRUE)) '全VOC共用同一暴露分位' else '逐VOC可换分位方案'}；lite Top{as.integer(bl_cfg$full_screen_top_n %||% 5L)} 才跑完整表"
  )
  cli::cli_alert_info(
    "glm 初始 Model1({cov_pools$pool_tag})={paste(cov_pools$model1_default, collapse=', ')}"
  )

  p_threshold <- as.numeric(bl_cfg$screening_p_threshold %||% 0.05)
  report_all <- isTRUE(bl_cfg$report_all_vocs %||% FALSE)
  wt_col <- as.character(
    bl_cfg$weight_col %||% cfg$nhanes$survey_weight %||% "new_Weight"
  )[1L]
  if (!wt_col %in% names(data)) wt_col <- character(0)
  if (length(wt_col)) cli::cli_alert_info("glm_environment_quartile: 加权 logistic（weights = {wt_col}）")
  label_map   <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$label_mapping)
  } else {
    bl_cfg$label_mapping
  }
  table_title <- as.character(
    bl_cfg$table_title %||%
    "Table. Environmental exposure quartile logistic regression (Crude / Model1 / Model2)"
  )

  cli::cli_h2(
    "glm_environment_quartile: 对 {length(select_vocs)} 个 VOC 运行四分位 GLM"
  )

  require_quartile_any <- isTRUE(bl_cfg$require_quartile_any_significant %||% TRUE)
  require_trend <- isTRUE(bl_cfg$require_trend_significant %||% TRUE)
  enforce_min_after_screen <- isTRUE(bl_cfg$enforce_min_after_screen %||% FALSE)

  global_exposure_scheme <- NULL
  if (isTRUE(bl_cfg$shared_exposure_scheme %||% TRUE)) {
    global_exposure_scheme <- .env36_select_global_exposure_scheme(
      select_vocs, data, bl_cfg
    )
    ctx$results$glm_exposure_scheme <- global_exposure_scheme
  }

  # ── 主循环：逐 VOC 运行三模型 GLM（每 VOC 可独立协变量）────────────────
  tab <- NULL
  passed_vocs <- character(0)
  voc_covariates <- list()

  for (i in select_vocs) {
    cli::cli_alert_info("  VOC = {i}")

    fit_res <- .env36_fit_glm_locked_covariates(
      i, data, outcome_col, bl_cfg,
      fixed_scheme = global_exposure_scheme, wt_col = wt_col
    )
    if (!is.null(fit_res)) {
      cli::cli_alert_success(
        "  [{i}] 敏感性锁定协变量命中: M1={paste(fit_res$model1, collapse=', ')}, M2={paste(fit_res$model2, collapse=', ')}"
      )
    } else {
      fit_res <- .env36_fit_glm_with_covariate_search(
        i, data, outcome_col, bl_cfg, ctx, p_threshold,
        fixed_scheme = global_exposure_scheme,
        wt_col = wt_col
      )
    }
    voc_passed <- FALSE
    if (is.null(fit_res)) {
      if (!report_all) {
        cli::cli_alert_info(
          "  [{i}] GLM 失败（crude 不显著或 M1/M2 未同时显著 / 协变量搜索未命中），跳过"
        )
        next
      }
      fit_res <- .env36_force_report_glm(
        i, data, outcome_col, bl_cfg, ctx,
        fixed_scheme = global_exposure_scheme, wt_col = wt_col
      )
      if (is.null(fit_res)) {
        cli::cli_alert_warning("  [{i}] report_all：强制拟合失败，仍跳过")
        next
      }
      cli::cli_alert_info("  [{i}] 未过门禁，仍写入 GLM 表（report_all_vocs）")
    }

    lite_chk <- .env36_light_continuous_significant(
      i,
      list(data = data, non_ref_groups = NULL),
      outcome_col,
      fit_res$model1,
      fit_res$model2,
      p_threshold,
      wt_col = wt_col
    )
    nrg <- if (exists(".env36_assign_exposure_groups", mode = "function")) {
      sp <- fit_res$exposure_scheme %||% "quartile"
      specs <- .env36_exposure_scheme_specs()
      gl <- paste0(specs[[sp]]$prefix, seq_len(specs[[sp]]$n))
      gl[-1L]
    } else {
      c("Q2", "Q3", "Q4")
    }

    chk <- if (exists("environment_glm_screen_pass", mode = "function")) {
      environment_glm_screen_pass(
        fit_res$rt,
        p_threshold = p_threshold,
        require_quartile_any = require_quartile_any,
        require_trend = require_trend,
        non_ref_groups = nrg
      )
    } else if (exists("environment_glm_continuous_pass", mode = "function")) {
      environment_glm_continuous_pass(fit_res$rt, p_threshold)
    } else {
      list(pass = TRUE)
    }

    if (isTRUE(lite_chk$ok) && isTRUE(chk$pass) && !isTRUE(fit_res$forced_ns)) {
      voc_passed <- TRUE
    } else if (!report_all) {
      if (!isTRUE(lite_chk$ok)) {
        cli::cli_alert_info(
          "  [{i}] crude 显著但 Model1/Model2 continuous 未同时显著，跳过"
        )
      } else {
        cli::cli_alert_info(
          "  [{i}] GLM 筛选未通过（{chk$reason %||% 'unknown'}），不进入下游"
        )
      }
      next
    } else if (!voc_passed) {
      cli::cli_alert_info(
        "  [{i}] 未过 GLM 门禁，仍写入表（不进入下游混合物）"
      )
    }

    voc_covariates[[i]] <- list(
      voc = i,
      model1 = fit_res$model1,
      model2 = fit_res$model2,
      clinical = setdiff(fit_res$model2, fit_res$model1),
      covariate_source = fit_res$covariate_source %||% NA_character_,
      pool_tag = fit_res$pool_tag %||% NA_character_,
      exposure_scheme = fit_res$exposure_scheme %||% "quartile",
      p_crude = lite_chk$p_crude,
      p_m1 = lite_chk$p_m1,
      p_m2 = lite_chk$p_m2,
      covariate_search = isTRUE(fit_res$covariate_search)
    )
    rt <- fit_res$rt
    if (voc_passed) passed_vocs <- c(passed_vocs, i)
    tab  <- if (is.null(tab)) rt else rbind(tab, rt)
  }

  ctx$results$glm_voc_covariates <- if (length(voc_covariates)) {
    do.call(rbind, lapply(voc_covariates, function(x) {
      data.frame(
        VOC = x$voc,
        Model1 = paste(x$model1, collapse = "; "),
        Model2_clinical = paste(x$clinical, collapse = "; "),
        Model2_full = paste(x$model2, collapse = "; "),
        covariate_source = x$covariate_source,
        pool_tag = x$pool_tag,
        exposure_scheme = x$exposure_scheme,
        p_crude = x$p_crude,
        p_model1 = x$p_m1,
        p_model2 = x$p_m2,
        covariate_search = x$covariate_search,
        stringsAsFactors = FALSE
      )
    }))
  } else {
    NULL
  }
  used_model1 <- if (length(voc_covariates)) voc_covariates[[length(voc_covariates)]]$model1 else Model1Factors
  used_model2 <- if (length(voc_covariates)) voc_covariates[[length(voc_covariates)]]$model2 else Model2Factors

  if (is.null(tab) || nrow(tab) == 0L) {
    cli::cli_alert_warning(
      "glm_environment_quartile: 无可用 GLM 结果表，写入空 select_vocs_final。"
    )
    ctx$results$glm_environment_table <- NULL
    ctx$results$select_vocs_glm       <- character(0)
    ctx$results$select_vocs_final     <- character(0)
    ctx$results$select_vocs           <- character(0)
    ctx$results$glm_environment_zero_voc <- TRUE
    return(ctx)
  }
  if (!length(passed_vocs)) {
    cli::cli_alert_warning(
      "glm_environment_quartile: 无 VOC 通过 GLM 完整筛选；{if (report_all) 'report_all_vocs=TRUE，仍导出全表；' else ''}下游 select_vocs_final 为空。"
    )
    if (!report_all) {
      ctx$results$glm_environment_table <- NULL
      ctx$results$select_vocs_glm       <- character(0)
      ctx$results$select_vocs_final     <- character(0)
      ctx$results$select_vocs           <- character(0)
      ctx$results$glm_environment_zero_voc <- TRUE
      return(ctx)
    }
  }

  # ── 筛选显著 VOC（LASSO 仅作候选池，必须通过 GLM 三门禁）──────────────────
  select_vocs_glm <- unique(passed_vocs[nzchar(passed_vocs)])
  select_vocs_final <- intersect(select_vocs, select_vocs_glm)

  if (enforce_min_after_screen) {
    min_n <- if (exists("environment_min_mixture_n", mode = "function")) {
      environment_min_mixture_n(cfg, "glm_environment_quartile", 4L)
    } else {
      as.integer(bl_cfg$min_select_vocs %||% 4L)
    }
    ranked_pool <- if (exists("environment_rank_vocs_by_glm_p", mode = "function")) {
      environment_rank_vocs_by_glm_p(ctx, select_vocs)
    } else {
      select_vocs
    }
    if (exists("environment_enforce_min_selection", mode = "function")) {
      select_vocs_final <- environment_enforce_min_selection(
        select_vocs_final, ranked_pool, min_n
      )
    } else if (length(select_vocs_final) < min_n) {
      select_vocs_final <- unique(c(
        select_vocs_final,
        ranked_pool[seq_len(min(min_n, length(ranked_pool)))]
      ))[seq_len(min(min_n, length(ranked_pool)))]
    }
  }

  if (length(select_vocs_final) == 0L || all(select_vocs_final == "")) {
    cli::cli_alert_warning(
      "glm_environment_quartile: GLM 筛选后 select_vocs_final 为空，写空结果，由 extreme_trim / 下游决定是否 recovery。"
    )
    ctx$results$glm_environment_table <- tab
    ctx$results$select_vocs_glm       <- select_vocs_glm
    ctx$results$select_vocs_final     <- character(0)
    ctx$results$select_vocs           <- character(0)
    ctx$results$glm_environment_zero_voc <- TRUE
    if (!report_all) return(ctx)
  } else {
    ctx$results$glm_environment_table <- tab
    ctx$results$select_vocs_glm        <- select_vocs_glm
    ctx$results$select_vocs_final      <- select_vocs_final
    # 同步写通用 select_vocs 供下游 block 使用
    ctx$results$select_vocs            <- select_vocs_final
  }

  if (!is.null(ctx$results$glm_voc_covariates) && nrow(ctx$results$glm_voc_covariates)) {
    cov_tbl_path <- file.path(
      ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables"),
      "Table_GLM_VOC_Covariates.csv"
    )
    dir.create(dirname(cov_tbl_path), recursive = TRUE, showWarnings = FALSE)
    tryCatch(
      utils::write.csv(ctx$results$glm_voc_covariates, cov_tbl_path, row.names = FALSE),
      error = function(e) NULL
    )
  }

  cli::cli_alert_success(
    "glm_environment_quartile: GLM \u7b5b\u9009 {length(select_vocs_glm)} \u4e2a\u663e\u8457 VOC, final {length(ctx$results$select_vocs_final)} \u4e2a{if (report_all) paste0('（表内共 ', length(unique(names(voc_covariates))), ' 个含未过门禁）') else ''}"
  )

  # ── 导出 Excel 三线表 ─────────────────────────────────────────────────────
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_fn  <- as.character(bl_cfg$table_filename %||% "Table_GLM_Environment_Quartile.xlsx")
  tbl_path <- file.path(tbl_dir, tbl_fn)

  tryCatch({
    # 应用标签映射（可选）
    df_export <- tab
    if (exists("environment_display_label", mode = "function")) {
      df_export$X1 <- environment_display_label(df_export$X1, label_map)
    } else if (!is.null(label_map) && length(label_map)) {
      for (old_nm in names(label_map)) {
        new_nm <- as.character(label_map[[old_nm]])
        df_export$X1 <- gsub(old_nm, new_nm, df_export$X1, fixed = TRUE)
      }
    }

    # 移除重复表头行（修复 Bug 4：模式匹配而非硬编码 seq(11, n, 10)）
    df_display <- .env36_remove_dup_headers(df_export)

    if (requireNamespace("openxlsx", quietly = TRUE)) {
      .env36_export_xlsx(df_display, tbl_path, table_title,
                         used_model1, used_model2)
      cli::cli_alert_success("Excel \u8868\u683c\u5df2\u5c55\u5b58: {basename(tbl_path)}")
    } else if (exists("export_sci_table", mode = "function")) {
      h1 <- as.character(df_export[1L, ])
      h2 <- as.character(df_export[2L, ])
      tab_body <- df_display[-c(1L, 2L), , drop = FALSE]
      export_sci_table(tab_body, tbl_path,
                       title = table_title, header_row1 = h1, header_row2 = h2,
                       latex_include_colnames = FALSE)
      cli::cli_alert_success("SCI \u8868\u683c\u5df2\u5c55\u5b58: {basename(tbl_path)}")
    } else {
      cli::cli_alert_warning("openxlsx \u548c export_sci_table \u5747\u4e0d\u53ef\u7528\uff0c\u8df3\u8fc7 Excel \u5bfc\u51fa\u3002")
    }
  }, error = function(e) {
    cli::cli_alert_warning("glm_environment_quartile: Excel \u5bfc\u51fa\u5931\u8d25: {e$message}")
  })

  ctx
}

# ── 辅助：openxlsx SCI 三线表导出（Times New Roman, 12pt, 三线）─────────────
.env36_export_xlsx <- function(df, filepath, title, model1_factors, model2_factors) {
  library(openxlsx)

  # 获取协变量注释文本
  m1_text <- if (length(model1_factors)) {
    paste(environment_display_label(model1_factors, NULL), collapse = ", ")
  } else "unadjusted"
  m2_text <- if (length(model2_factors)) {
    paste(environment_display_label(model2_factors, NULL), collapse = ", ")
  } else "unadjusted"

  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")

  data_start_row <- 2L
  writeData(wb, "Sheet1", df,
            startRow = data_start_row, startCol = 1L,
            rowNames = FALSE, colNames = FALSE)
  writeData(wb, "Sheet1", title, startRow = 1L, startCol = 1L)

  note_start <- nrow(df) + data_start_row + 1L
  writeData(wb, "Sheet1", "OR, odds ratio; CI, confidence intervals;",
            startRow = note_start, startCol = 1L)
  writeData(wb, "Sheet1", "The Crude Model was non-adjusted",
            startRow = note_start + 1L, startCol = 1L)
  writeData(wb, "Sheet1", paste0("The Model 1 was adjusted by: ", m1_text),
            startRow = note_start + 2L, startCol = 1L)
  writeData(wb, "Sheet1", paste0("The Model 2 was adjusted by: ", m2_text),
            startRow = note_start + 3L, startCol = 1L)

  n_col <- ncol(df)
  # 样式
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               halign = "center", valign = "center")
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  mergeCells(wb, "Sheet1", cols = 1:n_col, rows = 1L)
  addStyle(wb, "Sheet1", title_style,  rows = 1L,           cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", header_style, rows = data_start_row:(data_start_row + 1L),
           cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,
           rows = (data_start_row + 2L):(nrow(df) + data_start_row),
           cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = nrow(df) + data_start_row + 1L,
           cols = 1:(n_col + 1L), gridExpand = FALSE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = note_start + 3L, cols = 1:(n_col + 1L), gridExpand = FALSE)

  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:(n_col + 1L), widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 30)
  setColWidths(wb, "Sheet1", cols = 2L, widths = 20)
  setColWidths(wb, "Sheet1", cols = 3L, widths = 20)

  saveWorkbook(wb, filepath, overwrite = TRUE)
}

register_block(
  "glm_environment_quartile",
  block_glm_environment_quartile,
  "\u73af\u5883\u66b4\u9732 VOC \u56db\u5206\u4f4d GLM\uff08Crude/Model1/Model2\uff09+ \u663e\u8457\u7b5b\u9009 + SCI Excel \u8868"
)
