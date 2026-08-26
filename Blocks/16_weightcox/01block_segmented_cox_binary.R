###############################################################################
#  segmented_cox_binary — RCS/ROC cutoff 将 index 二分两段；每段内 mean/median 再二分 index，
#                          拟合分层 Cox 得 Table S4 两行 HR；全样本连续 index + 同一套协变量
#                          做 segmented::segmented() log-likelihood 检验。
#                          不含 cutoff 图、KM、二次 baseline RData（见 block_weightcox_plot_KM.R）。
#                          2026-08-21 起：预后双库项目分段 Cox 统一走本块（单切点两段，
#                          切点 = RCS primary cutoff），不再用分位数外层分段 / maxstat 图。
#
#  register_block: "segmented_cox_binary"
#  典型流水线: … → multicollinearity → 10_cox → 15_rcs → segmented_cox_binary → [weightcox 图/KM]
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  时间/事件/暴露      = config$survival$time_var / event_var / index_var
#  cutoff（外层 2 段） = run_block 参数 > config$cutoff > ctx$results$cutoff_value(15_rcs)
#                        > ctx$results$roc_summary$cutoff(13_roc) > ctx$results$nhanes_cutoff
#                        > cutoff_file > RCS 块目录 cutoff_<index>.txt
#                        > maxstat(surv_cutpoint) 自算（仅 maxstat_fallback=TRUE 时；默认关）
#  HR 方向 anchor      = ctx$results$cox_highest_group_model2_hr（10_cox Model2 最高组）；
#                        无有效 HR 时 require_hr_direction="auto" 下不卡方向
#  协变量池（搜索用）  = random_covariate_search$pool 或 ctx$results$Model2Factors
#
#  # ── 配置 config$segmented_cox_binary（可 fallback config$weightcox）──────────
#  segmented_cox_binary = list(
#    cutoff             = NULL,    # 手动 cutoff；NULL → 上游 RCS / ROC / maxstat
#    cutoff_file        = NULL,    # 一行数值的 cutoff 文本路径
#    roc_cutoff_row     = NULL,    # list(model=..., dataset=...) 从 roc_summary 选行
#    maxstat_fallback   = FALSE,   # 默认关；切点必须来自 RCS
#    maxstat_minprop    = 0.2,     # 仅 maxstat_fallback=TRUE 时使用
#    cutoff_scan_range  = 0,       # 默认不扫描；切点=RCS，不得为凑显著偏移
#    cutoff_scan_step   = 0.01,
#    min_segment_n      = 20,      # 每层最少样本
#    min_segment_events = 5,       # 每层最少事件数
#    split_within_stratum = "median",  # 层内 index 二分："mean" | "median"
#    covariates         = NULL,    # 固定协变量；默认回退 Model2Factors（与 Table 2 一致）
#    sig_cutoff         = 0.05,    # 无固定/搜索协变量时，单因素 Cox 筛 P 阈值
#    segmented_extra_covariates = NULL,  # 仅追加到 segmented()；NULL=与分层 Cox 同协变量
#    table_caption      = NULL,    # NULL → "Segmented Cox of <index> and <disease>"
#    table_filename     = NULL,    # NULL → pub 编号（supp_table）自动命名
#    random_covariate_search = list(
#      enable                    = FALSE,  # 2026-08-19 起默认关：协变量=Table 2 Model2Factors，不随机凑显著
#      require_hr_direction      = "auto",  # auto|none；auto=有 10_cox anchor 才卡 HR 方向
#      max_outer_attempts        = 1000L,   # 外层循环：未命中则 factors_Num+1
#      max_inner_attempts        = 1000L,   # 内层循环：随机抽协变量组合
#      initial_factors_n         = 1L,      # 每次抽样协变量个数起点
#      progress_every            = 50L,
#      pool                      = NULL,    # NULL → Model2Factors
#      high_stratum_p_max        = 0.05,    # 搜索/扫描：仅判 ≥cutoff 段（最高外层段）
#      high_stratum_min_hr       = 1,       # anchor 无效且非 p_only 时 HR 下限
#      both_strata_significance_use_p_only = FALSE,  # TRUE=搜索时不卡 HR 方向
#      seed                      = NULL,
#      save_sampled_csv          = TRUE,
#      use_sampled_covariates    = TRUE
#    ),
#    pause_enable               = TRUE,
#    pause_on_no_data           = TRUE,
#    pause_on_no_cutoff         = TRUE,
#    pause_on_high_stratum_fail = FALSE
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$segmented_cox_binary, ctx$results$segmented_cox（兼容别名）
#      Tables/Table S#. Segmented Cox of <index> and <disease>.xlsx（pub 自动编号）
#      表注：段内 median split 口径 + LLR 口径 + 切点来源（RCS primary cutoff）
#      Segmented_Cox_binary_sampled_covariates.csv（搜索命中时）
#  不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
#
#  源: C01_segmented_Cox 脚本（双层 while 搜索 + Table S4）；依赖 survival, segmented
###############################################################################

