###############################################################################
#  ROC — 基于 ml_models 已训练 workflow 绘制 ROC（发病 / 预后均可）。
#
#  register_block: "ROC"
#  典型流水线: train_validation → ml_models → ROC（勿与父块 block_ROC.R 重复 source）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results$ml_models（含 tidymodels workflow + recipe）
#  predict 矩阵与 block_ml_models 一致（bake 后特征）
#  预后: 真值对齐 survival$event_var；发病: Group 二分类
#
#  # ── 配置 config$roc ───────────────────────────────────────────────────────
#  roc = list(
#    enable      = TRUE,              # FALSE 跳过整块
#    ml_model    = "auto",            # auto=验证集 AUC 最优；或 dt|rf|xgboost|lightgbm|...
#    datasets    = c("validation","train"),  # 子集 train|validation|all
#    font_family = NULL               # NULL → config$plot$font_family
#  ),
#  说明: roc$ml_model 只控制画哪个已训练模型，不限制 ml_models$methods
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  Figures/Fig_ROC_*.pdf、Table_ROC_summary、ctx$results$roc_summary
#  源: Blocks/block_ROC.R（父块保留；本目录为目录化副本）
###############################################################################

.ml_tag_from_display <- function(display_name) {
  dm <- c(
    "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "ENet" = "enet",
    "RSVM" = "rsvm", "MLP" = "mlp", "Logistic" = "logistic",
    "LightGBM" = "lightgbm", "KNN" = "knn", "TabPFN" = "tabpfn",
    "AdaBoost" = "adaboost", "CatBoost" = "catboost", "TablCL_v2" = "tablcl_v2"
  )
  disp <- tolower(trimws(as.character(display_name)))
  hit <- match(disp, tolower(names(dm)), nomatch = NA_integer_)
  if (!is.na(hit)) return(unname(dm[hit]))
  disp
}

.resolve_roc_model_tag <- function(ctx, roc_cfg, fitted_names) {
  choice <- tolower(trimws(as.character(roc_cfg$ml_model %||% "auto")[1L]))
  if (identical(choice, "auto") || !nzchar(choice)) {
    tag <- ctx$results$ml_best_model_tag %||% NULL
    if (!is.null(tag) && nzchar(tag) && tag %in% fitted_names) return(tag)
    ev <- ctx$results$ml_eval_all
    if (is.null(ev) || !nrow(ev)) {
      stop("block_ROC: ml_model=auto 需要 ml_eval_all 或 ml_best_model_tag，请先运行 ml_models。", call. = FALSE)
    }
    sub <- ev[tolower(as.character(ev$dataset)) == "test" &
                tolower(as.character(ev$.metric)) == "roc_auc", , drop = FALSE]
    if (!nrow(sub)) stop("block_ROC: ml_eval_all 中无 validation/test 的 roc_auc。", call. = FALSE)
    dm <- c(
      "DT" = "dt", "RF" = "rf", "XGBoost" = "xgboost", "ENet" = "enet",
      "RSVM" = "rsvm", "MLP" = "mlp", "Logistic" = "logistic",
      "LightGBM" = "lightgbm", "KNN" = "knn", "TabPFN" = "tabpfn",
      "AdaBoost" = "adaboost", "CatBoost" = "catboost", "TablCL_v2" = "tablcl_v2"
    )
    .row_tag <- function(disp) {
      hit <- match(tolower(trimws(disp)), tolower(names(dm)), nomatch = NA_integer_)
      if (is.na(hit)) tolower(trimws(disp)) else unname(dm[hit])
    }
    sub[["tmp_ml_tag"]] <- vapply(as.character(sub$model), .row_tag, character(1L))
    ok <- sub[["tmp_ml_tag"]] %in% fitted_names
    sub <- if (any(ok)) sub[ok, , drop = FALSE] else sub
    best <- sub[which.max(as.numeric(sub$.estimate)), , drop = FALSE]
    return(.ml_tag_from_display(as.character(best$model[1L])))
  }
  choice
}

