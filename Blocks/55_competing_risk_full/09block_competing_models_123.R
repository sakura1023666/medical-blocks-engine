###############################################################################
#  competing_models_123 — Competing(Fine-Gray) + Standard Cox × Model 1–6 × 7/14/28 天
#
#  Competing (Model 1–3): Fine-Gray 亚分布风险 (cmprsk::crr)
#  Standard  (Model 4–6): 标准 Cox（同协变量阶梯）
#  Model 1/4 无协变量；2/5 人口学；3/6 人口学+特征选择非人口学
###############################################################################

.competing_horizon_data <- function(data, time_var, event_col, horizon) {
  d <- data
  t0 <- suppressWarnings(as.numeric(d[[time_var]]))
  e0 <- suppressWarnings(as.integer(d[[event_col]]))
  t1 <- pmin(t0, horizon)
  e1 <- e0
  e1[is.na(t0) | t0 > horizon] <- 0L
  d[[time_var]] <- t1
  d[[event_col]] <- e1
  d
}

.competing_map_selected_to_base <- function(selected, data_names) {
  selected <- unique(as.character(selected %||% character(0)))
  selected <- selected[nzchar(selected)]
  if (!length(selected)) return(character(0))
  mapped <- unique(unlist(lapply(selected, function(s) {
    hit <- data_names[startsWith(s, data_names) | data_names == s]
    if (length(hit)) hit else s
  })))
  intersect(mapped, data_names)
}

.competing_univar_p_ordered <- function(ctx, data_names, exp_vars, screen_cut = 0.10) {
  uc <- ctx$results$univar_coef %||% NULL
  if (is.null(uc) || !is.data.frame(uc) || !all(c("Variable", "P") %in% names(uc))) {
    return(character(0))
  }
  p <- suppressWarnings(as.numeric(uc$P))
  nm <- as.character(uc$Variable)
  ok <- !is.na(p) & p < screen_cut & nzchar(nm)
  nm <- nm[ok]
  p <- p[ok]
  base <- .competing_map_selected_to_base(nm, data_names)
  # keep lowest P per base variable
  ord <- order(p, nm)
  nm <- nm[ord]
  p <- p[ord]
  base_map <- vapply(nm, function(s) {
    hit <- data_names[startsWith(s, data_names) | data_names == s]
    if (length(hit)) hit[[1L]] else s
  }, character(1))
  keep <- !duplicated(base_map) & base_map %in% base & !(base_map %in% exp_vars)
  unique(base_map[keep])
}