.scb01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.scb01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "segmented_cox_binary",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: segmented_cox_binary — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.scb01_coerce_event_01 <- function(x, cfg, evname) {
  if (is.numeric(x)) {
    if (all(is.na(x))) return(as.numeric(x))
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
    stop("segmented_cox_binary: ", evname, " 为数值但非 0/1 编码")
  }
  if (is.logical(x)) return(as.integer(x))
  ana_lbl <- trimws(cfg$project$analysis_group %||% "")
  if (!nzchar(ana_lbl)) {
    stop("segmented_cox_binary: 字符型 ", evname, " 需 config$project$analysis_group")
  }
  xc <- trimws(as.character(x))
  out <- rep(NA_integer_, length(xc))
  not_na <- !is.na(xc) & nzchar(xc)
  is_event <- not_na & (xc == ana_lbl | tolower(xc) == tolower(ana_lbl))
  out[is_event] <- 1L
  out[not_na & !is_event] <- 0L
  out
}

.scb01_regex_escape <- function(x) {
  gsub("([][{}()^$.|?*+\\\\])", "\\\\\\1", x, perl = TRUE)
}

.scb01_extract_high_vs_low <- function(fit, index_var) {
  if (is.null(fit)) return(NULL)
  b <- tryCatch(stats::coef(fit), error = function(e) NULL)
  if (is.null(b) || length(b) < 1L) return(NULL)
  nm <- names(b)
  if (is.null(nm)) nm <- paste0("coef", seq_along(b))
  esc <- .scb01_regex_escape(index_var)
  pick_row <- function(rn) {
    ig <- grep(paste0("^", esc, "high$"), rn, ignore.case = TRUE, perl = TRUE)[1L]
    if (is.na(ig)) ig <- grep(paste0("^", esc, ".+high$"), rn, ignore.case = TRUE, perl = TRUE)[1L]
    if (is.na(ig)) ig <- grep("high$", rn, ignore.case = TRUE, perl = TRUE)[1L]
    if (is.na(ig)) ig <- grep("high", rn, ignore.case = TRUE, perl = TRUE)[1L]
    if (is.na(ig) && length(rn) == 1L) ig <- 1L
    if (is.na(ig)) NA_integer_ else as.integer(ig)
  }
  ig <- pick_row(nm)
  if (is.na(ig)) return(NULL)
  cname <- nm[ig]
  from_wald <- function() {
    V <- tryCatch(stats::vcov(fit), error = function(e) NULL)
    if (is.null(V)) return(NULL)
    ii <- match(cname, rownames(V))
    if (is.na(ii)) return(NULL)
    se <- suppressWarnings(sqrt(V[ii, ii]))
    beta <- as.numeric(b[ig])
    if (!is.finite(beta) || !is.finite(se) || se <= 0) return(NULL)
    z <- stats::qnorm(0.975)
    list(
      hr = exp(beta),
      ci_lo = exp(beta - z * se),
      ci_hi = exp(beta + z * se),
      p = 2 * stats::pnorm(-abs(beta / se))
    )
  }
  # conf.int must be numeric (0.95); TRUE coerces to 1 → 100% CI → (0, Inf)
  s <- tryCatch(summary(fit, conf.int = 0.95), error = function(e) NULL)
  if (!is.null(s) && !is.null(s$coefficients) && nrow(s$coefficients) >= 1L) {
    co <- s$coefficients
    ci <- s$conf.int
    rn <- rownames(co)
    ig2 <- pick_row(rn)
    if (!is.na(ig2)) {
      ig_ci <- ig2
      if (!is.null(rownames(ci)) && rn[ig2] %in% rownames(ci)) {
        ig_ci <- match(rn[ig2], rownames(ci))[1L]
      }
      pcol <- grep("^Pr\\(", colnames(co), perl = TRUE)[1L]
      if (is.na(pcol)) pcol <- ncol(co)
      hr_col <- grep("exp\\(coef\\)", colnames(ci), perl = TRUE)[1L]
      lo_col <- grep("lower", colnames(ci), perl = TRUE)[1L]
      hi_col <- grep("upper", colnames(ci), perl = TRUE)[1L]
      if (is.na(hr_col)) hr_col <- 1L
      if (is.na(lo_col)) lo_col <- min(3L, ncol(ci))
      if (is.na(hi_col)) hi_col <- min(4L, ncol(ci))
      hr <- ci[ig_ci, hr_col, drop = TRUE]
      lo <- ci[ig_ci, lo_col, drop = TRUE]
      hi <- ci[ig_ci, hi_col, drop = TRUE]
      pv <- co[ig2, pcol, drop = TRUE]
      if (all(is.finite(c(hr, lo, hi)))) {
        return(list(
          hr = round(as.numeric(hr), 3),
          ci_lo = round(as.numeric(lo), 3),
          ci_hi = round(as.numeric(hi), 3),
          p = if (is.finite(pv)) round(as.numeric(pv), 4) else NA_real_
        ))
      }
    }
  }
  w <- from_wald()
  if (is.null(w)) return(NULL)
  list(
    hr = round(w$hr, 3),
    ci_lo = round(w$ci_lo, 3),
    ci_hi = round(w$ci_hi, 3),
    p = if (is.finite(w$p)) round(as.numeric(w$p), 4) else NA_real_
  )
}

