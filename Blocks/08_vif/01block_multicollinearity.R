###############################################################################
#  multicollinearity — VIF 共线性筛选，回写 Model1Factors / Model2Factors（含 NHANES 加权 VIF）。
#
#  register_block: "multicollinearity"
#  典型流水线: baseline 后、单因素/多因素/RCS 前；下游读 ctx$results$Model2Factors
#  源: Blocks/block_multicollinearity.R（Blocks/08_vif）
#
#  功能:
#    1. 对 Model2Factors ∪ multicollinearity$vif_design_extra_predictors 建设计矩阵算 VIF
#       （extra 仅用于共线性诊断，不写回 Model2Factors）
#    2. 首先选择VIF < vif_threshold_strict的变量
#    3. 如果筛选后变量数 < min_vars_threshold，则放宽标准选择VIF < vif_threshold_loose的变量
#    4. Model1/Model2 按决策树拆分（多因素VIF人口学 → 单因素VIF人口学 → 单因素VIF池全部非实验室）；
#       多因素VIF池为空时工作池回退单因素VIF池；三级回退时 Model2 仅含实验室指标
#
#  输入: ctx$data$imputed（优先）或 ctx$data$cleaned
#        ctx$results$Model1Factors / ctx$results$Model2Factors
#
#  VIF 说明:
#   在自变量之间计算方差膨胀因子（每个 X_j 对其余 X 回归的 R²），不依赖结局类型。
#   因此发病/预后、二分类/多分类无需分开写两套：与后续 Logistic / multinomial / Cox
#   的系数解释无关，仅诊断预测变量间共线性。
#  输出:
#    - VIF_check.csv / .tex
#    - Model1Factors.RData / Model1Factors.txt (更新后)
#    - Model2Factors.RData / Model2Factors.txt (更新后)
#    - ctx$results$vif_design_extra_predictors — 实际纳入 VIF 的额外列（解析到数据列名后）
#    - VIF_design_matrix_predictors.txt — 进入 model.matrix 的原始变量名列表（Model2 ∪ extra）
#    - multicollinearity$vif_append_extra_to_model2_outputs — TRUE 时将 extra 一并写入 Model2Factors 输出
###############################################################################

# ── 人体测量 VIF（本块内嵌）────────────────────────────────────────────

.mcol_extract_base_varname <- function(var_names, all_vars) {
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
.mcol_pipeline_effective_vif_thresholds <- function(cfg) {
  mc <- cfg$multicollinearity %||% list()
  fs <- cfg$feature_selection %||% list()
  fs_on <- isTRUE(fs$enable %||% TRUE)
  strict <- as.numeric(mc$vif_threshold_strict %||% 4)[1L]
  loose  <- as.numeric(mc$vif_threshold_loose %||% 10)[1L]
  min_v  <- as.numeric(mc$min_vars_threshold %||% 10)[1L]
  if (fs_on) {
    thr_fs <- as.numeric(mc$vif_threshold_before_feature_selection %||% strict)[1L]
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
.mcol_calculate_vif_from_vars <- function(vars, data) {
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

.mcol_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mcol_anthropometric_vif_acceptable <- function(vars, data, anthro, threshold) {
  anthro <- intersect(as.character(anthro), as.character(vars))
  if (!length(anthro)) return(TRUE)
  res <- .mcol_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) return(TRUE)
  mx <- vapply(anthro, function(a) .mcol_max_vif_for_original_var(res$vif_values, a), numeric(1))
  all(is.finite(mx) & mx < threshold)
}

.mcol_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
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
  thr <- .mcol_pipeline_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  if ("BMI" %in% anthro) {
    drop_hw <- intersect(c("Weight", "Height"), anthro)
    if (length(drop_hw)) {
      return(list(
        kept = setdiff(vars, drop_hw),
        dropped = drop_hw,
        strategy = "bmi_present_drop_weight_height",
        anthro_max_vif = NULL
      ))
    }
  }
  # 仅 0–1 个人体测量变量：不做并存 VIF 协调（≥2 个时须全部 VIF < thr 才并存保留）
  if (length(anthro) < 2L) {
    return(list(
      kept = vars, dropped = character(0), strategy = "single_or_none",
      anthro_max_vif = NULL
    ))
  }
  res0 <- .mcol_calculate_vif_from_vars(vars, data)
  anthro_max <- stats::setNames(
    vapply(anthro, function(a) .mcol_max_vif_for_original_var(res0$vif_values, a), numeric(1)),
    anthro
  )
  if (.mcol_anthropometric_vif_acceptable(vars, data, anthro, thr)) {
    return(list(
      kept = vars, dropped = character(0), strategy = "vif_ok",
      anthro_max_vif = anthro_max
    ))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro) next
    trial <- setdiff(vars, d1)
    if (.mcol_anthropometric_vif_acceptable(trial, data, intersect(anthro, trial), thr)) {
      return(list(
        kept = trial, dropped = d1, strategy = paste0("drop_one:", d1),
        anthro_max_vif = anthro_max
      ))
    }
  }
  drop_wh <- intersect(c("Weight", "Height"), anthro)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 2L &&
      .mcol_anthropometric_vif_acceptable(trial2, data, intersect(anthro, trial2), thr)) {
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

.mcol_filter_coef_df_by_dropped_vars <- function(df, dropped, base_vars) {
  if (is.null(df) || !nrow(df) || !length(dropped)) return(df)
  row_base <- vapply(df$Variable, function(vn) {
    b <- .mcol_extract_base_varname(c(vn), base_vars)
    if (length(b) >= 1L) as.character(b)[1L] else vn
  }, character(1L))
  df[!row_base %in% dropped, , drop = FALSE]
}

.mcol_apply_anthropometric_vif_resolution <- function(
    vars, data, cfg, ctx = NULL, label = "pipeline") {
  res <- .mcol_resolve_anthropometric_vif_vars(vars, data, cfg)
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
    thr_msg <- .mcol_pipeline_effective_vif_thresholds(cfg)$strict
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

# 与 Table 1（.default_table1_sections + baseline$table1_sections）一致的分组顺序；
# cfg$prediction$index_vars 缺省为 c(ALBI, HALP, CALLY, ANLR, RAR)，置于表格末段
.mcol_order_base_vars_table1_style <- sort_vars_by_table1_sections

.mcol_build_orig_var_vif_table <- function(vars, data) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (!length(vars)) return(NULL)
  if (length(vars) == 1L) {
    return(data.frame(Variable = vars, VIF = NA_real_, stringsAsFactors = FALSE))
  }
  res <- .mcol_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) {
    return(data.frame(Variable = vars, VIF = NA_real_, stringsAsFactors = FALSE))
  }
  vifs <- vapply(vars, function(v) {
    .mcol_max_vif_for_original_var(res$vif_values, v)
  }, numeric(1))
  data.frame(Variable = vars, VIF = round(vifs, 3), stringsAsFactors = FALSE)
}

.mcol_compute_screen_pass <- function(vars, data, cfg, vif_threshold) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (!length(vars)) return(character(0))
  if (length(vars) == 1L) return(vars)

  mc <- cfg$multicollinearity %||% list()
  mode <- tolower(trimws(as.character(mc$vif_removal_mode %||% "iterative")[1L]))
  ar_cfg <- mc$anthropometric_vif_resolution %||% list()
  anthro_cfg <- unique(as.character(ar_cfg$vars %||% c("BMI", "Weight", "Height")))
  anthro_in <- intersect(anthro_cfg, vars)

  working <- vars
  if (length(anthro_in) >= 2L && isTRUE(ar_cfg$enable %||% TRUE)) {
    cli::cli_h2("BMI/Weight/Height 人体测量 VIF 协调（screen 阶段，≥2 项并存）")
    ar <- .mcol_resolve_anthropometric_vif_vars(vars, data, cfg)
    working <- ar$kept
    dropped <- setdiff(vars, working)
    if (length(dropped)) {
      cli::cli_alert_info(
        "screen: 人体测量协调策略 [{ar$strategy}]，剔除: {paste(dropped, collapse = ', ')}"
      )
    } else if (identical(ar$strategy, "vif_ok")) {
      cli::cli_alert_info("screen: 人体测量 {length(anthro_in)} 项并存且各自 VIF < {vif_threshold}，全部保留")
    }
  }

  exposure <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exposure <- as.character(pipeline_index_exposure_var(cfg))
    exposure <- exposure[nzchar(exposure)]
  }
  protect <- intersect(exposure, working)

  if (identical(mode, "batch")) {
    res <- .mcol_calculate_vif_from_vars(working, data)
    vif_values <- res$vif_values
    .passes <- function(v) {
      if (is.null(vif_values)) return(TRUE)
      mx <- .mcol_max_vif_for_original_var(vif_values, v)
      if (!is.finite(mx)) return(FALSE)
      mx < vif_threshold
    }
    non_anthro <- setdiff(working, anthro_cfg)
    anthro_keep <- intersect(working, anthro_cfg)
    non_anthro_kept <- non_anthro[vapply(non_anthro, .passes, logical(1))]
    if (length(anthro_in) < 2L) {
      anthro_keep <- anthro_keep[vapply(anthro_keep, .passes, logical(1))]
    }
    return(unique(c(non_anthro_kept, anthro_keep)))
  }

  # iterative：每次剔除 VIF 最高者，直至全部 < vif_threshold（暴露指标不剔除）
  removed <- character(0)
  max_iter <- max(1L, length(working))
  for (iter in seq_len(max_iter)) {
    if (length(working) <= 1L) break
    tbl <- .mcol_build_orig_var_vif_table(working, data)
    if (is.null(tbl) || !nrow(tbl)) break
    bad <- tbl[is.finite(tbl$VIF) & tbl$VIF >= vif_threshold, , drop = FALSE]
    if (!nrow(bad)) break
    bad_vars <- as.character(bad$Variable)
    droppable <- setdiff(bad_vars, protect)
    if (!length(droppable)) break
    ord <- order(bad$VIF[match(droppable, bad_vars)], decreasing = TRUE, na.last = TRUE)
    drop_v <- droppable[ord[1L]]
    vif_drop <- bad$VIF[match(drop_v, bad$Variable)][1L]
    working <- setdiff(working, drop_v)
    removed <- c(removed, drop_v)
    cli::cli_alert_info(
      "VIF 迭代剔除 [{iter}]: {drop_v} (VIF={round(vif_drop, 3)} ≥ {vif_threshold})"
    )
  }
  if (length(removed)) {
    cli::cli_alert_success(
      "VIF 迭代完成：剔除 {length(removed)} 个变量，保留 {length(working)} 个（阈值 < {vif_threshold}）"
    )
  }
  unique(working)
}

