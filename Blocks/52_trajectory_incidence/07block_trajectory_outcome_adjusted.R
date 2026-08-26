###############################################################################
#  trajectory_outcome_adjusted — AKD logistic + 死亡 Cox 全协变量调整
###############################################################################

block_trajectory_outcome_adjusted <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !"trajectory_class" %in% names(data))
    stop("trajectory_outcome_adjusted: 缺少 trajectory_class", call. = FALSE)

  covars <- bl$outcome_covariates %||% c(
    "Age", "Gender", "baseline_creatinine", "SOFA"
  )
  covars <- intersect(covars, names(data))
  adj_rhs <- if (length(covars)) paste(c("+", paste(covars, collapse = " + ")), collapse = " ") else ""

  outcomes <- bl$outcome_vars %||% c("AKD", "Mortality_7d", "Mortality_28d")
  rows <- list()

  for (oc in intersect(outcomes, names(data))) {
    if (oc == "AKD") {
      y <- as.integer(as.numeric(data[[oc]]) >= 1)
      fml <- stats::as.formula(paste("y ~ trajectory_class", adj_rhs))
      fit <- tryCatch(stats::glm(fml, data = cbind(data, y = y), family = stats::binomial()), error = function(e) NULL)
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        for (i in seq_len(nrow(sm))) {
          if (rownames(sm)[i] == "(Intercept)") next
          rows[[length(rows) + 1L]] <- data.frame(
            outcome = oc, term = rownames(sm)[i],
            estimate = sm[i, 1], OR = exp(sm[i, 1]), p = sm[i, 4],
            model = "logistic_adjusted", stringsAsFactors = FALSE
          )
        }
      }
    }
    if (oc %in% c("Mortality_7d", "Mortality_28d") && all(c("futime", oc) %in% names(data)) &&
        requireNamespace("survival", quietly = TRUE)) {
      fml <- stats::as.formula(paste(
        "survival::Surv(futime, as.integer(data[[oc]])) ~ trajectory_class", adj_rhs
      ))
      cfit <- tryCatch(survival::coxph(fml, data = data), error = function(e) NULL)
      if (!is.null(cfit)) {
        sm <- summary(cfit)$coefficients
        for (i in seq_len(nrow(sm))) {
          rows[[length(rows) + 1L]] <- data.frame(
            outcome = oc, term = rownames(sm)[i],
            estimate = sm[i, 1], OR = exp(sm[i, 1]), p = sm[i, 5],
            model = "cox_adjusted", stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no results")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Trajectory_Outcomes_Adjusted.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$trajectory_outcome_adjusted <- tab
  cli::cli_alert_success("全协变量调整结局模型完成（协变量: {paste(covars, collapse=', ')}）")
  ctx
}

register_block("trajectory_outcome_adjusted", block_trajectory_outcome_adjusted,
               "轨迹类结局全协变量调整")