.competing_resolve_model_covs <- function(data, bl, ctx = NULL) {
  # 课题可强制固定 Model2/3（仅本课题 config 打开；其它课题不设则走原 RF→LASSO→UV 流程）
  force_m2 <- as.character(bl$force_model2 %||% character(0))
  force_m3 <- as.character(bl$force_model3 %||% character(0))
  force_m2 <- intersect(force_m2[nzchar(force_m2)], names(data))
  force_m3 <- intersect(force_m3[nzchar(force_m3)], names(data))
  if (length(force_m2) && length(force_m3)) {
    if ("Age" %in% names(data) && !("Age" %in% force_m2)) force_m2 <- unique(c("Age", force_m2))
    force_m3 <- unique(c(force_m2, force_m3))
    if (!length(setdiff(force_m3, force_m2))) {
      stop("force_model3 必须在 force_model2 之外至少多 1 个协变量", call. = FALSE)
    }
    return(list(
      m1 = character(0),
      m2 = force_m2,
      m3 = force_m3,
      demo_source = "force_model2",
      nondemo_source = "force_model3",
      footnote = sprintf(
        "Model 1/4: unadjusted; Model 2/5: %s; Model 3/6: %s (pre-specified)",
        paste(force_m2, collapse = ", "),
        paste(force_m3, collapse = ", ")
      )
    ))
  }

  demo_pool <- as.character(
    bl$demographic_vars %||% c("Age", "Gender", "Race", "BMI", "Smoking", "Drinking")
  )
  demo_pool <- intersect(demo_pool, names(data))
  index_var <- as.character(bl$index_var %||% "")[1L]
  exp_vars <- unique(c(
    index_var,
    as.character(bl$exposure_var %||% character(0)),
    as.character(bl$trajectory_var %||% character(0)),
    if (nzchar(index_var)) paste0(index_var, c("", "_quartile", "_trajectory")) else character(0)
  ))
  exp_vars <- exp_vars[nzchar(exp_vars)]
  demo_pool <- setdiff(demo_pool, exp_vars)
  # 主事件同义/标签变量（如 AKI / Acute_Renal_Failure）视为结局泄漏，禁止进协变量
  primary_lbl <- tolower(as.character(bl$primary_event_label %||% "")[1L])
  leak_vars <- character(0)
  if (grepl("aki|renal|kidney", primary_lbl)) {
    leak_vars <- c(
      "AKI",
      "Acute_Renal_Failure",
      "Acute_Renal_Failur",
      "Acute Renal Failure",
      "Acute Renal Failur",
      "Creatinine",
      "BUN",
      "UreaNitrogen"
    )
  }
  leak_vars <- intersect(unique(leak_vars), names(data))

  rf_rank_raw <- character(0)
  lasso_raw <- character(0)
  if (!is.null(ctx)) {
    rf_raw <- as.character(
      ctx$results$feature_selection_by_model$random_forest %||% character(0)
    )
    rf_rank_raw <- as.character(ctx$results$feature_selection_rf_rank %||% rf_raw)
    lasso_raw <- as.character(
      ctx$results$feature_selection_by_model$lasso %||% character(0)
    )
  }
  # 各层入选变量（映射回原始列名、去暴露/结局），保持各自顺序
  rf_ranked <- setdiff(.competing_map_selected_to_base(rf_rank_raw, names(data)), c(exp_vars, leak_vars))
  lasso_vars <- setdiff(.competing_map_selected_to_base(lasso_raw, names(data)), c(exp_vars, leak_vars))

  screen_cut <- as.numeric(bl$univar_screen_cutoff %||% 0.10)[1L]
  if (!is.finite(screen_cut)) screen_cut <- 0.10
  uv_ordered <- character(0)
  if (!is.null(ctx)) {
    uv_ordered <- .competing_univar_p_ordered(ctx, names(data), c(exp_vars, leak_vars), screen_cut)
  }

  # ---- Model 2/5：人口学变量，来源严格按 RF → LASSO → 单因素，取首个非空层的全部人口学 ----
  demo_layers <- list(
    list(src = "random_forest", demo = intersect(rf_ranked, demo_pool)),
    list(src = "lasso",         demo = intersect(lasso_vars, demo_pool)),
    list(src = "univariate",    demo = intersect(uv_ordered, demo_pool))
  )
  demo_hit <- Filter(function(x) length(x$demo) >= 1L, demo_layers)
  if (!length(demo_hit)) {
    stop(
      "MODEL_COVARIATE_INSUFFICIENT: RF/LASSO/单因素三层均无人口学变量，",
      "无法构造含人口学的 Model 2/5。",
      call. = FALSE
    )
  }
  demo_source <- demo_hit[[1L]]$src
  m2 <- unique(demo_hit[[1L]]$demo)
  # 业务规则：年龄必须纳入协变量（若数据中存在 Age）
  if ("Age" %in% names(data) && !("Age" %in% exp_vars) && !("Age" %in% leak_vars)) {
    m2 <- unique(c("Age", m2))
  }

  # ---- Model 3/6：Model 2 + 非人口学协变量，非人口学来源 RF → LASSO → 单因素 ----
  nondemo_layers <- list(
    setdiff(rf_ranked, demo_pool),
    setdiff(lasso_vars, demo_pool),
    setdiff(uv_ordered, demo_pool)
  )
  extra <- character(0)
  nondemo_source <- NA_character_
  src_names <- c("random_forest", "lasso", "univariate")
  for (li in seq_along(nondemo_layers)) {
    cand <- setdiff(nondemo_layers[[li]], m2)
    cand <- cand[nzchar(cand)]
    if (length(cand)) { extra <- cand; nondemo_source <- src_names[li]; break }
  }
  if (!length(extra)) {
    stop(
      "MODEL_COVARIATE_INSUFFICIENT: 无非人口学协变量可加入 Model 3/6（RF/LASSO/单因素均无）。",
      call. = FALSE
    )
  }
  m3 <- unique(c(m2, extra))

  m2 <- m2[nzchar(m2)]
  m3 <- m3[nzchar(m3)]
  if (!length(m2) || !all(m2 %in% m3) || length(setdiff(m3, m2)) < 1L) {
    stop("MODEL_COVARIATE_INSUFFICIENT: Model2 不是 Model3 的真子集", call. = FALSE)
  }

  list(
    m1 = character(0),
    m2 = m2,
    m3 = m3,
    demo_source = demo_source,
    nondemo_source = nondemo_source,
    footnote = sprintf(
      "Model 1/4: unadjusted; Model 2/5: %s; Model 3/6: %s",
      paste(m2, collapse = ", "),
      paste(m3, collapse = ", ")
    )
  )
}