.mcol_compute_final_pass <- function(vars, data, vif_threshold) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (!length(vars)) return(character(0))
  if (length(vars) == 1L) return(vars)

  res <- .mcol_calculate_vif_from_vars(vars, data)
  vif_values <- res$vif_values
  if (is.null(vif_values)) return(vars)

  kept <- character(0)
  for (v in vars) {
    mx <- .mcol_max_vif_for_original_var(vif_values, v)
    if (is.finite(mx) && mx < vif_threshold) kept <- c(kept, v)
  }
  unique(kept)
}

# final 发表表专用：暴露指标不参与协变量 VIF 筛选，但单独追加一行供 Table S6 展示
.mcol_append_exposure_vif_row <- function(vif_tbl, exposure, data, build_fn,
                                         ctx = NULL, cfg = NULL) {
  exposure <- as.character(exposure)[1L]
  if (!nzchar(exposure) || !exposure %in% names(data)) return(vif_tbl)
  if (!is.null(vif_tbl) && exposure %in% vif_tbl$Variable) return(vif_tbl)
  covars <- if (!is.null(vif_tbl) && nrow(vif_tbl)) vif_tbl$Variable else character(0)
  covars <- setdiff(covars, exposure)
  if (!length(covars)) return(vif_tbl)
  trial <- build_fn(unique(c(covars, exposure)), data)
  if (is.null(trial) || !nrow(trial)) return(vif_tbl)
  exp_row <- trial[trial$Variable == exposure, , drop = FALSE]
  if (!nrow(exp_row)) return(vif_tbl)
  out <- rbind(vif_tbl, exp_row)
  if (exists("order_vars_like_table1", mode = "function") && !is.null(ctx)) {
    ord <- order_vars_like_table1(out$Variable, ctx, cfg, data)
    ord <- ord[ord %in% out$Variable]
    out <- out[match(ord, out$Variable), , drop = FALSE]
  }
  out
}

.mcol_export_vif_phase_tables <- function(ctx, cfg, phase_label, vif_tbl, selected_vars,
                                           csv_name, table_caption, vif_tbl_pub = NULL) {
  if (is.null(vif_tbl) || !nrow(vif_tbl)) return(invisible(FALSE))

  thr <- .mcol_pipeline_effective_vif_thresholds(cfg)$strict
  mc_cfg <- cfg$multicollinearity %||% list()
  exposure <- if (exists("pipeline_index_exposure_var", mode = "function")) {
    pipeline_index_exposure_var(cfg)
  } else character(0)
  pub_src <- if (!is.null(vif_tbl_pub) && nrow(vif_tbl_pub)) vif_tbl_pub else vif_tbl
  if (exists("order_vars_like_table1", mode = "function")) {
    ord <- order_vars_like_table1(pub_src$Variable, ctx, cfg)
    pub_src <- pub_src[match(ord, pub_src$Variable), , drop = FALSE]
  }
  if (isTRUE(mc_cfg$export_full_vif_table %||% FALSE)) {
    full_name <- sub("\\.csv$", "_full.csv", csv_name, ignore.case = TRUE)
    if (identical(full_name, csv_name)) full_name <- paste0(csv_name, "_full")
    write.csv(pub_src, file.path(ctx$output_dir, full_name), row.names = FALSE)
    cli::cli_alert_info("Saved: {full_name}（全量 VIF 诊断表）")
  }

  vif_export <- vif_tbl[is.finite(vif_tbl$VIF) & vif_tbl$VIF < thr, , drop = FALSE]
  if (length(selected_vars)) {
    vif_export <- vif_export[vif_export$Variable %in% selected_vars, , drop = FALSE]
  }
  if (length(exposure) > 0L && nzchar(exposure)) {
    exp_row <- pub_src[pub_src$Variable == exposure, , drop = FALSE]
    if (nrow(exp_row) && !exposure %in% vif_export$Variable) {
      vif_export <- rbind(vif_export, exp_row)
      if (exists("order_vars_like_table1", mode = "function")) {
        ord <- order_vars_like_table1(vif_export$Variable, ctx, cfg)
        vif_export <- vif_export[match(ord, vif_export$Variable), , drop = FALSE]
      }
    }
  }
  if (!nrow(vif_export)) {
    cli::cli_alert_warning("VIF {phase_label} 发表表：无 VIF < {thr} 的行，跳过导出")
    return(invisible(FALSE))
  }

  vif_export$Variable_display <- gsub("_", " ", vif_export$Variable, fixed = TRUE)
  vif_path <- file.path(ctx$output_dir, csv_name)
  write.csv(
    vif_export[, c("Variable_display", "VIF"), drop = FALSE],
    vif_path, row.names = FALSE
  )
  cli::cli_alert_success("Saved: {csv_name}（仅 VIF < {thr}；暴露指标始终保留）")

  tbl_pub <- vif_export[, c("Variable", "VIF"), drop = FALSE]
  names(tbl_pub)[names(tbl_pub) == "Variable"] <- "Variable"
  if ("Variable_display" %in% names(vif_export)) {
    tbl_pub$Variable <- vif_export$Variable_display
  } else {
    tbl_pub$Variable <- gsub("_", " ", tbl_pub$Variable, fixed = TRUE)
  }
  tbl_pub$VIF <- format_vif_pub_column(tbl_pub$VIF)
  cap_vif <- table_caption %||% paste0("Multicollinearity Analysis VIF ", phase_label)
  cap_vif <- sub("^Table S\\d+[a-z]?\\.\\s*", "", cap_vif)
  paths_vif <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_vif, "xlsx")
  tryCatch(
    export_sci_table(
      tbl_pub, paths_vif$filepath, title = paths_vif$title,
      blank_na_cells = FALSE, excel_use_prepared = FALSE
    ),
    error = function(e) cli::cli_alert_warning("VIF Excel export failed: {e$message}")
  )
  invisible(TRUE)
}

