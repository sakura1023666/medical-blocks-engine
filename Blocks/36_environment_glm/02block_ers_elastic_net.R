###############################################################################
#  ers_elastic_net — 自适应弹性网环境风险评分 + 加权 logistic（权重列齐全时）
#
#  register_block: "ers_elastic_net"
#  文献用 gcdnet。本块优先 glmnet（alpha 网格 + 5 折），避免改旧 LASSO 块。
#  弹性网本身原文未写抽样权重；ERS 与结局的 Model1/2 在权重可用时用 svyglm。
#
#  config$ers_elastic_net = list(
#    alphas = seq(0, 1, length.out = 11),
#    nfolds = 5L,
#    bootstrap_B = 200L,
#    seed = 2024L,
#    survey_weight = "WTMEC2YR",
#    survey_psu = "SDMVPSU",
#    survey_strata = "SDMVSTRA"
#  )
###############################################################################

block_ers_elastic_net <- function(ctx, ...) {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  source(file.path(root, "R/environment_exwas_core.R"), local = FALSE)
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    stop("需要 R 包 glmnet", call. = FALSE)
  }
  cfg <- ctx$config$ers_elastic_net %||% list()
  df <- ctx$data$imputed %||% ctx$data$cleaned
  y <- ctx$results$exwas_outcome %||% "DN"
  xs <- ctx$results$exwas_exposures
  if (!length(xs)) stop("缺少 exwas_exposures", call. = FALSE)
  panel <- cfg$panel_prefix %||% NULL
  if (!is.null(panel) && nzchar(panel)) {
    hit <- xs[grepl(paste0("^", panel), xs)]
    if (length(hit) >= 5L) xs <- hit
  }
  # 按共同测定人数从最完整的一列往上加，加到共同人数仍不少于 150 为止。
  nobs <- vapply(xs, function(x) sum(!is.na(df[[x]])), integer(1))
  xs <- xs[order(-nobs)]
  chosen <- xs[1]
  for (x in xs[-1]) {
    trial <- c(chosen, x)
    n_cc <- sum(stats::complete.cases(df[, trial, drop = FALSE]))
    if (n_cc >= 150L) chosen <- trial
  }
  xs <- chosen
  exwas_log("ERS 使用共同测定暴露 ", length(xs), " 个")
  covars <- ctx$config$exwas_unweighted$covariates %||% character(0)
  covars <- intersect(covars, names(df))
  dd <- df[, c(y, xs), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  X <- as.matrix(dd[, xs, drop = FALSE])
  yy <- dd[[y]]
  alphas <- cfg$alphas %||% seq(0, 1, length.out = 11)
  set.seed(cfg$seed %||% 2024L)
  best <- NULL
  for (a in alphas) {
    cv <- tryCatch(
      glmnet::cv.glmnet(X, yy, family = "binomial", alpha = a,
                        nfolds = cfg$nfolds %||% 5L, standardize = TRUE),
      error = function(e) NULL
    )
    if (is.null(cv)) next
    dev <- min(cv$cvm)
    if (is.null(best) || dev < best$dev) best <- list(alpha = a, cv = cv, dev = dev)
  }
  if (is.null(best)) stop("弹性网未能拟合", call. = FALSE)
  coefs <- as.matrix(stats::coef(best$cv, s = "lambda.min"))
  sel <- setdiff(rownames(coefs)[abs(coefs[, 1]) > 0], "(Intercept)")
  B <- cfg$bootstrap_B %||% 200L
  freq <- setNames(numeric(length(xs)), xs)
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(dd), replace = TRUE)
    cvb <- tryCatch(
      glmnet::cv.glmnet(X[idx, , drop = FALSE], yy[idx], family = "binomial",
                        alpha = best$alpha, nfolds = 3L),
      error = function(e) NULL
    )
    if (is.null(cvb)) next
    cb <- as.matrix(stats::coef(cvb, s = "lambda.min"))
    hit <- setdiff(rownames(cb)[abs(cb[, 1]) > 0], "(Intercept)")
    freq[intersect(hit, xs)] <- freq[intersect(hit, xs)] + 1
  }
  freq <- freq / B
  dd$ERS <- as.numeric(X[, sel, drop = FALSE] %*% coefs[sel, 1])
  iqr <- stats::IQR(dd$ERS)
  if (!is.finite(iqr) || iqr == 0) iqr <- 1
  dd$ERS_IQR <- dd$ERS / iqr
  dd$ERS_high <- as.integer(dd$ERS >= stats::median(dd$ERS))
  # 把 ERS 合并回插补数据（按行号不安全）。用暴露线性组合在全数据上重算。
  full <- df
  ok <- stats::complete.cases(full[, sel, drop = FALSE])
  full$ERS <- NA_real_
  full$ERS[ok] <- as.numeric(as.matrix(full[ok, sel, drop = FALSE]) %*% coefs[sel, 1])
  ctx$data$imputed <- full
  ctx$results$ers_selected <- sel
  ctx$results$ers_alpha <- best$alpha
  ctx$results$ers_inclusion <- freq
  out <- ctx$config$project$output_dir %||% "Output/exwas"
  exwas_ensure_dir(out)
  utils::write.csv(
    data.frame(exposure = names(freq), inclusion = as.numeric(freq)),
    file.path(out, "Table_S5_ERS_inclusion.csv"), row.names = FALSE
  )
  # Model1 空模，Model2 全协变量。权重列齐全才 svyglm。
  survey_cfg <- list(
    survey_weight = cfg$survey_weight %||% "WTMEC2YR",
    survey_psu = cfg$survey_psu %||% "SDMVPSU",
    survey_strata = cfg$survey_strata %||% "SDMVSTRA"
  )
  use <- full[is.finite(full$ERS), , drop = FALSE]
  use$ERS_IQR <- use$ERS / iqr
  rows <- list()
  specs <- list(
    list(model = "Model1", covars = character(0)),
    list(model = "Model2", covars = covars)
  )
  for (spec in specs) {
    model <- spec$model
    cv <- intersect(spec$covars, names(use))
    if (exwas_has_survey(use, survey_cfg)) {
      est <- exwas_weighted_logit(use, y, "ERS_IQR", cv, survey_cfg)
      weighted <- TRUE
    } else {
      est <- exwas_fit_one(use, y, "ERS_IQR", cv)
      est <- est[, c("OR", "lo", "hi", "p")]
      weighted <- FALSE
    }
    rows[[length(rows) + 1L]] <- data.frame(model = model, weighted = weighted, est)
  }
  tab <- do.call(rbind, rows)
  utils::write.csv(tab, file.path(out, "Table_ERS_logistic.csv"), row.names = FALSE)
  if (!any(tab$weighted)) {
    writeLines(
      "未找到 WTMEC2YR/SDMVPSU/SDMVSTRA，ERS 关联暂为不加权 logistic。补齐设计列后重跑本块即可加权。",
      file.path(out, "weight_unavailable_ERS.txt")
    )
  }
  exwas_log("ERS 入选 ", length(sel), " 个暴露；alpha=", best$alpha)
  ctx
}

register_block(
  "ers_elastic_net",
  block_ers_elastic_net,
  "弹性网环境风险评分及结局关联"
)
