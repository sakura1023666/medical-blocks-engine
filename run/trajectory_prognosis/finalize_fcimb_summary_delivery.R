#!/usr/bin/env Rscript
# 轨迹预后 fcimb summary_results 交付收口（引擎级，全项目复用）
#
#   Rscript run/trajectory_prognosis/finalize_fcimb_summary_delivery.R \
#     --dir ".../by_index/【success】WPR/summary_results" \
#     --index WPR --client 天涯 --no-date --ng 4
#
#   # 只要 scrub/Methods/软件版本，不出中期：
#   Rscript … --dir … --skip-midterm
#
# 勿在课题 scripts/ 再堆 hotfix；改逻辑只改 R/trajectory_fcimb_delivery_finalize.R

args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  # 拼到下一个 --flag（客户名等可含空格）
  parts <- character(0)
  j <- i + 1L
  while (j <= length(args) && !grepl("^--", args[[j]])) {
    parts <- c(parts, args[[j]])
    j <- j + 1L
  }
  if (!length(parts)) return(default)
  paste(parts, collapse = " ")
}
.has <- function(flag) flag %in% args

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = .root)

.dir <- .get("--dir")
.index <- .get("--index", "WPR")
.client <- .get("--client", "天涯")
.ng <- as.integer(.get("--ng", "4"))
.no_date <- .has("--no-date") || isTRUE(as.logical(.get("--no-date", "TRUE")))
.skip_mid <- .has("--skip-midterm")

if (is.null(.dir) || !dir.exists(.dir)) {
  stop("需要 --dir <summary_results 绝对路径>", call. = FALSE)
}

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_fcimb_delivery_finalize.R"), local = FALSE)

res <- trajectory_fcimb_finalize_summary_delivery(
  summary_root = .dir,
  index_lab = .index,
  ng = .ng,
  client = .client,
  no_date = .no_date,
  write_midterm = !.skip_mid,
  root = .root
)
cat("FCIMB_DELIVERY_OK dir=", res$summary_root, "\n", sep = "")
if (!is.null(res$midterm$pdf) && !is.na(res$midterm$pdf)) {
  cat("MIDTERM_PDF=", res$midterm$pdf, "\n", sep = "")
}
