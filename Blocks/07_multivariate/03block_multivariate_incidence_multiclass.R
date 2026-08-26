###############################################################################
#  multivariate_incidence_multiclass — 发病多分类多因素 multinomial OR（Table S2）。
#
#  register_block: "multivariate_incidence_multiclass"
#  前置: univariate_incidence_multiclass；univar_coef、tb1
#  # ── 配置 config$multivariate_incidence_multiclass ───────────────────────────
#  sig_cutoff、pause_*、参照水平设置；multiclass 结局 multinomial 拟合
#  写: Table S2 多因素 OR；块内 bl_cfg <- cfg$multivariate_incidence_multiclass
###############################################################################

.mvi03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.mvi03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "multivariate_incidence_multiclass", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / 发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。", call. = FALSE)
}
.mvi03_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff %||% bl_cfg$p_threshold
  if (is.null(cutoff)) .mvi03_pause(ctx, "未配置 sig_cutoff", "在 config$multivariate_incidence_multiclass 设置 sig_cutoff", NULL)
  as.numeric(cutoff)[1L]
}



# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.mvi03_extract_base_varname <- function(var_names, all_vars) {
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
.mvi03_pipeline_effective_vif_thresholds <- function(cfg) {
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
.mvi03_calculate_vif_from_vars <- function(vars, data) {
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

.mvi03_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mvi03_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mvi03_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mvi03_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mvi03_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  thr <- .mvi03_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }
  res0 <- .mvi03_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mvi03_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mvi03_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro) next
    trial <- setdiff(vars, d1)
    if (.mvi03_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- intersect(c("Weight", "Height"), anthro)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 2L &&
      .mvi03_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
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

.mvi03_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mvi03_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mvi03_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mvi03_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .mvi03_pipeline_effective_vif_thresholds(cfg)$strict
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


.multivariate_incidence_multiclass_export_table_s2 <- function(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, tb1, study_type, classification_mode) {
  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .mvi03_extract_base_varname(c(vn), predictor_vars)
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
    as.character(.extract_base_varname(c(vn), predictor_vars)[1])
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
  disc_n <- uv_cfg$discrete_max_levels %||% 5L

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
      as.character(.extract_base_varname(c(vn), predictor_vars)[1])
    }, character(1))
    uvar <- uvar[order(match(base_ord_u, predictor_vars, nomatch = 999999L), uvar)]
    bases_ordered <- unique(vapply(uvar, function(vn) {
      as.character(.extract_base_varname(c(vn), predictor_vars)[1])
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
          b <- as.character(.extract_base_varname(c(su), predictor_vars)[1])
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
        identical(as.character(.extract_base_varname(c(vn), predictor_vars)[1]), bv)
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


  pub_mv <- pub_pair(
    ctx, ctx$output_dir_tables, "supp_table",
    base_title, "Multivariable Regression Analysis", "xlsx"
  )
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

.mvi03_run_multivariate_multinomial <- function(vars, data, outcome_col, reference_group) {
  if (length(vars) == 0) return(NULL)
  data[[outcome_col]] <- factor(data[[outcome_col]])
  data[[outcome_col]] <- stats::relevel(data[[outcome_col]], ref = reference_group)
  fml <- stats::as.formula(paste(outcome_col, "~", paste(vars, collapse = " + ")))
  fit <- tryCatch(
    nnet::multinom(fml, data = data, trace = FALSE, maxit = 500),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  smry <- summary(fit)$coefficients
  se   <- summary(fit)$standard.errors
  z    <- smry / se
  p    <- 2 * (1 - stats::pnorm(abs(z)))
  ci_lo <- exp(smry - 1.96 * se)
  ci_hi <- exp(smry + 1.96 * se)
  or    <- exp(smry)
  results <- list()
  for (i in seq_len(nrow(smry))) {
    group_name <- rownames(smry)[i]
    for (j in seq_len(ncol(smry))) {
      var_name <- colnames(smry)[j]
      if (var_name == "(Intercept)") next
      results[[length(results) + 1L]] <- data.frame(
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

block_multivariate_incidence_multiclass <- function(ctx, ...) {
  suppressPackageStartupMessages({})

  cfg     <- ctx$config
  data    <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run imputation or data_clean first.")
    if (tolower(ctx$config$project$study_type %||% "") != "incidence") stop("需要 study_type=incidence")
  if (!identical(ctx$config$project$classification_mode %||% "binary", "multiclass")) stop("需要 classification_mode=multiclass")
  if (.is_nhanes_db(ctx$config)) stop("NHANES 请用 multivariate_incidence_multiclass")

  univar_df <- ctx$results$univar_coef
  if (is.null(univar_df) || !is.data.frame(univar_df) || nrow(univar_df) == 0L) {
    stop("请先运行对应 univariate_* 块以生成 ctx$results$univar_coef")
  }

  tb1_in <- as.character(ctx$results$tb1 %||% ctx$results$univar_features %||% character(0))
  tb1_in <- unique(tb1_in[nzchar(tb1_in)])
  if (!length(tb1_in)) stop("单因素显著变量 tb1 为空，请先运行 univariate_*")

  mv_cfg <- cfg$multivariate_incidence_multiclass %||% list()
  bl_cfg <- mv_cfg
  p_threshold <- .mvi03_resolve_sig_cutoff(bl_cfg, ctx)
  excluded_predictors <- mv_cfg$excluded_predictors %||% character(0)
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
  .extract_base_varname <- .mvi03_extract_base_varname

  reference_group <- cfg$project$reference_group

  cli::cli_h2("多因素回归（基于单因素 tb1）")
  tb1_in <- intersect(tb1_in, names(data))
  multivar_result <- .mvi03_run_multivariate_multinomial(tb1_in, data, outcome_col, reference_group)
  tb2 <- character(0)
  if (!is.null(multivar_result) && nrow(multivar_result) > 0) {
    tb2 <- .extract_base_varname(multivar_result$Variable[multivar_result$P < p_threshold], tb1_in)
  }
  cli::cli_alert_success("多因素显著变量 tb2 (P < {p_threshold}): {length(tb2)} 个")

  model2_base <- if (length(tb2) > 0L) tb2 else tb1_in
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

  cli::cli_h2("BMI/Weight/Height 人体测量 VIF 协调")
  ar_anthro <- .mvi03_apply_anthropometric_vif_resolution(
    Model2Factors, data, cfg, ctx, "multivariate_incidence_multiclass"
  )
  ctx <- ar_anthro$ctx
  if (length(ar_anthro$dropped) > 0L) {
    dropped_anthro <- ar_anthro$dropped
    tb2 <- setdiff(tb2, dropped_anthro)
    Model1Factors <- setdiff(Model1Factors, dropped_anthro)
    Model2Factors <- ar_anthro$kept
    univar_df <- .mvi03_filter_coef_df_by_dropped_vars(univar_df, dropped_anthro, predictor_vars)
    multivar_result <- .mvi03_filter_coef_df_by_dropped_vars(multivar_result, dropped_anthro, predictor_vars)
  }

  if (length(Model2Factors) == 0) {
    ctx$results$pause_point <- list(
      block = "multivariate_incidence_multiclass",
      reason = "Model2Factors 为空",
      suggestion = paste0("检查多因素结果或放宽 config$multivariate_incidence_multiclass$sig_cutoff (当前: ", p_threshold, ")"),
      data_snapshot = utils::head(multivar_result, 5)
    )
    stop("PAUSE_FOR_USER_DECISION: Model2Factors 为空。")
  }

  ctx <- save_result(ctx, "tb2_multivar_features", tb2, "D05_Multivariable_Features.RData")
  ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
  ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
  writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
  writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))

  .multivariate_incidence_multiclass_export_table_s2(ctx, cfg, mv_cfg, data, predictor_vars,
    univar_df, multivar_result, tb1_in, study_type, classification_mode)

  ctx$results$tb2 <- tb2
  ctx$results$multivar_features <- tb2
  ctx$results$univar_features <- tb1_in
  ctx$results$Model1Factors <- Model1Factors
  ctx$results$Model2Factors <- Model2Factors
  cli::cli_alert_success("多因素分析完成")
  ctx
}

register_block("multivariate_incidence_multiclass", block_multivariate_incidence_multiclass, "multivariate_incidence_multiclass")
