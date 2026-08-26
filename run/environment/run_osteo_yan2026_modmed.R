#!/usr/bin/env Rscript
# OA Yan2026 中介/调节复现
# Rscript: "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
#   run/environment/run_osteo_yan2026_modmed.R
#   MODMED_SIMS=50 run/...  # 冒烟

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

script_path <- .init_script_dir()
if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- normalizePath(
  file.path(root, "configs/config_osteo_yan2026_modmed.R"),
  winslash = "/", mustWork = TRUE
)
sims_cli <- NA_integer_
smoke_cli <- FALSE
i <- 1L
while (i <= length(args)) {
  if (identical(args[[i]], "--config") && i < length(args)) {
    config_path <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
    i <- i + 2L
  } else if (identical(args[[i]], "--sims") && i < length(args)) {
    sims_cli <- as.integer(args[[i + 1L]])
    i <- i + 2L
  } else if (identical(args[[i]], "--smoke")) {
    smoke_cli <- TRUE
    i <- i + 1L
  } else {
    stop("未知参数: ", args[[i]], call. = FALSE)
  }
}

if (isTRUE(smoke_cli)) Sys.setenv(MODMED_SMOKE = "1")
if (is.finite(sims_cli)) Sys.setenv(MODMED_SIMS = as.character(sims_cli))

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)
options(cli.hyperlink = FALSE, warn = 1)

out <- config$project$output_dir
for (d in c(out, file.path(out, "Tables"), file.path(out, "Figures"),
            file.path(out, "checkpoints"), file.path(out, "logs"))) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

cli::cli_h1("OA Yan2026 moderated mediation")
cli::cli_alert_info("config: {.file {config_path}}")
cli::cli_alert_info("output: {.file {out}}")
cli::cli_alert_info("MODMED_SMOKE={Sys.getenv('MODMED_SMOKE', unset = '0')}")
cli::cli_alert_info("MODMED_SIMS={Sys.getenv('MODMED_SIMS', unset = '(config default)')}")

# 确保各 block 能定位仓库根（Windows Rscript 下 env 跨进程不可靠）
config$project$repo_root <- root

run_pipeline(root, config = config, pipeline = pipeline)
