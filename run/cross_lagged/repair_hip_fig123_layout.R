#!/usr/bin/env Rscript
# 髋部交付 Fig1–3 版式返工（50/65）：
# - Fig1：去掉面板内 “Figure 1. XX — Inclusion / Exclusion” 小标题；外标仅库名
# - Fig2：拼图不写 A/B/C/D 字母（仅库名）；竖拼四库 RCS
# - Fig3：2×2（上二下二）四库亚组
#
# MEDICAL_BLOCKS_ROOT=... Rscript run/cross_lagged/repair_hip_fig123_layout.R

`%||%` <- function(a, b) if (is.null(a) || !length(a) || (length(a) == 1L && is.na(a))) b else a

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) {
  cmd <- commandArgs(trailingOnly = FALSE)
  fa <- sub("^--file=", "", cmd[grepl("^--file=", cmd)][1L])
  root <- normalizePath(file.path(dirname(fa), "../.."), winslash = "/", mustWork = TRUE)
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/attrition_log.R"), local = FALSE)
source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

.pick_newest <- function(paths) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(NA_character_)
  paths[order(file.info(paths)$mtime, decreasing = TRUE)][[1L]]
}

.find_rcs <- function(engine, db) {
  if (identical(db, "Pooled")) {
    return(.pick_newest(c(
      file.path(engine, "phase3_post_Pooled/step03_rcs_incidence/Figures/Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf"),
      file.path(engine, "phase3_post_Pooled/step02_rcs_incidence/Figures/Figure 2-Pooled. RCS of Frailty Index and Hip Fracture.pdf")
    )))
  }
  base <- file.path(engine, paste0("phase1_", db, "_allages"))
  cands <- list.files(base, pattern = paste0("Figure 2-", db, "\\. RCS.*\\.pdf$"),
                      full.names = TRUE, recursive = TRUE)
  prefer <- cands[grepl("step\\d+_rcs_incidence", cands)]
  .pick_newest(if (length(prefer)) prefer else cands)
}

.find_forest <- function(engine, db) {
  if (identical(db, "Pooled")) {
    return(.pick_newest(c(
      file.path(engine, "phase3_post_Pooled/Figures/Figure 3-Pooled. Subgroup Forest analyses of FI.pdf"),
      file.path(engine, "phase3_post_Pooled/Figures/Figure 2-UnknownDB. Subgroup Forest analyses of FI.pdf")
    )))
  }
  base <- file.path(engine, paste0("phase1_", db, "_allages"))
  cands <- list.files(base, pattern = paste0("Figure 3-", db, "\\. Subgroup.*\\.pdf$"),
                      full.names = TRUE, recursive = TRUE)
  prefer <- cands[grepl("step\\d+_subgroup", cands)]
  .pick_newest(if (length(prefer)) prefer else cands)
}

.redraw_fig1_panel <- function(engine, db, out_pdf) {
  draw_csv <- file.path(
    engine, paste0("phase3_long_", db), "Tables",
    sprintf("Flowchart_attrition_%s_draw.csv", db)
  )
  if (!file.exists(draw_csv)) {
    draw_csv <- file.path(
      engine, paste0("phase3_long_", db), "Tables",
      sprintf("Flowchart_attrition_%s.csv", db)
    )
  }
  stopifnot(file.exists(draw_csv))
  rows <- utils::read.csv(draw_csv, stringsAsFactors = FALSE, check.names = FALSE)
  # 不要面板内 Figure 1. XX — Inclusion 小标题
  ok <- attrition_draw_pdf(rows, title = "", out_pdf)
  if (!isTRUE(ok) || !file.exists(out_pdf)) stop("Fig1 panel failed: ", db)
  invisible(out_pdf)
}

