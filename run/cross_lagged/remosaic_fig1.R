#!/usr/bin/env Rscript
# 交叉滞后主文 Figure 1：重画 xs-only 面板 + 拼图 + 四目录 600 dpi
#
# 用法：
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/cross_lagged/remosaic_fig1.R \
#     --study /mnt/g/02block_result/22_depression/cross-laged_40595747
#
# 禁止在结果目录另写 hotfix_remosaic_*.R。
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (is.null(a) || !length(a) || (length(a) == 1L && is.na(a))) b else a

get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
has_flag <- function(flag) flag %in% args

study <- get_opt("--study", Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = ""))
if (!nzchar(as.character(study %||% ""))) {
  stop("请传 --study <课题根> 或设 CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
}
study <- normalizePath(study, winslash = "/", mustWork = TRUE)

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", cmd_args[grepl("^--file=", cmd_args)][1L])
script_dir <- if (nzchar(file_arg %||% "")) {
  dirname(normalizePath(file_arg, winslash = "/", mustWork = TRUE))
} else {
  getwd()
}
root_cands <- unique(c(
  Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
  normalizePath(file.path(script_dir, "../.."), winslash = "/", mustWork = FALSE),
  getwd()
))
root_cands <- root_cands[nzchar(root_cands)]
root <- NULL
for (cand in root_cands) {
  if (dir.exists(file.path(cand, "R")) && file.exists(file.path(cand, "R/cross_lagged_fig1_pub.R"))) {
    root <- cand
    break
  }
}
if (is.null(root)) stop("找不到 MEDICAL_BLOCKS_ROOT（含 R/cross_lagged_fig1_pub.R）", call. = FALSE)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

source(file.path(root, "R/cross_lagged_fig1_pub.R"), local = FALSE)
redraw <- !has_flag("--no-redraw")
res <- cross_lagged_remosaic_fig1(study, redraw_xs = redraw)
message("Fig1 mosaic: ", res$out_pdf)
message("panels: ", paste(res$dbs, collapse = ", "))
