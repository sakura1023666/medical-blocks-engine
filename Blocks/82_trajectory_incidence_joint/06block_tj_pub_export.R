###############################################################################
# tj_pub_export — 联合轨迹发病 发表收口（Table1-3 + Fig1-4 + Methods + 交付根）
#
# 产物落 delivery root = <Output>/summary_results/：
#   Tables/   Table 1 (baseline by class × system)
#             Table 2 (Cox Model1-K × outcome × system)
#             Table 3 (subgroup HR + P-int)
#             Table S1 (sensitivity)  Table S2 (trajectory IC per system)
#   Figures/  Figure 1 (attrition flowchart)  Figure 2 (KM by class, per system)
#             Figure 3 (adjusted HR forest)    Figure 4 (trajectory panels)
#             pdf/ + image_information/
#   Methods_statistical_analysis.md  Methods_software_versions.txt
# 收口：export_pub_figures → pub_sync_xlsx_a1_titles_to_filenames → prune 白名单
#
# register_block: "tj_pub_export"
###############################################################################

block_tj_pub_export <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/attrition_log.R"), local = FALSE)
  })
  bl <- ctx$config$joint_trajectory %||% stop("tj_pub_export: 缺 config", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  pub <- bl$pub %||% list()
  df <- ctx$data$cleaned %||% ctx$data$raw
  out_root <- file.path(ctx$config$project$output_dir %||% "Output")
  fam <- tj_pub_font(ctx$config)

  DR <- pub$delivery_root %||% file.path(out_root, "summary_results")
  TD <- file.path(DR, "Tables"); FD <- file.path(DR, "Figures")
  for (d in c(TD, FD, file.path(FD, "pdf"), file.path(FD, "image_information")))
    dir.create(d, showWarnings = FALSE, recursive = TRUE)

  dfname <- function(s) gsub("[^A-Za-z0-9]+", "_", s)
  prim_key <- paste0("tj_outcome_", (bl$outcome %||% list())$primary$name %||% "primary")
  prim <- ctx$results[[prim_key]] %||% ctx$results$tj_outcome_primary

  # ── Table 1 baseline by class（每体系）──────────────────────────────
  cont_vars <- pub$table1_cont %||% intersect(c("age","BMI_w2","TyG_w2","whtr_w2","sbp","dbp"), names(df))
  cat_vars  <- pub$table1_cat  %||% intersect(c("sex","race_white","edu","smoke","drink","hbp_d","dm_d","chol_d"), names(df))
  t1_list <- list()
  for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys); if (!gv %in% names(df)) next
    lv <- sort(unique(as.character(df[[gv]])))
    t1 <- tj_table1_by_class(df, gv, cont_vars, cat_vars, class_order = lv)
    # 文件名/标题避免括号（export_sci_table 会剥括号导致同名覆盖）；体系名用连字符后缀
    t1_path <- file.path(TD, paste0("Table 1 - baseline by trajectory class - ", dfname(sys), ".xlsx"))
    export_sci_table(t1, t1_path,
      title = paste0("Table 1. Baseline characteristics by joint trajectory class - ", sys),
      table_footnotes = c("Mean (SD) for continuous, n (%) for binary; Kruskal-Wallis / chi-square P.",
                          "Reference class = lowest trajectory risk (T1)."))
    t1_list[[sys]] <- t1
  }

  # ── Table 2 Cox（合并 ctx$results$tj_cox）──────────────────────────
  cox <- ctx$results$tj_cox
  if (!is.null(cox) && nrow(cox)) {
    m_lev <- unique(cox$model); c_lev <- unique(cox$class)
    idx <- expand.grid(model = m_lev, class = c_lev, system = unique(cox$system),
                       stringsAsFactors = FALSE)
    t2 <- data.frame(Class = idx$class, System = idx$system, check.names = FALSE)
    for (mn in m_lev) {
      sub <- cox[cox$model == mn, , drop = FALSE]
      key <- paste(sub$system, sub$class, sep = "|")
      cell <- sprintf("%.3f (%.3f, %.3f)", sub$HR, sub$lo, sub$hi)
      names <- ifelse(sub$p < 0.001, paste0(cell, " <0.001"),
                      paste0(cell, sprintf(" %.3f", sub$p)))
      t2[[mn]] <- names[match(paste(idx$system, idx$class, sep="|"), key)]
      t2[[mn]][is.na(t2[[mn]]) | t2[[mn]] == "NA (NA, NA)"] <- "1 (reference)"
    }
    t2 <- t2[order(t2$System, match(t2$Class, c_lev)), ]
    export_sci_table(t2, file.path(TD, "Table 2 - Cox models by class and covariate set.xlsx"),
      title = "Table 2. Hazard ratios (95% CI) for incident disease by trajectory class, sequential models",
      table_footnotes = c("Reference = T1 (lowest trajectory). Models sequentially add covariates.",
                          "Rubin-pooled across imputations when MICE enabled.",
                          "Cell format: HR (95% CI) P."))
  }

  # ── Table 3 subgroup HR + P-int ────────────────────────────────────
  sg <- ctx$results$tj_subgroup; pib <- ctx$results$tj_p_interaction
  if (!is.null(sg) && nrow(sg)) {
    disp <- sg
    disp$est <- ifelse(is.na(disp$HR), "NE",
      sprintf("%.3f (%.3f, %.3f)", disp$HR, disp$lo, disp$hi))
    disp$pv <- ifelse(is.na(disp$p), NA,
      ifelse(disp$p < 0.001, "<0.001", sprintf("%.3f", disp$p)))
    t3 <- data.frame(System = disp$system, Subgroup = disp$subgroup, Level = disp$level,
                     N = disp$n, Events = disp$events, Class = disp$class,
                     `HR (95% CI)` = disp$est, P = disp$pv, check.names = FALSE)
    if (!is.null(pib) && nrow(pib)) {
      t3$P.int <- NA
      for (r in seq_len(nrow(pib))) {
        hit <- which(t3$System == pib$system[r] & t3$Subgroup == pib$subgroup[r])
        if (length(hit)) t3$P.int[hit[1]] <- sprintf("%.3f", pib$p_interaction[r])
      }
    }
    export_sci_table(t3, file.path(TD, "Table 3 - subgroup hazard ratios and interaction P.xlsx"),
      title = "Table 3. Subgroup-specific hazard ratios by trajectory class with P for interaction",
      table_footnotes = c("NE = not estimable (events below minimum).",
                          "P for interaction from Rubin-pooled likelihood-ratio test."))
  }

  # ── Sensitivity S1 ────────────────────────────────────────────────
  sens <- ctx$results$tj_sensitivity
  if (!is.null(sens) && nrow(sens)) {
    sens$est <- sprintf("%.3f (%.3f, %.3f)", sens$HR, sens$lo, sens$hi)
    sens$pv <- ifelse(sens$p < 0.001, "<0.001", sprintf("%.3f", sens$p))
    ts <- sens[, c("system","analysis","class","est","pv","m")]
    names(ts) <- c("System","Sensitivity analysis","Class","HR (95% CI)","P","Imputations")
    export_sci_table(ts, file.path(TD, "Table S1 - sensitivity analyses.xlsx"),
      title = "Table S1. Sensitivity analyses of trajectory class and incident disease",
      table_footnotes = c("Imputations = 1 for complete-case and when MICE disabled.",
                          "S7 weights posterior probabilities; S9 adds follow-up time main effect."))
  }
  # ── Figure 1 attrition flowchart ──────────────────────────────────
  tryCatch({
    rows <- attrition_finalize_rows(ctx, ctx$config)
    attrition_draw_pdf(rows, "Figure 1. Study flowchart",
                       file.path(FD, "pdf", "Figure 1 - flowchart.pdf"), font_family = fam)
  }, error = function(e) cli::cli_alert_warning("Fig1 跳过: {conditionMessage(e)}"))

  # ── Figure 2 KM by class（每体系）─────────────────────────────────
  if (!is.null(prim)) for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys); if (!gv %in% names(df)) next
    tryCatch(tj_km_pdf(df, gv, prim$event, prim$time,
      file.path(FD, "pdf", paste0("Figure 2 - KM by class (", dfname(sys), ").pdf")),
      paste0("Figure 2. ", sys, " trajectory classes: incident outcome"), fam),
      error = function(e) cli::cli_alert_warning("Fig2 {sys} 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 3 adjusted HR forest ───────────────────────────────────
  mn_last <- tail(unique(cox$model), 1)
  if (!is.null(cox) && nrow(cox) && !is.null(mn_last)) {
    fr <- cox[cox$model == mn_last, , drop = FALSE]
    fr$lab <- paste0(fr$system, " ", fr$class, " (", fr$outcome, ")")
    fr <- fr[order(fr$HR), ]
    tryCatch(tj_forest_pdf(fr, file.path(FD, "pdf", "Figure 3 - adjusted HR forest.pdf"),
      paste0("Figure 3. Fully adjusted HR by trajectory class (", mn_last, ")"), fam),
      error = function(e) cli::cli_alert_warning("Fig3 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 4 trajectory panels（每体系每指标）─────────────────────
  if (!is.null(ctx$results$tj_gbmtm)) {
    for (sys in names(ctx$results$tj_gbmtm)) {
      fobj <- ctx$results$tj_gbmtm[[sys]]
      inds <- fobj$long$ind[1]
      tryCatch(tj_traj_panel(fobj, inds, file.path(FD, "pdf",
        paste0("Figure 4 - trajectories (", dfname(sys), ").pdf")), fam,
        paste0("Figure 4. ", sys, " joint trajectory: ", inds)),
        error = function(e) cli::cli_alert_warning("Fig4 {sys} 跳过: {conditionMessage(e)}"))
    }
  }

  # ── Methods md + software txt ─────────────────────────────────────
  tj_write_software_versions(DR)
  m_lev <- if (!is.null(cox)) unique(cox$model) else "model4"
  writeLines(c(
    "# Methods - Joint longitudinal trajectories of incident disease", "",
    "## Study design and cohort",
    "Prospective cohort; joint group-based multi-trajectory modeling (GBMTM) of two time-varying composite indices across examination waves.",
    "Baseline prevalent outcome cases excluded. Trajectory classes assigned on observed data (EM full-information, missing waves handled under local independence).",
    "",
    "## Trajectory modeling",
    sprintf("GBMTM polynomial degree %d; candidate K = %s. Selection by AIC/BIC with AvePP >= 0.70 and smallest class >= 5%%.",
            as.integer(bl$poly_degree %||% 2), paste(as.integer(bl$k_range %||% 2:6), collapse = ",")),
    "Classes ordered by ascending trajectory risk; lowest-risk class (T1) = reference.",
    "",
    "## Statistical analysis",
    sprintf("Cox proportional hazards, sequential models: %s.", paste(m_lev, collapse = " -> ")),
    "Missing covariates multiply imputed (m >= 5) and Rubin-pooled; trajectory classes held fixed (operation layer).",
    "Subgroup interaction P from Rubin-pooled likelihood-ratio test. Sensitivity: exclude early events, remove diabetes/hypertension, complete-case, exclude lipid/glucose medication, posterior-probability weighting, follow-up-time terms.",
    "",
    "## Software",
    "See Methods_software_versions.txt. R with survival, survminer, mice, ggplot2. GBMTM via engine R/gbmtm_core.R."),
    file.path(DR, "Methods_statistical_analysis.md"))

  # ── image_information (minimal, honest) ───────────────────────────
  pdfs <- list.files(file.path(FD, "pdf"), pattern = "\\.pdf$", full.names = TRUE)
  for (p in pdfs) {
    bn <- sub("\\.pdf$", "", basename(p))
    writeLines(c(paste0("# ", bn), "", "## 图面说明",
      paste0("矢量 PDF 由 tj_pub_export 生成（", fam, " 字体）。"),
      "## 分析上下文",
      paste0("暴露 = GBMTM 联合轨迹类别（参照 T1）；结局 = ",
             (bl$outcome %||% list())$primary$name %||% "primary",
             "；体系 = ", paste(names(bl$index_pairs), collapse = ", "))),
      file.path(FD, "image_information", paste0(bn, ".md")))
  }

  # ── 收口：队列 flush（export_sci_table 默认入队）→ 格式 / 表题 / prune ──
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx <- tryCatch(flush_pub_output_queues(ctx), error = function(e) {
      cli::cli_alert_warning("表队列 flush 失败: {conditionMessage(e)}"); ctx })
  }
  # Trajectory IC → Table S2（flush 后 Out/Tables 才存在源文件）
  for (sys in names(bl$index_pairs)) {
    src <- file.path(out_root, "Tables", paste0("Table_Trajectory_IC_", sys, ".xlsx"))
    if (!file.exists(src)) {
      alt <- list.files(file.path(out_root, "Tables"), pattern = paste0("Trajectory IC.*", gsub("_", " ", sys)), full.names = TRUE)
      if (length(alt)) src <- alt[1]
    }
    if (file.exists(src)) {
      dst <- file.path(TD, paste0("Table S2 - trajectory model selection - ", dfname(sys), ".xlsx"))
      file.copy(src, dst, overwrite = TRUE)
    } else cli::cli_alert_warning("Table S2 ({sys}): 未找到 IC 源表")
  }
  if (exists("export_pub_figures", mode = "function")) {
    tryCatch(export_pub_figures(FD, meta = list(figures_dir = FD, tables_dir = TD),
      config = ctx$config, purge = TRUE), error = function(e) NULL)
  }
  if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    tryCatch(pub_sync_xlsx_a1_titles_to_filenames(TD), error = function(e) NULL)
  }
  # 三线表收口闸门：display scrub（含 pub_xlsx_enforce_three_line.py：顶线/栏目线/
  # 底线对齐最后数据行、无竖线、关网格线；值零改动、幂等）
  .prune_src <- file.path(root, "R/pub_delivery_prune.R")
  if (file.exists(.prune_src)) suppressWarnings(source(.prune_src, local = FALSE))
  if (exists("pub_delivery_scrub_display", mode = "function")) {
    tryCatch(pub_delivery_scrub_display(DR, root = root),
             error = function(e) cli::cli_alert_warning("scrub_display 跳过: {conditionMessage(e)}"))
  }
  if (exists("pub_prune_delivery_root", mode = "function")) {
    tryCatch(pub_prune_delivery_root(DR), error = function(e) cli::cli_alert_warning("prune 跳过: {conditionMessage(e)}"))
  }

  cli::cli_alert_success("tj_pub_export: 交付根 {DR} — Tables={length(list.files(TD))}, Figures/pdf={length(list.files(file.path(FD,'pdf')))}")
  invisible(ctx)
}

register_block("tj_pub_export", block_tj_pub_export, "联合轨迹发病 发表收口 Table1-3+Fig1-4+Methods+交付根")
