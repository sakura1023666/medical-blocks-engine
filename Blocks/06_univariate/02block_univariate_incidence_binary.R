###############################################################################
#  univariate_incidence_binary — 发病二分类单因素 Logistic OR（Table S2a）。
#
#  register_block: "univariate_incidence_binary"
#  典型流水线: incidence + 非 NHANES；二分类结局；下游 multivariate_incidence_binary
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data  = ctx$data$imputed %||% ctx$data$cleaned
#  require_study = incidence；classification_mode 为 binary
#
#  # ── 配置 config$univariate_incidence_binary ───────────────────────────────
#  sig_cutoff（必填）、pause_*、导出表名、排除列等
#
#  写: univar_coef；块内 bl_cfg <- cfg$univariate_incidence_binary
###############################################################################

.uvi02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.uvi02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "univariate_incidence_binary", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / 发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。", call. = FALSE)
}
.uvi02_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff %||% bl_cfg$p_threshold
  if (is.null(cutoff)) .uvi02_pause(ctx, "未配置 sig_cutoff", "在 config$univariate_incidence_binary 设置 sig_cutoff", NULL)
  as.numeric(cutoff)[1L]
}



.uvi02_extract_base_varname <- function(var_names, all_vars) {
  base_names <- vapply(var_names, function(vn) {
    for (av in all_vars[order(-nchar(all_vars))]) {
      if (vn == av) return(av)
      if (startsWith(vn, av)) return(av)
      pattern <- paste0("^", av, "\\d*$")
      if (grepl(pattern, vn, perl = TRUE)) return(av)
    }
    vn
  }, character(1L), USE.NAMES = FALSE)
  unique(base_names)
}

