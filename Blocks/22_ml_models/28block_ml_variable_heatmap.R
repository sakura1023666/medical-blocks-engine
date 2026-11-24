###############################################################################
#  ml_variable_heatmap — ML 预测变量总览热图（患者×临床变量 + 结局/数据集/预测概率）
#
#  对齐旧 ROP 交付 Figure 5「Variable heatmap of the TabPFN model…」：
#  - 列为个体，行为临床变量；底部附加 Group / dataset / <Model>_predicted_value
#  - 默认解释验证集 AUC 最优模型（常为 TabPFN）；可用 config 指定
#
#  参考实现：ComplexHeatmap 多样本注释热图
#  https://jokergoo.github.io/ComplexHeatmap/
#  https://biostatsquid.com/heatmaps-with-complexheatmap-r-tutorial/
#
#  ml_variable_heatmap = list(
#    enable = TRUE,
#    ml_model = "auto",           # auto | tabpfn | lightgbm | ...
#    features = NULL,             # NULL=尽量用分析队列可画列；或字符向量；"ml"=仅最终 ML 特征
#    include_train = TRUE,
#    include_validation = TRUE,
#    order_by = "predicted",      # predicted | group | none
#    max_n = 2000L,               # 过多则分层抽样
#    figure_stem = NULL,          # NULL → 自动英文题
#    width = 12, height = 10
#  )
#
#  register_block: "ml_variable_heatmap"
#  典型位置: ml_aggregate / performance_ml / shap 之后
###############################################################################

.mlvh28_tag_from_display <- function(display_name) {
  dm <- c(
    "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "ENet" = "enet",
    "RSVM" = "rsvm", "MLP" = "mlp", "RealMLP" = "realmlp", "Logistic" = "logistic",
    "LightGBM" = "lightgbm", "KNN" = "knn", "TabPFN" = "tabpfn",
    "AdaBoost" = "adaboost", "CatBoost" = "catboost", "TabPFNv2" = "tabpfnv2",
    "TablCL_v2" = "tablcl_v2"
  )
  disp <- trimws(as.character(display_name)[1L])
  hit <- match(tolower(disp), tolower(names(dm)), nomatch = NA_integer_)
  if (!is.na(hit)) return(unname(dm[hit]))
  tolower(disp)
}

.mlvh28_display_from_tag <- function(tag) {
  dm <- c(
    dt = "DT", rf = "RF", xgboost = "XGBoost", enet = "ENet", rsvm = "RSVM",
    mlp = "MLP", realmlp = "RealMLP", logistic = "Logistic", lightgbm = "LightGBM",
    knn = "KNN", tabpfn = "TabPFN", adaboost = "AdaBoost", catboost = "CatBoost",
    tabpfnv2 = "TabPFNv2", tablcl_v2 = "TablCL_v2"
  )
  unname(dm[tolower(tag)]) %||% tag
}

.mlvh28_resolve_tag <- function(ctx, bl_cfg) {
  choice <- tolower(trimws(as.character(bl_cfg$ml_model %||% bl_cfg$model %||% "auto")[1L]))
  if (!identical(choice, "auto") && nzchar(choice)) return(choice)
  best <- tolower(trimws(as.character(ctx$results$ml_best_model_tag %||% "")[1L]))
  if (nzchar(best)) return(best)
  disp <- ctx$results$ml_best_model_display %||% ""
  if (nzchar(as.character(disp)[1L])) return(.mlvh28_tag_from_display(disp))
  "tabpfn"
}

.mlvh28_load_preds <- function(ctx, tag) {
  models_dir <- if (exists("resolve_ml_models_dir_for_tag", mode = "function")) {
    resolve_ml_models_dir_for_tag(ctx, tag)
  } else {
    ""
  }
  rdata <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  if (!file.exists(rdata)) return(NULL)
  env <- new.env(parent = emptyenv())
  ok <- isTRUE(tryCatch({ load(rdata, envir = env); TRUE }, error = function(e) FALSE))
  if (!ok) return(NULL)
  list(
    final = env$final_predictions %||% NULL,
    raw_train = env[[paste0("raw_pred_train_", tag)]] %||% NULL,
    raw_test = env[[paste0("raw_pred_test_", tag)]] %||% NULL,
    predtrain = env[[paste0("predtrain_", tag)]] %||% env$predtrain %||% NULL,
    predtest = env[[paste0("predtest_", tag)]] %||% env$predtest %||% NULL
  )
}

.mlvh28_drop_cols <- function() {
  c(
    "SEQN", "SEQN_original", "id", "ID", "patient_id", "row_id",
    "predicted_prob", "dataset", "model", ".row", ".weights", "weights",
    "sample_weight"
  )
}

