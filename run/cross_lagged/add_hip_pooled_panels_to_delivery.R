#!/usr/bin/env Rscript
# 髋部骨折交付 Fig2/Fig3 对齐抑郁：竖拼 A–D = CHARLS|ELSA|HRS|Pooled
# 仅改 summary_result（50）/（65）的 Fig2/Fig3 + image_information；不动 S6/S7 中介表。
#
# 用法：
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/cross_lagged/add_hip_pooled_panels_to_delivery.R

`%||%` <- function(a, b) if (is.null(a) || !length(a) || (length(a) == 1L && is.na(a))) b else a

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) {
  cmd <- commandArgs(trailingOnly = FALSE)
  fa <- sub("^--file=", "", cmd[grepl("^--file=", cmd)][1L])
  root <- normalizePath(file.path(dirname(fa), "../.."), winslash = "/", mustWork = TRUE)
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

.pick_newest <- function(paths) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(NA_character_)
  paths[order(file.info(paths)$mtime, decreasing = TRUE)][[1L]]
}

.find_db_rcs <- function(engine_root, db) {
  base <- file.path(engine_root, paste0("phase1_", db, "_allages"))
  cands <- list.files(
    file.path(base),
    pattern = paste0("Figure 2-", db, "\\. RCS of Frailty Index and Hip Fracture\\.pdf$"),
    full.names = TRUE, recursive = TRUE
  )
  # 优先 step*_rcs_incidence
  prefer <- cands[grepl("step\\d+_rcs_incidence", cands)]
  .pick_newest(if (length(prefer)) prefer else cands)
}

.find_db_forest <- function(engine_root, db) {
  base <- file.path(engine_root, paste0("phase1_", db, "_allages"))
  cands <- list.files(
    file.path(base),
    pattern = paste0("Figure 3-", db, "\\. Subgroup Forest analyses of FI\\.pdf$"),
    full.names = TRUE, recursive = TRUE
  )
  prefer <- cands[grepl("step\\d+_subgroup", cands)]
  .pick_newest(if (length(prefer)) prefer else cands)
}

.find_pooled_rcs <- function(engine_root) {
  cands <- c(
    file.path(engine_root, "phase3_post_Pooled/step03_rcs_incidence/Figures/Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf"),
    file.path(engine_root, "phase3_post_Pooled/step02_rcs_incidence/Figures/Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf"),
    file.path(engine_root, "summary_result/Figures/pdf/Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf")
  )
  .pick_newest(cands)
}

.find_pooled_forest <- function(engine_root) {
  cands <- c(
    file.path(engine_root, "phase3_post_Pooled/Figures/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf"),
    file.path(engine_root, "summary_result/figure/pdf/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf"),
    file.path(engine_root, "summary_result/Figures/pdf/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf")
  )
  .pick_newest(cands)
}

.write_md <- function(path, title, body_fig, body_ctx) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c(
      paste0("# ", title),
      "",
      "## 图面说明",
      body_fig,
      "",
      "## 分析上下文",
      body_ctx
    ),
    path,
    useBytes = TRUE
  )
}

.compose_one_cut <- function(cut) {
  engine <- file.path(
    root,
    sprintf("Output/16_Hip_fracture_cross-laged_40595747_age%s", cut)
  )
  dest <- sprintf(
    "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result（%s）",
    cut
  )
  stopifnot(dir.exists(engine), dir.exists(dest))
  pdf_dir <- file.path(dest, "Figures", "pdf")
  md_dir <- file.path(dest, "Figures", "image_information")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(md_dir, recursive = TRUE, showWarnings = FALSE)

  labels <- c("CHARLS", "ELSA", "HRS", "Pooled")
  rcs_paths <- c(
    .find_db_rcs(engine, "CHARLS"),
    .find_db_rcs(engine, "ELSA"),
    .find_db_rcs(engine, "HRS"),
    .find_pooled_rcs(engine)
  )
  forest_paths <- c(
    .find_db_forest(engine, "CHARLS"),
    .find_db_forest(engine, "ELSA"),
    .find_db_forest(engine, "HRS"),
    .find_pooled_forest(engine)
  )
  if (anyNA(rcs_paths) || !all(file.exists(rcs_paths))) {
    stop("age", cut, " RCS panels missing: ", paste(rcs_paths, collapse = " | "))
  }
  if (anyNA(forest_paths) || !all(file.exists(forest_paths))) {
    stop("age", cut, " forest panels missing: ", paste(forest_paths, collapse = " | "))
  }

  fig2 <- file.path(pdf_dir, "Figure 2. RCS of Frailty Index and Hip fracture.pdf")
  fig3 <- file.path(pdf_dir, "Figure 3. Subgroup analyses of FI.pdf")
  # RCS 竖拼；亚组 4 库 side→compose 自动 2×2（上下各二）
  .dual_db_compose_n_pdf_vector(rcs_paths, labels, fig2, layout = "stack")
  .dual_db_compose_n_pdf_vector(forest_paths, labels, fig3, layout = "side")

  age_note <- sprintf("Age ≥ %s analytic sample; CHARLS + ELSA + HRS + Pooled.", cut)
  .write_md(
    file.path(md_dir, "Figure 2. RCS of Frailty Index and Hip fracture.md"),
    "Figure 2. RCS of Frailty Index and Hip fracture",
    paste(
      "四面板竖拼：CHARLS、ELSA、HRS、Pooled（外标仅库名）；每库含 Crude / Model 1 / Model 2 三条 RCS。",
      "蓝线为 OR 点估计，阴影为 95% CI。图面 P for overall / P for nonlinear 以 PDF 文本为准。",
      sep = "\n"
    ),
    paste(
      age_note,
      "暴露: Frailty Index（连续）；结局: Hip fracture；Grouping: tertile（与主文 logistic 闸门一致）。",
      "是否拼图: 是（竖排，含 Pooled）。",
      sep = "\n"
    )
  )
  .write_md(
    file.path(md_dir, "Figure 3. Subgroup analyses of FI.md"),
    "Figure 3. Subgroup analyses of FI",
    paste(
      "四面板 2×2：上排 CHARLS|ELSA，下排 HRS|Pooled（外标仅库名）。亚组为最高 vs 最低三分位（T3 vs T1），全分析集估计。",
      "各层含 OR (95% CI)、P 与 P for interaction；NE 层为事件过少不可估。",
      sep = "\n"
    ),
    paste(
      age_note,
      "暴露: Frailty Index（T3 vs T1）；结局: Hip fracture；Grouping: tertile。",
      "Pooled 亚组调整含 Country（与 Table 2-Pooled Model2 一致）。",
      "是否拼图: 是（2×2，含 Pooled）。",
      sep = "\n"
    )
  )

  # 交付默认 PDF-only：刷新 ensure_formats（不强制 png/tiff）
  tryCatch(
    pub_figure_ensure_formats(file.path(dest, "Figures"), config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))),
    error = function(e) message("ensure_formats warn: ", conditionMessage(e))
  )

  message("OK age", cut, " Fig2=", fig2)
  message("OK age", cut, " Fig3=", fig3)
  invisible(list(fig2 = fig2, fig3 = fig3, rcs = rcs_paths, forest = forest_paths))
}

res50 <- .compose_one_cut("50")
res65 <- .compose_one_cut("65")
message("Done both cuts.")
