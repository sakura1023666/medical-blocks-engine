#!/usr/bin/env Rscript
# =============================================================================
#  四套文献流水线并行 Batch 总入口
#
#  同时启动四套 batch（各 batch 内部再并行 worker）:
#    B08 环境毒物  | B12 动态因果 | B09 多病叠加 | B23 多模态
#
#  用法:
#    Rscript run/study/run_four_studies_parallel_batch.R
#    Rscript run/study/run_four_studies_parallel_batch.R --workers 2
#    Rscript run/study/run_four_studies_parallel_batch.R --no-skip
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
if (requireNamespace("cli", quietly = TRUE)) {
  options(cli.hyperlink = FALSE)
} else {
  cli <- list(
    cli_alert_success = function(...) cat(paste0(..., "\n")),
    cli_alert_danger = function(...) cat(paste0(..., "\n")),
    cli_h2 = function(...) cat(paste0("\n", ..., "\n"))
  )
}
rscript <- study_rscript_bin()

pipelines <- list(
  list(name = "environment_cd", script = "run/environment/run_environment_cd_osteo_batch.R"),
  list(name = "dynamic_causal", script = "run/dynamic_causal/run_dynamic_causal_dual_batch.R"),
  list(name = "multimorbidity", script = "run/multimorbidity/run_multimorbidity_additive_batch.R"),
  list(name = "multimodal",     script = "run/multimodal/run_multimodal_tbi_batch.R")
)

log_dir <- file.path(root, "Output", "_four_studies_batch_logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

extra <- c("--workers", workers)
if (!skip_existing) extra <- c(extra, "--no-skip")
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) {
  Sys.setenv(SMOKE_NO_FEISHU = "1")
}

if (!requireNamespace("processx", quietly = TRUE)) {
  utils::install.packages("processx", repos = "https://cloud.r-project.org", quiet = TRUE)
}

procs <- list()
for (pl in pipelines) {
  pl_name  <- pl$name
  log_path <- file.path(log_dir, paste0(pl_name, ".log"))
  script   <- normalizePath(file.path(root, pl$script), winslash = "/", mustWork = TRUE)
  message(sprintf("启动 batch [%s] → %s", pl_name, basename(log_path)))
  procs[[pl_name]] <- processx::process$new(
    rscript,
    c(script, extra, root),
    stdout = log_path,
    stderr = log_path,
    wd = root,
    cleanup = FALSE
  )
}

cli::cli_h2("等待四套 batch 完成…")
results <- list()
for (nm in names(procs)) {
  procs[[nm]]$wait()
  exit <- as.integer(procs[[nm]]$get_exit_status() %||% 1L)
  results[[nm]] <- exit
  if (identical(exit, 0L)) {
    message(sprintf("%s: 成功", nm))
  } else {
    message(sprintf("%s: 失败 (exit=%s)，见 %s", nm, exit, file.path(log_dir, paste0(nm, ".log"))))
  }
}

ok <- sum(vapply(results, function(x) identical(as.integer(x), 0L), logical(1L)))
cat("\n── 四套并行 Batch 汇总 ──\n")
cat(sprintf("成功 %d / %d\n", ok, length(pipelines)))
if (ok < length(pipelines)) quit(save = "no", status = 1)
