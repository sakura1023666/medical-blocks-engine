###############################################################################
#  cross_lagged_fig1_pub.R — 交叉滞后 Figure 1 分库重画 + 三（或 N）库拼图
#
#  抑郁×高血压等课题：CHARLS 等 xs-only 用 cross_lagged_draw_xs_fig1；
#  ELSA/HRS 用 phase3_long 纵向 Fig1；再拼成 summary_result/Figures 主文 Fig1。
#  禁止在结果目录堆 remosaic hotfix——统一走本文件 / run/cross_lagged/remosaic_fig1.R
###############################################################################

#' 解析交叉滞后课题根下的分库 Fig1 PDF 路径（xs 或 longitudinal）
cross_lagged_fig1_panel_paths <- function(study_root, dbs = NULL) {
  study_root <- as.character(study_root)[1L]
  if (!exists("cross_lagged_study_meta", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    sm <- file.path(root, "R/cross_lagged_study_meta.R")
    if (file.exists(sm)) source(sm, local = FALSE)
  }
  meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  xs <- as.character(meta$cohorts_xs %||% character(0))
  lg <- as.character(meta$cohorts_long %||% character(0))
  if (is.null(dbs) || !length(dbs)) {
    dbs <- unique(c(xs, lg))
  }
  dbs <- as.character(dbs)
  out <- list()
  for (db in dbs) {
    p1_cands <- c(
      file.path(study_root, paste0("phase1_", db, "_allages")),
      file.path(study_root, paste0("phase1_", db))
    )
    p1 <- p1_cands[dir.exists(p1_cands)][1L]
    xs_pdf <- if (!is.na(p1) && nzchar(p1)) {
      file.path(p1, "Figures", sprintf("Figure 1-%s. Inclusion exclusion flowchart.pdf", db))
    } else {
      NA_character_
    }
    long_pdf <- file.path(
      study_root, paste0("phase3_long_", db), "Figures",
      sprintf("Figure 1-%s. Longitudinal inclusion exclusion flowchart.pdf", db)
    )
    # 纵向库优先 long；xs-only（如抑郁课题 CHARLS）用横断面
    use_long <- db %in% lg && file.exists(long_pdf)
    path <- if (use_long) long_pdf else if (!is.na(xs_pdf) && file.exists(xs_pdf)) xs_pdf else NA_character_
    out[[db]] <- path
  }
  out
}

#' 重画 xs-only 库 Fig1（抑郁×HTN：CHARLS 抑郁阳性 + HTN 分叉）
cross_lagged_redraw_xs_fig1_panels <- function(study_root, dbs = NULL) {
  study_root <- as.character(study_root)[1L]
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  for (f in c(
    file.path(root, "R/utils.R"),
    file.path(root, "R/attrition_log.R"),
    file.path(root, "R/cross_lagged_study_meta.R"),
    file.path(root, "R/cross_lagged_xs_flowchart.R")
  )) {
    if (file.exists(f)) source(f, local = FALSE)
  }
  meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  xs <- as.character(meta$cohorts_xs %||% character(0))
  lg <- as.character(meta$cohorts_long %||% character(0))
  xs_only <- setdiff(xs, lg)
  if (!is.null(dbs) && length(dbs)) xs_only <- intersect(xs_only, as.character(dbs))
  paths <- character(0)
  for (db in xs_only) {
    if (!exists("cross_lagged_draw_xs_fig1", mode = "function")) next
    p <- tryCatch(cross_lagged_draw_xs_fig1(study_root, db), error = function(e) {
      warning(db, " xs fig1: ", conditionMessage(e), call. = FALSE)
      NULL
    })
    if (!is.null(p) && file.exists(p)) paths <- c(paths, p)
  }
  invisible(paths)
}

#' 拼主文 Figure 1 到 summary_result/Figures（四目录 + 600 dpi）
#'
#' @param study_root 课题根（含 phase1_* / phase3_long_*）
#' @param redraw_xs 先重画 xs-only 面板（默认 TRUE）
#' @param labels 面板标签；默认 A/B/C + 库名
#' @param out_stem 主文图 stem（无扩展名）
cross_lagged_remosaic_fig1 <- function(study_root,
                                       redraw_xs = TRUE,
                                       labels = NULL,
                                       out_stem = "Figure 1. Inclusion exclusion flowchart",
                                       layout = "side") {
  study_root <- as.character(study_root)[1L]
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  for (f in c(
    file.path(root, "R/utils.R"),
    file.path(root, "R/dual_db_combine_figures.R"),
    file.path(root, "R/pub_figure_export.R"),
    file.path(root, "R/cross_lagged_study_meta.R")
  )) {
    if (file.exists(f)) source(f, local = FALSE)
  }
  if (isTRUE(redraw_xs)) {
    cross_lagged_redraw_xs_fig1_panels(study_root)
  }
  meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  # 拼图顺序：xs 声明顺序（抑郁课题 CHARLS, ELSA, HRS）
  dbs <- as.character(meta$cohorts_xs %||% names(cross_lagged_fig1_panel_paths(study_root)))
  panel_map <- cross_lagged_fig1_panel_paths(study_root, dbs = dbs)
  paths <- unlist(panel_map, use.names = FALSE)
  dbs_ok <- dbs[vapply(panel_map[dbs], function(p) is.character(p) && length(p) && file.exists(p), logical(1))]
  paths <- vapply(dbs_ok, function(db) panel_map[[db]], character(1))
  if (length(paths) < 2L) {
    stop("Fig1 拼图需要至少 2 个分库 PDF，当前: ", paste(dbs_ok, collapse = ", "), call. = FALSE)
  }
  if (is.null(labels) || !length(labels)) {
    letters_lab <- LETTERS[seq_along(dbs_ok)]
    labels <- paste0(letters_lab, ". ", dbs_ok)
  }
  fig_root <- file.path(study_root, "summary_result", "Figures")
  dir.create(file.path(fig_root, "pdf"), recursive = TRUE, showWarnings = FALSE)
  out_pdf <- file.path(fig_root, "pdf", paste0(out_stem, ".pdf"))
  if (!exists(".dual_db_compose_n_pdf_vector", mode = "function")) {
    stop("缺少 .dual_db_compose_n_pdf_vector（请 source R/dual_db_combine_figures.R）", call. = FALSE)
  }
  .dual_db_compose_n_pdf_vector(paths, labels, out_pdf, layout = layout)
  # 平铺一份供 ensure_formats 收纳
  flat <- file.path(fig_root, paste0(out_stem, ".pdf"))
  file.copy(out_pdf, flat, overwrite = TRUE)
  # 仅补本图栅格：删旧 png/tiff 后 ensure（purge=FALSE 保其它图）
  for (ext in c("png", "tiff")) {
    old <- file.path(fig_root, ext, paste0(out_stem, ".", ext))
    if (file.exists(old)) unlink(old)
  }
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    pub_figure_ensure_formats(fig_root, purge = FALSE)
  }
  if (file.exists(flat)) unlink(flat)
  # image_information（抑郁课题写清背景人群与分叉；其它 kind 写面板清单）
  md_dir <- file.path(fig_root, "image_information")
  dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)
  md <- file.path(md_dir, paste0(out_stem, ".md"))
  kind <- as.character(meta$kind %||% "")[1L]
  ann_extra <- character(0)
  if (identical(kind, "depression_htn_frailty")) {
    if (!exists("cross_lagged_depression_htn_baseline_attrition", mode = "function")) {
      xf <- file.path(root, "R/cross_lagged_xs_flowchart.R")
      if (file.exists(xf)) source(xf, local = FALSE)
    }
    bits <- character(0)
    for (db in dbs_ok) {
      rows <- tryCatch(
        cross_lagged_depression_htn_baseline_attrition(study_root, db, through = "depressed"),
        error = function(e) NULL
      )
      if (!is.data.frame(rows) || nrow(rows) < 2L) next
      n_fi <- rows$n[1L]
      n_dep <- rows$n[nrow(rows)]
      n_htn <- attr(rows, "n_htn")
      n_free <- attr(rows, "n_free")
      bits <- c(bits, sprintf(
        "- %s：FI 基线 %s → 抑郁阳性 %s（Table 1）；分叉 HTN %s / 无 HTN %s",
        db,
        format(as.integer(n_fi), big.mark = ","),
        format(as.integer(n_dep), big.mark = ","),
        format(as.integer(n_htn), big.mark = ","),
        format(as.integer(n_free), big.mark = ",")
      ))
    }
    ann_extra <- c(
      "共同前段：Baseline with FI → Exclude CES-D negative → Depression-positive analytic sample（= Table 1 Overall）。",
      "xs-only（CHARLS）：止于抑郁阳性，底部分叉 Hypertension / No Hypertension。",
      "纵向库（ELSA/HRS）：再 Exclude 现患 → Disease-free → follow-up → wave1+wave2 终框分叉。",
      "",
      "### 图上标注",
      bits
    )
  }
  lines <- c(
    paste0("# ", out_stem),
    "",
    "## 图面说明",
    sprintf("分库拼图（%s）。", paste(labels, collapse = "；")),
    ann_extra,
    if (!length(ann_extra)) "各库纳入排除流程见分库面板。",
    "",
    "## 分析上下文",
    sprintf("- kind: %s", kind),
    sprintf("- 人群: %s", if (identical(kind, "depression_htn_frailty")) "基线 CES-D 抑郁症状阳性" else "见课题 meta"),
    sprintf("- cohorts_xs: %s", paste(meta$cohorts_xs %||% dbs_ok, collapse = ", ")),
    sprintf("- cohorts_long: %s", paste(meta$cohorts_long %||% character(0), collapse = ", ")),
    "- 是否拼图: 是"
  )
  writeLines(unlist(lines), md)
  invisible(list(
    out_pdf = out_pdf,
    panels = paths,
    labels = labels,
    dbs = dbs_ok
  ))
}
