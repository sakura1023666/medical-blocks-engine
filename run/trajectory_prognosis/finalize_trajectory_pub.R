#!/usr/bin/env Rscript
# 轨迹预后双库发表收口（引擎 API，全项目复用）
#
#   Rscript run/trajectory_prognosis/finalize_trajectory_pub.R \
#     --index-root /path/to/by_index/【success】INDEX \
#     --config /path/to/study/config.R \
#     [--index GPR]
#
# 等价于调用 trajectory_batch_finalize_index_outputs()。
# 勿再为单课题新建 repair_* 脚本堆 hotfix。

args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
.index_root <- .get("--index-root")
.config <- .get("--config")
.index <- .get("--index")

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
if (is.null(.index_root) || !dir.exists(.index_root))
  stop("需要 --index-root <by_index/【success】INDEX>", call. = FALSE)
if (is.null(.config) || !file.exists(.config))
  stop("需要 --config <study config.R>", call. = FALSE)

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/trajectory_dual_pub_harmonize.R"))
source(file.path(.root, "R/trajectory_pub_finalize.R"))
source(.config)
if (is.null(config$project$root) || !nzchar(config$project$root))
  config$project$root <- .root

ix <- .index %||% gsub("^【success】|^【failed】", "", basename(.index_root))
trajectory_batch_finalize_index_outputs(
  index_root = .index_root,
  config = config,
  index_name = ix
)
cli::cli_alert_success("finalize 完成: {(.index_root)}")
