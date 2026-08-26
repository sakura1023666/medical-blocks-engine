###############################################################################
#  dynamic_causal_cox_total — Total CMI 三分位 Cox + RCS（双队列预后）
#
#  register_block: "dynamic_causal_cox_total"
###############################################################################

block_dynamic_causal_cox_total <- function(ctx, ...) {
  ctx$config$dynamic_causal$analysis_type <- "change"
  if (exists("block_dynamic_causal_analysis_filter", mode = "function")) {
    ctx <- block_dynamic_causal_analysis_filter(ctx)
  }
  suppressPackageStartupMessages({
    if (!requireNamespace("survival", quietly = TRUE)) stop("需要 survival 包")
    library(survival)
  })
  bl <- ctx$config$dynamic_causal_cox %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("dynamic_causal_cox_total: 无数据", call. = FALSE)

  surv <- ctx$config$survival %||% list()
  time_var <- surv$time_var %||% "futime"
  event_var <- surv$event_var %||% "CVD_event"
  tert_var <- bl$tertile_var %||% "analysis_tert"
  cont_var <- bl$continuous_var %||% "analysis_index"

  for (v in c(time_var, event_var, tert_var, cont_var)) {
    if (!v %in% names(data)) stop("dynamic_causal_cox_total: 缺列 ", v, call. = FALSE)
  }

  ev <- data[[event_var]]
  if (is.character(ev) || is.factor(ev)) {
    case_lbl <- pipeline_outcome_case_label(ctx$config)
    data[[event_var]] <- ifelse(as.character(ev) == case_lbl, 1L, 0L)
  }
  data[[event_var]] <- as.numeric(data[[event_var]])

  data <- data[!is.na(data[[time_var]]) & data[[time_var]] > 0 & !is.na(data[[event_var]]) & !is.na(data[[tert_var]]), , drop = FALSE]
  if (nrow(data) < 10L) stop("dynamic_causal_cox_total: 有效样本不足", call. = FALSE)
  data[[tert_var]] <- factor(data[[tert_var]], levels = c("T1_low", "T2_mid", "T3_high"))
  data <- data[!is.na(data[[tert_var]]), , drop = FALSE]

  m1 <- coxph(Surv(data[[time_var]], data[[event_var]]) ~ data[[tert_var]], data = data)
  m2 <- coxph(Surv(data[[time_var]], data[[event_var]]) ~ data[[cont_var]], data = data)

  sm <- summary(m1)
  hr_rows <- lapply(seq_len(nrow(sm$coefficients)), function(i) {
    rn <- rownames(sm$coefficients)[i]
    data.frame(
      term = rn,
      HR = round(exp(coef(m1)[i]), 3),
      lower = round(exp(confint(m1)[i, 1]), 3),
      upper = round(exp(confint(m1)[i, 2]), 3),
      p = signif(sm$coefficients[i, "Pr(>|z|)"], 4),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, hr_rows)
  cont_sm <- summary(m2)
  tab <- rbind(tab, data.frame(
    term = "Total_CMI_continuous",
    HR = round(exp(coef(m2)[1]), 3),
    lower = round(exp(confint(m2)[1, 1]), 3),
    upper = round(exp(confint(m2)[1, 2]), 3),
    p = signif(cont_sm$coefficients[1, "Pr(>|z|)"], 4),
    stringsAsFactors = FALSE
  ))

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_Cox_Total_CMI.csv"), row.names = FALSE)
  ctx$results$dynamic_causal_cox <- list(table = tab, model_tertile = m1, model_continuous = m2)
  cli::cli_alert_success("Total CMI Cox 完成（n={nrow(data)}，事件={sum(data[[event_var]], na.rm=TRUE)}）")
  ctx
}

register_block(
  "dynamic_causal_cox_total",
  block_dynamic_causal_cox_total,
  "动态因果 Total CMI Cox 三分位"
)
