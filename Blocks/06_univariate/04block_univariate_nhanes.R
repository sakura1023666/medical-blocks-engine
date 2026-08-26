###############################################################################
#  univariate_nhanes — NHANES 加权单因素 svyglm（Table S2a + M1/M2/M3 候选池逻辑）。
#
#  register_block: "univariate_nhanes"
#  前置: run_block("obj")；survey 包；incidence + binary
#
#  # ── 配置 config$univariate_nhanes（节选，详见块内）────────────────────────
#  univariate_nhanes = list(
#    sig_cutoff            = 0.05,     # 单因素筛选 P 阈值（必填语义）
#    p_threshold           = 0.05,     # sig_cutoff 别名
#    tb2_threshold         = 15,       # |Wald tb2| 超阈值时 tb3 分支用 tb1 否则 tb2
#    discrete_max_levels   = 5L,       # 离散变量最大水平数
#    model1_candidate_names = c("Age", "Gender", ...),  # M1 固定候选（块内默认）
#    pause_enable                  = TRUE,
#    pause_on_missing_design       = TRUE,
#    pause_on_missing_packages     = TRUE,
#    pause_on_no_predictors        = TRUE,
#    pause_on_multivariate_fail    = TRUE,
#    pause_on_min_sig_vars         = TRUE,
#    pause_min_sig_vars            = 3L
#  ),
#
#  require_data          = ctx$results$nhanes_design  # 须先 run_block(obj)
#  块内读取 config$univariate_nhanes；调查设计见 config$nhanes。
#  策略 B：NHANES 库不跑 univariate_incidence_binary，本块写入 univar_features / multivar_features。
###############################################################################

.uvn04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  val <- bl_cfg[[key]]
  if (is.null(val)) return(isTRUE(default))
  isTRUE(val)
}

.uvn04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "univariate_nhanes",
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

.uvn04_resolve_sig_cutoff <- function(bl_cfg, ctx) {
  cutoff <- bl_cfg$sig_cutoff
  if (is.null(cutoff)) cutoff <- bl_cfg$p_threshold
  if (is.null(cutoff)) {
    .uvn04_pause(
      ctx,
      "未配置 config$univariate_nhanes$sig_cutoff（或 legacy p_threshold）。",
      "在 config$univariate_nhanes 中设置 sig_cutoff。",
      NULL
    )
  }
  as.numeric(cutoff)[1L]
}

