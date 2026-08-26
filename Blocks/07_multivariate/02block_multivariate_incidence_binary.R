###############################################################################
#  multivariate_incidence_binary — 发病二分类多因素 Logistic OR（Table S6 池）。
#  multivariate_incidence_harmonized — VIF final 锁定协变量多因素（Table S8）。
#
#  register_block: "multivariate_incidence_binary"
#  register_block: "multivariate_incidence_harmonized"
#  前置: univariate_incidence_binary；harmonized 另需 multicollinearity_final
#  典型位置: ... multicollinearity_final → [dual_db_covariate_harmonize] →
#            multivariate_incidence_harmonized → logistic_*
#  配置: config$multivariate_incidence_binary / $multivariate_incidence_harmonized
#    table_number = 8L
#    协变量铁律: vif_final_pass（多因素 VIF p<0.05 幸存者 + 暴露），不用 preset
#    单库文件名: "Multivariable Regression Analysis"
#    双库文件名: "Multivariable Regression Analysis (dual-database harmonized covariates)"
###############################################################################

.mv02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.mv02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "multivariate_incidence_binary", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / 发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。", call. = FALSE)
}
.mv02_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff %||% bl_cfg$p_threshold
  if (is.null(cutoff)) .mv02_pause(ctx, "未配置 sig_cutoff", "在 config$multivariate_incidence_binary 设置 sig_cutoff", NULL)
  as.numeric(cutoff)[1L]
}



# ── 多因素 Logistic 回归（incidence 二分类）─────────────────────────────────────

.run_multivariate_binary <- function(vars, data, outcome_col, disease_label) {
  if (length(vars) == 0L) return(NULL)
  rhs <- paste(vars, collapse = " + ")
  fml <- stats::as.formula(paste0(outcome_col, " ~ ", rhs))
  fit <- tryCatch(
    stats::glm(fml, data = data, family = stats::binomial(link = "logit")),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  co <- s$coefficients
  nm <- rownames(co)
  if (is.null(nm) || length(nm) == 0L) return(NULL)
  est <- co[, "Estimate", drop = TRUE]
  se  <- co[, "Std. Error", drop = TRUE]
  or  <- exp(est)
  lo  <- exp(est - 1.96 * se)
  hi  <- exp(est + 1.96 * se)
  data.frame(
    Variable = nm,
    OR       = as.numeric(or),
    CI_lo    = as.numeric(lo),
    CI_hi    = as.numeric(hi),
    P        = as.numeric(co[, "Pr(>|z|)", drop = TRUE]),
    stringsAsFactors = FALSE
  )
}

# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.mv02_extract_base_varname <- function(var_names, all_vars) {
  base_names <- sapply(var_names, function(vn) {
    for (av in all_vars[order(-nchar(all_vars))]) {
      if (vn == av) return(av)
      if (startsWith(vn, av)) return(av)
      pattern <- paste0("^", av, "\\d*$")
      if (grepl(pattern, vn, perl = TRUE)) return(av)
    }
    vn
  })
  unique(base_names)
}

