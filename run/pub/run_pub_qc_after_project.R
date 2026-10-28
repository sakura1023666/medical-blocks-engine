#!/usr/bin/env Rscript
# 发表结构 QC CLI（全项目复用）
#   Rscript run/pub/run_pub_qc_after_project.R --project <课题根>
# 检查：Figures 四目录 + png/tiff 嵌入 DPI ≥ 600；写出 reports/pub_qc_*.md 与 nature stub。

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

proj <- .arg("--project", NULL)
if (is.null(proj) || !nzchar(proj)) {
  stop("用法: Rscript run/pub/run_pub_qc_after_project.R --project <project_root>", call. = FALSE)
}
if (!dir.exists(proj)) {
  # WSL / Windows 路径互备
  alt <- sub("^G:/", "/mnt/g/", proj, ignore.case = TRUE)
  alt <- sub("^E:/", "/mnt/e/", alt, ignore.case = TRUE)
  if (dir.exists(alt)) proj <- alt
}
stopifnot(dir.exists(proj))

engine <- {
  cands <- c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", ""),
    Sys.getenv("BLOCK_REPO_ROOT", ""),
    "E:/01block/01Block-new-Final",
    "/mnt/e/01block/01Block-new-Final"
  )
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  if (!length(hit)) stop("找不到引擎根 MEDICAL_BLOCKS_ROOT", call. = FALSE)
  hit[[1L]]
}

Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
if (!nzchar(Sys.getenv("MEDICAL_BLOCKS_PYTHON", ""))) {
  if (file.exists("/usr/bin/python3")) Sys.setenv(MEDICAL_BLOCKS_PYTHON = "/usr/bin/python3")
}

source(file.path(engine, "R/utils.R"), local = TRUE)
source(file.path(engine, "R/pub_figure_export.R"), local = TRUE)
source(file.path(engine, "R/pub_qc_after_finalize.R"), local = TRUE)

res <- pub_qc_run_after_project(proj, force = TRUE)
if (isFALSE(res$ok)) quit(status = 1L)
invisible(res)
