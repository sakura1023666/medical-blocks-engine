###############################################################################
#  Block: COX — 多模型 Cox 比例风险回归
#
#  模型定义:
#    Crude   — 仅分组变量单因素；不显著则（auto/manual）跳下一分位，二分位仍不显著则 stop
#    Model1/2 — 候选协变量子集按规模递增自动组合搜索，直至目标组显著，再经 VIF 修剪
#
#  分组策略:
#    auto — 四分位 → 三分位 → 二分位；Crude 不显著则跳过该档；三模型均显著才采纳，否则 stop（无回退）
#    manual — 固定 2/3/4 分位分组（见 config$cox$manual_n_groups）
#    predefined — 数据已有分类列：设 config$cox$group_var 或 block_COX(..., group_var=)
#                可选 config$cox$group_levels 固定因子水平顺序（见 config.R）
#
#  输入:
#    time_var: 生存时间变量名
#    event_var: 事件变量名
#    index_var: 核心指标变量名 (连续变量)
#    model1_covariates: Model1 协变量 (优先从multicollinearity读取)
#    model2_covariates: Model2 协变量 (优先从multicollinearity读取)
#
#  输出:
#    Table_Cox_HR.xlsx — HR 表格
#    ctx$results$cox_models — 模型结果
###############################################################################