.scb01_dichotomize_index <- function(v, split_mode) {
  split_mode <- tolower(as.character(split_mode)[1L])
  if (!split_mode %in% c("mean", "median")) split_mode <- "mean"
  split_fun <- if (identical(split_mode, "median")) stats::median else base::mean
  ok <- is.finite(v)
  if (sum(ok) < 2L) return(rep(NA_character_, length(v)))
  spl <- split_fun(v[ok], na.rm = TRUE)
  bin <- ifelse(!ok, NA_character_, ifelse(v >= spl, "high", "low"))
  if (length(unique(stats::na.omit(bin))) >= 2L) return(bin)
  r <- rank(v, ties.method = "average", na.last = "keep")
  mr <- stats::median(r[ok], na.rm = TRUE)
  bin2 <- ifelse(!ok, NA_character_, ifelse(r > mr, "high", "low"))
  bin2
}

.scb01_cox_stratum_extract <- function(tmp, idx, time_v, event_v, fac_vec, split_mode) {
  if (nrow(tmp) < 2L) return(NULL)
  tmp[[idx]] <- .scb01_dichotomize_index(tmp[[idx]], split_mode)
  tmp[[idx]] <- factor(tmp[[idx]], levels = c("low", "high"))
  if (nlevels(droplevels(tmp[[idx]])) < 2L) return(NULL)
  fac_vec <- unique(intersect(as.character(fac_vec), names(tmp)))
  rhs <- if (length(fac_vec)) paste(fac_vec, collapse = " + ") else NULL
  fml <- if (!is.null(rhs)) {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx, " + ", rhs))
  } else {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx))
  }
  fml0 <- stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx))
  .safe_coxph <- function(formula_obj, dat) {
    bad_warn <- FALSE
    fit <- tryCatch(
      withCallingHandlers(
        survival::coxph(formula_obj, data = dat),
        warning = function(w) {
          msg <- conditionMessage(w)
          if (grepl("coefficient may be infinite|did not converge|singular|infinite", msg, ignore.case = TRUE)) {
            bad_warn <<- TRUE
          }
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) NULL
    )
    if (isTRUE(bad_warn)) return(NULL)
    fit
  }
  use_cols <- unique(c(time_v, event_v, idx, fac_vec))
  tmp <- stats::na.omit(tmp[, use_cols, drop = FALSE])
  o <- .safe_coxph(fml, tmp)
  ex <- .scb01_extract_high_vs_low(o, idx)
  if (!is.null(ex)) return(ex)
  o0 <- .safe_coxph(fml0, tmp)
  .scb01_extract_high_vs_low(o0, idx)
}

.scb01_run_binary_strata <- function(dat, idx, cut, fac_vec, time_v, event_v, split_mode,
                                     min_n, min_ev) {
  tmp1 <- dat[dat[[idx]] < cut, , drop = FALSE]
  tmp2 <- dat[dat[[idx]] >= cut, , drop = FALSE]
  n_ev1 <- sum(tmp1[[event_v]] == 1L, na.rm = TRUE)
  n_ev2 <- sum(tmp2[[event_v]] == 1L, na.rm = TRUE)
  if (nrow(tmp1) < min_n || nrow(tmp2) < min_n || n_ev1 < min_ev || n_ev2 < min_ev) {
    return(list(low = NULL, high = NULL))
  }
  list(
    low = .scb01_cox_stratum_extract(tmp1, idx, time_v, event_v, fac_vec, split_mode),
    high = .scb01_cox_stratum_extract(tmp2, idx, time_v, event_v, fac_vec, split_mode)
  )
}

.scb01_parse_cox_hr_anchor <- function(rt_df, top_level) {
  if (is.null(rt_df) || !nrow(rt_df)) return(NA_real_)
  df <- as.data.frame(rt_df, stringsAsFactors = FALSE)
  if (ncol(df) < 10L) return(NA_real_)
  c1 <- trimws(as.character(df[[1L]]))
  idx <- which(c1 == as.character(top_level))
  if (!length(idx)) return(NA_real_)
  hr <- suppressWarnings(as.numeric(df[[10L]][idx[1L]]))
  if (is.finite(hr)) hr else NA_real_
}

.scb01_resolve_anchor_hr <- function(ctx) {
  raw <- ctx$results$cox_highest_group_model2_hr
  hr <- suppressWarnings(as.numeric(if (length(raw)) raw[[1L]] else NA_real_))
  if (length(hr) == 1L && is.finite(hr)) {
    return(list(hr = hr, level = ctx$results$cox_highest_group_level %||% NA_character_))
  }
  cg <- ctx$results$cox_grouping %||% NULL
  rt <- ctx$results$cox_hr
  if (is.null(cg) || is.null(rt)) return(list(hr = NA_real_, level = NA_character_))
  glv <- cg$group_levels
  if (is.null(glv) || length(glv) < 2L) return(list(hr = NA_real_, level = NA_character_))
  top <- glv[length(glv)]
  hr2 <- .scb01_parse_cox_hr_anchor(rt, top)
  list(hr = hr2, level = top)
}

