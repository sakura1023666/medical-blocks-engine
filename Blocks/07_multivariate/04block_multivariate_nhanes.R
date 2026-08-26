###############################################################################
#  multivariate_nhanes — NHANES 加权多因素 svyglm（Table S5 变量池）。
#  multivariate_nhanes_harmonized — VIF final 锁定协变量多因素（Table S7；
#      单库无 dual-database 括号；对齐预后 Table S7 / 发病 regular Table S8）。
#
#  register_block: "multivariate_nhanes"
#  register_block: "multivariate_nhanes_harmonized"
#  典型流水线: ... multicollinearity_nhanes_final → dual_db_covariate_harmonize →
#              multivariate_nhanes_harmonized → logistic_*
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  requires_blocks   = c("obj")           # ctx$results$nhanes_design
#  requires_packages = c("survey")
#  require_data      = ctx$results$nhanes_design
#  require_study     = incidence + classification_mode binary
#
#  # ── 配置 config$multivariate_nhanes ───────────────────────────────────────
#  sig_cutoff / p_threshold、tb2_threshold、discrete_max_levels、
#  model1_candidate_names、pause_enable 与各 pause_on_*、pause_min_sig_vars
#  调查设计权重: config$nhanes（与 obj 块一致）
#
#  # ── 读写 ctx ─────────────────────────────────────────────────────────────
#  策略 B: 写入 univar_features / multivar_features 供下游 ROC、RCS 等
###############################################################################

.mvn04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  val <- bl_cfg[[key]]
  if (is.null(val)) return(isTRUE(default))
  isTRUE(val)
}

.mvn04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "multivariate_nhanes",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: Negative result or anomaly detected. See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.mvn04_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff
  if (is.null(cutoff)) cutoff <- bl_cfg$p_threshold
  if (is.null(cutoff)) {
    .mvn04_pause(
      ctx,
      "未配置 config$multivariate_nhanes$sig_cutoff（或 legacy p_threshold）。",
      "在 config$multivariate_nhanes 中设置 sig_cutoff。",
      NULL
    )
  }
  as.numeric(cutoff)[1L]
}

.mvn04_svy_coef_to_df <- function(fit) {
  sm <- summary(fit)$coefficients
  rn <- rownames(sm)[rownames(sm) != "(Intercept)"]
  if (!length(rn)) return(NULL)
  pr_i <- grep("^Pr\\(", colnames(sm))
  pcol <- if (length(pr_i)) pr_i[1L] else NA_integer_
  t_i <- grep("^(t|z) value$", colnames(sm), ignore.case = TRUE)[1L]
  do.call(rbind, lapply(rn, function(r) {
    est <- sm[r, "Estimate", drop = TRUE]
    se  <- sm[r, "Std. Error", drop = TRUE]
    pv  <- if (is.finite(pcol)) suppressWarnings(as.numeric(sm[r, pcol])) else NA_real_
    # survey df.residual<=0 时 Pr 常为 NaN：用 Wald z 回退，避免发表表丢掉 p=
    if (!is.finite(pv) && is.finite(t_i)) {
      tv <- suppressWarnings(as.numeric(sm[r, t_i]))
      if (is.finite(tv)) pv <- 2 * stats::pnorm(-abs(tv))
    }
    if (!is.finite(pv) && is.finite(est) && is.finite(se) && se > 0) {
      pv <- 2 * stats::pnorm(-abs(est / se))
    }
    data.frame(
      Variable = r,
      OR       = exp(est),
      CI_lo    = exp(est - 1.96 * se),
      CI_hi    = exp(est + 1.96 * se),
      P        = pv,
      stringsAsFactors = FALSE
    )
  }))
}

