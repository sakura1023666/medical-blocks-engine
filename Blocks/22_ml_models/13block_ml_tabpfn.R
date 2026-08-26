###############################################################################
#  ml_tabpfn — tabpfn excel/reticulate
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_data += ctx$data$train / ctx$data$test（须先 train_validation）
#  require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors
#
#  ml_tabpfn = list(
#    enable = TRUE,
#    cv_folds = NULL,              # NULL → splitting$seed 链 / 默认 5
#    seed = NULL,
#    limits = list(),              # 可选：min_total_n / min_class_n / min_train_n / max_train_n
#    pause_enable = TRUE,
#    pause_on_missing_data = TRUE,
#    mode = "excel",               # "excel" | "reticulate"
#    data_path = NULL,
#    reticulate = list(),
#  ),
#
#  register_block: "ml_tabpfn"
#  典型流水线: train_validation → 本块 → ml_aggregate
###############################################################################


.mltp13_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.mltp13_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "ml_tabpfn",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ml_tabpfn — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.mltp13_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mltp13_check_limits <- function(n_train, min_class_n, bl_cfg, tag) {
  lm <- bl_cfg$limits %||% list()
  if (!length(lm)) return(TRUE)
  ok <- TRUE
  if (!is.null(lm$min_total_n)) {
    req <- as.integer(lm$min_total_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_tabpfn: 训练集 n={n_train} < min_total_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_class_n)) {
    req <- as.integer(lm$min_class_n)[1L]
    if (is.finite(req) && min_class_n < req) {
      cli::cli_alert_info("ml_tabpfn: 最小类 n={min_class_n} < min_class_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$min_train_n)) {
    req <- as.integer(lm$min_train_n)[1L]
    if (is.finite(req) && n_train < req) {
      cli::cli_alert_info("ml_tabpfn: 训练集 n={n_train} < min_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  if (!is.null(lm$max_train_n)) {
    req <- as.integer(lm$max_train_n)[1L]
    if (is.finite(req) && n_train > req) {
      cli::cli_alert_info("ml_tabpfn: 训练集 n={n_train} > max_train_n={req}，跳过。")
      ok <- FALSE
    }
  }
  ok
}

.mltp13_prep <- function(ctx, bl_cfg) {
  cfg <- ctx$config
  sp_cfg <- cfg$splitting %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease"
  id_col <- cfg$data$id_column %||% NULL
  ana_group <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_group <- cfg$project$reference_group %||% "Control"
  fold_num <- as.integer(bl_cfg$cv_folds %||% cfg$ml_tabpfn$cv_folds %||% cfg$ml_models$cv_folds %||% 5L)[1L]
  seed_val <- as.integer(bl_cfg$seed %||% sp_cfg$seed %||% cfg$imputation$seed %||% 42L)[1L]
  pred_ref_col <- .mltp13_prob_col_name(ref_group)
  pred_ana_col <- .mltp13_prob_col_name(ana_group)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) {
    if (.mltp13_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mltp13_pause(ctx, "无 imputed/cleaned 数据", "请先运行 imputation / data_clean。")
    }
    stop("ml_tabpfn: 无数据。", call. = FALSE)
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
    if (.mltp13_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mltp13_pause(ctx, "feature_selection_final 为空", "请先运行 feature_selection。")
    }
    stop("ml_tabpfn: feature_selection_final 为空。", call. = FALSE)
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
  if (!length(feats)) stop("ml_tabpfn: 无可用特征。", call. = FALSE)

  if (!outcome_col %in% names(data)) {
    stop("ml_tabpfn: 结局列不在数据中。", call. = FALSE)
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
  if (nrow(data_ml) < 30L) stop("ml_tabpfn: 有效样本过少。", call. = FALSE)

  if (is.null(ctx$data$train) || is.null(ctx$data$test)) {
    if (.mltp13_should_pause(bl_cfg, "pause_on_missing_data")) {
      .mltp13_pause(ctx, "缺少 train/test", "请先 run_block(ctx, \"train_validation\")。")
    }
    stop("ml_tabpfn: 缺少 ctx$data$train / test。", call. = FALSE)
  }

  df_train <- ctx$data$train
  df_validation <- ctx$data$test
  cn_model <- c("Group", intersect(feats, names(df_train)))
  miss <- setdiff(feats, names(df_train))
  if (length(miss)) stop("ml_tabpfn: 训练集缺少特征列。", call. = FALSE)
  df_train <- df_train[, cn_model, drop = FALSE]
  df_validation <- df_validation[, cn_model, drop = FALSE]

  n_train <- nrow(df_train)
  cls_tab <- table(df_train$Group)
  min_class_n <- if (length(cls_tab)) min(as.integer(cls_tab)) else 0L

  lm <- bl_cfg$limits %||% list()
  margin <- as.integer(lm$cv_min_class_margin %||% 1L)[1L]
  max_fold <- max(2L, min_class_n - margin)
  if (is.finite(max_fold) && max_fold >= 2L && fold_num > max_fold) {
    cli::cli_alert_info("ml_tabpfn: CV 折数 {fold_num} → {max_fold}（最小类 n={min_class_n}）。")
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

.mltp13_save_tidymodels <- function(prep, tag, res) {
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

.mltp13_write_ctx_meta <- function(ctx, prep) {
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

.mltp13_prob_col_name <- function(group_label) {
  paste0(".pred_", make.names(as.character(group_label)[1L]))
}

.mltp13_prob_col_candidates <- function(group_label) {
  g <- as.character(group_label)[1L]
  unique(c(paste0(".pred_", g), paste0(".pred_", make.names(g))))
}

.mltp13_detect_prob_col <- function(df, group_label, preferred = NULL) {
  nms <- names(df)
  if (!is.null(preferred) && preferred %in% nms) return(preferred)
  cands <- .mltp13_prob_col_candidates(group_label)
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

.mltp13_run_excel_ml_bundle <- function(
    xlsx_path, ref_g, ana_g, pred_ref_col, pred_ana_col,
    sheet_stem, model_label, long_model_name,
    skip_metric_swap = FALSE) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop(model_label, " 需要 openxlsx 包", call. = FALSE)
  }
  if (!file.exists(xlsx_path)) {
    stop(model_label, " 数据文件不存在: ", xlsx_path, call. = FALSE)
  }

  .rd <- function(sheet) openxlsx::read.xlsx(xlsx_path, sheet = sheet)[, -1L]

  eval_ml           <- .rd(paste0("eval_", sheet_stem))
  eval_ml$model     <- model_label
  predtrain_ml      <- .rd(paste0("predtrain_", sheet_stem))
  predtest_ml       <- .rd(paste0("predtest_", sheet_stem))
  final_predictions_ml <- .rd(paste0("final_predictions_", sheet_stem))
  eval_best_cv5_ml      <- .rd(paste0("eval_best_cv5_", sheet_stem))
  eval_best_cv5_ml$model <- model_label
  eval_best_cv5_ml_spec  <- .rd(paste0("eval_best_cv5_", sheet_stem, "_spec"))
  eval_best_cv5_ml_spec$model <- model_label
  eval_best_cv5_ml_sens  <- .rd(paste0("eval_best_cv5_", sheet_stem, "_sens"))
  eval_best_cv5_ml_sens$model <- model_label

  .fix_pred <- function(df) {
    df <- df[, c(ref_g, ana_g, "Group", "dataset", "model")]
    colnames(df) <- c(pred_ref_col, pred_ana_col, "Group", "dataset", "model")
    df$model <- model_label
    df
  }
  predtrain_ml <- .fix_pred(predtrain_ml)
  predtest_ml  <- .fix_pred(predtest_ml)

  # 旧版外部 Python 脚本：sens/spec 与 R 约定相反；reticulate 本仓库脚本已按 R 约定计算，勿对调
  if (!isTRUE(skip_metric_swap)) {
    ev <- eval_ml
    for (ds in c("train", "test")) {
      s_val <- ev[ev$.metric == "sens" & ev$dataset == ds, ]$.estimate
      p_val <- ev[ev$.metric == "spec" & ev$dataset == ds, ]$.estimate
      ev[ev$.metric == "sens" & ev$dataset == ds, ]$.estimate <- p_val
      ev[ev$.metric == "spec" & ev$dataset == ds, ]$.estimate <- s_val
      ev[ev$.metric == "recall" & ev$dataset == ds, ]$.estimate <- p_val
    }
    eval_ml <- ev

    tmp <- eval_best_cv5_ml_spec
    eval_best_cv5_ml_spec <- eval_best_cv5_ml_sens
    eval_best_cv5_ml_sens <- tmp
    eval_best_cv5_ml_spec$.metric <- "sens"
    eval_best_cv5_ml_sens$.metric <- "spec"
  }

  paras <- openxlsx::read.xlsx(xlsx_path, sheet = "paras")[, -1L]
  hp_str <- gsub(":", "=", as.character(paras[2L, 2L]))

  list(
    model = NULL, eval = eval_ml,
    predtrain = predtrain_ml, predtest = predtest_ml,
    final_predictions = final_predictions_ml,
    cv5_auc = eval_best_cv5_ml, cv5_spec = eval_best_cv5_ml_spec,
    cv5_sens = eval_best_cv5_ml_sens,
    hpbest_frame = data.frame(Model = long_model_name, Hyperparameter = hp_str)
  )
}

.mltp13_run_tabpfn <- function(tabpfn_path, hpbest_rdata_path,
                            ref_g, ana_g, pred_ref_col, pred_ana_col,
                            skip_metric_swap = FALSE) {
  .mltp13_run_excel_ml_bundle(
    tabpfn_path, ref_g, ana_g, pred_ref_col, pred_ana_col,
    sheet_stem = "tabpfn",
    model_label = "TabPFN",
    long_model_name = "Tabular Prior-data Fitted Network (TabPFN)",
    skip_metric_swap = skip_metric_swap
  )
}

.mltp13_tabpfn_run_via_reticulate <- function(
    df_train, df_validation, ref_group, ana_group,
    ml_cfg, cv_folds, seed_val, out_xlsx, project_wd,
    model_version = "v2") {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("TabPFN reticulate 模式需要安装 R 包 reticulate。", call. = FALSE)
  }
  rt <- ml_cfg$tabpfn_reticulate %||% list()

  # Prior Labs JWT：必须在 reticulate::use_python() **之前** Sys.setenv，嵌入的 Python 才会继承 TABPFN_TOKEN
  # （tabpfn.browser_auth.get_cached_token 只读该变量；见 also TABPFN_API_KEY 别名）
  .tabpfn_k <- trimws(Sys.getenv("TABPFN_TOKEN", ""))
  if (!nzchar(.tabpfn_k)) .tabpfn_k <- trimws(Sys.getenv("TABPFN_API_KEY", ""))
  if (!nzchar(.tabpfn_k) && length(rt$tabpfn_token)) {
    .tabpfn_k <- trimws(as.character(rt$tabpfn_token)[1L])
  }
  if (nzchar(.tabpfn_k)) {
    Sys.setenv(TABPFN_TOKEN = .tabpfn_k, TABPFN_API_KEY = .tabpfn_k)
    .tabpfn_tok_file <- tempfile("tabpfn_jwt_", fileext = ".txt")
    writeLines(.tabpfn_k, .tabpfn_tok_file, useBytes = TRUE)
    Sys.setenv(TABPFN_TOKEN_FILE = normalizePath(.tabpfn_tok_file, winslash = "/", mustWork = TRUE))
    on.exit(
      {
        unlink(.tabpfn_tok_file, force = TRUE)
        Sys.unsetenv("TABPFN_TOKEN_FILE")
      },
      add = TRUE
    )
  }

  pyexe <- as.character(rt$python %||% "")[1L]
  if (!nzchar(pyexe)) {
    pyexe <- Sys.which("python")
    if (!nzchar(pyexe)) pyexe <- Sys.which("python3")
  }
  if (!nzchar(pyexe)) {
    stop("未找到 Python 可执行文件。请在 config$ml_models$tabpfn_reticulate$python 中指定。", call. = FALSE)
  }
  # Windows: 去掉 MSYS sh（rtools / Anaconda Library/usr/bin），并补 APPDATA→本地 ckpt
  if (.Platform$OS.type == "windows") {
    pyexe <- gsub("\\\\", "/", pyexe)
    if (grepl("^/[a-zA-Z]/", pyexe) && !grepl("^/(usr|bin|tmp|home|opt|var|mnt)/", pyexe)) {
      pyexe <- paste0(toupper(substr(pyexe, 2L, 2L)), ":", substring(pyexe, 3L))
    }
    py_short <- tryCatch(utils::shortPathName(pyexe), error = function(e) pyexe)
    if (nzchar(py_short)) pyexe <- gsub("\\\\", "/", py_short)
    Sys.setenv(RETICULATE_PYTHON = pyexe)
    .up <- Sys.getenv("USERPROFILE", unset = "")
    if (!nzchar(Sys.getenv("APPDATA", "")) && nzchar(.up)) {
      Sys.setenv(APPDATA = file.path(.up, "AppData", "Roaming", fsep = "\\"))
    }
    if (!nzchar(Sys.getenv("LOCALAPPDATA", "")) && nzchar(.up)) {
      Sys.setenv(LOCALAPPDATA = file.path(.up, "AppData", "Local", fsep = "\\"))
    }
    .sysroot <- Sys.getenv("SystemRoot", unset = "C:\\Windows")
    .py_dir <- gsub("/", "\\\\", dirname(pyexe))
    Sys.setenv(
      COMSPEC = file.path(.sysroot, "System32", "cmd.exe", fsep = "\\"),
      ComSpec = file.path(.sysroot, "System32", "cmd.exe", fsep = "\\"),
      SystemRoot = .sysroot,
      PATH = paste(
        file.path(.sysroot, "System32", fsep = "\\"),
        .sysroot,
        file.path(.sysroot, "System32", "WindowsPowerShell", "v1.0", fsep = "\\"),
        .py_dir,
        "C:\\ProgramData\\anaconda3",
        "C:\\ProgramData\\anaconda3\\Scripts",
        "C:\\ProgramData\\anaconda3\\Library\\bin",
        sep = ";"
      )
    )
  }
  cli::cli_alert_info("TabPFN reticulate python: {.path {pyexe}}")
  if (!file.exists(pyexe)) {
    stop("Python 可执行文件不存在: ", pyexe, call. = FALSE)
  }
  reticulate::use_python(pyexe, required = TRUE)
  # use_python 可能再注入 conda MSYS；立刻清回安全 PATH
  if (.Platform$OS.type == "windows") {
    .sysroot <- Sys.getenv("SystemRoot", unset = "C:\\Windows")
    .py_dir <- gsub("/", "\\\\", dirname(pyexe))
    Sys.setenv(
      COMSPEC = file.path(.sysroot, "System32", "cmd.exe", fsep = "\\"),
      PATH = paste(
        file.path(.sysroot, "System32", fsep = "\\"),
        .sysroot,
        file.path(.sysroot, "System32", "WindowsPowerShell", "v1.0", fsep = "\\"),
        .py_dir,
        "C:\\ProgramData\\anaconda3",
        "C:\\ProgramData\\anaconda3\\Scripts",
        "C:\\ProgramData\\anaconda3\\Library\\bin",
        sep = ";"
      )
    )
  }
  # 嵌入 Python 后再写一遍离线开关 + APPDATA（reticulate 子解释器偶发吃不到 R 的 Sys.setenv）
  reticulate::py_run_string(
    paste(
      "import os",
      "os.environ['HF_HUB_OFFLINE']='1'",
      "os.environ['TRANSFORMERS_OFFLINE']='1'",
      "os.environ['HF_DATASETS_OFFLINE']='1'",
      paste0("os.environ['APPDATA']=", encodeString(Sys.getenv("APPDATA", ""), quote = "\"", na.encode = FALSE)),
      paste0("os.environ['LOCALAPPDATA']=", encodeString(Sys.getenv("LOCALAPPDATA", ""), quote = "\"", na.encode = FALSE)),
      paste0("os.environ['USERPROFILE']=", encodeString(Sys.getenv("USERPROFILE", ""), quote = "\"", na.encode = FALSE)),
      sep = "\n"
    ),
    convert = FALSE
  )
  ve <- as.character(rt$virtualenv %||% "")[1L]
  if (nzchar(ve)) reticulate::use_virtualenv(ve, required = TRUE)
  ce <- as.character(rt$condaenv %||% "")[1L]
  if (nzchar(ce)) reticulate::use_condaenv(ce, required = TRUE)

  # 嵌入后再写一次 os.environ（WSL→Windows R→Python 链路上偶发不同步）
  if (nzchar(.tabpfn_k)) {
    .esc <- encodeString(.tabpfn_k, quote = "\"", na.encode = FALSE)
    reticulate::py_run_string(
      paste0(
        "import os\n",
        "os.environ['TABPFN_TOKEN'] = ", .esc, "\n",
        "os.environ['TABPFN_API_KEY'] = ", .esc, "\n",
        "os.environ['TABPFN_TOKEN_FILE'] = ",
        encodeString(Sys.getenv("TABPFN_TOKEN_FILE", ""), quote = "\"", na.encode = FALSE)
      ),
      convert = FALSE
    )
  }

  script_dir <- rt$script_dir %||% file.path(project_wd, "python")
  script_dir <- normalizePath(script_dir, winslash = "/", mustWork = TRUE)
  py_file <- file.path(script_dir, "block_tabpfn_ml_export.py")
  if (!file.exists(py_file)) {
    stop("未找到 TabPFN 导出脚本: ", py_file, call. = FALSE)
  }

  td <- tempfile("tabpfn_ml_")
  dir.create(td, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  train_csv <- file.path(td, "train.csv")
  val_csv   <- file.path(td, "val.csv")
  utils::write.csv(df_train, train_csv, row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(df_validation, val_csv, row.names = FALSE, fileEncoding = "UTF-8")

  out_xlsx <- normalizePath(out_xlsx, winslash = "/", mustWork = FALSE)
  dir.create(dirname(out_xlsx), showWarnings = FALSE, recursive = TRUE)

  device <- as.character(rt$device %||% "cpu")[1L]
  ig <- isTRUE(rt$ignore_pretraining_limits)

  mod <- reticulate::import_from_path(
    "block_tabpfn_ml_export",
    path = script_dir,
    convert = TRUE
  )
  .tabpfn_pass <- if (nzchar(.tabpfn_k)) .tabpfn_k else NULL
  mod$export_tabpfn_excel(
    train_csv,
    val_csv,
    out_xlsx,
    ref_group,
    ana_group,
    as.integer(cv_folds),
    as.integer(seed_val),
    device = device,
    ignore_pretraining_limits = ig,
    tabpfn_token = .tabpfn_pass,
    model_version = model_version
  )
  if (!file.exists(out_xlsx)) {
    stop("TabPFN reticulate: 未生成输出文件 ", out_xlsx, call. = FALSE)
  }
  invisible(out_xlsx)
}

.mltp13_save_excel_import_results <- function(res_tab, tag, hpbest_list, all_eval, all_preds,
                                          hpbest_path, models_dir, all_models = list(),
                                          df_train_raw = NULL, df_validation_raw = NULL,
                                          pred_ana_col = NULL) {
  hpbest_list[[paste0("hpbest_", tag)]] <- res_tab$hpbest_frame
  save(hpbest_list, file = hpbest_path)
  out_file <- file.path(models_dir, paste0("evalresult_", tag, ".RData"))
  # save() 只接受变量名，须先赋给本地变量
  final_predictions <- res_tab$final_predictions
  predtrain         <- res_tab$predtrain
  predtest          <- res_tab$predtest
  eval_res          <- res_tab$eval
  ev5               <- res_tab$cv5_auc
  ev5s              <- res_tab$cv5_spec
  ev5n              <- res_tab$cv5_sens
  # 用与其他模型一致的变量名（predtrain_<tag> / predtest_<tag> / eval_<tag>）
  assign(paste0("predtrain_", tag), predtrain)
  assign(paste0("predtest_",  tag), predtest)
  assign(paste0("eval_",      tag), eval_res)

  # 未标准化特征 + 预测概率
  .mk_raw <- function(raw_df, pred_df, pcol) {
    if (is.null(raw_df) || is.null(pred_df)) return(NULL)
    prob_vec <- if (!is.null(pcol) && pcol %in% names(pred_df)) pred_df[[pcol]] else NA_real_
    cbind(data.frame(predicted_prob = prob_vec, stringsAsFactors = FALSE), raw_df)
  }
  assign(paste0("raw_pred_train_", tag),
         .mk_raw(df_train_raw, predtrain, pred_ana_col))
  assign(paste0("raw_pred_test_", tag),
         .mk_raw(df_validation_raw, predtest, pred_ana_col))
  assign(paste0("raw_pred_all_", tag),
         rbind(get(paste0("raw_pred_train_", tag)), get(paste0("raw_pred_test_", tag))))

  save(
    list = c("final_predictions",
             paste0("predtrain_", tag),
             paste0("predtest_",  tag),
             paste0("eval_",      tag),
             paste0("raw_pred_train_", tag),
             paste0("raw_pred_test_",  tag),
             paste0("raw_pred_all_",   tag),
             "ev5", "ev5s", "ev5n"),
    file = out_file,
    envir = environment()
  )
  all_eval[[tag]]   <- eval_res
  all_preds[[tag]]  <- final_predictions
  # 写入占位符，使 block_performance_ml 能通过 names(ml_models) 发现该模型
  if (is.null(all_models[[tag]])) all_models[[tag]] <- list(tag = tag, source = "excel_import")
  cli::cli_alert_success("{toupper(tag)} 结果已保存: {.file {out_file}}")
  list(hpbest_list = hpbest_list, all_eval = all_eval, all_preds = all_preds,
       all_models = all_models)
}

block_ml_tabpfn <- function(ctx, ...) {
  bl_cfg <- ctx$config$ml_tabpfn %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$ml_tabpfn$enable=FALSE，跳过。")
    return(ctx)
  }
  prep <- .mltp13_prep(ctx, bl_cfg)
  ctx <- prep$ctx
  tag <- "tabpfn"
  if (!.mltp13_check_limits(prep$n_train, prep$min_class_n, bl_cfg, tag)) return(ctx)

  ml_cfg <- ctx$config$ml_models %||% list()
  tabpfn_mode <- tolower(trimws(as.character(bl_cfg$mode %||% bl_cfg$tabpfn_mode %||% ml_cfg$tabpfn_mode %||% "excel")[1L]))
  tabpfn_path <- bl_cfg$data_path %||% bl_cfg$tabpfn_data_path %||% ml_cfg$tabpfn_data_path %||% NULL
  models_dir <- prep$models_dir
  hpbest_path <- prep$hpbest_path
  hpbest_list <- prep$hpbest_list
  all_models <- ctx$results$ml_models %||% list()

  run_save <- function(res_tab, skip_swap) {
    .mltp13_save_excel_import_results(
      res_tab, tag, hpbest_list, list(), list(), hpbest_path, models_dir,
      all_models = all_models,
      df_train_raw = prep$df_train, df_validation_raw = prep$df_validation,
      pred_ana_col = prep$pred_ana_col
    )
  }

  z <- NULL
  if (identical(tabpfn_mode, "reticulate")) {
    rt <- bl_cfg$reticulate %||% bl_cfg$tabpfn_reticulate %||% ml_cfg$tabpfn_reticulate %||% list()
    project_wd <- as.character(rt$project_wd %||% getwd())[1L]
    tabpfn_excel <- rt$keep_excel_path %||% file.path(models_dir, "TabPFN_reticulate_export.xlsx")
    cli::cli_h2("ml_tabpfn: TabPFN reticulate → {.file {tabpfn_excel}}")
    z <- tryCatch({
      ml_rt <- list(tabpfn_reticulate = rt)
      .mltp13_tabpfn_run_via_reticulate(
        prep$df_train, prep$df_validation, prep$ref_group, prep$ana_group,
        ml_rt, prep$fold_num, prep$seed_val, tabpfn_excel, project_wd
      )
      res_tab <- .mltp13_run_tabpfn(
        tabpfn_excel, hpbest_path, prep$ref_group, prep$ana_group,
        prep$pred_ref_col, prep$pred_ana_col, skip_metric_swap = TRUE
      )
      run_save(res_tab, TRUE)
    }, error = function(e) {
      cli::cli_alert_danger("TabPFN(reticulate) 失败: {e$message}")
      tb <- paste(utils::capture.output(traceback()), collapse = "\n")
      dbg <- file.path(models_dir, "tabpfn_reticulate_error.txt")
      tryCatch({
        writeLines(c(
          paste("message:", conditionMessage(e)),
          paste("project_wd:", project_wd),
          paste("getwd:", getwd()),
          paste("RETICULATE_PYTHON:", Sys.getenv("RETICULATE_PYTHON", "")),
          paste("PATH head:", substr(Sys.getenv("PATH"), 1, 300)),
          "--- traceback ---",
          tb
        ), dbg)
        cli::cli_alert_info("TabPFN 错误详情已写: {.file {dbg}}")
      }, error = function(e2) invisible(NULL))
      NULL
    })
  } else if (!is.null(tabpfn_path) && nzchar(tabpfn_path)) {
    cli::cli_h2("ml_tabpfn: TabPFN excel → {.file {tabpfn_path}}")
    z <- tryCatch({
      res_tab <- .mltp13_run_tabpfn(
        tabpfn_path, hpbest_path, prep$ref_group, prep$ana_group,
        prep$pred_ref_col, prep$pred_ana_col, skip_metric_swap = FALSE
      )
      run_save(res_tab, FALSE)
    }, error = function(e) { cli::cli_alert_danger("TabPFN(excel) 失败: {e$message}"); NULL })
  } else if (requireNamespace("reticulate", quietly = TRUE) &&
             (nzchar(trimws(Sys.getenv("TABPFN_TOKEN", ""))) || nzchar(trimws(Sys.getenv("TABPFN_API_KEY", ""))))) {
    cli::cli_alert_warning("ml_tabpfn: 未配置 Excel，回退 reticulate。")
    rt <- bl_cfg$reticulate %||% bl_cfg$tabpfn_reticulate %||% ml_cfg$tabpfn_reticulate %||% list()
    project_wd <- as.character(rt$project_wd %||% getwd())[1L]
    tabpfn_excel <- rt$keep_excel_path %||% file.path(models_dir, "TabPFN_reticulate_export.xlsx")
    z <- tryCatch({
      ml_rt <- list(tabpfn_reticulate = rt)
      .mltp13_tabpfn_run_via_reticulate(
        prep$df_train, prep$df_validation, prep$ref_group, prep$ana_group,
        ml_rt, prep$fold_num, prep$seed_val, tabpfn_excel, project_wd
      )
      res_tab <- .mltp13_run_tabpfn(
        tabpfn_excel, hpbest_path, prep$ref_group, prep$ana_group,
        prep$pred_ref_col, prep$pred_ana_col, skip_metric_swap = TRUE
      )
      run_save(res_tab, TRUE)
    }, error = function(e) { cli::cli_alert_danger("TabPFN(reticulate fallback) 失败: {e$message}"); NULL })
  } else {
    cli::cli_alert_warning("ml_tabpfn: 未配置 data_path 且无 reticulate/TOKEN，跳过。")
    return(ctx)
  }

  if (is.null(z)) return(ctx)
  ctx <- .mltp13_write_ctx_meta(ctx, prep)
  ctx$results$ml_models[[tag]] <- z$all_models[[tag]] %||% list(tag = tag, source = "excel_import")
  ctx$results$ml_predictions_all[[tag]] <- z$all_preds[[tag]]
  ctx$results$ml_eval_by_model[[tag]] <- z$all_eval[[tag]]
  ctx
}

register_block("ml_tabpfn", block_ml_tabpfn, "TabPFN 训练/导入（excel 或 reticulate）")
