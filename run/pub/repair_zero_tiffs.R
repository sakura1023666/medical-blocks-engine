#!/usr/bin/env Rscript
# =============================================================================
#  零字节 TIFF 批量修复（SMB/WSL 直写 0B 坑的全项目 CLI）
#
#  用法（任意目录均可）:
#    Rscript run/pub/repair_zero_tiffs.R --dir ".../by_index/【success】TyG_WWI/Figures"
#    Rscript run/pub/repair_zero_tiffs.R --root "/mnt/g/02block_result" [--dry-run]
#
#  行为:
#    扫描目标（或 root 下所有 */Figures 四目录），对 tiff/ 中缺失或 <=800B 的
#    *.tiff，用同名 png/ 图走 PIL 重导 LZW TIFF（引擎
#    R/pub_figure_export.R → pub_figure_ensure_tiff_from_png /
#    pub_figure_repair_zero_tiffs）。幂等：合格文件不动。
# =============================================================================

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[[1L]])
    return(normalizePath(file.path(dirname(fp), "..", ".."), winslash = "/", mustWork = FALSE))
  }
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(eng)) return(normalizePath(eng, winslash = "/", mustWork = FALSE))
  normalizePath(getwd(), winslash = "/")
}

.args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag) {
  i <- match(flag, .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else NULL
}
dry_run <- "--dry-run" %in% .args
root <- get_opt("--root")
one_dir <- get_opt("--dir")

ENGINE <- .init_root()
source(file.path(ENGINE, "R", "pub_figure_export.R"))

# 收集 Figures 目录
fig_dirs <- character(0)
if (!is.null(one_dir)) {
  fig_dirs <- normalizePath(one_dir, winslash = "/", mustWork = FALSE)
} else if (!is.null(root)) {
  cand <- Sys.glob(file.path(root, "*", "*", "*", "*", "Figures"))
  cand2 <- Sys.glob(file.path(root, "**", "Figures"))
  fig_dirs <- unique(c(cand, cand2))
  fig_dirs <- fig_dirs[file.exists(file.path(fig_dirs, "tiff"))]
} else {
  stop("需要 --dir <Figures目录> 或 --root <扫描根>", call. = FALSE)
}

n_fix <- 0L
n_fail <- 0L
for (d in fig_dirs) {
  if (!dir.exists(d)) next
  if (!dir.exists(file.path(d, "tiff")) || !dir.exists(file.path(d, "pdf"))) next
  tfs <- list.files(file.path(d, "tiff"), pattern = "\\.tiff$",
                    ignore.case = TRUE, full.names = TRUE)
  pdfs <- list.files(file.path(d, "pdf"), pattern = "^Figure.*\\.pdf$",
                     ignore.case = TRUE)
  stems <- sub("\\.pdf$", "", pdfs, ignore.case = TRUE)
  # 缺失 + 0 字节都算坏
  bad <- character(0)
  for (st in stems) {
    tp <- file.path(d, "tiff", paste0(st, ".tiff"))
    if (!file.exists(tp) || isTRUE(file.info(tp)$size <= 800L)) bad <- c(bad, tp)
  }
  for (tp in bad) {
    stem <- sub("\\.tiff$", "", basename(tp), ignore.case = TRUE)
    pp <- file.path(d, "png", paste0(stem, ".png"))
    if (dry_run) {
      cat("[dry-run]", tp, if (file.exists(pp)) "(png ok)" else "(缺 png)", "\n")
      next
    }
    if (pub_figure_ensure_tiff_from_png(pp, tp)) {
      cat("fixed:", tp, "\n"); n_fix <- n_fix + 1L
    } else {
      cat("FAILED:", tp, "\n"); n_fail <- n_fail + 1L
    }
  }
}
cat(sprintf("done: fixed=%d failed=%d\n", n_fix, n_fail))
if (n_fail > 0L) quit(status = 1L)
