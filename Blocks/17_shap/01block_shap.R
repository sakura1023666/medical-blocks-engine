###############################################################################
#  shap — 基于 ml_models workflow 的 SHAP 蜂群图 / 瀑布图 / 依赖图（发病 / 预后）。
#
#  register_block: "shap"
#  典型流水线: ml_models 之后；建议包 shapviz、cowplot
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results$ml_models[[tag]]（parsnip fit + recipe）
#  ml_model 优先树模型（xgboost/lightgbm/rf）；kernel 解释需 kernel_bg_n 背景样本
#
#  # ── 配置 config$shap（块内还读 enable、ml_model、bee_color_* 等）────────────
#  shap = list(
#    enable              = TRUE,
#    ml_model / model     = "auto",   # auto 优先 xgboost→lightgbm→rf→...
#    top_n                = 10,       # 蜂群图展示前 N 个特征
#    n_dependence         = 4,        # 依赖图数量上限
#    kernel_bg_n          = 50,       # kernel SHAP 背景行数
#    dependence_features  = NULL,     # 显式指定依赖图变量；NULL 按重要性选
#    pin_index_importance_top = FALSE, # TRUE：暴露/指标在 A/B 重要性图置顶（不改 SHAP 值）
#    importance_pin_top   = NULL,       # 额外置顶变量，如 c("Preop_Cr")
#    bee_color_low/high   = NULL,     # 蜂群渐变；NULL 用 shapviz 默认或随机预设
#    font_family          = NULL
#  ),
#  预后: 输出文件名带预后标注；SHAP 仍对 Group 二分类 workflow 解释
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  Figures/Fig_SHAP_*.pdf、ctx$results$shap_*；源: Blocks/block_shap.R
###############################################################################

.shap_ml_tag_from_display <- function(display_name) {
  dm <- c(
    "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "ENet" = "enet",
    "RSVM" = "rsvm", "MLP" = "mlp", "RealMLP" = "realmlp", "Logistic" = "logistic",
    "LightGBM" = "lightgbm", "KNN" = "knn", "TabPFN" = "tabpfn",
    "AdaBoost" = "adaboost", "CatBoost" = "catboost", "TablCL_v2" = "tablcl_v2",
    "RSF" = "rsf", "Random Survival Forest (RSF)" = "rsf",
    "Random survival forest" = "rsf",
    "XGBSurv" = "xgbsurv", "XGBoost Survival (XGBSurv)" = "xgbsurv",
    "XGBoost-Cox" = "xgbsurv",
    "CoxBoost" = "coxboost",
    "GBM-Cox" = "gbmsurv",
    "Ridge-Cox" = "ridge_cox",
    "ElasticNet-Cox" = "enet_cox",
    "SurvivalSVM" = "survivalsvm",
    "mboost-Cox" = "mboost_cox"
  )
  disp <- tolower(trimws(as.character(display_name)))
  hit <- match(disp, tolower(names(dm)), nomatch = NA_integer_)
  if (!is.na(hit)) return(unname(dm[hit]))
  disp
}

.shap_model_display_name <- function(ctx, tag) {
  tag <- tolower(trimws(as.character(tag %||% "")[1L]))
  best_tag <- tolower(trimws(as.character(ctx$results$ml_best_model_tag %||% tag)[1L]))
  disp <- as.character(ctx$results$ml_best_model_display %||% "")[1L]
  if (identical(tag, best_tag) && nzchar(disp)) return(disp)
  dm <- c(
    dt = "DT", rf = "RF", xgboost = "XGBoost", enet = "ENet", rsvm = "RSVM",
    mlp = "MLP", realmlp = "RealMLP", logistic = "Logistic", lightgbm = "LightGBM",
    knn = "KNN", tabpfn = "TabPFN", adaboost = "AdaBoost", catboost = "CatBoost",
    tablcl_v2 = "TablCL_v2"
  )
  unname(dm[tag]) %||% tag
}

#' importance / bee 图 Y 轴顺序：暴露可置顶，柱长/色点仍为真实 SHAP
.shap_resolve_importance_display_order <- function(shp, sh_cfg = list(), index_feats = character(0)) {
  if (is.null(shp)) return(NULL)
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) return(NULL)
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  if (!ncol(sv)) return(NULL)
  imp <- sort(colMeans(abs(sv)), decreasing = TRUE)
  ranked <- names(imp)
  pin <- as.character(sh_cfg$importance_pin_top %||% character(0))
  pin <- pin[nzchar(trimws(pin))]
  if (isTRUE(sh_cfg$pin_index_importance_top %||% FALSE)) {
    pin <- unique(c(as.character(index_feats)[nzchar(as.character(index_feats))], pin))
  }
  pin <- pin[pin %in% ranked]
  if (!length(pin)) return(ranked)
  unique(c(pin, setdiff(ranked, pin)))
}

.shap_apply_importance_display_order <- function(p, feature_order) {
  if (is.null(p) || !length(feature_order)) return(p)
  feature_order <- as.character(feature_order)
  tryCatch(
    p + ggplot2::scale_y_discrete(limits = rev(feature_order)),
    error = function(e) p
  )
}

.shap_clear_shapviz_banner <- function(p) {
  if (is.null(p) || !inherits(p, "ggplot")) return(p)
  .drop_banner <- function(s) {
    if (length(s) == 0L) return(TRUE)
    s <- trimws(as.character(s))
    if (!length(s) || all(!nzchar(s)) || all(is.na(s))) return(TRUE)
    s <- s[!is.na(s) & nzchar(s)]
    if (!length(s)) return(TRUE)
    any(vapply(s, function(one) {
      grepl("incidence.*train|prognosis.*train|train.*incidence|train.*prognosis", one, ignore.case = TRUE) ||
        grepl("^[—–-].*\\(.*\\)$|^[—–-].*,\\s*(incidence|prognosis|train)", one, ignore.case = TRUE) ||
        grepl("^\\(.*(incidence|prognosis|train).*(incidence|prognosis|train).*\\)$", one, ignore.case = TRUE)
    }, logical(1L)))
  }
  sub <- tryCatch(as.character(p$labels$subtitle), error = function(e) character(0))
  tit <- tryCatch(as.character(p$labels$title), error = function(e) character(0))
  if (.drop_banner(sub)) p <- p + ggplot2::labs(subtitle = NULL)
  if (.drop_banner(tit)) p <- p + ggplot2::labs(title = NULL)
  p
}

.shap_panel_finish <- function(p, font_family, sh_cfg = list(), keep_title = FALSE) {
  if (is.null(p)) return(p)
  p <- .shap_clear_shapviz_banner(p)
  p <- .shap_apply_font(p, font_family)
  axis_sz <- as.numeric(sh_cfg$panel_axis_text_size %||% 8.5)[1L]
  if (!is.finite(axis_sz) || axis_sz <= 0) axis_sz <- 8.5
  right_m <- as.numeric(sh_cfg$panel_margin_right %||% 28)[1L]
  if (!is.finite(right_m) || right_m < 8) right_m <- 28
  left_m <- as.numeric(sh_cfg$panel_margin_left %||% 14)[1L]
  if (!is.finite(left_m) || left_m < 4) left_m <- 14
  title_el <- if (isTRUE(keep_title)) {
    ggplot2::element_text(size = ggplot2::rel(0.95), face = "bold", hjust = 0)
  } else {
    ggplot2::element_blank()
  }
  p + ggplot2::theme(
    plot.title = title_el,
    plot.subtitle = ggplot2::element_text(size = ggplot2::rel(0.72), lineheight = 1.05),
    plot.caption = ggplot2::element_text(size = ggplot2::rel(0.68)),
    axis.text.y = ggplot2::element_text(size = axis_sz),
    axis.text.x = ggplot2::element_text(size = axis_sz),
    legend.box.margin = ggplot2::margin(0, 8, 0, 4, "pt"),
    plot.margin = ggplot2::margin(4, right_m, 4, left_m, "pt")
  )
}

# 仅用于图面展示：下划线改空格；计算用列名保持不变
.shap_pretty_label <- function(x) {
  gsub("_", " ", as.character(x), fixed = TRUE)
}

.shap_feature_matrix_aligned <- function(shp, X_df) {
  X_df <- as.data.frame(X_df)
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) return(X_df)
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  n_sv <- nrow(sv)
  if (nrow(X_df) == n_sv) return(X_df)
  X_from_shp <- tryCatch(shapviz::get_feature_values(shp), error = function(e) NULL)
  if (!is.null(X_from_shp) && nrow(X_from_shp) == n_sv) {
    return(as.data.frame(X_from_shp))
  }
  if (nrow(X_df) >= n_sv) return(X_df[seq_len(n_sv), , drop = FALSE])
  X_df
}

.shap_apply_pretty_display <- function(shp, X_df, X_mat = NULL) {
  if (is.null(shp) || is.null(X_df) || !ncol(X_df)) {
    return(list(shp = shp, X_df = X_df, X_mat = X_mat))
  }
  X_df <- .shap_feature_matrix_aligned(shp, X_df)
  old_cn <- colnames(X_df)
  disp <- .shap_pretty_label(old_cn)
  if (anyDuplicated(disp)) disp <- make.unique(disp, sep = " ")
  if (identical(disp, old_cn)) {
    return(list(shp = shp, X_df = X_df, X_mat = X_mat))
  }
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) return(list(shp = shp, X_df = X_df, X_mat = X_mat))
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  cn <- intersect(colnames(sv), old_cn)
  if (!length(cn)) return(list(shp = shp, X_df = X_df, X_mat = X_mat))
  map <- setNames(disp, old_cn)
  X_sub <- X_df[, cn, drop = FALSE]
  colnames(X_sub) <- unname(map[cn])
  sv_sub <- sv[, cn, drop = FALSE]
  colnames(sv_sub) <- unname(map[cn])
  out <- tryCatch(
    shapviz::shapviz(sv_sub, X = X_sub),
    error = function(e) shapviz::shapviz(as.matrix(sv_sub), X = X_sub)
  )
  attr(out, "shap_method") <- attr(shp, "shap_method")
  attr(out, "shap_tag") <- attr(shp, "shap_tag")
  # 先按旧列名子集，再改展示名，避免 rename 后字符下标失效
  if (!is.null(X_mat) && (is.matrix(X_mat) || is.data.frame(X_mat))) {
    keepm <- intersect(colnames(X_mat), cn)
    if (length(keepm)) {
      X_mat <- X_mat[, keepm, drop = FALSE]
      colnames(X_mat) <- unname(map[keepm])
    } else if (ncol(X_mat) == length(cn) && is.null(colnames(X_mat))) {
      X_mat <- X_mat[, seq_along(cn), drop = FALSE]
      colnames(X_mat) <- unname(map[cn])
    }
  }
  list(shp = out, X_df = X_sub, X_mat = X_mat)
}

.shap_apply_clinical_value_labels <- function(shp, X_df, ctx) {
  raw <- tryCatch(.shap_ml_train_frame(ctx, shap_plot_only = TRUE), error = function(e) NULL)
  if (is.null(raw) || !is.data.frame(raw) || is.null(X_df) || !is.data.frame(X_df)) return(shp)
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  xv <- tryCatch(shapviz::get_feature_values(shp), error = function(e) X_df)
  if (is.null(sv) || is.null(xv)) return(shp)
  xv <- as.data.frame(xv)
  changed <- FALSE
  for (cn in names(xv)) {
    raw_cn <- if (cn %in% names(raw)) cn else gsub(" ", "_", cn, fixed = TRUE)
    if (!raw_cn %in% names(raw) || !.shap_is_categorical_col(raw[[raw_cn]])) next
    lev <- if (is.factor(raw[[raw_cn]])) levels(raw[[raw_cn]]) else {
      unique(as.character(raw[[raw_cn]][!is.na(raw[[raw_cn]])]))
    }
    code <- suppressWarnings(as.integer(as.character(xv[[cn]])))
    ok <- !is.na(code)
    if (!length(lev) || !any(ok) || any(code[ok] < 1L | code[ok] > length(lev))) next
    lab <- rep(NA_character_, length(code))
    lab[ok] <- lev[code[ok]]
    xv[[cn]] <- factor(lab, levels = lev)
    changed <- TRUE
  }
  if (!changed) return(shp)
  out <- tryCatch(shapviz::shapviz(as.matrix(sv), X = xv), error = function(e) NULL)
  if (is.null(out)) return(shp)
  out$baseline <- shp$baseline
  attr(out, "shap_method") <- attr(shp, "shap_method")
  attr(out, "shap_tag") <- attr(shp, "shap_tag")
  out
}