.mcol_resolve_demo_keywords <- function(cfg) {
  cfg <- cfg %||% list()
  st <- tolower(trimws(as.character(cfg$project$study_type %||% "")))
  pick_kw <- function(x) {
    kw <- as.character((x %||% list())$demo_keywords %||% character(0))
    kw[nzchar(kw)]
  }
  if (st == "incidence") {
    kw <- c(
      pick_kw(cfg$multivariate_incidence_binary),
      pick_kw(cfg$univariate_incidence_binary),
      pick_kw(cfg$multivariate_incidence_multiclass)
    )
    if (length(kw)) return(unique(kw))
  }
  kw <- c(
    pick_kw(cfg$multivariate_prognosis),
    pick_kw(cfg$univariate_prognosis),
    pick_kw(cfg$multivariate_nhanes)
  )
  if (length(kw)) return(unique(kw))
  as.character(((cfg$dual_db %||% list())$harmonization %||% list())$demo_keywords %||% character(0))
}

.mcol_model1_from_model2 <- function(model2, cfg, prev_m1 = character(0)) {
  model2 <- unique(as.character(model2[nzchar(as.character(model2))]))
  prev_m1 <- unique(as.character(prev_m1[nzchar(as.character(prev_m1))]))
  prev_m1 <- prev_m1[prev_m1 %in% model2]
  if (length(prev_m1)) return(prev_m1)

  demo_keywords <- .mcol_resolve_demo_keywords(cfg)
  if (!length(demo_keywords)) return(character(0))

  demo_pattern <- paste(demo_keywords, collapse = "|")
  unique(model2[grepl(demo_pattern, model2, ignore.case = TRUE)])
}

#' VIF final 后 Model1/Model2 拆分（多因素VIF → 单因素VIF → 三级回退非实验室）
.mcol_build_covariate_bl_cfg <- function(cfg) {
  demo_kw <- .mcol_resolve_demo_keywords(cfg)
  lcfg <- cfg$logistic_nhanes_weighted %||% cfg$logistic_covariates %||% list()
  list(
    model1_demographic_names = demo_kw,
    demo_factor_names = as.character(lcfg$demo_factor_names %||% unique(c(
      demo_kw, "PIR", "Income", "Insurance", "Language"
    ))),
    clinical_factor_names = as.character(lcfg$clinical_factor_names %||% c(
      "HDL", "Hypertension", "T2DM", "Hyperlipidemia", "COPD",
      "Heart_Failure", "CKD", "Pneumonia", "Cancer", "Stroke"
    ))
  )
}

.mcol_resolve_index_var <- function(cfg) {
  if (isTRUE((cfg$analysis_exclusion %||% list())$allow_no_index %||% FALSE)) {
    return("")
  }
  out <- as.character(
    (cfg$survival_batch %||% list())$current_index %||%
      (cfg$incidence_batch %||% list())$current_index %||%
      (cfg$logistic %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      if (exists("pipeline_index_exposure_var", mode = "function")) {
        pipeline_index_exposure_var(cfg)
      } else {
        NULL
      } %||%
      "BMI"
  )
  out <- out[!is.na(out) & nzchar(out)]
  if (length(out)) out[[1L]] else ""
}

#' 按决策树拆分 VIF final 池 → Model1 / Model2，并写入 tier 元数据供 Cox/logistic 随机搜索
.mcol_apply_vif_final_covariate_split <- function(ctx, cfg, selected, data) {
  index_var <- .mcol_resolve_index_var(cfg)
  screen_pool <- as.character(
    ctx$results$vif_screen_pass %||%
      ctx$results$vif_screen_pass_weighted %||%
      character(0)
  )
  bl_cfg <- .mcol_build_covariate_bl_cfg(cfg)

  if (exists(".lnw00_split_vif_final_models", mode = "function")) {
    split <- .lnw00_split_vif_final_models(
      selected, cfg, data, index_var, bl_cfg, screen_pool = screen_pool
    )
    Model1Factors <- split$M1
    Model2Factors <- split$M2
    ctx$results$covariate_model1_tier <- split$model1_tier %||% "mvif_demo"
    ctx$results$covariate_model2_lab_only <- isTRUE(split$model2_lab_only)
    ctx$results$covariate_m1_search_pool <- split$m1_search_pool %||% character(0)
    ctx$results$covariate_m2_search_pool <- split$m2_search_pool %||% character(0)
    ctx$results$nhanes_logistic_model1_tier <- ctx$results$covariate_model1_tier
    ctx$results$nhanes_logistic_model2_lab_only <- ctx$results$covariate_model2_lab_only
  } else {
    Model2Factors <- selected
    Model1Factors <- .mcol_model1_from_model2(
      Model2Factors, cfg, prev_m1 = ctx$results$Model1Factors %||% character(0)
    )
  }

  # 已有/可补 Age 时，去掉未进多因素 VIF 的填充人口学（Marital 等）
  # 强加 Age 不显著则保留单因素人口学回退
  if (exists("pipeline_uv_demo_fallback_model1", mode = "function")) {
    data_cols <- if (is.data.frame(data)) names(data) else character(0)
    age_sig <- if (exists("pipeline_forced_age_is_significant", mode = "function") &&
                   is.data.frame(data)) {
      pipeline_forced_age_is_significant(data, cfg, index_var)
    } else {
      NULL
    }
    keep_final <- intersect(Model1Factors, as.character(selected))
    extras <- setdiff(Model1Factors, as.character(selected))
    if (length(extras)) {
      trim <- pipeline_uv_demo_fallback_model1(
        extras, data_cols, cfg, age_significant = age_sig
      )
      dropped <- setdiff(extras, trim$M1)
      Model1Factors <- unique(c(keep_final, trim$M1))
      if (isFALSE(age_sig)) {
        cli::cli_alert_info(
          "协变量选择: 强加 Age 不显著，保留单因素填充人口学: {paste(extras, collapse = ', ')}"
        )
      } else if (length(dropped)) {
        Model2Factors <- unique(c(Model1Factors, setdiff(Model2Factors, dropped)))
        cli::cli_alert_info(
          "协变量选择: 已有 Age，从 Model1 去掉单因素填充人口学: {paste(dropped, collapse = ', ')}"
        )
      }
    }
  }

  if (exists("pipeline_strip_index_from_model_factors", mode = "function")) {
    stripped <- pipeline_strip_index_from_model_factors(Model1Factors, Model2Factors, cfg)
    Model1Factors <- stripped$M1
    Model2Factors <- stripped$M2
  }
  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(Model1Factors, Model2Factors, cfg, index_var)
    Model1Factors <- cn$M1
    Model2Factors <- cn$M2
  }

  list(ctx = ctx, Model1Factors = Model1Factors, Model2Factors = Model2Factors)
}

