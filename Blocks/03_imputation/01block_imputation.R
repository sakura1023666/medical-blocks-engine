###############################################################################
#  imputation — MICE 多重插补、缺失热图、插补前后 Table S1（SCI 三线表）。
#
#  register_block: "imputation"
#  典型流水线: data_clean（± column_mapping）之后；下游均读 ctx$data$imputed
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$mapped %||% ctx$data$cleaned
#
#  # ── 配置 config$imputation ─────────────────────────────────────────────────
#  imputation = list(
#    missing_col_threshold  = 0.2,    # 插补前：列缺失率超阈值则删列
#    method                 = "cart", # MICE 单变量法（mice 包 method）
#    m                      = 5L,     # 插补数据集个数
#    max_iter               = 5L,     # Gibbs 迭代次数
#    seed                   = 1234L,  # 须与 config 全局种子一致；块内不私自 set.seed
#    complete_action        = 1L,     # 操作层单套 complete（trim/FS/轨迹）写入 imputed
#    rubin_pool             = TRUE,   # m>1 时推断回归默认 Rubin 合并（R/mi_rubin_pool.R）
#    required_non_na_cols   = NULL,   # 这些列均非 NA 才保留行
#    var_ranges             = NULL,   # 插补后数值/因子水平范围约束 list
#    export_missing_fig     = FALSE,  # 是否导出缺失模式热图 PDF（双库拼图后默认关闭）
#    missing_fig_filename   = NULL,   # 固定 PDF 名（不占 Figure Sn. 序号）；NULL → Figure_Missing_Value_Overview.pdf
#    missing_fig_title      = NULL,   # 图内标题；NULL → "Variable missing value overview in {database} cohort"
#    export_table_s1        = TRUE,   # 是否导出插补前后 Table S1
#    table_s1_title         = NULL,
#    table_s1_filename      = NULL,
#    table_s1_exclude_vars  = NULL,   # 额外排除列；引擎默认再排除 fustatus /
#                                     # survival$event_var / data$outcome_column（结局不作 S1 行）
#    fit_on                 = "all"   # TST 必须 "train"：仅 train 估计 MICE；
#                                     # 须先有 ctx$data$train/test（或 tst_split 物化：test=val∪test）；
#                                     # validation/test 用 mice(ignore=TRUE) 由同一模型填入（不泄漏）；
#                                     # 失败则回退 train 列中位数/众数填 test；
#                                     # 禁止对 val/test 各自重新 mice()；complete_action 取第几套写入 imputed
#    # 另见全局 config$analysis_var_policy：生成表/图前删除任一层级 n<20 的分类列
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$imputed, ctx$data$train/test（fit_on=train）, ctx$results$mice_model, ctx$results$table_s1
#  文件: Figure_Missing_Value_Overview.pdf（固定名，不占 Figure Sn. 序号；可镜像至根 Figures/）；
#       Table S1 xlsx/tex（每变量在 Before MI 有缺失时多一行 Missing (%)）；D01_AfterMI_Data.RData（行名=ID）
#  源: Blocks/block_imputation.R（父块保留；Blocks/03_imputation 为目录化副本）
###############################################################################

# Table S1：每个变量都追加 Missing (%)（0% 也显式标注，避免表内格式不一致）
.imp01_s1_missing_pct_row <- function(x_before, x_after, n_before, n_after) {
  if (exists("pipeline_s1_missing_pct_row", mode = "function")) {
    return(pipeline_s1_missing_pct_row(x_before, x_after, n_before, n_after))
  }
  n_miss_b <- sum(is.na(x_before))
  n_miss_a <- sum(is.na(x_after))
  pct_b <- if (isTRUE(n_before > 0L)) n_miss_b / n_before * 100 else 0
  pct_a <- if (isTRUE(n_after > 0L)) n_miss_a / n_after * 100 else 0
  data.frame(
    Variable = "  Missing (%)",
    Statistic = "",
    Before_MI = paste0(fmt_num(pct_b), "%"),
    After_MI  = paste0(fmt_num(pct_a), "%"),
    P_value = "",
    .is_cat_row = TRUE,
    .is_section_row = FALSE,
    stringsAsFactors = FALSE
  )
}

.imp01_test_normality <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3) return(FALSE)
  p <- tryCatch({
    if (n > 5000) stats::ks.test(scale(x), "pnorm")$p.value
    else          stats::shapiro.test(x)$p.value
  }, error = function(e) 0)
  p >= 0.05
}

.imp01_constrain_ranges <- function(imputed_df, var_ranges) {
  if (is.null(var_ranges) || length(var_ranges) == 0) return(imputed_df)
  for (var in names(var_ranges)) {
    if (!var %in% names(imputed_df)) next
    range_val <- var_ranges[[var]]
    if (is.numeric(range_val) && length(range_val) == 2) {
      lower <- range_val[1]
      upper <- range_val[2]
      imputed_df[[var]] <- ifelse(
        imputed_df[[var]] < lower, lower,
        ifelse(imputed_df[[var]] > upper, upper, imputed_df[[var]])
      )
    } else if (is.character(range_val)) {
      legal_vals <- range_val
      imputed_df[[var]] <- ifelse(
        imputed_df[[var]] %in% legal_vals,
        imputed_df[[var]], legal_vals[1]
      )
    }
  }
  imputed_df
}

.imp01_detect_id_cols <- function(data, cfg) {
  id_col_cfg <- cfg$data$id_column %||% NULL
  id_candidates <- unique(c(id_col_cfg, "ID", "subject_id", "SEQN", "patient_id", "hadm_id"))
  intersect(id_candidates, names(data))
}

.imp01_primary_id_col <- function(id_cols, cfg) {
  id_cfg <- cfg$data$id_column %||% NULL
  if (!is.null(id_cfg) && id_cfg %in% id_cols) return(id_cfg)
  id_cols[1L]
}

.imp01_prepare_for_save <- function(data_imputed, id_cols, primary_id) {
  out <- data_imputed
  if (length(primary_id) == 1L && primary_id %in% names(out)) {
    rn <- as.character(out[[primary_id]])
    if (anyDuplicated(rn)) {
      cli::cli_alert_warning("ID 列存在重复，保留 ID 列（纵向数据），不设置行名: {primary_id}")
    } else {
      rownames(out) <- rn
      out[[primary_id]] <- NULL
    }
  }
  drop_cols <- setdiff(id_cols, primary_id)
  if (length(drop_cols)) {
    out <- out[, setdiff(names(out), drop_cols), drop = FALSE]
  }
  out
}

.imp01_missing_keep_mask <- function(data_work, missing_col_threshold, imp_cfg, cfg) {
  missing.percent <- colMeans(is.na(data_work))
  keep <- missing.percent <= missing_col_threshold
  # 双库：伙伴库缺失率超阈值的列一并剔除，保证后续所有表/图列集合对齐
  if (exists("pipeline_dual_db_partner_high_missing_cols", mode = "function")) {
    partner_drop <- pipeline_dual_db_partner_high_missing_cols(cfg, missing_col_threshold)
    partner_drop <- intersect(partner_drop, names(data_work))
    if (length(partner_drop)) {
      keep[partner_drop] <- FALSE
      cli::cli_alert_warning(
        "dual_db 缺失并集锁定：额外剔除伙伴库高缺失列 {length(partner_drop)} 个: {paste(utils::head(partner_drop, 12), collapse = ', ')}{if (length(partner_drop) > 12) '...' else ''}"
      )
    }
  }
  if (isTRUE(imp_cfg$force_keep_weight_cols %||% FALSE)) {
    protect_wt <- if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
      nhanes_survey_weight_source_cols(cfg)
    } else {
      c("WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTSAF2YR", "WTSAF4YR",
        "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR", "new_Weight")
    }
    force_keep <- intersect(protect_wt, names(data_work))
    keep[force_keep] <- TRUE
  }
  force_keep_extra <- as.character(imp_cfg$force_keep_columns %||% character(0))
  if (length(force_keep_extra)) {
    fk <- intersect(force_keep_extra, names(data_work))
    if (length(fk)) keep[fk] <- TRUE
  }
  # 保护结局/暴露/ID/Age/Gender；Height/Weight/BMI 超阈值照删
  if (exists("pipeline_imputation_missing_protect_vars", mode = "function")) {
    prot <- intersect(pipeline_imputation_missing_protect_vars(cfg), names(data_work))
    if (length(prot)) keep[prot] <- TRUE
  }
  keep
}

.imp01_filter_analysis_rows <- function(data_work, outcome_col, required_non_na) {
  if (outcome_col %in% names(data_work)) {
    n_before <- nrow(data_work)
    data_work <- data_work[!is.na(data_work[[outcome_col]]), , drop = FALSE]
    if (nrow(data_work) < n_before) {
      cli::cli_alert_info("剔除结局缺失行: {n_before - nrow(data_work)} 行")
    }
  }
  if (length(required_non_na)) {
    for (col in required_non_na) {
      if (!col %in% names(data_work)) next
      n_before <- nrow(data_work)
      data_work <- data_work[!is.na(data_work[[col]]), , drop = FALSE]
      if (nrow(data_work) < n_before) {
        cli::cli_alert_info("剔除 {col} 缺失行: {n_before - nrow(data_work)} 行")
      }
    }
  }
  data_work
}

.imp01_build_mice_inputs <- function(data_work, cfg, imp_cfg, id_cols_present, outcome_col) {
  mice_skip <- unique(c(
    as.character(imp_cfg$exclude_from_mice_cols %||% character(0)),
    if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
      nhanes_survey_weight_source_cols(cfg)
    } else {
      c("Source_File", "SDDSRVYR", "WTSA2YR", "WTSAF2YR", "WTSAF4YR",
        "WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTINT4YR",
        "SDMVPSU", "SDMVSTRA", "new_Weight")
    }
  ))
  mice_skip <- intersect(mice_skip, names(data_work))
  id_for_attach <- NULL
  if (length(id_cols_present)) {
    id_for_attach <- data_work[, id_cols_present, drop = FALSE]
    data_mice <- data_work[, setdiff(names(data_work), c(id_cols_present, mice_skip)), drop = FALSE]
  } else {
    data_mice <- data_work[, setdiff(names(data_work), mice_skip), drop = FALSE]
  }
  mice_attach <- data_work[, intersect(mice_skip, names(data_work)), drop = FALSE]
  outcome_attach <- if (outcome_col %in% names(data_work)) data_work[[outcome_col]] else NULL
  if (outcome_col %in% names(data_work) && outcome_col %in% names(data_mice)) {
    data_mice <- data_mice[, setdiff(names(data_mice), outcome_col), drop = FALSE]
  }
  list(
    data_mice = data_mice,
    id_for_attach = id_for_attach,
    mice_attach = mice_attach,
    outcome_attach = outcome_attach,
    mice_skip = mice_skip
  )
}

.imp01_sanitize_mice_matrix <- function(data_mice, data_work, cfg) {
  if (exists("pipeline_sanitize_numeric_for_mice", mode = "function")) {
    san <- pipeline_sanitize_numeric_for_mice(data_mice, cfg)
    data_mice <- san$data
    if (san$n_nonfinite > 0L || san$n_pp_filled > 0L) {
      cli::cli_alert_info(
        "插补前数值清洗: 非有限→NA {san$n_nonfinite}，PP 回填 {san$n_pp_filled}"
      )
    }
  } else {
    for (col in names(data_mice)) {
      if (is.numeric(data_mice[[col]])) {
        x <- data_mice[[col]]
        x[!is.finite(x)] <- NA_real_
        data_mice[[col]] <- x
      }
    }
  }
  for (col in names(data_mice)) {
    if (col %in% names(data_work)) data_work[[col]] <- data_mice[[col]]
  }
  list(data_mice = data_mice, data_work = data_work)
}

