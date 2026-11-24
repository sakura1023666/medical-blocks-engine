###############################################################################
#  00ml_nafld_cm_common.R — 34 脂肪肝 C/M/C+M 公共函数（定制课题，非通用模板）
###############################################################################

.nafld_cm_study_root <- function(cfg) {
  as.character((cfg$project %||% list())$output_dir %||% getwd())[1L]
}

.nafld_cm_out_dirs <- function(cfg) {
  root <- .nafld_cm_study_root(cfg)
  list(
    root = root,
    tables = file.path(root, "Tables"),
    figures = file.path(root, "Figures"),
    data = file.path(root, "Data"),
    checkpoints = file.path(root, "checkpoints")
  )
}

.nafld_cm_ensure_dirs <- function(cfg) {
  d <- .nafld_cm_out_dirs(cfg)
  for (p in c(d$tables, d$figures, d$data, d$checkpoints)) {
    if (!dir.exists(p)) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(d)
}

.nafld_cm_load_metabolome <- function(cfg, clinical_df) {
  path <- (cfg$data %||% list())$rawdata_path
  obj <- (cfg$data %||% list())$metabolome_obj %||% "FattyLiver_metabolome"
  if (!file.exists(path)) return(clinical_df)
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  if (!exists(obj, envir = env, inherits = FALSE)) return(clinical_df)
  meta <- get(obj, envir = env)
  if (!is.data.frame(meta)) return(clinical_df)
  id <- (cfg$data %||% list())$id_column %||% "ID"
  if (!id %in% names(meta) || !id %in% names(clinical_df)) return(clinical_df)
  u_cols <- grep("^U_", names(meta), value = TRUE)
  if (!length(u_cols)) return(clinical_df)
  keep <- c(id, u_cols)
  merged <- merge(clinical_df, meta[, keep, drop = FALSE], by = id, all.x = TRUE)
  .nafld_cm_creatinine_correct(cfg, merged)
}

#' 尿肌酐校正（spot urine 稀释校正）——所有下游代谢组消费的单一开关。
#' config$data$creatinine_normalize = list(
#'   enable = TRUE, col = "U_Creatinine", ref = "median"
#' )
#' 校正式：corrected = x / U_Creatinine * ref(队列中位肌酐)，保持量级；
#'   组间中位比即为稀释校正后的方向。
#' - U_Creatinine 自身不校正（保留原值作 QC/展示；自除会退化为常数）
#' - 参照肌酐 <=0 或非有限 → 该样本该列校正值为 NA（下游 complete.cases/finite 自动剔除）
#' - 0 视为未检出哨兵，维持 0（与肌酐审计口径一致）
#' @return 若 enable=FALSE 或无肌酐列，返回原 df；否则返回校正后的 df。
.nafld_cm_creatinine_correct <- function(cfg, df) {
  cn <- (cfg$data %||% list())$creatinine_normalize
  if (!is.list(cn) || !isTRUE(cn$enable)) return(df)
  if (!is.data.frame(df)) return(df)
  cr_col <- as.character(cn$col %||% "U_Creatinine")[1L]
  if (!(cr_col %in% names(df))) return(df)
  uc <- suppressWarnings(as.numeric(df[[cr_col]]))
  ok_uc <- is.finite(uc) & uc > 0
  ref <- cn$ref %||% "median"
  scale_c <- if (is.character(ref) && identical(ref, "median")) {
    stats::median(uc[ok_uc], na.rm = TRUE)
  } else {
    r0 <- suppressWarnings(as.numeric(ref))[1L]
    if (is.finite(r0) && r0 > 0) r0 else stats::median(uc[ok_uc], na.rm = TRUE)
  }
  if (!is.finite(scale_c) || scale_c <= 0) return(df)
  u_cols <- setdiff(grep("^U_", names(df), value = TRUE), cr_col)
  for (cc in u_cols) {
    x <- suppressWarnings(as.numeric(df[[cc]]))
    corrected <- x / uc * scale_c
    corrected[!ok_uc] <- NA_real_   # 参照肌酐缺失/<=0 → 无法校正
    df[[cc]] <- corrected
  }
  attr(df, "creatinine_normalized") <- TRUE
  df
}

.nafld_cm_clinical_pool <- function(cfg, data) {
  pool <- as.character((cfg$feature_pools %||% list())$clinical %||% character(0))
  never <- as.character((cfg$feature_pools %||% list())$never_features %||% character(0))
  # 血压列名：mapping 后可能是 NBPS/NBPD
  pool <- unique(c(pool, "NBPS", "NBPD", "SBP", "DBP"))
  setdiff(intersect(pool, names(data)), never)
}

.nafld_cm_metabolite_pool <- function(cfg, data) {
  pref <- as.character((cfg$feature_pools %||% list())$metabolite_prefix %||% "U_")[1L]
  never <- as.character((cfg$feature_pools %||% list())$never_features %||% character(0))
  cols <- grep(paste0("^", pref), names(data), value = TRUE)
  setdiff(cols, never)
}

.nafld_cm_outcome01 <- function(y, positive = "NAFLD") {
  if (is.factor(y)) y <- as.character(y)
  as.integer(as.character(y) == as.character(positive))
}

.nafld_cm_model_matrix <- function(data, vars, outcome_col, positive = "NAFLD") {
  vars <- intersect(vars, names(data))
  d <- data[, c(outcome_col, vars), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  y <- .nafld_cm_outcome01(d[[outcome_col]], positive)
  x <- d[, vars, drop = FALSE]
  for (j in seq_along(x)) {
    if (is.factor(x[[j]]) || is.character(x[[j]])) {
      x[[j]] <- as.numeric(as.factor(x[[j]]))
    } else {
      x[[j]] <- as.numeric(x[[j]])
    }
  }
  list(x = as.matrix(x), y = y, n = nrow(x), vars = vars)
}

#' Wilcoxon FDR 筛选（代谢物）
.nafld_cm_select_wilcoxon_fdr <- function(x, y, alpha = 0.05) {
  p <- apply(x, 2L, function(col) {
    if (length(unique(col[!is.na(col)])) < 2L) return(1)
    tryCatch(stats::wilcox.test(col[y == 1], col[y == 0])$p.value, error = function(e) 1)
  })
  padj <- stats::p.adjust(p, method = "BH")
  names(padj)[which(padj < alpha)]
}

#' LASSO 筛选
#' @param s "lambda.1se" | "lambda.min"
#' @param lambda_mult 在所选 lambda 上再乘倍数（>1 更稀疏）
.nafld_cm_select_lasso <- function(x, y, seed = 123L, s = "lambda.1se", lambda_mult = 1) {
  if (!requireNamespace("glmnet", quietly = TRUE)) return(character(0))
  set.seed(seed)
  fit <- tryCatch(
    glmnet::cv.glmnet(x, y, family = "binomial", alpha = 1, nfolds = min(5L, nrow(x))),
    error = function(e) NULL
  )
  if (is.null(fit)) return(character(0))
  s <- as.character(s %||% "lambda.1se")[1L]
  if (!s %in% c("lambda.1se", "lambda.min")) s <- "lambda.1se"
  lam0 <- if (identical(s, "lambda.min")) fit$lambda.min else fit$lambda.1se
  mult <- as.numeric(lambda_mult %||% 1)[1L]
  if (!is.finite(mult) || mult <= 0) mult <- 1
  lam <- lam0 * mult
  # 不超过路径上最大 lambda（否则可能全零）
  lam <- min(max(lam, min(fit$lambda)), max(fit$lambda))
  cf <- as.matrix(stats::coef(fit, s = lam))
  rn <- rownames(cf)[which(cf[, 1] != 0)]
  setdiff(rn, "(Intercept)")
}

.nafld_cm_fe_ntree <- function(cfg) {
  ml <- cfg$ml_small_sample %||% list()
  if (isTRUE(ml$quick)) as.integer(ml$quick_ntree %||% 50L) else 200L
}

#' Boruta 筛选（无包则退化为 RF 重要性 top）
.nafld_cm_select_boruta <- function(x, y, seed = 123L, max_runs = 50L, ntree = 200L) {
  df <- as.data.frame(x)
  df$.y <- factor(y)
  if (requireNamespace("Boruta", quietly = TRUE)) {
    set.seed(seed)
    bt <- tryCatch(
      Boruta::Boruta(.y ~ ., data = df, maxRuns = max_runs, doTrace = 0L),
      error = function(e) NULL
    )
    if (!is.null(bt)) {
      conf <- Boruta::getSelectedAttributes(bt, withTentative = FALSE)
      return(as.character(conf))
    }
  }
  .nafld_cm_select_rf_importance(x, y, seed = seed, top_frac = 0.3, ntree = ntree)
}

#' RF importance top fraction（可设上限）
.nafld_cm_select_rf_importance <- function(x, y, seed = 123L, top_frac = 0.3,
                                           ntree = 200L, top_max = Inf) {
  if (!requireNamespace("randomForest", quietly = TRUE)) return(character(0))
  set.seed(seed)
  df <- as.data.frame(x)
  df$.y <- factor(y)
  fit <- tryCatch(
    randomForest::randomForest(.y ~ ., data = df, ntree = ntree, importance = TRUE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(character(0))
  imp <- randomForest::importance(fit)
  sc <- if ("MeanDecreaseGini" %in% colnames(imp)) imp[, "MeanDecreaseGini"] else imp[, 1]
  sc <- sort(sc, decreasing = TRUE)
  n_keep <- max(1L, ceiling(length(sc) * top_frac))
  cap <- suppressWarnings(as.integer(top_max)[1L])
  if (is.finite(cap) && cap > 0L) n_keep <- min(n_keep, cap)
  names(sc)[seq_len(min(n_keep, length(sc)))]
}

#' VIF 剔除（迭代；防无名向量死循环）
.nafld_cm_select_vif <- function(x, y, threshold = 5) {
  vars <- colnames(x)
  if (length(vars) < 2L) return(vars)
  df <- as.data.frame(x)
  df$.y <- y
  guard <- 0L
  repeat {
    guard <- guard + 1L
    if (length(vars) < 2L || guard > 80L) break
    fml <- stats::as.formula(paste(".y ~", paste(vars, collapse = "+")))
    fit <- tryCatch(
      suppressWarnings(stats::glm(fml, data = df, family = binomial())),
      error = function(e) NULL
    )
    if (is.null(fit)) break
    if (!requireNamespace("car", quietly = TRUE)) break
    vv <- tryCatch(suppressWarnings(car::vif(fit)), error = function(e) NULL)
    if (is.null(vv)) break
    if (is.matrix(vv)) vv <- vv[, 1]
    vv <- as.numeric(vv)
    names(vv) <- if (!is.null(names(vv)) && length(names(vv))) names(vv) else vars[seq_along(vv)]
    mx <- max(vv, na.rm = TRUE)
    if (!is.finite(mx) || mx < threshold) break
    drop <- names(vv)[which.max(vv)]
    if (!length(drop) || is.na(drop) || !drop %in% vars) {
      drop <- vars[which.max(vv)]
    }
    n0 <- length(vars)
    vars <- setdiff(vars, drop)
    if (length(vars) >= n0) break
  }
  vars
}

#' Youden 指标
.nafld_cm_youden_metrics <- function(y, p) {
  if (!requireNamespace("pROC", quietly = TRUE) || length(unique(y)) < 2L) {
    return(list(auc = NA_real_, sens = NA_real_, spec = NA_real_, thr = 0.5))
  }
  roc <- pROC::roc(y, p, quiet = TRUE, direction = "<")
  coords <- pROC::coords(roc, "best", ret = c("threshold", "sensitivity", "specificity"),
                         best.method = "youden", transpose = FALSE)
  list(
    auc = as.numeric(pROC::auc(roc)),
    sens = as.numeric(coords$sensitivity[1]),
    spec = as.numeric(coords$specificity[1]),
    thr = as.numeric(coords$threshold[1])
  )
}

#' 共识：至少 min_hit 种方法选中
.nafld_cm_consensus <- function(method_lists, min_hit = 2L) {
  allv <- unique(unlist(method_lists, use.names = FALSE))
  if (!length(allv)) return(character(0))
  hits <- sapply(allv, function(v) sum(vapply(method_lists, function(m) v %in% m, logical(1))))
  allv[hits >= min_hit]
}

#' 临床空间特征工程（Boruta + LASSO + VIF → 共识）
.nafld_cm_fe_clinical <- function(x, y, cfg) {
  fe <- cfg$feature_engineering %||% list()
  min_hit <- as.integer(fe$consensus_min_clinical %||% fe$consensus_min %||% 2L)
  vif_th <- as.numeric(fe$vif_threshold %||% 5)
  ntree <- .nafld_cm_fe_ntree(cfg)
  ml <- cfg$ml_small_sample %||% list()
  max_runs <- as.integer(fe$boruta_max_runs %||% if (isTRUE(ml$quick)) 20L else 50L)
  lasso_s <- as.character(fe$lasso_s %||% "lambda.1se")[1L]
  lasso_mult <- as.numeric(fe$lasso_lambda_mult %||% 1)[1L]
  m_boruta <- .nafld_cm_select_boruta(x, y, max_runs = max_runs, ntree = ntree)
  m_lasso <- .nafld_cm_select_lasso(x, y, s = lasso_s, lambda_mult = lasso_mult)
  # VIF 在 LASSO∪Boruta 候选上做
  cand <- unique(c(m_boruta, m_lasso))
  if (!length(cand)) cand <- colnames(x)
  x2 <- x[, cand, drop = FALSE]
  m_vif <- .nafld_cm_select_vif(x2, y, threshold = vif_th)
  list(
    boruta = m_boruta, lasso = m_lasso, vif = m_vif,
    selected = .nafld_cm_consensus(list(m_boruta, m_lasso, m_vif), min_hit)
  )
}

#' 代谢物空间（Wilcoxon FDR + Boruta + RF → 共识；可要求最终必须过 FDR）
.nafld_cm_fe_metabolite <- function(x, y, cfg) {
  fe <- cfg$feature_engineering %||% list()
  min_hit <- as.integer(fe$consensus_min_metabolite %||% fe$consensus_min %||% 2L)
  alpha <- as.numeric(fe$fdr_alpha %||% 0.05)
  ntree <- .nafld_cm_fe_ntree(cfg)
  ml <- cfg$ml_small_sample %||% list()
  max_runs <- as.integer(fe$boruta_max_runs %||% if (isTRUE(ml$quick)) 20L else 50L)
  top_frac <- as.numeric(fe$rf_top_frac %||% 0.3)[1L]
  top_max <- as.numeric(fe$rf_top_max %||% Inf)[1L]
  m_w <- .nafld_cm_select_wilcoxon_fdr(x, y, alpha = alpha)
  # 加严：Boruta/RF 主要在 FDR 通过集上跑（池太小则回退全量）
  x_b <- if (length(m_w) >= 5L) x[, m_w, drop = FALSE] else x
  m_b <- .nafld_cm_select_boruta(x_b, y, max_runs = max_runs, ntree = ntree)
  if (requireNamespace("Boruta", quietly = TRUE)) {
    m_r <- .nafld_cm_select_rf_importance(
      x_b, y, ntree = ntree, top_frac = top_frac, top_max = top_max
    )
  } else {
    m_r <- m_b
  }
  sel <- .nafld_cm_consensus(list(m_w, m_b, m_r), min_hit)
  # 最终代谢物必须过 FDR（与「Wilcoxon 门控」一致，进一步控数）
  if (isTRUE(fe$metabolite_require_fdr %||% TRUE) && length(m_w)) {
    sel <- intersect(sel, m_w)
  }
  # 硬上限：按 RF 重要性（无则按名字）截到 metabolite_max_selected
  max_m <- suppressWarnings(as.integer(fe$metabolite_max_selected %||% NA_integer_)[1L])
  if (is.finite(max_m) && max_m > 0L && length(sel) > max_m) {
    ord <- intersect(m_r, sel)
    rest <- setdiff(sel, ord)
    sel <- c(ord, rest)[seq_len(max_m)]
  }
  list(
    wilcoxon_fdr = m_w, boruta = m_b, rf = m_r,
    selected = sel
  )
}

#' 取训练集（优先 ctx$data$train 的 ID）
.nafld_cm_training_df <- function(ctx, data) {
  cfg <- ctx$config
  id <- cfg$data$id_column %||% "ID"
  if (!is.null(ctx$data$train) && is.data.frame(ctx$data$train) && id %in% names(ctx$data$train) && id %in% names(data)) {
    return(data[as.character(data[[id]]) %in% as.character(ctx$data$train[[id]]), , drop = FALSE])
  }
  if ("is_train" %in% names(data)) {
    return(data[as.logical(data$is_train), , drop = FALSE])
  }
  if ("train" %in% names(data) && is.logical(data$train)) {
    return(data[data$train, , drop = FALSE])
  }
  if (!is.null(ctx$results$train_ids) && id %in% names(data)) {
    return(data[as.character(data[[id]]) %in% as.character(ctx$results$train_ids), , drop = FALSE])
  }
  data
}

#' 解析 Python 可执行文件（对齐 ml_small_sample / TabPFN reticulate 配置）
.nafld_cm_resolve_python_exe <- function(cfg) {
  ml <- cfg$ml_small_sample %||% list()
  # TabNet 必须用带 pytorch-tabnet 的 venv；勿回落到仅 matplotlib 的绘图 venv
  rt <- ml$tabnet_python %||% list()
  pyexe <- if (is.list(rt)) as.character(rt$python %||% "")[1L] else as.character(rt)[1L]
  if (!nzchar(pyexe)) {
    pe <- ml$python_exe
    pyexe <- if (is.list(pe)) as.character(pe$python %||% "")[1L] else as.character(pe %||% "")[1L]
  }
  if (!nzchar(pyexe)) pyexe <- Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = "")
  if (!nzchar(pyexe)) pyexe <- Sys.getenv("RETICULATE_PYTHON", unset = "")
  if (!nzchar(pyexe)) pyexe <- Sys.which("python3")
  if (!nzchar(pyexe)) pyexe <- Sys.which("python")
  as.character(pyexe)[1L]
}

.nafld_cm_resolve_figure_python <- function(cfg) {
  ml <- cfg$ml_small_sample %||% list()
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  cands <- c(
    if (is.list(ml$python_exe)) ml$python_exe$python else ml$python_exe,
    file.path(root, ".venv_ml_pub/bin/python"),
    file.path((cfg$project %||% list())$output_dir %||% "", ".venv_tabnet/bin/python"),
    Sys.which("python3")
  )
  cands <- unique(as.character(cands))
  cands <- cands[nzchar(cands) & file.exists(cands)]
  for (py in cands) {
    ok <- isTRUE(tryCatch({
      system2(py, c("-c", "import matplotlib, sklearn, pandas, numpy"),
              stdout = FALSE, stderr = FALSE) == 0
    }, error = function(e) FALSE))
    if (ok) return(py)
  }
  if (length(cands)) return(cands[[1L]])
  ""
}

.nafld_cm_tabnet_script <- function(cfg) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  script <- file.path(root, "python", "ml_tabnet_fit_predict.py")
  if (file.exists(script)) return(script)
  file.path(getwd(), "python", "ml_tabnet_fit_predict.py")
}

.nafld_cm_tabnet_available <- function(cfg) {
  pyexe <- .nafld_cm_resolve_python_exe(cfg)
  script <- .nafld_cm_tabnet_script(cfg)
  if (!nzchar(pyexe) || !file.exists(script)) return(FALSE)
  cmd <- sprintf(
    "%s -c \"from pytorch_tabnet.tab_model import TabNetClassifier\"",
    shQuote(pyexe)
  )
  isTRUE(suppressWarnings(system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)) == 0L)
}

#' TabNet 单折预测（subprocess → python/ml_tabnet_fit_predict.py）
.nafld_cm_tabnet_fit_pred <- function(x_tr, y_tr, x_te, cfg, seed = 1L) {
  pyexe <- .nafld_cm_resolve_python_exe(cfg)
  script <- .nafld_cm_tabnet_script(cfg)
  if (!nzchar(pyexe) || !file.exists(script)) {
    return(list(pred = rep(NA_real_, nrow(x_te)), ok = FALSE, error = "TabNet python/script missing"))
  }
  ml <- cfg$ml_small_sample %||% list()
  tn <- ml$tabnet %||% list()
  td <- file.path(tempdir(), paste0("nafld_tabnet_", sample.int(1e9, 1L)))
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  xtr_f <- file.path(td, "x_train.csv")
  ytr_f <- file.path(td, "y_train.csv")
  xte_f <- file.path(td, "x_test.csv")
  out_f <- file.path(td, "pred.csv")
  utils::write.csv(as.data.frame(x_tr), xtr_f, row.names = FALSE)
  utils::write.csv(data.frame(y = as.integer(y_tr)), ytr_f, row.names = FALSE)
  utils::write.csv(as.data.frame(x_te), xte_f, row.names = FALSE)
  cmd <- paste(
    shQuote(pyexe), shQuote(script),
    "--x-train", shQuote(xtr_f),
    "--y-train", shQuote(ytr_f),
    "--x-test", shQuote(xte_f),
    "--out-pred", shQuote(out_f),
    "--seed", as.integer(seed),
    "--max-epochs", as.integer(tn$max_epochs %||% 80L),
    "--patience", as.integer(tn$patience %||% 15L),
    "--batch-size", as.integer(tn$batch_size %||% 128L)
  )
  st <- suppressWarnings(system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE))
  if (st != 0L || !file.exists(out_f)) {
    return(list(pred = rep(NA_real_, nrow(x_te)), ok = FALSE, error = paste0("TabNet exit ", st)))
  }
  pred <- tryCatch(
    as.numeric(utils::read.csv(out_f, stringsAsFactors = FALSE)$pred),
    error = function(e) rep(NA_real_, nrow(x_te))
  )
  if (length(pred) != nrow(x_te) || !any(is.finite(pred))) {
    return(list(pred = rep(NA_real_, nrow(x_te)), ok = FALSE, error = "TabNet pred invalid"))
  }
  list(pred = pred, ok = TRUE, error = NULL)
}

#' 写入 attrition 队列步（供 Figure 1）
.nafld_cm_attrition_record_cohort <- function(ctx, cfg) {
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  al <- file.path(root, "R/attrition_log.R")
  if (file.exists(al) && !exists("attrition_record", mode = "function")) {
    source(al, local = FALSE)
  }
  if (!exists("attrition_record", mode = "function")) return(ctx)
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
  if (is.null(data)) return(ctx)
  data <- .nafld_cm_load_metabolome(cfg, data)
  n_all <- nrow(data)
  n_tr <- nrow(.nafld_cm_training_df(ctx, data))
  ctx <- attrition_record(ctx, "analytic", "Analytic cohort (NAFLD vs Normal classification)", n_all)
  if (n_tr < n_all) {
    ctx <- attrition_record(
      ctx, "ml_train",
      "Training set for ML model development (70% stratified split)",
      n_tr,
      meta = list(exclude_label = sprintf("Validation set held out (30%%, n=%d)", n_all - n_tr))
    )
  }
  ctx
}