.mcol_run_vif_phase <- function(ctx, phase) {
  phase <- tolower(as.character(phase)[1L])
  if (!phase %in% c("screen", "final", "legacy")) {
    stop("Unknown VIF phase: ", phase, call. = FALSE)
  }

  cfg  <- ctx$config
  up_res <- pipeline_upstream_modeling_data(ctx)
  data <- up_res$data
  if (is.null(data)) stop("No data found. Run 'imputation' or 'data_clean' first.")

  mc_cfg <- cfg$multicollinearity %||% list()
  vth <- .mcol_pipeline_effective_vif_thresholds(cfg)
  vif_threshold <- vth$strict

  id_col <- cfg$data$id_column %||% NULL
  if (!is.null(id_col) && id_col %in% names(data)) {
    data <- data[, !names(data) %in% id_col, drop = FALSE]
  }

  phase_cfg <- mc_cfg[[phase]] %||% list()
  is_screen <- identical(phase, "screen")
  is_final  <- identical(phase, "final")
  is_legacy <- identical(phase, "legacy")

  if (is_screen) {
    input_vars <- as.character(ctx$results$tb_screen %||% character(0))
    input_vars <- unique(input_vars[nzchar(input_vars)])
    if (!length(input_vars)) {
      stop("multicollinearity_screen: tb_screen 为空，请先运行 univariate_prognosis / univariate_incidence_binary。", call. = FALSE)
    }
    # 防御：若单因素未限 Table1，VIF screen 仍只保留基线表变量池
    if (exists("pipeline_dual_db_include_predictors", mode = "function")) {
      t1_pool <- pipeline_dual_db_include_predictors(cfg)
      if (length(t1_pool)) {
        keep <- intersect(input_vars, t1_pool)
        drop_n <- length(setdiff(input_vars, keep))
        if (drop_n > 0L) {
          cli::cli_alert_warning(
            "VIF screen: 剔除 {drop_n} 个非 Table1 特征，保留 {length(keep)} 个"
          )
        }
        input_vars <- keep
      }
    }
    if (!length(input_vars)) {
      stop(
        "multicollinearity_screen: 与 Table1 变量池交集为空。",
        "请检查 univariate_from_baseline_table1 / baseline_binary$include_vars。",
        call. = FALSE
      )
    }
    cli::cli_h2("VIF screening（单因素 p<0.1 ∩ Table1，{length(input_vars)} 个变量）")
  } else if (is_final) {
    input_vars <- as.character(ctx$results$tb2 %||% ctx$results$multivar_features %||% character(0))
    input_vars <- unique(input_vars[nzchar(input_vars)])
    if (!length(input_vars)) {
      for (fb_key in c("tb_screen", "tb1", "vif_screen_pass", "Model2Factors")) {
        fb <- as.character(ctx$results[[fb_key]] %||% character(0))
        fb <- unique(fb[nzchar(fb)])
        if (length(fb)) {
          input_vars <- fb
          cli::cli_alert_warning(
            "multicollinearity_final: tb2 为空，回退单因素/{fb_key}（{length(input_vars)} 个）"
          )
          break
        }
      }
    }
    if (!length(input_vars)) {
      stop("multicollinearity_final: tb2 为空，请先运行 multivariate_prognosis。", call. = FALSE)
    }
    cli::cli_h2("VIF final（多因素 p<0.05 显著变量，{length(input_vars)} 个）")
  } else {
    mc_excl <- unique(c(
      as.character(mc_cfg$exclude_vars %||% character(0)),
      as.character(id_col %||% character(0))
    ))
    input_vars <- setdiff(ctx$results$Model2Factors %||% character(0), mc_excl)
    if (!length(input_vars)) {
      stop("multicollinearity: Model2Factors 为空。", call. = FALSE)
    }
  }

  mc_excl <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(id_col %||% character(0))
  ))
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    mc_excl <- setdiff(mc_excl, pipeline_index_exposure_var(cfg))
  }
  if (length(mc_excl) && (is_screen || is_final)) {
    dropped_excl <- intersect(input_vars, mc_excl)
    if (length(dropped_excl)) {
      cli::cli_alert_info("exclude_vars 强制排除: {paste(dropped_excl, collapse = ', ')}")
    }
    input_vars <- setdiff(input_vars, mc_excl)
    if (!length(input_vars)) {
      stop(sprintf("multicollinearity_%s: exclude_vars 后无变量保留。", phase), call. = FALSE)
    }
  }

  cli::cli_alert_info("VIF 阈值: {vif_threshold}（min_vars={vth$min_vars}，不放宽至 VIF<{vth$loose}）")

  exposure <- if (exists("pipeline_index_exposure_var", mode = "function")) {
    pipeline_index_exposure_var(cfg)
  } else {
    character(0)
  }
  # 当前暴露指标（如 MCV）必须以连续变量进入 VIF 表，即使不在 Model1 协变量池
  if (length(exposure) && exposure %in% names(data)) {
    input_vars <- unique(c(input_vars, exposure))
  }

  vif_comp_exclude <- if (exists("pipeline_index_vif_exclude_vars", mode = "function")) {
    intersect(pipeline_index_vif_exclude_vars(cfg), input_vars)
  } else {
    character(0)
  }
  if (length(vif_comp_exclude)) {
    cli::cli_alert_info(
      "VIF 设计矩阵排除暴露组分: {paste(vif_comp_exclude, collapse = ', ')}"
    )
  }

  vif_tbl_vars <- setdiff(input_vars, vif_comp_exclude)
  ar_cfg <- mc_cfg$anthropometric_vif_resolution %||% list()
  if (isTRUE(ar_cfg$enable %||% FALSE)) {
    ar_pre <- .mcol_resolve_anthropometric_vif_vars(vif_tbl_vars, data, cfg)
    vif_tbl_vars <- ar_pre$kept
    if (length(ar_pre$dropped)) {
      cli::cli_alert_info(
        "VIF 表基于人体测量协调后变量集 [{ar_pre$strategy}]，已剔除: {paste(ar_pre$dropped, collapse = ', ')}"
      )
    }
  }
  vif_covariate_vars <- setdiff(vif_tbl_vars, exposure)
  vif_tbl <- .mcol_build_orig_var_vif_table(vif_tbl_vars, data)
  if (is.null(vif_tbl)) stop("VIF 计算失败。", call. = FALSE)
  if (exists(".reorder_vif_table_like_univariate", mode = "function")) {
    vif_tbl <- .reorder_vif_table_like_univariate(vif_tbl, cfg, data, ctx)
  }

  if (is_screen) {
    selected <- .mcol_compute_screen_pass(vif_covariate_vars, data, cfg, vif_threshold)
    if (exists("order_vars_like_table1", mode = "function")) {
      selected <- order_vars_like_table1(selected, ctx, cfg, data)
    }
    # vif_screen_pass：纯 VIF 筛选结果（不含强制人口学扩写）
    ctx$results$vif_screen_pass <- selected
    ctx <- save_result(ctx, "vif_screen_pass", selected, "VIF_screen_pass.RData")
    writeLines(selected, file.path(ctx$output_dir, "VIF_screen_pass.txt"))
    demo_kw <- .mcol_resolve_demo_keywords(cfg)
    m1 <- intersect(selected, demo_kw)
    if (!length(m1) && exists(".mcol_model1_from_model2", mode = "function")) {
      m1 <- .mcol_model1_from_model2(selected, cfg, prev_m1 = ctx$results$Model1Factors %||% character(0))
    }
    m2 <- selected
    # 强制 Age → Model1/Model2（调整协变量用；即使单因素未入选）。Gender 默认不强制。
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      before <- m2
      merged <- pipeline_merge_force_covariates(m1, m2, names(data), cfg)
      m1 <- merged$M1
      m2 <- merged$M2
      force_only <- setdiff(m2, before)
      if (length(force_only)) {
        cli::cli_alert_info(
          "VIF screen: 强制纳入调整协变量: {paste(force_only, collapse = ', ')}"
        )
      }
    }
    ctx$results$Model1Factors <- m1
    ctx$results$Model2Factors <- m2
    ctx$results$univar_features <- m2
    ctx <- save_result(ctx, "Model2Factors", m2, "Model2Factors.RData")
    writeLines(m2, file.path(ctx$output_dir, "Model2Factors.txt"))
    try(ctx <- save_result(ctx, "Model1Factors", m1, "Model1Factors.RData"), silent = TRUE)
    try(writeLines(m1, file.path(ctx$output_dir, "Model1Factors.txt")), silent = TRUE)
    cli::cli_alert_success("screen 筛选后进入特征选择: {length(m2)} 个变量（已写入 Model2Factors）")
    cli::cli_alert_info("保留: {paste(m2, collapse = ', ')}")
    cli::cli_alert_info("Model1 (含强制人口学): {paste(m1, collapse = ', ')}")
    removed <- setdiff(input_vars, selected)
    if (length(removed)) {
      cli::cli_alert_warning("screen 未进入多因素: {paste(removed, collapse = ', ')}")
    }
    csv_name <- phase_cfg$csv_name %||% "VIF_check_screen.csv"
    table_caption <- phase_cfg$table_title %||%
      "Multicollinearity Analysis VIF screen"
    vif_tbl_pub <- .mcol_build_orig_var_vif_table(selected, data)
    if (exists(".reorder_vif_table_like_univariate", mode = "function") && !is.null(vif_tbl_pub)) {
      vif_tbl_pub <- .reorder_vif_table_like_univariate(vif_tbl_pub, cfg, data, ctx)
    }
    # 发表表强制保留当前暴露（与 final 一致）；不强制写入 Model2Factors
    exposure <- pipeline_index_exposure_var(cfg)
    if (nzchar(as.character(exposure %||% "")[1L])) {
      vif_tbl_pub <- .mcol_append_exposure_vif_row(
        vif_tbl_pub %||% vif_tbl, exposure, data, .mcol_build_orig_var_vif_table, ctx, cfg
      )
    }
    .mcol_export_vif_phase_tables(
      ctx, cfg, "screen", vif_tbl_pub %||% vif_tbl, selected, csv_name, table_caption,
      vif_tbl_pub = vif_tbl_pub
    )
    ctx$results$vif_screen_table <- vif_tbl
    cli::cli_alert_success("VIF screening 完成")
    return(ctx)
  }

  if (is_final) {
    selected <- .mcol_compute_final_pass(setdiff(input_vars, vif_comp_exclude), data, vif_threshold)
    if (exists("order_vars_like_table1", mode = "function")) {
      selected <- order_vars_like_table1(selected, ctx, cfg, data)
    }
    if (!length(selected)) {
      ctx$results$pause_point <- list(
        block = "multicollinearity_final",
        reason = "VIF final 筛选后无变量保留",
        suggestion = paste0("检查共线性或放宽 vif_threshold_strict (当前: ", vif_threshold, ")"),
        data_snapshot = utils::head(vif_tbl, 10)
      )
      stop("PAUSE_FOR_USER_DECISION: VIF final 筛选后无变量。")
    }

    split_res <- .mcol_apply_vif_final_covariate_split(ctx, cfg, selected, data)
    ctx <- split_res$ctx
    Model1Factors <- split_res$Model1Factors
    Model2Factors <- split_res$Model2Factors
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      merged <- pipeline_merge_force_covariates(
        Model1Factors, Model2Factors, names(data), cfg
      )
      Model1Factors <- merged$M1
      Model2Factors <- merged$M2
    }
    if (!length(Model1Factors)) {
      cli::cli_alert_warning(
        "multicollinearity_final: Model1Factors 为空；请检查 demo_keywords 或单因素 VIF 池。"
      )
    }

    ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
    ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
    writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
    writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))

    summary_dir <- file.path(ctx$output_dir_tables, "Summary")
    root_summary <- file.path(ctx$root_output_dir %||% dirname(ctx$output_dir), "Tables", "Summary")
    for (d in unique(c(summary_dir, root_summary))) {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    ix_lab <- as.character(cfg$survival$index_var %||% cfg$survival$exposure %||% "Index")[1L]
    db_lab <- tolower(trimws(as.character(cfg$project$database %||% "db")))
    # 轨迹预后：FinalCovariates_* 留给 JLCM survival 协变量；VIF 写 Model2 专用文件，避免覆盖
    is_traj <- !is.null(cfg$trajectory_jlcm) ||
      length(ctx$results$trajectory_jlcm_models %||% list()) > 0L
    cov_fname <- if (is_traj) {
      paste0("FinalCovariates_Model2_", ix_lab, "_", db_lab, ".txt")
    } else {
      paste0("FinalCovariates_", ix_lab, "_", db_lab, ".txt")
    }
    fp_cov <- file.path(summary_dir, cov_fname)
    cov_lines <- c(
      paste0("# Final covariates (Model2Factors", if (is_traj) ", VIF multivariate final" else "",
             ") — ", ix_lab, " / ", toupper(db_lab)),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      Model2Factors
    )
    writeLines(cov_lines, fp_cov)
    if (!identical(normalizePath(root_summary, winslash = "/"), normalizePath(summary_dir, winslash = "/"))) {
      writeLines(cov_lines, file.path(root_summary, cov_fname))
    }
    cli::cli_alert_success("最终协变量已导出: {.file {basename(fp_cov)}}")

    csv_name <- phase_cfg$csv_name %||% "VIF_check_final.csv"
    table_caption <- phase_cfg$table_title %||%
      "Multicollinearity Analysis VIF final"
    vif_tbl_pub <- .mcol_append_exposure_vif_row(
      vif_tbl, exposure, data, .mcol_build_orig_var_vif_table, ctx, cfg
    )
    .mcol_export_vif_phase_tables(
      ctx, cfg, "final", vif_tbl, selected, csv_name, table_caption,
      vif_tbl_pub = vif_tbl_pub
    )

    ctx$results$Model1Factors <- Model1Factors
    ctx$results$Model2Factors <- Model2Factors
    ctx$results$vif_final_pass <- selected
    ctx$results$vif_final_table <- vif_tbl
    ctx$results$univar_features <- Model2Factors

    cli::cli_alert_success("Model2Factors (final): {length(Model2Factors)} 个 — {paste(Model2Factors, collapse = ', ')}")
    cli::cli_alert_info("Model1Factors (人口学): {length(Model1Factors)} 个 — {paste(Model1Factors, collapse = ', ')}")
    removed <- setdiff(input_vars, selected)
    if (length(removed)) {
      cli::cli_alert_warning("final VIF 移除: {paste(removed, collapse = ', ')}")
    }
    cli::cli_alert_success("VIF final 完成")
    return(ctx)
  }

  # legacy: 保留旧版 multicollinearity 行为（Model2Factors 输入 → VIF 筛选）
  NULL
}