.repair_cut <- function(cut) {
  engine <- file.path(root, sprintf("Output/16_Hip_fracture_cross-laged_40595747_age%s", cut))
  dest <- sprintf(
    "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result（%s）",
    cut
  )
  stopifnot(dir.exists(engine), dir.exists(dest))
  pdf_dir <- file.path(dest, "Figures", "pdf")
  md_dir <- file.path(dest, "Figures", "image_information")
  work <- file.path(tempdir(), sprintf("hip_fig123_age%s", cut))
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)

  # ---- Fig1 ----
  f1_panels <- character(0)
  for (db in c("CHARLS", "ELSA", "HRS")) {
    p <- file.path(work, sprintf("Fig1_%s.pdf", db))
    .redraw_fig1_panel(engine, db, p)
    f1_panels <- c(f1_panels, p)
  }
  f1_out <- file.path(pdf_dir, "Figure 1. Inclusion exclusion flowchart.pdf")
  .dual_db_compose_n_pdf_vector(
    f1_panels,
    c("CHARLS", "ELSA", "HRS"),
    f1_out,
    layout = "side"
  )

  # ---- Fig2：无拼图 A/B/C/D；子图标题去 A./B./C. 前缀 ----
  f2_paths <- vapply(c("CHARLS", "ELSA", "HRS", "Pooled"), function(db) {
    p <- .find_rcs(engine, db)
    if (is.na(p) || !file.exists(p)) stop("missing RCS: ", db)
    stripped <- file.path(work, sprintf("Fig2_%s_stripped.pdf", db))
    py <- sprintf(
      paste(
        "import fitz",
        "doc=fitz.open(%s)",
        "page=doc[0]",
        "for old,new in [('A.Crude Model','Crude Model'),('B.Model 1','Model 1'),('C.Model 2','Model 2')]:",
        "  for r in page.search_for(old):",
        "    page.add_redact_annot(r,text=new,fontsize=9,fontname='times-bold',text_color=(0,0,0),fill=(1,1,1))",
        "page.apply_redactions(); doc.save(%s); doc.close()",
        sep = "\n"
      ),
      shQuote(p, type = "cmd"),
      shQuote(stripped, type = "cmd")
    )
    status <- system2("python3", args = c("-c", py))
    if (!identical(as.integer(status), 0L) || !file.exists(stripped)) {
      stop("Fig2 strip failed: ", db)
    }
    stripped
  }, character(1))
  f2_out <- file.path(pdf_dir, "Figure 2. RCS of Frailty Index and Hip fracture.pdf")
  .dual_db_compose_n_pdf_vector(
    f2_paths,
    c("CHARLS", "ELSA", "HRS", "Pooled"),
    f2_out,
    layout = "stack"
  )

  # ---- Fig3：2×2 ----
  f3_paths <- vapply(c("CHARLS", "ELSA", "HRS", "Pooled"), function(db) {
    p <- .find_forest(engine, db)
    if (is.na(p) || !file.exists(p)) stop("missing forest: ", db)
    p
  }, character(1))
  f3_out <- file.path(pdf_dir, "Figure 3. Subgroup analyses of FI.pdf")
  .dual_db_compose_n_pdf_vector(
    f3_paths,
    c("CHARLS", "ELSA", "HRS", "Pooled"),
    f3_out,
    layout = "grid"
  )

  # image_information
  writeLines(c(
    "# Figure 1. Inclusion exclusion flowchart",
    "",
    "## 图面说明",
    "三栏横向：CHARLS、ELSA、HRS 纵向纳排流程；面板内无 “Figure 1. … Inclusion / Exclusion” 小标题，外标仅为库名。",
    "",
    "## 分析上下文",
    sprintf("Age ≥ %s; CHARLS + ELSA + HRS longitudinal inclusion/exclusion.", cut)
  ), file.path(md_dir, "Figure 1. Inclusion exclusion flowchart.md"), useBytes = TRUE)

  writeLines(c(
    "# Figure 2. RCS of Frailty Index and Hip fracture",
    "",
    "## 图面说明",
    "四面板竖拼：CHARLS、ELSA、HRS、Pooled；拼图外标仅为库名（无 A/B/C/D）。",
    "每库三条 RCS 标题为 Crude Model / Model 1 / Model 2（无 A/B/C 前缀）。",
    "",
    "## 分析上下文",
    sprintf("Age ≥ %s; FI continuous vs hip fracture; tertile gate aligned.", cut)
  ), file.path(md_dir, "Figure 2. RCS of Frailty Index and Hip fracture.md"), useBytes = TRUE)

  writeLines(c(
    "# Figure 3. Subgroup analyses of FI",
    "",
    "## 图面说明",
    "四面板 2×2：上排 CHARLS | ELSA，下排 HRS | Pooled；外标为库名。",
    "亚组为最高 vs 最低三分位（T3 vs T1），全分析集。",
    "",
    "## 分析上下文",
    sprintf("Age ≥ %s; FI tertile contrast; Pooled adjusted for Country.", cut)
  ), file.path(md_dir, "Figure 3. Subgroup analyses of FI.md"), useBytes = TRUE)

  tryCatch(
    pub_figure_ensure_formats(
      file.path(dest, "Figures"),
      config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))
    ),
    error = function(e) message("ensure_formats: ", conditionMessage(e))
  )

  message("OK age", cut, " Fig1/2/3 repaired")
  invisible(list(f1 = f1_out, f2 = f2_out, f3 = f3_out))
}

invisible(lapply(c("50", "65"), .repair_cut))
message("Done.")
