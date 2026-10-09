###############################################################################
#  segmented_cox_quartile — 全样本 index 按四分位切为 4 个外层段（Q1–Q4，与 cox_quartile 一致）；
#                            每段内 mean/median 再二分 index → high vs low，分层 Cox 得 4 行 HR；
#                            全样本连续 index + 同一套协变量做 segmented()（3 个 psi）。
#                            不含 cutoff 图、KM、二次 baseline RData。
#
#  register_block: "segmented_cox_quartile"
#  典型流水线: … → multicollinearity → cox_quartile → segmented_cox_quartile
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_cox         = 须先 run_block(ctx, "cox_quartile")
#                        ctx$results$cox_grouping$method == "quartile" 且 n_groups == 4
#  时间/事件/暴露      = config$survival$time_var / event_var / index_var
#  外层断点（3 个）    = ctx$results$cox_index_breaks（cox_quartile 写入，通常为 quantile 的 25/50/75%）
#                        或全样本 quantile(index)[2:4]（与 cox_quartile 默认切法一致）
#  HR 方向 anchor      = ctx$results$cox_highest_group_model2_hr（通常为 Q4 vs Q1 的 Model2 HR）；
#                        无有效 HR 时不卡方向（require_hr_direction = "auto"）
#  协变量池（搜索用）  = random_covariate_search$pool 或 ctx$results$Model2Factors
#
#  # ── 配置 config$segmented_cox_quartile ──────────────────────────────────────
#  segmented_cox_quartile = list(
#    split_within_stratum = "median",    # 层内 index 二分："mean" | "median"
#    min_segment_n        = 20,
#    min_segment_events   = 5,
#    covariates           = NULL,        # 固定协变量；本块无单因素筛选回退时需自行指定或开搜索
#    table_filename       = NULL,
#    random_covariate_search = list(
#      enable                    = FALSE,
#      require_hr_direction      = "auto",
#      max_outer_attempts        = 1000L,
#      max_inner_attempts        = 1000L,
#      initial_factors_n         = 1L,
#      pool                      = NULL,
#      high_stratum_p_max        = 0.05,    # 仅判最高外层段（第 4 段 / Q4 区间）
#      high_stratum_min_hr       = 1,
#      both_strata_significance_use_p_only = FALSE,
#      seed                      = NULL
#    ),
#    pause_enable             = TRUE,
#    pause_on_cox_mismatch    = TRUE       # 未先跑 cox_quartile 时 pause
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$segmented_cox_quartile
#      Tables/Table S4. Segmented Cox (quartile) of <index> and <disease>.xlsx
#      Table 共 4 行 HR + 1 行 Log-likelihood ratio
#  不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
#
#  源: 外层切点对齐 Blocks/10_cox/03block_cox_quartile.R
#  依赖: survival, segmented
###############################################################################

