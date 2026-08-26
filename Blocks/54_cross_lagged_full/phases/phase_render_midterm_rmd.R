#!/usr/bin/env Rscript
# 根据 summary_result 生成中期 PDF 报告（rmarkdown/pandoc 版；老师交付优先用 xelatex 版）
# 入口：Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase midterm_rmd
options(warn = 1)

.ca <- commandArgs(trailingOnly = FALSE)
.file_hits <- grep("^--file=", .ca, value = TRUE)
.file <- if (length(.file_hits)) sub("^--file=", "", .file_hits[1L]) else ""
.script_dir <- if (nzchar(.file)) {
  normalizePath(dirname(.file), winslash = "/", mustWork = FALSE)
} else {
  normalizePath(getwd(), winslash = "/")
}
root <- if (basename(.script_dir) == "phases" &&
           grepl("54_cross_lagged", basename(dirname(.script_dir)), fixed = TRUE)) {
  normalizePath(file.path(.script_dir, "..", "..", ".."), winslash = "/")
} else if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", ""))) {
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT"), winslash = "/")
} else {
  "/mnt/e/01block/01Block-new-Final"
}
if (!dir.exists(root)) root <- "/mnt/e/01block/01Block-new-Final"
setwd(root)

rmd <- file.path(root, "Blocks/54_cross_lagged_full/phases/make_midterm_report.Rmd")
if (!file.exists(rmd)) stop("缺少 Rmd: ", rmd, call. = FALSE)

sys_g <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/summary_result"
sys_e <- file.path(root, "Output/16_Hip_fracture_cross-laged_40595747_allages/summary_result")
SR <- if (dir.exists(file.path(sys_g, "figure"))) sys_g else sys_e
Sys.setenv(CROSS_LAGGED_SUMMARY_ROOT = SR)

out_dir_e <- file.path(root, "Output/16_Hip_fracture_cross-laged_40595747_allages/summary_result")
out_dir_g <- sys_g
dir.create(out_dir_e, recursive = TRUE, showWarnings = FALSE)

out_pdf <- file.path(
  out_dir_e,
  "中期报告_虚弱指数与髋部骨折_三队列交叉滞后分析.pdf"
)

tmpdir <- tempfile("midterm_")
dir.create(tmpdir)
file.copy(rmd, file.path(tmpdir, "make_midterm_report.Rmd"))

message("summary_result = ", SR)
message("output = ", out_pdf)

ok <- tryCatch({
  rmarkdown::render(
    input = file.path(tmpdir, "make_midterm_report.Rmd"),
    output_file = basename(out_pdf),
    output_dir = tmpdir,
    envir = new.env(parent = globalenv()),
    quiet = FALSE
  )
  TRUE
}, error = function(e) {
  message("RENDER ERROR: ", conditionMessage(e))
  FALSE
})

src <- file.path(tmpdir, basename(out_pdf))
if (isTRUE(ok) && file.exists(src)) {
  file.copy(src, out_pdf, overwrite = TRUE)
  if (dir.exists(dirname(out_dir_g))) {
    dir.create(out_dir_g, recursive = TRUE, showWarnings = FALSE)
    file.copy(src, file.path(out_dir_g, basename(out_pdf)), overwrite = TRUE)
  }
  message("OK: ", out_pdf)
  message("size: ", file.info(out_pdf)$size)
} else {
  logs <- list.files(tmpdir, full.names = TRUE)
  message("failed; tmp files: ", paste(basename(logs), collapse = ", "))
  quit(status = 1)
}
