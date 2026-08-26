###############################################################################
#  sem_stratified — 按肌少症状态分层 Cox（抑郁/认知 → 衰弱）
#  文献: Zhu 2025 J Adv Research
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

block_sem_stratified <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_stratified: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)

  strata_col <- bl$exposure_var %||% "Sarcopenia"
  time_var <- bl$time_var %||% "Frailty_time"
  event_var <- bl$event_var %||% "Frailty_event"
  preds <- c(bl$m1_var %||% "Depression", bl$m2_var %||% "Cognitive_score")
  covs <- bl$covariate_vars %||% c("Age", "Gender")

  if (!strata_col %in% names(data)) {
    cli::cli_alert_warning("sem_stratified: 缺少分层列")
    return(ctx)
  }

  strata_vals <- unique(data[[strata_col]])
  rows <- list()
  for (sv in strata_vals) {
    sub <- data[data[[strata_col]] == sv, , drop = FALSE]
    if (nrow(sub) < 20L) next
    stratum_lbl <- if (is.numeric(sv)) ifelse(sv == 1L, "Sarcopenia", "Non_sarcopenia") else as.character(sv)
    for (pred in preds) {
      if (!pred %in% names(sub)) next
      adj <- setdiff(intersect(covs, names(sub)), pred)
      rhs <- paste(c(pred, adj), collapse = " + ")
      fit <- tryCatch(
        survival::coxph(
          stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs)),
          data = sub
        ),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      s <- summary(fit)
      rows[[length(rows) + 1L]] <- data.frame(
        stratum = stratum_lbl,
        predictor = pred,
        n = nrow(sub),
        events = sum(sub[[event_var]] == 1L, na.rm = TRUE),
        HR = round(s$conf.int[pred, "exp(coef)"], 3),
        lower = round(s$conf.int[pred, "lower .95"], 3),
        upper = round(s$conf.int[pred, "upper .95"], 3),
        p = signif(s$coefficients[pred, "Pr(>|z|)"], 3),
        stringsAsFactors = FALSE
      )
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no stratified results")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Stratified_Cox.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$results$sem_stratified <- list(table = tab)
  cli::cli_alert_success("肌少症分层 Cox 完成")
  ctx
}

register_block("sem_stratified", block_sem_stratified, "肌少症分层 Cox")
