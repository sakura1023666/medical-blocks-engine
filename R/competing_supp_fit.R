###############################################################################
#  competing_supp_fit.R — 补充表专用 Model1–3 重拟合（全项目可复用）
#  Model1: 仅暴露；Model2: 暴露+人口学；Model3: 暴露+人口学+临床基线
#  骨架对齐案例完整协变量行；主文 selected 变量若存在则并入 Model2/3
###############################################################################

.competing_supp_display_label <- function(x) {
  x <- as.character(x)
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  # 保留 ASCII >= / <=，避免 Excel/部分环境对 ≥ ≤ 显示异常
  # GenderMale / RaceWhite 等系数名
  x <- sub("^Gender\\s*\\(?Male\\)?$", "Gender(Male)", x, ignore.case = TRUE)
  x <- sub("^Gender\\s*\\(?Female\\)?$", "Gender(Female)", x, ignore.case = TRUE)
  x <- sub("^Gender Male$", "Gender(Male)", x, ignore.case = TRUE)
  x <- sub("^Gender Female$", "Gender(Female)", x, ignore.case = TRUE)
  x <- sub("^Race (.+)$", "Race(\\1)", x)
  x <- sub(" Yes$", "(Yes)", x)
  x <- sub(" No$", "(No)", x)
  # 若历史结果已写成 Unicode，导表时统一回 ASCII
  x <- gsub("\u2265", ">=", x, fixed = TRUE)
  x <- gsub("\u2264", "<=", x, fixed = TRUE)
  trimws(x)
}

.competing_supp_horizon_labels <- function(horizons) {
  # 短窗（≤28 天）与主图一致用「N-day」；仅长随访末档才用 Overall
  horizons <- as.integer(horizons)
  labs <- paste0(horizons, "-day")
  last_h <- if (length(horizons)) horizons[length(horizons)] else NA_integer_
  if (is.finite(last_h) && last_h > 28L) {
    labs[length(labs)] <- "Overall follow-up duration"
  }
  labs
}

#' 补充表协变量池：与主文 Model1-3 协变量保持一致
.competing_supp_cov_pools <- function(data, bl = list(), ctx = NULL) {
  cm <- if (!is.null(ctx)) ctx$results$competing_model_covs else NULL
  if (!is.list(cm)) {
    stop("SUPP_COVARIATE_SYNC_FAIL: 缺少主文 competing_model_covs，补充表无法与正文协变量保持一致。", call. = FALSE)
  }
  m2 <- intersect(as.character(cm$m2 %||% character(0)), names(data))
  m3 <- intersect(as.character(cm$m3 %||% character(0)), names(data))
  if (!length(m2) || !length(m3) || !all(m2 %in% m3)) {
    stop("SUPP_COVARIATE_SYNC_FAIL: 主文协变量集合无效（要求 m2 非空且 m2 ⊂ m3）。", call. = FALSE)
  }
  list(
    demo = m2,
    clinical = setdiff(m3, m2),
    all = unique(c(m2, m3)),
    m1 = character(0),
    m2 = m2,
    m3 = m3,
    source = "main_models_synced"
  )
}

#' 早期发病剔除的时间窗（天）：年尺度→365；短随访默认 2 天
#' （不用首个 horizon，否则剔除窗=7 时 7-day 列会无主事件）
.competing_supp_early_lag_days <- function(data, time_var, bl = list()) {
  cfg_lag <- suppressWarnings(as.numeric(bl$supp_exclude_early_days %||% NA_real_)[1L])
  if (is.finite(cfg_lag) && cfg_lag >= 0) return(as.integer(cfg_lag))
  tmax <- suppressWarnings(max(as.numeric(data[[time_var]]), na.rm = TRUE))
  if (is.finite(tmax) && tmax >= 365) return(365L)
  as.integer(bl$supp_exclude_early_days_default %||% 2L)[1L]
}

#' 剔除“早期主事件”个体（年尺度=随访第1年发病；短随访=前 lag 天内发病）
.competing_supp_exclude_early_primary <- function(data, time_var, event_col, primary, lag_days) {
  if (!is.data.frame(data) || !nrow(data)) {
    return(list(data = data, n_excluded = 0L, lag_days = as.integer(lag_days)[1L]))
  }
  lag_days <- as.integer(lag_days)[1L]
  tt <- suppressWarnings(as.numeric(data[[time_var]]))
  ee <- suppressWarnings(as.integer(data[[event_col]]))
  early <- !is.na(ee) & !is.na(tt) & ee == as.integer(primary)[1L] & tt <= lag_days
  list(
    data = data[!early, , drop = FALSE],
    n_excluded = as.integer(sum(early, na.rm = TRUE)),
    lag_days = lag_days
  )
}

