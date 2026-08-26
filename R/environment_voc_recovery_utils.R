###############################################################################
#  environment_voc_recovery_utils.R — 环境 VOC 单因素不足时的亚组 / 极端值恢复
###############################################################################

environment_clinical_rerun_blocks <- function() {
  c(
    "data_clean", "column_mapping", "environment_lod_screen", "imputation",
    "environment_voc_log_transform", "obj",
    "baseline_nhanes", "univariate_nhanes",
    "environment_voc_clinical_gate",
    "multicollinearity_nhanes_screen"
  )
}

environment_downstream_rerun_blocks <- function() {
  c(
    environment_clinical_rerun_blocks(),
    "process_environment_data",
    "remove_outliers",
    "lasso_environment_voc",
    "glm_environment_quartile"
  )
}

environment_recovery_min_glm_vocs <- function(cfg) {
  bl <- cfg$environment_voc_extreme_trim %||% list()
  as.integer(
    bl$min_glm_vocs %||%
      (cfg$environment_bkmr %||% list())$min_vocs_before_bkmr %||%
      (cfg$bkmr_fit %||% list())$min_select_vocs %||%
      3L
  )[1L]
}

environment_count_glm_final_vocs <- function(ctx) {
  v <- unique(as.character(ctx$results$select_vocs_final %||% character(0)))
  v <- v[nzchar(v)]
  list(n = length(v), vocs = v)
}

environment_recovery_pipeline_ok <- function(ctx, cfg = NULL) {
  cfg <- cfg %||% ctx$config %||% list()
  min_n <- environment_recovery_min_glm_vocs(cfg)
  cnt <- environment_count_glm_final_vocs(ctx)
  isTRUE(cnt$n >= min_n)
}

environment_ensure_raw_snapshot <- function(ctx) {
  raw <- ctx$data$raw
  if (is.null(ctx$results$environment_raw_snapshot) && is.data.frame(raw) && nrow(raw)) {
    ctx$results$environment_raw_snapshot <- raw
  }
  ctx
}

environment_reset_downstream_ctx <- function(ctx) {
  keys_clear <- c(
    "environment_process_stats", "environment_voc_cols", "environment_prelog_vocs",
    "env_label_df",
    "select_vocs", "select_vocs_lasso", "select_vocs_univar",
    "lasso_gene_sum", "lasso_height", "lasso_cv_list", "univariate_env_table",
    "select_vocs_glm", "select_vocs_final", "glm_environment_table",
    "glm_quartile_table", "environment_glm_covariates", "glm_covariate_search_log"
  )
  for (k in keys_clear) ctx$results[[k]] <- NULL
  ctx
}

environment_clear_active_subgroup <- function(ctx) {
  ctx$results$environment_active_subgroup <- NULL
  ctx$results$environment_active_subgroup_label <- NULL
  if (!is.null(ctx$config$environment_subgroup_search)) {
    ctx$config$environment_subgroup_search$active_filter <- NULL
  }
  ctx
}

environment_voc_pool <- function(data, cfg) {
  if (exists("environment_voc_allowlist", mode = "function")) {
    v <- environment_voc_allowlist(data, cfg)
  } else {
    v <- as.character((cfg$environment %||% list())$voc_columns %||% character(0))
  }
  intersect(unique(v[nzchar(v)]), names(data))
}

environment_calculate_vif_from_vars <- function(vars, data) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (length(vars) <= 1L) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
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
    return(list(vif_df = NULL, vif_values = NULL))
  }
  vif_values <- tryCatch({
    r2s <- vapply(seq_len(ncol(X)), function(j) {
      if (ncol(X) == 1L) return(0)
      summary(stats::lm(X[, j] ~ X[, -j, drop = FALSE]))$r.squared
    }, numeric(1))
    stats::setNames(1 / (1 - r2s), colnames(X))
  }, error = function(e) NULL)
  if (is.null(vif_values)) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
  list(
    vif_df = data.frame(
      Variable = names(vif_values),
      VIF = round(as.numeric(vif_values), 3),
      stringsAsFactors = FALSE
    ),
    vif_values = vif_values
  )
}

