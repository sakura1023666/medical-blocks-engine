###############################################################################
#  trajectory_jlcm — JLCM 联合轨迹模型拟合：宽转长→合并生存/协变量→gridsearch→IC表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed_with_id %||% ctx$data$imputed   # pipeline 决定，块内不选源
#  require_pkg  = lcmm, survival, splines, dplyr, tidyr, stringr, cli
#
#  trajectory_jlcm = list(
#    index_vars            = c("BAR"),
#    class_range           = 2:8,
#    rawdata_path_template = "RawData/12_{Index}.RData",
#    rawdata_obj           = "index_df",
#    id_column             = NULL,
#    non_na_col            = "non_na_count",
#    time_col_start        = 2L,
#    time_col_end          = 29L,
#    time_col_sep          = "_",
#    outlier_quantiles     = c(0.01, 0.99),
#    value_transform       = "none",
#    survival_time_var     = NULL,                  # NULL → config$survival$time_var
#    survival_event_var    = NULL,                  # NULL → config$survival$event_var
#    max_followup          = 28,
#    covariate_vars        = character(0),          # 手动指定的协变量（追加）
#    covariate_vars_from_vif = FALSE,                # TRUE → 并入 ctx$results$Model1Factors ∪ Model2Factors
#    dual_db_harmonize_survival_covariates = TRUE,   # batch 双库：VIF final 交集后共用 survival 协变量
#    dual_db_shared_covariates = FALSE,              # 运行时标记：已由 batch worker 注入共有列表
#    survival_covariate_max  = 5L,                   # survival 公式最多协变量数
#    survival_covariate_continuous_only = TRUE,        # 仅连续变量进入 survival 子模型
#    spline_df             = 2L,
#    hazard                = "Weibull",
#    hazardtype            = "Specific",
#    gridsearch_rep        = 50L,
#    gridsearch_maxiter    = 10L,
#    gridsearch_refit_on_health_fail = TRUE,         # LL 非单调/空类 → 自动加大 gridsearch 重拟合（.tfj02_jlcm_health_guard）
#    gridsearch_refit_rep_cap        = 200L,          # 重拟合 rep 上限
#    gridsearch_refit_maxiter        = 40L,           # 重拟合 maxiter
#    adaptive_class_cap    = TRUE,                   # TRUE → 按 n_subj 自动封顶 class_range
#    adaptive_class_cap_n_threshold = 1000L,         # n_subj < 阈值 → max_ng_low；否则 max_ng_high
#    adaptive_class_cap_ng_low  = 4L,
#    adaptive_class_cap_ng_high = 6L,
#    prefer_final_ng       = 2L,                     # 供下游图表/表格默认取用的类别数
#    assign_class_ng       = NULL,                   # NULL → 用 prefer_final_ng；把该 ng 的类别写回 ctx$data$imputed$trajectory_class
#    stop_on_ng1_fail       = TRUE,                   # ng=1 拟合失败/未收敛 → stop() 终止后续 block
#    stop_on_ng2_fail       = FALSE,                  # ng=2 拟合失败/未收敛 → stop() 终止后续 block
#    stop_on_no_output      = TRUE,                   # 无 trajectory_long 输出 → stop()（批量避免仅插补图仍标 success）
#    pause_enable          = TRUE,
#    pause_on_missing_survival = TRUE
#  ),
#
#  register_block: "trajectory_jlcm"
#  写: ctx$data$trajectory_long, ctx$data$imputed/cleaned 新增 trajectory_class 列，
#      ctx$results$trajectory_jlcm_models, ctx$results$trajectory_ic_table
#  落盘: Data/D01_long_{Index}_D_{D}.RData, Data/D01_jlcm_{Index}_models.RData,
#        Tables/Table_Trajectory_IC_JLCM.xlsx
#
#  协变量说明：covariate_vars（∪ VIF 最终协变量，若 covariate_vars_from_vif=TRUE）仅进入
#  survival 子模型（survival = Surv(surv_time, surv_event) ~ 协变量），用于调整组别特异性
#  风险；fixed/random/mixture 仍只含时间样条，不含协变量（与 Ye 2024 文献一致）。
###############################################################################

.tfj02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tfj02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block         = "trajectory_jlcm",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tfj02_stop_jlcm <- function(reason, bl_cfg) {
  if (isTRUE(bl_cfg$pause_enable %||% FALSE)) {
    stop(
      "PAUSE_FOR_USER_DECISION: ", reason,
      call. = FALSE
    )
  }
  stop(reason, call. = FALSE)
}

.tfj02_ng1_ok <- function(m1) {
  !is.null(m1) && is.list(m1) && isTRUE((m1$conv %||% NA_integer_) == 1L)
}

.tfj02_resolve_path <- function(p) {
  if (grepl("^(/|[A-Za-z]:[/\\\\])", p)) p else file.path(getwd(), p)
}

# rawdata_obj 未匹配时，回退加载该 RData 中第一个 data.frame 对象（容错，对齐用户脚本习惯）
.tfj02_load_rawdata_obj <- function(raw_path, rawdata_obj) {
  e_raw <- new.env(parent = emptyenv())
  obj_names <- load(raw_path, envir = e_raw)
  if (rawdata_obj %in% obj_names) {
    df <- get(rawdata_obj, envir = e_raw)
    if (is.data.frame(df)) return(df)
  }
  for (nm in obj_names) {
    obj <- get(nm, envir = e_raw)
    if (is.data.frame(obj)) {
      cli::cli_alert_warning(
        "rawdata_obj='{rawdata_obj}' 未找到，回退使用 RData 中第一个 data.frame 对象 '{nm}'"
      )
      return(obj)
    }
  }
  NULL
}

# 按 n_subj 自适应封顶最大类别数（<阈值→ng_low，否则→ng_high）
.tfj02_adaptive_max_ng <- function(n_subj, enable, threshold, ng_low, ng_high) {
  if (!isTRUE(enable)) return(Inf)
  if (n_subj < threshold) ng_low else ng_high
}

# survival 子模型协变量：仅连续型，最多 max_n 个（优先单因素 P 值最小）
.tfj02_is_continuous_col <- function(x, min_unique = 3L) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(FALSE)
  if (is.numeric(x) || is.integer(x)) {
    ux <- unique(x[!is.na(x) & is.finite(x)])
    return(length(ux) >= min_unique)
  }
  nx <- suppressWarnings(as.numeric(as.character(x)))
  ux <- unique(nx[!is.na(nx) & is.finite(nx)])
  length(ux) >= min_unique
}

.tfj02_coerce_numeric_col <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.numeric(x))
  suppressWarnings(as.numeric(as.character(x)))
}