.mlvh28_resolve_features <- function(ctx, bl_cfg, data_nms) {
  feats_cfg <- bl_cfg$features
  if (is.character(feats_cfg) && length(feats_cfg) == 1L &&
      tolower(feats_cfg) %in% c("ml", "final", "selected")) {
    feats <- tryCatch({
      if (exists(".shap_resolve_ml_feature_names", mode = "function")) {
        .shap_resolve_ml_feature_names(ctx)
      } else {
        as.character(ctx$results$feature_selection_final %||% character(0))
      }
    }, error = function(e) character(0))
    return(intersect(feats, data_nms))
  }
  if (!is.null(feats_cfg) && length(feats_cfg) && !identical(feats_cfg, "auto")) {
    return(intersect(as.character(feats_cfg), data_nms))
  }
  drop <- union(.mlvh28_drop_cols(), c("Group", "Disease_Group", "Disease"))
  cand <- setdiff(data_nms, drop)
  ## 去掉全 NA / 常数 / 高基数 ID 样字符列
  cand
}

.mlvh28_is_cat <- function(x, max_level = 8L) {
  ## 仅二分类/少量名义变量当分类；Apgar(0–10) 等有序分值仍作连续
  if (is.logical(x)) return(TRUE)
  if (is.factor(x) || is.character(x)) {
    return(length(unique(stats::na.omit(as.character(x)))) <= max_level)
  }
  ux <- unique(stats::na.omit(as.numeric(x)))
  ## 数值列：只有 0/1（或恰好 2 个水平）才当分类
  length(ux) > 0L && length(ux) <= 2L && all(abs(ux - round(ux)) < 1e-8)
}

.mlvh28_build_plot_df <- function(ctx, bl_cfg, tag) {
  train <- ctx$data$train %||% NULL
  test <- ctx$data$validation %||% ctx$data$test %||% NULL
  if (is.null(train) || !is.data.frame(train)) {
    stop("ml_variable_heatmap: 需要 ctx$data$train。", call. = FALSE)
  }
  preds <- .mlvh28_load_preds(ctx, tag)
  disp <- .mlvh28_display_from_tag(tag)
  pred_col <- paste0(disp, "_predicted_value")

  .one <- function(df, dataset_lab, pred_vec) {
    out <- as.data.frame(df, check.names = FALSE)
    out$dataset <- dataset_lab
    out[[pred_col]] <- as.numeric(pred_vec)
    if (!"Group" %in% names(out)) {
      if ("Disease_Group" %in% names(out)) out$Group <- out$Disease_Group
    }
    out
  }

  .pred_vec <- function(raw_df, pred_df, n_expect) {
    if (!is.null(raw_df) && "predicted_prob" %in% names(raw_df) && nrow(raw_df) == n_expect) {
      return(as.numeric(raw_df$predicted_prob))
    }
    ana <- trimws(as.character(
      ctx$config$project$analysis_group %||% ctx$config$project$disease %||% "Case"
    )[1L])
    pcol <- ctx$results$ml_pred_ana_col %||% paste0(".pred_", make.names(ana))
    if (!is.null(pred_df) && is.data.frame(pred_df) && pcol %in% names(pred_df) &&
        nrow(pred_df) == n_expect) {
      return(as.numeric(pred_df[[pcol]]))
    }
    if (!is.null(preds$final) && is.data.frame(preds$final)) {
      hit <- grep("_predicted_value$", names(preds$final), value = TRUE)
      if (length(hit)) return(as.numeric(preds$final[[hit[1L]]]))
    }
    rep(NA_real_, n_expect)
  }

  chunks <- list()
  if (isTRUE(bl_cfg$include_train %||% TRUE)) {
    ## 用完整 train 临床列 + TabPFN 概率（旧 Fig5 为全变量总览，不只 ML 10 特征）
    chunks[[length(chunks) + 1L]] <- .one(
      train, "training",
      .pred_vec(preds$raw_train, preds$predtrain, nrow(train))
    )
  }
  if (isTRUE(bl_cfg$include_validation %||% TRUE) && !is.null(test) && is.data.frame(test)) {
    chunks[[length(chunks) + 1L]] <- .one(
      test, "validation",
      .pred_vec(preds$raw_test, preds$predtest, nrow(test))
    )
  }
  if (!length(chunks)) stop("ml_variable_heatmap: 无可用样本。", call. = FALSE)
  ## 对齐列后 rbind
  all_n <- unique(unlist(lapply(chunks, names)))
  chunks <- lapply(chunks, function(d) {
    miss <- setdiff(all_n, names(d))
    for (m in miss) d[[m]] <- NA
    d[, all_n, drop = FALSE]
  })
  do.call(rbind, chunks)
}