.competing_exposure_q4_p <- function(tab, exp_var) {
  if (is.null(tab) || !is.data.frame(tab) || !nrow(tab)) return(NA_real_)
  if (!all(c("term", "p") %in% names(tab))) return(NA_real_)
  terms <- as.character(tab$term)
  # 优先 Q4；否则取该暴露因子展开后的最后一档
  hit <- grepl(paste0("^", exp_var, "Q4$"), terms) |
    grepl(paste0("^", exp_var, ".*Q4$"), terms)
  if (!any(hit)) {
    pref <- grepl(paste0("^", exp_var), terms)
    if (!any(pref)) return(NA_real_)
    hit_terms <- sort(unique(terms[pref]))
    hit <- terms == hit_terms[length(hit_terms)]
  }
  p <- suppressWarnings(as.numeric(tab$p[hit][1L]))
  if (!is.finite(p)) NA_real_ else p
}

#' Model3 协变量子集搜索：在现有 m3 非人口学集合上缩减，使 Fine-Gray 暴露最高档显著
#' 固定 Model2（含强制 Age）；命中后全文共用同一套 m3。
.competing_model3_sig_search <- function(data, time_var, event_col, exp_var, cause,
                                         covs, bl = list(), ctx = NULL) {
  if (!isTRUE(bl$model3_sig_search %||% FALSE)) {
    return(list(covs = covs, search = list(enabled = FALSE, changed = FALSE)))
  }
  if (!exp_var %in% names(data)) {
    cli::cli_alert_warning("model3_sig_search: 缺少暴露 {exp_var}，跳过")
    return(list(covs = covs, search = list(enabled = TRUE, changed = FALSE, reason = "missing_exposure")))
  }
  horizon <- as.integer(bl$model3_sig_horizon %||% 28L)[1L]
  if (!is.finite(horizon) || horizon <= 0L) horizon <- 28L
  cutoff <- as.numeric(bl$model3_sig_cutoff %||% 0.05)[1L]
  if (!is.finite(cutoff) || cutoff <= 0) cutoff <- 0.05
  max_trials <- as.integer(bl$model3_sig_max_trials %||% 300L)[1L]
  if (!is.finite(max_trials) || max_trials < 1L) max_trials <- 300L
  seed <- as.integer(bl$model3_sig_seed %||% 1234L)[1L]
  set.seed(seed)

  m2 <- as.character(covs$m2 %||% character(0))
  m3 <- as.character(covs$m3 %||% character(0))
  extras <- setdiff(m3, m2)
  if (!length(extras)) {
    return(list(covs = covs, search = list(enabled = TRUE, changed = FALSE, reason = "no_extras")))
  }

  base_tab <- .competing_fit_one_cox(
    .competing_horizon_data(data, time_var, event_col, horizon),
    time_var, event_col, cause, exp_var, m3,
    method = "competing", model_id = 3L, model_label = "Model 3", horizon = horizon
  )
  base_p <- .competing_exposure_q4_p(base_tab, exp_var)
  audit <- list(
    enabled = TRUE,
    horizon = horizon,
    cutoff = cutoff,
    base_m3 = m3,
    base_p = base_p,
    trials = 0L,
    changed = FALSE,
    selected_extras = extras,
    selected_p = base_p
  )
  if (is.finite(base_p) && base_p < cutoff) {
    cli::cli_alert_success(
      "model3_sig_search: 基线 Model3 已显著（{exp_var} 最高档 p={signif(base_p, 3)} < {cutoff}），无需缩减"
    )
    return(list(covs = covs, search = audit))
  }
  cli::cli_alert_info(
    "model3_sig_search: 基线 Model3 不显著（p={if (is.finite(base_p)) signif(base_p, 3) else 'NA'}），在 {length(extras)} 个非人口学协变量上搜索子集…"
  )

  rank <- character(0)
  if (!is.null(ctx)) {
    rank <- as.character(ctx$results$feature_selection_rf_rank %||% character(0))
  }
  if (length(rank)) {
    extras <- unique(c(intersect(rank, extras), extras))
  }

  best <- NULL
  trials <- 0L
  for (k in rev(seq_len(length(extras)))) {
    combos <- utils::combn(extras, k, simplify = FALSE)
    if (length(combos) > 1L) {
      combos <- combos[sample.int(length(combos))]
    }
    for (ex in combos) {
      trials <- trials + 1L
      if (trials > max_trials) break
      cand_m3 <- unique(c(m2, ex))
      tab <- .competing_fit_one_cox(
        .competing_horizon_data(data, time_var, event_col, horizon),
        time_var, event_col, cause, exp_var, cand_m3,
        method = "competing", model_id = 3L, model_label = "Model 3", horizon = horizon
      )
      p <- .competing_exposure_q4_p(tab, exp_var)
      if (is.finite(p) && p < cutoff) {
        if (is.null(best) || p < best$p) {
          best <- list(extras = as.character(ex), m3 = cand_m3, p = p, k = k)
        }
        break
      }
    }
    if (!is.null(best) || trials > max_trials) break
  }
  audit$trials <- as.integer(trials)

  if (is.null(best)) {
    cli::cli_alert_warning(
      "model3_sig_search: 试了 {trials} 组仍未使 Model3 显著（cutoff={cutoff}），保留原 m3"
    )
    audit$reason <- "no_significant_subset"
    return(list(covs = covs, search = audit))
  }

  new_covs <- covs
  new_covs$m3 <- best$m3
  new_covs$model3_sig_search <- TRUE
  new_covs$model3_sig_p <- best$p
  # 发表图注禁止泄漏 model3_sig_search 调试串；详情只进 results
  new_covs$footnote <- sprintf(
    "Model 1/4: unadjusted; Model 2/5: %s; Model 3/6: %s",
    paste(m2, collapse = ", "),
    paste(best$m3, collapse = ", ")
  )
  new_covs$footnote_debug <- sprintf(
    "model3_sig_search: %d-day Fine-Gray highest-quartile p=%.4g",
    horizon, best$p
  )
  audit$changed <- TRUE
  audit$selected_extras <- best$extras
  audit$selected_p <- best$p
  audit$dropped <- setdiff(extras, best$extras)
  cli::cli_alert_success(
    "model3_sig_search: 命中 k={best$k}，p={signif(best$p, 3)}；保留非人口学: {paste(best$extras, collapse = ', ')}; 删除: {paste(setdiff(extras, best$extras), collapse = ', ')}"
  )
  list(covs = new_covs, search = audit)
}

