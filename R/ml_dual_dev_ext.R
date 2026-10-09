###############################################################################
#  ml_dual_dev_ext.R — 双库发病/预后 ML：大库开发(train/内验) + 小库整库外验
#  单库不走本口径。文献口径：COPD ICU interpretable ML
#  (Respir Res 2026, 三集 ROC：开发内验 / 时间外验 / 地理外验)
###############################################################################

ml_dual_is_dev_ext_mode <- function(cfg = list()) {
  st <- tolower(trimws(as.character((cfg$project %||% list())$study_type %||% "")[1L]))
  ## 发病 / 预后双库均可走「大库开发(7:3) + 小库整库外验冻结模型」。
  ## 预后此前被注释排除；17_AKI 双库预后 ML 需同口径，故放开 prognosis。
  if (!st %in% c("incidence", "prognosis")) return(FALSE)
  split <- as.character(
    (cfg$ml_batch %||% list())$split_mode %||%
      (cfg$incidence_batch %||% list())$split_mode %||% ""
  )[1L]
  identical(split, "dev_internal_ext")
}

ml_dual_apply_dev_ext_overrides <- function(config) {
  if (!ml_dual_is_dev_ext_mode(config)) return(config)
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  bc$pub_figure_scheme <- "ml_dual_dev_ext"
  config$ml_batch <- bc
  config$incidence_batch <- bc
  config$multicollinearity <- modifyList(
    config$multicollinearity %||% list(),
    list(selection_on = "train", data_slots = "train")
  )
  config$performance_ml <- modifyList(
    config$performance_ml %||% list(),
    list(combined_panel = FALSE)
  )
  config$supplementary_ml <- modifyList(
    config$supplementary_ml %||% list(),
    list(methods = c("hyperparameters"))
  )
  config$baseline_binary <- modifyList(
    config$baseline_binary %||% list(),
    list(
      export_train_val_baseline = TRUE,
      train_val_table_title =
        "Baseline characteristics by training and internal validation sets (after multiple imputation)"
    )
  )
  ## 加权主库（baseline_nhanes）同口径：train-vs-internal 附表（S12 对齐 14_肌少症）
  config$baseline_nhanes <- modifyList(
    config$baseline_nhanes %||% list(),
    list(
      export_train_val_baseline = TRUE,
      train_val_table_title =
        "Baseline characteristics by training and internal validation sets (after multiple imputation)"
    )
  )
  config
}

ml_dual_apply_dev_ext_db_overrides <- function(config, is_primary) {
  if (!ml_dual_is_dev_ext_mode(config)) {
    ## 默认次库仍自训；冻结外验块关掉
    if (!isTRUE(is_primary)) {
      config$ml_eval_external <- modifyList(
        config$ml_eval_external %||% list(),
        list(enable = FALSE)
      )
    }
    return(config)
  }
  if (isTRUE(is_primary)) {
    config$ml_eval_external <- modifyList(
      config$ml_eval_external %||% list(),
      list(enable = FALSE)
    )
    return(config)
  }
  config$train_validation <- modifyList(
    config$train_validation %||% list(),
    list(mode = "external_all", export_baseline_table = FALSE)
  )
  config$imputation <- modifyList(
    config$imputation %||% list(),
    list(
      export_table_s1 = TRUE,
      export_table_s1_validation = FALSE,
      table_s1_title =
        "Baseline characteristics before and after imputation (external validation set)"
    )
  )
  config$baseline_binary <- modifyList(
    config$baseline_binary %||% list(),
    list(export_train_val_baseline = FALSE)
  )
  config$ml_eval_external <- modifyList(
    config$ml_eval_external %||% list(),
    list(enable = TRUE)
  )
  config$ml_models <- modifyList(
    config$ml_models %||% list(),
    list(enable = FALSE)
  )
  config$performance_ml <- modifyList(
    config$performance_ml %||% list(),
    list(enable = FALSE, combined_panel = FALSE)
  )
  config$supplementary_ml <- modifyList(
    config$supplementary_ml %||% list(),
    list(enable = FALSE)
  )
  config$shap <- modifyList(config$shap %||% list(), list(enable = FALSE))
  config$shiny_ml_app <- modifyList(
    config$shiny_ml_app %||% list(),
    list(enable = FALSE)
  )
  config
}

ml_dual_dev_ext_find_evalresults <- function(db_dir) {
  db_dir <- as.character(db_dir %||% "")[1L]
  if (!nzchar(db_dir) || !dir.exists(db_dir)) return(character(0))
  hits <- list.files(
    db_dir,
    pattern = "^evalresult_.+\\.RData$",
    recursive = TRUE,
    full.names = TRUE
  )
  hits <- hits[grepl("/Models/", hits, ignore.case = TRUE)]
  hits <- hits[!grepl("ShinyApp", hits, ignore.case = TRUE)]
  unique(hits)
}

ml_dual_dev_ext_tag_from_evalpath <- function(path) {
  bn <- basename(as.character(path)[1L])
  sub("^evalresult_(.+)\\.RData$", "\\1", bn, ignore.case = TRUE)
}

