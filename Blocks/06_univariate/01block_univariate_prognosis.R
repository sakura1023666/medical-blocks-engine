###############################################################################
#  univariate_prognosis — 预后单因素 Cox：输出 Table S2a 风格 HR 表 + univar_coef。
#
#  register_block: "univariate_prognosis"
#  典型流水线: imputation 后；study_type=prognosis；供 multivariate_prognosis 读 univar_coef
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data  = ctx$data$imputed %||% ctx$data$cleaned
#  require_study = project$study_type == "prognosis"
#
#  # ── 配置 config$univariate_prognosis（必配 sig_cutoff）────────────────────
#  sig_cutoff / p_threshold、pause_enable、pause_on_*、exclude_vars、table 导出文件名等
#
#  # ── 读写 ctx ─────────────────────────────────────────────────────────────
#  写: ctx$results$univar_coef、tb1 等；Tables/Table S2a*.xlsx
#  块内 bl_cfg <- cfg$univariate_prognosis
###############################################################################

.uvp01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.uvp01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "univariate_prognosis", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / 发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。", call. = FALSE)
}
.uvp01_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff %||% bl_cfg$p_threshold
  if (is.null(cutoff)) .uvp01_pause(ctx, "未配置 sig_cutoff", "在 config$univariate_prognosis 设置 sig_cutoff", NULL)
  as.numeric(cutoff)[1L]
}

.uvp01_extract_base_varname <- function(var_names, all_vars) {
  var_names <- as.character(var_names)
  var_names <- var_names[!is.na(var_names) & nzchar(var_names)]
  if (!length(var_names)) return(character(0))
  base_names <- vapply(var_names, function(vn) {
    if (is.na(vn) || !nzchar(vn)) return(NA_character_)
    for (av in all_vars[order(-nchar(all_vars))]) {
      if (is.na(av) || !nzchar(av)) next
      if (identical(vn, av)) return(av)
      if (startsWith(vn, av)) return(av)
      pattern <- paste0("^", av, "\\d*$")
      if (grepl(pattern, vn, perl = TRUE)) return(av)
    }
    vn
  }, character(1L), USE.NAMES = FALSE)
  unique(base_names[!is.na(base_names) & nzchar(base_names)])
}