.competing_supp_fit_one <- function(d_h, time_var, event_col, cause, exp_var, covs,
                                    method = c("competing", "standard"),
                                    model_id = 1L, model_label = "Model 1", horizon = 28L) {
  method <- match.arg(method)
  if (!exists(".competing_fit_one_cox", mode = "function")) {
    return(NULL)
  }
  .competing_fit_one_cox(
    d_h, time_var, event_col, cause, exp_var, covs,
    method = method, model_id = model_id, model_label = model_label, horizon = horizon
  )
}

#' 为补充表拟合 Model1–3 × horizons × method（展示用阶梯，非主文 FS 阶梯）
.competing_supp_fit_models <- function(data, time_var, event_col, exp_var, cause,
                                       horizons = c(7L, 14L, 28L),
                                       cov_pools = NULL,
                                       methods = c("standard", "competing"),
                                       bl = list(), ctx = NULL) {
  if (is.null(data) || !exp_var %in% names(data)) {
    return(data.frame(note = "missing exposure", stringsAsFactors = FALSE))
  }
  if (!requireNamespace("survival", quietly = TRUE)) {
    return(data.frame(note = "no survival", stringsAsFactors = FALSE))
  }
  # 确保 .competing_fit_one_cox 可用
  if (!exists(".competing_fit_one_cox", mode = "function") && !is.null(ctx)) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/55_competing_risk_full/09block_competing_models_123.R"), local = FALSE)
  }
  if (is.null(cov_pools)) cov_pools <- .competing_supp_cov_pools(data, bl, ctx)

  data <- data[!is.na(data[[exp_var]]), , drop = FALSE]
  if (is.factor(data[[exp_var]]) || is.character(data[[exp_var]])) {
    data[[exp_var]] <- factor(trimws(as.character(data[[exp_var]])))
  }

  specs <- list()
  if ("competing" %in% methods) {
    specs <- c(specs, list(
      list(method = "competing", id = 1L, lab = "Model 1", covs = cov_pools$m1),
      list(method = "competing", id = 2L, lab = "Model 2", covs = cov_pools$m2),
      list(method = "competing", id = 3L, lab = "Model 3", covs = cov_pools$m3)
    ))
  }
  if ("standard" %in% methods) {
    specs <- c(specs, list(
      list(method = "standard", id = 1L, lab = "Model 1", covs = cov_pools$m1),
      list(method = "standard", id = 2L, lab = "Model 2", covs = cov_pools$m2),
      list(method = "standard", id = 3L, lab = "Model 3", covs = cov_pools$m3)
    ))
  }

  rows <- list()
  for (h in as.integer(horizons)) {
    d_h <- if (exists(".competing_horizon_data", mode = "function")) {
      .competing_horizon_data(data, time_var, event_col, h)
    } else {
      data
    }
    for (sp in specs) {
      rows[[length(rows) + 1L]] <- .competing_supp_fit_one(
        d_h, time_var, event_col, cause, exp_var, sp$covs,
        method = sp$method, model_id = sp$id, model_label = sp$lab, horizon = h
      )
    }
  }
  tab <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(tab) || !nrow(tab)) {
    return(data.frame(note = "supp models failed", stringsAsFactors = FALSE))
  }
  attr(tab, "cov_pools") <- cov_pools
  tab
}