.scb01_hr_direction_ok <- function(hr, anchor_hr, rs_cfg) {
  req_mode <- tolower(as.character(rs_cfg$require_hr_direction %||% "auto")[1L])
  if (identical(req_mode, "none")) return(TRUE)
  anchor_hr <- suppressWarnings(as.numeric(anchor_hr[1L]))
  use_anchor <- is.finite(anchor_hr) && abs(anchor_hr - 1) > 1e-8
  if (identical(req_mode, "auto") && !use_anchor) return(TRUE)
  if (!is.finite(hr)) return(FALSE)
  if (use_anchor) {
    if (anchor_hr > 1) return(hr > 1)
    return(hr < 1)
  }
  min_hr <- as.numeric(rs_cfg$high_stratum_min_hr %||% 1)
  hr > min_hr
}

.scb01_stratum_p_ok <- function(r, p_cut) {
  !is.null(r) && is.finite(r$p) && r$p < p_cut
}

.scb01_highest_stratum_ok <- function(sr, p_cut, anchor_hr, rs_cfg) {
  rh <- sr$high
  if (!.scb01_stratum_p_ok(rh, p_cut)) return(FALSE)
  p_only <- isTRUE(rs_cfg$both_strata_significance_use_p_only %||% FALSE)
  if (isTRUE(p_only)) return(TRUE)
  .scb01_hr_direction_ok(rh$hr, anchor_hr, rs_cfg)
}

.scb01_nested_covariate_search <- function(dat, idx, cut, time_v, event_v, pool_rs, rs_cfg,
                                           min_n, min_ev, split_mode, anchor_hr) {
  max_outer <- as.integer(rs_cfg$max_outer_attempts %||% 1000L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 1000L)
  factors_num <- max(1L, as.integer(rs_cfg$initial_factors_n %||% 1L))
  p_max <- as.numeric(rs_cfg$high_stratum_p_max %||% 0.05)
  progress_every <- max(1L, as.integer(rs_cfg$progress_every %||% 50L))
  sd <- rs_cfg$seed %||% NULL
  if (!is.null(sd)) set.seed(as.integer(sd))

  pool_rs <- unique(intersect(as.character(pool_rs), names(dat)))
  if (length(pool_rs) < 1L) return(NULL)

  cli::cli_alert_info(
    "segmented_cox_binary 随机搜索：outer={max_outer}，inner={max_inner}，factors_Num 递增"
  )

  attempt_count <- 0L
  exit_outer <- FALSE
  best <- NULL

  while (attempt_count < max_outer && !exit_outer) {
    inner_count <- 0L
    condition_met <- FALSE
    k_use <- min(factors_num, length(pool_rs))

    while (inner_count < max_inner && !condition_met) {
      sample_factors <- sample(pool_rs, k_use, replace = FALSE)
      sr <- .scb01_run_binary_strata(
        dat, idx, cut, sample_factors, time_v, event_v, split_mode, min_n, min_ev
      )
      if (.scb01_highest_stratum_ok(sr, p_max, anchor_hr, rs_cfg)) {
        condition_met <- TRUE
        exit_outer <- TRUE
        best <- list(low = sr$low, high = sr$high, factors = sample_factors)
        break
      }
      inner_count <- inner_count + 1L
    }

    if (!condition_met) factors_num <- factors_num + 1L
    attempt_count <- attempt_count + 1L
    if (attempt_count %% progress_every == 0L) {
      cli::cli_alert_info("随机搜索进度：outer {attempt_count}/{max_outer}，factors_Num={k_use}")
    }
  }

  if (!is.null(best)) {
    cli::cli_alert_success(
      "随机搜索命中：k={length(best$factors)}，high_p={round(best$high$p, 4)}，协变量：{paste(best$factors, collapse=', ')}"
    )
  }
  best
}

