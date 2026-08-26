###############################################################################
#  feature_selection_consensus — 多模型特征选择投票、共识解析与最终特征导出（无单方法、无韦恩/S2 图）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # 由 pipeline 决定，块内不选源
#  require_ctx_results = ctx$results$feature_selection_by_model  # 须先跑 01–06 各方法块
#  require_ctx_results += ctx$results$feature_selection_work（可选；含 feats/uv_cand/outcome 等）
#  require_ctx_results += ctx$results$univar_features / univar_pvalues（共识排序与回退）
#
#  feature_selection_consensus = list(
#    enable                          = TRUE,
#    target_n_features_min           = 8L,
#    target_n_features_max           = 50L,
#    prompt_final_methods            = NULL,   # NULL=交互式询问；批跑请设 final_methods
#    final_methods                   = NULL,
#    overlap_plot_methods            = NULL,   # 供下游 08 韦恩块；本块仅写入 venn_input
#    force_composite_features        = TRUE,
#    composite_features              = NULL,   # NULL → prediction$index_vars
#    min_composite_features          = 0L,
#    require_min_composites_in_auto  = FALSE,
#    fallback_univar_if_no_consensus = TRUE,
#    anthropometric_single           = NULL,   # NULL → 与父块相同默认（BMI/Weight/Height 最多 1 个）
#    persist_final_artifacts         = TRUE,
#    persist_to_checkpoints          = TRUE,
#    pause_enable                    = TRUE,
#    pause_on_no_data                = TRUE,
#    pause_on_all_methods_empty      = TRUE,
#    pause_on_resolve_fail           = TRUE,
#    pause_on_final_methods_prompt   = TRUE
#  ),
#
#  register_block: "feature_selection_consensus"
#  典型流水线: 01–06 方法块 → 本块 → 08 韦恩图（可选）
#  块内 bl_cfg <- cfg$feature_selection_consensus %||% cfg$feature_selection（legacy）
###############################################################################

.fsc07_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.fsc07_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "feature_selection_consensus",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_consensus — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.fsc07_anthropometric_single_cfg <- function(cfg) {
  fs <- cfg$feature_selection_consensus %||% cfg$feature_selection %||% list()
  fs$anthropometric_single %||% list(
    enable = TRUE,
    vars = c("BMI", "Weight", "Height"),
    max_coexistent = 1L,
    prefer_keep_one_order = c("BMI", "Weight", "Height")
  )
}

.fsc07_enforce_single_anthropometric <- function(vars, cfg, ctx = NULL, label = "feature_selection") {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  ar <- .fsc07_anthropometric_single_cfg(cfg)
  if (!isTRUE(ar$enable %||% TRUE)) {
    return(list(ctx = ctx, kept = vars, dropped = character(0)))
  }
  max_c <- suppressWarnings(as.integer(ar$max_coexistent)[1L])
  if (is.na(max_c)) max_c <- 1L
  if (max_c >= 3L) {
    return(list(ctx = ctx, kept = vars, dropped = character(0)))
  }
  anthro_cfg <- unique(as.character(ar$vars %||% c("BMI", "Weight", "Height")))
  prefer_keep <- unique(as.character(
    ar$prefer_keep_one_order %||% c("BMI", "Weight", "Height")
  ))
  anthro <- intersect(anthro_cfg, vars)
  if (length(anthro) <= max_c) {
    return(list(ctx = ctx, kept = vars, dropped = character(0)))
  }
  keep <- prefer_keep[prefer_keep %in% anthro][1L]
  if (is.na(keep) || !nzchar(keep)) keep <- anthro[1L]
  drop <- setdiff(anthro, keep)
  drop <- drop[nzchar(drop)]
  kept <- setdiff(vars, drop)
  cli::cli_alert_info(
    "{label}: 特征选择人体测量最多 {max_c} 个，保留 [{keep}]，剔除: {paste(drop, collapse = ', ')}"
  )
  if (!is.null(ctx)) {
    ctx$results$feature_selection_anthropometric_kept <- keep
    ctx$results$feature_selection_anthropometric_dropped <- drop
  }
  list(ctx = ctx, kept = kept, dropped = drop)
}

