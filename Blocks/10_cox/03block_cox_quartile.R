###############################################################################
#  cox_quartile — 预后四分位 Cox HR（Q1 参照 + p for trend），内嵌 Tb_ModelGroup3_HR。
#
#  register_block: "cox_quartile"
#  前置: Model1Factors / Model2Factors；可选协变量组合搜索（Phase1 递减 + Phase2 递增）
#
#  cox_quartile = list(
#    index_var, group_var, group_levels, model1/2_factors,
#    covariate_search = list(
#      enable = TRUE,                  # 显式 model1+model2_factors 时默认 FALSE
#      max_model1_attempts = 1000L,
#      max_model2_attempts = 1000L,
#      on_search_fail = "degrade"      # degrade | stop
#    ),
#    degrade_branch = "degrade_tertile",
#    table_filename, table_number, pause_enable, pause_on_fit_fail,
#    ph_test_enable = TRUE,            # Schoenfeld / cox.zph 附表，默认开
#    ph_table_number = NULL            # 固定附表号，如 14L → Table S14；NULL 顺延
#  )
###############################################################################

.cq03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.cq03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "cox_quartile", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: cox_quartile — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.cq03_format_p_cells <- function(rt) {
  cols <- if (exists("pipeline_table_p_cols", mode = "function")) {
    pipeline_table_p_cols(if (is.null(rt)) 12L else ncol(as.data.frame(rt)), binary_layout = FALSE)
  } else {
    c(6L, 9L, 12L)
  }
  if (exists("pub_fix_p_cells", mode = "function")) {
    return(pub_fix_p_cells(rt, cols))
  }
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  for (j in cols) {
    if (ncol(rt) < j) next
    x <- as.character(rt[[j]])
    x[grepl("[0-9]+\\.?[0-9]*[eE][+-][0-9]+", x) | grepl("^0$", x)] <- "<0.001"
    rt[[j]] <- x
  }
  rt
}

.cq03_Tb_ModelGroupNg_HR <- function(time_var, event_var, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors, group_labels, cutoffs,
                                      Model3Factors = NULL) {
  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  rhs_c <- function(vars) paste(c(vars), collapse = " + ")
  include_m3 <- length(as.character(Model3Factors %||% character(0))) > 0L
  mc1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(ContinuousName))), data = Data)
  mc2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model1Factors)))), data = Data)
  mc3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model2Factors)))), data = Data)
  mc4 <- if (include_m3) coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model3Factors)))), data = Data) else NULL
  mf1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(FactorName))), data = Data)
  mf2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model1Factors)))), data = Data)
  mf3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model2Factors)))), data = Data)
  mf4 <- if (include_m3) coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model3Factors)))), data = Data) else NULL
  mt1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(TrendName))), data = Data)
  mt2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model1Factors)))), data = Data)
  mt3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model2Factors)))), data = Data)
  mt4 <- if (include_m3) coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model3Factors)))), data = Data) else NULL
  .hr_ci_p <- function(m, row) {
    if (exists("pub_hr_ci_p", mode = "function")) return(pub_hr_ci_p(m, row))
    sm <- summary(m); ci <- suppressMessages(confint(m))
    list(hr = round(exp(coef(m))[row], 3),
         ci = paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")"),
         p = pub_format_p_cell(sm$coefficients[row, "Pr(>|z|)"]))
  }
  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .pct <- function(lv) paste0(as.numeric(cnt[lv]), "(", round(as.numeric(cnt[lv]) / n_total * 100, 2), "%)")
  c1 <- .hr_ci_p(mc1, 1L); c2 <- .hr_ci_p(mc2, 1L); c3 <- .hr_ci_p(mc3, 1L)
  c4 <- if (include_m3) .hr_ci_p(mc4, 1L) else NULL
  n_hdr <- if (exists("pub_cox_group_n_header", mode = "function")) pub_cox_group_n_header() else "N (%)"
  hdr <- pipeline_sci_with_model3_header(
    c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", ""),
    c("Characteristic", "Exposure cutoff", n_hdr, "HR", "95%CI", "P-value",
      "HR", "95%CI", "P-value", "HR", "95%CI", "P-value"),
    include_m3, "HR"
  )
  Line1 <- hdr$line1; Line2 <- hdr$line2; n_pad <- hdr$n_pad
  Line3 <- c(ContinuousName, rep("", n_pad))
  Line4 <- c(paste0(ContinuousName, " continuous"), "", "", c1$hr, c1$ci, c1$p, c2$hr, c2$ci, c2$p, c3$hr, c3$ci, c3$p,
             if (include_m3) c(c4$hr, c4$ci, c4$p) else character(0))
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", n_pad))
  ref_lv <- group_labels[1L]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "",
                pipeline_sci_model3_ref_cells(include_m3))
  non_ref <- group_labels[-1L]
  lines_nonref <- lapply(seq_along(non_ref), function(i) {
    lv <- non_ref[i]; r <- .hr_ci_p(mf1, i); r2 <- .hr_ci_p(mf2, i); r3 <- .hr_ci_p(mf3, i)
    r4 <- if (include_m3) .hr_ci_p(mf4, i) else NULL
    c(lv, cutoffs[lv], .pct(lv), r$hr, r$ci, r$p, r2$hr, r2$ci, r2$p, r3$hr, r3$ci, r3$p,
      if (include_m3) c(r4$hr, r4$ci, r4$p) else character(0))
  })
  Line_trend <- c("p for trend", rep("", 4L),
                  pub_format_p_cell(summary(mt1)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[1, "Pr(>|z|)"]),
                  if (include_m3) c("", "", pub_format_p_cell(summary(mt4)$coefficients[1, "Pr(>|z|)"])) else character(0))
  rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  rownames(rt) <- NULL
  list(table = rt, fits = list(grouped = list(crude = mf1, model1 = mf2, model2 = mf3, model3 = mf4)))
}

