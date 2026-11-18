#!/usr/bin/env Rscript
# IPW 阿替普酶 × 肺栓塞双库批量 — configs/templates/config_ipw_pe_alteplase_dual_batch.template.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
.parse_batch_args <- function(args) {
  opts <- list(
    config = NULL, workers = NULL, shared_only = FALSE,
    only_unit = NULL, skip_existing = TRUE, dry_run = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      opts$workers <- if (tolower(trimws(args[[i + 1L]])) == "auto") "auto" else as.integer(args[[i + 1L]])
      i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-unit" && i < length(args)) {
      opts$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--dry-run") {
      opts$dry_run <- TRUE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "ipw_pe_alteplase" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)
config_path <- normalizePath(
  run_opts$config %||% file.path(root, "configs/templates/config_ipw_pe_alteplase_dual_batch.template.R"),
  winslash = "/", mustWork = TRUE
)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/rscript_study.R"))
source(config_path)

if (!exists("pipeline_shared") || !exists("pipeline_unit") || !exists("config")) {
  stop("config 未导出 pipeline_shared / pipeline_unit / config", call. = FALSE)
}

if (isTRUE(run_opts$dry_run)) {
  cat("=== IPW PE×Alteplase dry-run ===\n")
  cat("config:", config_path, "\n")
  cat("project:", config$project$name %||% "", "| disease:", config$project$disease %||% "",
      "| database:", config$project$database %||% "", "\n")
  cat("rawdata:", config$data$rawdata_path %||% "",
      "| exists=", file.exists(as.character(config$data$rawdata_path %||% "")), "\n")
  cat("exposure block in unit:",
      "ipw_alteplase_exposure" %in% as.character(pipeline_unit$blocks %||% character(0)), "\n")
  cat("iptw exposure_var:", config$iptw_balance$exposure_var %||% "", "\n")
  cat("\npipeline_shared$blocks:\n")
  print(as.character(pipeline_shared$blocks %||% character(0)))
  cat("\npipeline_unit$blocks:\n")
  print(as.character(pipeline_unit$blocks %||% character(0)))
  cat("\nOK: source(config) + exists(pipeline_unit)=TRUE; dry-run exit 0\n")
  quit(save = "no", status = 0)
}

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
run_opts$workers <- run_opts$workers %||% (config$study_batch$parallel_workers %||% "auto")
options(cli.hyperlink = FALSE, warn = 1)

run_study_batch(root, config, pipeline_shared, pipeline_unit = pipeline_unit,
                run_opts = run_opts, config_path = config_path)