# 与 ml_models 中 recipe(step_dummy) 一致：名义变量水平须与训练集相同，否则 bake 列名/列数
# 与模型期望不一致（报错 “required columns Race_BLACK … are missing”）。
.align_roc_newdata_to_train <- function(sc, train_df, feat_cols) {
  if (is.null(train_df) || !nrow(train_df)) return(sc)
  for (nm in feat_cols) {
    if (!nm %in% names(sc) || !nm %in% names(train_df)) next
    xt <- train_df[[nm]]
    if (is.factor(xt)) {
      sc[[nm]] <- factor(as.character(sc[[nm]]), levels = levels(xt))
    } else if (is.character(xt)) {
      # 与 recipe 在训练集上对该列的 factor 水平一致（与 sort(unique) 可能不同）
      lev <- levels(factor(xt))
      sc[[nm]] <- factor(as.character(sc[[nm]]), levels = lev)
    } else if (is.logical(xt)) {
      xi <- sc[[nm]]
      if (is.numeric(xi)) {
        sc[[nm]] <- as.logical(as.integer(xi))
      } else {
        sc[[nm]] <- as.logical(xi)
      }
    } else if (is.numeric(xt)) {
      sc[[nm]] <- suppressWarnings(as.numeric(sc[[nm]]))
    }
  }
  if ("Group" %in% names(sc) && "Group" %in% names(train_df) && is.factor(train_df$Group)) {
    sc$Group <- factor(as.character(sc$Group), levels = levels(train_df$Group))
  }
  sc
}

# 与 block_ml_models.R 中 .ml_build_recipe 保持一致（改动时请两边同步）
.roc_recipe_scale_type_for_ml_tag <- function(tag) {
  tg <- tolower(as.character(tag)[1L])
  if (tg %in% c("enet", "rsvm")) return("center_scale")
  if (identical(tg, "mlp")) return("range")
  "none"
}

.roc_ml_build_recipe <- function(train_dat, scale_type = "none") {
  if (!requireNamespace("recipes", quietly = TRUE)) {
    stop("block_ROC: 需要 recipes 包。", call. = FALSE)
  }
  r <- recipes::recipe(Group ~ ., data = train_dat) %>%
    recipes::step_naomit(recipes::all_predictors(), skip = FALSE) %>%
    recipes::step_dummy(recipes::all_nominal_predictors())
  if (identical(scale_type, "center_scale")) {
    r <- r %>%
      recipes::step_center(recipes::all_predictors()) %>%
      recipes::step_scale(recipes::all_predictors())
  } else if (identical(scale_type, "range")) {
    r <- r %>% recipes::step_range(recipes::all_predictors())
  }
  recipes::prep(r)
}

# 与 block_ml_models.R 中 .ml_prob_col_candidates / .ml_detect_prob_col 一致（tidymodels 用 make.names 拼列名）
.roc_prob_col_candidates <- function(group_label) {
  g <- as.character(group_label)[1L]
  unique(c(paste0(".pred_", g), paste0(".pred_", make.names(g))))
}

.roc_detect_pred_prob_col <- function(df, group_label, preferred = NULL,
                                       ref_label = NULL, preferred_ref = NULL) {
  nms <- names(df)
  if (!is.null(preferred) && nzchar(preferred) && preferred %in% nms) return(preferred)
  cands <- .roc_prob_col_candidates(group_label)
  hit <- intersect(cands, nms)
  if (length(hit)) return(hit[1L])
  pred_cols <- nms[grepl("^\\.pred_", nms)]
  if (length(pred_cols)) {
    target <- make.names(as.character(group_label)[1L])
    stripped <- sub("^\\.pred_", "", pred_cols)
    j <- match(target, make.names(stripped))
    if (!is.na(j)) return(pred_cols[j])
  }
  # 二分类：两列 .pred_* 时，用参考组列名排除后取剩余一列（应对引擎列名与 make.names 不完全一致）
  pred_cols <- nms[grepl("^\\.pred_", nms)]
  if (length(pred_cols) == 2L && !is.null(ref_label)) {
    ref_nm <- if (!is.null(preferred_ref) && nzchar(preferred_ref) && preferred_ref %in% pred_cols) {
      preferred_ref
    } else {
      hr <- intersect(.roc_prob_col_candidates(ref_label), pred_cols)
      if (length(hr)) hr[1L] else NA_character_
    }
    if (!is.na(ref_nm) && ref_nm %in% pred_cols) {
      other <- setdiff(pred_cols, ref_nm)
      if (length(other) == 1L) return(other)
    }
  }
  stop(
    "block_ROC: 未找到分组 ", as.character(group_label)[1L], " 对应的概率列。predict 列名: ",
    paste(nms, collapse = ", "),
    call. = FALSE
  )
}