block_multicollinearity <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(car)
  })

  cfg           <- ctx$config
  data          <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'imputation' or 'data_clean' first.")

  mc_cfg <- cfg$multicollinearity %||% list()
  vth <- .mcol_pipeline_effective_vif_thresholds(cfg)
  vif_threshold_strict <- vth$strict
  vif_threshold_loose  <- vth$loose
  min_vars_threshold   <- vth$min_vars
  if (isTRUE(vth$feature_selection_follows)) {
    cli::cli_alert_info(
      "下游将运行 feature_selection，VIF 筛选用阈值 {vif_threshold_strict}（config$multicollinearity$vif_threshold_before_feature_selection）"
    )
  }

  vif_extra_raw <- mc_cfg$vif_design_extra_predictors %||% character(0)
  vif_extra_req <- unique(as.character(vif_extra_raw[!is.na(vif_extra_raw) & nzchar(vif_extra_raw)]))
  append_extra_to_m2 <- isTRUE(mc_cfg$vif_append_extra_to_model2_outputs %||% FALSE)

  # 将配置中的列名对齐到 data 实际列名（精确 → 大小写不敏感唯一匹配）
  .match_cfg_vars_to_data <- function(req, dnames) {
    if (length(req) == 0L) return(character(0))
    dn <- unique(as.character(dnames))
    dn_lower <- tolower(dn)
    out <- character(0)
    for (r in req) {
      if (r %in% dn) {
        out <- c(out, r)
        next
      }
      hit <- dn[dn_lower == tolower(r)]
      if (length(hit) == 1L) {
        out <- c(out, hit)
        if (hit != r) {
          cli::cli_alert_info("vif_design_extra_predictors: 配置名「{r}」→ 数据列「{hit}」（大小写不敏感）")
        }
      } else if (length(hit) > 1L) {
        cli::cli_alert_warning(
          "vif_design_extra_predictors: 「{r}」匹配到多个列，已跳过: {paste(hit, collapse = ', ')}"
        )
      } else {
        cli::cli_alert_warning(
          "vif_design_extra_predictors: 数据中找不到「{r}」（已试大小写不敏感）。请核对 imputed/cleaned 列名或 column_mapping 映射结果。"
        )
      }
    }
    unique(out)
  }

  cli::cli_alert_info("VIF严格阈值: {vif_threshold_strict}")
  cli::cli_alert_info("VIF宽松阈值: {vif_threshold_loose}")
  cli::cli_alert_info("最小变量数阈值: {min_vars_threshold}")

  id_col <- cfg$data$id_column %||% NULL
  if (!is.null(id_col) && id_col %in% names(data))
    data <- data[, !names(data) %in% id_col, drop = FALSE]

  # 从 config$multicollinearity$exclude_vars 读取强制排除列表（含 id_column）
  mc_excl <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(id_col %||% character(0))
  ))

  Model1Factors <- setdiff(ctx$results$Model1Factors %||% character(0), mc_excl)
  Model2Factors <- setdiff(ctx$results$Model2Factors %||% character(0), mc_excl)

  cli::cli_h2("BMI/Weight/Height 人体测量 VIF 协调（≥2 项并存须各自 VIF < {vif_threshold_strict}，否则渐进剔除）")
  ar_anthro <- .mcol_apply_anthropometric_vif_resolution(
    Model2Factors, data, cfg, ctx, "multicollinearity"
  )
  ctx <- ar_anthro$ctx
  if (length(ar_anthro$dropped) > 0L) {
    Model2Factors <- ar_anthro$kept
    Model1Factors <- setdiff(Model1Factors, ar_anthro$dropped)
    ctx$results$univar_features <- setdiff(
      as.character(ctx$results$univar_features %||% character(0)),
      ar_anthro$dropped
    )
  }

  if (length(Model1Factors) == 0 && length(Model2Factors) == 0) {
    ctx$results$pause_point <- list(
      block = "block_multicollinearity",
      reason = "未找到 Model1Factors 或 Model2Factors (No Model1Factors or Model2Factors found)",
      suggestion = "请先运行 run_univariate_block() 与 run_multivariate_block()（06/07 子块）",
      data_snapshot = NULL
    )
    stop("PAUSE_FOR_USER_DECISION: 未找到模型变量，请查看 ctx$results$pause_point 并指示下一步操作。")
  }

  cli::cli_alert_info("Model1Factors: {length(Model1Factors)} 个变量（仅用于回写，不参与VIF计算）")
  cli::cli_alert_info("Model2Factors: {length(Model2Factors)} 个变量")

  vif_extra <- .match_cfg_vars_to_data(vif_extra_req, names(data))
  vars_vif <- unique(c(Model2Factors, vif_extra))
  if (length(vif_extra_req) > 0L && length(vif_extra) == 0L) {
    cli::cli_alert_warning(
      "vif_design_extra_predictors 在配置中有 {length(vif_extra_req)} 项，但无一能匹配到当前数据列名；VIF 仅基于 Model2Factors。"
    )
  }
  if (length(vif_extra) > 0L) {
    cli::cli_alert_info(
      "VIF 设计矩阵额外纳入: {length(vif_extra)} 个 — {paste(vif_extra, collapse = ', ')}（默认不写 Model2Factors.txt；设 vif_append_extra_to_model2_outputs=TRUE 可追加）"
    )
  }

  # 仅基于自变量设计矩阵计算 VIF（与结局/研究类型无关，避免二分类硬编码 Y 导致多分类错误）
  .calculate_vif <- function(vars, data) {
    if (length(vars) <= 1) {
      return(list(vif_df = NULL, vif_values = NULL))
    }

    valid_vars <- vars[vars %in% names(data)]
    if (length(valid_vars) <= 1) {
      return(list(vif_df = NULL, vif_values = NULL))
    }

    df_subset <- data[, valid_vars, drop = FALSE]

    for (v in valid_vars) {
      if (is.factor(df_subset[[v]]) || is.character(df_subset[[v]])) {
        df_subset[[v]] <- as.numeric(as.factor(df_subset[[v]]))
      }
      if (any(is.na(df_subset[[v]]))) {
        df_subset[[v]][is.na(df_subset[[v]])] <- median(df_subset[[v]], na.rm = TRUE)
      }
    }

    X <- tryCatch({
      mm <- model.matrix(~ ., data = df_subset)
      mm[, -1L, drop = FALSE]
    }, error = function(e) NULL)

    if (is.null(X) || ncol(X) == 0L) {
      return(list(vif_df = NULL, vif_values = NULL))
    }

    vif_values <- tryCatch({
      r2s <- sapply(seq_len(ncol(X)), function(j) {
        if (ncol(X) == 1L) return(0)
        summary(lm(X[, j] ~ X[, -j, drop = FALSE]))$r.squared
      })
      vif_vals <- 1 / (1 - r2s)
      names(vif_vals) <- colnames(X)
      vif_vals
    }, error = function(e) NULL)

    if (is.null(vif_values)) {
      return(list(vif_df = NULL, vif_values = NULL))
    }

    vif_df <- data.frame(
      Variable = names(vif_values),
      VIF = round(vif_values, 3),
      stringsAsFactors = FALSE
    )

    list(vif_df = vif_df, vif_values = vif_values)
  }

  .filter_by_vif <- function(vars, data, threshold_strict, threshold_loose, min_vars) {
    if (length(vars) <= 1) {
      return(list(kept = vars, vif_df = NULL, threshold_used = NA))
    }

    result <- .calculate_vif(vars, data)
    vif_df <- result$vif_df
    vif_values <- result$vif_values

    if (is.null(vif_values)) {
      return(list(kept = vars, vif_df = NULL, threshold_used = NA))
    }

    kept_strict <- names(vif_values)[vif_values < threshold_strict]
    threshold_used <- threshold_strict

    if (length(kept_strict) < min_vars) {
      cli::cli_alert_info("VIF < {threshold_strict} 的变量数 ({length(kept_strict)}) < {min_vars}，放宽标准至 VIF < {threshold_loose}")
      kept_strict <- names(vif_values)[vif_values < threshold_loose]
      threshold_used <- threshold_loose
    }

    # 将哑变量列名（如 Race2、Education3）映射回原始变量名。
    # 修正：使用精确前缀匹配（varname 后紧跟数字/非单词字符，或完全相同），避免 Age 匹配 Age_Group。
    original_names <- vars
    kept_final <- character(0)
    for (v in original_names) {
      matching <- names(vif_values)[
        names(vif_values) == v |
        grepl(paste0("^", v, "(?:[0-9]|[^A-Za-z0-9_])"), names(vif_values), perl = TRUE)
      ]
      if (any(matching %in% kept_strict)) {
        kept_final <- c(kept_final, v)
      }
    }

    list(kept = unique(kept_final), vif_df = vif_df, threshold_used = threshold_used)
  }

  all_vif_results <- list()

  cli::cli_h2("Model2Factors VIF 检验（设计矩阵 = Model2 ∪ vif_design_extra_predictors）")
  if (length(Model2Factors) > 0) {
    result2 <- .filter_by_vif(vars_vif, data,
                              vif_threshold_strict, vif_threshold_loose, min_vars_threshold)
    Model2Factors_filtered <- Model2Factors[Model2Factors %in% result2$kept]
    if (isTRUE(append_extra_to_m2) && length(vif_extra) > 0L) {
      add_m2 <- vif_extra[!vif_extra %in% Model2Factors_filtered]
      if (length(add_m2) > 0L) {
        Model2Factors_filtered <- c(Model2Factors_filtered, add_m2)
        cli::cli_alert_info(
          "vif_append_extra_to_model2_outputs=TRUE: 已将额外变量追加到 Model2 输出末尾: {paste(add_m2, collapse = ', ')}"
        )
      }
    }
    threshold_used2 <- result2$threshold_used

    if (!is.null(result2$vif_df)) {
      all_vif_results$Model2 <- cbind(Model = "Model2", result2$vif_df)
    }

    cli::cli_alert_success("Model2Factors 筛选后: {length(Model2Factors_filtered)} 个变量 (阈值: VIF < {threshold_used2})")
    cli::cli_alert_info("保留变量: {paste(Model2Factors_filtered, collapse = ', ')}")

    removed2 <- setdiff(Model2Factors, Model2Factors_filtered)
    if (length(removed2) > 0) {
      cli::cli_alert_warning("移除变量 (共线性): {paste(removed2, collapse = ', ')}")
    }
  } else {
    Model2Factors_filtered <- character(0)
  }

  # Model1 不单独做 VIF；仅从筛选后的 Model2 中取交集，保持原顺序
  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(Model1Factors, Model2Factors_filtered, cfg)
    Model1Factors_filtered <- cn$M1
    Model2Factors_filtered <- cn$M2
  } else {
    Model1Factors_filtered <- Model1Factors[Model1Factors %in% Model2Factors_filtered]
  }
  cli::cli_alert_info("Model1Factors 从 Model2Factors 筛选结果继承: {length(Model1Factors_filtered)} 个变量")

  if (length(Model2Factors_filtered) == 0) {
    ctx$results$pause_point <- list(
      block = "block_multicollinearity",
      reason = "Model2Factors 经 VIF 筛选后无变量保留 (No Model2Factors remained after VIF filtering)",
      suggestion = "请检查变量间的共线性关系，或考虑放宽VIF阈值 (当前严格: {vif_threshold_strict}, 宽松: {vif_threshold_loose})",
      data_snapshot = if (length(all_vif_results) > 0) head(do.call(rbind, all_vif_results), 10) else NULL
    )
    stop("PAUSE_FOR_USER_DECISION: Model2Factors 经VIF筛选后无变量保留，请查看 ctx$results$pause_point 并指示下一步操作。")
  }

  cli::cli_h2("保存结果")

  design_list_path <- file.path(ctx$output_dir, "VIF_design_matrix_predictors.txt")
  writeLines(vars_vif, design_list_path)
  cli::cli_alert_success("Saved: VIF_design_matrix_predictors.txt（进入 model.matrix 的原始变量名，含 extra）")

  if (length(all_vif_results) > 0) {
    vif_combined <- do.call(rbind, all_vif_results)
    rownames(vif_combined) <- NULL
    vif_export <- vif_combined[, c("Variable", "VIF"), drop = FALSE]
    # 发表表与 Model2 筛选同一阈值（VIF < vif_threshold_strict；接 feature_selection 时为 10）
    vif_export <- vif_export[
      is.finite(vif_export$VIF) & vif_export$VIF < vif_threshold_strict,
      , drop = FALSE
    ]
    cli::cli_alert_info(
      "Table S3 / VIF_check：仅保留 VIF < {vif_threshold_strict}（与 Model2Factors 筛选一致）"
    )
    anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
    if (length(anthro_drop)) {
      vif_export <- vif_export[!vif_export$Variable %in% anthro_drop, , drop = FALSE]
    }
    vif_export$Variable <- gsub("_", " ", vif_export$Variable, fixed = TRUE)
    vif_path <- file.path(ctx$output_dir, "VIF_check.csv")
    write.csv(vif_export, vif_path, row.names = FALSE)
    cli::cli_alert_success("Saved: VIF_check.csv")

    paths_vif <- pub_paths(
      ctx, ctx$output_dir_tables, "supp_table",
      paste0("Multicollinearity Analysis (VIF) for ", cfg$project$disease),
      "xlsx"
    )
    tryCatch(
      export_sci_table(vif_export, paths_vif$filepath, title = paths_vif$title),
      error = function(e) cli::cli_alert_warning("Excel export failed: {e$message}")
    )
  }

  ctx <- save_result(ctx, "Model1Factors", Model1Factors_filtered, "Model1Factors.RData")
  ctx <- save_result(ctx, "Model2Factors", Model2Factors_filtered, "Model2Factors.RData")

  model1_txt_path <- file.path(ctx$output_dir, "Model1Factors.txt")
  writeLines(Model1Factors_filtered, model1_txt_path)
  cli::cli_alert_success("Saved: Model1Factors.txt")

  model2_txt_path <- file.path(ctx$output_dir, "Model2Factors.txt")
  writeLines(Model2Factors_filtered, model2_txt_path)
  cli::cli_alert_success("Saved: Model2Factors.txt")

  ctx$results$Model1Factors <- Model1Factors_filtered
  ctx$results$Model2Factors <- Model2Factors_filtered
  ctx$results$vif_results <- all_vif_results
  ctx$results$vif_design_extra_predictors <- vif_extra

  # VIF 后下游对齐 Model2；univar_features 与 VIF 后 Model2 一致（D06 仍保留单因素 tb1）
  ctx$results$univar_features <- Model2Factors_filtered
  cli::cli_alert_info(
    "feature_selection 将使用 VIF 后 Model2（{length(Model2Factors_filtered)} 个）: {paste(Model2Factors_filtered, collapse = ', ')}"
  )
  cli::cli_alert_info("D06_Univariable_Features.RData 保留单因素 tb1；Table S2/S2a 由 06/07 块导出。")

  cli::cli_alert_success("多重共线性检验完成")

  ctx
}

