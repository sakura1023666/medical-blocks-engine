###############################################################################
#  feature_selection_bagged_trees — caret::rfe + treebagFuncs；Figure S2F。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # 由 pipeline 决定，块内不选源
#  require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）
#  require_ctx_results += univar_features（Model2 不足时交集/回退）
#  require_packages = caret, ipred
#
#  feature_selection_bagged_trees = list(
#    enable                          = TRUE,
#    seed                            = NULL,   # NULL → splitting$seed → imputation$seed
#    target_n_features_min           = NULL,   # NULL → feature_selection_consensus 同键
#    target_n_features_max           = NULL,
#    rfe_sizes                       = NULL,   # NULL → 按 fn_min/max 与 p 自动网格
#    rfe_tolerance                   = 2,      # pickSizeTolerance 容差（%）
#    rfe_cv_number                   = 10L,
#    anthropometric_single           = NULL,   # NULL → BMI/Weight/Height 最多 1 个
#    pause_enable                    = TRUE,
#    pause_on_insufficient_candidates = TRUE
#  ),
#
#  register_block: "feature_selection_bagged_trees"
#  典型流水线: multicollinearity → 本块 → feature_selection_consensus
#  块内 bl_cfg <- cfg$feature_selection_bagged_trees %||% cfg$feature_selection（legacy）
###############################################################################

.fsbt05_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.fsbt05_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "feature_selection_bagged_trees",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_bagged_trees — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.fsbt05_anthropometric_single_cfg <- function(cfg, bl_cfg) {
  ar <- bl_cfg$anthropometric_single
  if (!is.null(ar)) return(ar)
  fs <- cfg$feature_selection %||% list()
  fs$anthropometric_single %||% list(
    enable = TRUE,
    vars = c("BMI", "Weight", "Height"),
    max_coexistent = 1L,
    prefer_keep_one_order = c("BMI", "Weight", "Height")
  )
}

