###############################################################################
#  multivariate_prognosis — 预后多因素 Cox HR（Table S2），读单因素 univar_coef 筛变量。
#
#  register_block: "multivariate_prognosis"
#  前置: univariate_prognosis；ctx$results$univar_coef、tb1
#  配置: config$multivariate_prognosis（sig_cutoff、Model 构建、pause、导出）
#  写: 多因素表、multivar 相关结果；study_type=prognosis
###############################################################################

.mvp01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.mvp01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "multivariate_prognosis", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / 发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。", call. = FALSE)
}
.mvp01_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff %||% bl_cfg$p_threshold
  if (is.null(cutoff)) .mvp01_pause(ctx, "未配置 sig_cutoff", "在 config$multivariate_prognosis 设置 sig_cutoff", NULL)
  as.numeric(cutoff)[1L]
}



# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.mvp01_extract_base_varname <- function(var_names, all_vars) {
  var_names <- as.character(var_names)
  var_names <- var_names[!is.na(var_names) & nzchar(var_names)]
  if (!length(var_names)) return(character(0))
  base_names <- sapply(var_names, function(vn) {
    if (is.na(vn) || !nzchar(vn)) return(NA_character_)
    for (av in all_vars[order(-nchar(all_vars))]) {
      if (is.na(av) || !nzchar(av)) next
      if (identical(vn, av)) return(av)
      if (startsWith(vn, av)) return(av)
      pattern <- paste0("^", av, "\\d*$")
      if (grepl(pattern, vn, perl = TRUE)) return(av)
    }
    vn
  })
  unique(base_names[!is.na(base_names) & nzchar(base_names)])
}

# VIF 阈值：若下游接 feature_selection（enable=TRUE），用 10；否则用 vif_threshold_strict（默认 4）
.mvp01_pipeline_effective_vif_thresholds <- function(cfg) {
  mc <- cfg$multicollinearity %||% list()
  fs <- cfg$feature_selection %||% list()
  fs_on <- isTRUE(fs$enable %||% TRUE)
  strict <- as.numeric(mc$vif_threshold_strict %||% 4)[1L]
  loose  <- as.numeric(mc$vif_threshold_loose %||% 10)[1L]
  min_v  <- as.numeric(mc$min_vars_threshold %||% 10)[1L]
  if (fs_on) {
    thr_fs <- as.numeric(mc$vif_threshold_before_feature_selection %||% 10)[1L]
    if (!is.na(thr_fs)) {
      strict <- thr_fs
      loose  <- max(loose, strict, na.rm = TRUE)
    }
  }
  list(
    strict = strict,
    loose = loose,
    min_vars = min_v,
    feature_selection_follows = fs_on
  )
}

# ── BMI / Weight / Height：VIF 过高时渐进剔除（单因素块内实现，供 multicollinearity 等复用）──
.mvp01_calculate_vif_from_vars <- function(vars, data) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (length(vars) <= 1L) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
  df_subset <- data[, vars, drop = FALSE]
  for (v in vars) {
    if (is.factor(df_subset[[v]]) || is.character(df_subset[[v]])) {
      df_subset[[v]] <- as.numeric(as.factor(df_subset[[v]]))
    }
    if (any(is.na(df_subset[[v]]))) {
      df_subset[[v]][is.na(df_subset[[v]])] <- stats::median(df_subset[[v]], na.rm = TRUE)
    }
  }
  X <- tryCatch({
    mm <- stats::model.matrix(~ ., data = df_subset)
    mm[, -1L, drop = FALSE]
  }, error = function(e) NULL)
  if (is.null(X) || ncol(X) == 0L) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
  vif_values <- tryCatch({
    r2s <- vapply(seq_len(ncol(X)), function(j) {
      if (ncol(X) == 1L) return(0)
      summary(stats::lm(X[, j] ~ X[, -j, drop = FALSE]))$r.squared
    }, numeric(1))
    stats::setNames(1 / (1 - r2s), colnames(X))
  }, error = function(e) NULL)
  if (is.null(vif_values)) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
  list(
    vif_df = data.frame(
      Variable = names(vif_values),
      VIF = round(as.numeric(vif_values), 3),
      stringsAsFactors = FALSE
    ),
    vif_values = vif_values
  )
}

.mvp01_max_vif_for_original_var <- function(vif_values, orig_name) {
  if (is.null(vif_values) || !length(vif_values) || !nzchar(orig_name)) {
    return(NA_real_)
  }
  hit <- names(vif_values)[
    names(vif_values) == orig_name |
      grepl(paste0("^", orig_name, "(?:[0-9]|[^A-Za-z0-9_])"), names(vif_values), perl = TRUE)
  ]
  if (!length(hit)) return(NA_real_)
  max(as.numeric(vif_values[hit]), na.rm = TRUE)
}

.mvp01_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mvp01_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mvp01_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mvp01_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[vars %in% names(data)]
  mc <- cfg$multicollinearity %||% list()
  ar <- mc$anthropometric_vif_resolution %||% list()
  if (!isTRUE(ar$enable %||% TRUE)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "disabled",
      anthro_max_vif = NULL
    ))
  }
  anthro_cfg <- unique(as.character(ar$vars %||% c("BMI", "Weight", "Height")))
  try_one <- unique(as.character(ar$prefer_drop_one_order %||% c("Weight", "Height")))
  thr <- .mvp01_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }
  res0 <- .mvp01_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mvp01_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mvp01_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro) next
    trial <- setdiff(vars, d1)
    if (.mvp01_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- intersect(c("Weight", "Height"), anthro)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 2L &&
      .mvp01_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
    return(list(
      kept = trial2, dropped = drop_wh, strategy = "drop_weight_and_height",
      anthro_max_vif = anthro_max
    ))
  }
  if ("BMI" %in% anthro) {
    trial3 <- setdiff(vars, "BMI")
    return(list(
      kept = trial3, dropped = "BMI", strategy = "drop_bmi",
      anthro_max_vif = anthro_max
    ))
  }
  list(kept = vars, dropped = character(0), strategy = "unresolved", anthro_max_vif = anthro_max)
}

