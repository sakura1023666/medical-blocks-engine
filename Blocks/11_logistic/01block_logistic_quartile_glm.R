###############################################################################
#  logistic_quartile_glm — 四分位 Q1–Q4 GLM Logistic 回归（Table 2 风格）。
#                          Q1 为参照；Crude / Model1 / Model2 + 双层嵌套随机搜索；
#                          连续暴露 + 四分位分组 + 趋势检验；export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned  # 必须存在且含 outcome/index 列
#  require_ctx_results   = "Model1Factors"  # 优先读取；为 NULL 时 fallback 到 bl_cfg$model1_factors
#  require_ctx_results  += "Model2Factors"  # 随机搜索候选池；为 NULL 时用数据所有协变量列
#
#  logistic_quartile_glm = list(
#    # ── 分组模式 ──────────────────────────────────────────────────────────
#    group_var              = NULL,    # 非 NULL → 数据中已有分类列，直接用；跳过四分位计算
#    group_levels           = NULL,    # 指定 factor 水平顺序（第一个为参照）；NULL 时按字母序
#    include_continuous_row = NULL,    # NULL → 自动（predefined 时 FALSE，否则 TRUE）
#                                      # 显式设为 FALSE 可跳过连续变量 OR 行
#    # ── 协变量 ────────────────────────────────────────────────────────────
#    model1_factors         = NULL,    # 非 NULL 时覆盖 ctx$results$Model1Factors
#    crude_factors          = NULL,    # 非 NULL → Crude 也调整这些列（Pooled 常用 Country）
#    # ── 双层嵌套随机搜索 ──────────────────────────────────────────────────
#    random_search = list(
#      max_outer_attempts    = 100L,   # 外层循环次数（协变量数量递增）
#      max_inner_attempts    = 10L,    # 内层循环次数（同一 k 下反复随机抽）
#      initial_factors_n     = 1L,     # 初始协变量数量，逐轮递增
#      p_threshold           = 0.05,   # 判定阈值
#      seed                  = NULL    # 可选：设种子保证可复现
#    ),
#    pause_enable           = TRUE,    # FALSE = 不触发 pause_point，降级为 warning/stop
#    pause_on_search_fail   = FALSE,   # TRUE → 搜索耗尽后 pause_point；FALSE → warning + 末次结果出表
#    table_filename         = NULL     # NULL → 自动命名
#  ),
#
#  register_block: "logistic_quartile_glm"
#  典型流水线: incidence + imputed；multicollinearity 后；可写 Model1Factors 供下游
#  块内 bl_cfg <- cfg$logistic_quartile_glm；data / project / survival 见主 config
###############################################################################

# ── 私有工具 ─────────────────────────────────────────────────────────────────

.lqg01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqg01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block      = "logistic_quartile_glm",
    reason     = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: logistic_quartile_glm — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.lqg01_assign_quartile_groups <- function(x) {
  xv <- as.numeric(x)
  u <- sort(unique(xv[is.finite(xv)]))
  if (length(u) < 2L) {
    stop("logistic_quartile_glm: 暴露变量唯一值不足 2，无法四分位分组。", call. = FALSE)
  }
  if (length(u) <= 4L) {
    labs <- paste0("Q", seq_along(u))
    grp <- factor(xv, levels = u, labels = labs)
    return(list(
      Group = grp,
      Num = as.numeric(factor(xv, levels = u, labels = seq_along(u))),
      raw_levels = labs,
      cutoffs = setNames(rep("", length(labs)), labs)
    ))
  }
  # 四分位：以 25/50/75% 为内边界，Qk = [Q(k-1), Qk) 左闭右开（Q1 严格 < P25）
  # 与 cut(min..max, include.lowest=TRUE) 不同：边界 ties 归入上一档，避免 Q1 人数偏大
  brks <- unique(as.numeric(stats::quantile(xv, probs = c(0.25, 0.5, 0.75), na.rm = TRUE)))
  if (length(brks) < 3L) {
    labs <- paste0("Q", seq_along(u))
    grp <- factor(xv, levels = u, labels = labs)
    return(list(
      Group = grp,
      Num = as.numeric(factor(xv, levels = u, labels = seq_along(u))),
      raw_levels = labs,
      cutoffs = setNames(rep("", length(labs)), labs)
    ))
  }
  grp_num <- ifelse(
    xv < brks[1L], 1L,
    ifelse(xv < brks[2L], 2L, ifelse(xv < brks[3L], 3L, 4L))
  )
  labs <- c("Q1", "Q2", "Q3", "Q4")
  grp <- factor(grp_num, levels = seq_along(labs), labels = labs)
  cutoffs <- c(
    paste0("< ", fmt_num_cutoff(brks[1L])),
    paste0(fmt_num_cutoff(brks[1L]), " -< ", fmt_num_cutoff(brks[2L])),
    paste0(fmt_num_cutoff(brks[2L]), " -< ", fmt_num_cutoff(brks[3L])),
    paste0("\u2265 ", fmt_num_cutoff(brks[3L]))
  )
  names(cutoffs) <- labs
  list(
    Group = grp,
    Num = as.numeric(grp),
    raw_levels = labs,
    cutoffs = cutoffs
  )
}