# VIF 阈值：若下游接 feature_selection（enable=TRUE），用 10；否则用 vif_threshold_strict（默认 4）
.mv02_pipeline_effective_vif_thresholds <- function(cfg) {
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
.mv02_calculate_vif_from_vars <- function(vars, data) {
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

.mv02_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mv02_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mv02_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mv02_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mv02_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  thr <- .mv02_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }
  res0 <- .mv02_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mv02_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mv02_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro) next
    trial <- setdiff(vars, d1)
    if (.mv02_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- intersect(c("Weight", "Height"), anthro)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 2L &&
      .mv02_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
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

.mv02_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mv02_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mv02_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mv02_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .mv02_pipeline_effective_vif_thresholds(cfg)$strict
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

# 发表表行顺序：own 库保留数据列序，否则按 .default_table1_sections（Table 1 分组）


.multivariate_incidence_binary_export_table_s2 <- function(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, tb1, tb2, study_type, classification_mode,
    force_continuous_vars = character(0)) {
  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .mv02_extract_base_varname(c(vn), predictor_vars)
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
  } else if (classification_mode == "binary") {
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
    as.character(.mv02_extract_base_varname(c(vn), predictor_vars)[1])
  }, character(1))
  # 发表表行顺序与 Table 1 分组保持一致（baseline$table1_sections 或默认分组）
  base_order_tbl1 <- order_vars_like_table1(unique(as.character(m$base_var)), ctx, cfg, data)
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
  if (FALSE) {
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
      as.character(.mv02_extract_base_varname(c(vn), predictor_vars)[1])
    }, character(1))
    uvar <- uvar[order(match(base_ord_u, predictor_vars, nomatch = 999999L), uvar)]
    bases_ordered <- unique(vapply(uvar, function(vn) {
      as.character(.mv02_extract_base_varname(c(vn), predictor_vars)[1])
    }, character(1)))
    bases_ordered <- order_vars_like_table1(bases_ordered, ctx, cfg, data)

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
          b <- as.character(.mv02_extract_base_varname(c(su), predictor_vars)[1])
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
        identical(as.character(.mv02_extract_base_varname(c(vn), predictor_vars)[1]), bv)
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
    b_ord <- order_vars_like_table1(b_uni, ctx, cfg, data)
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
        normal_vars <- ctx$results$normal_vars %||% character(0)
        if (bv %in% normal_vars) {
          all_txt <- paste0(fmt_num(mean(x, na.rm = TRUE)),
                            " \u00b1 ",
                            fmt_num(stats::sd(x, na.rm = TRUE)))
        } else {
          all_txt <- paste0(
            fmt_num(stats::median(x, na.rm = TRUE)), " (",
            fmt_num(stats::quantile(x, 0.25, na.rm = TRUE)), ", ",
            fmt_num(stats::quantile(x, 0.75, na.rm = TRUE)), ")")
        }
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
    bases <- order_vars_like_table1(bases, ctx, cfg, data)
    for (bv in bases) {
      x <- data[[bv]]
      lab_char <- gsub("_", " ", bv)
      sub_m <- m[m$base_var == bv, , drop = FALSE]
      is_cont <- (bv %in% force_continuous_vars) ||
        (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)

      if (is_cont) {
        normal_vars <- ctx$results$normal_vars %||% character(0)
        if (bv %in% normal_vars) {
          stat_label <- "Mean \u00b1 SD"
          all_txt <- paste0(fmt_num(mean(x, na.rm = TRUE)),
                            " \u00b1 ",
                            fmt_num(stats::sd(x, na.rm = TRUE)))
        } else {
          stat_label <- "Median (Q1, Q3)"
          all_txt <- paste0(
            fmt_num(stats::median(x, na.rm = TRUE)), " (",
            fmt_num(stats::quantile(x, 0.25, na.rm = TRUE)), ", ",
            fmt_num(stats::quantile(x, 0.75, na.rm = TRUE)), ")")
        }
        mr <- sub_m[sub_m$Variable == bv, , drop = FALSE]
        u1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr$Est_u[1], mr$Lo_u[1], mr$Hi_u[1], mr$P_u[1]) else ""
        m1 <- if (TRUE && nrow(mr) >= 1L) {
          .fmt_ci_p(mr$Est_m[1], mr$Lo_m[1], mr$Hi_m[1], mr$P_m[1])
        } else {
          ""
        }
        pub_rows[[length(pub_rows) + 1L]] <- data.frame(
          Characteristic = lab_char,
          Statistic = stat_label,
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


  file_caption <- as.character(
    mv_cfg$table_file_caption %||% "Multivariable Regression Analysis"
  )[1L]
  if (!nzchar(file_caption)) file_caption <- "Multivariable Regression Analysis"
  title_caption <- as.character(mv_cfg$table_title_caption %||% base_title)[1L]
  if (!nzchar(title_caption)) title_caption <- base_title
  fixed_sno <- suppressWarnings(as.integer(mv_cfg$table_number %||% NA_integer_)[1L])
  if (isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    title_caption <- file_caption
    if (!is.finite(fixed_sno) || fixed_sno < 1L) fixed_sno <- 8L
  }
  if (is.finite(fixed_sno) && fixed_sno >= 1L) {
    pref <- pub_prefix("supp_table", fixed_sno)
    title_mv <- paste(pref, title_caption)
    stem_f <- paste(pref, file_caption)
    filepath_mv <- .inject_db_into_pub_filepath(
      file.path(ctx$output_dir_tables, paste0(stem_f, ".xlsx"))
    )
    filepath_mv <- .pub_path_with_slot_label(ctx, filepath_mv)
    if (exists("pub_bump_supp_table_min", mode = "function")) {
      pub_bump_supp_table_min(fixed_sno)
    } else {
      cur <- as.integer(.pub_state$supp_table %||% 0L)
      if (cur < fixed_sno) .pub_state$supp_table <- fixed_sno
    }
  } else {
    pub_mv <- pub_pair(
      ctx, ctx$output_dir_tables, "supp_table",
      title_caption, file_caption, "xlsx"
    )
    title_mv <- pub_mv$title
    filepath_mv <- pub_mv$filepath
  }
  if (exists("multivariate_pub_drop_univariable_if_needed", mode = "function")) {
    out_table <- multivariate_pub_drop_univariable_if_needed(out_table, cfg)
    # 宽表双行表头同步删列
    h1 <- attr(out_table, "header_row1")
    h2 <- attr(out_table, "header_row2")
    if (!is.null(h1) && length(h1) != ncol(out_table)) attr(out_table, "header_row1") <- NULL
    if (!is.null(h2) && length(h2) != ncol(out_table)) attr(out_table, "header_row2") <- NULL
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

block_multivariate_incidence_binary <- function(ctx, ...) {
  suppressPackageStartupMessages({})

  cfg     <- ctx$config
  up_res  <- pipeline_upstream_modeling_data(ctx)
  data    <- up_res$data
  if (is.null(data)) stop("No data found. Run imputation or data_clean first.")
    if (tolower(ctx$config$project$study_type %||% "") != "incidence") stop("需要 study_type=incidence")
  if (!identical(ctx$config$project$classification_mode %||% "binary", "binary")) stop("需要 classification_mode=binary")
  if (.is_nhanes_db(ctx$config)) stop("NHANES 请用 multivariate_incidence_binary")

  univar_df <- ctx$results$univar_coef
  if (is.null(univar_df) || !is.data.frame(univar_df) || nrow(univar_df) == 0L) {
    stop("请先运行对应 univariate_* 块以生成 ctx$results$univar_coef")
  }

  tb1_display <- as.character(ctx$results$tb1 %||% character(0))
  tb1_display <- unique(tb1_display[nzchar(tb1_display)])
  if (!length(tb1_display)) stop("单因素显著变量 tb1 为空，请先运行 univariate_*")

  mv_cfg <- cfg$multivariate_incidence_binary %||% list()
  bl_cfg <- mv_cfg
  p_threshold <- .mv02_resolve_sig_cutoff(bl_cfg, ctx)
  input_from <- as.character(mv_cfg$input_from %||% "vif_screen_pass")[1L]
  mv_input <- switch(input_from,
    vif_screen_pass = as.character(ctx$results$vif_screen_pass %||% character(0)),
    vif_final_pass = as.character(ctx$results$vif_final_pass %||% character(0)),
    tb_screen = as.character(ctx$results$tb_screen %||% character(0)),
    tb1 = tb1_display,
    Model2Factors = as.character(ctx$results$Model2Factors %||% character(0)),
    model2_factors = as.character(ctx$results$Model2Factors %||% character(0)),
    as.character(ctx$results$univar_features %||% tb1_display)
  )
  mv_input <- unique(mv_input[nzchar(mv_input)])
  if (isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    locked <- locked_multivariable_covariates(ctx, cfg)
    mv_input <- locked$all
    tb1_display <- locked$all
    input_from <- "vif_final_pass"
    if (exists("pipeline_union_model3_required", mode = "function")) {
      ix <- if (exists("pipeline_index_exposure_var", mode = "function")) {
        pipeline_index_exposure_var(cfg)
      } else {
        NULL
      }
      before <- mv_input
      mv_input <- pipeline_union_model3_required(mv_input, cfg, names(data), ix)
      added <- setdiff(mv_input, before)
      if (length(added)) {
        cli::cli_alert_info("Table S8 并入 Model3 必调: {paste(added, collapse = ', ')}")
      }
    }
    tb1_display <- unique(c(tb1_display, mv_input))
    cli::cli_alert_info(
      "Table S8 锁定协变量 (vif_final_pass): {paste(mv_input, collapse = ', ')}"
    )
  }
  excluded_predictors <- unique(c(
    as.character(mv_cfg$excluded_predictors %||% character(0)),
    if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
      pipeline_covariate_analysis_exclude_vars(cfg)
    } else {
      character(0)
    }
  ))
  mc_cfg <- cfg$multicollinearity %||% list()
  mv_excl <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(cfg$data$id_column %||% character(0)),
    excluded_predictors
  ))
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    mv_excl <- setdiff(mv_excl, pipeline_index_exposure_var(cfg))
  }
  mv_excl <- mv_excl[nzchar(mv_excl)]
  if (length(mv_excl)) {
    dropped_mv <- intersect(mv_input, mv_excl)
    if (length(dropped_mv)) {
      cli::cli_alert_info("multivariate_incidence_binary: 排除非分析变量: {paste(dropped_mv, collapse = ', ')}")
    }
    mv_input <- setdiff(mv_input, mv_excl)
  }
  # 强制纳入暴露指标，避免多因素发表表暴露行为空
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    ix_exp <- pipeline_index_exposure_var(cfg)
    if (length(ix_exp) && nzchar(ix_exp[1L])) {
      mv_input <- unique(c(ix_exp[1L], mv_input))
    }
  }
  if (!length(mv_input)) {
    stop(
      "多因素输入变量为空 (config$multivariate_incidence_binary$input_from='", input_from,
      "')，请先运行 univariate_incidence_binary + multicollinearity_screen。",
      call. = FALSE
    )
  }
  required_predictors_cfg <- mv_cfg$required_predictors %||% character(0)
  demo_keywords <- mv_cfg$demo_keywords %||% character(0)
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  study_type <- "incidence"
  classification_mode <- cfg$project$classification_mode %||% "binary"
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  reference_group <- cfg$project$reference_group
  predictor_vars <- setdiff(names(data), outcome_col)
  excluded_predictors <- intersect(excluded_predictors, names(data))
  predictor_vars <- setdiff(predictor_vars, excluded_predictors)
  .mv02_extract_base_varname <- .mv02_extract_base_varname

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  if (study_type == "incidence" && identical(classification_mode, "binary")) {
    data[[outcome_col]] <- as.integer(data[[outcome_col]] == disease_label)
  }

  cli::cli_h2("多因素回归（基于 {input_from}，{length(mv_input)} 个变量）")
  mv_input <- intersect(mv_input, names(data))
  if (!length(mv_input)) {
    stop("多因素输入在排除暴露组分后为空。", call. = FALSE)
  }
  multivar_result <- .run_multivariate_binary(mv_input, data, outcome_col, disease_label)
  tb2 <- character(0)
  if (!is.null(multivar_result) && nrow(multivar_result) > 0) {
    tb2 <- .mv02_extract_base_varname(multivar_result$Variable[multivar_result$P < p_threshold], mv_input)
  }
  cli::cli_alert_success("多因素显著变量 tb2 (P < {p_threshold}): {length(tb2)} 个")

  model2_base <- if (length(tb2) > 0L) tb2 else mv_input
  required_predictors <- intersect(required_predictors_cfg, names(data))
  if (study_type == "prognosis") {
    required_predictors <- setdiff(required_predictors, c(time_var, event_var))
  } else {
    required_predictors <- setdiff(required_predictors, outcome_col)
  }
  Model2Factors <- unique(c(model2_base, required_predictors))
  Model2Factors <- intersect(Model2Factors, names(data))
  demo_pattern <- paste(demo_keywords, collapse = "|")
  Model1Factors <- Model2Factors[grepl(demo_pattern, Model2Factors, ignore.case = TRUE)]
  Model1Factors <- intersect(Model1Factors, names(data))

  write_mf <- isTRUE(mv_cfg$write_model_factors %||% TRUE)
  if (!isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    cli::cli_h2("BMI/Weight/Height 人体测量 VIF 协调")
    ar_anthro <- .mv02_apply_anthropometric_vif_resolution(
      Model2Factors, data, cfg, ctx, "multivariate_incidence_binary"
    )
    ctx <- ar_anthro$ctx
    if (length(ar_anthro$dropped) > 0L) {
      dropped_anthro <- ar_anthro$dropped
      tb2 <- setdiff(tb2, dropped_anthro)
      Model1Factors <- setdiff(Model1Factors, dropped_anthro)
      Model2Factors <- ar_anthro$kept
      univar_df <- .mv02_filter_coef_df_by_dropped_vars(univar_df, dropped_anthro, predictor_vars)
      multivar_result <- .mv02_filter_coef_df_by_dropped_vars(multivar_result, dropped_anthro, predictor_vars)
    }
  }

  if (length(Model2Factors) == 0) {
    ctx$results$pause_point <- list(
      block = "multivariate_incidence_binary",
      reason = "Model2Factors 为空",
      suggestion = paste0("检查多因素结果或放宽 config$multivariate_incidence_binary$sig_cutoff (当前: ", p_threshold, ")"),
      data_snapshot = utils::head(multivar_result, 5)
    )
    stop("PAUSE_FOR_USER_DECISION: Model2Factors 为空。")
  }

  if (exists("pipeline_strip_index_from_model_factors", mode = "function")) {
    stripped <- pipeline_strip_index_from_model_factors(Model1Factors, Model2Factors, cfg)
    Model1Factors <- stripped$M1
    Model2Factors <- stripped$M2
  }
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    merged <- pipeline_merge_force_covariates(Model1Factors, Model2Factors, names(data), cfg)
    Model1Factors <- merged$M1
    Model2Factors <- merged$M2
  }

  if (isTRUE(write_mf)) {
    ctx <- save_result(ctx, "tb2_multivar_features", tb2, "D05_Multivariable_Features.RData")
    ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
    ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
    writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
    writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))
  }

  .multivariate_incidence_binary_export_table_s2(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, tb1_display, tb2, study_type, classification_mode,
    force_continuous_vars = force_continuous_vars)

  if (isTRUE(write_mf)) {
    ctx$results$tb2 <- tb2
    ctx$results$multivar_features <- tb2
    ctx$results$univar_features <- mv_input
    ctx$results$Model1Factors <- Model1Factors
    ctx$results$Model2Factors <- Model2Factors
  }
  cli::cli_alert_success("多因素分析完成")
  ctx
}

