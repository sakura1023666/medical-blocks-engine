# 预后 2.0：Cox / 趋势项在 m>1 时按 Rubin 规则合并（专业 MI）。
# 依赖引擎 R/mi_rubin_pool.R。
#
# 分层口径（与竞争风险块一致）：
#   - 操作层（Boruta / SHAP / KM / RCS 画图 / Table1）：可用 complete #1
#   - 推断层（Table 3 Cox、敏感性 Cox）：m 套各自拟合 → Rubin 合并
# 禁止：m=5 却只报 complete#1 的 HR/P，还写成「多重插补」。

`%||%` <- function(a, b) if (is.null(a)) b else a

pv2_cox_fit_raw <- function(d, rhs, time_var = "futime_years", event_var = "fustatus",
                            weighted = FALSE) {
  d <- as.data.frame(d)
  d$time <- suppressWarnings(as.numeric(d[[time_var]]))
  d$event <- as.integer(d[[event_var]])
  ok <- is.finite(d$time) & d$time > 0 & !is.na(d$event)
  d <- d[ok, , drop = FALSE]
  if (!nrow(d)) return(NULL)
  fml <- stats::as.formula(paste("survival::Surv(time, event) ~", rhs))
  fit <- tryCatch({
    if (isTRUE(weighted) &&
        all(c("survey_weight", "psu", "strata") %in% names(d)) &&
        requireNamespace("survey", quietly = TRUE)) {
      d2 <- d[!is.na(d$survey_weight) & d$survey_weight > 0 &
                !is.na(d$psu) & !is.na(d$strata), , drop = FALSE]
      if (!nrow(d2)) return(NULL)
      des <- survey::svydesign(
        ids = ~psu, strata = ~strata, weights = ~survey_weight,
        data = d2, nest = TRUE
      )
      survey::svycoxph(fml, design = des)
    } else {
      survival::coxph(fml, data = d, ties = "efron")
    }
  }, error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  cf <- stats::coef(fit)
  V <- tryCatch(as.matrix(stats::vcov(fit)), error = function(e) NULL)
  if (is.null(V) || !length(cf)) return(NULL)
  list(coef = cf, var = V)
}

#' 单套或 Rubin 合并后的 HR 表（列：term, hr, lo, hi, p, mi_m, mi_pool）
pv2_cox_extract <- function(d, rhs, mids = NULL, time_var = "futime_years",
                            event_var = "fustatus", exposure_keep = character(0),
                            weighted = FALSE, rubin = TRUE) {
  engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
    "E:/01block/01Block-new-Final"
  } else {
    "/mnt/e/01block/01Block-new-Final"
  }
  if (!exists("mi_rubin_pool_estimates", mode = "function")) {
    source(file.path(engine, "R/mi_rubin_pool.R"), local = FALSE)
  }

  to_hr_df <- function(pooled) {
    if (is.null(pooled) || !length(pooled$coef)) return(NULL)
    z <- pooled$coef / pooled$se
    data.frame(
      term = names(pooled$coef),
      hr = as.numeric(exp(pooled$coef)),
      lo = as.numeric(exp(pooled$coef - 1.96 * pooled$se)),
      hi = as.numeric(exp(pooled$coef + 1.96 * pooled$se)),
      p = as.numeric(2 * stats::pnorm(-abs(z))),
      mi_m = as.integer(pooled$m %||% 1L),
      mi_pool = if (isTRUE(as.integer(pooled$m %||% 1L) > 1L)) "rubin" else "single",
      stringsAsFactors = FALSE
    )
  }

  use_rubin <- isTRUE(rubin) && !is.null(mids) && inherits(mids, "mids") &&
    as.integer(mids$m %||% 1L)[1L] > 1L

  if (!use_rubin) {
    raw <- pv2_cox_fit_raw(d, rhs, time_var, event_var, weighted = weighted)
    if (is.null(raw)) return(NULL)
    se <- sqrt(diag(as.matrix(raw$var)))
    names(se) <- names(raw$coef)
    return(to_hr_df(list(coef = raw$coef, se = se, m = 1L)))
  }

  m <- as.integer(mids$m)[1L]
  keep <- unique(c(time_var, event_var, exposure_keep))
  # 从 mids 取第 k 套，暴露/结局/时间强制用模板 d（未插补）
  id_candidates <- c("ID", "subject_id", "id")
  id_col <- id_candidates[id_candidates %in% names(d)][1L]
  fits <- list()
  for (k in seq_len(m)) {
    dk <- tryCatch(mice::complete(mids, action = k), error = function(e) NULL)
    if (is.null(dk) || !nrow(dk)) next
    # 行序与插补时一致：若有 ID 则按 ID 对齐到分析子集 d
    if (!is.na(id_col) && id_col %in% names(dk) && id_col %in% names(d)) {
      idx <- match(as.character(d[[id_col]]), as.character(dk[[id_col]]))
      if (all(is.na(idx))) next
      ok <- !is.na(idx)
      dk <- dk[idx[ok], , drop = FALSE]
      tpl <- d[ok, , drop = FALSE]
    } else if (nrow(dk) == nrow(d)) {
      tpl <- d
    } else {
      next
    }
    for (v in intersect(names(tpl), names(dk))) {
      # 协变量用插补值；暴露/时间/结局用模板
      if (!v %in% keep) tpl[[v]] <- dk[[v]]
    }
    # 模板没有、插补有的列
    for (v in setdiff(names(dk), names(tpl))) tpl[[v]] <- dk[[v]]
    raw <- pv2_cox_fit_raw(tpl, rhs, time_var, event_var, weighted = weighted)
    if (!is.null(raw)) fits[[length(fits) + 1L]] <- raw
  }
  pooled <- mi_rubin_pool_estimates(fits)
  if (is.null(pooled)) {
    # 回退单套操作层
    return(pv2_cox_extract(d, rhs, mids = NULL, time_var = time_var,
                           event_var = event_var, weighted = weighted, rubin = FALSE))
  }
  to_hr_df(pooled)
}

pv2_mi_methods_footnote <- function(m = 5L, maxit = 5L, seed = 1234L) {
  c(
    sprintf(
      "Multiple imputation by chained equations (cart, m = %d, maxit = %d, seed = %d).",
      as.integer(m), as.integer(maxit), as.integer(seed)
    ),
    paste(
      "Cox proportional hazards estimates were obtained in each imputed dataset",
      "and combined using Rubin's rules."
    ),
    paste(
      "Descriptive tables, feature selection (Boruta/SHAP), Kaplan–Meier and RCS plots",
      "used the first completed dataset for operational consistency."
    ),
    "Exposure, follow-up time, death status and survey weights were not imputed."
  )
}
