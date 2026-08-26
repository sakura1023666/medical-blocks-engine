###############################################################################
#  chord_diagram — 亚型弦图（Zhang 2025 逻辑）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = lca_results, lca_selected_vars, df_final, lca_optimal_k
#  require_block       = block_lca（须在 lca 之后）；自动 source 同目录 block_system_map_library.R
#
#  chord = list(
#    k              = NULL,         # NULL → lca_optimal_k
#    vars           = NULL,         # NULL → lca_selected_vars
#    threshold      = 0.15,
#    unknown_system = "Other",
#    col_above      = "#E64B35CC",
#    col_below      = "#4DBBD5CC",
#    sp_labels      = NULL,
#    output_dir     = NULL,         # NULL → lca$output_dir
#    fig_width      = 15,
#    fig_height     = 5.5,
#    gap_degree     = 4,
#    transparency   = 0.35
#  ),
#
#  输出: ctx$results$chord_system_summary, chord_data; Figure_Chord_Diagram_k{k}.pdf
###############################################################################

block_chord_diagram <- function(ctx, ...) {

  # ── 依赖包 ─────────────────────────────────────────────────────────────────
  needed <- c("circlize","dplyr","tidyr","cli")
  missing_pkgs2 <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs2)) {
    if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
      options(repos = c(CRAN = "https://cloud.r-project.org"))
    }
    install.packages(missing_pkgs2, quiet = TRUE)
  }
  suppressPackageStartupMessages({
    library(circlize); library(dplyr); library(tidyr)
  })

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── source 系统映射库（同目录优先，兼容旧 Blocks/ 根路径）────────────────────
  if (!exists("get_system_map", mode = "function")) {
    .sml_candidates <- unique(c(
      tryCatch(file.path(dirname(normalizePath(sys.frames()[[1L]]$ofile)), "block_system_map_library.R"),
               error = function(e) ""),
      file.path(getwd(), "Blocks", "29_chord_diagram", "block_system_map_library.R"),
      "Blocks/29_chord_diagram/block_system_map_library.R",
      file.path(getwd(), "Blocks", "block_system_map_library.R"),
      "Blocks/block_system_map_library.R"
    ))
    .sml_candidates <- .sml_candidates[nzchar(.sml_candidates)]
    .sourced <- FALSE
    for (.p in .sml_candidates) {
      if (file.exists(.p)) { source(.p, local = FALSE); .sourced <- TRUE; break }
    }
    if (!.sourced || !exists("get_system_map", mode = "function")) {
      stop("[chord_diagram] 找不到 block_system_map_library.R。",
           "\n  已尝试路径：", paste(.sml_candidates, collapse = "\n  "),
           "\n  请确认 Blocks/29_chord_diagram/block_system_map_library.R 存在，或先手动 source() 该文件。")
    }
  }

  cfg      <- ctx$config
  chd_cfg  <- cfg$chord %||% list()

  # ── 读取上游结果 ───────────────────────────────────────────────────────────
  results   <- ctx$results$lca_results
  sel_vars  <- ctx$results$lca_selected_vars
  df_final  <- ctx$results$df_final
  optimal_k <- ctx$results$lca_optimal_k

  if (is.null(results) || is.null(sel_vars) || is.null(df_final)) {
    ctx$results$pause_point <- list(
      block      = "chord_diagram",
      reason     = "缺少上游 lca 结果（results / lca_selected_vars / df_final）",
      suggestion = "请先运行 block_lca。"
    )
    stop("PAUSE_FOR_USER_DECISION: 请先运行 block_lca，查看 ctx$results$pause_point。")
  }

  # ── 配置参数 ───────────────────────────────────────────────────────────────
  k_chord     <- as.integer(chd_cfg$k         %||% optimal_k %||% 2)
  vars_use    <- chd_cfg$vars                  %||% sel_vars
  threshold   <- chd_cfg$threshold             %||% 0.15
  unk_sys     <- chd_cfg$unknown_system        %||% "Other"
  col_above   <- chd_cfg$col_above             %||% "#E64B35CC"   # 暖红，均值以上
  col_below   <- chd_cfg$col_below             %||% "#4DBBD5CC"   # 冷蓝，均值以下
  sp_labels   <- chd_cfg$sp_labels             %||% NULL
  out_dir     <- chd_cfg$output_dir            %||% cfg$lca$output_dir %||% "lca_output"
  fig_w       <- chd_cfg$fig_width             %||% 15
  fig_h       <- chd_cfg$fig_height            %||% 5.5
  gap_deg     <- chd_cfg$gap_degree            %||% 4
  transp      <- chd_cfg$transparency          %||% 0.35
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  cli::cli_h1("[chord_diagram] 弦图（Zhang 2025 逻辑，k={k_chord}）")

  # ── Step 1: 对齐数据 & 亚型标签 ───────────────────────────────────────────
  cls_vec <- results[[k_chord]]$consensusClass
  if (length(cls_vec) != nrow(df_final)) {
    stop("[chord_diagram] df_final 行数与聚类标签长度不一致。")
  }

  # 确保 vars_use 在数据中存在
  vars_use <- intersect(vars_use, colnames(df_final))
  if (length(vars_use) == 0) stop("[chord_diagram] vars_use 中无有效列名。")

  # 转数值
  df_chord <- df_final[, vars_use, drop = FALSE]
  df_chord[] <- lapply(df_chord, function(x) suppressWarnings(as.numeric(as.character(x))))
  bad_v <- vars_use[!sapply(df_chord, is.numeric)]
  if (length(bad_v) > 0) {
    cli::cli_alert_warning("以下变量无法转数值，已剔除：{paste(bad_v, collapse=', ')}")
    vars_use <- setdiff(vars_use, bad_v)
    df_chord <- df_chord[, vars_use, drop = FALSE]
  }
  if (length(vars_use) == 0) stop("[chord_diagram] 无可用数值变量。")

  df_chord$Subphenotype <- factor(cls_vec)

  # ── Step 2: 全队列 Z-score ─────────────────────────────────────────────────
  cli::cli_h2("Step 2: Z-score 标准化（全队列基准）")
  df_scaled <- as.data.frame(scale(df_chord[, vars_use, drop = FALSE]))
  df_scaled$Subphenotype <- df_chord$Subphenotype

  cli::cli_alert_info("Subphenotype 分布：")
  print(table(df_chord$Subphenotype, useNA = "ifany"))

  # ── Step 3: 系统映射 ───────────────────────────────────────────────────────
  cli::cli_h2("Step 3: 生理系统自动映射")
  system_map <- get_system_map(vars_use, unknown_system = unk_sys, verbose = TRUE)
  cli::cli_alert_info("系统分布：")
  print(table(system_map$System))

  # ── Step 4: 各亚型各系统 mean_z（Zhang 2025 核心逻辑） ─────────────────────
  cli::cli_h2("Step 4: 计算各亚型系统层面 mean Z-score")

  cluster_profiles <- df_scaled %>%
    group_by(Subphenotype) %>%
    summarise(across(all_of(vars_use), ~ mean(.x, na.rm = TRUE)), .groups = "drop") %>%
    pivot_longer(cols = all_of(vars_use), names_to = "Variable", values_to = "Z_Score") %>%
    left_join(system_map, by = "Variable")

  system_summary <- cluster_profiles %>%
    filter(!is.na(System)) %>%
    group_by(Subphenotype, System) %>%
    summarise(
      Z_sys    = mean(Z_Score, na.rm = TRUE),
      Strength = mean(abs(Z_Score), na.rm = TRUE),
      n_vars   = n(),
      .groups  = "drop"
    )
  ctx$results$chord_system_summary <- system_summary
  cli::cli_alert_info("系统汇总表：")
  print(as.data.frame(system_summary))

  # ── Step 5: 构建弦图数据框 ─────────────────────────────────────────────────
  sp_levels <- sort(as.character(unique(df_chord$Subphenotype)))
  if (!is.null(sp_labels)) {
    sp_label_map <- unlist(sp_labels)
  } else {
    sp_label_map <- setNames(
      paste0("Subphenotype ", sp_levels),
      sp_levels
    )
  }

  chord_raw <- system_summary %>%
    filter(Strength > threshold) %>%
    mutate(
      SP_label    = sp_label_map[as.character(Subphenotype)],
      SP_label    = ifelse(is.na(SP_label),
                           paste0("Subphenotype ", as.character(Subphenotype)),
                           SP_label),
      ribbon_col  = ifelse(Z_sys > 0, col_above, col_below),
      value       = Strength
    ) %>%
    dplyr::select(from = SP_label, to = System, value, ribbon_col, Z_sys)

  if (nrow(chord_raw) == 0) {
    ctx$results$pause_point <- list(
      block      = "chord_diagram",
      reason     = paste0("threshold=", threshold, " 筛选后弦图数据为空"),
      suggestion = paste0("尝试降低 config$chord$threshold（当前=", threshold,
                          "），或检查聚类是否有效分离。"),
      data_snapshot = head(system_summary, 10)
    )
    stop("PAUSE_FOR_USER_DECISION: 弦图数据为空，查看 ctx$results$pause_point。")
  }
  ctx$results$chord_data <- chord_raw
  cli::cli_alert_info("弦图数据（{nrow(chord_raw)} 条 ribbon）：")
  print(as.data.frame(chord_raw[, c("from","to","value","Z_sys")]))

  # ── Step 6: 配色方案 ───────────────────────────────────────────────────────
  sp_node_colors <- c(
    "#00468BFF","#ED0000FF","#42B540FF","#925E9FFF",
    "#FDAF91FF","#AD002AFF"
  )
  sp_unique  <- unique(chord_raw$from)
  sp_col_map <- setNames(sp_node_colors[seq_along(sp_unique)], sp_unique)

  sys_unique  <- unique(chord_raw$to)
  sys_col_map <- setNames(rep("grey80", length(sys_unique)), sys_unique)
  all_colors  <- c(sp_col_map, sys_col_map)

  # ── Step 7: 画图函数 ───────────────────────────────────────────────────────
  .plot_chord <- function(dat, main_title, panel_letter) {
    if (nrow(dat) == 0) {
      plot.new()
      title(main_title)
      mtext(panel_letter, side = 3, line = 0.2, adj = 0, cex = 1.6, font = 2)
      text(0.5, 0.5, "No data above threshold", cex = 1.2, col = "grey40")
      return(invisible(NULL))
    }

    present_sectors <- unique(c(dat$from, dat$to))
    panel_colors    <- all_colors[names(all_colors) %in% present_sectors]
    ribbon_col_vec  <- dat$ribbon_col

    circos.clear()
    circos.par(
      start.degree   = 90,
      gap.degree     = gap_deg,
      track.margin   = c(-0.1, 0.1),
      points.overflow.warning = FALSE
    )

    chordDiagram(
      x                = dat[, c("from","to","value")],
      grid.col         = panel_colors,
      col              = ribbon_col_vec,
      transparency     = transp,
      directional      = 1,
      direction.type   = c("diffHeight", "arrows"),
      link.arr.type    = "big.arrow",
      annotationTrack  = "grid",
      preAllocateTracks = list(track.height = 0.12)
    )

    circos.track(track.index = 1, panel.fun = function(x, y) {
      circos.text(
        CELL_META$xcenter, CELL_META$ylim[1],
        CELL_META$sector.index,
        facing     = "clockwise",
        niceFacing = TRUE,
        adj        = c(0, 0.5),
        cex        = 0.65,
        font       = 2,
        col        = "black"
      )
    }, bg.border = NA)

    title(main_title, cex.main = 1.15)
    mtext(panel_letter, side = 3, line = 0.2, adj = 0, cex = 1.6, font = 2)
  }

  # ── Step 8: 输出 PDF ───────────────────────────────────────────────────────
  subtypes_present <- sort(unique(chord_raw$from))
  n_sp     <- length(subtypes_present)
  n_panels <- 1 + n_sp

  panel_labs <- LETTERS[1:(n_panels + 1)]

  out_pdf <- file.path(out_dir, paste0("Figure_Chord_Diagram_k", k_chord, ".pdf"))
  .safe_font <- if (exists("plot_font_from_config", mode = "function")) {
    plot_font_from_config(cfg)
  } else if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family(cfg$plot$font_family %||% "Times New Roman")
  } else {
    "sans"
  }
  pdf(out_pdf, width = fig_w, height = fig_h, family = .safe_font)

  par(mfrow = c(1, n_panels), mar = c(1, 1, 3, 1))

  .plot_chord(
    dat          = chord_raw,
    main_title   = "All subphenotypes combined",
    panel_letter = panel_labs[1]
  )

  for (i in seq_along(subtypes_present)) {
    sp <- subtypes_present[i]
    .plot_chord(
      dat          = chord_raw %>% filter(from == sp),
      main_title   = sp,
      panel_letter = panel_labs[i + 1]
    )
  }

  dev.off()
  cli::cli_alert_success("弦图已保存：{normalizePath(out_pdf, mustWork=FALSE)}")

  # ── Step 9: 导出汇总表 ─────────────────────────────────────────────────────
  ctx <- save_result(ctx, "chord_system_summary",
                     as.data.frame(system_summary),
                     file.path(out_dir, paste0("Table_Chord_SystemSummary_k", k_chord, ".csv")))

  sum_export <- system_summary %>%
    mutate(
      Z_sys    = round(Z_sys, 3),
      Strength = round(Strength, 3),
      Direction = ifelse(Z_sys > 0, "Above mean", "Below mean")
    ) %>%
    dplyr::select(Subphenotype, System, n_vars, Z_sys, Strength, Direction) %>%
    as.data.frame()
  tryCatch(
    write.csv(sum_export,
              file.path(out_dir, paste0("Table_Chord_SystemSummary_k", k_chord, ".csv")),
              row.names = FALSE),
    error = function(e) cli::cli_alert_warning("Chord summary CSV failed: {e$message}")
  )
  export_sci_table(
    sum_export,
    file.path(out_dir, paste0("Table_Chord_SystemSummary_k", k_chord, ".xlsx")),
    title = paste0("Chord diagram system-level Z-score summary (k=", k_chord, ")")
  )

  cli::cli_alert_success("[chord_diagram] 全部完成。")
  ctx
}

register_block("chord_diagram", block_chord_diagram,
               "亚型弦图（Zhang 2025 逻辑）：系统均值Z-score，ribbon颜色区分高于/低于总均，自动系统映射，三面板 PDF")
