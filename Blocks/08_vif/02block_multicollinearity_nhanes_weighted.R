###############################################################################
#  multicollinearity_nhanes_* — NHANES 加权 VIF（lm(weights=) + design$variables）。
#
#  register_block:
#    multicollinearity_nhanes_screen — 单因素 p<0.1 候选 tb_screen → vif_screen_pass
#    multicollinearity_nhanes_final  — 多因素 tb2 → Model1/Model2 + 加权 VIF 表
#
#  前置: obj（nhanes_design）；screen 需 univariate_nhanes；final 需 multivariate_nhanes
#  配置: config$multicollinearity（阈值/anthropometric/exclude）；Model1 用 multivariate_nhanes$demo_keywords
#  不修改 univariate_nhanes / multivariate_nhanes 块内回归逻辑。
###############################################################################

.mcnw_effective_vif_thresholds <- function(cfg) {
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
  list(strict = strict, loose = loose, min_vars = min_v)
}

.mcnw_calculate_vif_from_vars <- function(vars, data) {
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

.mcnw_max_vif_for_original_var <- function(vif_values, orig_name) {
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

.mcnw_index_var <- function(cfg) {
  as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "BMI"
  )[1L]
}

.mcnw_protected_vif_vars <- function(cfg) {
  mc <- cfg$multicollinearity %||% list()
  ar <- mc$anthropometric_vif_resolution %||% list()
  unique(c(
    as.character(ar$protect_vars %||% character(0)),
    .mcnw_index_var(cfg)
  ))
}

.mcnw_resolve_anthropometric_vif_vars <- function(vars, data, cfg) {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[vars %in% names(data)]
  mc <- cfg$multicollinearity %||% list()
  ar <- mc$anthropometric_vif_resolution %||% list()
  if (!isTRUE(ar$enable %||% TRUE)) {
    return(list(kept = vars, dropped = character(0), strategy = "disabled"))
  }
  anthro_cfg <- unique(as.character(ar$vars %||% c("BMI", "Weight", "Height")))
  protected <- intersect(.mcnw_protected_vif_vars(cfg), vars)
  index_var <- .mcnw_index_var(cfg)
  try_one <- unique(as.character(ar$prefer_drop_one_order %||% c("Weight", "Height")))
  thr <- .mcnw_effective_vif_thresholds(cfg)$strict
  anthro <- intersect(anthro_cfg, vars)
  if ("BMI" %in% anthro) {
    drop_hw <- intersect(c("Weight", "Height"), anthro)
    if (length(drop_hw)) {
      return(list(
        kept = setdiff(vars, drop_hw),
        dropped = drop_hw,
        strategy = "bmi_present_drop_weight_height"
      ))
    }
  }
  if (length(anthro) < 2L) {
    return(list(kept = vars, dropped = character(0), strategy = "single_or_none"))
  }

  # 暴露指标（如 BMI）与身高/体重并存时，优先剔除身高体重以保留 BMI
  if (index_var %in% anthro) {
    drop_wh <- intersect(c("Weight", "Height"), anthro)
    if (length(drop_wh)) {
      return(list(
        kept = setdiff(vars, drop_wh),
        dropped = drop_wh,
        strategy = "drop_weight_height_keep_index"
      ))
    }
  }

  .acceptable <- function(vs) {
    res <- .mcnw_calculate_vif_from_vars(vs, data)
    mx <- vapply(anthro, function(a) {
      .mcnw_max_vif_for_original_var(res$vif_values, a)
    }, numeric(1))
    all(is.finite(mx) & mx < thr)
  }
  if (.acceptable(vars)) {
    return(list(kept = vars, dropped = character(0), strategy = "vif_ok"))
  }
  for (d1 in try_one) {
    if (!d1 %in% anthro || d1 %in% protected) next
    trial <- setdiff(vars, d1)
    if (.acceptable(trial)) {
      return(list(kept = trial, dropped = d1, strategy = paste0("drop_one:", d1)))
    }
  }
  drop_wh <- setdiff(intersect(c("Weight", "Height"), anthro), protected)
  trial2 <- setdiff(vars, drop_wh)
  if (length(drop_wh) >= 1L && .acceptable(trial2)) {
    return(list(
      kept = trial2,
      dropped = drop_wh,
      strategy = if (length(drop_wh) >= 2L) "drop_weight_and_height" else paste0("drop_one:", drop_wh[1L])
    ))
  }
  # 受保护变量（如 BMI）永不剔除；仅剔除非保护的人体测量变量
  to_drop <- setdiff(anthro, protected)
  if (length(to_drop)) {
    return(list(
      kept = setdiff(vars, to_drop),
      dropped = to_drop,
      strategy = "drop_non_protected_anthro"
    ))
  }
  list(kept = vars, dropped = character(0), strategy = "unresolved")
}

.mcnw_build_orig_var_vif_table <- function(vars, data) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (!length(vars)) return(NULL)
  if (length(vars) == 1L) {
    return(data.frame(Variable = vars, VIF = NA_real_, stringsAsFactors = FALSE))
  }
  res <- .mcnw_calculate_vif_from_vars(vars, data)
  if (is.null(res$vif_values)) {
    return(data.frame(Variable = vars, VIF = NA_real_, stringsAsFactors = FALSE))
  }
  vifs <- vapply(vars, function(v) {
    .mcnw_max_vif_for_original_var(res$vif_values, v)
  }, numeric(1))
  data.frame(Variable = vars, VIF = round(vifs, 3), stringsAsFactors = FALSE)
}

