#!/usr/bin/env Rscript
# =============================================================================
#  轨迹预后 APRI 多指标批量入口 — configs/templates/config_trajectory_prognosis_batch.template.R
#
#  用法:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R --shared-only
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R --workers 4
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R --only-index APRI,NLR
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_batch_args <- function(args) {
  opts <- list(config = NULL, workers = "auto", shared_only = FALSE, only_index = NULL, skip_existing = TRUE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      w <- trimws(args[[i + 1L]])
      opts$workers <- if (tolower(w) == "auto") "auto" else as.integer(w)
      i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)
config_path <- normalizePath(
  run_opts$config %||% file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R"),
  winslash = "/", mustWork = TRUE
)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
pipeline_extension_guard_check(
  routine = "trajectory",
  pipelines = list(
    pipeline_shared = if (exists("pipeline_shared")) pipeline_shared else NULL,
    pipeline_unit_prefix = if (exists("pipeline_unit_prefix")) pipeline_unit_prefix else NULL,
    pipeline_unit_suffix = if (exists("pipeline_unit_suffix")) pipeline_unit_suffix else NULL
  ),
  study_dir = .study_dir,
  root = root
)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

tb <- config$trajectory_batch %||% list()
db_seq <- as.character(tb$db_seq %||% c("eicu", "mimic"))
index_vars <- trajectory_batch_resolve_index_vars(config)
cli::cli_alert_info("指标批量：{length(index_vars)} 个（index_group={tb$index_group %||% 'dual_safe'}）")

cli::cli_h1("轨迹预后 APRI 批量 — 共享层（{paste(toupper(db_seq), collapse=' / ')}）")
log_dir <- file.path(config$project$output_dir, "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
for (db in db_seq) {
  trajectory_batch_run_shared_layer(root, config, db, pipeline_shared, skip_existing = run_opts$skip_existing)
}

if (isTRUE(run_opts$shared_only)) {
  cli::cli_alert_success("--shared-only：共享层完成，未派发指标 worker。")
  quit(save = "no", status = 0)
}

cli::cli_h1("轨迹预后 APRI 批量 — 按指标并行派发（{length(index_vars)} 个指标）")
trajectory_batch_dispatch_workers(
  root, config, index_vars,
  workers = run_opts$workers,
  only_index = run_opts$only_index,
  skip_existing = run_opts$skip_existing,
  config_path = config_path
)

cli::cli_alert_success("轨迹预后 APRI 批量完成。")