# 逐变量加权多因素：每个变量 + 其余协变量（与 incidence_binary 一致，非一次性全变量 joint 筛选）
.mvn04_run_multivariate_svy <- function(vars, design, all_vars) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(design$variables)]
  if (!length(vars)) return(NULL)
  rows <- list()
  for (v in vars) {
    others <- setdiff(vars, v)
    rhs <- if (length(others)) paste(c(v, others), collapse = " + ") else v
    fml <- stats::as.formula(paste0("Disease_Group ~ ", rhs))
    fit <- tryCatch(
      survey::svyglm(fml, design = design, family = stats::quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    part <- .mvn04_svy_coef_to_df(fit)
    if (is.null(part) || !nrow(part)) next
    keep <- vapply(part$Variable, function(rn) {
      identical(
        as.character(.mvn04_extract_base_varname(c(rn), all_vars)[1L]),
        v
      )
    }, logical(1))
    part <- part[keep, , drop = FALSE]
    if (nrow(part)) rows[[length(rows) + 1L]] <- part
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}



# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.mvn04_extract_base_varname <- function(var_names, all_vars) {
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
.mvn04_pipeline_effective_vif_thresholds <- function(cfg) {
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
.mvn04_calculate_vif_from_vars <- function(vars, data) {
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

.mvn04_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mvn04_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mvn04_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mvn04_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mvn04_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "BMI"
  )[1L]
  protected <- unique(c(
    as.character(ar$protect_vars %||% character(0)),
    index_var
  ))
  try_one <- unique(as.character(ar$prefer_drop_one_order %||% c("Weight", "Height")))
  thr <- .mvn04_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }

  if (index_var %in% anthro) {
    drop_wh <- intersect(c("Weight", "Height"), anthro)
    if (length(drop_wh)) {
      return(list(
        kept = setdiff(vars, drop_wh),
        dropped = drop_wh,
        strategy = "drop_weight_height_keep_index",
        anthro_max_vif = NULL
      ))
    }
  }

  res0 <- .mvn04_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mvn04_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mvn04_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro || d1 %in% protected) next
    trial <- setdiff(vars, d1)
    if (.mvn04_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- setdiff(intersect(c("Weight", "Height"), anthro), protected)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 1L &&
      .mvn04_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
    return(list(
      kept = trial2, dropped = drop_wh,
      strategy = if (length(drop_wh) >= 2L) "drop_weight_and_height" else paste0("drop_one:", drop_wh[1L]),
      anthro_max_vif = anthro_max
    ))
  }
  to_drop <- setdiff(anthro, protected)
  if (length(to_drop)) {
    return(list(
      kept = setdiff(vars, to_drop),
      dropped = to_drop,
      strategy = "drop_non_protected_anthro",
      anthro_max_vif = anthro_max
    ))
  }
  list(kept = vars, dropped = character(0), strategy = "unresolved", anthro_max_vif = anthro_max)
}

.mvn04_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mvn04_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mvn04_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mvn04_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .mvn04_pipeline_effective_vif_thresholds(cfg)$strict
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

# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.mvn04_extract_base_varname <- function(var_names, all_vars) {
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
.mvn04_pipeline_effective_vif_thresholds <- function(cfg) {
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
.mvn04_calculate_vif_from_vars <- function(vars, data) {
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

.mvn04_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mvn04_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mvn04_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mvn04_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mvn04_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "BMI"
  )[1L]
  protected <- unique(c(
    as.character(ar$protect_vars %||% character(0)),
    index_var
  ))
  try_one <- unique(as.character(ar$prefer_drop_one_order %||% c("Weight", "Height")))
  thr <- .mvn04_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }

  if (index_var %in% anthro) {
    drop_wh <- intersect(c("Weight", "Height"), anthro)
    if (length(drop_wh)) {
      return(list(
        kept = setdiff(vars, drop_wh),
        dropped = drop_wh,
        strategy = "drop_weight_height_keep_index",
        anthro_max_vif = NULL
      ))
    }
  }

  res0 <- .mvn04_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mvn04_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mvn04_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro || d1 %in% protected) next
    trial <- setdiff(vars, d1)
    if (.mvn04_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- setdiff(intersect(c("Weight", "Height"), anthro), protected)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 1L &&
      .mvn04_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
    return(list(
      kept = trial2, dropped = drop_wh,
      strategy = if (length(drop_wh) >= 2L) "drop_weight_and_height" else paste0("drop_one:", drop_wh[1L]),
      anthro_max_vif = anthro_max
    ))
  }
  to_drop <- setdiff(anthro, protected)
  if (length(to_drop)) {
    return(list(
      kept = setdiff(vars, to_drop),
      dropped = to_drop,
      strategy = "drop_non_protected_anthro",
      anthro_max_vif = anthro_max
    ))
  }
  list(kept = vars, dropped = character(0), strategy = "unresolved", anthro_max_vif = anthro_max)
}

