#!/usr/bin/env Rscript
# 预后 2.0 三库并行入口。旧 run/survival/ 不改。
#
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/prognosis_v2/run_prognosis_v2_batch.R \
#     --config configs/config_prognosis_v2_sleep_dyslipid.R \
#     --workers 3
#   只跑一库: 加上 --only-unit SHHS

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
.parse_batch_args <- function(args) {
  opts <- list(config = NULL, workers = NULL, only_unit = NULL, skip_existing = TRUE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) { opts$config <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--workers" && i < length(args)) { opts$workers <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--only-unit" && i < length(args)) {
      opts$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--no-skip") { opts$skip_existing <- FALSE; i <- i + 1L
    } else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "prognosis_v2" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

opts <- .parse_batch_args(commandArgs(trailingOnly = TRUE))
config_path <- normalizePath(
  opts$config %||% file.path(root, "configs/config_prognosis_v2_sleep_dyslipid.R"),
  winslash = "/", mustWork = TRUE
)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)

rscript_bin <- "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
if (!file.exists(rscript_bin)) rscript_bin <- study_rscript_bin()
workers <- opts$workers %||% config$study_batch$parallel_workers %||% 3L
if (identical(tolower(as.character(workers)), "auto")) workers <- 3L

.win_path <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (grepl("^/mnt/[A-Za-z]/", p)) {
    paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8))
  } else p
}

message("预后2.0 并行库: ", paste(config$study_batch$units, collapse = ", "))
message("Rscript: ", rscript_bin)
message("旧预后流水线 run/survival 不在本次调用里。")

units <- config$study_batch$units
if (length(opts$only_unit)) units <- intersect(units, opts$only_unit)
win_root <- .win_path(root)
win_cfg <- .win_path(config_path)
win_worker <- .win_path(file.path(root, config$study_batch$worker_script))
workers <- max(1L, as.integer(workers))
if (!requireNamespace("processx", quietly = TRUE)) stop("需要 processx 才能并行派发", call. = FALSE)

output_base <- config$study_batch$output_base
log_dir <- file.path(output_base, "logs")
if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

.status_ok <- function(unit) {
  p <- study_batch_status_path(output_base, unit)
  if (!file.exists(p)) return(FALSE)
  st <- tryCatch(jsonlite::fromJSON(p), error = function(e) NULL)
  identical(st$status, "success")
}

active <- list()
for (unit in units) {
  if (opts$skip_existing && .status_ok(unit)) {
    message("跳过 ", unit)
    next
  }
  while (length(active) >= workers) {
    Sys.sleep(5)
    active <- Filter(function(p) p$is_alive(), active)
  }
  log_path <- file.path(log_dir, paste0(unit, ".log"))
  proc <- processx::process$new(
    rscript_bin,
    c(win_worker, "--unit", unit, "--config", win_cfg, win_root),
    stdout = log_path, stderr = log_path, cleanup = FALSE
  )
  message("启动 ", unit, " → ", log_path)
  active[[length(active) + 1L]] <- proc
}
while (length(active)) {
  Sys.sleep(5)
  active <- Filter(function(p) p$is_alive(), active)
}
message("预后2.0 派发结束。状态见 ", output_base, "/by_unit/")
