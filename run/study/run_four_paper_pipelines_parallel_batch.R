#!/usr/bin/env Rscript
# =============================================================================
#  四套新文献流水线并行 Batch 总入口
#    B06 交叉滞后 | B22 竞争风险 | B24 AI临床 | B13 双库发病孟德尔
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

script_path <- .init_script_dir()
if (basename(script_path) == "study" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
workers <- "auto"
skip_existing <- TRUE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--workers" && i < length(args)) {
    workers <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--no-skip") {
    skip_existing <- FALSE; i <- i + 1L
  } else { i <- i + 1L }
}

source(file.path(root, "R/rscript_study.R"))
if (requireNamespace("cli", quietly = TRUE)) options(cli.hyperlink = FALSE)

rscript <- study_rscript_bin()
extra <- c("--workers", workers)
if (!skip_existing) extra <- c(extra, "--no-skip")
Sys.setenv(SMOKE_NO_FEISHU = "1")

system2(rscript, c(file.path(root, "scripts/create_smoke_four_paper_pipelines_data.R"), "100"))

pipelines <- list(
  list(
    name = "cross_lagged",
    script = "run/cross_lagged/run_cross_lagged_frailty.R",
    args = c("--batch")
  ),
  list(name = "competing_risk", script = "run/competing_risk/run_competing_risk_chf_batch.R"),
  list(name = "ai_clinical", script = "run/ai_clinical/run_ai_clinical_cdm_batch.R"),
  list(name = "dual_incidence_mr", script = "run/dual_incidence_mr/run_dual_incidence_mr_crm_batch.R")
)

log_dir <- file.path(root, "Output", "_four_paper_batch_logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("processx", quietly = TRUE))
  utils::install.packages("processx", repos = "https://cloud.r-project.org", quiet = TRUE)

procs <- list()
for (pl in pipelines) {
  log_path <- file.path(log_dir, paste0(pl$name, ".log"))
  script   <- normalizePath(file.path(root, pl$script), winslash = "/", mustWork = TRUE)
  pl_args  <- as.character(pl$args %||% character(0))
  message(sprintf("启动 batch [%s] → %s", pl$name, basename(log_path)))
  procs[[pl$name]] <- processx::process$new(
    rscript, c(script, pl_args, extra, root),
    stdout = log_path, stderr = log_path, wd = root, cleanup = FALSE
  )
}

results <- list()
for (nm in names(procs)) {
  procs[[nm]]$wait()
  exit <- as.integer(procs[[nm]]$get_exit_status() %||% 1L)
  results[[nm]] <- exit
  message(sprintf("%s: %s", nm, if (identical(exit, 0L)) "成功" else paste0("失败 exit=", exit)))
}

ok <- sum(vapply(results, function(x) identical(as.integer(x), 0L), logical(1L)))
cat(sprintf("\n四套新文献并行 Batch: 成功 %d / %d\n", ok, length(pipelines)))
if (ok < length(pipelines)) quit(save = "no", status = 1)
