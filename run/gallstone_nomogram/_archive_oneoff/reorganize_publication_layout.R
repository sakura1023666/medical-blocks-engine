#!/usr/bin/env Rscript
# 胆结石列线图：统一发表落盘（禁止 Figures 根平铺 PDF）
#   summary_results/Figures/{pdf,png,tiff,image_information}/  ← 主入口 Fig1–9 + S
#   association_by_feature/<feat>/Figures/{pdf,...}/           ← 单特征 Fig2/3/S
#   by_index/【success】*                                       ← 引擎中间产物（非浏览入口）
#
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/gallstone_nomogram/reorganize_publication_layout.R \
#     --project "G:/02block_result/45_Gallstone/Nomogram_41815074"

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else
    "G:/02block_result/45_Gallstone/Nomogram_41815074"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
message("project: ", .proj)

.root <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)

.sum <- file.path(.proj, "summary_results")
.fig <- file.path(.sum, "Figures")
.assoc <- file.path(.proj, "association_by_feature")
.bi <- file.path(.proj, "by_index")
.nom_fig_pdf <- file.path(.bi, "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "pdf")
.feats <- c("Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
            "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots")
# 仅保留列线图连续变量的关联目录；其余删除（不进补充）
.feats_assoc_keep <- c("pct_lt40", "pct_gt80")

dir.create(file.path(.fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(.assoc, recursive = TRUE, showWarnings = FALSE)

# ---------- helpers ----------
.strip_flat_into_pdf <- function(fig_root) {
  if (!dir.exists(fig_root)) return(invisible(0L))
  pdf_dir <- file.path(fig_root, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  flats <- list.files(fig_root, pattern = "^Figure.*\\.pdf$", full.names = TRUE)
  n <- 0L
  for (f in flats) {
    file.copy(f, file.path(pdf_dir, basename(f)), overwrite = TRUE)
    unlink(f)
    n <- n + 1L
  }
  invisible(n)
}

.harvest_pdfs_into <- function(dest_pdf, sources) {
  dir.create(dest_pdf, recursive = TRUE, showWarnings = FALSE)
  dest_pdf_n <- normalizePath(dest_pdf, winslash = "/", mustWork = FALSE)
  n <- 0L
  for (src in sources) {
    if (!file.exists(src)) next
    if (dir.exists(src)) {
      src_n <- normalizePath(src, winslash = "/", mustWork = FALSE)
      if (identical(src_n, dest_pdf_n)) next
      pdfs <- list.files(src, pattern = "^Figure.*\\.pdf$", full.names = TRUE)
      for (p in pdfs) {
        dest_f <- file.path(dest_pdf, basename(p))
        if (normalizePath(p, winslash = "/", mustWork = FALSE) ==
            normalizePath(dest_f, winslash = "/", mustWork = FALSE)) next
        file.copy(p, dest_f, overwrite = TRUE)
        n <- n + 1L
      }
    } else if (grepl("\\.pdf$", src, ignore.case = TRUE)) {
      dest_f <- file.path(dest_pdf, basename(src))
      if (normalizePath(src, winslash = "/", mustWork = FALSE) ==
          normalizePath(dest_f, winslash = "/", mustWork = FALSE)) next
      file.copy(src, dest_f, overwrite = TRUE)
      n <- n + 1L
    }
  }
  invisible(n)
}

# ---------- 1) 主入口 summary_results：收齐 Fig1–9 + S 到 pdf/ ----------
message("→ consolidate summary_results/Figures/pdf …")
.sum_pdf <- file.path(.fig, "pdf")
.harvest_pdfs_into(.sum_pdf, c(
  .sum_pdf,
  .fig,
  .nom_fig_pdf,
  file.path(.proj, "Figures", "pdf"),
  file.path(.proj, "Figures"),
  file.path(.proj, "_shared", "Figures", "pdf"),
  file.path(.proj, "_shared", "Figures")
))
.strip_flat_into_pdf(.fig)

# Fig1 若仍缺，从根/_shared 再捞
if (!file.exists(file.path(.sum_pdf, "Figure 1. Inclusion exclusion flowchart.pdf"))) {
  .harvest_pdfs_into(.sum_pdf, list.files(
    c(file.path(.proj, "Figures"), file.path(.proj, "_shared", "Figures"),
      file.path(.proj, "Figures", "pdf"), file.path(.proj, "_shared", "Figures", "pdf")),
    pattern = "Figure 1.*\\.pdf$", full.names = TRUE, recursive = TRUE
  ))
}

.have <- list.files(.sum_pdf, pattern = "^Figure.*\\.pdf$")
message("summary pdf count=", length(.have), ": ", paste(.have, collapse = " | "))

# 同步 summary → NOMOGRAM / 根 Figures/pdf / _shared/Figures/pdf（单向，主入口优先）
for (d in c(
  .nom_fig_pdf,
  file.path(.proj, "Figures", "pdf"),
  file.path(.proj, "_shared", "Figures", "pdf")
)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  for (p in list.files(.sum_pdf, pattern = "^Figure.*\\.pdf$", full.names = TRUE)) {
    file.copy(p, file.path(d, basename(p)), overwrite = TRUE)
  }
}

# 清掉各处 Figures 根平铺
for (fr in c(.fig,
             file.path(.proj, "Figures"),
             file.path(.proj, "_shared", "Figures"),
             file.path(.bi, "\u3010success\u3011NOMOGRAM", "summary_results", "Figures"))) {
  n <- .strip_flat_into_pdf(fr)
  if (n > 0) message("stripped flat pdfs: ", fr, " n=", n)
}

# 四目录
tryCatch(
  pub_figure_ensure_formats(.fig, config = list(pub = list(renumber = FALSE))),
  error = function(e) message("summary formats: ", conditionMessage(e))
)
tryCatch(
  pub_figure_ensure_formats(file.path(.proj, "Figures"),
                            config = list(pub = list(renumber = FALSE))),
  error = function(e) message("root Figures formats: ", conditionMessage(e))
)
tryCatch(
  pub_figure_ensure_formats(file.path(.proj, "_shared", "Figures"),
                            config = list(pub = list(renumber = FALSE))),
  error = function(e) message("_shared formats: ", conditionMessage(e))
)

# ---------- 2) association_by_feature：仅列线图连续变量 ----------
message("→ association_by_feature (keep=", paste(.feats_assoc_keep, collapse = ","), ") …")
# 删掉非保留特征目录（用户要求其余不进补充）
if (dir.exists(.assoc)) {
  for (d in list.dirs(.assoc, recursive = FALSE)) {
    if (!(basename(d) %in% .feats_assoc_keep)) {
      unlink(d, recursive = TRUE)
      message("removed association_by_feature/", basename(d))
    }
  }
}
for (feat in .feats_assoc_keep) {
  dest <- file.path(.assoc, feat)
  dest_fig <- file.path(dest, "Figures")
  dest_pdf <- file.path(dest_fig, "pdf")
  dest_tab <- file.path(dest, "Tables")
  dir.create(dest_pdf, recursive = TRUE, showWarnings = FALSE)
  dir.create(dest_tab, recursive = TRUE, showWarnings = FALSE)

  src_cands <- c(
    file.path(.proj, "by_unit", feat, "Figures", "pdf"),
    file.path(.proj, "by_unit", paste0("\u3010success\u3011", feat), "Figures", "pdf"),
    file.path(.proj, "by_unit", feat, "Figures"),
    file.path(.proj, "by_unit", paste0("\u3010success\u3011", feat), "Figures"),
    file.path(.bi, paste0("\u3010success\u3011", feat), "summary_results", "Figures", "pdf"),
    file.path(.bi, paste0("\u3010success\u3011", feat), "summary_results", "Figures")
  )
  pdfs <- character(0)
  for (s in src_cands) {
    if (!dir.exists(s)) next
    hit <- list.files(s, pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
    hit <- hit[grepl("Associations|RCS|Subgroup", basename(hit), ignore.case = TRUE)]
    hit <- hit[!grepl("LASSO|Nomogram|ROC|DCA|CIC|Multivariate|flowchart|Inclusion|continuous features",
                      basename(hit), ignore.case = TRUE)]
    if (length(hit)) {
      pdfs <- hit
      break
    }
  }
  # 清旧再写
  old <- list.files(dest_pdf, full.names = TRUE)
  if (length(old)) unlink(old)
  for (p in pdfs) {
    bn <- basename(p)
    if (grepl("Associations", bn, ignore.case = TRUE))
      bn <- sprintf("Figure 2. Associations %s.pdf", feat)
    else if (grepl("RCS", bn, ignore.case = TRUE))
      bn <- sprintf("Figure 3. RCS %s.pdf", feat)
    else if (grepl("Subgroup", bn, ignore.case = TRUE))
      bn <- sprintf("Figure S. Subgroup %s.pdf", feat)
    file.copy(p, file.path(dest_pdf, bn), overwrite = TRUE)
  }
  .strip_flat_into_pdf(dest_fig)
  tryCatch(
    pub_figure_ensure_formats(dest_fig, meta = list(feature = feat),
                              config = list(pub = list(renumber = FALSE))),
    error = function(e) message("formats WARN ", feat, ": ", conditionMessage(e))
  )

  # tables
  for (td in c(
    file.path(.proj, "by_unit", feat, "Tables"),
    file.path(.proj, "by_unit", paste0("\u3010success\u3011", feat), "Tables"),
    file.path(.bi, paste0("\u3010success\u3011", feat), "summary_results", "Tables")
  )) {
    if (!dir.exists(td)) next
    for (f in list.files(td, full.names = TRUE)) {
      if (!dir.exists(f) && grepl("assoc|RCS|subgroup|OR|Methods_assoc|UV", basename(f), ignore.case = TRUE))
        file.copy(f, file.path(dest_tab, basename(f)), overwrite = TRUE)
    }
  }
  writeLines(c(
    paste0("# 关联分析 — ", feat),
    "",
    "本目录仅含该连续特征相对 Success 的 Fig2 / Fig3 / FigS。",
    "主文 Fig1–9 请看项目根 `summary_results/Figures/pdf/`。"
  ), file.path(dest, "README.md"))
  message("association_by_feature/", feat, " n_pdf=",
          length(list.files(dest_pdf, pattern = "\\.pdf$")))
}

# ---------- 3) README ----------
writeLines(c(
  "# 胆结石碎石成功列线图 — 目录说明",
  "",
  "## 主入口（请从这里看）",
  "",
  "```",
  "summary_results/",
  "  Figures/pdf/   Figure 1 → 9 + S1/S2",
  "  Figures/png|tiff|image_information/",
  "  Tables/",
  "```",
  "",
  "## 单特征关联（不是 10 个独立课题）",
  "",
  "```",
  "association_by_feature/<feat>/Figures/pdf/   Fig2 / Fig3 / FigS",
  "```",
  "",
  "`by_index/【success】*`、根目录 `Figures/`、`_shared/Figures/` 为镜像/中间产物，",
  "浏览以 `summary_results/` 为准。禁止在 Figures 根目录平铺 Figure*.pdf。"
), file.path(.proj, "README_目录说明.md"))

writeLines(c(
  "# by_index 是引擎中间产物",
  "",
  "请打开：",
  "- `../summary_results/Figures/pdf/` — 主文 Fig1–9",
  "- `../association_by_feature/` — 各特征 Fig2/3/S"
), file.path(.bi, "README_请看上一级summary_results.md"))

writeLines(c(
  "# summary_results — 主发表入口",
  "",
  "Figures/pdf/ 下应为 Figure 1–9 连续编号（含 Fig2 森林拼图、Fig3 RCS 拼图）。",
  "单特征明细见 `../association_by_feature/`。"
), file.path(.sum, "README.md"))

# 终检：summary 根不得残留平铺
.left <- list.files(.fig, pattern = "^Figure.*\\.pdf$")
if (length(.left)) {
  message("WARN still flat in summary Figures/: ", paste(.left, collapse = ", "))
} else {
  message("OK: no flat PDFs under summary_results/Figures/")
}
message("DONE layout → summary_results + association_by_feature")
