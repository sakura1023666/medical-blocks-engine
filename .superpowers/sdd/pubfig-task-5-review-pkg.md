# Review package Task 5
R/pipeline_runner.R:853:  if (exists("export_pub_figures", mode = "function") ||
R/pipeline_runner.R:855:    if (!exists("export_pub_figures", mode = "function")) {
R/pipeline_runner.R:860:    is_dual_slot <- !is.null(config$dual_db$current_db) &&
R/pipeline_runner.R:862:    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
R/pipeline_runner.R:864:        export_pub_figures(figs, meta = list(
tests/test_result_review_guards.R:424:source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)
tests/test_result_review_guards.R:452:dual_db_combine_paired_figures(dirname(fd2), cfg_single)
tests/test_result_review_guards.R:461:dual_db_combine_paired_figures(ix_root, cfg_single)
tests/test_result_review_guards.R:467:if (!exists("export_pub_figures", mode = "function")) {
tests/test_result_review_guards.R:480:export_pub_figures(
tests/test_result_review_guards.R:499:# finalize 顺序：curate 之后调用 export_pub_figures
tests/test_result_review_guards.R:501:stopifnot(grepl("export_pub_figures\\(figs_dir", runner_txt))
tests/test_result_review_guards.R:503:export_pos <- regexpr("export_pub_figures\\(figs_dir", runner_txt)[1L]
tests/test_result_review_guards.R:511:stopifnot(grepl("export_pub_figures\\(figs", pipe_txt))
tests/test_result_review_guards.R:512:stopifnot(grepl("is_dual_slot", pipe_txt))
tests/test_result_review_guards.R:515:pipe_export_pos <- regexpr("export_pub_figures\\(figs", pipe_txt)[1L]
tests/test_result_review_guards.R:526:stopifnot(grepl("export_pub_figures\\(", comp_txt))
tests/test_result_review_guards.R:527:stopifnot(grepl("dual_db_combine_paired_figures", comp_txt))
tests/test_result_review_guards.R:528:comp_export_pos <- regexpr("export_pub_figures\\(", comp_txt)[1L]
Blocks/55_competing_risk_full/18block_competing_pub_export.R:309:    if (!exists("dual_db_combine_paired_figures", mode = "function")) {
Blocks/55_competing_risk_full/18block_competing_pub_export.R:310:      comb_src <- file.path(root, "R/dual_db_combine_figures.R")
Blocks/55_competing_risk_full/18block_competing_pub_export.R:313:    if (exists("dual_db_combine_paired_figures", mode = "function")) {
Blocks/55_competing_risk_full/18block_competing_pub_export.R:315:        dual_db_combine_paired_figures(out_root, cfg, figures_dir = fig_dir),
Blocks/55_competing_risk_full/18block_competing_pub_export.R:321:  if (!exists("export_pub_figures", mode = "function")) {
Blocks/55_competing_risk_full/18block_competing_pub_export.R:325:  if (exists("export_pub_figures", mode = "function")) {
Blocks/55_competing_risk_full/18block_competing_pub_export.R:327:      export_pub_figures(
--- pipeline_runner tail ---
      run_block(ctx, block_name),
      error = function(e) {
        msg <- conditionMessage(e)
        if (grepl("^COX_SEARCH_DEGRADE:", msg)) {
          cli::cli_alert_warning(
            "协变量搜索降级: {sub('^COX_SEARCH_DEGRADE: ', '', msg)}；继续下一 block（cox_branch={ctx$results$cox_branch %||% '?'}）"
          )
          return(ctx)
        }
        if (grepl("^COX_(BOTH_MODELS_SIG|M2_NOSIG)_DEGRADE:", msg)) {
          cli::cli_alert_warning(
            "Cox 双模型显著性降级: {sub('^COX_(BOTH_MODELS_SIG|M2_NOSIG)_DEGRADE: ', '', msg)}；继续下一 block（cox_branch={ctx$results$cox_branch %||% '?'}）"
          )
          return(ctx)
        }
        stop(e)
      }
    )

    if (exists("attrition_auto_append_nrow", mode = "function") &&
        !identical(block_name, "attrition_flowchart")) {
      n_after <- attrition_n_current(ctx)
      ctx <- attrition_auto_append_nrow(ctx, block_name, n_before, n_after)
    }

    if (block_name %in% render_tables_after &&
        exists("render_queued_tables", mode = "function")) {
      ctx <- render_queued_tables(ctx)
    }
    if (block_name %in% render_figures_after &&
        exists("render_queued_figures", mode = "function")) {
      ctx <- render_queued_figures(ctx)
    }

    if (checkpoint_enable) {
      pipeline_save_checkpoint(ctx, config, pipeline, full_idx, block_name, checkpoint_dir)
    }
  }

  cli::cli_alert_success("Pipeline finished: {pipeline$name %||% 'unnamed'}")
  if (exists("sync_all_block_pub_outputs_to_root", mode = "function")) {
    ctx <- sync_all_block_pub_outputs_to_root(ctx)
    # 删表后发表编号自动顺延（文件名 + xlsx/tex 内标题）；可用 config$pub$renumber = FALSE 关闭
    pub_cfg <- (config$pub %||% list())
    if (isTRUE(pub_cfg$renumber %||% TRUE) &&
        exists("pub_renumber_pub_dir", mode = "function")) {
      out_root <- ctx$root_output_dir %||% config$project$output_dir
      if (!is.null(out_root) && dir.exists(out_root)) {
        for (sub in c("Tables", "Figures")) {
          tryCatch(
            pub_renumber_pub_dir(file.path(out_root, sub)),
            error = function(e) cli::cli_alert_warning("编号重排失败[{sub}]: {e$message}")
          )
        }
      }
    }
  }
  if (exists("export_pub_figures", mode = "function") ||
      file.exists(file.path(root, "R/pub_figure_export.R"))) {
    if (!exists("export_pub_figures", mode = "function")) {
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    }
    out_root <- ctx$root_output_dir %||% config$project$output_dir
    figs <- file.path(out_root, "Figures")
    is_dual_slot <- !is.null(config$dual_db$current_db) &&
      nzchar(as.character(config$dual_db$current_db)[1L])
    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
      tryCatch(
        export_pub_figures(figs, meta = list(
          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
          outcome = config$data$outcome_column %||% "",
          databases = config$project$database %||% character(0),
          combined = FALSE
        ), config = config),
        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
      )
    }
  }
  invisible(ctx)
}
--- competing export tail ---
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