.mvn04_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mvn04_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mvn04_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mvn04_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .mvn04_pipeline_effective_vif_thresholds(cfg)$strict
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



.mvn04_publish_table_s2_nhanes <- function(
    ctx, cfg, mv_cfg, design, data_pub, pred_vars,
    univar_df, multivar_result, tb1, normal_vars = character(0),
    skewed_vars = character(0)) {
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  disc_n <- mv_cfg$discrete_max_levels %||% 5L
  if (is.null(univar_df) || nrow(univar_df) == 0L) return(invisible(FALSE))
  row_base <- vapply(univar_df$Variable, function(vn) {
    as.character(.mvn04_extract_base_varname(c(vn), pred_vars)[1L])
  }, character(1L))
  tb_show <- unique(as.character(tb1[nzchar(tb1)]))
  if (isTRUE((cfg$environment_batch %||% list())$include_vocs_in_clinical_screen) &&
      exists("environment_table1_voc_vars", mode = "function")) {
    voc_show <- intersect(environment_table1_voc_vars(data_pub, cfg), unique(row_base))
    tb_show <- unique(c(tb_show, voc_show))
  }
  # 强制保留暴露指标行（与 incidence multivariate 一致）
  keep_ix_row <- isTRUE((cfg$prediction %||% list())$keep_index_vars_in_regression_table %||% TRUE)
  if (isTRUE(keep_ix_row)) {
    pred_tbl_ix <- as.character((cfg$prediction %||% list())$index_vars %||% character(0))
    if (exists("pipeline_index_exposure_var", mode = "function")) {
      pred_tbl_ix <- unique(c(pred_tbl_ix, pipeline_index_exposure_var(cfg)))
    }
    pred_tbl_ix <- unique(pred_tbl_ix[nzchar(pred_tbl_ix)])
    tb_show <- unique(c(tb_show, intersect(pred_tbl_ix, unique(row_base))))
  }
  uni_slice <- univar_df[row_base %in% tb_show, , drop = FALSE]
  if (nrow(uni_slice) == 0L) uni_slice <- univar_df
  uni_key <- data.frame(
    Variable = uni_slice$Variable, Group = rep("", nrow(uni_slice)),
    Est_u = uni_slice$OR, Lo_u = uni_slice$CI_lo, Hi_u = uni_slice$CI_hi, P_u = uni_slice$P,
    stringsAsFactors = FALSE
  )
  multi_key <- NULL
  if (!is.null(multivar_result) && nrow(multivar_result) > 0L) {
    multi_key <- data.frame(
      Variable = multivar_result$Variable, Group = rep("", nrow(multivar_result)),
      Est_m = multivar_result$OR, Lo_m = multivar_result$CI_lo,
      Hi_m = multivar_result$CI_hi, P_m = multivar_result$P,
      stringsAsFactors = FALSE
    )
  }
  m <- if (is.null(multi_key)) {
    cbind(uni_key, Est_m = NA_real_, Lo_m = NA_real_, Hi_m = NA_real_, P_m = NA_real_)
  } else {
    merge(uni_key, multi_key, by = c("Variable", "Group"), all = TRUE, sort = FALSE)
  }
  m$base_var <- vapply(m$Variable, function(vn) {
    as.character(.mvn04_extract_base_varname(c(vn), pred_vars)[1L])
  }, character(1L))
  .fmt_p_inline <- function(p) {
    if (length(p) != 1L) return("")
    p <- suppressWarnings(as.numeric(p))
    if (!is.finite(p)) return("")
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
    if (!nzchar(pt)) return(paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ")"))
    paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ", ", pt, ")")
  }
  lab_uni <- "OR (univariable)"
  lab_multi <- "OR (multivariable)"
  base_title <- paste0("Logistic Regression Analysis of ", cfg$project$disease %||% "disease")
  pub_rows <- list()
  bases <- unique(m$base_var[m$base_var %in% names(data_pub)])
  if (exists("environment_clinical_voc_gate_columns", mode = "function")) {
    voc_gate <- environment_clinical_voc_gate_columns(data_pub, cfg)
    dropped_voc <- intersect(bases, voc_gate)
    if (length(dropped_voc)) {
      cli::cli_alert_info(
        "NHANES Table S4: 临床表剔除 {length(dropped_voc)} 个环境毒物列: {paste(dropped_voc, collapse = ', ')}"
      )
      bases <- setdiff(bases, voc_gate)
    }
  }
  bases <- order_vars_like_table1(bases, ctx, cfg, data_pub)
  for (bv in bases) {
    x <- data_pub[[bv]]
    lab_char <- gsub("_", " ", bv)
    sub_m <- m[m$base_var == bv, , drop = FALSE]
    is_cont <- (bv %in% force_continuous_vars) ||
      (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)
    if (is_cont) {
      is_norm <- is_var_normal_for_table(bv, normal_vars, skewed_vars)
      mr <- sub_m[sub_m$Variable == bv, , drop = FALSE]
      u1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr$Est_u[1], mr$Lo_u[1], mr$Hi_u[1], mr$P_u[1]) else ""
      m1 <- if (nrow(mr) >= 1L) .fmt_ci_p(mr$Est_m[1], mr$Lo_m[1], mr$Hi_m[1], mr$P_m[1]) else ""
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char,
        Statistic = continuous_statistic_label(is_norm),
        all = fmt_continuous_svy(design, bv, is_norm),
        U1 = u1, M1 = m1, stringsAsFactors = FALSE)
    } else {
      xf <- factor(x)
      lv <- levels(xf)
      if (!length(lv)) next
      ref <- lv[1L]
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char,
        Statistic = as.character(ref),
        all = fmt_categorical_level_svy(design, bv, ref),
        U1 = "", M1 = "", stringsAsFactors = FALSE)
      if (length(lv) > 1L) {
        for (k in seq_len(length(lv))[-1L]) {
          lev <- lv[k]
          mr <- sub_m[sub_m$Variable == paste0(bv, lev), , drop = FALSE]
          if (nrow(mr) == 0L) {
            mr <- sub_m[grepl(lev, sub_m$Variable, fixed = TRUE) & sub_m$Variable != bv, , drop = FALSE]
          }
          if (nrow(mr) == 0L) {
            mr <- sub_m[sub_m$Variable == lev, , drop = FALSE]
          }
          if (nrow(mr) > 1L) mr <- mr[1L, , drop = FALSE]
          u1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr$Est_u, mr$Lo_u, mr$Hi_u, mr$P_u) else ""
          m1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr$Est_m, mr$Lo_m, mr$Hi_m, mr$P_m) else ""
          pub_rows[[length(pub_rows) + 1L]] <- data.frame(
            Characteristic = "",
            Statistic = as.character(lev),
            all = fmt_categorical_level_svy(design, bv, lev),
            U1 = u1, M1 = m1, stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(pub_rows)) return(invisible(FALSE))
  out_table <- do.call(rbind, pub_rows)
  names(out_table)[names(out_table) == "U1"] <- lab_uni
  names(out_table)[names(out_table) == "M1"] <- lab_multi
  if (exists("multivariate_pub_drop_univariable_if_needed", mode = "function")) {
    out_table <- multivariate_pub_drop_univariable_if_needed(out_table, cfg)
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
    if (!is.finite(fixed_sno) || fixed_sno < 1L) fixed_sno <- 7L
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
    pub_mv <- list(title = title_mv, filepath = filepath_mv)
  } else {
    pub_mv <- pub_pair(
      ctx, ctx$output_dir_tables, "supp_table",
      title_caption, file_caption, "xlsx"
    )
  }
  tryCatch(export_sci_table(out_table, pub_mv$filepath, title = pub_mv$title),
           error = function(e) cli::cli_alert_warning("NHANES 多因素表导出失败: {e$message}"))
  invisible(TRUE)
}

