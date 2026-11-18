#!/usr/bin/env Rscript
# 预后 v2 发表 P0 机器门控 CLI
# 用法：
#   Rscript run/prognosis_v2/run_pv2_pub_p0_gate.R --dir <summary_results> [--scheme binary] [--contrast "High vs Low"]
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (is.null(a)) b else a

.get <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

.root <- .get("--dir", .get("-d", NA_character_))
if (is.na(.root) || !nzchar(.root)) {
  stop("Usage: Rscript run/prognosis_v2/run_pv2_pub_p0_gate.R --dir <summary_results> [--scheme binary]")
}
.scheme <- .get("--scheme", "binary")
.contrast <- .get("--contrast", NULL)

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.engine)) {
  for (cand in c(getwd(), "/mnt/e/01block/01Block-new-Final", "E:/01block/01Block-new-Final")) {
    if (file.exists(file.path(cand, "R/pv2_pub_p0_gate.R"))) {
      .engine <- cand
      break
    }
  }
}
source(file.path(.engine, "R/pv2_pub_p0_gate.R"), local = FALSE)
pv2_pub_p0_gate(
  summary_root = .root,
  locked_scheme = .scheme,
  contrast_lab = .contrast,
  stop_on_fail = TRUE
)
