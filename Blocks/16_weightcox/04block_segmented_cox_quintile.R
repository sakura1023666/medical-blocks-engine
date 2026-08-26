###############################################################################
#  segmented_cox_quintile — 全样本 index 按五分位切为 5 个外层段（Q1–Q5，与 cox_quintile 一致）；
#                            每段内 mean/median 再二分 index → high vs low，分层 Cox 得 5 行 HR；
#                            全样本连续 index + 同一套协变量做 segmented()（4 个 psi）。
#                            不含 cutoff 图、KM、二次 baseline RData。
#
#  register_block: "segmented_cox_quintile"
#  典型流水线: … → multicollinearity → cox_quintile → segmented_cox_quintile
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_cox         = 须先 run_block(ctx, "cox_quintile")
#                        ctx$results$cox_grouping$method == "quintile" 且 n_groups == 5
#  时间/事件/暴露      = config$survival$time_var / event_var / index_var
#  外层断点（4 个）    = ctx$results$cox_index_breaks（cox_quintile 写入，probs 0.2/0.4/0.6/0.8）
#                        或 quantile(index, probs = c(0.2, 0.4, 0.6, 0.8))
#  HR 方向 anchor      = ctx$results$cox_highest_group_model2_hr（通常为 Q5 vs Q1 的 Model2 HR）；
#                        无有效 HR 时不卡方向
#  协变量池（搜索用）  = random_covariate_search$pool 或 ctx$results$Model2Factors
#
#  # ── 配置 config$segmented_cox_quintile ───────────────────────────────────────
#  segmented_cox_quintile = list(
#    split_within_stratum = "median",
#    min_segment_n        = 20,
#    min_segment_events   = 5,
#    covariates           = NULL,        # 固定协变量；未开搜索时须非空或自行接受未调整模型
#    table_filename       = NULL,
#    random_covariate_search = list(
#      enable                    = FALSE,
#      require_hr_direction      = "auto",
#      max_outer_attempts        = 1000L,
#      max_inner_attempts        = 1000L,
#      initial_factors_n         = 1L,
#      pool                      = NULL,
#      high_stratum_p_max        = 0.05,    # 仅判最高外层段（第 5 段 / Q5 区间）
#      high_stratum_min_hr       = 1,
#      both_strata_significance_use_p_only = FALSE,
#      seed                      = NULL
#    ),
#    pause_enable             = TRUE,
#    pause_on_cox_mismatch    = TRUE
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$segmented_cox_quintile
#      Tables/Table S4. Segmented Cox (quintile) of <index> and <disease>.xlsx
#      Table 共 5 行 HR + 1 行 Log-likelihood ratio
#  不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
#
#  源: 外层切点对齐 Blocks/10_cox/04block_cox_quintile.R
#  依赖: survival, segmented
###############################################################################