# ── 内嵌 Tb_ModelGroup3_OR（GLM 版，参照组 = group_labels[1]）────────────────
#
#  参数：
#    cutoffs         — 命名字符向量（长度 = 组数），每个组的暴露边界描述字符串；
#                      predefined 分组时传入全 "" 的向量
#    group_labels    — 因子水平字符向量（第一个为参照组）
#    include_continuous — 是否包含连续变量 OR 行（Line3 + Line4）
#
#  表行结构（以 4 组 + include_continuous=TRUE 为例，共 10 行）：
#    Line1  — 双行表头第一行
#    Line2  — 列名行
#    Line3  — 暴露名称标题行（include_continuous=FALSE 时省略）
#    Line4  — 连续变量 OR 行（include_continuous=FALSE 时省略）
#    Line5  — 分组标题行
#    Line6  — 参照组 (Ref)
#    Line7… — 其余组的 OR 行（动态，组数 n 则有 n-1 行）
#    最后行 — p for trend（RCS cutoff / is_rcs_group 时不写）
#
#  随机搜索判定：始终取 rt 最后一行（p for trend）和倒数第二行（末组），
#               与 include_continuous 无关。

.lqg01_glm_binomial_safe <- function(formula, data) {
  d <- data
  for (v in all.vars(formula)[-1]) {
    if (v %in% names(d) && is.character(d[[v]])) d[[v]] <- factor(d[[v]])
  }
  fit <- tryCatch(stats::glm(formula, data = d, family = stats::binomial), error = function(e) e)
  if (!inherits(fit, "error")) return(fit)
  msg <- conditionMessage(fit)
  if (!grepl("contrasts can be applied", msg, fixed = TRUE)) stop(msg, call. = FALSE)
  mf <- stats::model.frame(formula, data = d, na.action = stats::na.omit)
  rhs <- setdiff(all.vars(formula), all.vars(formula)[1L])
  drop_vars <- rhs
  if (exists("pipeline_drop_degenerate_covariates", mode = "function")) {
    drop_vars <- setdiff(rhs, pipeline_drop_degenerate_covariates(mf, rhs))
  } else {
    drop_vars <- vapply(rhs, function(v) {
      if (!v %in% names(mf)) return(TRUE)
      x <- mf[[v]]
      (is.factor(x) || is.character(x)) && nlevels(factor(x)) < 2L
    }, logical(1L))
    drop_vars <- rhs[drop_vars]
  }
  keep <- setdiff(rhs, drop_vars)
  if (!length(keep)) stop(msg, call. = FALSE)
  new_fml <- stats::as.formula(
    paste(all.vars(formula)[1L], "~", paste(keep, collapse = " + "))
  )
  stats::glm(new_fml, data = d, family = stats::binomial)
}