.fsc07_order_subset <- function(vars, order_vec, n_max, protect = character(0)) {
  vars <- unique(as.character(vars[nzchar(as.character(vars))]))
  protect <- unique(as.character(protect[nzchar(as.character(protect))]))
  protect <- intersect(protect, vars)
  ordered <- intersect(order_vec, vars)
  # 复合/暴露指标常不在方法投票序 order_vec 中，须强制保留（不可被 intersect 滤掉）
  vars <- unique(c(setdiff(protect, ordered), ordered))
  if (length(vars) <= n_max) return(vars)
  rest <- setdiff(ordered, protect)
  n_rest <- max(0L, n_max - length(protect))
  if (length(rest) > n_rest) rest <- rest[seq_len(n_rest)]
  unique(c(protect, rest))
}

.fsc07_merge_forced_composites <- function(
    vars, comp_tags, cand_feats, order_vec, n_max,
    label = "feature_selection", enable = TRUE, data_cols = NULL) {
  vars <- unique(as.character(vars[nzchar(vars)]))
  comp_tags <- trimws(as.character(comp_tags[nzchar(comp_tags)]))
  comp_ok <- unique(intersect(comp_tags, cand_feats))
  if (isTRUE(enable) && length(comp_tags) && length(data_cols)) {
    comp_ok <- unique(c(comp_ok, intersect(comp_tags, data_cols)))
  }
  if (!isTRUE(enable)) {
    return(.fsc07_order_subset(vars, order_vec, n_max, protect = character(0)))
  }
  miss <- setdiff(comp_ok, vars)
  if (length(miss)) {
    cli::cli_alert_info(
      "{label}: 复合指标未出现在方法入选集，已强制并入: {paste(miss, collapse = ', ')}"
    )
    vars <- unique(c(vars, miss))
  }
  .fsc07_order_subset(vars, order_vec, n_max, protect = comp_ok)
}

.fsc07_venn_list_for_final <- function(
    by_model, overlap_methods, final, U, composite_in_final) {
  composite_in_final <- intersect(composite_in_final, final)
  if (length(overlap_methods) >= 2L) {
    return(stats::setNames(
      lapply(overlap_methods, function(m) {
        unique(c(
          intersect(by_model[[m]] %||% character(0), U),
          composite_in_final
        ))
      }),
      overlap_methods
    ))
  }
  if (length(overlap_methods) == 1L) {
    m1 <- overlap_methods[1L]
    return(stats::setNames(
      list(final, final),
      c(m1, paste0(m1, " (final)"))
    ))
  }
  list()
}

.fsc07_features_for_method_combo <- function(by_model, combo, order_vec) {
  combo <- unique(as.character(combo[nzchar(combo)]))
  if (!length(combo)) return(character(0))
  raw <- if (length(combo) == 1L) {
    as.character(by_model[[combo[1L]]] %||% character(0))
  } else {
    Reduce(intersect, by_model[combo])
  }
  intersect(order_vec, raw)
}

