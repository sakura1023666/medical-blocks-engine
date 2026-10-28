###############################################################################
# quantile_scheme_cascade.R — 分位级联闸门（引擎级，全项目复用）
#
# 规则：quartile → tertile → binary
#   在「未调整（crude）Cox/logistic」下检验最高档 vs 最低档；
#   当前档不通过则降一档；全文 Table2 / Cox / KM / 亚组 / 脚注 共用锁定 scheme。
#
# 显著性口径（与 logistic_gate / cox_gate 一致）：
#   只看最高暴露组 vs 参照；不要求中间档显著；连续行不参与闸门。
#
# Config（可选）:
#   config$quantile_scheme_cascade <- list(
#     enable = TRUE,
#     try_schemes = c("quartile", "tertile", "binary"),
#     p_threshold = 0.05,
#     pass_rule = "all",          # all | any | primary
#     on_none_pass = "best_n_pass", # best_n_pass | last | first
#     family = "cox",             # cox | glm_binomial
#     time_var = "futime_years", event_var = "fustatus",
#     outcome_var = NULL,         # glm 时用
#     lock_to_ctx = TRUE
#   )
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 分位 scheme 元数据（标签 / 对比文案 / 图例）
quantile_scheme_meta <- function(scheme) {
  scheme <- tolower(trimws(as.character(scheme %||% "quartile")[1L]))
  if (!scheme %in% c("quartile", "tertile", "binary", "median", "quintile")) {
    scheme <- "quartile"
  }
  if (identical(scheme, "median")) scheme <- "binary"
  switch(
    scheme,
    quartile = list(
      scheme = "quartile", n_groups = 4L,
      labels = c("Q1", "Q2", "Q3", "Q4"),
      probs = c(0, 0.25, 0.5, 0.75, 1),
      ref = "Q1", high = "Q4",
      contrast_lab = "Q4 vs Q1",
      legend_title = "Quartile",
      level_prefix = "Quartile",
      footnotes_scheme = "quartile (Q1-Q4)"
    ),
    tertile = list(
      scheme = "tertile", n_groups = 3L,
      labels = c("T1", "T2", "T3"),
      probs = c(0, 1 / 3, 2 / 3, 1),
      ref = "T1", high = "T3",
      contrast_lab = "T3 vs T1",
      legend_title = "Tertile",
      level_prefix = "Tertile",
      footnotes_scheme = "tertile (T1-T3)"
    ),
    binary = list(
      scheme = "binary", n_groups = 2L,
      labels = c("Low", "High"),
      probs = c(0, 0.5, 1),
      ref = "Low", high = "High",
      contrast_lab = "High vs Low",
      legend_title = "Median split",
      level_prefix = "",
      footnotes_scheme = "binary (median split: Low/High)"
    ),
    quintile = list(
      scheme = "quintile", n_groups = 5L,
      labels = c("Q1", "Q2", "Q3", "Q4", "Q5"),
      probs = c(0, 0.2, 0.4, 0.6, 0.8, 1),
      ref = "Q1", high = "Q5",
      contrast_lab = "Q5 vs Q1",
      legend_title = "Quintile",
      level_prefix = "Quintile",
      footnotes_scheme = "quintile (Q1-Q5)"
    )
  )
}

#' 按 scheme 切连续暴露为有序因子（最低档为参照）
quantile_scheme_cut <- function(x, scheme = "quartile") {
  meta <- quantile_scheme_meta(scheme)
  x <- as.numeric(x)
  ok <- is.finite(x)
  out <- rep(NA_character_, length(x))
  if (!any(ok)) {
    return(factor(out, levels = meta$labels))
  }
  br <- unique(as.numeric(stats::quantile(x[ok], probs = meta$probs, na.rm = TRUE, type = 7)))
  need <- meta$n_groups + 1L
  if (length(br) < need) {
    # 分位塌缩：尽量切；不够则全部 NA
    if (length(br) < 2L) return(factor(out, levels = meta$labels))
    labs <- meta$labels[seq_len(length(br) - 1L)]
    out[ok] <- as.character(cut(x[ok], breaks = br, include.lowest = TRUE, labels = labs))
    return(factor(out, levels = meta$labels))
  }
  out[ok] <- as.character(cut(
    x[ok], breaks = br, include.lowest = TRUE, labels = meta$labels
  ))
  factor(out, levels = meta$labels)
}

