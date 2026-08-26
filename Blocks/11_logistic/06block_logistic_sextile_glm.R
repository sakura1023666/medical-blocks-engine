###############################################################################
#  logistic_sextile_glm — 六分位（Q1–Q6）GLM Logistic 回归（Table 2 风格）。
#                         Q1（最低组）为参照；Crude / Model1 / Model2 + 随机搜索；
#                         export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results   = "Model1Factors"
#  require_ctx_results  += "final_features"
#
#  logistic_sextile_glm = list(
#    group_var              = NULL,    # 非 NULL → 直接用已有六分类列，跳过六分位计算
#    group_levels           = NULL,    # factor 水平顺序（第一个为参照）；NULL 时按字母序
#    include_continuous_row = NULL,    # NULL → 自动（predefined 时 FALSE，否则 TRUE）
#    model1_factors         = NULL,
#    random_search = list(
#      max_outer_attempts    = 100L,
#      max_inner_attempts    = 10L,
#      initial_factors_n     = 1L,
#      p_threshold           = 0.05,
#      seed                  = NULL
#    ),
#    pause_enable           = TRUE,
#    pause_on_search_fail   = FALSE,
#    table_filename         = NULL
#  ),
#
#  register_block: "logistic_sextile_glm"
#  块内 bl_cfg <- cfg$logistic_sextile_glm
###############################################################################

.lqg06_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqg06_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "logistic_sextile_glm", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: logistic_sextile_glm — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.lqg06_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      cutoffs, group_labels, include_continuous = TRUE) {
  fml_f01 <- as.formula(paste0(ResultName, "~", FactorName))
  fml_f02 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model1Factors), collapse = "+")))
  fml_f03 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model2Factors), collapse = "+")))
  fml_t01 <- as.formula(paste0(ResultName, "~", TrendName))
  fml_t02 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model1Factors), collapse = "+")))
  fml_t03 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model2Factors), collapse = "+")))

  mf  <- glm(fml_f01, data = Data, family = binomial)
  mf2 <- glm(fml_f02, data = Data, family = binomial)
  mf3 <- glm(fml_f03, data = Data, family = binomial)
  mt  <- glm(fml_t01, data = Data, family = binomial)
  mt2 <- glm(fml_t02, data = Data, family = binomial)
  mt3 <- glm(fml_t03, data = Data, family = binomial)

  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .ci <- function(m, row) {
    ci <- logistic_safe_confint(m)
    paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")")
  }
  .pct <- function(lv) { n <- as.numeric(cnt[lv]); paste0(n, "(", round(n/n_total*100, 2), "%)") }

  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)",
             "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11))

  ref_lv   <- group_labels[1]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")

  non_ref_lvs  <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv <- non_ref_lvs[i]; idx <- i + 1L
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(coef(mf)[idx]),  3), .ci(mf,  idx), round(summary(mf)$coefficients[idx, 4], 4),
      round(exp(coef(mf2)[idx]), 3), .ci(mf2, idx), round(summary(mf2)$coefficients[idx, 4], 4),
      round(exp(coef(mf3)[idx]), 3), .ci(mf3, idx), round(summary(mf3)$coefficients[idx, 4], 4))
  })

  Line_trend <- c("p for trend", rep("", 4),
                  round(summary(mt)$coefficients[2, 4], 4), "", "",
                  round(summary(mt2)$coefficients[2, 4], 4), "", "",
                  round(summary(mt3)$coefficients[2, 4], 4))

  if (include_continuous) {
    fml_c01 <- as.formula(paste0(ResultName, "~", ContinuousName))
    fml_c02 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model1Factors), collapse = "+")))
    fml_c03 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model2Factors), collapse = "+")))
    mc <- glm(fml_c01, data = Data, family = binomial)
    mc2 <- glm(fml_c02, data = Data, family = binomial)
    mc3 <- glm(fml_c03, data = Data, family = binomial)
    .ci_c <- function(m) { ci <- logistic_safe_confint(m); paste0("(", round(exp(ci[2,1]),3), ",", round(exp(ci[2,2]),3), ")") }
    Line3 <- c(ContinuousName, rep("", 11))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(coef(mc)[2]),  3), .ci_c(mc),  round(summary(mc)$coefficients[2, 4], 4),
               round(exp(coef(mc2)[2]), 3), .ci_c(mc2), round(summary(mc2)$coefficients[2, 4], 4),
               round(exp(coef(mc3)[2]), 3), .ci_c(mc3), round(summary(mc3)$coefficients[2, 4], 4))
    rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref), lines_nonref, list(Line_trend)))
  }
  rownames(rt) <- NULL; rt
}