.mvp01_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mvp01_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mvp01_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mvp01_resolve_anthropometric_vif_vars(vars, data, cfg)
  dropped <- unique(as.character(res$dropped))
  dropped <- dropped[nzchar(dropped)]
  if (length(dropped) > 0L) {
    cli::cli_alert_info(
      "{label}: BMI/Weight/Height VIF 策略 [{res$strategy}]，剔除: {paste(dropped, collapse = ', ')}"
    )
    if (!is.null(res$anthro_max_vif) && length(res$anthro_max_vif)) {
      cli::cli_alert_info(
        "{label}: 剔除前人体测量 max VIF — {paste(names(res$anthro_max_vif), round(res$anthro_max_vif, 3), sep = '=', collapse = '; ')}"
      )
    }
  } else if (identical(res$strategy, "vif_ok")) {
    thr_msg <- .mvp01_pipeline_effective_vif_thresholds(cfg)$strict
    n_anthro <- length(intersect(
      (cfg$multicollinearity %||% list())$anthropometric_vif_resolution$vars %||%
        c("BMI", "Weight", "Height"),
      res$kept
    ))
    cli::cli_alert_info(
      "{label}: 人体测量 {n_anthro} 项并存且各自 VIF < {thr_msg}，全部保留"
    )
    if (!is.null(res$anthro_max_vif) && length(res$anthro_max_vif)) {
      cli::cli_alert_info(
        "{label}: 人体测量 VIF — {paste(names(res$anthro_max_vif), round(res$anthro_max_vif, 3), sep = '=', collapse = '; ')}"
      )
    }
  }
  if (!is.null(ctx)) {
    prev <- unique(as.character(ctx$results$anthropometric_dropped_vars %||% character(0)))
    ctx$results$anthropometric_dropped_vars <- unique(c(prev, dropped))
    ctx$results$anthropometric_vif_strategy <- res$strategy
    ctx$results$anthropometric_max_vif <- res$anthro_max_vif
  }
  list(ctx = ctx, kept = res$kept, dropped = dropped, strategy = res$strategy)
}