# ─────────────────────────────────────────────────────────────────────────────
#  NHANES 加权版 VIF（C05_VIF 风格）
#  仅当 database_type 含 "nhanes"/"nhance" 时追加运行：
#    - 使用 lm(..., weights = new_Weight) 计算加权 VIF（与 C05 一致）
#    - 结果覆盖 ctx$results$Model1Factors / Model2Factors
#    - 导出 "Table S7. Weighted Multicollinearity VIF (NHANES).xlsx"
#
#  原有逻辑问题已修正（见 .filter_by_vif 中哑变量映射）。
# ─────────────────────────────────────────────────────────────────────────────
.block_mc_nhanes_weighted <- function(ctx) {
  cfg        <- ctx$config
  nhanes_cfg <- cfg$nhanes %||% list()
  mc_cfg     <- cfg$multicollinearity %||% list()

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    cli::cli_alert_warning("block_mc(NHANES): ctx$results$nhanes_design 为空，跳过加权 VIF。")
    return(ctx)
  }

  wt_col <- as.character(nhanes_cfg$survey_weight %||% "new_Weight")[1L]
  data_vif <- design$variables
  if (!wt_col %in% names(data_vif)) {
    cli::cli_alert_warning("block_mc(NHANES): 权重列 '{wt_col}' 不在 design$variables 中，跳过加权 VIF。")
    return(ctx)
  }

  vth <- .mcol_pipeline_effective_vif_thresholds(cfg)
  vif_strict <- vth$strict
  vif_loose  <- vth$loose
  min_vars   <- vth$min_vars
  if (isTRUE(vth$feature_selection_follows)) {
    cli::cli_alert_info(
      "block_mc(NHANES): 下游 feature_selection，加权 VIF 阈值 {vif_strict}"
    )
  }

  # 从加权分析已更新的 Model2Factors 读取（nhanes 加权单/多因素后已覆盖）
  Model1Factors <- ctx$results$Model1Factors %||% character(0)
  Model2Factors <- ctx$results$Model2Factors %||% character(0)
  if (length(Model2Factors) == 0L) {
    cli::cli_alert_warning("block_mc(NHANES): Model2Factors 为空，跳过加权 VIF。")
    return(ctx)
  }

  ar_nhanes <- .mcol_apply_anthropometric_vif_resolution(
    Model2Factors, as.data.frame(data_vif), cfg, ctx, "multicollinearity(NHANES weighted)"
  )
  ctx <- ar_nhanes$ctx
  if (length(ar_nhanes$dropped) > 0L) {
    Model2Factors <- ar_nhanes$kept
    Model1Factors <- setdiff(Model1Factors, ar_nhanes$dropped)
    ctx$results$univar_features <- setdiff(
      as.character(ctx$results$univar_features %||% character(0)),
      ar_nhanes$dropped
    )
  }

  # 从 config 读取所有排除变量，block 里不出现任何硬编码变量名
  drop_always <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(mc_cfg$weighted_vif_drop_vars %||% character(0)),
    as.character(cfg$data$id_column %||% character(0))
  ))
  GetFactors <- intersect(setdiff(Model2Factors, drop_always), names(data_vif))
  ve_raw_n <- mc_cfg$vif_design_extra_predictors %||% character(0)
  vif_extra_req_n <- unique(as.character(ve_raw_n[!is.na(ve_raw_n) & nzchar(ve_raw_n)]))
  dn_v <- names(data_vif)
  dn_l <- tolower(dn_v)
  vif_extra_n <- character(0)
  for (r in vif_extra_req_n) {
    if (r %in% dn_v) {
      vif_extra_n <- c(vif_extra_n, r)
    } else {
      hit <- dn_v[dn_l == tolower(r)]
      if (length(hit) == 1L) vif_extra_n <- c(vif_extra_n, hit)
    }
  }
  vif_extra_n <- unique(setdiff(vif_extra_n, drop_always))
  GetFactors <- unique(c(GetFactors, vif_extra_n))
  if (length(GetFactors) == 0L) {
    cli::cli_alert_warning("block_mc(NHANES): Model2Factors 中无有效列，跳过加权 VIF。")
    return(ctx)
  }
  if (length(vif_extra_n) > 0L) {
    cli::cli_alert_info("block_mc(NHANES): VIF 设计矩阵额外纳入: {paste(vif_extra_n, collapse = ', ')}")
  }

  # 因子列转数值（与 C05 一致）
  df_w <- data_vif
  for (nm in intersect(GetFactors, names(df_w)[sapply(df_w, is.factor)])) {
    df_w[[nm]] <- as.numeric(as.factor(df_w[[nm]]))
  }
  # 缺失值填充（中位数）
  for (nm in GetFactors) {
    if (any(is.na(df_w[[nm]]))) {
      df_w[[nm]][is.na(df_w[[nm]])] <- stats::median(df_w[[nm]], na.rm = TRUE)
    }
  }

  # 加权 VIF：lm(x_j ~ x_{-j}, weights = new_Weight)，计算 1/(1-R²)
  .weighted_vif <- function(vars, df, wt) {
    X <- tryCatch({
      mm <- stats::model.matrix(stats::as.formula(paste0("~ ", paste(vars, collapse = "+"))), data = df)
      mm[, -1L, drop = FALSE]
    }, error = function(e) NULL)
    if (is.null(X) || ncol(X) < 2L) return(NULL)
    w <- df[[wt]]
    r2s <- sapply(seq_len(ncol(X)), function(j) {
      fit <- tryCatch(
        stats::lm(X[, j] ~ X[, -j, drop = FALSE], weights = w),
        error = function(e) NULL
      )
      if (is.null(fit)) return(0)
      summary(fit)$r.squared
    })
    vif_v <- 1 / (1 - r2s)
    names(vif_v) <- colnames(X)
    vif_v
  }

  vif_vals <- tryCatch(
    .weighted_vif(GetFactors, df_w, wt_col),
    error = function(e) {
      cli::cli_alert_warning("block_mc(NHANES): 加权 VIF 计算失败: {e$message}")
      NULL
    }
  )

  if (is.null(vif_vals)) {
    cli::cli_alert_warning("block_mc(NHANES): 加权 VIF 失败，沿用非加权筛选结果。")
    return(ctx)
  }

  if (is.matrix(vif_vals)) vif_vals <- vif_vals[, 1]
  tb_vif_w <- data.frame(Variable = names(vif_vals), VIF = round(as.numeric(vif_vals), 3),
                          stringsAsFactors = FALSE)

  VIF_OK <- tb_vif_w$Variable[tb_vif_w$VIF < vif_strict]
  if (length(VIF_OK) < 10L) {
    VIF_OK <- tb_vif_w$Variable[tb_vif_w$VIF < vif_loose]
    cli::cli_alert_info("block_mc(NHANES): 加权 VIF<{vif_strict} 变量不足 10，放宽至 VIF<{vif_loose}: {paste(VIF_OK,collapse=',')}")
  } else {
    cli::cli_alert_info("block_mc(NHANES): 加权 VIF<{vif_strict}: {paste(VIF_OK,collapse=',')}")
  }

  # 哑变量列名映射回原始变量名（与 .filter_by_vif 修正版一致）
  .map_dummies_to_orig <- function(vif_ok_names, orig_vars) {
    kept <- character(0)
    for (v in orig_vars) {
      hit <- vif_ok_names[
        vif_ok_names == v |
        grepl(paste0("^", v, "(?:[0-9]|[^A-Za-z0-9_])"), vif_ok_names, perl = TRUE)
      ]
      if (length(hit) > 0L) kept <- c(kept, v)
    }
    unique(kept)
  }

  M2f_new <- .map_dummies_to_orig(VIF_OK, Model2Factors)
  if (isTRUE(mc_cfg$vif_append_extra_to_model2_outputs %||% FALSE) && length(vif_extra_n) > 0L) {
    extra_kept <- .map_dummies_to_orig(VIF_OK, vif_extra_n)
    add_e <- extra_kept[!extra_kept %in% M2f_new]
    if (length(add_e) > 0L) {
      M2f_new <- c(M2f_new, add_e)
      cli::cli_alert_info(
        "block_mc(NHANES): vif_append_extra_to_model2_outputs=TRUE，追加通过阈值的 extra: {paste(add_e, collapse = ', ')}"
      )
    }
  }
  if (length(M2f_new) == 0L) {
    cli::cli_alert_warning("block_mc(NHANES): 加权 VIF 筛选后 Model2Factors 为空，保留原筛选结果。")
    return(ctx)
  }
  M1f_new <- Model1Factors[Model1Factors %in% M2f_new]
  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(M1f_new, M2f_new, cfg)
    M1f_new <- cn$M1
    M2f_new <- cn$M2
  }

  ctx$results$Model1Factors <- M1f_new
  ctx$results$Model2Factors <- M2f_new
  ctx <- save_result(ctx, "Model1Factors", M1f_new, "Model1Factors.RData")
  ctx <- save_result(ctx, "Model2Factors", M2f_new, "Model2Factors.RData")
  writeLines(M1f_new, file.path(ctx$output_dir, "Model1Factors.txt"))
  writeLines(M2f_new, file.path(ctx$output_dir, "Model2Factors.txt"))

  # 导出加权 VIF 表（发表阈值与 Model2 筛选一致：VIF < vif_strict）
  tb_disp <- tb_vif_w
  tb_disp <- tb_disp[is.finite(tb_disp$VIF) & tb_disp$VIF < vif_strict, , drop = FALSE]
  cli::cli_alert_info(
    "NHANES 加权 VIF 发表表：仅保留 VIF < {vif_strict}（与 Model2Factors 筛选一致）"
  )
  anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
  if (length(anthro_drop)) {
    tb_disp <- tb_disp[!tb_disp$Variable %in% anthro_drop, , drop = FALSE]
  }
  tb_disp$Variable <- gsub("_", " ", tb_disp$Variable, fixed = TRUE)
  title_vif_w <- paste0("Table S. Weighted Multicollinearity Diagnostics (VIF, NHANES) for ",
                         cfg$project$disease %||% "outcome")
  fp_vif_w <- file.path(ctx$output_dir_tables,
                         "Table S. Weighted Multicollinearity VIF (NHANES).xlsx")
  tryCatch(
    export_sci_table(tb_disp, fp_vif_w, title = title_vif_w),
    error = function(e) cli::cli_alert_warning("NHANES 加权 VIF 表导出失败: {e$message}")
  )

  ctx$results$nhanes_vif_df_weighted <- tb_vif_w
  ctx$results$univar_features <- M2f_new
  cli::cli_alert_success(
    "block_mc(NHANES 加权 VIF) 完成。Model2Factors({length(M2f_new)}): {paste(M2f_new, collapse=', ')}"
  )
  ctx
}

