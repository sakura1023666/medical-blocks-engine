###############################################################################
#  cox_simple_continuous — 单次连续暴露 Cox（自 Blocks/57_crm/crm_cox_mortality 迁入）
#  register_block: "cox_simple_continuous"
#  兼容 config$dual_incidence_mr 与 config$cox_simple_continuous
###############################################################################

block_cox_simple_continuous <- function(ctx, ...) {
  bl <- ctx$config$cox_simple_continuous %||% ctx$config$dual_incidence_mr %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cox_simple_continuous: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  x <- bl$exposure_var %||% bl$index_var %||% "SUA"
  time_var <- bl$time_var %||% ctx$config$survival$time_var %||% "futime"
  event_var <- bl$event_var %||% ctx$config$survival$event_var %||% "fustatus"
  covs_default <- bl$covariates %||% c("Age", "Gender")
  covs <- intersect(covs_default, names(data))
  fit <- survival::coxph(
    as.formula(paste0("Surv(", time_var, ",", event_var, ")~", x,
                      if (length(covs)) paste("+", paste(covs, collapse = "+")) else "")),
    data = data
  )
  s <- summary(fit)
  tab <- data.frame(
    term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
    lower = round(s$conf.int[, "lower .95"], 3), upper = round(s$conf.int[, "upper .95"], 3),
    p = signif(s$coefficients[, "Pr(>|z|)"], 3), stringsAsFactors = FALSE
  )
  out_name <- bl$table_filename %||% "Table_Cox_Mortality_SUA.csv"
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", out_name)
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cox_simple_continuous <- list(table = tab)
  ctx$results$crm_cox <- list(table = tab)  # 兼容旧键
  cli::cli_alert_success("cox_simple_continuous 完成")
  ctx
}

register_block("cox_simple_continuous", block_cox_simple_continuous, "Cox 连续暴露（单次）")