environment_vif_prune_vars <- function(vars, data, threshold = 10, min_keep = 2L) {
  vars <- unique(intersect(as.character(vars), names(data)))
  min_keep <- as.integer(min_keep %||% 2L)[1L]
  empty_log <- data.frame(Variable = character(0), VIF = numeric(0), stringsAsFactors = FALSE)
  if (length(vars) <= min_keep) {
    return(list(vars = vars, removed = character(0), log = empty_log))
  }
  working <- vars
  vif_removed <- character(0)
  vif_log <- list()
  thr <- as.numeric(threshold)[1L]
  repeat {
    res <- environment_calculate_vif_from_vars(working, data)
    if (is.null(res$vif_df) || !nrow(res$vif_df)) break
    mx <- max(res$vif_df$VIF, na.rm = TRUE)
    if (!is.finite(mx) || mx <= thr) break
    if (length(working) <= min_keep) break
    drop_var <- res$vif_df$Variable[which.max(res$vif_df$VIF)]
    hit <- working[working == drop_var]
    if (!length(hit)) {
      hit <- working[grepl(drop_var, working, fixed = TRUE)]
    }
    if (!length(hit)) break
    drop_var <- hit[1L]
    vif_removed <- c(vif_removed, drop_var)
    vif_log[[length(vif_log) + 1L]] <- data.frame(
      Variable = drop_var, VIF = round(mx, 3), stringsAsFactors = FALSE
    )
    working <- setdiff(working, drop_var)
    if (!length(working)) break
  }
  list(
    vars = unique(working),
    removed = unique(vif_removed),
    log = if (length(vif_log)) do.call(rbind, vif_log) else empty_log
  )
}