.mvp01_run_multivariate_cox <- function(vars, data, time_var, event_var) {
  if (length(vars) == 0L) return(NULL)
  rhs <- paste(vars, collapse = " + ")
  fml <- stats::as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", rhs))
  fit <- tryCatch(
    survival::coxph(fml, data = data),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  co <- s$coefficients
  nm <- rownames(co)
  if (is.null(nm) || length(nm) == 0L) return(NULL)
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

.mvp01_coerce_survival_event_01 <- function(x, cfg) {
  if (is.numeric(x)) {
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
  }
  if (is.logical(x)) return(as.integer(x))
  xc <- trimws(as.character(x))
  ref_lbl <- trimws(cfg$project$reference_group %||% "")
  ana_lbl <- trimws(cfg$project$analysis_group %||% "")
  out <- rep(NA_integer_, length(xc))
  if (nzchar(ana_lbl)) out[xc == ana_lbl] <- 1L
  if (nzchar(ref_lbl)) out[xc == ref_lbl] <- 0L
  if (nzchar(ana_lbl)) out[tolower(xc) == tolower(ana_lbl) & is.na(out)] <- 1L
  if (nzchar(ref_lbl)) out[tolower(xc) == tolower(ref_lbl) & is.na(out)] <- 0L
  out[is.na(xc)] <- NA_integer_
  out
}

# 发表表行顺序：own 库保留数据列序，否则按 .default_table1_sections（Table 1 分组）


.multivariate_prognosis_export_table_s2 <- function(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, tb1, tb2 = character(0), study_type, classification_mode) {
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .mvp01_extract_base_varname(c(vn), predictor_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  uni_slice <- univar_df[row_base %in% tb1, , drop = FALSE]
  if (nrow(uni_slice) == 0L) uni_slice <- univar_df
  if (TRUE) {
    title_suffix <- " (all variables, multivariate tb1)"
  } else {
    title_suffix <- " (all variables, univariate)"
  }

  # run_prediction 多指标：Table S2 等发表表与 tb2/tb3 取并集，始终保留 prediction$index_vars 行（单因素未显著也输出）
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
      cli::cli_alert_info(
        "prediction$index_vars 已强制保留在单/多因素导出表行中: {paste(intersect(unique(row_base), pred_tbl_ix), collapse = ', ')}"
      )
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
    grp_u <- rep("", nrow(uni_slice))
    est_u <- uni_slice$HR
    base_title <- paste0("Cox Regression Analysis of ", cfg$project$disease)
  } else if (FALSE && classification_mode == "binary") {
    grp_u <- rep("", nrow(uni_slice))
    est_u <- uni_slice$OR
    base_title <- paste0("Logistic Regression Analysis of ", cfg$project$disease)
  } else {
    # multiclass incidence：宽表已由 wide_multiclass_done 路径生成；
    # 此处仍需为后续 uni_key 赋值，以免下游代码引用时报错
    grp_u <- if ("Group" %in% names(uni_slice)) as.character(uni_slice$Group) else rep("", nrow(uni_slice))
    est_u <- if ("OR" %in% names(uni_slice)) uni_slice$OR else rep(NA_real_, nrow(uni_slice))
    base_title <- paste0("Multinomial Logistic Regression Analysis of ", cfg$project$disease)
  }

  uni_key <- data.frame(
    Variable = uni_slice$Variable,
    Group    = grp_u,
    Est_u    = est_u,
    Lo_u     = uni_slice$CI_lo,
    Hi_u     = uni_slice$CI_hi,
    P_u      = uni_slice$P,
    stringsAsFactors = FALSE
  )

  # 多因素模型（"multivariate"=multivariate 时）始终对 tb2 拟合；发表表单因素行在 multivariate 下按 tb2 筛选以合并 multivar_result。
  multi_key <- NULL
  if (!is.null(multivar_result) && nrow(multivar_result) > 0) {
    if (study_type == "prognosis") {
      grp_m <- rep("", nrow(multivar_result))
      est_m <- multivar_result$HR
    } else {
      grp_m <- if (classification_mode == "binary") rep("", nrow(multivar_result)) else as.character(multivar_result$Group)
      est_m <- multivar_result$OR
    }
    multi_key <- data.frame(
      Variable = multivar_result$Variable,
      Group    = grp_m,
      Est_m    = est_m,
      Lo_m     = multivar_result$CI_lo,
      Hi_m     = multivar_result$CI_hi,
      P_m      = multivar_result$P,
      stringsAsFactors = FALSE
    )
  } else if (length(tb2) > 0L && TRUE) {
    cli::cli_alert_warning("多因素拟合无系数表输出，Multivariate 列留空（请检查 tb2 变量或 glm 是否失败）。")
  }

  if (is.null(multi_key)) {
    m <- uni_key
    m$Est_m <- NA_real_
    m$Lo_m <- NA_real_
    m$Hi_m <- NA_real_
    m$P_m <- NA_real_
  } else {
    m <- merge(uni_key, multi_key, by = c("Variable", "Group"), all = TRUE, sort = FALSE)
  }

  m$base_var <- vapply(m$Variable, function(vn) {
    as.character(.mvp01_extract_base_varname(c(vn), predictor_vars)[1])
  }, character(1))
  # 发表表行顺序与 Table 1 分组保持一致（baseline$table1_sections 或默认分组）
  base_order_tbl1 <- sort_univariate_table_vars(unique(as.character(m$base_var)), cfg, names(data))
  m <- m[order(
    match(as.character(m$base_var), base_order_tbl1, nomatch = 999999L),
    as.character(m$Group),
    as.character(m$Variable)
  ), , drop = FALSE]
  lab_uni <- if (study_type == "prognosis") "HR (univariable)" else "OR (univariable)"
  lab_multi <- if (study_type == "prognosis") "HR (multivariable)" else "OR (multivariable)"
  disc_n <- mv_cfg$discrete_max_levels %||% 5L

  wide_multiclass_done <- FALSE
  out_table <- NULL

  # 多分类 + 发病：Table 2 式宽表（每个非参照水平 vs reference，Crude / Adjusted）
  if (identical(classification_mode, "multiclass") && study_type == "incidence") {
    analysis_groups <- cfg$project$analysis_groups %||% character(0)
    ref_grp <- cfg$project$reference_group %||% ""
    analysis_groups <- as.character(analysis_groups)
    ref_grp <- as.character(ref_grp)
    if (length(ref_grp) > 1L) ref_grp <- ref_grp[1L]

    if (length(analysis_groups) >= 2L &&
        length(ref_grp) == 1L && nzchar(ref_grp) &&
        identical(trimws(analysis_groups[1]), trimws(ref_grp))) {
      cmp_levels <- analysis_groups[-1L]
    } else if (length(analysis_groups) > 0L && length(ref_grp) == 1L && nzchar(ref_grp)) {
      cmp_levels <- analysis_groups[vapply(analysis_groups, function(g) {
        !identical(trimws(as.character(g)), trimws(ref_grp))
      }, logical(1))]
    } else {
      cmp_levels <- unique(as.character(m$Group[m$Group != ""]))
    }

    .norm_lbl_mc <- function(s) {
      tolower(gsub("\\s+", " ", trimws(as.character(s))))
    }
    .cell_or_multinom <- function(vn, grp, adj) {
      vn <- as.character(vn)
      vi <- as.character(m$Variable)
      tg <- .norm_lbl_mc(grp)
      gi <- vapply(seq_len(nrow(m)), function(i) .norm_lbl_mc(m$Group[i]), character(1))
      hit <- vi == vn & gi == tg
      if (!any(hit)) {
        hit <- vi == vn & vapply(seq_len(nrow(m)), function(i) {
          identical(as.character(m$Group[i]), as.character(grp))
        }, logical(1))
      }
      rr <- m[hit, , drop = FALSE]
      if (nrow(rr) != 1L) return("")
      if (adj) {
        .fmt_ci_p(rr$Est_m[1], rr$Lo_m[1], rr$Hi_m[1], rr$P_m[1])
      } else {
        .fmt_ci_p(rr$Est_u[1], rr$Lo_u[1], rr$Hi_u[1], rr$P_u[1])
      }
    }

    uvar <- unique(as.character(m$Variable))
    base_ord_u <- vapply(uvar, function(vn) {
      as.character(.mvp01_extract_base_varname(c(vn), predictor_vars)[1])
    }, character(1))
    uvar <- uvar[order(match(base_ord_u, predictor_vars, nomatch = 999999L), uvar)]
    bases_ordered <- unique(vapply(uvar, function(vn) {
      as.character(.mvp01_extract_base_varname(c(vn), predictor_vars)[1])
    }, character(1)))
    bases_ordered <- sort_univariate_table_vars(bases_ordered, cfg, names(data))

    .find_vn_cat_level <- function(bv, lev, sub_uvars) {
      lev <- as.character(lev)
      for (su in sub_uvars) {
        if (!startsWith(su, bv)) next
        suf <- if (nchar(su) <= nchar(bv)) "" else substring(su, nchar(bv) + 1L)
        if (identical(suf, lev)) return(su)
      }
      cand <- paste0(bv, lev)
      if (cand %in% sub_uvars) return(cand)
      for (su in sub_uvars) {
        if (grepl(lev, su, fixed = TRUE)) {
          b <- as.character(.mvp01_extract_base_varname(c(su), predictor_vars)[1])
          if (identical(b, bv)) return(su)
        }
      }
      NA_character_
    }

    .make_effect_cols_mc <- function(vn_or_empty) {
      cols <- list()
      vn_ok <- length(vn_or_empty) == 1L && is.character(vn_or_empty) &&
        !is.na(vn_or_empty[1]) && nzchar(vn_or_empty[1])
      vn_use <- if (vn_ok) vn_or_empty[1] else NA_character_
      for (k in seq_along(cmp_levels)) {
        cl <- cmp_levels[k]
        if (!is.na(vn_use)) {
          cols[[paste0("Crude_", k)]] <- .cell_or_multinom(vn_use, cl, FALSE)
          if (TRUE) {
            cols[[paste0("Adj_", k)]] <- .cell_or_multinom(vn_use, cl, TRUE)
          }
        } else {
          cols[[paste0("Crude_", k)]] <- ""
          if (TRUE) {
            cols[[paste0("Adj_", k)]] <- ""
          }
        }
      }
      as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
    }

    eff_short <- "OR"
    mc_rows <- list()
    for (bv in bases_ordered) {
      if (!bv %in% names(data)) next
      sub_us <- uvar[vapply(uvar, function(vn) {
        identical(as.character(.mvp01_extract_base_varname(c(vn), predictor_vars)[1]), bv)
      }, logical(1))]
      if (length(sub_us) == 0L) next
      x <- data[[bv]]
      is_cont <- (bv %in% force_continuous_vars) ||
        (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)
      lab_bv <- gsub("_", " ", bv)

      if (is_cont) {
        vn0 <- if (bv %in% sub_us) bv else sub_us[1L]
        mc_rows[[length(mc_rows) + 1L]] <- cbind(
          data.frame(Variable = lab_bv, stringsAsFactors = FALSE, check.names = FALSE),
          .make_effect_cols_mc(vn0)
        )
      } else {
        mc_rows[[length(mc_rows) + 1L]] <- cbind(
          data.frame(Variable = lab_bv, stringsAsFactors = FALSE, check.names = FALSE),
          .make_effect_cols_mc(character(0))
        )
        xf <- factor(x)
        lv <- levels(xf)
        if (length(lv) == 0L) next
        for (lev in lv) {
          vn_lev <- .find_vn_cat_level(bv, lev, sub_us)
          mc_rows[[length(mc_rows) + 1L]] <- cbind(
            data.frame(Variable = paste0("  ", as.character(lev)), stringsAsFactors = FALSE, check.names = FALSE),
            .make_effect_cols_mc(if (!is.na(vn_lev)) vn_lev else character(0))
          )
        }
      }
    }

    out_mc <- do.call(rbind, mc_rows)
    rownames(out_mc) <- NULL

    r_disp <- if (length(ref_grp) == 1L && nzchar(ref_grp)) gsub("_", " ", ref_grp) else "Ref"
    header_row1 <- "Variable"
    header_row2 <- ""
    for (cl in cmp_levels) {
      c_disp <- gsub("_", " ", as.character(cl))
      cmp_title <- paste0(c_disp, " vs ", r_disp)
      if (TRUE) {
        header_row1 <- c(header_row1, cmp_title, cmp_title)
        header_row2 <- c(
          header_row2,
          paste0("Crude ", eff_short, " (95% CI), P"),
          paste0("Adjusted ", eff_short, " (95% CI), P")
        )
      } else {
        header_row1 <- c(header_row1, cmp_title)
        header_row2 <- c(
          header_row2,
          paste0("Crude ", eff_short, " (95% CI), P")
        )
      }
    }
    out_table <- out_mc
    attr(out_table, "header_row1") <- header_row1
    attr(out_table, "header_row2") <- header_row2
    wide_multiclass_done <- TRUE
  }

  pub_rows <- list()
  if (!wide_multiclass_done && identical(classification_mode, "multiclass")) {
    b_uni <- unique(m$base_var[m$base_var %in% names(data)])
    b_ord <- sort_univariate_table_vars(b_uni, cfg, names(data))
    m <- m[order(match(m$base_var, b_ord, nomatch = 999999L), m$Group, m$Variable), , drop = FALSE]
    prev_bv <- NA_character_
    for (i in seq_len(nrow(m))) {
      rr <- m[i, , drop = FALSE]
      bv <- rr$base_var[1]
      if (!bv %in% names(data)) next
      ch <- if (!identical(bv, prev_bv)) {
        prev_bv <- bv
        gsub("_", " ", bv)
      } else {
        ""
      }
      x <- data[[bv]]
      stat_txt <- paste0(rr$Group[1], " | ", gsub("_", " ", rr$Variable[1]))
      all_txt <- ""
      if ((bv %in% force_continuous_vars) ||
          (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)) {
        all_txt <- paste0(fmt_num(mean(x, na.rm = TRUE)), " \u00b1 ", fmt_num(stats::sd(x, na.rm = TRUE)))
      }
      u1 <- .fmt_ci_p(rr$Est_u, rr$Lo_u, rr$Hi_u, rr$P_u)
      m1 <- if (TRUE) {
        .fmt_ci_p(rr$Est_m, rr$Lo_m, rr$Hi_m, rr$P_m)
      } else {
        ""
      }
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = ch,
        Statistic = stat_txt,
        all = all_txt,
        U1 = u1,
        M1 = m1,
        stringsAsFactors = FALSE
      )
    }
  } else if (!wide_multiclass_done) {
    bases <- unique(m$base_var[m$base_var %in% names(data)])
    bases <- sort_univariate_table_vars(bases, cfg, names(data))
    for (bv in bases) {
      x <- data[[bv]]
      lab_char <- gsub("_", " ", bv)
      sub_m <- m[m$base_var == bv, , drop = FALSE]
      is_cont <- (bv %in% force_continuous_vars) ||
        (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)

      if (is_cont) {
        mu <- mean(x, na.rm = TRUE)
        sg <- stats::sd(x, na.rm = TRUE)
        all_txt <- paste0(fmt_num(mu), " \u00b1 ", fmt_num(sg))
        mr <- sub_m[sub_m$Variable == bv, , drop = FALSE]
        u1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr$Est_u[1], mr$Lo_u[1], mr$Hi_u[1], mr$P_u[1]) else ""
        m1 <- if (TRUE && nrow(mr) >= 1L) {
          .fmt_ci_p(mr$Est_m[1], mr$Lo_m[1], mr$Hi_m[1], mr$P_m[1])
        } else {
          ""
        }
        pub_rows[[length(pub_rows) + 1L]] <- data.frame(
          Characteristic = lab_char,
          Statistic = "Mean \u00b1 SD",
          all = all_txt,
          U1 = u1,
          M1 = m1,
          stringsAsFactors = FALSE
        )
      } else {
        xf <- factor(x)
        lv <- levels(xf)
        if (length(lv) == 0L) next
        n_tot <- sum(!is.na(x))
        ref <- lv[1]
        n0 <- sum(xf == ref, na.rm = TRUE)
        pct0 <- if (n_tot > 0) n0 / n_tot * 100 else 0
        pub_rows[[length(pub_rows) + 1L]] <- data.frame(
          Characteristic = lab_char,
          Statistic = as.character(ref),
          all = paste0(n0, " (", fmt_num(pct0), "%)"),
          U1 = "",
          M1 = "",
          stringsAsFactors = FALSE
        )
        if (length(lv) > 1L) {
          for (k in seq_len(length(lv))[-1L]) {
            lev <- lv[k]
            nk <- sum(xf == lev, na.rm = TRUE)
            pctk <- if (n_tot > 0) nk / n_tot * 100 else 0
            mr <- sub_m[sub_m$Variable == paste0(bv, lev), , drop = FALSE]
            if (nrow(mr) == 0L) {
              mr <- sub_m[grepl(lev, sub_m$Variable, fixed = TRUE) & sub_m$Variable != bv, , drop = FALSE]
            }
            if (nrow(mr) == 0L) {
              mr <- sub_m[sub_m$Variable == lev, , drop = FALSE]
            }
            if (nrow(mr) > 1L) mr <- mr[1L, , drop = FALSE]
            u1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr$Est_u, mr$Lo_u, mr$Hi_u, mr$P_u) else ""
            m1 <- if (TRUE && nrow(mr) == 1L) {
              .fmt_ci_p(mr$Est_m, mr$Lo_m, mr$Hi_m, mr$P_m)
            } else {
              ""
            }
            pub_rows[[length(pub_rows) + 1L]] <- data.frame(
              Characteristic = "",
              Statistic = as.character(lev),
              all = paste0(nk, " (", fmt_num(pctk), "%)"),
              U1 = u1,
              M1 = m1,
              stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }

  if (!wide_multiclass_done) {
    if (length(pub_rows) == 0L) {
      cli::cli_alert_warning("发表用表格行为空，退回简化宽表")
      out_table <- data.frame(
        Variable = m$Variable,
        Group = m$Group,
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      out_table[[lab_uni]] <- vapply(seq_len(nrow(m)), function(i) {
        .fmt_ci_p(m$Est_u[i], m$Lo_u[i], m$Hi_u[i], m$P_u[i])
      }, character(1))
      if (TRUE) {
        out_table[[lab_multi]] <- vapply(seq_len(nrow(m)), function(i) {
          .fmt_ci_p(m$Est_m[i], m$Lo_m[i], m$Hi_m[i], m$P_m[i])
        }, character(1))
      }
    } else {
      out_table <- do.call(rbind, pub_rows)
      names(out_table)[names(out_table) == "U1"] <- lab_uni
      if ("M1" %in% names(out_table)) {
        names(out_table)[names(out_table) == "M1"] <- lab_multi
      }
    }
  }


  file_caption <- as.character(mv_cfg$table_file_caption %||% "Multivariable Regression Analysis")[1L]
  if (!nzchar(file_caption)) file_caption <- "Multivariable Regression Analysis"
  title_caption <- as.character(mv_cfg$table_title_caption %||% file_caption)[1L]
  if (!nzchar(title_caption)) title_caption <- file_caption
  # base_title 可叠加说明（如 dual-database harmonized）
  base_extra <- as.character(mv_cfg$table_title_prefix %||% "")[1L]
  if (nzchar(base_extra)) {
    title_caption <- paste(base_extra, title_caption)
  }
  # Gate C+ Table S7：固定附表号，避免与 cox_quartile 基线表抢号后丢失
  fixed_sno <- suppressWarnings(as.integer(mv_cfg$table_number %||% NA_integer_)[1L])
  if (isTRUE(ctx$results$.multivariate_mode_harmonized) &&
      (!is.finite(fixed_sno) || fixed_sno < 1L)) {
    fixed_sno <- 7L
  }
  if (is.finite(fixed_sno) && fixed_sno >= 1L) {
    pref <- pub_prefix("supp_table", fixed_sno)
    title_mv <- paste(pref, title_caption)
    stem_f <- paste(pref, file_caption)
    filepath_mv <- .inject_db_into_pub_filepath(
      file.path(ctx$output_dir_tables, paste0(stem_f, ".xlsx"))
    )
    filepath_mv <- .pub_path_with_slot_label(ctx, filepath_mv)
    # 同步计数器，避免后续表号倒退到 S7 之前
    if (exists("pub_bump_supp_table_min", mode = "function")) {
      pub_bump_supp_table_min(fixed_sno)
    } else {
      cur <- as.integer(.pub_state$supp_table %||% 0L)
      if (cur < fixed_sno) .pub_state$supp_table <- fixed_sno
    }
    pub_mv <- list(title = title_mv, filepath = filepath_mv, id = fixed_sno)
  } else {
    pub_mv <- pub_pair(
      ctx, ctx$output_dir_tables, "supp_table",
      title_caption, file_caption, "xlsx"
    )
  }
  title_mv <- pub_mv$title
  filepath_mv <- pub_mv$filepath
  if (exists("multivariate_pub_drop_univariable_if_needed", mode = "function")) {
    out_table <- multivariate_pub_drop_univariable_if_needed(out_table, cfg)
    h1a <- attr(out_table, "header_row1")
    h2a <- attr(out_table, "header_row2")
    if (!is.null(h1a) && length(h1a) != ncol(out_table)) attr(out_table, "header_row1") <- NULL
    if (!is.null(h2a) && length(h2a) != ncol(out_table)) attr(out_table, "header_row2") <- NULL
  }
  h1 <- attr(out_table, "header_row1")
  h2 <- attr(out_table, "header_row2")
  tryCatch({
    if (wide_multiclass_done && !is.null(h1) && !is.null(h2) &&
        length(h1) == ncol(out_table) && length(h2) == ncol(out_table)) {
      # 分类子行：Variable 以两个空格开头；.prepare_df_for_tex 会 trimws 掉空格，
      # 因此在原始 out_table 上检测，通过 excel_level_row_idx 显式传给渲染器居中显示
      mc_level_idx <- which(grepl("^  ", as.character(out_table[[1L]])))
      excel_lv_idx <- if (length(mc_level_idx) > 0L) mc_level_idx + 1L else NULL
      export_sci_table(out_table, filepath_mv, title = title_mv,
                       header_row1 = h1, header_row2 = h2,
                       latex_include_colnames = FALSE,
                       excel_level_row_idx = excel_lv_idx)
    } else {
      export_sci_table(out_table, filepath_mv, title = title_mv)
    }
  }, error = function(e) cli::cli_alert_warning("Excel export failed: {e$message}"))

  invisible(TRUE)
}

block_multivariate_prognosis <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(survival)
  })

  cfg     <- ctx$config
  up_res  <- pipeline_upstream_modeling_data(ctx)
  data    <- up_res$data
  if (is.null(data)) stop("No data found. Run imputation or data_clean first.")
    if (tolower(ctx$config$project$study_type %||% "") != "prognosis") stop("需要 study_type=prognosis")
  if (.is_nhanes_db(ctx$config)) stop("NHANES 请用 multivariate_nhanes")

  univar_df <- ctx$results$univar_coef
  if (is.null(univar_df) || !is.data.frame(univar_df) || nrow(univar_df) == 0L) {
    stop("请先运行对应 univariate_* 块以生成 ctx$results$univar_coef")
  }

  tb1_in <- as.character(ctx$results$tb1 %||% character(0))
  tb1_in <- unique(tb1_in[nzchar(tb1_in)])

  mv_cfg <- cfg$multivariate_prognosis %||% list()
  # 闸门 B 对齐后统一协变量多因素表：优先读 multivariate_prognosis_harmonized
  if (isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    mv_cfg <- utils::modifyList(
      mv_cfg,
      cfg$multivariate_prognosis_harmonized %||% list()
    )
  }
  input_from <- as.character(mv_cfg$input_from %||% "vif_screen_pass")[1L]
  mv_input <- switch(input_from,
    vif_screen_pass = as.character(ctx$results$vif_screen_pass %||% character(0)),
    tb_screen = as.character(ctx$results$tb_screen %||% character(0)),
    tb1 = tb1_in,
    Model2Factors = as.character(ctx$results$Model2Factors %||% character(0)),
    model2_factors = as.character(ctx$results$Model2Factors %||% character(0)),
    as.character(ctx$results$univar_features %||% tb1_in)
  )
  mv_input <- unique(mv_input[nzchar(mv_input)])
  if (isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    # Gate C+ / 强制锁定集已写入 Model2Factors 时，勿再用 locked_multivariable
    # 覆盖（否则旧 Gate B / 空 cox_final 会把 Table S7 打回全池）。
    harm_fixed <- as.character(
      (cfg$multivariate_prognosis_harmonized %||% list())$fixed_model2_factors %||%
        character(0)
    )
    harm_fixed <- unique(harm_fixed[nzchar(harm_fixed)])
    if (length(harm_fixed)) {
      mv_input <- unique(c(
        as.character(ctx$results$Model1Factors %||% character(0)),
        harm_fixed
      ))
      mv_input <- unique(mv_input[nzchar(mv_input)])
      cli::cli_alert_info(
        "Table S7 使用 fixed_model2_factors: {paste(mv_input, collapse = ', ')}"
      )
    } else if (isTRUE(ctx$results$dual_db_cox_covariates_locked) &&
        exists("locked_multivariable_covariates", mode = "function")) {
      lk <- locked_multivariable_covariates(ctx, cfg)
      mv_input <- unique(as.character(lk$covariates %||% character(0)))
      cli::cli_alert_info(
        "Table S7 锁定为 Table 2 协变量: {paste(mv_input, collapse = ', ')}"
      )
    } else if (exists("pipeline_union_model3_required", mode = "function")) {
      ix <- if (exists("pipeline_index_exposure_var", mode = "function")) {
        pipeline_index_exposure_var(cfg)
      } else {
        NULL
      }
      before <- mv_input
      mv_input <- pipeline_union_model3_required(mv_input, cfg, names(data), ix)
      added <- setdiff(mv_input, before)
      if (length(added)) {
        cli::cli_alert_info("Table S7 并入 Model3 必调: {paste(added, collapse = ', ')}")
      }
    }
  }
  if (!length(mv_input)) {
    if (identical(input_from, "Model2Factors") || identical(input_from, "model2_factors")) {
      stop("多因素输入变量为空 (input_from=Model2Factors)：请先完成 VIF final 与 dual_db_covariate_harmonize。",
           call. = FALSE)
    }
    stop("多因素输入变量为空 (config$multivariate_prognosis$input_from='", input_from,
         "')，请先运行 univariate + multicollinearity_screen。", call. = FALSE)
  }

  bl_cfg <- mv_cfg
  p_threshold <- .mvp01_resolve_sig_cutoff(bl_cfg, ctx)
  excluded_predictors <- mv_cfg$excluded_predictors %||% character(0)
  required_predictors_cfg <- mv_cfg$required_predictors %||% character(0)
  demo_keywords <- mv_cfg$demo_keywords %||% character(0)
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  study_type <- "prognosis"
  classification_mode <- cfg$project$classification_mode %||% "binary"
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  if (event_var %in% names(data) && !is.numeric(data[[event_var]])) {
    data[[event_var]] <- .mvp01_coerce_survival_event_01(data[[event_var]], cfg)
    cli::cli_alert_info("已将 {event_var} 转为 0/1 数值（多因素 Cox）")
  }
  reference_group <- cfg$project$reference_group
  predictor_vars <- setdiff(names(data), outcome_col)
  excluded_predictors <- intersect(excluded_predictors, names(data))
  predictor_vars <- setdiff(predictor_vars, excluded_predictors)
  traj_class_cols <- predictor_vars[grepl("^trajectory_class(\\b|_)", predictor_vars, ignore.case = TRUE) |
                                      grepl("^trajectory_class$", predictor_vars, ignore.case = TRUE)]
  if (length(traj_class_cols)) {
    predictor_vars <- setdiff(predictor_vars, traj_class_cols)
    mv_input <- setdiff(mv_input, traj_class_cols)
    cli::cli_alert_info("排除潜类别列（不作协变量）: {paste(traj_class_cols, collapse = ', ')}")
  }
  if (exists("pipeline_apply_include_predictors", mode = "function")) {
    predictor_vars <- pipeline_apply_include_predictors(
      cfg, predictor_vars, names(data), label = "多因素导出/人体测量 VIF"
    )
  }

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  if (study_type == "incidence" && identical(classification_mode, "binary")) {
    data[[outcome_col]] <- as.integer(data[[outcome_col]] == disease_label)
  }

  cli::cli_h2("多因素回归（基于 {input_from}，{length(mv_input)} 个变量）")
  mv_input <- intersect(mv_input, names(data))
  # 发表表多因素列须含暴露指标；VIF screen 故意不把暴露放进协变量池，此处补回。
  # 同时剔除暴露组分（如 ALBI 的 Albumin/Bilirubin），避免共线。
  exposure <- if (exists("pipeline_index_exposure_var", mode = "function")) {
    as.character(pipeline_index_exposure_var(cfg) %||% character(0))[1L]
  } else {
    as.character(surv_cfg$index_var %||% character(0))[1L]
  }
  if (is.na(exposure) || !nzchar(exposure)) exposure <- ""
  comps <- if (exists("pipeline_index_component_vars_only", mode = "function")) {
    as.character(pipeline_index_component_vars_only(cfg) %||% character(0))
  } else {
    character(0)
  }
  comps <- comps[nzchar(comps)]
  mv_fit <- setdiff(mv_input, comps)
  if (nzchar(exposure) && exposure %in% names(data)) {
    mv_fit <- unique(c(exposure, mv_fit))
    if (length(intersect(comps, mv_input))) {
      cli::cli_alert_info(
        "多因素拟合纳入暴露 {.field {exposure}}，已剔除组分: {paste(intersect(comps, mv_input), collapse = ', ')}"
      )
    } else {
      cli::cli_alert_info("多因素拟合纳入暴露 {.field {exposure}}（与 VIF 协变量池一并估计）")
    }
  }
  mv_fit <- intersect(mv_fit, names(data))
  multivar_result <- .mvp01_run_multivariate_cox(mv_fit, data, time_var, event_var)
  tb2 <- character(0)
  if (!is.null(multivar_result) && nrow(multivar_result) > 0) {
    tb2 <- .mvp01_extract_base_varname(multivar_result$Variable[multivar_result$P < p_threshold], mv_fit)
  }
  # 记录暴露指标多因素 P（闸门 B：两库都显著才可用单因素 VIF screen）
  idx_p <- NA_real_
  if (nzchar(exposure) && !is.null(multivar_result) && nrow(multivar_result) > 0L &&
      all(c("Variable", "P") %in% names(multivar_result))) {
    hit <- multivar_result$Variable == exposure |
      grepl(paste0("^", exposure, "($|[0-9])"), multivar_result$Variable)
    if (any(hit, na.rm = TRUE)) {
      idx_p <- suppressWarnings(min(as.numeric(multivar_result$P[hit]), na.rm = TRUE))
    }
  }
  ctx$results$index_multivar_p <- idx_p
  ctx$results$index_multivar_significant <- is.finite(idx_p) && idx_p < p_threshold
  if (isTRUE(ctx$results$index_multivar_significant)) {
    cli::cli_alert_success(
      "暴露 {.field {exposure}} 多因素显著: P={format(round(idx_p, 4), scientific = FALSE)}"
    )
  } else if (nzchar(exposure)) {
    cli::cli_alert_info(
      "暴露 {.field {exposure}} 多因素未达显著: P={if (is.finite(idx_p)) format(round(idx_p, 4), scientific = FALSE) else 'NA'}"
    )
  }
  # 暴露显著性闸门须在剥离前检查（否则 ALBI 等会被误判为“未进入显著集”）
  if (exists("pipeline_check_index_regression_significant", mode = "function")) {
    pipeline_check_index_regression_significant(
      ctx, cfg, multivar_result, tb2, "multivariate_prognosis", p_threshold
    )
  }
  # 下游 Model2 / Gate B 只用调整协变量，不含暴露及组分
  idx_all <- unique(c(
    exposure,
    comps,
    if (exists("pipeline_index_var_names", mode = "function")) {
      as.character(pipeline_index_var_names(cfg) %||% character(0))
    } else character(0)
  ))
  idx_all <- idx_all[nzchar(idx_all)]
  tb2_cov <- setdiff(tb2, idx_all)
  if (length(setdiff(tb2, tb2_cov))) {
    cli::cli_alert_info(
      "tb2 协变量池已剥离暴露/组分: {paste(setdiff(tb2, tb2_cov), collapse = ', ')}"
    )
  }
  tb2 <- tb2_cov
  cli::cli_alert_success("多因素显著变量 tb2 (P < {p_threshold}): {length(tb2)} 个")
  if (length(tb2) == 0L) {
    min_p <- if (!is.null(multivar_result) && nrow(multivar_result) > 0) {
      min(multivar_result$P, na.rm = TRUE)
    } else NA_real_
    n_ev <- if (event_var %in% names(data)) sum(as.integer(data[[event_var]]) == 1L, na.rm = TRUE) else NA_integer_
    cli::cli_alert_warning(
      paste0(
        "多因素无 P<", p_threshold, " 显著变量（拟合纳入 ", length(mv_fit), " 个变量）。",
        if (is.finite(min_p)) paste0(" Cox 最小 P=", signif(min_p, 3), "。") else " Cox 未产出系数表（可能未收敛）。",
        if (!is.na(n_ev)) paste0(" 事件数=", n_ev, "。") else "",
        " 常见原因：变量过多/共线导致 Cox 不收敛，或调整后确实无独立显著协变量。",
        " 将由 multivariate_covariate_resolve 回退至单因素协变量池，流程不中断。"
      )
    )
  }

  write_model_factors <- isTRUE(mv_cfg$write_model_factors %||% FALSE)
  required_predictors_cfg <- mv_cfg$required_predictors %||% character(0)
  required_predictors <- intersect(required_predictors_cfg, names(data))
  if (study_type == "prognosis") {
    required_predictors <- setdiff(required_predictors, c(time_var, event_var))
  } else {
    required_predictors <- setdiff(required_predictors, outcome_col)
  }

  if (write_model_factors) {
    model2_base <- if (length(tb2) > 0L) tb2 else mv_input
    Model2Factors <- unique(c(model2_base, required_predictors))
    Model2Factors <- intersect(Model2Factors, names(data))

    cli::cli_h2("BMI/Weight/Height 人体测量 VIF 协调")
    ar_anthro <- .mvp01_apply_anthropometric_vif_resolution(
      Model2Factors, data, cfg, ctx, "multivariate_prognosis"
    )
    ctx <- ar_anthro$ctx
    if (length(ar_anthro$dropped) > 0L) {
      dropped_anthro <- ar_anthro$dropped
      tb2 <- setdiff(tb2, dropped_anthro)
      Model2Factors <- ar_anthro$kept
      univar_df <- .mvp01_filter_coef_df_by_dropped_vars(univar_df, dropped_anthro, predictor_vars)
      multivar_result <- .mvp01_filter_coef_df_by_dropped_vars(multivar_result, dropped_anthro, predictor_vars)
    }

    screen_pool <- as.character(
      ctx$results$vif_screen_pass %||% ctx$results$vif_screen_pass_weighted %||% character(0)
    )
    if (exists(".mcol_apply_vif_final_covariate_split", mode = "function")) {
      split_res <- .mcol_apply_vif_final_covariate_split(ctx, cfg, Model2Factors, data)
      ctx <- split_res$ctx
      Model1Factors <- split_res$Model1Factors
      Model2Factors <- split_res$Model2Factors
    } else {
      demo_pattern <- paste(demo_keywords, collapse = "|")
      Model1Factors <- Model2Factors[grepl(demo_pattern, Model2Factors, ignore.case = TRUE)]
      Model1Factors <- intersect(Model1Factors, names(data))
    }

    if (length(Model2Factors) == 0) {
      ctx$results$pause_point <- list(
        block = "multivariate_prognosis",
        reason = "Model2Factors 为空",
        suggestion = paste0("检查多因素结果或放宽 config$multivariate_prognosis$sig_cutoff (当前: ", p_threshold, ")"),
        data_snapshot = utils::head(multivar_result, 5)
      )
      stop("PAUSE_FOR_USER_DECISION: Model2Factors 为空。")
    }
  } else if (length(tb2) == 0L && length(mv_input) == 0L) {
    ctx$results$pause_point <- list(
      block = "multivariate_prognosis",
      reason = "多因素无显著变量且输入为空",
      suggestion = paste0("检查多因素结果或放宽 sig_cutoff (当前: ", p_threshold, ")"),
      data_snapshot = utils::head(multivar_result, 5)
    )
    stop("PAUSE_FOR_USER_DECISION: 多因素分析无可用变量。")
  }

  ctx <- save_result(ctx, "tb2_multivar_features", tb2, "D05_Multivariable_Features.RData")
  if (write_model_factors) {
    ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
    ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
    writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
    writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))
    ctx$results$Model1Factors <- Model1Factors
    ctx$results$Model2Factors <- Model2Factors
  }

  .multivariate_prognosis_export_table_s2(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, mv_input, tb2, study_type, classification_mode)

  ctx$results$tb2 <- tb2
  ctx$results$multivar_features <- tb2
  ctx$results$multivar_input <- mv_input
  cli::cli_alert_success("多因素分析完成")
  ctx
}