.imp01_drop_unusable_mice_cols <- function(data_mice, data_work, cfg = list()) {
  all_na <- vapply(data_mice, function(x) all(is.na(x)), logical(1L))
  if (any(all_na)) {
    drop_na <- names(data_mice)[all_na]
    cli::cli_alert_warning("插补前剔除全 NA 列: {paste(drop_na, collapse = ', ')}")
    data_mice <- data_mice[, !all_na, drop = FALSE]
    data_work <- data_work[, !names(data_work) %in% drop_na, drop = FALSE]
  }
  zero_var <- vapply(data_mice, function(x) {
    if (!is.numeric(x)) return(FALSE)
    v <- x[is.finite(x)]
    length(v) < 2L || stats::sd(v) == 0
  }, logical(1L))
  if (any(zero_var)) {
    drop_zv <- names(data_mice)[zero_var]
    cli::cli_alert_warning("插补前剔除零方差数值列: {paste(drop_zv, collapse = ', ')}")
    data_mice <- data_mice[, !zero_var, drop = FALSE]
    data_work <- data_work[, !names(data_work) %in% drop_zv, drop = FALSE]
  }
  # 双库：伙伴库不可用列一并剔除
  if (exists("pipeline_dual_db_partner_unusable_cols", mode = "function")) {
    pd <- pipeline_dual_db_partner_unusable_cols(cfg)
    pd <- intersect(pd, names(data_work))
    if (length(pd)) {
      cli::cli_alert_warning(
        "dual_db 不可用列并集锁定：额外剔除 {length(pd)} 列: {paste(utils::head(pd, 12), collapse = ', ')}{if (length(pd) > 12) '...' else ''}"
      )
      data_mice <- data_mice[, setdiff(names(data_mice), pd), drop = FALSE]
      data_work <- data_work[, setdiff(names(data_work), pd), drop = FALSE]
    }
  }
  list(data_mice = data_mice, data_work = data_work)
}

.imp01_residual_median_mode_fill <- function(data_imp) {
  n_resid <- sum(is.na(data_imp))
  if (n_resid <= 0L) return(data_imp)
  resid_cols <- names(data_imp)[vapply(data_imp, function(x) any(is.na(x)), logical(1L))]
  for (cn in resid_cols) {
    x <- data_imp[[cn]]
    if (is.numeric(x)) {
      fillv <- stats::median(x, na.rm = TRUE)
      if (is.finite(fillv)) data_imp[[cn]][is.na(x)] <- fillv
    } else {
      tab <- sort(table(x[!is.na(x)]), decreasing = TRUE)
      if (length(tab)) {
        mode_v <- names(tab)[1L]
        if (is.factor(x)) {
          data_imp[[cn]] <- as.character(x)
          data_imp[[cn]][is.na(data_imp[[cn]])] <- mode_v
          data_imp[[cn]] <- factor(data_imp[[cn]], levels = levels(x))
        } else {
          data_imp[[cn]][is.na(x)] <- mode_v
        }
      }
    }
  }
  cli::cli_alert_info(
    "MICE 后残留 NA {n_resid} 个（共线性跳过列），已用中位数/众数兜底填补: {paste(resid_cols, collapse = ', ')}"
  )
  data_imp
}

.imp01_fill_na_from_reference <- function(target, reference, cols = intersect(names(target), names(reference))) {
  out <- target
  for (cn in cols) {
    if (!cn %in% names(out) || !cn %in% names(reference)) next
    na_idx <- is.na(out[[cn]])
    if (!any(na_idx)) next
    ref_x <- reference[[cn]]
    tgt_x <- out[[cn]]
    if (is.numeric(tgt_x) || is.numeric(ref_x)) {
      fillv <- stats::median(ref_x, na.rm = TRUE)
      if (is.finite(fillv)) out[[cn]][na_idx] <- fillv
    } else {
      tab <- sort(table(ref_x[!is.na(ref_x)]), decreasing = TRUE)
      if (length(tab)) {
        mode_v <- names(tab)[1L]
        if (is.factor(tgt_x)) {
          out[[cn]] <- as.character(tgt_x)
          out[[cn]][na_idx] <- mode_v
          if (length(levels(tgt_x))) {
            out[[cn]] <- factor(out[[cn]], levels = unique(c(levels(tgt_x), mode_v)))
          } else {
            out[[cn]] <- factor(out[[cn]])
          }
        } else {
          out[[cn]][na_idx] <- mode_v
        }
      }
    }
  }
  out
}

.imp01_reattach_mice_extras <- function(data_imp, id_for_attach, mice_attach, outcome_attach, outcome_col) {
  if (!is.null(id_for_attach) && nrow(id_for_attach) == nrow(data_imp)) {
    for (nm in names(id_for_attach)) data_imp[[nm]] <- id_for_attach[[nm]]
  }
  if (ncol(mice_attach) && nrow(mice_attach) == nrow(data_imp)) {
    for (nm in names(mice_attach)) data_imp[[nm]] <- mice_attach[[nm]]
  }
  if (!is.null(outcome_attach) && length(outcome_attach) == nrow(data_imp)) {
    data_imp[[outcome_col]] <- outcome_attach
  }
  data_imp
}


# 数值稳定 PMM：在观测子集上剔除近常值 / QR 秩亏列后再走标准 PMM donor 匹配。
# mice::estimice 在 diag(X'X)=0 时即使用 ridge 仍会 solve 失败；本方法保持 PMM 算法，
# 仅做设计矩阵局部剪枝，并在极端情况下用 ginv 完成回归系数抽样。
.imp01_pmm_clean_x <- function(x, ry, tol = 1e-8) {
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  x[!is.finite(x)] <- 0
  if (!any(ry) || ncol(x) < 1L) return(x[, FALSE, drop = FALSE])
  xr <- x[ry, , drop = FALSE]
  keep <- vapply(seq_len(ncol(xr)), function(j) {
    z <- xr[, j]
    z <- z[is.finite(z)]
    length(z) >= 2L && is.finite(stats::sd(z)) && stats::sd(z) > tol
  }, logical(1L))
  if (!any(keep)) return(x[, FALSE, drop = FALSE])
  x <- x[, keep, drop = FALSE]
  xr <- x[ry, , drop = FALSE]
  if (ncol(xr) >= 2L) {
    q <- qr(xr, tol = tol)
    rnk <- q$rank
    if (is.finite(rnk) && rnk >= 1L && rnk < ncol(xr)) {
      x <- x[, sort(q$pivot[seq_len(rnk)]), drop = FALSE]
    }
  }
  x
}

.imp01_pmm_norm_draw <- function(y, ry, x, ridge = 1e-05) {
  # x 已含截距列；返回 list(coef, beta, sigma) 对齐 mice::.norm.draw
  xobs <- x[ry, , drop = FALSE]
  yobs <- as.numeric(y[ry])
  n <- nrow(xobs)
  p <- ncol(xobs)
  df <- max(n - p, 1L)
  xtx <- crossprod(xobs)
  d <- diag(xtx)
  pen <- as.numeric(ridge) * d
  pen[!is.finite(pen) | d < 1e-12] <- max(as.numeric(ridge), 1e-3)
  A <- xtx + diag(pen, nrow = p)
  v <- tryCatch(
    solve(A),
    error = function(e) {
      if (requireNamespace("MASS", quietly = TRUE)) MASS::ginv(A) else {
        # 对角兜底
        diag(1 / pmax(diag(A), 1e-8), nrow = p)
      }
    }
  )
  coef <- as.vector(v %*% crossprod(xobs, yobs))
  resid <- yobs - as.vector(xobs %*% coef)
  rss <- sum(resid^2)
  sigma <- sqrt(rss / stats::rchisq(1L, df))
  # chol(v) 可能因半正定失败 → 用对称化 + 对角抖动
  v2 <- (v + t(v)) / 2
  ev <- tryCatch(eigen(v2, symmetric = TRUE), error = function(e) NULL)
  if (is.null(ev)) {
    beta <- coef
  } else {
    lam <- pmax(ev$values, 0)
    R <- ev$vectors %*% diag(sqrt(lam), nrow = length(lam))
    beta <- coef + as.vector(R %*% stats::rnorm(p)) * sigma
  }
  list(coef = coef, beta = beta, sigma = sigma)
}

mice.impute.pmm_stable <- function(y, ry, x, wy = NULL, donors = 5L, matchtype = 1L,
                                   ridge = 1e-05, ...) {
  if (is.null(wy)) wy <- !ry
  x <- .imp01_pmm_clean_x(x, ry)
  if (ncol(x) < 1L || sum(ry) < 2L) {
    return(sample(y[ry], size = sum(wy), replace = TRUE))
  }
  x <- cbind(1, x)
  ynum <- y
  if (is.factor(y)) ynum <- as.integer(y)
  parm <- tryCatch(
    .imp01_pmm_norm_draw(ynum, ry, x, ridge = max(as.numeric(ridge), 1e-3)),
    error = function(e) NULL
  )
  if (is.null(parm)) {
    return(sample(y[ry], size = sum(wy), replace = TRUE))
  }
  if (as.integer(matchtype) == 0L) {
    yhatobs <- as.vector(x[ry, , drop = FALSE] %*% parm$coef)
    yhatmis <- as.vector(x[wy, , drop = FALSE] %*% parm$coef)
  } else if (as.integer(matchtype) == 2L) {
    yhatobs <- as.vector(x[ry, , drop = FALSE] %*% parm$beta)
    yhatmis <- as.vector(x[wy, , drop = FALSE] %*% parm$beta)
  } else {
    yhatobs <- as.vector(x[ry, , drop = FALSE] %*% parm$coef)
    yhatmis <- as.vector(x[wy, , drop = FALSE] %*% parm$beta)
  }
  if (any(!is.finite(yhatobs)) || any(!is.finite(yhatmis))) {
    return(sample(y[ry], size = sum(wy), replace = TRUE))
  }
  idx <- mice::matchindex(yhatobs, yhatmis, donors)
  y[ry][idx]
}

.imp01_prune_mice_collinearity <- function(data_mice,
                                           cor_threshold = 0.95,
                                           min_complete = 30L) {
  # Drop near-constant / highly collinear numeric predictors that break PMM .norm.draw.
  if (!is.data.frame(data_mice) || ncol(data_mice) < 2L) {
    return(list(data_mice = data_mice, dropped = character(0)))
  }
  dropped <- character(0)
  keep <- vapply(names(data_mice), function(cn) {
    x <- data_mice[[cn]]
    if (is.factor(x) || is.character(x)) {
      u <- unique(as.character(x[!is.na(x)]))
      return(length(u) >= 2L)
    }
    if (!is.numeric(x)) return(TRUE)
    v <- x[is.finite(x)]
    if (length(v) < as.integer(min_complete)) return(FALSE)
    stats::sd(v) > 0
  }, logical(1L))
  if (any(!keep)) {
    drop1 <- names(data_mice)[!keep]
    dropped <- c(dropped, drop1)
    cli::cli_alert_warning(
      "PMM 预检剔除近常值/低有效样本列 {length(drop1)}: {paste(utils::head(drop1, 8), collapse = ', ')}{if (length(drop1) > 8) '...' else ''}"
    )
    data_mice <- data_mice[, keep, drop = FALSE]
  }
  num_cols <- names(data_mice)[vapply(data_mice, is.numeric, logical(1L))]
  if (length(num_cols) >= 2L) {
    mat <- as.matrix(data_mice[, num_cols, drop = FALSE])
    cm <- suppressWarnings(stats::cor(mat, use = "pairwise.complete.obs"))
    cm[!is.finite(cm)] <- 0
    n_miss <- colSums(!is.finite(mat))
    drop2 <- character(0)
    for (i in seq_len(ncol(cm) - 1L)) {
      if (num_cols[i] %in% drop2) next
      for (j in (i + 1L):ncol(cm)) {
        if (num_cols[j] %in% drop2) next
        if (abs(cm[i, j]) >= as.numeric(cor_threshold)) {
          loser <- if (n_miss[i] <= n_miss[j]) num_cols[j] else num_cols[i]
          drop2 <- c(drop2, loser)
        }
      }
    }
    drop2 <- unique(drop2)
    if (length(drop2)) {
      dropped <- c(dropped, drop2)
      cli::cli_alert_warning(
        "PMM 预检剔除高相关(|r|>={cor_threshold})列 {length(drop2)}: {paste(utils::head(drop2, 8), collapse = ', ')}{if (length(drop2) > 8) '...' else ''}"
      )
      data_mice <- data_mice[, setdiff(names(data_mice), drop2), drop = FALSE]
      num_cols <- setdiff(num_cols, drop2)
    }
    if (length(num_cols) >= 2L) {
      mat2 <- as.matrix(data_mice[, num_cols, drop = FALSE])
      cc <- stats::complete.cases(mat2)
      if (sum(cc) >= max(30L, length(num_cols) + 5L)) {
        sc <- scale(mat2[cc, , drop = FALSE])
        sc[!is.finite(sc)] <- 0
        q <- qr(sc, tol = 1e-8)
        rnk <- q$rank
        if (is.finite(rnk) && rnk < length(num_cols)) {
          dep <- num_cols[q$pivot[seq.int(rnk + 1L, length(num_cols))]]
          dropped <- c(dropped, dep)
          cli::cli_alert_warning(
            "PMM 预检 QR 秩亏剔除 {length(dep)} 列: {paste(utils::head(dep, 8), collapse = ', ')}{if (length(dep) > 8) '...' else ''}"
          )
          data_mice <- data_mice[, setdiff(names(data_mice), dep), drop = FALSE]
        }
      }
    }
  }
  list(data_mice = data_mice, dropped = unique(dropped))
}