.mlvh28_row_scale <- function(mat) {
  t(apply(mat, 1L, function(v) {
    v <- as.numeric(v)
    rng <- range(v[is.finite(v)], na.rm = TRUE)
    if (!all(is.finite(rng)) || diff(rng) < 1e-12) return(rep(0.5, length(v)))
    (v - rng[1]) / (rng[2] - rng[1])
  }))
}

.mlvh28_draw <- function(plot_df, feature_cols, pred_col, bl_cfg, disp, out_pdf) {
  ## 对齐交付脚本 Figure 5 Heatmap.R：
  ## ha <- HeatmapAnnotation(df = df); Heatmap(mat, height=0, top_annotation=ha)
  ## draw(..., annotation_legend_side = "bottom")
  if (!requireNamespace("ComplexHeatmap", quietly = TRUE) ||
      !requireNamespace("grid", quietly = TRUE)) {
    stop("ml_variable_heatmap 需要 ComplexHeatmap + grid。", call. = FALSE)
  }
  df <- plot_df
  ord_by <- tolower(as.character(bl_cfg$order_by %||% "predicted")[1L])
  if (identical(ord_by, "predicted") && pred_col %in% names(df)) {
    df <- df[order(df$dataset, df[[pred_col]], na.last = TRUE), , drop = FALSE]
  } else if (identical(ord_by, "group") && "Group" %in% names(df)) {
    df <- df[order(df$dataset, df$Group), , drop = FALSE]
  }

  max_n <- as.integer(bl_cfg$max_n %||% 2000L)[1L]
  if (is.finite(max_n) && max_n > 0L && nrow(df) > max_n) {
    set.seed(as.integer(bl_cfg$seed %||% 42L)[1L])
    keep <- c(
      which(df$dataset == "training")[seq_len(min(sum(df$dataset == "training"),
                                                  as.integer(max_n * 0.7)))],
      which(df$dataset == "validation")[seq_len(min(sum(df$dataset == "validation"),
                                                    as.integer(max_n * 0.3)))]
    )
    keep <- unique(keep[is.finite(keep)])
    df <- df[keep, , drop = FALSE]
    cli::cli_alert_info("ml_variable_heatmap: 降采样至 {nrow(df)} 列。")
  }

  feature_cols <- intersect(feature_cols, names(df))
  feature_cols <- setdiff(feature_cols, c("Group", "dataset", pred_col))
  if (!length(feature_cols)) stop("ml_variable_heatmap: 无特征列可画。", call. = FALSE)

  ann_cols <- c(feature_cols, intersect(c("Group", "dataset", pred_col), names(df)))
  ann <- df[, ann_cols, drop = FALSE]

  ## 分类列转 factor；二值 0/1 → No/Yes；Group/dataset 贴交付标签
  for (nm in names(ann)) {
    if (identical(nm, pred_col)) {
      ann[[nm]] <- suppressWarnings(as.numeric(ann[[nm]]))
      next
    }
    if (identical(nm, "Group")) {
      gv <- as.character(ann[[nm]])
      gv[gv %in% c("No ROP", "Control", "0", "normal", "Normal")] <- "Normal"
      gv[gv %in% c("ROP", "1", "case", "Case")] <- "ROP"
      ann[[nm]] <- factor(gv)
      next
    }
    if (identical(nm, "dataset")) {
      dv <- as.character(ann[[nm]])
      dv[tolower(dv) == "training"] <- "Training set"
      dv[tolower(dv) %in% c("validation", "test")] <- "Validation set"
      ann[[nm]] <- factor(dv, levels = c("Training set", "Validation set"))
      next
    }
    if (.mlvh28_is_cat(ann[[nm]])) {
      v <- as.character(ann[[nm]])
      if (all(unique(stats::na.omit(v)) %in% c("0", "1"))) {
        v[v == "0"] <- "No"
        v[v == "1"] <- "Yes"
      }
      ann[[nm]] <- factor(v)
    } else {
      ann[[nm]] <- suppressWarnings(as.numeric(ann[[nm]]))
    }
  }

  font_gp <- grid::gpar(
    fontfamily = as.character(bl_cfg$font_family %||% "Times New Roman")[1L],
    fontsize = 8
  )
  ha <- ComplexHeatmap::HeatmapAnnotation(
    df = ann,
    annotation_name_gp = font_gp,
    annotation_name_side = "right",
    gap = grid::unit(0.6, "mm"),
    simple_anno_size = grid::unit(3.2, "mm")
  )

  ## 本体高度 0：只显示 annotation 条带（与交付脚本一致）
  mat <- matrix(0, nrow = 1L, ncol = nrow(ann))
  ht <- ComplexHeatmap::Heatmap(
    mat,
    name = "spacer",
    height = grid::unit(0, "mm"),
    show_heatmap_legend = FALSE,
    show_column_names = FALSE,
    show_row_names = FALSE,
    cluster_rows = FALSE,
    cluster_columns = FALSE,
    top_annotation = ha
  )

  w <- as.numeric(bl_cfg$width %||% 10)[1L]
  h <- as.numeric(bl_cfg$height %||% 10)[1L]
  if (!is.finite(w) || w < 6) w <- 10
  if (!is.finite(h) || h < 6) h <- 10
  opened <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    opened <- isTRUE(tryCatch({
      grDevices::cairo_pdf(out_pdf, width = w, height = h)
      TRUE
    }, error = function(e) FALSE))
  }
  if (!opened) grDevices::pdf(out_pdf, width = w, height = h)
  ComplexHeatmap::draw(
    ht,
    annotation_legend_side = "bottom",
    padding = grid::unit(c(2, 2, 2, 2), "mm")
  )
  grDevices::dev.off()
  invisible(out_pdf)
}