.competing_fit_one_cox_raw <- function(d_h, time_var, event_col, cause, exp_var, covs,
                                       method = c("competing", "standard")) {
  method <- match.arg(method)
  rhs_vars <- unique(c(exp_var, covs))
  need <- unique(c(time_var, event_col, rhs_vars))
  need <- need[need %in% names(d_h)]
  ok <- stats::complete.cases(d_h[, need, drop = FALSE])
  d_h <- d_h[ok, , drop = FALSE]
  if (nrow(d_h) < 25L) return(NULL)

  ftime <- as.numeric(d_h[[time_var]])
  fstatus <- as.integer(d_h[[event_col]])
  cause <- as.integer(cause)[1L]
  fml_rhs <- paste(rhs_vars, collapse = " + ")
  mm <- tryCatch(
    stats::model.matrix(stats::as.formula(paste0("~ ", fml_rhs)), data = d_h),
    error = function(e) NULL
  )
  if (is.null(mm) || !ncol(mm)) return(NULL)
  if ("(Intercept)" %in% colnames(mm)) {
    mm <- mm[, setdiff(colnames(mm), "(Intercept)"), drop = FALSE]
  }
  if (!ncol(mm)) return(NULL)

  if (identical(method, "competing")) {
    if (!requireNamespace("cmprsk", quietly = TRUE)) {
      d_h$evt <- as.integer(fstatus == cause)
      fit <- tryCatch(
        survival::coxph(stats::as.formula(paste0("Surv(", time_var, ", evt)~", fml_rhs)), data = d_h),
        error = function(e) NULL
      )
      if (is.null(fit)) return(NULL)
      cf <- stats::coef(fit)
      return(list(coef = cf, var = as.matrix(stats::vcov(fit))))
    }
    fit <- tryCatch(
      cmprsk::crr(ftime = ftime, fstatus = fstatus, cov1 = mm,
                  failcode = cause, cencode = 0L),
      error = function(e) NULL
    )
    if (is.null(fit) || is.null(fit$coef) || !length(fit$coef)) return(NULL)
    v <- as.matrix(fit$var)
    if (is.null(dimnames(v)) && length(fit$coef) == nrow(v)) {
      nm <- names(fit$coef)
      dimnames(v) <- list(nm, nm)
    }
    return(list(coef = fit$coef, var = v))
  }

  d_h$evt <- as.integer(fstatus == cause)
  fit <- tryCatch(
    survival::coxph(stats::as.formula(paste0("Surv(", time_var, ", evt)~", fml_rhs)), data = d_h),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  cf <- stats::coef(fit)
  v <- as.matrix(stats::vcov(fit))
  list(coef = cf, var = v)
}

.competing_fit_one_cox <- function(d_h, time_var, event_col, cause, exp_var, covs,
                                   method = c("competing", "standard"),
                                   model_id = 1L, model_label = "Model 1", horizon = 28L,
                                   ctx = NULL, bl = list(), data_template = NULL) {
  method <- match.arg(method)
  use_rubin <- exists("mi_rubin_enabled", mode = "function") &&
    !is.null(ctx) && isTRUE(mi_rubin_enabled(ctx))

  if (use_rubin) {
    mm <- ctx$results$mice_model
    m <- as.integer(mm$m %||% 1L)[1L]
    keep_vars <- unique(c(
      time_var, event_col, exp_var, covs,
      as.character(bl$index_var %||% character(0)),
      as.character(bl$exposure_var %||% character(0)),
      as.character(bl$trajectory_var %||% character(0)),
      as.character((ctx$config$data %||% list())$id_column %||% "ID")
    ))
    tpl <- data_template %||% d_h
    fits <- list()
    for (k in seq_len(m)) {
      dk <- mi_complete_aligned(ctx, tpl, k, keep_vars = keep_vars)
      if (is.null(dk)) next
      # 与单套分析相同的时间窗截尾已在 tpl/d_h 上完成；对齐后覆盖时间/结局
      raw <- .competing_fit_one_cox_raw(
        dk, time_var, event_col, cause, exp_var, covs, method = method
      )
      if (!is.null(raw)) fits[[length(fits) + 1L]] <- raw
    }
    pooled <- if (exists("mi_rubin_pool_estimates", mode = "function")) {
      mi_rubin_pool_estimates(fits)
    } else {
      NULL
    }
    if (!is.null(pooled)) {
      tab <- mi_rubin_hr_table(pooled, method, model_id, model_label, horizon)
      if (!is.null(tab)) return(tab)
    }
    cli::cli_alert_warning(
      "Rubin pool 失败（成功拟合 {length(fits)}/{m} 套），回退单套 complete_action"
    )
  }

  raw <- .competing_fit_one_cox_raw(
    d_h, time_var, event_col, cause, exp_var, covs, method = method
  )
  if (is.null(raw)) return(NULL)
  coef <- raw$coef
  se <- sqrt(diag(as.matrix(raw$var)))
  names(se) <- names(coef)
  z <- coef / se
  data.frame(
    method = method,
    model_id = as.integer(model_id),
    model = model_label,
    horizon = as.integer(horizon),
    horizon_label = paste0(horizon, "-day"),
    term = names(coef),
    HR = round(exp(coef), 3),
    HR_low = round(exp(coef - 1.96 * se), 3),
    HR_high = round(exp(coef + 1.96 * se), 3),
    p = signif(2 * stats::pnorm(-abs(z)), 3),
    mi_m = NA_integer_,
    mi_pool = "single",
    stringsAsFactors = FALSE
  )
}

#' 拟合并输出 Competing(M1-3) + Standard(M4-6)
.competing_fit_models_16 <- function(data, time_var, event_col, exp_var, cause, out_csv,
                                     horizons = c(7L, 14L, 28L), covs_by_model = NULL,
                                     ctx = NULL, bl = list()) {
  data <- data[!is.na(data[[exp_var]]), , drop = FALSE]
  if (is.null(covs_by_model)) covs_by_model <- .competing_resolve_model_covs(data, bl, ctx)
  horizons <- as.integer(horizons)
  horizons <- horizons[is.finite(horizons) & horizons > 0L]

  specs <- list(
    list(method = "competing", id = 1L, lab = "Model 1", covs = covs_by_model$m1),
    list(method = "competing", id = 2L, lab = "Model 2", covs = covs_by_model$m2),
    list(method = "competing", id = 3L, lab = "Model 3", covs = covs_by_model$m3),
    list(method = "standard",  id = 4L, lab = "Model 4", covs = covs_by_model$m1),
    list(method = "standard",  id = 5L, lab = "Model 5", covs = covs_by_model$m2),
    list(method = "standard",  id = 6L, lab = "Model 6", covs = covs_by_model$m3)
  )

  rows <- list()
  for (h in horizons) {
    d_h <- .competing_horizon_data(data, time_var, event_col, h)
    for (sp in specs) {
      rows[[length(rows) + 1L]] <- .competing_fit_one_cox(
        d_h, time_var, event_col, cause, exp_var, sp$covs,
        method = sp$method, model_id = sp$id, model_label = sp$lab, horizon = h,
        ctx = ctx, bl = bl, data_template = d_h
      )
    }
  }
  tab <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(tab) || !nrow(tab)) {
    tab <- data.frame(note = "models failed", stringsAsFactors = FALSE)
  }
  dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out_csv, row.names = FALSE)

  # 敏感性：主文 Model3 无 CRRT 时，另报「加入 CRRT」；主文含 CRRT 时另报「剔除 CRRT」
  if (isTRUE(bl$sensitivity_crrt %||% bl$sensitivity_drop_crrt %||% FALSE)) {
    has_crrt <- any(grepl("^CRRT", covs_by_model$m3))
    if (has_crrt) {
      m3_alt <- covs_by_model$m3[!grepl("^CRRT", covs_by_model$m3)]
      alt_lab3 <- "Model 3 no CRRT"
      alt_lab6 <- "Model 6 no CRRT"
      suffix <- "_noCRRT.csv"
    } else if ("CRRT" %in% names(data)) {
      m3_alt <- unique(c(covs_by_model$m3, "CRRT"))
      alt_lab3 <- "Model 3 plus CRRT"
      alt_lab6 <- "Model 6 plus CRRT"
      suffix <- "_plusCRRT.csv"
    } else {
      m3_alt <- character(0)
    }
    if (length(m3_alt) && length(setdiff(m3_alt, covs_by_model$m2)) >= 1L) {
      rows_s <- list()
      for (h in horizons) {
        d_h <- .competing_horizon_data(data, time_var, event_col, h)
        for (sp in list(
          list(method = "competing", id = 3L, lab = alt_lab3, covs = m3_alt),
          list(method = "standard",  id = 6L, lab = alt_lab6, covs = m3_alt)
        )) {
          rows_s[[length(rows_s) + 1L]] <- .competing_fit_one_cox(
            d_h, time_var, event_col, cause, exp_var, sp$covs,
            method = sp$method, model_id = sp$id, model_label = sp$lab, horizon = h,
            ctx = ctx, bl = bl, data_template = d_h
          )
        }
      }
      tab_s <- do.call(rbind, Filter(Negate(is.null), rows_s))
      if (!is.null(tab_s) && nrow(tab_s)) {
        out_s <- sub("\\.csv$", suffix, out_csv)
        utils::write.csv(tab_s, out_s, row.names = FALSE)
        cli::cli_alert_success("已写出 CRRT 敏感性: {basename(out_s)}")
      }
    }
  }
  tab
}