.lqg01_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      cutoffs, group_labels,
                                      include_continuous = TRUE,
                                      index_label = ContinuousName,
                                      Model3Factors = NULL,
                                      CrudeFactors = NULL,
                                      include_trend = TRUE) {

  include_m3 <- length(as.character(Model3Factors %||% character(0))) > 0L
  is_rcs_grp <- isTRUE(attr(cutoffs, "is_rcs_group") %||% FALSE)
  CrudeFactors <- intersect(
    setdiff(as.character(CrudeFactors %||% character(0)), c(ResultName, ContinuousName, FactorName, TrendName)),
    names(Data)
  )
  .rhs <- function(main, covs) {
    paste(c(main, covs), collapse = "+")
  }
  fml_f01 <- as.formula(paste0(ResultName, "~", .rhs(FactorName, CrudeFactors)))
  fml_f02 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model1Factors), collapse = "+")))
  fml_f03 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model2Factors), collapse = "+")))

  fml_t01 <- as.formula(paste0(ResultName, "~", .rhs(TrendName, CrudeFactors)))
  fml_t02 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model1Factors), collapse = "+")))
  fml_t03 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model2Factors), collapse = "+")))

  mf  <- .lqg01_glm_binomial_safe(fml_f01, Data)
  mf2 <- .lqg01_glm_binomial_safe(fml_f02, Data)
  mf3 <- .lqg01_glm_binomial_safe(fml_f03, Data)
  mf4 <- if (include_m3) .lqg01_glm_binomial_safe(as.formula(paste0(ResultName, "~", paste(c(FactorName, Model3Factors), collapse = "+"))), Data) else NULL

  mt  <- .lqg01_glm_binomial_safe(fml_t01, Data)
  mt2 <- .lqg01_glm_binomial_safe(fml_t02, Data)
  mt3 <- .lqg01_glm_binomial_safe(fml_t03, Data)
  mt4 <- if (include_m3) .lqg01_glm_binomial_safe(as.formula(paste0(ResultName, "~", paste(c(TrendName, Model3Factors), collapse = "+"))), Data) else NULL

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

  hdr <- pipeline_sci_with_model3_header(
    c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", ""),
    c("Characteristic", "Exposure cutoff", n_hdr,
      "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value"),
    include_m3, "OR"
  )
  Line1 <- hdr$line1; Line2 <- hdr$line2; n_pad <- hdr$n_pad
  Line5 <- c(paste0(index_label, " groups"), rep("", n_pad))

  # 参照组行
  ref_lv   <- group_labels[1]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "",
                pipeline_sci_model3_ref_cells(include_m3))

  .or3 <- function(m, idx) {
    if (is.null(m)) return(character(0))
    c(round(exp(coef(m)[idx]), 3), .ci_str(m, idx),
      logistic_glm_format_p(summary(m)$coefficients[idx, 4], is_rcs_grp))
  }

  # 非参照组行（coef 索引从 2 开始，对应 glm 截距之后的第 1 个 dummy 起）
  non_ref_lvs <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv  <- non_ref_lvs[i]
    idx <- i + 1L  # glm: [1]=intercept, [2]=第1个非参照 dummy ...
    c(lv, cutoffs[lv], .pct(lv), .or3(mf, idx), .or3(mf2, idx), .or3(mf3, idx), if (include_m3) .or3(mf4, idx) else character(0))
  })

  # 规则：RCS cutoff 分组表不放 p for trend（仅组间 OR）；分位主表保留
  drop_trend <- isFALSE(include_trend) ||
    isTRUE(attr(cutoffs, "is_rcs_group") %||% FALSE)
  Line_trend <- if (drop_trend) {
    NULL
  } else {
    c("p for trend", rep("", 4),
      pub_format_p_cell(summary(mt)$coefficients[2, 4]), "", "",
      pub_format_p_cell(summary(mt2)$coefficients[2, 4]), "", "",
      pub_format_p_cell(summary(mt3)$coefficients[2, 4]),
      if (include_m3) c("", "", pub_format_p_cell(summary(mt4)$coefficients[2, 4])) else character(0))
  }

  # 连续变量行（可选）
  if (include_continuous) {
    fml_c01 <- as.formula(paste0(ResultName, "~", .rhs(ContinuousName, CrudeFactors)))
    fml_c02 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model1Factors), collapse = "+")))
    fml_c03 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model2Factors), collapse = "+")))
    mc  <- .lqg01_glm_binomial_safe(fml_c01, Data)
    mc2 <- .lqg01_glm_binomial_safe(fml_c02, Data)
    mc3 <- .lqg01_glm_binomial_safe(fml_c03, Data)
    mc4 <- if (include_m3) .lqg01_glm_binomial_safe(as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model3Factors), collapse = "+"))), Data) else NULL
    .ci_c <- function(m) {
      ci <- logistic_safe_confint(m)
      paste0("(", round(exp(ci[2, 1]), 3), ",", round(exp(ci[2, 2]), 3), ")")
    }
    Line3 <- c(index_label, rep("", n_pad))
    Line4 <- c(paste0(index_label, " continuous"), "", "",
               round(exp(coef(mc)[2]), 3),  .ci_c(mc),  logistic_glm_format_p(summary(mc)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc2)[2]), 3), .ci_c(mc2), logistic_glm_format_p(summary(mc2)$coefficients[2, 4], is_rcs_grp),
               round(exp(coef(mc3)[2]), 3), .ci_c(mc3), logistic_glm_format_p(summary(mc3)$coefficients[2, 4], is_rcs_grp),
               if (include_m3) c(round(exp(coef(mc4)[2]), 3), .ci_c(mc4), logistic_glm_format_p(summary(mc4)$coefficients[2, 4], is_rcs_grp)) else character(0))
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

