###############################################################################
#  ml_nafld_pub_finalize — 决策树定稿 + 文献级图表收口
#
#  register_block: "ml_nafld_pub_finalize"
#  产出: summary_result/{table,figure} · supplement/* · SCI xlsx · 2×4 表现图
###############################################################################

block_ml_nafld_pub_finalize <- function(ctx, ...) {
  cfg <- ctx$config
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  common <- file.path(root, "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (!file.exists(common)) common <- file.path(getwd(), "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (file.exists(common)) source(common, local = FALSE)
  nested <- file.path(root, "Blocks/73_ml_nafld_cm/02block_ml_nafld_nested_cv.R")
  if (file.exists(nested)) source(nested, local = FALSE)
  polish <- file.path(root, "Blocks/73_ml_nafld_cm/05ml_nafld_cm_pub_polish.R")
  if (file.exists(polish)) source(polish, local = FALSE)
  complements <- file.path(root, "Blocks/73_ml_nafld_cm/10ml_nafld_scheme_complements.R")
  if (file.exists(complements)) source(complements, local = FALSE)

  source(file.path(root, "R/utils.R"), local = FALSE)
  source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  source(file.path(root, "R/ml_small_sample_metrics.R"), local = FALSE)
  source(file.path(root, "R/ml_small_sample_table45.R"), local = FALSE)
  if (file.exists(file.path(root, "R/ml_assoc_covariate_rule.R"))) {
    source(file.path(root, "R/ml_assoc_covariate_rule.R"), local = FALSE)
  }

  .nafld_cm_ensure_dirs(cfg)
  out <- .nafld_cm_out_dirs(cfg)
  study <- out$root
  ml <- cfg$ml_small_sample %||% list()
  B <- as.integer(ml$bootstrap_B %||% 1000L)

  best <- .nafld_cm_best_from_table4(cfg)
  if (!is.null(best)) {
    ctx$results$nafld_nested_cv <- list(
      table = utils::read.csv(
        file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.csv"),
        stringsAsFactors = FALSE
      ),
      best = best
    )
  }
  best_algo <- if (!is.null(best)) as.character(best$algorithm)[1L] else "LightGBM"
  best_space <- if (!is.null(best)) as.character(best$space)[1L] else "CM"

  # ── 1) Table 2 临床 / 代谢物 Table 1.1 + 2.1 ──
  cli::cli_alert_info("文献级: Table 2 (Crude/Model1/Model2)…")
  t2 <- tryCatch(.nafld_write_table2_sci(ctx, cfg, out$tables), error = function(e) {
    cli::cli_alert_warning("Table 2: {conditionMessage(e)}")
    NULL
  })
  cli::cli_alert_info("文献级: Table 1.1 / 2.1 代谢物…")
  t11 <- tryCatch(.nafld_write_table1_metabolite(ctx, cfg, out$tables), error = function(e) {
    cli::cli_alert_warning("Table 1.1: {conditionMessage(e)}")
    NULL
  })
  t21 <- tryCatch(.nafld_write_table2_metabolite(ctx, cfg, out$tables), error = function(e) {
    cli::cli_alert_warning("Table 2.1: {conditionMessage(e)}")
    NULL
  })

  # ── 2) 生成 OOF+val 概率（2×4 / Table5）──
  cli::cli_alert_info("文献级: 生成 ml_python_results.csv (5-fold OOF + val)…")
  # 与 nested CV 的 model_order 一致（本课题 config 不含 TabNet）
  fig_algos <- as.character(ml$model_order %||% c(
    "Logistic", "LASSO", "ElasticNet", "RF", "XGBoost", "LightGBM", "SVM", "TabNet"
  ))
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    fig_algos <- setdiff(fig_algos, c("LASSO", "ElasticNet"))
  }
  if (!requireNamespace("lightgbm", quietly = TRUE)) fig_algos <- setdiff(fig_algos, "LightGBM")
  if (!requireNamespace("xgboost", quietly = TRUE)) fig_algos <- setdiff(fig_algos, "XGBoost")
  if (!requireNamespace("randomForest", quietly = TRUE)) fig_algos <- setdiff(fig_algos, "RF")
  if (!requireNamespace("e1071", quietly = TRUE)) fig_algos <- setdiff(fig_algos, "SVM")
  if ("TabNet" %in% fig_algos &&
      !isTRUE(tryCatch(.nafld_cm_tabnet_available(cfg), error = function(e) FALSE))) {
    fig_algos <- setdiff(fig_algos, "TabNet")
  }
  cli::cli_alert_info("Figure 3 模型: {paste(fig_algos, collapse=', ')}")
  probs_info <- tryCatch(
    .nafld_write_ml_probs(ctx, cfg, algos = fig_algos, folds = 5L, seed = 1234L),
    error = function(e) {
      cli::cli_alert_warning("probs: {conditionMessage(e)}")
      NULL
    }
  )

  # ── 3) Table 4 nested CV SCI + Table 5 (ml_write_table45) ──
  cli::cli_alert_info("文献级: Table 4/5 SCI…")
  .nafld_nested_cv_table4_sci(cfg, out$tables)

  if (!is.null(probs_info) && file.exists(file.path(study, "ml_python_results.csv"))) {
    cfg_t45 <- cfg
    cfg_t45$ml_small_sample$model_order <- fig_algos
    feats <- probs_info$feats %||% character(0)
    tryCatch({
      ml_write_table45(
        out_dir = study,
        tab_dir = out$tables,
        d = NULL,
        cfg = cfg_t45,
        feature_label = if (length(feats) > 20L) c(feats[1:20], "…") else feats,
        train_n = probs_info$n_train,
        train_events = probs_info$events_train,
        footnote_extra_t4 = c(
          sprintf("Feature space for this table: %s (consensus features locked from G4).", best_space),
          "Note: nested space×algorithm overview remains Table 4 (nested CV); this internal-validation table supports Figure 3 panels A/C."
        ),
        footnote_extra_t5 = c(
          sprintf("Hold-out n=%d (%d events).", probs_info$n_val_n %||% NA, probs_info$events_val %||% NA),
          sprintf("Best nested-CV model was %s+%s (mean AUC from Table 4).", best_space, best_algo),
          "Hold-out AUC can appear optimistic in small unbalanced cohorts; primary claim uses nested-CV mean AUC."
        )
      )
      # 决策树命名：小样本 T4/T5 → Table 5 / 5.1（勿覆盖 nested Table 4）
      p_oof <- file.path(out$tables, "Table 4. ML performance internal validation.xlsx")
      p_val <- file.path(out$tables, "Table 5. ML performance validation.xlsx")
      p5 <- file.path(out$tables, "Table 5. ML performance internal validation (Youden bootstrap).xlsx")
      p51 <- file.path(out$tables, "Table 5.1 ML performance hold-out validation (Youden bootstrap).xlsx")
      if (file.exists(p_oof)) file.rename(p_oof, p5)
      if (file.exists(p_val)) file.rename(p_val, p51)
      # 表内标题随文件名改正（ml_write_table45 默认写 Table 4/5）
      .nafld_patch_xlsx_title <- function(path, title) {
        if (!file.exists(path) || !requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
        wb <- openxlsx::loadWorkbook(path)
        openxlsx::writeData(wb, sheet = names(wb)[1L], title, startCol = 1L, startRow = 1L)
        openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
        invisible(TRUE)
      }
      .nafld_patch_xlsx_title(p5, "Table 5. ML performance (internal validation, Youden + bootstrap)")
      .nafld_patch_xlsx_title(p51, "Table 5.1. ML performance (hold-out validation, Youden + bootstrap)")
    }, error = function(e) cli::cli_alert_warning("Table45: {conditionMessage(e)}"))
  }

  # Best nested CV → supplement 笔记，不占主文 Table 5 号
  if (!is.null(best)) {
    sup_note <- file.path(study, "supplement", "table")
    dir.create(sup_note, recursive = TRUE, showWarnings = FALSE)
    note_name <- sprintf(
      "Note. Best nested CV model (%s+%s).csv",
      best_space, best_algo
    )
    # 清掉旧命名笔记，避免 CM+LightGBM 与现最优并存
    old_notes <- list.files(sup_note, pattern = "^Note\\. Best nested CV model", full.names = TRUE)
    if (length(old_notes)) unlink(old_notes)
    utils::write.csv(
      best,
      file.path(sup_note, note_name),
      row.names = FALSE, fileEncoding = "UTF-8"
    )
  }

  # ── 4) Table 5.2 方案点名统计量 + Table 6 + NRI/IDI（含估腰围 FLI/LAP）──
  cli::cli_alert_info("文献级: Table 5.2 DeLong/H-L/Brier/PPV/NPV…")
  t52 <- tryCatch(
    .nafld_write_scheme_metrics(ctx, cfg, out$tables, best_algo = best_algo),
    error = function(e) {
      cli::cli_alert_warning("Table5.2: {conditionMessage(e)}")
      NULL
    }
  )
  if (!is.null(t52$split)) {
    # 把挂了 FLI/LAP 的 split 写回 imputed，供 Table6 使用
    if (!is.null(ctx$data$imputed) && !is.null(t52$split$val$FLI)) {
      full <- .nafld_attach_fli_lap_est(ctx$data$imputed, cfg, logger = function(...) invisible())
      ctx$data$imputed <- full
    }
  }
  cli::cli_alert_info("文献级: Table 6 + NRI/IDI…")
  t6 <- tryCatch(
    .nafld_write_table6_nri(ctx, cfg, out$tables, best_algo = best_algo),
    error = function(e) {
      cli::cli_alert_warning("Table6/NRI: {conditionMessage(e)}")
      NULL
    }
  )

  # ── 5) Figures ──
  fig_work <- file.path(study, "Figures", "_pub_work")
  dir.create(fig_work, recursive = TRUE, showWarnings = FALSE)

  cli::cli_alert_info("文献级: Figure 2…")
  .nafld_plot_figure2_journal(ctx, cfg, fig_work)

  # Figure 4 = 与发病/小样本 ML 同一套路：python/ml_figure_combined_2x4.py（先写临时/旧名再改号）
  cli::cli_alert_info("文献级: Figure 4 (standard ML 2×4)…")
  fig3_ok <- FALSE
  fig3_tmp <- file.path(fig_work, "Figure 3. ML performance combined 2x4.pdf")
  pyi <- .nafld_cm_resolve_figure_python(cfg)
  py_2x4 <- file.path(root, "python/ml_figure_combined_2x4.py")
  if (nzchar(pyi) && file.exists(py_2x4) && file.exists(file.path(study, "ml_python_results.csv"))) {
    Sys.setenv(MPLCONFIGDIR = file.path(tempdir(), "mplconfig"))
    dir.create(Sys.getenv("MPLCONFIGDIR"), recursive = TRUE, showWarnings = FALSE)
    cmd <- paste(
      shQuote(pyi), shQuote(py_2x4),
      "--root", shQuote(study),
      "--out", shQuote(fig3_tmp),
      "--bootstrap", as.character(min(B, 800L))
    )
    rc <- tryCatch(system(cmd, intern = TRUE), error = function(e) conditionMessage(e))
    fig3_ok <- file.exists(fig3_tmp)
    if (!fig3_ok) cli::cli_alert_warning("standard 2x4: {paste(utils::tail(rc, 3), collapse=' | ')}")
  }
  if (!fig3_ok && file.exists(file.path(study, "ml_python_results.csv"))) {
    fig3_ok <- isTRUE(tryCatch(
      .nafld_plot_figure3_2x4_r(study, fig3_tmp, algos = fig_algos, B = min(B, 400L)),
      error = function(e) {
        cli::cli_alert_warning("R 2x4: {conditionMessage(e)}")
        FALSE
      }
    ))
  }
  if (!fig3_ok) {
    cli::cli_alert_warning("Figure 4 2×4 未生成，回退热图+ROC")
    feats <- .nafld_cm_cm_features(ctx)
    refit <- if (!is.null(best)) .nafld_cm_retrain_best_val(ctx, cfg, best, feats) else NULL
    .nafld_cm_plot_figure3(ctx, cfg, fig_work, best, refit)
  }
  # 热图：正式编号为 Figure 3（Nested CV）
  t4p <- file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.csv")
  if (file.exists(t4p) && requireNamespace("ggplot2", quietly = TRUE)) {
    t4 <- utils::read.csv(t4p, stringsAsFactors = FALSE)
    p_heat <- ggplot2::ggplot(t4, ggplot2::aes(algorithm, space, fill = auc_mean)) +
      ggplot2::geom_tile(color = "white") +
      ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", auc_mean)), size = 2.8, family = "serif") +
      ggplot2::scale_fill_gradient(low = "#f7fbff", high = "#08306b") +
      ggplot2::labs(x = NULL, y = NULL, fill = "AUC", title = "Nested CV mean AUC by space and algorithm") +
      ggplot2::theme_classic(base_size = 11, base_family = "serif") +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
    ggplot2::ggsave(file.path(fig_work, "Figure 3. Nested CV AUC heatmap.pdf"), p_heat, width = 9, height = 4)
    # 兼容旧名
    file.copy(
      file.path(fig_work, "Figure 3. Nested CV AUC heatmap.pdf"),
      file.path(fig_work, "Figure S. Nested CV AUC heatmap.pdf"),
      overwrite = TRUE
    )
  }

  # 若 2×4 用旧文件名，先落到正式 Figure 4
  fig3_tmp <- file.path(fig_work, "Figure 3. ML performance combined 2x4.pdf")
  fig4_2x4 <- file.path(fig_work, "Figure 4. ML performance combined 2x4.pdf")
  if (file.exists(fig3_tmp) && !file.exists(fig4_2x4)) {
    file.copy(fig3_tmp, fig4_2x4, overwrite = TRUE)
  }
  if (fig3_ok && file.exists(fig3_tmp)) {
    file.copy(fig3_tmp, fig4_2x4, overwrite = TRUE)
    file.copy(fig3_tmp, file.path(fig_work, "Figure 3. ML performance heatmap and ROC.pdf"), overwrite = TRUE)
  }

  cli::cli_alert_info("文献级: Figure 5 SHAP…")
  shap_ok <- isTRUE(.nafld_plot_figure4_shap(ctx, cfg, fig_work, algo = best_algo))
  # SHAP 正式编号 Figure 5
  shap_src <- file.path(fig_work, "Figure 4. SHAP summary.pdf")
  shap_dst <- file.path(fig_work, "Figure 5. SHAP summary.pdf")
  if (file.exists(shap_src)) file.copy(shap_src, shap_dst, overwrite = TRUE)
  # 方案模块五：dependence + waterfall/force 单病例
  cli::cli_alert_info("文献级: Figure S4/S5 SHAP dependence + waterfall…")
  supp_fig_dir <- file.path(study, "supplement", "figure")
  dir.create(supp_fig_dir, recursive = TRUE, showWarnings = FALSE)
  shap_ext_ok <- tryCatch(
    isTRUE(.nafld_plot_shap_extended(ctx, cfg, fig_work, supp_fig_dir, algo = best_algo)),
    error = function(e) {
      cli::cli_alert_warning("SHAP extended: {conditionMessage(e)}")
      FALSE
    }
  )

  cli::cli_alert_info("文献级: Figure 6 vs scores…")
  .nafld_plot_figure5_scores(t6, fig_work)
  sc_src <- file.path(fig_work, "Figure 5. AUC vs traditional scores.pdf")
  sc_dst <- file.path(fig_work, "Figure 6. AUC vs traditional scores.pdf")
  if (file.exists(sc_src)) file.copy(sc_src, sc_dst, overwrite = TRUE)

  cli::cli_alert_info("文献级: Figure S1 传统评分箱线…")
  .nafld_plot_boxplot_scores_s1(ctx, cfg, fig_work)

  # AUC 偏高说明落盘
  note <- c(
    "# Hold-out AUC note (审稿友好)",
    "",
    sprintf("- Nested CV best: %s+%s mean AUC ≈ %s (primary performance claim).",
            best_space, best_algo,
            if (!is.null(best)) sprintf("%.3f", best$auc_mean) else "NA"),
    "- Hold-out (30% val) AUC for the same model can be higher (e.g. >0.95) in this small, class-imbalanced cohort (NAFLD>>Normal).",
    "- Primary reporting uses nested CV mean ± SD (Table 4). Hold-out metrics (Table 5.1 / Figure 4) are supportive.",
    "- Features were locked from training-set consensus (G4); traditional scores HSI/ZJU/TyG were excluded from the ML feature pool.",
    "- External validation (Figure 7) remains pending."
  )
  writeLines(note, file.path(study, "AUC_holdout_note.md"))

  # ── 6) summary_result 收口（单目录：Table 1–N + Table S*，无小数点号）──
  sum_tab <- file.path(study, "summary_result", "table")
  sum_fig <- file.path(study, "summary_result", "figure")
  sup_tab <- file.path(study, "supplement", "table")
  sup_fig <- file.path(study, "supplement", "figure")
  for (d in c(sum_tab, sum_fig, sup_tab, sup_fig)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  alias_old <- file.path(study, "summary_result", "Tables")
  if (dir.exists(alias_old)) unlink(alias_old, recursive = TRUE)
  # 清掉旧多目录 / 平铺杂件，只保留本轮定稿
  for (old in c("主文", "补充", "支撑", "01_主文_Table1-7", "02_补充_TableS", "03_支撑底稿")) {
    p_old <- file.path(sum_tab, old)
    if (dir.exists(p_old)) unlink(p_old, recursive = TRUE)
  }
  unlink(list.files(sum_tab, pattern = "\\.(xlsx|csv)$", full.names = TRUE))

  # Table 3 选特征 SCI；Feature count → S7（流水线工作区编号，定稿再映射）
  t3c <- file.path(out$tables, "Table 3. Feature count summary.csv")
  if (file.exists(t3c)) {
    t3 <- utils::read.csv(t3c, stringsAsFactors = FALSE)
    tryCatch(
      sci_xlsx_single_header_booktabs(
        file.path(out$tables, "Table S7. Feature count summary by space.xlsx"),
        "Table S7. Feature count by space",
        t3,
        footnotes = "Consensus features locked for nested CV (C ≥3 methods; M ≥2 + hard cap)."
      ),
      error = function(e) NULL
    )
    unlink(file.path(out$tables, "Table 3. Feature count summary.xlsx"))
  }
  t3s <- file.path(out$tables, "Table 3. Selected features by space.csv")
  if (file.exists(t3s)) {
    t3b <- utils::read.csv(t3s, stringsAsFactors = FALSE)
    tryCatch(
      sci_xlsx_single_header_booktabs(
        file.path(out$tables, "Table 3. Selected features by space.xlsx"),
        "Table 3. Selected features by space",
        t3b,
        footnotes = "C/M/CM feature lists after consensus filtering."
      ),
      error = function(e) NULL
    )
  }

  .copy_named <- function(src, dst) {
    if (is.character(src) && length(src) && file.exists(src[1L])) {
      file.copy(src[1L], dst, overwrite = TRUE)
    }
  }
  # 定稿精简：正文 Table 1–5；补充 Table S1–S12（其余不进 summary_result/table）
  main_map <- list(
    "Table 1. Baseline characteristics of NAFLD.xlsx" =
      c(file.path(out$tables, "Table 1-Hospital. Baseline characteristics of NAFLD.xlsx"),
        file.path(out$tables, "Table 1. Baseline characteristics of NAFLD.xlsx")),
    "Table 2. Selected features by space.xlsx" =
      file.path(out$tables, "Table 3. Selected features by space.xlsx"),
    "Table 3. Nested CV performance by space and algorithm.xlsx" =
      file.path(out$tables, "Table 4. Nested CV performance by space and algorithm.xlsx"),
    "Table 4. Best model vs traditional scores (HSI ZJU TyG FLI LAP).xlsx" =
      c(file.path(out$tables, "Table 6. Best model vs HSI ZJU TyG.xlsx"),
        file.path(out$tables, "Table 6. Best model vs traditional scores (HSI ZJU TyG FLI LAP).xlsx")),
    "Table 5. External bridging summary.xlsx" =
      c(file.path(out$tables, "Table 7. External bridging summary.xlsx"),
        file.path(sup_tab, "Table 7. External bridging summary.xlsx"))
  )
  for (nm in names(main_map)) {
    cands <- unlist(main_map[[nm]], use.names = FALSE)
    hit <- cands[file.exists(cands)][1L]
    .copy_named(hit, file.path(sum_tab, nm))
  }

  # 补充 S1–S12（工作区文件名 → 定稿号）
  s_rename <- c(
    "Table 1.1 Metabolite baseline characteristics.xlsx" =
      "Table S1. Metabolite baseline characteristics.xlsx",
    "Table 2. Clinical feature associations (Crude Model1 Model2).xlsx" =
      "Table S2. Clinical feature associations (Crude Model1 Model2).xlsx",
    "Table 2.1 Metabolite associations (Crude Model1 Model2).xlsx" =
      "Table S3. Metabolite associations (Crude Model1 Model2).xlsx",
    "Table 5. ML performance internal validation (Youden bootstrap).xlsx" =
      "Table S4. ML performance internal validation (Youden bootstrap).xlsx",
    "Table 5.1 ML performance hold-out validation (Youden bootstrap).xlsx" =
      "Table S5. ML performance hold-out validation (Youden bootstrap).xlsx",
    "Table 5.2 Scheme metrics DeLong HL Brier PPV NPV.xlsx" =
      "Table S6. Scheme metrics DeLong HL Brier PPV NPV.xlsx",
    "Table 6.1 NRI and IDI versus traditional scores.xlsx" =
      "Table S7. NRI and IDI versus traditional scores.xlsx",
    "Table S8. NHANES weighted clinical direction.xlsx" =
      "Table S8. NHANES weighted clinical direction.xlsx",
    "Table S9. GEO DE genes and pathway overlap.xlsx" =
      "Table S9. GEO DE genes and pathway overlap.xlsx",
    "Table S10. MW urine metabolite direction.xlsx" =
      "Table S10. MW urine metabolite direction.xlsx",
    "Table S13. Pathway convergence across sources.xlsx" =
      "Table S11. Pathway convergence across sources.xlsx",
    "Table S15. Differential urinary metabolites.xlsx" =
      "Table S12. Differential urinary metabolites.xlsx"
  )
  for (src_name in names(s_rename)) {
    src <- file.path(out$tables, src_name)
    if (!file.exists(src)) src <- file.path(sup_tab, src_name)
    .copy_named(src, file.path(sum_tab, unname(s_rename[[src_name]])))
    if (file.exists(src)) file.copy(src, file.path(sup_tab, basename(src)), overwrite = TRUE)
  }

  writeLines(c(
    "# 定稿表（精简）",
    "",
    "正文 Table 1–5；补充 Table S1–S12。全量备份见 `_archive_table_full_before_slim_*`。",
    sprintf("- 正文：%d；补充 S：%d；最优：%s+%s",
            length(list.files(sum_tab, pattern = "^Table [0-9]+\\.")),
            length(list.files(sum_tab, pattern = "^Table S[0-9]+\\.")),
            best_space, best_algo)
  ), file.path(sum_tab, "README.md"))

  # Figure 1
  fig1_cands <- c(
    file.path(out$figures, "Figure 1. Inclusion exclusion flowchart_hospital.pdf"),
    file.path(out$figures, "Figure 1. Inclusion exclusion flowchart.pdf"),
    file.path(study, "step15_attrition_flowchart", "Figures",
              "Figure 1. Inclusion exclusion flowchart_hospital.pdf"),
    file.path(study, "step15_attrition_flowchart", "Figures", "Figure 1. Flowchart.pdf")
  )
  af <- ctx$results$attrition_flowchart$pdf %||% NA_character_
  if (is.character(af) && length(af) && file.exists(af[1L])) fig1_cands <- c(af[1L], fig1_cands)
  fig1_src <- fig1_cands[file.exists(fig1_cands)][1L]
  if (!is.na(fig1_src) && nzchar(fig1_src)) {
    file.copy(fig1_src, file.path(sum_fig, "Figure 1. Inclusion exclusion flowchart.pdf"), overwrite = TRUE)
  }

  main_figs <- c(
    "Figure 2. Feature selection by space.pdf",
    "Figure 3. Nested CV AUC heatmap.pdf",
    "Figure 4. ML performance combined 2x4.pdf",
    "Figure 5. SHAP summary.pdf",
    "Figure 6. AUC vs traditional scores.pdf"
  )
  # 兼容旧 2×4 / SHAP / scores 文件名
  if (!file.exists(file.path(fig_work, main_figs[3]))) {
    alt <- file.path(fig_work, "Figure 3. ML performance combined 2x4.pdf")
    if (file.exists(alt)) file.copy(alt, file.path(fig_work, main_figs[3]), overwrite = TRUE)
  }
  if (!file.exists(file.path(fig_work, main_figs[4]))) {
    alt <- file.path(fig_work, "Figure 4. SHAP summary.pdf")
    if (file.exists(alt)) file.copy(alt, file.path(fig_work, main_figs[4]), overwrite = TRUE)
  }
  if (!file.exists(file.path(fig_work, main_figs[5]))) {
    alt <- file.path(fig_work, "Figure 5. AUC vs traditional scores.pdf")
    if (file.exists(alt)) file.copy(alt, file.path(fig_work, main_figs[5]), overwrite = TRUE)
  }
  for (f in main_figs) {
    s <- file.path(fig_work, f)
    if (file.exists(s)) file.copy(s, file.path(sum_fig, f), overwrite = TRUE)
  }
  # Figure 1 already copied above into sum_fig root; also ensure pdf/ later via export

  # 补充图连续编号 S1–S6（禁止跳号 / S5.1）
  # S1 传统评分箱线；S2 通路；S3 beeswarm；S4 dependence；S5 waterfall；S6 force
  s_map <- list(
    "Figure S1. Traditional scores boxplot HSI TyG.pdf" =
      file.path(fig_work, "Figure S1. Traditional scores boxplot HSI TyG.pdf"),
    "Figure S2. Hospital pathway enrichment.pdf" =
      file.path(sup_fig, "Figure S2. Hospital pathway enrichment.pdf"),
    "Figure S3. SHAP beeswarm.pdf" =
      file.path(sup_fig, "Figure S3. SHAP beeswarm.pdf"),
    "Figure S4. SHAP dependence top features.pdf" =
      file.path(fig_work, "Figure S4. SHAP dependence top features.pdf"),
    "Figure S5. SHAP waterfall low mid high cases.pdf" =
      file.path(fig_work, "Figure S5. SHAP waterfall low mid high cases.pdf"),
    "Figure S6. SHAP force low mid high cases.pdf" =
      file.path(fig_work, "Figure S6. SHAP force low mid high cases.pdf")
  )
  # 兼容旧名 S5.1 → S6
  if (!file.exists(s_map[["Figure S6. SHAP force low mid high cases.pdf"]])) {
    legacy <- file.path(fig_work, "Figure S5.1 SHAP force low mid high cases.pdf")
    if (!file.exists(legacy)) legacy <- file.path(sup_fig, "Figure S5.1 SHAP force low mid high cases.pdf")
    if (file.exists(legacy))
      s_map[["Figure S6. SHAP force low mid high cases.pdf"]] <- legacy
  }
  for (nm in names(s_map)) {
    s <- s_map[[nm]]
    if (!file.exists(s)) s <- file.path(sup_fig, nm)
    if (!file.exists(s)) s <- file.path(fig_work, nm)
    if (!file.exists(s)) next
    file.copy(s, file.path(sup_fig, nm), overwrite = TRUE)
    file.copy(s, file.path(sum_fig, nm), overwrite = TRUE)
  }
  # 清掉旧 S5.1 编号残留，避免汇总目录跳号
  for (d in c(sum_fig, file.path(sum_fig, "pdf"), file.path(sum_fig, "png"),
              file.path(sum_fig, "tiff"), file.path(sum_fig, "image_information"),
              sup_fig, fig_work)) {
    if (!dir.exists(d)) next
    olds <- list.files(d, pattern = "S5\\.1", full.names = TRUE)
    if (length(olds)) unlink(olds)
  }
  # 旧单张箱线仅留 supplement，不进主文汇总编号
  box_keep <- c(
    "Figure S1-Hospital. Boxplot TyG by Disease.pdf",
    "Figure S2-Hospital. Boxplot HSI by Disease.pdf"
  )
  for (sub in c("pdf", "")) {
    src_root <- if (nzchar(sub)) file.path(study, "Figures", sub) else out$figures
    if (!dir.exists(src_root)) next
    for (f in box_keep) {
      s <- file.path(src_root, f)
      if (file.exists(s)) file.copy(s, file.path(sup_fig, f), overwrite = TRUE)
    }
  }
  heat_s <- file.path(fig_work, "Figure S. Nested CV AUC heatmap.pdf")
  if (file.exists(heat_s)) file.copy(heat_s, file.path(sup_fig, basename(heat_s)), overwrite = TRUE)

  # 清理根 Figures 污染
  for (poll_dir in c(out$figures, file.path(study, "Figures", "pdf"))) {
    if (!dir.exists(poll_dir)) next
    bad <- list.files(poll_dir, full.names = TRUE, ignore.case = TRUE)
    bad <- bad[grepl("Boxplot|Nested CV AUC heatmap|AUC vs traditional", basename(bad), ignore.case = TRUE)]
    if (length(bad)) unlink(bad)
  }

  # pub 四目录
  pe <- file.path(root, "R/pub_figure_export.R")
  if (file.exists(pe)) {
    source(pe, local = FALSE)
    meta <- list(
      disease = cfg$project$disease,
      database = cfg$project$database,
      outcome = cfg$data$outcome_column,
      analysis_group = cfg$project$analysis_group,
      reference_group = cfg$project$reference_group,
      databases = cfg$project$database %||% "Hospital",
      exposure = "临床特征 C / 尿代谢物 M / 联合 CM（ML 特征空间）",
      grouping = "binary",
      n_total = 560L, n_train = 391L, n_val = 169L
    )
    if (exists("export_pub_figures", mode = "function")) {
      tryCatch(export_pub_figures(sum_fig, meta = meta, config = cfg), error = function(e) {
        cli::cli_alert_warning("export_pub_figures: {conditionMessage(e)}")
      })
    }
  }

  # 补刷 image_information 关键数字（简版追加）
  imd <- file.path(sum_fig, "image_information")
  if (dir.exists(imd) && !is.null(best)) {
    f4md <- file.path(imd, "Figure 4. ML performance combined 2x4.md")
    if (file.exists(f4md)) {
      extra <- c(
        "",
        "### 图上标注（收获）",
        sprintf("- Nested-CV best: %s+%s, mean AUC=%.3f", best_space, best_algo, best$auc_mean),
        sprintf("- Models in 2×4: %s", paste(fig_algos, collapse = ", ")),
        "- Panels A–H: standard ML 2×4 (ml_figure_combined_2x4) — A/B ROC, C/D calibration, E/F metrics+CI, G/H DCA."
      )
      write(extra, f4md, append = TRUE)
    }
    f3md <- file.path(imd, "Figure 3. Nested CV AUC heatmap.md")
    if (file.exists(f3md)) {
      write(c(
        "",
        "### 图上标注（收获）",
        sprintf("- Best cell: %s+%s, mean AUC=%.3f", best_space, best_algo, best$auc_mean),
        "- Values = nested CV mean AUC (5-fold × 10-repeats outer evaluations)."
      ), f3md, append = TRUE)
    }
  }

  readme <- c(
    "# ml_nafld_cm 汇总产出（文献级定稿）",
    "",
    "## 表 → summary_result/table/（精简）",
    paste0("- 正文 Table 1–5：", length(list.files(sum_tab, pattern = "^Table [0-9]+\\.")), " 张"),
    paste0("- 补充 Table S1–S12：", length(list.files(sum_tab, pattern = "^Table S[0-9]+\\.")), " 张"),
    "- 详见 `table/README.md`；全量备份 `_archive_table_full_before_slim_*`",
    "",
    "## summary_result/figure/pdf",
    paste0("- ", list.files(file.path(sum_fig, "pdf"), pattern = "\\.pdf$")),
    "",
    "## 说明",
    "- Table 3 = nested CV 主报；Table 4 = vs 传统评分（含估腰围 FLI/LAP）"
  )
  writeLines(readme, file.path(study, "summary_result", "README.md"))

  n_pdf <- length(list.files(file.path(sum_fig, "pdf"), pattern = "\\.pdf$"))
  n_main <- length(list.files(sum_tab, pattern = "^Table [0-9]+\\."))
  n_s <- length(list.files(sum_tab, pattern = "^Table S[0-9]+\\."))
  cli::cli_alert_success(
    "文献级收口完成：正文 {n_main} + 补充S {n_s} 表 / {n_pdf} 图；2×4={fig3_ok}; SHAP={shap_ok}"
  )

  ctx$results$nafld_pub_finalize <- list(
    summary_table_dir = sum_tab,
    summary_figure_dir = sum_fig,
    best = best,
    fig3_2x4 = fig3_ok,
    shap = shap_ok,
    table2 = !is.null(t2),
    table6_nri = !is.null(t6$nri)
  )
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block(
    "ml_nafld_pub_finalize",
    block_ml_nafld_pub_finalize,
    "NAFLD 文献级汇总（SCI表 + 2×4 + NRI/IDI + SHAP）"
  )
}
