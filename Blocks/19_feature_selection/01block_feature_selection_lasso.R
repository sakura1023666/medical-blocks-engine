###############################################################################
#  feature_selection_lasso — 重复 cv.glmnet LASSO + 频次筛选；Figure S2A / S2B。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # 由 pipeline 决定，块内不选源
#  require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）
#  require_ctx_results += univar_features（Model2 不足时交集/回退）
#  require_packages = glmnet（Cox 路径另需 survival）
#
#  feature_selection_lasso = list(
#    enable                          = TRUE,
#    seed                            = NULL,   # NULL → splitting$seed → imputation$seed
#    target_n_features_min           = NULL,   # NULL → feature_selection_consensus 同键
#    target_n_features_max           = NULL,
#    cv_folds                        = 10L,
#    lasso_cv_times                  = 1000L,
#    lasso_lambda_adjust_mult        = 1,
#    lasso_freq_cutoff_frac          = 0.9,
#    lasso_frequency_cutoff_n        = NULL,
#    lasso_lambda_adjust_search_n    = 60L,
#    lasso_top_n_fallback            = NULL,
#    lasso_use_cox                   = TRUE,   # prognosis 且存在 time/event 列时用 Cox
#    auto_lasso_params               = TRUE,
#    lasso_bootstrap                 = TRUE,
#    lasso_subsample_frac            = 0.8,
#    glmnet_maxit                    = 20000L,
#    lasso_fig3a_engine              = "base", # 或 "complexheatmap"
#    lasso_fig3a_top_patterns        = 6L,
#    anthropometric_single           = NULL,   # NULL → BMI/Weight/Height 最多 1 个
#    pause_enable                    = TRUE,
#    pause_on_insufficient_candidates = TRUE
#  ),
#
#  register_block: "feature_selection_lasso"
#  典型流水线: multicollinearity → 本块 → feature_selection_consensus
#  块内 bl_cfg <- cfg$feature_selection_lasso %||% cfg$feature_selection（legacy）
###############################################################################