ml_dual_dev_ext_load_eval <- function(path) {
  env <- new.env(parent = emptyenv())
  ok <- tryCatch({
    load(path, envir = env)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) return(NULL)
  tag <- ml_dual_dev_ext_tag_from_evalpath(path)
  pt <- paste0("predtrain_", tag)
  pv <- paste0("predtest_", tag)
  ft <- paste0("final_", tag)
  list(
    tag = tag,
    env = env,
    predtrain = if (exists(pt, envir = env, inherits = FALSE)) get(pt, envir = env) else NULL,
    predtest = if (exists(pv, envir = env, inherits = FALSE)) get(pv, envir = env) else NULL,
    final = if (exists(ft, envir = env, inherits = FALSE)) get(ft, envir = env) else NULL
  )
}

ml_dual_dev_ext_prob_ana <- function(pred_df, ana_group) {
  if (is.null(pred_df) || !is.data.frame(pred_df)) return(NULL)
  nms <- names(pred_df)
  cands <- unique(c(
    paste0(".pred_", make.names(as.character(ana_group)[1L])),
    paste0(".pred_", as.character(ana_group)[1L])
  ))
  hit <- intersect(cands, nms)
  if (length(hit)) return(as.numeric(pred_df[[hit[[1L]]]]))
  extra <- nms[grepl("^\\.pred_", nms) & nms != ".pred_class"]
  if (length(extra) == 1L) return(as.numeric(pred_df[[extra]]))
  if ("predicted_prob" %in% nms) return(as.numeric(pred_df$predicted_prob))
  NULL
}

ml_dual_dev_ext_youden_from_train <- function(predtrain, ana_group, ref_group) {
  p_ana <- ml_dual_dev_ext_prob_ana(predtrain, ana_group)
  if (is.null(p_ana) || !"Group" %in% names(predtrain)) return(0.5)
  y <- as.integer(as.character(predtrain$Group) == as.character(ana_group)[1L])
  ok <- is.finite(p_ana) & is.finite(y)
  if (sum(ok) < 10L || length(unique(y[ok])) < 2L) return(0.5)
  roc <- tryCatch(
    yardstick::roc_curve(
      data.frame(Group = factor(predtrain$Group[ok], levels = c(ref_group, ana_group)),
                 p = p_ana[ok]),
      Group, p,
      event_level = "second"
    ),
    error = function(e) NULL
  )
  if (is.null(roc) || !nrow(roc)) return(0.5)
  roc$y <- roc$sensitivity + roc$specificity - 1
  roc <- roc[order(-roc$y), , drop = FALSE]
  as.numeric(roc$.threshold[[1L]])
}

ml_dual_dev_ext_scale_for_tag <- function(tag) {
  t <- tolower(as.character(tag)[1L])
  if (t %in% c("enet", "rsvm")) return("center_scale")
  if (t %in% c("mlp", "realmlp")) return("range")
  "none"
}

#' 按主库训练集重建 recipes（dummy + 可选标准化），bake 外验新数据
ml_dual_dev_ext_bake_newdata <- function(train, newdata, feats, scale_type = "none") {
  if (is.null(train) || !is.data.frame(train) || !nrow(train)) {
    stop("bake: 需要非空主库训练集", call. = FALSE)
  }
  if (is.null(newdata) || !is.data.frame(newdata) || !nrow(newdata)) {
    stop("bake: 需要非空新数据", call. = FALSE)
  }
  if (!requireNamespace("recipes", quietly = TRUE)) {
    stop("bake: 需要 recipes 包", call. = FALSE)
  }
  keep <- unique(c(as.character(feats), "Group"))
  keep <- keep[nzchar(keep)]
  miss_tr <- setdiff(keep, names(train))
  miss_nd <- setdiff(keep, names(newdata))
  if (length(miss_tr)) {
    stop("bake: 主库训练缺列: ", paste(miss_tr, collapse = ", "), call. = FALSE)
  }
  if (length(miss_nd)) {
    stop("bake: 新数据缺列: ", paste(miss_nd, collapse = ", "), call. = FALSE)
  }
  tr <- train[, keep, drop = FALSE]
  nd <- newdata[, keep, drop = FALSE]
  for (cn in names(tr)) {
    if (is.factor(tr[[cn]])) {
      nd[[cn]] <- factor(as.character(nd[[cn]]), levels = levels(tr[[cn]]))
    } else if (is.numeric(tr[[cn]]) && !is.numeric(nd[[cn]])) {
      nd[[cn]] <- suppressWarnings(as.numeric(as.character(nd[[cn]])))
    }
  }
  r <- recipes::recipe(Group ~ ., data = tr)
  r <- recipes::step_impute_median(r, recipes::all_numeric_predictors())
  r <- recipes::step_impute_mode(r, recipes::all_nominal_predictors())
  r <- recipes::step_dummy(r, recipes::all_nominal_predictors())
  if (identical(scale_type, "center_scale")) {
    r <- recipes::step_center(r, recipes::all_predictors())
    r <- recipes::step_scale(r, recipes::all_predictors())
  } else if (identical(scale_type, "range")) {
    r <- recipes::step_range(r, recipes::all_predictors())
  }
  recipes::bake(recipes::prep(r, training = tr), new_data = nd)
}

ml_dual_dev_ext_extract_train <- function(obj) {
  if (is.null(obj)) return(NULL)
  if (is.data.frame(obj) && nrow(obj) > 0L) return(obj)
  ctx0 <- if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
  if (is.list(ctx0) && is.list(ctx0$data)) {
    for (slot in c("train", "imputed_train")) {
      tr <- ctx0$data[[slot]]
      if (is.data.frame(tr) && nrow(tr) > 0L) return(tr)
    }
  }
  NULL
}

#' 主库训练表候选路径。worker 把 checkpoint_base 设成 .../checkpoints/by_index/<ix>，
#' 不得再拼一层 by_index/<ix>。
ml_dual_dev_ext_primary_train_candidates <- function(ctx, pri_dir) {
  ix_root <- dirname(as.character(ctx$config$project$output_dir %||% ".")[1L])
  ix <- sub("^【[^】]+】", "", basename(ix_root))
  ck_base <- as.character((ctx$config$dual_db %||% list())$checkpoint_base %||% "")[1L]
  pri_slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
    dual_db_slot_path_name(ctx$config, "nhanes")
  } else {
    as.character((ctx$config$dual_db$primary %||% list())$name %||% "MIMIC_IV")[1L]
  }
  ck_is_index_dir <- nzchar(ck_base) && nzchar(ix) &&
    (identical(basename(ck_base), ix) ||
       grepl(paste0("(^|[/\\\\])by_index[/\\\\]", ix, "$"), ck_base))
  cands <- c(
    ## ML worker：checkpoint_base = checkpoints/by_index/<ix>
    if (nzchar(ck_base)) file.path(ck_base, pri_slot, "imputation.rds") else NA_character_,
    if (nzchar(ck_base)) file.path(ck_base, pri_slot, "ml_models_bundle.rds") else NA_character_,
    ## 若 checkpoint_base 仍是课题 checkpoints 根
    if (nzchar(ck_base) && nzchar(ix) && !isTRUE(ck_is_index_dir)) {
      file.path(ck_base, "by_index", ix, pri_slot, "imputation.rds")
    } else NA_character_,
    file.path(pri_dir, "Data", "df_train.rds")
  )
  if (dir.exists(pri_dir)) {
    extra <- list.files(
      pri_dir,
      pattern = "^df_train\\.rds$",
      recursive = TRUE,
      full.names = TRUE
    )
    extra <- extra[order(grepl("train_validation", extra, ignore.case = TRUE))]
    cands <- c(cands, extra)
  }
  unique(cands[!is.na(cands) & nzchar(as.character(cands))])
}