.univariate_prognosis_export_table_s2a <- function(
    ctx, cfg, uv_cfg, data, predictor_vars, univar_df, tb1,
    study_type, classification_mode) {
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  disc_n <- uv_cfg$discrete_max_levels %||% 5L
  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .uvp01_extract_base_varname(c(vn), predictor_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  uni_slice <- univar_df
  pred_tbl_ix <- as.character((cfg$prediction %||% list())$index_vars %||% character(0))
  # 预后暴露指标默认进 Table S2（即使在 excluded_predictors 里用于筛协变量）
  ix_keep <- unique(c(
    pred_tbl_ix,
    as.character((cfg$survival %||% list())$index_var %||% ""),
    as.character((cfg$competing_risk %||% list())$index_var %||% ""),
    as.character((cfg$incidence %||% list())$index_var %||% "")
  ))
  ix_keep <- ix_keep[nzchar(ix_keep)]
  keep_ix_row <- isTRUE((cfg$prediction %||% list())$keep_index_vars_in_regression_table %||% TRUE)
  if (keep_ix_row && length(ix_keep)) {
    # 确保导出循环能看到暴露列
    bases_extra <- intersect(ix_keep, names(data))
    if (length(bases_extra)) {
      # 若 univar 已含则保留；否则仅描述+提示（HR 需在拟合阶段纳入）
      miss_fit <- setdiff(bases_extra, unique(row_base))
      if (length(miss_fit) && nrow(univar_df)) {
        # 尝试从完整 univar_df 再捞（Variable 恰为指标名）
        add_ix <- univar_df[univar_df$Variable %in% bases_extra | row_base %in% bases_extra, , drop = FALSE]
        if (nrow(add_ix) > 0L) {
          uni_slice <- rbind(uni_slice, add_ix)
        }
      }
    }
  }
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
  } else if (identical(classification_mode, "binary")) {
    est_col <- uni_slice$OR
    lab_uni <- "OR (univariable)"
  } else {
    est_col <- if ("OR" %in% names(uni_slice)) uni_slice$OR else rep(NA_real_, nrow(uni_slice))
    lab_uni <- "OR (univariable)"
  }
  base_title <- if (study_type == "prognosis") {
    "Univariate Cox regression analysis"
  } else if (identical(classification_mode, "binary")) {
    "Univariate logistic regression analysis"
  } else {
    "Univariate multinomial logistic regression analysis"
  }
  # 旧逻辑用 disease 拼标题易不规范；允许 config 覆盖
  base_title <- as.character(uv_cfg$table_s2_title %||% base_title)[1L]
  bases <- unique(c(
    intersect(ix_keep, names(data)),
    row_base[row_base %in% names(data)]
  ))
  bases <- if (exists("order_vars_like_table1", mode = "function") &&
               length(ctx$results$table1_var_order %||% character(0))) {
    order_vars_like_table1(bases, ctx, cfg, data)
  } else {
    sort_univariate_table_vars(bases, cfg, names(data))
  }
  pub_rows <- list()
  for (bv in bases) {
    x <- data[[bv]]
    lab_char <- gsub("_", " ", bv)
    if (exists("pipeline_cox_unit_scale", mode = "function") && bv %in% names(data)) {
      sc_lab <- pipeline_cox_unit_scale(bv, data[[bv]])
      if (!identical(sc_lab$scale, 1)) {
        lab_char <- paste0(lab_char, " (", sc_lab$label, ")")
      }
    }
    sub_u <- uni_slice[row_base == bv, , drop = FALSE]
    is_cont <- (bv %in% force_continuous_vars) ||
      (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)
    if (is_cont) {
      use_median <- isTRUE(uv_cfg$table_s2_use_median_iqr %||% TRUE)
      if (use_median) {
        qs <- stats::quantile(x, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE)
        stat_lab <- "Median (Q1, Q3)"
        all_lab <- paste0(fmt_num(qs[2]), " (", fmt_num(qs[1]), ", ", fmt_num(qs[3]), ")")
      } else {
        mu <- mean(x, na.rm = TRUE)
        sg <- stats::sd(x, na.rm = TRUE)
        stat_lab <- "Mean \u00b1 SD"
        all_lab <- paste0(fmt_num(mu), " \u00b1 ", fmt_num(sg))
      }
      mr <- sub_u[sub_u$Variable == bv, , drop = FALSE]
      if (nrow(mr) == 0L && nrow(sub_u)) mr <- sub_u[1L, , drop = FALSE]
      u1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr[[if ("HR" %in% names(mr)) "HR" else "OR"]][1],
        mr$CI_lo[1], mr$CI_hi[1], mr$P[1]) else ""
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char, Statistic = stat_lab,
        all = all_lab,
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
          if (nrow(mr) == 0L && "Group" %in% names(sub_u)) {
            mr <- sub_u[as.character(sub_u$Group) == as.character(lev), , drop = FALSE]
          }
          if (nrow(mr) == 0L) {
            mr <- sub_u[grepl(paste0("^", bv, ".*", lev, "$"), sub_u$Variable), , drop = FALSE]
          }
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



block_univariate_prognosis <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
  })

  cfg           <- ctx$config
  up_res        <- pipeline_upstream_modeling_data(ctx)
  data          <- up_res$data
  if (tolower(ctx$config$project$study_type %||% "") != "prognosis") stop("univariate_prognosis 需要 study_type=prognosis")
  if (is.null(data)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  if (exists("pipeline_population_audit", mode = "function")) {
    ctx <- pipeline_population_audit(
      ctx, "univariate_prognosis", data,
      note = paste0(
        "Univariate Cox uses source=", up_res$source %||% "unknown",
        " (n=", nrow(data), "); may differ from outcome-strata baseline n"
      )
    )
  }
  cli::cli_alert_info(
    "univariate_prognosis: 分析队列 source={up_res$source %||% 'unknown'}, n={nrow(data)}（Cox HR）"
  )

  outcome_col   <- cfg$data$outcome_column    %||% "Disease"
  bl_cfg        <- cfg$univariate_prognosis %||% list()
  uv_cfg        <- bl_cfg
  p_threshold   <- .uvp01_resolve_sig_cutoff(bl_cfg, ctx)
  screening_cutoff <- as.numeric(bl_cfg$screening_cutoff %||% bl_cfg$vif_screen_cutoff %||% 0.1)[1L]
  if (is.na(screening_cutoff)) screening_cutoff <- 0.1
  excluded_predictors <- uv_cfg$excluded_predictors %||% character(0)

  required_predictors_cfg <- uv_cfg$required_predictors %||% character(0)
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  demo_keywords <- uv_cfg$demo_keywords       %||% c("age", "gender", "sex", "race", "ethnicity",
                                                      "education", "edu", "marital", "marriage",
                                                      "income", "pir", "poverty",
                                                      "bmi", "weight", "height",
                                                      "smoke", "alcohol", "drink", "language")

  classification_mode <- cfg$project$classification_mode %||% "binary"
  reference_group <- cfg$project$reference_group
  study_type <- "prognosis"

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

  {
    if (!time_var %in% names(data) || !event_var %in% names(data)) {
      stop("study_type='prognosis' 需要数据中存在 survival$time_var 与 survival$event_var（当前: ",
           time_var, ", ", event_var, "）")
    }
    # 预后：事件列须为 0/1（1=死亡/发生事件，0=存活/删失）。字符/因子时按配置与关键词映射
    .coerce_survival_event_01 <- function(x, cfg, evname) {
      if (is.numeric(x)) {
        if (all(is.na(x))) return(as.numeric(x))
        ux <- unique(stats::na.omit(as.numeric(x)))
        if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
        stop("prognosis: ", evname, " 为数值但非 0/1 编码，请先在数据或 config 中处理")
      }
      if (is.logical(x)) return(as.integer(x))
      xc <- trimws(as.character(x))
      ref_lbl <- trimws(cfg$project$reference_group %||% "")
      ana_lbl <- trimws(cfg$project$analysis_group %||% "")
      out <- rep(NA_integer_, length(xc))
      # analysis_group = 阳性/病例（预后里常为死亡组）→ 事件 1；reference_group = 阴性/对照（存活）→ 0
      if (nzchar(ana_lbl)) out[xc == ana_lbl] <- 1L
      if (nzchar(ref_lbl)) out[xc == ref_lbl] <- 0L
      if (nzchar(ana_lbl)) {
        hit <- tolower(xc) == tolower(ana_lbl)
        out[hit & is.na(out)] <- 1L
      }
      if (nzchar(ref_lbl)) {
        hit <- tolower(xc) == tolower(ref_lbl)
        out[hit & is.na(out)] <- 0L
      }
      unk <- is.na(out) & !is.na(xc) & nzchar(xc)
      if (any(unk)) {
        dead_kw <- c(
          "dead", "death", "died", "deceased", "non-survivor", "non survivor", "nonsurvivor",
          "non_survivor", "expire", "expired", "mortality", "fatal",
          "死亡", "死亡组", "病死", "过世"
        )
        alive_kw <- c(
          "alive", "survivor", "survive", "survived", "living", "live", "censor", "censored",
          "存活", "生存", "存活组", "生还"
        )
        xl <- tolower(xc[unk])
        is_dead <- vapply(xl, function(s) any(vapply(dead_kw, function(k) grepl(k, s, fixed = TRUE), logical(1))), logical(1))
        is_alive <- vapply(xl, function(s) any(vapply(alive_kw, function(k) grepl(k, s, fixed = TRUE), logical(1))), logical(1))
        idx <- which(unk)
        out[idx[is_dead & !is_alive]] <- 1L
        out[idx[is_alive & !is_dead]] <- 0L
      }
      bad <- is.na(out) & !is.na(xc) & nzchar(xc)
      if (any(bad)) {
        stop(
          "prognosis: 无法将 ", evname, " 映射为 0/1（死亡=1，存活=0）。",
          "未识别取值: ", paste(unique(xc[bad]), collapse = ", "),
          "。请在 config$project 设置 analysis_group / reference_group 或先把该列改为 0/1。"
        )
      }
      out[is.na(xc)] <- NA_integer_
      out
    }
    ev <- data[[event_var]]
    if (is.factor(ev) || is.character(ev)) {
      data[[event_var]] <- .coerce_survival_event_01(ev, cfg, event_var)
      cli::cli_alert_info(
        "已将 {event_var}（字符/因子）转为数值：死亡/事件=1，存活/删失=0"
      )
    } else if (is.logical(ev)) {
      data[[event_var]] <- as.integer(ev)
      cli::cli_alert_info("已将 {event_var}（逻辑型）转为 0/1 数值")
    }
    predictor_vars <- setdiff(names(data), c(time_var, event_var))
  }

  # 业务限定：文献不建议作为结局协变量的指标，从本步骤起即不参与后续分析
  excluded_predictors <- intersect(excluded_predictors, names(data))
  predictor_vars <- setdiff(predictor_vars, excluded_predictors)
  traj_class_cols <- predictor_vars[grepl("^trajectory_class(\\b|_)", predictor_vars, ignore.case = TRUE) |
                                      grepl("^trajectory_class$", predictor_vars, ignore.case = TRUE)]
  if (length(traj_class_cols)) {
    predictor_vars <- setdiff(predictor_vars, traj_class_cols)
    cli::cli_alert_info("排除潜类别列（不作协变量）: {paste(traj_class_cols, collapse = ', ')}")
  }
  if (length(excluded_predictors) > 0) {
    cli::cli_alert_info("按配置排除协变量: {paste(excluded_predictors, collapse = ', ')}")
  }
  # 暴露指标仍进单因素表（排除名单常含全部复合指标）
  ix_force <- unique(c(
    as.character((cfg$survival %||% list())$index_var %||% ""),
    as.character((cfg$competing_risk %||% list())$index_var %||% ""),
    as.character((cfg$incidence %||% list())$index_var %||% ""),
    as.character((cfg$prediction %||% list())$index_vars %||% character(0))
  ))
  ix_force <- intersect(ix_force[nzchar(ix_force)], names(data))
  if (length(ix_force) && isTRUE((cfg$prediction %||% list())$keep_index_vars_in_regression_table %||% TRUE)) {
    predictor_vars <- unique(c(ix_force, predictor_vars))
    cli::cli_alert_info("单因素保留暴露指标: {paste(ix_force, collapse = ', ')}")
  }
  if (exists("pipeline_apply_include_predictors", mode = "function")) {
    predictor_vars <- pipeline_apply_include_predictors(
      cfg, predictor_vars, names(data), label = "单因素/多因素候选"
    )
    ctx$results$dual_db_prognosis_vars <- predictor_vars
  }
  required_predictors_cfg <- as.character(required_predictors_cfg)
  required_predictors_cfg <- unique(required_predictors_cfg[nzchar(required_predictors_cfg)])
  req_in_data <- intersect(required_predictors_cfg, names(data))
  if (length(req_in_data)) {
    predictor_vars <- unique(c(predictor_vars, req_in_data))
    cli::cli_alert_info("强制纳入候选（required_predictors）: {paste(req_in_data, collapse = ', ')}")
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
            "univariate_prognosis: index_transform='log' 要求 ", idx_var_uv, " 全部非缺失值 >0；",
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
            "univariate_prognosis: index_transform='log1p' 要求 ", idx_var_uv, " > -1（非缺失）"
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
            "univariate_prognosis: index_transform='scale' 需要 ", idx_var_uv,
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
  if (FALSE) cli::cli_alert_info("结局变量: {outcome_col}")
  if (study_type == "prognosis") cli::cli_alert_info("生存: Surv({time_var}, {event_var})")
  cli::cli_alert_info("分类模式: {classification_mode}")
  cli::cli_alert_info("显著性阈值: P < {p_threshold}")

  .uvp01_bt <- function(nm) {
    paste0("`", gsub("`", "", as.character(nm)[1L], fixed = TRUE), "`")
  }

  .run_univariate_binary <- function(var, data, outcome_col, disease_label) {
    fml <- as.formula(paste0(.uvp01_bt(outcome_col), " ~ ", .uvp01_bt(var)))
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
    
    fml <- as.formula(paste0(.uvp01_bt(outcome_col), " ~ ", .uvp01_bt(var)))
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
    d_fit <- data
    if (exists("pipeline_cox_unit_scale", mode = "function") && var %in% names(d_fit)) {
      sc <- pipeline_cox_unit_scale(var, d_fit[[var]])
      if (!identical(sc$scale, 1) && is.numeric(sc$x)) {
        d_fit[[var]] <- sc$x
      }
    }
    fml <- as.formula(paste0(
      "Surv(", .uvp01_bt(time_var), ", ", .uvp01_bt(event_var), ") ~ ", .uvp01_bt(var)
    ))
    fit <- tryCatch(
      survival::coxph(fml, data = d_fit),
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


  .extract_base_varname <- .uvp01_extract_base_varname


  if (identical(classification_mode, "multiclass")) {
    cli::cli_alert_warning("prognosis 不使用多分类 Logistic；按 Cox 分析")
  }
  cli::cli_h2("单因素 Cox 回归（HR）")
  univar_results <- list()
  pb <- cli::cli_progress_bar("Univariate Cox", total = length(predictor_vars))
  for (var in predictor_vars) {
    res <- .run_univariate_cox(var, data, time_var, event_var)
    if (!is.null(res)) univar_results[[var]] <- res
    cli::cli_progress_update(id = pb)
  }
  cli::cli_progress_done(id = pb)
  univar_df <- if (length(univar_results)) { x <- do.call(rbind, univar_results); rownames(x) <- NULL; x } else NULL
  tb1 <- character(0)
  tb_screen <- character(0)
  if (!is.null(univar_df) && nrow(univar_df) > 0) {
    p_ok <- !is.na(univar_df$P)
    tb1 <- .extract_base_varname(
      univar_df$Variable[p_ok & univar_df$P < p_threshold],
      predictor_vars
    )
    tb_screen <- .extract_base_varname(
      univar_df$Variable[p_ok & univar_df$P < screening_cutoff],
      predictor_vars
    )
  }
  if (length(req_in_data) && !isTRUE(uv_cfg$fail_on_index_ns %||% FALSE)) {
    tb1 <- unique(c(tb1, req_in_data))
    tb_screen <- unique(c(tb_screen, req_in_data))
  }
  cli::cli_alert_success("单因素显著变量 tb1 (P < {p_threshold}): {length(tb1)} 个")
  cli::cli_alert_success("VIF screening 候选 tb_screen (P < {screening_cutoff}): {length(tb_screen)} 个")

  if (length(tb_screen) == 0) {
    ctx$results$pause_point <- list(
      block = "univariate_prognosis",
      reason = "未找到单因素 screening 候选变量 (p < screening_cutoff)",
      suggestion = paste0(
        "请检查数据或放宽 config$univariate_prognosis$screening_cutoff (当前: ", screening_cutoff, ")"
      ),
      data_snapshot = if (!is.null(univar_df) && nrow(univar_df) > 0) utils::head(univar_df, 5) else NULL
    )
    stop("PAUSE_FOR_USER_DECISION: 未找到 screening 候选变量，请查看 ctx$results$pause_point。")
  }

  if (exists("pipeline_check_index_regression_significant", mode = "function")) {
    pipeline_check_index_regression_significant(
      ctx, cfg, univar_df, tb1, "univariate_prognosis", p_threshold
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
    .univariate_prognosis_export_table_s2a(ctx, cfg, uv_cfg, data, predictor_vars, univar_df, tb1, study_type, classification_mode)
  }

  cli::cli_alert_success("单因素分析完成（仅单因素）")
  ctx
}

register_block(
  "univariate_prognosis",
  block_univariate_prognosis,
  "Prognosis univariate Cox HR + Table S2a"
)