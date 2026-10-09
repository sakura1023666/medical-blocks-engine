###############################################################################
#  cox_tertile — 预后三分位 Cox HR（T1 参照 + p for trend），Crude / Model1 / Model2。
#
#  register_block: "cox_tertile"
#  前置: imputed；Model1Factors / Model2Factors；可选协变量组合搜索
#
#  cox_tertile = list(
#    covariate_search = list(enable = TRUE, max_model1_attempts = 1000L,
#                            max_model2_attempts = 1000L, on_search_fail = "degrade"),
#    degrade_branch = "degrade_binary", ...
#  ),
#  group_var 非 NULL 时直接用已有三分类列；否则按暴露三分位切分
###############################################################################

.ct02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.ct02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "cox_tertile", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: cox_tertile — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.ct02_format_p_cells <- function(rt) {
  if (exists("pub_fix_p_cells", mode = "function")) {
    return(pub_fix_p_cells(rt, c(6L, 9L, 12L)))
  }
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  for (j in c(6L, 9L, 12L)) {
    if (ncol(rt) < j) next
    x <- as.character(rt[[j]])
    x[grepl("[0-9]+\\.?[0-9]*[eE][+-][0-9]+", x) | grepl("^0$", x)] <- "<0.001"
    rt[[j]] <- x
  }
  rt
}

.ct02_Tb_ModelGroupNg_HR <- function(time_var, event_var, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors, group_labels, cutoffs) {
  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  rhs_c <- function(vars) paste(c(vars), collapse = " + ")
  mc1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(ContinuousName))), data = Data)
  mc2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model1Factors)))), data = Data)
  mc3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model2Factors)))), data = Data)
  mf1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(FactorName))), data = Data)
  mf2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model1Factors)))), data = Data)
  mf3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model2Factors)))), data = Data)
  mt1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(TrendName))), data = Data)
  mt2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model1Factors)))), data = Data)
  mt3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model2Factors)))), data = Data)
  .hr_ci_p <- function(m, row) {
    sm <- summary(m); ci <- suppressMessages(confint(m))
    list(hr = round(exp(coef(m))[row], 3),
         ci = paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")"),
         p = pub_format_p_cell(sm$coefficients[row, "Pr(>|z|)"]))
  }
  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .pct <- function(lv) paste0(as.numeric(cnt[lv]), "(", round(as.numeric(cnt[lv]) / n_total * 100, 2), "%)")
  c1 <- .hr_ci_p(mc1, 1L); c2 <- .hr_ci_p(mc2, 1L); c3 <- .hr_ci_p(mc3, 1L)
  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)", "HR", "95%CI", "P-value",
             "HR", "95%CI", "P-value", "HR", "95%CI", "P-value")
  Line3 <- c(ContinuousName, rep("", 11L))
  Line4 <- c(paste0(ContinuousName, " continuous"), "", "", c1$hr, c1$ci, c1$p, c2$hr, c2$ci, c2$p, c3$hr, c3$ci, c3$p)
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11L))
  ref_lv <- group_labels[1L]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")
  non_ref <- group_labels[-1L]
  lines_nonref <- lapply(seq_along(non_ref), function(i) {
    lv <- non_ref[i]; r <- .hr_ci_p(mf1, i); r2 <- .hr_ci_p(mf2, i); r3 <- .hr_ci_p(mf3, i)
    c(lv, cutoffs[lv], .pct(lv), r$hr, r$ci, r$p, r2$hr, r2$ci, r2$p, r3$hr, r3$ci, r3$p)
  })
  Line_trend <- c("p for trend", rep("", 4L),
                  pub_format_p_cell(summary(mt1)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[1, "Pr(>|z|)"]))
  rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  rownames(rt) <- NULL
  list(table = rt, fits = list(grouped = list(crude = mf1, model1 = mf2, model2 = mf3)))
}

