###############################################################################
#  logistic_quintile_glm — 五分位 Q1–Q5 GLM Logistic 回归（Table 2 风格）。
#                          Q1 为参照；Crude / Model1 / Model2 + 随机搜索协变量；
#                          连续暴露 + 五分位分组 + 趋势检验；export_sci_table 三线表。
#                          逻辑来源：C01_LogisticCode_quintiles.R 第 1–610 行。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned  # 必须存在且含 outcome/index 列
#  require_ctx_results   = "Model1Factors"  # 优先读取；为 NULL 时 fallback 到 pos.factors[model1_pos_idx]
#  require_ctx_results  += "final_features" # 随机搜索候选池；为 NULL 时用数据所有协变量列
#
#  logistic_quintile_glm = list(
#    # ── 分组模式 ──────────────────────────────────────────────────────────
#    group_var              = NULL,    # 非 NULL → 数据中已有分类列，直接用；跳过五分位计算
#    group_levels           = NULL,    # 指定 factor 水平顺序（第一个为参照）；NULL 时按字母序
#    include_continuous_row = NULL,    # NULL → 自动（predefined 时 FALSE，否则 TRUE）
#    # ── 协变量 ────────────────────────────────────────────────────────────
#    model1_factors         = NULL,    # 非 NULL 时覆盖 ctx$results$Model1Factors
#    model1_pos_idx         = 8L,      # ctx$results$Model1Factors 为 NULL 时，取 pos.factors[model1_pos_idx]
#    # ── 双层嵌套随机搜索 ──────────────────────────────────────────────────
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
#  register_block: "logistic_quintile_glm"
#  典型流水线: incidence；五分位暴露；随机搜索 Model2；源 C01_LogisticCode_quintiles.R
#  块内 bl_cfg <- cfg$logistic_quintile_glm
###############################################################################

# ── 私有工具 ─────────────────────────────────────────────────────────────────

.lqq02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqq02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block      = "logistic_quintile_glm",
    reason     = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: logistic_quintile_glm — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

# ── 内嵌 Tb_ModelGroup3_OR（GLM 版，参照组 = group_labels[1]）────────────────
#
#  随机搜索判定（原 quintiles 逻辑）：
#    tb01 最后一行（p for trend）三列 + 倒数第二行（末组）第 12 列均 < bz2。
#  使用 nrow(tb01) 动态定位，与 include_continuous 无关。

.lqq02_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      cutoffs, group_labels,
                                      include_continuous = TRUE) {
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

  n_total <- nrow(Data)
  cnt     <- table(Data[[FactorName]])

  .ci_str <- function(m, row) {
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

  non_ref_lvs <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv  <- non_ref_lvs[i]
    idx <- i + 1L
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(coef(mf)[idx]),  3), .ci_str(mf,  idx), logistic_glm_format_p(summary(mf)$coefficients[idx, 4], is_rcs_grp),
      round(exp(coef(mf2)[idx]), 3), .ci_str(mf2, idx), logistic_glm_format_p(summary(mf2)$coefficients[idx, 4], is_rcs_grp),
      round(exp(coef(mf3)[idx]), 3), .ci_str(mf3, idx), logistic_glm_format_p(summary(mf3)$coefficients[idx, 4], is_rcs_grp))
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
    mc  <- logistic_glm_binomial_safe(fml_c01, Data)
    mc2 <- logistic_glm_binomial_safe(fml_c02, Data)
    mc3 <- logistic_glm_binomial_safe(fml_c03, Data)
    .ci_c <- function(m) {
      ci <- logistic_safe_confint(m)
      paste0("(", round(exp(ci[2, 1]), 3), ",", round(exp(ci[2, 2]), 3), ")")
    }
    Line3 <- c(ContinuousName, rep("", 11))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(coef(mc)[2]), 3),  .ci_c(mc),  logistic_glm_format_p(summary(mc)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc2)[2]), 3), .ci_c(mc2), logistic_glm_format_p(summary(mc2)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc3)[2]), 3), .ci_c(mc3), logistic_glm_format_p(summary(mc3)$coefficients[2, 4], is_rcs_grp))
    parts <- c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref)
  } else {
    parts <- c(list(Line1, Line2, Line5, Line_ref), lines_nonref)
  }
  if (!is.null(Line_trend)) parts <- c(parts, list(Line_trend))
  rt <- do.call(rbind, parts)

  rownames(rt) <- NULL
  rt
}

