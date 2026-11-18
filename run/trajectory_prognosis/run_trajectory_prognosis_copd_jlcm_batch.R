#!/usr/bin/env Rscript
# =============================================================================
#  COPD 复合指标轨迹预后 batch（MIMIC 发现 → eICU 外验 + PAMM）
#
#  先准备数据:
#    "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#      run/trajectory_prognosis/prepare_copd_trajectory_data.R
#
#  再跑:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_copd_jlcm_batch.R --shared-only
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_copd_jlcm_batch.R --workers 4
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
    } else i <- i + 1L
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
  run_opts$config %||% file.path(root, "configs/templates/config_trajectory_prognosis_copd_jlcm_batch.template.R"),
  winslash = "/", mustWork = TRUE
)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/rscript_study.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- file.path(dirname(config_path))
# 课题 extensions 放在产出根；Win R 勿用 /mnt/g
.ext_dir <- config$project$output_dir %||% .study_dir
if (!file.exists(file.path(.ext_dir, "extensions.json"))) {
  # 优先课题产出根 G:；勿误用 configs/templates 旁残留
  alt <- c(
    "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177/extensions.json",
    file.path(.study_dir, "extensions.json")
  )
  hit <- alt[file.exists(alt)]
  if (length(hit)) {
    .ext_dir <- dirname(hit[[1L]])
    cli::cli_alert_warning("extensions.json 改用: {(.ext_dir)}")
  }
}
cli::cli_alert_info(
  "extension guard study_dir={(.ext_dir)}; exists={file.exists(file.path(.ext_dir, 'extensions.json'))}"
)
pipeline_extension_guard_check(
  routine = "trajectory",
  pipelines = list(
    pipeline_shared = if (exists("pipeline_shared")) pipeline_shared else NULL,
    pipeline_unit_prefix = if (exists("pipeline_unit_prefix")) pipeline_unit_prefix else NULL,
    pipeline_unit_suffix = if (exists("pipeline_unit_suffix_discovery")) pipeline_unit_suffix_discovery else pipeline_unit_suffix
  ),
  study_dir = .ext_dir,
  root = root
)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

tb <- config$trajectory_batch %||% list()
db_seq <- as.character(tb$db_seq %||% c("mimic", "eicu"))
index_vars <- trajectory_batch_resolve_index_vars(config)
cli::cli_alert_info("COPD JLCM/PAMM 批量：{length(index_vars)} 个指标；db_seq={paste(db_seq, collapse=',')}")

cli::cli_h1("共享层")
for (db in db_seq) {
  trajectory_batch_run_shared_layer(root, config, db, pipeline_shared, skip_existing = run_opts$skip_existing)
}

if (isTRUE(run_opts$shared_only)) {
  cli::cli_alert_success("--shared-only 完成")
  quit(save = "no", status = 0)
}

cli::cli_h1("按指标并行派发")
trajectory_batch_dispatch_workers(
  root, config, index_vars,
  workers = run_opts$workers,
  only_index = run_opts$only_index,
  skip_existing = run_opts$skip_existing,
  config_path = config_path,
  worker_script = (config$trajectory_batch %||% list())$worker_script
)
cli::cli_alert_success("COPD trajectory batch 派发结束")
