###############################################################################
#  competing_pub_export — 文献级 Figure 1–9 + Table 1–4 + 清理废图
###############################################################################

block_competing_pub_export <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  cfg <- ctx$config
  root <- cfg$project$root %||% getwd()
  if (!exists(".competing_pub_forest_lai", mode = "function")) {
    source(file.path(root, "R/competing_risk_pub.R"), local = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_pub_export: 无数据", call. = FALSE)
  index_var <- bl$index_var %||% "TyG"
  time_var <- bl$time_var %||% "competing_time_28d"
  event_col <- bl$event_type_col %||% "competing_status_28d"
  exp_var <- bl$exposure_var %||% paste0(index_var, "_quartile")
  traj_var <- bl$trajectory_var %||% paste0(index_var, "_trajectory")
  primary <- as.integer(bl$primary_cause %||% 1L)[1L]
  death <- as.integer(bl$death_cause %||% 2L)[1L]
  horizon <- as.numeric(bl$cif_horizon %||% bl$followup_days %||% 28)[1L]
  horizons <- as.integer(bl$model_horizons %||% c(7L, 14L, 28L))
  db <- .competing_pub_db(cfg)
  footnote_dual <- .competing_cov_footnote(ctx, dual_section = TRUE)
  footnote_single <- .competing_cov_footnote(ctx, dual_section = FALSE)
  # 死亡双模型：全因死亡主推断为 cause-specific Cox；Fine-Gray 仅作补充 CIF
  if (isTRUE(bl$discharge_as_censor %||% FALSE)) {
    footnote_mortality_dual <- paste0(
      footnote_dual,
      " | Mortality primary: cause-specific Cox (M4-6; AKI/discharge censored). ",
      "Fine-Gray (M1-3) is supplementary CIF with death as failcode; ",
      "competing event for AKI primary = death only (discharge censored)."
    )
  } else {
    footnote_mortality_dual <- paste0(
      footnote_dual,
      " | Mortality primary: cause-specific Cox (M4-6; non-death censored). ",
      "Fine-Gray (M1-3) supplementary; HRs may reverse when discharge differs by group."
    )
  }
  covs_m3 <- ctx$results$competing_model_covs$m3 %||% character(0)

  out_root <- cfg$project$output_dir %||% "Output"
  tab_dir <- file.path(out_root, "Tables")
  fig_dir <- file.path(out_root, "Figures")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  # ---- Tables 1/3：SCI 三线（优先用 block 结果重写，避免被扁平 csv 覆盖）----
  t1 <- ctx$results$competing_baseline_quartile$table
  if (!is.null(t1) && nrow(t1)) {
    .competing_pub_write_xlsx(
      t1,
      file.path(tab_dir, sprintf("Table 1-%s. Baseline characteristics by %s quartile.xlsx", db, index_var)),
      title = sprintf("Table 1-%s. Baseline characteristics by %s quartile", db, index_var)
    )
  }
  t3 <- ctx$results$competing_baseline_trajectory$table
  if (!is.null(t3) && nrow(t3)) {
    .competing_pub_write_xlsx(
      t3,
      file.path(tab_dir, sprintf("Table 3-%s. Baseline characteristics by %s trajectory.xlsx", db, index_var)),
      title = sprintf("Table 3-%s. Baseline characteristics by %s trajectory", db, index_var)
    )
  }

  # ---- Tables 2/4：7/14/28-day Overall mortality (%) + P ----
  if (exp_var %in% names(data)) {
    .competing_write_cif_mortality_xlsx(
      file.path(tab_dir, sprintf("Table 2-%s. CIF of mortality by %s quartile.xlsx", db, index_var)),
      data, time_var, event_col, exp_var, death,
      horizons = horizons,
      title = sprintf("Table 2-%s. CIF of mortality by %s quartile", db, index_var)
    )
  }
  if (traj_var %in% names(data)) {
    .competing_write_cif_mortality_xlsx(
      file.path(tab_dir, sprintf("Table 4-%s. CIF of mortality by %s trajectory.xlsx", db, index_var)),
      data, time_var, event_col, traj_var, death,
      horizons = horizons,
      title = sprintf("Table 4-%s. CIF of mortality by %s trajectory", db, index_var)
    )
  }

  # Table S1：优先从 imputation 步骤原件复制，禁止二次扁平改写
  s1_dst <- file.path(tab_dir, sprintf(
    "Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db
  ))
  s1_src <- c(
    list.files(file.path(out_root, "step06_imputation", "Tables"),
               pattern = "Table S1.*before and after multiple imputation\\.xlsx$",
               full.names = TRUE, ignore.case = TRUE),
    list.files(file.path(dirname(out_root), "step06_imputation", "Tables"),
               pattern = "Table S1.*before and after multiple imputation\\.xlsx$",
               full.names = TRUE, ignore.case = TRUE),
    list.files(tab_dir, pattern = "Table S1.*before and after multiple imputation\\.xlsx$",
               full.names = TRUE, ignore.case = TRUE)
  )
  s1_src <- s1_src[file.exists(s1_src)]
  # 选体积最大的原件（插补块 SCI 原件通常更大且无二次表头）
  if (length(s1_src)) {
    s1_pick <- s1_src[which.max(file.info(s1_src)$size)]
    if (!identical(normalizePath(s1_pick, mustWork = FALSE),
                   normalizePath(s1_dst, mustWork = FALSE))) {
      file.copy(s1_pick, s1_dst, overwrite = TRUE)
    }
  }

  # ---- Figure 1 ----
  fig1 <- file.path(fig_dir, sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db))
  src_fc <- file.path(fig_dir, "Fig1_Flowchart_raw.pdf")
  if (file.exists(src_fc)) {
    if (!identical(normalizePath(src_fc, mustWork = FALSE), normalizePath(fig1, mustWork = FALSE)))
      file.copy(src_fc, fig1, overwrite = TRUE)
  }

  m123 <- ctx$results$competing_models_123$table
  m123d <- ctx$results$competing_models_123_death$table
  m123_tr <- ctx$results$competing_models_123_trajectory$table
  m123d_tr <- ctx$results$competing_models_123_death_trajectory$table

  primary_lbl <- as.character(bl$primary_event_label %||% "diabetes")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "diabetes"

  # Fig2 primary-event quartile Competing M1-3
  .competing_pub_forest_lai(
    m123,
    sprintf("Figure 2-%s. Association of %s quartile with %s", db, index_var, primary_lbl),
    file.path(fig_dir, sprintf("Figure 2-%s. Association of %s quartile with %s.pdf", db, index_var, primary_lbl)),
    horizons = horizons, dual_section = FALSE, footnote = footnote_single
  )

  # Fig3 RCS 2x3：单一规范文件名（含主事件+死亡），不再复制「for AKI」歧义副本
  fig3_path <- file.path(
    fig_dir,
    sprintf("Figure 3-%s. RCS dose-response of %s for %s and mortality.pdf",
            db, index_var, primary_lbl)
  )
  .competing_pub_rcs_grid(
    data, index_var, time_var, event_col, primary, death, horizons, covs_m3,
    sprintf("Figure 3-%s. RCS dose-response of %s", db, index_var),
    fig3_path,
    primary_lab = primary_lbl
  )
  # 清理历史歧义/重复 Figure 3
  old_fig3 <- list.files(
    fig_dir,
    pattern = sprintf("^Figure 3-%s\\. RCS dose-response of %s", db, index_var),
    full.names = TRUE
  )
  old_fig3 <- setdiff(normalizePath(old_fig3, mustWork = FALSE),
                      normalizePath(fig3_path, mustWork = FALSE))
  if (length(old_fig3)) unlink(old_fig3)

  # Fig4 CIF + risk table
  if (exp_var %in% names(data)) {
    tryCatch(
      .competing_pub_cif_with_risk_table(
        data, time_var, event_col, exp_var, death, horizon,
        sprintf("Figure 4-%s. CIF of mortality by %s quartile", db, index_var),
        file.path(fig_dir, sprintf("Figure 4-%s. CIF of mortality by %s quartile.pdf", db, index_var))
      ),
      error = function(e) cli::cli_alert_warning("Fig4 failed: {e$message}")
    )
  }

  # Fig5 mortality quartile dual
  tryCatch(
    .competing_pub_forest_lai(
      m123d,
      sprintf("Figure 5-%s. Association of %s quartile with mortality", db, index_var),
      file.path(fig_dir, sprintf("Figure 5-%s. Association of %s quartile with mortality.pdf", db, index_var)),
      horizons = horizons, dual_section = TRUE, footnote = footnote_mortality_dual
    ),
    error = function(e) cli::cli_alert_warning("Fig5 failed: {e$message}")
  )

  # Fig6 trajectory curves
  long <- ctx$results$competing_index_long$long
  traj_info <- ctx$results$competing_trajectory_class %||% list()
  fig6 <- file.path(fig_dir, sprintf("Figure 6-%s. Trajectory of %s.pdf", db, index_var))
  tryCatch({
    pdf(fig6, width = 7.5, height = 5.5)
    if (!is.null(long) && nrow(long) && traj_var %in% names(data)) {
      id_col <- ctx$results$competing_index_long$id_col %||% (cfg$data$id_column %||% "ID")
      val_col <- if ("value" %in% names(long)) "value" else index_var
      m <- unique(data[, c(id_col, traj_var), drop = FALSE])
      long2 <- merge(long, m, by = id_col, all.x = TRUE)
      long2 <- long2[!is.na(long2[[traj_var]]) & is.finite(long2[[val_col]]), , drop = FALSE]
      groups <- levels(factor(long2[[traj_var]]))
      cols <- grDevices::hcl.colors(max(1L, length(groups)), "Dark 3")
      # 先算各组日均曲线，纵轴自适应到曲线范围（而非个体极端值），避免均值线被压平
      agg_list <- lapply(groups, function(g) {
        sub <- long2[long2[[traj_var]] == g, , drop = FALSE]
        if (!nrow(sub)) return(NULL)
        stats::aggregate(sub[[val_col]], by = list(day = sub$day), FUN = mean, na.rm = TRUE)
      })
      names(agg_list) <- groups
      curve_vals <- unlist(lapply(agg_list, function(a) if (is.null(a)) NULL else a$x), use.names = FALSE)
      yr <- range(curve_vals, na.rm = TRUE)
      if (!all(is.finite(yr)) || diff(yr) == 0) yr <- range(long2[[val_col]], na.rm = TRUE)
      if (!all(is.finite(yr)) || diff(yr) == 0) yr <- c(0, 1)
      pad <- diff(yr) * 0.08
      yr <- c(yr[1] - pad, yr[2] + pad)
      xr <- range(long2$day, na.rm = TRUE)
      if (!all(is.finite(xr))) xr <- c(1, 28)
      plot(1, type = "n", xlim = xr, ylim = yr,
           xlab = "Day", ylab = index_var,
           main = sprintf("Figure 6-%s. Trajectory of %s (K=%s)", db, index_var,
                          traj_info$optimal_K %||% length(groups)))
      for (i in seq_along(groups)) {
        agg <- agg_list[[i]]
        if (is.null(agg) || !nrow(agg)) next
        lines(agg$day, agg$x, col = cols[i], lwd = 2)
      }
      legend("topright", legend = groups, col = cols, lty = 1, lwd = 2, bty = "n")
    } else {
      plot.new(); title(main = "Figure 6 (no trajectory data)")
    }
    dev.off()
  }, error = function(e) {
    if (dev.cur() > 1) try(dev.off(), silent = TRUE)
    cli::cli_alert_warning("Fig6 failed: {e$message}")
  })

  # Fig7 primary-event trajectory
  tryCatch(
    .competing_pub_forest_lai(
      m123_tr %||% m123,
      sprintf("Figure 7-%s. Association of %s trajectory with %s", db, index_var, primary_lbl),
      file.path(fig_dir, sprintf("Figure 7-%s. Association of %s trajectory with %s.pdf", db, index_var, primary_lbl)),
      horizons = horizons, term_pat = "T[2-9]|Stable|Increasing",
      dual_section = FALSE, footnote = footnote_single
    ),
    error = function(e) cli::cli_alert_warning("Fig7 failed: {e$message}")
  )

  # Fig8
  if (traj_var %in% names(data)) {
    tryCatch(
      .competing_pub_cif_with_risk_table(
        data, time_var, event_col, traj_var, death, horizon,
        sprintf("Figure 8-%s. CIF of mortality by %s trajectory", db, index_var),
        file.path(fig_dir, sprintf("Figure 8-%s. CIF of mortality by %s trajectory.pdf", db, index_var))
      ),
      error = function(e) cli::cli_alert_warning("Fig8 failed: {e$message}")
    )
  }

  # Fig9 mortality trajectory dual M1-6
  tryCatch(
    .competing_pub_forest_lai(
      m123d_tr %||% m123d,
      sprintf("Figure 9-%s. Association of %s trajectory with mortality", db, index_var),
      file.path(fig_dir, sprintf("Figure 9-%s. Association of %s trajectory with mortality.pdf", db, index_var)),
      horizons = horizons, term_pat = "T[2-9]|Stable|Increasing",
      dual_section = TRUE, footnote = footnote_mortality_dual
    ),
    error = function(e) cli::cli_alert_warning("Fig9 failed: {e$message}")
  )

  # 补充缺失图
  miss_cands <- list.files(fig_dir, pattern = "Missing|missing", full.names = TRUE)
  if (length(miss_cands)) {
    dst <- file.path(fig_dir, sprintf("Figure S1-%s. Missing value overview.pdf", db))
    src_n <- normalizePath(miss_cands[1], mustWork = FALSE)
    if (!identical(src_n, normalizePath(dst, mustWork = FALSE)))
      file.copy(miss_cands[1], dst, overwrite = TRUE)
  }

  # 清理非文献命名图
  junk <- list.files(fig_dir, full.names = TRUE)
  keep <- grepl("^Figure [0-9]+-", basename(junk)) | grepl("^Figure S[0-9]+-", basename(junk))
  unlink(junk[!keep])

  figs <- sort(list.files(fig_dir, pattern = "^Figure [0-9S]", full.names = FALSE))
  tabs <- sort(list.files(tab_dir, pattern = "^(Table |Supplementary Material )", full.names = FALSE))
  tabs <- tabs[file.exists(file.path(tab_dir, tabs)) & !dir.exists(file.path(tab_dir, tabs))]
  utils::write.csv(
    data.frame(type = c(rep("Figure", length(figs)), rep("Table", length(tabs))), file = c(figs, tabs)),
    file.path(tab_dir, "00_Literature_Output_Manifest.csv"), row.names = FALSE
  )

  # 写出协变量说明（发表版；调试信息另存）
  writeLines(
    c(footnote_dual,
      sprintf("trajectory: method=%s; optimal_K=%s; labels=%s",
              traj_info$method %||% "NA",
              traj_info$optimal_K %||% "NA",
              paste(traj_info$labels %||% character(0), collapse = ", "))),
    file.path(tab_dir, "00_Model_Covariates.txt")
  )
  dbg <- ctx$results$competing_model_covs$footnote_debug %||% ""
  if (nzchar(as.character(dbg)[1L])) {
    writeLines(
      as.character(dbg),
      file.path(tab_dir, "00_Model_Covariates_debug.txt")
    )
  }

  ctx$results$competing_pub_export <- list(
    figures = figs, tables = tabs,
    footnote = footnote_dual, footnote_single = footnote_single
  )

  # 多库：根 Figures 仍有 -DB 成对 PDF 时先拼图，再四目录发表导出
  pdfs_tagged <- list.files(fig_dir, pattern = "\\.pdf$", ignore.case = TRUE)
  per_db_pat <- "-[A-Za-z0-9_]+\\."
  dbs_have <- character(0)
  if (length(pdfs_tagged) && any(grepl(per_db_pat, pdfs_tagged, perl = TRUE))) {
    tags <- regmatches(pdfs_tagged, gregexpr(per_db_pat, pdfs_tagged, perl = TRUE))
    dbs_have <- unique(unlist(lapply(tags, function(x) sub("^-(.*)\\.$", "\\1", x))))
    dbs_have <- dbs_have[nzchar(dbs_have)]
  }
  combined_flag <- length(dbs_have) >= 2L
  if (combined_flag) {
    if (!exists("dual_db_combine_paired_figures", mode = "function")) {
      comb_src <- file.path(root, "R/dual_db_combine_figures.R")
      if (file.exists(comb_src)) source(comb_src, local = FALSE)
    }
    if (exists("dual_db_combine_paired_figures", mode = "function")) {
      tryCatch(
        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
        error = function(e) cli::cli_alert_warning("竞争风险拼图跳过: {e$message}")
      )
    }
  }

  if (!exists("export_pub_figures", mode = "function")) {
    src <- file.path(root, "R/pub_figure_export.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (exists("export_pub_figures", mode = "function")) {
    tryCatch(
      export_pub_figures(
        fig_dir,
        meta = list(
          exposure = cfg$project$exposure_var %||% "",
          outcome = cfg$data$outcome_column %||% "",
          databases = if (combined_flag) dbs_have else (cfg$project$database %||% character(0)),
          combined = combined_flag
        ),
        config = cfg
      ),
      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
    )
  }

  cli::cli_alert_success("文献级导出完成: {length(figs)} figures / {length(tabs)} tables")
  ctx
}

register_block("competing_pub_export", block_competing_pub_export, "文献级 Figure/Table 导出")