.tfj02_rank_covariates_by_univar <- function(vars, ctx) {
  univar <- ctx$results$univar_coef
  if (is.null(univar) || !is.data.frame(univar) || !"P" %in% names(univar)) return(vars)
  p_map <- stats::setNames(as.numeric(univar$P), as.character(univar$Variable))
  scores <- vapply(vars, function(v) {
    if (v %in% names(p_map)) return(p_map[[v]])
    hits <- p_map[startsWith(names(p_map), v)]
    if (length(hits)) min(hits, na.rm = TRUE) else NA_real_
  }, numeric(1))
  vars[order(ifelse(is.finite(scores), scores, Inf), vars)]
}

.tfj02_select_survival_covariates <- function(d, candidates, ctx, bl_cfg) {
  root <- ctx$config$project$root %||% getwd()
  util <- file.path(root, "R/trajectory_survival_utils.R")
  if (file.exists(util)) source(util, local = FALSE)
  if (exists("trajectory_select_survival_covariates", mode = "function")) {
    res <- trajectory_select_survival_covariates(
      d, candidates, ctx, list(trajectory_jlcm = bl_cfg)
    )
    if (length(res$dropped_non_continuous)) {
      show <- res$dropped_non_continuous
      if (length(show) > 8L) show <- c(head(show, 8L), "...")
      cli::cli_alert_warning(
        "JLCM survival 排除非连续协变量 ({length(res$dropped_non_continuous)} 个): {paste(show, collapse=', ')}"
      )
    }
    if (length(res$dropped_extra)) {
      cli::cli_alert_info(
        "JLCM survival 协变量截断至 {res$max_n} 个（单因素 P 优先）: {paste(res$vars, collapse=', ')}"
      )
      show <- res$dropped_extra
      if (length(show) > 8L) show <- c(head(show, 8L), "...")
      cli::cli_alert_info("  未纳入 survival 公式: {paste(show, collapse=', ')}")
    } else if (length(res$vars)) {
      msg <- if (isTRUE(bl_cfg$dual_db_shared_covariates)) {
        "JLCM survival 协变量（双库共有，{length(res$vars)} 个）: {paste(res$vars, collapse=', ')}"
      } else {
        "JLCM survival 协变量（{length(res$vars)} 个连续）: {paste(res$vars, collapse=', ')}"
      }
      cli::cli_alert_info(msg)
    } else {
      cli::cli_alert_warning("JLCM survival 无可用连续协变量，使用 Surv(...) ~ 1")
    }
    return(list(
      data = res$data,
      vars = res$vars,
      dropped_non_continuous = res$dropped_non_continuous
    ))
  }

  max_n <- suppressWarnings(as.integer(bl_cfg$survival_covariate_max %||% 5L)[1L])
  if (!is.finite(max_n) || max_n < 1L) max_n <- 5L
  continuous_only <- isTRUE(bl_cfg$survival_covariate_continuous_only %||% TRUE)

  candidates <- unique(as.character(candidates))
  candidates <- candidates[nzchar(candidates)]
  candidates <- intersect(candidates, names(d))

  dropped_non_cont <- character(0)
  cont_vars <- character(0)
  for (v in candidates) {
    if (continuous_only && !.tfj02_is_continuous_col(d[[v]])) {
      dropped_non_cont <- c(dropped_non_cont, v)
      next
    }
    cont_vars <- c(cont_vars, v)
  }

  if (length(dropped_non_cont)) {
    show <- dropped_non_cont
    if (length(show) > 8L) show <- c(head(show, 8L), "...")
    cli::cli_alert_warning(
      "JLCM survival 排除非连续协变量 ({length(dropped_non_cont)} 个): {paste(show, collapse=', ')}"
    )
  }

  cont_vars <- .tfj02_rank_covariates_by_univar(cont_vars, ctx)
  if (length(cont_vars) > max_n) {
    dropped_extra <- cont_vars[(max_n + 1L):length(cont_vars)]
    cont_vars <- cont_vars[seq_len(max_n)]
    cli::cli_alert_info(
      "JLCM survival 协变量截断至 {max_n} 个（单因素 P 优先）: {paste(cont_vars, collapse=', ')}"
    )
    if (length(dropped_extra)) {
      cli::cli_alert_info("  未纳入 survival 公式: {paste(head(dropped_extra, 8), collapse=', ')}")
    }
  } else if (length(cont_vars)) {
    cli::cli_alert_info(
      "JLCM survival 协变量（{length(cont_vars)} 个连续）: {paste(cont_vars, collapse=', ')}"
    )
  } else {
    cli::cli_alert_warning("JLCM survival 无可用连续协变量，使用 Surv(...) ~ 1")
  }

  for (v in cont_vars) d[[v]] <- .tfj02_coerce_numeric_col(d[[v]])
  list(data = d, vars = cont_vars, dropped_non_continuous = dropped_non_cont)
}

.tfj02_build_survival_formula <- function(cov_vars_avail) {
  if (!length(cov_vars_avail)) {
    return(stats::as.formula("Surv(surv_time, surv_event) ~ 1"))
  }
  rhs <- paste(cov_vars_avail, collapse = " + ")
  stats::as.formula(paste0("Surv(surv_time, surv_event) ~ ", rhs))
}

.tfj02_fit_jointlcmm <- function(data, spline_df, cov_vars_avail, hazard, hazardtype, ng,
                                 verbose = FALSE) {
  args <- list(
    fixed = stats::as.formula(paste0("scr_std ~ ns(time_day, df=", spline_df, ")")),
    random = stats::as.formula(paste0("~ ns(time_day, df=", spline_df, ")")),
    subject = "subject_id_num",
    data = data,
    survival = .tfj02_build_survival_formula(cov_vars_avail),
    hazard = hazard,
    hazardtype = hazardtype,
    ng = as.integer(ng),
    verbose = verbose
  )
  if (as.integer(ng) > 1L) {
    args$mixture <- stats::as.formula(paste0("~ ns(time_day, df=", spline_df, ")"))
  }
  do.call(lcmm::Jointlcmm, args)
}

.tfj02_unwrap_jointlcmm <- function(m) {
  if (inherits(m, "Jointlcmm")) return(m)
  if (is.list(m) && inherits(m$best, "Jointlcmm")) return(m$best)
  m
}

.tfj02_jlcm_conv_ok <- function(m) {
  obj <- .tfj02_unwrap_jointlcmm(m)
  if (is.null(obj) || !is.list(obj)) return(FALSE)
  isTRUE((obj$conv %||% NA_integer_) == 1L)
}