.fsl01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.fsl01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "feature_selection_lasso",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_lasso — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.fsl01_anthropometric_single_cfg <- function(cfg, bl_cfg) {
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

.fsl01_enforce_single_anthropometric <- function(vars, cfg, bl_cfg, ctx = NULL, label = "feature_selection_lasso") {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  ar <- .fsl01_anthropometric_single_cfg(cfg, bl_cfg)
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

feature_selection_resolve_lasso_candidates <- function(ctx, bl_cfg = list()) {
  m2_cand <- unique(as.character(ctx$results$Model2Factors %||% character(0)))
  m2_cand <- m2_cand[nzchar(m2_cand)]
  uv_cand <- unique(as.character(ctx$results$univar_features %||% character(0)))
  uv_cand <- uv_cand[nzchar(uv_cand)]
  source <- tolower(trimws(as.character(bl_cfg$candidate_source %||% "auto")[1L]))

  if (identical(source, "univariate")) return(uv_cand)
  ## Table1 全变量：连续 + 分类（及 table1_var_order），供「仅 LASSO」入模；UV/VIF 只作关联协变量
  if (source %in% c("table1", "all", "baseline", "table_1")) {
    t1 <- unique(c(
      as.character(ctx$results$table1_var_order %||% character(0)),
      as.character(ctx$results$continuous_vars %||% character(0)),
      as.character(ctx$results$categorical_vars %||% character(0))
    ))
    t1 <- t1[nzchar(t1)]
    if (length(t1)) return(t1)
    ## baseline 尚未落盘时回退数值列（仍排除结局/ID）
    data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$train
    if (is.data.frame(data) && ncol(data) > 0L) {
      cfg <- ctx$config %||% list()
      drop <- unique(c(
        as.character((cfg$data %||% list())$outcome_column %||% character(0)),
        as.character((cfg$data %||% list())$id_column %||% character(0)),
        as.character((cfg$incidence %||% list())$outcome_var %||% character(0)),
        "Group", "SEQN", "ID"
      ))
      num <- names(data)[vapply(data, is.numeric, logical(1L))]
      return(setdiff(num, drop))
    }
    return(character(0))
  }
  if (length(m2_cand) >= 3L) return(m2_cand)
  if (length(m2_cand) >= 1L && length(uv_cand) >= 1L) {
    return(intersect(uv_cand, m2_cand))
  }
  if (length(uv_cand) >= 3L) return(uv_cand)
  character(0)
}

#' Figure S2B（LASSO 模型路径）：热图（白/黄）+ 条形图（频次）；默认 base 图形（PDF 最稳）。
.fsl01_fig3a_lasso_model_plot <- function(cv_list_plot, fig3a_engine = NULL, fig3a_top_patterns = 6L) {
  if (!length(cv_list_plot)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "LASSO results empty")
    return(invisible())
  }

  gModel.sum <- vapply(cv_list_plot, function(x) {
    if (is.null(x)) return("")
    if (length(x) == 1L && identical(x, "isNA")) return("isNA")
    if (!length(x)) return("isNA")
    paste0(x, collapse = " ")
  }, character(1L))
  gModel.sum[nchar(gModel.sum) == 0L] <- "isNA"

  gModel_tbl <- sort(table(gModel.sum), decreasing = TRUE)
  yyy <- names(gModel_tbl)
  yyy <- yyy[nzchar(yyy)]
  if (!length(yyy)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "LASSO patterns empty")
    return(invisible())
  }
  top_n <- suppressWarnings(as.integer(fig3a_top_patterns)[1L])
  if (!is.na(top_n) && top_n > 0L && length(yyy) > top_n) {
    yyy <- yyy[seq_len(top_n)]
  }

  all_genes <- setdiff(unique(unlist(cv_list_plot, use.names = FALSE)), "isNA")
  if (!length(all_genes)) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "LASSO: no non-NA features across iterations")
    return(invisible())
  }

  yyy.df <- matrix(FALSE, nrow = length(yyy), ncol = length(all_genes),
                   dimnames = list(NULL, all_genes))
  rNames_yyyDf <- character(length(yyy))
  for (i in seq_along(yyy)) {
    gm <- strsplit(yyy[i], " ", fixed = TRUE)[[1L]]
    gm_count <- length(gm)
    yyy.df[i, ] <- FALSE
    if (gm_count > 0L) {
      for (j in seq_len(ncol(yyy.df))) {
        if (colnames(yyy.df)[j] %in% gm) yyy.df[i, j] <- TRUE
      }
    }
    rNames_yyyDf[i] <- paste0(gm_count, " Factors")
  }
  for (i in seq.int(2L, length(rNames_yyyDf))) {
    if (rNames_yyyDf[i] %in% rNames_yyyDf[seq_len(i - 1L)]) {
      rNames_yyyDf[i] <- paste0(rNames_yyyDf[i], "*")
    }
  }
  rNames_yyyDf <- make.unique(rNames_yyyDf, sep = "_")

  yyy.df <- yyy.df[, order(colnames(yyy.df)), drop = FALSE]
  # 图中变量展示名：下去下划线，避免与 times 面板标签挤在一起
  colnames(yyy.df) <- gsub("_", " ", colnames(yyy.df), fixed = TRUE)
  y.df <- apply(yyy.df, 2, as.numeric)
  if (!is.matrix(y.df)) {
    y.df <- matrix(y.df, nrow = nrow(yyy.df), ncol = ncol(yyy.df),
                   dimnames = dimnames(yyy.df))
  }
  rownames(y.df) <- rNames_yyyDf

  gModel_Count <- as.matrix(gModel_tbl[yyy])
  # 右侧面板只用数值标注，左侧行名不写 "N times"，避免与热图重叠
  rownames(gModel_Count) <- as.character(gModel_Count[, 1L])

  engine <- tolower(trimws(as.character(fig3a_engine %||% "base"))[1L])
  if (!nzchar(engine) || is.na(engine)) engine <- "base"

  .draw_base_panels <- function() {
    ng <- ncol(y.df)
    nr <- nrow(y.df)
    bmar <- max(6, min(14, 4 + ng * 0.09))
    op <- graphics::par(no.readonly = TRUE)
    on.exit(graphics::par(op), add = TRUE)
    graphics::layout(matrix(1:2, nrow = 1L), widths = c(2.0, 1.35))
    graphics::par(mar = c(bmar, 7, 3, 0.5))
    val_mat <- y.df[nr:1L, , drop = FALSE]
    graphics::plot.new()
    graphics::plot.window(
      xlim = c(0.5, ng + 0.5),
      ylim = c(0.5, nr + 0.5),
      xaxs = "i", yaxs = "i"
    )
    for (iy in seq_len(nr)) {
      for (ix in seq_len(ng)) {
        fill_col <- if (as.numeric(val_mat[iy, ix]) > 0) "yellow" else "white"
        graphics::rect(
          ix - 0.5, iy - 0.5, ix + 0.5, iy + 0.5,
          col = fill_col, border = "grey72", lwd = 0.6
        )
      }
    }
    graphics::title(main = "LASSO model patterns")
    cxa <- if (ng > 60) 0.28 else if (ng > 35) 0.4 else 0.55
    graphics::axis(1, at = seq_len(ng), labels = colnames(y.df), las = 2, cex.axis = cxa)
    graphics::axis(2, at = seq_len(nr), labels = rownames(y.df)[nr:1], las = 2, cex.axis = 0.72)
    graphics::box()
    graphics::par(mar = c(bmar, 1.2, 3, 5.5))
    cnt <- as.numeric(gModel_Count[, 1L])
    bp <- graphics::barplot(
      cnt,
      horiz = TRUE,
      las = 1,
      col = "#e56b6f",
      main = "Pattern count",
      names.arg = rep("", length(cnt)),
      xlim = c(0, max(cnt, 1) * 1.35),
      cex.names = 0.72
    )
    # times 标签放在柱右侧，避免与左侧热图重叠
    graphics::text(
      x = cnt + max(cnt, 1) * 0.03,
      y = bp,
      labels = paste0(cnt, " times"),
      adj = 0,
      cex = 0.72,
      xpd = TRUE
    )
  }

  if (identical(engine, "complexheatmap") &&
      requireNamespace("ComplexHeatmap", quietly = TRUE) &&
      requireNamespace("grid", quietly = TRUE)) {
    hp1 <- ComplexHeatmap::Heatmap(
      y.df,
      col = c("white", "yellow"),
      cluster_rows = FALSE,
      cluster_columns = FALSE,
      rect_gp = grid::gpar(col = "grey", lty = 1, lwd = 2),
      row_names_side = "left",
      show_heatmap_legend = FALSE
    )
    cnt_lab <- paste0(as.character(gModel_Count[, 1L]), " times")
    rownames(gModel_Count) <- cnt_lab
    hp2 <- ComplexHeatmap::Heatmap(
      gModel_Count,
      col = c("pink", "red"),
      cluster_rows = FALSE,
      cluster_columns = FALSE,
      row_names_side = "right",
      show_column_names = FALSE,
      show_heatmap_legend = FALSE,
      width = grid::unit(18, "mm")
    )
    ok_cm <- tryCatch(
      {
        grid::grid.newpage()
        ComplexHeatmap::draw(
          hp1 + hp2,
          newpage = FALSE,
          padding = grid::unit(c(2, 12, 2, 2), "mm")
        )
        TRUE
      },
      error = function(e) FALSE
    )
    if (isTRUE(ok_cm)) return(invisible())
  }

  .draw_base_panels()
  invisible()
}