.scq03_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}
.scq03_pause <- function(ctx, reason, suggestion, snap = NULL) {
  ctx$results$pause_point <- list(block = "segmented_cox_quartile", reason = reason, suggestion = suggestion,
                                   data_snapshot = if (is.data.frame(snap)) utils::head(snap, 5L) else NULL)
  stop("PAUSE_FOR_USER_DECISION: segmented_cox_quartile — ", reason, call. = FALSE)
}
.scq03_coerce_event <- function(x, cfg, ev) {
  if (is.numeric(x) && all(unique(na.omit(x)) %in% c(0, 1))) return(as.numeric(x))
  if (is.logical(x)) return(as.integer(x))
  ana <- cfg$project$analysis_group %||% ""
  xc <- trimws(as.character(x)); out <- rep(NA_integer_, length(xc))
  ok <- !is.na(xc) & nzchar(xc)
  out[ok & (xc == ana | tolower(xc) == tolower(ana))] <- 1L
  out[ok & !(xc == ana | tolower(xc) == tolower(ana))] <- 0L
  out
}
.scq03_extract_hl <- function(fit, idx) {
  if (is.null(fit)) return(NULL)
  # IMPORTANT: conf.int must be numeric level (e.g. 0.95).
  # summary(fit, conf.int = TRUE) coerces TRUE→1 → 100% CI → (0, Inf) on HR scale.
  s <- tryCatch(summary(fit, conf.int = 0.95), error = function(e) NULL)
  if (is.null(s)) return(NULL)
  co <- s$coefficients; ci <- s$conf.int
  ig <- grep("high", rownames(co), ignore.case = TRUE)[1L]
  if (is.na(ig)) ig <- 1L
  pcol <- grep("^Pr\\(", colnames(co), perl = TRUE)[1L]
  hr_col <- grep("exp\\(coef\\)", colnames(ci), perl = TRUE)[1L]
  lo_col <- grep("lower", colnames(ci), perl = TRUE)[1L]
  hi_col <- grep("upper", colnames(ci), perl = TRUE)[1L]
  if (is.na(hr_col)) hr_col <- 1L
  if (is.na(lo_col)) lo_col <- min(3L, ncol(ci))
  if (is.na(hi_col)) hi_col <- min(4L, ncol(ci))
  hr <- as.numeric(ci[ig, hr_col]); lo <- as.numeric(ci[ig, lo_col]); hi <- as.numeric(ci[ig, hi_col])
  if (!all(is.finite(c(hr, lo, hi)))) {
    # Wald fallback if summary CI still non-finite
    b <- tryCatch(stats::coef(fit)[ig], error = function(e) NA_real_)
    se <- tryCatch(sqrt(diag(as.matrix(stats::vcov(fit))))[ig], error = function(e) NA_real_)
    if (is.finite(b) && is.finite(se) && se > 0) {
      z <- stats::qnorm(0.975)
      hr <- exp(b); lo <- exp(b - z * se); hi <- exp(b + z * se)
    }
  }
  if (!all(is.finite(c(hr, lo, hi)))) return(NULL)
  list(hr = round(hr, 3), ci_lo = round(lo, 3), ci_hi = round(hi, 3),
       p = pub_format_p_cell(co[ig, pcol]))
}
.scq03_dichot <- function(v, mode) {
  fn <- if (tolower(mode)[1] == "median") stats::median else mean
  ok <- is.finite(v); spl <- fn(v[ok], na.rm = TRUE)
  ifelse(!ok, NA_character_, ifelse(v >= spl, "high", "low"))
}
.scq03_seg_sub <- function(dat, idx, br, i, n) {
  x <- dat[[idx]]
  if (i == 1L) dat[x < br[1], , drop = FALSE]
  else if (i == n) dat[x >= br[n - 1L], , drop = FALSE]
  else dat[x >= br[i - 1L] & x < br[i], , drop = FALSE]
}
.scq03_seg_lbl <- function(br, i, n) {
  if (i == 1L) paste0("< ", round(br[1], 2))
  else if (i == n) paste0("\u2265 ", round(br[n - 1L], 2))
  else paste0(round(br[i - 1L], 2), " \u2013 ", round(br[i], 2))
}
.scq03_one_seg <- function(dat, idx, br, i, n, fac, tv, ev, mode, min_n, min_ev) {
  tmp <- .scq03_seg_sub(dat, idx, br, i, n)
  if (nrow(tmp) < min_n || sum(tmp[[ev]] == 1, na.rm = TRUE) < min_ev) return(NULL)
  tmp[[idx]] <- factor(.scq03_dichot(tmp[[idx]], mode), levels = c("low", "high"))
  if (nlevels(droplevels(tmp[[idx]])) < 2L) return(NULL)
  fac <- intersect(fac, names(tmp))
  rhs <- if (length(fac)) paste(fac, collapse = " + ") else NULL
  fml <- as.formula(paste0("Surv(", tv, ",", ev, ")~", idx, if (length(rhs)) paste0("+", rhs) else ""))
  .scq03_extract_hl(tryCatch(survival::coxph(fml, data = na.omit(tmp)), error = function(e) NULL), idx)
}
.scq03_all_seg <- function(dat, idx, br, n, fac, tv, ev, mode, min_n, min_ev) {
  lapply(seq_len(n), function(i) .scq03_one_seg(dat, idx, br, i, n, fac, tv, ev, mode, min_n, min_ev))
}
.scq03_anchor <- function(ctx) {
  raw <- ctx$results$cox_highest_group_model2_hr
  hr <- suppressWarnings(as.numeric(if (length(raw)) raw[[1L]] else NA_real_))
  if (length(hr) != 1L || !is.finite(hr)) return(NA_real_)
  hr
}
.scq03_hr_ok <- function(hr, anch, rs) {
  if (tolower(rs$require_hr_direction %||% "auto")[1] == "none") return(TRUE)
  if (length(anch) != 1L || !is.finite(anch) || abs(anch - 1) < 1e-8) return(TRUE)
  if (length(hr) != 1L || !is.finite(hr)) return(FALSE)
  if (anch > 1) hr > 1 else hr < 1
}
.scq03_hi_ok <- function(sl, p, anch, rs) {
  rh <- sl[[length(sl)]]
  !is.null(rh) && is.finite(rh$p) && rh$p < p && (isTRUE(rs$both_strata_significance_use_p_only %||% FALSE) || .scq03_hr_ok(rh$hr, anch, rs))
}
.scq03_search <- function(dat, idx, br, n, tv, ev, pool, rs, min_n, min_ev, mode, anch) {
  pool <- intersect(pool, names(dat)); if (!length(pool)) return(NULL)
  if (!is.null(rs$seed)) set.seed(as.integer(rs$seed))
  for (attempt in seq_len(as.integer(rs$max_outer_attempts %||% 1000L))) {
    k <- min(max(1L, as.integer(rs$initial_factors_n %||% 1L)) + (attempt - 1L) %% length(pool), length(pool))
    for (inner in seq_len(as.integer(rs$max_inner_attempts %||% 1000L))) {
      fac <- sample(pool, k, replace = FALSE)
      sl <- .scq03_all_seg(dat, idx, br, n, fac, tv, ev, mode, min_n, min_ev)
      if (.scq03_hi_ok(sl, as.numeric(rs$high_stratum_p_max %||% 0.05), anch, rs)) return(list(segments = sl, factors = fac))
    }
  }
  NULL
}
.scq03_breaks <- function(ctx, data, idx, bl) {
  cg <- ctx$results$cox_grouping %||% list()
  if (!identical(cg$method, "quartile") || (cg$n_groups %||% 0) != 4L) {
    if (.scq03_should_pause(bl, "pause_on_cox_mismatch", TRUE)) .scq03_pause(ctx, "需先 cox_quartile", "run_block cox_quartile")
    cli::cli_alert_warning("将重算四分位断点")
  }
  br <- as.numeric(ctx$results$cox_index_breaks)
  br <- br[is.finite(br)]
  if (length(br) == 3L) return(br)
  if (length(br) >= 5L) return(br[c(2L, 3L, 4L)])
  if (length(br) > 3L) return(br[seq_len(3L)])
  qs <- as.numeric(stats::quantile(data[[idx]], na.rm = TRUE))
  qs[2:4]
}