.imp01_run_mice <- function(data_mice, method, m, max_iter, seed, complete_action,
                              ignore = NULL, ridge = 1e-2, cor_threshold = 0.95,
                              allow_cart_fallback = FALSE) {
  method_req <- as.character(method %||% "pmm")[1L]
  method <- method_req
  # 配置写 pmm 时改走数值稳定 PMM（算法仍为 predictive mean matching）
  if (identical(tolower(method), "pmm")) {
    if (!exists("mice.impute.pmm_stable", mode = "function", inherits = TRUE)) {
      stop("mice.impute.pmm_stable 未加载（检查 Blocks/03_imputation/01block_imputation.R）", call. = FALSE)
    }
    method <- "pmm_stable"
    cli::cli_alert_info("MICE method=pmm → pmm_stable（局部设计矩阵剪枝 + ginv，保持 PMM donor 匹配）")
  }
  ridge <- as.numeric(ridge %||% 1e-2)[1L]
  if (!is.finite(ridge) || ridge < 0) ridge <- 1e-2
  cor_threshold <- as.numeric(cor_threshold %||% 0.95)[1L]

  dropped_hold <- NULL
  if (tolower(method_req) %in% c("pmm", "norm", "norm.nob", "norm.boot", "norm.predict") ||
      identical(method, "pmm_stable")) {
    for (thr in unique(c(cor_threshold, 0.95, 0.90, 0.85))) {
      pruned <- .imp01_prune_mice_collinearity(data_mice, cor_threshold = thr)
      if (length(pruned$dropped)) {
        hold_cols <- intersect(pruned$dropped, names(data_mice))
        if (length(hold_cols)) {
          add <- data_mice[, hold_cols, drop = FALSE]
          if (is.null(dropped_hold)) dropped_hold <- add
          else for (cn in names(add)) if (!cn %in% names(dropped_hold)) dropped_hold[[cn]] <- add[[cn]]
        }
      }
      data_mice <- pruned$data_mice
    }
  }

  # 数值列 z-score，降低极端尺度导致的条件数爆炸（插补后还原）
  scale_center <- NULL
  scale_sd <- NULL
  num_scale <- names(data_mice)[vapply(data_mice, is.numeric, logical(1L))]
  if (length(num_scale)) {
    scale_center <- vapply(num_scale, function(cn) {
      v <- data_mice[[cn]]; v <- v[is.finite(v)]
      if (!length(v)) 0 else as.numeric(stats::median(v))
    }, numeric(1L))
    scale_sd <- vapply(num_scale, function(cn) {
      v <- data_mice[[cn]]; v <- v[is.finite(v)]
      if (length(v) < 2L) 1 else {
        s <- stats::sd(v); if (!is.finite(s) || s < 1e-12) 1 else s
      }
    }, numeric(1L))
    for (cn in num_scale) {
      data_mice[[cn]] <- (data_mice[[cn]] - scale_center[[cn]]) / scale_sd[[cn]]
    }
    cli::cli_alert_info("MICE 前对 {length(num_scale)} 个数值列做中位数/SD 标准化（完成后还原）")
  }

  pred <- NULL
  if (ncol(data_mice) >= 2L) {
    pred <- tryCatch(
      mice::quickpred(data_mice, mincor = 0.1, minpuc = 0.25),
      error = function(e) NULL
    )
    if (!is.null(pred)) {
      for (i in seq_len(nrow(pred))) {
        idx <- which(pred[i, ] != 0)
        if (length(idx) > 12L) pred[i, idx[-seq_len(12L)]] <- 0
      }
      cli::cli_alert_info(
        "MICE quickpred: 平均每变量 {round(mean(rowSums(pred)), 1)} 个预测变量（已封顶 ≤12）"
      )
    }
  }

  run_once <- function(meth, ridge_val, pred_mat = pred) {
    cli::cli_h2(
      "Running MICE (method={meth}, m={m}, maxit={max_iter}, seed={seed}, ridge={ridge_val})"
    )
    mice_args <- list(
      data = data_mice, m = m, seed = seed, method = meth,
      maxit = max_iter, ridge = ridge_val, printFlag = FALSE,
      remove.collinear = TRUE, remove.constant = TRUE
    )
    if (!is.null(pred_mat)) mice_args$predictorMatrix <- pred_mat
    if (!is.null(ignore)) {
      ignore <- as.logical(ignore)
      if (length(ignore) != nrow(data_mice)) stop("mice ignore 长度须 = nrow(data)", call. = FALSE)
      mice_args$ignore <- ignore
      cli::cli_alert_info(
        "MICE ignore: fit on {sum(!ignore, na.rm = TRUE)} rows; apply-to {sum(ignore, na.rm = TRUE)} held-out rows"
      )
    }
    do.call(mice::mice, mice_args)
  }

  rid_try <- unique(c(ridge, 1e-2, 5e-2, 1e-1, 0.5, 1.0))
  rid_try <- rid_try[is.finite(rid_try) & rid_try > 0]
  imp <- NULL
  last_err <- NULL
  for (rv in rid_try) {
    imp <- tryCatch(
      run_once(method, rv, pred),
      error = function(e) {
        last_err <<- e
        cli::cli_alert_warning("MICE {method} 失败（ridge={rv}）: {conditionMessage(e)}；继续重试")
        NULL
      }
    )
    if (!is.null(imp)) break
  }
  if (is.null(imp) && !is.null(pred)) {
    pred2 <- pred
    for (i in seq_len(nrow(pred2))) {
      idx <- which(pred2[i, ] != 0)
      if (length(idx) > 5L) pred2[i, idx[-seq_len(5L)]] <- 0
    }
    cli::cli_alert_warning("PMM 仍失败：收紧 predictorMatrix 至每变量 ≤5 个预测变量后重试")
    for (rv in c(0.1, 0.5, 1.0)) {
      imp <- tryCatch(
        run_once(method, rv, pred2),
        error = function(e) {
          last_err <<- e
          cli::cli_alert_warning("MICE {method} 失败（ridge={rv}, ≤5 pred）: {conditionMessage(e)}")
          NULL
        }
      )
      if (!is.null(imp)) break
    }
  }
  if (is.null(imp) && isTRUE(allow_cart_fallback) &&
      !tolower(method) %in% c("cart") && !identical(tolower(method_req), "cart")) {
    cli::cli_alert_warning("PMM 仍失败；config 允许 cart 回退（m={m}）")
    imp <- tryCatch(run_once("cart", max(ridge, 1e-3), pred), error = function(e) { last_err <<- e; NULL })
  }
  if (is.null(imp)) {
    stop(
      "MICE PMM 失败（pmm_stable + 共线剪枝 + ridge + quickpred 仍失败）: ",
      if (!is.null(last_err)) conditionMessage(last_err) else "unknown",
      call. = FALSE
    )
  }
  data_imp <- mice::complete(imp, action = complete_action)
  if (!is.null(dropped_hold) && ncol(dropped_hold) > 0L && nrow(dropped_hold) == nrow(data_imp)) {
    # 共线预检剔出的列：用已完成主集作预测子，再跑一轮 PMM（仍文献级 PMM，非 cart/中位数）
    stage2 <- dropped_hold
    # stage2 与 data_imp 同尺度：若主集已标准化，hold 列也需同样标准化
    if (!is.null(scale_center) && !is.null(scale_sd)) {
      for (cn in intersect(names(stage2), names(scale_center))) {
        if (is.numeric(stage2[[cn]])) {
          stage2[[cn]] <- (stage2[[cn]] - scale_center[[cn]]) / scale_sd[[cn]]
        }
      }
    }
    pred_cols <- names(data_imp)
    s2_df <- cbind(stage2, data_imp[, pred_cols, drop = FALSE])
    s2_method <- rep("", ncol(s2_df))
    names(s2_method) <- names(s2_df)
    s2_method[names(stage2)] <- if (exists("mice.impute.pmm_stable", mode = "function", inherits = TRUE)) {
      "pmm_stable"
    } else {
      "pmm"
    }
    s2_pred <- matrix(0L, nrow = ncol(s2_df), ncol = ncol(s2_df),
                      dimnames = list(names(s2_df), names(s2_df)))
    for (cn in names(stage2)) {
      s2_pred[cn, pred_cols] <- 1L
      s2_pred[cn, cn] <- 0L
    }
    cli::cli_alert_info(
      "共线预检列二阶段 PMM: {paste(names(stage2), collapse = ', ')}（预测子=主集完成列）"
    )
    s2_imp <- tryCatch(
      mice::mice(
        s2_df, m = 1L, maxit = max(3L, as.integer(max_iter)), seed = seed,
        method = s2_method, predictorMatrix = s2_pred,
        ridge = max(ridge, 1e-2), printFlag = FALSE,
        remove.collinear = TRUE, remove.constant = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning("二阶段 PMM 失败: {conditionMessage(e)}；该列稍后中位数兜底")
        NULL
      }
    )
    if (!is.null(s2_imp)) {
      s2_done <- mice::complete(s2_imp, action = 1L)
      for (cn in names(stage2)) data_imp[[cn]] <- s2_done[[cn]]
    } else {
      for (cn in names(stage2)) data_imp[[cn]] <- stage2[[cn]]
    }
  }
  if (!is.null(scale_center) && !is.null(scale_sd)) {
    for (cn in intersect(names(scale_center), names(data_imp))) {
      if (is.numeric(data_imp[[cn]])) {
        data_imp[[cn]] <- data_imp[[cn]] * scale_sd[[cn]] + scale_center[[cn]]
      }
    }
  }
  data_imp <- .imp01_residual_median_mode_fill(data_imp)
  meth_used <- unique(as.character(imp$method[nzchar(as.character(imp$method))]))
  cli::cli_alert_success(
    "Imputation complete (requested={method_req}, used={paste(meth_used, collapse=',')}). Remaining NA: {sum(is.na(data_imp))}"
  )
  list(data_imp = data_imp, imp = imp)
}

.imp01_prepare_work_frame <- function(data, cfg, imp_cfg, outcome_col, required_non_na,
                                      missing_col_threshold, id_cols_present, keep_mask = NULL) {
  data_work <- .imp01_filter_analysis_rows(data, outcome_col, required_non_na)
  if (is.null(keep_mask)) {
    keep_mask <- .imp01_missing_keep_mask(data_work, missing_col_threshold, imp_cfg, cfg)
  } else {
    keep_mask <- keep_mask[names(data_work)]
  }
  if (any(!keep_mask)) {
    dropped <- names(data_work)[!keep_mask]
    cli::cli_alert_info(
      "按 missing_col_threshold={missing_col_threshold} 剔除 {sum(!keep_mask)} 列: {paste(head(dropped, 8), collapse = ', ')}{if (sum(!keep_mask) > 8) '...' else ''}"
    )
  }
  data_work <- data_work[, keep_mask, drop = FALSE]
  mice_in <- .imp01_build_mice_inputs(data_work, cfg, imp_cfg, id_cols_present, outcome_col)
  san <- .imp01_sanitize_mice_matrix(mice_in$data_mice, data_work, cfg)
  drop <- .imp01_drop_unusable_mice_cols(san$data_mice, san$data_work, cfg)
  list(
    data_work = drop$data_work,
    data_mice = drop$data_mice,
    id_for_attach = mice_in$id_for_attach,
    mice_attach = mice_in$mice_attach,
    outcome_attach = mice_in$outcome_attach,
    keep_mask = keep_mask
  )
}

