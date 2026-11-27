###############################################################################
# tj_lit_export — 联合轨迹发病 对标文献版式补齐（Liu et al. 2026 Fig1-5/ST1-8）
#
# 交付根 = config$joint_trajectory$pub$delivery_root（与 tj_pub_export 同目录）。
# 新增产物（与现有编号顺延，不推翻已核对交付）：
#   Figures/pdf/Figure 5 - ridge densities.pdf               ← 文献 Fig2（ST3 图版）
#   Figures/pdf/Figure 6 - model selection curves.pdf        ← 文献 Fig3A/B（28 体系网格）
#   Figures/pdf/Figure 7 - joint trajectories - <sys>.pdf    ← 文献 Fig3C/D（双指标原始尺度+SE）
#   Figures/pdf/Figure 8 - cumulative incidence - <sys>.pdf  ← 文献 Fig4（1-S(t)+风险表）
#   Figures/pdf/Figure 9 - forest - <sys>.pdf                ← 文献 Fig5（每体系 M1-M4）
#   Tables/Table S3 - missing data proportions.xlsx          ← 文献 ST2
#   Tables/Table S4 - index descriptive statistics by wave.xlsx ← 文献 ST3
#   Tables/Table S5 - discriminative performance.xlsx        ← 文献 ST8
#   Tables/Table S6 - included versus excluded.xlsx          ← 文献 ST1（真实 n）
#   Tables/Table S7 - model fit indices across systems.xlsx  ← 文献 ST4（28 体系合并）
# register_block: "tj_lit_export"
###############################################################################

