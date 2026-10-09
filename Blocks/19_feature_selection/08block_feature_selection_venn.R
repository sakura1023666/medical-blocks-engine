###############################################################################
#  feature_selection_venn — Figure S1 特征选择方法重叠图（韦恩 / Euler / UpSet）；
#  单方法 LASSO 时上下拼 S2A+S2B 为 A/B 矢量单页（禁止多页 pdf_combine）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = feature_selection_final
#  require_ctx_results = feature_selection_venn_input   # 由 feature_selection_consensus (07) 写入
#  require_block       = feature_selection_consensus（须先跑 07；或 RDS 含 venn_input）
#
#  feature_selection_venn = list(
#    overlap_plot_methods   = NULL,    # 指定画哪几个方法；NULL=自动（≤4 全展示，>4 取前 4）
#    venn_width             = 10,
#    venn_height            = 7,
#    pause_enable           = TRUE,
#    pause_on_venn_mismatch = TRUE,    # 仅当画图方法=定稿方法全集且图心≠final 时 pause
#    skip_univar_fallback   = TRUE     # selection_source=univar_fallback 时不画图
#    sync_venn_center_to_ml = TRUE     # 用定稿方法全集交集同步；图截前 4 时不得用图心覆盖
#  ),
#
#  块内 fsv_cfg <- cfg$feature_selection_venn %||% cfg$feature_selection（legacy 绘图键）；
#  图方法为定稿子集时不修改 feature_selection_final。
#  register_block: "feature_selection_venn"
###############################################################################

# ── 私有工具 ─────────────────────────────────────────────────────────────────

.fsv08_should_pause <- function(fsv_cfg, key, default = TRUE) {
  if (!is.null(fsv_cfg$pause_enable) && !isTRUE(fsv_cfg$pause_enable)) return(FALSE)
  isTRUE(fsv_cfg[[key]] %||% default)
}

.fsv08_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) {
    utils::head(data_snapshot, 5L)
  } else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block         = "feature_selection_venn",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_venn — ", reason,
    " | See ctx$results$pause_point. / ",
    "发现异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

# 韦恩图各集合 = 方法入选 ∪ final 中的复合指标，使中心交集 = final
.fsv08_supp_figure_name <- function(fsv_cfg, kind = c("venn", "upset")) {
  kind <- match.arg(kind)
  if (kind == "venn") {
    as.character(fsv_cfg$venn_filename %||% "Figure S1.Venn.pdf")[1L]
  } else {
    as.character(fsv_cfg$upset_filename %||% "Figure S1.Upset.pdf")[1L]
  }
}

.fsv08_method_s2_figure <- function(method) {
  m <- tolower(trimws(as.character(method)[1L]))
  m <- gsub("[^a-z0-9_]+", "_", m)
  switch(m,
    lasso = "Figure S2B.LassoModel.pdf",
    lasso_cox = "Figure S2.LASSO-Cox.pdf",
    boruta = "Figure S2C.Boruta.pdf",
    bayesian = "Figure S2D.Bayesian.pdf",
    random_forest = "Figure S2E.Random forest.pdf",
    bagged_trees = "Figure S2F.Bagged trees.pdf",
    lvq = "Figure S2G.LVQ.pdf",
    NULL
  )
}

## 在 fig_dir 中按 stem 模糊匹配（允许 -Hosp. / 空格差异）
.fsv08_find_fig <- function(fig_dir, stem_regex) {
  files <- list.files(fig_dir, pattern = "(?i)\\.pdf$", full.names = TRUE)
  hit <- files[grepl(stem_regex, basename(files), ignore.case = TRUE, perl = TRUE)]
  if (length(hit)) hit[[1L]] else NA_character_
}