block_COX <- function(ctx, time_var = NULL, event_var = NULL,
                       index_var = NULL,
                       group_var = NULL,
                       model1_covariates = NULL, model2_covariates = NULL,
                       vif_threshold = 4, p_threshold = 0.05, ...) {
  suppressPackageStartupMessages({
    library(survival)
  })

  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'data_clean' or 'imputation' first.")

  cox_cfg <- cfg$cox %||% list()
  surv_cfg <- cfg$survival %||% list()

  time_var <- time_var %||% surv_cfg$time_var %||% "futime"
  event_var <- event_var %||% surv_cfg$event_var %||% "fustatus"
  index_var <- index_var %||% surv_cfg$index_var %||% cfg$logistic$index_var
  p_threshold <- p_threshold %||% cox_cfg$p_threshold %||% 0.05
  
  vif_threshold <- vif_threshold %||% cox_cfg$vif_threshold %||% 4
  grouping_mode <- tolower(trimws(cox_cfg$grouping_mode %||% "auto"))
  if (grouping_mode %in% c("preset", "external", "categorical", "fixed")) {
    grouping_mode <- "predefined"
  }
  predefined_group_var <- if (identical(grouping_mode, "predefined")) {
    gv <- group_var %||% cox_cfg$group_var %||% cox_cfg$predefined_group_var
    if (is.null(gv) || (is.character(gv) && !nzchar(gv[1L]))) {
      stop("grouping_mode='predefined' 需要 config$cox$group_var（或 block_COX(..., group_var=)）指定数据中已有分组列名。")
    }
    as.character(gv)[1L]
  } else {
    NULL
  }
  manual_n_groups <- as.integer(cox_cfg$manual_n_groups %||% 2L)
  manual_cov_enable <- isTRUE(cox_cfg$manual_covariates_enable)

  if (identical(grouping_mode, "manual") && manual_cov_enable &&
      is.null(model1_covariates) && is.null(model2_covariates)) {
    # 手动模式可选：强制使用 config$cox$model1_covariates / model2_covariates
    model1_covariates <- cox_cfg$model1_covariates %||% character(0)
    model2_covariates <- cox_cfg$model2_covariates %||% character(0)
    cli::cli_alert_info("Manual covariates enabled: using config$cox model1/model2 covariates.")
  } else {
    model1_covariates <- model1_covariates %||%
      ctx$results$Model1Factors %||%
      cox_cfg$model1_covariates %||%
      character(0)
    model2_covariates <- model2_covariates %||%
      ctx$results$Model2Factors %||%
      cox_cfg$model2_covariates %||%
      character(0)
  }

  # 预后分析：阳性事件标签须与结局列取值一致（优先 analysis_group，勿用 disease 名误当事件标签）
  disease_label <- cfg$project$analysis_group 

  if (is.character(data[[event_var]]) || is.factor(data[[event_var]])) {
    data[[event_var]] <- ifelse(data[[event_var]] == disease_label, 1, 0)
  }
  data[[event_var]] <- as.numeric(data[[event_var]])

  model1_covariates <- intersect(model1_covariates, names(data))
  model2_covariates <- setdiff(intersect(model2_covariates, names(data)), model1_covariates)
  if (!is.null(predefined_group_var)) {
    model1_covariates <- setdiff(model1_covariates, predefined_group_var)
    model2_covariates <- setdiff(model2_covariates, predefined_group_var)
  }

  cli::cli_h2("Cox Proportional Hazards Regression")
  cli::cli_alert_info("Time: {time_var}, Event: {event_var}")
  cli::cli_alert_info("Index variable: {index_var}")
  cli::cli_alert_info("VIF threshold: {vif_threshold}")
  cli::cli_alert_info("P-value threshold for group significance: {p_threshold}")
  cli::cli_alert_info("Candidate Model1 covariates (from multicollinearity): {paste(model1_covariates, collapse=', ')}")
  cli::cli_alert_info("Candidate Model2 covariates (from multicollinearity): {paste(model2_covariates, collapse=', ')}")
  cli::cli_alert_info("Grouping mode: {grouping_mode}")
  if (!is.null(predefined_group_var)) {
    cli::cli_alert_info("Predefined group column: {predefined_group_var}")
  }

  req_core <- c(time_var, event_var, index_var)
  if (!is.null(predefined_group_var)) {
    req_core <- unique(c(req_core, predefined_group_var))
  }
  for (v in req_core) {
    if (!v %in% names(data)) {
      stop(paste0("Variable '", v, "' not found in data."))
    }
  }

  all_vars <- unique(c(time_var, event_var, index_var, model1_covariates, model2_covariates))
  if (!is.null(predefined_group_var)) {
    all_vars <- unique(c(all_vars, predefined_group_var))
  }
  analysis_data <- data[, all_vars, drop = FALSE]
  analysis_data <- na.omit(analysis_data)

  .create_quantile_groups <- function(data, var, n_groups) {
    values <- data[[var]]
    if (n_groups == 4) {
      probs <- c(0, 0.25, 0.5, 0.75, 1)
      labels <- c("Q1", "Q2", "Q3", "Q4")
    } else if (n_groups == 3) {
      probs <- c(0, 1/3, 2/3, 1)
      labels <- c("T1", "T2", "T3")
    } else {
      probs <- c(0, 0.5, 1)
      labels <- c("low", "high")
    }
    
    cut_points <- quantile(values, probs = probs, na.rm = TRUE)
    cut_points <- unique(cut_points)
    
    if (length(cut_points) < 2) {
      return(NULL)
    }
    
    if (length(cut_points) - 1 < n_groups) {
      n_groups <- length(cut_points) - 1
      if (n_groups == 1) {
        return(NULL)
      }
      labels <- labels[1:n_groups]
    }
    
    groups <- cut(values, breaks = cut_points, labels = labels, include.lowest = TRUE)
    groups
  }

  .test_group_significance <- function(data, group_var, time_var, event_var, p_thresh) {
    formula_str <- paste0("Surv(", time_var, ", ", event_var, ") ~ ", group_var)
    fit <- tryCatch(coxph(as.formula(formula_str), data = data), error = function(e) NULL)
    
    if (is.null(fit)) {
      return(list(significant = FALSE, p_value = NA, fit = NULL))
    }
    
    smry <- summary(fit)
    coef_mat <- smry$coefficients
    
    group_coefs <- coef_mat[grep(group_var, rownames(coef_mat)), , drop = FALSE]
    
    if (nrow(group_coefs) == 0) {
      return(list(significant = FALSE, p_value = NA, fit = NULL))
    }
    
    p_values <- group_coefs[, "Pr(>|z|)"]
    min_p <- min(p_values, na.rm = TRUE)
    
    list(
      significant = !is.na(min_p) && min_p < p_thresh,
      p_value = min_p,
      fit = fit,
      n_groups = length(unique(data[[group_var]]))
    )
  }

  if (!identical(grouping_mode, "predefined")) {
    cli::cli_h2("Auto-selecting optimal grouping strategy")
  }

  .check_vif <- function(vars, data, time_var, event_var, vif_thresh = 4) {
    if (length(vars) <= 1) return(list(kept = vars, removed = character(0), vif_df = NULL))

    fml <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(vars, collapse = " + ")))
    fit <- tryCatch(coxph(fml, data = data), error = function(e) NULL)
    if (is.null(fit)) return(list(kept = vars, removed = character(0), vif_df = NULL))

    X <- model.matrix(fit)[, -1, drop = FALSE]
    if (ncol(X) <= 1) return(list(kept = vars, removed = character(0), vif_df = NULL))

    kept <- vars
    removed <- character(0)
    vif_df_list <- list()

    repeat {
      fml2 <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(kept, collapse = " + ")))
      fit2 <- tryCatch(coxph(fml2, data = data), error = function(e) NULL)
      if (is.null(fit2) || length(kept) <= 1) break

      X2 <- model.matrix(fit2)[, -1, drop = FALSE]
      if (ncol(X2) == 0) break

      r2s <- sapply(seq_len(ncol(X2)), function(j) {
        if (ncol(X2) == 1) return(0)
        summary(lm(X2[, j] ~ X2[, -j, drop = FALSE]))$r.squared
      })
      vif_vals <- 1 / (1 - r2s)
      names(vif_vals) <- colnames(X2)

      if (all(vif_vals < vif_thresh, na.rm = TRUE)) {
        vif_df_list[[length(vif_df_list) + 1]] <- data.frame(
          variable = names(vif_vals),
          VIF = round(vif_vals, 3),
          kept = TRUE,
          stringsAsFactors = FALSE
        )
        break
      }

      worst <- names(which.max(vif_vals))
      orig <- kept[sapply(kept, function(v) any(startsWith(worst, v)))]
      if (length(orig) == 0) orig <- worst
      orig <- orig[1]
      removed <- c(removed, orig)
      kept <- setdiff(kept, orig)
      cli::cli_alert_warning("VIF >= {vif_thresh}, removing: {orig} (VIF={round(max(vif_vals),2)})")
    }

    vif_df <- if (length(vif_df_list) > 0) do.call(rbind, vif_df_list) else NULL
    list(kept = kept, removed = removed, vif_df = vif_df)
  }

  .extract_cox_result <- function(fit, group_var = "Group") {
    if (is.null(fit)) return(NULL)
    smry <- summary(fit)
    coef_mat <- smry$coefficients
    ci <- smry$conf.int

    group_rows <- grep(group_var, rownames(coef_mat), value = TRUE)
    
    if (length(group_rows) == 0) {
      return(NULL)
    }
    
    results_list <- lapply(group_rows, function(var_name) {
      hr <- ci[var_name, "exp(coef)"]
      ci_lo <- ci[var_name, "lower .95"]
      ci_hi <- ci[var_name, "upper .95"]
      p_val <- coef_mat[var_name, "Pr(>|z|)"]
      
      list(
        comparison = var_name,
        HR = hr,
        CI_lo = ci_lo,
        CI_hi = ci_hi,
        P = p_val
      )
    })
    
    list(
      results = results_list,
      n = fit$n,
      n_groups = length(group_rows) + 1
    )
  }

  .fmt_hr <- function(res) {
    if (is.null(res)) return(list(hr_ci = "—", p = "—"))
    paste0(fmt_num(res$HR), " (", fmt_num(res$CI_lo), "-", fmt_num(res$CI_hi), ")")
  }

  .fmt_p <- function(res) {
    if (is.null(res)) return("—")
    fmt_pval(res$P)
  }

  .target_group_p <- function(fit, target_level, group_var = "Group") {
    if (is.null(fit) || is.null(target_level) || !nzchar(target_level)) return(NA_real_)
    smry <- summary(fit)
    coef_mat <- smry$coefficients
    rn <- rownames(coef_mat)
    target_row <- paste0(group_var, target_level)
    if (target_row %in% rn) {
      return(coef_mat[target_row, "Pr(>|z|)"])
    }
    gv_esc <- gsub("([.|()[\\]{}^$+*?\\\\])", "\\\\\\1", group_var, perl = TRUE)
    hit <- rn[grepl(paste0("^", gv_esc), rn)]
    suf <- sub(paste0("^", gv_esc), "", hit)
    w <- which(suf == target_level)
    if (length(w) == 1L) return(coef_mat[hit[w], "Pr(>|z|)"])
    NA_real_
  }

  .check_group_significant <- function(fit, target_level, group_var = "Group", p_threshold = 0.05) {
    if (is.null(fit)) return(FALSE)
    p_val <- .target_group_p(fit, target_level, group_var = group_var)
    !is.na(p_val) && p_val < p_threshold
  }

  .search_sig_covariate_combo_cox <- function(dat, base_vars, candidates, target_level) {
    if (length(base_vars) == 0L) base_vars <- "Group"
    for (S in covariate_subsets_increasing_order(candidates)) {
      rhs <- unique(c(base_vars, S))
      fml <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(rhs, collapse = " + ")))
      fit <- tryCatch(coxph(fml, data = dat), error = function(e) NULL)
      if (is.null(fit)) next
      if (!.check_group_significant(fit, target_level = target_level, p_threshold = p_threshold)) next
      if (length(rhs) > 1L) {
        vres <- .check_vif(rhs, dat, time_var, event_var, vif_threshold)
        rhs2 <- vres$kept
        fml2 <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(rhs2, collapse = " + ")))
        fit2 <- tryCatch(coxph(fml2, data = dat), error = function(e) NULL)
        if (is.null(fit2) || !.check_group_significant(fit2, target_level = target_level, p_threshold = p_threshold)) next
        return(list(fit = fit2, vars = rhs2, vif_df = vres$vif_df))
      }
      return(list(fit = fit, vars = rhs, vif_df = NULL))
    }
    list(fit = NULL, vars = NULL, vif_df = NULL)
  }

  .fit_multimodel_cox_grouped <- function(dat, grouping_name, n_groups_meta, skip_adj_if_crude_ns = TRUE) {
    dat$Group <- droplevels(dat$Group)
    target_level <- tail(levels(dat$Group), 1)
    group_counts_local <- table(dat$Group)
    cli::cli_alert_info("{grouping_name}: patients {nrow(dat)} ({paste(names(group_counts_local), '=', group_counts_local, collapse=', ')})")
    cli::cli_alert_info("{grouping_name}: target group for significance = {target_level}")

    crude_fit_local <- tryCatch(
      coxph(as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ Group")), data = dat),
      error = function(e) NULL
    )
    crude_sig <- .check_group_significant(crude_fit_local, target_level = target_level, p_threshold = p_threshold)
    crude_p <- .target_group_p(crude_fit_local, target_level = target_level)
    cli::cli_alert_info("{grouping_name}: Crude target-group P = {fmt_pval(crude_p)} ({ifelse(crude_sig, 'Significant', 'Not significant')})")

    if (!crude_sig && isTRUE(skip_adj_if_crude_ns)) {
      cli::cli_alert_info("{grouping_name}: Crude 不显著，跳过 Model1/Model2（由外层决定是否尝试下一分位）。")
      return(list(
        grouping_name = grouping_name,
        n_groups = n_groups_meta,
        data = dat,
        crude_fit = crude_fit_local,
        model1_fit = NULL,
        model2_fit = NULL,
        crude_res = .extract_cox_result(crude_fit_local),
        model1_res = NULL,
        model2_res = NULL,
        model1_vars = "Group",
        model2_vars = NULL,
        final_model1_cov = character(0),
        final_model2_cov = character(0),
        vif_all = list(Model1 = NULL, Model2 = NULL),
        all_significant = FALSE,
        crude_sig = FALSE,
        model1_sig = FALSE,
        model2_sig = FALSE
      ))
    }

    r1 <- .search_sig_covariate_combo_cox(dat, "Group", model1_covariates, target_level)
    m1_vars_local <- r1$vars %||% "Group"
    if (is.null(m1_vars_local)) m1_vars_local <- "Group"
    vif1 <- list(vif_df = r1$vif_df %||% NULL)
    if (is.null(r1$fit) && length(model1_covariates) > 0L) {
      m1_vars_local <- "Group"
      vif1 <- list(vif_df = NULL)
    }
    model1_fit_local <- if (!is.null(r1$fit)) r1$fit else tryCatch(
      coxph(as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ Group")), data = dat),
      error = function(e) NULL
    )
    model1_sig <- .check_group_significant(model1_fit_local, target_level = target_level, p_threshold = p_threshold)
    model1_p <- .target_group_p(model1_fit_local, target_level = target_level)
    cli::cli_alert_info("{grouping_name}: Model1 target-group P = {fmt_pval(model1_p)} ({ifelse(model1_sig, 'Significant', 'Not significant')})")

    final_model1_cov_local <- setdiff(m1_vars_local, "Group")
    m2_base <- unique(c("Group", final_model1_cov_local))
    r2 <- .search_sig_covariate_combo_cox(dat, m2_base, model2_covariates, target_level)
    m2_vars_local <- r2$vars
    vif2 <- list(vif_df = r2$vif_df %||% NULL)
    if (is.null(m2_vars_local)) {
      m2_vars_local <- m2_base
      vif2 <- list(vif_df = NULL)
      if (length(m2_vars_local) > 1L) {
        vif2 <- .check_vif(m2_vars_local, dat, time_var, event_var, vif_threshold)
        m2_vars_local <- vif2$kept
      }
      model2_fit_local <- tryCatch(
        coxph(as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(m2_vars_local, collapse = " + "))), data = dat),
        error = function(e) NULL
      )
    } else {
      model2_fit_local <- r2$fit
    }
    model2_sig <- .check_group_significant(model2_fit_local, target_level = target_level, p_threshold = p_threshold)
    model2_p <- .target_group_p(model2_fit_local, target_level = target_level)
    cli::cli_alert_info("{grouping_name}: Model2 target-group P = {fmt_pval(model2_p)} ({ifelse(model2_sig, 'Significant', 'Not significant')})")

    list(
      grouping_name = grouping_name,
      n_groups = n_groups_meta,
      data = dat,
      crude_fit = crude_fit_local,
      model1_fit = model1_fit_local,
      model2_fit = model2_fit_local,
      crude_res = .extract_cox_result(crude_fit_local),
      model1_res = .extract_cox_result(model1_fit_local),
      model2_res = .extract_cox_result(model2_fit_local),
      model1_vars = m1_vars_local,
      model2_vars = m2_vars_local,
      final_model1_cov = final_model1_cov_local,
      final_model2_cov = setdiff(m2_vars_local, c("Group", final_model1_cov_local)),
      vif_all = list(Model1 = vif1$vif_df %||% NULL, Model2 = vif2$vif_df %||% NULL),
      all_significant = crude_sig && model1_sig && model2_sig,
      crude_sig = crude_sig,
      model1_sig = model1_sig,
      model2_sig = model2_sig
    )
  }

  .evaluate_grouping <- function(n_groups, grouping_name) {
    dat <- analysis_data
    dat$Group <- .create_quantile_groups(dat, index_var, n_groups)
    if (is.null(dat$Group)) {
      cli::cli_alert_warning("{grouping_name}: grouping failed (insufficient unique values)")
      return(NULL)
    }
    dat$Group <- factor(dat$Group)
    .fit_multimodel_cox_grouped(dat, grouping_name, n_groups, skip_adj_if_crude_ns = TRUE)
  }

  .evaluate_predefined_grouping <- function(group_col) {
    dat <- analysis_data
    if (!group_col %in% names(dat)) return(NULL)
    graw <- dat[[group_col]]
    glv <- cox_cfg$group_levels %||% NULL
    if (length(glv) > 0L) {
      dat$Group <- factor(as.character(graw), levels = as.character(glv))
      dat <- dat[!is.na(dat$Group), , drop = FALSE]
    } else {
      dat$Group <- factor(graw)
    }
    if (nrow(dat) < 2L) {
      cli::cli_alert_warning("predefined: no rows left after group factorization")
      return(NULL)
    }
    dat$Group <- droplevels(dat$Group)
    if (nlevels(dat$Group) < 2L) {
      cli::cli_alert_warning("predefined: need >= 2 group levels in '{group_col}'")
      return(NULL)
    }
    cli::cli_h2("Predefined grouping: {group_col}")
    cli::cli_alert_info("predefined: levels = {paste(levels(dat$Group), collapse=', ')}")
    .fit_multimodel_cox_grouped(dat, "predefined", as.integer(nlevels(dat$Group)), skip_adj_if_crude_ns = FALSE)
  }

  if (identical(grouping_mode, "predefined")) {
    selected_eval <- .evaluate_predefined_grouping(predefined_group_var)
    if (is.null(selected_eval)) {
      stop("Predefined Cox: 列 '", predefined_group_var, "' 无法构造有效的分组（需至少 2 个水平且数据完整）。")
    }
    if (!isTRUE(selected_eval$all_significant)) {
      cli::cli_alert_warning("predefined: Crude/Model1/Model2 未必全部显著；仍按已有分组输出结果。")
    }
  } else {
    if (identical(grouping_mode, "manual")) {
      if (!manual_n_groups %in% c(2L, 3L, 4L)) {
        stop("config$cox$manual_n_groups must be one of 2/3/4 when grouping_mode='manual'.")
      }
      candidate_groupings <- switch(
        as.character(manual_n_groups),
        "4" = list(list(name = "quartile", n = 4, label = "Manual quartile (Q1-Q4)")),
        "3" = list(list(name = "tertile", n = 3, label = "Manual tertile (T1-T3)")),
        list(list(name = "median", n = 2, label = "Manual median (low/high)"))
      )
      cli::cli_alert_info("Manual grouping enabled: force {manual_n_groups}-group.")
    } else {
      candidate_groupings <- list(
        list(name = "quartile", n = 4, label = "Step1 quartile (Q1-Q4)"),
        list(name = "tertile", n = 3, label = "Step2 tertile (T1-T3)"),
        list(name = "median", n = 2, label = "Step3 median (low/high)")
      )
      cli::cli_alert_info("Auto grouping enabled: quartile -> tertile -> median fallback.")
    }

    selected_eval <- NULL
    last_ev <- NULL
    for (cand in candidate_groupings) {
      cli::cli_h2("Testing {cand$label}")
      ev <- .evaluate_grouping(cand$n, cand$name)
      if (is.null(ev)) next
      last_ev <- ev
      if (!isTRUE(ev$crude_sig)) {
        cli::cli_alert_warning(
          "{cand$name}: Crude 模型目标组不显著 (P>={p_threshold})，跳过该分位，尝试下一分位。"
        )
        next
      }
      if (!isTRUE(ev$model1_sig) || !isTRUE(ev$model2_sig)) {
        cli::cli_alert_warning(
          "{cand$name}: 协变量自动组合下 Model1 或 Model2 无法使目标组达到 P<{p_threshold}，尝试下一分位。"
        )
        next
      }
      selected_eval <- ev
      cli::cli_alert_success("已选择 {cand$name}：Crude / Model1 / Model2 目标组均显著。")
      break
    }
    if (is.null(selected_eval)) {
      if (is.null(last_ev)) {
        stop("无法为 Cox 构造任何有效分组（各分位切分失败或数据不足）。", call. = FALSE)
      }
      if (!isTRUE(last_ev$crude_sig)) {
        if (identical(grouping_mode, "manual")) {
          stop(
            paste0(
              "MANUAL_GROUPING_STOP: 当前固定分组 (", last_ev$grouping_name,
              ") 下 Crude 目标组不显著 (P>=", p_threshold,
              ")。请改用 auto、调整阈值或检查数据。"
            ),
            call. = FALSE
          )
        }
        stop(
          paste0(
            "AUTO_GROUPING_STOP: 已依次尝试四分位、三分位、二分位(median)；",
            "最后一档 (", last_ev$grouping_name, ") 上 Crude 目标组仍不显著 (P>=",
            p_threshold,
            ")。即使用二分位仍无法得到显著 crude 关联，流程终止。"
          ),
          call. = FALSE
        )
      }
      stop(
        paste0(
          "AUTO_GROUPING_STOP: 在分组 ", last_ev$grouping_name,
          " 上 Crude 已显著，但协变量自动组合无法使 Model1 与 Model2 目标组同时达到 P<",
          p_threshold,
          "。请检查 Model1Factors/Model2Factors 与 VIF 阈值 (", vif_threshold, ")."
        ),
        call. = FALSE
      )
    }
  }

  selected_grouping <- selected_eval$grouping_name
  analysis_data <- selected_eval$data
  crude_fit <- selected_eval$crude_fit
  model1_fit <- selected_eval$model1_fit
  model2_fit <- selected_eval$model2_fit
  crude_res <- selected_eval$crude_res
  model1_res <- selected_eval$model1_res
  model2_res <- selected_eval$model2_res
  m1_vars <- selected_eval$model1_vars
  m2_vars <- selected_eval$model2_vars
  final_model1_covariates <- selected_eval$final_model1_cov
  final_model2_covariates <- selected_eval$final_model2_cov
  vif_all <- selected_eval$vif_all

  bl_fc <- cfg$force_continuous_vars %||% character(0)
  idx_nm <- gsub("_", " ", index_var, fixed = TRUE)
  grp_lab <- switch(
    selected_grouping,
    quartile = "quartiles",
    tertile = "tertiles",
    median = "median split",
    predefined = (cox_cfg$predefined_group_label %||% "predefined groups"),
    selected_grouping
  )
  tab2_pub <- pub_pair(
    ctx, ctx$output_dir_tables, "main_table",
    title_caption = paste0(
      "Basic characteristics of participants by ", idx_nm, " (", grp_lab, ")"
    ),
    file_caption = paste0(
      "Basic characteristics by ", index_var, " ", selected_grouping, " (Cox cohort)"
    ),
    ext = "xlsx"
  )
  t2_res <- tryCatch(
    export_table2_characteristics_by_strata(
      data = analysis_data,
      strata_col = "Group",
      index_var = index_var,
      selected_grouping = selected_grouping,
      exclude_cols = unique(c(index_var, time_var, event_var)),
      filepath = tab2_pub$filepath,
      title = tab2_pub$title,
      p_threshold = cfg$baseline$p_threshold %||% 0.05,
      force_continuous = bl_fc
    ),
    error = function(e) {
      cli::cli_alert_warning("Table 2 (characteristics, Cox) 导出异常: {e$message}")
      NULL
    }
  )
  if (!is.null(t2_res) && !is.null(t2_res$tbl_df)) {
    ctx$results$cox_table2_characteristics <- t2_res$tbl_df
  }

  group_levels <- levels(analysis_data$Group)
  n_groups <- length(group_levels)
  group_counts <- table(analysis_data$Group)
  cli::cli_alert_info("Final grouping: {selected_grouping} ({paste(names(group_counts), '=', group_counts, collapse=', ')})")

  cli::cli_h2("Building output table")

  .extract_continuous_result <- function(fit, var_name) {
    if (is.null(fit)) return(NULL)
    smry <- summary(fit)
    coef_mat <- smry$coefficients
    ci <- smry$conf.int
    if (!var_name %in% rownames(coef_mat) || !var_name %in% rownames(ci)) return(NULL)
    list(
      HR = ci[var_name, "exp(coef)"],
      CI_lo = ci[var_name, "lower .95"],
      CI_hi = ci[var_name, "upper .95"],
      P = coef_mat[var_name, "Pr(>|z|)"]
    )
  }

  .compute_cutoffs <- function(values, selected_grouping) {
    probs <- switch(selected_grouping,
      "quartile" = c(0, 0.25, 0.5, 0.75, 1),
      "tertile" = c(0, 1 / 3, 2 / 3, 1),
      c(0, 0.5, 1)
    )
    cuts <- quantile(values, probs = probs, na.rm = TRUE)
    unique(cuts)
  }

  .fmt_cutoff <- function(lo, hi, is_last = FALSE) {
    if (is_last) {
      return(paste0(">= ", fmt_num(lo)))
    }
    paste0(fmt_num(lo), " - ", fmt_num(hi))
  }

  .fit_group_trend <- function(data, time_var, event_var, group_factor, covariates = character(0)) {
    dat <- data
    dat$GroupTrend <- as.numeric(group_factor)
    vars <- c("GroupTrend", covariates)
    fml <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", paste(vars, collapse = " + ")))
    fit <- tryCatch(coxph(fml, data = dat), error = function(e) NULL)
    if (is.null(fit)) return("—")
    sm <- summary(fit)$coefficients
    if (!"GroupTrend" %in% rownames(sm)) return("—")
    fmt_pval(sm["GroupTrend", "Pr(>|z|)"])
  }

  .lookup_group_row <- function(res, group_name) {
    if (is.null(res) || is.null(res$results)) return(NULL)
    hit <- which(vapply(res$results, function(x) identical(x$comparison, group_name), logical(1)))
    if (length(hit) == 0) return(NULL)
    res$results[[hit[1]]]
  }

  .fmt_effect_cols <- function(x) {
    if (is.null(x)) return(list(hr = "—", ci = "—", p = "—"))
    list(
      hr = fmt_num(x$HR),
      ci = paste0("(", fmt_num(x$CI_lo), ", ", fmt_num(x$CI_hi), ")"),
      p = fmt_pval(x$P)
    )
  }

  .ref_effect_cols <- function() list(hr = "Ref", ci = "", p = "")

  use_index_cutoffs <- !identical(selected_grouping, "predefined")
  include_continuous_row <- is.null(predefined_group_var) ||
    !identical(as.character(index_var), as.character(predefined_group_var))

  grouping_info <- switch(selected_grouping,
    "quartile" = "quartiles",
    "tertile" = "tertiles",
    "median" = "median",
    "predefined" = (cox_cfg$predefined_group_label %||% "preset categories"),
    selected_grouping
  )

  if (include_continuous_row) {
    continuous_crude_fit <- tryCatch(
      coxph(as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", index_var)), data = analysis_data),
      error = function(e) NULL
    )
    continuous_m1_fit <- if (length(final_model1_covariates) > 0) {
      tryCatch(
        coxph(
          as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", index_var, " + ",
                            paste(final_model1_covariates, collapse = " + "))),
          data = analysis_data
        ),
        error = function(e) NULL
      )
    } else continuous_crude_fit
    continuous_m2_fit <- if (length(c(final_model1_covariates, final_model2_covariates)) > 0) {
      tryCatch(
        coxph(
          as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", index_var, " + ",
                            paste(c(final_model1_covariates, final_model2_covariates), collapse = " + "))),
          data = analysis_data
        ),
        error = function(e) NULL
      )
    } else continuous_crude_fit
  } else {
    continuous_crude_fit <- NULL
    continuous_m1_fit <- NULL
    continuous_m2_fit <- NULL
  }

  cont_cr <- if (include_continuous_row) {
    .fmt_effect_cols(.extract_continuous_result(continuous_crude_fit, index_var))
  } else {
    list(hr = "—", ci = "—", p = "—")
  }
  cont_m1 <- if (include_continuous_row) {
    .fmt_effect_cols(.extract_continuous_result(continuous_m1_fit, index_var))
  } else {
    list(hr = "—", ci = "—", p = "—")
  }
  cont_m2 <- if (include_continuous_row) {
    .fmt_effect_cols(.extract_continuous_result(continuous_m2_fit, index_var))
  } else {
    list(hr = "—", ci = "—", p = "—")
  }

  group_counts <- table(analysis_data$Group)
  n_total <- nrow(analysis_data)
  cut_points <- if (use_index_cutoffs && index_var %in% names(analysis_data)) {
    .compute_cutoffs(analysis_data[[index_var]], selected_grouping)
  } else {
    numeric(0)
  }
  group_levels <- levels(analysis_data$Group)

  rows <- list()
  if (include_continuous_row) {
    rows[[length(rows) + 1]] <- data.frame(
      Characteristic = paste0(index_var, " continuous"),
      Exposure_cutoff = "",
      Case_pct = "",
      Crude_HR = cont_cr$hr, Crude_CI = cont_cr$ci, Crude_P = cont_cr$p,
      Model1_HR = cont_m1$hr, Model1_CI = cont_m1$ci, Model1_P = cont_m1$p,
      Model2_HR = cont_m2$hr, Model2_CI = cont_m2$ci, Model2_P = cont_m2$p,
      stringsAsFactors = FALSE
    )
  }

  subheader_char <- if (identical(selected_grouping, "predefined") && !is.null(predefined_group_var)) {
    paste0(predefined_group_var, " (", grouping_info, ")")
  } else {
    paste0(index_var, " ", grouping_info)
  }
  rows[[length(rows) + 1]] <- data.frame(
    Characteristic = subheader_char,
    Exposure_cutoff = "", Case_pct = "",
    Crude_HR = "", Crude_CI = "", Crude_P = "",
    Model1_HR = "", Model1_CI = "", Model1_P = "",
    Model2_HR = "", Model2_CI = "", Model2_P = "",
    stringsAsFactors = FALSE
  )

  for (i in seq_along(group_levels)) {
    lv <- group_levels[i]
    n_lv <- as.numeric(group_counts[lv])
    case_pct <- paste0(n_lv, " (", fmt_num(100 * n_lv / n_total), "%)")
    cutoff <- if (use_index_cutoffs && length(cut_points) >= 2 && i <= length(cut_points) - 1) {
      .fmt_cutoff(cut_points[i], cut_points[i + 1], is_last = (i == length(group_levels)))
    } else ""
    if (i == 1) {
      cr <- .ref_effect_cols()
      m1 <- .ref_effect_cols()
      m2 <- .ref_effect_cols()
    } else {
      cmp_name <- paste0("Group", lv)
      cr <- .fmt_effect_cols(.lookup_group_row(crude_res, cmp_name))
      m1 <- .fmt_effect_cols(.lookup_group_row(model1_res, cmp_name))
      m2 <- .fmt_effect_cols(.lookup_group_row(model2_res, cmp_name))
    }
    rows[[length(rows) + 1]] <- data.frame(
      Characteristic = lv,
      Exposure_cutoff = cutoff,
      Case_pct = case_pct,
      Crude_HR = cr$hr, Crude_CI = cr$ci, Crude_P = cr$p,
      Model1_HR = m1$hr, Model1_CI = m1$ci, Model1_P = m1$p,
      Model2_HR = m2$hr, Model2_CI = m2$ci, Model2_P = m2$p,
      stringsAsFactors = FALSE
    )
  }

  trend_cr <- .fit_group_trend(analysis_data, time_var, event_var, analysis_data$Group)
  trend_m1 <- .fit_group_trend(analysis_data, time_var, event_var, analysis_data$Group, final_model1_covariates)
  trend_m2 <- .fit_group_trend(analysis_data, time_var, event_var, analysis_data$Group,
                               c(final_model1_covariates, final_model2_covariates))
  rows[[length(rows) + 1]] <- data.frame(
    Characteristic = "p for trend",
    Exposure_cutoff = "",
    Case_pct = "",
    Crude_HR = "", Crude_CI = "", Crude_P = trend_cr,
    Model1_HR = "", Model1_CI = "", Model1_P = trend_m1,
    Model2_HR = "", Model2_CI = "", Model2_P = trend_m2,
    stringsAsFactors = FALSE
  )

  hr_table <- do.call(rbind, rows)

  index_name <- cfg$logistic$index_var %||% index_var
  disease_name <- cfg$project$disease %||% "Disease"

  assoc_pub <- pub_paths(
    ctx, ctx$output_dir_tables, "main_table",
    paste0("The Association Between ", index_name, " and ", disease_name),
    "xlsx"
  )
  model1_note <- if (length(final_model1_covariates) > 0) {
    paste(final_model1_covariates, collapse = ", ")
  } else {
    "None"
  }
  model1_note <- gsub("_", " ", model1_note, fixed = TRUE)
  model2_only_note <- if (length(final_model2_covariates) > 0) {
    paste(gsub("_", " ", final_model2_covariates, fixed = TRUE), collapse = ", ")
  } else {
    "None"
  }

  # 模型说明：导出为表下脚注（.tex / .xlsx 与 Table 1 一致），不写入 tabular 表体
  cox_table_footnotes <- c(
    "Crude Model was non-adjusted;",
    paste0("Model 1 was adjusted by: ", model1_note),
    paste0("Model 2 was adjusted by: ", model1_note, ", ", model2_only_note)
  )
  note_rows <- as.data.frame(
    matrix("", nrow = 3L, ncol = ncol(hr_table)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  colnames(note_rows) <- colnames(hr_table)
  note_rows[[1]] <- cox_table_footnotes
  ctx$results$cox_hr <- rbind(hr_table, note_rows)

  cox_header_row1 <- c(
    "Characteristic", "Exposure cutoff", "N (%)",
    "Crude Model", NA_character_, NA_character_,
    "Model 1", NA_character_, NA_character_,
    "Model 2", NA_character_, NA_character_
  )
  cox_header_row2 <- c(
    "", "", "",
    "HR", "95%CI", "P Value",
    "HR", "95%CI", "P Value",
    "HR", "95%CI", "P Value"
  )

  tryCatch({
    export_sci_table(
      hr_table, assoc_pub$filepath, title = assoc_pub$title,
      header_row1 = cox_header_row1,
      header_row2 = cox_header_row2,
      latex_include_colnames = FALSE,
      latex_align = "lllccccccccc",
      table_footnotes = cox_table_footnotes
    )
    cli::cli_alert_success("Table saved: {.file {basename(assoc_pub$filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("Excel export failed: {e$message}")
  })

  if (length(vif_all) > 0) {
    vif_df <- do.call(rbind, lapply(names(vif_all), function(mn) {
      df <- vif_all[[mn]]
      if (is.null(df)) return(NULL)
      cbind(Model = mn, df, stringsAsFactors = FALSE)
    }))
    if (!is.null(vif_df)) {
      vif_path <- file.path(ctx$output_dir, "VIF_check_Cox.csv")
      write.csv(vif_df, vif_path, row.names = FALSE)
      cli::cli_alert_success("VIF check saved: VIF_check_Cox.csv")
    }
  }

  ctx$results$cox_models <- list(
    crude = crude_fit,
    model1 = model1_fit,
    model2 = model2_fit,
    crude_res = crude_res,
    model1_res = model1_res,
    model2_res = model2_res,
    selected_grouping = selected_grouping,
    model1_vars = m1_vars,
    model2_vars = m2_vars
  )
  ctx$results$cox_grouping <- list(
    method = selected_grouping,
    n_groups = n_groups,
    group_levels = group_levels,
    predefined_group_var = predefined_group_var
  )
  
  ctx$results$cox_model1_covariates <- final_model1_covariates
  ctx$results$cox_model2_covariates <- final_model2_covariates
  
  cli::cli_alert_success("Selected grouping method: {selected_grouping} ({n_groups} groups)")
  cli::cli_alert_success("Model1 covariates saved: {paste(final_model1_covariates, collapse=', ')}")
  cli::cli_alert_success("Model2 covariates saved: {paste(final_model2_covariates, collapse=', ')}")

  cli::cli_alert_success("Cox regression completed")

  ctx
}

register_block("COX", block_COX,
               "Multi-model Cox: auto quartile/tertile/median, manual n-groups, or predefined group column")