.fsc07_resolve_final_selection <- function(
    by_model, method_names, order_vec, uv_pool, data_cols, feats_cand,
    fn_min, fn_max, fs, cfg) {
  force_comp <- isTRUE(fs$force_composite_features %||% TRUE)
  pred_cfg <- cfg$prediction %||% list()
  comp_tags <- trimws(as.character(
    fs$composite_features %||% pred_cfg$index_vars %||% character(0)
  ))
  comp_tags <- comp_tags[nzchar(comp_tags)]
  min_comp <- as.integer(fs$min_composite_features %||% 0L)[1L]
  if (is.na(min_comp) || min_comp < 0L) min_comp <- 0L
  require_comp <- isTRUE(fs$require_min_composites_in_auto %||% FALSE)
  fallback_uv <- isTRUE(fs$fallback_univar_if_no_consensus %||% TRUE)

  .score <- function(inter, k_len) {
    nc <- length(intersect(inter, comp_tags))
    nf <- length(inter)
    mid <- (fn_min + fn_max) / 2
    nc * 10000L + k_len * 1000L + nf * 100L - as.integer(abs(nf - mid) * 10)
  }

  msizes <- vapply(by_model[method_names], length, integer(1L))
  mord <- method_names[order(-msizes)]
  best <- list(combo = character(0), feats = character(0), score = -Inf)

  if (length(mord) >= 1L) {
    for (k in seq(length(mord), 1L)) {
      combos <- if (k == 1L) {
        lapply(mord, function(m) m)
      } else {
        utils::combn(mord, k, simplify = FALSE)
      }
      for (combo in combos) {
        raw <- .fsc07_features_for_method_combo(by_model, combo, order_vec)
        if (!length(raw)) next
        inter <- .fsc07_merge_forced_composites(
          raw, comp_tags, feats_cand, order_vec, fn_max, "resolve", force_comp, data_cols
        )
        nf <- length(inter)
        nc <- length(intersect(inter, comp_tags))
        valid <- (nf >= fn_min) && (nf <= fn_max) &&
          (!require_comp || nc >= min_comp)
        if (valid) {
          src <- if (k == 1L) "single_method" else "intersection"
          return(list(
            final = inter,
            selected_methods = combo,
            selection_source = src
          ))
        }
        sc <- .score(inter, k)
        if (sc > best$score) {
          best <- list(
            combo = combo,
            feats = inter,
            score = sc,
            source = if (k == 1L) "single_method" else "intersection"
          )
        }
      }
    }
  }

  if (length(best$feats) >= fn_min) {
    cli::cli_alert_warning(
      "无方法组合同时满足 {fn_min}–{fn_max} 个特征；采用次优 [{paste(best$combo, collapse = '+')}]（{length(best$feats)} 个）"
    )
    return(list(
      final = best$feats,
      selected_methods = best$combo,
      selection_source = best$source
    ))
  }

  if (length(best$combo)) {
    raw <- .fsc07_features_for_method_combo(by_model, best$combo, order_vec)
    if (length(raw) >= fn_min) {
      inter <- .fsc07_merge_forced_composites(
        raw, comp_tags, feats_cand, order_vec, fn_max, "resolve", force_comp, data_cols
      )
      cli::cli_alert_warning(
        "采用 [{paste(best$combo, collapse = '+')}] 全部入选特征（{length(inter)} 个，未达目标区间）"
      )
      return(list(
        final = inter,
        selected_methods = best$combo,
        selection_source = best$source
      ))
    }
  }

  if (isTRUE(fallback_uv)) {
    pool <- unique(as.character(uv_pool[nzchar(uv_pool)]))
    pool <- intersect(pool, data_cols)
    ar_uv <- .fsc07_enforce_single_anthropometric(pool, cfg, NULL, "univar_fallback")
    pool <- ar_uv$kept
    pool_ord <- intersect(order_vec, pool)
    if (length(pool_ord) >= fn_min) {
      final_uv <- .fsc07_merge_forced_composites(
        pool_ord, comp_tags, feats_cand, order_vec, fn_max, "univar_fallback", force_comp, data_cols
      )
      cli::cli_alert_warning(
        "多模型无法得到 ≥{fn_min} 个共识特征，回退为单因素显著变量（{length(final_uv)} 个，未用 VIF 候选）"
      )
      return(list(
        final = final_uv,
        selected_methods = character(0),
        selection_source = "univar_fallback"
      ))
    }
  }

  NULL
}

.fsc07_collect_meta_df <- function(ctx) {
  meta_raw <- ctx$results$feature_selection_meta
  if (!is.null(meta_raw) && length(meta_raw)) {
    if (is.data.frame(meta_raw)) return(meta_raw)
    if (is.list(meta_raw)) {
      return(tryCatch(
        dplyr::bind_rows(meta_raw, .id = "method"),
        error = function(e) data.frame()
      ))
    }
  }
  meta_list <- ctx$results$feature_selection_meta_list
  if (is.list(meta_list) && length(meta_list)) {
    return(tryCatch(
      dplyr::bind_rows(meta_list, .id = "method"),
      error = function(e) data.frame()
    ))
  }
  data.frame()
}