.fsbt05_enforce_single_anthropometric <- function(vars, cfg, bl_cfg, ctx = NULL, label = "feature_selection_bagged_trees") {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  ar <- .fsbt05_anthropometric_single_cfg(cfg, bl_cfg)
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

.fsbt05_coerce_predictors_for_caret <- function(df, feat_cols) {
  for (cn in feat_cols) {
    if (!cn %in% names(df)) next
    v <- df[[cn]]
    if (is.character(v)) {
      vn <- suppressWarnings(as.numeric(v))
      if (sum(!is.na(vn)) >= max(5L, floor(0.5 * length(vn)))) {
        df[[cn]] <- vn
      } else {
        df[[cn]] <- factor(v)
      }
    } else if (is.logical(v)) {
      df[[cn]] <- as.integer(v)
    }
  }
  df
}

.fsbt05_rfe_run <- function(tag, fn_list, d_model, feats, rfe_sizes, rfe_number, rfe_tolerance) {
  if (!requireNamespace("caret", quietly = TRUE)) {
    cli::cli_alert_warning("跳过 {tag}：未安装 caret")
    return(list(features = character(0), fit = NULL))
  }
  tryCatch({
    dff <- d_model[, feats, drop = FALSE]
    dff <- .fsbt05_coerce_predictors_for_caret(dff, feats)
    fn_list2 <- fn_list
    fn_list2$selectSize <- function(x, metric, tol = rfe_tolerance, maximize = TRUE) {
      caret::pickSizeTolerance(x, metric, tol = tol, maximize = maximize)
    }
    ctrl <- caret::rfeControl(
      functions = fn_list2,
      method = "cv",
      number = max(2L, min(rfe_number, nrow(dff))),
      verbose = FALSE
    )
    sz <- rfe_sizes[rfe_sizes <= ncol(dff)]
    if (!length(sz)) sz <- ncol(dff)
    out <- caret::rfe(
      x = dff,
      y = d_model$Group,
      sizes = unique(sort(sz)),
      rfeControl = ctrl
    )
    list(features = intersect(caret::predictors(out), feats), fit = out)
  }, error = function(e) {
    cli::cli_alert_warning("{tag} 失败: {e$message}")
    list(features = character(0), fit = NULL)
  })
}

block_feature_selection_bagged_trees <- function(ctx, ...) {
  suppressPackageStartupMessages(library(dplyr))
  cfg <- ctx$config
  bl_cfg <- cfg$feature_selection_bagged_trees %||% cfg$feature_selection %||% list()
  cons_cfg <- cfg$feature_selection_consensus %||% list()

  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$feature_selection_bagged_trees$enable=FALSE，跳过 feature_selection_bagged_trees。")
    return(ctx)
  }

  resolved <- feature_selection_modeling_data(ctx)
  data <- resolved$data
  if (is.null(data) || !is.data.frame(data)) {
    if (.fsbt05_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .fsbt05_pause(
        ctx,
        "无数据，请先运行 imputation / data_clean",
        "在 pipeline 中先 source 插补或清洗块",
        NULL
      )
    }
    stop("feature_selection_bagged_trees: 无数据。", call. = FALSE)
  }

  strip_ids <- intersect(
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    names(data)
  )
  if (length(strip_ids)) {
    data <- data[, setdiff(names(data), strip_ids), drop = FALSE]
    cli::cli_alert_info(
      "feature_selection_bagged_trees: 已从建模用数据副本移除 ID 类列: {paste(strip_ids, collapse = ', ')}"
    )
  }

  m2_cand <- as.character(ctx$results$Model2Factors %||% character(0))
  m2_cand <- m2_cand[nzchar(m2_cand)]
  uv_cand <- as.character(ctx$results$univar_features %||% character(0))
  uv_cand <- uv_cand[nzchar(uv_cand)]

  cand0 <- if (length(m2_cand) >= 3L) {
    cli::cli_alert_info(
      "feature_selection_bagged_trees: 候选特征使用 VIF 后 Model2Factors（{length(m2_cand)} 个）"
    )
    m2_cand
  } else if (length(m2_cand) >= 1L && length(uv_cand) >= 1L) {
    cli::cli_alert_warning(
      "feature_selection_bagged_trees: Model2Factors 仅 {length(m2_cand)} 个，改用 单因素显著 ∩ Model2"
    )
    intersect(uv_cand, m2_cand)
  } else if (length(uv_cand) >= 3L) {
    cli::cli_alert_warning(
      "feature_selection_bagged_trees: 无 VIF 后 Model2Factors，回退为 univar_features（请先跑 multicollinearity）"
    )
    uv_cand
  } else {
    character(0)
  }
  cand0 <- unique(cand0[nzchar(cand0)])

  if (length(cand0) < 3L) {
    snap <- utils::head(data, 5L)
    reason <- paste0(
      "特征选择候选仅 ", length(cand0),
      " 个（需 Model2Factors≥3、或 m2∩uv、或 univar_features≥3）"
    )
    suggestion <- "先跑 multicollinearity，或检查 p_threshold / VIF 阈值是否过严"
    if (.fsbt05_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fsbt05_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_bagged_trees: 特征选择候选特征不足。", call. = FALSE)
  }

  outcome_col <- resolved$outcome_col
  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (!outcome_col %in% names(data)) {
    stop(
      "feature_selection_bagged_trees: 结局列 ", outcome_col,
      " 不在数据中（发病请检查 incidence$outcome_var）。",
      call. = FALSE
    )
  }
  analysis_grp <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  reference_grp <- cfg$project$reference_group %||% "Control"
  sp <- cfg$splitting %||% list()
  train_ratio <- as.numeric(sp$train_ratio %||% 0.7)[1L]
  stratify <- isTRUE(sp$stratify %||% TRUE)
  feat_seed <- as.integer(
    bl_cfg$seed %||% sp$seed %||% cfg$imputation$seed %||% 1234L
  )[1L]
  set.seed(feat_seed)

  fn_min <- as.integer(bl_cfg$target_n_features_min)[1L]
  fn_max <- as.integer(bl_cfg$target_n_features_max)[1L]
  if (is.na(fn_min) || is.na(fn_max)) {
    fn_min <- as.integer(cons_cfg$target_n_features_min)[1L]
    fn_max <- as.integer(cons_cfg$target_n_features_max)[1L]
  }
  if (is.na(fn_min) || is.na(fn_max)) {
    fn_min <- as.integer((cfg$feature_selection %||% list())$target_n_features_min)[1L]
    fn_max <- as.integer((cfg$feature_selection %||% list())$target_n_features_max)[1L]
  }
  if (is.na(fn_min) || is.na(fn_max)) {
    stop(
      "feature_selection_bagged_trees: 请在 config 中设置 target_n_features_min / target_n_features_max。",
      call. = FALSE
    )
  }
  if (fn_min > fn_max || fn_min < 1L) {
    stop("feature_selection_bagged_trees: target_n_features_min/max 配置无效。", call. = FALSE)
  }

  never_pred <- pipeline_never_predictor_names(cfg)
  never_pred <- never_pred[nzchar(never_pred)]
  anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
  anthro_drop <- anthro_drop[nzchar(anthro_drop)]
  if (length(anthro_drop)) {
    cli::cli_alert_info(
      "feature_selection_bagged_trees: 排除人体测量 VIF 剔除项: {paste(anthro_drop, collapse = ', ')}"
    )
  }
  cand <- setdiff(as.character(cand0), c(outcome_col, never_pred, anthro_drop))
  cand <- intersect(cand, names(data))
  ar_cand <- .fsbt05_enforce_single_anthropometric(cand, cfg, bl_cfg, ctx, "feature_selection_bagged_trees")
  ctx <- ar_cand$ctx
  cand <- ar_cand$kept
  if (length(cand) < fn_min) {
    snap <- utils::head(
      data[, unique(c(outcome_col, head(cand, 5L))), drop = FALSE],
      5L
    )
    reason <- paste0(
      "候选特征仅 ", length(cand), " 个，低于目标下限 ", fn_min
    )
    suggestion <- "放宽对应 config$univariate_*$sig_cutoff 或检查列名映射"
    if (.fsbt05_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fsbt05_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_bagged_trees: 候选特征数量不足。", call. = FALSE)
  }

  .y_bin <- function(dat) {
    x <- dat[[outcome_col]]
    if (is.numeric(x) && all(stats::na.omit(unique(as.numeric(x))) %in% c(0, 1))) {
      return(as.integer(as.numeric(x)))
    }
    xc <- trimws(as.character(x))
    y <- rep(NA_integer_, length(xc))
    y[!is.na(xc) & xc == trimws(as.character(analysis_grp))] <- 1L
    y[!is.na(xc) & xc != trimws(as.character(analysis_grp))] <- 0L
    y
  }

  .train_idx <- function(dat, y01) {
    ok <- !is.na(y01)
    n <- sum(ok)
    if (n < 20L) stop("feature_selection_bagged_trees: 非缺失结局样本过少。", call. = FALSE)
    idx <- which(ok)
    if (stratify) {
      yv <- y01[idx]
      i1 <- idx[yv == 1L]
      i0 <- idx[yv == 0L]
      n1 <- max(1L, floor(length(i1) * train_ratio))
      n0 <- max(1L, floor(length(i0) * train_ratio))
      c(sample(i1, n1), sample(i0, n0))
    } else {
      sample(idx, max(1L, floor(n * train_ratio)))
    }
  }

  cols_use <- unique(c(outcome_col, cand))
  d0 <- data[, cols_use, drop = FALSE]
  y01 <- .y_bin(d0)
  tr <- feature_selection_row_index_for_fit(d0, y01, cfg, resolved)
  d_tr <- d0[tr, , drop = FALSE]
  d_tr <- d_tr[stats::complete.cases(d_tr), , drop = FALSE]
  if (nrow(d_tr) < 20L) {
    stop("feature_selection_bagged_trees: 训练集 complete.cases 后行数过少。", call. = FALSE)
  }

  feats <- intersect(cand, names(d_tr))
  if (length(feats) < 3L) {
    stop("feature_selection_bagged_trees: 训练集内可用候选特征过少。", call. = FALSE)
  }

  y_train <- .y_bin(d_tr)
  d_model <- d_tr[, c(outcome_col, feats), drop = FALSE]
  names(d_model)[1L] <- "Group"
  d_model$Group <- factor(
    ifelse(y_train == 1L, as.character(analysis_grp), as.character(reference_grp)),
    levels = c(as.character(reference_grp), as.character(analysis_grp))
  )

  ctx$results$feature_selection_work <- list(
    feats = feats,
    uv_cand = uv_cand,
    outcome_col = outcome_col,
    study_type = study_type,
    fn_min = fn_min,
    fn_max = fn_max,
    analysis_grp = analysis_grp,
    reference_grp = reference_grp,
    tr = tr
  )

  if (is.null(ctx$results$feature_selection_by_model)) {
    ctx$results$feature_selection_by_model <- list()
  }
  if (is.null(ctx$results$feature_selection_meta)) {
    ctx$results$feature_selection_meta <- list()
  }

  rfe_number <- as.integer(bl_cfg$rfe_cv_number %||% 10L)[1L]
  rfe_tolerance <- as.numeric(bl_cfg$rfe_tolerance %||% 2)[1L]
  if (!is.finite(rfe_tolerance) || rfe_tolerance < 0) rfe_tolerance <- 2
  rfe_sizes <- bl_cfg$rfe_sizes
  if (is.null(rfe_sizes)) {
    p0 <- length(feats)
    rfe_sizes <- unique(sort(pmin(p0, c(
      seq(fn_min, min(fn_max, p0), by = 1L),
      max(2L, min(p0, 6L)), p0
    ))))
  }

  sel <- character(0)
  fit_tb <- NULL
  if (requireNamespace("ipred", quietly = TRUE)) {
    z <- .fsbt05_rfe_run(
      "bagged_trees", caret::treebagFuncs, d_model, feats,
      rfe_sizes, rfe_number, rfe_tolerance
    )
    sel <- z$features %||% character(0)
    fit_tb <- z$fit
  } else {
    cli::cli_alert_warning("跳过 bagged_trees：请安装 ipred")
  }

  ctx$results$feature_selection_by_model[["bagged_trees"]] <- sel
  ctx$results$feature_selection_meta[["bagged_trees"]] <- data.frame(
    model = "bagged_trees",
    family = NA_character_,
    lambda_min = NA_real_,
    lambda_multiplier = NA_real_,
    n_selected = length(sel),
    stringsAsFactors = FALSE
  )

  if (!is.null(fit_tb)) {
    ctx <- save_figure(ctx, "Figure S2F.Bagged trees.pdf", function() {
      print(plot(fit_tb, type = c("o"), xlab = "Treebag"))
    }, width = 4, height = 4)
  }

  cli::cli_alert_success(
    "feature_selection_bagged_trees: 入选 {length(sel)} 个特征"
  )
  ctx
}

register_block(
  "feature_selection_bagged_trees",
  block_feature_selection_bagged_trees,
  "caret RFE 装袋树（treebagFuncs，Figure S2F）"
)
