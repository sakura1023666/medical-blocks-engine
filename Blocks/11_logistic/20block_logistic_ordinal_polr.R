###############################################################################
#  logistic_ordinal_polr — 有序 Logistic（polr）
#  自 57_crm 迁入；文献课题参数由 config 提供
###############################################################################

block_logistic_ordinal_polr <- function(ctx, ...) {
  bl <- ctx$config$logistic_ordinal_polr %||% ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("logistic_ordinal_polr: 无数据", call. = FALSE)
  y <- bl$crm_outcome_col %||% "CRM_count"
  x <- bl$exposure_var %||% "SUA"
  if (!all(c(y, x) %in% names(data))) stop("缺少 CRM 或 SUA 列", call. = FALSE)
  data[[y]] <- factor(data[[y]], ordered = TRUE)
  covs <- intersect(c("Age", "Gender"), names(data))
  if (!requireNamespace("MASS", quietly = TRUE)) stop("请安装 MASS", call. = FALSE)
  fml <- as.formula(paste(y, "~", x, if (length(covs)) paste("+", paste(covs, collapse = "+")) else ""))
  fit <- tryCatch(MASS::polr(fml, data = data, Hess = TRUE), error = function(e) NULL)
  tab <- data.frame(term = x, OR = NA_real_, p = NA_real_, stringsAsFactors = FALSE)
  if (!is.null(fit)) {
    ct <- coef(summary(fit))
    pcol <- intersect(c("Pr(>|t|)", "Pr(>|z|)"), colnames(ct))[1]
    tab <- data.frame(
      term = rownames(ct),
      OR = round(exp(ct[, 1]), 3),
      p = if (!is.na(pcol)) signif(ct[, pcol], 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Ordinal_CRM_SUA.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$logistic_ordinal_polr <- list(table = tab)
  ctx$results$crm_ordinal <- list(table = tab)
  cli::cli_alert_success("有序 Logistic (MASS::polr) 完成")
  ctx
}

register_block("logistic_ordinal_polr", block_logistic_ordinal_polr, "有序 Logistic (MASS::polr)")
