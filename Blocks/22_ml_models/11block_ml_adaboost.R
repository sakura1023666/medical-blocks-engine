###############################################################################
#  ml_adaboost — AdaBoost (adabag) 训练 + 评估
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_data += ctx$data$train / ctx$data$test（须先 train_validation）
#  require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors
#
#  ml_adaboost = list(
#    enable = TRUE,
#    cv_folds = NULL,              # NULL → splitting$seed 链 / 默认 5；n_train<350 时块内封顶 3
#    seed = NULL,
#    limits = list(max_train_n = 349L),  # n_train>349 软跳过（shared overrides 默认）
#    pause_enable = FALSE,
#    pause_on_missing_data = TRUE,
#  ),
#  防挂起：n_train<350 时 mfinal≤20、CV 折数≤3；轻量 SAMME rpart（不调用 adabag）。
#
#  register_block: "ml_adaboost"
#  典型流水线: train_validation → 本块 → ml_aggregate
###############################################################################


.mlada11_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.mlada11_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "ml_adaboost",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ml_adaboost — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.mlada11_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mlada11_check_limits <- function(n_train, min_class_n, bl_cfg, tag) {
  lm <- bl_cfg$limits %||% list()
  if (!length(lm)) return(TRUE)
  ok <- TRUE
  if (!is.null(lm$min_total_n)) {
    req <- as.integer(lm$min_total_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_adaboost: 训练集 n={n_train} < min_total_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_class_n)) {
    req <- as.integer(lm$min_class_n)[1L]
    if (is.finite(req) && min_class_n < req) {
      cli::cli_alert_info("ml_adaboost: 最小类 n={min_class_n} < min_class_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_train_n)) {
    req <- as.integer(lm$min_train_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_adaboost: 训练集 n={n_train} < min_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$max_train_n)) {
    req <- as.integer(lm$max_train_n)[1L]
    if (is.finite(req) && n_train > req) {
      cli::cli_alert_info("ml_adaboost: 训练集 n={n_train} > max_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  ok
}

.mlada11_prep <- function(ctx, bl_cfg) {
  cfg <- ctx$config
  sp_cfg <- cfg$splitting %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  id_col <- cfg$data$id_column %||% NULL
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group <- cfg$project$reference_group %||% "Control"
  fold_num <- as.integer(bl_cfg$cv_folds %||% cfg$ml_adaboost$cv_folds %||% cfg$ml_models$cv_folds %||% 5L)[1L]
  seed_val <- as.integer(bl_cfg$seed %||% sp_cfg$seed %||% cfg$imputation$seed %||% 42L)[1L]
  pred_ref_col <- .mlada11_prob_col_name(ref_group)
  pred_ana_col <- .mlada11_prob_col_name(ana_group)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    if (.mlada11_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlada11_pause(ctx, "无 imputed/cleaned 数据", "请先运行 imputation / data_clean。")
    }
    stop("ml_adaboost: 无数据。", call. = FALSE)
  }

  fs_cfg <- cfg$feature_selection %||% list()
  fs_on <- isTRUE(fs_cfg$enable %||% TRUE)
  ff0 <- ctx$results$feature_selection_final
  if (is.null(ff0) || !length(ff0)) {
    if (exists("load_feature_selection_final_into_ctx", mode = "function")) {
      ctx <- load_feature_selection_final_into_ctx(ctx)
      ff0 <- ctx$results$feature_selection_final
    }
  }
  if (fs_on && (is.null(ff0) || !length(ff0))) {
    if (.mlada11_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlada11_pause(ctx, "feature_selection_final 为空", "请先运行 feature_selection。")
    }
    stop("ml_adaboost: feature_selection_final 为空。", call. = FALSE)
  }

  feats <- if (length(ff0)) {
    as.character(ff0)
  } else {
    as.character(
      ctx$results$Model2Factors %||%
        setdiff(names(data), c(outcome_col, id_col,
                               cfg$survival$time_var, cfg$survival$event_var))
    )
  }
  feats <- setdiff(intersect(feats, names(data)), c(outcome_col, id_col %||% character(0)))
  if (!length(feats)) stop("ml_adaboost: 无可用特征。", call. = FALSE)

  if (!outcome_col %in% names(data)) {
    stop("ml_adaboost: 结局列不在数据中。", call. = FALSE)
  }
  data_ml <- data[, c(outcome_col, feats), drop = FALSE]
  names(data_ml)[1L] <- "Group"
  y_chr <- trimws(as.character(data_ml$Group))
  data_ml$Group <- factor(
    dplyr::case_when(
      y_chr == trimws(ana_group) ~ ana_group,
      y_chr == trimws(ref_group) ~ ref_group,
      TRUE ~ NA_character_
    ),
    levels = c(ref_group, ana_group)
  )
  data_ml <- data_ml[!is.na(data_ml$Group), , drop = FALSE]
  if (nrow(data_ml) < 30L) stop("ml_adaboost: 有效样本过少。", call. = FALSE)

  if (is.null(ctx$data$train) || is.null(ctx$data$test)) {
    if (.mlada11_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlada11_pause(ctx, "缺少 train/test", "请先 run_block(ctx, \"train_validation\")。")
    }
    stop("ml_adaboost: 缺少 ctx$data$train / test。", call. = FALSE)
  }

  df_train <- ctx$data$train
  df_validation <- ctx$data$test
  cn_model <- c("Group", intersect(feats, names(df_train)))
  miss <- setdiff(feats, names(df_train))
  if (length(miss)) stop("ml_adaboost: 训练集缺少特征列。", call. = FALSE)
  df_train <- df_train[, cn_model, drop = FALSE]
  df_validation <- df_validation[, cn_model, drop = FALSE]

  n_train <- nrow(df_train)
  cls_tab <- table(df_train$Group)
  min_class_n <- if (length(cls_tab)) min(as.integer(cls_tab)) else 0L

  lm <- bl_cfg$limits %||% list()
  margin <- as.integer(lm$cv_min_class_margin %||% 1L)[1L]
  max_fold <- max(2L, min_class_n - margin)
  if (is.finite(max_fold) && max_fold >= 2L && fold_num > max_fold) {
    cli::cli_alert_info("ml_adaboost: CV 折数 {fold_num} → {max_fold}（最小类 n={min_class_n}）。")
    fold_num <- max_fold
  }
  if (n_train < 350L && fold_num > 3L) {
    cli::cli_alert_info("ml_adaboost: n_train={n_train}<350，CV 折数 {fold_num} → 3。")
    fold_num <- 3L
  }

  data_dir <- file.path(ctx$output_dir, "Data")
  if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
  models_dir <- file.path(ctx$output_dir, "Models")
  if (!dir.exists(models_dir)) dir.create(models_dir, recursive = TRUE)
  hpbest_path <- file.path(data_dir, "Hpbest.RData")
  hpbest_list <- if (file.exists(hpbest_path)) {
    e <- new.env(parent = emptyenv()); load(hpbest_path, envir = e); e$hpbest_list
  } else list()

  list(
    ctx = ctx, cfg = cfg, bl_cfg = bl_cfg,
    df_train = df_train, df_validation = df_validation,
    ref_group = ref_group, ana_group = ana_group,
    pred_ref_col = pred_ref_col, pred_ana_col = pred_ana_col,
    fold_num = fold_num, seed_val = seed_val,
    feats = feats, n_train = n_train, min_class_n = min_class_n,
    data_dir = data_dir, models_dir = models_dir,
    hpbest_path = hpbest_path, hpbest_list = hpbest_list
  )
}

.mlada11_save_tidymodels <- function(prep, tag, res) {
  p <- prep
  hpbest_list <- p$hpbest_list
  hpbest_list[[paste0("hpbest_", tag)]] <- res$hpbest_frame
  save(hpbest_list, file = p$hpbest_path)

  .pred_col_ana <- p$pred_ana_col
  .mk_raw_pred <- function(raw_df, pred_df) {
    prob_vec <- if (.pred_col_ana %in% names(pred_df)) pred_df[[.pred_col_ana]] else NA_real_
    cbind(data.frame(predicted_prob = prob_vec, stringsAsFactors = FALSE), raw_df)
  }
  raw_pred_train_obj <- .mk_raw_pred(p$df_train, res$predtrain)
  raw_pred_test_obj  <- .mk_raw_pred(p$df_validation, res$predtest)
  raw_pred_all_obj   <- rbind(raw_pred_train_obj, raw_pred_test_obj)

  save_vars <- list(
    final_model = res$model,
    final_predictions = res$final_predictions,
    predtrain = res$predtrain,
    predtest = res$predtest,
    eval = res$eval,
    eval_best_cv5 = res$cv5_auc,
    eval_best_cv5_spec = res$cv5_spec,
    eval_best_cv5_sens = res$cv5_sens,
    raw_pred_train = raw_pred_train_obj,
    raw_pred_test = raw_pred_test_obj,
    raw_pred_all = raw_pred_all_obj
  )
  names(save_vars)[1L]  <- paste0("final_", tag)
  names(save_vars)[3L]  <- paste0("predtrain_", tag)
  names(save_vars)[4L]  <- paste0("predtest_", tag)
  names(save_vars)[5L]  <- paste0("eval_", tag)
  names(save_vars)[6L]  <- paste0("eval_best_cv5_", tag)
  names(save_vars)[7L]  <- paste0("eval_best_cv5_", tag, "_spec")
  names(save_vars)[8L]  <- paste0("eval_best_cv5_", tag, "_sens")
  names(save_vars)[9L]  <- paste0("raw_pred_train_", tag)
  names(save_vars)[10L] <- paste0("raw_pred_test_", tag)
  names(save_vars)[11L] <- paste0("raw_pred_all_", tag)
  out_file <- file.path(p$models_dir, paste0("evalresult_", tag, ".RData"))
  e_save <- new.env(parent = emptyenv())
  for (nm in names(save_vars)) assign(nm, save_vars[[nm]], envir = e_save)
  save(list = names(save_vars), file = out_file, envir = e_save)
  cli::cli_alert_success("{toupper(tag)} 结果已保存: {.file {out_file}}")
  list(out_file = out_file, eval = res$eval, model = res$model, preds = res$final_predictions)
}

.mlada11_write_ctx_meta <- function(ctx, prep) {
  ctx$results$ml_train_data <- prep$df_train
  ctx$results$ml_test_data <- prep$df_validation
  ctx$results$ml_pred_ref_col <- prep$pred_ref_col
  ctx$results$ml_pred_ana_col <- prep$pred_ana_col
  ctx$results$ml_feature_names <- prep$feats
  ctx <- ensure_ctx_results_list(ctx, "ml_models")
  ctx <- ensure_ctx_results_list(ctx, "ml_predictions_all")
  ctx <- ensure_ctx_results_list(ctx, "ml_eval_by_model")
  ctx$results[["ml_models_models_dir"]] <- prep$models_dir
  ctx
}

.mlada11_build_recipe <- function(train_dat, scale_type = "none") {
  # 用插补代替 step_naomit，保留所有行（避免训练/预测行数不一致）
  r <- recipes::recipe(Group ~ ., data = train_dat) %>%
    recipes::step_impute_median(recipes::all_numeric_predictors()) %>%
    recipes::step_impute_mode(recipes::all_nominal_predictors()) %>%
    recipes::step_dummy(recipes::all_nominal_predictors())
  if (scale_type == "center_scale") {
    r <- r %>%
      recipes::step_center(recipes::all_predictors()) %>%
      recipes::step_scale(recipes::all_predictors())
  } else if (scale_type == "range") {
    r <- r %>% recipes::step_range(recipes::all_predictors())
  }
  recipes::prep(r)
}

.mlada11_yueden <- function(roc_tbl) {
  roc_tbl %>%
    dplyr::mutate(yueden = sensitivity + specificity - 1) %>%
    dplyr::slice_max(yueden, n = 1, with_ties = FALSE) %>%
    dplyr::pull(.threshold)
}

.mlada11_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mlada11_prob_col_candidates <- function(group_label) {
  g <- as.character(group_label)[1L]
  unique(c(paste0(".pred_", g), paste0(".pred_", make.names(g))))
}

.mlada11_detect_prob_col <- function(df, group_label, preferred = NULL) {
  nms <- names(df)
  if (!is.null(preferred) && preferred %in% nms) return(preferred)
  cands <- .mlada11_prob_col_candidates(group_label)
  hit <- intersect(cands, nms)
  if (length(hit)) return(hit[1L])
  pred_cols <- nms[grepl("^\\.pred_", nms)]
  if (length(pred_cols)) {
    target <- make.names(as.character(group_label)[1L])
    stripped <- sub("^\\.pred_", "", pred_cols)
    j <- match(target, make.names(stripped))
    if (!is.na(j)) return(pred_cols[j])
  }
  stop(
    "未找到分组 ", as.character(group_label)[1L], " 对应的概率列。现有列: ",
    paste(nms, collapse = ", "),
    call. = FALSE
  )
}

.mlada11_predict_eval <- function(fit_obj, train2, test2,
                              model_name, pred_ref_col, pred_ana_col,
                              ref_g, ana_g) {
  grp_levels <- levels(train2$Group)

  .pred_one <- function(new_data, ds_label) {
    pred_prob <- stats::predict(fit_obj, new_data = new_data, type = "prob")
    ref_col <- .mlada11_detect_prob_col(pred_prob, ref_g, preferred = pred_ref_col)
    ana_col <- .mlada11_detect_prob_col(pred_prob, ana_g, preferred = pred_ana_col)
    if (!pred_ref_col %in% names(pred_prob)) pred_prob[[pred_ref_col]] <- pred_prob[[ref_col]]
    if (!pred_ana_col %in% names(pred_prob)) pred_prob[[pred_ana_col]] <- pred_prob[[ana_col]]
    pred_prob %>%
      dplyr::bind_cols(new_data %>% dplyr::select(Group)) %>%
      dplyr::mutate(dataset = ds_label, model = model_name)
  }

  predtrain <- .pred_one(train2, "train")
  predtest  <- .pred_one(test2,  "test")

  roctrain <- predtrain %>%
    yardstick::roc_curve(Group, !!rlang::sym(pred_ref_col), event_level = "first") %>%
    dplyr::mutate(dataset = "train")
  roctest  <- predtest %>%
    yardstick::roc_curve(Group, !!rlang::sym(pred_ref_col), event_level = "first") %>%
    dplyr::mutate(dataset = "test")

  yueden <- .mlada11_yueden(roctrain)

  .make_classes <- function(pred_df, thr) {
    pred_df %>%
      dplyr::mutate(.pred_class = factor(
        ifelse(.data[[pred_ref_col]] >= thr, ref_g, ana_g),
        levels = grp_levels
      ))
  }

  predtrain2 <- .make_classes(predtrain, yueden)
  predtest2  <- .make_classes(predtest,  yueden)

  .eval_one <- function(pred2, pred_prob, ds) {
    pred2 %>%
      yardstick::conf_mat(truth = Group, estimate = .pred_class) %>%
      summary(event_level = "second") %>%
      dplyr::bind_rows(
        pred_prob %>% yardstick::roc_auc(Group, !!rlang::sym(pred_ref_col), event_level = "first")
      ) %>%
      dplyr::mutate(dataset = ds)
  }

  eval_train <- .eval_one(predtrain2, predtrain, "train")
  eval_test  <- .eval_one(predtest2,  predtest,  "test")
  eval_both  <- dplyr::bind_rows(eval_train, eval_test) %>% dplyr::mutate(model = model_name)

  .make_final_preds <- function(new_data, ds_label) {
    pred_prob <- stats::predict(fit_obj, new_data = new_data, type = "prob")
    ref_col <- .mlada11_detect_prob_col(pred_prob, ref_g, preferred = pred_ref_col)
    ana_col <- .mlada11_detect_prob_col(pred_prob, ana_g, preferred = pred_ana_col)
    if (!pred_ref_col %in% names(pred_prob)) pred_prob[[pred_ref_col]] <- pred_prob[[ref_col]]
    if (!pred_ana_col %in% names(pred_prob)) pred_prob[[pred_ana_col]] <- pred_prob[[ana_col]]
    pred_prob %>%
      dplyr::bind_cols(new_data) %>%
      dplyr::mutate(dataset = ds_label)
  }

  fp_test  <- .make_final_preds(test2,  "Validation set")
  fp_train <- .make_final_preds(train2, "Training set")
  fp_all   <- rbind(fp_test, fp_train)
  fp_all   <- fp_all[, !names(fp_all) %in% pred_ref_col, drop = FALSE]
  names(fp_all)[names(fp_all) == pred_ana_col] <- paste0(model_name, "_predicted_value")

  list(
    predtrain = predtrain, predtest = predtest,
    roctrain  = roctrain,  roctest  = roctest,
    eval      = eval_both,
    final_predictions = fp_all,
    yueden    = yueden
  )
}

.mlada11_predict_eval_from_prob <- function(
    prob_ref_train, prob_ref_test, train2, test2,
    model_name, pred_ref_col, pred_ana_col, ref_g, ana_g) {
  prob_ref_train <- as.numeric(prob_ref_train)
  prob_ref_test  <- as.numeric(prob_ref_test)
  prob_ref_train[!is.finite(prob_ref_train)] <- NA_real_
  prob_ref_test[!is.finite(prob_ref_test)] <- NA_real_
  prob_ref_train <- pmin(pmax(prob_ref_train, 0), 1)
  prob_ref_test <- pmin(pmax(prob_ref_test, 0), 1)

  predtrain <- data.frame(
    Group = train2$Group,
    dataset = "train",
    model = model_name,
    stringsAsFactors = FALSE
  )
  predtest <- data.frame(
    Group = test2$Group,
    dataset = "test",
    model = model_name,
    stringsAsFactors = FALSE
  )
  predtrain[[pred_ref_col]] <- prob_ref_train
  predtrain[[pred_ana_col]] <- 1 - prob_ref_train
  predtest[[pred_ref_col]] <- prob_ref_test
  predtest[[pred_ana_col]] <- 1 - prob_ref_test

  roctrain <- predtrain %>%
    yardstick::roc_curve(Group, !!rlang::sym(pred_ref_col), event_level = "first") %>%
    dplyr::mutate(dataset = "train")
  yueden <- .mlada11_yueden(roctrain)

  .make_classes <- function(pred_df, thr) {
    pred_df %>%
      dplyr::mutate(.pred_class = factor(
        ifelse(.data[[pred_ref_col]] >= thr, ref_g, ana_g),
        levels = levels(train2$Group)
      ))
  }
  predtrain2 <- .make_classes(predtrain, yueden)
  predtest2  <- .make_classes(predtest,  yueden)
  .eval_one <- function(pred2, pred_prob, ds) {
    pred2 %>%
      yardstick::conf_mat(truth = Group, estimate = .pred_class) %>%
      summary(event_level = "second") %>%
      dplyr::bind_rows(
        pred_prob %>% yardstick::roc_auc(Group, !!rlang::sym(pred_ref_col), event_level = "first")
      ) %>%
      dplyr::mutate(dataset = ds)
  }
  eval_both <- dplyr::bind_rows(
    .eval_one(predtrain2, predtrain, "train"),
    .eval_one(predtest2, predtest, "test")
  ) %>% dplyr::mutate(model = model_name)

  fp_test  <- cbind(test2, dataset = "Validation set")
  fp_train <- cbind(train2, dataset = "Training set")
  fp_test[[paste0(model_name, "_predicted_value")]] <- predtest[[pred_ana_col]]
  fp_train[[paste0(model_name, "_predicted_value")]] <- predtrain[[pred_ana_col]]
  fp_all <- rbind(fp_test, fp_train)

  list(
    predtrain = predtrain, predtest = predtest,
    roctrain  = roctrain,  roctest = NULL,
    eval = eval_both,
    final_predictions = fp_all,
    yueden = yueden
  )
}

.mlada11_cv5_auc <- function(tune_obj, hpbest, eval_cv, model_name, pred_ref_col) {
  hp_cols <- setdiff(names(hpbest), ".config")
  pp <- tune::collect_predictions(tune_obj)
  if (!pred_ref_col %in% names(pp)) {
    # 兼容组名特殊字符导致的概率列名变化；仅允许数值概率列，排除 .pred_class 等 factor
    cand <- names(pp)[grepl("^\\.pred_", names(pp)) &
                        vapply(pp, is.numeric, logical(1L))]
    if (length(cand) >= 1L) {
      # 若只有一个概率列，直接视为 ref 概率；若有多个，优先取第一个
      pp[[pred_ref_col]] <- pp[[cand[1L]]]
    } else {
      stop(
        "未在 CV 预测中找到可用概率列（期望 ", pred_ref_col, "）。",
        call. = FALSE
      )
    }
  }
  pp %>%
    dplyr::inner_join(hpbest %>% dplyr::select(dplyr::all_of(hp_cols)),
                      by = hp_cols) %>%
    dplyr::group_by(id) %>%
    yardstick::roc_auc(Group, !!rlang::sym(pred_ref_col)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(model = model_name) %>%
    dplyr::inner_join(eval_cv %>% dplyr::select(.metric, mean, std_err),
                      by = ".metric")
}

.mlada11_cv5_spec <- function(tune_obj, hpbest, eval_cv, model_name) {
  hp_cols <- setdiff(names(hpbest), ".config")
  tune_obj %>%
    tune::collect_predictions() %>%
    dplyr::inner_join(hpbest %>% dplyr::select(dplyr::all_of(hp_cols)),
                      by = hp_cols) %>%
    dplyr::group_by(id) %>%
    yardstick::spec(truth = Group, estimate = .pred_class, event_level = "second") %>%
    dplyr::ungroup() %>%
    dplyr::mutate(model = model_name) %>%
    dplyr::inner_join(eval_cv %>% dplyr::select(.metric, mean, std_err),
                      by = ".metric")
}

.mlada11_cv5_sens <- function(tune_obj, hpbest, eval_cv, model_name) {
  hp_cols <- setdiff(names(hpbest), ".config")
  tune_obj %>%
    tune::collect_predictions() %>%
    dplyr::inner_join(hpbest %>% dplyr::select(dplyr::all_of(hp_cols)),
                      by = hp_cols) %>%
    dplyr::group_by(id) %>%
    yardstick::sens(truth = Group, estimate = .pred_class, event_level = "second") %>%
    dplyr::ungroup() %>%
    dplyr::mutate(model = model_name) %>%
    dplyr::inner_join(eval_cv %>% dplyr::select(.metric, mean, std_err),
                      by = ".metric")
}

#' 轻量二分类 SAMME（stump rpart），避免 adabag/foreach 挂起与 setTimeLimit 无法中断 native 代码
.mlada11_samme_stumps <- function(train_df, mfinal = 20L, seed = 42L) {
  if (!requireNamespace("rpart", quietly = TRUE)) {
    stop("AdaBoost 需要 rpart 包。", call. = FALSE)
  }
  set.seed(as.integer(seed)[1L])
  y <- train_df$Group
  if (!is.factor(y) || nlevels(y) != 2L) {
    stop("AdaBoost SAMME 仅支持二分类因子 Group。", call. = FALSE)
  }
  n <- nrow(train_df)
  w <- rep(1 / n, n)
  trees <- vector("list", mfinal)
  alphas <- rep(NA_real_, mfinal)
  lv <- levels(y)
  ctrl <- rpart::rpart.control(maxdepth = 1L, minsplit = 5L, cp = 0, xval = 0L)
  eps <- 1e-12
  kept <- 0L
  for (m in seq_len(mfinal)) {
    fit_m <- tryCatch(
      rpart::rpart(
        Group ~ ., data = train_df, weights = w,
        method = "class", control = ctrl, model = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(fit_m)) break
    pr <- tryCatch(
      predict(fit_m, newdata = train_df, type = "class"),
      error = function(e) NULL
    )
    if (is.null(pr) || length(pr) != n) break
    pr <- factor(as.character(pr), levels = lv)
    # err: weighted misclassification of current stump
    miss <- as.integer(pr != y)
    err <- sum(w * miss)
    # SAMME: if err >= 0.5 stump is worse than chance → stop
    if (!is.finite(err) || err >= 0.5 - eps || err <= eps) {
      if (err <= eps) {
        # perfect stump
        trees[[m]] <- fit_m
        alphas[[m]] <- 2
        kept <- m
      }
      break
    }
    alpha <- log((1 - err) / err) + log(nlevels(y) - 1)
    if (!is.finite(alpha) || alpha <= 0) break
    trees[[m]] <- fit_m
    alphas[[m]] <- alpha
    kept <- m
    # reweight
    w <- w * exp(alpha * miss)
    s <- sum(w)
    if (!is.finite(s) || s <= 0) break
    w <- w / s
  }
  if (kept < 1L) return(NULL)
  list(
    trees = trees[seq_len(kept)],
    alphas = alphas[seq_len(kept)],
    levels = lv,
    mfinal = kept
  )
}

.mlada11_samme_predict_prob <- function(fit, newdata) {
  n <- nrow(newdata)
  lv <- fit$levels
  acc <- matrix(0, nrow = n, ncol = length(lv))
  colnames(acc) <- lv
  for (i in seq_along(fit$trees)) {
    pr <- as.character(predict(fit$trees[[i]], newdata = newdata, type = "class"))
    for (j in seq_along(lv)) {
      acc[pr == lv[j], j] <- acc[pr == lv[j], j] + fit$alphas[[i]]
    }
  }
  # soft-max over class scores for probability-like output
  acc <- acc - apply(acc, 1L, max)
  ex <- exp(acc)
  rs <- rowSums(ex)
  rs[!is.finite(rs) | rs <= 0] <- 1
  as.data.frame(ex / rs, stringsAsFactors = FALSE)
}

.mlada11_run_adaboost <- function(traindata2, testdata2, folds, seed,
                              pred_ref_col, pred_ana_col, ref_g, ana_g) {
  set.seed(seed)
  n_tr <- as.integer(nrow(traindata2))
  # 仅用数值特征，最多 12 列（哑元膨胀易拖慢/过拟合）
  num_cols <- names(traindata2)[vapply(traindata2, is.numeric, logical(1))]
  keep <- unique(c("Group", utils::head(setdiff(num_cols, "Group"), 12L)))
  keep <- intersect(keep, names(traindata2))
  if (!"Group" %in% keep) keep <- c("Group", keep)
  traindata2 <- traindata2[, keep, drop = FALSE]
  testdata2 <- testdata2[, intersect(keep, names(testdata2)), drop = FALSE]
  # n_train<350 → 轻量；否则稍深（仍远小于经典 adabag 默认）
  mfinal <- if (n_tr < 350L) 20L else 50L
  cli::cli_alert_info(
    "ml_adaboost: SAMME stumps mfinal={mfinal}；特征={length(keep) - 1L}（n_train={n_tr}）"
  )

  final_ada <- tryCatch(
    .mlada11_samme_stumps(traindata2, mfinal = mfinal, seed = seed),
    error = function(e) {
      cli::cli_alert_danger("AdaBoost SAMME 失败: {e$message}")
      NULL
    }
  )
  if (is.null(final_ada)) return(NULL)

  tr_prob <- .mlada11_samme_predict_prob(final_ada, traindata2)
  te_prob <- .mlada11_samme_predict_prob(final_ada, testdata2)
  ref_col <- names(tr_prob)[match(ref_g, names(tr_prob), nomatch = NA_integer_)]
  if (is.na(ref_col)) {
    # levels may be make.names mismatch — fall back to first col if 2-class
    if (ncol(tr_prob) == 2L && ref_g %in% levels(traindata2$Group)) {
      ref_col <- names(tr_prob)[match(ref_g, levels(traindata2$Group), nomatch = 1L)]
    } else {
      stop("AdaBoost 预测概率列中未找到参考组: ", ref_g, call. = FALSE)
    }
  }
  res <- .mlada11_predict_eval_from_prob(
    tr_prob[[ref_col]], te_prob[[ref_col]],
    traindata2, testdata2, "AdaBoost",
    pred_ref_col, pred_ana_col, ref_g, ana_g
  )
  cv5_auc <- data.frame()
  cv5_spec <- data.frame()
  cv5_sens <- data.frame()
  hp_str <- paste0(
    "mfinal=", final_ada$mfinal, ", backend=samme_rpart, features=", length(keep) - 1L
  )

  list(
    model = final_ada, eval = res$eval,
    predtrain = res$predtrain, predtest = res$predtest,
    final_predictions = res$final_predictions,
    cv5_auc = cv5_auc, cv5_spec = cv5_spec, cv5_sens = cv5_sens,
    hpbest_frame = data.frame(Model = "AdaBoost (SAMME)", Hyperparameter = hp_str)
  )
}

block_ml_adaboost <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(tidymodels)
    library(dplyr)
  })
  bl_cfg <- ctx$config$ml_adaboost %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_adaboost$enable=FALSE，跳过。")
    return(ctx)
  }

  prep <- .mlada11_prep(ctx, bl_cfg)
  ctx <- prep$ctx
  tag <- "adaboost"

  if (!.mlada11_check_limits(prep$n_train, prep$min_class_n, bl_cfg, tag)) return(ctx)

  cli::cli_h2("ml_adaboost: 训练 {toupper(tag)}；折数={prep$fold_num}；种子={prep$seed_val}")


  rec <- .mlada11_build_recipe(prep$df_train, scale_type = "none")
  tr2 <- recipes::bake(rec, new_data = NULL) %>% dplyr::select(Group, dplyr::everything())
  te2 <- recipes::bake(rec, new_data = prep$df_validation) %>% dplyr::select(Group, dplyr::everything())

  set.seed(prep$seed_val)
  folds <- rsample::vfold_cv(tr2, v = prep$fold_num)

  res <- tryCatch(
    .mlada11_run_adaboost(
      tr2, te2, folds,
      seed = prep$seed_val,
      pred_ref_col = prep$pred_ref_col,
      pred_ana_col = prep$pred_ana_col,
      ref_g = prep$ref_group,
      ana_g = prep$ana_group
    ),
    error = function(e) {
      cli::cli_alert_danger("{toupper(tag)} 失败: {e$message}")
      NULL
    }
  )
  if (is.null(res)) return(ctx)

  saved <- .mlada11_save_tidymodels(prep, tag, res)
  ctx <- .mlada11_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- saved$model
  ctx$results$ml_predictions_all[[tag]] <- saved$preds
  ctx$results$ml_eval_by_model[[tag]] <- saved$eval
  cli::cli_alert_success("ml_adaboost 完成。")
  ctx
}

register_block("ml_adaboost", block_ml_adaboost, "AdaBoost (SAMME/rpart) 训练 + 评估")