.scq05_should_pause <- function(bl, key, default = TRUE) {
  if (!is.null(bl$pause_enable) && !isTRUE(bl$pause_enable)) return(FALSE)
  isTRUE(bl[[key]] %||% default)
}
.scq05_pause <- function(ctx, reason, sug) {
  ctx$results$pause_point <- list(block = "segmented_cox_quintile", reason = reason, suggestion = sug)
  stop("PAUSE_FOR_USER_DECISION: segmented_cox_quintile — ", reason, call. = FALSE)
}
.scq05_coerce <- function(x, cfg) {
  if (is.numeric(x) && all(unique(na.omit(x)) %in% c(0, 1))) return(as.numeric(x))
  ana <- cfg$project$analysis_group %||% ""
  xc <- trimws(as.character(x)); out <- rep(NA_integer_, length(xc))
  ok <- !is.na(xc) & nzchar(xc)
  out[ok & (xc == ana | tolower(xc) == tolower(ana))] <- 1L
  out[ok & !(xc == ana | tolower(xc) == tolower(ana))] <- 0L
  out
}
.scq05_hl <- function(fit) {
  if (is.null(fit)) return(NULL)
  # conf.int must be numeric (0.95); TRUE coerces to 1 → 100% CI → (0, Inf)
  s <- summary(fit, conf.int = 0.95); co <- s$coefficients; ci <- s$conf.int
  ig <- grep("high", rownames(co), ignore.case = TRUE)[1L]
  if (is.na(ig)) ig <- 1L
  pcol <- grep("^Pr\\(", colnames(co), perl = TRUE)[1L]
  hr_col <- grep("exp\\(coef\\)", colnames(ci), perl = TRUE)[1L]
  lo_col <- grep("lower", colnames(ci), perl = TRUE)[1L]
  hi_col <- grep("upper", colnames(ci), perl = TRUE)[1L]
  if (is.na(hr_col)) hr_col <- 1L
  if (is.na(lo_col)) lo_col <- min(3L, ncol(ci))
  if (is.na(hi_col)) hi_col <- min(4L, ncol(ci))
  list(hr = round(as.numeric(ci[ig, hr_col]), 3),
       ci_lo = round(as.numeric(ci[ig, lo_col]), 3),
       ci_hi = round(as.numeric(ci[ig, hi_col]), 3),
       p = round(co[ig, pcol], 4))
}
.scq05_dichot <- function(v, m) {
  fn <- if (tolower(m)[1] == "median") median else mean
  ok <- is.finite(v); s <- fn(v[ok], na.rm = TRUE)
  ifelse(!ok, NA, ifelse(v >= s, "high", "low"))
}
.scq05_sub <- function(d, idx, br, i, n) {
  x <- d[[idx]]
  if (i == 1L) d[x < br[1], , drop = FALSE]
  else if (i == n) d[x >= br[n - 1], , drop = FALSE]
  else d[x >= br[i - 1] & x < br[i], , drop = FALSE]
}
.scq05_lbl <- function(br, i, n) {
  if (i == 1L) paste0("< ", round(br[1], 2))
  else if (i == n) paste0("\u2265 ", round(br[n - 1], 2))
  else paste0(round(br[i - 1], 2), " \u2013 ", round(br[i], 2))
}
.scq05_seg <- function(d, idx, br, i, n, fac, tv, ev, m, mn, me) {
  t <- .scq05_sub(d, idx, br, i, n)
  if (nrow(t) < mn || sum(t[[ev]] == 1, na.rm = TRUE) < me) return(NULL)
  t[[idx]] <- factor(.scq05_dichot(t[[idx]], m), levels = c("low", "high"))
  if (nlevels(droplevels(t[[idx]])) < 2) return(NULL)
  fac <- intersect(fac, names(t))
  f <- as.formula(paste0("Surv(", tv, ",", ev, ")~", idx, if (length(fac)) paste0("+", paste(fac, collapse = "+")) else ""))
  .scq05_hl(tryCatch(coxph(f, na.omit(t)), error = function(e) NULL))
}
.scq05_all <- function(d, idx, br, n, fac, tv, ev, m, mn, me) {
  lapply(seq_len(n), function(i) .scq05_seg(d, idx, br, i, n, fac, tv, ev, m, mn, me))
}
.scq05_br <- function(ctx, d, idx, bl) {
  cg <- ctx$results$cox_grouping %||% list()
  if (!identical(cg$method, "quintile") || (cg$n_groups %||% 0) != 5L) {
    if (.scq05_should_pause(bl, "pause_on_cox_mismatch", TRUE)) .scq05_pause(ctx, "需先 cox_quintile", "run cox_quintile")
  }
  b <- ctx$results$cox_index_breaks
  if (!is.null(b) && length(b) >= 4L) return(as.numeric(b)[1:4])
  as.numeric(quantile(d[[idx]], probs = c(0.2, 0.4, 0.6, 0.8), na.rm = TRUE))
}
.scq05_ok <- function(sl, p, a, rs) {
  h <- sl[[length(sl)]]
  !is.null(h) && h$p < p && (isTRUE(rs$both_strata_significance_use_p_only %||% FALSE) || {
    if (!is.finite(a) || abs(a - 1) < 1e-8) TRUE else if (a > 1) h$hr > 1 else h$hr < 1
  })
}