.match_part_to_dtv <- function(d_tv, part) {
  cols <- names(part)
  if (!length(cols)) return(integer(0))
  if (!all(cols %in% names(d_tv))) {
    stop("block_ROC: train/test 列与建模队列不一致。", call. = FALSE)
  }
  paste_cols <- function(df, cn) {
    do.call(
      paste,
      c(lapply(cn, function(v) as.character(df[[v]])), list(sep = "\1"))
    )
  }
  match(paste_cols(part, cols), paste_cols(d_tv, cols), nomatch = NA_integer_)
}

.roc_stats_and_plot <- function(truth_num, marker, font_family, title, config = NULL) {
  if (!requireNamespace("pROC", quietly = TRUE)) stop("block_ROC 需要 pROC 包。", call. = FALSE)
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("block_ROC 需要 ggplot2。", call. = FALSE)

  ok <- is.finite(marker) & !is.na(truth_num)
  truth_num <- truth_num[ok]
  marker    <- marker[ok]
  if (length(unique(truth_num)) < 2L) {
    cli::cli_alert_warning("ROC: 结局无两类有效观测，跳过: {title}")
    return(NULL)
  }

  roc_obj <- pROC::roc(response = truth_num, predictor = marker, quiet = TRUE)
  auc_v   <- as.numeric(pROC::auc(roc_obj))
  auc_ci  <- pROC::ci.auc(roc_obj, quiet = TRUE)
  coords  <- pROC::coords(roc_obj, "all", ret = c("sensitivity", "specificity", "threshold"))
  j <- coords$sensitivity + coords$specificity - 1
  i <- which.max(j)
  best_spec <- coords$specificity[i]
  best_sens <- coords$sensitivity[i]
  cutoff    <- coords$threshold[i]

  df_line <- data.frame(
    x = 1 - coords$specificity,
    y = coords$sensitivity
  )

  lbl <- paste0(
    "Area under the curve = ", format(round(auc_v, 3), nsmall = 3),
    "\n95% CI: [", format(round(as.numeric(auc_ci[1]), 3), nsmall = 3), ", ",
    format(round(as.numeric(auc_ci[3]), 3), nsmall = 3), "]"
  )

  g <- ggplot2::ggplot(df_line, ggplot2::aes(x = .data$x, y = .data$y)) +
    ggplot2::geom_path(linewidth = 1, color = "#C6524A") +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "longdash", color = "gray50", linewidth = 0.8) +
    ggplot2::scale_x_continuous("1 - Specificity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    ggplot2::scale_y_continuous("Sensitivity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    ggplot2::annotate(
      "text", x = 1, y = 0.2, label = lbl, hjust = 1,
      size = 4.2, color = "#C6524A", fontface = "bold",
      family = font_family
    ) +
    ggplot2::annotate(
      "point", x = 1 - best_spec, y = best_sens,
      color = "#2874C5", size = 4, shape = 19
    ) +
    ggplot2::annotate(
      "text", x = min(1 - best_spec + 0.05, 0.98), y = max(best_sens - 0.05, 0.05),
      label = paste0("cutoff: ", format(round(cutoff, 4), scientific = FALSE)),
      hjust = 0, vjust = 1, size = 4, color = "#2874C5", fontface = "bold",
      family = font_family
    ) +
    ggplot2::labs(title = title) +
    ggplot2::theme_bw(base_family = font_family) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold", family = font_family),
      axis.title = ggplot2::element_text(size = 11, family = font_family),
      axis.text  = ggplot2::element_text(family = font_family),
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.border = ggplot2::element_rect(color = "black", fill = NA, linewidth = 0.5)
    )

  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(config, "mimic_inc_prog_sle_aki") &&
      exists("pub_figure_profile_apply_ggplot", mode = "function")) {
    g <- pub_figure_profile_apply_ggplot(g, config)
  }

  list(
    plot = g,
    stats = list(
      auc = auc_v, auc_ci_lo = as.numeric(auc_ci[1]), auc_ci_hi = as.numeric(auc_ci[3]),
      cutoff = cutoff, sensitivity = best_sens, specificity = best_spec, n = length(truth_num)
    )
  )
}