#' 高相关 VOC 筛选：每对相关对只剔除 VIF 较高者（保留另一个）
#'
#' @param mode
#'   - `pair_disjoint`（默认）：按 |r| 降序，每对变量至多决策一次；决策后该对不再参与。
#'   - `single_pass`：可多轮用到同一变量，保留侧 protected。
#'   - `iterative`：逐轮重算矩阵直到全部 |r|<=threshold。
environment_cor_prune_vars <- function(
    vars,
    data,
    threshold = 0.70,
    min_keep = 2L,
    method = "pearson",
    vif_values = NULL,
    mode = "pair_disjoint"
) {
  vars <- unique(intersect(as.character(vars), names(data)))
  min_keep <- as.integer(min_keep %||% 2L)[1L]
  empty_pairs <- data.frame(
    Var1 = character(0), Var2 = character(0),
    Abs_r = numeric(0), Dropped = character(0), Kept = character(0),
    stringsAsFactors = FALSE
  )
  if (length(vars) < 2L) {
    return(list(vars = vars, removed = character(0), pairs_log = empty_pairs))
  }

  thr <- as.numeric(threshold)[1L]
  cor_method <- as.character(method %||% "pearson")[1L]
  cor_mode <- tolower(as.character(mode %||% "pair_disjoint")[1L])

  .vif_of <- function(v) {
    if (is.null(vif_values) || !v %in% names(vif_values)) return(0)
    x <- suppressWarnings(as.numeric(vif_values[[v]]))
    if (is.finite(x)) x else 0
  }

  .drop_higher_vif <- function(v1, v2) {
    vif1 <- .vif_of(v1)
    vif2 <- .vif_of(v2)
    if (vif1 > vif2) {
      list(drop = v1, keep = v2)
    } else if (vif2 > vif1) {
      list(drop = v2, keep = v1)
    } else {
      list(drop = v2, keep = v1)
    }
  }

  .cor_matrix <- function(working) {
    mat <- data[, working, drop = FALSE]
    for (nm in working) {
      if (!is.numeric(mat[[nm]])) {
        mat[[nm]] <- suppressWarnings(as.numeric(as.character(mat[[nm]])))
      }
    }
    tryCatch(
      stats::cor(as.matrix(mat), method = cor_method, use = "pairwise.complete.obs"),
      error = function(e) NULL
    )
  }

  if (identical(cor_mode, "iterative")) {
    working <- vars
    cor_removed <- character(0)
    pairs_log <- list()
    repeat {
      if (length(working) < 2L) break
      cor_m <- .cor_matrix(working)
      if (is.null(cor_m)) break
      diag(cor_m) <- 0
      max_cor <- max(abs(cor_m), na.rm = TRUE)
      if (!is.finite(max_cor) || max_cor <= thr) break
      if (length(working) <= min_keep) break
      idx <- which(abs(cor_m) == max_cor, arr.ind = TRUE)[1, , drop = TRUE]
      v1 <- working[idx[1L]]
      v2 <- working[idx[2L]]
      pick <- .drop_higher_vif(v1, v2)
      cor_removed <- c(cor_removed, pick$drop)
      pairs_log[[length(pairs_log) + 1L]] <- data.frame(
        Var1 = v1, Var2 = v2, Abs_r = round(max_cor, 4),
        Dropped = pick$drop, Kept = pick$keep, stringsAsFactors = FALSE
      )
      working <- setdiff(working, pick$drop)
    }
    return(list(
      vars = unique(working),
      removed = unique(cor_removed),
      pairs_log = if (length(pairs_log)) do.call(rbind, pairs_log) else empty_pairs
    ))
  }

  if (identical(cor_mode, "pair_disjoint")) {
    working <- vars
    resolved <- character(0)
    cor_m <- .cor_matrix(working)
    if (is.null(cor_m)) {
      return(list(vars = working, removed = character(0), pairs_log = empty_pairs))
    }
    pairs <- list()
    nms <- colnames(cor_m)
    for (i in seq_len(nrow(cor_m) - 1L)) {
      for (j in (i + 1L):ncol(cor_m)) {
        r_ij <- abs(cor_m[i, j])
        if (is.finite(r_ij) && r_ij > thr) {
          pairs[[length(pairs) + 1L]] <- data.frame(
            Var1 = nms[i], Var2 = nms[j], Abs_r = r_ij,
            stringsAsFactors = FALSE
          )
        }
      }
    }
    if (!length(pairs)) {
      return(list(vars = working, removed = character(0), pairs_log = empty_pairs))
    }
    pair_df <- do.call(rbind, pairs)
    pair_df <- pair_df[order(-pair_df$Abs_r), , drop = FALSE]

    cor_removed <- character(0)
    pairs_log <- list()
    for (k in seq_len(nrow(pair_df))) {
      v1 <- as.character(pair_df$Var1[k])
      v2 <- as.character(pair_df$Var2[k])
      if (v1 %in% resolved || v2 %in% resolved) next
      if (!(v1 %in% working && v2 %in% working)) next
      pick <- .drop_higher_vif(v1, v2)
      cor_removed <- c(cor_removed, pick$drop)
      resolved <- unique(c(resolved, v1, v2))
      working <- setdiff(working, pick$drop)
      pairs_log[[length(pairs_log) + 1L]] <- data.frame(
        Var1 = v1, Var2 = v2, Abs_r = round(pair_df$Abs_r[k], 4),
        Dropped = pick$drop, Kept = pick$keep, stringsAsFactors = FALSE
      )
      if (length(working) <= min_keep) break
    }
    return(list(
      vars = unique(working),
      removed = unique(cor_removed),
      pairs_log = if (length(pairs_log)) do.call(rbind, pairs_log) else empty_pairs
    ))
  }

  if (identical(cor_mode, "single_pass")) {
    working <- vars
    protected <- character(0)
    cor_m <- .cor_matrix(working)
    if (is.null(cor_m)) {
      return(list(vars = working, removed = character(0), pairs_log = empty_pairs))
    }
    pairs <- list()
    nms <- colnames(cor_m)
    for (i in seq_len(nrow(cor_m) - 1L)) {
      for (j in (i + 1L):ncol(cor_m)) {
        r_ij <- abs(cor_m[i, j])
        if (is.finite(r_ij) && r_ij > thr) {
          pairs[[length(pairs) + 1L]] <- data.frame(
            Var1 = nms[i], Var2 = nms[j], Abs_r = r_ij,
            stringsAsFactors = FALSE
          )
        }
      }
    }
    if (!length(pairs)) {
      return(list(vars = working, removed = character(0), pairs_log = empty_pairs))
    }
    pair_df <- do.call(rbind, pairs)
    pair_df <- pair_df[order(-pair_df$Abs_r), , drop = FALSE]
    cor_removed <- character(0)
    pairs_log <- list()
    for (k in seq_len(nrow(pair_df))) {
      v1 <- as.character(pair_df$Var1[k])
      v2 <- as.character(pair_df$Var2[k])
      if (!(v1 %in% working && v2 %in% working)) next
      if (v1 %in% protected && v2 %in% protected) next
      if (v1 %in% protected) {
        pick <- list(drop = v2, keep = v1)
      } else if (v2 %in% protected) {
        pick <- list(drop = v1, keep = v2)
      } else {
        pick <- .drop_higher_vif(v1, v2)
      }
      if (pick$drop %in% protected) next
      cor_removed <- c(cor_removed, pick$drop)
      protected <- unique(c(protected, pick$keep))
      working <- setdiff(working, pick$drop)
      pairs_log[[length(pairs_log) + 1L]] <- data.frame(
        Var1 = v1, Var2 = v2, Abs_r = round(pair_df$Abs_r[k], 4),
        Dropped = pick$drop, Kept = pick$keep, stringsAsFactors = FALSE
      )
      if (length(working) <= min_keep) break
    }
    return(list(
      vars = unique(working),
      removed = unique(cor_removed),
      pairs_log = if (length(pairs_log)) do.call(rbind, pairs_log) else empty_pairs
    ))
  }

  list(vars = vars, removed = character(0), pairs_log = empty_pairs)
}