.tfj02_gridsearch_jointlcmm <- function(data, spline_df, cov_vars_avail, hazard, hazardtype,
                                        ng, minit, gs_rep, gs_maxiter) {
  # gridsearch 内部 do.call(..., envir=parent.frame())，须在 globalenv 绑定 data/minit
  data_sym <- ".__jlcm_gs_data__"
  minit_sym <- ".__jlcm_gs_minit__"
  assign(data_sym, data, envir = .GlobalEnv)
  assign(minit_sym, minit, envir = .GlobalEnv)
  on.exit(rm(list = c(data_sym, minit_sym), envir = .GlobalEnv), add = TRUE)

  surv_rhs <- if (length(cov_vars_avail)) paste(cov_vars_avail, collapse = " + ") else "1"
  mixture_txt <- if (ng > 1L) sprintf("mixture = ~ ns(time_day, df = %d), ", spline_df) else ""
  gs_txt <- sprintf(
    paste0(
      "gridsearch(m = Jointlcmm(",
      "fixed = scr_std ~ ns(time_day, df = %d), ",
      "random = ~ ns(time_day, df = %d), %s",
      "subject = \"subject_id_num\", data = %s, ",
      "survival = Surv(surv_time, surv_event) ~ %s, ",
      "hazard = \"%s\", hazardtype = \"%s\", ng = %d, verbose = FALSE), ",
      "rep = %d, maxiter = %d, minit = %s)"
    ),
    spline_df, spline_df, mixture_txt, data_sym, surv_rhs,
    hazard, hazardtype, ng, gs_rep, gs_maxiter, minit_sym
  )
  out <- eval(parse(text = gs_txt), envir = .GlobalEnv)
  if (!is.list(out) || is.null(out$conv)) {
    stop("gridsearch 未返回有效 Jointlcmm 对象", call. = FALSE)
  }
  out
}

# ── JLCM 健康守卫：高阶模型 Log-likelihood 非单调 / 空类 → 自动加大 gridsearch 重拟（审稿必查）──
.tfj02_model_props_min <- function(m) {
  pp <- tryCatch(as.data.frame(m$pprob), error = function(e) NULL)
  if (is.null(pp) || !"class" %in% names(pp)) return(NA_real_)
  tab <- prop.table(table(factor(as.integer(pp$class), levels = seq_len(m$ng))))
  suppressWarnings(min(as.numeric(tab), na.rm = TRUE))
}

.tfj02_jlcm_health_guard <- function(models_list, data, spline_df, cov_vars_avail,
                                     hazard, hazardtype, gs_rep, gs_maxiter,
                                     refit_enable = TRUE, refit_rep_cap = 200L,
                                     refit_maxiter = 40L) {
  ngs <- suppressWarnings(as.integer(gsub("^m", "", names(models_list)[
    grepl("^m[0-9]+$", names(models_list))])))
  ngs <- sort(ngs[is.finite(ngs)])
  ll <- stats::setNames(numeric(length(ngs)), as.character(ngs))
  for (g in ngs) {
    m <- .tfj02_unwrap_jointlcmm(models_list[[paste0("m", g)]])
    ll[as.character(g)] <- if (is.null(m)) NA_real_ else as.numeric(m$loglik)[1]
  }
  notes <- character(0)
  bad <- integer(0)
  for (i in seq_along(ngs)) {
    if (i == 1L || is.na(ll[i]) || is.na(ll[i - 1L])) next
    if (ll[i] < ll[i - 1L] - 1e-6) bad <- c(bad, ngs[i])
    m <- .tfj02_unwrap_jointlcmm(models_list[[paste0("m", ngs[i])]])
    mp <- .tfj02_model_props_min(m)
    if (is.finite(mp) && mp < 0.005) bad <- c(bad, ngs[i])  # 空/退化类
  }
  bad <- sort(unique(bad))
  if (!length(bad)) {
    return(list(models = models_list, notes = "LL monotone, no empty class", bad = integer(0)))
  }
  notes <- c(notes, paste0("health guard flagged ng=", paste(bad, collapse = ",")))
  if (!isTRUE(refit_enable)) {
    return(list(models = models_list, notes = notes, bad = bad))
  }
  m1 <- .tfj02_unwrap_jointlcmm(models_list[["m1"]])
  for (g in bad) {
    rep2 <- min(as.integer(refit_rep_cap), max(100L, 2L * as.integer(gs_rep)))
    cli::cli_alert_warning("JLCM 守卫：ng={g} LL非单调/空类 → gridsearch 重跑 rep={rep2}, maxiter={refit_maxiter}")
    m2b <- tryCatch(
      .tfj02_gridsearch_jointlcmm(data, spline_df, cov_vars_avail, hazard, hazardtype,
                                  g, m1 %||% models_list[["m1"]], rep2, refit_maxiter),
      error = function(e) {
        cli::cli_alert_danger("JLCM 守卫：ng={g} 重跑失败: {conditionMessage(e)}")
        NULL
      })
    m_old <- .tfj02_unwrap_jointlcmm(models_list[[paste0("m", g)]])
    ll_old <- if (is.null(m_old)) -Inf else as.numeric(m_old$loglik)[1]
    if (!is.null(m2b)) {
      m_new <- .tfj02_unwrap_jointlcmm(m2b)
      ll_new <- as.numeric(m_new$loglik)[1]
      if (is.finite(ll_new) && ll_new >= ll_old) {
        models_list[[paste0("m", g)]] <- m2b
        notes <- c(notes, sprintf("ng=%d refit kept: ll %.1f (was %.1f)", g, ll_new, ll_old))
      } else {
        notes <- c(notes, sprintf("ng=%d refit worse (%.1f < %.1f), kept original", g, ll_new, ll_old))
      }
    }
  }
  list(models = models_list, notes = notes, bad = bad)
}

.tfj02_apply_value_transform <- function(x, method) {
  method <- tolower(method %||% "none")
  switch(method,
    "log1p" = log1p(pmax(x, 0)),
    "yeojohnson" = {
      if (!requireNamespace("car", quietly = TRUE))
        stop("yeojohnson 变换需要 car 包：install.packages('car')")
      x_clean <- x[!is.na(x) & is.finite(x)]
      if (length(x_clean) < 10) return(x)
      lambda <- tryCatch({
        pt <- car::powerTransform(x_clean, family = "yjPower")
        as.numeric(pt$lambda)
      }, error = function(e) 0)
      car::yjPower(x, lambda = lambda, jacobian.adjusted = FALSE)
    },
    "robust" = {
      med <- stats::median(x, na.rm = TRUE)
      iqr <- stats::IQR(x, na.rm = TRUE)
      if (is.na(iqr) || iqr == 0) return(x)
      (x - med) / iqr
    },
    x
  )
}

.tfj02_winsorize <- function(x, probs = c(0.01, 0.99)) {
  q <- stats::quantile(x, probs = probs, na.rm = TRUE)
  x[!is.na(x) & x < q[1]] <- q[1]
  x[!is.na(x) & x > q[2]] <- q[2]
  x
}

