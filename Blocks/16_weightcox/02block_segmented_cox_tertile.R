###############################################################################
#  segmented_cox_tertile — 全样本 index 按三分位切为 3 个外层段（Q1/Q2/Q3，与 cox_tertile 一致）；
#                           每段内 mean/median 再二分 index → high vs low，分层 Cox 得 3 行 HR；
#                           全样本连续 index + 同一套协变量做 segmented()（2 个 psi = 两个断点）。
#                           不含 cutoff 图、KM、二次 baseline RData。
#
#  register_block: "segmented_cox_tertile"
#  典型流水线: … → multicollinearity → cox_tertile → segmented_cox_tertile
#              （勿与 segmented_cox_binary 同一次分析混跑；三分位断点来自 10_cox，非 RCS 单 cutoff）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_cox         = 须先 run_block(ctx, "cox_tertile")
#                        ctx$results$cox_grouping$method == "tertile" 且 n_groups == 3
#  时间/事件/暴露      = config$survival$time_var / event_var / index_var
#  外层断点（2 个）    = ctx$results$cox_index_breaks（cox_tertile 写入）
#                        或全样本 quantile(index, probs = c(1/3, 2/3))
#  HR 方向 anchor      = ctx$results$cox_highest_group_model2_hr（cox_tertile Table2 Model2 最高档，通常 Q3）；
#                        无有效 HR 时 require_hr_direction="auto" 下不卡方向
#  协变量池（搜索用）  = random_covariate_search$pool 或 ctx$results$Model2Factors
#
#  # ── 配置 config$segmented_cox_tertile ───────────────────────────────────────
#  segmented_cox_tertile = list(
#    require_cox_method   = "tertile",   # 与 ctx$results$cox_grouping$method 校验
#    split_within_stratum = "median",    # 层内 index 二分："mean" | "median"
#    min_segment_n        = 20,
#    min_segment_events   = 5,
#    covariates           = NULL,        # 固定协变量；搜索未命中时用
#    sig_cutoff           = 0.05,        # 无固定/搜索时，单因素 Cox 筛 P 阈值
#    segmented_extra_covariates = NULL,  # 仅追加到 segmented()；NULL=与分层 Cox 同协变量
#    table_filename       = NULL,        # NULL → Table S4. Segmented Cox (tertile) ...
#    random_covariate_search = list(
#      enable                    = FALSE,
#      require_hr_direction      = "auto",  # auto|none
#      max_outer_attempts        = 1000L,   # 外层：未命中则抽样协变量个数递增
#      max_inner_attempts        = 1000L,   # 内层：随机抽协变量组合
#      initial_factors_n       = 1L,
#      pool                      = NULL,    # NULL → Model2Factors
#      high_stratum_p_max        = 0.05,    # 仅判最高外层段（第 3 段 / Q3 区间）
#      high_stratum_min_hr       = 1,
#      both_strata_significance_use_p_only = FALSE,
#      seed                      = NULL
#    ),
#    pause_enable             = TRUE,
#    pause_on_cox_mismatch    = TRUE       # 未先跑 cox_tertile 时 pause
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$segmented_cox_tertile（breaks, segment_results, loglik_p, table, …）
#      Tables/Table S4. Segmented Cox (tertile) of <index> and <disease>.xlsx
#      Table 共 3 行 HR（Q1/Q2/Q3 各段层内 high vs low）+ 1 行 Log-likelihood ratio
#  不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
#
#  源: 与 segmented_cox_binary 同框架；外层切点对齐 Blocks/10_cox/02block_cox_tertile.R
#  依赖: survival, segmented
###############################################################################

.sct02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.sct02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "segmented_cox_tertile", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: segmented_cox_tertile — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.sct02_coerce_event_01 <- function(x, cfg, evname) {
  if (is.numeric(x)) {
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
    stop("segmented_cox_tertile: ", evname, " 非 0/1")
  }
  if (is.logical(x)) return(as.integer(x))
  ana <- trimws(cfg$project$analysis_group %||% "")
  if (!nzchar(ana)) stop("segmented_cox_tertile: 需 analysis_group")
  xc <- trimws(as.character(x))
  out <- rep(NA_integer_, length(xc))
  ok <- !is.na(xc) & nzchar(xc)
  out[ok & (xc == ana | tolower(xc) == tolower(ana))] <- 1L
  out[ok & !(xc == ana | tolower(xc) == tolower(ana))] <- 0L
  out
}

