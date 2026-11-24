###############################################################################
#  cftraj_multinomial — CircS -> 轨迹类 multinomial logistic OR/CI
#  文献: Ma 2026 Alzheimers Dement
###############################################################################

block_cftraj_multinomial <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_multinomial: 无数据", call. = FALSE)

  domains <- list(
    global = list(y = "trajectory_class_label_global", y_fallback = "trajectory_class_label"),
    episodic = list(y = "trajectory_class_label_episodic", y_fallback = NULL)
  )
  all_tabs <- list()

  for (dom in names(domains)) {
    spec <- domains[[dom]]
    y_col <- spec$y
    if (!y_col %in% names(data) && !is.null(spec$y_fallback) && spec$y_fallback %in% names(data))
      y_col <- spec$y_fallback
    if (!y_col %in% names(data)) next

    treat_col <- bl$circs_binary_col %||% "CircS_high"
    if (!treat_col %in% names(data) && "CircS" %in% names(data)) {
      thr <- as.integer(bl$circs_threshold %||% 4L)
      data[[treat_col]] <- as.integer(data$CircS >= thr)
    }
    if (!treat_col %in% names(data)) stop("cftraj_multinomial: 缺少 CircS 暴露列", call. = FALSE)

    dsub <- data
    dsub[[y_col]] <- as.factor(dsub[[y_col]])
    ref <- bl$trajectory_reference %||% "high"
    if (ref %in% levels(dsub[[y_col]])) dsub[[y_col]] <- stats::relevel(dsub[[y_col]], ref = ref)

    covars <- intersect(bl$covariates %||% c("Age", "Sex", "Education"), names(dsub))
    rhs <- c(treat_col, covars)
    fml <- stats::as.formula(paste(y_col, "~", paste(rhs, collapse = " + ")))

    rows <- list()
    if (requireNamespace("nnet", quietly = TRUE)) {
      fit <- tryCatch(nnet::multinom(fml, data = dsub, trace = FALSE, maxit = 300), error = function(e) NULL)
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        se <- summary(fit)$standard.errors
        if (is.matrix(sm)) {
          for (term in rownames(sm)) {
            if (term != treat_col) next
            for (cls in colnames(sm)) {
              b <- sm[term, cls]; s <- se[term, cls]
              rows[[length(rows) + 1L]] <- data.frame(
                cognitive_domain = dom, outcome_class = cls, term = term,
                OR = exp(b), CI_lower = exp(b - 1.96 * s), CI_upper = exp(b + 1.96 * s),
                p_value = 2 * stats::pnorm(-abs(b / s)),
                model = "multinomial", stringsAsFactors = FALSE
              )
            }
          }
        }
      }
    }

    if (!length(rows)) {
      for (cls in setdiff(levels(dsub[[y_col]]), ref)) {
        d2 <- dsub; d2$y_bin <- as.integer(d2[[y_col]] == cls)
        fit2 <- tryCatch(stats::glm(stats::as.formula(paste("y_bin ~", paste(rhs, collapse = " + "))),
          data = d2, family = stats::binomial()), error = function(e) NULL)
        if (is.null(fit2)) next
        cf <- summary(fit2)$coefficients
        if (treat_col %in% rownames(cf)) {
          b <- cf[treat_col, 1]; s <- cf[treat_col, 2]
          rows[[length(rows) + 1L]] <- data.frame(
            cognitive_domain = dom, outcome_class = cls, term = treat_col,
            OR = exp(b), CI_lower = exp(b - 1.96 * s), CI_upper = exp(b + 1.96 * s),
            p_value = cf[treat_col, 4], model = "binary_vs_ref", stringsAsFactors = FALSE
          )
        }
      }
    }

    tab <- if (length(rows)) do.call(rbind, rows) else data.frame(domain = dom, note = "no results")
    all_tabs[[dom]] <- tab
    out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj")
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(tab, file.path(out_dir, paste0("Table_CfTraj_Multinomial_CircS_", dom, ".csv")), row.names = FALSE)
  }

  tab_all <- if (length(all_tabs)) do.call(rbind, all_tabs) else data.frame(note = "no results")
  utils::write.csv(tab_all, file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj", "Table_CfTraj_Multinomial_CircS.csv"), row.names = FALSE)

  ctx$results$cftraj_multinomial <- tab_all
  cli::cli_alert_success("CircS→轨迹类 multinomial 完成 ({length(all_tabs)} 域)")
  ctx
}

register_block("cftraj_multinomial", block_cftraj_multinomial, "CircS 轨迹类 multinomial OR/CI")
