###############################################################################
#  logistic_binary_glm — 二分类（中位数二分）GLM Logistic 回归（Table 2 风格）。
#                        Q1（低组）为参照；Crude / Model1 / Model2 + 随机搜索；
#                        export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results   = "Model1Factors"
#  require_ctx_results  += "final_features"
#
#  logistic_binary_glm = list(
#    group_var              = NULL,    # 非 NULL → 直接用已有二分类列，跳过中位数计算
#    group_levels           = NULL,    # factor 水平顺序（第一个为参照）；NULL 时按字母序
#    include_continuous_row = NULL,    # NULL → 自动（predefined 时 FALSE，否则 TRUE）
#    model1_factors         = NULL,
#    random_search = list(
#      max_outer_attempts    = 100L,   # 外层循环次数（协变量数量递增）
#      max_inner_attempts    = 10L,    # 内层循环次数（同一 k 下反复随机抽）
#      initial_factors_n     = 1L,     # 初始协变量数量，逐轮递增
#      p_threshold           = 0.05,   # 判定阈值
#      seed                  = NULL    # 可选：设种子保证可复现
#    ),
#    pause_enable           = TRUE,
#    pause_on_search_fail   = FALSE,
#    table_filename         = NULL
#  ),
#
#  register_block: "logistic_binary_glm"
#  典型流水线: 发病二分类；中位数二分暴露；随机搜索 Model2 协变量
#  块内 bl_cfg <- cfg$logistic_binary_glm
###############################################################################

.lqg04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqg04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "logistic_binary_glm", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: logistic_binary_glm — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.lqg04_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
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
  rownames(rt) <- NULL; rt
}

