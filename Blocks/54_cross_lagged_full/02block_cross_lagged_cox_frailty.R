###############################################################################
#  cross_lagged_cox_frailty — 基线衰弱与 CVD 发病 Cox
###############################################################################

block_cross_lagged_cox_frailty <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_cox_frailty: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE))
    stop("请安装 survival", call. = FALSE)
  fi_var <- bl$fi_var %||% "FI_T1"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  if (!event_var %in% names(data) && "fustatus" %in% names(data)) event_var <- "fustatus"
  if (!fi_var %in% names(data)) stop("缺少 FI 列: ", fi_var, call. = FALSE)
  data[[time_var]] <- as.numeric(data[[time_var]])
  if (is.factor(data[[event_var]])) {
    case_lbl <- pipeline_outcome_case_label(ctx$config)
    data[[event_var]] <- as.integer(as.character(data[[event_var]]) == case_lbl)
  } else {
    data[[event_var]] <- as.integer(as.character(data[[event_var]]))
  }
  data[[fi_var]] <- as.numeric(data[[fi_var]])
  data <- data[complete.cases(data[[time_var]], data[[event_var]], data[[fi_var]]), , drop = FALSE]
  if (nrow(data) < 10L) stop("Cox: 有效样本不足 (n=", nrow(data), ")", call. = FALSE)
  covs <- intersect(c("Age", "Gender"), names(data))
  fml <- as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ",
                           fi_var, if (length(covs)) paste("+", paste(covs, collapse = "+")) else ""))
  fit <- survival::coxph(fml, data = data)
  s <- summary(fit)
  tab <- data.frame(
    term = rownames(s$coefficients),
    HR = round(s$conf.int[, "exp(coef)"], 3),
    lower = round(s$conf.int[, "lower .95"], 3),
    upper = round(s$conf.int[, "upper .95"], 3),
    p = signif(s$coefficients[, "Pr(>|z|)"], 3),
    stringsAsFactors = FALSE
  )
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Cox_Frailty_CVD.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_cox <- list(table = tab, model = fit)
  cli::cli_alert_success("Cox 衰弱→CVD 完成")
  ctx
}

register_block("cross_lagged_cox_frailty", block_cross_lagged_cox_frailty, "Cox 衰弱与 CVD")
