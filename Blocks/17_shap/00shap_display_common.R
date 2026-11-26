###############################################################################
#  00shap_display_common.R — SHAP 发表展示层（Blocks/17_shap）
#
#  与同目录分工（禁止乱放）：
#    00shap_router.R         — 算法路由 + analysis_group 符号对齐
#    00shap_display_common.R — recipe/baked dummy 折叠 + 发表拼图构建（本文件）
#    01block_shap.R          — register_block("shap") 主流程（source 上二者）
#    02block_shap_glm.R      — GLM SHAP
#    02block_shap_dl_mlp.R   — MLP/DL SHAP
#
#  命名：一律 .shap_*；折叠与 .shap_collapse_shapviz_to_venn_features 平行。
#  调用时依赖 01block_shap.R 已定义的面板 helper（R 按调用时查找）。
#  入口 CLI：run/ml/redraw_shap_pub_figure.R → .shap_build_pub_combined_figure
###############################################################################

#' 从 recipe/baked dummy 列名推断临床变量名（无 ctx 时兜底）
#' 例：Gender_Male → Gender；Familysize_X3.4 + Familysize_X..5 → Familysize
.shap_infer_feature_names_from_baked <- function(pred_cols) {
  pred_cols <- unique(as.character(pred_cols))
  pred_cols <- pred_cols[nzchar(pred_cols)]
  if (!length(pred_cols)) return(character(0))
  cont <- pred_cols[!grepl("_", pred_cols, fixed = TRUE)]
  dummies <- setdiff(pred_cols, cont)
  if (!length(dummies)) return(cont)

  cand <- unique(c(
    sub("_[^_]+$", "", dummies),
    sub("_X.*$", "", dummies)
  ))
  cand <- cand[nzchar(cand) & !cand %in% dummies]
  cand <- cand[order(nchar(cand), decreasing = TRUE)]
  keep <- character(0)
  covered <- character(0)
  for (r in cand) {
    hits <- dummies[startsWith(dummies, paste0(r, "_"))]
    if (!length(hits)) next
    if (all(hits %in% covered)) next
    keep <- c(keep, r)
    covered <- unique(c(covered, hits))
  }
  unique(c(cont, keep))
}

#' recipe/baked dummy → 临床变量：SHAP 按列求和（平行于韦恩折叠）
#'
#' 有 train 帧时 X 走 `.shap_collapse_shapviz_to_venn_features` 的原始分类列路径。
#' config：`shap$collapse_baked_dummies`（兼容旧键 `collapse_recipe_dummies`）。
.shap_collapse_shapviz_baked_dummies <- function(shp, X_df, ctx = NULL,
                                                feature_names = NULL) {
  if (is.null(shp) || !requireNamespace("shapviz", quietly = TRUE)) {
    return(list(shp = shp, X_df = X_df, X_mat = NULL, collapsed = FALSE))
  }
  if (!exists(".shap_collapse_shapviz_to_venn_features", mode = "function")) {
    cli::cli_alert_warning(
      "00shap_display_common: 缺少 .shap_collapse_shapviz_to_venn_features（须先 source 01block_shap.R）"
    )
    return(list(shp = shp, X_df = X_df, X_mat = NULL, collapsed = FALSE))
  }
  sv <- tryCatch(shapviz::get_shap_values(shp), error = function(e) NULL)
  if (is.null(sv)) {
    return(list(shp = shp, X_df = X_df, X_mat = NULL, collapsed = FALSE))
  }
  if (is.data.frame(sv)) sv <- as.matrix(sv)
  pred_cols <- colnames(sv)

  feats <- unique(as.character(feature_names %||% character(0)))
  feats <- feats[nzchar(feats)]
  if (!length(feats) && !is.null(ctx)) {
    feats <- unique(c(
      tryCatch(.shap_resolve_venn_feature_names(ctx), error = function(e) character(0)),
      tryCatch(.shap_resolve_ml_feature_names(ctx), error = function(e) character(0)),
      tryCatch(.shap_active_index_vars(ctx$config, ctx), error = function(e) character(0)),
      tryCatch(.shap_categorical_raw_features(ctx), error = function(e) character(0))
    ))
    feats <- feats[nzchar(feats)]
  }
  if (!length(feats)) {
    feats <- .shap_infer_feature_names_from_baked(pred_cols)
  }
  feats <- unique(feats[nzchar(feats)])
  if (!length(feats)) {
    return(list(shp = shp, X_df = X_df, X_mat = NULL, collapsed = FALSE))
  }

  needs <- FALSE
  for (v in feats) {
    if (v %in% pred_cols) next
    hits <- pred_cols[vapply(pred_cols, function(col) {
      .shap_is_baked_categorical_column(col, v)
    }, logical(1L))]
    if (length(hits)) {
      needs <- TRUE
      break
    }
  }
  if (!needs) {
    return(list(shp = shp, X_df = X_df, X_mat = NULL, collapsed = FALSE))
  }

  out <- .shap_collapse_shapviz_to_venn_features(
    shp, X_df, ctx %||% list(), venn_raw = feats
  )
  out$collapsed <- TRUE
  out
}