block_multivariate_nhanes <- function(ctx, ...) {
  options(survey.lonely.psu = "adjust")
  cfg <- ctx$config
  mv_cfg <- cfg$multivariate_nhanes %||% list()
  bl_cfg <- mv_cfg
  if (!.is_nhanes_db(cfg)) stop("multivariate_nhanes 仅用于 NHANES 数据库。")
  design <- ctx$results$nhanes_design
  if (is.null(design)) stop("请先 run_block(obj) 构建 nhanes_design")
  if (!requireNamespace("survey", quietly = TRUE)) stop("需要 R 包 survey")
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))

  univar_df <- ctx$results$univar_coef
  if ((is.null(univar_df) || !nrow(univar_df)) &&
      exists("environment_inject_covariate_fallback", mode = "function")) {
    ctx <- environment_inject_covariate_fallback(ctx)
    univar_df <- ctx$results$univar_coef
  }
  if (is.null(univar_df) || !nrow(univar_df)) stop("请先运行 univariate_nhanes")
  tb1_display <- as.character(ctx$results$tb1 %||% character(0))
  tb1_display <- unique(tb1_display[nzchar(tb1_display)])

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
      mv_input <- pipeline_union_model3_required(mv_input, cfg, names(design$variables), ix)
      added <- setdiff(mv_input, before)
      if (length(added)) {
        cli::cli_alert_info("Table S7 并入 Model3 必调: {paste(added, collapse = ', ')}")
      }
    }
    tb1_display <- unique(c(tb1_display, mv_input))
    cli::cli_alert_info(
      "Table S7 锁定协变量 (vif_final_pass): {paste(mv_input, collapse = ', ')}"
    )
  }
  nhanes_cfg <- cfg$nhanes %||% list()
  mc_cfg <- cfg$multicollinearity %||% list()
  index_excl <- if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
    pipeline_covariate_analysis_exclude_vars(cfg)
  } else {
    character(0)
  }
  mv_excl <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(mv_cfg$excluded_predictors %||% character(0)),
    as.character(nhanes_cfg$exclude_cols %||% character(0)),
    as.character(cfg$data$id_column %||% character(0)),
    index_excl
  ))
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    mv_excl <- setdiff(mv_excl, pipeline_index_exposure_var(cfg))
  }
  mv_excl <- mv_excl[nzchar(mv_excl)]
  if (length(mv_excl)) {
    dropped_mv <- intersect(mv_input, mv_excl)
    if (length(dropped_mv)) {
      cli::cli_alert_info("multivariate_nhanes: 排除非分析变量: {paste(dropped_mv, collapse = ', ')}")
    }
    mv_input <- setdiff(mv_input, mv_excl)
  }
  # 强制纳入暴露指标（与预后多因素一致，避免 Table S5 暴露行空）
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    ix_exp <- pipeline_index_exposure_var(cfg)
    if (length(ix_exp) && nzchar(ix_exp[1L])) {
      mv_input <- unique(c(ix_exp[1L], mv_input))
    }
  }
  if (!length(mv_input)) {
    if (exists("environment_inject_covariate_fallback", mode = "function")) {
      ctx <- environment_inject_covariate_fallback(ctx)
      mv_input <- as.character(ctx$results$vif_screen_pass %||% ctx$results$Model2Factors %||% character(0))
      mv_input <- unique(mv_input[nzchar(mv_input)])
    }
  }
  if (!length(mv_input)) {
    stop(
      "多因素输入变量为空 (config$multivariate_nhanes$input_from='", input_from,
      "')，请先运行 univariate_nhanes + multicollinearity_screen。",
      call. = FALSE
    )
  }
  if (isTRUE(ctx$results$environment_covariate_fallback_used) &&
      isTRUE(ctx$results$environment_covariate_hardcoded_fallback)) {
    ctx$results$tb2 <- mv_input
    ctx$results$multivar_features <- mv_input
    cli::cli_alert_warning("multivariate_nhanes: 已使用预设协变量 fallback，跳过多因素 svyglm。")
    return(ctx)
  }

  p_thr <- .mvn04_resolve_sig_cutoff(bl_cfg, ctx)
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- pipeline_outcome_case_label(cfg)
  design <- stats::update(
    design,
    Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], cfg, disease_lbl)
  )
  mv_input <- intersect(mv_input, names(design$variables))
  cli::cli_h2("多因素回归（基于 {input_from}，{length(mv_input)} 个变量）")

  multivar_result <- .mvn04_run_multivariate_svy(mv_input, design, mv_input)
  if (is.null(multivar_result) || !nrow(multivar_result)) {
    if (.mvn04_should_pause(bl_cfg, "pause_on_multivariate_fail")) {
      .mvn04_pause(ctx, "多因素 svyglm 失败", "检查 multivariate 输入变量共线性", NULL)
    }
    return(ctx)
  }
  sig_m <- !is.na(multivar_result$P) & multivar_result$P < p_thr
  tb2 <- .mvn04_extract_base_varname(multivar_result$Variable[sig_m], mv_input)
  model2_base <- if (length(tb2) > 0L) tb2 else mv_input

  demo_keywords <- as.character(mv_cfg$demo_keywords %||% c("Age", "Gender", "Sex", "Race", "Ethnic"))
  demo_pattern <- paste(demo_keywords, collapse = "|")
  Model2Factors <- intersect(model2_base, names(design$variables))
  M1f <- intersect(tb2, names(design$variables))
  M1f <- M1f[vapply(M1f, function(v) {
    any(grepl(paste(demo_keywords, collapse = "|"), v, ignore.case = TRUE))
  }, logical(1L))]
  M1f <- setdiff(M1f, as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% character(0)
  ))
  if (!length(M1f)) {
    cli::cli_alert_info(
      "multivariate_nhanes: tb2 无人口学显著变量，Model1 将在 VIF final 阶段按 screen/fallback 解析。"
    )
  }
  data_pub <- as.data.frame(design$variables, stringsAsFactors = FALSE)
  if (!isTRUE(ctx$results$.multivariate_mode_harmonized)) {
    ar <- .mvn04_apply_anthropometric_vif_resolution(Model2Factors, data_pub, cfg, ctx, "multivariate_nhanes")
    ctx <- ar$ctx
    if (length(ar$dropped)) {
      tb2 <- setdiff(tb2, ar$dropped)
      M1f <- setdiff(M1f, ar$dropped)
      Model2Factors <- ar$kept
      univar_df <- .mvn04_filter_coef_df_by_dropped_vars(univar_df, ar$dropped, mv_input)
      multivar_result <- .mvn04_filter_coef_df_by_dropped_vars(multivar_result, ar$dropped, mv_input)
    }
  }
  min_sig <- as.integer(mv_cfg$pause_min_sig_vars %||% 3L)
  if (length(Model2Factors) < min_sig && .mvn04_should_pause(mv_cfg, "pause_on_min_sig_vars")) {
    .mvn04_pause(ctx, paste0("Model2Factors 仅 ", length(Model2Factors), " 个"), "放宽 sig_cutoff", NULL)
  }
  if (exists("pipeline_strip_index_from_model_factors", mode = "function")) {
    stripped <- pipeline_strip_index_from_model_factors(M1f, Model2Factors, cfg)
    M1f <- stripped$M1
    Model2Factors <- stripped$M2
  }
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    merged <- pipeline_merge_force_covariates(M1f, Model2Factors, names(design$variables), cfg)
    M1f <- merged$M1
    Model2Factors <- merged$M2
  }
  write_mf <- isTRUE(mv_cfg$write_model_factors %||% TRUE) &&
    !isTRUE(ctx$results$.multivariate_mode_harmonized)
  if (isTRUE(write_mf)) {
    ctx <- save_result(ctx, "tb2_multivar_features", tb2, "D05_Multivariable_Features.RData")
    ctx <- save_result(ctx, "Model1Factors", M1f, "Model1Factors.RData")
    ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
    writeLines(M1f, file.path(ctx$output_dir, "Model1Factors.txt"))
    writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))
    ctx$results$tb2 <- tb2
    ctx$results$multivar_features <- tb2
    ctx$results$univar_features <- mv_input
    ctx$results$Model1Factors <- M1f
    ctx$results$Model2Factors <- Model2Factors
    ctx$results$nhanes_logistic_M1 <- M1f
    ctx$results$nhanes_logistic_M2 <- Model2Factors
    ctx$results$nhanes_tb1_weighted <- mv_input
    ctx$results$nhanes_tb2_weighted <- tb2
  }
  pred_vars <- mv_input
  tbl_tb1 <- if (length(tb1_display)) tb1_display else mv_input
  normal_vars <- as.character(ctx$results$normal_vars %||% character(0))
  skewed_vars <- as.character(ctx$results$skewed_vars %||% character(0))
  if (!length(normal_vars) && !length(skewed_vars)) {
    nn <- resolve_normality_vars(data_pub, names(Filter(is.numeric, data_pub)))
    normal_vars <- nn$normal
    skewed_vars <- nn$skewed
  }
  .mvn04_publish_table_s2_nhanes(
    ctx, cfg, mv_cfg, design, data_pub, pred_vars, univar_df, multivar_result, tbl_tb1,
    normal_vars = normal_vars, skewed_vars = skewed_vars
  )
  cli::cli_alert_success("multivariate_nhanes 完成: tb2={length(tb2)}, Model2={length(Model2Factors)}")
  ctx
}
register_block("multivariate_nhanes", block_multivariate_nhanes, "multivariate_nhanes（只多因素）")