# ── 主块函数 ─────────────────────────────────────────────────────────────────

block_logistic_quintile_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- if (exists("logistic_glm_resolve_bl_cfg", mode = "function")) {
    logistic_glm_resolve_bl_cfg(ctx, "logistic_quintile_glm")
  } else {
    cfg$logistic_quintile_glm %||% list()
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    cli::cli_alert_info("分类暴露：跳过 logistic_quintile_glm，仅回归变量本身")
    return(ctx)
  }
  phase <- as.character(bl_cfg$phase %||% "screen")[1L]

  # ── 数据 ────────────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    .lqq02_pause(ctx, "未找到分析数据（ctx$data$imputed / cleaned 均为空）",
                 "请先运行上游数据准备 block（imputation 或等价步骤）")
  }

  # ── 基本参数 ────────────────────────────────────────────────────────────────
  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  }
  index_var     <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) {
    stop("logistic_quintile_glm: index_var 未设置，请在 config$logistic_quintile_glm$index_var 中指定。")
  }
  if (!index_var %in% names(data)) {
    stop("logistic_quintile_glm: index_var '", index_var, "' 不在数据列中。")
  }
  if (!outcome_col %in% names(data)) {
    stop("logistic_quintile_glm: outcome_col '", outcome_col, "' 不在数据列中。")
  }

  # ── 随机搜索参数 ────────────────────────────────────────────────────────────
  rs_cfg <- bl_cfg$random_search %||% list()
  bz2    <- as.numeric(rs_cfg$p_threshold %||% 0.05)

  # ── 分组：已有分类列 或 五分位计算 ────────────────────────────────────────────
  group_var_name <- bl_cfg$group_var
  predefined     <- !is.null(group_var_name) && nzchar(group_var_name) &&
                    group_var_name %in% names(data)

  data2 <- data

  if (predefined) {
    raw_levels   <- bl_cfg$group_levels %||% sort(unique(as.character(data2[[group_var_name]])))
    data2$Group  <- factor(data2[[group_var_name]], levels = raw_levels)
    data2$Num    <- as.numeric(data2$Group)
    cutoffs      <- setNames(rep("", length(raw_levels)), raw_levels)
    if (identical(phase, "rcs")) {
      cutoffs <- logistic_rcs_prepare_cutoffs(raw_levels, ctx)
    }
    cli::cli_alert_info("logistic_quintile_glm: 使用已有分类列 '{group_var_name}'（{length(raw_levels)} 组），跳过五分位计算")
  } else {
    quintiles    <- quantile(data[[index_var]], probs = c(0.2, 0.4, 0.6, 0.8), na.rm = TRUE)
    data2$Group  <- "Q"
    data2$Group[data2[[index_var]] <  quintiles[1]] <- "Q1"
    data2$Group[data2[[index_var]] >= quintiles[1] & data2[[index_var]] < quintiles[2]] <- "Q2"
    data2$Group[data2[[index_var]] >= quintiles[2] & data2[[index_var]] < quintiles[3]] <- "Q3"
    data2$Group[data2[[index_var]] >= quintiles[3] & data2[[index_var]] < quintiles[4]] <- "Q4"
    data2$Group[data2[[index_var]] >= quintiles[4]] <- "Q5"
    data2$Group  <- factor(data2$Group, levels = c("Q1", "Q2", "Q3", "Q4", "Q5"))
    data2$Num    <- as.numeric(data2$Group)
    raw_levels   <- c("Q1", "Q2", "Q3", "Q4", "Q5")
    cutoffs      <- c(Q1 = paste0("\u2264 ",           round(quintiles[1], 2)),
                      Q2 = paste0(round(quintiles[1], 2), " - ", round(quintiles[2], 2)),
                      Q3 = paste0(round(quintiles[2], 2), " - ", round(quintiles[3], 2)),
                      Q4 = paste0(round(quintiles[3], 2), " - ", round(quintiles[4], 2)),
                      Q5 = paste0("\u2265 ",           round(quintiles[4], 2)))
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)

  # ── 结局 0/1 ────────────────────────────────────────────────────────────────
  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data2[[outcome_col]], cfg))
  } else {
    as.integer(data2[[outcome_col]] == disease_label)
  }

  excl_cols <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_quintile_glm",
    build_table_fn = function(m1, m2) {
      .lqq02_Tb_ModelGroup3_OR(
        outcome_col, index_var, "Group", "Num",
        data2, m1, m2, cutoffs, raw_levels, include_cont
      )
    },
    filter_m1 = function(m1) intersect(as.character(m1), colnames(data2))
  )
  ctx              <- cov$ctx
  Model1Factors    <- cov$M1
  Model2Factors    <- cov$M2
  tb01             <- cov$tb
  sample_factors   <- cov$sample_factors
  search_succeeded <- isTRUE(cov$search_succeeded)
  attempt_count    <- cov$attempt_count %||% 0L

  if (is.null(tb01)) stop("logistic_quintile_glm: 未产生有效结果。")

  block_name <- ctx$current_block %||% "logistic_quintile_glm"
  if (exists("logistic_gate_apply_after_table", mode = "function")) {
    ctx <- logistic_gate_apply_after_table(ctx, bl_cfg, tb01, raw_levels, block_name)
  }

  rt <- if (exists("format_logistic_table2_pvalues", mode = "function")) {
    format_logistic_table2_pvalues(tb01)
  } else {
    data.frame(tb01, stringsAsFactors = FALSE)
  }
  rownames(rt) <- NULL

  h1 <- as.character(rt[1, ]); h2 <- as.character(rt[2, ])
  rt_body <- rt[-c(1L, 2L), , drop = FALSE]
  rownames(rt_body) <- NULL
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))

  is_rcs <- identical(phase, "rcs")
  as_main <- if (exists("logistic_glm_export_as_main", mode = "function")) {
    logistic_glm_export_as_main(ctx, "quintile", is_rcs = is_rcs)
  } else {
    TRUE
  }
  table_kind <- if (isTRUE(as_main)) "main_table" else "supp_table"

  disease_disp <- gsub("_", " ", as.character(cfg$project$disease %||% outcome_col), fixed = TRUE)
  ix_disp <- if (exists("pipeline_index_display_name", mode = "function")) {
    pipeline_index_display_name(cfg, index_var)
  } else {
    gsub("_", " ", as.character(index_var), fixed = TRUE)
  }
  caption <- if (exists("logistic_glm_pub_caption", mode = "function")) {
    logistic_glm_pub_caption(
      ix_disp, disease_disp, scheme = "quintile", is_rcs = is_rcs
    )
  } else if (is_rcs) {
    paste0("Logistic regression of ", ix_disp, " RCS cutoff")
  } else {
    paste0("Logistic regression of ", ix_disp, " quintile")
  }

  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, table_kind, caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, table_kind, caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }

  tryCatch(
    export_sci_table(
      rt_body, filepath, title = title,
      header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE,
      table_footnotes = if (exists("logistic_glm_table_footnotes", mode = "function")) {
        logistic_glm_table_footnotes(Model1Factors, Model2Factors)
      } else {
        NULL
      }
    ),
    error = function(e) cli::cli_alert_warning("logistic_quintile_glm: export_sci_table 失败: {e$message}")
  )

  ctx$results$logistic_table2 <- rt
  if (isTRUE(as_main)) ctx$results$logistic_grouping_scheme <- "quintile"
  ctx$results$logistic_model1_factors  <- Model1Factors
  ctx$results$logistic_model2_factors  <- Model2Factors
  ctx$results$logistic_sample_factors  <- sample_factors

  ctx <- save_result(ctx, "logistic_quintile_glm_Model2Factors", Model2Factors,
                     "Model2Factors_quintile_glm.csv")

  cli::cli_alert_success("logistic_quintile_glm 完成（search_succeeded={search_succeeded}, as_main={as_main}）")
  ctx
}

register_block("logistic_quintile_glm", block_logistic_quintile_glm,
               "五分位 GLM Logistic 回归 Table 2（Q1 参照；闸门末招）")
register_block("logistic_quintile_glm_rcs", block_logistic_quintile_glm,
               "五分位 GLM Logistic（RCS cutoff 分组复跑）")
