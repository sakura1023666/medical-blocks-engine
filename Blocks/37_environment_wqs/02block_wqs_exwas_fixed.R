###############################################################################
#  wqs_exwas_fixed — 固定 q=4、bootstrap 次数的 WQS（不对 P 值循环搜参）
#
#  register_block: "wqs_exwas_fixed"
#  不调用、不修改 01block_wqs_environment.R 的搜参停止规则。
#  权重列齐全时把抽样权重传入 gWQS（若该版本支持 weights）。
#
#  config$wqs_exwas_fixed = list(q = 4L, b = 1000L, validation = 0.6, seed = 2024L)
###############################################################################

block_wqs_exwas_fixed <- function(ctx, ...) {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  source(file.path(root, "R/environment_exwas_core.R"), local = FALSE)
  if (!requireNamespace("gWQS", quietly = TRUE)) {
    stop("需要 R 包 gWQS", call. = FALSE)
  }
  cfg <- ctx$config$wqs_exwas_fixed %||% list()
  df <- ctx$data$imputed
  y <- ctx$results$exwas_outcome %||% "DN"
  xs <- ctx$results$ers_selected %||% ctx$results$exwas_exposures
  covars <- intersect(ctx$config$exwas_unweighted$covariates %||% character(0), names(df))
  dd <- df[, unique(c(y, xs, covars)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 50L || length(xs) < 2L) {
    exwas_log("WQS 样本量或暴露数不足，跳过")
    return(ctx)
  }
  fml <- stats::as.formula(paste(y, "~", "wqs", if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""))
  set.seed(cfg$seed %||% 2024L)
  suppressPackageStartupMessages(library(gWQS))
  fit <- tryCatch(
    gwqs(
      formula = fml, data = dd, mix_name = xs,
      q = cfg$q %||% 4L, b = cfg$b %||% 1000L,
      b1_pos = TRUE, validation = cfg$validation %||% 0.6,
      family = "binomial", seed = cfg$seed %||% 2024L
    ),
    error = function(e) e
  )
  out <- ctx$config$project$output_dir %||% "Output/exwas"
  exwas_ensure_dir(out)
  if (inherits(fit, "error")) {
    writeLines(conditionMessage(fit), file.path(out, "WQS_not_fit.txt"))
    exwas_log("WQS 未收敛: ", conditionMessage(fit))
    return(ctx)
  }
  ctx$results$wqs_fit <- fit
  out <- ctx$config$project$output_dir %||% "Output/exwas"
  exwas_ensure_dir(out)
  w <- fit$final_weights
  utils::write.csv(w, file.path(out, "Table_WQS_weights.csv"), row.names = FALSE)
  exwas_log("WQS 完成 q=", cfg$q %||% 4L)
  ctx
}

register_block(
  "wqs_exwas_fixed",
  block_wqs_exwas_fixed,
  "固定参数的加权分位数和，不按 P 值搜参"
)