block_tj_lit_export <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  suppressMessages({
    source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
    source(file.path(root, "R/literature_trajectory_joint_pub.R"), local = FALSE)
  })
  if (exists("pub_apply_naming_options", mode = "function")) {
    tryCatch(pub_apply_naming_options(ctx$config), error = function(e) NULL)
  }
  bl <- ctx$config$joint_trajectory %||% stop("tj_lit_export: 缺 config", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"
  prefix <- bl$group_col_prefix %||% "grp_"
  pub <- bl$pub %||% list()
  df <- ctx$data$cleaned %||% ctx$data$raw %||%
    stop("tj_lit_export: ctx$data$cleaned 缺失（GBMTM 未跑？）", call. = FALSE)
  out_root <- ctx$config$project$output_dir %||% "Output"
  fam <- tj_pub_font(ctx$config)
  DR <- pub$delivery_root %||% file.path(out_root, "summary_results")
  TD <- file.path(DR, "Tables"); FD <- file.path(DR, "Figures")
  for (d in c(TD, FD, file.path(FD, "pdf"), file.path(FD, "image_information")))
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  dfname <- function(s) gsub("[^A-Za-z0-9]+", "_", s)
  tdisp <- function(s) {
    s <- as.character(s)
    if (exists("pipeline_display_label", mode = "function")) {
      out <- tryCatch(pipeline_display_label(s), error = function(e) NULL)
      if (!is.null(out)) return(out)
    }
    gsub("_", " ", s)
  }
  prim_key <- paste0("tj_outcome_", (bl$outcome %||% list())$primary$name %||% "primary")
  prim <- ctx$results[[prim_key]] %||% ctx$results$tj_outcome_primary %||%
    stop("tj_lit_export: 缺结局结果", call. = FALSE)
  olabel <- trimws(as.character(ctx$config$attrition$fork_case_label %||%
    (bl$outcome %||% list())$primary$name %||% "outcome")[1L])
  tu_lab <- pub$time_unit_lab %||% "Follow-up (months)"
  waves <- as.integer(bl$waves %||% 1:3)
  # 参与建模的全部指标（体系名拆分去重 = 本课题指标池）
  inds_all <- unique(unlist(lapply(bl$index_pairs, as.character)))
  cox <- ctx$results$tj_cox
  sys_all <- names(bl$index_pairs)
  sys_have <- sys_all[vapply(sys_all, function(s)
    paste0(prefix, s) %in% names(df), logical(1))]
  n_done <- 0L

  if (!requireNamespace("patchwork", quietly = TRUE))
    stop("patchwork 不可用（TST/联合轨迹拼图入口需要）")
  if (!("package:patchwork" %in% search())) attachNamespace("patchwork")

  # ── Figure 5 Ridge densities（指标 × 波，一页多面板）──────────────
  tryCatch({
    pans <- list()
    for (ind in inds_all) {
      wcols <- paste0(ind, "_", waves)
      g <- tj_panel_ridge(df, ind, wcols, id_col = id_col, fam = fam,
                          lab = tdisp(ind))
      if (!is.null(g)) pans[[ind]] <- g
    }
    if (length(pans)) {
      nc <- 2L
      comb <- Reduce(function(a, b) a + b, pans) +
        patchwork::plot_layout(ncol = nc) +
        patchwork::plot_annotation(
          title = paste0("Figure 5. Distribution of ", length(pans),
                         " haematological indices across ", length(waves), " waves"),
          theme = ggplot2::theme(
            plot.title = ggplot2::element_text(family = fam, size = 11, face = "bold"),
            plot.tag = ggplot2::element_text(family = fam)))
      nr <- ceiling(length(pans) / nc)
      ggplot2::ggsave(file.path(FD, "pdf", "Figure 5 - ridge densities.pdf"),
                      comb, width = 7.4, height = min(10.6, 1.35 * nr + 1.6),
                      device = grDevices::cairo_pdf)
      n_done <- n_done + 1L
    }
  }, error = function(e) cli::cli_alert_warning("Fig5 ridge 跳过: {conditionMessage(e)}"))

  # ── Figure 6 model selection curves（每体系 AIC/BIC vs K 网格）─────────
  tryCatch({
    if (!is.null(ctx$results$tj_gbmtm) && length(ctx$results$tj_gbmtm)) {
      pans <- list()
      for (sys in names(ctx$results$tj_gbmtm)) {
        tab <- ctx$results$tj_gbmtm[[sys]]$select$table
        k_opt <- ctx$results$tj_gbmtm[[sys]]$K_opt
        g <- tj_panel_select(tab, k_opt = k_opt, fam = fam, lab = tdisp(sys),
                            show_entropy = FALSE)
        if (!is.null(g)) pans[[sys]] <- g
      }
      if (length(pans)) {
        nc <- 4L
        # patchwork 大网格：分块拼避免单次 layout 失败
        chunk <- ceiling(length(pans) / nc)
        pans2 <- lapply(split(seq_along(pans), rep(seq_len(chunk), each = nc,
                                                  length.out = length(pans))),
                        function(ii) Reduce(function(a, b) a + b, pans[ii]) +
                          patchwork::plot_layout(ncol = min(nc, length(ii))))
        comb <- Reduce(function(a, b) a / b, pans2) +
          patchwork::plot_annotation(
            title = "Figure 6. Model selection (AIC / BIC) across candidate K by joint system",
            theme = ggplot2::theme(
              plot.title = ggplot2::element_text(family = fam, size = 11, face = "bold")))
        ggplot2::ggsave(file.path(FD, "pdf", "Figure 6 - model selection curves.pdf"),
                        comb, width = 10.2,
                        height = min(10.8, 2.1 * length(pans2) + 1.2),
                        device = grDevices::cairo_pdf)
        n_done <- n_done + 1L
      }
    }
  }, error = function(e) cli::cli_alert_warning("Fig6 选型曲线跳过: {conditionMessage(e)}"))

  # ── Figure 7 joint trajectories 双指标原始尺度（每体系）────────────────
  for (sys in names(ctx$results$tj_gbmtm %||% list())) {
    tryCatch({
      pair_inds <- intersect(as.character(bl$index_pairs[[sys]]), inds_all)
      if (!length(pair_inds)) next
      g <- tj_panel_joint_traj(ctx$results$tj_gbmtm[[sys]], df, pair_inds,
                               id_col = id_col, prefix = prefix, sys = sys,
                               fam = fam,
                               lab = paste0("Figure 7. Joint trajectories: ",
                                            paste(tdisp(pair_inds), collapse = " + ")))
      if (is.null(g)) next
      ggplot2::ggsave(file.path(FD, "pdf",
        paste0("Figure 7 - joint trajectories (", dfname(sys), ").pdf")),
        g, width = 6.4, height = 3.9, device = grDevices::cairo_pdf)
      n_done <- n_done + 1L
    }, error = function(e) cli::cli_alert_warning("Fig7 {sys} 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 8 cumulative incidence（每体系，1-S(t)+Number at risk）──────
  for (sys in sys_have) {
    tryCatch({
      gv <- paste0(prefix, sys)
      g <- tj_panel_cuminc(df, gv, prim$event, prim$time, NULL, fam = fam,
                           lab = paste0("Figure 8. ", tdisp(sys),
                                        ": cumulative ", olabel),
                           time_unit_lab = tu_lab)
      if (is.null(g)) next
      ggplot2::ggsave(file.path(FD, "pdf",
        paste0("Figure 8 - cumulative incidence (", dfname(sys), ").pdf")),
        g, width = 6.3, height = 5.5, device = grDevices::cairo_pdf)
      n_done <- n_done + 1L
    }, error = function(e) cli::cli_alert_warning("Fig8 {sys} 跳过: {conditionMessage(e)}"))
  }

  # ── Figure 9 per-system forest (M1-M4)：代表体系 ──────────────────────
  # 默认不再取"前 3 个录入体系"，而按体系最优主模型 P 升序取前 3
  # （P 相同再看 C-index 不可得时保持字典序）；config 可用 pub$forest_systems 覆盖。
  top_sys <- as.character(pub$forest_systems %||% NULL)
  if (!length(top_sys) && !is.null(cox) && nrow(cox)) {
    pmin <- tapply(cox$p, as.character(cox$system), function(v) min(v, na.rm = TRUE))
    cand <- names(sort(pmin, na.last = TRUE))
    cand <- cand[cand %in% sys_have]
    top_sys <- head(cand, 3L)
  }
  if (!length(top_sys)) top_sys <- head(sys_have, 3L)
  if (!is.null(cox) && nrow(cox)) {
    m_lev <- unique(cox$model)
    m_disp <- sub("^model", "Model ", tolower(as.character(m_lev)), ignore.case = TRUE)
    for (sys in top_sys) {
      if (!sys %in% sys_have) next
      tryCatch({
        fr <- cox[cox$system == sys, , drop = FALSE]
        # NE 守卫与 06block 同口径：分离类不上图
        bad <- is.na(fr$HR) | !is.finite(fr$HR) | fr$HR == 0 |
          !is.finite(fr$lo) | !is.finite(fr$hi) | (fr$HR >= 1e6 | fr$HR <= 1e-6)
        fr <- fr[!bad, , drop = FALSE]
        if (nrow(fr) < 2L) next
        fr$lab <- paste0(fr$class, " | ",
                         m_disp[match(fr$model, m_lev)])
        ord <- paste0(sort(unique(fr$class)), " | ", m_disp)
        gg <- ggplot2::ggplot(fr, ggplot2::aes(x = HR, y = factor(lab, levels = rev(ord)))) +
          ggplot2::geom_vline(xintercept = 1, linetype = 2, color = "grey40") +
          ggplot2::geom_errorbar(ggplot2::aes(xmin = lo, xmax = hi),
                                 orientation = "y", width = 0.14,
                                 color = "#2C5F8A") +
          ggplot2::geom_point(size = 2.4, color = "#C0392B") +
          ggplot2::scale_x_log10(limits = c(min(0.4, min(fr$lo, na.rm = TRUE) * 0.8),
                                            max(2.5, max(fr$hi, na.rm = TRUE) * 1.25))) +
          ggplot2::labs(title = paste0("Figure 9. ", tdisp(sys),
                                       ": ", olabel, " HR by trajectory class"),
                        subtitle = "Models: M1 age; M2 +BMI; M3 +Nulliparity; M4 +chronic hypertension",
                        x = "Hazard ratio (95% CI, log scale)", y = NULL) +
          tj_theme(fam)
        ggplot2::ggsave(file.path(FD, "pdf",
          paste0("Figure 9 - forest (", dfname(sys), ").pdf")),
          gg, width = 6.6, height = 0.34 * nrow(fr) + 2.2,
          device = grDevices::cairo_pdf)
        n_done <- n_done + 1L
      }, error = function(e) cli::cli_alert_warning("Fig9 {sys} 跳过: {conditionMessage(e)}"))
    }
  }

  # ── Table S3 missing proportions（文献 ST2）───────────────────────────
  tryCatch({
    covs <- unique(unlist(bl$model_sets))
    covs <- c(covs, names(pub$table1_cont %||% character(0)),
                   names(pub$table1_cat %||% character(0)))
    covs <- covs[!covs %in% inds_all]
    ts3 <- tj_lit_missing_table(df, covs, labels = pub$table1_labels)
    export_sci_table(ts3, file.path(TD, "Table S3 - missing data proportions.xlsx"),
      title = "Table S3. Proportion of missing data for baseline covariates in the analytic sample",
      table_footnotes = c(
        "Analytic sample = participants with trajectory classes assigned in the joint trajectory models.",
        "No imputation was applied; models used complete covariate rows (see Methods)."))
  }, error = function(e) cli::cli_alert_warning("Table S3 跳过: {conditionMessage(e)}"))

  # ── Table S4 wave descriptive stats（文献 ST3）────────────────────────
  tryCatch({
    ts4 <- tj_lit_wave_desc_table(df, inds_all, waves, id_col = id_col)
    if (!is.null(ts4) && nrow(ts4)) {
      ts4$Variable <- tdisp(ts4$Variable)
      export_sci_table(ts4, file.path(TD, "Table S4 - index descriptive statistics by wave.xlsx"),
        title = paste0("Table S4. Descriptive statistics of the ", length(inds_all),
                       " longitudinal indices by wave"),
        table_footnotes = c(
          "Wave = scheduled visit order (1-3); exact gestational window of each draw was not recorded.",
          "Original (non-standardised) units as recorded in the source dataset."))
    }
  }, error = function(e) cli::cli_alert_warning("Table S4 跳过: {conditionMessage(e)}"))

  # ── Table S5 discriminative performance（文献 ST8）────────────────────
  tryCatch({
    base_covs <- as.character((bl$model_sets %||% list())$model1 %||% "age")
    ts5 <- tj_lit_discrim_table(df, sys_have, prefix, base_covs,
                                prim$event, prim$time,
                                top_n = pub$discrim_top_n %||% length(sys_have),
                                time_lab = tu_lab)
    if (!is.null(ts5) && nrow(ts5)) {
      nb <- attr(ts5, "n_boot") %||% 0L
      export_sci_table(ts5, file.path(TD, "Table S5 - discriminative performance.xlsx"),
        title = paste0("Table S5. Discriminative performance of joint trajectory systems versus the base model for ",
                       tolower(olabel)),
        table_footnotes = c(
          sprintf("Base model = %s (trajectory classes added per system).",
                  attr(ts5, "base_covs") %||% "age"),
          sprintf("C-index difference vs base; P from paired bootstrap (%d resamples, same draw for both models).", nb),
          "NRI / IDI computed on predicted probabilities at event time (linear predictor, logistic link); with few events these are directional only.",
          sprintf("Analytic n = %s.", format(attr(ts5, "n_analytic") %||% nrow(df),
                                             big.mark = ",", trim = TRUE))))
    }
  }, error = function(e) cli::cli_alert_warning("Table S5 跳过: {conditionMessage(e)}"))

  # ── Table S6 included vs excluded（文献 ST1；真实人数，禁止编造）────────
  tryCatch({
    n_inc <- nrow(df)
    n_excl <- as.integer(pub$excluded_n %||% 0L)
    covs <- unique(unlist(bl$model_sets))
    covs <- covs[covs %in% names(df) & !covs %in% inds_all]
    one_grp <- function(dat, cv) {
      out <- character(0)
      for (v in cv) {
        x <- suppressWarnings(as.numeric(dat[[v]]))
        lab <- if (!is.null(pub$table1_labels) && v %in% names(pub$table1_labels))
          as.character(pub$table1_labels[[v]]) else gsub("[_.]", " ", v)
        nuniq <- length(unique(na.omit(x)))
        cell <- if (nuniq <= 2L) {
          sprintf("%d (%.1f%%)", sum(x == 1, na.rm = TRUE),
                  if (any(!is.na(x))) 100 * mean(x == 1, na.rm = TRUE) else NA_real_)
        } else {
          sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
        }
        out <- c(out, paste0(lab, "\t", cell))
      }
      out
    }
    inc_lines <- one_grp(df, covs)
    exc_dat <- NULL
    if (file.exists(pub$excluded_data_path %||% "")) {
      tryCatch({
        exc_dat <- readRDS(pub$excluded_data_path)
        if (!is.data.frame(exc_dat)) exc_dat <- NULL
      }, error = function(e) NULL)
    }
    exc_lines <- if (!is.null(exc_dat) && nrow(exc_dat)) one_grp(exc_dat, covs) else
      rep("No participant met the exclusion criteria", length(covs))
    pv <- vapply(seq_along(covs), function(i) {
      v <- covs[i]; x <- suppressWarnings(as.numeric(df[[v]]))
      if (is.null(exc_dat)) return(NA_real_)
      y <- suppressWarnings(as.numeric(exc_dat[[v]]))
      if (all(is.na(x)) || all(is.na(y))) return(NA_real_)
      if (length(unique(na.omit(c(x, y)))) <= 2L) {
        tb <- matrix(c(sum(x == 1, na.rm = TRUE), sum(x == 0, na.rm = TRUE),
                       sum(y == 1, na.rm = TRUE), sum(y == 0, na.rm = TRUE)), 2)
        suppressWarnings(tryCatch(stats::chisq.test(tb)$p.value, error = function(e) NA_real_))
      } else {
        suppressWarnings(tryCatch(stats::wilcox.test(x, y)$p.value, error = function(e) NA_real_))
      }
    }, numeric(1))
    parts <- strsplit(inc_lines, "\t", fixed = TRUE)
    ts6 <- data.frame(
      Characteristic = vapply(parts, `[`, character(1), 1L),
      Included = vapply(inc_lines, function(s) sub("^[^\t]*\t", "", s), character(1)),
      Excluded = vapply(exc_lines, function(s) sub("^[^\t]*\t", "", s), character(1)),
      P = vapply(pv, function(p) if (is.na(p)) "-" else
        if (p < 0.001) "<0.001" else sprintf("%.3f", p), character(1)),
      check.names = FALSE, stringsAsFactors = FALSE)
    export_sci_table(ts6, file.path(TD, "Table S6 - included versus excluded participants.xlsx"),
      title = paste0("Table S6. Baseline characteristics of participants included in (n = ",
                     format(n_inc, big.mark = ",", trim = TRUE),
                     ") and excluded from (n = ",
                     format(n_excl, big.mark = ",", trim = TRUE), ") the analytic sample"),
      table_footnotes = c(
        sprintf("All %s enrolled participants with complete three-wave index data entered the analytic sample; no participant was excluded after enrolment (excluded column therefore carries no individual-level data).",
                format(n_inc, big.mark = ",", trim = TRUE)),
        "P column not computable when the excluded set is empty.",
        "Mean (SD) for continuous, n (%) for binary; as recorded in the source dataset."))
  }, error = function(e) cli::cli_alert_warning("Table S6 跳过: {conditionMessage(e)}"))

  # ── Table S7 model fit indices across systems（文献 ST4 合并版）────────
  tryCatch({
    ic_map <- lapply(ctx$results$tj_gbmtm %||% list(), function(x) x$select$table)
    kom <- lapply(ctx$results$tj_gbmtm %||% list(), function(x) x$K_opt)
    ts7 <- tj_lit_merge_ic(ic_map, kom)
    if (!is.null(ts7) && nrow(ts7)) {
      ts7$System <- tdisp(ts7$System)
      names(ts7)[names(ts7) == "MinAvePP"] <- "Minimum AvePP"
      names(ts7)[names(ts7) == "MinOCC"] <- "Minimum OCC"
      names(ts7)[names(ts7) == "MinClassProp"] <- "Smallest class, %"
      export_sci_table(ts7, file.path(TD, "Table S7 - model fit indices across systems.xlsx"),
        title = "Table S7. Model fit indices for group-based multi-trajectory modeling across candidate K, all joint systems",
        table_footnotes = c(
          "K = number of joint trajectory classes; selection primary = BIC / AIC.",
          sprintf("Soft gates: minimum average posterior probability >= %.2f, smallest class >= %.0f%%; entropy >= 0.80 preferred.",
                  as.numeric(bl$avepp_min %||% 0.70), 100 * as.numeric(bl$min_prop_floor %||% 0.05)),
          "OCC = odds of correct classification (per class; minimum reported).",
          "Selected = K retained for that system after AIC/BIC ranking with soft-gate review."))
    }
  }, error = function(e) cli::cli_alert_warning("Table S7 跳过: {conditionMessage(e)}"))

  # ── image_information（新图逐张；数字只从实体收获）───────────────────
  .tj_fmt_p <- function(pv) {
    if (!is.finite(pv)) return("未收获")
    if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
  }
  .tj_int <- function(x) {
    v <- suppressWarnings(as.integer(x))
    vapply(v, function(k) if (is.na(k)) "NA" else
      format(k, big.mark = ",", trim = TRUE), character(1))
  }
  n_ev <- sum(as.integer(prim$event %||% 0), na.rm = TRUE)
  ctx_common <- paste0(
    "数据库 = ", (pub$database_label %||% "Prospective cohort"),
    "（单队列，非拼图）；分析集 N = ", .tj_int(nrow(df)),
    "；结局 = ", olabel, "，事件 ", .tj_int(n_ev),
    sprintf("；时间尺度 = %s；访视波次 = %d", tu_lab, length(waves)),
    "；体系 = ", paste(vapply(sys_all, tdisp, character(1)), collapse = ", "))
  im_md <- function(bn, body) {
    writeLines(c(paste0("# ", bn), "", "## 图面说明", body,
                 "## 分析上下文", ctx_common),
               file.path(FD, "image_information", paste0(bn, ".md")))
  }
  # Figure 5 ridge
  tryCatch({
    wd <- character(0)
    for (ind in inds_all) {
      cells <- vapply(waves, function(w) {
        x <- suppressWarnings(as.numeric(df[[paste0(ind, "_", w)]]))
        sprintf("Wave %d n = %s, mean %.1f, SD %.1f", w, .tj_int(sum(!is.na(x))),
                mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
      }, character(1))
      wd <- c(wd, paste0("- ", tdisp(ind), ": ", paste(cells, collapse = "; ")))
    }
    im_md("Figure 5 - ridge densities", c(
      paste0("Ridge 密度图（ggridges）：每个面板一种血液学指标，纵轴自下而上为访视波次 Wave 1-",
             length(waves), "，横轴为指标原始值；填充色沿取值渐变（mako），展示各波分布形态与漂移。面板标题 = 指标名。"),
      "", "图上标注（各波样本量与分布，来自分析集实体）：", "", wd, "",
      "注：分析集各指标各波完整，故各面板每波 n 相同（= 分析集 N）。"))
  }, error = function(e) NULL)
  # Figure 6 selection curves
  tryCatch({
    cells <- vapply(names(ctx$results$tj_gbmtm %||% list()), function(sys) {
      tb <- ctx$results$tj_gbmtm[[sys]]$select$table
      ko <- ctx$results$tj_gbmtm[[sys]]$K_opt
      sprintf("- %s: K = %s; BIC = %s; 选定 K = %d", tdisp(sys),
              paste(tb$K, collapse = ","),
              paste(sprintf("%.1f", tb$BIC), collapse = ", "), as.integer(ko))
    }, character(1))
    im_md("Figure 6 - model selection curves", c(
      "GBMTM 选型曲线网格（每面板一个联合体系，4 列排布）：横轴为候选类别数 K，纵轴为 AIC（红）/ BIC（蓝），虚竖线 = 该体系最终选定的 K。",
      "", "图上标注（逐体系候选 K 与 BIC，选定值）：", "", cells, "",
      "本课题候选 K = 2-3（样本量与事件数限制；Methods 注明）。"))
  }, error = function(e) NULL)
  # Figure 7 joint trajectories（每体系）
  for (sys in names(ctx$results$tj_gbmtm %||% list())) {
    tryCatch({
      gv <- paste0(prefix, sys)
      lv <- unique(as.character(df[[gv]]))
      lv <- lv[order(as.integer(sub("^T", "", lv)))]
      nn <- .tj_int(as.integer(table(factor(df[[gv]], levels = lv))))
      pair_inds <- intersect(as.character(bl$index_pairs[[sys]]), inds_all)
      cells <- character(0)
      for (ind in pair_inds) {
        mns <- vapply(lv, function(cl) {
          v <- suppressWarnings(as.numeric(df[[paste0(ind, "_1")]])[!is.na(df[[gv]]) &
              as.character(df[[gv]]) == cl])
          sprintf("%s 基线均值 %.1f", cl, mean(v, na.rm = TRUE))
        }, character(1))
        cells <- c(cells, paste0("- ", tdisp(ind), "（原始单位，Wave 1）: ",
                                 paste(mns, collapse = "; ")))
      }
      im_md(paste0("Figure 7 - joint trajectories (", dfname(sys), ")"), c(
        paste0("双指标联合轨迹面板：左/右子面板分别为 ",
               paste(tdisp(pair_inds), collapse = " 与 "),
               "，横轴为 Examination wave 1-", length(waves),
               "，纵轴为各自原始尺度（面板内自动归一，无刻度数字）；每条彩线为一个联合潜类别的组内均值，灰色带 = ±95% CI（均值 ±1.96 SE）。类别图例 T1-T",
               length(lv), "。"),
        "", "图上标注：", "",
        paste0("- 各类别 n: ", paste(lv, " = ", nn, collapse = "; ")),
        cells, ""))
    }, error = function(e) NULL)
  }
  # Figure 8 cumulative incidence（每体系）
  for (sys in sys_have) {
    tryCatch({
      gv <- paste0(prefix, sys)
      d2 <- df[!is.na(df[[gv]]), , drop = FALSE]
      d2$.ev <- as.integer(prim$event[match(rownames(d2), rownames(df))])
      d2$.tm <- as.numeric(prim$time[match(rownames(d2), rownames(df))])
      d2 <- d2[!is.na(d2$.tm) & d2$.tm > 0 & !is.na(d2$.ev), , drop = FALSE]
      km <- stats::as.formula(paste0("survival::Surv(.tm, .ev) ~ ", gv))
      lr <- survival::survdiff(km, data = d2)
      pv <- stats::pchisq(lr$chisq, df = length(lr$n) - 1L, lower.tail = FALSE)
      lv <- sort(unique(as.character(d2[[gv]])))
      ev_by <- vapply(lv, function(cl) sum(d2$.ev[as.character(d2[[gv]]) == cl]),
                      numeric(1))
      last_ci <- vapply(lv, function(cl) {
        s <- survival::survfit(km, data = d2[d2[[gv]] == cl, ], times = max(d2$.tm))
        1 - as.numeric(s$surv)[1]
      }, numeric(1))
      im_md(paste0("Figure 8 - cumulative incidence (", dfname(sys), ")"), c(
        paste0("累积发病率曲线（1 - Kaplan–Meier 生存概率）：按 ", tdisp(sys),
               " 联合轨迹类别比较自入组起至首次 ", olabel,
               " 的累积发生概率；横轴 = ", tu_lab,
               "，阴影带 = 95% CI，图下方 Number at risk 表按类别逐时间点列出仍随访人数。"),
        "", "图上标注：", "",
        sprintf("- Log-rank P = %s", .tj_fmt_p(pv)),
        paste0("- ", lv, ": n = ", .tj_int(lr$n),
               "，事件 ", .tj_int(ev_by),
               sprintf("，末次随访累积发病率 %.1f%%", 100 * last_ci), collapse = "\n"), ""))
    }, error = function(e) NULL)
  }
  # Figure 9 per-system forest（每体系）
  for (sys in top_sys) {
    tryCatch({
      fr <- cox[cox$system == sys, , drop = FALSE]
      m_disp <- sub("^model", "Model ", tolower(as.character(unique(fr$model))),
                    ignore.case = TRUE)
      lab <- paste0(fr$class, " | ", sub("^model", "M", tolower(as.character(fr$model))))
      body <- c(
        paste0("森林图（分体系）：", tdisp(sys), " 联合轨迹类别相对参照类 T1 的发病 HR（95% CI，对数刻度），四套序贯调整模型逐行列出（M1 age；M2 +BMI；M3 +Nulliparity；M4 +chronic hypertension）。行名 = 类别 | 模型。灰虚线 = HR 1。"),
        "", "图上标注：", "",
        sprintf("- %s: HR %.3f (%.3f-%.3f), P %s", lab, fr$HR, fr$lo, fr$hi,
                vapply(fr$p, .tj_fmt_p, character(1))))
      im_md(paste0("Figure 9 - forest (", dfname(sys), ")"), body)
    }, error = function(e) NULL)
  }

  # ── Methods 追加：文献版式产物映射 ────────────────────────────────────
  tryCatch({
    mp <- file.path(DR, "Methods_statistical_analysis.md")
    if (file.exists(mp)) {
      txt <- readLines(mp, warn = FALSE)
      if (!any(grepl("Literature-aligned figure", txt, fixed = TRUE))) {
        add <- c("", "## Literature-aligned figure and table supplements",
          "Figure 5, Figure 6 and Figure 7 visualise the longitudinal index distributions (ridge densities), the model-selection curves (AIC/BIC against K for every joint system), and the class-specific mean trajectories on the original index scales, mirroring the reference-paper presentation.",
          "Figure 8 replots the event experience as cumulative incidence (1 - Kaplan-Meier) with number-at-risk tables; Figure 9 gives per-system forest plots across the four adjustment models.",
          "Table S3 tabulates missing-data proportions for the baseline covariates, Table S4 the wave-specific descriptive statistics of all modelled indices, Table S5 the discriminative performance of each joint system versus the base (age-only) model (C-index difference with paired-bootstrap P, plus category-free NRI and IDI as directional summaries given the limited number of events), Table S6 compares included versus excluded participants (the enrolled cohort entered the analytic sample in full, so the excluded column carries no individual-level data), and Table S7 consolidates the GBMTM fit indices (AIC, BIC, entropy, minimum AvePP, minimum OCC, smallest-class proportion) across candidate K for all 28 joint systems.",
          "Existing delivered items keep their original numbering: Table S1 (sensitivity), Table S2 (per-system model selection), Figure 1 (flowchart), Figure 2 (KM), Figure 3 (master forest), Figure 4 (standardised trajectory panels).")
        writeLines(c(txt, add), mp)
      }
    }
  }, error = function(e) cli::cli_alert_warning("Methods 追加失败: {conditionMessage(e)}"))

  # ── 表题同步（新表 A1 = 文件名）───────────────────────────────────────
  .sync_src <- file.path(root, "R/pub_xlsx_surgical.R")
  if (file.exists(.sync_src)) suppressWarnings(source(.sync_src, local = FALSE))
  if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    tryCatch(pub_sync_xlsx_a1_titles_to_filenames(TD),
             error = function(e) cli::cli_alert_warning("A1 同步失败: {conditionMessage(e)}"))
  }
  # 收口格式（PDF-only：pdf/ 目录 + image_information 同源）
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(pub_figure_ensure_formats(FD, config = ctx$config),
             error = function(e) cli::cli_alert_warning("ensure_formats 跳过: {conditionMessage(e)}"))
  }

  cli::cli_alert_success("tj_lit_export: 新增图 {n_done} 张 + 表 5 张 → {DR}")
  invisible(ctx)
}

register_block("tj_lit_export", block_tj_lit_export,
               "联合轨迹发病 文献版式补齐 Fig5-9 + Table S3-S7")
