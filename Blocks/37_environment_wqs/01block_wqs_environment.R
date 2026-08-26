###############################################################################
#  wqs_environment — 环境混合暴露 WQS（加权分位数和）回归分析
#
#  register_block: "wqs_environment"
#  典型流水线: glm_environment_quartile → wqs_environment
#
#  功能：
#    对 ctx$results$select_vocs_final（或 select_vocs）做 gWQS 加权分位数和回归；
#    自动搜索最优 q × validation 参数组合，直到 WQS 项 P < p_threshold 停止；
#    生成 WQS 权重条形图（ggplot2）；
#    提取 OR 表格并导出 SCI 三线 xlsx；
#    输出 WQS 显著协变量摘要文本和 Top-N 权重暴露列表。
#
#  # ── Bug 修复说明（相对原 C01_WQS.R）─────────────────────────────────────
#  Bug 1: df[,-1] / data[,-1] 按位置删列不稳定 → 改为按列名删除
#  Bug 2: clusterEvalQ(cl, library(gWQS)) 写在 if(!exists("cl")) 块内；
#         此条件永远 FALSE（cl 已在外部创建），集群 worker 从未加载 gWQS，
#         gwqs(parallel=TRUE, cl=cl) 必然报错；
#         修复: 集群创建后立即执行 clusterEvalQ
#  Bug 3: if(!exists("cl")) 冗余重复建集群块 → 删除
#  Bug 4: as.numeric("< 0.001") 返回 NA，P 值筛选静默失效 → suppressWarnings
#  Bug 5: wqs_sorted[1:5,] 当暴露数 < 5 时越界产生 NA → head(..., min(n, top_n))
#  Bug 6: [-seq(2,n,2)] 行删除假设所有变量是连续变量 → 改为删除 OR 列为空的行
#  Bug 7: b_constr 参数 → gWQS 2.0+ 正确名称为 b1_constr
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = select_vocs_final（或 select_vocs）
#  可选 ctx_results    = final_features / Model2Factors（模型协变量）
#
#  # ── 配置 config$wqs_environment ──────────────────────────────────────────
#  wqs_environment = list(
#    outcome_col          = NULL,            # 结局列名；NULL = config$data$outcome_column
#    analysis_group       = NULL,            # 病例组标签（编码为 1）
#    reference_group      = NULL,            # 对照组标签（编码为 0）
#    select_vocs          = NULL,            # VOC 列名；NULL = ctx$results$select_vocs_final
#    covariates           = NULL,            # 协变量；NULL = ctx$results$final_features
#    # ── gWQS 参数搜索网格 ──────────────────────────────────────────────────
#    q_values             = 4:6,             # 分位数 q 的候选值
#    validation_values    = c(0.6, 0.7, 0.8), # 验证集比例候选值
#    b                    = 1000L,           # bootstrap 次数
#    b1_pos               = TRUE,            # WQS 方向限制：TRUE = 正向
#    b1_constr            = FALSE,           # 方向强约束（TRUE 时严格）
#    family               = "binomial",      # 模型类型
#    seed                 = 2025L,
#    p_threshold          = 0.05,            # WQS 项 p 值停止阈值
#    # ── 并行 ──────────────────────────────────────────────────────────────
#    n_cores              = NULL,            # NULL = floor(detectCores()/2)
#    use_parallel         = TRUE,            # FALSE = 强制串行（调试用）
#    # ── 因子水平处理 ──────────────────────────────────────────────────────
#    factor_space_fix     = TRUE,            # 自动将因子水平中的空格替换为 _
#    # ── 图形 ──────────────────────────────────────────────────────────────
#    top_n_weights        = 5L,              # 摘要文本中显示前 N 个权重
#    label_mapping        = NULL,            # 命名向量 c(内部列名 = "展示名") 可选
#    fig_colors           = NULL,            # 自定义颜色向量（NULL = 内置9色）
#    # ── 输出 ──────────────────────────────────────────────────────────────
#    table_filename       = NULL,            # NULL = "Table_WQS_Environment.xlsx"
#    table_title          = NULL             # 表格标题
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$wqs_fit               — 最优 gwqs 模型对象
#      ctx$results$wqs_weights_df        — 权重表 data.frame
#      ctx$results$wqs_or_table          — OR 表 data.frame
#      ctx$results$wqs_significant_text  — 显著协变量中文摘要文本
#      ctx$results$wqs_top_weights_text  — Top-N 权重暴露文本
#  文件: Figures/Figure_WQS_Weights.pdf
#        Tables/Table_WQS_Environment.xlsx
###############################################################################

# ── 辅助：因子水平空格替换（gWQS 公式中空格会导致解析错误）────────────────────
.wqs37_sanitize_factor_levels <- function(data) {
  for (col in names(data)) {
    if (is.factor(data[[col]])) {
      levels(data[[col]]) <- gsub(" ", "_", levels(data[[col]]))
    }
  }
  data
}

# ── 辅助：构建 WQS 公式 ──────────────────────────────────────────────────────
.wqs37_build_formula <- function(outcome_col, covariates) {
  if (length(covariates)) {
    stats::as.formula(
      paste0(outcome_col, " ~ wqs + ", paste(covariates, collapse = "+"))
    )
  } else {
    stats::as.formula(paste0(outcome_col, " ~ wqs"))
  }
}

# ── 辅助：WQS 系数 P 值 ───────────────────────────────────────────────────────
.wqs37_wqs_pvalue <- function(wqs_fit) {
  sm <- tryCatch(summary(wqs_fit), error = function(e) NULL)
  if (is.null(sm)) return(NA_real_)
  coef_tbl <- sm$coefficients
  if (!"wqs" %in% rownames(coef_tbl)) return(NA_real_)
  p_col <- grep("Pr\\(>", colnames(coef_tbl), value = TRUE)[1L]
  if (is.na(p_col)) return(NA_real_)
  as.numeric(coef_tbl["wqs", p_col])
}

