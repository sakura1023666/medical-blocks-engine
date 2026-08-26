###############################################################################
#  markov_sensitivity_glmm — GLMM 敏感性 + FDR（Ren 2025 原文）
###############################################################################

block_markov_sensitivity_glmm <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("markov_sensitivity_glmm: 无数据", call. = FALSE)

  mmse_col <- bl$mmse_col %||% "MMSE"
  apoe_col <- bl$apoe_col %||% "APOE_carrier"
  life_col <- bl$lifestyle_col %||% "Healthy_lifestyle"
  id_col <- bl$id_col %||% "ID"

  d <- data
  d$CI_binary <- as.integer(suppressWarnings(as.numeric(d[[mmse_col]])) < (bl$ci_cutoff %||% 18L))
  d$MMSE_cont <- suppressWarnings(as.numeric(d[[mmse_col]]))

  rows <- list()
  if (requireNamespace("lme4", quietly = TRUE)) {
    tryCatch({
      f1 <- stats::as.formula(paste("CI_binary ~", life_col, "*", apoe_col, "+ (1|", id_col, ")"))
      m1 <- lme4::glmer(f1, data = d, family = stats::binomial(), control = lme4::glmerControl(optimizer = "bobyqa"))
      cf1 <- summary(m1)$coefficients
      for (rn in rownames(cf1)) {
        rows[[length(rows) + 1L]] <- data.frame(
          model = "GLMM_CI_binary", term = rn, estimate = cf1[rn, 1], se = cf1[rn, 2], p_value = cf1[rn, 4],
          stringsAsFactors = FALSE
        )
      }
      f2 <- stats::as.formula(paste("MMSE_cont ~", life_col, "*", apoe_col, "+ (1|", id_col, ")"))
      m2 <- lme4::lmer(f2, data = d)
      cf2 <- summary(m2)$coefficients
      for (rn in rownames(cf2)) {
        rows[[length(rows) + 1L]] <- data.frame(
          model = "GLMM_MMSE_continuous", term = rn, estimate = cf2[rn, 1], se = cf2[rn, 2],
          p_value = cf2[rn, 4], stringsAsFactors = FALSE
        )
      }
    }, error = function(e) cli::cli_alert_warning("GLMM: {e$message}"))
  }

  out_df <- if (length(rows)) do.call(rbind, rows) else data.frame()
  if (nrow(out_df) && requireNamespace("stats", quietly = TRUE)) {
    out_df$p_fdr <- stats::p.adjust(out_df$p_value, method = "BH")
  }

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(out_df, file.path(out_dir, "Table_Markov_Sensitivity_GLMM.csv"), row.names = FALSE)

  ctx$results$markov_sensitivity_glmm <- out_df
  cli::cli_alert_success("Markov GLMM 敏感性分析完成")
  ctx
}

register_block("markov_sensitivity_glmm", block_markov_sensitivity_glmm, "Markov GLMM 敏感性")