.tfj02_wide_to_long <- function(index_df, id_col, time_start, time_end, time_sep,
                                 non_na_col, outlier_q, value_transform) {
  if (non_na_col %in% names(index_df))
    index_df <- index_df[, !names(index_df) %in% non_na_col, drop = FALSE]

  ncols_actual <- ncol(index_df)
  if (time_start > ncols_actual) return(NULL)
  time_end_use <- min(time_end, ncols_actual)
  time_cols    <- names(index_df)[time_start:time_end_use]

  long <- index_df |>
    tidyr::pivot_longer(cols = tidyselect::all_of(time_cols),
                        names_to = "Time", values_to = "Value") |>
    as.data.frame()

  long$Value <- as.numeric(long$Value)
  long$Value[is.infinite(long$Value)] <- NA

  parts        <- stringr::str_split(long$Time, stringr::fixed(time_sep), simplify = TRUE)
  time_numeric <- suppressWarnings(as.numeric(parts[, ncol(parts)]))
  if (all(is.na(time_numeric))) return(NULL)
  long$Time <- time_numeric

  long$Value <- .tfj02_winsorize(long$Value, probs = outlier_q)
  long$Value <- .tfj02_apply_value_transform(long$Value, value_transform)
  long
}

.tfj02_ic_row <- function(m, Index, D, n_subj) {
  m <- .tfj02_unwrap_jointlcmm(m)
  if (is.null(m) || !is.list(m)) return(NULL)
  loglik <- m$loglik %||% NA_real_
  aic    <- m$AIC    %||% NA_real_
  bic    <- m$BIC    %||% NA_real_
  n_params <- if (!is.na(aic) && !is.na(loglik)) (aic + 2 * loglik) / 2 else NA_real_
  sabic  <- if (!is.na(n_params) && !is.na(loglik))
    -2 * loglik + n_params * log((n_subj + 2) / 24) else NA_real_
  entropy <- tryCatch({
    pprob <- as.data.frame(m$pprob)
    prob_cols <- grep("^prob", names(pprob), value = TRUE)
    if (length(prob_cols) == 0 || m$ng == 1) return(1.0)
    P <- as.matrix(pprob[, prob_cols, drop = FALSE])
    P <- pmax(P, .Machine$double.eps)
    round(1 - (-sum(P * log(P), na.rm = TRUE) / (nrow(P) * log(m$ng))), 4)
  }, error = function(e) NA_real_)
  class_props <- tryCatch({
    pprob <- as.data.frame(m$pprob)
    if (is.null(pprob$class) || is.null(m$ng) || m$ng < 1L) return(NULL)
    props <- round(100 * as.numeric(prop.table(table(pprob$class))), 1)
    names(props) <- paste0("Class_", seq_along(props))
    as.list(props)
  }, error = function(e) NULL)
  row <- data.frame(
    Index = Index, D = D, N = n_subj,
    Log_likelihood = round(loglik, 3),
    AIC = round(aic, 3), BIC = round(bic, 3), SABIC = round(sabic, 3),
    Entropy = entropy,
    Conv = m$conv %||% NA_integer_,
    stringsAsFactors = FALSE
  )
  if (!is.null(class_props)) {
    for (cn in names(class_props)) row[[cn]] <- class_props[[cn]]
  }
  row
}

.tfj02_auto_select_ng <- function(ic_df, bl_cfg) {
  if (!isTRUE(bl_cfg$auto_select_class_ng %||% FALSE)) {
    return(as.integer(bl_cfg$assign_class_ng %||% bl_cfg$prefer_final_ng %||% 2L))
  }
  df <- as.data.frame(ic_df)
  if (!nrow(df)) return(2L)
  if ("Conv" %in% names(df)) df <- df[df$Conv %in% c(1L, 1), , drop = FALSE]
  if ("D" %in% names(df)) df <- df[as.integer(df$D) >= 2L, , drop = FALSE]
  if (!nrow(df)) return(2L)
  min_prop <- as.numeric(bl_cfg$min_class_proportion_pct %||% 5)
  min_ent  <- as.numeric(bl_cfg$min_entropy_for_selection %||% 0.3)
  ok <- rep(TRUE, nrow(df))
  for (i in seq_len(nrow(df))) {
    if ("Entropy" %in% names(df) && !is.na(df$Entropy[i]) && df$Entropy[i] < min_ent) ok[i] <- FALSE
    ng <- as.integer(df$D[i])
    cls_cols <- paste0("Class_", seq_len(ng))
    cls_cols <- intersect(cls_cols, names(df))
    if (length(cls_cols)) {
      props <- as.numeric(df[i, cls_cols])
      props <- props[!is.na(props)]
      if (length(props) && min(props) < min_prop) ok[i] <- FALSE
    }
  }
  cand <- df[ok, , drop = FALSE]
  if (!nrow(cand)) cand <- df
  cand <- cand[order(cand$BIC), , drop = FALSE]
  ng_pick <- suppressWarnings(as.integer(cand$D[1L]))
  if (!is.finite(ng_pick)) 2L else ng_pick
}

.tfj02_resolve_fallback_ng <- function(bl_cfg) {
  for (src in list(bl_cfg$assign_class_ng, bl_cfg$prefer_final_ng)) {
    ng <- suppressWarnings(as.integer(src)[1L])
    if (is.finite(ng) && ng >= 1L) return(ng)
  }
  2L
}

.tfj02_write_trajectory_class <- function(ctx, Index, assign_ng, model_data_final,
                                          models_list, id_col) {
  assign_ng <- suppressWarnings(as.integer(assign_ng)[1L])
  if (!is.finite(assign_ng) || assign_ng < 1L) {
    cli::cli_alert_warning("{Index}: assign_ng 无效 ({assign_ng})，跳过 trajectory_class 回写")
    return(ctx)
  }
  m_g_raw <- models_list[[paste0("m", assign_ng)]]
  if (is.null(m_g_raw)) return(ctx)
  m_g <- .tfj02_unwrap_jointlcmm(m_g_raw)
  if (is.null(m_g$pprob)) return(ctx)
  pprob_df <- as.data.frame(m_g$pprob)
  class_assign <- pprob_df[, c("subject_id_num", "class")]
  subj_class <- unique(model_data_final[, c(id_col, "subject_id_num")])
  subj_class <- dplyr::left_join(subj_class, class_assign, by = "subject_id_num")
  subj_class <- subj_class[, c(id_col, "class")]
  names(subj_class)[2] <- "trajectory_class"
  subj_class$trajectory_class <- as.integer(subj_class$trajectory_class)
  idx_col_name <- paste0("trajectory_class_", Index)
  subj_class[[idx_col_name]] <- subj_class$trajectory_class
  for (slot in c("imputed", "cleaned")) {
    if (!is.null(ctx$data[[slot]]) && id_col %in% names(ctx$data[[slot]])) {
      tgt <- ctx$data[[slot]]
      tgt[[id_col]] <- as.character(tgt[[id_col]])
      tgt$trajectory_class <- NULL
      tgt[[idx_col_name]] <- NULL
      tgt <- dplyr::left_join(
        tgt,
        dplyr::mutate(subj_class, !!id_col := as.character(.data[[id_col]])),
        by = id_col
      )
      ctx$data[[slot]] <- tgt
    }
  }
  cli::cli_alert_success(
    "{Index}: ng={assign_ng} 类别已回写 ctx$data$imputed/cleaned$trajectory_class"
  )
  ctx
}