register_block("multivariate_incidence_binary", block_multivariate_incidence_binary, "multivariate_incidence_binary")

#' VIF final 锁定协变量多因素表（发病 Table S8；单库无 dual-database 括号）
block_multivariate_incidence_harmonized <- function(ctx, ...) {
  cfg <- ctx$config
  harm_opts <- cfg$multivariate_incidence_harmonized %||% list()
  locked <- locked_multivariable_covariates(ctx, cfg)
  if (!length(locked$covariates) && !length(locked$all)) {
    stop(
      "multivariate_incidence_harmonized: vif_final_pass 为空，请先 multicollinearity_final。",
      call. = FALSE
    )
  }
  cap <- as.character(
    harm_opts$table_file_caption %||% locked_multivariable_table_caption(cfg)
  )[1L]
  sno <- suppressWarnings(as.integer(harm_opts$table_number %||% 8L)[1L])
  if (!is.finite(sno) || sno < 1L) sno <- 8L
  cfg$multivariate_incidence_binary <- utils::modifyList(
    cfg$multivariate_incidence_binary %||% list(),
    list(
      input_from = "vif_final_pass",
      write_model_factors = FALSE,
      table_number = sno,
      table_file_caption = cap,
      table_title_caption = cap,
      pause_enable = FALSE
    )
  )
  ctx$config <- cfg
  ctx$results$.multivariate_mode_harmonized <- TRUE
  ctx <- block_multivariate_incidence_binary(ctx, ...)
  ctx$results$.multivariate_mode_harmonized <- FALSE
  ctx$results$multivar_harmonized_done <- TRUE
  ctx$results$multivar_harmonized_model2 <- locked$all
  ctx
}

register_block(
  "multivariate_incidence_harmonized",
  block_multivariate_incidence_harmonized,
  "VIF-final locked multivariable table (incidence Table S8)"
)