.mcnw_weighted_vif_values <- function(vars, df, wt_col) {
  for (nm in intersect(vars, names(df)[sapply(df, is.factor)])) {
    df[[nm]] <- as.numeric(as.factor(df[[nm]]))
  }
  for (nm in vars) {
    if (any(is.na(df[[nm]]))) {
      df[[nm]][is.na(df[[nm]])] <- stats::median(df[[nm]], na.rm = TRUE)
    }
  }
  X <- tryCatch({
    mm <- stats::model.matrix(stats::as.formula(paste0("~ ", paste(vars, collapse = "+"))), data = df)
    mm[, -1L, drop = FALSE]
  }, error = function(e) NULL)
  if (is.null(X) || ncol(X) < 1L) return(NULL)
  w <- df[[wt_col]]
  r2s <- vapply(seq_len(ncol(X)), function(j) {
    if (ncol(X) == 1L) return(0)
    fit <- tryCatch(stats::lm(X[, j] ~ X[, -j, drop = FALSE], weights = w), error = function(e) NULL)
    if (is.null(fit)) return(0)
    summary(fit)$r.squared
  }, numeric(1))
  vif_v <- 1 / (1 - r2s)
  stats::setNames(vif_v, colnames(X))
}

.mcnw_map_dummies_to_orig <- function(vif_ok_names, orig_vars) {
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

.mcnw_filter_by_weighted_vif <- function(orig_vars, vif_vals, threshold) {
  if (is.null(vif_vals) || !length(vif_vals)) return(orig_vars)
  ok_names <- names(vif_vals)[is.finite(vif_vals) & vif_vals < threshold]
  out <- .mcnw_map_dummies_to_orig(ok_names, orig_vars)
  if (!length(out) && length(orig_vars)) {
    mx <- vapply(orig_vars, function(v) .mcnw_max_vif_for_original_var(vif_vals, v), numeric(1))
    out <- orig_vars[is.finite(mx) & mx < threshold]
  }
  unique(out)
}

.mcnw_compute_pass <- function(vars, data, cfg, vif_threshold, wt_col, weighted = TRUE) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (!length(vars)) return(character(0))
  if (length(vars) == 1L) return(vars)

  mc <- cfg$multicollinearity %||% list()
  ar_cfg <- mc$anthropometric_vif_resolution %||% list()
  anthro_cfg <- unique(as.character(ar_cfg$vars %||% c("BMI", "Weight", "Height")))
  protected <- .mcnw_protected_vif_vars(cfg)
  hard_thr <- as.numeric(mc$vif_threshold_hard_drop %||% Inf)[1L]
  working <- vars
  if (length(intersect(anthro_cfg, vars)) >= 2L && isTRUE(ar_cfg$enable %||% TRUE)) {
    ar <- .mcnw_resolve_anthropometric_vif_vars(vars, data, cfg)
    working <- ar$kept
    if (length(ar$dropped)) {
      cli::cli_alert_info(
        "NHANES VIF 人体测量协调 [{ar$strategy}]，剔除: {paste(ar$dropped, collapse = ', ')}"
      )
    }
  }

  .compute_vals <- function(vars) {
    if (length(vars) < 2L) return(NULL)
    v <- NULL
    if (weighted && wt_col %in% names(data)) {
      v <- tryCatch(
        .mcnw_weighted_vif_values(vars, data, wt_col),
        error = function(e) {
          cli::cli_alert_warning("加权 VIF 计算失败，回退非加权: {e$message}")
          NULL
        }
      )
    }
    if (is.null(v)) v <- .mcnw_calculate_vif_from_vars(vars, data)$vif_values
    v
  }

  # 迭代逐一剔除 VIF 最高且 >= 阈值 的非保护变量，每轮重算 VIF，直到全部 < 阈值
  repeat {
    if (length(working) < 2L) break
    vif_vals <- .compute_vals(working)
    if (is.null(vif_vals) || !length(vif_vals)) break
    cand <- setdiff(working, protected)
    if (!length(cand)) break
    mxs <- vapply(cand, function(v) .mcnw_max_vif_for_original_var(vif_vals, v), numeric(1))
    mxs[!is.finite(mxs)] <- -Inf
    worst_i <- which.max(mxs)
    worst_vif <- mxs[worst_i]
    if (!is.finite(worst_vif) || worst_vif < vif_threshold) break
    worst_v <- cand[worst_i]
    working <- setdiff(working, worst_v)
    cli::cli_alert_info(
      "NHANES 加权 VIF 迭代剔除 {worst_v}（VIF={round(worst_vif, 3)} >= {vif_threshold}）"
    )
  }
  unique(working)
}

