###############################################################################
#  trajectory_outcome_models — 轨迹类 × AKD（logistic）/ 死亡（Cox）
###############################################################################

block_trajectory_outcome_models <- function(ctx, ...) {
  bl <- ctx$config$trajectory %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("trajectory_outcome_models: 无数据", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  data <- literature_ensure_id_column(data, id_col)
  if (!"trajectory_class" %in% names(data))
    stop("trajectory_outcome_models: 缺少 trajectory_class", call. = FALSE)

  outcomes <- bl$outcome_vars %||% c("AKD", "Mortality_28d")
  rows <- list()
  for (oc in intersect(outcomes, names(data))) {
    y <- as.integer(as.numeric(data[[oc]]) >= 1)
    fit <- tryCatch(
      stats::glm(y ~ trajectory_class, data = data, family = stats::binomial()),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      sm <- summary(fit)$coefficients
      for (i in seq_len(nrow(sm))) {
        if (rownames(sm)[i] == "(Intercept)") next
        rows[[length(rows) + 1L]] <- data.frame(
          outcome = oc, term = rownames(sm)[i],
          OR = exp(sm[i, 1]), p = sm[i, 4], model = "logistic",
          stringsAsFactors = FALSE
        )
      }
    }
    if (oc %in% c("Mortality_28d", "Mortality_7d") &&
        all(c("futime", oc) %in% names(data)) && requireNamespace("survival", quietly = TRUE)) {
      cfit <- tryCatch(
        survival::coxph(survival::Surv(futime, as.integer(data[[oc]])) ~ trajectory_class, data = data),
        error = function(e) NULL
      )
      if (!is.null(cfit)) {
        sm <- summary(cfit)$coefficients
        for (i in seq_len(nrow(sm))) {
          rows[[length(rows) + 1L]] <- data.frame(
            outcome = oc, term = rownames(sm)[i],
            OR = exp(sm[i, 1]), p = sm[i, 5], model = "cox",
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no results")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Trajectory_Outcomes.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$trajectory_outcome_models <- tab
  cli::cli_alert_success("轨迹结局模型完成")
  ctx
}

register_block("trajectory_outcome_models", block_trajectory_outcome_models, "轨迹类结局 logistic/Cox")