#' 未调整模型：最高档 vs 最低档的 P / HR(OR)
quantile_scheme_crude_highest_p <- function(
    data, expo_fac, time_var = NULL, event_var = NULL,
    outcome_var = NULL, family = c("cox", "glm_binomial")) {
  family <- match.arg(family)
  dd <- as.data.frame(data)
  dd$.__G__ <- droplevels(factor(expo_fac))
  lv <- levels(dd$.__G__)
  if (length(lv) < 2L) {
    return(list(p = NA_real_, est = NA_real_, lo = NA_real_, hi = NA_real_,
                high = NA_character_, n = nrow(dd), events = NA_integer_))
  }
  high <- lv[length(lv)]
  if (identical(family, "cox")) {
    if (!requireNamespace("survival", quietly = TRUE)) {
      stop("quantile_scheme_cascade: package survival required for family=cox", call. = FALSE)
    }
    if (is.null(time_var) || is.null(event_var) ||
        !time_var %in% names(dd) || !event_var %in% names(dd)) {
      stop("quantile_scheme_cascade: time_var/event_var required for Cox", call. = FALSE)
    }
    dd <- dd[is.finite(dd[[time_var]]) & !is.na(dd$.__G__) &
               is.finite(as.numeric(dd[[event_var]])), , drop = FALSE]
    if (nrow(dd) < 10L) {
      return(list(p = NA_real_, est = NA_real_, lo = NA_real_, hi = NA_real_,
                  high = high, n = nrow(dd), events = sum(as.integer(dd[[event_var]]) == 1L)))
    }
    fit <- tryCatch(
      survival::coxph(
        stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ .__G__")),
        data = dd
      ),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      return(list(p = NA_real_, est = NA_real_, lo = NA_real_, hi = NA_real_,
                  high = high, n = nrow(dd), events = sum(as.integer(dd[[event_var]]) == 1L)))
    }
    if (exists("cox_gate_target_group_p", mode = "function")) {
      p <- cox_gate_target_group_p(fit, high, group_var = ".__G__")
    } else {
      sm <- summary(fit)
      rn <- rownames(sm$coefficients)
      hit <- paste0(".__G__", high)
      p <- if (hit %in% rn) as.numeric(sm$coefficients[hit, "Pr(>|z|)"]) else NA_real_
    }
    ci <- tryCatch(summary(fit)$conf.int, error = function(e) NULL)
    hit <- paste0(".__G__", high)
    est <- lo <- hi <- NA_real_
    if (!is.null(ci) && hit %in% rownames(ci)) {
      est <- as.numeric(ci[hit, 1L])
      lo <- as.numeric(ci[hit, 3L])
      hi <- as.numeric(ci[hit, 4L])
    }
    return(list(
      p = p, est = est, lo = lo, hi = hi, high = high,
      n = nrow(dd), events = sum(as.integer(dd[[event_var]]) == 1L)
    ))
  }
  # glm binomial
  if (is.null(outcome_var) || !outcome_var %in% names(dd)) {
    stop("quantile_scheme_cascade: outcome_var required for glm_binomial", call. = FALSE)
  }
  y <- dd[[outcome_var]]
  if (is.character(y) || is.factor(y)) {
    # 尽量用引擎 0/1
    if (exists("pipeline_outcome_as_01", mode = "function")) {
      y <- pipeline_outcome_as_01(y)
    } else {
      y <- as.integer(as.factor(y)) - 1L
    }
  }
  dd$.__Y__ <- as.integer(y)
  dd <- dd[!is.na(dd$.__Y__) & !is.na(dd$.__G__), , drop = FALSE]
  fit <- tryCatch(
    stats::glm(.__Y__ ~ .__G__, data = dd, family = stats::binomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    return(list(p = NA_real_, est = NA_real_, lo = NA_real_, hi = NA_real_,
                high = high, n = nrow(dd), events = sum(dd$.__Y__ == 1L)))
  }
  cm <- summary(fit)$coefficients
  hit <- paste0(".__G__", high)
  if (!hit %in% rownames(cm)) {
    return(list(p = NA_real_, est = NA_real_, lo = NA_real_, hi = NA_real_,
                high = high, n = nrow(dd), events = sum(dd$.__Y__ == 1L)))
  }
  b <- as.numeric(cm[hit, "Estimate"])
  se <- as.numeric(cm[hit, "Std. Error"])
  p <- as.numeric(cm[hit, "Pr(>|z|)"])
  list(
    p = p, est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
    high = high, n = nrow(dd), events = sum(dd$.__Y__ == 1L)
  )
}

.qsc_normalize_cfg <- function(cfg = NULL) {
  q <- (cfg %||% list())$quantile_scheme_cascade %||% list()
  list(
    enable = isTRUE(q$enable %||% TRUE),
    try_schemes = {
      ts <- tolower(as.character(q$try_schemes %||% c("quartile", "tertile", "binary")))
      ts[ts == "median"] <- "binary"
      unique(ts[ts %in% c("quartile", "tertile", "binary", "quintile")])
    },
    p_threshold = {
      p <- as.numeric(q$p_threshold %||% 0.05)[1L]
      if (!is.finite(p) || p <= 0 || p >= 1) 0.05 else p
    },
    pass_rule = {
      r <- tolower(trimws(as.character(q$pass_rule %||% "all")[1L]))
      if (!r %in% c("all", "any", "primary")) "all" else r
    },
    on_none_pass = {
      r <- tolower(trimws(as.character(q$on_none_pass %||% "best_n_pass")[1L]))
      if (!r %in% c("best_n_pass", "last", "first")) "best_n_pass" else r
    },
    family = {
      f <- tolower(trimws(as.character(q$family %||% "cox")[1L]))
      if (f %in% c("logistic", "glm", "binomial")) "glm_binomial" else if (f == "cox") "cox" else "cox"
    },
    time_var = as.character(q$time_var %||% "futime_years")[1L],
    event_var = as.character(q$event_var %||% "fustatus")[1L],
    outcome_var = {
      ov <- q$outcome_var %||% NULL
      if (is.null(ov)) NA_character_ else as.character(ov)[1L]
    },
    lock_to_ctx = isTRUE(q$lock_to_ctx %||% TRUE),
    force_scheme = {
      fs <- tolower(trimws(as.character(q$force_scheme %||% "")[1L]))
      if (fs %in% c("quartile", "tertile", "binary", "quintile")) fs else NA_character_
    }
  )
}

.qsc_scheme_passes <- function(pass_vec, rule, primary_index = NULL, index_vars) {
  if (!length(pass_vec)) return(FALSE)
  if (identical(rule, "any")) return(any(pass_vec, na.rm = TRUE))
  if (identical(rule, "primary")) {
    ix <- as.character(primary_index %||% index_vars[1L])[1L]
    if (!ix %in% names(pass_vec)) return(FALSE)
    return(isTRUE(pass_vec[[ix]]))
  }
  # all
  all(pass_vec, na.rm = TRUE) && !any(is.na(pass_vec))
}

#' 核心：quartile→tertile→binary 级联，返回锁定 scheme + 明细
#'
#' @param data data.frame（操作层 complete#1 即可；闸门只判 crude 最高档）
#' @param index_vars 暴露列名
#' @param config 可选；读 config$quantile_scheme_cascade
#' @param primary_index pass_rule=primary 时用
quantile_scheme_resolve_cascade <- function(
    data, index_vars, config = NULL, primary_index = NULL,
    time_var = NULL, event_var = NULL, outcome_var = NULL, family = NULL) {
  opt <- .qsc_normalize_cfg(config)
  if (!isTRUE(opt$enable)) {
    sch <- opt$force_scheme
    if (is.na(sch)) sch <- "quartile"
    meta <- quantile_scheme_meta(sch)
    return(list(
      scheme = sch, meta = meta, enabled = FALSE,
      reason = "quantile_scheme_cascade disabled",
      trial = data.frame(), factors = list(),
      p_threshold = opt$p_threshold, pass_rule = opt$pass_rule
    ))
  }
  if (!is.na(opt$force_scheme)) {
    sch <- opt$force_scheme
    meta <- quantile_scheme_meta(sch)
    facs <- setNames(lapply(index_vars, function(ix) {
      if (!ix %in% names(data)) return(NULL)
      quantile_scheme_cut(data[[ix]], sch)
    }), index_vars)
    return(list(
      scheme = sch, meta = meta, enabled = TRUE,
      reason = paste0("force_scheme=", sch),
      trial = data.frame(), factors = facs,
      p_threshold = opt$p_threshold, pass_rule = opt$pass_rule
    ))
  }

  index_vars <- unique(as.character(index_vars)[nzchar(as.character(index_vars))])
  index_vars <- index_vars[index_vars %in% names(data)]
  if (!length(index_vars)) {
    stop("quantile_scheme_resolve_cascade: no index_vars found in data", call. = FALSE)
  }
  fam <- family %||% opt$family
  tv <- time_var %||% opt$time_var
  ev <- event_var %||% opt$event_var
  ov <- outcome_var %||% opt$outcome_var
  if (identical(fam, "glm_binomial") && (is.na(ov) || !nzchar(ov))) {
    ov <- as.character((config %||% list())$data$outcome_column %||% "Disease")[1L]
  }
  try_schemes <- opt$try_schemes
  if (!length(try_schemes)) try_schemes <- c("quartile", "tertile", "binary")

  rows <- list()
  pass_by_scheme <- list()
  for (sch in try_schemes) {
    pass <- setNames(logical(length(index_vars)), index_vars)
    for (ix in index_vars) {
      g <- quantile_scheme_cut(data[[ix]], sch)
      r <- quantile_scheme_crude_highest_p(
        data, g, time_var = tv, event_var = ev,
        outcome_var = if (is.na(ov)) NULL else ov, family = fam
      )
      ok <- is.finite(r$p) && r$p < opt$p_threshold
      pass[[ix]] <- ok
      rows[[length(rows) + 1L]] <- data.frame(
        scheme = sch, index = ix, high = r$high %||% NA_character_,
        p = r$p, est = r$est, lo = r$lo, hi = r$hi,
        n = r$n, events = r$events, pass = ok,
        stringsAsFactors = FALSE
      )
    }
    pass_by_scheme[[sch]] <- pass
  }
  trial <- if (length(rows)) do.call(rbind, rows) else data.frame()

  selected <- NA_character_
  reason <- ""
  for (sch in try_schemes) {
    if (.qsc_scheme_passes(pass_by_scheme[[sch]], opt$pass_rule, primary_index, index_vars)) {
      selected <- sch
      reason <- sprintf(
        "cascade first-pass: %s (pass_rule=%s, p<%.3f, crude highest vs lowest)",
        sch, opt$pass_rule, opt$p_threshold
      )
      break
    }
  }
  if (is.na(selected)) {
    if (identical(opt$on_none_pass, "last")) {
      selected <- try_schemes[length(try_schemes)]
      reason <- paste0("no scheme passed; on_none_pass=last → ", selected)
    } else if (identical(opt$on_none_pass, "first")) {
      selected <- try_schemes[1L]
      reason <- paste0("no scheme passed; on_none_pass=first → ", selected)
    } else {
      # best_n_pass：通过指标数最多；并列取更粗（靠后）分位
      n_pass <- vapply(try_schemes, function(sch) {
        sum(pass_by_scheme[[sch]], na.rm = TRUE)
      }, integer(1))
      best <- max(n_pass)
      cands <- try_schemes[n_pass == best]
      selected <- cands[length(cands)]
      reason <- sprintf(
        "no scheme passed pass_rule=%s; best_n_pass=%d → %s",
        opt$pass_rule, best, selected
      )
    }
  }

  meta <- quantile_scheme_meta(selected)
  facs <- setNames(lapply(index_vars, function(ix) {
    quantile_scheme_cut(data[[ix]], selected)
  }), index_vars)

  if (exists("cli::cli_alert_info", mode = "function") ||
      requireNamespace("cli", quietly = TRUE)) {
    tryCatch({
      for (sch in try_schemes) {
        seg <- vapply(index_vars, function(ix) {
          rr <- trial[trial$scheme == sch & trial$index == ix, , drop = FALSE]
          sprintf("%s P=%s%s", ix,
                  if (!nrow(rr) || !is.finite(rr$p[1])) "NA" else sprintf("%.3f", rr$p[1]),
                  if (nrow(rr) && isTRUE(rr$pass[1])) "*" else "")
        }, character(1))
        cli::cli_alert_info("分位级联 [{sch}]: {paste(seg, collapse = '; ')}")
      }
      cli::cli_alert_success("分位级联锁定 scheme={selected} — {reason}")
    }, error = function(e) NULL)
  }

  list(
    scheme = selected,
    meta = meta,
    enabled = TRUE,
    reason = reason,
    trial = trial,
    factors = facs,
    p_threshold = opt$p_threshold,
    pass_rule = opt$pass_rule,
    try_schemes = try_schemes,
    family = fam,
    index_vars = index_vars
  )
}

#' 把级联结果写入 ctx$results（供 subgroup / finalize 单一事实源）
quantile_scheme_lock_to_ctx <- function(ctx, resolved) {
  if (is.null(ctx) || is.null(resolved)) return(invisible(ctx))
  sch <- as.character(resolved$scheme)[1L]
  ctx$results$quantile_scheme_cascade <- resolved
  ctx$results$quantile_scheme_selected <- sch
  ctx$results$cox_grouping_scheme <- sch
  ctx$results$cox_selected_scheme <- sch
  # 发病侧若尚未锁定，也写入（不覆盖已有 logistic 闸门）
  if (is.null(ctx$results$logistic_grouping_scheme) ||
      !nzchar(as.character(ctx$results$logistic_grouping_scheme %||% "")[1L])) {
    ctx$results$logistic_grouping_scheme <- sch
  }
  invisible(ctx)
}

#' 在 data 上附加 {index}_Group 列（及兼容旧名 _Q）
quantile_scheme_attach_groups <- function(data, resolved, index_vars = NULL) {
  index_vars <- index_vars %||% resolved$index_vars %||% names(resolved$factors)
  index_vars <- as.character(index_vars)
  for (ix in index_vars) {
    g <- resolved$factors[[ix]]
    if (is.null(g)) {
      if (!ix %in% names(data)) next
      g <- quantile_scheme_cut(data[[ix]], resolved$scheme)
    }
    data[[paste0(ix, "_Group")]] <- g
    # 兼容旧 remirror / runner 读 _Q
    data[[paste0(ix, "_Q")]] <- g
  }
  attr(data, "quantile_scheme") <- resolved$scheme
  attr(data, "quantile_scheme_meta") <- resolved$meta
  data
}

#' 脚注短句
quantile_scheme_footnote_lines <- function(resolved) {
  if (is.null(resolved)) return(character(0))
  meta <- resolved$meta %||% quantile_scheme_meta(resolved$scheme)
  c(
    sprintf(
      "Exposure grouping locked by quantile_scheme_cascade: %s (tried %s; pass_rule=%s; crude highest vs lowest P<%.3f).",
      meta$footnotes_scheme,
      paste(resolved$try_schemes %||% character(0), collapse = "\u2192"),
      resolved$pass_rule %||% "all",
      as.numeric(resolved$p_threshold %||% 0.05)
    ),
    sprintf("Selection reason: %s", resolved$reason %||% ""),
    sprintf("All incidence/Cox/KM/subgroup displays use the same grouping (%s).", meta$contrast_lab)
  )
}

#' 展示行标签：Q2 → "  Quartile 2"；binary High → "  High"
quantile_scheme_level_display <- function(level, scheme) {
  meta <- quantile_scheme_meta(scheme)
  level <- as.character(level)[1L]
  if (identical(meta$scheme, "binary")) return(paste0("  ", level))
  # Q4 / T3
  num <- sub("^[QT]", "", level)
  if (grepl("^[0-9]+$", num) && nzchar(meta$level_prefix)) {
    return(paste0("  ", meta$level_prefix, " ", num))
  }
  paste0("  ", level)
}
