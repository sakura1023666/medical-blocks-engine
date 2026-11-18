#!/usr/bin/env Rscript
# 数据库池化 batch 总入口（预后地基 + BlendedLoS）
#
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/database_pooling/run_database_pooling_batch.R
#   Rscript run/database_pooling/run_database_pooling_batch.R --shared-only
#   Rscript run/database_pooling/run_database_pooling_batch.R --workers 4
#   Rscript run/database_pooling/run_database_pooling_batch.R --only-unit expD_pooled_mimic_amumc,model_benchmark
#   Rscript run/database_pooling/run_database_pooling_batch.R --list-units
#   Rscript run/database_pooling/run_database_pooling_batch.R --dry-run

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(
    config = NULL, workers = 1L, shared_only = FALSE, only_unit = NULL,
    list_units = FALSE, skip_existing = TRUE, dry_run = FALSE
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
    } else if (a == "--list-units") {
      opts$list_units <- TRUE; i <- i + 1L
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
if (basename(script_path) == "database_pooling" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_args(args)
.config_default <- file.path(root, "configs/templates/config_database_pooling_batch.template.R")
config_path <- normalizePath(run_opts$config %||% .config_default, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); try(feishu_load_dotenv(root), silent = TRUE)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dbpool_task_runner.R"))
source(config_path)

if (isTRUE(run_opts$dry_run)) config$dbpool$dry_run <- TRUE
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
if (nzchar(as.character(config$feishu$app_token %||% "")[1L])) {
  Sys.setenv(FEISHU_BITABLE_APP_TOKEN = config$feishu$app_token)
}
options(cli.hyperlink = FALSE, warn = 1)

units <- config$task_units %||% dbpool_default_units()
if (length(run_opts$only_unit)) units <- run_opts$only_unit

if (isTRUE(run_opts$list_units)) {
  cat(paste(units, collapse = "\n"), "\n")
  cat("# units:", length(units), "\n")
  quit(save = "no", status = 0)
}

workers <- run_opts$workers %||% 1L
out <- dbpool_run_task_parallel(
  root = root,
  config = config,
  units = units,
  workers = workers,
  shared_only = isTRUE(run_opts$shared_only),
  skip_existing = isTRUE(run_opts$skip_existing)
)
cli::cli_alert_success("database_pooling batch done: {out}")
