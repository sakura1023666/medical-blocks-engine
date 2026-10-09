###############################################################################
#  logistic_binary_clogit — 二分类（中位数二分）条件 Logistic 回归（Table 2 风格）。
#                           Q1 为参照；clogit + strata(strata_var)；
#                           Crude / Model1 / Model2 + 随机搜索；export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_strata_col    = bl_cfg$strata_var  # 默认 "match_id"
#  require_ctx_results   = "Model1Factors"
#  require_ctx_results  += "final_features"
#  require_package       = "survival"
#
#  logistic_binary_clogit = list(
#    group_var              = NULL,      # 非 NULL → 直接用已有二分类列，跳过中位数计算
#    group_levels           = NULL,
#    include_continuous_row = NULL,
#    strata_var             = "match_id",
#    filter_age_years       = TRUE,
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
#  clogit 系数提取说明：
#    单变量模型：coef(m) 单值，summary(m)$coefficients[5] P 值
#    多变量：coef(m)[1]，summary(m)$coefficients[1,5]
#    Q 组因子模型：coef[i-1] = 第 i 组（i>=2，无截距）
#
#  register_block: "logistic_binary_clogit"
#  匹配设计二分类 clogit；strata_var 默认 match_id
#  块内 bl_cfg <- cfg$logistic_binary_clogit
###############################################################################

.lqc07_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqc07_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "logistic_binary_clogit", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: logistic_binary_clogit — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.lqc07_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      strata_var, cutoffs, group_labels,
                                      include_continuous = TRUE) {
  .st <- function(vars) paste(c(vars, paste0("strata(", strata_var, ")")), collapse = "+")

  fml_f01 <- as.formula(paste0(ResultName, "~", .st(FactorName)))
  fml_f02 <- as.formula(paste0(ResultName, "~", .st(c(FactorName, Model1Factors))))
  fml_f03 <- as.formula(paste0(ResultName, "~", .st(c(FactorName, Model2Factors))))
  fml_t01 <- as.formula(paste0(ResultName, "~", .st(TrendName)))
  fml_t02 <- as.formula(paste0(ResultName, "~", .st(c(TrendName, Model1Factors))))
  fml_t03 <- as.formula(paste0(ResultName, "~", .st(c(TrendName, Model2Factors))))

  mf  <- survival::clogit(fml_f01, data = Data, method = "exact")
  mf2 <- survival::clogit(fml_f02, data = Data, method = "exact")
  mf3 <- survival::clogit(fml_f03, data = Data, method = "exact")
  mt  <- survival::clogit(fml_t01, data = Data, method = "exact")
  mt2 <- survival::clogit(fml_t02, data = Data, method = "exact")
  mt3 <- survival::clogit(fml_t03, data = Data, method = "exact")

  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .pct <- function(lv) { n <- as.numeric(cnt[lv]); paste0(n, "(", round(n/n_total*100, 2), "%)") }
  .ci_f <- function(m, idx) {
    ci <- logistic_safe_confint(m)
    paste0("(", round(exp(ci[idx, 1]), 3), ",", round(exp(ci[idx, 2]), 3), ")")
  }

  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)",
             "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11))

  ref_lv   <- group_labels[1]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")

  non_ref_lvs  <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv <- non_ref_lvs[i]; idx <- i
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(coef(mf)[idx]),  3), .ci_f(mf,  idx), pub_format_p_cell(summary(mf)$coefficients[idx, 5]),
      round(exp(coef(mf2)[idx]), 3), .ci_f(mf2, idx), pub_format_p_cell(summary(mf2)$coefficients[idx, 5]),
      round(exp(coef(mf3)[idx]), 3), .ci_f(mf3, idx), pub_format_p_cell(summary(mf3)$coefficients[idx, 5]))
  })

  Line_trend <- c("p for trend", rep("", 4),
                  pub_format_p_cell(summary(mt)$coefficients[1, 5]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[1, 5]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[1, 5]))

  if (include_continuous) {
    fml_c01 <- as.formula(paste0(ResultName, "~", .st(ContinuousName)))
    fml_c02 <- as.formula(paste0(ResultName, "~", .st(c(ContinuousName, Model1Factors))))
    fml_c03 <- as.formula(paste0(ResultName, "~", .st(c(ContinuousName, Model2Factors))))
    mc  <- survival::clogit(fml_c01, data = Data, method = "exact")
    mc2 <- survival::clogit(fml_c02, data = Data, method = "exact")
    mc3 <- survival::clogit(fml_c03, data = Data, method = "exact")
    .ci_c_s <- function(m) { ci <- logistic_safe_confint(m); paste0("(", round(exp(ci[1]),3), ",", round(exp(ci[2]),3), ")") }
    .ci_c_m <- function(m) { ci <- logistic_safe_confint(m); paste0("(", round(exp(ci[1,1]),3), ",", round(exp(ci[1,2]),3), ")") }
    Line3 <- c(ContinuousName, rep("", 11))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(coef(mc)),     3), .ci_c_s(mc),  pub_format_p_cell(summary(mc)$coefficients[5]),
               round(exp(coef(mc2)[1]), 3), .ci_c_m(mc2), pub_format_p_cell(summary(mc2)$coefficients[1, 5]),
               round(exp(coef(mc3)[1]), 3), .ci_c_m(mc3), pub_format_p_cell(summary(mc3)$coefficients[1, 5]))
    rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref), lines_nonref, list(Line_trend)))
  }
  rownames(rt) <- NULL; rt
}

