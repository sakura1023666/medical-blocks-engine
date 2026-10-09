#!/usr/bin/env Rscript
# 项目发表收口后自动质控入口（Phase 6）
# 结构盘点 + 写出报告骨架；Agent 须再按 pub-qc-after-project / nature_* skill 审 P0 并复检。
#
# Rscript run/pub/run_pub_qc_after_project.R \
#   --project /mnt/g/02block_result/45_Gallstone/Nomogram_41815074
#
# 环境变量：MEDICAL_BLOCKS_PROJECT_ROOT 可替代 --project

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]]
  else Sys.getenv("MEDICAL_BLOCKS_PROJECT_ROOT", unset = "")
}
if (!nzchar(.proj)) {
  stop("Usage: Rscript run/pub/run_pub_qc_after_project.R --project <project_root>")
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else getwd()
}
.day <- format(Sys.Date(), "%Y-%m-%d")
.rep <- file.path(.proj, "reports")
dir.create(.rep, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) message(paste0(...))
.message("pub-qc-after-project: ", .proj)

# ---------- success / failed inventory ----------
.bi <- file.path(.proj, "by_index")
.bu <- file.path(.proj, "by_unit")
.list_tag <- function(root, tag) {
  if (!dir.exists(root)) return(character(0))
  bn <- list.dirs(root, full.names = FALSE, recursive = FALSE)
  bn[grepl(paste0("^\u3010", tag, "\u3011"), bn)]
}
.success <- unique(c(.list_tag(.bi, "success"), .list_tag(.bu, "success")))
.failed <- unique(c(.list_tag(.bi, "failed"), .list_tag(.bu, "failed")))

# ---------- summary_results structure ----------
.sum <- file.path(.proj, "summary_results")
.fig <- file.path(.sum, "Figures")
.tab <- file.path(.sum, "Tables")
.has_sum <- dir.exists(.sum)
.pdfs <- if (dir.exists(file.path(.fig, "pdf"))) {
  list.files(file.path(.fig, "pdf"), pattern = "^Figure.*\\.pdf$")
} else character(0)
.pngs <- if (dir.exists(file.path(.fig, "png"))) {
  list.files(file.path(.fig, "png"), pattern = "^Figure.*\\.png$")
} else character(0)
.tiffs <- if (dir.exists(file.path(.fig, "tiff"))) {
  list.files(file.path(.fig, "tiff"), pattern = "^Figure.*\\.tiff$")
} else character(0)
.imds <- if (dir.exists(file.path(.fig, "image_information"))) {
  list.files(file.path(.fig, "image_information"), pattern = "^Figure.*\\.md$")
} else character(0)
.flat <- if (dir.exists(.fig)) {
  list.files(.fig, pattern = "^Figure.*\\.pdf$")
} else character(0)
.xlsx <- if (dir.exists(.tab)) list.files(.tab, pattern = "\\.xlsx$") else character(0)
.csv_main <- if (dir.exists(.tab)) {
  list.files(.tab, pattern = "\\.csv$")
} else character(0)

.zero_tiff <- character(0)
if (dir.exists(file.path(.fig, "tiff"))) {
  for (f in list.files(file.path(.fig, "tiff"), full.names = TRUE)) {
    if (file.info(f)$size < 1000) .zero_tiff <- c(.zero_tiff, basename(f))
  }
}

.imd_bad <- character(0)
if (dir.exists(file.path(.fig, "image_information"))) {
  for (f in list.files(file.path(.fig, "image_information"), pattern = "^Figure.*\\.md$", full.names = TRUE)) {
    t <- paste(readLines(f, warn = FALSE), collapse = "\n")
    if (!grepl("## 图面说明", t) || !grepl("## 分析上下文", t) ||
        grepl("## 标识", t) || grepl("## 技术", t)) {
      .imd_bad <- c(.imd_bad, basename(f))
    }
  }
}

.methods <- file.exists(file.path(.sum, "Methods_statistical_analysis.md"))

# 发表表/图注：单元格与 image_information 禁止下划线（程序列名除外）
.underscore_hits <- character(0)
if (requireNamespace("openxlsx", quietly = TRUE) && length(.xlsx)) {
  for (.xf in file.path(.tab, .xlsx)) {
    .d <- tryCatch(openxlsx::read.xlsx(.xf, sheet = 1, colNames = FALSE), error = function(e) NULL)
    if (is.null(.d)) next
    .cells <- as.character(unlist(.d, use.names = FALSE))
    .hit <- unique(.cells[!is.na(.cells) & grepl("_", .cells, fixed = TRUE)])
    # 忽略纯路径/扩展名误报较少：凡单元格含 _ 即记
    if (length(.hit)) {
      .underscore_hits <- c(
        .underscore_hits,
        sprintf("%s: %s", basename(.xf), paste(utils::head(.hit, 3), collapse = " | "))
      )
    }
  }
}
if (dir.exists(file.path(.fig, "image_information"))) {
  for (.mf in list.files(file.path(.fig, "image_information"), pattern = "\\.md$", full.names = TRUE)) {
    .mt <- paste(readLines(.mf, warn = FALSE), collapse = "\n")
    if (grepl("_", .mt, fixed = TRUE)) {
      .underscore_hits <- c(.underscore_hits, paste0("image_information/", basename(.mf)))
    }
  }
}

