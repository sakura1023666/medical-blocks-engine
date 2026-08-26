###############################################################################
#  cox_gate.R — Cox 四分位/三分位/二分闸门 + 协变量组合搜索（供 Blocks/10_cox 共用）
###############################################################################

#' 最高档分组在 Cox 拟合对象中的 P 值（参照组为最低档）
cox_gate_target_group_p <- function(fit, target_level, group_var = "Group") {
  if (is.null(fit) || is.null(target_level) || !nzchar(target_level)) {
    return(NA_real_)
  }
  smry <- tryCatch(summary(fit), error = function(e) NULL)
  if (is.null(smry)) return(NA_real_)
  coef_mat <- smry$coefficients
  rn <- rownames(coef_mat)
  target_row <- paste0(group_var, target_level)
  if (target_row %in% rn) {
    return(as.numeric(coef_mat[target_row, "Pr(>|z|)"]))
  }
  gv_esc <- gsub("([.|()[\\]{}^$+*?\\\\])", "\\\\\\1", group_var, perl = TRUE)
  hit <- rn[grepl(paste0("^", gv_esc), rn)]
  suf <- sub(paste0("^", gv_esc), "", hit)
  w <- which(suf == target_level)
  if (length(w) == 1L) return(as.numeric(coef_mat[hit[w], "Pr(>|z|)"]))
  NA_real_
}

cox_gate_check_sig <- function(fit, target_level, p_threshold = 0.05, group_var = "Group") {
  p_val <- cox_gate_target_group_p(fit, target_level, group_var = group_var)
  !is.na(p_val) && p_val < p_threshold
}

#' 是否启用协变量组合搜索（显式指定 model1_factors + model2_factors 时默认关闭）
cox_covariate_search_enabled <- function(bl_cfg, ctx = NULL) {
  # 闸门 B 统一协变量后：默认锁定，禁止再按库搜索子集
  if (!is.null(ctx) && isTRUE(ctx$results$dual_db_covariate_harmonized %||% FALSE)) {
    lock_gb <- isTRUE(
      ((ctx$config$dual_db %||% list())$harmonization %||% list())$lock_cox_to_gate_b %||% TRUE
    )
    if (lock_gb) return(FALSE)
  }
  search_cfg <- bl_cfg$covariate_search %||% list()
  if (!is.null(search_cfg$enable)) return(isTRUE(search_cfg$enable))
  explicit <- !is.null(bl_cfg$model1_factors) && !is.null(bl_cfg$model2_factors)
  !explicit
}

#' 双库 Gate B 是否锁定了 Cox 协变量
cox_dual_db_lock_active <- function(ctx) {
  !is.null(ctx) && isTRUE(ctx$results$dual_db_covariate_harmonized %||% FALSE) &&
    isTRUE(
      ((ctx$config$dual_db %||% list())$harmonization %||% list())$lock_cox_to_gate_b %||% TRUE
    )
}

#' 三级回退 tier 时 Cox 搜索使用非实验室 / 实验室分池
cox_resolve_covariate_search_pools <- function(ctx, model1_factors, m2_pool_extra) {
  m1 <- as.character(model1_factors)
  m2 <- as.character(m2_pool_extra)
  if (isTRUE(ctx$results$covariate_model2_lab_only %||% ctx$results$nhanes_logistic_model2_lab_only)) {
    m1 <- as.character(ctx$results$covariate_m1_search_pool %||% m1)
    m2 <- as.character(ctx$results$covariate_m2_search_pool %||% m2)
  }
  list(m1 = m1, m2 = m2, lab_only_tier = isTRUE(
    ctx$results$covariate_model2_lab_only %||% ctx$results$nhanes_logistic_model2_lab_only
  ))
}

#' Phase1 递减 + Phase2 递增；每次 coxph 计 1 次，达 max_attempts 返回 status=exhausted
cox_search_sig_covariate_combo <- function(
    dat, time_var, event_var, base_vars, candidates,
    target_level, p_threshold = 0.05, max_attempts = 1000L, group_var = "Group",
    min_subset_size = 0L) {
  if (length(base_vars) == 0L) base_vars <- "Group"
  cands <- unique(as.character(candidates))
  cands <- cands[nzchar(cands)]
  min_subset_size <- as.integer(min_subset_size)[1L]
  if (!is.finite(min_subset_size) || min_subset_size < 0L) min_subset_size <- 0L
  attempt <- 0L
  exhausted <- FALSE

  .try_one <- function(S) {
    if (length(S) < min_subset_size) return(list(hit = FALSE, done = FALSE))
    if (attempt >= max_attempts) {
      exhausted <<- TRUE
      return(list(hit = FALSE, done = TRUE))
    }
    attempt <<- attempt + 1L
    rhs <- unique(c(base_vars, S))
    fml <- stats::as.formula(paste0(
      "Surv(", time_var, ", ", event_var, ") ~ ",
      paste(rhs, collapse = " + ")
    ))
    fit <- tryCatch(survival::coxph(fml, data = dat), error = function(e) NULL)
    if (is.null(fit)) return(list(hit = FALSE, done = FALSE))
    if (!cox_gate_check_sig(fit, target_level, p_threshold, group_var = group_var)) {
      return(list(hit = FALSE, done = FALSE))
    }
    list(hit = TRUE, done = TRUE, fit = fit, vars = rhs)
  }

  if (length(cands) > 0L) {
    for (S in covariate_subsets_decreasing_from_full(cands)) {
      r <- .try_one(S)
      if (exhausted) return(list(status = "exhausted", attempts = attempt))
      if (isTRUE(r$hit)) return(list(status = "ok", attempts = attempt, fit = r$fit, vars = r$vars))
    }
    for (S in covariate_subsets_increasing_order(cands)) {
      r <- .try_one(S)
      if (exhausted) return(list(status = "exhausted", attempts = attempt))
      if (isTRUE(r$hit)) return(list(status = "ok", attempts = attempt, fit = r$fit, vars = r$vars))
    }
  } else {
    r <- .try_one(character(0))
    if (exhausted) return(list(status = "exhausted", attempts = attempt))
    if (isTRUE(r$hit)) return(list(status = "ok", attempts = attempt, fit = r$fit, vars = r$vars))
  }
  list(status = "not_found", attempts = attempt)
}

