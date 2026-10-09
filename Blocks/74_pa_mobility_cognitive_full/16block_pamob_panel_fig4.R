###############################################################################
# pamob_panel_fig4 — Figure 4：正文大样本 DSST；sNfL 标 Exploratory 副面板
###############################################################################

block_pamob_panel_fig4 <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages(c("survey", "ggplot2", "patchwork"))
  bl <- pamob_cfg(ctx)
  d_ds <- ctx$results$pamob_svy_dsst$data %||% ctx$data$pamob_nhanes_dsst
  d_nf <- ctx$results$pamob_svy_nfl$data %||% ctx$data$pamob_nhanes_nfl
  if (is.null(d_ds)) stop("pamob_panel_fig4: 请先跑 pamob_svy_dsst", call. = FALSE)

  cov_ds <- pamob_resolve_covars(
    d_ds, bl$nhanes_covariates_model3 %||% bl$covariates_model3 %||% character(0)
  )
  wt_ds <- if ("WT_USE" %in% names(d_ds)) "WT_USE" else "WTMEC2YR"
  m1 <- pamob_svy_adjusted_means(d_ds, "CFDDS", wt_ds, cov_ds)
  m1$panel <- sprintf("DSST (main, n=%d)", nrow(d_ds))

  plot_df <- m1
  if (!is.null(d_nf) && nrow(d_nf)) {
    cov_nf <- unique(c(
      pamob_resolve_covars(d_nf, bl$nhanes_covariates_model3 %||% bl$covariates_model3 %||% character(0)),
      pamob_resolve_covars(d_nf, "eGFR")
    ))
    m2 <- pamob_svy_adjusted_means(d_nf, "ln_SSSNFL", "WTSSNH2Y", cov_nf)
    m2$se <- exp(m2$mean) * m2$se
    m2$mean <- exp(m2$mean)
    m2$panel <- sprintf("sNfL geometric mean (exploratory, n=%d)", nrow(d_nf))
    plot_df <- rbind(m1, m2)
  }
  plot_df$phenotype <- factor(plot_df$phenotype, levels = unname(pamob_phenotype_labels()))

  fig <- pamob_figures_dir(ctx)
  pdf_path <- file.path(fig, "Figure 4. NHANES DSST and NfL panel.pdf")
  pamob_draw_fig4_panel(plot_df, pdf_path)
  pamob_write_csv(plot_df, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_Fig4_Means.csv"))
  ctx$results$pamob_panel_fig4 <- list(means = plot_df, adjusted = TRUE, dsst_main = TRUE)
  cli::cli_alert_success("Figure 4 (DSST main + exploratory sNfL)")
  ctx
}

register_block("pamob_panel_fig4", block_pamob_panel_fig4, "Figure 4 panel")