.imp01_align_test_to_train <- function(test_raw, train_imp) {
  common <- intersect(names(train_imp), names(test_raw))
  out <- test_raw[, common, drop = FALSE]
  missing_cols <- setdiff(names(train_imp), names(out))
  if (length(missing_cols)) {
    for (cn in missing_cols) out[[cn]] <- rep(NA, nrow(out))
  }
  out[, names(train_imp), drop = FALSE]
}

#' 若尚无 train/test 宽表，但已有 tst_split ID，则从队列物化（test = val∪test）
.imp01_materialize_from_tst_split <- function(ctx, cfg) {
  need_train <- is.null(ctx$data$train) || !is.data.frame(ctx$data$train) || nrow(ctx$data$train) < 1L
  need_test <- is.null(ctx$data$test) || !is.data.frame(ctx$data$test)
  if (!need_train && !need_test) return(ctx)
  sp <- ctx$data$tst_split
  if (is.null(sp) || is.null(sp$train)) {
    stop(
      "fit_on='train' 需要 ctx$data$train/test，或先跑 tst_split 写出 ID 划分",
      call. = FALSE
    )
  }
  base <- ctx$data$tst_cohort %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(base) || !is.data.frame(base) || nrow(base) < 1L) {
    stop("fit_on='train' 无法从 tst_cohort/mapped/cleaned 物化 train/test", call. = FALSE)
  }
  id_col <- if ("tst_patient_id" %in% names(base)) {
    "tst_patient_id"
  } else {
    as.character(cfg$data$id_column %||% "stay_id")[1L]
  }
  if (!id_col %in% names(base)) {
    stop("fit_on='train' 物化失败：宽表无 ID 列 ", id_col, call. = FALSE)
  }
  pid <- as.character(base[[id_col]])
  train_ids <- as.character(sp$train)
  hold_ids <- unique(c(as.character(sp$val %||% character(0)), as.character(sp$test %||% character(0))))
  if (!length(hold_ids) && length(sp$test)) hold_ids <- as.character(sp$test)
  ctx$data$train <- base[pid %in% train_ids, , drop = FALSE]
  ctx$data$test <- base[pid %in% hold_ids, , drop = FALSE]
  if ("tst_patient_id" %in% names(base) == FALSE && id_col != "tst_patient_id") {
    # keep as-is
  }
  ctx$results$mi_holdout <- "val_union_test"
  cli::cli_alert_info(
    "imputation: materialized train={nrow(ctx$data$train)} holdout(val∪test)={nrow(ctx$data$test)} from tst_split"
  )
  ctx
}

.imp01_fit_on_train <- function(ctx, cfg, imp_cfg, finalize_fn) {
  ctx <- .imp01_materialize_from_tst_split(ctx, cfg)
  train_raw <- ctx$data$train
  test_raw <- ctx$data$test
  if (is.null(train_raw) || !is.data.frame(train_raw) || nrow(train_raw) < 1L) {
    stop(
      "fit_on='train' 需要非空 ctx$data$train（tst_split 物化 / train_validation / cross_db）",
      call. = FALSE
    )
  }
  if (is.null(test_raw) || !is.data.frame(test_raw)) {
    stop("fit_on='train' 需要 ctx$data$test（holdout = val∪test 或 validation）", call. = FALSE)
  }

  cli::cli_h2(
    "Imputation fit_on=train: MICE fit on training only; apply model to validation (mice::ignore)"
  )

  outcome_col <- cfg$data$outcome_column %||% "Disease"
  required_non_na <- imp_cfg$required_non_na_cols %||% NULL
  missing_col_threshold <- imp_cfg$missing_col_threshold %||% 0.2
  method <- imp_cfg$method %||% "cart"
  m <- as.integer(imp_cfg$m %||% 5L)
  max_iter <- as.integer(imp_cfg$max_iter %||% 5L)
  seed <- as.integer(imp_cfg$seed %||% 1234L)
  complete_action <- as.integer(imp_cfg$complete_action %||% 1L)
  mice_ridge <- as.numeric(imp_cfg$ridge %||% 1e-2)[1L]
  mice_cor_drop <- as.numeric(imp_cfg$cor_drop_threshold %||% 0.95)[1L]
  allow_cart_fb <- isTRUE(imp_cfg$allow_cart_fallback %||% FALSE)
  id_cols_present <- .imp01_detect_id_cols(train_raw, cfg)

  train_raw <- pipeline_ensure_outcome_group_column(train_raw, cfg)
  test_raw <- pipeline_ensure_outcome_group_column(test_raw, cfg)

  train_prep <- .imp01_prepare_work_frame(
    train_raw, cfg, imp_cfg, outcome_col, required_non_na,
    missing_col_threshold, id_cols_present
  )
  keep_names <- names(train_prep$data_work)
  test_work <- test_raw[, intersect(keep_names, names(test_raw)), drop = FALSE]
  test_work <- .imp01_filter_analysis_rows(test_work, outcome_col, required_non_na)
  no_impute_cols <- unique(c(
    outcome_col,
    "Group",
    as.character(required_non_na %||% character(0))
  ))

  data_before_mi <- train_prep$data_work
  train_mice <- train_prep$data_mice
  # test 使用与 train 相同的列集合（含类型对齐），禁止用 test 自有分布做阈值剔列
  test_for_mice <- test_work
  for (cn in names(train_mice)) {
    if (!cn %in% names(test_for_mice)) test_for_mice[[cn]] <- NA
  }
  test_mice <- test_for_mice[, names(train_mice), drop = FALSE]
  # 因子水平对齐到 train，避免 mice 新水平报错
  for (cn in names(test_mice)) {
    if (is.factor(train_mice[[cn]])) {
      test_mice[[cn]] <- factor(
        as.character(test_mice[[cn]]),
        levels = levels(train_mice[[cn]])
      )
    } else if (is.character(train_mice[[cn]]) && is.factor(test_mice[[cn]])) {
      test_mice[[cn]] <- as.character(test_mice[[cn]])
    }
  }

  n_tr <- nrow(train_mice)
  n_te <- nrow(test_mice)
  imp_obj <- NULL
  train_imp <- NULL
  test_imp <- NULL

  if (sum(is.na(train_mice)) == 0L && sum(is.na(test_mice)) == 0L) {
    cli::cli_alert_success("Train+test 无协变量缺失，跳过 MICE。")
    train_imp <- train_prep$data_work
    test_imp <- .imp01_align_test_to_train(test_work, train_imp)
  } else if (ncol(train_mice) < 2L) {
    cli::cli_alert_warning(
      "Train MICE 跳过（可插补列 < 2）；用 train 列中位数/众数填充 train+test"
    )
    mice_filled <- .imp01_residual_median_mode_fill(train_mice)
    train_imp <- .imp01_reattach_mice_extras(
      mice_filled,
      train_prep$id_for_attach,
      train_prep$mice_attach,
      train_prep$outcome_attach,
      outcome_col
    )
    test_aligned <- .imp01_align_test_to_train(test_work, train_imp)
    fill_cols <- setdiff(names(train_mice), no_impute_cols)
    test_imp <- .imp01_fill_na_from_reference(test_aligned, train_imp, cols = fill_cols)
  } else {
    stacked <- rbind(train_mice, test_mice)
    ignore <- c(rep(FALSE, n_tr), rep(TRUE, n_te))
    mice_ok <- FALSE
    tryCatch({
      mice_res <- .imp01_run_mice(
        stacked, method, m, max_iter, seed, complete_action,
        ignore = ignore, ridge = mice_ridge, cor_threshold = mice_cor_drop,
        allow_cart_fallback = allow_cart_fb
      )
      filled <- mice_res$data_imp
      train_mice_c <- filled[seq_len(n_tr), , drop = FALSE]
      test_mice_c <- filled[n_tr + seq_len(n_te), , drop = FALSE]
      train_imp <- .imp01_reattach_mice_extras(
        train_mice_c,
        train_prep$id_for_attach,
        train_prep$mice_attach,
        train_prep$outcome_attach,
        outcome_col
      )
      # test：协变量来自 ignore 路径填补；结局/ID 始终回到 validation 原始标签
      test_imp <- test_mice_c
      idn <- intersect(id_cols_present, names(test_work))
      if (length(idn) && nrow(test_work) == nrow(test_imp)) {
        for (cn in idn) test_imp[[cn]] <- test_work[[cn]]
      }
      if (outcome_col %in% names(test_work) && nrow(test_work) == nrow(test_imp)) {
        test_imp[[outcome_col]] <- test_work[[outcome_col]]
      }
      # 非小鼠列（未入 mice 的列）保留 test 原值
      extra_cn <- setdiff(names(test_work), names(test_imp))
      for (cn in extra_cn) {
        if (nrow(test_work) == nrow(test_imp)) test_imp[[cn]] <- test_work[[cn]]
      }
      if ("Group" %in% names(test_work) && nrow(test_work) == nrow(test_imp)) {
        test_imp$Group <- test_work$Group
      }
      imp_obj <- mice_res$imp
      mice_ok <- TRUE
    }, error = function(e) {
      cli::cli_alert_warning(
        "MICE ignore 路径失败（{conditionMessage(e)}）；回退 train-only MICE + train 中位数/众数填 test"
      )
    })
    if (!isTRUE(mice_ok)) {
      mice_res <- .imp01_run_mice(
        train_mice, method, m, max_iter, seed, complete_action,
        ridge = mice_ridge, cor_threshold = mice_cor_drop,
        allow_cart_fallback = allow_cart_fb
      )
      train_imp <- .imp01_reattach_mice_extras(
        mice_res$data_imp,
        train_prep$id_for_attach,
        train_prep$mice_attach,
        train_prep$outcome_attach,
        outcome_col
      )
      imp_obj <- mice_res$imp
      test_aligned <- .imp01_align_test_to_train(test_work, train_imp)
      fill_cols <- setdiff(names(train_mice), no_impute_cols)
      test_imp <- .imp01_fill_na_from_reference(test_aligned, train_imp, cols = fill_cols)
      extra_fill_cols <- setdiff(
        intersect(names(test_imp), names(train_imp)),
        c(fill_cols, no_impute_cols)
      )
      if (length(extra_fill_cols)) {
        test_imp <- .imp01_fill_na_from_reference(test_imp, train_imp, cols = extra_fill_cols)
      }
    }
  }

  # 残余 NA：始终用 completed train 的边际中位数/众数兜底（不引用 validation 分布）
  fill_cols <- setdiff(intersect(names(train_imp), names(test_imp)), no_impute_cols)
  if (length(fill_cols) && any(is.na(test_imp[fill_cols]))) {
    test_imp <- .imp01_fill_na_from_reference(test_imp, train_imp, cols = fill_cols)
  }
  if (length(fill_cols) && any(is.na(train_imp[fill_cols]))) {
    train_imp <- .imp01_residual_median_mode_fill(train_imp)
  }

  ext_all <- isTRUE(ctx$results$train_validation_external_all)
  if (ext_all) {
    ## 次库整库外验：train/test 是同一批人，禁止 rbind 翻倍
    test_imp <- train_imp
    pooled <- train_imp
    n_train <- nrow(train_imp)
    cli::cli_alert_info(
      "imputation external_all: 整库一次插补 n={n_train}，出一张全集 S1，不出第二张验证集 S1b。"
    )
  } else {
    n_train <- nrow(train_imp)
    pooled <- rbind(train_imp, test_imp)
  }

  tables_dir <- file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tables_dir)) dir.create(tables_dir, recursive = TRUE)
  note_path <- file.path(tables_dir, "Imputation_fit_on_train.txt")
  writeLines(
    c(
      "Imputation fit_on=train (prediction-model leakage-safe)",
      paste0("Train rows: ", nrow(train_imp)),
      paste0("Validation/test rows: ", nrow(test_imp)),
      "Order: train/test assignment BEFORE multiple imputation.",
      "Train: MICE (mice::mice) estimated on training rows only.",
      "Holdout (val∪test or validation): imputed by the SAME MICE run via mice(ignore=TRUE).",
      "  Held-out cases do NOT contribute to imputation model parameters.",
      "NOT correct: fitting a separate mice() on val or on test.",
      "Fallback if ignore path fails: train-only MICE + train-column median/mode for test NA.",
      "Outcome labels are never imputed from covariates; required_non_na rows filtered in both sets.",
      paste0(
        if (ext_all) {
          paste0("Table S1 before/after MI: full external set (n=", nrow(train_imp), ").")
        } else {
          paste0(
            "Table S1 before/after MI: training rows only (n=", nrow(train_imp),
            "); complete_action=", complete_action, " of m=", m, "."
          )
        }
      ),
      paste0(
        "Table S1b (optional): holdout rows before/after MI (n=", nrow(test_imp),
        ") when export_table_s1_validation=TRUE."
      ),
      paste0(
        "MICE method=", method, ", m=", m, ", maxit=", max_iter,
        ", seed=", seed, ", complete_action=", complete_action
      ),
      paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    ),
    note_path
  )
  cli::cli_alert_success("Wrote {note_path}")

  out <- finalize_fn(
    pooled, imp_obj = imp_obj, data_before_mi = data_before_mi,
    table_s1_after = train_imp
  )
  if (is.null(out$results$data_before_mi) && is.data.frame(data_before_mi)) {
    out$results$data_before_mi <- data_before_mi
  }
  if (ext_all) {
    out$data$train <- train_imp
    out$data$test <- train_imp
    need_s1 <- !isFALSE(imp_cfg$export_table_s1 %||% TRUE) &&
      !isTRUE(out$results$table_s1_exported)
    if (need_s1 && exists(".imp01_build_table_s1", mode = "function")) {
      before <- out$results$data_before_mi %||% data_before_mi
      after <- out$data$imputed %||% train_imp
      if (is.data.frame(before) && is.data.frame(after) &&
          nrow(before) > 0L && nrow(after) > 0L) {
        common <- intersect(names(before), names(after))
        if (length(common) >= 2L) {
          cfg_s1 <- cfg
          cfg_s1$imputation <- imp_cfg
          cfg_s1$imputation$table_s1_title <- imp_cfg$table_s1_title %||%
            "Baseline characteristics before and after imputation (external validation set)"
          outcome_col_s1 <- cfg$data$outcome_column %||% "Disease"
          out <- tryCatch(
            .imp01_build_table_s1(
              out, cfg_s1, before[, common, drop = FALSE], after[, common, drop = FALSE],
              table_strata = (cfg$survival$event_var %||% outcome_col_s1),
              analysis_grp = pipeline_resolve_outcome_display_labels(cfg)$analysis,
              reference_grp = pipeline_resolve_outcome_display_labels(cfg)$reference,
              imp_cfg = cfg_s1$imputation
            ),
            error = function(e) {
              cli::cli_alert_warning("external_all Table S1 failed: {conditionMessage(e)}")
              out
            }
          )
        }
      }
    }
  } else if (!is.null(out$data$imputed) && nrow(out$data$imputed) >= n_train + nrow(test_imp)) {
    out$data$train <- out$data$imputed[seq_len(n_train), , drop = FALSE]
    out$data$test <- out$data$imputed[n_train + seq_len(nrow(test_imp)), , drop = FALSE]
  } else {
    out$data$train <- train_imp
    out$data$test <- test_imp
  }

  ## 验证集插补前后补充表（与训练集 Table S1 对称）；整库外验不出第二张
  export_s1_val <- isTRUE(imp_cfg$export_table_s1_validation %||% TRUE) && !ext_all
  if (export_s1_val && exists(".imp01_build_table_s1", mode = "function")) {
    ## test_work = 插补前验证集（已与 train 列对齐、筛行）
    if (is.data.frame(test_work) && nrow(test_work) == nrow(test_imp) && nrow(test_imp) > 0L) {
      cfg2 <- cfg
      .val_lab <- if (identical(
        as.character((cfg$ml_batch %||% list())$split_mode %||%
                       (cfg$incidence_batch %||% list())$split_mode %||% "")[1L],
        "dev_internal_ext"
      )) {
        "internal validation set"
      } else {
        "validation set"
      }
      cfg2$imputation$table_s1_title <- sprintf(
        "Baseline characteristics before and after imputation (%s, n=%d)",
        .val_lab, nrow(test_imp)
      )
      was_exported <- isTRUE(out$results$table_s1_exported)
      out$results$table_s1_exported <- FALSE
      out <- tryCatch(
        .imp01_build_table_s1(
          out, cfg2, test_work, test_imp,
          table_strata = (cfg$survival$event_var %||% cfg$data$outcome_column),
          analysis_grp = pipeline_resolve_outcome_display_labels(cfg)$analysis,
          reference_grp = pipeline_resolve_outcome_display_labels(cfg)$reference,
          imp_cfg = cfg2$imputation
        ),
        error = function(e) {
          cli::cli_alert_warning("Validation Table S1b skipped: {conditionMessage(e)}")
          out
        }
      )
      out$results$table_s1_validation_exported <- TRUE
      out$results$table_s1_exported <- was_exported || isTRUE(out$results$table_s1_exported)
      cli::cli_alert_success("Validation imputation table (S1b) queued")
    }
  }
  out
}