block_logistic_quartile_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- if (exists("logistic_glm_resolve_bl_cfg", mode = "function")) {
    logistic_glm_resolve_bl_cfg(ctx, "logistic_quartile_glm")
  } else {
    cfg$logistic_quartile_glm %||% list()
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    cli::cli_alert_info("分类暴露：跳过 logistic_quartile_glm，仅回归变量本身")
    return(ctx)
  }
  phase <- as.character(bl_cfg$phase %||% "screen")[1L]

  # ── 数据 ────────────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    .lqg01_pause(ctx, "未找到分析数据（ctx$data$imputed / cleaned 均为空）",
                 "请先运行上游数据准备 block（imputation 或等价步骤）")
  }

  # ── 基本参数 ────────────────────────────────────────────────────────────────
  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  disease_label <- if (exists("pipeline_outcome_case_label", mode = "function")) {
    pipeline_outcome_case_label(cfg)
  } else {
    cfg$project$analysis_group %||% cfg$project$disease %||% outcome_col
  }
  index_var     <- as.character(
    bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var %||%
      (cfg$prediction$index_vars %||% character(0))[1L]
  )[1L]
  ix_label      <- pipeline_index_display_name(cfg, index_var)
  if (is.null(index_var) || !nzchar(index_var)) {
    stop("logistic_quartile_glm: index_var 未设置，请在 config$logistic_quartile_glm$index_var 中指定。")
  }
  if (!index_var %in% names(data)) {
    stop("logistic_quartile_glm: index_var '", index_var, "' 不在数据列中。")
  }
  if (!outcome_col %in% names(data)) {
    stop("logistic_quartile_glm: outcome_col '", outcome_col, "' 不在数据列中。")
  }

  # ── 随机搜索参数 ────────────────────────────────────────────────────────────
  rs_cfg       <- bl_cfg$random_search %||% list()
  bz2          <- as.numeric(rs_cfg$p_threshold %||% 0.05)

  # ── 分组：已有分类列 或 四分位计算 ────────────────────────────────────────────
  group_var_name <- bl_cfg$group_var
  predefined     <- !is.null(group_var_name) && nzchar(group_var_name) &&
                    group_var_name %in% names(data)

  data2 <- data

  if (!isTRUE(predefined) && exists("pipeline_index_as_numeric", mode = "function")) {
    data2[[index_var]] <- pipeline_index_as_numeric(data2[[index_var]])
  }

  if (predefined) {
    raw_levels  <- bl_cfg$group_levels %||% sort(unique(as.character(data2[[group_var_name]])))
    raw_levels  <- as.character(raw_levels)
    raw_levels  <- raw_levels[nzchar(raw_levels)]
    # 丢掉数据中人数为 0 的预设水平（RCS 空档组会导致 glm 失败）
    present <- as.character(stats::na.omit(unique(as.character(data2[[group_var_name]]))))
    raw_levels <- raw_levels[raw_levels %in% present]
    if (!length(raw_levels)) {
      raw_levels <- sort(present)
    }
    data2$Group <- factor(as.character(data2[[group_var_name]]), levels = raw_levels)
    data2$Num   <- as.numeric(data2$Group)
    cutoffs     <- setNames(rep("", length(raw_levels)), raw_levels)
    if (identical(phase, "rcs")) {
      cutoffs <- logistic_rcs_prepare_cutoffs(raw_levels, ctx)
    }
    cli::cli_alert_info("logistic_quartile_glm: 使用已有分类列 '{group_var_name}'（{length(raw_levels)} 组），跳过四分位计算")
  } else {
    qg <- .lqg01_assign_quartile_groups(data2[[index_var]])
    data2$Group <- qg$Group
    data2$Num   <- qg$Num
    raw_levels  <- qg$raw_levels
    cutoffs     <- qg$cutoffs
    cli::cli_alert_info(
      "logistic_quartile_glm: 四分位分组 {paste(names(table(data2$Group, useNA='no')), table(data2$Group, useNA='no'), sep='=', collapse=', ')}"
    )
  }

  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% !predefined)
  CrudeFactors <- intersect(
    as.character(bl_cfg$crude_factors %||% cfg$logistic_covariates$crude_factors %||% character(0)),
    names(data2)
  )
  if (length(CrudeFactors)) {
    cli::cli_alert_info("logistic_quartile_glm Crude(+): {paste(CrudeFactors, collapse = ', ')}")
  }

  # ── 结局 0/1 ────────────────────────────────────────────────────────────────
  data2[[outcome_col]] <- as.character(data2[[outcome_col]])
  data2[[outcome_col]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    as.integer(pipeline_outcome_as_01(data2[[outcome_col]], cfg))
  } else {
    as.integer(data2[[outcome_col]] == disease_label)
  }

  excl_cols <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
  cov <- logistic_prepare_covariates(
    ctx, cfg, bl_cfg, data2, index_var, excl_cols, "logistic_quartile_glm",
    build_table_fn = function(m1, m2) {
      .lqg01_Tb_ModelGroup3_OR(
        outcome_col, index_var, "Group", "Num",
        data2, m1, m2, cutoffs, raw_levels, include_cont,
        index_label = ix_label, CrudeFactors = CrudeFactors
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
  if (exists("pipeline_apply_model3_after_m2", mode = "function")) {
    sig_fn <- NULL
    if (exists("pipeline_model3_sig_from_table", mode = "function") &&
        exists(".lqg01_Tb_ModelGroup3_OR", mode = "function")) {
      sig_fn <- function(covs) {
        tb_try <- tryCatch(
          .lqg01_Tb_ModelGroup3_OR(
            outcome_col, index_var, "Group", "Num",
            data2, Model1Factors, Model2Factors, cutoffs, raw_levels, include_cont,
            index_label = ix_label, Model3Factors = covs, CrudeFactors = CrudeFactors
          ),
          error = function(e) NULL
        )
        isTRUE(pipeline_model3_sig_from_table(tb_try, raw_levels))
      }
    }
    m3a <- pipeline_apply_model3_after_m2(
      ctx, cfg, Model2Factors, names(data2), index_var,
      sig_fn = sig_fn, M1 = Model1Factors
    )
    ctx <- m3a$ctx
    if (length(as.character(m3a$M2 %||% character(0)))) {
      Model2Factors <- unique(as.character(m3a$M2))
      ctx$results$Model2Factors <- Model2Factors
    }
    if (isTRUE(m3a$include_m3)) {
      tb_m3 <- tryCatch(
        .lqg01_Tb_ModelGroup3_OR(
          outcome_col, index_var, "Group", "Num",
          data2, Model1Factors, Model2Factors, cutoffs, raw_levels, include_cont,
          index_label = ix_label, Model3Factors = m3a$M3, CrudeFactors = CrudeFactors
        ),
        error = function(e) NULL
      )
      if (!is.null(tb_m3)) {
        tb01 <- tb_m3
        m3_sig <- isTRUE(m3a$m3_sig)
        if (!m3_sig) {
          m3_sig <- pipeline_model3_sig_from_table(tb01, raw_levels)
        }
        Model3Factors <- m3a$M3
        final <- pipeline_finalize_adjusted_factors(Model2Factors, Model3Factors, m3_sig)
        ctx <- pipeline_store_model3(ctx, Model3Factors, m3_sig, final)
      }
    }
  }

  if (identical(phase, "rcs") && exists("logistic_gate_apply_after_table", mode = "function")) {
    gv <- bl_cfg$group_var
    if (is.null(gv) || !nzchar(gv) || !gv %in% names(data2)) {
      stop(
        "logistic_quartile_glm (rcs): 未找到 RCS 分组列 '",
        gv %||% "", "'；请先运行 rcs_incidence。",
        call. = FALSE
      )
    }
  }

  block_name <- ctx$current_block %||% "logistic_quartile_glm"
  if (exists("logistic_gate_apply_after_table", mode = "function")) {
    ctx <- logistic_gate_apply_after_table(ctx, bl_cfg, tb01, raw_levels, block_name)
  }

  # ── P 值格式化 ───────────────────────────────────────────────────────────────
  is_rcs <- identical(phase, "rcs")
  rt <- data.frame(tb01, stringsAsFactors = FALSE)
  if (!isTRUE(is_rcs)) {
    for (cc in c(6, 9, 12)) {
      if (cc <= ncol(rt)) {
        hit <- which(as.character(rt[[cc]]) == "0")
        if (length(hit)) rt[[cc]][hit] <- "P < 0.001"
      }
    }
  }
  rownames(rt) <- NULL

  # ── export_sci_table ──────────────────────────────────────────────────────────
  h1      <- as.character(rt[1, ])
  h2      <- as.character(rt[2, ])
  rt_body <- rt[-c(1L, 2L), , drop = FALSE]
  rownames(rt_body) <- NULL
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))

  as_main <- if (exists("logistic_glm_export_as_main", mode = "function")) {
    logistic_glm_export_as_main(ctx, "quartile", is_rcs = is_rcs)
  } else {
    TRUE
  }
  # ML assoc force_export：三套分位均导出为主文表族（多 Table 2.x），非 RCS 主筛选
  if (isTRUE(bl_cfg$force_export %||% FALSE) && !isTRUE(is_rcs)) as_main <- TRUE
  table_kind <- if (isTRUE(as_main)) "main_table" else "supp_table"

  # 双库敏感性：NHANES 已有加权 Table2 时，未加权同档 GLM 必须导出为附表
  has_weighted_main <- !is.null(ctx$results$logistic_table2_weighted) ||
    !is.null(ctx$results$nhanes_logistic_table2)
  disease_disp <- gsub("_", " ", as.character(cfg$project$disease %||% disease_label), fixed = TRUE)
  caption <- if (exists("logistic_glm_pub_caption", mode = "function")) {
    logistic_glm_pub_caption(
      ix_label, disease_disp, scheme = "quartile",
      is_rcs = is_rcs, unweighted = isTRUE(has_weighted_main)
    )
  } else if (is_rcs) {
    paste0("Logistic regression of ", ix_label, " RCS cutoff")
  } else if (isTRUE(has_weighted_main)) {
    paste0("Logistic regression of ", ix_label, " quartile unweighted")
  } else {
    paste0("Logistic regression of ", ix_label, " quartile")
  }
  do_export <- if (exists("logistic_glm_should_export", mode = "function")) {
    logistic_glm_should_export(ctx, "quartile", is_rcs = is_rcs, bl_cfg = bl_cfg)
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
    tryCatch(
      export_sci_table(rt_body, filepath, title = title,
                       header_row1 = h1, header_row2 = h2,
                       latex_include_colnames = FALSE,
                       table_footnotes = logistic_glm_table_footnotes(
                         Model1Factors, Model2Factors, Model3Factors, m3_sig,
                         Crude = CrudeFactors
                       )),
      error = function(e) cli::cli_alert_warning("logistic_quartile_glm: export_sci_table 失败: {e$message}")
    )
  }

  # ── ctx$results ───────────────────────────────────────────────────────────────
  ctx$results$logistic_table2 <- rt
  if (isTRUE(as_main)) {
    ctx$results$logistic_grouping_scheme <- "quartile"
  }
  ctx$results$logistic_model1_factors  <- Model1Factors
  ctx$results$logistic_model2_factors  <- Model2Factors
  ctx$results$logistic_sample_factors  <- sample_factors

  ctx <- save_result(ctx, "logistic_quartile_glm_Model2Factors", Model2Factors,
                     "Model2Factors_quartile_glm.csv")

  cli::cli_alert_success("logistic_quartile_glm 完成（search_succeeded={search_succeeded}）")
  ctx
}

register_block("logistic_quartile_glm", block_logistic_quartile_glm,
               "四分位 GLM Logistic 回归 Table 2（Q1 参照，支持已有分类列）")
register_block("logistic_quartile_glm_rcs", block_logistic_quartile_glm,
               "四分位 GLM Logistic（RCS cutoff 分组复跑）")