ml_dual_dev_ext_load_primary_train <- function(ctx, pri_dir) {
  cands <- ml_dual_dev_ext_primary_train_candidates(ctx, pri_dir)
  for (p in cands) {
    if (!file.exists(p)) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    tr <- ml_dual_dev_ext_extract_train(obj)
    if (is.data.frame(tr) && nrow(tr) > 0L) return(tr)
  }
  NULL
}

ml_dual_dev_ext_predict_new <- function(fit, newdata, ana_group, ref_group) {
  if (is.null(fit) || is.null(newdata) || !nrow(newdata)) return(NULL)
  pr <- tryCatch(
    as.data.frame(predict(fit, new_data = newdata, type = "prob")),
    error = function(e) {
      err1 <- conditionMessage(e)
      tryCatch(
        as.data.frame(predict(fit, newdata = newdata, type = "prob")),
        error = function(e2) {
          ## newdata= 回退常掩盖真因（如缺列），优先保留第一次 new_data= 报错
          stop(err1, call. = FALSE)
        }
      )
    }
  )
  if (is.null(pr) || !nrow(pr)) return(NULL)
  ana_col <- intersect(
    unique(c(
      paste0(".pred_", make.names(as.character(ana_group)[1L])),
      paste0(".pred_", as.character(ana_group)[1L])
    )),
    names(pr)
  )
  ref_col <- intersect(
    unique(c(
      paste0(".pred_", make.names(as.character(ref_group)[1L])),
      paste0(".pred_", as.character(ref_group)[1L])
    )),
    names(pr)
  )
  if (!length(ana_col) && ncol(pr) >= 2L) {
    # 两列概率时，第二列常为事件类
    ana_col <- names(pr)[2L]
    ref_col <- names(pr)[1L]
  }
  if (!length(ana_col)) return(NULL)
  out <- newdata[, intersect("Group", names(newdata)), drop = FALSE]
  if (!ncol(out)) out <- data.frame(Group = NA, stringsAsFactors = FALSE)[rep(1L, nrow(pr)), , drop = FALSE]
  want_ana <- paste0(".pred_", make.names(as.character(ana_group)[1L]))
  want_ref <- paste0(".pred_", make.names(as.character(ref_group)[1L]))
  out[[want_ana]] <- as.numeric(pr[[ana_col[[1L]]]])
  if (length(ref_col)) {
    out[[want_ref]] <- as.numeric(pr[[ref_col[[1L]]]])
  } else {
    out[[want_ref]] <- 1 - out[[want_ana]]
  }
  out$dataset <- "test"
  out
}