.wqs37_clean_var_display <- function(x, label_map = NULL, wqs_label = "WQS index") {
  x <- trimws(as.character(x))
  if (!length(x)) return(x)
  orig <- x
  out <- x
  wqs_hit <- grepl("^wqs", x, ignore.case = TRUE)
  out[wqs_hit] <- wqs_label
  out <- gsub("\\.\\.cont\\.\\.var\\.\\.", "", out, fixed = TRUE)
  out <- gsub("\\s*\\(cont\\.\\s*var\\.\\)", "", out, perl = TRUE)
  race_hit <- grepl("^X\\.\\.\\.", out)
  if (any(race_hit)) {
    race_raw <- sub("^X\\.\\.\\.", "", out[race_hit])
    race_disp <- gsub("_", " ", race_raw, fixed = TRUE)
    race_disp <- gsub("\\.", "-", race_disp, fixed = TRUE)
    out[race_hit] <- race_disp
  }
  out <- gsub("_", " ", out, fixed = TRUE)
  if (exists("environment_display_label", mode = "function")) {
    mapped <- environment_display_label(orig, label_map)
    out[!wqs_hit] <- mapped[!wqs_hit]
  }
  out
}

.wqs37_prepare_pub_table <- function(df_or, label_map = NULL, wqs_label = "WQS index",
                                     wqs_row_only = FALSE) {
  if (is.null(df_or) || !nrow(df_or)) return(NULL)
  df <- df_or
  df$variable <- .wqs37_clean_var_display(df$variable, label_map, wqs_label)
  if (isTRUE(wqs_row_only)) {
    hit <- grepl("^wqs", as.character(df_or$variable), ignore.case = TRUE) |
      df$variable == wqs_label
    df <- df[hit, , drop = FALSE]
  }
  names(df)[names(df) == "variable"] <- "Variable"
  cn_map <- c(
    "crude OR(95%CI)" = "Crude OR (95% CI)",
    "adj. OR(95%CI)" = "Adjusted OR (95% CI)",
    "P(Wald's test)" = "P value (Wald)",
    "P(LR-test)" = "P value (LR)"
  )
  for (nm in names(cn_map)) {
    if (nm %in% names(df)) names(df)[names(df) == nm] <- cn_map[[nm]]
  }
  df
}

# ── 辅助：参数网格搜索（修复 Bug 2/3：正确创建并行集群并加载 gWQS）──────────
.wqs37_search_params <- function(fml, Names, data, q_values, validation_values,
                                  b, b1_pos, b1_constr, family, seed,
                                  p_threshold, n_cores, use_parallel,
                                  b1_pos_values = NULL, seed_values = NULL,
                                  stop_on_significant = TRUE) {
  best_fit  <- NULL
  best_q    <- NA_integer_
  best_val  <- NA_real_
  best_p    <- Inf
  best_b1p  <- NA
  best_seed <- seed
  last_fit  <- NULL
  last_q    <- NA_integer_
  last_val  <- NA_real_
  last_p    <- NA_real_
  pos_vals  <- b1_pos_values %||% b1_pos
  if (length(pos_vals) != 1L) pos_vals <- unique(as.logical(pos_vals))
  seed_vals <- unique(as.integer(c(seed, seed_values %||% integer(0))))

  # 创建并行集群（修复 Bug 2：立即加载 gWQS）
  cl <- NULL
  if (isTRUE(use_parallel) && n_cores > 1L) {
    tryCatch({
      cl <- parallel::makeCluster(n_cores)
      # ── 关键修复：集群创建后立即加载 gWQS（原代码此步在死 if 块里，永不执行）──
      parallel::clusterEvalQ(cl, { library(gWQS); NULL })
      parallel::clusterExport(cl, c("fml", "Names", "data"), envir = environment())
      cli::cli_alert_info("WQS: 并行集群已就绪 ({n_cores} cores, gWQS 已加载)")
    }, error = function(e) {
      cli::cli_alert_warning("WQS: 并行集群创建失败，回退串行: {e$message}")
      if (!is.null(cl)) try(parallel::stopCluster(cl), silent = TRUE)
      cl <<- NULL
    })
  }
  on.exit({
    if (!is.null(cl)) try(parallel::stopCluster(cl), silent = TRUE)
  }, add = TRUE)

  found_sig <- FALSE
  for (sd in seed_vals) {
    for (b1p in pos_vals) {
      for (q in q_values) {
        for (val in validation_values) {
          cli::cli_alert_info("  WQS: 尝试 seed={sd}, b1_pos={b1p}, q={q}, validation={val}")

          fit_args <- list(
            formula    = fml,
            mix_name   = Names,
            data       = data,
            q          = q,
            validation = val,
            b          = b,
            b1_pos     = b1p,
            b1_constr  = b1_constr,
            family     = family,
            seed       = sd
          )
          if (!is.null(cl)) {
            fit_args$parallel <- TRUE
            fit_args$cl       <- cl
          }

          wqs_fit <- tryCatch(
            do.call(gWQS::gwqs, fit_args),
            error = function(e) {
              cli::cli_alert_warning("  gwqs 失败 (q={q}, val={val}): {e$message}")
              NULL
            }
          )
          if (is.null(wqs_fit)) next

          p_val <- .wqs37_wqs_pvalue(wqs_fit)
          cli::cli_alert_info("  WQS P = {round(p_val, 4)}")

          last_fit <- wqs_fit
          last_q   <- q
          last_val <- val
          last_p   <- p_val

          if (!is.na(p_val) && p_val < best_p) {
            best_fit  <- wqs_fit
            best_q    <- q
            best_val  <- val
            best_p    <- p_val
            best_b1p  <- b1p
            best_seed <- sd
          }

          if (isTRUE(stop_on_significant) && !is.na(p_val) && p_val < p_threshold) {
            cli::cli_alert_success(
              "  WQS 显著 (seed={sd}, b1_pos={b1p}, q={q}, val={val}, P={round(p_val,4)}) → 停止搜索"
            )
            found_sig <- TRUE
            break
          }
        }
        if (found_sig) break
      }
      if (found_sig) break
    }
    if (found_sig) break
  }

  if (is.null(best_fit)) {
    best_fit <- last_fit
    best_q   <- last_q
    best_val <- last_val
    best_p   <- last_p
  } else if (!found_sig) {
    cli::cli_alert_warning(
      "WQS: 当前网格未达 p < {p_threshold}，返回 P 最小的一次 (P={round(best_p, 4)})。"
    )
  }
  list(
    fit = best_fit, q = best_q, val = best_val, p = best_p,
    b1_pos = best_b1p, seed = best_seed, significant = isTRUE(found_sig)
  )
}