block_feature_selection_lasso <- function(ctx, ...) {
  suppressPackageStartupMessages(library(dplyr))
  cfg <- ctx$config
  bl_cfg <- cfg$feature_selection_lasso %||% cfg$feature_selection %||% list()
  cons_cfg <- cfg$feature_selection_consensus %||% list()

  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$feature_selection_lasso$enable=FALSE，跳过 feature_selection_lasso。")
    return(ctx)
  }

  resolved <- feature_selection_modeling_data(ctx)
  data <- resolved$data
  if (is.null(data) || !is.data.frame(data)) {
    if (.fsl01_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .fsl01_pause(
        ctx,
        "无数据，请先运行 imputation / data_clean",
        "在 pipeline 中先 source 插补或清洗块",
        NULL
      )
    }
    stop("feature_selection_lasso: 无数据。", call. = FALSE)
  }

  strip_ids <- intersect(
    as.character((cfg$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    names(data)
  )
  if (length(strip_ids)) {
    data <- data[, setdiff(names(data), strip_ids), drop = FALSE]
    cli::cli_alert_info(
      "feature_selection_lasso: 已从建模用数据副本移除 ID 类列: {paste(strip_ids, collapse = ', ')}"
    )
  }

  m2_cand <- as.character(ctx$results$Model2Factors %||% character(0))
  m2_cand <- m2_cand[nzchar(m2_cand)]
  uv_cand <- as.character(ctx$results$univar_features %||% character(0))
  uv_cand <- uv_cand[nzchar(uv_cand)]

  candidate_source <- tolower(trimws(as.character(bl_cfg$candidate_source %||% "auto")[1L]))
  cand0 <- feature_selection_resolve_lasso_candidates(ctx, bl_cfg)
  if (identical(candidate_source, "univariate")) {
    cli::cli_alert_info(
      "feature_selection_lasso: 严格使用单因素候选（{length(cand0)} 个）"
    )
  } else if (candidate_source %in% c("table1", "all", "baseline", "table_1")) {
    cli::cli_alert_info(
      "feature_selection_lasso: 候选特征使用 Table1 全变量（{length(cand0)} 个；UV/VIF 不限 ML）"
    )
  } else if (length(m2_cand) >= 3L) {
    cli::cli_alert_info(
      "feature_selection_lasso: 候选特征使用 VIF 后 Model2Factors（{length(m2_cand)} 个）"
    )
  } else if (length(m2_cand) >= 1L && length(uv_cand) >= 1L) {
    cli::cli_alert_warning(
      "feature_selection_lasso: Model2Factors 仅 {length(m2_cand)} 个，改用 单因素显著 ∩ Model2"
    )
  } else if (length(uv_cand) >= 3L) {
    cli::cli_alert_warning(
      "feature_selection_lasso: 无 VIF 后 Model2Factors，回退为 univar_features（请先跑 multicollinearity）"
    )
  }
  cand0 <- unique(cand0[nzchar(cand0)])

  min_cand <- if (candidate_source %in% c("univariate", "table1", "all", "baseline", "table_1")) {
    1L
  } else {
    3L
  }
  if (length(cand0) < min_cand) {
    snap <- utils::head(data, 5L)
    reason <- paste0(
      "特征选择候选仅 ", length(cand0),
      " 个（candidate_source=", candidate_source, "，需 ≥", min_cand, "）"
    )
    suggestion <- "检查上一层筛选是否过严（单因素 P 阈值）"
    if (.fsl01_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fsl01_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_lasso: 特征选择候选特征不足。", call. = FALSE)
  }

  outcome_col <- resolved$outcome_col
  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  if (!outcome_col %in% names(data)) {
    stop(
      "feature_selection_lasso: 结局列 ", outcome_col,
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
      "feature_selection_lasso: 请在 config 中设置 target_n_features_min / target_n_features_max。",
      call. = FALSE
    )
  }
  if (fn_min > fn_max || fn_min < 1L) {
    stop("feature_selection_lasso: target_n_features_min/max 配置无效。", call. = FALSE)
  }

  never_pred <- pipeline_never_predictor_names(cfg)
  never_pred <- never_pred[nzchar(never_pred)]
  anthro_drop <- as.character(ctx$results$anthropometric_dropped_vars %||% character(0))
  anthro_drop <- anthro_drop[nzchar(anthro_drop)]
  if (length(anthro_drop)) {
    cli::cli_alert_info(
      "feature_selection_lasso: 排除人体测量 VIF 剔除项: {paste(anthro_drop, collapse = ', ')}"
    )
  }
  cand <- setdiff(as.character(cand0), c(outcome_col, never_pred, anthro_drop))
  cand <- intersect(cand, names(data))
  ar_cand <- .fsl01_enforce_single_anthropometric(cand, cfg, bl_cfg, ctx, "feature_selection_lasso")
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
    if (.fsl01_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fsl01_pause(ctx, reason, suggestion, snap)
    }
    stop("feature_selection_lasso: 候选特征数量不足。", call. = FALSE)
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
    if (n < 20L) stop("feature_selection_lasso: 非缺失结局样本过少。", call. = FALSE)
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
    stop("feature_selection_lasso: 训练集 complete.cases 后行数过少。", call. = FALSE)
  }

  feats <- intersect(cand, names(d_tr))
  if (length(feats) < 3L) {
    stop("feature_selection_lasso: 训练集内可用候选特征过少。", call. = FALSE)
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

  lasso_sel <- character(0)
  fit_objs <- list()
  nfolds <- as.integer(bl_cfg$cv_folds %||% 10L)[1L]

  tv <- cfg$survival$time_var %||% "futime"
  ev <- cfg$survival$event_var %||% "fustatus"
  use_cox_lasso <- identical(study_type, "prognosis") && isTRUE(bl_cfg$lasso_use_cox %||% TRUE)
  if (use_cox_lasso && !all(c(tv, ev) %in% names(data))) {
    cli::cli_alert_warning("LASSO-Cox 需要数据中包含 time/event 列，改用 binomial LASSO（按 Group）")
    use_cox_lasso <- FALSE
  }
  cli::cli_alert_info(
    "feature_selection_lasso: study_type={study_type}；结局列={outcome_col}；LASSO={if (use_cox_lasso) 'Cox' else 'binomial'}"
  )

  .lasso_terms_from_coef <- function(b_mat, mm_cols, assign_vec, term_labels, feats_all, drop_intercept = TRUE) {
    if (is.null(b_mat) || !is.matrix(b_mat) || nrow(b_mat) == 0L) return(character(0))
    rn <- rownames(b_mat)
    if (is.null(rn) || !length(rn)) return(character(0))
    nz <- rn[abs(b_mat[, 1L]) > 1e-10]
    if (isTRUE(drop_intercept)) nz <- setdiff(nz, "(Intercept)")
    if (!length(nz)) return(character(0))
    w <- which(mm_cols %in% nz)
    if (!length(w)) return(character(0))
    intersect(term_labels[unique(assign_vec[w])], feats_all)
  }

  .lasso_lambda_mult_grid <- function(n_sel, min_features, max_features,
                                     step = 0.1, max_up = 2.0) {
    step <- abs(as.numeric(step)[1L])
    if (!is.finite(step) || step <= 0) step <- 0.1
    max_up <- as.numeric(max_up)[1L]
    if (!is.finite(max_up) || max_up < step) max_up <- 2.0
    if (length(n_sel) < min_features) {
      unique(round(seq(1, 0, by = -step), 4))
    } else if (!is.null(max_features) && length(n_sel) > max_features) {
      unique(round(seq(step, max_up, by = step), 4))
    } else {
      unique(round(c(seq(1, 0, by = -step), seq(step * 2, max_up, by = step)), 4))
    }
  }

  .lasso_pick_mult_first_iter <- function(cvfit, mm_cols, assign_vec, term_labels, feats_all,
                                          drop_intercept, init_mult, min_features,
                                          max_features = NULL, search_n = 60L,
                                          lambda_step = 0.1, lambda_mult_max = 2.0) {
    lam0 <- cvfit$lambda.min
    .sel_at <- function(mult) {
      b <- as.matrix(coef(cvfit, s = lam0 * mult))
      .lasso_terms_from_coef(
        b, mm_cols, assign_vec, term_labels, feats_all,
        drop_intercept = drop_intercept
      )
    }
    init_sel <- .sel_at(init_mult)
    if (length(init_sel) >= min_features &&
        (is.null(max_features) || length(init_sel) <= max_features)) {
      return(list(mult = init_mult, sel = init_sel, adjusted = FALSE))
    }
    too_few <- length(init_sel) < min_features
    too_many <- !is.null(max_features) && length(init_sel) > max_features
    mult_try <- .lasso_lambda_mult_grid(
      init_sel, min_features, max_features,
      step = lambda_step, max_up = lambda_mult_max
    )
    if (too_many) {
      mult_try <- sort(mult_try, decreasing = FALSE)
    } else {
      mult_try <- sort(mult_try, decreasing = TRUE)
    }
    for (m in mult_try) {
      sel_m <- .sel_at(m)
      if (length(sel_m) >= min_features &&
          (is.null(max_features) || length(sel_m) <= max_features)) {
        return(list(mult = m, sel = sel_m, adjusted = !isTRUE(all.equal(m, init_mult))))
      }
    }
    best_mult <- if (too_many) mult_try[length(mult_try)] else mult_try[1L]
    best_sel <- .sel_at(best_mult)
    for (m in mult_try) {
      sel_m <- .sel_at(m)
      if (too_many) {
        if (length(sel_m) < length(best_sel) ||
            (length(best_sel) > max_features && length(sel_m) <= max_features)) {
          best_sel <- sel_m
          best_mult <- m
        }
      } else if (length(sel_m) > length(best_sel)) {
        best_sel <- sel_m
        best_mult <- m
      }
    }
    list(mult = best_mult, sel = best_sel, adjusted = !isTRUE(all.equal(best_mult, init_mult)))
  }

  .lasso_sel_at_mult <- function(store_item, mult, feats_all) {
    .lasso_terms_from_coef(
      as.matrix(coef(store_item$cvfit, s = store_item$lam0 * mult)),
      store_item$mm_cols, store_item$assign_vec, store_item$term_labels,
      feats_all, drop_intercept = store_item$drop_intercept
    )
  }

  .lasso_build_cv_list <- function(cvfit_store, mult, feats_all) {
    lapply(cvfit_store, function(st) {
      if (is.null(st)) return("isNA")
      sel_i <- .lasso_sel_at_mult(st, mult, feats_all)
      if (length(sel_i)) sel_i else "isNA"
    })
  }

  # 严格频次过线（不含 Top-N）。allow_top_fallback 仅作调 λ 仍不足时的最后兜底。
  .lasso_freq_select <- function(cv.list, freq_cutoff_n, feats, fn_min = 1L,
                                 bl_cfg = list(), allow_top_fallback = FALSE) {
    all_genes <- setdiff(unique(unlist(cv.list, use.names = FALSE)), "isNA")
    if (!length(all_genes)) return(character(0))
    hit_counts <- setNames(integer(length(all_genes)), all_genes)
    for (si in cv.list) {
      if (length(si) == 1L && identical(si, "isNA")) next
      hit_counts[intersect(si, names(hit_counts))] <- hit_counts[intersect(si, names(hit_counts))] + 1L
    }
    gene_sum <- sort(hit_counts, decreasing = TRUE)
    by_cut <- names(gene_sum)[gene_sum > freq_cutoff_n]
    if (length(by_cut) < fn_min && isTRUE(allow_top_fallback)) {
      n_fb <- max(
        as.integer(fn_min)[1L],
        as.integer(bl_cfg$lasso_top_n_fallback %||% fn_min)[1L]
      )
      n_fb <- max(1L, min(n_fb, length(gene_sum)))
      by_cut <- names(gene_sum)[seq_len(n_fb)]
      cli::cli_alert_warning(
        "lasso: 调 lambda mult 后频次过线仍不足，最后按频次 Top-{n_fb} 兜底（阈值>{freq_cutoff_n}/{length(cv.list)}）。"
      )
    }
    intersect(by_cut, feats)
  }

  .lasso_tune_mult_by_freq <- function(cv.list, cvfit_store, feats, fn_min, fn_max,
                                      freq_cutoff_n, lasso_times, bl_cfg,
                                      lambda_step, lambda_mult_max, init_mult) {
    # 只用严格过线数判断；禁止先 Top-N 再“达标”，否则永远不会减小 mult
    lasso_sel <- .lasso_freq_select(
      cv.list, freq_cutoff_n, feats, fn_min, bl_cfg, allow_top_fallback = FALSE
    )
    if (length(lasso_sel) >= fn_min && length(lasso_sel) <= fn_max) {
      return(list(ok = TRUE, mult = init_mult, cv.list = cv.list, lasso_sel = lasso_sel,
                  gene_sum = NULL))
    }
    # 入选过少 → 减小 mult（lambda = lambda.min×mult 更小 → 惩罚更松 → 变量更多，同 ML/VOC）
    # 入选过多 → 增大 mult
    if (!length(cvfit_store) || all(vapply(cvfit_store, is.null, logical(1L)))) {
      cli::cli_alert_warning(
        "lasso: 严格频次入选 {length(lasso_sel)} 个不在目标 {fn_min}–{fn_max}，且无 cvfit 缓存；尝试 Top 兜底。"
      )
      fb <- .lasso_freq_select(
        cv.list, freq_cutoff_n, feats, fn_min, bl_cfg, allow_top_fallback = TRUE
      )
      return(list(ok = length(fb) >= fn_min, mult = init_mult, cv.list = cv.list,
                  lasso_sel = fb, gene_sum = NULL))
    }
    if (length(lasso_sel) > fn_max) {
      # 收紧：增大 mult。若已贴 lasso_lambda_mult_max 仍过多，允许继续升到 tighten_cap
      tighten_cap <- as.numeric(bl_cfg$lasso_lambda_mult_tighten_max %||% 10)[1L]
      if (!is.finite(tighten_cap) || tighten_cap < lambda_mult_max) {
        tighten_cap <- max(10, lambda_mult_max)
      }
      up_max <- max(lambda_mult_max, tighten_cap, init_mult + lambda_step)
      mults <- unique(round(seq(init_mult, up_max, by = lambda_step), 4))
      dir_label <- "增大"
    } else {
      # 放松：减小 mult（含更小的正数与 0）
      down <- seq(init_mult, 0, by = -lambda_step)
      if (!length(down)) down <- 0
      mults <- unique(round(c(down, 0), 4))
      dir_label <- "减小"
    }
    cli::cli_alert_info(
      "lasso: 严格频次入选 {length(lasso_sel)} 个（目标 {fn_min}–{fn_max}），按步长 {lambda_step} {dir_label} lambda mult（=lambda.min×mult）重试…"
    )
    best_sel <- lasso_sel
    best_mult <- init_mult
    best_cv <- cv.list
    for (m in mults) {
      if (isTRUE(all.equal(m, init_mult))) next
      cv_m <- .lasso_build_cv_list(cvfit_store, m, feats)
      sel_m <- .lasso_freq_select(
        cv_m, freq_cutoff_n, feats, fn_min, bl_cfg, allow_top_fallback = FALSE
      )
      if (length(sel_m) >= fn_min && length(sel_m) <= fn_max) {
        cli::cli_alert_info(
          "lasso: lambda mult 调整为 {round(m, 4)}，严格频次入选 {length(sel_m)} 个特征。"
        )
        return(list(ok = TRUE, mult = m, cv.list = cv_m, lasso_sel = sel_m, gene_sum = NULL))
      }
      if (length(lasso_sel) < fn_min) {
        if (length(sel_m) > length(best_sel)) {
          best_sel <- sel_m
          best_mult <- m
          best_cv <- cv_m
        }
      } else if (length(sel_m) < length(best_sel) && length(sel_m) >= fn_min) {
        best_sel <- sel_m
        best_mult <- m
        best_cv <- cv_m
      }
    }
    if (length(best_sel) >= fn_min) {
      cli::cli_alert_warning(
        "lasso: 未精确落入 {fn_min}–{fn_max}，采用最接近严格结果 mult={round(best_mult, 4)}、入选 {length(best_sel)} 个。"
      )
      return(list(ok = TRUE, mult = best_mult, cv.list = best_cv, lasso_sel = best_sel, gene_sum = NULL))
    }
    # 最后兜底：在最松 mult 的频次排序上取 Top-fn_min（不得少于下限）
    fb <- .lasso_freq_select(
      best_cv, freq_cutoff_n, feats, fn_min, bl_cfg, allow_top_fallback = TRUE
    )
    cli::cli_alert_warning(
      "lasso: 已按步长 {lambda_step} 尝试 {dir_label} lambda mult，严格过线仍 < {fn_min}；兜底入选 {length(fb)} 个（mult={round(best_mult, 4)}）。"
    )
    list(ok = length(fb) >= fn_min, mult = best_mult, cv.list = best_cv, lasso_sel = fb, gene_sum = NULL)
  }

  .auto_calibrate_lambda <- function(cvfit, mm_cols, assign_vec, term_labels,
                                     feats_all, drop_intercept,
                                     current_mult, target_n,
                                     mult_cap = 2.0) {
    lam_min <- cvfit$lambda.min
    lam_path <- cvfit$lambda
    if (is.null(lam_path) || !length(lam_path)) return(current_mult)
    counts <- vapply(lam_path, function(lam) {
      b <- tryCatch(as.matrix(coef(cvfit, s = lam)), error = function(e) NULL)
      if (is.null(b)) return(NA_integer_)
      length(.lasso_terms_from_coef(b, mm_cols, assign_vec, term_labels,
                                    feats_all, drop_intercept))
    }, integer(1L))
    valid <- !is.na(counts) & counts > 0L
    if (!any(valid)) return(current_mult)
    idx <- which(valid)[which.min(abs(counts[valid] - target_n))]
    best_lam <- lam_path[idx]
    new_mult <- best_lam / lam_min
    # 与 ML/VOC 一致：mult 过大（远超 lambda.min）会过度稀疏；上限用配置的 mult_max
    mult_cap <- as.numeric(mult_cap)[1L]
    if (is.finite(mult_cap) && mult_cap > 0 && is.finite(new_mult) && new_mult > mult_cap) {
      cli::cli_alert_info(
        "auto_lasso_params: 扫描得到 mult={round(new_mult, 4)} 超过 lasso_lambda_mult_max={mult_cap}，先夹紧到 {mult_cap}。"
      )
      new_mult <- mult_cap
    }
    cli::cli_alert_info(
      "auto_lasso_params: lambda 路径扫描目标 {target_n} 个特征 → 每次迭代预计选出 {counts[idx]} 个，lambda mult 从 {round(current_mult, 4)} 调整为 {round(new_mult, 4)}。"
    )
    new_mult
  }

  family_used <- NA_character_
  lambda_adjust_mult <- NA_real_
  lam_vec <- rep(NA_real_, 0L)

  if (!requireNamespace("glmnet", quietly = TRUE)) {
    cli::cli_alert_warning("feature_selection_lasso: 跳过 lasso（未安装 glmnet）")
    lasso_sel <- character(0)
  } else {
    tryCatch({
      lasso_times <- as.integer(bl_cfg$lasso_cv_times %||% 1000L)[1L]
      if (is.na(lasso_times) || lasso_times < 1L) {
        stop("feature_selection_lasso: lasso_cv_times 必须为正整数。", call. = FALSE)
      }
      lambda_adjust_mult <- as.numeric(bl_cfg$lasso_lambda_adjust_mult %||% 1)[1L]
      if (is.na(lambda_adjust_mult) || lambda_adjust_mult < 0) {
        stop("feature_selection_lasso: lasso_lambda_adjust_mult 必须为非负数。", call. = FALSE)
      }
      lasso_lambda_step <- as.numeric(bl_cfg$lasso_lambda_step %||% 0.1)[1L]
      if (is.na(lasso_lambda_step) || lasso_lambda_step <= 0) lasso_lambda_step <- 0.1
      lasso_lambda_mult_max <- as.numeric(bl_cfg$lasso_lambda_mult_max %||% 2.0)[1L]
      if (is.na(lasso_lambda_mult_max) || lasso_lambda_mult_max <= lasso_lambda_step) {
        lasso_lambda_mult_max <- 2.0
      }
      freq_cutoff_frac <- as.numeric(bl_cfg$lasso_freq_cutoff_frac %||% 0.9)[1L]
      if (is.na(freq_cutoff_frac) || freq_cutoff_frac <= 0 || freq_cutoff_frac > 1) {
        freq_cutoff_frac <- 0.9
      }
      freq_cutoff_n <- as.integer(
        bl_cfg$lasso_frequency_cutoff_n %||% floor(freq_cutoff_frac * lasso_times)
      )[1L]
      freq_cutoff_n <- max(1L, min(lasso_times, freq_cutoff_n))

      cv.list <- vector("list", lasso_times)
      lam_vec <- rep(NA_real_, lasso_times)
      iter_pb <- tryCatch(
        cli::cli_progress_bar(
          total = lasso_times,
          clear = FALSE,
          format = "LASSO 内部迭代 [{cli::pb_bar}] {cli::pb_percent} ({cli::pb_current}/{cli::pb_total})"
        ),
        error = function(e) NULL
      )
      if (!is.null(iter_pb)) {
        on.exit(try(cli::cli_progress_done(id = iter_pb), silent = TRUE), add = TRUE)
      }

      use_bootstrap <- isTRUE(bl_cfg$lasso_bootstrap %||% TRUE)
      subsample_frac <- as.numeric(bl_cfg$lasso_subsample_frac %||% 0.8)[1L]
      if (is.na(subsample_frac) || subsample_frac <= 0.3 || subsample_frac > 1) {
        subsample_frac <- 0.8
      }
      auto_lasso <- isTRUE(bl_cfg$auto_lasso_params %||% TRUE)
      first_target_n <- if (auto_lasso) max(fn_min, as.integer(ceiling(fn_max * 0.75))) else fn_min

      if (use_bootstrap) {
        cli::cli_alert_info(
          "LASSO: 启用 bootstrap 子采样（每次迭代随机使用 {round(subsample_frac * 100)}% 训练样本），产生稳定性选择模式多样性。"
        )
      }

      .subsample_rows <- function(mat, y_vec, frac) {
        n <- nrow(mat)
        n_s <- max(20L, floor(n * frac))
        idx <- sort(sample.int(n, n_s, replace = FALSE))
        list(mat = mat[idx, , drop = FALSE], y = if (inherits(y_vec, "Surv")) y_vec[idx] else y_vec[idx])
      }

      if (use_cox_lasso) {
        cox_cols <- intersect(unique(c(tv, ev, feats)), names(data))
        d_c <- data[tr, cox_cols, drop = FALSE]
        d_c <- d_c[stats::complete.cases(d_c), , drop = FALSE]
        if (nrow(d_c) < 20L) stop("feature_selection_lasso: Cox-LASSO 训练集过小", call. = FALSE)
        Forms_c <- stats::as.formula(paste0("~ 0 + ", paste(feats, collapse = " + ")))
        Terms_c <- stats::terms(Forms_c, data = d_c[, feats, drop = FALSE])
        mm_c <- stats::model.matrix(Terms_c, data = d_c[, feats, drop = FALSE])
        asg_c <- attr(mm_c, "assign")
        tlab_c <- attr(Terms_c, "term.labels")
        yv_full <- survival::Surv(as.numeric(d_c[[tv]]), as.integer(as.numeric(d_c[[ev]])))
        calibrated <- FALSE
        cvfit_store <- vector("list", lasso_times)
        for (ii in seq_len(lasso_times)) {
          if (use_bootstrap && ii > 1L) {
            sub <- .subsample_rows(mm_c, yv_full, subsample_frac)
            mm_it <- sub$mat
            yv_it <- sub$y
          } else {
            mm_it <- mm_c
            yv_it <- yv_full
          }
          cvfit <- glmnet::cv.glmnet(
            mm_it, yv_it, family = "cox", alpha = 1, nfolds = min(nfolds, nrow(mm_it) %/% 2L),
            standardize = TRUE, maxit = as.integer(bl_cfg$glmnet_maxit %||% 20000L)[1L]
          )
          lam0 <- cvfit$lambda.min
          lam_vec[ii] <- lam0
          if (ii == 1L) {
            pick1 <- .lasso_pick_mult_first_iter(
              cvfit = cvfit, mm_cols = colnames(mm_c),
              assign_vec = asg_c, term_labels = tlab_c, feats_all = feats,
              drop_intercept = FALSE, init_mult = lambda_adjust_mult,
              min_features = first_target_n, max_features = fn_max,
              lambda_step = lasso_lambda_step, lambda_mult_max = lasso_lambda_mult_max
            )
            if (isTRUE(pick1$adjusted) && !isTRUE(all.equal(pick1$mult, lambda_adjust_mult))) {
              cli::cli_alert_info(
                "lasso: 首次迭代 lambda mult 按步长 {lasso_lambda_step} 调整为 {round(pick1$mult, 4)}。"
              )
            }
            lambda_adjust_mult <- pick1$mult
            sel_i <- pick1$sel
            if (auto_lasso && !calibrated) {
              target_n_auto <- first_target_n
              new_mult <- .auto_calibrate_lambda(
                cvfit, colnames(mm_c), asg_c, tlab_c, feats,
                drop_intercept = FALSE, current_mult = lambda_adjust_mult,
                target_n = target_n_auto, mult_cap = lasso_lambda_mult_max
              )
              if (!isTRUE(all.equal(new_mult, lambda_adjust_mult))) {
                lambda_adjust_mult <- new_mult
                new_frac <- min(0.75, freq_cutoff_frac)
                freq_cutoff_n <- max(1L, floor(new_frac * lasso_times))
                cli::cli_alert_info(
                  "auto_lasso_params: freq_cutoff 调整为 {round(new_frac * 100)}%（{freq_cutoff_n}/{lasso_times}）。"
                )
                sel_i <- .lasso_terms_from_coef(
                  as.matrix(coef(cvfit, s = lam0 * lambda_adjust_mult)),
                  colnames(mm_c), asg_c, tlab_c, feats, drop_intercept = FALSE
                )
              }
              calibrated <- TRUE
            }
          } else {
            sel_i <- .lasso_terms_from_coef(
              as.matrix(coef(cvfit, s = lam0 * lambda_adjust_mult)),
              colnames(mm_c), asg_c, tlab_c, feats, drop_intercept = FALSE
            )
          }
          cv.list[[ii]] <- if (length(sel_i)) sel_i else "isNA"
          cvfit_store[[ii]] <- list(
            cvfit = cvfit, lam0 = lam0, mm_cols = colnames(mm_c),
            assign_vec = asg_c, term_labels = tlab_c, drop_intercept = FALSE
          )
          if (!is.null(iter_pb)) try(cli::cli_progress_update(id = iter_pb, inc = 1), silent = TRUE)
        }
        family_used <- "cox"
      } else {
        y_g <- as.numeric(d_model$Group == levels(d_model$Group)[2L])
        Forms <- stats::as.formula(paste0("~ 0 + ", paste(feats, collapse = " + ")))
        Terms <- stats::terms(Forms, data = d_model[, feats, drop = FALSE])
        mm2 <- stats::model.matrix(Terms, data = d_model[, feats, drop = FALSE])
        asg <- attr(mm2, "assign")
        tlab <- attr(Terms, "term.labels")
        calibrated <- FALSE
        cvfit_store <- vector("list", lasso_times)
        for (ii in seq_len(lasso_times)) {
          if (use_bootstrap && ii > 1L) {
            sub <- .subsample_rows(mm2, y_g, subsample_frac)
            mm_it <- sub$mat
            yg_it <- sub$y
          } else {
            mm_it <- mm2
            yg_it <- y_g
          }
          cvfit <- glmnet::cv.glmnet(
            mm_it, yg_it, family = "binomial", alpha = 1, type.measure = "class",
            standardize = TRUE, nfolds = min(nfolds, nrow(mm_it) %/% 2L),
            maxit = as.integer(bl_cfg$glmnet_maxit %||% 20000L)[1L]
          )
          lam0 <- cvfit$lambda.min
          lam_vec[ii] <- lam0
          if (ii == 1L) {
            pick1 <- .lasso_pick_mult_first_iter(
              cvfit = cvfit, mm_cols = colnames(mm2),
              assign_vec = asg, term_labels = tlab, feats_all = feats,
              drop_intercept = TRUE, init_mult = lambda_adjust_mult,
              min_features = first_target_n, max_features = fn_max,
              lambda_step = lasso_lambda_step, lambda_mult_max = lasso_lambda_mult_max
            )
            if (isTRUE(pick1$adjusted) && !isTRUE(all.equal(pick1$mult, lambda_adjust_mult))) {
              cli::cli_alert_info(
                "lasso: 首次迭代 lambda mult 按步长 {lasso_lambda_step} 调整为 {round(pick1$mult, 4)}。"
              )
            }
            lambda_adjust_mult <- pick1$mult
            sel_i <- pick1$sel
            if (auto_lasso && !calibrated) {
              target_n_auto <- first_target_n
              new_mult <- .auto_calibrate_lambda(
                cvfit, colnames(mm2), asg, tlab, feats,
                drop_intercept = TRUE, current_mult = lambda_adjust_mult,
                target_n = target_n_auto, mult_cap = lasso_lambda_mult_max
              )
              if (!isTRUE(all.equal(new_mult, lambda_adjust_mult))) {
                lambda_adjust_mult <- new_mult
                new_frac <- min(0.75, freq_cutoff_frac)
                freq_cutoff_n <- max(1L, floor(new_frac * lasso_times))
                cli::cli_alert_info(
                  "auto_lasso_params: freq_cutoff 调整为 {round(new_frac * 100)}%（{freq_cutoff_n}/{lasso_times}）。"
                )
                sel_i <- .lasso_terms_from_coef(
                  as.matrix(coef(cvfit, s = lam0 * lambda_adjust_mult)),
                  colnames(mm2), asg, tlab, feats, drop_intercept = TRUE
                )
              }
              calibrated <- TRUE
            }
          } else {
            sel_i <- .lasso_terms_from_coef(
              as.matrix(coef(cvfit, s = lam0 * lambda_adjust_mult)),
              colnames(mm2), asg, tlab, feats, drop_intercept = TRUE
            )
          }
          cv.list[[ii]] <- if (length(sel_i)) sel_i else "isNA"
          cvfit_store[[ii]] <- list(
            cvfit = cvfit, lam0 = lam0, mm_cols = colnames(mm2),
            assign_vec = asg, term_labels = tlab, drop_intercept = TRUE
          )
          if (!is.null(iter_pb)) try(cli::cli_progress_update(id = iter_pb, inc = 1), silent = TRUE)
        }
        family_used <- "binomial"
      }

      all_genes <- setdiff(unique(unlist(cv.list, use.names = FALSE)), "isNA")
      if (!length(all_genes)) {
        lasso_sel <- character(0)
        fit_objs[["lasso_cv_list"]] <- cv.list
        fit_objs[["lasso_gene_sum"]] <- numeric(0)
        fit_objs[["lasso_times"]] <- lasso_times
        fit_objs[["lasso_cutoff_n"]] <- freq_cutoff_n
        cli::cli_alert_warning("lasso: {lasso_times} 次迭代均未选出有效特征。")
      } else {
        tune_res <- .lasso_tune_mult_by_freq(
          cv.list = cv.list, cvfit_store = cvfit_store, feats = feats,
          fn_min = fn_min, fn_max = fn_max, freq_cutoff_n = freq_cutoff_n,
          lasso_times = lasso_times, bl_cfg = bl_cfg,
          lambda_step = lasso_lambda_step, lambda_mult_max = lasso_lambda_mult_max,
          init_mult = lambda_adjust_mult
        )
        lasso_sel <- tune_res$lasso_sel
        if (isTRUE(tune_res$ok)) {
          cv.list <- tune_res$cv.list
          lambda_adjust_mult <- tune_res$mult
        }
        all_genes_final <- setdiff(unique(unlist(cv.list, use.names = FALSE)), "isNA")
        hit_counts <- setNames(integer(length(all_genes_final)), all_genes_final)
        for (si in cv.list) {
          if (length(si) == 1L && identical(si, "isNA")) next
          hit_counts[intersect(si, names(hit_counts))] <- hit_counts[intersect(si, names(hit_counts))] + 1L
        }
        gene_sum <- sort(hit_counts, decreasing = TRUE)
        fit_objs[["lasso_cv_list"]] <- cv.list
        fit_objs[["lasso_gene_sum"]] <- gene_sum
        fit_objs[["lasso_times"]] <- lasso_times
        fit_objs[["lasso_cutoff_n"]] <- freq_cutoff_n
      }

      if (length(lasso_sel)) {
        cli::cli_alert_info(
          "lasso: 采用 {lasso_times} 次重复，频次阈值>{freq_cutoff_n}，最终入选 {length(lasso_sel)} 个特征。"
        )
      }
    }, error = function(e) {
      cli::cli_alert_warning("lasso 失败: {e$message}")
      lasso_sel <<- character(0)
    })
  }

  ctx$results$feature_selection_by_model[["lasso"]] <- lasso_sel

  meta_row <- data.frame(
    model = "lasso",
    family = family_used,
    lambda_min = if (length(lam_vec)) stats::median(lam_vec, na.rm = TRUE) else NA_real_,
    lambda_multiplier = lambda_adjust_mult,
    n_selected = length(lasso_sel),
    stringsAsFactors = FALSE
  )
  ctx$results$feature_selection_meta[["lasso"]] <- meta_row

  if (!is.null(fit_objs[["lasso_cv_list"]]) && !is.null(fit_objs[["lasso_gene_sum"]])) {
    cv_list_plot <- fit_objs[["lasso_cv_list"]] %||% list()
    gene_sum <- fit_objs[["lasso_gene_sum"]] %||% numeric(0)
    lasso_times <- as.integer(fit_objs[["lasso_times"]] %||% length(cv_list_plot))[1L]
    lasso_cutoff_n <- as.integer(
      fit_objs[["lasso_cutoff_n"]] %||% floor(0.9 * max(1L, lasso_times))
    )[1L]

    if (length(cv_list_plot) && length(gene_sum)) {
      ctx <- save_figure(ctx, "Figure S2A.LassoGenes.pdf", function() {
        op <- graphics::par(mar = c(9.5, 4, 2, 1))
        on.exit(graphics::par(op), add = TRUE)
        nm <- gsub("_", " ", names(gene_sum), fixed = TRUE)
        graphics::barplot(
          gene_sum, names.arg = nm, col = "#b04735", las = 2,
          ylim = c(0, max(1, lasso_times))
        )
        graphics::abline(h = lasso_cutoff_n, lty = 2)
      }, width = 11, height = 6)

      ctx <- save_figure(ctx, "Figure S2B.LassoModel.pdf", function() {
        .fsl01_fig3a_lasso_model_plot(
          cv_list_plot,
          fig3a_engine = bl_cfg$lasso_fig3a_engine %||% "base",
          fig3a_top_patterns = as.integer(bl_cfg$lasso_fig3a_top_patterns %||% 6L)[1L]
        )
      }, width = 12, height = 6)
    }
  }

  cli::cli_alert_success(
    "feature_selection_lasso: 入选 {length(lasso_sel)} 个特征"
  )
  ctx
}

register_block(
  "feature_selection_lasso",
  block_feature_selection_lasso,
  "LASSO 重复 cv.glmnet + 频次筛选（Figure S2A/S2B）"
)