#' Crude RCS（无协变量）p for overall；用于 GLM 前剔除 crude 不显著的环境毒物
environment_voc_crude_rcs_p_overall <- function(ctx, voc, cfg = NULL, bl = list()) {
  voc <- as.character(voc)[1L]
  if (!nzchar(voc)) return(NA_real_)
  cfg <- cfg %||% ctx$config %||% list()
  design <- ctx$results$nhanes_design
  if (is.null(design) || !voc %in% names(design$variables)) return(NA_real_)
  if (!requireNamespace("survey", quietly = TRUE) ||
      !requireNamespace("Hmisc", quietly = TRUE)) {
    return(NA_real_)
  }
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  proj <- cfg$project %||% list()
  disease_lbl <- proj$analysis_group %||% proj$disease %||% "Case"
  p_thr <- as.numeric(bl$crude_rcs_p_threshold %||% 0.05)[1L]
  knot_n <- as.integer(bl$crude_rcs_knots %||% 4L)[1L]
  knot_q <- if (knot_n >= 4L) c(0.05, 0.35, 0.65, 0.95) else c(0.1, 0.5, 0.9)

  des <- stats::update(
    design,
    Disease_Group = as.numeric(design$variables[[outcome_col]] == disease_lbl)
  )
  x <- des$variables[[voc]]
  if (!is.numeric(x)) x <- suppressWarnings(as.numeric(x))
  if (sum(is.finite(x)) < 30L) return(NA_real_)
  knots <- stats::quantile(x, knot_q, na.rm = TRUE)
  if (length(unique(knots)) < 3L) return(NA_real_)
  n_rcs <- length(knots) - 1L
  bn <- paste0("rcs_b", seq_len(n_rcs))
  basis <- as.matrix(Hmisc::rcspline.eval(x, knots = knots, inclx = TRUE))
  if (is.null(basis) || ncol(basis) < 1L) return(NA_real_)
  colnames(basis) <- bn[seq_len(ncol(basis))]
  tmp <- des
  tmp$variables <- cbind(tmp$variables, as.data.frame(basis))
  fml <- stats::as.formula(paste0("Disease_Group ~ ", paste(colnames(basis), collapse = "+")))
  fit <- tryCatch(
    survey::svyglm(fml, design = tmp, family = stats::quasibinomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA_real_)
  p_ov <- tryCatch(survey::regTermTest(fit, colnames(basis))$p, error = function(e) NA_real_)
  as.numeric(p_ov)[1L]
}

environment_voc_filter_by_crude_rcs <- function(ctx, vocs, cfg = NULL, bl = list()) {
  vocs <- unique(as.character(vocs[nzchar(vocs)]))
  if (!length(vocs)) {
    return(list(keep = character(0), removed = character(0), log = data.frame()))
  }
  if (!isTRUE(bl$crude_rcs_prefilter_enable %||% FALSE)) {
    return(list(keep = vocs, removed = character(0), log = data.frame()))
  }
  p_thr <- as.numeric(bl$crude_rcs_p_threshold %||% 0.05)[1L]
  keep <- character(0)
  removed <- character(0)
  rows <- list()
  for (v in vocs) {
    p <- environment_voc_crude_rcs_p_overall(ctx, v, cfg, bl)
    if (is.finite(p) && p < p_thr) {
      keep <- c(keep, v)
    } else {
      removed <- c(removed, v)
      rows[[length(rows) + 1L]] <- data.frame(
        VOC = v, P_overall = round(p, 6), Removed = TRUE, stringsAsFactors = FALSE
      )
      cli::cli_alert_warning(
        "crude RCS 预筛: {v} p_overall={if (is.finite(p)) round(p, 4) else 'NA'} >= {p_thr}，剔除（不进 GLM）"
      )
    }
  }
  log_df <- if (length(rows)) do.call(rbind, rows) else data.frame(
    VOC = character(0), P_overall = numeric(0), Removed = logical(0),
    stringsAsFactors = FALSE
  )
  cli::cli_alert_info(
    "crude RCS 预筛: {length(keep)}/{length(vocs)} 个 VOC 进入 GLM（crude p<{p_thr}）"
  )
  list(keep = unique(keep), removed = unique(removed), log = log_df)
}

#' 环境 VOC 加权单因素（NHANES survey::svyglm），与临床 univariate_nhanes 分离
environment_voc_survey_univariate <- function(ctx, voc_pool, bl = list()) {
  voc_pool <- unique(intersect(as.character(voc_pool), names(
    (ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned) %||% list()
  )))
  empty <- list(keep = character(0), table = data.frame(
    Variable = character(0), P = numeric(0), stringsAsFactors = FALSE
  ))
  if (!length(voc_pool)) return(empty)

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    cli::cli_alert_warning(
      "environment_voc_survey_univariate: nhanes_design 为空，无法做 VOC 加权单因素。"
    )
    return(empty)
  }
  if (!requireNamespace("survey", quietly = TRUE)) {
    cli::cli_alert_warning("environment_voc_survey_univariate: 缺少 survey 包。")
    return(empty)
  }

  cfg <- ctx$config %||% list()
  p_cutoff <- as.numeric(bl$voc_univariate_p_cutoff %||%
    (cfg$univariate_nhanes %||% list())$screening_cutoff %||% 0.1)[1L]
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  proj <- cfg$project %||% list()
  disease_lbl <- proj$analysis_group %||% proj$disease %||% "Case"

  design <- stats::update(
    design,
    Disease_Group = as.numeric(design$variables[[outcome_col]] == disease_lbl)
  )
  voc_pool <- intersect(voc_pool, names(design$variables))
  if (!length(voc_pool)) return(empty)

  exclude_or_lt1 <- isTRUE(bl$voc_univariate_exclude_or_below_one %||% FALSE)
  rows <- list()
  keep <- character(0)
  n_or_dropped <- 0L
  for (v in voc_pool) {
    f <- stats::as.formula(paste0("Disease_Group ~ ", v))
    fit_u <- tryCatch(
      survey::svyglm(f, design = design, family = stats::quasibinomial()),
      error = function(e) NULL
    )
    if (is.null(fit_u)) next
    sm <- summary(fit_u)$coefficients
    if (is.null(sm) || nrow(sm) < 2L) next
    est <- sm[2L, 1L]
    se  <- sm[2L, 2L]
    pval <- sm[2L, 4L]
    or_v <- exp(est)
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = v,
      OR = round(or_v, 4),
      CI_lo = round(exp(est - 1.96 * se), 4),
      CI_hi = round(exp(est + 1.96 * se), 4),
      P = round(pval, 6),
      stringsAsFactors = FALSE
    )
    is_sig <- !is.na(pval) && pval < p_cutoff
    if (is_sig && exclude_or_lt1 && (!is.na(or_v) && or_v <= 1)) {
      n_or_dropped <- n_or_dropped + 1L
      next
    }
    if (is_sig) keep <- c(keep, v)
  }

  tbl <- if (length(rows)) do.call(rbind, rows) else empty$table
  cli::cli_alert_info(
    "environment_voc_survey_univariate: P<{p_cutoff}{if (exclude_or_lt1) ' & OR>1' else ''} 通过 {length(keep)}/{length(voc_pool)} 个 VOC{if (exclude_or_lt1 && n_or_dropped > 0L) paste0('（其中 ', n_or_dropped, ' 个因 OR<1 剔除）') else ''}"
  )
  list(keep = unique(keep), table = tbl)
}

