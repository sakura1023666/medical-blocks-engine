###############################################################################
#  cox_binary — 预后二分类 Cox HR（low/high，Q1 参照），Crude / Model1 / Model2。
#
#  register_block: "cox_binary"
#  典型流水线: multicollinearity 后；study_type=prognosis；可选协变量组合搜索
#
#  # ── 配置 config$cox_binary ───────────────────────────────────────────────
#  cox_binary = list(
#    covariate_search = list(
#      enable = TRUE, max_model1_attempts = 1000L, max_model2_attempts = 1000L,
#      on_search_fail = "stop"
#    ),
#    index_var         = NULL,   # 连续暴露；NULL → survival$index_var
#    group_var         = NULL,   # 已有二分类列则跳过 cutoff 计算
#    group_levels      = c("low", "high"),
#    cutoff            = NULL,   # 分组截断；NULL → 中位数或上游 cutoff 块结果
#    model1_factors    = NULL,   # 覆盖 ctx$Model1Factors
#    model2_factors    = NULL,
#    table_filename    = NULL,   # NULL → 自动 Table 2 Cox binary 命名
#    pause_enable      = TRUE,
#    pause_on_fit_fail = TRUE
#  ),
#  可 fallback config$cox$model1_covariates / model2_covariates
#  写: Tables Cox HR；export_sci_table
###############################################################################

.cb01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.cb01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "cox_binary",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: cox_binary — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.cb01_format_p_cells <- function(rt) {
  if (is.null(rt) || !is.matrix(rt) && !is.data.frame(rt)) return(rt)
  if (exists("pub_fix_p_cells", mode = "function")) {
    return(pub_fix_p_cells(as.data.frame(rt, stringsAsFactors = FALSE), c(5L, 8L, 11L)))
  }
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  p_cols <- c(5L, 8L, 11L)
  for (j in p_cols) {
    if (ncol(rt) < j) next
    x <- rt[[j]]
    if (!is.character(x)) x <- as.character(x)
    sci <- grepl("[0-9]+\\.?[0-9]*[eE][+-][0-9]+", x)
    zero <- grepl("^0$", x)
    x[sci | zero] <- "<0.001"
    rt[[j]] <- x
  }
  rt
}

.cb01_Tb_ModelGroup2_HR <- function(time_var, event_var, ContinuousName, FactorName, Data,
                                     Model1Factors, Model2Factors, DeathCause, Factors,
                                     ref_level, high_level) {
  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  rhs_c <- function(vars) paste(c(vars), collapse = " + ")

  fml_Continuous_c01 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(ContinuousName)))
  fml_Continuous_c02 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model1Factors))))
  fml_Continuous_c03 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model2Factors))))

  fml_Factors_f01 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(FactorName)))
  fml_Factors_f02 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model1Factors))))
  fml_Factors_f03 <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model2Factors))))

  model_Continuous_c01 <- coxph(fml_Continuous_c01, data = Data)
  model_Continuous_c02 <- coxph(fml_Continuous_c02, data = Data)
  model_Continuous_c03 <- coxph(fml_Continuous_c03, data = Data)

  model_Factors_c01 <- coxph(fml_Factors_f01, data = Data)
  model_Factors_c02 <- coxph(fml_Factors_f02, data = Data)
  model_Factors_c03 <- coxph(fml_Factors_f03, data = Data)

  .hr_ci_p <- function(m, row = 1L) {
    if (exists("pub_hr_ci_p", mode = "function")) return(pub_hr_ci_p(m, row))
    sm <- summary(m)
    hr <- round(exp(coef(m))[row], 3)
    ci <- suppressMessages(confint(m))
    ci_str <- paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")")
    p <- round(sm$coefficients[row, "Pr(>|z|)"], 4)
    list(hr = hr, ci = ci_str, p = p)
  }

  c1 <- .hr_ci_p(model_Continuous_c01)
  c2 <- .hr_ci_p(model_Continuous_c02)
  c3 <- .hr_ci_p(model_Continuous_c03)

  Line1 <- c("", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "N (%)", "HR", "95%CI", "P-value",
             "HR", "95%CI", "P-value", "HR", "95%CI", "P-value")
  Line3 <- c(DeathCause, rep("", 10L))
  Line4 <- c(
    paste0(Factors, " continuous"), "",
    c1$hr, c1$ci, c1$p, c2$hr, c2$ci, c2$p, c3$hr, c3$ci, c3$p
  )
  Line5 <- c(paste0(Factors, " category"), rep("", 10L))

  cnt <- table(Data[[FactorName]])
  pct_ref <- round(100 * as.numeric(cnt[ref_level]) / nrow(Data), 2)
  Line6 <- c(paste0("Lower ", Factors), pct_ref, rep(c("Ref", "", ""), 3L))

  f1 <- .hr_ci_p(model_Factors_c01)
  f2 <- .hr_ci_p(model_Factors_c02)
  f3 <- .hr_ci_p(model_Factors_c03)
  pct_hi <- round(100 * as.numeric(cnt[high_level]) / nrow(Data), 2)
  Line7 <- c(
    paste0("Higher ", Factors), pct_hi,
    f1$hr, f1$ci, f1$p, f2$hr, f2$ci, f2$p, f3$hr, f3$ci, f3$p
  )

  rt <- rbind(Line1, Line2, Line3, Line4, Line5, Line6, Line7)
  rownames(rt) <- NULL
  list(
    table = rt,
    fits = list(
      continuous = list(crude = model_Continuous_c01, model1 = model_Continuous_c02, model2 = model_Continuous_c03),
      grouped = list(crude = model_Factors_c01, model1 = model_Factors_c02, model2 = model_Factors_c03)
    )
  )
}