block_feature_selection_consensus <- function(ctx, ...) {
  suppressPackageStartupMessages(library(dplyr))
  cfg <- ctx$config
  bl_cfg <- cfg$feature_selection_consensus %||% cfg$feature_selection %||% list()

  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$feature_selection_consensus$enable=FALSE，跳过 feature_selection_consensus。")
    return(ctx)
  }

  resolved <- feature_selection_modeling_data(ctx)
  data <- resolved$data
  if (is.null(data) || !is.data.frame(data)) {
    if (.fsc07_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .fsc07_pause(
        ctx,
        "无数据，请先运行 imputation / data_clean",
        "在 pipeline 中先 source 插补或清洗块",
        NULL
      )
    }
    stop("feature_selection_consensus: 无数据。", call. = FALSE)
  }

  by_model_in <- ctx$results$feature_selection_by_model %||% list()
  if (!is.list(by_model_in) || !length(by_model_in)) {
    if (.fsc07_should_pause(bl_cfg, "pause_on_all_methods_empty", TRUE)) {
      .fsc07_pause(
        ctx,
        "ctx$results$feature_selection_by_model 为空",
        "请先运行 01–06 特征选择方法块（lasso/boruta/…）",
        utils::head(data, 5L)
      )
    }
    stop("feature_selection_consensus: feature_selection_by_model 为空。", call. = FALSE)
  }

  work <- ctx$results$feature_selection_work %||% list()
  feats <- as.character(work$feats %||% character(0))
  feats <- feats[nzchar(feats)]
  uv_cand <- as.character(work$uv_cand %||% character(0))
  uv_cand <- uv_cand[nzchar(uv_cand)]
  outcome_col <- as.character(work$outcome_col %||% "")[1L]
  study_type <- tolower(trimws(as.character(work$study_type %||% "")[1L]))
  fn_min <- suppressWarnings(as.integer(work$fn_min)[1L])
  fn_max <- suppressWarnings(as.integer(work$fn_max)[1L])

  if (!length(feats)) {
    feats <- unique(unlist(by_model_in, use.names = FALSE))
    feats <- feats[nzchar(feats)]
  }
  if (!length(uv_cand)) {
    uv_cand <- as.character(ctx$results$univar_features %||% character(0))
    uv_cand <- uv_cand[nzchar(uv_cand)]
  }
  if (is.na(outcome_col) || !nzchar(outcome_col)) {
    outcome_col <- cfg$data$outcome_column %||% "Disease"
    study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
    if (identical(study_type, "incidence")) {
      outcome_col <- as.character((cfg$incidence %||% list())$outcome_var %||% outcome_col)[1L]
    }
  }
  if (is.na(study_type) || !nzchar(study_type)) {
    study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  }
  if (is.na(fn_min) || is.na(fn_max)) {
    fn_min <- as.integer(bl_cfg$target_n_features_min)[1L]
    fn_max <- as.integer(bl_cfg$target_n_features_max)[1L]
  }
  if (is.na(fn_min) || is.na(fn_max)) {
    stop(
      "feature_selection_consensus: 请在 config 中设置 target_n_features_min / target_n_features_max。",
      call. = FALSE
    )
  }
  if (fn_min > fn_max || fn_min < 1L) {
    stop("feature_selection_consensus: target_n_features_min/max 配置无效。", call. = FALSE)
  }

  feats <- intersect(feats, names(data))
  comp_pool <- trimws(as.character(
    bl_cfg$composite_features %||% (cfg$prediction %||% list())$index_vars %||% character(0)
  ))
  comp_pool <- comp_pool[nzchar(comp_pool)]
  if (length(comp_pool)) {
    feats <- unique(c(feats, intersect(comp_pool, names(data))))
    uv_cand <- unique(c(uv_cand, intersect(comp_pool, names(data))))
  }
  if (!length(feats)) {
    feats <- intersect(unique(unlist(by_model_in, use.names = FALSE)), names(data))
  }

  up0 <- ctx$results$univar_pvalues
  up0_full <- NULL
  p_lookup_pool <- unique(c(feats, uv_cand))
  if (is.null(up0) || !length(up0)) {
    univar_p <- setNames(rep(NA_real_, length(p_lookup_pool)), trimws(as.character(p_lookup_pool)))
  } else {
    up0_full <- setNames(as.numeric(up0), trimws(names(up0)))
    univar_p <- setNames(rep(NA_real_, length(p_lookup_pool)), trimws(as.character(p_lookup_pool)))
    hit <- intersect(names(up0_full), names(univar_p))
    if (length(hit)) univar_p[hit] <- up0_full[hit]
  }

  .univar_p_get1 <- function(vec, nm) {
    if (is.null(vec) || !length(vec) || !nzchar(as.character(nm)[1L])) return(NA_real_)
    nm <- trimws(as.character(nm)[1L])
    nms <- names(vec)
    if (is.null(nms) || !length(nms)) return(NA_real_)
    if (nm %in% nms) return(suppressWarnings(as.numeric(vec[[nm]])))
    j <- match(nm, trimws(nms))
    if (!is.na(j)) return(suppressWarnings(as.numeric(vec[j])))
    NA_real_
  }
  .univar_p_lookup <- function(nm) {
    v <- .univar_p_get1(univar_p, nm)
    if (!is.na(v)) return(v)
    if (!is.null(up0_full) && length(up0_full)) .univar_p_get1(up0_full, nm) else NA_real_
  }

  by_model_all <- by_model_in
  nm_ok <- names(by_model_in)[vapply(by_model_in, length, integer(1L)) > 0L]
  if (length(nm_ok) < 1L) {
    if (.fsc07_should_pause(bl_cfg, "pause_on_all_methods_empty", TRUE)) {
      .fsc07_pause(
        ctx,
        "所有启用模型均未返回非空特征集",
        "检查 01–06 方法块依赖包、样本量，或放宽 rfe_sizes 等",
        utils::head(data, 5L)
      )
    }
    stop("feature_selection_consensus: 所有模型特征集均为空。", call. = FALSE)
  }
  by_model <- by_model_in[nm_ok]

  U <- unique(unlist(by_model, use.names = FALSE))
  vote <- vapply(U, function(f) {
    sum(vapply(by_model, function(s) f %in% s, logical(1L)))
  }, integer(1L))
  names(vote) <- U
  p_ord <- vapply(U, function(f) {
    pv <- .univar_p_lookup(f)
    if (is.na(pv)) 1 else suppressWarnings(as.numeric(pv))
  }, numeric(1L))
  U_sorted <- U[order(-vote[U], p_ord[U])]

  method_summary <- data.frame(
    method = names(by_model_all),
    n_selected = vapply(by_model_all, length, integer(1)),
    features = vapply(by_model_all, function(x) paste(x, collapse = ", "), character(1)),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(method_summary))) {
    cli::cli_alert_info(
      "{.field {method_summary$method[i]}} 选出 {.val {method_summary$n_selected[i]}} 个特征: {method_summary$features[i]}"
    )
  }

  method_names <- names(by_model)
  selected_methods <- method_names
  pm <- bl_cfg$prompt_final_methods
  if (is.null(pm)) {
    select_prompt <- interactive()
  } else {
    select_prompt <- isTRUE(pm)
  }
  if (length(method_names) >= 2L) {
    cfg_pick <- unique(intersect(
      trimws(as.character(bl_cfg$final_methods %||% character(0))),
      method_names
    ))
    if (length(cfg_pick)) selected_methods <- cfg_pick
    if (isTRUE(select_prompt) && !interactive() && !length(cfg_pick)) {
      if (.fsc07_should_pause(bl_cfg, "pause_on_final_methods_prompt", TRUE)) {
        .fsc07_pause(
          ctx,
          "需要选择最终方法（用于交集），但当前为非交互运行且未配置 final_methods",
          paste0(
            "请在 config$feature_selection_consensus$final_methods 中设置，例如: c(",
            paste(sprintf('"%s"', method_names), collapse = ", "),
            ")"
          ),
          method_summary
        )
      }
      stop("feature_selection_consensus: 非交互运行须配置 final_methods。", call. = FALSE)
    }
    if (isTRUE(select_prompt) && interactive()) {
      cli::cli_alert_info("选择哪些方法作为最终方法（用于取交集）")
      for (i in seq_along(method_names)) {
        cli::cli_alert_info("  [{i}] {method_names[i]}")
      }
      ans <- trimws(readline("请输入序号或方法名（逗号分隔，留空=全部）: "))
      if (nzchar(ans)) {
        toks <- trimws(unlist(strsplit(ans, "[,;，\\s]+")))
        toks <- toks[nzchar(toks)]
        pick <- character(0)
        for (tk in toks) {
          if (grepl("^[0-9]+$", tk)) {
            idx <- as.integer(tk)
            if (!is.na(idx) && idx >= 1L && idx <= length(method_names)) {
              pick <- c(pick, method_names[idx])
            }
          } else {
            j <- match(tolower(tk), tolower(method_names), nomatch = NA_integer_)
            if (!is.na(j)) pick <- c(pick, method_names[j])
          }
        }
        pick <- unique(intersect(pick, method_names))
        if (length(pick)) selected_methods <- pick
      }
    }
  }
  selected_methods <- unique(intersect(selected_methods, method_names))
  if (!length(selected_methods)) selected_methods <- method_names

  user_specified <- length(trimws(as.character(bl_cfg$final_methods %||% character(0)))) > 0L
  cfg_pick <- unique(intersect(
    trimws(as.character(bl_cfg$final_methods %||% character(0))),
    method_names
  ))
  search_methods <- if (user_specified && length(cfg_pick)) cfg_pick else method_names

  p_ord_uv <- vapply(uv_cand, .univar_p_lookup, numeric(1))
  uv_order <- uv_cand[order(p_ord_uv, na.last = TRUE)]

  res_sel <- .fsc07_resolve_final_selection(
    by_model, search_methods, U_sorted, uv_order, names(data), feats,
    fn_min, fn_max, bl_cfg, cfg
  )
  if (is.null(res_sel) || !length(res_sel$final)) {
    lasso_only <- as.character(ctx$results$feature_selection_by_model$lasso %||% character(0))
    lasso_only <- unique(lasso_only[nzchar(lasso_only)])
    if (length(lasso_only) >= fn_min && length(lasso_only) <= fn_max) {
      cli::cli_alert_warning(
        "feature_selection_consensus: 共识未达目标，回退使用 LASSO 入选的 {length(lasso_only)} 个特征（在 {fn_min}-{fn_max} 范围内）。"
      )
      res_sel <- list(
        final = lasso_only,
        selected_methods = "lasso",
        selection_source = "lasso_fallback"
      )
    } else if (length(lasso_only)) {
      cli::cli_alert_warning(
        "feature_selection_consensus: LASSO 仅 {length(lasso_only)} 个特征，不在目标 {fn_min}-{fn_max}，不回退。"
      )
    }
  }
  if (is.null(res_sel) || !length(res_sel$final)) {
    if (.fsc07_should_pause(bl_cfg, "pause_on_resolve_fail", TRUE)) {
      .fsc07_pause(
        ctx,
        paste0("无法从模型或单因素显著变量中得到 ≥ ", fn_min, " 个最终特征"),
        paste0(
          "放宽 target_n_features_min、检查 univar_features，或设置 final_methods / fallback_univar_if_no_consensus"
        ),
        method_summary
      )
    }
    stop("feature_selection_consensus: 无法解析最终特征集。", call. = FALSE)
  }

  selected_methods <- res_sel$selected_methods
  final <- res_sel$final
  selection_source <- res_sel$selection_source %||% "unknown"

  pred_cfg_fs <- cfg$prediction %||% list()
  comp_keep <- trimws(as.character(
    bl_cfg$composite_features %||% pred_cfg_fs$index_vars %||% character(0)
  ))
  comp_keep <- unique(comp_keep[nzchar(comp_keep)])
  comp_keep <- intersect(comp_keep, names(data))

  if (isTRUE(bl_cfg$force_composite_features %||% TRUE)) {
    final <- .fsc07_merge_forced_composites(
      final, comp_keep, feats, U_sorted, fn_max, "feature_selection_final", TRUE, names(data)
    )
  }

  ar_final <- .fsc07_enforce_single_anthropometric(final, cfg, ctx, "feature_selection_final")
  ctx <- ar_final$ctx
  final <- ar_final$kept

  if (isTRUE(bl_cfg$force_composite_features %||% TRUE)) {
    final <- .fsc07_merge_forced_composites(
      final, comp_keep, feats, U_sorted, fn_max, "feature_selection_final", TRUE, names(data)
    )
  }
  comp_in_final <- intersect(comp_keep, final)

  exp_req <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  exp_req <- exp_req[nzchar(exp_req)]
  exp_req <- intersect(exp_req, comp_keep)
  exp_req <- exp_req[exp_req %in% names(data)]
  if (length(exp_req) && !all(exp_req %in% final)) {
    stop(
      "COMPOSITE_NOT_IN_FEATURE_SELECTION: 暴露指标 ",
      paste(setdiff(exp_req, final), collapse = ", "),
      " 未纳入 feature_selection_final，本指标判为失败。",
      call. = FALSE
    )
  }
  if (length(comp_in_final)) {
    for (m in names(by_model)) {
      by_model[[m]] <- unique(c(by_model[[m]], comp_in_final))
    }
    U <- unique(unlist(by_model, use.names = FALSE))
  }

  src_msg <- switch(
    selection_source,
    intersection = paste0("方法交集 [", paste(selected_methods, collapse = "+"), "]"),
    single_method = paste0("单方法 [", paste(selected_methods, collapse = "+"), "]"),
    univar_fallback = "单因素显著（未用 VIF 候选）",
    paste0(selection_source)
  )
  cli::cli_alert_info("最终特征来源: {src_msg}")
  cli::cli_alert_success(
    "feature_selection_consensus 最终特征 {length(final)} 个（目标 {fn_min}–{fn_max}）: {paste(final, collapse = ', ')}"
  )
  ctx$results$feature_selection_selection_source <- selection_source

  ctx$results$Model2Factors <- final
  m1_keep <- intersect(as.character(ctx$results$Model1Factors %||% character(0)), final)
  if (length(m1_keep)) {
    ctx$results$Model1Factors <- m1_keep
  }

  vote_df <- data.frame(
    feature = U_sorted,
    vote_count = as.integer(vote[U_sorted]),
    univariate_p = vapply(U_sorted, function(f) {
      pv <- .univar_p_lookup(f)
      if (length(pv) != 1L || is.na(pv)) NA_real_ else round(as.numeric(pv), 4)
    }, numeric(1L)),
    in_final = U_sorted %in% final,
    stringsAsFactors = FALSE
  )
  vote_df$selected_methods <- paste(selected_methods, collapse = ", ")

  meta_df <- .fsc07_collect_meta_df(ctx)
  final_df <- data.frame(
    selection_source = selection_source,
    selected_methods = if (length(selected_methods)) {
      paste(selected_methods, collapse = ", ")
    } else {
      NA_character_
    },
    final_n = length(final),
    final_features = paste(final, collapse = ", "),
    stringsAsFactors = FALSE
  )

  title_sum <- "Feature selection: model-wise counts and consensus"
  fp_sum <- file.path(ctx$output_dir_tables, "Table_FeatureSelection_Summary.xlsx")
  export_sci_table(method_summary, fp_sum, title = paste0(title_sum, " (methods & features)"), sheet = "Methods")
  export_sci_table(vote_df, fp_sum, title = paste0(title_sum, " (votes)"), sheet = "Votes")
  export_sci_table(final_df, fp_sum, title = paste0(title_sum, " (final intersection)"), sheet = "Final")
  fp_meta <- file.path(ctx$output_dir_tables, "Table_FeatureSelection_ModelMeta.xlsx")
  if (nrow(meta_df)) {
    export_sci_table(meta_df, fp_meta, title = "Feature selection model metadata", sheet = "Meta")
  }

  overlap_methods <- bl_cfg$overlap_plot_methods %||% NULL
  if (!is.null(overlap_methods) && length(overlap_methods)) {
    overlap_methods <- unique(intersect(
      trimws(as.character(overlap_methods)),
      selected_methods
    ))
  }
  if (!length(overlap_methods)) {
    if (length(selected_methods) > 4L) {
      overlap_methods <- selected_methods[seq_len(4L)]
      cli::cli_alert_info(
        "韦恩输入: 最终方法 {length(selected_methods)} 个>4，默认仅展示前 4 个: {paste(overlap_methods, collapse = ', ')}。可用 overlap_plot_methods 指定。"
      )
    } else {
      overlap_methods <- selected_methods
    }
  }
  if (length(overlap_methods) > 4L) overlap_methods <- overlap_methods[seq_len(4L)]

  overlap_eligible <- identical(selection_source, "intersection") ||
    identical(selection_source, "single_method")
  if (overlap_eligible && identical(selection_source, "single_method")) {
    overlap_methods <- selected_methods[1L]
  }
  if (overlap_eligible && length(overlap_methods) >= 1L) {
    list_in <- .fsc07_venn_list_for_final(
      by_model, overlap_methods, final, U, comp_in_final
    )
  } else {
    list_in <- list()
  }
  list_in_full <- list_in
  n_sets <- length(list_in)
  if (overlap_eligible && n_sets < 2L && length(method_names) >= 2L) {
    overlap_methods <- method_names[seq_len(min(2L, length(method_names)))]
    list_in <- .fsc07_venn_list_for_final(
      by_model, overlap_methods, final, U, comp_in_final
    )
    n_sets <- length(list_in)
  }

  if (identical(selection_source, "univar_fallback")) {
    cli::cli_alert_info("单因素回退入选，韦恩图不可画（无多模型共识）")
  } else if (overlap_eligible && n_sets >= 2L) {
    venn_center_n <- length(Reduce(intersect, list_in))
    if (venn_center_n != length(final)) {
      stop(
        "feature_selection_consensus: 韦恩中心 (", venn_center_n, ") 与 final (",
        length(final), ") 不一致；请检查复合指标与各方法入选集。",
        call. = FALSE
      )
    }
  } else if (length(method_names) < 2L) {
    cli::cli_alert_warning("仅 1 个模型成功，韦恩图不可画")
  }

  ctx$results$feature_selection_venn_input <- list(
    by_model = by_model,
    by_model_all = by_model_all,
    final = final,
    selected_methods = selected_methods,
    selection_source = selection_source,
    comp_in_final = comp_in_final,
    U = U,
    overlap_eligible = overlap_eligible,
    method_names = method_names,
    overlap_methods = overlap_methods,
    list_in = list_in,
    list_in_full = list_in_full
  )

  ctx$results$feature_selection_by_model <- by_model
  ctx$results$feature_selection_final <- final
  ctx$results$ml_feature_names <- final
  ctx <- save_result(ctx, "Model2Factors", final, "Model2Factors.RData")
  writeLines(final, file.path(ctx$output_dir, "Model2Factors.txt"))
  ctx$results$feature_selection_vote_df <- vote_df
  ctx$results$feature_selection_meta <- meta_df
  ctx$results$feature_selection_methods_used <- names(by_model)
  ctx$results$feature_selection_methods_selected <- selected_methods
  ctx$results$feature_selection_method_summary <- method_summary

  ctx <- save_result(
    ctx, "feature_selection_final_export",
    data.frame(feature = final, stringsAsFactors = FALSE),
    "D08_FeatureSelection_Final.csv"
  )
  ctx$results$feature_selection_final <- final

  if (isTRUE(bl_cfg$persist_final_artifacts %||% TRUE)) {
    .fs_payload <- list(
      version = 1L,
      saved_at = Sys.time(),
      features = final,
      feature_selection_by_model = by_model,
      feature_selection_methods_used = names(by_model),
      feature_selection_methods_selected = selected_methods,
      feature_selection_method_summary = method_summary,
      feature_selection_vote_df = vote_df,
      feature_selection_meta = meta_df,
      feature_selection_venn_input = ctx$results$feature_selection_venn_input,
      selection_source = selection_source,
      outcome_column = outcome_col,
      study_type = study_type
    )
    data_dir <- file.path(ctx$output_dir, "Data")
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
    p_block <- file.path(data_dir, "feature_selection_final.rds")
    tryCatch({
      saveRDS(.fs_payload, p_block)
      cli::cli_alert_success("已保存特征 RDS: {.file {p_block}}")
    }, error = function(e) cli::cli_alert_warning("写入 block Data RDS 失败: {e$message}"))
    tryCatch({
      writeLines(final, file.path(data_dir, "feature_selection_final.txt"))
    }, error = function(e) invisible(NULL))
    root_out <- ctx$root_output_dir %||% ctx$output_dir
    p_root <- file.path(root_out, "feature_selection_final.rds")
    tryCatch({
      saveRDS(.fs_payload, p_root)
      cli::cli_alert_success("已保存特征 RDS（输出根，供下游 ml_models 自动探测）: {.file {p_root}}")
    }, error = function(e) cli::cli_alert_warning("写入输出根 RDS 失败: {e$message}"))
    if (isTRUE(bl_cfg$persist_to_checkpoints %||% TRUE)) {
      ck <- (cfg$checkpoint %||% list())$dir %||% "checkpoints"
      ck <- trimws(as.character(ck)[1L])
      ck_dir <- if (grepl("^(/|[A-Za-z]:[/\\\\])", ck)) ck else file.path(getwd(), ck)
      if (!dir.exists(ck_dir)) tryCatch(dir.create(ck_dir, recursive = TRUE), error = function(e) NULL)
      if (dir.exists(ck_dir)) {
        p_ck <- file.path(ck_dir, "feature_selection_final.rds")
        tryCatch({
          saveRDS(.fs_payload, p_ck)
          cli::cli_alert_success("已镜像 checkpoints: {.file {p_ck}}")
        }, error = function(e) cli::cli_alert_warning("写入 checkpoints 失败: {e$message}"))
      }
    }
  }

  cli::cli_alert_success(
    "feature_selection_consensus: 最终 {length(final)} 个特征（目标 {fn_min}–{fn_max}）；模型数 {length(by_model)}"
  )
  ctx
}

register_block(
  "feature_selection_consensus",
  block_feature_selection_consensus,
  "多模型特征选择共识（投票、最终特征、汇总表与 venn_input；无单方法与韦恩图）"
)