.sct02_regex_escape <- function(x) gsub("([][{}()^$.|?*+\\\\])", "\\\\\\1", x, perl = TRUE)

.sct02_extract_high_vs_low <- function(fit, index_var) {
  if (is.null(fit)) return(NULL)
  b <- tryCatch(stats::coef(fit), error = function(e) NULL)
  if (is.null(b) || !length(b)) return(NULL)
  nm <- names(b); if (is.null(nm)) nm <- "coef1"
  esc <- .sct02_regex_escape(index_var)
  ig <- grep(paste0("^", esc, "high$"), nm, ignore.case = TRUE, perl = TRUE)[1L]
  if (is.na(ig)) ig <- grep("high$", nm, ignore.case = TRUE, perl = TRUE)[1L]
  if (is.na(ig) && length(nm) == 1L) ig <- 1L
  if (is.na(ig)) return(NULL)
  # conf.int must be numeric (0.95); TRUE coerces to 1 → 100% CI → (0, Inf)
  s <- tryCatch(summary(fit, conf.int = 0.95), error = function(e) NULL)
  if (is.null(s)) return(NULL)
  co <- s$coefficients; ci <- s$conf.int
  ig2 <- ig
  if (!is.null(rownames(co))) {
    ig2 <- grep(paste0("^", esc, "high$"), rownames(co), ignore.case = TRUE, perl = TRUE)[1L]
    if (is.na(ig2)) ig2 <- ig
  }
  pcol <- grep("^Pr\\(", colnames(co), perl = TRUE)[1L]
  if (is.na(pcol)) pcol <- ncol(co)
  hr <- ci[ig2, grep("exp\\(coef\\)", colnames(ci), perl = TRUE)[1L], drop = TRUE]
  lo <- ci[ig2, grep("lower", colnames(ci), perl = TRUE)[1L], drop = TRUE]
  hi <- ci[ig2, grep("upper", colnames(ci), perl = TRUE)[1L], drop = TRUE]
  pv <- co[ig2, pcol, drop = TRUE]
  if (!all(is.finite(c(hr, lo, hi)))) return(NULL)
  list(hr = round(hr, 3), ci_lo = round(lo, 3), ci_hi = round(hi, 3),
       p = if (is.finite(pv)) round(pv, 4) else NA_real_)
}

.sct02_dichotomize <- function(v, split_mode) {
  split_mode <- tolower(as.character(split_mode)[1L])
  if (!split_mode %in% c("mean", "median")) split_mode <- "mean"
  fn <- if (split_mode == "median") stats::median else base::mean
  ok <- is.finite(v)
  if (sum(ok) < 2L) return(rep(NA_character_, length(v)))
  spl <- fn(v[ok], na.rm = TRUE)
  bin <- ifelse(!ok, NA_character_, ifelse(v >= spl, "high", "low"))
  if (length(unique(stats::na.omit(bin))) >= 2L) return(bin)
  r <- rank(v, ties.method = "average", na.last = "keep")
  ifelse(!ok, NA_character_, ifelse(r > stats::median(r[ok], na.rm = TRUE), "high", "low"))
}

.sct02_segment_subset <- function(dat, idx, breaks, seg_i, n_seg) {
  x <- dat[[idx]]
  if (seg_i == 1L) return(dat[x < breaks[1], , drop = FALSE])
  if (seg_i == n_seg) return(dat[x >= breaks[seg_i - 1L], , drop = FALSE])
  dat[x >= breaks[seg_i - 1L] & x < breaks[seg_i], , drop = FALSE]
}

.sct02_segment_label <- function(breaks, seg_i, n_seg, lv) {
  if (seg_i == 1L) return(paste0("< ", round(breaks[1], 2)))
  if (seg_i == n_seg) return(paste0("\u2265 ", round(breaks[n_seg - 1L], 2)))
  paste0(round(breaks[seg_i - 1L], 2), " \u2013 ", round(breaks[seg_i], 2))
}