environment_voc_univariate_candidates <- function(ctx, voc_pool, bl = list()) {
  source <- tolower(as.character(bl$voc_univariate_source %||% "voc_survey")[1L])
  if (source %in% c("voc_survey", "survey")) {
    res <- environment_voc_survey_univariate(ctx, voc_pool, bl)
    ctx$results$voc_univariate_coef <- res$table
    return(res$keep)
  }
  if (identical(source, "pool") || identical(source, "all")) {
    return(unique(intersect(as.character(voc_pool), names(
      (ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned) %||% list()
    ))))
  }
  if (identical(source, "tb_screen")) {
    uni <- unique(as.character(ctx$results$tb_screen %||% character(0)))
  } else if (identical(source, "both")) {
    uni <- unique(c(
      as.character(ctx$results$tb1 %||% character(0)),
      as.character(ctx$results$tb_screen %||% character(0))
    ))
  } else {
    uni <- unique(as.character(ctx$results$tb1 %||% character(0)))
  }
  p_cutoff <- as.numeric(bl$voc_univariate_p_cutoff %||% 0.05)[1L]
  uv_tbl <- ctx$results$univariate_nhanes %||% ctx$results$univariate_table %||% NULL
  if (!is.null(uv_tbl) && nrow(uv_tbl) && "P" %in% names(uv_tbl)) {
    sig_p <- uv_tbl[is.finite(uv_tbl$P) & uv_tbl$P < p_cutoff, , drop = FALSE]
    if (nrow(sig_p)) {
      sig_bases <- unique(vapply(sig_p$Variable, function(vn) {
        sub("_.*$", "", as.character(vn))
      }, character(1L)))
      uni <- intersect(uni, sig_bases)
    } else {
      uni <- character(0)
    }
  }
  intersect(voc_pool, uni[nzchar(uni)])
}

environment_count_sig_univariate_vocs <- function(ctx, cfg = NULL) {
  cfg <- cfg %||% ctx$config %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  voc <- environment_voc_pool(data, cfg)

  # clinical_gate 会把环境毒物从 tb1 剔除（仅保留临床协变量）；优先用门禁结果
  gate <- unique(as.character(ctx$results$select_vocs_clinical_gate %||% character(0)))
  gate <- intersect(gate, voc)
  if (length(gate)) {
    return(list(n = length(gate), vocs = gate, voc_pool = voc))
  }

  tb1_voc <- unique(as.character(ctx$results$tb1_voc_univariate %||% character(0)))
  tb1_voc <- intersect(tb1_voc, voc)
  if (length(tb1_voc)) {
    return(list(n = length(tb1_voc), vocs = tb1_voc, voc_pool = voc))
  }

  tb1 <- unique(as.character(ctx$results$tb1 %||% character(0)))
  passed <- intersect(voc, tb1)
  list(
    n = length(passed),
    vocs = passed,
    voc_pool = voc
  )
}