block_cox_quartile <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  if (exists("dual_db_apply_cox_unified_from_cache", mode = "function")) {
    ctx <- dual_db_apply_cox_unified_from_cache(ctx)
  }
  cfg <- ctx$config; cox_legacy <- cfg$cox %||% list(); bl_cfg <- cfg$cox_quartile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) .cq03_pause(ctx, "未找到分析数据", "请先运行 data_clean / imputation")

  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  index_var <- bl_cfg$index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) stop("cox_quartile: index_var 未设置。")
  for (v in c(time_var, event_var, index_var)) if (!v %in% names(data)) stop("cox_quartile: '", v, "' 不在数据中。")
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, data, index_var)
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    cli::cli_alert_info("分类暴露：跳过 cox_quartile，仅回归变量本身")
    return(ctx)
  }

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  data2 <- data
  if (is.character(data2[[event_var]]) || is.factor(data2[[event_var]])) {
    if (is.null(disease_label) || !nzchar(disease_label)) stop("cox_quartile: 需 config$project$analysis_group。")
    data2[[event_var]] <- ifelse(data2[[event_var]] == disease_label, 1, 0)
  }
  data2[[event_var]] <- as.numeric(data2[[event_var]])

  group_var_name <- bl_cfg$group_var
  predefined <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data2)
  raw_levels <- c("Q1", "Q2", "Q3", "Q4")

  if (predefined) {
    lv <- bl_cfg$group_levels %||% raw_levels
    data2$Group <- factor(data2[[group_var_name]], levels = lv)
    if (any(is.na(data2$Group))) stop("cox_quartile: group_var 水平不一致。")
    cutoffs <- setNames(rep("", length(lv)), lv)
    raw_levels <- lv
  } else {
    qs <- as.numeric(stats::quantile(data2[[index_var]], na.rm = TRUE))
    if (exists("pipeline_quartile_factor", mode = "function")) {
      data2$Group <- pipeline_quartile_factor(data2[[index_var]], breaks = qs)
    } else {
      data2$Group <- "Q"
      data2$Group[data2[[index_var]] < qs[2]] <- "Q1"
      data2$Group[data2[[index_var]] >= qs[2] & data2[[index_var]] < qs[3]] <- "Q2"
      data2$Group[data2[[index_var]] >= qs[3] & data2[[index_var]] < qs[4]] <- "Q3"
      data2$Group[data2[[index_var]] >= qs[4]] <- "Q4"
      data2$Group <- factor(data2$Group, levels = raw_levels)
    }
    .cutn <- function(z) if (exists("fmt_num", mode = "function")) fmt_num(z) else as.character(round(z, 2))
    cutoffs <- c(
      Q1 = paste0("< ", .cutn(qs[2])),
      Q2 = paste0(.cutn(qs[2]), "-< ", .cutn(qs[3])),
      Q3 = paste0(.cutn(qs[3]), "-< ", .cutn(qs[4])),
      Q4 = paste0("\u2265 ", .cutn(qs[4]))
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
  if (length(Model1Factors) == 0L) .cq03_pause(ctx, "Model1Factors 为空", "请先运行 multicollinearity")
  if ("Glucose" %in% Model1Factors && "A1c" %in% Model1Factors) Model1Factors <- Model1Factors[Model1Factors != "A1c"]
  Model1Factors <- intersect(Model1Factors, names(data2))
  m2_pool_extra <- setdiff(intersect(m2_raw, names(data2)), Model1Factors)
  all_cov <- unique(c(Model1Factors, m2_pool_extra))

  dt <- stats::na.omit(data2[, unique(c(time_var, event_var, index_var, "Group", "Num", all_cov)), drop = FALSE])
  if (nrow(dt) < 10L) .cq03_pause(ctx, "完整病例数过少", "检查缺失", utils::head(dt, 5L))

  use_search <- exists("cox_covariate_search_enabled", mode = "function") &&
    cox_covariate_search_enabled(bl_cfg)
  prefer_full <- isTRUE((bl_cfg$covariate_search %||% list())$prefer_full_first %||% TRUE)
  if (exists("cox_select_covariates_full_then_search", mode = "function") &&
      (use_search || prefer_full)) {
    sel <- cox_select_covariates_full_then_search(
      dt, time_var, event_var, Model1Factors, m2_pool_extra, bl_cfg, ctx = ctx
    )
    if (identical(sel$status, "search_fail") ||
        (isTRUE(sel$searched) && !identical(sel$status, "search_ok") &&
           !identical(sel$status, "full_ok") && !identical(sel$status, "full_kept_ns"))) {
      if (exists("cox_handle_search_fail", mode = "function") && !is.null(sel$search_res)) {
        cox_handle_search_fail(ctx, bl_cfg, "cox_quartile", sel$search_res)
      } else if (exists("cox_handle_search_fail", mode = "function")) {
        cox_handle_search_fail(ctx, bl_cfg, "cox_quartile", list(status = sel$status))
      }
    }
    Model1Factors <- sel$M1
    Model2Factors <- sel$M2
    if (isTRUE(sel$searched) && identical(sel$status, "search_ok")) {
      ctx$results$cox_model1_covariates_searched <- Model1Factors
      ctx$results$cox_model2_covariates_searched <- setdiff(Model2Factors, Model1Factors)
      cli::cli_alert_success(
        "cox_quartile: 搜索命中（M1 {sel$m1_attempts} 次，M2 {sel$m2_attempts} 次）"
      )
    }
    enforced <- if (exists("cox_enforce_model2_gt_m1", mode = "function")) {
      # 全量已显著或已搜索命中时，不再二次强制改集（避免又搜一遍）
      if (identical(sel$status, "full_ok") || identical(sel$status, "search_ok")) {
        list(M1 = Model1Factors, M2 = Model2Factors)
      } else {
        cox_enforce_model2_gt_m1(
          Model1Factors, Model2Factors, m2_pool_extra, ctx,
          dat = dt, time_var = time_var, event_var = event_var, bl_cfg = bl_cfg
        )
      }
    } else {
      list(M1 = Model1Factors, M2 = Model2Factors)
    }
    Model1Factors <- enforced$M1
    Model2Factors <- enforced$M2
  } else if (use_search) {
    sc <- bl_cfg$covariate_search %||% list()
    pools <- if (exists("cox_resolve_covariate_search_pools", mode = "function")) {
      cox_resolve_covariate_search_pools(ctx, Model1Factors, m2_pool_extra)
    } else {
      list(m1 = Model1Factors, m2 = m2_pool_extra, lab_only_tier = FALSE)
    }
    if (isTRUE(pools$lab_only_tier)) {
      cli::cli_alert_info("cox_quartile: 三级回退 tier — 搜索 M1 非实验室池 + M2 实验室池")
    }
    cli::cli_alert_info(
      "cox_quartile: 协变量组合搜索（Model1≤{sc$max_model1_attempts %||% 1000L}，Model2≤{sc$max_model2_attempts %||% 1000L} 次）"
    )
    search_res <- cox_fit_searched_covariates(dt, time_var, event_var, pools$m1, pools$m2, bl_cfg)
    if (!identical(search_res$status, "ok")) {
      cox_handle_search_fail(ctx, bl_cfg, "cox_quartile", search_res)
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
      "cox_quartile: 搜索命中（M1 {search_res$m1_attempts} 次，M2 {search_res$m2_attempts} 次）"
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

  res <- tryCatch(
    .cq03_Tb_ModelGroupNg_HR(time_var, event_var, index_var, "Group", "Num", dt,
                             Model1Factors, Model2Factors, raw_levels, cutoffs),
    error = function(e) {
      if (.cq03_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) .cq03_pause(ctx, conditionMessage(e), "检查协变量")
      stop("cox_quartile: ", conditionMessage(e), call. = FALSE)
    }
  )

  if (exists("cox_require_both_models_sig", mode = "function")) {
    ctx <- cox_require_both_models_sig(ctx, bl_cfg, "cox_quartile", res$fits$grouped, levels(dt$Group))
  }

  Model3Factors <- character(0)
  m3_sig <- FALSE
  if (exists("pipeline_apply_model3_after_m2", mode = "function") &&
      exists("pipeline_cox_grouped_significant", mode = "function")) {
    # 学术必调列需先并入 dt，否则 sig_fn / 降级链无法拟合
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
      pipeline_cox_grouped_significant(
        dt, time_var, event_var, "Group", "Num", covs
      )
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
        keep <- unique(c(names(dt), extra))
        dt <- stats::na.omit(data2[, keep, drop = FALSE])
      }
      res_m3 <- tryCatch(
        .cq03_Tb_ModelGroupNg_HR(
          time_var, event_var, index_var, "Group", "Num", dt,
          Model1Factors, Model2Factors, raw_levels, cutoffs,
          Model3Factors = m3a$M3
        ),
        error = function(e) NULL
      )
      if (!is.null(res_m3)) {
        res <- res_m3
        Model3Factors <- m3a$M3
        m3_sig <- isTRUE(m3a$m3_sig)
        if (!m3_sig) {
          m3_sig <- pipeline_cox_grouped_significant(
            dt, time_var, event_var, "Group", "Num", Model3Factors
          )
        }
        final <- pipeline_finalize_adjusted_factors(Model2Factors, Model3Factors, m3_sig)
        ctx <- pipeline_store_model3(ctx, Model3Factors, m3_sig, final)
      }
    } else {
      # 降级可能改写了 Model2，或弃用 Model3：按最终 Model2 重出表
      res <- tryCatch(
        .cq03_Tb_ModelGroupNg_HR(
          time_var, event_var, index_var, "Group", "Num", dt,
          Model1Factors, Model2Factors, raw_levels, cutoffs
        ),
        error = function(e) res
      )
    }
  }

  rt_df <- data.frame(.cq03_format_p_cells(res$table), stringsAsFactors = FALSE)
  rownames(rt_df) <- NULL
  h1 <- as.character(rt_df[1, ]); h2 <- as.character(rt_df[2, ])
  rt_body <- rt_df[-c(1L, 2L), , drop = FALSE]
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))
  caption <- paste0("The Association Between ", index_var, " and ",
                    cfg$project$disease %||% "Outcome")
  fixed_main <- suppressWarnings(as.integer(bl_cfg$table_number %||% NA_integer_)[1L])
  if (is.finite(fixed_main) && fixed_main >= 1L) {
    pref <- pub_prefix("main_table", fixed_main)
    title <- paste(pref, caption)
    filepath <- .inject_db_into_pub_filepath(
      file.path(ctx$output_dir_tables, paste0(title, ".xlsx"))
    )
  } else if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, "main_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  footnotes <- if (exists("pipeline_model3_table_footnotes", mode = "function")) {
    pipeline_model3_table_footnotes(Model1Factors, Model2Factors, Model3Factors, m3_sig)
  } else {
    c("Crude Model was non-adjusted;",
      paste0("Model 1 was adjusted by: ", paste(Model1Factors, collapse = ", ")),
      paste0("Model 2 was adjusted by: ", paste(Model2Factors, collapse = ", ")))
  }
  tryCatch(export_sci_table(rt_body, filepath, title = title, header_row1 = h1, header_row2 = h2,
                            latex_include_colnames = FALSE, table_footnotes = footnotes),
           error = function(e) cli::cli_alert_warning("cox_quartile: export 失败: {e$message}"))

  glv_cq <- levels(dt$Group)
  top_cq <- glv_cq[length(glv_cq)]
  hr_top_cq <- NA_real_
  mf3_cq <- tryCatch(res$fits$grouped$model2, error = function(e) NULL)
  if (!is.null(mf3_cq)) {
    cf_cq <- tryCatch(stats::coef(mf3_cq), error = function(e) NULL)
    if (!is.null(cf_cq) && length(cf_cq) >= 1L) {
      hr_top_cq <- round(exp(as.numeric(cf_cq[length(cf_cq)])), 4)
    }
  }
  ctx$results$cox_highest_group_model2_hr <- hr_top_cq
  ctx$results$cox_highest_group_level <- top_cq
  if (!predefined) {
    ctx$results$cox_index_breaks <- as.numeric(qs[2:4])
    if (exists("pipeline_store_continuous_km_cutpoints", mode = "function")) {
      ctx <- pipeline_store_continuous_km_cutpoints(
        ctx, index_var, as.numeric(qs), method = "quartile"
      )
    }
  }

  ctx$results$cox_hr <- rt_df
  ctx$results$cox_models <- res$fits$grouped
  ctx$results$cox_model1_covariates <- Model1Factors
  ctx$results$cox_model2_covariates <- setdiff(Model2Factors, Model1Factors)
  ctx$results$Model1Factors <- Model1Factors
  ctx$results$Model2Factors <- Model2Factors
  ctx$results$cox_grouping <- list(method = "quartile", n_groups = nlevels(dt$Group), group_levels = levels(dt$Group))
  if (exists("cox_gate_apply_after_grouped", mode = "function")) {
    ctx <- cox_gate_apply_after_grouped(ctx, bl_cfg, res$fits$grouped, levels(dt$Group))
    if (!is.null(ctx$results$cox_gate_detail)) {
      ctx$results$cox_quartile_gate <- ctx$results$cox_gate_detail
    }
  }
  # 写回四分位列，供 KM / 后续使用（data2 由 data 拷贝）
  q_col <- paste0(index_var, "_quartile")
  if (nrow(data2) == nrow(data)) {
    data[[q_col]] <- data2$Group
  } else {
    data[[q_col]] <- NA
    data[[q_col]][seq_len(nrow(data2))] <- data2$Group
  }
  if (!is.null(ctx$data$imputed) && nrow(ctx$data$imputed) == nrow(data)) {
    ctx$data$imputed[[q_col]] <- data[[q_col]]
  }
  if (!is.null(ctx$data$cleaned) && nrow(ctx$data$cleaned) == nrow(data)) {
    ctx$data$cleaned[[q_col]] <- data[[q_col]]
  }

  # Table：按指标四分位分层的基线特征（列名 Q1–Q4；P 用 fmt_pval）
  if (isTRUE(bl_cfg$export_baseline_by_group %||% TRUE) &&
      requireNamespace("gtsummary", quietly = TRUE)) {
    tryCatch({
      d_bl <- data2
      id_col <- cfg$data$id_column %||% "ID"
      drop_cols <- unique(c(
        time_var, event_var, index_var, "Group", "Num", q_col,
        id_col, "ID", "SEQN", "subject_id", "Mortality_28d",
        as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0))
      ))
      # 暴露公式组分（如 BAR→BUN/Albumin）不得进分位基线表（定义性循环）
      if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
        drop_cols <- unique(c(
          drop_cols,
          pipeline_mediation_lab_exclude_vars(cfg, data_cols = names(d_bl))
        ))
      } else if (exists("pipeline_index_component_vars_only", mode = "function")) {
        drop_cols <- unique(c(drop_cols, pipeline_index_component_vars_only(cfg)))
      }
      bl_vars <- setdiff(names(d_bl), drop_cols)
      if (exists("sort_vars_by_table1_sections", mode = "function")) {
        bl_vars <- sort_vars_by_table1_sections(bl_vars, cfg)
      }
      bl_vars <- intersect(bl_vars, names(d_bl))
      if (length(bl_vars) >= 1L) {
        suppressPackageStartupMessages({
          library(gtsummary)
          library(dplyr)
        })
        lv <- levels(d_bl$Group)
        if (is.null(lv) || !length(lv)) lv <- as.character(sort(unique(na.omit(d_bl$Group))))
        # 二分类强制 categorical：Yes/No 各出一行（默认 dichotomous 会把 Yes 合并进标签行）
        cat_vars <- bl_vars[vapply(bl_vars, function(v) {
          x <- d_bl[[v]]
          if (is.factor(x) || is.character(x) || is.logical(x)) return(TRUE)
          if (!is.numeric(x)) return(TRUE)
          ux <- unique(stats::na.omit(x))
          length(ux) <= 5L && all(ux == floor(ux))
        }, logical(1L))]
        type_list <- lapply(cat_vars, function(v) {
          stats::as.formula(paste0("`", v, "` ~ \"categorical\""))
        })
        tbl_args <- list(
          data = d_bl[, c("Group", bl_vars), drop = FALSE],
          by = "Group",
          missing = "no"
        )
        if (length(type_list)) tbl_args$type <- type_list
        tbl_g <- do.call(gtsummary::tbl_summary, tbl_args) %>%
          gtsummary::add_overall() %>%
          gtsummary::add_p(pvalue_fun = function(x) fmt_pval(x))
        # 表头对齐 Table 1：Overall N = x,xxx / Q1 N = xxx
        n_fmt <- function(n) format(as.integer(n), big.mark = ",", scientific = FALSE, trim = TRUE)
        n_overall <- sum(!is.na(d_bl$Group))
        n_by <- as.integer(table(factor(d_bl$Group, levels = lv)))
        names(n_by) <- lv
        hdr_args <- list(
          x = tbl_g, label = "**Characteristic**",
          stat_0 = paste0("**Overall N = ", n_fmt(n_overall), "**")
        )
        for (i in seq_along(lv)) {
          hdr_args[[paste0("stat_", i)]] <- paste0("**", lv[i], " N = ", n_fmt(n_by[[lv[i]]]), "**")
        }
        tbl_g <- do.call(gtsummary::modify_header, hdr_args)
        tbl_df <- as.data.frame(tbl_g)
        # 统一列名：去掉 markdown **；P 列改名
        cn <- names(tbl_df)
        cn <- gsub("\\*\\*", "", cn)
        cn <- gsub("^p\\.value$", "P value", cn, ignore.case = TRUE)
        cn <- gsub("^p value$", "P value", cn, ignore.case = TRUE)
        # 若仍残留 stat_k，按水平回填（含 N=）
        for (i in seq_along(lv)) {
          sk <- paste0("stat_", i)
          if (sk %in% cn) cn[cn == sk] <- paste0(lv[i], " N = ", n_fmt(n_by[[lv[i]]]))
        }
        if ("stat_0" %in% cn) cn[cn == "stat_0"] <- paste0("Overall N = ", n_fmt(n_overall))
        if ("label" %in% cn) cn[cn == "label"] <- "Characteristic"
        # 清理可能残留的纯 Qk / Overall 列名
        if (any(cn == "Overall")) cn[cn == "Overall"] <- paste0("Overall N = ", n_fmt(n_overall))
        for (q in lv) {
          if (q %in% cn) cn[cn == q] <- paste0(q, " N = ", n_fmt(n_by[[q]]))
        }
        names(tbl_df) <- cn
        if ("P value" %in% names(tbl_df)) {
          pv <- tbl_df[["P value"]]
          # 若仍是数值，再套一层 fmt_pval
          if (is.numeric(pv) || any(grepl("e-|E-", as.character(pv)))) {
            tbl_df[["P value"]] <- fmt_pval(suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", as.character(pv)))))
          } else {
            # 已是字符时：统一过小值为 <0.001，并限制 3 位
            tbl_df[["P value"]] <- vapply(as.character(pv), function(s) {
              if (!nzchar(s) || is.na(s) || s %in% c("NA", " ")) return("")
              if (grepl("^\\s*<", s)) return("<0.001")
              num <- suppressWarnings(as.numeric(s))
              if (!is.finite(num)) return(s)
              fmt_pval(num)
            }, character(1L))
          }
        }

        cap_bl <- paste0("Baseline characteristics by ", index_var, " quartile")
        # 默认 S10：S7 留给 Gate C+ 双库统一多因素；可被 baseline_by_group_table_s 覆盖
        fig_no <- suppressWarnings(as.integer(
          bl_cfg$baseline_by_group_table_s %||%
            (cfg$cox_quartile %||% list())$baseline_by_group_table_s %||%
            10L
        )[1L])
        if (is.finite(fig_no) && fig_no >= 1L && exists("pub_prefix", mode = "function")) {
          if (exists("pub_bump_supp_table_min", mode = "function")) {
            pub_bump_supp_table_min(fig_no)
          }
          title_bl <- paste0(pub_prefix("supp_table", fig_no), " ", cap_bl)
          if (exists(".inject_db_into_pub_label", mode = "function")) {
            title_bl <- .inject_db_into_pub_label(title_bl, sanitize_for_file = TRUE)
          }
          pub_bl <- list(
            title = title_bl,
            filepath = file.path(ctx$output_dir_tables, paste0(title_bl, ".xlsx"))
          )
        } else {
          pub_bl <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_bl, "xlsx")
        }
        dir.create(dirname(pub_bl$filepath), recursive = TRUE, showWarnings = FALSE)
        export_sci_table(tbl_df, pub_bl$filepath, title = pub_bl$title)
        if (exists("mirror_pub_output_to_root", mode = "function")) {
          mirror_pub_output_to_root(ctx, pub_bl$filepath)
        }
        cli::cli_alert_success("按 {index_var} 四分位基线表: {.file {basename(pub_bl$filepath)}}")
      }
    }, error = function(e) {
      cli::cli_alert_warning("cox_quartile 基线表(按分组)失败: {e$message}")
    })
  }

  if (exists("cox_ph_export_supp_table", mode = "function")) {
    ctx <- cox_ph_export_supp_table(
      ctx, res$fits$grouped, index_var, bl_cfg,
      model1_factors = Model1Factors,
      model2_factors = Model2Factors,
      model3_factors = Model3Factors,
      m3_significant = m3_sig
    )
  }

  cli::cli_alert_success("cox_quartile 完成: {.file {basename(filepath)}}")
  ctx
}

register_block("cox_quartile", block_cox_quartile, "四分位 Cox HR 表（可选协变量搜索 + trend + cox_gate + PH 检验）")