ml_dual_dev_ext_wide_from_loaded <- function(loaded, which = c("train", "test"), ana_group) {
  which <- match.arg(which)
  mats <- list()
  n_ref <- NA_integer_
  y <- NULL
  for (nm in names(loaded)) {
    L <- loaded[[nm]]
    pr <- if (identical(which, "train")) L$predtrain else L$predtest
    p <- ml_dual_dev_ext_prob_ana(pr, ana_group)
    if (is.null(p)) next
    if (is.na(n_ref)) {
      n_ref <- length(p)
      if (!is.null(pr) && "Group" %in% names(pr)) {
        y <- as.integer(as.character(pr$Group) == as.character(ana_group)[1L])
      }
    }
    if (length(p) != n_ref) next
    mats[[nm]] <- p
  }
  if (!length(mats) || is.null(y)) return(NULL)
  df <- as.data.frame(mats, check.names = FALSE)
  df$D <- y
  df$Outcome <- y
  ok <- is.finite(df$D) & apply(df[, names(mats), drop = FALSE], 1L, function(r) all(is.finite(r)))
  df[ok, , drop = FALSE]
}

ml_dual_dev_ext_display <- function(tag) {
  if (exists(".pm_display_from_tag", mode = "function")) {
    return(.pm_display_from_tag(tag))
  }
  toupper(as.character(tag)[1L])
}

ml_dual_dev_ext_load_db_models <- function(db_dir, ana_group) {
  files <- ml_dual_dev_ext_find_evalresults(db_dir)
  out <- list()
  for (f in files) {
    L <- ml_dual_dev_ext_load_eval(f)
    if (is.null(L)) next
    disp <- ml_dual_dev_ext_display(L$tag)
    out[[disp]] <- L
  }
  out
}

ml_dual_dev_ext_logloss <- function(y, p, eps = 1e-15) {
  y <- as.numeric(y)
  p <- pmin(pmax(as.numeric(p), eps), 1 - eps)
  ok <- is.finite(y) & is.finite(p)
  if (!any(ok)) return(NA_real_)
  -mean(y[ok] * log(p[ok]) + (1 - y[ok]) * log(1 - p[ok]))
}

ml_dual_dev_ext_metric_levels <- function() {
  c("roc_auc", "accuracy", "sens", "spec", "f_meas", "kap", "mcc")
}

#' Youden 切点：宽表列为 P(事件)，event_level=second
ml_dual_dev_ext_youden_from_wide <- function(w, model) {
  if (is.null(w) || !is.data.frame(w) || !nrow(w)) return(0.5)
  if (!model %in% names(w) || !"D" %in% names(w)) return(0.5)
  if (!requireNamespace("yardstick", quietly = TRUE)) return(0.5)
  y <- as.integer(w$D)
  p <- as.numeric(w[[model]])
  ok <- is.finite(p) & is.finite(y)
  if (sum(ok) < 10L || length(unique(y[ok])) < 2L) return(0.5)
  roc <- tryCatch(
    yardstick::roc_curve(
      data.frame(
        Group = factor(y[ok], levels = c(0, 1)),
        p = p[ok]
      ),
      Group, p,
      event_level = "second"
    ),
    error = function(e) NULL
  )
  if (is.null(roc) || !nrow(roc)) return(0.5)
  thr_n <- as.numeric(roc$.threshold)
  roc <- roc[is.finite(thr_n), , drop = FALSE]
  if (!nrow(roc)) return(0.5)
  roc$y <- as.numeric(roc$sensitivity) + as.numeric(roc$specificity) - 1
  roc <- roc[order(-roc$y, na.last = TRUE), , drop = FALSE]
  thr <- as.numeric(roc$.threshold[[1L]])
  if (!is.finite(thr)) 0.5 else as.numeric(thr)
}

#' 平行线指标：AUC + Youden 分类指标（与 performance_ml 宽表同口径）
ml_dual_dev_ext_eval_metrics <- function(w, models, dataset, thresh = NULL) {
  metric_lv <- ml_dual_dev_ext_metric_levels()
  empty <- data.frame(
    model = character(), dataset = character(),
    .metric = character(), .estimate = numeric(),
    stringsAsFactors = FALSE
  )
  if (is.null(w) || !is.data.frame(w) || !nrow(w) || !"D" %in% names(w)) {
    return(empty)
  }
  if (!requireNamespace("yardstick", quietly = TRUE)) return(empty)
  models <- as.character(models)
  models <- models[models %in% names(w)]
  if (!length(models)) return(empty)
  truth <- factor(as.integer(w$D), levels = c(0L, 1L))
  rows <- vector("list", length(models) * length(metric_lv))
  k <- 0L
  for (m in models) {
    p <- as.numeric(w[[m]])
    thr <- 0.5
    if (!is.null(thresh) && m %in% names(thresh)) {
      t1 <- suppressWarnings(as.numeric(thresh[[m]])[1L])
      if (is.finite(t1)) thr <- t1
    }
    est <- factor(as.integer(is.finite(p) & p >= thr), levels = c(0L, 1L))
    auc <- tryCatch(
      as.numeric(yardstick::roc_auc_vec(truth, p, event_level = "second")),
      error = function(e) NA_real_
    )
    acc <- tryCatch(
      as.numeric(yardstick::accuracy_vec(truth, est)),
      error = function(e) NA_real_
    )
    se <- tryCatch(
      as.numeric(yardstick::sens_vec(truth, est, event_level = "second")),
      error = function(e) NA_real_
    )
    sp <- tryCatch(
      as.numeric(yardstick::spec_vec(truth, est, event_level = "second")),
      error = function(e) NA_real_
    )
    f1 <- tryCatch(
      as.numeric(yardstick::f_meas_vec(truth, est, event_level = "second")),
      error = function(e) NA_real_
    )
    kap <- tryCatch(
      as.numeric(yardstick::kap_vec(truth, est)),
      error = function(e) NA_real_
    )
    mcc <- tryCatch(
      as.numeric(yardstick::mcc_vec(truth, est)),
      error = function(e) NA_real_
    )
    vals <- c(auc, acc, se, sp, f1, kap, mcc)
    for (i in seq_along(metric_lv)) {
      k <- k + 1L
      rows[[k]] <- data.frame(
        model = m, dataset = as.character(dataset)[1L],
        .metric = metric_lv[[i]], .estimate = as.numeric(vals[[i]]),
        stringsAsFactors = FALSE
      )
    }
  }
  if (k < 1L) return(empty)
  out <- do.call(rbind, rows[seq_len(k)])
  out$.metric <- factor(as.character(out$.metric), levels = metric_lv)
  rownames(out) <- NULL
  out
}

