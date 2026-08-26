###############################################################################
#  feature_selection_lvq — caret::train(method="lvq") + varImp 阈值/Top-N；Figure S2G。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # 由 pipeline 决定，块内不选源
#  require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）
#  require_ctx_results += univar_features（Model2 不足时交集/回退）
#  require_packages = caret
#
#  feature_selection_lvq = list(
#    enable                          = TRUE,
#    seed                            = NULL,   # NULL → splitting$seed → imputation$seed
#    target_n_features_min           = NULL,   # NULL → feature_selection_consensus 同键
#    target_n_features_max           = NULL,
#    lvq_importance_threshold        = 0.53,
#    lvq_top_n_fallback              = NULL,   # NULL → fn_max
#    anthropometric_single           = NULL,   # NULL → BMI/Weight/Height 最多 1 个
#    pause_enable                    = TRUE,
#    pause_on_no_data                = TRUE,
#    pause_on_insufficient_candidates = TRUE
#  ),
#
#  register_block: "feature_selection_lvq"
#  典型流水线: multicollinearity → 本块 → feature_selection_consensus
#  块内 bl_cfg <- cfg$feature_selection_lvq %||% cfg$feature_selection（legacy）
###############################################################################

.fslv06_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.fslv06_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "feature_selection_lvq",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_lvq — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.fslv06_anthropometric_single_cfg <- function(cfg, bl_cfg) {
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

.fslv06_enforce_single_anthropometric <- function(vars, cfg, bl_cfg, ctx = NULL, label = "feature_selection_lvq") {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  ar <- .fslv06_anthropometric_single_cfg(cfg, bl_cfg)
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

.fslv06_coerce_predictors_for_caret <- function(df, feat_cols) {
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

block_feature_selection_lvq <- function(ctx, ...) {
  suppressPackageStartupMessages(library(dplyr))
  cfg <- ctx$config
  bl_cfg <- cfg$feature_selection_lvq %||% cfg$feature_selection %||% list()
  cons_cfg <- cfg$feature_selection_consensus %||% list()

  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$feature_selection_lvq$enable=FALSE，跳过 feature_selection_lvq。")
    return(ctx)
  }

  resolved <- feature_selection_modeling_data(ctx)
  data <- resolved$data
  if (is.null(data) || !is.data.frame(data)) {
    if (.fslv06_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .fslv06_pause(
        ctx,
        "无数据，请先运行 imputation / data_clean",
        "在 pipeline 中先 source 插补或清洗块",
        NULL
      )
    }
    stop("feature_selection_lvq: 无数据。", call. = FALSE)
  }

  strip_ids <- intersect(
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    names(data)
  )
  if (length(strip_ids)) {
    data <- data[, setdiff(names(data), strip_ids), drop = FALSE]
    cli::cli_alert_info(
      "feature_selection_lvq: 已从建模用数据副本移除 ID 类列: {paste(strip_ids, collapse = ', ')}"
    )
  }

  m2_cand <- as.character(ctx$results$Model2Factors %||% character(0))
  m2_cand <- m2_cand[nzchar(m2_cand)]
  uv_cand <- as.character(ctx$results$univar_features %||% character(0))
  uv_cand <- uv_cand[nzchar(uv_cand)]

  cand0 <- if (length(m2_cand) >= 3L) {
    cli::cli_alert_info(
      "feature_selection_lvq: 候选特征使用 VIF 后 Model2Factors（{length(m2_cand)} 个）"
    )
    m2_cand
  } else if (length(m2_cand) >= 1L && length(uv_cand) >= 1L) {
    cli::cli_alert_warning(
      "feature_selection_lvq: Model2Factors 仅 {length(m2_cand)} 个，改用 单因素显著 ∩ Model2"
    )
    intersect(uv_cand, m2_cand)
  } else if (length(uv_cand) >= 3L) {
    cli::cli_alert_warning(
      "feature_selection_lvq: 无 VIF 后 Model2Factors，回退为 univar_features（请先跑 multicollinearity）"
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
    if (.fslv06_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fslv06_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_lvq: 特征选择候选特征不足。", call. = FALSE)
  }

  outcome_col <- resolved$outcome_col
  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (!outcome_col %in% names(data)) {
    stop(
      "feature_selection_lvq: 结局列 ", outcome_col,
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
      "feature_selection_lvq: 请在 config 中设置 target_n_features_min / target_n_features_max。",
      call. = FALSE
    )
  }
  if (fn_min > fn_max || fn_min < 1L) {
    stop("feature_selection_lvq: target_n_features_min/max 配置无效。", call. = FALSE)
  }

  never_pred <- pipeline_never_predictor_names(cfg)
  never_pred <- never_pred[nzchar(never_pred)]
  anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
  anthro_drop <- anthro_drop[nzchar(anthro_drop)]
  if (length(anthro_drop)) {
    cli::cli_alert_info(
      "feature_selection_lvq: 排除人体测量 VIF 剔除项: {paste(anthro_drop, collapse = ', ')}"
    )
  }
  cand <- setdiff(as.character(cand0), c(outcome_col, never_pred, anthro_drop))
  cand <- intersect(cand, names(data))
  ar_cand <- .fslv06_enforce_single_anthropometric(cand, cfg, bl_cfg, ctx, "feature_selection_lvq")
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
    if (.fslv06_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fslv06_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_lvq: 候选特征数量不足。", call. = FALSE)
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
    if (n < 20L) stop("feature_selection_lvq: 非缺失结局样本过少。", call. = FALSE)
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
    stop("feature_selection_lvq: 训练集 complete.cases 后行数过少。", call. = FALSE)
  }

  feats <- intersect(cand, names(d_tr))
  if (length(feats) < 3L) {
    stop("feature_selection_lvq: 训练集内可用候选特征过少。", call. = FALSE)
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

  sel <- character(0)
  m_lvq_plot <- NULL
  thr <- as.numeric(bl_cfg$lvq_importance_threshold %||% 0.53)[1L]

  if (!requireNamespace("caret", quietly = TRUE)) {
    cli::cli_alert_warning("feature_selection_lvq: 跳过 lvq（未安装 caret）")
  } else {
    tryCatch({
      d_lvq <- d_model
      d_lvq[, feats] <- .fslv06_coerce_predictors_for_caret(d_lvq[, feats, drop = FALSE], feats)
      tr_ctrl <- caret::trainControl(method = "cv", number = min(10L, nrow(d_lvq)))
      m_lvq <- caret::train(
        Group ~ .,
        data = d_lvq,
        method = "lvq",
        preProcess = "scale",
        trControl = tr_ctrl
      )
      imp <- caret::varImp(m_lvq, scale = FALSE)$importance
      m_lvq_plot <- m_lvq
      cls_nm <- analysis_grp
      if (!cls_nm %in% colnames(imp)) cls_nm <- colnames(imp)[ncol(imp)]
      keep <- rownames(imp)[imp[[cls_nm]] > thr]
      if (!length(keep)) {
        n_top <- as.integer(bl_cfg$lvq_top_n_fallback %||% fn_max)[1L]
        ord <- order(-imp[[cls_nm]])
        keep <- rownames(imp)[head(ord, min(n_top, nrow(imp)))]
      }
      sel <- intersect(keep, feats)
    }, error = function(e) {
      cli::cli_alert_warning("lvq 失败: {e$message}")
      sel <<- character(0)
    })
  }

  ctx$results$feature_selection_by_model[["lvq"]] <- sel
  ctx$results$feature_selection_meta[["lvq"]] <- data.frame(
    model = "lvq",
    family = NA_character_,
    lambda_min = NA_real_,
    lambda_multiplier = thr,
    n_selected = length(sel),
    stringsAsFactors = FALSE
  )

  if (!is.null(m_lvq_plot)) {
    ctx <- save_figure(ctx, "Figure S2G.LVQ.pdf", function() {
      if (requireNamespace("ggplot2", quietly = TRUE) &&
          requireNamespace("ggpubr", quietly = TRUE) &&
          requireNamespace("caret", quietly = TRUE)) {
        imp <- caret::varImp(m_lvq_plot, scale = FALSE)$importance
        cls_nm <- as.character(analysis_grp)[1L]
        if (!cls_nm %in% colnames(imp)) cls_nm <- colnames(imp)[ncol(imp)]
        gp <- ggplot2::ggplot(imp, ggplot2::aes(x = reorder(rownames(imp), .data[[cls_nm]]), y = .data[[cls_nm]])) +
          ggplot2::geom_col(fill = "#4d7cb5") +
          ggplot2::coord_flip() +
          ggplot2::theme_classic() +
          ggplot2::ylab("LVQ") + ggplot2::xlab("")
        print(gp)
      } else {
        print(plot(caret::varImp(m_lvq_plot, scale = FALSE), main = "LVQ Variable Importance"))
      }
    }, width = 8, height = 8)
  }

  cli::cli_alert_success(
    "feature_selection_lvq: 入选 {length(sel)} 个特征"
  )
  ctx
}

register_block(
  "feature_selection_lvq",
  block_feature_selection_lvq,
  "caret LVQ + varImp 阈值/Top-N（Figure S2G）"
)