block_ROC <- function(ctx, ...) {
  cfg <- ctx$config
  roc <- cfg$roc %||% list()
  if (isFALSE(roc$enable %||% TRUE)) {
    cli::cli_alert_info("config$roc$enable=FALSE，跳过 ROC。")
    return(ctx)
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% "incidence"))
  ana_group   <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group   <- cfg$project$reference_group %||% "Control"
  font_family <- plot_font_from_config(list(
    plot = list(font_family = roc$font_family %||% cfg$plot$font_family %||% "Times New Roman")
  ))

  outcome_ml <- cfg$data$outcome_column %||% "Disease"

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("block_ROC: 无 imputed/cleaned 数据。", call. = FALSE)

  feats <- as.character(ctx$results$ml_feature_names %||% character(0))
  if (!length(feats)) {
    feats <- as.character(
      ctx$results$feature_selection_final %||%
        ctx$results$Model2Factors %||% character(0)
    )
  }
  feats <- intersect(feats, names(data))
  if (!length(feats)) stop("block_ROC: 无可用特征列。", call. = FALSE)

  models <- ctx$results$ml_models %||% list()
  tag <- .resolve_roc_model_tag(ctx, roc, names(models))
  if (!tag %in% names(models)) {
    stop(
      "block_ROC: 模型 \"", tag, "\" 未出现在已训练列表中: ",
      paste(names(models), collapse = ", "),
      "。请检查 config$roc$ml_model 与 config$ml_models$methods。",
      call. = FALSE
    )
  }
  wf <- models[[tag]]
  if (is.null(wf) && tag %in% c("tabpfn", "tablcl_v2")) {
    stop(
      "block_ROC: ", tag, " 无 tidymodels workflow，请设 config$roc$ml_model 为 rf/lightgbm 等。",
      call. = FALSE
    )
  }
  if (is.null(wf)) {
    stop("block_ROC: 未找到 ctx$results$ml_models$", tag, "。", call. = FALSE)
  }

  if (!outcome_ml %in% names(data)) {
    stop("block_ROC: 结局列 ", outcome_ml, " 不在数据中（须与 ml_models 一致）。", call. = FALSE)
  }

  d_tv <- data
  y_chr <- trimws(as.character(d_tv[[outcome_ml]]))
  d_tv$Group <- factor(
    dplyr::case_when(
      y_chr == trimws(ana_group) ~ ana_group,
      y_chr == trimws(ref_group) ~ ref_group,
      TRUE ~ NA_character_
    ),
    levels = c(ref_group, ana_group)
  )
  d_tv <- d_tv[!is.na(d_tv$Group), , drop = FALSE]

  cn_sc <- c("Group", feats)
  miss <- setdiff(cn_sc, names(d_tv))
  if (length(miss)) {
    stop("block_ROC: 建模队列缺少列: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  sc <- d_tv[, cn_sc, drop = FALSE]
  tr_roc <- ctx$data$train
  if (is.null(tr_roc) || !nrow(tr_roc)) {
    stop("block_ROC: 需要 ctx$data$train（与 ml_models 相同划分）以复现 recipe 预处理。", call. = FALSE)
  }
  miss_tr <- setdiff(cn_sc, names(tr_roc))
  if (length(miss_tr)) {
    stop("block_ROC: ctx$data$train 缺少列: ", paste(miss_tr, collapse = ", "), call. = FALSE)
  }
  train_fit <- tr_roc[, cn_sc, drop = FALSE]
  sc <- .align_roc_newdata_to_train(sc, train_fit, feats)

  # ml_models 在 bake 后的 tr2 上 fit workflow（仅 add_formula，无 add_recipe），predict 须传入同结构 bake 结果，
  # 不能直接用原始 Race/Hypertension 等列名，否则会报缺少 Race_BLACK 等设计矩阵列。
  rt_scale <- .roc_recipe_scale_type_for_ml_tag(tag)
  rec_roc <- .roc_ml_build_recipe(train_fit, scale_type = rt_scale)
  pred_cols <- intersect(feats, names(sc))
  ok_rows <- if (length(pred_cols)) {
    stats::complete.cases(sc[, pred_cols, drop = FALSE])
  } else {
    rep(TRUE, nrow(sc))
  }

  pr <- tryCatch(
    {
      if (!any(ok_rows)) {
        stop("block_ROC: 全体样本在预测特征上存在 NA（step_naomit 无法 bake），无法 predict。", call. = FALSE)
      }
      sc_b <- recipes::bake(rec_roc, new_data = sc[ok_rows, , drop = FALSE])
      # 与 ml_models 中 tr2 一致：结局因子水平顺序须与训练集相同，否则 type=prob 列名可能与 ml_pred_* 不一致
      if ("Group" %in% names(sc_b) && is.factor(train_fit$Group)) {
        sc_b$Group <- factor(as.character(sc_b$Group), levels = levels(train_fit$Group))
      }
      predict(wf, new_data = sc_b, type = "prob")
    },
    error = function(e) {
      stop("block_ROC: predict 失败: ", e$message, call. = FALSE)
    }
  )
  pred_ana_col <- .roc_detect_pred_prob_col(
    pr, ana_group,
    preferred = ctx$results$ml_pred_ana_col %||% NULL,
    ref_label = ref_group,
    preferred_ref = ctx$results$ml_pred_ref_col %||% NULL
  )
  marker_tv <- rep(NA_real_, nrow(sc))
  marker_tv[ok_rows] <- as.numeric(pr[[pred_ana_col]])

  tr <- ctx$data$train
  te <- ctx$data$test
  if (is.null(tr) || is.null(te)) {
    stop("block_ROC: 缺少 ctx$data$train/test，请先运行 train_validation。", call. = FALSE)
  }

  sets <- tolower(as.character(roc$datasets %||% c("validation", "train")))
  if (!length(sets)) sets <- "validation"

  summ_rows <- list()

  event_var <- cfg$survival$event_var %||% NULL

  for (ds in sets) {
    if (identical(ds, "all")) {
      idx <- seq_len(nrow(d_tv))
      lab <- "all"
    } else if (identical(ds, "train") || ds == "training") {
      idx <- .match_part_to_dtv(d_tv, tr)
      lab <- "train"
    } else if (identical(ds, "validation") || identical(ds, "test")) {
      idx <- .match_part_to_dtv(d_tv, te)
      lab <- "validation"
    } else {
      next
    }
    if (anyNA(idx)) {
      stop("block_ROC: 无法将 ", ds, " 样本与 imputed 建模队列对齐（重复行或特征不一致？）。", call. = FALSE)
    }
    if (!length(idx)) next

    marker <- marker_tv[idx]

    if (identical(study_type, "prognosis")) {
      if (is.null(event_var) || !nzchar(event_var) || !event_var %in% names(d_tv)) {
        stop("block_ROC（预后）: 需要 config$survival$event_var 且在数据中存在。", call. = FALSE)
      }
      truth <- suppressWarnings(as.numeric(d_tv[[event_var]][idx]))
      ttl <- paste0("ROC (", toupper(tag), ", prognosis, ", lab, ", n=", sum(!is.na(truth) & is.finite(marker)), ")")
      z <- .roc_stats_and_plot(truth, marker, font_family, ttl, config = cfg)
      if (!is.null(z)) {
        # 与 boxplot 等一致：发表文件名经 save_figure →「Figure Sx-数据库名. …」
        fn <- pub_figure_file(ctx, "supp_figure",
          paste0("ROC (", toupper(tag), ", prognosis, ", lab, ")"))
        ctx <- save_figure(ctx, fn, local({
          gg <- z$plot
          function() print(gg)
        }), width = 8, height = 7)
        r <- z$stats
        r$dataset <- lab
        r$study <- "prognosis"
        r$model <- tag
        summ_rows[[length(summ_rows) + 1L]] <- r
      }
    } else {
      truth <- as.integer(d_tv$Group[idx] == ana_group)
      ttl <- paste0("ROC (", toupper(tag), ", incidence, ", lab, ", n=", length(truth), ")")
      z <- .roc_stats_and_plot(truth, marker, font_family, ttl, config = cfg)
      if (!is.null(z)) {
        fn <- pub_figure_file(ctx, "supp_figure",
          paste0("ROC (", toupper(tag), ", incidence, ", lab, ")"))
        ctx <- save_figure(ctx, fn, local({
          gg <- z$plot
          function() print(gg)
        }), width = 8, height = 7)
        r <- z$stats
        r$dataset <- lab
        r$study <- "incidence"
        r$model <- tag
        summ_rows[[length(summ_rows) + 1L]] <- r
      }
    }
  }

  ctx <- render_queued_figures(ctx)

  if (length(summ_rows)) {
    tab <- dplyr::bind_rows(lapply(summ_rows, function(z) as.data.frame(z, stringsAsFactors = FALSE)))
    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    fp <- file.path(tbl_dir, "Table_ROC_summary.xlsx")
    export_sci_table(tab, fp, title = "ROC summary (selected ML model)")
    ctx <- render_queued_tables(ctx)
    ctx$results$roc_summary <- tab
    ctx <- save_result(ctx, "roc_summary", tab, "roc_summary.csv")
  }

  ctx$results$roc_ml_model_tag <- tag
  cli::cli_alert_success("block_ROC 完成（模型={tag}，study_type={study_type}）")
  ctx
}

register_block("ROC", block_ROC, "基于 ml_models 选定模型的 ROC（发病/预后）")