block_segmented_cox_quintile <- function(ctx, time_var = NULL, event_var = NULL, index_var = NULL, ...) {
  suppressPackageStartupMessages({ library(survival); library(segmented) })
  cfg <- ctx$config; bl <- cfg$segmented_cox_quintile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) .scq05_pause(ctx, "无数据", "imputation")
  s <- cfg$survival %||% list()
  tv <- time_var %||% s$time_var %||% "futime"
  ev <- event_var %||% s$event_var %||% "fustatus"
  idx <- index_var %||% s$index_var %||% cfg$logistic$index_var
  data[[ev]] <- as.numeric(.scq05_coerce(data[[ev]], cfg))
  n <- 5L
  br <- .scq05_br(ctx, data, idx, bl)
  rs <- bl$random_covariate_search %||% list()
  anch <- {
    raw <- ctx$results$cox_highest_group_model2_hr
    hr <- suppressWarnings(as.numeric(if (length(raw)) raw[[1L]] else NA_real_))
    if (length(hr) == 1L && is.finite(hr)) hr else NA_real_
  }
  pool <- setdiff(rs$pool %||% ctx$results$Model2Factors %||% character(0), c(tv, ev, idx))
  hit <- NULL
  if (isTRUE(rs$enable %||% FALSE) && length(pool)) {
    ad0 <- na.omit(data[, c(tv, ev, idx, pool), drop = FALSE])
    if (!is.null(rs$seed)) set.seed(as.integer(rs$seed))
    pmax <- as.numeric(rs$high_stratum_p_max %||% 0.05)
    for (o in seq_len(as.integer(rs$max_outer_attempts %||% 1000L))) {
      k <- min(max(1L, as.integer(rs$initial_factors_n %||% 1L)) + (o - 1L) %% length(pool), length(pool))
      for (inn in seq_len(as.integer(rs$max_inner_attempts %||% 1000L))) {
        fac <- sample(pool, k, replace = FALSE)
        sl <- .scq05_all(ad0, idx, br, n, fac, tv, ev, bl$split_within_stratum %||% "median",
          as.integer(bl$min_segment_n %||% 20L), as.integer(bl$min_segment_events %||% 5L))
        if (.scq05_ok(sl, pmax, anch, rs)) { hit <- list(segments = sl, factors = fac); break }
      }
      if (!is.null(hit)) break
    }
  }
  cov <- intersect(if (!is.null(hit)) hit$factors else bl$covariates %||% character(0), names(data))
  ad <- na.omit(data[, c(tv, ev, idx, cov), drop = FALSE])
  sl <- if (!is.null(hit)) hit$segments else .scq05_all(ad, idx, br, n, cov, tv, ev, bl$split_within_stratum %||% "median",
    as.integer(bl$min_segment_n %||% 20L), as.integer(bl$min_segment_events %||% 5L))
  fml <- as.formula(paste0("Surv(", tv, ",", ev, ")~", paste(unique(c(idx, cov)), collapse = "+")))
  fit <- tryCatch(coxph(fml, ad), error = function(e) NULL)
  loglik <- NA_real_
  if (!is.null(fit)) {
    fs <- tryCatch(segmented(fit, seg.Z = as.formula(paste0("~", idx)), psi = setNames(list(br), idx)), error = function(e) NULL)
    if (!is.null(fs)) loglik <- tryCatch(round(summary(fs)$logtest$pvalue, 4), error = function(e) NA_real_)
  }
  cols <- c("Inflection point", "Adjusted HR", "95% CI", "P-value")
  rows <- lapply(seq_len(n), function(i) {
    ex <- sl[[i]]; lb <- .scq05_lbl(br, i, n); miss <- "\u2014"
    if (is.null(ex)) c(lb, miss, miss, miss) else c(lb, as.character(ex$hr), paste0("(", ex$ci_lo, ", ", ex$ci_hi, ")"), as.character(ex$p))
  })
  lp <- if (!is.finite(loglik) || loglik < 1e-4) "< 0.0001" else as.character(loglik)
  tb <- as.data.frame(do.call(rbind, c(rows, list(c("Log-likelihood ratio", "", "", lp)))), stringsAsFactors = FALSE)
  colnames(tb) <- cols
  caption <- paste0("Segmented Cox (quintile) of ", idx, " and ", cfg$project$disease %||% "Outcome")
  if (is.null(bl$table_filename) || !nzchar(bl$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", caption, "xlsx")
    title <- pub$title
    fp <- pub$filepath
  } else {
    title <- pub_title(ctx, "supp_table", caption)
    fp <- file.path(ctx$output_dir_tables, bl$table_filename)
  }
  tryCatch(export_sci_table(tb, fp, title = title, latex_include_colnames = TRUE, latex_align = "lccc"), error = function(e) NULL)
  ctx$results$segmented_cox_quintile <- list(breaks = br, segment_results = sl, loglik_p = loglik, covariates = cov, random_search = hit)
  cli::cli_alert_success("segmented_cox_quintile 完成")
  ctx
}
register_block("segmented_cox_quintile", block_segmented_cox_quintile, "五分位外层分段 Cox + Table S4")