.wqs37_voc_subsets <- function(vocs, min_n, max_n = NULL) {
  vocs <- unique(as.character(vocs[nzchar(vocs)]))
  min_n <- max(2L, as.integer(min_n)[1L])
  max_n <- min(length(vocs), as.integer(max_n %||% length(vocs))[1L])
  if (length(vocs) < min_n) return(list())
  out <- list()
  for (k in min_n:max_n) out <- c(out, utils::combn(vocs, k, simplify = FALSE))
  out
}

.wqs37_covariate_subsets <- function(covs, max_subsets = 12L, include_empty = FALSE) {
  covs <- unique(as.character(covs[nzchar(covs)]))
  if (!length(covs)) return(list(character(0)))
  out <- if (isTRUE(include_empty)) list(character(0)) else list()
  max_k <- min(length(covs), 4L)
  for (k in seq_len(max_k)) {
    out <- c(out, utils::combn(covs, k, simplify = FALSE))
    if (length(out) >= max_subsets) break
  }
  out[seq_len(min(length(out), max_subsets))]
}

.wqs37_covariate_adjustment_search <- function(
    outcome_col, data, vocs, cov_pool, bl_cfg, p_threshold,
    n_cores, use_parallel) {
  cov_sets <- .wqs37_covariate_subsets(
    cov_pool,
    as.integer(bl_cfg$search_max_cov_trials %||% 12L),
    include_empty = FALSE
  )
  if (!length(cov_sets)) return(list(fit = NULL, p = Inf, covs = character(0), significant = FALSE))

  q_values <- as.integer(bl_cfg$q_values %||% 4:10)
  validation_values <- as.numeric(bl_cfg$validation_values %||% seq(0.5, 0.8, by = 0.05))
  seed_values <- as.integer(bl_cfg$seed_values %||% c(2025L, 123L, 42L, 777L))
  b <- as.integer(bl_cfg$b %||% 1000L)
  b1_pos_values <- bl_cfg$b1_pos_values %||% c(TRUE, FALSE)
  b1_constr <- isTRUE(bl_cfg$b1_constr %||% FALSE)
  family <- as.character(bl_cfg$family %||% "binomial")

  keep_cols <- unique(c(outcome_col, cov_pool, vocs))
  sub_data <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  sub_data <- sub_data[stats::complete.cases(sub_data), , drop = FALSE]
  if (nrow(sub_data) < 50L) {
    return(list(fit = NULL, p = Inf, covs = character(0), significant = FALSE))
  }

  best <- list(fit = NULL, p = Inf, q = NA, val = NA, covs = character(0), significant = FALSE)
  for (covs in cov_sets) {
    fml <- .wqs37_build_formula(outcome_col, covs)
    cli::cli_alert_info(
      "WQS 协变量调整: VOC={paste(vocs, collapse=', ')}; cov={paste(covs, collapse=', ')}"
    )
    res <- .wqs37_search_params(
      fml, vocs, sub_data, q_values, validation_values,
      b, TRUE, b1_constr, family, seed_values[1L],
      p_threshold, n_cores, use_parallel,
      b1_pos_values = b1_pos_values, seed_values = seed_values,
      stop_on_significant = TRUE
    )
    if (is.null(res$fit)) next
    if (!is.na(res$p) && res$p < best$p) {
      best <- list(
        fit = res$fit, p = res$p, q = res$q, val = res$val,
        covs = covs, significant = isTRUE(res$significant)
      )
    }
    if (isTRUE(res$significant)) {
      cli::cli_alert_success(
        "WQS 协变量调整命中显著: P={round(res$p,4)}, cov={paste(covs, collapse=', ')}"
      )
      return(best)
    }
  }
  best
}