block_cox_binary <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  if (exists("dual_db_apply_cox_unified_from_cache", mode = "function")) {
    ctx <- dual_db_apply_cox_unified_from_cache(ctx)
  }
  if (exists("cox_gate_block_is_redundant", mode = "function") &&
      cox_gate_block_is_redundant("cox_binary", ctx)) {
    br <- ctx$results$cox_branch %||% "extend"
    cli::cli_alert_info(
      "cox_binary: 已走扩展分支（{br}），跳过二分类 Cox"
    )
    return(ctx)
  }

  cfg <- ctx$config
  cox_legacy <- cfg$cox %||% list()
  bl_cfg <- cfg$cox_binary %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    .cb01_pause(ctx, "未找到分析数据", "请先运行 data_clean / imputation")
  }
  # 若 index_var 是 Subphenotype，优先用 lca 产出的 df_final（含亚型列）
  df_lca <- ctx$results$df_final
  if (!is.null(df_lca) && is.data.frame(df_lca) && "Subphenotype" %in% names(df_lca)) {
    shared <- intersect(names(data), names(df_lca))
    extra  <- setdiff(names(df_lca), names(data))
    if (length(extra) > 0L) {
      rn_data <- rownames(data)
      rn_lca  <- rownames(df_lca)
      if (!is.null(rn_data) && !is.null(rn_lca) && length(intersect(rn_data, rn_lca)) > 0L) {
        data <- merge(data, df_lca[, extra, drop = FALSE],
                      by = "row.names", all.x = TRUE)
        rownames(data) <- data$Row.names
        data$Row.names <- NULL
      } else if (nrow(df_lca) == nrow(data)) {
        data <- cbind(data, df_lca[, extra, drop = FALSE])
      }
    }
  }

  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  index_var <- bl_cfg$index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) {
    stop("cox_binary: index_var 未设置（config$survival$index_var 或 cox_binary$index_var）。")
  }

  for (v in c(time_var, event_var, index_var)) {
    if (!v %in% names(data)) stop("cox_binary: 变量 '", v, "' 不在数据中。")
  }

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  data2 <- data
  if (is.character(data2[[event_var]]) || is.factor(data2[[event_var]])) {
    if (is.null(disease_label) || !nzchar(disease_label)) {
      stop("cox_binary: 事件列为字符/因子时需 config$project$analysis_group。")
    }
    data2[[event_var]] <- ifelse(data2[[event_var]] == disease_label, 1, 0)
  }
  data2[[event_var]] <- as.numeric(data2[[event_var]])

  group_var_name <- bl_cfg$group_var
  predefined <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data2)

  if (predefined) {
    raw <- data2[[group_var_name]]
    levels_use <- if (!is.null(bl_cfg$group_levels) && length(bl_cfg$group_levels) > 0L) {
      as.character(bl_cfg$group_levels)
    } else {
      sort(unique(as.character(raw[!is.na(raw)])))
    }
    data2$Group <- factor(as.character(raw), levels = levels_use)
    if (any(is.na(data2$Group))) stop("cox_binary: group_var 水平与 group_levels 不一致。")
    cli::cli_alert_info("cox_binary: 使用已有分组列 '{group_var_name}'")
  } else {
    levels_use <- as.character(bl_cfg$group_levels %||% c("low", "high"))
    cutoff <- bl_cfg$cutoff %||% ctx$results$cutoff_value
    if (is.null(cutoff) && !is.null(ctx$results$plot_cutoff$cutoff)) {
      cutoff <- ctx$results$plot_cutoff$cutoff
    }
    if (!is.null(cutoff) && is.finite(as.numeric(cutoff))) {
      cutoff <- as.numeric(cutoff)
      data2$Group <- ifelse(data2[[index_var]] < cutoff, levels_use[1], levels_use[2])
      cli::cli_alert_info("cox_binary: 固定 cutoff={cutoff}")
    } else {
      q_med <- as.numeric(stats::quantile(data2[[index_var]], probs = 0.5, na.rm = TRUE))
      data2$Group <- ifelse(data2[[index_var]] < q_med, levels_use[1], levels_use[2])
      cli::cli_alert_info("cox_binary: 中位数二分")
    }
    data2$Group <- factor(data2$Group, levels = levels_use)
  }

  data2$Num <- as.numeric(data2[[index_var]])

  cfg_m1 <- as.character(cox_legacy$model1_covariates %||% character(0))
  cfg_m2 <- as.character(cox_legacy$model2_covariates %||% character(0))
  Model1Factors <- as.character(
    bl_cfg$model1_factors %||%
      ctx$results$assoc_model1_factors %||%
      ctx$results$Model1Factors %||% cfg_m1
  )
  m2_raw <- as.character(
    bl_cfg$model2_factors %||%
      ctx$results$assoc_model2_factors %||%
      ctx$results$Model2Factors %||% cfg_m2
  )
  if (length(Model1Factors) == 0L && length(m2_raw) > 0L) {
    # VIF screen 可能只写出 Model2；敏感性分析用 Model2 顶层人口学作 Model1
    demo_guess <- c("Age", "Gender", "Sex", "Race", "BMI", "SOFA", "GCS")
    Model1Factors <- intersect(demo_guess, m2_raw)
    if (!length(Model1Factors)) {
      Model1Factors <- utils::head(m2_raw, 3L)
    }
    cli::cli_alert_warning(
      "cox_binary: Model1Factors 为空，已从 Model2 回退 {length(Model1Factors)} 个: {paste(Model1Factors, collapse = ', ')}"
    )
  }
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    merged <- pipeline_merge_force_covariates(
      Model1Factors, m2_raw, names(data2), cfg
    )
    Model1Factors <- merged$M1
    m2_raw <- merged$M2
  }
  if (length(Model1Factors) == 0L) {
    .cb01_pause(ctx, "Model1Factors 为空", "请先运行 multicollinearity / univariate，或指定 model1_factors")
  }
  if ("Glucose" %in% Model1Factors && "A1c" %in% Model1Factors) {
    Model1Factors <- Model1Factors[Model1Factors != "A1c"]
  }
  Model1Factors <- intersect(Model1Factors, names(data2))
  m2_pool_extra <- setdiff(intersect(m2_raw, names(data2)), Model1Factors)
  all_cov <- unique(c(Model1Factors, m2_pool_extra))

  keep_cols <- unique(c(time_var, event_var, index_var, "Group", "Num", all_cov))
  dt <- stats::na.omit(data2[, keep_cols, drop = FALSE])
  if (nrow(dt) < 10L) {
    .cb01_pause(ctx, "完整病例数过少", "检查生存时间与协变量缺失", utils::head(dt, 5L))
  }
  n_levels <- length(levels(droplevels(dt$Group)))
  if (n_levels < 2L) stop("cox_binary: 分组不足 2 水平。")

  is_subphenotype <- !is.null(index_var) && index_var == "Subphenotype"
  if (n_levels > 2L || is_subphenotype) {
    Model2Factors <- if (length(m2_raw) == 0L) Model1Factors else unique(c(Model1Factors, m2_pool_extra))
    cli::cli_alert_info("cox_binary: 检测到 {n_levels} 个亚型，输出多水平 Cox 汇总表（非二分 HR）。")
    surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
    fml_crude <- as.formula(paste0(surv_lhs, " ~ Group"))
    fml_m2    <- as.formula(paste0(surv_lhs, " ~ Group + ", paste(Model2Factors, collapse = " + ")))
    m_crude <- tryCatch(survival::coxph(fml_crude, data = dt), error = function(e) NULL)
    m_adj   <- tryCatch(survival::coxph(fml_m2,    data = dt), error = function(e) NULL)
    get_hr <- function(m) if (is.null(m)) NULL else {
      sm <- summary(m)$coefficients
      sm <- sm[grepl("^Group", rownames(sm)), , drop = FALSE]
      data.frame(Term = rownames(sm),
                 HR = round(exp(sm[,"coef"]),3),
                 CI_lower = round(exp(sm[,"coef"] - 1.96*sm[,"se(coef)"]),3),
                 CI_upper = round(exp(sm[,"coef"] + 1.96*sm[,"se(coef)"]),3),
                 P = round(sm[,"Pr(>|z|)"],4), stringsAsFactors = FALSE)
    }
    rt_crude <- get_hr(m_crude); rt_adj <- get_hr(m_adj)
    rt_out   <- if (!is.null(rt_crude) && !is.null(rt_adj)) {
      cbind(rt_crude, Adj_HR = rt_adj$HR, Adj_CI_lower = rt_adj$CI_lower,
            Adj_CI_upper = rt_adj$CI_upper, Adj_P = rt_adj$P)
    } else rt_crude %||% data.frame(note="Cox fit failed")
    ctx <- save_result(ctx, "cox_subtype_table", rt_out, "Table_Cox_Subphenotype.csv")
    if (!is.null(rt_out) && is.data.frame(rt_out)) {
      tryCatch(export_sci_table(rt_out,
        file.path(ctx$output_dir_tables %||% ctx$output_dir,
                  paste0("Table_Cox_Subphenotype_k", n_levels, ".xlsx")),
        title = paste0("Cox regression: Subphenotype association with ", time_var)),
        error = function(e) cli::cli_alert_warning("cox table export failed: {e$message}"))
    }
    cli::cli_alert_success("cox_binary (multi-level) 完成。")
    return(ctx)
  }

  use_search <- exists("cox_covariate_search_enabled", mode = "function") &&
    cox_covariate_search_enabled(bl_cfg)
  if (use_search) {
    sc <- bl_cfg$covariate_search %||% list()
    pools <- if (exists("cox_resolve_covariate_search_pools", mode = "function")) {
      cox_resolve_covariate_search_pools(ctx, Model1Factors, m2_pool_extra)
    } else {
      list(m1 = Model1Factors, m2 = m2_pool_extra, lab_only_tier = FALSE)
    }
    if (isTRUE(pools$lab_only_tier)) {
      cli::cli_alert_info("cox_binary: 三级回退 tier — 搜索 M1 非实验室池 + M2 实验室池")
    }
    if (isTRUE(ctx$results$dual_db_covariate_harmonized)) {
      cli::cli_alert_info(
        "cox_binary: 搜索在 Gate B 统一池内（之后会再对齐两库交集）"
      )
    }
    cli::cli_alert_info(
      "cox_binary: 协变量组合搜索（Model1≤{sc$max_model1_attempts %||% 1000L}，Model2≤{sc$max_model2_attempts %||% 1000L} 次）"
    )
    search_res <- cox_fit_searched_covariates(dt, time_var, event_var, pools$m1, pools$m2, bl_cfg)
    if (!identical(search_res$status, "ok")) {
      cox_handle_search_fail(ctx, bl_cfg, "cox_binary", search_res)
    }
    Model1Factors <- search_res$final_m1
    Model2Factors <- search_res$final_m2_all
    enforced <- if (exists("cox_enforce_model2_gt_m1", mode = "function")) {
      cox_enforce_model2_gt_m1(
        Model1Factors, Model2Factors, m2_pool_extra, ctx,
        dat = dt, time_var = time_var, event_var = event_var, bl_cfg = bl_cfg
      )
    } else {
      list(M1 = Model1Factors, M2 = Model2Factors)
    }
    Model1Factors <- enforced$M1
    Model2Factors <- enforced$M2
    ctx$results$cox_model1_covariates_searched <- Model1Factors
    ctx$results$cox_model2_covariates_searched <- setdiff(Model2Factors, Model1Factors)
    cli::cli_alert_success(
      "cox_binary: 搜索命中（M1 {search_res$m1_attempts} 次，M2 {search_res$m2_attempts} 次）"
    )
  } else {
    Model2Factors <- if (length(m2_raw) == 0L) Model1Factors else unique(c(Model1Factors, m2_pool_extra))
    enforced <- if (exists("cox_enforce_model2_gt_m1", mode = "function")) {
      cox_enforce_model2_gt_m1(
        Model1Factors, Model2Factors, m2_pool_extra, ctx,
        dat = dt, time_var = time_var, event_var = event_var, bl_cfg = bl_cfg
      )
    } else {
      list(M1 = Model1Factors, M2 = Model2Factors)
    }
    Model1Factors <- enforced$M1
    Model2Factors <- enforced$M2
  }

  if (exists("pipeline_apply_model3_after_m2", mode = "function") &&
      exists("pipeline_cox_grouped_significant", mode = "function")) {
    if (exists("pipeline_resolve_model3_factors", mode = "function")) {
      m3_probe <- tryCatch(
        pipeline_resolve_model3_factors(Model2Factors, cfg, names(data2), index_var),
        error = function(e) character(0)
      )
      extra0 <- setdiff(m3_probe, names(dt))
      if (length(extra0)) {
        dt <- stats::na.omit(data2[, unique(c(names(dt), extra0)), drop = FALSE])
      }
    }
    sig_fn <- function(covs) {
      pipeline_cox_grouped_significant(dt, time_var, event_var, "Group", "Num", covs)
    }
    m3a <- pipeline_apply_model3_after_m2(
      ctx, cfg, Model2Factors, names(data2), index_var,
      sig_fn = sig_fn, M1 = Model1Factors
    )
    ctx <- m3a$ctx
    if (length(as.character(m3a$M2 %||% character(0)))) {
      Model2Factors <- unique(as.character(m3a$M2))
      ctx$results$Model2Factors <- Model2Factors
      ctx$results$cox_model2_covariates <- setdiff(Model2Factors, Model1Factors)
    }
    if (isTRUE(m3a$include_m3)) {
      extra <- setdiff(m3a$M3, names(dt))
      if (length(extra)) {
        dt <- stats::na.omit(data2[, unique(c(names(dt), extra)), drop = FALSE])
      }
      m3_sig <- isTRUE(m3a$m3_sig)
      if (!m3_sig) {
        m3_sig <- pipeline_cox_grouped_significant(
          dt, time_var, event_var, "Group", "Num", m3a$M3
        )
      }
      final <- pipeline_finalize_adjusted_factors(Model2Factors, m3a$M3, m3_sig)
      ctx <- pipeline_store_model3(ctx, m3a$M3, m3_sig, final)
    }
  }

  res <- tryCatch(
    .cb01_Tb_ModelGroup2_HR(
      time_var = time_var, event_var = event_var,
      ContinuousName = "Num", FactorName = "Group", Data = dt,
      Model1Factors = Model1Factors, Model2Factors = Model2Factors,
      DeathCause = index_var, Factors = index_var,
      ref_level = levels_use[1], high_level = levels_use[2]
    ),
    error = function(e) {
      if (.cb01_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
        .cb01_pause(ctx, paste0("Cox 拟合失败: ", conditionMessage(e)), "检查协变量共线或样本量")
      }
      stop("cox_binary: ", conditionMessage(e), call. = FALSE)
    }
  )

  if (exists("cox_require_both_models_sig", mode = "function")) {
    ctx <- cox_require_both_models_sig(ctx, bl_cfg, "cox_binary", res$fits$grouped, levels(dt$Group))
  }

  rt_df <- data.frame(.cb01_format_p_cells(res$table), stringsAsFactors = FALSE)
  rownames(rt_df) <- NULL
  h1 <- as.character(rt_df[1, ]); h2 <- as.character(rt_df[2, ])
  rt_body <- rt_df[-c(1L, 2L), , drop = FALSE]
  rownames(rt_body) <- NULL
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))

  disease_name <- cfg$project$disease %||% "Outcome"
  caption <- as.character(
    bl_cfg$table_caption %||%
      paste0(
        "Sensitivity analysis: Multivariable Cox for ",
        index_var, " and ", disease_name
      )
  )[1L]
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, "main_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  footnotes <- c(
    "Crude Model was non-adjusted;",
    paste0("Model 1 was adjusted by: ", if (length(Model1Factors)) paste(Model1Factors, collapse = ", ") else "None"),
    paste0("Model 2 was adjusted by: ", if (length(Model2Factors)) paste(Model2Factors, collapse = ", ") else "None")
  )
  tryCatch(
    export_sci_table(rt_body, filepath, title = title, header_row1 = h1, header_row2 = h2,
                     latex_include_colnames = FALSE, table_footnotes = footnotes),
    error = function(e) cli::cli_alert_warning("cox_binary: export 失败: {e$message}")
  )

  glv_cb <- levels(dt$Group)
  top_cb <- glv_cb[length(glv_cb)]
  hr_top_cb <- NA_real_
  mf3_cb <- tryCatch(res$fits$grouped$model2, error = function(e) NULL)
  if (!is.null(mf3_cb)) {
    cf_cb <- tryCatch(stats::coef(mf3_cb), error = function(e) NULL)
    if (!is.null(cf_cb) && length(cf_cb) >= 1L) {
      hr_top_cb <- round(exp(as.numeric(cf_cb[length(cf_cb)])), 4)
    }
  }
  ctx$results$cox_highest_group_model2_hr <- hr_top_cb
  ctx$results$cox_highest_group_level <- top_cb

  ctx$results$cox_hr <- rt_df
  ctx$results$cox_models <- res$fits$grouped
  ctx$results$cox_model1_covariates <- Model1Factors
  ctx$results$cox_model2_covariates <- setdiff(Model2Factors, Model1Factors)
  ctx$results$cox_grouping <- list(method = "binary", n_groups = 2L, group_levels = levels(dt$Group))
  if (exists("cox_gate_apply_after_grouped", mode = "function") &&
      isTRUE(bl_cfg$gate_enable %||% FALSE)) {
    ctx <- cox_gate_apply_after_grouped(ctx, bl_cfg, res$fits$grouped, levels(dt$Group))
  }
  if (exists("cox_ph_export_supp_table", mode = "function")) {
    ctx <- cox_ph_export_supp_table(ctx, res$fits$grouped, index_var, bl_cfg)
  }
  cli::cli_alert_success("cox_binary 完成: {.file {basename(filepath)}}")
  ctx
}

register_block("cox_binary", block_cox_binary,
               "二分类 Cox HR 表（可选协变量搜索 + Tb_ModelGroup2_HR）")
