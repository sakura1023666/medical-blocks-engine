###############################################################################
#  shap_glm — 对 logistic nomogram 同特征矩阵做 SHAP（优先 shapviz / kernel）
#
#  register_block: "shap_glm"
#  典型流水线: logistic_nomogram 之后
#
#  config$shap_glm = list(
#    enable = TRUE,
#    n_explain = 200L,       # 解释样本上限
#    bg_n = 50L,             # kernel 背景
#    seed = 42L,
#    top_n = 12L
#  )
#  兼容: 缺 config$shap_glm 时回读 config$jin_index_sofa$shap
#
#  图题禁止裸写 "best model"：须写明 logistic nomogram 特征集 / 院内死亡结局
#  无 shapviz/fastshap/kernelshap 时 skip + 日志，不中断流水线
###############################################################################

.shap_glm_cfg <- function(cfg) {
  top <- cfg$shap_glm %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$shap %||% list()
}

.shap_glm_pred_fun <- function(fit, newdata) {
  if (inherits(fit, "lrm") || inherits(fit, "rms")) {
    pr <- tryCatch(
      as.numeric(stats::predict(fit, newdata = newdata, type = "fitted")),
      error = function(e) NULL
    )
    if (!is.null(pr)) return(pr)
  }
  if (inherits(fit, "glm")) {
    return(as.numeric(stats::predict(fit, newdata = newdata, type = "response")))
  }
  as.numeric(stats::predict(fit, newdata = newdata, type = "response"))
}