environment_default_subgroup_filters <- function(cfg = list()) {
  bl <- cfg$environment_subgroup_search %||% list()
  extra <- bl$custom_filters %||% list()
  base <- list(
    list(id = "age_lt_50", label = "Age < 50", expr = "Age < 50"),
    list(id = "age_ge_50", label = "Age >= 50", expr = "Age >= 50"),
    list(id = "age_lt_65", label = "Age < 65", expr = "Age < 65"),
    list(id = "age_ge_65", label = "Age >= 65", expr = "Age >= 65"),
    list(id = "obesity_bmi30", label = "Obesity (BMI>=30)", expr = "BMI >= 30"),
    list(id = "overweight_bmi25", label = "Overweight (BMI>=25)", expr = "BMI >= 25"),
    list(id = "hypertension", label = "Hypertension", expr = "Hypertension %in% c('Yes','yes','1',1)"),
    list(id = "diabetes", label = "Diabetes", expr = "Diabetes %in% c('Yes','yes','1',1)"),
    list(id = "htn_and_dm", label = "Hypertension + Diabetes", expr = "Hypertension %in% c('Yes','yes','1',1) & Diabetes %in% c('Yes','yes','1',1)"),
    list(id = "smoking_never", label = "Never smoker", expr = "Smoking %in% c('never','Never')"),
    list(id = "smoking_current", label = "Current smoker", expr = "Smoking %in% c('current','Current')"),
    list(id = "smoking_former", label = "Former smoker", expr = "Smoking %in% c('former','Former')"),
    list(id = "pir_low", label = "PIR <= 1.3", expr = "PIR %in% c('\\u2264 1.3', '<= 1.3') | (suppressWarnings(as.numeric(PIR)) <= 1.3)"),
    list(id = "race_nhw", label = "Non-Hispanic White", expr = "Race == 'Non-Hispanic White'"),
    list(id = "race_nhb", label = "Non-Hispanic Black", expr = "Race == 'Non-Hispanic Black'"),
    list(id = "race_hispanic", label = "Other/Mexican Hispanic", expr = "Race %in% c('Mexican American','Other Hispanic','Other Race')"),
    list(id = "female", label = "Female", expr = "Gender == 'Female'"),
    list(id = "male", label = "Male", expr = "Gender == 'Male'"),
    list(id = "albuminuria_high", label = "Albumin_Urine >= 30", expr = "Albumin_Urine >= 30"),
    list(id = "hyperuricemia", label = "Uric_Acid >= 7 (M) / 6 (F)", expr = "(Gender == 'Male' & Uric_Acid >= 7) | (Gender == 'Female' & Uric_Acid >= 6) | (is.na(Gender) & Uric_Acid >= 6.5)")
  )
  c(base, extra)
}

environment_apply_subgroup_filter <- function(df, filter_spec) {
  expr <- as.character(filter_spec$expr %||% "")[1L]
  if (!nzchar(expr) || !is.data.frame(df) || !nrow(df)) return(df)
  miss <- setdiff(all.vars(parse(text = expr)), names(df))
  if (length(miss)) return(df[0, , drop = FALSE])
  keep <- tryCatch(with(df, eval(parse(text = expr))), error = function(e) rep(FALSE, nrow(df)))
  keep[is.na(keep)] <- FALSE
  df[keep, , drop = FALSE]
}

environment_reset_clinical_ctx <- function(ctx) {
  keys_clear <- c(
    "cleaned", "mapped", "imputed",
    "sig_vars", "tb1", "tb2", "Model1Factors", "Model2Factors",
    "vif_final_pass", "vif_screen_pass", "select_vocs_clinical_gate",
    "tb1_voc_univariate",
    "environment_voc_clinical_gate_detail", "environment_voc_clinical_gate_mode",
    "nhanes_design", "baseline_done", "univariate_done"
  )
  for (k in keys_clear) ctx$results[[k]] <- NULL
  ctx$data$cleaned <- NULL
  ctx$data$mapped <- NULL
  ctx$data$imputed <- NULL
  ctx
}

environment_source_clinical_blocks <- function(root, sourced = character(0)) {
  if (exists("pipeline_source_block", mode = "function")) {
    for (bn in environment_clinical_rerun_blocks()) {
      sourced <- pipeline_source_block(root, bn, sourced)
    }
  }
  invisible(sourced)
}

environment_source_downstream_blocks <- function(root, sourced = character(0)) {
  if (exists("pipeline_source_block", mode = "function")) {
    for (bn in environment_downstream_rerun_blocks()) {
      sourced <- pipeline_source_block(root, bn, sourced)
    }
  }
  invisible(sourced)
}

environment_recovery_base <- function(ctx) {
  root <- ctx$root_output_dir %||% ctx$output_dir %||% "."
  file.path(root, "recovery")
}

environment_write_trial_summary <- function(trial_dir, summary) {
  if (is.null(trial_dir) || !nzchar(trial_dir)) return(invisible(NULL))
  dir.create(trial_dir, recursive = TRUE, showWarnings = FALSE)
  flat <- lapply(summary, function(x) {
    if (length(x) > 1L) paste(as.character(x), collapse = ";") else as.character(x)[1L]
  })
  df <- data.frame(field = names(flat), value = unlist(flat, use.names = FALSE), stringsAsFactors = FALSE)
  path <- file.path(trial_dir, "trial_summary.csv")
  tryCatch(utils::write.csv(df, path, row.names = FALSE), error = function(e) NULL)
  invisible(path)
}