.mcnw_export_vif_tables <- function(ctx, cfg, phase_label, vif_tbl, selected, csv_name, table_caption,
                                    vif_tbl_pub = NULL) {
  thr <- .mcnw_effective_vif_thresholds(cfg)$strict
  mc_cfg <- cfg$multicollinearity %||% list()
  env_label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg)
  } else NULL
  .mcnw_disp <- function(v) {
    if (exists("environment_display_label", mode = "function")) {
      environment_display_label(as.character(v), env_label_map)
    } else {
      gsub("_", " ", as.character(v), fixed = TRUE)
    }
  }
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
  if (length(selected)) {
    vif_export <- vif_export[vif_export$Variable %in% selected, , drop = FALSE]
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
  # 注意：不再无条件回填 VOC 行。VIF >= 阈值 的 VOC 已被迭代剔除，
  # 若回填会让 Table S4 重新出现 VIF>4 的环境变量（用户明确要求逐一删除）。
  # 仅保留通过 VIF 筛选（已在 selected 内、VIF < 阈值）的 VOC 行。
  if (!nrow(vif_export)) {
    cli::cli_alert_warning("NHANES VIF {phase_label} 发表表：无 VIF < {thr} 的行，跳过导出")
    return(invisible(FALSE))
  }

  vif_export$Variable_display <- .mcnw_disp(vif_export$Variable)
  write.csv(
    vif_export[, c("Variable_display", "VIF"), drop = FALSE],
    file.path(ctx$output_dir, csv_name), row.names = FALSE
  )
  cli::cli_alert_success("Saved: {csv_name}（仅 VIF < {thr}；暴露指标始终保留）")
  tbl_pub <- vif_export[, c("Variable", "VIF"), drop = FALSE]
  tbl_pub$Variable <- .mcnw_disp(tbl_pub$Variable)
  tbl_pub$VIF <- format_vif_pub_column(tbl_pub$VIF)
  cap_vif <- table_caption %||% paste0("Weighted Multicollinearity Analysis (VIF, NHANES) — ", phase_label)
  cap_vif <- sub("^Table S\\d+[a-z]?\\.\\s*", "", cap_vif)
  paths_vif <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_vif, "xlsx")
  tryCatch(
    export_sci_table(
      tbl_pub, paths_vif$filepath, title = paths_vif$title,
      blank_na_cells = FALSE, excel_use_prepared = FALSE
    ),
    error = function(e) cli::cli_alert_warning("NHANES 加权 VIF Excel 导出失败: {e$message}")
  )
  invisible(TRUE)
}