.univariate_incidence_binary_export_table_s2a <- function(
    ctx, cfg, uv_cfg, data, predictor_vars, univar_df, tb1,
    study_type, classification_mode) {
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  disc_n <- uv_cfg$discrete_max_levels %||% 5L
  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .uvi02_extract_base_varname(c(vn), predictor_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  uni_slice <- univar_df
  pred_tbl_ix <- as.character((cfg$prediction %||% list())$index_vars %||% character(0))
  pred_tbl_ix <- unique(pred_tbl_ix[nzchar(pred_tbl_ix)])
  keep_ix_row <- isTRUE((cfg$prediction %||% list())$keep_index_vars_in_regression_table %||% TRUE)
  if (keep_ix_row && length(pred_tbl_ix) && any(row_base %in% pred_tbl_ix)) {
    add_ix <- univar_df[row_base %in% pred_tbl_ix, , drop = FALSE]
    if (nrow(add_ix) > 0L) {
      uni_slice <- rbind(uni_slice, add_ix)
      dup_k <- if ("Group" %in% names(uni_slice)) {
        paste0(uni_slice$Variable, "\x01", uni_slice$Group)
      } else {
        as.character(uni_slice$Variable)
      }
      uni_slice <- uni_slice[!duplicated(dup_k, fromLast = FALSE), , drop = FALSE]
    }
  }
  .fmt_p_inline <- function(p) {
    if (length(p) != 1L || is.na(p)) return("")
    p <- as.numeric(p)
    if (p < 0.001) return("p<0.001")
    paste0("p=", formatC(round(p, 3), format = "f", digits = 3))
  }
  .fmt_ci_p <- function(est, lo, hi, p) {
    if (length(est) != 1L || is.na(est)) return("")
    pt <- .fmt_p_inline(p)
    if (is.na(lo) || is.na(hi)) {
      if (!nzchar(pt)) return(paste0(fmt_num(est)))
      return(paste0(fmt_num(est), " (", pt, ")"))
    }
    if (!nzchar(pt)) {
      return(paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ")"))
    }
    paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ", ", pt, ")")
  }
  if (study_type == "prognosis") {
    est_col <- uni_slice$HR
    lab_uni <- "HR (univariable)"
    base_title <- paste0("Cox Regression Analysis of ", cfg$project$disease)
  } else if (identical(classification_mode, "binary")) {
    est_col <- uni_slice$OR
    lab_uni <- "OR (univariable)"
    base_title <- paste0("Logistic Regression Analysis of ", cfg$project$disease)
  } else {
    est_col <- if ("OR" %in% names(uni_slice)) uni_slice$OR else rep(NA_real_, nrow(uni_slice))
    lab_uni <- "OR (univariable)"
    base_title <- paste0("Multinomial Logistic Regression Analysis of ", cfg$project$disease)
  }
  bases <- unique(row_base[row_base %in% names(data)])
  bases <- setdiff(bases, c("Group", "group"))
  bases <- order_vars_like_table1(bases, ctx, cfg, data)
  pub_rows <- list()
  for (bv in bases) {
    x <- data[[bv]]
    lab_char <- gsub("_", " ", bv)
    sub_u <- uni_slice[row_base == bv, , drop = FALSE]
    is_cont <- (bv %in% force_continuous_vars) ||
      (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)
    if (is_cont) {
      normal_vars <- ctx$results$normal_vars %||% character(0)
      if (bv %in% normal_vars) {
        stat_label <- "Mean \u00b1 SD"
        stat_val <- paste0(fmt_num(mean(x, na.rm = TRUE)),
                           " \u00b1 ",
                           fmt_num(stats::sd(x, na.rm = TRUE)))
      } else {
        stat_label <- "Median (Q1, Q3)"
        stat_val <- paste0(
          fmt_num(stats::median(x, na.rm = TRUE)), " (",
          fmt_num(stats::quantile(x, 0.25, na.rm = TRUE)), ", ",
          fmt_num(stats::quantile(x, 0.75, na.rm = TRUE)), ")")
      }
      mr <- sub_u[sub_u$Variable == bv, , drop = FALSE]
      if (nrow(mr) == 0L && nrow(sub_u)) mr <- sub_u[1L, , drop = FALSE]
      u1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr[[if ("HR" %in% names(mr)) "HR" else "OR"]][1],
        mr$CI_lo[1], mr$CI_hi[1], mr$P[1]) else ""
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char, Statistic = stat_label,
        all = stat_val,
        U1 = u1, stringsAsFactors = FALSE)
    } else {
      xf <- factor(x)
      lv <- levels(xf)
      if (!length(lv)) next
      n_tot <- sum(!is.na(x))
      ref <- lv[1L]
      n0 <- sum(xf == ref, na.rm = TRUE)
      pct0 <- if (n_tot > 0) n0 / n_tot * 100 else 0
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char, Statistic = as.character(ref),
        all = paste0(n0, " (", fmt_num(pct0), "%)"), U1 = "", stringsAsFactors = FALSE)
      if (length(lv) > 1L) {
        for (k in seq_len(length(lv))[-1L]) {
          lev <- lv[k]
          nk <- sum(xf == lev, na.rm = TRUE)
          pctk <- if (n_tot > 0) nk / n_tot * 100 else 0
          mr <- sub_u[sub_u$Variable == paste0(bv, lev), , drop = FALSE]
          if (nrow(mr) == 0L) mr <- sub_u[grepl(lev, sub_u$Variable, fixed = TRUE), , drop = FALSE]
          if (nrow(mr) > 1L) mr <- mr[1L, , drop = FALSE]
          u1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr[[if ("HR" %in% names(mr)) "HR" else "OR"]][1],
            mr$CI_lo[1], mr$CI_hi[1], mr$P[1]) else ""
          pub_rows[[length(pub_rows) + 1L]] <- data.frame(
            Characteristic = "", Statistic = as.character(lev),
            all = paste0(nk, " (", fmt_num(pctk), "%)"), U1 = u1, stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(pub_rows)) {
    cli::cli_alert_warning("Table S2a 发表用表格行为空")
    return(invisible(FALSE))
  }
  out_table <- do.call(rbind, pub_rows)
  names(out_table)[names(out_table) == "U1"] <- lab_uni
  pub_uv <- pub_pair(
    ctx, ctx$output_dir_tables, "supp_table",
    base_title, "Univariate Regression Analysis", "xlsx"
  )
  tryCatch(
    export_sci_table(out_table, pub_uv$filepath, title = pub_uv$title),
    error = function(e) cli::cli_alert_warning("Table S2a 导出失败: {e$message}")
  )
  invisible(TRUE)
}