block_segmented_cox_quartile <- function(ctx, time_var = NULL, event_var = NULL, index_var = NULL, ...) {
  suppressPackageStartupMessages({ library(survival); library(segmented) })
  cfg <- ctx$config; bl <- cfg$segmented_cox_quartile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) .scq03_pause(ctx, "无数据", "imputation")
  surv <- cfg$survival %||% list()
  tv <- time_var %||% surv$time_var %||% "futime"
  ev <- event_var %||% surv$event_var %||% "fustatus"
  idx <- index_var %||% surv$index_var %||% cfg$logistic$index_var
  data[[ev]] <- as.numeric(.scq03_coerce_event(data[[ev]], cfg, ev))
  n <- 4L
  br <- .scq03_breaks(ctx, data, idx, bl)
  rs <- if (is.list(bl$random_covariate_search)) bl$random_covariate_search else list()
  anch <- .scq03_anchor(ctx)
  pool <- setdiff(rs$pool %||% ctx$results$Model2Factors %||% character(0), c(tv, ev, idx))
  hit <- if (isTRUE(rs$enable %||% FALSE)) .scq03_search(na.omit(data[, c(tv, ev, idx, pool), drop = FALSE]), idx, br, n, tv, ev, pool, rs,
    as.integer(bl$min_segment_n %||% 20L), as.integer(bl$min_segment_events %||% 5L), bl$split_within_stratum %||% "median", anch) else NULL
  cov <- intersect(if (!is.null(hit)) hit$factors else bl$covariates %||% character(0), names(data))
  ad <- na.omit(data[, c(tv, ev, idx, cov), drop = FALSE])
  sl <- if (!is.null(hit)) hit$segments else .scq03_all_seg(ad, idx, br, n, cov, tv, ev, bl$split_within_stratum %||% "median",
    as.integer(bl$min_segment_n %||% 20L), as.integer(bl$min_segment_events %||% 5L))
  rhs <- unique(c(idx, cov)); fml <- as.formula(paste0("Surv(", tv, ",", ev, ")~", paste(rhs, collapse = "+")))
  fit <- tryCatch(coxph(fml, data = ad), error = function(e) NULL)
  loglik <- NA_real_
  if (!is.null(fit)) {
    fs <- tryCatch(segmented(fit, seg.Z = as.formula(paste0("~", idx)), psi = setNames(list(br), idx)), error = function(e) NULL)
    if (!is.null(fs)) loglik <- tryCatch(round(summary(fs)$logtest$pvalue, 4), error = function(e) NA_real_)
  }
  cols <- c("Inflection point", "Adjusted HR", "95% CI", "P-value")
  rows <- lapply(seq_len(n), function(i) {
    ex <- sl[[i]]; miss <- "\u2014"
    if (is.null(ex)) return(c(.scq03_seg_lbl(br, i, n), miss, miss, miss))
    c(.scq03_seg_lbl(br, i, n), as.character(ex$hr), paste0("(", ex$ci_lo, ", ", ex$ci_hi, ")"), as.character(ex$p))
  })
  lp <- if (length(loglik) != 1L || !is.finite(loglik) || loglik < 1e-4) "< 0.0001" else as.character(loglik)
  tb <- as.data.frame(do.call(rbind, c(rows, list(c("Log-likelihood ratio", "", "", lp)))), stringsAsFactors = FALSE)
  colnames(tb) <- cols
  # 脚注：段内 HR = 该段内 high vs low（中位数二分），不是 Qk vs Q1；
  # LLR = 全样本 segmented() 相对线性 Cox，可与各段 P 值不一致。
  fn_seg <- c(
    "Within each index interval, Adjusted HR compares high vs low (median split) inside that interval, not quartile vs Q1.",
    "Log-likelihood ratio tests a continuous segmented Cox vs linear Cox on the full sample; it can be significant even if within-interval HRs are not."
  )
  dis <- cfg$project$disease %||% "Disease"
  caption <- paste0("Segmented Cox (quartile) of ", idx, " and ", dis)
  if (is.null(bl$table_filename) || !nzchar(bl$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", caption, "xlsx")
    title <- pub$title
    fp <- pub$filepath
  } else {
    title <- pub_title(ctx, "supp_table", caption)
    fp <- file.path(ctx$output_dir_tables, bl$table_filename)
  }
  tryCatch(
    export_sci_table(
      tb, fp, title = title, latex_include_colnames = TRUE, latex_align = "lccc",
      table_footnotes = fn_seg
    ),
    error = function(e) cli::cli_alert_warning("segmented_cox_quartile 表格导出失败: {e$message}")
  )
  if (exists("render_queued_tables", mode = "function")) {
    ctx <- render_queued_tables(ctx)
  }
  ctx$results$segmented_cox_quartile <- list(breaks = br, segment_results = sl, loglik_p = loglik, covariates = cov, random_search = hit)
  cli::cli_alert_success("segmented_cox_quartile 完成")
  ctx
}
register_block("segmented_cox_quartile", block_segmented_cox_quartile, "四分位外层分段 Cox + Table S4")
