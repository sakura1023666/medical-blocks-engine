###############################################################################
#  competing_finegray — Fine-Gray 竞争风险 Cox（WHF vs 死亡）
###############################################################################

block_competing_finegray <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_finegray: 无数据", call. = FALSE)
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$exposure_var %||% "TyG_quartile"
  if (!event_col %in% names(data)) stop("缺少竞争事件列 ", event_col, call. = FALSE)
  tab <- data.frame(model = "FineGray", term = exp_var, HR = NA_real_, p = NA_real_, stringsAsFactors = FALSE)
  if (requireNamespace("riskRegression", quietly = TRUE) && requireNamespace("prodlim", quietly = TRUE)) {
    data$event_fg <- as.integer(data[[event_col]])
    data$ftime <- as.numeric(data[[time_var]])
    covs <- intersect(c("Age", "Gender", "BMI"), names(data))
    fml <- as.formula(paste0("Hist(ftime, event_fg)~", exp_var,
                             if (length(covs)) paste("+", paste(covs, collapse = "+")) else ""))
    fit <- tryCatch(
      riskRegression::FGR(fml, data = data, cause = 1L),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      s <- summary(fit)
      if (!is.null(s$coef) && nrow(s$coef)) {
        tab <- data.frame(
          term = rownames(s$coef),
          HR = round(exp(s$coef[, "coef"]), 3),
          p = signif(s$coef[, "P-value"], 3),
          cause = "WHF",
          stringsAsFactors = FALSE
        )
      }
    }
  } else if (requireNamespace("survival", quietly = TRUE)) {
    data$evt <- as.integer(data[[event_col]] == 1L)
    fit <- survival::coxph(as.formula(paste0("Surv(", time_var, ", evt)~", exp_var)), data = data)
    s <- summary(fit)
    tab <- data.frame(
      term = rownames(s$coefficients), HR = round(s$conf.int[, "exp(coef)"], 3),
      p = signif(s$coefficients[, "Pr(>|z|)"], 3), cause = "WHF_cox_fallback",
      stringsAsFactors = FALSE
    )
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_FineGray_", bl$index_var %||% "TyG", "_WHF.csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$competing_finegray <- list(table = tab)
  cli::cli_alert_success("Fine-Gray 竞争风险完成")
  ctx
}

register_block("competing_finegray", block_competing_finegray, "Fine-Gray 竞争风险")