.uvn04_svy_coef_to_df <- function(fit) {
  sm <- summary(fit)$coefficients
  rn <- rownames(sm)[rownames(sm) != "(Intercept)"]
  if (!length(rn)) return(NULL)
  pr_i <- grep("^Pr\\(", colnames(sm))
  pcol <- if (length(pr_i)) pr_i[1L] else NA_integer_
  do.call(rbind, lapply(rn, function(r) {
    est <- sm[r, "Estimate", drop = TRUE]
    se  <- sm[r, "Std. Error", drop = TRUE]
    pv  <- if (is.finite(pcol)) suppressWarnings(as.numeric(sm[r, pcol])) else NA_real_
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

.uvn04_match_coef_row <- function(sub_m, bv, lev = NULL) {
  if (is.null(sub_m) || !nrow(sub_m)) {
    return(sub_m[0, , drop = FALSE])
  }
  if (is.null(lev)) {
    mr <- sub_m[sub_m$Variable == bv, , drop = FALSE]
    if (nrow(mr)) return(mr[1L, , drop = FALSE])
    return(sub_m[0, , drop = FALSE])
  }
  lev <- as.character(lev)
  candidates <- unique(c(
    paste0(bv, lev),
    paste0(bv, trimws(lev)),
    paste0(bv, gsub("\\s+", " ", trimws(lev)))
  ))
  for (cand in candidates) {
    mr <- sub_m[sub_m$Variable == cand, , drop = FALSE]
    if (nrow(mr)) return(mr[1L, , drop = FALSE])
  }
  mr <- sub_m[grepl(paste0("^", bv), sub_m$Variable, perl = TRUE), , drop = FALSE]
  if (nzchar(trimws(lev))) {
    mr <- mr[vapply(mr$Variable, function(vn) {
      grepl(trimws(lev), vn, fixed = TRUE) || grepl(trimws(lev, which = "right"), vn, fixed = TRUE)
    }, logical(1)), , drop = FALSE]
  }
  if (nrow(mr) > 1L) mr <- mr[1L, , drop = FALSE]
  mr
}

.uvn04_publish_table_s2a_nhanes <- function(
    ctx, cfg, bl_cfg, design, data_pub, predictor_vars,
    univar_df, tb1, normal_vars = character(0), skewed_vars = character(0)) {
  force_continuous_vars <- cfg$force_continuous_vars %||% character(0)
  disc_n <- bl_cfg$discrete_max_levels %||% 5L
  .uvn04_env_lmap <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg)
  } else NULL
  .uvn04_disp <- function(v) {
    if (exists("environment_display_label", mode = "function")) {
      environment_display_label(as.character(v), .uvn04_env_lmap)
    } else {
      gsub("_", " ", as.character(v), fixed = TRUE)
    }
  }

  if (is.null(univar_df) || nrow(univar_df) == 0L) {
    cli::cli_alert_warning("univariate_nhanes: 无单因素系数，跳过 Table S2。")
    return(invisible(FALSE))
  }

  row_base <- vapply(univar_df$Variable, function(vn) {
    b <- .uvn04_extract_base_varname(c(vn), predictor_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))

  meta_drop <- if (exists("pipeline_meta_exclude_cols", mode = "function")) {
    pipeline_meta_exclude_cols()
  } else {
    c("new_Weight", "new_weight", "WTSA2YR", "WTMEC2YR")
  }
  keep_ix <- !row_base %in% meta_drop
  univar_df <- univar_df[keep_ix, , drop = FALSE]
  row_base <- row_base[keep_ix]

  # 表内展示全部单因素结果（tb1 仅用于下游筛选，不限制发表表行）
  uni_slice <- univar_df

  pred_tbl_ix <- as.character((cfg$prediction %||% list())$index_vars %||% character(0))
  pred_tbl_ix <- unique(pred_tbl_ix[nzchar(pred_tbl_ix)])
  keep_ix_row <- isTRUE((cfg$prediction %||% list())$keep_index_vars_in_regression_table %||% TRUE)
  if (keep_ix_row && length(pred_tbl_ix)) {
    missing_ix <- setdiff(pred_tbl_ix, row_base)
    if (length(missing_ix)) {
      cli::cli_alert_info(
        "NHANES Table S3: 预测指标 {paste(missing_ix, collapse = ', ')} 不在单因素结果中，已跳过追加。"
      )
    }
  }

  uni_key <- data.frame(
    Variable = uni_slice$Variable,
    Group    = rep("", nrow(uni_slice)),
    Est_u    = uni_slice$OR,
    Lo_u     = uni_slice$CI_lo,
    Hi_u     = uni_slice$CI_hi,
    P_u      = uni_slice$P,
    stringsAsFactors = FALSE
  )

  m <- uni_key
  m$base_var <- vapply(m$Variable, function(vn) {
    as.character(.uvn04_extract_base_varname(c(vn), predictor_vars)[1L])
  }, character(1L))

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

  lab_uni <- "OR (univariable)"
  lab_all <- "Overall"
  base_title <- paste0("Logistic Regression Analysis of ", cfg$project$disease %||% "disease")

  bases <- unique(row_base[row_base %in% names(data_pub)])
  if (exists("environment_clinical_voc_gate_columns", mode = "function")) {
    voc_gate <- environment_clinical_voc_gate_columns(data_pub, cfg)
    dropped_voc <- intersect(bases, voc_gate)
    if (length(dropped_voc)) {
      cli::cli_alert_info(
        "NHANES Table S3: 临床表剔除 {length(dropped_voc)} 个环境毒物列: {paste(dropped_voc, collapse = ', ')}"
      )
      bases <- setdiff(bases, voc_gate)
    }
  }
  bases <- order_vars_like_table1(bases, ctx, cfg, data_pub)

  pub_rows <- list()
  for (bv in bases) {
    x <- data_pub[[bv]]
    lab_char <- .uvn04_disp(bv)
    sub_m <- m[m$base_var == bv, , drop = FALSE]
    is_cont <- (bv %in% force_continuous_vars) ||
      (bv %in% as.character(ctx$results$continuous_vars %||% character(0))) ||
      (is.numeric(x) && length(unique(stats::na.omit(x))) > disc_n)

    if (is_cont) {
      is_norm <- is_var_normal_for_table(bv, normal_vars, skewed_vars)
      all_txt <- fmt_continuous_svy(design, bv, is_norm)
      mr <- .uvn04_match_coef_row(sub_m, bv)
      u1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr$Est_u[1], mr$Lo_u[1], mr$Hi_u[1], mr$P_u[1]) else ""
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char,
        Statistic = continuous_statistic_label(is_norm),
        all = all_txt,
        U1 = u1,
        stringsAsFactors = FALSE
      )
    } else {
      xf <- factor(x)
      lv <- levels(xf)
      if (length(lv) == 0L) next
      ref <- lv[1L]
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Characteristic = lab_char,
        Statistic = trimws(as.character(ref)),
        all = fmt_categorical_level_svy(design, bv, ref),
        U1 = "",
        stringsAsFactors = FALSE
      )
      if (length(lv) > 1L) {
        for (k in seq_len(length(lv))[-1L]) {
          lev <- lv[k]
          mr <- .uvn04_match_coef_row(sub_m, bv, lev)
          u1 <- if (nrow(mr) == 1L) .fmt_ci_p(mr$Est_u, mr$Lo_u, mr$Hi_u, mr$P_u) else ""
          pub_rows[[length(pub_rows) + 1L]] <- data.frame(
            Characteristic = "",
            Statistic = trimws(as.character(lev)),
            all = fmt_categorical_level_svy(design, bv, lev),
            U1 = u1,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  if (length(pub_rows) == 0L) {
    cli::cli_alert_warning("univariate_nhanes: Table S2 发表用表格行为空。")
    return(invisible(FALSE))
  }

  out_table <- do.call(rbind, pub_rows)
  names(out_table)[names(out_table) == "U1"] <- lab_uni
  names(out_table)[names(out_table) == "all"] <- lab_all

  pub_uv <- pub_pair(
    ctx, ctx$output_dir_tables, "supp_table",
    base_title, "Univariate Regression Analysis", "xlsx"
  )
  tryCatch(
    export_sci_table(out_table, pub_uv$filepath, title = pub_uv$title),
    error = function(e) cli::cli_alert_warning("NHANES Table S2 导出失败: {e$message}")
  )
  cli::cli_alert_success("univariate_nhanes Table S2: {.file {basename(pub_uv$filepath)}}")
  invisible(TRUE)
}


# ── 人体测量 VIF / 变量名解析（本块内嵌，不依赖公共 helper 文件）────────────

.uvn04_extract_base_varname <- function(var_names, all_vars) {
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
.uvn04_pipeline_effective_vif_thresholds <- function(cfg) {
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
.uvn04_calculate_vif_from_vars <- function(vars, data) {
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

.uvn04_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.uvn04_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .uvn04_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .uvn04_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.uvn04_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  thr <- .uvn04_pipeline_effective_vif_thresholds(cfg)$strict
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

  res0 <- .uvn04_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .uvn04_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.uvn04_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro || d1 %in% protected) next
    trial <- setdiff(vars, d1)
    if (.uvn04_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- setdiff(intersect(c("Weight", "Height"), anthro), protected)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 1L &&
      .uvn04_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
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

.uvn04_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .uvn04_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.uvn04_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .uvn04_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .uvn04_pipeline_effective_vif_thresholds(cfg)$strict
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


block_univariate_nhanes <- function(ctx, ...) {
  options(survey.lonely.psu = "adjust")

  cfg        <- ctx$config
  bl_cfg     <- cfg$univariate_nhanes %||% list()
  nhanes_cfg <- cfg$nhanes %||% list()
  proj_cfg   <- cfg$project %||% list()

  if (exists("environment_patch_voc_exclude", mode = "function")) {
    data_for_voc <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
    if (!is.null(data_for_voc)) {
      ctx$config <- environment_patch_voc_exclude(cfg, data_for_voc)
      if (exists("environment_patch_table1_sections", mode = "function")) {
        ctx$config <- environment_patch_table1_sections(ctx$config, data_for_voc)
      }
      cfg <- ctx$config
    }
  }

  if (!.is_nhanes_db(cfg)) {
    stop("univariate_nhanes 仅用于 database_type/database 为 NHANES/NHANCE；其它库请用 univariate_incidence_binary 或 univariate_prognosis。")
  }

  study_type <- tolower(cfg$project$study_type %||% "incidence")
  classification_mode <- cfg$project$classification_mode %||% "binary"
  if (!study_type %in% c("incidence", "environment") || !identical(classification_mode, "binary")) {
    stop(
      "univariate_nhanes 仅支持 study_type=incidence|environment 且 classification_mode=binary；",
      "当前: ", study_type, ", ", classification_mode
    )
  }

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    if (.uvn04_should_pause(bl_cfg, "pause_on_missing_design")) {
      .uvn04_pause(
        ctx,
        "ctx$results$nhanes_design 为空。",
        "请先运行 run_block(ctx, 'obj') 构建调查设计对象。",
        NULL
      )
    }
    cli::cli_alert_warning("univariate_nhanes: nhanes_design 为空，已跳过。")
    return(ctx)
  }

  if (!requireNamespace("survey", quietly = TRUE)) {
    if (.uvn04_should_pause(bl_cfg, "pause_on_missing_packages")) {
      .uvn04_pause(ctx, "缺少 R 包 survey。", "install.packages('survey') 后重试。", NULL)
    }
    return(ctx)
  }
  suppressPackageStartupMessages({ library(survey, warn.conflicts = FALSE) })

  p_thr   <- .uvn04_resolve_sig_cutoff(bl_cfg, ctx)

  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"

  wt_col  <- as.character(nhanes_cfg$survey_weight  %||% "new_Weight")[1L]
  psu_col <- as.character(nhanes_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(nhanes_cfg$survey_strata  %||% "SDMVSTRA")[1L]
  extra_excl <- as.character(nhanes_cfg$exclude_cols %||% c("WTINT2YR", "WTMEC2YR"))
  excl_cols  <- unique(c(wt_col, psu_col, str_col, extra_excl,
                         cfg$data$id_column %||% "SEQN"))

  design <- stats::update(
    design,
    Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], case_label = disease_lbl)
  )

  cov_excl <- if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
    pipeline_covariate_analysis_exclude_vars(cfg)
  } else {
    character(0)
  }
  idx_keep <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% character(0)
  )[1L]
  if (length(idx_keep) && nzchar(idx_keep)) {
    cov_excl <- setdiff(cov_excl, idx_keep)
  }
  uv_excl <- as.character(bl_cfg$excluded_predictors %||% character(0))
  if (length(idx_keep) && nzchar(idx_keep)) {
    uv_excl <- setdiff(uv_excl, idx_keep)
  }
  drop_always <- unique(c(
    "Disease", "Disease_Group", outcome_col,
    cov_excl, uv_excl,
    excl_cols
  ))
  drop_always <- intersect(drop_always, names(design$variables))
  if (length(cov_excl)) {
    cli::cli_alert_info(
      "univariate_nhanes: 排除非暴露协变量: {paste(intersect(cov_excl, names(design$variables)), collapse = ', ')}"
    )
  }
  pred_vars <- setdiff(names(design$variables), drop_always)
  if (length(idx_keep) && nzchar(idx_keep) && idx_keep %in% names(design$variables)) {
    pred_vars <- unique(c(pred_vars, idx_keep))
  }
  anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
  if (length(anthro_drop)) {
    pred_vars <- setdiff(pred_vars, anthro_drop)
    cli::cli_alert_info(
      "univariate_nhanes: 沿用已记录的人体测量剔除: {paste(anthro_drop, collapse = ', ')}"
    )
  }
  pred_vars <- pred_vars[sapply(design$variables[pred_vars],
                                function(x) length(unique(stats::na.omit(x))) > 1L)]

  if (length(pred_vars) == 0L) {
    if (.uvn04_should_pause(bl_cfg, "pause_on_no_predictors")) {
      .uvn04_pause(ctx, "无有效预测变量。", "检查 nhanes_design 与 exclude_cols。", NULL)
    }
    return(ctx)
  }

  urows <- list()
  for (v in pred_vars) {
    f <- stats::as.formula(paste0("Disease_Group ~ ", v))
    fit_u <- tryCatch(
      survey::svyglm(f, design = design, family = stats::quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit_u)) next
    part <- .uvn04_svy_coef_to_df(fit_u)
    if (!is.null(part) && nrow(part) > 0L) urows[[length(urows) + 1L]] <- part
  }
  univar_df <- if (length(urows)) do.call(rbind, urows) else NULL


  sig_u <- !is.na(univar_df$P) & univar_df$P < p_thr
  screening_cutoff <- as.numeric(bl_cfg$screening_cutoff %||% bl_cfg$p_threshold %||% 0.1)[1L]
  sig_screen <- !is.na(univar_df$P) & univar_df$P < screening_cutoff
  # 可选：排除单因素 OR<1（保护因素），仅保留有 OR>1 显著行的变量进入下游筛选（tb1→VIF）
  exclude_or_lt1 <- isTRUE(bl_cfg$exclude_or_below_one %||% FALSE)
  if (exclude_or_lt1 && "OR" %in% names(univar_df)) {
    or_pos     <- !is.na(univar_df$OR) & univar_df$OR > 1
    tb1_all    <- .uvn04_extract_base_varname(univar_df$Variable[sig_u], pred_vars)
    tb1_keep   <- .uvn04_extract_base_varname(univar_df$Variable[sig_u & or_pos], pred_vars)
    dropped_or <- setdiff(tb1_all, tb1_keep)
    sig_u      <- sig_u & or_pos
    sig_screen <- sig_screen & or_pos
    if (length(dropped_or)) {
      cli::cli_alert_info(
        "univariate_nhanes: 排除单因素 OR<1（保护因素）: {paste(dropped_or, collapse = ', ')}"
      )
    }
  }
  tb1 <- .uvn04_extract_base_varname(univar_df$Variable[sig_u], pred_vars)
  tb_screen <- .uvn04_extract_base_varname(univar_df$Variable[sig_screen], pred_vars)
  cli::cli_alert_success("单因素显著变量 tb1 (P < {p_thr}{if (exclude_or_lt1) ', OR>1' else ''}): {length(tb1)} 个")
  cli::cli_alert_success("VIF screening 候选 tb_screen (P < {screening_cutoff}): {length(tb_screen)} 个")
  data_pub <- as.data.frame(design$variables, stringsAsFactors = FALSE)

  if (length(tb1) < as.integer(bl_cfg$pause_min_sig_vars %||% 3L) &&
      .uvn04_should_pause(bl_cfg, "pause_on_min_sig_vars")) {
    .uvn04_pause(
      ctx,
      paste0("单因素显著变量仅 ", length(tb1), " 个。"),
      "放宽 config$univariate_nhanes$sig_cutoff。",
      if (!is.null(univar_df)) utils::head(univar_df, 5L) else NULL
    )
  }

  ctx <- save_result(ctx, "tb1_univar_features", tb1, "D06_Univariable_Features.RData")
  ctx <- save_result(ctx, "tb_screen_univar_features", tb_screen, "D06b_Univariable_Screen_Features.RData")
  ctx$results$tb1 <- tb1
  ctx$results$tb_screen <- tb_screen
  ctx$results$univar_features <- tb_screen
  ctx$results$univar_coef <- univar_df
  ctx$results$univariate_study_type <- study_type
  ctx$results$univar_pvalues <- if (!is.null(univar_df) && nrow(univar_df) > 0L) {
    setNames(univar_df$P, univar_df$Variable)
  } else NULL

  normal_vars <- as.character(ctx$results$normal_vars %||% character(0))
  skewed_vars <- as.character(ctx$results$skewed_vars %||% character(0))
  if (!length(normal_vars) && !length(skewed_vars)) {
    nn <- resolve_normality_vars(data_pub, names(Filter(is.numeric, data_pub)))
    normal_vars <- nn$normal
    skewed_vars <- nn$skewed
  } else if (!length(normal_vars) && length(skewed_vars)) {
    cont_v <- names(Filter(is.numeric, data_pub))
    normal_vars <- setdiff(cont_v, skewed_vars)
  }
  .uvn04_publish_table_s2a_nhanes(
    ctx, cfg, bl_cfg, design, data_pub, pred_vars, univar_df, tb1,
    normal_vars = normal_vars, skewed_vars = skewed_vars
  )
  cli::cli_alert_success("univariate_nhanes 完成: tb1={length(tb1)}")
  ctx
}

register_block(
  "univariate_nhanes",
  block_univariate_nhanes,
  "NHANES 加权单因素（只单因素）"
)
