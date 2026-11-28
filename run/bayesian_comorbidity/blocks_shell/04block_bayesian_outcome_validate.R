###############################################################################
#  bayesian_outcome_validate — Body Clock 预测残疾/步速/死亡（文献验证层）
###############################################################################

block_bayesian_outcome_validate <- function(ctx, ...) {
  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !"Body_Clock" %in% names(data))
    stop("bayesian_outcome_validate: 缺少 Body_Clock", call. = FALSE)

  outcomes <- bl$outcome_cols %||% c("Disability", "Walk_speed", "Mortality")
  outcomes <- intersect(outcomes, names(data))
  rows <- list()
  for (oc in outcomes) {
    y <- data[[oc]]
    if (is.numeric(y) && length(unique(y[!is.na(y)])) > 5) {
      fit <- tryCatch(stats::lm(stats::as.formula(paste(oc, "~ Body_Clock")), data = data),
                      error = function(e) NULL)
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        rows[[length(rows) + 1L]] <- data.frame(
          outcome = oc, model = "lm", beta = sm[2, 1], p = sm[2, 4],
          stringsAsFactors = FALSE
        )
      }
    } else {
      y01 <- as.integer(as.numeric(y) >= 1)
      fit <- tryCatch(stats::glm(y01 ~ Body_Clock, data = data, family = stats::binomial()),
                      error = function(e) NULL)
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        rows[[length(rows) + 1L]] <- data.frame(
          outcome = oc, model = "logistic", beta = sm[2, 1], p = sm[2, 4],
          stringsAsFactors = FALSE
        )
      }
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no outcomes")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Body_Clock_Outcomes.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$bayesian_outcome_validate <- tab
  cli::cli_alert_success("Body Clock 结局验证完成（{nrow(tab)} 个结局）")
  ctx
}

register_block("bayesian_outcome_validate", block_bayesian_outcome_validate, "Body Clock 结局验证")