block_imputation <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(mice)
    library(dplyr)
    library(naniar)
    library(ggplot2)
  })

  cfg      <- ctx$config
  imp_cfg  <- cfg$imputation %||% list()
  fit_on   <- imp_cfg$fit_on %||% "all"

  if (identical(fit_on, "train")) {
    outcome_col <- cfg$data$outcome_column %||% "Disease"
    study_type <- tolower(cfg$project$study_type %||% "incidence")
    outcome_lbl <- pipeline_resolve_outcome_display_labels(cfg)
    analysis_grp <- outcome_lbl$analysis
    reference_grp <- outcome_lbl$reference
    table_strata <- if (identical(study_type, "prognosis")) {
      cfg$survival$event_var %||% outcome_col
    } else {
      outcome_col
    }
    train_ref <- ctx$data$train
    id_cols_present <- if (!is.null(train_ref) && is.data.frame(train_ref)) {
      .imp01_detect_id_cols(train_ref, cfg)
    } else {
      character(0)
    }
    primary_id <- if (length(id_cols_present)) .imp01_primary_id_col(id_cols_present, cfg) else NULL
    var_ranges <- imp_cfg$var_ranges %||% NULL
    export_s1 <- !isFALSE(imp_cfg$export_table_s1 %||% TRUE)

    .imp01_finalize <- function(data_imputed, imp_obj = NULL, data_before_mi = NULL,
                                table_s1_after = NULL) {
      if (!is.null(var_ranges) && length(var_ranges) > 0) {
        cli::cli_h2("Applying variable range constraints")
        data_imputed <- .imp01_constrain_ranges(data_imputed, var_ranges)
        cli::cli_alert_success("Variable range constraints applied")
      }
      if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
        data_imputed <- pipeline_relabel_binary_outcome_column(data_imputed, cfg, col = outcome_col)
      }
      # 生成 Table S1 / 下游图之前：删除任一层级 n<20 的分类列（全局默认）
      if (exists("pipeline_drop_sparse_categorical_cols", mode = "function")) {
        data_imputed <- pipeline_drop_sparse_categorical_cols(data_imputed, cfg)
        dropped <- attr(data_imputed, "sparse_categorical_dropped") %||% character(0)
        attr(data_imputed, "sparse_categorical_dropped") <- NULL
        if (length(dropped)) {
          ctx$results$sparse_categorical_dropped <- unique(c(
            as.character(ctx$results$sparse_categorical_dropped %||% character(0)), dropped
          ))
          if (!is.null(data_before_mi) && is.data.frame(data_before_mi)) {
            data_before_mi <- data_before_mi[, intersect(names(data_before_mi), names(data_imputed)), drop = FALSE]
          }
          if (!is.null(table_s1_after) && is.data.frame(table_s1_after)) {
            table_s1_after <- table_s1_after[, intersect(names(table_s1_after), names(data_imputed)), drop = FALSE]
          }
        }
      }
      ctx$data$imputed <- data_imputed
      if (exists("pipeline_apply_index_residualize", mode = "function")) {
        ctx <- pipeline_apply_index_residualize(ctx, cfg)
        data_imputed <- ctx$data$imputed
      }
      if (!is.null(imp_obj)) {
        ctx$results$mice_model <- imp_obj
        id_primary <- as.character(
          (cfg$data %||% list())$id_column %||%
            (if (length(id_cols_present)) id_cols_present[[1L]] else "ID")
        )[1L]
        ids_vec <- NULL
        if (!is.null(data_before_mi) && is.data.frame(data_before_mi) &&
            id_primary %in% names(data_before_mi) &&
            nrow(data_before_mi) == nrow(imp_obj$data)) {
          ids_vec <- as.character(data_before_mi[[id_primary]])
        } else if (id_primary %in% names(data_imputed) &&
                   nrow(data_imputed) == nrow(imp_obj$data)) {
          ids_vec <- as.character(data_imputed[[id_primary]])
        }
        if (length(ids_vec)) {
          ctx$results$mice_row_ids <- ids_vec
          cli::cli_alert_info("mice_row_ids locked for Rubin pool (n={length(ids_vec)})")
        }
      }
      if (!is.null(data_before_mi) && is.data.frame(data_before_mi)) {
        ctx$results$data_before_mi <- data_before_mi
      }
      if (isTRUE(export_s1) && !is.null(data_before_mi)) {
        s1_after <- table_s1_after %||% data_imputed
        ctx <- tryCatch(
          .imp01_build_table_s1(
            ctx, cfg, data_before_mi, s1_after,
            table_strata, analysis_grp, reference_grp, imp_cfg
          ),
          error = function(e) {
            cli::cli_alert_warning("Table S1 skipped: {conditionMessage(e)}")
            ctx
          }
        )
      }
      data_save <- .imp01_prepare_for_save(data_imputed, id_cols_present, primary_id)
      ctx <- save_result(ctx, "imputed_data", data_save, "D01_AfterMI_Data.RData")
      cli::cli_alert_success("D01_AfterMI_Data.RData saved (rownames = primary ID, ID columns removed)")
      if (exists("attrition_record", mode = "function")) {
        n_imp <- attrition_n_current(ctx)
        ctx <- attrition_record(
          ctx, "after_imputation", "After imputation",
          n_imp, meta = list(block = "imputation")
        )
      }
      ctx
    }
    return(.imp01_fit_on_train(ctx, cfg, imp_cfg, .imp01_finalize))
  }

  data     <- ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("No cleaned/mapped data found. Run 'data_clean' or 'column_mapping' first.")
  }
  data <- pipeline_ensure_outcome_group_column(data, cfg)
  if (!is.null(ctx$data$mapped)) ctx$data$mapped <- data
  if (!is.null(ctx$data$cleaned)) ctx$data$cleaned <- data

  traj_util <- file.path(cfg$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) {
    source(traj_util, local = FALSE)
    if (exists("trajectory_coerce_vital_numeric", mode = "function")) {
      data <- trajectory_coerce_vital_numeric(data)
      if (!is.null(ctx$data$mapped)) ctx$data$mapped <- data
      if (!is.null(ctx$data$cleaned)) ctx$data$cleaned <- data
    }
    ix <- as.character(cfg$survival$index_var %||% character(0))[1L]
    wide_tpl <- cfg$trajectory_jlcm$rawdata_path_template %||% NULL
    if (nzchar(ix) && !is.null(wide_tpl) && nzchar(wide_tpl) &&
        exists("trajectory_merge_wide_baseline_index", mode = "function")) {
      db_slug <- tolower(trimws(as.character(cfg$project$database %||% "")))
      if (!db_slug %in% c("eicu", "mimic")) {
        db_slug <- if (grepl("mimic", db_slug, ignore.case = TRUE)) "mimic" else "eicu"
      }
      wide_path <- gsub("\\{db\\}", db_slug, wide_tpl, fixed = FALSE)
      wide_path <- gsub("\\{Index\\}", ix, wide_path, fixed = FALSE)
      id_col <- cfg$data$id_column %||% "subject_id"
      if (file.exists(wide_path)) {
        data <- trajectory_merge_wide_baseline_index(data, wide_path, ix, id_col, day = 1L)
        cli::cli_alert_info("已从宽表合并 day-1 指标: {ix} ({basename(wide_path)})")
        if (!is.null(ctx$data$mapped)) ctx$data$mapped <- data
        if (!is.null(ctx$data$cleaned)) ctx$data$cleaned <- data
      }
    }
  }

  outcome_col   <- cfg$data$outcome_column %||% "Disease"
  study_type    <- tolower(cfg$project$study_type %||% "incidence")
  outcome_lbl   <- pipeline_resolve_outcome_display_labels(cfg)
  analysis_grp  <- outcome_lbl$analysis
  reference_grp <- outcome_lbl$reference
  table_strata  <- if (identical(study_type, "prognosis")) {
    cfg$survival$event_var %||% outcome_col
  } else {
    outcome_col
  }

  database_name <- cfg$project$database %||% cfg$project$disease %||% "Study"
  if (tolower(trimws(as.character(database_name))) %in% c("nhance", "nhanes")) {
    database_name <- "NHANES"
  }

  id_cols_present <- .imp01_detect_id_cols(data, cfg)
  primary_id      <- if (length(id_cols_present)) .imp01_primary_id_col(id_cols_present, cfg) else NULL
  if (length(id_cols_present)) {
    cli::cli_alert_info(
      "检测到 ID 列: {paste(id_cols_present, collapse = ', ')} — 不参与 MICE；保存 D01 时主键 {primary_id} 转为行名"
    )
  }

  missing_col_threshold <- imp_cfg$missing_col_threshold %||% 0.2
  method         <- imp_cfg$method %||% "cart"
  m              <- as.integer(imp_cfg$m %||% 5L)
  max_iter       <- as.integer(imp_cfg$max_iter %||% 5L)
  seed           <- as.integer(imp_cfg$seed %||% 1234L)
  complete_action <- as.integer(imp_cfg$complete_action %||% 1L)
  mice_ridge     <- as.numeric(imp_cfg$ridge %||% 1e-2)[1L]
  mice_cor_drop  <- as.numeric(imp_cfg$cor_drop_threshold %||% 0.95)[1L]
  allow_cart_fb  <- isTRUE(imp_cfg$allow_cart_fallback %||% FALSE)
  required_non_na <- imp_cfg$required_non_na_cols %||% NULL
  var_ranges     <- imp_cfg$var_ranges %||% NULL
  export_fig     <- isTRUE(imp_cfg$export_missing_fig %||% FALSE)
  export_s1      <- isTRUE(imp_cfg$export_table_s1 %||% TRUE)

  .imp01_finalize <- function(data_imputed, imp_obj = NULL, data_before_mi = NULL) {
    if (!is.null(var_ranges) && length(var_ranges) > 0) {
      cli::cli_h2("Applying variable range constraints")
      data_imputed <- .imp01_constrain_ranges(data_imputed, var_ranges)
      cli::cli_alert_success("Variable range constraints applied")
    }

    if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
      data_imputed <- pipeline_relabel_binary_outcome_column(data_imputed, cfg, col = outcome_col)
    }

    # 生成 Table S1 / 下游图之前：删除任一层级 n<20 的分类列（全局默认）
    if (exists("pipeline_drop_sparse_categorical_cols", mode = "function")) {
      data_imputed <- pipeline_drop_sparse_categorical_cols(data_imputed, cfg)
      dropped <- attr(data_imputed, "sparse_categorical_dropped") %||% character(0)
      attr(data_imputed, "sparse_categorical_dropped") <- NULL
      if (length(dropped)) {
        ctx$results$sparse_categorical_dropped <- unique(c(
          as.character(ctx$results$sparse_categorical_dropped %||% character(0)), dropped
        ))
        if (!is.null(data_before_mi) && is.data.frame(data_before_mi)) {
          data_before_mi <- data_before_mi[, intersect(names(data_before_mi), names(data_imputed)), drop = FALSE]
        }
      }
    }

    ctx$data$imputed <- data_imputed
    if (exists("pipeline_apply_index_residualize", mode = "function")) {
      ctx <- pipeline_apply_index_residualize(ctx, cfg)
      data_imputed <- ctx$data$imputed
    }
    # TST 等：插补后同步队列，供后续 timeseries 静态广播 / landmark 使用
    if (!is.null(ctx$data$tst_cohort) && is.data.frame(ctx$data$tst_cohort)) {
      ctx$data$tst_cohort <- data_imputed
      ctx$data$cleaned <- data_imputed
      cli::cli_alert_info("imputation: 已同步 tst_cohort/cleaned ← imputed（n={nrow(data_imputed)}）")
    }
    if (!is.null(imp_obj)) {
      ctx$results$mice_model <- imp_obj
      # 与 mids 行序锁定的 ID，供 Rubin 对齐；trim 不得改写此向量
      id_primary <- as.character(
        (cfg$data %||% list())$id_column %||%
          (if (length(id_cols_present)) id_cols_present[[1L]] else "ID")
      )[1L]
      ids_vec <- NULL
      if (!is.null(data_before_mi) && is.data.frame(data_before_mi) &&
          id_primary %in% names(data_before_mi) &&
          nrow(data_before_mi) == nrow(imp_obj$data)) {
        ids_vec <- as.character(data_before_mi[[id_primary]])
      } else if (id_primary %in% names(data_imputed) &&
                 nrow(data_imputed) == nrow(imp_obj$data)) {
        ids_vec <- as.character(data_imputed[[id_primary]])
      }
      if (length(ids_vec)) {
        ctx$results$mice_row_ids <- ids_vec
        cli::cli_alert_info("mice_row_ids locked for Rubin pool (n={length(ids_vec)})")
      }
    }

    if (isTRUE(export_s1) && !is.null(data_before_mi)) {
      ctx$results$data_before_mi <- data_before_mi
      ctx <- .imp01_build_table_s1(
        ctx, cfg, data_before_mi, data_imputed,
        table_strata, analysis_grp, reference_grp, imp_cfg
      )
    }

    data_save <- .imp01_prepare_for_save(data_imputed, id_cols_present, primary_id)
    ctx <- save_result(ctx, "imputed_data", data_save, "D01_AfterMI_Data.RData")
    cli::cli_alert_success("D01_AfterMI_Data.RData saved (rownames = primary ID, ID columns removed)")
    if (exists("attrition_record", mode = "function")) {
      n_imp <- attrition_n_current(ctx)
      ctx <- attrition_record(
        ctx, "after_imputation", "After imputation",
        n_imp, meta = list(block = "imputation")
      )
    }
    ctx
  }

  n_missing <- sum(is.na(data))
  if (n_missing == 0) {
    cli::cli_alert_success("No missing values. Skipping MICE and missing plot.")
    return(.imp01_finalize(data, imp_obj = NULL, data_before_mi = if (export_s1) data else NULL))
  }
  cli::cli_alert_info("Total missing values before imputation: {n_missing}")

  data_work <- data
  if (outcome_col %in% names(data_work)) {
    n_before <- nrow(data_work)
    data_work <- data_work[!is.na(data_work[[outcome_col]]), , drop = FALSE]
    if (nrow(data_work) < n_before) {
      cli::cli_alert_info("剔除结局缺失行: {n_before - nrow(data_work)} 行")
    }
  }
  if (length(required_non_na)) {
    for (col in required_non_na) {
      if (!col %in% names(data_work)) next
      n_before <- nrow(data_work)
      data_work <- data_work[!is.na(data_work[[col]]), , drop = FALSE]
      if (nrow(data_work) < n_before) {
        cli::cli_alert_info("剔除 {col} 缺失行: {n_before - nrow(data_work)} 行")
      }
    }
  }

  missing.percent <- colMeans(is.na(data_work))
  n_drop <- sum(missing.percent > missing_col_threshold)
  # 即使用本库无超阈值列，双库并集仍可能剔除伙伴库高缺失列
  keep <- .imp01_missing_keep_mask(data_work, missing_col_threshold, imp_cfg, cfg)
  if (any(!keep) || n_drop > 0) {
    if (isTRUE(imp_cfg$force_keep_weight_cols %||% FALSE)) {
      protect_wt <- if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
        nhanes_survey_weight_source_cols(cfg)
      } else {
        c("WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTSAF2YR", "WTSAF4YR",
          "SDMVPSU", "SDMVSTRA", "Source_File", "SDDSRVYR", "new_Weight")
      }
      force_keep <- intersect(protect_wt, names(data_work))
      if (length(force_keep)) {
        rescued <- intersect(force_keep, names(data_work)[missing.percent > missing_col_threshold])
        if (length(rescued)) {
          cli::cli_alert_info(
            "保留 NHANES 权重列（缺失率超阈值但不可删）: {paste(rescued, collapse = ', ')}"
          )
        }
      }
    }
    force_keep_extra <- as.character(imp_cfg$force_keep_columns %||% character(0))
    if (length(force_keep_extra)) {
      fk <- intersect(force_keep_extra, names(data_work))
      if (length(fk)) {
        rescued <- intersect(fk, names(data_work)[missing.percent > missing_col_threshold])
        if (length(rescued)) {
          cli::cli_alert_info(
            "保留指定列（缺失率超阈值但不可删）: {paste(rescued, collapse = ', ')}"
          )
        }
      }
    }
    dropped <- names(data_work)[!keep]
    n_drop_actual <- length(dropped)
    if (n_drop_actual > 0) {
      cli::cli_alert_info(
        "按 missing_col_threshold={missing_col_threshold} 剔除 {n_drop_actual} 列: {paste(head(dropped, 8), collapse = ', ')}{if (n_drop_actual > 8) '...' else ''}"
      )
    }
    data_work <- data_work[, keep, drop = FALSE]
  }

  id_for_attach <- NULL
  mice_skip <- unique(c(
    as.character(imp_cfg$exclude_from_mice_cols %||% character(0)),
    if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
      nhanes_survey_weight_source_cols(cfg)
    } else {
      c("Source_File", "SDDSRVYR", "WTSA2YR", "WTSAF2YR", "WTSAF4YR",
        "WTMEC2YR", "WTMEC4YR", "WTINT2YR", "WTINT4YR",
        "SDMVPSU", "SDMVSTRA", "new_Weight")
    }
  ))
  mice_skip <- intersect(mice_skip, names(data_work))

  if (length(id_cols_present)) {
    id_for_attach <- data_work[, id_cols_present, drop = FALSE]
    data_mice <- data_work[, setdiff(names(data_work), c(id_cols_present, mice_skip)), drop = FALSE]
  } else {
    data_mice <- data_work[, setdiff(names(data_work), mice_skip), drop = FALSE]
  }
  mice_attach <- data_work[, intersect(mice_skip, names(data_work)), drop = FALSE]
  outcome_attach <- NULL
  if (outcome_col %in% names(data_work)) {
    outcome_attach <- data_work[[outcome_col]]
  }
  if (outcome_col %in% names(data_work) && outcome_col %in% names(data_mice)) {
    data_mice <- data_mice[, setdiff(names(data_mice), outcome_col), drop = FALSE]
    cli::cli_alert_info("MICE 不插补结局列: {outcome_col}")
  }
  if (length(mice_skip)) {
    cli::cli_alert_info(
      "MICE 排除调查设计/权重列: {paste(intersect(mice_skip, names(data_work)), collapse = ', ')}"
    )
  }

  if (sum(is.na(data_mice)) == 0) {
    cli::cli_alert_success("列筛选后无缺失，跳过 MICE。")
    data_out <- data_work
    return(.imp01_finalize(data_out, imp_obj = NULL, data_before_mi = data_work))
  }

  if (exists("pipeline_sanitize_numeric_for_mice", mode = "function")) {
    san <- pipeline_sanitize_numeric_for_mice(data_mice, cfg)
    data_mice <- san$data
    if (san$n_nonfinite > 0L || san$n_pp_filled > 0L) {
      cli::cli_alert_info(
        "插补前数值清洗: 非有限→NA {san$n_nonfinite}，PP 回填 {san$n_pp_filled}"
      )
    }
  } else {
    for (col in names(data_mice)) {
      if (is.numeric(data_mice[[col]])) {
        x <- data_mice[[col]]
        x[!is.finite(x)] <- NA_real_
        data_mice[[col]] <- x
      }
    }
  }
  bp_cols <- intersect(c("SBP", "DBP", "PP", "NBPS", "NBPD"), names(data_mice))
  if (length(bp_cols)) {
    n_bp_na <- sum(vapply(bp_cols, function(cn) sum(is.na(data_mice[[cn]])), integer(1)))
    cli::cli_alert_info(
      "血压列 {paste(bp_cols, collapse=', ')} 缺失合计 {n_bp_na} 个单元格（将参与 MICE）"
    )
  }
  for (col in names(data_mice)) {
    if (col %in% names(data_work)) data_work[[col]] <- data_mice[[col]]
  }

  drop_u <- .imp01_drop_unusable_mice_cols(data_mice, data_work, cfg)
  data_mice <- drop_u$data_mice
  data_work <- drop_u$data_work
  if (ncol(data_mice) == 0L || sum(is.na(data_mice)) == 0) {
    cli::cli_alert_success("剔除不可用列后无缺失，跳过 MICE。")
    return(.imp01_finalize(data_work, imp_obj = NULL, data_before_mi = data_work))
  }

  # Table S1 需完整插补前宽表（含结局/权重列）；data_mice 仅为 MICE 输入子集
  data_before_mi <- data_work

  if (isTRUE(export_fig)) {
    cli::cli_h2("Generating missing value overview plot")
    n_samples <- nrow(data_work)
    n_vars    <- ncol(data_mice)
    fig_height <- max(6, min(20, n_samples / 50))
    fig_width  <- max(8, min(30, n_vars * 0.8))
    fig_title <- as.character(imp_cfg$missing_fig_title %||% paste0(
      "Missing value overview in ", database_name, " cohort"
    ))[1L]
    output_dir_figures <- file.path(ctx$output_dir, "Figures")
    if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)

    # IPW 糖尿病项目：缺失热图 = Figure S1（对齐用户编号；原文 S1 为本项目 S2）
    as_supp <- isTRUE(imp_cfg$missing_as_supp_figure %||% FALSE)
    if (as_supp && exists("pub_figure_file", mode = "function") &&
        exists("save_figure", mode = "function")) {
      miss_cap <- as.character(
        imp_cfg$missing_fig_caption %||% "Missing value overview"
      )[1L]
      fig_stem <- pub_figure_file(ctx, "supp_figure", miss_cap)
      if (!grepl("Missing|missing", fig_stem, ignore.case = TRUE)) {
        fig_stem <- sub("\\.pdf$", " Missing value overview.pdf", fig_stem, ignore.case = TRUE)
      }
      data_plot <- data_mice
      if (nrow(data_plot) > 5000) {
        set.seed(seed)
        data_plot <- dplyr::slice_sample(data_plot, n = 5000)
        cli::cli_alert_info("缺失热图降采样: 5000/{nrow(data_mice)} 行")
      }
      ctx <- save_figure(
        ctx,
        fig_stem,
        function() {
          print(
            vis_miss(data_plot, cluster = FALSE, warn_large_data = FALSE) +
              ggplot2::theme(
                axis.text.x = ggplot2::element_text(
                  angle = 90, hjust = 1, vjust = 0.5, size = 8
                )
              ) +
              ggplot2::labs(title = fig_title)
          )
          invisible(NULL)
        },
        width = fig_width,
        height = fig_height
      )
      fig_path <- file.path(output_dir_figures, basename(fig_stem))
      ctx$results$imputation_missing_figure <- fig_stem
      cli::cli_alert_success("Missing value overview (Figure S1) queued: {basename(fig_stem)}")
    } else {
      fig_stem <- as.character(imp_cfg$missing_fig_filename %||% "Figure_Missing_Value_Overview.pdf")[1L]
      fig_path <- if (exists(".inject_db_into_pub_filepath", mode = "function")) {
        .inject_db_into_pub_filepath(file.path(output_dir_figures, fig_stem))
      } else {
        file.path(output_dir_figures, fig_stem)
      }
      if (exists(".pub_figure_filename", mode = "function")) {
        fig_path <- file.path(dirname(fig_path), .pub_figure_filename(basename(fig_path)))
      }
      data_plot <- data_mice
      if (nrow(data_plot) > 5000) {
        set.seed(seed)
        data_plot <- dplyr::slice_sample(data_plot, n = 5000)
        cli::cli_alert_info("缺失热图降采样: 5000/{nrow(data_mice)} 行")
      }
      grDevices::pdf(fig_path, width = fig_width, height = fig_height)
      tryCatch({
        print(vis_miss(data_plot, cluster = FALSE, warn_large_data = FALSE) +
                ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5, size = 8)) +
                ggplot2::labs(title = fig_title))
      }, error = function(e) {
        cli::cli_alert_warning("缺失热图绘制失败（不影响插补）: {e$message}")
      })
      grDevices::dev.off()
      cli::cli_alert_success("Missing value overview plot saved: {fig_path}")
      mirror_pub_output_to_root(ctx, fig_path)
    }
  }

  mice_res <- .imp01_run_mice(
    data_mice, method, m, max_iter, seed, complete_action,
    ridge = mice_ridge, cor_threshold = mice_cor_drop,
    allow_cart_fallback = allow_cart_fb
  )
  imp <- mice_res$imp
  data_imp <- mice_res$data_imp

  if (!is.null(id_for_attach) && nrow(id_for_attach) == nrow(data_imp)) {
    for (nm in names(id_for_attach)) data_imp[[nm]] <- id_for_attach[[nm]]
  }
  if (ncol(mice_attach) && nrow(mice_attach) == nrow(data_imp)) {
    for (nm in names(mice_attach)) data_imp[[nm]] <- mice_attach[[nm]]
  }
  if (!is.null(outcome_attach) && length(outcome_attach) == nrow(data_imp)) {
    data_imp[[outcome_col]] <- outcome_attach
  }

  .imp01_finalize(data_imp, imp_obj = imp, data_before_mi = data_before_mi)
}