.shap_dataset_incidence <- function(ctx) {
  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !nrow(data)) return(NA_real_)
  ana <- trimws(as.character(cfg$project$analysis_group %||% cfg$project$disease %||% "Case")[1L])
  ref <- trimws(as.character(cfg$project$reference_group %||% "Control")[1L])
  oc <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
  if (identical(tolower(cfg$project$study_type %||% ""), "incidence")) {
    oc <- as.character((cfg$incidence %||% list())$outcome_var %||% oc)[1L]
  }
  y <- NULL
  if (oc %in% names(data)) {
    if (is.numeric(data[[oc]])) {
      y <- as.integer(data[[oc]] == 1)
    } else {
      y <- as.integer(trimws(as.character(data[[oc]])) == ana)
    }
  } else if ("Group" %in% names(data)) {
    y <- as.integer(trimws(as.character(data$Group)) == ana)
  }
  if (is.null(y) || !any(!is.na(y))) return(NA_real_)
  mean(y[!is.na(y)] == 1L)
}

.shap_resolve_waterfall_row_id <- function(ctx, sh_cfg, tag, nrow_x, tr_frame = NULL,
                                           source_row_ids = NULL) {
  nrow_x <- as.integer(nrow_x)[1L]
  empty_pick <- list(
    row_id = 1L, incidence = NA_real_, pred_prob = NA_real_,
    outcome01 = NA_integer_, met_threshold = FALSE, rule = "fallback_row1"
  )
  if (!is.finite(nrow_x) || nrow_x < 1L) {
    return(list(row_id = 1L, pick = empty_pick))
  }
  # waterfall_row_id 仅在关闭自动选样时生效；模板常写死 1L，不能压过 case/高概率规则
  if (isFALSE(sh_cfg$waterfall_auto_case_high_prob %||% TRUE)) {
    manual <- sh_cfg$waterfall_row_id %||% NULL
    if (!is.null(manual) && !is.na(suppressWarnings(as.integer(manual)[1L]))) {
      rid <- min(max(1L, as.integer(manual)[1L]), nrow_x)
      return(list(row_id = rid, pick = modifyList(empty_pick, list(row_id = rid, rule = "manual"))))
    }
    return(list(row_id = 1L, pick = empty_pick))
  }
  ana <- trimws(as.character(ctx$config$project$analysis_group %||% ctx$config$project$disease %||% "Case")[1L])
  tr <- tr_frame
  if (is.null(tr)) tr <- tryCatch(.shap_ml_train_frame(ctx, shap_plot_only = TRUE), error = function(e) NULL)
  if (is.null(tr) || !nrow(tr)) {
    return(list(row_id = 1L, pick = empty_pick))
  }
  outcome01 <- as.integer(trimws(as.character(tr$Group)) == ana)
  pred_prob <- rep(NA_real_, nrow(tr))
  if (exists("resolve_ml_models_dir_for_tag", mode = "function") && nzchar(tag %||% "")) {
    models_dir <- resolve_ml_models_dir_for_tag(ctx, tag)
    rdata <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
    if (file.exists(rdata)) {
      env <- new.env(parent = emptyenv())
      tryCatch(load(rdata, envir = env), error = function(e) NULL)
      pt <- env$predtrain %||% env[[paste0("predtrain_", tag)]]
      if (!is.null(pt) && is.data.frame(pt) && nrow(pt) == nrow(tr)) {
        pred_col <- ctx$results$ml_pred_ana_col %||% paste0(".pred_", make.names(ana))
        if (pred_col %in% names(pt)) pred_prob <- as.numeric(pt[[pred_col]])
      }
    }
  }
  source_row_ids <- suppressWarnings(as.integer(source_row_ids))
  if (length(source_row_ids) == nrow_x &&
      all(is.finite(source_row_ids)) &&
      all(source_row_ids >= 1L & source_row_ids <= length(outcome01))) {
    outcome01 <- outcome01[source_row_ids]
    pred_prob <- pred_prob[source_row_ids]
  } else {
    source_row_ids <- seq_len(min(nrow_x, length(outcome01)))
    outcome01 <- outcome01[source_row_ids]
    pred_prob <- pred_prob[source_row_ids]
  }
  thr <- as.numeric(sh_cfg$waterfall_prob_threshold %||% 0.75)[1L]
  pick <- pipeline_pick_shap_waterfall_row(ctx, pred_prob, outcome01, prob_threshold = thr)
  row_id <- min(max(1L, pick$row_id), nrow_x)
  pick$source_row_id <- as.integer(source_row_ids[row_id])
  if (length(outcome01) >= row_id && (is.na(outcome01[row_id]) || outcome01[row_id] != 1L)) {
    hit_case <- which(!is.na(outcome01) & outcome01 == 1L)
    if (length(hit_case)) {
      row_id <- min(hit_case[1L], nrow_x)
      pick$row_id <- row_id
      pick$outcome01 <- as.integer(outcome01[row_id])
      pick$pred_prob <- as.numeric(pred_prob[row_id])
      pick$met_threshold <- isTRUE(pred_prob[row_id] > thr)
      pick$rule <- "case_fallback_first"
    }
  }
  list(row_id = row_id, pick = pick)
}

.shap_waterfall_link_values <- function(shp, row_id, link = "logit") {
  row_id <- as.integer(row_id)[1L]
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (inherits(sv, "Matrix")) sv <- as.matrix(sv)
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  if (is.null(sv) || !is.matrix(sv) || !nrow(sv) || !ncol(sv) || nrow(sv) < row_id) {
    return(list(fx = NA_real_, efx = NA_real_, on_prob_scale = FALSE))
  }
  base <- shp$baseline
  if (length(base) > 1L) base <- base[1L]
  fx <- as.numeric(base) + sum(sv[row_id, , drop = TRUE])
  efx <- as.numeric(base)
  on_prob <- identical(tolower(link), "logit") || identical(tolower(link), "probability")
  if (on_prob) {
    fx <- stats::plogis(fx)
    efx <- stats::plogis(efx)
  }
  list(fx = fx, efx = efx, on_prob_scale = on_prob)
}

.shap_waterfall_with_labels <- function(shp, row_id, sh_cfg, ctx) {
  pick <- ctx$results$shap_waterfall_pick %||% list()
  incidence <- ctx$results$shap_waterfall_incidence %||% .shap_dataset_incidence(ctx)
  thr <- as.numeric(sh_cfg$waterfall_prob_threshold %||% 0.75)[1L]
  if (!is.finite(thr)) thr <- 0.75
  link <- sh_cfg$waterfall_link %||% "logit"
  vals <- .shap_waterfall_link_values(shp, row_id, link = link)
  p <- tryCatch(
    shapviz::sv_waterfall(shp, row_id = row_id),
    error = function(e) {
      cli::cli_alert_warning("block_shap: waterfall 跳过（{conditionMessage(e)}）")
      NULL
    }
  )
  if (is.null(p)) return(NULL)

  outcome_lab <- if (identical(as.integer(pick$outcome01 %||% NA_integer_), 1L)) {
    "Actual outcome: case (positive)"
  } else if (identical(as.integer(pick$outcome01 %||% NA_integer_), 0L)) {
    "Actual outcome: non-case"
  } else {
    "Actual outcome: unknown"
  }
  pred_p <- pick$pred_prob %||% NA_real_
  thr_txt <- if (is.finite(as.numeric(pred_p))) {
    sprintf("pred=%.3f (prob)", as.numeric(pred_p))
  } else {
    "pred=NA"
  }
  sample_title <- paste0(outcome_lab, "; ", thr_txt)

  ## 关键：shapviz::sv_waterfall 本身已按 logit 空间标注柱末 f(x) 与基线 E[f(x)]。
  ## 旧代码另加 header f(x)=概率、caption E[f(x)]=概率基线，与图内 logit 标注互相矛盾
  ## （如 header f(x)=0.610 vs 柱末 f(x)=0.448；caption E[f(x)]=0.500 vs 基线 0）。
  ## 统一口径：只保留 pred（概率，明确标 (prob)），f(x)/E[f(x)] 交给 shapviz 原生 logit 标注。
  p <- p + ggplot2::labs(title = NULL, subtitle = sample_title, caption = NULL)
  p
}

.shap_resolve_model_tag <- function(ctx, sh_cfg, fitted_names) {
  preferred <- c("xgboost", "lightgbm", "rf", "catboost", "dt", "adaboost")
  .prefer_tag <- function(cands) {
    hit <- preferred[preferred %in% cands]
    if (length(hit)) return(hit[[1L]])
    cands[[1L]]
  }
  choice_raw <- sh_cfg$ml_model %||% sh_cfg$model %||% "auto"
  choice <- tolower(trimws(as.character(choice_raw)[1L]))
  if (identical(choice, "auto") || !nzchar(choice)) {
    tag <- ctx$results$ml_best_model_tag %||% NULL
    if (!is.null(tag) && nzchar(tag) && tag %in% fitted_names) return(tag)
    ev <- ctx$results$ml_eval_all
    if (is.null(ev) || !nrow(ev)) {
      if (length(fitted_names)) return(.prefer_tag(fitted_names))
      stop("block_shap: ml_model=auto 需要 ml_eval_all 或 ml_best_model_tag，请先运行 ml_models。", call. = FALSE)
    }
    st <- tolower(trimws(as.character(ctx$config$project$study_type %||% "")[1L]))
    ## 预后优先 C-index；发病用 roc_auc
    metrics <- if (identical(st, "prognosis")) {
      c("c_index", "roc_auc")
    } else {
      c("roc_auc", "c_index")
    }
    sub <- ev[tolower(as.character(ev$dataset)) == "test" &
                tolower(as.character(ev$.metric)) %in% metrics, , drop = FALSE]
    if (!nrow(sub)) stop("block_shap: ml_eval_all 中无 validation/test 的 roc_auc/c_index。", call. = FALSE)
    sub <- sub[order(match(tolower(as.character(sub$.metric)), metrics)), , drop = FALSE]
    sub <- sub[!duplicated(as.character(sub$model)), , drop = FALSE]
    sub[["tmp_ml_tag"]] <- vapply(as.character(sub$model), .shap_ml_tag_from_display, character(1L))
    ok <- sub[["tmp_ml_tag"]] %in% fitted_names
    sub <- if (any(ok)) sub[ok, , drop = FALSE] else sub
    best <- sub[which.max(as.numeric(sub$.estimate)), , drop = FALSE]
    tg <- .shap_ml_tag_from_display(as.character(best$model[1L]))
    if (tg %in% fitted_names) return(tg)
    if (length(fitted_names)) return(.prefer_tag(fitted_names))
    stop("block_shap: ml_model=auto 无法解析已训练模型。", call. = FALSE)
  }
  choice
}

.shap_active_index_vars <- function(cfg, ctx = NULL) {
  active <- unique(c(
    as.character(cfg$prediction$index_vars %||% character(0)),
    as.character(cfg$incidence$index_var %||% character(0))
  ))
  active <- active[nzchar(active)]
  if (length(active)) return(active)
  if (!is.null(ctx)) {
    active <- as.character(ctx$results$computed_index_names %||% character(0))
    active <- active[nzchar(active)]
  }
  active
}

.shap_tree_capable_tags <- function() {
  c("xgboost", "lightgbm", "rf", "catboost", "dt", "adaboost")
}

.shap_shapviz_capable_tags <- function() {
  c("xgboost", "lightgbm", "rf", "dt")
}

.shap_is_tree_shap_capable <- function(tag) {
  tag <- tolower(trimws(as.character(tag)[1L]))
  tag %in% .shap_tree_capable_tags()
}

.shap_is_shapviz_capable <- function(tag) {
  tag <- tolower(trimws(as.character(tag)[1L]))
  tag %in% .shap_shapviz_capable_tags()
}

.shap_pick_best_tag_among <- function(ctx, fitted_names, allowed_tags) {
  fitted_names <- as.character(fitted_names)[nzchar(as.character(fitted_names))]
  allowed <- intersect(as.character(allowed_tags), fitted_names)
  if (!length(allowed)) return(NULL)
  preferred <- c("xgboost", "lightgbm", "rf", "dt", "catboost", "adaboost")
  allowed <- c(intersect(preferred, allowed), setdiff(allowed, preferred))
  ev <- ctx$results$ml_eval_all
  if (is.null(ev) || !nrow(ev)) return(allowed[[1L]])
  sub <- ev[tolower(as.character(ev$dataset)) == "test" &
              tolower(as.character(ev$.metric)) == "roc_auc", , drop = FALSE]
  if (!nrow(sub)) return(allowed[[1L]])
  dm <- c(
    "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "LightGBM" = "lightgbm",
    "CatBoost" = "catboost", "AdaBoost" = "adaboost", "ENet" = "enet"
  )
  .row_tag <- function(disp) {
    hit <- match(tolower(trimws(disp)), tolower(names(dm)), nomatch = NA_integer_)
    if (is.na(hit)) tolower(trimws(disp)) else unname(dm[hit])
  }
  sub[["tmp_ml_tag"]] <- vapply(as.character(sub$model), .row_tag, character(1L))
  sub <- sub[sub[["tmp_ml_tag"]] %in% allowed, , drop = FALSE]
  if (!nrow(sub)) return(allowed[[1L]])
  best <- sub[which.max(as.numeric(sub$.estimate)), , drop = FALSE]
  tg <- .shap_ml_tag_from_display(as.character(best$model[1L]))
  if (tg %in% allowed) tg else allowed[[1L]]
}

