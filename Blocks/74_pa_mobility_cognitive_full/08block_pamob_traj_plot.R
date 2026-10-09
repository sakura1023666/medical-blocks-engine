###############################################################################
# pamob_traj_plot — Figure 3 双面板：Global + Episodic（含 95%CI）
###############################################################################

block_pamob_traj_plot <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  pamob_ensure_packages(c("lme4", "lmerTest", "ggplot2", "patchwork"))
  long0 <- ctx$data$pamob_lmm_fit_data %||% ctx$data$pamob_charls_long
  if (is.null(long0)) stop("pamob_traj_plot: 无数据", call. = FALSE)
  bl <- pamob_cfg(ctx)
  covs <- pamob_resolve_covars(long0, bl$covariates_model3 %||% character(0))

  .pred_grid <- function(long, outcome) {
    long <- long[!is.na(long[[outcome]]) & !is.na(long$phenotype) & !is.na(long$Time_years), ,
                 drop = FALSE]
    long$phenotype <- relevel(factor(long$phenotype, levels = unname(pamob_phenotype_labels())),
                               ref = "Active_preserved")
    rhs <- paste(c("Time_years * phenotype", covs), collapse = " + ")
    fml <- stats::as.formula(paste(outcome, "~", rhs, "+ (1 | ID_h)"))
    fit <- lmerTest::lmer(fml, data = long, REML = TRUE)
    grid <- expand.grid(
      Time_years = seq(0, max(long$Time_years, na.rm = TRUE), by = 1),
      phenotype = levels(long$phenotype),
      stringsAsFactors = FALSE
    )
    grid$phenotype <- factor(grid$phenotype, levels = levels(long$phenotype))
    grid$ID_h <- long$ID_h[1L]
    for (cv in covs) {
      v <- long[[cv]]
      if (is.numeric(v)) {
        grid[[cv]] <- mean(v, na.rm = TRUE)
      } else {
        tb <- sort(table(as.character(v)), decreasing = TRUE)
        grid[[cv]] <- if (length(tb)) names(tb)[1L] else NA
        if (is.factor(v)) grid[[cv]] <- factor(grid[[cv]], levels = levels(v))
      }
    }
    # 固定效应预测 + SE → 95% CI
    mm <- stats::model.matrix(stats::delete.response(stats::terms(fit)), grid)
    beta <- as.numeric(lme4::fixef(fit))
    # 对齐列
    common <- intersect(colnames(mm), names(beta))
    if (!length(common)) common <- intersect(colnames(mm), names(lme4::fixef(fit)))
    b <- lme4::fixef(fit)
    mm2 <- matrix(0, nrow = nrow(mm), ncol = length(b), dimnames = list(NULL, names(b)))
    for (nm in names(b)) {
      if (nm %in% colnames(mm)) mm2[, nm] <- mm[, nm]
    }
    grid$pred <- as.numeric(mm2 %*% b)
    vc <- as.matrix(stats::vcov(fit))
    # vcov 行名可能带空格
    vc <- vc[names(b), names(b), drop = FALSE]
    grid$se <- sqrt(pmax(0, diag(mm2 %*% vc %*% t(mm2))))
    grid$lo <- grid$pred - 1.96 * grid$se
    grid$hi <- grid$pred + 1.96 * grid$se
    grid$outcome <- outcome
    grid$n_ids <- length(unique(long$ID_h))
    grid$n_obs <- nrow(long)
    grid
  }

  g_global <- .pred_grid(long0, "Global_cognition")
  g_epi <- .pred_grid(long0, "Episodic_memory")
  grid <- rbind(g_global, g_epi)

  fig_dir <- pamob_figures_dir(ctx)
  pdf_path <- file.path(fig_dir, "Figure 3. CHARLS cognitive trajectories.pdf")
  pamob_draw_fig3_traj_dual(grid, pdf_path)
  pamob_write_csv(grid, file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_Pamob_Predicted_Trajectories.csv"))
  ctx$results$pamob_traj_plot <- list(path = pdf_path, grid = grid)
  cli::cli_alert_success("Figure 3 dual-panel trajectories (global + episodic, 95% CI)")
  ctx
}

register_block("pamob_traj_plot", block_pamob_traj_plot, "Figure 3 trajectories")