block_logistic_sextile_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$logistic_sextile_glm %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    .lqg06_pause(ctx, "未找到分析数据", "请先运行上游数据准备 block")

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  index_var     <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var))
    stop("logistic_sextile_glm: index_var 未设置。")
  if (!index_var %in% names(data)) stop("logistic_sextile_glm: index_var '", index_var, "' 不在数据列中。")
  if (!outcome_col %in% names(data)) stop("logistic_sextile_glm: outcome_col '", outcome_col, "' 不在数据列中。")

  rs_cfg <- bl_cfg$random_search %||% list()
  bz2    <- as.numeric(rs_cfg$p_threshold %||% 0.05)

  group_var_name <- bl_cfg$group_var
  predefined     <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data)
  data2 <- data

  if (predefined) {
    raw_levels  <- bl_cfg$group_levels %||% sort(unique(as.character(data2[[group_var_name]])))
    data2$Group <- factor(data2[[group_var_name]], levels = raw_levels)
    data2$Num   <- as.numeric(data2$Group)
    cutoffs     <- setNames(rep("", length(raw_levels)), raw_levels)
    cli::cli_alert_info("logistic_sextile_glm: 使用已有分类列 '{group_var_name}'")
  } else {
    probs       <- c(1/6, 2/6, 3/6, 4/6, 5/6)
    qs          <- as.numeric(quantile(data2[[index_var]], probs = probs, na.rm = TRUE))
    data2$Group <- cut(data2[[index_var]], breaks = c(-Inf, qs, Inf),
                       labels = c("Q1","Q2","Q3","Q4","Q5","Q6"), right = TRUE)
    data2$Group <- factor(data2$Group, levels = c("Q1","Q2","Q3","Q4","Q5","Q6"))
    data2$Num   <- as.numeric(data2$Group)
    raw_levels  <- c("Q1","Q2","Q3","Q4","Q5","Q6")
    cutoffs <- c(
      Q1 = paste0("< ", round(qs[1], 2)),
      Q2 = paste0(round(qs[1], 2), " \u2013 ", round(qs[2], 2)),
      Q3 = paste0(round(qs[2], 2), " \u2013 ", round(qs[3], 2)),
      Q4 = paste0(round(qs[3], 2), " \u2013 ", round(qs[4], 2)),
      Q5 = paste0(round(qs[4], 2), " \u2013 ", round(qs[5], 2)),
      Q6 = paste0("\u2265 ", round(qs[5], 2)))
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)

  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- ifelse(data2[[outcome_col]] == disease_label, 1L, 0L)

  excl_cols <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_sextile_glm",
    build_table_fn = function(m1, m2) {
      .lqg06_Tb_ModelGroup3_OR(
        outcome_col, index_var, "Group", "Num",
        data2, m1, m2, cutoffs, raw_levels, include_cont
      )
    },
    filter_m1 = function(m1) {
      m1 <- as.character(m1)
      if ("Age_Years" %in% m1 && "Age_Group" %in% m1) m1 <- m1[m1 != "Age_Group"]
      intersect(m1, colnames(data2))
    }
  )
  ctx              <- cov$ctx
  Model1Factors    <- cov$M1
  Model2Factors    <- cov$M2
  tb01             <- cov$tb
  sample_factors   <- cov$sample_factors
  search_succeeded <- isTRUE(cov$search_succeeded)
  attempt_count    <- cov$attempt_count %||% 0L

  rt <- data.frame(tb01, stringsAsFactors = FALSE)
  for (cc in c(6, 9, 12)) {
    if (cc <= ncol(rt)) {
      hit <- which(as.character(rt[[cc]]) == "0")
      if (length(hit)) rt[[cc]][hit] <- "P < 0.001"
    }
  }
  rownames(rt) <- NULL

  h1 <- as.character(rt[1, ]); h2 <- as.character(rt[2, ])
  rt_body <- rt[-c(1L, 2L), , drop = FALSE]; rownames(rt_body) <- NULL
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))

  caption <- paste0("Logistic regression analysis of ", index_var, " and ", outcome_col, " - sextile (GLM)")
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, "main_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  tryCatch(export_sci_table(rt_body, filepath, title = title,
                            header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE),
           error = function(e) cli::cli_alert_warning("logistic_sextile_glm: export 失败: {e$message}"))

  ctx$results$logistic_table2         <- rt
  ctx$results$logistic_model1_factors <- Model1Factors
  ctx$results$logistic_model2_factors <- Model2Factors
  ctx$results$logistic_sample_factors <- sample_factors
  ctx <- save_result(ctx, "logistic_sextile_glm_Model2Factors", Model2Factors, "Model2Factors_sextile_glm.csv")
  cli::cli_alert_success("logistic_sextile_glm 完成"); ctx
}

register_block("logistic_sextile_glm", block_logistic_sextile_glm,
               "六分位 GLM Logistic 回归 Table 2（Q1–Q6，Q1 参照）")