.block_mc_orig <- block_multicollinearity
block_multicollinearity <- function(ctx, ...) {
  ctx <- .block_mc_orig(ctx, ...)
  if (.is_nhanes_db(ctx$config)) {
    cli::cli_h2("block_multicollinearity(NHANES): 额外运行加权 VIF（C05 风格，lm(weights=)）")
    ctx <- .block_mc_nhanes_weighted(ctx)
  }
  ctx
}

block_multicollinearity_screen <- function(ctx, ...) {
  .mcol_run_vif_phase(ctx, "screen")
}

block_multicollinearity_final <- function(ctx, ...) {
  ctx <- .mcol_run_vif_phase(ctx, "final")
  if (.is_nhanes_db(ctx$config)) {
    cli::cli_h2("block_multicollinearity_final(NHANES): 额外运行加权 VIF")
    ctx <- .block_mc_nhanes_weighted(ctx)
  }
  ctx
}

register_block("multicollinearity_screen", block_multicollinearity_screen,
               "VIF screen (p<0.1): iterative VIF<4; seeds Model2Factors for feature selection")
register_block("multicollinearity_final", block_multicollinearity_final,
               "VIF final (p<0.05): strict VIF<4; Model1/Model2; full VIF table export")
register_block("multicollinearity", block_multicollinearity,
               "Legacy VIF among Model2Factors; NHANES weighted VIF appended")