.imp01_build_table_s1 <- function(ctx, cfg, data_before, data_imputed,
                                    table_strata, analysis_grp, reference_grp, imp_cfg) {
  cli::cli_h2("Generating Table S1 (before vs after imputation)")

  # 旁路/重跑时未必经过 run_block；保证发表命名库名不是 UnknownDB
  db_nm <- cfg$project$database %||% cfg$project$database_type %||% NULL
  if (!is.null(db_nm) && nzchar(trimws(as.character(db_nm)[1L]))) {
    options(pipeline.database_name = trimws(as.character(db_nm)[1L]))
  }

  id_s1 <- unique(c(
    as.character(cfg$data$id_column %||% character(0)),
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    "ID", "subject_id", "SEQN"
  ))
  id_s1 <- id_s1[nzchar(id_s1)]

  s1_excl_baseline <- unique(c(
    as.character((cfg$baseline %||% list())$exclude_vars %||% character(0)),
    as.character((cfg$baseline_binary %||% list())$exclude_vars %||% character(0))
  ))
  s1_excl_baseline <- s1_excl_baseline[nzchar(s1_excl_baseline)]
  max_cat_levels <- as.integer(imp_cfg$table_s1_max_cat_levels %||% 15L)
  if (!is.finite(max_cat_levels) || max_cat_levels < 2L) max_cat_levels <- 15L
  s1_excl_extra <- c(
    "Source_File", "SDDSRVYR", "DN",
    "new_weight", "new_Weight", "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
    "WTSAF2YR", "WTSAF4YR", "WTSA2YR",
    "WTDRD1", "WTDR2D", "WTSOG2YR",
    "SDMVSTRA", "SDMVPSU",
    # 结局状态不作 Before/After MI 行（预后 fustatus 与主文 28 天截尾后 Table1 易对不上）
    "fustatus"
  )
  s1_excl_outcome <- unique(c(
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character(table_strata %||% character(0))
  ))
  s1_excl_outcome <- s1_excl_outcome[nzchar(s1_excl_outcome)]
  s1_excl_cfg <- as.character(imp_cfg$table_s1_exclude_vars %||% character(0))
  s1_exclude <- unique(c(s1_excl_baseline, s1_excl_extra, s1_excl_outcome, s1_excl_cfg))
  s1_exclude <- intersect(s1_exclude, names(data_imputed))
  if (length(s1_exclude)) {
    cli::cli_alert_info("Table S1 排除变量: {paste(s1_exclude, collapse = ', ')}")
  }

  num_cols <- names(data_imputed)[vapply(data_imputed, is.numeric, logical(1))]
  num_cols <- setdiff(num_cols, c(table_strata, id_s1, s1_exclude))
  voc_force_s1 <- character(0)
  if (exists("environment_table1_voc_vars", mode = "function")) {
    voc_force_s1 <- intersect(
      environment_table1_voc_vars(data_imputed, cfg),
      num_cols
    )
  }
  # 当前暴露指标 / force_keep 绝不当作 ID-like 剔除（否则 MCV 等高基数连续暴露会从 S1 消失）
  force_keep_s1 <- unique(c(
    as.character(imp_cfg$force_keep_columns %||% character(0)),
    if (exists("pipeline_index_exposure_var", mode = "function")) {
      pipeline_index_exposure_var(cfg)
    } else {
      character(0)
    },
    as.character((cfg$survival %||% list())$index_var %||% character(0))
  ))
  force_keep_s1 <- force_keep_s1[nzchar(force_keep_s1)]
  id_like <- vapply(num_cols, function(v) {
    if (v %in% voc_force_s1 || v %in% force_keep_s1) return(FALSE)
    x <- data_imputed[[v]]
    length(unique(stats::na.omit(x))) > max(50L, floor(0.5 * length(x)))
  }, logical(1))
  if (any(id_like)) {
    skip_id_like <- num_cols[id_like]
    cli::cli_alert_warning(
      "Table S1 skip ID-like numeric cols: {paste(skip_id_like, collapse = ', ')}"
    )
    num_cols <- num_cols[!id_like]
  }
  normality   <- vapply(num_cols, function(v) .imp01_test_normality(data_imputed[[v]]), logical(1))
  normal_vars <- num_cols[normality]
  ctx$results$normal_vars <- normal_vars
  ctx$results$skewed_vars <- num_cols[!normality]

  table_strata_ok <- !is.null(table_strata) &&
    length(table_strata) >= 1L &&
    nzchar(as.character(table_strata)[1L]) &&
    as.character(table_strata)[1L] %in% names(data_imputed) &&
    as.character(table_strata)[1L] %in% names(data_before)
  if (isTRUE(table_strata_ok)) {
    table_strata <- as.character(table_strata)[1L]
    if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
      data_before <- pipeline_relabel_binary_outcome_column(
        data_before, cfg, col = table_strata
      )
      data_imputed <- pipeline_relabel_binary_outcome_column(
        data_imputed, cfg, col = table_strata
      )
    } else {
      vals <- na.omit(unique(data_imputed[[table_strata]]))
      if (is.numeric(data_imputed[[table_strata]]) && all(vals %in% c(0, 1))) {
        data_before[[table_strata]] <- ifelse(data_before[[table_strata]] == 1, analysis_grp, reference_grp)
        data_imputed[[table_strata]] <- ifelse(data_imputed[[table_strata]] == 1, analysis_grp, reference_grp)
      }
    }
    data_before[[table_strata]]   <- as.factor(data_before[[table_strata]])
    data_imputed[[table_strata]]  <- as.factor(data_imputed[[table_strata]])
  } else if (!is.null(table_strata) && length(table_strata) >= 1L && nzchar(as.character(table_strata)[1L])) {
    cli::cli_alert_warning("Table S1 stratification variable not found: {table_strata}")
    table_strata <- NULL
  } else {
    table_strata <- NULL
  }

  cat_cols <- setdiff(names(data_imputed), num_cols)
  cat_cols <- cat_cols[vapply(
    data_imputed[, cat_cols, drop = FALSE],
    function(x) is.factor(x) || is.character(x),
    logical(1)
  )]
  cat_cols <- setdiff(cat_cols, c(id_s1, s1_exclude, table_strata))

  if (exists("environment_patch_table1_sections", mode = "function")) {
    cfg <- environment_patch_table1_sections(cfg, data_imputed)
  }
  all_s1_vars <- setdiff(names(data_imputed), c(table_strata, id_s1, s1_exclude))
  s1_vars <- all_s1_vars
  if (exists("environment_sort_analysis_vars", mode = "function")) {
    s1_vars <- environment_sort_analysis_vars(all_s1_vars, cfg, data_imputed)
  } else {
    num_cols <- names(data_imputed)[vapply(data_imputed, is.numeric, logical(1))]
    num_cols <- setdiff(num_cols, c(table_strata, id_s1, s1_exclude))
    s1_vars <- c(num_cols, cat_cols)
    if (exists("sort_vars_by_table1_sections", mode = "function")) {
      s1_vars <- sort_vars_by_table1_sections(s1_vars, cfg)
    }
  }
  if (exists("order_vars_like_table1", mode = "function")) {
    s1_vars <- order_vars_like_table1(s1_vars, ctx, cfg, data_imputed)
  }
  # 排序/对齐后再次剔除结局状态（避免 Table1 对齐逻辑把 fustatus 加回）
  s1_vars <- setdiff(s1_vars, unique(c(s1_exclude, table_strata, "fustatus")))
  cat_cols <- setdiff(cat_cols, unique(c(s1_exclude, table_strata, "fustatus")))
  num_cols <- setdiff(num_cols, unique(c(s1_exclude, table_strata, "fustatus")))
  sections <- (cfg$baseline_nhanes %||% cfg$baseline %||% list())$table1_sections

  rows <- list()
  raw_p_map <- list()
  seen_sections <- character(0)
  for (v in s1_vars) {
    if (exists("environment_var_table1_section", mode = "function") &&
        !is.null(sections) && length(sections)) {
      sec_name <- environment_var_table1_section(v, sections)
      if (!is.null(sec_name) && !sec_name %in% seen_sections) {
        rows[[length(rows) + 1L]] <- data.frame(
          Variable = sec_name, Statistic = "",
          Before_MI = "", After_MI = "", P_value = "",
          .is_cat_row = FALSE, .is_section_row = TRUE,
          stringsAsFactors = FALSE
        )
        seen_sections <- c(seen_sections, sec_name)
      }
    }
    is_num <- v %in% num_cols
    if (is_num) {
      x_before <- data_before[[v]]
      x_after  <- data_imputed[[v]]
      is_norm  <- v %in% normal_vars
      label    <- if (is_norm) "Mean \u00b1 SD" else "Median (Q1, Q3)"
      p <- tryCatch({
        if (is_norm) stats::t.test(x_after, x_before)$p.value
        else          stats::wilcox.test(x_after, x_before)$p.value
      }, error = function(e) NA_real_)
      raw_p_map[[v]] <- p
      rows[[length(rows) + 1L]] <- data.frame(
        Variable = v, Statistic = label,
        Before_MI = fmt_continuous(x_before, is_norm),
        After_MI  = fmt_continuous(x_after, is_norm),
        P_value   = fmt_pval(p),
        .is_cat_row = FALSE, .is_section_row = FALSE,
        stringsAsFactors = FALSE
      )
      miss_row <- .imp01_s1_missing_pct_row(
        x_before, x_after, nrow(data_before), nrow(data_imputed)
      )
      if (!is.null(miss_row)) rows[[length(rows) + 1L]] <- miss_row
      next
    }
    if (!v %in% cat_cols) next

    x_before <- data_before[[v]]
    x_after  <- data_imputed[[v]]
    lvls <- unique(c(as.character(x_before), as.character(x_after)))
    lvls <- lvls[!is.na(lvls) & nzchar(lvls)]
    if (length(lvls) > max_cat_levels) {
      cli::cli_alert_warning(
        "Table S1 skip '{v}': {length(lvls)} levels (> {max_cat_levels})"
      )
      next
    }
    p <- tryCatch({
      # 列联表：行=分类水平，列=Before/After（Race 等可有 >2 行，勿按 2×2 误丢 P）
      tbl <- table(
        c(as.character(x_before), as.character(x_after)),
        c(rep("Before", length(x_before)), rep("After", length(x_after)))
      )
      if (ncol(tbl) != 2L || nrow(tbl) < 1L || nrow(tbl) > max_cat_levels) {
        NA_real_
      } else if (any(tbl < 5, na.rm = TRUE)) {
        stats::fisher.test(tbl, simulate.p.value = TRUE, B = 2000L)$p.value
      } else {
        stats::chisq.test(tbl)$p.value
      }
    }, error = function(e) NA_real_)
    raw_p_map[[v]] <- p
    lvls <- sort(lvls)
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = v, Statistic = "n (%)",
      Before_MI = "", After_MI = "", P_value = fmt_pval(p),
      .is_cat_row = TRUE, .is_section_row = FALSE, stringsAsFactors = FALSE
    )
    for (lv in lvls) {
      n_b <- sum(!is.na(x_before) & as.character(x_before) == lv)
      n_a <- sum(!is.na(x_after)  & as.character(x_after)  == lv)
      rows[[length(rows) + 1L]] <- data.frame(
        Variable = paste0("  ", lv), Statistic = "",
        Before_MI = paste0(n_b, " (", fmt_num(n_b / nrow(data_before) * 100), "%)"),
        After_MI  = paste0(n_a, " (", fmt_num(n_a / nrow(data_imputed) * 100), "%)"),
        P_value = "", .is_cat_row = TRUE, .is_section_row = FALSE, stringsAsFactors = FALSE
      )
    }
    miss_row <- .imp01_s1_missing_pct_row(
      x_before, x_after, nrow(data_before), nrow(data_imputed)
    )
    if (!is.null(miss_row)) rows[[length(rows) + 1L]] <- miss_row
  }

  if (!length(rows)) {
    cli::cli_alert_warning("Table S1: 无可用变量，跳过导出")
    return(ctx)
  }

  tab_s1 <- do.call(rbind, rows)
  for (cn in names(tab_s1)) {
    if (is.character(tab_s1[[cn]])) {
      tab_s1[[cn]] <- gsub("\\*\\*", "", tab_s1[[cn]])
      tab_s1[[cn]] <- ifelse(tab_s1[[cn]] %in% c("NA", "N/A", "NaN", "<NA>"), "", tab_s1[[cn]])
    }
  }
  if (exists("environment_resolve_label_map", mode = "function") &&
      exists("environment_display_label", mode = "function")) {
    tab_s1$Variable <- environment_display_label(
      tab_s1$Variable, environment_resolve_label_map(cfg)
    )
  } else {
    tab_s1$Variable <- gsub("_", " ", tab_s1$Variable, fixed = TRUE)
  }
  for (ri in seq_len(nrow(tab_s1))) {
    vi <- tab_s1$Variable[ri]
    if (grepl("^  ", vi)) next
    if (grepl("futime", vi, ignore.case = TRUE)) tab_s1$Variable[ri] <- "Follow-up time"
  }
  tab_s1$P_value <- gsub("_", " ", tab_s1$P_value, fixed = TRUE)
  names(tab_s1)[names(tab_s1) == "Before_MI"] <- "Before MI"
  names(tab_s1)[names(tab_s1) == "After_MI"]  <- "After MI"
  names(tab_s1)[names(tab_s1) == "P_value"]   <- "P value"

  is_cat_level_row <- tab_s1$.is_cat_row & grepl("^  ", as.character(tab_s1$Variable), perl = TRUE)
  excel_level_row_idx <- if (any(is_cat_level_row)) {
    as.integer(which(is_cat_level_row) + 1L)
  } else {
    NULL
  }
  tex_df <- tab_s1[, setdiff(names(tab_s1), c(".is_cat_row", ".is_section_row")), drop = FALSE]

  # 发病/预后全队列插补：默认不加 (training set)；仅 fit_on=train 且确有验证集时标注
  # 整库外验 train/test 是同一批人，不得写成 training set
  .s1_ext_all <- isTRUE((ctx$results %||% list())$train_validation_external_all)
  .s1_has_split <- !isTRUE(.s1_ext_all) &&
    !is.null(ctx$data$train) && is.data.frame(ctx$data$train) &&
    nrow(ctx$data$train) > 0L &&
    ((!is.null(ctx$data$test) && is.data.frame(ctx$data$test) && nrow(ctx$data$test) > 0L) ||
       (!is.null(ctx$data$validation) && is.data.frame(ctx$data$validation) &&
          nrow(ctx$data$validation) > 0L))
  .s1_fit_train <- identical(
    tolower(as.character(imp_cfg$fit_on %||% "all")[1L]), "train"
  ) && !isTRUE(.s1_ext_all)
  cap_s1 <- imp_cfg$table_s1_title %||% (
    if (isTRUE(.s1_ext_all)) {
      "Baseline characteristics before and after imputation (external validation set)"
    } else if (isTRUE(.s1_fit_train) && isTRUE(.s1_has_split)) {
      "Baseline characteristics before and after imputation (training set)"
    } else {
      "Baseline characteristics before and after imputation"
    }
  )
  cap_s1 <- sub("^Table S\\d+\\.\\s*", "", cap_s1)
  rm(.s1_has_split, .s1_fit_train, .s1_ext_all)
  paths_s1 <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap_s1, "xlsx")
  export_sci_table(tex_df, paths_s1$filepath, title = paths_s1$title, excel_level_row_idx = excel_level_row_idx)
  cli::cli_alert_success("Table S1 queued (export_sci_table)")
  ctx$results$table_s1 <- tex_df
  ctx$results$table_s1_raw_p <- raw_p_map
  ctx$results$table_s1_exported <- TRUE
  ctx$results$table_s1_exported <- TRUE

  if (exists("pipeline_mi_quality_from_table_s1", mode = "function") &&
      exists("pipeline_apply_mi_quality_to_ctx", mode = "function")) {
    # 用原始变量名的 p 值表构建门控，避免展示名空格干扰
    gate_tab <- data.frame(
      Variable = names(raw_p_map),
      `P value` = vapply(raw_p_map, function(p) {
        if (length(p) && is.finite(p[[1L]])) as.character(p[[1L]]) else NA_character_
      }, character(1L)),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    gate <- pipeline_mi_quality_from_table_s1(gate_tab, cfg, raw_p_map = raw_p_map)
    # exclude 名单使用数据中真实列名
    if (length(gate$exclude)) {
      real_names <- names(data_imputed)
      resolved <- character(0)
      for (v in gate$exclude) {
        if (v %in% real_names) {
          resolved <- c(resolved, v)
        } else {
          hit <- real_names[gsub("_", " ", real_names, fixed = TRUE) == gsub("_", " ", v, fixed = TRUE)]
          resolved <- c(resolved, hit)
        }
      }
      gate$exclude <- unique(resolved)
    }
    # 合并既有清单：Table1 重排后可能已剔除变量导致二次门控得到空集，避免覆盖清空
    prev_excl <- unique(as.character(ctx$results$mi_quality_exclude_vars %||% character(0)))
    gate$exclude <- unique(c(prev_excl, gate$exclude))
    # 双库：合并伙伴库 MI 质量剔除名单，避免后续表/图列集合分叉
    if (exists("pipeline_dual_db_partner_key", mode = "function") &&
        exists("pipeline_dual_db_load_analysis_df", mode = "function") &&
        isTRUE((cfg$dual_db %||% list())$enable %||% FALSE)) {
      partner <- pipeline_dual_db_partner_key(cfg)
      if (!is.null(partner)) {
        # 从伙伴库最新 ck 读 mi_quality_exclude_vars
        bc <- cfg$survival_batch %||% cfg$incidence_batch %||% list()
        ck_base <- (cfg$dual_db %||% list())$checkpoint_base %||% NULL
        slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
          dual_db_slot_path_name(cfg, partner)
        } else {
          partner
        }
        partner_excl <- character(0)
        if (!is.null(ck_base)) {
          for (fn in c("step05_imputation.rds", "imputation.rds", "step06_baseline_binary.rds")) {
            p <- file.path(ck_base, slot, fn)
            if (!file.exists(p)) next
            obj <- tryCatch(readRDS(p), error = function(e) NULL)
            if (is.null(obj)) next
            ctxp <- if (!is.null(obj$ctx)) obj$ctx else obj
            partner_excl <- as.character(ctxp$results$mi_quality_exclude_vars %||% character(0))
            if (length(partner_excl)) break
          }
        }
        if (length(partner_excl)) {
          gate$exclude <- unique(c(gate$exclude, partner_excl))
          cli::cli_alert_warning(
            "dual_db MI 质量并集锁定：并入伙伴库剔除 {length(partner_excl)} 列"
          )
        }
      }
    }
    ctx <- pipeline_apply_mi_quality_to_ctx(ctx, gate)
    # 同步从 imputed / before_mi 中剔除（保护变量已保留）
    if (exists("pipeline_drop_mi_quality_cols", mode = "function") &&
        length(ctx$results$mi_quality_exclude_vars)) {
      ctx$data$imputed <- pipeline_drop_mi_quality_cols(ctx$data$imputed, ctx)
      if (!is.null(ctx$results$data_before_mi)) {
        ctx$results$data_before_mi <- pipeline_drop_mi_quality_cols(ctx$results$data_before_mi, ctx)
      }
    }
  }

  ctx
}

register_block(
  "imputation",
  block_imputation,
  "MICE (cart) + missing plot + Table S1 before/after imputation"
)