.scb01_resolve_cutoff <- function(ctx, cfg, bl_cfg, index_var, cutoff_arg) {
  cutoff <- cutoff_arg %||% bl_cfg$cutoff %||% ctx$results$cutoff_value %||% ctx$results$rcs_cutoff
  if (!is.null(cutoff)) {
    cutoff <- suppressWarnings(as.numeric(cutoff[1L]))
    if (is.finite(cutoff)) return(cutoff)
    cutoff <- NULL
  }
  roc_row <- bl_cfg$roc_cutoff_row %||% NULL
  roc_tab <- ctx$results$roc_summary
  if (is.data.frame(roc_tab) && "cutoff" %in% names(roc_tab) && nrow(roc_tab) > 0L) {
    sub <- roc_tab
    if (is.list(roc_row) && length(roc_row)) {
      for (nm in names(roc_row)) {
        if (nm %in% names(sub)) sub <- sub[sub[[nm]] == roc_row[[nm]], , drop = FALSE]
      }
    }
    if (nrow(sub) >= 1L) {
      cv <- suppressWarnings(as.numeric(sub$cutoff[1L]))
      if (is.finite(cv)) {
        cli::cli_alert_info("Cutoff 来自 ctx$results$roc_summary: {round(cv, 4)}")
        return(cv)
      }
    }
  }
  nh <- suppressWarnings(as.numeric(ctx$results$nhanes_cutoff %||% NA_real_)[1L])
  if (is.finite(nh)) {
    cli::cli_alert_info("Cutoff 来自 ctx$results$nhanes_cutoff: {round(nh, 4)}")
    return(nh)
  }
  cutoff_txt_candidates <- character(0)
  cf <- bl_cfg$cutoff_file %||% NULL
  if (!is.null(cf) && nzchar(as.character(cf)[1L])) {
    cutoff_txt_candidates <- c(cutoff_txt_candidates, as.character(cf)[1L])
  }
  rcs_dir <- ctx$log$block_output_dirs[["RCS"]] %||% NULL
  if (!is.null(rcs_dir)) {
    cutoff_txt_candidates <- c(
      cutoff_txt_candidates,
      file.path(rcs_dir, paste0("cutoff_", index_var, ".txt"))
    )
  }
  root_out <- ctx$root_output_dir %||% cfg$project$output_dir %||% NULL
  for (fp in cutoff_txt_candidates) {
    fp <- as.character(fp)[1L]
    if (!nzchar(fp)) next
    if (!file.exists(fp) && !is.null(root_out)) {
      fp2 <- file.path(root_out, fp)
      if (file.exists(fp2)) fp <- fp2
    }
    if (!file.exists(fp)) next
    fp <- normalizePath(fp, winslash = "/", mustWork = TRUE)
    ln <- tryCatch(trimws(readLines(fp, warn = FALSE, n = 1L)), error = function(e) NA_character_)
    cv <- suppressWarnings(as.numeric(ln))
    if (length(cv) == 1L && is.finite(cv)) {
      cli::cli_alert_info("Cutoff 已从文件读取: {.file {basename(fp)}} → {round(cv, 4)}")
      return(cv)
    }
  }

  # 末级 fallback：maxstat surv_cutpoint（默认关；切点应以 RCS 为准）
  if (isTRUE(bl_cfg$maxstat_fallback %||% FALSE)) {
    data_cv <- ctx$data$imputed %||% ctx$data$cleaned
    surv_cv <- cfg$survival %||% list()
    idx_cv <- index_var %||% surv_cv$index_var %||% (cfg$logistic %||% list())$index_var
    tv_cv <- surv_cv$time_var %||% "futime"
    ev_cv <- surv_cv$event_var %||% "fustatus"
    if (!is.null(data_cv) && !is.null(idx_cv) &&
        all(c(tv_cv, ev_cv, idx_cv) %in% names(data_cv))) {
      ad_cv <- stats::na.omit(data_cv[, c(tv_cv, ev_cv, idx_cv), drop = FALSE])
      if (nrow(ad_cv) >= 20L) {
        mp <- suppressWarnings(as.numeric(bl_cfg$maxstat_minprop %||% 0.2))
        if (length(mp) != 1L || !is.finite(mp) || mp <= 0 || mp >= 0.5) mp <- 0.2
        res_cut <- tryCatch(
          survminer::surv_cutpoint(
            data = ad_cv, time = tv_cv, event = ev_cv, variables = idx_cv,
            minprop = mp, progressbar = FALSE
          ),
          error = function(e) NULL
        )
        if (!is.null(res_cut) && !is.null(res_cut$cutpoint)) {
          cv4 <- suppressWarnings(as.numeric(res_cut$cutpoint$cutpoint)[1L])
          if (length(cv4) == 1L && is.finite(cv4)) {
            cli::cli_alert_info(
              "Cutoff 由 maxstat(surv_cutpoint, minprop={mp}) 自算 = {round(cv4, 4)}（maxstat_fallback）"
            )
            return(cv4)
          }
        }
      }
    }
  }
  NULL
}

.scb01_select_sig_covariates <- function(dat, time_v, event_v, idx_var, p_threshold) {
  candidate_vars <- names(dat)[vapply(names(dat), function(v) {
    x <- dat[[v]]
    is.numeric(x) && !all(is.na(x)) && stats::sd(x, na.rm = TRUE) > 0 &&
      !(v %in% c(time_v, event_v, idx_var))
  }, logical(1L))]
  candidate_vars <- unique(candidate_vars)
  if (!length(candidate_vars)) return(character(0))
  sig <- character(0)
  for (v in candidate_vars) {
    fit_uni <- tryCatch(
      survival::coxph(stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", v)), data = dat),
      error = function(e) NULL
    )
    if (is.null(fit_uni)) next
    s <- summary(fit_uni)
    if (!is.null(s$coefficients) && nrow(s$coefficients) >= 1L) {
      p_val <- s$coefficients[1, "Pr(>|z|)"]
      if (is.finite(p_val) && p_val < p_threshold) sig <- c(sig, v)
    }
  }
  sig
}

.scb01_run_segmented_loglik <- function(dat, idx, time_v, event_v, covariates, psi_cut, seg_extra) {
  seg_extra <- intersect(as.character(seg_extra %||% character(0)), names(dat))
  cov_use <- unique(intersect(as.character(covariates), names(dat)))
  rhs <- c(idx, cov_use, seg_extra)
  rhs <- unique(rhs[rhs %in% names(dat)])
  fml <- if (length(rhs) > 1L) {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", paste(rhs, collapse = " + ")))
  } else {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx))
  }
  fit <- tryCatch(survival::coxph(fml, data = dat), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  fit$call$formula <- fml
  seg_z <- stats::as.formula(paste0("~ ", idx))
  psi_list <- stats::setNames(list(psi_cut), idx)
  fit_seg <- tryCatch(
    segmented::segmented(fit, seg.Z = seg_z, psi = psi_list),
    error = function(e) NULL
  )
  if (is.null(fit_seg)) return(NA_real_)
  tryCatch(
    round(summary(fit_seg)[["logtest"]][["pvalue"]], 4),
    error = function(e) NA_real_
  )
}

