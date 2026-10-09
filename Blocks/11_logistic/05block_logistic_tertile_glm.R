###############################################################################
#  logistic_tertile_glm — 三分位（T1/T2/T3）GLM Logistic 回归（Table 2 风格）。
#                         T1（低组）为参照；Crude / Model1 / Model2 + 随机搜索；
#                         export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results   = "Model1Factors"
#  require_ctx_results  += "final_features"
#
#  logistic_tertile_glm = list(
#    group_var              = NULL,    # 非 NULL → 直接用已有三分类列，跳过三分位计算
#    group_levels           = NULL,    # factor 水平顺序（第一个为参照）；NULL 时按字母序
#    include_continuous_row = NULL,    # NULL → 自动（predefined 时 FALSE，否则 TRUE）
#    model1_factors         = NULL,
#    random_search = list(
#      max_attempts         = 100L,
#      sample_n             = 8L,
#      p_threshold          = 0.05     # T3 三模型 + p_trend 三模型均须 < 此值
#    ),
#    pause_enable           = TRUE,
#    pause_on_search_fail   = FALSE,
#    table_filename         = NULL
#  ),
#
#  register_block: "logistic_tertile_glm"
#  块内 bl_cfg <- cfg$logistic_tertile_glm
###############################################################################

.lqg05_tertile_from_cfg <- function(x, bl_cfg = list()) {
  t_right <- isTRUE(bl_cfg$tertile_right %||% TRUE)
  t_labs <- bl_cfg$tertile_labels %||% c("Q1", "Q2", "Q3")
  if (length(t_labs) != 3L) t_labs <- c("Q1", "Q2", "Q3")
  qs <- as.numeric(stats::quantile(x, probs = c(1 / 3, 2 / 3), na.rm = TRUE))
  grp <- cut(
    x,
    breaks = c(-Inf, qs[1], qs[2], Inf),
    labels = t_labs,
    right = t_right,
    include.lowest = TRUE
  )
  grp <- factor(grp, levels = t_labs)
  if (!t_right) {
    cutoffs <- stats::setNames(
      c(
        paste0("< ", round(qs[1], 2)),
        paste0(round(qs[1], 2), " -< ", round(qs[2], 2)),
        paste0("\u2265 ", round(qs[2], 2))
      ),
      t_labs
    )
  } else {
    cutoffs <- stats::setNames(
      c(
        paste0("< ", round(qs[1], 2)),
        paste0(round(qs[1], 2), " \u2013 ", round(qs[2], 2)),
        paste0("\u2265 ", round(qs[2], 2))
      ),
      t_labs
    )
  }
  list(group = grp, cutoffs = cutoffs, levels = t_labs, qs = qs)
}

.lqg05_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqg05_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "logistic_tertile_glm", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: logistic_tertile_glm — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.lqg05_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      cutoffs, group_labels, include_continuous = TRUE) {
  is_rcs_grp <- isTRUE(attr(cutoffs, "is_rcs_group") %||% FALSE)
  fml_f01 <- as.formula(paste0(ResultName, "~", FactorName))
  fml_f02 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model1Factors), collapse = "+")))
  fml_f03 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model2Factors), collapse = "+")))
  fml_t01 <- as.formula(paste0(ResultName, "~", TrendName))
  fml_t02 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model1Factors), collapse = "+")))
  fml_t03 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model2Factors), collapse = "+")))

  mf  <- logistic_glm_binomial_safe(fml_f01, Data)
  mf2 <- logistic_glm_binomial_safe(fml_f02, Data)
  mf3 <- logistic_glm_binomial_safe(fml_f03, Data)
  mt  <- logistic_glm_binomial_safe(fml_t01, Data)
  mt2 <- logistic_glm_binomial_safe(fml_t02, Data)
  mt3 <- logistic_glm_binomial_safe(fml_t03, Data)

  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .ci <- function(m, row) {
    ci <- logistic_safe_confint(m)
    paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")")
  }
  .pct <- function(lv) {
    if (exists("pub_glm_group_n_cell_from_data", mode = "function")) {
      pub_glm_group_n_cell_from_data(Data, ResultName, FactorName, lv)
    } else {
      n <- as.numeric(cnt[lv])
      paste0(n, "(", round(n / n_total * 100, 2), "%)")
    }
  }
  n_hdr <- if (exists("pub_glm_group_n_header", mode = "function")) {
    pub_glm_group_n_header()
  } else {
    "Events / N (%)"
  }

  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", n_hdr,
             "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11))

  ref_lv   <- group_labels[1]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")

  non_ref_lvs  <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv <- non_ref_lvs[i]; idx <- i + 1L
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(coef(mf)[idx]),  3), .ci(mf,  idx), logistic_glm_format_p(summary(mf)$coefficients[idx, 4], is_rcs_grp),
      round(exp(coef(mf2)[idx]), 3), .ci(mf2, idx), logistic_glm_format_p(summary(mf2)$coefficients[idx, 4], is_rcs_grp),
      round(exp(coef(mf3)[idx]), 3), .ci(mf3, idx), logistic_glm_format_p(summary(mf3)$coefficients[idx, 4], is_rcs_grp))
  })

  # RCS cutoff 分组表不放 p for trend
  Line_trend <- if (isTRUE(attr(cutoffs, "is_rcs_group") %||% FALSE)) {
    NULL
  } else {
    c("p for trend", rep("", 4),
      pub_format_p_cell(summary(mt)$coefficients[2, 4]), "", "",
      pub_format_p_cell(summary(mt2)$coefficients[2, 4]), "", "",
      pub_format_p_cell(summary(mt3)$coefficients[2, 4]))
  }

  if (include_continuous) {
    fml_c01 <- as.formula(paste0(ResultName, "~", ContinuousName))
    fml_c02 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model1Factors), collapse = "+")))
    fml_c03 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model2Factors), collapse = "+")))
    mc <- logistic_glm_binomial_safe(fml_c01, Data)
    mc2 <- logistic_glm_binomial_safe(fml_c02, Data)
    mc3 <- logistic_glm_binomial_safe(fml_c03, Data)
    .ci_c <- function(m) { ci <- logistic_safe_confint(m); paste0("(", round(exp(ci[2,1]),3), ",", round(exp(ci[2,2]),3), ")") }
    Line3 <- c(ContinuousName, rep("", 11))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(coef(mc)[2]),  3), .ci_c(mc),  logistic_glm_format_p(summary(mc)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc2)[2]), 3), .ci_c(mc2), logistic_glm_format_p(summary(mc2)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc3)[2]), 3), .ci_c(mc3), logistic_glm_format_p(summary(mc3)$coefficients[2, 4], is_rcs_grp))
    parts <- c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref)
  } else {
    parts <- c(list(Line1, Line2, Line5, Line_ref), lines_nonref)
  }
  if (!is.null(Line_trend)) parts <- c(parts, list(Line_trend))
  rt <- do.call(rbind, parts)
  rownames(rt) <- NULL
  colnames(rt) <- NULL
  rt
}

