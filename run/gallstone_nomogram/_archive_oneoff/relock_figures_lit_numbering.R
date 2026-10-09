#!/usr/bin/env Rscript
# 胆结石列线图：按文献 Fig1–9 重锁图号；预测套图只保留一套（【success】NOMOGRAM）
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/gallstone_nomogram/relock_figures_lit_numbering.R \
#     --project "G:/02block_result/45_Gallstone/Nomogram_"

`%||%` <- function(a, b) if (!is.null(a)) a else b

.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]]
  else "G:/02block_result/45_Gallstone/Nomogram_"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)

root_repo <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
source(file.path(root_repo, "R/pub_figure_export.R"), local = FALSE)

message("project: ", .proj)

# 文献锁定文件名（预测套 + Fig1）
.lit_pred <- c(
  "Figure 1. Inclusion exclusion flowchart.pdf",
  "Figure 4. LASSO regression analysis.pdf",
  "Figure 5. Multivariate logistic regression.pdf",
  "Figure 6. Nomogram prediction model.pdf",
  "Figure 7. ROC and calibration.pdf",
  "Figure 8. DCA.pdf",
  "Figure 9. CIC.pdf"
)

# 从任意路径池按「内容关键词」找最佳源（忽略当前错误图号）
.find_by_keywords <- function(paths, pattern, prefer_num = NULL) {
  bn <- basename(paths)
  hit <- paths[grepl(pattern, bn, ignore.case = TRUE, perl = TRUE)]
  if (!length(hit)) return(NA_character_)
  if (!is.null(prefer_num)) {
    pref <- hit[grepl(sprintf("^Figure %s\\\\.", prefer_num), basename(hit))]
    if (length(pref)) return(pref[[1L]])
  }
  # 优先体积更大的非空文件
  sz <- file.info(hit)$size
  hit <- hit[order(sz, decreasing = TRUE)]
  hit[[1L]]
}

.collect_pdfs <- function(dirs) {
  out <- character(0)
  for (d in dirs) {
    if (!dir.exists(d)) next
    out <- c(out, list.files(d, pattern = "\\.pdf$", full.names = TRUE, recursive = TRUE))
  }
  unique(out[file.exists(out) & !is.na(file.info(out)$size) & file.info(out)$size > 0])
}

.pool <- .collect_pdfs(c(
  file.path(.proj, "Figures"),
  file.path(.proj, "Figures", "pdf"),
  file.path(.proj, "_shared", "Figures"),
  file.path(.proj, "_shared", "Figures", "pdf"),
  file.path(.proj, "_shared"),
  file.path(.proj, "by_index")
))

.map_src <- list(
  "Figure 1. Inclusion exclusion flowchart.pdf" =
    .find_by_keywords(.pool, "flowchart|Inclusion", prefer_num = 1L),
  "Figure 4. LASSO regression analysis.pdf" =
    .find_by_keywords(.pool, "LASSO", prefer_num = 4L),
  "Figure 5. Multivariate logistic regression.pdf" =
    .find_by_keywords(.pool, "Multivariate", prefer_num = 5L),
  "Figure 6. Nomogram prediction model.pdf" =
    .find_by_keywords(.pool, "Nomogram", prefer_num = 6L),
  "Figure 7. ROC and calibration.pdf" =
    .find_by_keywords(.pool, "ROC", prefer_num = 7L),
  "Figure 8. DCA.pdf" =
    .find_by_keywords(.pool, "(^| )DCA(\\.| )", prefer_num = 8L),
  "Figure 9. CIC.pdf" =
    .find_by_keywords(.pool, "(^| )CIC(\\.| )", prefer_num = 9L)
)

message("source map:")
for (nm in names(.map_src)) {
  message("  ", nm, " <- ", .map_src[[nm]] %||% "<MISSING>")
}