.shap_pick_best_tree_tag <- function(ctx, fitted_names) {
  .shap_pick_best_tag_among(ctx, fitted_names, .shap_tree_capable_tags())
}

.shap_pick_best_shapviz_tag <- function(ctx, fitted_names) {
  .shap_pick_best_tag_among(ctx, fitted_names, .shap_shapviz_capable_tags())
}

.shap_resolve_shap_model_tag <- function(ctx, sh_cfg, fitted_names) {
  tag <- .shap_resolve_model_tag(ctx, sh_cfg, fitted_names)
  ## 铁律：force_kernel_best_model / ml_model=auto 时，必须解释最优模型，禁止回退树模型
  if (isTRUE(sh_cfg$force_kernel_best_model %||% FALSE)) return(tag)
  choice <- tolower(trimws(as.character(sh_cfg$ml_model %||% sh_cfg$model %||% "auto")[1L]))
  if (identical(choice, "auto") &&
      identical(tolower(trimws(ctx$config$project$study_type %||% "")), "prognosis")) {
    return(tag)
  }
  if (.shap_is_shapviz_capable(tag)) return(tag)
  fb <- .shap_pick_best_shapviz_tag(ctx, fitted_names)
  if (!is.null(fb) && nzchar(fb)) {
    cli::cli_alert_info(
      "block_shap: 最优模型 {tag} 不支持 shapviz，回退至 {fb} 作 SHAP 解释。"
    )
    return(fb)
  }
  tag
}

.shap_exclude_foreign_composite_indices <- function(vars, cfg, ctx) {
  vars <- as.character(vars)[nzchar(as.character(vars))]
  if (!length(vars)) return(character(0))
  active <- .shap_active_index_vars(cfg, ctx)
  all_ix <- unique(c(
    active,
    as.character(ctx$results$computed_index_names %||% character(0))
  ))
  all_ix <- all_ix[nzchar(all_ix)]
  foreign <- setdiff(all_ix, active)
  if (length(foreign)) vars <- setdiff(vars, foreign)
  vars
}

.shap_resolve_ml_feature_names <- function(ctx) {
  ## 优先 feature_selection_final（定稿 ML 特征）。venn_center 在部分单方法
  ## （如仅 Boruta，draw_venn=FALSE）路径下可能残留候选并集（>final），导致
  ## 烘焙列与模型训练特征不一致 → kernel/fastshap 报「暴露列缺失」。
  feats <- as.character(
    ctx$results$feature_selection_final %||%
      ctx$results$ml_feature_names %||%
      ctx$results$feature_selection_venn_center %||%
      character(0)
  )
  n_final <- length(unique(feats[nzchar(feats)]))
  n_venn <- length(unique(as.character(
    ctx$results$feature_selection_venn_center %||% character(0)
  )))
  if (n_final > 0L && n_venn > n_final) {
    cli::cli_alert_info(
      "block_shap: venn_center({n_venn}) > final({n_final})，按 final 定稿特征解释。"
    )
  }
  feats <- unique(feats[nzchar(feats)])
  if (!length(feats)) {
    feats <- as.character(ctx$results$Model2Factors %||% character(0))
    feats <- unique(feats[nzchar(feats)])
  }
  if (!length(feats)) {
    tr <- ctx$data$train %||% ctx$results$ml_train_data
    if (!is.null(tr)) {
      feats <- setdiff(names(tr), "Group")
      if (length(feats)) {
        cli::cli_alert_warning(
          "block_shap: ml_feature_names 缺失，回退训练集全部预测列（n={length(feats)}）。"
        )
      }
    }
  }
  feats
}

.shap_match_venn_features <- function(ctx) {
  cfg <- ctx$config
  isTRUE((cfg$shap %||% list())$match_venn_features %||%
    (cfg$ml %||% list())$use_venn_center_features %||% FALSE)
}

.shap_resolve_venn_feature_names <- function(ctx) {
  ## 与 .shap_resolve_ml_feature_names 同序：final 定稿优先（venn_center 在单方法
  ## Boruta 路径可能残留候选并集）
  feats <- as.character(
    ctx$results$feature_selection_final %||%
      ctx$results$feature_selection_venn_center %||%
      ctx$results$ml_feature_names %||%
      character(0)
  )
  unique(feats[nzchar(feats)])
}

#' SHAP 图用特征：韦恩中心变量（与 ML 一致，含分类+连续）；否则数值协变量 + 分析指标
.shap_resolve_shap_plot_features <- function(ctx) {
  if (.shap_match_venn_features(ctx)) {
    feats <- .shap_resolve_venn_feature_names(ctx)
    if (length(feats)) {
      base <- .shap_train_data_frame(ctx)
      if (!is.null(base)) feats <- intersect(feats, names(base))
      if (length(feats)) return(feats)
    }
  }
  .shap_resolve_shap_raw_features(ctx)
}

.shap_is_categorical_col <- function(x) {
  is.factor(x) || is.character(x) || is.logical(x)
}

.shap_full_split_frame <- function(ctx, split = c("train", "test")) {
  split <- match.arg(split)
  if (identical(split, "train")) {
    ctx$data$train %||% ctx$results$ml_train_data
  } else {
    ctx$data$test %||% ctx$results$ml_test_data
  }
}

#' 将当前分析指标列并入 ML 训练/验证帧（指标通常不在 ml_feature_names 中）
.shap_attach_index_columns <- function(df, ctx, split = c("train", "test")) {
  if (is.null(df) || !nrow(df)) return(df)
  split <- match.arg(split)
  index_feats <- .shap_active_index_vars(ctx$config, ctx)
  if (!length(index_feats)) return(df)

  full <- .shap_full_split_frame(ctx, split)
  imp <- ctx$data$imputed %||% ctx$data$cleaned
  id_col <- as.character(ctx$config$data$id_column %||% "SEQN")[1L]

  for (ix in index_feats) {
    if (ix %in% names(df)) next
    val <- NULL
    if (!is.null(full) && ix %in% names(full) && nrow(full) == nrow(df)) {
      val <- full[[ix]]
    } else if (!is.null(imp) && ix %in% names(imp)) {
      if (nzchar(id_col) && id_col %in% names(df) && id_col %in% names(imp)) {
        val <- imp[[ix]][match(df[[id_col]], imp[[id_col]])]
      } else if (!is.null(full) && ix %in% names(imp) &&
                 nzchar(id_col) && id_col %in% names(full) && id_col %in% names(imp) &&
                 nrow(full) == nrow(df)) {
        val <- imp[[ix]][match(full[[id_col]], imp[[id_col]])]
      }
    }
    if (!is.null(val)) {
      df[[ix]] <- suppressWarnings(as.numeric(val))
    }
  }
  df
}

.shap_train_data_frame <- function(ctx) {
  base <- ctx$results$ml_train_data %||% ctx$data$train
  base <- .shap_ensure_group_column(base, ctx, split = "train")
  .shap_attach_index_columns(base, ctx, split = "train")
}

.shap_test_data_frame <- function(ctx) {
  base <- ctx$results$ml_test_data %||% ctx$data$test
  base <- .shap_ensure_group_column(base, ctx, split = "test")
  .shap_attach_index_columns(base, ctx, split = "test")
}

## 预后 ML 的 ml_train_data 只有 .time/.event，无 Group；从事件列或 data$train 回填
.shap_ensure_group_column <- function(base, ctx, split = c("train", "test")) {
  if (is.null(base) || !is.data.frame(base)) return(base)
  if ("Group" %in% names(base)) return(base)
  split <- match.arg(split)
  cfg <- ctx$config
  ana <- as.character(cfg$project$analysis_group %||% cfg$project$disease %||% "Case")[1L]
  ref <- as.character(cfg$project$reference_group %||% "Control")[1L]
  src <- if (identical(split, "test")) ctx$data$test else ctx$data$train
  if (!is.null(src) && "Group" %in% names(src) && nrow(src) == nrow(base)) {
    base$Group <- src$Group
    return(base)
  }
  ev <- NULL
  if (".event" %in% names(base)) {
    ev <- base[[".event"]]
  } else {
    ev_var <- cfg$survival$event_var %||% cfg$data$outcome_column %||% NULL
    if (!is.null(ev_var) && ev_var %in% names(base)) ev <- base[[ev_var]]
    if (is.null(ev) && !is.null(src) && !is.null(ev_var) && ev_var %in% names(src) &&
        nrow(src) == nrow(base)) {
      ev <- src[[ev_var]]
    }
  }
  if (is.null(ev)) {
    stop("block_shap: 无法构建 Group 列（缺 Group/.event/结局列）。", call. = FALSE)
  }
  if (exists(".mlsurv_coerce_event01", mode = "function")) {
    ev01 <- .mlsurv_coerce_event01(ev, analysis_group = ana, reference_group = ref)
  } else if (is.factor(ev) && nlevels(ev) == 2L) {
    ev01 <- as.integer(as.integer(ev) == 2L)
  } else {
    ev01 <- suppressWarnings(as.integer(ev))
  }
  base$Group <- factor(
    ifelse(ev01 == 1L, ana, ref),
    levels = unique(c(ref, ana))
  )
  base
}

#' SHAP 图用原始特征：ML 数值协变量 + 当前分析指标（排除 factor/character/logical）
.shap_resolve_shap_raw_features <- function(ctx) {
  ml_feats <- .shap_resolve_ml_feature_names(ctx)
  base <- .shap_train_data_frame(ctx)
  index_feats <- .shap_active_index_vars(ctx$config, ctx)
  if (is.null(base)) return(character(0))

  is_numeric_pred <- function(f) {
    if (!f %in% names(base)) return(FALSE)
    col <- base[[f]]
    is.numeric(col) && !is.factor(col)
  }

  numeric_feats <- ml_feats[vapply(ml_feats, is_numeric_pred, logical(1L))]
  index_ok <- index_feats[vapply(index_feats, is_numeric_pred, logical(1L))]
  out <- unique(c(index_ok, numeric_feats))
  if (length(index_feats) && !length(index_ok)) {
    cli::cli_alert_warning(
      "block_shap: 分析指标 [{paste(index_feats, collapse = ', ')}] 未能并入 SHAP 训练帧"
    )
  }
  out
}

.shap_categorical_raw_features <- function(ctx, ml_feats = NULL) {
  ml_feats <- ml_feats %||% .shap_resolve_ml_feature_names(ctx)
  base <- .shap_train_data_frame(ctx)
  if (is.null(base)) return(character(0))
  ml_feats[ml_feats %in% names(base) & vapply(ml_feats, function(f) {
    .shap_is_categorical_col(base[[f]])
  }, logical(1L))]
}

#' 韦恩/最终 ML 特征名 → 烘焙后列名（连续变量同名；分类变量含 dummy 前缀列）
.shap_baked_columns_for_venn_features <- function(ctx, pred_cols, venn_raw = NULL) {
  pred_cols <- as.character(pred_cols)
  venn_raw <- unique(as.character(venn_raw %||% .shap_resolve_venn_feature_names(ctx)))
  venn_raw <- venn_raw[nzchar(venn_raw)]
  if (!length(venn_raw)) return(pred_cols)
  keep <- character(0)
  for (v in venn_raw) {
    if (v %in% pred_cols) {
      keep <- c(keep, v)
    } else {
      hits <- pred_cols[vapply(pred_cols, function(col) {
        .shap_is_baked_categorical_column(col, v)
      }, logical(1L))]
      if (length(hits)) keep <- c(keep, hits)
    }
  }
  unique(keep[nzchar(keep)])
}

.shap_venn_plot_baked <- function(ctx, tag, explain_on, sh_cfg = NULL) {
  tr_plot <- .shap_ml_train_frame(ctx, shap_plot_only = TRUE)
  pred_cols_plot <- setdiff(names(tr_plot), "Group")
  if (!length(pred_cols_plot)) return(NULL)
  X_df_plot <- tr_plot[, pred_cols_plot, drop = FALSE]
  list(
    d = tr_plot,
    X_df = X_df_plot,
    X_mat = {
      Xm <- as.matrix(X_df_plot)
      storage.mode(Xm) <- "double"
      colnames(Xm) <- pred_cols_plot
      Xm
    },
    n = nrow(tr_plot)
  )
}