block_ml_variable_heatmap <- function(ctx, ...) {
  bl_cfg <- ctx$config$ml_variable_heatmap %||% list()
  if (isFALSE(bl_cfg$enable %||% FALSE)) {
    cli::cli_alert_info("config$ml_variable_heatmap$enable=FALSE，跳过。")
    return(ctx)
  }
  if (!requireNamespace("ComplexHeatmap", quietly = TRUE)) {
    cli::cli_alert_warning("未安装 ComplexHeatmap，跳过 ml_variable_heatmap。")
    return(ctx)
  }

  tag <- .mlvh28_resolve_tag(ctx, bl_cfg)
  disp <- .mlvh28_display_from_tag(tag)
  cli::cli_h2("ml_variable_heatmap: 模型={disp} ({tag})")

  plot_df <- .mlvh28_build_plot_df(ctx, bl_cfg, tag)
  pred_col <- paste0(disp, "_predicted_value")
  if (!pred_col %in% names(plot_df)) {
    ## 兼容 final_predictions 列名
    alt <- grep("_predicted_value$", names(plot_df), value = TRUE)
    if (length(alt)) {
      names(plot_df)[names(plot_df) == alt[1L]] <- pred_col
    }
  }
  feat_cols <- .mlvh28_resolve_features(ctx, bl_cfg, names(plot_df))
  if (!length(feat_cols)) {
    cli::cli_alert_warning("ml_variable_heatmap: 无可用特征，跳过。")
    return(ctx)
  }

  disease <- as.character(ctx$config$project$disease %||% "outcome")[1L]
  stem <- bl_cfg$figure_stem %||% sprintf(
    "Figure. Variable heatmap of the %s model predicting %s",
    disp, disease
  )
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  out_pdf <- file.path(fig_dir, paste0(stem, ".pdf"))

  .mlvh28_draw(plot_df, feat_cols, pred_col, bl_cfg, disp, out_pdf)
  cli::cli_alert_success("变量热图已写出: {.file {out_pdf}}")

  ## 同步到 Clinical/Figures 惯例目录
  root_fig <- file.path(ctx$root_output_dir %||% dirname(ctx$output_dir %||% "."), "Figures")
  if (dir.exists(dirname(root_fig))) {
    for (sub in c("pdf", "png", "tiff")) {
      d <- file.path(root_fig, sub)
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    file.copy(out_pdf, file.path(root_fig, "pdf", basename(out_pdf)), overwrite = TRUE)
    file.copy(out_pdf, file.path(root_fig, basename(out_pdf)), overwrite = TRUE)
    if (requireNamespace("pdftools", quietly = TRUE) && requireNamespace("png", quietly = TRUE)) {
      tryCatch({
        bm <- pdftools::pdf_render_page(out_pdf, page = 1, dpi = 200)
        png::writePNG(bm, file.path(root_fig, "png", sub("\\.pdf$", ".png", basename(out_pdf))))
      }, error = function(e) invisible(NULL))
    }
  }

  ctx$results$ml_variable_heatmap <- list(
    tag = tag,
    display = disp,
    n = nrow(plot_df),
    n_features = length(feat_cols),
    pdf = out_pdf
  )
  ctx
}

register_block(
  "ml_variable_heatmap",
  block_ml_variable_heatmap,
  "ML 预测变量热图（患者×特征 + Group/dataset/预测概率）"
)