block_trajectory_jlcm <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr); library(tidyr); library(stringr); library(cli)
    library(lcmm); library(survival); library(splines)
  })
  paper_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_paper_tables.R")
  if (file.exists(paper_util)) source(paper_util, local = FALSE)

  cfg    <- ctx$config
  bl_cfg <- cfg$trajectory_jlcm %||% list()

  index_vars  <- bl_cfg$index_vars %||% stop("trajectory_jlcm$index_vars 未配置。")
  class_range <- as.integer(bl_cfg$class_range %||% 2:8)
  rawdata_tpl <- bl_cfg$rawdata_path_template %||%
    stop("trajectory_jlcm$rawdata_path_template 未配置。")
  rawdata_obj   <- bl_cfg$rawdata_obj   %||% "index_df"
  id_col        <- bl_cfg$id_column    %||% cfg$data$id_column %||% "subject_id"
  non_na_col    <- bl_cfg$non_na_col   %||% "non_na_count"
  time_start    <- as.integer(bl_cfg$time_col_start %||% 2L)
  time_end      <- as.integer(bl_cfg$time_col_end   %||% 29L)
  time_sep      <- bl_cfg$time_col_sep %||% "_"
  outlier_q     <- bl_cfg$outlier_quantiles %||% c(0.01, 0.99)
  val_transform <- bl_cfg$value_transform     %||% "none"

  surv_time_var  <- bl_cfg$survival_time_var  %||%
    cfg$survival$time_var  %||%
    stop("trajectory_jlcm$survival_time_var 未配置。")
  surv_event_var <- bl_cfg$survival_event_var %||%
    cfg$survival$event_var %||%
    stop("trajectory_jlcm$survival_event_var 未配置。")
  max_followup   <- as.numeric(bl_cfg$max_followup %||% 28)
  cov_vars_manual <- as.character(bl_cfg$covariate_vars %||% character(0))
  cov_vars_vif    <- if (isTRUE(bl_cfg$covariate_vars_from_vif)) {
    as.character(union(ctx$results$Model1Factors %||% character(0),
                        ctx$results$Model2Factors %||% character(0)))
  } else character(0)
  cov_vars       <- union(cov_vars_manual, cov_vars_vif)
  if (length(cov_vars)) {
    max_cov <- bl_cfg$survival_covariate_max %||% 5L
    cli::cli_alert_info(
      "JLCM 候选协变量（VIF/手动，待筛连续≤{max_cov}）: {paste(cov_vars, collapse=', ')}"
    )
  }
  spline_df      <- as.integer(bl_cfg$spline_df %||% 2L)
  hazard         <- bl_cfg$hazard     %||% "Weibull"
  hazardtype     <- bl_cfg$hazardtype %||% "Specific"
  gs_rep         <- as.integer(bl_cfg$gridsearch_rep     %||% 50L)
  gs_maxiter     <- as.integer(bl_cfg$gridsearch_maxiter %||% 10L)
  adaptive_cap_enable <- if (is.null(bl_cfg$adaptive_class_cap)) TRUE else isTRUE(bl_cfg$adaptive_class_cap)
  adaptive_cap_n_thr  <- as.integer(bl_cfg$adaptive_class_cap_n_threshold %||% 1000L)
  adaptive_cap_ng_low  <- as.integer(bl_cfg$adaptive_class_cap_ng_low  %||% 4L)
  adaptive_cap_ng_high <- as.integer(bl_cfg$adaptive_class_cap_ng_high %||% 6L)
  prefer_final_ng <- as.integer(bl_cfg$prefer_final_ng %||% NA_integer_)
  assign_class_ng <- if (is.null(bl_cfg$assign_class_ng)) NA_integer_ else as.integer(bl_cfg$assign_class_ng)

  .tfj02_coerce_event_01 <- function(x, cfg, evname) {
    if (is.numeric(x) && !is.factor(x)) return(as.integer(x))
    if (is.logical(x)) return(as.integer(x))
    xc <- as.character(x)
    out <- suppressWarnings(as.integer(xc))
    unk <- is.na(out) & !is.na(xc) & nzchar(xc)
    if (any(unk)) {
      case_lbl <- if (exists("pipeline_outcome_case_label", mode = "function")) {
        pipeline_outcome_case_label(cfg)
      } else cfg$project$analysis_group %||% "Non-survivor"
      ref_lbl <- if (exists("pipeline_outcome_reference_label", mode = "function")) {
        pipeline_outcome_reference_label(cfg)
      } else cfg$project$reference_group %||% "Survivor"
      out[unk & xc == case_lbl] <- 1L
      out[unk & xc == ref_lbl] <- 0L
    }
    out
  }

  imputed_data <- ctx$data$imputed_with_id %||% ctx$data$imputed
  valid_ids    <- NULL
  if (!is.null(imputed_data)) {
    root <- ctx$config$project$root %||% getwd()
    if (file.exists(file.path(root, "R/literature_data_utils.R"))) {
      source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
      imputed_data <- literature_ensure_id_column(imputed_data, id_col)
    }
    id_in_imp <- intersect(c(id_col, "ID", "subject_id"), names(imputed_data))[1]
    if (!is.na(id_in_imp)) {
      valid_ids <- unique(as.character(imputed_data[[id_in_imp]]))
      valid_ids <- valid_ids[nzchar(valid_ids)]
      cli::cli_alert_info("筛选有效 subject_id（n = {length(valid_ids)}）")
    }
  } else {
    cli::cli_alert_warning("ctx$data$imputed 为空，不执行 subject_id 过滤")
  }

  if (is.null(ctx$data$trajectory_long)) ctx$data$trajectory_long <- list()
  if (is.null(ctx$results$trajectory_jlcm_models))
    ctx$results$trajectory_jlcm_models <- list()

  data_out_dir <- file.path(ctx$output_dir, "Data")
  if (!dir.exists(data_out_dir)) dir.create(data_out_dir, recursive = TRUE)

  baseline_df <- NULL
  if (!is.null(imputed_data)) {
    need_cols <- unique(c(id_col, surv_time_var, surv_event_var, cov_vars))
    avail     <- intersect(need_cols, names(imputed_data))
    if (length(avail) > 1) {
      baseline_df <- as.data.frame(imputed_data[, avail, drop = FALSE])
      baseline_df[[id_col]] <- as.character(baseline_df[[id_col]])
      if (surv_event_var %in% names(baseline_df)) {
        baseline_df[[surv_event_var]] <- .tfj02_coerce_event_01(
          baseline_df[[surv_event_var]], cfg, surv_event_var
        )
      }
      if (surv_time_var %in% names(baseline_df)) {
        baseline_df[[surv_time_var]] <- suppressWarnings(
          as.numeric(as.character(baseline_df[[surv_time_var]]))
        )
      }
      cli::cli_alert_info(
        "基线数据已提取（{nrow(baseline_df)} 行，列: {paste(avail, collapse=',')}）"
      )
    }
  }
  if (is.null(baseline_df))
    cli::cli_alert_warning("基线数据不可用，生存变量/协变量将从宽格式数据中查找")

  ic_rows <- list()

  for (Index in index_vars) {
    cli::cli_h1("JLCM 拟合: {Index}")
    raw_path <- .tfj02_resolve_path(gsub("\\{Index\\}", Index, rawdata_tpl))
    if (!file.exists(raw_path)) {
      cli::cli_alert_warning("文件不存在，跳过 {Index}: {.file {raw_path}}"); next
    }
    index_df <- .tfj02_load_rawdata_obj(raw_path, rawdata_obj)
    if (is.null(index_df)) {
      cli::cli_alert_warning("对象 '{rawdata_obj}' 不存在且无可用 data.frame 回退，跳过 {Index}"); next
    }
    index_df[[id_col]] <- as.character(index_df[[id_col]])
    if (!is.null(valid_ids) && length(valid_ids))
      index_df <- index_df[index_df[[id_col]] %in% valid_ids, ]
    if (nrow(index_df) == 0) { cli::cli_alert_warning("{Index}: 过滤后无样本"); next }

    long_base <- .tfj02_wide_to_long(index_df, id_col, time_start, time_end, time_sep,
                                      non_na_col, outlier_q, val_transform)
    if (is.null(long_base)) {
      cli::cli_alert_warning("{Index}: 宽转长失败，跳过"); next
    }
    names(long_base)[names(long_base) == "Time"]  <- "time_day"
    names(long_base)[names(long_base) == "Value"] <- "scr_std"

    if (!is.null(baseline_df)) {
      merge_cols <- intersect(names(baseline_df), c(surv_time_var, surv_event_var, cov_vars))
      merge_df   <- baseline_df[, c(id_col, merge_cols), drop = FALSE]
      long_base  <- dplyr::left_join(long_base, merge_df, by = id_col)
    }

    if (!all(c(surv_time_var, surv_event_var) %in% names(long_base))) {
      msg <- paste0("{Index}: 缺少生存变量 (", surv_time_var, "/", surv_event_var, ")，跳过")
      cli::cli_alert_danger(msg)
      if (.tfj02_should_pause(bl_cfg, "pause_on_missing_survival", TRUE)) {
        .tfj02_pause(
          ctx, msg,
          paste0(
            "在 config$trajectory_jlcm 中配置 survival_time_var / survival_event_var，",
            "并确认列存在于 ctx$data$imputed_with_id。"
          ),
          NULL
        )
      }
      next
    }

    model_data_final <- tryCatch({
      d <- long_base
      d$surv_time  <- pmax(pmin(suppressWarnings(as.numeric(
        as.character(d[[surv_time_var]]))), max_followup), 0.5)
      d$surv_event <- as.integer(
        .tfj02_coerce_event_01(d[[surv_event_var]], cfg, surv_event_var) == 1L &
        suppressWarnings(as.numeric(as.character(d[[surv_time_var]]))) <= max_followup
      )
      uid <- unique(d[[id_col]])
      d$subject_id_num <- as.integer(factor(d[[id_col]], levels = uid))
      d <- d[!is.na(d$scr_std) & !is.na(d$surv_time) & !is.na(d$surv_event), ]
      d <- d[d$subject_id_num %in% names(which(table(d$subject_id_num) >= 2)), ]
      d <- d[order(d$subject_id_num, d$time_day), ]
      rownames(d) <- NULL
      d
    }, error = function(e) { cli::cli_alert_danger("model_data_final 构建失败: {e$message}"); NULL })

    if (is.null(model_data_final) || nrow(model_data_final) == 0) {
      cli::cli_alert_warning("{Index}: model_data_final 为空，跳过"); next
    }

    cov_prep <- .tfj02_select_survival_covariates(model_data_final, cov_vars, ctx, bl_cfg)
    model_data_final <- cov_prep$data
    cov_vars_avail <- cov_prep$vars
    if (length(cov_vars_avail)) {
      cov_ok <- stats::complete.cases(model_data_final[, cov_vars_avail, drop = FALSE])
      if (any(!cov_ok)) {
        cli::cli_alert_info(
          "{Index}: survival 协变量非缺失筛选 {sum(!cov_ok)} 行 → 保留 {sum(cov_ok)} 行"
        )
      }
      model_data_final <- model_data_final[cov_ok, , drop = FALSE]
    }
    if (!nrow(model_data_final)) {
      cli::cli_alert_warning("{Index}: 连续协变量筛选后无样本，跳过"); next
    }
    n_subj <- length(unique(model_data_final$subject_id_num))
    cli::cli_alert_info("{Index}: 建模数据 {nrow(model_data_final)} 行，{n_subj} 名受试者")

    max_ng_for_index <- .tfj02_adaptive_max_ng(
      n_subj, adaptive_cap_enable, adaptive_cap_n_thr,
      adaptive_cap_ng_low, adaptive_cap_ng_high
    )
    class_range_eff <- class_range[class_range <= max_ng_for_index]
    if (adaptive_cap_enable) {
      cli::cli_alert_info(
        "{Index}: n_subj={n_subj} → 自适应类别数上限={max_ng_for_index}（阈值={adaptive_cap_n_thr}），有效 class_range: {paste(class_range_eff, collapse=',')}"
      )
    }
    if (!length(class_range_eff)) {
      cli::cli_alert_warning("{Index}: 自适应封顶后 class_range 为空，跳过多类拟合（仅拟合 ng=1）")
    }

    cov_missing <- setdiff(cov_vars, c(cov_vars_avail, cov_prep$dropped_non_continuous))
    if (length(cov_missing)) {
      cli::cli_alert_info(
        "{Index}: 未进入 survival 的候选协变量: {paste(head(cov_missing, 10), collapse=', ')}"
      )
    }

    cli::cli_h2("拟合 ng=1 基线模型")
    m1 <- tryCatch(
      .tfj02_fit_jointlcmm(
        model_data_final, spline_df, cov_vars_avail, hazard, hazardtype, 1L
      ),
      error = function(e) { cli::cli_alert_danger("ng=1 失败: {e$message}"); NULL }
    )

    stop_on_ng1_fail <- isTRUE(bl_cfg$stop_on_ng1_fail %||% TRUE)
    if (!.tfj02_ng1_ok(m1)) {
      m1_detail <- if (is.null(m1)) {
        "拟合报错"
      } else {
        sprintf("未收敛 (conv=%s)", m1$conv %||% NA)
      }
      cli::cli_alert_danger("{Index}: ng=1 基线模型失败 — {m1_detail}")
      if (stop_on_ng1_fail) {
        .tfj02_stop_jlcm(
          sprintf(
            "JLCM 早停 [%s]: ng=1 基线模型拟合失败（%s），终止后续 block。",
            Index, m1_detail
          ),
          bl_cfg
        )
      }
    }

    models_list <- list(m1 = m1)

    stop_on_ng2_fail <- isTRUE(bl_cfg$stop_on_ng2_fail %||% FALSE)

    if (.tfj02_ng1_ok(m1)) {
      for (g in setdiff(class_range_eff, 1L)) {
        cli::cli_h2("gridsearch ng={g}")
        mg <- tryCatch(
          .tfj02_gridsearch_jointlcmm(
            model_data_final, spline_df, cov_vars_avail, hazard, hazardtype,
            g, m1, gs_rep, gs_maxiter
          ),
          error = function(e) {
            msg <- if (inherits(e, "condition")) conditionMessage(e) else as.character(e)
            cli::cli_alert_danger("ng={g} 失败: {msg}")
            NULL
          }
        )
        if (!is.null(mg)) {
          models_list[[paste0("m", g)]] <- mg
          conv_flag <- .tfj02_jlcm_conv_ok(mg)
          cli::cli_alert_success("ng={g} {if(conv_flag) '收敛' else '未收敛（已保存）'}")
        } else {
          conv_flag <- FALSE
        }

        # ng=2 不收敛/拟合失败 → 早停（避免继续空耗 ng=3..6）
        if (identical(as.integer(g), 2L) && stop_on_ng2_fail && !isTRUE(conv_flag)) {
          m2_detail <- if (is.null(mg)) {
            "拟合报错"
          } else {
            sprintf("未收敛 (conv=%s)", .tfj02_unwrap_jointlcmm(mg)$conv %||% NA)
          }
          cli::cli_alert_danger("{Index}: ng=2 模型失败 — {m2_detail}")
          .tfj02_stop_jlcm(
            sprintf(
              "JLCM 早停 [%s]: ng=2 模型拟合失败（%s），终止后续 block。",
              Index, m2_detail
            ),
            bl_cfg
          )
        }
      }
    } else {
      cli::cli_alert_warning("ng=1 未收敛，跳过 ng=2..max")
    }

    # ── LL 单调性/空类守卫：自动重跑 + 记录到 results/Summary ──
    if (length(models_list) > 1L) {
      health <- tryCatch(
        .tfj02_jlcm_health_guard(
          models_list, model_data_final, spline_df, cov_vars_avail,
          hazard, hazardtype, gs_rep, gs_maxiter,
          refit_enable = if (is.null(bl_cfg$gridsearch_refit_on_health_fail)) TRUE else
            isTRUE(bl_cfg$gridsearch_refit_on_health_fail),
          refit_rep_cap = as.integer(bl_cfg$gridsearch_refit_rep_cap %||% 200L),
          refit_maxiter = as.integer(bl_cfg$gridsearch_refit_maxiter %||% 40L)
        ),
        error = function(e) {
          cli::cli_alert_danger("JLCM 健康守卫异常（不阻断）: {conditionMessage(e)}")
          NULL
        }
      )
      if (!is.null(health)) {
        models_list <- health$models
        ctx$results[[paste0("trajectory_jlcm_health_", Index)]] <- health$notes
        hp <- file.path(ctx$output_dir_tables, "Summary",
                        paste0("JLCM_health_", Index, ".txt"))
        dir.create(dirname(hp), recursive = TRUE, showWarnings = FALSE)
        writeLines(as.character(health$notes %||% "ok"), hp)
      }
    }

    models_list_with_cov <- models_list
    jlcm_file <- file.path(data_out_dir, paste0("D01_jlcm_", Index, "_models.RData"))
    save(models_list_with_cov, model_data_final, file = jlcm_file)
    ctx$results$trajectory_jlcm_models[[Index]] <- list(
      models = models_list_with_cov,
      model_data_final = model_data_final,
      covariate_vars_used = cov_vars_avail
    )
    summary_dir <- file.path(ctx$output_dir_tables, "Summary")
    root_summary <- file.path(ctx$root_output_dir %||% dirname(ctx$output_dir), "Tables", "Summary")
    for (d in unique(c(summary_dir, root_summary))) {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    db_lab <- tolower(trimws(as.character(cfg$project$database %||% "db")))
    fp_cov <- file.path(summary_dir, paste0("FinalCovariates_", Index, "_", db_lab, ".txt"))
    cov_lines <- c(
      paste0(
        "# Final covariates (JLCM survival submodel",
        if (isTRUE(bl_cfg$dual_db_shared_covariates)) ", dual-db shared" else "",
        ") — ", Index, " / ", toupper(db_lab)
      ),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      cov_vars_avail
    )
    writeLines(cov_lines, fp_cov)
    if (!identical(normalizePath(root_summary, winslash = "/"), normalizePath(summary_dir, winslash = "/"))) {
      writeLines(cov_lines, file.path(root_summary, paste0("FinalCovariates_", Index, "_", db_lab, ".txt")))
    }
    cli::cli_alert_success("JLCM survival 协变量已写入: {.file {basename(fp_cov)}}")
    cli::cli_alert_success("JLCM 模型落盘: {.file {basename(jlcm_file)}}")

    index_ic_rows <- list()
    for (g in class_range_eff) {
      key <- paste0(Index, "_D", g)
      m_g_raw <- models_list_with_cov[[paste0("m", g)]]
      if (is.null(m_g_raw)) next

      m_g <- .tfj02_unwrap_jointlcmm(m_g_raw)
      if (is.null(m_g$pprob)) {
        cli::cli_alert_warning("{key}: pprob 不存在，跳过类别分配")
        next
      }

      pprob_df <- as.data.frame(m_g$pprob)
      class_assign <- pprob_df[, c("subject_id_num", "class")]

      long_with_class <- model_data_final |>
        dplyr::left_join(class_assign, by = "subject_id_num") |>
        dplyr::mutate(Class = paste0("Class", class)) |>
        dplyr::rename(Time = time_day, Value = scr_std) |>
        dplyr::select(dplyr::all_of(id_col), Time, Value, Class,
                      dplyr::any_of(c(surv_time_var, surv_event_var,
                                      "surv_time", "surv_event", cov_vars)))

      ctx$data$trajectory_long[[key]] <- long_with_class
      long     <- long_with_class
      out_file <- file.path(data_out_dir, paste0("D01_long_", Index, "_D_", g, ".RData"))
      save(long, file = out_file)
      cli::cli_alert_success("{key}: 兼容长格式落盘")

      ic_row <- .tfj02_ic_row(m_g, Index, g, n_subj)
      if (!is.null(ic_row)) {
        ic_rows[[length(ic_rows) + 1L]] <- ic_row
        index_ic_rows[[length(index_ic_rows) + 1L]] <- ic_row
      }
    }

    index_ic_df <- tryCatch(dplyr::bind_rows(index_ic_rows), error = function(e) NULL)
    selected_ng <- if (!is.null(index_ic_df) && nrow(index_ic_df)) {
      .tfj02_auto_select_ng(index_ic_df, bl_cfg)
    } else {
      .tfj02_resolve_fallback_ng(bl_cfg)
    }
    if (!is.finite(suppressWarnings(as.integer(selected_ng)[1L]))) {
      selected_ng <- .tfj02_resolve_fallback_ng(bl_cfg)
    }
    ctx$results[[paste0("trajectory_optimal_ng_", Index)]] <- selected_ng
    ctx$results$trajectory_optimal_ng <- selected_ng
    cli::cli_alert_success("{Index}: 选定潜类别数 ng={selected_ng}")
    # 供发表整理 / 下游读取最优 ng
    for (sum_dir in unique(c(
      file.path(ctx$output_dir_tables %||% "Tables", "Summary"),
      file.path(ctx$root_output_dir %||% dirname(ctx$output_dir %||% "."), "Tables", "Summary")
    ))) {
      dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
      writeLines(as.character(selected_ng), file.path(sum_dir, paste0("optimal_ng_", Index, ".txt")))
    }
    ctx <- .tfj02_write_trajectory_class(
      ctx, Index, selected_ng, model_data_final, models_list_with_cov, id_col
    )
  }

  if (length(ic_rows) > 0) {
    ic_table <- tryCatch(dplyr::bind_rows(ic_rows), error = function(e) NULL)
    if (!is.null(ic_table)) {
      ctx$results$trajectory_ic_table <- ic_table[order(ic_table$Index, ic_table$D), , drop = FALSE]

      paper_util <- file.path(cfg$project$root %||% getwd(), "R/trajectory_paper_tables.R")
      if (file.exists(paper_util)) source(paper_util, local = FALSE)

      db_lab <- cfg$project$database %||% "Study"
      for (Index in index_vars) {
        pack <- ctx$results$trajectory_jlcm_models[[Index]]
        if (is.null(pack) || is.null(pack$models)) next
        ng <- ctx$results[[paste0("trajectory_optimal_ng_", Index)]] %||%
          ctx$results$trajectory_optimal_ng %||% 2L
        t2_title <- paste0(
          "Table 2. Metrics for determining the optimal number of classes (", Index, ")"
        )
        fp_t2 <- file.path(
          ctx$output_dir_tables,
          paste0("Table 2-", db_lab, ". Metrics for determining the optimal number of classes.xlsx")
        )
        # 始终写 CSV 兜底，避免 SCI 导出失败导致无 Table 2
        body2 <- tryCatch({
          if (exists("trajectory_build_table2_from_models", mode = "function")) {
            trajectory_build_table2_from_models(pack$models)
          } else NULL
        }, error = function(e) NULL)
        if (is.null(body2) || !nrow(body2)) body2 <- ic_table
        fp_ic2 <- file.path(ctx$output_dir_tables, paste0("Table2_", Index, "_model_comparison_ALL.csv"))
        tryCatch(
          utils::write.csv(body2, fp_ic2, row.names = FALSE, fileEncoding = "UTF-8"),
          error = function(e) cli::cli_alert_warning("Table2 CSV 写入失败: {e$message}")
        )
        ok_t2 <- FALSE
        if (exists("trajectory_export_table2_sci", mode = "function")) {
          ok_t2 <- isTRUE(tryCatch({
            trajectory_export_table2_sci(ctx, pack$models, fp_t2, t2_title)
            trajectory_export_table2_sci(
              ctx, pack$models,
              file.path(ctx$output_dir_tables, "Table_Trajectory_IC_JLCM.xlsx"),
              t2_title
            )
            TRUE
          }, error = function(e) {
            cli::cli_alert_warning("Table 2 SCI 导出失败: {e$message}")
            FALSE
          }))
        }
        if (ok_t2) {
          cli::cli_alert_success("Table 2 已输出: {.file {basename(fp_t2)}}")
        } else {
          cli::cli_alert_warning("Table 2 xlsx 未成功；已保留 CSV: {.file {basename(fp_ic2)}}")
        }
        m_sel <- pack$models[[paste0("m", ng)]]
        s8_title <- paste0("Table S8. Posterior classification table (", Index, ", ", db_lab, ")")
        fp_s8 <- file.path(
          ctx$output_dir_tables,
          paste0("Table S8-", db_lab, ". Posterior classification table.xlsx")
        )
        if (exists("trajectory_export_posterior_classification_sci", mode = "function")) {
          tryCatch({
            trajectory_export_posterior_classification_sci(ctx, m_sel, fp_s8, s8_title)
            cli::cli_alert_success("后验分类表已输出: {.file {basename(fp_s8)}}")
          }, error = function(e) cli::cli_alert_warning("后验分类表导出失败: {e$message}"))
        }
      }
    }
  }

  n_keys <- length(ctx$data$trajectory_long)
  stop_on_no_output <- isTRUE(bl_cfg$stop_on_no_output %||% TRUE)
  if (n_keys == 0) {
    if (stop_on_no_output) {
      .tfj02_stop_jlcm(
        "JLCM 早停: 无有效轨迹类别输出（trajectory_long 为空），终止后续 block。",
        bl_cfg
      )
    }
    if (.tfj02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .tfj02_pause(
        ctx,
        "所有 Index × D 均未成功拟合（JLCM）。",
        paste0(
          "请检查 config$trajectory_jlcm：① rawdata_path_template；② index_vars；",
          "③ 生存变量/协变量是否存在于 ctx$data$imputed_with_id。"
        ),
        NULL
      )
    }
  }
  cli::cli_alert_success(
    "trajectory_jlcm 完成: {n_keys} 个 Index×D 写入 ctx。"
  )
  ctx
}

register_block(
  "trajectory_jlcm", block_trajectory_jlcm,
  "JLCM 联合轨迹模型：生存+纵向→gridsearch→类别分配→落盘→IC表"
)