.mcnw_run_phase <- function(ctx, phase) {
  phase <- tolower(as.character(phase)[1L])
  if (!.is_nhanes_db(ctx$config)) {
    stop("multicollinearity_nhanes_* 仅用于 NHANES/NHANce 数据库。", call. = FALSE)
  }
  cfg <- ctx$config
  mc_cfg <- cfg$multicollinearity %||% list()
  nhanes_cfg <- cfg$nhanes %||% list()
  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    stop("multicollinearity_nhanes_*: ctx$results$nhanes_design 为空，请先 run_block(obj)。", call. = FALSE)
  }

  wt_col <- as.character(nhanes_cfg$survey_weight %||% "WTMEC2YR")[1L]
  data <- as.data.frame(design$variables, stringsAsFactors = FALSE)
  if (!wt_col %in% names(data)) {
    stop("multicollinearity_nhanes_*: 权重列 '", wt_col, "' 不在 design$variables 中。", call. = FALSE)
  }

  vth <- .mcnw_effective_vif_thresholds(cfg)
  vif_threshold <- vth$strict
  hard_drop <- as.numeric(mc_cfg$vif_threshold_hard_drop %||% Inf)[1L]
  phase_cfg <- mc_cfg[[phase]] %||% list()
  id_col <- cfg$data$id_column %||% character(0)
  mc_excl <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(mc_cfg$weighted_vif_drop_vars %||% character(0)),
    as.character(id_col %||% character(0)),
    as.character(nhanes_cfg$exclude_cols %||% character(0))
  ))
  if (exists("pipeline_survey_weight_metadata_cols", mode = "function")) {
    mc_excl <- unique(c(mc_excl, pipeline_survey_weight_metadata_cols()))
  }
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    mc_excl <- setdiff(mc_excl, pipeline_index_exposure_var(cfg))
  }

  if (identical(phase, "screen")) {
    screen_input <- as.character((mc_cfg$screen %||% list())$input_from %||% "tb_screen")[1L]
    input_vars <- if (identical(screen_input, "tb1")) {
      as.character(ctx$results$tb1 %||% character(0))
    } else {
      as.character(ctx$results$tb_screen %||% character(0))
    }
    if (!length(input_vars) && exists("environment_inject_covariate_fallback", mode = "function")) {
      ctx <- environment_inject_covariate_fallback(ctx)
      input_vars <- if (identical(screen_input, "tb1")) {
        as.character(ctx$results$tb1 %||% character(0))
      } else {
        as.character(ctx$results$tb_screen %||% character(0))
      }
    }
    if (!length(input_vars)) {
      stop("multicollinearity_nhanes_screen: ", screen_input, " 为空，请先运行 univariate_nhanes。", call. = FALSE)
    }
    cli::cli_h2("NHANES 加权 VIF screening（{screen_input} p<0.05，{length(input_vars)} 个变量）")
  } else if (identical(phase, "final")) {
    input_vars <- as.character(ctx$results$tb2 %||% ctx$results$multivar_features %||% character(0))
    if (!length(input_vars)) {
      if (isTRUE((mc_cfg$allow_empty_tb2_final %||% FALSE))) {
        input_vars <- as.character(
          ctx$results$Model2Factors %||% ctx$results$tb_screen %||% character(0)
        )
        if (length(input_vars)) {
          cli::cli_alert_warning(
            "multicollinearity_nhanes_final: tb2 为空，回退使用 Model2Factors/tb_screen（{length(input_vars)} 个）"
          )
        }
      }
      if (!length(input_vars)) {
        stop("multicollinearity_nhanes_final: tb2 为空，请先运行 multivariate_nhanes。", call. = FALSE)
      }
    }
    cli::cli_h2("NHANES 加权 VIF final（tb2，{length(input_vars)} 个变量）")
  } else {
    stop("Unknown NHANES VIF phase: ", phase, call. = FALSE)
  }

  input_vars <- unique(input_vars[nzchar(input_vars)])
  input_vars <- intersect(input_vars, names(data))
  if (identical(phase, "screen") &&
      isTRUE((cfg$environment_batch %||% list())$exclude_vocs_from_clinical_vif %||% FALSE)) {
    voc_excl <- character(0)
    if (exists("environment_clinical_voc_gate_columns", mode = "function")) {
      voc_excl <- environment_clinical_voc_gate_columns(data, cfg)
    } else if (exists("environment_voc_allowlist", mode = "function")) {
      voc_excl <- environment_voc_allowlist(data, cfg)
    } else {
      voc_excl <- as.character((cfg$environment %||% list())$voc_columns %||% character(0))
    }
    if (exists("environment_pattern_voc_columns", mode = "function")) {
      voc_excl <- unique(c(voc_excl, environment_pattern_voc_columns(data, cfg)))
    }
    excl_idx <- as.character((cfg$incidence %||% list())$index_exclude_vars %||% character(0))
    if (length(excl_idx)) voc_excl <- unique(c(voc_excl, excl_idx))
    voc_excl <- intersect(unique(voc_excl[nzchar(voc_excl)]), input_vars)
    if (length(voc_excl)) {
      cli::cli_alert_info(
        "临床 VIF screen 排除 {length(voc_excl)} 个环境 VOC（由 environment_voc_clinical_gate 单独逐步筛选）"
      )
      input_vars <- setdiff(input_vars, voc_excl)
    }
  }
  if (length(mc_excl)) {
    dropped_excl <- intersect(input_vars, mc_excl)
    if (length(dropped_excl)) {
      cli::cli_alert_info("exclude_vars 强制排除: {paste(dropped_excl, collapse = ', ')}")
    }
    input_vars <- setdiff(input_vars, mc_excl)
  }
  if (!length(input_vars)) {
    stop("multicollinearity_nhanes_", phase, ": 排除后无变量保留。", call. = FALSE)
  }

  cli::cli_alert_info("NHANES 加权 VIF 阈值: {vif_threshold}（硬剔除 > {hard_drop}；lm(weights={wt_col})）")
  vif_comp_exclude <- if (exists("pipeline_index_vif_exclude_vars", mode = "function")) {
    intersect(pipeline_index_vif_exclude_vars(cfg), input_vars)
  } else {
    character(0)
  }
  exposure <- if (exists("pipeline_index_exposure_var", mode = "function")) {
    pipeline_index_exposure_var(cfg)
  } else {
    character(0)
  }
  if (length(vif_comp_exclude)) {
    cli::cli_alert_info(
      "VIF 设计矩阵排除暴露组分: {paste(vif_comp_exclude, collapse = ', ')}"
    )
  }
  vif_tbl_vars <- setdiff(input_vars, vif_comp_exclude)
  if (isTRUE((cfg$environment_batch %||% list())$include_vocs_in_clinical_screen)) {
    # 只纳入通过单因素(P<0.05 且 OR>1)的环境毒物，而非全部 VOC
    voc_vif <- as.character(ctx$results$voc_univariate_pass %||% character(0))
    if (!length(voc_vif) && exists("environment_table1_voc_vars", mode = "function")) {
      voc_vif <- intersect(environment_table1_voc_vars(data, cfg), names(data))
    }
    voc_vif <- intersect(voc_vif, names(data))
    voc_vif <- setdiff(voc_vif, vif_comp_exclude)
    if (length(voc_vif)) {
      cli::cli_alert_info(
        "临床 VIF 表纳入单因素显著环境毒物 {length(voc_vif)} 个: {paste(voc_vif, collapse = ', ')}"
      )
    }
    vif_tbl_vars <- unique(c(vif_tbl_vars, voc_vif))
  }
  ar_pre <- .mcnw_resolve_anthropometric_vif_vars(vif_tbl_vars, data, cfg)
  vif_tbl_vars <- ar_pre$kept
  if (length(ar_pre$dropped)) {
    cli::cli_alert_info(
      "VIF 表基于人体测量协调后变量集 [{ar_pre$strategy}]，已剔除: {paste(ar_pre$dropped, collapse = ', ')}"
    )
  }
  vif_covariate_vars <- setdiff(vif_tbl_vars, exposure)
  vif_tbl <- .mcnw_build_orig_var_vif_table(vif_tbl_vars, data)
  if (is.null(vif_tbl)) stop("NHANES 加权 VIF 表构建失败。", call. = FALSE)
  if (nzchar(exposure) && exposure %in% names(data) &&
      exists(".mcol_append_exposure_vif_row", mode = "function")) {
    vif_tbl <- .mcol_append_exposure_vif_row(
      vif_tbl, exposure, data, .mcnw_build_orig_var_vif_table, ctx, cfg
    )
  }
  if (exists(".reorder_vif_table_like_univariate", mode = "function")) {
    vif_tbl <- .reorder_vif_table_like_univariate(vif_tbl, cfg, data, ctx)
  }

  selected <- .mcnw_compute_pass(vif_covariate_vars, data, cfg, vif_threshold, wt_col, weighted = TRUE)
  if (exists("order_vars_like_table1", mode = "function")) {
    selected <- order_vars_like_table1(selected, ctx, cfg, data)
  }
  if (!length(selected)) {
    ctx$results$pause_point <- list(
      block = paste0("multicollinearity_nhanes_", phase),
      reason = paste0("NHANES 加权 VIF ", phase, " 筛选后无变量保留"),
      suggestion = paste0("检查共线性或放宽 vif_threshold_strict (当前: ", vif_threshold, ")"),
      data_snapshot = utils::head(vif_tbl, 10)
    )
    stop("PAUSE_FOR_USER_DECISION: NHANES 加权 VIF 筛选后无变量。", call. = FALSE)
  }

  if (identical(phase, "screen")) {
    ctx$results$vif_screen_pass <- selected
    ctx <- save_result(ctx, "vif_screen_pass", selected, "VIF_screen_pass_weighted.RData")
    writeLines(selected, file.path(ctx$output_dir, "VIF_screen_pass_weighted.txt"))
    csv_name <- phase_cfg$csv_name %||% "VIF_check_screen_weighted.csv"
    table_caption <- phase_cfg$table_title %||%
      paste0("Weighted Multicollinearity Analysis (VIF, univariate screen, NHANES) for ",
             cfg$project$disease %||% "outcome")
    .mcnw_export_vif_tables(ctx, cfg, "screen", vif_tbl, selected, csv_name, table_caption)
    ctx$results$vif_screen_table_weighted <- vif_tbl
    ctx$results$vif_screen_pass_weighted <- selected
    cli::cli_alert_success(
      "multicollinearity_nhanes_screen 完成: {length(selected)} 个变量 VIF 通过 — {paste(selected, collapse = ', ')}"
    )
    if (isTRUE((cfg$environment_batch %||% list())$skip_clinical_multivariate %||% FALSE) &&
        exists("environment_finalize_clinical_covariates_without_multivariate", mode = "function")) {
      ctx <- environment_finalize_clinical_covariates_without_multivariate(ctx)
    }
    return(ctx)
  }

  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "BMI"
  )[1L]
  screen_pool <- as.character(
    ctx$results$vif_screen_pass %||% ctx$results$vif_screen_pass_weighted %||% character(0)
  )
  if (exists(".lnw00_split_vif_final_models", mode = "function")) {
    split <- .lnw00_split_vif_final_models(
      selected, cfg, data, index_var, bl_cfg = list(), screen_pool = screen_pool
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
    mv_cfg <- cfg$multivariate_nhanes %||% list()
    demo_keywords <- as.character(mv_cfg$demo_keywords %||% c("Age", "Gender", "Sex", "Race", "Ethnic"))
    demo_pattern <- paste(demo_keywords, collapse = "|")
    Model2Factors <- selected
    Model1Factors <- Model2Factors[grepl(demo_pattern, Model2Factors, ignore.case = TRUE)]
    Model1Factors <- intersect(Model1Factors, names(data))
  }
  if (exists("pipeline_strip_index_from_model_factors", mode = "function")) {
    stripped <- pipeline_strip_index_from_model_factors(Model1Factors, Model2Factors, cfg)
    Model1Factors <- stripped$M1
    Model2Factors <- stripped$M2
  }

  ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
  ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
  writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
  writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))

  csv_name <- phase_cfg$csv_name %||% "VIF_check_final_weighted.csv"
  table_caption <- phase_cfg$table_title %||%
    paste0("Weighted Multicollinearity Analysis (VIF, multivariate final, NHANES) for ",
           cfg$project$disease %||% "outcome")
  append_fn <- if (exists(".mcol_append_exposure_vif_row", mode = "function")) {
    .mcol_append_exposure_vif_row
  } else {
    function(vif_tbl, exposure, data, build_fn, ctx = NULL, cfg = NULL) vif_tbl
  }
  vif_tbl_pub <- append_fn(
    vif_tbl, exposure, data, .mcnw_build_orig_var_vif_table, ctx, cfg
  )
  .mcnw_export_vif_tables(
    ctx, cfg, "final", vif_tbl, selected, csv_name, table_caption,
    vif_tbl_pub = vif_tbl_pub
  )

  ctx$results$Model1Factors <- Model1Factors
  ctx$results$Model2Factors <- Model2Factors
  ctx$results$vif_final_pass <- unique(c(
    selected,
    exposure[nzchar(exposure) & exposure %in% names(data)]
  ))
  ctx$results$vif_final_table_weighted <- vif_tbl
  ctx$results$univar_features <- Model2Factors
  ctx$results$nhanes_logistic_M1 <- Model1Factors
  ctx$results$nhanes_logistic_M2 <- Model2Factors
  ctx$results$nhanes_vif_df_weighted <- vif_tbl

  removed <- setdiff(input_vars, selected)
  if (length(removed)) {
    cli::cli_alert_warning("final 加权 VIF 移除: {paste(removed, collapse = ', ')}")
  }
  cli::cli_alert_success(
    "multicollinearity_nhanes_final 完成: Model2={length(Model2Factors)}, Model1={length(Model1Factors)}"
  )
  ctx
}

block_multicollinearity_nhanes_screen <- function(ctx, ...) {
  .mcnw_run_phase(ctx, "screen")
}

block_multicollinearity_nhanes_final <- function(ctx, ...) {
  .mcnw_run_phase(ctx, "final")
}

register_block(
  "multicollinearity_nhanes_screen",
  block_multicollinearity_nhanes_screen,
  "NHANES 加权 VIF screen（tb_screen，lm(weights=)）"
)
register_block(
  "multicollinearity_nhanes_final",
  block_multicollinearity_nhanes_final,
  "NHANES 加权 VIF final（tb2 → Model1/Model2）"
)