block_cox_tertile <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  if (exists("dual_db_apply_cox_unified_from_cache", mode = "function")) {
    ctx <- dual_db_apply_cox_unified_from_cache(ctx)
  }
  if (exists("cox_gate_block_is_redundant", mode = "function") &&
      cox_gate_block_is_redundant("cox_tertile", ctx)) {
    br <- ctx$results$cox_branch %||% "quartile_extend"
    cli::cli_alert_info(
      "cox_tertile: 四分位已走扩展分支（{br}），跳过三分位 Cox"
    )
    return(ctx)
  }
  cfg <- ctx$config; cox_legacy <- cfg$cox %||% list(); bl_cfg <- cfg$cox_tertile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) .ct02_pause(ctx, "未找到分析数据", "请先运行 data_clean / imputation")

  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  index_var <- bl_cfg$index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) stop("cox_tertile: index_var 未设置。")
  for (v in c(time_var, event_var, index_var)) if (!v %in% names(data)) stop("cox_tertile: '", v, "' 不在数据中。")
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, data, index_var)
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    cli::cli_alert_info("分类暴露：跳过 cox_tertile，仅回归变量本身")
    return(ctx)
  }

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  data2 <- data
  if (is.character(data2[[event_var]]) || is.factor(data2[[event_var]])) {
    if (is.null(disease_label) || !nzchar(disease_label)) stop("cox_tertile: 需 config$project$analysis_group。")
    data2[[event_var]] <- ifelse(data2[[event_var]] == disease_label, 1, 0)
  }
  data2[[event_var]] <- as.numeric(data2[[event_var]])

  group_var_name <- bl_cfg$group_var
  predefined <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data2)
  raw_levels <- c("Q1", "Q2", "Q3")

  if (predefined) {
    lv <- bl_cfg$group_levels %||% raw_levels
    data2$Group <- factor(data2[[group_var_name]], levels = lv)
    if (any(is.na(data2$Group))) stop("cox_tertile: group_var 水平不一致。")
    cutoffs <- setNames(rep("", length(lv)), lv)
    raw_levels <- lv
  } else {
    qs <- as.numeric(stats::quantile(data2[[index_var]], probs = c(1/3, 2/3), na.rm = TRUE))
    data2$Group <- cut(data2[[index_var]], breaks = c(-Inf, qs, Inf),
                       labels = raw_levels, right = TRUE)
    data2$Group <- factor(data2$Group, levels = raw_levels)
    cutoffs <- c(
      Q1 = paste0("< ", round(qs[1], 2)),
      Q2 = paste0(round(qs[1], 2), " \u2013 ", round(qs[2], 2)),
      Q3 = paste0("\u2265 ", round(qs[2], 2))
    )
  }
  data2$Num <- as.numeric(data2$Group)

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
  if (length(Model1Factors) == 0L) .ct02_pause(ctx, "Model1Factors 为空", "请先运行 multicollinearity")
  if ("Glucose" %in% Model1Factors && "A1c" %in% Model1Factors) Model1Factors <- Model1Factors[Model1Factors != "A1c"]
  Model1Factors <- intersect(Model1Factors, names(data2))
  m2_pool_extra <- setdiff(intersect(m2_raw, names(data2)), Model1Factors)
  all_cov <- unique(c(Model1Factors, m2_pool_extra))

  dt <- stats::na.omit(data2[, unique(c(time_var, event_var, index_var, "Group", "Num", all_cov)), drop = FALSE])
  if (nrow(dt) < 10L) .ct02_pause(ctx, "完整病例数过少", "检查缺失", utils::head(dt, 5L))

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
      cli::cli_alert_info("cox_tertile: 三级回退 tier — 搜索 M1 非实验室池 + M2 实验室池")
    }
    if (isTRUE(ctx$results$dual_db_covariate_harmonized)) {
      cli::cli_alert_info(
        "cox_tertile: 搜索在 Gate B 统一池内（之后会再对齐两库交集）"
      )
    }
    cli::cli_alert_info(
      "cox_tertile: 协变量组合搜索（Model1≤{sc$max_model1_attempts %||% 1000L}，Model2≤{sc$max_model2_attempts %||% 1000L} 次）"
    )
    search_res <- cox_fit_searched_covariates(dt, time_var, event_var, pools$m1, pools$m2, bl_cfg)
    if (!identical(search_res$status, "ok")) {
      cox_handle_search_fail(ctx, bl_cfg, "cox_tertile", search_res)
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
      "cox_tertile: 搜索命中（M1 {search_res$m1_attempts} 次，M2 {search_res$m2_attempts} 次）"
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
    .ct02_Tb_ModelGroupNg_HR(time_var, event_var, index_var, "Group", "Num", dt,
                             Model1Factors, Model2Factors, raw_levels, cutoffs),
    error = function(e) {
      if (.ct02_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) .ct02_pause(ctx, conditionMessage(e), "检查协变量")
      stop("cox_tertile: ", conditionMessage(e), call. = FALSE)
    }
  )

  if (exists("cox_require_both_models_sig", mode = "function")) {
    ctx <- cox_require_both_models_sig(ctx, bl_cfg, "cox_tertile", res$fits$grouped, levels(dt$Group))
  }

  rt_df <- data.frame(.ct02_format_p_cells(res$table), stringsAsFactors = FALSE)
  rownames(rt_df) <- NULL
  h1 <- as.character(rt_df[1, ]); h2 <- as.character(rt_df[2, ])
  rt_body <- rt_df[-c(1L, 2L), , drop = FALSE]
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))
  caption <- paste0("The Association Between ", index_var, " and ",
                    cfg$project$disease %||% "Outcome", " (Cox tertile)")
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, "main_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  footnotes <- c("Crude Model was non-adjusted;",
                 paste0("Model 1 was adjusted by: ", paste(Model1Factors, collapse = ", ")),
                 paste0("Model 2 was adjusted by: ", paste(Model2Factors, collapse = ", ")))
  tryCatch(export_sci_table(rt_body, filepath, title = title, header_row1 = h1, header_row2 = h2,
                            latex_include_colnames = FALSE, table_footnotes = footnotes),
           error = function(e) cli::cli_alert_warning("cox_tertile: export 失败: {e$message}"))

  glv_ct <- levels(dt$Group)
  top_ct <- glv_ct[length(glv_ct)]
  hr_top_ct <- NA_real_
  mf3_ct <- tryCatch(res$fits$grouped$model2, error = function(e) NULL)
  if (!is.null(mf3_ct)) {
    cf_ct <- tryCatch(stats::coef(mf3_ct), error = function(e) NULL)
    if (!is.null(cf_ct) && length(cf_ct) >= 1L) {
      hr_top_ct <- round(exp(as.numeric(cf_ct[length(cf_ct)])), 4)
    }
  }
  ctx$results$cox_highest_group_model2_hr <- hr_top_ct
  ctx$results$cox_highest_group_level <- top_ct
  if (!predefined) ctx$results$cox_index_breaks <- as.numeric(qs)

  ctx$results$cox_hr <- rt_df
  ctx$results$cox_models <- res$fits$grouped
  ctx$results$cox_model1_covariates <- Model1Factors
  ctx$results$cox_model2_covariates <- setdiff(Model2Factors, Model1Factors)
  ctx$results$cox_grouping <- list(method = "tertile", n_groups = nlevels(dt$Group), group_levels = levels(dt$Group))
  if (exists("cox_gate_apply_after_grouped", mode = "function")) {
    ctx <- cox_gate_apply_after_grouped(ctx, bl_cfg, res$fits$grouped, levels(dt$Group))
  }
  if (exists("cox_ph_export_supp_table", mode = "function")) {
    ctx <- cox_ph_export_supp_table(ctx, res$fits$grouped, index_var, bl_cfg)
  }
  cli::cli_alert_success("cox_tertile 完成: {.file {basename(filepath)}}")
  ctx
}

register_block("cox_tertile", block_cox_tertile, "三分位 Cox HR 表（可选协变量搜索 + trend + cox_gate）")