#' workflow 全列 SHAP → 韦恩/ML 最终特征（10 个原始变量）；分类 dummy 的 SHAP 按列求和
.shap_collapse_shapviz_to_venn_features <- function(shp, X_df, ctx, venn_raw = NULL) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    return(list(shp = shp, X_df = X_df, X_mat = NULL))
  }
  venn_raw <- unique(as.character(venn_raw %||% .shap_resolve_venn_feature_names(ctx)))
  venn_raw <- venn_raw[nzchar(venn_raw)]
  if (!length(venn_raw)) return(list(shp = shp, X_df = X_df, X_mat = NULL))

  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) return(list(shp = shp, X_df = X_df, X_mat = NULL))
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  pred_cols <- colnames(sv)
  n <- nrow(sv)
  X_df <- .shap_feature_matrix_aligned(shp, X_df)

  tr_raw <- tryCatch(.shap_ml_train_frame(ctx, shap_plot_only = TRUE), error = function(e) NULL)
  use_raw_x <- !is.null(tr_raw) && nrow(tr_raw) >= n
  if (use_raw_x) tr_raw <- tr_raw[seq_len(n), , drop = FALSE]

  S_new <- matrix(0, nrow = n, ncol = length(venn_raw))
  colnames(S_new) <- venn_raw
  X_new <- as.data.frame(matrix(NA_real_, nrow = n, ncol = length(venn_raw)))
  colnames(X_new) <- venn_raw

  for (v in venn_raw) {
    cols <- if (v %in% pred_cols) {
      v
    } else {
      pred_cols[vapply(pred_cols, function(col) {
        .shap_is_baked_categorical_column(col, v)
      }, logical(1L))]
    }
    if (!length(cols)) next
    if (length(cols) == 1L) {
      S_new[, v] <- sv[, cols]
      X_new[[v]] <- if (use_raw_x && v %in% names(tr_raw)) {
        col <- tr_raw[[v]]
        if (.shap_is_categorical_col(col)) as.numeric(factor(col)) else suppressWarnings(as.numeric(col))
      } else {
        X_df[[cols]]
      }
    } else {
      S_new[, v] <- rowSums(sv[, cols, drop = FALSE])
      X_new[[v]] <- if (use_raw_x && v %in% names(tr_raw)) {
        col <- tr_raw[[v]]
        if (.shap_is_categorical_col(col)) as.numeric(factor(col)) else suppressWarnings(as.numeric(col))
      } else {
        rowMeans(X_df[, cols, drop = FALSE])
      }
    }
  }

  out_shp <- tryCatch(
    shapviz::shapviz(S_new, X = X_new),
    error = function(e) shapviz::shapviz(as.matrix(S_new), X = X_new)
  )
  attr(out_shp, "shap_method") <- attr(shp, "shap_method")
  attr(out_shp, "shap_tag") <- attr(shp, "shap_tag")
  X_mat <- as.matrix(X_new)
  storage.mode(X_mat) <- "double"
  colnames(X_mat) <- venn_raw
  list(shp = out_shp, X_df = X_new, X_mat = X_mat)
}

.shap_is_baked_categorical_column <- function(col, cat_raw) {
  if (col %in% cat_raw) return(TRUE)
  if (!length(cat_raw)) return(FALSE)
  any(vapply(cat_raw, function(cn) {
    grepl(paste0("^", gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", cn, perl = TRUE), "_"), col)
  }, logical(1L)))
}

#' 烘焙后列名 → SHAP 图展示列（去分类/dummy，保留分析指标）
.shap_filter_plot_columns <- function(ctx, pred_cols, sh_cfg = NULL) {
  sh_cfg <- sh_cfg %||% ctx$config$shap %||% list()
  if (isTRUE(.shap_match_venn_features(ctx))) {
    venn <- .shap_resolve_venn_feature_names(ctx)
    keep <- .shap_baked_columns_for_venn_features(ctx, pred_cols, venn)
    if (!length(keep)) keep <- as.character(pred_cols)
    keep <- unique(keep[nzchar(keep)])
    cli::cli_alert_info(
      "block_shap: 韦恩对齐 SHAP 图列 n={length(keep)}（ML 特征 {length(venn)} 个）: {paste(head(keep, 12), collapse = ', ')}{if (length(keep) > 12) ', ...' else ''}"
    )
    return(keep)
  }
  if (isFALSE(sh_cfg$exclude_categorical %||% TRUE)) return(pred_cols)

  cat_raw <- .shap_categorical_raw_features(ctx)
  index_feats <- .shap_active_index_vars(ctx$config, ctx)

  keep <- pred_cols[!vapply(pred_cols, function(col) {
    .shap_is_baked_categorical_column(col, cat_raw)
  }, logical(1L))]

  if (isTRUE(sh_cfg$force_index_in_plot %||% TRUE)) {
    for (ix in index_feats) {
      if (ix %in% pred_cols) keep <- unique(c(ix, keep))
    }
  }

  keep <- unique(keep[nzchar(keep)])
  if (!length(keep)) {
    cli::cli_alert_warning("block_shap: 排除分类变量后无可用列，保留全部烘焙列。")
    return(pred_cols)
  }

  dropped <- setdiff(pred_cols, keep)
  if (length(dropped)) {
    cli::cli_alert_info(
      "block_shap: SHAP 图已排除分类变量 {length(dropped)} 列（如 {paste(head(dropped, 5), collapse = ', ')}{if (length(dropped) > 5) ', ...' else ''}）"
    )
  }
  hit_ix <- intersect(index_feats, keep)
  if (length(hit_ix)) {
    cli::cli_alert_info("block_shap: SHAP 图包含分析指标: {paste(hit_ix, collapse = ', ')}")
  } else if (length(index_feats)) {
    cli::cli_alert_warning(
      "block_shap: 分析指标 [{paste(index_feats, collapse = ', ')}] 未出现在 SHAP 烘焙列中"
    )
  }
  keep
}

.shap_subset_shapviz <- function(shp, keep_cols, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) return(shp)
  keep_cols <- intersect(as.character(keep_cols), colnames(X_df))
  if (!length(keep_cols)) return(shp)
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) return(shp)
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  cn <- intersect(colnames(sv), keep_cols)
  if (!length(cn)) return(shp)
  X_df <- .shap_feature_matrix_aligned(shp, X_df)
  X_sub <- X_df[, cn, drop = FALSE]
  out <- tryCatch(
    shapviz::shapviz(sv[, cn, drop = FALSE], X = X_sub),
    error = function(e) {
      shapviz::shapviz(as.matrix(sv[, cn, drop = FALSE]), X = X_sub)
    }
  )
  attr(out, "shap_method") <- attr(shp, "shap_method")
  attr(out, "shap_tag") <- attr(shp, "shap_tag")
  out
}

.shap_ml_train_frame <- function(ctx, attach_id = FALSE, shap_plot_only = FALSE) {
  feats <- if (isTRUE(shap_plot_only)) {
    .shap_resolve_shap_plot_features(ctx)
  } else {
    .shap_resolve_ml_feature_names(ctx)
  }
  if (!length(feats)) {
    stop(
      "block_shap: ml_feature_names / feature_selection_final 为空，请先运行 ml_models。",
      call. = FALSE
    )
  }
  base <- .shap_train_data_frame(ctx)
  if (is.null(base)) {
    stop("block_shap: 缺少训练数据（ml_train_data / data$train）。", call. = FALSE)
  }
  hit <- intersect(feats, names(base))
  miss <- setdiff(feats, names(base))
  if (length(miss)) {
    cli::cli_alert_warning(
      "block_shap: ML 特征在训练集中缺失 {length(miss)} 个: {paste(head(miss, 6), collapse = ', ')}"
    )
  }
  if (length(hit) < 1L) {
    stop("block_shap: 训练集中无可用 ML 特征列。", call. = FALSE)
  }
  keep <- unique(c(intersect("Group", names(base)), hit))
  if (!"Group" %in% keep) {
    stop("block_shap: 训练集仍无 Group 列。", call. = FALSE)
  }
  out <- base[, keep, drop = FALSE]
  if (isTRUE(attach_id)) {
    id_col <- ctx$config$data$id_column %||% NULL
    tr_full <- ctx$data$train
    if (!is.null(id_col) && nzchar(id_col) && !is.null(tr_full) &&
        id_col %in% names(tr_full) && nrow(tr_full) == nrow(out)) {
      out[[id_col]] <- tr_full[[id_col]]
    }
  }
  out
}

.shap_ml_test_frame <- function(ctx, shap_plot_only = FALSE) {
  feats <- if (isTRUE(shap_plot_only)) {
    .shap_resolve_shap_plot_features(ctx)
  } else {
    .shap_resolve_ml_feature_names(ctx)
  }
  base <- .shap_test_data_frame(ctx)
  if (is.null(base)) {
    stop("block_shap: 缺少验证数据（ml_test_data / data$test）。", call. = FALSE)
  }
  hit <- intersect(feats, names(base))
  if (!length(hit)) {
    stop("block_shap: 验证集中无可用 ML 特征列。", call. = FALSE)
  }
  keep <- unique(c(intersect("Group", names(base)), hit))
  if (!"Group" %in% keep) {
    stop("block_shap: 验证集仍无 Group 列。", call. = FALSE)
  }
  base[, keep, drop = FALSE]
}

.shap_harmonization_dir <- function(ctx) {
  cfg <- ctx$config
  dd <- cfg$dual_db %||% list()
  d <- dd$harmonization_dir %||% file.path(
    dd$checkpoint_base %||% "checkpoints", "harmonization"
  )
  root <- cfg$project$root %||% getwd()
  d <- if (grepl("^(/|[A-Za-z]:[/\\\\])", d)) d else file.path(root, d)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  normalizePath(d, winslash = "/", mustWork = FALSE)
}

.shap_export_primary_plot_features <- function(ctx, dep_feats = character(0)) {
  dd <- ctx$config$dual_db %||% list()
  sh_cfg <- ctx$config$shap %||% list()
  is_primary <- identical(dd$current_db %||% "nhanes", "nhanes") ||
    identical(ctx$config$multi_db$role %||% "primary", "primary")
  if (!isTRUE(dd$enable %||% FALSE) || !is_primary) return(invisible(NULL))
  plot_feats <- if (.shap_match_venn_features(ctx)) {
    .shap_resolve_venn_feature_names(ctx)
  } else {
    .shap_resolve_shap_plot_features(ctx)
  }
  if (!length(plot_feats)) plot_feats <- .shap_resolve_ml_feature_names(ctx)
  path <- file.path(.shap_harmonization_dir(ctx), "shap_plot_features_primary.rds")
  saveRDS(
    list(
      ml_feature_names = plot_feats,
      raw_ml_feature_names = .shap_resolve_ml_feature_names(ctx),
      index_vars = .shap_active_index_vars(ctx$config, ctx),
      dependence_features = as.character(dep_feats)[nzchar(as.character(dep_feats))],
      exported_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      database = ctx$config$project$database %||% "NHANES"
    ),
    path
  )
  cli::cli_alert_info(
    "block_shap: 已导出主库 SHAP 图特征（n={length(plot_feats)}）→ {.file {basename(path)}}"
  )
  invisible(path)
}