#' 解析补充表未裁极端值数据：优先 trim 缓存，否则从 analysis_exclusion checkpoint 重建
.competing_supp_resolve_untrimmed <- function(ctx, data_trimmed, index_var) {
  .merge_traj <- function(pre, trimmed) {
    if (!is.data.frame(pre) || !is.data.frame(trimmed)) return(pre)
    bl <- ctx$config$competing_risk %||% list()
    exp_t <- as.character(bl$trajectory_var %||% paste0(index_var, "_trajectory"))[1L]
    id_col <- as.character((ctx$config$data %||% list())$id_column %||% "ID")[1L]
    if (exp_t %in% names(trimmed) && !exp_t %in% names(pre) &&
        id_col %in% names(pre) && id_col %in% names(trimmed)) {
      pre[[exp_t]] <- trimmed[[exp_t]][match(pre[[id_col]], trimmed[[id_col]])]
    }
    pre
  }

  pre <- ctx$results$trim_index_extreme$before_percentile_imputed
  if (is.data.frame(pre) && nrow(pre) > 0L && index_var %in% names(pre)) {
    return(.merge_traj(pre, data_trimmed))
  }

  out_dir <- ctx$root_output_dir %||% ctx$config$project$output_dir %||% NULL
  if (!is.null(out_dir) && nzchar(out_dir)) {
    ck <- file.path(out_dir, "checkpoints", "analysis_exclusion.rds")
    if (file.exists(ck)) {
      obj <- tryCatch(readRDS(ck), error = function(e) NULL)
      pre2 <- obj$ctx$data$imputed
      if (is.data.frame(pre2) && index_var %in% names(pre2)) {
        vals <- suppressWarnings(as.numeric(pre2[[index_var]]))
        pre2 <- pre2[is.finite(vals), , drop = FALSE]
        pre2 <- .merge_traj(pre2, data_trimmed)
        ctx$results$trim_index_extreme <- ctx$results$trim_index_extreme %||% list()
        ctx$results$trim_index_extreme$before_percentile_imputed <- pre2
        ctx$results$trim_index_extreme$index_var <- index_var
        cli::cli_alert_info("补充表：从 analysis_exclusion 重建未裁极端值队列 n={nrow(pre2)}")
        return(pre2)
      }
    }
  }
  data_trimmed
}

#' 取第 k 个插补完整集，对齐到分析队列 ID；暴露/结局沿用分析集，协变量用该次插补值
.competing_supp_mi_aligned <- function(ctx, data_template, k, bl = list()) {
  keep_vars <- unique(c(
    as.character(bl$time_var %||% "competing_time_28d"),
    as.character(bl$event_type_col %||% "competing_status_28d"),
    as.character(bl$index_var %||% character(0)),
    as.character(bl$exposure_var %||% character(0)),
    as.character(bl$trajectory_var %||% character(0)),
    as.character((ctx$config$data %||% list())$id_column %||% "ID")
  ))
  if (exists("mi_complete_aligned", mode = "function")) {
    return(mi_complete_aligned(ctx, data_template, k, keep_vars = keep_vars))
  }
  mm <- ctx$results$mice_model
  if (is.null(mm) || !inherits(mm, "mids")) return(NULL)
  k <- as.integer(k)[1L]
  if (!is.finite(k) || k < 1L || k > as.integer(mm$m %||% 0L)) return(NULL)
  if (!requireNamespace("mice", quietly = TRUE)) return(NULL)

  dk <- tryCatch(mice::complete(mm, action = k), error = function(e) NULL)
  if (!is.data.frame(dk) || !nrow(dk)) return(NULL)

  id_col <- as.character((ctx$config$data %||% list())$id_column %||% "ID")[1L]
  row_ids <- as.character(ctx$results$mice_row_ids %||% character(0))
  if (length(row_ids) == nrow(dk)) {
    dk[[id_col]] <- row_ids
  } else if (!id_col %in% names(dk)) {
    pre <- ctx$results$data_before_mi
    if (is.data.frame(pre) && id_col %in% names(pre) && nrow(pre) == nrow(dk)) {
      dk[[id_col]] <- as.character(pre[[id_col]])
    } else if (is.data.frame(mm$data) && id_col %in% names(mm$data) && nrow(mm$data) == nrow(dk)) {
      dk[[id_col]] <- as.character(mm$data[[id_col]])
    }
  }
  if (!id_col %in% names(data_template) || !id_col %in% names(dk)) return(NULL)

  ids <- as.character(data_template[[id_col]])
  idx <- match(ids, as.character(dk[[id_col]]))
  ok <- !is.na(idx)
  if (!any(ok)) return(NULL)
  out <- dk[idx[ok], , drop = FALSE]
  tpl <- data_template[ok, , drop = FALSE]

  for (v in keep_vars) {
    if (v %in% names(tpl)) out[[v]] <- tpl[[v]]
  }
  rownames(out) <- NULL
  out
}