block_shap_glm <- function(ctx, ...) {
  .cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(ctx$config$project$root %||% "")[1L],
    getwd()
  ))
  .lit <- NULL
  for (.r in .cands[nzchar(as.character(.cands))]) {
    .p <- file.path(.r, "R", "literature_jin_index_sofa.R")
    if (file.exists(.p)) { .lit <- .p; break }
  }
  if (!is.null(.lit)) source(.lit, local = FALSE)

  sh <- .shap_glm_cfg(ctx$config)
  if (!is.null(sh$enable) && !isTRUE(sh$enable)) {
    cli::cli_alert_info("shap_glm: enable=FALSE，跳过")
    return(ctx)
  }

  nom <- ctx$results$logistic_nomogram %||% ctx$results$jin_nomogram_cal
  if (is.null(nom) || is.null(nom$fit) || !length(nom$features)) {
    cli::cli_alert_warning("shap_glm: 需先跑 logistic_nomogram；跳过")
    return(ctx)
  }

  has_sv <- requireNamespace("shapviz", quietly = TRUE)
  has_ks <- requireNamespace("kernelshap", quietly = TRUE)
  has_fs <- requireNamespace("fastshap", quietly = TRUE)
  if (!has_sv && !has_ks && !has_fs) {
    cli::cli_alert_warning(
      "shap_glm: 未安装 shapviz/kernelshap/fastshap，跳过 SHAP（不中断）"
    )
    res <- list(ok = FALSE, reason = "missing_packages")
    ctx$results$shap_glm <- res
    ctx$results$jin_shap_explain <- res
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  feats <- as.character(nom$features)
  outcome <- as.character(nom$outcome)[1L]
  need <- unique(c(feats, outcome))
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    cli::cli_alert_warning("shap_glm: 缺列 {paste(miss, collapse=', ')}；跳过")
    return(ctx)
  }

  d <- data[, need, drop = FALSE]
  for (cc in feats) {
    if (is.character(d[[cc]])) d[[cc]] <- factor(d[[cc]])
  }
  d <- stats::na.omit(d)
  X <- d[, feats, drop = FALSE]
  X_num <- tryCatch({
    mm <- stats::model.matrix(~ . - 1, data = X)
    as.data.frame(mm)
  }, error = function(e) {
    X2 <- X
    for (cc in names(X2)) {
      if (is.factor(X2[[cc]])) X2[[cc]] <- as.numeric(X2[[cc]])
    }
    X2
  })

  n_explain <- as.integer(sh$n_explain %||% 200L)[1L]
  bg_n <- as.integer(sh$bg_n %||% 50L)[1L]
  seed <- as.integer(sh$seed %||% 42L)[1L]
  top_n <- as.integer(sh$top_n %||% 12L)[1L]
  set.seed(seed)
  n <- nrow(X_num)
  if (n < 10L) {
    cli::cli_alert_warning("shap_glm: 样本过少；跳过")
    return(ctx)
  }
  ix <- if (n > n_explain) sample.int(n, n_explain) else seq_len(n)
  bg_ix <- if (n > bg_n) sample.int(n, bg_n) else seq_len(n)

  fit <- nom$fit
  X_ex_f <- X[ix, , drop = FALSE]
  X_bg_f <- X[bg_ix, , drop = FALSE]
  pred_fun <- function(object, newdata) {
    .shap_glm_pred_fun(object, newdata)
  }

  sv <- NULL
  method_used <- NA_character_
  err_msg <- NULL

  if (has_ks && has_sv) {
    ks <- tryCatch(
      kernelshap::kernelshap(fit, X_ex_f, bg_X = X_bg_f, pred_fun = pred_fun),
      error = function(e) e
    )
    if (!inherits(ks, "error")) {
      sv <- tryCatch(shapviz::shapviz(ks), error = function(e) e)
      if (!inherits(sv, "error")) method_used <- "kernelshap+shapviz"
      else {
        err_msg <- conditionMessage(sv)
        sv <- NULL
      }
    } else {
      err_msg <- conditionMessage(ks)
    }
  }

  if (is.null(sv) && has_fs && has_sv) {
    fs <- tryCatch({
      fastshap::explain(
        fit,
        X = X_ex_f,
        pred_wrapper = function(object, newdata) pred_fun(object, newdata),
        nsim = 50L,
        adjust = TRUE
      )
    }, error = function(e) e)
    if (!inherits(fs, "error")) {
      sv <- tryCatch(shapviz::shapviz(fs, X = X_ex_f), error = function(e) e)
      if (!inherits(sv, "error")) method_used <- "fastshap+shapviz"
      else {
        err_msg <- conditionMessage(sv)
        sv <- NULL
      }
    } else {
      err_msg <- conditionMessage(fs)
    }
  }

  if (is.null(sv)) {
    cli::cli_alert_warning(
      "shap_glm: SHAP 计算失败，跳过。{err_msg %||% ''}"
    )
    res <- list(ok = FALSE, reason = "compute_failed", error = err_msg)
    ctx$results$shap_glm <- res
    ctx$results$jin_shap_explain <- res
    return(ctx)
  }

  out_root <- ctx$config$project$output_dir %||% file.path(root, "Output")
  fig_dir <- file.path(out_root, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  title_main <- paste0(
    "SHAP for logistic nomogram feature set\n",
    "(in-hospital mortality; not a tree 'best model')"
  )
  bee_path <- file.path(
    fig_dir,
    "Figure. SHAP beeswarm logistic nomogram in-hospital mortality.pdf"
  )
  grDevices::pdf(bee_path, width = 8.5, height = 6.5)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p <- tryCatch(
      shapviz::sv_importance(sv, kind = "beeswarm", max_display = top_n) +
        ggplot2::ggtitle(title_main),
      error = function(e) {
        shapviz::sv_importance(sv, kind = "bar", max_display = top_n) +
          ggplot2::ggtitle(title_main)
      }
    )
    print(p)
  } else {
    plot(sv, main = title_main)
  }
  grDevices::dev.off()

  bar_path <- file.path(
    fig_dir,
    "Figure. SHAP importance logistic nomogram in-hospital mortality.pdf"
  )
  grDevices::pdf(bar_path, width = 7.5, height = 5.5)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    print(
      shapviz::sv_importance(sv, kind = "bar", max_display = top_n) +
        ggplot2::ggtitle("Mean |SHAP| — logistic nomogram features (in-hospital death)")
    )
  }
  grDevices::dev.off()

  res <- list(
    ok = TRUE,
    method = method_used,
    features = feats,
    n_explain = length(ix),
    beeswarm_pdf = bee_path,
    importance_pdf = bar_path,
    title_rule = "Titles name logistic nomogram feature set + in-hospital mortality; never bare 'best model'."
  )
  ctx$results$shap_glm <- res
  ctx$results$jin_shap_explain <- res
  cli::cli_alert_success(
    "shap_glm: method={method_used}, n_explain={length(ix)}"
  )
  ctx
}

register_block(
  "shap_glm",
  block_shap_glm,
  "GLM/logistic列线图同特征SHAP（禁裸best model图题）"
)