.shap_load_primary_plot_features <- function(ctx) {
  path <- file.path(.shap_harmonization_dir(ctx), "shap_plot_features_primary.rds")
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

.shap_train_survey_weights <- function(ctx, train_df) {
  cfg <- ctx$config
  nhanes_cfg <- cfg$nhanes %||% list()
  wt_col <- as.character(nhanes_cfg$survey_weight %||% "new_Weight")[1L]
  id_col <- cfg$data$id_column %||% "SEQN"
  imputed <- ctx$data$imputed %||% ctx$data$cleaned
  w <- rep(1, nrow(train_df))
  if (!is.null(imputed) && id_col %in% names(imputed) && wt_col %in% names(imputed) &&
      id_col %in% names(train_df)) {
    w <- as.numeric(imputed[[wt_col]][match(train_df[[id_col]], imputed[[id_col]])])
  } else if (wt_col %in% names(train_df)) {
    w <- as.numeric(train_df[[wt_col]])
  } else {
    design <- ctx$results$nhanes_design
    vars <- design$variables
    if (!is.null(vars) && id_col %in% names(vars) && wt_col %in% names(vars) &&
        id_col %in% names(train_df)) {
      w <- as.numeric(vars[[wt_col]][match(train_df[[id_col]], vars[[id_col]])])
    }
  }
  w[!is.finite(w) | w <= 0] <- 1
  w
}

# 与 block_ml_models（xgboost 等）配方一致：插补 + dummy，不用 naomit 丢行
.shap_ml_build_recipe <- function(train_dat, scale_type = "none", dummy_nominal = TRUE) {
  r <- recipes::recipe(Group ~ ., data = train_dat) |>
    recipes::step_impute_median(recipes::all_numeric_predictors()) |>
    recipes::step_impute_mode(recipes::all_nominal_predictors())
  if (isTRUE(dummy_nominal)) {
    r <- r |> recipes::step_dummy(recipes::all_nominal_predictors())
  }
  if (identical(scale_type, "center_scale")) {
    r <- r |>
      recipes::step_center(recipes::all_predictors()) |>
      recipes::step_scale(recipes::all_predictors())
  } else if (identical(scale_type, "range")) {
    r <- r |> recipes::step_range(recipes::all_predictors())
  }
  recipes::prep(r)
}

.shap_recipe_type_for_tag <- function(tag) {
  if (identical(tag, "enet") || identical(tag, "rsvm")) return("center_scale")
  if (identical(tag, "mlp")) return("range")
  "none"
}

.shap_baked_matrix <- function(ctx, tag, explain_on, sh_cfg = NULL, wf = NULL,
                               shap_plot_only = FALSE) {
  tr <- .shap_ml_train_frame(ctx, shap_plot_only = shap_plot_only)
  te <- .shap_ml_test_frame(ctx, shap_plot_only = shap_plot_only)
  explain_on <- tolower(trimws(as.character(explain_on %||% "train")[1L]))
  ## 生存模型非 tidymodels：必须用原始特征帧（含 factor），禁止 recipe dummy
  surv_raw <- exists(".shap_surv_tags", mode = "function") &&
    tag %in% .shap_surv_tags()
  raw_mode <- isTRUE((sh_cfg %||% list())$use_train_without_recipe %||% FALSE) ||
    isTRUE(surv_raw)
  rec <- NULL
  if (!raw_mode && !is.null(wf) && inherits(wf, "workflow")) {
    rec <- tryCatch(workflows::extract_recipe(wf), error = function(e) NULL)
  }
  if (raw_mode) {
    src <- if (identical(explain_on, "validation") || identical(explain_on, "test")) te else tr
    d <- src[, c("Group", setdiff(names(src), "Group")), drop = FALSE]
  } else if (!is.null(rec)) {
    if (identical(explain_on, "validation") || identical(explain_on, "test")) {
      d <- recipes::bake(rec, new_data = te) |> dplyr::select(Group, dplyr::everything())
    } else {
      d <- recipes::bake(rec, new_data = tr) |> dplyr::select(Group, dplyr::everything())
    }
  } else {
    match_venn <- .shap_match_venn_features(ctx)
    dummy_nom <- !(isTRUE(shap_plot_only) && match_venn)
    rec <- .shap_ml_build_recipe(tr, .shap_recipe_type_for_tag(tag), dummy_nominal = dummy_nom)
    if (identical(explain_on, "validation") || identical(explain_on, "test")) {
      d <- recipes::bake(rec, new_data = te) |> dplyr::select(Group, dplyr::everything())
    } else {
      d <- recipes::juice(rec) |> dplyr::select(Group, dplyr::everything())
    }
  }
  pred_cols <- setdiff(names(d), "Group")
  if (!length(pred_cols)) stop("block_shap: 烘焙后无预测列。", call. = FALSE)
  ml_feats <- .shap_resolve_ml_feature_names(ctx)
  cli::cli_alert_info(
    "block_shap: ML 特征 {length(ml_feats)} 个 → 烘焙列 {length(pred_cols)} 个（{paste(head(pred_cols, 8), collapse = ', ')}{if (length(pred_cols) > 8) ', ...' else ''}）"
  )
  X_df <- d[, pred_cols, drop = FALSE]
  ## 生存 raw：保留 factor 供 mboost/gbm/rsf；矩阵侧再数值化
  if (!isTRUE(surv_raw)) {
    for (cn in names(X_df)) {
      col <- X_df[[cn]]
      if (is.factor(col) || is.character(col)) {
        X_df[[cn]] <- as.numeric(factor(col))
      } else if (is.logical(col)) {
        X_df[[cn]] <- as.integer(col)
      } else {
        X_df[[cn]] <- suppressWarnings(as.numeric(col))
      }
    }
  }
  X_mat <- X_df
  for (cn in names(X_mat)) {
    col <- X_mat[[cn]]
    if (is.factor(col) || is.character(col)) {
      X_mat[[cn]] <- as.numeric(factor(as.character(col)))
    } else if (is.logical(col)) {
      X_mat[[cn]] <- as.integer(col)
    } else {
      X_mat[[cn]] <- suppressWarnings(as.numeric(col))
    }
  }
  X_mat <- as.matrix(X_mat)
  storage.mode(X_mat) <- "double"
  colnames(X_mat) <- pred_cols
  list(d = d, X_df = X_df, X_mat = X_mat, n = nrow(d))
}

.shap_quick_xgb_shapviz <- function(baked, y_num, wts = NULL) {
  if (!requireNamespace("xgboost", quietly = TRUE)) return(NULL)
  if (!requireNamespace("shapviz", quietly = TRUE)) return(NULL)
  X_mat <- baked$X_mat
  X_df <- baked$X_df
  if (is.null(X_mat) || !nrow(X_mat) || length(y_num) != nrow(X_mat)) return(NULL)
  wts <- as.numeric(wts %||% rep(1, nrow(X_mat)))
  if (length(wts) != nrow(X_mat)) wts <- rep(1, nrow(X_mat))
  dtrain <- tryCatch(
    xgboost::xgb.DMatrix(data = X_mat, label = as.numeric(y_num), weight = wts),
    error = function(e) NULL
  )
  if (is.null(dtrain)) return(NULL)
  fit <- tryCatch(
    xgboost::xgb.train(
      params = list(
        objective = "binary:logistic", eval_metric = "logloss",
        eta = 0.08, max_depth = 6, gamma = 1,
        subsample = 0.8, colsample_bytree = 0.8
      ),
      data = dtrain, nrounds = 80, verbose = 0
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  tryCatch(
    shapviz::shapviz(fit, X_pred = X_mat, X = X_df),
    error = function(e) NULL
  )
}

.shap_apply_font <- function(p, font_family) {
  if (is.null(p)) return(p)
  p + ggplot2::theme(
    text         = ggplot2::element_text(family = font_family),
    axis.text    = ggplot2::element_text(family = font_family),
    axis.title   = ggplot2::element_text(family = font_family),
    plot.title   = ggplot2::element_text(family = font_family),
    legend.text  = ggplot2::element_text(family = font_family),
    strip.text   = ggplot2::element_text(family = font_family)
  )
}

.shap_build_shapviz <- function(wf, X_mat, X_df) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("block_shap 需要 shapviz 包。", call. = FALSE)
  }
  fit_p <- tryCatch(
    {
      if (inherits(wf, "workflow")) {
        workflows::extract_fit_parsnip(wf)
      } else if (inherits(wf, "model_fit")) {
        wf
      } else {
        stop("不支持的模型对象类型: ", paste(class(wf), collapse = "/"))
      }
    },
    error = function(e) stop("block_shap: extract_fit_parsnip 失败: ", e$message, call. = FALSE)
  )
  eng <- tryCatch(
    parsnip::extract_fit_engine(fit_p),
    error = function(e) stop("block_shap: extract_fit_engine 失败: ", e$message, call. = FALSE)
  )
  if (inherits(eng, "xgb.Booster")) {
    fn <- tryCatch(eng$feature_names, error = function(e) NULL)
    fn <- as.character(fn %||% character(0))
    if (length(fn)) {
      miss <- setdiff(fn, colnames(X_mat))
      if (length(miss)) {
        add0 <- matrix(0, nrow = nrow(X_mat), ncol = length(miss))
        colnames(add0) <- miss
        X_mat <- cbind(X_mat, add0)
        X_df <- cbind(X_df, as.data.frame(add0, check.names = FALSE))
      }
      keep <- intersect(fn, colnames(X_mat))
      X_mat <- X_mat[, keep, drop = FALSE]
      X_df <- X_df[, keep, drop = FALSE]
    }
  }
  tryCatch(
    shapviz::shapviz(eng, X_pred = X_mat, X = X_df),
    error = function(e) {
      stop(
        "block_shap: shapviz 无法从该引擎计算 SHAP（", class(eng)[[1L]], "）：",
        e$message,
        "\n请改用 xgboost / lightgbm / rf 等树或森林模型，或检查 recipe 与矩阵列名是否与训练一致。",
        call. = FALSE
      )
    }
  )
}

.shap_dependence_features <- function(shp, sh_cfg, pred_cols, index_feats = character(0)) {
  index_feats <- intersect(as.character(index_feats)[nzchar(as.character(index_feats))], pred_cols)
  add_raw <- sh_cfg$dependence_features_add %||%
    sh_cfg$additional_dependence_features %||%
    character(0)
  add_raw <- unique(c(index_feats, as.character(add_raw)[nzchar(as.character(add_raw))]))
  add_ok <- add_raw[add_raw %in% pred_cols]
  if (length(add_raw) && !length(add_ok)) {
    cli::cli_alert_warning(
      "block_shap: dependence_features_add 与烘焙列名无交集（dummy 后为 Age_XXX 等），请用与训练烘焙后一致的列名。"
    )
  }

  explicit <- sh_cfg$dependence_features %||% NULL
  if (length(explicit)) {
    ok <- intersect(as.character(explicit), pred_cols)
    if (!length(ok)) {
      cli::cli_alert_warning("block_shap: dependence_features 与烘焙列名无交集，改为自动选取（并保留 dependence_features_add）。")
    } else {
      out <- unique(c(ok, add_ok))
      return(out)
    }
  }

  max_n <- as.integer(sh_cfg$n_dependence %||% sh_cfg$dependence_max_features %||% 4L)[1L]
  if (!is.finite(max_n) || max_n < 1L) max_n <- 4L

  add_use <- add_ok[seq_len(min(length(add_ok), max_n))]
  n_auto <- max(0L, max_n - length(add_use))
  auto_part <- character(0)
  if (n_auto > 0L) {
    sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
    if (is.null(sv) || (!is.matrix(sv) && !is.data.frame(sv))) {
      rest <- setdiff(pred_cols, add_use)
      auto_part <- rest[seq_len(min(n_auto, length(rest)))]
    } else {
      if (is.data.frame(sv)) sv <- as.matrix(sv)
      cn <- intersect(colnames(sv), pred_cols)
      if (!length(cn)) {
        rest <- setdiff(pred_cols, add_use)
        auto_part <- rest[seq_len(min(n_auto, length(rest)))]
      } else {
        imp <- sort(colMeans(abs(sv[, cn, drop = FALSE])), decreasing = TRUE)
        ranked <- names(imp)
        ranked <- setdiff(ranked, add_use)
        auto_part <- ranked[seq_len(min(n_auto, length(ranked)))]
      }
    }
  }

  unique(c(add_use, auto_part))
}

.shap_label_study <- function(study_type) {
  if (identical(tolower(trimws(study_type %||% "")), "prognosis")) "prognosis" else "incidence"
}

.shap_router_file <- {
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  file.path(normalizePath(er, winslash = "/", mustWork = FALSE), "Blocks/17_shap/00shap_router.R")
}
if (file.exists(.shap_router_file)) {
  source(.shap_router_file, local = FALSE)
}

.shap_combine_panels <- function(named_plots, combine_order, font_family, label_size, rel_heights,
                                 layout = "grid2x2") {
  if (!requireNamespace("cowplot", quietly = TRUE)) {
    stop("block_shap: combine=TRUE 需要 cowplot 包。", call. = FALSE)
  }
  ord <- intersect(combine_order, names(named_plots))
  ord <- ord[vapply(ord, function(k) !is.null(named_plots[[k]]), logical(1L))]
  if (length(ord) < 2L) return(NULL)

  .one_label <- function(p, lab) {
    cowplot::ggdraw(p) +
      cowplot::draw_label(
        lab, x = 0.02, y = 0.98, hjust = 0, vjust = 1,
        size = label_size, fontface = "bold", fontfamily = font_family
      )
  }

  ## waterfall 置顶：C 全宽在上，A|B 中，D dependence 在下
  layout <- tolower(trimws(as.character(layout %||% "grid2x2")[1L]))
  if (identical(layout, "waterfall_top") &&
      all(c("importance", "bee", "waterfall", "dependence") %in% names(named_plots)) &&
      !is.null(named_plots$importance) && !is.null(named_plots$bee) &&
      !is.null(named_plots$waterfall) && !is.null(named_plots$dependence)) {
    pA <- .one_label(named_plots$importance, "A")
    pB <- .one_label(named_plots$bee, "B")
    pC <- .one_label(named_plots$waterfall, "C")
    pD <- .one_label(named_plots$dependence, "D")
    mid <- cowplot::plot_grid(pA, pB, ncol = 2L, align = "h")
    rh <- as.numeric(rel_heights)
    if (length(rh) != 3L || any(!is.finite(rh))) rh <- c(1.15, 1.0, 1.35)
    return(cowplot::plot_grid(pC, mid, pD, ncol = 1L, rel_heights = rh, align = "none"))
  }

  ## 上行 A|B|C，下行 D（waterfall 与 importance/bee 同排，整体更紧凑）
  if (identical(layout, "abc_top") &&
      all(c("importance", "bee", "waterfall", "dependence") %in% names(named_plots)) &&
      !is.null(named_plots$importance) && !is.null(named_plots$bee) &&
      !is.null(named_plots$waterfall) && !is.null(named_plots$dependence)) {
    pA <- .one_label(named_plots$importance, "A")
    pB <- .one_label(named_plots$bee, "B")
    pC <- .one_label(named_plots$waterfall, "C")
    pD <- .one_label(named_plots$dependence, "D")
    ## C(waterfall) 略加宽，避免三等分过挤
    top <- cowplot::plot_grid(pA, pB, pC, ncol = 3L, rel_widths = c(0.95, 1.1, 1.35), align = "none")
    rh2 <- as.numeric(rel_heights)
    if (length(rh2) != 2L || any(!is.finite(rh2))) rh2 <- c(1, 1.15)
    return(cowplot::plot_grid(top, pD, ncol = 1L, rel_heights = rh2, align = "none"))
  }

  labs <- LETTERS[seq_along(ord)]
  names(labs) <- ord
  ## 默认 2×2 单页（importance / bee / waterfall / dependence）
  if (length(ord) == 4L) {
    panels <- lapply(ord, function(k) .one_label(named_plots[[k]], labs[[k]]))
    return(cowplot::plot_grid(plotlist = panels, ncol = 2L, nrow = 2L, align = "none"))
  }
  dep_name <- "dependence"
  has_dep <- dep_name %in% ord
  top_ids <- if (has_dep) ord[ord != dep_name] else ord

  if (has_dep && length(top_ids)) {
    row1_k <- top_ids[seq_len(min(3L, length(top_ids)))]
    row1 <- lapply(row1_k, function(k) .one_label(named_plots[[k]], labs[[k]]))
    p_bot <- .one_label(named_plots[[dep_name]], labs[[dep_name]])
    top_g <- cowplot::plot_grid(plotlist = row1, ncol = length(row1), align = "none")
    rh2 <- as.numeric(rel_heights)
    if (length(rh2) != 2L || any(!is.finite(rh2))) rh2 <- c(1, 1)
    cowplot::plot_grid(top_g, p_bot, ncol = 1L, rel_heights = rh2)
  } else {
    row <- lapply(ord, function(k) .one_label(named_plots[[k]], labs[[k]]))
    cowplot::plot_grid(plotlist = row, ncol = min(2L, length(row)), align = "h")
  }
}

block_shap <- function(ctx, ...) {
  cfg <- ctx$config
  sh <- cfg$shap %||% list()
  if (isFALSE(sh$enable %||% TRUE)) {
    cli::cli_alert_info("config$shap$enable=FALSE，跳过 SHAP。")
    return(ctx)
  }

  prim_feats <- .shap_load_primary_plot_features(ctx)
  if (!is.null(prim_feats) && length(prim_feats$ml_feature_names)) {
    inherited <- as.character(prim_feats$ml_feature_names)
    present <- intersect(inherited, names(ctx$data$imputed %||% ctx$data$train %||% list()))
    if (length(present)) {
      ctx$results$shap_plot_feature_names <- present
      cli::cli_alert_info(
        "block_shap: 验证库对齐主库 SHAP 图特征 n={length(present)}（来自 shap_plot_features_primary.rds）"
      )
    }
    dep_prim <- as.character(prim_feats$dependence_features %||% character(0))
    dep_prim <- dep_prim[nzchar(dep_prim)]
    if (length(dep_prim) && is.null(sh$dependence_features)) {
      sh$dependence_features_add <- unique(c(
        as.character(sh$dependence_features_add %||% character(0)),
        dep_prim
      ))
    }
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  st_lab <- .shap_label_study(study_type)
  font_family <- plot_font_from_config(list(
    plot = list(font_family = sh$font_family %||% cfg$plot$font_family %||% "Times New Roman")
  ))

  models <- ctx$results$ml_models %||% list()
  if (!length(models)) stop("block_shap: ctx$results$ml_models 为空，请先运行 ml_models。", call. = FALSE)

  shap_res <- .shap_try_compute_best(ctx, sh, models)
  tag <- shap_res$tag
  shp <- shap_res$shp
  baked <- shap_res$baked
  shap_method <- shap_res$method
  shap_source_row_ids <- attr(shp, "shap_source_row_ids", exact = TRUE)

  if (is.null(shp) || is.null(tag)) {
    err_msg <- shap_res$error %||% "无可用方法"
    cli::cli_alert_warning(
      "block_shap: 所有已训练模型 SHAP 均失败（{err_msg}），已跳过。"
    )
    return(ctx)
  }

  explain_on <- sh$explain_on %||% "train"
  X_mat <- baked$X_mat
  X_df  <- baked$X_df
  X_df <- .shap_feature_matrix_aligned(shp, X_df)
  if (!is.null(X_mat) && nrow(X_mat) != nrow(X_df)) {
    X_mat <- X_mat[seq_len(nrow(X_df)), , drop = FALSE]
  }
  pred_cols <- colnames(X_mat)
  index_feats <- .shap_active_index_vars(cfg, ctx)

  sh_model_choice <- tolower(trimws(as.character(sh$ml_model %||% sh$model %||% "auto")[1L]))
  # 韦恩对齐：默认可用 TreeSHAP(xgboost) 画发表图；
  # 但 force_kernel_best_model=TRUE / 预后：必须解释最优模型，禁止换成 xgboost
  use_tree_viz <- !isTRUE(sh$force_kernel_best_model %||% FALSE) &&
    (isTRUE(sh$prefer_tree_shapviz %||% TRUE) ||
      identical(sh_model_choice, "xgboost") ||
      !(tag %in% c("xgboost", "lightgbm", "rf", "catboost", "dt", "adaboost", .shap_surv_tags())))
  if (identical(tolower(trimws(study_type)), "prognosis")) {
    use_tree_viz <- FALSE
  }
  if (.shap_match_venn_features(ctx) && use_tree_viz) {
    plot_baked <- tryCatch(
      .shap_baked_matrix(ctx, "xgboost", explain_on, sh_cfg = sh, shap_plot_only = TRUE),
      error = function(e) NULL
    )
    if (!is.null(plot_baked)) {
      tr_ix <- .shap_ml_train_frame(ctx, shap_plot_only = TRUE)
      y_chr <- trimws(as.character(tr_ix$Group))
      ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
      y_num <- as.integer(y_chr == trimws(ana_group))
      shp_v <- .shap_quick_xgb_shapviz(plot_baked, y_num)
      if (!is.null(shp_v)) {
        cli::cli_alert_info(
          "block_shap: 韦恩对齐发表图使用 TreeSHAP/xgboost（{ncol(plot_baked$X_mat)} 列；最优预测模型={tag}）"
        )
        shp <- shp_v
        baked <- plot_baked
        X_mat <- baked$X_mat
        X_df <- baked$X_df
        pred_cols <- colnames(X_mat)
        # 标题/文件名用 XGBoost（实际解释的模型）；最优预测模型仍记在 results
        ctx$results$shap_best_predictive_tag <- tag
        tag <- "xgboost"
        shap_method <- "venn_xgb_shapviz"
      }
    }
  }

  # 若仍是 kernel 最优模型路径：workflow 全列后聚合回韦恩特征
  if (.shap_match_venn_features(ctx) && !identical(shap_method, "venn_xgb_shapviz")) {
    collapsed <- .shap_collapse_shapviz_to_venn_features(shp, X_df, ctx)
    if (!is.null(collapsed$shp)) {
      n_venn <- ncol(collapsed$X_df)
      cli::cli_alert_info(
        "block_shap: 韦恩 SHAP 已聚合为 ML 最终特征 n={n_venn}（分类 dummy 列 SHAP 求和）"
      )
      shp <- collapsed$shp
      X_df <- collapsed$X_df
      if (!is.null(collapsed$X_mat)) X_mat <- collapsed$X_mat
      pred_cols <- colnames(X_df)
      shap_method <- paste0(shap_method, "_venn_collapse")
    }
  }

  missing_ix <- setdiff(index_feats, pred_cols)
  if (length(missing_ix) &&
      isTRUE(sh$force_index_in_plot %||% TRUE) &&
      !.shap_match_venn_features(ctx)) {
    plot_baked <- tryCatch(
      .shap_baked_matrix(ctx, "xgboost", explain_on, sh_cfg = sh, shap_plot_only = TRUE),
      error = function(e) NULL
    )
    if (!is.null(plot_baked)) {
      tr_ix <- .shap_ml_train_frame(ctx, shap_plot_only = TRUE)
      y_chr <- trimws(as.character(tr_ix$Group))
      ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
      y_num <- as.integer(y_chr == trimws(ana_group))
      shp_ix <- .shap_quick_xgb_shapviz(plot_baked, y_num)
      if (!is.null(shp_ix)) {
        cli::cli_alert_info(
          "block_shap: 分析指标未进入 ML 模型 SHAP，已改用 numeric+指标 xgboost 展示（{paste(index_feats, collapse = ', ')}）"
        )
        shp <- shp_ix
        baked <- plot_baked
        X_mat <- baked$X_mat
        X_df <- baked$X_df
        pred_cols <- colnames(X_mat)
        shap_method <- "index_xgb_shapviz"
      }
    }
  }

  plot_cols <- .shap_filter_plot_columns(ctx, pred_cols, sh)
  if (length(plot_cols) && !identical(plot_cols, pred_cols)) {
    shp <- .shap_subset_shapviz(shp, plot_cols, X_df)
    X_df <- .shap_feature_matrix_aligned(shp, X_df)
    plot_cols <- intersect(plot_cols, colnames(X_df))
    X_df <- X_df[, plot_cols, drop = FALSE]
    X_mat <- X_mat[, plot_cols, drop = FALSE]
    pred_cols <- plot_cols
  }
  pretty <- .shap_apply_pretty_display(shp, X_df, X_mat)
  shp <- pretty$shp
  X_df <- pretty$X_df
  if (!is.null(pretty$X_mat)) X_mat <- pretty$X_mat
  pred_cols <- colnames(X_df)
  # C/D 面板直接显示临床类别标签（如 Female/Male、No/Yes），
  # A/B 仍保留数值型特征值以维持连续色阶。
  shp_clinical <- .shap_apply_clinical_value_labels(shp, X_df, ctx)
  clinical_labels_applied <- !identical(shp_clinical, shp)

  top_n <- as.integer(sh$top_n %||% 10L)[1L]
  if (!is.finite(top_n) || top_n < 1L) top_n <- 10L
  if (.shap_match_venn_features(ctx)) {
    vn <- length(.shap_resolve_venn_feature_names(ctx))
    if (vn > 0L) top_n <- max(top_n, vn)
  }

  wf_res <- .shap_resolve_waterfall_row_id(
    ctx, sh, tag, nrow(X_df), tr_frame = NULL,
    source_row_ids = shap_source_row_ids
  )
  wf_row <- if (is.list(wf_res)) wf_res$row_id else wf_res
  if (is.list(wf_res) && !is.null(wf_res$pick)) {
    ctx$results$shap_waterfall_pick <- wf_res$pick
    ctx$results$shap_waterfall_incidence <- wf_res$pick$incidence
  }

  plots_wanted <- tolower(trimws(as.character(sh$plots %||% c(
    "importance", "bee", "waterfall", "dependence"
  ))))
  if (!length(plots_wanted)) plots_wanted <- c("importance", "bee", "waterfall", "dependence")

  show_numbers <- isTRUE(sh$importance_show_numbers %||% TRUE)
  save_each <- !isFALSE(sh$save_individual %||% TRUE)
  model_disp <- .shap_model_display_name(ctx, tag)
  # 拼图也保留短标题；模型名接在标题后，不写 (mlp, incidence, train)
  show_panel_titles <- !isFALSE(sh$show_panel_titles %||% TRUE)
  .panel_title <- function(base) paste0(base, " — ", model_disp)

  # 颜色统一：从 config$shap$bee_color_low/high 读取，NULL 时保持 shapviz 默认
  sh_bee_low  <- sh$bee_color_low  %||% NULL
  sh_bee_high <- sh$bee_color_high %||% NULL
  imp_order <- .shap_resolve_importance_display_order(shp, sh, index_feats)

  built <- list()
  if ("importance" %in% plots_wanted) {
    p_imp <- shapviz::sv_importance(shp, show_numbers = show_numbers, max_display = top_n)
    p_imp <- .shap_apply_importance_display_order(p_imp, imp_order)
    if (show_panel_titles) {
      p_imp <- p_imp + ggplot2::labs(title = .panel_title("SHAP importance"))
    }
    p_imp <- .shap_panel_finish(p_imp, font_family, sh, keep_title = show_panel_titles)
    # A 图 bar 色 = bee_color_high（与 B 图高值颜色统一）
    if (!is.null(sh_bee_high)) {
      p_imp <- tryCatch({
        p_imp$layers[[1L]]$aes_params$fill <- sh_bee_high
        p_imp
      }, error = function(e) p_imp)
    }
    built$importance <- p_imp
  }
  if ("bee" %in% plots_wanted) {
    p_bee_plot <- shapviz::sv_importance(shp, kind = "bee", max_display = top_n)
    p_bee_plot <- .shap_apply_importance_display_order(p_bee_plot, imp_order)
    if (show_panel_titles) {
      p_bee_plot <- p_bee_plot + ggplot2::labs(title = .panel_title("SHAP bee swarm"))
    }
    p_bee_plot <- .shap_panel_finish(p_bee_plot, font_family, sh, keep_title = show_panel_titles)
    if (!is.null(sh_bee_low) && !is.null(sh_bee_high)) {
      p_bee_plot <- tryCatch(
        p_bee_plot +
          ggplot2::scale_color_gradient(low = sh_bee_low, high = sh_bee_high,
                                        na.value = sh_bee_high),
        error = function(e) p_bee_plot
      )
    }
    built$bee <- p_bee_plot
  }
  if ("waterfall" %in% plots_wanted) {
    p_wf <- .shap_waterfall_with_labels(shp_clinical, wf_row, sh, ctx)
    if (!is.null(p_wf)) {
      if (show_panel_titles) {
        p_wf <- p_wf + ggplot2::labs(title = .panel_title(paste0("SHAP waterfall, row ", wf_row)))
      }
      built$waterfall <- .shap_panel_finish(p_wf, font_family, sh, keep_title = show_panel_titles)
    }
  }

  dep_feats <- character(0)
  if ("dependence" %in% plots_wanted) {
    dep_feats <- tryCatch(
      .shap_dependence_features(shp, sh, pred_cols, index_feats = index_feats),
      error = function(e) {
        cli::cli_alert_warning("block_shap: dependence 特征解析失败: {conditionMessage(e)}")
        character(0)
      }
    )
    dep_list <- list()
    for (j in seq_along(dep_feats)) {
      fj <- dep_feats[[j]]
      p_dep_j <- tryCatch(
        shapviz::sv_dependence(shp_clinical, v = fj),
        error = function(e) {
          cli::cli_alert_warning("block_shap: dependence[{fj}] 跳过（{conditionMessage(e)}）")
          NULL
        }
      )
      if (is.null(p_dep_j)) next
      if (show_panel_titles) {
        p_dep_j <- p_dep_j + ggplot2::labs(title = paste0("SHAP dependence: ", fj))
      }
      p_dep_j <- .shap_panel_finish(p_dep_j, font_family, sh, keep_title = show_panel_titles)
      if (!clinical_labels_applied && !is.null(sh_bee_low) && !is.null(sh_bee_high)) {
        p_dep_j <- tryCatch(
          p_dep_j +
            ggplot2::scale_color_gradient(low = sh_bee_low, high = sh_bee_high,
                                          na.value = sh_bee_high),
          error = function(e) p_dep_j
        )
      }
      dep_list[[fj]] <- p_dep_j
    }
    if (length(dep_list) >= 1L) {
      built$dependence <- if (length(dep_list) == 1L) {
        dep_list[[1L]]
      } else if (!requireNamespace("cowplot", quietly = TRUE)) {
        dep_list[[1L]]
      } else {
        dep_ncol <- as.integer(sh$dependence_ncol %||% 2L)[1L]
        if (!is.finite(dep_ncol) || dep_ncol < 1L) dep_ncol <- 2L
        cowplot::plot_grid(
          plotlist = dep_list,
          ncol = min(dep_ncol, length(dep_list)),
          align = "hv"
        )
      }
      ctx$results$shap_dependence_features_used <- dep_feats
      jj <- 1L
      for (nm in names(dep_list)) {
        if (!save_each) next
        nm_safe <- gsub("[^A-Za-z0-9._-]+", "_", nm, perl = TRUE)
        fn <- sprintf("Figure_SHAP_%s_%s_dependence_%02d_%s.pdf", tag, st_lab, jj, nm_safe)
        # plot_fn 只 return 图形对象；render_queued_figures 会 print，内部再 print 会落成双页
        ctx <- save_figure(ctx, fn, local({
          gg <- dep_list[[nm]]
          function() gg
        }), width = as.numeric(sh$dependence_single_width %||% 6), height = as.numeric(sh$dependence_single_height %||% 5))
        jj <- jj + 1L
      }
    } else {
      cli::cli_alert_warning("block_shap: 无可用 dependence 特征，跳过 dependence 子图。")
    }
  }

  study_note <- paste0(
    "Note: SHAP explains the fitted Group classifier (same as ml_models). ",
    "Filename tag \"", st_lab, "\" reflects config$project$study_type only."
  )

  if (save_each) {
    for (nm in names(built)) {
      if (identical(nm, "dependence")) next
      fn <- sprintf("Figure_SHAP_%s_%s_%s.pdf", tag, st_lab, nm)
      ctx <- save_figure(ctx, fn, local({
        gg <- built[[nm]]
        function() gg
      }), width = as.numeric(sh$single_width %||% 6), height = as.numeric(sh$single_height %||% 6))
    }
  }

  combine <- isTRUE(sh$combine %||% TRUE)
  combine_order <- tolower(trimws(as.character(sh$combine_plots %||% c(
    "importance", "bee", "waterfall", "dependence"
  ))))
  combine_order <- intersect(combine_order, plots_wanted)
  cfn <- sh$combine_filename %||% pub_figure_file(
    ctx, "main_figure",
    paste0("SHAP — ", model_disp)
  )

  if (combine && length(intersect(combine_order, names(built))) >= 2L) {
    layout <- tolower(trimws(as.character(sh$combine_layout %||% "grid2x2")[1L]))
    rel_h_default <- if (identical(layout, "waterfall_top")) {
      c(1.15, 1, 1.35)
    } else if (identical(layout, "abc_top")) {
      c(1, 1.05)
    } else {
      c(1, 1)
    }
    rel_h <- as.numeric(sh$combine_rel_heights %||% rel_h_default)
    if (identical(layout, "waterfall_top") && length(rel_h) != 3L) rel_h <- c(1.15, 1, 1.35)
    if (identical(layout, "abc_top") && length(rel_h) != 2L) rel_h <- c(1, 1.05)
    if (!layout %in% c("waterfall_top", "abc_top") && length(rel_h) != 2L) rel_h <- c(1, 1)
    label_size <- as.numeric(sh$combine_label_size %||% 10)
    comb <- tryCatch(
      .shap_combine_panels(
        built, combine_order, font_family, label_size, rel_h,
        layout = layout
      ),
      error = function(e) {
        cli::cli_alert_warning("block_shap: 拼图失败 ({e$message})，跳过 combined。")
        NULL
      }
    )
    if (!is.null(comb)) {
      cli::cli_alert_info(study_note)
      def_w <- if (identical(layout, "waterfall_top")) 14 else if (identical(layout, "abc_top")) 17 else 16
      def_h <- if (identical(layout, "waterfall_top")) 17 else if (identical(layout, "abc_top")) 11 else 11
      ctx <- save_figure(
        ctx, cfn,
        local({
          gg <- comb
          function() gg
        }),
        width  = as.numeric(sh$combined_width  %||% def_w),
        height = as.numeric(sh$combined_height %||% def_h)
      )
    }
  } else if (combine) {
    # 面板不足（< 2），删除可能存在的旧 combined 文件，避免旧图误导
    fig_dir_c <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    old_cfn <- file.path(fig_dir_c, cfn)
    if (file.exists(old_cfn)) {
      unlink(old_cfn)
      cli::cli_alert_info("block_shap: 可用面板不足，已删除旧 combined 文件: {basename(old_cfn)}")
    }
  }

  ctx <- render_queued_figures(ctx)
  ctx$results$shap_model_tag <- tag
  ctx$results$shap_method <- shap_method
  ctx$results$shap_study_label <- st_lab
  ctx$results$shap_explain_on <- explain_on
  ctx$results$shapviz <- shp
  ctx$results$shap_mean_abs <- tryCatch({
    sv <- shapviz::get_shap_values(shp)
    if (is.data.frame(sv)) sv <- as.matrix(sv)
    sort(colMeans(abs(sv)), decreasing = TRUE)
  }, error = function(e) NULL)
  ctx$results$shap_ml_feature_names <- .shap_resolve_shap_raw_features(ctx)
  .shap_export_primary_plot_features(ctx, ctx$results$shap_dependence_features_used %||% character(0))
  cli::cli_alert_success(
    "block_shap 完成（模型={tag}，method={shap_method}，study_type={study_type}，explain_on={explain_on}）"
  )
  ctx
}

# ─────────────────────────────────────────────────────────────────────────────
#  NHANES 加权 SHAP — 与 ML 相同特征（ml_feature_names）+ 相同 recipe 烘焙 + 调查权重
# ─────────────────────────────────────────────────────────────────────────────
.block_shap_nhanes_weighted <- function(ctx) {
  cfg        <- ctx$config
  sh_cfg     <- cfg$shap %||% list()
  nhanes_cfg <- cfg$nhanes %||% list()
  proj_cfg   <- cfg$project %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  wt_col      <- as.character(nhanes_cfg$survey_weight %||% "new_Weight")[1L]

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    cli::cli_alert_warning("block_shap(NHANES): nhanes_design 为空，跳过。")
    return(ctx)
  }
  if (requireNamespace("xgboost", quietly = TRUE)) {
    best_tag <- "xgboost"
  } else if (requireNamespace("lightgbm", quietly = TRUE)) {
    best_tag <- "lightgbm"
  } else {
    cli::cli_alert_warning("block_shap(NHANES): 需要 xgboost 或 lightgbm，跳过加权树 SHAP。")
    return(ctx)
  }
  cli::cli_alert_info(
    "block_shap(NHANES): 使用 {best_tag} + new_Weight 样本权重训练专用 SHAP 模型。"
  )
  pkgs <- c("shapviz", "caTools", "ggplot2", if (best_tag == "lightgbm") "lightgbm" else "xgboost")
  for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      cli::cli_alert_warning("block_shap(NHANES): 需要 {pkg}，跳过。"); return(ctx)
    }
  }
  suppressPackageStartupMessages({
    library(shapviz); library(caTools); library(ggplot2)
    if (best_tag == "lightgbm") library(lightgbm) else library(xgboost)
  })

  data_all <- design$variables

  ml_feats <- .shap_resolve_shap_raw_features(ctx)
  if (!length(ml_feats)) {
    cli::cli_alert_warning("block_shap(NHANES): 无 SHAP 数值特征清单，跳过加权 SHAP。")
    return(ctx)
  }
  train_ml <- tryCatch(
    .shap_ml_train_frame(ctx, attach_id = TRUE, shap_plot_only = TRUE),
    error = function(e) {
      cli::cli_alert_warning("block_shap(NHANES): {conditionMessage(e)}")
      NULL
    }
  )
  if (is.null(train_ml)) return(ctx)

  baked <- tryCatch(
    .shap_baked_matrix(
      ctx, best_tag, sh_cfg$explain_on %||% "train",
      sh_cfg = sh_cfg, shap_plot_only = TRUE
    ),
    error = function(e) {
      cli::cli_alert_warning("block_shap(NHANES): 烘焙 ML 矩阵失败 ({conditionMessage(e)})")
      NULL
    }
  )
  if (is.null(baked)) return(ctx)

  xgb_vars <- colnames(baked$X_mat)
  cli::cli_alert_info(
    "NHANES SHAP 变量（数值协变量+指标，烘焙后 {length(xgb_vars)} 列）: {paste(head(xgb_vars, 12), collapse = ', ')}{if (length(xgb_vars) > 12) ', ...' else ''}"
  )

  ana_group <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  ref_group <- proj_cfg$reference_group %||% "Control"
  y_chr <- trimws(as.character(train_ml$Group))
  y_num <- as.integer(y_chr == trimws(ana_group))
  wts <- .shap_train_survey_weights(ctx, train_ml)

  X_mat <- baked$X_mat
  if (nrow(X_mat) < 30L) {
    cli::cli_alert_warning("block_shap(NHANES): 训练样本不足，跳过。")
    return(ctx)
  }

  set.seed(123L)
  split <- caTools::sample.split(y_num, SplitRatio = 0.7)
  X_train <- X_mat[split, , drop = FALSE]
  X_test  <- X_mat[!split, , drop = FALSE]
  y_train <- y_num[split]
  y_test  <- y_num[!split]
  w_train <- wts[split]
  w_test  <- wts[!split]

  dtrain <- if (best_tag == "lightgbm") {
    lightgbm::lgb.Dataset(data = X_train, label = y_train, weight = w_train)
  } else {
    xgboost::xgb.DMatrix(data = X_train, label = y_train, weight = w_train)
  }
  dtest <- if (best_tag == "lightgbm") {
    lightgbm::lgb.Dataset(data = X_test, label = y_test, weight = w_test)
  } else {
    xgboost::xgb.DMatrix(data = X_test, label = y_test, weight = w_test)
  }

  params <- if (best_tag == "lightgbm") {
    list(
      objective = "binary", metric = "binary_logloss",
      learning_rate = 0.08, max_depth = 6, min_gain_to_split = 1,
      subsample = 0.8, colsample_bytree = 0.8)
  } else {
    list(
      objective = "binary:logistic", eval_metric = "logloss",
      eta = 0.08, max_depth = 6, gamma = 1,
      subsample = 0.8, colsample_bytree = 0.8)
  }
  xgb_model <- tryCatch(
    if (best_tag == "lightgbm") {
      lightgbm::lgb.train(
        params, dtrain, nrounds = 200,
        valids = list(train = dtrain, test = dtest),
        early_stopping_rounds = 10, verbose = -1)
    } else {
      xgboost::xgb.train(
        params, dtrain, nrounds = 200,
        watchlist = list(train = dtrain, test = dtest),
        early_stopping_rounds = 10, print_every_n = 50, verbose = 0)
    },
    error = function(e) {
      cli::cli_alert_warning("NHANES {best_tag} 训练失败: {e$message}"); NULL })
  if (is.null(xgb_model)) return(ctx)

  fit_shap <- tryCatch(
    if (best_tag == "lightgbm") {
      lightgbm::lgb.train(
        list(objective = "binary", learning_rate = 0.08),
        dtrain, nrounds = 6, verbose = -1)
    } else {
      xgboost::xgb.train(
        list(objective = "binary:logistic", learning_rate = 0.08),
        dtrain, nrounds = 6, verbose = 0)
    },
    error = function(e) xgb_model)

  # 字体：优先 shap/font 配置；WSL 环境下避免硬编码 Times New Roman 导致 invalid font type
  shp_font <- sh_cfg$font_family %||% (cfg$plot %||% list())$font_family %||% "sans"

  # Random color selection (C01_Xgboost 风格)
  bar_colors <- c("#4DBBD5","#E64B35","#00A087","#3C5488","#F39B7F",
                  "#8491B4","#91D1C2","#DC0000","#7E6148","#B09C85")
  bee_palettes <- list(
    list(low="#2166AC", high="#D73027"),
    list(low="#1A9850", high="#D73027"),
    list(low="#4575B4", high="#D6604D"),
    list(low="#5AAE61", high="#9970AB"),
    list(low="#762A83", high="#1B7837"))
  # 优先读 config$shap$bee_color_low/high；未设置则随机选预设调色盘
  cfg_bee_low  <- sh_cfg$bee_color_low  %||% NULL
  cfg_bee_high <- sh_cfg$bee_color_high %||% NULL
  if (!is.null(cfg_bee_low) && !is.null(cfg_bee_high)) {
    bee_pal <- list(low = cfg_bee_low, high = cfg_bee_high)
  } else {
    set.seed(as.integer(Sys.time()) %% 1000L)
    bee_pal <- bee_palettes[[sample(length(bee_palettes), 1L)]]
  }
  # A 图 bar 用 bee_pal$high（暖色端），与 B 图"Feature value High"颜色统一
  bar_col <- bee_pal$high

  shp <- tryCatch(
    shapviz::shapviz(
      fit_shap,
      X_pred = X_train,
      X      = as.data.frame(X_train, check.names = FALSE)
    ),
    error = function(e) {
      cli::cli_alert_warning("NHANES SHAP 计算失败: {e$message}"); NULL })
  if (is.null(shp)) return(ctx)

  index_feats <- .shap_active_index_vars(cfg, ctx)
  if (.shap_match_venn_features(ctx)) {
    venn_feats <- .shap_resolve_venn_feature_names(ctx)
    index_feats <- intersect(index_feats, venn_feats)
    if (!length(index_feats)) index_feats <- intersect(venn_feats, xgb_vars)
  }
  X_train_df <- as.data.frame(X_train, check.names = FALSE)
  plot_cols <- .shap_filter_plot_columns(ctx, colnames(X_train), sh_cfg)
  if (length(plot_cols) && !identical(plot_cols, colnames(X_train))) {
    shp <- .shap_subset_shapviz(shp, plot_cols, X_train_df)
    X_train_df <- X_train_df[, plot_cols, drop = FALSE]
    xgb_vars <- plot_cols
  }
  pretty_nh <- .shap_apply_pretty_display(shp, X_train_df, NULL)
  shp <- pretty_nh$shp
  X_train_df <- pretty_nh$X_df
  xgb_vars <- colnames(X_train_df)

  .tnr <- function()
    list(ggplot2::theme(
      text       = ggplot2::element_text(family = shp_font),
      axis.text  = ggplot2::element_text(family = shp_font),
      axis.title = ggplot2::element_text(family = shp_font),
      plot.title = ggplot2::element_text(family = shp_font)))

  top_n   <- as.integer(sh_cfg$top_n %||% 10L)[1L]
  if (!is.finite(top_n) || top_n < 1L) top_n <- 10L
  if (.shap_match_venn_features(ctx)) {
    vn <- length(.shap_resolve_venn_feature_names(ctx))
    if (vn > 0L) top_n <- max(top_n, vn)
  }
  wf_res  <- .shap_resolve_waterfall_row_id(ctx, sh_cfg, best_tag, nrow(X_train), tr_frame = NULL)
  wf_row <- if (is.list(wf_res)) wf_res$row_id else wf_res
  if (is.list(wf_res) && !is.null(wf_res$pick)) {
    ctx$results$shap_waterfall_pick <- wf_res$pick
    ctx$results$shap_waterfall_incidence <- wf_res$pick$incidence
  }
  n_dep   <- as.integer(sh_cfg$n_dependence %||% 4L)[1L]
  if (!is.finite(n_dep) || n_dep < 1L) n_dep <- 4L

  p_bar <- tryCatch({
    p <- shapviz::sv_importance(shp, show_numbers = FALSE, max_display = top_n) + .tnr()
    p <- .shap_apply_importance_display_order(
      p, .shap_resolve_importance_display_order(shp, sh_cfg, index_feats)
    )
    p$layers[[1]]$aes_params$fill <- bar_col
    p + ggplot2::labs(tag = "A", title = NULL) +
      ggplot2::theme(plot.tag.position = c(0, 1))
  }, error = function(e) NULL)

  p_bee <- tryCatch({
    pb <- shapviz::sv_importance(shp, kind = "bee", max_display = top_n,
                           color_bar_title = "Feature value")
    pb <- .shap_apply_importance_display_order(
      pb, .shap_resolve_importance_display_order(shp, sh_cfg, index_feats)
    )
    pb +
      ggplot2::scale_color_gradient(low = bee_pal$low, high = bee_pal$high,
                                    breaks = c(0, 1), labels = c("Low", "High")) +
      .tnr() +
      ggplot2::labs(tag = "B", title = NULL) +
      ggplot2::theme(plot.tag.position = c(0.05, 1))
  }, error = function(e) NULL)

  p_waterfall <- tryCatch({
    pw <- .shap_waterfall_with_labels(shp, wf_row, sh_cfg, ctx) + .tnr()
    cur_sub <- tryCatch(pw$labels$subtitle, error = function(e) NULL)
    pw + ggplot2::labs(tag = "C", title = NULL, subtitle = cur_sub) +
      ggplot2::theme(plot.tag.position = c(0, 1))
  }, error = function(e) NULL)

  # D：dependence 子图（优先暴露指标，再按 |SHAP| 补足；与 MIMIC combined 一致）
  pred_cols_dep <- xgb_vars
  if (!length(pred_cols_dep)) pred_cols_dep <- colnames(X_train)
  dep_index <- if (.shap_match_venn_features(ctx)) {
    intersect(.shap_active_index_vars(cfg, ctx), pred_cols_dep)
  } else {
    index_feats
  }
  dep_vars <- .shap_dependence_features(shp, sh_cfg, pred_cols_dep, index_feats = dep_index)
  if (!length(dep_vars)) dep_vars <- head(pred_cols_dep, min(n_dep, length(pred_cols_dep)))
  dep_vars <- head(unique(dep_vars), n_dep)
  p_dep <- if (length(dep_vars)) {
    tryCatch({
      dep_plots <- lapply(seq_along(dep_vars), function(i) {
        v <- dep_vars[[i]]
        shapviz::sv_dependence(shp, v = v) +
          ggplot2::scale_color_gradient(low = bee_pal$low, high = bee_pal$high,
                                        na.value = bee_pal$high) +
          .tnr() +
          ggplot2::labs(title = NULL, tag = if (i == 1L) "D" else NULL) +
          ggplot2::theme(plot.tag.position = c(0, 1))
      })
      if (requireNamespace("cowplot", quietly = TRUE)) {
        cowplot::plot_grid(plotlist = dep_plots, ncol = min(4L, length(dep_plots)), align = "hv")
      } else {
        dep_plots[[1L]]
      }
    }, error = function(e) {
      cli::cli_alert_warning("NHANES SHAP dependence 拼图失败: {conditionMessage(e)}")
      NULL
    })
  } else {
    cli::cli_alert_warning("NHANES SHAP: 无可用 dependence 变量（pred_cols={length(pred_cols_dep)}）")
    NULL
  }

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  fig_name <- pub_figure_file(ctx, "main_figure", paste0(
    "Weighted SHAP (NHANES) for ",
    proj_cfg$disease %||% "outcome"
  ))
  fig_path <- file.path(fig_dir, fig_name)

  top_panels <- Filter(Negate(is.null), list(A = p_bar, B = p_bee, C = p_waterfall))
  if (is.null(p_dep) && length(top_panels) >= 2L) {
    cli::cli_alert_warning("NHANES SHAP: 缺少 dependence 行，combined 图将不完整。")
  }

  if (length(top_panels) > 0) {
    tryCatch({
      # 上行：A B C；下行：D（dependence）
      if (requireNamespace("cowplot", quietly = TRUE) &&
          !is.null(p_dep) && length(top_panels) >= 2L) {
        top_row <- cowplot::plot_grid(
          plotlist = lapply(seq_along(top_panels), function(i) top_panels[[i]]),
          ncol = length(top_panels), align = "h"
        )
        combined <- cowplot::plot_grid(top_row, p_dep, ncol = 1L,
                                       rel_heights = c(1, 1.2))
        grDevices::cairo_pdf(fig_path,
          height = as.numeric(sh_cfg$combined_height %||% 12),
          width  = as.numeric(sh_cfg$combined_width  %||% 16),
          family = shp_font)
      } else if (requireNamespace("patchwork", quietly = TRUE) &&
                 length(top_panels) >= 2L) {
        suppressPackageStartupMessages(library(patchwork, warn.conflicts = FALSE))
        combined <- Reduce(`+`, top_panels)
        grDevices::cairo_pdf(fig_path, height = 6, width = 10 * length(top_panels) / 2,
                             family = shp_font)
      } else {
        combined <- top_panels[[1L]]
        grDevices::cairo_pdf(fig_path, height = 6, width = 10, family = shp_font)
      }
      print(combined)
      grDevices::dev.off()
      cli::cli_alert_success("NHANES SHAP 图保存: {.file {basename(fig_path)}}")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("NHANES SHAP 图保存失败: {e$message}")
    })
  }

  ctx$results$nhanes_shap <- list(
    model = xgb_model, shap = shp, vars = xgb_vars,
    ml_feature_names = ml_feats, bar_col = bar_col, bee_pal = bee_pal, model_tag = best_tag
  )
  ctx$results$shap_ml_feature_names <- ml_feats
  ctx$results$shap_dependence_features_used <- dep_vars %||% character(0)
  .shap_export_primary_plot_features(ctx, ctx$results$shap_dependence_features_used)
  cli::cli_alert_success("block_shap(NHANES {best_tag} 加权) 完成。")
  ctx
}

# 覆盖 register：NHANES 默认仅跑加权 SHAP（Fig 4）；MIMIC/regular 跑 tidymodels 拼图 SHAP
.block_shap_orig <- block_shap
block_shap <- function(ctx, ...) {
  sh_cfg <- ctx$config$shap %||% list()
  run_nhanes_w <- sh_cfg$run_nhanes_weighted
  if (is.null(run_nhanes_w)) run_nhanes_w <- TRUE
  is_nhanes <- exists(".is_nhanes_db", mode = "function") && .is_nhanes_db(ctx$config)
  if (isTRUE(run_nhanes_w) && is_nhanes) {
    cli::cli_h2("block_shap(NHANES): 加权 SHAP（new_Weight 样本权重）")
    ctx <- .block_shap_nhanes_weighted(ctx)
  } else {
    ctx <- .block_shap_orig(ctx, ...)
  }
  ctx
}

register_block("shap", block_shap,
  "基于 ml_models 的 SHAP 图（可选拼图）; NHANES 加权 XGBoost SHAP (new_Weight 样本权重) appended")