.shap_cfg_collapse_baked_dummies <- function(sh) {
  sh <- sh %||% list()
  if (!is.null(sh$collapse_baked_dummies)) return(isTRUE(sh$collapse_baked_dummies))
  if (!is.null(sh$collapse_recipe_dummies)) return(isTRUE(sh$collapse_recipe_dummies))
  TRUE
}

#' 从 tidymodels workflow / Shiny evalresult 构建发表 SHAP 拼图
#'
#' 顺序：analysis_group 符号对齐 → baked dummy 折叠 → pretty 展示名 →
#' combine_layout（默认 grid2x2：A 重要 / B 蜂群 / C 瀑布 / D 依赖）。
#'
#' @return list(fig, shp, X_df, tag, flipped, layout, font_family, waterfall_row, dependence_features)
.shap_build_pub_combined_figure <- function(wf, ctx = NULL, sh = NULL, tag = "xgboost",
                                            waterfall_row = NULL) {
  if (!requireNamespace("shapviz", quietly = TRUE)) {
    stop("00shap_display_common: 需要 shapviz", call. = FALSE)
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("00shap_display_common: 需要 ggplot2", call. = FALSE)
  }
  sh <- sh %||% list()
  sh$bee_color_low <- sh$bee_color_low %||% "#2166AC"
  sh$bee_color_high <- sh$bee_color_high %||% "#D73027"
  sh$dependence_point_alpha <- sh$dependence_point_alpha %||% 0.32
  sh$dependence_point_size <- sh$dependence_point_size %||% 0.95
  sh$dependence_add_smooth <- isTRUE(sh$dependence_add_smooth %||% TRUE)
  sh$dependence_x_quantiles <- sh$dependence_x_quantiles %||% c(0.01, 0.99)
  sh$panel_axis_text_size <- sh$panel_axis_text_size %||% 8.5
  sh$combine_layout <- sh$combine_layout %||% "grid2x2"
  do_collapse <- .shap_cfg_collapse_baked_dummies(sh)

  eng <- tryCatch(parsnip::extract_fit_engine(wf), error = function(e) NULL)
  if (is.null(eng)) stop("00shap_display_common: 无法 extract_fit_engine", call. = FALSE)
  X_df <- as.data.frame(wf$pre$mold$predictors)
  X_mat <- as.matrix(X_df)
  storage.mode(X_mat) <- "double"

  shp <- shapviz::shapviz(eng, X_pred = X_mat, X = X_df)
  if (exists(".shap_align_shapviz_to_analysis_group", mode = "function")) {
    shp <- .shap_align_shapviz_to_analysis_group(
      shp, wf = wf, ctx = ctx, eng = eng, X_mat = X_mat
    )
  }
  flipped <- isTRUE(attr(shp, "shap_sign_flipped"))

  if (isTRUE(do_collapse)) {
    col <- .shap_collapse_shapviz_baked_dummies(shp, X_df, ctx)
    if (isTRUE(col$collapsed) && !is.null(col$shp)) {
      shp <- col$shp
      X_df <- col$X_df
      if (!is.null(col$X_mat)) X_mat <- col$X_mat
    }
  }

  pretty <- .shap_apply_pretty_display(shp, X_df, X_mat)
  shp <- pretty$shp
  X_df <- pretty$X_df
  if (!is.null(pretty$X_mat)) X_mat <- pretty$X_mat
  pred_cols <- colnames(X_df)

  shp_clinical <- tryCatch(
    .shap_apply_clinical_value_labels(shp, X_df, ctx),
    error = function(e) shp
  )

  ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family(sh$font_family %||% "Times New Roman")
  } else {
    "Times"
  }
  if (is.null(ff) || grepl("Noto|CJK|Sans|Arial|Helvetica", ff, ignore.case = TRUE)) {
    ff <- "Liberation Serif"
  }

  top_n <- as.integer(sh$top_n %||% ncol(X_df))[1L]
  if (!is.finite(top_n) || top_n < 1L) top_n <- ncol(X_df)
  top_n <- min(top_n, ncol(X_df))
  imp_order <- names(sort(colMeans(abs(as.matrix(shapviz::get_shap_values(shp)))), decreasing = TRUE))
  bee_low <- sh$bee_color_low
  bee_high <- sh$bee_color_high
  model_disp <- .shap_model_display_name(ctx %||% list(config = list()), tag)

  pA <- shapviz::sv_importance(shp, show_numbers = TRUE, max_display = top_n) +
    ggplot2::labs(title = paste0("SHAP importance — ", model_disp))
  pA <- .shap_apply_importance_display_order(pA, imp_order)
  pA$layers[[1]]$aes_params$fill <- bee_high
  pA <- .shap_panel_finish(pA, ff, sh, keep_title = TRUE)

  pB <- shapviz::sv_importance(shp, kind = "bee", max_display = top_n,
                               color_bar_title = "Feature value") +
    ggplot2::labs(title = paste0("SHAP bee swarm — ", model_disp)) +
    ggplot2::scale_color_gradient(
      low = bee_low, high = bee_high, na.value = bee_high,
      breaks = c(0, 1), labels = c("Low", "High")
    )
  pB <- .shap_apply_importance_display_order(pB, imp_order)
  pB <- .shap_panel_finish(pB, ff, sh, keep_title = TRUE)

  n_row <- nrow(X_df)
  wf_row <- as.integer(waterfall_row %||% sh$waterfall_row %||% NA_integer_)[1L]
  if (!is.finite(wf_row) || wf_row < 1L || wf_row > n_row) {
    S <- as.matrix(shapviz::get_shap_values(shp))
    fx <- as.numeric(rowSums(S) + as.numeric(shp$baseline)[1L])
    wf_row <- which.max(fx)
  }
  pC <- tryCatch(
    {
      pw <- .shap_waterfall_with_labels(shp_clinical, wf_row, sh, ctx)
      if (is.null(pw)) {
        shapviz::sv_waterfall(shp_clinical, row_id = wf_row)
      } else {
        pw
      }
    },
    error = function(e) shapviz::sv_waterfall(shp, row_id = wf_row)
  )
  pC <- pC + ggplot2::labs(title = paste0("SHAP waterfall, row ", wf_row, " — ", model_disp))
  pC <- .shap_panel_finish(pC, ff, sh, keep_title = TRUE)

  dep_feats <- tryCatch(
    .shap_dependence_features(shp, sh, pred_cols, index_feats = character(0)),
    error = function(e) head(imp_order, 4L)
  )
  if (!length(dep_feats)) dep_feats <- head(imp_order, 4L)
  dep_list <- list()
  for (fj in dep_feats) {
    cv_j <- tryCatch(
      .shap_dependence_color_var(shp_clinical, fj, sh),
      error = function(e) "auto"
    )
    pj0 <- tryCatch(
      {
        if (is.null(cv_j)) {
          shapviz::sv_dependence(shp_clinical, v = fj, color_var = NULL)
        } else if (identical(cv_j, "auto")) {
          shapviz::sv_dependence(shp_clinical, v = fj)
        } else {
          shapviz::sv_dependence(shp_clinical, v = fj, color_var = cv_j)
        }
      },
      error = function(e) NULL
    )
    if (is.null(pj0)) next
    pj <- .shap_polish_dependence_plot(
      pj0, shp_clinical, fj, color_var = cv_j, sh_cfg = sh,
      bee_low = bee_low, bee_high = bee_high
    )
    pj <- .shap_apply_dependence_x_quantiles(pj, shp_clinical, fj, sh)
    pj <- pj + ggplot2::labs(title = paste0("SHAP dependence: ", fj))
    dep_list[[fj]] <- .shap_panel_finish(pj, ff, sh, keep_title = TRUE)
  }
  pD <- if (length(dep_list) >= 2L && requireNamespace("cowplot", quietly = TRUE)) {
    cowplot::plot_grid(plotlist = dep_list, ncol = 2L, align = "hv")
  } else if (length(dep_list)) {
    dep_list[[1L]]
  } else {
    ggplot2::ggplot() + ggplot2::theme_void()
  }

  built <- list(importance = pA, bee = pB, waterfall = pC, dependence = pD)
  layout <- tolower(trimws(as.character(sh$combine_layout %||% "grid2x2")[1L]))
  fig <- .shap_combine_panels(
    built, c("importance", "bee", "waterfall", "dependence"),
    ff, 12, c(1, 1), layout = layout
  )
  list(
    fig = fig, shp = shp, X_df = X_df, tag = tag,
    flipped = flipped, layout = layout, font_family = ff,
    waterfall_row = wf_row, dependence_features = names(dep_list)
  )
}
