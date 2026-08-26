#!/usr/bin/env Rscript
# =============================================================================
#  四套文献流水线并行 Batch 总入口
#    B14 复杂网络 | B10 共病贝叶斯 | B08 轨迹发病 | B07 轨迹预后
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

# 先生成 smoke 数据
system2(rscript, c(file.path(root, "scripts/create_smoke_four_literature_pipelines_data.R"), "100"))

pipelines <- list(
  list(name = "complex_network", script = "run/complex_network/run_complex_network_clhls_batch.R"),
  list(name = "bayesian_comorbidity", script = "run/bayesian_comorbidity/run_bayesian_comorbidity_batch.R"),
  list(name = "trajectory_incidence", script = "run/trajectory_incidence/run_trajectory_incidence_aki_batch.R"),
  list(name = "trajectory_prognosis", script = "run/trajectory_prognosis/run_trajectory_prognosis_plt_batch.R")
)

log_dir <- file.path(root, "Output", "_four_literature_batch_logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("processx", quietly = TRUE))
  utils::install.packages("processx", repos = "https://cloud.r-project.org", quiet = TRUE)

procs <- list()
for (pl in pipelines) {
  log_path <- file.path(log_dir, paste0(pl$name, ".log"))
  script   <- normalizePath(file.path(root, pl$script), winslash = "/", mustWork = TRUE)
  message(sprintf("启动 batch [%s] → %s", pl$name, basename(log_path)))
  procs[[pl$name]] <- processx::process$new(
    rscript, c(script, extra, root),
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
cat(sprintf("\n四套文献并行 Batch: 成功 %d / %d\n", ok, length(pipelines)))
if (ok < length(pipelines)) quit(save = "no", status = 1)