.sct02_run_one_segment <- function(dat, idx, breaks, seg_i, n_seg, fac, time_v, event_v, split_mode, min_n, min_ev) {
  tmp <- .sct02_segment_subset(dat, idx, breaks, seg_i, n_seg)
  if (nrow(tmp) < min_n) return(NULL)
  if (sum(tmp[[event_v]] == 1L, na.rm = TRUE) < min_ev) return(NULL)
  tmp[[idx]] <- factor(.sct02_dichotomize(tmp[[idx]], split_mode), levels = c("low", "high"))
  if (nlevels(droplevels(tmp[[idx]])) < 2L) return(NULL)
  fac <- intersect(as.character(fac), names(tmp))
  rhs <- if (length(fac)) paste(fac, collapse = " + ") else NULL
  fml <- if (length(rhs)) {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx, " + ", rhs))
  } else {
    stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", idx))
  }
  fit <- tryCatch(survival::coxph(fml, data = stats::na.omit(tmp)), error = function(e) NULL)
  .sct02_extract_high_vs_low(fit, idx)
}

.sct02_run_all_segments <- function(dat, idx, breaks, n_seg, fac, time_v, event_v, split_mode, min_n, min_ev) {
  # 勿用 out[[i]] <- NULL：在 R 中会删除列表元素而非存入 NULL
  out <- lapply(seq_len(n_seg), function(i) {
    .sct02_run_one_segment(dat, idx, breaks, i, n_seg, fac, time_v, event_v, split_mode, min_n, min_ev)
  })
  names(out) <- paste0("seg", seq_len(n_seg))
  out
}

.sct02_parse_anchor <- function(ctx) {
  raw <- ctx$results$cox_highest_group_model2_hr
  hr <- suppressWarnings(as.numeric(if (length(raw)) raw[[1L]] else NA_real_))
  if (length(hr) == 1L && is.finite(hr)) {
    return(list(hr = hr, level = ctx$results$cox_highest_group_level))
  }
  cg <- ctx$results$cox_grouping
  rt <- ctx$results$cox_hr
  if (is.null(cg) || is.null(rt)) return(list(hr = NA_real_, level = NA_character_))
  glv <- cg$group_levels
  top <- glv[length(glv)]
  df <- as.data.frame(rt, stringsAsFactors = FALSE)
  if (ncol(df) < 10L) return(list(hr = NA_real_, level = top))
  idx <- which(trimws(as.character(df[[1L]])) == as.character(top))
  hr2 <- if (length(idx)) suppressWarnings(as.numeric(df[[10L]][idx[1L]])) else NA_real_
  list(hr = if (is.finite(hr2)) hr2 else NA_real_, level = top)
}

.sct02_hr_ok <- function(hr, anchor_hr, rs_cfg) {
  mode <- tolower(as.character(rs_cfg$require_hr_direction %||% "auto")[1L])
  if (mode == "none") return(TRUE)
  anchor_hr <- suppressWarnings(as.numeric(anchor_hr[1L]))
  use <- is.finite(anchor_hr) && abs(anchor_hr - 1) > 1e-8
  if (mode == "auto" && !use) return(TRUE)
  if (!is.finite(hr)) return(FALSE)
  if (use) if (anchor_hr > 1) hr > 1 else hr < 1 else hr > as.numeric(rs_cfg$high_stratum_min_hr %||% 1)
}

.sct02_highest_ok <- function(seg_list, p_cut, anchor_hr, rs_cfg) {
  rh <- seg_list[[length(seg_list)]]
  if (is.null(rh) || !is.finite(rh$p) || rh$p >= p_cut) return(FALSE)
  p_only <- isTRUE(rs_cfg$both_strata_significance_use_p_only %||% FALSE)
  if (p_only) return(TRUE)
  .sct02_hr_ok(rh$hr, anchor_hr, rs_cfg)
}