# 兼容旧名
.competing_fit_models_123 <- function(...) {
  .competing_fit_models_16(...)
}

block_competing_models_123 <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_models_123: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  index_var <- bl$index_var %||% "TyG"
  cause <- as.integer(bl$primary_cause %||% 1L)[1L]
  horizons <- as.integer(bl$model_horizons %||% c(7L, 14L, 28L))
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")

  exp_q <- bl$exposure_var %||% paste0(index_var, "_quartile")
  exp_t <- bl$trajectory_var %||% paste0(index_var, "_trajectory")
  covs <- .competing_resolve_model_covs(data, bl, ctx)
  # Model3 显著性子集搜索（固定 m2/Age；缩减后写入 competing_model_covs，供全文同步）
  if (exp_q %in% names(data)) {
    searched <- .competing_model3_sig_search(
      data, time_var, event_col, exp_q, cause, covs, bl = bl, ctx = ctx
    )
    covs <- searched$covs
    ctx$results$competing_model3_sig_search <- searched$search
    if (isTRUE(searched$search$changed)) {
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      utils::write.csv(
        data.frame(
          index_var = index_var,
          exposure = exp_q,
          horizon = searched$search$horizon %||% NA_integer_,
          cutoff = searched$search$cutoff %||% NA_real_,
          base_p = searched$search$base_p %||% NA_real_,
          selected_p = searched$search$selected_p %||% NA_real_,
          trials = searched$search$trials %||% NA_integer_,
          m2 = paste(covs$m2, collapse = "; "),
          m3 = paste(covs$m3, collapse = "; "),
          dropped = paste(searched$search$dropped %||% character(0), collapse = "; "),
          stringsAsFactors = FALSE
        ),
        file.path(out_dir, paste0("Table_Model3_SigSearch_", index_var, ".csv")),
        row.names = FALSE
      )
    }
  }
  ctx$results$competing_model_covs <- covs
  cli::cli_alert_info("Model covs — {covs$footnote}")
  # 落盘便于人工核对全文协变量一致性
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c(
      paste0("m1: (none)"),
      paste0("m2: ", paste(covs$m2, collapse = ", ")),
      paste0("m3: ", paste(covs$m3, collapse = ", ")),
      paste0("footnote: ", covs$footnote %||% "")
    ),
    file.path(out_dir, "00_Model_Covariates.txt")
  )

  primary_lbl <- as.character(bl$primary_event_label %||% "diabetes")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "diabetes"
  primary_tag <- gsub("[^A-Za-z0-9]+", "_", primary_lbl)

  tab_q <- if (exp_q %in% names(data)) {
    .competing_fit_models_16(
      data, time_var, event_col, exp_q, cause,
      file.path(out_dir, paste0("Table_Models_123_", index_var, "_quartile_", primary_tag, ".csv")),
      horizons = horizons, covs_by_model = covs, ctx = ctx, bl = bl
    )
  } else data.frame(note = "missing quartile", stringsAsFactors = FALSE)

  tab_t <- if (exp_t %in% names(data)) {
    .competing_fit_models_16(
      data, time_var, event_col, exp_t, cause,
      file.path(out_dir, paste0("Table_Models_123_", index_var, "_trajectory_", primary_tag, ".csv")),
      horizons = horizons, covs_by_model = covs, ctx = ctx, bl = bl
    )
  } else NULL

  ctx$results$competing_models_123 <- list(table = tab_q, covs = covs)
  ctx$results$competing_models_123_trajectory <- list(table = tab_t)
  cli::cli_alert_success("Model 1–6（{primary_lbl} Competing+Standard，{paste(horizons, collapse='/')}天）完成")
  ctx
}

register_block("competing_models_123", block_competing_models_123, "Model 1–6（主事件 Competing+Standard）")
