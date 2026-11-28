###############################################################################
# gallstone_roc_cal_boot — Fig7 ROC+校准；第三列=bootstrap（替外验）
###############################################################################

block_gallstone_roc_cal_boot <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  fit_info <- ctx$results$gallstone_mv_nomogram
  if (is.null(fit_info$fit)) stop("roc_cal: 需先跑 gallstone_mv_nomogram", call. = FALSE)
  fit <- fit_info$fit
  use <- fit_info$features
  outcome <- ctx$config$data$outcome_column %||% "Success"
  train <- ctx$data$train
  test <- ctx$data$test
  bl <- ctx$config$gallstone_nomogram %||% list()
  B <- as.integer(bl$bootstrap_B %||% 200L)
  seed <- as.integer(bl$seed %||% 42L)

  .align_factors <- function(d, ref) {
    out <- d
    for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), names(out))) {
      if (cc %in% names(ref)) {
        out[[cc]] <- factor(as.character(out[[cc]]), levels = levels(factor(ref[[cc]])))
      } else {
        out[[cc]] <- factor(out[[cc]])
      }
    }
    out
  }
  .y01 <- function(d) {
    y <- d[[outcome]]
    if (is.factor(y)) as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
    else as.integer(as.numeric(y) == 1L)
  }
  .pred_rms <- function(d) {
    dd <- .align_factors(d, train)
    # 缺失因子水平 → NA 行；用 try
    pr <- tryCatch(
      as.numeric(stats::predict(fit, dd[, use, drop = FALSE], type = "fitted")),
      error = function(e) rep(NA_real_, nrow(dd))
    )
    pr
  }
  .pred_glm <- function(model, d, ref) {
    dd <- .align_factors(d, ref)
    tryCatch(as.numeric(stats::predict(model, newdata = dd, type = "response")),
             error = function(e) rep(NA_real_, nrow(dd)))
  }
  .auc <- function(y, p) {
    ok <- is.finite(y) & is.finite(p)
    y <- y[ok]; p <- p[ok]
    if (length(y) < 5 || length(unique(y)) < 2) return(NA_real_)
    if (requireNamespace("pROC", quietly = TRUE)) {
      as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE)))
    } else {
      r <- rank(p)
      n1 <- sum(y == 1); n0 <- sum(y == 0)
      if (n1 < 1 || n0 < 1) return(NA_real_)
      (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
    }
  }
  .cal_plot <- function(y, p, main) {
    if (requireNamespace("ggplot2", quietly = TRUE) && requireNamespace("dplyr", quietly = TRUE)) {
      # base loess
    }
    ok <- is.finite(p) & is.finite(y)
    y <- y[ok]; p <- p[ok]
    plot(0:1, 0:1, type = "n", xlab = "Predicted", ylab = "Observed", main = main)
    abline(0, 1, lty = 2, col = "grey50")
    if (length(unique(p)) > 5) {
      lo <- stats::lowess(p, y, f = 0.5)
      lines(lo, col = "steelblue", lwd = 2)
    }
    points(p, y, pch = 16, cex = 0.4, col = adjustcolor("black", 0.3))
  }
  .roc_plot <- function(y, p, main) {
    if (requireNamespace("pROC", quietly = TRUE)) {
      r <- pROC::roc(y, p, quiet = TRUE)
      plot(r, main = sprintf("%s\nAUC=%.3f", main, as.numeric(pROC::auc(r))))
    } else {
      plot.new(); title(sprintf("%s AUC=%.3f", main, .auc(y, p)))
    }
  }

  y_tr <- .y01(train); p_tr <- .pred_rms(train)
  y_va <- .y01(test);  p_va <- .pred_rms(test)
  # bootstrap on full analysis set as "third panel"
  full <- .align_factors(rbind(train, test), train)
  set.seed(seed)
  auc_boot <- rep(NA_real_, B)
  # 用 train 上 glm 近似（对齐因子）；bootstrap 重拟合容错
  train2 <- .align_factors(train, train)
  train2[[outcome]] <- .y01(train2)
  for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), use)) {
    train2[[cc]] <- factor(train2[[cc]])
  }
  suppressWarnings({
    for (b in seq_len(B)) {
      ii <- sample.int(nrow(full), replace = TRUE)
      db <- .align_factors(full[ii, , drop = FALSE], train)
      db[[outcome]] <- .y01(db)
      for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), use)) {
        db[[cc]] <- factor(db[[cc]], levels = levels(factor(train[[cc]])))
      }
      fb <- tryCatch(
        stats::glm(stats::as.formula(paste(outcome, "~", paste(use, collapse = "+"))),
                   data = db, family = binomial()),
        error = function(e) NULL
      )
      if (is.null(fb)) next
      pb <- .pred_glm(fb, full, train)
      auc_boot[b] <- .auc(.y01(full), pb)
    }
  })
  # bootstrap 平均预测：少次数即可（面板展示）
  n_rep <- min(30L, B)
  p_mat <- matrix(NA_real_, nrow = nrow(full), ncol = n_rep)
  suppressWarnings({
    for (j in seq_len(n_rep)) {
      ii <- sample.int(nrow(full), replace = TRUE)
      db <- .align_factors(full[ii, , drop = FALSE], train)
      db$.y <- .y01(db)
      for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), use)) {
        db[[cc]] <- factor(db[[cc]], levels = levels(factor(train[[cc]])))
      }
      fb <- tryCatch(
        stats::glm(stats::as.formula(paste(".y ~", paste(use, collapse = "+"))),
                   data = db, family = binomial()),
        error = function(e) NULL
      )
      if (is.null(fb)) next
      p_mat[, j] <- .pred_glm(fb, transform(full, .y = .y01(full)), train)
    }
  })
  p_boot_mean <- rowMeans(p_mat, na.rm = TRUE)

  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_figures, dirs$shared_tables,
                                      file.path(dirs$project, "Figures"), file.path(dirs$project, "Tables")))
  pdf(file.path(dirs$shared_figures, "Figure 7. ROC and calibration.pdf"), width = 12, height = 8)
  par(mfrow = c(2, 3))
  .roc_plot(y_tr, p_tr, "A. ROC train")
  .roc_plot(y_va, p_va, "B. ROC internal val")
  .roc_plot(.y01(full), p_boot_mean, sprintf("C. ROC bootstrap (mean AUC=%.3f)", mean(auc_boot, na.rm = TRUE)))
  .cal_plot(y_tr, p_tr, "D. Calibration train")
  .cal_plot(y_va, p_va, "E. Calibration internal val")
  .cal_plot(.y01(full), p_boot_mean, "F. Calibration bootstrap")
  dev.off()
  file.copy(file.path(dirs$shared_figures, "Figure 7. ROC and calibration.pdf"),
            file.path(dirs$project, "Figures", "Figure 7. ROC and calibration.pdf"), overwrite = TRUE)

  metrics <- data.frame(
    set = c("train", "internal_val", "bootstrap"),
    AUC = c(.auc(y_tr, p_tr), .auc(y_va, p_va), mean(auc_boot, na.rm = TRUE)),
    AUC_boot_lo = c(NA, NA, stats::quantile(auc_boot, 0.025, na.rm = TRUE)),
    AUC_boot_hi = c(NA, NA, stats::quantile(auc_boot, 0.975, na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(metrics, file.path(dirs$shared_tables, "Table_AUC_train_val_boot.csv"), row.names = FALSE)
  file.copy(file.path(dirs$shared_tables, "Table_AUC_train_val_boot.csv"),
            file.path(dirs$project, "Tables", "Table_AUC_train_val_boot.csv"), overwrite = TRUE)

  ctx$results$gallstone_roc_cal_boot <- list(metrics = metrics, p_train = p_tr, p_val = p_va,
                                             y_train = y_tr, y_val = y_va, p_boot = p_boot_mean,
                                             y_full = .y01(full), full = full)
  cli::cli_alert_success("Fig7 ROC/cal: train={round(metrics$AUC[1],3)} val={round(metrics$AUC[2],3)}")
  ctx
}

register_block("gallstone_roc_cal_boot", block_gallstone_roc_cal_boot, "胆结石Fig7 ROC校准bootstrap")
