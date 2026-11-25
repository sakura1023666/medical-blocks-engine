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
  # 单库收口命名（2026-11-25）：dual 关闭/单库课题 → 清空 -库名 注入
  if (exists("pub_apply_naming_options", mode = "function")) {
    tryCatch(pub_apply_naming_options(ctx$config), error = function(e) NULL)
  }
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
  ## 展示层：体系/pair 名禁编程下划线（pub_no_underscore_display）；文件名仍用 dfname
  tdisp <- function(s) {
    s <- as.character(s)
    if (exists("pipeline_display_label", mode = "function")) {
      out <- tryCatch(pipeline_display_label(s), error = function(e) NULL)
      if (!is.null(out)) return(out)
    }
    gsub("_", " ", s)
  }
  prim_key <- paste0("tj_outcome_", (bl$outcome %||% list())$primary$name %||% "primary")
  prim <- ctx$results[[prim_key]] %||% ctx$results$tj_outcome_primary
  # 结局展示名（禁原始列名进表题；pub_table_xlsx 铁律 6b）
  olabel <- {
    fc <- trimws(as.character(ctx$config$attrition$fork_case_label %||% NA_character_)[1L])
    if (!is.na(fc) && nzchar(fc)) {
      fc
    } else if (exists("pipeline_outcome_case_label", mode = "function")) {
      oc <- trimws(as.character(
        tryCatch(pipeline_outcome_case_label(ctx$config), error = function(e) NA_character_)
      )[1L])
      nm <- (bl$outcome %||% list())$primary$name %||% "primary"
      if (!is.na(oc) && nzchar(oc) && !identical(tolower(oc), "case")) oc else nm
    } else {
      (bl$outcome %||% list())$primary$name %||% "primary"
    }
  }

  # ── Table 1 baseline by class（每体系）──────────────────────────────
  cont_vars <- pub$table1_cont %||% intersect(c("age","BMI_w2","TyG_w2","whtr_w2","sbp","dbp"), names(df))
  cat_vars  <- pub$table1_cat  %||% intersect(c("sex","race_white","edu","smoke","drink","hbp_d","dm_d","chol_d"), names(df))
  t1_list <- list()
  for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys); if (!gv %in% names(df)) next
    lv <- sort(unique(as.character(df[[gv]])))
    t1 <- tj_table1_by_class(df, gv, cont_vars, cat_vars, class_order = lv,
                             var_labels = pub$table1_labels)
    # 文件名/标题避免括号（export_sci_table 会剥括号导致同名覆盖）；体系名用连字符后缀
    t1_path <- file.path(TD, paste0("Table 1 - baseline by trajectory class - ", dfname(sys), ".xlsx"))
    export_sci_table(t1, t1_path,
      title = paste0("Table 1. Baseline characteristics by trajectory class - ", tdisp(sys)),
      table_footnotes = c("Mean (SD) for continuous, n (%) for binary; Kruskal-Wallis / chi-square P.",
                          "Reference class T1 = class with the lowest baseline level of the index.",
                          "Units as recorded in the source dataset; not re-scaled here."))
    t1_list[[sys]] <- t1
  }

  # ── Table 2 Cox（合并 ctx$results$tj_cox）──────────────────────────
  # 行结构（2026-11-25 修复）：每体系一行/类，T1=参照显式 "1 (reference)"；
  # 禁止 expand.grid(model×class×system) 造成同类重复 N 行（旧 bug 已踩）。
  cox <- ctx$results$tj_cox
  if (!is.null(cox) && nrow(cox)) {
    m_lev <- unique(cox$model)
    t2 <- data.frame(Class = character(0), System = character(0), check.names = FALSE)
    for (sys_i in unique(cox$system)) {
      sub_s <- cox[cox$system == sys_i, , drop = FALSE]
      c_lev <- sort(unique(c(sub_s$class, "T1")))
      for (cl in c_lev) {
        row1 <- data.frame(Class = cl, System = sys_i, check.names = FALSE)
        for (mn in m_lev) {
          r <- sub_s[sub_s$model == mn & sub_s$class == cl, , drop = FALSE]
          if (!nrow(r) || cl == "T1") { row1[[mn]] <- "1 (reference)"; next }
          # 准完全分离（HR=0 且 CI 上限 Inf）→ NE，禁止 0.000 交差
          if (isTRUE(r$HR[1] == 0) && is.infinite(r$hi[1])) { row1[[mn]] <- "NE"; next }
          cell <- sprintf("%.3f (%.3f, %.3f)", r$HR[1], r$lo[1], r$hi[1])
          row1[[mn]] <- if (r$p[1] < 0.001) paste0(cell, " <0.001") else
                        paste0(cell, sprintf(" %.3f", r$p[1]))
        }
        t2 <- rbind(t2, row1)
      }
    }
    n_ne <- sum(vapply(m_lev, function(mn) sum(t2[[mn]] == "NE"), integer(1)))
    t2$System <- tdisp(t2$System)
    fn2 <- c("Reference = T1 (lowest trajectory class) within each index system.",
             "Models sequentially add covariates.",
             "Cell format: HR (95% CI) P.",
             sprintf("Time scale = %s; see Methods.", pub$time_unit_lab %||% "months"))
    if (tryCatch(mi_rubin_enabled(ctx), error = function(e) FALSE))
      fn2 <- c(fn2, "Rubin-pooled across imputations.")
    else fn2 <- c(fn2, "Complete-case estimates (no imputation required).")
    if (n_ne) fn2 <- c(fn2, "NE = not estimable (zero events in class; quasi-complete separation).")
    export_sci_table(t2, file.path(TD, "Table 2 - Cox models by class and covariate set.xlsx"),
      title = paste0("Table 2. Hazard ratios (95% CI) for incident ", tolower(olabel),
                     " by trajectory class, sequential models"),
      table_footnotes = fn2)
    ctx$results$tj_table2_ne <- n_ne
  }

  # ── Table 3 subgroup HR + P-int ────────────────────────────────────
  sg <- ctx$results$tj_subgroup; pib <- ctx$results$tj_p_interaction
  if (!is.null(sg) && nrow(sg)) {
    disp <- sg
    disp$est <- ifelse(is.na(disp$HR), "NE",
      sprintf("%.3f (%.3f, %.3f)", disp$HR, disp$lo, disp$hi))
    disp$pv <- ifelse(is.na(disp$p), NA,
      ifelse(disp$p < 0.001, "<0.001", sprintf("%.3f", disp$p)))
    t3 <- data.frame(System = tdisp(disp$system), Subgroup = disp$subgroup, Level = disp$level,
                     N = disp$n, Events = disp$events, Class = disp$class,
                     `HR (95% CI)` = disp$est, P = disp$pv, check.names = FALSE)
    if (!is.null(pib) && nrow(pib)) {
      t3$P.int <- NA
      for (r in seq_len(nrow(pib))) {
        hit <- which(t3$System == tdisp(pib$system[r]) & t3$Subgroup == pib$subgroup[r])
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
    has_bh <- "p_bh" %in% names(sens) && any(!is.na(sens$p_bh))
    sens$pbh <- if (has_bh) ifelse(is.na(sens$p_bh), NA,
      ifelse(sens$p_bh < 0.001, "<0.001", sprintf("%.3f", sens$p_bh))) else NA_character_
    ts <- sens[, c("system","analysis","class","est","pv","pbh","m")]
    ts$system <- tdisp(ts$system)
    names(ts) <- c("System","Sensitivity analysis","Class","HR (95% CI)","P",
                   "P (FDR-adjusted)","Imputations")
    # MICE 关闭时 m 恒为 1：列名如实改为 Model fits，避免被读成「单重插补」
    rubin_on <- tryCatch(exists("mi_rubin_enabled") && isTRUE(mi_rubin_enabled(ctx)),
                         error = function(e) FALSE)
    if (!rubin_on) names(ts)[7L] <- "Model fits"
    fn_all <- c(
      "Imputations = number of imputed datasets pooled per estimate; when MICE is disabled or for complete-case analyses, 1 single (non-imputed) fit per class.",
      "Model fits = 1: multiple imputation not required (no missing covariates in the analysis set).",
      S7 = "S7 weights posterior class probabilities (>=0.1 truncation).",
      S9 = "S9 adds follow-up time main effect (linear / cubic).",
      S8 = "S8 = interval-censored complementary log-log (Weibull PH parameterisation).",
      S10 = "S10 = cross-classified median-split categories of the baseline indices (reference = both-low).",
      "P (FDR-adjusted): Benjamini-Hochberg across trajectory classes within each analysis.")
    have <- paste(sens$analysis, collapse = " ")
    keep_fn <- c(
      !rubin_on,                                  # Model fits 脚注仅 MICE 关闭时出
      grepl("S7", have), grepl("S9", have), grepl("S8", have),
      grepl("S10", have), TRUE)
    # 首条（Imputations）始终保留
    fn <- c(fn_all[1L], fn_all[-1L][keep_fn])
    fn <- c(fn, sprintf("Analyses run: %s.", paste(sort(unique(sens$analysis)), collapse = ", ")))
    export_sci_table(ts, file.path(TD, "Table S1 - sensitivity analyses.xlsx"),
      title = paste0("Table S1. Sensitivity analyses of trajectory class and incident ",
                     tolower(olabel)),
      table_footnotes = fn)
  }
  # ── Table 4 Fine-Gray competing risk（tj_fg 存在时）───────────────
  fg <- ctx$results$tj_fg
  if (!is.null(fg) && nrow(fg)) {
    fgf <- fg[!is.na(fg$sHR), , drop = FALSE]
    if (nrow(fgf)) {
      fgf$est <- sprintf("%.3f (%.3f, %.3f)", fgf$sHR, fgf$lo, fgf$hi)
      fgf$pv  <- ifelse(fgf$p < 0.001, "<0.001", sprintf("%.3f", fgf$p))
      t4 <- fgf[, c("system", "outcome", "model", "class", "est", "pv", "method",
                    "n_events", "n_competing")]
      t4$system <- tdisp(t4$system)
      names(t4) <- c("System", "Outcome", "Model", "Class", "sHR (95% CI)", "P",
                     "Method", "Events", "Competing events")
      comp_note <- (ctx$results$tj_fg_note %||% "all-cause death")
      export_sci_table(t4, file.path(TD, "Table 4 - Fine-Gray competing risk by class.xlsx"),
        title = "Table 4. Subdistribution hazard ratios for incident disease by trajectory class (Fine-Gray)",
        table_footnotes = c(paste0("Competing event = ", comp_note,
                                   "; sHR from cmprsk::crr (failcode = primary event)."),
                            "Cause-specific Cox fallback (see Method column) when cmprsk unavailable.",
                            "Rubin pooled across MICE imputations when enabled; complete#1 otherwise."))
    }
  }

  # ── Figure 1 attrition flowchart ──────────────────────────────────
  fig1_rows <- NULL
  tryCatch({
    rows <- attrition_finalize_rows(ctx, ctx$config)
    fig1_rows <- rows
    # 逐步纳排落 _internal CSV（不进发表 Tables；供 image_information 与 QC 交叉分母）
    tryCatch({
      idir <- file.path(out_root, "_internal"); dir.create(idir, showWarnings = FALSE, recursive = TRUE)
      if (!is.null(rows) && nrow(rows))
        write.csv(rows, file.path(idir, "Flowchart_attrition.csv"), row.names = FALSE)
    }, error = function(e) invisible(NULL))
    attrition_draw_pdf(rows, "Figure 1. Study flowchart",
                       file.path(FD, "pdf", "Figure 1 - flowchart.pdf"), font_family = fam)
  }, error = function(e) cli::cli_alert_warning("Fig1 跳过: {conditionMessage(e)}"))

  # ── Figure 2 KM by class（每体系）─────────────────────────────────
  tu_lab <- pub$time_unit_lab %||% "Follow-up (months)"
  # olabel 已在函数前段定义（attrition$fork_case_label 优先）
  if (!is.null(prim)) for (sys in names(bl$index_pairs)) {
    gv <- paste0(prefix, sys); if (!gv %in% names(df)) next
    tryCatch(tj_km_pdf(df, gv, prim$event, prim$time,
      file.path(FD, "pdf", paste0("Figure 2 - KM by class (", dfname(sys), ").pdf")),
      paste0("Figure 2. ", tdisp(sys), " trajectory classes: incident ", olabel), fam,
      time_unit_lab = tu_lab),
      error = function(e) cli::cli_alert_warning("Fig2 {sys} 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 3 adjusted HR forest ───────────────────────────────────
  mn_last <- tail(unique(cox$model), 1)
  mn_disp0 <- sub("^model", "Model ", tolower(as.character(mn_last %||% "")), ignore.case = TRUE)
  if (!is.null(cox) && nrow(cox) && !is.null(mn_last)) {
    fr <- cox[cox$model == mn_last, , drop = FALSE]
    # 零事件类（准完全分离 HR=0/CI=Inf）不可上图（假竖线）；Table 2 已标 NE
    sep_bad <- !is.na(fr$HR) & fr$HR == 0 & is.infinite(fr$hi)
    if (any(sep_bad)) {
      cli::cli_alert_info("Fig3: 剔除 {sum(sep_bad)} 个不可估类（0 事件分离）")
      fr <- fr[!sep_bad, , drop = FALSE]
    }
    # 行名 = 体系 + 类别（禁原始结局列名 "(pe)"；结局名已写进标题）
    fr$lab <- paste0(tdisp(fr$system), " ", fr$class)
    fr <- fr[order(fr$HR), ]
    tryCatch(tj_forest_pdf(fr, file.path(FD, "pdf", "Figure 3 - adjusted HR forest.pdf"),
      paste0("Figure 3. Adjusted ", olabel, " HR by trajectory class (", mn_disp0, ")"), fam),
      error = function(e) cli::cli_alert_warning("Fig3 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 4 trajectory panels（每体系每指标）─────────────────────
  if (!is.null(ctx$results$tj_gbmtm)) {
    for (sys in names(ctx$results$tj_gbmtm)) {
      fobj <- ctx$results$tj_gbmtm[[sys]]
      inds <- fobj$long$ind[1]
      # 标题自适应：单指标不写 joint、不重复 sys:ind；多指标才用 joint 措辞
      n_inds <- length(unique(fobj$long$ind))
      f4_title <- if (n_inds <= 1L) {
        paste0("Figure 4. Latent trajectory classes of ", tdisp(inds))
      } else {
        paste0("Figure 4. Joint trajectory of ", paste(tdisp(inds), collapse = " and "))
      }
      tryCatch(tj_traj_panel(fobj, inds, file.path(FD, "pdf",
        paste0("Figure 4 - trajectories (", dfname(sys), ").pdf")), fam, f4_title),
        error = function(e) cli::cli_alert_warning("Fig4 {sys} 跳过: {conditionMessage(e)}"))
    }
  }

  # ── Methods md + software txt ─────────────────────────────────────
  tj_write_software_versions(DR)
  m_lev <- if (!is.null(cox) && nrow(cox)) unique(cox$model) else "model4"
  # Methods 自适应（2026-11-25，65_pre-eclampsia 单指标/0%缺失/无死亡场景踩坑）：
  # 体系数、插补是否启用、竞争是否做、敏感性实跑项 —— 禁止与实际运行不符的模板默认句
  npair <- length(bl$index_pairs)
  pair_len <- max(1L, as.integer(vapply(bl$index_pairs, length, integer(1))))
  sys_word <- if (pair_len == 1L) "single-index group-based trajectory" else
    sprintf("joint %d-index group-based multi-trajectory", pair_len)
  mi_on <- isTRUE(ctx$config$imputation$enable) &&
    tryCatch(mi_rubin_enabled(ctx), error = function(e) FALSE)
  mi_lines <- if (mi_on) {
    sprintf("Missing covariates multiply imputed (m = %d) and Rubin-pooled; trajectory classes held fixed (operation layer).",
            as.integer(ctx$results$mice_model$m %||% ctx$config$imputation$m %||% 5L))
  } else {
    "No covariate imputation was required (complete covariate data); all estimates are from the observed cohort."
  }
  cr_on <- isTRUE((bl$competing_risk %||% list())$enable)
  cr_line <- paste0("Competing-risk analysis (Fine-Gray subdistribution): ",
    if (cr_on) (ctx$results$tj_fg_note %||% "enabled.") else
      "not applicable in this cohort (no mortality follow-up).")
  sens_done <- if (!is.null(sens) && nrow(sens)) sort(unique(as.character(sens$analysis))) else character(0)
  writeLines(c(
    paste0("# Methods - Longitudinal trajectories and incident ",
           toupper((bl$outcome %||% list())$primary$name %||% "outcome")), "",
    "## Study design and cohort",
    sprintf("Prospective cohort; %s modeling (GBMTM) of time-varying indices across examination waves.", sys_word),
    if (!is.null(bl$age_filter) && nzchar(as.character(bl$age_filter)[1L]))
      paste0("Inclusion: ", bl$age_filter, ".") else
      "All eligible enrolled participants analysed; no age restriction applied.",
    "Baseline prevalent outcome cases excluded where identifiable. Trajectory classes assigned on observed data (EM full-information, missing waves handled under local independence).",
    "",
    "## Trajectory modeling",
    sprintf("GBMTM polynomial degree %d; candidate K = %s. Selection by AIC/BIC with AvePP >= %.2f and smallest class >= %.0f%%.",
            as.integer(bl$poly_degree %||% 2), paste(as.integer(bl$k_range %||% 2:6), collapse = ","),
            as.numeric(bl$avepp_min %||% 0.70), 100 * as.numeric(bl$min_prop_floor %||% 0.05)),
    "Classes ordered by ascending trajectory risk; lowest-risk class (T1) = reference.",
    "",
    "## Statistical analysis",
    sprintf("Cox proportional hazards, sequential models: %s.", paste(m_lev, collapse = " -> ")),
    mi_lines,
    paste0("Subgroup interaction P from ", if (mi_on) "Rubin-pooled " else "",
           "likelihood-ratio test. Benjamini-Hochberg FDR adjustment applied across trajectory groups."),
    sprintf("Sensitivity analyses performed: %s. Analyses requiring columns absent in this dataset were skipped and are not reported.",
            if (length(sens_done)) paste(sens_done, collapse = ", ") else "none estimable"),
    cr_line,
    "",
    "## Software",
    paste0("See Methods_software_versions.txt. R with survival, survminer, ggplot2",
           if (mi_on) " and mice" else "",
           ". GBMTM via engine R/gbmtm_core.R."),
    # 课题级补充（config$joint_trajectory$pub$methods_extra）：
    #   limitations = character vector -> "## Limitations" 节（时点/EPV/口径必写）
    #   design      = character vector -> 追加到 Study design and cohort 之后
    local({
      mx <- (bl$pub %||% list())$methods_extra
      if (!is.list(mx)) return(character(0))
      out <- character(0)
      if (length(mx$design)) out <- c(out, "", "## Additional design notes", mx$design)
      if (length(mx$analysis)) out <- c(out, "", "## Additional analysis notes", mx$analysis)
      if (length(mx$limitations)) out <- c(out, "", "## Limitations",
                                           sprintf("%d. %s", seq_along(mx$limitations), mx$limitations))
      out
    })
  ), file.path(DR, "Methods_statistical_analysis.md"))

  # ── image_information（多段图面说明 + 图上标注数字，只从实体收获）──
  .tj_fmt_p <- function(pv) {
    if (!is.finite(pv)) return("未收获")
    if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
  }
  # 整数展示：千分位但不右对齐补空格（避免 md 里 "n =  23" 双空格）
  .tj_int <- function(x) {
    v <- suppressWarnings(as.integer(x))
    vapply(v, function(k) if (is.na(k)) "NA" else format(k, big.mark = ",", trim = TRUE),
           character(1))
  }
  .km_harvest <- function(sys) {
    gv <- paste0(prefix, sys); if (!gv %in% names(df)) return(NULL)
    if (is.null(prim)) return(NULL)
    d2 <- df[!is.na(df[[gv]]), , drop = FALSE]
    d2$.ev <- as.integer(prim$event[match(rownames(d2), rownames(df))])
    d2$.tm <- as.numeric(prim$time[match(rownames(d2), rownames(df))])
    d2 <- d2[!is.na(d2$.tm) & d2$.tm > 0 & !is.na(d2$.ev), , drop = FALSE]
    d2$.g <- factor(d2[[gv]])
    if (nlevels(d2$.g) < 2) return(NULL)
    lr <- survival::survdiff(stats::as.formula("survival::Surv(.tm, .ev) ~ .g"), data = d2)
    pv <- stats::pchisq(lr$chisq, df = length(lr$n) - 1L, lower.tail = FALSE)
    data.frame(class = levels(d2$.g), n = as.integer(lr$n),
               events = as.integer(tapply(d2$.ev, d2$.g, sum)), p = pv)
  }
  .pair_len0 <- max(1L, as.integer(vapply(bl$index_pairs, length, integer(1))))
  .word_sys  <- if (.pair_len0 <= 1L) "单指标" else "多指标联合"
  .n_waves <- length(bl$waves %||% 1:3)
  # olabel 已在 Fig2 段前定义（attrition$fork_case_label 优先）
  .ctx_common <- paste0(
    "数据库 = ", (bl$pub %||% list())$database_label %||% "Prospective cohort",
    "（单队列，非拼图）；分析集 N = ", .tj_int(nrow(df)),
    "；结局 = ", olabel,
    "，事件 ", .tj_int(sum(as.integer(prim$event %||% 0), na.rm = TRUE)),
    sprintf("；时间尺度 = %s；访视波次 = %d", tu_lab, .n_waves),
    sprintf("；暴露 = %s GBMTM 潜轨迹类别（参照类 = 每组 T1；T1 按指标取值定为基线低/中/持续低水平组，非统一「最低风险」）；", .word_sys),
    "体系 = ", paste(vapply(names(bl$index_pairs), tdisp, character(1)), collapse = ", "))
  pdfs <- list.files(file.path(FD, "pdf"), pattern = "\\.pdf$", full.names = TRUE)
  for (p in pdfs) {
    bn <- sub("\\.pdf$", "", basename(p))
    # Figure 1 纳排图：逐步保留 n + 本步排除人数（pub_figure_image_information 铁律 §4）
    if (grepl("flowchart", bn, ignore.case = TRUE) && !is.null(fig1_rows) && nrow(fig1_rows)) {
      steps_txt <- character(0)
      prev_n <- NA_integer_
      for (ri in seq_len(nrow(fig1_rows))) {
        nn <- suppressWarnings(as.integer(fig1_rows$n[ri]))
        st <- as.character(fig1_rows$step[ri])
        ex <- as.character(fig1_rows$exclude_label[ri])
        line <- if (!is.na(nn)) sprintf("- %s: n = %s", st, .tj_int(nn)) else paste0("- ", st)
        if (!is.na(nn) && !is.na(prev_n) && prev_n > nn)
          line <- sprintf("%s（本步排除 %s 人）", line, .tj_int(prev_n - nn))
        if (!is.na(ex) && nzchar(ex) && ex != "NA") line <- paste0(line, "；Exclude: ", ex)
        # 末步底部分叉：结局两组人数（图上粉/绿框）
        if (ri == nrow(fig1_rows) &&
            all(c("fork_left_label", "fork_left_n") %in% names(fig1_rows))) {
          fl <- suppressWarnings(as.integer(fig1_rows$fork_left_n[ri]))
          frn <- suppressWarnings(as.integer(fig1_rows$fork_right_n[ri]))
          if (is.finite(frn)) {
            line <- sprintf("%s；分叉 %s = %s，%s = %s", line,
              as.character(fig1_rows$fork_left_label[ri]), .tj_int(fl),
              as.character(fig1_rows$fork_right_label[ri]), .tj_int(frn))
          }
        }
        steps_txt <- c(steps_txt, line)
        if (!is.na(nn)) prev_n <- nn
      }
      fig1_body <- c(
        paste0("CONSORT 纳排流程图（矢量 PDF，", fam, " 字体）：主列为逐步纳入人群，右侧 Exclude 框写各步真实剔除原因与人数；底部按结局状态分叉为发生与未发生两组。"),
        "",
        "图上逐步保留人数：", steps_txt)
      writeLines(c(paste0("# ", bn), "", "## 图面说明", fig1_body,
        "## 分析上下文", .ctx_common),
        file.path(FD, "image_information", paste0(bn, ".md")))
      next
    }
    ## Fig2/3/4：按铁律写「多段图面说明 + 图上标注数字（只从实体收获）+ 分析上下文」
    body_i <- NULL
    sys_i <- sub("^.* \\(([^)]+)\\)$", "\\1", bn)
    if (grepl("KM by class|trajectories", bn, ignore.case = TRUE) &&
        nzchar(sys_i) && !identical(sys_i, bn) && sys_i %in% names(bl$index_pairs)) {
      gvi <- paste0(prefix, sys_i)
      k_lv <- if (gvi %in% names(df)) sort(unique(as.character(df[[gvi]]))) else character(0)
      k_n <- if (length(k_lv)) as.integer(table(factor(df[[gvi]], levels = k_lv))) else integer(0)
      if (grepl("KM by class", bn, ignore.case = TRUE)) {
        kh <- .km_harvest(sys_i)
        body_i <- c(
          sprintf(paste0("Kaplan–Meier 曲线：按 %s 潜轨迹类别比较自入组起至首次 ", olabel,
                         " 的发生概率；横轴为随访时间（", tu_lab,
                         "），纵轴为无事件生存概率；图例与 Number at risk 行名即类别标签（T1 起），",
                         "风险表首列为入组时点全体风险人数。"), tdisp(sys_i)),
          "",
          "图上标注：",
          "",
          if (!is.null(kh)) c(
            sprintf("- Log-rank P = %s", .tj_fmt_p(kh$p[1])),
            sprintf("- %s: n = %s，事件 %s", kh$class,
                    .tj_int(kh$n), .tj_int(kh$events))) else "- Log-rank P / 各层 n：未收获",
          "")
      } else {
        fobj_i <- ctx$results$tj_gbmtm[[sys_i]]
        body_i <- c(
          sprintf(paste0("潜类别均值轨迹图：%s 在 %d 个访视波次（横轴 Examination wave 1-%d）上的组内均值轨迹；",
                         "纵轴为标准化指标水平（z 尺度）；每条彩色线为一个 GBMTM 潜类别均值，",
                         "类别数由 IC/AIC-BIC 选型锁定。"), tdisp(sys_i), .n_waves, .n_waves),
          "",
          "图上标注：",
          "",
          if (length(k_n)) sprintf("- %s：n = %s", k_lv, .tj_int(k_n)) else "- 类别样本量：未收获",
          "")
      }
    } else if (grepl("adjusted HR forest", bn, ignore.case = TRUE)) {
      fr2 <- if (!is.null(cox) && nrow(cox)) cox[cox$model == mn_last, , drop = FALSE] else NULL
      ne_n <- 0L
      if (!is.null(fr2)) {
        sep_i <- !is.na(fr2$HR) & fr2$HR == 0 & is.infinite(fr2$hi)
        ne_n <- sum(sep_i)
        fr2 <- fr2[!sep_i, , drop = FALSE]
        fr2$lab2 <- paste0(tdisp(fr2$system), " ", fr2$class)
        fr2 <- fr2[order(fr2$HR), ]
      }
      mn_disp <- sub("^model", "Model ", tolower(as.character(mn_last)), ignore.case = TRUE)
      body_i <- c(
        sprintf("森林图：%s（最完整调整模型）下，各指标体系轨迹类别相对参照类（T1）的发病 HR（95%% CI，对数刻度）；灰色虚线为无效线 HR = 1，红点为点估计。行名 = 体系 + 类别。",
                mn_disp),
        "",
        "图上标注：",
        "",
        if (!is.null(fr2) && nrow(fr2))
          sprintf("- %s: HR %.3f (%.3f-%.3f), P %s", fr2$lab2, fr2$HR, fr2$lo, fr2$hi,
                  vapply(fr2$p, .tj_fmt_p, character(1))) else "- 各行 HR：未收获",
        "",
        if (ne_n > 0L) sprintf("注：%d 个类别因 0 事件（准完全分离）不可估计，未上图，在 Table 2 中标 NE。", ne_n) else "")
    }
    if (is.null(body_i))
      body_i <- paste0("矢量 PDF 由 tj_pub_export 生成（", fam, " 字体）。")
    writeLines(c(paste0("# ", bn), "", "## 图面说明", body_i,
      "## 分析上下文", .ctx_common),
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
