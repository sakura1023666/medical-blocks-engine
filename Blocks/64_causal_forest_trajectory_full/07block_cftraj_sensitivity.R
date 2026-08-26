###############################################################################
#  cftraj_sensitivity — CircS 阈值敏感性（默认 3/4/5）
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

block_cftraj_sensitivity <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_sensitivity: 无数据", call. = FALSE)
  if (!"CircS" %in% names(data) && !"trajectory_class_label" %in% names(data))
    stop("cftraj_sensitivity: 请先运行 cftraj_circs_compute / cftraj_lcmm_fit", call. = FALSE)

  score_col <- bl$circs_score_col %||% "CircS"
  if (!score_col %in% names(data)) stop("cftraj_sensitivity: 缺少 CircS 连续计分列", call. = FALSE)

  thresholds <- as.integer(bl$sensitivity_thresholds %||% c(3L, 4L, 5L))
  y_col <- if ("trajectory_class_label" %in% names(data)) "trajectory_class_label" else "trajectory_class"
  covars <- intersect(bl$covariates %||% c("Age", "Sex", "Education"), names(data))

  rows <- list()
  for (thr in thresholds) {
    treat <- paste0("CircS_ge_", thr)
    data[[treat]] <- as.integer(suppressWarnings(as.numeric(data[[score_col]])) >= thr)
    n_high <- sum(data[[treat]] == 1L, na.rm = TRUE)
    n_low <- sum(data[[treat]] == 0L, na.rm = TRUE)

    if (y_col %in% names(data) && length(unique(data[[y_col]][!is.na(data[[y_col]])])) >= 2L) {
      d2 <- data[!is.na(data[[y_col]]) & !is.na(data[[treat]]), , drop = FALSE]
      d2[[y_col]] <- as.factor(d2[[y_col]])
      ref <- bl$trajectory_reference %||% levels(d2[[y_col]])[1L]
      if (ref %in% levels(d2[[y_col]])) d2[[y_col]] <- stats::relevel(d2[[y_col]], ref = ref)
      rhs <- c(treat, covars)
      if (requireNamespace("nnet", quietly = TRUE)) {
        fit <- tryCatch(
          nnet::multinom(stats::as.formula(paste(y_col, "~", paste(rhs, collapse = " + "))),
            data = d2, trace = FALSE, maxit = 200),
          error = function(e) NULL
        )
        if (!is.null(fit)) {
          sm <- summary(fit)$coefficients
          se <- summary(fit)$standard.errors
          if (is.matrix(sm) && treat %in% rownames(sm)) {
            for (cls in colnames(sm)) {
              b <- sm[treat, cls]; s <- se[treat, cls]
              rows[[length(rows) + 1L]] <- data.frame(
                circs_threshold = thr, outcome_class = cls, term = treat,
                OR = exp(b), CI_lower = exp(b - 1.96 * s), CI_upper = exp(b + 1.96 * s),
                p_value = 2 * stats::pnorm(-abs(b / s)),
                n_high = n_high, n_low = n_low, model = "multinomial",
                stringsAsFactors = FALSE
              )
            }
          }
        }
      }
      if (!any(vapply(rows, function(r) identical(r$circs_threshold, thr), logical(1)))) {
        for (cls in setdiff(levels(d2[[y_col]]), ref)) {
          d3 <- d2
          d3$y_bin <- as.integer(d3[[y_col]] == cls)
          fit2 <- tryCatch(
            stats::glm(stats::as.formula(paste("y_bin ~", paste(rhs, collapse = " + "))),
              data = d3, family = stats::binomial()),
            error = function(e) NULL
          )
          if (is.null(fit2)) next
          cf <- summary(fit2)$coefficients
          if (treat %in% rownames(cf)) {
            b <- cf[treat, 1]; s <- cf[treat, 2]
            rows[[length(rows) + 1L]] <- data.frame(
              circs_threshold = thr, outcome_class = cls, term = treat,
              OR = exp(b), CI_lower = exp(b - 1.96 * s), CI_upper = exp(b + 1.96 * s),
              p_value = cf[treat, 4],
              n_high = n_high, n_low = n_low, model = "binary_vs_ref",
              stringsAsFactors = FALSE
            )
          }
        }
      }
    } else {
      rows[[length(rows) + 1L]] <- data.frame(
        circs_threshold = thr, outcome_class = NA_character_, term = treat,
        OR = NA_real_, CI_lower = NA_real_, CI_upper = NA_real_, p_value = NA_real_,
        n_high = n_high, n_low = n_low, model = "descriptive_only",
        stringsAsFactors = FALSE
      )
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no results")
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_CfTraj_Sensitivity_CircS_Threshold.csv"), row.names = FALSE)

  ctx$results$cftraj_sensitivity <- tab
  cli::cli_alert_success("CircS 阈值敏感性分析完成")
  ctx
}

register_block("cftraj_sensitivity", block_cftraj_sensitivity, "CircS 阈值敏感性 3/4/5")