.sct02_nested_search <- function(dat, idx, breaks, n_seg, time_v, event_v, pool, rs_cfg, min_n, min_ev, split_mode, anchor_hr) {
  max_outer <- as.integer(rs_cfg$max_outer_attempts %||% 1000L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 1000L)
  k_start <- max(1L, as.integer(rs_cfg$initial_factors_n %||% 1L))
  p_max <- as.numeric(rs_cfg$high_stratum_p_max %||% 0.05)
  pool <- intersect(as.character(pool), names(dat))
  if (!length(pool)) return(NULL)
  if (!is.null(rs_cfg$seed)) set.seed(as.integer(rs_cfg$seed))
  best <- NULL
  attempt <- 0L
  k_fac <- k_start
  while (attempt < max_outer) {
    inner <- 0L
    hit <- FALSE
    while (inner < max_inner && !hit) {
      k_use <- min(k_fac, length(pool))
      fac <- sample(pool, k_use, replace = FALSE)
      seg_res <- .sct02_run_all_segments(dat, idx, breaks, n_seg, fac, time_v, event_v, split_mode, min_n, min_ev)
      if (.sct02_highest_ok(seg_res, p_max, anchor_hr, rs_cfg)) {
        best <- list(segments = seg_res, factors = fac)
        hit <- TRUE
        break
      }
      inner <- inner + 1L
    }
    if (hit) break
    k_fac <- k_fac + 1L
    attempt <- attempt + 1L
  }
  best
}

.sct02_get_breaks <- function(ctx, data, index_var, bl_cfg) {
  cg <- ctx$results$cox_grouping %||% list()
  req <- bl_cfg$require_cox_method %||% "tertile"
  if (!identical(cg$method, req) || (cg$n_groups %||% 0L) != 3L) {
    if (.sct02_should_pause(bl_cfg, "pause_on_cox_mismatch", TRUE)) {
      .sct02_pause(ctx, paste0("需先运行 cox_", req), paste0("run_block(ctx, 'cox_", req, "')"))
    }
    cli::cli_alert_warning("cox_grouping 非 {req}，将按全样本 quantile 重算断点")
  }
  br <- ctx$results$cox_index_breaks
  if (!is.null(br) && length(br) >= 2L) {
    return(as.numeric(br)[seq_len(2L)])
  }
  as.numeric(stats::quantile(data[[index_var]], probs = c(1/3, 2/3), na.rm = TRUE))
}

