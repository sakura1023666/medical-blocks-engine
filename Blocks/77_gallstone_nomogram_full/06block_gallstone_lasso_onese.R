###############################################################################
# gallstone_lasso_onese — Fig4 临床预指定预测因子的 Ridge 收缩（替代 LASSO 海选）
# 小样本：事先点名 3–5 个机制/文献候选，不做数据驱动稀疏筛选
###############################################################################

block_gallstone_lasso_onese <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("需要 glmnet", call. = FALSE)

  train <- ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  gn <- ctx$config$gallstone_nomogram %||% list()
  use <- gallstone_nomogram_prespec_predictors(ctx$config)
  use <- use[use %in% names(train)]
  if (!length(use)) stop("prespecified_predictors 在训练集中均不存在", call. = FALSE)

  y <- train[[outcome]]
  if (is.factor(y)) {
    y01 <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
  } else {
    y01 <- as.integer(as.numeric(y) == 1L)
  }

  # 仅预指定列；连续列标准化后拟合 ridge（alpha=0）
  dmm <- train[, use, drop = FALSE]
  for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), use)) {
    dmm[[cc]] <- factor(dmm[[cc]])
  }
  mm <- stats::model.matrix(~ ., data = dmm)[, -1L, drop = FALSE]
  for (j in seq_len(ncol(mm))) {
    s <- stats::sd(mm[, j])
    if (is.finite(s) && s > 0) mm[, j] <- as.numeric(scale(mm[, j]))
  }

  set.seed(as.integer(gn$seed %||% 42L))
  cvfit <- glmnet::cv.glmnet(
    mm, y01, family = "binomial", alpha = 0,
    nfolds = 10L, type.measure = "deviance", standardize = FALSE
  )
  fit <- cvfit$glmnet.fit
  s_use <- gn$ridge_lambda %||% "lambda.1se"
  if (!s_use %in% c("lambda.1se", "lambda.min")) s_use <- "lambda.1se"
  lam <- if (identical(s_use, "lambda.min")) cvfit$lambda.min else cvfit$lambda.1se

  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(
    dirs$shared_figures, dirs$shared_tables,
    file.path(dirs$project, "Figures"),
    file.path(dirs$project, "Tables")
  ))

  # Fig4：Ridge 路径 + CV（占原 LASSO 图位）
  pdf_path <- file.path(
    dirs$shared_figures,
    "Figure 4. Ridge shrinkage of pre-specified predictors.pdf"
  )
  # 清旧 LASSO 图文件名，避免混留
  old_lasso <- c(
    file.path(dirs$shared_figures, "Figure 4. LASSO regression analysis.pdf"),
    file.path(dirs$project, "Figures", "Figure 4. LASSO regression analysis.pdf"),
    file.path(dirs$project, "summary_results", "Figures", "pdf",
              "Figure 4. LASSO regression analysis.pdf")
  )
  unlink(old_lasso[file.exists(old_lasso)])

  grDevices::pdf(pdf_path, width = 10, height = 5)
  op <- graphics::par(mfrow = c(1, 2), mar = c(5, 4.5, 3.5, 1.5))
  graphics::plot(fit, xvar = "lambda", label = FALSE)
  graphics::abline(v = log(lam), lty = 2, col = "firebrick", lwd = 1.5)
  graphics::mtext("A. Ridge coefficient paths", side = 3, line = 1.8, cex = 1, font = 2)
  graphics::plot(cvfit)
  graphics::mtext("B. 10-fold CV (ridge, one-SE)", side = 3, line = 1.8, cex = 1, font = 2)
  graphics::par(op)
  grDevices::dev.off()
  file.copy(pdf_path, file.path(dirs$project, "Figures", basename(pdf_path)), overwrite = TRUE)

  coefs <- as.matrix(stats::coef(cvfit, s = lam))
  keep <- rownames(coefs)[rownames(coefs) != "(Intercept)"]
  sel <- data.frame(
    feature = keep,
    ridge_coef = as.numeric(coefs[keep, 1]),
    stringsAsFactors = FALSE
  )
  meta <- data.frame(
    item = c(
      "method", "prespecified_predictors", "lambda_rule", "lambda",
      "alpha", "n_train", "n_events"
    ),
    value = c(
      "clinical_prespecification + ridge (glmnet alpha=0)",
      paste(use, collapse = ", "),
      s_use,
      sprintf("%.6g", lam),
      "0",
      as.character(nrow(train)),
      as.character(sum(y01 == 1L))
    ),
    stringsAsFactors = FALSE
  )
  tab_coef <- file.path(dirs$shared_tables, "Table_prespecified_ridge_coefficients.csv")
  tab_meta <- file.path(dirs$shared_tables, "Table_prespecified_predictors.csv")
  utils::write.csv(sel, tab_coef, row.names = FALSE)
  utils::write.csv(meta, tab_meta, row.names = FALSE)
  # 兼容旧文件名指针：写说明，删旧 LASSO 表
  old_tabs <- c(
    file.path(dirs$shared_tables, "Table_LASSO_selected_lambda1se.csv"),
    file.path(dirs$project, "Tables", "Table_LASSO_selected_lambda1se.csv"),
    file.path(dirs$project, "summary_results", "Tables", "Table_LASSO_selected_lambda1se.csv")
  )
  unlink(old_tabs[file.exists(old_tabs)])
  dest_dir <- file.path(dirs$project, "Tables")
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(tab_coef, file.path(dest_dir, basename(tab_coef)), overwrite = TRUE)
  file.copy(tab_meta, file.path(dest_dir, basename(tab_meta)), overwrite = TRUE)
  writeLines(c(
    "Prediction features = clinically pre-specified (not LASSO-selected).",
    paste0("Predictors: ", paste(use, collapse = ", "), "."),
    "Fig4 = ridge (alpha=0) coefficient paths + 10-fold CV; lambda.1se marked.",
    "Excluded from prediction pool by design: CT % / ct_min/max (near-separation),",
    "stone_type / shape / color / surface (separation or non-prespec)."
  ), file.path(dirs$shared_tables, "Methods_prespec_ridge.txt"))

  # selected = 预指定原列（供下游 MV/列线图使用；非稀疏清零结果）
  ctx$results$gallstone_lasso_onese <- list(
    method = "prespec_ridge",
    lambda_1se = cvfit$lambda.1se,
    lambda_min = cvfit$lambda.min,
    lambda_used = lam,
    lambda_rule = s_use,
    selected = use,
    ridge_table = sel,
    cvfit = cvfit,
    x_train = mm,
    y_train = y01,
    features = use,
    prespecified = use
  )
  ctx$results$gallstone_prespec_ridge <- ctx$results$gallstone_lasso_onese
  cli::cli_alert_success(
    "Fig4 prespec+ridge: predictors={paste(use, collapse=', ')} ({s_use})"
  )
  ctx
}

register_block(
  "gallstone_lasso_onese",
  block_gallstone_lasso_onese,
  "胆结石临床预指定+Ridge Fig4（替代LASSO）"
)