block_logistic_binary_clogit <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$logistic_binary_clogit %||% list()

  if (!requireNamespace("survival", quietly = TRUE))
    stop("logistic_binary_clogit: 需要 survival 包（clogit），请先安装。")

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    .lqc07_pause(ctx, "未找到分析数据", "请先运行上游数据准备 block")

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  }
  index_var     <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  strata_var    <- bl_cfg$strata_var %||% "match_id"

  if (is.null(index_var) || !nzchar(index_var)) stop("logistic_binary_clogit: index_var 未设置。")
  if (!index_var   %in% names(data)) stop("logistic_binary_clogit: index_var '",   index_var,   "' 不在数据列中。")
  if (!outcome_col %in% names(data)) stop("logistic_binary_clogit: outcome_col '", outcome_col, "' 不在数据列中。")
  if (!strata_var  %in% names(data)) stop("logistic_binary_clogit: strata_var '",  strata_var,  "' 不在数据列中。")
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, data, index_var)
  }

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
  } else {
    q_med       <- as.numeric(quantile(data2[[index_var]], probs = 0.5, na.rm = TRUE))
    data2$Group <- ifelse(data2[[index_var]] < q_med, "Q1", "Q2")
    data2$Group <- factor(data2$Group, levels = c("Q1", "Q2"))
    data2$Num   <- as.numeric(data2$Group)
    raw_levels  <- c("Q1", "Q2")
    cutoffs     <- c(Q1 = paste0("< ", round(q_med, 2)), Q2 = paste0("\u2265 ", round(q_med, 2)))
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)

  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data2[[outcome_col]], cfg))
  } else {
    as.integer(data2[[outcome_col]] == disease_label)
  }

  excl_cols <- c(outcome_col, index_var, "Group", "Num", strata_var, if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_binary_clogit",
    build_table_fn = function(m1, m2) {
      .lqc07_Tb_ModelGroup3_OR(
        outcome_col, index_var, "Group", "Num",
        data2, m1, m2, strata_var, cutoffs, raw_levels, include_cont
      )
    },
    filter_m1 = function(m1) {
      m1 <- as.character(m1)
      if (isTRUE(bl_cfg$filter_age_years %||% TRUE)) {
        if ("Age_Years" %in% m1 && "Age_Group" %in% m1) m1 <- m1[m1 != "Age_Group"]
        m1 <- m1[m1 != "Age_Years"]
      } else if ("Age_Years" %in% m1 && "Age_Group" %in% m1) {
        m1 <- m1[m1 != "Age_Group"]
      }
      setdiff(intersect(m1, colnames(data2)), strata_var)
    },
    combine_model2_fn = function(m1, sampled) setdiff(unique(c(m1, sampled)), strata_var)
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

  caption <- paste0("Conditional logistic regression analysis of ", index_var, " and ", outcome_col, " - binary (clogit, Q1 Ref)")
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
           error = function(e) cli::cli_alert_warning("logistic_binary_clogit: export 失败: {e$message}"))

  ctx$results$logistic_table2         <- rt
  ctx$results$logistic_model1_factors <- Model1Factors
  ctx$results$logistic_model2_factors <- Model2Factors
  ctx$results$logistic_sample_factors <- sample_factors
  ctx <- save_result(ctx, "logistic_binary_clogit_Model2Factors", Model2Factors, "Model2Factors_binary_clogit.csv")
  cli::cli_alert_success("logistic_binary_clogit 完成"); ctx
}

register_block("logistic_binary_clogit", block_logistic_binary_clogit,
               "二分类条件 Logistic 回归 Table 2（clogit + strata，中位数二分，Q1 参照）")
