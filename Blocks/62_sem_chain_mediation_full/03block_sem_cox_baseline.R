###############################################################################
#  sem_cox_baseline — 各路径 Cox 基线模型（肌少症/抑郁/认知 → 衰弱）
#  文献: Zhu 2025 J Adv Research
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

.sem_cox_one <- function(data, pred, time_var, event_var, covs) {
  need <- c(pred, time_var, event_var)
  if (!all(need %in% names(data))) return(NULL)
  d <- data[complete.cases(data[[pred]], data[[time_var]], data[[event_var]]), , drop = FALSE]
  adj <- intersect(covs, names(d))
  adj <- setdiff(adj, pred)
  rhs <- paste(c(pred, adj), collapse = " + ")
  fml <- stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs))
  fit <- tryCatch(survival::coxph(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  data.frame(
    path = pred,
    term = rownames(s$coefficients),
    HR = round(s$conf.int[, "exp(coef)"], 3),
    lower = round(s$conf.int[, "lower .95"], 3),
    upper = round(s$conf.int[, "upper .95"], 3),
    p = signif(s$coefficients[, "Pr(>|z|)"], 3),
    n = nrow(d),
    events = sum(d[[event_var]] == 1L, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}

block_sem_cox_baseline <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_cox_baseline: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)

  x <- bl$exposure_var %||% "Sarcopenia"
  m1 <- bl$m1_var %||% "Depression"
  m2 <- bl$m2_var %||% "Cognitive_score"
  time_var <- bl$time_var %||% "Frailty_time"
  event_var <- bl$event_var %||% "Frailty_event"
  covs <- bl$covariate_vars %||% c("Age", "Gender")

  paths <- list(
    "Sarcopenia->Frailty" = x,
    "Depression->Frailty" = m1,
    "Cognitive->Frailty" = m2
  )
  tabs <- list()
  for (nm in names(paths)) {
    pred <- paths[[nm]]
    if (!pred %in% names(data)) next
    tab <- .sem_cox_one(data, pred, time_var, event_var, covs)
    if (!is.null(tab)) {
      tab$model <- nm
      tabs[[length(tabs) + 1L]] <- tab
    }
  }
  res <- if (length(tabs)) do.call(rbind, tabs) else data.frame(note = "no valid Cox paths")

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Cox_Baseline_Paths.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res, out, row.names = FALSE)

  ctx$results$sem_cox_baseline <- list(table = res)
  cli::cli_alert_success("SEM 基线路径 Cox 完成 ({length(tabs)} 条路径)")
  ctx
}

register_block("sem_cox_baseline", block_sem_cox_baseline, "肌少症/抑郁/认知→衰弱 Cox")