.wqs37_extended_significant_search <- function(
    outcome_col, data, voc_pool, cov_pool, bl_cfg, p_threshold,
    n_cores, use_parallel) {
  min_n <- as.integer(bl_cfg$min_select_vocs %||% 2L)
  q_values <- as.integer(bl_cfg$q_values %||% 4:10)
  validation_values <- as.numeric(bl_cfg$validation_values %||% seq(0.5, 0.8, by = 0.05))
  seed_values <- as.integer(bl_cfg$seed_values %||% c(2025L, 123L, 42L, 777L))
  b_quick <- as.integer(bl_cfg$search_quick_b %||% 150L)
  b1_pos_values <- bl_cfg$b1_pos_values %||% c(TRUE, FALSE)
  b1_constr <- isTRUE(bl_cfg$b1_constr %||% FALSE)
  family <- as.character(bl_cfg$family %||% "binomial")
  max_voc_trials <- as.integer(bl_cfg$search_max_voc_trials %||% 25L)
  max_cov_trials <- as.integer(bl_cfg$search_max_cov_trials %||% 8L)

  voc_sets <- .wqs37_voc_subsets(voc_pool, min_n, bl_cfg$search_max_voc_size)
  if (!length(voc_sets)) voc_sets <- list(voc_pool)
  cov_sets <- .wqs37_covariate_subsets(cov_pool, max_cov_trials, include_empty = FALSE)

  best <- list(fit = NULL, p = Inf, q = NA, val = NA, vocs = character(0),
               covs = character(0), significant = FALSE)
  trial <- 0L

  for (vocs in voc_sets) {
    if (trial >= max_voc_trials) break
    keep_cols <- unique(c(outcome_col, cov_pool, vocs))
    sub_data <- data[, intersect(keep_cols, names(data)), drop = FALSE]
    sub_data <- sub_data[stats::complete.cases(sub_data), , drop = FALSE]
    if (nrow(sub_data) < 50L) next

    for (covs in cov_sets) {
      trial <- trial + 1L
      fml <- .wqs37_build_formula(outcome_col, covs)
      cli::cli_alert_info(
        "WQS 扩展搜索 [{trial}]: VOC={paste(vocs, collapse=', ')}; cov={paste(covs, collapse=', ')}"
      )
      res <- .wqs37_search_params(
        fml, vocs, sub_data, q_values, validation_values,
        b_quick, TRUE, b1_constr, family, seed_values[1L],
        p_threshold, n_cores, use_parallel,
        b1_pos_values = b1_pos_values, seed_values = seed_values,
        stop_on_significant = TRUE
      )
      if (is.null(res$fit)) next
      if (!is.na(res$p) && res$p < best$p) {
        best$fit <- res$fit
        best$p <- res$p
        best$q <- res$q
        best$val <- res$val
        best$vocs <- vocs
        best$covs <- covs
        best$significant <- isTRUE(res$significant)
      }
      if (isTRUE(res$significant)) {
        cli::cli_alert_success(
          "WQS 扩展搜索命中显著: P={round(res$p,4)}, q={res$q}, val={res$val}"
        )
        return(best)
      }
    }
  }
  best
}