register_block("multivariate_prognosis", block_multivariate_prognosis, "multivariate_prognosis")

# Gate B 后 / Gate C+ 最终锁定后：用 Model2Factors 再跑多因素 → Table S7
# dual_db 下默认 defer：流水线中途不写表，待 Gate C+ 锁最终协变量后再导出
block_multivariate_prognosis_harmonized <- function(ctx, ...) {
  cfg <- ctx$config
  dual_on <- isTRUE((cfg$dual_db %||% list())$enable)
  harm_opts <- cfg$multivariate_prognosis_harmonized %||% list()
  defer <- isTRUE(harm_opts$defer_until_cox_lock %||%
                    ((cfg$dual_db %||% list())$harmonization %||% list())$defer_s7_until_cox_lock %||%
                    TRUE)
  force_now <- isTRUE(ctx$results$dual_db_force_export_harmonized_multivar %||% FALSE) ||
    isTRUE(harm_opts$force_export %||% FALSE) ||
    isTRUE(ctx$results$dual_db_cox_covariates_locked %||% FALSE)

  if (dual_on && isTRUE(defer) && !force_now) {
    m2_hold <- as.character(ctx$results$Model2Factors %||% character(0))
    cli::cli_alert_info(
      "multivariate_prognosis_harmonized: Table S7 延后到 Gate C+ 最终协变量锁定后再出（当前池: {paste(m2_hold, collapse = ', ')}）"
    )
    ctx$results$multivar_harmonized_deferred <- TRUE
    return(ctx)
  }

  if (dual_on && !isTRUE(ctx$results$dual_db_covariate_harmonized)) {
    cli::cli_alert_warning(
      "multivariate_prognosis_harmonized: 尚未 dual_db_covariate_harmonized，仍以当前 Model2Factors 出表。"
    )
  }
  m2 <- as.character(ctx$results$Model2Factors %||% character(0))
  # 先应用固定锁定集（Gate C+ 传入），再做空检查
  fixed_m1 <- as.character(harm_opts$fixed_model1_factors %||% character(0))
  fixed_m2 <- as.character(harm_opts$fixed_model2_factors %||% character(0))
  fixed_m1 <- unique(fixed_m1[nzchar(fixed_m1)])
  fixed_m2 <- unique(fixed_m2[nzchar(fixed_m2)])
  if (length(fixed_m2)) {
    if (length(fixed_m1)) ctx$results$Model1Factors <- fixed_m1
    ctx$results$Model2Factors <- unique(c(ctx$results$Model1Factors %||% fixed_m1, fixed_m2))
    m2 <- ctx$results$Model2Factors
    cli::cli_alert_info("Table S7 强制使用锁定协变量: {paste(m2, collapse = ', ')}")
  }
  # 单库且未传入 Gate C+ 锁定集：用多因素 VIF final，不用 preset Model2
  if (!length(fixed_m2) &&
      exists("locked_mv_n_databases", mode = "function") &&
      locked_mv_n_databases(cfg) < 2L &&
      exists("locked_multivariable_covariates", mode = "function")) {
    locked <- locked_multivariable_covariates(ctx, cfg)
    if (length(locked$all)) {
      ctx$results$Model2Factors <- locked$all
      m2 <- locked$all
      cli::cli_alert_info("单库 Table S7 改用 vif_final_pass: {paste(m2, collapse = ', ')}")
    }
  }
  if (!length(m2)) {
    stop(
      "multivariate_prognosis_harmonized: Model2Factors 为空，请先 dual_db_covariate_harmonize / Gate C+。",
      call. = FALSE
    )
  }
  cli::cli_h2("多因素回归（双库最终统一协变量 Model2Factors）: {paste(m2, collapse = ', ')}")
  # 默认：固定读 Model2、不回写 factors、文件名体现 harmonized
  cap_locked <- if (exists("locked_multivariable_table_caption", mode = "function")) {
    locked_multivariable_table_caption(cfg)
  } else {
    "Multivariable Regression Analysis harmonized"
  }
  cfg$multivariate_prognosis_harmonized <- utils::modifyList(list(
    input_from = "Model2Factors",
    write_model_factors = FALSE,
    table_file_caption = cap_locked,
    table_title_caption = cap_locked,
    fail_on_index_ns = FALSE,
    pause_enable = FALSE
  ), harm_opts)
  ctx$config <- cfg
  ctx$results$.multivariate_mode_harmonized <- TRUE
  ctx <- block_multivariate_prognosis(ctx, ...)
  ctx$results$.multivariate_mode_harmonized <- FALSE
  ctx$results$multivar_harmonized_done <- TRUE
  ctx$results$multivar_harmonized_model2 <- as.character(ctx$results$Model2Factors %||% m2)
  ctx$results$multivar_harmonized_deferred <- FALSE
  ctx
}

register_block(
  "multivariate_prognosis_harmonized",
  block_multivariate_prognosis_harmonized,
  "Gate C+ 后双库最终统一协变量多因素表（Table S7）"
)
