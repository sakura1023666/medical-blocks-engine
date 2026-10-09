###############################################################################
# gallstone_mv_nomogram — Fig5 多因素（Firth/brglm2）+ Fig6 rms 列线图
# 预测因子 = 临床预指定（来自 gallstone_lasso_onese / prespec_ridge），非 LASSO 海选
###############################################################################

block_gallstone_mv_nomogram <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  if (!requireNamespace("rms", quietly = TRUE)) stop("需要 rms", call. = FALSE)

  train <- ctx$data$train %||% ctx$data$imputed
  outcome <- ctx$config$data$outcome_column %||% "Success"
  las <- ctx$results$gallstone_prespec_ridge %||% ctx$results$gallstone_lasso_onese

  use <- las$prespecified %||% las$selected %||% gallstone_nomogram_prespec_predictors(ctx$config)
  # 兼容旧 LASSO 哑变量名 → 原列
  if (!is.null(las$method) && identical(las$method, "prespec_ridge")) {
    use <- as.character(use)
  } else if (length(las$selected)) {
    feats <- unique(c(gallstone_nomogram_cont_features(ctx$config),
                      gallstone_nomogram_cat_features(ctx$config)))
    hit <- feats[vapply(feats, function(f) {
      any(grepl(paste0("^", f), las$selected) | las$selected == f)
    }, logical(1))]
    if (length(hit)) use <- hit
  }
  use <- unique(use[use %in% names(train)])
  if (!length(use)) stop("MV/nomogram: 无可用预测因子", call. = FALSE)

  d <- train[, c(outcome, use), drop = FALSE]
  y <- d[[outcome]]
  if (is.factor(y)) {
    d[[outcome]] <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
  } else {
    d[[outcome]] <- as.integer(as.numeric(y) == 1L)
  }
  for (cc in intersect(gallstone_nomogram_cat_features(ctx$config), use)) {
    d[[cc]] <- factor(d[[cc]])
  }

  fml <- stats::as.formula(paste(outcome, "~", paste(use, collapse = " + ")))
  # Firth / bias-reduced logistic（小样本 + 准分离）
  fit_glm <- tryCatch({
    if (requireNamespace("brglm2", quietly = TRUE)) {
      stats::glm(fml, data = d, family = stats::binomial(), method = brglm2::brglmFit)
    } else {
      stats::glm(fml, data = d, family = stats::binomial())
    }
  }, error = function(e) stats::glm(fml, data = d, family = stats::binomial()))

  sm <- summary(fit_glm)$coefficients
  tn <- setdiff(rownames(sm), "(Intercept)")
  est <- sm[tn, "Estimate"]
  se <- sm[tn, "Std. Error"]
  pval <- sm[tn, ncol(sm)]
  or <- exp(est)
  lo <- exp(est - 1.96 * se)
  hi <- exp(est + 1.96 * se)
  tab <- data.frame(
    term = tn,
    OR = as.numeric(or),
    CI_low = as.numeric(lo),
    CI_high = as.numeric(hi),
    P = as.numeric(pval),
    OR_CI = sprintf("%.2f (%.2f, %.2f)", as.numeric(or), as.numeric(lo), as.numeric(hi)),
    stringsAsFactors = FALSE
  )

  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(
    dirs$shared_figures, dirs$shared_tables,
    file.path(dirs$project, "Figures"), file.path(dirs$project, "Tables")
  ))
  utils::write.csv(tab, file.path(dirs$shared_tables, "Table_multivariate_logistic.csv"),
                   row.names = FALSE)
  file.copy(
    file.path(dirs$shared_tables, "Table_multivariate_logistic.csv"),
    file.path(dirs$project, "Tables", "Table_multivariate_logistic.csv"),
    overwrite = TRUE
  )
  writeLines(c(
    paste0("Multivariate = Firth/brglm2 logistic on clinically pre-specified predictors: ",
           paste(use, collapse = ", "), "."),
    "Not LASSO-selected. Fig5 forest from Firth OR; Fig6 nomogram from rms::lrm on same set."
  ), file.path(dirs$shared_tables, "Methods_mv_prespec_firth.txt"))

  # Fig5 简易森林（finalize/rebuild 可再美化）
  pdf(file.path(dirs$shared_figures, "Figure 5. Multivariate logistic regression.pdf"),
      width = 8, height = max(3.5, 0.42 * nrow(tab) + 2))
  op <- graphics::par(mar = c(5, 12, 3, 2))
  ys <- seq_len(nrow(tab))
  xlim <- range(c(tab$CI_low, tab$CI_high, 1), finite = TRUE)
  if (!all(is.finite(xlim)) || diff(xlim) == 0) xlim <- c(0.2, 5)
  lo_p <- pmax(tab$CI_low, xlim[1])
  hi_p <- pmin(tab$CI_high, xlim[2])
  graphics::plot(
    pmin(pmax(tab$OR, xlim[1]), xlim[2]), ys, pch = 15, col = "#E67E22",
    xlim = xlim, log = "x", yaxt = "n",
    xlab = "OR (log scale)", ylab = "",
    main = "Multivariate logistic (Firth; pre-specified)"
  )
  graphics::axis(2, at = ys, labels = tab$term, las = 1, cex.axis = 0.8)
  graphics::arrows(lo_p, ys, hi_p, ys, angle = 90, code = 3, length = 0.04)
  graphics::abline(v = 1, lty = 2, col = "grey40")
  graphics::par(op)
  grDevices::dev.off()
  file.copy(
    file.path(dirs$shared_figures, "Figure 5. Multivariate logistic regression.pdf"),
    file.path(dirs$project, "Figures", "Figure 5. Multivariate logistic regression.pdf"),
    overwrite = TRUE
  )

  # Fig6 nomogram：同变量集 rms::lrm
  dd <- rms::datadist(d)
  options(datadist = "dd")
  assign("dd", dd, envir = .GlobalEnv)
  fit <- tryCatch(
    rms::lrm(fml, data = d, x = TRUE, y = TRUE),
    error = function(e) NULL
  )
  pdf(file.path(dirs$shared_figures, "Figure 6. Nomogram prediction model.pdf"),
      width = 10, height = max(4.5, 0.7 * length(use) + 3))
  if (!is.null(fit)) {
    nom <- tryCatch(
      rms::nomogram(fit, fun = stats::plogis, funlabel = "Predicted probability of success"),
      error = function(e) NULL
    )
    if (!is.null(nom)) {
      info <- attr(nom, "info")
      if (!is.null(info)) {
        info$lp <- FALSE
        attr(nom, "info") <- info
      }
      graphics::plot(
        nom, xfrac = 0.24, cex.axis = 0.9, cex.var = 1.1,
        col.grid = c("#7EADCF", "#D0E4F4"),
        points.label = "Points", total.points.label = "Total Points"
      )
    } else {
      graphics::plot.new(); graphics::title("Nomogram failed")
    }
  } else {
    graphics::plot.new(); graphics::title("Nomogram failed (lrm)")
  }
  grDevices::dev.off()
  file.copy(
    file.path(dirs$shared_figures, "Figure 6. Nomogram prediction model.pdf"),
    file.path(dirs$project, "Figures", "Figure 6. Nomogram prediction model.pdf"),
    overwrite = TRUE
  )
  options(datadist = NULL)

  ctx$results$gallstone_mv_nomogram <- list(
    fit = fit,
    fit_glm = fit_glm,
    features = use,
    table = tab,
    method = "prespec_firth"
  )
  cli::cli_alert_success(
    "Fig5-6 prespec Firth + nomogram: {length(use)} features ({paste(use, collapse=', ')})"
  )
  ctx
}

register_block(
  "gallstone_mv_nomogram",
  block_gallstone_mv_nomogram,
  "胆结石预指定Firth多因素+列线图"
)