.nom_root <- file.path(.proj, "by_index", paste0("\u3010success\u3011", "NOMOGRAM"), "summary_results")
.nom_fig <- file.path(.nom_root, "Figures")
.nom_tab <- file.path(.nom_root, "Tables")
.nom_pdf <- file.path(.nom_fig, "pdf")
dir.create(.nom_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(.nom_tab, recursive = TRUE, showWarnings = FALSE)

# 清空 NOMOGRAM 旧图后写入锁定套
if (dir.exists(.nom_fig)) {
  old <- list.files(.nom_fig, recursive = TRUE, full.names = TRUE)
  unlink(old[file.exists(old) & !dir.exists(old)])
}
dir.create(.nom_pdf, recursive = TRUE, showWarnings = FALSE)

for (nm in names(.map_src)) {
  src <- .map_src[[nm]]
  if (is.na(src) || !file.exists(src)) {
    warning("缺源: ", nm)
    next
  }
  dest <- file.path(.nom_pdf, nm)
  file.copy(src, dest, overwrite = TRUE)
  message("NOMOGRAM <- ", basename(src), " => ", nm)
}

# 同步 Tables（预测相关）到 NOMOGRAM
.tab_pool <- unique(c(
  list.files(file.path(.proj, "Tables"), full.names = TRUE),
  list.files(file.path(.proj, "_shared", "Tables"), full.names = TRUE)
))
.tab_keep <- c(
  "Flowchart_attrition.csv",
  "Table 1. Baseline by Success.csv",
  "Table 2. Train vs validation baseline.csv",
  "Table_LASSO_selected_lambda1se.csv",
  "Table_multivariate_logistic.csv",
  "Table_AUC_train_val_boot.csv",
  "Methods_split_denominator_note.txt"
)
for (tb in .tab_keep) {
  src <- .tab_pool[basename(.tab_pool) == tb]
  if (length(src)) file.copy(src[[1L]], file.path(.nom_tab, tb), overwrite = TRUE)
}

writeLines(c(
  "# 【success】NOMOGRAM — 预测套图唯一发表目录",
  "",
  "文献图号锁定：",
  "- Figure 1 Flowchart",
  "- Figure 4 LASSO",
  "- Figure 5 Multivariate logistic",
  "- Figure 6 Nomogram",
  "- Figure 7 ROC + calibration（第三面板=bootstrap，非外库）",
  "- Figure 8 DCA",
  "- Figure 9 CIC",
  "",
  "各连续特征单元只保留 Figure 2 Associations / Figure 3 RCS / Figure S Subgroup。",
  "禁止 pub_renumber 顺延压缩图号（config$pub$renumber=FALSE）。"
), file.path(.nom_root, "README.md"))

# 项目根 + _shared：写成同一套锁定名（先清再拷）
.rewrite_dir_pdf <- function(fig_root) {
  pdf_dir <- if (dir.exists(file.path(fig_root, "pdf"))) file.path(fig_root, "pdf") else fig_root
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  # 删除错误编号的预测相关平铺 pdf
  old <- list.files(pdf_dir, pattern = "Figure.*\\.pdf$", full.names = TRUE)
  unlink(old)
  for (nm in names(.map_src)) {
    src <- file.path(.nom_pdf, nm)
    if (file.exists(src)) file.copy(src, file.path(pdf_dir, nm), overwrite = TRUE)
  }
}

.rewrite_dir_pdf(file.path(.proj, "Figures"))
.rewrite_dir_pdf(file.path(.proj, "_shared", "Figures"))

# 各连续特征 success：只留 Fig2/3/S；删预测套重复
.unit_dirs <- list.dirs(file.path(.proj, "by_index"), recursive = FALSE)
.unit_dirs <- .unit_dirs[grepl("\u3010success\u3011", basename(.unit_dirs))]
.unit_dirs <- .unit_dirs[!grepl("NOMOGRAM$", basename(.unit_dirs))]

.pred_pat <- "(LASSO|Multivariate|Nomogram|ROC|calibration|DCA|CIC|flowchart|Inclusion)"

for (ud in .unit_dirs) {
  feat <- sub(".*\u3010success\u3011", "", basename(ud))
  fig <- file.path(ud, "summary_results", "Figures")
  pdf_dir <- file.path(fig, "pdf")
  if (!dir.exists(pdf_dir)) pdf_dir <- fig
  if (!dir.exists(pdf_dir)) next

  # 定位本特征 Associations / RCS / Subgroup
  all_pdf <- list.files(pdf_dir, pattern = "\\.pdf$", full.names = TRUE)
  # 也从 unit Tables/Figures 非 pdf 子目录找
  more <- list.files(file.path(ud, "summary_results"), pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
  pool_u <- unique(c(all_pdf, more))

  assoc <- pool_u[grepl(paste0("Associations.*", feat), basename(pool_u), ignore.case = TRUE) |
                    grepl(paste0("Associations ", feat), basename(pool_u), ignore.case = TRUE)]
  if (!length(assoc)) assoc <- pool_u[grepl("Associations", basename(pool_u), ignore.case = TRUE)]
  rcs <- pool_u[grepl(paste0("RCS.*", feat), basename(pool_u), ignore.case = TRUE) |
                  grepl(paste0("RCS ", feat), basename(pool_u), ignore.case = TRUE)]
  if (!length(rcs)) rcs <- pool_u[grepl("RCS", basename(pool_u), ignore.case = TRUE)]
  subg <- pool_u[grepl("Subgroup", basename(pool_u), ignore.case = TRUE)]

  # 清空 pdf 目录后只写入 2/3/S
  unlink(list.files(pdf_dir, full.names = TRUE))
  # 同步清 png/tiff/image_information 将由 ensure_formats 重建
  for (sub in c("png", "tiff", "image_information")) {
    sd <- file.path(fig, sub)
    if (dir.exists(sd)) unlink(list.files(sd, full.names = TRUE, recursive = TRUE))
  }

  if (length(assoc)) {
    file.copy(assoc[[1L]], file.path(pdf_dir, sprintf("Figure 2. Associations %s.pdf", feat)), overwrite = TRUE)
  }
  if (length(rcs)) {
    file.copy(rcs[[1L]], file.path(pdf_dir, sprintf("Figure 3. RCS %s.pdf", feat)), overwrite = TRUE)
  }
  if (length(subg)) {
    file.copy(subg[[1L]], file.path(pdf_dir, sprintf("Figure S. Subgroup %s.pdf", feat)), overwrite = TRUE)
  }
  message("unit cleaned: ", feat,
          " assoc=", length(assoc) > 0, " rcs=", length(rcs) > 0, " sub=", length(subg) > 0)
}

# 四目录导出（关 renumber：ensure_formats 本身不顺延号）
.ensure <- function(fg) {
  if (!dir.exists(fg)) return(invisible(NULL))
  tryCatch(
    pub_figure_ensure_formats(fg, meta = list(note = "lit-locked"), config = list(pub = list(renumber = FALSE))),
    error = function(e) message("ensure_formats WARN: ", conditionMessage(e))
  )
}

.ensure(.nom_fig)
.ensure(file.path(.proj, "Figures"))
.ensure(file.path(.proj, "_shared", "Figures"))
for (ud in .unit_dirs) {
  .ensure(file.path(ud, "summary_results", "Figures"))
}

# 清单
.write_manifest <- function(path, files) {
  writeLines(c("# Figure lock manifest", "", files), path)
}
.write_manifest(
  file.path(.nom_root, "FIGURE_LOCK.md"),
  c(
    "Fig1 flowchart", "Fig4 LASSO", "Fig5 multivariate", "Fig6 nomogram",
    "Fig7 ROC+cal (bootstrap panel)", "Fig8 DCA", "Fig9 CIC",
    "Per-feature units: Fig2 Associations / Fig3 RCS / Fig S Subgroup only"
  )
)

message("DONE relock → ", .nom_root)

# 重锁后：文献对齐汇总（Fig1–9 连续，含 Fig2/3）+ 按特征关联目录
.rs <- Sys.which("Rscript")
if (!nzchar(.rs) && file.exists("/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"))
  .rs <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
.reorg <- file.path(.root, "run/gallstone_nomogram/reorganize_publication_layout.R")
.lit <- file.path(.root, "run/gallstone_nomogram/rebuild_summary_lit_aligned.R")
if (nzchar(.rs) && file.exists(.reorg)) {
  message("→ reorganize publication layout …")
  system2(.rs, args = c(.reorg, "--project", .proj))
}
if (nzchar(.rs) && file.exists(.lit)) {
  message("→ rebuild lit-aligned summary Fig1–9 …")
  system2(.rs, args = c(.lit, "--project", .proj))
}