block_logistic_tertile_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- if (exists("logistic_glm_resolve_bl_cfg", mode = "function")) {
    logistic_glm_resolve_bl_cfg(ctx, "logistic_tertile_glm")
  } else {
    cfg$logistic_tertile_glm %||% list()
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    cli::cli_alert_info("分类暴露：跳过 logistic_tertile_glm，仅回归变量本身")
    return(ctx)
  }
  phase <- as.character(bl_cfg$phase %||% "screen")[1L]

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    .lqg05_pause(ctx, "未找到分析数据", "请先运行上游数据准备 block")

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  }
  index_var     <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var))
    stop("logistic_tertile_glm: index_var 未设置。")
  if (!index_var %in% names(data)) stop("logistic_tertile_glm: index_var '", index_var, "' 不在数据列中。")
  if (!outcome_col %in% names(data)) stop("logistic_tertile_glm: outcome_col '", outcome_col, "' 不在数据列中。")

  group_var_name <- bl_cfg$group_var
  predefined     <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data)
  data2 <- data

  if (!isTRUE(predefined) && exists("pipeline_index_as_numeric", mode = "function")) {
    data2[[index_var]] <- pipeline_index_as_numeric(data2[[index_var]])
  }

  if (predefined) {
    raw_levels  <- bl_cfg$group_levels %||% sort(unique(as.character(data2[[group_var_name]])))
    data2$Group <- factor(data2[[group_var_name]], levels = raw_levels)
    data2$Num   <- as.numeric(data2$Group)
    cutoffs     <- setNames(rep("", length(raw_levels)), raw_levels)
    if (identical(phase, "rcs")) {
      cutoffs <- logistic_rcs_prepare_cutoffs(raw_levels, ctx)
    }
    cli::cli_alert_info("logistic_tertile_glm: 使用已有分类列 '{group_var_name}'")
  } else {
    tert        <- .lqg05_tertile_from_cfg(data2[[index_var]], bl_cfg)
    data2$Group <- tert$group
    data2$Num   <- as.numeric(data2$Group)
    raw_levels  <- tert$levels
    cutoffs     <- tert$cutoffs
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)

  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data2[[outcome_col]], cfg))
  } else {
    as.integer(data2[[outcome_col]] == disease_label)
  }

  excl_cols <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_tertile_glm",
    build_table_fn = function(m1, m2) {
      .lqg05_Tb_ModelGroup3_OR(
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

  if (is.null(tb01)) stop("logistic_tertile_glm: 未产生有效结果。")

  Model3Factors <- character(0)
  m3_sig <- FALSE
  if (exists("pipeline_glm_apply_model3", mode = "function")) {
    m3a <- pipeline_glm_apply_model3(
      ctx, cfg, data2, outcome_col, index_var, "Group", "Num",
      Model2Factors, tb01, raw_levels
    )
    ctx <- m3a$ctx
    tb01 <- m3a$tb
    Model3Factors <- m3a$M3
    m3_sig <- m3a$m3_sig
  }

  if (identical(phase, "rcs")) {
    gv <- bl_cfg$group_var
    if (is.null(gv) || !nzchar(gv) || !gv %in% names(data2)) {
      stop(
        "logistic_tertile_glm (rcs): 未找到 RCS 分组列 '",
        gv %||% "", "'；请先运行 rcs_incidence。",
        call. = FALSE
      )
    }
  }

  block_name <- ctx$current_block %||% "logistic_tertile_glm"
  if (exists("logistic_gate_apply_after_table", mode = "function")) {
    ctx <- logistic_gate_apply_after_table(ctx, bl_cfg, tb01, raw_levels, block_name)
  }

  rt <- format_logistic_table2_pvalues(tb01)
  rownames(rt) <- NULL

  h1 <- as.character(rt[1, ]); h2 <- as.character(rt[2, ])
  rt_body <- rt[-c(1L, 2L), , drop = FALSE]; rownames(rt_body) <- NULL
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))

  is_rcs <- identical(phase, "rcs")
  as_main <- if (exists("logistic_glm_export_as_main", mode = "function")) {
    logistic_glm_export_as_main(ctx, "tertile", is_rcs = is_rcs)
  } else {
    TRUE
  }
  if (isTRUE(bl_cfg$force_export %||% FALSE) && !isTRUE(is_rcs)) as_main <- TRUE
  table_kind <- if (isTRUE(as_main)) "main_table" else "supp_table"

  has_weighted_main <- !is.null(ctx$results$logistic_table2_weighted) ||
    !is.null(ctx$results$nhanes_logistic_table2)
  disease_disp <- gsub("_", " ", as.character(cfg$project$disease %||% outcome_col), fixed = TRUE)
  ix_disp <- gsub("_", " ", as.character(index_var), fixed = TRUE)
  caption <- if (exists("logistic_glm_pub_caption", mode = "function")) {
    logistic_glm_pub_caption(
      ix_disp, disease_disp, scheme = "tertile",
      is_rcs = is_rcs, unweighted = isTRUE(has_weighted_main)
    )
  } else if (is_rcs) {
    paste0("Logistic regression of ", ix_disp, " RCS cutoff")
  } else if (isTRUE(has_weighted_main)) {
    paste0("Logistic regression of ", ix_disp, " tertile unweighted")
  } else {
    paste0("Logistic regression of ", ix_disp, " tertile")
  }
  do_export <- if (exists("logistic_glm_should_export", mode = "function")) {
    logistic_glm_should_export(ctx, "tertile", is_rcs = is_rcs, bl_cfg = bl_cfg)
  } else {
    isTRUE(as_main) || is_rcs ||
      !isTRUE((cfg$dual_db %||% list())$enable) ||
      isTRUE(has_weighted_main)
  }
  if (isTRUE(do_export)) {
    if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
      pub <- pub_paths(ctx, ctx$output_dir_tables, table_kind, caption, "xlsx")
      title <- pub$title
      filepath <- pub$filepath
    } else {
      title <- pub_title(ctx, table_kind, caption)
      filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
    }
    tryCatch(export_sci_table(rt_body, filepath, title = title,
                              header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE,
                              table_footnotes = logistic_glm_table_footnotes(Model1Factors, Model2Factors, Model3Factors, m3_sig)),
             error = function(e) cli::cli_alert_warning("logistic_tertile_glm: export 失败: {e$message}"))
  }

  if (isTRUE(as_main)) {
    ctx$results$logistic_table2 <- rt
    ctx$results$logistic_grouping_scheme <- "tertile"
  } else {
    # 双库闸门 C 降级重导需要各档表；非主表也写入 results 供 checkpoint 读取
    ctx$results$logistic_table2 <- rt
  }
  if (exists(".lnw00_table_pvals", mode = "function")) {
    pv <- .lnw00_table_pvals(rt)
    ctx$results$logistic_table2_trend_p <- list(
      crude = pv$trend_crude,
      model1 = pv$trend_m1,
      model2 = pv$trend_m2
    )
  }
  ctx$results$logistic_model1_factors <- Model1Factors
  ctx$results$logistic_model2_factors <- Model2Factors
  ctx$results$logistic_sample_factors <- sample_factors
  ctx <- save_result(ctx, "logistic_tertile_glm_Model2Factors", Model2Factors, "Model2Factors_tertile_glm.csv")
  cli::cli_alert_success("logistic_tertile_glm 完成"); ctx
}

register_block("logistic_tertile_glm", block_logistic_tertile_glm,
               "三分位 GLM Logistic 回归 Table 2（T1/T2/T3，T1 参照）")
register_block("logistic_tertile_glm_rcs", block_logistic_tertile_glm,
               "三分位 GLM Logistic（RCS cutoff 分组复跑）")