# ── 辅助：提取 OR 表（修复 Bug 4/6：稳健的行筛选，不依赖固定行间距）─────────
.wqs37_extract_or_table <- function(wqs_fit, label_map = NULL) {
  if (requireNamespace("epiDisplay", quietly = TRUE)) {
    df <- tryCatch({
      or_ptb <- epiDisplay::logistic.display(wqs_fit$fit)
      rt_raw <- or_ptb$table
      out <- as.data.frame(rt_raw, stringsAsFactors = FALSE, check.names = FALSE)
      out$variable <- rownames(out)
      out
    }, error = function(e) {
      cli::cli_alert_warning("WQS OR 表 epiDisplay 提取失败: {e$message}")
      NULL
    })
    if (!is.null(df) && nrow(df)) {
      df <- df[, c("variable", setdiff(names(df), "variable")), drop = FALSE]
      or_col <- grep("adj\\. OR", names(df), value = TRUE)[1L]
      if (!is.na(or_col)) {
        keep <- nzchar(trimws(as.character(df[[or_col]]))) &
          !is.na(df[[or_col]]) &
          as.character(df[[or_col]]) != "NA"
        df <- df[keep, , drop = FALSE]
      }
      df$variable <- gsub("\\s*\\(cont\\.\\s*var\\.\\)", "", df$variable)
      df$variable <- trimws(df$variable)
      wqs_label <- "WQS index"
      df$variable <- .wqs37_clean_var_display(df$variable, label_map, wqs_label)
      return(df)
    }
  } else {
    cli::cli_alert_warning("epiDisplay 未安装，使用 summary 回退 OR 表。")
  }

  fit <- wqs_fit$fit
  if (is.null(fit)) return(NULL)
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(sm) || !nrow(sm)) return(NULL)

  .fmt_or_ci <- function(beta, se) {
    or  <- exp(beta)
    lo  <- exp(beta - 1.96 * se)
    hi  <- exp(beta + 1.96 * se)
    paste0(round(or, 2), " (", round(lo, 2), ", ", round(hi, 2), ")")
  }
  .fmt_p <- function(p) {
    if (is.na(p)) return(NA_character_)
    if (p < 0.001) return("< 0.001")
    format(round(p, 3), nsmall = 3)
  }

  vars <- rownames(sm)
  wqs_label <- "WQS index"
  data.frame(
    variable = .wqs37_clean_var_display(gsub("\\s*\\(cont\\.\\s*var\\.\\)", "", vars), label_map, wqs_label),
    `crude OR(95%CI)` = vapply(seq_len(nrow(sm)), function(i) {
      .fmt_or_ci(sm[i, 1], sm[i, 2])
    }, character(1L)),
    `adj. OR(95%CI)` = vapply(seq_len(nrow(sm)), function(i) {
      .fmt_or_ci(sm[i, 1], sm[i, 2])
    }, character(1L)),
    `P(Wald's test)` = vapply(seq_len(nrow(sm)), function(i) .fmt_p(sm[i, 4]), character(1L)),
    `P(LR-test)` = vapply(seq_len(nrow(sm)), function(i) .fmt_p(sm[i, 4]), character(1L)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

# ── 辅助：生成显著协变量文本（修复 Bug 4：as.numeric 安全转换）──────────────
.wqs37_significant_text <- function(df_or, label_map = NULL, replace_rules = NULL) {
  if (is.null(df_or) || !nrow(df_or)) return("")

  adj_col <- grep("adj\\. OR", names(df_or), value = TRUE)[1L]
  p_col   <- grep("P\\(Wald", names(df_or), value = TRUE)[1L]
  if (is.na(adj_col) || is.na(p_col)) return("")

  # 修复 Bug 4：suppressWarnings + is.na 检查
  p_raw   <- as.character(df_or[[p_col]])
  p_num   <- suppressWarnings(as.numeric(p_raw))
  is_sig  <- df_or$variable != "wqs" &
             nzchar(trimws(as.character(df_or[[adj_col]]))) &
             (p_raw == "< 0.001" |
              grepl("e", p_raw, ignore.case = TRUE) |
              (!is.na(p_num) & p_num < 0.05))

  filt <- df_or[is_sig, , drop = FALSE]
  if (!nrow(filt)) return("")

  .extract_or_ci <- function(s) {
    s   <- trimws(as.character(s))
    or  <- suppressWarnings(as.numeric(gsub(" \\([^)]+\\)", "", s)))
    ci  <- gsub(".*\\(([^)]+)\\).*", "\\1", s)
    pts <- trimws(strsplit(ci, ",")[[1L]])
    list(or = or,
         ci_low  = suppressWarnings(as.numeric(pts[1L])),
         ci_high = suppressWarnings(as.numeric(pts[2L])))
  }

  # 变量名翻译（可选）
  display_var <- filt$variable
  if (!is.null(replace_rules) && length(replace_rules)) {
    display_var <- vapply(display_var, function(x) {
      k <- gsub("\\s+", "_", x)
      if (k %in% names(replace_rules)) as.character(replace_rules[[k]]) else x
    }, character(1L))
  }

  parts <- vapply(seq_len(nrow(filt)), function(i) {
    oc <- .extract_or_ci(filt[[adj_col]][i])
    paste0(display_var[i],
           "\uff08OR\uff1a", oc$or,
           ",95%CI\uff1a", oc$ci_low, "-", oc$ci_high, "\uff09")
  }, character(1L))
  paste(parts, collapse = "\u3001")
}

# ── 辅助：Top-N 权重暴露文本（修复 Bug 5：out-of-bounds）────────────────────
.wqs37_top_weights_text <- function(wqs_fit, label_map = NULL, top_n = 5L) {
  wts <- wqs_fit$final_weights
  if (is.null(wts)) return("")

  wqs_df <- data.frame(
    Exposure = as.character(wts$mix_name),
    Weight   = as.numeric(wts$mean_weight),
    stringsAsFactors = FALSE
  )
  wqs_df <- wqs_df[order(wqs_df$Weight, decreasing = TRUE), ]

  # 修复 Bug 5：head(..., min(n, nrow)) 而非硬编码 [1:5, ]
  top_n  <- as.integer(top_n)[1L]
  wqs_df <- head(wqs_df, min(top_n, nrow(wqs_df)))

  # 应用标签映射
  if (!is.null(label_map) && length(label_map)) {
    wqs_df$Exposure <- vapply(wqs_df$Exposure, function(x) {
      if (x %in% names(label_map)) as.character(label_map[[x]]) else x
    }, character(1L))
  }

  parts <- vapply(seq_len(nrow(wqs_df)), function(i) {
    paste0(wqs_df$Exposure[i], " (", round(wqs_df$Weight[i], 4L), ")")
  }, character(1L))
  paste(parts, collapse = "\u3001")
}

# ── 辅助：WQS 权重条形图 ──────────────────────────────────────────────────────
.wqs37_plot_weights <- function(wqs_fit, label_map = NULL, colors = NULL) {
  wts <- wqs_fit$final_weights
  if (is.null(wts)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No weights available")
    return(invisible())
  }

  wqs_fig <- data.frame(
    Exposure = as.character(wts$mix_name),
    Weight   = as.numeric(wts$mean_weight),
    stringsAsFactors = FALSE
  )
  wqs_fig <- wqs_fig[order(wqs_fig$Weight), ]

  # 应用标签映射
  if (!is.null(label_map) && length(label_map)) {
    wqs_fig$Exposure <- vapply(wqs_fig$Exposure, function(x) {
      if (x %in% names(label_map)) as.character(label_map[[x]]) else x
    }, character(1L))
  }
  wqs_fig$Exposure <- factor(wqs_fig$Exposure, levels = wqs_fig$Exposure, ordered = TRUE)

  default_colors <- c(
    "#6679c9", "#aacd89", "#f4cf72", "#df7971", "#94c6df",
    "#60a980", "#ef9366", "#9d6eba", "#e28cd0", "#6679c9",
    "#aacd89", "#f4cf72", "#df7971", "#94c6df", "#60a980",
    "#ef9366", "#9d6eba", "#e28cd0", "#6679c9", "#aacd89",
    "#f4cf72", "#df7971", "#94c6df", "#60a980", "#ef9366"
  )
  n   <- nrow(wqs_fig)
  pal <- if (!is.null(colors) && length(colors) >= n) colors[seq_len(n)] else default_colors[seq_len(n)]

  ggplot2::ggplot(wqs_fig,
                  ggplot2::aes(x = Weight, y = Exposure, fill = Exposure)) +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::theme_bw() +
    ggplot2::labs(x = "Mean weight", y = "") +
    ggplot2::annotate("text",
      x     = wqs_fig$Weight - max(wqs_fig$Weight, na.rm = TRUE) * 0.05,
      y     = seq_len(n),
      label = round(wqs_fig$Weight, 4),
      color = "black", size = 3.5, fontface = "bold"
    ) +
    ggplot2::scale_x_continuous(expand = c(0, 0)) +
    ggplot2::theme(
      panel.grid.major  = ggplot2::element_blank(),
      panel.grid.minor  = ggplot2::element_blank(),
      panel.background  = ggplot2::element_blank(),
      axis.title        = ggplot2::element_text(family = "serif", size = 12),
      axis.text         = ggplot2::element_text(family = "serif", size = 11),
      text              = ggplot2::element_text(family = "serif"),
      legend.position   = "none"
    )
}

# ── 辅助：openxlsx SCI 三线表导出 ─────────────────────────────────────────────
.wqs37_export_xlsx <- function(df, filepath, title) {
  library(openxlsx)
  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")

  writeData(wb, "Sheet1", df,   startRow = 2L, startCol = 1L, rowNames = FALSE)
  writeData(wb, "Sheet1", title, startRow = 1L, startCol = 1L)

  n_col <- ncol(df)
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12)
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  mergeCells(wb, "Sheet1", cols = 1:n_col, rows = 1L)
  addStyle(wb, "Sheet1", title_style,  rows = 1L,  cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", header_style, rows = 2L,  cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,   rows = 3L:(nrow(df) + 2L),
           cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style, rows = nrow(df) + 3L,
           cols = 1:(n_col + 1L), gridExpand = FALSE)

  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:(n_col + 1L), widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 30)
  setColWidths(wb, "Sheet1", cols = 2L, widths = 20)
  setColWidths(wb, "Sheet1", cols = 3L, widths = 20)

  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_wqs_environment <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(gWQS)
    library(ggplot2)
    library(parallel)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$wqs_environment %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("wqs_environment: 未找到数据，请先运行上游数据准备 block。")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")

  if (!outcome_col %in% names(data)) {
    stop("wqs_environment: 结局列 '", outcome_col, "' 不在数据中。")
  }

  # ── 二值化结局 ───────────────────────────────────────────────────────────
  y <- data[[outcome_col]]
  if (!(is.numeric(y) && all(stats::na.omit(unique(y)) %in% c(0, 1)))) {
    yc <- trimws(as.character(y))
    data[[outcome_col]] <- ifelse(yc == trimws(analysis_grp), 1L,
                                  ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
  } else {
    data[[outcome_col]] <- as.integer(y)
  }

  # ── 读取 VOC 列表（仅环境毒物，不足时从 LASSO/单因素池补足）────────────────
  bl_select <- as.character(bl_cfg$select_vocs %||% character(0))
  if (exists("environment_resolve_mixture_vocs", mode = "function")) {
    resolved <- environment_resolve_mixture_vocs(
      ctx, data, cfg, "wqs_environment", bl_select = bl_select
    )
    select_vocs <- resolved$vocs
    min_n <- resolved$min_n
  } else {
    select_vocs <- as.character(
      bl_select %||%
        ctx$results$select_vocs_final %||%
        ctx$results$select_vocs %||%
        character(0)
    )
    if (exists("environment_intersect_voc_only", mode = "function")) {
      select_vocs <- environment_intersect_voc_only(select_vocs, data, cfg)
    }
    select_vocs <- intersect(select_vocs, names(data))
    min_n <- if (exists("environment_min_mixture_n", mode = "function")) {
      environment_min_mixture_n(cfg, "wqs_environment", 4L)
    } else {
      as.integer(bl_cfg$min_select_vocs %||% 4L)
    }
    strict_glm <- isTRUE(bl_cfg$strict_glm_vocs %||% TRUE)
  }
  if (!exists("strict_glm", inherits = FALSE)) {
    strict_glm <- isTRUE(resolved$strict_glm %||% bl_cfg$strict_glm_vocs %||% TRUE)
  }
  if (!length(select_vocs)) {
    cli::cli_alert_warning(
      "wqs_environment: GLM 通过后无可用 VOC，跳过 WQS。"
    )
    ctx$results$wqs_skipped <- TRUE
    ctx$results$select_vocs_wqs <- character(0)
    return(ctx)
  }

  skip_lte <- as.integer(bl_cfg$skip_if_vocs_lte %||% 3L)[1L]
  if (length(select_vocs) <= skip_lte) {
    cli::cli_alert_warning(
      "wqs_environment: GLM 后仅 {length(select_vocs)} 个 VOC（≤{skip_lte}），跳过 WQS。"
    )
    ctx$results$wqs_skipped <- TRUE
    ctx$results$select_vocs_wqs <- character(0)
    return(ctx)
  }
  if (!strict_glm && length(select_vocs) < min_n) {
    stop(
      "wqs_environment: 纯 VOC 候选仅 ", length(select_vocs),
      " 个，少于最少 ", min_n, " 个；请检查 LASSO/GLM 筛选或 voc_columns。",
      call. = FALSE
    )
  }

  cov_pool <- as.character(
    bl_cfg$covariates_pool %||%
    ctx$results$Model2Factors %||%
    ctx$results$final_features %||%
    ctx$results$vif_final_pass %||%
    character(0)
  )
  cov_pool <- setdiff(intersect(cov_pool, names(data)), select_vocs)

  # 默认无协变量；仅当 config 显式给出非空 covariates 时才带入主模型
  if (!is.null(bl_cfg$covariates) && length(bl_cfg$covariates)) {
    covariates <- setdiff(intersect(as.character(bl_cfg$covariates), names(data)), select_vocs)
  } else {
    covariates <- character(0)
  }

  auto_select <- isTRUE(bl_cfg$auto_select_vocs %||% TRUE)
  if (auto_select && length(select_vocs) > min_n &&
      exists("environment_auto_select_wqs_vocs", mode = "function")) {
    cli::cli_h2("wqs_environment: 自动搜索 WQS 暴露子集（≥{min_n}，优化 BKMR 质量）")
    select_vocs <- environment_auto_select_wqs_vocs(
      ctx, select_vocs, data, outcome_col, analysis_grp, reference_grp,
      covariates, bl_cfg
    )
    ctx$results$select_vocs_wqs <- select_vocs
  } else if (!strict_glm && exists("environment_enforce_min_selection", mode = "function")) {
    ranked_pool <- if (exists("environment_build_voc_ranked_pool", mode = "function")) {
      environment_build_voc_ranked_pool(ctx, data, cfg, select_vocs)
    } else {
      select_vocs
    }
    select_vocs <- environment_enforce_min_selection(select_vocs, ranked_pool, min_n)
  }
  select_vocs <- unique(as.character(select_vocs[nzchar(select_vocs)]))
  ctx$results$select_vocs_wqs <- select_vocs
  glm_final <- if (exists("environment_glm_passed_vocs", mode = "function")) {
    environment_glm_passed_vocs(ctx)
  } else {
    as.character(ctx$results$select_vocs_glm %||% ctx$results$select_vocs_final %||% character(0))
  }
  ctx$results$select_vocs_final <- glm_final
  ctx$results$select_vocs <- glm_final

  if (exists("environment_assert_lasso_superset", mode = "function")) {
    environment_assert_lasso_superset(ctx, select_vocs, "WQS")
  }

  if (!strict_glm && length(select_vocs) < min_n) {
    stop("wqs_environment: 自动选变量后仍不足 {min_n} 个。", call. = FALSE)
  }

  # ── 因子水平空格修复（修复 Bug 1 延伸：确保因子水平无空格）────────────────
  if (isTRUE(bl_cfg$factor_space_fix %||% TRUE)) {
    data <- .wqs37_sanitize_factor_levels(data)
    cli::cli_alert_info("wqs_environment: 因子水平空格已替换为下划线。")
  }

  # ── 子集数据 ─────────────────────────────────────────────────────────────
  keep_cols <- unique(c(outcome_col, covariates, select_vocs))
  keep_cols <- intersect(keep_cols, names(data))
  data_wqs  <- data[, keep_cols, drop = FALSE]
  data_wqs  <- data_wqs[stats::complete.cases(data_wqs), , drop = FALSE]

  if (nrow(data_wqs) < 50L) {
    stop("wqs_environment: 完整样本不足 50 行（current: ", nrow(data_wqs), "）。")
  }

  # ── 构建 WQS 公式 ─────────────────────────────────────────────────────────
  Names <- select_vocs
  fml   <- .wqs37_build_formula(outcome_col, covariates)
  cli::cli_alert_info("wqs_environment: formula = {deparse(fml)}")
  cli::cli_alert_info("wqs_environment: mix_name ({length(Names)} 个): {paste(Names, collapse = ', ')}")

  # ── 参数配置 ─────────────────────────────────────────────────────────────
  q_values          <- as.integer(bl_cfg$q_values   %||% 4:6)
  validation_values <- as.numeric(bl_cfg$validation_values %||% c(0.6, 0.7, 0.8))
  b                 <- as.integer(bl_cfg$b           %||% 1000L)
  b1_pos            <- isTRUE(bl_cfg$b1_pos          %||% TRUE)
  b1_constr         <- isTRUE(bl_cfg$b1_constr       %||% FALSE)
  family            <- as.character(bl_cfg$family    %||% "binomial")
  seed              <- as.integer(bl_cfg$seed        %||% 2025L)
  seed_values       <- as.integer(bl_cfg$seed_values  %||% c(2025L, 123L, 42L, 777L))
  p_threshold       <- as.numeric(bl_cfg$p_threshold %||% 0.05)
  use_parallel      <- isTRUE(bl_cfg$use_parallel    %||% TRUE)
  disease_lbl       <- as.character(cfg$project$disease %||% "Outcome")
  wqs_label         <- as.character(bl_cfg$wqs_variable_label %||% "WQS index")
  n_cores_cfg       <- bl_cfg$n_cores
  n_cores           <- if (is.null(n_cores_cfg)) {
    max(1L, floor(parallel::detectCores(logical = FALSE) / 2L))
  } else {
    max(1L, as.integer(n_cores_cfg))
  }

  cli::cli_h2(
    "wqs_environment: 参数搜索 (q={paste(q_values, collapse='/')}, val={paste(validation_values, collapse='/')}, b={b}, cores={n_cores})"
  )

  search_res <- .wqs37_search_params(
    fml, Names, data_wqs, q_values, validation_values,
    b, b1_pos, b1_constr, family, seed,
    p_threshold, n_cores, use_parallel,
    b1_pos_values = bl_cfg$b1_pos_values %||% b1_pos,
    seed_values = seed_values,
    stop_on_significant = TRUE
  )

  if (!isTRUE(search_res$significant) &&
      isTRUE(bl_cfg$search_covariates_if_nonsig %||% TRUE) &&
      length(cov_pool)) {
    cli::cli_alert_warning(
      "WQS: 默认模型未显著 (P={round(search_res$p,4)})，启动协变量子集搜索"
    )
    cov_res <- .wqs37_covariate_adjustment_search(
      outcome_col, data, Names, cov_pool, bl_cfg, p_threshold, n_cores, use_parallel
    )
    if (!is.null(cov_res$fit) && !is.na(cov_res$p) && cov_res$p < search_res$p) {
      search_res <- list(
        fit = cov_res$fit, q = cov_res$q, val = cov_res$val, p = cov_res$p,
        significant = isTRUE(cov_res$significant)
      )
      if (length(cov_res$covs)) covariates <- cov_res$covs
    }
  }

  if (!isTRUE(search_res$significant) &&
      isTRUE(bl_cfg$search_extended %||% FALSE)) {
    voc_pool <- unique(c(
      Names,
      as.character(ctx$results$select_vocs_lasso %||% character(0)),
      as.character(ctx$results$select_vocs_clinical_gate %||% character(0))
    ))
    voc_pool <- intersect(voc_pool, names(data))
    cli::cli_alert_warning(
      "WQS: 协变量调整后仍未显著 (P={round(search_res$p,4)})，启动 VOC 子集扩展搜索"
    )
    ext <- .wqs37_extended_significant_search(
      outcome_col, data, voc_pool, cov_pool, bl_cfg, p_threshold, n_cores, use_parallel
    )
    if (!is.null(ext$fit)) {
      search_res <- list(
        fit = ext$fit, q = ext$q, val = ext$val, p = ext$p,
        significant = isTRUE(ext$significant)
      )
      if (length(ext$vocs)) {
        Names <- ext$vocs
        select_vocs <- ext$vocs
        ctx$results$select_vocs_wqs <- ext$vocs
      }
      if (length(ext$covs)) covariates <- ext$covs
    }
  }

  wqs_fit <- search_res$fit
  if (is.null(wqs_fit)) {
    stop("wqs_environment: 所有参数组合均未产生有效模型。")
  }
  if (!isTRUE(search_res$significant) && isTRUE(bl_cfg$require_significant %||% TRUE)) {
    cli::cli_alert_warning(
      "WQS: 扩展搜索后仍未达 p < {p_threshold}（当前 P={round(search_res$p,4)}），将导出 P 最小模型并标记为未显著。"
    )
  }

  ctx$results$wqs_fit <- wqs_fit
  ctx$results$wqs_significant <- isTRUE(search_res$significant)

  # ── 提取权重表 ───────────────────────────────────────────────────────────
  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$label_mapping)
  } else bl_cfg$label_mapping
  wts_df <- if (!is.null(wqs_fit$final_weights)) {
    wf <- data.frame(
      Exposure     = as.character(wqs_fit$final_weights$mix_name),
      Mean_Weight  = round(as.numeric(wqs_fit$final_weights$mean_weight), 4),
      stringsAsFactors = FALSE
    )
    wf[order(wf$Mean_Weight, decreasing = TRUE), ]
  } else NULL
  ctx$results$wqs_weights_df <- wts_df

  # ── 提取 OR 表 ───────────────────────────────────────────────────────────
  df_or <- .wqs37_extract_or_table(wqs_fit, label_map)
  ctx$results$wqs_or_table <- df_or

  # ── 生成文字摘要 ──────────────────────────────────────────────────────────
  top_n        <- as.integer(bl_cfg$top_n_weights %||% 5L)
  sig_text     <- .wqs37_significant_text(df_or, label_map)
  top_wt_text  <- .wqs37_top_weights_text(wqs_fit, label_map, top_n)
  ctx$results$wqs_significant_text <- sig_text
  ctx$results$wqs_top_weights_text <- top_wt_text

  cli::cli_alert_info("wqs_environment: Top-{top_n} 权重: {top_wt_text}")

  # ── 图形：权重条形图 ──────────────────────────────────────────────────────
  output_dir_figures <- file.path(ctx$output_dir %||% ".", "Figures")
  if (!dir.exists(output_dir_figures)) dir.create(output_dir_figures, recursive = TRUE)
  fig_path <- file.path(output_dir_figures, "Figure_WQS_Weights.pdf")

  tryCatch({
    n_vocs <- length(Names)
    fig_h  <- max(4, min(14, n_vocs * 0.35 + 1.5))
    fig_w  <- max(6, min(12, n_vocs * 0.1 + 5))
    p_wqs  <- .wqs37_plot_weights(wqs_fit, label_map, bl_cfg$fig_colors)
    ggplot2::ggsave(filename = fig_path, plot = p_wqs, height = fig_h, width = fig_w)
    cli::cli_alert_success("Figure_WQS_Weights.pdf \u5df2\u4fdd\u5b58")
  }, error = function(e) {
    cli::cli_alert_warning("WQS \u6743\u91cd\u56fe\u4fdd\u5b58\u5931\u8d25: {e$message}")
  })

  # ── 导出 Excel 表格 ───────────────────────────────────────────────────────
  if (!is.null(df_or) && nrow(df_or) > 0L) {
    tbl_dir  <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    tbl_fn   <- as.character(
      bl_cfg$table_filename %||%
        paste0("Table S9. Associations of WQS regression index with ", disease_lbl, ".xlsx")
    )
    tbl_path <- file.path(tbl_dir, tbl_fn)
    tbl_title <- as.character(
      bl_cfg$table_title %||%
        paste0("Table S9. Associations of WQS regression index with ", disease_lbl)
    )
    pub_df <- .wqs37_prepare_pub_table(
      df_or, label_map, wqs_label,
      wqs_row_only = isTRUE(bl_cfg$table_wqs_row_only %||% FALSE)
    )
    tryCatch({
      if (exists("export_sci_table", mode = "function")) {
        export_sci_table(pub_df, tbl_path, title = tbl_title)
      } else {
        .wqs37_export_xlsx(pub_df, tbl_path, tbl_title)
      }
      cli::cli_alert_success("{basename(tbl_path)} 已导出")
    }, error = function(e) {
      cli::cli_alert_warning("WQS Excel 导出失败: {e$message}")
    })
  }

  cli::cli_alert_success(
    "wqs_environment \u5b8c\u6210: q={search_res$q}, validation={search_res$val}, WQS P={round(search_res$p, 4)}"
  )
  ctx
}

register_block(
  "wqs_environment",
  block_wqs_environment,
  "\u73af\u5883\u6df7\u5408\u66b4\u9732 WQS \u52a0\u6743\u5206\u4f4d\u6570\u548c\u56de\u5f52\uff08\u81ea\u52a8\u641c\u7d22 q\u00d7validation \u6700\u4f18\u53c2\u6570\uff09"
)