environment_rerun_through_glm <- function(ctx, root, raw_df = NULL,
                                          trial_output_dir = NULL,
                                          clear_subgroup = TRUE) {
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  parent_root <- ctx$root_output_dir %||% ctx$output_dir %||% "."
  parent_counter <- as.integer(ctx$log$block_step_counter %||% 0L)
  use_trial_dir <- !is.null(trial_output_dir) && nzchar(as.character(trial_output_dir)[1L])
  if (use_trial_dir) {
    trial_output_dir <- normalizePath(trial_output_dir, winslash = "/", mustWork = FALSE)
    dir.create(trial_output_dir, recursive = TRUE, showWarnings = FALSE)
    ctx$root_output_dir <- trial_output_dir
    ctx$log$block_step_counter <- 0L
    cli::cli_alert_info("recovery trial 输出: {.file {trial_output_dir}}")
  }
  if (nzchar(root) && dir.exists(root)) {
    environment_source_downstream_blocks(root)
  }
  if (!is.null(raw_df)) {
    ctx$data$raw <- raw_df
    ctx$results$environment_dkd_prepared <- TRUE
  }
  if (isTRUE(clear_subgroup)) {
    ctx <- environment_clear_active_subgroup(ctx)
  }
  ctx <- environment_reset_clinical_ctx(ctx)
  ctx <- environment_reset_downstream_ctx(ctx)
  for (bn in environment_downstream_rerun_blocks()) {
    ctx <- run_block(ctx, bn)
  }
  if (use_trial_dir) {
    ctx$root_output_dir <- parent_root
    ctx$log$block_step_counter <- parent_counter
  }
  ctx
}

environment_rerun_clinical_path <- function(ctx, root, raw_df = NULL, trial_output_dir = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  parent_root <- ctx$root_output_dir %||% ctx$output_dir %||% "."
  parent_counter <- as.integer(ctx$log$block_step_counter %||% 0L)
  use_trial_dir <- !is.null(trial_output_dir) && nzchar(as.character(trial_output_dir)[1L])
  if (use_trial_dir) {
    trial_output_dir <- normalizePath(trial_output_dir, winslash = "/", mustWork = FALSE)
    dir.create(trial_output_dir, recursive = TRUE, showWarnings = FALSE)
    ctx$root_output_dir <- trial_output_dir
    ctx$log$block_step_counter <- 0L
    cli::cli_alert_info("recovery trial 输出: {.file {trial_output_dir}}")
  }
  if (nzchar(root) && dir.exists(root)) {
    environment_source_clinical_blocks(root)
  }
  if (!is.null(raw_df)) {
    ctx$data$raw <- raw_df
    ctx$results$environment_dkd_prepared <- TRUE
  }
  ctx <- environment_reset_clinical_ctx(ctx)
  for (bn in environment_clinical_rerun_blocks()) {
    ctx <- run_block(ctx, bn)
  }
  if (use_trial_dir) {
    ctx$root_output_dir <- parent_root
    ctx$log$block_step_counter <- parent_counter
  }
  ctx
}

environment_trial_sig_voc_count <- function(raw_df, ctx, root, trial_output_dir = NULL,
                                            trial_meta = list()) {
  ctx2 <- ctx
  ctx2$data$raw <- raw_df
  ctx2 <- environment_rerun_clinical_path(ctx2, root, raw_df = raw_df, trial_output_dir = trial_output_dir)
  cnt <- environment_count_sig_univariate_vocs(ctx2, ctx2$config)
  if (!is.null(trial_output_dir) && nzchar(trial_output_dir)) {
    meta <- c(
      trial_meta,
      list(
        n_sample = nrow(raw_df),
        sig_vocs_n = cnt$n,
        sig_vocs = cnt$vocs,
        trial_dir = trial_output_dir
      )
    )
    environment_write_trial_summary(trial_output_dir, meta)
  }
  list(n = cnt$n, vocs = cnt$vocs, ctx = ctx2)
}