#' 拟合 MI dataset 1/2 的 Competing Model1–3（案例 Missing values imputed dataset k）
.competing_supp_fit_mi_sections <- function(ctx, data_h, time_var, event_col, exp_var, cause,
                                            horizons, cov_pools, skeleton, bl,
                                            n_mi = 2L, method = "competing") {
  sections <- list()
  for (k in seq_len(as.integer(n_mi)[1L])) {
    dk <- .competing_supp_mi_aligned(ctx, data_h, k, bl = bl)
    title <- sprintf("Missing values imputed dataset %d", k)
    if (is.null(dk)) {
      cli::cli_alert_warning("补充表：无法构建 {title}，跳过")
      next
    }
    tab_k <- .competing_supp_fit_models(
      dk, time_var, event_col, exp_var, cause, horizons = horizons,
      cov_pools = cov_pools, methods = method, bl = bl, ctx = ctx
    )
    sections[[length(sections) + 1L]] <- list(
      tab = tab_k, method = method,
      skeleton_vars = skeleton,
      section_title = title,
      extra_note = NULL
    )
  }
  sections
}

#' 补充表4：对 Model3 协变量（含暴露）做 VIF 共线性诊断
.competing_supp_vif_table <- function(data, vars, bl = list(), ctx = NULL,
                                      include_exposure = TRUE) {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars) & vars %in% names(data)]
  if (isTRUE(include_exposure)) {
    exp_q <- as.character(bl$exposure_var %||% character(0))[1L]
    if (nzchar(exp_q %||% "") && exp_q %in% names(data)) {
      vars <- unique(c(exp_q, vars))
    }
  }
  thr_strict <- suppressWarnings(as.numeric(
    (ctx$config$multicollinearity %||% list())$vif_threshold_strict %||%
      bl$vif_threshold_strict %||% 4
  )[1L])
  if (!is.finite(thr_strict) || thr_strict <= 0) thr_strict <- 4
  thr_loose <- suppressWarnings(as.numeric(
    (ctx$config$multicollinearity %||% list())$vif_threshold_loose %||%
      bl$vif_threshold_loose %||% 10
  )[1L])
  if (!is.finite(thr_loose) || thr_loose <= 0) thr_loose <- 10

  if (length(vars) <= 1L) {
    return(data.frame(
      Variable = character(0), VIF = numeric(0), Judgment = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # 优先复用项目内 VIF 计算器
  res <- if (exists(".mcol_calculate_vif_from_vars", mode = "function")) {
    .mcol_calculate_vif_from_vars(vars, data)
  } else {
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
      list(vif_df = NULL, vif_values = NULL)
    } else {
      vif_values <- tryCatch({
        r2s <- vapply(seq_len(ncol(X)), function(j) {
          if (ncol(X) == 1L) return(0)
          summary(stats::lm(X[, j] ~ X[, -j, drop = FALSE]))$r.squared
        }, numeric(1))
        stats::setNames(1 / (1 - r2s), colnames(X))
      }, error = function(e) NULL)
      list(
        vif_df = if (is.null(vif_values)) NULL else data.frame(
          Variable = names(vif_values),
          VIF = as.numeric(vif_values),
          stringsAsFactors = FALSE
        ),
        vif_values = vif_values
      )
    }
  }

  if (is.null(res$vif_df) || !nrow(res$vif_df)) {
    return(data.frame(
      Variable = character(0), VIF = numeric(0), Judgment = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # 按原始变量聚合（取 dummy 中最大 VIF）
  base_of <- function(term) {
    hit <- vars[vapply(vars, function(v) identical(term, v) || startsWith(term, v), logical(1))]
    if (!length(hit)) return(term)
    hit[which.max(nchar(hit))]
  }
  bases <- vapply(as.character(res$vif_df$Variable), base_of, character(1))
  agg <- tapply(as.numeric(res$vif_df$VIF), bases, function(z) max(z, na.rm = TRUE))
  out <- data.frame(
    Variable = names(agg),
    VIF = as.numeric(agg),
    stringsAsFactors = FALSE
  )
  # 保持输入变量顺序
  out <- out[order(match(out$Variable, vars, nomatch = 9999L)), , drop = FALSE]
  rownames(out) <- NULL
  out$Judgment <- ifelse(
    !is.finite(out$VIF), "NE",
    ifelse(out$VIF < thr_strict, sprintf("Pass (VIF<%g)", thr_strict),
           ifelse(out$VIF < thr_loose, sprintf("Borderline (VIF<%g)", thr_loose),
                  sprintf("Fail (VIF\u2265%g)", thr_loose)))
  )
  out$Variable <- .competing_supp_display_label(out$Variable)
  attr(out, "vif_threshold_strict") <- thr_strict
  attr(out, "vif_threshold_loose") <- thr_loose
  attr(out, "vif_vars") <- vars
  out
}

