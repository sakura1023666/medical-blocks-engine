#!/usr/bin/env Rscript
# 兼容薄封装 → run/pub/finalize_delivery_root.R --prune-only
# 新课题请直接用 finalize_delivery_root.R（完整收口）或带 --prune-only。
#
#   Rscript run/pub/prune_delivery_root.R --dir ".../summary_result"
#   Rscript run/pub/prune_delivery_root.R --project ".../课题根"

args <- commandArgs(trailingOnly = TRUE)
ca <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", ca[grep("^--file=", ca)])
here <- if (length(f)) dirname(normalizePath(f[[1]], winslash = "/")) else getwd()
target <- file.path(here, "finalize_delivery_root.R")
if (!file.exists(target)) {
  target <- file.path(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final"),
    "run", "pub", "finalize_delivery_root.R"
  )
}
if (!"--prune-only" %in% args) args <- c(args, "--prune-only")
status <- system2(
  command = "Rscript",
  args = c(target, args),
  stdout = "",
  stderr = ""
)
quit(save = "no", status = if (is.numeric(status)) as.integer(status) else 1L)