.sct02_loglik <- function(dat, idx, time_v, event_v, cov, psi_breaks, extra) {
  extra <- intersect(as.character(extra %||% character(0)), names(dat))
  cov <- intersect(as.character(cov), names(dat))
  rhs <- unique(c(idx, cov, extra))
  fml <- stats::as.formula(paste0("Surv(", time_v, ", ", event_v, ") ~ ", paste(rhs, collapse = " + ")))
  fit <- tryCatch(survival::coxph(fml, data = dat), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  fit_seg <- tryCatch(
    segmented::segmented(fit, seg.Z = stats::as.formula(paste0("~ ", idx)),
                         psi = stats::setNames(list(as.numeric(psi_breaks)), idx)),
    error = function(e) NULL
  )
  if (is.null(fit_seg)) return(NA_real_)
  tryCatch(round(summary(fit_seg)[["logtest"]][["pvalue"]], 4), error = function(e) NA_real_)
}

.sct02_fmt <- function(lbl, ex) {
  miss <- "\u2014"
  if (is.null(ex)) return(c(lbl, miss, miss, miss))
  c(lbl, as.character(ex$hr), paste0("(", ex$ci_lo, ", ", ex$ci_hi, ")"),
    if (is.finite(ex$p)) as.character(ex$p) else miss)
}

.sct02_select_sig <- function(dat, time_v, event_v, idx, p_thr) {
  cand <- names(dat)[vapply(names(dat), function(v) {
    is.numeric(dat[[v]]) && stats::sd(dat[[v]], na.rm = TRUE) > 0 && !(v %in% c(time_v, event_v, idx))
  }, logical(1L))]
  sig <- character(0)
  for (v in cand) {
    fit <- tryCatch(survival::coxph(stats::as.formula(paste0("Surv(", time_v, ",", event_v, ")~", v)), data = dat), error = function(e) NULL)
    if (!is.null(fit) && is.finite(summary(fit)$coefficients[1, "Pr(>|z|)"]) &&
        summary(fit)$coefficients[1, "Pr(>|z|)"] < p_thr) sig <- c(sig, v)
  }
  sig
}

block_segmented_cox_tertile <- function(ctx, time_var = NULL, event_var = NULL, index_var = NULL, ...) {
  suppressPackageStartupMessages({ library(survival); library(segmented) })
  cfg <- ctx$config
  bl_cfg <- cfg$segmented_cox_tertile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) .sct02_pause(ctx, "无数据", "先跑 imputation")

  surv <- cfg$survival %||% list()
  time_var <- time_var %||% surv$time_var %||% "futime"
  event_var <- event_var %||% surv$event_var %||% "fustatus"
  index_var <- index_var %||% surv$index_var %||% (cfg$logistic %||% list())$index_var
  data[[event_var]] <- as.numeric(.sct02_coerce_event_01(data[[event_var]], cfg, event_var))

  n_seg <- 3L
  breaks <- .sct02_get_breaks(ctx, data, index_var, bl_cfg)
  min_n <- as.integer(bl_cfg$min_segment_n %||% 20L)
  min_ev <- as.integer(bl_cfg$min_segment_events %||% 5L)
  split_mode <- bl_cfg$split_within_stratum %||% "median"
  sig_cut <- as.numeric(bl_cfg$sig_cutoff %||% 0.05)
  rs_cfg <- if (is.list(bl_cfg$random_covariate_search)) bl_cfg$random_covariate_search else list()
  anchor <- .sct02_parse_anchor(ctx)

  search_hit <- NULL
  if (isTRUE(rs_cfg$enable %||% FALSE)) {
    pool <- rs_cfg$pool %||% ctx$results$Model2Factors %||% character(0)
    pool <- setdiff(pool, c(time_var, event_var, index_var))
    search_hit <- .sct02_nested_search(
      stats::na.omit(data[, unique(c(time_var, event_var, index_var, pool)), drop = FALSE]),
      index_var, breaks, n_seg, time_var, event_var, pool, rs_cfg, min_n, min_ev, split_mode, anchor$hr
    )
  }

  cov <- bl_cfg$covariates %||% NULL
  if (!is.null(search_hit)) cov <- search_hit$factors
  if (is.null(cov) || !length(cov)) cov <- .sct02_select_sig(data, time_var, event_var, index_var, sig_cut)
  cov <- intersect(as.character(cov), names(data))

  ad <- stats::na.omit(data[, c(time_var, event_var, index_var, cov), drop = FALSE])
  seg_res <- if (!is.null(search_hit)) search_hit$segments else .sct02_run_all_segments(ad, index_var, breaks, n_seg, cov, time_var, event_var, split_mode, min_n, min_ev)

  loglik_p <- .sct02_loglik(ad, index_var, time_var, event_var, cov, breaks, bl_cfg$segmented_extra_covariates)

  cols <- c("Inflection point", "Adjusted HR", "95% CI", "P-value")
  rows <- lapply(seq_len(n_seg), function(i) {
    .sct02_fmt(.sct02_segment_label(breaks, i, n_seg), seg_res[[i]])
  })
  line04_p <- if (!is.finite(loglik_p) || loglik_p < 0.0001) "< 0.0001" else as.character(loglik_p)
  tb_body <- as.data.frame(do.call(rbind, c(rows, list(c("Log-likelihood ratio", "", "", line04_p)))), stringsAsFactors = FALSE)
  colnames(tb_body) <- cols
  hdr <- as.data.frame(t(cols), stringsAsFactors = FALSE); colnames(hdr) <- cols
  tb_display <- rbind(hdr, tb_body)

  disease <- cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  caption <- paste0("Segmented Cox (tertile) of ", index_var, " and ", disease)
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", caption, "xlsx")
    title <- pub$title
    fp <- pub$filepath
  } else {
    title <- pub_title(ctx, "supp_table", caption)
    fp <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  tryCatch(export_sci_table(tb_body, fp, title = title, latex_include_colnames = TRUE, latex_align = "lccc"),
           error = function(e) cli::cli_alert_warning("export 失败: {e$message}"))

  ctx$results$segmented_cox_tertile <- list(
    breaks = breaks, n_segments = n_seg, covariates = cov,
    segment_results = seg_res, loglik_p = loglik_p, table = tb_display,
    random_search = search_hit, anchor_hr = anchor$hr
  )
  cli::cli_alert_success("segmented_cox_tertile 完成")
  ctx
}

register_block("segmented_cox_tertile", block_segmented_cox_tertile,
               "三分位外层分段 Cox + Table S4")