block_univariate_incidence_binary <- function(ctx, ...) {
  suppressPackageStartupMessages({
    # glm in stats
  })

  cfg           <- ctx$config
  bl_cfg        <- cfg$univariate_incidence_binary %||% list()
  uv_cfg        <- bl_cfg
  slot          <- bl_cfg$data_slot %||% "imputed"
  source_tag    <- slot
  if (identical(slot, "train")) {
    if (is.data.frame(ctx$data$train) && nrow(ctx$data$train) > 0L) {
      data <- ctx$data$train
    } else {
      cli::cli_alert_warning(
        "univariate_incidence_binary: data_slot=train but train missing/empty, falling back to imputed"
      )
      data <- ctx$data$imputed %||% ctx$data$cleaned
      source_tag <- "imputed"
    }
  } else {
    data <- ctx$data$imputed %||% ctx$data$cleaned
    source_tag <- "imputed"
  }
  if (tolower(ctx$config$project$study_type %||% "") != "incidence") stop("需要 study_type=incidence")
  if (!identical(ctx$config$project$classification_mode %||% "binary", "binary")) stop("需要 classification_mode=binary；NHANES 请用 univariate_nhanes")
  if (.is_nhanes_db(ctx$config)) stop("NHANES 库请只运行 univariate_nhanes，不要运行 univariate_incidence_binary")
  if (is.null(data) || !is.data.frame(data)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
    data <- pipeline_ensure_outcome_group_column(data, cfg)
  }
  if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
    data <- pipeline_relabel_binary_outcome_column(data, cfg)
  }
  outcome_col   <- cfg$data$outcome_column    %||% "Disease"
  study_type_uv <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (identical(study_type_uv, "incidence")) {
    outcome_col <- as.character((cfg$incidence %||% list())$outcome_var %||% outcome_col)[1L]
  } else {
    outcome_col <- as.character((cfg$survival %||% list())$event_var %||% outcome_col)[1L]
  }
  if (identical(source_tag, "train") &&
      "Group" %in% names(data) && !outcome_col %in% names(data)) {
    data[[outcome_col]] <- data[["Group"]]
  }
  if (exists("pipeline_drop_mi_quality_cols", mode = "function")) {
    data <- pipeline_drop_mi_quality_cols(data, ctx)
  }
  up_res        <- list(data = data, source = source_tag, outcome_col = outcome_col)
  if (exists("pipeline_population_audit", mode = "function")) {
    ctx <- pipeline_population_audit(
      ctx, "univariate_incidence_binary", data,
      note = paste0(
        "Univariate logistic uses source=", up_res$source %||% "unknown",
        " (n=", nrow(data), "); may differ from outcome-strata baseline n"
      )
    )
  }
  cli::cli_alert_info(
    "univariate_incidence_binary: 分析队列 source={up_res$source %||% 'unknown'}, n={nrow(data)}（Logistic OR）"
  )
  p_threshold   <- .uvi02_resolve_sig_cutoff(bl_cfg, ctx)
  excluded_predictors <- unique(c(
    as.character(uv_cfg$excluded_predictors %||% character(0)),
    if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
      pipeline_covariate_analysis_exclude_vars(cfg)
    } else {
      character(0)
    }
  ))
  idx_keep <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% character(0)
  )[1L]
  if (length(idx_keep) && nzchar(idx_keep)) {
    excluded_predictors <- setdiff(excluded_predictors, idx_keep)
  }

  required_predictors_cfg <- uv_cfg$required_predictors %||% character(0)
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  demo_keywords <- uv_cfg$demo_keywords       %||% c("age", "gender", "sex", "race", "ethnicity",
                                                      "education", "edu", "marital", "marriage",
                                                      "income", "pir", "poverty",
                                                      "bmi", "weight", "height",
                                                      "smoke", "alcohol", "drink", "language")

  classification_mode <- cfg$project$classification_mode %||% "binary"
  reference_group <- cfg$project$reference_group
  study_type <- "incidence"

  id_col <- cfg$data$id_column %||% NULL
  strip_id_cfg <- as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0))
  strip_here <- unique(c(as.character(id_col %||% character(0)), strip_id_cfg))
  strip_here <- strip_here[nzchar(strip_here) & strip_here %in% names(data)]
  if (length(strip_here)) {
    data <- data[, setdiff(names(data), strip_here), drop = FALSE]
    cli::cli_alert_info("已从分析用数据中移除 ID 类列: {paste(strip_here, collapse = ', ')}")
  }

  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"

  predictor_vars <- setdiff(names(data), outcome_col)
  meta_drop <- unique(c(
    "Group", "group",
    as.character(cfg$data$id_column %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0))
  ))
  meta_drop <- meta_drop[nzchar(meta_drop)]
  predictor_vars <- setdiff(predictor_vars, meta_drop)
  # 业务限定：文献不建议作为结局协变量的指标，从本步骤起即不参与后续分析
  excluded_predictors <- intersect(excluded_predictors, names(data))
  predictor_vars <- setdiff(predictor_vars, excluded_predictors)
  if (length(idx_keep) && nzchar(idx_keep) && idx_keep %in% names(data)) {
    predictor_vars <- unique(c(predictor_vars, idx_keep))
  }
  if (length(excluded_predictors) > 0) {
    cli::cli_alert_info("按配置排除协变量: {paste(excluded_predictors, collapse = ', ')}")
  }
  # 仅基线表特征（baseline_binary$include_vars / cross_lagged 统一 Table 1）
  if (exists("pipeline_apply_include_predictors", mode = "function")) {
    predictor_vars <- pipeline_apply_include_predictors(
      cfg, predictor_vars, names(data), label = "单因素候选"
    )
  }
  if (length(idx_keep) && nzchar(idx_keep) && idx_keep %in% names(data)) {
    predictor_vars <- unique(c(predictor_vars, idx_keep))
  }

  force_continuous_vars <- intersect(force_continuous_vars, predictor_vars)
  if (length(force_continuous_vars) > 0) {
    .coerce_force_continuous <- function(x) {
      if (is.numeric(x)) return(as.numeric(x))
      x_num <- suppressWarnings(as.numeric(as.character(x)))
      if (sum(!is.na(x_num)) > 0) return(x_num)
      suppressWarnings(as.numeric(factor(x)))
    }
    for (v in force_continuous_vars) {
      data[[v]] <- .coerce_force_continuous(data[[v]])
    }
    cli::cli_alert_info("强制按连续变量处理: {paste(force_continuous_vars, collapse = ', ')}")
  }

  # 核心指标尺度变换（仅本块内用于回归的 data 副本，不写回 ctx$data）
  idx_transform <- tolower(trimws(as.character(uv_cfg$index_transform %||% "none")))
  idx_var_uv <- if (study_type == "prognosis") {
    surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  } else {
    (cfg$logistic %||% list())$index_var %||% surv_cfg$index_var
  }
  idx_var_uv <- as.character(idx_var_uv)[1L]
  uv_index_transform_applied <- NULL
  if (nzchar(idx_transform) && !identical(idx_transform, "none") && nzchar(idx_var_uv)) {
    if (idx_var_uv %in% names(data)) {
      .coerce_index_numeric <- function(x) {
        if (is.numeric(x)) return(as.numeric(x))
        x_num <- suppressWarnings(as.numeric(as.character(x)))
        if (sum(!is.na(x_num)) > 0) return(x_num)
        suppressWarnings(as.numeric(factor(x)))
      }
      xv <- .coerce_index_numeric(data[[idx_var_uv]])
      if (idx_transform == "log") {
        ok <- !is.na(xv) & xv > 0
        if (!all(ok | is.na(xv))) {
          stop(
            "univariate_incidence_binary: index_transform='log' 要求 ", idx_var_uv, " 全部非缺失值 >0；",
            "当前存在 <=0 或非数值。可改用 index_transform='log1p' 或先清洗数据。"
          )
        }
        data[[idx_var_uv]] <- log(xv)
        uv_index_transform_applied <- list(variable = idx_var_uv, method = "log")
        cli::cli_alert_info("已对核心指标 {idx_var_uv} 作 log 变换（单因素回归用）")
      } else if (idx_transform == "log1p") {
        ok <- !is.na(xv) & xv > -1
        if (!all(ok | is.na(xv))) {
          stop(
            "univariate_incidence_binary: index_transform='log1p' 要求 ", idx_var_uv, " > -1（非缺失）"
          )
        }
        data[[idx_var_uv]] <- log1p(xv)
        uv_index_transform_applied <- list(variable = idx_var_uv, method = "log1p")
        cli::cli_alert_info("已对核心指标 {idx_var_uv} 作 log1p 变换（单因素回归用）")
      } else if (idx_transform %in% c("scale", "standardize", "zscore", "z")) {
        m <- mean(xv, na.rm = TRUE)
        s <- stats::sd(xv, na.rm = TRUE)
        if (!is.finite(m) || !is.finite(s) || s == 0) {
          stop(
            "univariate_incidence_binary: index_transform='scale' 需要 ", idx_var_uv,
            " 在非缺失样本上 sd>0"
          )
        }
        data[[idx_var_uv]] <- as.numeric((xv - m) / s)
        uv_index_transform_applied <- list(
          variable = idx_var_uv, method = "scale", center = m, scale = s
        )
        cli::cli_alert_info(
          "已对核心指标 {idx_var_uv} 作标准化 (mean={round(m, 6)}, sd={round(s, 6)})（单因素回归用）"
        )
      } else {
        cli::cli_alert_warning(
          "未知 index_transform='{idx_transform}'，已忽略。可选: none, log, log1p, scale"
        )
      }
    } else {
      cli::cli_alert_warning(
        "配置了 index_transform 但 index 列不在数据中: {idx_var_uv}，已跳过变换"
      )
    }
  }

  cli::cli_alert_info("候选变量数量: {length(predictor_vars)}")
  cli::cli_alert_info("研究类型: {study_type} ({if (study_type == 'prognosis') 'Cox HR' else 'Logistic OR'})")
  if (study_type == "incidence") cli::cli_alert_info("结局变量: {outcome_col}")
  if (study_type == "prognosis") cli::cli_alert_info("生存: Surv({time_var}, {event_var})")
  cli::cli_alert_info("分类模式: {classification_mode}")
  cli::cli_alert_info("显著性阈值: P < {p_threshold}")

  .run_univariate_binary <- function(var, data, outcome_col, disease_label) {
    fml <- as.formula(paste0(outcome_col, " ~ ", var))
    fit <- tryCatch(
      glm(fml, data = data, family = "binomial"),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)

    smry <- summary(fit)$coefficients
    ci   <- tryCatch(exp(confint.default(fit)), error = function(e) NULL)
    rns  <- rownames(smry)[rownames(smry) != "(Intercept)"]

    results <- lapply(rns, function(rn) {
      data.frame(
        Variable = rn,
        OR       = exp(smry[rn, "Estimate"]),
        CI_lo    = if (!is.null(ci)) ci[rn, 1] else NA_real_,
        CI_hi    = if (!is.null(ci)) ci[rn, 2] else NA_real_,
        P        = smry[rn, "Pr(>|z|)"],
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, results)
  }

  .run_univariate_multinomial <- function(var, data, outcome_col, reference_group) {
    data[[outcome_col]] <- factor(data[[outcome_col]])
    data[[outcome_col]] <- relevel(data[[outcome_col]], ref = reference_group)
    
    fml <- as.formula(paste0(outcome_col, " ~ ", var))
    fit <- tryCatch(
      multinom(fml, data = data, trace = FALSE),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)

    smry <- summary(fit)$coefficients
    se   <- summary(fit)$standard.errors
    z    <- smry / se
    p    <- 2 * (1 - pnorm(abs(z)))
    
    ci_lo <- exp(smry - 1.96 * se)
    ci_hi <- exp(smry + 1.96 * se)
    or    <- exp(smry)
    
    results <- list()
    for (i in 1:nrow(smry)) {
      group_name <- rownames(smry)[i]
      for (j in 1:ncol(smry)) {
        var_name <- colnames(smry)[j]
        if (var_name == "(Intercept)") next
        
        results[[length(results) + 1]] <- data.frame(
          Variable = var_name,
          Group = group_name,
          OR = or[i, j],
          CI_lo = ci_lo[i, j],
          CI_hi = ci_hi[i, j],
          P = p[i, j],
          stringsAsFactors = FALSE
        )
      }
    }
    do.call(rbind, results)
  }



  .run_univariate_cox <- function(var, data, time_var, event_var) {
    fml <- as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", var))
    fit <- tryCatch(
      survival::coxph(fml, data = data),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)
    s <- summary(fit)
    co <- s$coefficients
    nm <- rownames(co)
    if (is.null(nm) || length(nm) == 0) return(NULL)
    if (!is.null(s$conf.int) && nrow(s$conf.int) == length(nm)) {
      hr <- s$conf.int[, "exp(coef)", drop = TRUE]
      lo <- s$conf.int[, "lower .95", drop = TRUE]
      hi <- s$conf.int[, "upper .95", drop = TRUE]
    } else {
      se <- co[, "se(coef)", drop = TRUE]
      est <- co[, "coef", drop = TRUE]
      hr <- exp(est)
      lo <- exp(est - 1.96 * se)
      hi <- exp(est + 1.96 * se)
    }
    data.frame(
      Variable = nm,
      HR       = as.numeric(hr),
      CI_lo    = as.numeric(lo),
      CI_hi    = as.numeric(hi),
      P        = as.numeric(co[, "Pr(>|z|)", drop = TRUE]),
      stringsAsFactors = FALSE
    )
  }


  .extract_base_varname <- .uvi02_extract_base_varname


  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  cli::cli_alert_info("阳性标签: {disease_label}")
  data[[outcome_col]] <- as.integer(data[[outcome_col]] == disease_label)
  cli::cli_h2("单因素回归分析 (二分类 Logistic, OR)")
  univar_results <- list()
  pb <- cli::cli_progress_bar("Univariate", total = length(predictor_vars))
  for (var in predictor_vars) {
    res <- .run_univariate_binary(var, data, outcome_col, disease_label)
    if (!is.null(res)) univar_results[[var]] <- res
    cli::cli_progress_update(id = pb)
  }
  cli::cli_progress_done(id = pb)
  univar_df <- if (length(univar_results)) { x <- do.call(rbind, univar_results); rownames(x) <- NULL; x } else NULL
  tb1 <- character(0)
  tb_screen <- character(0)
  if (!is.null(univar_df) && nrow(univar_df) > 0) {
    tb1 <- .extract_base_varname(univar_df$Variable[univar_df$P < p_threshold], predictor_vars)
    screening_cutoff <- as.numeric(uv_cfg$screening_cutoff %||% uv_cfg$p_threshold %||% 0.1)[1L]
    tb_screen <- .extract_base_varname(univar_df$Variable[univar_df$P < screening_cutoff], predictor_vars)
  }
  cli::cli_alert_success("单因素显著变量 tb1 (P < {p_threshold}): {length(tb1)} 个")
  screening_cutoff <- as.numeric(uv_cfg$screening_cutoff %||% uv_cfg$p_threshold %||% 0.1)[1L]
  cli::cli_alert_success("VIF screening 候选 tb_screen (P < {screening_cutoff}): {length(tb_screen)} 个")

  if (length(tb1) == 0) {
    snap <- if (!is.null(univar_df) && nrow(univar_df) > 0) utils::head(univar_df, 5) else NULL
    suggestion <- paste0(
      "请检查数据或放宽 config$univariate_incidence_binary$sig_cutoff (当前: ",
      p_threshold, ")"
    )
    if (.uvi02_should_pause(uv_cfg, "pause_on_no_significant", TRUE)) {
      ctx$results$pause_point <- list(
        block = "univariate_incidence_binary",
        reason = "未找到单因素显著变量",
        suggestion = suggestion,
        data_snapshot = snap
      )
      stop("PAUSE_FOR_USER_DECISION: 未找到单因素显著变量，请查看 ctx$results$pause_point。")
    }
    cli::cli_alert_warning(
      "未找到单因素显著变量（pause_enable=FALSE，继续；tb1 为空）。{suggestion}"
    )
  }

  cli::cli_h2("保存单因素结果")
  ctx <- save_result(ctx, "tb1_univar_features", tb1, "D06_Univariable_Features.RData")
  ctx <- save_result(ctx, "tb_screen_univar_features", tb_screen, "D06b_Univariable_Screen_Features.RData")
  ctx$results$tb1 <- tb1
  ctx$results$tb_screen <- tb_screen
  ctx$results$univar_features <- tb_screen
  ctx$results$univar_coef <- univar_df
  ctx$results$univariate_index_transform <- uv_index_transform_applied
  ctx$results$univar_pvalues <- if (!is.null(univar_df) && nrow(univar_df) > 0) {
    setNames(univar_df$P, univar_df$Variable)
  } else {
    NULL
  }
  ctx$results$univariate_study_type <- study_type

  if (!is.null(univar_df) && nrow(univar_df) > 0) {
    .univariate_incidence_binary_export_table_s2a(ctx, cfg, uv_cfg, data, predictor_vars, univar_df, tb1, study_type, classification_mode)
  }

  cli::cli_alert_success("单因素分析完成（仅单因素）")
  ctx
}

register_block(
  "univariate_incidence_binary",
  block_univariate_incidence_binary,
  "univariate_incidence_binary（发病二分类单因素 Logistic）"
)