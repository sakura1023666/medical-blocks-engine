###############################################################################
#  sem_sensitivity — 敏感性分析（排除早期衰弱事件）
#  文献: Zhu 2025 J Adv Research
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

.sem_cox_hr <- function(d, pred, time_var, event_var, covs) {
  need <- c(pred, time_var, event_var)
  if (!all(need %in% names(d))) return(NA_real_)
  dd <- d[complete.cases(d[need]), , drop = FALSE]
  if (nrow(dd) < 20L) return(NA_real_)
  adj <- setdiff(intersect(covs, names(dd)), pred)
  rhs <- paste(c(pred, adj), collapse = " + ")
  fit <- tryCatch(
    survival::coxph(stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs)), data = dd),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NA_real_)
  round(summary(fit)$conf.int[pred, "exp(coef)"], 3)
}

block_sem_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_sensitivity: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)

  x <- bl$exposure_var %||% "Sarcopenia"
  m1 <- bl$m1_var %||% "Depression"
  m2 <- bl$m2_var %||% "Cognitive_score"
  time_var <- bl$time_var %||% "Frailty_time"
  event_var <- bl$event_var %||% "Frailty_event"
  covs <- bl$covariate_vars %||% c("Age", "Gender")
  exclude_years <- as.numeric(bl$sensitivity_exclude_years %||% bl$early_event_cutoff %||% 1)

  if (!all(c(time_var, event_var) %in% names(data))) {
    cli::cli_alert_warning("sem_sensitivity: 缺少生存变量")
    return(ctx)
  }

  d_excl <- data
  early <- d_excl[[event_var]] == 1L & !is.na(d_excl[[time_var]]) & d_excl[[time_var]] <= exclude_years
  d_excl <- d_excl[!early, , drop = FALSE]
  d_excl[[event_var]] <- as.integer(d_excl[[event_var]] == 1L)
  d_excl[[time_var]] <- pmax(d_excl[[time_var]] - exclude_years, 0.01)

  scenarios <- list(
    primary = data,
    exclude_early_events = d_excl
  )
  if (bl$sensitivity_exclude_depression %||% FALSE) {
    scenarios$exclude_baseline_depression <- data[data[[m1]] != 1L, , drop = FALSE]
  }

  preds <- c(x, m1, m2)
  rows <- list()
  for (sc in names(scenarios)) {
    dd <- scenarios[[sc]]
    for (pred in preds) {
      if (!pred %in% names(dd)) next
      rows[[length(rows) + 1L]] <- data.frame(
        scenario = sc,
        predictor = pred,
        HR = .sem_cox_hr(dd, pred, time_var, event_var, covs),
        n = nrow(dd),
        events = sum(dd[[event_var]] == 1L, na.rm = TRUE),
        exclude_years = if (sc == "exclude_early_events") exclude_years else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no sensitivity results")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Sensitivity.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$results$sem_sensitivity <- list(table = tab, exclude_years = exclude_years)
  cli::cli_alert_success("敏感性分析完成 (排除 ≤{exclude_years} 年事件)")
  ctx
}

register_block("sem_sensitivity", block_sem_sensitivity, "排除早期事件敏感性")