## 仅 LASSO：S2A + S2B 上下 A/B 矢量单页；其它方法不拼
.fsv08_stack_pdfs_ab <- function(pdf_paths, dest) {
  pdf_paths <- as.character(pdf_paths)
  pdf_paths <- pdf_paths[file.exists(pdf_paths)]
  if (length(pdf_paths) < 2L) return(FALSE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (exists("pub_figure_combine_ab_pdfs", mode = "function")) {
    ok <- isTRUE(tryCatch(
      pub_figure_combine_ab_pdfs(pdf_paths[[1L]], pdf_paths[[2L]], dest),
      error = function(e) FALSE
    ))
    if (isTRUE(ok) && file.exists(dest) && isTRUE(file.info(dest)$size > 5000L)) {
      return(TRUE)
    }
  }
  ## 回退：pdftools 多页合并
  if (requireNamespace("pdftools", quietly = TRUE)) {
    ok <- tryCatch({
      pdftools::pdf_combine(pdf_paths, output = dest)
      file.exists(dest) && file.info(dest)$size > 5000L
    }, error = function(e) FALSE)
    if (isTRUE(ok)) return(TRUE)
  }
  src <- if (length(pdf_paths) >= 2L) pdf_paths[[2L]] else pdf_paths[[1L]]
  file.copy(src, dest, overwrite = TRUE)
}

.fsv08_promote_single_method_s1 <- function(ctx, method, fsv_cfg) {
  if (!isTRUE(fsv_cfg$single_method_use_s2_plot %||% TRUE)) return(ctx)
  method <- tolower(trimws(as.character(method)[1L]))
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) return(ctx)

  dest_bn <- .fsv08_supp_figure_name(fsv_cfg, "venn")
  ## 单方法 S1 文件名：Figure S1.Lasso.pdf / Figure S1.Boruta.pdf（不是 Venn）
  dest_bn <- sub(
    "\\.Venn\\.pdf$",
    paste0(".", gsub("[^A-Za-z0-9._-]+", "_", method), ".pdf"),
    dest_bn
  )
  if (!grepl("Figure S1", dest_bn, ignore.case = TRUE)) {
    dest_bn <- paste0("Figure S1.", gsub("[^A-Za-z0-9._-]+", "_", method), ".pdf")
  }
  dest <- file.path(fig_dir, dest_bn)

  if (identical(method, "lasso")) {
    ## 仅 LASSO：上下拼 S2A + S2B
    a <- .fsv08_find_fig(fig_dir, "Figure\\s*S2A.*LassoGenes")
    b <- .fsv08_find_fig(fig_dir, "Figure\\s*S2B.*LassoModel")
    if (is.na(a) || is.na(b)) {
      ## 也可能落在 step 子目录 Figures
      step_figs <- list.files(
        ctx$output_dir %||% ".",
        pattern = "(?i)Figure\\s*S2[AB].*Lasso.*\\.pdf$",
        recursive = TRUE, full.names = TRUE
      )
      if (is.na(a)) {
        hit <- step_figs[grepl("S2A", basename(step_figs), ignore.case = TRUE)]
        if (length(hit)) a <- hit[[1L]]
      }
      if (is.na(b)) {
        hit <- step_figs[grepl("S2B", basename(step_figs), ignore.case = TRUE)]
        if (length(hit)) b <- hit[[1L]]
      }
    }
    if (!is.na(a) && !is.na(b) && file.exists(a) && file.exists(b)) {
      ok <- .fsv08_stack_pdfs_ab(c(a, b), dest)
      if (isTRUE(ok) || file.exists(dest)) {
        cli::cli_alert_success(
          "feature_selection_venn: 单方法 lasso，已上下 A/B 拼接 S2A+S2B → {basename(dest)}"
        )
        return(ctx)
      }
    }
    ## 拼失败则退回单张 S2B / S2A
    src <- if (!is.na(b) && file.exists(b)) b else if (!is.na(a) && file.exists(a)) a else NA_character_
    if (is.na(src)) return(ctx)
    file.copy(src, dest, overwrite = TRUE)
    cli::cli_alert_warning(
      "feature_selection_venn: lasso 拼图失败，已用单张 {basename(src)} → {basename(dest)}"
    )
    return(ctx)
  }

  if (identical(method, "lasso_cox")) {
    ## 预后 LASSO-Cox：已是 A/B/C 拼图，直接升为 S1
    src <- .fsv08_find_fig(fig_dir, "Figure\\s*S2.*LASSO-Cox")
    if (is.na(src)) {
      src <- .fsv08_find_fig(fig_dir, "Figure\\s*S1.*LASSO-Cox")
    }
    if (is.na(src)) {
      step_figs <- list.files(
        ctx$output_dir %||% ".",
        pattern = "(?i)Figure\\s*S[12].*LASSO-Cox.*\\.pdf$",
        recursive = TRUE, full.names = TRUE
      )
      if (length(step_figs)) src <- step_figs[[1L]]
    }
    if (is.na(src) || !file.exists(src)) return(ctx)
    file.copy(src, dest, overwrite = TRUE)
    cli::cli_alert_success(
      "feature_selection_venn: 单方法 lasso_cox，已提升 {basename(src)} → {basename(dest)}"
    )
    return(ctx)
  }

  ## 其它单方法（boruta/rf/…）：直接升为 S1，不拼图
  src_bn <- .fsv08_method_s2_figure(method)
  src <- if (!is.null(src_bn)) file.path(fig_dir, src_bn) else NA_character_
  if (is.na(src) || !file.exists(src)) {
    src <- .fsv08_find_fig(
      fig_dir,
      paste0("Figure\\s*S2[A-G].*", gsub("_", ".*", method))
    )
  }
  if (is.na(src) || !file.exists(src)) {
    alts <- list.files(fig_dir, pattern = "\\.pdf$", full.names = TRUE)
    alts <- alts[grepl("Figure S2", basename(alts), fixed = TRUE)]
    if (!length(alts)) return(ctx)
    src <- alts[[1L]]
  }
  if (identical(
    normalizePath(src, winslash = "/", mustWork = FALSE),
    normalizePath(dest, winslash = "/", mustWork = FALSE)
  )) {
    return(ctx)
  }
  ok <- file.copy(src, dest, overwrite = TRUE)
  if (isTRUE(ok)) {
    cli::cli_alert_success(
      "feature_selection_venn: 单方法 {method}，已复制 {basename(src)} → {basename(dest)}（不拼图）"
    )
  }
  ctx
}