# Layer A hard fails
.fail <- character(0)
.warn <- character(0)
if (!.has_sum && !length(.success)) {
  .fail <- c(.fail, "无 summary_results 且无 【success】 可审")
}
if (length(.flat)) .fail <- c(.fail, paste0("Figures 根平铺 PDF: ", paste(.flat, collapse = ", ")))
if (length(.pdfs) && (length(.pngs) != length(.pdfs) || length(.tiffs) != length(.pdfs))) {
  .fail <- c(.fail, sprintf("四目录数量不一致 pdf=%d png=%d tiff=%d",
                            length(.pdfs), length(.pngs), length(.tiffs)))
}
if (length(.zero_tiff)) .fail <- c(.fail, paste0("过小 TIFF: ", paste(.zero_tiff, collapse = ", ")))
if (length(.imd_bad)) .warn <- c(.warn, paste0("image_information 结构异常: ", paste(.imd_bad, collapse = ", ")))
if (length(.csv_main)) .warn <- c(.warn, paste0("主序 Tables 仍有裸 CSV（发病套路应为 xlsx）: ",
                                                 paste(.csv_main, collapse = ", ")))
if (!.methods) .warn <- c(.warn, "缺 summary_results/Methods_statistical_analysis.md")
if (!length(.xlsx) && .has_sum) .warn <- c(.warn, "summary_results/Tables 无 xlsx")
if (length(.underscore_hits)) {
  .warn <- c(
    .warn,
    paste0(
      "发表表/图注含下划线（须用展示名，见 pipeline_scrub_pub_df）: ",
      paste(utils::head(.underscore_hits, 8), collapse = "; ")
    )
  )
}

.verdict <- if (length(.fail)) "FAIL" else if (length(.warn)) "WARN" else "PASS_STRUCTURE"
# Agent 必须继续跑 nature-statistics + nature-figure；结构 PASS 不等于交付 PASS

.lines <- c(
  "# 发表质控报告（自动骨架）",
  paste0("- 项目根：`", .proj, "`"),
  paste0("- 日期：", .day),
  paste0("- 审阅结论：**", .verdict, "**（结构层；Nature P0 须 Agent 按 skill 复检后改总评）"),
  "- 是否建议交稿：否（待 Nature Layer D P0 清零）",
  sprintf("- 审阅范围：【success】 n=%d；已跳过 【failed】 n=%d", length(.success), length(.failed)),
  "- Nature P0：待审 / 见同目录 nature_*_qc_*.md",
  "",
  "## Success / Failed",
  paste0("- success: ", if (length(.success)) paste(.success, collapse = ", ") else "（无 by_index/by_unit success；以 summary_results 为主）"),
  paste0("- failed: ", length(.failed)),
  "",
  "## Layer A — 结构",
  sprintf("- summary_results: %s", .has_sum),
  sprintf("- Figures pdf/png/tiff/image_information: %d / %d / %d / %d",
          length(.pdfs), length(.pngs), length(.tiffs), length(.imds)),
  sprintf("- 平铺 PDF: %d", length(.flat)),
  sprintf("- Tables xlsx: %d；主序 csv: %d", length(.xlsx), length(.csv_main)),
  sprintf("- Methods_statistical_analysis.md: %s", .methods),
  "",
  "### FAIL",
  if (length(.fail)) paste0("- ", .fail) else "- （无）",
  "",
  "### WARN",
  if (length(.warn)) paste0("- ", .warn) else "- （无）",
  "",
  "## Layer B/C/D — Agent 必做",
  "1. 按 `.cursor/skills/pub-qc-after-project/SKILL.md` 交叉数字 + 逻辑。",
  "2. 按 `nature-statistics` + `nature-figure` 审 Methods / 图注 / 面板；修全部 P0。",
  "3. 改图后 `pub_figure_ensure_formats`；改表走 SCI xlsx / 外科修复。",
  "4. 更新本报告总评为 PASS/WARN/FAIL，并写：",
  paste0("   - `reports/nature_statistics_qc_", .day, ".md`"),
  paste0("   - `reports/nature_figure_qc_", .day, ".md`"),
  "",
  "## 附录 — Figure PDF 清单",
  if (length(.pdfs)) paste0("- ", .pdfs) else "- （无）",
  "",
  "## 附录 — Tables xlsx 清单",
  if (length(.xlsx)) paste0("- ", .xlsx) else "- （无）",
  ""
)
.out <- file.path(.rep, paste0("pub_qc_", .day, ".md"))
writeLines(.lines, .out)
.message("wrote ", .out, " verdict=", .verdict)

# touch nature stubs if missing（Agent 填实）
.ns <- file.path(.rep, paste0("nature_statistics_qc_", .day, ".md"))
.nf <- file.path(.rep, paste0("nature_figure_qc_", .day, ".md"))
if (!file.exists(.ns)) {
  writeLines(c(
    "# Nature statistics QC",
    paste0("- 项目：", .proj),
    paste0("- 日期：", .day),
    "- 状态：AUTO_STUB — Agent 须按 nature-statistics skill 填实并标 P0/P1/P2",
    "",
    "## Major statistical issues",
    "- （待审）",
    ""
  ), .ns)
}
if (!file.exists(.nf)) {
  writeLines(c(
    "# Nature figure QC",
    paste0("- 项目：", .proj),
    paste0("- 日期：", .day),
    "- 状态：AUTO_STUB — Agent 须按 nature-figure skill 填实；FIX BEFORE DELIVERY = P0",
    "",
    "## Issues",
    "- （待审）",
    ""
  ), .nf)
}

# optional inventory script
.inv <- file.path(.root, "scripts/pub_qc_inventory.py")
if (file.exists(.inv)) {
  try(system2("python3", c(.inv, "--root", .proj, "--success-only"),
              stdout = file.path(.rep, paste0("pub_qc_", .day, "_inventory.txt")),
              stderr = FALSE), silent = TRUE)
}

invisible(.verdict)
