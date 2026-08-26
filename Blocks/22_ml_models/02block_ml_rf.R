###############################################################################
#  ml_rf — Random Forest 网格调参 + 评估
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_data += ctx$data$train / ctx$data$test（须先 train_validation）
#  require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors
#
#  ml_rf = list(
#    enable = TRUE,
#    cv_folds = NULL,              # NULL → splitting$seed 链 / 默认 5
#    seed = NULL,
#    limits = list(),              # 可选：min_total_n / min_class_n / min_train_n / max_train_n
#    pause_enable = TRUE,
#    pause_on_missing_data = TRUE,
#    rf_engine = "randomForest",  # randomForest | ranger
#  ),
#
#  register_block: "ml_rf"
#  典型流水线: train_validation → 本块 → ml_aggregate
###############################################################################


.mlrf02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.mlrf02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "ml_rf",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ml_rf — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.mlrf02_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mlrf02_check_limits <- function(n_train, min_class_n, bl_cfg, tag) {
  lm <- bl_cfg$limits %||% list()
  if (!length(lm)) return(TRUE)
  ok <- TRUE
  if (!is.null(lm$min_total_n)) {
    req <- as.integer(lm$min_total_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_rf: 训练集 n={n_train} < min_total_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_class_n)) {
    req <- as.integer(lm$min_class_n)[1L]
    if (is.finite(req) && min_class_n < req) {
      cli::cli_alert_info("ml_rf: 最小类 n={min_class_n} < min_class_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_train_n)) {
    req <- as.integer(lm$min_train_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_rf: 训练集 n={n_train} < min_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$max_train_n)) {
    req <- as.integer(lm$max_train_n)[1L]
    if (is.finite(req) && n_train > req) {
      cli::cli_alert_info("ml_rf: 训练集 n={n_train} > max_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  ok
}

.mlrf02_prep <- function(ctx, bl_cfg) {
  cfg <- ctx$config
  sp_cfg <- cfg$splitting %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  id_col <- cfg$data$id_column %||% NULL
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group <- cfg$project$reference_group %||% "Control"
  fold_num <- as.integer(bl_cfg$cv_folds %||% cfg$ml_rf$cv_folds %||% cfg$ml_models$cv_folds %||% 5L)[1L]
  seed_val <- as.integer(bl_cfg$seed %||% sp_cfg$seed %||% cfg$imputation$seed %||% 42L)[1L]
  pred_ref_col <- .mlrf02_prob_col_name(ref_group)
  pred_ana_col <- .mlrf02_prob_col_name(ana_group)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    if (.mlrf02_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlrf02_pause(ctx, "无 imputed/cleaned 数据", "请先运行 imputation / data_clean。")
    }
    stop("ml_rf: 无数据。", call. = FALSE)
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
    if (.mlrf02_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlrf02_pause(ctx, "feature_selection_final 为空", "请先运行 feature_selection。")
    }
    stop("ml_rf: feature_selection_final 为空。", call. = FALSE)
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
  if (!length(feats)) stop("ml_rf: 无可用特征。", call. = FALSE)

  if (!outcome_col %in% names(data)) {
    stop("ml_rf: 结局列不在数据中。", call. = FALSE)
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
  if (nrow(data_ml) < 30L) stop("ml_rf: 有效样本过少。", call. = FALSE)

  if (is.null(ctx$data$train) || is.null(ctx$data$test)) {
    if (.mlrf02_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlrf02_pause(ctx, "缺少 train/test", "请先 run_block(ctx, \"train_validation\")。")
    }
    stop("ml_rf: 缺少 ctx$data$train / test。", call. = FALSE)
  }

  df_train <- ctx$data$train
  df_validation <- ctx$data$test
  cn_model <- c("Group", intersect(feats, names(df_train)))
  miss <- setdiff(feats, names(df_train))
  if (length(miss)) stop("ml_rf: 训练集缺少特征列。", call. = FALSE)
  df_train <- df_train[, cn_model, drop = FALSE]
  df_validation <- df_validation[, cn_model, drop = FALSE]

  n_train <- nrow(df_train)
  cls_tab <- table(df_train$Group)
  min_class_n <- if (length(cls_tab)) min(as.integer(cls_tab)) else 0L

  lm <- bl_cfg$limits %||% list()
  margin <- as.integer(lm$cv_min_class_margin %||% 1L)[1L]
  max_fold <- max(2L, min_class_n - margin)
  if (is.finite(max_fold) && max_fold >= 2L && fold_num > max_fold) {
    cli::cli_alert_info("ml_rf: CV 折数 {fold_num} → {max_fold}（最小类 n={min_class_n}）。")
    fold_num <- max_fold
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

.mlrf02_save_tidymodels <- function(prep, tag, res) {
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

.mlrf02_write_ctx_meta <- function(ctx, prep) {
  ctx$results$ml_train_data <- prep$df_train
  ctx$results$ml_test_data <- prep$df_validation
  ctx$results$ml_pred_ref_col <- prep$pred_ref_col
  ctx$results$ml_pred_ana_col <- prep$pred_ana_col
  ctx$results$ml_feature_names <- prep$feats
  ctx$results$ml_models_models_dir <- prep$models_dir
  ctx$results$ml_models <- ctx$results$ml_models %||% list()
  ctx$results$ml_predictions_all <- ctx$results$ml_predictions_all %||% list()
  ctx$results$ml_eval_by_model <- ctx$results$ml_eval_by_model %||% list()
  ctx
}

.mlrf02_build_recipe <- function(train_dat, scale_type = "none") {
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

.mlrf02_yueden <- function(roc_tbl) {
  roc_tbl %>%
    dplyr::mutate(yueden = sensitivity + specificity - 1) %>%
    dplyr::slice_max(yueden, n = 1, with_ties = FALSE) %>%
    dplyr::pull(.threshold)
}

.mlrf02_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mlrf02_prob_col_candidates <- function(group_label) {
  g <- as.character(group_label)[1L]
  unique(c(paste0(".pred_", g), paste0(".pred_", make.names(g))))
}

.mlrf02_detect_prob_col <- function(df, group_label, preferred = NULL) {
  nms <- names(df)
  if (!is.null(preferred) && preferred %in% nms) return(preferred)
  cands <- .mlrf02_prob_col_candidates(group_label)
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

.mlrf02_predict_eval <- function(fit_obj, train2, test2,
                              model_name, pred_ref_col, pred_ana_col,
                              ref_g, ana_g) {
  grp_levels <- levels(train2$Group)

  .pred_one <- function(new_data, ds_label) {
    pred_prob <- stats::predict(fit_obj, new_data = new_data, type = "prob")
    ref_col <- .mlrf02_detect_prob_col(pred_prob, ref_g, preferred = pred_ref_col)
    ana_col <- .mlrf02_detect_prob_col(pred_prob, ana_g, preferred = pred_ana_col)
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

  yueden <- .mlrf02_yueden(roctrain)

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
      summary(event_level = "first") %>%
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
    ref_col <- .mlrf02_detect_prob_col(pred_prob, ref_g, preferred = pred_ref_col)
    ana_col <- .mlrf02_detect_prob_col(pred_prob, ana_g, preferred = pred_ana_col)
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

.mlrf02_predict_eval_from_prob <- function(
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
  yueden <- .mlrf02_yueden(roctrain)

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
      summary(event_level = "first") %>%
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

.mlrf02_cv5_auc <- function(tune_obj, hpbest, eval_cv, model_name, pred_ref_col) {
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

.mlrf02_cv5_spec <- function(tune_obj, hpbest, eval_cv, model_name) {
  hp_cols <- setdiff(names(hpbest), ".config")
  tune_obj %>%
    tune::collect_predictions() %>%
    dplyr::inner_join(hpbest %>% dplyr::select(dplyr::all_of(hp_cols)),
                      by = hp_cols) %>%
    dplyr::group_by(id) %>%
    yardstick::spec(truth = Group, estimate = .pred_class) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(model = model_name) %>%
    dplyr::inner_join(eval_cv %>% dplyr::select(.metric, mean, std_err),
                      by = ".metric")
}

.mlrf02_cv5_sens <- function(tune_obj, hpbest, eval_cv, model_name) {
  hp_cols <- setdiff(names(hpbest), ".config")
  tune_obj %>%
    tune::collect_predictions() %>%
    dplyr::inner_join(hpbest %>% dplyr::select(dplyr::all_of(hp_cols)),
                      by = hp_cols) %>%
    dplyr::group_by(id) %>%
    yardstick::sens(truth = Group, estimate = .pred_class) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(model = model_name) %>%
    dplyr::inner_join(eval_cv %>% dplyr::select(.metric, mean, std_err),
                      by = ".metric")
}

.mlrf02_run_rf <- function(traindata2, testdata2, folds, seed,
                        pred_ref_col, pred_ana_col, ref_g, ana_g,
                        rf_engine = "randomForest") {
  rf_engine <- tolower(trimws(as.character(rf_engine)[1L]))
  if (identical(rf_engine, "randomforest")) rf_engine <- "randomForest"
  if (!rf_engine %in% c("randomForest", "ranger")) rf_engine <- "randomForest"
  model_rf <- parsnip::rand_forest(
    mode = "classification", engine = rf_engine,
    mtry = tune::tune(), trees = tune::tune(), min_n = tune::tune()
  )
  model_rf <- if (identical(rf_engine, "ranger")) {
    model_rf %>% parsnip::set_args(importance = "permutation")
  } else {
    model_rf %>% parsnip::set_args(importance = TRUE)
  }

  wk_rf <- workflows::workflow() %>%
    workflows::add_model(model_rf) %>%
    workflows::add_formula(Group ~ .)

  hpset_rf <- dials::parameters(
    dials::mtry(range = c(2, 10)),
    dials::trees(range = c(200, 500)),
    dials::min_n(range = c(20, 50))
  )
  hpgrid_rf <- dials::grid_regular(hpset_rf, levels = c(2, 2, 2))

  set.seed(seed)
  tune_rf <- wk_rf %>%
    tune::tune_grid(
      resamples = folds, grid = hpgrid_rf,
      metrics = yardstick::metric_set(
        yardstick::accuracy, yardstick::roc_auc, yardstick::spec,
        yardstick::sens, yardstick::kap, yardstick::pr_auc
      ),
      control = tune::control_grid(save_pred = TRUE, verbose = FALSE)
    )

  eval_tune <- tune::collect_metrics(tune_rf)

  hpbest      <- tune::select_best(tune_rf, metric = "roc_auc")
  hpbest_spec <- tune::select_best(tune_rf, metric = "spec")
  hpbest_sens <- tune::select_best(tune_rf, metric = "sens")

  hp_keys <- setdiff(names(hpbest), ".config")
  eval_cv      <- eval_tune %>% dplyr::inner_join(hpbest      %>% dplyr::select(dplyr::all_of(hp_keys)), by = hp_keys)
  eval_cv_spec <- eval_tune %>% dplyr::inner_join(hpbest_spec %>% dplyr::select(dplyr::all_of(hp_keys)), by = hp_keys)
  eval_cv_sens <- eval_tune %>% dplyr::inner_join(hpbest_sens %>% dplyr::select(dplyr::all_of(hp_keys)), by = hp_keys)

  set.seed(seed)
  final_rf <- wk_rf %>% tune::finalize_workflow(hpbest) %>% parsnip::fit(traindata2)

  res <- .mlrf02_predict_eval(final_rf, traindata2, testdata2,
                           "RF", pred_ref_col, pred_ana_col, ref_g, ana_g)

  cv5_auc  <- .mlrf02_cv5_auc(tune_rf,  hpbest,      eval_cv,      "RF", pred_ref_col)
  cv5_spec <- .mlrf02_cv5_spec(tune_rf, hpbest_spec,  eval_cv_spec, "RF")
  cv5_sens <- .mlrf02_cv5_sens(tune_rf, hpbest_sens,  eval_cv_sens, "RF")

  hp_str <- paste(
    names(hpbest)[names(hpbest) != ".config"],
    vapply(names(hpbest)[names(hpbest) != ".config"],
           function(n) as.character(hpbest[[n]][1L]), character(1L)),
    sep = "=", collapse = ", "
  )

  list(
    model = final_rf, eval = res$eval,
    predtrain = res$predtrain, predtest = res$predtest,
    final_predictions = res$final_predictions,
    cv5_auc = cv5_auc, cv5_spec = cv5_spec, cv5_sens = cv5_sens,
    hpbest_frame = data.frame(Model = "Random Forest (RF)", Hyperparameter = hp_str)
  )
}

block_ml_rf <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(tidymodels)
    library(dplyr)
  })
  bl_cfg <- ctx$config$ml_rf %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_rf$enable=FALSE，跳过。")
    return(ctx)
  }

  prep <- .mlrf02_prep(ctx, bl_cfg)
  ctx <- prep$ctx
  tag <- "rf"

  if (!.mlrf02_check_limits(prep$n_train, prep$min_class_n, bl_cfg, tag)) return(ctx)

  cli::cli_h2("ml_rf: 训练 {toupper(tag)}；折数={prep$fold_num}；种子={prep$seed_val}")

  rf_engine <- tolower(trimws(as.character(bl_cfg$rf_engine %||% ctx$config$ml_models$rf_engine %||% "randomForest")[1L]))
  if (identical(rf_engine, "randomforest")) rf_engine <- "randomForest"

  rec <- .mlrf02_build_recipe(prep$df_train, scale_type = "none")
  tr2 <- recipes::bake(rec, new_data = NULL) %>% dplyr::select(Group, dplyr::everything())
  te2 <- recipes::bake(rec, new_data = prep$df_validation) %>% dplyr::select(Group, dplyr::everything())

  set.seed(prep$seed_val)
  folds <- rsample::vfold_cv(tr2, v = prep$fold_num)

  res <- tryCatch(
    .mlrf02_run_rf(
      tr2, te2, folds,
      seed = prep$seed_val,
      pred_ref_col = prep$pred_ref_col,
      pred_ana_col = prep$pred_ana_col,
      ref_g = prep$ref_group,
      ana_g = prep$ana_group, rf_engine = rf_engine
    ),
    error = function(e) {
      cli::cli_alert_danger("{toupper(tag)} 失败: {e$message}")
      NULL
    }
  )
  if (is.null(res)) return(ctx)

  saved <- .mlrf02_save_tidymodels(prep, tag, res)
  ctx <- .mlrf02_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- saved$model
  ctx$results$ml_predictions_all[[tag]] <- saved$preds
  ctx$results$ml_eval_by_model[[tag]] <- saved$eval
  cli::cli_alert_success("ml_rf 完成。")
  ctx
}

register_block("ml_rf", block_ml_rf, "Random Forest 网格调参 + 评估")