.fsv08_exposure_vars_in_data <- function(ctx, cfg) {
  exp <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  exp <- exp[nzchar(exp)]
  if (!length(exp)) return(character(0))
  resolved <- feature_selection_modeling_data(ctx)
  dat <- resolved$data
  if (is.null(dat)) return(character(0))
  exp[exp %in% names(dat)]
}

.fsv08_is_plot_method_subset <- function(overlap_methods, selected_methods) {
  om <- unique(as.character(overlap_methods[nzchar(as.character(overlap_methods))]))
  sm <- unique(as.character(selected_methods[nzchar(as.character(selected_methods))]))
  length(sm) >= 2L && length(om) >= 1L && !setequal(om, sm)
}

.fsv08_venn_list_for_final <- function(
    by_model, overlap_methods, final, U, composite_in_final,
    exposure_vars = character(0)) {
  exposure_ok <- as.character(exposure_vars)[nzchar(as.character(exposure_vars))]
  composite_in_final <- unique(c(
    intersect(composite_in_final, final),
    exposure_ok
  ))
  if (length(overlap_methods) >= 2L) {
    return(stats::setNames(
      lapply(overlap_methods, function(m) {
        unique(c(
          intersect(by_model[[m]] %||% character(0), U),
          composite_in_final
        ))
      }),
      overlap_methods
    ))
  }
  if (length(overlap_methods) == 1L) {
    m1 <- overlap_methods[1L]
    return(stats::setNames(
      list(unique(final)),
      m1
    ))
  }
  list()
}

.fsv08_require_exposure_in_features <- function(ctx, feats, cfg, fsv_cfg = list()) {
  feats <- unique(as.character(feats)[nzchar(as.character(feats))])
  if (!isTRUE(fsv_cfg$require_exposure_in_features %||% TRUE)) return(feats)
  exp_ok <- .fsv08_exposure_vars_in_data(ctx, cfg)
  if (!length(exp_ok)) return(feats)
  missing <- setdiff(exp_ok, feats)
  if (length(missing)) {
    stop(
      "COMPOSITE_NOT_IN_FEATURE_SELECTION: 暴露指标 ",
      paste(missing, collapse = ", "),
      " 未纳入韦恩中心/特征选择，本指标判为失败。",
      call. = FALSE
    )
  }
  feats
}

# ── 主块 ─────────────────────────────────────────────────────────────────────