#' VIF final 锁定协变量多因素表（NHANES Table S7；单库无 dual-database 括号）
block_multivariate_nhanes_harmonized <- function(ctx, ...) {
  cfg <- ctx$config
  harm_opts <- cfg$multivariate_nhanes_harmonized %||% list()
  locked <- locked_multivariable_covariates(ctx, cfg)
  if (!length(locked$covariates) && !length(locked$all)) {
    stop(
      "multivariate_nhanes_harmonized: vif_final_pass 为空，请先 multicollinearity_nhanes_final。",
      call. = FALSE
    )
  }
  cap <- as.character(
    harm_opts$table_file_caption %||% locked_multivariable_table_caption(cfg)
  )[1L]
  sno <- suppressWarnings(as.integer(harm_opts$table_number %||% 7L)[1L])
  if (!is.finite(sno) || sno < 1L) sno <- 7L
  cfg$multivariate_nhanes <- utils::modifyList(
    cfg$multivariate_nhanes %||% list(),
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
  ctx <- block_multivariate_nhanes(ctx, ...)
  ctx$results$.multivariate_mode_harmonized <- FALSE
  ctx$results$multivar_harmonized_done <- TRUE
  ctx$results$multivar_harmonized_model2 <- locked$all
  ctx
}

register_block(
  "multivariate_nhanes_harmonized",
  block_multivariate_nhanes_harmonized,
  "VIF-final locked multivariable table (NHANES Table S7)"
)