block_logistic_binary_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- if (exists("logistic_glm_resolve_bl_cfg", mode = "function")) {
    logistic_glm_resolve_bl_cfg(ctx, "logistic_binary_glm")
  } else {
    cfg$logistic_binary_glm %||% list()
  }
  phase <- as.character(bl_cfg$phase %||% "screen")[1L]

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    .lqg04_pause(ctx, "未找到分析数据", "请先运行上游数据准备 block")
  # 若 index_var 是 Subphenotype，优先用 lca 产出的 df_final（含亚型列）
  df_lca <- ctx$results$df_final
  if (!is.null(df_lca) && is.data.frame(df_lca) && "Subphenotype" %in% names(df_lca)) {
    extra <- setdiff(names(df_lca), names(data))
    if (length(extra) > 0L) {
      rn_data <- rownames(data); rn_lca <- rownames(df_lca)
      if (!is.null(rn_data) && !is.null(rn_lca) && length(intersect(rn_data, rn_lca)) > 0L) {
        data <- merge(data, df_lca[, extra, drop = FALSE], by = "row.names", all.x = TRUE)
        rownames(data) <- data$Row.names; data$Row.names <- NULL
      } else if (nrow(df_lca) == nrow(data)) {
        data <- cbind(data, df_lca[, extra, drop = FALSE])
      }
    }
  }

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  }
  index_var     <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var))
    stop("logistic_binary_glm: index_var 未设置。")
  if (!index_var %in% names(data)) stop("logistic_binary_glm: index_var '", index_var, "' 不在数据列中。")
  if (!outcome_col %in% names(data)) stop("logistic_binary_glm: outcome_col '", outcome_col, "' 不在数据列中。")

  group_var_name <- bl_cfg$group_var
  predefined     <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data)
  data2 <- data

  if (!isTRUE(predefined) && exists("pipeline_index_as_numeric", mode = "function")) {
    data2[[index_var]] <- pipeline_index_as_numeric(data2[[index_var]])
  }

  if (predefined) {
    raw_levels  <- if (!is.null(bl_cfg$group_levels) && length(bl_cfg$group_levels) > 0L) {
      as.character(bl_cfg$group_levels)
    } else {
      sort(unique(as.character(data2[[group_var_name]][!is.na(data2[[group_var_name]])])))
    }
    data2$Group <- factor(data2[[group_var_name]], levels = raw_levels)
    data2$Num   <- as.numeric(data2$Group)
    cutoffs     <- setNames(rep("", length(raw_levels)), raw_levels)
    if (identical(phase, "rcs")) {
      cutoffs <- logistic_rcs_prepare_cutoffs(raw_levels, ctx)
    }
    cli::cli_alert_info("logistic_binary_glm: 使用已有分类列 '{group_var_name}'")
  } else {
    q_med       <- as.numeric(quantile(data2[[index_var]], probs = 0.5, na.rm = TRUE))
    data2$Group <- ifelse(data2[[index_var]] < q_med, "Q1", "Q2")
    data2$Group <- factor(data2$Group, levels = c("Q1", "Q2"))
    data2$Num   <- as.numeric(data2$Group)
    raw_levels  <- c("Q1", "Q2")
    cutoffs     <- c(Q1 = paste0("< ", round(q_med, 2)), Q2 = paste0("\u2265 ", round(q_med, 2)))
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)

  # 多亚型 Subphenotype：直接输出简化多水平 logistic，不走随机搜索路径
  is_subphenotype <- !is.null(index_var) && index_var == "Subphenotype"
  if (predefined && is_subphenotype) {
    data3 <- data2
    data3[[outcome_col]] <- as.character(data3[[outcome_col]])
    data3[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data3[[outcome_col]], cfg))
  } else {
    as.integer(data3[[outcome_col]] == disease_label)
  }
    data3$.outcome_tmp   <- data3[[outcome_col]]  # 安全的临时列名（避免 in-hospital 被解析为关键字）
    data3$Group <- factor(as.character(data3[[group_var_name]]), levels = raw_levels)
    keep3 <- unique(c(".outcome_tmp", "Group", as.character(bl_cfg$model2_factors %||% ctx$results$Model2Factors %||% "Age")))
    keep3 <- intersect(keep3, names(data3))
    dt3   <- stats::na.omit(data3[, keep3, drop = FALSE])
    m2fac <- intersect(setdiff(keep3, c(".outcome_tmp", "Group")), names(dt3))
    fml_c <- as.formula(".outcome_tmp ~ Group")
    fml_a <- if (length(m2fac) > 0L) as.formula(paste0(".outcome_tmp ~ Group + ", paste(m2fac, collapse="+"))) else fml_c
    get_or <- function(fml) tryCatch({
      m <- logistic_glm_binomial_safe(fml, dt3)
      sm <- summary(m)$coefficients
      sm <- sm[grepl("^Group", rownames(sm)), , drop = FALSE]
      data.frame(Term = rownames(sm),
                 OR = round(exp(sm[,"Estimate"]),3),
                 CI95 = apply(logistic_safe_confint(m)[grepl("^Group", rownames(logistic_safe_confint(m))), , drop=FALSE], 1,
                              function(r) paste0("(", round(exp(r[1]),3),",", round(exp(r[2]),3),")")),
                 P = pub_format_p_cell(sm[,"Pr(>|z|)"]), stringsAsFactors=FALSE)
    }, error = function(e) NULL)
    or_crude <- get_or(fml_c); or_adj <- get_or(fml_a)
    rt_out   <- if (!is.null(or_crude) && !is.null(or_adj)) {
      cbind(or_crude, Adj_OR = or_adj$OR, Adj_CI95 = or_adj$CI95, Adj_P = or_adj$P)
    } else or_crude %||% data.frame(note = "Logistic fit failed")
    ctx <- save_result(ctx, "logistic_subtype_table", rt_out, "Table_Logistic_Subphenotype.csv")
    tryCatch(export_sci_table(rt_out,
      file.path(ctx$output_dir_tables %||% ctx$output_dir,
                paste0("Table_Logistic_Subphenotype_k", nlevels(dt3$Group), ".xlsx")),
      title = paste0("Logistic regression: Subphenotype, outcome=", outcome_col)),
      error = function(e) cli::cli_alert_warning("logistic table export failed: {e$message}"))
    cli::cli_alert_success("logistic_binary_glm (Subphenotype multi-level) 完成。")
    return(ctx)
  }

  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data2[[outcome_col]], cfg))
  } else {
    as.integer(data2[[outcome_col]] == disease_label)
  }

  excl_cols <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_binary_glm",
    build_table_fn = function(m1, m2) {
      .lqg04_Tb_ModelGroup3_OR(
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
  Model3Factors    <- character(0)
  m3_sig           <- FALSE
  if (exists("pipeline_glm_apply_model3", mode = "function") && !is.null(tb01)) {
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
        "logistic_binary_glm (rcs): 未找到 RCS 分组列 '",
        gv %||% "", "'；请先运行 rcs_incidence。",
        call. = FALSE
      )
    }
  }

  block_name <- ctx$current_block %||% "logistic_binary_glm"
  if (exists("logistic_gate_apply_after_table_defer_stop", mode = "function")) {
    ctx <- logistic_gate_apply_after_table_defer_stop(
      ctx, bl_cfg, tb01, raw_levels, block_name
    )
  } else if (exists("logistic_gate_apply_after_table", mode = "function")) {
    ctx <- logistic_gate_apply_after_table(ctx, bl_cfg, tb01, raw_levels, block_name)
  }

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

  is_rcs <- identical(phase, "rcs")
  as_main <- if (exists("logistic_glm_export_as_main", mode = "function")) {
    logistic_glm_export_as_main(ctx, "binary", is_rcs = is_rcs)
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
      ix_disp, disease_disp,
      scheme = if (isTRUE(bl_cfg$categorical_exposure)) "" else "binary",
      is_rcs = is_rcs, unweighted = isTRUE(has_weighted_main),
      native_levels = isTRUE(bl_cfg$categorical_exposure)
    )
  } else if (is_rcs) {
    paste0("Logistic regression of ", ix_disp, " RCS cutoff")
  } else if (isTRUE(has_weighted_main)) {
    paste0("Logistic regression of ", ix_disp, " binary unweighted")
  } else {
    paste0("Logistic regression of ", ix_disp, " binary")
  }
  do_export <- if (exists("logistic_glm_should_export", mode = "function")) {
    logistic_glm_should_export(ctx, "binary", is_rcs = is_rcs, bl_cfg = bl_cfg)
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
             error = function(e) cli::cli_alert_warning("logistic_binary_glm: export 失败: {e$message}"))
  }
  if (exists("logistic_gate_throw_pending_stop", mode = "function")) {
    logistic_gate_throw_pending_stop(ctx)
  }

  ctx$results$logistic_table2 <- rt
  if (isTRUE(as_main)) {
    ctx$results$logistic_grouping_scheme <- "binary"
  }
  ctx$results$logistic_model1_factors <- Model1Factors
  ctx$results$logistic_model2_factors <- Model2Factors
  ctx$results$logistic_sample_factors <- sample_factors
  ctx <- save_result(ctx, "logistic_binary_glm_Model2Factors", Model2Factors, "Model2Factors_binary_glm.csv")
  cli::cli_alert_success("logistic_binary_glm 完成"); ctx
}

register_block("logistic_binary_glm", block_logistic_binary_glm,
               "二分类 GLM Logistic 回归 Table 2（中位数二分，Q1 参照）")
register_block("logistic_binary_glm_rcs", block_logistic_binary_glm,
               "二分类 GLM Logistic（RCS cutoff 分组复跑）")