block_feature_selection_venn <- function(ctx, ...) {
  cfg <- ctx$config
  fsv_cfg <- cfg$feature_selection_venn %||% cfg$feature_selection %||% list()
  fs_legacy <- cfg$feature_selection %||% list()

  if (isFALSE(fsv_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$feature_selection_venn$enable=FALSE，跳过 feature_selection_venn。")
    return(ctx)
  }

  final <- ctx$results$feature_selection_final
  if (is.null(final) || !length(final)) {
    if (.fsv08_should_pause(fsv_cfg, "pause_on_missing_final", TRUE)) {
      .fsv08_pause(
        ctx,
        "缺少 ctx$results$feature_selection_final",
        "请先运行 feature_selection_consensus（07）或 load_feature_selection_final_into_ctx()",
        NULL
      )
    }
    stop("feature_selection_venn: 缺少 feature_selection_final。", call. = FALSE)
  }
  final <- as.character(final)

  vi <- ctx$results$feature_selection_venn_input
  if (is.null(vi) || !is.list(vi) || !length(vi)) {
    if (.fsv08_should_pause(fsv_cfg, "pause_on_missing_venn_input", TRUE)) {
      .fsv08_pause(
        ctx,
        "缺少 ctx$results$feature_selection_venn_input",
        "请先运行 feature_selection_consensus（07）；RDS 应含 feature_selection_venn_input 字段",
        NULL
      )
    }
    stop("feature_selection_venn: 缺少 feature_selection_venn_input。", call. = FALSE)
  }

  by_model <- vi$by_model
  if (is.null(by_model) || !length(by_model)) {
    if (.fsv08_should_pause(fsv_cfg, "pause_on_empty_by_model", TRUE)) {
      .fsv08_pause(
        ctx,
        "feature_selection_venn_input$by_model 为空",
        "检查 01–06 方法块是否成功，并重新运行 consensus",
        NULL
      )
    }
    stop("feature_selection_venn: by_model 为空。", call. = FALSE)
  }

  selection_source <- as.character(vi$selection_source %||% "unknown")[1L]
  selected_methods <- as.character(vi$selected_methods %||% names(by_model))
  selected_methods <- unique(intersect(selected_methods, names(by_model)))
  if (!length(selected_methods)) selected_methods <- names(by_model)

  ## 仅 LASSO / 单方法：不出韦恩，直接升 S1（LASSO 两图上下拼）
  if (isTRUE(ctx$results$feature_selection_lasso_only) ||
      identical(selection_source, "single_method") ||
      length(selected_methods) == 1L) {
    method_one <- selected_methods[1L] %||% names(by_model)[1L]
    if (!is.null(method_one) && nzchar(method_one)) {
      ctx <- .fsv08_promote_single_method_s1(ctx, method_one, fsv_cfg)
      return(ctx)
    }
  }

  method_names <- as.character(vi$method_names %||% names(by_model))
  U <- as.character(vi$U %||% unique(unlist(by_model, use.names = FALSE)))
  comp_in_final <- as.character(vi$comp_in_final %||% character(0))
  exposure_vars <- .fsv08_exposure_vars_in_data(ctx, cfg)

  if (identical(selection_source, "univar_fallback") &&
      isTRUE(fsv_cfg$skip_univar_fallback %||% TRUE)) {
    cli::cli_alert_info("Figure S1: 单因素回退入选，跳过韦恩图（无多模型共识）")
    return(ctx)
  }

  draw_venn <- vi$overlap_eligible
  if (is.null(draw_venn)) {
    draw_venn <- identical(selection_source, "intersection") ||
      identical(selection_source, "single_method")
  }
  draw_venn <- isTRUE(draw_venn)

  # ── 韦恩图（≥2 个模型）/ Euler / UpSet ───────────────────────────────────
  overlap_methods <- fsv_cfg$overlap_plot_methods %||% fs_legacy$overlap_plot_methods %||% NULL
  if (!is.null(overlap_methods) && length(overlap_methods)) {
    overlap_methods <- unique(intersect(
      trimws(as.character(overlap_methods)),
      selected_methods
    ))
  }
  if (!length(overlap_methods)) {
    if (length(selected_methods) > 4L) {
      overlap_methods <- selected_methods[seq_len(4L)]
      cli::cli_alert_info(
        "Figure S1: 最终方法 {length(selected_methods)} 个>4，韦恩图仅展示前 4 个: {paste(overlap_methods, collapse = ', ')}。可用 config$feature_selection_venn$overlap_plot_methods 指定。"
      )
    } else {
      overlap_methods <- selected_methods
    }
  }
  if (length(overlap_methods) > 4L) overlap_methods <- overlap_methods[seq_len(4L)]

  if (draw_venn && identical(selection_source, "single_method")) {
    overlap_methods <- selected_methods[1L]
  }
  if (draw_venn && length(overlap_methods) >= 1L) {
    list_in <- .fsv08_venn_list_for_final(
      by_model, overlap_methods, final, U, comp_in_final, exposure_vars
    )
  } else {
    list_in <- list()
  }
  list_in_full <- list_in
  n_sets <- length(list_in)

  if (draw_venn && n_sets < 2L && length(method_names) >= 2L &&
      !identical(selection_source, "single_method")) {
    overlap_methods <- method_names[seq_len(min(2L, length(method_names)))]
    list_in <- .fsv08_venn_list_for_final(
      by_model, overlap_methods, final, U, comp_in_final, exposure_vars
    )
    n_sets <- length(list_in)
  }

  .inter_len <- function(lst, idx) {
    length(Reduce(intersect, lst[as.integer(idx)]))
  }
  venn_center_n <- if (n_sets >= 2L) {
    length(Reduce(intersect, list_in))
  } else if (n_sets == 1L) {
    length(list_in[[1L]])
  } else {
    0L
  }

  sync_venn <- isTRUE(fsv_cfg$sync_venn_center_to_ml %||%
    (cfg$ml %||% list())$use_venn_center_features %||% TRUE)
  plot_subset <- .fsv08_is_plot_method_subset(overlap_methods, selected_methods)

  if (draw_venn && venn_center_n != length(final)) {
    if (isTRUE(plot_subset)) {
      cli::cli_alert_info(
        "韦恩图仅展示 {length(overlap_methods)}/{length(selected_methods)} 个定稿方法，图心 n={venn_center_n} 与定稿 n={length(final)} 不同是预期现象。不以图心覆盖 ML 特征。"
      )
    } else if (isTRUE(sync_venn)) {
      cli::cli_alert_info(
        "韦恩中心 ({venn_center_n}) 与 consensus final ({length(final)}) 不一致；将以韦恩中心覆盖 ML/SHAP 特征。"
      )
    } else {
    msg <- paste0(
      "韦恩中心 (", venn_center_n, ") 与 final (",
      length(final), ") 不一致；请检查复合指标与各方法入选集。"
    )
    if (.fsv08_should_pause(fsv_cfg, "pause_on_venn_mismatch", TRUE)) {
      .fsv08_pause(
        ctx,
        msg,
        "检查 config 复合指标设置、各方法入选集，或调整 overlap_plot_methods 后重跑本块",
        data.frame(
          venn_center_n = venn_center_n,
          final_n = length(final),
          overlap_methods = paste(overlap_methods, collapse = ", "),
          stringsAsFactors = FALSE
        )
      )
    }
    stop("feature_selection_venn: ", msg, call. = FALSE)
    }
  }

  .plot_classic_venn <- function() {
    nm <- names(list_in)
    if (is.null(nm)) nm <- paste0("M", seq_len(n_sets))

    if (requireNamespace("ggVennDiagram", quietly = TRUE) &&
        requireNamespace("ggplot2", quietly = TRUE) &&
        n_sets >= 2L && n_sets <= 7L) {
      ok_gg <- tryCatch({
        named_list <- stats::setNames(list_in, nm)
        gp <- ggVennDiagram::ggVennDiagram(named_list, label_alpha = 0, edge_size = 0.8) +
          ggplot2::scale_fill_gradient(low = "#d4edf7", high = "#2166ac") +
          ggplot2::scale_color_manual(values = rep("grey30", n_sets)) +
          ggplot2::theme(
            legend.position = "bottom",
            plot.title = ggplot2::element_text(hjust = 0.5, face = "bold", size = 13)
          ) +
          ggplot2::ggtitle("Feature selection overlap (Venn)")
        print(gp)
        TRUE
      }, error = function(e) FALSE)
      if (isTRUE(ok_gg)) return(TRUE)
    }

    if (!requireNamespace("VennDiagram", quietly = TRUE)) return(FALSE)
    if (n_sets < 2L || n_sets > 4L) return(FALSE)
    fills <- c("lightblue", "lightgreen", "pink", "wheat")[seq_len(n_sets)]
    alph <- rep(0.45, n_sets)
    ok <- tryCatch(
      {
        suppressMessages({
          grid::grid.newpage()
          if (n_sets == 2L) {
            s1 <- list_in[[1L]]
            s2 <- list_in[[2L]]
            g <- VennDiagram::draw.pairwise.venn(
              area1 = length(s1), area2 = length(s2),
              cross.area = .inter_len(list_in, c(1L, 2L)),
              category = nm,
              fill = fills,
              alpha = alph,
              cat.fontface = "bold",
              cat.cex = 1.1
            )
            grid::grid.draw(g)
          } else if (n_sets == 3L) {
            s1 <- list_in[[1L]]
            s2 <- list_in[[2L]]
            s3 <- list_in[[3L]]
            ab <- intersect(s1, s2)
            bc <- intersect(s2, s3)
            ac <- intersect(s1, s3)
            n123 <- length(Reduce(intersect, list(s1, s2, s3)))
            n12 <- length(ab) - n123
            n23 <- length(bc) - n123
            n13 <- length(ac) - n123
            g <- VennDiagram::draw.triple.venn(
              area1 = length(s1), area2 = length(s2), area3 = length(s3),
              n12 = n12, n13 = n13, n23 = n23, n123 = n123,
              category = nm, fill = fills, alpha = alph,
              cat.fontface = "bold", cat.cex = 1.05
            )
            grid::grid.draw(g)
          } else {
            g <- VennDiagram::draw.quad.venn(
              area1 = length(list_in[[1L]]), area2 = length(list_in[[2L]]),
              area3 = length(list_in[[3L]]), area4 = length(list_in[[4L]]),
              n12 = .inter_len(list_in, c(1L, 2L)), n13 = .inter_len(list_in, c(1L, 3L)),
              n14 = .inter_len(list_in, c(1L, 4L)), n23 = .inter_len(list_in, c(2L, 3L)),
              n24 = .inter_len(list_in, c(2L, 4L)), n34 = .inter_len(list_in, c(3L, 4L)),
              n123 = .inter_len(list_in, c(1L, 2L, 3L)),
              n124 = .inter_len(list_in, c(1L, 2L, 4L)),
              n134 = .inter_len(list_in, c(1L, 3L, 4L)),
              n234 = .inter_len(list_in, c(2L, 3L, 4L)),
              n1234 = .inter_len(list_in, c(1L, 2L, 3L, 4L)),
              category = nm, fill = fills, alpha = alph,
              cat.fontface = "bold", cat.cex = 0.95
            )
            grid::grid.draw(g)
          }
        })
        TRUE
      },
      error = function(e) FALSE
    )
    ok
  }

  ctx$results$feature_selection_venn_sets <- list_in
  ctx$results$feature_selection_venn_methods <- overlap_methods

  if (n_sets >= 2L) {
    fig_overlap_name <- if (n_sets <= 4L) {
      .fsv08_supp_figure_name(fsv_cfg, "venn")
    } else {
      .fsv08_supp_figure_name(fsv_cfg, "upset")
    }
    ctx <- save_figure(ctx, fig_overlap_name, function() {
      list_up <- if (length(list_in_full) > length(list_in)) list_in_full else list_in
      n_up <- length(list_up)
      if (.plot_classic_venn()) return(invisible())
      cli::cli_alert_warning(
        "Figure S1: 经典圆形韦恩未成功（缺 VennDiagram 或集合计数不满足画图条件），将尝试 Euler / UpSet。"
      )
      if (requireNamespace("eulerr", quietly = TRUE) && n_up <= 6L) {
        fit <- try(eulerr::euler(list_up), silent = TRUE)
        if (!inherits(fit, "try-error")) {
          print(plot(fit, quantities = TRUE, legend = TRUE, main = "Feature selection overlap (Euler)"))
          return(invisible())
        }
      }
      if (requireNamespace("UpSetR", quietly = TRUE)) {
        print(UpSetR::upset(
          UpSetR::fromList(list_up),
          nsets = n_up, main.bar.color = "steelblue",
          sets.bar.color = "darkred", order.by = "freq"
        ))
        return(invisible())
      }
      graphics::plot.new()
      graphics::text(
        0.5, 0.5,
        "Install VennDiagram（2–4 模型韦恩图）或 eulerr / UpSetR 以绘制重叠图"
      )
    },
    width = as.numeric(fsv_cfg$venn_width %||% fs_legacy$venn_width %||% 10)[1L],
    height = as.numeric(fsv_cfg$venn_height %||% fs_legacy$venn_height %||% 7)[1L])
    cli::cli_alert_success(
      "feature_selection_venn: 已保存 {fig_overlap_name}（{n_sets} 个集合）"
    )
  } else {
    method_one <- overlap_methods[1L] %||% selected_methods[1L] %||% names(by_model)[1L]
    if (!is.null(method_one) && nzchar(method_one)) {
      ctx <- .fsv08_promote_single_method_s1(ctx, method_one, fsv_cfg)
    } else {
      cli::cli_alert_warning("feature_selection_venn: 仅 1 个模型成功或无可画集合，跳过重叠图")
    }
  }

  if (isTRUE(sync_venn) && n_sets >= 2L && length(list_in)) {
    ## 图截前 4 时用定稿方法全集交集；与 consensus final 对齐，不用更大的图心覆盖
    if (isTRUE(plot_subset) && length(selected_methods) >= 2L) {
      list_canon <- .fsv08_venn_list_for_final(
        by_model, selected_methods, final, U, comp_in_final, exposure_vars
      )
      venn_center <- if (length(list_canon) >= 2L) {
        Reduce(intersect, list_canon)
      } else {
        final
      }
    } else {
      venn_center <- Reduce(intersect, list_in)
    }
    venn_center <- unique(as.character(venn_center[nzchar(as.character(venn_center))]))
    venn_center <- .fsv08_require_exposure_in_features(ctx, venn_center, cfg, fsv_cfg)
    if (isTRUE(plot_subset)) {
      keep <- unique(as.character(final[nzchar(as.character(final))]))
      keep <- .fsv08_require_exposure_in_features(ctx, keep, cfg, fsv_cfg)
      ctx$results$feature_selection_venn_center <- keep
      ctx$results$ml_feature_names <- keep
      ctx$results$shap_plot_feature_names <- keep
      if (length(venn_center) && !setequal(venn_center, keep)) {
        cli::cli_alert_warning(
          "定稿方法全集交集 n={length(venn_center)} 与 consensus final n={length(keep)} 不一致，保留 consensus final，不覆盖。"
        )
      } else {
        cli::cli_alert_info(
          "韦恩图为定稿方法子集，已保留 consensus final {length(keep)} 个 ML/SHAP 特征: {paste(keep, collapse = ', ')}"
        )
      }
    } else if (length(venn_center)) {
      ctx$results$feature_selection_final <- venn_center
      ctx$results$Model2Factors <- venn_center
      ctx$results$ml_feature_names <- venn_center
      ctx$results$feature_selection_venn_center <- venn_center
      ctx$results$shap_plot_feature_names <- venn_center
      cli::cli_alert_info(
        "韦恩中心 {length(venn_center)} 个变量已同步为 ML/SHAP 特征: {paste(venn_center, collapse = ', ')}"
      )
      data_dir <- file.path(ctx$output_dir, "Data")
      if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
      tryCatch(
        saveRDS(venn_center, file.path(data_dir, "feature_selection_final.rds")),
        error = function(e) NULL
      )
      tryCatch(
        saveRDS(venn_center, file.path(ctx$output_dir, "feature_selection_final.rds")),
        error = function(e) NULL
      )
    }
  }

  ctx
}

register_block(
  "feature_selection_venn",
  block_feature_selection_venn,
  "特征选择方法重叠图（韦恩/Euler/UpSet，Figure S1）"
)