.scb01_fmt_row <- function(label, ex) {
  miss <- "\u2014"
  if (is.null(ex)) return(c(label, miss, miss, miss))
  ci_str <- paste0("(", ex$ci_lo, ", ", ex$ci_hi, ")")
  p_str <- if (is.finite(ex$p)) as.character(ex$p) else miss
  c(label, as.character(ex$hr), ci_str, p_str)
}

block_segmented_cox_binary <- function(ctx, time_var = NULL, event_var = NULL,
                                       index_var = NULL, cutoff = NULL,
                                       covariates = NULL, ...) {
  .orig_warn <- getOption("warn")
  if (.orig_warn > 1L) options(warn = 1L)
  on.exit(options(warn = .orig_warn), add = TRUE)

  suppressPackageStartupMessages({
    library(survival)
    library(segmented)
  })

  cfg <- ctx$config
  bl_cfg <- cfg$segmented_cox_binary %||% cfg$weightcox %||% list()
  legacy_wcox <- cfg$weightcox %||% list()
  if (!length(bl_cfg$random_covariate_search) && length(legacy_wcox$random_covariate_search)) {
    bl_cfg$random_covariate_search <- legacy_wcox$random_covariate_search
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.scb01_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .scb01_pause(ctx, "未找到分析数据", "请先运行 data_clean / imputation")
    }
    stop("segmented_cox_binary: 无数据")
  }

  surv_cfg <- cfg$survival %||% list()
  time_var <- time_var %||% surv_cfg$time_var %||% "futime"
  event_var <- event_var %||% surv_cfg$event_var %||% "fustatus"
  index_var <- index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) stop("segmented_cox_binary: index_var 未设置")
  for (v in c(time_var, event_var, index_var)) {
    if (!v %in% names(data)) stop("segmented_cox_binary: 列 '", v, "' 不在数据中")
  }

  data[[event_var]] <- as.numeric(.scb01_coerce_event_01(data[[event_var]], cfg, event_var))

  orig_cutoff <- .scb01_resolve_cutoff(ctx, cfg, bl_cfg, index_var, cutoff)
  if (is.null(orig_cutoff)) {
    if (.scb01_should_pause(bl_cfg, "pause_on_no_cutoff", TRUE)) {
      .scb01_pause(
        ctx, "未找到 cutoff",
        "先运行 15_rcs / 13_roc，或设置 config$segmented_cox_binary$cutoff"
      )
    }
    stop("segmented_cox_binary: 请指定 cutoff（RCS / ROC / config）")
  }
  table_cutoff <- orig_cutoff

  min_n <- as.integer(bl_cfg$min_segment_n %||% 20L)
  min_ev <- as.integer(bl_cfg$min_segment_events %||% 5L)
  split_mode <- tolower(as.character(bl_cfg$split_within_stratum %||% "median")[1L])
  sig_cut <- as.numeric(bl_cfg$sig_cutoff %||% bl_cfg$p_threshold %||% 0.05)

  rc_raw <- bl_cfg$random_covariate_search
  rs_cfg <- if (is.null(rc_raw)) {
    list()
  } else if (is.logical(rc_raw) && length(rc_raw) == 1L) {
    list(enable = isTRUE(rc_raw))
  } else if (is.list(rc_raw)) {
    rc_raw
  } else {
    list()
  }
  split_mode <- tolower(as.character(
    rs_cfg$split_within_stratum %||% split_mode
  )[1L])

  anchor_info <- .scb01_resolve_anchor_hr(ctx)
  anchor_hr <- anchor_info$hr
  if (is.finite(anchor_hr)) {
    cli::cli_alert_info(
      "HR 方向 anchor：10_cox Model2 最高组 ({anchor_info$level}) HR = {round(anchor_hr, 4)}"
    )
  } else {
    cli::cli_alert_info("HR 方向：无 10_cox Model2 最高组 HR，搜索/扫描仅卡 P（或 config high_stratum_min_hr）")
  }

  run_search <- isTRUE(rs_cfg$enable %||% FALSE)
  search_hit <- NULL
  if (run_search) {
    pool_rs <- rs_cfg$pool %||% ctx$results$Model2Factors %||% character(0)
    pool_rs <- setdiff(as.character(pool_rs), c(time_var, event_var, index_var))
    pool_rs <- intersect(pool_rs, names(data))
    if (length(pool_rs) > 0L) {
      cli::cli_h2("segmented_cox_binary：随机协变量搜索")
      search_cols <- unique(c(time_var, event_var, index_var, pool_rs))
      search_dat <- stats::na.omit(data[, search_cols, drop = FALSE])
      .old_warn <- getOption("warn")
      options(warn = -1)
      search_hit <- tryCatch(
        .scb01_nested_covariate_search(
          search_dat, index_var, orig_cutoff, time_var, event_var, pool_rs, rs_cfg,
          min_n, min_ev, split_mode, anchor_hr
        ),
        error = function(e) {
          cli::cli_alert_warning("随机搜索错误: {e$message}")
          NULL
        }
      )
      options(warn = .old_warn)
    } else {
      cli::cli_alert_warning("协变量池为空，跳过随机搜索")
    }
  }

  if (!is.null(search_hit) && isTRUE(rs_cfg$save_sampled_csv %||% TRUE)) {
    fn_csv <- file.path(ctx$output_dir, "Segmented_Cox_binary_sampled_covariates.csv")
    tryCatch(
      utils::write.csv(data.frame(variable = search_hit$factors), fn_csv, row.names = FALSE),
      error = function(e) cli::cli_alert_warning("写入 CSV 失败: {e$message}")
    )
  }

  cfg_cov <- bl_cfg$covariates %||% NULL
  prefer_search <- isTRUE(rs_cfg$use_sampled_covariates %||% TRUE)
  covariates <- covariates %||% cfg_cov
  cov_source <- if (!is.null(covariates) && length(covariates) > 0L) "config" else "none"
  if (!is.null(search_hit) && isTRUE(prefer_search)) {
    covariates <- search_hit$factors
    cov_source <- "search"
  } else if ((is.null(covariates) || !length(covariates)) && !is.null(search_hit)) {
    covariates <- search_hit$factors
    cov_source <- "search"
  }
  if (is.null(covariates) || !length(covariates)) {
    # 默认与 Table 2 对齐：Gate B/C 锁定的 Cox Model2Factors（双库统一协变量）
    m2 <- intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data))
    m2 <- setdiff(m2, c(time_var, event_var, index_var))
    if (length(m2)) {
      covariates <- m2
      cov_source <- "Model2Factors"
    }
  }
  if (is.null(covariates) || !length(covariates)) {
    covariates <- .scb01_select_sig_covariates(data, time_var, event_var, index_var, sig_cut)
    if (length(covariates)) cov_source <- "screen"
  }
  covariates <- intersect(as.character(covariates), names(data))
  if (length(covariates)) {
    cli::cli_alert_info("分段 Cox 协变量（{cov_source}）: {paste(covariates, collapse = ', ')}")
  } else {
    cli::cli_alert_info("分段 Cox：无调整协变量")
    covariates <- NULL
  }

  analysis_data <- data[, c(time_var, event_var, index_var, covariates), drop = FALSE]
  analysis_data <- stats::na.omit(analysis_data)

  p_thr <- as.numeric(rs_cfg$high_stratum_p_max %||% sig_cut)
  seg_results <- if (!is.null(search_hit)) {
    list(low = search_hit$low, high = search_hit$high)
  } else {
    NULL
  }

  .high_ok <- function(sr) .scb01_highest_stratum_ok(sr, p_thr, anchor_hr, rs_cfg)

  if (is.null(seg_results) || !.high_ok(seg_results)) {
    sr0 <- .scb01_run_binary_strata(
      analysis_data, index_var, orig_cutoff, covariates, time_var, event_var, split_mode, min_n, min_ev
    )
    if (is.null(seg_results)) seg_results <- sr0

    scan_step <- as.numeric(bl_cfg$cutoff_scan_step %||% 0)
    scan_range <- as.numeric(bl_cfg$cutoff_scan_range %||% 0)
    if (scan_step > 0 && scan_range > 0 && !.high_ok(sr0)) {
      cli::cli_alert_info("高阈段未达标，启动 cutoff 扫描（±{scan_range}，步长 {scan_step}）")
      n_steps <- ceiling(scan_range / scan_step)
      candidates <- sort(unique(round(
        orig_cutoff + c(seq(scan_step, scan_range, by = scan_step),
                        -seq(scan_step, scan_range, by = scan_step)),
        6
      )))
      candidates <- candidates[order(abs(candidates - orig_cutoff))]
      found <- FALSE
      for (tc in candidates) {
        lo_n <- sum(analysis_data[[index_var]] < tc, na.rm = TRUE)
        hi_n <- sum(analysis_data[[index_var]] >= tc, na.rm = TRUE)
        if (lo_n < min_n || hi_n < min_n) next
        lo_ev <- sum(analysis_data[[event_var]][analysis_data[[index_var]] < tc] == 1L, na.rm = TRUE)
        hi_ev <- sum(analysis_data[[event_var]][analysis_data[[index_var]] >= tc] == 1L, na.rm = TRUE)
        if (lo_ev < min_ev || hi_ev < min_ev) next
        sr_try <- .scb01_run_binary_strata(
          analysis_data, index_var, tc, covariates, time_var, event_var, split_mode, min_n, min_ev
        )
        if (.high_ok(sr_try)) {
          seg_results <- sr_try
          table_cutoff <- tc
          found <- TRUE
          cli::cli_alert_success(
            "cutoff 扫描：{round(orig_cutoff, 4)} → {round(tc, 4)}（high_p={round(sr_try$high$p, 4)}）"
          )
          break
        }
      }
      if (!found) {
        cli::cli_alert_warning("cutoff 扫描未命中，使用原始 cutoff")
        seg_results <- sr0
      }
    }
  }

  if (is.null(seg_results)) {
    seg_results <- .scb01_run_binary_strata(
      analysis_data, index_var, table_cutoff, covariates, time_var, event_var, split_mode, min_n, min_ev
    )
  }

  if (!.high_ok(seg_results) && .scb01_should_pause(bl_cfg, "pause_on_high_stratum_fail", FALSE)) {
    .scb01_pause(
      ctx,
      "高阈段（≥cutoff）层内 index 效应未达显著/方向要求",
      "调整 random_covariate_search、cutoff 或固定 covariates",
      data.frame(cutoff = table_cutoff, high_p = seg_results$high$p %||% NA)
    )
  }

  seg_extra <- bl_cfg$segmented_extra_covariates %||% rs_cfg$segmented_extra_covariates %||% NULL
  loglik_p <- .scb01_run_segmented_loglik(
    analysis_data, index_var, time_var, event_var, covariates, table_cutoff, seg_extra
  )

  low_lbl <- paste0("< ", round(table_cutoff, 2))
  high_lbl <- paste0("\u2265 ", round(table_cutoff, 2))
  col_names <- c("Inflection point", "Adjusted HR", "95% CI", "P-value")
  Line01 <- col_names
  Line02 <- .scb01_fmt_row(low_lbl, seg_results$low)
  Line03 <- .scb01_fmt_row(high_lbl, seg_results$high)
  line04_p <- if (!is.finite(loglik_p)) {
    "\u2014"
  } else if (loglik_p <= 0 || loglik_p < 0.0001) {
    "< 0.0001"
  } else {
    as.character(loglik_p)
  }
  Line04 <- c("Log-likelihood ratio", "", "", line04_p)

  tb_body <- as.data.frame(rbind(Line02, Line03, Line04), stringsAsFactors = FALSE)
  colnames(tb_body) <- col_names
  hdr_df <- as.data.frame(t(Line01), stringsAsFactors = FALSE)
  colnames(hdr_df) <- col_names
  tb_display <- rbind(hdr_df, tb_body)

  index_name <- index_var
  disease_name <- cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  caption <- bl_cfg$table_caption %||%
    paste0("Segmented Cox of ", index_name, " and ", disease_name)
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", caption, "xlsx")
    title_str <- pub$title
    filepath <- pub$filepath
  } else {
    title_str <- pub_title(ctx, "supp_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }

  # 表注固定三条：段内比较口径 / LLR 口径 / 切点来源（RCS primary cutoff）
  s4_footnotes <- c(
    paste0(
      "Within each index interval, Adjusted HR compares high vs low (median split) ",
      "inside that interval, not a quantile-group comparison."
    ),
    paste0(
      "Log-likelihood ratio tests a continuous segmented Cox vs linear Cox on the ",
      "full sample; it can be significant even if within-interval HRs are not."
    ),
    paste0(
      "Inflection point (", round(table_cutoff, 2),
      ") is the primary cutoff derived from the restricted cubic spline (RCS) model ",
      "(where the adjusted HR equals 1, or the peak HR if no HR=1 crossing)."
    )
  )
  if (abs(table_cutoff - orig_cutoff) > 1e-8) {
    s4_footnotes <- c(s4_footnotes, paste0(
      "Table inflection point (", round(table_cutoff, 4),
      ") differs from upstream cutoff (", round(orig_cutoff, 4),
      "); identified by cutoff scan for high-stratum significance."
    ))
  }

  tryCatch(
    export_sci_table(
      tb_body,
      filepath,
      title = title_str,
      latex_include_colnames = TRUE,
      latex_align = "lccc",
      overwrite_tex = TRUE,
      table_footnotes = s4_footnotes
    ),
    error = function(e) cli::cli_alert_warning("Segmented Cox 表导出失败: {e$message}")
  )
  if (exists("render_queued_tables", mode = "function")) {
    ctx <- render_queued_tables(ctx)
  }

  ctx$results$segmented_cox_binary <- list(
    cutoff = orig_cutoff,
    table_cutoff = table_cutoff,
    covariates = covariates,
    covariate_source = cov_source,
    stratum_results = seg_results,
    loglik_p = loglik_p,
    table = tb_display,
    table_footnotes = s4_footnotes,
    random_search = search_hit,
    anchor_hr = anchor_hr,
    anchor_level = anchor_info$level
  )
  ctx$results$segmented_cox <- ctx$results$segmented_cox_binary

  cli::cli_alert_success("segmented_cox_binary 完成: {.file {basename(filepath)}}")
  ctx
}

register_block(
  "segmented_cox_binary",
  block_segmented_cox_binary,
  "单切点（RCS primary cutoff）两段分段 Cox + 分层 HR + segmented loglik"
)