#' 与 performance_ml Table 3/4 同列：Events + Model / AUC / accuracy / Sens / Spec / F1 / Kappa / MCC
ml_dual_dev_ext_eval_wide_table <- function(ev, digits = 3L, events = NULL, total = NULL) {
  empty <- data.frame(
    Model = character(), AUC = character(), accuracy = character(),
    Sensitivity = character(), Specificity = character(), F1 = character(),
    Kappa = character(), MCC = character(),
    stringsAsFactors = FALSE
  )
  if (is.null(ev) || !nrow(ev)) return(empty)
  models <- unique(as.character(ev$model))
  digits <- as.integer(digits)[1L]
  if (!is.finite(digits) || digits < 0L) digits <- 3L
  fmt <- function(x) {
    x <- suppressWarnings(as.numeric(x)[1L])
    if (!is.finite(x)) return(NA_character_)
    format(round(x, digits), nsmall = digits, scientific = FALSE, trim = TRUE)
  }
  getv <- function(sub, met) {
    hit <- sub$.estimate[as.character(sub$.metric) == met]
    if (!length(hit)) NA_real_ else as.numeric(hit[[1L]])
  }
  rows <- lapply(models, function(m) {
    sub <- ev[as.character(ev$model) == m, , drop = FALSE]
    data.frame(
      Model = m,
      AUC = fmt(getv(sub, "roc_auc")),
      accuracy = fmt(getv(sub, "accuracy")),
      Sensitivity = fmt(getv(sub, "sens")),
      Specificity = fmt(getv(sub, "spec")),
      F1 = fmt(getv(sub, "f_meas")),
      Kappa = fmt(getv(sub, "kap")),
      MCC = fmt(getv(sub, "mcc")),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  ev_n <- suppressWarnings(as.integer(events)[1L])
  tot_n <- suppressWarnings(as.integer(total)[1L])
  if (is.finite(ev_n) && is.finite(tot_n) && tot_n > 0L) {
    ev_row <- out[1L, , drop = FALSE]
    ev_row[1L, ] <- NA_character_
    ev_row$Model <- "Events (Case/Total)"
    ev_row$AUC <- sprintf("%d/%d", ev_n, tot_n)
    out <- rbind(ev_row, out)
  }
  rownames(out) <- NULL
  out
}

ml_dual_dev_ext_compose_pub <- function(index_root, cfg, tables_only = FALSE) {
  if (!ml_dual_is_dev_ext_mode(cfg)) return(invisible(FALSE))
  if (!dir.exists(index_root)) return(invisible(FALSE))
  pri <- dual_db_slot_path_name(cfg, "nhanes")
  sec <- dual_db_slot_path_name(cfg, "mimic")
  pri_dir <- file.path(index_root, pri)
  sec_dir <- file.path(index_root, sec)
  ## pred 列名是 tidymodels 的 .pred_<显示名>：结局 0/1 在流水线内被
  ## pipeline_relabel_binary_outcome_column 重标为疾病显示名（如 AKI）。
  ## 必须用重标后的 analysis 显示名，否则 .pred_1 找不到 → 三集宽表全 NULL。
  ana <- {
    lbl <- tryCatch(
      pipeline_resolve_outcome_display_labels(cfg),
      error = function(e) NULL
    )
    a0 <- as.character(cfg$project$analysis_group %||% cfg$project$disease %||% "Case")[1L]
    if (!is.null(lbl) && nzchar(as.character(lbl$analysis %||% "")[1L])) {
      as.character(lbl$analysis)[1L]
    } else {
      a0
    }
  }
  pri_nm <- as.character((cfg$dual_db$primary %||% list())$name %||% pri)[1L]
  sec_nm <- as.character((cfg$dual_db$secondary %||% list())$name %||% sec)[1L]
  pri_lab <- gsub("_", " ", pri_nm, fixed = TRUE)
  sec_lab <- gsub("_", " ", sec_nm, fixed = TRUE)

  loaded_pri <- ml_dual_dev_ext_load_db_models(pri_dir, ana)
  loaded_sec <- ml_dual_dev_ext_load_db_models(sec_dir, ana)
  if (!length(loaded_pri) || !length(loaded_sec)) {
    cli::cli_alert_warning("dev_internal_ext: 主库或外验 evalresult 不足，跳过三集拼图。")
    return(invisible(FALSE))
  }

  w_tr <- ml_dual_dev_ext_wide_from_loaded(loaded_pri, "train", ana)
  w_va <- ml_dual_dev_ext_wide_from_loaded(loaded_pri, "test", ana)
  w_ex <- ml_dual_dev_ext_wide_from_loaded(loaded_sec, "test", ana)
  if (is.null(w_tr) || is.null(w_va) || is.null(w_ex)) {
    cli::cli_alert_warning("dev_internal_ext: 三集预测宽表未齐，跳过拼图。")
    return(invisible(FALSE))
  }
  models <- Reduce(intersect, list(names(loaded_pri), names(w_tr), names(w_va), names(w_ex)))
  models <- setdiff(models, c("D", "Outcome"))
  if (!length(models)) return(invisible(FALSE))

  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  pm_src <- file.path(er, "Blocks/23_ml_performance/01block_performance_ml.R")
  if (file.exists(pm_src) && !exists(".pm_multi_roc_plot", mode = "function")) {
    source(pm_src, local = FALSE)
  }
  suppressPackageStartupMessages({
    if (requireNamespace("dplyr", quietly = TRUE)) library(dplyr)
    if (requireNamespace("magrittr", quietly = TRUE)) library(magrittr)
    if (requireNamespace("ggplot2", quietly = TRUE)) library(ggplot2)
    if (requireNamespace("cowplot", quietly = TRUE)) library(cowplot)
  })
  font_family <- if (exists(".pm_font_family", mode = "function")) {
    .pm_font_family(cfg$performance_ml, cfg)
  } else {
    "Times New Roman"
  }
  colors <- if (exists(".pm_default_colors", mode = "function")) {
    .pm_default_colors(length(models))
  } else {
    grDevices::hcl.colors(length(models), "Dark 3")
  }
  titles <- c(
    paste0(pri_lab, " training set"),
    paste0(pri_lab, " internal validation"),
    paste0(sec_lab, " external validation")
  )
  wides <- list(w_tr, w_va, w_ex)

  .grid3 <- function(plots, fn, w = 15, h = 5.2) {
    plots <- plots[!vapply(plots, is.null, logical(1L))]
    if (length(plots) < 3L || !requireNamespace("cowplot", quietly = TRUE)) return(FALSE)
    dest <- file.path(index_root, "Figures")
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    path <- file.path(dest, fn)
    save_one <- function(family) {
      grob <- cowplot::plot_grid(
        plotlist = plots, nrow = 1L, labels = c("A", "B", "C"),
        label_fontfamily = family, label_size = 12
      )
      dev <- if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else grDevices::pdf
      ggplot2::ggsave(path, grob, width = w, height = h, device = dev)
      TRUE
    }
    ok <- tryCatch(save_one(font_family), error = function(e) FALSE)
    if (!isTRUE(ok)) {
      ok <- tryCatch(save_one("serif"), error = function(e) {
        cli::cli_alert_warning("dev_internal_ext 图失败 {fn}: {e$message}")
        FALSE
      })
    }
    isTRUE(ok)
  }

  thr_map <- NULL
  ev_ex <- NULL
  if (requireNamespace("yardstick", quietly = TRUE)) {
    thr_map <- vapply(
      models,
      function(m) ml_dual_dev_ext_youden_from_wide(w_tr, m),
      numeric(1L)
    )
    names(thr_map) <- models
    ev_ex <- ml_dual_dev_ext_eval_metrics(w_ex, models, "test", thr_map)
  }

  if (!isTRUE(tables_only)) {
  roc_ps <- lapply(seq_along(wides), function(i) {
    tryCatch({
      if (!exists(".pm_multi_roc_plot", mode = "function")) return(NULL)
      .pm_multi_roc_plot(wides[[i]], models, colors, titles[[i]], font_family, base_size = 9)
    }, error = function(e) {
      cli::cli_alert_warning("dev_internal_ext ROC 面板 {i} 失败: {e$message}")
      NULL
    })
  })
  cal_ps <- lapply(seq_along(wides), function(i) {
    tryCatch({
      if (!exists(".pm_calibration_plot", mode = "function")) return(NULL)
      ww <- wides[[i]]
      ww$Outcome <- ww$D
      keep <- unique(c("Outcome", intersect(models, names(ww))))
      ww <- ww[, keep, drop = FALSE]
      p <- .pm_calibration_plot(ww, models, colors, titles[[i]], font_family, base_size = 9)
      if (is.null(p)) {
        cli::cli_alert_warning("dev_internal_ext 校准面板 {i} 返回空")
      }
      p
    }, error = function(e) {
      cli::cli_alert_warning("dev_internal_ext 校准面板 {i} 失败: {e$message}")
      NULL
    })
  })
  pm_cfg <- cfg$performance_ml %||% list()
  dca_y_min_fixed <- suppressWarnings(as.numeric(pm_cfg$dca_y_min %||% NA_real_)[1L])
  dca_y_max_fixed <- suppressWarnings(as.numeric(pm_cfg$dca_y_max %||% NA_real_)[1L])
  dca_ps <- lapply(seq_along(wides), function(i) {
    tryCatch({
      if (!exists(".pm_dca_plot", mode = "function")) return(NULL)
      ww <- wides[[i]]
      ww$Outcome <- ww$D
      ev <- mean(as.numeric(ww$D), na.rm = TRUE)
      ## 高事件率：纵轴从 0 起会留下大片空白；收到 treat-all 起点的约 40%
      ymin <- if (is.finite(dca_y_min_fixed)) {
        dca_y_min_fixed
      } else if (is.finite(ev) && ev >= 0.45) {
        max(0, ev * 0.40)
      } else {
        0
      }
      ymax <- if (is.finite(dca_y_max_fixed) && dca_y_max_fixed > ymin) {
        dca_y_max_fixed
      } else {
        NULL
      }
      ## 课题可配 performance_ml$dca_x_max=1 → 横轴 0–100%（label_percent）
      dca_x_max <- suppressWarnings(as.numeric(pm_cfg$dca_x_max %||% NA_real_)[1L])
      if (is.finite(dca_x_max) && dca_x_max > 0) {
        .pm_dca_plot(
          ww, models, font_family, y_max = ymax, y_min = ymin,
          title = titles[[i]], base_size = 9,
          thresholds = seq(0, dca_x_max, by = 0.01),
          x_max = dca_x_max, auto_xlim = FALSE
        )
      } else {
        .pm_dca_plot(
          ww, models, font_family, y_max = ymax, y_min = ymin,
          title = titles[[i]], base_size = 9, auto_xlim = TRUE
        )
      }
    }, error = function(e) {
      cli::cli_alert_warning("dev_internal_ext DCA 面板 {i} 失败: {e$message}")
      NULL
    })
  })
  par_ps <- list(NULL, NULL, NULL)

  ## 平行线：三面板必须共用纵轴，避免外验较低 sensitivity 被局部缩放后误读。
  if (exists(".pm_parallel_metric_plot", mode = "function") &&
      !is.null(thr_map)) {
    ev_tr <- ml_dual_dev_ext_eval_metrics(w_tr, models, "train", thr_map)
    ev_va <- ml_dual_dev_ext_eval_metrics(w_va, models, "test", thr_map)
    metric_min <- suppressWarnings(min(
      c(ev_tr$.estimate, ev_va$.estimate, ev_ex$.estimate),
      na.rm = TRUE
    ))
    metric_ymin <- if (is.finite(metric_min) && metric_min < 0) {
      max(-1, floor(metric_min * 10) / 10)
    } else {
      0
    }
    metric_ylim <- c(metric_ymin, 1)
    par_ps <- list(
      .pm_parallel_metric_plot(
        ev_tr, models, colors, titles[[1L]], font_family, "train", 9,
        y_limits = metric_ylim
      ),
      .pm_parallel_metric_plot(
        ev_va, models, colors, titles[[2L]], font_family, "test", 9,
        y_limits = metric_ylim
      ),
      .pm_parallel_metric_plot(
        ev_ex, models, colors, titles[[3L]], font_family, "test", 9,
        y_limits = metric_ylim
      )
    )
  }

  n_ok <- function(ps) sum(!vapply(ps, is.null, logical(1L)))
  if (!isTRUE(.grid3(roc_ps, "Figure 3. ML ROC training internal and external.pdf"))) {
    cli::cli_alert_warning("dev_internal_ext: Figure 3 未写出（有效面板 {n_ok(roc_ps)}）")
  }
  if (!isTRUE(.grid3(cal_ps, "Figure 4. ML calibration training internal and external.pdf"))) {
    cli::cli_alert_warning("dev_internal_ext: Figure 4 未写出（有效面板 {n_ok(cal_ps)}）")
  }
  if (!isTRUE(.grid3(par_ps, "Figure 5. ML metrics training internal and external.pdf"))) {
    cli::cli_alert_warning("dev_internal_ext: Figure 5 未写出（有效面板 {n_ok(par_ps)}）")
  }
  if (!isTRUE(.grid3(dca_ps, "Figure 6. ML DCA training internal and external.pdf"))) {
    cli::cli_alert_warning("dev_internal_ext: Figure 6 未写出（有效面板 {n_ok(dca_ps)}）")
  }
  }

  ## Log-Loss 三列
  tbl_dir <- file.path(index_root, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  ll <- data.frame(
    Model = models,
    Log_Loss_Train = vapply(models, function(m) ml_dual_dev_ext_logloss(w_tr$D, w_tr[[m]]), numeric(1L)),
    Log_Loss_Internal_validation = vapply(models, function(m) ml_dual_dev_ext_logloss(w_va$D, w_va[[m]]), numeric(1L)),
    Log_Loss_External_validation = vapply(models, function(m) ml_dual_dev_ext_logloss(w_ex$D, w_ex[[m]]), numeric(1L)),
    stringsAsFactors = FALSE
  )
  if (exists(".sm_round_df_numeric", mode = "function")) {
    ll <- .sm_round_df_numeric(ll, 3L)
  } else {
    for (cn in names(ll)[-1L]) ll[[cn]] <- round(ll[[cn]], 3)
  }
  ll_title <- "Log-Loss (training, internal validation, and external validation)"
  .write_tbl <- function(df, title) {
    dest <- file.path(tbl_dir, paste0(title, ".xlsx"))
    if (exists("export_sci_table", mode = "function")) {
      old <- getOption("pipeline.database_name")
      on.exit(options(pipeline.database_name = old), add = TRUE)
      options(pipeline.database_name = "")
      export_sci_table(df, dest, title = title)
      if (exists("flush_pub_output_queues", mode = "function")) {
        flush_pub_output_queues(list(
          config = cfg,
          output_dir = index_root,
          output_dir_tables = tbl_dir
        ))
      }
    } else if (requireNamespace("openxlsx", quietly = TRUE)) {
      openxlsx::write.xlsx(df, dest, overwrite = TRUE)
    }
  }
  if (requireNamespace("yardstick", quietly = TRUE) && !is.null(thr_map)) {
    ev_tr_w <- ml_dual_dev_ext_eval_metrics(w_tr, models, "train", thr_map)
    ev_va_w <- ml_dual_dev_ext_eval_metrics(w_va, models, "test", thr_map)
    if (!is.null(ev_tr_w) && nrow(ev_tr_w)) {
      .write_tbl(
        ml_dual_dev_ext_eval_wide_table(
          ev_tr_w, digits = 3L,
          events = sum(as.integer(w_tr$D) == 1L, na.rm = TRUE),
          total = sum(is.finite(as.integer(w_tr$D)))
        ),
        paste0("Table 3-", pri_lab, ". ML performance wide training")
      )
    }
    if (!is.null(ev_va_w) && nrow(ev_va_w)) {
      .write_tbl(
        ml_dual_dev_ext_eval_wide_table(
          ev_va_w, digits = 3L,
          events = sum(as.integer(w_va$D) == 1L, na.rm = TRUE),
          total = sum(is.finite(as.integer(w_va$D)))
        ),
        paste0("Table 4-", pri_lab, ". ML performance wide validation")
      )
    }
  }
  if (!is.null(ev_ex) && nrow(ev_ex)) {
    wt5 <- ml_dual_dev_ext_eval_wide_table(
      ev_ex,
      digits = 3L,
      events = sum(as.integer(w_ex$D) == 1L, na.rm = TRUE),
      total = sum(is.finite(as.integer(w_ex$D)))
    )
    .write_tbl(
      wt5,
      paste0("Table 5-", sec_lab, ". ML performance wide external validation")
    )
  }
  .write_tbl(ll, paste0("Table S. ", ll_title))

  ## DeLong / NRI：三集各一张
  sm_src <- file.path(er, "Blocks/24_ml_supplementary/01block_supplementary_ml.R")
  if (file.exists(sm_src) && !exists(".sm_run_delong_grid", mode = "function")) {
    source(sm_src, local = FALSE)
  }
  .plist <- function(w) {
    out <- list()
    for (m in models) out[[m]] <- as.numeric(w[[m]])
    out
  }
  sets <- list(
    list(lab = "training set", w = w_tr),
    list(lab = "internal validation set", w = w_va),
    list(lab = "external validation set", w = w_ex)
  )
  for (s in sets) {
    if (exists(".sm_run_delong_grid", mode = "function")) {
      d <- tryCatch(.sm_run_delong_grid(s$w$D, .plist(s$w), "delong"), error = function(e) NULL)
      if (!is.null(d)) {
        if (exists(".sm_round_df_numeric", mode = "function")) {
          d <- .sm_round_df_numeric(d, 3L)
        }
        tit <- paste0("DeLong tests ", s$lab)
        .write_tbl(d, paste0("Table S. ", tit))
      }
    }
    if (exists(".sm_run_nri_grid", mode = "function")) {
      df_rc <- data.frame(Group = s$w$D)
      nri <- tryCatch(
        .sm_run_nri_grid(df_rc, .plist(s$w), c(0, 0.5, 1)),
        error = function(e) NULL
      )
      if (!is.null(nri)) {
        tit <- paste0("NRI and IDI ", s$lab)
        .write_tbl(nri, paste0("Table S. ", tit))
      }
    }
  }
  if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
    cur_src <- file.path(er, "R/ml_dual_pub_table_curate.R")
    if (!file.exists(cur_src)) cur_src <- file.path(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R/ml_dual_pub_table_curate.R"
    )
    if (file.exists(cur_src)) source(cur_src, local = FALSE)
  }
  cur_ok <- FALSE
  if (exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
    cur_ok <- isTRUE(tryCatch({
      incidence_batch_curate_ml_pub_tables(tbl_dir, cfg)
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("dev_internal_ext 表号整理跳过: {e$message}")
      FALSE
    }))
  }
  if (isTRUE(cur_ok)) {
    leftover <- list.files(tbl_dir, pattern = "^Table S\\. ", full.names = TRUE, ignore.case = TRUE)
    if (length(leftover)) {
      unlink(leftover)
      cli::cli_alert_info("已删除无编号草稿表 {length(leftover)} 张")
    }
  }
  cli::cli_alert_success("dev_internal_ext: 已写出三集 Figure 3–6 与 Log-Loss/DeLong 表")
  invisible(TRUE)
}