environment_trial_glm_voc_count <- function(raw_df, ctx, root, trial_output_dir = NULL,
                                          trial_meta = list()) {
  status <- "ok"
  trial_ctx <- tryCatch(
    environment_rerun_through_glm(
      ctx, root, raw_df = raw_df,
      trial_output_dir = trial_output_dir,
      clear_subgroup = TRUE
    ),
    error = function(e) {
      status <<- "failed"
      cli::cli_alert_warning(
        "recovery GLM 重跑失败: {conditionMessage(e)}"
      )
      NULL
    }
  )
  cnt <- if (is.null(trial_ctx)) {
    list(n = 0L, vocs = character(0))
  } else {
    environment_count_glm_final_vocs(trial_ctx)
  }
  if (!is.null(trial_output_dir) && nzchar(trial_output_dir)) {
    meta <- c(
      trial_meta,
      list(
        n_sample = nrow(raw_df),
        glm_final_vocs_n = cnt$n,
        glm_final_vocs = cnt$vocs,
        status = status,
        trial_dir = trial_output_dir
      )
    )
    environment_write_trial_summary(trial_output_dir, meta)
  }
  list(
    n = cnt$n,
    vocs = cnt$vocs,
    ctx = if (is.null(trial_ctx)) ctx else trial_ctx,
    status = status
  )
}

environment_pick_extreme_trim_candidates <- function(data, voc_pool, tb1,
                                                       n_drop = NULL,
                                                       drop_frac = 0.005,
                                                       exclude_seqn = integer(0)) {
  if (is.null(data) || !nrow(data) || !length(voc_pool)) return(integer(0))
  id_col <- if ("SEQN" %in% names(data)) "SEQN" else if ("ID" %in% names(data)) "ID" else NULL
  if (is.null(id_col)) return(integer(0))

  ids <- as.numeric(data[[id_col]])
  excl <- as.numeric(exclude_seqn %||% integer(0))
  if (length(excl)) {
    keep <- !(ids %in% excl)
    data <- data[keep, , drop = FALSE]
    ids <- as.numeric(data[[id_col]])
  }

  n_avail <- nrow(data)
  if (!n_avail) return(integer(0))

  if (!is.null(n_drop)) {
    n_drop <- max(1L, as.integer(n_drop)[1L])
  } else {
    frac <- as.numeric(drop_frac %||% 0.005)[1L]
    if (!is.finite(frac) || frac <= 0) frac <- 0.005
    n_drop <- max(1L, as.integer(ceiling(n_avail * frac)))
  }
  n_drop <- min(n_drop, n_avail)

  voc_pool   <- intersect(as.character(voc_pool), names(data))
  borderline <- setdiff(voc_pool, tb1)
  if (!length(borderline)) borderline <- voc_pool
  borderline <- intersect(borderline, names(data))
  score <- rep(0, nrow(data))
  for (v in borderline) {
    x <- suppressWarnings(as.numeric(data[[v]]))
    if (!any(is.finite(x))) next
    z <- (x - mean(x, na.rm = TRUE)) / stats::sd(x, na.rm = TRUE)
    z[!is.finite(z)] <- 0
    score <- score + abs(z)
  }
  if (all(score <= 0) && length(borderline)) {
    ord <- order(data[[borderline[1]]], decreasing = TRUE, na.last = TRUE)
  } else if (all(score <= 0)) {
    return(integer(0))
  } else {
    ord <- order(score, decreasing = TRUE, na.last = TRUE)
  }
  as.numeric(data[[id_col]][ord[seq_len(min(n_drop, length(ord)))]])
}

environment_extreme_trim_scoring_data <- function(raw_base, excluded, cfg) {
  data_ref <- environment_filter_raw_by_seqn(
    raw_base, keep_seqn = raw_base$SEQN, exclude_seqn = excluded
  )
  if (!nrow(data_ref)) return(data_ref)
  voc_cols <- environment_voc_pool(data_ref, cfg)
  voc_cols <- intersect(voc_cols, names(data_ref))
  if (!length(voc_cols)) return(data_ref)
  for (v in voc_cols) {
    if (!is.numeric(data_ref[[v]])) {
      data_ref[[v]] <- suppressWarnings(as.numeric(data_ref[[v]]))
    }
  }
  data_ref
}

environment_filter_raw_by_seqn <- function(raw_df, keep_seqn, exclude_seqn = integer(0)) {
  id_col <- if ("SEQN" %in% names(raw_df)) "SEQN" else "ID"
  ids <- as.numeric(raw_df[[id_col]])
  keep <- ids %in% as.numeric(keep_seqn) & !(ids %in% as.numeric(exclude_seqn))
  raw_df[keep, , drop = FALSE]
}

environment_apply_cohort_weight_requirement <- function(EnvResult, env_wt_df) {
  if (is.null(env_wt_df) || !nrow(env_wt_df)) return(EnvResult)
  wt_ok <- env_wt_df$SEQN[is.finite(env_wt_df$WTSA2YR) & env_wt_df$WTSA2YR > 0]
  n_before <- nrow(EnvResult)
  EnvResult <- EnvResult[EnvResult$SEQN %in% wt_ok, , drop = FALSE]
  dropped <- setdiff(as.numeric(unique(EnvResult$SEQN)), wt_ok)
  if (n_before > nrow(EnvResult)) {
    cli::cli_alert_info(
      "require_env_weight: 剔除无有效 WTSA2YR 的 {n_before - nrow(EnvResult)} 人 → n={nrow(EnvResult)}"
    )
  }
  EnvResult
}