#' 先尝试全量 Model1/Model2；若最高组未同时显著且允许搜索，再自动搜索子集
cox_select_covariates_full_then_search <- function(
    dt, time_var, event_var, model1_factors, m2_pool_extra, bl_cfg, ctx = NULL) {
  m1 <- unique(as.character(model1_factors)[nzchar(as.character(model1_factors))])
  m2_extra <- unique(as.character(m2_pool_extra)[nzchar(as.character(m2_pool_extra))])
  m2_extra <- setdiff(m2_extra, m1)
  m2_full <- unique(c(m1, m2_extra))
  p_thresh <- as.numeric(bl_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  search_on <- exists("cox_covariate_search_enabled", mode = "function") &&
    cox_covariate_search_enabled(bl_cfg)
  prefer_full <- isTRUE((bl_cfg$covariate_search %||% list())$prefer_full_first %||% TRUE)
  # 双库 Gate B 后：池已是统一 Model2，允许在该池内搜索；Table 2 最终一致靠 Gate C 后交集再锁
  if (!is.null(ctx) && isTRUE(ctx$results$dual_db_covariate_harmonized) && isTRUE(search_on)) {
    cli::cli_alert_info("Cox: 在 Gate B 统一协变量池内搜索（两库表注最终再取交集对齐）")
  }

  dt$Group <- droplevels(dt$Group)
  target <- tail(levels(dt$Group), 1L)

  .fit_group <- function(covars) {
    rhs <- unique(c("Group", covars))
    fml <- stats::as.formula(paste0(
      "Surv(", time_var, ", ", event_var, ") ~ ", paste(rhs, collapse = " + ")
    ))
    tryCatch(survival::coxph(fml, data = dt), error = function(e) NULL)
  }

  if (prefer_full || !search_on) {
    fit1 <- .fit_group(m1)
    fit2 <- .fit_group(m2_full)
    m1_ok <- cox_gate_check_sig(fit1, target, p_thresh)
    m2_ok <- cox_gate_check_sig(fit2, target, p_thresh) && length(setdiff(m2_full, m1)) > 0L
    if (m1_ok && m2_ok) {
      cli::cli_alert_success(
        "Cox: 全量协变量 Model1/Model2 最高组均显著，保留闸门 B 统一集（不搜索）"
      )
      return(list(
        status = "full_ok", M1 = m1, M2 = m2_full,
        searched = FALSE, m1_attempts = 0L, m2_attempts = 0L
      ))
    }
    if (!search_on) {
      cli::cli_alert_warning(
        paste0(
          "Cox: 全量协变量未同时显著（M1=", m1_ok, ", M2=", m2_ok,
          "），且未开启自动搜索，仍使用全量集"
        )
      )
      return(list(
        status = "full_kept_ns", M1 = m1, M2 = m2_full,
        searched = FALSE, m1_attempts = 0L, m2_attempts = 0L
      ))
    }
    cli::cli_alert_info(
      paste0(
        "Cox: 全量协变量未同时显著（M1 sig=", m1_ok, ", M2 sig=", m2_ok,
        "）→ 开启自动协变量搜索"
      )
    )
  }

  sc <- bl_cfg$covariate_search %||% list()
  cli::cli_alert_info(
    "Cox: 协变量组合搜索（Model1≤{sc$max_model1_attempts %||% 1000L}，Model2≤{sc$max_model2_attempts %||% 1000L} 次）"
  )
  search_res <- cox_fit_searched_covariates(dt, time_var, event_var, m1, m2_extra, bl_cfg)
  if (!identical(search_res$status, "ok")) {
    return(list(
      status = search_res$status %||% "search_fail",
      M1 = m1, M2 = m2_full,
      searched = TRUE,
      search_res = search_res,
      m1_attempts = search_res$m1_attempts %||% 0L,
      m2_attempts = search_res$m2_attempts %||% 0L
    ))
  }
  list(
    status = "search_ok",
    M1 = search_res$final_m1,
    M2 = search_res$final_m2_all,
    searched = TRUE,
    search_res = search_res,
    m1_attempts = search_res$m1_attempts %||% 0L,
    m2_attempts = search_res$m2_attempts %||% 0L
  )
}

#' Crude 显著后依次搜索 Model1 / Model2 协变量子集（对齐 block_COX 逻辑）
cox_fit_searched_covariates <- function(dt, time_var, event_var, m1_pool, m2_pool_extra, bl_cfg) {
  search_cfg <- bl_cfg$covariate_search %||% list()
  p_thresh <- as.numeric(bl_cfg$p_threshold %||% search_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  max_m1 <- as.integer(search_cfg$max_model1_attempts %||% 1000L)[1L]
  max_m2 <- as.integer(search_cfg$max_model2_attempts %||% 1000L)[1L]
  if (!is.finite(max_m1) || max_m1 < 1L) max_m1 <- 1000L
  if (!is.finite(max_m2) || max_m2 < 1L) max_m2 <- 1000L

  dt$Group <- droplevels(dt$Group)
  target <- tail(levels(dt$Group), 1L)

  crude_fit <- tryCatch(
    survival::coxph(
      stats::as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ Group")),
      data = dt
    ),
    error = function(e) NULL
  )
  if (!cox_gate_check_sig(crude_fit, target, p_thresh)) {
    return(list(
      status = "crude_ns",
      crude_fit = crude_fit,
      m1_attempts = 0L,
      m2_attempts = 0L
    ))
  }

  r1 <- cox_search_sig_covariate_combo(
    dt, time_var, event_var, "Group", m1_pool,
    target, p_thresh, max_m1
  )
  if (!identical(r1$status, "ok")) {
    return(list(
      status = paste0("m1_", r1$status),
      m1_attempts = r1$attempts %||% 0L,
      m2_attempts = 0L,
      crude_fit = crude_fit
    ))
  }

  final_m1 <- setdiff(r1$vars, "Group")
  m2_base <- unique(c("Group", final_m1))
  m2_min_extra <- if (length(m2_pool_extra)) 1L else 0L
  r2 <- cox_search_sig_covariate_combo(
    dt, time_var, event_var, m2_base, m2_pool_extra,
    target, p_thresh, max_m2, min_subset_size = m2_min_extra
  )
  if (!identical(r2$status, "ok")) {
    return(list(
      status = paste0("m2_", r2$status),
      m1_attempts = r1$attempts %||% 0L,
      m2_attempts = r2$attempts %||% 0L,
      final_m1 = final_m1,
      crude_fit = crude_fit,
      model1_fit = r1$fit
    ))
  }

  final_m2_all <- setdiff(r2$vars, "Group")
  list(
    status = "ok",
    final_m1 = final_m1,
    final_m2_all = final_m2_all,
    final_m2_extra = setdiff(final_m2_all, final_m1),
    m1_attempts = r1$attempts %||% 0L,
    m2_attempts = r2$attempts %||% 0L,
    crude_fit = crude_fit,
    model1_fit = r1$fit,
    model2_fit = r2$fit
  )
}

#' Cox 表：Model2 必须严格多于 Model1，且（若提供数据）两模型最高组均须显著
cox_enforce_model2_gt_m1 <- function(
    m1, m2, m2_pool_extra = character(0), ctx = NULL,
    dat = NULL, time_var = NULL, event_var = NULL, bl_cfg = NULL) {
  m1 <- unique(as.character(m1)[nzchar(as.character(m1))])
  m2 <- unique(as.character(m2)[nzchar(as.character(m2))])
  p_thresh <- as.numeric(bl_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  can_check <- !is.null(dat) && is.data.frame(dat) && nrow(dat) > 0L &&
    !is.null(time_var) && nzchar(time_var) && !is.null(event_var) && nzchar(event_var)
  # ML assoc 等：允许 M1==M2 直接出表（发表用固定 VIF 协变量）
  allow_eq <- isTRUE(bl_cfg$allow_m2_eq_m1 %||% FALSE)

  .target_level <- function(d) {
    d$Group <- droplevels(d$Group)
    tail(levels(d$Group), 1L)
  }

  .fit_sig <- function(covars, d) {
    rhs <- unique(c("Group", covars))
    fml <- stats::as.formula(paste0(
      "Surv(", time_var, ", ", event_var, ") ~ ",
      paste(rhs, collapse = " + ")
    ))
    fit <- tryCatch(survival::coxph(fml, data = d), error = function(e) NULL)
    if (is.null(fit)) return(list(ok = FALSE, fit = NULL))
    tgt <- .target_level(d)
    ok <- cox_gate_check_sig(fit, tgt, p_thresh)
    list(ok = ok, fit = fit)
  }

  if (length(setdiff(m2, m1)) > 0L) {
    if (!can_check) return(list(M1 = m1, M2 = m2))
    chk <- .fit_sig(m2, dat)
    if (isTRUE(chk$ok)) return(list(M1 = m1, M2 = m2, model2_fit = chk$fit))
    # 结构已满足 M2 真超集 Model1：除非显式要求增量显著，否则保留既定 M1≠M2 出表
    require_extra_sig <- isTRUE(bl_cfg$require_model2_extra_sig %||% FALSE)
    if (!require_extra_sig || allow_eq) {
      cli::cli_alert_warning(
        "Cox: Model2 为 Model1 真超集，最高组不显著，仍按既定 M1≠M2 出表"
      )
      return(list(M1 = m1, M2 = m2, model2_fit = chk$fit))
    }
  }

  fb <- unique(as.character(m2_pool_extra)[nzchar(as.character(m2_pool_extra))])
  fb <- setdiff(fb, m1)
  if (!length(fb) && !is.null(ctx)) {
    harm_m2 <- as.character(ctx$results$Model2Factors %||% character(0))
    fb <- setdiff(harm_m2, m1)
  }
  if (!length(fb)) {
    if (allow_eq) {
      cli::cli_alert_warning(
        "Cox: Model2 与 Model1 相同（allow_m2_eq_m1=TRUE），继续出表: {paste(m1, collapse = ', ')}"
      )
      return(list(M1 = m1, M2 = if (length(m2)) m2 else m1))
    }
    stop(
      "COX_M2_EQ_M1: Model2 与 Model1 相同（", paste(m1, collapse = ", "),
      "），且无闸门 B 临床协变量可追加，已停止。",
      call. = FALSE
    )
  }

  if (can_check) {
    search_cfg <- bl_cfg$covariate_search %||% list()
    max_m2 <- as.integer(search_cfg$max_model2_attempts %||% 1000L)[1L]
    d <- dat
    d$Group <- droplevels(d$Group)
    target <- .target_level(d)
    m2_base <- unique(c("Group", m1))
    r2 <- cox_search_sig_covariate_combo(
      d, time_var, event_var, m2_base, fb,
      target, p_thresh, max_m2, min_subset_size = 1L
    )
    if (identical(r2$status, "ok")) {
      m2_out <- setdiff(r2$vars, "Group")
      if (length(setdiff(m2_out, m1)) > 0L) {
        cli::cli_alert_warning(
          "Cox: Model2 须多于 Model1 且显著，已选用: {paste(setdiff(m2_out, m1), collapse = ', ')}"
        )
        return(list(M1 = m1, M2 = m2_out, model2_fit = r2$fit))
      }
    }
    if (allow_eq) {
      cli::cli_alert_warning(
        "Cox: 无法扩展 Model2 且显著；allow_m2_eq_m1=TRUE，用 M1 出表"
      )
      return(list(M1 = m1, M2 = if (length(m2)) m2 else m1))
    }
    degrade <- as.character(bl_cfg$degrade_branch %||% "")[1L]
    on_fail <- as.character(search_cfg$on_search_fail %||% "degrade")[1L]
    if (!is.null(ctx) && identical(on_fail, "degrade") && nzchar(degrade)) {
      ctx$results$cox_branch <- degrade
      stop(
        "COX_M2_NOSIG_DEGRADE: 无法在 Model2 中同时满足「多于 Model1」与「最高组 P<", p_thresh,
        "」；已设 cox_branch=", degrade, "。",
        call. = FALSE
      )
    }
    stop(
      "COX_M2_NOSIG: 无法在 Model2 中同时满足「多于 Model1」与「最高组 P<", p_thresh,
      "」（候选: ", paste(fb, collapse = ", "), "），已停止。",
      call. = FALSE
    )
  }

  m2_out <- unique(c(m1, fb))
  cli::cli_alert_warning(
    "Cox 协变量：搜索后 Model2 与 Model1 相同，强制保留闸门 B 临床增量: {paste(setdiff(m2_out, m1), collapse = ', ')}"
  )
  list(M1 = m1, M2 = m2_out)
}

#' 校验 Model1 / Model2 最高组均显著；不满足时 degrade 或 stop
cox_require_both_models_sig <- function(ctx, bl_cfg, block_name, grouped_fits, group_levels) {
  if (!isTRUE(bl_cfg$require_both_models_sig %||% TRUE)) return(invisible(ctx))
  p_thresh <- as.numeric(bl_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  glv <- as.character(group_levels)
  if (!length(glv)) return(invisible(ctx))
  top_level <- glv[length(glv)]

  m1_fit <- grouped_fits$model1 %||% NULL
  m2_fit <- grouped_fits$model2 %||% NULL
  m1_p <- cox_gate_target_group_p(m1_fit, top_level)
  m2_p <- cox_gate_target_group_p(m2_fit, top_level)
  m1_sig <- cox_gate_check_sig(m1_fit, top_level, p_thresh)
  m2_sig <- cox_gate_check_sig(m2_fit, top_level, p_thresh)

  ctx$results$cox_model_sig_detail <- list(
    block = block_name,
    top_level = top_level,
    p_threshold = p_thresh,
    model1_p = m1_p,
    model2_p = m2_p,
    model1_sig = m1_sig,
    model2_sig = m2_sig
  )

  if (m1_sig && m2_sig) return(invisible(ctx))

  degrade <- as.character(bl_cfg$degrade_branch %||% "")[1L]
  on_fail <- as.character((bl_cfg$covariate_search %||% list())$on_search_fail %||% "degrade")[1L]
  ctx$results$cox_covariate_search_detail <- list(
    block = block_name,
    status = if (!m1_sig && !m2_sig) "both_models_ns" else if (!m1_sig) "model1_ns" else "model2_ns",
    model1_p = m1_p,
    model2_p = m2_p
  )
  if (identical(on_fail, "degrade") && nzchar(degrade)) {
    ctx$results$cox_branch <- degrade
    stop(
      "COX_BOTH_MODELS_SIG_DEGRADE: ", block_name,
      " — Model1 sig=", m1_sig, " (P=", format_p(m1_p), "), ",
      "Model2 sig=", m2_sig, " (P=", format_p(m2_p), ")；已设 cox_branch=", degrade, "。",
      call. = FALSE
    )
  }
  stop(
    "COX_BOTH_MODELS_SIG: ", block_name,
    " — Model1 sig=", m1_sig, " (P=", format_p(m1_p), "), ",
    "Model2 sig=", m2_sig, " (P=", format_p(m2_p), ")。",
    call. = FALSE
  )
}

format_p <- function(p) {
  if (is.null(p) || length(p) != 1L || !is.finite(p)) return("NA")
  format(round(p, 4), scientific = FALSE)
}

#' 搜索失败：默认 degrade（写 cox_branch）并 stop；无 degrade_branch 时硬 stop
cox_handle_search_fail <- function(ctx, bl_cfg, block_name, search_res) {
  search_cfg <- bl_cfg$covariate_search %||% list()
  on_fail <- as.character(search_cfg$on_search_fail %||% "degrade")[1L]
  degrade <- as.character(bl_cfg$degrade_branch %||% "")[1L]
  ctx$results$cox_covariate_search_detail <- list(
    block = block_name,
    status = search_res$status %||% "unknown",
    m1_attempts = search_res$m1_attempts %||% NA_integer_,
    m2_attempts = search_res$m2_attempts %||% NA_integer_
  )
  if (identical(on_fail, "degrade") && nzchar(degrade)) {
    ctx$results$cox_branch <- degrade
    stop(
      "COX_SEARCH_DEGRADE: ", block_name, " — ", search_res$status,
      "（Model1 尝试 ", search_res$m1_attempts %||% 0L,
      "，Model2 尝试 ", search_res$m2_attempts %||% 0L,
      "）；已设 cox_branch=", degrade, "，请继续 pipeline 下一分位块。",
      call. = FALSE
    )
  }
  stop(
    "COX_SEARCH_STOP: ", block_name, " — ", search_res$status,
    "（Model1 尝试 ", search_res$m1_attempts %||% 0L,
    "，Model2 尝试 ", search_res$m2_attempts %||% 0L, "）。",
    call. = FALSE
  )
}

#' Cox 分支 → 分位方案名（quartile / tertile / binary）
cox_gate_scheme_from_branch <- function(branch) {
  b <- tolower(as.character(branch %||% "")[1L])
  if (grepl("quartile", b, fixed = TRUE)) return("quartile")
  if (grepl("tertile", b, fixed = TRUE)) return("tertile")
  if (grepl("binary", b, fixed = TRUE)) return("binary")
  NA_character_
}

#' 双库统一分位时：当前 block 是否允许 extend（更粗分位则禁止 extend）
cox_gate_unified_blocks_extend <- function(ctx, block_scheme, model2_sig, extend_branch, degrade_branch) {
  if (!isTRUE(ctx$results$dual_db_cox_unified_locked %||% FALSE)) {
    if (isTRUE(model2_sig) && nzchar(extend_branch)) {
      return(list(branch = extend_branch, action = "extend"))
    }
    if (nzchar(degrade_branch)) return(list(branch = degrade_branch, action = "degrade"))
    return(list(branch = NA_character_, action = "none"))
  }
  target <- as.character(ctx$results$dual_db_cox_unified_scheme %||% "")[1L]
  if (!nzchar(target)) {
    if (isTRUE(model2_sig) && nzchar(extend_branch)) {
      return(list(branch = extend_branch, action = "extend"))
    }
    if (nzchar(degrade_branch)) return(list(branch = degrade_branch, action = "degrade"))
    return(list(branch = NA_character_, action = "none"))
  }
  td <- if (exists("logistic_gate_scheme_depth", mode = "function")) {
    logistic_gate_scheme_depth(target)
  } else 0L
  bd <- if (exists("logistic_gate_scheme_depth", mode = "function")) {
    logistic_gate_scheme_depth(block_scheme)
  } else 0L
  if (is.finite(bd) && is.finite(td) && bd < td) {
    if (nzchar(degrade_branch)) {
      return(list(branch = degrade_branch, action = "degrade_unified"))
    }
    return(list(branch = NA_character_, action = "none"))
  }
  if (isTRUE(model2_sig) && nzchar(extend_branch) && bd == td) {
    return(list(branch = extend_branch, action = "extend"))
  }
  if (nzchar(degrade_branch)) return(list(branch = degrade_branch, action = "degrade"))
  list(branch = NA_character_, action = "none")
}

#' 已锁定的扩展分支：后续 Cox 块不得覆盖 cox_branch
cox_gate_extend_branches <- function() {
  c("extend_quartile", "extend_tertile", "extend_binary")
}

#' 本 block 是否应直接跳过（四分位已成功扩展时不再跑三分位/二分 Cox）
cox_gate_block_is_redundant <- function(block_name, ctx) {
  branch <- if (exists("cox_gate_effective_branch", mode = "function")) {
    cox_gate_effective_branch(ctx)
  } else {
    as.character(ctx$results$cox_branch %||% "")[1L]
  }
  if (branch %in% c("extend_quartile", "extend_binary") &&
      block_name == "cox_tertile") {
    return(TRUE)
  }
  if (branch %in% c("extend_quartile", "extend_tertile") &&
      block_name == "cox_binary") {
    return(TRUE)
  }
  qg <- ctx$results$cox_quartile_gate %||% NULL
  if (block_name == "cox_tertile" && is.list(qg) && isTRUE(qg$model2_sig)) {
    return(TRUE)
  }
  FALSE
}

#' 当前生效的 Cox 分支（双库统一分位锁定时优先用统一方案）
cox_gate_effective_branch <- function(ctx) {
  if (isTRUE(ctx$results$dual_db_cox_unified_locked %||% FALSE)) {
    sch <- as.character(ctx$results$dual_db_cox_unified_scheme %||% "")[1L]
    if (nzchar(sch)) return(paste0("extend_", sch))
  }
  as.character(ctx$results$cox_branch %||% "")[1L]
}

#' Cox 分组表跑完后应用闸门（gate_enable=FALSE 时无操作）
cox_gate_apply_after_grouped <- function(ctx, bl_cfg, grouped_fits, group_levels) {
  if (!isTRUE(bl_cfg$gate_enable %||% FALSE)) {
    return(ctx)
  }
  unified_scheme <- if (isTRUE(ctx$results$dual_db_cox_unified_locked %||% FALSE)) {
    as.character(ctx$results$dual_db_cox_unified_scheme %||% "")[1L]
  } else ""
  existing <- as.character(ctx$results$cox_branch %||% "")[1L]
  if (nzchar(existing) && existing %in% cox_gate_extend_branches()) {
    keep_existing <- TRUE
    if (nzchar(unified_scheme)) {
      ex_d <- logistic_gate_scheme_depth(cox_gate_scheme_from_branch(existing))
      uni_d <- logistic_gate_scheme_depth(unified_scheme)
      if (is.finite(ex_d) && is.finite(uni_d) && ex_d < uni_d) {
        keep_existing <- FALSE
      }
    }
    if (keep_existing) {
      cli::cli_alert_info("cox_gate: 保留已有扩展分支 {.val {existing}}，本块不更新 cox_branch")
      return(ctx)
    }
  }
  p_thresh <- as.numeric(bl_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05

  glv <- as.character(group_levels)
  if (!length(glv)) {
    cli::cli_alert_warning("cox_gate: 无分组水平，跳过闸门。")
    return(ctx)
  }
  top_level <- glv[length(glv)]

  crude_fit <- grouped_fits$crude %||% NULL
  model2_fit <- grouped_fits$model2 %||% NULL
  crude_p <- cox_gate_target_group_p(crude_fit, top_level)
  model2_p <- cox_gate_target_group_p(model2_fit, top_level)

  crude_sig <- cox_gate_check_sig(crude_fit, top_level, p_thresh)
  model1_sig <- cox_gate_check_sig(grouped_fits$model1 %||% NULL, top_level, p_thresh)
  model2_sig <- cox_gate_check_sig(model2_fit, top_level, p_thresh)
  model1_p <- cox_gate_target_group_p(grouped_fits$model1 %||% NULL, top_level)

  if (!crude_sig && isTRUE(bl_cfg$stop_if_crude_highest_ns %||% TRUE)) {
    stop(
      "cox_gate: Crude 最高组 ", top_level, " P=",
      if (is.na(crude_p)) "NA" else format(round(crude_p, 4), scientific = FALSE),
      " >= ", p_thresh, "，分析终止。",
      call. = FALSE
    )
  }

  extend_branch <- as.character(bl_cfg$extend_branch %||% "")[1L]
  degrade_branch <- as.character(bl_cfg$degrade_branch %||% "")[1L]
  block_scheme <- cox_gate_scheme_from_branch(extend_branch %||% degrade_branch)

  gate_out <- cox_gate_unified_blocks_extend(
    ctx, block_scheme, model2_sig, extend_branch, degrade_branch
  )
  if (nzchar(gate_out$branch %||% "")) {
    ctx$results$cox_branch <- gate_out$branch
    if (identical(gate_out$action, "extend")) {
      cli::cli_alert_success("cox_gate: Model2 最高组 {top_level} 显著 → {gate_out$branch}")
    } else if (identical(gate_out$action, "degrade_unified")) {
      cli::cli_alert_info(
        "cox_gate: 双库统一分位 {ctx$results$dual_db_cox_unified_scheme}，{block_scheme} 不 extend → {gate_out$branch}"
      )
    } else {
      cli::cli_alert_info("cox_gate: Model2 最高组 {top_level} 不显著 → {gate_out$branch}")
    }
  }

  ctx$results$cox_gate_detail <- list(
    top_level = top_level,
    p_threshold = p_thresh,
    crude_p = crude_p,
    model1_p = model1_p,
    model2_p = model2_p,
    crude_sig = crude_sig,
    model1_sig = model1_sig,
    model2_sig = model2_sig,
    branch = ctx$results$cox_branch %||% NA_character_
  )
  ctx
}

#' pipeline 是否跳过该 block（须 pipeline$cox_gate$enable = TRUE 且已有 cox_branch）
pipeline_cox_gate_should_skip <- function(block_name, ctx, pipeline) {
  gate_cfg <- pipeline$cox_gate %||% list()
  if (!isTRUE(gate_cfg$enable)) return(FALSE)

  if (exists("cox_gate_block_is_redundant", mode = "function") &&
      cox_gate_block_is_redundant(block_name, ctx)) {
    return(TRUE)
  }

  branch <- if (exists("cox_gate_effective_branch", mode = "function")) {
    cox_gate_effective_branch(ctx)
  } else {
    as.character(ctx$results$cox_branch %||% "")[1L]
  }
  if (!nzchar(branch)) return(FALSE)

  # plot_cutoff 已停产（enable=FALSE）；切点以 RCS 为准，不再出 maxstat 图
  # segmented_cox_binary 不随闸门跳过：分段 Cox 统一用 RCS primary cutoff（单切点两段），
  # 不再按 Cox 分位分支产出 segmented_cox_quartile/tertile（旧规则，已废弃）。
  skip_by_branch <- list(
    extend_quartile = c(
      "cox_tertile", "cox_binary",
      "segmented_cox_quartile", "segmented_cox_tertile", "km_binary"
    ),
    degrade_tertile = c(
      "rcs_prognosis", "km_strata", "segmented_cox_quartile",
      "cox_binary", "segmented_cox_tertile",
      "km_binary", "segmented_cox_binary", "subgroup_prognosis"
    ),
    extend_tertile = c(
      "cox_tertile", "cox_binary",
      "segmented_cox_quartile", "km_binary"
    ),
    degrade_binary = c(
      "rcs_prognosis", "km_strata",
      "segmented_cox_quartile", "segmented_cox_tertile",
      "km_binary", "segmented_cox_binary", "subgroup_prognosis"
    ),
    extend_binary = c(
      "cox_quartile", "cox_tertile",
      "km_strata", "segmented_cox_quartile", "segmented_cox_tertile"
    )
  )

  skip_list <- skip_by_branch[[branch]] %||% character(0)
  isTRUE(block_name %in% skip_list)
}

# ── Gate C 后双库联合剪枝：共用 Model2 子集，使两库最高档 M2+M3 均显著 ──

cox_dual_severity_drop_priority <- function() {
  c("SOFA", "GCS", "OASIS", "APSIII", "SAPSII", "SIRS", "Charlson",
    "Ventilation", "CRRT", "Lactate")
}

#' 把优先删除的重症评分放到向量末尾，递减枚举时先丢掉它们
cox_dual_order_extras_for_prune <- function(extras) {
  extras <- unique(as.character(extras)[nzchar(as.character(extras))])
  pri <- cox_dual_severity_drop_priority()
  c(setdiff(extras, pri), intersect(pri, extras))
}

cox_prepare_grouped_data_for_scheme <- function(ctx, cfg, index_var, scheme) {
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.data.frame(data)) return(NULL)
  surv_cfg <- cfg$survival %||% list()
  time_var <- as.character(surv_cfg$time_var %||% "futime")[1L]
  event_var <- as.character(surv_cfg$event_var %||% "fustatus")[1L]
  index_var <- as.character(index_var %||% "")[1L]
  scheme <- tolower(as.character(scheme %||% "quartile")[1L])
  need <- c(time_var, event_var, index_var)
  if (any(!need %in% names(data))) return(NULL)
  dt <- data
  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  if (is.character(dt[[event_var]]) || is.factor(dt[[event_var]])) {
    if (is.null(disease_label) || !nzchar(as.character(disease_label)[1L])) return(NULL)
    dt[[event_var]] <- ifelse(dt[[event_var]] == disease_label, 1, 0)
  }
  dt[[event_var]] <- as.numeric(dt[[event_var]])
  x <- suppressWarnings(as.numeric(dt[[index_var]]))
  if (identical(scheme, "tertile")) {
    qs <- as.numeric(stats::quantile(x, probs = c(0, 1 / 3, 2 / 3, 1), na.rm = TRUE))
    dt$Group <- cut(x, breaks = qs, include.lowest = TRUE, labels = c("Q1", "Q2", "Q3"))
  } else if (identical(scheme, "binary")) {
    med <- stats::median(x, na.rm = TRUE)
    dt$Group <- factor(ifelse(x < med, "low", "high"), levels = c("low", "high"))
  } else {
    qs <- as.numeric(stats::quantile(x, na.rm = TRUE))
    if (exists("pipeline_quartile_factor", mode = "function")) {
      dt$Group <- pipeline_quartile_factor(x, breaks = qs)
    } else {
      dt$Group <- cut(x, breaks = qs, include.lowest = TRUE,
                      labels = c("Q1", "Q2", "Q3", "Q4"))
    }
  }
  dt$Group <- droplevels(factor(dt$Group))
  keep <- stats::complete.cases(dt[, c(time_var, event_var, index_var, "Group"), drop = FALSE])
  dt <- dt[keep, , drop = FALSE]
  if (nrow(dt) < 20L || nlevels(dt$Group) < 2L) return(NULL)
  dt$Num <- as.numeric(dt$Group)
  list(
    dt = dt, time_var = time_var, event_var = event_var,
    target = as.character(tail(levels(dt$Group), 1L))
  )
}

cox_highest_group_p_for_covs <- function(prep, covs) {
  if (is.null(prep) || is.null(prep$dt)) return(NA_real_)
  covs <- unique(as.character(covs)[nzchar(as.character(covs))])
  covs <- intersect(covs, names(prep$dt))
  rhs <- unique(c("Group", covs))
  fml <- stats::as.formula(paste0(
    "Surv(", prep$time_var, ", ", prep$event_var, ") ~ ",
    paste(rhs, collapse = " + ")
  ))
  fit <- tryCatch(survival::coxph(fml, data = prep$dt), error = function(e) NULL)
  cox_gate_target_group_p(fit, prep$target, group_var = "Group")
}

cox_trend_p_for_covs <- function(prep, covs) {
  if (is.null(prep) || is.null(prep$dt)) return(NA_real_)
  dt <- prep$dt
  if (!"Num" %in% names(dt)) dt$Num <- as.numeric(dt$Group)
  covs <- unique(as.character(covs)[nzchar(as.character(covs))])
  covs <- intersect(covs, names(dt))
  rhs <- unique(c("Num", covs))
  fml <- stats::as.formula(paste0(
    "Surv(", prep$time_var, ", ", prep$event_var, ") ~ ",
    paste(rhs, collapse = " + ")
  ))
  fit <- tryCatch(survival::coxph(fml, data = dt), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  smry <- tryCatch(summary(fit), error = function(e) NULL)
  if (is.null(smry)) return(NA_real_)
  coef_mat <- smry$coefficients
  if (!"Num" %in% rownames(coef_mat)) return(NA_real_)
  as.numeric(coef_mat["Num", "Pr(>|z|)"])
}

cox_dual_model3_for_m2 <- function(m2, cfg, cols, index_var) {
  m2 <- unique(as.character(m2)[nzchar(as.character(m2))])
  m2 <- intersect(m2, cols)
  if (!exists("pipeline_resolve_model3_factors", mode = "function")) return(m2)
  m3 <- tryCatch(
    pipeline_resolve_model3_factors(m2, cfg, cols, index_var),
    error = function(e) m2
  )
  if (!length(m3)) m2 else unique(as.character(m3))
}

#' 两库 Table 2 关键 p：最高档 +（可选）p for trend，Model2 与 Model3
cox_dual_candidate_pmax <- function(prepared, m2, cfg, index_var,
                                    require_trend = TRUE) {
  m2 <- unique(as.character(m2)[nzchar(as.character(m2))])
  ps <- numeric(0)
  for (prep in prepared) {
    if (is.null(prep)) return(Inf)
    cols <- names(prep$dt)
    m2u <- intersect(m2, cols)
    p2h <- cox_highest_group_p_for_covs(prep, m2u)
    if (!is.finite(p2h)) return(Inf)
    ps <- c(ps, p2h)
    if (isTRUE(require_trend)) {
      p2t <- cox_trend_p_for_covs(prep, m2u)
      if (!is.finite(p2t)) return(Inf)
      ps <- c(ps, p2t)
    }
    m3 <- cox_dual_model3_for_m2(m2u, cfg, cols, index_var)
    if (!identical(sort(m3), sort(m2u))) {
      p3h <- cox_highest_group_p_for_covs(prep, m3)
      if (!is.finite(p3h)) return(Inf)
      ps <- c(ps, p3h)
      if (isTRUE(require_trend)) {
        p3t <- cox_trend_p_for_covs(prep, m3)
        if (!is.finite(p3t)) return(Inf)
        ps <- c(ps, p3t)
      }
    }
  }
  max(ps)
}

cox_dual_candidate_m2_m3_highest_sig <- function(prepared, m2, cfg, index_var,
                                                 p_threshold = 0.05,
                                                 require_trend = TRUE) {
  p_threshold <- as.numeric(p_threshold %||% 0.05)[1L]
  if (!is.finite(p_threshold)) p_threshold <- 0.05
  pmax <- cox_dual_candidate_pmax(
    prepared, m2, cfg, index_var, require_trend = require_trend
  )
  is.finite(pmax) && pmax < p_threshold
}

cox_dual_unique_subsets <- function(lst) {
  lst <- lst[vapply(lst, function(x) length(as.character(x)) > 0L, logical(1L))]
  if (!length(lst)) return(list())
  keys <- vapply(lst, function(x) paste(sort(as.character(x)), collapse = "\x01"), "")
  lst[!duplicated(keys)]
}

cox_dual_prune_subsets <- function(extras) {
  extras <- unique(as.character(extras)[nzchar(as.character(extras))])
  pri <- intersect(cox_dual_severity_drop_priority(), extras)
  labs <- setdiff(extras, pri)
  decreasing <- function(v) {
    if (!length(v)) return(list())
    if (exists("covariate_subsets_decreasing_from_full", mode = "function")) {
      covariate_subsets_decreasing_from_full(v)
    } else {
      list(v)
    }
  }
  out <- list()
  if (length(labs) && length(pri)) out <- c(out, list(labs), decreasing(labs))
  out <- c(out, decreasing(extras))
  cox_dual_unique_subsets(out)
}

#' 在 Gate B 锁定的 Model2 池内找两库共用子集：
#' 两库最高档与 p for trend 的 Model2/Model3 均 p<0.05。
#' 命中多个子集时取「最差 p 最小」者，并优先丢掉重症评分。
cox_prune_dual_highest_group <- function(prepared, m1, m2, cfg, index_var,
                                         p_threshold = 0.05,
                                         require_trend = TRUE) {
  m1 <- unique(as.character(m1)[nzchar(as.character(m1))])
  m2 <- unique(as.character(m2)[nzchar(as.character(m2))])
  if (!length(m1)) m1 <- "Age"
  extras <- cox_dual_order_extras_for_prune(setdiff(m2, m1))
  full <- unique(c(m1, extras))
  out_keep <- function(reason) {
    list(M1 = m1, M2 = full, pruned = FALSE, dropped = character(0), reason = reason)
  }
  if (!length(prepared) || any(vapply(prepared, is.null, logical(1L)))) {
    return(out_keep("prepare_fail"))
  }
  if (!length(extras)) return(out_keep("no_extras"))
  p_threshold <- as.numeric(p_threshold %||% 0.05)[1L]
  if (!is.finite(p_threshold)) p_threshold <- 0.05
  pri <- cox_dual_severity_drop_priority()

  score_one <- function(S, req_tr) {
    cand <- unique(c(m1, as.character(S)))
    pmax <- cox_dual_candidate_pmax(
      prepared, cand, cfg, index_var, require_trend = req_tr
    )
    dropped <- setdiff(extras, as.character(S))
    list(
      S = as.character(S), cand = cand, pmax = pmax,
      n_sev = length(intersect(dropped, pri)), dropped = dropped
    )
  }
  pick_best <- function(req_tr) {
    subsets <- cox_dual_prune_subsets(extras)
    best <- NULL
    for (S in subsets) {
      sc <- score_one(S, req_tr)
      if (!is.finite(sc$pmax) || sc$pmax >= p_threshold) next
      if (is.null(best) ||
          sc$pmax < best$pmax - 1e-12 ||
          (abs(sc$pmax - best$pmax) < 1e-12 && sc$n_sev > best$n_sev)) {
        best <- sc
      }
    }
    best
  }

  best <- pick_best(isTRUE(require_trend))
  used_trend <- isTRUE(require_trend)
  if (is.null(best) && isTRUE(require_trend)) {
    cli::cli_alert_warning(
      "Gate C 双库剪枝：无子集使两库最高档+趋势均显著，改只卡最高档并尽量降低趋势 p"
    )
    subsets <- cox_dual_prune_subsets(extras)
    best_fb <- NULL
    for (S in subsets) {
      sc_h <- score_one(S, FALSE)
      if (!is.finite(sc_h$pmax) || sc_h$pmax >= p_threshold) next
      sc_t <- cox_dual_candidate_pmax(
        prepared, sc_h$cand, cfg, index_var, require_trend = TRUE
      )
      sc_h$trend_p <- if (is.finite(sc_t)) sc_t else Inf
      if (is.null(best_fb) ||
          sc_h$trend_p < best_fb$trend_p - 1e-12 ||
          (abs(sc_h$trend_p - best_fb$trend_p) < 1e-12 && sc_h$n_sev > best_fb$n_sev)) {
        best_fb <- sc_h
      }
    }
    best <- best_fb
    used_trend <- FALSE
  }
  if (is.null(best)) {
    cli::cli_alert_warning(
      "Gate C 双库剪枝：Gate B 池内无共用子集使两库最高档 Model2+Model3 均显著，保留全集"
    )
    return(out_keep("no_subset"))
  }
  full_p <- cox_dual_candidate_pmax(
    prepared, full, cfg, index_var, require_trend = used_trend
  )
  if (identical(sort(best$cand), sort(full)) && is.finite(full_p) && full_p < p_threshold) {
    return(list(M1 = m1, M2 = full, pruned = FALSE, dropped = character(0), reason = "full_ok"))
  }
  tr_lab <- if (used_trend) "最高档+趋势" else "最高档"
  cli::cli_alert_success(
    "Gate C 双库剪枝：两库 {tr_lab} Model2/Model3 均显著（最差 p={round(best$pmax, 4)}）；删除 {paste(best$dropped, collapse = ', ')}"
  )
  list(
    M1 = m1, M2 = best$cand, pruned = TRUE, dropped = best$dropped,
    reason = if (used_trend) "pruned" else "pruned_highest_only",
    pmax = best$pmax
  )
}
