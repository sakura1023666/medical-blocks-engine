###############################################################################
#  ml_survival_model_helpers.R — 生存 ML 子块（ml_rsf / ml_xgbsurv）共用
###############################################################################

.mlsurv_source_helpers <- function(ctx) {
  invisible(NULL)
}

.mlsurv_is_prognosis <- function(cfg) {
  st <- identical(tolower(trimws(cfg$project$study_type %||% "incidence")), "prognosis")
  if (isTRUE(st)) return(TRUE)
  ## 单指标预后 ML：流水线可保持 incidence（过 guard / UV），但 assoc=cox + 有生存列
  assoc <- tolower(trimws(as.character(
    (cfg$ml_batch %||% list())$assoc_model %||%
      (cfg$incidence_batch %||% list())$assoc_model %||% ""
  )[1L]))
  has_surv <- nzchar(as.character((cfg$survival %||% list())$time_var %||% "")[1L]) &&
    nzchar(as.character((cfg$survival %||% list())$event_var %||% "")[1L])
  identical(assoc, "cox") && isTRUE(has_surv)
}

.mlsurv_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.mlsurv_pause <- function(ctx, block_id, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = block_id,
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ", block_id, " — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.mlsurv_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mlsurv_check_limits <- function(n_train, n_events, bl_cfg, tag) {
  lm <- bl_cfg$limits %||% list()
  if (!length(lm)) return(TRUE)
  ok <- TRUE
  if (!is.null(lm$min_total_n)) {
    req <- as.integer(lm$min_total_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("{tag}: 训练集 n={n_train} < min_total_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_event_n)) {
    req <- as.integer(lm$min_event_n)[1L]
    if (is.finite(req) && n_events < req) {
      cli::cli_alert_info("{tag}: 训练集事件数={n_events} < min_event_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_train_n)) {
    req <- as.integer(lm$min_train_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("{tag}: 训练集 n={n_train} < min_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$max_train_n)) {
    req <- as.integer(lm$max_train_n)[1L]
    if (is.finite(req) && n_train > req) {
      cli::cli_alert_info("{tag}: 训练集 n={n_train} > max_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  ok
}

.mlsurv_coerce_event01 <- function(x, analysis_group = NULL, reference_group = NULL) {
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x)) {
    ux <- sort(unique(x[is.finite(x)]))
    if (length(ux) == 2L && all(ux %in% c(0, 1))) return(as.integer(round(x)))
    if (length(ux) == 2L && all(ux %in% c(1, 2))) return(as.integer(x == 2))
  }
  if (is.factor(x) || is.character(x)) {
    xc <- trimws(as.character(x))
    ok <- !is.na(xc) & nzchar(xc)
    if (all(xc[ok] %in% c("0", "1"))) return(suppressWarnings(as.integer(xc)))
    if (all(xc[ok] %in% c("1", "2"))) return(as.integer(xc == "2"))
    ana <- trimws(as.character(analysis_group %||% "")[1L])
    ref <- trimws(as.character(reference_group %||% "")[1L])
    if (nzchar(ana) && any(xc[ok] == ana, na.rm = TRUE)) {
      return(as.integer(xc == ana))
    }
    if (nzchar(ref) && any(xc[ok] == ref, na.rm = TRUE) &&
        length(unique(xc[ok])) == 2L) {
      return(as.integer(xc != ref))
    }
    # 常见事件标签（复发/死亡/病例等）→ 1；其余 → 0
    # 注意：排除 "No ... Recurrence" / Non-event 等否定标签，避免全员被标成事件
    ev_pat <- "(?i)(?<!\\bno[-_ ]?)(?<!\\bnon[-_ ]?)(recurr|relaps|death|dead|died|event|case|yes|positive|fail)"
    # R PCRE 对 lookbehind 长度敏感；改用两步：先匹配再剔除否定前缀
    hit_ev <- grepl("(?i)recurr|relaps|death|dead|died|event|case|yes|positive|fail", xc)
    hit_neg <- grepl("(?i)^(no|non|without|absent|negative)\\b|\\bno[-_ ]", xc)
    if (any(hit_ev[ok] & !hit_neg[ok])) {
      return(as.integer(hit_ev & !hit_neg))
    }
    # 因子水平码 1/2 → 事件=第 2 水平（与 Surv 惯例一致：后水平为事件）
    if (is.factor(x) && nlevels(x) == 2L) {
      return(as.integer(as.integer(x) == 2L))
    }
  }
  out <- suppressWarnings(as.integer(as.numeric(x)))
  ux <- sort(unique(out[is.finite(out)]))
  if (length(ux) == 2L && all(ux %in% c(1L, 2L))) return(as.integer(out == 2L))
  out
}

.mlsurv_prep <- function(ctx, bl_cfg, block_id) {
  cfg <- ctx$config
  if (!.mlsurv_is_prognosis(cfg)) {
    cli::cli_alert_info("{block_id}: study_type 非 prognosis，跳过生存树模型。")
    return(NULL)
  }

  sp_cfg <- cfg$splitting %||% list()
  time_var <- cfg$survival$time_var %||% NULL
  event_var <- cfg$survival$event_var %||% NULL
  id_col <- cfg$data$id_column %||% NULL
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group <- cfg$project$reference_group %||% "Control"
  fold_num <- as.integer(bl_cfg$cv_folds %||% cfg[[block_id]]$cv_folds %||% cfg$ml_models$cv_folds %||% 5L)[1L]
  seed_val <- as.integer(bl_cfg$seed %||% sp_cfg$seed %||% cfg$imputation$seed %||% 42L)[1L]
  pred_ref_col <- .mlsurv_prob_col_name(ref_group)
  pred_ana_col <- .mlsurv_prob_col_name(ana_group)

  if (is.null(time_var) || !nzchar(time_var) || is.null(event_var) || !nzchar(event_var)) {
    if (.mlsurv_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlsurv_pause(ctx, block_id, "缺少 survival$time_var / event_var", "请在 config$survival 中设置。")
    }
    stop(block_id, ": 缺少 survival$time_var / event_var。", call. = FALSE)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    if (.mlsurv_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlsurv_pause(ctx, block_id, "无 imputed/cleaned 数据", "请先运行 imputation / data_clean。")
    }
    stop(block_id, ": 无数据。", call. = FALSE)
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
    if (.mlsurv_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlsurv_pause(ctx, block_id, "feature_selection_final 为空", "请先运行 feature_selection。")
    }
    stop(block_id, ": feature_selection_final 为空。", call. = FALSE)
  }

  feats <- if (length(ff0)) {
    as.character(ff0)
  } else {
    as.character(
      ctx$results$Model2Factors %||%
        setdiff(names(data), c(id_col, time_var, event_var, cfg$data$outcome_column))
    )
  }
  feats <- setdiff(intersect(feats, names(data)), c(id_col %||% character(0), time_var, event_var))
  if (!length(feats)) stop(block_id, ": 无可用特征。", call. = FALSE)

  if (!all(c(time_var, event_var) %in% names(data))) {
    stop(block_id, ": time/event 列不在数据中。", call. = FALSE)
  }

  if (is.null(ctx$data$train) || is.null(ctx$data$test)) {
    if (.mlsurv_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mlsurv_pause(ctx, block_id, "缺少 train/test", "请先 run_block(ctx, \"train_validation\")。")
    }
    stop(block_id, ": 缺少 ctx$data$train / test。", call. = FALSE)
  }

  cn_model <- c(time_var, event_var, intersect(feats, names(ctx$data$train)))
  miss <- setdiff(feats, names(ctx$data$train))
  if (length(miss)) stop(block_id, ": 训练集缺少特征列。", call. = FALSE)

  df_train <- ctx$data$train[, cn_model, drop = FALSE]
  df_validation <- ctx$data$test[, cn_model, drop = FALSE]
  names(df_train)[1:2] <- c(".time", ".event")
  names(df_validation)[1:2] <- c(".time", ".event")

  df_train$.time <- suppressWarnings(as.numeric(df_train$.time))
  df_validation$.time <- suppressWarnings(as.numeric(df_validation$.time))
  df_train$.event <- .mlsurv_coerce_event01(
    df_train$.event, analysis_group = ana_group, reference_group = ref_group
  )
  df_validation$.event <- .mlsurv_coerce_event01(
    df_validation$.event, analysis_group = ana_group, reference_group = ref_group
  )

  ok_tr <- is.finite(df_train$.time) & df_train$.time > 0 & !is.na(df_train$.event)
  ok_va <- is.finite(df_validation$.time) & df_validation$.time > 0 & !is.na(df_validation$.event)
  df_train <- df_train[ok_tr, , drop = FALSE]
  df_validation <- df_validation[ok_va, , drop = FALSE]

  n_train <- nrow(df_train)
  n_events <- sum(df_train$.event == 1L, na.rm = TRUE)
  if (n_train < 30L || n_events < 5L) {
    stop(block_id, ": 有效训练样本或事件数过少。", call. = FALSE)
  }

  min_events <- min(sum(df_train$.event == 1L), sum(df_train$.event == 0L))
  margin <- as.integer((bl_cfg$limits %||% list())$cv_min_event_margin %||% 1L)[1L]
  max_fold <- max(2L, min_events - margin)
  if (is.finite(max_fold) && max_fold >= 2L && fold_num > max_fold) {
    cli::cli_alert_info("{block_id}: CV 折数 {fold_num} → {max_fold}（最小事件/删失 n={min_events}）。")
    fold_num <- max_fold
  }

  data_dir <- file.path(ctx$output_dir, "Data")
  if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
  models_dir <- file.path(ctx$output_dir, "Models")
  if (!dir.exists(models_dir)) dir.create(models_dir, recursive = TRUE)
  hpbest_path <- file.path(data_dir, "Hpbest_survival.RData")
  hpbest_list <- if (file.exists(hpbest_path)) {
    e <- new.env(parent = emptyenv()); load(hpbest_path, envir = e); e$hpbest_list
  } else list()

  list(
    ctx = ctx, cfg = cfg, bl_cfg = bl_cfg, block_id = block_id,
    df_train = df_train, df_validation = df_validation,
    ref_group = ref_group, ana_group = ana_group,
    pred_ref_col = pred_ref_col, pred_ana_col = pred_ana_col,
    fold_num = fold_num, seed_val = seed_val,
    feats = feats, n_train = n_train, n_events = n_events,
    time_var = time_var, event_var = event_var,
    data_dir = data_dir, models_dir = models_dir,
    hpbest_path = hpbest_path, hpbest_list = hpbest_list
  )
}

.mlsurv_impute_frame <- function(train_df, new_df = NULL) {
  feat_cols <- setdiff(names(train_df), c(".time", ".event"))
  out_tr <- train_df
  for (col in feat_cols) {
    x <- out_tr[[col]]
    if (is.numeric(x) || is.integer(x) || is.logical(x)) {
      med <- stats::median(suppressWarnings(as.numeric(x)), na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      out_tr[[col]][!is.finite(suppressWarnings(as.numeric(out_tr[[col]])))] <- med
    } else {
      x_chr <- as.character(x)
      x_chr[is.na(x_chr) | !nzchar(trimws(x_chr))] <- NA_character_
      mode_val <- names(sort(table(x_chr), decreasing = TRUE))[1L]
      if (is.na(mode_val) || !nzchar(mode_val)) mode_val <- "Missing"
      x_chr[is.na(x_chr)] <- mode_val
      out_tr[[col]] <- factor(x_chr)
    }
  }
  if (is.null(new_df)) return(out_tr)
  out_va <- new_df
  for (col in feat_cols) {
    ref <- out_tr[[col]]
    x <- out_va[[col]]
    if (is.numeric(ref) || is.integer(ref) || is.logical(ref)) {
      med <- stats::median(suppressWarnings(as.numeric(ref)), na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      out_va[[col]] <- suppressWarnings(as.numeric(x))
      out_va[[col]][!is.finite(out_va[[col]])] <- med
    } else {
      ref_chr <- as.character(ref)
      ref_chr[is.na(ref_chr) | !nzchar(trimws(ref_chr))] <- NA_character_
      mode_val <- names(sort(table(ref_chr), decreasing = TRUE))[1L]
      if (is.na(mode_val) || !nzchar(mode_val)) mode_val <- "Missing"
      lv <- unique(c(levels(ref), mode_val))
      x_chr <- as.character(x)
      x_chr[is.na(x_chr) | !nzchar(trimws(x_chr))] <- mode_val
      x_chr[!(x_chr %in% lv)] <- mode_val
      out_va[[col]] <- factor(x_chr, levels = lv)
      out_tr[[col]] <- factor(ref_chr, levels = lv)
    }
  }
  list(train = out_tr, validation = out_va)
}

.mlsurv_model_matrix <- function(train_df, new_df = NULL) {
  feat_cols <- setdiff(names(train_df), c(".time", ".event"))
  form <- stats::as.formula(paste("~", paste(feat_cols, collapse = " + ")))
  mm_tr <- stats::model.matrix(form, data = train_df)
  mm_tr <- mm_tr[, colnames(mm_tr) != "(Intercept)", drop = FALSE]
  if (is.null(new_df)) {
    return(list(train = mm_tr, validation = NULL, terms = attr(mm_tr, "assign")))
  }
  mm_va <- stats::model.matrix(form, data = new_df)
  cn <- colnames(mm_tr)
  mm_va <- mm_va[, cn, drop = FALSE]
  list(train = mm_tr, validation = mm_va)
}

.mlsurv_cindex <- function(time, event, risk) {
  time <- suppressWarnings(as.numeric(time))
  event <- .mlsurv_coerce_event01(event)
  risk <- suppressWarnings(as.numeric(risk))
  ok <- is.finite(time) & time > 0 & !is.na(event) & is.finite(risk)
  if (sum(ok) < 5L || sum(event[ok] == 1L) < 2L) return(NA_real_)
  ## survival::concordance(公式接口) 把「更大预测值」当成更长生存；
  ## Cox / 风险评分则是「越大风险越高 → 生存越短」，故对 risk 取负再算 C。
  ## 与 coxph()$concordance 方向一致。
  sc <- tryCatch(
    {
      cc <- survival::concordance(
        survival::Surv(time[ok], event[ok]) ~ I(-risk[ok])
      )
      as.numeric(cc$concordance)
    },
    error = function(e) NA_real_
  )
  sc
}

## 若训练集上 -risk 的 C-index 明显高于 risk，则翻转（适配「预测生存时间」类输出）
.mlsurv_orient_risk <- function(time, event, risk_train, risk_test = NULL) {
  c_pos <- .mlsurv_cindex(time, event, risk_train)
  c_neg <- .mlsurv_cindex(time, event, -risk_train)
  flip <- is.finite(c_neg) && (!is.finite(c_pos) || (c_neg - c_pos) > 0.02)
  if (flip) {
    risk_train <- -risk_train
    if (!is.null(risk_test)) risk_test <- -risk_test
  }
  list(train = risk_train, test = risk_test, flipped = flip, c_index_train = if (flip) c_neg else c_pos)
}

.mlsurv_scale01 <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  rng <- range(x[is.finite(x)], na.rm = TRUE)
  if (!all(is.finite(rng)) || diff(rng) < 1e-12) return(rep(0.5, length(x)))
  (x - rng[1]) / (rng[2] - rng[1])
}

.mlsurv_youden <- function(event, risk) {
  ev <- .mlsurv_coerce_event01(event)
  sc <- .mlsurv_scale01(risk)
  if (requireNamespace("pROC", quietly = TRUE)) {
    roc <- tryCatch(
      pROC::roc(response = ev, predictor = sc, quiet = TRUE, direction = "<"),
      error = function(e) NULL
    )
    if (!is.null(roc)) {
      cc <- pROC::coords(roc, "best", ret = "threshold", best.method = "youden", transpose = FALSE)
      return(as.numeric(cc[1L]))
    }
  }
  med <- stats::median(sc[is.finite(sc)], na.rm = TRUE)
  if (!is.finite(med)) 0.5 else med
}

.mlsurv_eval_metrics <- function(time, event, risk, model_name, dataset) {
  ev <- .mlsurv_coerce_event01(event)
  cidx <- .mlsurv_cindex(time, event, risk)
  sc <- .mlsurv_scale01(risk)
  thr <- .mlsurv_youden(ev, risk)
  pred_cls <- ifelse(sc >= thr, 1L, 0L)
  tp <- sum(pred_cls == 1L & ev == 1L, na.rm = TRUE)
  tn <- sum(pred_cls == 0L & ev == 0L, na.rm = TRUE)
  fp <- sum(pred_cls == 1L & ev == 0L, na.rm = TRUE)
  fn <- sum(pred_cls == 0L & ev == 1L, na.rm = TRUE)
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  kap <- if (requireNamespace("yardstick", quietly = TRUE)) {
    df <- data.frame(truth = factor(ev, levels = c(0, 1)), estimate = factor(pred_cls, levels = c(0, 1)))
    suppressWarnings(as.numeric(yardstick::kap(df, truth = truth, estimate = estimate)$.estimate))
  } else NA_real_
  auc <- if (requireNamespace("pROC", quietly = TRUE)) {
    tryCatch(
      as.numeric(pROC::auc(pROC::roc(ev, sc, quiet = TRUE, direction = "<"))),
      error = function(e) NA_real_
    )
  } else NA_real_
  data.frame(
    .metric = c("c_index", "roc_auc", "sens", "spec", "kap"),
    .estimate = c(cidx, auc, sens, spec, kap),
    dataset = dataset,
    model = model_name,
    stringsAsFactors = FALSE
  )
}

.mlsurv_predict_eval <- function(time, event, risk, train_meta, test_meta,
                                 model_name, pred_ref_col, pred_ana_col,
                                 ref_g, ana_g) {
  risk_tr <- .mlsurv_scale01(risk$train)
  risk_te <- .mlsurv_scale01(risk$test)

  predtrain <- data.frame(
    Group = factor(ifelse(train_meta$.event == 1L, ana_g, ref_g), levels = c(ref_g, ana_g)),
    dataset = "train",
    model = model_name,
    stringsAsFactors = FALSE
  )
  predtest <- data.frame(
    Group = factor(ifelse(test_meta$.event == 1L, ana_g, ref_g), levels = c(ref_g, ana_g)),
    dataset = "test",
    model = model_name,
    stringsAsFactors = FALSE
  )
  predtrain[[pred_ref_col]] <- 1 - risk_tr
  predtrain[[pred_ana_col]] <- risk_tr
  predtest[[pred_ref_col]] <- 1 - risk_te
  predtest[[pred_ana_col]] <- risk_te

  eval <- dplyr::bind_rows(
    .mlsurv_eval_metrics(train_meta$.time, train_meta$.event, risk$train, model_name, "train"),
    .mlsurv_eval_metrics(test_meta$.time, test_meta$.event, risk$test, model_name, "test")
  )

  fp_test <- cbind(test_meta, dataset = "Validation set")
  fp_train <- cbind(train_meta, dataset = "Training set")
  fp_test[[paste0(model_name, "_predicted_value")]] <- risk_te
  fp_train[[paste0(model_name, "_predicted_value")]] <- risk_tr
  fp_all <- rbind(fp_test, fp_train)

  list(
    predtrain = predtrain,
    predtest = predtest,
    eval = eval,
    final_predictions = fp_all
  )
}

.mlsurv_save_result <- function(prep, tag, res, model_obj) {
  p <- prep
  hpbest_list <- p$hpbest_list
  if (!is.null(res$hpbest_frame)) {
    hpbest_list[[paste0("hpbest_", tag)]] <- res$hpbest_frame
    save(hpbest_list, file = p$hpbest_path)
  }

  raw_pred_train_obj <- cbind(
    data.frame(predicted_risk = res$risk$train, stringsAsFactors = FALSE),
    p$df_train
  )
  raw_pred_test_obj <- cbind(
    data.frame(predicted_risk = res$risk$test, stringsAsFactors = FALSE),
    p$df_validation
  )
  raw_pred_all_obj <- rbind(raw_pred_train_obj, raw_pred_test_obj)

  save_vars <- list(
    final_model = model_obj,
    final_predictions = res$final_predictions,
    predtrain = res$predtrain,
    predtest = res$predtest,
    eval = res$eval,
    eval_best_cv5 = res$cv5_cindex,
    raw_pred_train = raw_pred_train_obj,
    raw_pred_test = raw_pred_test_obj,
    raw_pred_all = raw_pred_all_obj
  )
  names(save_vars)[1L] <- paste0("final_", tag)
  names(save_vars)[3L] <- paste0("predtrain_", tag)
  names(save_vars)[4L] <- paste0("predtest_", tag)
  names(save_vars)[5L] <- paste0("eval_", tag)
  names(save_vars)[6L] <- paste0("eval_best_cv5_", tag)
  names(save_vars)[7L] <- paste0("raw_pred_train_", tag)
  names(save_vars)[8L] <- paste0("raw_pred_test_", tag)
  names(save_vars)[9L] <- paste0("raw_pred_all_", tag)

  out_file <- file.path(p$models_dir, paste0("evalresult_", tag, ".RData"))
  e_save <- new.env(parent = emptyenv())
  for (nm in names(save_vars)) assign(nm, save_vars[[nm]], envir = e_save)
  save(list = names(save_vars), file = out_file, envir = e_save)
  cli::cli_alert_success("{toupper(tag)} 结果已保存: {.file {out_file}}")
  list(out_file = out_file, eval = res$eval, model = model_obj, preds = res$final_predictions)
}

.mlsurv_write_ctx_meta <- function(ctx, prep) {
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

.mlsurv_cv_cindex_rows <- function(fold_ids, cindex_vec, model_name) {
  data.frame(
    id = fold_ids,
    .metric = "c_index",
    .estimate = cindex_vec,
    model = model_name,
    stringsAsFactors = FALSE
  )
}

###############################################################################
#  通用生存 ML block 收尾 + 网格 CV
###############################################################################

.mlsurv_summarise_cv5 <- function(cv_rows, model_name) {
  cv5 <- dplyr::bind_rows(cv_rows[which(vapply(cv_rows, nrow, integer(1L)) > 0L)])
  if (!nrow(cv5)) return(cv5)
  cv5 <- cv5[cv5$.metric == "c_index" & is.finite(cv5$.estimate), , drop = FALSE]
  if (!nrow(cv5)) return(cv5)
  cv5 %>%
    dplyr::group_by(.data$.metric) %>%
    dplyr::summarise(
      mean = mean(.data$.estimate, na.rm = TRUE),
      std_err = stats::sd(.data$.estimate, na.rm = TRUE) / sqrt(sum(is.finite(.data$.estimate))),
      .groups = "drop"
    ) %>%
    dplyr::mutate(model = model_name)
}

.mlsurv_finish_block <- function(ctx, prep, tag, display_name, res_core) {
  ## 统一风险方向（越高 = 越高复发/死亡风险）
  oriented <- .mlsurv_orient_risk(
    prep$df_train$.time, prep$df_train$.event,
    res_core$risk$train, res_core$risk$test
  )
  if (isTRUE(oriented$flipped)) {
    cli::cli_alert_info(
      "{tag}: 风险评分已翻转以对齐 Cox C-index 方向（train C≈{round(oriented$c_index_train, 3)}）。"
    )
  }
  res_core$risk <- list(train = oriented$train, test = oriented$test)
  pe <- .mlsurv_predict_eval(
    prep$df_train$.time, prep$df_train$.event, res_core$risk,
    prep$df_train, prep$df_validation,
    display_name, prep$pred_ref_col, prep$pred_ana_col,
    prep$ref_group, prep$ana_group
  )
  res <- c(res_core, pe)
  saved <- .mlsurv_save_result(prep, tag, res, res_core$model)
  ctx <- .mlsurv_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- saved$model
  ctx$results$ml_predictions_all[[tag]] <- saved$preds
  ctx$results$ml_eval_by_model[[tag]] <- saved$eval
  ctx
}

.mlsurv_source_self <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  path <- file.path(root, "R/ml_survival_model_helpers.R")
  if (file.exists(path)) source(path, local = FALSE)
}
